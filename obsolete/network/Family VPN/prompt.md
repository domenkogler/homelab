# Family VPN Setup – MikroTik WireGuard with Travel AP & Captive Portal

**Role:** Senior network engineer (RouterOS specialist).  
**Task:** Provide a complete, deployable configuration for a family VPN using two MikroTik routers. Your answer must contain:

1. **All RouterOS CLI commands** – step by step, with brief inline explanations.  
2. **A user‑friendly setup guide** – non‑technical, aimed at family members (spouse/kids).  
3. **A testing checklist** – to verify every requirement.

---

## 1. Goal

Create a **full‑tunnel WireGuard VPN** between the **home** (RB4011) and a **travel access point** (hAP ac²).  
All internet traffic from the travel LAN must exit through the home router.  
The travel AP must be **easy to operate** – especially connecting to hotel Wi‑Fi – using a built‑in captive portal.

---

## 2. Network Topology & Hardware

```
                             ┌─────────────────────────────────────────┐
                             │              INTERNET                   │
                             └─────┬───────────┬───────────────────────┘
                                   │           │
                   (PPPoE – DDNS endpoint)  (hotel network – ether1 or hotel Wi‑Fi)
                                   │           │
                           ┌───────▼────┐  ┌───▼─────────────────────┐
                           │  RB4011    │  │  hAP ac²  (Travel AP)   │
                           │  (Home)    │  │   WAN1: ether1 (primary)│
                           │  LAN:      │  │   WAN2: wlan1 (station) │
                           │ 10.10.1.0/│  │   LAN: bridge‑trusted   │
                           │    24      │  │         192.168.123.0/24│
                           └────────────┘  │   Wi‑Fi: "Family‑Travel"│
                                           │        (5 GHz)          │
                                           └─────────────────────────┘
```

- **Home router** – MikroTik RB4011, RouterOS v7 (upgraded to latest stable).  
  - Internet via **PPPoE** (ISP assigns a static IP), but the WireGuard endpoint uses the **MikroTik Cloud DDNS hostname** (`/ip cloud ddns-enabled=yes`) for reliability.  
  - LAN subnet: `10.10.1.0/24`, gateway `10.10.1.1`  
  - Baseline config provided as `rb4011.rsc`. **Important:** all existing WireGuard interfaces/peers, netwatch entries, cloud Back‑to‑Home, and firewall rules will be **purged** and rebuilt from scratch to avoid conflicts with the old back‑to‑home VPN.

- **Travel AP** – MikroTik hAP ac², RouterOS v7 (upgraded to latest stable).  
  - **First‑time setup:** connect `ether1` to the home LAN temporarily to obtain internet access for the RouterOS upgrade.  
  - **Dual WAN** (active/passive):
    - `ether1` (primary) – DHCP client, wired connection e.g. in a hotel room  
    - `wlan1` (secondary) – 2.4 GHz radio configured as **station** to join hotel Wi‑Fi  
  - **LAN** – bridge named `bridge-trusted`, subnet `192.168.123.0/24`, gateway `192.168.123.1`  
  - **Wi‑Fi** – 5 GHz radio, SSID `Family-Traveling`, WPA2‑PSK (key you will define)  
  - Baseline config provided as `hap-ac2.rsc`

The two attached `.rsc` files contain the current, factory‑like configs. You must build upon them without breaking any existing necessary functionality.

---

## 3. Detailed Requirements

### A. WireGuard VPN Tunnel
- Establish a site‑to‑site WireGuard tunnel between the RB4011 (server) and hAP ac² (client).  
- Tunnel subnet: `10.99.99.0/31` (RB4011 `.1`, hAP ac² `.2`).  
- Pre‑shared keys and private/public keys must be generated; include the exact commands.  
- The tunnel must be **always up** and should survive WAN disconnections.

### B. Routing – Full Tunnel
- All traffic from the travel LAN (`192.168.123.0/24`) **must exit to the internet via the home router**.  
  - On the travel AP, set a default route (`0.0.0.0/0`) pointing to the WireGuard interface.  
  - On the home router, masquerade traffic from `192.168.123.0/24` and from `10.10.1.0/24` as needed.  
- Dual‑stack (IPv4 only for this setup).

### C. Kill‑Switch (Leak Prevention)
- On the travel AP, **firewall rules must drop all traffic** from `bridge-trusted` (LAN) that is **not** leaving through the WireGuard interface.  
- Even if the default route disappears, no packet from the LAN should ever reach the public WAN interfaces directly.  
- The kill‑switch must not break the travel AP’s own management connectivity (e.g., WinBox, SSH) – but access to those services should only be possible from the LAN or over the VPN.

### D. WAN Failover – `ether1` Primary, Hotel Wi‑Fi Secondary
- The travel AP must automatically prefer `ether1` as the outgoing WAN link when an Ethernet cable is connected and gets an IP.  
- If `ether1` has no link, the device should use the Wi‑Fi station (`wlan1`) connection as its WAN.  
- Implementation hint: use **different route distances** (e.g., `distance=1` for ether1 DHCP, `distance=2` for wlan1 DHCP). No need for complex netwatch scripts.

### E. Travel AP Captive Portal – Hotel Wi‑Fi Configuration
The travel AP must provide a **simple, family‑friendly way** to connect to hotel Wi‑Fi without needing WinBox or SSH. The requirement is to **use MikroTik’s built‑in Hotspot** with a custom login page.

**How it must work:**
1. Any wireless client (phone/laptop) connected to `Family-Traveling` opens a browser.  
2. They are automatically redirected to the **Hotspot login page** at `http://potovalni.vpn` (local domain).  
3. The login page shows two fields:  
   - “Hotel Wi‑Fi name”  
   - “Hotel Wi‑Fi password”  
   and a **“Connect”** button.  
4. The user enters the hotel’s SSID and WPA2 key and clicks Connect.  
5. The router **applies** those settings to the `wlan1` station interface (security profile, SSID, triggers DHCP).  
6. After a successful configuration, the user should see a confirmation page, and normal internet works (provided the hotel Wi‑Fi accepts the connection).

**Implementation details (you must figure out the exact RouterOS mechanics):**
- The Hotspot is active on `bridge-trusted`.  
- The login method should be **HTTP-PAP** (or another that passes `$user` and `$password` to a login script).  
- You must create a **Hotspot login script** (`on-login` with `use-user-details=yes`) that:
  - Receives the hotel SSID as `$user` and hotel password as `$password`.
  - Updates the `wlan1` security profile and SSID.
  - Enables the DHCP client on `wlan1` (or re‑enables it with a longer renewal).
  - Logs a message and returns `$ok = true` to let the user pass the Hotspot (the “authentication” is just for data entry, not real AAA).
- The login page must be customised (replace `login.html`) with clear labels and a friendly design.
- The router’s own DNS must resolve `potovalni.vpn` to `192.168.123.1` so the browser redirect works even when no internet is available.

### F. DNS Configuration
- The travel AP’s DHCP server hands out `192.168.123.1` as the DNS server to LAN clients.
- The router’s built‑in DNS must:
  - Forward all queries for a **home domain** (e.g., `.home.kogler.si` or just `home`) to the home router’s DNS at `10.10.1.1` **through the VPN**.
  - All other queries can be resolved via a public resolver (configurable, e.g., 1.1.1.1), also reachable over the VPN (so they go through the home exit).
  - Cache results for performance.

### G. Family‑Friendly / Ease of Use
- The whole solution must require **zero technical knowledge** after initial setup.  
- A printed card can stay in the travel bag: “Connect to Wi‑Fi `Family-Traveling`, open a browser, type hotel Wi‑Fi name and password, done.”  
- The user guide you produce must be written in a simple, encouraging tone suitable for a non‑technical spouse or older child.

---

## 4. Constraints & Assumptions

- **RouterOS version**: 7.x (latest stable). Both routers must be **upgraded to the latest stable RouterOS 7.x** before applying the new configuration. The hAP ac² needs a temporary wired connection to the home LAN (`ether1` → home bridge) to download the update. No Docker, no external VPS, no additional hardware.
- **RB4011 clean slate:** All existing WireGuard interfaces/peers, `/ip cloud` Back‑to‑Home, `/tool netwatch` WireGuard entries, and `/ip firewall filter` + `/ip firewall nat` rules will be **deleted** and rewritten. Other config (CAPsMAN, DHCP leases, bridges, PPPoE, IPv6) is preserved.
- The `rb4011.rsc` and `hap-ac2.rsc` files are the current state of each device. For RB4011 only the areas listed above are wiped; for hAP ac² the config is nearly factory‑default so most configuration is built from scratch.
- **IPv6:** The home router has IPv6 via PPPoE prefix delegation. The travel AP **may pass IPv6 from the travel LAN through the VPN** if the upstream hotel network provides it. Firewall and kill‑switch rules must handle IPv6 traffic so it follows the same full‑tunnel policy. If IPv6 is unavailable through the VPN, travel‑LAN IPv6 traffic should be dropped.
- The hAP ac²'s radios: 2.4 GHz (`wlan1`) will be used as a **station** (5 GHz optional). 5 GHz (`wlan2`) will host the `Family-Traveling` AP. If the .rsc shows a different setup, adapt accordingly.
- The captive portal must work without any internet connection (first‑time hotel setup). `potovalni.vpn` is a **local‑only** hostname.
- Security: Use WPA2‑PSK for both the home AP and the travel LAN AP (passphrases provided as variables by the user).
- All internet traffic from the travel LAN is routed through the home router – no split tunneling.

---

## 5. Requested Deliverables

Produce your answer in three clearly separated parts:

### Part 1 – RouterOS CLI Commands
For **both routers**, provide the exact CLI commands, in order, with a short explanation after each block.  
Use `\` line continuations for readability.  
Include:
- WireGuard key generation and peer setup.
- IP address assignments, interfaces, firewall rules, NAT, routing.
- Hotspot server, user‑profile, login script, custom HTML (you can paste the entire `login.html` content inside a script that uploads it, or use the `/file` command).
- DNS static entries, forwarding rules.
- Any scripts that run on boot or on Hotspot events.

### Part 2 – User Guide (Family‑Friendly)
A step‑by‑step guide written for a **non‑technical user** (like a 14‑year‑old). It should cover:
- How to connect to the `Family-Traveling` Wi‑Fi.
- How to set up hotel Wi‑Fi using the captive portal (with screenshots described in words).
- What to do if it doesn’t work (basic troubleshooting: “Check if the hotel’s Wi‑Fi name and password are correct”, “Try connecting a cable to ether1 first”, etc.).
- How to see if the VPN is working (e.g., visiting whatismyip.com should show the home’s IP).

### Part 3 – Testing Checklist
A list of concrete tests one can run to validate every requirement, for example:
- Ping from travel LAN client to `10.10.1.1`.
- Traceroute from travel LAN client to the internet shows home router as first hop after the AP.
- Disconnect the WireGuard tunnel on the travel AP and verify that LAN clients lose all connectivity.
- Plug in ether1 on travel AP with an internet‑capable DHCP, verify it takes precedence over a connected hotel Wi‑Fi.
- Open browser, go to `potovalni.vpn`, enter arbitrary hotel SSID/password, verify that the station connects (check logs/status).
- Verify DNS resolution of `.home.kogler.si` names from the travel LAN.

---

## 6. Additional Notes

- The key challenge is the **captive portal integration with station reconfiguration**. Spend time designing a clean, reliable script.  
- The `on-login` script must handle the case where `$user` or `$password` are empty – log an error and reject the login.  
- Make sure the kill‑switch does not break communication between the Hotspot and the LAN client (the Hotspot’s web UI must still be reachable even when VPN is down, but the LAN client should not get internet – so the walled garden for the Hotspot server must be allowed).  
- All commands should be **idempotent** where possible – they can be re‑run without breaking things.