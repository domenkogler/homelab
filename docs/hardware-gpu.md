---
title: Shared GPU Resource
role: cross-cutting
domain: hardware
cross_cutting: true
status: active
tags: [hardware, gpu, rocm, cross-cutting]
---
# Shared GPU Resource

> **Role:** Cross-cutting detail — shared GPU resource across AI/vision (immich-ML), voice, and gaming. oldsrv RX 7600 = Sunshine encode + immich-ML batch; spark (GB10) is the separate local-LLM/voice inference tier.
> **Links to:** `services-office.md`, `smart-home-voice.md`, `services.md`
> **Linked from:** `hardware-oldsrv.md`, `hardware-spark.md`, `deployment-compose.md`

---

## Phase 1: AMD Radeon RX 7600 — Sunshine gaming encode + immich-ML batch inference (AI)

> **Corrected 2026-09-09 (owner):** the RX 7600 is **NOT "gaming encode only / no AI."** It serves
> **both** (a) Sunshine game-streaming encode **and** (b) **immich-ML batch inference** — the container
> bundles its own ROCm runtime and needs only `/dev/dri` + `/dev/kfd`. What is *excluded* from the
> dGPU is **host LLM inference**: Ollama is disabled on oldsrv and generation/embeddings/rerank/STT/TTS
> are consolidated on **spark** (Triton, GB10 — HD-335). `amd_rocm` host userland stays
> Debian-trixie-native tooling only (no external AMD repo, HD-318).

| Spec | Value |
|------|-------|
| VRAM | 8 GB GDDR6 |
| Interface | PCIe 4.0 x8 |
| Docker access | `/dev/dri`, `/dev/kfd` |
| GPU workloads | **Sunshine gaming-encode** + **immich-ML batch inference (AI)** — container-bundled ROCm |
| Host GPU | Intel HD 630 (iGPU, desktop only) — Xorg primary |

### Dual GPU Topology

- **Intel HD 630 (iGPU):** Xorg primary — monitor on motherboard output. Family desktop compositing.
- **Radeon RX 7600 (dGPU):** No monitor. **Sunshine game-streaming encode** + **immich-ML batch
  inference (AI)** — immich-ML is a pause-able GPU consumer (2026-09-06) whose container bundles its own
  ROCm runtime and only needs `/dev/dri`+`/dev/kfd`+udev. No **Ollama/LLM** on oldsrv (disabled
  2026-09-07 — generation/embeddings on spark/Triton, HD-335). **Host ROCm = Debian-trixie-native
  tooling only** (`rocm-opencl-icd`/`rocminfo`/`hipcc`, no external AMD repo — HD-318 2026-09-07: the
  Ubuntu-noble AMD repo is incompatible with trixie).
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
| **Immich-ML batch (AI)** | Immich-ML (face/object recognition, container ROCm) | ~3–5 GB | Photo/ML job — pause-able (Sunshine prep-command) |
| **Gaming** | None (Sunshine active) | 0 GB (immich-ML paused) | User launches Sunshine (manual) |
| **Idle** | None | ~0 GB (GPU ~5 W) | No Sunshine stream, no immich-ML job |

### Phase 2 Modes (spark — GB10, 128 GB unified)

`spark` runs the **Triton Inference Server** with the NVFP4 model set (see `hardware-spark.md`).
With 128 GB unified memory there is no tight VRAM budget — models load concurrently; model
swapping is Triton/KeepAlive-driven, not a manual gaming preempt.

| Mode | Active Models | Memory (approx) | Trigger |
|------|--------------|-----------------|---------|
| **Programming / Coding** | Qwen3-Coder-Next-80B | ~50 GB (NVFP4) | Coding session |
| **Family Chat / RAG** | Nemotron-Lightning-30B or Llama-3.3-70B + bge-m3 | ~15–40 GB | Chat / retrieval |
| **Voice** | Whisper-large-v3(-turbo) STT + XTTS/Piper TTS | ~10 GB | Voice commands |
| **Embed/Rerank** | bge-m3 + bge-reranker-v2-m3 | ~5 GB | RAG ingest/query |
| **Idle** | None (Triton model swap / KeepAlive) | ~0–few GB | No activity |

---

## GPU Consumers

| Consumer | Domain | Doc |
|----------|--------|-----|
| ~~Ollama~~ | ~~LLM inference~~ — **removed from oldsrv** (disabled 2026-09-07; inference on spark/Triton, HD-335) | [`services-ai.md`](services-ai.md) |
| Whisper STT | Voice (speech-to-text) — **spark GB10** (Triton, HD-335) | [`smart-home-voice.md`](smart-home-voice.md) |
| Piper TTS | Voice (text-to-speech) — **spark GB10** (Triton, HD-335) | [`smart-home-voice.md`](smart-home-voice.md) |
| **Immich-ML** | **Photo face recognition / ML batch inference (AI)** — container-bundled ROCm | [`services.md`](services.md) |
| **Sunshine** | Game streaming (manual start) — gaming-encode | [`hardware-oldsrv.md`](hardware-oldsrv.md) |

> oldsrv RX 7600 GPU consumers = **Sunshine (gaming encode) + Immich-ML (AI batch)**. Spark (GB10) is
> the separate, **sole local inference tier** for LLM/embeddings/rerank/STT/TTS.

---

## Priority Rules

- **Gaming-first (2026-09-06):** Sunshine owns the GPU for streams; immich-ML batch runs in
  free-GPU time. Sunshine prep-commands `docker pause/unpause immich-ml` freeze/resume ML at
  stream start/end — **no lost work, instant resume** (kernel freeze).
- Sunshine `restart: "no"` (manual-start); idle GPU ~5 W when neither gaming nor ML-active.
- `docker pause` frees compute instantly; VRAM stays allocated until the process re-runs
  (non-issue at 8 GB/3–5 GB ML footprint).
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