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

> 2026-08-23: the `"platform"` key was REMOVED from `renovate.json` — the pinned
> renovate image (35.x) rejects it as an unknown platform (native forgejo support
> arrived ≥37); the platform comes exclusively from the compose env
> (`RENOVATE_PLATFORM: gitea`). Repo-side config must stay platform-agnostic.

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
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

> SSOT is the rendered template
> [IaC/ansible/templates/docker_services/renovate/docker-compose.yml.j2](../IaC/ansible/templates/docker_services/renovate/docker-compose.yml.j2)
> — the block below mirrors it as of 2026-08-24 (task 5).
>
> **Prerequisite / status:** Renovate was DISABLED (service `enabled: false` in group_vars) because the
> Forgejo instance had no repos and renovate 404'd → "Repository has unknown error" crash-loop. **Re-enabled
> 2026-08-24 (task 5):** `domen/test` exists (verified 200) but `domen/homelab` is not yet migrated, so
> `RENOVATE_REPOSITORIES` TEMPORARILY points at `domen/test` (compose env). Switch back to `domen/homelab`
> when that repo lands on Forgejo (owner). The playbook converge is OWNED by the other session — this repo
> change is a file-edit only. The token itself verified valid (200 as `domen`, 2026-08-23 debug one-shot).

```yaml
services:
  renovate:
    image: ghcr.io/renovatebot/renovate:{{ renovate_version }}  # pinned via group_vars/all/versions.yml
    restart: unless-stopped
    environment:
      RENOVATE_PLATFORM: gitea                       # forgejo value unsupported < image 37
      RENOVATE_ENDPOINT: http://forgejo:3000         # INTERNAL — public URL sits behind forward-auth
      RENOVATE_TOKEN: "{{ lookup('community.general.onepassword', 'forgejo_api', field='credential', vault=op_vault) }}"
      RENOVATE_REPOSITORIES: "domen/test"   # TEMPORARY — domen/homelab pending migration (task 5)
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

---

## Run model & triggers (HD-264 sandbox, 2026-08-26)

Renovate needs **no push webhook and no job scheduler** to detect updates — it **polls** the configured
repos on its own cadence (the renovate CLI is pull-based). Two things are therefore **optional**, NOT
required for correctness:
- A **push webhook** would only make detection *instant* after a push; it is not needed for Renovate to
  work.
- A `schedule`/cron (`RENOVATE_CRON` / `schedule` in config) only gates **when** runs are allowed
  (e.g. nightly, avoid work hours) to limit noisy PRs/CI churn — optional policy, not a correctness need.

**Container run-model (the actual fix for the exit-0 restart churn):** Renovate is a *run-once* image —
it does one pass then exits 0. Combined with `restart: unless-stopped` and no schedule, Docker restarts it
immediately → tight loop (`RestartCount=3392` live). Correct models: (a) long-running daemon/sidecar that
keeps sleeping between polls, (b) a systemd timer / cron that invokes it on a cadence, or (c) run-on-demand.
HD-264 (todo) builds a working model plus the `domen/test` sandbox; GitHub migration stays the LAST step.