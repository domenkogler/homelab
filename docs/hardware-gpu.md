---
title: Shared GPU Resource
role: cross-cutting
domain: hardware
status: active
tags: [hardware, gpu, rocm, cross-cutting]
---
# Shared GPU Resource

> **Role:** Cross-cutting detail — GPU used by LLM, voice, vision, and gaming across multiple domains.
> **Links to:** `llm-office.md`, `smart-home-voice.md`, `services.md`
> **Linked from:** `hardware-oldsrv.md`, `hardware-phase2.md`, `deployment-compose.md`

---

## Phase 1: AMD Radeon RX 7600

| Spec | Value |
|------|-------|
| VRAM | 8 GB GDDR6 |
| Interface | PCIe 4.0 x8 |
| Docker access | `/dev/dri`, `/dev/kfd` |
| Host GPU | Intel HD 630 (iGPU, desktop only) |

### Dual GPU Topology

- **Intel HD 630 (iGPU):** Xorg primary — monitor on motherboard output. Family desktop compositing.
- **Radeon RX 7600 (dGPU):** No monitor. Reserved for Docker containers.
- Xorg config fragment in `/etc/X11/xorg.conf.d/10-igpu-primary.conf` forces iGPU, excludes dGPU.

---

## Phase 2: AMD Radeon AI PRO R9700

| Spec | Value |
|------|-------|
| VRAM | 32 GB |
| Form | Blower, 2-slot |
| Motherboard | ASUS ProArt B850-Creator WiFi NEO (PCIe x8/x8) |
| Future | Second GPU possible (x8/x8 dual-GPU support) |

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

### Phase 2 Modes (R9700, 32 GB)

| Mode | Active Models | VRAM Usage | Trigger |
|------|--------------|------------|---------|
| **Programming** | Qwen 2.5-Coder 32B | ~24 GB | Heavy coding session |
| **Family Home** | Whisper + HA LLM + Piper TTS | ~7 GB | Voice commands |
| **Idle** | None (after 5 min) | ~0 GB (~12 W) | No activity |
| **Gaming** | None | 0 GB | Manual stop AI → Sunshine |

---

## GPU Consumers

| Consumer | Domain | Doc |
|----------|--------|-----|
| Ollama | LLM inference | [`llm-office.md`](llm-office.md) |
| Whisper STT | Voice (speech-to-text) | [`smart-home-voice.md`](smart-home-voice.md) |
| Piper TTS | Voice (text-to-speech) | [`smart-home-voice.md`](smart-home-voice.md) |
| Immich-ML | Photo face recognition | [`services.md`](services.md) |
| Sunshine | Game streaming (manual, secondary) | [`hardware-oldsrv.md`](hardware-oldsrv.md) |

---

## Priority Rules

- **LLM always has priority over gaming**
- Gaming: user manually runs `docker compose stop ollama immich-ml` to free VRAM
- After gaming: `docker compose up -d ollama immich-ml` restores AI
- No automated preemption — manual switch

---

## Docker Device Mappings

```yaml
# For GPU-enabled containers (ollama, immich-ml, sunshine):
devices:
  - /dev/dri:/dev/dri
  - /dev/kfd:/dev/kfd
```

Udev rules set `/dev/kfd` mode 0666 and `/dev/dri/render*` mode 0666 for container access.