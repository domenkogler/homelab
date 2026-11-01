# `prompt-gate.md` - Seat brief · the win11 seat's gate cost and the engine contract of its legs

> **Role:** dispatch note for **one** session on the laptop's **win11** seat: make `bash scripts/validate-all.sh` there
> cheap and honest. Two questions, answered leg by leg and never in general: **which engine** should run a leg, and **what a
> leg must declare** so a tool the far side lacks can never read as a pass. This is a **seat** brief: it claims **legs, not
> rows** - the rows whose tails this window moves are **ridden, not carried**, and stay owned by whoever [todo-table.md](todo-table.md) §B0 names
> (the engine's package act belongs to [prompt-laptop-wsl.md](prompt-laptop-wsl.md)'s seat leg; the pool question sits in
> [todo-table.md](todo-table.md) §B0's unbriefed tail until the orchestrator wires it). Re-derive every owner and id at your own `HEAD`, CONVENTIONS §4.
> **Rows it carries:** none. The [todo-table.md](todo-table.md) §B0 row and the [prompt.md](prompt.md) §2 pointer are the orchestrator's own pass (O2), not
> a lane edit.
> **Linked from:** nothing yet - the owner's entry point for this window.
> **Seat:** **run this file FROM win11** (Git-Bash, not a WSL launcher: `bash scripts/harness/seat-bash-build.sh --check`
> names which build a profile-loaded shell resolves). The legs marked `[engine]` land inside that box's own WSL Debian
> engine, and the `wsl` seat's clone is the comparison seat, not the driver. WHY the win11 seat and not the Debian one: the
> seat under measurement is the Windows one, and inside the engine the route is off by design, so a timing taken there
> describes a box that has no problem to fix - [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1.

**Contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1-O11) + [README.md](README.md) §4. One session, one worktree, one branch;
⛔ never edit `prompt.md` or `todo-table.md` from a lane (O2). ≤2 children live, `async: true`, the parent's own model
(O10-O11). No converge and no host act: nothing here touches a deployed box.

**Status — the engine's contract is written down and now enforced, and the seat's cost question has a mechanism as its
answer: the win11 launcher runs the tree legs, and that is the whole wall. A3 is landed; the open legs are
A7 (two-face grading — run it first), A2 (verdicts, not wall) and A5 (one run, not a sweep)**, dispatched at the end of §2.**
What exists now, and how to see it:

* **The parity harness** — [`scripts/bench/win/gate-parity.sh`](scripts/bench/win/gate-parity.sh) plus the planted legs
  in [`scripts/testdata/gate-parity/`](scripts/testdata/gate-parity/): rc 0 parity, rc 1 diff (naming the arm count and
  the verdict-word difference per side), rc 2 `CANNOT RUN`. **A run whose engine side never crossed answers rc 2** — the
  route's own testimony is read from the raw corpus, before normalizer rule 2 erases it, because a declined head and a
  crossed run are otherwise the same bytes. Re-derive: `bash scripts/bench/win/gate-parity.sh --self-test`, and
  `HL_WSL=off bash scripts/bench/win/gate-parity.sh -- bash scripts/testdata/gate-parity/portable.sh` → rc 2, with the
  parity word absent. The recognizer counts the words this repo's harness legs actually print (`GREEN`, `caught` among
  them), which is what makes a crossed self-test comparable at all; the vocabulary is stated in the runner's own header.
* **What the engine answers, in words** — the route's probe prints the inventory beside the `route:` line, so a leg's
  `CANNOT RUN` is read against a stated set instead of discovered per leg. Widening the pinned PATH to expose the
  engine's node is **refused**, with the condition that reopens it in
  [`docs/harness-rejected.md`](docs/harness-rejected.md); the node exists at `~/.local/share/pi-node/current/bin/node`
  and is unreachable by name, which is a probe question, not an environment boundary —
  [`docs/harness-pi-seats.md`](docs/harness-pi-seats.md) §1 carries the seat's own numbers and what they mean.
* **The `ms/exec` figure every run prints is the seat's real per-fork price from 2026-10-31 on, and a fifth of it before.**
  The host-cost probe resolved its target with `command -v true`, which in bash names the **builtin**, so the "five execs"
  loop forked once (the `$(seq)` word list) and divided that fork by five — on every seat. `type -P true` + `{1..5}` is the
  fix, `SKIP` prints where no `true` binary exists, and `degraded` moved to > 300. Re-derive both sides: native
  `t0=$EPOCHREALTIME; for i in {1..200}; do "$(type -P true)" >/dev/null; done; echo $(( (t1-t0)/200 ))`, and the engine's
  `date +%s.%N` around 200 forks of `/bin/true` (its cwd on the mount costs slightly more than `/tmp`). §1's older figures
  and every number in this brief's history are pre-fix scale — multiply by five to compare them with a loop measurement.
* **The wall has a floor, and it is a leg rather than the pool.** List-scheduling one run's `--time` durations predicts
  the observed wall within ~10 % at every width, and it says the run stops getting faster once the pool is wider than the
  legs that can run at once: from there `wall ≈ the heaviest leg`, not `Σ/pool`. Launching the heavy legs *first* reaches
  that floor at a much narrower pool than registration order does — registration order starts the expensive block first
  but scatters the heaviest legs through the middle of it. So a `GATE_WIN_PAR` sweep is a small knob (read: it buys
  nothing past that width, and excludes nothing worth excluding), and the two knobs that move the wall are **order** and
  **making the heavy legs cheaper** — which is A2. Re-derive on any run: `bash scripts/validate-all.sh --time`, then read
  `--time slowest`'s top entry against the printed `wall`, and `--list | wc -l` for the leg count.
* **Two legs are native on purpose.** `pi-seat-sync.sh --self-test` reads THIS checkout through `git` (`self_head()`)
  and classifies the seat, so a crossed verdict there is an agreement between two runs that read no HEAD; and
  `scripts/secrets/check-token-holders.sh --self-test` refuses natively by design and belongs wrapped. Both reasons are
  in their registration lines, which is where a reader meets them.
* **A leg declares the engine tools it shells out to, and an absent one answers `CANNOT RUN` (rc 2) rather than rc 0.**
  `hl_wsl_needs <tool>…` in [`scripts/lib/wsl-route.sh`](scripts/lib/wsl-route.sh) is the leg's own claim, answered from the
  probe's inventory so a declaring leg pays no spawn and the route keeps its three exits; the `unknown` answer (the probe got
  nothing) is a boundary, not an absence. [`scripts/gate/check-leg-contract.sh`](scripts/gate/check-leg-contract.sh) holds the
  conjunction — a wrapped leg that classifies the seat or opens a vault/ssh/network trip **reddens naming file:line** — with
  accepted wrong-seat boundaries in
  [`scripts/gate/leg_contract_boundaries.txt`](scripts/gate/leg_contract_boundaries.txt), where a **stale entry reddens** so a
  ledger cannot decay into a mute button, and `NOT JUDGED` for what a scan cannot reach. Re-derive:
  `bash scripts/gate/check-leg-contract.sh --self-test`, then the same command without the flag (it names the declarations,
  the wrapped legs and the tools the probe asks); [`scripts/testdata/leg-contract/run.sh`](scripts/testdata/leg-contract/run.sh)
  is the declaring subject that keeps the real-tree read from grading an empty corpus.
* **The wall is the launcher running tree legs, and a commit-stamped snapshot grades them in about a minute.** The same
  commit grades in the engine's own ext4 in ~1 min and in ten-to-twenty minutes through the win11 launcher — the launcher
  pays a fork plus an AV scan per process and the engine does not. Path mapping across `/mnt/<drive>` is the middle option
  and the worst of both: 9p metadata per file, and a Linux git that cannot open a Windows checkout at all (the route prints
  `git=unavailable` in a linked worktree). So the gate has **two faces**: a **tree face** in the engine's ext4 and a **seat
  face** native on win11, proven over the same commit; legs whose subject spans both (`sync-skills`, `sync-extensions`,
  `check_secret_leak.py`, `check_placeholders.py`, `install-tmux-conf --check`, the vault/ssh legs) are **joined** and run
  native, because in a snapshot they prove neither side. **Copy with git, never with a file copier**: history is a
  dependency (`check_string_twins.py`'s baseline rev, `check_hd_mint_space.py`, `check_todo_done.py --refs`), so a working-tree
  copy turns those legs green across nothing. The recipe is in §0; `rsync` does not do this job — it is absent from the engine
  and Cygwin's `rsync` cannot address the engine at all (`//host/` reads as a remote, a UNC path reads as relative).

---

## 0. Pre-flight - all of it, in this order, before touching a file

```bash
echo "seat=$(uname -n) provider=$PI_PROVIDER model=$PI_MODEL"
git status --short && git worktree list && git log --oneline -1 origin/main
bash scripts/validate-all.sh --list | wc -l        # the leg count, re-derived, never remembered
bash scripts/lib/wsl-route.sh --self-test          # its last arm is the LIVE probe: it must name the engine
bash scripts/harness/seat-bash-build.sh --check    # a bare `bash` here must be Git-Bash, not the WSL launcher
bash scripts/harness/seat-python.sh                # the launcher a leg is launched with, on this seat
wsl.exe -d Debian -- /usr/bin/uname -r             # the engine, on this box, answers a Microsoft kernel
```

**Grade the tree face in the engine, not through the launcher — and never run the launcher's full set to debug one line.**
The snapshot is a **snapshot**, not a seat, so it must say which commit it graded:

```bash
# once: a git copy on the engine's ext4 (a git delta, not a file copy — history is a dependency)
wsl.exe -d Debian -u domen -- bash -c 'git clone -q --no-hardlinks /mnt/d/source/domenkogler/homelab ~/gate-snap/homelab'
# every run: move it to the commit being graded, then grade it
wsl.exe -d Debian -u domen -- bash -c 'cd ~/gate-snap/homelab && git fetch -q /mnt/d/source/domenkogler/homelab HEAD \
  && git checkout -q --detach FETCH_HEAD && git log --oneline -1 && bash scripts/validate-all.sh'
# uncommitted tracked edits ride as a patch; untracked files come as ONE tar stream, never per-file:
git diff HEAD | wsl.exe -d Debian -u domen -- bash -c 'cd ~/gate-snap/homelab && git apply --index -'
git ls-files --others --exclude-standard | tar -cf - -T - | wsl.exe -d Debian -u domen -- tar -xf - -C gate-snap/homelab
```

⛔ never `git clone` with the Windows tree as cwd and a relative destination: a lost destination argument put a **178 MB clone
inside the merge station** on 2026-11-01 and `guard-session.sh` hard-failed the station's own gate. ⛔ never run the full set
from a `wsl.exe --cd` whose cwd is the mount. The seat face (the legs above that read `~/.pi`, the vault, or another host)
still runs native, where it can see this box.

Then the [README.md](README.md) §0 ritual (the outline grep, `git status`, **your own worktree** - the guard refuses edits while the
primary sits on `main`) and the prior-art sweep: this file's own subject has decided predecessors in
[scripts/lib/wsl-route.sh](scripts/lib/wsl-route.sh) (the header states the eligibility conjunction), its registry row in
[`scripts/README.md`](scripts/README.md), and the seat's own bullets in
[docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1. Read them before proposing anything; ⛔ no re-decision in this lane.

**The rule that governs every number in this brief:** a timing is taken **A/B alternating**, never one run against another,
and never while a second lane is running a gate - the same item set has taken 204 s and 1518 s on this box with nothing
different but what else was forking. Attach the `ms/exec` figure from the gate's own `gate: ... ms/exec on this host` line to
every number you record; a number without it is not evidence ([`scripts/README.md`](scripts/README.md) Notes & conventions).

## 1. The two kinds of leg - the whole decision in one line each

* A leg whose cost is **process creation inside a sandbox it builds** crosses the door and gets roughly an order of magnitude
  cheaper: the engine forks at a fraction of a millisecond, this seat pays tens of milliseconds per spawn plus an AV scan.
  Re-derive on both sides: `time ( for i in $(seq 100); do /bin/true; done )`, and the interpreter with `python3 -c pass` /
  `py -3 -c pass`.
* A leg whose cost is **reading this checkout** never crosses: across `/mnt/<drive>` the same walk costs several times more
  (per-file 9p metadata, and a Linux git that cannot open a Windows checkout at all). Re-derive: run one tree-walking checker
  both ways and read the seconds, not the theory.

So the eligibility test is not "is it slow", it is **what it waits on**. `hl_wsl_route` at the registration line is the only
place the decision is expressed; the conjunction a leg must satisfy (tree-or-sandbox only, no net/ssh/vault, no seat `$HOME`
or PATH tool the engine lacks, no seat self-classification, nothing read out of this checkout through git) is stated once in
the lib's header and enforced by the probe, not by a list.

## 2. The legs

| # | leg | where | done when |
|---|---|---|---|
| A1 | **the parity harness** - a leg's native and crossed runs must agree on more than their exit code. A reusable runner lands under `scripts/bench/`: run the argv here, run the same argv through `hl_wsl_route`, compare the **arm counts and verdict words** after stripping CR, `/mnt/...`, drive-letter and temp-path noise; rc 2 when either side could not run. Registry row + registration + `--self-test` in the same commit (one row per tracked file is `check_script_layout.py`'s rule) | win11 | the runner reddens on a planted leg that loses an arm across the door, and greens on one that only differs by path spelling |
| A2 | **wrap what A1 proves.** Take the candidates from the top of `bash scripts/validate-all.sh --time`'s slowest list, then keep only what the conjunction permits: `check_string_twins.py --self-test` and `check_net_manager.py --self-test` (fixture trees, no seat state, no door-facing dep), `install-tmux-conf.sh --self-test` (the engine has `tmux`, this seat prints SKIPs, so the wrap buys verdicts as well as time), `check_hd_mint_space.py --self-test` (arm-identical; its checkout-reading tree-scan forms stay native), `pi-settings-config.sh --self-test` / `pi-tui-config.sh --self-test` (wrap inside the registration function — `hl_wsl_route` routes only a `python`/`python3`/`py`/`bash`/`sh` head), and `install-hooks.sh --self-test` ONLY once its vault leg has a seam, since as written it opens a vault trip and is ineligible. The rest of the heavy list is ineligible by design: seat-classifying (`pi-seat-sync`, `lib/pi-seat`, `lib/wsl-route`, `seat-*-build`) or vault/ssh (`lib/vault-env`, `git-bootstrap-win11`) | win11 | each wrap cites its parity output in the commit message; a crossed leg that judges **fewer** arms than the native one is a finding regardless of how fast it is |
| A3 | **declared runtime deps.** A wrapped leg that needs a tool the engine lacks must answer `CANNOT RUN` (rc 2), never rc 0. The shape to copy already exists: `scripts/testdata/rsync-max-delete/run.sh` tests the binary and exits 2, and the gate prints the NOTE. Make the engine's tool inventory visible once per run from `hl_wsl_probe` rather than discovered per leg, and give the leg-contract checker a home in `scripts/gate/` with its registry row and registration | win11 + `[engine]` | an arm proves rc 2 for a named missing tool on a seat that lacks it, and the same arm proves the tool's presence is not assumed anywhere else |
| A4 | **`[engine]` the engine's own tool set.** Two facts to re-check before deciding anything: the engine's `rsync` (absent, and absent in Git-Bash too, so the two real `--max-delete` fires run on neither seat of this laptop) and its **node**, which IS installed but under `$HOME`, behind the route's deliberately pinned PATH - which is why `pi-tui-config --self-test`'s `pinned-node` arm SKIPs when crossed. ⛔ do not "fix" node by installing into `/usr/local/bin`: the pin exists so a leg cannot run a runtime that is not the seat's. If engine-side node is wanted, it is a declared extra PATH in the route and a line in [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1 - and if it is refused, it goes to [docs/harness-rejected.md](docs/harness-rejected.md) | `[engine]` (the `apt` act is [prompt-laptop-wsl.md](prompt-laptop-wsl.md) §0's seat leg - ride it, do not re-mint it) | the gate says, per leg and in words, which tools the engine had; the rsync arms run somewhere on this laptop or are named as not running |
| A5 | **answer HD-1202's `GATE_WIN_PAR` tail — against the floor, not against the headline seconds.** Alternate 4 / 8 / 16-wide runs of the full set, at least three alternations, quiet box, `ms/exec` per run (real scale since 2026-10-31; see the status bullet). Read each run's `--time slowest` top entry against its `wall`: past the width where the heaviest leg sets the wall, the pool buys nothing, and no leg is excluded from the pool to make the number look better (a leg outside the pool runs serially and lands whole on the critical path, and a per-leg pool exception would need the second queue this repo declined). If the sweep comes back flat, the finding is **launch order**, not width: the heavy legs are launched first as a block but the heaviest of them mid-block, and starting them first reaches the floor at a narrower pool — that question goes to the runner/registration design and needs its own measurement, not a ruling here | win11 | a default that is no longer marked untested, or an explicit decision to keep the current value with the measurement that justifies it, and the floor named as the reason a wider pool was not taken |
| A6 | ⏳ **the residue the parity harness may find.** If any already-wrapped leg loses arms across the door, it is unwrapped (or its arms are made engine-independent) in the same commit | win11 | every wrapped leg's parity diff is empty, or the leg is native and says why in its registration reason |
| A7 | **two-face grading: a tree face in a commit-stamped ext4 snapshot, a seat face native, and `joined` legs native by default.** The face is a **decision at the registration line** (`face=tree\|seat\|joined`, the sibling of the `item_q`/`item_x` profile decision) so there is still ONE item list — ⛔ no second list, no second registry, no `validate-all-win11.sh`. `--profile quick` and [`scripts/gate/check-leg-contract.sh`](scripts/gate/check-leg-contract.sh) fail closed on a leg whose face is undecided, and the checker's own arms prove the bucketing: a leg marked `tree` that reads `~/.pi` or opens a socket reddens, and a leg marked `seat` that could have crossed only costs a note. The snapshot act wants a self-testing driver (`scripts/harness/`-shaped: assert `snapshot.commit == HEAD`, carry or **refuse** uncommitted edits, prove a planted stale file does not survive a sync, `--check` that grades without running the gate). ⛔ the snapshot is never a seat: a standing clone at a fixed path is what `wsl-route.sh`'s header refuses to call a win11 verdict, and the commit stamp is what keeps that honest | win11 + `[engine]` | a full grading of one commit is the sum of the two faces, both faces print the same commit, an undecided leg reddens the run, and the tree face's wall is re-derived here rather than quoted |

**The legs still open, in the order that costs least.** (A3 is landed; A6 stays a residue leg that reports only what parity finds.)

* **A7 — two-face grading. Run this leg before the others: it is the only one that moves the clock, and every later leg pays
  the wall until it lands.** Read the two status bullets above and §0's recipe first; the eligibility conjunction in
  [`scripts/lib/wsl-route.sh`](scripts/lib/wsl-route.sh) already states the axis, so A7 changes *where the gate runs*, not
  *what may cross*. Land it in this order: (1) the face decision at each registration line (`face=tree|seat|joined`), derived
  — never re-declared — by `check-leg-contract.sh`, which now has the facts to derive them; (2) the snapshot driver with its
  own `--self-test`, including an arm that reddens when the snapshot's commit is not the graded commit and an arm that plants a
  stale file and requires it to be gone; (3) one run of each face on the same commit, with both faces' walls and `ms/exec` in
  the commit message. The seat face must name its legs and stay native — a joined leg graded in the snapshot proves neither
  side — and the report ends with the two walls side by side, which is the sentence `docs/harness-pi-seats.md` §1 wants.
* **A3 — declared runtime deps. ✅ landed:** `hl_wsl_needs`, the conjunction enforcer and the boundary ledger are in
  `scripts/gate/`; the crossed-pair half of the token-holders boundary is parked as **A6/A1** territory (it needs one live
  crossing pair, which is the parity instrument's act, not this checker's).
* **A2 — wrap what A1 proves — and read it as a verdict leg, not a wall-clock leg.** The eligible fork-heavy legs are already
  routed, so A2 buys the answers this seat cannot print (`install-tmux-conf --self-test` where the native run can only SKIP),
  not minutes; A7 is what moves the clock. Each wrap cites its own parity output in the commit message:
  `install-tmux-conf.sh --self-test` gains real verdicts where the native run prints SKIPs, and
  `check_hd_mint_space.py --self-test` is arm-identical across the door (its tree-scan forms read the checkout through
  `git` and stay native). `pi-settings-config.sh --self-test` is registered as a shell function, so its wrap belongs
  inside that function — `hl_wsl_route` routes only a `python|python3|py|bash|sh` head. A wrap that judges fewer arms
  than the native run is a finding, whatever the stopwatch says.
* **A5 — `GATE_WIN_PAR`, priced as one run rather than a sweep.** A full launcher run is 10–20 minutes on this seat, so the
  nine-run sweep this leg once specified is a half-day spent to confirm a flat curve the floor bullet already predicts — that
  trade is refused, and the method is now: take **one** `bash scripts/validate-all.sh --time` run, list-schedule its per-leg
  durations at 4 / 8 / 16 (the model agrees with the observed wall within ~10 % at every width, per the floor bullet), and
  **run live only the widths the model says differ** — usually one confirmation, not nine. Weigh `--time`'s `Σ/wall`
  against wall **and the top entry of `--time slowest` against wall** — the second one is the bound: past the width where
  the heaviest leg sets the wall, a wider pool buys nothing, so a flat answer is a finding about the leg and the launch
  order rather than about the number. If A7 has landed, say so and grade the **seat face** instead: with the tree legs gone the
  pool question answers itself, and the honest verdict is then "the knob moved out from under the row". Attach the
  `gate: N items in flight` line to every figure, because `GATE_NPAR` is
  against wall **and the top entry of `--time slowest` against wall** — the second one is the bound: past the width where
  the heaviest leg sets the wall, a wider pool buys nothing, so a flat sweep is a finding about the leg and the launch
  order rather than about the number. Attach the `gate: N items in flight` line to every figure, because `GATE_NPAR` is
  the ansible legs' fan-out and does not move with the pool width. The verdict becomes one sentence in
  [`docs/harness-pi-seats.md`](docs/harness-pi-seats.md) §1 and the numbers go in the commit message, in the same change
  that shortens [todo.md](todo.md) HD-1202.

## 3. What this brief must not do

* ⛔ no second item list and no `validate-all-win11.sh` - one registry, one routing decision, is the standing ruling recorded
  in [scripts/lib/wsl-route.sh](scripts/lib/wsl-route.sh)'s header.
* ⛔ no `GIT_DIR`/`GIT_WORK_TREE` injection to make git-reading legs cross: it repairs one leg and poisons every leg that
  builds its own fixture repo.
* ⛔ no wrap of a seat-classifying leg (`seat-bash-build.sh`, `seat-ssh-build.sh`, `git-bootstrap-win11.sh`,
  `install-nerd-font.sh`, `lib/pi-seat.sh`, `lib/wsl-route.sh` - its control arm *is* the seat) or of anything that opens a
  vault/ssh/network trip.
* ⛔ no timing while another lane runs a gate, and never a single run against a single run.
* ⛔ no full launcher run to debug one red line — the two checks that print it are seconds apart (`--only <substring>`), and a
  20-minute run spent to read one finding is how a lane loses its deadline to the stopwatch.
* ⛔ no file copier for the tree face (no `shutil.copytree`, no `cp -r`, no rsync of the working tree): history is a
  dependency of four legs, so a working-tree copy turns them green across nothing. Git moves the bytes; a snapshot driver only
  states and verifies the act.
* ⛔ no measuring "the win11 verdict" from inside WSL: there the route is off by design and legs run natively.
* ⛔ no new gate without a profile decision at its registration line - `--profile quick` fails closed on an undecided leg.

## 4. Traps (each one silent, or expensive)

* **The interop PATH.** `wsl.exe -d Debian -- <cmd>` without a PATH pin inherits the Windows PATH, so a leg can silently run
  the Windows `pi`/`node`/`ssh`/`python` and report them as the engine's answer. The route pins PATH as a command *prefix*
  (never exported, or the seat's own legs stop converting their arguments); any new spawn across the door goes through the
  lib's exec helper, nothing else.
* **A linked worktree and the engine's git.** In a Windows worktree the route prints `git=unavailable` (the `.git` file names
  a `D:/...` path a Linux git resolves relatively). Expected, and it changes no verdict - but it makes any crossed arm that
  needs the checkout worthless evidence. Take parity measurements in a worktree and say so, or in the primary when it is
  clean; never by editing the primary.
* **git-bash path rewriting.** POSIX-looking arguments become `C:/Program Files/Git/...`; the converter pin lives on the
  spawn line, and anything with nested quoting goes through a script file rather than a heredoc.
* **A fast crossed leg can be a lie.** The most tempting numbers are the ones that turn arms into `SKIP`s - the parity diff,
  not the stopwatch, is what authorises a wrap.
* **Scratch belongs to your worktree.** An untracked or tracked file left in the **primary** hard-fails the merge station's
  own gate (`guard-session.sh --validate-mode`); `.scratch/` is ignored, but it is not exempt from being somebody else's
  WIP.
* **Lanes share the box.** Other sessions create and prune worktrees while you work: manage yours by name with
  `git worktree add`/`remove`, never `rm`, and expect a foreign lane's gate run to move `ms/exec` under you.

## 5. Acceptance

* `bash scripts/validate-all.sh` green in the worktree, exit code read from `$?` - with the leg count from
  `--list | wc -l` in the commit message, so a dropped registration cannot hide.
* the parity harness runs as a gate item and its `--self-test` catches **both** halves: an arm lost across the door reddens,
  a path-spelling-only difference stays green.
* every wrapped leg's registration line states its engine decision and its declared tools; a missing engine tool answers
  rc 2, proved by an arm rather than by prose.
* both faces of one commit are proven, each printing the commit it graded; a leg whose `face` is undecided reddens the run
  rather than silently running somewhere; and the tree face's wall is re-derived in the commit message beside the seat face's,
  so the claim "the wall was the launcher" is a measurement and not a slogan.
* HD-1202's `GATE_WIN_PAR` tail resolved into a doc sentence (or re-parked with the exact measurement that blocked it) and
  the row's `⏳` shortened in the same commit.
* docs carry facts plus the command that re-derives them, measurements live in the commit message, and this brief is deleted
  in the orchestrator's cleanup commit (O7).
