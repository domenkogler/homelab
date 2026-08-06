# subagent-routing

How a plan task's `difficulty` and `Model` become a pi-subagents execution.

## Mapping

| Difficulty | Worker role | `thinking` | Notes |
|-----------|-------------|-----------|-------|
| 1-2 | `worker` | low/medium | mechanical, well-specified |
| 3 | `worker` | medium | multi-file, needs careful editing |
| 4 | `worker` (or `delegate` + `reviewer`) | high | demanding; add a review pass if the human wants |
| 5 | `planner`-refined worker + `reviewer` | high | ambiguous/high-risk; fanout review recommended |

## Model argument

Every launch passes the task's **resolved model** from the index Models table as
a per-run override (strongest precedence; never mutates global settings), and
points the worker at the task FILE so it reads the exact scope/values itself:

```text
/run worker[model=anthropic/claude-sonnet-4.5:high] "Execute task T<ID>. Read plan/<date>-<slug>/T<ID>.md; apply its exact File scope and values; then run its exact Validation command and report PASS/FAIL."
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
| 3 | `deepseek/deepseek-v4-pro` | `openai/gpt-5.2` |
| 4 | `anthropic/claude-sonnet-4.5` | `anthropic/claude-opus-4.5` |
| 5 | `anthropic/claude-sonnet-4.5` | `anthropic/claude-opus-4.5` |

Use the plan's Models table as authoritative — these are only the defaults
`plan-task` generates.

## Upgrade proposal shape (on failure)

```text
Task T2 validation FAILED (exit 1):
<validator output>
Proposed upgrade: openrouter/free -> deepseek/deepseek-v4-flash ($0.088/M)
[difficulty 2 fallback]. Approve to retry, edit the model, or stop.
```
