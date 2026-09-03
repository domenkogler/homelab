---
title: Smart Home & Voice Assistant
role: index
domain: smart-home
status: active
tags: [smart-home, homeassistant]
---
# Smart Home & Voice Assistant

> **Role:** Index — the smart-home domain hub. Home Assistant, devices, voice pipeline, architecture, and links to each `smart-home-*.md` + `home-assistant-current.md` detail doc.
> **Links to:** `smart-home-voice.md`, `smart-home-audio.md`, `smart-home-failover.md`, `home-assistant-current.md`, `interfaces.md`
> **Linked from:** `index.md`

> 🟢 **IaC done, not yet live — ⏳ deploy-gated.** The HA primary (Pi, HAOS→Docker redo) + standby (oldsrv) + voice pipeline are designed but **not live**; the current live instance is the HAOS box documented in [`home-assistant-current.md`](home-assistant-current.md). Deploy tracks HD-04 (Pi redo) / Phase 4.

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
| Shelly RGBW2 | Whole house | Wi-Fi | LED strip control (4× Gen1 RGBW2 on IoT VLAN 20: kuhinja `.13`, wc `.14` 4-ch, orhideje `.15`, kopalnica `.16`) |
| Nvidia Shield | Living room | Wi-Fi | Media playback |
| Weather station (**HmIP-SWO-B**) | Outdoor | Homematic IP (868 MHz) | Temperature, humidity, wind, relative brightness, sunshine duration |
| Heat-recovery ventilator (**Zehnder ComfoAir Q**) | Utility | KNX (ComfoConnect KNX-C) | Temperatures, flow rates |
| LG air conditioners (**ThinQ**, QCA4002 Wi-Fi module) | Rooms | Wi-Fi 2.4 GHz — **cloud-to-cloud** (VLAN 21 tier) | Climate control via HA ThinQ integration (PAT) |
| Bosch appliances (**Home Connect**) | Kitchen/utility | Wi-Fi 2.4 GHz — **cloud-to-cloud** (VLAN 21 tier) | via HA `home_connect` integration (OAuth) |

---

## Cloud Appliances — LG ThinQ & Bosch Home Connect

> **Placement decision (HD-228, 2026-08-23):** cloud-dependent appliances live on **VLAN 21
> (IoT-Internet)** — the deliberate cloud exception to the otherwise local-first smart home (same
> tier as the HmIP-HAP cloud phase, HD-13). Both platforms are strictly **cloud-to-cloud**: the
> appliance keeps an outbound TLS session to the vendor cloud, and HA talks to that cloud API
> (ThinQ via PAT, Home Connect via OAuth). There is **NO local network path** to these devices —
> when the internet or vendor cloud is down they hold last state and physical controls still work.
> No WAN port-forwardings exist or are needed for either family.

### Network implications (RouterOS IaC)

- **Outbound:** VLAN 21 → WAN is allow-all by design (`network-vlans.md` matrix) — deliberately NOT
  port-tightened, because the stacks need more than HTTPS: Bosch also speaks **TCP/8080** to Home
  Connect servers; both need **UDP/123 NTP** (a drifted clock breaks TLS certificate validation and
  looks like a mysterious outage) plus working DNS. If 21 egress is ever tightened, keep at minimum
  80+443/tcp, 8080/tcp, 123/udp and resolver reachability.
- **Cross-VLAN: nothing to open.** No mDNS reflection, no multicast routing between VLANs —
  discovery/pairing runs through the vendor apps while the phone sits on the appliance SSID, and HA
  integrates purely via cloud API. mDNS reflection is explicitly REJECTED — see
  [network-rejected.md](network-rejected.md).
- **Contrast with local devices:** the Gen1 Shellys need a real cross-VLAN exception (IoT →
  `trusted-ha` udp/5683 CoAP push); these cloud appliances need ZERO rules beyond their VLAN's WAN egress.

### Migration runbook — moving an LG AC to `Kogler IOT WAN`

Pre-provisioning constraints (the QCA4002 Qualcomm Wi-Fi chip is picky):

- **2.4 GHz only** — CAPsMAN config `cfg-kogler-iot-wan` must serve a 2.4 GHz band (applies to the
  Shellys' `cfg-kogler-iot` too — Gen1 Shellys are 2.4 GHz as well).
- **Simple SSID/password charset** — no spaces/special characters; keep IoT SSID passphrases
  alphanumeric when choosing them for the CAPsMAN items.

Per unit (physical remote required; LG ACs have no local web UI or backup-WiFi path):

1. Phone joins `Kogler IOT WAN`.
2. AC powered on; hold the two buttons flanking Temperature-Down (model-dependent — often
   Energy-Saver + Jet Mode, or a key marked Wi-Fi) ~3 s until the beep; the panel Wi-Fi icon blinks
   = pairing mode.
3. LG ThinQ app → select the AC → "Change Wi-Fi Network" (or delete + re-add via +) → feed it the
   new SSID/password.
4. AC rejoins LG cloud on its own; HA picks up the move automatically — no integration change (the
   PAT is account-scoped, not network-scoped).
5. ✔ Verify: entity states refresh in HA; unit shows online in the ThinQ app.

Maintenance: the **ThinQ PAT expires/rotates** — store it in 1Password (intended item
`lg-thinq_api`, field `credential`) and treat renewal as a recurring calendar item; a dead PAT
shows up as HA entities going unavailable while the AC itself still works from the vendor app.

## Home Assistant

- **Host (node):** `pi.kogler.si` (Raspberry Pi 4, in daily use) — **primary**; accessed via the VIP `ha.kogler.si`
- **Fallback:** `home-assistant-standby` Docker container on oldsrv (systemd unit, disabled by default) — **active/standby failover, manual trigger + manual failback**
- **Configs:** In this homelab repo (moved from HA's own GitHub repo)

> **Failover design → [`smart-home-failover.md`](smart-home-failover.md).** Both nodes share a VIP (keepalived/VRRP); `ha.kogler.si` routes to the VIP so takeover needs no DNS flip or per-device reconfig. WAN loss is NOT a trigger (HA is local); failover is only for Pi failure and must work offline.
- **Entity list:** Not yet exported — needed for HA Dashboard `lovelace` + Grafana generation (enable HA Prometheus exporter: see `observability.md`)
- **Shelly integration (HA on the Pi):** the 4× Gen1 RGBW2 (`shelly-rgbw2-*`, IoT VLAN 20 — SSOT `network-addresses-generated.md`) need the **narrow new-TCP tcp/80 exception** logged in [`network-vlans.md`](network-vlans.md) (same pattern as the KNX HD-319 exception — the Pi is a node, not `trusted-admin`). The **device add itself is a HUMAN step**: HA's Shelly integration is config-flow (UI) only, added by IP (no mDNS across VLANs). Dashboard cards are authored in the lovelace views and bind once the devices are added.

### Remote access & SSO (ha.kogler.si)

- **Web UI (browser):** SSO via **Authentik** using HA's native **OpenID Connect (OIDC)** integration — family logs into Authentik (passkey), no separate HA password.
- **Companion app / Android Auto:** uses HA's **long-lived access token** (one-time pairing, authenticated through Authentik). The **`ha` route must NOT use Authentik Forward-Auth** — that would break the app's WebSocket/API and token flow.
- **Security:** at the edge keep Traefik + CrowdSec/rate-limit; in HA set `http.use_x_forwarded_for: true` + `trusted_proxies: <Traefik>`. Keep **one local `owner` account** as a recovery fallback if Authentik is unreachable.
- Config: `configuration.yaml` templated from this repo (see `deployment-ansible.md` → `home_assistant` role).

---

## Homematic IP & KNX Integration

- **Weather sensor HmIP-SWO-B** pairs over Homematic IP radio; HA integration = **`homematicip_cloud`** (current, HAP cloud mode).
- **Rekuperator ComfoAir Q 350/450** connects via **ComfoConnect KNX-C** module → KNX TP bus → **GIRA IP Router `.118`**; HA integration = **`knx`**.
- **KNX config direction (decided 2026-08-21, IMPLEMENTED 2026-09-03): ETS project file is the SSOT, rendered into HA.** The ETS export **`assets/references/knx/StanovanjeKogler_v1_0.knxproj`** is the SSOT for group addresses (192 GAs, main group 0: lights/covers/radiators/doors/appliances). The `home_assistant` role now (a) deploys the `.knxproj` to `/config/knx/` (KNX panel import for Group Monitor names + `knx.telegram` destination_name — the UI import does NOT auto-create control entities), and (b) renders **`knx-entities.yaml`** — HA `knx:` entity maps **generated from the .knxproj** by `scripts/knx-hass-gen.py` (lights/cover/switch/binary_sensor, addresses+names from ETS roles). The KNX/IP **connection** (tunneling to the GIRA IP router `knx-ip` (SSOT)) is configured in the KNX config-flow UI (current HA has no YAML connection key). Legacy `assets/references/old-ha/knx-*.yaml` = reference only; the rekuperator ComfoConnect GAs (12/1/*) are NOT in the current export and are ported as hand-curated sensors in `knx-entities.yaml`.
- **Local RF plan (deferred 2026-08-18 / HD-13 parked):** the intended HmIP-RFUSB stick + RaspberryMatic on the Pi (Debian/Docker) for full-local-ish Homematic is **held until an HmIP-RFUSB is bought**. **Meanwhile the HmIP-HAP stays in cloud mode** (`homematicip_cloud`); HA keeps talking to the HAP. When/if the RFUSB is added later, HA would switch to RaspberryMatic over **XML-RPC 2001/2010** via the legacy **`homematic`** integration (pairing stored on the stick survives a host change).
- **Failover of Homematic (cloud-HAP for now):** because HmIP-HAP is the cloud AP, its failover story is cloud-bound rather than a physical stick move — Homematic follows the cloud HAP, not the HA VIP. The stick-move step (HD-18), that applies **only** once local RF is bought, is **blocked/parked** on HD-13. IP devices (KNX, Shelly) fail over purely via the VIP as before. See [`smart-home-failover.md`](smart-home-failover.md).
- **HA recorder:** after observability is live, **trim, NOT disable, recorder history** (`purge_keep_days: 1–2`, `commit_interval` up, `exclude` noisy domains) to cut Raspberry Pi microSD writes — Grafana reads central Prometheus for long-term graphs. **Kept enabled** deliberately: it still powers the **Logbook**, **Energy Dashboard (long-term statistics)** (KNX appliance-current sensors → kWh), and `history_stats` / `history()` templates that Grafana doesn't cover. Full Pi SD-wear strategy (recorder + Docker-log driver + tmpfs `/var/log`): [`observability.md`](observability.md) → *Pi SD-card wear strategy*.

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
| Live HA instance (HAOS) + HAOS→Docker feasibility | [`home-assistant-current.md`](home-assistant-current.md) |

## Related

- [Voice Pipeline](smart-home-voice.md)
- [Interface Matrix — Dashboards & Management](interfaces.md)
- [Audio System](smart-home-audio.md)
- [HA Failover & High Availability](smart-home-failover.md)
- [Current HA Instance (HAOS) & HAOS→Docker](home-assistant-current.md)
- [Smart Home Review Queue](smart-home-review.md)
- [Smart Home Rejected / Dropped (decision log)](smart-home-rejected.md)
