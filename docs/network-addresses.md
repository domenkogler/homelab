# Ansible managed: file edited by Ansible
<!-- Network address plan — auto-generated from IaC/ansible/group_vars/all.yml. -->
<!-- Do NOT hand-edit. Change group_vars/all.yml and re-render. -->
<!-- Source of truth: IaC/ansible (group_vars/all.yml, host_vars) -->

# Network Addresses — SSOT

> **Source of truth:** IaC/ansible. Addresses are hand-edited only in
> `group_vars/all.yml` (`network_vlans`, `network_static_hosts`, `network_ranges`)
> and the host_vars; this page is a generated view. See also
> [`services.md`](services.md) for the Traefik URL / accessibility mapping.

## VLANs

| VLAN | Name | Subnet | DHCP pool | SSID |
|------|------|--------|-----------|------|
| 10 | Home | 10.10.1.0/24 | 10.10.1.100-10.10.1.199 | Kogler |
| 20 | IoT | 10.10.20.0/24 | 10.10.20.100-10.10.20.199 | Kogler IOT |
| 21 | IoT-Internet | 10.10.21.0/24 | 10.10.21.100-10.10.21.199 | Kogler IOT WAN |
| 30 | Guest | 10.10.30.0/24 | 10.10.30.100-10.10.30.199 | Kogler guest |
| 40 | Kids | 10.10.40.0/24 | 10.10.40.100-10.10.40.199 | Kogler Kids |
| 50 | Media | 10.10.50.0/24 | 10.10.50.100-10.10.50.199 |  |
| 99 | Management | 10.10.99.0/24 | 10.10.99.50-10.10.99.99 |  |

## Static hosts

| VLAN | IP | Host | Role |
|------|----|------|------|
| 99 | 10.10.99.1 | router | RB4011 gateway |
| 99 | 10.10.99.2 | switch | CRS328 mgmt |
| 99 | 10.10.99.3 | ap-garage | wAP ac (garaža) |
| 99 | 10.10.99.4 | ap-spalnica | hAP ac² (spalnica) |
| 99 | 10.10.99.5 | ap-dnevna | hAP ac (dnevna) |
| 99 | 10.10.99.6 | ap-spare | hAP ac² spare |
| 99 | 10.10.99.9 | ups | PowerWalker VFI 3000 IoT |
| 99 | 10.10.99.10 | nas | HP MicroServer Gen8 |
| 99 | 10.10.99.11 | ilo | nas iLO4 BMC |
| 99 | 10.10.99.20 | pi | RPi4 node + DNS secondary |
| 99 | 10.10.99.30 | oldsrv | i7-7700K node + DNS primary |
| 10 | 10.10.1.1 | router | Home gateway |
| 10 | 10.10.1.10 | nas | Cockpit/NFS/NUT master |
| 10 | 10.10.1.20 | pi | node + DNS secondary (VRRP anchor) |
| 10 | 10.10.1.30 | oldsrv | node + DNS primary (VRRP anchor) |
| 10 | 10.10.1.200 | ha-vip | keepalived VIP — ha.kogler.si |

## Infrastructure networks

| Name | CIDR | Purpose |
|------|------|---------|
| wireguard | 10.255.0.0/16 | WireGuard / tunnel family (S2S links, VPS networks) |
| wg-s2s | 10.255.40.0/30 | WireGuard S2S link — home RB4011 (.1) ↔ VPS (.2) |
| wg-vps-services | 10.255.20.0/24 | WireGuard — VPS services network |
| wg-vps-dmz | 10.255.10.0/24 | WireGuard — VPS DMZ |
| wg-vps-lab | 10.255.30.0/24 | WireGuard — VPS lab |
| headscale | 100.64.0.0/10 | Headscale overlay (CGNAT, Tailscale-compatible) |
| traefik-public | 172.20.0.0/16 | Docker bridge — Traefik edge ↔ exposed services |
| services-internal | 172.21.0.0/16 | Docker bridge — app ↔ app communication |
| db-internal | 172.22.0.0/16 | Docker bridge — databases (fully isolated) |
| site | 10.10.0.0/16 | Whole homelab site — all VLANs (10.10.x.0/24) |

## Service addresses (Home VLAN 10)

| Purpose | Address | Host |
|---------|---------|------|
| DNS primary (Technitium) | 10.10.1.30 | oldsrv |
| DNS secondary (Technitium) | 10.10.1.20 | pi |
| DNS secondary web UI (`dns-pi.kogler.si`) | VIP `10.10.1.200` (edge) → `10.10.1.20:5380` | pi |
| Home Assistant VIP (`ha.kogler.si`) | 10.10.1.200 | pi ↔ oldsrv (keepalived) |

> **VIP:** `10.10.1.200` is a single `/32` reserved for keepalived (ha.kogler.si). Home DHCP pool
> stays ≤ `10.10.1.199` — never extend it into the VIP or assign `10.10.1.200` statically.

> Non-HTTP services bypass Traefik: DNS 53 (above) · NUT 3493 (nas master, intra-Home)
> · UPS web 80/443 (`10.10.99.9`) · SNMP 161 (router/switch) · WireGuard · SSH/WinBox.

> Last generated: 2026-08-11T19:52:45+00:00
