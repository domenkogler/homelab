# subagent-routing

How a plan task's `difficulty` and `Model` become a pi-subagents execution, and
how workers are launched **safely** (isolated so they cannot take over the run).

## Mapping

| Difficulty | Worker role | `thinking` | Notes |
|-----------|-------------|-----------|-------|
| 1-2 | `worker` | low/medium | mechanical, well-specified |
| 3 | `worker` | medium | multi-file, careful editing — **free tier is fine for well-scoped tasks** (verified); escalate on validation failure |
| 4 | `worker` (or `delegate` + `reviewer`) | high | demanding; add a review pass if the human wants; human gate |
| 5 | `planner`-refined worker + `reviewer` | high | ambiguous/high-risk; fanout review recommended; human gate |

## Model argument

Every launch passes the task's **resolved model** from the index Models table as
a per-run override (strongest precedence; never mutates global settings), and
points the worker at the task FILE so it reads the exact scope/values itself.

## Safe worker launch (ALWAYS)

A worker must be launched so it inherits **none of the orchestrator's** plan,
chat, or skill context, otherwise it can read the whole plan and try to run
other tasks. For every per-task worker:

- **`context: "fresh"`** — NOT a fork of the orchestrator session.
- **Scoped, explicit prompt** that (1) names ONLY its single task file,
  (2) forbids reading `index.md` or sibling `T*.md`, (3) forbids editing
  `index.md` ("the orchestrator owns it"), (4) forbids touching anything outside
  its File scope, (5) says "run your exact Validation command, report PASS/FAIL,
  then STOP — do not start other tasks."
- **`turnBudget`** cap (generous but finite) so a loop aborts instead of drifting.
- **Acceptance evidence** requiring `changed-files` scope (flags out-of-scope writes).
- Pin **CWD to the repo root** and pass the platform-env note; use absolute
  forward-slash paths for the task file (workers may start in a different CWD).

Sketch:

```text
runs.run('T<ID>', {
  agent: 'worker',
  model: '<resolved model>:<thinking?>',
  context: 'fresh',
  turnBudget: { maxTurns: <cap> },
  acceptance: { level: 'checked', evidence: ['changed-files','commands-run','no-staged-files','residual-risks'] },
  task: `Environment: <platform/shell> — pin CWD to <abs repo root>, use <py -3|python3>. `
        `Execute ONLY task T<ID> from /abs/path/plan/<date>-<slug>/T<ID>.md. `
        `Do NOT read plan/.../index.md or any sibling T*.md. Do NOT edit index.md (orchestrator owns it). `
        `Touch ONLY the File scope listed in T<ID>.md. Run its exact Validation command and report PASS/FAIL. Then STOP.`
})
```

- Append a `:level` (e.g. `:high`) only where your provider supports the
  thinking-level suffix; otherwise omit it.
- On **validation failure**, propose an upgrade: raise to the next tier's model
  from the plan's Models table, or the `fallback` for that difficulty. Present it
  and wait for approval. Do not auto-upgrade.

## Reference: price/tier defaults (mirror of plan-task model-cache)

| Difficulty | Selected | Fallback (proposed on failure) |
|-----------|----------|--------------------------------|
| 1 | `openrouter/free` | `openai/gpt-5-nano` |
| 2 | `openrouter/free` | `deepseek/deepseek-v4-flash` |
| 3 | `openrouter/free` | `deepseek/deepseek-v4-pro` |
| 4 | `anthropic/claude-sonnet-4.5` | `anthropic/claude-opus-4.5` |
| 5 | `anthropic/claude-sonnet-4.5` | `anthropic/claude-opus-4.5` |

> Difficulty-3 defaults to `openrouter/free` because well-scoped Multi-file config
> tasks are reliably handled at the free tier; escalate to the fallback on
> validation failure rather than paying up front. Use the plan's Models table as
> authoritative — these are only the defaults `plan-task` generates.

## Upgrade proposal shape (on failure)

```text
Task T2 validation FAILED (exit 1):
<validator output>
Proposed upgrade: openrouter/free -> deepseek/deepseek-v4-flash ($0.088/M)
[difficulty 2 fallback]. Approve to retry, edit the model, or stop.
```
