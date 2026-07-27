# =============================================================================
# RB4011 — Kogler Homelab — Initial Config
# =============================================================================
# Purpose:  Fresh-start baseline for factory-reset router (manual import via WinBox)
# After:    Reset → No Defaults → set temporary IP + admin password via WinBox MAC
#           Then drag this file into WinBox Files → /import rb4011_initial.rsc
# =============================================================================
# WARNING: Replace ALL CHANGEME values before importing.
#           PPPoE credentials from Telekom Slovenije.
#           WireGuard keys — generate with: openssl rand -base64 32
# =============================================================================

# ---- System ----

/system identity set name=rb4011.kogler.lan
/system clock set time-zone-name=Europe/Ljubljana
/system ntp client set enabled=yes server-dns-names=pool.ntp.org
/system ntp client servers add server=193.2.1.66

# ---- PPPoE (Telekom Slovenije) ----

/interface pppoe-client add \
    name=pppoe-telekom \
    interface=ether1 \
    user=CHANGEME \
    password=CHANGEME \
    add-default-route=yes \
    use-peer-dns=no \
    disabled=no

# IPv6 via PPPoE
/ipv6 dhcp-client add \
    interface=pppoe-telekom \
    pool-name=ipv6-pool \
    prefix-hint=::/56 \
    add-default-route=yes \
    disabled=no

# ---- Bridge (VLAN-aware) ----

/interface bridge add \
    name=bridge-lan \
    vlan-filtering=yes \
    protocol-mode=none

# Add all physical ports to bridge
/interface bridge port add bridge=bridge-lan interface=ether2  pvid=1
/interface bridge port add bridge=bridge-lan interface=ether3  pvid=1
/interface bridge port add bridge=bridge-lan interface=ether4  pvid=1
/interface bridge port add bridge=bridge-lan interface=ether5  pvid=1
/interface bridge port add bridge=bridge-lan interface=ether6  pvid=1
/interface bridge port add bridge=bridge-lan interface=ether7  pvid=1
/interface bridge port add bridge=bridge-lan interface=ether8  pvid=1
/interface bridge port add bridge=bridge-lan interface=ether9  pvid=1
/interface bridge port add bridge=bridge-lan interface=ether10 pvid=1
/interface bridge port add bridge=bridge-lan interface=sfp-sfpplus1 pvid=1

# ---- Bridge VLAN assignments ----
# VLAN 1:  Blackhole (unused, all ports default pvid=1)
# VLAN 10: Home
# VLAN 20: IoT
# VLAN 30: Guest
# VLAN 40: Kids
# VLAN 50: Media
# VLAN 99: Management

# sfp-sfpplus1: trunk to CRS328 — all VLANs tagged
# bridge-lan: tagged = router CPU sees all VLANs

/interface bridge vlan add bridge=bridge-lan vlan-ids=10 tagged=bridge-lan,sfp-sfpplus1
/interface bridge vlan add bridge=bridge-lan vlan-ids=20 tagged=bridge-lan,sfp-sfpplus1
/interface bridge vlan add bridge=bridge-lan vlan-ids=30 tagged=bridge-lan,sfp-sfpplus1
/interface bridge vlan add bridge=bridge-lan vlan-ids=40 tagged=bridge-lan,sfp-sfpplus1
/interface bridge vlan add bridge=bridge-lan vlan-ids=50 tagged=bridge-lan,sfp-sfpplus1
/interface bridge vlan add bridge=bridge-lan vlan-ids=99 tagged=bridge-lan,sfp-sfpplus1

# ---- VLAN interfaces (L3) ----

/interface vlan add name=vlan10-home  vlan-id=10 interface=bridge-lan
/interface vlan add name=vlan20-iot   vlan-id=20 interface=bridge-lan
/interface vlan add name=vlan30-guest vlan-id=30 interface=bridge-lan
/interface vlan add name=vlan40-kids  vlan-id=40 interface=bridge-lan
/interface vlan add name=vlan50-media vlan-id=50 interface=bridge-lan
/interface vlan add name=vlan99-mgmt  vlan-id=99 interface=bridge-lan

# ---- IP Addresses ----

/ip address add address=10.10.1.1/24  interface=vlan10-home  comment="Home gateway"
/ip address add address=10.10.20.1/24 interface=vlan20-iot   comment="IoT gateway"
/ip address add address=10.10.30.1/24 interface=vlan30-guest comment="Guest gateway"
/ip address add address=10.10.40.1/24 interface=vlan40-kids  comment="Kids gateway"
/ip address add address=10.10.50.1/24 interface=vlan50-media comment="Media gateway"
/ip address add address=10.10.99.1/24 interface=vlan99-mgmt  comment="Management gateway"

# ---- DHCP Pools ----

/ip pool add name=pool-home    ranges=10.10.1.100-10.10.1.199
/ip pool add name=pool-iot     ranges=10.10.20.100-10.10.20.199
/ip pool add name=pool-guest   ranges=10.10.30.100-10.10.30.199
/ip pool add name=pool-kids    ranges=10.10.40.100-10.10.40.199
/ip pool add name=pool-media   ranges=10.10.50.100-10.10.50.199
/ip pool add name=pool-mgmt    ranges=10.10.99.50-10.10.99.99

# ---- DHCP Servers ----

/ip dhcp-server add name=dhcp-home  interface=vlan10-home  address-pool=pool-home  disabled=no
/ip dhcp-server add name=dhcp-iot   interface=vlan20-iot   address-pool=pool-iot   disabled=no
/ip dhcp-server add name=dhcp-guest interface=vlan30-guest address-pool=pool-guest disabled=no
/ip dhcp-server add name=dhcp-kids  interface=vlan40-kids  address-pool=pool-kids  disabled=no
/ip dhcp-server add name=dhcp-media interface=vlan50-media address-pool=pool-media disabled=no
/ip dhcp-server add name=dhcp-mgmt  interface=vlan99-mgmt  address-pool=pool-mgmt  disabled=no

# ---- DHCP Networks ----
# DNS points at router (10.10.x.1). Router forwards to Technitium (later) / 1.1.1.1 (now)

/ip dhcp-server network add \
    address=10.10.1.0/24 gateway=10.10.1.1 dns-server=10.10.1.1 \
    domain=home.kogler.si comment="Home"

/ip dhcp-server network add \
    address=10.10.20.0/24 gateway=10.10.20.1 dns-server=10.10.20.1 \
    domain=home.kogler.si comment="IoT"

/ip dhcp-server network add \
    address=10.10.30.0/24 gateway=10.10.30.1 dns-server=10.10.30.1 \
    comment="Guest (no local domain)"

/ip dhcp-server network add \
    address=10.10.40.0/24 gateway=10.10.40.1 dns-server=10.10.40.1 \
    domain=home.kogler.si comment="Kids"

/ip dhcp-server network add \
    address=10.10.50.0/24 gateway=10.10.50.1 dns-server=10.10.50.1 \
    domain=home.kogler.si comment="Media"

/ip dhcp-server network add \
    address=10.10.99.0/24 gateway=10.10.99.1 dns-server=10.10.99.1 \
    domain=home.kogler.si comment="Management"

# ---- DNS (temporary — switches to Technitium after Debian PC is up) ----

/ip dns set \
    servers=1.1.1.1 \
    allow-remote-requests=yes

# ---- Interface Lists (for firewall) ----

/interface list add name=WAN
/interface list add name=LAN
/interface list add name=VLAN-Home
/interface list add name=VLAN-IoT
/interface list add name=VLAN-Guest
/interface list add name=VLAN-Kids
/interface list add name=VLAN-Media
/interface list add name=VLAN-Mgmt

/interface list member add list=WAN        interface=pppoe-telekom
/interface list member add list=LAN        interface=vlan10-home
/interface list member add list=LAN        interface=vlan20-iot
/interface list member add list=LAN        interface=vlan30-guest
/interface list member add list=LAN        interface=vlan40-kids
/interface list member add list=LAN        interface=vlan50-media
/interface list member add list=LAN        interface=vlan99-mgmt
/interface list member add list=VLAN-Home  interface=vlan10-home
/interface list member add list=VLAN-IoT   interface=vlan20-iot
/interface list member add list=VLAN-Guest interface=vlan30-guest
/interface list member add list=VLAN-Kids  interface=vlan40-kids
/interface list member add list=VLAN-Media interface=vlan50-media
/interface list member add list=VLAN-Mgmt  interface=vlan99-mgmt

# ---- Address Lists ----

# Trusted Home devices allowed to initiate connections into IoT
/ip firewall address-list add address=10.10.1.10  list=trusted-ha    comment="Home Assistant (RPi4)"
# Debian PC address added later after install

# IoT devices allowed internet access (firmware updates)
# Uncomment and add IPs when needed:
# /ip firewall address-list add address=10.10.20.x list=iot-internet-ok comment="Allowlisted IoT device"

# ---- Firewall: Filter ----

# Default chains
/ip firewall filter add chain=input   connection-state=established,related action=accept comment="Allow established input"
/ip firewall filter add chain=input   connection-state=invalid              action=drop    comment="Drop invalid input"
/ip firewall filter add chain=forward connection-state=established,related action=accept comment="Allow established forward"
/ip firewall filter add chain=forward connection-state=invalid              action=drop    comment="Drop invalid forward"

# Trusted management access (router itself)
/ip firewall filter add chain=input in-interface-list=VLAN-Home protocol=tcp dst-port=22,8291,8728,80,443 action=accept comment="SSH/WinBox/API/Web from Home"
/ip firewall filter add chain=input in-interface-list=VLAN-Mgmt protocol=tcp dst-port=22,8291,8728,80,443 action=accept comment="SSH/WinBox/API/Web from Mgmt"
/ip firewall filter add chain=input in-interface=vlan10-home                               protocol=icmp                                 action=accept comment="ICMP from Home"
/ip firewall filter add chain=input in-interface=vlan99-mgmt                               protocol=icmp                                 action=accept comment="ICMP from Mgmt"
/ip firewall filter add chain=input                                                         action=drop    comment="Drop all other input"

# Inter-VLAN forwarding rules
# NOTE: Order matters — rules are evaluated top-to-bottom

# DNS: allow all VLANs → router DNS (intercepted before inter-VLAN drop)
/ip firewall filter add chain=forward dst-address=10.10.1.1   protocol=udp dst-port=53 in-interface-list=LAN action=accept comment="DNS → router (Home GW)"
/ip firewall filter add chain=forward dst-address=10.10.20.1  protocol=udp dst-port=53 in-interface-list=LAN action=accept comment="DNS → router (IoT GW)"
/ip firewall filter add chain=forward dst-address=10.10.30.1  protocol=udp dst-port=53 in-interface-list=LAN action=accept comment="DNS → router (Guest GW)"
/ip firewall filter add chain=forward dst-address=10.10.40.1  protocol=udp dst-port=53 in-interface-list=LAN action=accept comment="DNS → router (Kids GW)"
/ip firewall filter add chain=forward dst-address=10.10.50.1  protocol=udp dst-port=53 in-interface-list=LAN action=accept comment="DNS → router (Media GW)"
/ip firewall filter add chain=forward dst-address=10.10.99.1  protocol=udp dst-port=53 in-interface-list=LAN action=accept comment="DNS → router (Mgmt GW)"

# Home → IoT (MQTT/HA initiated by trusted devices)
/ip firewall filter add chain=forward \
    src-address-list=trusted-ha out-interface=vlan20-iot \
    connection-state=new action=accept \
    comment="Home→IoT (trusted: HA)"

# Home → Management
/ip firewall filter add chain=forward \
    in-interface=vlan10-home out-interface=vlan99-mgmt \
    protocol=tcp dst-port=22,8291,80,443 action=accept \
    comment="Home→Mgmt (SSH/WinBox/Web)"

# Home → Media (casting, remote control)
/ip firewall filter add chain=forward \
    in-interface=vlan10-home out-interface=vlan50-media \
    action=accept comment="Home→Media (cast/control)"

# Media → Home (media server)
/ip firewall filter add chain=forward \
    in-interface=vlan50-media out-interface=vlan10-home \
    action=accept comment="Media→Home (Plex/Jellyfin)"

# IoT: no internet (manual disable this rule for firmware updates)
/ip firewall filter add chain=forward \
    in-interface=vlan20-iot out-interface-list=WAN \
    action=drop comment="IoT→WAN DROP (disable for firmware updates)"

# Kids bedtime block (22:00–07:00, hard drop bypass-proof)
/ip firewall filter add chain=forward \
    in-interface=vlan40-kids out-interface-list=WAN \
    time=22h00m-23h59m,sun,mon,tue,wed,thu,fri,sat \
    action=drop comment="Kids bedtime 22:00-00:00"
/ip firewall filter add chain=forward \
    in-interface=vlan40-kids out-interface-list=WAN \
    time=0h00m-7h00m,sun,mon,tue,wed,thu,fri,sat \
    action=drop comment="Kids bedtime 00:00-07:00"

# Guest → LAN (internet only)
/ip firewall filter add chain=forward \
    in-interface=vlan30-guest out-interface-list=LAN \
    action=drop comment="Guest→LAN DROP"

# IoT → Home (only replies, no new connections)
/ip firewall filter add chain=forward \
    in-interface=vlan20-iot out-interface=vlan10-home \
    connection-state=new action=drop \
    comment="IoT↛Home (block new)"

# Kids → Home
/ip firewall filter add chain=forward \
    in-interface=vlan40-kids out-interface=vlan10-home \
    action=drop comment="Kids↛Home"

# Inter-VLAN catch-all drop (below all exceptions)
/ip firewall filter add chain=forward \
    in-interface-list=LAN out-interface-list=LAN \
    action=drop comment="Default inter-VLAN drop"

# ---- Firewall: NAT ----

/ip firewall nat add chain=srcnat out-interface-list=WAN action=masquerade comment="Masquerade all → WAN"

# ---- CAPsMAN ----

/caps-man security add \
    name=sec-kogler \
    authentication-types=wpa2-psk \
    passphrase=CHANGEME \
    encryption=aes-ccm

/caps-man security add \
    name=sec-kogler-iot \
    authentication-types=wpa2-psk \
    passphrase=CHANGEME \
    encryption=aes-ccm

/caps-man security add \
    name=sec-kogler-guest \
    authentication-types=wpa2-psk \
    passphrase=CHANGEME \
    encryption=aes-ccm

/caps-man security add \
    name=sec-kogler-kids \
    authentication-types=wpa2-psk \
    passphrase=CHANGEME \
    encryption=aes-ccm

# Datapaths — one per VLAN, local-forwarding=no (all traffic tunneled to router)
/caps-man datapath add \
    name=dp-home  bridge=bridge-lan local-forwarding=no client-to-client-forwarding=yes
/caps-man datapath add \
    name=dp-iot   bridge=bridge-lan local-forwarding=no client-to-client-forwarding=no
/caps-man datapath add \
    name=dp-guest bridge=bridge-lan local-forwarding=no client-to-client-forwarding=no
/caps-man datapath add \
    name=dp-kids  bridge=bridge-lan local-forwarding=no client-to-client-forwarding=no

# Configurations — SSID → datapath → VLAN
/caps-man configuration add \
    name=cfg-kogler \
    ssid=Kogler \
    security=sec-kogler \
    datapath=dp-home \
    datapath.vlan-id=10 \
    datapath.vlan-mode=use-tag

/caps-man configuration add \
    name=cfg-kogler-iot \
    ssid=Kogler-IOT \
    security=sec-kogler-iot \
    datapath=dp-iot \
    datapath.vlan-id=20 \
    datapath.vlan-mode=use-tag

/caps-man configuration add \
    name=cfg-kogler-guest \
    ssid=Kogler-guest \
    security=sec-kogler-guest \
    datapath=dp-guest \
    datapath.vlan-id=30 \
    datapath.vlan-mode=use-tag

/caps-man configuration add \
    name=cfg-kogler-kids \
    ssid=Kogler-Kids \
    security=sec-kogler-kids \
    datapath=dp-kids \
    datapath.vlan-id=40 \
    datapath.vlan-mode=use-tag

# Provisioning — all APs get all 4 SSIDs
/caps-man provisioning add \
    action=create-dynamic-enabled \
    master-configuration=cfg-kogler \
    slave-configurations=cfg-kogler-iot,cfg-kogler-guest,cfg-kogler-kids

# Enable CAPsMAN
/caps-man manager set \
    enabled=yes \
    certificate=auto \
    ca-certificate=auto \
    generate-ca=yes

# ---- WireGuard ----

# Site-to-Site: Home ↔ VPS
/interface wireguard add \
    name=wg-vps \
    listen-port=13231 \
    private-key="CHANGEME"

/ip address add \
    address=10.255.40.1/30 \
    interface=wg-vps \
    comment="S2S tunnel to VPS"

# Road-warrior server (legacy — Headscale replaces this for family)
/interface wireguard add \
    name=wg-roadwarrior \
    listen-port=13232 \
    private-key="CHANGEME"

/ip address add \
    address=10.255.50.1/24 \
    interface=wg-roadwarrior \
    comment="Road-warrior VPN"

# Travel router peer (placeholder — key generated later)
# /interface wireguard peers add \
#     interface=wg-vps \
#     public-key="CHANGEME" \
#     allowed-address=10.99.99.2/32 \
#     comment="Travel hAP ac2 (Sploax)"

# VPS peer (placeholder — key generated later)
# /interface wireguard peers add \
#     interface=wg-vps \
#     public-key="CHANGEME" \
#     allowed-address=10.255.40.2/32,10.255.20.0/24 \
#     comment="Cloud VPS"

# ---- Static Routes ----
# Reach VPS services via S2S tunnel (activate when peer is added)
# /ip route add dst-address=10.255.20.0/24 gateway=10.255.40.2 comment="VPS services via wg-vps"

# ---- Services ----

/ip service set api     disabled=no
/ip service set www-ssl disabled=no certificate=none
/ip service set ssh     disabled=no port=22

# ---- End ----
# After import, verify:
#   1. PPPoE connects → /interface pppoe-client monitor pppoe-telekom
#   2. DHCP servers running → /ip dhcp-server print
#   3. CAPsMAN active → /caps-man manager print
#   4. Export final config → /export file=rb4011_final