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

- **Public (Cloudflare, DNS-only):** publish **A + AAAA** for the internet-facing set — same list as the mirror in [`services.md`](services.md) §Domain & Subdomain Plan. The home `/56` prefix is **static** (unchanged for 7+ years), so AAAA is safe and enables real dual-stack. Assign oldsrv a **fixed global IPv6** from the /56 for its AAAA.
- **Manually or via Ansible:** the public record list is the SSOT in `IaC/ansible/roles/cloudflare_dns/vars/main.yml`, applied by `playbooks/dns.yml` (control node, `community.dns.cloudflare_dns`, token `cloudflare_api` in 1Password `Homelab-ansible`; **IP-filtered to the home WAN address — run from the home control plane only**). Records for the VPS public edge (`vps` → the VPS public A/AAAA) are already listed; add each `*.kogler.si` service there as it moves onto the VPS.
- **Matrix delegation (public):** the homeserver name is `kogler.si`, delegated to `matrix.kogler.si` — publish `_matrix._tcp` SRV (`matrix.kogler.si 443`) and serve `_matrix/client` + `_matrix/server` well-known on `kogler.si` and `matrix.kogler.si` (Caddy/Traefik static host or an intermediate). Required for clean `@user:kogler.si` IDs and federation (see [`services-matrix.md`](services-matrix.md)).
- **Internal (Technitium):** serve **A (IPv4)** for all hosts/services — primary, deterministic, matches the static VLAN/IPv4 plan and the IPv4 inter-VLAN firewall.
- **Internal AAAA: REJECTED for now (HD-36).** Static prefix would allow it, but it needs stable per-host global addressing **and** mirroring inter-VLAN isolation in the IPv6 firewall (currently IPv6 is WAN-only). No current internal-IPv6 need; IPv4-first internally. Revisit only if a concrete requirement appears. Decision log: [network-rejected.md](network-rejected.md) HD-36.

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
