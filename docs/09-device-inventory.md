# Device Inventory — Port Map

> **Purpose:** Physical port-to-device mapping for the CRS328 and RB4011.
> Print this page, walk to the rack, and fill in the blanks.
> When complete, this feeds the CRS328 `.rsc` config.
>
> Last queried: router and switch via API. Known devices are pre-filled.

---

## CRS328-24P-4S+ — Switch

```
Ports 1–8 (left to right)
═══════════════════════════════════════════════════════════════════════════════
  1             2               3               4               5
 ┌──────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
 │ ? ? ? ?  │ │  DomenPC   │ │   P14s     │ │ HA RPi4    │ │ HMIP-HAP   │
 │ LINK UP  │ │  .134      │ │   .115     │ │  .122      │ │  .121      │
 │          │ │  deblab VM │ │            │ │            │ │            │
 │          │ │  .125      │ │            │ │            │ │            │
 │ VLAN: __ │ │  VLAN: 10  │ │  VLAN: 10  │ │  VLAN: 10  │ │  VLAN: 20  │
 └──────────┘ └────────────┘ └────────────┘ └────────────┘ └────────────┘

  6             7               8
 ┌──────────┐ ┌────────────┐ ┌────────────┐
 │          │ │            │ │            │
 │          │ │            │ │            │
 │          │ │            │ │            │
 │          │ │            │ │            │
 │ VLAN: __ │ │ VLAN: __   │ │ VLAN: __   │
 └──────────┘ └────────────┘ └────────────┘

Ports 9–16 (left to right)
═══════════════════════════════════════════════════════════════════════════════
  9             10              11              12
 ┌──────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
 │          │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │
 │ VLAN: __ │ │ VLAN: __   │ │ VLAN: __   │ │ VLAN: __   │
 └──────────┘ └────────────┘ └────────────┘ └────────────┘

  13            14              15              16
 ┌──────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
 │          │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │
 │ VLAN: __ │ │ VLAN: __   │ │ VLAN: __   │ │ VLAN: __   │
 └──────────┘ └────────────┘ └────────────┘ └────────────┘

Ports 17–24 (left to right)
═══════════════════════════════════════════════════════════════════════════════
  17            18              19              20
 ┌──────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
 │          │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │
 │ VLAN: __ │ │ VLAN: __   │ │ VLAN: __   │ │ VLAN: __   │
 └──────────┘ └────────────┘ └────────────┘ └────────────┘

  21            22              23              24
 ┌──────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
 │          │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │
 │ VLAN: __ │ │ VLAN: __   │ │ VLAN: __   │ │ VLAN: __   │
 └──────────┘ └────────────┘ └────────────┘ └────────────┘

SFP+ Ports (1–4)
═══════════════════════════════════════════════════════════════════════════════
  SFP+1                    SFP+2           SFP+3           SFP+4
 ┌──────────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
 │ Trunk → RB4011   │ │            │ │            │ │            │
 │ 10,20,30,40,     │ │            │ │            │ │            │
 │ 50,99 tagged     │ │            │ │            │ │            │
 │ ✅ CONFIRMED     │ │            │ │            │ │            │
 └──────────────────┘ └────────────┘ └────────────┘ └────────────┘
```

---

## RB4011iGS+ — Router

```
Ports 1–5 (left to right)
═══════════════════════════════════════════════════════════════════════════════
  1 (PoE in)     2               3               4               5
 ┌──────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
 │Telekom   │ │            │ │            │ │            │ │            │
 │ONT (WAN) │ │            │ │            │ │            │ │            │
 │PPPoE     │ │            │ │            │ │            │ │            │
 │✅        │ │ VLAN: __   │ │ VLAN: __   │ │ VLAN: __   │ │ VLAN: __   │
 └──────────┘ └────────────┘ └────────────┘ └────────────┘ └────────────┘

Ports 6–10 (left to right)
═══════════════════════════════════════════════════════════════════════════════
  6              7               8               9               10
 ┌──────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
 │ (down)   │ │  (down)    │ │  (down)    │ │  (down)    │ │  (down)    │
 │          │ │            │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │ │            │
 │          │ │            │ │            │ │            │ │            │
 │ VLAN: __ │ │ VLAN: __   │ │ VLAN: __   │ │ VLAN: __   │ │ VLAN: __   │
 └──────────┘ └────────────┘ └────────────┘ └────────────┘ └────────────┘

SFP+
═══════════════════════════════════════════════════════════════════════════════
  sfp-sfpplus1
 ┌──────────────────┐
 │ Trunk → CRS328   │
 │ 10,20,30,40,     │
 │ 50,99 tagged     │
 │ ✅ CONFIRMED     │
 └──────────────────┘
```

---

## Unlocated Devices (trace these)

These devices are online but their physical port could not be determined via API:

| MAC | Device | IP | Likely VLAN | Found it on port |
|-----|--------|----|-------------|-------------------|
| `64:D1:54:AA:24:D1` | **AP-dnevna** | 10.10.1.3 | VLAN 99 (Mgmt) | |
| `C4:AD:34:42:F1:7D` | **AP-spalnica** | 10.10.1.5 | VLAN 99 (Mgmt) | |
| `6C:3B:6B:7D:B9:C5` | **AP-garaza** | 10.10.1.4 (offline) | VLAN 99 (Mgmt) | |
| `74:BF:C0:CD:33:0B` | **Printer** | 10.10.1.117 | VLAN 10 (Home) | |
| `00:0A:B3:27:5F:8B` | **GIRA IP Router (KNX)** | 10.10.1.118 | VLAN 20 (IoT) | |
| `00:0A:B3:29:2C:9E` | **GIRA X1** | 10.10.1.138 | VLAN 20 (IoT) | |
| `00:20:85:C0:92:FA` | **UPS 3000** | 10.10.1.109 | VLAN 99 (Mgmt) | |
| `EC:71:DB:5F:BC:C1` | **Reolink Camera** | 10.10.1.123 | VLAN 20 (IoT) | |

> **Tip:** Look for small switches, PoE injectors, or devices daisy-chained behind APs.

---

## VLAN Quick Reference

| VLAN ID | Name | Subnet | Color (for labels) |
|---------|------|--------|--------------------|
| 1 | Blackhole (unused) | — | — |
| 10 | Home | 10.10.1.0/24 | 🟦 Blue |
| 20 | IoT | 10.10.20.0/24 | 🟨 Yellow |
| 30 | Guest | 10.10.30.0/24 | 🟥 Red |
| 40 | Kids | 10.10.40.0/24 | 🟩 Green |
| 50 | Media | 10.10.50.0/24 | 🟪 Purple |
| 99 | Management | 10.10.99.0/24 | ⬜ White |

### Port type cheat sheet

| Device type | Port config | VLAN |
|-------------|------------|------|
| Family PC, laptop, server | Access | 10 (Home) |
| Shelly, KNX, Homematic, ESP32 | Access | 20 (IoT) |
| AP (hAP ac/ac²) | Access | 99 (Mgmt) |
| Printer | Access | 10 (Home) |
| Camera | Access | 20 (IoT) |
| Shield, console, smart TV | Access | 50 (Media) |
| UPS management | Access | 99 (Mgmt) |
| Debian homelab PC | Trunk | 10,20,50 tagged + 99 native |
| SFP+ uplinks | Trunk | 10,20,30,40,50,99 tagged |