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
> cosmetic: at the current pin (**44.133.0**, `group_vars/all/versions.yml`) Renovate honours a
> `platform` key in the config file, so stating it in both places guarantees a future disagreement —
> the compose env wins silently. Native Forgejo support arrived in ≥37.
>
> **The fleet is not Renovate-maintained:** Renovate here is pointed at `domen/test`, so nothing opens
> a PR against this repo and pins are refreshed by hand — see §Manual pin refresh. "Renovate keeps it
> current" is a true statement about the CONFIG and a false statement about the fleet until that
> pointer moves.

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
      "description": "The one npm-managed pin in the repo is the pi stack in group_vars/all/versions.yml (pi_host_*/pi_dev_*/pi_web_*) — it is an APPLICATION version, not a Docker base image, so §7's stabilityDays argument applies verbatim. `pi_host_web_npm_version` is exempt: the pi-web cockpit self-updates inside @beta from the phone, so pinning that string would break its own update path."
    }
  ],
  "fileMatch": {
    "jsonnet": ["**/*.jsonnet", "**/*.libsonnet"]
  }
}
```

---

### Deb checksums: fetch, never transcribe

A `sha256` in a variable name is a **do-not-edit marker** for exactly this reason. When a version bump
does require the digest to move, the digest must come from the vendor in the same breath as the bump —
`python3 scripts/image-pin-probe.py --debs` fetches `pkgs.tailscale.com/stable/tailscale_<ver>_<arch>.deb.sha256`
and compares every arch line, and it is the only honest way to write those lines. A transcribed digest can
share 8 hex chars with upstream and diverge after: every offline gate passes, the render is clean, and the
converge dies mid-role on a `get_url` checksum mismatch — the play aborts and everything downstream stays
unconverged with `changed=0`.

## Manual pin refresh

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
  stable: an upstream dev-channel tag or a commit-suffixed nightly of an unreleased version is never
  a target.
* **existence probe** — a tag that 404s is a phantom pin. No gate can see this, because every
  gate renders the string and none asks the registry, and a host that already has the layer cached
  never finds out.
* **official images** — Docker Hub push date is a *rebuild* date, so the release feed (GitHub)
  supplies the date for `library/*` instead.

Then: apply the values into `group_vars/all/versions.yml` (the SSOT), keep `*_image` digest pins
untouched, and state the deploy cost — a data-format major (postgres 16 → 18,
RabbitMQ 3 → 4) is a migration, not a restart.

---

## Docker Compose

> SSOT is the rendered template
> [IaC/ansible/templates/docker_services/renovate/docker-compose.yml.j2](../IaC/ansible/templates/docker_services/renovate/docker-compose.yml.j2)
> — the block below mirrors it; if they disagree, the template wins.
>
> ⏳ **Status: enabled, pointed at the wrong repo on purpose.** `RENOVATE_REPOSITORIES` is
> `domen/test` because **`domen/homelab` has not been migrated to Forgejo**. Flip it to `domen/homelab`
> when that repo lands.
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
      RENOVATE_REPOSITORIES: "domen/test"   # TEMPORARY — domen/homelab pending migration
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
- **Ansible Galaxy collections** (`IaC/ansible/requirements.yml`) — `community.*` pinned collections
- **Python `requirements.txt`** (`client/office-bridge/requirements.txt` + any future)

Does NOT scan:
- System packages (handled by `unattended-upgrades` on Debian)
- RouterOS firmware (manual check)
- The repo's build/test tools in `scripts/*.py` (no declared dependency manifest — the pip manager tracks `requirements*.txt` only)

---

## Run model & triggers

Renovate needs **no push webhook and no job scheduler** to detect updates — it **polls** the configured
repos on its own cadence (the renovate CLI is pull-based). Two things are therefore **optional**, NOT
required for correctness:
- A **push webhook** would only make detection *instant* after a push; it is not needed for Renovate to
  work.
- A `schedule`/cron (`RENOVATE_CRON` / `schedule` in config) only gates **when** runs are allowed
  (e.g. nightly, avoid work hours) to limit noisy PRs/CI churn — optional policy, not a correctness need.

**Container run-model:** Renovate is a *run-once* image —
it does one pass then exits 0. Combined with `restart: unless-stopped` and no schedule, Docker restarts it
immediately → tight loop. Correct models: (a) long-running daemon/sidecar that
keeps sleeping between polls, (b) a systemd timer / cron that invokes it on a cadence, or (c) run-on-demand.
The `domen/test` sandbox is what this run model is decided against; the GitHub migration stays the LAST
step.