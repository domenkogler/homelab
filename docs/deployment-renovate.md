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

> **`renovate.json` must stay platform-agnostic — there is deliberately no `"platform"` key.**
> The platform comes exclusively from the compose env (`RENOVATE_PLATFORM: gitea`), and that is not
> cosmetic: the image pinned until 2026-10-08 was **35.10.0**, whose config parser rejects a
> `platform` key as an unknown platform (native Forgejo support arrived in ≥37). The pin is
> **44.133.0** since 2026-10-08, where a `platform` key WOULD be honoured — which is exactly why the
> rule now has to be stated instead of being enforced by an old parser. Setting it in both places
> guarantees a future disagreement; setting it in the file hands the run a platform the env also
> claims, and the compose one wins silently.
>
> **Why the fleet was nine majors behind:** Renovate here is pointed at `domen/test` (HD-264 tail), so
> nothing has ever opened a PR against this repo. The pins were refreshed by hand on 2026-10-08 — see
> §Manual pin refresh below. "Renovate keeps it current" is a true statement about the CONFIG and a
> false statement about the fleet until that pointer moves.

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
    },
    {
      "matchManagers": ["npm"],
      "stabilityDays": 3,
      "description": "The one npm-managed pin in the repo is the pi stack in group_vars/all/versions.yml (pi_host_*/pi_dev_*/pi_web_*) — it is an APPLICATION version, not a Docker base image, so §7's stabilityDays argument applies verbatim. `pi_host_web_npm_version` is exempt: the pi-web cockpit self-updates inside @beta from the phone, so pinning that string would break its own update path (HD-484)."
    }
  ],
  "fileMatch": {
    "jsonnet": ["**/*.jsonnet", "**/*.libsonnet"]
  }
}
```

---

## Manual pin refresh (what to do while HD-264 is open)

Until `RENOVATE_REPOSITORIES` names this repo, the Dependency Dashboard produces nothing here, so a
version refresh is a session task. Do it with the probe, not from memory:

```bash
python3 scripts/image-pin-probe.py --verify     # every *_version in versions.yml, per registry
```

It prints, per pin: the current value, the newest **stable** release at least `stabilityDays`
(3) old, the newest release of any kind, whether the CURRENT tag actually exists upstream, and
what it must NOT change (the digest-pinned `*_image` values, which carry their own certification).
Rules it encodes, and why each one exists:

* **3-day hold** — same rule as `stabilityDays` in the config above, so a hand refresh and a future
  Renovate PR agree; a release younger than that is reported as "newest any", not as a target.
* **prerelease/flavour filter** — `alpha`/`rc`/`nightly`/`dev`/`-snapshot`/`-enterprise` are not
  stable. This is what caught `signal_cli_rest_api_version` sitting on the upstream **dev channel**
  (`0.203-dev`) while stable was `0.101`, and `slskd` on a commit-suffixed nightly of an unreleased
  `0.26.1`.
* **existence probe** — a tag that 404s is a phantom pin. `db_backup_version: 4.1.100` and
  `sunshine_version: v2026.821.30050-ubuntu-24.04` both did: no gate can see this, because every
  gate renders the string and none asks the registry, and a host that already has the layer cached
  never finds out. This is the check the repo was missing.
* **official images** — Docker Hub push date is a *rebuild* date, so the release feed (GitHub)
  supplies the date for `library/*` instead.

Then: apply the values into `group_vars/all/versions.yml` (the SSOT), keep `*_image` digest pins
untouched, and put the deploy cost in the todo row — a data-format major (postgres 16 → 18,
RabbitMQ 3 → 4) is a migration, not a restart.

---

## Docker Compose

> SSOT is the rendered template
> [IaC/ansible/templates/docker_services/renovate/docker-compose.yml.j2](../IaC/ansible/templates/docker_services/renovate/docker-compose.yml.j2)
> — the block below mirrors it; if they disagree, the template wins.
>
> ⏳ **Status: enabled, pointed at the wrong repo on purpose.** `RENOVATE_REPOSITORIES` is still
> `domen/test` because **`domen/homelab` has never been migrated to Forgejo**. Flip it to `domen/homelab`
> when that repo lands (HD-264 tail).
> **Why this matters more than a typo:** with no target repo, Renovate 404s and **crash-loops** the
> container with "Repository has unknown error" — the service looks down but is really misconfigured, which
> is why the repo pointer and the token validity are the first two things to check.

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

## Run model & triggers (HD-264)

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