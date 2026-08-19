---
title: Service Catalog
role: broad
domain: services
status: active
tags: [services, catalog]
---
# Service Catalog

> **Role:** Broad context — all Docker services, networks, domains.
> **Links to:** `services-traefik.md`, `services-authentik.md`, `services-matrix.md`, `services-finance.md`, `services-vps.md`, `deployment-compose.md`, `subscription.md`
> **Linked from:** `index.md`, `deployment-ansible.md`

---

## Service Catalog (placement: HD-135 split — oldsrv GPU/LAN core + VPS edge/observability)

> Subdomains are relative to `kogler.si` (no port, no suffix). RAM = approx **idle / peak in MB** —
> estimates to be validated with `container_memory_working_set_bytes` after deploy (TODO, `observability.md`).
> Network codes (`P/I/D/W`, `host`): see [Docker Networks](#docker-networks). Exposure: see
> [Domain & Subdomain Plan](#domain--subdomain-plan) — **anything not listed there as public is internal-only**.

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| Traefik | traefik | P | 60–120 / 250 | Reverse proxy, auto-SSL, Forward Auth (dashboard internal) |
| CrowdSec | — | P | 100–200 / 400 | WAF, brute-force protection (dashboard via Metabase) |
| Authentik | sso | P+I | 700–1,100 / 2,000 | OIDC SSO, MFA (WebAuthn) — bundle: server+worker+postgres+redis |
| OpenCloud | file | I | 250–400 / 700 | File sync, WebDAV, OIDC — Go (~100 MB), lighter than Nextcloud. **Filesystem/WebDAV storage** (HD-131 D2). **Auth: native OIDC → Authentik** (multi-redirect web+desktop+mobile, HD-52); client provisioned via Blueprint + secret-egress glue |
| MinIO | — | I | 60–120 / 300 | **S3-compatible object store** (HD-131 D1) — backs **Immich originals** (bucket `immich-originals`); loopback/overlay only, no public edge. Later move to Hetzner Storage Box / cloud S3 = endpoint change |
| Immich | foto | I | 600–1,000 / 2,000 | Photo management, mobile apps (app+postgres+valkey — microservices merged into server in v3). **Originals on live Box (CIFS), thumbs/DB local** (HD-131 D1/D3). **Auth (HD-148): native OIDC → Authentik** (web + mobile `app.immich:///oauth-callback`); client via Blueprint + glue |
| Forgejo | git | I | 150–250 / 450 | Git hosting, Issues, PRs (+ Actions runner). **Auth (HD-148): native OIDC → Authentik** (web SSO + per-user API/token); client via Blueprint + glue |
| Ollama | — | I | 600–1,000 / 2,500–4,000 | LLM inference (Qwen, Llama) — models in **AMD RX 7600 8 GB VRAM** |
| Immich-ML | — | I | 300–600 / 1,200 | Face recognition, smart search — shares AMD VRAM |
| LiteLLM | — | I | 120–250 / 500 | **AI stack** — LLM gateway/router (HD-100): local Ollama + OpenRouter (gen) + Cohere (embeddings). Single OpenAI-compatible endpoint, services-internal + llm-backend; own SQLite keys/spend; only component holding upstream keys |
| Open WebUI | ai | P | 300–600 / 1,500 | **AI stack** — family chat + RAG UI (HD-101); public via Authentik OIDC + crowdsec-only; backend = LiteLLM (HD-100); RAG: Cohere embed-v4 (via LiteLLM), Docling (HD-103), PGVector (HD-102); data volume `/srv/docker/open-webui`; OIDC client provisioned via Blueprint + glue |
| Docling | — | I | 150–400 / 900 | **AI stack** — OCR / document understanding for RAG (CPU, HD-103; `docling-serve-cpu:v1.30.0`, services-internal, v1 API, HF weight cache volume) |
| OpenClaw | — | I | 200–500 / 1,200 | **AI stack** — agent orchestration (ex-Clawd, HD-104); models → LiteLLM (HD-100); OpenCloud WebDAV skill; **version pinned**; config/state volume `/srv/docker/openclaw` |
| PGVector | — | D | 100–250 / 600 | **AI stack** — vector DB for Open WebUI RAG + chat history (`db-internal`, HD-102; `pgvector/pgvector:0.8.6-pg16-trixie`; tagged; backup via db-backup DB04 → Kopia) |
| Technitium | dns | I | 120–250 / 400 | Central DNS router, VLAN-aware (binds 53 on host) |
| Pi-hole | ad | I | 100–200 / 300 | Ad-blocking DNS |
| Headscale | vpn | P | 60–120 / 250 | Tailscale coordination server |
| Kopia | bck | I | 150–250 / 500 | Encrypted off-site backup → Hetzner Storage Box (backup, far DC) |
| DB Backup | — | D | 30–60 / 200 | Database dumps (tiredofit/db-backup) |
| Homepage | kogler.si (root) / home | P | 80–150 / 250 | Family launchpad + status widget |
| Metabase | sec | P+I | 250–450 / 800 | CrowdSec dashboard + analytics sandbox (one instance, two roles). **Auth (HD-148): Forward-Auth** (Metabase OSS has NO OIDC/SSO — paid Enterprise feature; provider/`metabase_oidc` declared for future, but route stays Forward-Auth) |
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
| PairDrop | pairdrop | I | 100–180 / 300 | **P2P file share** (HD-113) — browser WebRTC "AirDrop-style" transfers, local-network device discovery, internal-only via Forward-Auth (linuxserver image; no data persisted to disk) |
| Stirling PDF | pdf | I | 150–400 / 800 | **PDF toolkit** (HD-58) — merge/split/compress/convert/number/OCR (Tesseract `eng+slv`); anonymous mode + Forward-Auth, internal-only; no local online-PDF-editor dependency; **stateless (in-memory, no disk/backup)** |
| Tuwunel (homeserver) | matrix | P+I | 150–350 / 700 | Rust Matrix homeserver (`/_matrix/*`, public/federated, native SSO → Authentik; RocksDB file store in `/srv/docker/matrix` — no external DB) |
| Element Web | chat | P | 30–80 / 150 | Matrix web client (SSO via homeserver → Authentik) |
| Actual Budget | budget | P+I | 60–120 / 250 | Budgeting + investment tracking (Node.js + SQLite, one container; native Enable Banking sync, Forward-Auth) |

> **Domain docs:** [Matrix messaging](services-matrix.md) · [Personal finance](services-finance.md)

> **RAM sanity (48 GB on oldsrv):** typical idle ≈ 12–15 GB, worst-case burst ≈ 22–26 GB,
> gaming mode ≈ 10–13 GB — ample headroom. Plus host desktop + browser 2–4 GB (6–8 GB heavy).
> Estimates only; validate with real working-set metrics after deploy (observability TODO).

> **Storage & versions (summary):** storage SSOT = [`storage-zfs.md`](storage-zfs.md). OpenCloud keeps its
> own per-file versions (`REV.*` in `.oc-nodes/`); `tank/data/documents` gets **5-min ZFS snapshots kept 8 h**
> as the deeper history. **Immich originals are S3-backed (MinIO → Storage Box later, HD-131 D1/D3)**;
> `tank/data/immich` is MinIO's object store, not a ZFS-copy of originals. OpenCloud FR
> [opencloud-eu/opencloud#1702](https://github.com/opencloud-eu/opencloud/issues/1702)
> (expose ZFS snapshots in the version panel) is a future option, not planned around.

---

## Docker Networks

| Network | Purpose |
|---------|---------|
| traefik-public | Traefik ↔ exposed services |
| services-internal | App ↔ app communication |
| db-internal | Databases, fully isolated |
| wireguard-s2s | WireGuard S2S tunnel home router ↔ VPS (HD-03/HD-135; reaches home VLANs + wg-vps-services) |

> CIDRs: [`network-addresses.md`](network-addresses.md) → *Infrastructure networks* (SSOT).

> **Network codes (used in the catalog above):** `P` = traefik-public (edge) · `I` = services-internal
> (app ↔ app) · `D` = db-internal (isolated) · `W` = wireguard-s2s (home router ↔ VPS S2S tunnel)
> · `host` = host process / host docker.sock, not on an overlay (Alloy, Doco-CD).

---

## Domain & Subdomain Plan

- **Single namespace:** `kogler.si`. Public DNS (Cloudflare, **DNS-only**), local DNS (Technitium, split-horizon).
- One wildcard `*.kogler.si` cert via Cloudflare DNS-01.
- **Internal = no public DNS record + WAN-block.**
- **Placement (HD-135 split):** the public/edge/GitOps/observability tier runs on the **VPS**; the GPU/LAN/storage-bound core runs on **oldsrv**. Subdomains/URLs are host-agnostic (unchanged by placement). See [`services-vps.md`](services-vps.md).

### Public (internet-facing via Traefik + Authentik) — the exceptions

The catalog above is the single list of subdomains; **only this subset** gets a Cloudflare record and a
WAN allow. Everything else in the catalog is **internal-only** (no public record, WAN-blocked; defense in depth).

| Subdomain | Service |
|-----------|---------|
| `kogler.si` (root) + `home` | Homepage — public, but behind Authentik Forward-Auth |
| `sso` | Authentik |
| `foto` | Immich |
| `file` | OpenCloud |
| `ai` | Open WebUI — AI chat/RAG, public, Authentik OIDC + crowdsec-only (HD-101) |
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
- **Public/edge/observability tier** — the public edge (Traefik/CrowdSec/Authentik), live-data apps (OpenCloud/Immich/Forgejo), AI stack, **observability backend** (Prometheus/Loki/Grafana), n8n, GitOps (Renovate), and edge accessories (Matrix/Headscale/Metabase/PairDrop/Stirling/renovate) run on the **VPS** ([`services-vps.md`](services-vps.md), HD-135); oldsrv avoids the public/edge workload
- **Office MCP bridges (Windows 11 clients)** — native per-client apps, **not** Docker services in this catalog; distributed server-side from a repo `client/office-bridge/` folder. See [`llm-office.md`](llm-office.md) (HD-106–111).
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
- **Owner = neutral shared owner `storage_uid`/`storage_gid` (`media`, 1005)** across all *arr containers
  (linuxserver `PUID/PGID={{ storage_uid }}`/`PGID={{ storage_gid }}`; Jellyfin `user: "{{ storage_uid }}:{{ storage_gid }}"`,
  HD-94/HD-131). SMB/NFS ownership on nas must match.
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
- [Personal Finance Stack](services-finance.md)
- [Deferred VPS Infrastructure](services-vps.md)
- [Docker Compose Specification](deployment-compose.md)
- [Service Subscriptions & Costs](subscription.md)