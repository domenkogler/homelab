## [](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant#qwen38-flash-next-quantized-ple-tables)Qwen3.8-Flash-Next quantized PLE tables

The 51.2B-parameter n-gram (PLE) table is the reason this model wants ~100 GB of free host RAM: the CPU-offload worker holds it in BF16 (95.4 GB). This repo ships the same table quantized — **FP8 per-row (49 GB)**, **INT4 group-16 (32 GB)**, and **NVFP4-style group-16 e2m1 (28.8 GB)** — plus a two-file overlay for the `vllm/vllm-openai:qwen38-flash-next` image that serves them memory-mapped straight from disk. Host RAM cost becomes page cache only, reclaimable under pressure.

Built from the original BF16 tables, so it works with any checkpoint of this model: [our mixed NVFP4/FP8 build](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-mixed-NVFP4-FP8), [our plain NVFP4](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-NVFP4), the original model, and, since 2026-09-06, checkpoints that ship their own table in FP8. The overlay stubs the table parameter and serves gathers from the sidecar, so the checkpoint's own table tensors are dropped before they load. That turns the table format into a non-issue: [nvidia's NVFP4 build](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-NVFP4), whose card documents an 8-GPU deployment because its FP8 table cannot use vLLM's BF16-only host offload, boots on one 96 GB card this way (234 s, 88,828 MiB, 348k-token KV pool) and scores 92.1 knowledge / 78.3 tool-calling under our protocol. Its 53.7 GB table-and-MTP shard can be skipped at download time.

## [](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant#serve)Serve

```bash
hf download primitive-ai/Qwen3.8-Flash-Next-PLE-quant \
  worker_image_quant.py ple_layer_quant.py --local-dir .
hf download primitive-ai/Qwen3.8-Flash-Next-PLE-quant --include "ples_int4/*" --local-dir .
# (or ples_fp8/* for the FP8 table)

docker run --gpus all --ipc=host -p 8000:8000 \
  -v $PWD/worker_image_quant.py:/usr/local/lib/python3.12/dist-packages/vllm/v1/ple_offload/worker.py:ro \
  -v $PWD/ple_layer_quant.py:/usr/local/lib/python3.12/dist-packages/vllm/models/qwen3_8_flash_next/nvidia/ple_layer.py:ro \
  -v $PWD/ples_int4:/ples_int4 -e VLLM_PLE_QUANT_DIR=/ples_int4 \
  -e VLLM_PLE_CPU_OFFLOAD=1 -e VLLM_PLE_OFFLOAD_READY_TIMEOUT=3600 \
  -e VLLM_GDN_DECODE_KERNEL=triton \
  vllm/vllm-openai:qwen38-flash-next \
  --model primitive-ai/Qwen3.8-Flash-Next-mixed-NVFP4-FP8 \
  --distributed-executor-backend mp \
  --gpu-memory-utilization 0.92 \
  --max-model-len 32768 --max-num-seqs 36 \
  --enable-auto-tool-choice --tool-call-parser qwen3_coder \
  --reasoning-parser qwen3
```

Drop `-e VLLM_GDN_DECODE_KERNEL=triton` when serving the plain NVFP4 build. No container memory cap needed: unlike the BF16 disk path, the quantized tables fit the page cache next to checkpoint streaming. Two flags were added to the block on 2026-09-06 after a field report, and both failures reproduce on our box: the image's default `--max-num-seqs` (1024) exceeds the Mamba state blocks left at 0.92 utilization (598) and CUDA graph capture aborts, and at the native 262,144 context with MTP the KV cache needs 7.57 GiB where 5.95 GiB is left after the draft head. 32,768 / 36 is what the table below was measured with; the report ran 135,168 / 64 with MTP.

Hosts with less than about 100 GB of RAM plus swap: the `ple_layer_quant.py` in this repo since 2026-09-06 builds the 95 GB table parameter on the meta device, so the offload worker no longer requests that allocation and `vm.overcommit_memory` can stay at its default. Before that revision the worker constructed the BF16 parameter first and the kernel's heuristic refused it (`DefaultCPUAllocator: can't allocate memory: you tried to allocate 102400491520 bytes`), which a 64 GB host reported and we reproduced under an emulated 67 GiB commit limit; the revised file boots under the same limit and scores 77.0 (three runs: 76.0, 76.0, 79.0, against 78.2 for the same table with the previous overlay) on the tool-calling suite. The reporter then confirmed it on the real machine (64 GB, CommitLimit 40 GiB, kernel-default overcommit): 341 s to healthy, KV pool unchanged at 216,778 tokens, host RAM about 10 GB, with the previous overlay still failing in the same session ([log](https://github.com/MarcoPizeta/flash-next-rtxpro6000-bench/blob/main/logs/test-revised-ple-overlay-no-overcommit-20260906.log)). Re-download the overlay if yours predates 2026-09-06. The BF16 disk overlay on the model cards still needs `sysctl vm.overcommit_memory=1` on such hosts.

## [](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant#measured)Measured

One RTX PRO 6000 Blackwell (96 GB), 176 GB host, local NVMe, mixed NVFP4/FP8 checkpoint. Throughput: 8K in / 512 out, prefix-cache-free, two seeds (shown a / b). Accuracy: the same pinned 1,170-item knowledge + 200-item tool-calling protocol as the model cards, thinking on.

|table|size|host RSS|boot|tok/s @ 1|tok/s @ 32|TTFT @ 1|knowledge|tool-calling (n=3)|
|---|---|---|---|---|---|---|---|---|
|BF16, in RAM (baseline)|95.4 GB|~95 GB|302 s|84.5 / 84.4|516.8 / 523.6|569 / 573 ms|92.2|79.2|
|FP8 per-row, mmapped|49 GB|52.6 GB°|364 s|80.3 / 80.1|489.7 / 500.7|759 / 768 ms|92.2|77.7|
|INT4 group-16, mmapped|32 GB|32.9 GB°|333 s|80.2 / 80.1|483.6 / 487.9|663 / 671 ms|92.9|78.2|
|NVFP4 group-16 e2m1, mmapped|28.8 GB|29.8 GB°|417 s|80.3 / 80.1|476.8 / 479.5|648 / 656 ms|92.2|78.7|

° mapped file pages, reclaimable under memory pressure — not anonymous RAM. Tool-calling is the pooled 200-item suite, mean of three runs per format (suite repeat spread ±1.5; all four formats sit in one band). Generation-sanity gates passed on every configuration.

Validated end to end inside a **48 GB container** (INT4 table): sanity PASS, tool-calling 80.5, 79.4 tok/s @ 1 and 486 @ 32 — within noise of uncapped. The cap was a cgroup limit on a 176 GB host; a real 64 GB host also needs the current overlay revision (or the `vm.overcommit_memory` setting) from the serve section.

**Field report, 64 GB host.** [Marzero](https://github.com/MarcoPizeta/flash-next-rtxpro6000-bench) ran this INT4 table with the mixed checkpoint on one RTX PRO 6000 and 64 GB of DDR5 (60.9 GiB usable), MTP 3, `--max-model-len 135168 --max-num-seqs 64`: decode with MTP 102 / 140 / 99 tok/s at 1k / 8k / 32k input single-stream and 296 / 282 / 151 at concurrency 4, prefill about 28k tok/s from 8k to 128k, host RAM 10 to 12 GB, KV pool 217k tokens with MTP (503k without), 2.1 to 2.3 Wh per 1k output tokens, all 32k x 16 requests served. Their protocol, their box; the raw JSON and scripts are in the repo. One operational note from the same run: the offload worker keeps three cores in a busy loop, which pushed an air-cooled Threadripper to 95 °C until clocks were capped at 4.5 GHz.

## [](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant#format)Format

Sidecars are 128 shard files (`shard_N.safetensors`, 2,500,012 rows each, concatenated in shard order) plus `META.json`. Row width 160.

|variant|tensors per shard|dequant|
|---|---|---|
|`ples_fp8`|`weight_fp8` \[rows, 160\] e4m3fn; `weight_scale` \[rows\] fp32|`row = fp8 * scale[row]`|
|`ples_int4`|`weight_i4` \[rows, 80\] uint8, two nibbles, low first; `weight_scale` \[rows, 10\] fp16|`row[c] = (nibble - 8) * scale[row, c // 16]`|
|`ples_nvfp4`|`weight_e2m1` \[rows, 80\] uint8 (code = mag index|sign<<3, mags 0,.5,1,1.5,2,3,4,6); `weight_scale` \[rows, 10\] e4m3fn; `weight_scale_2` \[\] fp32|

The overlay maps every shard with safetensors' native mmap and dequantizes only the gathered rows (~100–200 KB per decoded token), so cold-start cost and steady-state RAM both scale with the working set, not the table.

## [](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant#notes)Notes

-   The overlay targets this exact image; the gather hook lives in a vendored model file (`vllm/models/qwen3_8_flash_next/nvidia/ple_layer.py`), which is why this ships as an overlay rather than a vLLM PR. The BF16 disk path, which needs no model-file hook, is PR [vllm-project/vllm#54070](https://github.com/vllm-project/vllm/pull/54070).
-   MTP speculative decoding (`num_speculative_tokens: 3`) composes well with the quantized tables: 129.6 tok/s single-stream on the real-prompt eval with the INT4 table and 128.8 with NVFP4, vs 142.6 with the BF16 table in RAM and 77.5–82.3 with the BF16 table on NVMe. Speculation multiplies gather traffic; the quantized working sets still fit the page cache where the BF16 one does not, so quantization is what makes MTP + low-RAM hosts viable together.
-   The image's stock worker cannot load quantized tables at all (it rejects `ngram_embedding.weight_scale`), which on this image also rules out CPU offload for checkpoints that ship FP8 tables with a global scale. Upstream has moved since: the offload PR branch ([#53899](https://github.com/vllm-project/vllm/pull/53899)) loads FP8 and NVFP4 global-scale tables since 2026-08-30, and [#54129](https://github.com/vllm-project/vllm/pull/54129) memory-maps the FP8 table out of the checkpoint shards. Both work at one scale per table; the sidecars here are per-row (FP8) or per-16-column group (INT4, NVFP4) and attach to any BF16-table checkpoint.
-   Two other community packagings of the table exist: [edougawa](https://huggingface.co/edougawa/Qwen3.8-Flash-Next-W4A16-PLE4-MTP-Spark) carries it as per-row INT4 with FP16 scales inside the checkpoint (needs their vLLM patch), and [HamboneLabs](https://huggingface.co/HamboneLabs-AI/Qwen3.8-Flash-Next-uint3-g64) maps a raw BF16 file the way the disk overlay here does (their patch set). Neither was measured here.
-   The current image (unchanged as of 2026-09-03) predates a fix for a startup race in the PLE offload path (vLLM hangs after CUDA graph capture, looping `No available shared memory broadcast block`; [vllm-project/vllm#53960](https://github.com/vllm-project/vllm/issues/53960), fixed on 2026-08-29 in the offload PR branch, #53899, still unmerged). This repo ships the fixed connector as [`connector_mrv2.py`](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant/blob/main/connector_mrv2.py) — add a third mount: `-v $PWD/connector_mrv2.py:/usr/local/lib/python3.12/dist-packages/vllm/v1/ple_offload/connector.py:ro`. Verified with the overlays here: normal boot, sanity and accuracy unchanged.
-   Same hang, different cause: the GPU worker and the offload subprocess exchange a CUDA IPC file descriptor with `pidfd_getfd(2)`; where seccomp denies it (a managed container host without `CAP_SYS_PTRACE`) or Yama's default `ptrace_scope=1` blocks it (bare metal), the boot hangs after graph capture with no error naming the cause. `--cap-add=SYS_PTRACE` on the `docker run`, or `sysctl kernel.yama.ptrace_scope=0` on bare metal; reports and a preflight probe: [one](https://github.com/vllm-project/vllm/pull/53899#issuecomment-5448518741), [two](https://github.com/vllm-project/vllm/pull/53899#issuecomment-5553027248). Not needed on our box or on the 64 GB-host field report.

___

![Primitive](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-mixed-NVFP4-FP8/resolve/main/assets/primitive-logo.png)

<sub><a href="https://primitive.com/" rel="nofollow"><b>primitive</b></a> · <a href="https://huggingface.co/primitive-ai">more models</a> · inference economics for production LLM systems</sub>