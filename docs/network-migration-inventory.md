---
title: Network Migration Inventory — flat LAN → VLAN cutover (Phase 1.5)
role: reference
domain: network
status: active
tags: [network, vlan, migration]
---
# Network Migration Inventory

> **Role:** Reference — device-by-device working table for the Phase 1.5 cutover (ledger step
> "Migrate devices"). Source: **live DHCP lease dump 2026-08-23** (read-only RouterOS API via the
> management laptop). Deliberately NO current IP addresses here — flat-LAN DHCP leases are
> transient pre-cutover artifacts (kept out of repo docs by convention); the **MAC address is the
> stable reservation key**. Targets derive from the SSOTs: [`network-vlans.md`](network-vlans.md)
> (Port Type Reference, firewall matrix),
> [`network-addresses-generated.md`](network-addresses-generated.md) (address plan),
> [`smart-home.md`](smart-home.md) §Cloud Appliances (HD-228). Reservations get added to the router
> IaC during cutover prep — never hand-set on gear.

## Infrastructure & servers

| Device (hostname) | MAC (reservation key) | → VLAN | SSID | Notes |
|---|---|---|---|---|
| CRS328 switch | 74:4D:28:F0:31:9A | 99 (Mgmt) | — | static today ✓ |
| AP-dnevna (hAP ac²) | C4:AD:34:42:F0:B9 | 99 (Mgmt) | serves WLAN | ✅ **SWAP EXECUTED (spare hAP ac², C4:AD:34:42:F0:B9)** — classic hAP ac retired; hardware prerequisite for HD-232 (modern wifi-qcom-ac fleet: no MIPSBE device remains) satisfied. MAC/address SSOT updated (all.yml + switch.yml). |
| AP-garaza (wAP ac) | ~~6C:3B:6B:7D:B9:C5~~ | — | — | **☠️ DEAD 2026-08-24 — REMOVED from fleet + canvas (ether1 free).** Hardware-fault verdict after full diagnosis: PHY links (1G) and PoE fine on CRS328 `ether7`, but the board boot-loops / goes totally silent after network init (no DHCP renew, no MNDP, no ARP); RouterOS config reset + Netinstall/Etherboot attempts failed (device answered BOOTP once at 2026-08-24 00:40 then went mute; Netinstall never listed it). Switch-side PoE auto-on `current_too_low` cutoffs during its hangs were a *symptom*, not the cause. Removed from `network_static_hosts` + `switch_port_map` + rack-connections (Phase 1.5 prep). Any replacement must still be wifi-qcom-ac-capable (HD-232). |
| AP-spalnica (hAP ac²) | C4:AD:34:42:F1:7D | 99 (Mgmt) | serves WLAN | wifi-qcom-ac-capable HW — relevant again: HD-232 moves the whole fleet to the modern package |
| spare hAP ac² ("MikroTik") | C4:AD:34:42:F0:B9 | → becomes AP-dnevna | serves WLAN | consumed by the planned dnevna swap — which is now also the HD-232 modern-flavor prerequisite |
| oldsrv | 70:85:C2:2D:6F:04 | trunk 10+99 | — | SSOT Home/Mgmt addresses apply AFTER cutover |
| nas (gen8) | 1C:98:EC:0E:0D:38 | 10 (Home) | — | fresh install 2026-08-23; pools exported |
| gen8 iLO4 | 1C:98:EC:0E:0D:3A | 99 (Mgmt) | — | SSOT `ilo` address post-cutover |
| pi ("homeassistant") | E4:5F:01:26:EF:AA | trunk 10+99 | — | HA primary; Phase 4 redo pending |
| UPS PowerWalker VFI 3000 | 00:20:85:C0:92:FA | 99 (Mgmt) | — | `ups_management` list; web UI rule HD-09; NUT master talks USB-local |

## Smart-home devices

| Device | MAC (reservation key) | → VLAN | SSID | Notes |
|---|---|---|---|---|
| Shelly RGBW2 (kuhinja) | 50:02:91:B0:AD:A6 | 20 (IoT) | Kogler IOT | Gen1 — CoAP push rule HD-229 |
| Shelly RGBW2 (WC, white 4-ch) | 50:02:91:B0:B2:4E | 20 (IoT) | Kogler IOT | „ |
| Shelly RGBW2 (orhideje) | 50:02:91:B0:AF:05 | 20 (IoT) | Kogler IOT | „ |
| Shelly RGBW2 (kopalnica) | 50:02:91:B0:DE:C4 | 20 (IoT) | Kogler IOT | „ |
| Shelly DW2 flood sensor | 10:52:1C:07:8E:D5 | 20 (IoT) | Kogler IOT | Gen1 CoAP as well |
| GIRA X1 (KNX) | 00:0A:B3:29:2C:9E | 20 (IoT) | — | reachable from HA via trusted-admin→IoT |
| GIRA IP Router (KNX bus) | 00:0A:B3:27:5F:8B | 20 (IoT) | — | „ |
| LG AC klima (QCA4002) #1 | 2C:2B:F9:23:41:EC | 21 (IoT-Internet) | Kogler IOT WAN | cloud-only, HD-228 runbook |
| LG AC klima (QCA4002) #2 | 2C:2B:F9:22:BA:DD | 21 (IoT-Internet) | Kogler IOT WAN | „ |
| Bosch CSG656RB7… (Home Connect) | 68:A4:0E:2E:65:AE | 21 (IoT-Internet) | Kogler IOT WAN | make reservation (dynamic lease today) |
| Bosch SMV88TX36E (dishwasher) | 68:A4:0E:0B:E5:81 | 21 (IoT-Internet) | Kogler IOT WAN | „ |
| Bosch HNG6764B6 (oven) | 68:A4:0E:2F:46:87 | 21 (IoT-Internet) | Kogler IOT WAN | „ |

## Family & misc

| Device | MAC (reservation key) | → VLAN | SSID | Notes |
|---|---|---|---|---|
| Canon TS9550 printer ("Tiskalnik") | 74:BF:C0:CD:33:0B | 10 (Home) | — | reservation; web UI family-reachable by design (same VLAN) |
| Reolink camera (garage) | EC:71:DB:5F:BC:C1 | 20 (IoT) | — | **stay IoT(20)** — RTSP/ONVIF consumed by **Frigate on oldsrv** (trusted-admin → IoT new-connection accept already covers it); family viewing via HA/Frigate UI, no direct camera access. Frigate integration planned on oldsrv (HD-tracked); camera stays on internet-blocked IoT (privacy) |
| Family phones/tablets (Martina, Domen ×2, Valentina tablet) | various | 10 (Home) | Kogler | plain clients. Live lease (2026-08-24) confirms Valentina tablet (30:56:84:35:00:DC) + `Naprava-A54-uporabnika-Domen` (34:F0:43:73:96:35) — likely one of Domen's devices; confirm on cutover. |
| ~~"deblab" (Hyper-V VM NIC)~~ | ~~00:15:5D:01:67:1E~~ | — | — | **DISPOSED (2026-08-24, owner):** Hyper-V VM deleted; no longer on network, removed from scope. |
| ~~"truenas"~~ | ~~92:47:15:04:EB:49~~ | — | — | **DISPOSED (2026-08-24, owner):** VM no longer exists (locally-administered MAC, never owned); removed from scope. |
| NVIDIA Shield (Media) | 48:B0:2D:09:6F:90 | 50 (Media) | — | **D2-confirmed: NVIDIA Shield on Media(50)** — resolves the earlier ⚠ unknown (`switch_port_map` had it at ether20; live lease still hostname-less) |
| `0003B5F29AFDC36` → **HMIP-HAP HomeMatic AP** | 00:1A:22:1E:F7:FD | 21 (IoT-Internet) | — | **RESOLVED (task-6, live lease 2026-08-24):** this IS the eQ-3 HMIP-HAP HomeMatic Access Point — MAC matches router.yml ether9 + Rack.canvas + rack-connections.json exactly; static lease hostname = its device ID. **VLAN 21 IoT-Internet** per network-vlans Port Type Reference (cloud-bound HAP needs internet; IoT(20) would drop its WAN path). |

## Cutover-night order (derived)

1. Infra first: router baseline → switch → APs join CAPsMAN (SSIDs appear).
2. Servers onto trunk/access ports; verify management reachability from laptop (VLAN 99 native path).
3. Wired per-device ports per tables above; WiFi devices re-join their SSID (Shelly fleet via the shelly skill `wifi rotate`, LG ACs per smart-home.md §Cloud Appliances, Bosch via Home Connect app re-pair if needed).
4. Unknowns (⚠ rows) stay parked on VLAN 10 until identified. **Resolved 2026-08-24 (task 6):** `0003B5F29AFDC36` = HomeMatic HAP (→ VLAN 21), NVIDIA Shield (→ Media 50). **Disposed 2026-08-24 (owner):** `deblab` + `truenas` VMs deleted — removed from scope. No unknowns remain open.
