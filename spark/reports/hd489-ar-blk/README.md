# HD-489 — arm `ar-blk` (tier 2: ar-mmap + in-checkpoint MTP-3 block rejection) — **current winner**

Measured 2026-10-03 09:40–09:52 UTC on spark. **The strongest arm measured in the funnel to
date.**

**Profile**: `ar-blk` — same AR AutoRound-hybrid weights + FP8 PLE disk-mmap as `ar-mmap`
(quantization auto_gptq, ple_mmap FAST_PATH, enforce_eager boot fix), **one delta**:
speculative decode **ON** — `spec_config: {method: mtp, num_speculative_tokens: 3,
rejection_sample_method: block, draft_sample_method: probabilistic}`. Boot confirmed:
`Resolved architecture: Qwen3_8FlashNextMTP` (the in-checkpoint MTP head initialised), `fp8
hybrid: drafter-experts arm armed` (drafter runs fp8).

## Fidelity (PASSED)

- Accuracy battery **0 failures, 10/10 outputs**.
- Slovenian accepted-length: 1373-token prompt accepted, coherent Slovenian content (correct
  diacritics), `finish: stop`.

## Speed legs

| leg | seed | window (UTC) | dur | dec/stream | TTFT p50 | ITL p50 | MTP | cold_ok | ok | preempt |
|-----|------|--------------|-----|-----------|----------|---------|-----|---------|----|---------|
| C2  decode | 42 | 09:40:00–09:42:12 | 132s | 35.1 | 799 ms | 67.1 ms | 49.6% | no* | 8/8 | 0 |
| C1  prefill | 43 | 09:43:06–09:47:17 | 250s | 17.4 | 17056 ms | 65.6 ms | 54.6% | yes | 8/8 | 0 |
| C2L long   | 44 | 09:47:21–09:52:45 | 324s | **39.7** | 716 ms | 64.6 ms | 54.7% | **yes** | 12/12 | 0 |

\* C2 ran 132s (<180s) because decode is so fast — `cold_ok=no`; the C2L leg supplies the
≥180s corroborated window (`cold_ok=yes`, 324s).

## Reading — ~2× decode over everything else

| metric | u2-blk (tier-1 best) | ar-mmap (t2 base) | **ar-blk** | delta vs u2 |
|--------|----------------------|-------------------|------------|-------------|
| C2L dec/stream | 23.6 | 20.4 | **39.7** | **+68%** |
| C2L TTFT p50 | 2481 ms | 635 ms | **716 ms** | −71% |
| C2L ITL p50 | 96.1 ms | 49.8 ms | 64.6 ms | −33% |
| C1 dec/stream | 7.2 | 12.6 | **17.4** | **+142%** |

The **AR AutoRound W4A16-hybrid weights + in-checkpoint MTP-3 block rejection** together
deliver the funnel's best decode: **39.7 tok/s corroborated (C2L, cold_ok=yes)** vs the best
tier-1 (u2-blk 23.6) and vs tier-2 baseline (ar-mmap 20.4, spec OFF). The drafter (fp8-experts
arm, the in-checkpoint MTP head) roughly **doubles decode output** on these weights while
keeping TTFT ~0.7s. MTP acceptance 49-55% is healthy (vs 46-49% on AWQ).

## Verdict

**ar-blk is the funnel's current winner.** The delta "in-checkpoint MTP-3 with block rejection
on the AR-hybrid weights" is the single biggest measurable win. The remaining arms (ar-dv adds
the 65,536-id draft vocabulary; v16b* add the T80 drafter + piecewise graphs) must beat 39.7
tok/s C2L-corroborated.

## Evidence

- `raw/atrest-*`, `raw/result-*` (this dir)
- CSV rows: `spark/bench/results-v2.csv` (`t2-arblk,20261003-094000/094306/094721`)
- VM cross-check: same monitoring-not-converged caveat.