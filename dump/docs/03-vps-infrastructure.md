# VPS Infrastructure

> **Canonical doc.** Merges: `družinski web sistem.md`, `Varnostni načrt za zaščito VPS.md`, `1password authentik.md`, `chosen db backup service.md`, VPS sections from `Home Lab & Family Network Architecture.md`.

---

## Provider & Specs

| Item | Provider | Specs | Cost |
|------|----------|-------|------|
| VPS | **Contabo Storage VPS 30** | 6 vCPU, 18 GB RAM, 1 TB SSD | ~€15/mo |
| Bulk Storage | **Hetzner Storage Box** (1 TB) | CIFS-mounted for photos/files | ~€4/mo |
| Backup Storage | **iDrive e2** | S3-compatible, Kopia target | ~€5/mo |

> **Why Contabo over Hetzner dedicated:** The dedicated server is overkill for 4+4 users. Contabo VPS 30 provides enough resources for Proxmox with room for monitoring/observability stack. Hetzner Storage Box handles bulk files economically.

---

## Hypervisor: Proxmox VE

Proxmox is preferred over Docker-only because the stack will include monitoring, observability, and future lab VMs.

### Network Bridges

| Bridge | Name | CIDR | Purpose |
|--------|------|------|---------|
| vmbr0 | WAN | public IP | Internet-facing reverse proxy |
| vmbr1 | DMZ | 10.255.10.0/24 | Traefik, CrowdSec |
| vmbr2 | Services | 10.255.20.0/24 | Authentik, Immich, OpenCloud, Git |
| vmbr3 | Lab | 10.255.30.0/24 | Isolated testing |
| vmbr4 | Site2Site | 10.255.40.0/30 | WireGuard tunnel to home (VPS endpoint: 10.255.40.2) |

### Firewall (Proxmox-level)
- Default **deny all** inter-bridge traffic
- Allow Services → DMZ (reverse proxy reaches apps)
- Allow Site2Site → Services (home accesses VPS services)
- Block Lab → all other bridges
- Block WAN → everything except :443 (HTTPS) to DMZ

---

## Application Stack

```
                         INTERNET
                            │
                    ┌───────▼────────┐
                    │   Cloudflare   │ DDoS, geo-blocking (orange cloud)
                    │   (optional)   │
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
        │    ┌──────────────┼───────────────────┘
        │    │              │
  ┌─────▼────▼──────┐  ┌────▼──────────┐
  │  Forgejo (Git)  │  │Hetzner StorBox│ ← bulk files (CIFS mounted)
  │  + Kopia Web UI │  │    (1 TB)     │
  └─────────────────┘  └───────────────┘

  DBs, thumbnails, indexes → local VPS SSD (speed)
  Raw photos, large files   → Hetzner Storage Box (economy)
```

### Service Choices

| Service | Software | Why |
|---------|----------|-----|
| Reverse Proxy | **Traefik** | Auto-SSL, Docker-native labels, Forward Auth middleware |
| Identity | **Authentik** | OIDC SSO, MFA (WebAuthn/TOTP), Forward Auth for all apps |
| File Sync | **OpenCloud** | Go-based (~100MB RAM), WebDAV, OIDC, Windows Explorer integration, Android app |
| Photos | **Immich** | C++/Go, fast, AI face recognition, mobile apps, **remote ML at home server** |
| Email/Calendar | **Infomaniak kSuite** | Swiss (EU privacy), CalDAV/VTODO, catch-all aliases, paid |
| Git + CI/CD | **Forgejo** | Lightweight, OIDC, self-hosted, built-in Actions runner, Renovate integration |
| WAF/Brute-force | **CrowdSec** | Community threat intel, free for personal use, Authentik + Traefik parsers |
| Update Tracking | **Renovate Bot** | Tracks Docker upstreams, 3-day stability delay, auto-PR generation — see [08](08-gitops-operations.md) |
| Family Dashboard | **Homepage** | App launchpad at `kogler.si`, Authentik-protected, auto-generated config — see [08](08-gitops-operations.md) |

### What is NOT on the VPS
- **Pangolin** — removed from plan. Traefik handles all reverse proxy duties.
- **Home Assistant** — stays on-prem (home server or Raspberry Pi 4)
- **LLM/Ollama** — runs on home server GPU
- **Immich ML** — runs on home server GPU (remote ML feature)
- **Homepage** — runs on VPS (see Service Choices above)
- **Renovate Bot** — runs on VPS alongside Forgejo (see Service Choices above)

---

## Security Hardening

### Layer 1: Cloudflare (TBD)
- **Not yet decided** — needs further investigation
- Proxy (orange cloud) hides real VPS IP, WAF geo-blocking, absorbs DDoS
- Alternative: direct exposure with Traefik + CrowdSec only (simpler, no third party)

### Layer 2: Traefik Security Headers
```yaml
browserXssFilter: true
contentTypeNosniff: true
forceSTSHeader: true
stsSeconds: 31536000
stsIncludeSubdomains: true
frameDeny: true
X-Robots-Tag: "none,noarchive,nosnippet,notranslate,noimageindex"
```

### Layer 3: CrowdSec
- Parses Authentik + Traefik logs
- Community blocklist (IPs that attacked others)
- Free for personal use

### Layer 4: Authentik Forward Auth
- No app exposes its own login publicly
- Traefik middleware blocks traffic before it reaches the app

### Layer 5: Docker Security
- Separate `traefik-public` network for proxy ↔ app communication
- Databases on isolated internal networks
- Containers run as non-root where possible, `cap_drop: [ALL]`

### 🔴 Critical: Trusted Proxies
```
AUTHENTIK_TRUSTED_PROXIES = <Traefik IP>, <Cloudflare IPs>
```
Without this, CrowdSec/Fail2Ban will block your own proxy and break everything.

---

## Immich — Remote ML at Home Server

- **Immich runs on VPS** (app server + database + thumbnails on local SSD)
- **Raw photos stored on Hetzner Storage Box** (mounted via CIFS)
- **Machine learning (face recognition, object detection) offloaded to home server GPU** via Immich's remote ML feature. In Phase 1 this targets the bare-metal Debian desktop's Docker immich-ml container (RX 7600); in Phase 2 it targets the Proxmox LXC (R9700).
- **Current state:** Photos on Google Photos → will migrate to Storage Box after idempotent Ansible setup
- Photos are **publicly accessible** (like Google Photos today)

---

## 1Password + Authentik Integration

### Setup
- Authentik in **Compatibility Mode** → 1Password autofill works (solves split username/password flow)
- Family uses **1Password Passkeys** (WebAuthn) for biometric login
- Conditional access policy possible: home LAN (skip MFA) vs remote (require MFA)

### Passwordless Flow
1. User clicks "Log in with Passkey" on Authentik
2. 1Password intercepts, prompts FaceID/TouchID/Master Password
3. Logged in — no typing

---

## Database Backup (Pre-Kopia)

Before Kopia snapshots, databases are dumped to files:

1. **tiredofit/db-backup** — long-lived service with internal cron
   - Dumps PostgreSQL, MySQL, etc. to local SSD
   - Compresses (Gzip/Bzip2/Xz/Zstd), creates checksums
   - Handles retention cleanup
2. **Kopia** then snapshots the dump files + all configs
3. Temp dump files cleaned up after successful snapshot

---

## Kopia Backups

- **Backs up:** Both VPS and home server
- **Target:** iDrive e2 (S3-compatible)
- **Features:** Client-side encryption, dedup, multi-threaded compression, Reed-Solomon error correction
- **Web GUI:** Exposed via Traefik, protected by Authentik SSO
- **Master password:** Stored in 1Password

---

## Git Repository Strategy

- **Primary:** Self-hosted Forgejo on VPS (OIDC via Authentik)
- **Mirror:** Public/private GitHub
- **One repo** for everything: IaC code, Ansible playbooks, Docker Compose files, RouterOS scripts, technical documentation, and family guides
- **Auto-generated:** `docs/inventory.md` (service version matrix) — regenerated by Ansible post-deploy hook. `renovate.json` at repo root configures Renovate Bot
- README.md at repo root: links to `docs/technical/` for architecture, `docs/family/` for family guides (last priority)
- **Forgejo is the authoritative source** — management laptop pulls from here, Actions runner deploys from here. Git is the single source of truth

---

## Domain & Subdomain Plan

- **Public domain:** `kogler.si` (services accessible from internet)
- **Local domain:** `kogler.lan` (internal-only services, resolved by Technitium)

| Service | Subdomain | Access |
|---------|-----------|--------|
| **Homepage** | `kogler.si` (root) | Public (Authentik-protected) — family landing page, app launchpad |
| Immich | `foto.kogler.si` | Public (like Google Photos today) |
| OpenCloud | `file.kogler.si` | Public |
| Authentik | `sso.kogler.si` | Public (login portal for all apps) |
| Forgejo (Git) | `git.kogler.si` | Public |
| Kopia Web UI | `bck.kogler.si` | Public (SSO-protected) |
| Headscale | `vpn.kogler.si` | Public (coordination server) |
| Grafana | `stats.kogler.si` | Public (SSO-protected) |
| Home Assistant | `ha.kogler.lan` | Local only |
| Technitium | `dns.kogler.lan` | Local only |
| Pi-hole | `ad.kogler.lan` | Local only |

### Suggested additions (to consider):

| Service | Subdomain | Access | Notes |
|---------|-----------|--------|-------|
| Traefik Dashboard | `traefik.kogler.lan` | Local only | Router admin UI |
| Proxmox (VPS) | `pve.kogler.lan` | Local only (via VPN) | VPS hypervisor management |
| Proxmox (Home) | `pve-home.kogler.lan` | Local only | Home hypervisor management |
| Uptime/Monitoring | `status.kogler.si` | Public (SSO) | If you add Uptime Kuma or similar |
| CrowdSec Dashboard | `sec.kogler.lan` | Local only | Security overview |
| n8n | `auto.kogler.lan` | Local only | Office automation |
| Portainer/Dockge | `docker.kogler.lan` | Local only | Container management |

## Open Question

- **Cloudflare proxy or direct VPS IP?** Still under investigation — no decision yet. Both paths documented.

---

> **Operations layer (Isaac):** For Renovate, Forgejo Actions, Homepage configuration, and the deployment lifecycle, see [08-gitops-operations.md](08-gitops-operations.md).
> **IaC implementation:** For the Ansible specification (roles, templates, build order), see `../Iaac/README.md`.