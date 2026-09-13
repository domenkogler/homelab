# Qwen3.8-Flash-Next at 170K context on a single 96 GB card. ~110 tok/s.

**Community:** r/LocalLLaMA · **Posted by:** u/UltrMgns · **Score:** 22 upvotes · **Date:** August 30, 2026

**Source:** https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/qwen38flashnext_at_170k_context_on_a_single_96_gb/

---

I used the quantized n-gram to INT4, it's 32 GB, memory-mapped from disk.  
I confirmed that it works great on 150-160k context, and i was watching all the time my VRAM usage while doing single thread long horizon things - the available VRAM should be enough to push it to over 170k and above)  
The quality is there guys... It really is. It made a few complex html games and it figured out ways to play them itself without a browser (my ubuntu machine does not have any gui) and it kept improving and improving.... Here we go:

    hf download primitive-ai/Qwen3.8-Flash-Next-NVFP4 \
      --exclude "ple-bf16-*" --local-dir ./flash-next
    cd flash-next
    hf download primitive-ai/Qwen3.8-Flash-Next-PLE-quant \
      --include "ples_int4/*" --local-dir .
    hf download primitive-ai/Qwen3.8-Flash-Next-PLE-quant \
      worker_image_quant.py ple_layer_quant.py --local-dir .

Skipping `ple-bf16-*` (saves 100 GB but breaks the index. So we trim that index):

    import json
    p='model.safetensors.index.json'; d=json.load(open(p)); wm=d['weight_map']
    drop=[k for k,v in wm.items() if v.startswith('ple-bf16-')]
    assert len(drop)==128 and all('ngram_embedding' in k for k in drop)
    for k in drop: del wm[k]
    json.dump(d, open(p,'w'))

My intent was to fit the n-grams in my 64Gb of RAM, but at the end, n-grams and experts + kvcache all live inside the GPU's VRAM and its FAST!  
76–125 tok/s single stream. The spread is MTP acceptance: \~87% on code and JSON, \~40% on just talking. Prefix caching hits 90%+ on a long horizon task. \~89 GB VRAM, \~33 GB page cache, 165-170K context, one GPU. Here's my full k0s yaml file (single server with a single Pro 6000).   
I'm running it on my single node k0s and here is my yaml (cuda 13/580, ubuntu 24.04 no gui):

    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: vllm-qwen38-flash-next
      namespace: default
    spec:
      replicas: 1
      strategy:
        type: Recreate          # never two of these on one GPU
      selector:
        matchLabels:
          app: vllm-qwen38-flash-next
      template:
        metadata:
          labels:
            app: vllm-qwen38-flash-next
        spec:
          runtimeClassName: nvidia
          nodeSelector:
            nvidia.com/gpu.present: "true"
          tolerations:
          - effect: NoSchedule
            key: nvidia.com/gpu
            operator: Exists
          initContainers:
          - name: init-echo
            image: busybox:1.36
            command: ["/bin/sh", "-c"]
            args: ['echo "I am here" > /opt/reservation/echo.txt']
            volumeMounts:
            - mountPath: /opt/reservation
              name: reservation-volume
          containers:
          - name: vllm-server
            image: vllm/vllm-openai:qwen38-flash-next
            imagePullPolicy: IfNotPresent
            args:
            - --model
            - /model
            # ---- load-bearing for single-GPU PLE offload ----
            - --distributed-executor-backend
            - mp
            # -------------------------------------------------
            - --dtype
            - auto
            - --kv-cache-dtype
            - auto
            - --gpu-memory-utilization
            - "0.95"
            - --max-model-len
            - "173400"
            - --tensor-parallel-size
            - "1"
            - --pipeline-parallel-size
            - "1"
            - --limit-mm-per-prompt
            - '{"image":12,"video":2}'
            - --max-num-batched-tokens
            - "16384"
            - --max-num-seqs
            - "4"
            - --enable-chunked-prefill
            - --enable-prefix-caching
            - --no-enable-flashinfer-autotune
            - --speculative-config
            - '{"method":"mtp","num_speculative_tokens":3}'
            - --override-generation-config
            - '{"temperature":1,"top_p":0.95,"top_k":20}'
            - --enable-auto-tool-choice
            - --reasoning-parser
            - qwen3
            - --tool-call-parser
            - qwen3_coder
            - --trust-remote-code
            - --api-key
            - key1
            - --host
            - 0.0.0.0
            - --port
            - "8990"
            - --served-model-name
            - qwen38-flash
            env:
            - name: VLLM_PLE_CPU_OFFLOAD
              value: "1"
            - name: VLLM_PLE_OFFLOAD_READY_TIMEOUT
              value: "1800"
            # Confirmed: worker_image_quant.py:419 reads this. Points at the
            # INT4 table dir; the overlay memory-maps it (MADV_RANDOM, mode "c").
            - name: VLLM_PLE_QUANT_DIR
              value: /model/ples_int4
            # Deliberately NOT setting VLLM_PLE_DISK_OFFLOAD_DIR (line 450) --
            # that selects the BF16-table-on-NVMe path instead.
            - name: VLLM_LOGGING_LEVEL
              value: INFO
            - name: OMP_NUM_THREADS
              value: "1"
            - name: PYTORCH_CUDA_ALLOC_CONF
              value: max_split_size_mb:512
            ports:
            - containerPort: 8990
              protocol: TCP
            resources:
              limits:
                cpu: "12"
                nvidia.com/gpu: "1"
              requests:
                cpu: "8"
                nvidia.com/gpu: "1"
            securityContext:
              capabilities:
                add: ["IPC_LOCK", "SYS_ADMIN"]
            startupProbe:
              httpGet:
                path: /health
                port: 8990
              periodSeconds: 15
              failureThreshold: 80        # ~20 min; first boot loads the table
            readinessProbe:
              httpGet:
                path: /health
                port: 8990
              periodSeconds: 20
              failureThreshold: 3
            lifecycle:
              preStop:
                exec:
                  command: ["/bin/sh", "-c", "rm -f /opt/reservation/echo.txt"]
            volumeMounts:
            - mountPath: /model
              name: model-volume
              readOnly: true
            # --- two-file quantized-PLE overlay ---
            - mountPath: /usr/local/lib/python3.12/dist-packages/vllm/v1/ple_offload/worker.py
              name: ple-worker-overlay
              readOnly: true
            - mountPath: /usr/local/lib/python3.12/dist-packages/vllm/models/qwen3_8_flash_next/nvidia/ple_layer.py
              name: ple-layer-overlay
              readOnly: true
            - mountPath: /ples_int4
              name: ple-tables
              readOnly: true
            # --------------------------------------
            - mountPath: /dev/shm
              name: dshm
            - mountPath: /root/.cache/vllm
              name: vllm-cache
            - mountPath: /root/.triton
              name: triton-cache
            - mountPath: /opt/reservation
              name: reservation-volume
          volumes:
          - name: model-volume
            hostPath:
              path: /directory/models/Qwen3.8-Flash-Next-NVFP4
              type: Directory
          - name: ple-worker-overlay
            hostPath:
              path: /directory/ple-overlay/worker_image_quant.py
              type: File
          - name: ple-tables
            hostPath:
              path: /directory/models/Qwen3.8-Flash-Next-NVFP4/ples_int4
              type: Directory
          - name: ple-layer-overlay
            hostPath:
              path: /directory/ple-overlay/ple_layer_quant.py
              type: File
          - name: dshm
            emptyDir:
              medium: Memory
              sizeLimit: 32Gi
          - name: reservation-volume
            hostPath:
              path: /opt/reservation
              type: DirectoryOrCreate
          - name: vllm-cache
            hostPath:
              path: /var/cache/vllm
              type: DirectoryOrCreate
          - name: triton-cache
            hostPath:
              path: /var/cache/triton
              type: DirectoryOrCreate
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: vllm-qwen38-flash-next
      namespace: default
    spec:
      type: NodePort
      selector:
        app: vllm-qwen38-flash-next
      ports:
      - name: http
        port: 8990
        targetPort: 8990
        nodePort: 32001
        protocol: TCP

Big Thank you to primitive-ai, whoever he is.

---

## Comments (7 fetched)

---

**u/Dull-Giraffe** · 8 points · Aug 30, 2026

SGLang is fastest for me: at real context depths:  
150-160 tok/s  narrative,  
200-215 tok/s code,

192k context, spec tokens=3. MTP acceptance is good. It's nearly free: the MTP head lands at 0.51 GB in VRAM and the KV pool is unchanged, so speculation costs no context.

SGLang PR #36556 needed to be included.

This is single RTX6000Pro card, in a modern intel desktop system.

---

> **u/live4evrr** · 0 points

> Did you also include PR [36497](https://github.com/sgl-project/sglang/pull/36497)? How much RAM does this take up? During initializatio using Radixark nvfp4 it freezes up for me/

> > **u/l0nedigit** · 1 points

> > I've got the same card and 64gb ram. Had a browser tab on some more ram, contemplating pulling the trigger. But this post may have been a wallet saver. Will have to try it out. Thanks OP

> > **u/Dull-Giraffe** · 1 points

> > Late here in NZ so excuse the AI summary - but in case it helps:
> > 
> > PR #36497: Yes, but not as a patch — it's baked into the image. I run lmsysorg/sglang:qwen38flashnext, the day-0 preview tag (pushed 2026-08-26, branch qwen4-main-squashed) that carries the still-unmerged model support from #36497. Stable v0.5.18 doesn't have qwen4\_exp and fails with an unknown model type. On top of that image I apply PR #36556 at container start — on sm\_120 that one is not optional: without the full fix, QSA decode boots and passes a smoke test, then silently emits token ID 0 (!!!!) past the first KV page (\~position 65 at page-size 64). If you only fix the varlen fallback crash from #36531, you get exactly that trap.
> > 
> > RAM: two budgets.
> > 
> > \- GPU: 78.2 GiB of the 96 GB card — 68 GB NVFP4 routed experts + 16 GB BF16 everything-else — leaving \~17 GiB for KV + GDN state at 196K context.
> > 
> > \- Host: \~51.2 GB of pinned memory for the FP8 n-gram table via --ple-offload-embedding (that flag is load-bearing; without it the table goes to VRAM and nothing fits). Budget \~55–60 GB for the container overall, plus --shm-size 16g. --ulimit memlock=-1 is mandatory — any memlock ceiling below the table size fails the pin.

**u/Desperate-Data-3747** · 3 points · Aug 30, 2026

Beats qwen3.8 27b?

---

> **u/UltrMgns** · 10 points

> By a lot, and it's obvious once you start comparing outputs.

> > **u/wgaca2** · 0 points

> > That chart does not show "a lot"

> > > **u/NeKon69** · 10 points

> > > You do realize benchmarks isn't the only way to measure model performance? And also not a very accurate one.

> > > > **u/wgaca2** · 0 points

> > > > Oh i do, but that was OP's argument

> **u/uti24** · 2 points

> From my tests, yes, I would say so.
> 
> Not by a ton, but noticeably. If you don't know they're different models, you might not notice sometimes.
> 
> It also argues much less with itself.

> **u/pulse77** · 3 points

> It beats qwen3.8 27b:
> 
> https://preview.redd.it/ii70rc3mxgmh1.png?width=1142&format=png&auto=webp&s=fdce444fdd3f7585e44d19212d5f8d331bc19b18
> 
> 

> > **u/egnegn1** · 1 points

> > Yes, but at 4x the hardware cost.
> > 
> > There should be a metric hw cost per intelligence and cost per token speed.

> > > **u/Zyj** · 3 points

> > > Well it only has 6b active parameters, so you could argue that it will be a lot faster than 27b active parameters. Yes, it needs more VRAM/unified RAM.

**u/KingGongzilla** · 2 points · Aug 30, 2026

cool!!

---

**u/madbrain1976** · 2 points · Aug 30, 2026

Thanks. Feeding this recipe to Codex to adjust and see what I get with my lowly 4 x 5060 Ti 16GB at PCIe 4.0 x8 with P2P, rather than your single 5.0 x16 single 96GB card. I do have twice the system RAM, but it's DDR4.

Any hint on your client parameters for reproduction would be helpful - eg. a llama-benchy command that hits your server. For now, codex is going to try a 170k prompt - if that's what you meant you used by "165-170K context".

---

> **u/Lumpy_Concentrate807** · 1 points

> Curious to hear what you get! Also have quad 5060. But right now maybe not enough system RAM (64 GB). So your results can help evaluate if to invest more...

> > **u/madbrain1976** · 1 points

> > So far, only OOM, unfortunately. Gotta try again.

> > **u/madbrain1976** · 0 points

> > Here are the gory details. I have 128GB of RAM, and still couldn't make it fit. Looks like this OP's recipe really is not suitable for 4 GPUs.
> > 
> >     Title: Trying the Qwen3.8-Flash-Next 170K recipe on 4x RTX 5060 Ti 16GB: three startup blockers
> >     
> >     I tried adapting the single-96GB-GPU Qwen3.8-Flash-Next NVFP4 recipe to four RTX 5060 Ti 16GB cards.
> >     
> >     Hardware/software:
> >     
> >     - 4x RTX 5060 Ti 16GB
> >     - NVIDIA driver 610.57.04
> >     - Full-mesh P2P tested and working
> >     - vLLM image pinned to the same recipe image digest
> >     - Qwen3.8-Flash-Next-NVFP4 plus the INT4 PLE sidecar
> >     - Tensor parallel size 4
> >     - Maximum model length 173,400
> >     - MTP speculative depth 3
> >     
> >     The original Reddit post gives a server configuration and observed throughput, but no exact client command, prompt, token counts, repeat count, seed, timing boundary, or raw benchmark result. I therefore treated this as a server-recipe reproduction first. No benchmark was run because the server never reached its health-ready state.
> >     
> >     All three attempts loaded the 52 core checkpoint shards and the INT4 PLE sidecar. They failed later, while preparing the NVFP4 MoE weights, before KV-cache allocation, CUDA graph warmup, or API readiness.
> >     
> >     Attempt 1: automatic MoE backend, 10 GiB CPU offload per GPU
> >     
> >     vLLM selected FLASHINFER_CUTLASS. After loading the weights, every TP worker failed with:
> >     
> >         NotImplementedError: Intermediate size padding for w1 and w3 ...
> >         is not currently supported: FLASHINFER_CUTLASS
> >     
> >     Splitting this model's MoE expert dimensions four ways requires padding/alignment. This particular NVFP4 conversion backend does not implement that padded TP=4 layout.
> >     
> >     This was a backend limitation, not an OOM, corrupt checkpoint, P2P problem, or long-context problem.
> >     
> >     Attempt 2: Humming MoE backend, 10 GiB CPU offload per GPU
> >     
> >     The Humming backend supports the TP=4 layout and passed the first failure. However, Humming has to repack the NVFP4 weights into its own kernel layout. That temporarily requires new output tensors while the original tensors are still resident.
> >     
> >     At the failure point, each 15.52 GiB CUDA-visible GPU was already using about 15.1 GiB:
> >     
> >     - GPU 0 had 15.88 MiB free and failed a 40 MiB allocation.
> >     - GPU 1 had 291.50 MiB free and failed a 320 MiB allocation.
> >     - GPUs 2 and 3 had about 320 MiB free and failed 320 MiB allocations.
> >     
> >     Only about 55 MiB was reserved-but-unused by PyTorch, so this was mainly genuine capacity pressure rather than severe allocator fragmentation.
> >     
> >     Attempt 3: Humming MoE backend, 11.5 GiB CPU offload per GPU
> >     
> >     Increasing CPU offload fixed the GPU repacking headroom. During conversion, GPU use was approximately 12.5-12.9 GiB per card, leaving approximately 3.0-3.3 GiB free.
> >     
> >     The bottleneck then moved to host RAM. vLLM logged approximately 11.59 GiB of CPU-offloaded parameters per worker, or about 46.4 GiB across four workers. The process also had the 32GB INT4 PLE sidecar, the 78.23 GiB core checkpoint, shared-memory/communication buffers, and temporary Humming conversion tensors in play.
> >     
> >     The container reached approximately 115.2 GiB on a host with 123.6 GiB of RAM. It spent about 76 minutes in the Humming repacking stage and was then killed:
> >     
> >         OOMKilled=true
> >         ExitCode=137
> >     
> >     There was no Docker memory limit, so this was host-wide memory exhaustion. The machine has swap, but CUDA/UVA pinned memory and active shared-memory regions cannot necessarily be reclaimed or swapped like ordinary anonymous memory.
> >     
> >     Warnings that were not responsible:
> >     
> >     - The PLE sidecar loaded all 128 INT4 shards successfully.
> >     - P2P was independently verified as working full-mesh.
> >     - vLLM fell back to NCCL when its custom all-reduce path was unavailable.
> >     - Transformer min_frames/max_frames documentation warnings were noisy but nonfatal.
> >     - None of the attempts reached KV-cache allocation, so 173,400-token KV capacity was not the failure yet.
> >     
> >     The practical squeeze is:
> >     
> >     - Less CPU offload: Humming's temporary conversion buffers exceed 16GB GPU memory.
> >     - More CPU offload: conversion exceeds the host's 123GB RAM.
> >     
> >     Full status, commands, and logs:
> >     
> >     http://hal:8080/reddit-qwen38-flash-next-4x5060/report.html
> >     
> >     Original recipe:
> >     
> >     https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/qwen38flashnext_at_170k_context_on_a_single_96_gb/
> >     Title: Trying the Qwen3.8-Flash-Next 170K recipe on 4x RTX 5060 Ti 16GB: three startup blockers
> >     
> >     I tried adapting the single-96GB-GPU Qwen3.8-Flash-Next NVFP4 recipe to four RTX 5060 Ti 16GB cards.
> >     
> >     Hardware/software:
> >     
> >     - 4x RTX 5060 Ti 16GB
> >     - NVIDIA driver 610.57.04
> >     - Full-mesh P2P tested and working
> >     - vLLM image pinned to the same recipe image digest
> >     - Qwen3.8-Flash-Next-NVFP4 plus the INT4 PLE sidecar
> >     - Tensor parallel size 4
> >     - Maximum model length 173,400
> >     - MTP speculative depth 3
> >     
> >     The original Reddit post gives a server configuration and observed throughput, but no exact client command, prompt, token counts, repeat count, seed, timing boundary, or raw benchmark result. I therefore treated this as a server-recipe reproduction first. No benchmark was run because the server never reached its health-ready state.
> >     
> >     All three attempts loaded the 52 core checkpoint shards and the INT4 PLE sidecar. They failed later, while preparing the NVFP4 MoE weights, before KV-cache allocation, CUDA graph warmup, or API readiness.
> >     
> >     Attempt 1: automatic MoE backend, 10 GiB CPU offload per GPU
> >     
> >     vLLM selected FLASHINFER_CUTLASS. After loading the weights, every TP worker failed with:
> >     
> >         NotImplementedError: Intermediate size padding for w1 and w3 ...
> >         is not currently supported: FLASHINFER_CUTLASS
> >     
> >     Splitting this model's MoE expert dimensions four ways requires padding/alignment. This particular NVFP4 conversion backend does not implement that padded TP=4 layout.
> >     
> >     This was a backend limitation, not an OOM, corrupt checkpoint, P2P problem, or long-context problem.
> >     
> >     Attempt 2: Humming MoE backend, 10 GiB CPU offload per GPU
> >     
> >     The Humming backend supports the TP=4 layout and passed the first failure. However, Humming has to repack the NVFP4 weights into its own kernel layout. That temporarily requires new output tensors while the original tensors are still resident.
> >     
> >     At the failure point, each 15.52 GiB CUDA-visible GPU was already using about 15.1 GiB:
> >     
> >     - GPU 0 had 15.88 MiB free and failed a 40 MiB allocation.
> >     - GPU 1 had 291.50 MiB free and failed a 320 MiB allocation.
> >     - GPUs 2 and 3 had about 320 MiB free and failed 320 MiB allocations.
> >     
> >     Only about 55 MiB was reserved-but-unused by PyTorch, so this was mainly genuine capacity pressure rather than severe allocator fragmentation.
> >     
> >     Attempt 3: Humming MoE backend, 11.5 GiB CPU offload per GPU
> >     
> >     Increasing CPU offload fixed the GPU repacking headroom. During conversion, GPU use was approximately 12.5-12.9 GiB per card, leaving approximately 3.0-3.3 GiB free.
> >     
> >     The bottleneck then moved to host RAM. vLLM logged approximately 11.59 GiB of CPU-offloaded parameters per worker, or about 46.4 GiB across four workers. The process also had the 32GB INT4 PLE sidecar, the 78.23 GiB core checkpoint, shared-memory/communication buffers, and temporary Humming conversion tensors in play.
> >     
> >     The container reached approximately 115.2 GiB on a host with 123.6 GiB of RAM. It spent about 76 minutes in the Humming repacking stage and was then killed:
> >     
> >         OOMKilled=true
> >         ExitCode=137
> >     
> >     There was no Docker memory limit, so this was host-wide memory exhaustion. The machine has swap, but CUDA/UVA pinned memory and active shared-memory regions cannot necessarily be reclaimed or swapped like ordinary anonymous memory.
> >     
> >     Warnings that were not responsible:
> >     
> >     - The PLE sidecar loaded all 128 INT4 shards successfully.
> >     - P2P was independently verified as working full-mesh.
> >     - vLLM fell back to NCCL when its custom all-reduce path was unavailable.
> >     - Transformer min_frames/max_frames documentation warnings were noisy but nonfatal.
> >     - None of the attempts reached KV-cache allocation, so 173,400-token KV capacity was not the failure yet.
> >     
> >     The practical squeeze is:
> >     
> >     - Less CPU offload: Humming's temporary conversion buffers exceed 16GB GPU memory.
> >     - More CPU offload: conversion exceeds the host's 123GB RAM.
> >     
> >     Full status, commands, and logs:
> >     
> >     http://hal:8080/reddit-qwen38-flash-next-4x5060/report.html
> >     
> >     Original recipe:
> >     
> >     https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/qwen38flashnext_at_170k_context_on_a_single_96_gb/
> >     

**u/ForestoShen** · 1 points · Aug 30, 2026

You should be able to push the context limit to full  262k by using fp8 mtp quant, the acceptence rate seems mostly unaffected to me . I'm runing on sglang though, not sure how vllm would handle it.

---

> **u/Dull-Giraffe** · 1 points

> I'm on SGLang too - keen to hear how you find fp8 as you use it more. I've stayed with BF16 @ 192k for flash next, and made sure it's solid at that. My tests take hours to run so can only change so many things each day!

**u/Zyj** · 1 points · Aug 30, 2026

I will have 96GB (4xRTX 3090 24GB) and 128GB RAM, is anyone running that? I'd like to have the numbers.

---

**u/AdSafe4047** · 0 points · Aug 30, 2026

there is a sglang fork that runs nvfp4 with q8 cache quant where you can put 3x256k cache + vision + mtp - it flies. Compared to qwen 27b fp8 bv16 it beats it in my benchmark suite.

---
