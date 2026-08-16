---
title: Security Hardening Posture
role: detail
domain: security
status: active
tags: [security, waf, hardening, secrets, bootstrap]
---
# Security Hardening Posture

> **Role:** Security hardening posture — the durable "how we secure the homelab" reference, distilled from
> the Qwen security audits (`../Qwen-bugs.md`) into ongoing rules. Each section below states an *ongoing
> policy/law* and links the owning doc that implements it; per-bug evidence lives in `../Qwen-bugs.md`.
> **Links to:** `services-traefik.md`, `deployment-compose.md`, `deployment-secrets.md`,
> `deployment-preseed.md`, `smart-home-failover.md`, `backup.md`, `network-ops.md`, `network-vpn.md`,
> `observability.md`, `deployment-renovate.md`
> **Linked from:** `../README.md`, `index.md`

The six sections below map 1:1 to the six systemic flaws (Flaw A–F) identified in the architecture audit.
Everything is tracked in `../todo.md` (HD-XX rows, `source: qwen`).

## 1. Edge WAF (Flaw A)

> **Law:** every internet- or LAN-facing route must carry **at least one** of `authentik-forward-auth@file`
> or `crowdsec-only@file`. A service that skips Forward-Auth (because it has its own login) must **still**
> get `crowdsec-only` — it must never be left with zero edge protection.

**Middleware map:**
- `authentik-forward-auth@file` — bundles Authentik OIDC + CrowdSec bouncer. For app-facing routes with a
  managed login (most web apps).
- `crowdsec-only@file` — CrowdSec bouncer only. For self-auth'd services that deliberately skip
  Forward-Auth (native SSO / own login).

**Routes that skip Forward-Auth and MUST carry `crowdsec-only@file`:**
- `ha.kogler.si` (HA native auth) — KOPS-004
- `media.kogler.si` (Jellyfin login) — KOPS-018
- `seerr.kogler.si` (Seerr login) — KOPS-047
- `matrix.kogler.si` (Matrix-native OIDC) — KOPS-018
- `chat.kogler.si` (Element Web, homeserver SSO) — KOPS-025
- HA standby via VIP — KOPS-018

Owning doc: [services-traefik.md](services-traefik.md). Tracked: HD-60, HD-72.

## 2. Version pinning (Flaw B)

> **Law:** no mutable image tags in production. Every service image must use an explicit
> semver/manifest pin defined as a variable in `group_vars/*.yml`, tracked by Renovate — never `latest`,
> never a mutable alias tag such as `-rocm`.

- `traefik` uses `traefik_version` (currently `latest` — pin to a semver; HD-61).
- Every `:latest` across the 42 compose templates must be converted to a pinned var (`deployment-compose.md`).
- `ollama/ollama:rocm` is a mutable alias → pin to a specific `0.6.x-rocm` (KOPS-027).

Owning docs: [deployment-compose.md](deployment-compose.md), [deployment-renovate.md](deployment-renovate.md).
Tracked: HD-61.

## 3. Host port-binding policy (Flaw C)

> **Law:** no service binds a container port to `0.0.0.0` on the host. Prefer the Docker overlay network
> (containers reach each other by service name). When a host port cannot be avoided, bind loopback
> (`127.0.0.1:p:p`) or a specific VLAN IP.

- **Signal CLI** `8080:8080` — remove host bind; n8n reaches it via `services-internal` by name (KOPS-002).
- **Prometheus** `9090:9090` — bind loopback (KOPS-017).
- **Technitium** `53:53` — bind a specific VLAN IP (KOPS-015/064).
- **Sunshine** `47989-48010` — restrict to Home VLAN IP (KOPS-007).

Owning doc: [deployment-compose.md](deployment-compose.md). Tracked: HD-62.

## 4. Container minimum privilege (Flaw D)

> **Law:** prefer targeted `devices:` and `cap_add:` over `privileged`, broad `NET_ADMIN`, or
> `network_mode: host`. No container runs as root, or with host networking, without a documented reason.

- **HA primary** — currently `privileged: true` + `network_mode: host`; move to targeted
  `devices:` + `cap_add:` (KOPS-014). `network_mode: host` is only justified for keepalived VRRP multicast;
  keep the minimum that VRRP needs. Owning doc: [smart-home-failover.md](smart-home-failover.md). HD-72.
- **Technitium** — runs as root with `NET_ADMIN` on port 53; add `user:` and drop `NET_ADMIN` if not
  required (KOPS-015/032). HD-62/064.
- **Doco-CD** — host-network + `docker.sock:rw` + Forgejo write token. Keep `cap_drop: ALL`, distroless
  non-root; split the Forgejo token so Doco-CD's write scope is bounded (KOPS-024/055). HD-77.

Tracked: HD-72, HD-77.

## 5. Backup coverage (Flaw E)

> **Law:** every stateful database must be covered by `db-backup` (or Kopia) **before** go-live. A lost DB
> loses metadata that cannot be reconstructed from the original media/bytes.

- **immich** Postgres — albums, faces, labels, smart-search embeddings (KOPS-026).
- **opencloud** Postgres — document versions / metadata.
- Add/uncomment the `immich-postgres` + `opencloud` DB blocks in `db-backup` (HD-63). Note the real
  service hostname is `immich-postgres`, *not* the stale `immich-db` comment.

Owning docs: [backup.md](backup.md), [storage-zfs.md](storage-zfs.md). Tracked: HD-63.

## 6. Bootstrap hygiene (Flaw F)

> **Law:** nothing in the bare-metal/bootstrap path may ship with shared or default credentials, or expose
> management services beyond the Management VLAN.

- **Preseed root password** — use a unique per-host hash, or `root-login false` (KOPS-044). HD-80.
  Owning doc: [deployment-preseed.md](deployment-preseed.md).
- **Router API** — restrict to the Management VLAN interface in the bootstrap `.rsc` itself, or disable if
  no TLS (KOPS-003/042). HD-83. Owning doc: [network-ops.md](network-ops.md).
- **Switch port map** — `group_vars/switch.yml` must exist before first switch deploy so unused ports
  don't all land on VLAN 99 (KOPS-043; folded into HD-03).
- **Fail-loud secrets** — no `default('')`; a missing 1Password secret must fail loudly, not deploy an
  unprotected service (KOPS-010). HD-65. Owning doc: [deployment-secrets.md](deployment-secrets.md).
- **Preseed defaults / post_install** — dedupe the `sshd_config` append (KOPS-012). HD-88.

Owning docs: [deployment-preseed.md](deployment-preseed.md),
[deployment-secrets.md](deployment-secrets.md), [network-ops.md](network-ops.md).
Tracked: HD-65, HD-80, HD-83, HD-88.

## 7. Decision log

> Accepted/closed policy decisions — recorded so they are **not** re-raised as open bugs on future scans.
> (Populated from the AUD-02 dispositions; AUD-13 keeps this current.)

- **Matrix open federation** (KOPS-033) — accepted/expected for a federated Matrix homeserver.
  Date: 2025-08-16.
- **SNMP v2c default community** (KOPS-034) — flagged *pending decision* in `observability.md`;
  not an open defect. Tracked: HD-53.
- **Playbook role order** (KOPS-050, `network` before `storage` on oldsrv) — documented as accepted;
  not a bug.
- **Homepage docker.sock health widget** (KOPS-058) — accepted (read-only mount, behind Forward-Auth).
- **Seerr SQLite single-file** (KOPS-059) — accepted risk (reconfig takes ~15 min; keep in Kopia scope).