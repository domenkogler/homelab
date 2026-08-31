---
title: 1Password CLI & SSH Agent — runner setup
role: reference
domain: deployment
status: active
tags: [deployment, secrets, 1password, ssh]
---
# 1Password CLI & SSH Agent — WSL runner setup

> **Role:** Reference — how the WSL Ansible runner authenticates to 1Password: the CLI
> Service Account token (for `community.general.onepassword` secret lookups) and the SSH
> agent for key-based host access. Covers only the **runner** side; the vault/item naming
> conventions live in [`deployment-secrets.md`](deployment-secrets.md).
> **Links to:** `deployment-secrets.md`, `deployment-ansible.md`, `deployment.md`
> **Linked from:** `index.md`, `deployment-secrets.md`

---

## 1. Service Account token (Ansible secret lookups)

Ansible resolves every secret via
`lookup('community.general.onepassword', '<item>', field='<field>', vault=op_vault)`
on the **control host** (the WSL Debian runner). That lookup authenticates to 1Password
using a **Service Account token**, not an interactive login.

### Credential source
- **1Password item:** `Service Account Auth Token: ansible` (`ansible`).
- **Vault:** a **Private vault** (not the `Homelab-ansible` vault).
- **Why private:** keeps the automation service-account token out of the main secret
  vault (`Homelab-ansible`), limiting blast radius. This is a **deliberate deviation** from the
  `deployment-tasks.md`/`deployment-secrets.md` assumption that an `op_api` Service
  Account token item exists in `Homelab-ansible`. **That `op_api` item is intentionally NOT
  created.** The token for this runner lives in the private vault instead.

### Installed location (runner)
```bash
~/.config/op/homelab-sa-token      # 0600, one line: export OP_SERVICE_ACCOUNT_TOKEN='...'
```
- Sourced from `~/.bashrc` (`[ -f ... ] && source ...`).
- Ansible's `community.general.onepassword` lookup reads `OP_SERVICE_ACCOUNT_TOKEN`
  at run time — so it is non-interactive (no `op signin` / 2FA prompt).

### Service account scope
The service account must have **read access to the `Homelab-ansible` vault** (where the secret
items live) plus any private vault holding runner credentials. Verify:
```bash
op vault list                      # should list Homelab-ansible (and the private vault)
op whoami                          # shows User Type: SERVICE_ACCOUNT
```

### Install on a fresh runner (repo bootstrap convention)
```bash
mkdir -p ~/.config/op
umask 077
printf 'export OP_SERVICE_ACCOUNT_TOKEN=%q\n' 'PASTE_TOKEN' > ~/.config/op/homelab-sa-token
chmod 600 ~/.config/op/homelab-sa-token
[ -f ~/.config/op/homelab-sa-token ] && source ~/.config/op/homelab-sa-token
grep -q "homelab-sa-token" ~/.bashrc || \
  printf '\n[ -f %s ] && source %s\n' "$HOME/.config/op/homelab-sa-token" "$HOME/.config/op/homelab-sa-token" >> ~/.bashrc
```

---

## 2. SSH agent (key-based host access)

Hosts are reached over SSH as `ansible-admin` (or the per-host `ansible_user`).
Two identity models are in use on the runner:

- **WSL local key:** `~/.ssh/id_ed25519` — used to reach the VPS (`vps.kogler.si` /
  `159.195.111.66`). Its public key is installed in each host's `~/.ssh/authorized_keys`
  for `ansible-admin`. (Committed `ansible-admin`/`laptop-domen` keys are the repo
  convention; on hosts lacking them, the runner's local key was authorized to unblock.)
- **1Password SSH agent** (repo-preferred, `deployment-secrets.md` -> "SSH Key
  Separation"): private keys never on disk, served on demand via `IdentityAgent`.
  Requires `~/.ssh/config` + `~/.ssh/<name>.pub` reference files + the 1Password SSH
  agent socket. **This runner currently uses the plain WSL key** (no `~/.ssh/config`);
  the 1Password SSH agent setup is the intended end state.

### Windows-desktop agent notes (interactive laptop access)

Found live 2026-08-22 while restoring VPS access (HD-209 — live SSH restore; evidence in the commit + `deployment-tasks.md`):

- **Vault allowlist:** the desktop agent serves ONLY vaults listed in 1Password's agent
  config `agent.toml` (Windows: `%LOCALAPPDATA%\1Password\config\ssh\agent.toml`; each
  vault gets an `[[ssh-keys]] vault = "<vault>"` block). `Homelab-ansible` MUST be added
  or its SSH items (`laptop-domen_ssh`, `ansible-admin_ssh`) are invisible to `ssh`.
- **Keep the offered-key count small:** hosts run `maxauthtries 3` (HD-154); every
  agent-served key burns one offer. Disable "Use with SSH agent" on unused items so
  plain `ssh ansible-admin@vps.kogler.si` reaches the right key within 3 tries.
- **Pub-hint + agent refusal:** pointing `IdentityFile` at a `.pub` served by the agent works
  (e.g. `IdentityFile ~/.ssh/ansible-admin_ssh.pub` + `IdentitiesOnly`); if the vault is NOT
  allowlisted in `agent.toml`, the agent refuses the key and `ssh` misreports it as
  `Load key … invalid format` — the toml fix above is the real solution, not a client bug.
- **Laptop convenience (final, owner-set 2026-08-22):** `~/.ssh/config` carries TWO aliases,
  both `User ansible-admin` (the only SSH user), differing only by the presented key via
  `.pub` hint + `IdentitiesOnly yes`: `vps-ansible` → runner identity (`ansible-admin_ssh.pub`),
  `vps` → personal interactive identity (`laptop-domen_ssh.pub`). Item names are vault
  identities, NOT usernames — there is no `laptop-domen` user on any host.

---

## 3. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `error: could not find session token for account` | `OP_SERVICE_ACCOUNT_TOKEN` not exported in this shell — source `~/.bashrc` (interactive shell only) |
| `"<item>" isn't an item in the "Homelab-ansible" vault` | Item missing (not an auth failure) — create it in 1Password, or check the exact name/field |
| `Unable to sign in to 1Password. Missing required parameters` | Token absent — install/export `OP_SERVICE_ACCOUNT_TOKEN` |
| `op vault list` only shows some vaults | Service account lacks read grant on the needed vault |
| `Permission denied (publickey)` to a host | Runner's SSH key not authorized in that host's `authorized_keys` |
| `invalid JSON provided` / `invalid JSON in piped input` on `op item create/edit` | Non-TTY stdin: op interprets piped input as a JSON item template. Run with `< /dev/null` in scripts, ansible shell tasks, ssh one-liners, cron (provisioner + secret-egress glue precedents, Phase 1 2026-08-22) |
| **Secret VALUE leaked into chat/transcript via `op item get --reveal`** | Rotate the affected secret immediately (see Output hygiene above); if it's a shared Authentik client (`headscale_api`), regenerate the provider client_secret in Authentik, `op item edit` the 1P item, and re-render the consuming services; **never** inspect further in plaintext |
| `Failed to change ownership of the temporary files` | `acl` package (`setfacl`) missing on the target host — added to the `common` role prereqs |

> **Secrets rule (CONVENTIONS §6):** never put token/item values in docs or git. This file
> documents *where* and *how*; the values stay in 1Password and the `0600` runner file.
>
> **Output hygiene (CONVENTIONS §2, HD-234):** when a probe/rotation touches a secret, print
> **lengths / prefixes / item IDs / hashes only** — never a full value. `op item get … --reveal`
> into a shell that echoes to a session/transcript log is how live client_secrets leak into
> chat (HD-233 incident). Rotating a shared Authentik client: regenerate the secret in the
> provider ORM (providers don't expose `generate_client_id`; `authentik.lib.generators` has
> `generate_id`/`generate_key`/`generate_code_fixed_length`), persist to the 1P item, then
> re-render the consuming services (headscale + headplane read `headscale_api`) and verify —
> full step-by-step (incl. the `docker cp`-broken + `op --template`-stdin gotchas) lives in
> [`services-authentik.md`](services-authentik.md) *Rotating a shared Authentik OIDC client secret* runbook.