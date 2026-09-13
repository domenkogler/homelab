# R5 capture — SGLang day-0 image, PR #36556, BF16 KV @192k, FP8 n-gram pinned (Dull-Giraffe)

**Source:** https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/qwen38flashnext_at_170k_context_on_a_single_96_gb/
(Thread: "Qwen3.8-Flash-Next at 170K context on a single 96 GB card. ~110 tok/s", u/UltrMgns, 2026-08-30 — SGLang content is in the comment tree, mainly u/Dull-Giraffe)
**Captured:** 2026-09 (from local evidence file `Qwen3.8-Flash-Next at 170K context on a single 96 GB card 110 t-s.md`)

## SGLang-relevant content (Dull-Giraffe, 2026-08-30)

> SGLang is fastest for me: at real context depths:
> 150-160 tok/s  narrative,
> 200-215 tok/s code,
>
> 192k context, spec tokens=3. MTP acceptance is good. It's nearly free: the MTP head lands at 0.51 GB in VRAM and the KV pool is unchanged, so speculation costs no context.
>
> SGLang PR #36556 needed to be included.
>
> This is single RTX6000Pro card, in a modern intel desktop system.

Reply to u/live4evrr (question: "Did you also include PR #36497? How much RAM does this take up? During initialization using Radixark nvfp4 it freezes up for me"):

> PR #36497: Yes, but not as a patch — it's baked into the image. I run lmsysorg/sglang:qwen38flashnext, the day-0 preview tag (pushed 2026-08-26, branch qwen4-main-squashed) that carries the still-unmerged model support from #36497. Stable v0.5.18 doesn't have qwen4_exp and fails with an unknown model type. On top of that image I apply PR #36556 at container start — on sm_120 that one is not optional: without the full fix, QSA decode boots and passes a smoke test, then silently emits token ID 0 (!!!!) past the first KV page (~position 65 at page-size 64). If you only fix the varlen fallback crash from #36531, you get exactly that trap.
>
> RAM: two budgets.
>
> - GPU: 78.2 GiB of the 96 GB card — 68 GB NVFP4 routed experts + 16 GB BF16 everything-else — leaving ~17 GiB for KV + GDN state at 196K context.
>
> - Host: ~51.2 GB of pinned memory for the FP8 n-gram table via --ple-offload-embedding (that flag is load-bearing; without it the table goes to VRAM and nothing fits). Budget ~55–60 GB for the container overall, plus --shm-size 16g. --ulimit memlock=-1 is mandatory — any memlock ceiling below the table size fails the pin.

Further exchange:

> **u/ForestoShen:** You should be able to push the context limit to full 262k by using fp8 mtp quant, the acceptance rate seems mostly unaffected to me. I'm running on sglang though, not sure how vllm would handle it.
>
> **u/Dull-Giraffe:** I'm on SGLang too - keen to hear how you find fp8 as you use it more. I've stayed with BF16 @ 192k for flash next, and made sure it's solid at that. My tests take hours to run so can only change so many things each day!

> **u/AdSafe4047:** there is a sglang fork that runs nvfp4 with q8 cache quant where you can put 3x256k cache + vision + mtp - it flies. Compared to qwen 27b fp8 bv16 it beats it in my benchmark suite.

## Why this capture matters
- Names the ONLY known SGLang artifact for this model: day-0 image `lmsysorg/sglang:qwen38flashnext` (2026-08-26, branch qwen4-main-squashed) + PR #36497 baked in + PR #36556 applied at start.
- Documents the sm_120 silent token-ID-0 failure mode of missing #36556 (correctness-critical; sm_121/GB10 status unverified).
- Confirms BF16 KV at 192k on SGLang and the full memory budget split (weights / KV+GDN state / pinned FP8 PLE table).
- SGLang-vs-vLLM-at-depth datapoint: 150–215 tok/s on SGLang at real depth, single RTX 6000 Pro.
