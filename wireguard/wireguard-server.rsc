# WireGuard server configuration for RB4011
# Import into RouterOS: /import wireguard-server.rsc
#
# BEFORE IMPORTING:
#   1. Run the commands in generate-keys.rsc to create key pairs
#   2. Replace the placeholders below with the actual keys:
#      <router-public-key>  → your router's public key
#      <laptop-public-key>  → the laptop peer's public key
#      <phone-public-key>   → the phone peer's public key

# --- WireGuard interface ---
/interface wireguard
add listen-port=13231 mtu=1420 name=wg-home

# --- IP address on WireGuard interface (VPN subnet) ---
/ip address
add address=10.10.99.1/24 interface=wg-home network=10.10.99.0

# --- Add wg-home to LAN list so router management is accessible ---
# This allows Winbox, WebFig, SSH, DNS from VPN clients
/interface list member
add interface=wg-home list=LAN

# --- Forward rules: allow traffic between VPN and LAN ---
# Inserted at the top of the forward chain
/ip firewall filter
add action=accept chain=forward comment="VPN -> LAN" in-interface=wg-home out-interface-list=LAN place-before=0
add action=accept chain=forward comment="LAN -> VPN" in-interface-list=LAN out-interface=wg-home place-before=0

# --- LAPTOP peer (split tunnel: only LAN subnets routed through VPN) ---
/interface wireguard peers
add allowed-address=10.10.99.2/32 comment="laptop" interface=wg-home public-key="<laptop-public-key>"

# --- PHONE/TABLET peer (full tunnel: all traffic through home) ---
/interface wireguard peers
add allowed-address=10.10.99.3/32 comment="phone" interface=wg-home public-key="<phone-public-key>"