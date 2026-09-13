# R3 capture — SGLang 460k-total-tokens config (no rope scaling) + 512k claim + 1M claim

**Source thread:** "Fastest qwen3.8 Flash Next Setup?" — r/LocalLLaMA, u/AppealSame4367, 2026-09-04
**Source URL:** https://www.reddit.com/r/LocalLLaMA/comments/ (thread captured locally as fastest-qwen3-8-flash-next-setup.md)
**Captured:** 2026-09 (excerpt of local capture; R3-relevant content only)

---

## Decisive config: u/Turbulent-Alps4046 (8 points)

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

**R3 notes (annotator):** NO `--rope-scaling` / YaRN flag present. `--context-length 262144` caps per-request at native; `--max-total-tokens 460000` is the KV-pool budget. GDN state budgeted separately via `--max-mamba-cache-size 24` (= `--max-running-requests 4` with headroom).

## Follow-up: 512k claim

u/Turbulent-Alps4046 (4 points):

> If you want more 512k total context but slower decode, you can turn off MTP.
> See my other post: https://www.reddit.com/r/LocalLLM/comments/1vz20ap/qwen38flashnextnvfp4_on_single_rtx_pro_6000_120ts/

OP confirmation (u/AppealSame4367): "with your recipe I'm getting 90 TPS for a single slot. It can fit two slots, though. I've disabled MTP because of vision issues and such." And: "I'm getting between 120-170 tps decode with MTP single concurrency." (Turbulent-Alps4046)

## 1M-context claim (unverified): u/Miserable-Dare5090 (3 points)

> I'm getting 4000pp and 80tg with 2 CMP170s, at depth. […] Concurrency is still pretty good at c4, about 38TG per request. Total around 100. Without MTP or optimization.

> My two cards are 2x16 with peer to peer enabled by firmware hacking: […] took some patches from here and there, got peer to peer working on the cards, patched me the offloading ngram to disk for Qwen Flash Next, and then loaded the model on the two cards with 1M context (so 4 streams at 256K, c4 above) on TP2.

**R3 notes (annotator):** forked/patched vLLM stack, no logs, and "1M context (so 4 streams at 256K)" again reads as pool capacity across 4 streams, not a single 1M request. Unverified.
