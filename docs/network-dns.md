# DNS Architecture

> **Role:** Detail — DNS routing, Technitium/Pi-hole, per-subnet policy.
> **Links to:** `network-vlans.md`, `services.md`
> **Linked from:** `network.md`, `index.md`

---

## Design: Technitium as Central DNS Router

Technitium runs on the Phase 1 home server (bare-metal Debian, Management VLAN IP). It intercepts all DNS queries from every VLAN and routes them to the appropriate upstream filter based on source subnet.

```
                     ┌──────────────────────────┐
                     │     Technitium           │
                     │  (Central DNS Router)    │
                     │  Management VLAN         │
                     └──────┬───────┬───────────┘
                            │       │
            ┌───────────────┼───────┼───────────────┐
            │               │       │               │
      ┌─────▼─────┐  ┌──────▼──┐ ┌──▼───────┐  ┌────▼────┐
      │  Pi-hole  │  │ AdGuard │ │Cloudflare│  │ Quad9   │
      │ (Home)    │  │ (Kids)  │ │ Families │  │ (IoT)   │
      │ Ad-block  │  │Adult flt│ │1.1.1.3   │  │9.9.9.9  │
      └───────────┘  └─────────┘ └──────────┘  └─────────┘
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
Client → Router (10.10.x.1) → Technitium (10.10.99.X) → Pi-hole/AdGuard/Quad9
                             ↘ 1.1.1.1 (fallback if Debian PC unreachable)
```

- Router `/ip dns` forwards to Technitium as primary, `1.1.1.1` as secondary
- If the server is down: internet still works (unfiltered via 1.1.1.1), but local `*.kogler.si` and ad-blocking unavailable
- DHCP clients always point at the router's IP for DNS

---

## Single Namespace & Split-Horizon

Everything uses one namespace **`kogler.si`** (DHCP option 15, hosts, services).

- **Local (Technitium):** authoritative for `*.kogler.si` internally — resolves hosts/services to internal IPs, and auto-creates records from DHCP leases.
- **Public (Cloudflare):** publishes **only** the internet-facing subset (`kogler.si`, `foto`, `file`, `git`, `sso`, `ha`, `vpn`). Cloudflare is **DNS-only** (no proxy) — real client IPs reach Traefik.
- Internal-only services/hosts (stats, bck, dns, ad, auto, cockpit-*, router, switch, nas, oldsrv) have **no public record**; WAN firewall blocks them (defense in depth).
- **TLS:** a single wildcard `*.kogler.si` certificate, issued via ACME **DNS-01** with a Cloudflare API token (1Password `Homelab`) — covers internal and public hostnames alike.

---

## MikroTik Firewall Rules for DNS

- Allow DNS (UDP 53) from all user VLANs to Technitium IP on Management VLAN (99)
- Global inter-VLAN drop rule sits **below** these exceptions

---

## Local Name Resolution & mDNS

- **DHCP lease integration:** Technitium queries RouterOS REST API for `/ip/dhcp-server/lease` → auto-creates `*.kogler.si` records
- **mDNS reflector:** Technitium bridges `.local` names across all VLANs (RouterOS built-in mDNS is bridge-wide only, cannot cross VLANs)

---

## Pi-hole Configuration

- Upstream: Cloudflare (1.1.1.1) or Google (8.8.8.8)
- Conditional forwarding: local domain → Technitium IP (so Pi-hole logs show hostnames)
- Internal Technitium blocklists **disabled** (minimize RAM; Pi-hole handles blocking)