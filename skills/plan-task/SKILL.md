---
name: plan-task
description: |
  Produces a self-driving execution-plan as a directory (plan/<date>-<slug>/index.md
  driver file + one T<ID>.md per task) from a goal: ordered, idempotent subtasks
  with exact validation commands, per-task difficulty (1-5) and optional per-task
  model (by price, from a cached OpenRouter tier table with age-aware refresh). Use when the user asks to "plan a change",
  "reorganize X", "prepare an execution plan", "split into tasks", or wants a
  reviewable plan with verifiable endpoints before anything is executed. Pairs
  with the run-task skill, which executes the produced plan.
---

# plan-task — producer

Turn a goal into a **reviewable execution-plan directory** (a lean `index.md` +
one `T<ID>.md` per task) that another agent (`run-task`) can execute one task at
a time. You **never execute** here; you prepare + clarify + emit. The human
reviews and edits the plan before any execution happens.

## Workflow

1. **Scope check.** Confirm this is a plan-production request. If the user wants
   execution now, tell them to run `run-task` afterwards. Do not execute tasks.

2. **Check the environment (every plan).** Load the `platform-env` skill
   (`skills/platform-env/SKILL.md`) and detect the platform + shell
   (`references/detect.md`), then read the matching platform doc
   (`references/windows11.md` or `references/debian.md`). Record the findings so
   they follow the plan into execution:
   - Every emitted plan gets an **`## Environment`** section in `index.md` with:
     platform, shell flavor, repo root, temp dir, home dir, python launcher
     (`py -3` vs `python3`), path-separator convention, encoding/line-ending
     rule, and the 2-3 most load-bearing constraints for THIS plan.
   - Every task's **Executor prompt** carries a one-line env note
     (e.g. "Windows 11 / cmd — pin CWD, use `py -3`, UTF-8; see index `## Environment`").
   - Validation commands must be **shell-correct for the detected shell** (e.g.
     on Windows PowerShell 5.1 `&&` is invalid; on Debian use `python3` not
     `python`). Use forward-slash relative paths from the repo root.

3. **Gather context.** Read the relevant repo/docs/chat history needed to make
   the plan concrete (exact files, existing conventions, constraints).

4. **Auto-refresh the model cache (default — cheap & always current).**
   Capturing live **prices AND capabilities** is cheaper and more reliable than
   deciding whether the cache is "fresh enough", so **refresh by default**:
   - Run the refresh script with the detected Python launcher from the **skill dir**
  (its `references/` and `scripts/` are CWD-relative), e.g. on Windows:
  `cd /d skills\plan-task && py -3 scripts\refresh-model-cache.py`; on Debian:
  `cd skills/plan-task && python3 scripts/refresh-model-cache.py`
  (live prices + capability flags).
     On success: review the table, adopt sensible new candidates, persist, then
     re-derive the proposed models for THIS plan from the refreshed cache.
   - Adopt what you approve (all part of the refresh):
     - `--apply` → persist tracked models with updated price/tier,
     - `--add <id1,id2>` → adopt specific NEW candidates,
     - `--add-new` → adopt every relevant NEW model (zero-cost / globally-cheapest
       / cheapest-per-tier).
   - If refresh fails/offline: use `references/model-cache.json` as-is and state
     "offline — using cached table (fetched_at <age>)".
   - **Always show the cache table with price AND capability flags**, so a
     cheap-but-incapable pick is visible even when the table is brand new.
     ```
     Cache age: 3d 2h (offline) / just refreshed
     id                tier  in/M      out/M    caps
     openrouter/free   T1    $0.0000   $0.0000  image/text->text ·T·J·R·V
     ...
     Proposed for this plan: T1(1)->openrouter/free $0 ·... ; T3(3)->deepseek-v4-pro $0.435 text->text ·T·J·R
     ```
   - **Present the proposed Models table** (task → difficulty → model → price →
     caps) so the human can override at the `run-task` model gate if a default's
     capabilities don't fit that task's needs — even if the table is fresh.
   - Always display price and capabilities alongside any model you propose.

5. **Clarify** — only ask what the chat history does not already answer. Load
   `references/clarification-checklist.md` and ask the unresolved items
   (goal/success criteria, scope + invariants, compatibility constraints,
   execution model, checkpoint placement, plan output path). Never ask
   redundant questions.

6. **Decompose** the goal into ordered tasks following
   `references/task-section-template.md`. Compute per-task:
   - `difficulty` (1-5) via `references/selection-algorithm.md` rubric table.
   - `model` via the price-driven selection rules in
     `references/selection-algorithm.md` (cheap first; difficulty 1-3 now default
     to free; propose-upgrade fallback on failure).
   - `validation` = an **exact command** + **exact pass criterion** (usually
     "exit code 0"). Make each subtask idempotent ("skip if already valid").
   - **`dependencies`** = which tasks must be `done` before this one runs, and any
     sibling task that WRITES THE SAME FILE as this one (forces serialization).
     Record it in the task file (see below) and in the index dependency graph.

7. **Human checkpoint placement** — insert an `awaiting-verification` gate on
   **difficulty 4-5** tasks by default (human-editable). Lower-difficulty tasks
   get no gate unless the human asks for one.

8. **Emit** a plan **directory** at `./plan/<YYYY-MM-DD>-<slug>/` (relative
   `plan/` subdir of the repo root) using `references/manifest-template.md`:
   - `index.md` — the lean driver + review file: goal, runbook, **Environment**
     (detected platform/shell), global invariants, the resolved **Models** table
     (per task: difficulty, selected model, price in/out), the **Dependency graph**
     (edges + shared-file notes), the **Task summary**
     progress table, `CURRENT_TASK`, **Global acceptance**, and Out of scope. Keep
     this small.
   - `T1.md`, `T2.md`, ... — **one file per task**, each following
     `references/task-section-template.md` (objective, file scope, exact values,
     subtasks, difficulty, model, validation, executor prompt).
   - Each per-task file is the ONLY place the worker needs to read; heavy payload
     tables (e.g. a 40-row frontmatter map) live in the task file, NOT in index.
   - **Every task file carries a `**Dependencies:**` line** (task IDs it waits on,
     or `none`) plus a shared-file note where a sibling writes the same path.
   - index.md includes a **`## Dependency graph`** section (edges + shared-file
     serialization notes) so concurrency is explicitly visible.
   - The **Task summary** table in `index.md` is the single source of progress
     state (Status column); per-task files do NOT carry their own status.

9. **Hand off** — tell the human the plan is ready for **review and editing**
   (difficulty, models, gate placement, validation). Do not execute. Remind
   them that `run-task` will present the model-assignment table for final
   approval before running.

## Rules

- **Never execute** a task in this skill. Your output is a plan + a clear
  handoff.
- **Record dependencies + shared files** so `run-task` can schedule safely and
  concurrently when the human opts in.
- **Idempotent subtasks only**: each subtask states "skip if already valid" so
  interrupted/reread execution is safe.
- **Exact validation**: every task's Validation block is a copy-pasteable
  command plus a binary pass criterion. No "it looks right".
- **Only ask what's missing.** Minimize friction.

## References

- `references/clarification-checklist.md` — questions to ask when context is thin
- `references/manifest-template.md` — the skeleton for `plan/<date>-<slug>/index.md`
- `references/task-section-template.md` — the per-task file (`T<ID>.md`) schema
- `references/selection-algorithm.md` — difficulty rubric + price-driven model selection
- `references/model-cache.json` — cached tier/prices (age + 30d stale threshold)
