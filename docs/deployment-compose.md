---
title: Docker Compose Specification
role: generation-target
domain: deployment
status: active
tags: [deployment, docker, compose]
---
# Docker Compose Specification

> **Role:** ★ Generation target — read this to generate `docker-compose.yml` files for any homelab service.
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
| DNS (Technitium, Pi-hole) | `services-internal` |
| VPN (Headscale) | `traefik-public` |
| Backup (Kopia, DB Backup) | `services-internal` / `db-internal` |
| Dashboard (Homepage) | `traefik-public` |
| Dashboard (Metabase) | `traefik-public` **+** `services-internal` |
| Observe (Alloy) | host (`docker.sock`) + `services-internal` |
| Observe (Prometheus, Loki) | `db-internal` |
| Observe (Grafana) | `traefik-public` **+** `db-internal` (needs to query backends) |
| Observe (blackbox-exporter) | `services-internal` |
| Alert (n8n) | `services-internal` |
| CD (Doco-CD) | host network (needs `docker.sock`) |
| Update (Renovate) | `services-internal` |
| Stream (Sunshine) | `services-internal` |

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

Services that need GPU access: **Ollama, Immich-ML, Sunshine**.

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

See [`hardware-gpu.md`](hardware-gpu.md) for the GPU topology and VRAM strategy.

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
  POSTGRES_PASSWORD: "{{ lookup('community.general.onepassword', 'authentik_pg_password', vault='Homelab') }}"

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
      POSTGRES_PASSWORD: "{{ lookup('community.general.onepassword', '<service>_pg_password', vault='Homelab') }}"

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
      DB01_USER: "{{ lookup('community.general.onepassword', '<service>_db_user', vault='Homelab') }}"
      DB01_PASS: "{{ lookup('community.general.onepassword', '<service>_pg_password', vault='Homelab') }}"
      COMPRESSION: ZSTD
      RETENTION: "7"
    volumes:
      - db-backups:/backup
```

---

## Volume Strategy

- Named volumes for persistent data
- Bind mounts only where necessary (Docker socket, GPU devices, configs on host)
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