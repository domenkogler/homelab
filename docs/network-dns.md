---
title: DNS Architecture
role: detail
domain: network
status: active
tags: [network, dns, technitium, pihole]
---
# DNS Architecture

> **Role:** Detail — DNS routing, Technitium, per-subnet policy.
> **Links to:** `network-vlans.md`, `services.md`
> **Linked from:** `network.md`, `index.md`

---

## Design: Technitium as Central DNS Router (Primary + Secondary + Tertiary)

Technitium runs as a Docker container on the **VPS (primary, HD-299)** and two home instances —
**oldsrv (secondary)** and the **Raspberry Pi (tertiary; `ha.kogler.si` is the VIP)** — three separate
physical hosts so a DNS outage never depends on a single failure domain. The VPS is always-on +
WAN-reachable, so it is the primary resolver for LAN + tailnet (client address = the VPS public IP,
`dns_primary_ip`); oldsrv + Pi cover the home-WAN-out / VPS-down cases from the LAN. All three serve the
same per-subnet policy and internal `*.kogler.si` records. ✅ **all three instances seeded + live.**
See the HA-failover tie-in in [`smart-home-failover.md`](smart-home-failover.md).

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
| Home (10) | Main-Group | **Technitium Advanced Blocking** (ad-block lists, per-client groups, multiple block-list formats) | Aggressive ad-blocking on the reliable DNS tier (VPS/Pi). The two kids tablets are **per-MAC dst-nat'd to the Kids-Group resolver** (HD-326): router NAT redirects their `:53` to Technitium, which applies the Kids-Group policy. |
| Kids (40) | Kids-Group | **Cloudflare Families** (1.1.1.3) | Adult content + porn filtering — the VLAN-40 hijack (HD-182) covers the (currently unused for Wi-Fi) Kids VLAN; the Home-VLAN kids tablets get the same policy via the per-MAC dst-nat (HD-326) |
| IoT (20) | IoT-Group | **Quad9** (9.9.9.9) | Malware + botnet blocking. Cloud-IoT devices with `wan_allow` still resolve through this row — they gain WAN egress only, never a DNS bypass. IoT plain `:53` is dst-nat'd to the **Pi tertiary** (`dns_tertiary_ip`) so per-device query visibility lands on the Pi's log (`dns-pi.kogler.si`); DoT(853) bypass is dropped (router role). |
| Guest (30) | Guest-Group | Standard public (1.1.1.1) | No filtering needed |

---

## Per-Instance Split-Horizon (HD-350/HD-352)

✅ **live on all three instances** (VPS primary + oldsrv secondary + Pi tertiary).
⏳ After any Pi-side change, verify `dig @<home> media.kogler.si` → oldsrv LAN IP.

The three instances serve the SAME primary zone but with **per-instance A-record targets**, so LAN
clients stay on the home LAN while WAN/tailnet clients keep the VPS edge. Record table (matched by the
`technitium-seed` loop, per `svc.instance`):

| Record | VPS primary | oldsrv secondary + Pi tertiary |
|---|---|---|
| Home-hosted (`media`, `seerr`, `seerrng`, `sonarr`, `radarr`, `lidarr`, `prowlarr`, `bazarr`, `profilarr`, `sab`, `torrent`) | VPS public IP (`dns_primary_ip`) | **oldsrv LAN IP** (`oldsrv_home_ip`) — home edge, no WAN round-trip |
| `ha` / `dns-pi` | VIP (`ha_vip`) | VIP (`ha_vip`) — same on all (DNS never breaks HA lookup) |
| `ha.ts` (**tailnet-only**, HD-405) | — (never seeded in Technitium) | — (never seeded) · resolves ONLY via **headscale `dns.extra_records`** to `tailnet_oldsrv_ip`, rendered by `tailnet_ts_only_subdomains` (group_vars/vps.yml) in the **`*.ts.kogler.si` namespace only** |
| VPS-hosted (`foto`, `file`, `git`, `ai`, `office`, `pdf`, `chat`, `matrix`, `drop`, `bin`, `sso`, `dns`, `vpn`, … + root/home/vps) | VPS public IP | VPS public IP (their backends live on the VPS; the home edge reaches them via wg-s2s :4443 double-hop, HD-350) |
| Tailnet dashboards (`stats`, `logs`, `csui`, `traefik`, `auto`) | VPS tailnet sidecar IP | VPS tailnet sidecar IP (cluster constant) · these + the AI names (`llm`/`db-spark`/`litellm`) also resolve on tailnet devices via **MagicDNS extra_records** (both namespaces, HD-371) — the Technitium A records remain for LAN/split-horizon parity |
| `modem` | — (never seeded on VPS) | LAN-only (HD-302) |
| `spark` / `db-spark` / `llm` (HD-365/370) | — (never seeded on VPS) | **spark LAN IP** (`spark_home_ip`) — headless GPU node, LAN-only (`llm` = spark OpenAI-API, `db-spark` = DGX dashboard; VPS/tailnet reach them via the tailnet edge over WG S2S, not by seeding the primary) |
| `litellm` (HD-370) | VPS public IP (`dns_primary_ip`) — VPS-resident spine admin, split-horizon parity | VPS public IP — same (the LAN/tailnet reach the admin via the edge) |
| `llitellm` (HD-370) | — (never seeded on VPS) | **oldsrv LAN IP** — LAN (dev) LiteLLM on the home edge (LAN-only) |
| `llogs` | — (never seeded on VPS) | **oldsrv LAN IP** (`oldsrv_home_ip`) — LAN log hub (Dozzle), LAN-only (same rule as `modem`/`spark`: a LAN-only viewer must never resolve from VPS/internet) |

> **Why home-hosted names are per-instance:** the home-hosted apps run on **oldsrv** (host-net backends on
> `oldsrv_home_ip`). Pointing them at the VPS public IP on the home instances would make every LAN hit
> depend on WAN (the HD-349 drill finding). The home edge (`traefik-internal`,
> [services-traefik.md](services-traefik.md) §Edge model) serves them from `oldsrv_home_ip`; the VPS
> primary keeps `dns_primary_ip` so WAN/tailnet reach the VPS first.

---

## DNS Flow

```
Client → Technitium (DHCP-pushed chain, see below)
        → Router /ip dns (implicit final fallback, own upstream = the same chain + Cloudflare)
```

- **Resolver chain pushed by DHCP (RouterOS caps `dns-server` at 3 values — a 4th is silently dropped,
  so the router IP is deliberately NOT in the list):**
  - **Home VLAN 10:** **Pi tertiary → VPS primary → oldsrv secondary** (HD-334) — Home resolves via the
    Pi, which gives per-device query visibility in the Pi's log and makes per-MAC filtering work.
  - **All other VLANs (guest/mgmt/iot/media):** **VPS primary → oldsrv secondary → Pi tertiary** — they
    are not per-device filtered.
  - The router's `/ip dns` is the **implicit** last resort via its own upstream (the same chain first +
    Cloudflare `1.1.1.1`/`1.0.0.1` last); its WAN egress is what the VPS `dns-allow-home` nft set permits.
  - `.rsc`/role parity: the DHCP `dns-server` is rendered from the same SSOT in both
    `roles/router/tasks/main.yml` and `rb4011_converge.rsc.j2`.
- **Clients must query the Technitium instances DIRECTLY** — do NOT point DHCP at the router and let
  `/ip dns` forward: RouterOS `/ip dns` is a single global resolver/cache and cannot differentiate
  per-VLAN, so the per-subnet policy above would collapse into one upstream.
- The VPS primary is reached from the LAN through the existing Home/Media/Guest/Mgmt→WAN egress (HD-309)
  and from the tailnet via its public IP; the VPS nftables source-allow blocks everything else
  (tailnet CGNAT + home WAN only, HD-299).
- **Resilience chain (the point of the 3-instance tier):**
  - VPS always-on → normal path (LAN + tailnet). If the WG tunnel drops, LAN clients still reach the VPS
    primary over the public WAN (it does not depend on the tunnel).
  - If the VPS is down **or WAN is out**: timeout/failover → oldsrv (secondary), then Pi (tertiary) — both
    on the LAN, keep resolving local `*.kogler.si` + per-subnet filtering; public internet is only a last
    resort (unfiltered). ✅ **WAN-out failover verified on both home legs** (Pi and oldsrv): with the home
    WAN down the VPS primary times out while the LAN-local instances answer the full `*.kogler.si` set,
    and recovery on PPPoE re-enable is immediate (no negative caching).
- **The secondary/tertiary are a true failure-domain split** — oldsrv, Pi and VPS are different physical boxes.
- `ha.kogler.si` resolves to the **VIP** on every instance (see [`smart-home-failover.md`](smart-home-failover.md))
  so DNS is never the thing that breaks HA lookup.
- **Away-from-home HA is a separate name, on purpose (HD-405, 2026-09-20).** `ha.ts.kogler.si` answers only
  on the tailnet and points at oldsrv's own node; the plain `ha.kogler.si` keeps resolving to the VIP from
  every instance. The reason is the HD-382/389 resolver-ambiguity class plus a failure-domain argument:
  MagicDNS answers extra_records **client-side on Android/iOS**, so a single name published to both planes
  would also send a tailnet-enabled phone **at home** to oldsrv instead of the VIP — putting a new
  `oldsrv`-must-be-up dependency inside the exact failure domain `smart-home-failover.md` exists to remove.
  The `.ts` twin costs the owner one extra entry in the Companion app and keeps both planes honest.
  ⚠ A client can hold a stale MagicDNS answer: `dig @100.100.100.100 ha.ts.kogler.si` proves what headscale
  serves; a client that disagrees needs a Tailscale reconnect (toggle), not a DNS change.
- **The tailnet resolver chain is location-independent (HD-415, shipped 2026-09-22).** `dns.nameservers` is **MagicDNS loop → oldsrv's tailnet node address → VPS public**. One resolver reachable from wherever the device is, instead of a list sorted by where the device usually is: the node address answers direct-over-LAN at home with the WAN pulled *and* away while the home link is up, and the VPS instance stays behind it so a dead node never costs away-side resolution. What it replaced was MagicDNS loop → VPS public → `oldsrv` LAN → `Pi` LAN: the last two are private home addresses, so a phone on cellular got `DNS unavailable` and burned resolver timeouts before falling back — but they were also what kept `*.kogler.si` answering on a tailnet device **at home with the WAN down**, since the VPS primary is precisely the path a WAN outage removes. That tradeoff, and why trimming was the wrong answer, is the decision record: §The resolution requirement below + [network-rejected.md](network-rejected.md) 2026-09-21. Names inside the tailnet's own domain answer from the netmap client-side, which is why tailnet-only records (`ha.ts`) resolve on any network regardless of which resolver is up.
- **The VIP's `:443` edge is served by whichever keepalived node owns the VIP:** in normal mode the Pi's
  minimal **`traefik-ha`** edge serves `ha.kogler.si`; after a forward takeover the home-LAN
  **`traefik-internal`** edge on oldsrv takes over (HD-349/HD-346). Both serve an identical
  `ha` route → VIP:8123, so `ha.kogler.si → VIP` is always served by the active HA node
  (**no DNS flip on failover**). See [`smart-home-failover.md`](smart-home-failover.md) +
  [services-traefik.md](services-traefik.md) §Edge model.

### Recursion + exposure controls

- **Technitium's default recursion (`AllowOnlyForPrivateNetworks`) is wrong for this network:** it refuses
  recursion for any PUBLIC source, including home-WAN/hairpin (src = the home WAN IP) and tailnet CGNAT
  (`100.64/10` is not RFC1918) → the laptop/WSL and Windows Tailscale get `REFUSED` while VPS-local tests pass.
- `technitium-seed.yml` therefore sets the recursion policy **via the API booleans**
  `allowRecursion=true` + `allowRecursionOnlyForPrivateNetworks=false` (= "allow all networks") plus
  `recursionNetworkACL` = home LAN subnets (SSOT `network_vlans`) + tailnet CGNAT + loopback. Fully
  idempotent on every converge; no manual/UI step.
- **The network-level gate is the authoritative control, NOT the app ACL.** `recursionNetworkACL` alone did
  not enforce from an external source. The VPS **nftables FORWARD chain** source-restricts the published
  `:53` (→ `tchnitium_dns_overlay_ip`) to the allow set (tailnet CGNAT + home WAN `@dns-allow-home`) and
  drops everything else — required because Docker's published-port `53:53` DNAT happens in PREROUTING and
  is then **FORWARDED** to the container bridge, so those packets never traverse the INPUT chain (a FORWARD
  drop is authoritative over Docker's iptables accept). Template: `vps-hardening/templates/nftables.conf.j2`;
  apply via `playbooks/vps.yml --tags hardening`. The ACL stays as defense-in-depth (keep the allow-list).
  · [network-rejected.md](network-rejected.md) rows INPUT-source-allow-only / recursionNetworkACL-only.

### Web UIs

- **Primary UI:** `dns.kogler.si` (VPS, Forward-Auth; **no host 5380 publish** — served through the VPS
  Traefik overlay). The `forward-dns` Authentik ProxyProvider (`provider_edge_dns` + `app_edge_dns`) must
  exist in `ks-forward-auth.yml` or the outpost 404s on the unmatched Host even though the route and the
  forward-auth label are present; deploy via `playbooks/authentik-blueprints.yml`.
- **Forward-Auth only GATES the edge — Technitium has its OWN local `admin` login (1P `technitium_login`)
  behind it; SSO never logs you into Technitium.**
- **Pi tertiary UI:** `dns-pi.kogler.si` — FQDN shape borrowed from the cockpit naming; like `ha` it resolves
  to the **VIP (`ha-vip`)** and is served by the Pi's `traefik-ha` edge → local `pi:5380` (IP per SSOT), so
  it stays reachable when oldsrv is down (internal-only, no Forward-Auth). The **5380 publish is
  TERTIARY-ONLY**: `technitium-pi` publishes `5380:5380/tcp` (the traefik-ha `dns-pi` route runs with
  `network_mode: host` → `http://{{ technitium_secondary_ip }}:5380`, which 502s unless the port listens);
  oldsrv (secondary) stays unexposed and the VPS primary stays overlay-only. Direct fallback `pi:5380` on the LAN.
- **Admin bootstrap (all instances):** the seed role reads `technitium_login`/`technitium_api` from 1Password
  and runs on every `docker_services` converge. On a fresh instance Technitium boots with `admin`/`admin`;
  the documented `POST /api/user/changePassword` (`pass` + `newPass` + `Authorization: Bearer`) recreates the
  admin to the 1P value, after which the seed is idempotent. A stale local admin is the classic cause of a
  silently unseeded instance (login fails → seed never runs → `NOERROR`/0-answer for internal names).

### Static records

- `ha.kogler.si → VIP` and `dns-pi.kogler.si → VIP` (VIP = `ha-vip`, value per SSOT), **plus**
  `sso.kogler.si → {{ dns_primary_ip }}` (the VPS public IP — Authentik edge; same target as its public
  CNAME, so internal + public agree) must be **A records on EVERY Technitium instance**. DHCP
  auto-creation only covers leases, and the VIP is **not** a lease — without them the traefik-ha /
  oldsrv edges are unreachable by name.
- **`modem.kogler.si` is NOT a universal record** — the Comtrend UI is LAN/router-only and must never
  resolve from the VPS/internet; the seed loop skips the `modem` row on the VPS primary via a `when`-gate
  (HD-302).
- **Tailnet admin dashboards (HD-135b / HD-273):** the plain `*.kogler.si` admin names (`stats`, `logs`,
  `csui`, `traefik`, `auto`, `db-spark`, `llm`, `litellm`) are **A records on every instance → the
  `tailnet_sidecar_ip`** (the `vps-obs` tailnet IP, `group_vars/vps.yml` = the traefik-tailnet edge). The
  value is a **tailnet IP**, so ONLY tailnet clients can reach it — LAN-only clients resolve it but fail to
  connect, which is correct. Headscale `dns.extra_records` mirrors them into both namespaces and
  `dns.nameservers` puts the **MagicDNS loop first** (HD-371), so a tailnet device resolves `*.kogler.si`
  + `*.ts.kogler.si` on any network; the Technitium A records remain for non-tailnet clients + parity.
- **Per-device DNS visibility + control-plane records (HD-334):** the seed loop also carries
  `vpn.kogler.si` / `home.kogler.si` / `dns.kogler.si` → the right split-horizon targets (VPS public IP for
  the control plane / home login) on **every** instance. ·
  [roles/router/tasks/main.yml](IaC/ansible/roles/router/tasks/main.yml) (dhcp dns-server chain) ·
  [technitium-seed.yml](IaC/ansible/roles/docker_services/tasks/technitium-seed.yml)
- ***arr stack (every instance → oldsrv Traefik edge):** `seerr`, `sonarr`, `radarr`, `lidarr`, `prowlarr`,
  `bazarr`, `sab`, `torrent`, `media`, `profilarr`, `logs` (all `*.kogler.si`). Recyclarr has no hostname
  (scheduled worker, no UI). All are **internal-only** — no public (Cloudflare) record, WAN-blocked
  (see `services.md`).

---

## Single Namespace & Split-Horizon

Everything uses one namespace **`kogler.si`** (DHCP option 15, hosts, services).

- **Local (Technitium):** authoritative for `*.kogler.si` internally — resolves hosts/services to internal IPs, and auto-creates records from DHCP leases.
- **Public (Cloudflare):** publishes **only** the internet-facing subset — the human-readable mirror is [`services.md`](services.md) §Domain & Subdomain Plan (`kogler.si` root + `home`, `sso`, `dns`, `foto`, `file`, `office`, `ai`, `git`, `ha`, `vpn`, `matrix`, `chat`). Cloudflare is **DNS-only** (no proxy) — real client IPs reach Traefik.
  **HD-198 (public-record SSOT method):** publish records **incrementally** — one `*.kogler.si` record added to `cloudflare_dns/vars/main.yml` as each service lands on the VPS edge (gate: applies go LIVE on Cloudflare), and keep `docs/services.md` §Domain & Subdomain Plan as the human-readable mirror re-rendered as the list grows. The live Cloudflare zone + `cloudflare_dns/vars/main.yml` are dual SSOTs — never hand-edit the live zone without the file (and vice-versa).
  **`dns` is the ONE admin-surface exception** (HD-198): `dns.kogler.si` → `vps.kogler.si` is the public bootstrap path to the VPS DNS admin — needed to reach the UI and to recreate the VPS admin — even though the UI itself sits behind Authentik Forward-Auth.
- **Internal-only services/hosts** (`stats`, `ad`, `auto`, `logs`, `cockpit-*`, `router`, `switch`, `nas`, `oldsrv`) have **no public record**; the WAN firewall blocks them (defense in depth). The **observability admin dashboards** (`stats`/`traefik`/`logs`/`csui`/`auto`) are **tailnet-only**: their Phase-1 public CNAMEs are removed from the IaC SSOT (`cloudflare_dns/vars/main.yml`) and ⏳ must be **deleted from the live Cloudflare zone** by the owner (deploy-gated — the Ansible role only ensures `state: present`, it never deletes live records). On the tailnet they resolve via **headscale MagicDNS** (see [`network-vpn.md`](network-vpn.md) §Tailnet-exposed services); Technitium carries no record for them for non-tailnet clients, which cannot route to the VPS tailnet IP anyway.
- **TLS:** a single wildcard `*.kogler.si` certificate, issued via ACME **DNS-01** with a Cloudflare API token (1Password `Homelab-ansible`) — covers internal and public hostnames alike.

### A / AAAA policy

- **Public (Cloudflare, DNS-only):** publish **A + AAAA** for the internet-facing set — same list as the mirror in [`services.md`](services.md) §Domain & Subdomain Plan. ⚠ **The "static /56" premise is now measured, and it is weaker than written:** the home prefix arrives as a **DHCPv6-PD lease** (measured 2026-09-22: `2a00:ee2:2700:8f00::/56`, ~15 min lease, renewing) that has not changed in years — same value, but it is *leased*, so any AAAA pointing into it must survive a re-delegation (which is why the router takes its own address from the pool instead of hardcoding the prefix: [network-vlans.md](network-vlans.md) §IPv6). Assign oldsrv a **fixed global IPv6** from the /56 for its AAAA — which today it does **not** have: its Home NIC uses stable-privacy + temporary addresses, so nothing there is assignable (that host-side change is `roles/network`, and it is the missing prerequisite in HD-414's one-host firewall exception).
- **Manually or via Ansible:** the public record list is the SSOT in `IaC/ansible/roles/cloudflare_dns/vars/main.yml`, applied by `playbooks/dns.yml` (control node, `community.dns.cloudflare_dns`, token `cloudflare_api` in 1Password `Homelab-ansible`; **IP-filtered to the home WAN address — run from the home control plane only**). Records for the VPS public edge (`vps` → the VPS public A/AAAA) are already listed; add each `*.kogler.si` service there as it moves onto the VPS.
- **Matrix delegation (public):** the homeserver name is `kogler.si`, delegated to `matrix.kogler.si` — publish `_matrix._tcp` SRV (`matrix.kogler.si 443`) and serve `_matrix/client` + `_matrix/server` well-known on `kogler.si` and `matrix.kogler.si` (Caddy/Traefik static host or an intermediate). Required for clean `@user:kogler.si` IDs and federation (see [`services-matrix.md`](services-matrix.md)).
- **Internal (Technitium):** serve **A (IPv4)** for all hosts/services — primary, deterministic, matches the static VLAN/IPv4 plan and the IPv4 inter-VLAN firewall.
- **Internal AAAA: REJECTED for now (HD-36).** It needs stable per-host global addressing **and** mirroring inter-VLAN isolation in the IPv6 firewall. ⏳ **Status check 2026-09-22 (IPv6 is live on the Home VLAN — the rejection still stands, on the first reason):** isolation is now mirrored for real (v6 filter + no prefix on 20/30/40/50/99, [network-vlans.md](network-vlans.md) §IPv6), but stable per-host addressing is **more** clearly missing than before — measured, oldsrv's Home NIC runs `addr_gen_mode=1` (RFC 7217) with `use_tempaddr=2`, so the only addresses a home host gets are a hashed stable-privacy GUA plus rotating temporaries. Nothing name-able, no AAAA. Revisit only with a concrete requirement **and** pinned host addresses (`IPv6Token=` / static assignment in `roles/network`). Decision log: [network-rejected.md](network-rejected.md) HD-36.

---

## The resolution requirement (HD-415, decided 2026-09-21)

`*.kogler.si` **must** resolve in three situations, and this is the acceptance test for any change to a resolver, a
nameserver list or the tailnet `nameservers` chain:

1. **On the LAN** — any VLAN client, via the per-subnet Technitium policy above.
2. **Away from home** — a tailnet device reaching the split-horizon zone.
3. **At home with the WAN down** — a tailnet device at home still resolving the zone.

Case **(d)** — away while the **home** WAN is down — has no answer by physics, and the owner has accepted that
explicitly, preferring a clean "the zone is down" over a half-resolving zone that returns addresses for services
that cannot answer.

**The physics that decides the design** (and why "just trim the unreachable resolvers" is wrong): with the home WAN
down, nothing off-site is reachable from inside — *the VPS included* — so case 3 can only ever be served by
something on the LAN. And with the home WAN down, an away device has no path to a home resolver either. So a
resolver list sorted by "where the device usually is" cannot win: the answer is one resolver that is reachable from
**wherever the device is**.

**Decided design (HD-415, folded into the HD-414 lane):**

- Name **oldsrv's own tailnet node address** as a tailnet nameserver — Technitium on oldsrv binds it. At home it
  stays reachable **direct over the LAN even with the WAN pulled**; away it is reachable whenever the home link is
  up. One entry, both places.
- Keep the **VPS public** instance as the **second** entry, so a dead node never costs away-side resolution — the
  public half of the zone (`auth.`, the VPS edge) lives in the same split-horizon set.
- Drop the two **LAN-address** entries (oldsrv LAN, Pi LAN): they were unreachable off-site and are the whole
  `DNS unavailable` wart, and their survival job is taken over by the node address.
- LAN clients are untouched — they get the LAN resolvers from DHCP, exactly as today.

**⚠ Verify, do not assume, before converging** (this repo has been bitten by guessed control-plane syntax): that
headscale in the pinned version accepts a **node address** as a nameserver; that Technitium binds the tailnet
interface; and above all that a phone at home really does reach the node **direct-over-LAN with the WAN pulled** —
that one property is the entire design, so the acceptance test is the three-case drill (LAN / cellular / home with
the WAN pulled), not a `dig` from the laptop. Decision log: [network-rejected.md](network-rejected.md) 2026-09-21.

⏳ **2026-09-22: investigated inside the HD-414 lane and deliberately NOT shipped.** Three measurements, each of
which changes the design as written above — recorded here so the next implementer does not re-derive them:

1. **"Technitium binds it" is already true and needs no change.** Live oldsrv Technitium listens on `0.0.0.0:53`
   + `[::]:53`, which already covers the node address (SSOT `tailnet_oldsrv_ip`). `InterfaceListeners` would buy nothing here —
   it is not the blocker, so do not open it under this row's name.
2. **The blocker is the headscale ACL, not the bind.** `tag:dev`'s accept rule names **`tcp 443` only**, so a
   tailnet node's udp/53 is dropped by the net pol whatever listens. Shipping the nameserver entry alone produces
   a *worse* failure than today: the broken entry enters the tailnet search path and the "resolver error: server
   misbehaving → fall through to the next server" behaviour gets absorbed by the tailscale domain. So this row is
   a **policy widening** (`udp 53` to that one node IP, and the same question for every node that will ever be
   named) plus a control-plane change — not a template tweak. ⛔ Owner gate either way: landing it is a headscale
   stop/start, and every tailnet device reconnects.
3. **The boundary of what actually needs a resolver is narrower than the row assumes.** MagicDNS
   (`100.100.100.100`, first in the chain per HD-371) answers the **tailnet dashboard set** — `stats`/`logs`/
   `csui`/`sec`/`traefik`/`auto` in both namespaces — **client-side on any network**, because those are
   `extra_records` in `config.yaml.j2`. The **home-hosted app names** (`media`, `seerr`, the *arr set, downloads)
   are **not** `extra_records`, so they still need a reachable resolver: away that is the VPS Technitium
   (`dns_primary_ip`), and at home with the WAN pulled it is the **oldsrv entry** — which is precisely the entry
   the redesign wants to re-address. So case (c) does not get easier from MagicDNS, and the node-address swap must
   be proven in exactly that scenario. Also measured: nothing on the router routes the tailnet range into
   `wg-s2s`, so a tailnet-served RA reaching home resolution with the home WAN down would need router work too —
   that is the leg the three-case drill has never exercised.

✅ **Answered 2026-09-22 — the owner authorized the ACL widening: include `udp 53`.** DNS only: the rest of the
2026-09-20 invariant (no LAN bridge, no advertised routes, no exit node, no Tailscale SSH) stands. The headscale
stop/start is authorized too, **conditional on a safety auto-re-enable if the driving session drops** — the exact
`udp:` scoping and that condition are written in the HD-415 row, and the auto-re-enable must be proven before the
first stop.

✅ **SHIPPED 2026-09-22 — the chain is live; the drill is what remains.** The converged headscale config now
serves `nameservers: [100.100.100.100, tailnet_oldsrv_ip, dns_primary_ip]` and the net policy carries the
`udp:`-scoped `udp 53` rule to `{{ tailnet_oldsrv_ip }}/32`; both halves render from the same
`tailnet_oldsrv_ip` condition, so a nameserver entry can never ship without its grant (and an unset node
address drops the entry rather than rendering `""`, because a DNS list must never be able to stop the
control plane it describes). What was measured on the way, ordered by what it costs to re-derive:

* **The node-address resolver answers over the tailnet.** `dig @<tailnet_oldsrv_ip> media.kogler.si` from a
  tailnet node returned the home answer where the same query had timed out minutes earlier. On `oldsrv` the
  query arrives on `tailscale0`, is DNATed to the Technitium container and the reply leaves on `tailscale0`
  again: `ts-forward`'s mark-accept and oif-accept counters moved together while its
  tailscale's anti-loop drop (`ip saddr <the tailnet range> oifname tailscale0 drop`) counter **stayed at 0** — at the FORWARD hook the container
  reply is still sourced from the *container* address (the DNAT undo happens later, in POSTROUTING), so
  tailscale's anti-loop drop never sees a tailnet source. That was the open question about hosting a
  published container on a node's own tailnet address, and it is why no `roles/network` exception was needed.
* **The grant really is DNS-only.** udp/53 answers; **tcp/53 times out** (a truncated answer would therefore
  fail — the answers here are small A records, and widening it is a separate owner call); tcp/8443 stays
  blocked; the `tag:dev:443` rule is untouched.
* **The VPS fallback is a *view*, not a copy of the zone.** From an away source the VPS primary answers the
  control-plane/edge set (`sso`, `vpn`, `ha`, the apex) and **NXDOMAIN for the home-hosted media family**
  (`media`, `seerr`, the *arr set), while the same instance answers those names for an internal source. The
  2026-09-22 investigation's line "away that is the VPS Technitium" therefore holds only for the public/edge
  half: **for the media family the node entry is the only resolver that has ever answered away from home.**
  That is the strongest argument for this design and exactly what case (b) of the drill must read.
* **`headscale configtest` does not validate `dns.nameservers` values** — a garbage address passes it
  silently (canary-proven). `headscale policy check` DOES parse `proto` (a garbage protocol fails naming
  `/acls/<n>/proto`), so it is the real gate for the policy half; the DNS list is gated by the post-converge
  dig, not by configtest.
* **Proving the safety net cost one outage of its own:** an arm step that ran in a different command from the
  stop did not actually arm, and the stop left the control plane down for 2m20s until a manual `compose up`.
  `scripts/guarded-converge.sh` now asserts arm-live before it is allowed to stop anything, and the
  authorization's "prove it first" was then carried out properly (stop → the watchdog brought it back by
  itself in 19s → disarm honoured mid-window).

⛔ **Still open — the three-case drill** (procedure: [deployment-manual.md](../deployment-manual.md) §1.4e).
Case (c) is **not** "the phone on cellular": with the home WAN down the node has no public endpoint and DERP
is unreachable too, so the only thing that can work is the phone on **home Wi-Fi** reaching
`<tailnet_oldsrv_ip>` **direct over the LAN** while the tailnet runs on its cached netmap (the app warning
about the unreachable control plane is expected and is not the failure). Read the answer, not the page:
`ERR_NAME_NOT_RESOLVED` is an HD-415 failure, while connected-but-timed-out is the pre-existing property that
the internal zone returns **LAN** addresses no away device can route to. A laptop at home may instrument case
(c) but does not prove it.

> ⚠ **Measured 2026-09-22, the day the chain shipped: a delivered tailnet chain is *advisory* unless the
> domain is split to it.** `dns.override_local_dns: false` is deliberate (the tailnet must not become a DNS
> exit, and the nodes refuse a wildcard listener on `:53`), and its meaning is exactly Tailscale's wording —
> *"by default, your tailnet's devices use their local DNS settings for all queries."* So the chain is
> installed but consulted only for MagicDNS-local names and for domains named in `dns.nameservers.split`.
> Measured, same afternoon, tailnet connected: the Windows laptop resolved the internal zone from **the Pi's
> LAN resolver address, not from the chain**; and a phone on cellular got an authoritative NXDOMAIN for a
> name that has never existed outside the internal zone — oldsrv's `tailscale0` forward counter sat at
> **9 packets before and 9 after** the lookup (while the container's `udp/53` DNAT counter moved on ordinary
> LAN traffic alone), i.e. **the node was never asked**. The chain itself is sound and reachable: `dig`
> against the node's tailnet address answers the zone from off-site. What is missing is the zone being
> **addressed** to it, which is a `split` decision, not an ordering one → **HD-432**.
> Two more measurements from the same pass, both load-bearing for that decision. (1) The **VPS** instance
> serves the media family only to sources it treats as internal — `NOERROR` with the VPS edge as the answer
> from the home WAN, `NXDOMAIN` from an away source, same instance, same name — so a co-equal VPS entry in
> the chain is not merely unhelpful away from home, it actively answers `NXDOMAIN` for names the node entry
> serves; a two-instance chain of *different views* is a race, which is why the old chain's symptom was
> never a clean failure. (2) The **Pi** answers the internal zone from its own copy (`ha` → the VIP,
> `media` → oldsrv's LAN address, queried directly), which is why a dead oldsrv does not take home
> resolution down with it — the home DNS chain is not as single-homed as the VPN doc's one-liner implies.

## The answer-plane model (decided 2026-09-22 — HD-415 closed, HD-432/433 decided, HD-435/436 opened)

One namespace, three planes, and **the answer must be routable by the client that receives it.**
That single rule is what the previous section's measurements forced out of the design: a tailnet
chain that resolves a name to an address the client cannot route to is not resolution, it is a
black hole with extra steps.

| plane | who answers | what the client gets | what it survives |
|---|---|---|---|
| **public** | Cloudflare | published names → the VPS edge | anything at home dying |
| **tailnet** | **the client's own netmap** (headscale `extra_records`, answered by MagicDNS locally) | pinned names → a **tailnet address** (VPS edge, oldsrv's node, later the Pi's node) | every home box dying, headscale dying, the WAN dying — resolution is cached on the device; only reachability varies |
| **LAN** | the Pi's Technitium (secondary of the VPS primary) | internal answers: the VIP for `ha`, oldsrv's edge for the media family, the VPS for public names | oldsrv dying; **not** the Pi dying → fixed by the dual-resolver decision below |

**Decided, each with the reason that decided it:**

1. **No split-DNS** (`HD-432`, owner 2026-09-22). Splitting the zone to a tailnet resolver would
   answer `media` with a LAN address to a phone on cellular — correct, unreachable — would have **no
   fallback** (a split domain is never asked of the OS resolver), and would pin whole-zone resolution
   to one box. What is needed is *reachable answers*, which is what extra_records are.
2. **`dns.override_local_dns` stays `false`.** The tailnet does not become a DNS exit. The consequence
   is accepted knowingly: the delivered nameserver chain is advisory (measured above), and nothing in
   this design depends on a client being forced to a resolver.
3. **Admin surfaces that are tailnet-only stay tailnet-only, and the LAN zone stops lying** (owner
   choice (a), 2026-09-22). The zone currently answers `stats`, `logs` and `csui` to **LAN** clients
   with a tailnet address — unresolvable-by-design for a device without the tailnet, presented as a
   successful answer. The rule going forward, as a generator invariant: a name marked tailnet-only is
   **never seeded into the LAN-facing view**; a LAN client gets a clean `NXDOMAIN` ("not here") rather
   than a black hole. Publishing Dozzle / the CrowdSec UI on the public edge was the alternative and
   was declined — that option puts container logs and the security console on the open internet.
4. **LAN clients get two resolvers.** The router hands out **both** the Pi and oldsrv. Today the Pi is
   the only DNS the router advertises, so a Pi outage takes home resolution down completely — including
   `ha.kogler.si` and SSO's internal answer — while a Technitium primary sits idle on oldsrv. No VIP, no
   runbook step, nothing to move: this is the same shape as decision 6.
5. **`extra_records` move to the watched file** (`dns.extra_records_path`), so no record edit ever
   restarts the control plane again. Two hazards carried with it: `dns.extra_records` and
   `dns.extra_records_path` are **mutually exclusive** in the pinned version (both set → the process
   exits at startup), so the swap is atomic or it takes the control plane down; and a "container is
   Running" post-check is **not** liveness, because a fatal config leaves a crash-looping container
   reporting `running`. The guarded-converge assert gets a real probe before that swap is allowed.
6. **`HD-435`: the Pi joins the tailnet and HA's names get two A records** (Pi + oldsrv). Both boxes
   proxy to the VIP, so the answer follows HA in either direction. Flagged as **designed, not yet
   measured**: multi-A fall-over on a real client must be proven with a plug-pull before it is relied on.
7. **HA's one URL is the plain `ha.kogler.si`** — see [network-vpn.md](network-vpn.md) §Tailnet boundary.
   The `.ts` twin stays as a free alias.

### `zone_kogler_si` — the zone as one derived list (HD-436)

The zone's membership is currently maintained in **three** places (the Technitium seed's inline record
list, headscale's `tailnet_subdomains` / `tailnet_ts_only_subdomains` lists, and the public Cloudflare
set) and a **fourth** exists as unversioned state on a workstation. The refactor deletes all three
lists by deriving them.

There is already a machine-readable source: the `docker_services` entries in `group_vars` carry
`name`, `subdomain`, `public:` and `enabled:`, and `docs/services-inventory-generated.md` renders them.
So `zone_kogler_si` is **derived from those entries**, not hand-typed, with three added fields:

```yaml
internal: true|false            # seed into the LAN-facing zone
tailnet: none|edge|node|dual    # answer published into every client's netmap (decision 3 applies)
ts_router: true|false           # attach this service's router to the tailnet listener
```

rendered into: the Technitium seed, the watched records JSON, the public Cloudflare set, and the tailnet
listener's router list — with a validator that fails the build on the mismatch classes (see the table
below), and an optional **generated** per-workstation alias file for unqualified names, so no hosts entry
is ever typed again by hand.

**Measured 2026-09-22, the drift those validators exist to catch** — every row is a bug found by
comparing the four sources, none of which noticed:

| name | reality | class |
|---|---|---|
| `music` (navidrome, `enabled: true`) | resolves **nowhere** — not seeded, not public | service up, name absent |
| `sec` (metabase, `enabled: false`) | still resolves publicly **and** internally to the tailnet edge | name outlives the service |
| media family | the seed answers **oldsrv**; `network-addresses-generated.md` says the **NAS** | generated view vs source |
| `stats` | labelled **Beszel** in the address doc, served by **Grafana** per `vps.yml` | label vs owner |
| `stats` / `logs` / `csui` | LAN clients are handed a **tailnet address** | decision 3 above |
| a workstation hosts file | pins `.ts` + short names to tailnet node addresses and cites `scripts/tailnet-hosts.txt` + `scripts/tailscale-dns-fix.ps1` — **neither has ever existed in git** | unversioned state with a citation that looks recorded |

The last row also costs an instrument: a hosts override sits **above** DNS on the one machine you would
otherwise debug on, so a wrong zone answer becomes invisible exactly where it would have been noticed.

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
  forwards to the same Technitium chain first + 1.1.1.1/1.0.0.1 last
  (upstream mirror of the DHCP list, HD-317).
- Global inter-VLAN drop rule sits **below** these exceptions.
- There is **no** "allow DNS on the Management VLAN" rule — Technitium is **not** on the
  Management VLAN (it is Home/VPS-based).

---

## Local Name Resolution & mDNS

- **DHCP lease integration:** Technitium queries the RouterOS REST API for `/ip/dhcp-server/lease` → auto-creates `*.kogler.si` records. The VPS primary binds the **public** IP; the home secondaries bind the **Home**-VLAN IPs of oldsrv + Pi (per SSOT) — cross-VLAN DNS is permitted by the forward rules above.
- **mDNS reflector:** Technitium bridges `.local` names across all VLANs (RouterOS built-in mDNS is bridge-wide only, cannot cross VLANs). (RouterOS/Avahi cross-VLAN reflection is rejected — [network-rejected.md](network-rejected.md) mDNS reflection.)

---

## Convergence & Drift (the recurring DNS outage class)

> **Why DNS breaks:** the split-horizon records are applied by the `technitium-seed` tail of the
> `docker_services` role, which **only runs when a converge's deploy loop includes a technitium instance**.
> A deploy-SCOPED converge (`docker_services_scope=<svc>`) skips the seed silently — so a new/edited seed
> row lands on ONE instance and not the others until someone remembers to re-converge each host.

Three mechanisms close it — one command, one schedule, one gate:

1. **One-command re-seed of all three instances** — [`playbooks/dns-seed.yml`](../IaC/ansible/playbooks/dns-seed.yml):
   ```bash
   bash scripts/ansible-run.sh playbooks/dns-seed.yml
   ```
   Runs ONLY the `docker_services` role, scoped to each host's technitium instance (fast, surgical — no
   common/docker/network re-run; `compose up -d` is a no-op on unchanged specs), and re-asserts zone + all
   records + recursion ACL via the idempotent seed tail. Use it after **any** edit to `technitium-seed.yml`
   instead of remembering three manual converges.

2. **Scheduled self-heal (per DNS host)** — the `docker_services` role deploys systemd
   [`dns-seed.service`](../IaC/ansible/roles/docker_services/templates/dns-seed.service.j2) +
   [`dns-seed.timer`](../IaC/ansible/roles/docker_services/templates/dns-seed.timer.j2)
   (interval `dns_seed_interval`, default 5m). The timer runs a no-op-if-synced `docker compose up -d` on
   the local Technitium compose — this starts the container if it is down (self-healing a stopped DNS tier)
   and, because zones live in the persistent `/etc/dns` bind, an up-to-date compose == an up-to-date zone.
   It is the **trigger, not a memory**: an edited SSOT + a scoped converge that skipped the seed self-heals
   within the interval. The VPS `:53` publish stays source-restricted (nftables FORWARD gate, HD-299) — a
   compose up on an unchanged spec does not recreate/re-publish it.

3. **Static drift gate** — [`scripts/check_dns_seed_drift.py`](../scripts/check_dns_seed_drift.py)
   (wired into `validate-all.sh`): renders the seed record table against the SSOT for all three instances
   and enforces the per-instance split + the LAN-only `when`-gate. A record/gate drift FAILS the repo gate
   before a converge ships — the mechanical form of the parity guard below.

> **Single-namespace parity rule:** the split-horizon zone must carry the SAME public record set that
> Cloudflare serves — **every `cloudflare_dns/vars/main.yml` public record must also be an A record in the
> `technitium-seed` loop** (target `dns_primary_ip` = what the public CNAMEs resolve to), including the
> apex `vps.kogler.si` (the A/AAAA host every public CNAME flattens to). The authoritative VPS primary
> answers `NXDOMAIN`/`NOERROR`-0 for anything missing from its zone, and it is first in several resolver
> chains — so a missing record looks like "that name does not exist" (browser `ERR_NAME_NOT_RESOLVED`,
> `ssh vps` = *No such host is known*) even though Cloudflare has it.

> **Convention:** any new `*.kogler.si` A record lands in `technitium-seed.yml` **in the same commit** as
> its service bring-up; then run `playbooks/dns-seed.yml` to push it to all three instances. The self-heal
> + gate cover the human-forgets case.
> **Records-loop note:** `tailnet_sidecar_ip` is a cluster constant — the loop must use
> `default(tailnet_sidecar_ip, true)` so hosts that do not define it (home instances) still seed the row.

---

## Pi-hole (retired)

Pi-hole is *retired* — Main-Group ad-blocking runs on **Technitium Advanced Blocking** (the reliable VPS/Pi
DNS tier) instead of the oldsrv container. Its catalog row, historical configuration and the retirement
record live in [`services-dns.md`](services-dns.md) and
[`services-rejected.md`](services-rejected.md). This file owns only the per-VLAN/subnet DNS **policy** above.
