---
title: DNS Services — Technitium (& retired Pi-hole)
role: detail
domain: services
status: active
tags: [services, dns, technitium, pihole]
---
# DNS Services — Technitium

> **Role:** Detail — the DNS *services* slice of the services catalog. Network/ops policy (VLANs,
> per-subnet upstream filtering, port-53 binding, record SSOT) is owned by [`network-dns.md`](network-dns.md);
> this doc covers the DNS **services** and their exposure.
> **Links to:** `network-dns.md`, `network-vlans.md`, `services.md`
> **Linked from:** `services.md`, `network-dns.md`

> **Status: 🟢 live** — the **VPS primary** Technitium is seeded and its zone + split-horizon records are
> verified; the **Pi tertiary** (`dns-pi.kogler.si`) is live; **oldsrv's secondary** still needs seeding via
> the same `technitium-seed` role once its admin endpoint is reachable.
> **Pi-hole is retired** — ad blocking runs in Technitium ([§Blocking](#blocking--retired-pi-hole)).
> Deploy progress: [`deployment-tasks.md`](../deployment-tasks.md).

---

## Catalog

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| Technitium | dns | I | 120–250 / 400 | Central DNS router, VLAN-aware (binds :53 on the host) |

## Redundancy

- **Primary — VPS** (Docker, `dns-servers` overlay; web UI `dns.kogler.si`). `dns.kogler.si` resolves to the
  VPS edge and is behind **Authentik Forward-Auth**: its `forward-dns` ProxyProvider lives in
  `ks-forward-auth.yml` (blueprint, applied via `playbooks/authentik-blueprints.yml`), and the route label is
  on the primary technitium compose (`Host(dns.kogler.si)` + `authentik-forward-auth@file`).
- **Secondary — oldsrv**: a different failure domain; keeps internal `*.kogler.si` resolution + per-subnet
  filtering when the VPS is unreachable.
- **Tertiary — Raspberry Pi** (`pi.kogler.si`): web UI at `dns-pi.kogler.si` through the Pi `traefik-ha` edge
  (the container publishes :5380 on the host) so it stays reachable when oldsrv is down. Port/record detail:
  [network-dns.md](network-dns.md).

> **Seeding is add-only (⚠ known gap).** The `technitium-seed` role calls `zones/records/add` and never
> deletes, so a retired service can leave an orphan record on the primary. Track and prune those explicitly —
> see [services-admin.md](services-admin.md) §Open item.

## Blocking — retired Pi-hole

Ad blocking is **Technitium Advanced Blocking** (per-client groups, multiple block-list formats) running on
the reliable VPS/Pi DNS tier — not an oldsrv container. Rationale + the decision:
[services-rejected.md](services-rejected.md).

Two facts worth keeping if it is ever re-enabled:
- A forwarder in front of Technitium must **conditionally forward the local domain to the Technitium
  primary**, or its logs will show IPs instead of hostnames.
- If an external blocker runs, Technitium's own blocklists should be **disabled** — two blockers in series
  costs RAM and makes "why is this blocked?" ambiguous.

## Related
- [Network DNS architecture](network-dns.md) — VLAN/subnet policy, port-53 binding, DNS SSOT
- [Services index](services.md) — catalog legend + network/subdomain SSOT
