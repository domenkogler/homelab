#==============================================================================
# hAP ac² — 05-hotspot-dns
# Hotspot captive portal + DNS configuration.
#
# The Hotspot server runs on bridge-trusted.  When a LAN client opens a
# browser, they are redirected to the login page at http://potovalni.vpn.
# The user enters the hotel Wi‑Fi SSID + password, and the on‑login script
# applies those settings to wlan1 (station mode).
#
# VARIABLES:
#   <HOME_DOMAIN> – e.g. home.kogler.si (domain forwarded to home DNS)
#==============================================================================

# ── 1. Upload the custom login page ─────────────────────────────────────────
# The file 06-hotspot-login.html must be uploaded to the router first.
# After uploading, copy it into the hotspot directory:
#   /tool fetch url="http://.../06-hotspot-login.html" dst-path=login.html
#   /file set login.html contents=[/file get login.html contents]
# Or use drag-and-drop in WinBox Files → hotspot folder.
#
# For now, the script references the file that will be at hotspot/login.html
# after manual upload.

# ── 2. Hotspot server profile ───────────────────────────────────────────────
/ip hotspot profile add \
    dns-name=potovalni.vpn \
    html-directory=hotspot \
    login-by=http-pap \
    name=hotel-setup \
    use-radius=no

# ── 3. Hotspot user profile (transparent — no real AAA) ─────────────────────
/ip hotspot user profile add \
    name=hotel-config \
    on-login=hotspot-on-login \
    address-pool=none \
    transparent-proxy=no

# ── 4. Hotspot server (on bridge-trusted) ───────────────────────────────────
/ip hotspot add \
    address-pool=none \
    disabled=no \
    interface=bridge-trusted \
    name=hotspot-hotel \
    profile=hotel-setup

# ── 5. Hotspot walled garden (allow access to the login page itself) ────────
# The Hotspot already allows DNS and HTTP to the router by default.
# Explicitly allow the potovalni.vpn host:
/ip hotspot walled-garden ip add \
    action=accept \
    dst-host=potovalni.vpn

# ── 6. On‑login script ──────────────────────────────────────────────────────
# This script runs when the user submits the hotel Wi‑Fi credentials.
# $user   = hotel SSID
# $password = hotel WPA2 key
/system script add \
    name=hotspot-on-login \
    policy=read,write,test \
    source="\
:if ([:len \$\"user\"] = 0 || [:len \$\"password\"] = 0) do={\r\
    \n  :log error \"Hotspot: empty SSID or password\"\r\
    \n  :set \$ok false\r\
    \n} else={\r\
    \n  :do {\r\
    \n    /interface wireless security-profiles set [find name=\"hotel-station\"] wpa2-pre-shared-key=\$\"password\"\r\
    \n    /interface wireless set wlan1 ssid=\$\"user\"\r\
    \n    :delay 500ms\r\
    \n    /ip dhcp-client enable [find interface=wlan1]\r\
    \n    :log info \"Hotspot: wlan1 configured for SSID=\$\"user\"\"\r\
    \n    :set \$ok true\r\
    \n  } on-error={\r\
    \n    :log error \"Hotspot: failed to configure wlan1 - \$!\"\r\
    \n    :set \$ok false\r\
    \n  }\r\
    \n}\r\
    \n"

# ── 7. DNS: resolve potovalni.vpn locally ───────────────────────────────────
/ip dns static add \
    address=192.168.123.1 \
    name=potovalni.vpn \
    type=A

# ── 8. DNS: forward home domain queries to the home router through the VPN ──
/ip dns static add \
    comment="Forward *.home.kogler.si to home DNS via VPN" \
    forward-to=10.10.1.1 \
    name=home.kogler.si \
    type=FWD

# ── 9. DNS: set resolver (traffic goes through VPN because default route is wg-family) ──
/ip dns set \
    allow-remote-requests=yes \
    servers=1.1.1.1

# ── 10. Hotspot user (dummy entry — the on‑login script handles "auth") ─────
# Users don't need to pre‑exist; the on‑login script with HTTP‑PAP will
# receive any username/password.  But we need at least one user profile
# mapped.  Create a wildcard-like setup:
/ip hotspot user add \
    name=default \
    profile=hotel-config

# ═════════════════════════════════════════════════════════════════════════════
# Manual step after running this file:
#   Upload 06-hotspot-login.html to the router's hotspot/ directory.
#   In WinBox: Files → drag login.html into the hotspot folder.
#   Or via CLI: /tool fetch url="..." dst-path=hotspot/login.html
# ═════════════════════════════════════════════════════════════════════════════