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

Technitium runs as a Docker container on oldsrv (primary) and a **second instance on the Raspberry Pi** (`pi.kogler.si` — secondary; `ha.kogler.si` is the VIP) — two separate physical hosts so a DNS outage does not depend on a single failure domain. Both serve the same per-subnet policy and internal `*.kogler.si` records. See the HA-failover tie-in in [`smart-home-failover.md`](smart-home-failover.md).

```
              ┌────────────────────────────┐
              │ Technitium DNS router      │
              │ PRIMARY  (oldsrv)          │
              │ + SECONDARY (Pi/ha.kogler) │
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
Client → Technitium PRIMARY (oldsrv, 10.10.1.30)     ← DHCP lists this first
        → Technitium SECONDARY (pi, 10.10.1.20)
        → Router /ip dns (10.10.x.1, tertiary) → 1.1.1.1 (final fallback)
```

- DHCP hands clients **both** Technitium addresses first (10.10.1.30, 10.10.1.20),
  then the router's IP as tertiary — so per-subnet filtering is enforced (Technitium
  sees the source subnet, not the router). All three bind **Home**-VLAN addresses.
- If oldsrv is down: the **secondary on the Pi** still resolves local `*.kogler.si`
  and enforces per-subnet filtering; 1.1.1.1 is only a last resort (unfiltered)
- The **secondary is a true failure-domain split** — the Pi is a different physical box from oldsrv
- `ha.kogler.si` resolves to the **VIP** on both secondary and primary (see [`smart-home-failover.md`](smart-home-failover.md)) so DNS is never the thing that breaks HA lookup
- **The VIP's `:443` edge is served by whichever keepalived node owns the VIP:** in normal mode the Pi's minimal **`traefik-ha`** edge serves `ha.kogler.si`; after a forward takeover oldsrv's `traefik` takes over. Both serve an identical `ha` route → VIP:8123, so `ha.kogler.si → VIP` is always served by the active HA node (**no DNS flip on failover**). See [`smart-home-failover.md`](smart-home-failover.md).
- **Web UIs:** primary on `dns.kogler.si` (oldsrv, Forward-Auth). The **secondary** on the Pi at **`dns-pi.kogler.si`** — FQDN shape only borrowed from the cockpit naming; like `ha` it resolves to the **VIP `10.10.1.200`** and is served by the Pi's `traefik-ha` edge → local `10.10.1.20:5380`, so it keeps working **when oldsrv is down** (internal-only, no Forward-Auth). Direct fallback `http://10.10.1.20:5380`.
- **Static records (do not forget):** `ha.kogler.si → 10.10.1.200` and `dns-pi.kogler.si → 10.10.1.200` must be created as **A records on BOTH Technitium instances** (primary + secondary). DHCP auto-creation only covers leases, and the VIP is **not** a lease — without these static records the edges are unreachable by name.
- **Coupling tradeoff (accepted):** the Pi also hosts primary HA. A Pi failure takes the DNS secondary down **with** it — but the DNS **primary** (oldsrv) survives, and oldsrv is exactly the box HA fails over to, so resolution is never the thing that breaks HA in the Pi-down scenario.

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

Technitium binds **Home**-VLAN addresses (`10.10.1.30` oldsrv primary, `10.10.1.20`
Pi secondary). Clients on every other VLAN reach them via explicit **forward** rules,
plus the router's own resolver is open on UDP/TCP 53 (input) as a tertiary.

- Forward, above the inter-VLAN drop: from `in-interface-list=LAN` →
  `dst-address=10.10.1.30` **and** `10.10.1.20`, UDP 53 (+ DoT 853).
- Input: `in-interface-list=LAN` UDP/TCP 53 → router `/ip dns` (tertiary), which itself
  forwards to Technitium + 1.1.1.1.
- Global inter-VLAN drop rule sits **below** these exceptions.
- There is **no** "allow DNS on the Management VLAN" rule — Technitium is **not** on the
  Management VLAN; the old Mgmt-placement wording predates the Home-based move.

---

## Local Name Resolution & mDNS

- **DHCP lease integration:** Technitium queries RouterOS REST API for `/ip/dhcp-server/lease` → auto-creates `*.kogler.si` records. Technitium primary binds the **Home** IP `10.10.1.30` (oldsrv) and secondary `10.10.1.20` (the Pi) — cross-VLAN DNS is permitted by the forward rules above.
- **mDNS reflector:** Technitium bridges `.local` names across all VLANs (RouterOS built-in mDNS is bridge-wide only, cannot cross VLANs)

---

## Pi-hole Configuration

- Upstream: Cloudflare (1.1.1.1) or Google (8.8.8.8)
- Conditional forwarding: local domain → Technitium IP (so Pi-hole logs show hostnames)
- Internal Technitium blocklists **disabled** (minimize RAM; Pi-hole handles blocking)