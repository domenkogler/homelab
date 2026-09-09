---
title: Admin — Ops, GitOps, Security & Backup
role: detail
domain: services
status: active
tags: [services, admin, ops, gitops, security, backup]
---
# Admin — Ops, GitOps, Security & Backup

> **Role:** Detail — the operational/admin slice of the services stack: GitOps (Forgejo, Renovate), edge-security dashboards (CrowdSec, Metabase), VPN mesh (Headscale), backup (Kopia, DB Backup), and the **network/rack topology dashboard (Homelable, HD-45)**.
> **Links to:** `services-traefik.md`, `services-authentik.md`, `backup.md`, `deployment-renovate.md`, `observability.md`, `network-rack.md`, `services.md`
> **Linked from:** `services.md`, `index.md`

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
| Homelable | — | host (Home VLAN) | ~200–400 / 800 | Network/rack topology visualizer (HD-45) — oldsrv, internal-only, **deploy-gated** (`enabled:false`). nmap discovery + live healthchecks + device inventory/docs + rack canvas; complements the HD-343 network-clients Grafana view. Reached at `http://<oldsrv-home-ip>:3000`. Auth = local admin (`homelable_login`). |

## Homelable — network/rack topology visualizer (HD-45, re-scoped 2026-09-09)

> **Status: 🟢 IaC authored, not yet live — ⏳ deploy-gated.** Homelable (Pouzor/homelable, MIT) is the owner's chosen "network dashboard" — an interactive canvas of **who is on the network + how it is connected + live status** in one tool. Registered in `home_servers.yml` `docker_services` with `enabled: false`; nothing runs until the owner signs off + the secrets are seeded (Stage 9 below).

**Why this tool (owner decision 2026-09-09):** the owner has seen the Grafana **Network Clients** dashboard (HD-343) and wants **Homelable alongside it** — Grafana stays the metrics/alerting view (per-VLAN tables + time series), Homelable adds the **topology/rack canvas** those tables cannot express. Both run on the LAN; neither is public.

### The i/ii/iii mapping
| Want | Delivered by | Detail |
|------|--------------|--------|
| (i) who is on the network + per-VLAN | **HD-343 Grafana** (`stats.kogler.si`, network-clients dashboard) **AND** Homelable device inventory + nmap Pending queue | HD-343 = SSOT-accurate `mikrotik_client` union (DHCP/ARP/FDB/wifi). Homelable = its own scan/discovery + inventory; approve discovered devices into its canvas. Keep HD-343 authoritative for *leases*; use Homelable's canvas for the *curated map* |
| (ii) topology / connection map | **Homelable** (network diagram + rack canvas + port patching) | The tool's core. Import/curate the router/switch/APs + every VLAN's devices; draw links; watch live status (ping/http/health) on the canvas |
| (iii) combined view | **Homelable canvas** with HD-343-derived context | Homelable nodes carry IP/MAC + live status; where a node is also in `mikrotik_client`, its VLAN/source is visible. A combined "all-in-one" single pane is the Homelable canvas itself; Grafana stays the tabular/metrics pane |

**Integration with the HD-343 network-clients exporter:** Homelable does **not** consume `mikrotik_client` directly (no Prometheus import in v3.4.x upstream). The integration is *curation*: seed the Homelable inventory from the same reality HD-343 reflects — the static hosts in the SSOT (`network_static_hosts`) and the HD-343 live view — then let Homelable's own scanner + healthchecks keep it live. Do not double-source truth: `network_static_hosts` (IaC) is the SSOT for what *should* exist; HD-343 shows what *does*; Homelable is the *map + status* layer over both. (If upstream later ships a Prometheus/VictoriaMetrics import, wire it to the same `mikrotik_client` series.)

### Access model (fleet-exposure policy, HD-251)
- **Internal-only, never public** — no DNS record, no WAN allow, no VPS edge route. Same posture as the tailnet-only admin dashboards, with one structural difference: those live on the VPS `traefik-tailnet` edge, whereas Homelable must live **on oldsrv on the Home VLAN** to scan the LAN (nmap + ARP + ping need L2/LAN presence — see compose header).
- **Reach:** LAN clients on VLAN 10 → `http://<oldsrv-home-ip>:3000`. Remote/tailnet: oldsrv is a tailnet node — a **Pattern-A sidecar / tailnet route** is the planned remote path (future tail, HD-45 deploy tail); not built yet.
- **Auth:** Homelable's local admin login (username + bcrypt `AUTH_PASSWORD_HASH`). Native OIDC is available but deliberately OFF for now (single-owner admin tool behind the LAN ACL). Revisit only if family members get accounts.
- **Network placement:** `network_mode: host` for backend + frontend, both **binding only the Home-VLAN IP** (never 0.0.0.0) — the actual-budget / mcp-* narrow-bind precedent. The optional MCP container joins `services-internal` (off by default).

### Ports / services
| Container | Image | Host bind | Purpose |
|-----------|-------|-----------|---------|
| homelable-backend | `ghcr.io/pouzor/homelable-backend:{{ homelable_version }}` | host-net, uvicorn on `127.0.0.1:8000` (nginx fronts it) | FastAPI: scan, healthchecks, DB |
| homelable-frontend | `ghcr.io/pouzor/homelable-frontend:{{ homelable_version }}` | host-net, nginx on `<oldsrv-home-ip>:3000` | React SPA (proxies `/api` → loopback backend) |
| homelable-mcp *(optional)* | `ghcr.io/pouzor/homelable-mcp:{{ homelable_version }}` | `services-internal` | MCP server for AI-tool topology read/write (off by default) |

### State & backup
- SQLite DB + uploads under `/srv/docker/homelable/data` (host bind). Covered by the oldsrv **kopia-agent** snapshot scope (`/srv/docker`, backup.md) — add a source line when the service goes live.
- Disposable/regenerable by design: the canvas is *curated* data, not a service SSOT. Keep it backed up but never treat it as authoritative for IPs/VLANs (`network_static_hosts` is).

### Secrets (1Password `Homelab-ansible`, catalog-generated — provision-secrets.py)
| Item | Category/fields | Consumed as | Notes |
|------|-----------------|-------------|-------|
| `homelable_login` | Login — `username`, `password`, `bcrypt_hash` | `AUTH_USERNAME`, `AUTH_PASSWORD_HASH` | `bcrypt_hash` = bcrypt(password), written at item creation (see `homelable_login_item()`). Compose escapes `$`→`$$` (HD-270). Rotate rewrites password + hash together. |
| `homelable_secret` | Password — `password` (48-char gen) | `SECRET_KEY` (+ `MCP_SERVICE_KEY` when MCP on) | ≥32 bytes for JWT. Rotatable (sessions reset). |
| `homelable_mcp` | API Credential — `credential` | `MCP_API_KEY` | Only consumed when `homelable_mcp_enabled`; catalog-created so the flag flip never needs a manual seed. |

### Onboarding stage (CONVENTIONS §5)
Authored 2026-09-09 against upstream **v3.4.1** (registry-verified on GHCR for backend/frontend/mcp). Register the row as **Stage 8/10** — steps 1–8 (exposure/secrets/compose/registry/edge-decision/state/observability/validation) are authored in this section + the compose + the docs; **step 9 (deploy gate) is owner-gated** and step 10 (docs close) follows the live verify.

| # | Onboarding step | State |
|---|-----------------|-------|
| 1 | Exposure & auth decision | ✅ internal-only, Home-VLAN narrow-bind, local admin (OIDC deferred) — this section |
| 2 | Secrets | ✅ names + docs + CATALOG authored (`homelable_login`/`homelable_secret`/`homelable_mcp`); items must be created before first converge |
| 3 | Compose template | ✅ `templates/docker_services/homelable/` (compose + nginx.conf.j2), pins in `versions.yml`, scanner vars in `home_servers.yml` |
| 4 | Registry | ✅ `home_servers.yml` row `enabled:false` + catalog row here + `services.md` |
| 5 | Edge (if exposed) | ✅ none (internal-only; no Traefik on oldsrv — HD-331). Direct Home-IP :3000 |
| 6 | State & backups | ✅ `/srv/docker/homelable/data` → kopia scope (add live source at deploy) |
| 6.5 | Storage / data location | ✅ oldsrv local bind (not NAS) — canvas is host-local curated data |
| 7 | Observability | ✅ image healthcheck + `Up` status visible; node metrics flow via Alloy (host exporter) |
| 8 | Validation | ✅ `validate-all.sh` green (compose + registry + version pin) |
| 9 | **Deploy gate (owner)** | ⏳ seed 1P items → `ansible-run.sh playbooks/home_servers.yml -e docker_services_scope=homelable` (or full oldsrv converge) → owner creates admin + approves first scan |
| 10 | Docs close | ⏳ after live verify — confirm this section's ✅/⏳ and delete any open todo row |

### Owner deploy checklist (what unblocks this)
1. **Seed the three 1P items**: `OP_SERVICE_ACCOUNT_TOKEN=… python3 scripts/provision-secrets.py --create --yes` (creates `homelable_login` w/ bcrypt, `homelable_secret`, `homelable_mcp`) — or `scripts/provision-vault.sh` on the WSL runner.
2. **Deploy**: `ansible-run.sh playbooks/home_servers.yml --tags docker_services -e docker_services_scope=homelable` (surgical) — first apply is human-gated per CONVENTIONS §5.9.
3. **First-run**: open `http://<oldsrv-home-ip>:3000`, log in with the `homelable_login` creds, trigger the first scan, approve discovered devices into the canvas; sketch the rack + draw links.
4. **(Optional, later)** flip `homelable_mcp_enabled: true` + converge for AI-tool access once the canvas is curated; add a tailnet Pattern-A route for remote use.

### Known gaps / upstream caveats
- **v3.4.x is young and fast-moving** — pin is `3.4.1`; re-verify the image/tag and re-check the release notes at first deploy (HD-134/§7 discipline).
- Scanner MAC caveat: with host networking the backend sees real MACs; without it every device is MAC-less (avoided here by design).
- No upstream Prometheus/VictoriaMetrics import yet — HD-343 integration is curation-based (see i/ii/iii above).
- The tool is not a metrics/logs/alert backend — Grafana/VictoriaMetrics stay authoritative for that (observability.md).

## Notes

- **CrowdSec** runs on the Traefik edge (middleware chain in [`services-traefik.md`](services-traefik.md)); the CrowdSec *dashboard* is served via the **Metabase** instance (one Metabase = CrowdSec view + analytics sandbox). CrowdSec's bundled/pinned Metabase image is **not** used.
- **Admin Dashboards decision:** Traefik Dashboard — tailnet-only `traefik.kogler.si` / `traefik.ts.kogler.si` ([`services-traefik.md`](services-traefik.md) → traefik-tailnet); CrowdSec Dashboard — tailnet-only `sec.kogler.si` / `sec.ts.kogler.si` (Metabase) + **CrowdSec Web UI** `csui.kogler.si` / `csui.ts.kogler.si` (HD-272). All reached over the **headscale tailnet** via the `traefik-tailnet` edge (clean subdomain URLs, no ports — HD-135b follow-up, 2026-08-28), no public record. **Portainer / Dockge — excluded** (single Ansible-templated compose model).
- **GitOps:** Forgejo Actions + Renovate drive the Ansible deploy chain — see [`deployment-renovate.md`](deployment-renovate.md), [`deployment.md`](deployment.md).
- **Metabase first boot (manual, one-time — HD-241 record, walked 2026-08-24):** wizard order = language → admin account → data-source (**skip** — sources are compose-wired, HD-242) → usage-data prefs. Chosen: admin `admin@kogler.si` (Cloudflare alias → personal mail; vault item `metabase_login` — manual 1P creation outside the provision-secrets catalog), anonymous tracking **OFF**, HTTPS-redirect **OFF** (correct behind Traefik TLS termination — an app-level redirect would loop), forward-auth logout round-trip verified. Password-reset mails need SMTP (below) — until converged, the vault entry is the recovery path.
- **Metabase SMTP (HD-241, CLOSED 2026-09-08):** `MB_EMAIL_SMTP_*` in the compose template consume the shared smtp2go SSOT (`smtp2go_host`/`smtp2go_port`) + the shared `smtp_login` item; From = `notify@kogler.si` (smtp2go account identity). Env-set settings override AND lock the Admin-UI fields → mail config changes via converge only. **✅ VERIFIED END-TO-END 2026-09-08:** owner's *Send test email* delivered from `notify@kogler.si` (“hooray!”). **Three bugs fixed en route:** ① smtp2go `587` blocked from the VPS egress → SSOT `smtp2go_port` → **2525** (live 2026-09-08); ② VPS Grafana had NO `grafana_smtp_host` (VPS is its own group, not home_servers) → fell back to dead `localhost:25` → added derived `grafana_smtp_host` in `group_vars/vps.yml` (also live); ③ Metabase From-address env var was WRONG (`MB_FROM_ADDRESS` ignored → fell back to unverified `notifications@metabase.com`, smtp2go 550) → fixed to **`MB_EMAIL_FROM_ADDRESS`** per Metabase docs (`MB_EMAIL_FROM_ADDRESS_OVERRIDE` is Pro/Enterprise-only). Grafana emails also confirmed working. ⏳ Known gap (unchanged, HD-238): `metabase-data` H2 volume has NO backup coverage — keep sandbox data disposable.
- **Metabase data sources (HD-242):** ① CrowdSec SQLite bind `/srv/docker/crowdsec/db` → connection type *SQLite*, path `/var/lib/crowdsec/data/crowdsec.db`, then import the official CrowdSec dashboard JSONs; ② Forgejo Postgres over `db-internal` via read-only role `metabase_ro` (auto-created/re-synced by `deploy-service.yml` from `metabase-forgejo_ro`; SELECT-only incl. default privileges); ③ Zipline Postgres same pattern once HD-112 first-deploys (DB05).
- **Metabase LDAP auth — REJECTED (HD-243, owner decision 2026-09-09):** Metabase OSS LDAP would still be a second login form behind Forward-Auth (no SSO/MFA passthrough) and needs an outpost-binding decision (HD-186 blast radius: outpost is WG-S2S-bound for Samba). **Revisit trigger was "second regular human user" — the owner is the sole Metabase user, so it is closed/rejected.** Metabase stays Forward-Auth + local admin-only. Decision log: [services-rejected.md](services-rejected.md) HD-243.

## Related
- [Backup](backup.md) — Kopia / DB-backup policy
- [Observability](observability.md) — Metabase/CrowdSec dashboards overlap