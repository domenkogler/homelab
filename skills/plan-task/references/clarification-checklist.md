# Clarification checklist

Ask **only** the items whose answers are not already in the chat history / repo.
Each item maps to a section of the plan you will emit. Stop as soon as it is
unambiguous; do not interrogate the user.

## Required before you can write a concrete plan

| # | Question | Feeds plan section |
|---|----------|--------------------|
| 1 | What is the goal, and what does "done" look like? What is the success criterion? | Objective, Final acceptance |
| 2 | What is in scope / out of scope? Exact files or folders? | File scope (each task), Global invariants |
| 3 | What must NOT break or change (compatibility constraints, e.g. "no renames", "no wikiwikilinks", "must keep rendering on GitHub/Doco-CD", "no secrets committed")? | Global invariants + validation |
| 4 | Execution model: plan only, or plan + execute afterward? Single agent or subagents? Parallel or strictly sequential? | Driver runbook |
| 5 | Are human checkpoints wanted, and where? (Default: only difficulty 4-5.) | task `awaiting-verification` gates |
| 6 | Where should the plan document live? (Default: `./plan/`.) | output path |

## Defaults you may assume (state them, don't ask)

- Execution is **strictly sequential, one task at a time, no parallelism**.
- Each task is **fully idempotent** ("skip if already valid").
- Each task's **validation is an exact command + exit-code-0** pass.
- Review happens **before execution**: plan is human-edited, then `run-task`
  re-presents the model table for approval.
- Models are selected **cheap-first** from the cached tier table; difficulty
  1-2 default to the free router and never use a T4 model.
- Human checkpoints on difficulty 4-5 only (editable).

## If context is fundamentally insufficient

If the goal is too vague to decompose safely, list what is missing and ask the
user to provide it. Do **not** fabricate a file scope or success criteria.
Producing a plausible-but-wrong plan is worse than asking.
