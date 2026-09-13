# Updated my benchmark with a new vLLM based recipe for Qwen 3.8 Flash Next : now up to 98/100 (instead of 91 previously)

**Community:** r/LocalLLaMA · **Posted by:** u/WonderRico · **Score:** 18 upvotes · **Date:** September 4, 2026

**Source:** https://www.reddit.com/r/LocalLLaMA/comments/1w7c4ej/updated_my_benchmark_with_a_new_vllm_based_recipe/

---

I was using:

* weights [https://huggingface.co/RadixArk/Qwen3.8-Flash-Next-NVFP4](https://huggingface.co/RadixArk/Qwen3.8-Flash-Next-NVFP4) 
* with the optimized SGLANG (patched) from  [https://old.reddit.com/r/BlackwellPerformance/comments/1w04xb7/qwen38\_flashnext\_on\_1x\_rtx\_pro\_6000\_171\_ts\_c1\_428/](https://old.reddit.com/r/BlackwellPerformance/comments/1w04xb7/qwen38_flashnext_on_1x_rtx_pro_6000_171_ts_c1_428/)

Now I'm using: 

* weights (AWQ W4A16) from: [https://huggingface.co/wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16](https://huggingface.co/wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16)
* PLE (INT4) from: [https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant)
* with vLLM patched with the patch from the same repo cf [https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant#serve](https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant#serve)
* the goal was to load both the weights and the n-gram PLE quantized in 4bits either on my sm89 or sm120 devices

It's way slower (for my low concurrency usecase) but also **a lot better**. I was surprised to see such a delta.

I reached 98/100 (instead of 91) both with medium and xhigh reasoning (still not useful for this bench). And now it really feels like a huge setup up from the other models. It's the best score AND the most efficient...

I'll try to dig deeper to understand if the difference comes from the engine (and its patches) or the quants themselves. And try to optimize further the vLLM receipt for my setup

as always, the graphs and the data : 

* [here](https://wonderrico.github.io/local_llm_benchmark/benchmark-main.html)
* and [here](https://wonderrico.github.io/local_llm_benchmark/benchmark-detail.html)

---

## Comments (6 fetched)

---

**u/asankhs** · 5 points · Sep 4, 2026

The cleanest next run may be a small ablation: old/new weights crossed with old/new engine, while keeping prompts, sampling, and scoring fixed. Right now the weights, engine patch, PLE, and quant scheme all change together, so 91 → 98 is operationally useful but hard to attribute.

If the full 2×2 is not load-compatible, even old weights on the patched vLLM with PLE off/on would narrow it down. Publishing the seven task-level flips would also show whether the gain clusters in one capability rather than being broad.

---

> **u/ArtfulGenie69** · 0 points

> Probably can't attribute the gain to the int4 ple. I had seen this discussion on huggingface talking about how this one w4a16 model thinks way more than a similar awq model. The awq and the w4a16 model didn't have everything in int4 but the awq had the attention layers also at bf16 and that stopped the over thinking. The problem is it makes it to big to fit on 4x3090. There is a lot of info about it in this comment and on the main model card.
> 
> https://huggingface.co/VnimanieAI/Qwen3.8-Flash-Next-W4A16/discussions/4

**u/jacek2023** · 2 points · Sep 4, 2026

Thanks for sharing

---

**u/CATLLM** · 1 points · Sep 4, 2026

Thanks for this! I had the RadixArk running on my pro6000 and thought it was weird they calibrated their quant to cnn\_dailymail - i mean of all the datasets on huggingface they have to pick that.



---

**u/cosmicnag** · 1 points · Sep 5, 2026

Wondering if nvfp4/sglang/vllm is valid for when cpu/ram offloading is required. Currently running 4.05 bpw EXL3 on exllama (I have 5090 + 4090 + 192 GB VRAM). Geting around 50 tok/sec with mtp 1 (this seems to be working better than 2/3 for me). EXL3 is slower than nvfp4 but way more bang for buck VRAM KLD-wise.

---

**u/ManagerieOfNewbs** · 1 points · Sep 11, 2026

What are you using to perform benchmarks? I'm always looking for the most capable model to plug into Cline VS Code for personal projects where it can have the maximum logic. So far I have found the Thinkcap version to be strongest performer yet when working with building agents

---

**u/Reasonable-Phase8028** · 1 points · Sep 4, 2026

and still you did not share the full command to run this. my god people love flexing

---

> **u/WonderRico** · 5 points

> the full command(s) is only relevant only to my own config.
> 
>     docker run --cap-add SYS_PTRACE --security-opt seccomp=unconfined 
>     --ulimit memlock=-1 --rm --init --ipc=host --shm-size=32g 
>     --gpus device=0 --name llamaswap_1gpu_96 --runtime nvidia 
>     -v /storage/llms/models:/models 
>     -v /storage/llms/models/cache:/root/.cache -v /storage/llms/models/cache/triton:/root/.triton 
>     -e CUDA_DEVICE_ORDER=PCI_BUS_ID 
>     -e TORCHINDUCTOR_CACHE_DIR=/root/.cache/torchinductor 
>     -e NCCL_P2P_DISABLE=1 -e OMP_NUM_THREADS=4 -e SAFETENSORS_FAST_GPU=1 
>     -p 5802:8000 -e VLLM_PLE_CPU_OFFLOAD -e PYTORCH_ALLOC_CONF -e VLLM_PLE_OFFLOAD_READY_TIMEOUT -e VLLM_PLE_QUANT_DIR 
>     -v /storage/llms/models/ST-Qwen3.8-Flash-Next-AWQ-W4A16-PLE-quant/worker_image_quant.py:/usr/local/lib/python3.12/dist-packages/vllm/v1/ple_offload/worker.py:ro 
>     -v /storage/llms/models/ST-Qwen3.8-Flash-Next-AWQ-W4A16-PLE-quant/ple_layer_quant.py:/usr/local/lib/python3.12/dist-packages/vllm/models/qwen3_8_flash_next/nvidia/ple_layer.py:ro 
>     -v /storage/llms/models/ST-Qwen3.8-Flash-Next-AWQ-W4A16-PLE-quant/ples_int4:/ples_int4 
> 
>     vllm/vllm-openai:qwen38-flash-next /models/ST-Qwen3.8-Flash-Next-AWQ-W4A16-PLE-quant 
>     --max-num-seqs 4 --enable-prefix-caching --enable_sleep_mode --max-model-len 150000 --trust-remote-code --gpu_memory_utilization 0.95 
>     --enable-prompt-tokens-details --max-num-batched-tokens 4096 --tensor-parallel-size 1 --max-num-seqs 4 --kv-cache-dtype bfloat16 
>     --enable-expert-parallel --distributed-executor-backend mp --enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser qwen3 
>     --speculative-config '{"method":"mtp","num_speculative_tokens":3}' 
> 
> the one to care about is in one of the links I provided : https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant#serve

> > **u/Reasonable-Phase8028** · 1 points

> > thanks. appreciate it <3
