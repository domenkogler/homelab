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

> **Decision:** OIDC providers/applications are declared as an **Authentik Blueprint**; a
> **secret-egress glue** copies the generated client creds into 1Password. See
> [`services-authentik.md`](services-authentik.md) *OIDC client provisioning* for the decision.
> This section is the compose-side contract.

### Blueprint volume (authentik compose template)
The `authentik-server` service mounts a **`blueprints/`** volume (alongside the existing
`/templates`): Authentik applies the Blueprint idempotently at startup / on demand. The
`ks-oidc.yml` Blueprint declares the OIDC providers + applications for Open WebUI, Headscale,
Matrix (Tuwunel), OpenClaw, OpenCloud (native OIDC, multi-redirect), **Immich, Forgejo, Metabase**
(HD-148). Optionally the Authentik
**LDAP provider/outpost** (D7/HD-132) is also declared here, removing a manual UI create-step.

### Deploy ordering (in `vps.yml`)
Steps 2–4 map to the Ansible **Authentik pre-pass** (`roles/docker_services/tasks/prepass-authentik.yml`,
HD-162), which runs **before** the per-service deploy loop and is gated on `authentik` being in
`docker_services`. The loop (`deploy-service.yml`) additionally validates each rendered compose
file (`docker compose -f … validate`) before `up`. See
[`deployment-ansible.md`](deployment-ansible.md) §`docker_services`.

1. Deploy `authentik` (+ bundled pg/redis/ldap) — `docker compose up -d`.
2. **Apply the Blueprint** (`ks-oidc.yml`) — via Authentik API (`authentik-provision_api`) or the
   bundled blueprint on container start.
3. **Run the secret-egress glue** — for each declared provider, `GET /api/v3/core/providers/oauth2/`
   → seed the 1Password item (`openwebui_api`, `headscale_api`, `matrix_api`, `openclaw_api`,
   `opencloud_oidc`, `immich_oidc`, `forgejo_oidc`, `metabase_oidc`). (The OpenCloud Graph-API
   service account `opencloud-service_api` is NOT this glue's job — it is seeded by the
   `sync-authentik-users` rework, HD-145.)
4. Deploy the **OIDC consumers** — their compose `lookup()` now resolves real client creds.

Fail-closed (HD-65/91): the glue aborts loudly if `authentik-provision_api` is missing, rather than
rendering a consumer with an empty/placeholder OIDC secret.

### OpenCloud native-OIDC switch (HD-52)
For OpenCloud, native OIDC (desktop/mobile client) requires, in the `opencloud` compose:
- uncomment the `OC_OIDC_ISSUER` / `PROXY_OIDC_*` / `OC_EXCLUDE_RUN_SERVICES: idm` block;
- remove the `traefik.http.routers.opencloud.middlewares: authentik-forward-auth@file` label;
- add `sso.kogler.si` to OpenCloud `csp.yaml` `connect-src`/`frame-src`.
The Authentik provider itself is a **Blueprint entry** (multi-redirect web + desktop + mobile), so
no UI creation is needed.

### Immich native-OIDC note (HD-148)
Immich v3 mobile is OAuth-capable; its default mobile redirect is the custom scheme
`app.immich:///oauth-callback`. Per the official Immich OAuth docs (Authentik is first-class):

**Authentik client profile (confidential):** Provider type OIDC/OAuth2, **Confidential** client,
Application type **Web**, Grant type **Authorization Code** (no `implicit`). `issuer_url` =
`https://sso.kogler.si/application/o/immich/` (the `.well-known/openid-configuration` suffix is
auto-appended on discovery).

**Redirect URIs (Authentik provider `redirect_uris` must include all):**
- `app.immich:///oauth-callback` — **mobile** (MUST be present for iOS/Android)
- `https://foto.kogler.si/auth/login` — web login
- `https://foto.kogler.si/user-settings` — web manual OAuth link
- optional **Backchannel logout**: `https://foto.kogler.si/api/oauth/backchannel-logout`
For local debugging also allow `http://localhost:2283/auth/login` + `http://localhost:2283/user-settings`.

**Immich env/config (`immich_oidc` from 1Password):** `scope openid email profile`; claims
`preferred_username` → storage label, `immich_role` → role (`user`/`admin`), `immich_quota` →
storage quota (claims are creation-only, not re-synced); `Auto Register` true, optional `Auto Launch`
(per-request `/auth/login?autoLaunch=0|1`). `Mobile Redirect URI Override` empty → uses the custom scheme;
only set it if Authentik rejects the custom scheme (http(s)-forwarder workaround, deploy-verify).

**Edge changes in the `immich-app` compose:**
- add the config above (client creds from 1Password `immich_oidc`, issuer/scope/claims);
- **remove** the `traefik.http.routers.immich.middlewares: authentik-forward-auth@file` label
  (would block the mobile OAuth redirect).

### Forgejo / Metabase native-OIDC notes (HD-148)
- **Forgejo** (`git.`): callback `https://git.kogler.si/user/oauth2/<app-slug>/callback`; keep
  `crowdsec-only` edge; decide whether git-over-https/API pushes stay open or follow web SSO.
- **Metabase** (`sec.`): **Metabase OSS (`metabase/metabase:latest`) has NO OIDC/SSO — it is a
  paid Enterprise feature.** The `metabase_oidc` provider is declared (Blueprint) only for a
  future Enterprise license; with OSS the route **stays Forward-Auth** (free, works). If
  Enterprise is ever licensed: switch this route to `crowdsec-only` + enable `MB_OIDC_*`
  (single provider, `https://sec.kogler.si/auth/sso` callback).

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

> **Stale — HD-135/HD-151:** Immich now runs on the VPS with originals on the **live Hetzner Box** (CIFS) and
> the NAS datasets trimmed. Kept only as historical context; do not follow the mount paths below.

```yaml
services:
  immich-server:
    volumes:
      - /srv/docker/immich/upload:/data        # local NVMe: thumbs, encoded-video
      - /mnt/nas/data/immich:/data/library     # NFS originals (storage template on)
```

- Container-internal path changed from `/usr/src/app/upload` → `/data` (v3+).
- Enable **storage template** so originals go to `/data/library`.
- Bind-mount nas `tank/data/immich` → `/data/library` (only big write-once originals cross NFS).
- Postgres + Immich-ML model cache + ML embeddings (in DB) stay local — see [`storage.md`](storage.md).
- Face thumbnail files → `bulk/data/immich-thumbs` nightly (backed up); the rest of `thumbs/` regenerable.

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
  LDAP provider + outpost exist (preferably declared in the `ks-oidc.yml` Blueprint — see the
  *Authentik OIDC provisioning* section above), then seed `authentik-ldap_bind` before Samba
  ldapsam connects.


Auth tokens for internal services live in 1Password `Homelab` vault under the
`<service>-internal_api` naming pattern. Referenced via `lookup('community.general.onepassword', ...)` at template render time.