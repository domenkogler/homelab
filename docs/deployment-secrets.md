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
- **No tribal knowledge** — if Domen is incapacitated, family + trusted tech contact can recover from 1Password + repo

---

## 1Password as Sole Secrets Backend

| Principle | Implementation |
|-----------|---------------|
| **One vault** | All secrets in `Homelab` vault |
| **Never in Git** | No `.env` files, no Ansible Vault, no hardcoded credentials |
| **Resolved at deploy time** | Ansible templates call `lookup('community.general.onepassword', ...)` — secrets fetched at render time, never cached |
| **Doco-CD integration** | Service Account token with minimum-scope vault access. Secrets resolved at deploy, never on disk |
| **1Password CLI** | Installed on management laptop + Actions runner. `op` CLI + `OP_SERVICE_ACCOUNT_TOKEN` |
| **1Password SSH agent** | Private keys never on disk — served from `Homelab` vault on demand. See SSH Key Separation below |

---

## Secret Naming Convention

> **The single source of truth for 1Password items.** Every secret lives in the `Homelab` vault.

**Item name pattern: `<service>_<type>`**

- `<service>` = the consuming service / role. May contain `-` (e.g. `ansible-admin`, `laptop-domen`, `grafana-smtp`, `kopia-s3`). **Never `_` inside the service name.**
- `_` is the **only** delimiter between `<service>` and `<type>` in the whole name.
- `<type>` = the 1Password **item type** (see map below) — it determines which field the lookup reads.
- **Never put the field in the item name** (e.g. `service-name-db-password` → `service-name_db`).

**Always pass `field=` in Ansible.** The `community.general.onepassword` lookup defaults to the `password` field, which is **NOT** always the value you want. Vault is the `op_vault` variable (defined once in `group_vars/all.yml` → `Homelab`), so a vault rename is a one-line change:

```yaml
lookup('community.general.onepassword', '<service>_<type>', field='<field>', vault=op_vault)
```

---

## Type Map — one per `<type>`, with canonical examples

| `type`       | 1Password item    | `field=`              | Examples |
|--------------|-------------------|-----------------------|----------|
| `login`      | Login             | `password`            | SMTP/SMTP-relay creds (`grafana-smtp_login`, `nut-smtp_login`), admin accounts (`mikrotik-admin_login`, `grafana_login`, `authentik_login`), any username+password combo |
| `password`   | Password          | `password`            | shared / opaque secrets with no username: webhook HMAC (`doco-cd_password`), VRRP (`ha-vrrp_password`), upsmon (`nut_password`), repo master (`kopia_password`), Django `SECRET_KEY` (`authentik_password`), WireGuard private key (`wg_password`), Matrix bootstrap shared secret (`matrix_password`) |
| `api`        | API Credential    | `credential`          | tokens & keys: Cloudflare (`cloudflare_api`), Forgejo (`forgejo_api`), HA long-lived (`ha_api`), HA failover trigger (`ha-failover_api`), headscale OIDC (`headscale_api`), 1Password service-account (`op_api`), signal-cli (`signal_api`), PrivadoVPN WireGuard client key (`privado-vpn_api`), Matrix/Authentik OIDC client (`matrix_api`), Meteoblue weather key (`meteoblue_api`) |
| `db`         | Database          | `password` (also `username`) | platform DBs: `authentik_db`, `opencloud_db`, `immich_db`, `forgejo_db` — Database item holds both `username` (DB user) and `password` |
| `ssh`        | SSH Key           | `private_key` / `public_key` | `laptop-domen_ssh`, `ansible-admin_ssh`, `ai_ssh` — item stores both halves; read whichever the consumer needs |

> **Guidance:**
> - `login` = anything with a **username** (admin accounts, SMTP relays). One Login item per service — e.g. a service that has both an admin login and an SMTP relay gets two items: `grafana_login` + `grafana-smtp_login`.
> - `password` = a shared/opaque secret with **no username** (tokens for HMAC/VRRP/upsmon, repo/SECRET keys).
> - `api` = a **credential/token/key** for an API (including S3 and service-account tokens). API Credential items use `username` for access-key/client-id where applicable and `credential` for the secret.
> - `db` = Database item (`username` + `password` fields). Field for postgres link/password is `password`.
> - `ssh` = SSH Key item (`private_key` + `public_key` fields). See SSH Key Separation below.

---

## Master Secret List (canonical)

| Item name | `field=` | Used By |
|-----------|----------|---------|
| `laptop-domen_ssh` | `private_key` / `public_key` | post_install.sh — Domen's personal key → `ansible-admin` |
| `ansible-admin_ssh` | `private_key` / `public_key` | post_install.sh — dedicated Ansible key → `ansible-admin` |
| `ai_ssh` | `private_key` / `public_key` | post_install.sh — AI debug key (maps to `openrouter_ai`) → `ai-debug` |
| `netcup-ccp_login` | `password` | netcup — **Customer Control Panel** login (item `netcup-ccp_login`, 1Password `Homelab`). Billing / orders / subscription management at netcup. **NOT** consumed by Ansible (SSH provisioning, see `ansible-admin_ssh`) — account reference only (netcup RS 2000 G12) |
| `netcup-scp_login` | `password` | netcup — **Server Control Panel (SCP)** login — per-VPS admin/console (reboot, reinstall OS, KVM/console access, root password reset). Root-level access to the box; **break-glass** fallback if SSH is unavailable. Ansible still authenticates via `ansible-admin_ssh` by default |
| `netcup-vps_login` | `password` | netcup — **root/OS access** to RS 2000 G12: root password + IPv4/IPv6 (`159.195.111.66` / `2a0a:4cc0:60:fcc:*`). **Deliberately in a SEPARATE 1Password vault (NOT `Homelab`) so Ansible cannot read it** — kept off the automation path for safety. Break-glass root fallback; day-to-day SSH is `ansible-admin_ssh` as `ansible-admin` |
| `Hertzner-SB-Data` | — (connection ref) | Hetzner Storage Box **live** (BX11 1 TB) — connection reference for CIFS/SMB + WebDAV (`u653411`, server `653411`, SSH/SFTP port 23); **SMB username + password** stored here and consumed by the **`cifs` role** (VPS live-Box mount `/mnt/storagebox`, field=`username`/`password`). Recorded under `subscriptions.yml` (`secret: Hertzner-SB-Data`) — see `subscription.md` "Hetzner Storage Box — live" |
| `Hertzner-SB-Backup` | — (connection ref) | Hetzner Storage Box **backup** (BX11 1 TB) — connection reference, **no password** (SSH-key auth). Holds URL/username (`u653424`, server `u653424`, SSH/SFTP port 23). Recorded under `subscriptions.yml` (`secret: Hertzner-SB-Backup`), not an Ansible lookup — see `subscription.md` "Hetzner Storage Box — backup" |
| `kopia_password` | `password` | kopia-server (repo master password) |
| `authentik_db` | `password` (`username` = DB user) | authentik (Postgres) |
| `authentik_password` | `password` | authentik (Django `SECRET_KEY`) |
| `authentik_login` | `password` | authentik (bootstrap admin user) |
| `authentik-api_token` | `api` | authentik — API token (read-only) used by the Authentik→NAS provisioning glue (`sync-authentik-users.sh`, D5/HD-131) |
| `authentik-ldap_bind` | `password` | authentik LDAP outpost token + Samba ldapsam **bind password** (D7/HD-132). The outpost `AUTHENTIK_TOKEN` and Samba `ldap admin password` both read `field=password`. Populated at deploy when the LDAP provider/outpost are created (see deployment-compose.md HD-132). |
| `opencloud_db` | `password` | opencloud (Postgres) |
| `minio_login` | `login` | MinIO S3 object store (HD-131 D1) — `username` = root user, `password` = root secret; S3 endpoint for Immich originals |
| `immich_db` | `password` | immich-app (Postgres) |
| `forgejo_db` | `password` | forgejo (Postgres) |
| `forgejo_api` | `credential` | doco-cd (`GIT_ACCESS_TOKEN`) + renovate (`RENOVATE_TOKEN`) — Forgejo token |
| `grafana_login` | `password` | grafana (admin user) |
| `grafana-smtp_login` | `password` | grafana (SMTP fail-safe contact point) |
| `ha_api` | `credential` | HA long-lived token → Traefik/Companion, `/api/prometheus` bearer for Prometheus |
| `ha-vrrp_password` | `password` | keepalived (VIP `ha.kogler.si`) shared auth |
| `ha-failover_api` | `credential` | HA failover trigger API (HD-17) — Homepage buttons + `ha-failover-api` token |
| `meteoblue_api` | `credential` | Home Assistant core `meteoblue` weather integration (HD-22) — Meteoblue model API key |
| `headscale_api` | `credential` | headscale (OIDC client secret; `username` = client id) |
| `nut_password` | `password` | NUT UPS monitor (upsmon client → master auth) |
| `nut-exporter_password` | `password` | nut_exporter → upsd read-only auth (dedicated `upsmon slave` user on the NUT master) |
| `nut-smtp_login` | `password` | UPS / scheduled-shutdown email notifications (SMTP; `username` = notify email + SMTP user) |
| `network-snmp_login` | `credential` | router + switch — MikroTik SNMP **read-only community** for Alloy polling (HD-53/Option A); `credential` = the RO community string |
| `wg_password` | `password` | router (WireGuard S2S private key) |
| `mikrotik-admin_login` | `password` | router + switch + APs — MikroTik RouterOS admin (items RB4011/CRS328/hAP; shared across all network gear) |
| `pppoe_login` | `password` (`username` = PPPoE user) | router — ISP (Telekom) PPPoE credentials for the egress WAN |
| `cloudflare_api` | `credential` | ACME **DNS-01** wildcard `*.kogler.si` cert |
| ~~`kopia-s3_api`~~ | ~~`credential` (S3 access key)~~ | **retired (HD-31): iDrive e2 S3 dropped.** Kopia now targets the **backup Box over SSH/SFTP (port 23)** — SSH-key auth via `Hertzner-SB-Backup`, repo password via `kopia_password`. No S3 credential item needed. |
| `op_api` | `credential` | 1Password Service Account token → Doco-CD + Forgejo Actions |
| `signal_api` | `credential` (`username` = phone number) | signal-cli-rest-api (linked-device pair / captcha) |
| `signal-internal_api` | `credential` | signal-cli-rest-api — API token auth (`SIGNAL_CLI_API_TOKEN`; requests require `X-Api-Key` header) so no container on services-internal can send Signal as Domen's number without it (KOPS-002 / HD-125). n8n sends this in its webhook call |
| `kopia-server-internal_api` | `username` + `credential` | kopia-server auth (HD-59) — `username` = the `user@host` identity backup clients present via HTTP Basic Auth, `credential` = password; written to the in-container `server.htpasswd` (plaintext, 0600). Replaces the old `--without-password` |
| `prometheus-internal_api` | `username` + `bcrypt_hash` | prometheus Basic Auth (HD-59) — `username` = user, `bcrypt_hash` = bcrypt hash for `basic_auth_users` (generate via `scripts/gen-htpasswd.py`). Grafana + Alloy consume this endpoint |
| `doco-cd_password` | `password` | Doco-CD webhook HMAC (`WEBHOOK_SECRET`) |
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

> Entity count: **36 items**, each a single `<service>_<type>` name with one `_` delimiter.
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
| `grafana_smtp_password` | `grafana-smtp_login` |
| `ha_api_key` / `ha_exporter_token` / `ha_prometheus_token` / `long_lived_token` | `ha_api` |
| `ha_vrrp_password` | `ha-vrrp_password` |
| `headscale_oidc_secret` | `headscale_api` |
| `upsmon_password` / `nut_upsmon_password` | `nut_password` |
| `smtp_notify_creds` / `nut_notify_email` / `nut_smtp_user` / `nut_smtp_pass` | `nut-smtp_login` |
| `snmp_ro_community` (snmp.yml.j2 auth) | `network-snmp_login` |
| `wireguard_private_key` | `wg_password` |
| `router_admin_password` | `mikrotik-admin_login` |
| `router_login` | `mikrotik-admin_login` |
| `cloudflare_api_token` / `cloudflare_api_token_credential` | `cloudflare_api` |
| ~~`s3_kopia_access_key` / `s3_kopia_secret_key` / `kopia_access_key` / `s3_kopia_secret`~~ → ~~`kopia-s3_api`~~ | **retired (HD-31/HD-135)** — iDrive S3 dropped; Kopia = SFTP to backup Box (see `kopia-s3_api` row) |
| `op_service_account_token` | `op_api` |
| `doco_cd_op_service_account` | `op_api` (single SA token for Doco-CD + Actions) |
| `doco_cd_webhook_secret` | `doco-cd_password` |
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

**1Password SSH agent:** private keys never exist on disk — served on demand from the `Homelab` vault (Settings → Developer → SSH agent, socket path). Create the `.pub` reference files once in `~/.ssh/` (the agent reads them to identify items). Laptop `~/.ssh/config`:

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
- **Doco-CD** — 1Password Service Account token (`op_api`), scoped to `Homelab` vault only
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
| **Doco-CD → Docker socket** | Mounts `docker.sock` read-write. Non-root container, `cap_drop: [ALL]` |
| **Doco-CD → Forgejo** | Git access token (`forgejo_api`, read-only on repo) |
| **Doco-CD → 1Password** | Service Account token (`op_api`) — minimum-scope `Homelab` vault access |
| **Actions runner → VPS** | Dedicated SSH key (separate from Domen's personal key) |
| **Actions runner → 1Password** | Service Account token (`op_api`) — stored as Forgejo secret |
| **Homepage → internet** | Protected by Authentik Forward Auth |
| **Renovate → Docker Hub** | Read-only registry access — no credentials for public images |
| **AI → homelab hosts** | Dedicated `ai-debug` user — LAN-only (`from=`), no agent/port/X11 forwarding; sudo limited to the `ai-diag` allowlist (read-only diagnostics, see below) |
| **Ansible → hosts** | Fail-closed guards (site.yml pre-flight + `common` role assert) — playbooks refuse to run as `ai-debug` or unknown users; sudo + docker group granted only to `ansible_admin_users` (`ansible-admin`, `pi`) |
