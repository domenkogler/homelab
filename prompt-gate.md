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

**Status — the seat's cost question is answered, the engine's contract is written down, and the pool question now has a
number to be read against; legs A3, A2 and A5 stay open and are dispatched at the end of §2.** What exists now, and how to
see it:

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
| A2 | **wrap what A1 proves.** Take the candidates from the top of `bash scripts/validate-all.sh --time`'s slowest list, then keep only what the conjunction permits: `check_string_twins.py --self-test` and `check_net_manager.py --self-test` (fixture trees, no seat state, no door-facing dep), `install-tmux-conf.sh --self-test` (the engine has `tmux`, this seat prints SKIPs, so the wrap buys verdicts as well as time), `check_hd_mint_space.py --self-test` (arm-identical; its checkout-reading tree-scan forms stay native), `pi-settings-config.sh --self-test` / `pi-tui-config.sh --self-test` (wrap inside the registration function — `hl_wsl_route` routes only a `python|python3|py|bash|sh` head), and `install-hooks.sh --self-test` ONLY once its vault leg has a seam, since as written it opens a vault trip and is ineligible. The rest of the heavy list is ineligible by design: seat-classifying (`pi-seat-sync`, `lib/pi-seat`, `lib/wsl-route`, `seat-*-build`) or vault/ssh (`lib/vault-env`, `git-bootstrap-win11`) | win11 | each wrap cites its parity output in the commit message; a crossed leg that judges **fewer** arms than the native one is a finding regardless of how fast it is |
| A3 | **declared runtime deps.** A wrapped leg that needs a tool the engine lacks must answer `CANNOT RUN` (rc 2), never rc 0. The shape to copy already exists: `scripts/testdata/rsync-max-delete/run.sh` tests the binary and exits 2, and the gate prints the NOTE. Make the engine's tool inventory visible once per run from `hl_wsl_probe` rather than discovered per leg, and give the leg-contract checker a home in `scripts/gate/` with its registry row and registration | win11 + `[engine]` | an arm proves rc 2 for a named missing tool on a seat that lacks it, and the same arm proves the tool's presence is not assumed anywhere else |
| A4 | **`[engine]` the engine's own tool set.** Two facts to re-check before deciding anything: the engine's `rsync` (absent, and absent in Git-Bash too, so the two real `--max-delete` fires run on neither seat of this laptop) and its **node**, which IS installed but under `$HOME`, behind the route's deliberately pinned PATH - which is why `pi-tui-config --self-test`'s `pinned-node` arm SKIPs when crossed. ⛔ do not "fix" node by installing into `/usr/local/bin`: the pin exists so a leg cannot run a runtime that is not the seat's. If engine-side node is wanted, it is a declared extra PATH in the route and a line in [docs/harness-pi-seats.md](docs/harness-pi-seats.md) §1 - and if it is refused, it goes to [docs/harness-rejected.md](docs/harness-rejected.md) | `[engine]` (the `apt` act is [prompt-laptop-wsl.md](prompt-laptop-wsl.md) §0's seat leg - ride it, do not re-mint it) | the gate says, per leg and in words, which tools the engine had; the rsync arms run somewhere on this laptop or are named as not running |
| A5 | **answer HD-1202's `GATE_WIN_PAR` tail — against the floor, not against the headline seconds.** Alternate 4 / 8 / 16-wide runs of the full set, at least three alternations, quiet box, `ms/exec` per run (real scale since 2026-10-31; see the status bullet). Read each run's `--time slowest` top entry against its `wall`: past the width where the heaviest leg sets the wall, the pool buys nothing, and no leg is excluded from the pool to make the number look better (a leg outside the pool runs serially and lands whole on the critical path, and a per-leg pool exception would need the second queue this repo declined). If the sweep comes back flat, the finding is **launch order**, not width: the heavy legs are launched first as a block but the heaviest of them mid-block, and starting them first reaches the floor at a narrower pool — that question goes to the runner/registration design and needs its own measurement, not a ruling here | win11 | a default that is no longer marked untested, or an explicit decision to keep the current value with the measurement that justifies it, and the floor named as the reason a wider pool was not taken |
| A6 | ⏳ **the residue the parity harness may find.** If any already-wrapped leg loses arms across the door, it is unwrapped (or its arms are made engine-independent) in the same commit | win11 | every wrapped leg's parity diff is empty, or the leg is native and says why in its registration reason |

**The three legs still open, in the order that costs least.**

* **A3 — declared runtime deps.** A wrapped leg that needs a tool the engine lacks answers `CANNOT RUN` (rc 2), never
  rc 0; the inventory the probe printed is what its `CANNOT RUN` is read against. The shape to copy is
  [`scripts/testdata/rsync-max-delete/run.sh`](scripts/testdata/rsync-max-delete/run.sh) — it tests the binary and exits
  2, and the gate prints the NOTE. The checker still needs a home in `scripts/gate/` with its registry row and its
  registration, and `check-token-holders --self-test` (native rc 1 by design, crossed rc 0) is the leg this rule and the
  parity classifier must both classify as a wrong-seat boundary rather than a lost arm.
* **A2 — wrap what A1 proves**, each wrap citing its own parity output in the commit message:
  `install-tmux-conf.sh --self-test` gains real verdicts where the native run prints SKIPs, and
  `check_hd_mint_space.py --self-test` is arm-identical across the door (its tree-scan forms read the checkout through
  `git` and stay native). `pi-settings-config.sh --self-test` is registered as a shell function, so its wrap belongs
  inside that function — `hl_wsl_route` routes only a `python|python3|py|bash|sh` head. A wrap that judges fewer arms
  than the native run is a finding, whatever the stopwatch says.
* **A5 — `GATE_WIN_PAR`.** The sweep is `for p in 4 8 16; do GATE_WIN_PAR=$p bash scripts/validate-all.sh --time; done`,
  at least three A/B alternations, on a box with no other lane forking, and the numbers to weigh are `--time`'s `Σ/wall`
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
* HD-1202's `GATE_WIN_PAR` tail resolved into a doc sentence (or re-parked with the exact measurement that blocked it) and
  the row's `⏳` shortened in the same commit.
* docs carry facts plus the command that re-derives them, measurements live in the commit message, and this brief is deleted
  in the orchestrator's cleanup commit (O7).
