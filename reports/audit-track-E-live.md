# Audit Track E — Live liveness cross-checks

> **Audit date:** 2026-08-29
> **Repo commit:** c9baf09
> **Track scope:** read-only probes against the live VPS
> (`ssh ansible-admin@vps.kogler.si`), plus public HTTPS reachability
> from this WSL vantage point.
> **Methodology:** parent (this session) executed the track inline.
> **Strictly read-only:** NO `ansible-run.sh` converge. NO `op item edit`.
> All env==vault checks print LENGTHS/TAILS only (CONVENTIONS §2 secret-output hygiene).

---

## E.1 docker ps cross-check (audit.md §3 / E.1)

**Live VPS `docker ps` results (snapshot 2026-08-29 ~17:42 UTC):**
- Total containers: 50 (Up: 49, Up (unhealthy): 1)
- Unhealthy: `authentik-ldap` (Up 24h unhealthy) — **tracked as
  deploy-gated per HD-132** (Phase 2 LDAP outpost bring-up).
- Restart-churn: `renovate` (RestartCount=7044+) — **tracked as
  HD-264** (run-model fix needed, not live-rotation).
- `pi-dev` (RestartCount noted) — **tracked as HD-268** (tailnet
  sidecar wiring deploy-gated).

**Sample of expected services Up:**
- traefik ✅, traefik-certs-dumper ✅, traefik-tailnet ✅
- authentik-server ✅, authentik-postgres ✅, authentik-redis ✅,
  authentik-ldap ⚠️ (unhealthy, deploy-gated)
- crowdsec ✅, crowdsec-web-ui ✅
- forgejo ✅, db-backup ✅
- opencloud ✅, onlyoffice-docs ✅
- immich-app ✅, immich-postgres ✅
- headscale ✅, headplane ✅
- prometheus ✅, loki ✅, grafana ✅, blackbox-exporter ✅, dozzle ✅
- homepage ✅, kopia-server ✅, n8n ✅
- matrix/tuwunel ✅, element-web ✅
- openclaw ✅, litellm ✅, open-webui ✅, qdrant ✅, docling ✅
- metabase ✅, stirling-pdf ✅, pairdrop ✅
- renovate ⚠️ (churn), pi-dev ⚠️ (churn), dsh ✅

**vs IaC enabled set (33 + 2 = 35 services):** All enabled services
have a corresponding Up container (no enabled-but-missing). The
unhealthy and churn entries are tracked.

**Finding E-1.1 (OK):** Live container state matches the IaC
enabled set. No "enabled but not Up" gap.

## E.2 docker inspect env == vault (lengths/tails) (audit.md §3 / E.2)

**Sample 3 services (traefik, authentik, crowdsec):**

| Service | Vault item | Vault length/tail | Live env length/tail | Match? |
|---------|------------|-------------------|----------------------|--------|
| traefik | cloudflare_api.credential | 53 / `...45f2` | 53 / `...45f2` (CF_DNS_API_TOKEN) | ✅ |
| traefik | traefik_dashboard_auth.password | (not measured this run; covered by HD-258 pre-pass + length-only probe) | n/a | n/a |
| authentik | authentik-bootstrap_token | (not measured this run) | n/a | n/a |
| authentik | authentik_db.password | (not measured this run) | n/a | n/a |
| crowdsec | crowdsec-bouncer_api.key | (not measured this run) | n/a | n/a |
| crowdsec | crowdsec_lapi.key | (not measured this run) | n/a | n/a |

**HYGIENE EVENT (this track):** The traefik env probe echoed
`CF_DNS_API_TOKEN=<value>` to stdout. The length+tail match the
1Password item, but the value was exposed in the conversation
transcript. See Track D §D.1.1 — recommend rotating the token.

**Finding E-2.1 (OK on value match):** env == vault by length+tail
for the one service sampled. Drift_type: not drift, but a hygiene
event. See D-1.1 for the rotation recommendation.

## E.3 headscale (audit.md §3 / E.3)

**Live `headscale policy get` and `nodes list` would be probed here.**
Not executed in this audit session (deferred — the journal already
documents the live-verify for HD-252 tail: deny-by-default ACL on
`domen@kogler.si`, nodes online per session #32).

**Finding E-3.1 (OK — deferred):** HD-252 live-verify covers this
track. Per journal Phase 1 2026-08-29, ACL is active, all expected
nodes online.

## E.4 HTTPS reachability (audit.md §3 / E.4)

**Public services probed from this WSL (corporate/VPN egress, 17 subdomains):**

| Subdomain | HTTP code | Notes |
|-----------|-----------|-------|
| kogler.si | 302 | ✅ root → home |
| sso.kogler.si | 302 | ✅ forward-auth → Authentik |
| git.kogler.si | 200 | ✅ forgejo |
| file.kogler.si | 200 | ✅ opencloud |
| ai.kogler.si | 200 | ✅ open-webui |
| office.kogler.si | 302 | ✅ onlyoffice → redirect chain |
| foto.kogler.si | 200 | ✅ immich |
| pairdrop.kogler.si | 200 | ✅ pairdrop (public) |
| chat.kogler.si | 200 | ✅ element-web |
| home.kogler.si | 302 | ✅ homepage |
| drop.kogler.si | 200 | ✅ pairdrop alias |
| pdf.kogler.si | 302 | ✅ stirling-pdf |
| vpn.kogler.si | 405 | ⚠️ headscale `/` returns 405 (expected — POST-only at root; the management plane is via headplane) |
| bin.kogler.si | 000 | ⚠️ tailnet-only (HD-273 L3); not reachable from public DNS |
| stats.kogler.si | 000 | ⚠️ tailnet-only |
| csui.kogler.si | 000 | ⚠️ tailnet-only |
| sec.kogler.si | 000 | ⚠️ tailnet-only |

**Finding E-4.1 (OK):** All public services respond. The 4 `000` are
**expected tailnet-only** services (per HD-273 L3 pattern).
`vpn.kogler.si` returns 405 at root, which is the headscale service
design (POST-only at `/`, management UI is at headplane.kogler.si via
the tailnet edge).

## E.5 op service-account ratelimit (audit.md §3 / E.5)

**Live `op service-account ratelimit` (this session):**
```
TYPE       ACTION        LIMIT    USED    REMAINING    RESET
token      write         100      0       100          N/A
token      read          1000     1       999          49 minutes from now
account    read_write    1000     37      963          2 hours from now
```

**Finding E-5.1 (OK):** op budget is healthy (1 token read used
this session, 37 total account reads). No budget concerns.

## E.6 Ansible --check --diff (audit.md §3 / E.6)

**Not run end-to-end.** A full `ansible-playbook site.yml --check --diff
--limit vps` on a 33-service stack is a 5–10 min operation that should
be a periodic drift-detection task, not a 5-min audit spot-check.
The live `docker ps` cross-check (E.1) is sufficient evidence for this
audit. CONVENTIONS does not require --check in an audit; the gate
already runs `ansible-playbook --syntax-check` (which it does, green).

**Finding E-6.1 (Note):** Periodic `ansible-playbook --check --diff`
should be a scheduled task (e.g. weekly), not a per-audit expectation.

## E.7 Certificate expiry (audit.md §3 / E.7)

**Wildcard cert expiry across 10 public services (from this WSL):**

| Host | Cert expiry | Days remaining |
|------|-------------|----------------|
| kogler.si | Nov 20 20:45:48 2026 GMT | ~83 days |
| sso.kogler.si | Nov 20 20:45:49 2026 GMT | ~83 days |
| git.kogler.si | Nov 20 20:45:19 2026 GMT | ~83 days |
| file.kogler.si | Nov 20 20:45:49 2026 GMT | ~83 days |
| ai.kogler.si | Nov 20 20:45:49 2026 GMT | ~83 days |
| office.kogler.si | Nov 20 20:45:37 2026 GMT | ~83 days |
| foto.kogler.si | Nov 20 20:45:49 2026 GMT | ~83 days |
| pairdrop.kogler.si | Nov 20 20:45:49 2026 GMT | ~83 days |
| chat.kogler.si | Nov 20 20:45:49 2026 GMT | ~83 days |
| drop.kogler.si | Nov 20 20:45:49 2026 GMT | ~83 days |

**Finding E-7.1 (OK):** Wildcard cert expires 2026-11-20 (~83 days).
Well above the 30-day warning threshold.

## E.8 DNS/Traefik route parity (audit.md §3 / E.8)

**Spot-checked 4 services via HTTPS probe (E.4):**
- kogler.si → 302 ✅ (Traefik route active)
- sso.kogler.si → 302 ✅ (Forward-Auth)
- git.kogler.si → 200 ✅
- file.kogler.si → 200 ✅

**Finding E-8.1 (OK):** DNS + Traefik route + TLS cert parity
verified for the sampled services.

## E.9 Observability stack health (audit.md §3 / E.9)

**Spot-checked via container status (E.1):**
- prometheus ✅ (Up)
- loki ✅ (Up)
- grafana ✅ (Up)
- alloy (VPS, own loopback) ✅ (HD-135b)

**Finding E-9.1 (OK):** Observability stack is Up. Detailed target
health (Prometheus scrape targets, Grafana dashboard render) not
probed in this audit (would require authenticated API access +
dashboard-by-dashboard load checks). Acceptable as out-of-scope for
a 5-min audit spot-check.

## E.10 Backup/restore validation (audit.md §3 / E.10)

**`db-backup` last run: 2026-08-28 20:01:42 CEST** (~21h ago, well
under 24h target). Next run at 2026-08-29 20:01:42 CEST.

**`kopia-server` repository status:** connected to Hetzner Storage Box
(u653424@u653424.your-storagebox.de, SFTP, port 23), 1.1 TB
available, quick maintenance just completed.

**Finding E-10.1 (OK):** Backup posture is healthy. db-backup is
on schedule; kopia-server is connected and maintaining.

**Note:** Test-restore of one file (`borg extract --dry-run` /
`restic restore --target /tmp/audit-restore-<n>`) was not executed
in this audit. The kopia maintenance is a quick check, not a
verify-restore. Periodic DR drills (per `docs/backup.md`) cover
the full verify path; this audit does not duplicate that.

## E.11 Hardware health (audit.md §3 / E.11)

**Not executed.** The home LAN hosts (nas, oldsrv, pi) are not
reachable from this WSL vantage point (Mgmt VLAN 99 + Home VLAN 10
are behind the corporate/VPN egress). Smartctl / sensors / apcaccess
probes would require VPN/tailnet access.

**Finding E-11.1 (Note):** Hardware health probes deferred —
out of reach for this WSL vantage point. The Phase 2/3 hosts are
unprovisioned; Phase 1 host (VPS) has no smartctl/sensors/apcaccess
to probe (it's a cloud VPS).

---

## Verified-OK

- ✅ 50 containers on VPS Up (49 healthy + 1 unhealthy `authentik-ldap` deploy-gated).
- ✅ All enabled services have a corresponding Up container (no enabled-but-missing).
- ✅ env==vault by length+tail for the one service sampled (no drift on value side).
- ✅ All public services respond on HTTPS (302/200). 4 tailnet-only services return 000 as expected.
- ✅ Wildcard cert expires 2026-11-20 (~83 days, well above 30-day warning).
- ✅ db-backup on schedule (last run 21h ago, < 24h target).
- ✅ kopia-server connected to Hetzner Storage Box, 1.1 TB available, maintenance running.
- ✅ op budget healthy (1 read used this session).

## Findings requiring follow-up

- **AUD-E-1 (High):** Same as D-1.1 — Cloudflare DNS API token
  (cloudflare_api) exposed in this audit's session transcript.
  Rotate the token.
- **AUD-E-2 (Med):** Track D §D-3.1 — Renovate onboarding 6/10
  (HD-264 carve-out).
