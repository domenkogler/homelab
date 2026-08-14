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

> Subdomains are relative to `kogler.si` (no port, no suffix). RAM = approx **idle / peak in MB** —
> estimates to be validated with `container_memory_working_set_bytes` after deploy (TODO, `observability.md`).
> Network codes (`P/I/D/W`, `host`): see [Docker Networks](#docker-networks). Exposure: see
> [Domain & Subdomain Plan](#domain--subdomain-plan) — **anything not listed there as public is internal-only**.

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| Traefik | traefik | P | 60–120 / 250 | Reverse proxy, auto-SSL, Forward Auth (dashboard internal) |
| CrowdSec | — | P | 100–200 / 400 | WAF, brute-force protection (dashboard via Metabase) |
| Authentik | sso | P+I | 700–1,100 / 2,000 | OIDC SSO, MFA (WebAuthn) — bundle: server+worker+postgres+redis |
| OpenCloud | file | I | 250–400 / 700 | File sync, WebDAV, OIDC — Go (~100 MB), lighter than Nextcloud |
| Immich | foto | I | 800–1,300 / 2,500 | Photo management, mobile apps (app+postgres+redis) |
| Forgejo | git | I | 150–250 / 450 | Git hosting, Issues, PRs (+ Actions runner) |
| Ollama | — | I | 600–1,000 / 2,500–4,000 | LLM inference (Qwen, Llama) — models in **AMD RX 7600 8 GB VRAM** |
| Immich-ML | — | I | 300–600 / 1,200 | Face recognition, smart search — shares AMD VRAM |
| Technitium | dns | I | 120–250 / 400 | Central DNS router, VLAN-aware (binds 53 on host) |
| Pi-hole | ad | I | 100–200 / 300 | Ad-blocking DNS |
| Headscale | vpn | P | 60–120 / 250 | Tailscale coordination server |
| Kopia | bck | I | 150–250 / 500 | Encrypted off-site backup → iDrive e2 |
| DB Backup | — | D | 30–60 / 200 | Database dumps (tiredofit/db-backup) |
| Homepage | kogler.si (root) / home | P | 80–150 / 250 | Family launchpad + status widget |
| Metabase | sec | P+I | 250–450 / 800 | CrowdSec dashboard + analytics sandbox (one instance, two roles) |
| Alloy | — | host | 200–400 / 600 | Host metrics + logs + SNMP agent (Ansible, mounts docker.sock) |
| Prometheus | — | D | 200–400 / 800 | Sole metrics store (30d) |
| Loki | — | D | 300–600 / 1,500 | Log aggregation (14d) |
| Grafana | stats | P+D | 150–300 / 500 | Dashboards (internal) |
| blackbox-exporter | — | I | 10–25 / 40 | External reachability (`probe_success`) |
| Dozzle | logs | P | 25–50 / 80 | Live container log viewer — ALL containers, read-only docker.sock; **viewer only, Loki stays the log store** |
| n8n | auto | I | 200–400 / 700 | Alert router → Signal/email (also office automation) |
| signal-cli | — | I | 80–150 / 250 | Signal delivery (linked device, "Homelab Alerts") |
| Doco-CD | — | host | 60–120 / 200 | GitOps continuous delivery (host docker.sock) |
| Renovate Bot | — | I | 150–300 / 600 | Docker image version tracking |
| Sunshine | — | I | 100–200 / 500 | Game streaming (manual start) — AMD dGPU (VRAM) |
| HA standby | ha (VIP) | I | 300–500 / 800 | Home Assistant cold-standby on oldsrv (failover) |
| RaspberryMatic standby | — | I | 100–200 / 300 | Homematic CCU3 standby container |
| Jellyfin | media | P+I | 250–400 / +150–350 per stream | Media server — **Intel HD 630 iGPU** QuickSync transcode, own login |
| Seerr | seerr | P+I | 150–250 / 400 | Request portal (seerr.dev, `seerr/seerr`) — own login, Jellyfin/Plex/Emby |
| Sonarr | sonarr | P+I | 120–180 / 250 | TV series management (linuxserver) |
| Radarr | radarr | P+I | 140–200 / 300 | Movie management (linuxserver) |
| Lidarr | lidarr | P+I | 90–140 / 200 | Music management (linuxserver) |
| Prowlarr | prowlarr | P+I | 70–120 / 180 | Indexer registry shared by all *arr |
| Bazarr | bazarr | P+I | 80–150 / 250 | Subtitle management (connects to Sonarr/Radarr) |
| SABnzbd | sab | P+I | 90–150 / 500 | Usenet downloader → Eweka (NL), plain LAN (no VPN) |
| qBittorrent | torrent | P+I (via gluetun) | 80–130 / 300 | Torrent downloader — only egress via VPN |
| gluetun | — | P+I | 15–30 / 50 | WireGuard sidecar → PrivadoVPN (NL); only qBittorrent routes through it |
| Profilarr | profilarr | P+I | 50–100 / 150 | Quality-profile UI on top of Sonarr/Radarr |
| Recyclarr | — | I | 40–80 / 200 | TRaSH custom formats + quality profiles sync (scheduled, no UI) |

> **Messaging (Matrix)** — see [`services-matrix.md`](services-matrix.md): homeserver **Tuwunel** (`matrix.`), web client **Element Web** (`chat.`) — **native-only** (family↔family). Public + federated; Matrix-native SSO → Authentik (not Forward-Auth). WhatsApp/Messenger/Signal **bridges are deferred** (Phase-2 best-effort, dedicated numbers only). Rows below are the planned Phase-1 additions (estimates to validate after deploy).

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| Tuwunel (homeserver) | matrix | P+I+D | 120–250 / 600 | Rust Matrix homeserver (`/_matrix/*`, public/federated, native SSO → Authentik) |
| Element Web | chat | P | 30–80 / 150 | Matrix web client (SSO via homeserver → Authentik) |

> **RAM sanity (48 GB on oldsrv):** typical idle ≈ 12–15 GB, worst-case burst ≈ 22–26 GB,
> gaming mode ≈ 10–13 GB — ample headroom. Plus host desktop + browser 2–4 GB (6–8 GB heavy).
> Estimates only; validate with real working-set metrics after deploy (observability TODO).

> **Storage & versions (summary):** storage SSOT = [`storage-zfs.md`](storage-zfs.md). OpenCloud keeps its
> own per-file versions (`REV.*` in `.oc-nodes/`); `tank/data/documents` gets **5-min ZFS snapshots kept 8 h**
> as the deeper history. OpenCloud FR [opencloud-eu/opencloud#1702](https://github.com/opencloud-eu/opencloud/issues/1702)
> (expose ZFS snapshots in the version panel) is a future option, not planned around.

---

## Docker Networks

| Network | Purpose |
|---------|---------|
| traefik-public | Traefik ↔ exposed services |
| services-internal | App ↔ app communication |
| db-internal | Databases, fully isolated |
| wireguard-s2s | WireGuard tunnel to VPS (Phase 2 — not yet used) |

> CIDRs: [`network-addresses.md`](network-addresses.md) → *Infrastructure networks* (SSOT).

> **Network codes (used in the catalog above):** `P` = traefik-public (edge) · `I` = services-internal
> (app ↔ app) · `D` = db-internal (isolated) · `W` = wireguard-s2s (VPS tunnel, Phase 2 — not yet used)
> · `host` = host process / host docker.sock, not on an overlay (Alloy, Doco-CD).

---

## Domain & Subdomain Plan

- **Single namespace:** `kogler.si`. Public DNS (Cloudflare, **DNS-only**), local DNS (Technitium, split-horizon).
- One wildcard `*.kogler.si` cert via Cloudflare DNS-01.
- **Internal = no public DNS record + WAN-block.**
- In Phase 1 all services run on `oldsrv`; public-faced ones move to `vps` (Traefik) in Phase 2 — domain/URLs unchanged.

### Public (internet-facing via Traefik + Authentik) — the exceptions

The catalog above is the single list of subdomains; **only this subset** gets a Cloudflare record and a
WAN allow. Everything else in the catalog is **internal-only** (no public record, WAN-blocked; defense in depth).

| Subdomain | Service |
|-----------|---------|
| `kogler.si` (root) + `home` | Homepage — public, but behind Authentik Forward-Auth |
| `sso` | Authentik |
| `foto` | Immich |
| `file` | OpenCloud |
| `git` | Forgejo |
| `ha` | Home Assistant (VIP, HA-native auth, no Forward-Auth) |
| `vpn` | Headscale |
| `matrix` | Tuwunel homeserver — public/federated, `/_matrix/*` **no Forward-Auth** (Matrix-native SSO → Authentik) |
| `chat` | Element Web — Matrix-native SSO → Authentik |

### Decision: Admin Dashboards

- **Traefik Dashboard** — **included**, internal-only, `traefik.kogler.si` (labels in [`services-traefik.md`](services-traefik.md)).
- **CrowdSec Dashboard** — **included**, internal-only, `sec.kogler.si`, served via the **Metabase** instance (one Metabase = CrowdSec view + Metabase learning/analytics sandbox). CrowdSec's bundled/pinned Metabase image is **not** used, keeping the Metabase version decoupled from CrowdSec.
- **Portainer / Dockge** — **excluded**. Conflicts with the GitOps model (Doco-CD + Ansible-templated compose) and adds an extra Docker-socket admin surface. Not deployed.

---

## What Is NOT on oldsrv

- **Home Assistant (primary)** — on the Raspberry Pi 4 (HA config in this repo), co-located with **RaspberryMatic + HmIP-RFUSB** (local Homematic IP), the **Technitium secondary** DNS, and a minimal **`traefik-ha`** edge (VIP-bound) that serves `ha.kogler.si` and keeps it reachable when oldsrv is down. **Standby** Home Assistant runs on oldsrv: see [`smart-home-failover.md`](smart-home-failover.md).
- **VPS services** — deferred to Phase 2+ ([`services-vps.md`](services-vps.md))
- **Pangolin** — removed; Traefik handles all reverse proxy

## DNS Redundancy

- **Technitium primary** on oldsrv (Docker, `services-internal`).
- **Technitium secondary** on the **Raspberry Pi (`pi.kogler.si`)** — different failure domain; keeps internal `*.kogler.si` + per-subnet filtering when oldsrv is down (see [`network-dns.md`](network-dns.md)).

---

## Media / *arr Stack

Media lives on the nas **`bulk`** pool (RAIDZ2) in a single dataset — `bulk/media` — because TRaSH
hardlinks between `downloads/` and `media/` require a **single filesystem** (ZFS hardlinks can't cross
dataset boundaries).

```
bulk/media/                       # ONE dataset — ACTIVE library, NOT backed up (redownloadable)
├── media/
│   ├── movies/
│   ├── tv/
│   └── music/
└── downloads/                    # transient scratch (hardlink-import → media/, then prune)
    ├── incomplete/{usenet,torrent}
    └── complete/{movies,tv,music}   # TRaSH per-category (SABnzbd categories / qBittorrent save paths)
```

- Three NFS exports: `bulk/media` → oldsrv **`/mnt/nas/media`** (the *arr share), `tank/data` →
  `/mnt/nas/data` (immutable user data) and `bulk/data/immich-thumbs` → `/mnt/nas/thumbs` (push target) —
  two pools, three exports.
- **Import = hardlink** (Sonarr/Radarr/Lidarr: `Use Hardlinks` ON) — instant, zero-space, atomic.
- **Media is not backed up** — no sanoid snapshots, no syncoid, no Kopia. Lost media is re-fetched via
  usenet/torrents. Full layout/properties/replication: [`storage-zfs.md`](storage-zfs.md).
- **PUID/PGID `1000:1000`** (domen) across all *arr containers (linuxserver `PUID/PGID` env;
  Jellyfin `user: "1000:1000"`). NFS ownership on nas must match.
- **VPN:** only qBittorrent egress → gluetun (WireGuard, PrivadoVPN, Netherlands — same region as
  Eweka usenet). SABnzbd stays on the plain LAN (usenet is a licensed service, no VPN needed).
- **Auth:** admin UIs (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Profilarr, SABnzbd, qBittorrent) =
  Authentik Forward-Auth, built-in logins disabled. Jellyfin + Seerr = own login
  (client apps / family request portal would break under forward-auth). Dozzle (observability) is
  also Forward-Auth — see [`observability.md`](observability.md).
- **FlareSolverr: deferred** — only if an indexer actually requires Cloudflare bypass.
- All *arr subdomains are **internal-only** (not in the public set above).

| App | Web UI | Auth | Notes |
|-----|--------|------|-------|
| Jellyfin | `media.` | own login | transcode via Intel HD 630 `/dev/dri` |
| Seerr | `seerr.` | own login | family request portal |
| Sonarr/Radarr/Lidarr/Prowlarr/Bazarr/Profilarr | `<name>.` | Forward-Auth | linuxserver images |
| SABnzbd | `sab.` | Forward-Auth | → Eweka |
| qBittorrent | `torrent.` | Forward-Auth | via gluetun network namespace |
| Recyclarr | — | — | scheduled; config `recyclarr.yml` in this repo |

---

## Observability & Alerting

Full architecture in [`observability.md`](observability.md). Summary:

- **Metrics ownership:** Alloy = host + SNMP; Prometheus = service scrape (Traefik, CrowdSec, Doco-CD); blackbox = external reachability; HA exporter = entity metrics. **One metrics backend: Prometheus.**
- **Logs:** Alloy → Loki (14d).
- **Display:** Grafana (`stats.kogler.si`, **internal**, admin-only SSO) + Homepage status widget (reachability).
- **Alerts:** Grafana Alerting → n8n → Signal (Homelab Alerts group) + email fail-safe. 3 tiers (Critical/Warning/Info).
- **Alloy** runs as a host service (Ansible) with `docker.sock` access for container logs — it is **not** a containerized service.
- **Live logs:** Dozzle (`logs.kogler.si`, internal, Forward-Auth) streams live per-container logs for **all** Docker services (read-only docker.sock) — day-to-day ops tail. Viewer only: nothing is stored; Loki stays the log store (14d) and Grafana the search/alert surface.

## Service Accessibility & Traefik URL mapping (SSOT)

> **Rule of thumb:** every HTTP(S) service is reached at `https://<sub>.kogler.si`
> (port 443, wildcard `*.kogler.si` cert) via Traefik — **no ports in URLs**.
> Backends bind private overlay/LAN addresses and are never exposed directly.

- **Rule A (HTTP/S):** Traefik only, hostname-based, no ports. User-facing ports
  (8123, 9090, …) exist only as Traefik backends.
- **Rule B (non-HTTP, bypass Traefik — direct IP + firewall):** DNS 53
  (primary oldsrv, secondary pi) · NUT 3493 (nas master,
  intra-Home) · UPS web 80/443 (host `ups`) · SNMP 161
  (router/switch) · WireGuard · SSH/WinBox (Mgmt, trusted only). Host IPs per
  [`network-addresses.md`](network-addresses.md) (SSOT).

### URL → backend (edge cases only)

The catalog table above maps every `<sub>.kogler.si` → its container on Traefik. Only
these deviate from the convention and are listed here:

| URL | Backend | Why it's here |
|-----|---------|---------------|
| `https://ha.kogler.si` | VIP (`ha-vip`) :8123, keepalived | VIP edge switches nodes; never "correct" to a node IP |
| `https://dns-pi.kogler.si` | VIP (`ha-vip`) → Pi `traefik-ha` → `pi:5380` | Pi edge — reachable when oldsrv is down |
| `https://cockpit-nas.kogler.si` | `nas:9090` (IP per SSOT) | host service (not a Docker service) |
| `https://cockpit-oldsrv.kogler.si` | `oldsrv:9090` (IP per SSOT) | host service |

> The executable half of the mapping lives in the Traefik labels in
> `IaC/ansible/templates/docker_services/*/docker-compose.yml.j2`.

**Cockpit scope:** nas + oldsrv only. The Pi is managed via SSH/Ansible + the HA
Web UI — it does **not** run Cockpit.

**`ha` route coupling (VIP, must-not-break):** `ha.kogler.si` resolves to the **VIP
(`ha-vip`) on the Home VLAN**, and the VIP's `:443` edge is served by whichever
keepalived node owns it — the Pi's minimal **`traefik-ha`** edge in normal mode,
oldsrv's `traefik` after a forward takeover. Both edges serve an identical `ha`
route → VIP:8123, so the route keeps working as long as keepalived keeps the VIP on
the active HA node and every DNS server serves `ha.kogler.si → VIP` (never "correct"
it to a node IP). Treat the VIP as the only valid backend. Runbook:
[`smart-home-failover.md`](smart-home-failover.md).

## Related

- [Traefik — Reverse Proxy & Edge](services-traefik.md)
- [Authentik — Identity & SSO](services-authentik.md)
- [Matrix — Messaging](services-matrix.md)
- [Deferred VPS Infrastructure](services-vps.md)
- [Docker Compose Specification](deployment-compose.md)
- [Service Subscriptions & Costs](subscription.md)