#==============================================================================
# RB4011 — 01-cleanup
# Purge old WireGuard, cloud Back‑to‑Home, netwatch, and firewall rules.
# Run this BEFORE applying the new WireGuard + firewall configs.
#
# SAFE: other config (CAPsMAN, bridges, DHCP leases, PPPoE, IPv6) is untouched.
#==============================================================================

# 1. Disable cloud Back‑to‑Home (old VPN mesh)
/ip cloud set back-to-home-vpn=disabled

# 2. Remove all WireGuard peers (must delete peers before the interface)
/interface wireguard peers remove [find]
# 3. Remove the WireGuard interface itself
/interface wireguard remove [find]

# 4. Remove all netwatch entries (they reference old WG peers)
/tool netwatch remove [find]

# 5. Wipe IPv4 firewall filter rules
/ip firewall filter remove [find]

# 6. Wipe IPv4 firewall NAT rules
/ip firewall nat remove [find]

# 7. Wipe IPv4 firewall mangle rules (if any)
/ip firewall mangle remove [find]

# 8. Wipe IPv4 firewall raw rules (if any)
/ip firewall raw remove [find]

# Done. The router is now a clean slate for WireGuard + firewall.
# Next: run 02-wireguard.rsc
