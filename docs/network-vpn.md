# VPN & Remote Access

> **Role:** Detail — VPN layers, Headscale mesh, remote access. (Travel router obsolete.)
> **Links to:** `network.md`, `hardware-oldsrv.md`
> **Linked from:** `network.md`, `index.md`

---

## Three VPN Layers

| Layer | Technology | Endpoint | Purpose |
|-------|-----------|----------|---------|
| **Site-to-Site** | WireGuard (native RouterOS) | RB4011 ↔ VPS | Home LAN ↔ VPS services, always on |
| **Road-Warrior** | WireGuard (native RouterOS) | RB4011, port 13231 | Phones/laptops to home (legacy/migration) |
| **Mobile Mesh** | **Headscale** (self-hosted Tailscale) | Home server Docker | Family phones — easier app, wife-friendly |

> **Strategy:** WireGuard stays for site-to-site. Headscale replaces WireGuard road-warrior for family mobile devices. Headscale traffic goes through the site-to-site WireGuard tunnel to reach VPS services.

---

## Layer 1: Site-to-Site (Home ↔ VPS)

- **Home RB4011:** `10.255.40.1/30`
- **VPS WireGuard endpoint:** `10.255.40.2/30`
- Always on, no on-demand
- Home router: static route `10.255.20.0/24 → via 10.255.40.2`
- VPS: route `10.10.0.0/16 → via 10.255.40.1`

---

## Layer 2: Headscale (Mobile Mesh)

- Runs on home server as Docker container
- Default overlay subnet: `100.64.0.0/10`
- Clients: Android/iOS Tailscale app, laptops
- On RB4011: static route + firewall rules so `100.64.0.0/10` reaches `10.10.1.0/24`
- Headscale traffic to VPS goes through site-to-site WireGuard

### Transition Plan
1. Deploy Headscale on home server
2. Migrate family one-by-one from WireGuard to Tailscale app
3. Keep WireGuard road-warrior as fallback

---

## Layer 3: Travel Router

> **⚠️ OBSOLETE — SUPERSEDED BY HEADSCALE (Layer 2).** The travel-router approach is retained
> here only for reference; it is **not** the supported path. Use the Tailscale/Headscale app instead.
> The hAP ac² used for this is now treated as a **spare AP**.

### Device
- **MikroTik hAP ac²** (existing spare)

### Network
| Interface | Role |
|-----------|------|
| `ether1` | Primary WAN (DHCP client, wired hotel) |
| `wlan1` (2.4 GHz) | Secondary WAN (station mode, hotel Wi-Fi) |
| `bridge-trusted` | LAN: `192.168.123.0/24`, gateway `192.168.123.1` |
| `wlan2` (5 GHz) | Family SSID: "Family-Traveling" (WPA2-PSK) |

### Dual WAN (Active/Passive)
- `ether1` DHCP: route distance = 1 (preferred)
- `wlan1` DHCP: route distance = 2 (fallback)

### Kill-Switch
- Firewall drops all traffic from `bridge-trusted` not exiting via WireGuard interface
- If VPN goes down → LAN clients lose internet (no leak to hotel WAN)

### WireGuard Tunnel
- Site-to-site between travel hAP ac² and home RB4011
- Tunnel subnet: `10.99.99.0/31` (travel: `.2`, home: `.1`)
- Full tunnel: `AllowedIPs = 0.0.0.0/0`

### Captive Portal (Hotel Wi-Fi)
- Family connects to "Family-Traveling" → opens `http://potovalni.vpn` → enters hotel Wi-Fi credentials
- Uses MikroTik Hotspot with custom `login.html` and `on-login` script
- **⚠️ NOT YET PROTOTYPED** — highest technical risk
- Hotel captive portal workaround: connect phone directly to hotel Wi-Fi first, accept portal, then switch to travel router

### Fallback
If travel router doesn't work reliably: use Headscale on individual devices.

---

## DNS on Travel Router

| Domain | Resolves via |
|--------|-------------|
| `potovalni.vpn` | Local static DNS → `192.168.123.1` |
| `*.kogler.si` | Forwarded through VPN → home DNS |
| Everything else | Public resolver (1.1.1.1), through VPN |

---

## Family Usage Scenarios

| Situation | How to Connect |
|-----------|---------------|
| **At home** | "Kogler" SSID, `kogler.si` dashboard |
| **Traveling** | Tailscale app → tap Connect (mobile mesh) |
| **Remote (anywhere)** | Tailscale → access Immich, OpenCloud, HA |