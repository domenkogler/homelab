---
title: Shared GPU Resource
role: cross-cutting
domain: hardware
cross_cutting: true
status: active
tags: [hardware, gpu, rocm, cross-cutting]
---
# Shared GPU Resource

> **Role:** Cross-cutting detail — GPU used by LLM, voice, vision, and gaming across multiple domains.
> **Links to:** `services-office.md`, `smart-home-voice.md`, `services.md`
> **Linked from:** `hardware-oldsrv.md`, `hardware-spark.md`, `deployment-compose.md`

---

## Phase 1: AMD Radeon RX 7600 — gaming encode ONLY (no AI)

| Spec | Value |
|------|-------|
| VRAM | 8 GB GDDR6 |
| Interface | PCIe 4.0 x8 |
| Docker access | `/dev/dri`, `/dev/kfd` |
| Host GPU | Intel HD 630 (iGPU, desktop only) |

### Dual GPU Topology

- **Intel HD 630 (iGPU):** Xorg primary — monitor on motherboard output. Family desktop compositing.
- **Radeon RX 7600 (dGPU):** No monitor. **Sunshine game-streaming encode only** (non-AI).
  All AI inference moved to spark (2026-09-06). No ROCm/Ollama.
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

`OLLAMA_KEEP_ALIVE=5m` set in `/etc/environment` — model unloads after 5 min of LLM inactivity.

### Phase 1 Modes (RX 7600, 8 GB)

| Mode | Active Models | VRAM Usage | Trigger |
|------|--------------|------------|---------|
| **LLM Active** | Qwen 2.5-Coder 14B or Llama 3.1 8B | 6–8 GB (near full) | API request received |
| **Voice + Vision** | Whisper STT + Piper TTS + Immich-ML | ~3–5 GB | Voice command or photo upload |
| **Idle** | None (after 5 min) | ~0 GB (GPU ~12 W) | No activity for 5 minutes |
| **Gaming** | None (Ollama + Immich-ML stopped) | 0 GB | User manually stops AI containers → launches Sunshine |

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
| Ollama | LLM inference | [`services-office.md`](services-office.md) |
| Whisper STT | Voice (speech-to-text) | [`smart-home-voice.md`](smart-home-voice.md) |
| Piper TTS | Voice (text-to-speech) | [`smart-home-voice.md`](smart-home-voice.md) |
| Immich-ML | Photo face recognition | [`services.md`](services.md) |
| Sunshine | Game streaming (manual, secondary) | [`hardware-oldsrv.md`](hardware-oldsrv.md) |

---

## Priority Rules

- **GPU = gaming encode only** (2026-09-06); no AI competes for it (AI is on spark).
- Sunshine is manual-start (`restart: "no"`); when not streaming the GPU idles (~5 W).
- No automated preemption needed — no AI container shares the dGPU anymore.

---

## Docker Device Mappings

```yaml
# For GPU-enabled containers (ollama, immich-ml, sunshine):
devices:
  - /dev/dri:/dev/dri
  - /dev/kfd:/dev/kfd
```

Udev rules set `/dev/kfd` mode 0666 and `/dev/dri/render*` mode 0666 for container access.