# R5 — SGLang on GB10/DGX Spark (engine candidate, esp. for long context + bf16)

**Question ID:** R5 · **Question:** Is SGLang a viable engine candidate for serving Qwen3.8-Flash-Next on the GB10/DGX Spark (sm_121, aarch64, 128 GB unified LPDDR5x @ ~273 GB/s), especially for long context and bf16 KV?
**Date:** 2026-09 · **Research mode:** local-evidence only — **web tools were unavailable in this lane** (supervisor decision 2026-09). Parts 1 and 5 of the question could not be web-verified; see "Open gaps for parent verification".

**VERDICT: PARTIAL** — SGLang is a working, well-configured engine for this model on Blackwell (sm_120 x86, 96 GB cards) with strong long-context numbers, but **no GB10/DGX Spark-specific evidence (official support status, aarch64 image/wheel availability, sm_121 correctness, Spark performance calibration) exists in the local evidence set**. Green for the x86-verified parts; the GB10 halves are unverified.

---

## Findings

1. **Claim:** The only known SGLang packaging for Qwen3.8-Flash-Next is a day-0 preview Docker image `lmsysorg/sglang:qwen38flashnext` (pushed 2026-08-26, branch `qwen4-main-squashed`) that bakes in the then-unmerged model-support PR #36497; stable SGLang v0.5.18 fails with "unknown model type" (no `qwen4_exp`). **Sources:** [r/LocalLLaMA 170K thread, Dull-Giraffe comment](https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/qwen38flashnext_at_170k_context_on_a_single_96_gb/) (R5 capture 1). **Support:** direct evidence. **Confidence:** high (for x86; image arch unverified).

2. **Claim:** SGLang PR #36556 is mandatory on sm_120: without the full fix, QSA decode boots, passes a smoke test, then **silently emits token ID 0 past the first KV page** (~position 65 at page-size 64); fixing only the varlen fallback crash from #36531 reproduces exactly that trap. Dull-Giraffe applies it "at container start" on top of the day-0 image. **Sources:** same thread. **Support:** direct evidence (community report, single operator). **Confidence:** high that it is mandatory on sm_120; **unknown whether it covers sm_121** — this is a silent-corruption-class risk that must be verified first on the GB10.

3. **Claim:** Complete community SGLang recipe on 1× RTX 6000 Pro (96 GB, GDDR7): RadixArk NVFP4 checkpoint, `--quantization modelopt_fp4 --fp4-gemm-backend flashinfer_cutlass --attention-backend triton --linear-attn-prefill-backend triton --linear-attn-decode-backend flashinfer --mamba-ssm-dtype bfloat16 --page-size 64 --ple-offload-embedding`, NEXTN MTP (steps 3, topk 1, draft 4, `--speculative-draft-model-quantization unquant`), `--max-mamba-cache-size 24 --mamba-radix-cache-strategy extra_buffer --mamba-track-interval 64`, `--context-length 262144 --max-total-tokens 460000 --mem-fraction-static 0.975 --chunked-prefill-size 4096 --max-running-requests 4 --watchdog-timeout 1800`. Result: ~10,000 tok/s prefill, 120–170 tok/s decode, 460k total context; MTP-off reaches 512k total context at ~120 t/s. **Sources:** [r/LocalLLaMA "Fastest qwen3.8 Flash Next Setup?", Turbulent-Alps4046 comment](https://www.reddit.com/r/LocalLLaMA/comments/1nsqf1c/ — see R5 capture 2; full flag list verbatim there) + [120 t/s follow-up post](https://www.reddit.com/r/LocalLLM/comments/1vz20ap/qwen38flashnextnvfp4_on_single_rtx_pro_6000_120ts/). **Support:** direct evidence, reproduced by OP (90 t/s with MTP disabled, 2 slots fit) and adopted by multiple commenters. **Confidence:** high for sm_120 x86.

4. **Claim:** BF16 KV at 192k context on SGLang confirmed (Dull-Giraffe): 150–160 tok/s narrative, 200–215 tok/s code at real depth; MTP spec tokens=3 with the MTP head costing only 0.51 GB and no KV-pool reduction. Memory split on 96 GB: 78.2 GiB GPU (68 GB NVFP4 routed experts + 16 GB BF16 everything-else), ~17 GiB left for KV+GDN state at 196k; host: ~51.2 GB pinned FP8 n-gram table via `--ple-offload-embedding` (`--ulimit memlock=-1` mandatory, `--shm-size 16g`, container budget ~55–60 GB). **Sources:** R5 capture 1. **Support:** direct evidence. **Confidence:** high. Note: this is bf16 **KV cache** on NVFP4 **weights** — no local evidence of full-bf16-weights serving on SGLang (cross-check R1; see gaps).

5. **Claim:** Highest-context SGLang config in evidence: `jpezzulli/sglang-rtxpro6000` (containerized, maintained; release 2026-09-06 with ~+15% c1 decode / +5% c4) serving RadixArk NVFP4 at full 262K context, BF16 KV, 51.2 GB FP8 n-gram table pinned in RAM, **32 GB HiCache pinned in RAM**, CUDA 13.3, RTX PRO 6000 WS. Used for a 99/100 SWE-bench Verified run. **Sources:** [Templates Comparison thread](https://www.reddit.com/r/LocalLLaMA/comments/1w84mod/qwen38_flash_next_templates_comparison/) + [jpezzulli/sglang-rtxpro6000](https://github.com/jpezzulli/sglang-rtxpro6000) (R5 capture 3). **Support:** direct evidence. **Confidence:** high for x86 sm_120. HiCache is a distinct long-context lever from `--max-total-tokens`/mamba-cache sizing and is relevant to a 128 GB unified pool.

6. **Claim:** Accuracy/tool-calling penalty for SGLang vs vLLM on this model: same operator measured SGLang+NVFP4 = 91/100 vs vLLM+AWQ-W4A16 = 98/100 on their SWE-bench slice; jinnyjuice independently: "using vLLM results in fewer tool call fails compared to SGLang, according to the benchmarks." **Confound (explicitly unresolved by the reporter):** engine AND quant changed together (NVFP4 vs AWQ W4A16), so engine-vs-quant attribution is unknown. **Sources:** [Templates Comparison comments, WonderRico table](https://www.reddit.com/r/LocalLLaMA/comments/1w84mod/qwen38_flash_next_templates_comparison/), [98/100 recipe thread](https://www.reddit.com/r/LocalLLaMA/comments/1w7c4ej/updated_my_benchmark_with_a_new_vllm_based_recipe/) (R5 capture 3). **Support:** direct evidence, confounded. **Confidence:** medium.

7. **Claim:** Additional SGLang throughput reference: patched SGLang recipe at 171 t/s c1 / 428 t/s c4 on 1× RTX Pro 6000 ([r/BlackwellPerformance](https://old.reddit.com/r/BlackwellPerformance/comments/1w04xb7/qwen38_flashnext_on_1x_rtx_pro_6000_171_ts_c1_428/), 2026-09, cited by WonderRico); an unverified "sglang fork with nvfp4 + q8 cache quant, 3×256k cache + vision + mtp" mentioned by u/AdSafe4047. **Support:** direct mention, second-hand. **Confidence:** medium/low (no config captured for the fork).

8. **Claim — RESEARCHER INFERENCE (not from any source):** On GB10 the `--ple-offload-embedding` pin (51–52 GB host RAM) and the HiCache RAM pin lose their host/GPU distinction — CPU+GPU share one 128 GB pool — so host-pinned tables consume the same pool as KV/mamba caches; the pinned-memory-vs-VRAM tradeoff collapses into one budget, and the ~273 GB/s bandwidth ceiling applies to PLE gathers. The NVFP4 x86 split (68 GB weights + 17 GiB KV at 196k on 96 GB) suggests a 128 GB pool could fit NVFP4 weights + a much larger KV/GDN budget, but decode throughput is bandwidth-bound and 273 GB/s is ~⅙ of a 6000 Pro's ~1.8 TB/s — expect materially lower t/s than the 120–215 tok/s x86 numbers. **Support:** inference only; no GB10 SGLang datapoint found.

## Implications for the bench plan

- **Keep SGLang as engine candidate #2** (vLLM is #1 on accuracy evidence), but gate it on two pre-bench checks on the actual GB10: (a) does an aarch64 variant of `lmsysorg/sglang:qwen38flashnext` exist/run under DGX OS, (b) does PR #36556 (or an sm_121-equivalent) apply — treat silent token-ID-0 as a MUST-verify, not a smoke-test item.
- The long-context flag kit transfers as-is if the image runs: `--max-mamba-cache-size`, `--mamba-radix-cache-strategy extra_buffer`, `--mamba-track-interval 64`, `--max-total-tokens` vs `--context-length` separation, NEXTN/MTP spec flags, `--page-size 64`.
- On GB10, re-plan the memory budget as ONE pool: NVFP4 weights (~78 GB per x86 split) + KV + GDN state + (optionally) pinned PLE table; `--ple-offload-embedding` may be unnecessary if the FP8/BF16 table fits the pool, or harmful if it evicts KV.
- Do NOT use the x86 t/s numbers as GB10 expectations; bandwidth (~273 GB/s) predicts decode well below the 96 GB GDDR7 card results. Bench both `--kv-cache-dtype auto/bfloat16` and FP8 KV; test HiCache for >262k ambitions.

## Open gaps for parent verification [unverified — web tools unavailable in lane]

1. **SGLang official GB10/DGX Spark support status:** SGLang docs/releases mentioning DGX Spark/GB10/sm_121/aarch64; NVIDIA DGX Spark docs listing SGLang as a supported runtime; whether `lmsysorg/sglang:qwen38flashnext` (or a successor) has an arm64 manifest. Community DGX Spark SGLang reports. ← question part 1.
2. **DGX Spark performance reports for SGLang (any model):** any tok/s datapoint on GB10 to calibrate what 273 GB/s unified memory delivers vs GDDR7 cards; also whether SGLang on GB10 uses unified-memory-specific paths (no host-pinned copies). ← question part 5.
3. **Full-precision (bf16 weights) serving of Qwen3.8-Flash-Next on SGLang:** no local evidence; "BF16" in the captures refers to KV cache / mamba SSM dtype / non-expert weights only. Cross-check R1; ~208 GB bf16 weights would not fit 128 GB anyway (inference: bf16-weights serving is likely out of budget on GB10 — verify).
4. **sm_121 status of PR #36556 and #36497 merge state** as of 2026-09: local evidence is 2026-08-26/30; both may have merged or changed since.
5. **Tool-calling quality, engine-isolated:** the 91-vs-98 result conflates quant and engine; no clean SGLang-vs-vLLM same-quant comparison found locally.

## Sources

- Kept: r/LocalLLaMA 170K thread (Dull-Giraffe SGLang comments) — day-0 image, #36556 trap, BF16 KV @192k, memory budgets (R5 capture 1)
- Kept: r/LocalLLaMA "Fastest setup" thread (Turbulent-Alps4046 recipe) — full SGLang flag kit, 460k/512k context, throughput (R5 capture 2)
- Kept: Templates Comparison + 98/100 threads + jpezzulli/sglang-rtxpro6000 GitHub — HiCache 262K config, accuracy/tool-call evidence (R5 capture 3)
- Deprioritized: r/BlackwellPerformance 171 t/s post — cited second-hand, not fetched
- Deprioritized: u/AdSafe4047 "sglang fork with q8 cache quant" — no link/config, unverified

---

## Parent verification addendum (2026-09-13, web-verified)

**SGLang on GB10/DGX Spark — VERIFIED ACTIVE (fills the lane's two main gaps):**
- Official NVIDIA playbook: `NVIDIA/dgx-spark-playbooks/nvidia/sglang` — "optimized SGLang CUDA
  container on a single NVIDIA Spark device". NVIDIA officially documents SGLang on DGX Spark.
- SGLang issue #11658 = official DGX Spark (GB10, sm_121a) support-tracking issue; LMSYS blog
  (2025-10-13) DGX Spark benchmarks + Docker tag `lmsysorg/sglang:spark` (note: that tag predates
  Flash-Next; model-specific image remains `lmsysorg/sglang:qwen38flashnext`).
- **This exact model runs on GB10 via SGLang — two published, measured recipes:**
  1. tonyd2wild/Qwen3.8-Flash-Next-NVFP4-DGX-Spark — day-0 (2026-08-26) NVFP4 on 2× Spark TP2 over
     200G ConnectX, SM121 QSA kernel-guard fix; "vLLM cannot serve it yet" (day-0 status).
  2. hashd1ve/qwen38-flash-next-one-dgx-spark — single Spark, RadixArk NVFP4 126 GiB in 121.63 GiB,
     41.5 tok/s code, full 262k ctx, GSM8K-verified. Two file-overlay patches (NVMe PLE mmap; QSA
     sm_121 Triton varlen = merged upstream #36845). See capture R5-hashd1ve-dgx-spark-sglang.md.
- GB10 SGLang bug surface (single-device, same cookbook image): issue #36716 (4 bugs: silent garbage
  decode via trtllm-gen, non-compacting _compact_kv, TMA-O varlen boot crash, fp8 tl.dot sparse
  prefill); issue #36558 (QSA decode: no working kernel path on SM121 — resolved by #36845 Triton
  varlen). SGLang PR #36364: GB10 MXFP4 cookbook cells measured on real GB10 (other models).
- **GB10 perf calibration (SGLang, this model):** ~41.5 tok/s single (code), TP2 day-0 config.
  Consistent with vLLM single-Spark numbers (36–46 tok/s) → 273 GB/s unified bandwidth is the
  ceiling, engine choice matters less than on GDDR7 cards.

**Revised R5 verdict: GREEN — SGLang is a first-class engine candidate for GB10, with the
strongest published single-Spark recipe for this model (hashd1ve) and official NVIDIA playbook
support. Watch #36716 bug set for single-device serving.**

## Remaining open items for bench time
1. Whether `lmsysorg/sglang:qwen38flashnext` is multi-arch (aarch64) — the two GB10 recipes above
   imply yes; verify manifest at pull time.
2. Whether #36845 (QSA Triton varlen) is in the current cookbook image or needs the file overlay.
3. SGLang+AWQ W4A16 on GB10 (accuracy champion quant on the SGLang engine) — no published GB10
   datapoint; bench A-lane covers it.
