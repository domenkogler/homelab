# HD-489 — arm `ar-mmap` (tier 2 baseline: AR-hybrid + FP8 PLE mmap, spec OFF, **eager**)

Measured 2026-10-03 08:02–08:22 UTC on spark. **The tier-2 baseline and — so far — the
standout arm of the funnel.**

**Profile**: `ar-mmap` — `Qwen3.8-Flash-Next-W4A16-AutoRound-hybrid` (71 G, `/opt/homelab/models`,
loaded as **`quantization: auto_gptq`**) + FP8 PLE table via **disk mmap** (`ple_mmap: true`,
`VLLM_PLE_MMAP_DIR=/ple-table`, `FAST_PATH on (fadvise+preadv gather, 33 fds)`, `PLE table ready:
layer 1, 320,001,536 rows`), **spec OFF** (`speculative_config=None` — no drafter dir exists for
this checkpoint).

**Boot fix applied (owner-approved)**: `enforce_eager: true` — the FP8 mmap path copies an
unpinned CPU tensor into the CUDA graph during capture (→ `RuntimeError: Cannot copy between CPU
and CUDA tensors during CUDA graph capture unless the CPU tensor is pinned`). Eager mode
(`CUDAGraphMode.NONE`) skips graph capture entirely. **Trade: decode without CUDA-graph
acceleration — yet the numbers below beat the graph-accelerated AWQ arms on prefill and match
them on decode.**

## Fidelity (PASSED)

- Accuracy battery **0 failures, 10/10 outputs**.
- Slovenian accepted-length: 1313-token Slovenian prompt accepted (full), coherent Slovenian
  final content (`Razumem. To je res: Slovenija je država v srednji Evropi, glavno mesto pa je
  Ljubljana.`), correct diacritics, `finish: stop`.

## Speed legs (all clean)

| leg | seed | window (UTC) | dur | dec/stream | TTFT p50 | ITL p50 | ok | preempt |
|-----|------|--------------|-----|-----------|----------|---------|----|---------|
| C2  decode | 42 | 08:02:21–08:05:59 | 217s | **20.3** | **738 ms** | **49.5 ms** | 8/8 | 0 |
| C1  prefill | 43 | 08:06:06–08:11:45 | 338s | **12.6** | **15.99 s** | 49.2 ms | 8/8 | 0 |
| C2L long   | 44 | 08:11:59–08:22:15 | 616s | **20.4** | **635 ms** | **49.8 ms** | 12/12 | 0 |

At rest: engine/all pid 0/84973 MiB, usable 27.5 GiB (mmap table stays in page-cache, not the
KV pool — the 47.7 GiB FP8 table is prewarmed page cache, ~4 GB resident).

## Reading — the AR-hybrid weights are the funnel's story so far

| metric | u1-patch (AWQ, graphs) | u2-blk (AWQ, graphs) | **ar-mmap (AR, eager)** | delta vs u2 |
|--------|------------------------|----------------------|--------------------------|-------------|
| C2 dec/stream | 17.9 | 20.2 | **20.3** | parity (in eager!) |
| C2 TTFT p50 | 2879 ms | 3645 ms | **738 ms** | **−80%** |
| C2 ITL p50 | 97.3 ms | 101.3 ms | **49.5 ms** | **−51%** |
| C1 TTFT p50 (32k) | 57.2 s | 50.7 s | **15.99 s** | **−68%** |
| C1 dec/stream | 6.4 | 7.2 | **12.6** | **+75%** |

The **AutoRound W4A16-hybrid weights + FP8-disk-mmap PLE** deliver ~4× lower TTFT, ~2× lower
ITL, and parity decode **without CUDA graphs** — better per-step kernels compensate for eager
mode. The 47.7 GiB PLE table off NVMe (mmap) also frees the pool vs the in-memory INT4 overlay
(usable 27.5 GiB vs ~20 GiB).

## Verdict

**ar-mmap is the new tier-2 reference** and the strongest arm measured so far. Its decode is
eager-mode (no graphs) — the delta to tier-3 `v16b*` (which brings spec + graphs back) and to
`ar-blk` (spec ON) will tell whether decode improves further.

## Evidence

- `raw/atrest-*`, `raw/result-*` (this dir)
- CSV rows: `spark/bench/results-v2.csv` (`t2-arm,20261003-080221/080606/081159`)
- VM cross-check: same monitoring-not-converged caveat.