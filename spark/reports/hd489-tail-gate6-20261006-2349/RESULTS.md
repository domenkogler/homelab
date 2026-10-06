# HD-489 tail — gate 6 (accuracy) on the live 20 GB `fast` shape

**Run:** 2026-10-06 23:49Z, 108 s window. **Engine under test:** spark, live profile `fast`
(`--kv-cache-memory-bytes 20000000000`, `--max-num-seqs 8`, `--max-model-len 262144`,
`--reasoning-parser qwen3`, MTP speculative decoding ON, container started 2026-10-06T11:49:52Z,
`RestartCount=0`). **Driver:** headless `run-gate6.sh` on spark (`spark/bench/accuracy-gate.sh`,
10 fixed prompts, `temperature 0`, `max_tokens 1024`).

## Seat (rule 0, stated before any number)

The driving session's own model **is** `spark/qwen3.8-flash-next`, and the battery ran while that
session was attached. **No tok/s, TTFT or ITL is claimed anywhere in this file** — rule 0 is
satisfied by not producing a timed number. What IS produced is a *quality* score, and the
contamination that matters for it is pool pressure, which the evidence says was absent:
`vllm:num_preemptions_total` delta **+0**, zero `preempt|out of memory` lines in the engine log,
`usable` 12.84 → 12.91 GiB across the window (`MemAvailable − CmaFree`, both ends in `raw/`).

## Result: 7/10 answered, 6 of those agree with the B1 baseline, 1 budget-starved

| item | vs B1 (`difflib` ratio) | finish_reason | completion / reasoning tokens | verdict |
|---|---|---|---|---|
| json-extract | 1.00 | stop | 191 / 150 | same answer |
| logic | 1.00 | stop | 99 / 63 | same answer |
| state-tracker | 1.00 | stop | 93 / 80 | same answer |
| html-game | 1.00 | length → EMPTY | 1024 / 1024 | **baseline is EMPTY too** — not a regression |
| tool-call | 1.00 | stop → EMPTY | 183 / 152 | **baseline is EMPTY too** (no `tools` in the request) |
| summarize | 0.79 | stop | 126 / 80 | same content, reworded |
| long-reasoning | 0.53 | stop | 277 / 100 | same proof, terser |
| math-multistep | 0.55 | stop | 190 / 108 | same answer, different wording |
| code-review | 0.29 | stop | 469 / 287 | same defect list, expanded |
| **code-fib** | **0.01** | **length** | **1024 / 1024** | **EMPTY where B1 had 314 c — budget, not ability** |

**Gate 6 verdict: PASS with one named exception.** No item shows a degraded *answer*; the single
failure (`code-fib`) is `finish_reason=length` with **all 1024 completion tokens spent as
`reasoning_tokens`** — the answer never got to print. That is the exact confound the gate doc says
produced the 91-vs-98-vs-99 spread: the battery's `max_tokens: 1024` was sized for a non-reasoning
engine, and `fast` runs with the `qwen3` reasoning parser on.

**Recommendation (NOT applied — it would silently change the comparison basis of a fixed battery):**
raise the battery to `max_tokens ≥ 4096`, or score with thinking off via `chat_template_kwargs`, and
say which in the row. The engine reports `completion_tokens_details.reasoning_tokens` per request, so
the confound is now measurable instead of folklore.

## Confounds recorded with the score (the requirement, not prose)

engine `vllm-qwen-spark` on profile `fast` · model `/model` (ar-hybrid AR + PLE mmap, the HD-489 winner)
· template/thinking: `--reasoning-parser qwen3`, thinking **ON**, `temperature 0` · budget: `max_tokens 1024`
· speculative: MTP ON — this window drew **4181 accepted / 6660 drafted tokens across 2220 drafts
(62.8 % token acceptance, 1.88 accepted per draft)** · prefix cache: +1,531,200 hits / +1,541,802 queries.

## Clock trace — recorded, and explicitly NOT the HD-469 baseline

`raw/clocks-gate6.txt`, 108 1-second samples across the window: **`clocks.sm` 2398 / 2405 / 2405
(min / p50 / max MHz)**, power 15–55 W (p50 31 W), max 69 °C. It sits in the capped band (~2411 named,
2496–2515 pre-cap) — but the GPU was **lightly loaded** at best, and the gate doc is right that an
idle-ish read proves nothing about the regime. **HD-469's under-cap baseline under load is still owed**
and must come from a non-spark-served session.

## Files

`run-gate6.sh` (the driver, verbatim) · `raw/seat.txt` (engine argv + `/health`) ·
`raw/accuracy/fast-20gb-20261006-2349/*.{json,out}` (the 10 raw responses) · `raw/battery.log` ·
`raw/clocks-gate6.txt` · `raw/meminfo-{before,after}.txt` · `raw/metrics-{before,after}.txt` ·
`raw/engine-warn-count.txt` · `raw/rc.txt` (rc=0).
