# `prompt-361.md` — Lane brief · the cockpit / coding-seat / grants lane on oldsrv (HD-361 · 442 · 443 · 445 · 446 · 465 · HD-444 · HD-411)

> **Role:** dispatch note for **one** lane session. **The rows are the authority** for what is missing and how to do it:
> [todo.md](todo.md) HD-361 · HD-442 · HD-443 · HD-445 · HD-446 · HD-465 · HD-444 · HD-411. This file carries the lane
> contract, the order of work, the pairing and the traps — nothing else. History lives in the owning docs and in git.
> **Linked from:** [prompt.md](prompt.md) §3 · [todo.md](todo.md) · [todo-table.md](todo-table.md)

**Contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O8), which overrides README §4 / CONVENTIONS §6 at the
items it numbers. One session, one worktree, one branch, one brief. Never edit `prompt.md` or `todo-table.md` (O2); edit
**only your own `todo.md` rows**. Owner gate → **park and continue** (O4), naming the exact blocked action. Close-out =
owning doc + row tails + signed commit + `bash scripts/validate-all.sh` green **in this worktree** → **stop**. When the last
row closes, tell the parent: **this brief dies in the parent's cleanup commit** (O7), not in yours.

**Converge host:** **oldsrv** (`roles/cockpit/**`, `/opt/traefik-internal`, the seat units). One converge in flight,
detached, **never `--diff`** (O3). **nas / pi are read-back only.**
⛔ Never in the same wave as [prompt-384.md](prompt-384.md) or [prompt-357.md](prompt-357.md) — same oldsrv slot. Also
never in the window of **HD-487** (oldsrv lockout-class — it edits the leg the converge rides).
✅ **2026-10-05: the seat-shaped cut (the pi-dev-seat lane) closed and its brief is gone**, so the oldsrv slot is no longer
contested by it. It took **445** and **446** with it and left **442**/**443** with owner-gated tails — which changes what is
left *here*: this lane's seat-adjacent residue is now the phone drill (**444**, owner) and **411**/**465**, not the cockpit
role or the installer.

**Design SSOTs:** [docs/security.md](docs/security.md) (cockpit `maint`, the grant rulings) ·
[docs/services-traefik.md](docs/services-traefik.md) §Cockpit Routes · [docs/services-ai.md](docs/services-ai.md) §9b (the
seat plane) · [docs/pi-harness.md](docs/pi-harness.md) §1/§4 · [docs/deployment-secrets.md](docs/deployment-secrets.md) ·
[deployment-manual.md](deployment-manual.md) Phase 4c.

## Order of work

| # | Row | Do | Note |
|---|-----|----|------|
| 1 | **HD-445** | Give the coding cockpit an **owning role**: render unit + drop-ins + env path + linger from the vars | `docker_services` is the wrong home (owner-decided: not containers). Must be `--check`-safe on the first try. Render **both** drop-ins — `loopback-bind.conf` **and** `pi-on-path.conf` (a systemd **user** unit gets no login PATH, which is what a phone reported as "no model available"). `tmux` is the owning role's package decision, not a hand `apt install` |
| 2 | **HD-443** | Own users + `authorized_keys` in a role → converge `ansible-admin` / `domen` / `ai-debug` on reachable nodes → re-run the auditor | ⛔ The **order is the safety property**: prove `ansible-admin` logs in → comment the line out with a dated marker → prove the dependents → only then remove (HD-413 lockout set). Re-read the reverted Pi `admin` retirement first. The owner's 30 s SSH-agent-stub rename stays in the row |
| 3 | **HD-465** | Land the **deployed** `cockpit-nas-ts` router so `Host: cockpit-nas.ts.kogler.si` answers on the tailnet listener | Owner ruled 2026-10-01: **oldsrv owns Cockpit** (load-bearing — both `pi-oldsrv.ts` and `cockpit-nas.ts` ride oldsrv's `websecure-ts` listener). ⛔ A converge alone will not do it; the row carries why (dead render + the router that never reached an edge) |
| 4 | **HD-361** | The authenticated Cockpit pane **in a browser**, per host | ⛔ `--tags cockpit --check` can never be green — the row carries the `check_mode: false` fix shape. ⚠ `cockpit` is in the HD-413 lockout set: drive it off-box |
| 5 | **HD-442** | The damage audit: what the oldsrv glue and key-provisioning passes were supposed to write since the token went stale, verified one by one | ⛔ Any consumer treating a token file's *existence* as its *validity* must fail loud on 403. ⚠ Mint trap: `ssh oldsrv` is the **ansible-admin** seat, not `domen`, and the seat's env file is `0600 domen` — an unprivileged read yields EMPTY and hash-vs-hash "matches" empty against empty. **Assert LENGTH before comparing fingerprints** |
| 6 | **HD-446** | `scripts/install-pi-debian.sh` — the sibling of `install-pi-wsl.sh` | Worth writing **before the third pi host**, not before. The traps are in the row |
| 7 | **HD-444** | ⏳ owner hand: the phone crossing (PWA over the tailnet, **laptop shut**) | Park (O4). It gates HD-411's comparison window; if headscale denies phone → oldsrv on the cockpit port, record the exact denied pair in the transport lane's file — do not edit policy here |
| 8 | **HD-411** | PARKED — resume only on the owner's word | Resume facts (the real package name, the squat, the posture) are in the row. Verdict lands in [docs/services-ai.md](docs/services-ai.md) §9b either way; the browser cockpit stays primary |

## Traps

- ⚠ A rebuild of oldsrv today loses the cockpit silently until HD-445 lands — the seat is `domen` + linger.
- ⚠ Never interpret a missing measurement as a negative result, and never compare two identical failures as evidence
  (CONVENTIONS §6).
- HA guests (`haos-*`) are a **declared scope limit**, never "clean".

## Acceptance

Each row's ⏳ list empty → row deleted, record in the owning doc + commit. Cockpit-nas answers from away in a browser
(HD-465) · the phone crossing recorded honestly (HD-444) · grants owned by a role and re-audited (HD-443) · the seat owned
by a role (HD-445) · `bash scripts/validate-all.sh` green **in this worktree** → **stop**.
