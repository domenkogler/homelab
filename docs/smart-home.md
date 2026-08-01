# Smart Home & Voice Assistant

> **Role:** Broad context — Home Assistant, devices, voice pipeline, architecture.
> **Links to:** `smart-home-voice.md`, `smart-home-dashboards.md`, `smart-home-audio.md`
> **Linked from:** `index.md`

---

## Architecture: 100% Local, Cloud-Free

```
[User Voice] → [Guition ESP32-S3 / Android Phone] → Wi-Fi
     → [debhost (Docker)] → Whisper STT
     → [Ollama LLM] → Response text
     → [Piper TTS] → Audio output
     → [Home Assistant] → executes command
     → [WiiM Bar / Audio Pro speaker] → plays response
```

- **Zero cloud dependency** — works if internet is down
- All processing on debhost GPU (RX 7600)
- See [`hardware-gpu.md`](hardware-gpu.md) for GPU sharing strategy

---

## Smart Home Devices

| Device | Location | Protocol | Function |
|--------|----------|----------|----------|
| Guition Round ESP32-S3 + Rotary Knob | Kitchen | ESPHome / Wi-Fi | Wake word mic, visual timer, rotary knob |
| Android phones (family) | All rooms | HA Companion / Willow | Voice satellites (excellent mics) |
| KNX devices | Whole house | KNX bus | Lights, blinds |
| Shelly RGBW2 | Whole house | Wi-Fi | LED strip control |
| Nvidia Shield | Living room | Wi-Fi | Media playback |
| Weather station | Outdoor | HA integration | Temperature, humidity, wind |
| Heat-recovery ventilator | Utility | HA integration | Temperature, flow rates |

---

## Home Assistant

- **Primary:** Raspberry Pi 4 (in daily use — not worth migration risk)
- **Cold standby:** Docker container on debhost (systemd unit, disabled by default)
- **Configs:** In this homelab repo (moved from HA's own GitHub repo)
- **Entity list:** Not yet exported — needed for TileBoard + Grafana generation

---

## Wake Word

- **Language: English** (wider tool support; it's only 2 words)
- **Phrase: "Hey, assistant"** (tentative — family meeting still needed)
- See [`smart-home-voice.md`](smart-home-voice.md) for engine selection

---

## Kitchen Display — Guition Round ESP32-S3

- **Cost:** €20–35
- **Power:** Permanent USB-C (no battery — always listening)
- **Software:** ESPHome
- **Roles:**
  1. Wake word microphone (microWakeWord)
  2. Visual cooking timer (countdown display)
  3. Rotary knob — physical control for timers/lights with wet hands
- **Aesthetic:** Round display, matches WiiM Bar design

---

## Rejected

**Minisforum MS-A2** — considered as dedicated AI/voice processor. Rejected: centralized LLM on debhost GPU avoids managing two separate AI devices.

---

## Open Questions

- Home Assistant entity list (needed for TileBoard + Grafana)
- Wall-mounted tablet model for TileBoard
- Wake word final approval ("Hey, assistant" is tentative)

---

## Document Map

| For | Read |
|-----|------|
| Voice pipeline details | [`smart-home-voice.md`](smart-home-voice.md) |
| Dashboards & interfaces | [`smart-home-dashboards.md`](smart-home-dashboards.md) |
| Audio hardware | [`smart-home-audio.md`](smart-home-audio.md) |