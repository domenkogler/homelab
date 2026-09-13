# Qwen3.8-Flash-Next on one DGX Spark (SGLang, RadixArk NVFP4) — capture

**Source:** https://github.com/hashd1ve/qwen38-flash-next-one-dgx-spark
**Captured:** 2026-09-13 (parent fetch, README truncated at 8K)
**Relevance:** R5 (SGLang on GB10), S4 long context (needle data), unified-memory PLE insight

- 126.0 GiB RadixArk NVFP4 checkpoint served in 121.63 GiB unified memory, SGLang,
  41.5 tok/s on code, full 262k context, GSM8K within noise of published. Day-zero 2026-08-26.
- **Unified-memory insight:** every engine's PLE "offload to host RAM" flag frees NOTHING on Spark
  (host RAM and GPU memory are the same pool). PLE must go to NVMe instead.
  - Patch 1: PLE table on NVMe via file-backed mmap (torch.from_file shared), per Qwen tech report
    §2.3.2 (tables designed for off-accelerator storage; layer-2 placement for prefetch overlap).
    47.7 GiB table = 20M rows x 160 B; token reads 16 rows; cost <3% wall clock; 138 KB/token disk
    reads (~20 MB/s NVMe). madvise(MADV_RANDOM). GB10 supports host-page-table CUDA dereference
    (cudaDevAttrPageableMemoryAccessUsesHostPageTables==1). Bench: decode 16 rows 3.58 ms cold /
    0.12 ms warm.
  - Patch 2: QSA has NO decode kernel on sm_121 (is_sm100_supported() gates). WARNING: widening the
    trtllm gate to sm_12x silently corrupts long-context decode (flashinfer XQA path, no sm12x
    cubins): token-id-0 runs 1/4 requests @120k, 2/4 @190k, 4/4 @210k (sglang#36806 retired it).
    Correct fix = Triton varlen fallback, merged upstream sglang#36845.
    Needle retrieval verified 4/4 at 120k, 190k, 210k with the fixed path.
- Checkpoint anatomy (RadixArk NVFP4): routed experts NVFP4 68.0 GB; PLE n-gram table fp8 51.2 GB
  (47.7 GiB); BF16 (attn/GDN/mHC/vision/MTP/lm_head) 16.0 GB; total 135.3 GB = 126.0 GiB.
- Related: tonyd2wild/Qwen3.8-Flash-Next-NVFP4-DGX-Spark — day-0 2x DGX Spark TP2 SGLang NVFP4
  (200G ConnectX fabric), SM121 QSA kernel-guard fix; "vLLM cannot serve it yet" (at day 0).
- SGLang cookbook lists H200/B200/B300/GB300 — GB10 NOT on it (as of capture).
