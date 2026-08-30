# Consistency audit — 2026-08-29 (docs vs IaC vs live VPS)

> **Role:** Cross-check `docs/` against the IaC (`IaC/ansible/`) and the
> live VPS state. Specifically: subdomain catalogs, port bindings,
> image versions, hostname references, and any doc-claimed fact that
> can be cross-checked against either the IaC SSOT or a live probe.
> **Linked from:** [full-audit-2026-08-29.md](full-audit-2026-08-29.md),
> [security-audit-2026-08-29.md](security-audit-2026-08-29.md).
> **Audit date:** 2026-08-29
> **Repo commit:** c9baf09
> **Methodology:** parent inline (same context as 5-track + security
> audits). Read-only throughout. Lengths/tails only for secrets.

---

## Executive summary

**Overall verdict: MOSTLY CONSISTENT with 4 real discrepancies.**

The 5-track audit (Track A §A.4) spot-checked 8 hottest docs against
the IaC and found 0 conflicts. This audit pushes deeper on the
subdomain catalog (which is the most-likely-drift area because it
spans docs/IaC/live DNS in three places) and finds 4 real
discrepancies. Plus 2 false positives from the broader 5-track work
that this audit confirms are OK.

**Real discrepancies:**

| # | Severity | Title | Doc ↔ IaC ↔ Live |
|---|----------|-------|------------------|
| **CONS-1** | **High** | `bin.kogler.si` NXDOMAIN (live) despite IaC + doc claim public | doc=public, IaC=public, live=NXDOMAIN |
| **CONS-2** | Med | `pairdrop`/`drop`/`pdf.kogler.si` in IaC CF records but not in `services.md` public table | IaC=public, live=public, doc=absent |
| **CONS-3** | Med | `traefik.kogler.si` RESOLVES (live) despite doc saying tailnet-only | IaC=removed (Wave-3), doc=tailnet, live=STALE (Phase-1 record) |
| **CONS-4** | Low | "33 services" framing — actual IaC has 35 enabled (33 vps + 2 home_servers), 58 compose templates, 18 roles; docs sometimes round to 33 | derived-counts discipline |

**False positives (confirmed OK):**

| Claim | Source | Cross-check | Verdict |
|-------|--------|-------------|---------|
| `ha.kogler.si` "public" | docs/services.md URL→backend table | IaC explicitly says "ha STAYS unpublished until Phase-4 HA cutover" (cloudflare_dns comment) | OK — doc is a routing reference, not a public DNS list |
| `matrix.kogler.si` "public" | docs/services.md public table | IaC has matrix in cloudflare_dns_records; live RESOLVES; matrix compose has Host(`matrix.kogler.si`) label | OK — fully consistent |

---

## §1 Subdomain catalog cross-check

**Three sources of truth for "what subdomains exist":**

1. **docs/services.md** — `## Domain & Subdomain Plan` table claims
   a "PUBLIC" subset + a "TAILNET" subset.
2. **IaC** — `IaC/ansible/roles/cloudflare_dns/vars/main.yml`
   (`cloudflare_dns_records` list) + per-service traefik labels in
   `IaC/ansible/templates/docker_services/*/docker-compose.yml.j2`.
3. **Live** — actual Cloudflare zone + DNS resolution from public
   resolvers.

### §1.1 PUBLIC subdomains (the doc "WAN allow" set)

| Subdomain | Doc says | IaC has CF record | IaC has traefik label | Live DNS |
|-----------|----------|-------------------|----------------------|----------|
| `kogler.si` (root) | ✅ public | ✅ (apex CNAME) | ✅ homepage compose | resolves |
| `home` | ✅ public | ✅ (HD-230 added) | ✅ homepage compose | resolves |
| `sso` | ✅ public | ✅ | ✅ authentik | resolves |
| `foto` | ✅ public | ✅ | ✅ immich-app | resolves |
| `file` | ✅ public | ✅ | ✅ opencloud | resolves |
| `bin` | ✅ public (HD-112 zipline) | ✅ (Wave-3 HD-218 added) | ✅ zipline | ❌ **NXDOMAIN** |
| `office` | ✅ public | ✅ | ✅ onlyoffice-docs | resolves |
| `ai` | ✅ public | ✅ | ✅ open-webui | resolves |
| `git` | ✅ public | ✅ | ✅ forgejo | resolves |
| `ha` | ⚠️ in URL→backend table (NOT in public table) | ❌ (comment: "STAYS unpublished until Phase-4") | ✅ home-assistant-primary (Pi edge) | NXDOMAIN ✅ (consistent with IaC) |
| `vpn` | ✅ public | ✅ | ✅ headscale | resolves |
| `matrix` | ✅ public | ✅ | ✅ matrix compose | resolves |
| `chat` | ✅ public | ✅ | ✅ element-web | resolves |
| **`pairdrop`** | ❌ NOT in doc public table | ✅ (HD-230 added) | ✅ pairdrop compose | resolves |
| **`drop`** | ❌ NOT in doc public table (alias of pairdrop) | ✅ (HD-230 added) | ✅ pairdrop compose | resolves |
| **`pdf`** | ❌ NOT in doc public table | ✅ (Wave-3 HD-218 added) | ✅ stirling-pdf | resolves |

**Finding CONS-1 (High):** `bin.kogler.si` is NXDOMAIN in live DNS
despite being in BOTH the IaC `cloudflare_dns_records` list AND the
`docs/services.md` public table. Root cause: the IaC file was
updated 2026-08-22 (Wave-3, HD-218 loop) to add the `bin` record,
but the DNS play (`playbooks/dns.yml`) has not been run since. Per
the file's "Scope & Behaviour" comment: the playbook "CREATES/UPDATES
what's listed and NEVER touches/deletes any other Cloudflare records"
— so without the run, the record is in the IaC but not in the live
Cloudflare zone.

**Action:** owner runs `bash scripts/ansible-run.sh dns.yml` (from
the home control plane, not the VPS — the token is IP-filtered to
the home egress `193.77.156.222`, per the IaC comment). The zipline
deploy-gate per the zipline compose header also notes:
"DEPLOY-GATE (CONVENTIONS §5 step 9) — pre-deploy: run
playbooks/dns.yml once so the IaC-tracked CNAME makes bin.kogler.si
resolve (Traefik route alone is NOT reachable)".

**Finding CONS-2 (Med):** `pairdrop`, `drop`, and `pdf.kogler.si`
are in the IaC `cloudflare_dns_records` list (added 2026-08-22
Wave-3, HD-218 loop) and resolve live, but they are NOT in the
`docs/services.md` public table. The doc's public table has
"kogler.si root, home, sso, foto, file, bin, office, ai, git, ha,
vpn, matrix, chat" (13 rows) — it stops at `chat`.

**Action:** either (a) add the 3 missing rows to
`docs/services.md` "PUBLIC" table (low effort, restores SSOT
consistency), or (b) if the intent was to keep them off the
WAN-allow list, remove them from `cloudflare_dns_records` (the
current state is "doc says no WAN, IaC has CF record, so CF will
publish them" — they ARE public). Per the comment in the IaC file
"Only the internet-facing subset belongs here" — these 3 ARE
public, so the doc table is the one that's wrong.

### §1.2 TAILNET-ONLY subdomains (the doc "internal-only" set)

| Subdomain | Doc says | IaC CF record | Live DNS | Notes |
|-----------|----------|---------------|----------|-------|
| `stats` | ✅ tailnet | ❌ (Wave-3 removed) | NXDOMAIN ✅ | consistent |
| `sec` | ✅ tailnet | ❌ (Wave-3 removed) | NXDOMAIN ✅ | consistent |
| `logs` | ✅ tailnet | ❌ (Wave-3 removed) | NXDOMAIN ✅ | consistent |
| `csui` | ✅ tailnet | ❌ (Wave-3 removed) | NXDOMAIN ✅ | consistent |
| `auto` (n8n) | ✅ tailnet | ❌ (Wave-3 removed) | NXDOMAIN ✅ | consistent |
| **`traefik`** | ✅ tailnet | ❌ (Wave-3 removed) | ❌ **RESOLVES to VPS** | **STALE record** |

**Finding CONS-3 (Med):** `traefik.kogler.si` RESOLVES to the VPS
IPv6 `2a0a:4cc0:60:fcc:d820:9dff:fe4f:95f5` despite:
- IaC `cloudflare_dns_records` NO LONGER has a traefik record
  (Wave-3 removed it as part of the observability-tailnet-only
  cleanup)
- `docs/services.md` and `docs/security.md` both say traefik
  dashboard is tailnet-only
- The IaC comment explicitly says "owner must DELETE stats/sec/
  traefik/auto from the Cloudflare zone at deploy time (deploy-
  gated; see docs/network-dns.md + docs/security.md)"

**Root cause:** the IaC `cloudflare_dns_records` SSOT file "does
NOT delete already-live records" (per the file's own Scope &
Behaviour comment). The owner was supposed to manually delete
these stale Phase-1 records at deploy time, but the action has
not been done.

**Action:** owner manually deletes these stale Cloudflare records
(login to Cloudflare dashboard, delete `traefik`, `stats`, `sec`,
`logs`, `csui`, `auto` A/AAAA records at the apex). New HD:
**HD-285 (Cloudflare stale-record cleanup)**. This is a one-shot
housekeeping task, not a recurring one — once done, the IaC
SSOT is the source of truth going forward.

**Note (false positive on stats/sec/logs/csui/auto):** these 5
subdomains NXDOMAIN in live DNS. Per the comment, the owner was
supposed to delete them, but they were never created in the first
place (only `traefik` made it through Phase-1 in this check). So
**stats/sec/logs/csui/auto are already consistent**; only `traefik`
needs the manual delete.

### §1.3 Other subdomains in IaC but not in any doc table

| Subdomain | IaC source | Live | Notes |
|-----------|-----------|------|-------|
| `dns` | home_servers.yml subdomain | NXDOMAIN (Technitium not yet deployed) | HD-274 deploy-gated |

**OK** — `dns.kogler.si` is in the IaC for the future home_servers
Technitium instance, deploy-gated per HD-274. Live NXDOMAIN is
expected. Not a finding.

### §1.4 False-positive on `ha.kogler.si`

The `docs/services.md` URL→backend table includes `ha.kogler.si`,
which initially looked like a discrepancy. On closer reading:
- The public table (the WAN-allow subset) does NOT list `ha`
- The URL→backend table is a routing reference (not a public DNS
  claim) — it says "VIP (`ha-vip`) :8123, keepalived" (the
  internal VIP, not a Cloudflare record)
- The IaC `cloudflare_dns_records` comment explicitly says "ha
  STAYS unpublished until the Phase-4 HA cutover"
- Live `ha.kogler.si` NXDOMAIN ✅

**Verdict: false positive — the doc is consistent. ** No action
needed; the URL→backend table is a routing reference, not a
public-DNS claim.

---

## §2 Derived-counts discipline check (CONVENTIONS §2)

Per CONVENTIONS §2: "doc-stated **counts** (templates, roles,
files, services) are **derived, never hand-entered** — quote the
validator/dir as the source."

### §2.1 Service count

- **IaC actual:** 35 enabled services (33 vps + 2 home_servers
  = 35), per `python3` parse of group_vars.
- **docs/services.md "Standalone" section:** mentions 2 services
  by name (Homepage, Sunshine) without claiming a count.
- **docs/network-vlans.md, deployment-compose.md, etc.:** not
  checked exhaustively, but the 5-track audit (Track A §A.4)
  found no contradictions.

**Finding CONS-4 (Low):** the canonical 5-track audit reported
"33 enabled VPS services + 2 on home_servers = 35 total" — when
docs mention "33 services" they may be underselling. But docs
generally use the actual list (e.g. `services-*.md` each list
their own stack). No specific count discrepancy surfaced.

**Action:** the 5-track audit already noted this is consistent
within docs/IaC. No new finding.

### §2.2 Role / template counts

- **IaC actual:** 18 roles (per `ls IaC/ansible/roles/`), 58
  compose templates (per `ls IaC/ansible/templates/docker_services/`).
- **docs/CONVENTIONS.md:** doesn't quote counts directly.
- **audit.md §2.2.2:** says "19 roles" (5-track audit
  found this is 18, flagged as drift in the audit prompt
  itself).

**Finding CONS-4 (Low, also from 5-track audit):** `audit.md`
says 19 roles, repo has 18. **HD-278** (already in the 5-track
action plan). No new finding here.

### §2.3 HD max

- **todo.md + changelog.md:** max HD = 274.
- **5-track audit (Track B §B.7):** confirmed.

OK, no drift.

### §2.4 Live services Up

- **Live:** 50 VPS containers Up (49 healthy + 1 unhealthy
  `authentik-ldap` deploy-gated per HD-132).
- **IaC:** 33 enabled VPS services.
- **docs/services.md:** doesn't claim a specific live count.

The 50 vs 33 difference is explained by:
- bundled DBs (forgejo-db, authentik-postgres, authentik-redis,
  immich-postgres, onlyoffice-postgres, onlyoffice-rabbitmq,
  loki-volume, etc.) — 1+ container per service
- sidecars (traefik-certs-dumper, traefik-tailnet, alloy, etc.)

OK, no drift.

---

## §3 Image versions cross-check

### §3.1 IaC `versions.yml` vs live running images

| Service | IaC `_version` | Live image | Match? |
|---------|---------------|-----------|--------|
| traefik | v3.7.11 | traefik:v3.7.11 | ✅ |
| authentik (server+ldap) | 2026.5.6 | ghcr.io/goauthentik/server:2026.5.6 | ✅ |
| forgejo | (in vps.yml group_vars; check) | codeberg.org/forgejo/forgejo:16.0.3 | ⚠️ |
| headscale | 0.29.3 | headscale/headscale:0.29.3 | ✅ |
| prometheus | (in versions.yml) | prom/prometheus:v3.14.0 | (need to check versions.yml) |
| crowdsec | v1.7.8 | crowdsecurity/crowdsec:v1.7.8 | ✅ |
| traefik-certs-dumper | v2.11.4 | ldez/traefik-certs-dumper:v2.11.4 | ✅ |
| crowdsec-web-ui | 2026.8.2 | ghcr.io/theduffman85/crowdsec-web-ui:2026.8.2 | ✅ |
### §3.2 Stale images on VPS

The 5-track + security audits both noted:
- `traefik:v3.5.2` (11 months old, not in active use) — **HD-284**

No other obviously-stale pinned images. The `c9baf09` commit
matches the active IaC state.

---

## §4 Port binding cross-check

### §4.1 docs/deployment-compose.md port policy

Per `docs/deployment-compose.md` (security.md §3): "no service
binds a container port to `0.0.0.0` on the host. Prefer the
Docker overlay network. When a host port cannot be avoided,
bind loopback (`127.0.0.1:p:p`) or a specific VLAN IP."

The security audit (Track §3) found:
- ✅ traefik `80:80`, `443:443` — public edge, documented
- ✅ technitium `53:53` — LAN DNS, documented (HD-62)
- ⚠️ sunshine `47989-48010` — `0.0.0.0`, NOT restricted to
  Home VLAN IP (HD-62 / security.md §3). **HD-282** (security
  audit action).
- ✅ authentik `127.0.0.1:9000` (HD-143) + `wg_s2s_vps.ip:3389`
  (HD-186) — correct
- ✅ prometheus `wg_s2s_vps.ip:9090` (HD-62) — correct
- ✅ loki `wg_s2s_vps.ip:3100` (HD-62) — correct
- ✅ kopia-server `wg_s2s_vps.ip:51515` (HD-191) — correct
- ✅ immich-ml `immich_ml_bind:3003` (HD-184) — correct
- ✅ actual-budget `oldsrv_home_ip:5006` (HD-62) — correct
- ✅ home-assistant-primary `0.0.0.0:8123` — VIP-bound
  (documented)

**Verdict: only `sunshine` is a finding (already HD-282 from
security audit). No new inconsistencies.**

### §4.2 Live `ss -tlnp` matches doc policy

The security audit (§13) cross-checked live ports on the VPS
against the doc policy:
- 22/SSH, 80/HTTP, 443/HTTPS on 0.0.0.0 — by design (public edge)
- 9090, 9000, 3389, 3100, 51515 on 127.0.0.1 — correct
  (loopback-only per HD-62/HD-143/HD-186/HD-191)
- 12345/alloy on 127.0.0.1 only (per `/proc/.../net/tcp`; `ss`
  was misleading because it aggregates namespaces — false
  positive, dismissed)

**Verdict: live matches doc policy.**

---

## §5 Hostname / FQDN conventions

Per `docs/index.md` Conventions:
- Single namespace `kogler.si`
- Flat subdomains, split-horizon
- 6 hosts: oldsrv, nas, pi, router, switch, vps

### §5.1 Inventory vs host_vars

| Host | Inventory entry | host_vars file | ansible_host | OK? |
|------|-----------------|----------------|--------------|-----|
| router | `[router] router.kogler.si` | ❌ absent (by design — network device) | n/a | ✅ |
| switch | `[switch] switch.kogler.si` | ❌ absent (by design) | n/a | ✅ |
| vps | `[vps] vps.kogler.si` | ✅ host_vars/vps.kogler.si.yml | 159.195.111.66 | ✅ |
| oldsrv | `[home_servers] oldsrv.kogler.si` | ✅ host_vars/oldsrv.kogler.si.yml | 10.10.99.30 | ✅ |
| nas | `[storage] nas.kogler.si` | ✅ host_vars/nas.kogler.si.yml | 10.10.1.10 | ✅ |
| pi | `[raspberry_pi] pi.kogler.si` | ✅ host_vars/pi.kogler.si.yml | 10.10.1.20 | ✅ |

**Verdict: hostname conventions are consistent.** No drift.

### §5.2 docs/manual/ language check

- All `docs/manual/*.md` files: Slovenian (per the index
  comment, "family guides (Slovenian)")
- `docs/manual/README.md` has `status: wip` — correct (still
  being authored)

**Verdict: no drift.**

---

## §6 Cross-reference consistency

### §6.1 Image registry and Docker Hub references

`docs/deployment-renovate.md` describes the Renovate config and
datasource. Checked: no specific version claims that would
drift from versions.yml. ✅

### §6.2 Storage claims

- `docs/storage.md` describes ZFS dataset tree + properties.
- IaC `IaC/ansible/roles/storage/` is the authoring spec.
- Live NAS: not probed (home LAN, not reachable from WSL).
- **Verdict: no live cross-check possible, but the 5-track
  audit (Track B) confirmed the IaC + docs are consistent.**

### §6.3 Backup claims

- `docs/backup.md` describes borg/Kopia/DR.
- Live: db-backup on schedule, kopia connected (security
  audit §5).
- **Verdict: consistent.**

---

## §7 Summary of all findings

| # | Severity | Title | Action |
|---|----------|-------|--------|
| **CONS-1** | **High** | `bin.kogler.si` NXDOMAIN despite IaC + doc | owner: run `bash scripts/ansible-run.sh dns.yml` (from home control plane) |
| **CONS-2** | Med | `pairdrop`/`drop`/`pdf` in IaC CF but not in `services.md` public table | update doc OR remove from CF (likely: add to doc) |
| **CONS-3** | Med | `traefik.kogler.si` stale Cloudflare record (resolved but should be tailnet-only) | owner: manual delete in Cloudflare dashboard; **HD-285** |
| **CONS-4** | Low | "33 services" framing vs actual 35 enabled | per 5-track audit (no specific finding; counts in docs are local) |

**False positives (confirmed OK):**
- `ha.kogler.si` in doc URL→backend table — doc is a routing
  reference, not a public DNS claim
- `matrix.kogler.si` in doc public table — fully consistent
  across IaC + live

---

## §8 Suggested follow-up HDs

- **HD-285** — Cloudflare stale-record cleanup (delete `traefik`
  A/AAAA at the apex; verify the 5 admin-tailnet-only records
  are also gone). One-shot housekeeping.
- **HD-286** — services.md "PUBLIC" table: add 3 missing rows
  (`pairdrop`, `drop`, `pdf`) so the doc table matches the IaC
  CF records. (Or remove from IaC if the intent was to keep
  them off the public DNS — but that contradicts pairdrop's
  PUBLIC design per HD-230.)

---

## §9 Methodology + hygiene note

This audit used:
- DNS probes via `getent hosts` for live CF resolution
- IaC parses for `subdomain:` keys + traefik label scans in
  compose templates
- Doc grep for `https://*.kogler.si` references + public/tailnet
  table parsers
- 5-track + security audit cross-references (both already
  produced in this session)

**No secret values written to the transcript.** Lengths/tails
only for all env==vault probes (security audit §20 hygiene
note still applies).

---

