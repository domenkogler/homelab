---
title: DNS Architecture
role: detail
domain: network
status: active
tags: [network, dns, technitium, pihole]
---
# DNS Architecture

> **Role:** Detail — DNS routing, Technitium/Pi-hole, per-subnet policy.
> **Links to:** `network-vlans.md`, `services.md`
> **Linked from:** `network.md`, `index.md`

---

## Design: Technitium as Central DNS Router (Primary + Secondary)

Technitium runs as a Docker container on oldsrv (primary) and a **second instance on nas (secondary)** — two separate physical hosts so a DNS outage does not depend on a single failure domain. Both serve the same per-subnet policy and internal `*.kogler.si` records. See the HA-failover tie-in in [`smart-home-failover.md`](smart-home-failover.md).

```
              ┌────────────────────────────┐
              │ Technitium DNS router      │
              │ PRIMARY  (oldsrv)          │
              │ + SECONDARY (nas)          │
              └──────┬──────────┬─────────┘
                     │          │
            ┌────────┴───┐  ┌───┴────────┐
            │  per-subnet│  │  internal  │
            │  upstream  │  │ *.kogler.si│
            └────────────┘  └────────────┘
```

---

## Per-Subnet DNS Policy

| Source Subnet | Technitium Group | Upstream Filter | Purpose |
|--------------|------------------|-----------------|---------|
| Management | — | Local system | Infrastructure isolation |
| Home (10.10.1.0/24) | Main-Group | **Pi-hole** | Aggressive ad-blocking |
| Kids (10.10.40.0/24) | Kids-Group | **Cloudflare Families** (1.1.1.3) | Adult content + porn filtering |
| IoT (10.10.20.0/24) | IoT-Group | **Quad9** (9.9.9.9) | Malware + botnet blocking |
| Guest (10.10.30.0/24) | Guest-Group | Standard public (1.1.1.1) | No filtering needed |

---

## DNS Flow

```
Client → Router (10.10.x.1) → Technitium PRIMARY (oldsrv, 10.10.99.X)
                             ↘ Technitium SECONDARY (nas, 10.10.1.50)
                             ↘ 1.1.1.1 (final fallback)
```

- Router `/ip dns` forwards to **Technitium primary + secondary**, `1.1.1.1` as final fallback
- DHCP clients receive **both** the primary and secondary Technitium addresses (and the router's IP)
- If oldsrv is down: the **secondary on nas** still resolves local `*.kogler.si` and enforces per-subnet filtering; 1.1.1.1 is only a last resort (unfiltered)
- The **secondary is a true failure-domain split** — nas is a different physical box from oldsrv
- `ha.kogler.si` resolves to the **VIP** on both secondary and primary (see [`smart-home-failover.md`](smart-home-failover.md)) so DNS is never the thing that breaks HA lookup

---

## Single Namespace & Split-Horizon

Everything uses one namespace **`kogler.si`** (DHCP option 15, hosts, services).

- **Local (Technitium):** authoritative for `*.kogler.si` internally — resolves hosts/services to internal IPs, and auto-creates records from DHCP leases.
- **Public (Cloudflare):** publishes **only** the internet-facing subset (`kogler.si`, `foto`, `file`, `git`, `sso`, `ha`, `vpn`). Cloudflare is **DNS-only** (no proxy) — real client IPs reach Traefik.
- Internal-only services/hosts (stats, bck, dns, ad, auto, cockpit-*, router, switch, nas, oldsrv) have **no public record**; WAN firewall blocks them (defense in depth).
- **TLS:** a single wildcard `*.kogler.si` certificate, issued via ACME **DNS-01** with a Cloudflare API token (1Password `Homelab`) — covers internal and public hostnames alike.

### A / AAAA policy

- **Public (Cloudflare, DNS-only):** publish **A + AAAA** for the internet-facing set (`kogler.si`, `foto`, `file`, `git`, `sso`, `ha`, `vpn`). The home `/56` prefix is **static** (unchanged for 7+ years), so AAAA is safe and enables real dual-stack. Assign oldsrv a **fixed global IPv6** from the /56 for its AAAA.
- **Internal (Technitium):** serve **A (IPv4)** for all hosts/services — primary, deterministic, matches the static VLAN/IPv4 plan and the IPv4 inter-VLAN firewall.
- **Internal AAAA: deferred (optional).** Static prefix would allow it, but it needs stable per-host global addressing **and** mirroring inter-VLAN isolation in the IPv6 firewall (currently IPv6 is WAN-only). IPv4-first internally until that's verified.

---

## MikroTik Firewall Rules for DNS

- Allow DNS (UDP 53) from all user VLANs to Technitium IP on Management VLAN (99)
- Global inter-VLAN drop rule sits **below** these exceptions

---

## Local Name Resolution & mDNS

- **DHCP lease integration:** Technitium queries RouterOS REST API for `/ip/dhcp-server/lease` → auto-creates `*.kogler.si` records. Technitium runs on oldsrv (Management VLAN 99, native trunk) — same VLAN as the router's management interface, so no inter-VLAN firewall rule is needed.
- **mDNS reflector:** Technitium bridges `.local` names across all VLANs (RouterOS built-in mDNS is bridge-wide only, cannot cross VLANs)

---

## Pi-hole Configuration

- Upstream: Cloudflare (1.1.1.1) or Google (8.8.8.8)
- Conditional forwarding: local domain → Technitium IP (so Pi-hole logs show hostnames)
- Internal Technitium blocklists **disabled** (minimize RAM; Pi-hole handles blocking)