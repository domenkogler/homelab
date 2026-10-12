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
one vault):

| Item | Scope | Who uses it |
|---|---|---|
| `op_api` | **read** `Homelab-ansible` | the control node (`op` CLI + Ansible's `community.general.onepassword` lookup) and every Debian **seat**. No CI holder — **there is no Forgejo runner holding it** ([../deployment-tasks.md](../deployment-tasks.md) §Vault inventory), and the only workflow in the tree (`spark/.github/workflows/ansible-ci.yml`) carries no OP secret. The item is the **single mint point** for all three Debian installs: the oldsrv control node, the oldsrv seat and the laptop |
| `op-write_api` | **read + write** | anything that must CREATE/ROTATE items: `scripts/provision-secrets.py`, and the host-side glue deployed to `/etc/op/provision-token`; it reaches those hosts only through an `op-provision-token` converge ([deployment-secrets.md](deployment-secrets.md) §`op-write_api`) |

The two scopes cannot be told apart by `op vault list` — both service accounts list the one vault;
see §Proving which service account an install holds.

### Where a token is installed (the whole list)
| Host / system | Token | Source of truth |
|---|---|---|
| **`oldsrv` — the on-site control node** (`ansible-admin`) | `op_api` | `~/.config/op/homelab-sa-token` (0600), written by `bootstrap-runner.sh --token-stdin` from `op read` — the value never crosses a prompt or a shell history |
| **`oldsrv` SEAT — `domen`, the cockpit/authoring account** | `op_api` | `~/.config/op/homelab-sa-token` (0600, owner `domen`), sourced from `~/.bashrc` — this is what makes the seat able to author ([deployment-ansible.md](deployment-ansible.md) §Runner placement) |
| **control node (rescue)** — this WSL Debian laptop; not the only place `ansible-playbook` is run interactively, and it stays installed as the door you open when the on-site runner is the thing that is broken ([deployment-ansible.md](deployment-ansible.md) §Runner placement) | `op_api` | `~/.config/op/homelab-sa-token` (0600) |
| Forgejo CI runner | — | **no holder**: no `.forgejo/` workflow, no runner, so nothing renews this token in CI |
| **vps** — the Authentik secret-egress glue + `kopia-fingerprint-sync.yml` | `op-write_api` | `/etc/op/provision-token`, 0600 root, deployed by the docker_services pre-pass |
| home hosts | `op-write_api` | same path, but ONLY where a `bootstrap_keys` service converges (`deploy-service.yml`) |
| **spark** | none | it has no token at all — that is exactly why every spark playbook runs through the `pi` jump host ([deployment-ansible.md](deployment-ansible.md)) |
| **Win11 desktop** | **none, by design** | git auth uses the **1Password desktop app** over `\\.\pipe\openssh-ssh-agent`; there is no `op` CLI and no SA token there (`scripts/git-bootstrap-win11.sh` reads neither `OP_SIGN` nor `OP_AUTH`). The one task that would make it a consumer: `scripts/render-pi-config.py` falls back to this same file, so mint `pi_auth` from a Debian seat, or strip the CR if you ever pipe `op.exe` output into it |

### Proving which service account an install holds

`op vault list` **cannot distinguish the two scopes** — both service accounts list the one
`Homelab-ansible` vault. Scope is proven by the **`op whoami` Integration ID** (the two service
accounts are different integrations) or by a write attempt that fails. An install seeded from the
wrong item silently runs the write-scoped `op-write_api` credential while every read-side check
passes — so scope a seat only from `op_api/credential`, and prove it by Integration ID.

`sha256(token)[:12]`, values never printed (CONVENTIONS §6):

| Item / install | value | service account |
|---|---|---|
| `op_api` — **current** | `6a1342f44e65` | Integration `DUW6UPKY5JGG3MM6WF3HBHQWGQ` (read) |
| `op-write_api` — **current** | `b61f34e3bc95` | Integration `PR4Z2FGWW5BRXNL6OR3FNYL3R4` (read+write) |

The superseded `op_api` value stays valid until its grace window closes on **~2026-10-15**.

A rotation revokes the consumers of **that item**, and only them. Enumerate consumers by *value hash*,
not by *doc row* — a host can appear in one item's row while carrying the other item's value.
Sweep form (hashes only, never values):

```bash
for f in ~/.config/op/homelab-sa-token /home/*/.config/op/homelab-sa-token; do \
  [ -f "$f" ] || continue; ( set -a; . "$f"; set +a \
    ; printf '%s  %s\n' "$f" "$(printf %s "$OP_SERVICE_ACCOUNT_TOKEN" | sha256sum | cut -c1-12)" ); done
```

### Rotating the control-node token
`scripts/bootstrap-runner.sh` is **create-only** — `if [ ! -f "$OP_TOKEN_FILE" ]` — so after a
rotation it prints *"token already stored"* and changes nothing. Prefer the **pipe form**, which needs
no paste box and leaves no literal in history or in a transcript (needs any still-working token on the
box, since it reads the item itself — do it inside the grace window, not after):
```bash
umask 077; install -d -m 700 ~/.config/op
op read "op://Homelab-ansible/op_api/credential" </dev/null | \
  { IFS= read -r T; printf 'export OP_SERVICE_ACCOUNT_TOKEN=%q\n' "$T"; } \
  > ~/.config/op/homelab-sa-token && chmod 600 ~/.config/op/homelab-sa-token
unset OP_SERVICE_ACCOUNT_TOKEN; set -a; . ~/.config/op/homelab-sa-token; set +a
op whoami && printf 'len=%s sha256[:12]=%s\n' "${#OP_SERVICE_ACCOUNT_TOKEN}" \
  "$(printf %s "$OP_SERVICE_ACCOUNT_TOKEN" | sha256sum | cut -c1-12)"
```
Only a paste box is available (a fresh box, or after the old value died) — then use `read -rsp` so the
value never lands on a command line, and scrub history afterwards:
```bash
read -rsp "new op_api token: " T && printf 'export OP_SERVICE_ACCOUNT_TOKEN=%q\n' "$T" \
  > ~/.config/op/homelab-sa-token && unset T && chmod 600 ~/.config/op/homelab-sa-token \
  && set -a && . ~/.config/op/homelab-sa-token && set +a && op whoami
sed -i '/^export OP_SERVICE_ACCOUNT_TOKEN=/d' ~/.bash_history
```
⚠ **`~/.bashrc` is scrubbed by `bootstrap-runner.sh` step 5; `~/.bash_history` is not.** A token typed
into a `printf … 'PASTE_TOKEN' > …` command line is stored verbatim in history.
The sweep is the `sed` above; the audit is `grep -c '^export OP_SERVICE_ACCOUNT_TOKEN=' ~/.bash_history`.
**Check the same file on every seat, and check the pi transcripts** — a value that crossed a transcript
cannot be scrubbed from the repo, only rotated.
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
Never put the literal in the command line — the form below takes it from a prompt, so history and
transcripts stay clean:
```bash
mkdir -p ~/.config/op
umask 077
read -rsp "op_api service-account token: " OP_TOKEN && echo
printf 'export OP_SERVICE_ACCOUNT_TOKEN=%q\n' "$OP_TOKEN" > ~/.config/op/homelab-sa-token
unset OP_TOKEN
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
  convention; on hosts lacking them, the runner's local key is authorized instead.)
- **1Password SSH agent** (repo-preferred, `deployment-secrets.md` -> "SSH Key
  Separation"): private keys never on disk, served on demand via `IdentityAgent`.
  Requires `~/.ssh/config` + `~/.ssh/<name>.pub` reference files + the 1Password SSH
  agent socket. **This runner currently uses the plain WSL key** (no `~/.ssh/config`);
  the 1Password SSH agent setup is the intended end state.

### GitHub signing + auth keys — a third job for the same agent

Commit **signing is retired**: the only key left of this mechanism is `GitHub auth`, the transport
key, which is also the only key still registered on the GitHub account.

`GitHub auth` is an SSH_KEY item in **`Homelab-ansible`**, not in the `Private` vault. Two
consequences worth naming:

- **A read-scope service account can pull it.** `git-bootstrap.sh --ssh-auth` runs end to end
  on a headless Debian seat with only `~/.config/op/homelab-sa-token` in the environment — no
  interactive `op signin`, no desktop app, no 2FA. The `OP_VAULT` override covers any machine whose
  items still live in the other vault (`OP_VAULT=Private bash scripts/git-bootstrap.sh --ssh-auth`).
- **Signing does not need the agent at all when the key is passphrase-free** (measured, git 2.47.3):
  `user.signingkey=/home/domen/.ssh/github_signing` signs with
  `SSH_AUTH_SOCK` **removed from the environment** (`%G?` → `G`), while `key::<pub>` fails with
  `error: Couldn't get agent socket?` + `fatal: failed to write commit object`. Every non-interactive
  shell is in that second class — pi, cron, a converge — so the file path is the seat's form and the
  `key::` form is only for a passphrase-protected key. Check which one you have with
  `ssh-keygen -y -P '' -f ~/.ssh/github_signing`; the same test is what `git-bootstrap.sh` runs to
  choose the form. Verification needs `gpg.ssh.allowedSignersFile` (see §Troubleshooting), or git
  reports `N` on a signed commit.

### Windows-desktop agent notes (interactive laptop access)

Each of these produces an auth-shaped error with a non-auth cause:

- **Vault allowlist:** the desktop agent serves ONLY vaults listed in 1Password's agent
  config `agent.toml` (Windows: `%LOCALAPPDATA%\1Password\config\ssh\agent.toml`; each
  vault gets an `[[ssh-keys]] vault = "<vault>"` block). `Homelab-ansible` MUST be added
  or its SSH items (`domen_ssh`, `ansible-admin_ssh`) are invisible to `ssh`.
- **Keep the offered-key count small:** hosts run `maxauthtries 3`; every
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
  identities, NOT usernames. The human account is `domen` (sanctioned fleet-wide, landed by IaC); `domen_ssh` is the item name, never a login.

---

## 3. Troubleshooting

> ⚠ **Two `op` behaviours on the service-account path.** (1) **`op run` does not resolve
> `{OP://item/field}` references under a service account** — it passes the literal reference string INTO
> the target item and then exits 4 with `(404) Not Found`. Reference syntax is a desktop/CLI-session
> feature; from an SA seat, read the source field into a variable and write it as an ordinary
> `field=value` argument. (2) **`op item edit` reports `(404) Not Found` and rc=4 even when the write
> landed.** The exit code of `op item edit` is therefore not evidence: verify by re-reading the item and
> comparing lengths/booleans (never print values), and state explicitly that a "failed" edit may already
> have applied.

| Symptom | Cause / fix |
|---------|-------------|
| `error: could not find session token for account` | `OP_SERVICE_ACCOUNT_TOKEN` not exported in this shell — source `~/.bashrc` (interactive shell only) |
| `"<item>" isn't an item in the "Homelab-ansible" vault` | Item missing (not an auth failure) — create it in 1Password, or check the exact name/field |
| `Unable to sign in to 1Password. Missing required parameters` | Token absent — install/export `OP_SERVICE_ACCOUNT_TOKEN` |
| `op vault list` only shows some vaults | Service account lacks read grant on the needed vault |
| `Permission denied (publickey)` to a host | Runner's SSH key not authorized in that host's `authorized_keys` |
| `invalid JSON provided` / `invalid JSON in piped input` on `op item create/edit` | Non-TTY stdin: op interprets piped input as a JSON item template. Run with `< /dev/null` in scripts, ansible shell tasks, ssh one-liners, cron (provisioner + secret-egress glue precedents) |
| **Secret VALUE leaked into chat/transcript via `op item get --reveal`** | Rotate the affected secret immediately (see Output hygiene above); if it's a shared Authentik client (`headscale_api`), regenerate the provider client_secret in Authentik, `op item edit` the 1P item, and re-render the consuming services; **never** inspect further in plaintext |
| `Failed to change ownership of the temporary files` | `acl` package (`setfacl`) missing on the target host — added to the `common` role prereqs |
| **`Couldn't get agent socket?` then `fatal: failed to write commit object` on `git commit`** | `gpg.format=ssh` with `user.signingkey` in the `key::<pub>` form and **no `SSH_AUTH_SOCK`** in a non-interactive shell (pi, cron, a converge). Set `user.signingkey` to the key FILE when it is passphrase-free — `ssh-keygen -y -P '' -f ~/.ssh/github_signing` answers that question — or export `SSH_AUTH_SOCK=/run/user/$(id -u)/openssh_agent`. Refusing the commit is the correct failure; a silently unsigned commit is not (CONVENTIONS §6) |
| **`git log -1 --format='%G?'` prints `N` on commits you know are signed** | No `gpg.ssh.allowedSignersFile` configured — git cannot verify, so it reports `N` for every commit, signed or not. Use `grep -c '^gpgsig'` over `git cat-file commit HEAD` meanwhile, then set the file (deployment-manual.md §0.4a) |
| **`op item edit` returns `error: an HTTP error occurred … 404` right after clearing a field** | **Spurious (op CLI 2.39).** The write has ALREADY been applied — the 404 is the CLI's post-edit re-read hitting a stale revision. **Re-read the item to confirm the new state instead of retrying**, and never treat it as "nothing happened" — that class of failure only repeats the clear or corrupts the field ordering |
| `op item get <item>` prints something like `REDACTED`/a hint where a value should be, and a comparison "fails" | `op item get` **without `--reveal`** returns a non-secret hint string, not the value — so any equality test against an expected secret is false by construction. Add `--reveal` (and keep the output out of transcripts per §Output hygiene), or compare a `sha256` of the revealed value instead of the value itself |

> **Secrets rule (CONVENTIONS §6):** never put token/item values in docs or git. This file
> documents *where* and *how*; the values stay in 1Password and the `0600` runner file.
>
> **Output hygiene (CONVENTIONS §2):** when a probe/rotation touches a secret, print
> **lengths / prefixes / item IDs / hashes only** — never a full value. `op item get … --reveal`
> into a shell that echoes to a session/transcript log is how live client_secrets leak into
> chat. Rotating a shared Authentik client: regenerate the secret in the
> provider ORM (providers don't expose `generate_client_id`; `authentik.lib.generators` has
> `generate_id`/`generate_key`/`generate_code_fixed_length`), persist to the 1P item, then
> re-render the consuming services (headscale + headplane read `headscale_api`) and verify —
> full step-by-step (incl. the `docker cp`-broken + `op --template`-stdin gotchas) lives in
> [`services-authentik.md`](services-authentik.md) *Rotating a shared Authentik OIDC client secret* runbook.