# Fastest qwen3.8 Flash Next Setup?

**Subreddit:** r/LocalLLaMA · **Author:** u/AppealSame4367 · **Score:** 3 · **Posted:** 2026-09-04

I'm currently running 3x slots 200k at iq4 with q8 kv cache, ik\_llama, on a rented rtx 6000 pro.

Prefill is somewhere at 2000 tps and decode at around 40 tps for single request.

2-4 Parallel: It goes down to 500-1000 tps prefill and 10-20 tps decode.

This is the best card it could run on apart from datacenter gpus and it runs... not very good?

I tried vllm recipes before, but that's 4-5 days ago.

What's the best current setup to run it with highest prefill + decode for 2-4 slots and q4 quants or better and q8 kv cache or better?

---

## Comments (26 captured)

[1] u/Turbulent-Alps4046 · 8 points
Don't use llama.cpp for Qwen 3.8 Flash Next. It has 5x worse performance than vLLM/SGLang currently.

Here is my SGLang setting for 10,000 t/s prefill, 170 t/s decode, 460k total context:  
\`\`\`  
python3 -m sglang.launch\_server \\

  \--model-path /models/RadixArk/Qwen3.8-Flash-Next-NVFP4 \\

  \--served-model-name Qwen/Qwen3.8-Flash-Next \\

  \--host [0.0.0.0](http://0.0.0.0) \--port 8000 \\

  \--enable-metrics \\

  \--enable-cache-report \\

  \--context-length 262144 \\

  \--quantization modelopt\_fp4 \\

  \--fp4-gemm-backend flashinfer\_cutlass \\

  \--attention-backend triton \\

  \--linear-attn-prefill-backend triton \\

  \--linear-attn-decode-backend flashinfer \\

  \--mamba-ssm-dtype bfloat16 \\

  \--page-size 64 \\

  \--ple-offload-embedding \\

  \--tp 1 \\

  \--trust-remote-code \\

  \--speculative-algorithm NEXTN \\

  \--speculative-num-steps 3 \\

  \--speculative-eagle-topk 1 \\

  \--speculative-num-draft-tokens 4 \\

  \--speculative-draft-model-quantization unquant \\

  \--max-mamba-cache-size 24 \\

  \--max-total-tokens 460000 \\

  \--kv-cache-dtype auto \\

  \--mem-fraction-static 0.975 \\

  \--chunked-prefill-size 4096 \\

  \--max-running-requests 4 \\

  \--mamba-radix-cache-strategy extra\_buffer \\

  \--mamba-track-interval 64 \\

  \--watchdog-timeout 1800 \\

  \--tool-call-parser qwen3\_coder \\

  \--reasoning-parser qwen3

\`\`\`

  [1.1] u/Turbulent-Alps4046 · 4 points
  If you want more 512k total context but slower decode, you can turn off MTP.  

  See my other post: [https://www.reddit.com/r/LocalLLM/comments/1vz20ap/qwen38flashnextnvfp4\_on\_single\_rtx\_pro\_6000\_120ts/](https://www.reddit.com/r/LocalLLM/comments/1vz20ap/qwen38flashnextnvfp4_on_single_rtx_pro_6000_120ts/)

  [1.2] u/AppealSame4367 · 2 points (OP)
  Okay, with your recipe I'm getting 90 TPS for a single slot. It can fit two slots, though. I've disabled MTP because of vision issues and such.

  Thanks!

  [1.3] u/AppealSame4367 · 1 point (OP)
  These are the values I'd want! Thank you

  [1.4] u/mvaranka · 1 point
  Thank you from me too, will try these. Currently running on vllm, slower.

  [1.5] u/nomorebuttsplz · 1 point
  thank you for this recipe! Holy shit my RTX 6000 pro is now basically unlimited Opus 4.5 or 4.6 at 100 t/s.

  What is your single concurrency decode speed? I am only getting about 100 but I think it might be because i am on windows with a linux vm

    [1.5.1] u/Turbulent-Alps4046 · 1 point
    I’m getting between 120-170 tps decode with MTP single concurrency.

[2] u/cibernox · 6 points
That seems suspiciously low for an rtx6000pro

  [2.1] u/Formal-Exam-8767 · 0 points
  Probably overflows into RAM.

[3] u/egnegn1 · 3 points
Post the command you used.

Apart from that the 96 GB are just a bit to small to run everything from VRAM. 

Did you try FreeToken? It manages the available VRAM and RAM better.

[4] u/OvertaxedOne · 3 points
This performance is terrible, you should be seeing several times that on your GPU.   My first stop would be vllm with a NVFP4 quant variant.

[5] u/Miserable-Dare5090 · 3 points
I’m getting 4000pp and 80tg with 2 CMP170s, at depth.

https://preview.redd.it/yvv7j7kqyhnh1.png?width=777&format=png&auto=webp&s=c855b13c9d56f56b2a2908eff96887c97d32c715

Concurrency is still pretty good at c4, about 38TG per request. Total around 100. Without MTP or optimization. 

About 1/10 the price of a 6000 each when I bought them. 

EDIT: Blue line is Flash Next as mentioned. Other lines are other LLMs on separate GPUs.

  [5.1] u/AppealSame4367 · 1 point (OP)
  cmp170 are really interesting cards. Guess they now cost almost as much :-D

  [5.2] u/Gnasherrr · 1 point
  waiting on waterblocks to get my 4x 170hx running. this is looking fast tho! btw are these on pcie 4x or 16x? TP or PP? care to share your recipe?

    [5.2.1] u/Miserable-Dare5090 · 1 point
    16x, but you need to go point your agent to github, to a repo you can search on google with “deepseek v4 cmp170” for your 4 card setup. Trust me, you will want to run deepseek flash vision. DS4F is perfect for these cards.

    My two cards are 2x16 with peer to peer enabled by firmware hacking: Deepseek V4 Flash on Hermes got serious, and unlocked the cards, tried a whole bunch of vLLM/A100/CMP170/170HX github forks I threw at it, took some patches from here and there, got peer to peer working on the cards, patched me the offloading ngram to disk for Qwen Flash Next, and then loaded the model on the two cards with 1M context (so 4 streams at 256K, c4 above) on TP2.

    That’s how excited you should be about it. Once you get deepseek on these cards following that github recipe, you can just ask it via hermes to load qwen flash next. But then you’ll need…MORE GPU…  
    it’s never enough my man.

    EDIT: for deepseek you’ll want to do PP4, the repo explains why. But they just maybe unlocked 3x16 on the cards? So maybe soon you’ll do TP4 with them

[6] u/RG_Fusion · 2 points
Something isn't right with this result. You should be doing much better than my system.

I have an AMD EPYC 7742 server with 512 GB of DDR4 and two RTX Pro 4500 Blackwell cards (64 GB).  
I'm currently getting 70 tok/s on the IQ4 Quantization without using MTP (single-user).

  [6.1] u/AppealSame4367 · 1 point (OP)
  Thank you, that's very helpful. Since I rent that card, I'd always prefer a cheaper setup with almost the same power.

  What prefill rates do you get?

    [6.1.1] u/RG_Fusion · 1 point
    When I fit the entire model into the GPUs, excluding the engrams, I'm seeing around 2,000 tok/s. Unfortunately, IQ4 only just barely fits in the GPUs and to go beyond 8k context I need to offload to RAM. Allowing some of the upper layers to offload to RAM, I can get the full available context size for the model. Running it like this, I get closer to 60 tok/s decode and 600 tok/s prefill.

    If I had one more additionaly GPU I would be able to get the full context without offloading, but realistically you'd actually want 4 GPUs to continue using tensor parrallel.

      [6.1.1.1] u/AppealSame4367 · 1 point (OP)
      I would have expected worse. 60 decode and 600 prefill is still alright for a partial offload to ram. Thx for the infos!

        [6.1.1.1.1] u/RG_Fusion · 1 point
        No problem.

        As a bit of additional info, I've been running the Unsloth UD-Q6\_K\_XL for most of my tasks. The IQ4 quant was just an experiment to see what would happen if the model was fully in VRAM.

        Running UD-Q6\_K\_XL I'm getting 30 tok/s decode and 500 tok/s prefill.

          [6.1.1.1.1.1] u/AppealSame4367 · 1 point (OP)
          I'm still pretty new to q3.8 flash next. Did you notice proper intelligence differences between q4 and q6?

            [6.1.1.1.1.1.1] u/RG_Fusion · 2 points
            Between UD-Q4_K_XL and UD-Q6_K_XL I'm not seeing much of a difference. Q6 might be slightly more attentive?

            However, I am seeing a pretty big difference between IQ4 and UD-Q6_K_XL. So it seems important not to over-quantize the model.

            My recommendation is to not go below UD-Q4_K_XL.

[7] u/lkarlslund · 2 points
You might want to take my feature branch for Ninfer for a spin - beats VLLM on my rig. "Works for me" status, feedback welcome. 95GB VRAM at 256K context + 51GB ngram mmap \~12K PP and 100-200TG with MTP3 and vision.

[https://github.com/lkarlslund/ninfer/tree/feat/qwen3-8-flash-next-125b-a6b](https://github.com/lkarlslund/ninfer/tree/feat/qwen3-8-flash-next-125b-a6b)

  [7.1] u/AppealSame4367 · 1 point (OP)
  But it's single stream, right?

  I mean, the numbers are very very good. Might be worth it to just do one thing after another then.

  Thank you!

  Edit: Config reads --max-concurrency 2, so I guess it's 2 in parallel

    [7.1.1] u/lkarlslund · 1 point
    Yes, Ninfer is single stream. If you want multi stream, stick to VLLM.

[8] u/AI_spell · 2 points
On a single 6000 Pro I'd start with a 4-bit AWQ or GPTQ build in vLLM or SGLang and leave a few GB of VRAM headroom instead of trying to fill the card. Keep the context around 32k to start, then raise it only if you need it, since KV cache can eat the gain fast. Benchmark prompt and decode separately at your real batch size, because the headline tok/s usually assumes a tiny prompt.
