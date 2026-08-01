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
| **Resolved at deploy time** | Ansible templates call `lookup('onepassword', ...)` — secrets fetched at render time, never cached |
| **Doco-CD integration** | Service Account token with minimum-scope vault access. Secrets resolved at deploy, never on disk |
| **1Password CLI** | Installed on management laptop + Actions runner. `op` CLI + `OP_SERVICE_ACCOUNT_TOKEN` |

---

## Secret Naming Convention

All secrets in `Homelab` vault. Pattern: `<service>_<type>`.

| Secret Name | Used By |
|-------------|---------|
| `admin_laptop_ssh_pubkey` | post_install.sh (ED25519 public key) |
| `kopia_master_password` | kopia, kopia-agent, kopia-server |
| `authentik_pg_password` | authentik |
| `authentik_secret_key` | authentik |
| `opencloud_db_password` | opencloud |
| `immich_db_password` | immich-app |
| `forgejo_db_password` | forgejo |
| `grafana_admin_password` | grafana |
| `headscale_oidc_secret` | headscale |
| `ha_api_key` | home_assistant |
| `influxdb_token` | monitoring |
| `router_admin_password` | router |
| `wireguard_private_key` | router (S2S + road-warrior) |
| `forgejo_token` | Doco-CD (repo access) |
| `doco_cd_webhook_secret` | Doco-CD webhook |
| `doco_cd_op_service_account` | Doco-CD → 1Password |

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

- **SSH keys** — ED25519 key in 1Password, injected by post_install.sh
- **Ansible** — 1Password lookup at render time, no passwords in playbooks
- **Doco-CD** — 1Password Service Account token, scoped to `Homelab` vault only
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
| **Doco-CD → Forgejo** | Git access token (read-only on repo) |
| **Doco-CD → 1Password** | Service Account token — minimum-scope `Homelab` vault access |
| **Actions runner → VPS** | Dedicated SSH key (separate from Domen's personal key) |
| **Actions runner → 1Password** | Service Account token — stored as Forgejo secret |
| **Homepage → internet** | Protected by Authentik Forward Auth |
| **Renovate → Docker Hub** | Read-only registry access — no credentials for public images |