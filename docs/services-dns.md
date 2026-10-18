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
> verified; the **Pi tertiary** (`dns-pi.kogler.si`) is live; the **oldsrv secondary** is seeded by the same
> `technitium-seed` role.
> **Pi-hole is retired** — the design puts ad blocking in Technitium ([§Blocking](#blocking--retired-pi-hole));
> ⚠ **no block lists are configured on any instance** (live state), so nothing is being blocked.
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
  ⚠ **A scoped Pi converge names the SERVICE, and the service is not called `technitium` here.** The Pi's
  entry is `technitium-secondary` (`group_vars/raspberry_pi.yml`) with `instance: secondary-pi`, which is what
  selects the container `technitium-pi`; `docker_services_scope=technitium` matches no entry on this host and
  deploys nothing while still reporting a clean run. `playbooks/dns-seed.yml` derives the name from the
  `docker_services` list and is the form to prefer; the hand-written equivalent is
  `playbooks/raspberry_pi.yml --limit pi.kogler.si --tags docker_services -e docker_services_scope=technitium-secondary`.
  The name is historical — the live tier is VPS primary + oldsrv secondary + Pi **tertiary**.
- **Resolver upstream (live):** the **Pi** instance is the only one given public forwarders
  (`1.1.1.1` + `9.9.9.9`): the Home VLAN asks it first, and public forwarders cut cold-name fan-out on ARM from
  p50 143 ms to 60 ms. Value + rationale: [network-dns.md](network-dns.md) §Resolver upstream.

> **Seeding has two halves.** The `technitium-seed` role asserts the listed records with
> `zones/records/add` and removes the ones a retirement left behind; an orphan sits in **all three**
> instances' zone copies, not on the primary alone, so one delete is not the fix. A retirement is recorded
> in `zone_kogler_si_retired` — the prune leg's candidate set — see [services-admin.md](services-admin.md) §Open item.

## Blocking — retired Pi-hole

Ad blocking is a **Technitium** question and nothing in this fleet loads a list — the tier ruling is
in [network-dns.md](network-dns.md) §Tier policy rulings, and the decision not to run a Pi-hole-class
blocker is [services-rejected.md](services-rejected.md).

The part that was a defect is now owned: **`enableBlocking = true` with `blockListUrls = null`** was
live on all three instances — blocking switched on with nothing loaded, which reads as "protection is
configured" in an API dump and enforces nothing. The seed derives the flag from
`technitium_dns_policy` instead of trusting the instance, so a list-free tier reads
`enableBlocking = false`, and an instance found carrying a list the SSOT does not declare fails the
converge instead of being switched off. Per-instance values, read back over the API:

| Instance | `enableBlocking` | `blockListUrls` |
|---|---|---|
| VPS primary | from the last seed | none declared |
| oldsrv secondary | from the last seed | none declared |
| Pi tertiary | from the last seed | none declared |

Two facts worth keeping if a list is ever loaded: a forwarder in front of Technitium must
**conditionally forward the local domain to the Technitium primary**, or its logs will show IPs
instead of hostnames; and if an external blocker ever runs, Technitium's own lists should be
**disabled** — two blockers in series costs RAM and makes "why is this blocked?" ambiguous.

⚠ **What is NOT true here, despite how a Technitium feature list reads:** there is no per-client-group
blocking and no per-client-group upstream on this pin — the product exposes neither, and the probe is
recorded in [network-dns.md](network-dns.md) §What the pin can and cannot enforce.

## Related
- [Network DNS architecture](network-dns.md) — VLAN/subnet policy, port-53 binding, DNS SSOT
- [Services index](services.md) — catalog legend + network/subdomain SSOT
