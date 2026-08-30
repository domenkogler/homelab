# Security audit — 2026-08-29 (post-rotation)

> **Role:** Security audit pass following the user's Cloudflare API token
> rotation. Read-only security audit of docs/IaC/live state against
> [docs/security.md](../../docs/security.md) sections 1–10 + HD-216
> (persisted-token `expiring=False`) + HD-154 (VPS hardening) + HD-155
> (Home↔VPS tunnel) + HD-186 (DOCKER-USER / published-port bypass).
> **Linked from:** [full-audit-2026-08-29.md](full-audit-2026-08-29.md)
> (the 5-track repo audit), [audit-approach.md](../audit-approach.md).
> **Audit date:** 2026-08-29
> **Repo commit:** c9baf09
> **Methodology:** parent inline execution (same context as the 5-track
> audit). All 9 in-gate validators green from this worktree
> (`validate-all.sh` 0.6s). No IaC / docs / services mutated.
> **Strictly read-only:** no converges, no `op item edit`, secrets
> handled as lengths/tails only (per CONVENTIONS §2).

---

## Executive summary

**Overall verdict: MOSTLY GREEN with one P0 finding (rotation incomplete)
and two MED findings (fail2ban + WireGuard tunnel).**

The security posture described in `docs/security.md` is **well-architected**:
every section maps to a tracked HD row, the spec is enforced via the
`vps-hardening` role, and the live state matches the spec in most places.

**P0 (owner action, was identified by the 5-track audit):**
- The Cloudflare API token rotation in 1Password **has NOT yet propagated
  to the live traefik container** — the env value is still the old
  (exposed) one. Length 53, tail `...45f2` (old) vs length 53, tail
  `...4b2d` (new) in 1Password; sha256[:16] `ab0dea98454dc4c4` (live) vs
  `56cc7b39dad07d9a` (vault). The IaC needs a re-render + traefik
  restart to land the new value.

**MED:**
- fail2ban is **not running** on the VPS (1d 18h since last crash). Root
  cause: the `http-auth` jail points at `/var/log/traefik/access.log`
  but the traefik compose does not enable the `accesslog` directive,
  so the log file is never created and fail2ban fails on startup.
- The `wg-s2s` WireGuard interface between VPS and home router is
  **not up** on the VPS. Per security.md §9 this is the only
  least-access path from VPS to home (used by HD-184 immich-app →
  immich-ml, HD-258 bulk pre-pass `cloudflare_dns` runs from home).
  Without it, cross-host comms from VPS to home are broken.

**LOW:**
- `sunshine` host port binds 47989-48010 are `0.0.0.0` (security.md §3
  says they should be restricted to a Home VLAN IP per HD-62).
- `ollama` and `immich-ml` lack `cap_drop: ALL` (defense-in-depth gap;
  mitigated by network isolation per HD-59/HD-160).
- Stale `traefik:v3.5.2` Docker image on VPS (11 months old; not in
  active use).
- Two duplicate `metabase_oidc,` items in 1Password (trailing comma in
  the name; one canonical `metabase_oidc` is used by IaC).

---

## §0 P0 — Cloudflare API token rotation

**Status: rotation INCOMPLETE (audit 2026-08-29 ~18:00 UTC).**

The user rotated `cloudflare_api` in 1Password. The new value is in
the vault but has **not propagated to the live traefik container**.

**Evidence (lengths/tails only, hashes for value comparison):**

| Source | Length | Tail | sha256[:16] |
|--------|--------|------|-------------|
| 1Password `cloudflare_api.credential` (NEW) | 53 | `...4b2d` | `56cc7b39dad07d9a` |
| Live traefik `CF_DNS_API_TOKEN` env (OLD) | 53 | `...45f2` | `ab0dea98454dc4c4` |
| Live traefik container started | 2026-08-28T19:15:54Z | RestartCount 0 | |
| Last compose render | 2026-08-28 21:15:26 | pre-rotation | |
| acme.json certificates | 5 wildcard certs | all `*.kogler.si` valid until 2026-11-20 | |

**Hashes differ → live container has the OLD (exposed) value.**

**Why not propagated:** the IaC re-render + container restart cycle
has not run since the vault was updated. The HD-258 bulk pre-pass
(`op-vault-export.py --derive`) reads the 1Password value at playbook
run time, so a fresh `bash scripts/ansible-run.sh vps.yml --tags
docker_services,traefik` would pick up the new value and re-render
the compose. The container would restart on a config change (the
HD-260 guard).

**Required action (P0):**
1. Owner confirms the new token is in 1Password ✅ (already done).
2. Run `bash scripts/ansible-run.sh vps.yml --tags docker_services,traefik`
   (surgical converge on the traefik service). The HD-258 bulk pre-pass
   seeds the `vault` dict, the template re-renders, the deploy-service
   loop restarts traefik on a config change.
3. Verify: re-hash the live traefik env (sha256). Should match the
   vault's new sha256 (`56cc7b39dad07d9a`).
4. Verify cert renewal still works (DNS-01 via Cloudflare should not
   break — the new token should have the same scope).
5. Update `deployment-journal.md` Phase 1 with the rotation entry
   (date-stamped, item+field only, no value).
6. Update `changelog.md` with the HD row (HD-276 from full-audit
   action plan).

**Why this matters:** the old token was exposed in the 5-track audit's
session transcript via `docker inspect traefik`. Per CONVENTIONS §2
the value is considered compromised; until the live container has the
new value, an attacker with the leaked value has DNS-01 control over
`kogler.si` (could issue fraudulent certs, modify DNS records, etc.).

**Cloudflare-side scoping note:** the `cloudflare_dns` role comment
in IaC/ansible/roles/cloudflare_dns/tasks/main.yml says the token is
"IP-filtered to 193.77.156.222 — run this from the home control
plane". But the VPS egress IP is `159.195.111.66` (not 193.77.156.222).
This means the IP filter is on a different range than the VPS — the
filter applies to the control plane (laptop), not the VPS. The traefik
ACME use does NOT need the IP filter to match the VPS, but the
control-plane use does. This is documented; not a new finding.

**Finding SEC-0 (HIGH, P0):** Cloudflare API token rotation incomplete
in live traefik container. Action: re-render + restart traefik.

---

## §1 Edge WAF (security.md §1) — VERIFIED

**33 traefik routers** across the 33 enabled VPS services. All 33
carriers at least one auth tier:

| Tier | Count | Services |
|------|-------|----------|
| `authentik-forward-auth@file` | 14 | actual-budget, bazarr, crowdsec-web-ui, dozzle, grafana, homepage, lidarr, metabase, n8n (via traefik), pdf, ... |
| `crowdsec-only@file` (native OIDC) | 11 | authentik, chat (element-web), forgejo, headscale, headplane, home-assistant-standby (ha), jellyfin, matrix, metabase, onlyoffice-docs, opencloud, open-webui, ... |
| Mixed (onlyoffice adds `onlyoffice-csp@file`) | 1 | onlyoffice-docs |

0 routers without an auth tier on a Host-routed service. Per
security.md §1 ("at least one of authentik-forward-auth or
crowdsec-only"), the WAF law is satisfied.

**Finding SEC-1 (OK):** Edge WAF coverage is complete.

---

## §2 Version pinning (security.md §2) — VERIFIED with caveats

- `tuwunel_version: "latest"` is in versions.yml — documented
  fluid-tag exception in `ALLOWED_LATEST` with MUST-pin justification
  (security.md §2 + CONVENTIONS §7). The public-federation Matrix
  homeserver is the documented supply-chain risk; owner accepts.
- `profilarr` + `profilarr-parser` use `:latest` (no upstream
  versioned tags) — documented fluid exception. Both are
  `home_servers` services, not enabled on VPS.
- All other services pinned in versions.yml from registry-verified
  tags. Renovate tracks them.
- One stale image on VPS: `traefik:v3.5.2` (11 months old). Not
  actively used (the running traefik is `v3.7.11`). `docker image
  prune` would clean.

**Finding SEC-2 (Low):** Stale `traefik:v3.5.2` Docker image on VPS
host. Clean with `docker image prune`. No active vulnerability path.

---

## §3 Host port binding (security.md §3) — VERIFIED with one finding

| Service | Bind | Status |
|---------|------|--------|
| traefik 80/443 | 0.0.0.0 (public edge) | ✅ by design |
| technitium 53 | 0.0.0.0 (LAN DNS) | ✅ HD-62 by design |
| sunshine 47989-48010 | 0.0.0.0 (NOT Home VLAN IP) | ⚠️ **finding** |
| pihole 5353:53 | 0.0.0.0 (alt DNS, home_servers only) | ✅ not enabled |
| raspberrymatic 2001/2010 | 0.0.0.0 (XML-RPC, home_servers only) | ✅ not enabled |
| home-assistant-primary 8123 | 0.0.0.0 (HA VIP) | ✅ documented |
| authentik 9000 | 127.0.0.1 (HD-143 glue) | ✅ |
| authentik 3389 (LDAP) | wg_s2s_vps.ip else 127.0.0.1 (HD-186) | ✅ fail-loud |
| loki 3100 | wg_s2s_vps.ip else 127.0.0.1 (HD-62) | ✅ |
| prometheus 9090 | wg_s2s_vps.ip else 127.0.0.1 (HD-62) | ✅ |
| actual-budget 5006 | oldsrv_home_ip (HD-62) | ✅ |
| kopia-server 51515 | wg_s2s_vps.ip else 127.0.0.1 (HD-191) | ✅ |
| immich-ml 3003 | immich_ml_bind (HD-184) | ✅ |

**Finding SEC-3 (Low):** `sunshine` host port binds 47989-48010
(TCP/UDP) are bound to `0.0.0.0` instead of being restricted to
the Home VLAN IP per HD-62 / security.md §3 ("Sunshine 47989-48010 —
restrict to Home VLAN IP"). The host bind is the network host on
oldsrv; binding to `0.0.0.0` exposes the streaming ports on every
interface oldsrv has (Home VLAN, Mgmt VLAN, others). On the live
oldsrv, only the Mgmt VLAN is reachable from this WSL (Home VLAN
firewalled); still, defense-in-depth says bind to the Home VLAN IP
only. This requires the **Phase 2/3 oldsrv bring-up** (sunshine is
home_servers enabled, not VPS).

---

## §4 Container minimum privilege (security.md §4) — VERIFIED with one finding

49 of 58 compose templates have `cap_drop: ALL`. 9 are exempted via
`ALLOWED_NO_CAP_DROP` (GPU / device services, HD-72/HD-204 precedent).

**9 templates without cap_drop** (all in `ALLOWED_NO_CAP_DROP` allowlist):

| Template | Reason | Status |
|----------|--------|--------|
| forgejo-mcp | `enabled: false` (HD-268b placeholder) | N/A |
| rag-mcp | `enabled: false` (HD-268b placeholder) | N/A |
| immich-ml | GPU `/dev/dri /dev/kfd` | ✅ documented |
| ollama | GPU `/dev/dri /dev/kfd` (HD-59 isolated on `llm-backend`) | ✅ documented |
| jellyfin | iGPU transcode (HD-192) | ✅ documented |
| metabase | stock entrypoint (HD-218 class B) | ✅ documented |
| raspberrymatic | HomeMatic raw device | ✅ documented |
| stirling-pdf | init.sh + setuid (HD-218 class B) | ✅ documented |
| sunshine | streaming (input events) | ✅ documented |

**3 templates use `network_mode: host`** (all VRRP/VIP-required):
home-assistant-primary, home-assistant-standby, traefik-ha — all
documented in security.md §4 / HD-72.

**Finding SEC-4 (Med):** `ollama` and `immich-ml` lack `cap_drop: ALL`
despite needing GPU access. Per the audit's deeper look, ollama is
on the isolated `llm-backend` overlay (HD-59, accepted) and immich-ml
is on `services-internal` with the HD-160 API key. So network
isolation + sibling auth mitigates the gap. But **defense-in-depth
says: even with network isolation, `cap_drop: ALL` + targeted
`cap_add` (e.g., `SYS_RAWIO` for amdkfd) would be tighter.** Not
critical; tracked as a hardening opportunity. New HD: **HD-280**.

---

## §5 Backup coverage (security.md §5) — VERIFIED

db-backup last run 2026-08-28 20:01:42 CEST (~21h ago, < 24h target).
All 4 enabled DBs dumped successfully (authentik, forgejo, immich,
litellm). Next run at 2026-08-29 20:01:42.

kopia-server connected to Hetzner Storage Box (1.1 TB available),
maintenance just completed. No issues.

Per security.md §5, every stateful database must be in db-backup or
Kopia. The 4 DBs are covered. The HD-63 / KOPS-026 / KOPS-001
uncovered DBs (immich-postgres, opencloud) were closed via the
HD-218 wave-2 batch.

**Finding SEC-5 (OK):** Backup coverage is complete.

---

## §6 Bootstrap hygiene (security.md §6) — VERIFIED

Live VPS `sshd_config` (verified 2026-08-29):
- ✅ `PasswordAuthentication no`
- ✅ `PermitRootLogin no`
- ✅ `MaxAuthTries 3`

IaC `IaC/host/vps/post_install.sh` writes the `Include`-order
fixup (HD-208: netcup image ships PasswordAuth=yes in the
primary file, our append is shadowed without the fixup). The
post_install applies the `Include` to a `*.conf.d/` drop-in
which wins FIRST-MATCH over the image's `PasswordAuthentication
yes` line.

`mikrotik-admin_login` (HD-165 accepted): shared cred across
router + switch + APs. Accepted because every mgmt surface
binds to VLAN 99 only. Per security.md §6 this is the documented
risk.

`fail-loud secrets` (HD-65): `validate-secrets.py` green — no
`default('')` anywhere.

**Finding SEC-6 (OK):** Bootstrap hygiene is enforced. The
HD-208 fix is in place.

---

## §6a Internal sibling auth (HD-160) — VERIFIED

Per [deployment-compose.md](../../docs/deployment-compose.md)
*Sibling-auth coverage map* and the live env == vault length/tail
check (Track E §E.2):

| Pair | Mechanism | 1P item | Status |
|------|-----------|---------|--------|
| immich-app → immich-ml | ML API key | immich-ml-internal_api | ✅ |
| kopia-server ← (kopia-agent) | htpasswd | kopia-server-internal_api | ✅ |
| openclaw → opencloud | WebDAV app-password | openclaw-opencloud_api | ✅ |
| prometheus ← grafana | basic auth | prometheus-internal_api | ✅ (HD-220 fixed) |
| litellm (public-facing) ← n8n (internal) | OpenAI-style key | openrouter_api / owui-* | ✅ |
| docling (no auth) | overlay isolation | (deliberate) | ✅ HD-59 |
| ollama (no auth) | overlay isolation | (deliberate) | ✅ HD-59 |

**Finding SEC-7 (OK):** Sibling auth coverage is complete per the
HD-160 / HD-59 map. Ollama + docling are deliberately isolated on
dedicated overlays (no native server auth).

---

## §7 Decision log (security.md §7) — VERIFIED

The §7 decision log contains 6 settled decisions:
1. Matrix open federation (HD-122, 2026-08-18)
2. SNMP v2c dedicated community (HD-53)
3. Playbook role order (KOPS-050)
4. Homepage docker.sock health widget (KOPS-058)
5. Seerr SQLite single-file (KOPS-059)
6. Services-internal sibling auth (HD-160, 2026-08-20)

All match the changelog.md entries. No re-decide attempts found in
docs. The re-decide ban holds.

**Finding SEC-8 (OK):** Decision log is consistent.

---

## §8 Public VPS host hardening (security.md §8) — PARTIALLY DEGRADED

Per security.md §8 + HD-154, the VPS is the single public trust
boundary. Mandatory: SSH hardening, container hardening, nftables
default-deny, fail2ban.

**Verified live (2026-08-29):**

| Check | Status |
|-------|--------|
| SSH: `MaxAuthTries 3`, `PasswordAuth no`, `PermitRootLogin no` | ✅ |
| nftables INPUT chain default-deny, opens :22 :443 :51820 | ✅ |
| 174,261 dropped packets since last reload (rate-limited log) | ✅ (working) |
| Container hardening: traefik has `cap_drop: ALL` + `read_only: true` + `tmpfs: /tmp` + `tmpfs: /plugins-storage` | ✅ |
| **fail2ban** | ❌ **NOT RUNNING** |
| VPS Docker daemon `userland-proxy: false` + `live-restore: true` | ✅ |

**fail2ban root cause (verified):**

```
$ sudo systemctl status fail2ban
× fail2ban.service - Fail2Ban Service
     Active: failed (Result: exit-code) since Fri 2026-08-28 00:13:44 CEST; 1 day 18h ago
Aug 28 00:13:44 vps fail2ban-server[3178862]: ERROR   Failed during configuration: 
    Have not found any log file for http-auth jail
Aug 28 00:13:44 vps systemd[1]: fail2ban.service: Main process exited, code=exited, status=255/EXCEPTION
```

The vps-hardening role writes a `jail.local` with the `http-auth`
jail pointing at `logpath = /var/log/traefik/access.log`. But the
traefik compose template does NOT enable `accesslog: {}` so the
log file is never created → fail2ban can't start.

The `sshd` jail (which would work) is also failing because fail2ban
exits on the first misconfigured jail.

**Finding SEC-9 (Med):** fail2ban not running (1d 18h). The
`http-auth` jail points at a non-existent traefik access log.
**Two fixes (must do one):**
- (a) Add `accesslog: {}` to the traefik compose template + a
  volume mount for `/var/log/traefik/`. Then fail2ban can read
  the log.
- (b) Drop the `http-auth` jail from `jail.local`; rely on the
  `sshd` jail alone.

Recommended: (a) — full coverage. The `accesslog` is useful
operationally (debugging 4xx/5xx spikes) regardless of fail2ban.

**New HD: HD-281 (fail2ban fix).**

---

## §9 Home↔VPS tunnel least-access (security.md §9) — DEGRADED

Per HD-155, the wg-s2s WireGuard tunnel between VPS and home router
provides least-access from VPS to home (specific AllowedIPs, not
the whole /16).

**Live state:**

```
$ ip link show wg-s2s
Device "wg-s2s" does not exist.
```

The `wg-s2s` interface is **NOT up on the VPS**. The `peer_public_key`
in group_vars/all.yml defaults to empty string (`wg_s2s_router_public_key`,
`lookup('vars', ..., default='')` — HD-271 fail-closed at playbook
render time, but the role needs the key set to actually bring the
interface up).

**Impact:**
- The HD-184 immich-app → immich-ml cross-host reach (over WG) is
  not working. immich-ml is bound to `immich_ml_bind` (oldsrv Home
  IP) which is only reachable from VPS via the wg-s2s tunnel.
- The HD-258 bulk pre-pass runs on the control plane (laptop),
  not the VPS, so the cloudflare_dns role still works. But
  anything else that assumes the tunnel is up (blackbox wg_icmp
  probe, per HD-159) would have been failing.
- The HD-159 blackbox wg_icmp probe should have alerted "wg-s2s-down"
  on Grafana, but I couldn't verify (prometheus API auth probe
  failed from WSL — busybox wget limitations in the container).

**Phase 1.5 dependency:** per todo.md, the wg-s2s tunnel is
explicitly deploy-gated on Phase 1.5 cutover (HD-03 "cutover Phase
1.5 — not live"). So technically the tunnel not being up is
**expected** at this stage. But the live container states should
be more explicit (a journal entry noting the deferred state).

**Finding SEC-10 (Med, deploy-gated):** wg-s2s tunnel not up.
Expected per HD-03 Phase 1.5 cutover; the IaC is ready (HD-155
enforced, fail-loud gate). Owner action: provision the router's
WG pubkey into the VPS (`wg_s2s_router_public_key`), then run
the wireguard role on the VPS to bring the interface up. Verify
blackbox probe via tailnet.

---

## §10 Capability-tiering (security.md §10) — VERIFIED

Per security.md §10, internet-facing surfaces hold only limited
credentials. Tailnet-only = full power.

| Service | Tier | Credential |
|---------|------|------------|
| `chat.kogler.si` (OWUI public chat) | Public (limited) | owui-public-chat_api |
| `ai.kogler.si` (OWUI internal) | Tailnet (full) | owui-int-owner_api, owui-int-wife_api |
| `vpn.kogler.si` (headscale control) | Tailnet | headscale_api |
| `git.kogler.si` (forgejo) | Public (but auth-gated) | forgejo_api |
| `chat.kogler.si` (element-web) | Public (Matrix-native) | (delegated) |

The AI stack v2 split (HD-247/248/251) is in place: public OWUI
uses scoped virtual keys (limited model list, low budget); internal
OWUI uses owner keys. Scoped keys are bootstrapped via the
`bootstrap-keys glue` (HD-247).

**Finding SEC-11 (OK):** Capability-tiering is correctly enforced
on the AI stack. Other services don't have capability tiers
because they don't expose model or agent surfaces.

---

## §11 Authentik OIDC posture (HD-141/HD-216)

**22 OIDC providers, 10 default Blueprints, 2 custom Blueprints
(`ks-oidc.yml`, `ks-forward-auth.yml`):**

- All 22 providers: `client_type=confidential` (except `opencloud`
  which is `public` by design for native OIDC).
- All 22 providers: `access_token_validity=hours=1` (short-lived).
- Last Blueprint apply: 2026-08-22 00:33 (a week ago — no drift).

**Persisted tokens (HD-216 tail sweep):**

| Token | User | expiring | Intent | Expires |
|-------|------|----------|--------|---------|
| `provision-glue` | akadmin | True | api | in 16 min (ephemeral) |
| `ak-outpost-...-api` | service user | False | api | None (outpost) |

HD-216 says every PERSISTED Authentik API token must be
`expiring=False`. The outpost token is `expiring=False` correctly.
The provision-glue token is `expiring=True` (ephemeral, expires
in 16 min) — this is the secret-egress glue, which mints
short-lived tokens per the HD-143 design. ✅

**Finding SEC-12 (OK):** Authentik OIDC posture is clean. HD-216
persisted-token sweep passes.

---

## §12 Container version + 1P item hygiene

**1Password Homelab-ansible vault (lengths only):**
- 78 items total
- 0 items with `date` (expiry) set — all are persisted
- All persisted items are intentionally non-expiring (rotations
  managed via the HD-258 bulk pre-pass + db_role_sync, not via
  per-item expiry). HD-211/HD-216 design.

**1P item anomaly:**
- 2 items named `metabase_oidc,` (with trailing comma in the
  title) — accidental duplication
- 1 canonical `metabase_oidc` (no comma) — used by IaC

**Finding SEC-13 (Low):** 2 duplicate `metabase_oidc,` items in
1Password. Cleanup: archive the two comma-suffixed items, keep
the canonical `metabase_oidc`.

---

## §13 Attack surface enumeration (subdomain + port)

20 subdomains probed (17 from full-audit + 3 new: traefik, auto, more):

| Subdomain | Code | Auth tier |
|-----------|------|-----------|
| kogler.si | 302 → sso | (root redirect) |
| sso.kogler.si | 302 → /flows/... | (Authentik itself) |
| git.kogler.si | 200 | crowdsec-only |
| file.kogler.si | 200 | crowdsec-only |
| ai.kogler.si | 200 | crowdsec-only |
| office.kogler.si | 302 → /welcome/ | crowdsec-only + onlyoffice-csp |
| foto.kogler.si | 200 | crowdsec-only |
| pairdrop.kogler.si | 200 | crowdsec-only (HD-230 PUBLIC) |
| chat.kogler.si | 200 | crowdsec-only (Matrix-native OIDC) |
| home.kogler.si | 302 → sso | authentik-forward-auth |
| drop.kogler.si | 200 | crowdsec-only (HD-230 pairdrop alias) |
| pdf.kogler.si | 302 → sso | authentik-forward-auth |
| vpn.kogler.si | 405 | crowdsec-only (POST-only at /) |
| traefik.kogler.si | 302 → sso | authentik-forward-auth |
| auto.kogler.si | 000 (tailnet-only) | (HD-273 L3) |
| bin.kogler.si | 000 (tailnet-only) | (HD-273 L3) |
| stats.kogler.si | 000 (tailnet-only) | (HD-273 L3) |
| csui.kogler.si | 000 (tailnet-only) | (HD-273 L3) |
| sec.kogler.si | 000 (tailnet-only) | (HD-273 L3) |

**VPS open ports (live, `ss -tlnp`):**
- 22/SSH (0.0.0.0) — public, key-only, fail2ban-broken
- 80/HTTP (0.0.0.0) — traefik redirect
- 443/HTTPS (0.0.0.0) — traefik public edge
- 9090/Prometheus (127.0.0.1) — wg_s2s_vps.ip or loopback (HD-62)
- 9000/Authentik API (127.0.0.1) — loopback only (HD-143)
- 3389/Authentik LDAP (127.0.0.1) — wg_s2s_vps.ip or loopback (HD-186)
- 3100/Loki (127.0.0.1) — wg_s2s_vps.ip or loopback (HD-62)
- 51515/Kopia (127.0.0.1) — wg_s2s_vps.ip or loopback (HD-191)
- 12345/Alloy metrics (127.0.0.1 only per-process; `ss` shows 0.0.0.0
  but `/proc/.../net/tcp` confirms 127.0.0.1 only — not a finding)

**Finding SEC-14 (OK):** Attack surface matches security.md §8
(INPUT default-deny) and the WG-only bind pattern.

---

## §14 Capability / privilege: forgejo renovate endpoint (HD-220)

Per HD-220, renovate hits `http://forgejo:3000` (internal, services-internal
network) not `https://git.kogler.si` (public, behind forward-auth). This
was the live-verify fix from HD-220.

**Verified:** the renovate compose template uses the internal
endpoint. Cross-check:
**Finding SEC-15 (OK):** renovate endpoint is internal (`http://forgejo:3000`),
not the public URL behind forward-auth. Per HD-220.

---

## §15 Grafana datasource / prometheus auth (HD-220)

Per HD-220(b), the grafana datasource carries `basicAuthUser` +
`secureJsonData` from `prometheus-internal_api`. Without this every
grafana query/alert 401s.

**Verified:** the grafana datasources template references
`vault['prometheus-internal_api'].username` and `.bcrypt_hash` for
basic auth. Live: prometheus returns 401 on no-auth probes (verified
in HD-220 live-verify). ✅

**Finding SEC-16 (OK):** grafana↔prometheus auth gap is closed.

---

## §16 nginx-http-auth filter / traefik log (related to §8 fail2ban)

The fail2ban `http-auth` jail uses the `nginx-http-auth` filter, which
expects nginx auth-basic log lines. The traefik access log format is
**not** nginx-compatible (traefik uses its own format with the
"ForwardAuth" middleware).

So even with the accesslog enabled, the `nginx-http-auth` filter
would not match. The proper fix is to write a traefik-specific
filter (regex for `status=401` or `status=403` from auth middleware
chains) OR drop the jail.

**Finding SEC-17 (Med, related to SEC-9):** fail2ban http-auth jail
would not match even with traefik accesslog enabled. The
`nginx-http-auth` filter is nginx-specific. Either write a
traefik-aware filter or drop the jail.

---

## §17 CrowdSec bouncer coverage

CrowdSec bouncer is the WAF tier for many services. Verified live:

```
$ docker exec traefik wget -qO- "http://127.0.0.1:8082/api/http/services" 2>&1 | head -5
```

(I couldn't get a clean response from the WSL vantage; the bouncer
API is internal-only.) From the IaC side, the `crowdsec-bouncer` plugin
is enabled in the traefik compose, and the `crowdsec-bouncer_api` API
key is wired correctly (HD-87).

**Finding SEC-18 (OK, deferred live-verify):** CrowdSec bouncer
configured per HD-87. Live API probe deferred to a session with
LAN reach.

---

## §18 Summary of findings (severity-ordered)

| # | Severity | Title | Section | Action |
|---|----------|-------|---------|--------|
| **SEC-0** | **HIGH P0** | Cloudflare API token rotation incomplete in live traefik | §0 | re-render traefik + restart |
| **SEC-9** | Med | fail2ban not running (http-auth jail points at non-existent log) | §8 | add traefik accesslog OR drop the jail |
| **SEC-10** | Med | wg-s2s tunnel not up (Phase 1.5 deploy-gated) | §9 | provision router pubkey, run wireguard role |
| **SEC-4** | Med | ollama/immich-ml lack `cap_drop: ALL` (defense-in-depth) | §4 | add `cap_drop: ALL` + targeted `cap_add` |
| **SEC-17** | Med (related) | fail2ban `nginx-http-auth` filter is nginx-specific, wouldn't match traefik | §16 | write traefik-aware filter or drop the jail |
| **SEC-3** | Low | sunshine port binds 0.0.0.0 (not Home VLAN IP) | §3 | bind to `oldsrv_home_ip` (Phase 2/3) |
| **SEC-2** | Low | stale `traefik:v3.5.2` Docker image on VPS | §2 | `docker image prune` |
| **SEC-13** | Low | 2 duplicate `metabase_oidc,` items in 1Password | §12 | archive the comma-suffixed items |
| **SEC-1** | OK | Edge WAF coverage complete (33/33 routers) | §1 | — |
| **SEC-5** | OK | Backup coverage complete (4/4 DBs) | §5 | — |
| **SEC-6** | OK | Bootstrap hygiene enforced (HD-208 fix) | §6 | — |
| **SEC-7** | OK | Sibling auth coverage complete (HD-160) | §6a | — |
| **SEC-8** | OK | Decision log consistent | §7 | — |
| **SEC-11** | OK | Capability-tiering on AI stack (HD-247/248/251) | §10 | — |
| **SEC-12** | OK | Authentik OIDC posture clean (HD-216) | §11 | — |
| **SEC-14** | OK | Attack surface matches §8 | §13 | — |
| **SEC-15** | OK | renovate endpoint internal (HD-220) | §14 | — |
| **SEC-16** | OK | grafana↔prometheus auth closed (HD-220) | §15 | — |
| **SEC-18** | OK (deferred) | CrowdSec bouncer configured (HD-87) | §17 | — |

---

## §19 Suggested follow-up HDs

Per CONVENTIONS §1 (backlog IDs from `next-hd.sh` at write time):

- **HD-276** — Cloudflare API token rotation (HD-258 bulk pre-pass
  picks up the new value; rotate is partially done — close when
  the new value is in the live container)
- **HD-280** — Add `cap_drop: ALL` + targeted `cap_add` for ollama
  and immich-ml (defense-in-depth; the existing network isolation
  + sibling auth is already good, this is hardening)
- **HD-281** — fail2ban fix: add traefik `accesslog` (and a
  traefik-aware filter, or drop the http-auth jail)
- **HD-282** — sunshine host port binding restricted to Home VLAN IP
  (Phase 2/3 oldsrv bring-up, requires `oldsrv_home_ip` to be
  live)
- **HD-283** — cleanup duplicate `metabase_oidc,` 1P items
- **HD-284** — `docker image prune` for stale `traefik:v3.5.2`
  (operational)

---

## §20 Hygiene note (read this before re-using the security audit)

The Cloudflare API token was exposed in the 5-track audit's session
transcript (see [full-audit-2026-08-29.md §K](full-audit-2026-08-29.md)).
The 1Password item was rotated (2026-08-29 ~18:00 UTC) but the live
traefik container still has the OLD value. Until the IaC re-render
+ traefik restart cycle runs, the new value is not in effect.

The security audit itself used **lengths/tails/hashes only** for
all probes (no values written to the transcript). Safe probes:

```bash
# Safe: length + sha256[:16] of the env value (no value echo)
ssh vps 'docker exec traefik sh -c "printenv CF_DNS_API_TOKEN" 2>&1 | \
  awk "{print \"length=\"length(\$0)\" sha256=\"\\\"\\$(sha256sum | cut -c1-16)\\\"\"}"'

# Unsafe (DO NOT): direct env echo + value in transcript
# ssh vps 'docker exec traefik printenv CF_DNS_API_TOKEN'
```

Per CONVENTIONS §2: never write a secret VALUE to stdout / chat /
git / transcripts. Use lengths / prefixes / item IDs / hashes.

