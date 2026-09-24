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

### Credential source — TWO service accounts
Both items live in the **`Homelab-ansible`** vault itself (`op vault list` returns exactly that
one vault), both re-issued:

| Item | Scope | Who uses it |
|---|---|---|
| `op_api` | **read** `Homelab-ansible` | the control node (`op` CLI + Ansible's `community.general.onepassword` lookup) any CI runner that resolves the vault (HD-315's `vault-gate`; Phase 0/5 of [../deployment-tasks.md](../deployment-tasks.md) store `op_api` as a runner secret — renew it there after every rotation, or CI's vault access starts 403-ing) |
| `op-write_api` | **read + write** | anything that must CREATE/ROTATE items: `scripts/provision-secrets.py`, and the host-side glue deployed to `/etc/op/provision-token` (renamed from `vps-op-write_api`, now deleted) |

> **Superseded design (kept for the record, do not re-implement):** this section used to say the
> runner token was item **`Service Account Auth Token: ansible`** in a separate **Private vault**,
> and that an `op_api` item in `Homelab-ansible` was *"intentionally NOT created"*. That is no
> longer how it works — the control-node token IS an `op_api` item in the main vault, and there is
> no second vault. Verified by `op vault list` + `op item list --vault Homelab-ansible`.

### Where a token is installed (the whole list)
| Host / system | Token | Source of truth |
|---|---|---|
| **`oldsrv` — the on-site control node** (seeds 2026-09-22, proving logs 2026-09-23) | `op_api` | `~/.config/op/homelab-sa-token` (0600), written by `bootstrap-runner.sh --token-stdin` from `op read` on the laptop — the value never crossed a prompt or a shell history |
| **control node (rescue)** — this WSL Debian laptop. No longer "the only place `ansible-playbook` is run interactively" (HD-407 closed that), and it stays installed as the door you open when the on-site runner is the thing that is broken | `op_api`… **nominally** — see the two-token finding below | `~/.config/op/homelab-sa-token` (0600) |
| **Forgejo CI runner** (the `vault-gate` job + any playbook it runs) | `op_api` | a Forgejo secret |
| **vps** — the Authentik secret-egress glue + `kopia-fingerprint-sync.yml` | `op-write_api` | `/etc/op/provision-token`, 0600 root, deployed by the docker_services pre-pass |
| home hosts | `op-write_api` | same path, but ONLY where a `bootstrap_keys` service converges (`deploy-service.yml`) |
| **spark** | none | it has no token at all — that is exactly why every spark playbook runs through the `pi` jump host ([deployment-ansible.md](deployment-ansible.md)) |
| **Win11 desktop** | **none, by design** | git auth/signing uses the **1Password desktop app** over `\\.\pipe\openssh-ssh-agent`; there is no `op` CLI and no SA token there (`scripts/git-bootstrap-win11.sh` reads neither `OP_SIGN` nor `OP_AUTH`) |

### Two live read-scope service-account tokens exist today (measured 2026-09-23, by hash)

`sha256(token)[:12]`, values never printed — the method the rotation section already prescribes:

| Where | length | hash prefix |
|---|---|---|
| laptop `~/.config/op/homelab-sa-token` | 850 | `be1939305745` |
| `op://Homelab-ansible/op_api/credential` (the item the docs call the source of truth) | 850 | `adc2aada8f6e` |
| oldsrv `~/.config/op/homelab-sa-token` | 850 | `adc2aada8f6e` — matches the vault item |

So the laptop's installed token is **not** the token the vault says is canonical, and both work.
Consequence, stated plainly: **rotating or deleting `op_api` does not revoke the laptop's token.**
An SA token that exists only on a disk and in no vault item is invisible to every procedure written
against the vault, which is the same class of defect as `oldsrv-rsync` (HD-416) in a different
subsystem. ⏳ Decide deliberately: either re-seat the laptop from `op read` and let the vault item be
the single mint point, or mint/record the second token as its own vault item with a named consumer.
Not this lane's call — it is a credential-revocation decision, and revoking the wrong one locks the
rescue runner out of the vault.

### Rotating the control-node token
`scripts/bootstrap-runner.sh` is **create-only** — `if [ ! -f "$OP_TOKEN_FILE" ]` — so after a
rotation it prints *"token already stored"* and changes nothing. Rotate with:
```bash
read -rsp "new op_api token: " T && printf 'export OP_SERVICE_ACCOUNT_TOKEN=%q\n' "$T" \
  > ~/.config/op/homelab-sa-token && unset T && chmod 600 ~/.config/op/homelab-sa-token \
  && set -a && . ~/.config/op/homelab-sa-token && set +a && op whoami
```
**Trap that bites every time:** an already-running shell keeps exporting the OLD value, and the
environment beats the file. `op whoami` returning `403 … You aren't authorized to access this
resource` with a freshly-written file means exactly that — re-`source` the file (or open a new
shell). Verify a rotation took effect by **hash**, never by printing the value.
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
  for `ansible-admin`. (Committed `ansible-admin`/`domen_ssh` keys are the repo
  convention; on hosts lacking them, the runner's local key was authorized to unblock.)
- **1Password SSH agent** (repo-preferred, `deployment-secrets.md` -> "SSH Key
  Separation"): private keys never on disk, served on demand via `IdentityAgent`.
  Requires `~/.ssh/config` + `~/.ssh/<name>.pub` reference files + the 1Password SSH
  agent socket. **This runner currently uses the plain WSL key** (no `~/.ssh/config`);
  the 1Password SSH agent setup is the intended end state.

### Windows-desktop agent notes (interactive laptop access)

Discovered the hard way during a VPS SSH restore (HD-209). Each of these produces an auth-shaped error with a non-auth cause:

- **Vault allowlist:** the desktop agent serves ONLY vaults listed in 1Password's agent
  config `agent.toml` (Windows: `%LOCALAPPDATA%\1Password\config\ssh\agent.toml`; each
  vault gets an `[[ssh-keys]] vault = "<vault>"` block). `Homelab-ansible` MUST be added
  or its SSH items (`domen_ssh`, `ansible-admin_ssh`) are invisible to `ssh`.
- **Keep the offered-key count small:** hosts run `maxauthtries 3` (HD-154); every
  agent-served key burns one offer. Disable "Use with SSH agent" on unused items so
  plain `ssh ansible-admin@vps.kogler.si` reaches the right key within 3 tries.
- **Pub-hint + agent refusal:** pointing `IdentityFile` at a `.pub` served by the agent works
  (e.g. `IdentityFile ~/.ssh/ansible-admin_ssh.pub` + `IdentitiesOnly`); if the vault is NOT
  allowlisted in `agent.toml`, the agent refuses the key and `ssh` misreports it as
  `Load key … invalid format` — the toml fix above is the real solution, not a client bug.
- **Laptop convenience (owner-set):** `~/.ssh/config` carries TWO aliases,
  both `User ansible-admin` (the only SSH user), differing only by the presented key via
  `.pub` hint + `IdentitiesOnly yes`: `vps-ansible` → runner identity (`ansible-admin_ssh.pub`),
  `vps` → personal interactive identity (`domen_ssh.pub`). Item names are vault
  identities, NOT usernames. The human account is `domen` (HD-443: sanctioned fleet-wide, being landed by IaC); `domen_ssh` is the item name, never a login.

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
| **`op item edit` returns `error: an HTTP error occurred … 404` right after clearing a field** | **Spurious (op CLI 2.39).** The write has ALREADY been applied — the 404 is the CLI's post-edit re-read hitting a stale revision. **Re-read the item to confirm the new state instead of retrying**, and never treat it as "nothing happened" — that class of failure only repeats the clear or corrupts the field ordering (live 2026-09-17, the `dsh` credential clear) |
| `op item get <item>` prints something like `REDACTED`/a hint where a value should be, and a comparison "fails" | `op item get` **without `--reveal`** returns a non-secret hint string, not the value — so any equality test against an expected secret is false by construction. Add `--reveal` (and keep the output out of transcripts per §Output hygiene), or compare a `sha256` of the revealed value instead of the value itself |

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