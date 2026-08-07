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
| **Dashboard** | Metabase | No | traefik-public + services-internal | CrowdSec dashboard + Metabase learning/analytics at `sec.kogler.si` |
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
| Traefik Dashboard | `traefik.kogler.si` |
| CrowdSec Dashboard (Metabase) | `sec.kogler.si` |
| Kopia Web UI | `bck.kogler.si` |
| n8n | `auto.kogler.si` |
| Technitium | `dns.kogler.si` |
| Pi-hole | `ad.kogler.si` |
| NAS Cockpit | `cockpit-nas.kogler.si` |
| Server Cockpit | `cockpit-oldsrv.kogler.si` |

### Decision: Admin Dashboards

- **Traefik Dashboard** — **included**, internal-only, `traefik.kogler.si` (labels in [`services-traefik.md`](services-traefik.md)).
- **CrowdSec Dashboard** — **included**, internal-only, `sec.kogler.si`, served via the **Metabase** instance (one Metabase = CrowdSec view + Metabase learning/analytics sandbox). CrowdSec's bundled/pinned Metabase image is **not** used, keeping the Metabase version decoupled from CrowdSec.
- **Portainer / Dockge** — **excluded**. Conflicts with the GitOps model (Doco-CD + Ansible-templated compose) and adds an extra Docker-socket admin surface. Not deployed.

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
| Admin dashboards | **Traefik API** + **Metabase** | Traefik's built-in dashboard for routing/debug; Metabase serves the CrowdSec view and doubles as a Metabase learning/analytics sandbox — no Portainer/Dockge (GitOps) |

---

## Observability & Alerting

Full architecture in [`observability.md`](observability.md). Summary:

- **Metrics ownership:** Alloy = host + SNMP; Prometheus = service scrape (Traefik, CrowdSec, Doco-CD); blackbox = external reachability; HA exporter = entity metrics. **One metrics backend: Prometheus.**
- **Logs:** Alloy → Loki (14d).
- **Display:** Grafana (`stats.kogler.si`, **internal**, admin-only SSO) + Homepage status widget (reachability).
- **Alerts:** Grafana Alerting → n8n → Signal (Homelab Alerts group) + email fail-safe. 3 tiers (Critical/Warning/Info).
- **Alloy** runs as a host service (Ansible) with `docker.sock` access for container logs — it is **not** a containerized service.

## Service Accessibility & Traefik URL mapping (SSOT)

> **Rule of thumb:** every HTTP(S) service is reached at `https://<name>.kogler.si`
> (port 443, wildcard `*.kogler.si` cert) via Traefik — **no ports in URLs**.
> Backends bind private overlay/LAN addresses and are never exposed directly.

- **Rule A (HTTP/S):** Traefik only, hostname-based, no ports. User-facing ports
  (8123, 9090, …) exist only as Traefik backends.
- **Rule B (non-HTTP, bypass Traefik — direct IP + firewall):** DNS 53
  (primary `10.10.1.30` oldsrv, secondary `10.10.1.20` pi) · NUT 3493 (nas master,
  intra-Home) · UPS Modbus 502 + web 80/443 (`10.10.99.9`) · SNMP 161
  (router/switch) · WireGuard · SSH/WinBox (Mgmt, trusted only).

### URL → backend

| URL | Backend |
|-----|---------|
| `https://kogler.si` / `home.` | Homepage |
| `https://ha.kogler.si` | `10.10.1.200:8123` (VIP, keepalived) |
| `https://cockpit-nas.kogler.si` | `10.10.1.10:9090` |
| `https://cockpit-oldsrv.kogler.si` | `10.10.1.30:9090` |
| `https://dns.kogler.si` | Technitium web UI (resolution stays `10.10.1.30`/`10.10.1.20`:53) |
| `https://ad.kogler.si` | Pi-hole |
| `https://stats.kogler.si` | Grafana |
| `https://traefik.kogler.si` | Traefik Dashboard |
| `https://sec.kogler.si` | CrowdSec Dashboard / Metabase |
| `https://foto./file./sso./git./vpn./bck./auto.` | Immich / OpenCloud / Authentik / Forgejo / Headscale / Kopia / n8n |

**Cockpit scope:** nas + oldsrv only. The Pi is managed via SSH/Ansible + the HA
Web UI — it does **not** run Cockpit.

> Addresses are defined in the single source of truth — [`network-addresses.md`](network-addresses.md).
> The executable half of this mapping lives in the Traefik labels in `IaC/ansible/templates/docker_services/*/docker-compose.yml.j2`.

## Related

- [Traefik — Reverse Proxy & Edge](services-traefik.md)
- [Authentik — Identity & SSO](services-authentik.md)
- [Deferred VPS Infrastructure](services-vps.md)
- [Docker Compose Specification](deployment-compose.md)
- [Service Subscriptions & Costs](subscription.md)
