# R5 capture — SGLang NVFP4 recipe, 460k context, 10k prefill / 170 t/s decode (Turbulent-Alps4046)

**Source:** https://www.reddit.com/r/LocalLLaMA/comments/1nsqf1c/ (thread: "Fastest qwen3.8 Flash Next Setup?", u/AppealSame4367, 2026-09-04 — SGLang recipe is comment [1] by u/Turbulent-Alps4046)
**Captured:** 2026-09 (from local evidence file `fastest-qwen3-8-flash-next-setup.md`)

## Comment [1] — u/Turbulent-Alps4046 (8 points)

> Don't use llama.cpp for Qwen 3.8 Flash Next. It has 5x worse performance than vLLM/SGLang currently.
>
> Here is my SGLang setting for 10,000 t/s prefill, 170 t/s decode, 460k total context:

```
python3 -m sglang.launch_server \
  --model-path /models/RadixArk/Qwen3.8-Flash-Next-NVFP4 \
  --served-model-name Qwen/Qwen3.8-Flash-Next \
  --host 0.0.0.0 --port 8000 \
  --enable-metrics \
  --enable-cache-report \
  --context-length 262144 \
  --quantization modelopt_fp4 \
  --fp4-gemm-backend flashinfer_cutlass \
  --attention-backend triton \
  --linear-attn-prefill-backend triton \
  --linear-attn-decode-backend flashinfer \
  --mamba-ssm-dtype bfloat16 \
  --page-size 64 \
  --ple-offload-embedding \
  --tp 1 \
  --trust-remote-code \
  --speculative-algorithm NEXTN \
  --speculative-num-steps 3 \
  --speculative-eagle-topk 1 \
  --speculative-num-draft-tokens 4 \
  --speculative-draft-model-quantization unquant \
  --max-mamba-cache-size 24 \
  --max-total-tokens 460000 \
  --kv-cache-dtype auto \
  --mem-fraction-static 0.975 \
  --chunked-prefill-size 4096 \
  --max-running-requests 4 \
  --mamba-radix-cache-strategy extra_buffer \
  --mamba-track-interval 64 \
  --watchdog-timeout 1800 \
  --tool-call-parser qwen3_coder \
  --reasoning-parser qwen3
```

> [1.1] If you want more 512k total context but slower decode, you can turn off MTP. See my other post:
> https://www.reddit.com/r/LocalLLM/comments/1vz20ap/qwen38flashnextnvfp4_on_single_rtx_pro_6000_120ts/
> [1.5.1] I'm getting between 120-170 tps decode with MTP single concurrency.

Reproduction [1.2]: OP reports 90 t/s single slot with the recipe (MTP disabled for vision issues), two slots fit on the 96 GB card.

## Why this capture matters
- Complete, community-reproduced SGLang launch config for this model: every long-context and mamba-cache flag in one place (`--max-total-tokens 460000` vs `--context-length 262144`, `--max-mamba-cache-size 24`, `--mamba-radix-cache-strategy extra_buffer`, `--mamba-track-interval 64`, `--mamba-ssm-dtype bfloat16`, NEXTN MTP spec flags).
- Headline numbers on 1× RTX 6000 Pro (96 GB, GDDR7): ~10k tok/s prefill, 120–170 tok/s decode, 460k total context; MTP-off variant reaches 512k total context at ~120 t/s.
- Uses `--ple-offload-embedding` (n-gram table → host RAM pinned) — semantics change on a unified-memory GB10 pool.
- Uses RadixArk NVFP4 checkpoint (the one with the cnn_dailymail calibration critique — cross-reference R4/R2).
