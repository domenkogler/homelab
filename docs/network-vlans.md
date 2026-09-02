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

> **Status (planning):** the network is **currently flat (single Home-VLAN subnet)** — VLAN segmentation below is **planned**, not yet live. Docs that historically implied devices are already isolated are being corrected (see live DHCP notes in `network-dns.md`). Subnets, DHCP pools and SSIDs are SSOT data: see [`network-addresses-generated.md`](network-addresses-generated.md).

---

## VLAN Table

| VLAN ID | Name | Purpose |
|---------|------|---------|
| 1 | — | Blackhole (unused) |
| 10 | Home | Trusted family devices, phones, servers, HA |
| 20 | IoT | Smart-home (KNX, Shelly, ESP32-S3), no internet |
| 21 | IoT-Internet | Internet-needing IoT (HAP during cloud phase, Bosch appliances) |
| 30 | Guest | Internet-only, client isolation |
| 40 | Kids | Filtered DNS, restricted access, time-blocked 22:00–07:00 |
| 50 | Media | NVIDIA Shield, gaming consoles, smart TV |
| 99 | Management | Router, switch, AP management |

---

## CAPsMAN SSID-to-VLAN Mapping

| CAPsMAN Config | VLAN ID | SSID |
|----------------|---------|------|
| `cfg-kogler` | 10 | Kogler |
| `cfg-kogler-iot` | 20 | Kogler IOT |

> **Active SSIDs only (owner decision, 2026-09-02):** `Kogler` + `Kogler IOT` are the only two
> broadcast. `Kogler IOT WAN` (21), `Kogler guest` (30), `Kogler Kids` (40) are **disabled** — kept
> in the SSOT (`routeros_capsman_ssids`, commented out) + 1Password, ready to re-enable.

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
  passphrases from the active `wifi-kogler*` 1Password items at render (currently the two enabled
  SSIDs: wifi-kogler_password + wifi-kogler-iot_password). ap_initial.rsc.j2 uses modern
  `/interface wifi cap`.
  **Human-gated at cutover:** ① dnevna swap (spare hAP ac² → dnevna), ② garage replacement
  wifi-qcom-ac-capable. Validate-live TODOs are marked in the templates (fail-loud).

---

## Inter-VLAN Firewall Rules

**Default-deny** forwarding between VLANs. Specific exceptions:

| Source VLAN | Destination VLAN | Rule |
|-------------|-----------------|------|
| Home (10) | IoT (20) | Accept established/related + new from trusted IPs (MQTT/HA) |
| Home (10) | IoT-Internet (21) | Accept established/related + new from trusted IPs (HA→HAP, Prometheus→HA) |
| Home (10) | Management (99) | Accept SSH/WinBox/API (22,8291,8728)/HTTPS · **80/443 (UPS web UI)** from trusted Home servers (`trusted-admin`: nas/oldsrv/HA-VIP) |
| Home (10) | Media (50) | Accept (remote control, casting) |
| IoT (20) | Home (10) | **Drop all** (only replies to Home-initiated) — EXCEPT CoAP **udp/5683 → `trusted-ha`** (Gen1 Shelly push, HD-229) |
| IoT (20) | WAN | **Drop all** — disable rule manually for firmware updates |
| IoT-Internet (21) | WAN | **Allowed** (these devices need cloud/internet) |
| IoT-Internet (21) | Home (10) | **Drop all** (only replies to Home-initiated) |
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

> **UPS / NUT note:** the NUT master (`nas`) and clients (`oldsrv`, `ha`) are all on VLAN 10 (Home), so **3493/tcp (NUT) is intra-VLAN — no inter-VLAN rule needed**. The UPS itself is managed on VLAN 99 (Mgmt); only Modbus TCP (`502`) and web (`80/443`) are reachable from the monitoring hosts per the rule above (see [`hardware-ups.md`](hardware-ups.md)).

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
  fixed + verified). See [network-rejected.md](network-rejected.md) Pi-uses-NM.
- **Laptop** (`laptop-domen`, added 2026-09-01): static on `dhcp-mgmt` (was dynamic `.99.90`);
  SSOT row in [network-addresses-generated.md](network-addresses-generated.md);
- **APs** `ap-*` → `dhcp-mgmt`; other reserved devices → their VLAN's `dhcp-<id>`.

Reservations win over the pool at the next renewal (lease-time 30 min); a device keeps its
dynamic address until the lease turns over.

> **Port model (2026-09-01, final 2026-09-02): untagged = primary/access VLAN, tagged = secondary/admin (Mgmt 99).**
> A single untagged port carries ONE VLAN (untagged frames map to `pvid`), so dual-homed hosts
> (oldsrv, Pi) ride **Home (10) untagged + Mgmt (99) tagged** on the same port. The **laptop is Home-untagged ONLY**
> (mgmt reached via the Pi's tagged-99 hop — Windows never touches tagged 99). This is the strict,
> defense-in-depth decision: **Home never reaches core infra (Mgmt VLAN) by default**; the Pi's `eth0.99`
> tagged leg is the only real mgmt-plane client. Supersedes the old "Mgmt-access + single-VLAN" model
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
| Homematic HAP (cloud), Bosch IoT | Access | 21 (IoT-Internet) |
| LG ThinQ / Bosch Home Connect appliance | Access | 21 (IoT-Internet) |
| AP (hAP ac/ac²) | Access | 99 (Mgmt) |
| Printer | Access | 10 (Home) |
| Camera | Access | 20 (IoT) |
| Shield, console, smart TV | Access | 50 (Media) |
| UPS management | Access | 99 (Mgmt) |
| Laptop (admin, router ether3) | Access (Home only) | **10 (Home) untagged only** — mgmt via Pi tagged-99 hop (`~/.ssh/config` `pi99`/`router99` + `switch`/`ap-*`/`nas99` ProxyJump); static `laptop-domen` (2026-09-01, HD-307) |
| Debian homelab PC (oldsrv) | Access + tagged | **10 (Home) untagged** + 99 (Mgmt) tagged |
| SFP+ uplinks | Trunk | 10,20,30,40,50,99 tagged |