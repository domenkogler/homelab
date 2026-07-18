# Home Network Architecture

> **Canonical doc.** Merges: `Home Lab & Family Network Architecture.md`, `Homelab network architecture.md` (duplicate), `Multi-VLAN DNS Integration Architecture.md`.

---

## Hardware (Existing — Owned)

| Device | Model | Role |
|--------|-------|------|
| Router | MikroTik RB4011iGS+ | PPPoE, VLAN routing, firewall, WireGuard server, CAPsMAN |
| Switch | MikroTik CRS328-24P-4S+ | Layer-2 VLAN-aware, PoE for APs, trunk via SFP+ |
| APs | hAP ac, hAP ac² (×2 + 1 spare) | CAPsMAN-managed, all wired (no mesh) |

---

## WAN / ISP

- **ISP:** Telekom Slovenije
- **Connection:** PPPoE on `ether1` (ONT)
- **IPv4:** Static public IP with domain `vpn.kogler.si`
- **IPv6:** Fully enabled, `/56` prefix via PPPoE

---

## VLAN Plan

All wired ports and CAPsMAN wireless traffic carried over a **single VLAN-aware bridge** on the RB4011. Inter-VLAN routing happens on the router; the switch is pure Layer-2.

| VLAN ID | Name | Subnet | Purpose | SSID |
|---------|------|--------|---------|------|
| 1 | Management | 10.10.99.0/24 | Router, switch, AP management | — |
| 10 | Home | 10.10.1.0/24 | Trusted family devices, servers, NAS, HA | "Kogler" |
| 20 | IoT | 10.10.20.0/24 | Smart-home (KNX, Shelly) — isolated | "Kogler IOT" |
| 30 | Guest | 10.10.30.0/24 | Internet-only, client isolation | "Kogler guest" |
| 40 | Kids | 10.10.40.0/24 | Filtered DNS, restricted access | (future dedicated SSID) |

### Physical Layout

- `ether1` → ISP ONT (PPPoE)
- `sfp-sfpplus1` → trunk to CRS328 (VLANs 1,10,20,30,40 tagged)
- Other ports → access ports as needed, or all devices behind the switch

### CAPsMAN

- **Mode:** `local-forwarding=no` (tunnel all traffic to central router for VLAN tagging)
- **All APs are wired** — no mesh hops
- SSID-to-VLAN mapping:

| CAPsMAN Config | VLAN ID | SSID |
|----------------|---------|------|
| cfg_kogler | 10 | Kogler |
| cfg_Kogler-IOT | 20 | Kogler IOT |
| cfg_Kogler-guest | 30 | Kogler guest |
| (future) cfg_kogler-kids | 40 | Kogler kids |

---

## Firewall Rules (Inter-VLAN)

**Default-deny** forwarding between VLANs. Specific exceptions:

| Source VLAN | Destination VLAN | Rule |
|-------------|-----------------|------|
| Home (10) | IoT (20) | Accept established/related + new from trusted IPs for MQTT/HA |
| Home (10) | Management (1) | Accept for SSH/WinBox/HTTPS |
| IoT (20) | Home (10) | **Drop all** (only replies to Home-initiated) |
| Guest (30) | any LAN | **Drop all** (internet only) |
| Kids (40) | Home (10) | Drop, DNS forced through filter |
| All | WAN | Allowed (masqueraded) |

Implemented with **address-lists** and **interface lists** in RouterOS.

---

## DNS Architecture (All VLANs)

### Design: Technitium as Central DNS Router

Technitium runs on the **home server** (Management VLAN). It intercepts all DNS queries from every VLAN and routes them to the appropriate upstream filter based on source subnet.

```
                     ┌──────────────────────────┐
                     │     Technitium           │
                     │  (Central DNS Router)    │
                     │  Management VLAN         │
                     └──────┬───────┬───────────┘
                            │       │
            ┌───────────────┼───────┼───────────────┐
            │               │       │               │
      ┌─────▼─────┐  ┌──────▼──┐ ┌──▼───────┐  ┌────▼────┐
      │  Pi-hole  │  │ AdGuard │ │Cloudflare│  │ Quad9   │
      │ (Home)    │  │ (Kids)  │ │ Families │  │ (IoT)   │
      │ Ad-block  │  │Adult flt│ │1.1.1.3   │  │9.9.9.9  │
      └───────────┘  └─────────┘ └──────────┘  └─────────┘
```

### Per-Subnet DNS Policy (Technitium Group Mapping)

| Source Subnet | Technitium Group | Upstream Filter | Purpose |
|--------------|------------------|-----------------|---------|
| Management | — | Local system | Infrastructure isolation |
| Home (10.10.1.0/24) | Main-Group | **Pi-hole** | Aggressive ad-blocking |
| Kids (10.10.40.0/24) | Kids-Group | **Cloudflare Families** (1.1.1.3) | Adult content + porn filtering |
| IoT (10.10.20.0/24) | IoT-Group | **Quad9** (9.9.9.9) | Malware + botnet blocking |
| Guest (10.10.30.0/24) | Guest-Group | Standard public (1.1.1.1) | No filtering needed |

### MikroTik Firewall Rules for DNS

- Allow DNS (UDP 53) from all user VLANs to Technitium IP on Management VLAN
- Allow DHCP (UDP 67-68) from user VLANs to Technitium
- Global inter-VLAN drop rule sits **below** these exceptions

### Pi-hole Configuration

- Upstream: Cloudflare (1.1.1.1) or Google (8.8.8.8)
- Conditional forwarding: local domain → Technitium IP (so Pi-hole logs show hostnames, not raw IPs)
- Internal Technitium blocklists **disabled** (to minimize RAM; Pi-hole handles blocking)

### Current State

RB4011 currently just forwards DNS to 1.1.1.1/8.8.8.8 — no filtering at all. This design replaces that entirely.

---

## Migration Plan (Summary)

From the full plan in the original architecture doc:

1. **Backup** current RB4011 config
2. **Phase 1** (2h): VLAN core — new bridge, VLAN interfaces, DHCP servers, firewall chain
3. **Phase 2** (1h): Switch & AP migration — CRS328 VLAN-aware bridge, CAPsMAN update
4. **Phase 3** (2h): Device re-assignment — move wired devices to correct VLANs, update HA
5. **Phase 4** (1h): VPN & DNS — WireGuard road-warrior, DNS architecture (Technitium + Pi-hole + AdGuard)

---

## Router Config Storage

- Current config exported as `rb4011_config.rsc` → stored in `Iaac/router/`
- All future config changes via **Ansible** or version-controlled `.rsc` files
- Git-versioned in the homelab repo