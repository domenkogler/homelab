#==============================================================================
# hAP ac² — 03-wan-failover
# Dual WAN with route-distance failover:
#   ether1: DHCP client, default-route-distance=1 (preferred)
#   wlan1:  DHCP client, default-route-distance=2 (fallback)
#
# The WireGuard endpoint resolves via DNS (DDNS) and the handshake traffic
# is routed out whichever WAN is currently active thanks to the
# default route with the lower distance.
#
# wlan1 SSID + security are NOT set here — the captive portal script
# applies them at runtime (see 05-hotspot-dns.rsc).
#==============================================================================

# --- ether1 DHCP client (primary WAN) ---
# add-default-route=yes creates a default route with distance=1
/ip dhcp-client add \
    add-default-route=yes \
    default-route-distance=1 \
    disabled=no \
    interface=ether1 \
    use-peer-dns=no \
    use-peer-ntp=no

# --- wlan1 DHCP client (secondary WAN) ---
# add-default-route=yes creates a default route with distance=2
# This will only be used if ether1 has no link/IP.
/ip dhcp-client add \
    add-default-route=yes \
    default-route-distance=2 \
    disabled=no \
    interface=wlan1 \
    use-peer-dns=no \
    use-peer-ntp=no

# --- WireGuard route takes priority over both WAN routes ---
# The static route from 02-wireguard.rsc (distance=1) already wins over
# ether1 DHCP (distance=1, but static is evaluated first).
# If WireGuard goes down, the route disappears and DHCP routes take over —
# but the kill‑switch (04-firewall-killswitch.rsc) will block LAN traffic
# from reaching the WAN, preventing any leak.

# Next: run 04-firewall-killswitch.rsc
