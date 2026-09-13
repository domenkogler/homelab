# R5 capture — SGLang 262K + HiCache on jpezzulli/sglang-rtxpro6000, accuracy/tool-call evidence (Templates Comparison thread)

**Source:** https://www.reddit.com/r/LocalLLaMA/comments/1w84mod/qwen38_flash_next_templates_comparison/ (u/HeDo88TH, 2026-09-05) and https://www.reddit.com/r/LocalLLaMA/comments/1w7c4ej/updated_my_benchmark_with_a_new_vllm_based_recipe/ (u/WonderRico, 2026-09-04)
**Captured:** 2026-09 (from local evidence files `Qwen3.8 Flash Next - Templates Comparison.md` and `vLLM based recipe for Qwen 3.8 Flash Next now up to 98-100.md`)

## Runtime section of the Templates Comparison post (u/HeDo88TH, 2026-09-05)

> I containerized [`jpezzulli/sglang-rtxpro6000`](https://github.com/jpezzulli/sglang-rtxpro6000) and ran Flash Next with [RadixArk/Qwen3.8-Flash-Next-NVFP4](https://huggingface.co/RadixArk/Qwen3.8-Flash-Next-NVFP4) on **CUDA 13.3**.
>
> * Full **262K context**
> * **BF16 KV**
> * **51.2 GB FP8 n-gram embedding table** pinned in RAM
> * **32 GB HiCache** pinned in RAM
>
> Hardware: Ryzen 9 9900X, 128 GB DDR5-5600, RTX PRO 6000 WS.
> SWE-bench Verified with mini-SWE-agent 2.4.6, slice 0:100. Stock template @ xhigh: 99/100 resolved.

## jpezzulli (repo author) in comments, 2026-09-06

> Glad to see my repo being used. New release being published right now with about 15 percent increase c1 decode and 5 percent at c4. Also a few maintenance items that were in a release early!

## WonderRico cross-benchmarks (SGLang vs vLLM, same machine, sm_120 + sm_89)

From the Templates Comparison comments (u/WonderRico):

> I tested two quants: the same radix version as yours on the same sglang config, and another one in vLLM. I only tested with the stock chat template.
>
> | model | template | reasoning effort | Weights quant | KV cache quant | PLE quant | Score /100 | Requests | req/pts | in Mtok | out Mtok |
> |---|---|---|---|---|---|---|---|---|---|---|
> | Qwen3.8-Flash-Next | stock | medium | NVFP4 | FP8 | FP8 | 91 | 2653 | 29 | 44 | 0.88 |
> | Qwen3.8-Flash-Next | sharp | medium | NVFP4 | FP8 | FP8 | 89 | 2903 | 33 | 50 | 0.97 |
> | Qwen3.8-Flash-Next | froggeric | medium | NVFP4 | FP8 | FP8 | 89 | 3017 | 34 | 50 | 0.96 |
>
> However, **the AWQ version on vLLM got me to 98/100 while the NFP4 in SGLANG stayed at 91**

From the "vLLM based recipe … 98/100" thread (u/WonderRico, 2026-09-04): prior SGLang setup was "the optimized SGLANG (patched) from https://old.reddit.com/r/BlackwellPerformance/comments/1w04xb7/qwen38_flashnext_on_1x_rtx_pro_6000_171_ts_c1_428/" (171 t/s c1, 428 t/s c4 headline); the new vLLM+AWQ-W4A16+PLE-INT4 setup reached 98/100 — "It's way slower (for my low concurrency usecase) but also a lot better… I'll try to dig deeper to understand if the difference comes from the engine (and its patches) or the quants themselves."

## jinnyjuice on tool calls, 2026-09-06

> You should know that using vLLM results in fewer tool call fails compared to SGLang, according to the benchmarks.

## Why this capture matters
- Highest-context SGLang config in evidence: full 262K context with BF16 KV on one 96 GB card, with HiCache (32 GB, RAM-pinned) as the long-context KV mechanism — a distinct lever from `--max-total-tokens`/mamba-cache sizing.
- Names a maintained, containerized SGLang packaging (`jpezzulli/sglang-rtxpro6000`) with active releases (+15% c1 decode, +5% c4, 2026-09-06) — candidate base image, though it is an x86/sm_120 packaging.
- Quantifies the SGLang accuracy penalty in one operator's suite (91 vs 98) — confounded (engine AND quant changed together: SGLang+NVFP4 vs vLLM+AWQ-W4A16); the engine-vs-quant attribution is explicitly unresolved by the reporter.
- Independent tool-calling claim against SGLang (jinnyjuice).
- SGLang patched-recipe throughput reference: 171 t/s c1 / 428 t/s c4 (r/BlackwellPerformance, 2026-09).
