# HD-489 — arm `ar-dv` (tier 2: ar-blk + the 65,536-id draft-vocabulary slice)

Measured 2026-10-03 10:29–10:42 UTC on spark. **A slight regression vs ar-blk — the
draft-vocab slice does not help.**

**Profile**: `ar-dv` — identical to `ar-blk` (AR AutoRound-hybrid + FP8 PLE disk-mmap,
in-checkpoint MTP-3 block rejection, enforce_eager boot fix), **one delta**: the
`65,536-id draft-vocabulary slice` (the vendored `draft-vocab-ids-K65536.txt`, 389 KB, 65,536
lines — staged this session after fixing a stale dir at the mount target; `mtp draft vocab:
hooks installed` confirmed in boot).

## Fidelity (PASSED)

- Accuracy battery **0 failures, 10/10 outputs**.
- Boot: `mtp draft vocab hooks installed`, KV pool `515,786 tokens / 1.97x`, RestartCount 0.

## Speed legs

| leg | seed | window (UTC) | dur | dec/stream | TTFT p50 | ITL p50 | MTP | cold_ok | ok | preempt |
|-----|------|--------------|-----|-----------|----------|---------|-----|---------|----|---------|
| C2  decode | 42 | 10:29:19–10:31:43 | 143s | 31.8 | 769 ms | 57.1 ms | 30.9% | no* | 8/8 | 0 |
| C1  prefill | 43 | 10:31:49–10:36:33 | 285s | 15.1 | 16719 ms | 57.4 ms | 23.3% | yes | 8/8 | 0 |
| C2L long   | 44 | 10:36:39–10:42:37 | 357s | **35.8** | 707 ms | 57.1 ms | 36.8% | **yes** | 12/12 | 0 |

\* C2 <180s (fast), cold_ok=no; C2L corroborates.

## Reading — the draft vocab costs acceptance and decode

| metric | ar-blk | **ar-dv** | delta |
|--------|--------|-----------|-------|
| C2L dec/stream | 39.7 | 35.8 | **−10%** |
| C2L MTP accept | 54.7% | 36.8% | **−18pp** |
| C2 dec/stream | 35.1 | 31.8 | −9% |
| C2L ITL p50 | 64.6 ms | 57.1 ms | −12% (only win) |

The 65,536-id draft vocabulary **lowers per-position MTP acceptance** (54.7→36.8%) and decode
(39.7→35.8 tok/s) vs ar-blk's in-checkpoint draft. The larger draft space samples more tokens
the target rejects, eating throughput. The only improvement is a modest ITL drop (57 vs 65 ms).

## Verdict

**ar-dv loses to ar-blk.** The 65,536-id draft-vocabulary slice is a net negative on these
weights. **ar-blk (39.7 tok/s C2L-corroborated) remains the tier-2 / overall winner.** ar-dv is
recorded for the funnel as "draft-vocab slice hurts" — the v16b* tier-3 arms (which also carry
the T80 drafter + draft vocab) should expect the same drag unless the T80 drafter changes the
math.

## Evidence

- `raw/atrest-*`, `raw/result-*` (this dir)
- CSV rows: `spark/bench/results-v2.csv` (`t2-ardv,20261003-102919/103149/103639`)
- VM cross-check: same monitoring-not-converged caveat.