You work as a systems and network engineer. I am asking for a detailed, step-by-step technical plan, RouterOS v7 CLI commands, and Docker Compose configurations to set up a family "Road Warrior" VPN system.

## Phase 1: Site-to-Site WireGuard VPN

### 1. Context and network topology:
**Home router (RB4011):** Has a static public IP with an associated domain (vpn.kogler.si). Home LAN IP space is 10.10.1.0/24. Attached find `rb4011.rsc` for config. Start with this config.

**Travel AP (MikroTik hAP ac2):** Uses a secure local subnet 192.168.123.0/24. The router's location IP is 192.168.123.1. Attached find `hap-ac2.rsc` for config. Start with this config.

**Home Homelab server:** Runs Docker (will be used in Phase 2).

### 2. Technical requirements for Phase 1 (travel AP and RB4011 - Fixed WireGuard):

**2a. Establish a permanent WireGuard connection (Site-to-Site)** between the home RB4011 and the travel AP. Traffic between 10.10.1.0/24 and 192.168.123.0/24 must be full-duplex and pass-through.

**2b. Create a Trusted Bridge (`bridge-trusted`)** on the travel AP that combines:
- Virtual AP (local WiFi SSID for the family, e.g. "Family-Traveling")
- Ports ether3, ether4, and ether5
- This bridge assigns IPs from the range 192.168.123.0/24

**2c. Port ether2** should be bridged with ether1 (WAN) for direct access to the hotel network without VPN (for devices that do not need a home network).

**2d. Wife-Friendly feature (Splash / Captive Portal with static name):** 
- Enable settings/script for a simple travel web portal on the travel AP for entering the hotel WiFi password
- In RouterOS DNS, set a static rule so that entering the domain `potovalni.vpn` in the browser automatically opens this interface (without entering the IP address)

**2e. Security (Kill-Switch):** If the WireGuard tunnel fails, the firewall on the travel AP must not let traffic from the `bridge-trusted` unprotected to the public hotel internet.

## Phase 2: Headscale (Tailscale) for Mobile Devices

**Important: This phase should be implemented AFTER Phase 1 is verified working.**

### 3. Technical requirements for Phase 2 (Homelab - Headscale):

**3a. Prepare a `docker-compose.yml` file** for setting up Headscale and the associated web interface (Headscale-UI) for easier management of individual devices (e.g., phones on the go).

**3b. On the home RB4011**, set up a static route and firewall rules so that traffic from the Headscale network (default 100.64.0.0/10) can access the home LAN (10.10.1.0/24) without any problems.

### 4. Required outputs:

**4a. Clean and commented CLI code** for:
- Home RB4011 (RouterOS v7)
- Travel AP (RouterOS v7)

**4b. Docker Compose file** and basic instructions for starting the Headscale environment.

**4c. FAMILY USER GUIDE** (Print-friendly, in plain Slovenian language):

**Part 1:** How to turn on the travel AP in the hotel, open the `potovalni.vpn` page on the phone, and connect it to the hotel WiFi