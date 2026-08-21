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

VLAN subnets per [`network-addresses-generated.md`](network-addresses-generated.md) (SSOT).

| Source VLAN | Technitium Group | Upstream Filter | Purpose |
|--------------|------------------|-----------------|---------|
| Management | — | Local system | Infrastructure isolation |
| Home (10) | Main-Group | **Pi-hole** | Aggressive ad-blocking |
| Kids (40) | Kids-Group | **Cloudflare Families** (1.1.1.3) | Adult content + porn filtering |
| IoT (20) | IoT-Group | **Quad9** (9.9.9.9) | Malware + botnet blocking |
| Guest (30) | Guest-Group | Standard public (1.1.1.1) | No filtering needed |

---

## DNS Flow

```
Client → Technitium PRIMARY (oldsrv)     ← DHCP lists this first
        → Technitium SECONDARY (pi)
        → Router /ip dns (tertiary, per-VLAN gateway) → 1.1.1.1 (final fallback)
```

- DHCP hands clients **both** Technitium servers first (oldsrv, then pi — addresses per SSOT),
  then the router's IP as tertiary — so per-subnet filtering is enforced (Technitium
  sees the source subnet, not the router). All three bind **Home**-VLAN addresses.
- If oldsrv is down: the **secondary on the Pi** still resolves local `*.kogler.si`
  and enforces per-subnet filtering; 1.1.1.1 is only a last resort (unfiltered)
- The **secondary is a true failure-domain split** — the Pi is a different physical box from oldsrv
- `ha.kogler.si` resolves to the **VIP** on both secondary and primary (see [`smart-home-failover.md`](smart-home-failover.md)) so DNS is never the thing that breaks HA lookup
- **The VIP's `:443` edge is served by whichever keepalived node owns the VIP:** in normal mode the Pi's minimal **`traefik-ha`** edge serves `ha.kogler.si`; after a forward takeover oldsrv's `traefik` takes over. Both serve an identical `ha` route → VIP:8123, so `ha.kogler.si → VIP` is always served by the active HA node (**no DNS flip on failover**). See [`smart-home-failover.md`](smart-home-failover.md).
- **Web UIs:** primary on `dns.kogler.si` (oldsrv, Forward-Auth). The **secondary** on the Pi at **`dns-pi.kogler.si`** — FQDN shape only borrowed from the cockpit naming; like `ha` it resolves to the **VIP (`ha-vip`)** and is served by the Pi's `traefik-ha` edge → local `pi:5380` (IP per SSOT), so it keeps working **when oldsrv is down** (internal-only, no Forward-Auth). Direct fallback `pi:5380` on the LAN.
- **Static records (do not forget):** `ha.kogler.si → VIP` and `dns-pi.kogler.si → VIP` (VIP = `ha-vip`, value per SSOT) must be created as **A records on BOTH Technitium instances** (primary + secondary). DHCP auto-creation only covers leases, and the VIP is **not** a lease — without these static records the edges are unreachable by name.
- **Static records — *arr stack (both instances → oldsrv Traefik edge):** `seerr`, `sonarr`,
  `radarr`, `lidarr`, `prowlarr`, `bazarr`, `sab`, `torrent`, `media`, `profilarr`, `logs` (all
  `*.kogler.si`). Recyclarr has no hostname (scheduled worker, no UI). All are **internal-only** —
  no public (Cloudflare) record, WAN-blocked (see `services.md`).
- **Coupling tradeoff (accepted):** the Pi also hosts primary HA. A Pi failure takes the DNS secondary down **with** it — but the DNS **primary** (oldsrv) survives, and oldsrv is exactly the box HA fails over to, so resolution is never the thing that breaks HA in the Pi-down scenario.

---

## Single Namespace & Split-Horizon

Everything uses one namespace **`kogler.si`** (DHCP option 15, hosts, services).

- **Local (Technitium):** authoritative for `*.kogler.si` internally — resolves hosts/services to internal IPs, and auto-creates records from DHCP leases.
- **Public (Cloudflare):** publishes **only** the internet-facing subset — the human-readable mirror is [`services.md`](services.md) §Domain & Subdomain Plan (`kogler.si` root + `home`, `sso`, `foto`, `file`, `office`, `ai`, `git`, `ha`, `vpn`, `matrix`, `chat`). Cloudflare is **DNS-only** (no proxy) — real client IPs reach Traefik.
- Internal-only services/hosts (stats, dns, ad, auto, logs, cockpit-*, router, switch, nas, oldsrv) have **no public record**; WAN firewall blocks them (defense in depth).
- **TLS:** a single wildcard `*.kogler.si` certificate, issued via ACME **DNS-01** with a Cloudflare API token (1Password `Homelab-ansible`) — covers internal and public hostnames alike.

### A / AAAA policy

- **Public (Cloudflare, DNS-only):** publish **A + AAAA** for the internet-facing set — same list as the mirror in [`services.md`](services.md) §Domain & Subdomain Plan. The home `/56` prefix is **static** (unchanged for 7+ years), so AAAA is safe and enables real dual-stack. Assign oldsrv a **fixed global IPv6** from the /56 for its AAAA.
- **Manually or via Ansible:** the public record list is the SSOT in `IaC/ansible/roles/cloudflare_dns/vars/main.yml`, applied by `playbooks/dns.yml` (control node, `community.dns.cloudflare_dns`, token `cloudflare_api` in 1Password `Homelab-ansible`; **IP-filtered to `193.77.156.222` — run from the home control plane only**). Records for the VPS public edge (`vps` → `159.195.111.66` / `2a0a:...`) are already listed; add each `*.kogler.si` service there as it moves onto the VPS.
- **Matrix delegation (public):** the homeserver name is `kogler.si`, delegated to `matrix.kogler.si` — publish `_matrix._tcp` SRV (`matrix.kogler.si 443`) and serve `_matrix/client` + `_matrix/server` well-known on `kogler.si` and `matrix.kogler.si` (Caddy/Traefik static host or an intermediate). Required for clean `@user:kogler.si` IDs and federation (see [`services-matrix.md`](services-matrix.md)).
- **Internal (Technitium):** serve **A (IPv4)** for all hosts/services — primary, deterministic, matches the static VLAN/IPv4 plan and the IPv4 inter-VLAN firewall.
- **Internal AAAA: deferred (optional).** Static prefix would allow it, but it needs stable per-host global addressing **and** mirroring inter-VLAN isolation in the IPv6 firewall (currently IPv6 is WAN-only). IPv4-first internally until that's verified.

---

## MikroTik Firewall Rules for DNS

Technitium binds **Home**-VLAN addresses (oldsrv primary, pi secondary — values per
SSOT). Clients on every other VLAN reach them via explicit **forward** rules,
plus the router's own resolver is open on UDP/TCP 53 (input) as a tertiary.

- Forward, above the inter-VLAN drop: from `in-interface-list=LAN` →
  `dst-address=<oldsrv IP>` **and** `<pi IP>` (per SSOT), UDP 53 (+ DoT 853).
- Input: `in-interface-list=LAN` UDP/TCP 53 → router `/ip dns` (tertiary), which itself
  forwards to Technitium + 1.1.1.1.
- Global inter-VLAN drop rule sits **below** these exceptions.
- There is **no** "allow DNS on the Management VLAN" rule — Technitium is **not** on the
  Management VLAN; the old Mgmt-placement wording predates the Home-based move.

---

## Local Name Resolution & mDNS

- **DHCP lease integration:** Technitium queries RouterOS REST API for `/ip/dhcp-server/lease` → auto-creates `*.kogler.si` records. Technitium primary binds the **Home**-VLAN IP of oldsrv and secondary that of the Pi (per SSOT) — cross-VLAN DNS is permitted by the forward rules above.
- **mDNS reflector:** Technitium bridges `.local` names across all VLANs (RouterOS built-in mDNS is bridge-wide only, cannot cross VLANs)

---

## Pi-hole

Pi-hole is a *service* — its catalog row, configuration (upstream resolvers, conditional forwarding to
the Technitium primary so logs show hostnames, blocklist policy) and deployment live in
[`services-dns.md`](services-dns.md). This file owns only the per-VLAN/subnet DNS **policy** above.
