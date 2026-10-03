# HD-489 — arm `ar-mmap` (tier 2 baseline: AR-hybrid + FP8 PLE mmap, spec OFF) — **FAILED TO BOOT**

Measured attempt 2026-10-03 06:57–07:16 UTC on spark. The tier-2 ladder's baseline arm cannot
boot with the current `ple_mmap` path.

**Profile**: `ar-mmap` — `Qwen3.8-Flash-Next-W4A16-AutoRound-hybrid` (71 G, `/opt/homelab/models`)
+ FP8 PLE table (`ple-table-fp8`, 49 G) served by **disk mmap** (`ple_mmap: true`,
`VLLM_PLE_MMAP_DIR=/ple-table`), speculative decode OFF (`spec_tokens: 0` — no drafter dir for
this checkpoint).

## Failure (hard, reproducible at CUDA-graph capture)

The FP8 PLE mmap path prewarmed correctly (`PLE mmap: FAST_PATH on (fadvise+preadv gather, 33
fds, max_rows=262144)`, `prewarming page cache (47.7 GiB)`, `PLE table ready: layer 1, 320001536
rows`), checkpoint loaded, then **during CUDA-graph capture**:

```
torch.ops.vllm.ple_mmap_lookup(...) → vllm_ple_mmap.py:832 _lookup_impl →
vllm_ple_mmap.py:675 forward → ple_layer.py:438 → RuntimeError:
Cannot copy between CPU and CUDA tensors during CUDA graph capture unless the
CPU tensor is pinned. Please use tensor.pin_memory() ...
Worker failed ... Engine core initialization failed.
```

## Root cause

The **mmap'd PLE table data (a CPU/page-cache tensor) is copied into the CUDA graph during
capture without `pin_memory`**. CUDA graph capture forbids unpinned CPU→GPU copies; the
`ple_mmap_lookup` op in `vllm_ple_mmap.py` carries the mmap'd rows as an unpinned CPU tensor.
So **`ple_mmap: true` is incompatible with CUDA-graph capture in this build** — every `ar-*`
arm (all `ple_mmap: true`) hits this, not just this one.

## Why tier-1 (u1–u4) booted fine

The u-arms use `ple_overlay: true` (INT4 code overlay into `ple_layer.py`) + the PLE offload
env trio — no disk-mmap lookup op in the graph. The mmap path is the delta that breaks.

## Verdict

**ar-mmap (and by construction ar-blk, ar-dv — all `ple_mmap: true`) cannot boot as authored.**
The tier-2 ladder is blocked on the mmap×CUDA-graph pinning conflict, NOT on weights/table
(layer 1's rows loaded: 320,001,536 × 160 B = 47.7 GiB prewarmed OK).

**Candidate fix (arm-def decision, not made unilaterally):** the mmap arms could set
`enforce_eager: true` (disable CUDA-graph capture) — trade eager-mode decode speed for
bootability — or the `ple_mmap_lookup` op could pin_memory its CPU rows. The funnel's
"one delta per arm" rule means this deserves an explicit authoring decision rather than a
silent flag change.

The box is flipped back to `u2-blk` (working tier-1 best).

## Evidence

- Engine logs: `ple_mmap_lookup` CUDA-graph pinning RuntimeError, EngineCore init failure
  (captured above). RestartCount 1 (killed before deeper crash-loop).
- PLE mmap prewarm success lines (table ready) prove table + weights staged correctly.