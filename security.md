# Security Audit (Round 2)

> **Role:** Audit deliverable — security posture assessment: documented controls vs implemented IaC,
> gaps, and prioritized enhancements. Produced 2026-08-21 per `prompt.md`.
> **Linked from:** `prompt.md`; siblings: `docs-vs-iac.md`, `docs-changes.md`, `iac-changes.md`,
> `conventions-sugestions.md`, `tracking-sugestions.md`, `architecture.md`.
> **Context:** nothing is live except the provisioned VPS host; findings are about the IaC that *will*
> deploy. Canonical posture doc: `docs/security.md` (this file proposes changes to it, not a rival).

---

## 1. Posture digest (documented + implemented)

- **Trust boundaries:** internet → VPS (single public boundary: nftables default-deny :443/:51820,
  fail2ban, hardened sshd, CrowdSec+Traefik edge) → WG S2S (least-access AllowedIPs + RouterOS
  forward ACL, fail-loud pubkey gate) → VLAN-segmented LAN (default-deny inter-VLAN, mgmt services
  bound to Mgmt VLAN, CAPsMAN SSID→VLAN map).
- **Identity:** Authentik SSO (passkeys/WebAuthn); Forward-Auth default with `crowdsec-only` for
  self-auth'd routes; native-OIDC exceptions declared via Blueprint + secret-egress glue.
- **Secrets:** 1Password single vault at render time, fail-loud (no `default('')`), naming convention,
  rename map, provisioner with rotate support; SSH key separation (personal/ansible/ai-debug with
  restricted from= and no-sudo dispatcher).
- **Containers:** cap_drop/read_only/tmpfs policy, no host ports unless justified, internal sibling
  auth coverage map (HD-160), pinned versions via Renovate (law).
- **Ops:** ai-debug user can never run Ansible or gain sudo beyond the read-only dispatcher;
  assert-before-mutate on router/switch; two-sided deploy-gate discipline.

This is a strong posture for the class of system. The findings below are where implementation lags
the documented law, plus a few genuine design gaps.

## 2. Findings

| ID | Sev | Area | Finding | Evidence | Recommendation |
|----|-----|------|---------|----------|----------------|
| S1 | **H** | VPS firewall | The nftables forward chain accepts `iifname/oifname "docker*"`, which also accepts Docker's DNAT'd **published** ports from the WAN — published ports bypass the input-chain default-deny. Meanwhile the authentik compose publishes LDAP outpost `3389:3389` on all interfaces (comment says "restrict src at firewall", but the firewall doesn't). Net effect: the "deny-all except :443/:51820" claim does not hold for docker-published ports. | `roles/vps-hardening/templates/nftables.conf.j2` forward chain; `templates/docker_services/authentik/docker-compose.yml.j2` ports block | Either (a) remove the 3389 publish — reach the LDAP outpost over wg-vps-services instead; or (b) add a DOCKER-USER-style filter chain restricting forwarded dports to 443 (+ explicit LDAP source = WG peer); or (c) bind the publish to the WG peer IP. Also fix the template comment that claims input-chain protection covers it. |
| S2 | **H** | Supply chain | 21 services ship bare `:latest`; mutable aliases persist (`ollama:rocm`, HA `stable`, immich `release`) despite CONVENTIONS §7 and HD-134 marked done. Renovate tracks latest tags but cannot pin what upstream re-points. | grep over `templates/docker_services/*/docker-compose.yml.j2` (full list in `iac-changes.md` §3) | Pin all remaining images in `versions.yml` after one registry verification each; make missing pins fail the render; extend validator denylist. |
| S3 | **M** | Ansible guard | site.yml pre-flight admin-user guard covers home_servers/raspberry_pi/storage but **not vps** — the one internet-facing host (comment still says "Phase 2"). common-role assert backstops it, but defense-in-depth should not skip the public box. | `IaC/ansible/site.yml` guard play | Add `vps` to the play's host pattern now that HD-40A provisioned it. |
| S4 | **M** | Network bootstrap | crs328 template enables api/www-ssl/ssh without interface binding; ap template leaves ssh unbound on a flat bridge including WLAN interfaces — management surfaces listen on all ports during the bootstrap window. rb4011 does it right (`interface=vlan99-mgmt`). | `IaC/router/templates/crs328_initial.rsc.j2`, `ap_initial.rsc.j2` vs `rb4011_initial.rsc.j2` | Mirror the rb4011 binding pattern in both templates before Phase 1.5 cutover. |
| S5 | **M** | Host ports | HD-62 items partially unapplied: technitium publishes `53:53` on all interfaces (comment reinterprets the law as "by design"), sunshine publishes its port range unbound, pihole publishes 5353, raspberrymatic publishes XML-RPC/UI ports (parked service still rendering). On a flat pre-VLAN network today these are LAN-wide binds. | respective compose templates | Bind to the Home-VLAN node IP (or loopback + explicit firewall rule) when the network role lands; until then accept + keep the ⏳ markers accurate. |
| S6 | **M** | HA container | HA primary still runs `privileged: true` + `network_mode: host` (HD-72 open). Documented as official-guidance, but it is root-equivalent on the smart-home controller reachable via the VIP route. | `templates/docker_services/home-assistant-primary/docker-compose.yml.j2` | Execute HD-72 as planned (targeted devices/cap_add; keep host-net only for the VRRP sidecar if unavoidable). |
| S7 | **M** | Cert/TLS | Wildcard-cert issuer ambiguity (VPS vs oldsrv) — besides ops risk, it determines which host holds the ACME account + DNS-01 token blast radius. | `docs-vs-iac.md` §C | Decide once (changelog), align texts; prefer the VPS as issuer (public edge, always-on) and turn oldsrv/Pi into cert consumers — but either answer is acceptable if single. |
| S8 | **L** | SSH | `host_key_checking = False` globally in ansible.cfg — TOFU accepted for bootstrap, but the VPS fingerprints are already recorded in deployment-ansible.md for pinning. | `ansible.cfg`; deployment-ansible.md fingerprint table | Move to a provisioned known_hosts (or per-host `host_key_checking` override) once hosts are stable. |
| S9 | **L** | Network gear | Shared MikroTik admin credential across router/switch/APs + default `admin` user retained (renamed-password only). Accepted under HD-165 because mgmt binds to Mgmt VLAN — but the acceptance *depends* on S4's bindings being applied everywhere including APs. | rb4011/ap/crs328 templates; deployment-secrets HD-165 note | Keep the shared cred only while every mgmt surface is interface-bound; revisit per-gear items at first AP add. |
| S10 | **L** | Preseed | Placeholder disk IDs/pubkeys ship in preseeds; wrong-disk partitioning or locked-out Pi possible if placeholders aren't replaced (no loud guard outside oldsrv's pool create). | nas/oldsrv/vps preseeds; pi first-boot script | Add post-install placeholder assertions (B5 proposal, conventions-sugestions.md). |
| S11 | **L** | Loki | Multi-tenant auth is tenant isolation, not authentication — a compromised db-internal container can forge the tenant header. Accepted in observability.md for Phase 1 set. | observability.md HD-115 caveat | Keep accepted; revisit if db-internal membership grows beyond the current trusted set. |
| S12 | **L** | Secrets docs | Vault-name drift (`Homelab` vs `Homelab-ansible`) across README/comments could cause an operator to create items in the wrong vault; op_api story told three ways. | `docs-vs-iac.md` §E | Text sweep; adopt one canonical description of runner auth (1password.md is the most current). |
| S13 | **Info** | Backups | Backup integrity checks exist at push time (HD-127); Kopia client-side encryption to backup Box; restore drill yearly. No offline/immutable copy of the Kopia repo itself (ransomware could reach the Box via the leaked key) — standard residual risk worth stating in backup.md. | backup.md | Add one sentence acknowledging repo-immutability as accepted residual risk (or enable Box snapshot/versioning if available). |
| S14 | **Info** | Monitoring | Alert path has good fail-safes (Grafana SMTP parallel, NUT-side notify independent of stack). Gap: nothing alerts on *cert expiry* except the KOPS-061 Grafana rule (<14 days) — fine; but nothing monitors the WG tunnel from the *home* side (blackbox probes run from VPS). | observability.md; todo HD-159 | HD-159 already plans the wg_icmp probe — ensure it evaluates from the VPS against the router peer AND a home-side check exists after Phase 1.5 (router netwatch → SNMP trap or similar). |

## 3. Doc-vs-IaC security contradictions (summary)

1. `security.md` §2 claims traefik "currently latest" (it is pinned) while the broader pin law is
   unenforced for 21 services — both directions of drift in one section.
2. `vps-hardening` narrative ("input policy drop, allow :443/:51820") vs actual published-port
   behavior (S1) — the checklist verify commands would pass while 3389 stays exposed.
3. deployment-tasks Phase 4 instructs installing local Homematic + pihole on the Pi — services the
   security posture no longer includes (HD-13 parked; pihole lives on oldsrv).
4. `deployment-secrets.md` master list vs templates: `opencloud_login` consumed by compose but absent
   from the list; `op_api` present in list but declared never-created by 1password.md.

## 4. Prioritized enhancement plan

1. **S1** (published-port bypass) — before the first VPS deploy of authentik; smallest fix is
   removing/re-scoping the 3389 publish.
2. **S2** (pin sweep) — mechanical; converts the biggest supply-chain exposure.
3. **S3+S4** (guard scope + bootstrap bindings) — tiny diffs, do together.
4. **S5/S6** (host-port binds, HA caps) — execute the already-tracked HD-62/HD-72 at their phases;
   update security.md status markers when done rather than leaving ✅-style prose ahead of reality.
5. **S7** (issuer decision) — human call, then text alignment.
6. **S8–S13** — fold into the owning docs' next edits opportunistically.

> Cross-ref: detailed IaC mechanics in `iac-changes.md`; convention proposals B4/B5/A5 in
> `conventions-sugestions.md`; phase placement fixes in `tracking-sugestions.md`.

---

## 5. Deep-dive addendum (round 2) — role/template verification pass

Follow-up pass over the router/switch roles, the docker_services deploy path, and all 49 compose
templates line-by-line. New findings (S-numbers continue from §2):

| ID | Sev | Area | Finding | Recommendation |
|----|-----|------|---------|----------------|
| S15 | **M** | Header trust | **Authentik trusts the whole `traefik-public` /16** (`AUTHENTIK_TRUSTED_PROXIES` = the CIDR from `network_ranges`). This is the exact anti-pattern HD-81/KOPS-039 removed for HA: any compromised container on traefik-public can spoof `X-Forwarded-For` toward Authentik, poisoning client-IP decisions (rate-limit views, logging, and any future "internal network → skip MFA" conditional-access rule). | Mirror the HD-81 pattern: pin the Traefik edge container IP(s) in a group_var, not the /16. |
| S16 | **M** | Header trust | **Grafana auth-proxy trusts a raw header + auto-signup.** `GF_AUTH_PROXY_HEADER_NAME: X-authentik-email` with `GF_AUTH_PROXY_AUTO_SIGN_UP: "true"`: any container on traefik-public can bypass Traefik and reach `grafana:3000` directly on the overlay, send a forged `X-authentik-email`, and get an auto-created account (admin if it matches the admin email). The route's forward-auth protects only the HTTP edge path, not the overlay path. | Use a signed header (Authentik `X-authentik-jwt` validated via `GF_AUTH_PROXY_WHITELISTED_DOMAINS`/JWKS or `allow_insecure=false` header-signing), and set `AUTO_SIGN_UP: false` with explicit user provisioning. Same class fix as S15. |
| S17 | **M** | Edge law | **Two route families carry zero edge middleware.** (a) `sso.kogler.si` (the public login page — the most brute-force-attractive route in the system) has no bouncer; only the VPS fail2ban `http-auth` jail covers it. (b) `cockpit-nas`/`cockpit-oldsrv` file-provider routes have no middleware at all (docs document skipping Forward-Auth, not skipping CrowdSec). The §1 law says "never zero edge protection" — both are undocumented exceptions. | Add `crowdsec-only@file` to cockpit routes; for `sso`, either add the bouncer (verify Authentik outpost callbacks aren't blocked) or document the exception in security.md §1 with the compensating control named. |
| S18 | **M** | Backup | **oldsrv Kopia agent missing from the SSOT** (cross-ref `docs-vs-iac.md` J5): backup.md's off-site path for oldsrv-local state (dumps, service state, thumbs, `/opt/*` configs) has no deploying service. | Add the agent to `group_vars/home_servers.yml` or re-scope backup.md; until then oldsrv state relies on NAS pushes only (single-copy). |
| S19 | **M** | Network | **Kids VLAN controls unimplemented** (cross-ref J6): bedtime block, forced filtered DNS, Kids→Home drop are all doc-matrix items with no IaC behind them — the Phase 1.5 firewall-matrix verification would pass silently incomplete if Kids VLAN is treated as "done". | Implement or explicitly ⏳-mark the Kids rules in network-vlans.md + deployment-tasks Phase 1.5. |
| S20 | **L** | Network | **`trusted-ha` list unused; Home→IoT new-connections granted to `trusted-admin`** (includes nas) — slightly wider than the documented matrix; the HA-specific list exists but gates nothing. | Point the Home→IoT new rule at `trusted-ha` (or merge lists and update docs). |
| S21 | **L** | Secrets | `signal-cli-rest-api` uses `\| default('', true)` on the captcha lookup — the only fail-open secret in the tree. Arguably correct (captcha is registration-time only) but it violates the HD-65 no-defaults law silently. | Replace with a documented two-phase lookup or a comment exempting it explicitly. |
| S22 | **L** | Containers | The compose-convention hardening (cap_drop/read_only/tmpfs) is applied on **almost no template** — including the public-edge set (traefik, authentik, opencloud, forgejo). The convention exists in deployment-compose.md but the validator never enforced it. | Either roll out cap_drop/read_only per service at deploy-verify time, or add a validator check with a documented allowlist (GPU/VPN services exempt). |

### S1 verification plan (make the top finding testable)

S1 (published ports bypass the input default-deny via `oifname "docker*"` forward accept) is based
on source reading; confirm before first VPS deploy with:

1. `docker info` on the VPS → confirm firewall backend (iptables-nft vs nftables) and that
   `userland-proxy: false` (DNAT path, not proxy path).
2. After `vps-hardening` + authentik deploy: from an **external** host, `nc -vz <vps-public-ip> 3389`
   and `ldapsearch -H ldap://<vps-public-ip>:3389 -x -s base` — if either connects, S1 confirmed
   live. Also test from the WG peer (should connect — that path is intended for Samba).
3. `nft list ruleset` → verify no DOCKER-USER filtering exists and the forward chain order
   (`oifname docker* accept` present).
4. Fix options re-tested in the same order: (a) remove the 3389 publish and reach the outpost over
   `wg-vps-services` (preferred — Samba binds then target the VPS WG address); (b) add a
   DOCKER-USER chain allowing forwarded dport 3389 only from the WG peer, 443 from any;
   (c) bind the publish to the WG address as with prometheus/loki.
5. Add the winning option to `vps-hardening` as executable IaC + a verify line in the
   `services-vps.md` checklist table (so HD-154's verify pass covers it).

### Verified-good (round 2 pass)

HD-155 RouterOS ACL (address-lists + accept/drop pair + fail-closed pubkey assert) — implemented
exactly as documented; INPUT-chain mgmt gating and SNMP Mgmt-only ACL — exact; WG S2S peer config
and scoped AllowedIPs — exact; middleware law enforced on every labelled route (exceptions tracked
as S17); db-backup covers all four Postgres DBs; Blueprint declares exactly the 8 documented
providers; storage role dataset/property/snapshot parity with storage.md (nas side); Alloy
per-host instance label present; SNMP community fail-loud from 1Password.
