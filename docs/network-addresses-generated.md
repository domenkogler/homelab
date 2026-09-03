# Ansible managed
<!-- Network address plan — auto-generated from IaC/ansible/group_vars/all.yml. -->
<!-- Do NOT hand-edit. Change group_vars/all.yml and re-render. -->
<!-- Re-render (Windows / no Ansible):  python scripts/render_network_addresses.py -->
<!-- Re-render (Ansible / Linux / CI):   ansible-playbook IaC/ansible/playbooks/render-docs.yml -i IaC/ansible/inventory.ini -->
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
| 99 | 10.10.99.4 | ap-spalnica | hAP ac² (spalnica) |
| 99 | 10.10.99.5 | ap-dnevna | hAP ac² (dnevna) |
| 99 | 10.10.99.6 | ap-spare | hAP ac² spare |
| 99 | 10.10.99.9 | ups | PowerWalker VFI 3000 IoT |
| 99 | 10.10.99.10 | nas | HP MicroServer Gen8 |
| 99 | 10.10.99.11 | ilo | nas iLO4 BMC |
| 99 | 10.10.99.20 | pi | RPi4 node + DNS secondary |
| 99 | 10.10.99.30 | oldsrv | i7-7700K node + DNS primary |
| 99 | 10.10.99.80 | laptop-domen | Domen's laptop (admin, mgmt VLAN) — reaches mgmt via tagged-99 hop (Pi eth0.99), Home->Mgmt forward removed (strict) |
| 10 | 10.10.1.1 | router | Home gateway |
| 10 | 10.10.1.10 | nas | Cockpit/NFS/NUT master |
| 10 | 10.10.1.20 | pi | node + DNS secondary (VRRP anchor) |
| 10 | 10.10.1.30 | oldsrv | node + DNS primary (VRRP anchor) |
| 10 | 10.10.1.50 | homematic-ccu-pi | RaspberryMatic CCU — Pi primary (macvlan) — HD-13 parked, dormant until HmIP-RFUSB bought |
| 10 | 10.10.1.51 | homematic-ccu-oldsrv | RaspberryMatic CCU — oldsrv standby (macvlan) — HD-13 parked, dormant until HmIP-RFUSB bought |
| 10 | 10.10.1.200 | ha-vip | keepalived VIP — ha.kogler.si |
| 10 | 10.10.1.60 | tablet-valentina | Valentina tablet (family, Kogler SSID) |
| 10 | 10.10.1.61 | phone-domen | Domen's phone A54 (family, Kogler SSID) |
| 10 | 10.10.1.62 | phone-martina | Martina's phone A55 (family, Kogler SSID) |
| 10 | 10.10.1.63 | tablet-ipad | iPad tablet (family, Kogler SSID) — locally-administered/randomized MAC (iOS default) |
| 20 | 10.10.20.1 | router | IoT gateway |
| 21 | 10.10.21.1 | router | IoT-Internet gateway |
| 30 | 10.10.30.1 | router | Guest gateway |
| 40 | 10.10.40.1 | router | Kids gateway |
| 50 | 10.10.50.1 | router | Media gateway |
| 10 | 10.10.1.13 | canon-ts9550 | Canon TS9550 printer (family web UI) |
| 20 | 10.10.20.10 | knx-x1 | GIRA X1 KNX controller |
| 20 | 10.10.20.11 | knx-ip | GIRA IP router (KNX bus) |
| 20 | 10.10.20.12 | reolink-garage | Reolink camera (garage) |
| 20 | 10.10.20.13 | shelly-rgbw2-kuhinja | Shelly RGBW2 (kuhinja) — n8n firmware target |
| 20 | 10.10.20.14 | shelly-rgbw2-wc | Shelly RGBW2 (WC white 4-ch) — n8n firmware target |
| 20 | 10.10.20.15 | shelly-rgbw2-orhideje | Shelly RGBW2 (orhideje) — n8n firmware target |
| 20 | 10.10.20.16 | shelly-rgbw2-kopalnica | Shelly RGBW2 (kopalnica) — n8n firmware target |
| 21 | 10.10.21.10 | bosch-dishwash | Bosch SMV88TX36E dishwasher |
| 21 | 10.10.21.11 | bosch-oven | Bosch HNG6764B6 oven |
| 21 | 10.10.21.12 | bosch-cooktop | Bosch CSG656RB7... cooktop |
| 21 | 10.10.21.13 | lg-ac1 | LG AC klima #1 (QCA4002) |
| 21 | 10.10.21.15 | homematic-hap | HMIP-HAP HomeMatic AP (cloud) — resolved task-6; wired to IoT-Internet per network-vlans (cloud-bound) |
| 21 | 10.10.21.14 | lg-ac2 | LG AC klima #2 (QCA4002) |
| 50 | 10.10.50.10 | nvidia-shield | NVIDIA Shield (Media) — D2-confirmed |
| 50 | 10.10.50.11 | nintendo-switch | Nintendo Switch 2 (Media, D3) |

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
| llm-backend | 172.23.0.0/16 | Docker bridge — LLM backend (Ollama) ↔ LiteLLM only, fully isolated (HD-59) |
| tailnet-apps | 172.24.0.0/16 | Docker bridge — tailnet Traefik edge (traefik-tailnet) ↔ Pattern-A sidecar UIs (HD-296, HD-268c, HD-250); isolated from traefik-public + services-internal so the tailnet edge can't reach apps it shouldn't |
| dns-servers | 172.25.0.0/24 | Docker bridge — Technitium DNS primary (VPS) ↔ its Traefik edge; the container pin is tchnitium_dns_overlay_ip (client resolver = VPS public IP, dns_primary_ip)  |
| site | 10.10.0.0/16 | Whole homelab site — all VLANs (10.10.x.0/24) |
| nfs-clients | 10.10.1.30/32 | NFS export clients — nas tank/data + bulk/media → oldsrv (Home VLAN IP) |
| modem-lan | 192.168.1.0/24 | Comtrend GRG-4260us GPON modem's own LAN (PPPoE bridge mode). The RB4011 takes a /24 on this subnet (192.168.1.2/24 on ether1, connected route to the modem subnet) so the modem's web UI at 192.168.1.1 stays reachable from the homelab — the router presents trusted-admin traffic via srcnat masquerade (HD-302, live-fixed 2026-09-02 from the /32 that had no route) — for the twice-yearly PPPoE-redial dance. |

## WAN-side static hosts

Hosts on subnets the RB4011 connects to but does NOT control (the modem's own LAN
sits behind the ONT). These are not on any homelab VLAN and are not in the
`network_static_hosts` loop above. The Comtrend row drives the HD-302
`trusted-admin` reachability path for the twice-yearly PPPoE-redial dance.

| IP | Host | Role | SSOT |
|----|------|------|------|
| 192.168.1.1 | modem.kogler.si | Comtrend GRG-4260us GPON modem web UI (PPPoE bridge) | `group_vars/router.yml` `comtrend_modem.modem_mgmt_ip` |
| 192.168.1.2/24 | router.kogler.si (on ether1) | RB4011 /24 on the modem's LAN, connected route to the modem subnet + srcnat masquerade for trusted-admin (HD-302) | `group_vars/router.yml` `comtrend_modem.router_on_modem` |

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

> Last generated: 2026-09-03T09:16:10Z