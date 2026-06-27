# Testing Checklist – Family VPN

Run these tests after deploying the configuration on both routers.
Mark each test ✅ (pass) or ❌ (fail).

---

## 1. WireGuard Tunnel

| # | Test | Expected Result | ✓ |
|---|------|-----------------|---|
| 1.1 | On RB4011: `/interface wireguard peers print` | Peer shows `interface=wg-family`, latest handshake ≤ 30s ago | |
| 1.2 | On hAP ac²: `/interface wireguard peers print` | Peer shows `interface=wg-family`, latest handshake ≤ 30s ago | |
| 1.3 | From travel LAN client: `ping 10.99.99.1` | Ping succeeds (2–5ms) | |
| 1.4 | From travel LAN client: `ping 10.10.1.1` | Ping succeeds (home router LAN IP) | |

---

## 2. Full‑Tunnel Routing

| # | Test | Expected Result | ✓ |
|---|------|-----------------|---|
| 2.1 | From travel LAN client: `traceroute 1.1.1.1` | First hop: `192.168.123.1`, second hop: `10.99.99.1` (RB4011), then to internet | |
| 2.2 | From travel LAN client: browse `whatismyip.com` | Shows the **home** public IP (not the hotel’s IP) | |
| 2.3 | From travel LAN client: `curl https://ipinfo.io` | IP matches the home router’s public IP, location matches home city | |

---

## 3. Kill‑Switch (Leak Prevention)

| # | Test | Expected Result | ✓ |
|---|------|-----------------|---|
| 3.1 | On hAP ac²: `/interface wireguard disable wg-family` | WireGuard interface goes down | |
| 3.2 | From travel LAN client: `ping 1.1.1.1` | **Timeout** — no connectivity | |
| 3.3 | From travel LAN client: `ping 192.168.123.1` | Still works (router itself is reachable) | |
| 3.4 | From travel LAN client: browse `http://potovalni.vpn` | Hotspot page still loads (walled garden intact) | |
| 3.5 | On hAP ac²: `/interface wireguard enable wg-family` | VPN reconnects within 30s | |
| 3.6 | From travel LAN client: `ping 1.1.1.1` again | Ping recovers after VPN reconnects | |

---

## 4. WAN Failover

| # | Test | Expected Result | ✓ |
|---|------|-----------------|---|
| 4.1 | Both ether1 and wlan1 have internet-capable DHCP | On hAP ac²: `/ip route print where dst-address=0.0.0.0/0` | Two DHCP routes: distance=1 (ether1) and distance=2 (wlan1). WireGuard route (distance=1) is active. | |
| 4.2 | Unplug ether1 cable | `/ip route print` — ether1 DHCP route disappears, wlan1 route (distance=2) becomes the active WAN route for WG transport | |
| 4.3 | VPN still works after ether1 unplugged | From travel LAN: `ping 1.1.1.1` still succeeds | |
| 4.4 | Reconnect ether1 cable | `/ip route print` — ether1 route reappears with distance=1. WG transport switches back to ether1. | |
| 4.5 | Remove wlan1 DHCP (simulate no hotel Wi‑Fi) | ether1 route remains sole WAN route; VPN works over ether1 only | |

---

## 5. Captive Portal (Hotel Wi‑Fi Setup)

| # | Test | Expected Result | ✓ |
|---|------|-----------------|---|
| 5.1 | Connect phone/laptop to `Family-Traveling` | Wi‑Fi connects, IP in `192.168.123.x` range, DNS = `192.168.123.1` | |
| 5.2 | Open browser → `http://potovalni.vpn` | Hotspot login page loads (purple page, hotel icon, two fields) | |
| 5.3 | Enter a valid test SSID + password, click Connect | Page submits; wlan1 is configured with the new SSID | |
| 5.4 | Check `/log print where topics~"hotspot"` | Log entry: `Hotspot: wlan1 configured for SSID=<test-ssid>` | |
| 5.5 | Check `/interface wireless print where default-name=wlan1` | SSID matches the test SSID entered | |
| 5.6 | Check `/ip dhcp-client print where interface=wlan1` | DHCP client is enabled/running on wlan1 | |
| 5.7 | Enter empty SSID or password, click Connect | Login fails (no wlan1 reconfiguration). Error log entry appears. | |
| 5.8 | No internet connection on the travel AP | `http://potovalni.vpn` still resolves to `192.168.123.1` (local DNS works) | |

---

## 6. DNS

| # | Test | Expected Result | ✓ |
|---|------|-----------------|---|
| 6.1 | From travel LAN client: `nslookup potovalni.vpn` | Resolves to `192.168.123.1` | |
| 6.2 | From travel LAN client: `nslookup home.kogler.si` | Resolves to `10.10.1.1` (home DNS server) | |
| 6.3 | From travel LAN client: `nslookup nas.lan` | Query is forwarded to home DNS → resolves to `10.10.1.2` (if set) | |
| 6.4 | From travel LAN client: `nslookup google.com` | Resolves via 1.1.1.1 (through VPN) | |
| 6.5 | hAP ac² own DNS: `/ip dns cache print` | Cache has entries for resolved queries | |

---

## 7. IPv6 (if available)

| # | Test | Expected Result | ✓ |
|---|------|-----------------|---|
| 7.1 | On hAP ac²: `/ipv6 dhcp-client print` (if WAN provides IPv6) | DHCPv6 client gets a prefix | |
| 7.2 | IPv6 traffic from LAN client follows kill‑switch | If VPN is down, IPv6 traffic from LAN is dropped | |
| 7.3 | IPv6 website (e.g. `ipv6.google.com`) loads from travel LAN | If IPv6 is available through the VPN, it works | |

---

## 8. Security

| # | Test | Expected Result | ✓ |
|---|------|-----------------|---|
| 8.1 | Scan RB4011 public IP: `nmap -p <WG_LISTEN_PORT> <home-ip>` | WireGuard port is open (UDP shows `open|filtered`) | |
| 8.2 | Scan RB4011: `nmap -p 22,80,443,8291,8728 <home-ip>` | All TCP ports show `filtered` or `closed` (no management exposed) | |
| 8.3 | From outside: try connecting to `Family-Traveling` Wi‑Fi without password | Connection rejected (WPA2‑PSK enforced) | |
| 8.4 | Attempt WinBox from hotel network to travel AP WAN IP | Connection fails (input drop from WAN) | |

---

## Summary

| Section | Requirement | Status |
|---------|------------|--------|
| 1 | WireGuard tunnel up | ⬜ |
| 2 | Full‑tunnel routing | ⬜ |
| 3 | Kill‑switch works | ⬜ |
| 4 | WAN failover | ⬜ |
| 5 | Captive portal | ⬜ |
| 6 | DNS forwarding | ⬜ |
| 7 | IPv6 (optional) | ⬜ |
| 8 | Security | ⬜ |

All boxes checked? ✅ The configuration is ready for travel! 🌍