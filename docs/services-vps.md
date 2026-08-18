---
title: Deferred VPS Infrastructure
role: reference
domain: services
status: active
tags: [services, vps, netcup]
---
# Deferred VPS Infrastructure

> **Role:** Detail — reference architecture for the netcup VPS.
> **Status:** ✅ **Decision (2025-08-16, HD-93):** the VPS is to be **purchased before go-live** and the
> public edge moves onto it from **day one** (public Traefik + CrowdSec + Authentik + public apps terminate
> TLS on the VPS over WG S2S → oldsrv backends). This supersedes the older "deferred to Phase 2+" wording
> below, which is retained as the implementation spec for what actually ships there.
> **Links to:** `services.md`, `network-vpn.md`
> **Linked from:** `services.md`

---

## Provider & Specs

| Item | Provider | Specs | Cost |
|------|----------|-------|------|
| VPS | **netcup RS 2000 G12** (root server) | **AMD EPYC™ 9645** · **8 dedicated cores** · **16 GB DDR5 ECC** · **512 GB NVMe SSD** · **2,5 GBit/s** iface (flatrate) | **263,52 €/12 mo** (21,96 €/mo) |
| Local Block Storage | netcup add-on | Expandable up to **8 TB** (candidate bulk tier alongside Hetzner Storage Box) | *variable* |
| Bulk Storage | **Hetzner Storage Box** (live) — **BX11 1 TB**, bought 2026-08-18 (`Hertzner-SB-Data`) | CIFS-mounted for photos/files, served from VPS | **3,90 €/mo** |

> **Why netcup RS over Hetzner dedicated:** A root server gives dedicated compute for 4+4 users
> without the overhead/pricing of a full Hetzner dedicated box. Storage Box handles bulk files economically.

---

## OS: Debian (Docker)

Plain Debian with Docker CE — no hypervisor. The netcup RS is a root server (already virtualized at the provider). Same Docker networks as oldsrv ([`services.md`](services.md)).

---

## Application Stack

```
                         INTERNET
                            │
                    ┌───────▼────────┐
                    │   Cloudflare   │ DDoS, geo-blocking (optional)
                    └───────┬────────┘
                            │ :443
                    ┌───────▼────────┐
                    │    Traefik     │ Reverse proxy, auto-SSL, Forward Auth
                    │  + CrowdSec    │ Brute-force protection
                    └───────┬────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
  ┌─────▼─────┐      ┌──────▼──────┐     ┌──────▼──────┐
  │ Authentik │      │  OpenCloud  │     │   Immich    │
  │  (SSO)    │      │ (File sync) │     │  (Photos)   │
  └─────┬─────┘      └──────┬──────┘     └──────┬──────┘
        │                   │                   │
  ┌─────▼──────────┐  ┌─────▼──────────┐
  │  Forgejo (Git) │  │Hetzner StorBox │ ← bulk files (CIFS)
  └────────────────┘  └────────────────┘

  DBs, thumbnails → local SSD (speed)
  Raw photos      → Storage Box (economy)
```

---

## Security Hardening

### Layer 1: Cloudflare (TBD)
- Proxy (orange cloud) hides real VPS IP, WAF geo-blocking, DDoS absorption
- Alternative: direct exposure with Traefik + CrowdSec only

### Layer 2: Traefik Security Headers
(See [`services-traefik.md`](services-traefik.md))

### Layer 3: CrowdSec
- Parses Authentik + Traefik logs
- Community blocklist, free for personal use

### Layer 4: Authentik Forward Auth
- No app exposes its own login publicly
- Traefik middleware blocks traffic before it reaches the app

### Layer 5: Docker Security
- Separate networks per role
- Databases on isolated `db-internal` network
- `cap_drop: [ALL]` where possible

---

## Immich — Remote ML at Home Server

- Immich app server + database on VPS
- Raw photos on Hetzner Storage Box (CIFS)
- **Machine learning offloaded to home server GPU** via Immich remote ML feature
- Phase 1: targets oldsrv immich-ml container (RX 7600)
- Phase 2: targets Proxmox LXC (R9700)

---

## VPS-Specific Firewall (iptables/nftables)

- Default **deny all** inbound except :443 and WireGuard port
- Docker networks isolated from each other
- Allow WireGuard subnet → services network

---

## Database Backup (Pre-Kopia)

1. **tiredofit/db-backup** — long-lived service with internal cron
   - Dumps PostgreSQL to local SSD
   - Compresses (Gzip/Bzip2/Xz/Zstd), creates checksums
2. **Kopia** snapshots the dump files + configs
3. Temp dumps cleaned up after successful snapshot

---

## What Stays on Home Server

- Home Assistant (Raspberry Pi 4)
- Ollama / LLM (needs GPU)
- Immich ML (needs GPU)
- DNS (Technitium + Pi-hole)
- Headscale (VPN mesh)