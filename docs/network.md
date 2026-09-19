---
title: Network Architecture
role: index
domain: network
status: active
tags: [network, topology]
---
# Network Architecture

> **Role:** Index — the network domain hub. Broad topology overview + links to each `network-*.md` stack doc.
> **Links to:** `network-vlans.md`, `network-dns.md`, `network-vpn.md`, `network-rack.md`, `network-rack-generated.md`, `network-ops.md`
> **Linked from:** `index.md`

---

## Hosts

| Host (FQDN) | Model | Role |
|-------------|-------|------|
| `router.kogler.si` | MikroTik RB4011iGS+ | PPPoE, VLAN routing, firewall, WireGuard server, CAPsMAN |
| `switch.kogler.si` | MikroTik CRS328-24P-4S+ | Layer-2 VLAN-aware, PoE for APs, trunk via SFP+ |
| APs | **wAP ac (garaža) = DEAD (hardware fault, needs replacement — ether1 reserved)**, hAP ac² (spalnica), hAP ac (dnevna) + spare hAP ac² | CAPsMAN-managed, all wired (no mesh) |

---

## WAN / ISP

- **ISP:** Telekom Slovenije
- **Connection:** PPPoE on `ether1` (ONT: Comtrend GRG-4260us)
- **IPv4:** Static public IP with domain `kogler.si`
- **IPv6:** Fully enabled, `/56` prefix via PPPoE

### Comtrend modem management path (HD-302)

> **✅ live** (HD-302) — laptop → modem web UI answers (401 auth page).

The Comtrend GRG-4260us is a consumer ONT in **PPPoE-bridge mode** — the RB4011
dials the PPPoE session on `ether1` via `pppoe-telekom`. The Comtrend's own
web UI lives on its LAN at the SSOT `comtrend_modem.modem_mgmt_ip` and is needed for the **twice-yearly
PPPoE-redial dance** (when the ISP-side session gets sticky and needs a manual
release). To avoid a physical cable swap every time:

- The RB4011 takes a **static `/24` on the modem's LAN** (SSOT:
  [`comtrend_modem.router_on_modem`](network-addresses-generated.md)) on `ether1`
  so the RB4011 can route to the modem's web UI. It must be a **`/24`, not a `/32`**:
  a `/32` gives no connected route to the modem subnet, so forwarded laptop traffic
  hits the PPPoE default instead of `ether1`
  ([network-rejected.md](network-rejected.md) `ether1` `/32` host route).
- A **srcnat masquerade** (SSOT: `comtrend_modem.modem_mgmt_ip`,
  `comtrend_modem.iface` — `out-interface=<iface> dst-address=<modem mgmt IP>
  protocol=tcp dst-port=80,443`) is REQUIRED: the consumer ONT only answers its
  web UI to its directly-connected LAN peer (the router's own modem-LAN
  address, SSOT `comtrend_modem.router_on_modem`) and silently ignores forwarded
  HTTP from deeper LAN subnets (the connection tracker shows `syn-sent` with 0
  reply packets). The router presents trusted-admin traffic to the modem as its
  own modem-LAN address.
- A **FORWARD rule** in the `router` Ansible role restricts access to
  `trusted-admin` hosts only (the laptop). All other homelab hosts get an
  explicit **default-deny** to the modem's subnet (SSOT:
  [`comtrend_modem.modem_subnet`](network-addresses-generated.md)).
- Private DNS record **`modem.kogler.si`** (SSOT:
  [`comtrend_modem.modem_mgmt_ip`](network-addresses-generated.md)) is ✅ live and lets
  the laptop browse the modem by name. The record must **never** go to Cloudflare —
  the modem is on a private RFC1918 subnet. In `technitium-seed.yml` it is seeded on the
  **home instances only** (Pi tertiary `secondary-pi` + oldsrv secondary `secondary`),
  gated OFF the VPS primary: it must never resolve from VPS/internet.

SSOT: `IaC/ansible/group_vars/router.yml` → `comtrend_modem`. The role is
idempotent and gated by `comtrend_modem.enabled: true` for opt-out per host.

---

## Physical Topology

```
Internet → ONT → router ether1 (WAN)
                    │
                    │ sfp-sfpplus1 (trunk)
                    ▼
              switch (CRS328-24P-4S+)
                    │
        ┌───────────┼───────────┐
        │           │           │
    APs (PoE)   Wired devices  oldsrv (trunk)
  2× hAP (access ports) VLAN 10,20,50 tagged
                       VLAN 99 native (Mgmt)
  (☠️ garage AP DEAD — hardware fault, ether1 reserved for replacement)
```

- **oldsrv** uses single UTP (Intel i350-T2) to switch as VLAN trunk — all VLANs over one cable; host-side dual-home (Home 10 untagged + Mgmt 99 tagged) via the `network` role's systemd-networkd units (HD-311)
- **nas** connects via access port (VLAN 10 Home, VLAN 99 tagged for Mgmt — dual-home via the same netd role units, HD-311)

---

## Key Design Decisions

- Router does all inter-VLAN routing; switch is pure Layer-2
- Single VLAN-aware bridge on the router carries all traffic
- CAPsMAN in `local-forwarding=no` mode (all traffic tunneled to router)
- No mesh — all APs wired

> **Status:** VLAN segmentation is **LIVE** — the network is no longer flat. VLAN definitions, subnets
> and firewall rules: [`network-vlans.md`](network-vlans.md); subnets/DHCP/SSIDs SSOT:
> [`network-addresses-generated.md`](network-addresses-generated.md).

---

## Document Map

| For | Read |
|-----|------|
| VLAN plan, subnets, firewall rules | [`network-vlans.md`](network-vlans.md) |
| DNS architecture, Technitium/Pi-hole | [`network-dns.md`](network-dns.md) |
| VPN layers, Headscale mesh | [`network-vpn.md`](network-vpn.md) |
| Device wiring & interconnections | [`assets/Network-Devices.canvas`](assets/Network-Devices.canvas) (Obsidian Canvas) ⚠️ WIP |
| Rack layout (18U cabinet, rooms) | [`network-rack.md`](network-rack.md) → `assets/Rack.canvas` |
| Rack wiring (port↔device, generated) | [`network-rack-generated.md`](network-rack-generated.md) |
| Router config storage & versioning | [`network-ops.md`](network-ops.md) |
| Monitoring / SNMP | [`observability.md`](observability.md) |

## Related

- [VLAN Plan](network-vlans.md)
- [DNS Architecture](network-dns.md)
- [VPN & Remote Access](network-vpn.md)
- [Rack Layout](network-rack.md) · [Rack Wiring](network-rack-generated.md)
- [Network Operations — Router Config Storage](network-ops.md)
- [Network Review Queue](network-review.md)
- [Network Rejected / Dropped (decision log)](network-rejected.md)
