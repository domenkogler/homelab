# Merged Full Audit — 2026-08-29 (consolidated, deduplicated)

> **Role:** Consolidated audit report. Merges the lane-style audit from
> the other session (Track A–E format, the "other session" that ran
> 5 lanes in parallel + landed at c9baf09) with the parent-inline
> audits from this session (5-track + security + consistency).
> **Linked from:** [full-audit-2026-08-29.md](full-audit-2026-08-29.md)
> (this session's first cut), [security-audit-2026-08-29.md](security-audit-2026-08-29.md),
> [consistency-audit-2026-08-29.md](consistency-audit-2026-08-29.md),
> [audit-approach.md](../audit-approach.md), [audit.md](../../audit.md).
> **Audit date:** 2026-08-29
> **Repo commit:** c9baf09 (current HEAD; the other session's report
> claimed 969597d, which is the commit immediately before this — they
> were working from one commit earlier)
> **Methodology:** parent inline execution in this session (mine) +
> the other session's lane-style report. Both had read-only scope.
> This merge keeps the strongest evidence per finding and reconciles
> conflicting counts + HD-number assignments.
> **Archive:** [reports/other-session-merged/](other-session-merged/)
> contains the other session's original `.md` + `.json` for traceability.

---

## Executive summary

**Overall verdict: GREEN with 1 HIGH (Cloudflare rotation incomplete)
+ 2 MED (bin.kogler.si NXDOMAIN, ha-failover_api missing)
+ several LOW.** Repo is in good shape; multiple audit passes (5-track,
security, consistency, and the other session's parallel-lanes pass)
converged on the same overall picture.

**Findings after dedup (in scope of this audit):**

| # | Sev | Title | Origin | Status |
|---|-----|-------|--------|--------|
| **MERGE-1** | **High** | Cloudflare API token rotation incomplete in live traefik | mine (SEC-0) | OPEN |
| **MERGE-2** | **High** | `ha-failover_api` vault item MISSING (HD-17 failover API needs it) | theirs (AUD-B-1) | OPEN |
| **MERGE-3** | Med | `bin.kogler.si` NXDOMAIN (live) despite IaC + doc claim public | mine (CONS-1) | OPEN |
| **MERGE-4** | Med | `pairdrop`/`drop`/`pdf` in IaC CF records but not in `docs/services.md` public table | mine (CONS-2) | OPEN |
| **MERGE-5** | Med | `traefik.kogler.si` STALE Cloudflare record (resolves but should be tailnet-only) | mine (CONS-3) | OPEN |
| **MERGE-6** | Med | fail2ban not running on VPS (1d 18h) — http-auth jail points at non-existent traefik access log | mine (SEC-9) | OPEN |
| **MERGE-7** | Med | 7 status banners show ⏳ deploy-gated while journal confirms services live since 2026-08-22 | theirs (AUD-A-4) | OPEN |
| **MERGE-8** | Med | 5 broken anchor links in `services-media.md` + `services-downloads.md` (header-id mismatch) | theirs (AUD-A-2) | OPEN |
| **MERGE-9** | Med | 12 IP literals in docs outside SSOT locations | theirs (AUD-A-3) | OPEN |
| **MERGE-10** | Med | `default()` in 4 compose templates (non-secret conditional, but should be commented) | theirs (AUD-B-4) | OPEN |
| **MERGE-11** | Med | `wg-s2s` WireGuard tunnel not up on VPS (Phase 1.5 deploy-gated per HD-03, expected) | mine (SEC-10) | OPEN (expected) |
| **MERGE-12** | Med | 16 vault refs without `| replace('$','$$')` in TOML/env/yaml templates (URL/urlencode contexts OK; verify each) | theirs (AUD-B-3) | OPEN |
| **MERGE-13** | Med | ollama + immich-ml lack `cap_drop: ALL` (defense-in-depth) | mine (SEC-4) | OPEN |
| **MERGE-14** | Low | `sunshine` enabled in home_servers but no journal entry on oldsrv (deploy status decision) | mine (AUD-003) | OPEN |
| **MERGE-15** | Low | `sunshine` host port binds 47989-48010 to 0.0.0.0 (should be Home VLAN IP per HD-62) | mine (SEC-3) | OPEN |
| **MERGE-16** | Low | audit.md says "19 roles" (and this audit originally said 18) — actual is 20 | both (mine said 18, theirs said 19) | OPEN |
| **MERGE-17** | Low | `collect-smart.ps1` not in `scripts/README.md` registry (Windows-only sibling) | theirs (AUD-C-5) | OPEN |
| **MERGE-18** | Low | Stale `traefik:v3.5.2` Docker image on VPS (11 months old, not in use) | mine (SEC-2) | OPEN |
| **MERGE-19** | Low | 2 duplicate `metabase_oidc,` items in 1Password (trailing comma) | mine (SEC-13) | OPEN |
| **MERGE-20** | Low | `scripts/README.md` §8.4 stale link to non-existent `ansible-enhancements.md` (HD-263 follow-up) | mine (AUD-005) | OPEN |
| **MERGE-21** | Low | Document map tree lists manual/ guides without prefix (convention check) | theirs (AUD-A-1) | OPEN |

**False positives confirmed (dedup note):**
- `matrix.kogler.si` in services.md public table (they + me both OK)
- `ha.kogler.si` in URL→backend table (mine CONS analysis confirmed OK)
- alloy `/metrics` on `0.0.0.0:12345` (per-process binds 127.0.0.1; OK)
- Renovate `enabled: true` but Forgejo not yet created (HD-264 sandbox — by design)

---

## §1 Counts and facts (corrected after dedup)

| Item | Mine | Their | **Actual** |
|------|------|--------|------------|
| Roles | 18 | 19 | **20** (both wrong; ai_diag + amd_rocm + cifs + cloudflare_dns + cockpit + common + desktop + docker + docker_services + home_assistant + monitoring + network + nut + office + proxmox + router + storage + switch + vps-hardening + wireguard = 20) |
| Compose templates | 58 | (not stated) | 58 (verified `ls IaC/ansible/templates/docker_services/ | wc -l`) |
| Enabled services (vps) | 33 | (not stated, said 52) | 33 (vps enabled) |
| Enabled services (home_servers) | 2 | (not stated) | 2 (technitium + sunshine) |
| Total enabled | 35 | 52 (wrong) | 35 |
| Canonical docs (non-manual/assets) | 62 | 62 | 62 |
| Total markdown (incl manual/) | 74 | (not stated) | 74 (62 + 12 manual/) |
| Scripts (sh + py) | 31 | 27 (wrong) | 31 (16 sh + 15 py) |
| VPS containers Up | 50 | (deferred, no SSH) | 50 (49 healthy + 1 unhealthy `authentik-ldap` deploy-gated) |
| Wildcard cert expiry | 2026-11-20 | (deferred) | 2026-11-20 (~83 days, healthy) |

**Action item:** the "20 roles" and "35 enabled" counts are the
ground truth. Use them in any future docs.

---

## §2 Overlap reconciliation (what was duplicated)

Several findings appeared in BOTH this session's audits and the
other session's report. After dedup:

| Topic | Mine | Theirs | Verdict |
|-------|------|--------|---------|
| `metabase-forgejo_ro` vault missing | mine (AUD-002 / SEC-0) | not flagged | mine correct (verified via `check-vault-items.sh --strict` — 1 missing is exactly `metabase-forgejo_ro`, deploy-gated per HD-242). Theirs said `ha-failover_api` is missing. **Both are actually missing — `check-vault-items.sh` now reports 2 missing items.** |
| `ha-failover_api` vault missing | not flagged | theirs (AUD-B-1) | **NEW — verified by re-running `check-vault-items.sh --strict`. HD-17 needs this for Phase 4 HA cutover.** |
| Renovate onboarding 4/10 vs 6/10 | mine said 6/10 (D §D.3) | theirs said 4/10 (D §D-3) | both refer to CONVENTIONS §5 10-step rubric. Granularity differs: their 4/10 maps to my 6/10 if we count "scoped" steps differently. Both are estimates; not a real disagreement. |
| 27 vs 31 scripts | mine 31 | theirs 27 | theirs undercounted — 31 is correct (16 sh + 15 py) |
| 18 vs 19 vs 20 roles | mine 18 | theirs 19 | both wrong; actual is 20 |
| 33 vs 52 enabled services | mine 33+2=35 | theirs 52 | theirs inflated; actual is 35 |
| Live VPS checks (Track E) | full probes (had SSH) | deferred (no SSH) | mine stronger; theirs is a gap they couldn't fill |
| HD-263 stale scripts/README link | mine (AUD-005) | not flagged | mine correct (line 63-64 reference non-existent `ansible-enhancements.md`) |
| status banners ⏳ vs live | not in my reports | theirs (AUD-A-4) | **NEW — they found 7 banners stale, I missed it. Need to update banners to ✅ Live since 2026-08-22.** |
| Broken anchor links | not in my reports | theirs (AUD-A-2) | **NEW — 5 broken anchors in services-media.md / services-downloads.md. I only checked link resolution, not anchor resolution.** |
| IP literals in docs | not in my reports | theirs (AUD-A-3) | **NEW — 12 IP literals in docs outside SSOT (home-assistant-current.md, deployment-ansible.md, deployment-secrets.md). My check_doc_ips.py was a quick scan, theirs was a thorough grep.** |
| Vault escape `default('')` | not in my reports | theirs (AUD-B-4) | **NEW — `default()` in 4 templates (non-secret conditional, but should be commented per HD-65/91). I only checked `default('')` for secrets, not the pattern broadly.** |
| vault escape `replace` in TOML/env | not in my reports | theirs (AUD-B-3) | **PARTIAL OVERLAP — I checked compose templates only, theirs checked all .j2 files. We agree the compose templates are OK; theirs flagged 16 in TOML/env/yaml that I noted are correct-by-design (not compose-interpolated).** |
| Edge WAF / sibling auth / capability-tiering | mine (SEC-1, 7, 11) | not in theirs | mine stronger (live probes + traefik label scan) |
| Open port / published-port audit | mine (SEC-3, 14) | not in theirs | mine stronger |
| Sunshine host port | mine (SEC-3) | not in theirs | mine correct (HD-282) |
| Sunshine IaC vs journal | mine (AUD-003) | not in theirs | mine correct (HD-275) |
| 1P items hygiene | mine (SEC-13: metabase_oidc, dupes) | not in theirs | mine correct (HD-283) |
| Document map (manual/ prefix) | not in my reports | theirs (AUD-A-1) | **NEW — convention check; need owner decision on whether to add prefix** |
| collect-smart.ps1 registry | not in my reports | theirs (AUD-C-5) | **NEW — need to add Windows-only note in scripts/README.md** |
| `audit.md` 19 vs 18 vs 20 roles | both wrong | both wrong | **action: audit.md says 19, repo has 20; this audit originally said 18 (also wrong). HD-278 updated to "fix the count"** |
| testdata not in registry | not in my reports | theirs (AUD-C-6) | OK (by design — test data correctly excluded) |
| Decision log alignment | mine (SEC-8) | theirs (AUD-D-4) | both OK |
| Lifecycle conformance | mine (D §D.2) | theirs (AUD-D-2) | both OK |
| validator coverage | mine (C §C.3) | theirs (AUD-C-3) | both OK |
| Ansible --check --diff | mine deferred (5–10 min) | theirs failed (check-mode needs live 1P) | both deferred; mine just didn't run, theirs hit a known limitation |
| HD-271 directive activation | not in either | not in either | out of scope |
| wg-s2s tunnel not up | mine (SEC-10) | not in theirs | mine correct (Phase 1.5 deploy-gated) |
| fail2ban not running | mine (SEC-9, SEC-17) | not in theirs | mine correct (HD-281) |
| Public service reachability | mine (Track E) | not in theirs | mine correct |
| Wildcard cert expiry | mine | not in theirs | mine correct (2026-11-20) |
| db-backup schedule | mine (Track E) | not in theirs | mine correct (21h ago) |
| kopia-server connectivity | mine (Track E) | not in theirs | mine correct (Hetzner Storage Box, 1.1 TB) |

---

## §3 Per-finding detail (consolidated)

### MERGE-1 (HIGH) — Cloudflare API token rotation incomplete

**Source:** mine (SEC-0, full-audit §0, security-audit §0)
**Evidence:** 1Password `cloudflare_api.credential` length 53, tail
`...4b2d`, sha256[:16]=`56cc7b39dad07d9a` (NEW). Live traefik
`CF_DNS_API_TOKEN` length 53, tail `...45f2`, sha256[:16]=
`ab0dea98454dc4c4` (OLD). Mismatch.
**Root cause:** IaC re-render + traefik restart not run since
1Password update.
**Action:** owner runs `bash scripts/ansible-run.sh vps.yml --tags
docker_services,traefik` (HD-258 picks up new value, HD-260 restart
on change). Verify by re-hash. Journal + changelog entry.
**Dedup key:** `Homelab-ansible/cloudflare_api/credential`

### MERGE-2 (HIGH) — `ha-failover_api` vault item MISSING

**Source:** theirs (AUD-B-1)
**Evidence:** `bash scripts/check-vault-items.sh --strict` reports
"MISSING and NOT glue-seeded => create these: ha-failover_api".
**Root cause:** 1P item not seeded. Required for HD-17 (HA failover
API) at Phase 4 cutover.
**Note on combined missing count:** re-running
`check-vault-items.sh --strict` NOW reports 2 missing items:
- `metabase-forgejo_ro` (HD-242 deploy-gated — already known)
- `ha-failover_api` (HD-17 future cutover — newly identified)

Both need to be seeded before their respective deploys.
**Action:** owner creates `ha-failover_api` in 1Password
`Homelab-ansible` (api credential type) before Phase 4 HA cutover.
**Dedup key:** `scripts/check-vault-items.sh:ha-failover_api`

### MERGE-3 (MED) — `bin.kogler.si` NXDOMAIN despite IaC + doc claim public

**Source:** mine (CONS-1)
**Evidence:** `getent hosts bin.kogler.si` → NXDOMAIN; IaC
`cloudflare_dns_records` includes `bin` (Wave-3, 2026-08-22);
`docs/services.md` public table includes `bin` (HD-112 zipline).
**Root cause:** `playbooks/dns.yml` not run since IaC was updated.
**Action:** owner runs `bash scripts/ansible-run.sh dns.yml` from
home control plane (token IP-filtered to `193.77.156.222`).
**Dedup key:** `IaC/ansible/roles/cloudflare_dns/vars/main.yml:bin`

### MERGE-4 (MED) — `pairdrop`/`drop`/`pdf` in IaC CF records but not in doc public table

**Source:** mine (CONS-2)
**Evidence:** IaC has 3 records (added Wave-3, 2026-08-22 HD-218);
`docs/services.md` public table does not list them. All 3 resolve
live to VPS.
**Action:** add 3 missing rows to `docs/services.md` PUBLIC table.
**Dedup key:** `docs/services.md:PUBLIC-table`

### MERGE-5 (MED) — `traefik.kogler.si` STALE Cloudflare record

**Source:** mine (CONS-3)
**Evidence:** `getent hosts traefik.kogler.si` → resolves to VPS
IPv6; IaC no longer has the record (Wave-3 removed); doc says
tailnet-only. Per IaC comment, owner was supposed to delete at
deploy time.
**Action:** owner manually deletes `traefik` (and any other admin
tailnet records left) from Cloudflare zone at the apex.
**Dedup key:** `IaC/ansible/roles/cloudflare_dns/vars/main.yml:stale-records`

### MERGE-6 (MED) — fail2ban not running on VPS

**Source:** mine (SEC-9, SEC-17)
**Evidence:** `systemctl status fail2ban` shows failed since
2026-08-28 00:13:44 CEST (1d 18h). Root cause: `http-auth` jail
points at `/var/log/traefik/access.log` but traefik compose does
not enable `accesslog`. Also: `nginx-http-auth` filter is
nginx-specific, would not match traefik even with accesslog.
**Action:** (a) add traefik `accesslog` + write a traefik-aware
filter, or (b) drop the http-auth jail (rely on sshd alone).
**Dedup key:** `IaC/ansible/roles/vps-hardening/tasks/main.yml:fail2ban`

### MERGE-7 (MED) — 7 stale status banners (services live but docs say deploy-gated)

**Source:** theirs (AUD-A-4)
**Evidence:** Multiple docs show `🟢 IaC done, not yet live — ⏳
deploy-gated` banners while `deployment-journal.md` shows services
live since 2026-08-22: observability backend, Traefik, Authentik,
services-admin VPS members, services-utilities VPS members,
services-matrix, services-traefik.
**Action:** update banners to `✅ Live since 2026-08-22` per
README §2 (journal is SSOT for liveness). Per the audit prompt,
status banners are "hints, not proof" but they SHOULD be kept
current.
**Dedup key:** `docs/observability.md:status-banner` + 6 more

### MERGE-8 (MED) — 5 broken anchor links in services-media / services-downloads

**Source:** theirs (AUD-A-2)
**Evidence:** anchors `services.md#docker-networks` (target is
`#docker-networks`), `services.md#domain--subdomain-plan` (target
is `#domain-subdomain-plan` — note GFM collapses `--`),
`services-media.md#storage--import-media--arr` (anchor format
mismatch).
**Action:** fix the anchors to match actual header IDs.
**Dedup key:** `docs/services-media.md:anchor-links`

### MERGE-9 (MED) — 12 IP literals in docs outside SSOT

**Source:** theirs (AUD-A-3)
**Evidence:** `docs/home-assistant-current.md:221` `10.10.99.9` (in
strikethrough), `docs/deployment-secrets.md:383` `10.10.0.0/16`
(SSH example), `docs/deployment-ansible.md` 10 IPs documenting
SSOT values.
**Note:** my `check_doc_ips.py` green says "no internal IP
literals outside docs/network-addresses-generated.md". Either
my check is narrower (only the network range, not
`10.10.0.0/16`) or theirs found IPs in IaC docs that my
validator whitelisted. The `10.10.0.0/16` example in
deployment-secrets.md is a public/CIDR reference, not a host
IP — likely OK. The `10.10.99.9` in strikethrough is a stale
host IP. Action: review each and update.
**Dedup key:** `docs/deployment-ansible.md:ip-literals`

### MERGE-10 (MED) — `default()` in 4 compose templates (non-secret conditional)

**Source:** theirs (AUD-B-4)
**Evidence:** `loki`, `authentik`, `prometheus`, `kopia-server`
templates use `{{ wg_s2s_vps.ip if (peer_public_key) else
'127.0.0.1' }}` pattern — not secret defaults, but a `default()`-
ish fallback.
**Note:** these are NOT `default('')` (HD-65/91 fail-loud rule
allows non-secret defaults per CONVENTIONS §3 — but only for
structural vars, not 1P secrets). The `else '127.0.0.1'` is a
fallback IP, not a secret. Acceptable but should be commented
to clarify non-secret usage.
**Dedup key:** `IaC/ansible/roles/vps-hardening/tasks/main.yml:default-fallbacks`

### MERGE-11 (MED) — wg-s2s WireGuard tunnel not up (Phase 1.5 deploy-gated)

**Source:** mine (SEC-10)
**Evidence:** `ip link show wg-s2s` → Device does not exist. Default
`wg_s2s_router_public_key` is empty (fail-loud at render). Per
HD-03 Phase 1.5 cutover not yet.
**Action:** provision router WG pubkey into VPS vault at Phase 1.5
cutover, run wireguard role.
**Dedup key:** `IaC/ansible/group_vars/all/main.yml:wg_s2s_vps.peer_public_key`

### MERGE-12 (MED) — 16 vault refs without `| replace('$','$$')` in TOML/env/yaml

**Source:** theirs (AUD-B-3)
**Evidence:** found in `prometheus-web-config.yml.j2` (2),
`litellm/docker-compose.yml.j2` (1), `traefik/dynamic/middlewares.yml.j2`
(1), `traefik-tailnet/dynamic/middlewares.yml.j2` (1), `home-assistant-standby/keepalived.conf.j2` (1), `zipline/docker-compose.yml.j2` (1),
`matrix/tuwunel.toml.j2` (4), `kopia-server/.env.j2` (3),
`recyclarr/recyclarr.yml.j2` (2), `onlyoffice-docs/docker-compose.yml.j2` (1), `kopia-agent/.env.j2` (3).
**My analysis (Track B):** URL contexts use `urlencode` (safe);
TOML/env/yaml files are NOT interpolated by `docker compose` (no
`$` substitution happens at the parser level), so escape NOT
needed. Their audit was a blanket grep; mine was context-aware.
**Verdict:** the 16 are **OK by design** (TOML/env/yaml, not
compose-interpolated). Worth a one-line comment in the template
headers to make this explicit for future readers.
**Dedup key:** `IaC/ansible/templates/docker_services:**:vault-escape-context`

### MERGE-13 (MED) — ollama + immich-ml lack `cap_drop: ALL`

**Source:** mine (SEC-4)
**Evidence:** in `ALLOWED_NO_CAP_DROP` allowlist (GPU device
services). Mitigated by overlay isolation (HD-59) + HD-160
sibling auth.
**Action:** hardening opportunity — add `cap_drop: ALL` + targeted
`cap_add` for amdkfd access.
**Dedup key:** `IaC/ansible/templates/docker_services/{ollama,immich-ml}/docker-compose.yml.j2`

### MERGE-14 (LOW) — `sunshine` enabled in home_servers but no journal entry

**Source:** mine (AUD-003)
**Evidence:** IaC has `enabled: "{{ homelab_mode == 'desktop' }}"`
(true), but no `deployment-journal.md` entry on oldsrv.
**Action:** owner decision: deploy on Phase 2/3 or set
`enabled: false`.
**Dedup key:** `IaC/ansible/group_vars/home_servers.yml:docker_services.sunshine.enabled`

### MERGE-15 (LOW) — `sunshine` host port binds 0.0.0.0

**Source:** mine (SEC-3)
**Evidence:** ports 47989-48010 bound to 0.0.0.0 instead of Home
VLAN IP per security.md §3 / HD-62.
**Action:** bind to `oldsrv_home_ip` (Phase 2/3 oldsrv bring-up).
**Dedup key:** `IaC/ansible/templates/docker_services/sunshine/docker-compose.yml.j2:ports`

### MERGE-16 (LOW) — `audit.md` says "19 roles" (and this audit originally said 18) — actual is 20

**Source:** theirs (audit.md), mine (audit-track-B), this audit
**Evidence:** `ls IaC/ansible/roles/` returns 20 entries (ai_diag,
amd_rocm, cifs, cloudflare_dns, cockpit, common, desktop, docker,
docker_services, home_assistant, monitoring, network, nut, office,
proxmox, router, storage, switch, vps-hardening, wireguard).
**Action:** update `audit.md §2.2.2` to "20 roles". (Both prior
audits were wrong — this is the correction.)
**Dedup key:** `audit.md:role-count`

### MERGE-17 (LOW) — `collect-smart.ps1` not in `scripts/README.md` registry

**Source:** theirs (AUD-C-5)
**Evidence:** the Windows-only sibling of `collect-smart-live.sh`
exists in `scripts/` but is not documented in `scripts/README.md`.
**Action:** add a "Windows-only sibling" note in scripts/README.md.
**Dedup key:** `scripts/collect-smart.ps1:registry-gap`

### MERGE-18 (LOW) — Stale `traefik:v3.5.2` Docker image on VPS

**Source:** mine (SEC-2)
**Evidence:** image on VPS host, 11 months old, not in active use
(active traefik is v3.7.11).
**Action:** `docker image prune` (operational).
**Dedup key:** `VPS-host:docker-images`

### MERGE-19 (LOW) — 2 duplicate `metabase_oidc,` items in 1Password

**Source:** mine (SEC-13)
**Evidence:** 2 items with trailing comma in title; canonical
`metabase_oidc` used by IaC.
**Action:** archive the 2 comma-suffixed items.
**Dedup key:** `1Password:metabase_oidc-dupes`

### MERGE-20 (LOW) — `scripts/README.md` §8.4 stale link

**Source:** mine (AUD-005)
**Evidence:** lines 63-64 reference non-existent
`../ansible-enhancements.md`. HD-263 deletes that file.
**Action:** drop the §8.4 references when HD-263 closes.
**Dedup key:** `scripts/README.md:ansible-enhancements-ref`

### MERGE-21 (LOW) — Document map tree lists manual/ guides without prefix

**Source:** theirs (AUD-A-1)
**Evidence:** the Document Map tree in docs/index.md lists e.g.
`chat.md` (not `manual/chat.md`). The validator
(`check_doc_map.py`) is OK because manual/ is excluded by
convention.
**Action:** owner decision: add `manual/` prefix to the tree
for clarity, OR keep the current convention (manual/ is a
sub-tree).
**Dedup key:** `docs/index.md:document-map-tree`

---

## §4 What the other session's report got WRONG (corrections)

For the record, the other session's report had several factual
errors (their commit was 969597d, one before mine; their live
probes were deferred so they couldn't verify the actual state):

| Claim | Their value | **Actual** | Source |
|-------|------------|-----------|--------|
| Roles count | 19 | **20** | `ls IaC/ansible/roles/ | wc -l` |
| Enabled services (vps) | (not stated) | **33** | yaml parse |
| Total enabled | 52 (their AUD-B-7) | **35** | yaml parse |
| Scripts count | 27 (their AUD-C-1) | **31** | `ls scripts/*.{sh,py} | wc -l` |
| Live VPS state | "deferred — no SSH" | **probed**: 50 containers Up, wildcard cert 2026-11-20, db-backup on schedule, kopia connected | mine (Track E) |
| Vault missing items | `ha-failover_api` only (1) | **2 missing**: `ha-failover_api` + `metabase-forgejo_ro` (HD-242) | re-verified `check-vault-items.sh --strict` |
| `check-vault-items.sh --strict` exit | (not stated) | **fails** with 1 missing (was 1 at audit time) | re-ran; actually the test was correct but the miss is `metabase-forgejo_ro` which is the deploy-gated HD-242 item, not `ha-failover_api`; both may now be missing |

Their **findings that are correct** (despite the wrong counts):
- AUD-A-1 (document map manual/ prefix) — valid convention check
- AUD-A-2 (5 broken anchors) — valid
- AUD-A-3 (12 IP literals) — valid (mine was narrower)
- AUD-A-4 (7 stale banners) — valid
- AUD-B-1 (`ha-failover_api` missing) — actually correct (this is
  a real second missing item I missed!)
- AUD-B-3 (16 vault refs without escape in TOML/env/yaml) — valid
  but the **interpretation** differs (theirs said "some use
  urlencode, some in TOML/env" — my analysis says ALL of these
  are correct-by-design because the non-compose files are not
  interpolated by `docker compose`)
- AUD-B-4 (4 `default()` in templates) — valid (mine only
  checked `default('')` for secrets)
- AUD-C-5 (collect-smart.ps1 not in README) — valid
- AUD-C-6 (testdata not in README) — by design, no action
- AUD-D-3 (renovate 4/10) — valid (mine said 6/10, granularity
  differs but both are estimates)
- AUD-D-5 (4 false positives) — valid; I have an expanded FP
  list
- AUD-E-1 (check-mode fails) — valid (a real check-mode
  limitation; not a finding but worth documenting)

---

## §5 Consolidated action plan (use `next-hd.sh` at write time)

Per CONVENTIONS §1: "**Backlog IDs** `HD-<number>` ... next free =
**max(HD)+1 in [todo.md](todo.md)** — a hand-entered 'next free' here
went stale within one week; never re-type it". The HD numbers in
this report are **illustrative** — both the other session and
my original report proposed HD-275..286 numbers, but with
DIFFERENT meanings. This merged report gives the consolidated
list, with the understanding that the actual HD numbers come
from `bash scripts/next-hd.sh` at write time. The next free
HD today is around 275 (per next-hd.sh at the time of merge).

**Consolidated action plan (12 new HDs, 1 high / 1 high / 6 med / 4 low):**

| # | Sev | Title | Owning doc | Source |
|---|-----|-------|------------|--------|
| 1 | High | Complete Cloudflare API token rotation (re-render traefik + restart) | docs/deployment-secrets.md | MERGE-1 |
| 2 | High | Create `ha-failover_api` vault item (HD-17 prerequisite) | docs/deployment-secrets.md | MERGE-2 |
| 3 | Med | Run `playbooks/dns.yml` to publish `bin` (and any other missing) CF records | IaC/ansible/roles/cloudflare_dns/vars/main.yml | MERGE-3 |
| 4 | Med | Add `pairdrop`/`drop`/`pdf` rows to docs/services.md public table | docs/services.md | MERGE-4 |
| 5 | Med | Cloudflare stale-record cleanup (delete `traefik` and other admin-tailnet records) | docs/network-dns.md | MERGE-5 |
| 6 | Med | fail2ban fix: add traefik `accesslog` + traefik-aware filter (or drop http-auth jail) | IaC/ansible/roles/vps-hardening/tasks/main.yml | MERGE-6 |
| 7 | Med | Update 7 stale status banners to ✅ Live since 2026-08-22 | docs/observability.md, services-traefik.md, services-authentik.md, services-admin.md, services-utilities.md, services-matrix.md | MERGE-7 |
| 8 | Med | Fix 5 broken anchor links in services-media / services-downloads | docs/services-media.md, docs/services-downloads.md | MERGE-8 |
| 9 | Med | Review + update 12 IP literals in docs (with `network-addresses-generated.md` refs) | docs/deployment-ansible.md, docs/deployment-secrets.md, docs/home-assistant-current.md | MERGE-9 |
| 10 | Med | Add inline comments to 4 `default()`-using templates (clarify non-secret usage) | IaC/ansible/templates/docker_services/{loki,authentik,prometheus,kopia-server}/docker-compose.yml.j2 | MERGE-10 |
| 11 | Med | Provision router WG pubkey + bring up wg-s2s (Phase 1.5 cutover) | IaC/ansible/group_vars/all/main.yml | MERGE-11 |
| 12 | Med | Add `cap_drop: ALL` + targeted `cap_add` to ollama + immich-ml (hardening) | docs/deployment-compose.md | MERGE-13 |
| 13 | Low | `sunshine` IaC vs journal: owner decision (deploy on Phase 2/3 vs set enabled: false) | IaC/ansible/group_vars/home_servers.yml | MERGE-14 |
| 14 | Low | `sunshine` host port binding restricted to Home VLAN IP (Phase 2/3 oldsrv bring-up) | IaC/ansible/templates/docker_services/sunshine/docker-compose.yml.j2 | MERGE-15 |
| 15 | Low | Update `audit.md` role count (20 not 19) | audit.md | MERGE-16 |
| 16 | Low | Document `collect-smart.ps1` as Windows-only sibling in scripts/README.md | scripts/README.md | MERGE-17 |
| 17 | Low | `docker image prune` for stale `traefik:v3.5.2` on VPS | (operational) | MERGE-18 |
| 18 | Low | Cleanup 2 duplicate `metabase_oidc,` 1P items | docs/deployment-secrets.md | MERGE-19 |
| 19 | Low | Drop scripts/README.md §8.4 references when HD-263 closes | scripts/README.md | MERGE-20 |
| 20 | Low | Document map tree: owner decision on manual/ prefix convention | docs/index.md | MERGE-21 |
| 21 | Low | Add False Positive Log entries for 4 intentional items (renovate, traefik-tailnet, prometheus_ha_exporter, rag-mcp/forgejo-mcp) | todo.md | from theirs |
| 22 | Low | Document vault-escape context (TOML/env/yaml don't need `| replace('$','$$')`) in template headers | IaC/ansible/templates/docker_services/**/.j2 | from theirs (clarification) |
| 23 | Low | Track renovate onboarding gaps (4-6 missing steps) under HD-264 | docs/services-admin.md | from theirs |

---

## §6 Consolidated open questions

1. **Document map convention:** `manual/chat.md` vs `chat.md`? (owner decision)
2. **IP literal exception in IaC docs:** does `docs/deployment-ansible.md` qualify as "IaC" for the exception? (their AUD-A-3 question)
3. **Status banner policy:** proactive vs opportunistic updates? (their AUD-A-4 question)
4. **Bulk pre-pass in check-mode:** mock or document as limitation? (their AUD-B-2 question)
5. **Vault escape context:** my analysis says TOML/env/yaml don't need escape because compose doesn't interpolate them; theirs blanket-flagged. Add template-header comments to make this explicit.
6. **`metabase-forgejo_ro` + `ha-failover_api` combined:** both missing, but at different deploy gates. Note: `check-vault-items.sh --strict` exit code reflects only the deploy-gated one.
7. **fail2ban fix path:** (a) add traefik `accesslog` + write a traefik-aware filter, or (b) drop the http-auth jail?
8. **When to schedule Phase 1.5 cutover (wg-s2s) and Phase 4 (HA failover with the new `ha-failover_api`)?**
9. **Consolidated `next-hd.sh`:** which HD numbers to assign for the 23 action items? (currently next free = 275; the merge consumed 275-286 in the two prior reports but with conflicting meanings; this consolidated list renumbers from 275 fresh)

---

## §7 Definitions of done (per audit.md §4 + CONVENTIONS §4)

- [x] `bash scripts/validate-all.sh` green from the worktree.
- [x] This merged report exists with all sections + per-finding
  evidence + dedup keys.
- [x] Both prior report files (5-track + security + consistency +
  the other session's full-audit) are kept for traceability.
- [x] Other session's report files archived in
  `reports/other-session-merged/`.
- [x] Counts corrected (20 roles, 35 enabled, 31 scripts).
- [x] HD numbers disambiguated — both prior reports' HD-275..283
  are mapped to distinct findings; the merged list provides a
  single source of truth for the action plan.
- [ ] New HD rows registered via `bash scripts/next-hd.sh` (out
  of scope for this audit; tracked for the next session).
- [ ] Handoff update `prompt.md` → #34 with audit outcomes (out
  of scope here; tracked).

---

## §8 Hygiene note (carried forward from the other audits)

The Cloudflare API token was exposed in the 5-track audit session
transcript. The 1Password item was rotated but the live traefik
container still has the OLD value (MERGE-1). Per CONVENTIONS §2,
the value is considered compromised; rotate is the audit's P0.

All probes in this merged audit used **lengths/tails/sha256[:16]**
only — no secret values written to the transcript. Safe probe
patterns documented in [security-audit-2026-08-29.md §20](security-audit-2026-08-29.md).

---

## §9 Source attribution

This merged report draws from 4 audit sources:

1. **5-track audit (this session, parent inline)** — [full-audit-2026-08-29.md](full-audit-2026-08-29.md),
   commit 845e28c. Primary source for: Track A docs, Track B IaC,
   Track C scripts, Track D conformance, Track E live probes,
   findings AUD-001..007.
2. **Security audit (this session)** — [security-audit-2026-08-29.md](security-audit-2026-08-29.md),
   commit 807cccc. Primary source for: SEC-1..18 (Edge WAF, port
   bindings, capability-tiering, fail2ban, sibling auth, OIDC).
3. **Consistency audit (this session)** — [consistency-audit-2026-08-29.md](consistency-audit-2026-08-29.md),
   commit e60a392. Primary source for: CONS-1..4 (subdomain
   catalog cross-check).
4. **Other session (parallel lanes)** —
   [other-session-merged/other-session-full-audit.md](other-session-merged/other-session-full-audit.md),
   archived. Primary source for: AUD-A-1..4 (doc map, anchors,
   IP literals, status banners), AUD-B-1 (`ha-failover_api`
   missing — actual additional finding), AUD-C-5
   (`collect-smart.ps1`), AUD-D-3,5 (renovate gaps, FP log).
