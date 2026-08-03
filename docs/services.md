# Service Catalog

> **Role:** Broad context — all Docker services, networks, domains.
> **Links to:** `services-traefik.md`, `services-authentik.md`, `services-vps.md`, `deployment-compose.md`, `subscription.md`
> **Linked from:** `index.md`, `deployment-ansible.md`

---

## Service Catalog (Phase 1 — all on debhost)

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
| **Observe** | Alloy | No | host + services-internal | Host metrics + logs + SNMP agent (Docker socket) |
| **Observe** | Prometheus | No | db-internal | Sole metrics store (30d) |
| **Observe** | Loki | No | db-internal | Log aggregation (14d) |
| **Observe** | Grafana | No | traefik-public + db-internal | Dashboards at `stats.kogler.si` |
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

- **Public domain:** `kogler.si`
- **Local domain:** `home.kogler.si` (resolved by Technitium)

| Service | Subdomain | Access |
|---------|-----------|--------|
| **Homepage** | `kogler.si` (root) | Public (Authentik-protected) |
| Immich | `foto.kogler.si` | Public |
| OpenCloud | `file.kogler.si` | Public |
| Authentik | `sso.kogler.si` | Public |
| Forgejo | `git.kogler.si` | Public |
| Kopia Web UI | `bck.kogler.si` | Public (SSO-protected) |
| Headscale | `vpn.kogler.si` | Public |
| Grafana | `stats.kogler.si` | Public (SSO-protected) |
| n8n | `auto.home.kogler.si` | Local only |
| Home Assistant | `ha.home.kogler.si` | Local only |
| Technitium | `dns.home.kogler.si` | Local only |
| Pi-hole | `ad.home.kogler.si` | Local only |

### Suggested (not deployed yet)

| Service | Subdomain | Access |
|---------|-----------|--------|
| Traefik Dashboard | `traefik.home.kogler.si` | Local only |
| CrowdSec Dashboard | `sec.home.kogler.si` | Local only |
| Portainer/Dockge | `docker.home.kogler.si` | Local only |

---

## What Is NOT on debhost

- **Home Assistant** — on Raspberry Pi 4 (HA config in this repo)
- **VPS services** — deferred to Phase 2+ ([`services-vps.md`](services-vps.md))
- **Pangolin** — removed; Traefik handles all reverse proxy

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
- **Display:** Grafana (`stats.kogler.si`, admin-only SSO) + Homepage status widget (reachability).
- **Alerts:** Grafana Alerting → n8n → Signal (Homelab Alerts group) + email fail-safe. 3 tiers (Critical/Warning/Info).
- **Alloy** runs as a host service (Ansible) with `docker.sock` access for container logs — it is **not** a containerized service.