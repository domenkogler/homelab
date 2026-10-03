# HD-489 tail — B2: concurrency on the winner (`ar-blk`)

Measured 2026-10-03 against the **live `ar-blk`** engine on spark
(`vllm-qwen-spark`, `RestartCount=0`, `OOMKilled=false`, `enforce_eager`,
`spec{mtp,3,block,probabilistic}`).

## Verdict

**PASS** — gate-4 concurrency is proven for `ar-blk` (the first `ar-*` arm with it).

| check | command (verbatim from the brief) | result |
|---|---|---|
| gate 3 | `spark-llm-probe.py … ctx 262144` | **PASS** — HTTP 200, prompt **258,863** (~98.8 % of window), 134.2 s |
| gate 4 | `spark-llm-probe.py … concurrent 4` | **PASS** — 4/4 HTTP 200, wall 2.7 s, lat min/med/max **2.6/2.6/2.7 s** (slowest ≈ solo, **no 3× blow-up**) |
| timed conc | `run-scenario.sh B2-conc C3` (8k/1k, conc 2) | **24.5 tok/s/stream**, 6/6 ok, ITL p50 80 ms, MTP 52.0 %, 0 preempts, 31 W |
| timed conc | `run-scenario.sh B2-conc2 C2L` at `C2L_CONC=2` | **31.8 tok/s/stream**, 12/12 ok, `cold_ok=yes` (208 s), MTP 56.4 %, 0 preempts, 0.14 Wh/1k |

## Reading

- **Gate 4 passes**: all 200s and slowest (2.7 s) ≤ 3× solo (solo C2L TTFT p50 ~0.7–0.9 s, and
  the concurrency leg's 2.7 s max is a prefill-bound tail, not a decode blow-up). The funnel
  previously had **every number at conc 1** — now `ar-blk` is proven up to 4 concurrent, and
  the conc-2 decode (24.5 C3 / 31.8 C2L) shows the expected per-stream cost of batching.
- `enforce_eager` was the suspected per-step-launch-overhead regime; at conc 2 the per-stream
  decode holds 24.5–31.8 tok/s with **zero preemptions**, so batching does not collapse it.
- The pool is 16 GB ≈ 1.97×; concurrent full-window sessions (2×262k) still need the pool
  arithmetic in the brief (B7), and the observed usable 22.7–23.5 GiB shows room.
- This closes the funnel's "gate 4 unproven for every ar-* arm" gap for the winner.

## Evidence

- `raw/probe-ctx262144.txt` · `raw/probe-concurrent4.txt` (probe legs, from the laptop via the
  loopback tunnel with the bearer from 1Password, `--token-env`)
- `raw/atrest-*B2-*` · `raw/result-*B2-*` · `raw/power-*B2-*` · `raw/benchlog-*B2-*`
- CSV rows on spark: `~/bench/results-v2.csv` (`B2-conc-C3` at 20261003-155028,
  `B2-conc2-C2L` at 20261003-155256)
- Runner: external seat (`agent:external`, Rule 0 clean — not spark-served)