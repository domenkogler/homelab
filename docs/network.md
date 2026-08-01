# Network Architecture

> **Role:** Broad context — ISP, physical topology, overview.
> **Links to:** `network-vlans.md`, `network-dns.md`, `network-vpn.md`, `network-devices.md`, `network-rack.md`
> **Linked from:** `index.md`

---

## Hardware

| Device | Model | Role |
|--------|-------|------|
| Router | MikroTik RB4011iGS+ | PPPoE, VLAN routing, firewall, WireGuard server, CAPsMAN |
| Switch | MikroTik CRS328-24P-4S+ | Layer-2 VLAN-aware, PoE for APs, trunk via SFP+ |
| APs | hAP ac, hAP ac² (×2 + 1 spare) | CAPsMAN-managed, all wired (no mesh) |

---

## WAN / ISP

- **ISP:** Telekom Slovenije
- **Connection:** PPPoE on `ether1` (ONT: Comtrend GRG-4260us)
- **IPv4:** Static public IP with domain `vpn.kogler.si`
- **IPv6:** Fully enabled, `/56` prefix via PPPoE

---

## Physical Topology

```
Internet → ONT → RB4011 ether1 (WAN)
                    │
                    │ sfp-sfpplus1 (trunk)
                    ▼
              CRS328-24P-4S+ (switch)
                    │
        ┌───────────┼───────────┐
        │           │           │
    APs (PoE)   Wired devices  debhost (trunk)
    hAP ac ×3   (access ports) VLAN 10,20,50 tagged
                               VLAN 99 native (Mgmt)
```

- **debhost** uses single UTP (Intel i350-T2) to CRS328 as VLAN trunk — all VLANs over one cable
- **gen8** connects via access port (VLAN 10 Home, VLAN 99 native for Mgmt)

---

## Key Design Decisions

- Router does all inter-VLAN routing; switch is pure Layer-2
- Single VLAN-aware bridge on RB4011 carries all traffic
- CAPsMAN in `local-forwarding=no` mode (all traffic tunneled to router)
- No mesh — all APs wired

---

## Document Map

| For | Read |
|-----|------|
| VLAN plan, subnets, firewall rules | [`network-vlans.md`](network-vlans.md) |
| DNS architecture, Technitium/Pi-hole | [`network-dns.md`](network-dns.md) |
| VPN layers, Headscale, travel router | [`network-vpn.md`](network-vpn.md) |
| Port maps, device inventory | [`network-devices.md`](network-devices.md) |
| Rack layout | [`network-rack.md`](network-rack.md) → `assets/Rack.canvas` |

---

## Router Config Storage

- `rb4011_initial.rsc` — fresh-start baseline (`Iaac/router/rb4011_initial.rsc`)
- Current config exported as `rb4011_config.rsc` → stored in `Iaac/router/`
- All config changes via **Ansible** or version-controlled `.rsc` snippets
- Git-versioned in the homelab repo