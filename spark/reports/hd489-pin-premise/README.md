# HD-489 — the pin arms' premise, checked against the engine's own counters

**Why this exists.** `u4-pin` and `v16b-pin` are the only two arms in the funnel whose whole
justification is a memory-budget finding rather than a speed claim: the catalogue says the
never-evict patch "is the direct answer to the 0 %-prefix-hit re-prefill we measure on every long
session", citing [../../../docs/hardware-spark.md](../../../docs/hardware-spark.md) §Unified-memory budget —
"a ~162k-token session = 56 % of the (8.2 GiB-era) KV pool, and at prefix hit **0 %** every turn
re-prefills the whole window (17,008 tok/s)". Step 3 of the lane asks the owner to author a
`never_evict_prompt` substring and a pool fraction. Before spending an arm — and 25 % of the pool
permanently — on that premise, the premise got one query pass.

**Rule 0 status.** Counter reads only. No timed number is produced here, and none of these numbers
is a leg measurement: the window includes this analyst's own agent traffic (which is precisely the
traffic shape the premise is about, but it means these are aggregate reads of live production, not a
controlled run). [../../llm-profiles/README.md](../../llm-profiles/README.md) Rule 0 permits exactly this
class of read from any session.

## What the engine says (2026-10-02, `job="vllm"`, `instance=spark.kogler.si`)

| Read | Value | Note |
|---|---|---|
| prefix-cache hit ratio | 94.8 % lifetime · 95.3 % 7 d · **96.3 % 24 h** · 91.3 % 1 h | hits/queries, token-weighted |
| cached share of prompt tokens | **96.3 %** (24 h) | `prompt_tokens_cached / prompt_tokens` — the same story from the other side |
| **recomputed** share of prompt tokens | **3.70 % (24 h)** · 4.57 % (7 d) | `request_prefill_kv_computed_tokens_sum / prompt_tokens_total` — the actual re-prefill bill |
| prompt tokens per request | p50 **137,821** · p95 **200,000** | real sessions really are ~140 k tokens; p95 sits on the top finite bucket, so it is a floor, not a value |
| recomputed tokens per request | p50 **3,731** · p95 **11,300** | this is the entire headroom a prompt-KV pin can buy |
| preemptions | **5** over an uptime of 276,325 s (3.19 d) | the doc's loop needs eviction pressure; there is almost none |
| MTP acceptance | 1.82 accepted tokens per draft | gate 8's counter, already in the store |
| decode throughput, two independent paths | `rate(generation_tokens_total[1m])` = 26.3 tok/s vs TPOT p50 0.0375 s ⇒ 26.7 tok/s | different cadences, different code paths, 1.5 % apart — the store and the histograms corroborate each other |
| one 12-minute window | 9 completed requests, 1,491,679 prompt tokens, 70,393 recomputed (4.7 %), peak concurrency 1 | what a real quiet period looks like |

## Reading of it

1. **The 0 % regime is not current, and the doc says so.** Its own qualifier is "the **(8.2 GiB-era)**
   KV pool". The certified `reasoning` pool is 16 GB — 515,679 slots by the gate's own projection —
   so a 162 k-token session is no longer 56 % of the pool, and the named loop (own prefix blocks
   evicted → 0 % hit → full re-prefill) requires eviction, which the preemption counter says is not
   happening: five in 3.2 days.
2. **The ceiling on these two arms is small.** Median 3.7 k and p95 11.3 k recomputed tokens per
   request, at the doc's own 17,008 tok/s re-prefill rate, is **≈ 0.22 s median and ≈ 0.66 s p95 of
   TTFT per request** — against a measured TTFT p95 of ~29 s in the same store. A ~2 % TTFT effect on
   the tail is not what this funnel ships an arm for.
3. **The cost side is not small, and it is the real decision.** The arms inherit
   `never_evict_max_fraction: "0.25"`, i.e. ~129 k tokens (≈ 4 GB of a 16 GB pool) pinned permanently
   — which is 25 % of the pool that the *other* 96 % of cached tokens no longer get, on a box whose
   whole documented failure mode is allocator/occupancy growth. The measurement that decides these
   arms is therefore not "does the pin help when nothing is contending" (it cannot, there is nothing
   to save) but **`recomp_tok_delta` against `preempt_delta` under raised occupancy**.
4. **Which changes the fraction the owner should author.** If the target is the residual recompute —
   p95 ≈ 11.3 k tokens — then a quarter of the pool is ~10× more pinning than the problem needs.
   **0.03 (≈ 15.5 k tokens, ≈ 480 MB) covers the p95 with headroom** and leaves 0.22 of the pool in
   play. Inheriting 0.25 is a default, not a decision.
5. **Keep the arms, demote the premise.** They are cheap to run (gated only on the substring), and
   under the `seqs=8` / piecewise arms — the ones that *raise* occupancy — the eviction loop the doc
   describes may genuinely return. Run them **after** tier 1 has booted an arm with `max_num_seqs=8`,
   and judge them on `recomp_tok_delta` + `preempt_delta`, not on the hit ratio, which is already at
   96 % and cannot show a win of this size.

## One trap found while doing this

`model_name` is **not** a stable join key on this box: the archived bench captures under
`spark/bench/raw/` (2026-09-14) carry `model_name="/model"`, while the live series carry
`model_name="spark/qwen3.8-flash-next"`. A dashboard or query keyed on `model_name` either spans
two identities or silently returns nothing. **Query on `job="vllm", instance="spark.kogler.si"`** —
which is also the honest key for the funnel, since all 16 arms will serve the same served-model-name
by design.

## Reproduce it (the exact query set)

Evaluate over any window; `{job="vllm",instance="spark.kogler.si"}` is implied below and omitted for
width. Same result path as `spark/bench/vm-window.sh`, which does the per-leg version.

```promql
# hit ratios
sum(increase(vllm:prefix_cache_hits_total[24h])) / sum(increase(vllm:prefix_cache_queries_total[24h]))
sum(increase(vllm:prompt_tokens_cached_total[24h])) / sum(increase(vllm:prompt_tokens_total[24h]))

# THE number for the pin arms: what actually gets re-computed
sum(increase(vllm:request_prefill_kv_computed_tokens_sum[24h])) / sum(increase(vllm:prompt_tokens_total[24h]))
histogram_quantile(0.95, sum(rate(vllm:request_prefill_kv_computed_tokens_bucket[6h])) by (le))
histogram_quantile(0.95, sum(rate(vllm:request_prompt_tokens_bucket[6h])) by (le))

# is there eviction pressure? (the premise's own mechanism)
sum(vllm:num_preemptions_total)
time() - process_start_time_seconds{job="vllm"}

# cross-check the speed path two ways
sum(rate(vllm:generation_tokens_total[1m]))
histogram_quantile(0.50, sum(rate(vllm:request_time_per_output_token_seconds_bucket[15m])) by (le))
```

Query them through the VM API the same way the harness does: `GET /api/v1/query` with basic auth
from the 1Password item `victoria-metrics_api` (see `spark/bench/vm-window.sh` for the
0600-curl-config pattern that keeps the secret out of argv).
