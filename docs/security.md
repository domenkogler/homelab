---
title: Security Hardening Posture
role: detail
domain: security
status: active
tags: [security, waf, hardening, secrets, bootstrap]
---
# Security Hardening Posture

> **Role:** Security hardening posture — the durable "how we secure the homelab" reference, distilled from
> the Qwen security audits into ongoing rules. Each section states an *ongoing policy* and links (a) the
> owning doc that implements it and (b) the canonical `todo.md` **HD-xx** tracking row. The underlying
> raw findings live in the evidence annex `../reports/Qwen-bugs.md` (referenced below as *evidence* where useful);
> **HD-xx rows are the primary tracking handle**, KOPS ids are the archived annex footer.
> **Links to:** `services-traefik.md`, `deployment-compose.md`, `deployment-secrets.md`,
> `deployment-preseed.md`, `smart-home-failover.md`, `backup.md`, `network-ops.md`, `network-vpn.md`,
> `observability.md`, `deployment-renovate.md`, `services-authentik.md`
> **Linked from:** `../README.md`, `index.md`

Each of the six sections maps to one systemic flaw (Flaw A–F) from the architecture audit. Everything is
tracked in `../todo.md` (HD-XX rows, `source: qwen`).

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
- HA standby via VIP

Owning doc: [services-traefik.md](services-traefik.md). **Tracked: HD-60** (crowdsec-only middleware
chain), HD-72 (HA caps). *Evidence: KOPS-004/018/047/025.*

## 2. Version pinning (Flaw B)

> **Law:** no mutable image tags in production. Every service image must use an explicit semver/manifest
> pin defined as a variable in `group_vars/*.yml`, tracked by Renovate — never `latest`, never a mutable
> alias such as `-rocm`.

- **Traefik** — pin `traefik_version` (currently `latest`) to a semver. **HD-61**.
- **Every `:latest`** across the 42 compose templates → convert to a pinned var. **HD-61**
  (owning doc: [deployment-compose.md](deployment-compose.md)).
- **Ollama `:rocm`** is a mutable alias → pin to a specific `0.6.x-rocm`. **HD-61** *(evidence: KOPS-027)*.

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
- **Doco-CD** — host-network + `docker.sock:rw` + Forgejo write token. Keep `cap_drop: ALL`, distroless
  non-root; split the Forgejo token to bound write scope (**HD-77**; evidence: KOPS-024/055).

**Tracked: HD-72, HD-62, HD-77.**

## 5. Backup coverage (Flaw E)

> **Law:** every stateful database must be covered by `db-backup` (or Kopia) **before** go-live. A lost DB
> loses metadata that cannot be reconstructed from the original media/bytes.

- **immich** Postgres — albums, faces, labels, smart-search embeddings. **HD-63** *(evidence: KOPS-026)*.
- **opencloud** Postgres — document versions / metadata. **HD-63**.
- Add/uncomment the `immich-postgres` + `opencloud` DB blocks in `db-backup`. Note the real service
  hostname is `immich-postgres`, *not* the stale `immich-db` comment.

Owning docs: [backup.md](backup.md), [storage-zfs.md](storage-zfs.md). **Tracked: HD-63.**

## 6. Bootstrap hygiene (Flaw F)

> **Law:** nothing in the bare-metal/bootstrap path may ship with shared or default credentials, or expose
> management services beyond the Management VLAN.

- **Preseed root password** — use a unique per-host hash, or `root-login false` (**HD-80**; evidence
  KOPS-044). Owning doc: [deployment-preseed.md](deployment-preseed.md).
- **Router API** — restrict to the Management VLAN interface in the bootstrap `.rsc`, or disable if no TLS
  (**HD-83**; evidence KOPS-003/042). Owning doc: [network-ops.md](network-ops.md).
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

## 7. Decision log

> Accepted/closed policy decisions — recorded so they are **not** re-raised as open bugs on future scans.
> (Populated from the AUD-02 dispositions; AUD-13 keeps this current.)

- **Matrix open federation** — **accepted/expected, kept by decision (HD-122, 2026-08-18).** Open federation affirms
  the original 2025-08-16 acceptance: a federated Matrix homeserver interoperating with the wider Matrix world.
  The "any Matrix user can DM the family" concern is mitigated WITHOUT breaking federation via
  `require_auth_for_profile_requests=true` (stops anonymous profile/MXID scraping) + `allow_public_room_directory_over_federation=false`
  (blocks `/publicRooms` enumeration). `trusted_servers` is a **key-notary** list, not an ingress permit-list —
  there is no per-server inbound federation allow-list in Conduwuit/Tuwunel; unsolicited DMs are handled client-side
  (per-user ignore/block). IaC: `tuwunel.toml.j2`. *(evidence: KOPS-033 → closed, HD-122)* Owning doc: [`services-matrix.md`](services-matrix.md).
- **SNMP v2c default community** — **Decided (HD-53, Option A):** dedicated read-only community (`network-snmp_login`, in 1Password) replacing `public`, with SNMP (161/udp) **restricted to the Management VLAN** via router INPUT-chain ACL. KOPS-034 closed. Date: 2026-08-18. *(evidence: KOPS-034)* Owning doc: [`observability.md`](observability.md).
- **Playbook role order** (`network` before `storage` on oldsrv) — documented as accepted; not a bug.
  *(evidence: KOPS-050)* Date: 2025-08-16.
- **Homepage docker.sock health widget** — accepted (read-only mount, behind Forward-Auth).
  *(evidence: KOPS-058)* Date: 2025-08-16.
- **Seerr SQLite single-file** — accepted risk (reconfig takes ~15 min; keep in Kopia scope).
  *(evidence: KOPS-059)* Date: 2025-08-16.