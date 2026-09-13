# Qwen/Qwen3.8-Flash-Next — official HF model card (capture)

**Source:** https://huggingface.co/Qwen/Qwen3.8-Flash-Next
**Captured:** 2026-09-13 (parent fetch, readable extraction)
**Relevance:** R1 (original weights exist — this IS the canonical checkpoint), R3 (context extension), R5 (recommended engines)

---

> This repository contains model weights and configuration files for the post-trained model in the Hugging Face Transformers format.
> Compatible with Hugging Face Transformers, vLLM, SGLang, TokenSpeed, etc.
> Qwen3.8-Flash (Qwen Cloud API) is the official version based on Qwen3.8-Flash-Next with **1M context length by default**.

## Model Overview (language model)
- 125B total / 6B activated + **51B n-gram embedding** + 4B MTP
- Hidden dim 2560; token vocab 248,320; **n-gram embedding 20,000,000** (bigrams/trigrams at **layer 2**)
- 48 layers; layout 12 × (3 × (Gated DeltaNet → MoE) → 1 × (Qwen Sparse Attention → MoE))
- GDN: 48 V heads / 16 QK heads, head dim 128
- **QSA (Qwen Sparse Attention)**: 24 Q heads / 2 KV heads, head dim 256, RoPE dim 64; indexer = MQA 4Q+1 shared K, head dim 128, budget 512 blocks / 2048 tokens (micro-block level, not per-token selection)
- MoE: 512 experts, 10 routed + 1 shared activated, expert dim 640
- Gated Residual: 4 branches, bottleneck rank 320
- MTP: 1 layer, multi-step trained
- **Context Length: 262,144 natively and extensible up to 1,000,000 tokens.**

## Serving (official)
> "For production workloads or high-throughput scenarios, dedicated serving engines such as **SGLang, KTransformers or vLLM** are strongly recommended."
- SGLang: docs.sglang.io/cookbook/autoregressive/Qwen/Qwen3.8-Flash-Next
- vLLM: recipes.vllm.ai/Qwen/Qwen3.8-Flash-Next
- TokenSpeed: lightseek.org/tokenspeed/recipes/models#qwen3-8-flash-next
- Thinking mode default; reasoning_effort xhigh/medium/low (xhigh default); preserve_thinking default ON (retains thinking blocks across turns — KV cache utilization)
- Sampling (thinking): temperature=1.0, top_p=0.95, top_k=20

## Long-context extension (OFFICIAL recipe — resolves R3's key gap)
> "Qwen3.8-Flash-Next natively supports context lengths of up to 262,144 tokens. For long-horizon tasks where the total length exceeds this limit, we recommend using RoPE scaling techniques, e.g., **YaRN**."

YaRN config for `rope_parameters` in `text_config`:
```json
{
    "mrope_interleaved": true,
    "mrope_section": [11, 11, 10],
    "rope_type": "yarn",
    "rope_theta": 10000000,
    "partial_rotary_factor": 0.25,
    "factor": 4.0,
    "original_max_position_embeddings": 262144
}
```

vLLM:
```
VLLM_ALLOW_LONG_MAX_MODEL_LEN=1 vllm serve ... --hf-overrides '{"text_config": {"rope_parameters": {"mrope_interleaved": true, "mrope_section": [11, 11, 10], "rope_type": "yarn", "rope_theta": 10000000, "partial_rotary_factor": 0.25, "factor": 4.0, "original_max_position_embeddings": 262144}}}' --max-model-len 1000000
```

SGLang:
```
SGLANG_ALLOW_OVERWRITE_LONGER_CONTEXT_LEN=1 python -m sglang.launch_server ... --json-model-override-args '{"text_config": {"rope_parameters": {...as above...}}}' --context-length 1000000
```

TokenSpeed: analogous `TOKENSPEED_ALLOW_OVERWRITE_LONGER_CONTEXT_LEN=1 tokenspeed serve ...`.

> All frameworks implement **static YaRN** (factor constant regardless of input length, potentially impacting shorter texts). Only apply when long context is needed. Tune factor: for 524,288-typical usage, factor 2.0 is better.

Max output lengths at 1M context (recommended): reasoning 262,144; final response 131,072.

## config.json highlights (parent-fetched 2026-09-13, raw)
- architectures: ["Qwen4ExpForConditionalGeneration"], model_type qwen4_exp (multimodal; vision encoder 27 layers, hidden 1152)
- text_config.max_position_embeddings: 262144
- rope_parameters: { rope_type: "default", rope_theta: 10000000, partial_rotary_factor: 0.25, mrope_interleaved: true, mrope_section: [11,11,10] } — **no YaRN in checkpoint**
- full_attention_interval: 4; layer_types: 36 linear_attention + 12 full_attention (3:1)
- mtp: { num_hidden_layers: 1, hybrid: true, layer_types: ["full_attention"], rope_theta: 10000000 }
- num_experts 512, per-tok 10, moe_intermediate 640, shared_expert 640
- linear: 16 QK heads / 48 V heads, dims 128/128; mamba_ssm_dtype float32
- indexer_budget 2048, indexer_compress_ratio 4
- transformers_version 5.8.0.dev0

## Benchmarks (official, 256K window, temp=1.0 top_p=0.95)
- SWE-bench Pro 62.5 · SWE-bench Multilingual 81.0 · DeepSWE 1.1 58.7 · IFBench 81.3 · GPQA Diamond 91.7 · HLE 35.9 · LiveCodeBench v6 91.9 · Toolathlon 73.5 · Agents' Last Exam 51.2 — beats Qwen3.8-27B on essentially all; comparable or better than DeepSeek-V4-Flash and Qwen3.7-Plus (397B/17B-active) on several.

## Citation
@techreport{qwen2026design, title={On the Design of {Qwen3.8-Next} Architecture...}, institution={Alibaba Group}, month={August}, year={2026}}
Blog: https://qwen.ai/blog?id=qwen3.8-flash-next · Tech report: github.com/QwenLM/Qwen3.8-Flash-Next/blob/main/tech_report.pdf
Downloads last month: 624,390
