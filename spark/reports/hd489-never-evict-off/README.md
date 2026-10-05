# HD-489 — the never-evict prompt pin, measured on live sessions and rejected

**Why this exists.** `spark/reports/hd489-pin-premise/README.md` established that the pin's premise
(a ~0 % prefix-hit re-prefill on every long session) belonged to the 8.2 GiB pool era, and left the
value of the mechanism itself unmeasured: `u4-pin`/`v16b-pin` benches never engage a substring pin,
because a bench prompt contains no operator instructions. The engine ships its own instrumentation
for exactly this question, so the question got answered with counters instead of another synthetic
leg. Outcome: **the flag is off for every profile** —
[../../../docs/services-ai-rejected.md](../../../docs/services-ai-rejected.md) carries the decision
row, [../../../docs/spark-llm-profiles.md](../../../docs/spark-llm-profiles.md) §Never-evict prompt pin
carries the rule.

**Rule 0 status.** Counter reads and read-only image greps only. No timed number is produced here.
Window: the engine boot at **2026-10-04 22:16:56 UTC** to **2026-10-05 ~07:30 UTC** (profile `fast`,
25 GB pool, `max_num_seqs 8`, one interactive pi session as the traffic).

## The numbers

| signal | source | value |
|---|---|---|
| `[never-evict] holding N blocks … % of the KV pool` | `docker logs vllm-qwen-spark` | **never printed** — `log_never_evict_pin()` (`v1/core/sched/scheduler.py:2528`) returns early when `reserved == 0`, so the pin reserved **0 blocks** for the whole window |
| `[never-evict] armed: 559-token marker, pin capped at 142 blocks (25% of 569)` | same, once at 22:28:17 UTC | boot-time only: it proves the marker tokenised and the cap computed. **It is not match evidence** — matching calls `_arm_never_evict_pin()` (`scheduler.py:2470`), whose only log is the `holding` line above |
| `vllm:num_preemptions_total` | `/metrics` | **0** |
| `vllm:prompt_tokens_by_source_total{source="local_cache_hit"}` | `/metrics` | 3,136,000 |
| `vllm:prompt_tokens_by_source_total{source="local_compute"}` | `/metrics` | 160,231 → **4.9 % recomputed**, 95.1 % cached |
| pre-pin baseline, same metric | `spark/reports/hd489-pin-premise/README.md` | **3.70 % (24 h) · 4.57 % (7 d)** — the number did not move when the pin arrived |
| client-side | `~/.pi/agent/AGENTS.md` (WSL) → absent; `PI_PROVIDER=spark` | the needle is the pi global-instructions text and the serving client loads no `AGENTS.md`, so **no request in the window carried it** |

Attribution check that keeps this honest: the counters reset at boot, and the overnight MMLU run
ended 2026-10-04 21:36 UTC, i.e. 40 min **before** this process started — so the 3.3 M prompt tokens
are the interactive session, not the bench. The session's own accounting agrees: 48 turns,
3,754,350 prompt tokens, largest turn 155,903, 05:39:06Z → 07:30:44Z.

## Why the mechanism was never going to pay here

* The pool, not the pin, is what keeps a long session's prefix resident: 25 GB = 806,269 token
  slots = **3.08 × the 262,144 window**. With 0 preemptions there is no eviction for a pin to resist.
* The pin is single-slot: `_arm_never_evict_pin` — *"Pin the marked prompt's prefix, **replacing
  whatever was pinned before**"*. Concurrent sessions overwrite each other's pin, which is the
  normal shape of this box (lanes, harnesses, subagents).
* Pinned blocks leave `get_num_free_blocks()`, and that number drives admission control — so a pin
  is a subsidy to the one client whose prompt matches, paid by every other stream sharing the GPU.
* Matching is a **token subsequence**: `tokenizer.encode(marker, add_special_tokens=False)` minus the
  first and last token, then `_contains_subseq(prompt_token_ids, needle)`. All-or-nothing: one
  changed character anywhere in the marker stops the whole pin, silently, while the boot log still
  prints `armed`. That is also why "generate the marker by concatenating several always-read files"
  was rejected as a design — and why those files are not contiguous in any prompt anyway (only the
  global instructions are in the system prompt; repo docs arrive as separate tool results).

## The image-lineage finding (what actually cost the boot)

The argument pair exists only in the patched lineage. Read from the images on the box:

```bash
# ultrafast (the served `fast` image) — declares the pair:
#   vllm/engine/arg_utils.py:748  never_evict_kv_cache_prompt_includes: str | None
#   vllm/config/cache.py:200,207  (+ compute_hash() includes both keys)
#   vllm/v1/core/block_pool.py    _acquire_pin()/set_pinned_hashes()/get_pin_stats()
docker run --rm --network none --entrypoint /bin/sh qwen38-flash-dgx:iter6d-20260910 \
  -lc 'grep -rn never_evict /usr/local/lib/python3.12/dist-packages/vllm | head'
# base (reasoning/graded image) — only a docstring hit in reload/sanitize.py:
docker run --rm --network none --entrypoint /bin/sh \
  vllm/vllm-openai:qwen38-flash-next@sha256:fc120ece0a38… \
  -lc 'grep -rn "never.evict" $V --include=*.py | head'   # vLLM 0.1.dev20073+g8e685d198
```

So the 2026-10-03 "ONE value aliased by every profile" change made `spark_llm_profile=reasoning`
render `--never-evict-kv-cache-*` into a build that has no such argument: `api_server` exits at
parse, Docker restart-loops the engine. Live cost, from the overnight run's own
evidence (`RESULTS.md` on branch `session/hd489-0803`, run id `20261004-0804`): **`restarts=105`**,
box restored to `fast` by the run's converge-back. The gate was green throughout — it checked that
the pin rendered, never which image would receive it. Hence
`spark_llm_never_evict_capable_images: [ultrafast]` plus a new assert in
`roles/spark-llm-profile`, a `pin-lineage` invariant + canary in `scripts/check_spark_llm_gate.py`,
and a render-time refusal in `scripts/spark-llm-render-matrix.py`.

## Pool arithmetic, so nobody quotes "25 % of the pool" as 6.25 GB of room

Boot log: `Setting attention block size to 1600 tokens to ensure that attention page size is >=
mamba page size` + `Padding mamba page size by 0.25%`; the pool is reported as **569 blocks** with
the cap at **142 blocks**, and `GPU KV cache size: 806,269 tokens` — so a block is ≈ 1,417 tokens
and 25 % ≈ **0.20 M tokens ≈ 0.77 × one 262k window**, not a byte figure. (The 1600-vs-1417
tokens/block discrepancy is the hybrid mamba page-size unification; flagged, not resolved.)

## Re-open test (two counters, no bench leg)

`prompt_tokens_by_source` recomputed share climbing past ~10 %, or `num_preemptions_total > 0`,
across matched windows of concurrent long sessions. Per CONVENTIONS §8.3, re-arming needs an
exception note; and the needle must be proven against a prompt a real session sends — never a
synthetic leg (§6: a test that cannot fail is not evidence).

## Reproduce

```bash
ssh spark "curl -s localhost:8000/metrics | grep -E '^vllm:(prompt_tokens_by_source|num_preemptions|prefix_cache)'"
ssh spark "docker logs vllm-qwen-spark 2>&1 | grep -i never-evict"
ssh spark "docker inspect vllm-qwen-spark --format '{{.State.StartedAt}} restarts={{.RestartCount}}'"
```
