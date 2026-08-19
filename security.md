# Security — Audit & Recommended Enhancements

> **Role:** Security audit — current posture (as designed) across edge, auth, network, Docker, secrets, bootstrap, backup + recommended enhancements.
> **Pairs with:** `docs/security.md` (existing hardening law), `docs-vs-iac.md`, `architecture.md`, `iac-changes.md`.
> **Current state:** planning; VPS provisioned; home hosts not yet live.

## 1. Existing posture — audit the current design (largely sound)

### Strengths present in the design
- **Edge WAF law** (`security.md §1`): every internet/LAN route carries `authentik-forward-auth@file` **or** `crowdsec-only@file` (KIP law). Sound — native-OIDC routes (ha, matrix, file, foto, ai) deliberately get crowdsec-only, no bone forward-auth.
- **Version pinning law** (`§2`): mutable-tag ban, Renovate-tracked pins, cronion for the fluid-tag exceptions.
- **Host-port policy** (`§3`): no `0.0.0.0:port` binds by default; loopback / VLAN-bound where needed. Mostly applied (HD-62 done).
- **Container min-privilege** (`§4`): cap_drop/read_only/tmpfs; `cap_add` targeted; avoid privileged/network_mode host except VRRP.
- **Backup coverage** (`§5`): DBs → db-backup/Kopia.
- **Bootstrap hygiene** (`§6`): preseed root-login false, per-host, fail-loud secrets.
- **Secrets**: 1Password only, `lookup(...)` at render, never committed; no `default('')`.
- **Admin/AI least-privilege** (site pre-flight assert `ai-debug` cannot run Ansible; one sudo allowlist `ai-diag`).

## 2. Security gaps found in this audit

### 2.1. 🔴 Public VPS is the biggest trust subject — **harden the VPS OS / SSH surface**
- The VPS is the public edge. Only notes found: netcup SCP (no ai-debug), root-login disabled, key-only `ansible-admin`. **Missing from docs as explicit hardening:**
  - **fail2ban / SSH rate-limit** on the VPS (it's a public IP now).
  - **Limiting AllowUsers already done**, but add **`MaxAuthTries`, `PasswordAuthentication no`, `Source address filter`** — and note `Fail2ban` availability.
  - **Docker/container escape hardening on the public host:** review that the VPS `docker_services` compose uses `cap_drop`/`read_only`/`tmpfs` where possible and no public container gets `privileged`.
- **Risk:** docs mention hardening *aspirationally*; the concrete VPS-specific OS/edge hardening (fail2ban, ssh config knobs, iptables default-deny) lives partly in `services-vps.md` §VPS firewall (deny-all except 443+WG) — **make it a required checklist item**, not a design spec.

### 2.2. 🔴 `wireguard` VPS peer gating = a security-clearance gap
- `playbooks/vps.yml` runs the `wireguard` role only when `wg_s2s_vps.peer_public_key` is non-empty (i.e. provisioned). Until then **no tunnel**, so the home-plane is not reachable from VPS. That is **fail-safe now**, but **the surface once the tunnel is up** (VPS → home LAN over `wg-s2s`, route `site`/`wg-vps-services`) must be **least-access**: 
  - **Recommend:** define an **ACL on the tunnel**: VPS Prometheus/Loki reach home exporters + HA-VIP + probes only (not general LAN r/w). Document which home subnets/ports the VPS may reach and enforce in WireGuard AllowedIPs + a RouterOS INPUT rule. Today it routes `site` (whole /16) + `wg-vps-services` — **too broad** for a compromised-VPS blast radius.

### 2.3. 🟡 Docker `services-internal` still relies on no-auth sibling trust
- `security.md` §4 + `deployment-compose.md` §"internal auth" already mitigate (**llm-backend** Ollama isolation, Kopia htpasswd, Prometheus basic-auth, Signal API token). 
- **Remaining gap:** other `services-internal` siblings (e.g. technologies, dozzle, a future API) still assume the overlay is trusted. **Recommend:** extend the HD-59 discipline — a supply-chain compromise in **any** public image on `services-internal` currently crosses to sibling services on the same overlay. For anything holding/writing data, add a per-service token/header. This is the single most valuable hardening thread after VPS SSH.

### 2.4. 🟡 Root/container escape on media/*arr (deliberate trade-off)
- The `*arr` stack + Jellyfin have needed host/NFS access + (in some cases) `PUID/PGID` to a neutral owner; Docker `cap_drop` isn't applied to all of them. Acceptable (they're internal/LAN), but **document the boundary**: they must **never** be on `traefik-public` or have WAN exposure; and they shouldn't join `services-internal` for non-media peers. Verify `traefik.enable` is false or no public DNS for every media/**arr** row (already claimed internal-only).
- Sunication ports (47989-48010) bound to Home VLAN — confirm this stays (manual-start, LAN/VPN clients) and that the bind is a **specific VLAN IP**, not 0.0.0.0.

### 2.5. 🟡 Secrets render-time 1Password — one exposure each deploy, already mitigated
- The `lookup` at render time is correct (no cached secret). **Watch:** the Authentik `secret-egress glue` writes OIDC client creds **into the 1Password `Homelab` items on the VPS**. Confirm the glue's **write-scoped `authentik-provision_api`** is scoped to issuer/app/flow/outpost only (least-priv) and **never** the read `authentik-api_token`. This is already a security.md §6 rule; **verify it's enforced in the glue + by the token scope**, and that the glue writes `field=username/credential` (`oidc` type) not password.

### 2.6 / security.md "certificates"
- Wildcard `*.kogler.si` via DNS-01 on the **VPS** Traefik — for a public host the ACME acct + Cloudflare token in 1Password is fine. **Recommend:** a Grafana cert-expiry alert rule (HD-130 has one) — confirm it covers the **VPS-issued** wildcard (not just the Pi edge).

### 2.7 / Home-media & backups — 
- **`bulk/media` unbacked** — accepted (redownloadable). **Verify the security posture note:** no attacker-writable path; the *arr stack (usenet→*) writes to `downloads`, so **keep `downloads` off the public/proxy plane** and confirm qB/TORRENT egress stays the sole externally-reaching path.

### 2.8 / Secret rotation hygiene
- `n8n_password` (immutable encryption key) vs `n8n-webhook_api` (rotatable) — **good split** (HD-77). Recommend a **rotation checklist** for the rotatable tokens (Signal internal API, Grafana SMTP, HA api) in `security` so they aren't permanent.

## 3. Recommended security enhancements (prioritized)

| # | Action | Priority | Owner |
|---|--------|----------|-------|
| 1 | VPS: explicit SSH hardening (MaxAuthTries, SourceAlive, fail2ban) + container hardening + default-deny inbound (accept 443 + WG port) committed as a **checklist item, not just prose** | 🔴 | `deployment-preseed.md` (VPS), `services-vps.md`, `security.md` §6 |
| 2 | **Nail down the VPS→home tunnel blast radius**: WireGuard AllowedIPs + RouterOS INPUT-list so VPS reaches **only** the exporter/VIP/probe targets, not `site /16` rw | 🔴 | `network-vpn.md`, `router.yml`, `all.yml` (`wg_s2s_vps.allowed_ips`) |
| 3 | **services-internal sibling auth** (HD-59 discipline for every data-writing sibling): token/header on each exposed-data sibling | 🔴 | `deployment-compose.md`, `security.md` §4 |
| 4 | **Fail2Ban** (or IP-throttle) on VPS SSH + n8n/Grafana/Forgejo public login (CrowdSec partly covers; add a host-level rate-limit) | high | `services-vps.md` |
| 5 | **Persistence/rotation**: document which tokens are rotatable + add a rotation mini-runbook | 🟡 | `deployment-secrets.md` / `security.md` |
| 6 | **blackbox liveness** — extend to liveness of the **home↔VPS** link (router CON/WG up probe) so tunnel-down is a first-class alert | 🟡 | `observability.md`, `monitoring` role |
| 7 | **Fail-loud glue + least-privilege** — confirm `authentik-provision_api` write-scope + read/write token split in the secret-egress glue is enforced (code-review item) | 🟡 | `deployment-compose.md`, `services-authentik.md` |
| 8 | **Docs-SSOT honesty**: any security rule that lives in a doc must have a matching IaC enforcement or a ⏳ deploy-gate — the security docs shouldn't say "we harden X" if X isn't deployed yet | 🟡 | all security/hardware/service docs |

## 4. What NOT to change (keep the current safe postures)
- No watchtower on HA (Renovate+stable only) — keep.
- No Doco-CD (docker.sock root) — keep removed.
- No public/TileBoard/watchtower — already decided-away.
- Open Matrix federation with hardening — accepted, documented.
- No `0.0.0.0` host binds (loopback/VLAN-only) — keep.

> **Top ask:** the two highest-value changes are **#1 (explicit VPS hardening checklist)** and **#2 (tunnel least-access ACL)**. Both are "design → enforced" hardening the current docs only describe aspirationally, and both materially reduce the blast radius of the one public host + the one tunnel into the home LAN.