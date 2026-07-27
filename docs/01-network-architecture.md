# Home Network Architecture

> **Canonical doc.** Merges: `Home Lab & Family Network Architecture.md`, `Homelab network architecture.md` (duplicate), `Multi-VLAN DNS Integration Architecture.md`.

---

## Hardware (Existing — Owned)

| Device | Model | Role |
|--------|-------|------|
| Router | MikroTik RB4011iGS+ | PPPoE, VLAN routing, firewall, WireGuard server, CAPsMAN |
| Switch | MikroTik CRS328-24P-4S+ | Layer-2 VLAN-aware, PoE for APs, trunk via SFP+ |
| APs | hAP ac, hAP ac² (×2 + 1 spare) | CAPsMAN-managed, all wired (no mesh) |
| Home Server (Phase 1) | Intel i7-7700K + Radeon RX 7600 + Intel i350-T2 | Bare-metal Debian desktop, Docker AI host, Technitium DNS, Pi-hole, Headscale, family PC |

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
| 1 | — | — | Blackhole (unused) | — |
| 10 | Home | 10.10.1.0/24 | Trusted family devices, phones, servers, HA | "Kogler" |
| 20 | IoT | 10.10.20.0/24 | Smart-home (KNX, Shelly, ESP32-S3 voice mic), no internet | "Kogler IOT" |
| 30 | Guest | 10.10.30.0/24 | Internet-only, client isolation | "Kogler guest" |
| 40 | Kids | 10.10.40.0/24 | Filtered DNS, restricted access, time-blocked 22:00–07:00 | "Kogler Kids" |
| 50 | Media | 10.10.50.0/24 | NVIDIA Shield, gaming consoles, smart TV | — |
| 99 | Management | 10.10.99.0/24 | Router, switch, AP management | — |

### Physical Layout

- `ether1` → ISP ONT (PPPoE)
- `sfp-sfpplus1` → trunk to CRS328 (VLANs 10,20,30,40,50,99 tagged)
- Home Server (Phase 1) → single UTP to CRS328, VLAN trunk (10,20,50 tagged, 99 native for Management)
- Other ports → access ports as needed, or all devices behind the switch

> **Note:** The home server has an Intel i350-T2 dual-port NIC, but only one port is used (single UTP cable at location). All VLANs are carried over this single trunk link to the CRS328 switch.

### CAPsMAN

- **Mode:** `local-forwarding=no` (tunnel all traffic to central router for VLAN tagging)
- **All APs are wired** — no mesh hops
- SSID-to-VLAN mapping:

| CAPsMAN Config | VLAN ID | SSID |
|----------------|---------|------|
| cfg_kogler | 10 | Kogler |
| cfg_Kogler-IOT | 20 | Kogler IOT |
| cfg_Kogler-guest | 30 | Kogler guest |
| cfg_kogler-kids | 40 | Kogler Kids |

---

## Firewall Rules (Inter-VLAN)

**Default-deny** forwarding between VLANs. Specific exceptions:

| Source VLAN | Destination VLAN | Rule |
|-------------|-----------------|------|
| Home (10) | IoT (20) | Accept established/related + new from trusted IPs for MQTT/HA |
| Home (10) | Management (99) | Accept for SSH/WinBox/HTTPS |
| Home (10) | Media (50) | Accept (remote control, casting) |
| IoT (20) | Home (10) | **Drop all** (only replies to Home-initiated) |
| IoT (20) | WAN | **Drop all** (no internet — disable rule manually for firmware updates) |
| Media (50) | Home (10) | Accept (media server, Plex/Jellyfin) |
| Guest (30) | any LAN | **Drop all** (internet only) |
| Kids (40) | Home (10) | Drop, DNS forced through filter |
| Kids (40) | WAN | Drop 22:00–07:00 (bedtime — hard block at firewall, bypass-proof) |
| All (except IoT) | WAN | Allowed (masqueraded) |

Implemented with **address-lists** and **interface lists** in RouterOS.

---

## DNS Architecture (All VLANs)

### Design: Technitium as Central DNS Router

Technitium runs on the **Phase 1 home server** (bare-metal Debian, Management VLAN IP). It intercepts all DNS queries from every VLAN and routes them to the appropriate upstream filter based on source subnet. Pi-hole also runs on the same host as a Docker container.

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

- Allow DNS (UDP 53) from all user VLANs to Technitium IP on Management VLAN (99)
- Global inter-VLAN drop rule sits **below** these exceptions

### Pi-hole Configuration

- Upstream: Cloudflare (1.1.1.1) or Google (8.8.8.8)
- Conditional forwarding: local domain → Technitium IP (so Pi-hole logs show hostnames, not raw IPs)
- Internal Technitium blocklists **disabled** (to minimize RAM; Pi-hole handles blocking)

### DHCP Responsibility

DHCP is handled entirely by the RB4011 router — **not** Technitium. The router runs a DHCP server on each VLAN interface. This ensures devices always get IP leases even if the Debian PC is down. DHCP option 15 (`domain=home.kogler.si`) is set on each DHCP network so clients know their local domain.

### DNS Resilience

RouterOS `/ip dns` forwards to Technitium as primary, `1.1.1.1` as secondary:

```
Client → Router (10.10.x.1) → Technitium (10.10.99.X) → Pi-hole/AdGuard/Quad9
                             ↘ 1.1.1.1 (fallback if Debian PC unreachable)
```

If the Debian PC is down: internet still works (unfiltered), but local `*.home.kogler.si` names and ad-blocking are temporarily unavailable. DHCP clients are unaffected — they always point at the router's IP for DNS.

### Local Name Resolution & mDNS

- **DHCP lease integration:** Technitium queries the RouterOS REST API for `/ip/dhcp-server/lease` and automatically creates `*.home.kogler.si` DNS records for all devices with hostnames
- **mDNS reflector:** Technitium bridges `.local` names across all VLANs. RouterOS built-in mDNS is bridge-wide only and cannot cross VLAN boundaries

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
   - Router initially forwards DNS to 1.1.1.1. Technitium deployment happens via Ansible after Debian PC is operational — then a single-line change on the router switches DNS forwarding to Technitium.

---

## Router Config Storage

- `rb4011_initial.rsc` — fresh-start baseline for factory-reset router (manual import via WinBox)
- Current config exported as `rb4011_config.rsc` → stored in `Iaac/router/`
- All subsequent config changes via **Ansible** or version-controlled `.rsc` snippets
- Git-versioned in the homelab repo