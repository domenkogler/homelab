---
name: run-task
description: |
  Executes an execution-plan (a plan/<date>-<slug>/ directory of index.md + one
  T<ID>.md per task) produced by the plan-task skill: drives each task with an
  isolated pi-subagents worker at the task's resolved model, runs each task's
  exact validation command, pauses at human checkpoints (difficulty 4-5),
  proposes a model upgrade on failure, and writes a closing report. You are the
  ORCHESTRATOR: you launch workers, own index.md progress, and decide scheduling.
  Supports sequential AND concurrent execution (concurrency is opt-in, asked at
  the start). Use after plan-task has produced and the human has reviewed a plan.
# NOTE: explicit-only skill. Invoke it via /skill:run-task or by naming it; it is
# hidden from automatic model invocation (disable-model-invocation: true).
disable-model-invocation: true
---

# run-task — executor / driver

Load an existing plan (produced by `plan-task`) and drive it to completion.
**You are the orchestrator; subagents do the per-task work.** A plan is a
**directory**: `./plan/<date>-<slug>/index.md` (driver/review file) + one
`T<ID>.md` per task (payload).

The orchestrator NEVER delegates its own duties. **Designated subagents cleanly
isolated from the orchestrator context** — so a worker cannot read the whole
plan and try to run other tasks. Nothing about running tasks changes what is
"managed": you schedule, workers execute exactly one task each, you own progress.

## Workflow

1. **Locate the plan.** Ask the user which `./plan/<date>-<slug>/` directory to
   run, or read the most recent one if unambiguous. Read **`index.md`** (goal,
   runbook, models, environment, dependency graph, task summary, CURRENT_TASK,
   acceptance).

2. **Establish the environment (startup).** Load the `platform-env` skill
   (`skills/platform-env/SKILL.md`) and read the plan's **`## Environment`**
   section. Resolve the repo root and **pin CWD** to it before any command.
   Note the shell flavor and matching constraints (python launcher, path
   separators, temp/home, UTF-8, `&&` validity). Repeat the env note to every
   worker and keep every validation command shell-correct for that environment.

3. **Concurrency gate — ASK FIRST (ONE time).** Before any launch, ask the
   human explicitly:
   > "Run tasks concurrently, or strictly one at a time?"
   Do not assume. **Default = sequential** unless the human opts into
   concurrency. If concurrent, confirm the plan is safe to parallelize (see
   `How to decide concurrency` below) and note the chosen mode in your report.

4. **Startup model-review gate (ONE time).** Read the plan's **Models** table and
   presentation-check every task (model, price, AND capabilities — a cheap default
   that can't do what the task needs is a veto even on a fresh table):
   ```
   Task  Difficulty  Selected model           in/M    out/M   caps
   T1    1           openrouter/free          $0      $0      img/txt->txt ·T·J·R·V
   ...
   ```
   **Block until the human approves or edits the assignments.** Only after
   approval do you begin executing. Do not silently change a model.

5. **Execute.** For each task not `done` (sequentially, or a batch of
   concurrently-safe tasks — see below):
   - Read that task's file (`plan/<date>-<slug>/T<ID>.md`) to get its File scope,
     exact values, executor prompt, and Validation command.
   - Launch a worker via pi-subagents, pointing it at the task FILE using the
     **absolute forward-slash path**, pinning CWD to the repo root, with the
     platform-env note. **Isolation is mandatory** (see `Worker isolation`):
     - fresh context (NOT a fork of the orchestrator),
     - a scoped prompt naming ONLY its one task file,
     - explicit forbids: reading `index.md`/sibling `T*.md`, editing `index.md`,
       touching anything outside its File scope, running other tasks,
     - a `turnBudget` (default cap) so it cannot spiral.
   - Run the task's **exact Validation command** verbatim (shell-correct for the
     detected environment). Pass = exit 0 (and any stated criterion).

6. **Advance / stop:**
   - **Pass** → set task status `done` in `index.md` (summary table + update
     `CURRENT_TASK` to the next runnable task), move to the next.
   - **Fail** → set status `in-progress` in `index.md`, paste the validator output
     into the index, **propose a model upgrade** (next tier / cheaper-capable
     fallback from `references/subagent-routing.md` or the index's Models table), and
     **wait for approval** before retrying. Stop the dependent chain — tasks that
     depend on a failed task must NOT start. Do NOT skip a failed task.

7. **Human checkpoints.** When you reach/pass a task marked `awaiting-verification`
   (difficulty 4-5 by default), pause and wait for explicit human sign-off before
   marking it `done`. A gate task blocks its dependents regardless of concurrency.
   See `references/human-checkpoints.md`.

8. **Final acceptance.** After the last task, run `index.md`'s **Global acceptance**
   suite (exact commands, exit 0). Append a closing report to `index.md` and set
   `CURRENT_TASK: none`.

9. **Deletion approval.** Ask the human for permission before deleting the
   `/plan/` directory (`index.md` + `T*.md`). Never delete without explicit approval.

## How to decide concurrency

A task may run **concurrently with others only if ALL of these hold**:
- The human opted into concurrency at step 3.
- Its **dependency edges are satisfied**: per the plan's `## Dependency graph`,
  every task it depends on is already `done` (or is also being run this batch and
  the graph shows an explicit serial edge you are respecting).
- Its **File scope is disjoint** from every other concurrently-running task (they
  do not write the same path). Two tasks editing the SAME file (e.g. both appending
  to one `group_vars/...yml`) must be serialized, even if independent.
- It is **not** an `awaiting-verification` gate task that has not been approved
  (gate tasks run alone while the human reviews).
- Your task tool limits (max parallel, concurrency cap) are respected.

When in doubt, **serialize**. Concurrency is a scheduling optimization, not a
requirement; a batch of 2-3 independent, disjoint-scope tasks is the sweet spot.

## Worker isolation (safety — always)

Every per-task worker MUST be launched so it cannot take over the run:
1. **fresh context, not fork** — it inherits none of your plan/chat/skill context.
2. **Scoped prompt** — name ONLY its single task file; do not reference the index.
3. **Explicit forbids** — "do NOT read `plan/.../index.md` or any sibling `T*.md`;
   do NOT edit `index.md` (the orchestrator owns it); touch ONLY the File scope
   listed in your task file; stop after your exact Validation command; do not start
   other tasks."
4. **turn budget** — cap worker turns (e.g. a generous but finite ceiling) so a
   degenerate loop aborts instead of drifting.
5. **Acceptance evidence** — require `changed-files` scope evidence so any
   out-of-scope write is flagged.

You (orchestrator) are the ONLY writer of `index.md` Status/CURRENT_TASK. If a
worker reports it edited `index.md` or ran multiple tasks, treat that as a scope
breach and re-verify its output independently before trusting it.

## Rules

- **Scheduling is yours, not the workers'.** Workers run one task each; they never
  read the plan index or other task files, never update progress, never launch
  other subagents.
- **Concurrency is opt-in.** Ask at the start; default sequential. Only run
  concurrent batches that satisfy every clause in `How to decide concurrency`.
- **Respect the dependency graph.** A task never starts before its dependencies
  are `done`; a dependent of a failed task never starts.
- **Never edit files outside a task's File scope.** If a worker proposes a scope
  change, stop and escalate to the human. You (orchestrator) also do not edit
  task files; you only update `index.md` progress.
- **Exact validation only.** "Looks fine" is not a pass; the command must exit 0.
- **Environment-correct commands.** The same command text can behave differently
  per shell (`&&`, `py -3` vs `python3`, `where` vs `which`). Run validators with
  the command syntax and interpreter the detected environment requires; if a
  validation *looks* wrong because of an environment mismatch, fix the invocation
  (per platform-env) rather than declaring a real failure.
- **Human gate is authoritative.** The concurrency gate, model-review gate, and
  every `awaiting-verification` task pause execution until the human responds.
- Do not invent or auto-apply model upgrades; always propose and wait.

## References

- `references/subagent-routing.md` — model/difficulty mapping + safe worker launch
- `references/human-checkpoints.md` — gate semantics, editing, and approval rules

## Progress state

- Status / `CURRENT_TASK` live **only** in `index.md` (Task summary `Status`
  column). Task files `T<ID>.md` are immutable payload — never write Status into
  them (avoids sync drift).
