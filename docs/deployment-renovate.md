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

1. Renovate container runs on oldsrv, scans `docker-compose.yml` files in repo
2. New upstream Docker image detected → **3-day hold** (stability delay)
3. After 3 days, update appears as checkbox on **Dependency Dashboard** (Forgejo Issue, auto-managed)
4. Domen reviews → checks the box
5. Renovate generates PR with version bump
6. Merge PR → Doco-CD auto-deploys

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
        ▼ (Doco-CD detects new commit)
  docker compose pull && docker compose up -d
        │
        ▼ (Post-deploy hooks)
  Regenerate Homepage + inventory docs
```

---

## Scope

Renovate scans:
- `docker-compose.yml` files in the repo
- Custom Dockerfiles with `FROM` directives
- Docker Compose service image tags

Does NOT scan:
- System packages (handled by `unattended-upgrades` on Debian)
- Ansible Galaxy roles (manually updated)
- RouterOS firmware (manual check)