# R3 — Native and extended context: what is possible and with which config?

**Question ID:** R3 · **Date:** 2026-09 · **Model in scope:** Qwen/Qwen3.8-Flash-Next (hybrid GDN + partial full attention, MoE, MTP)
**Question in one line:** What context lengths are achievable for Qwen3.8-Flash-Next on a DGX Spark-class (GB10, sm_121, 128 GB unified) node, and with which exact config?

**VERDICT: PARTIAL** — native 262,144 and the decisive SGLang/vLLM context configs are confirmed from local captures; config.json (rope_theta / rope_scaling / max_position_embeddings), the GDN-rope-scaling architectural question, and 256k/512k needle-test quality data are open gaps for parent verification (no web tools in this lane).

## Findings

1. **Claim:** Native context is 262,144 tokens and is runnable end-to-end by the community. **Sources:** [HeDo88TH templates thread](https://www.reddit.com/r/LocalLLaMA/comments/1w84mod/qwen38_flash_next_templates_comparison/) ("Full 262K context", SGLang, jpezzulli/sglang-rtxpro6000 container, BF16 KV, 51.2 GB FP8 PLE in RAM + 32 GB HiCache); [Turbulent-Alps4046 recipe](https://www.reddit.com/r/LocalLLaMA/comments/1w3lxoe/ — see capture R3-sglang-460k-total-tokens-config.md) runs `--context-length 262144`; primitive-ai PLE card: "at the native 262,144 context with MTP the KV cache needs 7.57 GiB where 5.95 GiB is left after the draft head" (96 GB card). **Support:** direct evidence. **Confidence:** high.

2. **Claim:** The widely-shared SGLang "460k" recipe uses **no rope scaling** — it is a KV-pool budget setting, not a per-request context extension. **Sources:** Turbulent-Alps4046 config (captured in R3-sglang-460k-total-tokens-config.md): `--context-length 262144 --max-total-tokens 460000 --max-mamba-cache-size 24 --mamba-ssm-dtype bfloat16 --mamba-radix-cache-strategy extra_buffer --mamba-track-interval 64 --mem-fraction-static 0.975 --page-size 64`. **Support:** direct evidence for the flags; **researcher inference** for the semantics: since `--context-length` stays at 262,144, no single request can exceed native context — `--max-total-tokens 460000` sizes the KV pool (total tokens across requests + prefix cache), which is the natural way to exploit the fact that only the full-attention fraction scales with context. **Confidence:** high for the flags, medium for the semantics interpretation (no SGLang doc captured).

3. **Claim:** "512k total context with MTP off, slower decode" — same poster, same thread. **Source:** Turbulent-Alps4046 reply linking [the 120 t/s RTX Pro 6000 post](https://www.reddit.com/r/LocalLLM/comments/1vz20ap/qwen38flashnextnvfp4_on_single_rtx_pro_6000_120ts/). **Support:** direct quote of the claim ("If you want more 512k total context but slower decode, you can turn off MTP"); consistent with Marzero's measured KV pool of 217k tokens with MTP vs **503k without** on the same 96 GB card (primitive-ai PLE card field report). **Confidence:** medium (claim not independently reproduced in captures).

4. **Claim:** vLLM per-request long-context runs are capped well below native by KV + draft-head memory on 96 GB cards; the primitive-ai card quantifies it: at native 262,144 with MTP the KV cache needs 7.57 GiB vs 5.95 GiB left after the draft head → community vLLM runs use `--max-model-len` 32,768 (primitive-ai measured table), 135,168 with MTP / KV pool 217k with MTP vs 503k without (Marzero field report), 150,000 (WonderRico), 173,400 (UltrMgns 170K thread). Turning MTP off or capping `--max-num-seqs` frees the headroom for the full 262,144. **Sources:** [primitive-ai PLE card](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant); [170K thread](https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/qwen38flashnext_at_170k_context_on_a_single_96_gb/). **Support:** direct evidence. **Confidence:** high.

5. **Claim:** On the 128 GB unified-pool GB10 target, the binding constraint is KV-pool + mamba-state budget, not rope; MTP-off is the lever that roughly doubles usable KV pool (217k → 503k on a 96 GB card per Marzero). **Sources:** primitive-ai PLE card, Marzero field report. **Support:** direct evidence for the numbers; researcher inference for the GB10 projection. **Confidence:** medium.

6. **Claim (unverified):** 1M context on 2× CMP170 (170HX) TP2 with a patched vLLM fork ("patched me the offloading ngram to disk … loaded the model on the two cards with 1M context (so 4 streams at 256K, c4 above) on TP2") — u/Miserable-Dare5090. Note "4 streams at 256K": even here 1M is pool across 4 streams, not a single 1M request. **Source:** captured in R3-sglang-460k-total-tokens-config.md (from the "Fastest setup" thread). **Support:** community claim only, no logs; patched/forked stack. **Confidence:** low.

7. **Claim:** SGLang long-context operation on this model needs specific patches/flags: image `lmsysorg/sglang:qwen38flashnext` (carries unmerged model support, PR [#36497](https://github.com/sgl-project/sglang/pull/36497)); PR [#36556](https://github.com/sgl-project/sglang/pull/36556) is mandatory on sm_120 — without it, "QSA decode … silently emits token ID 0 past the first KV page (~position 65 at page-size 64)". Dull-Giraffe ran 192k context, MTP 3, MTP head 0.51 GB, KV pool unchanged by speculation. ForestoShen: fp8 MTP quant enables full 262k on SGLang. **Sources:** 170K thread comments (captured in R3-170k-192k-context-96GB.md). **Support:** direct evidence. **Confidence:** medium-high (sm_120; sm_121 parity unverified).

8. **Claim:** Long-context quality at depth: full-262K SGLang setup scored 99/100 on SWE-bench Verified slice 0:100 (stock template, xhigh effort) — indirect evidence that quality holds at full native context. 170K-thread OP: "confirmed that it works great on 150-160k context … The quality is there". **No needle-in-haystack / RULER numbers at 256k/512k found anywhere in the captures.** **Sources:** templates thread; 170K thread. **Support:** direct evidence for the SWE-bench number; absence noted for needle tests. **Confidence:** medium.

## SGLang vs vLLM flag semantics (as evidenced in the captures)

- vLLM `--max-model-len` = per-request ceiling; must be ≤ native 262,144 (all working vLLM configs set it explicitly: 32,768 / 135,168 / 150,000 / 173,400).
- SGLang `--context-length` = per-request ceiling (262,144 in the 460k recipe); `--max-total-tokens` = total KV-pool token budget (460,000 / 512,000 claims).
- GDN state is budgeted separately from KV: SGLang `--max-mamba-cache-size 24` (number of concurrent mamba state blocks → caps `--max-running-requests`), `--mamba-ssm-dtype bfloat16`, `--mamba-radix-cache-strategy extra_buffer`, `--mamba-track-interval 64`. On vLLM the analogous failure is documented by primitive-ai: image default `--max-num-seqs` 1024 exceeds the Mamba state blocks at 0.92 utilization (598) → CUDA graph capture aborts.
- **No rope-scaling / YaRN flag appears in any working long-context config captured** (460k SGLang, 173k vLLM, 192k SGLang, 262k SGLang).

## The key architectural question — recorded, not resolved

For hybrid GDN models the linear-attention layers carry constant-size state per sequence, so context extension beyond native should in principle be purely a KV-pool/memory question (only the full-attention fraction's KV scales with tokens), and the observed rope-scaling-free 460k/512k runs are consistent with that. **But this is inference, not verified documentation**: no captured SGLang/vLLM doc or issue states it for the Qwen3-Next family, and the model's config.json (rope_theta, rope_scaling/YaRN, max_position_embeddings) was not fetchable in this lane. Parent must verify before the bench plan commits to >262k runs.

## Implications for the bench plan (GB10 / 128 GB unified)

- Bench the **native 262,144** single-stream as the primary context point — twice community-proven, no rope tricks needed.
- Expect MTP-off to be required (or `--max-num-seqs` small) to hit 262,144 with headroom; MTP-off costs decode speed (claim: still ~90 t/s class on smaller cards) but frees ~2.3× KV pool.
- Unified 128 GB pool removes the host-RAM vs VRAM split that shaped the 96 GB-card recipes; PLE-quant (int4, 32 GB, mmapped) keeps host cost to page cache. A >262k pool (e.g. 460k–500k total tokens) is plausible but only useful as concurrency/prefix-cache budget, not single-request context, unless the config.json question resolves favorably.
- SGLang on sm_121: verify the qwen38flashnext image builds/runs for sm_121 and carries the #36556 fix; the silent token-ID-0 corruption trap is a benchmark-validity risk, not just a perf issue.

## Open gaps for parent verification (web-dependent, unverified in this lane)

1. **config.json of Qwen/Qwen3.8-Flash-Next** (and/or wtdcode AWQ repo): rope_theta, rope_scaling (YaRN? factor? original_max_position_embeddings?), max_position_embeddings. Fetch: https://huggingface.co/Qwen/Qwen3.8-Flash-Next/resolve/main/config.json
2. **Whether GDN context extension needs rope scaling at all** — SGLang/vLLM docs/issues for Qwen3-Next-family: search "Qwen3-Next long context YaRN", vllm qwen3_next model docs, sglang hybrid_linear_attn docs.
3. **Needle-test / long-context quality at 256k/512k** for this model — none found in captures.
4. **Whether SGLang accepts `--context-length` > 262,144 on this model without rope scaling** (the 512k claim may be pool-only).
5. **1M-context CMP170 claim** — unverified, forked stack, likely pool-not-request.

## Sources used

- Local captures (mined): fastest-qwen3-8-flash-next-setup.md; primitive-aiQwen3.8-Flash-Next-PLE.md; "Qwen3.8-Flash-Next at 170K context…110 t-s.md"; "Qwen3.8 Flash Next - Templates Comparison.md"; "vLLM based recipe … 98-100.md".
- New captures written this lane: R3-sglang-460k-total-tokens-config.md, R3-170k-192k-context-96GB.md (excerpts of the two decisive long-context community configs).
- No new web sources were fetchable (no web tools in this lane runtime) — disclosed per supervisor policy.

---

## Parent verification addendum (2026-09-13, web-verified — resolves the lane's missing-evidence list)

1. **config.json — VERIFIED** (fetched raw from https://huggingface.co/Qwen/Qwen3.8-Flash-Next/resolve/main/config.json,
   full capture in R1-hf-model-card.md):
   - max_position_embeddings: **262144**; rope_parameters: { rope_type: **"default"**, rope_theta: **10000000**,
     partial_rotary_factor: 0.25, mrope_interleaved: true, mrope_section: [11,11,10] } — NO YaRN in checkpoint.
   - full_attention_interval: 4 → 36 linear + 12 full layers (3:1); mtp: 1 layer, rope_theta 1e7;
     mamba_ssm_dtype float32; MoE 512 experts / 10+1 active; indexer_budget 2048.
2. **Official context-extension statement — VERIFIED** (HF model card): "Context Length: 262,144
   natively and extensible up to **1,000,000** tokens." Official YaRN recipe (rope_type yarn,
   factor 4.0, original_max_position_embeddings 262144) with exact vLLM `--hf-overrides` and SGLang
   `--json-model-override-args` commands, plus guidance: static YaRN costs short-context quality —
   use factor 2.0 for ~512k-typical workloads. ⇒ **R3 verdict: GREEN.** 256k = native, no overrides;
   512k = YaRN factor 2.0 (or native + big pool per the 460k SGLang run); 1M = YaRN factor 4.0,
   officially supported; madeye demonstrates 524,288 on a single Spark (serve-500k.sh).
3. **Architectural question resolved (official docs):** >262k operation = YaRN rope scaling + memory
   budget. Note the observed 460k SGLang run used --context-length 262144 (per-request cap) with
   460k *pool* — i.e., that datapoint is concurrency pool, NOT per-request >262k. Per-request >262k
   requires the YaRN overrides. Both semantics matter for S4/S5.
4. **Long-context quality: VERIFIED at depth** — hashd1ve: exact needle retrieval 4/4 at 120k,
   190k AND 210k on GB10 with the #36845 Triton varlen path (after fixing the XQA corruption:
   1/4–4/4 requests silently corrupted at ≥120k via the wrong kernel — a MUST-check in our bench:
   long-context accuracy is kernel-path-dependent on GB10). Full-262K SWE-bench 99/100 (x86).
