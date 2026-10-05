# HD-489 — arm `u1-patch` (tier 1 isolation control)

Measured 2026-10-02 22:45–23:17 UTC on spark (DGX GB10, unified pool 121.62 GiB).
Engine: the **patched ultrafast lineage** (`sha256:4900c13edab97dd8deb5f429456ae72e3c093cbacb3381f98feb10788f379d92`,
built 2026-10-02 from the pinned upstream commit `0c391a3e` on the certified base digest `fc120ece…`),
serving `spark/qwen3.8-flash-next`.

**What this arm is** — the funnel's tier-1 isolation control: identical weights (AWQ `Qwen3.8-Flash-Next-AWQ`)
and argv family to the certified `reasoning` profile, but on the **patched vLLM lineage**. Its only claim:
"the patch stack, alone, changes X". It is **not** a candidate to win; it prices the patch.

## Fidelity gates (PASSED before any timing)

- **Accuracy battery** (`accuracy-gate.sh hd489-u1-patch`): 10/10 prompts returned HTTP 200,
  9/10 meaningful outputs, diffs vs the B1 baseline are cosmetic/equivalent
  (code-review: same fix, more detail; json-extract: identical JSON inline vs multi-line; math: same
  reasoning, fuller). **No visible degradation vs B1.**
- **Tool-call item**: `EMPTY` — probe limitation, not engine failure: the engine has
  `--enable-auto-tool-choice` (boot log: `"auto" tool choice has been enabled`) but the probe sends no
  `tools` schema, so the model returns no tool call. Flagged honestly; not counted as a pass.
- **Slovenian accepted-length** (probe, 3017-token Slovenian paragraph): engine accepted the full prompt
  no truncation, produced a coherent Slovenian response with correct diacritics (`Š`,`č`,`ž`) — `finish:
  length` on the 256-token cap. **Slovenian accepted-length gate PASSED.**
- Engine boot: `GPU KV cache size: 515,786 tokens, Maximum concurrency for 262,144 tokens per request:
  1.97x` — the 16 GB pool holds the full window 1.97×, matching the gate's projection (515,679).

## Speed legs (all recorded clean)

All legs: `cold_ok=yes` (≥180 s → VM corroboration admissible in principle), `req_ok_delta=N`
(exclusivity proof — the window contained only our traffic), `preempt_delta=0`.

| leg | seed | window (UTC) | dur | ttft_p50 | itl_p50 | dec/stream | total_thr | ok | preempt |
|-----|------|--------------|-----|----------|---------|------------|-----------|----|---------|
| C2  decode | 42 | 20:51:59–20:56:05 | 244s | 2879 ms | 97.3 ms | 17.9 | 55.6 | 8/8 | 0 |
| C1  prefill | 43 | 20:56:14–21:07:16 | 660s | 57176 ms | 95.0 ms | 6.4 | 415.7 | 8/8 | 0 |
| C2L long   | 44 | 21:07:20–21:17:24 | 604s | 2448 ms | 97.0 ms | 20.9 | 42.9 | 12/12 | 0 |

Per-position MTP acceptance (C2): pos0 53.4%, pos1 28.0%, pos2 16.5% — overall 32.6%.
Power (C2): mean 26 W, 0.43 Wh/1k output tokens.
Memory at rest (C2): engine/all pid MiB = 175903/92975, usable 19.7 GiB.
Recomputed prompt tokens (C2): +8612 (prefix-cache miss on the 8k dataset prompts; pin arms' metric,
off for this non-pin arm).

## Reading

- **Decode 17.9 tok/s (C2) / 20.9 (C2L) per stream** on the patched build with AWQ weights.
  The certified `reasoning` baseline (same weights, base image) is the comparison — see the funnel
  table in `docs/spark-llm-profiles.md` / `docs/hardware-spark.md` §Bench + engine selection.
- 1.97× window is servable; zero preemptions at conc=1.
- The isolated-patch decode here is the number tier-2 `ar-*` and tier-3 `v16b` arms must beat.

## Evidence (this dir)

- `raw/atrest-*` — memory at rest per leg (engine/all pid MiB, usable GiB)
- `raw/result-*` — vLLM bench JSON per leg (quantiles, throughput, MTP acceptance)
- `raw/benchlog-*` — raw harness logs per leg (paths/scrubbed of credentials)
- CSV rows: `spark/bench/results-v2.csv` (rows `t1-u1,20261002-205159/205614/210720`)

**VM cross-check note**: `vm-window.sh` could not complete its VictoriaMetrics query from this runner
(VM endpoint not reachable: `?query=up` timed out). Per the HD-489 status-change brief, monitoring is
**not** converged on this lane's authority, so the harness-side `/metrics` deltas (recorded by
run-scenario off the engine directly) are the authoritative leg record; the VM witness side is pending
the monitoring converge.