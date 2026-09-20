---
title: Voice Pipeline
role: detail
domain: smart-home
status: active
tags: [smart-home, voice, whisper, piper]
---
# Voice Pipeline

> **Role:** Detail — Whisper STT, LLM, Piper TTS pipeline.
> **Links to:** `hardware-gpu.md`, `services-office.md`
> **Linked from:** `smart-home.md`
>
> **Shape (decision #24):** Whisper STT runs on the **oldsrv RX 7600**, Piper TTS on **CPU**, and the LLM
> leg (intent/response) is meant to be a **gateway model** reached through LiteLLM like every other
> simple querier — never a direct engine URL. See [services-ai.md](services-ai.md) §Architecture for the
> routing model and §9c for the GPU model.
>
> ⚠ **That leg does not exist yet.** Home Assistant has **no LiteLLM consumer, no scoped key and no
> gateway env wiring** in the deployment (`home-assistant-primary` renders `environment: {}`), so voice's
> LLM step has nothing to call. The STT engine underneath it is live; the wiring is open work
> ([Q-A.md](Q-A.md) finding 4, alongside HD-384's consumer work).
>
> **Engine = `whisper.cpp` `main-vulkan`, digest-pinned** (decision #27) — RADV, native RDNA3, no ROCm
> userspace. Two earlier recipes were ruled out by evidence, not preference: a ROCm/`GGML_HIP` build
> (correct in theory, **no published artifact**) and PyTorch ROCm images (wrong target + heavy). The chain
> and its sources live in [services-ai.md](services-ai.md) §9 and
> [services-rejected.md](services-rejected.md). Two consequences worth carrying: **a build recipe nobody
> publishes is not an option**, and with Vulkan the weight lives on the card, so container RSS (~34 MiB) is
> **not** "VRAM used".
>
> Measured on this card: `large-v3-turbo` **0.40 s** per 11 s WAV at **1.72 GiB** VRAM; CPU fallback
> **17.5 s** — and that fallback is **native**, decided at init, so a container that never touches the GPU
> never notices. Numbers: [services-ai-bench.md](services-ai-bench.md) §2.

---

## Pipeline Flow

```
Microphone → Wake Word Detection → Whisper STT → LLM → Piper TTS → Speaker
   (ESP32)      (microWakeWord)      (RX 7600)   (spark)    (CPU)      (WiiM Bar)
```

---

## Wake Word Detection

### ESP32-S3 (Kitchen Display)
- **microWakeWord** — open-source, ESP32-compatible, Wyoming protocol
- **ESP-SR** (Espressif Speech Recognition) — built-in, free, custom wake words
- Limitation: ESP32-S3 limited RAM; ~2-word English wake words feasible

### Android Phones (Satellites)
- **Willow** (open-source) or **Home Assistant Companion** with Assist
- Far better microphones and noise cancellation than ESP32
- On-device wake word detection — no server load

> **Recommendation:** microWakeWord on ESP32-S3 for kitchen (fixed location, known acoustics). HA Assist on Android phones for other rooms. Both feed same central STT pipeline.

---

## Components

| Stage | Software | Hardware | Notes |
|-------|----------|----------|-------|
| **Wake Word** | microWakeWord / HA Assist | ESP32-S3 / Android | "Hey, assistant" |
| **STT** | **`whisper.cpp` `main-vulkan`** (`whisper-server`, digest-pinned) — **not** faster-whisper (CTranslate2 is CUDA-only) | **oldsrv RX 7600** (Vulkan/RADV — no `/dev/kfd`, no `HSA_*`) | **Slovenian** + English → text (multilingual GGML, measured `n_langs = 100`). **No OpenAI-compat wrapper needed**: `--inference-path /v1/audio/transcriptions` — measured, see [services-ai-bench.md](services-ai-bench.md) §2 |
| **LLM** | Gateway model via LiteLLM — `openai/spark/qwen3.8-flash-next` (fast) or `openai/spark/qwen3.6-27b` (reasoning) | **spark GB10**, through the gateway | Intent parsing, response generation |
| **TTS** | Piper TTS | **CPU** (decision #24 — CPU-only engine) | Text → Slovenian speech |

---

## GPU VRAM for Voice

When voice is active, GPU runs in **Pinned-AI** mode (decision #24):

| Model | VRAM |
|-------|------|
| Whisper STT (`large-v3-turbo` GGML) | ~2 GB → **measured 1.79 GiB fp16 / 0.77 GiB q5_0** ([services-ai-bench.md](services-ai-bench.md) §2) |
| bge-m3 embed (RAG, co-resident) | ~1–2 GB |
| bge-reranker (RAG, co-resident) | ~0.5 GiB **on the GPU** — the CPU detour was a stale-table artifact (#25) |
| **Total (pinned-AI)** | **2475 MiB measured all-three warm** (of 8 GB) — [hardware-gpu.md](hardware-gpu.md) |
| Piper TTS | **CPU** (~0.5 GB RAM, instant) |
| LLM (intent/response) | **spark GB10** (big-model tier) |

> **Why Vulkan and not ROCm:** `whisper.cpp` ships a ROCm Dockerfile but **publishes no ROCm artifact**
> (no ghcr tag, Docker Hub 404), so the ROCm route means owning a `GGML_HIP` + native-`gfx1102` build in
> this repo — a private compile-and-publish pipeline for a card whose real profile is RADV desktop graphics +
> compute. Also rejected: PyTorch ROCm images (they force `HSA_OVERRIDE_GFX_VERSION=10.3.0` = gfx1030 code
> paths on RDNA3, drag gradio/demucs/stable-ts, and want `seccomp=unconfined` + `SYS_PTRACE` + host IPC) and
> faster-whisper (CTranslate2 has no ROCm backend). The Vulkan image needs only `/dev/dri/renderD128` +
> `video`/`render` group membership. Decision chain + evidence:
> [services-ai.md](services-ai.md) §9 · [hardware-gpu.md](hardware-gpu.md).

> **VRAM priority (decision #24):** gaming > pinned-AI (voice/embed/rerank) > immich-ML. Pinned-AI measures
> **2475 MiB** all-three warm, so pinned-AI + immich-ML fit under 8 GB and immich-ML does not have to be
> paused for voice — and `pause` would not free VRAM anyway ([hardware-gpu.md](hardware-gpu.md)).

See [`hardware-gpu.md`](hardware-gpu.md) for the full VRAM management table.

---

## Language Pipeline

- **Wake word:** English (2 words — wider tool support)
- **STT:** English (Whisper supports multilingual, but English best accuracy)
- **LLM:** Slovenian response generation (spark big-model — Qwen3-Coder-Next-80B / Nemotron support Slovenian)
- **TTS:** Slovenian output (Piper has Slovenian voice models)

---

## Not Yet Implemented

Depends on:
1. oldsrv with GPU operational (RX 7600, pinned-AI mode)
2. Whisper (faster-whisper) + bge-m3/bge-reranker containers on oldsrv (decision #24)
3. Piper TTS on CPU
4. ESP32-S3 flashed with ESPHome + microWakeWord
5. HA Assist configured on family phones