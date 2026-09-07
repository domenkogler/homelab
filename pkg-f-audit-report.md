# Pkg F — Edge-model WIP audit report (2026-09-07)

Auditor: subagent (deepseek-v4-flash) · worktree: `/home/domen/source/homelab-wt-20260904-0950`
Scope: audit HD-331/332/333/334 WIP (commit `3e9385d` rebased on main `51c8ed8`) + fix worktree defects.
Do NOT commit (per task). validate-all at end: **GREEN (all validators passed)**.

## (a) Findings per checklist item

### 1. Duplicate `middlewares:` key in routes.yml.j2 — **FIXED**
- Two adjacent `middlewares:` sections at lines 453-454 (both `redirect-to-https`), introduced by the WIP
  commit (main has exactly ONE `middlewares:`). Traefik file-provider YAML with a duplicate top-level
  `middlewares:` key is a schema defect (merge ambiguity / potential reload failure).
- **Edit:** collapsed to a single `middlewares:` block. Verified: `grep -n "^  middlewares:"` → 1 occurrence.
- The real Authentik/CrowdSec chains correctly live in the sibling `middlewares.yml.j2` (not duplicated in
  routes.yml) — confirmed by Docker-compose mount `./dynamic:/etc/traefik/dynamic:ro` which loads all three
  files (routes.yml + middlewares.yml + tls.yml) into one file-provider directory namespace.
- Best-effort YAML parse (jinja stripped): `http:{routers:49→51, middlewares:[redirect-to-https], services:20→21}` OK.

### 2. `public:` flag was DEAD — **WIRED + validator updated**
- `public: true` = public-edge (Docker-label routes). `public: false`/absent = internal-only (SSOT spec,
  `docs/services-traefik.md` §Implementation spec HD-332).
- **Before:** 4 VPS apps flagged `public: false` (grafana, dozzle, metabase, crowdsec-web-ui) still carried
  `traefik.enable: "true"` + public router labels → they were served by the MAIN public edge despite the
  internal-only docs. That is an exposure mismatch AND violates the spec ("public edge serves ONLY public:true").
- **Edits (4 templates):** grafana / dozzle / metabase / crowdsec-web-ui `docker-compose.yml.j2` — labels block
  wrapped in `{% if not (svc.public is defined and not svc.public) %}`; explicit `public: false` renders
  `traefik.enable: "false"` + an INTERNAL-ONLY comment; absent flag (legacy arr-stack/safe entries) renders the
  original public labels unchanged. Verified render: grafana (public:false) → `traefik.enable: "false"`;
  homepage (public:true) → unchanged labels.
- **Validator edit (`scripts/validate-docker-services.py`):** the web-label law (`traefik.enable` +
  `traefik.http.routers.*` required) is skipped for explicitly `public: false` web apps, and an **inverse
  check** fires if a `public: false` app renders `traefik.enable: true` (prevents silent re-exposure).
  Absent flag = legacy behavior preserved (arr-stack labels stay valid; `traefik` edge stays public).
  Used `is defined` guard (the validator's `mock_default` overrides jinja's `default`, so `| default(...)`
  cannot rescue a missing dict key under StrictUndefined — direct lesson).
- **Result:** full gate `PASS: 58 docker_services templates valid`.

### 3. Missing internal router for `authentik` (sso.kogler.si) — **FIXED**
- ALL 13 other `public: true` apps have an internal-edge router; **sso was missing** → the internal edge's
  forward-auth chains redirect unauthenticated users to `sso.kogler.si`, but with no internal sso route the
  redirect would bounce over WAN to the PUBLIC sso (slow / WAN-dependent login on the internal edge).
- **Edits (routes.yml.j2):** added `sso-int-kogler` (websecure, `crowdsec-only`, `authentik-backend`, tls) +
  `sso-int-http-redirect` (web, redirect-to-https) + `authentik-backend` service →
  `http://authentik-server:9000` (matches compose service name + port, joins traefik-public).

### 4. Backends — all CORRECT (verified)
Every `*-backend` service resolves to the real compose **SERVICE name** (Docker DNS) + correct port:
authentik-server:9000, n8n:5678, chat:80, crowdsec-web-ui:3000, technitium:5380, dsh:3080, forgejo:3000,
headscale:8080, homepage:3000, immich-server:2283, dozzle:8080, matrix:8008, onlyoffice-docs:80,
open-webui:8080, opencloud:9200, pairdrop:3000, pi-dev:8080, metabase:3000, grafana:3000, stirling-pdf:8080,
zipline:3000. Cross-checked against each compose's service names + `loadbalancer.server.port`.

### 5. Internal-only apps keep their routes + no duplicate public exposure
- stats/logs/csui/sec/traefik/dsh/pi-dev/auto all retain their `.ts` twin routers + `*-kogler`/`*-http-redirect`
  routers (verified: each has 2–3 routers, `.ts` names intact).
- They do NOT gain public Docker-label routes on the main edge (grafana/dozzle/metabase/crowdsec-web-ui now
  render `traefik.enable: "false"` via the `public: false` gate). n8n already `labels: {}`.

### 6. Router Host collisions — NONE
- 32 unique hosts across 51 routers; every "collision" is the intentional websecure+http-redirect pair on the
  same host (different entrypoints) — expected. No host appears in two DIFFERENT apps. Same-zone split-horizon
  names (`dns.kogler.si`, `vpn.kogler.si`, `home.kogler.si`) are served once per edge (internal route) and are
  public CNAMEs on Cloudflare for those that are public — consistent.

### 7. HD-334 touches — consistent
- `technitium-seed`: `vpn.kogler.si`/`home.kogler.si`/`dns.kogler.si` → `dns_primary_ip` (VPS public IP),
  matching `docs/network-dns.md` HD-334 spec exactly (control-plane/home login + Technitium UI; VPS public IP
  per the public CNAMEs). Correct — NOT `ha_vip`.
- Router role + `rb4011_converge.rsc.j2`: Pi-first DNS (`dns_tertiary_ip, dns_primary_ip, dns_secondary_ip`)
  only for VLAN id==10 (Home); all other VLANs keep VPS-first. Both files consistent.

## (b) Exact edits made (files changed, worktree only — NOT committed)

1. `IaC/ansible/templates/docker_services/traefik-tailnet/dynamic/routes.yml.j2`
   - collapsed duplicate `  middlewares:` (lines 453-454) → one block
   - + `sso-int-kogler` + `sso-int-http-redirect` routers
   - + `authentik-backend` service (`http://authentik-server:9000`)
2. `IaC/ansible/templates/docker_services/grafana/docker-compose.yml.j2` — `public: false` gate on labels
3. `IaC/ansible/templates/docker_services/dozzle/docker-compose.yml.j2` — same gate
4. `IaC/ansible/templates/docker_services/metabase/docker-compose.yml.j2` — same gate
5. `IaC/ansible/templates/docker_services/crowdsec-web-ui/docker-compose.yml.j2` — same gate
6. `scripts/validate-docker-services.py` — web-label law honors `public:` flag (skip + inverse check)

## (c) Remaining gaps / orchestrator notes

1. **Operational effect of the public:false label gate:** after the next VPS `docker_services` converge,
   grafana/dozzle/metabase/crowdsec-web-ui will STOP being served by the MAIN public edge (public labels off).
   They remain reachable on the internal `traefik-tailnet` edge (stats/logs/sec/csui routes already exist).
   This matches the documented intent (tailnet-only admin dashboards) + the HD-332 spec, but it IS a live
   exposure change — orchestrator should call it out in the deploy/verify step + ensure the Cloudflare
   records are already removed/absent (the SSOT comment flags stats/sec/traefik/auto as owner-delete pending).
2. **HD-333 (WG listener + nftables + tailnet ACL) is NOT yet implemented** in the WIP — vps.yml has only the
   `wg_internal_edge_port: 4443` + `wg_internal_edge_target_ip` sketches. Remainder of Pkg F, separate lane.
3. `public:` flag absent on `home_servers.yml`/`raspberry_pi.yml` entries is intentionally NO-OP (legacy
   behavior preserved); only explicit `public: false` gates labels. Document when the flag rolls to those sets.
4. The validator change is SSOT-consistent but is a repo-gate change — reviewer/orchestrator should eyeball it.
5. No commit made (per task). Full worktree diff vs main = 10 files, +398/−40.