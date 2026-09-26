---
title: Secrets Management & Passwordless Philosophy
role: detail
domain: deployment
status: active
tags: [deployment, secrets, 1password]
---
# Secrets Management & Passwordless Philosophy

> **Role:** Detail — 1Password as sole secrets backend, self-documenting philosophy, passwordless-first design.
> **Links to:** `deployment-oidc.md` (OIDC client + egress glue), `services-authentik.md` (OIDC secret rotation runbook), `deployment-ai-stack-secrets.md` (AI items + LiteLLM glue), `scripts/README.md` (parallel-1P contract), `backup.md`, `manual/README.md`
> **Linked from:** `deployment.md`, `deployment-ansible.md`, `deployment-compose.md`, `index.md`

---

## Self-Documenting Homelab Philosophy

- **Single Git repo is source of truth** — `git clone` + `ansible-playbook` = fully rebuilt infrastructure
- **Secrets never touch the repo** — all credentials live exclusively in 1Password
- **Documentation drives automation** — these `docs/*.md` files are read by AI to generate IaC configs
- ⚠ **Rotation caveat:** updating a 1Password item does NOT update already-initialized service state — re-render + redeploy applies it only where the service reads env/config at start. Known one-time seeds: `POSTGRES_PASSWORD` initializes a volume ONCE (later rotation needs `ALTER USER` inside the container); `AUTHENTIK_BOOTSTRAP_*` applies only at user creation. Both hit live during Phase 1 (akadmin identity, forgejo-db role) and were synced manually via sanctioned tooling.
- **No tribal knowledge** — if Domen is incapacitated, family + trusted tech contact can recover from 1Password + repo

### Config vs credential split — why there is NO `server` type

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

### Vault taxonomy — the two-vault model

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

> **Two secret-handling traps found live (HD-382, 2026-09-17):**
>
> 1. **`--diff` on a `docker_services` converge dumps rendered secrets.** The bulk 1P pre-pass runs
>    `no_log`, but the **template diff of a rendered `docker-compose.yml` is not no_log** — an
>    `--check --diff` run printed live `LITELLM_MASTER_KEY` / `OPENROUTER_API_KEY` values onto stdout
>    into the run log. Use `--check` (no `--diff`); verify renders from the template, or diff the
>    rendered host file with the secret lines filtered. If a log ever catches values, `shred -u` it —
>    do not grep it back (CONVENTIONS §6).
> 2. **LiteLLM does not expand `os.environ/…` inside a DB-stored model's `litellm_params`.** With
>    `STORE_MODEL_IN_DB=true` the entry `api_key: os.environ/SPARK_LLM_API` is forwarded to the
>    upstream **literally** → engine 401 (proven through the proxy and in-process
>    `litellm.completion`, v1.83.10). To keep a bearer out of the Kopia-backed DB, deliver it as the
>    **provider credential env** the model's provider prefix already reads (`openai/…` → `OPENAI_API_KEY`)
>    and leave `api_key` **unset** in the row — that path returns 200. Caveat to record per service: a
>    future bare `openai/…` entry with no `api_key` silently inherits that key.
>
### Rendering a secret into a YAML config file — block scalar is the default (HD-233 lesson)

> When a secret VALUE lands as a **mapping value in a rendered YAML/TOML config** (not a Docker
> `KEY: "{{ … }}"` env assignment — those aren't parsed as YAML by the app), render it as a
> **folded block scalar `>-` and NEVER a quoted inline `"{{ … }}"`.** An Authentik/OIDC
> `client_secret` (or any 1P `credential`/`password`) can contain `:`, `"`, `'`, backtick, `@`, `#`,
> `&`, `*`, `[`, `]`, `!`, `?`, `<`, `>` … which a quoted scalar does **not** escape — the inline form
> breaks YAML parse and crash-loops the app (**a rotated `headscale_api`
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
> a Blueprint, `recyclarr.yml`, and the `home_assistant` role's **`secrets.yaml.j2`** (rendered to
> `/opt/home-assistant-primary/secrets.yaml` + `{{ ha_standby_path }}/secrets.yaml`, fenced with `>-`
> block scalars per HD-233; HA resolves the values via `!secret` refs from `configuration.yaml.j2`).
> Shell scripts stay inline-quoted (never YAML-parsed). Rendered
> **compose files are still YAML** — `docker compose` parses them at deploy — so 1P-sourced
> `env:` values use `>-` there TOO (HD-166: a `"` in the value breaks the entire rendered file;
> plain non-secret env strings stay quoted). **TOML:** has no `>-`; use a basic string with Jinja escaping
> (`| replace('\\','\\\\') | replace('"','\\"')`) so a value containing `"` or `\` still parses
> (`tuwunel.toml` precedent). Validators: `validate-docker-services.py` mocks lookups, so
> it does not catch a secret-as-inline-quote; the audit is `grep` across `templates/**/*.j2` for
> `: "{{ lookup('community.general.onepassword'` in a *config* (non-compose) file (HD-233).
>
> **Compose `$`-interpolation — escape `$` → `$$`, and only in compose-parsed text (HD-270):**
>
> `docker compose` performs raw-text `$`-interpolation (`${VAR}` / `$VAR`) over the **whole rendered
> compose file BEFORE YAML parsing** — YAML quoting, `>-` folding and block scalars do **NOT** protect
> a literal `$` in a value. A 1Password secret whose value contains a `$` (e.g. `…$PoZcG…`) is therefore
> parsed as compose variable `PoZcG` → defaulted to blank → the running config is **silently truncated**
> at the `$`. The `docker compose config --quiet` validation only *warns + blanks*, never fails, so it
> misses the drift (**live incident: HD-270, 2026-08-28 full-converge log**, 6×
> `The "<token>" variable is not set. Defaulting to a blank string.`).
>
> **Fix, Layer 1 (source, primary):** prefer generators whose alphabet **excludes `$`**, so rotated
> values are natively safe forever — `provision-secrets.py` `gen_pw()` dropped `$` from its pool
> (2026-08-28). `gen_token()` never emits `$`. This makes every future rotation through
> `--rotate`/`--rotate-all` `$`-free at birth. (The dead `gen_wg_key()` helper was removed
> in HD-205 — `wg genkey` is the authoritative source for the wg private keys.)
>
> **Fix, Layer 2 (defensive, at render):** escape a 1Password field **only when it lands in compose-parsed
> text** — append `| replace('$','$$')` to the Jinja expression:
>
> ```yaml
> SECRET: >-
>   {{ vault['secret'].password | mandatory | replace('$', '$$') }}
> ```
>
> `$$` is the Compose escape ("prevents Compose from interpolating a value"); YAML parses it back to
> a literal `$`. This is safe against **any** future secret source (hand-pasted, vendor-rotated, OIDC
> glue) regardless of rotation-by-hand.
>
> **Scope — escape ONLY in compose text, NEVER in a plain config file (HD-270):**  interpolation applies
> only to docker-compose-parsed YAML. In a **non-compose** config template (`config.yaml`, `keepalived.conf`,
> `middlewares.yml`, `tuwunel.toml`, `prometheus-web-config.yml`, `recyclarr.yml`) the value is read by the
> app **as-is** — a `$$` there would be a **literal `$` you did not want** and would corrupt the secret.
> So the rule is **not** "escape every vault ref":
>
> - **Escape** every vault ref inside a `docker-compose.yml.j2` (Population A — compose interpolates it).
> - **Do NOT escape** vault refs inside non-compose config templates (Population B).
> - **Exempt the two composed `DATABASE_URL` values** (`zipline`, `litellm`) — their secret halves are
>   already `urlencode`'d, and `urlencode` writes `$` as `%24`, so no `$` survives; adding `replace`
>   would corrupt the URL.
>
> **Idempotency note:** `replace('$','$$')` is a single-layer escape. Applied once to a value the pool
> already keeps `$`-free it's a no-op; never chain the filter (it would double a pre-existing `$$`).
> Validator coverage: `validate-docker-services.py` unit-CI fixtures should be extended to assert the
> escaped vs un-escaped render; the live check is `docker inspect` env equal to the vault value.

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
| `ssh`        | SSH Key           | `private_key` / `public_key` | `domen_ssh`, `ansible-admin_ssh`, `ai_ssh` — item stores both halves; read whichever the consumer needs |

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

**5. Glue concurrency & 1P budget (HD-269):** the two bootstrap glues (`authentik-secret-egress`, `litellm-bootstrap-keys`) both fan out their vault reads/probes in parallel under a shared 1Password rate-limit budget (`OP_PARALLEL`, default 6 — never exceed ~6 concurrent `op` calls; only curl/docker-exec HTTP probes may go wider; hosted 1P rate-limits can block 15min+). Authentik may parallel-write distinct *oidc* items; LiteLLM keeps mint/store serial (unique-alias invariant). The full mechanism × layer × direction table + extensibility rule lives in [`scripts/README.md`](../scripts/README.md) §Parallel 1Password operations. If a third glue loop is ever added, copy that bounded fan-out pattern — do NOT merge the scripts.

**6. Glue-routing index — which doc owns which secret-glue step (SSOT for findability):**

| Lookup | Owning doc | What it covers |
|--------|-----------|----------------|
| Configure / create OIDC clients + Blueprint | [`deployment-oidc.md`](deployment-oidc.md) | Authentik Blueprint + egress-glue mechanics (procedural) — the secret-egress glue step (`deployment-oidc.md` §3), deploy ordering, per-service OIDC recipes |
| Rotate an OIDC client secret | [`services-authentik.md`](services-authentik.md) §"Rotating a shared Authentik OIDC client secret" | the on-host rotation runbook (verify + edit + re-render consumers) |
| Rotate the shared RouterOS `admin` password (`mikrotik-admin_login`) | [`network-ops.md`](network-ops.md) §Rotating the shared admin password (HD-321) | vault `old-password`/`password` update → re-render `render-converge.yml` + `render-routeros.yml` → apply per device via `routeros-apply-delta.sh`/`apply-converge.yml` → verify from a Mgmt-sourced API path |
| AI-stack items + LiteLLM scoped-key glue | [`deployment-ai-stack-secrets.md`](deployment-ai-stack-secrets.md) | AI 1P item creation, OIDC wiring, LiteLLM bootstrap-keys rotation/rollback (HD-105) |
| Rotate the spark engine bearer (`spark-llm_api`) | [`deployment-ai-stack-secrets.md`](deployment-ai-stack-secrets.md) §4a | the FOUR coupled bearers (engine `--api-key` + both LiteLLM envs + laptop `models.json`), the single-window rule, the write-scoped-token location, and the 2026-09-18 leak + rotation window |
| Retire an SSH grant, or audit who may SSH into a host | [`deployment-secrets.md`](deployment-secrets.md) §Who is authorized where | the per-host grant inventory + the reversible retire sequence above (HD-416 is the automated gate) |
| The two glue scripts' parallel implementation + concurrency budget | [`scripts/README.md`](../scripts/README.md) §Parallel 1Password operations | layer × direction × concurrency table, the 1P budget, extensibility rule |

> Findability rule: if you search for "which glue / who provisions / how to rotate" a secret, start here; the row routes you to the owning doc. Do NOT re-author glue mechanics in multiple docs — each row is a single source.

**7. Writing a manual value from the CLI without leaking it (and without writing it wrongly):** hand
creation in the 1Password UI is the default for the manual-value path; when the write has to happen
from a runner, these rules are what make it safe *and correct*:

- **Never pass the value as an argument.** `op item edit <item> "field=<value>"` puts the secret in
  `argv`, visible to every process on the box. Values move through files (0600, `shred -u` after) or
  templates, and only **lengths/hashes** are ever printed (CONVENTIONS §6).
- **`op item create --template` with a `fields` array does NOT fill the category's built-in fields — it
  APPENDS new ones and leaves `username`/`password` empty.** The item then looks correct (`op item get`
  shows both values under the right labels) while every **label-based** read — `op://…`, the
  `onepassword` lookup, `op-vault-export.py` — resolves the empty duplicate. Rendered compose then
  carries empty credentials, which is the silent class these guards exist for. Verified on op CLI 2.39.0
  for `create --template` **and** `edit --template` with a fields-only template.
- **The correct CLI shape is a round-trip:** create the item **bare** (title/category/vault/tags),
  `op item get … --format json` → set `value` on the fields whose **`id`** already exists →
  `op item edit … --template <file>`.
- **Verify by length *and* shape**, not by "the command exited 0":
  `op read op://<vault>/<item>/<field> | wc -c` for each field, plus a field-list check that each
  expected `id` appears **exactly once**. An empty `wc -c` on a field that should hold bytes means the
  duplicate-field shape bug above, not a missing value — fix the item before any converge renders it.

**8. Token scope actually measured (2026-09-21, owner-asked):** the runner's **ambient**
`OP_SERVICE_ACCOUNT_TOKEN` performed `item delete` / `item create` / `item edit` on `Homelab-ansible`
without the `op-write_api` token — i.e. it is **not read-only**. Scripts and docs that fetch
`op-write_api` because "the exported SA token is READ-scoped" (`rotate-spark-llm-key.sh`, its
[`scripts/README.md`](../scripts/README.md) row) carry an assumption that no longer holds; the read-only
expectation is a least-privilege property, so either the token is narrowed or those notes are corrected
(`scripts/**` owner this wave: `prompt-407.md` (**closed, brief deleted**)). Do not treat the discrepancy as
permission to write from an automation path that was designed to be read-only.---

## Master Secret List (canonical)

| Item name | `field=` | Used By |
|-----------|----------|---------|
| `domen_ssh` | `private_key` / `public_key` | post_install.sh — Domen's personal key → `ansible-admin` |
| `ansible-admin_ssh` | `private_key` / `public_key` | post_install.sh — dedicated Ansible key → `ansible-admin` |
| `ai_ssh` | `private_key` / `public_key` | post_install.sh — AI debug key (maps to `openrouter_ai`) → `ai-debug` |
| `netcup-ccp_login` | `password` | netcup — **Customer Control Panel** login (item `netcup-ccp_login`, 1Password `Homelab-ansible`). Billing / orders / subscription management at netcup. **NOT** consumed by Ansible (SSH provisioning, see `ansible-admin_ssh`) — account reference only (netcup RS 2000 G12) |
| `netcup-scp_login` | `password` | netcup — **Server Control Panel (SCP)** login — per-VPS admin/console (reboot, reinstall OS, KVM/console access, root password reset). Root-level access to the box; **break-glass** fallback if SSH is unavailable. Ansible still authenticates via `ansible-admin_ssh` by default |
| `netcup-vps_login` | `password` | netcup — **root/OS access** to RS 2000 G12: root password + IPv4/IPv6 (`159.195.111.66` / `2a0a:4cc0:60:fcc:*`). **Deliberately in a SEPARATE 1Password vault (NOT `Homelab-ansible`) so Ansible cannot read it** — kept off the automation path for safety. Break-glass root fallback; day-to-day SSH is `ansible-admin_ssh` as `ansible-admin` |
| `Hertzner-SB-Data` | — (connection ref) | Hetzner Storage Box **live** (BX11 1 TB) — connection reference for CIFS/SMB + WebDAV (`u653411`, server `653411`, SSH/SFTP port 23); **SMB username + password** stored here and consumed by the **`cifs` role** (VPS live-Box mount `/mnt/storagebox`, field=`username`/`password`). Recorded under `subscriptions.yml` (`secret: Hertzner-SB-Data`) — see `subscription.md` "Hetzner Storage Box — live" |
| `Hertzner-SB-Backup` | — (connection ref) | Hetzner Storage Box **backup** (BX11 1 TB) — connection reference, **no password** (SSH-key auth). Holds URL/username (`u653424`, server `u653424`, SSH/SFTP port 23). Recorded under `subscriptions.yml` (`secret: Hertzner-SB-Backup`), not an Ansible lookup — see `subscription.md` "Hetzner Storage Box — backup" |
| `kopia_password` | `password` | kopia-server (repo master password) |
| `kopia-server_fingerprint` | `password` | **kopia-server TLS trust anchor (HD-318a)** — SHA-256 fingerprint (lowercase hex) of the persisted self-signed cert at `/srv/docker/kopia-server/config/tls.crt`; the oldsrv agent pins it (`--server-cert-fingerprint`). **Derived value**: seeded from the live cert by the docker_services `kopia-fingerprint-sync.yml` task (NOT catalog-generated — the catalog builder returns `[]`); NOT_AUTO_ROTATABLE (rotate = regenerate cert + re-pin both sides) |
| `authentik_db` | `password` (`username` = DB user) | authentik (Postgres) |
| `authentik_password` | `password` | authentik (Django `SECRET_KEY`) |
| `authentik_login` | `password` | authentik (bootstrap admin user) |
| `authentik-nas_api` | `api` | authentik — API token (**read-only**), minted durable (`expiring=False`, HD-216) at NAS provisioning from the VPS via `ak shell`, used by the Authentik→NAS provisioning glue (`sync-authentik-users.sh`, D5/HD-131). Distinct from the write-scoped `authentik-provision_api` (below) — this one may only *read* (family group/group members). |
| `authentik-provision_api` | `api` | **RETIRED 2026-08-22 (HD-143 rework, Option A):** the OIDC glue now mints an EPHEMERAL api-intent token per run via `ak shell` and revokes it on exit — a persisted Authentik token was observed being rotated/invalidated server-side within minutes (HD-216), silently invalidating any vault-stored copy. Root cause since IDENTIFIED (2026-08-24, HD-216 close): upstream AUTO-ROTATES expiring api-intent tokens (≈5-min sweep; only `expiring=False` tokens persist — recipe in [services-authentik.md](services-authentik.md)). Row kept as tombstone; delete when the 2025→2026 date sweep touches this file. |
| `op-write_api` | `api` | 1Password **service-account token (read+write)** — renamed 2026-09-19 from `vps-op-write_api`, which is DELETED — for the VPS host-side `op` CLI — deployed by the docker_services pre-pass to `/etc/op/provision-token` (0600); the glue uses it to seed the OIDC client-cred items. Different system/secret from `authentik-provision_api`. ⚠ **The copy deployed on OLDSRV is dead (measured 2026-09-23):** `/etc/op/provision-token` there belongs to a service account 1Password reports as `403 Forbidden (Service Account Deleted)`, so anything on oldsrv that writes to the vault through it fails — and fails at the first `op` call, not quietly. Consequence: the "home hosts hold `op-write_api` where a `bootstrap_keys` service converges" claim in §Where a token is installed is **stale for oldsrv**, and any secret that was supposed to be written from oldsrv since that SA was deleted never landed. Owner action: mint a current write-scoped SA, update this item, re-run the pre-pass that deploys the token, then re-test (`op item list --vault Homelab-ansible` with the file as the token is a sufficient probe). **CORRECTED 2026-09-23, later the same night — the owner action above was wrong** and would have sent the owner to hunt a credential that already works. Probing BOTH hosts with their own file: the VPS copy (re-deployed 2026-09-19) answers `op item list` with real rows; oldsrv's (2026-09-15) returns the 403. Same vault item, opposite verdict ⇒ **the item is alive**; oldsrv simply never received the re-issued value — and it never could have, because the only task that writes `/etc/op/provision-token` is the Authentik pre-pass, gated on `'authentik' in docker_services` (VPS-only) and hard-asserting that same condition. A home host had **no refresh path in code at all**, so "re-run the pre-pass" was not an action anyone could take. Fix landed the same night: `roles/docker_services/tasks/op-provision-token.yml` + `docker_services_op_provision_token: true` in `home_servers.yml`, gated `scope_is_all` and mutually exclusive with the Authentik pre-pass. That task also **probes the token instead of trusting the file's existence** — every consumer here tests `[ -r /etc/op/provision-token ]` and then trusts the read, which is exactly how a dead credential survived eight days of green converges. |
| ⚠ `cockpit-pi-web_api` | **does not exist yet** | The `PI_WEB_TOKEN` guarding the oldsrv coding seat (HD-409) lives **only** in `/home/domen/.config/pi-web/env` on that box (0600, owner `domen`). It went un-minted because the session that found it believed the write-scoped SA above was deleted — the belief was wrong (corrected above), but the row's reason for existing stands: a credential with no vault item is invisible to rotation and to the inventory, the same class as `oldsrv-rsync`. ⛔ **Deliberately NOT catalog-generated**, and the reason it is absent from `provision-secrets.py`'s `CATALOG` while the two `*-cockpit_login` rows below are in it: `--create` mints a NEW random value, whereas the live cockpit already has one and every paired client is bound to it. So the item must be created carrying the **same** value the env file holds. Sequence: re-converge `docker_services` on oldsrv (the token fix above) → read the value from the env file straight into the item, never through a transcript (CONVENTIONS §6 never-print) → verify by hash → rewrite this row as a normal entry with a rotation note, which must also say that **rotating it re-pairs every client**. |
| `oldsrv-cockpit_login` | `password` | **HD-361** — the PAM password behind the `maint` break-glass identity on **oldsrv**. Consumer: `roles/cockpit/tasks/maint-user.yml`, which reads it on the control node (fail-closed: no value, no converge), crypts it **on the target** with `openssl passwd -6` and a salt derived from the item name — deterministic so the hash is stable across converges AND so the verify step can prove the installed hash IS this value — and installs it via `ansible.builtin.user`. Grants group membership `cockpit-session` (the gate) + `sudo` (owner decision 2026-09-21: the web-tty must be able to break glass) and NOTHING else: no `NOPASSWD` sudoers entry — the converge reads `sudo -l -U maint` and FAILS if a fragment ever granted one — no SSH key, and `AllowUsers` is read back and asserted not to contain `maint`. The hash is what lands in `/etc/shadow` (root-readable); the plaintext never touches the host, a log or a transcript. ⏳ Measured 2026-09-23/24: `getent passwd maint` **ABSENT** on oldsrv — not because the leg is missing (it is written) but because the host has been off the network since 2026-09-23 21:39:56; `cockpit-oldsrv.kogler.si` has no working login until that box returns and `--tags cockpit` runs against it.
| `nas-cockpit_login` | `password` | **HD-361** — the same `maint` break-glass PAM identity on **nas** (`cockpit-nas.kogler.si`); same consumer, same rules, separate value on purpose (one shared item would hand two management consoles the same password, which is the opposite of why there are two). ✅ **Live + console-verified 2026-09-24**: `maint` exists, its group set is exactly `cockpit-session` + `sudo`, the installed hash byte-matches this item, `AllowUsers` does not admit it, and Cockpit returns 200 for it at `/cockpit/login` — the first time that endpoint has ever accepted a credential on this host. Re-converging is `changed=0`. Note the gate is new: before it, `/etc/pam.d/cockpit` imposed no group restriction, so this item's account joined a console that already authenticated any local password holder — see [security.md](security.md).
| `authentik-ldap_bind` | `password` | authentik LDAP outpost token + Samba ldapsam **bind password** (D7/HD-132). The outpost `AUTHENTIK_TOKEN` and Samba `ldap admin password` both read `field=password`. Populated at deploy when the LDAP provider/outpost are created (see deployment-oidc.md HD-132). |
| `opencloud_db` | `password` | opencloud (Postgres) |
| `opencloud_oidc` | `api` (`username` = client_id, `credential` = client_secret) | **OpenCloud native-OIDC client** (HD-52) — multi-redirect (web + desktop + mobile) Authentik provider, declared in the Blueprint; client_id/secret seeded by the secret-egress glue. |
| `opencloud-service_api` | `api` | OpenCloud **service account** for the Graph API — used by `sync-authentik-users.sh` / the provisioning glue to create OpenCloud users (D5/HD-131). **Not** the interactive `opencloud_login` (admin/break-glass); separate least-privilege service identity (required — service account must exist). |
| `opencloud_login` | `password` | OpenCloud **interactive admin/break-glass login** (`IDM_ADMIN_PASSWORD` in the opencloud compose) — separate from the least-privilege `opencloud-service_api` service account (above). |
| `opencloud-collab_password` | `password` | **Single shared WOPI/JWT secret across the entire OpenCloud ↔ ONLYOFFICE chain (HD-166, single-secret decision)** — used on ALL of: OpenCloud `OC_JWT_SECRET` (system-wide reva token_manager secret — MUST be set so auth-minted REVA tokens validate in collaboration; absence causes “token signature is invalid” 401), OpenCloud `COLLABORATION_JWT_SECRET` (mints/verifies ONLYOFFICE REST tokens), OpenCloud `COLLABORATION_WOPI_SECRET` (mints/verifies WOPI JWT + encrypts/decrypts embedded REVA token), and ONLYOFFICE `JWT_SECRET` — all must match exactly. Generated once at deploy; fail-loud if absent (HD-65). Rotation = regenerate, re-render BOTH compose files, converge, and **users must RE-LOGIN** (existing REVA tokens die).
| `immich_oidc` | `api` (`username` = client_id, `credential` = client_secret) | **Immich native-OIDC client** (HD-148) — web redirects `https://foto.kogler.si/auth/login` + `https://foto.kogler.si/user-settings` + mobile custom-scheme `app.immich:///oauth-callback` (needs Authentik to accept the custom scheme, or the http(s)/Mobile Redirect Override workaround); Confidential + Auth Code; storage label `preferred_username`, optional `immich_quota`. Declared in Blueprint; creds seeded by glue. **Consumer = `tasks/immich-seed.yml`, NOT the compose** — Immich v3 reads no OAuth env var, so the seed PUTs these into the DB system config (HD-147; [deployment-oidc.md](deployment-oidc.md) §Immich). |
| `immich-admin_login` | `login` (`username` = admin email, `password`) | **Immich's own admin seat** (the native e-pošta/geslo account created by the first-run wizard — NOT an Authentik identity). Owner-seeded with the real values (2026-09-25). Consumed by `roles/docker_services/tasks/immich-seed.yml`, which must log in as it to `PUT /api/admin/config` — Immich has no API-token path for system config and no admin CLI, and the config is DB-only. Rotating the Immich admin password therefore needs a re-run of that seed lane (or nothing, if the seed is not re-run — it reads the item at run time). It is also the **break-glass login** if OIDC ever breaks, so do not lock it. |
| `forgejo_oidc` | `api` (`username` = client_id, `credential` = client_secret) | **Forgejo native-OIDC client** (HD-148) — web + git/API SSO on `git.`, callback `https://git.kogler.si/user/oauth2/<app-slug>/callback`; declared in Blueprint, creds seeded by glue. |
| ~~`metabase_oidc`~~ | ~~`api`~~ | **RETIRED 2026-09-14 (Metabase removed from VPS; future home oldsrv).** Was FUTURE/OPTIONAL (HD-148): Metabase OSS has **no OIDC/SSO — paid Pro/Enterprise only**; provider declared in Blueprint + item seeded by glue for a *future* Enterprise license; Metabase stayed **Forward-Auth**. Callback was `https://sec.kogler.si/auth/sso`. The dormant provider/glue line is left in place (touching it forces a live Authentik blueprint re-apply — out of scope of the retirement); item stays in the vault. **Owner ruling 2026-09-25 (HD-447): the live Authentik objects are deleted and the IaC stays `enabled: false` — see §Item titles are load-bearing for the acceptance test.** The vault item was **deleted by the owner 2026-09-26**, closing the one residue this row carried. Revisit ONLY if an oldsrv Metabase gets an Enterprise license + VPS Authentik OIDC. |
| `zipline_oidc` | `api` (`username` = client_id, `credential` = client_secret) | **Zipline native-OIDC client (HD-112)** — dashboard SSO on `bin.kogler.si`, callback `https://bin.kogler.si/api/auth/oauth/oidc`; declared in Blueprint, creds seeded by glue. Viewer routes + guest uploads stay anonymous by design (crowdsec-only tier). |
| ~~`minio_login`~~ | ~~`login`~~ | **retired (HD-135): MinIO S3 removed** — Immich originals + encoded-video go to the **live Hetzner Box (CIFS)**, not S3/MinIO. Orphaned MinIO compose template, `minio_version` var, and the Immich `IMMICH_S3_*` block all removed; `services.md` MinIO row removed. No S3 credential needed. |
| `immich_db` | `password` | immich-app (Postgres) |
| `forgejo_db` | `password` | forgejo (Postgres) |
| `zipline_db` | `password` | zipline-db sidecar (HD-112; Postgres metadata DB — users/links/metadata; dumped via db-backup DB05; file payloads live in the Kopia-excluded uploads tree) |
| `zipline_password` | `password` | zipline `CORE_SECRET` (session/config secret; HD-112). Fail-loud at render (HD-65). |
| `litellm_db` | `password` (`username`=DB user) | litellm-db sidecar (HD-247; Postgres runtime DB — **keys/models/spend via STORE_MODEL_IN_DB = CRITICAL state**; dumped via db-backup **DB06**; init-once password → NOT_AUTO_ROTATABLE, rotation = re-init = data loss without dump/restore) |
| `owui-public-chat_api`, `owui-public-rag_api`, `owui-int-wife_api`, `owui-int-owner_api`, `openclaw-litellm_api`, `rag-int-svc_api` | `api` → `credential` = LiteLLM virtual key `sk-…` | per-consumer scoped auth to LiteLLM (**HD-247**). Creation path: **glue-generated at bootstrap** — minted by POST `/key/generate` during the litellm converge and written straight into 1Password by `litellm-bootstrap-keys.sh`; NOT catalog-random (values are unprovisionable manually — they exist only server-side). Rotation semantics: delete the item's credential field AND the server key by alias in the Admin UI, re-run the glue (create-if-absent); a stale stored sk aborts loudly (rc2) since sks are hashed at rest. **Parked 2026-09-17 (HD-386):** `dsh_api` + `pi-harness_openai_api` have NO consuming record any more (the `litellm_scoped_keys` entries are commented out with their consumers), so neither is minted, probed or required; the ITEMS stay in the vault untouched — `dsh_api` still holds the stale VPS-era value and would trip rc2 again if the record is ever restored (remediation: HD-383). Scopes/budgets SSOT: `group_vars/vps.yml` `litellm_scoped_keys`; matrix in [services-ai.md](services-ai.md) §4 |
| `onlyoffice_db` | `password` | onlyoffice-postgres sidecar (ONLYOFFICE Docs metadata/document-tracking DB — regenerable state; HD-166 fix 2026-08-23) |
| `onlyoffice-rabbitmq_login` | `login` (`username`+`password`) | onlyoffice-rabbitmq sidecar — `RABBITMQ_DEFAULT_USER/PASS` (first mnesia init) + ONLYOFFICE `AMQP_URI`; NOT auto-rotatable (both sides coupled) |
| `forgejo_api` | `credential` | renovate (`RENOVATE_TOKEN`) — Forgejo token (deploy/CI via the Forgejo Actions runner); previously also doco-cd `GIT_ACCESS_TOKEN` (doco-cd dropped, HD-150) |
| `grafana_login` | `password` | grafana (admin user) |
| `smtp_login` | `password` | **SMTP relay (HD-54, SMTP2Go)** — shared by Grafana (SMTP fail-safe) + NUT (UPS email notify) + HA `secrets.yaml` (rendered, consumer pending). (Metabase SMTP consumer **retired 2026-09-14** — no longer a consumer.) `username` = SMTP user + notify email (`notify@kogler.si`); `password` = SMTP pass. **Rotated 2026-09-09** (exposed via git history) → converged VPS/grafana+metabase, Pi+oldsrv HA secrets, NUT upssched-cmd (hash-verified live). |
| `ha_api` | `credential` | HA long-lived token → Traefik/Companion, `/api/prometheus` bearer for Prometheus |
| `ha-vrrp_password` | `password` | keepalived (VIP `ha.kogler.si`) shared auth |
| `ha-failover_api` | `credential` | HA failover trigger API (HD-17) — Homepage buttons + `ha-failover-api` token |
| `homelable_login` | `username`, `password`, `bcrypt_hash` | Homelable admin login (HD-45) — `username`/`password` = the local admin creds; `bcrypt_hash` = bcrypt(password), rendered as the backend `AUTH_PASSWORD_HASH`. Catalog-generated (Login + bcrypt_hash pair, see `homelable_login_item()` in provision-secrets.py). Rotation rewrites password + hash together. |
| `homelable_secret` | `password` | Homelable `SECRET_KEY` (JWT/session signing, ≥32 bytes) + shared `MCP_SERVICE_KEY` source when the MCP container is enabled (HD-45). Catalog-generated. |
| `homelable_mcp` | `credential` | Homelable MCP server `MCP_API_KEY` (HD-45, optional container) — AI-tool topology read/write. Catalog-generated; unused while `homelable_mcp_enabled` is false. |
| `rustdesk_login` | `username` = **public** key (base64), `password` = **secret** key (base64) | **RustDesk server (HD-412, VPS)** — the hbbs/hbbr ed25519 keypair: `KEY_PUB`/`KEY_PRIV` in the compose; with `ENCRYPTED_ONLY=1` both binaries run `-k _`, so the PUBLIC half is what every client pins as its "Key" and the SECRET half authenticates the server to them. **Naming:** `<service>_<type>` with type = the 1Password **item type**, so this is a **Login** item — it is NOT an interactive login and there is no account behind it; Login is the category whose two field labels (`username`/`password`) both the HD-258 pre-pass (`op-vault-export.py`) and the `validate-docker-services.py` mock materialise, so a custom field name (or an SSH-key item) renders green and fails at deploy. The suffix also keeps it inside `check_vault_docs.py`'s derived set. **Manual-value class, NOT in the provisioner CATALOG**: `rustdesk-utils genkeypair` mints it (generation + the write rules = §Creation & Rotation Workflow item 7; this row is its coverage record. ⚠ `check-vault-items.sh` cannot see it either — the script greps literal `onepassword', 'NAME'` lookups and this template uses the HD-258 `vault['…']` dict form, so **the fail-closed render is the actual gate**; seed before `enabled: true`. **NOT_AUTO_ROTATABLE — externally-coupled**: the s6 `key-secret` step seeds `/data/id_ed25519*` only when the file is absent, so the live file is authoritative and a vault edit changes nothing; rotating (replace the item **and** delete `/data/id_ed25519*` **and** re-deploy) **orphans every enrolled client**, whose stored key stops matching — re-enrolment is manual, per machine. **Backup story:** the item IS the restore (wipe `/srv/docker/rustdesk-server/data`, re-converge → the pair is re-seeded and clients keep working), which is why the seed must exist BEFORE `enabled: true` (the compose is fail-closed without it — HD-386 class). ⚠ The pair is visible in `docker inspect` env output on that container. |
| `crowdsec-bouncer_api` | `credential` | CrowdSec LAPI bouncer key for the Traefik bouncer plugin (`cscli bouncers add traefik-bouncer`; Wave-3 R5, 2026-08-22) |
| `meteoblue_api` | `credential` | Home Assistant core `meteoblue` weather integration (HD-22) — Meteoblue model API key |
| `headscale_api` | `credential` | headscale (OIDC client secret; `username` = client id) |
| `headplane_api` | `credential` | Headplane → **Headscale API key** (REQUIRED for Headplane OIDC mode, HD-233). Mint ONCE on the VPS: `docker exec headscale headscale apikeys create --expiration 8760d` |
| `headplane_password` | `password` | Headplane cookie/session signing secret — exactly 32 chars (`openssl rand -hex 16`), HD-233. **Password category** (c.f. `authentik_password`) — not under `api`. |
| `tailscale-sidecar_api` | `credential` | tailscale-sidecar (HD-135b follow-up) — **Tailscale/Headscale preauth key** for the `vps-obs` sidecar node, scoped to `tag:sidecar` (`docker exec headscale headscale preauthkeys create --user 2 --tags tag:sidecar --reusable --expiration 8760h -o json`), consumed by the `traefik-tailnet` compose `TS_AUTHKEY`. API-Credential type (`credential` field). |
| `tailscale-oldsrv_api` | `credential` | tailscale-node (HD-405, 2026-09-20) — **headscale preauth key** for the `oldsrv` tailnet node, scoped to `tag:dev`: `docker exec headscale headscale preauthkeys create --user 2 --tags tag:dev --reusable --expiration 8760h -o json`. Consumed by `host_vars/oldsrv.kogler.si.yml` → `roles/tailscale-node`; written to `/run` mode 0600 for the one `tailscale up` and shredded in the block's `always`, so no copy outlives the join. **Manual-value path** — headscale mints it, so it is NOT in the provisioner CATALOG and `check-vault-items.sh` does not scan host roles (same exemption as `switch`/`router`); this row IS the coverage record. ⚠ headscale 0.29.3 emits the value under JSON key **`key`**, not `secret`: a redaction filter written against `secret` LEAKS it (live 2026-09-20 — key id 6 reached a transcript, was expired + deleted, id 7 minted instead. The field name is the trap). |
| `tailscale-pi_api` | `credential` | tailscale-node (HD-435, 2026-09-25) — **headscale preauth key** for the SECOND permitted home node, the Pi, scoped to its OWN tag: `docker exec headscale headscale preauthkeys create --user <id> --tags tag:home-edge --reusable --expiration 8760h -o json`. ⚠ **The tag IS the reach surface**: the ACL grants `tcp/443` by tag, so a key minted with `tag:dev` (or with no tag) gives the Pi either the dev seat's ports or nothing at all — read the assignment back with `headscale nodes list` after the join. Consumed by `host_vars/pi.kogler.si.yml` → `roles/tailscale-node` (key written to `/run` mode 0600, shredded in `always`). API-Credential type (`credential` field). ✅ **Seeded 2026-09-25** (key id 8, minted by the headscale CLI on the VPS and written with `op item create --category "API Credential"`); the Pi read it and enrolled as headscale node 13 / `tag:home-edge` the same day. The Pi converge fails loud (no `default('')` fallback) if this item is ever removed. |
| ~~`tailscale_dsh_api` / ~~`tailscale_pi_dev_api` | ~~`credential`~~ | **PARKED with the harnesses (HD-386 + decision #26, 2026-09-17):** headscale preauth keys for the `dsh` / `pi-dev` tailscale sidecars. Both harnesses were removed by the owner and their `docker_services` rows are `enabled: false`, so nothing renders them; the values are still in the provisioner catalog + the NOT_AUTO_ROTATABLE guard. Kept as a tombstone so a re-onboarding can mint fresh keys; do **not** seed them as a prerequisite. |
| `home-assistant_api` | `api` → `credential` = LiteLLM virtual key `sk-…` | **DOES NOT EXIST YET — record authored 2026-09-26 (HD-384), consumed by HD-403.** Home Assistant's own scoped key for the Assist LLM leg: allow-list is the single row `spark/qwen3.8-flash-next` (never a `spark/*` wildcard), no `max_budget`, `rpm: 30` (the implementer's number — the owner decided small caps stay, not a figure). Glue-minted by `lan-litellm`, which runs on oldsrv with the write-scoped op token; while that box is down `bootstrap_keys` stays false, so nothing here may render this item. ⚠ **Consumption path (HD-403, established 2026-09-26):** no template ever renders it. HA's stock `litellm` integration stores the value in a **config entry** — plaintext `/config/.storage/core.config_entries` on the Pi — and `roles/home_assistant/templates/ha-config-sync.sh.j2` rsyncs that directory (`--delete`, excluding only `secrets.yaml`) to the oldsrv standby, so **the minted key replicates off the primary** and rides whatever backs the standby. ⏳ **Owed before the HA entry is created:** an explicit accept/mitigate ruling on that replication, recorded here; until it lands, do not read "it is only ever rendered from the vault" as the protection this item usually carries (CONVENTIONS §6 secret hygiene). |
| ~~`dsh_api`~~ | ~~`credential`~~ | **RETIRED 2026-09-26 (HD-383).** DSH (the DeepSeekHarness coding harness) is a REJECTED LiteLLM consumer — decision #26 + HD-386 — so this item is neither restored nor re-minted. The stale VPS-DB-era bearer is now **cleared in the vault** (measured empty 2026-09-26; the item itself is kept, because a parked consumer is not a deleted secret). ⏳ **Owed on oldsrv:** the **LAN** gateway still holds the orphaned virtual key with alias `dsh` — deleting it is a LAN Admin UI action on `llitellm.kogler.si`, unreachable while oldsrv is down (HD-455). The name stays documented deliberately: `roles/docker_services/defaults/main.yml` still maps the parked `dsh` service to it, and `scripts/check_vault_docs.py` fails an IaC-referenced item that this table does not document. |
| `nut_password` | `password` | NUT UPS monitor (upsmon client → master auth) |
| `nut-exporter_password` | `password` | nut_exporter → upsd read-only auth (dedicated `upsmon slave` user on the NUT master) |
| `network-snmp_api` | `credential` | router + switch — MikroTik SNMP **read-only community** for Alloy polling (HD-53/Option A); `credential` = the RO community string |
| `mikrotik-logpipe_api` | `password` | router — **scoped read-only RouterOS API user `logpipe`** (HD-313): remote syslog/API read for log shipping + central monitoring; `password` = the user's password. `read` group = read-only to all config paths, no write. Mgmt-VLAN only. (Superseded 2026-09-09: the n8n firmware window HD-312d is closed — permanent `wan_allow` covers firmware WAN.) |
| `mikrotik-n8n_api` | `password` | router — **scoped read-only RouterOS API user `n8n`** (HD-312(4)): provisioned for the n8n firmware-workflow automation; `password` = the user's password; Mgmt-VLAN only. **Superseded 2026-09-09:** the temp `iot-wan-allow` flow is not needed (permanent `wan_allow`), the user stays provisioned for future admin uses. |
| `wg_password` | `password` | router (WireGuard S2S private key — router side, distinct per-side, HD-285) |
| `wg_password_vps` | `password` | VPS (WireGuard S2S private key — VPS side, distinct per-side, HD-285; NEW 2026-09-02) |
| `wifi-kogler_password` | `password` | CAPsMAN SSID **Kogler** (VLAN 10 Home) — router role when `routeros_capsman_enabled` flips true (HD-228/HD-03); alphanumeric only, 2.4 GHz-friendly chips on this SSID family (HD-228) |
| `wifi-kogler-iot_password` | `password` | CAPsMAN SSID **Kogler IOT** (VLAN 20 IoT, no internet) — Gen1 Shellys live here |
| `wifi-kogler-iot-wan_password` | `password` | ~~CAPsMAN SSID **Kogler IOT WAN** (VLAN 21 IoT-Internet)~~ — **SSID DELETED 2026-09-03 (HD-312):** IOT-WAN collapsed into Kogler IOT; cloud-IoT (Bosch/LG) WAN via `iot-wan-allow` MAC list (phase 3). **VLAN 21 itself DELETED 2026-09-04 (HD-325)** — cloud-IoT moved to VLAN 20 + `wan_allow` flag. Item kept in 1Password (no longer referenced by any config). |
| `wifi-kogler-guest_password` | `password` | CAPsMAN SSID **Kogler guest** (VLAN 30 Guest, 5GHz, client-isolated internet-only) — live 2026-09-03 |
| `wifi-kogler-kids_password` | `password` | ~~CAPsMAN SSID **Kogler Kids** (VLAN 40 Kids, filtered DNS + bedtime block HD-182)~~ — **SSID DELETED 2026-09-03 (HD-312):** kids-control migrates to the firewall MAC-address-list (`kids-*`, phase 3) with the family devices on Kogler/VLAN 10. Item kept in 1Password (no longer referenced by any config). |
| `tube-archivist_login` | `credential` | Tube Archivist (HD-362) **web-UI login** (username in `username`; the archive UI's password) — separate from `tube-archivist_api` (used by the Jellyfin plugin) and `tube-archivist_ui`. **PLACEHOLDER** created 2026-09-14 so the (deploy-gated) converge renders; OVERWRITE with the real password set in the Tube Archivist first-run wizard (http://10.10.1.30:8000) after deployment. |
| `tube-archivist_ui` | `credential` | Tube Archivist (HD-362) **UI/API token** — used by the TubeArchivist plugin in Jellyfin (`/api/token/`); optional at deploy (only if the Jellyfin plugin is used) |
| `tube-archivist_api` | `credential` | Tube Archivist (HD-362) **API key** for the Jellyfin plugin — OPTIONAL (Jellyfin plugin later; NOT required by the compose — docs-only for now) |
| `tube-archivist-es` | `username`=`elastic` + `password` | **Elasticsearch `elastic` bootstrap password** (`ELASTIC_PASSWORD` on BOTH the archivist-es container and the app) — catalog-generated 2026-09-14; the TA bootstrap env-check requires it. Applies only while `tube-archivist` is `enabled: true`; the service is **DISABLED + torn down 2026-09-15**, so it is not a live oldsrv prerequisite today. |
| `lidarr-url-dl_login` | `username`+`credential` | **Lidarr-YouTube-Downloader** web-UI login — entered in its Settings page at first run; reference-only (not fetched by compose) |
| `lastfm_login` | `username`+`credential` | **Last.fm** account for Aurral's discovery history (user + API key / password) |
| `metabrainz_login` | `username`+`credential` | **ListenBrainz** (Metabrainz) account for Aurral's discovery history |
| `slskd_login` | `username`+`credential` | **Soulseek** account (username/password) for slskd — Soulseek network login; `soulseek_api` token used for the slskd UI auth. NB the item is named `slskd_login` (matches the template + registry); a duplicate `soulseek_login` item exists from an earlier seed and can be deleted. `soulseek_api` is a PLACEHOLDER (created 2026-09-14) — overwrite with the slskd UI token (Options→Web UI→Token, http://10.10.1.30:5030) after deploy.
| `mikrotik-admin_login` | `password` | router + switch + APs — MikroTik RouterOS admin (items RB4011/CRS328/hAP; **shared across all network gear — accepted, HD-165**). One admin password across all gear is an **accepted risk**: every RouterOS management surface binds to the Management VLAN (99) only — router `api`/`www-ssl`/`ssh` (8728/443/22) are `interface=vlan99-mgmt`; switch + APs are L2-only with no WAN egress — so the shared credential never crosses the internet boundary ([network-ops.md](network-ops.md)). Revisit per-gear items only if a gear gains WAN-exposed management or the Mgmt-VLAN INPUT ACL changes. |
| `pppoe_login` | `password` (`username` = PPPoE user) | router — ISP (Telekom) PPPoE credentials for the egress WAN |
| `cloudflare_api` | `credential` | ACME **DNS-01** wildcard `*.kogler.si` cert. Token IP filter: use **EXACT addresses only** — CIDR rows (/22, /64) proved unreliable on API-token filters (Wave-3 R5); VPS set = `159.195.111.66` + `2a0a:4cc0:60:fcc:d820:9dff:fe4f:95f5` (stable SLAAC), runner = home v4/v6 |
| ~~`kopia-s3_api`~~ | ~~`credential` (S3 access key)~~ | **retired (HD-31): iDrive e2 S3 dropped.** Kopia now targets the **backup Box over SSH/SFTP (port 23)** — SSH-key auth via `Hertzner-SB-Backup`, repo password via `kopia_password`. No S3 credential item needed. |
| `op_api` | `credential` | 1Password Service Account token → **Forgejo Actions** (deploy button). **Note (HD-140):** the Ansible runner uses the separate `Service Account Auth Token: ansible` in a **Private vault** instead of this item — see [1password.md](1password.md). `op_api` is the token storage slot for Actions; it is NOT created for the runner's CLI lookup. (Doco-CD half removed — Doco-CD dropped, HD-150.) |
| `signal_api` | `credential` (`username` = phone number) | signal-cli-rest-api (linked-device pair / captcha) |
| `signal-internal_api` | `credential` | signal-cli-rest-api — API token auth (`SIGNAL_CLI_API_TOKEN`; requests require `X-Api-Key` header) so no container on services-internal can send Signal as Domen's number without it (KOPS-002 / HD-125). n8n sends this in its webhook call |
| `kopia-server-internal_api` | `username` + `credential` | kopia-server auth (HD-59/HD-318a) — `username` = the server-admin `user@host` identity (htpasswd + UI), `credential` = password; the per-client `oldsrv-agent@oldsrv.kogler.si` entry (`kopia_agent_user`, group_vars) shares the same credential. Written to the in-container `server.htpasswd` (plaintext, 0600); the repo-user password is the **repo master password** (`kopia_password`), not this credential (kopia quirk, verified 2026-09-08). Replaces the old `--without-password` |
| `victoria-metrics_api` | `username` + `password` | **VictoriaMetrics basic auth (HD-341/342)** — new item for the Victoria* migration; replaces the retired `prometheus-internal_api`. `username` + `password` only (Victoria's `-httpAuth.username` / `-httpAuth.password` are plaintext basic-auth, NOT bcrypt). Consumed by Grafana (VM datasource, uid `prometheus`) + Alloy remote_write + the oldsrv `mcp-victoriametrics` MCP server over the tailnet. Catalog-generated (`scripts/provision-secrets.py`), rotatable; seed BEFORE the Victoria converge (`provision-vault.sh`). |
| `victoria-logs_api` | `username` + `password` | **VictoriaLogs basic auth (HD-341/342)** — new item for the Victoria* migration; replaces the Loki unauthenticated endpoint. `username` + `password` only (VictoriaLogs `-httpAuth.username` / `-httpAuth.password` plaintext). Consumed by Grafana (VictoriaLogs datasource, uid `loki`) + Alloy log push + the oldsrv `mcp-victorialogs` MCP server over the tailnet. Catalog-generated, rotatable; seed BEFORE the Victoria converge. |
| `technitium_login` | `password` (`username` = the admin user) | **Technitium DNS admin credential — consumed by the `technitium-seed` role on ALL THREE instances** (VPS primary / oldsrv secondary / Pi tertiary). **Human-gated by construction:** the app seeds `admin`/`admin` on a fresh volume (deleting `auth.config`/`cache.bin` does NOT reset it), so the operator must set the admin to THIS value through the documented `POST /api/user/changePassword` API **before** the first seed run, or the seed's login fails and no split-horizon record is ever created. NOT catalog-generatable and NOT auto-rotatable: one value must match three instances, and rotation = re-apply on each. Catalog gap found 2026-09-19 while auditing the ledger prerequisites (the seed task reads it at `roles/docker_services/tasks/technitium-seed.yml`). Runbook: [deployment-manual.md](../deployment-manual.md) §DNS admin bootstrap · spec: [network-dns.md](network-dns.md) |
| `technitium_api` | `credential` | Technitium — **declared prerequisite only.** It is listed in `_service_vault_items.technitium` (so `check-vault-items.sh` demands it), but **no task looks it up**: the seed role authenticates with `technitium_login` (username+password) and nothing reads an API key. Either wire it (if Technitium ever gets a token-auth path) or drop the entry from `_service_vault_items` — until then it is a required-but-unused item, same class as the `op_api` runner question in [deployment-ai-stack-secrets.md](deployment-ai-stack-secrets.md) §4a. |
| `crowdsec-webui_lapi_api` | `credential` | CrowdSec Web UI LAPI **watcher machine** password (HD-272) — `docker exec crowdsec cscli machines add crowdsec-web-ui --password '<credential>' -f /dev/null` (deploy-gated owner step). Separate from the `crowdsec-bouncer_api` bouncer key. url-safe token, rotatable (not externally-coupled). |
| `immich-ml-internal_api` | `credential` | **ML API-key auth (HD-160)** — shared secret between `immich-app` (sends as ML-auth header) and `immich-ml` (validates it). Fail-loud (HD-65). Exact Immich v3 env var names deploy-verified. |
| `openclaw-opencloud_api` | `username` + `credential` | **OpenClaw → OpenCloud WebDAV (HD-160)** — `username` = OpenCloud service user, `credential` = app-specific password; consumed by `openclaw onboard` / `openclaw.json` WebDAV block. Scoped, rotatable, fail-loud. |
| ~~`doco-cd_password`~~ | ~~`password`~~ | **retired (HD-150): Doco-CD dropped** — single Ansible-only deploy/upgrade path. No webhook HMAC needed. |
| `sonarr_api` | `credential` | Sonarr API key — recyclarr syncs quality profiles from this instance. **HD-318:** catalog-created placeholder at Phase-3 seed; OVERWRITE with the instance's real `config.xml` ApiKey after first boot (manual-value class), then re-run recyclarr. **NOT auto-rotatable** (externally-coupled to the running instance). |
| `radarr_api` | `credential` | Radarr API key — recyclarr syncs quality profiles from this instance. **HD-318:** catalog-created placeholder at Phase-3 seed; OVERWRITE with the instance's real `config.xml` ApiKey after first boot (manual-value class), then re-run recyclarr. **NOT auto-rotatable** (externally-coupled to the running instance). |
| `lidarr_api` | `credential` | Lidarr API key — **music-pillar apps use it** (Aurral → Lidarr; Lidarr-YouTube-Downloader → Lidarr). **HD-362:** PLACEHOLDER seed created 2026-09-14 so the converge renders; OVERWRITE with the instance's real `config.xml` ApiKey (on oldsrv `/srv/docker/lidarr/config/config.xml`) after first boot, then re-run recyclarr. Same manual-value class as sonarr/radarr_api. **NOT auto-rotatable** (coupled to the running Lidarr instance). |
| `lidarr-url-dl_login` | `username`+`credential` | **Lidarr-YouTube-Downloader** (HD-362) web-UI login — entered in its Settings page at first run (no env-var auth upstream) |
| `pihole_password` | `password` | ~~Pi-hole admin UI~~ — **RETIRED 2026-09-10** (pihole → Technitium Advanced Blocking); item kept provisioned for re-enable |
| `matrix_api` | `credential` (`username` = client_id) | Tuwunel Matrix — Authentik OIDC client (`client_id` = username, `client_secret` = credential); callback URI registered in Authentik provider |
| `matrix_password` | `password` | Tuwunel Matrix — `registration_shared_secret` (bootstrap via `/_synapse/admin/v1/register`; keep a copy with the server identity/backups — HD-49) |
| `n8n_password` | `password` | n8n — `N8N_ENCRYPTION_KEY` (workflow encryption; long-lived, immutable — rotating means re-encrypting stored credentials). NOT used for webhook auth (see `n8n-webhook_api`) · HD-77 |
| `n8n-webhook_api` | `credential` | n8n — webhook/API auth token (`N8N_BASIC_AUTH_PASSWORD`; Grafana webhook contact point `basicAuthPassword`) — independently rotatable short-lived token so the encryption key is never exposed in webhook auth (KOPS-031 / HD-77). HTTP basic auth user = `grafana` |
| `n8n_api` | `credential` | **n8n — public REST API key** (Settings → n8n API; JWT `X-N8N-API-KEY`; HD-347). Used to provision/activate the `homelab-alerts` alert-router workflow (`POST /api/v1/workflows` + `/activate`) instead of a manual UI import — the workflow JSON is versioned in `roles/monitoring/files/n8n/`. Created by owner 2026-09-09; **rotatable** — regenerate in the n8n UI + update this item (rotation precedent 2026-09-09: key leaked in a transcript, rotated same day). |
| `openrouter_api` | `credential` | **AI stack** — LiteLLM: all external LLM generation (OpenRouter). Single key reused across every LLM consumer (Open WebUI, OpenClaw); only LiteLLM sees it. **Second consumer since 2026-09-23:** the pi harness's own `~/.pi/agent/auth.json`, rendered by `scripts/render-pi-config.py` (HD-388) — rotating it now also needs a re-render on every client, not just a LiteLLM restart. ⚠ Duplicate-title hazard, measured the same day: two items were named `openrouter_api` in this vault at once (owner removed one) — see §Item titles are load-bearing below. |
| `entrim_api` | `credential` | **AI stack — client-side** — Entrim (hosted, cost-bearing) bearer for the pi harness's `providers.entrim.apiKey`. Minted 2026-09-23 by the owner to retire the last key that lived only inside a hand-kept `models.json`; the value hash-matched the one already on the laptop, so `scripts/render-pi-config.py` adopted it as a no-op (HD-388). **Recyclable** — replace in Entrim's console, update this item, re-render each client. |
| `opencode-go` | `credential` | **AI stack — client-side** — opencode-go provider key for the pi harness's `~/.pi/agent/auth.json` (HD-388, vendor `pi-auth`). Recorded 2026-09-23; previously hand-kept with no vault item at all. **Recyclable** at the provider, then re-render. |
| `spark-llm_api` | `credential` | **AI stack** — spark's engine bearer key (HD-370): vLLM/SGLang `--api-key` on the `llm.kogler.si` OpenAI-API. The spark name edge + both LiteLLMs' spark model entry authenticate with it. **First vault item for the spark node** (was vault-free by design); catalog-created (`provision-secrets.py`). |
| `spark_login` | `password` (`username` = `admin`) | **DGX Spark (GB10) first-boot admin account** — the password chosen in the NVIDIA/DGX OS setup wizard on first power-on (a human at the display + keyboard). **Not consumed by Ansible** (the automation identity is `ansible-admin` via `ansible-admin_ssh`), so per the two-vault model it lives in the **Homelab (human)** vault as a console/break-glass credential for a re-provision or KVM recovery. Set during [deployment-manual.md](../deployment-manual.md) §spark first-boot. |
| ~~`cohere_api`~~ | ~~`credential`~~ | ~~**AI stack** — LiteLLM: Cohere **embed-v4 multilingual** (embeddings only).~~ **RETIRED 2026-09-06 (decision #23)** — embed/rerank local on oldsrv RX 7600 via Ollama `:rocm` (decision #24). Item may be deleted from 1P. |
| `litellm_api` | `credential` | **AI stack** — LiteLLM master key that Open WebUI + OpenClaw use to authenticate (they never hold upstream keys). |
| `openwebui_secret` | `password` | **AI stack** — Open WebUI session/encryption secret (optional). |
| `openwebui_api` | `credential` (`username` = client_id) | **AI stack** — Open WebUI **Authentik OIDC client** (`client_id` = username, `client_secret` = credential); redirect URI `https://ai.kogler.si/oauth2/callback` registered in the Authentik provider (HD-101) |
| `qdrant_db` | `credential` (API key; no username) | **AI stack** — Qdrant hybrid vector store (HD-268, replaces PGVector). Rebuildable cache (docs/services-ai.md §5b); single static API key served via `QDRANT__SERVICE__API_KEY`. No db-backup DBxx block (not Postgres). |
| `pi-harness_forgejo_api` | `credential` | **AI stack / dual harness (HD-268c)** — pi.dev Forgejo service-account **PR-only** token (propose-via-PR, NO merge, no FS access). Issued by the Forgejo UI; NOT_AUTO_ROTATABLE. |
| `dsh_forgejo_api` | `credential` | **AI stack / dual harness (HD-268c)** — DSH Forgejo service-account **PR-only** token (propose-via-PR, NO merge, no FS access). Issued by the Forgejo UI; NOT_AUTO_ROTATABLE. |
| `openclaw_gateway_token` | `password` | **AI stack** — OpenClaw gateway/Control-UI auth token (HD-104); generated by `openclaw onboard`, stored here fail-closed |
| `openwebui_api` *(see runbook)* | — | AI-stack OIDC wiring + full item-creation checklist: [`deployment-ai-stack-secrets.md`](deployment-ai-stack-secrets.md) (HD-105) |

> Entity naming: each item is a single `<service>_<type>` name with one `_` delimiter. The countable
> catalog (auto-generated + human-gated items) lives in [`../../scripts/provision-secrets.py`](../scripts/provision-secrets.py)
> (`--list`) — counts are derived, never hand-entered (CONVENTIONS §2).
> Future / not-yet-created: `n8n-smtp_login` (SMTP relay — provider not chosen yet, see deployment.md), `ha_mqtt` / `ha-mqtt_login` (if MQTT added to HA), `proxmox_root` / `proxmox_login` (Phase 2).

### Item titles are load-bearing — they are the primary key

1Password resolves items **by title** for every consumer here (`op read op://vault/item/field`,
`op item edit "$item"`), so a title is a foreign key even though nothing enforces it. Two failure modes
were measured on 2026-09-23 by sweeping `op item list` against the consumers:

* **Duplicates.** Two items named `openrouter_api` existed in `Homelab-ansible` at once (different ids, same
  vault). Every title-based lookup resolves to *one* of them, so a rotation can write the copy nobody reads
  — the same shape as the two live `op_api` tokens in [1password.md](1password.md): a secret that exists
  twice is a secret that rotates once and then lies about it.
* **Dirty titles.** `authentik-secret-egress.sh` built item names from a hard-coded `PROVIDERS` array and one
  entry carried a trailing comma, so `op item edit` failed on `metabase_oidc,` and the fall-through
  `op item create` **minted it** — and reported success, four times across 18 days, while the real item sat
  untouched. The general failure mode is the keeper: a create that lands beside a name the fleet already
  owns is invisible to "write-only-if-changed" logic, so the sync rots quietly. The glue now validates every
  `slug:item` against `^[a-z0-9][a-z0-9_-]*$` before any `op` call and fails loud; any script that builds
  item names from a list owes the same check (`scripts/provision-secrets.py` included).

**Read-only sweep** (prints counts, never values):

```bash
op item list --format json | python3 -c "import json,sys,re,collections; c=collections.Counter(i['title'] for i in json.load(sys.stdin)); print('dups :', {k:v for k,v in c.items() if v>1} or 'none'); print('dirty:', [k for k in c if not re.fullmatch(r'[a-z0-9][a-z0-9_-]*', k)] or 'none')"
```

Measured 2026-09-23 on `Homelab-ansible` (118 items): `dups: none`, and `dirty:` reports
`admin @dns.kogler.si` and `Hertzner-SB-Data` — **both known-legit human-named items**, not glue output.
The pattern is deliberately stricter than reality because the titles that matter are machine-written;
the two above are the accepted exceptions, so leave them and watch for anything *new*.

**What verifying that fix looks like (measured 2026-09-23).** The full VPS `docker_services` converge
(`ok=330 failed=0`) runs the glue (15.3 s) and mints **nothing** — the sweep above returns exactly one clean
`metabase_oidc` (the four phantom items being owner-deleted by then), and the deployed copy on the VPS is
byte-identical to the template (`md5 d1ccc0d4…`, `bash -n` clean), so the guard is live, not just committed. The signature that separates "written and
rotating" from "a duplicate sitting beside the real item": `updated_at == created_at` (here both
`2026-08-22`) means the item was **never** written, which is what a permanently-failing `op item edit`
with a successful `op item create` fall-through looks like from the outside.

**Retiring a service out of Authentik (HD-447, executed 2026-09-25).** The owner's ruling was **delete the
live objects, keep the IaC disabled**: the objects come out of the RUNNING Authentik while the repo keeps its
(disabled) declaration, so the revival path survives. Four standing rules fall out of doing that safely:

- **Disable it in the registry first; comment a blueprint block out only where the disable flag cannot reach
  it.** `enabled: false` keeps both the IaC and the revival path. Commenting is the fallback, not the
  mechanism, because an edit that leaves a dangling `!KeyOf` behind fails the **whole** blueprint
  (`blueprints/*.yml` are `copy:`d unrendered) — an **IdP** outage rather than one service's. The same care
  applies to `outpost_embedded`: one shared object, so retire a service's entries, never the object.
- **A blueprint apply is an UPSERT: removing an entry does NOT delete the server-side object.** Deletion is a
  separate, explicit pass through the Authentik API / `ak shell` — AI work, not a human hunt-and-peck — run
  with an exact-name allowlist plus two asserts: the expected set is present, and no OTHER application rides
  those providers.
- ⚠ **Blueprint ids are not object names.** This service's providers are `provider_edge_sec*` /
  `edge-sec-ts` in the blueprint but live in the DB as `forward-sec` and `forward-sec-ts` (and
  `provider_metabase`/`app_metabase` are the DB's `Metabase`), so a search for `edge-sec` returns nothing and
  invites a second, unnecessary deletion pass. Query the DB for `name`/`slug`, not for the blueprint id.
- **Acceptance is a read, not a claim:** re-render the scoped blueprint set (the retiring comments replacing
  the object blocks prove the render), apply `playbooks/authentik-blueprints.yml` to `changed=0 failed=0`,
  then take the same read again and confirm **nothing re-minted**. The one real `authentik Embedded Outpost`
  — shared by every Forward-Auth route in the fleet — stays untouched by any such pass.

Deleted 2026-09-25 and verified by that read: **3 applications** (`Metabase`, `Metabase (edge)`,
`Metabase (tailnet ts)`) and **3 OAuth2 providers** (`metabase`, `forward-sec`, `forward-sec-ts`), plus the
dormant `metabase_oidc` vault item, which the owner **deleted from the vault on 2026-09-26** — the retirement is
complete on both sides now. It was safe to remove because its egress entry is
`{% raw %}{% if _enabled.get('metabase', false) %}{% endraw %}`-gated, so it renders nothing while
`enabled: false` (the gate, not the name-shape guard, is what makes it inert).

⚠ **A Cloudflare record is an owner step from anywhere but home:** the `cloudflare_api` token is IP-filtered
to the home WAN, so no away session can delete a public record (`sec.kogler.si` went by owner hand for that
reason alone).

A hard-coded provider list that outlives the service is how this defect stayed invisible: the **list**, not
the fleet, decides what gets synced.

---

## Rename Map (legacy → canonical)

| Legacy (before) | Canonical (now) |
|-----------------|-----------------|
| `admin_laptop_ssh_pubkey` | `domen_ssh` |
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
| ~~`vps-op-write_api`~~ | `op-write_api` (renamed in place 2026-09-19; the old title is DELETED — a stale reference 403s) |
| ~~`prometheus-internal_api`~~ | **retired with Prometheus/Loki (HD-341/342)** → `victoria-metrics_api` + `victoria-logs_api` (plaintext basic auth, not bcrypt) |

| `signal_api_*` | `signal_api` |

> `nut_smtp_server` (relay host, not a credential) is **config** — it lives in `group_vars`, not
> 1Password. `wildcard_cert_file` / `wildcard_cert_key_file` are cert filenames, not secrets.

---

## SSH Key Separation

Three independent ED25519 keys, one per purpose. Separate keys = revoke/rotate one without affecting the others, and audit which key was used.

| Key (1Password item) | Authorized user on hosts | Access level |
|----------------------|--------------------------|--------------|
| `domen_ssh` (item **renamed by the owner 2026-09-25** from `laptop-domen_ssh`; the script + doc references moved in the same change) | `domen`, on **every** node | Human seat — **decided:** `sudo` group, **password-required, no NOPASSWD**, credential in a `domen_login` item (the HD-361 break-glass precedent) |
| `ansible-admin_ssh` | `ansible-admin`, on **every** node | Full (NOPASSWD sudo) — the converge key, and the only account IaC needs |
| `ai_ssh` (private maps to `openrouter_ai`) | `ai-debug`, on **every** node | Debug only — **no sudo group, no 1Password/op access**, LAN-only, no forwarding |

**Decided 2026-09-25 (HD-443), and this table's shape is the decision, not an observation:** the human key
becomes an **account** (`domen`) rather than a second key under the automation account; the AI account is
fleet-wide with no sudo; the Pi uses the same `ansible-admin` shape as every other host. The 1Password rename **was executed by the owner on 2026-09-25** and the four script references
(`check_ssh_grants.py`, `gen-custom-script.sh`, `gen-media-post-install.sh`, `get-bootstrap-keys.sh`)
plus every doc row moved in the same change — a rename that spans item + scripts in one window is the
only safe form, because a script reading the old item name breaks every bootstrap path mid-flight.
⚠ **Laptop-side tail (owner, not AI-doable):** rename the SSH-agent stub `~/.ssh/laptop-domen.pub` →
`~/.ssh/domen_ssh.pub` and point `IdentityFile` at it — the 1Password agent matches by item name, so a
stale stub makes `ssh` offer nothing and report `invalid format`.

**Not "the same keys everywhere" — measured per host (2026-09-22 sweep, `scripts/check_ssh_grants.py`).**
The three vault keys did **not** all ride on every host: `ansible-admin_ssh` is on all five managed
hosts; `domen_ssh` is on nas · oldsrv · spark · vps but **not the Pi**; `ai_ssh` is on
nas · oldsrv only, and only as `ai-debug`. **⚠ That is the measured state, and the gap between it and the
table above is live drift, not a decision** — the fleet-wide `domen` / `ai-debug` placement is owed by
HD-443's IaC work, and today **no role owns the user+key layout** (preseed and `first-boot-config.sh`
write it once, imperatively), which is why it drifted at all. No vault key is authorized on the HA guests.
The guests (`haos-vm-1`, `haos-mininta`) are **not swept** — their short names do not resolve from any host
the sweep can drive (`ssh ansible-admin@haos-vm-1` → "Could not resolve hostname"), and **the owner accepted
that scope on 2026-09-25**: they are outside the audit set, which is a declared limit, **not** a clean bill
(HD-416 tail). Placement and verdicts live in one place: §Who is authorized where below, machine-checked.

**AI access is safe because it is a different user.** The AI key can never log in as `ansible-admin` (which has passwordless root). The `ai-debug` authorized_keys line is injected by `post_install.sh`:

```
restrict,no-agent-forwarding,no-port-forwarding,no-X11-forwarding,from="10.10.0.0/16" ssh-ed25519 <AI_PUBKEY> openrouter_ai
```

**1Password SSH agent:** private keys never exist on disk — served on demand from the `Homelab-ansible` vault (Settings → Developer → SSH agent, socket path). Create the `.pub` reference files once in `~/.ssh/` (the agent reads them to identify items). Laptop `~/.ssh/config`:

```
Host nas nas-ansible nas-ai
  IdentityAgent <1Password SSH agent socket>

Host nas              # personal key
  User ansible-admin    # ⚠ becomes `domen` when HD-443 lands the accounts; until then the human key
                        #   is still authorized under ansible-admin (that is the drift being closed)
  IdentityFile ~/.ssh/domen_ssh.pub
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

### Who is authorized where — the grant inventory (swept 2026-09-22 by `scripts/check_ssh_grants.py`; first hand-swept 2026-09-21)

The three vault keys above are **not** the whole `authorized_keys` picture. Hand-made grants
exist on the boxes, nothing in IaC declares them, and there was no way to know without
sweeping every host. Fingerprints only, never key material (CONVENTIONS §6):

| Fingerprint | Identity | Where authorized | Verdict |
|---|---|---|---|
| `XTmK3tR…` | `domen_ssh` | nas · oldsrv · spark · vps → `ansible-admin` | vault-issued, live. **✅ Decided 2026-09-25: fleet-wide, but under `domen`, not `ansible-admin`** — spark is sanctioned as the `domen` seat; the 1Password item was renamed 2026-09-25, and moving the key off `ansible-admin` onto `domen` is HD-443's IaC step |
| `1uKzmwf…` | `ansible-admin_ssh` | every managed host → `ansible-admin`, **plus pi → `admin`** | vault-issued, the converge key (30 accepted logins on nas in 2 days). **✅ Decided 2026-09-25: `ansible-admin` is the Pi's admin surface.** ⚠ The second placement — `admin` on the Pi (uid 1000, `/etc/sudoers.d/admin` = `NOPASSWD:ALL`) — is **not** needed by IaC (`host_vars/pi.kogler.si.yml` sets `ansible_user: ansible-admin`), **✅ DECIDED 2026-09-25 (round 2): the owner needs no `admin` account at all** — the key comes off `admin` and the account is retired. ⛔ Order is the safety property: prove `ansible-admin` (then `domen`) can log in on the Pi → remove the key from `admin` → only then lock/remove the account. Never reverse it (HD-413 lockout set) |
| `Ug788c…` | `ai_ssh` | nas · **oldsrv** → `ai-debug` | vault-issued, scoped by HD-51. **✅ Decided 2026-09-25: sanctioned on every node** (`nas · oldsrv · pi · spark · vps`), no sudo, no op access; the `restrict,…,from=` options stay. Extending it to pi/spark/vps is HD-443 work |
| `DxoZeGK…` | `ha-sync@pi.kogler.si` | oldsrv · vps | hand-made, live (HA failover + cert pull), **no vault item** |
| `VX0TbLr…` | `traefik-cert-sync@oldsrv.kogler.si` | vps → `ansible-admin` | hand-made, live on a timer (HD-350), **no vault item** |
| `7ZuAhqI…` | `traefik-cert-sync@spark.kogler.si` | vps → `ansible-admin` | hand-made, live on a timer (HD-350), **no vault item** |
| `U+6vLRV…` | `oldsrv-rsync` | ~~nas → `ansible-admin`~~ | **retired 2026-09-21** (below); re-confirmed ABSENT on the 2026-09-22 sweep |

**This table is a machine-checked gate, not prose (HD-416).** `python3 scripts/check_ssh_grants.py`
sweeps every `authorized_keys` + `/root/.ssh/authorized_keys` on the managed hosts (`ssh` +
`ssh-keygen -lf`, read-only), derives the named set from THIS table plus the vault public halves
(`domen_ssh` / `ansible-admin_ssh` / `ai_ssh`), and exits 1 unless named ≡ live. It reds on
`UNKNOWN` (live key nobody named), `RETIRED-BUT-PRESENT`, `WRONG-ACCOUNT` (a named key under an
account the table does not name — the exact shape of the `oldsrv-rsync` finding), `UNPLACED` (a key
on a host the table does not name) and `AMBIGUOUS` (two identities matching one key — reported, never
guessed away). `--self-test` scores fixtures offline, including the false readings the live run
caught in the checker itself; `--dump` keeps a dated capture. Run it before and after any grant
change; it revokes nothing. The sweep set is the five managed hosts (`nas`, `oldsrv`, `pi`, `spark`,
`vps`) — **the HA guests are not in it and are therefore unaudited**; the owner accepted that scope
on 2026-09-25 (HD-443), and the acceptance changes the *wording*, not the truth: unaudited ≠ clean.

**Two claims this sweep disproved** (both were written as fact and both were wrong): "the same three
keys are authorized on **every** homelab host" — pi carries ONLY `ansible-admin_ssh`, and no vault
key is authorized on the HA guests; and the row's premise that `restore-runner-key.sh` "refuses
before it touches a thing" when the retired key is absent — on 2026-09-22 it refused **twice** with
"no `oldsrv-rsync` key to restore", which is the retired key still being treated as the expected
state. The script grew `--force-throwaway` for exactly that case; the box's own key went to
`id_ed25519.pre-restore-20260922-230051`, and the **grant stays retired** (the restore moved a
private file, it did not re-authorize anything). The `⏳ Delete both halves after one green backup
night` gate below is **unsatisfiable as written** — see that paragraph.

**The `oldsrv-rsync` retirement, in full, because it is the reason this section exists.**
oldsrv's `/home/ansible-admin/.ssh/id_ed25519` was a hand-made key with no vault item and no
IaC reference, and its public half authorized it as `ansible-admin` **on nas** — an account
that is `ALL=(ALL) NOPASSWD:ALL`. So the key was, in effect, "anyone holding oldsrv can root
the family data store". Evidence that nothing used it: the keypair's mtime is 2026-09-08
10:03:58; nas's `sshd` logged the first accepted login 5 seconds later and the last at 11:56
the same day; and the same journal shows 10 accepted-publickey logins in the two days before
this writing (30 of them the canonical runner key), so the silence after 2026-09-08 is
**disuse, not log rotation**. It was also redundant — `ansible-admin_ssh` is already
authorized on nas for the same account. Retired by commenting the entry out (backup:
`/root/authorized_keys.nas.pre-retire-20260921-011512`), then proven inert rather than
assumed: fresh `ansible-admin` auth to nas + `storage.yml --limit nas --check --tags common`
→ `ok=20 changed=0 failed=0`. **⏳ Delete both halves after one green backup night**
(`push-db-dumps` 03:35 / `push-services` 04:00 / `push-face-thumbs` 04:30 run as
`svc-backup` and rsync to a local tank path, so they were never the consumer — one night is
the proof, not the theory). Do **not** adopt it into the vault: adopting would promote a
one-time migration key to a managed secret, which is backwards.

**⚠️ The "one green backup night" gate cannot be met as written (measured 2026-09-22).** All three
push timers have been `Result=ERR` **since 2026-09-18** — before the key was retired on the 21st —
and for a cause with nothing to do with SSH: `rsync: chown3 … Operation not permitted (1)` from
`svc-backup` into `/srv/backups/nextcloud`, i.e. an ownership problem on the destination. Waiting
for green would hold an retired private key on disk indefinitely on a criterion that will not turn
green until a different row lands. The deletion decision belongs to **HD-122** (`push-db-dumps`
failures) / the owner; what HD-416 owns is the *grant*, and the grant is proven absent. Do not
"resolve" this by pointing the gate at an unrelated green timer, and do not delete the key while
those timers are red for whatever reason the owner decides.

**Retiring an SSH grant — the reversible sequence.** The characteristic failure of an SSH change
is being locked out by your own fix, so the order matters and each step is evidence, not opinion:

1. **Enumerate before touching anything.** Run `ssh-keygen -lf` per `authorized_keys` file on
   every host. A file stores the base64 blob, so grepping for a *fingerprint* matches nothing —
   that mistake cost a false "not authorized anywhere" reading on 2026-09-21.
2. **Establish disuse from the authorizing host's log**, not from memory:
   `journalctl -u ssh -u sshd | grep <fingerprint>`, and confirm the journal actually covers the
   interval you are claiming silence for — rotation or a reboot explains absence too.
   `atime` is not evidence: a read-only `grep -r` over the home directory updates it.
3. **Back up, then neutralize without deleting** — comment the line out with a dated marker.
   One line, instantly revertible.
4. **Prove inert with something you actually depend on:** a fresh `ssh` as that account plus one
   `--check` converge leg against that host. `failed=0` is the proof; "it looked unused" is not.
5. **Let the plausible consumers run one full cycle** (the backup timers, whatever is scheduled),
   then delete both halves — the private key on the holder, the line on the authorizer.
6. **Do not adopt a discovered key into the vault as the first move.** That promotes an unknown,
   often one-time key to a managed secret and makes it permanent. Retire it, and mint a named key
   only when a real job needs one.

**The rule this section carries forward:** a grant that is neither vault-issued nor named in
the table above does not exist as far as this repo is concerned — and that is precisely why a
grant has to be named here or removed. The four hand-made-but-live keys (`ha-sync`, the two
`traefik-cert-sync`, and any future one) are a standing decision, not an oversight: either
give them items and stop hand-making them, or accept that revocation depends on remembering
where they live. HD-416 is the gate for that.

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
