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

> 🟢 **VPS members live since 2026-08-22** (Phase 1): Forgejo (healed 2026-08-23 after the postgres role-password rotation fix, HD-220a), CrowdSec, Headscale + Headplane admin UI, kopia-server, db-backup, Renovate. ⏳ deploy-gated: kopia-agent (oldsrv, Phase 3) plus owner tails surfaced in todo.md (Forgejo repo creation/migration, kopia seed/wiring decisions — HD-230).
> **Metabase RETIRED from the VPS 2026-09-14** (never used; no data to lose; VPS RAM tight) — if ever needed again it runs on **OLDSRV** (see §Metabase below).

---

## Catalog

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| Forgejo | git | I | 150–250 / 450 | Git hosting, Issues, PRs (+ Actions runner). **GitOps / upgrade-automation trigger** — Forgejo Actions → Renovate → Ansible. **Auth (HD-148): native OIDC → Authentik** (web SSO + per-user API/token); client via Blueprint + glue |
| Renovate Bot | — | I | 150–300 / 600 | Docker image version tracking (GitOps upgrade automation) |
| CrowdSec | — | P | 100–200 / 400 | WAF, brute-force protection (dashboard via CrowdSec Web UI — Metabase retired 2026-09-14) |
| ~~Metabase~~ | ~~sec~~ | ~~P+I~~ | ~~250–450 / 800~~ | **RETIRED from the VPS 2026-09-14** (never used; VPS RAM tight). If revived → **OLDSRV** (fresh analytics sandbox, no sources). See §Metabase below. Template + disabled VPS entry retained |
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

## Metabase — RETIRED from the VPS (2026-09-14)

> **Retired for now** — never used, no data to lose, VPS RAM tight. The compose template, the
> disabled VPS `docker_services` entry, and this documentation are retained so it can be revived
> **on OLDSRV** later (owner: *"if it will be needed it will be on oldsrv"*). Vault item
> `metabase-forgejo_ro` left in place (owner: leave as-is); the `metabase_ro` role stays in
> forgejo-db but is no longer re-synced (db_ro keys commented out in `vps.yml`).

**What it was (VPS analytics sandbox, `sec.kogler.si`, tailnet-only):** historical record below.

- **CrowdSec dashboard** was served via **Metabase** (one instance = CrowdSec view + analytics sandbox). CrowdSec's bundled/pinned Metabase image was **not** used. After retirement the CrowdSec dashboard surface is **CrowdSec Web UI** (`csui.kogler.si`, HD-272) alone.
- **Reachability while live:** tailnet-only `sec.kogler.si` / `sec.ts.kogler.si` over the VPS `traefik-tailnet` edge (forward-auth on the plain name; ACL-gated on `*.ts`). Both routes + the DNS record were **removed 2026-09-14** with the retirement.
- **Data sources (HD-242, ALL REMOVED 2026-09-14):** ① CrowdSec SQLite bind `/srv/docker/crowdsec/db` (VPS-local; WAL-recovery RW); ② Forgejo Postgres over `db-internal` via read-only role `metabase_ro` (from `metabase-forgejo_ro`, SELECT-only); ③ Zipline Postgres (never went live). A future oldsrv home re-adds LAN sources.
- **First boot (HD-241 record, walked 2026-08-24):** wizard order = language → admin account → data-source (**skip**) → usage prefs. Chosen: admin `admin@kogler.si` (vault `metabase_login`), anonymous tracking OFF, HTTPS-redirect OFF. Password-reset via SMTP.
- **SMTP (HD-241, CLOSED 2026-09-08):** `MB_EMAIL_SMTP_*` from smtp2go SSOT + shared `smtp_login`; From = `notify@kogler.si`; verified end-to-end. Four fixes en route (port 2525, VPS `grafana_smtp_host`, `MB_EMAIL_FROM_ADDRESS`).
- **LDAP/OIDC — REJECTED (HD-243, 2026-09-09):** OSS has no OIDC/SSO (paid); LDAP = a second login + outpost blast radius; owner is sole user. Stays Forward-Auth + local admin. Decision: [services-rejected.md](services-rejected.md) HD-243.

**Revival path (when wanted):** enable on **OLDSRV** — add an oldsrv `docker_services` entry (`template_dir: metabase`, `public: false`), decide its reach/auth (LAN direct vs a future oldsrv edge), re-add any LAN data sources to the template (the VPS CrowdSec/db-internal sources are gone), seed the `smtp_login` + `metabase_login` items if not present, converge oldsrv. Out of the current session's scope (oldsrv converge not run here).

> **Deploy note (2026-09-14):** the `technitium-seed` role only adds records (`zones/records/add`) — it does **not** delete retired ones. After the retirement the VPS primary Technitium still carries a stale internal `sec.kogler.si` A-record to the tailnet-sidecar IP (harmless — points at the dead tailnet edge → 404 — but it contradicts the SSOT). Remove it via the Technitium API (`/api/zones/records/delete`, HD-324 path) the next time Technitium is touched, or fold a record-prune into the seed role when a record-retirement comes around.

## Notes

- **CrowdSec** runs on the Traefik edge (middleware chain in [`services-traefik.md`](services-traefik.md)); its dashboards/surfaces: **CrowdSec Web UI** (`csui.kogler.si`) + the retired-Metabase dashboard (see §Metabase above — no longer a CrowdSec dashboard since 2026-09-14).
- **Admin Dashboards decision:** Traefik Dashboard — tailnet-only `traefik.kogler.si` / `traefik.ts.kogler.si` ([`services-traefik.md`](services-traefik.md) → traefik-tailnet); **CrowdSec Web UI** `csui.kogler.si` / `csui.ts.kogler.si` (HD-272) — all reached over the **headscale tailnet** via the `traefik-tailnet` edge (clean subdomain URLs, no ports — HD-135b follow-up, 2026-08-28), no public record. (Metabase `sec` was a tailnet dashboard too but is **retired 2026-09-14** — see §Metabase above.) **Portainer / Dockge — excluded** (single Ansible-templated compose model).
- **GitOps:** Forgejo Actions + Renovate drive the Ansible deploy chain — see [`deployment-renovate.md`](deployment-renovate.md), [`deployment.md`](deployment.md).
- **Metabase — RETIRED 2026-09-14** (see the §Metabase section above): first boot, SMTP, data sources, and LDAP/OIDC decisions are recorded there for the future oldsrv revival.

## Related
- [Backup](backup.md) — Kopia / DB-backup policy
- [Observability](observability.md) — CrowdSec dashboards / analytics overlap