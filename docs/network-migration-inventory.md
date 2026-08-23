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
| AP-dnevna (hAP ac classic) | 64:D1:54:AA:24:D1 | 99 (Mgmt) | serves WLAN | **OWNER PLAN (2026-08-23): replace with the spare hAP ac²** (then set `ap-dnevna` MAC to C4:AD:34:42:F0:B9 in group_vars); classic unit retires — removes a blocker for a future new-wifi-CAPsMAN refresh |
| AP-dnevna (hAP ac classic) | 64:D1:54:AA:24:D1 | 99 (Mgmt) | serves WLAN | **OWNER PLAN (2026-08-23): replace with the spare hAP ac²** (then set `ap-dnevna` MAC to C4:AD:34:42:F0:B9 in group_vars); classic unit retires — swap is now a HARD PREREQUISITE for HD-232 (modern wifi-qcom-ac fleet: no MIPSBE device may remain) |
| AP-garaza (wAP ac) | 6C:3B:6B:7D:B9:C5 | 99 (Mgmt) | serves WLAN | **☠️ DEAD 2026-08-24 — replace.** Hardware-fault verdict after full diagnosis: PHY links (1G) and PoE fine on CRS328 `ether7`, but the board boot-loops / goes totally silent after network init (no DHCP renew, no MNDP, no ARP); RouterOS config reset + Netinstall/Etherboot attempts failed (device answered BOOTP once at 2026-08-24 00:40 then went mute; Netinstall never listed it). Switch-side PoE auto-on `current_too_low` cutoffs during its hangs were a *symptom*, not the cause. AP-garaza DHCP lease left reserved for the replacement unit (address per network-addresses-generated.md). **Replacement MUST be wifi-qcom-ac-capable (HD-232)** — variant question (D vs T) moot with this unit gone |
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
| Reolink camera (garage) | EC:71:DB:5F:BC:C1 | 20 (IoT) | — | ⚠ viewing from family devices then ONLY via trusted hosts/HA — confirm acceptable, else move to 10 |
| Family phones/tablets (Martina, Domen ×2, Valentina tablet) | various | 10 (Home) | Kogler | plain clients |
| "deblab" (Hyper-V VM NIC) | 00:15:5D:01:67:1E | ? | — | ⚠ identify — Hyper-V virtual MAC, host unknown |
| "truenas" | 92:47:15:04:EB:49 | ? | — | ⚠ identify — not in any owning doc (heritage TrueNAS box?) |
| *(no hostname)* | 48:B0:2D:09:6F:90 | ? | — | ⚠ identify |
| 0003B5F29AFDC36 | 00:1A:22:1E:F7:FD | ? | — | ⚠ identify (static lease) |

## Cutover-night order (derived)

1. Infra first: router baseline → switch → APs join CAPsMAN (SSIDs appear).
2. Servers onto trunk/access ports; verify management reachability from laptop (VLAN 99 native path).
3. Wired per-device ports per tables above; WiFi devices re-join their SSID (Shelly fleet via the shelly skill `wifi rotate`, LG ACs per smart-home.md §Cloud Appliances, Bosch via Home Connect app re-pair if needed).
4. Unknowns (⚠ rows) stay parked on VLAN 10 until identified.
