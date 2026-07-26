#==============================================================================
# hAP ac² — 01-base-config
# Bridge, LAN IP, DHCP server, Wi‑Fi AP for the travel LAN.
#
# Topology after this file:
#   bridge-trusted: 192.168.123.0/24
#     ├── ether2, ether3, ether4, ether5 (wired LAN ports)
#     └── wlan2 (5 GHz AP – "Family-Traveling")
#   wlan1: reserved for hotel Wi‑Fi station (configured by captive portal)
#   ether1: reserved for wired WAN (configured in 03-wan-failover.rsc)
#
# VARIABLES:
#   <WIFI_PASSPHRASE>  – WPA2 key for "Family-Traveling" (≥ 8 chars)
#==============================================================================

# --- 1. Create the LAN bridge ---
/interface bridge add \
    admin-mac=auto \
    auto-mac=yes \
    comment="Trusted LAN bridge for travel clients" \
    name=bridge-trusted \
    port-cost-mode=short

# --- 2. Add LAN ports to bridge ---
/interface bridge port add bridge=bridge-trusted interface=ether2
/interface bridge port add bridge=bridge-trusted interface=ether3
/interface bridge port add bridge=bridge-trusted interface=ether4
/interface bridge port add bridge=bridge-trusted interface=ether5
# wlan2 will be added after it is configured as AP (step 7)

# --- 3. Set LAN IP ---
/ip address add \
    address=192.168.123.1/24 \
    comment="Travel LAN gateway" \
    interface=bridge-trusted \
    network=192.168.123.0

# --- 4. LAN DHCP pool ---
/ip pool add \
    name=dhcp_pool-trusted \
    ranges=192.168.123.100-192.168.123.200

# --- 5. LAN DHCP server ---
/ip dhcp-server add \
    address-pool=dhcp_pool-trusted \
    interface=bridge-trusted \
    lease-time=1h \
    name=dhcp-trusted

/ip dhcp-server network add \
    address=192.168.123.0/24 \
    dns-server=192.168.123.1 \
    gateway=192.168.123.1

# --- 6. Wi‑Fi security profile ---
/interface wireless security-profiles add \
    authentication-types=wpa2-psk \
    mode=dynamic-keys \
    name=family-travel-ap \
    wpa2-pre-shared-key=<WIFI_PASSPHRASE>

# --- 7. Configure wlan2 as 5 GHz access point ---
/interface wireless set [find default-name=wlan2] \
    band=5ghz-a/n/ac \
    channel-width=20/40/80mhz-Ceee \
    country=slovenia \
    disabled=no \
    frequency=auto \
    mode=ap-bridge \
    security-profile=family-travel-ap \
    ssid=Family-Traveling

# Add wlan2 to the bridge
/interface bridge port add bridge=bridge-trusted interface=wlan2

# --- 8. Configure wlan1 as 2.4 GHz station (hotel Wi‑Fi) ---
# Mode = station, but SSID and security are set by the captive portal script.
# A placeholder security profile is created here.
/interface wireless security-profiles add \
    authentication-types=wpa2-psk \
    mode=dynamic-keys \
    name=hotel-station

/interface wireless set [find default-name=wlan1] \
    band=2ghz-b/g/n \
    channel-width=20/40mhz-Ce \
    country=slovenia \
    disabled=no \
    frequency=auto \
    mode=station \
    security-profile=hotel-station \
    ssid="" \
    default-ap-tx-limit=300000000

# --- 9. Interface lists ---
/interface list add name=LAN
/interface list add name=WAN

/interface list member add interface=bridge-trusted list=LAN
/interface list member add interface=ether1 list=WAN
/interface list member add interface=wlan1 list=WAN

# --- 10. Router identity ---
/system identity set name=travel-ap

# --- 11. Clock ---
/system clock set time-zone-name=Europe/Ljubljana
/system ntp client set enabled=yes
/system ntp client servers add address=10.10.1.1

# Base config done. Next: run 02-wireguard.rsc
