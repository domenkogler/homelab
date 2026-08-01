# Voice Pipeline

> **Role:** Detail — Whisper STT, Ollama LLM, Piper TTS pipeline.
> **Links to:** `hardware-gpu.md`, `llm-office.md`
> **Linked from:** `smart-home.md`

---

## Pipeline Flow

```
Microphone → Wake Word Detection → Whisper STT → Ollama LLM → Piper TTS → Speaker
   (ESP32)      (microWakeWord)      (GPU)         (GPU)        (GPU)      (WiiM Bar)
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
| **STT** | Whisper (faster-whisper) | debhost GPU (RX 7600) | English speech → text |
| **LLM** | Ollama (Llama 3.1 8B / Qwen 2.5 7B) | debhost GPU (RX 7600) | Intent parsing, response generation |
| **TTS** | Piper TTS | debhost GPU (RX 7600) | Text → Slovenian speech |

---

## GPU VRAM for Voice

When voice is active, GPU runs in **Voice + Vision** mode:

| Model | VRAM |
|-------|------|
| Whisper STT | ~2 GB |
| Ollama (light model) | ~3 GB |
| Piper TTS | ~0.5 GB |
| Immich-ML (background) | ~2 GB |
| **Total** | ~7–8 GB (near RX 7600 limit) |

See [`hardware-gpu.md`](../hardware-gpu.md) for the full VRAM management table.

---

## Language Pipeline

- **Wake word:** English (2 words — wider tool support)
- **STT:** English (Whisper supports multilingual, but English best accuracy)
- **LLM:** Slovenian response generation (Llama 3.1 + Qwen support Slovenian)
- **TTS:** Slovenian output (Piper has Slovenian voice models)

---

## Not Yet Implemented

Depends on:
1. debhost with GPU operational
2. Ollama + model downloads
3. Whisper + Piper containers
4. ESP32-S3 flashed with ESPHome + microWakeWord
5. HA Assist configured on family phones