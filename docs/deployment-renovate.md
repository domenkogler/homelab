---
title: Renovate Bot — Update Lifecycle
role: detail
domain: deployment
status: active
tags: [deployment, renovate, updates]
---
# Renovate Bot — Update Lifecycle

> **Role:** Detail — Docker image version tracking, stability delay, PR automation.
> **Links to:** `deployment.md`
> **Linked from:** `deployment.md`, `index.md`

---

## How It Works

1. Renovate container runs on the **VPS** (co-located with Forgejo), scans `docker-compose.yml` files in repo
2. New upstream Docker image detected → **3-day hold** (stability delay)
3. After 3 days, update appears as checkbox on **Dependency Dashboard** (Forgejo Issue, auto-managed)
4. Domen reviews → checks the box
5. Renovate generates PR with version bump
6. Merge PR → **Forgejo Actions deploy button** (`workflow_dispatch`) → **Ansible** applies the image-tag bump (VPS + oldsrv, one path) → `docker compose up -d`

---

## Configuration (`renovate.json` at repo root)

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "platform": "forgejo",
  "dependencyDashboard": true,
  "dependencyDashboardAutoclose": false,
  "dependencyDashboardTitle": "Homelab Dependency Dashboard",
  "packageRules": [
    {
      "matchDatasources": ["docker"],
      "stabilityDays": 3
    },
    {
      "matchManagers": ["ansible-galaxy", "pip_requirements"],
      "stabilityDays": 3
    }
  ]
}
```

---

## Docker Compose

```yaml
services:
  renovate:
    image: ghcr.io/renovatebot/renovate:latest
    restart: unless-stopped
    environment:
      RENOVATE_PLATFORM: forgejo
      RENOVATE_ENDPOINT: https://git.kogler.si
      RENOVATE_TOKEN: ${FORGEJO_TOKEN}
      RENOVATE_REPOSITORIES: "domen/homelab"
      RENOVATE_ONBOARDING: "false"
    networks:
      - services-internal
```

---

## Full Lifecycle

```
Upstream Release
        │
        ▼ (Renovate detects new version)
  3-Day Stability Hold
        │
        ▼
  Dependency Dashboard (Forgejo Issue)
  □ immich: v1.120.0 → v1.122.1
        │
        ▼ (Domen checks box)
  Renovate creates PR
        │
        ▼ (Domen reviews, merges)
  Version committed to main branch
        │
        ▼ (Forgejo Actions deploy button → Ansible)
  docker compose pull && docker compose up -d
        │
        ▼ (Post-deploy hooks)
  Regenerate Homepage + inventory docs
```

---

## Scope

Renovate scans:
- `docker-compose.yml` files in the repo (Docker images)
- Custom Dockerfiles with `FROM` directives
- Docker Compose service image tags
- **Ansible Galaxy collections** (`IaC/ansible/requirements.yml`) — `community.*` pinned collections (HD-90 / KOPS-062)
- **Python `requirements.txt`** (`client/office-bridge/requirements.txt` + any future) (HD-90 / KOPS-062)

Does NOT scan:
- System packages (handled by `unattended-upgrades` on Debian)
- RouterOS firmware (manual check)
- The repo's build/test tools in `scripts/*.py` (no declared dependency manifest — the pip manager tracks `requirements*.txt` only)