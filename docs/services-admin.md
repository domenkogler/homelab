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

> 🟢 **VPS members live since 2026-08-22** (Phase 1): Forgejo (healed 2026-08-23 after the postgres role-password rotation fix, HD-220a), CrowdSec, Metabase, Headscale + Headplane admin UI, kopia-server, db-backup, Renovate. ⏳ deploy-gated: kopia-agent (oldsrv, Phase 3) plus owner tails surfaced in todo.md (Forgejo repo creation/migration, kopia seed/wiring decisions — HD-230).

---

## Catalog

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| Forgejo | git | I | 150–250 / 450 | Git hosting, Issues, PRs (+ Actions runner). **GitOps / upgrade-automation trigger** — Forgejo Actions → Renovate → Ansible. **Auth (HD-148): native OIDC → Authentik** (web SSO + per-user API/token); client via Blueprint + glue |
| Renovate Bot | — | I | 150–300 / 600 | Docker image version tracking (GitOps upgrade automation) |
| CrowdSec | — | P | 100–200 / 400 | WAF, brute-force protection (dashboard via Metabase) |
| Metabase | sec | P+I | 250–450 / 800 | CrowdSec dashboard + analytics sandbox (one instance, two roles). **Auth (HD-148): Forward-Auth** (Metabase OSS has NO OIDC/SSO — paid Enterprise feature; provider/`metabase_oidc` declared for future, but route stays Forward-Auth) |
| Headscale | vpn | P | 60–120 / 250 | Tailscale coordination server |
| Kopia | — | I | 150–250 / 500 | Encrypted off-site backup (kopia-server on the VPS + oldsrv agent, HD-191) → Hetzner Storage Box (backup, far DC); agent reach = WG-only `:51515`, no subdomain |
| DB Backup | — | D | 30–60 / 200 | Database dumps (tiredofit/db-backup) |

## Notes

- **CrowdSec** runs on the Traefik edge (middleware chain in [`services-traefik.md`](services-traefik.md)); the CrowdSec *dashboard* is served via the **Metabase** instance (one Metabase = CrowdSec view + analytics sandbox). CrowdSec's bundled/pinned Metabase image is **not** used.
- **Admin Dashboards decision:** Traefik Dashboard — internal-only `traefik.kogler.si` ([`services-traefik.md`](services-traefik.md)); CrowdSec Dashboard — internal-only `sec.kogler.si` (Metabase). **Portainer / Dockge — excluded** (single Ansible-templated compose model).
- **GitOps:** Forgejo Actions + Renovate drive the Ansible deploy chain — see [`deployment-renovate.md`](deployment-renovate.md), [`deployment.md`](deployment.md).
- **Metabase first boot (manual, one-time — HD-241 record, walked 2026-08-24):** wizard order = language → admin account → data-source (**skip** — sources are compose-wired, HD-242) → usage-data prefs. Chosen: admin `admin@kogler.si` (Cloudflare alias → personal mail; vault item `metabase_login` — manual 1P creation outside the provision-secrets catalog), anonymous tracking **OFF**, HTTPS-redirect **OFF** (correct behind Traefik TLS termination — an app-level redirect would loop), forward-auth logout round-trip verified. Password-reset mails need SMTP (below) — until converged, the vault entry is the recovery path.
- **Metabase SMTP (HD-241, env-driven):** `MB_EMAIL_SMTP_*` in the compose template consume the shared smtp2go SSOT (`smtp2go_host`/`smtp2go_port`) + the shared `smtp_login` item; From = `notify@kogler.si` (smtp2go account identity). Env-set settings override AND lock the Admin-UI fields → mail config changes via converge only. Verify: Admin → Email → *Send test email*.
- **Metabase data sources (HD-242):** ① CrowdSec SQLite bind `/srv/docker/crowdsec/db` → connection type *SQLite*, path `/var/lib/crowdsec/data/crowdsec.db`, then import the official CrowdSec dashboard JSONs; ② Forgejo Postgres over `db-internal` via read-only role `metabase_ro` (auto-created/re-synced by `deploy-service.yml` from `metabase-forgejo_ro`; SELECT-only incl. default privileges); ③ Zipline Postgres same pattern once HD-112 first-deploys (DB05).
- **Metabase LDAP auth — DEFERRED (HD-243):** OSS-included LDAP vs the Authentik outpost would still show a second login form (no SSO/MFA passthrough) and needs an outpost-binding decision (HD-186 blast radius: outpost is WG-S2S-bound for Samba). Revisit trigger: second regular human user.

## Related
- [Services index](services.md)
- [Backup](backup.md) — Kopia / DB-backup policy
- [Observability](observability.md) — Metabase/CrowdSec dashboards overlap