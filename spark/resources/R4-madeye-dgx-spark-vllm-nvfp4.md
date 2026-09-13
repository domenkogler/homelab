# Qwen3.8-Flash-Next on a single NVIDIA DGX Spark (vLLM, NVIDIA NVFP4 checkpoint) — capture

**Source:** https://madeye.github.io/qwen38-flash-next-on-dgx-spark/
**Captured:** 2026-09-13 (parent fetch, readable)
**Relevance:** R4 (vLLM on GB10 works), S2/S3/S4 calibration (GB10 decode/prefill), 512k YaRN demo

- Official NVIDIA NVFP4 checkpoint, single DGX Spark (GB10, 128 GB unified), TP1,
  pinned vLLM nightly `8a728663`, staged disk PLE gather (NVMe mmap), MTP3
  (47,149-token draft vocab), BF16 recurrent state, FP8 KV, 6 seq slots, 4096-token
  prefill chunks, 262,144-token context, decode CUDA graphs. Prefix caching + DFlash disabled.
  Default 30 GiB host reserve -> GMU=0.7535.
- Measured 2026-09-10 (thinking off, T=0):
  - Prose 1 req: **36.83 tok/s** out; Code 1 req: **45.75 tok/s**; TTFT ~0.2 s
  - 4 mixed requests: **100.18 tok/s aggregate**
  - Prefill: 8.2k prompt 1,606 tok/s; 32.8k prompt 1,825 tok/s
  - MTP draft acceptance 65.7%; KV budget 7.44 GiB = **507,810 tokens**; min free host mem 19.94 GiB
- Earlier 40-prompt run (2026-09-06): 43.5 tok/s median decode, TTFT 0.26 s.
- Legacy RadixArk profiles: NVFP4 19.1 tok/s decode vs Hybrid (+fp8 side layers) 21.6 (+13%); prefill 1,042 / 916 tok/s.
- Memory: FP8 PLE table 47.68 GiB served from NVMe via staged disk reads; model load 76.48 GiB;
  **NVFP4 PLE storage not supported by current loader** (FP8 table used instead).
- `scripts/serve-500k.sh`: legacy **YaRN 524,288 context · hybrid · 1 seq** — 512k on one Spark demonstrated.
