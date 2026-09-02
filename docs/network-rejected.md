---
title: Network — Rejected / Dropped Decision Log
role: log
domain: network
status: active
tags: [network, rejected, decision-log]
---
# Network — Rejected / Dropped

> **Role:** Append-only decision log — network tooling options the homelab evaluated and declined. Sorted by tool name. This log is the per-domain **decision-log SSOT**.
> **Links to:** `network.md`
> **Linked from:** `index.md`, `network.md`

> ⚠️ **Append-only.** Never edit or reorder an entry after it lands. A changed decision is a new appended entry (do not strike/replace). Each row: `| <tool> | <rejected|dropped|superseded> | <date> | <why + evidence link> |`.
> ⚠️ **Evidence = the owning doc + this decision log.** Dates are the decision dates in the owning doc / git-attribution dates (advisory).

## Decisions

| Tool | Status | Date | Why |
|------|--------|------|-----|
| mDNS reflection (RouterOS mDNS repeater / Avahi across VLANs) | rejected | 2026-08-23 | Cross-VLAN mDNS re-couples the broadcast domains the VLAN plan exists to separate; no integration needs it — cloud appliances (LG ThinQ / Bosch Home Connect) pair via vendor apps + cloud APIs with zero cross-VLAN rules ([smart-home.md](smart-home.md) §Cloud Appliances), local devices (Shelly Gen1 CoAP, KNX gateway, ESPHome) are added by static host/IP with DHCP reservations. Decision context HD-228. · [smart-home.md](smart-home.md), [network-vlans.md](network-vlans.md) |
| netplan | rejected | 2026-08-16 | Host network config-manager — Ubuntu-desktop default + extra python3/libnetplan translation layer; rejected in favor of native `systemd-networkd`. HD-56. · [network.md](network.md) |
| systemd-networkd (on RPi Pi) | superseded | 2026-09-01 | The 2026-08-16 netplan-rejection recorded `systemd-networkd` as the repo's config-manager, but the live Pi (Raspberry Pi OS / Debian trixie) ships **NetworkManager** (cloud-init `renderers/activators: netplan, network-manager`; NM 1.52.1 active; no systemd-networkd). Implementing the networkd unit as written would disable/fight NM and risk severing the remote session. **Pi host-side dual-home is therefore done via two NetworkManager keyfiles** (HD-311 refined 2026-09-02): `pi-eth0.nmconnection` = untagged Home on the parent (`ansible_host`, default via Home — single gateway, no `never-default`; DNS via `bootstrap_dns_servers`) + `pi-mgmt.nmconnection` = tagged Mgmt on the `eth0.99` sub-interface (`mgmt_ip`, never-default, route via the tagged leg). The Mgmt IP lives ONLY on the tagged sub-interface — the untagged parent cannot reach the Mgmt plane (ether10 pvid=10), and its stale connected route hijacked `mgmt_subnet` lookups away from the tagged leg (`router99` 'No route to host' live 2026-09-02, fixed + verified). desktop/VPS hosts keep systemd-networkd where that is their manager. HD-307/HD-311. · [network-vlans.md](network-vlans.md), [roles/network](…/IaC/ansible/roles/network/) |
| systemd-networkd (nas/oldsrv netd units) | accepted | 2026-09-02 | **nas + oldsrv (desktop/VPS class) use systemd-networkd** for static dual-home: physical `.network` (untagged Home 10 + default route), `.netdev` VLAN-99 tagged sub-interface, and its `.network` (Mgmt IP, connected-only). Rendered by the `network` role (HD-311). Pi remains the NetworkManager exception (2026-09-01 row). · [network-vlans.md](network-vlans.md), [roles/network](…/IaC/ansible/roles/network/) |

> **Not a network-domain decision:** services / deploy / storage / smart-home rejections live in their own `<domain>-rejected.md`. See [`services-rejected.md`](services-rejected.md), [`deployment-rejected.md`](deployment-rejected.md), [`storage-rejected.md`](storage-rejected.md), [`smart-home-rejected.md`](smart-home-rejected.md).
> **SSOT note:** this log is the decision-log SSOT for the network domain.