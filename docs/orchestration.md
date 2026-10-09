> **Role:** the PERMANENT process contract for repo sessions — the working contract (§3) and the
> lane-session orchestrator mode (§4, overrides O1–O9, launch, merge/cleanup). It was moved out of
> [prompt.md](../prompt.md) on 2026-09-28 when the handoff was slimmed; the LIVE wave table is NOT here —
> it lives in [todo-table.md](../todo-table.md) §B0. Where the contract below is silent,
> [README.md](../README.md) §4 and [CONVENTIONS.md](../CONVENTIONS.md) §6 stand and outrank everything.
> **Linked from:** [prompt.md](../prompt.md) · [README.md](../README.md) §4 · [todo-table.md](../todo-table.md) §B0 · [CONVENTIONS.md](../CONVENTIONS.md) §4/§6

---
## 3. Working contract (non-negotiable)

1. **Step-0 ritual, in order:** first the conventions map — `grep -n "^#\|^## \|^### " CONVENTIONS.md | head -40` (README §0 step 1; every rule here is cited by §, so the outline comes before the file) — then `git status` sanity + fresh session worktree (`git worktree add ../homelab-wt-<date>-<HHMM>`, CONVENTIONS §6) — enforced by `scripts/guard-session.sh`.
2. **Prior-art sweep** before new HD rows: todo.md + owning docs + `<domain>-rejected.md` + `git log -S 'HD-…'` (re-decide ban). The sweep applies to **your own open questions and claims** too, and a claim needs the *implementation* read, not a matched line: a docs sweep on 2026-09-20 asserted `environment: {}` (the compose renders `TZ`), called a settled `group_vars/vps.yml` decision an owner call, and named tailnet hosts that existed nowhere — three errors, one cause.
3. **Validate before finishing:** `bash scripts/validate-all.sh` must end green (checks prompt↔todo consistency, SSOT doc map, IP literals, placeholders, done-row deletion, **and the two doc-role contracts** below). Since 2026-10-06 it activates `~/ansible-venv` itself and preflights `import jinja2, yaml`, so **a non-interactive green counts**: the gate used to die on `ModuleNotFoundError: jinja2` under cron/pi/a converge — the venv reaches PATH only through `~/.bashrc`, which non-interactive shells skip — while the same commit went green from an interactive shell, which made the verdict depend on the invoker instead of the tree. Verified non-interactively on BOTH Debian seats (oldsrv + the WSL primary, 2026-10-06).
   - **Ledger vs runbook (gated since 2026-09-19 — do not fight the gate):** `deployment-tasks.md` is the **only** place progress is written, as `- [ ] **HD-nnn** — <pending action> · [doc]` lines; every open one must have a live `todo.md` row (closed row → delete the line, the record is the owning doc + the commit), every `- [x]` carries its date. `deployment-manual.md` is **imperative procedure only** — no ✅/⏳ markers, no dated or "live lesson / as executed / close-out" narrative, no inlined knowledge (link the owning doc), and its `## Phase N` numbers must match the ledger's (spark = **Phase 4b** in both). Anything automated stays in IaC, not in prose.
4. **SSOT direction:** values in IaC (`group_vars/*.yml`, `host_vars/*.yml`) · generated `*-generated.md` never hand-edited · secrets 1Password `Homelab-ansible` only, fail-loud (no `default('')`).
5. **Lifecycle:** fully-done HD row → **deleted** from todo.md (record in owning doc + git). IaC-done-but-deploy-gated row stays with a ⏳ tail. Decisions written once to the owning doc + `<domain>-rejected.md`.
6. **Close-out:** record the outcome + runbook in the owning doc; commit (plain `git commit` — signing retired, HD-1116); merge/push per the session branch policy (unmerged `session/*` branches are the norm until the deploy-gate flips).
7. **Orchestrator discipline (2026-09-08 lesson):** for multi-step/multi-host/live-deploy changes, one parent co-ordinates bounded single-deliverable subagent lanes (pi-subagents); the parent holds final acceptance + runs validate-all. Timebox reviews (~10 min); a child exceeding that with no verdict is steered to wrap up.

**Ask-if-unsure:** planned/multi-host/deploy-gated/irreversible → orchestrator pattern; re-deciding → check owning doc + rejected log first; unsure of the owning doc → `docs/index.md` map.


---

## 4. Orchestrator mode — independent lane sessions, one merge station

> **Read this first if you were launched from a `prompt-<domain>.md` brief.** This section is the **parent**
> contract for running two (or more) independent lane sessions in parallel, and it is an **OVERRIDE, not a
> restatement**: the nine items **O1–O9** below deliberately behave differently from [README.md](../README.md)
> §4 and [CONVENTIONS.md](../CONVENTIONS.md) §6 + its Session close-out row. **Where this section is silent,
> README and CONVENTIONS stand and outrank everything.** A brief is a dispatch note: it can narrow §4, never
> widen it, and if a brief contradicts §4 then **§4 wins and the brief is wrong** — fix the brief, do not
> improvise a third set of rules in the middle of a lane.

**Two different things in this repo are both called "orchestrator" — do not conflate them:**

| Mode | What actually runs | Governed by |
|---|---|---|
| Subagent lanes | bounded, single-deliverable **children inside one session** (pi-subagents); the parent holds acceptance | README §4 item 7 + README §"Orchestrator + reviewer discipline" (HD-346). **Unchanged by this section.** |
| **Lane sessions (this section)** | **two independent full sessions**, each with **its own brief, its own worktree and its own branch**, each closing several HD rows; the parent launches both, merges both, and owns the cleanup | **§4.** A lane session is a normal repo session *plus* these overrides — it is not a subagent, it has no parent in its own process, and §4 is its only extra rule. |

### The overrides — why a lane session must not behave exactly like a README §4 session

| # | The normal rule | Orchestrator mode | Why it differs |
|---|---|---|---|
| **O1** | CONVENTIONS §worktree: "main receives only **fast-forward** merges" | The **first** lane to finish is FF-merged. The **second** runs `git rebase main` inside its own worktree, re-runs `validate-all.sh` there, and is then FF-merged. **A merge commit is never created on `main`.** | Two parallel branches cannot both be ancestors of one `main`; rebase keeps the FF invariant honest instead of abandoning it |
| **O2** | CONVENTIONS close-out (3) + (5): **the session** updates `prompt.md`, by editing the previous handoff | **`prompt.md` and `todo-table.md` are orchestrator-only.** A lane session does not touch either. It edits **only its own `todo.md` rows** (row-local hunks — never re-sort, re-flow or renumber the tables) and may tick **only its own** `deployment-tasks.md` lines | `scripts/check_todo_done.py` fails on any disagreement between `prompt.md`'s open/done claims and `todo.md`. With two writers on the views, a red gate is the *expected* outcome, not an accident |
| **O3** | [todo-table.md](../todo-table.md) §C4: `docs/services-ai*.md` + `IaC/ansible/templates/docker_services/**` are one-writer-at-a-time (read tree-wide) | Narrowed to **one writer per service directory** + **one converge in flight per host**. oldsrv / VPS / spark / router are separate slots; **the router slot is global** (its converge is the device-wide `/import`). `docs/services-ai*.md` stays single-writer (lane 407's) | Read tree-wide, that rule forbids any two lanes existing; the real hazard it guards is two converges restarting containers on one host and the `--diff` secret-dump class, both of which are per-directory + per-host |
| **O4** | README §4.7 + CONVENTIONS: planned / multi-host / deploy-gated → **stop and ask** | **Park and continue.** An owner gate reached inside a lane is written into that row's ⏳ tail as the *exact* blocked action; the lane finishes everything unblocked and names the park in its final report. It does not stall the sibling lane and does not end its session early | A lane that waits unattended burns the whole parallel slot — and every brief contains at least one owner-gated row |
| **O5** | CONVENTIONS §worktree: the primary checkout is a merge station | Kept **strictly**, and it also binds the **orchestrator**: the cleanup commit (view re-sync, brief deletion, link fixes) is made in **its own worktree/branch**. `scripts/guard-session.sh` refuses edits while primary sits on `main`, and `validate-all.sh` **hard-fails on primary + main + dirty** — only a *clean* main validation is the exempt form | The merge station is not an edit site, not even for tidying up after a merge |
| **O6** | README §4.8: ownership follows the action; the session that did the work writes the runbook line | **Unchanged, and it is on the lane.** `deployment-manual.md` is deliberately claimed by no brief, so a lane that performed any hand-repeatable step writes the imperative line **in its own commit** | The exact hole README §4.8 was written for; the orchestrator must not be expected to notice it after the fact |
| **O7** | CONVENTIONS §lifecycle: a closed row is deleted from `todo.md` | Kept for the lane. The **domain brief file itself** is deleted by the **orchestrator**, in the cleanup commit, **in the same commit as the link fixes** in `prompt.md`, `todo.md` and `todo-table.md` | `scripts/check_doc_map.py` scans every root `*.md` **except `prompt-*`**: a dangling link from `todo.md`/`todo-table.md`/`prompt.md` fails the gate, while a link from one brief to another is not checked at all (this corrects the belief recorded in `prompt-414.md` row 8) |
| **O8** | CONVENTIONS §worktree: on a path collision, abort and pick a new name | Hard rule for the parent too: it **never** `rm`s / moves / renames a worktree it did not create; lane worktrees are removed **after** the merge, **by name**, with `git worktree remove`; branches die by `git branch -d` (**never `-D`**) | The 2026-08-23 incident; and `-d`'s refusal is the cheap proof that nothing was stranded |
| **O9** | README §4.7 + CONVENTIONS §6: nothing bounds how many **sessions** a run may have — O3 caps *converge slots*, not contexts, so launching a lane per brief is legal on its face | Sessions are cheap, **contexts are not**. At most **8 concurrent agent sessions** and at most **2 full-context sessions — the orchestrator counts as one**. The default shape is *orchestrator + one lane*; a **third** is allowed only when the other two are near done, and **4 is the ceiling, never exceeded**. Anything beyond must be a **narrow-context child** (a bounded single-deliverable subagent with its own fresh, small context — README §4 "Orchestrator + reviewer discipline") and never a second full lane wearing a brief. The brief pool is a **dispatch queue, not a parallelism licence** | A full lane session pays the README §0/§1 boot ritual (~60 k tokens of `todo.md` alone), so parallel lanes are paid for out of the context budget, not the session budget; rows queued behind an occupied host slot (O3) are **waiting, not missing** |



> **The live lane map (waves) is state, not contract — it lives in [todo-table.md](../todo-table.md) §B0.**
> Pairing constraints (never two lanes on one converge host, O3) are contract; which brief is
> live this week is not.



> **Probe lanes — outside the wave system, deliberately.** Two have run; both are **closed** and both briefs are
> **deleted**. The surviving pointers are these lines:
> * **`prompt-OV.md` (OpenViking, closed 2026-09-21):** **rejected outright** (corpus index *and* memory fallback),
>   logged in [`docs/services-ai-rejected.md`](services-ai-rejected.md), evidence
>   [`reports/probe-ov-20260921.md`](../reports/probe-ov-20260921.md). Do not re-propose OV without the exception note
>   §8.3 requires; the reopen triggers are in that log.
> * **`prompt-agentmemory.md` (agentmemory, closed 2026-09-22):** measurement-only, no `HD-` row by design. Its
>   findings are folded into [`docs/services-ai.md`](services-ai.md) §9b (memory-plane note) + §10, evidence
>   [`reports/probe-agentmemory-20260921.md`](../reports/probe-agentmemory-20260921.md). **The owner calls OQ-12/13/14
>   are OPEN** ([todo.md](../todo.md) §1) — nothing was installed, nothing was decided.
> Probe lanes still matter to **O3**: they stand things up **on oldsrv** under the `domen` seat (a venv / npm prefix,
> never a container) and drive the local AI legs, so they contend for that box and its dGPU even while converging
> nothing — check whether one is in flight before launching an oldsrv lane, and never run one beside
> [`prompt-376.md`](../prompt-376.md). A new probe brief is written only on the owner's request.


### Launch procedure (the parent)

1. Primary = merge station: `git fetch`, `git status` clean, `git checkout main`, `bash scripts/validate-all.sh` green (clean-main is the exempt form under O5).
2. One worktree + branch per lane, created **by the parent** so the naming is never improvised:
   `git worktree add -b session/<lane>-$(date +%Y%m%d-%H%M) ../homelab-wt-$(date +%Y%m%d-%H%M) main`
3. Hand each lane exactly four things: its brief path, the sibling brief path, this §4, and the standing
   instruction **"do not edit `prompt.md` or `todo-table.md`"** (O2). The brief carries the rest.
4. Check the converge slots before launching: two lanes must not share a host (O3). If the only work left in
   two lanes is on one host, they are sequential, not parallel.


### Merge + cleanup (the parent — none of this is ever a lane's job)

1. Touch nothing until both lane branches are **committed and green in their own worktree** — and prove that to yourself: `git -C <lane-worktree> log --oneline -1` + `git show --stat` + `git status --short`. **A lane's own report is not evidence.** Measured 2026-09-25 on this very contract: two delegated `worker` sessions on HD-439 each returned a finished report naming files, line numbers, validator output and a commit message — and the lane worktree was **empty**, no commit, no changed byte, twice, with the two reports contradicting each other on the facts they claimed to have measured. A lane that says "done" and a lane that is done are different claims; only `git log` decides. (It also means a fabricated report can be politely refused: stop the run, keep the row open, take the work over.)
2. FF-merge lane A into `main` from the primary; `bash scripts/validate-all.sh` there.
3. Rebase lane B onto `main` **inside its worktree** → re-run `validate-all.sh` **there** → FF-merge B (O1).
4. Open **the parent's own worktree/branch** (O5) and make cleanup **one commit**:
   re-sync `todo-table.md` from the merged `todo.md` + `prompt.md` (it is a view, not a second record);
   update `prompt.md` §2 to the post-merge state and remove the closed brief from the wave table;
   `git rm` each finished brief **together with** its link fixes in `prompt.md` / `todo.md` / `todo-table.md`
   (O7). The 2026-09-22 sweep paid the last scheduled debt: `prompt-405.md`, `prompt-next.md`, `prompt-OV.md` and
   `prompt-agentmemory.md` are gone and no view links a deleted brief.
5. `git worktree remove` each lane worktree, `git worktree prune`, `git branch -d session/<lane>…` (O8), `git push`.
   ⚠ **A merged branch does not mean a drained worktree — inventory the residue first.** `git merge-base --is-ancestor` proves
   only the *commits*. A lane can be fully merged and still hold uncommitted and untracked files, and `git worktree remove`
   discards them (measured 2026-10-07 sweeping four stale lanes: every one was merged, every one was dirty, and three held
   work that had never reached `main` — a new `docs/deployment-secrets.md` section, three never-committed scripts, and a bench
   driver). So before removing: `git -C <wt> status --porcelain` in each, then for every added line decide
   *present-in-`main` / superseded / to-rescue* (`git grep -F -- '<line>' main -- <path>` names which), rescue what is real into
   its owning doc, and only then remove. A row that was **minted inside** the residue must be re-checked against the registry
   before it lands: one such row said `HD-491`, which `todo.md` already uses for the CrewAI call — the duplicate-mint class
   HD-495's row records. Where the answer is "superseded", the discard still gets recorded where it is read (the owning doc or
   the domain's `-rejected.md`), because "it existed and was thrown away" is the fact the next session cannot otherwise find.
   ⚠ **A patch-absorbed branch is not an ancestor, and `-d` cannot tell the two cases apart.** When a lane's work reached
   `main` through cherry-picks or an earlier rebase, `git cherry -v main <branch>` shows every commit as `-` yet `git branch -d`
   still refuses — and `-D` is forbidden (O8), so the sweep stalls. The convention-compatible move is `git rebase main <branch>`:
   git drops the already-applied commits, the branch becomes a true ancestor, and `-d` then succeeds with its proof intact
   (measured 2026-10-06 on `session/hd469-run3-0019`: 4/4 patches upstream, `-d` refused, rebase → 0 commits ahead → deleted).
   ⛔ Also: never run that rebase from the merge station — `git rebase main <branch>` **checks the branch out**, turning the
   primary into an edit context mid-cleanup (`git checkout main` immediately restores it).
6. Prove the station is clean: primary on `main`, `git status` empty, `git worktree list` shows one entry.
7. Report: rows closed (= deleted from `todo.md`), rows parked on an owner gate (with the exact blocked
   action), and any row that still has **no** brief — an unbriefed row is not lost, it stays in
   [todo-table.md](../todo-table.md) §B.

**A lane's own close-out is deliberately shorter than CONVENTIONS §close-out**: owning doc + row tail + runbook
line if it did a manual step (O6) + plain `git commit` (signing retired, HD-1116) + `validate-all.sh` green **in its worktree** → **stop**. The
merge, the views and the brief's death belong to the parent.

