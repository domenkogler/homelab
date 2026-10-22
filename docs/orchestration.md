---
title: Repo Session Contract and Orchestrator Mode
role: reference
domain: meta
cross_cutting: true
status: active
tags: [meta, process, orchestration, sessions]
---
> **Role:** the PERMANENT process contract for repo sessions (cross-cutting) — the working contract (§3) and the
> lane-session orchestrator mode (§4, overrides O1–O11, launch, merge/cleanup) + the child-lane contract
inside one session. The LIVE wave table is
> NOT here — it lives in [todo-table.md](../todo-table.md) §B0. Where the contract below is silent,
> [README.md](../README.md) §4 and [CONVENTIONS.md](../CONVENTIONS.md) §6 stand and outrank everything.
> **Linked from:** [prompt.md](../prompt.md) · [README.md](../README.md) §4 · [todo-table.md](../todo-table.md) §B0 · [CONVENTIONS.md](../CONVENTIONS.md) §4/§6

---
## 3. Working contract (non-negotiable)

1. **Step-0 ritual, in order:** first the conventions map — `grep -n "^#\|^## \|^### " CONVENTIONS.md | head -40` (README §0 step 1; every rule here is cited by §, so the outline comes before the file) — then `git status` sanity + fresh session worktree (`git worktree add ../homelab-wt-<date>-<HHMM>`, CONVENTIONS §6) — enforced by `scripts/gate/guard-session.sh`.
2. **Prior-art sweep** before new HD rows: todo.md + owning docs + `<domain>-rejected.md` + `git log -S 'HD-…'` (re-decide ban). The sweep applies to **your own open questions and claims** too, and a claim needs the *implementation* read, not a matched line — a matched line in a doc is not evidence about the compose, an owner decision already written down is not an open owner call, and a host name must exist somewhere before it is named.
3. **Validate before finishing:** `bash scripts/validate-all.sh` must end green (checks prompt↔todo consistency, SSOT doc map, IP literals, placeholders, done-row deletion, **and the two doc-role contracts** below). It activates `~/ansible-venv` itself and preflights `import jinja2, yaml`, so **a non-interactive green counts** (cron, pi, a converge): the venv reaches PATH only through `~/.bashrc`, which non-interactive shells skip, and a verdict that depends on the invoker instead of the tree is not a verdict.
   - **Ledger vs runbook (gated — do not fight the gate):** `deployment-tasks.md` is the **only** place progress is written, as `- [ ] **HD-nnn** — <pending action> · [doc]` lines; every open one must have a live `todo.md` row (closed row → delete the line, the record is the owning doc + the commit), every `- [x]` carries its date. `deployment-manual.md` is **imperative procedure only** — no ✅/⏳ markers, no dated or "live lesson / as executed / close-out" narrative, no inlined knowledge (link the owning doc), and its `## Phase N` numbers must match the ledger's (spark = **Phase 4b** in both). Anything automated stays in IaC, not in prose.
4. **SSOT direction:** values in IaC (`group_vars/*.yml`, `host_vars/*.yml`) · generated `*-generated.md` never hand-edited · secrets 1Password `Homelab-ansible` only, fail-loud (no `default('')`).
5. **Lifecycle:** fully-done HD row → **deleted** from todo.md (record in owning doc + git). IaC-done-but-deploy-gated row stays with a ⏳ tail. Decisions written once to the owning doc + `<domain>-rejected.md`.
6. **Close-out:** record the outcome + runbook in the owning doc; commit (plain `git commit` — commit signing is retired); merge/push per the session branch policy (unmerged `session/*` branches are the norm until the deploy-gate flips).
7. **Orchestrator discipline:** for multi-step/multi-host/live-deploy changes, one parent co-ordinates bounded single-deliverable subagent lanes (pi-subagents); the parent holds final acceptance + runs validate-all. **Delegation is the default, not an escalation** (O10), and a child's silence is a compaction pause, not a hang — the run budget is 2 h per child, so steer on a *needs-attention* notice or the deadline, never on quiet (O11).

**Ask-if-unsure:** planned/multi-host/deploy-gated/irreversible → orchestrator pattern; re-deciding → check owning doc + rejected log first; unsure of the owning doc → `docs/index.md` map.


---

## 4. Orchestrator mode — independent lane sessions, one merge station

> **Read this first if you were launched from a `prompt-<domain>.md` brief.** This section is the **parent**
> contract for running two (or more) independent lane sessions in parallel, and it is an **OVERRIDE, not a
> restatement**: the eleven items **O1–O11** below deliberately behave differently from [README.md](../README.md)
> §4 and [CONVENTIONS.md](../CONVENTIONS.md) §6 + its Session close-out row. **Where this section is silent,
> README and CONVENTIONS stand and outrank everything.** A brief is a dispatch note: it can narrow §4, never
> widen it, and if a brief contradicts §4 then **§4 wins and the brief is wrong** — fix the brief, do not
> improvise a third set of rules in the middle of a lane.

**Two different things in this repo are both called "orchestrator" — do not conflate them:**

| Mode | What actually runs | Governed by |
|---|---|---|
| Subagent lanes | bounded, single-deliverable **children inside one session** (pi-subagents); the parent holds acceptance | README §4 item 7 + README §"Orchestrator + reviewer discipline". **Unchanged by this section.** |
| **Lane sessions (this section)** | **two independent full sessions**, each with **its own brief, its own worktree and its own branch**, each closing several HD rows; the parent launches both, merges both, and owns the cleanup | **§4.** A lane session is a normal repo session *plus* these overrides — it is not a subagent, it has no parent in its own process, and §4 is its only extra rule. |

### The overrides — why a lane session must not behave exactly like a README §4 session

| # | The normal rule | Orchestrator mode | Why it differs |
|---|---|---|---|
| **O1** | CONVENTIONS §worktree: "main receives only **fast-forward** merges" | The **first** lane to finish is FF-merged. The **second** runs `git rebase main` inside its own worktree, re-runs `validate-all.sh` there, and is then FF-merged. **A merge commit is never created on `main`.** | Two parallel branches cannot both be ancestors of one `main`; rebase keeps the FF invariant honest instead of abandoning it |
| **O2** | CONVENTIONS close-out (3) + (5): **the session** updates `prompt.md`, by editing the previous handoff | **`prompt.md` and `todo-table.md` are orchestrator-only.** A lane session does not touch either. It edits **only its own `todo.md` rows** (row-local hunks — never re-sort, re-flow or renumber the tables) and may tick **only its own** `deployment-tasks.md` lines | `scripts/gate/check_todo_done.py` fails on any disagreement between `prompt.md`'s open/done claims and `todo.md`. With two writers on the views, a red gate is the *expected* outcome, not an accident |
| **O3** | [todo-table.md](../todo-table.md) §C4: `docs/services-ai*.md` + `IaC/ansible/templates/docker_services/**` are one-writer-at-a-time (read tree-wide) | Narrowed to **one writer per service directory** + **one converge in flight per host**. oldsrv / VPS / spark / router are separate slots; **the router slot is global** (its converge is the device-wide `/import`). `docs/services-ai*.md` stays single-writer | Read tree-wide, that rule forbids any two lanes existing; the real hazard it guards is two converges restarting containers on one host and the `--diff` secret-dump class, both of which are per-directory + per-host |
| **O4** | README §4.7 + CONVENTIONS: planned / multi-host / deploy-gated → **stop and ask** | **Park and continue.** An owner gate reached inside a lane is written into that row's ⏳ tail as the *exact* blocked action; the lane finishes everything unblocked and names the park in its final report. It does not stall the sibling lane and does not end its session early | A lane that waits unattended burns the whole parallel slot — and every brief contains at least one owner-gated row |
| **O5** | CONVENTIONS §worktree: the primary checkout is a merge station | Kept **strictly**, and it also binds the **orchestrator**: the cleanup commit (view re-sync, brief deletion, link fixes) is made in **its own worktree/branch**. `scripts/gate/guard-session.sh` refuses edits while primary sits on `main`, and `validate-all.sh` **hard-fails on primary + main + dirty** — only a *clean* main validation is the exempt form | The merge station is not an edit site, not even for tidying up after a merge |
| **O6** | README §4.8: ownership follows the action; the session that did the work writes the runbook line | **Unchanged, and it is on the lane.** `deployment-manual.md` is deliberately claimed by no brief, so a lane that performed any hand-repeatable step writes the imperative line **in its own commit** | The exact hole README §4.8 was written for; the orchestrator must not be expected to notice it after the fact |
| **O7** | CONVENTIONS §lifecycle: a closed row is deleted from `todo.md` | Kept for the lane. The **domain brief file itself** is deleted by the **orchestrator**, in the cleanup commit, **in the same commit as the link fixes** in `prompt.md`, `todo.md` and `todo-table.md` | `scripts/gate/check_doc_map.py` scans every root `*.md` **except `prompt-*`**: a dangling link from `todo.md`/`todo-table.md`/`prompt.md` fails the gate, while a link from one brief to another is not checked at all |
| **O8** | CONVENTIONS §worktree: on a path collision, abort and pick a new name | Hard rule for the parent too: it **never** `rm`s / moves / renames a worktree it did not create; lane worktrees are removed **after** the merge, **by name**, with `git worktree remove`; branches die by `git branch -d` (**never `-D`**) | A worktree removed by a session that did not create it is gone; and `-d`'s refusal is the cheap proof that nothing was stranded |
| **O9** | README §4.7 + CONVENTIONS §6: nothing bounds how many **sessions** a run may have — O3 caps *converge slots*, not contexts, so launching a lane per brief is legal on its face | Sessions are cheap, **contexts are not**. At most **8 concurrent agent sessions** and at most **2 full-context sessions — the orchestrator counts as one**. The default shape is *orchestrator + one lane*; a **third** is allowed only when the other two are near done, and **4 is the ceiling, never exceeded**. Anything beyond must be a **narrow-context child** (a bounded single-deliverable subagent with its own fresh, small context — README §4 "Orchestrator + reviewer discipline") and never a second full lane wearing a brief. The brief pool is a **dispatch queue, not a parallelism licence** | A full lane session pays the README §0/§1 boot ritual (~60 k tokens of `todo.md` alone), so parallel lanes are paid for out of the context budget, not the session budget; rows queued behind an occupied host slot (O3) are **waiting, not missing** |
| **O10** | README §4 item 7 + the pi-subagents contract: the parent works directly by default, and delegation must be earned per task | **Delegation is the default.** Every analysis, read-down, authorship and verification task runs as a child. The parent spends its own context on four things only: composing launches, reading **evidence** (`git log`, `git status --porcelain`, `git show --stat`, gate output), merging, and `validate-all.sh` | O9's reasoning applied one level down: a boot ritual costs tens of thousands of tokens, so a parent that re-reads the tree in order to brief a child pays that bill twice. ⚠ This does **not** soften Merge + cleanup step 1: reading evidence *is* the parent's job, and a lane's report is still not proof |
| **O11** | Harness defaults: up to 20 concurrent children, a 30-minute run backstop, and whatever model a call names | **≤2 children live at a time** (one writer per cwd), **`async: true` on every launch**, a **2 h deadline per child**, and **the parent's model only** — enforced mechanically by `subagents.modelScope` with `allow: ["inherit"]` in [`../pi-agent/settings-ssot.json`](../pi-agent/settings-ssot.json), which the settings plane merges into every seat | The engine sets the number, not taste: `spark_vllm_max_num_seqs: 4`, minus the parent, minus one sequence reserved for the always-on consumers (voice, LiteLLM, RAG) = **2** ([harness-pi-engines.md](harness-pi-engines.md) §6). A third child does not queue politely — it preempts a live prefix and recomputes it |



> **The live lane map (waves) is state, not contract — it lives in [todo-table.md](../todo-table.md) §B0.**
> Pairing constraints (never two lanes on one converge host, O3) are contract; which brief is
> live this week is not.



> **Probe lanes are outside the wave system, deliberately** (contract for **O3**). A probe stands things up
> **on oldsrv** under the `domen` seat (a venv / npm prefix, never a container) and drives the local AI legs, so
> it contends for that box and its dGPU even while converging nothing — check whether one is in flight before
> launching an oldsrv lane, and never run one beside a lane holding the **spark** converge slot. A new probe
> brief is written only on the owner's request.


### Child lanes inside one session (O10–O11)

> O9 bounds **sessions**; this bounds the **children**. Both are about the same scarce thing, and neither
> is a licence to fan out — the queue of rows is not the queue of children.

- **The parent does not do the work.** It composes launches, reads evidence, merges, runs the gate. Need to
  know something about the tree? That is a `scout`. Need two independent readings of one change? Two children,
  not two passes of the parent's own context. Bounded, single-deliverable, one acceptance micro-format each —
  an over-scoped child is worse than none (README §"Orchestrator + reviewer discipline").
- **Two live children, and only one writer per cwd.** A third does not wait its turn quietly: on the shared
  engine it preempts somebody's prefix ([harness-pi-engines.md](harness-pi-engines.md) §6). Concurrency is a KV-pool decision
  wearing a process-table costume, so the ceiling is the engine's arithmetic, not a preference.
- **The model is inherited, never overridden.** Every builtin child takes the session model, and a seat's
  rendered model set carries one serving provider, so a `model:` override names something this harness does
  not have. The restriction is a setting, not a habit — `subagents.modelScope` (`enforce` + `strict`,
  `allow: ["inherit"]`) in [`../pi-agent/settings-ssot.json`](../pi-agent/settings-ssot.json) — so an override
  fails at launch instead of buying an unavailable model at run time. A child therefore pays the **parent's
  full context window**: keep child prompts bounded and the context `fresh`; forking a 262k parent context
  into a child is precisely the KV act [harness-pi-engines.md](harness-pi-engines.md) §6 exists to warn about. (The
  lane-profile alias in that section is a paper artifact and is NOT in the model spec; if it is ever landed,
  widening the scope is a deliberate change, not a side effect.)
- **Async always, and silence is not a hang.** Launch with `async: true`, then yield and let the wake bring
  the parent back — `bg_wait` is for work with no native completion notice, not for every child. A child served
  by a local engine goes quiet for **minutes** while it compacts (pi compacts at `contextWindow −
  compaction.reserveTokens`, and thinking-on decode runs ~11 tok/s per [harness-pi-seats.md](harness-pi-seats.md) §5), so
  **do not steer, stop, or re-launch on silence**. Act on a needs-attention notice, a repeated tool-attempt
  failure, or the deadline. The deadline is **2 h per child**, because the harness's own 30-minute backstop
  is shorter than a real bounded task at that decode rate; the value lives with the rest of the child-runtime
  knobs in [`../pi-agent/settings-ssot.json`](../pi-agent/settings-ssot.json) as `_subagentConfig`, the payload
  for the extension's own config file, installed by the `subagent` seat plane
  ([`../scripts/harness/pi-subagent-config.sh`](../scripts/harness/pi-subagent-config.sh)); a seat whose own
  `--check` does not print `OK` for that file still runs the harness defaults and the numbers must be passed on
  the launch and read as authored, not as effective.
- **A missing verdict is a blocker, never a green.** A reviewer launch whose structured output comes back empty passes a
  `if (!verdict.blockers)` test exactly as a clean review does, so a verdict-gated fix stage silently no-ops and the run ships
  a review it never received. A script must treat a MISSING verdict as a blocker and dispatch the fix from the reviewer's
  **prose**, which is the half that always comes back.
- **Dispatch filter on a spark-served seat.** If the session's own model is spark, the spark engine brief is
  out of scope for the **whole run** — no child may be launched against it, timed or not (standing rule 2 in
  [todo-table.md](../todo-table.md) §C). A provably engine-safe spark converge stays allowed, with the engine
  id / `StartedAt` / `RestartCount` read before and after.
- **The seat axis is separate from the model axis, and a launch must state both.** Two different things gate a run: *which
  model serves the session* decides whether timed and engine legs are allowed at all, and *which box the session stands on*
  decides whether a converge is refused by the self-converge guard — that guard fires when the target **is** the controller,
  and it asks nothing about the model. So a session may be barred from a timed leg while standing on the one box that may
  drive a lockout-class converge, and the reverse is equally possible. Externally-served runs take the designated runner
  station (the WSL Debian laptop seat: off-box for every target, not the engine host, owner of no converge slot) — see
  standing rule 9 in [todo-table.md](../todo-table.md) §C and [../prompt-laptop-wsl.md](../prompt-laptop-wsl.md), which is a
  **seat** brief: it claims **legs, not rows**, so the row→brief index in [todo-table.md](../todo-table.md) §B0 stays the single owner of every row and the
  station never becomes a second claimant on a domain lane's work.


### Launch procedure (the parent)

1. Primary = merge station: `git fetch`, `git status` clean, `git checkout main`, `bash scripts/validate-all.sh` green (clean-main is the exempt form under O5).
2. One worktree + branch per lane, created **by the parent** so the naming is never improvised:
   `git worktree add -b session/<lane>-$(date +%Y%m%d-%H%M) ../homelab-wt-$(date +%Y%m%d-%H%M) main`
3. Hand each lane exactly four things: its brief path, the sibling brief path, this §4, and the standing
   instruction **"do not edit `prompt.md` or `todo-table.md`"** (O2). The brief carries the rest. **O10–O11 apply
   inside a lane exactly as they apply to the parent** — a lane that performs its own analysis rather than
   delegating it spends the run's context budget twice.
   ⚠ **And say the sitting's constraints IN the launch, because a lane's ROW is a plan and only the dispatch is a
   constraint.** A row that names a converge gets converged. A rule that lives in the parent's head — read-only plus
   `--check` while the owner sleeps, a host excluded tonight, an engine-leg ban — reaches a lane ONLY if the launch
   text carries it. Measured 2026-10-21: a lane whose dispatch omitted the night rule read its row, took its
   read-only first act correctly, and then ran a live `--tags monitoring` converge on the VPS, because the row named
   that converge and nothing said *not tonight*. One line in the launch is the whole fix; the fix is not a lane that
   has to guess.
4. Check the converge slots before launching: two lanes must not share a host (O3). If the only work left in
   two lanes is on one host, they are sequential, not parallel.
5. Read the seat's own model (`echo $PI_PROVIDER`): on a spark-served seat the spark engine brief is excluded
   from the whole run, for the parent and for every child alike (O11's dispatch filter). Say which briefs are
   excluded and why, in the same breath as the lane map — a lane that discovers the exclusion mid-flight has
   spent a slot learning it.
6. Read the seat's **placement** the same way: whether this box is the target of any leg it is about to drive. A
   lockout-class role on the controller's own host is refused by the guard and must be re-driven from another control node
   (the seat brief names the legs), and an externally-served run belongs on the designated runner station — naming the seat
   in the launch is what makes a timed leg's provenance checkable afterwards.
7. **Launch every lane with `checkpointBeforeDeadlineMs`, and say the deadline in the prompt.** A lane's wall timeout
   (two hours by default) KILLS it where it stands, and a kill does not commit: the measured failure mode on this fleet
   is a lane that ran two hours, reported a green tree and deliverables by name, and left **no commit at all** — the work
   existed only in its context. The checkpoint parameter asks the runner to tell the child to checkpoint a fixed interval
   before that deadline (this repo uses 20 minutes), so it commits and reports instead of being cut off mid-sentence.
   It is best-effort — the deadline kill still applies — so the prompt must also carry the standing instruction
   **"commit after each deliverable, before starting the next"**: committing per deliverable is what makes a lost lane
   partially recoverable, and it costs nothing.
8. **A timed-out lane is rescued, not re-run from scratch.** The parent inspects the tree first (`git log main..HEAD`,
   `git show --stat`, `git status --short`), rebases and merges whatever is committed and green, then launches a
   **finisher** child in the *same* worktree carrying only the unfinished scope and the parent's own measurements of the
   live state — the finisher starts from landed commits, and must not be told to re-derive what the parent has already
   measured on the host.
9. **The merge station is not exempt from the rule it enforces.** A parent's "small doc fix" made directly in the primary
   is the same violation CONVENTIONS §6 forbids a lane, and `guard-session.sh` says so in its own words — *validate-all ran from the
   PRIMARY checkout on 'main' with DIRTY files* — which means the gate cannot be run green until the edit is either
   committed or moved. Committing to get a green run inverts the order and is how the guard's warning becomes a notice
   served after the fact. So: **make the parent's own edit in a worktree, gate it there, FF-merge it** — exactly the
   lane procedure, with the parent as the lane. The one legitimate primary-side act is running the gate at a CLEAN tree
   after a merge (O5's exempt form); "dirty, then commit, then gate" is not that.


### Merge + cleanup (the parent — none of this is ever a lane's job)

1. Touch nothing until both lane branches are **committed and green in their own worktree** — and prove that to yourself: `git -C <lane-worktree> log --oneline -1` + `git show --stat` + `git status --short`. **A lane's own report is not evidence; only `git log` decides.** A finished-sounding report naming files, line numbers, validator output and a commit message can describe a worktree with no commit and no changed byte. (A report that does not match the tree is refused: stop the run, keep the row open, take the work over.)
2. FF-merge lane A into `main` from the primary; `bash scripts/validate-all.sh` there.
3. Rebase lane B onto `main` **inside its worktree** → re-run `validate-all.sh` **there** → FF-merge B (O1).
   ⚠ **`todo.md` merges ROW-WISE, never by choosing a conflict hunk.** A row is the unit of record (CONVENTIONS §4),
   and two lanes editing one row produce a conflict whose two sides are each **half the truth** — picking either side
   silently deletes the other lane's measurement, its parked state, or its falsified premise. So resolve every
   `todo.md` hunk by reading **both** sides against the row and writing the union: one row, both lanes' facts, the
   newer premise winning over the older one it contradicts. ⛔ `git checkout --ours`/`--theirs` on a registry file,
   and `-X theirs` / `-X ours` on a whole merge, are forbidden for `todo.md` by default; if one is ever used, the
   merge is **not finished** until the other side's row content is re-verified claim-by-claim — `git diff main^1 main
   -- todo.md` plus a `grep -F` for a specific sentence taken from each side of every row the two branches both
   touched. A green validator is not that proof: both views can agree with a registry that just lost a row.
   ⚠ **Before any merge into `main`, diff the row-id sets and require the difference to be empty** — both directions,
   `comm -3` over the ids each side carries. An id present on one side and absent in the merged result is a row some
   lane's work died in, and it is the one thing a row-wise merge can still lose while printing no conflict.
   `scripts/gate/check_todo_done.py --refs` then proves the surviving rows still hold every id the root briefs and
   views name, so a row that vanished with its references is caught by the gate rather than by a reader.
   ⚠ **After an interrupted or aborted rebase, prove the branch actually moved:**
   `git merge-base --is-ancestor main <lane-branch>` must exit **0** before the FF-merge. A rebase that stopped on a
   conflict and was quit leaves the branch where it started, `merge` then opens a real merge commit instead of a
   fast-forward, and the lane's rows land with `main`'s newer rows on the losing side of it (O1).
4. Open **the parent's own worktree/branch** (O5) and make cleanup **one commit**:
   re-sync `todo-table.md` from the merged `todo.md` + `prompt.md` (it is a view, not a second record);
   update `prompt.md` §2 to the post-merge state and remove the closed brief from the wave table;
   `git rm` each finished brief **together with** its link fixes in `prompt.md` / `todo.md` / `todo-table.md`
   (O7). No view may link a deleted brief.
   **The handoff seal re-derives in this same commit.** If the merge touched `prompt.md`, run
   `python3 scripts/gate/check_handoff_size.py --reseal` and commit the rewritten
   `scripts/gate/handoff_baseline.txt` beside it — the seal is the station's to write and a lane's never
   to touch, because two lanes resealing loses an entry and a lane that reseals has answered its own
   finding. **A ceiling red after a merge means the handoff GREW: trim the handoff.** Raising a ceiling
   is how this guard gets muted rather than kept. A ⚠ that a new typed count was frozen is the same
   offer twice — deleting the number is the cheaper fix, and the seal is where the rest of the debt gets
   booked, not where it gets argued with.
5. `git worktree remove` each lane worktree, `git worktree prune`, `git branch -d session/<lane>…` (O8), `git push`.
   **The station that merged is the station that pushes** — every station pushes after its merge, so no merged commit
   waits on another host being switched on, and `git status -sb` reading level with `origin/main` is the close-out
   check (an ahead-of count is a step left undone, not a step skipped on request). On `remote: fatal error in
   commit_refs`: re-prove the ACL with `--dry-run`, then retry — GitHub-side, not a key or ACL fault.
   ⚠ **Gate the exit code, not the last line, before any push.** `bash scripts/validate-all.sh | tail -3` exits **0
   whatever the gate found** — a pipe reports the last command's status, so `… | tail && git push` pushes straight
   through a red gate. Measured 2026-10-22: a merged tip went out on a station whose preceding run printed **two**
   failures — the named `check_secret_leak.py` plus `usable-sampler.sh --self-test`, which then passed solo and passed
   a full re-run (a pool-starvation flake, recorded as such in HD-1117, not written as fixed) — and the push had
   already happened. So read the verdict as a value — `bash scripts/validate-all.sh; rc=$?` — and push on `rc=0`.
   Where a red is already on record the **failure list is the test, not the number**: on the pi-dev seat a live
   `rc=1` is the *designed* state until the HD-1181 rotation lands, so compare what the run printed against the named
   set and push only when the two are the same set — then say which named red you shipped.
   ⚠ **A merged branch does not mean a drained worktree — inventory the residue first.** `git merge-base --is-ancestor` proves
   only the *commits*. A lane can be fully merged and still hold uncommitted and untracked files, and `git worktree remove`
   discards them. A merged lane can still be dirty and still hold work that never reached `main`. So before removing: `git -C <wt> status --porcelain` in each, then for every added line decide
   *present-in-`main` / superseded / to-rescue* (`git grep -F -- '<line>' main -- <path>` names which), rescue what is real into
   its owning doc, and only then remove. A row that was **minted inside** the residue must be re-checked against the registry
   before it lands: an id already used in `todo.md` for a different subject is a duplicate mint.
   The detector is `scripts/gate/check_todo_done.py`, already wired into `validate-all.sh`: it keys ids
   on the numeric stem and prints `todo.md:line:col` for every row that shares one, so run the gate IN
   THE MERGED TREE and let it name the collision before anything is re-numbered — it reads only the
   checked-out registry, which is why a lane's parallel mint stays invisible until its branch lands
   and why the merged tree is the first place this check can fire. Where the answer is "superseded", the discard still gets recorded where it is read (the owning doc or
   the domain's `-rejected.md`), because "it existed and was thrown away" is the fact the next session cannot otherwise find.
   ⚠ **A patch-absorbed branch is not an ancestor, and `-d` cannot tell the two cases apart.** When a lane's work reached
   `main` through cherry-picks or an earlier rebase, `git cherry -v main <branch>` shows every commit as `-` yet `git branch -d`
   still refuses — and `-D` is forbidden (O8), so the sweep stalls. The convention-compatible move is `git rebase main <branch>`:
   git drops the already-applied commits, the branch becomes a true ancestor, and `-d` then succeeds with its proof intact.
   ⛔ Also: never run that rebase from the merge station — `git rebase main <branch>` **checks the branch out**, turning the
   primary into an edit context mid-cleanup (`git checkout main` immediately restores it).
6. Prove the station is clean: primary on `main`, `git status` empty, `git worktree list` shows one entry — and
   **no lane process is left holding a host**: the residue inventory is a file list only, and a merged lane can
   still own a live session or a listener on a converge target. The rule and the two process-side reads are
   §Lane residue below; run them before `git worktree remove`, not after.
7. Report: rows closed (= deleted from `todo.md`), rows parked on an owner gate (with the exact blocked
   action), and any row that still has **no** brief — an unbriefed row is not lost, it stays in
   [todo-table.md](../todo-table.md) §B.

**A lane's own close-out is deliberately shorter than CONVENTIONS §close-out**: owning doc + row tail + runbook
line if it did a manual step (O6) + plain `git commit` (commit signing is retired) + `validate-all.sh` green **in its worktree** → **stop**. The
merge, the views and the brief's death belong to the parent.

### Lane residue — what a lane leaves behind (the exit check)

> **The rule: a lane leaves no uncommitted tree, no running process, and no untracked file.** A lane ends when
> its *worktree* is empty, not when its work is described. Three classes of residue outlived their lanes, each
> one measured here rather than theorised, and none of the three is caught by `validate-all.sh`, because every
> one of them is invisible to a checker reading the committed tree.

| Residue | How it was measured | What it costs |
|---|---|---|
| **An uncommitted tree at the deadline** | several lanes reported deliverables by name with **no commit at all** — the work existed only in the child's context, and the run's wall timeout kills without committing | the lane is unrecoverable; step 7's `checkpointBeforeDeadlineMs` and the commit-per-deliverable instruction exist because of this |
| **A process that outlived its lane** | a detached `ssh -n -N -L 5030:<oldsrv's Home address>:5030 oldsrv` was found **LISTENing on the driving seat 5 h 27 m after the lane that opened it finished**, forwarding a loopback port into a production host's service socket (the address is the SSOT's, [network-addresses-generated.md](network-addresses-generated.md) — written here as a name because an IP literal outside the SSOT is a gate failure, and this sentence outlives any one address) | an unowned path into a live host, held by nobody, closed by nobody, and discovered by accident |
| **A half-written file left untracked** | an instrument (a script nothing had `git add`ed) sat in the worktree, so the gate could not see it and no later session could find it | an instrument that does not exist is worse than no instrument: it reports nothing and hides nothing |

**The lane's own exit check — three commands, run by the lane, before it reports:**

```bash
git status --porcelain                                  # must print NOTHING: committed, or it does not exist
ps -eo args | grep -E 'ssh .*(-N|-L|-D)'                # must print NOTHING: no tunnel, no mux you opened
ss -ltn                                                 # must show no port this lane opened
```

⚠ **A tunnel is not a read-only access.** An `-L`/`-D` forward reads nothing by itself, so it feels like a probe,
but it is a standing path from the driving seat into a production host's socket, and its lifetime is the process,
not the task. It survives the context that justified it — the lane is gone, the endpoint stays — and because
nothing owns it, it is found by accident, usually as somebody else's unexplained listener. Kill it when the read
that needed it returns, in the same lane, and prove it with `ss -ltn`; if it must outlive the lane, that is a
parent decision and it goes in the row, not in the shell history.

**The parent-side corollary:** before merging a lane, the parent verifies **no lane process is still holding a
host**. O3's *one converge in flight per host* is a statement about the fleet, not about the branch — it is a lie
if a finished lane left an attached session, a detached run, or a listener on that host, because the next lane
merges into a host that is still busy. `git merge-base --is-ancestor` proves the commits; the process table is a
different proof and step 5's residue inventory does not produce it. Run the same two process-side reads above in
the lane's worktree host before removing the worktree, and if anything is alive, stop the merge and take the work
over rather than freeing a slot that is not free.

