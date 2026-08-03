# Deferred VPS Infrastructure

> **Role:** Detail — reference architecture for Contabo VPS. Deferred to Phase 2+.
> **Status:** In Phase 1, all services here run on oldsrv ([`hardware-oldsrv.md`](hardware-oldsrv.md)).
> **Links to:** `services.md`, `network-vpn.md`
> **Linked from:** `services.md`

---

## Provider & Specs

| Item | Provider | Specs | Cost |
|------|----------|-------|------|
| VPS | **Contabo Storage VPS 30** | 6 vCPU, 18 GB RAM, 1 TB SSD | ~€15/mo |
| Bulk Storage | **Hetzner Storage Box** (1 TB) | CIFS-mounted for photos/files | ~€4/mo |

> **Why Contabo over Hetzner dedicated:** Dedicated server is overkill for 4+4 users. VPS 30 provides enough resources for the Docker stack with monitoring overhead. Storage Box handles bulk files economically.

---

## OS: Debian (Docker)

Plain Debian with Docker CE — no hypervisor. Contabo VPS is already virtualized. Same Docker networks as oldsrv ([`services.md`](services.md)).

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