---
title: Admin — Ops, GitOps, Security & Backup
role: detail
domain: services
status: active
tags: [services, admin, ops, gitops, security, backup]
---
# Admin — Ops, GitOps, Security & Backup

> **Role:** Detail — the operational/admin slice of the services stack: GitOps (Forgejo, Renovate), edge-security dashboards (CrowdSec, Metabase), VPN mesh (Headscale), and backup (Kopia, DB Backup).
> **Links to:** `services-traefik.md`, `services-authentik.md`, `backup.md`, `deployment-renovate.md`, `observability.md`, `services.md`
> **Linked from:** `services.md`

> ⚠️ **Planning phase — not yet deployed.** Admin services are IaC-authored but **not live**; deploy-gated against `deployment-tasks.md`.

---

## Catalog

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| Forgejo | git | I | 150–250 / 450 | Git hosting, Issues, PRs (+ Actions runner). **GitOps / upgrade-automation trigger** — Forgejo Actions → Renovate → Ansible. **Auth (HD-148): native OIDC → Authentik** (web SSO + per-user API/token); client via Blueprint + glue |
| Renovate Bot | — | I | 150–300 / 600 | Docker image version tracking (GitOps upgrade automation) |
| CrowdSec | — | P | 100–200 / 400 | WAF, brute-force protection (dashboard via Metabase) |
| Metabase | sec | P+I | 250–450 / 800 | CrowdSec dashboard + analytics sandbox (one instance, two roles). **Auth (HD-148): Forward-Auth** (Metabase OSS has NO OIDC/SSO — paid Enterprise feature; provider/`metabase_oidc` declared for future, but route stays Forward-Auth) |
| Headscale | vpn | P | 60–120 / 250 | Tailscale coordination server |
| Kopia | bck | I | 150–250 / 500 | Encrypted off-site backup → Hetzner Storage Box (backup, far DC) |
| DB Backup | — | D | 30–60 / 200 | Database dumps (tiredofit/db-backup) |

## Notes

- **CrowdSec** runs on the Traefik edge (middleware chain in [`services-traefik.md`](services-traefik.md)); the CrowdSec *dashboard* is served via the **Metabase** instance (one Metabase = CrowdSec view + analytics sandbox). CrowdSec's bundled/pinned Metabase image is **not** used.
- **Admin Dashboards decision:** Traefik Dashboard — internal-only `traefik.kogler.si` ([`services-traefik.md`](services-traefik.md)); CrowdSec Dashboard — internal-only `sec.kogler.si` (Metabase). **Portainer / Dockge — excluded** (single Ansible-templated compose model).
- **GitOps:** Forgejo Actions + Renovate drive the Ansible deploy chain — see [`deployment-renovate.md`](deployment-renovate.md), [`deployment.md`](deployment.md).

## Related
- [Services index](services.md)
- [Backup](backup.md) — Kopia / DB-backup policy
- [Observability](observability.md) — Metabase/CrowdSec dashboards overlap