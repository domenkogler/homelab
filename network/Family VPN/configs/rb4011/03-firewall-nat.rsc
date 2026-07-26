#==============================================================================
# RB4011 — 03-firewall-nat
# Fresh firewall + NAT rules.  Builds on WAN list (ether1 + pppoe-telekom)
# and LAN list (bridge) that already exist from the baseline config.
#
# VARIABLES:
#   <WG_LISTEN_PORT> – same port used in 02-wireguard.rsc
#==============================================================================

# ── INPUT CHAIN ──────────────────────────────────────────────────────────────

# Accept WireGuard UDP on the listen port
/ip firewall filter add \
    action=accept \
    chain=input \
    comment="WireGuard handshake" \
    dst-port=<WG_LISTEN_PORT> \
    protocol=udp

# Accept established, related, untracked
/ip firewall filter add \
    action=accept \
    chain=input \
    comment="defconf: accept established,related,untracked" \
    connection-state=established,related,untracked

# Drop invalid packets
/ip firewall filter add \
    action=drop \
    chain=input \
    comment="defconf: drop invalid" \
    connection-state=invalid \
    log=yes log-prefix="drop-invalid"

# Accept ICMP (ping, traceroute)
/ip firewall filter add \
    action=accept \
    chain=input \
    comment="defconf: accept ICMP" \
    protocol=icmp

# Accept to loopback (CAPsMAN needs this)
/ip firewall filter add \
    action=accept \
    chain=input \
    comment="defconf: accept to local loopback" \
    dst-address=127.0.0.1

# Accept from LAN (management, DNS, DHCP, etc.)
/ip firewall filter add \
    action=accept \
    chain=input \
    comment="allow from LAN" \
    in-interface-list=LAN

# Accept from WireGuard interface (remote management if needed)
/ip firewall filter add \
    action=accept \
    chain=input \
    comment="allow from WireGuard VPN" \
    in-interface=wg-family

# Drop everything else from WAN
/ip firewall filter add \
    action=drop \
    chain=input \
    comment="defconf: drop all not from LAN" \
    in-interface-list=!LAN \
    log=yes log-prefix="drop-WAN-input"


# ── FORWARD CHAIN ────────────────────────────────────────────────────────────

# Accept IPsec (if ever needed in the future)
/ip firewall filter add \
    action=accept \
    chain=forward \
    comment="defconf: accept in ipsec policy" \
    ipsec-policy=in,ipsec
/ip firewall filter add \
    action=accept \
    chain=forward \
    comment="defconf: accept out ipsec policy" \
    ipsec-policy=out,ipsec

# FastTrack established/related (performance)
/ip firewall filter add \
    action=fasttrack-connection \
    chain=forward \
    comment="defconf: fasttrack" \
    connection-state=established,related

# Accept established, related, untracked
/ip firewall filter add \
    action=accept \
    chain=forward \
    comment="defconf: accept established,related,untracked" \
    connection-state=established,related,untracked

# Drop invalid
/ip firewall filter add \
    action=drop \
    chain=forward \
    comment="defconf: drop invalid" \
    connection-state=invalid \
    log=yes log-prefix="drop-fwd-invalid"

# Drop new connections from WAN that are not DSTNATed
/ip firewall filter add \
    action=drop \
    chain=forward \
    comment="defconf: drop all from WAN not DSTNATed" \
    connection-nat-state=!dstnat \
    connection-state=new \
    in-interface-list=WAN \
    log=yes log-prefix="drop-fwd-WAN"


# ── NAT (SRCNAT MASQUERADE) ──────────────────────────────────────────────────

# Masquerade everything leaving via WAN (covers 10.10.1.0/24 and 192.168.123.0/24)
/ip firewall nat add \
    action=masquerade \
    chain=srcnat \
    comment="masquerade out WAN" \
    out-interface-list=WAN


# Next: run 04-dns.rsc
