---
title: Rack Layout
role: detail
domain: network
status: active
tags: [network, rack]
---
# Rack Layout

> **Role:** Detail — 18U rack cabinet layout.
> **Links to:** `assets/Rack.canvas` (visual diagram)
> **Linked from:** `network.md`, `index.md`

---

## Rack: 19" 18U Frame

Visual layout is maintained in **[Rack.canvas](assets/Rack.canvas)** — open with Obsidian Canvas.

### Unit Assignment (bottom to top)

| U | Device |
|---|--------|
| U13 | MikroTik RB4011iGS+ Router |
| U15 | MikroTik CRS328-24P-4S+ Switch |
| U17 | Schrack 24-Port Cat.6 Patch Panel B |
| U18 | Schrack 24-Port Cat.6 Patch Panel A |

### Additional Rack-Mounted Devices

| Device | Location |
|--------|----------|
| Comtrend GRG-4260us GPON Gateway | Next to RB4011 |
| Raspberry Pi 4 B | Shelf next to RB4011 |
| eQ-3 HMIP-HAP | Shelf next to Raspberry Pi |
| PowerWalker VFI 3000 ICR IoT UPS | Rack floor / nearby · IP `10.10.1.109`, MAC `00:20:85:C0:92:FA` — see [`hardware-ups.md`](hardware-ups.md) |

---

## Patch Panel A (U18) — Room Map

| Port Range | Room |
|------------|------|
| 1–2 | garaža (garage) |
| 3–4 | predsoba rack (entryway/rack) |
| 5 | hodnik domofon (hallway/intercom) |
| 6–9 | spalnica (master bedroom) |
| 10–11 | spalnica garderoba (walk-in closet) |
| 12 | Utility |
| 13–16 | roza soba (pink room) |
| 17–21 | zelena soba (green room) |

## Patch Panel B (U17) — Room Map

| Port Range | Room |
|------------|------|
| 1–4 | kabinet (office cabinet) |
| 5–8 | kuhinja (kitchen) |
| 9–10 | dnevna klima (living room A/C) |
| 11–12 | dnevna omara (living room cabinet) |
| 13–18 | dnevna pod TV (living room, under TV) |
| 19–20 | dnevna TV (living room TV) |
| 21–22 | predsoba elektrika (entryway, electrical) |
| 23–24 | _(empty)_ |

---

## Device Images

| Device | Image |
|--------|-------|
| CRS328 | [`assets/images/CRS328.png`](assets/images/CRS328.png) |
| RB4011 | [`assets/images/RB4011.png`](assets/images/RB4011.png) |
| Comtrend GRG-4260us | [`assets/images/Comtrend-GRG-4260us.png`](assets/images/Comtrend-GRG-4260us.png) |
| HMIP-HAP | [`assets/images/HMIP-HAP.png`](assets/images/HMIP-HAP.png) |
| hAP ac | [`assets/images/hAP-ac.png`](assets/images/hAP-ac.png) |
| hAP ac² | [`assets/images/hAP-ac2.png`](assets/images/hAP-ac2.png) |
| wAP ac | [`assets/images/wAP-ac.png`](assets/images/wAP-ac.png) |

---

## Related

- **[Network Devices Canvas](assets/Network-Devices.canvas)** — Obsidian Canvas with device interconnections
- **[PowerWalker Manual](assets/manuals/PowerWalker-VFI-3000-ICR-IoT.pdf)**