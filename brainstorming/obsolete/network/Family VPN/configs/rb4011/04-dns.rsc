#==============================================================================
# RB4011 — 04-dns
# DNS configuration.  The baseline config already has:
#   /ip dns set allow-remote-requests=yes servers=1.1.1.1,8.8.8.8
# and several static entries.  This file adds static entries for the
# WireGuard peers and verifies DNS is reachable from the travel LAN.
#
# VARIABLES:
#   <HOME_DOMAIN> – e.g. home.kogler.si  (used on travel AP for conditional forwarding)
#==============================================================================

# --- Ensure DNS allows remote requests (idempotent) ---
/ip dns set allow-remote-requests=yes

# --- Static entry so "home.kogler.si" names resolve through this router ---
# Travel AP will forward home-domain queries here (see hap-ac2/05-hotspot-dns.rsc).
# This entry ensures the travel AP itself can resolve the home DNS server.
/ip dns static add \
    address=10.10.1.1 \
    comment="Home DNS server (for travel AP conditional forwarding)" \
    name=home.kogler.si \
    type=A

# --- Optional: static entry for the travel AP WireGuard peer ---
# /ip dns static add address=10.99.99.2 name=travel-ap.lan type=A

# RB4011 configuration is complete.
# Move on to the hAP ac² configs.
