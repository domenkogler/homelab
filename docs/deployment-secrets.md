---
title: Secrets Management & Passwordless Philosophy
role: detail
domain: deployment
status: active
tags: [deployment, secrets, 1password]
---
# Secrets Management & Passwordless Philosophy

> **Role:** Detail — 1Password as sole secrets backend, self-documenting philosophy, passwordless-first design.
> **Links to:** `services-authentik.md`, `backup.md`, `manual/README.md`
> **Linked from:** `deployment.md`, `deployment-ansible.md`, `deployment-compose.md`, `index.md`

---

## Self-Documenting Homelab Philosophy

- **Single Git repo is source of truth** — `git clone` + `ansible-playbook` = fully rebuilt infrastructure
- **Secrets never touch the repo** — all credentials live exclusively in 1Password
- **Documentation drives automation** — these `docs/*.md` files are read by AI to generate IaC configs
- ⚠ **Rotation caveat (Wave-3 R5, 2026-08-22):** updating a 1Password item does NOT update already-initialized service state — re-render + redeploy applies it only where the service reads env/config at start. Known one-time seeds: `POSTGRES_PASSWORD` initializes a volume ONCE (later rotation needs `ALTER USER` inside the container); `AUTHENTIK_BOOTSTRAP_*` applies only at user creation. Both hit live during Phase 1 (akadmin identity, forgejo-db role) and were synced manually via sanctioned tooling.
- **No tribal knowledge** — if Domen is incapacitated, family + trusted tech contact can recover from 1Password + repo

### Config vs credential split (decision 2026-08-19 — why there is NO `server` type)

1Password holds **credentials only**. Connection *configuration* (which host, which user, which port)
lives in the **Git IaC** so `git clone` → `ansible-playbook` can fully rebuild and a recoverer finds
host facts in the repo. This split is deliberate and **intentionally uses no `server`-type secret**
(an item bundling host + user + key + port).

| Connection fact | Where it lives | Why |
|-----------------|----------------|-----|
| hostname / IP / port | `host_vars/*.yml` (`ansible_host`), `group_vars/all/main.yml` (`kopia_sftp_*`, …) | **config**, not secret — part of the repo's self-rebuild + recovery premise; moving it to 1P would break the `git clone → rebuild` and the provisioning bootstrap (which needs host facts before 1P is available) |
| login (`ansible_user`, `kopia_sftp_user`) | `host_vars` / `group_vars` (inventory) | the login alone grants nothing; the **key** does. Kept in IaC so inventory is complete |
| **key / credential** | 1Password `_ssh` items via the **1Password SSH agent**, or connection-refs (`Hertzner-SB-Backup`) for kopia SFTP | this is the actual secret — never on disk, never in Git |

**Why not a `server` type:** none of the repo's consumers need a full bundle from a single
`lookup()` — Ansible reads host/login from inventory (parse-time, not 1P), and keys come from
the SSH agent / connection refs. A `server` item would (a) duplicate the IaC host/user SSOT
(second source of truth — `CONVENTIONS.md`), (b) weaken the recovery/bootstrap premise by hiding
host facts in 1P, and (c) match nothing that consumes it. The kopia SFTP case already demonstrates
the split: `kopia_sftp_host/user/port` in `group_vars` + `Hertzner-SB-Backup` key-ref in 1P.

**Exception:** genuinely credential-like, ops-only connection facts that are deliberately kept OFF
the automation path (e.g. `netcup-vps_login` root + IP in the **Homelab (human)** vault) stay in 1Password —
that is a break-glass decision, not a connection-config item.

### Vault taxonomy — the two-vault model (confirmed 2026-08-22)

| Vault | Role | Access |
|-------|------|--------|
| **`Homelab-ansible`** | Automation vault — holds EVERY secret the IaC consumes (`*_api` / `*_password` / `*_db` items, SSH keys). The only vault that Ansible `lookup()`, the service-account token(s) and `provision-secrets.py` touch. | `Homelab-ansible` service account(s) + owner |
| **Homelab (human)** | Break-glass vault — human-only credentials deliberately OFF the automation path (`netcup-ccp_login`, `netcup-scp_login`, `netcup-vps_login`, …). | owner only — **no service account has access** |

Rule of thumb: if Ansible must read it, it lives in `Homelab-ansible`; if it exists only for a human at a
provider console or for console break-glass, it lives in **Homelab (human)**. The split is the blast-radius
boundary — a leaked automation token never exposes break-glass credentials.

---

## 1Password as Sole Secrets Backend

| Principle | Implementation |
|-----------|---------------|
| **One vault** | All secrets in `Homelab-ansible` vault |
| **Never in Git** | No `.env` files, no Ansible Vault, no hardcoded credentials |
| **Resolved at deploy time** | Ansible templates call `lookup('community.general.onepassword', ...)` — secrets fetched at render time, never cached |
| **Forgejo Actions integration** | Service Account token with minimum-scope vault access. Secrets resolved at deploy, never on disk |
| **1Password CLI** | Installed on management laptop + Actions runner. `op` CLI + `OP_SERVICE_ACCOUNT_TOKEN` |
| **1Password SSH agent** | Private keys never on disk — served from `Homelab-ansible` vault on demand. See SSH Key Separation below |

---

## Secret Naming Convention

> **The single source of truth for 1Password items.** Every secret lives in the `Homelab-ansible` vault.

**Item name pattern: `<service>_<type>`**

- `<service>` = the consuming service / role. May contain `-` (e.g. `ansible-admin`, `laptop-domen`, `grafana-smtp`, `kopia-s3`). **Never `_` inside the service name.**
- `_` is the **only** delimiter between `<service>` and `<type>` in the whole name.
- `<type>` = the 1Password **item type** (see map below) — it determines which field the lookup reads.
- **Never put the field in the item name** (e.g. `service-name-db-password` → `service-name_db`).

**Always pass `field=` in Ansible.** The `community.general.onepassword` lookup defaults to the `password` field, which is **NOT** always the value you want. Vault is the `op_vault` variable (defined once in `group_vars/all/main.yml` → `Homelab-ansible`), so a vault rename is a one-line change:

```yaml
lookup('community.general.onepassword', '<service>_<type>', field='<field>', vault=op_vault)
```

### Rendering a secret into a YAML config file — block scalar is the default (HD-233 lesson)

> When a secret VALUE lands as a **mapping value in a rendered YAML/TOML config** (not a Docker
> `KEY: "{{ … }}"` env assignment — those aren't parsed as YAML by the app), render it as a
> **folded block scalar `>-` and NEVER a quoted inline `"{{ … }}"`.** An Authentik/OIDC
> `client_secret` (or any 1P `credential`/`password`) can contain `:`, `"`, `'`, backtick, `@`, `#`,
> `&`, `*`, `[`, `]`, `!`, `?`, `<`, `>` … which a quoted scalar does **not** escape — the inline form
> breaks YAML parse and crash-loops the app (**live incident 2026-08-24:** the rotated `headscale_api`
> secret broke BOTH headscale and headplane on restart with `YAMLException` / `EISDIR`).
>
> **Pattern (YAML-safe):**
>
> ```yaml
> oidc:
>   client_secret: >-
>     {{ lookup('community.general.onepassword', 'headscale_api', field='credential', vault=op_vault) }}
> ```
>
> **Do NOT render this way for a secret that may contain special char** (breaks on `:`/`"`):
>
> ```yaml
>   client_secret: "{{ … }}"   # BROKEN if the value contains : " ' etc.
> ```
>
> Scope: required for any file the consuming app parses as structured config (YAML/TOML/JSON) and the
> value is a 1Password secret — e.g. `headscale/config.yaml`, `headplane` config, `prometheus-web-config`,
> a Blueprint, `recyclarr.yml`. Shell scripts stay inline-quoted (never YAML-parsed). Rendered
> **compose files are still YAML** — `docker compose` parses them at deploy — so 1P-sourced
> `env:` values use `>-` there TOO (HD-166: a `"` in the value breaks the entire rendered file;
> plain non-secret env strings stay quoted). **TOML:** has no `>-`; use a basic string with Jinja escaping
> (`| replace('\\','\\\\') | replace('"','\\"')`) so a value containing `"` or `\` still parses
> (`tuwunel.toml` precedent). Validators: `validate-docker-services.py` mocks lookups, so
> it does not catch a secret-as-inline-quote; the audit is `grep` across `templates/**/*.j2` for
> `: "{{ lookup('community.general.onepassword'` in a *config* (non-compose) file (HD-233).

---

## Type Map — one per `<type>`, with canonical examples

> There is **no `server` type** by design — host/login/port are connection *config* kept in Git IaC;
> 1Password holds only *credentials*. See *Config vs credential split* above.

| `type`       | 1Password item    | `field=`              | Examples |
|--------------|-------------------|-----------------------|----------|
| `login`      | Login             | `password`            | SMTP/SMTP-relay creds (`smtp_login`), admin accounts (`mikrotik-admin_login`, `grafana_login`, `authentik_login`), any username+password combo |
| `password`   | Password          | `password`            | shared / opaque secrets with no username: webhook HMAC (`doco-cd_password` — retired HD-150), VRRP (`ha-vrrp_password`), upsmon (`nut_password`), repo master (`kopia_password`), Django `SECRET_KEY` (`authentik_password`), Matrix bootstrap shared secret (`matrix_password`), Headplane cookie/session signing secret (`headplane_password`), WireGuard private key (`wg_password`) |
| `api`        | API Credential    | `credential`          | tokens & keys: Cloudflare (`cloudflare_api`), Forgejo (`forgejo_api`), HA long-lived (`ha_api`), HA failover trigger (`ha-failover_api`), headscale OIDC (`headscale_api`), Headplane → Headscale API key (`headplane_api`), 1Password service-account (`op_api`), signal-cli (`signal_api`), PrivadoVPN WireGuard client key (`privado-vpn_api`), Matrix/Authentik OIDC client (`matrix_api`), Meteoblue weather key (`meteoblue_api`) |
| `oidc`       | API Credential    | `username`=`client_id`, `credential`=`client_secret` | **OAuth2/OIDC client credentials** — the 1Password item holds the Authentik-generated client_id (in `username`) + client_secret (in `credential`), seeded by the secret-egress glue (HD-143). e.g. `immich_oidc`, `opencloud_oidc`, `forgejo_oidc`, `metabase_oidc`. **Use `oidc`, NOT `api`**, for a service's OIDC *client* — this keeps it distinct from service API tokens (e.g. `forgejo_api` = the renovate git token, vs `forgejo_oidc` = the Authentik login client). Items older than this rule (`matrix_api`, `headscale_api`, `openwebui_api` for OIDC) are grandfathered under `api`; do not rename them. |
| `db`         | Database          | `password` (also `username`) | platform DBs: `authentik_db`, `opencloud_db`, `immich_db`, `forgejo_db`, `onlyoffice_db` — Database item holds both `username` (DB user) and `password` |
| `ssh`        | SSH Key           | `private_key` / `public_key` | `laptop-domen_ssh`, `ansible-admin_ssh`, `ai_ssh` — item stores both halves; read whichever the consumer needs |

> **Guidance:**
> - `login` = anything with a **username** (admin accounts, SMTP relays). One Login item per service — e.g. a service that has both an admin login and an SMTP relay gets two items: `grafana_login` + `smtp_login`.
> - `password` = a shared/opaque secret with **no username** (tokens for HMAC/VRRP/upsmon, repo/SECRET keys).
> - `api` = a **credential/token/key** for an API (including S3 and service-account tokens). API Credential items use `username` for access-key/client-id where applicable and `credential` for the secret.
> - `db` = Database item (`username` + `password` fields). Field for postgres link/password is `password`.
> - `ssh` = SSH Key item (`private_key` + `public_key` fields). See SSH Key Separation below.
> - `oidc` = an OAuth2/OIDC **client** (client_id + client_secret), seeded by the Authentik glue. Prefer `oidc` over `api` for a service's OIDC login client to avoid mixing with that service's API token. (Some early OIDC items use `api`; grandfathered.)

---

## Creation & Rotation Workflow

> Canonical index: CONVENTIONS §2 rows "Secret creation path / Seed before converge / Rotation propagation / Item-reference coverage" — this section carries the mechanics.

**1. Pick the creation path — every item is exactly one of four:**

| Path | When | How |
|------|------|-----|
| **Catalog-generated** | value is a fresh random secret with no external source | add a row to `provision-secrets.py` CATALOG (`--create` never overwrites existing items), then seed via `provision-vault.sh` from the WSL runner |
| **Manual-value** | value originates outside the homelab (provider dashboard, human-chosen password, alias address) | create the item by hand in 1Password; still add catalog/docs rows so scanners and docs know it exists |
| **Glue-seeded** | OAuth2/OIDC client for an Authentik-backed service (`*_oidc`) | NEVER hand-create and never put in CATALOG — the `authentik-secret-egress` glue generates and persists these at blueprint apply |
| **Externally-coupled** | rotation would break live state (DB cluster init-once passwords, admin bootstrap, shared HMAC keys) | may be catalog-created once, but MUST sit in `NOT_AUTO_ROTATABLE` with a stated reason; rotation = manual vault edit + explicit re-wire runbook |

**2. Order of operations (fail-loud invariant):** items exist BEFORE the playbook that renders their consumer runs — 1Password lookups fail loud mid-converge otherwise. Sequence per deploy: `check-vault-items.sh` → seed gaps (`provision-vault.sh`, or manual) → converge.

**3. Rotation propagation contract:** a rotated vault value reaches live state ONLY through (a) compose/config re-render on the next converge, or (b) an explicit sync task (`db_role_sync` ALTER ROLE guard, HD-220; `db_ro_sync` read-only role ensure, HD-242). If neither path exists for an item, it belongs in `NOT_AUTO_ROTATABLE` — silent divergence between vault and live state is the incident class these guards exist for (forgejo crash-loop 2026-08-23).

**4. Coverage contract:** when a change introduces a NEW group_vars key class that references a vault item (e.g. `db_ro_item`), the same change extends `check-vault-items.sh` to scan that key class — scanner blind spots defeat the fail-loud chain (HD-244).

---

## Master Secret List (canonical)

| Item name | `field=` | Used By |
|-----------|----------|---------|
| `laptop-domen_ssh` | `private_key` / `public_key` | post_install.sh — Domen's personal key → `ansible-admin` |
| `ansible-admin_ssh` | `private_key` / `public_key` | post_install.sh — dedicated Ansible key → `ansible-admin` |
| `ai_ssh` | `private_key` / `public_key` | post_install.sh — AI debug key (maps to `openrouter_ai`) → `ai-debug` |
| `netcup-ccp_login` | `password` | netcup — **Customer Control Panel** login (item `netcup-ccp_login`, 1Password `Homelab-ansible`). Billing / orders / subscription management at netcup. **NOT** consumed by Ansible (SSH provisioning, see `ansible-admin_ssh`) — account reference only (netcup RS 2000 G12) |
| `netcup-scp_login` | `password` | netcup — **Server Control Panel (SCP)** login — per-VPS admin/console (reboot, reinstall OS, KVM/console access, root password reset). Root-level access to the box; **break-glass** fallback if SSH is unavailable. Ansible still authenticates via `ansible-admin_ssh` by default |
| `netcup-vps_login` | `password` | netcup — **root/OS access** to RS 2000 G12: root password + IPv4/IPv6 (`159.195.111.66` / `2a0a:4cc0:60:fcc:*`). **Deliberately in a SEPARATE 1Password vault (NOT `Homelab-ansible`) so Ansible cannot read it** — kept off the automation path for safety. Break-glass root fallback; day-to-day SSH is `ansible-admin_ssh` as `ansible-admin` |
| `Hertzner-SB-Data` | — (connection ref) | Hetzner Storage Box **live** (BX11 1 TB) — connection reference for CIFS/SMB + WebDAV (`u653411`, server `653411`, SSH/SFTP port 23); **SMB username + password** stored here and consumed by the **`cifs` role** (VPS live-Box mount `/mnt/storagebox`, field=`username`/`password`). Recorded under `subscriptions.yml` (`secret: Hertzner-SB-Data`) — see `subscription.md` "Hetzner Storage Box — live" |
| `Hertzner-SB-Backup` | — (connection ref) | Hetzner Storage Box **backup** (BX11 1 TB) — connection reference, **no password** (SSH-key auth). Holds URL/username (`u653424`, server `u653424`, SSH/SFTP port 23). Recorded under `subscriptions.yml` (`secret: Hertzner-SB-Backup`), not an Ansible lookup — see `subscription.md` "Hetzner Storage Box — backup" |
| `kopia_password` | `password` | kopia-server (repo master password) |
| `authentik_db` | `password` (`username` = DB user) | authentik (Postgres) |
| `authentik_password` | `password` | authentik (Django `SECRET_KEY`) |
| `authentik_login` | `password` | authentik (bootstrap admin user) |
| `authentik-nas_api` | `api` | authentik — API token (**read-only**), minted durable (`expiring=False`, HD-216) at NAS provisioning from the VPS via `ak shell`, used by the Authentik→NAS provisioning glue (`sync-authentik-users.sh`, D5/HD-131). Distinct from the write-scoped `authentik-provision_api` (below) — this one may only *read* (family group/group members). |
| `authentik-provision_api` | `api` | **RETIRED 2026-08-22 (HD-143 rework, Option A):** the OIDC glue now mints an EPHEMERAL api-intent token per run via `ak shell` and revokes it on exit — a persisted Authentik token was observed being rotated/invalidated server-side within minutes (HD-216), silently invalidating any vault-stored copy. Root cause since IDENTIFIED (2026-08-24, HD-216 close): upstream AUTO-ROTATES expiring api-intent tokens (≈5-min sweep; only `expiring=False` tokens persist — recipe in [services-authentik.md](services-authentik.md)). Row kept as tombstone; delete when the 2025→2026 date sweep touches this file. |
| `vps-op-write_api` | `api` | 1Password **service-account token (write-scoped)** for the VPS host-side `op` CLI — deployed by the docker_services pre-pass to `/etc/op/provision-token` (0600); the glue uses it to seed the OIDC client-cred items. Different system/secret from `authentik-provision_api`. |
| `authentik-ldap_bind` | `password` | authentik LDAP outpost token + Samba ldapsam **bind password** (D7/HD-132). The outpost `AUTHENTIK_TOKEN` and Samba `ldap admin password` both read `field=password`. Populated at deploy when the LDAP provider/outpost are created (see deployment-oidc.md HD-132). |
| `opencloud_db` | `password` | opencloud (Postgres) |
| `opencloud_oidc` | `api` (`username` = client_id, `credential` = client_secret) | **OpenCloud native-OIDC client** (HD-52) — multi-redirect (web + desktop + mobile) Authentik provider, declared in the Blueprint; client_id/secret seeded by the secret-egress glue. |
| `opencloud-service_api` | `api` | OpenCloud **service account** for the Graph API — used by `sync-authentik-users.sh` / the provisioning glue to create OpenCloud users (D5/HD-131). **Not** the interactive `opencloud_login` (admin/break-glass); separate least-privilege service identity (required — service account must exist). |
| `opencloud_login` | `password` | OpenCloud **interactive admin/break-glass login** (`IDM_ADMIN_PASSWORD` in the opencloud compose) — separate from the least-privilege `opencloud-service_api` service account (above). |
| `opencloud-collab_password` | `password` | **Single shared WOPI/JWT secret across the entire OpenCloud ↔ ONLYOFFICE chain (HD-166, single-secret decision)** — used on ALL of: OpenCloud `OC_JWT_SECRET` (system-wide reva token_manager secret — MUST be set so auth-minted REVA tokens validate in collaboration; absence causes “token signature is invalid” 401), OpenCloud `COLLABORATION_JWT_SECRET` (mints/verifies ONLYOFFICE REST tokens), OpenCloud `COLLABORATION_WOPI_SECRET` (mints/verifies WOPI JWT + encrypts/decrypts embedded REVA token), and ONLYOFFICE `JWT_SECRET` — all must match exactly. Generated once at deploy; fail-loud if absent (HD-65). Rotation = regenerate, re-render BOTH compose files, converge, and **users must RE-LOGIN** (existing REVA tokens die).
| `immich_oidc` | `api` (`username` = client_id, `credential` = client_secret) | **Immich native-OIDC client** (HD-148) — web redirects `https://foto.kogler.si/auth/login` + `https://foto.kogler.si/user-settings` + mobile custom-scheme `app.immich:///oauth-callback` (needs Authentik to accept the custom scheme, or the http(s)/Mobile Redirect Override workaround); Confidential + Auth Code; storage label `preferred_username`, optional `immich_quota`. Declared in Blueprint; creds seeded by glue. |
| `forgejo_oidc` | `api` (`username` = client_id, `credential` = client_secret) | **Forgejo native-OIDC client** (HD-148) — web + git/API SSO on `git.`, callback `https://git.kogler.si/user/oauth2/<app-slug>/callback`; declared in Blueprint, creds seeded by glue. |
| `metabase_oidc` | `api` (`username` = client_id, `credential` = client_secret) | **Metabase OIDC client — FUTURE/OPTIONAL (HD-148):** Metabase OSS (`metabase/metabase:latest`) has **no OIDC/SSO — paid Pro/Enterprise only**. Provider declared in Blueprint + item seeded by glue for a *future* Enterprise license; until then Metabase stays **Forward-Auth** (route NOT switched). Callback `https://sec.kogler.si/auth/sso`. |
| `zipline_oidc` | `api` (`username` = client_id, `credential` = client_secret) | **Zipline native-OIDC client (HD-112)** — dashboard SSO on `bin.kogler.si`, callback `https://bin.kogler.si/api/auth/oauth/oidc`; declared in Blueprint, creds seeded by glue. Viewer routes + guest uploads stay anonymous by design (crowdsec-only tier). |
| ~~`minio_login`~~ | ~~`login`~~ | **retired (HD-135): MinIO S3 removed** — Immich originals + encoded-video go to the **live Hetzner Box (CIFS)**, not S3/MinIO. Orphaned MinIO compose template, `minio_version` var, and the Immich `IMMICH_S3_*` block all removed; `services.md` MinIO row removed. No S3 credential needed. |
| `immich_db` | `password` | immich-app (Postgres) |
| `forgejo_db` | `password` | forgejo (Postgres) |
| `zipline_db` | `password` | zipline-db sidecar (HD-112; Postgres metadata DB — users/links/metadata; dumped via db-backup DB05; file payloads live in the Kopia-excluded uploads tree) |
| `zipline_password` | `password` | zipline `CORE_SECRET` (session/config secret; HD-112). Fail-loud at render (HD-65). |
| `litellm_db` | `password` (`username`=DB user) | litellm-db sidecar (HD-247; Postgres runtime DB — **keys/models/spend via STORE_MODEL_IN_DB = CRITICAL state**; dumped via db-backup **DB06**; init-once password → NOT_AUTO_ROTATABLE, rotation = re-init = data loss without dump/restore) |
| `owui-public-chat_api`, `owui-public-rag_api`, `owui-int-wife_api`, `owui-int-owner_api`, `dsh_api`, `openclaw-litellm_api`, `rag-int-svc_api` | `api` → `credential` = LiteLLM virtual key `sk-…` | per-consumer scoped auth to LiteLLM (**HD-247**). Creation path: **glue-generated at bootstrap** — minted by POST `/key/generate` during the litellm converge and written straight into 1Password by `litellm-bootstrap-keys.sh`; NOT catalog-random (values are unprovisionable manually — they exist only server-side). Rotation semantics: delete the item's credential field AND the server key by alias in the Admin UI, re-run the glue (create-if-absent); a stale stored sk aborts loudly (rc2) since sks are hashed at rest. Scopes/budgets SSOT: `group_vars/vps.yml` `litellm_scoped_keys`; matrix in [services-ai.md](services-ai.md) §4 |
| `onlyoffice_db` | `password` | onlyoffice-postgres sidecar (ONLYOFFICE Docs metadata/document-tracking DB — regenerable state; HD-166 fix 2026-08-23) |
| `onlyoffice-rabbitmq_login` | `login` (`username`+`password`) | onlyoffice-rabbitmq sidecar — `RABBITMQ_DEFAULT_USER/PASS` (first mnesia init) + ONLYOFFICE `AMQP_URI`; NOT auto-rotatable (both sides coupled) |
| `forgejo_api` | `credential` | renovate (`RENOVATE_TOKEN`) — Forgejo token (deploy/CI via the Forgejo Actions runner); previously also doco-cd `GIT_ACCESS_TOKEN` (doco-cd dropped, HD-150) |
| `grafana_login` | `password` | grafana (admin user) |
| `smtp_login` | `password` | **SMTP relay (HD-54, SMTP2Go)** — shared by Grafana (SMTP fail-safe) + NUT (UPS email notify). `username` = SMTP user + notify email; `password` = SMTP pass. |
| `ha_api` | `credential` | HA long-lived token → Traefik/Companion, `/api/prometheus` bearer for Prometheus |
| `ha-vrrp_password` | `password` | keepalived (VIP `ha.kogler.si`) shared auth |
| `ha-failover_api` | `credential` | HA failover trigger API (HD-17) — Homepage buttons + `ha-failover-api` token |
| `crowdsec-bouncer_api` | `credential` | CrowdSec LAPI bouncer key for the Traefik bouncer plugin (`cscli bouncers add traefik-bouncer`; Wave-3 R5, 2026-08-22) |
| `meteoblue_api` | `credential` | Home Assistant core `meteoblue` weather integration (HD-22) — Meteoblue model API key |
| `headscale_api` | `credential` | headscale (OIDC client secret; `username` = client id) |
| `headplane_api` | `credential` | Headplane → **Headscale API key** (REQUIRED for Headplane OIDC mode, HD-233). Mint ONCE on the VPS: `docker exec headscale headscale apikeys create --expiration 8760d` |
| `headplane_password` | `password` | Headplane cookie/session signing secret — exactly 32 chars (`openssl rand -hex 16`), HD-233. **Password category** (c.f. `authentik_password`) — not under `api`. |
| `nut_password` | `password` | NUT UPS monitor (upsmon client → master auth) |
| `nut-exporter_password` | `password` | nut_exporter → upsd read-only auth (dedicated `upsmon slave` user on the NUT master) |
| `network-snmp_api` | `credential` | router + switch — MikroTik SNMP **read-only community** for Alloy polling (HD-53/Option A); `credential` = the RO community string |
| `wg_password` | `password` | router (WireGuard S2S private key) |
| `wifi-kogler_password` | `password` | CAPsMAN SSID **Kogler** (VLAN 10 Home) — router role when `routeros_capsman_enabled` flips true (HD-228/HD-03); alphanumeric only, 2.4 GHz-friendly chips on this SSID family (HD-228) |
| `wifi-kogler-iot_password` | `password` | CAPsMAN SSID **Kogler IOT** (VLAN 20 IoT, no internet) — Gen1 Shellys live here |
| `wifi-kogler-iot-wan_password` | `password` | CAPsMAN SSID **Kogler IOT WAN** (VLAN 21 IoT-Internet) — Bosch/LG cloud appliances (HD-228) |
| `wifi-kogler-guest_password` | `password` | CAPsMAN SSID **Kogler guest** (VLAN 30 Guest, client-isolated internet-only) |
| `wifi-kogler-kids_password` | `password` | CAPsMAN SSID **Kogler Kids** (VLAN 40 Kids, filtered DNS + bedtime block HD-182) |
| `privado-vpn_api` | `credential` | **PrivadoVPN WireGuard client private key** for the gluetun sidecar (`WIREGUARD_PRIVATE_KEY` in the qbittorrent compose; provider `privado`) — the *arr download traffic egresses through the VPN tunnel (HD-131 D2). |
| `mikrotik-admin_login` | `password` | router + switch + APs — MikroTik RouterOS admin (items RB4011/CRS328/hAP; **shared across all network gear — accepted, HD-165**). One admin password across all gear is an **accepted risk**: every RouterOS management surface binds to the Management VLAN (99) only — router `api`/`www-ssl`/`ssh` (8728/443/22) are `interface=vlan99-mgmt`; switch + APs are L2-only with no WAN egress — so the shared credential never crosses the internet boundary ([network-ops.md](network-ops.md)). Revisit per-gear items only if a gear gains WAN-exposed management or the Mgmt-VLAN INPUT ACL changes. |
| `pppoe_login` | `password` (`username` = PPPoE user) | router — ISP (Telekom) PPPoE credentials for the egress WAN |
| `cloudflare_api` | `credential` | ACME **DNS-01** wildcard `*.kogler.si` cert. Token IP filter: use **EXACT addresses only** — CIDR rows (/22, /64) proved unreliable on API-token filters (Wave-3 R5); VPS set = `159.195.111.66` + `2a0a:4cc0:60:fcc:d820:9dff:fe4f:95f5` (stable SLAAC), runner = home v4/v6 |
| ~~`kopia-s3_api`~~ | ~~`credential` (S3 access key)~~ | **retired (HD-31): iDrive e2 S3 dropped.** Kopia now targets the **backup Box over SSH/SFTP (port 23)** — SSH-key auth via `Hertzner-SB-Backup`, repo password via `kopia_password`. No S3 credential item needed. |
| `op_api` | `credential` | 1Password Service Account token → **Forgejo Actions** (deploy button). **Note (HD-140):** the Ansible runner uses the separate `Service Account Auth Token: ansible` in a **Private vault** instead of this item — see [1password.md](1password.md). `op_api` is the token storage slot for Actions; it is NOT created for the runner's CLI lookup. (Doco-CD half removed — Doco-CD dropped, HD-150.) |
| `signal_api` | `credential` (`username` = phone number) | signal-cli-rest-api (linked-device pair / captcha) |
| `signal-internal_api` | `credential` | signal-cli-rest-api — API token auth (`SIGNAL_CLI_API_TOKEN`; requests require `X-Api-Key` header) so no container on services-internal can send Signal as Domen's number without it (KOPS-002 / HD-125). n8n sends this in its webhook call |
| `kopia-server-internal_api` | `username` + `credential` | kopia-server auth (HD-59) — `username` = the `user@host` identity backup clients present via HTTP Basic Auth, `credential` = password; written to the in-container `server.htpasswd` (plaintext, 0600). Replaces the old `--without-password` |
| `prometheus-internal_api` | `username` + `bcrypt_hash` | prometheus Basic Auth (HD-59) — `username` = user, `bcrypt_hash` = bcrypt hash for `basic_auth_users` (generate via `scripts/gen-htpasswd.py`). Grafana + Alloy consume this endpoint |
| `immich-ml-internal_api` | `credential` | **ML API-key auth (HD-160)** — shared secret between `immich-app` (sends as ML-auth header) and `immich-ml` (validates it). Fail-loud (HD-65). Exact Immich v3 env var names deploy-verified. |
| `openclaw-opencloud_api` | `username` + `credential` | **OpenClaw → OpenCloud WebDAV (HD-160)** — `username` = OpenCloud service user, `credential` = app-specific password; consumed by `openclaw onboard` / `openclaw.json` WebDAV block. Scoped, rotatable, fail-loud. |
| ~~`doco-cd_password`~~ | ~~`password`~~ | **retired (HD-150): Doco-CD dropped** — single Ansible-only deploy/upgrade path. No webhook HMAC needed. |
| `sonarr_api` | `credential` | Sonarr API key — recyclarr syncs quality profiles from this instance |
| `radarr_api` | `credential` | Radarr API key — recyclarr syncs quality profiles from this instance |
| `pihole_password` | `password` | Pi-hole admin UI (`WEBPASSWORD`) — optional; empty = no password set via web UI |
| `matrix_api` | `credential` (`username` = client_id) | Tuwunel Matrix — Authentik OIDC client (`client_id` = username, `client_secret` = credential); callback URI registered in Authentik provider |
| `matrix_password` | `password` | Tuwunel Matrix — `registration_shared_secret` (bootstrap via `/_synapse/admin/v1/register`; keep a copy with the server identity/backups — HD-49) |
| `n8n_password` | `password` | n8n — `N8N_ENCRYPTION_KEY` (workflow encryption; long-lived, immutable — rotating means re-encrypting stored credentials). NOT used for webhook auth (see `n8n-webhook_api`) · HD-77 |
| `n8n-webhook_api` | `credential` | n8n — webhook/API auth token (`N8N_BASIC_AUTH_PASSWORD`; Grafana webhook contact point `basicAuthPassword`) — independently rotatable short-lived token so the encryption key is never exposed in webhook auth (KOPS-031 / HD-77). HTTP basic auth user = `grafana` |
| `openrouter_api` | `credential` | **AI stack** — LiteLLM: all external LLM generation (OpenRouter). Single key reused across every LLM consumer (Open WebUI, OpenClaw); only LiteLLM sees it. |
| `cohere_api` | `credential` | **AI stack** — LiteLLM: Cohere **embed-v4 multilingual** (embeddings only). Note: embeddings are **not** on OpenRouter, so this is a separate key from `openrouter_api`. |
| `litellm_master_key` | `credential` | **AI stack** — LiteLLM master key that Open WebUI + OpenClaw use to authenticate (they never hold upstream keys). |
| `openwebui_secret` | `password` | **AI stack** — Open WebUI session/encryption secret (optional). |
| `openwebui_api` | `credential` (`username` = client_id) | **AI stack** — Open WebUI **Authentik OIDC client** (`client_id` = username, `client_secret` = credential); redirect URI `https://ai.kogler.si/oauth2/callback` registered in the Authentik provider (HD-101) |
| `pgvector_db` | `password` (`username` = DB user) | **AI stack** — Open WebUI RAG vector DB (PGVector). Either this dedicated item or reuse a `db` pattern for the `pgvector` postgres. |
| `openclaw_gateway_token` | `password` | **AI stack** — OpenClaw gateway/Control-UI auth token (HD-104); generated by `openclaw onboard`, stored here fail-closed |
| `openwebui_api` *(see runbook)* | — | AI-stack OIDC wiring + full item-creation checklist: [`deployment-ai-stack-secrets.md`](deployment-ai-stack-secrets.md) (HD-105) |

> Entity naming: each item is a single `<service>_<type>` name with one `_` delimiter. The countable
> catalog (auto-generated + human-gated items) lives in [`../../scripts/provision-secrets.py`](../scripts/provision-secrets.py)
> (`--list`) — counts are derived, never hand-entered (CONVENTIONS §2).
> Future / not-yet-created: `n8n-smtp_login` (SMTP relay — provider not chosen yet, see deployment.md), `ha_mqtt` / `ha-mqtt_login` (if MQTT added to HA), `proxmox_root` / `proxmox_login` (Phase 2).

---

## Rename Map (legacy → canonical)

| Legacy (before) | Canonical (now) |
|-----------------|-----------------|
| `admin_laptop_ssh_pubkey` | `laptop-domen_ssh` |
| `ssh_ansible_pubkey` | `ansible-admin_ssh` |
| `ssh_ai_pubkey` | `ai_ssh` |
| `kopia_master_password` | `kopia_password` |
| `authentik_pg_password` | `authentik_db` |
| `authentik_secret_key` | `authentik_password` |
| `samba_ldap_admin_password` (smb.conf) / authentik-ldap `AUTHENTIK_TOKEN` | `authentik-ldap_bind` |
| `opencloud_db_password` | `opencloud_db` |
| `immich_db_password` | `immich_db` |
| `forgejo_db_password` | `forgejo_db` |
| `forgejo_token` | `forgejo_api` |
| `grafana_admin_password` | `grafana_login` |
| `grafana_smtp_password` | `smtp_login` |
| `ha_api_key` / `ha_exporter_token` / `ha_prometheus_token` / `long_lived_token` | `ha_api` |
| `ha_vrrp_password` | `ha-vrrp_password` |
| `headscale_oidc_secret` | `headscale_api` |
| `headscale_client_secret` (rotated HD-235) | `headscale_api` |
| `headplane_headscale_api_key` / `headplane_api_key` | `headplane_api` |
| `headplane_cookie_secret` | `headplane_password` |
| `upsmon_password` / `nut_upsmon_password` | `nut_password` |
| `smtp_notify_creds` / `nut_notify_email` / `nut_smtp_user` / `nut_smtp_pass` | `smtp_login` |
| `snmp_ro_community` (snmp.yml.j2 auth) | `network-snmp_api` |
| `network-snmp_login` (misnamed; API Credential, `credential` field) | `network-snmp_api` |
| `wireguard_private_key` | `wg_password` |
| `router_admin_password` | `mikrotik-admin_login` |
| `router_login` | `mikrotik-admin_login` |
| `cloudflare_api_token` / `cloudflare_api_token_credential` | `cloudflare_api` |
| ~~`s3_kopia_access_key` / `s3_kopia_secret_key` / `kopia_access_key` / `s3_kopia_secret`~~ → ~~`kopia-s3_api`~~ | **retired (HD-31/HD-135)** — iDrive S3 dropped; Kopia = SFTP to backup Box (see `kopia-s3_api` row) |
| `op_service_account_token` | `op_api` |

| `signal_api_*` | `signal_api` |

> `nut_smtp_server` (relay host, not a credential) is **config** — it lives in `group_vars`, not
> 1Password. `wildcard_cert_file` / `wildcard_cert_key_file` are cert filenames, not secrets.

---

## SSH Key Separation

Three independent ED25519 keys, one per purpose. Separate keys = revoke/rotate one without affecting the others, and audit which key was used.

| Key (1Password item) | Authorized user on hosts | Access level |
|----------------------|--------------------------|--------------|
| `laptop-domen_ssh` (private: personal) | `ansible-admin` | Full (NOPASSWD sudo) |
| `ansible-admin_ssh` | `ansible-admin` | Full (NOPASSWD sudo) |
| `ai_ssh` (private maps to `openrouter_ai`) | `ai-debug` | Debug only — no sudo, LAN-only, no forwarding |

**The same three keys are authorized on every homelab host** (nas, oldsrv, ...).

**AI access is safe because it is a different user.** The AI key can never log in as `ansible-admin` (which has passwordless root). The `ai-debug` authorized_keys line is injected by `post_install.sh`:

```
restrict,no-agent-forwarding,no-port-forwarding,no-X11-forwarding,from="10.10.0.0/16" ssh-ed25519 <AI_PUBKEY> openrouter_ai
```

**1Password SSH agent:** private keys never exist on disk — served on demand from the `Homelab-ansible` vault (Settings → Developer → SSH agent, socket path). Create the `.pub` reference files once in `~/.ssh/` (the agent reads them to identify items). Laptop `~/.ssh/config`:

```
Host nas nas-ansible nas-ai
  IdentityAgent <1Password SSH agent socket>

Host nas              # personal key
  User ansible-admin
  IdentityFile ~/.ssh/laptop-domen.pub
  IdentitiesOnly yes

Host nas-ansible      # dedicated Ansible key
  HostName nas
  User ansible-admin
  IdentityFile ~/.ssh/ansible-admin.pub
  IdentitiesOnly yes

Host nas-ai           # AI debugging — tell the AI: "use ssh nas-ai"
  HostName nas
  User ai-debug
  IdentityFile ~/.ssh/ai.pub
  IdentitiesOnly yes
  ForwardAgent no
  ForwardX11 no
```

After a host reinstall the host key changes — run `ssh-keygen -R nas` (or `-R oldsrv`) once on the laptop.

---

## AI Diagnostics Access (`ai-diag`)

For disk-failure forensics, `ai-debug` gets **exactly one** sudo entry — a locked-down dispatcher, never a shell:

```
# /etc/sudoers.d/ai-diag  (deployed by Ansible role `ai_diag`, mode 0440)
ai-debug ALL=(root) NOPASSWD: /usr/local/sbin/ai-diag *
```

- **No free-form flags.** In sudoers `*` is greedy and matches spaces, so a bare `smartctl *` would allow `smartctl -a /dev/sda -s off`. The dispatcher runs only fixed command lines with regex-validated `/dev/` or identifier arguments — flag smuggling is impossible.
- **Runtime contract:** the AI runs `sudo ai-diag help` to see everything it may do. Read-only SMART/ZFS/journal diagnostics, plus three non-destructive ops: `smart-test-short`, `smart-test-long`, `smart-test-abort`.
- **Audited:** every invocation appears in the sudo + journal logs (`LogLevel VERBOSE`).
- **Updating:** the script lives in the repo (`IaC/ansible/roles/ai_diag/files/ai-diag`). Edit it → re-run the `ai_diag` role → hosts updated. No SSH gymnastics, no drift.

---

## Passwordless-First Design

### For Family

- **No passwords to remember or type** — everything is biometric
- **Authentik** serves the SSO login page
- **1Password Passkeys** (WebAuthn) handle authentication:
  1. Click "Log in with Passkey"
  2. 1Password intercepts → FaceID/TouchID/Master Password
  3. Logged in — no typing
- **No app has its own login** — Traefik Forward Auth blocks unauthenticated traffic before it reaches any service

### For Administration (Domen)

- **SSH keys** — three separate ED25519 keys (personal / Ansible / AI) in 1Password, injected by post_install.sh. AI key restricted to the `ai-debug` user (no sudo, LAN-only, no forwarding)
- **Ansible** — 1Password lookup at render time, no passwords in playbooks

- **Forgejo** — OIDC via Authentik, or deploy key with push access

---

## Family Safe — Physical Backup

Paper stored in family safe:

1. **1Password master password + recovery codes**
2. **Link to Forgejo repo** (primary) + GitHub mirror (fallback)
3. **Brief instructions in Slovenian:**
   - "Odpri ta link na računalniku"
   - "Preberi README.md"
   - "Če ne razumeš, pokliči [trusted tech contact]"

This ensures no single point of failure: 1Password cloud + paper backup + Git mirrors.

---

## Security Boundaries

| Boundary | Detail |
|----------|--------|
| **Actions runner → VPS** | Dedicated SSH key (separate from Domen's personal key) |
| **Actions runner → 1Password** | Service Account token (`op_api`) — stored as Forgejo secret |
| **Homepage → internet** | Protected by Authentik Forward Auth |
| **Renovate → Docker Hub** | Read-only registry access — no credentials for public images |
| **AI → homelab hosts** | Dedicated `ai-debug` user — LAN-only (`from=`), no agent/port/X11 forwarding; sudo limited to the `ai-diag` allowlist (read-only diagnostics, see below) |
| **Ansible → hosts** | Fail-closed guards (site.yml pre-flight + `common` role assert) — playbooks refuse to run as `ai-debug` or unknown users; sudo + docker group granted only to `ansible_admin_users` (`ansible-admin`, `pi`) |
