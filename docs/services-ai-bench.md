---
title: Measured AI inference benchmarks on oldsrv (STT + rerank device sweep)
role: evidence
domain: services
status: active
tags: [services, ai, gpu, benchmark, stt, rerank, vram, whisper, vulkan]
---
# AI Inference Benchmarks — oldsrv RX 7600 / HD 630 / CPU (measured 2026-09-18)

> **Role:** dated **measurement** appendix for the pinned-AI tier ([services-ai.md](services-ai.md) §9
> decisions #24/#25, HD-369 / HD-385). §9c is the *source-reading* record (what upstreams claim); **this doc is
> the *measured* record** (what this card actually does), because the 2026-09-17 paper arithmetic in decision
> #25(b) was wrong by ~10–20× and only a probe could say so.
>
> **Status: this appendix was acted on.** Decision **#27** adopted its result (Vulkan engine family, Q8_0
> quantization, reranker on the dGPU) and the three legs shipped in IaC as `whisper` / `reranker` / `embed`
> (HD-391/HD-392). What this file is *for* is the evidence behind those numbers: it is a measurement record,
> so its dates are provenance, not history for its own sake.
>
> All probes ran in throwaway containers with loopback-only ports and were deleted afterwards; live services
> were not touched. Read the plan-of-record in [services-ai.md](services-ai.md) §3a — **not** §4's tunnel URL,
> which is a torn-down test edge.

## 1. Measurement environment

| Item | Value |
|------|-------|
| Host | `oldsrv` (Debian 13, kernel 6.12.107, Docker 29.7.2, Compose 5.5.0) |
| CPU | Intel i7-7700K, 4C/8T, AVX2 + FMA, **no AVX-512 / no VNNI**, DDR4-2400 (~34 GB/s) |
| RAM | 46 GiB (≥ 33 GiB available throughout) |
| dGPU | AMD Radeon **RX 7600** `gfx1102` → `/dev/dri/renderD129`, `render` gid **992**, sysfs `card1/mem_info_vram_used`, total 8.57 GiB |
| iGPU | Intel **HD 630 (KBL GT2, Gen 9.5)** → `/dev/dri/renderD128`, i915, **Xorg primary** (family desktop) and already the Jellyfin **QSV** transcode device |
| Access path | `ssh -J vps` → Home leg of `oldsrv.kogler.si`. ⚠ The Mgmt-VLAN address was **unreachable from the workstation** in this session and the `oldsrv` alias's `ProxyJump vps` does not work (the VPS has no Mgmt route); the same host key was verified on both legs before trusting it → recorded as **HD-392** |

**Images used (kept on the box for the implementation converge — no bare `latest` in IaC, CONVENTIONS §7):**

| Image | Digest (`@sha256:`) | Unpacked |
|-------|--------------------|----------|
| `ghcr.io/ggml-org/whisper.cpp` `main-vulkan` | `cf102ac361a0978ce2b225c7fa9eccedc781915b7be4d198692ea5fe2261597f` | 2.34 GB |
| `ghcr.io/ggml-org/llama.cpp` `server-vulkan` | `7158edb447f837734142c899183e255538d89d63a037f60077b26fc1c7f95353` (v0.4.1, build 11028, `972d2313b`) | 1.21 GB |
| `ghcr.io/huggingface/text-embeddings-inference` `cpu-1.9.4` | `2538ea1c9640d3763b15af668039d24172d063b42337b0c27796fc2be180c78d` | 938 MB |

**Models:** `ggml-large-v3-turbo.bin` + `-q5_0` (ggerganov/whisper.cpp GGML URLs — **the sha256 gap here is
now closed**: `ggml-large-v3-turbo.bin` = 1 624 555 275 B, `sha256 1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69`,
and `-q5_0` = 574 041 195 B, `sha256 394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2` — both
**verified against the downloaded bytes on oldsrv 2026-09-19**, not just against the HF tree OID; they now live
as `whisper_cpp_model_sha256` / `whisper_cpp_model_q5_sha256` in `group_vars/all/versions.yml`),
`gpustack/bge-reranker-v2-m3-GGUF` **Q8_0** (635,676,416 B, `sha256 a43c7c9b11a4c1517e5bf95151960e1621d1b72f7a493364b01e386cf1aaa1d3`, Apache-2.0, 27 990 DL — verified against the HF LFS OID),
`ggml-org/bge-m3-Q8_0-GGUF` **Q8_0** (634,553,760 B, MIT, official `ggml-org` org; HF LFS OID `sha256 aa473d51f451a22f0fcf39ba3330c14bed38a385712b1113440f69df4047a173` — **verified on the fetched bytes 2026-09-19**, and note the artifact name is lowercase: `bge-m3-q8_0.gguf`),
`gpustack/bge-m3-GGUF` **FP16** (1,157,671,200 B, `sha256 daec91ffb5dd0c27411bd71f29932917c49cf529a641d0168496c3a501e3062c`) and **Q8_0** (634,553,760 B, `sha256 950f4a8e5e19477a6d3c26d2f162233c20002c601f75e4b002e3239997821167`),
`gpustack/bge-reranker-v2-m3-GGUF` **FP16** (1,159,776,896 B, `sha256 5df93be121c09c43432102ad2b9569d369ccb85c209ca7583e8ccd28f0e41b88`) — the Q8_0 of both reranker mirrors is the same bytes as above,
`kftof/bge-reranker-v2-m3-onnx-int8-avx2` (ORT INT8) and stock `BAAI/bge-reranker-v2-m3` (candle fp32).

**Method:** warm-up request, then 3 timed repetitions per shape, `curl` wall-clock (`%{time_total}` or
`date +%s%N` delta); VRAM from the `amdgpu` sysfs counter (not `rocm-smi`, which the host does not ship);
container RSS from `docker stats`; corpus = **real Slovenian prose** from `readme-humans.md`, chunked into
20 × 100-word documents (an earlier synthetic-`besedaN` corpus inflated tokens/word ~2× — those numbers are
superseded here and are only quoted where they are the only measurement available).

## 2. STT — `whisper.cpp` on Vulkan (RX 7600)

Device visibility: passing **only `renderD129`** makes `ggml_vulkan` enumerate **only** the RX 7600
(`AMD Radeon RX 7600 (RADV NAVI33) | fp16: 1 | matrix cores: KHR_coopmat`); the i915 iGPU never appears.
Measured with an 11 s WAV:

| Model | Backend | VRAM (Δ over 66 MiB idle) | Host RSS | Warm latency | Notes |
|-------|---------|---------------------------|----------|--------------|-------|
| `large-v3-turbo` (fp16) | Vulkan/dGPU | **1788 MiB** (Δ1722) | **34 MiB** | **0.40 s** (cold 0.85 s) | 6× sustained all 0.40 s; 3-way burst 0.40 / 0.81 / 1.21 s |
| `large-v3-turbo-q5_0` | Vulkan/dGPU | **786 MiB** (Δ720) | 34 MiB | 0.39 s | same latency, 1.0 GiB less VRAM |
| `base.en` (image default) | Vulkan/dGPU | 289 MiB | — | 0.12 s | English-only ⇒ unusable for Slovenian |
| `large-v3-turbo` | **CPU** (`-ng` / no DRI node) | — | **1.59 GiB** | **17.5 s** | load +2.6 — degraded-fallback only |

**Wire contract — the §9c "thin wrapper is required" claim is FALSE.** `--inference-path /v1/audio/transcriptions`
relocates the inference route: `POST /v1/audio/transcriptions` → `200 {"text": … }`, `POST /inference` → **404**,
`/health` stays at the request root, and the extra OpenAI-style multipart fields (`model`, `language`,
`response_format`) are accepted rather than rejected. Home Assistant Assist therefore needs **no wrapper**.

**GPU-first / CPU-fallback is native** (HD-385 wanted exactly this): with no DRI node present the server logs
`ggml_vulkan: No devices found` → `no GPU found` → **serves on CPU and stays up**; `-ng` forces the same path.
Honest limit: this is **init-time** fallback. A mid-run GPU fault is a container crash + restart, not a fallback.

Model fetch (HD-385 item d): `huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin`
→ 1.6 GB in 18 s, `-q5_0` 548 MB in 11 s. The image ships **only** `ggml-base.en.bin`, so an IaC fetch task is mandatory.
**That task exists now (HD-391, 2026-09-19)** as the generic `svc.model_*` opt-in in
`roles/docker_services/tasks/deploy-service.yml`, pinned to `sha256 1fc70f77…2bc69` (§1) — the digest the bench
could not supply, measured on the bytes on this box.

## 3. Rerank — the device sweep (`bge-reranker-v2-m3`, same weights, same build, one variable)

Same GGUF Q8_0 + the same `llama.cpp` binary for all three device rows; TEI rows are a different server (noted).
Latency = `POST /v1/rerank`, `top_n: 5`, real Slovenian chunks:

| Engine / device | 5 docs × 100 w | 10 docs | **20 docs** | Memory | Host cost |
|-----------------|----------------|---------|-------------|--------|-----------|
| **`llama.cpp` Vulkan → RX 7600** | **0.14 s** | **0.27 s** | **0.50 s** | **425 MiB VRAM**, RSS 157 MiB | **~0 % CPU**, load 0.35 |
| `llama.cpp` Vulkan → HD 630 iGPU | 5.8 s | 11.4 s | 22.8 s | **798 MiB host RAM** (no VRAM counter) | low CPU |
| `llama.cpp` CPU (Q8_0) | — | 3.9 s | 8.0 s | 158 MiB | load 1.7 |
| **TEI `cpu-1.9.4`, ORT INT8** | **1.1 s** | 2.6 s | **5.3 s** | **2.66 GiB RSS** | **~790 % CPU (all 8 threads)** |
| TEI `cpu-1.9.4`, candle fp32 | 1.8× slower than INT8 | — | 20×300 synthetic words = 45.9 s | 3.9 GiB RSS | saturates the box |

**Headlines:**
1. **CPU rerank is ~10–20× slower than the paper arithmetic in #25(b) claimed** — measured slope ≈ **260 ms per
   100-word chunk**, so a top-20 rerank costs ~5.3 s (ORT INT8) … 8.0 s (llama.cpp) of *all eight cores*, against an
   assumed "20 pairs ≈ 10–30 ms/pair" (0.2–0.6 s). 8 AVX2 cores + ORT INT8 with no VNNI is the reason: INT8 buys
   only **1.8×** over fp32 here (measured), not 4×.
2. **The dGPU answers it for 425 MiB of VRAM and 0 % CPU** — 10× faster than the best CPU option. #25(b)'s
   premise ("GPU residency buys nothing while costing 1.5 GB VRAM + a ROCm runtime") was half right — *ROCm*
   buys nothing — and half wrong: the Vulkan path costs 0.42 GB, not 1.5 GB.
3. **TEI is the better CPU engine, `llama.cpp` is the better GPU engine** — TEI INT8 beats llama.cpp CPU
   (5.3 s vs 8.0 s) while llama.cpp Vulkan beats everything by 10×.

**Wire shapes (matters for LiteLLM):**

| Server | Request | Response |
|--------|---------|----------|
| TEI `/rerank` | `{query, texts, top_n, return_text, raw_scores, truncate, truncation_direction}` | `[{index, score}]` sorted desc. A Cohere-style `documents` body → **HTTP 422 `missing field texts`** |
| `llama-server` `/v1/rerank` (`--embedding --pooling rank --rerank`) | `{model, query, documents, top_n}` | `{results: [{index, relevance_score}], usage}` |

LiteLLM `v1.83.10-stable` `jina_ai/` rerank (`litellm/llms/jina_ai/rerank/transformation.py`, read 2026-09-18):
`get_complete_url` **forces** `<api_base>/v1/rerank`, the request body is `{model, query, documents, top_n,
return_documents}`, and the response parser reads `results[].index` + `results[].relevance_score` — **byte-for-byte
the `llama-server` shape**. `api_key` is required by `validate_environment` but only becomes a `Bearer` header
that `llama-server` ignores. ⚠ DB-stored `litellm_params` do **not** expand `os.environ/` (HD-382) → `api_base`
must be a literal, and local providers need a dummy `api_key`. TEI instead needs the `huggingface/` provider
(`texts` shape).

## 3b. Embeddings — Vulkan vs the live Ollama `:rocm` leg, **and the vector-space drift check**

Embed was the one leg #25(a) left alone (“already live + E2E-verified, no reason to move”), so the question is
not *can* Vulkan do it but whether the move is worth the churn. Model: **`ggml-org/bge-m3-Q8_0-GGUF`**
(634.6 MB, **MIT**, the official `ggml-org` org) in the **same `llama.cpp server-vulkan` image** as the
reranker; reference = the **live** `ollama:0.32.15-rocm` `bge-m3` container, untouched, reached over
`llm-backend`. Corpus: 1 short query + 50 chunk-shaped Slovenian texts (~110 words each, **7 604 tokens**
batched), both engines timed by the same wall-clock method.

| Engine / device | 1 chunk (query path) | batch of 51 (ingest path) | VRAM | Host RSS | dim | norm |
|-----------------|----------------------|---------------------------|------|----------|-----|------|
| `ollama :rocm` bge-m3 (**live**) | **~470–545 ms** | **1.83 – 1.93 s** | **833–899 MiB** | **2.19 GiB** | 1024 | — |
| `llama.cpp` Vulkan bge-m3 **Q8_0** | **15 ms** (33×) | **0.81 – 1.26 s** (2.3×) | **~326 MiB** | **157 MiB** | 1024 | **1.000000** |

**The deciding number — it is the same vector space:** cosine similarity between the two engines’ vectors
across all 51 documents = **mean 0.99960, min 0.99856** (discrimination sanity: `cos(doc0, doc1) = 0.41`, so
the figure is not trivially inflated). ⇒ switching engines does **not** invalidate the existing Qdrant vectors
and does not *require* re-embedding for correctness — and re-embedding anyway is free today, because the
corpus is a rebuildable cache (decision #19) and nothing is RAG’d yet.

Supporting detail: `--pooling cls` and the GGUF-declared default produce **identical** vectors (no pooling
landmine here, unlike the reranker GGUF which needed `--pooling rank` explicitly); `--embd-normalize` defaults
to **2 = L2**, which is what bge expects, and returned vectors are unit-norm; `ollama` cold-load was
**4.9–5.4 s** vs **2–3 s** for the GGUF leg.

**Verdict (→ decision #27 leg (c)): move embed to the same Vulkan runtime.** The case is not only the query
path (500 ms → 15 ms, and *every* RAG/Assist query embeds its query) but the stack: **−507 MiB VRAM,
−2.0 GiB host RSS**, 2.3× ingest, one image family across all three legs, one model-fetch task shape
(GGUF + sha256), a native CPU fallback the ROCm leg has no cheap equivalent of, and **no `/dev/kfd` /
ROCm userspace left in the AI tier** (immich-ML carries its own ROCm inside its image).
⚠ Two implementation-time checks ride with it: (1) **`--ctx-size` must cover the real ingest chunk** — the
probe used ~150-token chunks, llama.cpp truncates beyond the context window, and bge-m3 supports 8192;
(2) quantization is **settled by §3c**: Q8_0 (16 ms, ~326 MiB, cos 0.9996), with FP16 measured and rejected
(19 ms, ~595 MiB, cos 0.99996 — one more nine for +269 MiB and +18 % latency).
✅ **Check (1) was measured at deploy time (2026-09-19) and it was the wrong knob — [services-ai.md](services-ai.md)
§3a-3 finding 1.** `--ctx-size 2048` alone still answered **HTTP 500 on an 842-token input** ("increase the
physical batch size (current batch size: 512)"), and the number that message reports is the **ubatch**, so the
first fix (batch 2048 / ubatch 512) failed identically. Both GGUF legs now run **2048/2048/2048** and the
842-token chunk returns 200 with `n_tokens = 842, truncated = 0`; the VRAM price of ubatch 512 → 2048 was
**~15–35 MiB**, so compute-buffer size (not ctx) is the thing to budget against when HD-268b fixes a real chunk
shape. Also measured here, for the record: **real Slovenian audio** (the probe only ever ran English
`jfk.wav`) and the endpoint's failure mode for over-window input is a **loud 500**, not silent truncation.
Residency note for all three legs: `llama-server` has **no Ollama-style keep-alive/LRU unloading**, so each
leg holds its model until restart; `--sleep-idle-seconds` (PR #18228, single- and multi-model) can release GPU
memory while idle at the cost of a reload on the next request.

## 3c. Quantization sweep — **Q8_0 vs FP16** on both GGUF legs (same image, same flags, same request)

`gpustack/bge-m3-GGUF` + `gpustack/bge-reranker-v2-m3-GGUF` (MIT / Apache-2.0), each quantization loaded as its
own container on the RX 7600, same corpus as §3b (51 texts / 7 604 tokens; rerank = 20 docs / 2 888 tokens,
`top_n: 20`):

| Leg | Model | Query path | Batch / ingest | VRAM leg Δ | Host RSS | Fidelity |
|-----|---------|------------|----------------|------------|----------|----------|
| embed | **FP16** (1 157.7 MB) | 19–20 ms | 1399 / 907 ms | **~595 MiB** | 158 MiB | **cos vs live Ollama 0.99996 (min 0.99990)** |
| embed | **Q8_0** (634.6 MB) | **16–17 ms** | 1397 / 864 ms | **~326 MiB** | 157 MiB | cos vs live Ollama 0.99960 (min 0.99856) |
| embed | FP16 ↔ Q8_0 | — | — | +269 MiB for FP16 | — | cos **0.99960 (min 0.99837)** |
| rerank | **FP16** (1 159.8 MB) | 405 / 378 ms | — | ~597 MiB | 158 MiB | — |
| rerank | **Q8_0** (635.7 MB) | **342 / 383 ms** | — | **~327 MiB** | 157 MiB | vs FP16: max \|Δscore\| **0.068**, mean **0.031**, **top-5 overlap 5/5** |

**Verdict: Q8_0 on both legs.** FP16 buys one more leading nine on the drift figure (**0.99996 vs 0.99960**) —
a fidelity level already ~40× tighter than any retrieval threshold would notice — for **+269 MiB VRAM per leg**
and **+18 %** query-path latency (16.5 → 19.5 ms). On the reranker the two quantizations are the **same speed
within noise** (0.34–0.38 s) while FP16 costs ~270 MiB more, and their score vectors agree on the whole
ranking that matters: same doc on top (2.12 vs 2.15), **top-5 identical**, mean \|Δ\| 0.031. The one thing that
differs is the ordering **inside the deep tail** (scores at −7.66 vs −7.69 permute), which is tie-breaking noise
rather than a signal, and which `top_n: 5` never shows the caller.

⚠ **Two honesty notes on this table:**
1. **The VRAM figures are relative, not absolute.** The `mem_info_vram_used` deltas (~595 MiB for 1.16 GB of
   FP16 weights, ~326 MiB for 0.63 GB of Q8_0) are ≈50 % of the weight bytes for *both* quantizations — the
   sysfs counter tracks committed pages, not reserved buffers. Use the ratio (FP16 ≈ 1.8× Q8_0) for sizing,
   and re-measure the tier under a real ingest job before finalising the VRAM budget.
2. **`ggml-org/bge-m3-Q8_0-GGUF` and `gpustack/bge-m3-Q8_0.gguf` are different files
   (`aa473d51f451…` vs `950f4a8e5e19…`) but numerically equivalent** — the §3b and §3c drift figures against the
   live Ollama reference agree to five decimals across the two runs, so the conversion is deterministic and the
   mirror choice is about **provenance/maintenance**, not accuracy. (The two reranker Q8_0 mirrors are
   byte-identical: both `a43c7c9b11a4…`.)

## 4. The iGPU question: can the HD 630 serve the reranker?

**It can run it; it should not.** Measured: `llama.cpp --list-devices` with only `renderD128` exposed reports
`Vulkan0: Intel(R) HD Graphics 630 (KBL GT2) (35911 MiB, 32319 MiB free)`, and a rerank server on it does return
correct scores — at **5.8 s / 11.4 s / 22.8 s** (5/10/20 docs). That is **~20× slower than the discrete card and
~2–3× slower than doing nothing but plain CPU**, while holding ~800 MiB of host RAM. Reasons, in order of weight:

| Reason | Evidence |
|--------|----------|
| **Gen 9.5 has no compute acceleration** | 24 EUs, fp32 only, no matrix-coopmat path; and Vulkan/ANV advertises the iGPU's "VRAM" as **35.9 GiB** — i.e. host RAM it may allocate, with no VRAM counter to keep it honest |
| **It is the family desktop** | i915 is the **Xorg primary** ([hardware-gpu.md](hardware-gpu.md) forces the iGPU for Xorg and excludes the dGPU from the desktop); compute load shows up as desktop jank on the PC the family uses |
| **It is already a media device** | `jellyfin` mounts all of `/dev/dri` for **QSV** ([hardware-media template](../IaC/ansible/templates/docker_services/jellyfin/docker-compose.yml.j2)) — a third consumer on Gen 9.5 shares one ring with the compositor and transcodes |
| **Driver support is frozen** | `intel/compute-runtime` `documentation/LEGACY_PLATFORMS.md`: since release **24.35.30872.22** regular packages are **Gen12+**; Gen8/9/11 (Kaby Lake = OpenCL 3.0, Level Zero 1.5) ship only as **`legacy1`-suffixed** packages, frozen on the 24.35 branch, "no new features" |
| **The supported iGPU stack is a different runtime** | OpenVINO's GPU plugin supports Gen 8+ (the officially supported route), but **no rerank-capable server in this repo's option set speaks OpenVINO** — TEI has no OpenVINO backend and `llama.cpp`'s OpenVINO image does not serve `/v1/rerank`. Reaching the iGPU properly means adding **OVMS** + an IR/ONNX conversion step = a **fourth** runtime on a box that already carries ROCm + Vulkan |
| **SYCL is a dead branch here** | `llama.cpp:server-intel` (SYCL) needs Level Zero → on Gen 9 that is `intel-level-zero-gpu-legacy1` (frozen), i.e. the same frozen path with worse support than Vulkan/ANV |

**Verdict:** the iGPU is the wrong device for AI compute on this box — measurably slower than the CPU, contended
with the desktop and Jellyfin, and driver-frozen. Keep it as the display + QSV device only. If a second compute
device is ever needed, the honest candidates are the RX 7600 (5.3 GiB free, §6) or spark — not the HD 630.

## 5. TEI CPU landmines (all three reproduced, all three must be encoded in the template if TEI is kept)

| Landmine | Measurement | Template consequence |
|----------|-------------|----------------------|
| **Warmup RAM bomb** | with default batch flags the INT8 model sat at **10.8 GiB RSS**; under an experimental `--memory=6g` it was **OOMKilled** | `--max-batch-tokens 2048` is mandatory → RSS 2.66 GiB, ready 11 s (default 8192 → 11.25 GiB for **no** latency gain, measured) |
| **Hard 422 on batch size** | `--max-client-batch-size 8` + a 20-doc request → **HTTP 422** (silent pipeline death for RAG top-20) | `--max-client-batch-size ≥ 32` |
| **`OMP_NUM_THREADS` kills startup** | with `OMP_NUM_THREADS=4` **and** with `=8`, readiness never arrived (240 s / 400 s timeouts); unset it warms in 11 s and already uses **~790 % CPU** | **never** set it; cap the leg with `cpus:` in compose instead |
| Model-format footnote | TEI tries `onnx/model.onnx`, then falls back and downloads `model.safetensors` — stock `BAAI/bge-reranker-v2-m3` **does** load on the CPU image (no ONNX export needed); `kftof/…-int8-avx2` serves from a **repo-root** `model.onnx` (works, but non-conventional — `onnx-community/bge-reranker-v2-m3-ONNX` has the conventional `onnx/model_*.onnx` layout) | if TEI is kept, prefer the conventional-layout ONNX repo |

## 6. Co-residency ledger — the whole pinned-AI tier on one 8 GB card

`mem_info_vram_used` on `card1`, live containers untouched (`immich-ml`, `sunshine`, `ollama`, `lan-litellm`,
`jellyfin` all `Up` throughout):

| Stage | VRAM | Note |
|-------|------|------|
| all containers, GPU idle | **66 MiB** | baseline |
| + `bge-m3` warm in `ollama` (ROCm/KFD) | **848–886 MiB** | model ≈ **0.8 GiB**, not the "~1.2 GB" in #24/#25; cold embed 1.87 s, warm 0.075 s |
| + reranker Q8_0 (Vulkan) | **1174 MiB** | Δ **326 MiB** |
| + `whisper large-v3-turbo` fp16 (Vulkan) | **2896 MiB** | Δ 1722 MiB |
| under mixed load (all three busy) | **2929 MiB** | **5.26 GiB free** for immich-ML (3–5 GB) — co-residency plausible, and q5_0 buys back another ~1.0 GiB |
| `immich-ml` **idle** | **0 MiB** | RSS 412 MiB; its VRAM cost exists only during an active job |
| *(if embed moves to the Vulkan runtime, §3b)* | **~2.4 GiB** | replace the 833 MiB ROCm embed leg with ~326 MiB — and `ollama`’s **2.19 GiB host RSS** leaves the picture entirely |

**Concurrency (the question #24/#25 could not answer on paper):**

| Load | whisper (11 s WAV) | rerank (20 docs) | embed |
|------|--------------------|------------------|-------|
| solo, all three resident | 0.65 s | 0.35 s | 0.075 s |
| all three fired simultaneously ×3 | 0.80 – 0.84 s | 0.79 – 0.80 s | 0.09 s |
| 6× sustained mixed | **0.76 – 0.79 s** | **0.76 – 0.79 s** | — |

Contention factor ≈ 1.5–2× at worst, flat under sustained load, host **load ~1.1** (the CPU is not the bottleneck
on the GPU path), and **0 `amdgpu` hang/reset lines** in `dmesg` across ~25 min of Vulkan compute (the CWSR
burn-in item in HD-385(f) is partly satisfied for Vulkan; ROCm/KFD legs were not stressed).
⚠ Pre-existing, **not** caused by these probes: `dmesg` carries **641 × `amdgpu: init_user_pages: Failed to get
user pages: -1`** spread over 2026-09-15 → 09-18, i.e. from the `/dev/kfd` holders (ollama / immich-ml) → **HD-393**.

## 7. What this measurement invalidates

| Claim (source) | Measured 2026-09-18 |
|----------------|---------------------|
| "#25(b): 568 M params, 20 pairs ≈ **10–30 ms/pair**, so GPU buys nothing" | **260 ms per 100-word chunk** on 8 threads; top-20 = 5.3 s (ORT INT8) / 8.0 s (llama.cpp CPU). GPU path = **0.50 s** and 425 MiB |
| "#25(b): GPU rerank would cost **1.5 GB VRAM** + a ROCm runtime" | Vulkan GGUF Q8_0 = **425 MiB**, no ROCm userspace, RSS 157 MiB |
| "#24: pinned tier ≈ **5–6 GB of 8 GB**" (and #25's 3–4 GB) | measured pinned tier = **2.9 GiB** (embed 0.8 + rerank 0.33 + STT 1.7), 5.26 GiB free |
| "#25(b): **Ollama is not a rerank host** — no GGUF reranker path exists" | **Still true for Ollama**, but false as a general statement: `llama.cpp` ships GGUF rerankers (`gpustack/bge-reranker-v2-m3-GGUF`, Apache-2.0) and a `/v1/rerank` endpoint |
| "§9c: `whisper.cpp` server is not OpenAI-compatible → **a thin wrapper is required**" | `--inference-path /v1/audio/transcriptions` makes it OpenAI-shaped; no wrapper |
| "§9c: an official ROCm image path for whisper.cpp **does exist**" | The **Dockerfile** exists (`.devops/main-rocm.Dockerfile`) but **no published artifact**: the docker CI matrix has **no** ROCm entry; ghcr tags = `main, main-musa, main-intel, main-cuda, main-vulkan, main-arm64, main-vulkan-arm64`; Docker Hub `ggmlorg/whisper.cpp` → 404. A self-build = a new build-task pattern with no Renovate trail — this is *why* the STT engine moved to Vulkan (HD-391) |
| "reranker on the iGPU is free capacity" | **5.8–22.8 s** per request (slower than CPU), ~800 MiB host RAM, frozen Gen 9.5 driver stack, contends with Xorg + QSV |
| “#25(a): embed **stays** on Ollama `:rocm` — already live, no reason to move” | There is a measured reason: **33× on the query path (15 ms vs ~500 ms)**, 2.3× ingest, **−507 MiB VRAM**, **−2.0 GiB host RSS**, and **cosine 0.9996 against the live vectors**, so the move costs no correctness-driven re-embed (§3b) |

## 8. Recommendation (**ACCEPTED by owner 2026-09-18** — plan of record: [services-ai.md](services-ai.md) §3a; implementation HD-391)

| Leg | Recommendation | Why |
|-----|----------------|-----|
| **STT** | `ghcr.io/ggml-org/whisper.cpp:main-vulkan` **digest-pinned**, `large-v3-turbo` (q5_0 if VRAM pressure), GPU-first with native CPU fallback, `--inference-path /v1/audio/transcriptions`, `/dev/dri/renderD129` only | published + digest-pinnable artifact, RADV native RDNA3 (no ROCm userspace, no ISA override), 0.4 s / 11 s WAV, no wrapper |
| **Rerank** | `ghcr.io/ggml-org/llama.cpp:server-vulkan` **digest-pinned** + `gpustack/bge-reranker-v2-m3-GGUF` **Q8_0** (§3c: FP16 measured, same speed, +270 MiB, identical top-5) + `--embedding --pooling rank --rerank --device Vulkan0`, routed as LiteLLM **`jina_ai/`** | 0.34–0.50 s for top-20 vs 5.3 s on the CPU, 425 MiB, ~0 % CPU, same backend family as STT, and the wire shape is already the one LiteLLM parses |
| **Embed** | **⏳ also move to the Vulkan runtime** — same `llama.cpp server-vulkan` image + `ggml-org/bge-m3-Q8_0-GGUF` (MIT; **Q8_0 chosen over FP16 — both measured, §3c**) — with **Ollama `:rocm` `bge-m3` kept as the fallback rung** until the Vulkan leg is live-verified, then retired | measured **15 ms vs ~500 ms** per query chunk, 2.3× ingest, **326 MiB vs 899 MiB** VRAM, 157 MiB vs 2.19 GiB RSS, **cosine 0.9996 vs the live vectors** ⇒ same vector space, no correctness-driven re-embed (§3b) |
| Fallback ladder | rerank: llama.cpp Vulkan → TEI `cpu-1.9.4` INT8 (`huggingface/` provider, §5 flags) → `gte-multilingual-reranker-base` (278 M, ~2× cheaper CPU, **unmeasured**) · embed: llama.cpp Vulkan → **Ollama `:rocm`** (already live) → llama.cpp CPU · STT: CPU fallback is native | keeps a CPU path that does not need a GPU device node |

**Budget consequence:** the pinned tier becomes **2.9 GiB VRAM of 8 GiB** with **all three legs on the GPU** —
which *reverses* #25(b)'s "rerank is CPU" placement **on measured grounds**, while keeping #24's placement
(RX 7600 = pinned tier) intact. immich-ML (3–5 GB) still fits at the low end; keep the Sunshine pause glue.
If embed moves too (§3b), the tier drops to **~2.4 GiB** (embed 0.33 + rerank 0.33 + STT 1.72) and the last
`/dev/kfd` consumer of the AI tier disappears.

## 9. Repro

```bash
# STT (dGPU): serves the OpenAI-ish path with no wrapper
docker run -d --name probe-w -p 127.0.0.1:18080:18080 \
  --device /dev/dri/renderD129 --group-add 992 -v $WM:/models:ro \
  --entrypoint /app/build/bin/whisper-server \
  ghcr.io/ggml-org/whisper.cpp@sha256:cf102ac3… \
  --inference-path /v1/audio/transcriptions --host 0.0.0.0 --port 18080 \
  -m /models/ggml-large-v3-turbo.bin -l auto
curl -F "file=@jfk.wav" http://127.0.0.1:18080/v1/audio/transcriptions     # -> {"text": … }

# Rerank (dGPU): GGUF + rank pooling; --device is llama-server's OWN flag (not docker's),
# GGML_VK_VISIBLE_DEVICES only restricts enumeration. Swap renderD128/GGML_VK_VISIBLE_DEVICES=0 for the iGPU.
docker run -d --name probe-r -p 127.0.0.1:18090:8080 \
  --device /dev/dri/renderD129 --group-add 992 -v $M:/models:ro \
  -e GGML_VK_VISIBLE_DEVICES=0 --entrypoint /app/llama-server \
  ghcr.io/ggml-org/llama.cpp@sha256:7158edb4… \
  -m /models/bge-reranker-v2-m3-Q8_0.gguf --embedding --pooling rank --rerank \
  --device Vulkan0 --host 0.0.0.0 --port 8080
curl -d '{"model":"local-reranker","query":"…","top_n":5,"documents":["…"]}' \
     http://127.0.0.1:18090/v1/rerank                                        # -> {"results":[{"index":…,"relevance_score":…}]}

# Rerank (TEI CPU): note the caps (see §5) and that OMP_NUM_THREADS must stay unset
docker run -d -p 127.0.0.1:18085:8080 -v $HF:/data --entrypoint text-embeddings-router \
  ghcr.io/huggingface/text-embeddings-inference@sha256:2538ea1c… \
  --model-id kftof/bge-reranker-v2-m3-onnx-int8-avx2 --port 8080 \
  --max-batch-tokens 2048 --max-client-batch-size 32

# Embed (dGPU, same image): OpenAI-compatible /v1/embeddings; pooling comes from the GGUF (= cls)
docker run -d --name probe-e -p 127.0.0.1:18093:8080 \
  --device /dev/dri/renderD129 --group-add 992 -v $M:/models:ro \
  -e GGML_VK_VISIBLE_DEVICES=0 --entrypoint /app/llama-server \
  ghcr.io/ggml-org/llama.cpp@sha256:7158edb4… \
  -m /models/bge-m3-q8_0.gguf --embedding --device Vulkan0 --host 0.0.0.0 --port 8080
curl -d '{"model":"bge-m3-gguf","input":["Kako nastavim varnostno kopiranje?"]}' \
     http://127.0.0.1:18093/v1/embeddings                       # -> data[0].embedding, dim 1024, |v| = 1.0
# drift check against the LIVE ollama leg (same 51 texts, cosine per doc):
docker run --rm --network llm-backend curlimages/curl -s -X POST http://ollama:11434/api/embed \
  -d '{"model":"bge-m3","input":[ … same texts … ]}'            # -> {"embeddings":[[1024 floats], …]}

# VRAM ledger
watch -n1 'awk "{printf \"%.0f MiB\n\", \$1/1048576}" /sys/class/drm/card1/device/mem_info_vram_used'
```

**Cleanup state (verified):** probe containers 0, `/tmp/probe-*` + model dirs deleted (TEI's HF cache is
root-owned inside `/tmp` — `sudo` needed), probe ports unbound, VRAM back to baseline, all live services `Up`.
Kept deliberately: the three images above (≈ 4.5 GB of 897 GB free) so the implementation converge is not a re-pull.

**Related:** [services-ai.md](services-ai.md) §9 #24/#25 + §9c · [hardware-gpu.md](hardware-gpu.md) ·
[smart-home-voice.md](smart-home-voice.md) · `todo.md` HD-369 / HD-385 / **HD-391 / HD-392 / HD-393**
