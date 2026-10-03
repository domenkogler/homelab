# HD-489 — arm `v16b-s4` (tier 3: v16b + seqs=4 control)

Measured 2026-10-03 11:40–11:54 UTC on spark. **seqs=4 freed memory enough to run the C2L
leg, but the full T80+draft-vocab recipe still loses to ar-blk on decode.**

**Profile**: `v16b-s4` — identical to `v16b` (T80 dense-MTP drafter + 65,536-id draft-vocab +
FP8 PLE mmap + enforce_eager) except **`max_num_seqs: 4`** (the client-contract control).
`Resolved architecture: Qwen3_8FlashNextMTP`.

## Fidelity (PASSED)

- Accuracy battery **0 failures, 10/10 outputs**.
- Healthy, RestartCount 0, KV pool 515,786 / 1.97×.

## Speed legs (C2L RAN — seqs=4 freed memory)

| leg | seed | dec/stream | TTFT p50 | ITL p50 | MTP | cold_ok | ok | preempt |
|-----|------|-----------|----------|---------|-----|---------|----|---------|
| C2  decode | 42 | 34.1 | 733 ms | 52.0 ms | 29.4% | no | 8/8 | 0 |
| C1  prefill | 43 | 16.1 | 16736 ms | 52.8 ms | 25.7% | **yes** | 8/8 | 0 |
| C2L long   | 44 | **33.1** | 685 ms | 52.2 ms | 25.7% | **yes** | 12/12 | 0 |

Host available rose to **25 GiB** (vs v16b's 11 GiB) — seqs=4 freed ~14 GiB, clearing the OOM
guard for C2L.

## Reading — the T80+draft-vocab recipe is the drag, not the batch shape

| metric | ar-blk (winner) | v16b | **v16b-s4** | delta vs ar-blk |
|--------|-----------------|------|-------------|-----------------|
| C2L dec/stream | 39.7 | cannot run | 33.1 | **−17%** |
| C2L MTP accept | 54.7% | — | 25.7% | **−29pp** |
| C2 dec/stream | 35.1 | 33.1 | 34.1 | −3% |

seqs=4 makes the recipe runnable (C2L works) but decode stays **below ar-blk** and MTP
acceptance stays low (~26%). The **draft-vocab slice + T80 drafter** (not seqs) is what drags
acceptance/decode — consistent with ar-dv's finding on the same vocab slice.

## Verdict

**v16b-s4 loses to ar-blk** (C2L 33.1 vs 39.7). seqs=4 is the memory-feasible variant of the
upstream recipe, but the recipe itself is slower than the lean in-checkpoint-MTP ar-blk on
this box. **ar-blk remains the winner.**

## Evidence

- `raw/atrest-*`, `raw/result-*` (this dir)
- CSV rows: `spark/bench/results-v2.csv` (`t3-v16bs4,20261003-114027/114250/114723`)