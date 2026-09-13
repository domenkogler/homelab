# R1 — Do original bf16/fp16 weights of Qwen3.8-Flash-Next exist?

Question ID: R1 · Question: Does a canonical (ideally Qwen-org) bf16/fp16 checkpoint of Qwen3.8-Flash-Next exist on HF, and if not, is dequantizing the AWQ W4A16 a viable benchmark reference?
Date: 2026-09
VERDICT: **PARTIAL** — local captures strongly imply an original BF16 checkpoint exists and quantify its PLE table, but no live HF fetch was possible in this lane (no web tools registered). Canonical repo id, license, config.json (layers, full-attn fraction, rope/YaRN) remain UNVERIFIED and are listed for parent verification.

## Verdict line
An original BF16 checkpoint almost certainly exists (quant ecosystem + primitive-ai's "built from the original BF16 tables" statement), but it is ~250 GB-class [inference] and therefore NOT runnable on the 128 GB GB10 target; on-box bench candidates remain the quantized repos. Dequantized-AWQ is the fallback *reference* candidate (offline accuracy oracle), not a runnable candidate.

## Findings

1. **Claim:** An original checkpoint of Qwen3.8-Flash-Next exists and ships its PLE n-gram table in BF16. **Sources:** [primitive-ai/Qwen3.8-Flash-Next-PLE-quant card](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant). **Support:** direct evidence — the card states the quantized sidecars were "Built from the original BF16 tables, so it works with any checkpoint of this model: our mixed NVFP4/FP8 build, our plain NVFP4, **the original model**, and, since 2026-09-06, checkpoints that ship their own table in FP8." It also gives the BF16 table size: "the CPU-offload worker holds it in BF16 (**95.4 GB**)". **Confidence:** high (that the original exists); the *identity/location* of the original repo is [unverified] — the served model name in a captured SGLang config (`--served-model-name Qwen/Qwen3.8-Flash-Next`, Turbulent-Alps4046 recipe) hints the canonical id is `Qwen/Qwen3.8-Flash-Next`, but this is a hint, not confirmation.

2. **Claim:** A BF16 copy of the 51.2B-param PLE table ships inside `primitive-ai/Qwen3.8-Flash-Next-NVFP4` as `ple-bf16-*` shards. **Sources:** [r/LocalLLaMA 170K-context post](https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/qwen38flashnext_at_170k_context_on_a_single_96_gb/) (OP's index-trimming snippet: `drop=[k for k,v in wm.items() if v.startswith('ple-bf16-')]; assert len(drop)==128 and all('ngram_embedding' in k for k in drop)` — "Skipping `ple-bf16-*` (saves 100 GB but breaks the index)"; commenter madbrain1976's reproduction log: "the 52 core checkpoint shards", "the 78.23 GiB core checkpoint"). **Support:** direct evidence. So the NVFP4 repo = 52 core shards (78.23 GiB: 68 GB NVFP4 routed experts + 16 GB BF16 everything-else, per Dull-Giraffe) + 128 `ple-bf16-*` ngram shards (~100 GB) + optional MTP head. Table geometry (PLE-quant card): 2,500,012 rows × 128 shards ≈ 320M rows × 160 cols = 51.2 GB FP8-class = **51.2B params**; BF16 doubles it (~95–100 GB observed, consistent). **Confidence:** high.

3. **Claim:** Model scale is ~125B total params, 6B active (MoE). **Sources:** [ninfer feature branch](https://github.com/lkarlslund/ninfer/tree/feat/qwen3-8-flash-next-125b-a6b) (branch name `qwen3-8-flash-next-125b-a6b`); r/LocalLLaMA commenter u/Zyj: "it only has 6b active parameters". **Support:** direct evidence (naming + community statement), cross-consistent with NVFP4 sizes (~78 GiB core ≈ 74B params at ~4.5 bits — plausible for ~125B total minus 51.2B table at NVFP4 if table excluded... see gap note). **Confidence:** medium. **Researcher inference:** BF16 full checkpoint (including BF16 table) is therefore ~2×125 GB ≈ 250 GB — does NOT fit the GB10's 128 GB unified pool even with nothing else resident; the original BF16 weights are a provenance/accuracy artifact, not a bench-run candidate on this node.

4. **Claim:** A large quant ecosystem derived from upstream weights exists, all implying an accessible original checkpoint. **Sources:** local captures + card cross-links: Unsloth UD-Q6_K_XL / IQ4 (RG_Fusion, r/LocalLLaMA setup thread), [wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16](https://huggingface.co/wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16), [VnimanieAI/Qwen3.8-Flash-Next-W4A16](https://huggingface.co/VnimanieAI/Qwen3.8-Flash-Next-W4A16) (discussion #4: AWQ keeps attention layers at bf16, which "stopped the over thinking"), [RadixArk/Qwen3.8-Flash-Next-NVFP4](https://huggingface.co/RadixArk/Qwen3.8-Flash-Next-NVFP4) (cnn_dailymail-calibrated), [nvidia/Qwen3.8-Flash-Next-NVFP4](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-NVFP4) (FP8 table, ships "its own table in FP8"), primitive-ai NVFP4 + mixed-NVFP4-FP8, [edougawa/Qwen3.8-Flash-Next-W4A16-PLE4-MTP-Spark](https://huggingface.co/edougawa/Qwen3.8-Flash-Next-W4A16-PLE4-MTP-Spark), [HamboneLabs-AI/Qwen3.8-Flash-Next-uint3-g64](https://huggingface.co/HamboneLabs-AI/Qwen3.8-Flash-Next-uint3-g64). **Support:** direct evidence of the derivatives; the upstream link is interpretation. **Confidence:** high that derivatives exist; medium that they all derive from a single canonical bf16 repo (vs each other).

5. **Claim (question 3):** Dequantizing the AWQ W4A16 checkpoint to bf16 as a benchmark reference — **no prior art found in local captures**; recorded as the fallback candidate per bench plan, NOT a verified candidate. **Support:** researcher inference. General AWQ dequant tooling exists in the ecosystem (autoawq `--skip-safetensors`/dequant paths, llm-compressor) [unverified for this checkpoint; web check needed]. Known accuracy fact (VnimanieAI discussion #4 via ArtfulGenie69): the W4A16 recipe's *bf16 attention layers* materially affect behavior ("stopped the over thinking"), so a dequantized-AWQ reference is NOT bit-equivalent to a true bf16 original — usable as a comparative oracle only, clearly labeled. Also unknown [unverified]: whether the wtdcode AWQ repo ships its own PLE table or relies on the primitive-ai sidecar/overlay (WonderRico's recipe mounted `ples_int4` separately, and the overlay stubs the checkpoint's own table tensors). **Confidence:** low-medium — needs parent verification before relying on it.

6. **Engine-side pointers relevant to R1:** model code lives at `vllm/models/qwen3_8_flash_next/` (vLLM image `vllm/vllm-openai:qwen38-flash-next`) and SGLang `qwen4_exp` (image `lmsysorg/sglang:qwen38flashnext`, branch qwen4-main-squashed, PRs #36497/#36556/#36531). MTP head ≈ 0.51 GB (Dull-Giraffe). **Support:** direct evidence from captures.

## Implications for the bench plan

- Do NOT plan a bf16-original run on the GB10: ~250 GB [inference] vs 128 GB unified pool — physically impossible. The bench matrix runs on quantized checkpoints (NVFP4/AWQ-W4A16 + PLE sidecar), which is what all captured community recipes do.
- R1's real deliverable is a *provenance/accuracy anchor*: once the parent verifies the canonical repo, capture its config.json (rope/YaRN for R3) and use it to judge quant accuracy deltas (the 98/100 AWQ recipe vs 91 RadixArk NVFP4, per WonderRico).
- Dequantized-AWQ-bf16 is only viable as an offline reference if parent-verified tooling exists; even then it stays OFF the bench node (size) and inherits the W4A16's bf16-attention asymmetry — treat as "candidate (offline only)" not "candidate (on-node)".
- The BF16 table itself (95.4 GB) is available without the original repo: it ships inside primitive-ai's NVFP4 repo as `ple-bf16-*` (128 shards) — but on GB10 use the quantized sidecars (ples_int4 32 GB / ples_nvfp4 28.8 GB) instead; BF16 table does not fit alongside anything on 128 GB.

## Open gaps for parent verification (web tools unavailable in this lane)

1. Does `https://huggingface.co/Qwen/Qwen3.8-Flash-Next` exist? Exact repo id, org, license, total download size, file listing, last-update date.
2. config.json of the canonical checkpoint: num hidden layers, full-attention layer count/fraction, rope/YaRN settings (needed by R3), MoE expert counts, MTP head config.
3. Whether the original repo ships the 51.2B PLE table in BF16 and its exact tensor name/shard layout.
4. Whether wtdcode AWQ W4A16 repo includes the PLE table (or BF16 attention layers as the VnimanieAI comment implies) — file listing + config.
5. Working AWQ→bf16 dequant tooling and any prior art of dequantizing this specific checkpoint.

## Sources
- Kept: primitive-ai/Qwen3.8-Flash-Next-PLE-quant model card (https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant) — primary statement that original BF16 tables exist + table geometry/sizes. (Existing capture: `primitive-aiQwen3.8-Flash-Next-PLE.md`; R1 extraction: `R1-ple-quant-card-evidence.md`.)
- Kept: r/LocalLLaMA 170K-context post (https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/) — shard structure of the NVFP4 repo incl. `ple-bf16-*`. (Existing capture + R1 extraction: `R1-nvfp4-shard-structure.md`.)
- Kept: r/LocalLLaMA "Fastest setup" thread — Unsloth quants, ninfer branch name, active-param count.
- Kept: r/LocalLLaMA 98/100 vLLM recipe thread — AWQ repo usage, VnimanieAI W4A16 accuracy discussion pointer.
- Rejected: Templates Comparison thread — chat-template topic, no R1 weight-provenance content beyond confirming RadixArk repo use.

## Next steps
Parent: fetch the HF model pages (Qwen/Qwen3.8-Flash-Next, wtdcode AWQ repo, VnimanieAI W4A16), verify items 1–5 above, update this digest; hand rope/YaRN values to R3.

---

## Parent verification addendum (2026-09-13, web-verified — resolves the lane's gaps)

1. **Canonical checkpoint — VERIFIED: https://huggingface.co/Qwen/Qwen3.8-Flash-Next** (official Qwen
   org; 624,390 downloads last month; full card captured in R1-hf-model-card.md). Post-trained
   weights in HF format, Transformers/vLLM/SGLang-compatible. 125B total / 6B active + 51B n-gram
   embedding + 4B MTP; dtype bfloat16 (config.json).
2. **S1-as-bf16 on the GB10 bench: NOT RUNNABLE — upgrade lane's inference to a finding.** bf16
   checkpoint ≈ 250 GB (125B params) vs 121.63 GiB unified pool; even weights-only don't fit, before
   PLE tables and KV. The official FP8 checkpoint is 172.78 GiB (forum datapoint) — also does not
   fit. ⇒ S1 (best reasoning) must ship as a quantized profile (AWQ W4A16, the 98/100 recipe) or a
   dequantized-AWQ reference documented as such; true-bf16 serves only as a provenance anchor.
3. **vLLM's own recipe starts at 4× GB300** (forum) — the model was never targeted at single-128GB
   by the vendor; every single-Spark recipe is community quant work (RadixArk/nvidia NVFP4,
   wtdcode AWQ).
4. wtdcode AWQ repo file listing + dequant prior art: still unverified, low priority — moot given
   finding 2 (S1 rides on AWQ, not on bf16).
