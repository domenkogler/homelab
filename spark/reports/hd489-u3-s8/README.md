# HD-489 — arm `u3-s8` (tier 1: u2-blk + 8 seqs + piecewise CUDA graphs)

Measured 2026-10-02 22:28–22:52 UTC on spark. Same image/weights as u1/u2 (patched lineage,
AWQ + INT4 PLE), **two deltas vs u2-blk**: `max_num_seqs: 8` and `cudagraph_piecewise: true`
(verified in boot: `max_num_seqs': 8`, `cudagraph_mode': <CUDAGraphMode.PIECEWISE>`).
Block rejection kept from u2-blk.

## Fidelity (PASSED)

- Accuracy battery **0 failures, 10/10 outputs** (same probes as u1/u2).
- KV pool: `GPU KV cache size: 515,786 tokens, 1.97x` (unchanged — pool is `--kv-cache-memory-bytes`
  driven, seqs doesn't change it).

## Speed legs (all clean)

| leg | seed | window (UTC) | dur | ttft_p50 | ttft_p99 | dec/stream | MTP accept | ok | preempt |
|-----|------|--------------|-----|----------|----------|------------|------------|----|---------|
| C2  decode | 42 | 22:28:12–22:31:57 | 224s | 3981 ms | 5071 ms | 19.6 | 49.1% | 8/8 | 0 |
| C1  prefill | 43 | 22:32:36–22:42:47 | 611s | 54011 ms | 62266 ms | 6.9 | 52.4% | 8/8 | 0 |
| C2L long   | 44 | 22:42:48–22:52:07 | 557s | 2415 ms | 2805 ms | 22.7 | 46.7% | 12/12 | 0 |

## Reading — seqs=8 strands ~40 GB, buys no decode

| metric | u2-blk (seqs=4) | u3-s8 (seqs=8) | delta |
|--------|------------------|-----------------|-------|
| C2 dec/stream | 20.2 | 19.6 | **−3%** |
| C2L dec/stream | 23.6 | 22.7 | **−4%** |
| C2 MTP accept | 46.3% | 49.1% | +2.8pp |
| **engine pid MiB at rest** | 276,855 | **317,638** | **+40,783 MiB ≈ +40 GB** |

**The §6.2 stranding rule fires**: seqs=8 raises the engine's at-rest residency by ~40 GB on
the single 121.6 GiB pool vs seqs=4, while decode neither improves (slightly worse) nor hurts
TTFT meaningfully. The MTP-acceptance edge (49% vs 46%) is not worth 40 GB of pool.

**Verdict for the funnel: seqs=8 is a memory-heavy no-win on the AWQ lane.** u2-blk's seqs=4
is the better batch shape here. Tier-3 `v16b` uses seqs=8 by upstream recipe — this arm
prices that choice (and it is where the never-evict/pin arms' contention would show, per the
pin-premise report's "run them after tier 1 has booted an arm with max_num_seqs=8").

## Evidence

- `raw/atrest-*` (incl. the +40 GB seqs delta), `raw/result-*`
- CSV rows: `spark/bench/results-v2.csv` (`t1-u3,20261002-222812/223236/224248`)
- VM cross-check: same caveat (monitoring not converged; harness deltas authoritative).