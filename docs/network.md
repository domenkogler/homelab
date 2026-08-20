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
| APs | wAP ac (garaža), hAP ac² (spalnica), hAP ac (dnevna) + spare hAP ac² | CAPsMAN-managed, all wired (no mesh) |

---

## WAN / ISP

- **ISP:** Telekom Slovenije
- **Connection:** PPPoE on `ether1` (ONT: Comtrend GRG-4260us)
- **IPv4:** Static public IP with domain `kogler.si`
- **IPv6:** Fully enabled, `/56` prefix via PPPoE

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
  wAP ac + 2× hAP  (access ports) VLAN 10,20,50 tagged
                               VLAN 99 native (Mgmt)
```

- **oldsrv** uses single UTP (Intel i350-T2) to switch as VLAN trunk — all VLANs over one cable
- **nas** connects via access port (VLAN 10 Home, VLAN 99 native for Mgmt)

---

## Key Design Decisions

- Router does all inter-VLAN routing; switch is pure Layer-2
- Single VLAN-aware bridge on the router carries all traffic
- CAPsMAN in `local-forwarding=no` mode (all traffic tunneled to router)
- No mesh — all APs wired

> **Status:** the network is **currently flat (single Home-VLAN subnet)** — VLAN segmentation is **planned**. Subnets per [`network-addresses-generated.md`](network-addresses-generated.md) (SSOT).

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
