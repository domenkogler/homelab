---
title: DNS Services — Technitium & Pi-hole
role: detail
domain: services
status: active
tags: [services, dns, technitium, pihole]
---
# DNS Services — Technitium & Pi-hole

> **Role:** Detail — the DNS *services* slice of the services catalog (Technitium router, Pi-hole ad-blocker). Network/ops policy (VLANs, per-subnet upstream filtering, port-53 binding) is owned by [`network-dns.md`](network-dns.md).
> **Links to:** `network-dns.md`, `network-vlans.md`, `services.md`
> **Linked from:** `services.md`, `network-dns.md`

> ⚠️ **Planning phase — not yet deployed.** DNS services are IaC-authored but **not live**; deploy-gated against `deployment-tasks.md`.

---

## Catalog

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| Technitium | dns | I | 120–250 / 400 | Central DNS router, VLAN-aware (binds 53 on host) |
| Pi-hole | ad | I | 100–200 / 300 | Ad-blocking DNS |

## DNS Redundancy

- **Technitium primary** on oldsrv (Docker, `services-internal`).
- **Technitium secondary** on the **Raspberry Pi (`pi.kogler.si`)** — different failure domain; keeps internal `*.kogler.si` + per-subnet filtering when oldsrv is down (see [`network-dns.md`](network-dns.md) + [`smart-home-failover.md`]).

## Related
- [Network DNS architecture](network-dns.md) — VLAN/subnet policy, port-53 binding, DNS SSOT
- [Services index](services.md) — catalog legend + network/subdomain SSOT