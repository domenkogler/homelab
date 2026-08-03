# =============================================================================
# hAP ac / hAP ac² — Kogler Homelab — CAP Mode Config
# =============================================================================
# Purpose:  Configure AP as CAPsMAN-managed (run after factory reset)
#           CRS328 port must be access port on VLAN 99 (Management) for CAP discovery
# Usage:    Drag into WinBox Files → /import ap_initial.rsc
#           Update identity per AP (ap-kitchen, ap-livingroom, etc.)
# =============================================================================
# WARNING: Replace CHANGEME values before importing.
# =============================================================================

# ---- System ----

/system identity set name=CHANGEME
/user set [find name=admin] password=CHANGEME
/system clock set time-zone-name=Europe/Ljubljana
/system ntp client set enabled=yes server-dns-names=pool.ntp.org

# ---- Bridge (all ports) ----

/interface bridge add name=bridge protocol-mode=none

/interface bridge port add bridge=bridge interface=ether1
/interface bridge port add bridge=bridge interface=ether2
/interface bridge port add bridge=bridge interface=ether3
/interface bridge port add bridge=bridge interface=ether4
/interface bridge port add bridge=bridge interface=ether5
/interface bridge port add bridge=bridge interface=wlan1
/interface bridge port add bridge=bridge interface=wlan2

# ---- DHCP Client (gets IP from Management VLAN 99 via CRS328) ----

/ip dhcp-client add interface=bridge disabled=no comment="Mgmt IP from CRS328 access port"

# ---- CAP Mode ----

/interface wireless cap set \
    enabled=yes \
    interfaces=wlan1,wlan2 \
    discovery-interfaces=bridge

# ---- Optional: static IP for direct access ----
# Uncomment if DHCP fails and you need MAC-Telnet:
# /ip address add address=192.168.88.2/24 interface=bridge

# ---- End ----
# After import, verify on RB4011:
#   /caps-man remote-cap print
# AP should appear with 5 dynamic interfaces (one per SSID)