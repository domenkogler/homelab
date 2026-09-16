---
title: Shared GPU Resource
role: cross-cutting
domain: hardware
cross_cutting: true
status: active
tags: [hardware, gpu, rocm, cross-cutting]
---
# Shared GPU Resource

> **Role:** Cross-cutting detail — shared GPU resource across AI/vision (immich-ML), voice, and gaming. oldsrv RX 7600 = **pinned AI services (STT/embed/rerank) + Sunshine encode + immich-ML batch**; spark (GB10) is the separate **big-model generation tier** (decision #24, 2026-09-15).
> **Links to:** `services-office.md`, `smart-home-voice.md`, `services.md`
> **Linked from:** `hardware-oldsrv.md`, `hardware-spark.md`, `deployment-compose.md`

---

## Phase 1: AMD Radeon RX 7600 — Sunshine gaming encode + immich-ML batch inference (AI)

> **Corrected 2026-09-09 (owner), refined 2026-09-15 (decision #24):** the RX 7600 is **NOT "gaming
> encode only / no AI."** It serves (a) Sunshine game-streaming encode, (b) **immich-ML batch
> inference**, and (c) — **NEW 2026-09-15** — the **pinned AI services: Whisper STT + bge-m3 embed +
> bge-reranker** (container-bundled ROCm, ≈5–6 GB of 8 GB). What is *excluded* from the dGPU is
> **host LLM inference and big-model generation**: Ollama is disabled on oldsrv and the large
> generation models run on **spark** (Triton, GB10 — HD-335). `amd_rocm` host userland stays
> Debian-trixie-native tooling only (no external AMD repo, HD-318).

| Spec | Value |
|------|-------|
| VRAM | 8 GB GDDR6 |
| Interface | PCIe 4.0 x8 |
| Docker access | `/dev/dri`, `/dev/kfd` |
| GPU workloads | **Pinned AI services (Whisper STT + bge-m3 embed + bge-reranker, decision #24) + Sunshine gaming-encode + immich-ML batch inference (AI)** — container-bundled ROCm |
| Host GPU | Intel HD 630 (iGPU, desktop only) — Xorg primary |

### Dual GPU Topology

- **Intel HD 630 (iGPU):** Xorg primary — monitor on motherboard output. Family desktop compositing.
- **Radeon RX 7600 (dGPU):** No monitor. **Pinned AI services (Whisper STT + bge-m3 embed + bge-reranker,
  decision #24) + Sunshine game-streaming encode** + **immich-ML batch inference (AI)** — all pause-able
  GPU consumers (2026-09-06) whose containers bundle their own ROCm runtime and only need
  `/dev/dri`+`/dev/kfd`+udev. No **Ollama/LLM** on oldsrv (disabled 2026-09-07 — big-model generation on
  spark/Triton, HD-335). **Host ROCm = Debian-trixie-native tooling only** (`rocm-opencl-icd`/`rocminfo`/`hipcc`,
  no external AMD repo — HD-318 2026-09-07: the Ubuntu-noble AMD repo is incompatible with trixie).
- Xorg config fragment in `/etc/X11/xorg.conf.d/10-igpu-primary.conf` forces iGPU, excludes dGPU.

---

## Phase 2: NVIDIA GB10 Grace Blackwell (spark)

The old planned Phase 2 GPU (AMD Radeon AI PRO R9700 32 GB, Ryzen build) is **superseded** by the
NVIDIA **GB10 Grace Blackwell** superchip in the ThinkStation PGX (`hardware-spark.md`). Not a
discrete GPU — a unified CPU+GPU superchip with **128 GB shared LPDDR5x** memory (no separate VRAM
division) and **1 PFLOP FP4**.

| Spec | Value |
|------|-------|
| Superchip | NVIDIA GB10 Grace Blackwell (20-core Arm + Blackwell GPU) |
| Unified memory | **128 GB** LPDDR5x (shared CPU/GPU, 256-bit, 273 GB/s) |
| AI performance | **1000 TOPS · 1 PFLOP (FP4)** |
| Node | `spark.kogler.si` — ThinkStation PGX SFF |

---

## VRAM Management

> **Legacy note:** `OLLAMA_KEEP_ALIVE`/Ollama-era modes were removed (Ollama disabled on oldsrv
> 2026-09-07). Current dGPU consumers = Sunshine (gaming) + immich-ML (batch); LLM inference runs on
> spark (GB10).

### Phase 1 Modes (RX 7600, 8 GB)

| Mode | Active Models | VRAM Usage | Trigger |
|------|--------------|------------|---------|
| **Pinned AI (voice/embed/rerank)** | Whisper STT (~2 GB) + bge-m3 embed (~1–2 GB) + bge-reranker (~1–2 GB) | **~5–6 GB** | Voice command / RAG ingest-query — pause-able (Sunshine prep-command) |
| **Immich-ML batch (AI)** | Immich-ML (face/object recognition, container ROCm) | ~3–5 GB | Photo/ML job — **lowest priority** (paused when pinned-AI active) |
| **Gaming** | None (Sunshine active) | 0 GB (pinned-AI + immich-ML paused) | User launches Sunshine (manual) |
| **Idle** | None | ~0 GB (GPU ~5 W) | No Sunshine stream, no pinned-AI, no immich-ML job |

### Phase 2 Modes (spark — GB10, 128 GB unified)

`spark` runs the **big-model generation tier** (decision #24, 2026-09-15) — the NVFP4 generation set
(see `hardware-spark.md`). With 128 GB unified memory there is no tight VRAM budget — models load
concurrently; model swapping is Triton/KeepAlive-driven, not a manual gaming preempt. The small
pinned services (STT/embed/rerank) moved to the oldsrv RX 7600 (decision #24).

> ⚠️ **2026-09-16 correction:** earlier wording here ("no tight VRAM budget — models load concurrently")
> is **wrong for vLLM today**. There IS a hard budget — but it is a **host-RAM budget**: on GB10 every GPU
> allocation is the same 121.62 GiB pool the OS runs in, and vLLM's `gpu_memory_utilization`
> replace-by-percentage arithmetic eats the host's reserve. Three global-OOM incidents in 24 h
> (2026-09-15 ×2, 2026-09-16 ×1; kernel killed the user session before the engine on the third).
> Budget mechanics, sizing table, incident log + diagnosis recipe: [hardware-spark.md](hardware-spark.md)
> **§Unified-memory budget & OOM governance**. Simply put: the *only* real governor of host headroom on
> this box is vLLM's `--kv-cache-memory`/`gpu_memory_utilization`; the container memory cage cannot
> protect the host (GPU pages are not cgroup-charged).

| Mode | Active Models | Memory (approx) | Trigger |
|---|---|---|---|
| **Programming / Coding** | Qwen3-Coder-Next-80B | ~50 GB (NVFP4) | Coding session |
| **Family Chat / RAG** | Nemotron-Lightning-30B or Llama-3.3-70B | ~15–40 GB | Chat / retrieval |
| **Idle** | None (Triton model swap / KeepAlive) | ~0–few GB | No activity |

---

## GPU Consumers

| Consumer | Domain | Doc |
|----------|--------|-----|
| ~~Ollama~~ | ~~LLM inference~~ — **removed from oldsrv** (disabled 2026-09-07; big-model generation on spark/Triton, HD-335) | [`services-ai.md`](services-ai.md) |
| Whisper STT | Voice (speech-to-text) — **oldsrv RX 7600** (decision #24, 2026-09-15) | [`smart-home-voice.md`](smart-home-voice.md) |
| Piper TTS | Voice (text-to-speech) — **CPU** (CPU-only engine, decision #24) | [`smart-home-voice.md`](smart-home-voice.md) |
| bge-m3 embed | RAG embeddings — **oldsrv RX 7600** (decision #24) | [`services-ai.md`](services-ai.md) |
| bge-reranker | RAG rerank — **oldsrv RX 7600** (decision #24) | [`services-ai.md`](services-ai.md) |
| **Immich-ML** | **Photo face recognition / ML batch inference (AI)** — container-bundled ROCm, **lowest priority** | [`services.md`](services.md) |
| **Sunshine** | Game streaming (manual start) — gaming-encode | [`hardware-oldsrv.md`](hardware-oldsrv.md) |

> oldsrv RX 7600 GPU consumers = **pinned AI (STT/embed/rerank, decision #24) + Sunshine (gaming encode) + Immich-ML (AI batch, lowest priority)**. Spark (GB10) is the separate **big-model generation tier**.

---

## Priority Rules

- **Gaming-first (2026-09-06):** Sunshine owns the GPU for streams; pinned-AI + immich-ML batch run in
  free-GPU time. Sunshine prep-commands `docker pause/unpause` freeze/resume the AI consumers at
  stream start/end — **no lost work, instant resume** (kernel freeze).
- **Priority order (decision #24, 2026-09-15):** gaming > pinned-AI (voice/embed/rerank) > immich-ML.
  Pinned-AI ≈5–6 GB + immich-ML ≈3–5 GB would exceed 8 GB → they must not run simultaneously;
  immich-ML is paused when pinned-AI is active.
- Sunshine `restart: "no"` (manual-start); idle GPU ~5 W when neither gaming nor AI-active.
- `docker pause` frees compute instantly; VRAM stays allocated until the process re-runs
  (non-issue at 8 GB/5–6 GB pinned-AI footprint).
- No automated preemption beyond the pause-mechanism; CPU fallback for immich-ML only if
  ONNX-GPU proves fragile (not the default).

---

## Docker Device Mappings

```yaml
# For GPU-enabled containers (immich-ml, sunshine):
devices:
  - /dev/dri:/dev/dri
  - /dev/kfd:/dev/kfd
```

Udev rules set `/dev/kfd` mode 0666 and `/dev/dri/render*` mode 0666 for container access.