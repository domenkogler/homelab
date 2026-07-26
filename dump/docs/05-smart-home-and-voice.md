# Smart Home & Voice Assistant

> **Canonical doc.** Merges: `Načrt Homelab sistema_ Lokalni slovenski glasovni asistent in avdio sistem.md`, `Homeassistant rework.md`, `Homeassistant rework prompt.md` (superseded template).

---

## Architecture: 100% Local, Cloud-Free

```
[User Voice] → [Guition ESP32-S3 / Android Phone] → Wi-Fi
     → [Home Server (Docker)] → Whisper STT (English wake word)
     → [Ollama LLM] → Response text
     → [Piper TTS] → Audio output
     → [Home Assistant] → executes command
     → [WiiM Bar / Audio Pro speaker] → plays response
```

- **Zero cloud dependency** — works if internet is down
- All processing on the home server GPU (Radeon RX 7600 or future R9700)
- In Phase 1, GPU is accessed directly by Docker containers via `/dev/dri` and `/dev/kfd` (no LXC passthrough layer). Phase 2 uses Proxmox LXC GPU passthrough.

---

## Wake Word

- **Language: English** (wider tool support; it's only 2 short words)
- **Phrase: "Hey, assistant"** (tentative — family meeting still needed for final approval)
- **Wake word detection engine:** Depends on the final hardware choice.

### Wake Word Engine Recommendation

For **ESP32-S3** (Guition display):
- **ESP-SR** (Espressif Speech Recognition) — built-in, free, supports custom wake words
- **microWakeWord** — open-source, runs on ESP32, compatible with Home Assistant's Wyoming protocol
- Limitation: ESP32-S3 has limited RAM; custom English wake words (~2 words) are feasible, but accuracy depends on ambient noise

For **Android phones** (as satellites):
- **Willow** (open-source) or **Home Assistant Companion** with Assist
- Phones have far better microphones and noise cancellation than ESP32
- Can run wake word detection on-device (no server load)

> **Recommendation:** Use **microWakeWord** on the ESP32-S3 for the kitchen display (fixed location, known acoustics). Use **Home Assistant Assist** on Android phones for other rooms. Both feed into the same central STT pipeline on the server.

---

## Smart Home Devices

| Device | Location | Protocol | Function |
|--------|----------|----------|----------|
| Guition Round ESP32-S3 + Rotary Knob | Kitchen | ESPHome / Wi-Fi | Wake word mic, visual timer, rotary knob (wet/messy hands safe) |
| Android phones (family) | All rooms | HA Companion / Willow | Voice satellites (free, excellent mics, noise cancellation) |
| KNX devices | Whole house | KNX bus | Lights, blinds |
| Shelly RGBW2 | Whole house | Wi-Fi | LED strip control |
| Nvidia Shield | Living room | Wi-Fi | Media playback |
| Weather station | Outdoor | HA integration | Temperature, humidity, wind |
| Heat-recovery ventilator | Utility | HA integration | Temperature, flow rates |

---

## Audio System

| Device | Location | Connection | Features |
|--------|----------|------------|----------|
| **WiiM Bar** | Living room / TV | HDMI eARC + Chromecast | Dolby Atmos all-in-one soundbar, no separate subwoofer needed. Round display matches Guition kitchen display aesthetically. |
| **Audio Pro A10 MKII** | Portable | Wi-Fi + Bluetooth | Multi-room with WiiM Bar when home, Bluetooth when outdoors |

### What Was Rejected & Why

| System | Reason |
|--------|--------|
| Sonos | No Chromecast (Android-unfriendly), closed ecosystem |
| JBL Authentics | Retro/leather look doesn't fit apartment, requires separate floor subwoofer |
| Bose & Denon (HEOS) | Cloud dependency — Bose killed support for older models, Denon requires cloud login |
| Smart speaker mics (Alexa/Google) | Closed ecosystem — cannot redirect raw audio to local LLM |

---

## Dashboards

### TileBoard — Control Dashboard
- **Purpose:** Fast control for lights, blinds, Shelly RGBW, media (Nvidia Shield)
- **Display:** Wall-mounted tablet or PC
- **Style:** Dark mode, modern, minimal
- Waiting on entity list from Home Assistant to generate `config.js`

### Grafana — Analytics Dashboard
- **Purpose:** Time-series data visualization
- **Data sources:** InfluxDB (fed by HA / Telegraf from MikroTik)
- **Graphs planned:**
  - MikroTik traffic (24h, 1s refresh)
  - Weather station temperature trends (7 days)
  - Heat-recovery ventilator temperatures and flow rates
- **Integration:** Grafana panels embedded in TileBoard via `TYPES.IFRAME` tiles

### Home Assistant
- Central hub for all device integration
- Currently running on Raspberry Pi 4
- **Stays on Raspberry Pi 4** (daily use — not worth migration risk)
- **Backup LXC on home server** as cold standby
- **Configs:** Move from HA's own GitHub repo into this homelab repo

## Wall-Mounted Tablet

- **Not decided yet** — model/resolution affects TileBoard config sizing
- Options under consideration: iPad, Android tablet, repurposed screen

---

## Home Assistant Entity List

The TileBoard + Grafana prompts are ready — they need the actual HA entity list to generate `config.js` and Grafana dashboard JSON.

> **Next step:** Export HA entity list and feed it to the prompt template.

---

## Kitchen Display Details

**Guition Round ESP32-S3 with Rotary Knob:**
- Cost: €20–35
- Power: Permanent USB-C (no battery — microphone always listening)
- Software: ESPHome
- Roles:
  1. Wake word microphone (microWakeWord)
  2. Visual cooking timer (countdown display)
  3. Rotary knob — physical control for timers/lights with wet or flour-covered hands
- Front glass: splash-resistant (not officially waterproof)
- Aesthetic: round display, matches WiiM Bar design language

---

## Rejected Approach

**Minisforum MS-A2** — initially considered as dedicated AI/voice processor with NPU. **Rejected** in favor of centralized LLM processing on the home server. The custom server's GPU handles all inference (voice + LLM + image recognition). This avoids managing two separate AI-capable devices.

---

## Open Questions

- **What is the Home Assistant entity list?** (needed for TileBoard + Grafana generation)
- **Wall-mounted tablet model for TileBoard?** (not decided yet)
- **Wake word final approval?** ("Hey, assistant" is tentative)