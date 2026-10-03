# HD-489 — arm `v16b-pin` (tier 3: v16b-s4 + never-evict pin, fraction 0.03)

Measured 2026-10-03 12:31–12:34 UTC on spark. **The final arm of the funnel. The pin is
neutral on synthetic benches (as u4-pin found); the T80+draft-vocab recipe's low MTP carries
over.**

**Profile**: `v16b-pin` — identical to `v16b-s4` (T80 dense-MTP drafter + 65,536-id
draft-vocab + FP8 PLE mmap + enforce_eager + seqs=4) **one delta**: `--never-evict-kv-cache-prompt-includes
"# Global instructions (loaded at every session start by pi)"` +
`--never-evict-kv-cache-max-fraction 0.03` (owner-approved pin, verified in argv).

## Fidelity (PASSED)

- Accuracy battery **0 failures, 10/10 outputs**.
- Healthy, RestartCount 0, KV pool 515,786 / 1.97×.

## Speed leg (C2; the pin's metric is recomp/preempt, so C2 suffices)

| leg | seed | dec/stream | TTFT p50 | ITL p50 | MTP | recomp_tok_delta | preempt | cold_ok | ok |
|-----|------|-----------|----------|---------|-----|------------------|---------|---------|----|
| C2  decode | **45** | **29.1** | 705 ms | 52.1 ms | 19.3% | **+8608** | 0 | no | **8/8** |

A first C2 (seed 42) was **contaminated** — `ok_delta=-18/8` and negative recomp
(counter reset between snapshots; window invalid). Re-run (seed 45) clean: 8/8, preempts 0.

## Reading — pin neutral on synthetic benches, recipe's low MTP unchanged

- **`recomp_tok_delta +8608`, `prefix_hits +0`** — identical to every non-pin arm: the bench
  dataset prompts do not contain the pinned "Global instructions" substring, so the pin never
  engages in synthetic legs. Its benefit would only appear in real sessions whose
  project_context carries the substring (the premise's caveat, same as u4-pin).
- Decode 29.1 ≈ v16b-s4's 34.1 (slightly lower, within run variance; MTP 19.3% lowest of the
  recipe — the draft-vocab drag, plus the pin's 0.03 pool reservation).
- `preempt_delta 0` — nothing to protect, matching the premise report.

## Verdict

**v16b-pin confirms the tier-3 conclusion**: the T80+draft-vocab recipe is slower than ar-blk
(29-34 vs 39.7 C2L-corroborated) with low MTP (~20-27%), and the never-evict pin is neutral on
every bench we can run. **The funnel's winner is `ar-blk` (in-checkpoint MTP-3 block rejection
on the AR-hybrid weights, 39.7 tok/s C2L-corroborated)**, with the pin arms and the full
upstream recipes eliminated by measurement.

## Evidence

- `raw/atrest-*`, `raw/result-*` (this dir; seed-45 clean leg)
- CSV rows: `spark/bench/results-v2.csv` (`t3-v16bpin,20261003-123150` valid; `-122925`
  contaminated, excluded — counters reset)