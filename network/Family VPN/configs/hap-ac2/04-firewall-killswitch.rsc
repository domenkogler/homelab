#==============================================================================
# hAP ac² — 04-firewall-killswitch
# Kill‑switch firewall: LAN clients can ONLY reach the internet through the
# WireGuard tunnel.  If the VPN goes down, LAN traffic is blocked — no leak.
#
# The router itself can still reach the WAN (for WireGuard handshake, DDNS
# resolution, NTP, RouterOS updates).  The Hotspot walled garden (dynamic
# rules inserted by the Hotspot server) is not affected.
#==============================================================================

# ── IPv4 INPUT CHAIN ────────────────────────────────────────────────────────

# Accept established, related, untracked
/ip firewall filter add \
    action=accept \
    chain=input \
    comment="accept established,related,untracked" \
    connection-state=established,related,untracked

# Drop invalid
/ip firewall filter add \
    action=drop \
    chain=input \
    comment="drop invalid" \
    connection-state=invalid

# Accept ICMP
/ip firewall filter add \
    action=accept \
    chain=input \
    comment="accept ICMP" \
    protocol=icmp

# Accept from LAN (hotspot, DNS, WinBox, SSH)
/ip firewall filter add \
    action=accept \
    chain=input \
    comment="allow from LAN" \
    in-interface-list=LAN

# Accept WireGuard traffic
/ip firewall filter add \
    action=accept \
    chain=input \
    comment="allow WireGuard" \
    in-interface=wg-family

# Drop everything else from WAN
/ip firewall filter add \
    action=drop \
    chain=input \
    comment="drop all from WAN" \
    in-interface-list=WAN


# ── IPv4 FORWARD CHAIN ──────────────────────────────────────────────────────

# Accept established, related, untracked
/ip firewall filter add \
    action=accept \
    chain=forward \
    comment="accept established,related,untracked" \
    connection-state=established,related,untracked

# Drop invalid
/ip firewall filter add \
    action=drop \
    chain=forward \
    comment="drop invalid" \
    connection-state=invalid

# KILL‑SWITCH: drop LAN traffic trying to go out any WAN interface
# (The Hotspot server inserts its own dynamic rules that take precedence;
#  this rule catches anything else that would leak to the hotel network.)
/ip firewall filter add \
    action=drop \
    chain=forward \
    comment="KILL-SWITCH: block LAN -> WAN" \
    in-interface=bridge-trusted \
    out-interface-list=WAN

# Accept all other forward traffic
# (LAN <-> WireGuard, WireGuard <-> WAN, internal LAN traffic)
/ip firewall filter add \
    action=accept \
    chain=forward \
    comment="accept all other forward"


# ── IPv6 INPUT CHAIN ────────────────────────────────────────────────────────

/ipv6 firewall filter add \
    action=accept \
    chain=input \
    comment="accept established,related,untracked" \
    connection-state=established,related,untracked

/ipv6 firewall filter add \
    action=drop \
    chain=input \
    comment="drop invalid" \
    connection-state=invalid

/ipv6 firewall filter add \
    action=accept \
    chain=input \
    comment="accept ICMPv6" \
    protocol=icmpv6

/ipv6 firewall filter add \
    action=accept \
    chain=input \
    comment="accept from LAN" \
    in-interface-list=LAN

/ipv6 firewall filter add \
    action=drop \
    chain=input \
    comment="drop all from WAN" \
    in-interface-list=WAN


# ── IPv6 FORWARD CHAIN ──────────────────────────────────────────────────────

/ipv6 firewall filter add \
    action=accept \
    chain=forward \
    comment="accept established,related,untracked" \
    connection-state=established,related,untracked

/ipv6 firewall filter add \
    action=drop \
    chain=forward \
    comment="drop invalid" \
    connection-state=invalid

# KILL‑SWITCH for IPv6: same logic as IPv4
/ipv6 firewall filter add \
    action=drop \
    chain=forward \
    comment="KILL-SWITCH: block LAN -> WAN (IPv6)" \
    in-interface=bridge-trusted \
    out-interface-list=WAN

/ipv6 firewall filter add \
    action=accept \
    chain=forward \
    comment="accept all other forward (IPv6)"


# ── DISABLE IPv6 NEIGHBOR DISCOVERY ON WAN (privacy) ────────────────────────
/ipv6 nd set [find interface=wlan1] disabled=yes
/ipv6 nd set [find interface=ether1] disabled=yes

# Next: run 05-hotspot-dns.rsc