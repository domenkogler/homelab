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

## Design: Technitium as Central DNS Router (Primary + Secondary + Tertiary)

Technitium runs as a Docker container on the **VPS (primary, HD-299/2026-09-03)** and two home instances — **oldsrv (secondary)** and the **Raspberry Pi (tertiary; `ha.kogler.si` is the VIP)** — three separate physical hosts so a DNS outage does not depend on a single failure domain. The VPS is always-on + WAN-reachable, so it is the primary resolver for LAN + tailnet (client address = the VPS public IP, `dns_primary_ip`); oldsrv + Pi cover the home-WAN-out / VPS-down cases from the LAN. All serve the same per-subnet policy and internal `*.kogler.si` records. See the HA-failover tie-in in [`smart-home-failover.md`](smart-home-failover.md).

```
                ┌────────────────────────────────┐
                │ Technitium DNS router         │
                │ PRIMARY   (VPS, dns_primary_ip)│
                │ + SECONDARY (oldsrv)          │
                │ + TERTIARY  (Pi/ha.kogler)    │
                └──────┬──────────┬────────────┘
                       │          │
              ┌────────┴───┐  ┌───┴────────┐
              │ per-subnet │  │  internal  │
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
| IoT (20) | IoT-Group | **Quad9** (9.9.9.9) | Malware + botnet blocking — cloud-IoT devices in `iot-wan-allow` (HD-312 phase 3) still resolve via this row; they only gain WAN egress, not a DNS bypass |
| Guest (30) | Guest-Group | Standard public (1.1.1.1) | No filtering needed |

---

## DNS Flow

```
Client → Technitium PRIMARY (VPS public IP)  ← DHCP lists this first
        → Technitium SECONDARY (oldsrv)
        → Technitium TERTIARY (Pi)
        → Router /ip dns (final fallback, per-VLAN gateway) → 1.1.1.1
```

- DHCP hands clients the **full resolver chain** (VPS primary first, then oldsrv, then
  Pi, then the router IP last — addresses per SSOT `dns_primary_ip`/`dns_secondary_ip`/
  `dns_tertiary_ip`), so per-subnet filtering is enforced (Technitium sees the
  source subnet, not the router). Clients query the Technitium instances DIRECTLY —
  do NOT point DHCP at the router and let /ip dns forward: RouterOS /ip dns is a
  single global resolver/cache and cannot differentiate per-VLAN, so the per-subnet
  policy above would collapse into one upstream. The router IP in the DHCP chain is
  the final fallback only (unfiltered last resort). The VPS primary is reached from
  the LAN through the existing Home/Media/Guest/Mgmt→WAN egress (HD-309) and from
  tailnet via its public IP; the VPS nftables source-allow blocks everything else
  (tailnet CGNAT + home WAN only, HD-299). .rsc/role parity: the DHCP dns-server is
  rendered from the same SSOT in both `roles/router/tasks/main.yml` and
  `rb4011_converge.rsc.j2`; the router /ip dns upstream mirrors the same chain first
  + Cloudflare 1.1.1.1/1.0.0.1 last (its WAN egress is what the VPS dns-allow-home
  nft set permits).
- **Resilience chain (the point of the 3-instance tier):**
  - VPS always-on → normal path (LAN + tailnet). If the WG tunnel drops, LAN clients still
    reach the VPS primary over the public WAN (it does not depend on the tunnel).
  - If the VPS is down **or WAN is out**: timeout/failover → oldsrv (secondary), then Pi
    (tertiary) — both on the LAN, keep resolving local `*.kogler.si` + per-subnet filtering;
    1.1.1.1 is only a last resort (unfiltered).
- The **secondary/tertiary are a true failure-domain split** — oldsrv, Pi, and VPS are all
  different physical boxes.
- `ha.kogler.si` resolves to the **VIP** on every instance (see [`smart-home-failover.md`](smart-home-failover.md)) so DNS is never the thing that breaks HA lookup.
- **The VIP's `:443` edge is served by whichever keepalived node owns the VIP:** in normal mode the Pi's minimal **`traefik-ha`** edge serves `ha.kogler.si`; after a forward takeover oldsrv's `traefik` takes over. Both serve an identical `ha` route → VIP:8123, so `ha.kogler.si → VIP` is always served by the active HA node (**no DNS flip on failover**). See [`smart-home-failover.md`](smart-home-failover.md).
- **Web UIs:** primary web UI on `dns.kogler.si` (VPS, Forward-Auth; **no host 5380** — served via the VPS Traefik overlay).
  **🔴 404 fixed 2026-09-03:** `https://dns.kogler.si/` returned 404 because the `forward-dns`
  Authentik ProxyProvider was missing from `ks-forward-auth.yml` (the route + forward-auth label
  existed since HD-62; the outpost 404'd on the unmatched Host). Added `provider_edge_dns` +
  `app_edge_dns`; deploy via `playbooks/authentik-blueprints.yml`. The Pi tertiary has **`dns-pi.kogler.si`** — FQDN shape only borrowed from the cockpit naming; like `ha` it resolves to the **VIP (`ha-vip`)** and is served by the Pi's `traefik-ha` edge → local `pi:5380` (IP per SSOT), so it stays reachable when oldsrv is down (internal-only, no Forward-Auth). **The 5380 publish is now TERTIARY-ONLY** (fixed 2026-09-03): the Pi Technitium container publishes `5380:5380/tcp` so the traefik-ha `dns-pi` route (network_mode: host → http://{{ technitium_secondary_ip }}:5380) actually answers (was 502 — the port wasn't listening); oldsrv (secondary) stays unexposed and the VPS primary stays overlay-only. Direct fallback `pi:5380` on the LAN. oldsrv's UI is not exposed (primary UI lives on the VPS).
- **Static records (do not forget):** `ha.kogler.si → VIP` and `dns-pi.kogler.si → VIP` (VIP = `ha-vip`, value per SSOT) must be created as **A records on EVERY Technitium instance** (VPS primary + oldsrv secondary + Pi tertiary). DHCP auto-creation only covers leases, and the VIP is **not** a lease — without them the traefik-ha / oldsrv edges are unreachable by name. **SEEDED 2026-09-03:** Pi instance verified live (`dig @<pi Home IP per SSOT>`); VPS primary + oldsrv secondary get them via the new `technitium-seed` Ansible role (runs on every `docker_services` converge, reads `technitium_login`/`technitium_api` from 1Password) once their admin is bootstrapped.
- **Static records — tailnet admin dashboards (HD-135b follow-up / HD-273, 2026-08-28):** the **plain `*.kogler.si`** admin names (`stats`, `logs`, `csui`, `sec`, `traefik`, `auto`) must be **A records on BOTH Technitium instances → the `vps-obs` tailnet IP** (the `tailnet_sidecar_ip` group_var, `group_vars/vps.yml` — the traefik-tailnet edge). **Why:** Tailscale client MagicDNS only ANSWERS its `base_domain` (`ts.kogler.si`); for a FQDN matching a search domain (`kogler.si`), the client queries its **configured nameserver for that domain** — here Technitium — so without these records the plain names NXDOMAIN on tailnet devices (the `.ts.kogler.si` twins work via MagicDNS extra_records; the plain set needs the Technitium split-horizon, exactly like `ha`). The value is a **tailnet IP** so ONLY tailnet clients can reach it (LAN-only clients resolve it but fail to connect — correct, tailnet-only). **SEEDED 2026-09-03:** on the Pi instance (verified live); VPS primary + oldsrv secondary via the seed role once their admin is up.
  **🔴 LIVE SYMPTOM (2026-09-03, owner report): *`https://stats.ts.kogler.si/` works but `https://stats.kogler.si/` doesn't* — root cause = the VPS primary Technitium NEVER SEEDED.** The laptop's DNS chain is router DHCP → VPS primary first (→ oldsrv down → Pi). The VPS primary answers `dns.kogler.si` (CNAME to `vps.kogler.si`) but **NOERROR/0-answer for `stats.kogler.si`** — its `auth.config` has a stale `admin` whose password does NOT match the 1P `technitium_login` item → the `technitium-seed` role's login fails (`Invalid username or password for user: admin`, verified via `/api/user/login` POST to the container's overlay IP `tchnitium_dns_overlay_ip` :5380) → the seed never runs → no `stats`/`ha`/`logs`/… A records on the VPS primary. The router itself resolves correctly (`dig @router stats.kogler.si` → `tailnet_sidecar_ip`), and the Pi tertiary HAS all records (`dig @<pi Home IP per SSOT>`), so the failure is confined to resolvers that hit the VPS-primary FIRST and cache the negative (laptop WSL → Windows host → router → VPS primary). **FIX (owner, exact):** recreate the VPS Technitium admin via the `dns.kogler.si` UI (public CNAME already published; UI behind Authentik Forward-Auth) with the password stored in 1P `technitium_login`, then re-run the seed: `ansible-playbook playbooks/vps.yml -l vps -t docker_services -e docker_services_scope=technitium` (or a full `docker_services` converge) → `technitium-seed.yml` bootstraps the zone + all split-horizon records → verify `dig @<VPS public IP per SSOT> stats.kogler.si` → `tailnet_sidecar_ip`. oldsrv secondary seeds the same way once its admin is up. Cloudflare `stats` correctly returns empty (internal-only).
- **Static records — *arr stack (every instance → oldsrv Traefik edge):** `seerr`, `sonarr`,
  `radarr`, `lidarr`, `prowlarr`, `bazarr`, `sab`, `torrent`, `media`, `profilarr`, `logs` (all
  `*.kogler.si`). Recyclarr has no hostname (scheduled worker, no UI). All are **internal-only** —
  no public (Cloudflare) record, WAN-blocked (see `services.md`).
- **Coupling tradeoff (accepted):** the Pi also hosts primary HA. A Pi failure takes the DNS **tertiary** down **with** it — but the DNS primary (VPS, HD-299) and secondary (oldsrv) survive, and oldsrv is exactly the box HA fails over to, so resolution is never the thing that breaks HA in the Pi-down scenario.

---

## Single Namespace & Split-Horizon

Everything uses one namespace **`kogler.si`** (DHCP option 15, hosts, services).

- **Local (Technitium):** authoritative for `*.kogler.si` internally — resolves hosts/services to internal IPs, and auto-creates records from DHCP leases.
- **Public (Cloudflare):** publishes **only** the internet-facing subset — the human-readable mirror is [`services.md`](services.md) §Domain & Subdomain Plan (`kogler.si` root + `home`, `sso`, `dns`, `foto`, `file`, `office`, `ai`, `git`, `ha`, `vpn`, `matrix`, `chat`). Cloudflare is **DNS-only** (no proxy) — real client IPs reach Traefik. **`dns` (the Technitium web UI) is the ONE admin-surface exception** (added 2026-09-03, now in the IaC SSOT `cloudflare_dns/vars/main.yml` per HD-198): `dns.kogler.si` → `vps.kogler.si` is needed as the public bootstrap path to the VPS DNS admin (and for the owner to recreate the VPS admin + finish seed), even though the UI itself sits behind Authentik Forward-Auth.
- Internal-only services/hosts (stats, ad, auto, logs, cockpit-*, router, switch, nas, oldsrv) have **no public record**; WAN firewall blocks them (defense in depth). **The observability admin dashboards (stats/sec/traefik/logs/csui/auto) are tailnet-only** (HD-135b follow-up, 2026-08-28): the Phase-1 public CNAMEs are removed from the IaC SSOT (`cloudflare_dns/vars/main.yml`) and must be **deleted from the Cloudflare zone** by the owner (deploy-gated — the Ansible role only ensures `state: present`, it does not delete live records). On the tailnet they resolve via **headscale MagicDNS** — `dns.extra_records` maps each dashboard subdomain (and its `*.ts.kogler.si` twin) to the `vps-obs` tailnet IP, and `dns.search_domains: [kogler.si]` extends MagicDNS to the plain `*.kogler.si` names — so the owner's tailnet devices reach `https://stats.kogler.si`, `https://logs.kogler.si`, … directly (see [`network-vpn.md`](network-vpn.md) §Tailnet-exposed services). Technitium (the LAN resolver) carries **no** record for these — plain-LAN clients cannot route to the VPS tailnet IP anyway.
- **TLS:** a single wildcard `*.kogler.si` certificate, issued via ACME **DNS-01** with a Cloudflare API token (1Password `Homelab-ansible`) — covers internal and public hostnames alike.

### A / AAAA policy

- **Public (Cloudflare, DNS-only):** publish **A + AAAA** for the internet-facing set — same list as the mirror in [`services.md`](services.md) §Domain & Subdomain Plan. The home `/56` prefix is **static** (unchanged for 7+ years), so AAAA is safe and enables real dual-stack. Assign oldsrv a **fixed global IPv6** from the /56 for its AAAA.
- **Manually or via Ansible:** the public record list is the SSOT in `IaC/ansible/roles/cloudflare_dns/vars/main.yml`, applied by `playbooks/dns.yml` (control node, `community.dns.cloudflare_dns`, token `cloudflare_api` in 1Password `Homelab-ansible`; **IP-filtered to `193.77.156.222` — run from the home control plane only**). Records for the VPS public edge (`vps` → `159.195.111.66` / `2a0a:...`) are already listed; add each `*.kogler.si` service there as it moves onto the VPS.
- **Matrix delegation (public):** the homeserver name is `kogler.si`, delegated to `matrix.kogler.si` — publish `_matrix._tcp` SRV (`matrix.kogler.si 443`) and serve `_matrix/client` + `_matrix/server` well-known on `kogler.si` and `matrix.kogler.si` (Caddy/Traefik static host or an intermediate). Required for clean `@user:kogler.si` IDs and federation (see [`services-matrix.md`](services-matrix.md)).
- **Internal (Technitium):** serve **A (IPv4)** for all hosts/services — primary, deterministic, matches the static VLAN/IPv4 plan and the IPv4 inter-VLAN firewall.
- **Internal AAAA: deferred (optional).** Static prefix would allow it, but it needs stable per-host global addressing **and** mirroring inter-VLAN isolation in the IPv6 firewall (currently IPv6 is WAN-only). IPv4-first internally until that's verified.

---

## MikroTik Firewall Rules for DNS

Technitium instances bind resolver addresses (VPS public IP primary, oldsrv secondary, Pi tertiary — values per
SSOT `dns_primary_ip`/`dns_secondary_ip`/`dns_tertiary_ip`). Clients on every other VLAN reach them via explicit
**forward** rules, plus the router's own resolver is open on UDP/TCP 53 (input) as a final fallback.

- Forward, above the inter-VLAN drop: from `in-interface-list=LAN` →
  `dst-address=<oldsrv IP>` **and** `<pi IP>` (per SSOT), UDP 53 (+ DoT 853). **The VPS
  primary is NOT a LAN forward target** — LAN clients reach it via the approved
  Home/Media/Guest/Mgmt→WAN egress (HD-309) to the VPS public IP; the VPS nftables
  source-allow (tailnet CGNAT + home WAN only) is the control (HD-299).
- Input: `in-interface-list=LAN` UDP/TCP 53 → router `/ip dns` (final fallback), which itself
  forwards to the same Technitium chain first (VPS→oldsrv→Pi) + 1.1.1.1/1.0.0.1 last
  (upstream mirror of the DHCP list, HD-317).
- Global inter-VLAN drop rule sits **below** these exceptions.
- There is **no** "allow DNS on the Management VLAN" rule — Technitium is **not** on the
  Management VLAN; the old Mgmt-placement wording predates the Home-based move.

---

## Local Name Resolution & mDNS

- **DHCP lease integration:** Technitium queries RouterOS REST API for `/ip/dhcp-server/lease` → auto-creates `*.kogler.si` records. The VPS primary binds the **public** IP; the home secondaries bind the **Home**-VLAN IPs of oldsrv + Pi (per SSOT) — cross-VLAN DNS is permitted by the forward rules above.
- **mDNS reflector:** Technitium bridges `.local` names across all VLANs (RouterOS built-in mDNS is bridge-wide only, cannot cross VLANs)

---

## Pi-hole

Pi-hole is a *service* — its catalog row, configuration (upstream resolvers, conditional forwarding to
the Technitium primary so logs show hostnames, blocklist policy) and deployment live in
[`services-dns.md`](services-dns.md). This file owns only the per-VLAN/subnet DNS **policy** above.
