---
title: DNS Architecture
role: detail
domain: network
status: active
tags: [network, dns, technitium]
---
# DNS Architecture

> **Role:** Detail — DNS routing, Technitium, per-subnet policy.
> **Links to:** `network-vlans.md`, `services.md`
> **Linked from:** `network.md`, `index.md`

---

## Design: Technitium as Central DNS Router (Primary + Secondary + Tertiary)

Technitium runs as a Docker container on the **VPS (primary)** and two home instances —
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
| Home (10) | Main-Group | **Technitium Advanced Blocking** (ad-block lists, per-client groups, multiple block-list formats) | Aggressive ad-blocking on the reliable DNS tier (VPS/Pi). The two kids tablets are **per-MAC dst-nat'd to the Kids-Group resolver**: router NAT redirects their `:53` to Technitium, which applies the Kids-Group policy. |
| Kids (40) | Kids-Group | **Cloudflare Families** (1.1.1.3) | Adult content + porn filtering — the VLAN-40 hijack covers the (currently unused for Wi-Fi) Kids VLAN; the Home-VLAN kids tablets get the same policy via the per-MAC dst-nat |
| IoT (20) | IoT-Group | **Quad9** (9.9.9.9) | Malware + botnet blocking. **No ad block lists here:** appliance firmware is the flakiest thing on the network and shares CDN/IP ranges with ad-serving endpoints, so the IoT tier gets malware blocking at the resolver and nothing more. Cloud-IoT devices with `wan_allow` still resolve through this row — they gain WAN egress only, never a DNS bypass. IoT plain `:53` is dst-nat'd to the **Pi tertiary** (`dns_tertiary_ip`) so per-device query visibility lands on the Pi's log (`dns-pi.kogler.si`); DoT(853) bypass is dropped (router role). |
| Guest (30) | Guest-Group | Same as Home | **Guest inherits the Home block set** — the same protection for unmanaged guest devices, and one group fewer to maintain. Home and Guest carry **no block list** (see §Tier policy rulings). |

> ⚠ **The Group / Upstream-Filter columns above are DESIGN, not live state.**
> Read over the API on the Pi tertiary **and** the VPS primary: `blockListUrls = null` (blocking is enabled,
> `blockingType = NxDomain`, but there is not a single list), **no client custom options exist at all** —
> which is the mechanism Technitium uses for per-subnet upstreams — and `logQueries = false` on both, with no
> `/var/log/technitium/dns` on the Pi. So what enforces per-VLAN behaviour today is the **router-side**
> per-VLAN / per-MAC `:53` dst-nat, which chooses *which resolver answers*, not the upstream
> filter. Consequence: the Kids (Cloudflare Families) and IoT (Quad9) rows are **not implemented on the DNS
> tier**, and the per-device query visibility this doc cites as the reason for Pi-first (and for the IoT
> dst-nat) **cannot be observed at all**.
> The *capability* stays intended, so the table is design/pending rather than deleted. Pending, on the DNS
> tier: client groups + the block-list mechanism, the Kids → Cloudflare Families `1.1.1.3` upstream, the
> IoT → Quad9 upstream, and `logQueries` on the Pi. Until those land nothing in the Group / Upstream-Filter
> columns is enforced, and the visibility claim must not be written up as achieved anywhere.

### Tier policy rulings — what the DNS-tier work is built against

The shape below is decided; the rows carry only the implementation. **This section is the ruling — the
policy table above must not restate it.**

| # | Question | Ruling |
|---|---|---|
| 1 | Which block lists for **Home** | **None** — the Home/Guest tier loads no block list. The candidate light curated set Hagezi `multi` + `privacy` (`https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/multi.txt` + `…/adblock/privacy.txt`) is not loaded, and neither is an aggressive `multi+`/`premium`/`PRO` tier: this tier answers the operator's own tailnet traffic, so a false positive is self-inflicted |
| 2 | **Kids** scope | **VLAN 40 AND the two Home-VLAN kids tablets.** The per-MAC `:53` dst-nat is already live and lands on a group that does not exist; the tablets are the actual children, so VLAN-only would leave the doc's claim false. Upstream = **Cloudflare Families `1.1.1.3`**, never a block list — Families answers `NXDOMAIN` for the whole family-blocked set, which is the enforcement |
| 3 | **IoT** | **Quad9 upstream, no block lists** (see the table row above for why) |
| 4 | **Guest** | **Same as Home** |
| 5 | **Query log** (`logQueries`) | **On the Pi tertiary only** (the dst-nat target, i.e. the box that already sees IoT traffic), **14-day retention, root-readable, no per-device dashboard.** It is a per-device behaviour record on the box that also hosts the HA primary, so the retention and the readers are part of the setting, not an afterthought |

✅ **The Home/Guest tier carries NO block list** ([network-rejected.md](network-rejected.md)); the enforcement
the family actually needs (Kids) is an **upstream** (Cloudflare Families), not a list. A tier with no list
must read `enableBlocking=false`, while all three instances today run `enableBlocking=true` with
`blockListUrls=null` — blocking switched on with nothing loaded, a silent-failure shape that must not persist.

⚠ **Two consequences of the topology, independent of which lists are loaded**: (a) Home clients, **away
clients and tailnet clients all resolve through the VPS primary** (`dns_primary_ip` is the VPS's public
address), so whatever the Home tier loads applies to the operator's own VPN traffic too; (b) acceptance is
therefore per-**instance**, not per-VLAN — a setting loaded on one of the three instances is a fleet policy
with three failure modes, so drift-proofing the three instances is part of any change here.

⛔ **Acceptance is a device, not a `dig`**: an unsupervised device on each path fails to resolve a
filtered name while `kogler.si` still resolves. And because the Kids mechanism is an *upstream*, prove it by
answering-authority, not by an `NXDOMAIN` that a caching layer could have produced from a stale entry.

---

## Resolver upstream (forwarders)

✅ **live on all THREE instances 2026-09-30** — `forwarders = 1.1.1.1 + 9.9.9.9`, `forwarderProtocol = Udp`,
`concurrentForwarding = true` on the VPS primary, the oldsrv secondary and the Pi tertiary. One shared list
for all three instances; per-instance lists are declined
([`network-rejected.md`](network-rejected.md)). The flag is what carries it, and an instance that ever loses
the flag reverts to root-chase on the next seed by design.

**Why it matters.** An instance with `forwarders` empty has to chase each cold public name from the **root
servers** — with `dnssecValidation = true` and `qnameMinimization = true` both on and
`resolverTimeout 1500 × resolverRetries 2` as the per-name ceiling. The Pi is the instance the
Home VLAN asks first, on ARM, so it pays the most:

| Measured from the admin laptop | Pi root-chase | Pi + forwarders | oldsrv | 1.1.1.1 direct |
|---|---|---|---|---|
| 40-way browser-style fan-out, p50 / max | **143 / 162 ms** | **60 / 86 ms** | 74 / 80 ms | 46 / 55 ms |
| same fan-out, total wall clock | 190 ms | 91 ms | 85 ms | 62 ms |
| 120 sequential cold lookups, p50 | 49 ms | 38 ms | 50 ms | 32 ms |

**The other two legs, measured on their own box.** The pass above measures the Pi from the laptop and leaves
the VPS unmeasured, so both remaining instances were probed on the host, 12 cold disjoint domains per target,
root-chasing and then forwarding:

| Measured on the box itself | root-chase p50 / tail | 1.1.1.1 direct p50 | with forwarders (fresh disjoint set) |
|---|---|---|---|
| VPS primary | **39 ms / 116 ms** | 15 ms | **~18 ms**, max 48 ms |
| oldsrv secondary | **85 ms / 208 ms** | ~16 ms | **~40 ms**, max 132 ms |

The residual tail with forwarders set is the *forwarder's* cold cache for that name, not our chase depth.

**How to tell root-chase from forwarding without the admin API (reusable, read-only).**
`dig @<instance> o-o.myaddr.l.google.com TXT` returns the source address Google saw. A root-chasing instance
returns **its own egress** — VPS `159.195.111.66`, oldsrv `193.77.156.222`. A forwarding
one returns the forwarder's — VPS `66.185.117.247`, oldsrv `162.158.246.12` (a
Cloudflare range). The Pi cannot be probed this way (that box ships neither `dig` nor `nslookup`); its state
rests on the hand-clear → re-seed cycle instead.

⚠ **Method trap that makes a chase look fast:** `<random>.example.com` is **not** a cold probe — the
`example.com` glue is already cached, so the whole chase collapses to one hop and reads 0–4 ms. Use disjoint
*real* domains, and a **different set per target**, or the second target is reading the first one's cache.

**Why the HA requirement is untouched — this is the acceptance question.** Forwarders are an **egress** knob:
they change what the resolver asks outward, never which address clients ask or whether that address floats.
`ha.kogler.si`, `dns-pi.kogler.si` and the rest of `kogler.si` are answered **authoritatively** from the
instance's own primary zone (the `aa` flag holds on the Pi), so an upstream is never consulted for them and
dead upstreams cannot break HA name resolution. WAN egress is *already* a dependency of this design — root,
TLD and authoritative servers are all internet-resident — so nothing LAN-local is weaker here, and oldsrv is
not additionally in the answer path.

**Why exactly TWO upstreams.** With forwarders set, Technitium queries all of them in parallel (fastest wins)
and does **not** fall back to root recursion when they fail — "forward-first" is an open vendor request
([TechnitiumSoftware/DnsServer#481](https://github.com/TechnitiumSoftware/DnsServer/issues/481)), not a
feature. One upstream would therefore make public resolution depend on a single operator; Cloudflare + Quad9
are separate networks, operators and block policies. DNSSEC validation stays observable end to end: a forward
through the Pi returns the `ad` bit for a validated name, same as the forwarder itself.

⛔ **Never** point `dns_resolver_upstreams` at the router's `/ip dns` — its own upstream is this same resolver
chain, so that is a forwarding loop that also puts oldsrv/VPS back into the answer path — and not at oldsrv
either: the Pi is the Home VLAN's first resolver precisely so the HA-primary tier does not depend on the HA
standby (that requirement is why the ordering is not "fastest first").

**SSOT:** the list is `dns_resolver_upstreams` in [`group_vars/all/main.yml`](../IaC/ansible/group_vars/all/main.yml);
the per-instance opt-in is `technitium_forwarders` on **each** instance's `docker_services` entry —
[`group_vars/vps.yml`](../IaC/ansible/group_vars/vps.yml) (primary),
[`group_vars/home_servers.yml`](../IaC/ansible/group_vars/home_servers.yml) (oldsrv secondary) and
[`group_vars/raspberry_pi.yml`](../IaC/ansible/group_vars/raspberry_pi.yml) (tertiary); the API task is
`Technitium: set resolver upstream (forwarders) from SSOT` in
[`technitium-seed.yml`](../IaC/ansible/roles/docker_services/tasks/technitium-seed.yml). It is **declarative**:
an instance without the flag gets `forwarders=` cleared every seed (empty → readback stays `null`, proven a
no-op rather than an API error). Push with `bash scripts/ansible-run.sh playbooks/dns-seed.yml [--limit …]`.
The key is read **only** by that API task, never by
[`templates/docker_services/technitium/docker-compose.yml.j2`](../IaC/ansible/templates/docker_services/technitium/docker-compose.yml.j2),
so the render cannot change and no container is ever touched by a forwarder converge. Internal answers are
authoritative on every instance
(`llm.kogler.si` → spark's Home address, `ha.kogler.si` → `ha_vip`, flags `qr aa`), on loopback **and**
on the LAN address alike.

⚠ **Still un-owned by IaC:** the rest of the resolver's tuning is live-state product default that no role
sets — `resolverTimeout` / `resolverRetries`, `maxConcurrentResolutionsPerCore`, `cacheMaximumEntries = 10000`,
`dnssecValidation`, `qnameMinimization`, `serveStale`, `logQueries`. Forwarders eliminate the dominant cost; the
rest stays UI-and-memory until the seed owns it — and note the overlap: `logQueries` is also what the IoT
visibility claim and the Pi query log depend on, so whoever owns this tuning must not set a value that
silently closes or reopens that claim.

---

## Host-side resolver — what a box asks its OWN `/etc/resolv.conf`

✅ **live on oldsrv 2026-10-01** (`home_servers.yml --tags nm-resolver`) and ✅ **on the Pi 2026-10-08**
(`raspberry_pi.yml --tags nm-pi` → keyfile + `reload NetworkManager`; `getent llm.kogler.si` answers spark's
Home address **on the Pi itself**). Everything above this section is about what an *instance* asks outward.
This is the other axis: which resolver **the host itself** asks. Every home host inherits
`bootstrap_dns_servers` (`1.1.1.1`) — sound at boot, because a box that hosts the DNS tier must not need
it to boot, and disqualifying for the running box: a host on `1.1.1.1` cannot name one split-horizon service
of its own (`getent` empty, `curl` rc=6) even while the instance it hosts answers every one of them — see
[services-ai.md](services-ai.md) §9b-1.

Probe: `dig llm.kogler.si @<target>` **on oldsrv**:

| Resolver the box is asked to use           | Reply                | Verdict                                                            |
| ------------------------------------------ | -------------------- | ------------------------------------------------------------------ |
| own instance (`dns_secondary_ip`)          | spark's Home address | ✅ authoritative (`qr aa`), also on loopback                        |
| Pi tertiary (`dns_tertiary_ip`)            | spark's Home address | ✅ authoritative — the rung that survives the local instance dying  |
| VPS primary (`dns_primary_ip`)             | **nothing**          | ⛔ correct, and load-bearing: see below                             |
| `1.1.1.1` (`bootstrap_dns_servers`)        | nothing internal     | ⛔ the defect                                                       |

**The converged pair** is `host_resolver_dns` in
[`host_vars/oldsrv.kogler.si.yml`](../IaC/ansible/host_vars/oldsrv.kogler.si.yml) — own instance first,
Pi tertiary second, both SSOT-derived — applied by the `nm-resolver` leg of `roles/network`. There is
deliberately **no third rung**: the VPS primary is authoritative for the public view only, so as a
home host's resolver it answers `NXDOMAIN` for exactly the names this exists to resolve, and glibc
compares nothing — it takes the first reply it gets. A public/VPS fallback is therefore worse than a
timeout. ⛔ Floating the resolver with the VIP **replaces the first entry**, it does not add
one; the two rows must agree, not race.

**Two states, not one — converge both.** NetworkManager has an on-disk profile (`dns=a;b;`, keyfile
semicolon form) and a committed `/etc/resolv.conf` (`nameserver a`). They are not the same fact, and a
compare on the first alone stays green on a box whose second never landed. The role reads both, writes
only on profile drift, re-commits whenever the **applied** state is wrong (so a half-applied box
self-heals), and asserts the file at the end.

**NetworkManager owns oldsrv's uplink; systemd-networkd does not run there.** `NetworkManager` is
enabled+active, `systemd-networkd` **disabled and inactive**, and the rendered
`20-eno1.*` units name an interface this box does not have (the live Home parent is the same interface
`ha_keepalived_interface` names). There is no race for `resolv.conf` — the netd path is inert — and the
resolver leg goes through the installer's NM profile (`Wired connection 1`, written on disk **without** the
`.nmconnection` suffix the Pi/spark keyfiles carry). One config manager per box, **NetworkManager
fleet-wide** ([network-rejected.md](network-rejected.md)); `netd_phys_name: eno1` and those dead unit files
are the evidence for that rule, not part of this one.

**The Pi needs no nmcli leg, and that is a fact about the two boxes, not a shortcut.** oldsrv's uplink
profile is installer-owned, so its resolver must be read, modified and reapplied; the Pi's keyfile is rendered by
`roles/network` (`pi-eth0.nmconnection.j2`), so `dns=` comes from
`host_resolver_dns`, with `bootstrap_dns_servers` kept as the fallback for a host that has not defined a
steady-state pair, and the existing `reload NetworkManager` handler re-commits `/etc/resolv.conf`
without touching the link (the `traefik-ha` watchdog stays GREEN, `RestartCount` 0, HA 200 through the VIP).
Pair on the Pi = own instance first (`dns_tertiary_ip`) then oldsrv,
same rule as oldsrv, VPS absent for the reason above.

⚠ **`nas` is not in this class**: its `resolv.conf` is
`dns_tertiary_ip, dns_primary_ip, dns_secondary_ip` — Pi, VPS, oldsrv, in that order — so internal names resolve — but the VPS sits between two home
rungs, which is precisely the rung this design refuses, and `systemd-networkd` is **inactive** there, so
which manager owns the file is unresolved. Fixing it through this template would be guessing.

**Session-safe mechanism — `device reapply`, never `connection up`.** `connection modify` writes the
profile; the file is rewritten only when NM re-commits it. `connection up` tears the interface down and
re-activates it — that is the leg the converge, and every ssh into the box, rides. `device reapply` re-
commits without dropping the link: the converge that changes the resolver runs over that leg, the session
survives it, and the link reads `UP` with the same address afterwards.

⚠ **Three traps:**

1. `nmcli connection modify` and `nmcli device reapply` are **refused to a plain user** (rc=1
   `Insufficient privileges`, rc=6 `not authorized`). A hand test needs `sudo`; a converge does not,
   because `playbooks/home_servers.yml` is `become: true`.
2. `--tags <anything>` **skips "Gathering Facts"**, so a role that needs a fact must gather it itself —
   otherwise the reapply target is empty on exactly the scoped form this leg ships to be run with
   (`--tags nm-resolver`).
3. This repo runs `inject_facts_as_vars = False` (`ansible.cfg`): the top-level
   `ansible_default_ipv4` var **does not exist** — read `ansible_facts['default_ipv4']`.

**Verify (read-only, no secrets):**

```bash
ssh oldsrv 'grep -v "^#" /etc/resolv.conf; getent hosts llm.kogler.si'
bash scripts/ansible-run.sh playbooks/home_servers.yml \
     --limit oldsrv.kogler.si --tags nm-resolver --check --no-pull   # prints on-disk | applied | wanted
```

⛔ **Same class, other boxes.** The Pi carries its `host_resolver_dns` pair, and `nas` and `spark` are
unmeasured. Two places still read the Pi as a `1.1.1.1` box and so do not hold: `scripts/README.md`'s
guarded-converge row ("measure from the VIP address, not by name") and a Pi procedure that asserts
"Pi read-back proves nothing".

---

## Per-Instance Split-Horizon

✅ **live on all three instances** (VPS primary + oldsrv secondary + Pi tertiary).
⏳ After any Pi-side change, verify `dig @<home> media.kogler.si` → oldsrv LAN IP.

The three instances serve the SAME primary zone but with **per-instance A-record targets**, so LAN
clients stay on the home LAN while WAN/tailnet clients keep the VPS edge. Record table (matched by the
`technitium-seed` loop, per `svc.instance`):

| Record | VPS primary | oldsrv secondary + Pi tertiary |
|---|---|---|
| Home-hosted (`media`, `seerr`, `seerrng`, `sonarr`, `radarr`, `lidarr`, `prowlarr`, `bazarr`, `profilarr`, `sab`, `torrent`) | VPS public IP (`dns_primary_ip`) | **oldsrv LAN IP** (`oldsrv_home_ip`) — home edge, no WAN round-trip |
| `ha` / `dns-pi` | VIP (`ha_vip`) | VIP (`ha_vip`) — same on all (DNS never breaks HA lookup) |
| `ha.ts` (**tailnet-only**) | — (never seeded in Technitium) | — (never seeded) · resolves ONLY via **headscale `dns.extra_records`** to `tailnet_oldsrv_ip`, rendered by `tailnet_ts_only_subdomains` (group_vars/vps.yml) in the **`*.ts.kogler.si` namespace only** |
| `cockpit-nas.ts` (**tailnet-only**) | — (never seeded in Technitium) | — (never seeded) · resolves ONLY via **headscale `dns.extra_records`** to `tailnet_oldsrv_ip` (the class default), rendered by `tailnet_ts_only_subdomains` (group_vars/vps.yml) → oldsrv's own `websecure-ts` listener → `cockpit-nas-ts` in the cockpit role's `cockpit.yml` → `nas:9090`. Exists because the PLAIN `cockpit-nas.kogler.si` is LAN-only (a Home-VLAN answer is a black hole off-LAN), so off-LAN the nas console has no plain name of its own. Dies with oldsrv; see [services-traefik.md](services-traefik.md) §Cockpit Routes |
| `spark.ts` (**tailnet-only**) | — (never seeded in Technitium, and never a Cloudflare record) | — (never seeded) · resolves ONLY via **headscale `dns.extra_records`** to `tailnet_sidecar_ip`, rendered by `tailnet_ts_only_subdomains` (group_vars/vps.yml) in the **`*.ts.kogler.si` namespace only** → the tailnet edge Host-routes it over WG S2S to spark's own edge :443. The PLAIN `spark.kogler.si` is deliberately absent from MagicDNS: it is the host name, and answering a host name from the netmap is the resolver-ambiguity trap |
| VPS-hosted (`foto`, `file`, `git`, `ai`, `office`, `pdf`, `chat`, `matrix`, `drop`, `bin`, `sso`, `dns`, `vpn`, … + root/home/vps) | VPS public IP | VPS public IP (their backends live on the VPS; the home edge reaches them via wg-s2s :4443 double-hop) |
| Tailnet dashboards (`stats`, `logs`, `csui`, `traefik`, `auto`) | VPS tailnet sidecar IP | VPS tailnet sidecar IP (cluster constant) · these + the AI names (`llm`/`db-spark`/`litellm`) also resolve on tailnet devices via **MagicDNS extra_records** (both namespaces) — the Technitium A records remain for LAN/split-horizon parity |
| `modem` | — (never seeded on VPS) | LAN-only |
| `spark` / `db-spark` / `llm` | — (never seeded on VPS) | **spark LAN IP** (`spark_home_ip`) — headless GPU node, LAN-only (`spark` = the box, and the DGX dashboard's URL of record on :443; `llm` = spark OpenAI-API; `db-spark` = the LEGACY dashboard alias, kept resolving, no new consumers; VPS/tailnet reach them via the tailnet edge over WG S2S, not by seeding the primary) |
| `litellm` | VPS public IP (`dns_primary_ip`) — VPS-resident spine admin, split-horizon parity | VPS public IP — same (the LAN/tailnet reach the admin via the edge) |
| `llitellm` | — (never seeded on VPS) | **oldsrv LAN IP** — LAN (dev) LiteLLM on the home edge (LAN-only) |
| `llogs` | — (never seeded on VPS) | **oldsrv LAN IP** (`oldsrv_home_ip`) — LAN log hub (Dozzle), LAN-only (same rule as `modem`/`spark`: a LAN-only viewer must never resolve from VPS/internet) |

> **Why home-hosted names are per-instance:** the home-hosted apps run on **oldsrv** (host-net backends on
> `oldsrv_home_ip`). Pointing them at the VPS public IP on the home instances would make every LAN hit
> depend on WAN (the failover-drill finding). The home edge (`traefik-internal`,
> [services-traefik.md](services-traefik.md) §Edge model) serves them from `oldsrv_home_ip`; the VPS
> primary keeps `dns_primary_ip` so WAN/tailnet reach the VPS first.
>
> ⚠ **A split-horizon answer is a *promise*, and a promise with no route behind it is a 404.** The VPS primary
> answers the home-hosted names with `dns_primary_ip`, so unless the VPS edge also carries a **router** for
> them a client that asks the VPS first gets `media.kogler.si` → `dns_primary_ip` → **HTTP 404**, while the
> same name asked of either home instance returns `oldsrv_home_ip` → **302 → `/web/`**. Read the pair from any
> client: `dig @<VPS> media.kogler.si` → the VPS address, `dig @<Pi>` / `@oldsrv` → the oldsrv Home
> address, and `curl --resolve media.kogler.si:443:<VPS IP>` → 404 vs `:443:<oldsrv Home IP>` → 302.
> **Which resolver a VLAN queries first is therefore a reachability switch, not a preference** — see
> §DNS Flow and `network_vlans[].lan_first_dns`.
>
> **Both halves of the fix are required.** (a) `lan_first_dns` gives VLAN 10 **and 50**
> a home resolver first, and (b) the VPS edge routes `media` / `seerr` / `seerrng` to the home edge over
> WG S2S (`traefik/dynamic/routes.yml.j2`, the `ha` route as precedent, `crowdsec-only@file` per the
> [security.md](security.md) §1 law), so the VPS answer is served rather than merely pointed at.
> `media.kogler.si` is published publicly (`public: true` + the Cloudflare CNAME — see
> [services-media.md](services-media.md) §How to reach it from anywhere); `seerr` / `seerrng` are routed at
> the VPS edge but stay **unpublished**, so they are reachable by name only where a resolver is told.
> A VPS-addressed `--resolve media.kogler.si:443:<VPS IP>` reads **302**, and the same URL's
> `/System/Info/Public` returns Jellyfin JSON through the two-hop chain. The invariant to keep:
> **an answer plane and an edge route must move together** — "works on the Home VLAN, 404 everywhere else"
> is the signature of this defect, not of a dead service.

---

## DNS Flow

```
Client → Technitium (DHCP-pushed chain, see below)
        → Router /ip dns (implicit final fallback, own upstream = the same chain + Cloudflare)
```

- **Resolver chain pushed by DHCP (RouterOS caps `dns-server` at 3 values — a 4th is silently dropped,
  so the router IP is deliberately NOT in the list):**
  - **Home VLAN 10 and Media VLAN 50** (`lan_first_dns: true` on the `network_vlans` row — SSOT, the flag
    both the role and the converge render from, never a hardcoded VLAN id):
    **Pi tertiary → VPS primary → oldsrv secondary**. For VLAN 10 the durable reason is
    **HA-independence**: HA's primary runs on the Pi and the standby on oldsrv, so Home must keep resolving
    with oldsrv down, and the resolver must never sit behind the standby. ⚠ The other reason this chain is
    often quoted — *per-device query visibility in the Pi's log* — **is not delivered**:
    `logQueries = false` on the
    Pi, so the Pi's query log does not exist. Note the pushed address is the
    Pi's **node IP** (`dns_tertiary_ip`), not the VIP: the resolver does **not** currently float with HA.
    VLAN 50 is in this list for the other half of the same mechanism: the
    first resolver decides which **split-horizon answer** that VLAN gets for the home-hosted app names —
    see §Per-Instance Split-Horizon for the 404 that makes this a requirement, not a preference.
  - **Every other VLAN (guest 30 / kids 40 / mgmt 99):** **VPS primary → oldsrv secondary → Pi tertiary** —
    they are not per-device filtered, and their devices are expected to reach internal apps through the
    **VPS** edge. That holds for the VPS-hosted apps and, for the home-hosted ones, only because the VPS edge
    also carries routes for `media`/`seerr`/`seerrng` — a VPS-first VLAN can open them, and a missing route on
    that edge is the thing to look for if it cannot. (IoT 20 and the Kids MACs are separate: the router `dst-nat`s their `:53` to a
    chosen instance regardless of this order — see §Per-Subnet DNS Policy.)
  - The router's `/ip dns` is the **implicit** last resort via its own upstream (the same chain first +
    Cloudflare `1.1.1.1`/`1.0.0.1` last); its WAN egress is what the VPS `dns-allow-home` nft set permits.
  - `.rsc`/role parity: the DHCP `dns-server` is rendered from the same SSOT in
    `roles/router/tasks/main.yml`, `rb4011_converge.rsc.j2` and the transient
    `rb4011_dns_resolver_delta.rsc.j2` — all three read `network_vlans[].lan_first_dns`, so no
    apply path can hand a VLAN a different resolver order than the other two.
  - ⚠ **The rendered order is NOT what RouterOS stores.** `/import … set dns-server=<secondary>,<tertiary>,<primary>` (in `group_vars` IP order) reads
    back as `<tertiary>,<secondary>,<primary>` — **the list is re-sorted numerically on any write that
    actually changes it**; a `set` whose value already matches is a no-op, so the rows nobody rewrites
    keep whatever order they were created with (VLAN 10 shows `tertiary, primary,
    secondary`, which no current render can produce). Two consequences, both live now:
    (a) the invariant a `lan_first_dns` VLAN actually gets is *a home address sorts first* — true here
    only because the home resolvers sit on the Home-VLAN range and `dns_primary_ip` is a public address,
    which makes this **address-dependent, not a guaranteed property of the render**; (b) if a future converge ever *changes* one of
    the VPS-first VLANs, its list gets re-sorted too and that VLAN silently becomes home-first — the
    flip is invisible in the diff and in the template.
    **So the render is never the evidence; read the device:**
    ```bash
    ssh router ':foreach n in=[/ip dhcp-server network find] do={ :put (\
      [/ip dhcp-server network get $n address] . " -> " . [/ip dhcp-server network get $n dns-server]) }'
    ```
    ⚠ `/ip dhcp-server network print where address=…` and `print as-value` return **nothing** over
    non-interactive SSH on this build — the empty result is the probe failing, not the row missing
    (`[find …]` also resolves against the *current* menu, so a bare `find` at the root menu returns
    nothing and `set [find …]` silently changes nothing). Use the `foreach` form above.
- **Clients must query the Technitium instances DIRECTLY** — do NOT point DHCP at the router and let
  `/ip dns` forward: RouterOS `/ip dns` is a single global resolver/cache and cannot differentiate
  per-VLAN, so the per-subnet policy above would collapse into one upstream.
- The VPS primary is reached from the LAN through the existing Home/Media/Guest/Mgmt→WAN egress
  and from the tailnet via its public IP; the VPS nftables source-allow blocks everything else
  (tailnet CGNAT + home WAN only).
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
- **Away-from-home HA is a separate name, on purpose.** `ha.ts.kogler.si` answers only
  on the tailnet and points at oldsrv's own node; the plain `ha.kogler.si` keeps resolving to the VIP from
  every instance. The reason is the resolver-ambiguity class plus a failure-domain argument:
  MagicDNS answers extra_records **client-side on Android/iOS**, so a single name published to both planes
  would also send a tailnet-enabled phone **at home** to oldsrv instead of the VIP — putting a new
  `oldsrv`-must-be-up dependency inside the exact failure domain `smart-home-failover.md` exists to remove.
  The `.ts` twin costs the owner one extra entry in the Companion app and keeps both planes honest.
  ⚠ A client can hold a stale MagicDNS answer: `dig @100.100.100.100 ha.ts.kogler.si` proves what headscale
  serves; a client that disagrees needs a Tailscale reconnect (toggle), not a DNS change.
- **The tailnet resolver chain is location-independent.** `dns.nameservers` is **MagicDNS loop → oldsrv's tailnet node address → VPS public**. One resolver reachable from wherever the device is, instead of a list sorted by where the device usually is: the node address answers direct-over-LAN at home with the WAN pulled *and* away while the home link is up, and the VPS instance stays behind it so a dead node never costs away-side resolution. LAN-address nameservers (`oldsrv` LAN, `Pi` LAN) are deliberately **absent** from the chain: they are private home addresses, so a phone on cellular gets `DNS unavailable` and burns resolver timeouts before falling back — and they are also the only thing that would keep `*.kogler.si` answering on a tailnet device **at home with the WAN down** if the node address were not there, since the VPS primary is precisely the path a WAN outage removes; the node address takes over that job. The tradeoff, and why trimming is the wrong answer, is the decision record: §The resolution requirement below + [network-rejected.md](network-rejected.md). Names inside the tailnet's own domain answer from the netmap client-side, which is why tailnet-only records (`ha.ts`) resolve on any network regardless of which resolver is up.
- **The VIP's `:443` edge is served by whichever keepalived node owns the VIP:** in normal mode the Pi's
  minimal **`traefik-ha`** edge serves `ha.kogler.si`; after a forward takeover the home-LAN
  **`traefik-internal`** edge on oldsrv takes over. Both serve an identical
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
- **The network-level gate is the authoritative control, NOT the app ACL.** `recursionNetworkACL` alone does
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
  CNAME, so internal + public agree) must be **A records on EVERY Technitium instance**. These are explicit
  records, never lease-derived ones, and the VIP is **not** a lease — without them the traefik-ha /
  oldsrv edges are unreachable by name.
- **`modem.kogler.si` is NOT a universal record** — the Comtrend UI is LAN/router-only and must never
  resolve from the VPS/internet; the seed loop skips the `modem` row on the VPS primary via a `when`-gate.
- **A route that is deployed, converged and healthy but has no A record** is invisible to every check that
  looks at containers — the failure is `NXDOMAIN`, which looks like a client problem. Two record classes sit
  behind that rule:
  * `cockpit-oldsrv.kogler.si` / `cockpit-nas.kogler.si` → each host's **Home-VLAN address (per SSOT)**,
    carried in `zone_kogler_si` with `lan_only: true`, beside the `cockpit` role's file-provider routes. They join the `modem`/`spark` **LAN-only** class (seed skips them on the VPS
    primary): a Home address answered to a travelling peer is a black hole, and `check_dns_seed_drift.py`
    holds that class in its `LAN_ONLY` contract so the two lists cannot drift apart.
  * `pi-oldsrv.ts.kogler.si` is seeded **nowhere**, and that is the record. It lives in
    `tailnet_ts_only_subdomains`, which headscale renders as a **single MagicDNS A record** pointing at
    oldsrv's own tailnet node; `traefik-internal`'s `websecure-ts` listener answers it and proxies to the
    seat on loopback ([services-ai.md](services-ai.md) §9b-1). No plain `pi-oldsrv.kogler.si` exists in any
    zone (the `ha`/`spark` reasoning: MagicDNS answers extra_records client-side, so a plain name is
    a second door nobody asked for), so `dig pi-oldsrv.kogler.si` returning nothing is the design working.
  Verify with the control name in the same call — `dig +short llitellm.kogler.si` resolves, so an empty
  answer for one of these means the record, not the resolver.

- **Tailnet admin dashboards:** the plain `*.kogler.si` admin names (`stats`, `logs`,
  `csui`, `traefik`, `auto`) are **A records on every instance → the
  `tailnet_sidecar_ip`** (the `vps-obs` tailnet IP, `group_vars/vps.yml` = the traefik-tailnet edge). The
  value is a **tailnet IP**, so ONLY tailnet clients can reach it — LAN-only clients resolve it but fail to
  connect, which is correct. Headscale `dns.extra_records` mirrors them into both namespaces and
  `dns.nameservers` puts the **MagicDNS loop first**, so a tailnet device resolves `*.kogler.si`
  + `*.ts.kogler.si` on any network; the Technitium A records remain for non-tailnet clients + parity.
- **Control-plane records:** the seed loop also carries
  `vpn.kogler.si` / `home.kogler.si` / `dns.kogler.si` → the right split-horizon targets (VPS public IP for
  the control plane / home login) on **every** instance. ·
  [roles/router/tasks/main.yml](../IaC/ansible/roles/router/tasks/main.yml) (dhcp dns-server chain) ·
  [technitium-seed.yml](../IaC/ansible/roles/docker_services/tasks/technitium-seed.yml)
- ***arr stack (every instance → oldsrv Traefik edge):** `seerr`, `sonarr`, `radarr`, `lidarr`, `prowlarr`,
  `bazarr`, `sab`, `torrent`, `media`, `profilarr` (all `*.kogler.si`). Recyclarr has no hostname
  (scheduled worker, no UI). All are **internal-only** — no public (Cloudflare) record, WAN-blocked
  (see `services.md`).

---

## Single Namespace & Split-Horizon

Everything uses one namespace **`kogler.si`** (DHCP option 15 — see [network-vlans.md](network-vlans.md) §DHCP for how it is actually delivered, hosts, services).

⚠ **One namespace is not one answer set.** A name has to be *seeded* to be answered: the LAN view carries
service names and the host names `nas` / `oldsrv` / `pi` / `router`, and anything not seeded is answered by a
broadcast fallback rather than by DNS. §Local Name Resolution records what the
zone answers today.

- **Local (Technitium):** authoritative for `*.kogler.si` internally — resolves hosts/services to internal IPs; the answer set is what `zone_kogler_si` seeds, not DHCP-lease auto-creation (see §Local Name Resolution & mDNS).
- **Public (Cloudflare):** publishes **only** the internet-facing subset — the human-readable mirror is [`services.md`](services.md) §Domain & Subdomain Plan (`kogler.si` root + `home`, `sso`, `dns`, `foto`, `file`, `office`, `ai`, `git`, `ha`, `vpn`, `matrix`, `chat`). Cloudflare is **DNS-only** (no proxy) — real client IPs reach Traefik.
  **Public-record SSOT method:** publish records **incrementally** — one `*.kogler.si` record added to `cloudflare_dns/vars/main.yml` as each service lands on the VPS edge (gate: applies go LIVE on Cloudflare), and keep `docs/services.md` §Domain & Subdomain Plan as the human-readable mirror re-rendered as the list grows. The live Cloudflare zone + `cloudflare_dns/vars/main.yml` are dual SSOTs — never hand-edit the live zone without the file (and vice-versa).
  **`dns` is the ONE admin-surface exception**: `dns.kogler.si` → `vps.kogler.si` is the public bootstrap path to the VPS DNS admin — needed to reach the UI and to recreate the VPS admin — even though the UI itself sits behind Authentik Forward-Auth.
- **Internal-only services/hosts** (`stats`, `auto`, `logs`, `cockpit-*`, `router`, `switch`, `nas`, `oldsrv`) have **no public record**; the WAN firewall blocks them (defense in depth). The **observability admin dashboards** (`stats`/`traefik`/`logs`/`csui`/`auto`) are **tailnet-only**: their public CNAMEs are absent from the IaC SSOT (`cloudflare_dns/vars/main.yml`) and ⏳ must be **deleted from the live Cloudflare zone** by the owner (deploy-gated — the Ansible role only ensures `state: present`, it never deletes live records). On the tailnet they resolve via **headscale MagicDNS** (see [`network-vpn.md`](network-vpn.md) §Tailnet-exposed services); Technitium carries no record for them for non-tailnet clients, which cannot route to the VPS tailnet IP anyway.
- **TLS:** a single wildcard `*.kogler.si` certificate, issued via ACME **DNS-01** with a Cloudflare API token (1Password `Homelab-ansible`) — covers internal and public hostnames alike.

### A / AAAA policy

- **Public (Cloudflare, DNS-only):** publish **A + AAAA** for the internet-facing set — same list as the mirror in [`services.md`](services.md) §Domain & Subdomain Plan. ⚠ **The "static /56" premise is weaker than it reads:** the home prefix arrives as a **DHCPv6-PD lease** (`2a00:ee2:2700:8f00::/56`, ~15 min lease, renewing) that has not changed in years — same value, but it is *leased*, so any AAAA pointing into it must survive a re-delegation (which is why the router takes its own address from the pool instead of hardcoding the prefix: [network-vlans.md](network-vlans.md) §IPv6). Assign oldsrv a **fixed global IPv6** from the /56 for its AAAA — which today it does **not** have: its Home NIC uses stable-privacy + temporary addresses, so nothing there is assignable (that host-side change is `roles/network`, and it is the missing prerequisite in the one-host IPv6 firewall exception).
- **Manually or via Ansible:** the public record list is the SSOT in `IaC/ansible/roles/cloudflare_dns/vars/main.yml`, applied by `playbooks/dns.yml` (control node, `community.dns.cloudflare_dns`, token `cloudflare_api` in 1Password `Homelab-ansible`; **IP-filtered to the home WAN address — run from the home control plane only**). Records for the VPS public edge (`vps` → the VPS public A/AAAA) are already listed; add each `*.kogler.si` service there as it moves onto the VPS.
- **Matrix delegation (public):** the homeserver name is `kogler.si`, delegated to `matrix.kogler.si` — publish `_matrix._tcp` SRV (`matrix.kogler.si 443`) and serve `_matrix/client` + `_matrix/server` well-known on `kogler.si` and `matrix.kogler.si` (Caddy/Traefik static host or an intermediate). Required for clean `@user:kogler.si` IDs and federation (see [`services-matrix.md`](services-matrix.md)).
- **Internal (Technitium):** serve **A (IPv4)** for all hosts/services — primary, deterministic, matches the static VLAN/IPv4 plan and the IPv4 inter-VLAN firewall.
- **Internal AAAA: rejected for now.** It needs stable per-host global addressing **and** mirroring inter-VLAN isolation in the IPv6 firewall. IPv6 is live on the Home VLAN and the rejection still stands, on the first reason: isolation is mirrored for real (v6 filter + no prefix on 20/30/40/50/99, [network-vlans.md](network-vlans.md) §IPv6), but stable per-host addressing is **more** clearly missing than the second reason suggests — oldsrv's Home NIC runs `addr_gen_mode=1` (RFC 7217) with `use_tempaddr=2`, so the only addresses a home host gets are a hashed stable-privacy GUA plus rotating temporaries. Nothing name-able, no AAAA. Revisit only with a concrete requirement **and** pinned host addresses (`IPv6Token=` / static assignment in `roles/network`). Decision log: [network-rejected.md](network-rejected.md).

---

## The resolution requirement

`*.kogler.si` **must** resolve in three situations, and this is the acceptance test for any change to a resolver, a
nameserver list or the tailnet `nameservers` chain:

1. **On the LAN** — any VLAN client, via the per-subnet Technitium policy above.
2. **Away from home** — a tailnet device reaching the split-horizon zone.
3. **At home with the WAN down** — a tailnet device at home still resolving the zone.

Case **(d)** — away while the **home** WAN is down — has no answer by physics, and it is accepted
explicitly: a clean "the zone is down" over a half-resolving zone that returns addresses for services
that cannot answer.

**The physics that decides the design** (and why "just trim the unreachable resolvers" is wrong): with the home WAN
down, nothing off-site is reachable from inside — *the VPS included* — so case 3 can only ever be served by
something on the LAN. And with the home WAN down, an away device has no path to a home resolver either. So a
resolver list sorted by "where the device usually is" cannot win: the answer is one resolver that is reachable from
**wherever the device is**.

**The decided design:**

- **oldsrv's own tailnet node address** is named as a tailnet nameserver — Technitium on oldsrv binds it. At home it
  stays reachable **direct over the LAN even with the WAN pulled**; away it is reachable whenever the home link is
  up. One entry, both places.
- The **VPS public** instance is the **second** entry, so a dead node never costs away-side resolution — the
  public half of the zone (`auth.`, the VPS edge) lives in the same split-horizon set.
- The two **LAN-address** entries (oldsrv LAN, Pi LAN) are absent: they are unreachable off-site — the whole
  `DNS unavailable` wart — and their survival job is taken over by the node address.
- LAN clients are untouched — they get the LAN resolvers from DHCP.

**⚠ Verify, do not assume, before converging** (guessed control-plane syntax is the failure class here): that
headscale in the pinned version accepts a **node address** as a nameserver; that Technitium binds the tailnet
interface; and above all that a phone at home really does reach the node **direct-over-LAN with the WAN pulled** —
that one property is the entire design, so the acceptance test is the three-case drill (LAN / cellular / home with
the WAN pulled), not a `dig` from the laptop. Decision log: [network-rejected.md](network-rejected.md).

⏳ **Three properties of the live boxes gate this design — they shape it as written
above, so do not re-derive them:**

1. **Technitium already binds the node address.** Live oldsrv Technitium listens on `0.0.0.0:53`
   + `[::]:53`, which already covers the node address (SSOT `tailnet_oldsrv_ip`). `InterfaceListeners` would buy nothing here —
   it is not the blocker, so do not open it looking for this.
2. **The gate is the headscale ACL, not the bind.** A tailnet node's udp/53 must be granted explicitly: with a
   `tag:dev` accept rule naming **`tcp 443` only**, a node's udp/53 is dropped by the net pol whatever listens.
   Shipping the nameserver entry alone produces a *worse* failure than not shipping it: the broken entry enters
   the tailnet search path and the "resolver error: server misbehaving → fall through to the next server"
   behaviour gets absorbed by the tailscale domain. So a resolver entry is always a **policy widening**
   (`udp 53` to that one node IP, and the same question for every node that will ever be named) plus a
   control-plane change — never a template tweak. ⛔ Landing it is a headscale
   stop/start, and every tailnet device reconnects.
3. **What actually needs a resolver is narrower than the chain assumes.** MagicDNS
   (`100.100.100.100`, first in the chain) answers the **tailnet dashboard set** — `stats`/`logs`/
   `csui`/`traefik`/`auto` in both namespaces — **client-side on any network**, because those are
   `extra_records` in `config.yaml.j2`. The **home-hosted app names** (`media`, `seerr`, the *arr set, downloads)
   are **not** `extra_records`, so they still need a reachable resolver: away that is the VPS Technitium
   (`dns_primary_ip`), and at home with the WAN pulled it is the **oldsrv entry**. So case (c) does not get
   easier from MagicDNS, and the node address must be proven in exactly that scenario. Nothing on the router
   routes the tailnet range into `wg-s2s`, so a tailnet-served RA reaching home resolution with the home WAN
   down would need router work too — that is the leg the three-case drill has never exercised.

✅ **Live — the chain ships; the drill is what remains.** The converged headscale config serves
`nameservers: [100.100.100.100, tailnet_oldsrv_ip, dns_primary_ip]` and the net policy carries the
`udp:`-scoped `udp 53` rule to `{{ tailnet_oldsrv_ip }}/32`; both halves render from the same
`tailnet_oldsrv_ip` condition, so a nameserver entry can never ship without its grant (and an unset node
address drops the entry rather than rendering `""`, because a DNS list must never be able to stop the
control plane it describes). The grant is DNS-only: the rest of the tailnet-boundary invariant (no LAN bridge,
no advertised routes, no exit node, no Tailscale SSH) stands. What the live reads say, ordered by what it costs
to re-derive:

* **The node-address resolver answers over the tailnet.** `dig @<tailnet_oldsrv_ip> media.kogler.si` from a
  tailnet node returns the home answer. On `oldsrv` the
  query arrives on `tailscale0`, is DNATed to the Technitium container and the reply leaves on `tailscale0`
  again: `ts-forward`'s mark-accept and oif-accept counters move together while the
  tailscale anti-loop drop (`ip saddr <the tailnet range> oifname tailscale0 drop`) counter **stays at 0** — at the FORWARD hook the container
  reply is still sourced from the *container* address (the DNAT undo happens later, in POSTROUTING), so
  tailscale's anti-loop drop never sees a tailnet source. That is why hosting a published container on a node's
  own tailnet address needs no `roles/network` exception.
* **The grant is DNS-only.** udp/53 answers; **tcp/53 times out** (a truncated answer would therefore
  fail — the answers here are small A records, and widening it is a separate owner call); tcp/8443 stays
  blocked; the `tag:dev:443` rule is untouched.
* **The VPS fallback is a *view*, not a copy of the zone.** From an away source the VPS primary answers the
  control-plane/edge set (`sso`, `vpn`, `ha`, the apex) and **NXDOMAIN for the home-hosted media family**
  (`media`, `seerr`, the *arr set), while the same instance answers those names for an internal source. Away
  from home the VPS entry therefore serves only the public/edge half:
  **for the media family the node entry is the only resolver that answers away from home at all.**
  That is the strongest argument for this design and exactly what case (b) of the drill must read.
* **`headscale configtest` does not validate `dns.nameservers` values** — a garbage address passes it
  silently (canary-proven). `headscale policy check` DOES parse `proto` (a garbage protocol fails naming
  `/acls/<n>/proto`), so it is the real gate for the policy half; the DNS list is gated by the post-converge
  dig, not by configtest.
* **The safety net must be asserted, not assumed.** `scripts/guarded-converge.sh` asserts arm-live before it is
  allowed to stop anything: an arm step run in a different command from the stop does not actually arm, and a
  stop without a live watchdog leaves the control plane down until someone runs `compose up`. The watchdog is
  proven by stopping the control plane, reading the self-recovery (~19s) and honouring a disarm mid-window.

⛔ **Open — the three-case drill** (procedure: [deployment-manual.md](../deployment-manual.md) §1.4e).
Case (c) is **not** "the phone on cellular": with the home WAN down the node has no public endpoint and DERP
is unreachable too, so the only thing that can work is the phone on **home Wi-Fi** reaching
`<tailnet_oldsrv_ip>` **direct over the LAN** while the tailnet runs on its cached netmap (the app warning
about the unreachable control plane is expected and is not the failure). Read the answer, not the page:
`ERR_NAME_NOT_RESOLVED` is a resolution failure, while connected-but-timed-out is the pre-existing property that
the internal zone returns **LAN** addresses no away device can route to. A laptop at home may instrument case
(c) but does not prove it.

> ⚠ **A delivered tailnet chain is *advisory* unless the domain is split to it.**
> `dns.override_local_dns: false` is deliberate (the tailnet must not become a DNS
> exit, and the nodes refuse a wildcard listener on `:53`), and its meaning is exactly Tailscale's wording —
> *"by default, your tailnet's devices use their local DNS settings for all queries."* So the chain is
> installed but consulted only for MagicDNS-local names and for domains named in `dns.nameservers.split`.
> With the tailnet connected, a Windows laptop resolves the internal zone from **its LAN resolver, not from the
> chain**, and a phone on cellular gets an authoritative NXDOMAIN for a name that has never existed outside the
> internal zone — oldsrv's `tailscale0` forward counter does not move, i.e. **the node is never asked**. The
> chain itself is sound and reachable: `dig`
> against the node's tailnet address answers the zone from off-site. What is missing is the zone being
> **addressed** to it, which is a `split` decision, not an ordering one — and splitting is declined
> ([network-rejected.md](network-rejected.md)), so nothing here may assume a client was told to use the chain.
> Two related reads, both load-bearing. (1) The **VPS** instance
> serves the media family only to sources it treats as internal — `NOERROR` with the VPS edge as the answer
> from the home WAN, `NXDOMAIN` from an away source, same instance, same name — so a co-equal VPS entry in
> the chain is not merely unhelpful away from home, it actively answers `NXDOMAIN` for names the node entry
> serves; a two-instance chain of *different views* is a race. (2) The **Pi** answers the internal zone from its
> own copy (`ha` → the VIP,
> `media` → oldsrv's LAN address, queried directly), which is why a dead oldsrv does not take home
> resolution down with it — the home DNS chain is not single-homed, whatever the VPN doc's one-liner implies.

## The answer-plane model

One namespace, three planes, and **the answer must be routable by the client that receives it.**
That single rule is what the reads above force out of the design: a tailnet
chain that resolves a name to an address the client cannot route to is not resolution, it is a
black hole with extra steps.

| plane | who answers | what the client gets | what it survives |
|---|---|---|---|
| **public** | Cloudflare | published names → the VPS edge | anything at home dying |
| **tailnet** | **the client's own netmap** (headscale `extra_records`, answered by MagicDNS locally) | pinned names → a **tailnet address** (VPS edge, oldsrv's node, later the Pi's node) | every home box dying, headscale dying, the WAN dying — resolution is cached on the device; only reachability varies |
| **LAN** | the Pi's Technitium (the tertiary instance) | internal answers: the VIP for `ha`, oldsrv's edge for the media family, the VPS for public names | oldsrv dying; **not** the Pi dying → fixed by the dual-resolver decision below |

**The rulings, each with the reason that holds it:**

1. **No split-DNS.** Splitting the zone to a tailnet resolver would
   answer `media` with a LAN address to a phone on cellular — correct, unreachable — would have **no
   fallback** (a split domain is never asked of the OS resolver), and would pin whole-zone resolution
   to one box. What is needed is *reachable answers*, which is what extra_records are.
2. **`dns.override_local_dns` stays `false`.** The tailnet does not become a DNS exit. The consequence
   is accepted knowingly: the delivered nameserver chain is advisory (as above), and nothing in
   this design depends on a client being forced to a resolver.
3. **Admin surfaces that are tailnet-only stay tailnet-only, and the LAN zone does not lie.**
   The zone currently answers `stats`, `logs` and `csui` to **LAN** clients
   with a tailnet address — unresolvable-by-design for a device without the tailnet, presented as a
   successful answer. The rule going forward, as a generator invariant: a name marked tailnet-only is
   **never seeded into the LAN-facing view**; a LAN client gets a clean `NXDOMAIN` ("not here") rather
   than a black hole. Publishing Dozzle / the CrowdSec UI on the public edge is declined — it puts
   container logs and the security console on the open internet.
4. **LAN DNS redundancy is implemented; the premise for raising it is false.**
   "The router advertises only the Pi, so a Pi outage ends home resolution" is **wrong**:
   live `/ip dhcp-server network` on the router shows **all six** DHCP networks advertising **three**
   resolvers, Home (the Home subnet) first-listed as Pi → VPS → oldsrv, the other VLANs VPS → oldsrv → Pi
   (RouterOS caps a network at three, which is why all three are used). That failover is in place, and
   no router change is needed. What the same reading
   **does** turn up is narrower and real: the per-VLAN *forcing* rules override those options, and each forces
   to a **single** target — IoT (`iot_subnet`, udp+tcp/53) is dst-nat'd to the **Pi tertiary only**
   (live-confirmed), the Kids VLAN and the kids' reserved MACs to the **VPS primary** (from the rendered
   template, not re-measured live). Those two are deliberate — query visibility on the Pi's log, filtering
   enforcement on the primary — but they mean **IoT devices lose DNS with the Pi** and kids' devices lose it
   with the VPS resolver, even though their DHCP options list three servers. Re-open trigger: an IoT or kids
   incident where DNS, not WAN, is the dead leg.
5. **`extra_records` move to the watched file** (`dns.extra_records_path`), so no record edit ever
   restarts the control plane again. Two hazards carried with it: `dns.extra_records` and
   `dns.extra_records_path` are **mutually exclusive** in the pinned version (both set → the process
   exits at startup), so the swap is atomic or it takes the control plane down; and a "container is
   Running" post-check is **not** liveness, because a fatal config leaves a crash-looping container
   reporting `running`. **Precondition:** the guarded-converge assert must carry a real probe before this swap is
   attempted; the swap itself is still ahead.
6. **The Pi joins the tailnet and HA's names get two A records** (Pi + oldsrv). Both boxes
   proxy to the VIP, so the answer follows HA in either direction. Flagged as **designed, not yet
   measured**: multi-A fall-over on a real client must be proven with a plug-pull before it is relied on.
7. **HA's one URL is the plain `ha.kogler.si`** — see [network-vpn.md](network-vpn.md) §Tailnet boundary.
   The `.ts` twin stays as a free alias.

⚠ **The two planes are disjoint — no single *forwarded* answer covers both**, and that decides the workstation
half of this refactor. From one box, one interface, both nameservers probed directly: MagicDNS
(`100.100.100.100`) answers the `.ts` `extra_records` — both `pi-oldsrv.ts.kogler.si` and
`cockpit-nas.ts.kogler.si` resolve to oldsrv's tailnet address — and **nothing** for the plain names, while
Technitium answers the plain names (→ oldsrv / vps / spark, addresses in
[network-addresses-generated.md](network-addresses-generated.md)) and **NXDOMAIN** for the whole
`*.ts.kogler.si` namespace (authority `kogler.si` SOA serial 45, negative TTL 900) — the public zone carries no `ts`
dlegation, so no forwarder anywhere can answer that plane. Three consequences, in dependency order: a forwarder-only
client can never resolve `.ts` (which is why the phone and the Windows side of a laptop work and a WSL seat does not
— same tailnet, same ACL, different resolver stack); a routing-domain split would buy that one plane by breaking the
other, and it is declined, so it stays declined; and the only sanctioned workstation-side remedy is
the **generated alias artifact** derived from `zone_kogler_si` below — never a hand-typed `hosts` entry,
and never an unversioned per-box resolver drop-in, which is a fourth source this refactor exists to delete.

### `zone_kogler_si` — the zone as one derived list

The zone's membership has three sources — the Technitium seed's inline record list, headscale's
`tailnet_subdomains` / `tailnet_ts_only_subdomains` lists, and the public Cloudflare set — plus a
**fourth** that exists as unversioned state on a workstation. The refactor deletes those lists by deriving
them. **The Technitium seed is derived; the other two still hand-author**, so those planes are doubled and the
parity gate holds.

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

✅ **In an unattended window, only the dry-diff runs** — render both remaining
consumers against `zone_kogler_si_render.py`, write the diff into the report as the artifact, converge
nothing. The two converges stay owner-present (they re-render live edge routing), and the
routes→`*_url` half is deliberately **not** bundled with them.

**The drift these validators exist to catch** — every row is a mismatch between the four sources:

| name | reality | class |
|---|---|---|
| `music` (navidrome, `enabled: true`) | resolves **nowhere** — not seeded, not public | service up, name absent |
| `sec` (metabase, `enabled: false`) | still resolves publicly **and** internally to the tailnet edge | name outlives the service |
| media family | the seed answers **oldsrv**; `network-addresses-generated.md` says the **NAS** | generated view vs source |
| `stats` / `logs` / `csui` | LAN clients are handed a **tailnet address** | decision 3 above |
| a workstation hosts file | pins `.ts` + short names to tailnet node addresses and cites `scripts/tailnet-hosts.txt` + `scripts/tailscale-dns-fix.ps1` — files that are **not in git**; the mechanism is rejected ([network-rejected.md](network-rejected.md) "hosts-file aliases as the answer mechanism"), and the shipped answer is `scripts/wsl-nat-resolv.ps1` | unversioned state with a citation that looks recorded |

The last row also costs an instrument: a hosts override sits **above** DNS on the one machine you would
otherwise debug on, so a wrong zone answer becomes invisible exactly where it would have been noticed.

**Derivation is partial.** The parity gate compares the derived views against a snapshot of the hand-authored
sources, so it can prove that the derivation changed no answer — it **cannot** prove that a name added to a
hand-authored source after the snapshot was taken reached the derived list; the diff of that change is where
such a name shows up. Re-derive the parity
fixture only as part of the consumer switch, never from the derived list itself
(`capture_zone_kogler_si_golden.py` refuses to). Where the answers are identical there is nothing to push, so
no converge is owed.

| plane | state | what is the source of truth today |
|---|---|---|
| Technitium seed | **derived** | `zone_kogler_si` — `loop: zone_kogler_si_seed_records`, gate `zone_kogler_si_lan_only` |
| MagicDNS + the tailnet router lists | still hand-authored | `group_vars/vps.yml` → `tailnet_subdomains` / `tailnet_ts_only_subdomains` |
| public Cloudflare set | still hand-authored | `roles/cloudflare_dns/vars/main.yml` → `cloudflare_dns_records` |

Two planes are therefore **doubled**, and while they are, `scripts/check_zone_kogler_si_parity.py`
(runs in `validate-all.sh`) is what keeps the halves answering the same thing: it diffs the derived
views against `scripts/testdata/zone_kogler_si_golden.json` — a snapshot of what the hand-authored
sources answered BEFORE the derivation — and refuses a dropped name, a re-pointed address, a
`.ts`-only name published in the plain namespace, a consumer answering nothing, or a golden field
silently dropped from a row. The two failure shapes it exists for: a `when` gate that compares
`item.name` against a var that resolved to the STRING repr of a list, which turns `in` into a substring test
and drops names from the VPS primary; and `check_dns_seed_drift.py`, which understands only literal inline
`loop:` lists and can report "OK: 43 records" while reading ZERO rows from a derived loop. A contract gate and
the thing it guards can be blind in the same way, at the same time.

⛔ So: do not write that a consumer reads this list until its `loop:` or template actually does. No
gate catches that sentence; the next NXDOMAIN does.

---

## MikroTik Firewall Rules for DNS

Technitium instances bind resolver addresses (VPS public IP primary, oldsrv secondary, Pi tertiary — values per
SSOT `dns_primary_ip`/`dns_secondary_ip`/`dns_tertiary_ip`). Clients on every other VLAN reach them via explicit
**forward** rules, plus the router's own resolver is open on UDP/TCP 53 (input) as a final fallback.

- Forward, above the inter-VLAN drop: from `in-interface-list=LAN` →
  `dst-address=<oldsrv IP>` **and** `<pi IP>` (per SSOT), UDP 53 (+ DoT 853). **The VPS
  primary is NOT a LAN forward target** — LAN clients reach it via the approved
  Home/Media/Guest/Mgmt→WAN egress to the VPS public IP; the VPS nftables
  source-allow (tailnet CGNAT + home WAN only) is the control.
- Input: `in-interface-list=LAN` UDP/TCP 53 → router `/ip dns` (final fallback), which itself
  forwards to the same Technitium chain first + 1.1.1.1/1.0.0.1 last
  (upstream mirror of the DHCP list).
- Global inter-VLAN drop rule sits **below** these exceptions.
- There is **no** "allow DNS on the Management VLAN" rule — Technitium is **not** on the
  Management VLAN (it is Home/VPS-based).

---

## Local Name Resolution & mDNS

- **Host names in the LAN zone.** `nas` / `oldsrv` / `pi` / `router` carry
  LAN A records (`internal: true`, `lan_only: true`, `tailnet: none` in `zone_kogler_si`) so a
  machine is reachable **by name over any link**.
  A host without such a record is not unreachable — Windows does not need DNS for `\\nas\media`: with no
  answer it falls through to **LLMNR/NetBIOS broadcast**, which a wired switch port delivers and a Wi-Fi
  client does not. The shape of that gap is a mount by IP that **works** and a mount by name that **does
  not**, with Samba itself healthy on both legs (`smbd` + `nmbd` active, an ARP entry for the wireless
  client, TCP 445 open both ways). A broadcast fallback that happens to work on one link is not name resolution,
  which is why the answer is the record plus the suffix (DHCP option 15,
  [network-vlans.md](network-vlans.md) §DHCP) and not a Wi-Fi setting.
  - ⛔ `switch` and `ilo` stay unpublished on purpose: their only address is Mgmt-99, which a Home
    client cannot route to — the answer-must-be-routable rule above. Publishing them would turn a
    clean `NXDOMAIN` into a black hole.
  - ⛔ No `hosts` entries as the mechanism (rejected — [network-rejected.md](network-rejected.md)
    "hosts-file aliases as the answer mechanism"), and no mDNS reflection across VLANs either
    (rejected, same file). Both would fix exactly this symptom and make every future read of the
    zone untrustworthy on the one machine you debug with.
- **DHCP lease integration: not present on this fleet.** Technitium does **not** query the RouterOS REST API
  for `/ip/dhcp-server/lease` and does not auto-create `*.kogler.si` records from it — no instance carries
  that integration, and no lease-derived records exist for any host name. The LAN answer set is exactly what
  `zone_kogler_si` seeds. If the
  integration is ever wanted, it is a decision against that list, not a box to tick.
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
   within the interval. The VPS `:53` publish stays source-restricted (nftables FORWARD gate) — a
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
