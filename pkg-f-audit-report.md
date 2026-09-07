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
---

## LANE B — HD-333 (WG-S2S + tailnet reach for the internal all-app edge) — 2026-09-07

Implementer: subagent (deepseek-v4-flash, Lane B). Do NOT commit (per task). validate-all GREEN.

### (a) What changed + files
1. `IaC/ansible/group_vars/vps.yml` — HD-333 SSOT comment updated: design corrected from manual nftables DNAT to docker compose `ports:` publish + nftables allow; `wg_internal_edge_port: 4443` + `wg_internal_edge_target_ip` (the edge container IP, stripped of /32) kept as SSOT.
2. `IaC/ansible/templates/docker_services/traefik-tailnet/docker-compose.yml.j2` — added `ports:` publishing the internal edge TLS listener (:443) ONLY on the wg-s2s VPS address at `{{ wg_internal_edge_port }}` (4443): `"{{ wg_s2s_vps.ip if (wg_s2s_vps.peer_public_key | default('') | length > 0) else '127.0.0.1' }}:{{ wg_internal_edge_port }}:443"` — same WG-bound guard idiom as kopia-server/prometheus/loki/authentik-LDAP (binds loopback when no tunnel intended).
3. `IaC/ansible/roles/vps-hardening/templates/nftables.conf.j2` — added input allow: `iifname "wg-s2s" ip saddr {{ wg_s2s_vps.router_ip }} tcp dport {{ wg_internal_edge_port }} accept` (HD-313 pattern, scoped to the router peer).
4. `docs/network-vpn.md` §HD-333 — implementation description updated to the compose-publish design + deploy-gated verify checklist (SSOT-IP-free wording for check_doc_ips).
5. `scripts/validate-docker-services.py` — BASE_CTX mocks for `wg_internal_edge_port` + `wg_internal_edge_target_ip` (VPS-only vars, same class as `wg_s2s_vps`).

### (b) Second-listener wiring (mechanism, port, iface, SSOT)
- **Mechanism:** no second WG interface. The existing `wg-s2s` tunnel is reused; the internal edge's **TLS listener is published on the wg-s2s VPS address** via docker compose `ports:` → `<wg-s2s VPS addr>:4443 → container edge-IP:443`. Docker's own PREROUTING DNAT translates host→container, so **no manual nftables DNAT** (same precedent: kopia-server :51515). Host :443 stays the PUBLIC edge; the internal edge rides a dedicated host port 4443.
- **Port:** 4443 (SSOT `wg_internal_edge_port`, vps.yml). **Iface:** wg-s2s (VPS side, `{{ wg_s2s_vps.ip }}`). **Target:** `wg_internal_edge_target_ip` = the edge container IP (pinned, HD-240).
- The existing 51820 listener/peer handshake is untouched (WG handshake happens on the tunnel's own UDP 51820 regardless of the TCP app port).

### (c) Router-side reach analysis
- The RB4011 peer routes the `wg-s2s` /30 out wg-s2s (converge line: `/ip route add dst-address=</30> gateway=wg-s2s`), and its forward chain has **no final catch-all drop** for home→wg (last rules are the Comtrend modem block) → RouterOS forward default-accept → home→`<wg-s2s VPS addr>:4443` naturally routes out wg-s2s.
- **NAT:** converge srcnat only masquerades `out-interface=pppoe-telekom` (WAN). Home→wg-s2s keeps its Home-VLAN source IP; the VPS nftables allow scope is `ip saddr {{ wg_s2s_vps.router_ip }}` (the router's wg-s2s side), which is the source the tunnel delivers — works regardless of home origin. No router-side change needed.
- **Precedent:** kopia-agent already connects home→`wg_s2s_vps.ip:51515` (same pattern), so the path is proven live.

### (d) nftables rule
`iifname "wg-s2s" ip saddr {{ wg_s2s_vps.router_ip }} tcp dport {{ wg_internal_edge_port }} accept` (4443), added in vps-hardening/templates/nftables.conf.j2 input chain — scoped to the router peer, defense-in-depth (docker DNAT is the primary path). **NOTE:** nftailes is default-deny inbound; docker-published ports on the wg address are DNAT'd pre-filter, so the rule is belt-and-suspenders per HD-313; it also documents intent.

### (e) Deploy-gated verify checklist (written into docs/network-vpn.md §HD-333)
1. `ss -ltnp | grep :{{ wg_internal_edge_port }}` → bound to the wg-s2s VPS address (after VPS `docker_services` + `vps-hardening` converge).
2. From a scoped home host over WG (oldsrv/nas/pi): `curl -k -I https://<wg-s2s VPS addr>:4443` → HTTP/2 302 / TLS response.
3. Split-horizon alternative once HD-334 seeds: `curl -k -I https://kogler.si` over the tunnel / `https://<edge container IP>:4443` with Host header.
4. Tailnet path unchanged: tailnet device → `https://stats.kogler.si` / `https://<app>.ts.kogler.si`.
5. Tailscale ACL (`policy.hujson`) already allows family nodes → `tag:sidecar:443`; no extension needed for the existing owner set.

### (f) Notes for orchestrator/deploy
- **Reach scope:** the VPS WG peer `allowed_ips` (HD-155 least-access: nas/ha-vip/oldsrv/pi/router/switch) means the internal edge via WG is reachable ONLY from those scoped home infra hosts. **End-user devices (laptop/phone/tablet) use the tailnet path** (sidecar + headscale ACL) — WG is the infra/automation path, not the family path. If family-from-home-over-WG is ever wanted, that is a separate allowed_ips/ACL decision (do NOT broaden silently).
- **Deploy touchpoints:** VPS converge with `--tags docker_services,hardening` (traefik-tailnet + nftables apply). No router converge needed. No live host was touched.
- **Validator:** added mocks keep `validate-docker-services.py` green (58 templates valid).

---

## Docs + todo lifecycle update (2026-09-07, docs lane — uncommitted)

Docs/todo lifecycle for Pkg F (HD-331-334), reflecting **IaC-authored + validate-green + reviewer-approved but NOT yet live** (commits 3e9385d/50a7336/9fbe58e). validate-all **green** (incl. check_doc_map 75 docs all links resolve, check_generated_suffix 4 generated OK, no `-generated.md` touched). Files changed:
- `docs/services-traefik.md` — §Edge model / implementation-spec: added "**Status: IAC-AUTHORED (not yet live — deploy-gated on VPS `docker_services` converge)**" line documenting the `public:` flag + label gate + internal-edge routes + sso router; kept the existing `Live since 2026-08-22` public-edge line intact (that part is live; only the NEW internal-edge/publish work is deploy-gated).
- `docs/network-vpn.md` — §HD-333: marked **IAC-AUTHORED (not yet live — deploy-gated on VPS `docker_services` + `vps-hardening` converge)**; the impl + deploy-gated verify checklist (added in 9fbe58e) is retained.
- `todo.md` — HD-332 + HD-333 rows: status now "**IAC DONE 2026-09-07, deploy-gated on VPS converge**" with authored details (label gate, sso router, :4443 publish, nftables rule, SSOT vars) + ⏳ marked **pending LIVE CONVERGE**. HD-334 row: "**IAC AUTHORED 2026-09-07, deploy-gated on VPS + router + Pi converge**" (Pi-first VLAN-10 DNS + `vpn`/`home`/`dns` seed records) — ⏳ pending LIVE CONVERGE + `dig @<pi> vpn/home/dns` verify. Pkg F §2.1a table row: HD-332/333 = IAC DONE, HD-334 = IaC authored, deploy = VPS+router+Pi converges. HD-331 unchanged (DECIDED, locked). No rows closed/deleted; depend links preserved.
- `README.md` / `prompt.md` — NOT touched (no Pkg F pointer in README; prompt.md is another handoff's ownership per default).
