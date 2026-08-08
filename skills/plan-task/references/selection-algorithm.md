# selection-algorithm

Two inputs drive task selection: **difficulty (1-5)** and **model (by price)**.

## Difficulty rubric

| Score | Meaning | Model tier | Checkpoint |
|-------|---------|-----------|------------|
| 1 | Trivial / mechanical, single file, no research, low risk | T1 | no |
| 2 | Straightforward, small batch, well-specified | T1-T2 | no |
| 3 | Moderate, multi-file, some judgment, needs validation | T3 | no |
| 4 | Demanding, cross-cutting, design + verification | T4 | **yes** |
| 5 | Ambiguous / high-risk / needs review fanout + human gate | T4 | **yes** |

## Model selection (price-driven, cheap first)

Per-model comparison uses **price_in** (USD / 1M prompt tokens); price_out is
shown alongside for cost awareness.

### Allowed tier set per difficulty

```
d=1 -> {T1}
d=2 -> {T1, T2, T3}        # T3 allowed only if cheaper than T2 (rule A)
d=3 -> {T3}                # minimum tier T3
d=4 -> {T4}                # minimum tier T4
d=5 -> {T4}                # minimum tier T4
```

### Selection rules (in priority order)

1. **Never-T4-for-1-2:** difficulty 1-2 never selects a T4 model, even if it is
   the global cheapest (rule B exception: T4 may be used for everything else).
2. **Cheapest-first:** within the allowed set (all models whose tier >= the
   difficulty's minimum tier), pick the model with the **lowest price_in**.
3. **Rule A:** for d=2, if a T3 model is *cheaper* than the cheapest T2 model,
   the T3 model is eligible and wins on price (it is used first).
4. **Rule B:** if a T4 model is the *global cheapest*, it is selected for every
   difficulty **except 1-2**.
5. **Free default for easy/well-scoped tasks:** d=1, d=2, d=3 default to
   `openrouter/free` (cost $0) — well-scoped multi-file config/implementation
   tasks are reliably handled at the free tier (verified). If execution later
   fails to meet the goal, `run-task` proposes an upgrade to the `fallback`
   model (see cache `difficulty_defaults`).

### Defaults (from a freshly refreshed cache)

| Difficulty | Selected | Fallback (proposed on failure) |
|-----------|----------|--------------------------------|
| 1 | `openrouter/free` ($0) | `openai/gpt-5-nano` ($0.05/M) |
| 2 | `openrouter/free` ($0) | `deepseek/deepseek-v4-flash` ($0.088/M) |
| 3 | `openrouter/free` ($0) | `deepseek/deepseek-v4-pro` ($0.435/M) |
| 4 | `anthropic/claude-sonnet-4.5` ($3.00/M) | `anthropic/claude-opus-4.5` ($5.00/M) |
| 5 | `anthropic/claude-sonnet-4.5` ($3.00/M) | `anthropic/claude-opus-4.5` ($5.00/M) |

### Worked examples (with a live-priced cache)

- If refresh shows `T3 deepseek-v4-pro` at $0.15 and `T2 deepseek-v4-flash` at
  $0.28: rule A makes the T3 model eligible for d=2 and it wins (cheaper).
- If refresh shows `T4 claude-opus-4.5` at $0.10 (global cheapest): rule B
  selects it for d=3,4,5; d=1,2 stay on `openrouter/free`.
- Every cache refresh **surfaces NEW OpenRouter candidates** and **price/tier
  changes** (see `scripts/refresh-model-cache.py --add / --add-new / --apply`);
  adopt what you approve, then plan-time selection re-derives the cheapest picks
  from the models list and re-presents them. The `tier_defaults`/
  `difficulty_defaults` in the cache remain curated human fallbacks and are NOT
  auto-rewritten.

All defaults and selections are **human-editable**; embed the final resolved
map in the plan's Models section.

## Capability fit (not just price)

Every cached model carries a `caps` flag string (modalities + tools/json/reasoning/
vision/audio). Price-first selection can pick a cheap model that a task cannot
use (e.g. a vision task vs a text-only default). So:
- Show the `caps` column in the cache table and in the plan's **Models** table
  and per-task `Capabilities` line.
- Flag a likely mismatch at the gate ("T3 needs vision; default is text-only") and
  propose the cheapest capable model instead.
- A capability veto is valid even when the cache is brand new — the table's age
  only tells you prices are current.
