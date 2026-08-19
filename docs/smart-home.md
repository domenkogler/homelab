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

> ⚠️ **Planning phase — nothing deployed yet.** The HA primary (Pi, HAOS→Docker redo) + standby (oldsrv) + voice pipeline are designed but **not live**; the current live instance is the HAOS box documented in [`home-assistant-current.md`](home-assistant-current.md). Deploy tracks HD-04 (Pi redo) / Phase 4.

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
- **Entity list:** Not yet exported — needed for HA Dashboard `lovelace` + Grafana generation (enable HA Prometheus exporter: see `observability.md`)

### Remote access & SSO (ha.kogler.si)

- **Web UI (browser):** SSO via **Authentik** using HA's native **OpenID Connect (OIDC)** integration — family logs into Authentik (passkey), no separate HA password.
- **Companion app / Android Auto:** uses HA's **long-lived access token** (one-time pairing, authenticated through Authentik). The **`ha` route must NOT use Authentik Forward-Auth** — that would break the app's WebSocket/API and token flow.
- **Security:** at the edge keep Traefik + CrowdSec/rate-limit; in HA set `http.use_x_forwarded_for: true` + `trusted_proxies: <Traefik>`. Keep **one local `owner` account** as a recovery fallback if Authentik is unreachable.
- Config: `configuration.yaml` templated from this repo (see `deployment-ansible.md` → `home_assistant` role).

---

## Homematic IP & KNX Integration

- **Weather sensor HmIP-SWO-B** pairs over Homematic IP radio; HA integration = **`homematicip_cloud`** (current, HAP cloud mode).
- **Rekuperator ComfoAir Q 350/450** connects via **ComfoConnect KNX-C** module → KNX TP bus → **GIRA IP Router `.118`**; HA integration = **`knx`**.
- **Local RF plan (deferred 2026-08-18 / HD-13 parked):** the intended HmIP-RFUSB stick + RaspberryMatic on the Pi (Debian/Docker) for full-local-ish Homematic is **held until an HmIP-RFUSB is bought**. **Meanwhile the HmIP-HAP stays in cloud mode** (`homematicip_cloud`); HA keeps talking to the HAP. When/if the RFUSB is added later, HA would switch to RaspberryMatic over **XML-RPC 2001/2010** via the legacy **`homematic`** integration (pairing stored on the stick survives a host change).
- **Failover of Homematic (cloud-HAP for now):** because HmIP-HAP is the cloud AP, its failover story is cloud-bound rather than a physical stick move — Homematic follows the cloud HAP, not the HA VIP. The stick-move step (HD-18), that applies **only** once local RF is bought, is **blocked/parked** on HD-13. IP devices (KNX, Shelly) fail over purely via the VIP as before. See [`smart-home-failover.md`](smart-home-failover.md).
- **HA recorder:** after observability is live, **trim, NOT disable, recorder history** (`purge_keep_days: 1–2`, `commit_interval` up, `exclude` noisy domains) to cut Raspberry Pi microSD writes — Grafana reads central Prometheus for long-term graphs. **Kept enabled** deliberately: it still powers the **Logbook**, **Energy Dashboard (long-term statistics)** (KNX appliance-current sensors → kWh), and `history_stats` / `history()` templates that Grafana doesn't cover. Full Pi SD-wear strategy (recorder + Docker-log driver + tmpfs `/var/log`): [`observability.md`](docs/observability.md) → *Pi SD-card wear strategy*.

---

## Wake Word

- **Language: English** (wider tool support; single word)
- **Phrase: "Assistant"** (approved 2026-08-18, HD-25) — changeable later: wake words are per-device configurable in ESPHome/HA Assist, so adjusting after the family tries it is trivial (no re-architecture).
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

- Home Assistant entity list (needed for HA Dashboard **lovelace** + Grafana generation; enable HA Prometheus exporter: see `observability.md`)
- Wall-surface Dashboard: native HA Dashboard on existing devices (iPad A16 + Android RT8, 80% capped) — **TileBoard retired (HD-24)**
- Wake word final approval ("Assistant" — approved 2026-08-18, HD-25; changeable later)
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
