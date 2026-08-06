---
name: run-task
description: |
  Executes an execution-plan (a plan/<date>-<slug>/ directory of index.md + one
  T<ID>.md per task) produced by the plan-task skill: one task at a time, no
  parallelism, driving each task with a pi-subagents worker at the task's resolved
  model, running that task's exact validation command, pausing at human checkpoints
  (difficulty 4-5), proposing a model upgrade on failure, and writing a closing
  report. Use after plan-task has produced and the human has reviewed a plan.
---

# run-task — executor / driver

Load an existing plan (produced by `plan-task`) and drive it to completion,
**one task at a time**. You are the orchestrator; subagents do the work. A plan
is a **directory**: `./plan/<date>-<slug>/index.md` (driver/review file) + one
`T<ID>.md` per task (payload).

## Workflow

1. **Locate the plan.** Ask the user which `./plan/<date>-<slug>/` directory to
   run, or read the most recent one if unambiguous. Read **`index.md`** (the lean
   driver file: goal, runbook, models, task summary, CURRENT_TASK, acceptance).

2. **Startup model-review gate (ONE time).** Read the plan's **Models** table and
   presentation-check every task (model, price, AND capabilities — a cheap default
   that can't do what the task needs is a veto even on a fresh table):
   ```
   Task  Difficulty  Selected model           in/M    out/M   caps
   T1    1           openrouter/free          $0      $0      img/txt->txt ·T·J·R·V
   ...
   ```
   **Block until the human approves or edits the assignments.** Only after
   approval do you begin executing. Do not silently change a model.

3. **Execute sequentially.** Take the first task not marked `done`:
   - Read that task's file from `index.md`'s summary (`plan/<date>-<slug>/T<ID>.md`)
     to get its File scope, exact values, executor prompt, and Validation command.
   - Launch a worker via pi-subagents, pointing it at the task FILE (the worker
     reads the task body itself instead of a giant inline paste):
     `run /run worker[model=<selected model>] "Execute task T<ID>. Read plan/<date>-<slug>/T<ID>.md; apply its exact File scope and values; then run its exact Validation command and report PASS/FAIL."`
   - The worker touches ONLY the task's File scope and applies the exact values.
   - Run the task's **exact Validation command** verbatim. Pass = exit 0 (and any
     stated criterion).

4. **Advance / stop:**
   - **Pass** → set task status `done` in `index.md` (summary table + `CURRENT_TASK`),
     move to the next task.
   - **Fail** → set status `in-progress` in `index.md`, paste the validator output
     into the index, **propose a model upgrade** (next tier / cheaper-capable
     fallback from `references/subagent-routing.md` or the index's Models table), and
     **wait for approval** before retrying. Do NOT skip to the next task.

5. **Human checkpoints.** When you reach a task marked `awaiting-verification`
   (difficulty 4-5 by default), pause and wait for explicit human sign-off before
   marking it `done` and advancing. See `references/human-checkpoints.md`.

6. **Final acceptance.** After the last task, run `index.md`'s **Global acceptance**
   suite (exact commands, exit 0). Append a closing report to `index.md` and set
   `CURRENT_TASK: none`.

7. **Deletion approval.** Ask the human for permission before deleting the
   `/plan/` directory (`index.md` + `T*.md`). Never delete without explicit approval.

## Rules

- **Strictly sequential.** Never run two tasks in parallel.
- **Never edit files outside a task's File scope.** If a worker proposes a scope
  change, stop and escalate to the human.
- **Exact validation only.** "Looks fine" is not a pass; the command must exit 0.
- **Human gate is authoritative.** The model-review gate and every
  `awaiting-verification` task pause execution until the human responds.
- Do not invent or auto-apply model upgrades; always propose and wait.

## References

- `references/subagent-routing.md` — how difficulty/model map to `/run <agent>[model=...]`
- `references/human-checkpoints.md` — gate semantics, editing, and approval rules

## Progress state

- Status / `CURRENT_TASK` live **only** in `index.md` (Task summary `Status`
  column). Task files `T<ID>.md` are immutable payload — never write Status into
  them (avoids sync drift).
