---
title: 1Password CLI & SSH Agent — runner setup
role: reference
domain: deployment
status: active
sensitivity: secret-bearing
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
| `op_api` | **read** `Homelab-ansible`, read-only at the integration (console-confirmed) | the control node (`op` CLI + Ansible's `community.general.onepassword` lookup) and every Debian **seat**. No CI holder — **no Actions store in the fleet holds this token**: the homelab repo is GitHub-hosted with **zero runners registered at it**, the `vps` Forgejo instance carries no homelab repo, and the only workflow in the tree (`spark/.github/workflows/ansible-ci.yml`) declares no OP secret ([../deployment-tasks.md](../deployment-tasks.md) §Vault inventory). The item is the **single mint point** for all four Debian installs: the oldsrv control node, the oldsrv seat, the laptop, and the `vps` control account |
| `op-write_api` | **read + write** | anything that must CREATE/ROTATE items: `scripts/secrets/provision-secrets.py`, and the host-side glue deployed to `/etc/op/provision-token`; it reaches those hosts only through an `op-provision-token` converge ([deployment-secrets.md](deployment-secrets.md) §`op-write_api`) |

The two scopes cannot be told apart by `op vault list` — both service accounts list the one vault;
see §Proving which service account an install holds.

### Where a token is installed (the whole list)
| Host / system | Token | Source of truth |
|---|---|---|
| **`oldsrv` — the on-site control node** (`ansible-admin`) | `op_api` | `~/.config/op/homelab-sa-token` (0600), written by `bootstrap-runner.sh --token-stdin` from `op read` — the value never crosses a prompt or a shell history |
| **`oldsrv` SEAT — `domen`, the cockpit/authoring account** | `op_api` | `~/.config/op/homelab-sa-token` (0600, owner `domen`), sourced from `~/.bashrc` — this is what makes the seat able to author ([deployment-ansible.md](deployment-ansible.md) §Runner placement) |
| **control node (rescue)** — this WSL Debian laptop; not the only place `ansible-playbook` is run interactively, and it stays installed as the door you open when the on-site runner is the thing that is broken ([deployment-ansible.md](deployment-ansible.md) §Runner placement) | `op_api` | `~/.config/op/homelab-sa-token` (0600) |
| **`vps` — the VPS control account** (`ansible-admin`) | `op_api` | `~/.config/op/homelab-sa-token` (0600), sourced from `~/.bashrc` — the same shape and the same pipe-form re-seat as the on-site control node, so `op` on that box reads the vault headless. An `op_api` rotation reaches this host by **two** paths: this file, and the `/etc/op/provision-token` render below (different item, so one rotation does not cover the other). It is the install a seat-side sweep cannot see — `~` and `/home/*` are the paths of the host the sweep runs on, so enumerating it means running the sweep there (§Proving which service account an install holds) |
| **`oldsrv` — the `root` account** | **none** | `/root/.config/op/` holds only `config` and the daemon socket — no token file, no `/root/.bashrc` line. A root shell there reaches the vault only with an explicit token in the child env (`OP_SERVICE_ACCOUNT_TOKEN=$(sudo cat /etc/op/provision-token) op …`). A hand-planted home-token copy is the failure mode worth naming: **nothing re-seats `root`**, so it goes stale at the first rotation and answers `(403) Forbidden (Service Account Deleted)` while every real seat reads the vault fine |
| CI (GitHub Actions / Forgejo Actions) | — | **no holder**: the homelab repo is GitHub-hosted with no runner registered at the repo, the `vps` Forgejo instance hosts no homelab repo (and no `.forgejo/` workflow exists in the tree), so nothing renews this token in CI |
| **vps** — the Authentik secret-egress glue + `kopia-fingerprint-sync.yml` | `op-write_api` | `/etc/op/provision-token`, 0600 root, deployed by the docker_services pre-pass |
| home hosts | `op-write_api` | same path, but ONLY where a `bootstrap_keys` service converges (`deploy-service.yml`) |
| **spark** | none | it has no token at all — that is exactly why every spark playbook runs through the `pi` jump host ([deployment-ansible.md](deployment-ansible.md)) |
| **Win11 desktop** | **none installed, by design** | No token file sits on that disk and the seat installs none of its own. It IS a vault *reader*: the vault legs resolve the credential through [`../scripts/lib/vault-env.sh`](../scripts/lib/vault-env.sh), which reads the Debian engine's install across the WSL door (`route=door:Debian`) — the same `op_api` bytes, never a copy, so a rotation reaches this seat with no second re-seat. Git auth stays on the desktop app over `\\.\pipe\openssh-ssh-agent` (`scripts/git/git-bootstrap-win11.sh` reads the auth item (`OP_AUTH_ITEM`) through the lib ONLY when it raises the transport key; the desktop-app route reads neither `OP_SIGN` nor `OP_AUTH`). The CLI is installed there (`op.exe`, winget `AgileBits.1Password.CLI`); with no resolved credential it must NOT be called — that is the desktop-app route, one consent dialog per read (see [`deployment-secrets.md`](deployment-secrets.md) §What actually raises a 1Password prompt) |

### Reading the vault from the Win11 seat, where no token is installed

The Windows seat holds no vault credential of its own and keeps holding none — but the gate legs that
compare vault values still have to run there, and a seat that reaches `op` with nothing exported does
not fail: it asks the **desktop app**, which authorises a key against a requesting process and so
raises a consent dialog *per read*, in a harness that starts a fresh shell per command. The rule that
prevents that is one file — [`../scripts/lib/vault-env.sh`](../scripts/lib/vault-env.sh), with
[`../scripts/lib/vault_env.py`](../scripts/lib/vault_env.py) as its python face — and every leg calls it: the
Debian-side entry points that used to `source` the file are folded in, so it is read in one file and written in one.

| order | source | `route=` |
|---|---|---|
| 1 | `OP_SERVICE_ACCOUNT_TOKEN` already in the environment | `env` |
| 2 | `~/.config/op/homelab-sa-token` on the seat asking | `file` |
| 3 | **win11 seat only:** that same file, read from the Debian engine across the WSL door | `door:Debian` |
| 4 | nothing else is allowed to answer | `none`, rc 1 |

What that buys: **nothing lands on the Windows disk** — step 3 `cat`s the engine's own `0600` file across one
`wsl.exe` trip (~0.3 s) and hands the value to the calling process through a pipe, and `--emit` refuses a
terminal (rc 3), so no `echo $(…)` can park it in a run log. There is therefore **one install to rotate, not
two**: the rotation procedure above reaches this seat by itself, with no re-seat step to forget. And a seat
with neither a local file nor a reachable engine gets **a refusal, not a dialog** — the leg reports a
boundary (`check_secret_leak.py` exits 2 → a printed SKIP); on that seat the dialog route is not a degraded
check, it is the absence of one.

**The leak gate bounds the CREDENTIAL, not the CLI.** Clearing `PATH` removes `op` but not the credential: where
the Server SDK is importable in the leg's own interpreter the batched read answers with no `op` at all, so an
unreachable-vault arm that scrubs only `PATH` has measured nothing. That arm runs TWO children, each stripped of
`PATH`, `HOME`, the WSL door (`HL_WSL=off`) and the environment token:

| child | what puts the vault out of reach | the boundary it has to print |
|---|---|---|
| `-S`, probe candidates at a stub | no `op` and no SDK — `-S` skips `site`, which takes the SDK off `sys.path` whether it sits in the interpreter's `site-packages` (a `py -3.13` install on the Win11 seat) or in a `--user` site (a Debian seat's `python3`) | no `op` on PATH and no interpreter imports the onepassword SDK |
| `HL_VAULT_READ_ROUTE=sdk`, no token | the SDK route asked with no credential, which [`../scripts/lib/vault_read.py`](../scripts/lib/vault_read.py) refuses — the mutation table cannot patch it, because the table patches the gate file | no vault credential reachable on this seat (…) |

Both exit rc 2, and the **reason** says which station stopped it: a seat with no `bash` on `PATH`
fails in [`../scripts/lib/vault_env.py`](../scripts/lib/vault_env.py)'s `ensure()`, one station before
the SDK route is tried, so that SKIP proves a boundary fired and not that the removed token is what the
child would have used. An interpreter outside the SDK's wheels imports no SDK with or without `-S`, so
the child leaning on `-S` is evidence only on the SDK-bearing interpreter the leg runs in.

Two traps the lib carries so legs do not. A value that crossed `wsl.exe` (or a Windows-authored file) can hold
a trailing `\r`, which `op` sends verbatim and the vault answers **403** — indistinguishable from a dead token
— so the parse strips CR and quotes, reading with `read -r`/out parameters rather than `$( )`, which on a
Git-Bash seat can *hide* the very CR the code is trying to strip. And provenance is printed, never assumed:
`route=`, `sha256[:12]=`, and with `--identity` the Integration ID, the only read that separates the two
service accounts (§Proving which service account an install holds).

```bash
bash scripts/lib/vault-env.sh --check --identity     # route/len/hash + whoami's Integration ID
python scripts/lib/vault_env.py                      # the python face, same answer
```

`HL_WSL=off` disables step 3 exactly as it disables the leg-routing engine, and a seat that is not the
win11 one never tries it.

### What a gate run costs the vault, and why legs pass IDs

Two ceilings apply to every service-account request AT ONCE, and `op service-account ratelimit` prints
both: the token's own 1000 reads/hour, and — the one that binds a lab like this — **1000 requests per
24 h for the whole 1Password account, shared by every service account on it** (Families/Personal;
Teams 5 000, Business 50 000). Waiting for the hourly reset does not help an exhausted daily bucket,
and a second service account does not either: the daily bucket is per account, not per token. The
failure looks like `Too many requests. Your client has been rate-limited. Try again in  seconds` —
with the seconds blank, because the CLI has no retry-after for this class.

**The whole-vault read is ONE batched read that the legs share**
([`../scripts/lib/vault_read.py`](../scripts/lib/vault_read.py)): where the Server SDK is
importable it answers `items.list` once plus `items.get_all` in 50-ID chunks — single-digit requests
for the vault's ~143 items — and where it is not, the same reader runs a clearly labelled
`op item get` FALLBACK costing 1 list + 1 read per item (~1 + N requests). Every leg prints its
request count (`route=`/`requests=` on stderr), so the log, not a comment, states what a run paid;
the ID-addressed fallback replaced an earlier name-addressed fan-out that cost 3 requests per item —
~429 requests, three runs to an exhausted day. Measured against the live vault (143 items): **1
request** for the names mode, **4** for every value (`items.list` + 3 × `get_all`) — the fallback
price for the same read is ~144. A **full `validate-all`** on a seat where the SDK route answers moves
the account bucket by **one** (`op service-account ratelimit` read either side of the run) where the
same run on the fallback spent ~480; the printed `requests=` is the ceiling of the calls the reader
made, and the account's own counter comes in at or below it, so treat the printed number as the worst
case and the bucket as the fact.

**A vault NAME is not a valid SDK address.** `items.list` / `items.get_all` take a vault **ID** and
answer a title with `invalid user input: … the provided ID is not in a valid format`; `op` hides that
by resolving names, the SDK does not. The SDK route therefore asks the same ID map the CLI legs use
(warm ⇒ free, cold ⇒ ONE `vaults.list`, counted in the printed `requests=` **and pinned in the map so
the next run is free again** — an unpinned resolution is a request bought on every run, which is what a
seat whose map `op` never warmed measured: 2 per name list, 5 per value read), and a vault the account
does not answer is a boundary that names `vault-env.sh --map`, never an empty fleet.

A leg that needs the vault's **names and versions only** — the catalog check's HAVE-list — asks the
reader's names mode (`--list`, or `read_names()`), which stops after the list on BOTH routes: ONE
request, and no value is read at all. Asking for names is not a reason to buy the whole vault.

Seat step — the SDK wheel is tagged cp39–cp313, so an interpreter newer than the wheel set cannot
import it and the reader answers through the fallback until this runs on a supported interpreter:

```bash
python3 scripts/lib/vault_read.py --probe         # which interpreter imports onepassword, and which half failed where it does not
python3 scripts/lib/vault_read.py --install-sdk   # pip install onepassword-sdk into the probed interpreter — an explicit seat act; nothing installs by itself
```

On a seat whose python is PEP-668-managed (every Debian seat, and oldsrv's `python3`) the plain
install is refused, and `--install-sdk` retries it as a **user-site** install (`--user
--break-system-packages`) — no OS package moves, and plain `python3` imports the SDK, which is what
the probe needs. The Win11 seat needs it on `py -3.13` specifically, because its `py -3` is 3.14 and outside
the wheel set — which is also where the gate's own launcher probe lands there (`python3` is the Store stub,
so the probe settles on `py -3`): a full gate run on that seat answers the no-SDK shape. A seat that has not had
this act still works — it pays the labelled fallback.

A **name** is not a free address. `op item get` and `op read` resolve the name first and 1Password bills
the resolving — 3 requests for a name-addressed read, 1 for an ID-addressed one (CLI docs, "Commands
that make multiple requests"). The legs therefore address by **ID**: the vault ID comes
out of the `op item list` answer the run already paid for, and titles come from the map
[`../scripts/lib/vault-env.sh`](../scripts/lib/vault-env.sh) keeps in the seat's state dir. A title the map
does not know keeps the NAME and prints a NOTE — a guessed ID is a wrong answer, not a cheap one — and one
miss costs two reads, after which it is right forever.

```bash
op service-account ratelimit            # both buckets, used/remaining/reset — ask this before debugging transport
bash scripts/lib/vault-env.sh --map Homelab-ansible    # how many titles the seat knows, and the vault ID
```

### Proving which service account an install holds

`op vault list` **cannot distinguish the two scopes** — both service accounts list the one
`Homelab-ansible` vault. Scope is proven by the **`op whoami` Integration ID** (the two service
accounts are different integrations) or by a write attempt that fails. An install seeded from the
wrong item silently runs the write-scoped `op-write_api` credential while every read-side check
passes — so scope a seat only from `op_api/credential`, and prove it by Integration ID.

`sha256(token)[:12]`, values never printed (CONVENTIONS §6):

| Item / install | value | service account |
|---|---|---|
| `op_api` — **current** | `d633b4f9190e` | Integration `QO3TQ6IMYJF5LFB5EUERCEGJEY` — **read scope** (the read item's own integration, read off the console's scope page) |
| `op_api` — superseded, live until ~2026-10-30 | `6a1342f44e65` | Integration `DUW6UPKY5JGG3MM6WF3HBHQWGQ` (read) |
| `op-write_api` — **current** | `c387f297133f` | Integration `RBULV4SW7JDKLDXRG25LC44VVI` (read+write) |

Each minted generation of these items answers with **its own Integration ID** — `op_api`'s superseded
generation answers `DUW6UPKY5JGG3MM6WF3HBHQWGQ` and its current one `QO3TQ6IMYJF5LFB5EUERCEGJEY`, and
the write item's measured generations answered `PR4Z2FGWW5BRXNL6OR3FNYL3R4`, then
`WN7FJT54IVHDDC4XR3YJ73R2CY`, then `RBULV4SW7JDKLDXRG25LC44VVI`. So an ID that matches no row here is a generation this table has not
recorded, and the value hash (the sweep below) settles which item it belongs to — the current `op_api`
value hashes apart from `op-write_api`'s AND answers an ID apart from its integration, which is what
separates a re-seated seat from a mis-seeded one.

**A seat cannot measure the scope of an Integration ID it has never seen.** `op item create --dry-run`
never reaches the API (it answers rc 0 for both items), and `op item delete`/`edit` on a name that does
not resolve dies at **name resolution**, not at the write permission — so neither is a scope verdict.
The verdict is a write that reaches the API and fails, or the console's own scope page.

The grace window on a superseded `op_api` value is **owner-set at the rotation**, not a product
default: the superseded generation expires **~2026-10-30**, and every holder must re-seat inside that
window (§Rotating the control-node token). A re-seat proven after that date is a re-seat of a dead
token. The two facts are not interchangeable: the **value hash** is what identifies a holder (the
sweep below), the **Integration ID** is what proves scope. An install whose `op whoami` answers a
write-scoped ID other than the row above is running a superseded credential.

A rotation revokes the consumers of **that item**, and only them. Enumerate consumers by *value hash*,
not by *doc row* — a host can appear in one item's row while carrying the other item's value.
Sweep form (hashes only, never values):

```bash
for f in ~/.config/op/homelab-sa-token /home/*/.config/op/homelab-sa-token /root/.config/op/homelab-sa-token; do \
  [ -f "$f" ] || continue; ( set -a; . "$f"; set +a \
    ; printf '%s  %s\n' "$f" "$(printf %s "$OP_SERVICE_ACCOUNT_TOKEN" | sha256sum | cut -c1-12)" ); done
```

⚠ **The `/root` path is part of the sweep, not an extra.** Run as an ordinary user it silently matches
nothing, so the one install no leg ever re-seats — a root-side copy — goes unlisted (§Where a token is
installed). Run the sweep with `sudo` on every host.

⚠ **A sweep sees one host.** `~` and `/home/*` are the paths of the machine the loop runs on, so the
control node's sweep never lists `vps`'s install. Enumerating consumers means running the loop on
every host in §Where a token is installed, not on the one you are standing in.

⚠ **A bare-value token file is hashed, never sourced.** `~/.config/op/homelab-sa-token` is
`export OP_SERVICE_ACCOUNT_TOKEN=…`, so the dot-and-hash above is safe. `/etc/op/provision-token` is the
**bare token**, and `. "$f"` executes it: bash answers `command not found` **with the whole value on the
line**, which writes the credential into whatever is capturing that output — the leak class
[`deployment-secrets.md`](deployment-secrets.md) §Creation & Rotation Workflow item 7 bans. For that shape
hash the bytes, and prove liveness without a value in the environment of anything that prints:
```bash
printf '%s  %s\n' "$f" "$(printf %s "$(cat "$f")" | tr -d '\r\n' | sha256sum | cut -c1-12)"
OP_SERVICE_ACCOUNT_TOKEN=$(cat "$f") op item list --vault Homelab-ansible   # value: in the child env, never on a command line
```

⚠ **Sweep the whole value — a prefix is not evidence.** In an `ops_`-family token the leading bytes are
an envelope, not entropy: the first 80 characters are byte-identical between `op_api` and
`op-write_api`, and byte-identical between two generations of the same item (the write item's two
generations first differ at byte **161**). All of those 80-char prefixes hash to `bd8441df3705`. So a
transcript that captured only a prefix names neither the item nor the generation, and a prefix hash
matches every holder of a different credential too.

### Rotating the control-node token
`scripts/ansible/bootstrap-runner.sh` is **create-only** — `if [ ! -f "$OP_TOKEN_FILE" ]` — so after a
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

**Rotating `op-write_api` is not the re-seat.** Seat and runner files carry `op_api`, so a write-token
rotation reaches them not at all; the write credential reaches its hosts only as the **rendered copy**
`/etc/op/provision-token`, which no rotation touches. After rotating the item, the re-seat is the pass
that re-renders that file: `op-provision-token.yml` (`docker_services_op_provision_token`) on a
non-Authentik host, or the Authentik pre-pass on the VPS. **Both writers are gated `scope_is_all`, so the
refresh cannot be narrowed by scope — only by tag, and only on top of a full-scope run:**

```bash
# vps — the pre-pass is the authoritative writer; `--tags secret-egress` keeps the run to the render +
# the token + the glue, and touches no container:
bash scripts/ansible/ansible-run.sh playbooks/vps.yml -e docker_services_scope=all --tags secret-egress
# a home host (oldsrv today) — the token task carries only `docker_services`, so the run is the whole
# role at full scope. It also reaches the Technitium seed's prune read, which is broken (HD-1152), so
# expect a RED RECAP AFTER the token task lands and its own probe answers: read it by task, not by rc.
bash scripts/ansible/ansible-run.sh playbooks/home_servers.yml -l oldsrv.kogler.si -e docker_services_scope=all --tags docker_services
```

Both are laptop-issued (`self-converge-guard.yml`). Until the pass lands, the host keeps presenting the
superseded value and every read-side check still passes — so prove a host with the hash sweep above plus
its own `op item list --vault Homelab-ansible` answer, never with `[ -r … ]`.
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
  on a headless Debian seat with only `~/.config/op/homelab-sa-token` installed — no
  interactive `op signin`, no desktop app, no 2FA. The path resolves that file through
  [`../scripts/lib/vault-env.sh`](../scripts/lib/vault-env.sh) **before** it asks `op` anything, which is
  the part that matters: the token is a `0600` FILE and `op` reads only the environment, so a seat that
  holds the file and exports nothing fails the vault preflight with "you are not currently signed in"
  and gets advice no non-interactive shell can answer. The Win11 seat raises the same item with
  `git-bootstrap-win11.sh --git-identity` / `--raise-key`, borrowing the engine's install across the
  door. The `OP_VAULT` override covers any machine whose
  items still live in the other vault (`OP_VAULT=Private bash scripts/git/git-bootstrap.sh --ssh-auth`).
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
| **Secret VALUE leaked into chat/transcript — via `op item get --reveal` or a bare `op read` whose stdout the session captures** | **The leaked value is compromised and a transcript cannot be scrubbed — rotation is the only remedy**, so rotate first and reason about blast radius afterwards, never the reverse. A **partial** leak counts as a full one: an `ops_` service-account token's first ~80 bytes are an envelope shared by every generation of the item, so the transcript does not tell you how much of a working token got out, and a shorter-than-expected value is not "only part of it". If it's a shared Authentik client (`headscale_api`), regenerate the provider client_secret in Authentik, `op item edit` the 1P item, and re-render the consuming services. If it is a **shared registration secret** (Tuwunel's `matrix_password`, which `tuwunel.toml` renders): the remedy is still rotation, and its cost is smaller than it looks — rotating invalidates the *registration door* (`/_synapse/admin/v1/register`) and nothing already registered, because accounts and access tokens minted through the secret live in the homeserver's own store; re-render the homeserver config through IaC and read the alert room back. **Never** inspect further in plaintext, and prove the rotation landed by length/hash prefix, not by reading the value (Output hygiene below) |
| `Failed to change ownership of the temporary files` | `acl` package (`setfacl`) missing on the target host — added to the `common` role prereqs |
| **`Couldn't get agent socket?` then `fatal: failed to write commit object` on `git commit`** | `gpg.format=ssh` with `user.signingkey` in the `key::<pub>` form and **no `SSH_AUTH_SOCK`** in a non-interactive shell (pi, cron, a converge). Set `user.signingkey` to the key FILE when it is passphrase-free — `ssh-keygen -y -P '' -f ~/.ssh/github_signing` answers that question — or export `SSH_AUTH_SOCK=/run/user/$(id -u)/openssh_agent`. Refusing the commit is the correct failure; a silently unsigned commit is not (CONVENTIONS §6) |
| **`git log -1 --format='%G?'` prints `N` on commits you know are signed** | No `gpg.ssh.allowedSignersFile` configured — git cannot verify, so it reports `N` for every commit, signed or not. Use `grep -c '^gpgsig'` over `git cat-file commit HEAD` meanwhile, then set the file (deployment-manual.md §0.4a) |
| **`op item edit` returns `error: an HTTP error occurred … 404` right after clearing a field** | **Spurious (op CLI 2.39).** The write has ALREADY been applied — the 404 is the CLI's post-edit re-read hitting a stale revision. **Re-read the item to confirm the new state instead of retrying**, and never treat it as "nothing happened" — that class of failure only repeats the clear or corrupts the field ordering |
| `op item get <item>` prints something like `REDACTED`/a hint where a value should be, and a comparison "fails" | `op item get` **without `--reveal`** returns a non-secret hint string, not the value — so any equality test against an expected secret is false by construction. Add `--reveal` (and keep the output out of transcripts per §Output hygiene), or compare a `sha256` of the revealed value instead of the value itself |

> **Secrets rule (CONVENTIONS §6):** never put token/item values in docs or git. This file
> documents *where* and *how*; the values stay in 1Password and the `0600` runner file.

### Output hygiene (CONVENTIONS §2) — prove presence, never print

When a probe or rotation touches a secret, print **lengths / prefixes / item IDs / hashes only** —
never a full value. A read probe therefore ends in `| wc -c` or a `[[ -n … ]]` test, and a **bare
`op read` in a shell whose stdout is captured is the failure shape**: the value goes straight into the
session/transcript log, where it cannot be scrubbed and only rotation removes it. `op item get …
--reveal` into a shell that echoes to a session/transcript log is how live client_secrets leak into
chat.

**Proving a value's presence = a length or a short hash prefix, never the value.** The same
12-character `sha256` prefix on both sides is the proof that a rendered config holds the vault value;
take it through a pipe so no intermediate step can echo the value, and never write a **full** hash of a
live secret anywhere a transcript can carry it (a full hash is an offline guess-check against a
low-entropy value).

```bash
# vault side — length and 12-char prefix, the value never lands on a tty or in a log
op read 'op://Homelab-ansible/<item>/<field>' | tr -d '\n' | wc -c
op read 'op://Homelab-ansible/<item>/<field>' | tr -d '\n' | sha256sum | cut -c1-12
# deployed side — the SAME prefix from the rendered file (here: the homeserver's registration secret)
sudo grep -m1 '^registration_shared_secret' /opt/matrix/tuwunel.toml \
    | sed -n 's/.*"\(.*\)"$/\1/p' | tr -d '\n' | sha256sum | cut -c1-12
```

A **stale deployed copy** is the usual finding after a rotation, and it is not fixed by hand: re-render
it through that service's own narrow converge, which is also what restarts the container that reads the
file only at start ([deployment-secrets.md](deployment-secrets.md) §Master Secret List).

Rotating a shared Authentik client: regenerate the secret in the
provider ORM (providers don't expose `generate_client_id`; `authentik.lib.generators` has
`generate_id`/`generate_key`/`generate_code_fixed_length`), persist to the 1P item, then
re-render the consuming services (headscale + headplane read `headscale_api`) and verify —
full step-by-step (incl. the `docker cp`-broken + `op --template`-stdin gotchas) lives in
[`services-authentik.md`](services-authentik.md) *Rotating a shared Authentik OIDC client secret* runbook.