---
title: Network Migration Inventory — flat LAN → VLAN cutover (Phase 1.5)
role: reference
domain: network
status: active
tags: [network, vlan, migration]
---
# Network Migration Inventory

> **Role:** Reference — device-by-device inventory keyed by **MAC (the stable reservation key)**, built for
> the Phase 1.5 flat-LAN → VLAN cutover and kept as the human-readable companion to the IaC reservations.
> The cutover itself is **done** (VLANs live — see [network-vlans.md](network-vlans.md)).
> Source: live DHCP lease dump (read-only RouterOS API). Deliberately NO current IP addresses here —
> addresses belong to [`network-addresses-generated.md`](network-addresses-generated.md). Targets derive
> from the SSOTs: [`network-vlans.md`](network-vlans.md) (Port Type Reference, firewall matrix) and
> [`smart-home.md`](smart-home.md) §Cloud Appliances (HD-228). Reservations are always added to the router
> IaC — never hand-set on gear.

## Infrastructure & servers

| Device (hostname) | MAC (reservation key) | → VLAN | SSID | Notes |
|---|---|---|---|---|
| CRS328 switch | 74:4D:28:F0:31:9A | 99 (Mgmt) | — | static today ✓ |
| AP-dnevna (hAP ac²) | C4:AD:34:42:F0:B9 | 99 (Mgmt) | serves WLAN | The **spare hAP ac² was swapped into dnevna** and the classic hAP ac retired — the HD-232 hardware prerequisite (modern `wifi-qcom-ac` fleet, no MIPSBE device left). MAC/address SSOT in `all.yml` + `switch.yml`. |
| AP-garaza (wAP ac) | ~~6C:3B:6B:7D:B9:C5~~ | — | — | **☠️ DEAD — removed from the fleet + canvas; replacement pending.** Hardware-fault verdict after full diagnosis: PHY (1G) and PoE on CRS328 `ether7` are fine, but the board boot-loops / goes silent after network init (no DHCP renew, no MNDP, no ARP); config reset + Netinstall/Etherboot all failed. Switch-side PoE `current_too_low` cutoffs during its hangs were a symptom, not the cause. Removed from `network_static_hosts` + `switch_port_map` + rack-connections. **Any replacement must be wifi-qcom-ac-capable (HD-232).** |
| AP-spalnica (hAP ac²) | C4:AD:34:42:F1:7D | 99 (Mgmt) | serves WLAN | wifi-qcom-ac-capable hardware (HD-232 modern flavor) |
| oldsrv | 70:85:C2:2D:6F:04 | trunk 10+99 | — | SSOT Home/Mgmt addresses apply AFTER cutover |
| nas (gen8) | 1C:98:EC:0E:0D:38 | 10 (Home) | — | — |
| gen8 iLO4 | 1C:98:EC:0E:0D:3A | 99 (Mgmt) | — | SSOT `ilo` address post-cutover |
| pi ("homeassistant") | E4:5F:01:26:EF:AA | trunk 10+99 | — | HA primary |
| UPS PowerWalker VFI 3000 | 00:20:85:C0:92:FA | 20 (IoT, no WAN) | — | moved off Mgmt HD-338; `ups_management` web-UI rule removed; NUT master talks USB-local |

## Smart-home devices

| Device | MAC (reservation key) | → VLAN | SSID | Notes |
|---|---|---|---|---|
| Shelly RGBW2 (kuhinja) | 50:02:91:B0:AD:A6 | 20 (IoT) | Kogler IOT | Gen1 — CoAP push rule HD-229; static reservation (HD-312) → SSOT row `shelly-rgbw2-kuhinja` |
| Shelly RGBW2 (WC, white 4-ch) | 50:02:91:B0:B2:4E | 20 (IoT) | Kogler IOT | „ → SSOT row `shelly-rgbw2-wc` |
| Shelly RGBW2 (orhideje) | 50:02:91:B0:AF:05 | 20 (IoT) | Kogler IOT | „ → SSOT row `shelly-rgbw2-orhideje` |
| Shelly RGBW2 (kopalnica) | 50:02:91:B0:DE:C4 | 20 (IoT) | Kogler IOT | „ → SSOT row `shelly-rgbw2-kopalnica` |
| Shelly DW2 flood sensor | 10:52:1C:07:8E:D5 | 20 (IoT) | Kogler IOT | Gen1 CoAP as well |
| GIRA X1 (KNX) | 00:0A:B3:29:2C:9E | 20 (IoT) | — | reachable from HA via trusted-admin→IoT |
| GIRA IP Router (KNX bus) | 00:0A:B3:27:5F:8B | 20 (IoT) | — | „ |
| LG AC klima (QCA4002) #1 | 2C:2B:F9:23:41:EC | 20 (IOT) + `wan_allow` | Kogler IOT | cloud-only, HD-228 runbook |
| LG AC klima (QCA4002) #2 | 2C:2B:F9:22:BA:DD | 20 (IOT) + `wan_allow` | Kogler IOT | „ |
| Bosch CSG656RB7… (Home Connect) | 68:A4:0E:2E:65:AE | 20 (IOT) + `wan_allow` | Kogler IOT | reservation in the IoT pool (SSOT) |
| Bosch SMV88TX36E (dishwasher) | 68:A4:0E:0B:E5:81 | 20 (IOT) + `wan_allow` | Kogler IOT | „ |
| Bosch HNG6764B6 (oven) | 68:A4:0E:2F:46:87 | 20 (IOT) + `wan_allow` | Kogler IOT | „ |

## Family & misc

| Device | MAC (reservation key) | → VLAN | SSID | Notes |
|---|---|---|---|---|
| Canon TS9550 printer ("Tiskalnik") | 74:BF:C0:CD:33:0B | 10 (Home) | — | reservation; web UI family-reachable by design (same VLAN) |
| Reolink camera (garage) | EC:71:DB:5F:BC:C1 | 20 (IoT) | — | **stay IoT(20)** — RTSP/ONVIF consumed by **Frigate on oldsrv** (trusted-admin → IoT new-connection accept already covers it); family viewing via HA/Frigate UI, no direct camera access. Frigate integration planned on oldsrv (HD-tracked); camera stays on internet-blocked IoT (privacy) |
| Family phones/tablets (Martina, Domen ×2, Valentina tablet, **iPad**) | various | 10 (Home) | Kogler | plain clients, **static reservations** (HD-312): SSOT rows `tablet-valentina` / `phone-domen` / `phone-martina` / `tablet-ipad` on Home — the `kids-*` firewall MAC rules reference these by MAC. ⚠ `tablet-ipad` is a locally-administered (iOS "Private Wi-Fi Address") MAC: if it ever rotates, the SSOT row must follow or the kids controls stop matching. |
| NVIDIA Shield (Media) | 48:B0:2D:09:6F:90 | 50 (Media) | — | On Media(50) — `switch_port_map` has it at ether20; the live lease is hostname-less, so identify it by MAC |
| **HMIP-HAP HomeMatic AP** (lease hostname `0003B5F29AFDC36`) | 00:1A:22:1E:F7:FD | 20 (IOT) + `wan_allow` | — | eQ-3 HMIP-HAP — MAC matches router.yml `ether9` + Rack.canvas + rack-connections.json; the static lease hostname is its device ID. Cloud-bound: keeps WAN via the per-MAC accept. |

## Cutover-night order (derived)

1. Infra first: router baseline → switch → APs join CAPsMAN (SSIDs appear).
2. Servers onto trunk/access ports; verify management reachability from laptop (VLAN 99 native path).
3. Wired per-device ports per tables above; WiFi devices re-join their SSID (Shelly fleet via the shelly skill `wifi rotate`, LG ACs per smart-home.md §Cloud Appliances, Bosch via Home Connect app re-pair if needed).
4. Unknowns (⚠ rows) stay parked on VLAN 10 until identified. **No unknowns remain open** — the two former
   unidentified leases are the HomeMatic HAP and the NVIDIA Shield (rows above); the two disposed VM NICs are
   in [network-rejected.md](network-rejected.md).
