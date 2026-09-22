---
title: VLAN Plan
role: detail
domain: network
status: active
tags: [network, vlan, firewall]
---
# VLAN Plan

> **Role:** Detail — VLAN definitions, subnets, firewall rules.
> **Links to:** `network-dns.md`, `network-addresses-generated.md`
> **Linked from:** `network.md`, `index.md`

> **Status:** the VLAN segmentation below is **LIVE** — this doc is the plan of record for VLANs, firewall
> and CAPsMAN. [`network-addresses-generated.md`](network-addresses-generated.md) is the SSOT for
> subnets / DHCP reservations / SSIDs. Anywhere another doc implies a flat network, that doc is stale.
> ✅ **HD-312 is CLOSED 2026-09-21** — every phase was live-verified 2026-09-08 and the last tail (the
> time-gated observation of the bedtime window + the Kids filtered-DNS binding) closed on the owner's
> sighting: at the observation hour **both kids tablets (`tablet-valentina` + iPad) had no internet**, which
> is the bedtime WAN block firing as designed. The filtered-DNS NAT was not separately eyeballed — it rides
> the same `kids-*` rule set and the same two MACs, and the tablets resolving nothing while blocked is
> consistent with it (re-open only if a kid device is ever seen bypassing the filter).
>
> ✅ **IPv6 is LIVE on the Home VLAN only (HD-414, 2026-09-22)** — see §IPv6 below. It closes the HD-405
> blocker ("the ISP delegates no /56"): it does. Every earlier claim in this repo that IPv6 is "not enabled
> anywhere on purpose" / "WAN-only" described a device state that had never been provisioned, not a decision
> that survives contact with the delegation — §IPv6 is the plan of record now.

---

## IPv6 — scoped dual-stack (Home VLAN only)

**The delegation is real and it is dynamic.** Measured on the live ISP: DHCPv6-PD over `pppoe-telekom`
delegates **`2a00:ee2:2700:8f00::/56`** (lease ~15 min, renewed; `prefix-hint` asks for the same /56 back).
The /56 has not changed in years, but it is *leased*, not static — so no row in the converge contains it.

**Allocation rules (SSOT: `network_ipv6` in `group_vars/all/main.yml`):**

| What | How | Why it is written this way |
|---|---|---|
| Router Home GWA | `/ipv6 address add address=::1/64 from-p=pd-wan6 advertise=yes` → `<delegated>::1/64` | the /64 is taken from the pool at runtime, so a re-delegation heals itself; no prefix literal to rot |
| The advertised prefix | **nothing configures it.** `advertise=yes` on that one address makes RouterOS create a *dynamic* `/ipv6 nd prefix` row (`2a00:ee2:2700:8f00::/64`, `on-link=yes autonomous=yes`, lifetime follows the lease) | `/ipv6 nd prefix` in 7.24 has no `from-pool`/`template`; the advertised-address mechanism is the one that tracks the delegation |
| No RA elsewhere | no other VLAN has an address with `advertise=yes` → nothing to advertise. The v6 forward chain also refuses egress from 20/30/40/50 and any origin from 99 | a `disabled=yes` `/ipv6 nd` row does **not** refuse RA — it falls back to the default `interface=all` row and advertises anyway (measured). Do not express "no RA here" that way |
| Clients | SLAAC (`managed-address-configuration=no`, `other-configuration=no`, **`advertise-dns=no`**) | DNS stays on the DHCP-provided Technitium chain ([network-dns.md](network-dns.md)); a v6 DNS in the RA would silently replace it |
| Hosts | no host carries an IaC-assigned GUA, and no internal AAAA exists (HD-36's reason still holds — see below) | |

**The filter.** IPv4 inbound safety is an accident of NAT; IPv6 has no NAT, so the filter *is* the
protection. `/ipv6 firewall filter` is first-match-wins (verified on this device: an exception placed
below the drop is never reached — the brief's "accept … then drop all" order is a bug, the accept goes
above), so both chains are rebuilt in this order and the converge keeps that order:

- `input`: `established,related` → ICMPv6 **1,2,3,4** (RFC 4890 errors; **2 = Packet Too Big = PMTUD**,
  the classic silent-v6 breakage when black-holed) → **133–136** (RS/RA/NS/NA — the ISP's RA is what
  carries the `::/0` route) → UDP **546** (a DHCPv6 exchange the *server* starts is `new`, not related) →
  **drop everything else from `pppoe-telekom`**.
- `forward`: `established,related` → ICMPv6 1–4 from the WAN (hosts must see PMTUD) → **drop everything
  else from the WAN** → drop egress from `vlan20/30/40/50` and from `vlan99-mgmt` (the v6 mirror of the
  v4 "these VLANs are IPv4-routed" and `drop-mgmt-origin` posture).
- **No inbound accept exists, by design.** The one exception the row anticipated (`udp 41641 →` oldsrv)
  was measured to be un-writable: oldsrv's Home NIC is `addr_gen_mode=1` (RFC 7217 stable-privacy) with
  `use_tempaddr=2`, so SLAAC gives it a hashed address plus rotating temporaries — there is no address to
  name. Writing the rule anyway would ship a listener opening that matches nothing. Tailscale does not
  need it for the common case: its hole punch makes the phone's packets *replies* to oldsrv's own first
  packet, and rule 1 admits those. Revisit only with the morning measurement in hand (HD-410) **and** a
  pinned host address (`roles/network`: `IPv6Token=` + no privacy extensions), which is a host-side
  decision this router section cannot make.

**Invariants:** (1) RA/SLAAC on VLAN 10 only — exactly one `advertise=yes` address device-wide; (2) DNS is
never advertised in an RA; (3) no inbound v6 accept exists without a written row naming the one host and
port; (4) `established,related` stays the first rule in both v6 chains; (5) any future v6 for another VLAN
must land its own inter-VLAN drops at the same time — today the isolation is structural (no prefix = no
route), and that stops being true the moment a second prefix is advertised.

**Rollback is two switches, and nothing else has to be undone:**
`/ipv6 nd set [find where interface=vlan10-home] disabled=yes` then
`/ipv6 address remove [find where comment~"^HD-414"]` — `ra-lifetime=30m`, so advertised addresses age out
on their own and the Home VLAN returns to IPv4-only. Runbook + how to verify: [network-ops.md](network-ops.md)
§IPv6 and the runbook steps in `deployment-manual.md` §1.5.3d.

**Re-checking the invariants** (all four measured clean on the live device 2026-09-22; the fourth is the one that
quietly regresses if someone adds a second advertised prefix):

```bash
ssh router '/ipv6 address print count-only where advertise=yes'              # 1  — RA on VLAN 10 only
ssh router '/ipv6 nd print count-only where !disabled and interface!="all"'  # 1  — the one vlan10-home row
ssh router '/ipv6 nd prefix print count-only'                                # 1  — the dynamic prefix row
ssh router '/ipv6 address print count-only where interface!="vlan10-home" and address!~"^fe80" \
                and interface!=lo and interface!=pppoe-telekom'              # 0  — no GUA on 20/30/40/50/99
# and from a Home host — no home name may carry AAAA yet (HD-36 stands):
dig +short <resolver> media.kogler.si AAAA                                   # empty
```

---

## VLAN Table

| VLAN ID | Name | Purpose |
|---------|------|---------|
| 1 | — | Blackhole (unused) |
| 10 | Home | Trusted family devices, phones, servers, HA |
| 20 | IoT | Smart-home (KNX, Shelly, ESP32-S3) + **cloud-IoT (Bosch/LG/HAP)** — cloud devices get WAN via per-device `wan_allow`, no internet for the rest |
| 30 | Guest | Internet-only, client isolation |
| 40 | Kids | Filtered DNS, restricted access, time-blocked 22:00–07:00 |
| 50 | Media | NVIDIA Shield, gaming consoles, smart TV |
| 99 | Management | Router, switch, AP management |

---

## CAPsMAN SSID-to-VLAN Mapping

> **Live SSID set (3 SSIDs):** `Kogler` + `Kogler IOT` + `Kogler guest`. The per-purpose SSID model
> (IOT-WAN, kids SSIDs) and the phantom **VLAN 21 (IoT-Internet)** are gone — decisions logged in
> [network-rejected.md](network-rejected.md) rows *per-purpose SSID per VLAN* and
> *VLAN 21 (IoT-Internet) as a Wi-Fi-reachable network*.

| CAPsMAN Config | VLAN ID | SSID | Band | Isolation / note |
|----------------|---------|------|------|------------------|
| `cfg-kogler` | 10 | Kogler | 2.4 + 5 | **none** — family sees each other; kids devices join here (kids controls = firewall MAC rules, NOT a VLAN) |
| `cfg-kogler-iot` | 20 | Kogler IOT | 2.4 only | **client-isolation yes** — IoT devices can't see each other; cloud-IoT (Bosch/LG/HAP) get WAN via per-device `wan_allow` accepts |
| `cfg-kogler-guest` | 30 | Kogler guest | 5 only | **client-isolation yes** + firewall drop-to-LAN — internet-only |

> **Per-device control model (HD-312/HD-325):** per-device network control = **firewall `src-mac-address`
> rules** rendered from `network_static_hosts` (`iot-wan-allow`, `kids-*`), *not* SSID-per-purpose and
> *not* per-client VLAN tagging.
> - **No per-MAC VLAN on this fleet.** `wifi-qcom-ac` (802.11ac) cannot do per-client VLAN tagging —
>   VLAN assignment rides the **CAP bridge access-port pvid model** only
>   ([network-rejected.md](network-rejected.md) HD-312 2b).
> - **Static IP is a precondition.** The per-MAC model works only if every controlled device's IP is
>   static: each IoT/kids/cloud-IoT device gets a **static DHCP reservation** (MAC → IP) in
>   `network_static_hosts`. A row with a `mac:` IS a controlled device — there is no separate
>   `static_ip: true` flag. Devices without a reservation are treated as untrusted (Guest-style).
> - **Kids device set** (`kids-*` rules): `tablet-valentina` + `tablet-ipad`, both static on Home/VLAN 10.
>   The iPad must keep a **fixed per-SSID MAC** — iOS "Private Wi-Fi Address" is disabled for the Kogler
>   SSID; if it is ever re-enabled the `tablet-ipad` SSOT MAC must be updated to the new value or the
>   per-MAC controls stop matching.
> - **No temporary WAN-toggle automation.** Cloud-IoT appliances hold **permanent** WAN through the
>   per-device `wan_allow: true` flag; firmware updates ride that standing egress. The `n8n` RouterOS API
>   user (`mikrotik-n8n_api`) stays provisioned for admin use, but no temp-toggle flow is authored
>   ([network-rejected.md](network-rejected.md) HD-312(4)).
> - **Reservation → live latency:** reservations win over the pool at the next renewal (lease-time
>   30 min); a device keeps its dynamic address until the lease turns over after the router converge.

- **Mode:** `local-forwarding=no` (data-path) — all traffic tunneled to the router for VLAN tagging.
  This section is the SSOT; per-SSID VLAN tagging rides the CAP's **bridge** pvid + tagged uplink —
  `wifi-qcom-ac` does not support manager datapath `vlan-id`
  ([network-rejected.md](network-rejected.md) CAPsMAN manager datapath vlan-id).
- All APs wired, no mesh.
- **Delivery:** steady-state CAPsMAN ships as a **rendered rsc**
  (`IaC/router/templates/capsman_steady-state.rsc.j2`) uploaded at the cutover — **not** ansible
  `api_modify`. Fleet-wide modern `wifi-qcom-ac` (HD-232): `ap_initial.rsc.j2` uses
  `/interface wifi cap`; WPA2-PSK passphrases come from the active `wifi-kogler*` 1Password items at render.
- **Per-MAC VLAN / policy:** see the model note above — `iot-wan-allow` + `kids-*` rules rendered from
  `network_static_hosts`.
- **Band split:** `Kogler IOT` is **2.4GHz-only**, `Kogler guest` is **5GHz-only** — provisioning is split
  by SSID band (`band: 5` in `routeros_capsman_ssids` SSOT). 2.4GHz carries Kogler + Kogler IOT, 5GHz
  carries Kogler + Kogler guest (IoT devices don't need 5GHz; guests get the freed 5GHz radio).
- **5GHz is pinned to a non-DFS channel: channel 36 (5180)** via per-band master configs
  `cfg-kogler-24` / `cfg-kogler-5` (`channel.band=5ghz-ac channel.frequency=5180` on the 5GHz config).
  DFS channels break association for many phones (esp. Samsung). The pin lives on the 5GHz config only —
  a shared config disturbs the IOT slaves ([network-rejected.md](network-rejected.md) DFS + shared master config).
- **Switch AP ports:** APs do per-SSID VLAN tagging, so their CRS328 ports (ether11/12) MUST be **tagged
  members of the wifi VLANs (10 + 20 + 30 + 40)** in addition to the untagged 99 mgmt access. With
  access-99 only, the APs' tagged client frames are dropped at switch ingress → clients associate but
  never get DHCP (symptom: devices disconnect every few seconds, Shellys unreachable on VLAN 20, KNX lag).
  Encoded in `wifi_ports` (`group_vars/switch.yml`) + the converge rsc, and guarded by the switch role's
  parity `api_modify` task (`roles/switch/tasks/main.yml`, HD-339) under the edit-both-or-neither rule —
  **this has regressed once via a converge rewrite; keep the parity task.**
  **Human-gated at cutover:** ① dnevna swap (spare hAP ac² → dnevna), ② garage replacement
  wifi-qcom-ac-capable AP. Validate-live TODOs are marked in the templates (fail-loud).

---

## Inter-VLAN Firewall Rules

**Default-deny** forwarding between VLANs. Specific exceptions:

| Source VLAN | Destination VLAN | Rule |
|-------------|-----------------|------|
| Home (10) | IoT (20) | Accept established/related + new from trusted IPs (MQTT/HA) · **KNXnet/IP udp/3671 → `knx-ip` (GIRA IP router)** — HA on the Pi tunnels to the KNX bus; the Pi is a node, not `trusted-admin`, so the KNX tunnel gets its own narrow new-UDP exception (✅ live) · **Shelly Gen1 RGBW2 REST tcp/80 → IoT (20)** — HA on the Pi polls the Shelly HTTP API (same narrow pattern as the KNX exception) · **Shelly Gen1 CoIoT/CoAP client udp/5683 → IoT (20)** — HA's config flow + runtime `BlockDevice` open a CoAP client session toward each device; without this new-UDP forward the "add by IP" flow aborts `cannot_connect` · the reverse CoAP udp/5683 push to `trusted-ha` is the separate row below · **Home→IoT new-connections gating = `trusted-ha` ONLY** (`oldsrv` + `ha-vip`; `nas` excluded) |
| Home (10) | Management (99) | Accept SSH/WinBox/API (22,8291,8728)/HTTPS from trusted Home servers (`trusted-admin`: nas/oldsrv/HA-VIP) — **no UPS web UI**: the UPS NIC is on IoT 20 with no WAN, NUT/USB only |
| Home (10) | Media (50) | Accept (remote control, casting) |
| IoT (20) | Home (10) | **Drop all** (only replies to Home-initiated) — EXCEPT CoAP **udp/5683 → `trusted-ha`** (Gen1 Shelly push; **HA must be LISTENING on udp/5683** — the CoAP server lives inside the HA container and is published to the host/VIP via `5683:5683/udp` in the compose so the Shellys can reach it) |
| IoT (20) | WAN | **Drop all** — EXCEPT cloud-IoT devices (2× LG, 3× Bosch, HAP — SSOT `wan_allow: true` rows) get a per-MAC `src-mac-address` accept **above** the drop |
| Media (50) | Home (10) | Accept (media server, Plex/Jellyfin) |
| Management (99) | Home (10) | Accept (whole Mgmt VLAN — admin laptop / Pi discovery + provisioning, HD-307) |
| Guest (30) | any LAN | **Drop all** (internet only) |
| Kids (40) | Home (10) | Drop, DNS forced through filter |
| Kids (40) | WAN | Drop 22:00–07:00 (bedtime — hard block at firewall) |
| All (except IoT) | WAN | Allowed (masqueraded) |

Implemented with **address-lists** and **interface lists** in RouterOS.

> **Rule-order invariants (RouterOS is first-match-wins):**
> - Cloud-IoT `iot-wan-allow` per-MAC accepts must sit **above** the IoT→WAN drop, or the devices have no WAN.
> - The `kids-*` bedtime WAN drops + DoT-bypass drops must sit **above** the Home→WAN accept, or they are shadowed.
> - Kids DNS rules must sit **below** the LAN→resolver accepts so Kids DNS keeps working; NAT forces
>   Kids `:53` → Technitium primary.
> - The full rule set + order of record lives in `rb4011_converge.rsc.j2` (apply-of-record). Any rule
>   added by a transient delta **must** be folded back into that template, or the next converge import
>   silently drops it.
> - The role's `Ensure inter-VLAN forward firewall rules` full-reconcile task stays gated off
>   (`when: false`): a live role run would delete the per-MAC rows that only the converge template carries.

> **Kids controls (HD-179/HD-182)** — bedtime block, forced filtered DNS, Kids→Home drop — are
> implemented in the router role and live. The bedtime `time=` drop works on RouterOS 7: reading the
> rule **outside** the 22:00–07:00 window shows `invalid=true`, which is RouterOS's normal
> out-of-window display, **not a defect**. **✅ Observed live 2026-09-21 (owner):** both kids tablets
> (`tablet-valentina`, `tablet-ipad`) had no internet at the observation hour — the bedtime WAN block is
> confirmed firing on the real client set, which was the last open tail of HD-312.

> **Router INPUT chain (HD-78):** the rules above are the `forward` (inter-VLAN) policy. Separately, the
> router's **own** management service ports (`22,8728,8729,8291,80,443`) are gated by a `chain: input`
> firewall: reachable **only from the Management VLAN (99) and `trusted-admin` hosts**
> (nas/oldsrv/ha-vip), dropped from all other sources. See [`network-ops.md`](network-ops.md).

> **UPS / NUT:** the NUT master (`nas`) and clients (`oldsrv`, `ha`) are all on VLAN 10 (Home), so
> **3493/tcp (NUT) is intra-VLAN — no inter-VLAN rule needed**. The UPS NIC is on **IoT VLAN 20
> (no WAN)** with no consumer (NUT/USB only). See [`hardware-ups.md`](hardware-ups.md).

---

## DHCP

DHCP is handled entirely by the **RB4011 router** on each VLAN interface. This ensures devices always get IP leases even if the Debian PC is down.

DHCP option 15 (`domain=kogler.si`) is set on each DHCP network.

Static DHCP reservations (SSOT: `group_vars/all.yml` → `network_static_hosts`, applied by
`roles/router` + `rb4011_converge.rsc.j2`; live verification via the RouterOS API):

- **Pi** (`pi`): static on BOTH legs (dual-home, HD-307/HD-311) — Home VLAN on `dhcp-10` + Mgmt VLAN on
  `dhcp-mgmt`. Its SSOT rows (incl. the MAC + static IPs) live in
  [network-addresses-generated.md](network-addresses-generated.md). Host-side static dual-home uses the
  `network` role's **two NetworkManager keyfiles**: `pi-eth0.nmconnection` = **untagged Home** on the
  parent (`ansible_host`, default via Home) and `pi-mgmt.nmconnection` = **tagged Mgmt on `eth0.99`**
  (`mgmt_ip`, never-default). The Mgmt IP lives ONLY on the tagged sub-interface — an address on the
  untagged parent hijacks `mgmt_subnet` lookups away from the tagged leg
  ([network-rejected.md](network-rejected.md) systemd-networkd on the Pi).
- **Laptop** (`laptop-domen`): static on `dhcp-mgmt`; SSOT row in
  [network-addresses-generated.md](network-addresses-generated.md).
- **UPS + iLO**: their SSOT rows must carry a `mac:` or the router never binds the reservation (the
  device silently falls back to a dynamic lease).
- **APs** `ap-*` → `dhcp-mgmt`; other reserved devices → their VLAN's `dhcp-<id>`.
- **Shelly fleet**: the 4× Shelly RGBW2 (VLAN 20) carry MAC + static reservations as
  `shelly-rgbw2-{kuhinja,wc,orhideje,kopalnica}`; the family WiFi clients that the kids controls match
  (`tablet-valentina`, `phone-domen`, `phone-martina`, `tablet-ipad`) are static on Home.

Reservations win over the pool at the next renewal (lease-time 30 min); a device keeps its
dynamic address until the lease turns over.

> **Port model: untagged = primary/access VLAN, tagged = secondary/admin (Mgmt 99).** A single untagged
> port carries ONE VLAN (untagged frames map to `pvid`), so dual-homed hosts (oldsrv, Pi, laptop) ride
> **Home (10) untagged + Mgmt (99) tagged** on the same port. This is the defense-in-depth rule:
> **Home never reaches core infra (Mgmt VLAN) by default.**
> - **Windows side of the laptop:** Home-untagged + Mgmt99 tagged (Mgmt99 vNIC = static `laptop-domen`
>   Mgmt IP, no default gateway).
> - **WSL Debian does NOT tag its own 99 leg** — the WSL2 hyper-v vNIC cannot carry tagged 99 (vNIC
>   trunking is impossible; mirrored mode is view-only, ARP FAIL), so WSL reaches the Mgmt plane via the
>   Windows host as gateway (`laptop-domen` Home IP as next-hop, Windows IP forwarding ON; Debian `eth0`
>   static `laptop-wsl` Home IP). Durable WSL runner state = **NAT + auto-resolv**
>   (`scripts/wsl-nat-resolv.ps1` + `.wslconfig` → `networkingMode=Nat`), which keeps Debian working on
>   any network; the bridged `wsl-vlan-trunk.ps1` / static-`10-eth0.network` route-through is an
>   **opt-in `-EnableMgmt99` extra for home only**
>   ([network-rejected.md](network-rejected.md) WSL bridged Mgmt99 route-through as default).
> - **Mgmt-plane clients:** the Pi's `eth0.99` tagged leg and the laptop's Windows Mgmt99 vNIC.
>   Off-LAN admin is a different path entirely (Home leg via the VPS jump) — see
>   [network-vpn.md](network-vpn.md).
> - The model changes L2 membership/tagging only — no IP changes; devices keep their `10.10.x` /
>   `10.10.99.x` static reservations.
> - **SSH alias names are NOT defined here** — the single alias SSOT is
>   [network-vpn.md](network-vpn.md) §The laptop alias contract.
>
> **Host-side dual-home for nas + oldsrv** (desktop/VPS class) is rendered by the `network` role as
> systemd-networkd units: physical `.network` (untagged Home 10 + default route) + VLAN-99 tagged
> sub-interface (`.netdev` `eno1.99`) + its `.network` (Mgmt address, connected route only, no default).
> The Pi keeps the NetworkManager keyfile path (`pi-eth0.nmconnection`, HD-307). See
> [network-rejected.md](network-rejected.md) and `roles/network/`.

---

## Port Type Reference

| Device type | Port config | VLAN |
|-------------|------------|------|
| Family PC, laptop, server (dual-homed) | Access + tagged | **10 (Home) untagged** + 99 (Mgmt) tagged |
| Raspberry Pi (HA + DNS secondary) | Access + tagged | **10 (Home) untagged** + 99 (Mgmt) tagged |
| Lenovo ThinkStation PGX (spark, router ether8) | Access + tagged | **10 (Home) untagged** + 99 (Mgmt) tagged — single NIC; wired direct on the RB4011 (1 Gb/s = accepted final: the RB4011 has no 10 G copper port, see [hardware-spark.md](hardware-spark.md) §Network / placement) |
| Shelly, KNX, ESP32-S3 | Access | 20 (IoT, no internet) |
| Homematic HAP (cloud), Bosch/LG appliances | Access | **20 (IoT) + `wan_allow`** — cloud devices on the IOT SSID get WAN via per-MAC `iot-wan-allow` accepts |
| AP (hAP ac/ac²) | Access | 99 (Mgmt) |
| Printer | Access | 10 (Home) |
| Camera | Access | 20 (IoT) |
| Shield, console, smart TV | Access | 50 (Media) |
| UPS NIC | Access | 20 (IoT, no WAN) — NUT/USB only |
| Laptop (admin, router ether3) | Access + tagged | **10 (Home) untagged** (Windows Home IP `laptop-domen` SSOT) + **99 (Mgmt) tagged on Windows Mgmt99 vNIC** (`laptop-domen` Mgmt IP, no gw); **WSL Debian does not tag 99 itself** — it routes the Mgmt subnet via Windows (Home IP, IP forwarding ON; Debian `eth0` static `laptop-wsl` Home IP). SSOT rows `laptop-domen`/`laptop-wsl` |
| Debian homelab PC (oldsrv) | Access + tagged | **10 (Home) untagged** + 99 (Mgmt) tagged |
| SFP+ uplinks | Trunk | 10,20,30,40,50,99 tagged |

> **Access-port untagged membership:** a CRS328 access port with `ingress-filtering` on the bridge only
> forwards frames for VLANs it is a **member** of — `pvid` alone is NOT enough. Every `switch_port_map`
> access port is therefore an **untagged member** of its role VLAN on the bridge (Media 50 →
> `untagged=ether14,ether20`; Home 10 → printer/nas; IoT 20 → KNX/camera/UPS-ether4; Mgmt 99 → APs
> ether11/12 only) — encoded in `crs328_converge.rsc.j2` + the switch role. Without it, frames are
> dropped at switch ingress → the router never learns the MAC → empty ARP and no DHCP/WAN.
> (HD-328; the APs' **tagged** membership is the other half — see §Switch AP ports.)

> **AP wired-port lockdown (HD-89 / HD-304 Part 2):** a wired device plugged into an AP's *unused*
> ethernet port must NOT land on the Management VLAN. `ether2..ether5` are `disabled=yes` and removed
> from the AP bridge (uplink `ether1` + radios `wifi1/wifi2` only) in `ap_initial.rsc.j2` (bootstrap) +
> the renderable `ap_lockdown_delta.rsc.j2` (running APs). The AP also carries its own **INPUT firewall**
> (established/related → bridge → DHCP → drop) gating mgmt services to Mgmt VLAN + `trusted-admin`, like
> the router and switch — `available-from=` alone is not a guard (HD-304 Part 2 parity).
> · [ap_initial.rsc.j2](IaC/router/templates/ap_initial.rsc.j2) · [ap_lockdown_delta.rsc.j2](IaC/router/templates/ap_lockdown_delta.rsc.j2)
