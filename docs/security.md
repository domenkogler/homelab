---
title: Security Hardening Posture
role: detail
domain: deployment
cross_cutting: true
status: active
tags: [security, waf, hardening, secrets, bootstrap]
---
# Security Hardening Posture

> **Role:** Security hardening posture (cross-cutting) — the durable "how we secure the homelab" reference, distilled from
> the Qwen security audits into ongoing rules. Each section states an *ongoing policy* and links (a) the
> owning doc that implements it and (b) the canonical `todo.md` **HD-xx** tracking row. The underlying
> raw findings live in the evidence annex `../reports/Qwen-bugs.md` (referenced below as *evidence* where useful);
> **HD-xx rows are the primary tracking handle**, KOPS ids are the archived annex footer.
> **Links to:** `services-traefik.md`, `deployment-compose.md`, `deployment-secrets.md`,
> `deployment-preseed.md`, `smart-home-failover.md`, `backup.md`, `network-ops.md`, `network-vpn.md`,
> `observability.md`, `deployment-renovate.md`, `services-authentik.md`
> **Linked from:** `deployment.md`, `../README.md`, `index.md`

Each of the first six sections maps to one systemic flaw (Flaw A–F) from the architecture audit. Everything is
tracked in `../todo.md` (HD-XX rows, `source: qwen`). §§8–9 fold the post-HD-135 public-VPS + tunnel
hardening recommendations from the 2026-08-19 security audit (the temporary root `security.md`/`architecture.md`
were deleted after folding — HD-153).

## 1. Edge WAF (Flaw A)

> **Law:** every internet- or LAN-facing route must carry **at least one** of `authentik-forward-auth@file`
> or `crowdsec-only@file`. A service that skips Forward-Auth (because it has its own login) must **still**
> get `crowdsec-only` — it must never be left with zero edge protection.

**Middleware map:**
- `authentik-forward-auth@file` — bundles Authentik OIDC + CrowdSec bouncer. App-facing routes with a
  managed login (most web apps).
- `crowdsec-only@file` — CrowdSec bouncer only. Self-auth'd services that deliberately skip Forward-Auth
  (native SSO / own login).

**Route that skip Forward-Auth and MUST carry `crowdsec-only@file` (all → HD-60):**
- `ha.kogler.si` (HA native auth)
- `media.kogler.si` (Jellyfin login)
- `seerr.kogler.si` (Seerr login)
- `matrix.kogler.si` (Matrix-native OIDC)
- `chat.kogler.si` (Element Web, homeserver SSO)
- `file.kogler.si` (OpenCloud — native OIDC, HD-144)
- `foto.kogler.si` (Immich — native OIDC, HD-148)
- `ai.kogler.si` (Open WebUI — native OIDC, HD-101)
- `sso.kogler.si` (Authentik itself — it IS the auth provider, so Forward-Auth would be circular; **HD-194**: the bouncer filters by source IP only and every callback path (`/application/o/<slug>/callback/`, `/outpost.goauthentik.io/*`) arrives as an ordinary browser request from a user IP — outpost↔server API traffic runs container-direct on services-internal, never through this router; brute force is additionally covered by the fail2ban `http-auth` jail)
- cockpit-nas/cockpit-oldsrv file-provider routes (own-login mgmt surface, HD-188)
- HA standby via VIP

Owning doc: [services-traefik.md](services-traefik.md). **Tracked: HD-60** (crowdsec-only middleware
chain), HD-72 (HA caps). *Evidence: KOPS-004/018/047/025.*

## 2. Version pinning (Flaw B)

> **Law:** no mutable image tags in production. Every service image must use an explicit semver/manifest
> pin defined as a variable in `group_vars/*.yml`, tracked by Renovate — never `latest`, never a mutable
> alias such as `-rocm`.

- **Traefik** — pinned `traefik_version: v3.5.2` (HD-61, done).
- **Every `:latest`** across the compose templates → pinned var. **HD-192 (done 2026-08-21):** all
  templates now render `{{ *_version }}` pins from `group_vars/all/versions.yml` (registry-verified);
  the only remaining `latest` renders are the documented fluid exceptions (tuwunel HD-121,
  profilarr — no versioned tags upstream). The validator allowlist is inverted: bare-`latest`
  fails unless in `ALLOWED_LATEST` with a MUST-pin justification.
- **Ollama `:rocm`** mutable alias → pinned to a specific `<ver>-rocm` build tag (`ollama_version`,
  HD-192; the RX 7600 needs the ROCm-bundled variant).

Owning docs: [deployment-compose.md](deployment-compose.md),
[deployment-renovate.md](deployment-renovate.md). **Tracked: HD-61.**

## 3. Host port-binding policy (Flaw C)

> **Law:** no service binds a container port to `0.0.0.0` on the host. Prefer the Docker overlay network
> (containers reach each other by service name). When a host port cannot be avoided, bind loopback
> (`127.0.0.1:p:p`) or a specific VLAN IP.

- **Signal CLI** `8080:8080` — remove the host bind (n8n reaches it by name). **HD-62** *(evidence: KOPS-002)*.
- **Prometheus** `9090:9090` — bind loopback. **HD-62** *(evidence: KOPS-017)*.
- **Technitium** `53:53` — bind a specific VLAN IP. **HD-62** *(evidence: KOPS-015/064)*.
- **Sunshine** `47989-48010` — restrict to Home VLAN IP. **HD-62** *(evidence: KOPS-007)*.

Owning doc: [deployment-compose.md](deployment-compose.md). **Tracked: HD-62.**

## 4. Container minimum privilege (Flaw D)

> **Law:** prefer targeted `devices:` and `cap_add:` over `privileged`, broad `NET_ADMIN`, or
> `network_mode: host`. No container runs as root, or with host networking, without a documented reason.

- **HA primary** — move `privileged: true` + `network_mode: host` to targeted `devices:` + `cap_add:`
  (**HD-72**). `network_mode: host` is only justified for keepalived VRRP multicast; keep the minimum VRRP
  needs. *(evidence: KOPS-014)*. Owning doc: [smart-home-failover.md](smart-home-failover.md).
- **Technitium** — runs as root with `NET_ADMIN` on port 53; add `user:` and drop `NET_ADMIN` if not
  required (**HD-62** host-port policy; evidence: KOPS-015/032).

**Tracked: HD-72, HD-62.** *(HD-77 was the Doco-CD Forgejo-token split — dropped with Doco-CD, HD-150.)*

## 5. Backup coverage (Flaw E)

> **Law:** every stateful database must be covered by `db-backup` (or Kopia) **before** go-live. A lost DB
> loses metadata that cannot be reconstructed from the original media/bytes.

- **immich** Postgres — albums, faces, labels, smart-search embeddings. **HD-63** *(evidence: KOPS-026)*.
- **opencloud** Postgres — document versions / metadata. **HD-63**.
- Add/uncomment the `immich-postgres` + `opencloud` DB blocks in `db-backup`. Note the real service
  hostname is `immich-postgres`, *not* the stale `immich-db` comment.

Owning docs: [backup.md](backup.md), [storage.md](storage.md). **Tracked: HD-63.**

## 6. Bootstrap hygiene (Flaw F)

> **Law:** nothing in the bare-metal/bootstrap path may ship with shared or default credentials, or expose
> management services beyond the Management VLAN.

- **Preseed root password** — use a unique per-host hash, or `root-login false` (**HD-80**; evidence
  KOPS-044). Owning doc: [deployment-preseed.md](deployment-preseed.md).
- **Router API** — restrict to the Management VLAN interface in the bootstrap `.rsc`, or disable if no TLS
  (**HD-83**; evidence KOPS-003/042). Owning doc: [network-ops.md](network-ops.md).
- **Shared RouterOS admin (HD-165, accepted)** — one `mikrotik-admin_login` password across router + switch
  + APs is an **accepted** risk **because every management surface binds to the Management VLAN (99) only**
  (router `api`/`www-ssl`/`ssh` = `interface=vlan99-mgmt`; switch + APs are L2-only, no WAN egress); the shared
  credential never crosses an internet boundary. Revisit per-gear items only if a gear gains WAN-exposed
  management or the Mgmt-VLAN ACL changes. Owning docs: [deployment-secrets.md](deployment-secrets.md), [network-ops.md](network-ops.md).
- **Switch port map** — `group_vars/switch.yml` must exist before first switch deploy so unused ports
  don't all land on VLAN 99 (folded into **HD-03**; evidence KOPS-043).
- **Fail-loud secrets** — no `default('')`; a missing 1Password secret must fail loudly, not deploy an
  unprotected service (**HD-65**; evidence KOPS-010). Owning doc: [deployment-secrets.md](deployment-secrets.md).
- **Authentik provisioning token least-privilege** — the **write-scoped** `authentik-provision_api`
  (Blueprint apply + secret-egress glue) must be scoped to issuer/app/flow/outpost endpoints *only*;
  the **read-only** `authentik-api_token` (NAS glue) must never be granted write scope. See
  [`services-authentik.md`](services-authentik.md) *OIDC client provisioning* / [`deployment-secrets.md`](deployment-secrets.md).
- **Preseed defaults / post_install** — dedupe the `sshd_config` append (**HD-88**; evidence KOPS-012).

Owning docs: [deployment-preseed.md](deployment-preseed.md),
[deployment-secrets.md](deployment-secrets.md), [network-ops.md](network-ops.md).
**Tracked: HD-65, HD-80, HD-83, HD-88, HD-03.**

## 6a. Internal sibling auth (HD-160)

> **Law:** every **data-writing `services-internal` sibling** carries per-service token/header auth, or a
> documented network-isolation decision — so a supply-chain compromise in any public image on the
> overlay can't write to a sibling (extends HD-59, which covered Kopia/Prometheus/Signal/Ollama).

- **Coverage map (SSOT):** [`deployment-compose.md`](deployment-compose.md) *§ Container Security →
  Sibling-auth coverage map* — every writer→receiver pair, its auth mechanism, 1Password item and
  status.
- **Deliberate isolation decisions (accepted, not gaps):**
  - **Ollama** — no native server auth (`OLLAMA_AUTH_*` is ollama.com-cloud only) → stays on the
    dedicated `llm-backend` overlay reachable only by LiteLLM (**HD-59**).
  - **docling** — no supported API-key mechanism → treated like Ollama; consumed only by the AI
    stack over the overlay (see [`services-ai.md`](services-ai.md)).
- **Cross-host reaches** (`immich-app→immich-ml`, `n8n→signal-cli`) traverse the WG tunnel; the
  token is enforced at the **receiving** service.
- **Fail-loud (HD-65):** a missing `-internal_api` / `_api` item aborts the render — never
  `default('')`.

Owning doc: [`deployment-compose.md`](deployment-compose.md). **Tracked: HD-160.**

---

## 7. Decision log

> Accepted/closed policy decisions — recorded so they are **not** re-raised as open bugs on future scans.
> (Populated from the AUD-02 dispositions; AUD-13 keeps this current.)

- **Matrix open federation** — **accepted/expected, kept by decision (HD-122, 2026-08-18).** Open federation affirms
  the original 2026-08-16 acceptance: a federated Matrix homeserver interoperating with the wider Matrix world.
  The "any Matrix user can DM the family" concern is mitigated WITHOUT breaking federation via
  `require_auth_for_profile_requests=true` (stops anonymous profile/MXID scraping) + `allow_public_room_directory_over_federation=false`
  (blocks `/publicRooms` enumeration). `trusted_servers` is a **key-notary** list, not an ingress permit-list —
  there is no per-server inbound federation allow-list in Conduwuit/Tuwunel; unsolicited DMs are handled client-side
  (per-user ignore/block). IaC: `tuwunel.toml.j2`. *(evidence: KOPS-033 → closed, HD-122)* Owning doc: [`services-matrix.md`](services-matrix.md).
- **SNMP v2c default community** — **Decided (HD-53, Option A):** dedicated read-only community (`network-snmp_api`, in 1Password) replacing `public`, with SNMP (161/udp) **restricted to the Management VLAN** via router INPUT-chain ACL. KOPS-034 closed. Date: 2026-08-18. *(evidence: KOPS-034)* Owning doc: [`observability.md`](observability.md).
- **Playbook role order** (`network` before `storage` on oldsrv) — documented as accepted; not a bug.
  *(evidence: KOPS-050)* Date: 2026-08-16.
- **Homepage docker.sock health widget** — accepted (read-only mount, behind Forward-Auth).
  *(evidence: KOPS-058)* Date: 2026-08-16.
- **Seerr SQLite single-file** — accepted risk (reconfig takes ~15 min; keep in Kopia scope).
  *(evidence: KOPS-059)* Date: 2026-08-16.
- **services-internal sibling auth** — **done (HD-160, 2026-08-20):** every data-writing
  `services-internal` sibling now has per-service token/header auth or a documented isolation
  decision. Ollama isolated on `llm-backend` (HD-59); OpenClaw→OpenCloud via scoped
  app-specific password (`openclaw-opencloud_api`); immich-app→immich-ml via native ML API key
  (`immich-ml-internal_api`). Coverage map: `deployment-compose.md` §Sibling-auth coverage map.
  *(evidence: KOPS-001/002/016 → closed, HD-59/HD-125/HD-160)*

## 8. Public VPS host hardening (HD-154)

> **Law:** the VPS is the **single public trust boundary** — the biggest surface exposed to the internet.
> Its OS/SSH/Docker surface must be hardened as an explicit **checklist item at VPS deploy (HD-40A/154)**, not
> left as aspirational design prose. **Enforced (2026-08-19, HD-154):** the mandatory checklist now lives in
> `docs/services-vps.md` §VPS-Specific Firewall as a verify-command table, **and** is implemented as executable
> IaC by the **`vps-hardening` Ansible role** (`playbooks/vps.yml` before `docker_services`) + the
> `IaC/host/vps/post_install.sh` sshd extras. A VPS deploy that skips the role fails review.
> Folded from the 2026-08-19 security audit (HD-153).

- **SSH hardening** ✅ — `MaxAuthTries 3`, `PasswordAuthentication no`, `PermitRootLogin no`, key-only `ansible-admin`
  (post_install.sh + role assert); **fail2ban** SSH jail (`maxretry 3`) + `http-auth` jail for public login pages
  (n8n/Grafana/Forgejo). Owned by [deployment-preseed.md](deployment-preseed.md) (VPS) + [services-vps.md](services-vps.md)
  §VPS-Specific Firewall + `roles/vps-hardening/`. **HD-154. ✅ enforced.**
- **Container/escape hardening** ✅ — the VPS `docker_services` compose uses `cap_drop`/`read_only`/`tmpfs` where
  possible; no public container gets `privileged` / host networking without a documented reason (§4 applies);
  daemon `userland-proxy: false` + `live-restore: true`. **HD-154. ✅ enforced (daemon) + compose-policy.**
- **VPS firewall default-deny** ✅ — inbound **deny-all except :443 + :51820 (WG)** via the `vps-hardening` role's
- **Published-port bypass closed (S1, HD-186):** docker-published ports traverse the *forward* chain (`oifname "docker*" accept`), so the input default-deny does not cover them. **Implemented (decided HD-204): no public publishes** — authentik's all-interfaces LDAP `3389` publish was removed; the outpost binds only the WG S2S address (prometheus/loki precedent), and Samba (nas, the client) pulls over the tunnel. Verify row added to the `services-vps.md` §VPS-Specific Firewall checklist (external `nc`/`ldapsearch` must refuse; WG-side must connect). Documented future-hardening option if a public publish is ever required: a **DOCKER-USER filter chain** restricting forwarded dports (443 from any; specific ports from the WG peer only) — implement only then, as its own gated task. **HD-186. ✅ IaC; ⏳ live-verify at deploy.**
  `/etc/nftables.conf` (nftables, input policy drop). Committed as executable checklist, not prose. **HD-154. ✅ enforced.**
- **SSO on VPS admission** ✅ — the netcup `post_install.sh` SSH config matches the preseed defaults; root-login
  disabled, per-host keys (Domen + Ansible), no `ai-debug` on a public box
  (see [deployment-preseed.md](deployment-preseed.md) → VPS Deviations). **HD-154. ✅ enforced.**

## 9. Home↔VPS tunnel least-access (HD-155)

> **Law:** the `wg-s2s` home↔VPS tunnel must be **least-access**, not a wide-open bridge. Today `vps.yml` routes
> `site` (whole /16) + `wg-vps-services` from the VPS into the home plane — **too broad** for a compromised-VPS
> blast radius. Folded from the 2026-08-19 security audit (HD-153).
>
> **Enforced (2026-08-19, HD-155):**
> - **WireGuard AllowedIPs** scoped on BOTH sides (`all.yml` `wg_s2s_vps.allowed_ips` + `router.yml` `wireguard_s2s_vps.allowed_ips`)
>   to the **specific home targets** only — nas (nut:9199/zfs:9198), ha-vip (HA:8123), oldsrv + pi (probes/backends),
>   router/switch (ICMP) — **NOT** the whole `site` /16. Derived from `network_static_hosts` by name (no literals).
> - **RouterOS forward ACL:** a `vps_s2s_peer` address-list may reach only `vps_scoped_home`; everything else from
>   the VPS peer is **DROPPED** (fail-loud blast radius on the router, independent of crypto AllowedIPs).
> - **fail-loud WG gate:** the `wireguard` role already asserts an **empty peer pubkey aborts** (assert task, HD-65/91) —
>   a run never looks like it configured WG when it didn't. (`playbooks/vps.yml` also gates the role on
>   `wg_s2s_vps.peer_public_key` non-empty.)
>
>   `wg_s2s_vps.peer_public_key` non-empty.)
>
> **Design note (superseded by the enforcement above):** the original recommendation was an ACL on the tunnel —
> WG gate. That is now implemented; see the enforced items above.
>
> Owning docs: [network-vpn.md](network-vpn.md), [services-vps.md](services-vps.md), `router.yml`, `all.yml`
> (`wg_s2s_vps.allowed_ips`). **HD-155 (IaC + ACL), HD-03 (deploy-gate).**