#==============================================================================
# hAP ac² — 02-wireguard
# WireGuard "client" side. Generates keys, creates interface + peer for RB4011,
# and sets the default route through the tunnel.
#
# VARIABLES:
#   <RB4011_PUBLIC_KEY>    – public key from RB4011 (printed by its 02-wireguard.rsc)
#   <RB4011_DDNS_HOSTNAME> – MikroTik cloud DDNS hostname (e.g. XXXXX.sn.mynetname.net)
#   <WG_LISTEN_PORT>       – same port used on RB4011 (e.g. 29008)
#==============================================================================

# --- Generate hAP ac² WireGuard key pair ---
/interface wireguard add \
    comment="Family VPN – client side" \
    mtu=1420 \
    name=wg-family

# --- Assign tunnel IP (client side = .2) ---
/ip address add \
    address=10.99.99.2/31 \
    interface=wg-family \
    network=10.99.99.0

# --- Add the RB4011 peer ---
/interface wireguard peers add \
    allowed-address=0.0.0.0/0 \
    comment="Home RB4011" \
    endpoint-address=<RB4011_DDNS_HOSTNAME> \
    endpoint-port=<WG_LISTEN_PORT> \
    interface=wg-family \
    persistent-keepalive=25s \
    public-key="<RB4011_PUBLIC_KEY>"

# --- Route all traffic through the VPN ---
# Remove any default route that DHCP clients may have added
/ip route remove [find dst-address=0.0.0.0/0]

# Add default route via the WireGuard interface (distance=1 overrides DHCP routes)
/ip route add \
    comment="Default route via VPN" \
    disabled=no \
    distance=1 \
    dst-address=0.0.0.0/0 \
    gateway=wg-family

# --- Show the hAP ac² public key (copy this to RB4011 config) ---
:put "=== hAP ac² WireGuard public key ==="
/interface wireguard print value-list where name=wg-family
:put "=== Paste the public-key value into rb4011/02-wireguard.rsc ==="

# Next: run 03-wan-failover.rsc
