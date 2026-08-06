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
   driver file: goal, runbook, models, environment, task summary, CURRENT_TASK,
   acceptance).

2. **Establish the environment (startup).** Load the `platform-env` skill
   (`skills/platform-env/SKILL.md`) and read the plan's **`## Environment`**
   section. Resolve the repo root and **pin CWD** to it before any command.
   Note the shell flavor and matching constraints (python launcher, path
   separators, temp/home, UTF-8, `&&` validity). Repeat the env note to every
   worker and keep every validation command shell-correct for that environment.

3. **Startup model-review gate (ONE time).** Read the plan's **Models** table and
   presentation-check every task (model, price, AND capabilities — a cheap default
   that can't do what the task needs is a veto even on a fresh table):
   ```
   Task  Difficulty  Selected model           in/M    out/M   caps
   T1    1           openrouter/free          $0      $0      img/txt->txt ·T·J·R·V
   ...
   ```
   **Block until the human approves or edits the assignments.** Only after
   approval do you begin executing. Do not silently change a model.

4. **Execute sequentially.** Take the first task not marked `done`:
   - Read that task's file from `index.md`'s summary (`plan/<date>-<slug>/T<ID>.md`)
     to get its File scope, exact values, executor prompt, and Validation command.
   - Launch a worker via pi-subagents, pointing it at the task FILE using the
     **absolute forward-slash path** (workers may start in a different CWD), and
     tell it to pin CWD to the repo root and apply the platform-env note:
     `run /run worker[model=<selected model>] "Environment: <platform/shell> (see repo root `## Environment`). cd to <abs repo root> first. Execute task T<ID>. Read <abs path>/plan/<date>-<slug>/T<ID>.md; apply its exact File scope and values; then run its exact Validation command (using <py -3|python3>) and report PASS/FAIL."`
   - The worker touches ONLY the task's File scope and applies the exact values.
   - Run the task's **exact Validation command** verbatim (shell-correct for the
     detected environment). Pass = exit 0 (and any stated criterion).

5. **Advance / stop:**
   - **Pass** → set task status `done` in `index.md` (summary table + `CURRENT_TASK`),
     move to the next task.
   - **Fail** → set status `in-progress` in `index.md`, paste the validator output
     into the index, **propose a model upgrade** (next tier / cheaper-capable
     fallback from `references/subagent-routing.md` or the index's Models table), and
     **wait for approval** before retrying. Do NOT skip to the next task.

6. **Human checkpoints.** When you reach a task marked `awaiting-verification`
   (difficulty 4-5 by default), pause and wait for explicit human sign-off before
   marking it `done` and advancing. See `references/human-checkpoints.md`.

7. **Final acceptance.** After the last task, run `index.md`'s **Global acceptance**
   suite (exact commands, exit 0). Append a closing report to `index.md` and set
   `CURRENT_TASK: none`.

8. **Deletion approval.** Ask the human for permission before deleting the
   `/plan/` directory (`index.md` + `T*.md`). Never delete without explicit approval.

## Rules

- **Strictly sequential.** Never run two tasks in parallel.
- **Never edit files outside a task's File scope.** If a worker proposes a scope
  change, stop and escalate to the human.
- **Exact validation only.** "Looks fine" is not a pass; the command must exit 0.
- **Environment-correct commands.** The same command text can behave differently
  per shell (`&&`, `py -3` vs `python3`, `where` vs `which`). Run validators with
  the command syntax and interpreter the detected environment requires; if a
  validation *looks* wrong because of an environment mismatch, fix the invocation
  (per platform-env) rather than declaring a real failure.
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
