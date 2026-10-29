# prompt-refresh.md — the brief-refresh pass: the cells the pin window falsified, and the fan-out that corrects them

> **Rows it carries:** none. This brief carries a run, not a queue. The rows named below are **ridden, not
> carried** — each keeps its own owner and its own brief; no row is minted for the act, and no ownership moves
> here. The `todo-table.md` §B0 wiring is part of the final handoff pass (Phase 4).
> **Role:** the runbook for bringing the `prompt-*.md` family back in line with `todo.md` after the pin window
> falsified a third of its cells — plus the **dependency order** the ranked pointer list in `prompt.md` §2 does not
> carry, because a priority list and a run order are two different facts. Author-only: **no converge, no host act,
> no secret act runs anywhere in this run.**
> **Linked from:** [prompt.md](prompt.md) §2 · executed state in
> [plan/tasks-refresh-briefs-20261029.md](plan/tasks-refresh-briefs-20261029.md) (the work package; it dies with this file).

---

## 0. How to run this file

- A phase is **done** when every box in it is ticked. `todo.md` is touched **once, in Phase 4** — the lanes touch
  no registry file at all (see §2), so there is nothing for a lane to record there.
- ⛔ No `HD-` id is minted for anything in this file. A closed row is deleted; a doc states facts and never
  session history (CONVENTIONS §4/§6.4).
- **Per-lane execution state — the branches, the worktrees, the parks — is
  [`plan/tasks-refresh-briefs-20261029.md`](plan/tasks-refresh-briefs-20261029.md)**. The boxes here say what is
  owed; that file carries what each lane proved and what it parked, and it dies in the same commit as this one.
- The **last content act, before this file dies, is the handoff pass** (`prompt.md` + `todo-table.md` §B0) — once,
  at the end, not per task. Phase 4 holds it, ending with both files deleted.
- ⚠ A lane that *describes* its work has done nothing: only `git log` in its worktree decides
  ([docs/orchestration.md](docs/orchestration.md) §4 Merge + cleanup step 1).

## 1. State this brief was written against

- Station tip `fe3cd5c1`, `validate-all.sh` green on a clean `main` (`rc=0`; the only reds a run prints are the
  self-test canaries inside the checkers).
- The pin window (`prompt-update.md`) ran 2026-10-28/29 under rulings N1–N7 / S1–S10: **Phases 1–4 landed**
  (the pin commit, most rotations, and the `pi`/`vps`/`nas`/`oldsrv` converges), **Phase 5 (router/switch) and
  Phase 6 (spark) did not run**, Phases 7–8 are owed. Consequence: the fleet is at the NEW pins on four hosts
  while spark publishes the new pin map over old packages — six `differ` rows that are a parked apply, not drift.
- **The next content window is `prompt-update.md` Phase 6** — the spark converge and the v32 flips, taken in an
  externally-served sitting on the WSL station with the owner present (Rule 0: a spark-served session cannot run
  it, and it is the one act in the fleet whose model choice the agent does not get to make — README §3).
- **A sibling session's lane is unmerged on this station:** branch `session/20261029-hd435`, head `94bbcdde`,
  worktree `../homelab-wt-20261029-2232`, touching `prompt-dns-transport.md`, `todo.md`, `todo-table.md`,
  `docs/network-{vpn,dns,rejected}.md` and `docs/smart-home-failover.md`. It is not this run's to remove (O8), and
  it is the reason the dns brief is the ONE brief this run does not touch.

## 2. The lane rule that makes this safe

Two full lanes, ≤2 live children, the parent's model, one writer per cwd, `async: true`,
`checkpointBeforeDeadlineMs: 600000` (effective on this seat —
`~/.pi/agent/extensions/subagent/config.json`, not merely authored). Everything below is O1–O11 of
[docs/orchestration.md](docs/orchestration.md) §4, restated only where this run differs from a normal lane:

- ⛔ A lane edits **nothing** but its own listed brief files. Not `todo.md`, not `todo-table.md`, not
  `prompt.md`, not `prompt-update.md`, not `plan/` — the views are the parent's (O2), and in this run that means a
  lane touches **no registry file at all**.
- ⛔ A lane does **not** change the `Rows it carries` id list in its brief's header. That triple (§B0 ↔ brief
  header ↔ `prompt.md`) is held equal by `python3 scripts/gate/check_brief_coverage.py` — 115 assignments over 13
  briefs, 85 handoff assignments, re-derived by that command and by nothing else.
- A row that contradicts its brief is the brief's bug, not the row's: fix the brief to match the row and report
  the contradiction. `todo.md` is the authority and it is current.
- Facts only: no session narrative, no dated results, no typed count a command can print (CONVENTIONS §6.4).

## 3. Phase 0 — the station, and the worktrees to TAKE (not recreate)

This session already paid for the checkouts. **Take them over; do not `git worktree add` new ones for the same
lanes, and do not remove them until Phase 2 has merged what is in them.**

| lane | worktree | branch | forked at | files it owns | state |
|---|---|---|---|---|---|
| A | `../homelab-wt-20261029-2309` | `session/briefs-net-obsv-stor-20261029-2309` | `fe3cd5c1` | `prompt-observability-alerting.md` · `prompt-storage-backup.md` · `prompt-spark-llm.md` · `spark/reports/external-window-card.md` | clean, **no commit** — its children were stopped at 2026-10-29 22:32 before writing anything |
| B | `../homelab-wt-20261029-2310` | `session/briefs-home-media-seat-20261029-2309` | `fe3cd5c1` | `prompt-smart-home.md` · `prompt-media-arrs.md` · `prompt-seat-cockpit-grants.md` · `prompt-scripts.md` | clean, **no commit** — same |
| parent | `../homelab-wt-parent-20261029-2309` | `session/handoff-runorder-20261029-2309` | `fe3cd5c1` | `prompt-refresh.md` · `plan/tasks-refresh-briefs-20261029.md` · `prompt.md` | holds this brief's own commits |

- [ ] `git fetch origin && git log --oneline -1 origin/main` — if `main` moved past `fe3cd5c1`, rebase each lane
      branch **inside its own worktree** before dispatching (`git -C <wt> rebase main`), then re-check the fork.
- [ ] `git worktree list` + `git -C <each wt> status --porcelain` — take the state, do not assume it.
- [ ] `bash scripts/validate-all.sh; rc=$?` on a clean `main` — green is the precondition, rc is the test.
- [ ] `bash scripts/harness/seat-llm-path.sh --check` → `path=lan` on the station, and `echo $PI_PROVIDER`.
      Both go **in the launch text**, not in the parent's head (§Launch 3's measured trap).

## 4. Phase 1 — the fan-out (two author-only lanes)

- [ ] Read [`plan/tasks-refresh-briefs-20261029.md`](plan/tasks-refresh-briefs-20261029.md) §A: it is the rule set
      **and** the per-file evidence table (which cell is stale, what it must say, and the row/commit that made it
      stale). The launches carry nothing but paths, so a lane reads the package, not a pasted corpus.
- [ ] Author the fan-out as a file, validate it, then launch it:
      `subagent({action:"validate", workflow:"/tmp/pi-lanes-<date>-<HHMM>.js"})` → then
      `subagent({workflow:"<that path>", async:true})`. The previous script is reusable as a template at
      `/tmp/pi-lanes-20261029-2309.js` while `/tmp` lives.
- [ ] Lane A and Lane B in parallel (disjoint files, no converge, so O3 is not even in play).
- [ ] Nothing steers on silence — a minutes-long pause on this engine is a compaction, not a hang (O11).

## 5. Phase 2 — merge (the parent, nothing else)

- [ ] Evidence before touching anything: `git -C <wt> log --oneline main..HEAD`, `git show --stat`,
      `git status --porcelain`, in **both** lanes. A report is not evidence.
- [ ] FF lane A into `main`; `bash scripts/validate-all.sh; rc=$?` in the primary (clean-main is the exempt form).
- [ ] Rebase lane B onto `main` **inside its worktree**, re-gate **there**, prove
      `git merge-base --is-ancestor main <branch>` exits 0, then FF-merge (O1).
- [ ] `comm -3 <(git show main:todo.md | grep -oE '^\| HD-[0-9]+' | sort -u) <(git show <lane>:todo.md | grep -oE '^\| HD-[0-9]+' | sort -u)`
      — empty in both directions. It should be trivially empty here: no lane was allowed to touch the registry,
      which is exactly why an empty answer is *proof* rather than luck.
- [ ] `python3 scripts/gate/check_brief_coverage.py` green; `python3 scripts/gate/check_todo_done.py --refs` green.
- [ ] Inventory the residue before removing anything: `git -C <wt> status --porcelain` (a merged lane can still be
      dirty), then the two process reads (`ps -eo args | grep -E 'ssh .*(-N|-L|-D)'`, `ss -ltn`).
- [ ] `git worktree remove` the two lane worktrees, `git worktree prune`, `git branch -d` both branches (O8; a
      patch-absorbed branch needs `git rebase main <branch>` first, never `-D`). Leave
      `../homelab-wt-20261029-2232` (the sibling's) alone.

## 6. Phase 3 — the deferred third wave (after the sibling branch lands)

- [ ] `git merge-base --is-ancestor session/20261029-hd435 main` — if it answers 0 (or its content landed by
      rebase), the collision is gone; if not, it is still an open sibling lane and this whole phase stays parked.
- [ ] **`prompt-dns-transport.md`** — refresh it the same way: HD-435's publish half is now **live and inert**
      (`ha` is `dual`, both home edges answer that SNI, but a tailnet client answers the name from ONE
      `extra_record`, so the away path that survives is the other node's own `pi.ts.kogler.si`); HD-487's one owed
      act is the **VPS** delete of the dead `20-eno1.netdev`; HD-1152's first real apply and the router-slot items
      (HD-1160, HD-1133, HD-461) are owner-present parks. Read the row, not this summary.
- [ ] Verify (do not assume) the four briefs this run declared "current enough": `prompt-external.md`,
      `prompt-secrets.md`, `prompt-laptop-wsl.md`, `prompt-edge-identity.md`, `prompt-litellm-consumers.md`,
      `prompt-laptop-legs.md`.

## 7. Phase 4 — the handoff pass, then this file dies

- [ ] `todo.md` — only if a phase above actually moved a row; otherwise nothing.
- [ ] `prompt.md` §2 and `todo-table.md` §B0 re-derived for whatever closed; `check_brief_coverage.py` green.
- [ ] The handoff seal re-derives in the same commit: `python3 scripts/gate/check_handoff_size.py --reseal`
      (the station's act, never a lane's) when the run grew `prompt.md` with real content.
- [ ] `bash scripts/validate-all.sh; rc=$?` green — or red only on a named, dated exception (the live-value leak
      debts: the `wifi-kogler*` PSKs, `spark-llm_api`/`litellm-engine_api` until Phase 6, `pppoe_login`/Soulseek as
      not rotatable, and `jellyfin-seer_api`, which no machine path can rotate).
- [ ] Commit, FF-merge, push. Then **delete `prompt-refresh.md` and
      [`plan/tasks-refresh-briefs-20261029.md`](plan/tasks-refresh-briefs-20261029.md) in that same commit** (O7).

## 8. The dependency ladder — where it lives

The ladder itself is **one fact and it lives in [`prompt.md`](prompt.md) §2** ("the dependency ladder") —
`prompt.md` is the dispatch view, so a second copy here is the twin every gate in this repo exists to catch. What
this run adds is only what the ladder cannot carry: **rank is not order** (the numbered list in `prompt.md` §2
ranks by what unblocks the most; the ladder says what must run first), and the exclusions below.

⛔ Never inside the Phase-6 window: the router/switch items (ruling N3, the global slot), the `llm.kogler.si`
answer flip (it moves the answer for every client and lands on the converge that re-renders headscale's
`config.yaml`), the five `pin-major-*.md` majors, any spark hunk of the observability lane **inside a bench
window**, and any second metrics-window sampler or profile flip beside a spark-slot converge.

## 9. Traps

- **A brief that reads as current is the expensive kind of stale.** Every id in every brief still resolves
  (`check_todo_done.py --refs` proves it), so no gate tells you a cell describes work a lane already did. The
  sweep is: read the row, read the brief's cell for it, keep what the row still asks.
- **Do not "fix" a brief by moving a row to a different brief.** The row→brief map is one fact in three views and
  a checker holds them equal; a lane that edits one view sends the parent a red gate instead of a fix.
- **No lane reseals a ratchet.** A size reminder a lane prints is the parent's to clear at the merge.
- **`spark/reports/hd*/` are dated records** — immutable. The external-window **card** is a dispatcher page and is
  in scope; a dated result is not.
- **Never delete or edit a transcript to quiet a leak check** (HD-1181), and never edit a checker to mute a live
  value. A red leak gate is the designed state until a rotation lands.
- **⛔ never `git commit -s`** — signing is retired; `git log -1 --format='%G?'` → `N` is the expected value.

## 10. Held out on purpose

`prompt-dns-transport.md` (a live sibling lane holds it, §1) · every converge, every secret, every host act (this
run is author-only by construction) · the pin window's own Phases 6–8, which are the content window this run
prepares for and are **not** run from here · the dated `spark/reports/hd*/` records and the frozen `reports/`
archives · the five `pin-major-*.md` root briefs · any new brief, any new row, any view edit by a lane.
