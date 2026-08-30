# Ansible managed
# Rack Connections

> **Generated** from [`rack-connections.json`](rack-connections.json) by `scripts/render_rack_connections.py` — do not hand-edit.
> Source of truth: [`assets/Rack.canvas`](assets/Rack.canvas) (Obsidian Canvas).

Each row = one physical link. Patch-panel targets show the wall-side room/device + MAC (see the panel tables).

## Device connectivity

### RB4011iGS+ Router (`rb4011`)

| Interface | Connected to | Note |
|-----------|--------------|------|
| `ether1` | **GRG-4260us GPON Gateway** eth2 `1C:64:99:51:BF:92` | WAN upstream |
| `ether2` | **Panel B / port 7** → miza / PC · PC `00:1B:21:13:12:15` |  |
| `ether3` | **Panel B / port 8** → miza / docking laptop · laptop (docking station) `48:2A:E3:9D:31:85` |  |
| `ether7` | **HP Gen 8 server** iLO4 `1C:98:EC:0E:0D:3A` | HP iLO 4 out-of-band mgmt |
| `ether9` | **HMIP-HAP HomeMatic Access Point** eth `00:1A:22:1E:F7:FD` | fixed: HMIP-HAP on eth9 |
| `ether10` | **Raspberry Pi 4 B** eth `E4:5F:01:26:EF:AA` | fixed: Raspberry Pi on eth10 |
| `sfp+` | **CRS328-24P-4S+ Switch** sfp+1 _— (no MAC)_ |  |

### CRS328-24P-4S+ Switch (`crs328`)

| Interface | Connected to | Note |
|-----------|--------------|------|
| `eth1` | **Panel A / port 2** → AP · ☠️ Mikrotik wAP ac (DEAD 2026-08-24, HD-232 — port reserved for replacement; replacement must be wifi-qcom-ac-capable) `6C:3B:6B:7D:B9:C5` | reversal: eth1->A2 |
| `eth2` | **Panel A / port 1** → kamera · Reolink RLC-420-5MP `EC:71:DB:5F:BC:C1` | reversal: eth2->A1 |
| `eth3` | **Panel A / port 4** → rack · no device _— (no MAC)_ | reversal |
| `eth4` | **Panel A / port 3** → rack / UPS · PowerWalker VFI 3000 ICR IoT `00:20:85:C0:92:FA` | reversal |
| `eth6` | **Panel B / port 3** → levo / printer · Canon TS9550 `74:BF:C0:CD:33:0B` | reversal |
| `eth9` | **HP Gen 8 server** eno2 `1C:98:EC:0E:0D:39` |  |
| `eth10` | **HP Gen 8 server** eno1 `1C:98:EC:0E:0D:38` |  |
| `eth11` | **Panel B / port 12** → omara / AP · Mikrotik hAP ac `64:D1:54:AA:24:D1` | reversal |
| `eth12` | **Panel A / port 10** → garderoba / AP · Mikrotik hAP ac2 `C4:AD:34:42:F1:7D` | reversal |
| `eth14` | **Panel B / port 14** → pod TV / konzola · Nintendo Switch 2 `E0:EF:BF:74:CE:07` | reversal |
| `eth15` | **Panel A / port 16** → miza · no device _— (no MAC)_ | reversal |
| `eth16` | **Panel A / port 15** → miza · no device _— (no MAC)_ | reversal |
| `eth20` | **Panel B / port 18** → pod TV / Streaming · Nvidia Shield TV pro `48:B0:2D:09:6F:90` | reversal |
| `eth21` | **Panel B / port 22** → elektrika / KNX · Gira IP Router `00:0A:B3:27:5F:8B` | reversal |
| `eth22` | **Panel B / port 21** → elektrika / KNX · Gira X1 `00:0A:B3:29:2C:9E` | reversal |
| `eth23` | **Panel A / port 19** → miza · no device _— (no MAC)_ | reversal |
| `eth24` | **Panel A / port 20** → miza · no device _— (no MAC)_ | reversal |
| `sfp+1` | **RB4011iGS+ Router** sfp+ `74:4D:28:8D:45:C8` |  |

### GRG-4260us GPON Gateway (`comtrend`)

| Interface | Connected to | Note |
|-----------|--------------|------|
| `eth2` | **RB4011iGS+ Router** ether1 `74:4D:28:8D:45:BE` | WAN upstream |

### HP Gen 8 server (`nas`)

| Interface | Connected to | Note |
|-----------|--------------|------|
| `eno1` | **CRS328-24P-4S+ Switch** eth10 _— (no MAC)_ |  |
| `eno2` | **CRS328-24P-4S+ Switch** eth9 _— (no MAC)_ |  |
| `iLO4` | **RB4011iGS+ Router** ether7 `74:4D:28:8D:45:C4` | HP iLO 4 out-of-band mgmt |

### Raspberry Pi 4 B (`pi`)
> Role: Home Assistant

| Interface | Connected to | Note |
|-----------|--------------|------|
| `eth` | **RB4011iGS+ Router** ether10 `74:4D:28:8D:45:C7` | fixed: Raspberry Pi on eth10 |

### HMIP-HAP HomeMatic Access Point (`hmip`)

| Interface | Connected to | Note |
|-----------|--------------|------|
| `eth` | **RB4011iGS+ Router** ether9 `74:4D:28:8D:45:C6` | fixed: HMIP-HAP on eth9 |

### TL-SG108E switch (`tplink-sg108e`)
> Note: Present in canvas as image only; no cabling table found. Wiring unknown.

_No modelled connections (appears in canvas but wiring unknown)._

## Patch panel wiring

### Patch Panel A — Schrack 24-Port Cat.6 Patch Panel A (`U18`)

| Port | Patched from | Room / end | Device | MAC |
|------|--------------|------------|--------|-----|
| ✔ 1 | CRS328-24P-4S+ Switch `eth2` | garaža kamera | Reolink RLC-420-5MP | `EC:71:DB:5F:BC:C1` |
| ✗ 2 | CRS328-24P-4S+ Switch `eth1` | garaža AP | ☠️ Mikrotik wAP ac (DEAD 2026-08-24, HD-232 — port reserved for replacement; replacement must be wifi-qcom-ac-capable) | `6C:3B:6B:7D:B9:C5` |
| ✔ 3 | CRS328-24P-4S+ Switch `eth4` | predsoba rack / UPS | PowerWalker VFI 3000 ICR IoT | `00:20:85:C0:92:FA` |
| ✗ 4 | CRS328-24P-4S+ Switch `eth3` | predsoba rack | — | `—` |
| ✗ 5 | — | hodnik domofon | — | `—` |
| ✗ 6 | — | spalnica postelja | — | `—` |
| ✗ 7 | — | spalnica postelja | — | `—` |
| ✗ 8 | — | spalnica TV | — | `—` |
| ✗ 9 | — | spalnica TV | — | `—` |
| ✔ 10 | CRS328-24P-4S+ Switch `eth12` | spalnica garderoba / AP | Mikrotik hAP ac2 | `C4:AD:34:42:F1:7D` |
| ✗ 11 | — | spalnica garderoba | — | `—` |
| ✗ 12 | — | utility  | — | `—` |
| ✗ 13 | — | roza soba postelja | — | `—` |
| ✗ 14 | — | roza soba postelja | — | `—` |
| ✗ 15 | CRS328-24P-4S+ Switch `eth16` | roza soba miza | — | `—` |
| ✗ 16 | CRS328-24P-4S+ Switch `eth15` | roza soba miza | — | `—` |
| ✗ 17 | — | zelena soba postelja | — | `—` |
| ✗ 18 | — | zelena soba postelja | — | `—` |
| ✗ 19 | CRS328-24P-4S+ Switch `eth23` | zelena soba miza | — | `—` |
| ✗ 20 | CRS328-24P-4S+ Switch `eth24` | zelena soba miza | — | `—` |
| ✗ 21 | — | zelena soba talno gretje | — | `—` |
| ✗ 22 | — | zelena soba  | — | `—` |
| ✗ 23 | — | —  | — | `—` |
| ✗ 24 | — | —  | — | `—` |

### Patch Panel B — Schrack 24-Port Cat.6 Patch Panel B (`U17`)

| Port | Patched from | Room / end | Device | MAC |
|------|--------------|------------|--------|-----|
| ✗ 1 | — | kabinet desno | — | `—` |
| ✗ 2 | — | kabinet desno | — | `—` |
| ✔ 3 | CRS328-24P-4S+ Switch `eth6` | kabinet levo / printer | Canon TS9550 | `74:BF:C0:CD:33:0B` |
| ✗ 4 | — | kabinet levo | — | `—` |
| ✗ 5 | — | kuhinja omara | — | `—` |
| ✗ 6 | — | kuhinja omara | — | `—` |
| ✔ 7 | RB4011iGS+ Router `ether2` | kabinet miza / PC | PC | `00:1B:21:13:12:15` |
| ✔ 8 | RB4011iGS+ Router `ether3` | kabinet miza / docking laptop | laptop (docking station) | `48:2A:E3:9D:31:85` |
| ✗ 9 | — | dnevna klima | — | `—` |
| ✗ 10 | — | dnevna klima | — | `—` |
| ✗ 11 | — | dnevna omara | — | `—` |
| ✔ 12 | CRS328-24P-4S+ Switch `eth11` | dnevna omara / AP | Mikrotik hAP ac | `64:D1:54:AA:24:D1` |
| ✗ 13 | — | dnevna pod TV | — | `—` |
| ✔ 14 | CRS328-24P-4S+ Switch `eth14` | dnevna pod TV / konzola | Nintendo Switch 2 | `E0:EF:BF:74:CE:07` |
| ✗ 15 | — | dnevna pod TV | — | `—` |
| ✗ 16 | — | dnevna pod TV | — | `—` |
| ✗ 17 | — | dnevna pod TV | — | `—` |
| ✔ 18 | CRS328-24P-4S+ Switch `eth20` | dnevna pod TV / Streaming | Nvidia Shield TV pro | `48:B0:2D:09:6F:90` |
| ✗ 19 | — | dnevna TV | — | `—` |
| ✗ 20 | — | dnevna TV | — | `—` |
| ✔ 21 | CRS328-24P-4S+ Switch `eth22` | predsoba elektrika / KNX | Gira X1 | `00:0A:B3:29:2C:9E` |
| ✔ 22 | CRS328-24P-4S+ Switch `eth21` | predsoba elektrika / KNX | Gira IP Router | `00:0A:B3:27:5F:8B` |
| ✗ 23 | — | —  | — | `—` |
| ✗ 24 | — | —  | — | `—` |

## Notes

- Reversal rule on CRS328 (user-confirmed): canvas draws switch ports in 2 rows; lower on-canvas cell = lower port number (eth1->A2, eth2->A1). Applied consistently to all paired columns.
- Fixed conflicts (user-confirmed): Raspberry Pi is on RB4011 ether10 (was labeled 'eth6' by a standalone canvas node); HMIP-HAP is on RB4011 ether9 (was labeled 'eth5').
- TP-Link TL-SG108E appears in the canvas as an image but has no wiring table - its connections are unknown and not modelled.
- Patch panel ports with cable but no device (e.g. A4, roza/zelena miza) are marked used:false and show 'patch cord terminated, no device'.
- Comtrend eth2 <-> RB4011 ether1 is the WAN upstream link.
- RB4011 ether4, ether5, ether6, ether8 are unused/empty.
- Comtrend eth1, eth3, eth4, eth5 are unused/empty.
