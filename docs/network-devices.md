> **⚠️ WORK IN PROGRESS — port map not verified. Do not rely on specific port/VLAN/MAC assignments; a physical wiring audit is pending.**
>
> Known inconsistencies to resolve during the audit:
> - Garage AP: identified as **hAP ac** on RB4011 vs **wAP ac** at Patch Panel A /1/2 → actual is **wAP ac**.
> - HA Raspberry Pi (RPi 4) and HMIP-HAP are currently connected **directly to the router**, on the **flat network (no VLANs)** — the RB4011/switch rows below are draft.

# Device Inventory — Port Map

> **Role:** Detail — physical port-to-device mapping for CRS328 and RB4011.
> **Links to:** `network-vlans.md`, `assets/Rack.canvas`
> **Linked from:** `network.md`, `index.md`

---

## RB4011iGS+ — Router

| Port | Connection | VLAN | Notes |
|------|-----------|------|-------|
| ether1 | Comtrend ONT (WAN) | — | PPPoE, Telekom Slovenije |
| ether2 | hAP ac (AP-garaza) | 99 | 6C:3B:6B:7D:B9:C5 |
| ether3 | hAP ac² (AP-spalnica) | 99 | C4:AD:34:42:F1:7D |
| ether4 | hAP ac (AP-dnevna) | 99 | 64:D1:54:AA:24:D1 |
| ether5 | eQ-3 HMIP-HAP | 21 | 00:1A:22:1E:F7:FD |
| ether6 | Raspberry Pi 4 B (HA) | 99 | E4:5F:01:26:EF:AA |
| ether7–10 | _(down)_ | — | — |
| sfp-sfpplus1 | Trunk → CRS328 | Tagged: 10,20,30,40,50,99 | 74:4D:28:F0:31:B2 |

---

## CRS328-24P-4S+ — Switch

### Ports 1–8

| Port | Device | IP | VLAN | MAC |
|------|--------|-----|------|-----|
| 1 | _(occupied, link up)_ | — | — | — |
| 2 | oldsrv | .134 | 10 | — |
| 3 | ThinkPad P14s | .115 | 10 | — |
| 4 | HA Raspberry Pi 4 | .122 | 10 | — |
| 5 | HMIP-HAP (Homematic) | .121 | 21 | — |
| 6–8 | _(empty)_ | — | — | — |

### Ports 9–16

| Port | Device | IP | VLAN | MAC |
|------|--------|-----|------|-----|
| 9 | dnevna klima | — | — | — |
| 10 | dnevna klima | — | — | — |
| 11 | dnevna omara | — | — | — |
| 12 | AP-dnevna (hAP ac) | 10.10.1.3 | 99 | 64:D1:54:AA:24:D1 |
| 13 | dnevna pod TV | — | 50 | — |
| 14 | Nintendo Switch 2 | — | 50 | E0:EF:BF:74:CE:07 |
| 15 | dnevna pod TV | — | — | — |
| 16 | dnevna pod TV | — | — | — |

### Ports 17–24

| Port | Device | IP | VLAN | MAC |
|------|--------|-----|------|-----|
| 17 | dnevna pod TV | — | 50 | — |
| 18 | Nvidia Shield TV Pro | — | 50 | 48:B0:2D:09:6F:90 |
| 19 | dnevna TV | — | — | — |
| 20 | dnevna TV | — | — | — |
| 21 | predsoba elektrika — Gira X1 | 10.10.1.138 | 20 | 00:0A:B3:29:2C:9E |
| 22 | predsoba elektrika — Gira IP Router | 10.10.1.118 | 20 | 00:0A:B3:27:5F:8B |
| 23–24 | _(empty)_ | — | — | — |

### SFP+ Ports

| Port | Connection | VLANs |
|------|-----------|-------|
| SFP+1 | Trunk → RB4011 | Tagged: 10,20,30,40,50,99 |
| SFP+2–4 | _(empty)_ | — |

---

## Patch Panel A (U18) — Ports 1–8

| Port | Location | Device |
|------|----------|--------|
| 1 | garaža | Reolink RLC-420-5MP camera (EC:71:DB:5F:BC:C1) |
| 2 | garaža | AP-garaza (wAP ac, 6C:3B:6B:7D:B9:C5) |
| 3 | predsoba rack | PowerWalker VFI 3000 ICR IoT UPS (00:20:85:C0:92:FA) |
| 4 | predsoba rack | — |
| 5 | hodnik domofon | — |
| 6 | spalnica postelja | — |
| 7 | spalnica postelja | — |
| 8 | spalnica TV | — |

## Patch Panel A (U18) — Ports 9–16

| Port | Location | Device |
|------|----------|--------|
| 9 | spalnica TV | — |
| 10 | spalnica garderoba | AP-spalnica (hAP ac², C4:AD:34:42:F1:7D) |
| 11 | spalnica garderoba | — |
| 12 | Utility | — |
| 13 | roza postelja | — |
| 14 | roza postelja | — |
| 15 | roza miza | — |
| 16 | roza miza | — |

## Patch Panel A (U18) — Ports 17–24

| Port | Location | Device |
|------|----------|--------|
| 17 | zelena postelja | — |
| 18 | zelena postelja | — |
| 19 | zelena miza | — |
| 20 | zelena miza | — |
| 21 | talno gretje | — |
| 22–24 | _(empty)_ | — |

---

## Patch Panel B (U17) — Ports 1–8

| Port | Location | Device |
|------|----------|--------|
| 1 | kabinet desno | — |
| 2 | kabinet desno | — |
| 3 | kabinet levo | Canon TS9550 printer (74:BF:C0:CD:33:0B) |
| 4 | kabinet levo | — |
| 5 | kuhinja omara | — |
| 6 | kuhinja omara | — |
| 7 | kabinet miza | Family PC |
| 8 | kabinet miza | Docking laptop |

---

## Unlocated Devices

Devices online but physical port not confirmed:

| MAC | Device | IP | Likely VLAN |
|-----|--------|----|-------------|
| `64:D1:54:AA:24:D1` | AP-dnevna | 10.10.1.3 | 99 |
| `C4:AD:34:42:F1:7D` | AP-spalnica | 10.10.1.5 | 99 |
| `6C:3B:6B:7D:B9:C5` | AP-garaza | 10.10.1.4 (offline) | 99 |
| `74:BF:C0:CD:33:0B` | Printer | 10.10.1.117 | 10 |
| `00:0A:B3:27:5F:8B` | GIRA IP Router (KNX) | 10.10.1.118 | 20 |
| `00:0A:B3:29:2C:9E` | GIRA X1 | 10.10.1.138 | 20 |
| `00:20:85:C0:92:FA` | UPS 3000 | 10.10.1.109 | 99 |
| `EC:71:DB:5F:BC:C1` | Reolink Camera | 10.10.1.123 | 20 |