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
| **Resolved at deploy time** | Ansible templates call `lookup('onepassword', ...)` — secrets fetched at render time, never cached |
| **Doco-CD integration** | Service Account token with minimum-scope vault access. Secrets resolved at deploy, never on disk |
| **1Password CLI** | Installed on management laptop + Actions runner. `op` CLI + `OP_SERVICE_ACCOUNT_TOKEN` |
| **1Password SSH agent** | Private keys never on disk — served from `Homelab` vault on demand. See SSH Key Separation below |

---

## Secret Naming Convention

All secrets in `Homelab` vault. Pattern: `<service>_<type>`.

| Secret Name | Used By |
|-------------|---------|
| `admin_laptop_ssh_pubkey` | post_install.sh — personal key → `ansible-admin` |
| `ssh_ansible_pubkey` | post_install.sh — dedicated Ansible key → `ansible-admin` |
| `ssh_ai_pubkey` | post_install.sh — AI debug key (`openrouter_ai`) → `ai-debug` |
| `kopia_master_password` | kopia, kopia-agent, kopia-server |
| `authentik_pg_password` | authentik |
| `authentik_secret_key` | authentik |
| `opencloud_db_password` | opencloud |
| `immich_db_password` | immich-app |
| `forgejo_db_password` | forgejo |
| `grafana_admin_password` | grafana |
| `grafana_smtp_password` | grafana (SMTP fail-safe contact point) |
| `ha_exporter_token` | Prometheus → HA `/api/prometheus` bearer |
| `signal_api_*` | signal-cli (linked device) |
| `n8n_*` | n8n (webhook, SMTP) |
| `headscale_oidc_secret` | headscale |
| `ha_api_key` | home_assistant |
| `router_admin_password` | router |
| `wireguard_private_key` | router (S2S + road-warrior) |
| `forgejo_token` | Doco-CD (repo access) |
| `doco_cd_webhook_secret` | Doco-CD webhook |
| `doco_cd_op_service_account` | Doco-CD → 1Password |
| `cloudflare_api_token` | ACME **DNS-01** wildcard `*.kogler.si` cert |

---

## SSH Key Separation

Three independent ED25519 keys, one per purpose. Separate keys = revoke/rotate one without affecting the others, and audit which key was used.

| Key (1Password item) | Authorized user on hosts | Access level |
|----------------------|--------------------------|--------------|
| `admin_laptop_ssh_pubkey` (private: personal) | `ansible-admin` | Full (NOPASSWD sudo) |
| `ssh_ansible_pubkey` | `ansible-admin` | Full (NOPASSWD sudo) |
| `ssh_ai_pubkey` (`openrouter_ai`) | `ai-debug` | Debug only — no sudo, LAN-only, no forwarding |

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
  IdentityFile ~/.ssh/admin_laptop.pub
  IdentitiesOnly yes

Host nas-ansible      # dedicated Ansible key
  HostName nas
  User ansible-admin
  IdentityFile ~/.ssh/ansible.pub
  IdentitiesOnly yes

Host nas-ai           # AI debugging — tell the AI: "use ssh nas-ai"
  HostName nas
  User ai-debug
  IdentityFile ~/.ssh/openrouter_ai.pub
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
| **AI → homelab hosts** | Dedicated `ai-debug` user — LAN-only (`from=`), no agent/port/X11 forwarding; sudo limited to the `ai-diag` allowlist (read-only diagnostics, see below) |
| **Ansible → hosts** | Fail-closed guards (site.yml pre-flight + `common` role assert) — playbooks refuse to run as `ai-debug` or unknown users; sudo + docker group granted only to `ansible_admin_users` (`ansible-admin`, `pi`) |