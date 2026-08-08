# Network Addresses — SSOT

> **Source of truth:** IaC/ansible. Addresses are hand-edited only in
> `IaC/ansible/group_vars/all.yml` (`network_vlans`, `network_static_hosts`) and the
> host_vars; this page is a generated view. See also
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

## Service addresses (Home VLAN 10)

| Purpose | Address | Host |
|---------|---------|------|
| DNS primary (Technitium) | 10.10.1.30 | oldsrv |
| DNS secondary (Technitium) | 10.10.1.20 | pi |
| DNS secondary web UI (`dns-pi.kogler.si`) | VIP `10.10.1.200` (edge) → `10.10.1.20:5380` | pi |
| Home Assistant VIP (`ha.kogler.si`) | 10.10.1.200 | pi ↔ oldsrv (keepalived) |

> Non-HTTP services bypass Traefik: DNS 53 (above) · NUT 3493 (nas master, intra-Home)
> · UPS web 80/443 (10.10.99.9) · SNMP 161 (router/switch) · WireGuard · SSH/WinBox.
