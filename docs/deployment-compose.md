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
> **Links to:** `services.md`, `hardware-gpu.md`, `deployment-secrets.md`, `deployment-oidc.md`
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
| Office editor (ONLYOFFICE Docs — WOPI helper for OpenCloud, HD-166) | `traefik-public` (only; no auth surface, no user identity) |
| AI/LLM (Ollama → `llm-backend`; Immich-ML, LiteLLM, Docling, OpenClaw) | `services-internal`; Ollama on **`llm-backend`** (isolated, reachable only by LiteLLM — HD-59) |
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
| CD (Ansible via Forgejo Actions) | host SSH (no Docker-socket agent) |
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

## Authentik OIDC provisioning — Blueprint + secret-egress glue

> Moved to **[`deployment-oidc.md`](deployment-oidc.md)** (HD-199 split): the Blueprint + secret-egress-glue contract, deploy ordering, and the per-service native-OIDC recipes live there. This doc stays pure compose conventions.

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
  qBittorrent); Jellyfin official `jellyfin/jellyfin`; `seerr/seerr`; gluetun `qmcgaw/gluetun`
  (upstream — the former `qm12` fork no longer exists, HD-192);
  Profilarr (`ghcr.io/dictionarry-hub/profilarr` + parser sidecar, Dictionarry-Hub, Deno-based v2); Recyclarr `ghcr.io/recyclarr/recyclarr`.
  All pinned via `*_version` vars in `group_vars/all/versions.yml` (HD-192, registry-verified
  2026-08-21) + Renovate-tracked; the only `latest` left is Profilarr (no versioned tags upstream —
  documented fluid exception) and tuwunel (MUST-pin precedent, HD-121).
- **PUID/PGID:** all filesystem/SMB-backed containers (the *arr stack, qBittorrent) run as the
  **neutral shared owner `storage_uid`/`storage_gid` = `1005` (`media`)** — linuxserver images via
  `PUID={{ storage_uid }}`/`PGID={{ storage_gid }}`, Jellyfin/OpenCloud via `user: "{{ storage_uid }}:{{ storage_gid }}"`.
  NFS/SMB ownership on nas must match (HD-94/HD-131). **Immich originals are NOT S3-backed — they live on
  the live Hetzner Box (CIFS) via the Immich storage template (HD-135);**
  so Immich's container user is not the shared-files owner for originals.
- **Storage:** media lives in a **single dataset** on the nas `bulk` pool — `bulk/media` → NFS export →
  oldsrv `/mnt/nas/media` (one filesystem → TRaSH hardlinks; **not backed up**, redownloadable):
  - Jellyfin: `/mnt/nas/media/media/...` **ro**
  - Sonarr/Radarr/Lidarr: library `/mnt/nas/media/media/<cat>` (rw — creates folders) + `downloads/complete/<cat>` (import)
  - SABnzbd / qBittorrent: `/mnt/nas/media/downloads` (rw)
  - Bazarr: library dirs (writes subtitles next to media)
  - `Use Hardlinks: ON` in Sonarr/Radarr/Lidarr
  - Full layout + dataset properties: [`storage.md`](storage.md)
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

### Immich (v3) — Server + Postgres + Valkey (microservices merged into server)

Immich v3 uses its own Postgres image (`ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`)
and Valkey (`docker.io/valkey/valkey:9`) instead of Redis. Microservices are merged into the server
container — no separate `immich-microservices` service needed.

### Immich Hybrid Storage (originals on NAS, thumbs/ML local)  *(superseded 2026-08-18)*

> Superseded by **HD-135** (VPS era): Immich app + DB + thumbs run on the **VPS**, originals + encoded-video
> on the **live Hetzner Box** (CIFS), ML offloaded to oldsrv — layout in [`storage.md`](storage.md), decision
> history in [changelog.md](../changelog.md) (HD-135/HD-151). The old NAS-NFS mount plan lives in git history.

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
  paths. Ownership `storage_uid`/`storage_gid` (`media`, 1005) where the app expects it (see *arr conventions; HD-94).
- Named volumes only for truly ephemeral/utility caches — never for anything that is backed up
- Bind mounts for host resources (Docker socket, GPU devices)
- No anonymous volumes

**Documented exceptions (HD-200 / audit D10):**

- `technitium` binds `/opt/technitium/config` instead of `/srv/docker/technitium` — the template renders
  BOTH the oldsrv primary and the Pi secondary, and the Pi has no oldsrv-style `/srv/docker` ZFS dataset
  layout; Kopia covers `/opt/*`, so backup coverage is intact. Revisit only if per-host state paths are
  ever introduced.
- `prometheus` keeps its TSDB in the named volume `prometheus-data` — regenerable data (scrape/
  remote_write sources re-send after loss), deliberately NOT backed up ([backup.md](backup.md)), growth
  bounded by 30d retention. That places it on the ephemeral/utility side of the named-volume rule, not
  the stateful/backed-up side.

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

### Internal Service Authentication

Even trusted containers on shared Docker networks should have independent auth. A supply-chain
compromise in one public image gives the attacker free rein across the entire bridge network if
sibling services have no auth. Apply minimum auth per service:

- **Services accepting API requests:** require token/key/header where the service supports it (n8n API key). **Ollama has NO native server auth** (`OLLAMA_AUTH_*` applies only to ollama.com cloud, not the local API) — the control instead is **network isolation**: Ollama sits on the dedicated **`llm-backend`** overlay reachable only by LiteLLM (HD-59), not `services-internal`.
- **Backup servers:** always require server auth. **Kopia uses `--htpasswd-file`** (the server has **no `--password` flag** — `--password`/`--without-password` are repo/at-rest vs network concerns). Kopia's htpasswd parser accepts plaintext `user:password` (0600); secret = `kopia-server-internal_api`. Never `--without-password` (HD-59).
- **Observability UIs:** protect scrape/config endpoints — Prometheus `--web.config.file` with **bcrypt** `basic_auth_users` (`prometheus-internal_api`; hash via `scripts/gen-htpasswd.py`); endpoint stays loopback-only (HD-62) (HD-59).
- **Grafana:** disable built-in login form (`GF_AUTH_DISABLE_LOGIN_FORM: "true"`) to force single path through Authentik proxy
- **Grafana:** disable built-in login form (`GF_AUTH_DISABLE_LOGIN_FORM: "true"`) to force single path through Authentik proxy

#### Sibling-auth coverage map (HD-160)

Every **data-writing `services-internal` sibling** carries per-service token/header auth, or a
documented network-isolation decision — so a supply-chain compromise in any public image on the
overlay can't write to a sibling (extends HD-59). Cross-host reaches (`immich-app→immich-ml`,
`n8n→signal-cli`) traverse the WG tunnel; the token is enforced at the **receiving** service.

| Pair (writer → receiver) | Host(s) | Auth mechanism | 1Password item | Status |
|---|---|---|---|---|
| n8n → signal-cli | VPS → oldsrv (WG) | `X-Api-Key` (`SIGNAL_CLI_API_TOKEN`) | `signal-internal_api` | ✅ HD-125 |
| backup clients → kopia | VPS (WG) | `--htpasswd-file` Basic | `kopia-server-internal_api` | ✅ HD-59 |
| grafana/alloy → prometheus | VPS | `--web.config.file` bcrypt | `prometheus-internal_api` | ✅ HD-59 |
| litellm → ollama | VPS → oldsrv (WG) | **network isolation** (`llm-backend`, no native auth) | — | ✅ HD-59 |
| open-webui / openclaw → litellm | VPS | `LITELLM_MASTER_KEY` bearer | `litellm_master_key` | ✅ HD-100 |
| openclaw → opencloud (WebDAV) | VPS | OpenCloud **app-specific password** (scoped service user) | `openclaw-opencloud_api` | ✅ IaC (HD-160) |
| immich-app → immich-ml | VPS → oldsrv (WG) | native ML **API-key header** | `immich-ml-internal_api` | ✅ IaC (HD-160) |
| renovate → forgejo API | VPS | `RENOVATE_TOKEN` | `forgejo_api` | ✅ |
| recyclarr → sonarr/radarr | oldsrv | API key | `sonarr_api` / `radarr_api` | ✅ |
| db-backup → postgres (immich/opencloud/forgejo) | VPS | postgres password (`db-internal`) | `*_db` | ✅ |
| opencloud ↔ onlyoffice-docs (WOPI) | VPS | shared JWT (`COLLABORATION_JWT_SECRET`) | `opencloud-collab_password` | ✅ HD-166 |

Deliberate isolation decisions (accepted, not gaps): **Ollama** (no native server auth → stays on
`llm-backend`, reachable only by LiteLLM, HD-59) and **docling** (no supported API key → see
`services-ai.md`; treated like Ollama). *Cross-ref: `security.md` HD-160 block.*

#### Samba ↔ Authentik-as-LDAP (D7 / HD-132) — the pull contract
- **Samba authenticates against Authentik as an LDAP provider** (`passdb backend = ldapsam`);
  **Authentik is the SSOT and does NOT push.** No password is replicated/synced to the NAS.
- **Effect:** a user changes their own password in the Authentik self-service
  portal and the **next Samba bind (pull) reads it** — no admin step, no sync.
- **Nothing in Ansible/glue writes a local Samba password** — we deliberately removed the old
  `smbpasswd -a` provisioning (D5). Writing a local password would shadow/overwrite the LDAP
  credential and break self-service; there is no such task anywhere.
- **Dependency/trade-off:** because Samba pulls live from the LDAP outpost, if Authentik or its
  `ak-outpost-ldap` is down, family drives cannot mount (no local fallback). Accepted D7 trade-off;
  if outage resilience is ever required, revisit (LDAP replica cache / local fallback).
- Bind/base DN are **design constants** in `storage_samba_ldap` (storage role); the **bind
  password** is the secret `authentik-ldap_bind` (1Password). Deploy order: ensure the Authentik
  LDAP provider + outpost exist (preferably declared in the `ks-oidc.yml` Blueprint — see
  [`deployment-oidc.md`](deployment-oidc.md)), then seed `authentik-ldap_bind` before Samba
  ldapsam connects.


Auth tokens for internal services live in 1Password `Homelab-ansible` vault under the
`<service>-internal_api` naming pattern. Referenced via `lookup('community.general.onepassword', ...)` at template render time.