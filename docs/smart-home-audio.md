# Audio System

> **Role:** Detail — multi-room audio hardware for music and voice assistant output.
> **Linked from:** `smart-home.md`

---

## Hardware

| Device | Location | Connection | Features |
|--------|----------|------------|----------|
| **WiiM Bar** | Living room / TV | HDMI eARC + Chromecast | Dolby Atmos soundbar, no separate subwoofer. Round display matches Guition kitchen display. |
| **Audio Pro A10 MKII** | Portable | Wi-Fi + Bluetooth | Multi-room with WiiM Bar at home, Bluetooth outdoors |

---

## Multi-Room Strategy

- **WiiM Bar** is the primary living room speaker (TV + music + voice responses)
- **Audio Pro A10 MKII** extends to other rooms via Wi-Fi multi-room
- Both support **Chromecast** — family can cast from Android phones
- Voice assistant responses play through the nearest speaker via HA media player integration

---

## Rejected Options

| System | Reason |
|--------|--------|
| Sonos | No Chromecast (Android-unfriendly), closed ecosystem |
| JBL Authentics | Retro/leather look doesn't fit apartment, requires separate floor subwoofer |
| Bose & Denon (HEOS) | Cloud dependency — Bose killed support for older models, Denon requires cloud login |
| Smart speaker mics (Alexa/Google) | Closed ecosystem — cannot redirect raw audio to local LLM |