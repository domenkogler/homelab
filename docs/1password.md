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
| `op_api` | **read** `Homelab-ansible` | the control node (`op` CLI + Ansible's `community.general.onepassword` lookup) and every Debian **seat**. No CI holder: the Phase 0/5 "`op_api` as a runner secret" premise was answered 2026-09-25 — **there is no Forgejo runner holding it** (HD-396, [../deployment-tasks.md](../deployment-tasks.md) §Vault inventory), and the only workflow in the tree (`spark/.github/workflows/ansible-ci.yml`) carries no OP secret. ✅ **Rotated by the owner 2026-10-08** (leak response), the superseded value stops working ~2026-10-15; ✅ **re-seated 2026-10-09 on all three Debian installs** — the oldsrv control node, the oldsrv seat and the laptop (HD-495 carries the leg) — so the item is again the **single mint point**. ⏳ `/etc/op/provision-token` hosts still owed (the `op-write_api` leg, see the rotation-round block below) |
| `op-write_api` | **read + write** | anything that must CREATE/ROTATE items: `scripts/provision-secrets.py`, and the host-side glue deployed to `/etc/op/provision-token` (renamed from `vps-op-write_api`, now deleted). ⚠ **Rotated by the owner 2026-10-09 in the same leak response** — every `/etc/op/provision-token` copy in the fleet now carries the SUPERSEDED value and 403s once the grace window closes; it reaches them only through an `op-provision-token` converge ([deployment-secrets.md](deployment-secrets.md) §`op-write_api`) |

> **Superseded design (kept for the record, do not re-implement):** this section used to say the
> runner token was item **`Service Account Auth Token: ansible`** in a separate **Private vault**,
> and that an `op_api` item in `Homelab-ansible` was *"intentionally NOT created"*. That is no
> longer how it works — the control-node token IS an `op_api` item in the main vault, and there is
> no second vault. Verified by `op vault list` + `op item list --vault Homelab-ansible`.

### Where a token is installed (the whole list)
| Host / system | Token | Source of truth |
|---|---|---|
| **`oldsrv` — the on-site control node** (`ansible-admin`, seeds 2026-09-22, proving logs 2026-09-23) | `op_api` | `~/.config/op/homelab-sa-token` (0600), written by `bootstrap-runner.sh --token-stdin` from `op read` on the laptop — the value never crossed a prompt or a shell history. ✅ **re-seated to the rotated value 2026-10-09** (`op item list` = rows, not 403) |
| **`oldsrv` SEAT — `domen`, the cockpit/authoring account** (HD-495, 2026-10-06) | `op_api` | `~/.config/op/homelab-sa-token` (0600, owner `domen`), sourced from `~/.bashrc`. This is what closed "the seat cannot author" in [deployment-ansible.md](deployment-ansible.md) §Runner placement. ⚠ **Until 2026-10-09 this file held the WRITE-scoped token, not `op_api`** — see the corrected finding below; ✅ re-seated to the read-scoped value 2026-10-09, now proven by SA identity, not by `op vault list` (which cannot tell the two scopes apart) |
| **control node (rescue)** — this WSL Debian laptop. No longer "the only place `ansible-playbook` is run interactively" (HD-407 closed that), and it stays installed as the door you open when the on-site runner is the thing that is broken | `op_api` | `~/.config/op/homelab-sa-token` (0600). ✅ **re-seated 2026-10-09 and measured**: `be1939305745` **before** — the write item, so this install was mis-seeded too, which is what finally closes the "two-token finding" below — and `6a1342f44e65` / Integration `DUW6UPKY5JGG3MM6WF3HBHQWGQ` after, `op item list` answering rows |
| ~~Forgejo CI runner~~ | ~~`op_api`~~ | **no holder** (HD-396, settled 2026-09-25): no `.forgejo/` workflow, no runner. The Phase 0/5 "renew it in CI after every rotation" line has nothing to renew |
| **vps** — the Authentik secret-egress glue + `kopia-fingerprint-sync.yml` | `op-write_api` | `/etc/op/provision-token`, 0600 root, deployed by the docker_services pre-pass |
| home hosts | `op-write_api` | same path, but ONLY where a `bootstrap_keys` service converges (`deploy-service.yml`) |
| **spark** | none | it has no token at all — that is exactly why every spark playbook runs through the `pi` jump host ([deployment-ansible.md](deployment-ansible.md)) |
| **Win11 desktop** | **none, by design** | git auth/signing uses the **1Password desktop app** over `\\.\pipe\openssh-ssh-agent`; there is no `op` CLI and no SA token there (`scripts/git-bootstrap-win11.sh` reads neither `OP_SIGN` nor `OP_AUTH`). ✅ **verified absent 2026-10-09** (file missing, history clean) — but note the one task that would make it a consumer: `scripts/render-pi-config.py` falls back to this same file, so mint `pi_auth` from a Debian seat, or strip the CR if you ever pipe `op.exe` output into it |

### The "two-token finding" was wrong: the second value was the WRITE-scoped item

> **CORRECTED 2026-10-09, measured during the rotation re-seat.** This section documented a
> "vault-invisible" second read-scope token living only on the laptop's disk, and concluded that
> rotating `op_api` could not revoke it. The premise was a **mis-seed, not a mystery**: the value in
> question (`be1939305745`) is byte-identical to `op://Homelab-ansible/**op-write_api**/credential` —
> the **read+write**-scoped service account. Whoever seeded the oldsrv seat on **2026-10-07 01:05**
> (file mtime) read the write item instead of `op_api`. Two things follow, and both were invisible to
> every check this repo had:
>
> 1. **A seat was running a write-scoped credential** for ten months' worth of authoring work, and
>    `op vault list` — the probe this doc cited as "read scope verified" — **cannot distinguish the two
>    scopes**: both list the one vault. Scope is proven by the **`op whoami` Integration ID** (the two
>    service accounts are different integrations) or by a write attempt that fails.
> 2. **Rotating `op_api` revoked nothing on that box.** A rotation of item A does not touch item B, so
>    a leak-response rotation silently left the mis-seated consumer holding a live credential. That is
>    the HD-442 class again, one level up: the check passes, the credential is wrong.
>
> **Measured on both installs 2026-10-09, so this is now a fact and not an inference:** the laptop's copy
> hashed `be1939305745` immediately before its re-seat, the same value the seat carried. There was never
> a second mint point — the "vault-invisible token" this section used to warn about was `op-write_api`
> installed in two places, and `op_api/credential` is again the single source of truth for all three
> Debian installs (laptop, oldsrv runner, oldsrv seat).

`sha256(token)[:12]`, values never printed (CONVENTIONS §6). Current pair after the 2026-10 leak response:

| Item / install | value | service account |
|---|---|---|
| `op_api` — **current** | `6a1342f44e65` | Integration `DUW6UPKY5JGG3MM6WF3HBHQWGQ` (read) |
| `op_api` — superseded 2026-10-08 | `adc2aada8f6e` | dead ~2026-10-15 (probed alive 2026-10-09: 137 vault rows) |
| `op-write_api` — **current** (2026-10-09) | `b61f34e3bc95` | Integration `PR4Z2FGWW5BRXNL6OR3FNYL3R4` (read+write) |
| `op-write_api` — superseded 2026-10-09 | `be1939305745` | Integration `MBMQSOLDYBBDVDTSVT7WDRPMQM`; this is the value the "two-token finding" thought was vault-invisible |

**The revocation rule, restated so the next rotation does not repeat this:** a rotation revokes the
consumers of **that item**, and only them. Enumerate consumers by *value hash*, not by *doc row* — the
seat appeared in the `op_api` row and carried the write item. Sweep form (hashes only, never values):

```bash
for f in ~/.config/op/homelab-sa-token /home/*/.config/op/homelab-sa-token; do \
  [ -f "$f" ] || continue; ( set -a; . "$f"; set +a \
    ; printf '%s  %s\n' "$f" "$(printf %s "$OP_SERVICE_ACCOUNT_TOKEN" | sha256sum | cut -c1-12)" ); done
```

✅ **Closed by this round:** the laptop-WSL copy (`be1939305745` → `6a1342f44e65`, measured 2026-10-09)
and the Win11 seat (confirmed to hold no SA token).
✅ **The last leg closed the same evening:** both **`/etc/op/provision-token`** hosts — `oldsrv` and `vps` —
were refreshed by a full `docker_services` converge (`scope_is_all`) issued FROM the laptop and now re-hash
to `b61f34e3bc95` (written 21:26 / 21:27), the role's own "Probe the deployed token is actually accepted"
task green on both and no container left `unhealthy`/`exited`. Getting there needed the laptop (HD-413
self-converge lockout), and the first attempt at 18:37 died in the launcher's own self-update — see
[deployment-ansible.md](deployment-ansible.md) §Runner placement.

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
into a `printf … 'PASTE_TOKEN' > …` command line — the form this doc used to recommend — is stored
verbatim in history (found live 2026-10-09 on the oldsrv seat, one line, mode 0600, purged in place).
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
transcripts stay clean (the older `'PASTE_TOKEN'` form in this line's place leaked into
`~/.bash_history` exactly as described above):
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
  convention; on hosts lacking them, the runner's local key was authorized to unblock.)
- **1Password SSH agent** (repo-preferred, `deployment-secrets.md` -> "SSH Key
  Separation"): private keys never on disk, served on demand via `IdentityAgent`.
  Requires `~/.ssh/config` + `~/.ssh/<name>.pub` reference files + the 1Password SSH
  agent socket. **This runner currently uses the plain WSL key** (no `~/.ssh/config`);
  the 1Password SSH agent setup is the intended end state.

### GitHub signing + auth keys (HD-495) — a third job for the same agent

⚠ **Status 2026-10-09: `GitHub sign` is DELETED** and signing is retired (HD-1116) — what is left of
this mechanism is `GitHub auth`, the transport key, which is also the only key still registered on the
GitHub account. Everything below stays as the record of how the pair worked, because that is what a
re-registration would have to re-establish.

`GitHub sign` and `GitHub auth` were SSH_KEY items in **`Homelab-ansible`** (moved out of the
`Private` vault 2026-10-06). Two consequences worth naming, because the whole "seat cannot sign"
restriction was built on the old location:

- **A read-scope service account can now pull them.** `git-bootstrap.sh --ssh-auth` runs end to end
  on a headless Debian seat with only `~/.config/op/homelab-sa-token` in the environment — no
  interactive `op signin`, no desktop app, no 2FA. The `Private` override still works for a machine
  set up before the move (`OP_VAULT=Private bash scripts/git-bootstrap.sh --ssh-auth`).
- **Signing does not need the agent at all when the key is passphrase-free.** Proven on the seat
  (git 2.47.3, both halves): `user.signingkey=/home/domen/.ssh/github_signing` signs with
  `SSH_AUTH_SOCK` **removed from the environment** (`%G?` → `G`), while `key::<pub>` fails with
  `error: Couldn't get agent socket?` + `fatal: failed to write commit object`. Every non-interactive
  shell is in that second class — pi, cron, a converge — so the file path is the seat's form and the
  `key::` form is only for a passphrase-protected key. Check which one you have with
  `ssh-keygen -y -P '' -f ~/.ssh/github_signing`; the same test is what `git-bootstrap.sh` now runs to
  choose the form. Verification needs `gpg.ssh.allowedSignersFile` (see §Troubleshooting), or git
  reports `N` on a signed commit.

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

> ⚠ **Two `op` behaviours that made a routine value-move go wrong (measured 2026-10-07, service-account
> path on the oldsrv seat).** (1) **`op run` does not resolve `{OP://item/field}` references under a service
> account** — it passed the literal `{OP://soulseek_login/username}` (30 chars) INTO the target item and then
> exited 4 with `(404) Not Found`. Reference syntax is a desktop/CLI-session feature; from an SA seat, read
> the source field into a variable and write it as an ordinary `field=value` argument. (2) **`op item edit`
> reports `(404) Not Found` and rc=4 even when the write landed** — reproduced twice, re-read both times. So
> from this seat the exit code of `op item edit` is not evidence: verify by re-reading the item and comparing
> lengths/booleans (never print values), and be explicit that a "failed" edit may already have applied.

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
| **`Couldn't get agent socket?` then `fatal: failed to write commit object` on `git commit`** | `gpg.format=ssh` with `user.signingkey` in the `key::<pub>` form and **no `SSH_AUTH_SOCK`** in a non-interactive shell (pi, cron, a converge). Set `user.signingkey` to the key FILE when it is passphrase-free — `ssh-keygen -y -P '' -f ~/.ssh/github_signing` answers that question — or export `SSH_AUTH_SOCK=/run/user/$(id -u)/openssh_agent`. Refusing the commit is the correct failure; a silently unsigned commit is not (CONVENTIONS §6, HD-495) |
| **`git log -1 --format='%G?'` prints `N` on commits you know are signed** | No `gpg.ssh.allowedSignersFile` configured — git cannot verify, so it reports `N` for every commit, signed or not. Use `grep -c '^gpgsig'` over `git cat-file commit HEAD` meanwhile, then set the file (deployment-manual.md §0.4a) |
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