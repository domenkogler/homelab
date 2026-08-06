# task-section-template (T<ID>.md)

Every plan has **one file per task**: `plan/<date>-<slug>/T<ID>.md`. This file is
the ONLY thing the executing worker needs to read. `run-task` hands the worker
this file's path, and the worker transcribes rather than invents. Status is NOT
stored here — the `index.md` Task summary table is the single source of progress.

```markdown
# T<ID> — <short title>

**Objective:** one sentence describing the outcome.

**File scope (ONLY these):**
- path/to/file
- path/to/file

**Exact values to insert** (top of file / where specified):
| File | field | value |
|------|-------|-------|
| ...  | ...   | ...   |

**Subtasks (do in order; tick as you go):**
- [ ] 1. Read the file; skip this subtask if already valid (idempotent)
- [ ] 2. Apply exact values above; do NOT change any existing body lines
- [ ] 3. Do NOT touch anything outside File scope

**Difficulty:** <1-5>

**Model:** <openrouter model id, e.g. deepseek/deepseek-v4-pro>

**Capabilities:** <compact flags, e.g. text->text ·T·J·R | in/file/img/txt->txt ·T·J·R·V>
<state why this fits the task if it is non-obvious, e.g. "vision needed by T3">

**Validation:**
```
<EXACT command, e.g. `python scripts/validate-plan.py --task T4`>
# pass = <EXACT criterion, e.g. "prints PASS for all checks and exits 0">
```

**Executor prompt (paste to the worker):**
> Environment: <platform/shell> — pin CWD to repo root (<abs path>), use <py -3|python3>
> for validators, UTF-8 no-BOM; see index
> (`plan/<date>-<slug>/index.md` `## Environment`) for full platform rules.
>
> You are executing task T<ID>. Read THIS file (`plan/<date>-<slug>/T<ID>.md`)
> for the exact File scope and values. Touch ONLY those files. Insert the exact
> values, transcribe them verbatim, and change no existing body lines. Then run
> the exact Validation command below. Report PASS or FAIL. On PASS, your driver
> (run-task) marks the task `done` in `index.md` and advances. On FAIL, stay
> `in-progress`, paste the validator output, and STOP - do not advance.
```

## Rules for writing task files

- Every subtask is **idempotent**: state the skip condition explicitly.
- Keep subtasks small and independently verifiable (a failure localizes).
- Order matters; the checklist preserves partial progress on interruption.
- The executor must never need to make a judgment call about scope or values.
- Carry **status in `index.md` only** — never add a `[Status: ...]` header here.
- If the task has a large payload (big table / many files), it lives entirely in
  this task file; the index references it only by filename.
