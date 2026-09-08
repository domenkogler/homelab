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

> **Status (2026-09-07):** VLAN segmentation below is **LIVE** (executed via HD-229/HD-285/HD-310/HD-312). Docs that historically implied the network was flat are stale — treat this doc's definitions as the live plan; `network-addresses-generated.md` is the SSOT for subnets/DHCP/SSIDs. HD-339's WiFi + KNX regressions were **fixed live 2026-09-07 + SSOT commits** (see note under Switch AP ports below); its only remaining owner item (rekuperator room-temp probe) is a device fault, not network config.

---

## VLAN Table

| VLAN ID | Name | Purpose |
|---------|------|---------|
| 1 | — | Blackhole (unused) |
| 10 | Home | Trusted family devices, phones, servers, HA |
| 20 | IoT | Smart-home (KNX, Shelly, ESP32-S3) + **cloud-IoT (Bosch/LG/HAP)** — cloud devices get WAN via per-MAC `iot-wan-allow` (HD-325), no internet for the rest |
| 30 | Guest | Internet-only, client isolation |
| 40 | Kids | Filtered DNS, restricted access, time-blocked 22:00–07:00 |
| 50 | Media | NVIDIA Shield, gaming consoles, smart TV |
| 99 | Management | Router, switch, AP management |

---

## CAPsMAN SSID-to-VLAN Mapping

> **LIVE (2026-09-03):** `Kogler` + `Kogler IOT` + **`Kogler guest`** broadcast (3-SSID per HD-312;
> IOT-WAN + Kids SSIDs DELETED live + from SSOT 2026-09-03; **VLAN 21 (IoT-Internet) DELETED 2026-09-04
> (HD-325)** — cloud-IoT joined VLAN 20 with per-MAC WAN egress; guest took VLAN 30, kids-control
> migrates to the firewall MAC-address-list per HD-312). Table below reflects the live state.

| CAPsMAN Config | VLAN ID | SSID | Band | Isolation / note |
|----------------|---------|------|------|------------------|
| `cfg-kogler` | 10 | Kogler | 2.4 + 5 | **none** — family sees each other; kids devices join here (kids controls = firewall MAC-address-list, NOT a VLAN) |
| `cfg-kogler-iot` | 20 | Kogler IOT | 2.4 only | **client-isolation yes** — IoT devices can't see each other; cloud-IoT (Bosch/LG/HAP) get WAN via `iot-wan-allow` per-MAC accepts (HD-325) |
| `cfg-kogler-guest` | 30 | Kogler guest | 5 only | **client-isolation yes** + firewall drop-to-LAN — internet-only |

> **3-SSID rationale (HD-312, 2026-09-03 — see [network-rejected.md](network-rejected.md) row):**
> the 2.4GHz band had 5 SSIDs = wasted airtime; all devices have static MACs in
> `network_static_hosts`, so per-MAC control (firewall MAC-address-lists + per-device
> `src-mac-address` forward rules) beats SSID-per-purpose. Kids merge into Kogler (same network). IoT + IoT-WAN
> merge into IOT (cloud-IoT permanent-WAN + firmware-window temporary WAN both via `iot-wan-allow`).
> Guest stays its own SSID (unknown clients can't be MAC-mapped).
> ⚠ **Per-MAC vlan-id caveat (2026-09-04):** the original rationale mentioned a CAPsMAN `access-list`
> `vlan-id` override — **that capability does NOT exist on wifi-qcom-ac** (802.11ac chipsets cannot do
> per-client vlan tagging, per the MikroTik WiFi wiki; the legacy `/interface wireless access-list`
> vlan-id does not apply to the modern stack). VLAN assignment on this fleet rides the **CAP bridge
> access-port pvid model** only; per-device network control = firewall MAC-lists (see
> [network-rejected.md](network-rejected.md) HD-312 2b row). **HD-325 (2026-09-04) drew the conclusion:**
> VLAN 21 (IoT-Internet) is DELETED — it was never reachable by wifi clients (no per-client VLAN), so
> `vlan: 21` rows moved to VLAN 20 with a per-device `wan_allow` flag (cloud-IoT egress).
>
> **Static-IP requirement (HD-312, 2026-09-03):** the per-MAC model + MAC-address-list firewall
> rules only work predictably if every controlled device's **IP is static** — each IoT/kids/cloud-IoT
> device gets a **static DHCP reservation** (MAC → IP) in `network_static_hosts` (SSOT), so the
> firewall MAC-lists (iot-wan-allow, kids-*) and the n8n firmware automation all reference a stable
> identity. Devices without a reservation are treated as untrusted (Guest-style).
>
> ✅ **PHASE 1 (static-IP sweep) DONE 2026-09-03** (SSOT + render; router-role/`converge.rsc` pick
> the rows up automatically — live-apply at the next router converge/cutover):
> - **Shelly fleet** — the 4× Shelly RGBW2 (VLAN 20, n8n firmware targets) now carry MAC +
>   static reservations in `network_static_hosts` (`shelly-rgbw2-{kuhinja,wc,orhideje,kopalnica}`),
>   plus the 4 family WiFi clients static on Home
>   (`tablet-valentina`, `phone-domen` A54, `phone-martina` A55, `tablet-ipad`)
>   for the kids-control MAC-list.
> - **UPS + iLO fixed:** their SSOT rows lacked a MAC → the router never bound them (dynamic lease
>   instead of their reserved SSOT addresses). MACs added (`00:20:85:C0:92:FA` /
>   `1C:98:EC:0E:0D:3A`) — they now bind their reserved addresses.
> - The reservation **is** the marker: a row with a `mac:` is a controlled device; no separate
>   `static_ip: true` flag needed (HD-312 decision).
> - ⏳ Live-apply is **router-converge-gated** (Phase 1.5 cutover / next `router.yml` converge);
>   devices hold their current dynamic address until the lease turns over after the reservation lands.
>
> ✅ **PHASE 3 (firewall MAC-address-lists) IA-C DONE 2026-09-03** (router role, deploy-gated —
> [todo.md HD-312](../todo.md) row): the router role now renders **one `src-mac-address` forward-accept per cloud-IoT device** (the `wan_allow: true` rows: 2× LG, 3× Bosch, HAP — exactly the devices who lost WAN when the IOT-WAN SSID was deleted 2026-09-03; pre-HD-325 these were the `vlan: 21` rows) above the IoT→WAN drop, restoring their internet. (NOTE live 2026-09-03: RouterOS `/ip firewall address-list` is IP/CIDR-only, so the per-MAC rule must be `src-mac-address` in the forward filter, NOT an address-list — the earlier MAC-address-list task was removed; HD-325 moved the list source from `vlan: 21` rows to the `wan_allow` flag.) The `kids-*` MAC-address-lists are **reserved** (sherds from the same SSOT: `kids-{role}` per controlled family device) but gated `when: false` — no firewall rules reference
> them yet (owner: define the kids device set). **HD-326 2026-09-04 — kids set DEFINED + iPad fixed-MAC decision:** the set = `tablet-valentina` + `tablet-ipad`, both static on Home/VLAN 10. The iPad currently uses an iOS **randomized "Private Wi-Fi Address"** (`F6:9B:E2:B9:26:F9` — locally-administered/randomized per-SSID). **Owner decision (2026-09-04): disable "Private Wi-Fi Address" on the iPad for the Kogler SSID** — this yields a fixed per-SSID MAC so the per-MAC controls + the static reservation are stable. ⏳ **Owner step (before implement):** disable the setting on the iPad; if the resulting fixed MAC differs from the SSOT `tablet-ipad` value, update the row (the reserved `F6:9B:E2:B9:26:F9` is the randomized value and would stop matching).
> ✅ **HD-326 FULLY LIVE + VERIFIED 2026-09-08 (owner iPad step done + live-apply):** the owner disabled Private Wi-Fi Address on the iPad → it now associates to **Kogler** on `cap-wifi2` with the **fixed MAC `F6:9B:E2:B9:26:F9`** (live wifi-reg) and its DHCP lease binds the **static reservation for `tablet-ipad`** (bound, not dynamic; IP per the `tablet-ipad` SSOT row in [network-addresses-generated.md](network-addresses-generated.md)). Applied via delta `rb4011_hd326_fix_delta.rsc` (routeros-apply-delta.sh): the HD-326 per-MAC bedtime WAN drops + DoT-bypass drops were **BELOW** the Home→WAN accept (shadowed — first-match-wins) and the cloud-IoT `iot-wan-allow` accepts were **BELOW** the IoT→WAN drop (blocked). Delta removed the duplicates + re-added everything ABOVE the WAN accepts, and added the missing `tablet-valentina` filtered-DNS NAT rows. **Live-verified:** HD-326 kids rules now above Home→WAN accept (ind 13-16); `iot-wan-allow` accepts above IoT→WAN drop (ind 21-26); NAT has 4 dst-nat rows (both kids × udp+tcp → Technitium primary); **cloud-IoT WAN regained — Bosch/HAP/LG established connections to AWS/Azure** (sources = the `wan_allow` SSOT rows' reserved IPs). **SSOT parity:** the full set + order landed in `rb4011_converge.rsc.j2` (2026-09-08, was missing all `src-mac-address` rules — a converge import would have silently dropped them); the delta is transient/folded. HD-326 row deleted from todo.md per CONVENTIONS §4(a); remaining tails = HD-312 (4) n8n workflow + time-gated observation (bedtime window, Kids-Group binding `dig` check).


- **Mode:** `local-forwarding=no` (data-path) — all traffic tunneled to the router for VLAN tagging
  (network-vlans.md's CAPsMAN section is the SSOT; per-SSID VLAN tagging rides the CAP's **bridge**
  pvid/tagged-uplink — wifi-qcom-ac does NOT support manager datapath vlan-id on the CAP, live-verified
  + fixed 2026-09-02).
- All APs wired, no mesh
- **Delivery (owner decision, 2026-08-24 / task 8):** steady-state CAPsMAN ships as a **rendered rsc**
  (`IaC/router/templates/capsman_steady-state.rsc.j2`) uploaded at the cutover — **not** ansible
  `api_modify`. MODERN `wifi-qcom-ac` fleet-wide (HD-232): VLAN tagging under the CAP's bridge
  (per-SSID pvid + tagged uplink on the AP — NOT manager datapath vlan-id, which wifi-qcom-ac CAPs
  reject with 'does not support assigning vlans'; live-verified + fixed 2026-09-02), WPA2-PSK
  passphrases from the active `wifi-kogler*` 1Password items at render. ap_initial.rsc.j2 uses modern
  `/interface wifi cap`.
- **Per-MAC VLAN / policy (HD-312 target):** per-device network control = **firewall MAC-address-lists**
  (`iot-wan-allow`, `kids-*`) rendered from `network_static_hosts` — see the 3-SSID rationale note above;
  a CAPsMAN `access-list` `vlan-id` per-MAC override is **NOT supported on wifi-qcom-ac** (802.11ac cannot
  do per-client vlan tagging — [network-rejected.md](network-rejected.md) HD-312 2b). VLAN assignment on
  this fleet rides the CAP bridge access-port pvid model (already live).
- **Band split (owner decision, 2026-09-03):** `Kogler IOT` is **2.4GHz-only**; `Kogler guest` is
  **5GHz-only** — provisioning is split by SSID band (`band: 5` in `routeros_capsman_ssids` SSOT):
  2.4GHz carries Kogler + Kogler IOT, 5GHz carries Kogler + Kogler guest (IoT devices don't need
  5GHz; guests get the freed 5GHz radio).
- **5GHz non-DFS channel (2026-09-03 fix — 'phone won't connect to 5GHz'):** CAPsMAN auto-selected
  DFS channels (5500/5580) which many phones (esp. Samsung) can't associate with. 5GHz is now pinned
  to **channel 36 (5180, non-DFS)** via per-band master configs `cfg-kogler-24`/`cfg-kogler-5`
  (`channel.band=5ghz-ac channel.frequency=5180` on the 5GHz config; 2.4GHz has no pin so it never
  disturbs the IOT slaves — live-probed: a shared config with the pin broke them).
- **Switch AP ports (2026-09-03 live fix — 'phone disconnects' root cause):** APs do per-SSID VLAN
  tagging, so their CRS328 ports (ether11/12) MUST be **tagged members of the wifi VLANs (10 + 20)**
  in addition to the untagged 99 mgmt access. With access-99 only, the AP's tagged client frames
  (VLAN 10/20) were dropped at switch ingress → clients associated but never got DHCP → 'phone
  disconnects every few seconds'. Encoded in `wifi_ports` (group_vars/switch.yml) + the converge rsc.
  **⚠ REGRESSION hit again 2026-09-07 (HD-339):** the HD-338 converge rewrite dropped `ether11/12`
  from the SSID-VLAN tagged membership (only untagged-99 left) → same signature (all WiFi clients
  associate but no DHCP; Shellys unreachable over VLAN 20; KNX lagged on the shared VLAN-20 path).
  Fixed live (VLAN 10/20/30/40 `tagged=bridge,sfp-sfpplus1,ether11,ether12`) + **switch role gets a
  parity `api_modify` task** (`roles/switch/tasks/main.yml` HD-339) so the HD-338 edit-both-or-neither
  rule now covers the SSID-VLAN membership too. Verified: 4× Shelly ARP dynamic on `vlan20-iot` +
  Pi→Shelly HTTP 200 + phone/Shelly DHCP on renewal. **HD-339 CLOSED 2026-09-07** (owner confirmed the
  rekuperator room-temp −10°C is a physical ComfoConnect probe fault; no network action needed — see
  [home-assistant-current.md](home-assistant-current.md)).
  **Human-gated at cutover:** ① dnevna swap (spare hAP ac² → dnevna), ② garage replacement
  wifi-qcom-ac-capable. Validate-live TODOs are marked in the templates (fail-loud).

---

## Inter-VLAN Firewall Rules

**Default-deny** forwarding between VLANs. Specific exceptions:

| Source VLAN | Destination VLAN | Rule |
|-------------|-----------------|------|
| Home (10) | IoT (20) | Accept established/related + new from trusted IPs (MQTT/HA) · **KNXnet/IP udp/3671 → `knx-ip` (GIRA IP router)** — HA on the Pi tunnels to the KNX bus (HD-319 ✅ LIVE 2026-09-03, verified via router API + KNX integration loads real entities; the Pi is a node, not `trusted-admin`, so the KNX tunnel gets its own narrow new-UDP exception) · **Shelly Gen1 RGBW2 REST tcp/80 → IoT (20)** — HA on the Pi polls the Shelly HTTP API (same narrow pattern as the KNX exception; the Pi is a node, not `trusted-admin`) · **Shelly Gen1 CoIoT/CoAP client udp/5683 → IoT (20)** — HA's config flow + runtime `BlockDevice` opens a CoAP client session toward each device; without this forward new-UDP the “add by IP” flow aborted `cannot_connect` (HD-323 ✅ LIVE 2026-09-03; the reverse CoAP udp/5683 push to `trusted-ha` is the separate row below) · **Home→IoT new-connections gating = `trusted-ha` ONLY** (owner decision 2026-09-04, HD-03): `oldsrv` + `ha-vip` — **`nas` excluded** (narrower than the old `trusted-admin` scope) |
| Home (10) | Management (99) | Accept SSH/WinBox/API (22,8291,8728)/HTTPS from trusted Home servers (`trusted-admin`: nas/oldsrv/HA-VIP) — ~~80/443 UPS web UI~~ **removed (HD-338):** UPS NIC moved to IoT 20 no-WAN; NUT/USB only |
| Home (10) | Media (50) | Accept (remote control, casting) |
| IoT (20) | Home (10) | **Drop all** (only replies to Home-initiated) — EXCEPT CoAP **udp/5683 → `trusted-ha`** (Gen1 Shelly push, HD-229; **HA must be LISTENING on udp/5683** — the CoAP server lives inside the HA container and is published to the host/VIP via `5683:5683/udp` in the compose so the Shellys can actually reach it, HD-323) |
| IoT (20) | WAN | **Drop all** — EXCEPT cloud-IoT devices (2× LG, 3× Bosch, HAP — SSOT `wan_allow: true` rows; HD-312 phase 3 + HD-325) get a per-MAC `src-mac-address` accept above the drop; n8n firmware-window MACs ride the same per-MAC accepts temporarily (HD-312d) |
| Media (50) | Home (10) | Accept (media server, Plex/Jellyfin) |
| Management (99) | Home (10) | Accept (whole Mgmt VLAN — admin laptop / Pi discovery + provisioning, HD-307; owner decision 2026-09-01) |
| Guest (30) | any LAN | **Drop all** (internet only) |
| Kids (40) | Home (10) | Drop, DNS forced through filter |
| Kids (40) | WAN | Drop 22:00–07:00 (bedtime — hard block at firewall) |
| All (except IoT) | WAN | Allowed (masqueraded) |

Implemented with **address-lists** and **interface lists** in RouterOS.

> **Kids VLAN status (HD-179, decided 2026-08-21; impl = HD-182):** the three Kids controls above
> (bedtime block, forced filtered DNS, Kids→Home drop) are implemented in the router role. The
> **bedtime 22:00–07:00 `time=` drop is confirmed working on RouterOS 7** (verified live 2026-09-01;
> `invalid=true` when read outside the 22:00–07:00 window is RouterOS's normal out-of-window display,
> not a defect). ⏳ Still deploy-gated: the forced-DNS hijack and the Kids→Home drop live-verify.

> **Router INPUT chain (HD-78 / KOPS-003/009):** the rules above are the `forward` (inter-VLAN) policy.
> Separately, the router's **own** management service ports (`22,8728,8729,8291,80,443`) are gated by a
> `chain: input` firewall: reachable **only from the Management VLAN (99) and `trusted-admin` hosts**
> (nas/oldsrv/ha-vip), dropped from all other sources. See [`network-ops.md`](network-ops.md).

> **UPS / NUT note:** the NUT master (`nas`) and clients (`oldsrv`, `ha`) are all on VLAN 10 (Home), so **3493/tcp (NUT) is intra-VLAN — no inter-VLAN rule needed**. The UPS NIC is on **IoT VLAN 20 (no WAN)** — no consumer (NUT/USB only); the former Modbus TCP/web reach was RETIRED with the move (HD-338). See [`hardware-ups.md`](hardware-ups.md).

---

## DHCP

DHCP is handled entirely by the **RB4011 router** on each VLAN interface. This ensures devices always get IP leases even if the Debian PC is down.

DHCP option 15 (`domain=kogler.si`) is set on each DHCP network.

Static DHCP reservations (SSOT: `group_vars/all.yml` → `network_static_hosts`, applied by
`roles/router` + `rb4011_converge.rsc.j2`; live verification via the RouterOS API):

- **Pi** (`pi`): static on BOTH legs (dual-home, HD-307/HD-311) — Home VLAN on `dhcp-10` + Mgmt VLAN on
  `dhcp-mgmt`. Its SSOT rows (incl. the MAC + static IPs) live in
  [network-addresses-generated.md](network-addresses-generated.md); reservations applied live
  2026-08-31. A stale dynamic Mgmt lease (`.97`) was removed so the static reservation binds at
  the next renewal; host-side static dual-home implemented via the `network` role's **two NetworkManager
  keyfiles**: `pi-eth0.nmconnection` = **untagged Home** on the parent (`ansible_host`, default via Home) and
  `pi-mgmt.nmconnection` = **tagged Mgmt on `eth0.99`** (`mgmt_ip`, never-default) — the Mgmt IP lives
  ONLY on the tagged sub-interface (HD-311(b)), never on the untagged parent (its connected route
  hijacked `mgmt_subnet` lookups away from the tagged leg — `router99` 'No route to host' live 2026-09-02,
  fixed + verified; on 2026-09-08 the laptop direct-.99 path is the operative one (no Pi hop; aliases
  `router`/`switch`/`oldsrv` direct + `pi99` as the dual-leg exception). See [network-rejected.md](network-rejected.md) Pi-uses-NM.
- **Laptop** (`laptop-domen`, added 2026-09-01): static on `dhcp-mgmt` (was dynamic `.99.90`);
  SSOT row in [network-addresses-generated.md](network-addresses-generated.md);
- **APs** `ap-*` → `dhcp-mgmt`; other reserved devices → their VLAN's `dhcp-<id>`.

Reservations win over the pool at the next renewal (lease-time 30 min); a device keeps its
dynamic address until the lease turns over.

> **Port model (2026-09-01, final 2026-09-02): untagged = primary/access VLAN, tagged = secondary/admin (Mgmt 99).**
> A single untagged port carries ONE VLAN (untagged frames map to `pvid`), so dual-homed hosts
> (oldsrv, Pi, laptop) ride **Home (10) untagged + Mgmt (99) tagged** on the same port. The **laptop's Windows side is Home-untagged + Mgmt99 tagged** (Mgmt99 vNIC = static `laptop-domen` Mgmt IP, no default gw); **WSL Debian does NOT tag its own 99 leg** — WSL2's hyper-v vNIC can't carry tagged 99 (vNIC trunking impossible; mirrored = view-only, ARP FAIL), so **WSL reaches the Mgmt plane via the Windows host as gateway** (`laptop-domen` Home IP as next-hop, Windows IP forwarding ON; Debian `eth0` static `laptop-wsl` Home IP). **Direct-Mgmt on 2026-09-08 (replaces the ProxyJump-`pi` hop):** the Windows Mgmt99 vNIC + forwarding make `.99.x` reachable **directly** from the laptop/WSL — SSH aliases `router`/`switch`/`oldsrv`/`pi99` point straight at the Mgmt IPs, **no `ProxyJump pi`** (the hop aliases `pi99`-via-`pi`, `router99`, `oldsrv99`, `nas99` were removed + deduped; `pi` stays Home, `pi99` stays Mgmt as the one dual-leg exception). **Durable WSL runner state (2026-09-07): NAT + auto-resolv** — `scripts/wsl-nat-resolv.ps1` keeps Debian working on any network (wired/WiFi/hotspot) via `.wslconfig` → `networkingMode=Nat` + auto-generated `/etc/resolv.conf`; the bridged `wsl-vlan-trunk.ps1`/static-`10-eth0.network` route-through is now an **opt-in `-EnableMgmt99` extra for home only**. This is the defense-in-depth decision: **Home never reaches core infra (Mgmt VLAN) by default**; the Pi's `eth0.99` tagged leg + Windows' Mgmt99 are the mgmt-plane clients (`laptop-domen` `.80`, `laptop-wsl` routes via it). Supersedes the old "Mgmt-access + single-VLAN" model
> (dead Pi Home leg, HD-307/308) AND the temporary Home→Mgmt forward (reverted 2026-09-02). It does NOT change
> any IP — devices keep their `10.10.x`/`10.10.99.x` static reservations; it changes the L2 VLAN membership/tagging only.
>
> **Host-side dual-home was implemented 2026-09-02 (HD-311):** the `network` role now renders
> systemd-networkd units for **nas + oldsrv** (desktop/VPS class) — physical `.network`
> (untagged Home 10 + default route) + VLAN-99 tagged sub-interface (`.netdev` `eno1.99`) + its
> `.network` (Mgmt address, connected route only, no default). The Pi keeps the NetworkManager
> keyfile path (`pi-eth0.nmconnection`, HD-307). See [network-rejected.md](network-rejected.md)
> and `roles/network/`.

---

## Port Type Reference

| Device type | Port config | VLAN |
|-------------|------------|------|
| Family PC, laptop, server (dual-homed) | Access + tagged | **10 (Home) untagged** + 99 (Mgmt) tagged |
| Raspberry Pi (HA + DNS secondary) | Access + tagged | **10 (Home) untagged** + 99 (Mgmt) tagged |
| Shelly, KNX, ESP32-S3 | Access | 20 (IoT, no internet) |
| Homematic HAP (cloud), Bosch/LG appliances | Access | **20 (IoT) + `wan_allow`** — cloud devices on the IOT SSID get WAN via per-MAC `iot-wan-allow` accepts (HD-325; VLAN 21 deleted) |
| AP (hAP ac/ac²) | Access | 99 (Mgmt) |
| Printer | Access | 10 (Home) |
| Camera | Access | 20 (IoT) |
| Shield, console, smart TV | Access | 50 (Media) |
| UPS NIC | Access | 20 (IoT, no WAN) — NUT/USB only, **off Mgmt (HD-338)** |
| Laptop (admin, router ether3) | Access + tagged | **10 (Home) untagged** (Windows Home IP `laptop-domen` SSOT) + **99 (Mgmt) tagged on Windows Mgmt99 vNIC** (`laptop-domen` Mgmt IP, no gw); **WSL Debian does not tag 99 itself** — it routes the Mgmt subnet via Windows (Home IP, IP forwarding ON; Debian `eth0` static `laptop-wsl` Home IP). SSOT rows `laptop-domen`/`laptop-wsl` (2026-09-07) |
| Debian homelab PC (oldsrv) | Access + tagged | **10 (Home) untagged** + 99 (Mgmt) tagged |
| SFP+ uplinks | Trunk | 10,20,30,40,50,99 tagged |

> ✅ **Access-port untagged membership (HD-328, LIVE 2026-09-04)** — a CRS328 access port with `ingress-filtering` on the bridge only forwards frames for VLANs it is a **member** of; `pvid` alone is NOT enough. Every `switch_port_map` access port is therefore an **untagged member** of its role VLAN on the bridge (Media 50 → `untagged=ether14,ether20`; Home 10 → printer/nas; IoT 20 → KNX/camera/UPS-ether4; Mgmt 99 → APs ether11/12 only — UPS moved off Mgmt HD-338) — encoded in `crs328_converge.rsc.j2` + the switch role. Without this, the Shield/console on VLAN 50 had frames dropped at switch ingress → router never saw the MAC → empty ARP + no DHCP/WAN (live-found 2026-09-04, fixed + Shield online). The 2026-09-03 wifi fix added the APs as **tagged** members (wifi_ports); the access ports were the missing half.

> ✅ **AP wired-port lockdown (HD-89 / KOPS-046 + HD-304 Part 2, DONE + LIVE 2026-09-08):** a wired device plugged into an AP's *unused* ethernet port previously landed on the full Management VLAN (the AP bridge was untagged-99 on the switch; all 5 AP ether ports were bridged). Owner decision 2026-09-08: **disable the unused wired ports outright** — `ether2..ether5` are now `disabled=yes` + removed from the AP bridge (uplink `ether1` + radios `wifi1/wifi2` only) in `ap_initial.rsc.j2` (bootstrap) + the renderable `ap_lockdown_delta.rsc.j2` (running APs). **LIVE-APPLIED + VERIFIED 2026-09-08:** `ap_lockdown_delta.rsc` applied to both running APs via `routeros-apply-delta.sh` — ether2-5 disabled + INPUT firewall present on both, radios/WiFi unaffected. The AP also gained the **missing INPUT firewall** (established/related → bridge → DHCP → drop) — `available-from=` alone was the only guard; now the AP's mgmt services are gated to Mgmt VLAN + trusted-admin like the router/switch (HD-304 Part 2 parity). · [ap_initial.rsc.j2](IaC/router/templates/ap_initial.rsc.j2) · [ap_lockdown_delta.rsc.j2](IaC/router/templates/ap_lockdown_delta.rsc.j2)