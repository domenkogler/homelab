---
title: Docker Compose Specification
role: design-spec
domain: deployment
status: active
tags: [deployment, docker, compose]
---
# Docker Compose Specification

> **Role:** ★ Design spec — read this to **author or correct** `docker-compose.yml`
> files for any homelab service. Concrete values (networks, IPs, image tags) live
> in IaC (`group_vars/*.yml`, compose templates) and flow **IaC → docs** via the
> render — this file is the authoring guide, not a runtime input.
> **Links to:** `services.md`, `hardware-gpu.md`, `deployment-secrets.md`
> **Linked from:** `deployment.md`, `index.md`

---

## File Location Convention

```
IaC/ansible/templates/docker_services/<service>/
├── docker-compose.yml.j2              # Main compose (Jinja2 template)
└── <extra configs>                    # Service-specific files (traefik.yml, middlewares.yml, etc.)
```

Deployed to: `/opt/<service>/docker-compose.yml`

---

## Network Assignment

| Service Category | Network |
|-----------------|---------|
| Edge (Traefik, CrowdSec) | `traefik-public` |
| Identity (Authentik) | `traefik-public` + `services-internal` |
| Platform (OpenCloud, Immich, Forgejo) | `services-internal` |
| AI/LLM (Ollama, Immich-ML) | `services-internal` |
| DNS (Technitium, Pi-hole) | `traefik-public` + `services-internal` (Technitium web UI behind Traefik; Pi-hole ad-blocking behind Traefik) |
| VPN (Headscale) | `traefik-public` |
| Backup (Kopia, DB Backup) | `services-internal` / `db-internal` |
| Dashboard (Homepage) | `traefik-public` |
| Dashboard (Metabase) | `traefik-public` **+** `services-internal` |
| Observe (Alloy) | host (`docker.sock`) + `services-internal` |
| Observe (Prometheus, Loki) | `db-internal` |
| Observe (Grafana) | `traefik-public` **+** `db-internal` (needs to query backends) |
| Observe (blackbox-exporter) | `services-internal` |
| Observe logs viewer (Dozzle) | `traefik-public` (read-only `docker.sock`) |
| Alert (n8n) | `services-internal` |
| CD (Doco-CD) | host network (needs `docker.sock`) |
| Update (Renovate) | `services-internal` |
| Stream (Sunshine) | `services-internal` |
| Media/*arr UI (Jellyfin, Seerr, Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, SABnzbd, Profilarr) | `services-internal` + `traefik-public` |
| Media torrent VPN (gluetun; qBittorrent via `network_mode: service:gluetun`) | `traefik-public` + `services-internal` (shares gluetun namespace) |
| Media scheduled (Recyclarr) | `services-internal` |

---

## Shared Networks

```yaml
networks:
  traefik-public:
    external: true       # Created first by traefik compose
  services-internal:
    external: true
  db-internal:
    external: true
```

---

## GPU-Enabled Containers

Services that need GPU access: **Ollama, Immich-ML, Sunshine** (+ **Jellyfin** — iGPU transcode, not the AMD dGPU).

```yaml
services:
  ollama:
    devices:
      - /dev/dri:/dev/dri
      - /dev/kfd:/dev/kfd
    environment:
      OLLAMA_KEEP_ALIVE: 5m
    group_add:
      - "{{ gpu_render_gid }}"    # render group
      - "{{ gpu_video_gid }}"     # video group
```

### Jellyfin (iGPU transcode)

```yaml
services:
  jellyfin:
    devices:
      - /dev/dri:/dev/dri          # Intel HD 630 QuickSync
    group_add:
      - "{{ gpu_render_gid | default(104) }}"
      - "{{ gpu_video_gid | default(44) }}"
```

See [`hardware-gpu.md`](hardware-gpu.md) for the GPU topology and VRAM strategy.

### *arr / Media Stack Conventions

- **Images:** `linuxserver/*` for the *arr apps (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, SABnzbd,
  qBittorrent); Jellyfin official `jellyfin/jellyfin`; `seerr/seerr`; gluetun `qm12/gluetun`;
  Profilarr (`ghcr.io/dictionarry-hub/profilarr` + parser sidecar, Dictionarry-Hub, Deno-based v2); Recyclarr `ghcr.io/recyclarr/recyclarr`.
  `latest` tags, Renovate-tracked.
- **PUID/PGID:** all *arr containers run as **`1000:1000`** (domen) — linuxserver images via
  `PUID=1000`/`PGID=1000`, Jellyfin via `user: "1000:1000"`. NFS ownership on nas must match.
- **Storage:** media lives in a **single dataset** on the nas `bulk` pool — `bulk/media` → NFS export →
  oldsrv `/mnt/nas/media` (one filesystem → TRaSH hardlinks; **not backed up**, redownloadable):
  - Jellyfin: `/mnt/nas/media/media/...` **ro**
  - Sonarr/Radarr/Lidarr: library `/mnt/nas/media/media/<cat>` (rw — creates folders) + `downloads/complete/<cat>` (import)
  - SABnzbd / qBittorrent: `/mnt/nas/media/downloads` (rw)
  - Bazarr: library dirs (writes subtitles next to media)
  - `Use Hardlinks: ON` in Sonarr/Radarr/Lidarr
  - Full layout + dataset properties: [`storage-zfs.md`](storage-zfs.md)
- **Downloader egress:** only qBittorrent routes through gluetun:
  ```yaml
  services:
    gluetun:
      image: qm12/gluetun:latest
      cap_add: [NET_ADMIN]
      devices:
        - /dev/net/tun:/dev/net/tun
      environment:
        VPN_SERVICE_PROVIDER: privado
        VPN_TYPE: wireguard
        WIREGUARD_PRIVATE_KEY: "{{ lookup('community.general.onepassword', 'privado-vpn_api', field='credential', vault=op_vault) }}"
        SERVER_COUNTRIES: Netherlands
    qbittorrent:
      image: linuxserver/qbittorrent:latest
      network_mode: "service:gluetun"      # no own network — shares gluetun namespace
      depends_on: [gluetun]
  # gluetun must be on traefik-public + services-internal so the qBittorrent
  # web UI stays reachable via Traefik and Sonarr/Radarr can call its API.
  ```
  SABnzbd stays on the plain LAN (Eweka usenet is a licensed service).
- **Auth:** admin UIs behind `authentik-forward-auth@file` with built-in logins disabled;
  Jellyfin + Seerr use their own login (client apps / family portal).
- **Dozzle** is an observability viewer (all containers), not part of the *arr stack — see `observability.md`.

### Immich Hybrid Storage (originals on NAS, thumbs/ML local)

```yaml
services:
  immich-server:
    volumes:
      - immich-data:/usr/src/app/upload        # local NVMe: thumbs, encoded-video
      - /mnt/nas/data/immich:/usr/src/app/upload/library   # NFS originals (storage template on)
```

- `UPLOAD_LOCATION` = local NVMe; enable **storage template** so originals go to `upload/library`
- Bind-mount nas `tank/data/immich` → `upload/library` (only big write-once originals cross NFS)
- Postgres + Immich-ML model cache + ML embeddings (in DB) stay local — see [`storage-zfs.md`](storage-zfs.md)
- Face thumbnail files → `bulk/data/immich-thumbs` nightly (backed up); the rest of `thumbs/` regenerable

---

## Traefik Labels (Exposed Services)

Services exposed via Traefik must have labels:

```yaml
services:
  immich:
    labels:
      traefik.enable: "true"
      traefik.http.routers.immich.rule: "Host(`foto.kogler.si`)"
      traefik.http.routers.immich.entrypoints: websecure
      traefik.http.routers.immich.tls.certresolver: letsencrypt
      traefik.http.routers.immich.middlewares: authentik-forward-auth@file
    networks:
      - traefik-public
      - services-internal
```

Services NOT exposed publicly (databases, internal-only apps) have `traefik.enable: "false"` or no Traefik labels.

---

## Secret Resolution

Secrets come from 1Password at template render time. Never hardcode:

```yaml
# Good — resolved at Ansible template time
environment:
  POSTGRES_PASSWORD: "{{ lookup('community.general.onepassword', 'authentik_db', field='password', vault=op_vault) }}"

# Bad — never commit secrets
environment:
  POSTGRES_PASSWORD: "mysecretpassword123"
```

See [`deployment-secrets.md`](deployment-secrets.md) for the naming convention.

---

## Observability / TSDB Retention

- **Prometheus:** retention 30d, data on oldsrv local disk
- **Loki:** single-node/SSD, retention 14d, compaction on, filesystem/TSDB store
- **Grafana:** attached to **both** `traefik-public` + `db-internal`
- **Alloy:** host-installed (Ansible), mounts `docker.sock` for container logs
- **HA exporter:** HA exposes `/api/prometheus` (bearer token); Prometheus scrapes it — entities become metrics
- TSDB data is **regenerable, not backed up** (see `backup.md`); retention is deliberate

## Common Patterns

### Database Service
```yaml
services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    networks:
      - db-internal
    volumes:
      - postgres-data:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: "{{ lookup('community.general.onepassword', '<service>_db', field='password', vault=op_vault) }}"

volumes:
  postgres-data:
```

### Web Service with Traefik
```yaml
services:
  app:
    image: ghcr.io/org/app:latest
    restart: unless-stopped
    networks:
      - traefik-public
      - services-internal
    labels:
      traefik.enable: "true"
      traefik.http.routers.app.rule: "Host(`app.kogler.si`)"
      traefik.http.routers.app.entrypoints: websecure
      traefik.http.routers.app.tls.certresolver: letsencrypt
      traefik.http.routers.app.middlewares: authentik-forward-auth@file
```

### Periodic Task (DB Backup)
```yaml
services:
  db-backup:
    image: tiredofit/db-backup:latest
    restart: unless-stopped
    networks:
      - db-internal
    environment:
      DB01_TYPE: postgresql
      DB01_HOST: postgres
      DB01_PORT: "5432"
      DB01_USER: "{{ lookup('community.general.onepassword', '<service>_db', field='username', vault=op_vault) }}"
      DB01_PASS: "{{ lookup('community.general.onepassword', '<service>_db', field='password', vault=op_vault) }}"
      COMPRESSION: ZSTD
      RETENTION: "7"
    volumes:
      - db-backups:/backup
```

---

## Volume Strategy

- **Stateful service data = bind mounts** under `/srv/docker/<svc>` on the oldsrv `nvme` ZFS pool —
  each dir is its own dataset (per-service recordsize/snapshots) and backup jobs + Kopia get clean host
  paths. Ownership `1000:1000` (domen) where the app expects it (see *arr conventions).
- Named volumes only for truly ephemeral/utility caches — never for anything that is backed up
- Bind mounts for host resources (Docker socket, GPU devices)
- No anonymous volumes

---

## Restart Policy

| Service Type | Policy |
|-------------|--------|
| Always-on (24/7) | `restart: unless-stopped` |
| AI/LLM | `restart: always` (must start at boot before login) |
| Manual-only (Sunshine) | `restart: "no"` |

---

## Container Security

```yaml
services:
  app:
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE    # Only if needed
    read_only: true         # Immutable containers where possible
    tmpfs:
      - /tmp
```