---
title: VLAN Plan
role: detail
domain: network
status: active
tags: [network, vlan, firewall]
---
# VLAN Plan

> **Role:** Detail — VLAN definitions, subnets, firewall rules.
> **Links to:** `network-dns.md`, `network-devices.md`
> **Linked from:** `network.md`, `index.md`

> **Status (planning):** the network is **currently flat on `10.10.1.0/24`** — VLAN segmentation below is **planned**, not yet live. Docs that historically implied devices are already isolated are being corrected (see live DHCP in `network-devices.md`).

---

## VLAN Table

| VLAN ID | Name | Subnet | Purpose | SSID |
|---------|------|--------|---------|------|
| 1 | — | — | Blackhole (unused) | — |
| 10 | Home | 10.10.1.0/24 | Trusted family devices, phones, servers, HA | "Kogler" |
| 20 | IoT | 10.10.20.0/24 | Smart-home (KNX, Shelly, ESP32-S3), no internet | "Kogler IOT" |
| 21 | IoT-Internet | 10.10.21.0/24 | Internet-needing IoT (HAP during cloud phase, Bosch appliances) | "Kogler IOT WAN" |
| 30 | Guest | 10.10.30.0/24 | Internet-only, client isolation | "Kogler guest" |
| 40 | Kids | 10.10.40.0/24 | Filtered DNS, restricted access, time-blocked 22:00–07:00 | "Kogler Kids" |
| 50 | Media | 10.10.50.0/24 | NVIDIA Shield, gaming consoles, smart TV | — |
| 99 | Management | 10.10.99.0/24 | Router, switch, AP management | — |

---

## CAPsMAN SSID-to-VLAN Mapping

| CAPsMAN Config | VLAN ID | SSID |
|----------------|---------|------|
| `cfg-kogler` | 10 | Kogler |
| `cfg-kogler-iot` | 20 | Kogler IOT |
| `cfg-kogler-iot-wan` | 21 | Kogler IOT WAN |
| `cfg-kogler-guest` | 30 | Kogler guest |
| `cfg-kogler-kids` | 40 | Kogler Kids |

- **Mode:** `local-forwarding=no` — all traffic tunneled to router for VLAN tagging
- All APs wired, no mesh

---

## Inter-VLAN Firewall Rules

**Default-deny** forwarding between VLANs. Specific exceptions:

| Source VLAN | Destination VLAN | Rule |
|-------------|-----------------|------|
| Home (10) | IoT (20) | Accept established/related + new from trusted IPs (MQTT/HA) |
| Home (10) | IoT-Internet (21) | Accept established/related + new from trusted IPs (HA→HAP, Prometheus→HA) |
| Home (10) | Management (99) | Accept SSH/WinBox/HTTPS |
| Home (10) | Media (50) | Accept (remote control, casting) |
| IoT (20) | Home (10) | **Drop all** (only replies to Home-initiated) |
| IoT (20) | WAN | **Drop all** — disable rule manually for firmware updates |
| IoT-Internet (21) | WAN | **Allowed** (these devices need cloud/internet) |
| IoT-Internet (21) | Home (10) | **Drop all** (only replies to Home-initiated) |
| Media (50) | Home (10) | Accept (media server, Plex/Jellyfin) |
| Guest (30) | any LAN | **Drop all** (internet only) |
| Kids (40) | Home (10) | Drop, DNS forced through filter |
| Kids (40) | WAN | Drop 22:00–07:00 (bedtime — hard block at firewall) |
| All (except IoT) | WAN | Allowed (masqueraded) |

Implemented with **address-lists** and **interface lists** in RouterOS.

---

## DHCP

DHCP is handled entirely by the **RB4011 router** on each VLAN interface. This ensures devices always get IP leases even if the Debian PC is down.

DHCP option 15 (`domain=kogler.si`) is set on each DHCP network.

---

## Port Type Reference

| Device type | Port config | VLAN |
|-------------|------------|------|
| Family PC, laptop, server | Access | 10 (Home) |
| Shelly, KNX, ESP32-S3 | Access | 20 (IoT, no internet) |
| Homematic HAP (cloud), Bosch IoT | Access | 21 (IoT-Internet) |
| AP (hAP ac/ac²) | Access | 99 (Mgmt) |
| Printer | Access | 10 (Home) |
| Camera | Access | 20 (IoT) |
| Shield, console, smart TV | Access | 50 (Media) |
| UPS management | Access | 99 (Mgmt) |
| Debian homelab PC | Trunk | 10,20,50 tagged + 99 native |
| SFP+ uplinks | Trunk | 10,20,30,40,50,99 tagged |