# `prompt-seat-cockpit-grants.md` — Lane brief · Cockpit on both nodes, the coding seats, grants, the seat plane

> **Role:** dispatch note for **one** lane session on the cockpit / coding-seat / grants domain. **The rows are the
> authority** for what is missing and how to do it — this file carries the contract, the order of work and the traps,
> nothing else: [todo.md](todo.md) **HD-361 · HD-442 · HD-443 · HD-465 · HD-444 · HD-411 · HD-495 · HD-1085 · HD-1110 ·
> HD-1115** (row ids as of `16177f19` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O9) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers and this brief deliberately restates none of them.

**Converge hosts + slots (O3):** **oldsrv** (`roles/cockpit`, the tailnet listener's dynamic dir, `roles/access`) and
**nas** (the second cockpit host) — one converge in flight per host, detached, **never `--diff`**. `roles/access` fans out
to vps/oldsrv/nas/pi/spark, so a grants converge touches **every** host slot: run it host-by-host, not as one tree-wide run.
⛔ **Do not share a wave with another oldsrv lane** — same `websecure-ts` listener, same container set, and `cockpit` plus
`access` are both in the SSH-lockout class: drive them **off-box**, never from the box you are changing.
**The seat plane is not a converge**: `scripts/pi-seat-sync.sh` and its per-plane owners deploy from each seat's own clone.
Before any `scripts/pi-config/` hunk, `git worktree list` + `git log --oneline -3 -- scripts/pi-config` — a live pi-seat lane
edits the same directory.

**Read first:** [docs/security.md](docs/security.md) (cockpit `maint`, the grant rulings) →
[docs/services-traefik.md](docs/services-traefik.md) §Cockpit Routes → [docs/pi-harness.md](docs/pi-harness.md) §1, §5, §5a,
§5b → [docs/services-ai.md](docs/services-ai.md) §9b → [docs/deployment-secrets.md](docs/deployment-secrets.md).

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-465** | Land a **deployed** tailnet cockpit router on the node that serves the listener, then load the authenticated pane in a browser from **off the tailnet** | The ruling is **both nodes serve the Cockpit tailnet surfaces** — the 2026-10-01 "oldsrv owns Cockpit" ruling is superseded. What is still missing is a router that reaches a live edge: `IaC/ansible/roles/cockpit/tasks/main.yml:56` writes `/opt/traefik/dynamic/cockpit.yml` on oldsrv, which is the **VPS** project's file-provider dir (`templates/docker_services/traefik/docker-compose.yml.j2:65`), while the `websecure-ts` listener lives in **traefik-internal** (`.../traefik-internal/docker-compose.yml.j2:69`) and watches that project's own `./dynamic`. `cockpit-routes.yml.j2:46` already authors `cockpit-nas-ts` on `websecure-ts` — it has never reached an edge |
| 2 | **HD-361** | Prove the authenticated Cockpit pane **in a browser, per host** (`maint`) | ⛔ `--tags cockpit --check` can never be green on any host: every read-back is a `command`/`shell` task skipped under `--check`, so the asserts read empty stdout and scream on a healthy box. Fix shape = `check_mode: false` on those read-back tasks. Only `GET /cockpit/login` + Basic tells the truth, and even 200 leaves the WebSocket Origin check unproven. The nas-from-away half is HD-465's, not cockpit's |
| 3 | **HD-443** | Read the Pi's sshd journal for `admin` acceptances and revoke only when it reads 0; sanction the operator's own path first if any acceptance is recent | ⛔ Order is the safety property: place `domen` → prove it logs in → dated marker + disabled `authorized_keys` file → prove the dependents → only then remove; the role asserts `ansible-admin` stays in `AllowUsers` **before** the template task and re-reads the live config with `sshd -T` after. ⏳ Owner leg to park with its exact text: the 1Password item rename `laptop-domen.pub` → `dome_ssh.pub` plus the client `IdentityFile` repoint |
| 4 | **HD-442** | Run the catalog-vs-vault completeness read (the seat's SA token authenticates `op`, so this is AI work, not an owner gate) and report; **revoke nothing** unless the read disagrees | ⚠ `item list` is not `item get`. ⚠ Mint trap: `ssh oldsrv` lands on the **ansible-admin** seat and the seat's env file is `0600 domen` — an unprivileged read yields EMPTY and hash-vs-hash then "matches" empty against empty. **Assert LENGTH before comparing fingerprints.** Any consumer treating a token file's *existence* as its *validity* must fail loud on 403 |
| 5 | **HD-495** | Two legs only: move the hand-planted seat state into IaC (the gitconfig, the two `~/.ssh` keys, `allowed_signers`, the `~/.bashrc` blocks — all derivable from `Homelab-ansible`), and re-seed + prove every SA-token consumer (runner clone, the seat's `~/.config/op/homelab-sa-token`, the Forgejo `vault-gate`) before the rotated value's predecessor expires; report lengths/hashes, never the value | ⛔ Commit signing is **retired**: a rebuild recovers `gpgsign=false`, so plant no signing key, never run `git commit -s`, and never re-add the `ssh-add ~/.ssh/github_signing` recovery. A consumer left on the old token fails its vault writes **silently** — the HD-442 class |
| 6 | **HD-444** | ⏳ Owner hand, park and continue (O4): the phone crossing — PWA over the tailnet, **laptop shut**, token gate + session list + one chat round-trip | It gates HD-411's comparison window. If headscale denies phone→oldsrv on the cockpit port, record the exact denied pair in the **transport lane's** file — do not edit tailnet policy here |
| 7 | **HD-411** | PARKED — resume only on the owner's word (needs a hand on the phone; the browser cockpit is primary by design) | The npm name-squat is in the row: the real package is `@getpaseo/cli`, not `paseo`. The verdict lands in [docs/services-ai.md](docs/services-ai.md) §9b either way — accepted → full onboarding, abandoned → tombstone with the decision kept |
| 8 | **HD-1085** | The leg no in-repo probe can reach: mouse-select text inside a tmux pane on a Debian seat, then paste it on the machine you typed from | Name the gate by what it checks, not by its number: `scripts/install-tmux-conf.sh --self-test` plus `--check --strict` (repo `pi-agent/tmux/tmux.conf` == `~/.tmux.conf` **and** the config actually takes effect). If nothing arrives the seat is correct and the **outer terminal** refuses OSC 52 (`xterm` needs `allowWindowOps: true`; VTE ≥ 0.60, kitty, wezterm, foot, alacritty accept by default). A foreign `~/.tmux.conf` stays a REFUSAL by design |
| 9 | **HD-1110** | Run `bash scripts/pi-seat-sync.sh --push` where it has never run: the `wsl` seat's `pi` on PATH is the Windows Volta shim and fails `volta: command not found`, so `scripts/install-pi-wsl.sh` has never been run there; then resolve the `models` plane's `pi_auth` drift | An UNREACHABLE seat **fails** the run; a clone not at this commit is `STALE-CLONE` and its planes are not run. From the laptop the `oldsrv` leg is down (the jump's `IdentityFile` points at a PUBLIC key — HD-443's owner tail): run that seat from WSL or on the seat (§5a local form). ⚠ The drift is the finding: the seat holds an **OAuth** openrouter entry while the spec renders `api_key` — decide which side is wrong, never overwrite live tokens to make a check pass |
| 10 | **HD-1115** | Let the Debian seats converge the `pi-self` plane when their clone reaches this commit (it rides HD-1110's legs), and name a mechanism for any seat whose pi is neither Volta- nor pinned-prefix-managed | `pi_host_npm_version` / `pi_dev_npm_version` are both **1.1.0** (`IaC/ansible/group_vars/all/versions.yml:513`, `:267`) and MUST stay equal. `BEHIND` and `AHEAD` are both drift — AHEAD is the shape that hides (an unpinned `@latest`, a hand-run `pi update self`). ⚠ `pin()` runs inside `$( )`, so its `exit 1` leaves the caller running with an EMPTY value; the same shape is still unfixed in `scripts/install-pi-debian.sh` and `scripts/pi-settings-config.sh` |

## ⛔ Traps that cost a round (re-grounded at this `HEAD`)

* **Cockpit's tailnet surfaces are served by both nodes** — this is the current fact, not the old "oldsrv owns Cockpit"
  ruling. The load-bearing detail survives the supersession and is not taste: `pi-oldsrv.ts.kogler.si` (the pi-web seat) and
  `cockpit-nas.ts.kogler.si` both ride oldsrv's `websecure-ts` listener, so changing which node owns the router moves the seat.
* **A file-provider path is a per-project promise.** `/opt/traefik/dynamic` belongs to the VPS `traefik` project; oldsrv's
  tailnet listener belongs to `traefik-internal`. Converging `roles/cockpit` writes a file nothing watches — the converge is
  green and the router is dead. Read the mount line of the edge that owns the entrypoint.
* **A Pi read-back proves nothing about `.ts`** — the `.ts` namespace is answered by the VPS primary (a **zone** fact, not a
  `resolv.conf` symptom, and the HD-488 resolver fix did not change that). **Being off the tailnet is the blocker; being away
  is not.**
* `--check` on `cockpit` is structurally red; `--check` on a guarded converge is what an unattended run is authorised for, so
  say which of the two you ran.
* **Never interpret a missing measurement as a negative result**, and never present two identical failures as evidence
  (CONVENTIONS §6). This lane is full of owner hands: an unmeasured phone leg is **not** a denial.
* HA guest accounts are a **declared scope limit** of the grant plumbing, never a finding of "clean".
* Converge `roles/access` / `roles/cockpit` from **off** the target, never from the box whose `AllowUsers` you are editing.

## Owns / never touches

**Owns:** `IaC/ansible/roles/cockpit/**` and `IaC/ansible/roles/access/**` with `group_vars/all/access.yml`, the cockpit legs
of the tailnet listener's dynamic dir, `scripts/{pi-seat-sync.sh,pi-settings-config.sh,pi-tui-config.sh,pi-self-update.sh,install-tmux-conf.sh,install-nerd-font.sh,install-pi-debian.sh,install-pi-wsl.sh,sync-extensions.sh,git-bootstrap.sh,git-bootstrap-win11.sh}`
and `scripts/win/`, `scripts/pi-config/`, `pi-agent/**` (incl. `tmux/tmux.conf`, `settings-ssot.json`),
`scripts/git/`, the grant/seat sections of `docs/security.md`, `docs/services-traefik.md` §Cockpit Routes,
`docs/pi-harness.md`, `docs/services-ai.md` §9b, `docs/deployment-secrets.md`, and your own `todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2) or another brief's rows; headscale/tailnet **policy** files and the DNS answer
plane (the transport lane records the denied pair); traefik edge/route work beyond the cockpit routers; the Authentik clients
and OIDC providers (the edge-identity lane); `templates/docker_services/{litellm,lan-litellm}/**`; `roles/monitoring/**`;
`IaC/router/**` and the global router slot; the laptop's LM Studio legs (the laptop brief); the Kopia/backup rows; the frozen
archives and generated `*-generated.md`.

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path counts as
not run. Concretely: the cockpit tailnet router **deployed** — the rendered router quoted from the file-provider dir of the
edge that owns `websecure-ts`, plus an off-tailnet browser load of the authenticated pane on each node · the `--check` red on
`cockpit` turned structural (`check_mode: false` on the read-backs, with one healthy-host run quoted) · Pi `admin` revoked
only at a zero acceptance count, or parked with the count read · the vault/catalog read reported with disagreement named and
nothing revoked on assumption · the seat's hand-planted state owned by IaC or the gap named, and every SA-token consumer
re-seeded with hash/length evidence · the phone crossing and the Paseo verdict `PARKED` with their exact blocked actions ·
the OSC 52 leg answered per outer-terminal, with the in-repo gate quoted by what it checks · `pi-seat-sync.sh --push` run on
the seat that never had it, and the `pi_auth` mode decided rather than overwritten · the `pi-self` plane green on the Debian
seats or the seat's mechanism named · rows trimmed to their tails or deleted, no history in the row ·
`bash scripts/validate-all.sh` green **in this worktree** → **stop**.
