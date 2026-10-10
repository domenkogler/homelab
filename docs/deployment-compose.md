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
| Office editor (ONLYOFFICE Docs — WOPI helper for OpenCloud) | `traefik-public` (only; no auth surface, no user identity) |
| AI/LLM (Ollama → `llm-backend`; Immich-ML, LiteLLM, Docling, OpenClaw) | `services-internal`; Ollama on **`llm-backend`** (isolated, reachable only by LiteLLM). The **Vulkan tier joins that same isolation on purpose**: `whisper`, `reranker`, `embed` are `llm-backend`-only with **no `ports:` and no Traefik labels** — their APIs have no auth, so the network is the boundary and only LiteLLM may speak to them |
| AI coding harness (pi-dev, DSH) | `services-internal` (LiteLLM reach for models + Forgejo for PRs). DSH WebUI = **Pattern-A tailnet serve** (loopback :3080, netns sidecar, NO socat bridge; never on `services-internal`). pi = TUI/CLI (no web port). Each consumes scoped LiteLLM key + PR-only Forgejo token. |
| DNS (Technitium, Pi-hole) | `traefik-public` + `services-internal` (Technitium web UI behind Traefik; Pi-hole ad-blocking behind Traefik) |
| VPN (Headscale) | `traefik-public` |
| Backup (Kopia, DB Backup) | `services-internal` / `db-internal` |
| Dashboard (Homepage) | `traefik-public` |
| Observe (Alloy) | host (`docker.sock`) + `services-internal` |
| Observe (VictoriaMetrics, VictoriaLogs) | `db-internal` |
| Observe (Grafana) | `traefik-public` **+** `db-internal` (needs to query backends) |
| Observe (blackbox-exporter) | `services-internal` |
| Observe logs viewer (Dozzle) | `traefik-public` (read-only `docker.sock`) · on the **VPS** |
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

> The Blueprint + secret-egress-glue contract, deploy ordering, and the per-service native-OIDC recipes live in **[`deployment-oidc.md`](deployment-oidc.md)**. This doc stays pure compose conventions.

---

## GPU-Enabled Containers

Services that need GPU access on oldsrv: **the pinned AI tier** (embed / rerank / STT on the Vulkan runtime), **Immich-ML** and **Sunshine** — all on the AMD RX 7600 dGPU — plus **Jellyfin**, which transcodes on the Intel HD 630 **iGPU**, not the dGPU. There is no general LLM runtime on this box: generation lives on spark. Immich-ML bundles its own ROCm runtime and needs only `/dev/dri` + `/dev/kfd`.

```yaml
services:
  immich-ml:
    devices:
      - /dev/dri:/dev/dri
      - /dev/kfd:/dev/kfd
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
  (upstream);
  Profilarr (`ghcr.io/dictionarry-hub/profilarr` + parser sidecar, Dictionarry-Hub, Deno-based v2); Recyclarr `ghcr.io/recyclarr/recyclarr`.
  All pinned via `*_version` vars in `group_vars/all/versions.yml` (registry-verified,
  Renovate-tracked); the only `latest` left is Profilarr (no versioned tags upstream —
  documented fluid exception) and tuwunel (MUST-pin).
- **PUID/PGID:** all filesystem/SMB-backed containers (the *arr stack, qBittorrent) run as the
  **neutral shared owner `storage_uid`/`storage_gid` = `1005` (`media`)** — linuxserver images via
  `PUID={{ storage_uid }}`/`PGID={{ storage_gid }}`, Jellyfin/OpenCloud via `user: "{{ storage_uid }}:{{ storage_gid }}"`.
  NFS/SMB ownership on nas must match. **Immich originals are NOT S3-backed — they live on
  the live Hetzner Box (CIFS) via the Immich storage template;**
  so Immich's container user is not the shared-files owner for originals.
- **Storage:** media lives in a **single dataset** on the nas `bulk` pool — `bulk/media` → NFS export →
  oldsrv `/mnt/nas/media` (one filesystem → TRaSH hardlinks; **not backed up**, redownloadable):
  - Jellyfin: `/mnt/nas/media/media/...` **ro**
  - Sonarr/Radarr/Lidarr: library `/mnt/nas/media/media/<cat>` (rw — creates folders) + `downloads/complete/<cat>` (import)
  - SABnzbd / qBittorrent: `/mnt/nas/media/downloads` (rw)
  - Bazarr: library dirs (writes subtitles next to media)
  - `Use Hardlinks: ON` in Sonarr/Radarr/Lidarr
  - Full layout + dataset properties: [`storage.md`](storage.md)
- **Downloader egress:** only qBittorrent routes through gluetun. gluetun runs the `custom` WireGuard provider (upstream gluetun has no `privado` provider); the endpoint/address config is non-secret and comes from `group_vars/home_servers.yml` (`privado_vpn_*`), the client private key from 1Password:
  ```yaml
  services:
    gluetun:
      image: qmcgaw/gluetun:{{ gluetun_version }}   # upstream image
      cap_add: [NET_ADMIN]
      devices:
        - /dev/net/tun:/dev/net/tun
      environment:
        VPN_SERVICE_PROVIDER: custom        # no `privado` provider upstream
        VPN_TYPE: wireguard
        WIREGUARD_ENDPOINT_IP: "{{ privado_vpn_endpoint_ip }}"
        WIREGUARD_ENDPOINT_PORT: "{{ privado_vpn_endpoint_port }}"
        WIREGUARD_PUBLIC_KEY: "{{ privado_vpn_public_key }}"
        WIREGUARD_PRIVATE_KEY: "{{ vault['privado-vpn_api'].credential | replace('$','$$') }}"
        WIREGUARD_ADDRESSES: "{{ privado_vpn_address }}/{{ privado_vpn_cidr }}"
    qbittorrent:
      image: linuxserver/qbittorrent:{{ qbittorrent_version }}
      network_mode: "service:gluetun"      # no own network — shares gluetun namespace
      depends_on: [gluetun]
  # gluetun must be on traefik-public + services-internal so the qBittorrent
  # web UI stays reachable via Traefik and Sonarr/Radarr can call its API.
  ```
  SABnzbd stays on the plain LAN (Eweka usenet is a licensed service).
- **Auth:** admin UIs behind `authentik-forward-auth@file` with built-in logins disabled;
  Jellyfin + Seerr use their own login (client apps / family portal).
- **Dozzle** is an observability viewer (all containers), not part of the *arr stack — see `observability.md`. Runs on the **VPS** so log viewing is independent of home hosts.

### Immich (v3) — Server + Postgres + Valkey (microservices merged into server)

Immich v3 uses its own Postgres image (`ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`)
and Valkey (`docker.io/valkey/valkey:9`) instead of Redis. Microservices are merged into the server
container — no separate `immich-microservices` service needed.

## Template Jinja pitfalls (compose) — every one bites a live container

1. **Jinja evaluates expressions inside YAML COMMENTS.** A header line like
   `# Secrets via {{ lookup('community.general.onepassword', '...', vault=op_vault) }}` EXECUTES the
   lookup at render and fails on the literal item name. Keep comments expression-free — a `#` comment
   that merely quotes an app's Jinja expression (n8n's `$env.SIGNAL_*` written WITH braces) kills the
   render with `Syntax error in template: unexpected char '$'` and takes the whole VPS
   `docker_services` converge with it. Prose about a Jinja expression must be written WITHOUT the
   braces, and `validate-docker-services.py` (run by `validate-all.sh`, renders every compose template
   in ~0.5 s) catches exactly this — **run it after touching any template, not only before the commit.**
2. **Indented block tags + `trim_blocks` glue indentation.** An indented
   `      {% if ... %}` / `{% endif %}` pair collapses to its leading spaces merged onto the next
   content line (+6 indent per tag), producing invalid YAML. Rule: block tags at column 0 only;
   conditional label lines use the single-line form
   `{{ 'key: value' if (cond) else '# fallback comment' }}`.
3. **`${VAR}` interpolation does NOT read `services.environment`.** docker compose resolves it from
   shell env / project `.env` only, so plain `docker compose config` validation aborts on required
   vars (`${KOPIA_SERVER_USER:?...}`). When a command needs interpolation values, render an extra
   `.env.j2` (registered in `_extra_templates`, note the leading dot) next to the compose file
   (kopia-server/agent precedent); the `:?` guards stay fail-loud.

---

## Extra Config Templates — render + restart-on-change

Extras registered in `_extra_templates` (docker_services role defaults) are rendered per service by
deploy-service.yml and are BIND-MOUNTED into the containers. Two consequences:

1. **`docker compose up -d` does NOT see content changes** of bind-mounted files — it recreates on
   container-spec changes only. deploy-service.yml therefore registers the render task's result and
   runs a guarded post-up restart (`docker_compose_v2: state: restarted`) for that ONE service when a
   non-`.env` extra actually changed. Idempotent converges never fire it; first boot is safe (`up`
   created the containers moments earlier).
2. **Exclusions are semantic, not arbitrary:** `.env.j2` extras (kopia-server/agent) feed compose
   `${}` interpolation, where a change IS a spec change and `up -d` already recreated — restarting
   again would be a double bounce. `traefik` / `traefik-ha` dynamic files sit in the file-provider
   watch dir and hot-reload in-process; restarting Traefik would only drop edge traffic. VictoriaMetrics
   (and VictoriaLogs) is restarted deliberately: its config churn costs one short gap, while the HTTP
   auth (basic auth via victoria-metrics_api/victoria-logs_api) is read at startup only.

If a future extra must NOT trigger this restart, extend the guard's exclusion list in
deploy-service.yml rather than bypassing the render registration.

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

- **VictoriaMetrics:** retention 365d (metrics, pure storage), `db-internal`
- **VictoriaLogs:** retention 90d (logs), `db-internal`
- **Grafana:** attached to **both** `traefik-public` + `db-internal`
- **Alloy:** host-installed (Ansible), mounts `docker.sock` for container logs; **the single scrape tier** (topology B)
- **HA exporter:** HA exposes `/api/prometheus` (bearer token); Alloy scrapes it — entities become metrics
- TSDB data is **Kopia-backed** (VM/VL volumes, see `backup.md`); retention is deliberate (365d/90d)

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
  paths. Ownership `storage_uid`/`storage_gid` (`media`, 1005) where the app expects it (see *arr conventions).
- Named volumes only for truly ephemeral/utility caches — never for anything that is backed up
- Bind mounts for host resources (Docker socket, GPU devices)
- No anonymous volumes

**Documented exceptions:**

- `technitium` binds `/opt/technitium/config` instead of `/srv/docker/technitium` — the template renders
  BOTH the oldsrv primary and the Pi secondary, and the Pi has no oldsrv-style `/srv/docker` ZFS dataset
  layout; Kopia covers `/opt/*`, so backup coverage is intact. Revisit only if per-host state paths are
  ever introduced.
- `victoria-metrics` keeps its TSDB in the host bind `/srv/docker/victoria-metrics/data` — **Kopia-backed**
  (see `backup.md`), growth bounded by 365d retention.

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

> **`read_only` is NOT universal — drop it where the image's startup writes.**
> The hardening default above is the target, but the following image families **cannot** run `read_only: true`
> without crash-looping:
> - **linuxserver s6-overlay images** (`linuxserver/*`): s6 init writes `/run/s6` + `/config` as root before
>   the PUID drop → drop `read_only`, keep `cap_drop: ALL` + `tmpfs: /run:exec` + `cap_add SETGID/SETUID`
>   (sonarr/radarr/qbittorrent precedent — the *arr templates carry the inline note).
>   ⚠ **`/run:exec` is not optional for ANY s6 image**: docker's default tmpfs options are `noexec`, so
>   stage0 cannot exec `/run/s6/basedir/bin/init` and the container restart-loops on **exit 126**
>   (`/run/s6/basedir/bin/init: Permission denied`) whenever the tmpfs is a plain `- /run`.
>   **Do not over-apply this exception**: the exemption is `linuxserver/*`-specific, not
>   "s6"-general — a stock s6-overlay image (verified with `rustdesk/rustdesk-server-s6:1.1.16`) runs
>   `read_only: true` + `cap_drop: ALL` + `tmpfs: /tmp, /run:exec` with no `cap_add` at all.
>   ⚠ **`cap_drop: ALL` also removes `CAP_CHOWN`, and the linuxserver images need it**. Their init
>   `chown`s `/run/<app>-temp` to the PUID before dropping privileges; without that capability the chown fails
>   (`chown: changing ownership of '/run/radarr-temp': Operation not permitted`, followed by the image's own
>   "**** Permissions could not be set ****" warning) and the directory stays `root:root 0755` while the app
>   runs as uid 1005. For the ASP.NET-family apps (Sonarr/Radarr/Lidarr/Prowlarr) that directory is `TMPDIR`,
>   and `Path.GetTempFileName()` is how ASP.NET Core DataProtection persists its **cookie-signing key ring** —
>   so the app starts, answers its API, and cannot issue a session cookie it can later read: **every login
>   bounces back to `/login`** with `KeyRingProvider: An error occurred while reading the key ring` in the log.
>   It looks exactly like a lost password and is not one. Fix by mounting that one path as its own tmpfs
>   (`- /run/<app>-temp:mode=1777,exec` — verified to land as `drwxrwxrwt`), **not** by handing `CAP_CHOWN`
>   back: that capability would let the container's root chown files on the `/media` and `/downloads` binds.
> - **Images whose entrypoint ends in `setpriv`/`su-exec`** (signal-cli-rest-api, profilarr): need
>   `cap_add CHOWN,SETGID,SETUID` (privilege-drop) and, where a helper persists into a uid-owned volume
>   (signal-cli `jsonrpc2-helper`), also `DAC_OVERRIDE,FOWNER`.
> - **Images with a real data dir ≠ the mounted path** (actual-budget: `/data` owned by uid 1001, NOT
>   `/app/data`): mount the correct target + `bind_owner_uid`/`bind_dirs` on the docker_services entry
>   (deploy-service.yml Class-A pre-create).
> - **kopia image**: entrypoint is `/bin/kopia` (clear with `entrypoint: []` before a `command: sh -c`);
>   needs writable `/app/logs`. **TLS:** `kopia repository connect server`
>   in 0.23.x hard-requires `https://` (no client-side `--insecure`) — the server serves a PERSISTED
>   self-signed cert (`--tls-cert-file`/`--tls-key-file`, generated once under
>   `/srv/docker/kopia-server/config/`) and the agent pins its stable SHA-256 fingerprint
>   (`--server-cert-fingerprint`, 1P `kopia-server_fingerprint`). kopia's own `--tls-generate-cert`
>   (in-memory) would change the fingerprint on every restart — never use it here.

### Internal Service Authentication

Even trusted containers on shared Docker networks should have independent auth. A supply-chain
compromise in one public image gives the attacker free rein across the entire bridge network if
sibling services have no auth. Apply minimum auth per service:

- **Services accepting API requests:** require token/key/header where the service supports it (n8n API key). **Ollama has NO native server auth** (`OLLAMA_AUTH_*` applies only to ollama.com cloud, not the local API) — the control instead is **network isolation**: Ollama sits on the dedicated **`llm-backend`** overlay reachable only by LiteLLM, not `services-internal`.
- **Backup servers:** always require server auth. **Kopia uses `--htpasswd-file`** (the server has **no `--password` flag** — `--password`/`--without-password` are repo/at-rest vs network concerns). Kopia's htpasswd parser accepts plaintext `user:password` (0600); secret = `kopia-server-internal_api`. Never `--without-password`.
- **VictoriaMetrics / VictoriaLogs:** protect the HTTP endpoints — their own `-httpAuth.username`/
  `-httpAuth.password` (plaintext basic auth) via `victoria-metrics_api`/`victoria-logs_api`;
  endpoints stay loopback + wg-s2s-bound.
- **Grafana:** disable built-in login form (`GF_AUTH_DISABLE_LOGIN_FORM: "true"`) to force single path through Authentik proxy
- **Expiry-bearing infra tokens:** a token is non-expiring by design or named in a rotation runbook at the moment it is minted — an expiring token with no rotator decays silently while every gate stays green (the runbook index is [deployment-secrets.md](deployment-secrets.md))

#### Sibling-auth coverage map

Every **data-writing `services-internal` sibling** carries per-service token/header auth, or a
documented network-isolation decision — so a supply-chain compromise in any public image on the
overlay can't write to a sibling. Cross-host reaches (`immich-app→immich-ml`,
`n8n→signal-cli`) traverse the WG tunnel; the token is enforced at the **receiving** service.

| Pair (writer → receiver) | Host(s) | Auth mechanism | 1Password item | Status |
|---|---|---|---|---|
| n8n → signal-cli | VPS → oldsrv (WG) | `X-Api-Key` (`SIGNAL_CLI_API_TOKEN`) | `signal-internal_api` | ✅ |
| backup clients → kopia | VPS (WG) | `--htpasswd-file` Basic | `kopia-server-internal_api` | ✅ |
| VictoriaMetrics/VictoriaLogs auth | VPS | `-httpAuth` plaintext basic auth | `victoria-metrics_api` / `victoria-logs_api` | ✅ |
| litellm → ollama | VPS → oldsrv (WG) | **network isolation** (`llm-backend`, no native auth) | — | ✅ |
| open-webui / openclaw → litellm | VPS | `LITELLM_MASTER_KEY` bearer | `litellm_api` | ✅ |
| openclaw → opencloud (WebDAV) | VPS | OpenCloud **app-specific password** (scoped service user) | `openclaw-opencloud_api` | ✅ |
| immich-app → immich-ml | VPS → oldsrv (WG) | native ML **API-key header** | `immich-ml-internal_api` | ✅ live-verified 2026-09-08 |
| renovate → forgejo API | VPS | `RENOVATE_TOKEN` | `forgejo_api` | ✅ |
| recyclarr → sonarr/radarr | oldsrv | API key | `sonarr_api` / `radarr_api` | ✅ |
| db-backup → postgres (immich/opencloud/forgejo) | VPS | postgres password (`db-internal`) | `*_db` | ✅ |
| opencloud ↔ onlyoffice-docs (WOPI) | VPS | shared JWT (`COLLABORATION_JWT_SECRET`) | `opencloud-collab_password` | ✅ |

Deliberate isolation decisions (accepted, not gaps): **Ollama** (no native server auth → stays on
`llm-backend`, reachable only by LiteLLM) and **docling** (no supported API key → see
`services-ai.md`; treated like Ollama). *Cross-ref: `security.md` §6a Internal sibling auth.*

⚠ **Retiring a compose service does not stop its container, and a green converge hides that.**
`docker_compose_v2` never passes `--remove-orphans`, so deleting a service block re-renders the file,
brings the stack up, and leaves the old container RUNNING — the only trace is a task-level warning
(`Found orphan containers (<name>) for this project`) that reads like trivia. Removal is a
second act on the host: `docker compose -f /opt/<service>/docker-compose.yml up -d --remove-orphans`,
and the flag belongs AFTER `up` (`docker compose --remove-orphans up` fails with `unknown flag`).
Prove removal with `docker ps -a --format '{{.Names}}' | grep -c <name>` → 0, never with the
playbook recap. `authentik-ldap` and the `storage_samba_passdb` / `storage_samba_ldap` vars are
**deleted, not defaulted** — NAS SMB auth is local **tdbsam**
([storage-rejected.md](storage-rejected.md) row *Authentik LDAP outpost as the Samba passdb (ldapsam)*).

Auth tokens for internal services live in 1Password `Homelab-ansible` vault under the
`<service>-internal_api` naming pattern. Referenced via `lookup('community.general.onepassword', ...)` at template render time.
