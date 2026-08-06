#==============================================================================
# hAP ac² — 00-system-upgrade
# First‑time setup: upgrade RouterOS to latest stable 7.x
#
# PREREQUISITE (do this manually first):
#   1. Connect ether1 on the hAP ac² to any port on the home RB4011 bridge
#      (which is the 10.10.1.0/24 LAN — ether2–ether10 or SFP+).
#   2. The hAP ac² will get a DHCP lease from the home router.
#   3. Verify internet access from the hAP ac²:
#        /ping 1.1.1.1 count=3
#   4. Then proceed below.
#==============================================================================

# --- Check current version ---
/system resource print
/system routerboard print

# --- Upgrade RouterOS to latest stable ---
/system package update set channel=stable
/system package update check-for-updates
:delay 5s
/system package update install

# The router will reboot automatically after the update.
# After reboot, verify the new version:
#   /system resource print

# Now you are ready to run 01-base-config.rsc
