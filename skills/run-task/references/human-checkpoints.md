# human-checkpoints

Rules for the `awaiting-verification` status and the startup model gate.

## When checkpoints appear

- `plan-task` inserts an `awaiting-verification` gate on **difficulty 4-5**
  tasks by default. Lower-difficulty tasks have none unless the human added one.
- The human may **edit** the plan to add/remove gates before execution. Respect
  whatever gates are present in the plan; do not second-guess them.

## Gate semantics (at execution time)

When you reach a task whose status is `awaiting-verification`:

1. **Pause.** Do not mark it `done` yet.
2. Present the task's summary to the human:
   - Objective, files touched, difficulty, model used, validation result.
   - Any diffs the worker produced (so the human can eyeball correctness).
3. **Wait** for explicit approval, edits, or a request to redo.
4. On approval → mark `done`, advance. On "edit" → apply the edit, re-run the
   exact Validation command, then re-present.

## Startup model gate (run-task step 4)

- Single, one-time gate at the start. Show the full Task → model table
  (model, price, caps) and note any capability mismatch.
- The human **approves once** (then it runs without further model prompts) or
  **edits** it (then run with the edited assignments).
- The human may also edit `index.md` (or a task file) directly between
  `plan-task` and `run-task`; treat the plan's Models table as authoritative at
  startup.

## Concurrency gate (run-task step 3)

- run-task **asks first** whether to run concurrently or one at a time; default
  is sequential unless the human opts in.
- A task may run concurrently only if its dependencies (plan `## Dependency graph`)
  are satisfied, its File scope is disjoint from other running tasks, and it is
  not an unapproved gate task. See run-task `How to decide concurrency`.

## Gates under concurrency

- An `awaiting-verification` gate task runs alone while the human reviews; its
  **dependents must not start** until it is approved and marked `done`.
- A dependent of a **failed** task must not start, regardless of the mode.

## Safety

- Never mark a gate task `done` without a human response.
- If the human is silent, stop and wait — do not auto-continue past a gate.
