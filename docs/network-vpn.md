---
title: VPN & Remote Access
role: detail
domain: network
status: active
tags: [network, vpn, wireguard, headscale]
---
# VPN & Remote Access

> **Role:** Detail — WireGuard site-to-site, Headscale mobile mesh, remote access.
> **Links to:** `network.md`, `hardware-oldsrv.md`
> **Linked from:** `network.md`, `index.md`

---

## Two Layers, Two Subnet Families

| Layer | Technology | Endpoint | Purpose |
|-------|-----------|----------|---------|
| **Site-to-Site** | WireGuard (native RouterOS) | RB4011 ↔ VPS, port 51820 | Home LAN ↔ VPS services, always on |
| **Mobile Mesh** | **Headscale** (self-hosted Tailscale) | Home server Docker | Family phones/devices — easier app, wife-friendly |

> **Strategy:** WireGuard is **site-to-site only**. User devices use Headscale.
> The old WireGuard road-warrior endpoint and the travel router were **removed** —
> Headscale fully replaces them.

### Reserved Subnets

| Family | Range | Allocations |
|--------|-------|-------------|
| **WireGuard / tunnel** | `10.255.0.0/16` | `10.255.40.0/30` S2S link (home `.1` ↔ VPS `.2`) · `10.255.20.0/24` VPS services · `10.255.10.0/24` VPS DMZ · `10.255.30.0/24` VPS lab |
| **Headscale overlay** | `100.64.0.0/10` | CGNAT (Tailscale-compatible) — router routes this to Home LAN |
| **Home LAN** | `10.10.0.0/16` | VLANs `10.10.x.0/24` (see `network-vlans.md`) |

---

## Layer 1: WireGuard Site-to-Site (Home ↔ VPS)

- **Home RB4011:** `10.255.40.1/30`
- **VPS WireGuard endpoint:** `10.255.40.2/30`
- Always on, no on-demand
- Home router: static route `10.255.20.0/24 → via 10.255.40.2`
- VPS: route `10.10.0.0/16 → via 10.255.40.1`

## Layer 2: Headscale (Mobile Mesh)

- Runs on home server as Docker container
- Overlay subnet: `100.64.0.0/10`
- Clients: Android/iOS Tailscale app, laptops
- On RB4011: static route + firewall rules so `100.64.0.0/10` reaches `10.10.1.0/24`
- Headscale traffic to VPS goes through the site-to-site WireGuard tunnel

### Transition
1. Deploy Headscale on home server
2. Family installs the Tailscale app (one-by-one migration from the removed road-warrior / travel-router paths)
3. WireGuard road-warrior and the travel router are **gone** — no fallback surface to maintain

---

## Family Usage Scenarios

| Situation | How to Connect |
|-----------|---------------|
| **At home** | "Kogler" SSID, `kogler.si` dashboard |
| **Traveling** | Tailscale app → tap Connect (mobile mesh) |
| **Remote (anywhere)** | Tailscale → access Immich, OpenCloud, HA |