# HD-489 — arm `u2-blk` (tier 1: u1-patch + block rejection sampling)

Measured 2026-10-02 21:51–22:14 UTC on spark. Same image/weights as `u1-patch`
(patched lineage `sha256:4900c13e…`, AWQ `Qwen3.8-Flash-Next-AWQ`, INT4 PLE overlay),
**one delta**: speculative-config `rejection_sample_method: block, draft_sample_method:
probabilistic` (vs u1's default). Verified in boot: `'speculative_config':
{'method': 'mtp', 'num_speculative_tokens': 3, 'rejection_sample_method': 'block',
'draft_sample_method': 'probabilistic'}`.

## Fidelity (PASSED)

- Accuracy battery 10/10 HTTP-200, outputs equivalent to B1/u1 (state-tracker, json-extract,
  long-reasoning correct). Block rejection did not degrade quality.
- Tool-call item `EMPTY` — same probe limitation as u1 (no `tools` schema sent).
- Slovenian accepted-length: same engine lineage; u1's Slovenian probe already proved
  full-prompt acceptance at 3k tokens; block rejection is a sampling-method change, not a
  length/capacity change — no expectation of regression, spot-checked by the battery's
  correct Slovenian-adjacent outputs.
- KV pool: `GPU KV cache size: 515,786 tokens, 1.97x` (same as u1).

## Speed legs (all clean)

| leg | seed | window (UTC) | dur | ttft_p50 | itl_p50 | dec/stream | MTP accept | ok | preempt |
|-----|------|--------------|-----|----------|---------|------------|------------|----|---------|
| C2  decode | 42 | 21:51:29–21:55:08 | 218s | 3645 ms | 101.3 ms | 20.2 | 46.3% | 8/8 | 0 |
| C1  prefill | 43 | 21:55:13–22:05:05 | 591s | 50673 ms | 96.1 ms | 7.2 | 49.4% | 8/8 | 0 |
| C2L long   | 44 | 22:05:09–22:14:06 | 537s | 2481 ms | 96.1 ms | 23.6 | 47.1% | 12/12 | 0 |

Power (C2): 25 W, 0.37 Wh/1k. Memory at rest (C2): engine/all pid MiB 0/92599, usable 20.3 GiB.

## Reading — block rejection is a real decode win on the AWQ lane

vs u1-patch (identical except the rejection method):

| metric | u1-patch | u2-blk | delta |
|--------|----------|--------|-------|
| C2 dec/stream | 17.9 | 20.2 | **+13%** |
| C2L dec/stream | 20.9 | 23.6 | **+13%** |
| C2 MTP accept | 32.6% | 46.3% | **+13.7pp** |
| C2L MTP accept | 38.5% | 47.1% | **+8.6pp** |

Direction matches upstream's claim (block rejection is what they say lets the drafter not
bias output, and it raises acceptance). This is the strongest tier-1 signal so far; tier-3
`v16b*` and the `ar-*` weight arms must beat it.

## Evidence

- `raw/atrest-*`, `raw/result-*` (this dir)
- CSV rows: `spark/bench/results-v2.csv` (`t1-u2,20261002-215129/215512/220509`)
- VM cross-check: same caveat as u1 (VM endpoint unreachable from runner; harness-side
  deltas authoritative until monitoring converges).