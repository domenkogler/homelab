---
title: Current Home Assistant Instance — Live Inventory
role: detail
domain: smart-home
status: active
tags: [smart-home, homeassistant, haos, hacs, addons, audit, docker, failover]
---
# Current Home Assistant Instance — Live Inventory

> **Role:** Detail — live inventory of the HA instance on the Raspberry Pi 4: integrations, devices, community
> plugins, and the host surface a Debian + HA Container deployment does not provide.
> **Links to:** `smart-home.md`, `smart-home-failover.md`, `deployment-ansible.md` (`home_assistant` role), `backup.md`
> **Linked from:** `smart-home.md`, `index.md`

> **What this file is.** An inventory of the **live** HA instance, read from the running system (the REST
> API, plus the `ha` CLI + shell for what REST cannot expose: `custom_components/`, USB, host/OS facts).
> Where a section was verified against the box it says so; items still marked **to-confirm** are the residue
> the API cannot answer.
>
> **Architecture:** the primary runs on the Pi as **Debian + HA Container** with a Technitium instance
> co-located. As-built runbook: [deployment-pi-provision.md](deployment-pi-provision.md);
> design: [smart-home.md](smart-home.md), [smart-home-failover.md](smart-home-failover.md).
>
> **KNX group addresses** come from the ETS project export
> (`assets/references/knx/StanovanjeKogler_v1_0.knxproj` + HA `knx` `project_file:`,
> [smart-home.md](smart-home.md)).
>
> 🔧 **KNX wiring constraints** — both silent, both structural:
> ① **`route_back: true` is required on the KNX tunneling connection** or the DALI / ComfoConnect gateways'
> spontaneous status telegrams (InfoOnOff, InfoDimmingValue, humidity) never reach HA. The symptom is not an
> error: light *state* silently never syncs (HA believes "off", so re-sending ON looks like nothing happened)
> and ventilator humidity reads unknown.
> ② **`brightness_address` must be an absolute-dimming group object.** HA writes 0–255 to whatever is
> configured there, so pointing it at a `DimmingControl` (DPT 3.7, relative) object makes **0 mean OFF and
> the OFF command is ignored** — the generator uses `DimmingValue` (DPT 5.1) for that field.
> ③ A physically wrong reading can be a real device fault: **prove the bus value before blaming the config,
> and blame the sensor only after the config is ruled out.**

---

## 1. Executive Summary

- The instance runs on a **Raspberry Pi 4 B** as **Debian + HA Container**, rendered by the `home_assistant` role.
- **Versions** are pinned in `IaC/ansible/group_vars/all/versions.yml` — never read them from this file.
- **198 entities**, spanning KNX (blinds, lights, heat-recovery ventilator, appliance power), Homematic IP (6 room thermostats + weather station + alarm), Shelly (<lights, buttons, overpowering>), media (Nvidia Shield via Android-TV-Remote **and** Cast, Sony BRAVIA via DLNA), Companion mobile apps, and weather.
- **Community plugins:** **HACS v2.0.5** is the only entry in `custom_components/`; `motion`, `ai_task`,
  OneDrive, go2rtc and card-mod are **not present** (§7.1). The forecast source is core `meteoblue` (§6.4).
- **HACS and its custom components live inside HA Core**, not the Supervisor, so they behave identically under
  HA Container. The HAOS-only surface is the **Supervisor services + the dev add-ons** — §8 lists what replaces
  each of them.

---

## 2. Snapshot Metadata

| Field | Value |
|---|---|
| Instance URL | `https://ha.kogler.si` (via VIP/Traefik) |
| Hostname reference | `ha.kogler.si` → routes to this IP (VIP concept in `smart-home-failover.md`) |
| Install method | **Debian + HA Container** on Raspberry Pi 4 B |
| HA Core | pinned in `IaC/ansible/group_vars/all/versions.yml` — never read from this file |
| Config directory | `/config` |
| Config source | **storage** (`.storage` database) |
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
| External / internal URL | `external_url` = `https://ha.kogler.si` (see §5); no Nabu Casa / direct URL |

> Notes: UI strings are Slovenian (`location_name`, entity friendly names in `sl`). Remote access is handled by the Traefik reverse-proxy / `ha.kogler.si` (see `smart-home.md`), not by Nabu Casa.

---

## 4. Runtime & Topology Highlights

- 198 entities; major domains: **sensor 77**, **binary_sensor 39**, **light 30**, **update 9**, **cover 8**, **climate 6**, plus media_player, script, person, device_tracker, notify, todo, switch, remote, alarm_control_panel, tts, conversation, weather, sun, zone.
- **No MQTT broker, no Zigbee/Z-Wave, no ESPHome integration** is currently loaded or present as entities (see §6 — several devices in `smart-home.md` are therefore not represented in this live instance yet).
- **Single active node** — no split-brain concern.

---

## 5. Accounts & Authentication (`/auth/providers`)

> **Reachability.** `ha.kogler.si` must resolve to the **VIP from every resolver**; a name that resolves from
> one resolver and not another is a **seed/zone** problem, not a TLS or routing problem. The Pi's Technitium
> zone still needs its seed, so resolution today depends on resolver order — see the failover doc's open item.
> Pi `traefik-ha` TLS serves the synced `*.kogler.si` wildcard
> ([smart-home-failover.md](smart-home-failover.md) §Offline-safe cert).

- **One auth provider: `homeassistant`** (local user accounts — `domen` owner + a local `admin`). **Home Assistant Cloud** loaded. `external_url` = `https://ha.kogler.si`.
- **No Authentik/OIDC — by design, not a gap.** HA is **local-auth + WAN-independent**: the smart home must keep working when the VPS, Authentik and the WAN are all gone ([smart-home-failover.md](smart-home-failover.md)); `ha` is never behind Authentik Forward-Auth (decision log: [smart-home-rejected.md](smart-home-rejected.md)).
- **`mobile_app:` must be declared explicitly** in the rendered `configuration.yaml` — this instance renders
  its integration list and has **no `default_config:`**, so anything not listed simply does not exist. The tell
  is `/api/mobile_app/registrations`: **404 = integration absent, 401 = present and asking for a token**.
- **Never drop `type: homeassistant` from `auth_providers`.** With only an external/`trusted_networks` provider,
  HA shows *"Enable mobile clients"* for any client from an untrusted network and the Companion app loses its
  login entirely.
- One `owner` account (`domen`) plus a local `admin`, as designed in `smart-home-failover.md`.

> **Host-move relevance:** local user accounts and long-lived tokens live in `.storage`, so they move with the
> config directory — no auth rebuild is needed.

---

## 6. Integrations & Devices (as observed live)

> Integration → physical device mapping. `source:` attributes are KNX group addresses (confirmed custom-style attribute added by the KNX integration).

### 6.1 Cable / bus / IP device control
| Integration (domain) | Devices / entities observed | Notes |
|---|---|---|
| **KNX** (`knx`) | **8 blinds** (cover, device_class `blind`: Dnevna soba, Hodnik, Kabinet, Kopalnica, Kuhinja, Soba roza, Soba zelena, Spalnica) · many **lights** · **rekuperator/ComfoAir Q** (airflow, supply/extract/room/outdoor temp+humidity, filter) · **appliance current** (pečica mala/velika=oven, pomivalni stroj=dishwasher, pralni stroj=washer, sušilni stroj=dryer — group addr `1.1.7`, mA) · KNX interface status sensors (telegrams, connection, individual address) · external/internal security zones | Home's field bus. GIRA IP router; ComfoAir Q via ComfoConnect KNX-C per `smart-home.md` |
| **Homematic IP** (`homematicip_cloud`) | **6 thermostats** (Dnevna soba, Kopalnica, Roza soba, Spalnica, WC, Zelena soba) + temp/humidity/abs-humidity · **weather station HmIP-SWO-B** (temp, humidity, illuminance, windspeed, storm, sunshine) · alarm control panel + battery sensors | **Cloud mode** (HmIP-HAP on internet VLAN) — there is no local-RF path (decision log: [smart-home-rejected.md](smart-home-rejected.md)) |
| **Shelly** (`shelly`) | **LED/light strips** (LED kuhinja, Kopalnica LED, orhideje, soba postelje/omare, WC-4 ch1–4, Utility…) · **buttons** (Tipka) · **overpowering** binary sensors · **reboot buttons** (Ponovno zaženi) · light values | Native Shelly integration (direct LAN HTTP/WebSocket, **no MQTT**). RGBW2 controllers/buttons across rooms. The 4× Gen1 RGBW2 (`shelly-rgbw2-*`, IoT VLAN 20, `auth:false`) are added **by IP in the HA UI** (config flow only — no mDNS across VLANs) and need the narrow Home→IoT new-TCP tcp/80 exception (the Pi node is not in `trusted-admin`); dashboard strips live in `lovelace-stanovanje` |

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

### 6.4 Weather (1 provider)
| Integration | Entity | Notes |
|---|---|---|
| **meteoblue** (core) | `weather.meteoblue_kogler_si_maribor` | **Single authoritative source** (Maribor, `{{ home_latitude }}/{{ home_longitude }}`). Key = `meteoblue_api` (1Password Homelab-ansible). Hourly + 7-day forecast; Slovenia is modeled well. Configured in `configuration.yaml.j2` (IaC). |

### 6.5 Host-level surface
`supervisor` (`hassio`), the HAOS **backup** manager and the Raspberry Pi integrations (`rpi_power`,
`raspberry_pi`) are **not part of HA Container**: Pi health (undervoltage, EEPROM) and backups are host-level
concerns (§8, [`backup.md`](backup.md)).

### 6.6 Presence of *missing* integrations (important for device claims)
> Confirmed **absent** from loaded components: `esphome`, `mqtt`, `zwave_js`, `zha/zigbee`, `oidc`/`openid_connect`. Consequently:
- The **Guition kitchen ESP32-S3** and any ESPHome node from `smart-home.md` are **not currently an active integration** on this instance.
- **No MQTT broker** is used by anything live (Shelly are native, KNX is direct): matches the failover doc's "no broker" design.

---

## 7. Community Plugins (as observed)

### 7.1 HACS & custom components
> HACS itself is installed and reports **v2.0.5**. Custom components load inside HA Core, so they behave identically in HA Container.

| Plugin | Type | Installed | Latest (reported) | Purpose | Docker-portable? |
|---|---|---|---|---|---|
| **HACS** | Integration (core) | 2.0.5 | 2.0.5 | Community add-on store / install manager | ✅ Yes |
| **OneDrive Backup** (`onedrive`) | HACS integration | *(api)* | — | Cloud backup to Microsoft OneDrive (used space/free space/drive state sensors) | ✅ Yes |
| **go2rtc** (`go2rtc`) | HACS integration | *(api)* | — | Camera/RTSP streaming (camera/ffmpeg/stream/web_rtc loaded; **no live camera entities yet**) | ✅ Yes |
| **card-mod** (`card_mod`) | HACS frontend card | v3.4.4 | v4.2.1 (skipped) | Custom Lovelace card CSS/modification (frontend resource — lives under `www/`, not `custom_components/`) | ✅ Yes |

> **Verified on disk:** `/config/custom_components/` contains **exactly one directory: `hacs`**. The
> components a REST pass had attributed to HACS/custom (OneDrive, go2rtc, card-mod, `motion`, `ai_task`) are
> **not** there — frontend resources such as card-mod load from `www/`, and `ai_task` is a core integration,
> not a custom component. So there is nothing to port except HACS itself (+ any `www/` frontend resources);
> adding OneDrive or go2rtc is a fresh-deploy decision, not a migration step.

### 7.2 No Supervisor surface
The dev-tool add-ons an HAOS host would carry — `a0d7b954_ssh` (Advanced SSH & Web Terminal),
`core_configurator` (File editor), `a0d7b954_vscode` (Studio Code Server) — do not exist under HA Container;
their equivalents are containers (`lscr.io/linuxserver/code-server`, an SSHD container) or host tools. No
MQTT (Mosquitto), Zigbee2MQTT or media add-ons are in the design. No camera entities are live; go2rtc would be
a plain custom component if cameras are ever added.

**Host facts:** `lsusb` = **hub only, zero user USB devices** (no ESP32-S3 serial device, no RF stick — the
Homematic HAP is a cloud device); NIC = `end0` (+ `wlan0`).

---

## 8. What the Container host does not provide

HACS and any custom component install into `custom_components/` inside the HA Core config, independent of the
Supervisor, so they behave identically here. The HAOS-only surface and what replaces it:

| Capability | Debian + HA Container (this host) |
|---|---|
| Add-ons: SSH & Web Terminal, File editor, Studio Code Server | separate containers (`lscr.io/linuxserver/code-server`, an SSHD container) or host tools |
| Add-on store ecosystem (community repos) | none — there is no Supervisor |
| Supervisor auto-backup / add-on lifecycle / watchdog | host backup per [`backup.md`](backup.md) + Docker restart policies |
| OS / firmware (RPi EEPROM) updates | host `apt` / `rpi-eeprom-update`, outside HA |
| RPi undervoltage + hardware integration | `rpi_power` / `raspberry_pi` are not part of HA Container — detect at the OS level |
| VRRP / keepalived for the failover VIP | ✅ native on the host — the enabler for `smart-home-failover.md` |
| Config + auth + entity parity with the standby | one Ansible `home_assistant` role renders both nodes (see `deployment-ansible.md`) |

---

## 9. Open Questions / Data Gaps (to-confirm)

- [ ] Confirm **ESPHome**: `smart-home.md` references a Guition ESP32-S3 kitchen device, but the `esphome` integration is **not loaded** on this instance and `lsusb` shows no USB serial device — is it online/paired elsewhere or not yet added?

---

## 10. Related

- [Smart Home](smart-home.md)
- [HA Failover & High Availability](smart-home-failover.md) (VIP/VRRP, standby on oldsrv — the reason Docker matters here)
- [Home Assistant Voice Pipeline](smart-home-voice.md)
- [Ansible Specification — `home_assistant` role](deployment-ansible.md)
- [Service Catalog](services.md)
- [Backup & DR](backup.md)
