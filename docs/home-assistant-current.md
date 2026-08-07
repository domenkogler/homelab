---
title: Current Home Assistant Instance — Live Inventory & HAOS→Docker Feasibility
role: detail
domain: smart-home
status: active
tags: [smart-home, homeassistant, haos, hacs, addons, audit, docker, failover]
---
# Current Home Assistant Instance — Live Inventory & HAOS→Docker Feasibility

> **Role:** Detail — point-in-time snapshot of the live HA instance on the Raspberry Pi 4 (HAOS), all integrations/devices, community plugins (HACS + add-ons), and their impact when evaluating a future **VM with HAOS vs HA in Docker** deployment.
> **Links to:** `smart-home.md`, `smart-home-failover.md`, `deployment-ansible.md` (`home_assistant` role), `backup.md`
> **Linked from:** `index.md`

> ⚠️ **How this was collected (planning phase — read-only, nothing changed).** Enumerated live on **2026-08-07** via the HA REST API (`http://10.10.1.122:8123`) authenticated with the `domen` owner account login flow. No files on the HA host were modified; no config was read from the (separate) HA config git repo. Items that the REST API cannot expose (full Supervisor add-on store, exact HACS repository list, some integration attribution) are marked **to-confirm** below.

> 🧭 **Planned changes (post-audit, decision taken — see `smart-home.md`, `smart-home-failover.md`, `network-dns.md`).**
> 1. **Primary redo:** Pi moves from HAOS → **Debian + HA Container** during the network redo (keeps the failover VIP/VRRP and one Ansible role for both nodes).
> 2. **Homematic IP:** HAP **cloud mode** is replaced by a local **HmIP-RFUSB + RaspberryMatic** on the Pi (`homematic` XML-RPC 2001/2010); failover = physically moving the stick to oldsrv (pairing stored on the stick).
> 3. **Technitium secondary DNS** moves from nas → the Pi (now a Debian host).
> 4. **Dev add-ons** (SSH / File editor / Studio Code Server) + Supervisor-only services are replaced by standalone containers or host tools in the Docker deployment; HAOS-only auto-backup replaced per `backup.md`.
> This file remains a point-in-time inventory of the *current* live instance; the bullets above are the approved direction, not yet applied.

---

## 1. Executive Summary

- The live instance is a **Raspberry Pi 4 B running Home Assistant OS (HAOS)** — confirmed by the `hassio` (Supervisor) component, the HAOS/OS/Supervisor update entities, and Raspberry Pi–specific integrations.
- **Component versions:** HA **Core 2026.7.4** · HA **OS 18.2** · **Supervisor 2026.07.5** · RPi4 firmware 2026-01-09.
- **198 entities**, spanning KNX (blinds, lights, heat-recovery ventilator, appliance power), Homematic IP (6 room thermostats + weather station + alarm), Shelly (<lights, buttons, overpowering>), media (Nvidia Shield via Android-TV-Remote **and** Cast, Sony BRAVIA via DLNA), Companion mobile apps, and weather.
- **Community/HACS plugins confirmed:** **HACS v2.0.5**, **OneDrive Backup** (cloud backup), **go2rtc** (camera streaming), and **card-mod v3.4.4** (frontend). Likely-custom but **to-confirm:** `motion`, `ai_task`, and a Slovenian "Weather 2000" forecast source.
- **HAOS add-ons (Supervisor, all official):** `Advanced SSH & Web Terminal`, `File editor`, `Studio Code Server`. These are the **only** Supervisor add-ons currently detected.
- **Feasibility verdict (Docker):** **High** — every functional integration (KNX, Homematic IP, Shelly, media, Companion, weather, HACS, OneDrive, go2rtc) runs under **HA Container**, because HACS and its custom components live inside HA Core, not the Supervisor. The only things lost moving to Docker are the **dev-tool add-ons** (SSH/File editor/VS Code) and **Supervisor OS-level services** (OS/firmware updates, watchdog, add-on lifecycle) — all replaceable as standalone containers or host tools. Details in §8.

---

## 2. Snapshot Metadata

| Field | Value |
|---|---|
| Instance URL | `http://10.10.1.122:8123` (Home VLAN) |
| Hostname reference | `ha.kogler.si` → routes to this IP (VIP concept in `smart-home-failover.md`) |
| Install method | **HA OS (HAOS)** on Raspberry Pi 4 B — Supervisor present |
| HA Core | **2026.7.4** (latest available 2026.8.0) |
| HA OS | **18.2** |
| Supervisor | **2026.07.5** |
| RPi4 EEPROM/firmware | 2026-01-09 |
| Config directory | `/config` |
| Config source | **storage** (`.storage` database) — expected for default_config HAOS install |
| Data collection method | REST API + owner login token; entities 198 |
| Auth provider | `homeassistant` local only (see §5) |

---

## 3. Localisation & Home

| Setting | Value |
|---|---|
| Location name | Belačeva ulica 5 (home zone) |
| Country / currency | SI / EUR |
| Language | `sl` (Slovenian) |
| Time zone | Europe/Belgrade |
| Latitude / Longitude | 46.5596 / 15.6355 |
| Elevation | 275 m |
| Unit system | km, mm, m², g, Pa, °C, L, m/s (metric) |
| External/internal URL | **null** (no Nabu Casa / direct URL set) |

> Notes: UI strings are Slovenian (`location_name`, entity friendly names in `sl`). `external_url`/`internal_url` are **null** — remote access is expected to be handled by Traefik reverse-proxy / `ha.kogler.si` (see `smart-home.md`), not by an HA-configured URL.

---

## 4. Runtime & Topology Highlights

- 198 entities; major domains: **sensor 77**, **binary_sensor 39**, **light 30**, **update 9**, **cover 8**, **climate 6**, plus media_player, script, person, device_tracker, notify, todo, switch, remote, alarm_control_panel, tts, conversation, weather, sun, zone.
- **No MQTT broker, no Zigbee/Z-Wave, no ESPHome integration** is currently loaded or present as entities (see §6 — several devices in `smart-home.md` are therefore not represented in this live instance yet).
- **No split-brain concern today:** single active node.

---

## 5. Accounts & Authentication (`/auth/providers`)

- **Only one auth provider:** `homeassistant` (local user accounts). **Home Assistant Cloud is loaded** (`cloud` in components) but no external URL set.
- **No Authentik/OIDC connected live** — `oidc` / `openid_connect` are **absent** from loaded components. This contradicts the *planned* SSO via Authentik in `smart-home.md`/`smart-home-failover.md`; that flow is **future**, not currently active on this instance.
- One `owner` account (`domen`) used for this audit. A local recovery owner account is retained as designed in `smart-home-failover.md`.

> **Migration relevance:** In a Docker/VM-HAOS move, local user accounts and long-lived-tokens are stored in `.storage` and move with the config — no rebuild of auth needed as long as the config directory is preserved.

---

## 6. Integrations & Devices (as observed live)

> Integration → physical device mapping. `source:` attributes are KNX group addresses (confirmed custom-style attribute added by the KNX integration).

### 6.1 Cable / bus / IP device control
| Integration (domain) | Devices / entities observed | Notes |
|---|---|---|
| **KNX** (`knx`) | **8 blinds** (cover, device_class `blind`: Dnevna soba, Hodnik, Kabinet, Kopalnica, Kuhinja, Soba roza, Soba zelena, Spalnica) · many **lights** · **rekuperator/ComfoAir Q** (airflow, supply/extract/room/outdoor temp+humidity, filter) · **appliance current** (pečica mala/velika=oven, pomivalni stroj=dishwasher, pralni stroj=washer, sušilni stroj=dryer — group addr `1.1.7`, mA) · KNX interface status sensors (telegrams, connection, individual address) · external/internal security zones | Home's field bus. GIRA IP router; ComfoAir Q via ComfoConnect KNX-C per `smart-home.md` |
| **Homematic IP** (`homematicip_cloud`) | **6 thermostats** (Dnevna soba, Kopalnica, Roza soba, Spalnica, WC, Zelena soba) + temp/humidity/abs-humidity · **weather station HmIP-SWO-B** (temp, humidity, illuminance, windspeed, storm, sunshine) · alarm control panel + battery sensors | **Cloud mode** (HAP on internet VLAN) per `smart-home.md` phase-1/2 roadmap; target is local CCU3/RaspberryMatic |
| **Shelly** (`shelly`) | **LED/light strips** (LED kuhinja, Kopalnica LED, orhideje, soba postelje/omare, WC-4 ch1–4, Utility…) · **buttons** (Tipka) · **overpowering** binary sensors · **reboot buttons** (Ponovno zaženi) · light values | Native Shelly integration (direct LAN HTTP/WebSocket, **no MQTT**). RGBW2 controllers/buttons across rooms |
| **Modbus** (`modbus`) | **UPS** sensors: battery capacity, input voltage, output load (scaled raw values, e.g. capacity 20041→~20%, input 2055→~20.5 V) | Source is the **PowerWalker VFI ICT/ICR IoT 3000** on `10.10.1.109:502` (unit 1) — see [`hardware-ups.md`](hardware-ups.md). Exact register map **to-confirm** |

### 6.2 Media
| Integration | Devices / entities | Notes |
|---|---|---|
| **Android TV Remote** (`androidtv_remote`) | `media_player.shield` + `remote.shield` (Nvidia Shield) | App-pairing based remote |
| **Google Cast** (`cast`) | `media_player.shield_2` (tv class — Shield as Cast target) | Shield exposes both; 2 entries expected |
| **DLNA DMR** (`dlna_dmr`) | `media_player.bravia_kdl_46ex520` (Sony BRAVIA TV, currently unavailable) | |
| **Google Translate TTS** (`google_translate`) | `tts.google_translate_en_com` | Voice/audio playback backend |

### 6.3 Presence / mobile
| Integration | Devices / entities | Notes |
|---|---|---|
| **Mobile App (Companion)** (`mobile_app`) | `SM-A546B` (Galaxy A54), `SM-A556B` (Galaxy A56): device_tracker, notify, battery level/state, charger type | 2 phones registered via HA Companion |

### 6.4 Weather (2 providers)
| Integration | Entity | Notes |
|---|---|---|
| **met** (Meteorologisk institutt) | `weather.forecast_dom` (Forecast Belačeva ulica 5) | Official core weather |
| **Weather 2000 / Slovenian** (custom?) | `weather.weather_2000_slovenija` | Non-core added source; likely a HACS/third-party Slovenian feed (**to-confirm** — not attributable via REST attributes; no matching domain in component list) |

### 6.5 System / HAOS-level
| Integration | Observed | Notes |
|---|---|---|
| **Supervisor (HAOS)** (`hassio`) | update/sensor/switch/binary_sensor entities | Confirms HAOS; add-on update entities in §7 |
| **RPi Power** (`rpi_power`) | `binary_sensor.rpi_power_status` (undervoltage detection) | Pi PSU health |
| **Raspberry Pi** (`raspberry_pi`, `homeassistant_hardware`) | RPi4 firmware update entity | Hardware platform |
| **Backup** (`backup`) | automatic backup manager + last/next scheduled backup sensors | HAOS automatic backups |

### 6.6 Presence of *missing* integrations (important for Docker/device claims)
> Confirmed **absent** from loaded components: `esphome`, `mqtt`, `zwave_js`, `zha/zigbee`, `oidc`/`openid_connect`. Consequently:
- The **Guition kitchen ESP32-S3** and any ESPHome node from `smart-home.md` are **not currently an active integration** on this instance.
- **No MQTT broker** is used by anything live (Shelly are native, KNX is direct): matches the failover doc's "no broker" design.
- **Authentik SSO not yet wired** into HA live (see §5).

---

## 7. Community Plugins (as observed)

### 7.1 HACS & custom components
> HACS itself is installed and reports **v2.0.5**. Custom components load inside HA Core, so they behave identically in HA Container.

| Plugin | Type | Installed | Latest (reported) | Purpose | Docker-portable? |
|---|---|---|---|---|---|
| **HACS** | Integration (core) | 2.0.5 | 2.0.5 | Community add-on store / install manager | ✅ Yes |
| **OneDrive Backup** (`onedrive`) | HACS integration | *(api)* | — | Cloud backup to Microsoft OneDrive (used space/free space/drive state sensors) | ✅ Yes |
| **go2rtc** (`go2rtc`) | HACS integration | *(api)* | — | Camera/RTSP streaming (camera/ffmpeg/stream/web_rtc loaded; **no live camera entities yet**) | ✅ Yes |
| **card-mod** (`card_mod`) | HACS frontend card | v3.4.4 | v4.2.1 (skipped) | Custom Lovelace card CSS/modification | ✅ Yes |
| **motion** (`motion`) | HACS?(custom) | *(api)* | — | Motion-detection component (no motion entities live yet) | **To-confirm** |
| **ai_task** (`ai_task`) | custom / 2026-builtin? | *(api)* | — | AI/LLM task component | **To-confirm** |
| **Weather 2000 (SI)** | HACS?(custom) | *(api)* | — | Slovenian forecast (`weather.weather_2000_slovenija`) | **To-confirm** |

> Exact installed versions of OneDrive, go2rtc, motion, ai_task, Weather-2000 are not exposed via the REST API — confirm by reading HACS `.storage/hacs.data` + `custom_components/` from the config git repo or via SSH (Advanced SSH add-on) + admin Supervisor access.

### 7.2 HAOS add-ons (Supervisor) — currently installed
> These are **all official** HA add-ons (dev/management tooling). Identified via their `update` entities + add-on slugs. Accessing the full add-on store/`/api/hassio/*` returns **401 (non-admin token)** — the complete list should be re-checked with admin rights or SSH.

| Add-on | Slug | Version | Category | Docker replacement |
|---|---|---|---|---|
| **Advanced SSH & Web Terminal** | `a0d7b954_ssh` | 24.0.1 | official (dev/ops) | Standalone SSH server / use host SSH |
| **File editor** | *(official)* | 6.1.0 | official (dev/ops) | VS Code / code-server container, or `config` editor add-on replacement |
| **Studio Code Server** | *(official)* | 6.0.1 | official (dev/ops) | `lscr.io/linuxserver/code-server` container |
| *(HA Core / OS / Supervisor updates)* | — | Core 2026.7.4 · OS 18.2 · Sup 2026.07.5 | platform | n/a in Docker (host-managed) |

> No **community** add-on store repositories are detected among installed add-ons. No MQTT (Mosquitto), Zigbee2MQTT, or media add-ons are installed.

### 7.3 HAOS/OS-level services (not add-ons)
- Supervisor watchdog, OS + Supervisor + `raspberry_pi` EEPROM updates, automatic **backup** (HAOS backup manager), RPi power monitoring, hardware detection (`homeassistant_hardware`). These are **HAOS-only** and do not exist in HA Container.

---

## 8. Impact Assessment: VM+HAOS vs HA in Docker (community-plugin lens)

**Bottom line: HACS + all custom components (OneDrive, go2rtc, card-mod, and likely motion/ai_task/Weather-2000) are fully compatible with HA Container.** HACS installs into `custom_components/` inside the HA Core config, independent of the Supervisor. The genuine HAOS-only surface is limited to **Supervisor services + the 3 dev add-ons**.

| Capability | VM + HAOS (target) | HA in Docker (Pi or VM) |
|---|---|---|
| HACS + OneDrive + go2rtc + card-mod | ✅ native | ✅ native (same `custom_components/`) |
| Motion / AI-task / Weather-2000 custom comps | ✅ native | ✅ native (same mechanism) |
| **Add-ons**: SSH, File editor, Studio Code Server | ✅ Supervisor add-ons | ❌ not available → run separate containers (`linuxserver/code-server`, SSHD) or host tools |
| Add-on store ecosystem (community repos) | ✅ | ❌ (no Supervisor add-on store in Container) |
| Supervisor auto-backup / add-on lifecycle / watchdog | ✅ built-in | ❌ → use host backup (e.g. `backup.md` / Kopia) + Docker restart policies |
| OS / firmware (RPi EEPROM) updates | ✅ HAOS-managed | ❌ → host apt/`rpi-eeprom-update` outside HA |
| RPi undervoltage + hardware integration | ✅ | ⚠️ partially — `rpi_power` and `raspberry_pi` are not part of HA Container; use OS-level detection on the host |
| VRRP/keepalived for VIP failover | ⚠️ **not feasible on Pi-HAOS**; feasible on VM-HAOS if VM host VLANs allow (still has Supervisor constraints) | ✅ native on host (enabler for the failover design in `smart-home-failover.md`) |
| Config + auth + entities parity | same `.storage`+`configuration.yaml` | same — one Ansible `home_assistant` role renders both (see `deployment-ansible.md`) |

### 8.1 Practical migration notes
- **No functional integration is lost** going to Docker; only dev/ops tooling (3 add-ons) and HAOS OS-level services change form. Recreate tooling as containers: `code-server`, an SSH jump container, and a host cron/systemd backup.
- **OneDrive Backup** (HACS) keeps working in Docker (it's a Core integration calling the Microsoft Graph API) — no Supervisor dependency.
- **go2rtc / cameras:** no camera entities are live today; once added, they remain a plain custom component in either deployment.
- **HAOS backup** (Supervisor) is the one backup path that disappears; ensure an equivalent (the repo's `backup.md` / Kopia / host snapshots) covers `/config` in a Docker deployment.
- **Superset of constraints:** if the chosen direction is **VM + HAOS** (rather than Pi-HAOS), most Supervisor benefits return, but VRRP for the failover VIP is still cleaner on a plain Docker/host deployment (as documented in `smart-home-failover.md`).

---

## 9. Open Questions / Data Gaps (to-confirm before finalising plans)

- [ ] Confirm exact installed versions + full repository list of **HACS** custom components (`motion`, `ai_task`, Weather-2000, OneDrive, go2rtc) via SSH (`Advanced SSH & Web Terminal`) or the config git repo (`custom_components/`, `.storage/hacs.data`).
- [ ] Confirm the **full Supervisor add-on list** with an **admin** token (`/api/hassio/addons` returned 401 for the owner `domen` token used here) — ensures no community add-on store is in use.
- [x] Confirm **Modbus UPS** device/register details — device is the **PowerWalker VFI ICT/ICR IoT 3000** on `10.10.1.109:502` (unit 1); *register map* still to-confirm (see [`hardware-ups.md`](hardware-ups.md)).
- [ ] Confirm **ESPHome**: `smart-home.md` references a Guition ESP32-S3 kitchen device, but the `esphome` integration is **not loaded** on this instance — is it online/paired elsewhere or not yet added?
- [ ] Confirm the **"Weather 2000, Slovenija"** source — third-party/HACS vs core, and whether it should be retained or replaced.
- [ ] Whether the planned **Authentik/OIDC** SSO is meant to be introduced during the redo (currently not connected).

---

## 10. Related

- [Smart Home](smart-home.md)
- [HA Failover & High Availability](smart-home-failover.md) (VIP/VRRP, standby on oldsrv — the reason Docker matters here)
- [Home Assistant Voice Pipeline](smart-home-voice.md)
- [Ansible Specification — `home_assistant` role](deployment-ansible.md)
- [Service Catalog](services.md)
- [Backup & DR](backup.md)
