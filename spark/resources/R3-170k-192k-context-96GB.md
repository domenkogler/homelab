# R3 capture — 170K/192K long-context runs on a single 96 GB card (vLLM + SGLang configs, quality reports)

**Source thread:** "Qwen3.8-Flash-Next at 170K context on a single 96 GB card. ~110 tok/s." — r/LocalLLaMA, u/UltrMgns, 2026-08-30
**Source URL:** https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/qwen38flashnext_at_170k_context_on_a_single_96_gb/
**Captured:** 2026-09 (excerpt of local capture; R3-relevant content only)

---

## OP run (vLLM): u/UltrMgns, 22 upvotes

- Quantized n-gram PLE to INT4 (32 GB), memory-mapped from disk; checkpoint primitive-ai/Qwen3.8-Flash-Next-NVFP4 with `ple-bf16-*` shards excluded (index trimmed of 128 `ngram_embedding` entries).
- "I confirmed that it works great on 150-160k context … The quality is there guys…"
- "76–125 tok/s single stream. The spread is MTP acceptance: ~87% on code and JSON, ~40% on just talking. Prefix caching hits 90%+ on a long horizon task. ~89 GB VRAM, ~33 GB page cache, 165-170K context, one GPU."
- Decisive vLLM flags (k8s Deployment args): `--max-model-len 173400`, `--gpu-memory-utilization 0.95`, `--kv-cache-dtype auto`, `--max-num-seqs 4`, `--max-num-batched-tokens 16384`, `--speculative-config '{"method":"mtp","num_speculative_tokens":3}'`, `--distributed-executor-backend mp`, PLE env: `VLLM_PLE_CPU_OFFLOAD=1`, `VLLM_PLE_QUANT_DIR=/model/ples_int4`.

**R3 notes (annotator):** no rope-scaling flag; per-request context limited to 173,400 by KV + draft head on 96 GB.

## Decisive SGLang comment: u/Dull-Giraffe (8 points)

> SGLang is fastest for me: at real context depths: 150-160 tok/s narrative, 200-215 tok/s code,
> 192k context, spec tokens=3. MTP acceptance is good. It's nearly free: the MTP head lands at 0.51 GB in VRAM and the KV pool is unchanged, so speculation costs no context.
>
> SGLang PR #36556 needed to be included.

Follow-up detail (same user):

> PR #36497: Yes, but not as a patch — it's baked into the image. I run lmsysorg/sglang:qwen38flashnext, the day-0 preview tag (pushed 2026-08-26, branch qwen4-main-squashed) that carries the still-unmerged model support from #36497. Stable v0.5.18 doesn't have qwen4_exp and fails with an unknown model type. On top of that image I apply PR #36556 at container start — on sm_120 that one is not optional: without the full fix, QSA decode boots and passes a smoke test, then silently emits token ID 0 (!!!!) past the first KV page (~position 65 at page-size 64). If you only fix the varlen fallback crash from #36531, you get exactly that trap.
>
> RAM: two budgets.
> - GPU: 78.2 GiB of the 96 GB card — 68 GB NVFP4 routed experts + 16 GB BF16 everything-else — leaving ~17 GiB for KV + GDN state at 196K context.
> - Host: ~51.2 GB of pinned memory for the FP8 n-gram table via --ple-offload-embedding (that flag is load-bearing; without it the table goes to VRAM and nothing fits). Budget ~55–60 GB for the container overall, plus --shm-size 16g. --ulimit memlock=-1 is mandatory — any memlock ceiling below the table size fails the pin.

**R3 notes (annotator):** #36556 = https://github.com/sgl-project/sglang/pull/36556 ; #36497 = https://github.com/sgl-project/sglang/pull/36497 ; silent-corruption trap is a benchmark-validity risk on sm_120 — sm_121 parity unverified.

## Full-native-context enabler: u/ForestoShen

> You should be able to push the context limit to full 262k by using fp8 mtp quant, the acceptance rate seems mostly unaffected to me. I'm running on sglang though, not sure how vllm would handle it.

Dull-Giraffe reply: stayed with BF16 MTP @ 192k for stability.

## Other model-card corroboration (from primitive-ai PLE card, locally captured)

- "at the native 262,144 context with MTP the KV cache needs 7.57 GiB where 5.95 GiB is left after the draft head" (96 GB card at 0.92 utilization) → why vLLM runs sit at 135k–173k with MTP on.
- Marzero 64 GB-host field report: `--max-model-len 135168 --max-num-seqs 64`, MTP 3 → decode 102/140/99 tok/s at 1k/8k/32k input; "KV pool 217k tokens with MTP (503k without)".
