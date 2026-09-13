# R2-nvfp4.md

**Question ID:** R2
**Question:** NVFP4 availability for Qwen3.8-Flash-Next (weights + PLE tables) and accuracy evidence.
**Date:** 2026-09
**VERDICT: PARTIAL** — candidate set is unblocked (four pre-quantized NVFP4 checkpoints + 28.8 GB ples_nvfp4 sidecar all confirmed as pullable artifacts from local primary-source capture), but independent primary-source confirmation of the four HF checkpoint pages and any additional accuracy comparisons was NOT possible: web/fetch tools were unavailable in this lane. Every item marked **[unverified — web tools unavailable in lane]** needs parent verification before it is treated as confirmed.

## Findings

### A. NVFP4 checkpoint availability

1. **Claim:** Four NVFP4 checkpoints of Qwen/Qwen3.8-Flash-Next exist and are community-proven as pullable artifacts. All are pre-quantized → GREEN candidates; nothing needs building.
   **Sources:** local captures of primitive-ai PLE-quant card, r/LocalLLaMA threads (URLs below).
   **Support:** direct evidence (community configs reference them by exact HF path and run them). **Confidence:** high that they exist; page-level details below are **[unverified — web tools unavailable in lane]**.

2. **Claim:** `primitive-ai/Qwen3.8-Flash-Next-NVFP4` — plain NVFP4 build. Core checkpoint ≈78.23 GiB across 52 shards; ships its own BF16 PLE table as `ple-bf16-*` (128 shards, ≈95.4 GB) which can be skipped at download (`--exclude "ple-bf16-*"` + index trim dropping exactly 128 `ngram_embedding` entries). No quantized table shipped on the checkpoint itself. Published by primitive-ai.
   **Sources:** r/LocalLLaMA 1w2b2j0 (UltrMgns recipe + madbrain1976 failure report giving 78.23 GiB / 52 shards); primitive-ai PLE-quant card.
   **Support:** direct evidence from field reports; card text itself **[unverified]**. **Confidence:** high (two independent reports agree on paths/sizes).

3. **Claim:** `primitive-ai/Qwen3.8-Flash-Next-mixed-NVFP4-FP8` — mixed NVFP4/FP8 build, the checkpoint primitive-ai measured all four PLE table formats against on a 96 GB card. primitive-ai says "drop `-e VLLM_GDN_DECODE_KERNEL=triton` when serving the plain NVFP4 build", i.e. the mixed build keeps the triton GDN decode kernel env var.
   **Sources:** primitive-ai PLE-quant card (captured verbatim locally = primary source for this repo's behavior).
   **Support:** direct evidence. **Confidence:** high for serving behavior; page **[unverified]**.

4. **Claim:** `nvidia/Qwen3.8-Flash-Next-NVFP4` — nvidia build whose card documents an 8-GPU deployment because its FP8 table cannot use vLLM's BF16-only host offload; nevertheless it boots on ONE 96 GB card via primitive-ai's PLE overlay: 234 s boot, 88,828 MiB, 348k-token KV pool. Its 53.7 GB table-and-MTP shard is skippable at download time (overlay stubs the table parameter). Scores **92.1 knowledge / 78.3 tool-calling** under primitive-ai's pinned 1,170-item knowledge + 200-item tool-calling protocol — this confirms the 92.1/78.3 figures from the same primary capture.
   **Sources:** primitive-ai PLE-quant card (primary capture).
   **Support:** direct evidence (quoted on primitive-ai's card); nvidia's own card text **[unverified]**. **Confidence:** medium-high (single source, but it is the protocol owner reporting its own measurement).

5. **Claim:** `RadixArk/Qwen3.8-Flash-Next-NVFP4` — most community-deployed NVFP4 build (SGLang `--quantization modelopt_fp4 --fp4-gemm-backend flashinfer_cutlass --ple-offload-embedding`). Composition per field report: ≈68 GB NVFP4 routed experts + ≈16 GB BF16 everything-else. Ships an FP8 n-gram table (51.2 GB, pinned in host RAM via `--ple-offload-embedding`). Serves at 150–170 t/s decode, ~10k t/s prefill, 460k context on a single RTX PRO 6000 (Turbulent-Alps4046 full flag set captured).
   **Sources:** r/LocalLLaMA fastest-setup thread (Turbulent-Alps4046), r/LocalLLaMA 1w84mod (HeDo88TH), r/LocalLLaMA 1w2b2j0 (Dull-Giraffe).
   **Support:** direct evidence; card **[unverified]**. **Confidence:** high.

6. **Claim:** `primitive-ai/Qwen3.8-Flash-Next-PLE-quant` (primary source, captured verbatim) ships the quantized PLE sidecars, including **ples_nvfp4 = 28.8 GB** (NVFP4-style group-16 e2m1). CONFIRMED locally against the card text. Format: 128 `shard_N.safetensors` (2,500,012 rows each, row width 160) + `META.json`; tensors `weight_e2m1 [rows,80] uint8` (code = mag index|sign<<3, mags 0,.5,1,1.5,2,3,4,6), `weight_scale [rows,10] e4m3fn`, `weight_scale_2 [] fp32`. Siblings: `ples_int4` 32 GB, `ples_fp8` 49 GB. Overlay files: `worker_image_quant.py`, `ple_layer_quant.py` (meta-device build since 2026-09-06, removes the 95 GB host allocation / overcommit problem), `connector_mrv2.py` (fixes vllm#53960 boot hang). Works with any BF16-table checkpoint, and since 2026-09-06 with checkpoints shipping FP8 tables.
   **Sources:** primitive-ai/Qwen3.8-Flash-Next-PLE-quant card (local verbatim capture).
   **Support:** direct evidence. **Confidence:** high.

7. **Claim:** PLE-table quantization to NVFP4 costs ~nothing in accuracy/throughput — the deciding data point for using ples_nvfp4 on a 128 GB unified-memory box. Measured by primitive-ai, one RTX PRO 6000, mixed checkpoint, same 1,170+200 protocol: BF16-in-RAM baseline 92.2 knowledge / 79.2 tool-calling, 84.5 t/s @1, 516.8 @32; **NVFP4 sidecar 92.2 / 78.7, 80.3 @1, 476.8 @32**, boot 417 s. All four formats sit in one band (tool-call spread ±1.5). MTP+NVFP4 table: 128.8 t/s single-stream vs 142.6 (BF16 in RAM).
   **Sources:** primitive-ai PLE-quant card. **Support:** direct evidence. **Confidence:** high.

8. **Claim:** Two further community packagings of the table exist but were not measured by primitive-ai: `edougawa/Qwen3.8-Flash-Next-W4A16-PLE4-MTP-Spark` (per-row INT4 PLE with FP16 scales inside the checkpoint; needs their vLLM patch) and `HamboneLabs-AI/Qwen3.8-Flash-Next-uint3-g64` (raw BF16 table mapped via their patch set).
   **Sources:** primitive-ai PLE-quant card "Notes". **Support:** direct evidence (card statement). **Confidence:** medium (existence asserted by the card; repos **[unverified]**).

### B. Accuracy evidence: NVFP4 vs AWQ

9. **Claim:** WonderRico's SWE-bench-Verified-style bench (100-task django slice): **AWQ W4A16 (wtdcode) on vLLM = 98/100; RadixArk NVFP4 + FP8 KV + FP8 PLE on SGLang = 91/100** (sharp/froggeric templates on NVFP4: 89). Both medium and xhigh reasoning gave 98 on AWQ. Confirmed as stated in the task.
   **Sources:** r/LocalLLaMA 1w7c4ej (WonderRico) + r/LocalLLaMA 1w84mod comment table. **Support:** direct evidence. **Confidence:** high for the numbers; attribution unresolved (author himself says weights/engine/quant changed together).

10. **Claim:** RadixArk calibration critique: community comment — "thought it was weird they calibrated their quant to cnn_dailymail — of all the datasets on huggingface they had to pick that." Confirms the critique exists, as anecdotal commentary (not a benchmark).
    **Sources:** r/LocalLLaMA 1w7c4ej comment (u/CATLLM). **Support:** direct evidence of the critique's existence. **Confidence:** high that the critique exists; low as accuracy evidence.

11. **Claim:** Mechanistic hypothesis for the 98-vs-91 delta: HF discussion `VnimanieAI/Qwen3.8-Flash-Next-W4A16#4` — the AWQ recipe keeps attention layers at bf16, which stops the model overthinking (NVFP4 quantizes them; also makes it too big for 4×3090). **[Discussion content unverified — web tools unavailable in lane; only the pointer is captured.]**
    **Sources:** r/LocalLLaMA 1w7c4ej comment (u/ArtfulGenie69). **Support:** direct evidence of the pointer; discussion text unverified. **Confidence:** medium.

12. **Claim (researcher inference, clearly labeled):** The 91 vs 98 gap is NOT cleanly attributable to NVFP4 quantization. Counter-evidence in the same captures: HeDo88TH ran the **RadixArk NVFP4 on SGLang at stock template xhigh = 99/100** on SWE-bench Verified slice 0:100 — higher than WonderRico's AWQ/vLLM 98. Engine, template, reasoning effort, and protocol all differ between the two setups. Inference: engine + template + reasoning-effort dominate; quantization delta is plausible (VnimanieAI#4 mechanism) but unproven. No additional direct NVFP4-vs-AWQ comparisons for this model were found in the captures.
    **Sources:** r/LocalLLaMA 1w84mod (HeDo88TH table; WonderRico cross-comment). **Support:** researcher inference from direct evidence. **Confidence:** medium.

### C. llm-compressor self-conversion recipe

13. **Claim:** No documented llm-compressor NVFP4 self-conversion recipe for the hybrid-GDN/Qwen3-Next architecture appears in any local capture. Nothing found = recorded as NOT a candidate (and self-conversion is excluded from candidacy by task rules anyway). Pre-quantized checkpoints (primitive-ai ×2, nvidia, RadixArk NVFP4 + wtdcode AWQ W4A16) exist, making self-conversion moot for the bench.
    **Sources:** absence of evidence across all five local captures. **Support:** missing evidence, not proof of absence. **Confidence:** low-medium that no recipe exists publicly.

## Implications for the bench plan

- All NVFP4 artifacts are existing pullable artifacts: 4 checkpoint repos + the 28.8 GB `ples_nvfp4` sidecar + two overlay .py files + container image `vllm/vllm-openai:qwen38-flash-next`. Nothing to build. GREEN on availability.
- Recommended bench matrix on the PGX/GB10 (128 GB unified, host-RAM/VRAM distinction collapses): (a) accuracy lane → wtdcode AWQ W4A16 + ples_int4 sidecar, vLLM (the 98/100 recipe, WonderRico full docker command captured); (b) speed lane → RadixArk or primitive-ai NVFP4 + ples_nvfp4 sidecar (smallest host footprint, 92.2/78.7 under primitive-ai protocol), SGLang with Turbulent-Alps4046's flag set or vLLM with the overlay. On GB10 the page-cache/reclaimable-mmap property of the sidecars means the 28.8 GB table coexists with the ~78 GB checkpoint inside the 128 GB pool.
- Operational gotchas carried into the bench: image default `--max-num-seqs 1024` exceeds Mamba state blocks at 0.92 utilization → set explicitly; native 262k context + MTP needs 7.57 GiB KV vs 5.95 left → cap max-model-len or drop MTP; mount `connector_mrv2.py` for vllm#53960; `--cap-add=SYS_PTRACE` / yama ptrace_scope may be needed in containers; meta-device `ple_layer_quant.py` (post-2026-09-06) required if host commit limit is tight; PLE offload worker busy-loops ~3 cores (thermals on air-cooled CPU).
- Accuracy reporting caveat: bench results on NVFP4 builds must record engine + template + reasoning effort, since the 91↔99 spread across captures is dominated by those, not provably by quantization.

## Open gaps for parent verification (web tools unavailable in this lane)

1. Primary-source confirmation of the four NVFP4 checkpoint pages — `primitive-ai/Qwen3.8-Flash-Next-NVFP4`, `primitive-ai/Qwen3.8-Flash-Next-mixed-NVFP4-FP8`, `nvidia/Qwen3.8-Flash-Next-NVFP4`, `RadixArk/Qwen3.8-Flash-Next-NVFP4`: exact download sizes, what table each ships (BF16/FP8/none), publisher identity, license. Sizes above come from field reports, not the cards.
2. Additional NVFP4 vs AWQ accuracy comparisons beyond WonderRico's single bench; content of HF discussion VnimanieAI/Qwen3.8-Flash-Next-W4A16#4 (bf16-attention/overthinking claim).
3. Existence of a documented llm-compressor NVFP4 self-conversion recipe for hybrid-GDN/Qwen3-Next (fallback only; likely moot given pre-quantized checkpoints).
4. nvidia card's own accuracy table beyond the 92.1/78.3 relayed by primitive-ai (confirm nvidia reports those numbers itself, and under whose protocol).

## Sources

Kept (local verbatim captures / field reports with exact configs):
- primitive-ai/Qwen3.8-Flash-Next-PLE-quant model card — https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant (PRIMARY: ples_nvfp4 28.8 GB spec, all table-format accuracy numbers, nvidia-card relay incl. 92.1/78.3, overlay files, gotchas)
- r/LocalLLaMA "Updated my benchmark with a new vLLM based recipe" — https://www.reddit.com/r/LocalLLaMA/comments/1w7c4ej/ (WonderRico 98 vs 91, full vLLM docker command, RadixArk cnn_dailymail critique, VnimanieAI#4 pointer)
- r/LocalLLaMA "Qwen3.8 Flash Next - Templates Comparison" — https://www.reddit.com/r/LocalLLaMA/comments/1w84mod/ (HeDo88TH: RadixArk NVFP4/SGLang stock xhigh 99/100; WonderRico quant-table cross-comment)
- r/LocalLLaMA "Qwen3.8-Flash-Next at 170K context on a single 96 GB card" — https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/ (primitive-ai NVFP4 + ples_int4 download recipe, index trim, checkpoint sizes, k8s yaml, SGLang composition numbers)
- r/LocalLLaMA "Fastest qwen3.8 Flash Next Setup?" (thread captured in fastest-qwen3-8-flash-next-setup.md; RadixArk/SGLang full flag set, modelopt_fp4)

Rejected/deprioritized: none of the five captures were rejected; all were mined. No external sources could be fetched or evaluated (no web tools in lane).

Raw-capture note: per task contract, primary-source captures should be written as R2-*.md files in spark/resources/. The single decisive primary source (primitive-ai PLE-quant card) is already captured verbatim in that folder as `primitive-aiQwen3.8-Flash-Next-PLE.md`; duplicating it would create a redundant file. No new primary sources could be fetched, so no additional capture files were created.

---

## Parent verification addendum (2026-09-13, web-verified)

1. **nvidia/Qwen3.8-Flash-Next-NVFP4 is the "official" NVFP4 quant — VERIFIED** (referenced by the
   madeye single-Spark recipe as "NVIDIA's official NVFP4 checkpoint"; forum thread "Qwen3.8-Flash-Next
   on 1, 2 and 4 DGX Sparks with NVIDIA's official NVFP4 quant: 64 tok/s peak single stream").
2. **GB10-specific NVFP4 findings (change the A2 calculus):**
   - vLLM published builds: NVFP4 MoE falls back to Marlin on sm_121 → unservable on the unified
     pool (#50925); forum: "FP4 support is not there yet for vLLM on GB10 — better performance
     using AWQ quants."
   - SGLang on GB10 + NVFP4: WORKS (tonyd2wild TP2 day-0; hashd1ve single-Spark 41.5 tok/s;
     madeye's vLLM recipe also runs NVFP4 on a patched nightly 8a728663 with staged NVMe PLE).
   - ⇒ **A2 (NVFP4) stays IN the bench matrix but only on SGLang (or the patched vLLM recipe);
     on stock published vLLM images NVFP4 is a documented non-starter on GB10.** The accuracy
     confound (NVFP4≈91 vs AWQ≈98 on WonderRico's bench) still stands — AWQ+PLE likely wins S1/S2
     accuracy; NVFP4 competes on S3 aggregate throughput.
3. ples_nvfp4 (28.8 GB) confirmed as pullable sidecar; note madeye: "NVFP4 PLE storage is not
   supported by the current loader" — his recipe uses the FP8 table (47.68 GiB) with NVMe staging.
   Verify at bench time which PLE formats the GB10 recipes actually accept.
