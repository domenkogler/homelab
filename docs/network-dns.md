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
| Home (10) | Main-Group | **Pi-hole** | Aggressive ad-blocking — **HD-326 (2026-09-04): the two kids tablets are per-MAC dst-nat'd to the Kids-Group resolver** (router NAT redirects their :53 to Technitium, which applies the Kids-Group policy — Cloudflare Families; see the Kids row) |
| Kids (40) | Kids-Group | **Cloudflare Families** (1.1.1.3) | Adult content + porn filtering — the VLAN-40 hijack (HD-182) covers the (now unused) Kids VLAN; the Home-VLAN kids tablets get the same policy via the per-MAC dst-nat (HD-326) |
| IoT (20) | IoT-Group | **Quad9** (9.9.9.9) | Malware + botnet blocking — cloud-IoT devices in `iot-wan-allow` (HD-312 phase 3) still resolve via this row; they only gain WAN egress, not a DNS bypass. **HD-342 (2026-09-07):** IoT plain :53 is dst-nat'd to the Pi tertiary (`dns_tertiary_ip`) so per-device query visibility lands on the Pi's log (`dns-pi.kogler.si`); DoT(853) bypass is dropped (router role). The Pi's IoT-Group chain still applies the Quad9 upstream.
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
  (tailnet CGNAT + home WAN only, HD-299).
  **🔴 2026-09-08 open-resolver exposure (fixed):** the INPUT source-allow alone was
  NOT the control — Docker's published-port `53:53` DNAT happens in PREROUTING and is
  then FORWARDED to the container bridge, so those packets never traverse the INPUT
  chain's `ip saddr @dns-allow-home … dport 53 accept`. They were matched by the
  generic `oifname "br-*" accept` in the nft FORWARD chain, so ANY external source
  reached the resolver (confirmed live: scanners `reposify.net`/`pfcloud.network`/
  AWS/GCP hit it, and it answered recursion from a non-ACL source). **Fix:** the
  FORWARD chain now source-restricts the DNS primary published port (`:53 →
  {{ tchnitium_dns_overlay_ip }}`) to the same allow set (tailnet CGNAT `100.64/10`
  + home WAN `@dns-allow-home`), dropping everything else to the container — a FORWARD
  drop is authoritative over Docker's iptables accept (proven by the 2026-08-23
  isolation incident). Template: `vps-hardening/templates/nftables.conf.j2`; apply via
  `playbooks/vps.yml --tags hardening`.
  **✅ Post-fix verification 2026-09-08 (all three access classes live-tested):** ① LAN
  VLAN-10 (Pi-first) resolves the full `*.kogler.si` set; ② home-WAN → VPS primary
  (`@dns-allow-home` = home WAN IP) resolves incl. recursion (`example.com`); ③ tailnet
  CGNAT → VPS primary verified from a real tailnet node (`tailscale-sidecar` @
  CGNAT range : `nslookup {ha,sso,dns,vps,stats}.kogler.si <VPS resolver per SSOT>` all answer,
  `stats` → the `tailnet_sidecar_ip` edge). The FORWARD-chain drop counters stayed at 43 UDP / 0 TCP
  during the CGNAT queries (traffic went through the allow, not the drop), proving the
  gate permits exactly the two allowed classes and rejects the rest.
  **🔴 Recursion-policy gap (2026-09-08):** the seed sets `allowRecursion=true` +
  `allowRecursionOnlyForPrivateNetworks=false` ("allow all networks") and intends the
  `recursionNetworkACL` (home subnets + tailnet CGNAT + loopback) as the real gate, but
  that ACL did NOT enforce from an external source (a non-ACL source got full
  `ra`/NOERROR answers, verified live). The FORWARD-chain gate above is now the
  authoritative network-level control; the ACL remains defense-in-depth (keep the
  allow-list).
  **🔴 Recursion policy (HD-317 follow-up, 2026-09-03, FULLY API-managed):** Technitium
  default `recursion` is `AllowOnlyForPrivateNetworks` — refuses recursion for any PUBLIC
  source, incl. home-WAN/hairpin (src = home WAN IP) and tailnet CGNAT (100.64/10 is not
  RFC1918) → home WSL/laptop + Windows Tailscale DNS broke (REFUSED) while VPS-local tests
  passed. `technitium-seed.yml` now sets the recursion policy + ACL via the API **booleans**
  `allowRecursion=true` + `allowRecursionOnlyForPrivateNetworks=false` (= "Allow all
  networks") plus `recursionNetworkACL` = home LAN subnets (SSOT `network_vlans`) + tailnet
  CGNAT + loopback. No manual/UI step required — fully idempotent on every converge.
  .rsc/role parity: the DHCP dns-server is
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
  - **✅ WAN-out failover test PASSED 2026-09-08 (owner, PPPoE disabled on the router):** with the
    home WAN down, `dig @159.195.111.66` (VPS primary) timed out while the **LAN-local Pi answered
    the full `*.kogler.si` set** and HA/dns-pi stayed 200; clean immediate recovery on PPPoE
    re-enable (no negative caching). This proved the **Pi leg**; **✅ oldsrv leg DONE + LIVE 2026-09-08
    (HD-340):** oldsrv Technitium admin recreated to the 1P `technitium_login` value (default
    `admin`/`admin` verified by direct login test, then `changePassword` API) + `home_servers.yml -e
    docker_services_scope=technitium` seed converge `failed=0` → `kogler.si.zone` seeded with the full
    split-horizon record set; live-verified `dig @127.0.0.1 {ha,dns-pi,stats,...,drop}.kogler.si` all
    answer from the oldsrv secondary (record set identical to VPS/Pi). **All three legs seeded — the
    3-instance DNS HA is COMPLETE.**
- The **secondary/tertiary are a true failure-domain split** — oldsrv, Pi, and VPS are all
  different physical boxes.
- `ha.kogler.si` resolves to the **VIP** on every instance (see [`smart-home-failover.md`](smart-home-failover.md)) so DNS is never the thing that breaks HA lookup.
- **The VIP's `:443` edge is served by whichever keepalived node owns the VIP:** in normal mode the Pi's minimal **`traefik-ha`** edge serves `ha.kogler.si`; after a forward takeover the home-LAN **`traefik-internal`** edge on oldsrv takes over (HD-349/346). Both serve an identical `ha` route → VIP:8123, so `ha.kogler.si → VIP` is always served by the active HA node (**no DNS flip on failover**). See [`smart-home-failover.md`](smart-home-failover.md) + the re-decided edge model [services-traefik.md](services-traefik.md) §Edge model.
- **Web UIs:** primary web UI on `dns.kogler.si` (VPS, Forward-Auth; **no host 5380** — served via the VPS Traefik overlay). **Note: Forward-Auth only GATES the edge — Technitium has its OWN local `admin` login (1P `technitium_login`) behind it; SSO never logs you into Technitium** (confirmed live 2026-09-08).
  **🔴 404 fixed 2026-09-03:** `https://dns.kogler.si/` returned 404 because the `forward-dns`
  Authentik ProxyProvider was missing from `ks-forward-auth.yml` (the route + forward-auth label
  existed since HD-62; the outpost 404'd on the unmatched Host). Added `provider_edge_dns` +
  `app_edge_dns`; deploy via `playbooks/authentik-blueprints.yml`. The Pi tertiary has **`dns-pi.kogler.si`** — FQDN shape only borrowed from the cockpit naming; like `ha` it resolves to the **VIP (`ha-vip`)** and is served by the Pi's `traefik-ha` edge → local `pi:5380` (IP per SSOT), so it stays reachable when oldsrv is down (internal-only, no Forward-Auth). **The 5380 publish is now TERTIARY-ONLY** (IaC `a238e47`; **LIVE 2026-09-04** — landed via the Pi `docker_services` converge; `technitium-pi` publishes `5380:5380/tcp`, `pi:5380` answers HTTP 200): the Pi Technitium container publishes `5380:5380/tcp` so the traefik-ha `dns-pi` route (network_mode: host → http://{{ technitium_secondary_ip }}:5380) actually answers (was 502 — the port wasn't listening); oldsrv (secondary) stays unexposed and the VPS primary stays overlay-only. Direct fallback `pi:5380` on the LAN. oldsrv's UI is not exposed (primary UI lives on the VPS). **✅ Pi admin-align + seed DONE + LIVE 2026-09-07 (HD-330):** Pi Technitium admin recreated to the 1P `technitium_login` value; `raspberry_pi.yml -e docker_services_scope=technitium-secondary` converge `failed=0` created `kogler.si.zone` + all split-horizon A records (`ha`/`dns-pi` → VIP, dashboards → `tailnet_sidecar_ip`, `sso` → VPS public IP). Verified: `getent hosts ha.kogler.si` → VIP; `dig @<Pi Home IP per SSOT>` and `dig @<VPS primary>` both answer. Two seed IaC bugs fixed (container-IP discovery literal `\n` gluing two IPs → fixed with `tr`+`awk`; VPS-only `tailnet_sidecar_ip` in the records loop → `default(tailnet_sidecar_ip, true)` (cluster constant)).
- **Static records (do not forget):** `ha.kogler.si → VIP` and `dns-pi.kogler.si → VIP` (VIP = `ha-vip`, value per SSOT), **plus** `sso.kogler.si → {{ dns_primary_ip }}` (the VPS public IP — Authentik edge; same target as its public CNAME, so internal + public agree; seeded on every instance) must be created as **A records on EVERY Technitium instance** (VPS primary + oldsrv secondary + Pi tertiary). DHCP auto-creation only covers leases, and the VIP is **not** a lease — without them the traefik-ha / oldsrv edges are unreachable by name. **ALL THREE INSTANCES SEEDED (2026-09-08):** VPS primary (**HD-324**) + Pi tertiary (**HD-330**) seeded earlier; **✅ oldsrv secondary seeded LIVE 2026-09-08 (HD-340)** — admin recreated to 1P `technitium_login` + `technitium-seed` converge green; `dig @127.0.0.1 <record>.kogler.si` answers the full set on oldsrv too. The 3-instance split-horizon battery (Pkg C) is COMPLETE. (The seed role reads `technitium_login`/`technitium_api` from 1Password and runs on every `docker_services` converge.) **`modem.kogler.si` is NOT a universal record** — the Comtrend UI is LAN/router-only (must never resolve from the VPS/internet); handle it LAN-side (HD-302). **IaC + LIVE 2026-09-08 (HD-302):** seeded on the **home instances only** (Pi tertiary `secondary-pi` + oldsrv secondary `secondary`) via a `when`-gate in the seed loop — the modem row is skipped on the VPS primary (`primary` instance). **Verified live 2026-09-08:** `dig @<pi> modem.kogler.si` + `dig @<oldsrv>` both → the SSOT modem IP; `dig @159.195.111.66` (VPS primary) does NOT answer it.- **Static records — tailnet admin dashboards (HD-135b follow-up / HD-273, 2026-08-28):** the **plain `*.kogler.si`** admin names (`stats`, `logs`, `csui`, `sec`, `traefik`, `auto`) must be **A records on BOTH Technitium instances → the `vps-obs` tailnet IP** (the `tailnet_sidecar_ip` group_var, `group_vars/vps.yml` — the traefik-tailnet edge). **Why:** Tailscale client MagicDNS only ANSWERS its `base_domain` (`ts.kogler.si`); for a FQDN matching a search domain (`kogler.si`), the client queries its **configured nameserver for that domain** — here Technitium — so without these records the plain names NXDOMAIN on tailnet devices (the `.ts.kogler.si` twins work via MagicDNS extra_records; the plain set needs the Technitium split-horizon, exactly like `ha`). The value is a **tailnet IP** so ONLY tailnet clients can reach it (LAN-only clients resolve it but fail to connect — correct, tailnet-only). **SEEDED 2026-09-03:** on the Pi instance (verified live); VPS primary + oldsrv secondary via the seed role once their admin is up.
- **Per-device DNS visibility + control-plane records (HD-334, Option A edge model — ✔️ LIVE 2026-09-07, CLOSED):** two changes, tracked as HD-334 (heading the internal-edge package F in todo.md §2.1a):
  - **Pi-first VLAN-10 DHCP DNS:** the Home-VLAN `dhcp-10` dns-server ordering becomes **Pi → VPS-primary → oldsrv → router** (currently VPS-primary first, line 53) so LAN clients resolve via the **Pi** — each device's IP appears in the Pi's query log (per-device visibility) and real per-MAC filtering works once HD-330 rotates the Pi admin + seeds its zone. VPS-primary-first stays for the other VLANs (guest/mgmt/iot/media) — they are not per-device-filtered.
  - **Seed-loop extension:** the `technitium-seed` loop gains `vpn.kogler.si` / `home.kogler.si` / `dns.kogler.si` → the right split-horizon targets (VPS public IP for the control-plane/home login; the missing records behind the Tailscale `vpn.kogler.si` NXDOMAIN). Seeded on EVERY instance (VPS primary + oldsrv + Pi).
  - **Verify (✔️ DONE + LIVE 2026-09-07):** after HD-330 (Pi admin-align) → Pi converge (`raspberry_pi.yml -e docker_services_scope=technitium-secondary`) → `dig @<pi> vpn/home/dns` + the Pi Technitium query log shows per-device queries. · [roles/router/tasks/main.yml](IaC/ansible/roles/router/tasks/main.yml) (dhcp dns-server chain) · [technitium-seed.yml](IaC/ansible/roles/docker_services/tasks/technitium-seed.yml)
  - **Single-namespace parity guard (HD-341, 2026-09-07):** the split-horizon zone must carry the SAME public record set that Cloudflare serves, so LAN/tailnet clients resolve `*.kogler.si` consistently. The authoritative VPS primary answers **NOERROR/0-answer (NODATA)** for any name NOT in the seed loop — even though Cloudflare has it — producing `ERR_NAME_NOT_RESOLVED` in browsers using the VPS-primary-first chain (live 2026-09-07: `file/foto/git/bin/ai` broken while `sso` fine). Rule: **every `cloudflare_dns/vars/main.yml` public record must also be an A record in the `technitium-seed` loop** (target `dns_primary_ip` = same as the public CNAMEs resolve to). The seed loop now includes the full public set (`kogler.si` root + `sso/dns/home/vpn/file/foto/git/bin/ai/office/pdf/chat/matrix/drop`). Re-seed VPS primary + Pi tertiary (+ oldsrv) to close. **HD-344 (2026-09-08): `vps.kogler.si` itself was the ONE public record missing from the seed loop** — the apex A/AAAA host every public CNAME (`sso`/`dns`/`home`/…) flattens to (its public A + AAAA live in `cloudflare_dns/vars/main.yml`). Since the authoritative VPS primary Technitium answers NXDOMAIN for names missing from its zone (and is FIRST in the home WSL + Windows resolver chain), `vps.kogler.si` never resolved → `ssh vps` failed with *No such host is known*. Added `vps.kogler.si → {{ dns_primary_ip }}` (A-only; the public AAAA covers IPv6) to the `technitium-seed` loop, seeded on EVERY instance. **Live 2026-09-08:** VPS technitium-scope converge + `dig @159.195.111.66 vps.kogler.si` → `159.195.111.66`.
  - **Per-client DNS visibility deploy step (HD-341):** the Pi-first ordering is authored (VPS-primary-first for non-VLAN-10); apply the router converge so VLAN-10 clients resolve via the Pi — their per-device IPs then appear in the Pi Technitium query log instead of everything collapsing to the home WAN egress `193.77.156.222` on the VPS primary.
  **✅ RESOLVED + LIVE-VERIFIED 2026-09-03 (HD-324): the VPS primary Technitium is now seeded** (admin recreated to the 1P `technitium_login` value via the documented `POST /api/user/changePassword` API after the default `admin`/`admin` bootstrap login; seed role fixed + green; `dig @159.195.111.66 {ha,dns-pi,stats,logs,csui,sec,traefik,auto}.kogler.si` all answer; **`sso.kogler.si` added to the seed loop 2026-09-04 (HD-329)** — this was the one missing internal record behind the `stats.kogler.si → sso` login loop's ERR_NAME_NOT_RESOLVED once the laptop used the router chain; `modem` stays LAN-only / router-side (HD-302, not universal)). Prior root cause (for the record): The laptop's DNS chain is router DHCP → VPS primary first (→ oldsrv down → Pi). The VPS primary answers `dns.kogler.si` (CNAME to `vps.kogler.si`) but **NOERROR/0-answer for `stats.kogler.si`** — its `auth.config` has a stale `admin` whose password does NOT match the 1P `technitium_login` item → the `technitium-seed` role's login fails (`Invalid username or password for user: admin`, verified via `/api/user/login` POST to the container's overlay IP `tchnitium_dns_overlay_ip` :5380) → the seed never runs → no `stats`/`ha`/`logs`/… A records on the VPS primary. The router itself resolves correctly (`dig @router stats.kogler.si` → `tailnet_sidecar_ip`), and the Pi tertiary HAS all records (`dig @<pi Home IP per SSOT>`), so the failure is confined to resolvers that hit the VPS-primary FIRST and cache the negative (laptop WSL → Windows host → router → VPS primary). **DONE (HD-324, 2026-09-03):** the documented API path was used — the seed's default-bootstrap login `admin`/`admin` succeeded after the 502 fix, and `POST /api/user/changePassword` (`pass` + `newPass` + `Authorization: Bearer`, per [APIDOCS](https://github.com/TechnitiumSoftware/DnsServer/blob/master/APIDOCS.md)) set the admin to the 1P `technitium_login` value; the `technitium-seed` role (with the `register: _tech_record` fix) seeded the zone + all records; seed converge now `failed=0` idempotently. oldsrv secondary seeds the same way once its admin is up (Phase 3). Cloudflare `stats` correctly returns empty (internal-only). **Historical record (2026-09-03, HD-317/HD-297c):** the owner-facing symptom *`https://stats.ts.kogler.si/` works but `https://stats.kogler.si/` doesn't* was traced to the VPS primary Technitium NEVER SEEDING — its `auth.config` had an `admin` whose password did NOT match the 1P `technitium_login` item → the `technitium-seed` role's login failed (`Invalid username or password for user: admin`, verified via `/api/user/login` POST to the container's overlay IP `tchnitium_dns_overlay_ip` :5380) → no `stats`/`ha`/`logs`/… A records on the VPS primary → the laptop resolver (router DHCP → VPS primary first, oldsrv down, Pi last) got NOERROR/0-answer for `stats.kogler.si` and cached it. RESOLVED by the HD-324 admin recreate + seed converge above.
- **Static records — *arr stack (every instance → oldsrv Traefik edge):** `seerr`, `sonarr`,
  `radarr`, `lidarr`, `prowlarr`, `bazarr`, `sab`, `torrent`, `media`, `profilarr`, `logs` (all
  `*.kogler.si`). Recyclarr has no hostname (scheduled worker, no UI). All are **internal-only** —
  no public (Cloudflare) record, WAN-blocked (see `services.md`).
- **Coupling tradeoff (accepted):** the Pi also hosts primary HA. A Pi failure takes the DNS **tertiary** down **with** it — but the DNS primary (VPS, HD-299) and secondary (oldsrv) survive, and oldsrv is exactly the box HA fails over to, so resolution is never the thing that breaks HA in the Pi-down scenario.

---

## Single Namespace & Split-Horizon

Everything uses one namespace **`kogler.si`** (DHCP option 15, hosts, services).

- **Local (Technitium):** authoritative for `*.kogler.si` internally — resolves hosts/services to internal IPs, and auto-creates records from DHCP leases.
- **Public (Cloudflare):** publishes **only** the internet-facing subset — the human-readable mirror is [`services.md`](services.md) §Domain & Subdomain Plan (`kogler.si` root + `home`, `sso`, `dns`, `foto`, `file`, `office`, `ai`, `git`, `ha`, `vpn`, `matrix`, `chat`). Cloudflare is **DNS-only** (no proxy) — real client IPs reach Traefik. **`dns` (the Technitium web UI) is the ONE admin-surface exception** (added 2026-09-03, now in the IaC SSOT `cloudflare_dns/vars/main.yml` per HD-198): `dns.kogler.si` → `vps.kogler.si` is needed as the public bootstrap path to the VPS DNS admin (and for the owner to recreate the VPS admin + finish seed), even though the UI itself sits behind Authentik Forward-Auth. **HD-198 (public-record SSOT method):** publish public records **incrementally** — one `*.kogler.si` record added to `cloudflare_dns/vars/main.yml` as each service lands on the VPS edge (gate: applies go LIVE on Cloudflare), and keep `docs/services.md` §Domain & Subdomain Plan as the human-readable mirror re-rendered as the list grows. The live Cloudflare zone + `cloudflare_dns/vars/main.yml` are dual SSOTs — never hand-edit the live zone without the file (and vice-versa). `dns` is the one admin-surface exception (added 2026-09-03, HD-198).
- **Internal-only services/hosts (stats, ad, auto, logs, cockpit-*, router, switch, nas, oldsrv) have **no public record**; WAN firewall blocks them (defense in depth). **The observability admin dashboards (stats/sec/traefik/logs/csui/auto) are tailnet-only** (HD-135b follow-up, 2026-08-28): the Phase-1 public CNAMEs are removed from the IaC SSOT (`cloudflare_dns/vars/main.yml`) and must be **deleted from the Cloudflare zone** by the owner (deploy-gated — the Ansible role only ensures `state: present`, it does not delete live records). On the tailnet they resolve via **headscale MagicDNS** — `dns.extra_records` maps each dashboard subdomain (and its `*.ts.kogler.si` twin) to the `vps-obs` tailnet IP, and `dns.search_domains: [kogler.si]` extends MagicDNS to the plain `*.kogler.si` names — so the owner's tailnet devices reach `https://stats.kogler.si`, `https://logs.kogler.si`, … directly (see [`network-vpn.md`](network-vpn.md) §Tailnet-exposed services). Technitium (the LAN resolver) carries **no** record for these — plain-LAN clients cannot route to the VPS tailnet IP anyway.
- **TLS:** a single wildcard `*.kogler.si` certificate, issued via ACME **DNS-01** with a Cloudflare API token (1Password `Homelab-ansible`) — covers internal and public hostnames alike.

### A / AAAA policy

- **Public (Cloudflare, DNS-only):** publish **A + AAAA** for the internet-facing set — same list as the mirror in [`services.md`](services.md) §Domain & Subdomain Plan. The home `/56` prefix is **static** (unchanged for 7+ years), so AAAA is safe and enables real dual-stack. Assign oldsrv a **fixed global IPv6** from the /56 for its AAAA.
- **Manually or via Ansible:** the public record list is the SSOT in `IaC/ansible/roles/cloudflare_dns/vars/main.yml`, applied by `playbooks/dns.yml` (control node, `community.dns.cloudflare_dns`, token `cloudflare_api` in 1Password `Homelab-ansible`; **IP-filtered to `193.77.156.222` — run from the home control plane only**). Records for the VPS public edge (`vps` → `159.195.111.66` / `2a0a:...`) are already listed; add each `*.kogler.si` service there as it moves onto the VPS.
- **Matrix delegation (public):** the homeserver name is `kogler.si`, delegated to `matrix.kogler.si` — publish `_matrix._tcp` SRV (`matrix.kogler.si 443`) and serve `_matrix/client` + `_matrix/server` well-known on `kogler.si` and `matrix.kogler.si` (Caddy/Traefik static host or an intermediate). Required for clean `@user:kogler.si` IDs and federation (see [`services-matrix.md`](services-matrix.md)).
- **Internal (Technitium):** serve **A (IPv4)** for all hosts/services — primary, deterministic, matches the static VLAN/IPv4 plan and the IPv4 inter-VLAN firewall.
- **Internal AAAA: REJECTED for now (HD-36, owner decision 2026-09-09).** Static prefix would allow it, but it needs stable per-host global addressing **and** mirroring inter-VLAN isolation in the IPv6 firewall (currently IPv6 is WAN-only). No current internal-IPv6 need; IPv4-first internally. Revisit only if a concrete requirement appears. Decision log: [network-rejected.md](network-rejected.md) HD-36.

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
