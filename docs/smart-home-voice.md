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
> **Placement (decision #24, 2026-09-15):** Whisper STT runs on the **oldsrv RX 7600** (container-bundled
> ROCm, ~2 GB); Piper TTS runs on **CPU** (CPU-only engine, ~0.5 GB, instant); the LLM (intent/response)
> runs on **spark** (big-model generation tier).

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
| **STT** | Whisper (faster-whisper) | **oldsrv RX 7600** (decision #24) | English speech → text |
| **LLM** | spark big-model (Qwen3-Coder-Next-80B / Nemotron) | **spark GB10** (decision #24) | Intent parsing, response generation |
| **TTS** | Piper TTS | **CPU** (decision #24 — CPU-only engine) | Text → Slovenian speech |

---

## GPU VRAM for Voice

When voice is active, GPU runs in **Pinned-AI** mode (decision #24):

| Model | VRAM |
|-------|------|
| Whisper STT | ~2 GB |
| bge-m3 embed (RAG, co-resident) | ~1–2 GB |
| bge-reranker (RAG, co-resident) | ~1–2 GB |
| **Total (pinned-AI)** | **~5–6 GB (of 8 GB)** |
| Piper TTS | **CPU** (~0.5 GB RAM, instant) |
| LLM (intent/response) | **spark GB10** (big-model tier) |

> **Priority (decision #24):** gaming > pinned-AI (voice/embed/rerank) > immich-ML. Pinned-AI ≈5–6 GB
> + immich-ML ≈3–5 GB would exceed 8 GB → immich-ML is paused when pinned-AI is active.

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