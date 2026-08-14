---
title: Smart Home & Voice Assistant
role: broad
domain: smart-home
status: active
tags: [smart-home, homeassistant]
---
# Smart Home & Voice Assistant

> **Role:** Broad context — Home Assistant, devices, voice pipeline, architecture.
> **Links to:** `smart-home-voice.md`, `interfaces.md`, `smart-home-audio.md`
> **Linked from:** `index.md`

---

## Architecture: 100% Local, Cloud-Free

```
[User Voice] → [Guition ESP32-S3 / Android Phone] → Wi-Fi
     → [oldsrv (Docker)] → Whisper STT
     → [Ollama LLM] → Response text
     → [Piper TTS] → Audio output
     → [Home Assistant] → executes command
     → [WiiM Bar / Audio Pro speaker] → plays response
```

- **Zero cloud dependency** — works if internet is down
- All processing on oldsrv GPU (RX 7600)
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
| Weather station (**HmIP-SWO-B**) | Outdoor | Homematic IP (868 MHz) | Temperature, humidity, wind, relative brightness, sunshine duration |
| Heat-recovery ventilator (**Zehnder ComfoAir Q**) | Utility | KNX (ComfoConnect KNX-C) | Temperatures, flow rates |

---

## Home Assistant

- **Host (node):** `pi.kogler.si` (Raspberry Pi 4, in daily use) — **primary**; accessed via the VIP `ha.kogler.si`
- **Fallback:** `home-assistant-standby` Docker container on oldsrv (systemd unit, disabled by default) — **active/standby failover, manual trigger + manual failback**
- **Configs:** In this homelab repo (moved from HA's own GitHub repo)

> **Failover design → [`smart-home-failover.md`](smart-home-failover.md).** Both nodes share a VIP (keepalived/VRRP); `ha.kogler.si` routes to the VIP so takeover needs no DNS flip or per-device reconfig. WAN loss is NOT a trigger (HA is local); failover is only for Pi failure and must work offline.
- **Entity list:** Not yet exported — needed for TileBoard + Grafana generation (enable HA Prometheus exporter: see `observability.md`)

### Remote access & SSO (ha.kogler.si)

- **Web UI (browser):** SSO via **Authentik** using HA's native **OpenID Connect (OIDC)** integration — family logs into Authentik (passkey), no separate HA password.
- **Companion app / Android Auto:** uses HA's **long-lived access token** (one-time pairing, authenticated through Authentik). The **`ha` route must NOT use Authentik Forward-Auth** — that would break the app's WebSocket/API and token flow.
- **Security:** at the edge keep Traefik + CrowdSec/rate-limit; in HA set `http.use_x_forwarded_for: true` + `trusted_proxies: <Traefik>`. Keep **one local `owner` account** as a recovery fallback if Authentik is unreachable.
- Config: `configuration.yaml` templated from this repo (see `deployment-ansible.md` → `home_assistant` role).

---

## Homematic IP & KNX Integration

- **Weather sensor HmIP-SWO-B** pairs over Homematic IP radio; HA integration = **`homematicip_cloud`** (current, HAP cloud mode).
- **Rekuperator ComfoAir Q 350/450** connects via **ComfoConnect KNX-C** module → KNX TP bus → **GIRA IP Router `.118`**; HA integration = **`knx`**.
- **Local RF plan (during the redo, replaces HAP cloud mode):** a **HmIP-RFUSB stick + RaspberryMatic** on the Pi (Debian/Docker) gives full local, zero-cloud Homematic IP. HA talks to RaspberryMatic over **XML-RPC 2001/2010** via the legacy **`homematic`** integration. Pairing is stored **on the stick**, so it survives a host change.
- **Failover of Homematic** is the one physical step in the HA failover model: if the Pi dies, the stick is **physically moved to oldsrv** (pairing travels with it → no re-pair) and the single failover trigger brings up RaspberryMatic + HA standby. See [`smart-home-failover.md`](smart-home-failover.md).
- **HA recorder:** after observability is live, **trim, NOT disable, recorder history** (`purge_keep_days: 1–2`, `commit_interval` up, `exclude` noisy domains) to cut Raspberry Pi microSD writes — Grafana reads central Prometheus for long-term graphs. **Kept enabled** deliberately: it still powers the **Logbook**, **Energy Dashboard (long-term statistics)** (KNX appliance-current sensors → kWh), and `history_stats` / `history()` templates that Grafana doesn't cover. Full Pi SD-wear strategy (recorder + Docker-log driver + tmpfs `/var/log`): [`observability.md`](docs/observability.md) → *Pi SD-card wear strategy*.

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

**Minisforum MS-A2** — considered as dedicated AI/voice processor. Rejected: centralized LLM on oldsrv GPU avoids managing two separate AI devices.

---

## Open Questions

- Home Assistant entity list (needed for TileBoard + Grafana)
- Wall-mounted tablet model for TileBoard
- Wake word final approval ("Hey, assistant" is tentative)
- Confirmed HmIP-SWO-B channels: no rain / wind-direction (not part of this sensor)

---

## Document Map

| For | Read |
|-----|------|
| Voice pipeline details | [`smart-home-voice.md`](smart-home-voice.md) |
| Dashboards & interfaces | [`interfaces.md`](interfaces.md) |
| Audio hardware | [`smart-home-audio.md`](smart-home-audio.md) |
| HA failover & high availability | [`smart-home-failover.md`](smart-home-failover.md) |

## Related

- [Voice Pipeline](smart-home-voice.md)
- [Interface Matrix — Dashboards & Management](interfaces.md)
- [Audio System](smart-home-audio.md)
- [HA Failover & High Availability](smart-home-failover.md)
