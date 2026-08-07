---
title: Service Catalog
role: broad
domain: services
status: active
tags: [services, catalog]
---
# Service Catalog

> **Role:** Broad context — all Docker services, networks, domains.
> **Links to:** `services-traefik.md`, `services-authentik.md`, `services-vps.md`, `deployment-compose.md`, `subscription.md`
> **Linked from:** `index.md`, `deployment-ansible.md`

---

## Service Catalog (Phase 1 — all on oldsrv)

| Category | Service | GPU | Network | Description |
|----------|---------|-----|---------|-------------|
| **Edge** | Traefik | No | traefik-public | Reverse proxy, auto-SSL, Forward Auth |
| **Edge** | CrowdSec | No | traefik-public | WAF, brute-force protection |
| **Identity** | Authentik | No | services-internal | OIDC SSO, MFA (WebAuthn) |
| **Platform** | OpenCloud | No | services-internal | File sync, WebDAV, OIDC |
| **Platform** | Immich | No | services-internal | Photo management, mobile apps |
| **Platform** | Forgejo | No | services-internal | Git hosting, Issues, PRs |
| **AI** | Ollama | **Yes** | services-internal | LLM inference (Qwen, Llama) |
| **AI** | Immich-ML | **Yes** | services-internal | Face recognition, smart search |
| **DNS** | Technitium | No | services-internal | Central DNS router, VLAN-aware |
| **DNS** | Pi-hole | No | services-internal | Ad-blocking DNS |
| **VPN** | Headscale | No | traefik-public | Tailscale coordination server |
| **Backup** | Kopia | No | services-internal | Encrypted off-site backup → iDrive e2 |
| **Backup** | DB Backup | No | db-internal | Database dumps (tiredofit/db-backup) |
| **Dashboard** | Homepage | No | traefik-public | Family launchpad at `kogler.si` |
| **Observe** | Alloy | No | host (Ansible, not containerized) | Host metrics + logs + SNMP agent — host-installed via Ansible, mounts docker.sock |
| **Observe** | Prometheus | No | db-internal | Sole metrics store (30d) |
| **Observe** | Loki | No | db-internal | Log aggregation (14d) |
| **Observe** | Grafana | No | traefik-public + db-internal | Dashboards at `stats.kogler.si` (internal) |
| **Observe** | blackbox-exporter | No | services-internal | External reachability (`probe_success`) |
| **Alert** | n8n | No | services-internal | Alert router → Signal/email (also office automation) |
| **CD** | Doco-CD | No | host docker.sock | GitOps continuous delivery |
| **Update** | Renovate Bot | No | services-internal | Docker image version tracking |
| **Stream** | Sunshine | **Yes** | services-internal | Game streaming (manual start) |

---

## Docker Networks

| Network | CIDR | Purpose |
|---------|------|---------|
| traefik-public | 172.20.0.0/16 | Traefik ↔ exposed services |
| services-internal | 172.21.0.0/16 | App ↔ app communication |
| db-internal | 172.22.0.0/16 | Databases, fully isolated |
| wireguard-s2s | 10.255.40.0/30 | WireGuard tunnel to VPS |

---

## Domain & Subdomain Plan

- **Single namespace:** `kogler.si`. Public DNS (Cloudflare, **DNS-only**), local DNS (Technitium, split-horizon).
- One wildcard `*.kogler.si` cert via Cloudflare DNS-01.
- **Internal = no public DNS record + WAN-block.**
- In Phase 1 all services run on `oldsrv`; public-faced ones move to `vps` (Traefik) in Phase 2 — domain/URLs unchanged.

### Public (internet-facing, via Traefik + Authentik)

| Service | Subdomain |
|---------|-----------|
| Homepage | `kogler.si` (canonical root) + **`home.kogler.si`** (alias) — public, but behind **Authentik Forward-Auth** (no anonymous access) |
| Immich | `foto.kogler.si` |
| OpenCloud | `file.kogler.si` |
| Authentik | `sso.kogler.si` |
| Forgejo | `git.kogler.si` |
| Home Assistant | `ha.kogler.si` (HA-native auth / OIDC, no Forward-Auth) |
| Headscale | `vpn.kogler.si` |

### Internal (LAN / VPN only — no public record)

| Service | Subdomain |
|---------|-----------|
| Grafana | `stats.kogler.si` |
| Kopia Web UI | `bck.kogler.si` |
| n8n | `auto.kogler.si` |
| Technitium | `dns.kogler.si` |
| Pi-hole | `ad.kogler.si` |
| NAS Cockpit | `cockpit-nas.kogler.si` |
| Server Cockpit | `cockpit-oldsrv.kogler.si` |

### Suggested (not deployed yet)

| Service | Subdomain | Access |
|---------|-----------|--------|
| Traefik Dashboard | `traefik.kogler.si` | Internal |
| CrowdSec Dashboard | `sec.kogler.si` | Internal |
| Portainer/Dockge | `docker.kogler.si` | Internal |

---

## What Is NOT on oldsrv

- **Home Assistant (primary)** — on the Raspberry Pi 4 (HA config in this repo), co-located with **RaspberryMatic + HmIP-RFUSB** (local Homematic IP) and the **Technitium secondary** DNS. **Standby** Home Assistant runs on oldsrv: see [`smart-home-failover.md`](smart-home-failover.md).
- **VPS services** — deferred to Phase 2+ ([`services-vps.md`](services-vps.md))
- **Pangolin** — removed; Traefik handles all reverse proxy

## DNS Redundancy

- **Technitium primary** on oldsrv (Docker, `services-internal`).
- **Technitium secondary** on the **Raspberry Pi (`ha.kogler.si`)** — different failure domain; keeps internal `*.kogler.si` + per-subnet filtering when oldsrv is down (see [`network-dns.md`](network-dns.md)).

---

## Service Choice Rationale

| Service | Software | Why |
|---------|----------|-----|
| Reverse Proxy | **Traefik** | Auto-SSL, Docker-native labels, Forward Auth |
| Identity | **Authentik** | OIDC SSO, MFA (WebAuthn/TOTP), Forward Auth |
| File Sync | **OpenCloud** | Go-based (~100MB RAM), WebDAV, OIDC, Windows + Android |
| Photos | **Immich** | C++/Go, AI face recognition, mobile apps |
| Email/Calendar | **Infomaniak kSuite** | Swiss (EU privacy), CalDAV, catch-all aliases |
| Git + CI/CD | **Forgejo** | Lightweight, OIDC, built-in Actions runner |
| WAF | **CrowdSec** | Community threat intel, free, Authentik + Traefik parsers |
| Dashboard | **Homepage** | App launchpad, health dots, auto-generated config |

---

## Observability & Alerting

Full architecture in [`observability.md`](observability.md). Summary:

- **Metrics ownership:** Alloy = host + SNMP; Prometheus = service scrape (Traefik, CrowdSec, Doco-CD); blackbox = external reachability; HA exporter = entity metrics. **One metrics backend: Prometheus.**
- **Logs:** Alloy → Loki (14d).
- **Display:** Grafana (`stats.kogler.si`, **internal**, admin-only SSO) + Homepage status widget (reachability).
- **Alerts:** Grafana Alerting → n8n → Signal (Homelab Alerts group) + email fail-safe. 3 tiers (Critical/Warning/Info).
- **Alloy** runs as a host service (Ansible) with `docker.sock` access for container logs — it is **not** a containerized service.

## Related

- [Traefik — Reverse Proxy & Edge](services-traefik.md)
- [Authentik — Identity & SSO](services-authentik.md)
- [Deferred VPS Infrastructure](services-vps.md)
- [Docker Compose Specification](deployment-compose.md)
- [Service Subscriptions & Costs](subscription.md)
