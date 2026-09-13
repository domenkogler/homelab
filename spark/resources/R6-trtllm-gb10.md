# R6 — TensorRT-LLM on GB10/DGX Spark (engine candidate, research-only)

**Question:** Is TensorRT-LLM a viable prebuilt/candidate path for serving Qwen3.8-Flash-Next on the Lenovo PGX / GB10 (DGX Spark-class, sm_121, aarch64, 128 GB unified), given the "no source-building" constraint?
**Date:** 2026-09
**VERDICT: PARTIAL** — No TRT-LLM candidate could be confirmed OR excluded from evidence available to this lane. **Web verification was not possible in this session (no web tools registered); local evidence contains zero TRT-LLM content.** The parent lane is completing the web checks listed under "Open gaps for parent verification" and will update this digest.

## Evidence basis and its limits

- All five local capture files in `spark/resources/` were mined (`fastest-qwen3-8-flash-next-setup.md`, `primitive-aiQwen3.8-Flash-Next-PLE.md`, `Qwen3.8-Flash-Next at 170K context on a single 96 GB card 110 t-s.md`, `Qwen3.8 Flash Next - Templates Comparison.md`, `vLLM based recipe for Qwen 3.8 Flash Next now up to 98-100.md`). **None mentions TensorRT-LLM, TRT-LLM, NGC TRT-LLM containers, trtllm-build, or TensorRT model optimizer (modelopt) at all.** They are entirely vLLM/SGLang/llama.cpp/EXL3/Ninfer discussion.
- No `web_search`/`fetch_content`/`source_check` tools were available in this lane (confirmed with the supervisor). Therefore **no claim below is backed by fresh web evidence**, and the researcher-inference items are explicitly labeled as such.

## Findings (local evidence only)

1. **Claim:** The only proven, artifact-level serving paths for Qwen3.8-Flash-Next on single Blackwell cards are vLLM and SGLang images. **Sources:** local captures (URLs inside the capture files): `vllm/vllm-openai:qwen38-flash-next` (primitive-ai PLE-quant card, https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant#serve) and `lmsysorg/sglang:qwen38flashnext` (r/LocalLLaMA 170K-context thread, https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/, comment by u/Dull-Giraffe). **Support:** direct evidence. **Confidence:** high.
2. **Claim:** No community report in the captured corpus runs this model on TRT-LLM; no TRT-LLM checkpoint, engine, or recipe for this model appears anywhere in the corpus. **Support:** direct evidence (absence across all five files). **Confidence:** high for the corpus, low as a proxy for the whole web.
3. **Claim (researcher inference, NOT source-stated):** The existence of `nvidia/Qwen3.8-Flash-Next-NVFP4` (FP8 PLE table, 8-GPU documented deployment) shows NVIDIA quantization tooling (NVFP4, likely ModelOpt) touched this model, which is *consistent with* but **not** evidence of a TRT-LLM path. NVFP4 is a format TRT-LLM natively supports on Blackwell in general, but whether the hybrid-GDN + MTP architecture is supported by TRT-LLM's Qwen3-Next-family implementation is unverified. **Confidence:** low.
4. **Claim (researcher inference, NOT source-stated):** If TRT-LLM does support the arch on GB10, the judge-rule in the task applies: engine compilation with `trtllm-build` inside an official NVIDIA container is standard usage and would qualify as a candidate; custom kernel/patch requirements would disqualify it. That judgment cannot be made yet because the support-matrix evidence is missing. **Confidence:** n/a (posture only).
5. **Claim:** GB10-relevant constraints that any TRT-LLM path must clear, from the shared context + captures: sm_121 compute capability (sm_120/sm_121 kernel availability was already load-bearing for SGLang — PR #36556 comment in the 170K capture), 128 GB unified LPDDR5x at ~273 GB/s (memory-bandwidth-bound decode; the model's 51.2B-param n-gram PLE table at 95.4 GB BF16 would not fit alongside weights in 128 GB — the quantized PLE sidecars, 28.8–49 GB, are the community solution and are **vLLM-overlay-specific artifacts**, `worker_image_quant.py`/`ple_layer_quant.py`, with no known TRT-LLM equivalent). **Support:** direct evidence for the numbers, researcher inference for the TRT-LLM implication. **Confidence:** medium.

## Implications for the bench plan (short)

- **Plan around vLLM/SGLang as the primary bench candidates.** They are the only paths with documented containers, flags, and measured numbers (80–170 tok/s single-stream class, RTX PRO 6000 numbers in captures; GB10 will differ). TRT-LLM is at best a speculative fourth lane pending parent web verification.
- Do not budget bench time for a TRT-LLM engine-build attempt until the parent confirms (a) official GB10/DGX Spark TRT-LLM support and (b) Qwen3-Next/GDN+MTP support in the release matrix.
- Note for any TRT-LLM attempt: the PLE n-gram table is the memory pain point; there is no known TRT-LLM counterpart to the quantized-PLE sidecar overlay, so a TRT-LLM path likely needs a checkpoint with a compact table (e.g., the FP8-table nvidia checkpoint) or its own offload mechanism — unverified.

## Open gaps for parent verification (exactly what needs checking)

1. **Official TRT-LLM support on DGX Spark/GB10:** docs.nvidia.com DGX Spark section — is TRT-LLM listed as a supported runtime (it appears other runtimes like SGLang/vLLM are the documented ones)? Check NGC catalog for aarch64/GB10 TRT-LLM container images and release notes for sm_121 support.
2. **Qwen3.8-Flash-Next / Qwen3-Next-family support matrix in TRT-LLM:** TRT-LLM release notes, `examples/` directory (qwen3_next / hybrid GDN examples), and whether MTP (NEXTN speculative) is exposed via TRT-LLM for this arch.
3. **Quantization formats on GB10:** native NVFP4 support on sm_121, ModelOpt NVFP4 checkpoint compatibility with the existing `nvidia/Qwen3.8-Flash-Next-NVFP4` / `RadixArk/...-NVFP4` checkpoints, and long-context (262k) + bf16/fp16 KV support for the GDN hybrid.
4. **Performance reports:** any NVIDIA blog / community TRT-LLM vs vLLM numbers on DGX Spark for hybrid-GDN models (expected to be scarce; the model released ~2026-08).
5. **Decision rule recap for the parent:** documented official-container path for this model on GB10 → candidate (engine compile allowed); custom kernels/source patches → NOT a candidate.

## Sources

- Kept (local captures only; no web fetches were possible):
  - primitive-ai/Qwen3.8-Flash-Next-PLE-quant model card capture — the vLLM container/overlay recipe and PLE table sizes.
  - r/LocalLLaMA 170K-context thread capture — SGLang image name, PR numbers, sm_120 kernel sensitivity.
  - r/LocalLLaMA "Fastest setup" thread capture — SGLang flag set, engine comparison context.
  - r/LocalLLaMA templates-comparison and WonderRico 98/100 captures — accuracy context, AWQ/NVFP4 behavior.
- Rejected/deprioritized: none new (nothing was fetched).

---

## Parent verification addendum (2026-09-13, web-verified)

**TRT-LLM on DGX Spark — VERIFIED OFFICIAL (fills the lane's gap 1):**
- Official NVIDIA playbook: https://build.nvidia.com/spark/trt-llm — "Install and use TensorRT-LLM
  on DGX Spark… achieving significantly higher throughput and lower latency than standard PyTorch
  inference". Container: `nvcr.io/nvidia/tensorrt-llm/release:1.2.0` (also 1.2.0rc6 referenced in
  the playbook README). GB10 platform fixes exist upstream (PR #12902: disable NCCL_SYMMETRIC
  tactic on GB10).
- **Model-specific support for Qwen3.8-Flash-Next: NO evidence found** (no support-matrix entry,
  no example, no community serving report). Adjacent data point is negative-ish: issue #12762 —
  Qwen3-30B-A3B NVFP4 HF export FAILS to load in TRT-LLM on DGX Spark/GB10 (weight_scale mismatch,
  container 1.2.0, modelopt 0.37.0) — Qwen MoE NVFP4 export path on GB10 is currently broken there.
- PLE n-gram table: no TRT-LLM equivalent of the quantized-sidecar overlay (lane's caveat stands);
  the 47.7–51.2 GB table would have to live in the same unified pool as weights+KV, with no
  published NVMe-staged gather path.

**Revised R6 verdict: RED as a bench candidate for THIS model today** — the engine officially
supports GB10, but there is no documented Qwen3.8-Flash-Next (qwen4_exp / hybrid-GDN+MTP) path,
the Qwen-MoE NVFP4 export on GB10 is broken (#12762), and the PLE table has no serving story.
Record as "future row"; revisit only if vLLM AND SGLang both fail a Phase-D context target or the
accuracy gate (the pre-declared escape-hatch rule — and SGLang comes first in that ladder anyway).

