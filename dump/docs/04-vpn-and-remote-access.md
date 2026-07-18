# VPN & Remote Access

> **Canonical doc.** Merges: `Road warrior plan.md`, `potovalni vpn prompt.md`, `potovalni.vpn.md`, VPN sections from `Home Lab & Family Network Architecture.md`.

---

## Three VPN Layers

| Layer | Technology | Endpoint | Purpose |
|-------|-----------|----------|---------|
| **Site-to-Site** | WireGuard (native RouterOS) | RB4011 ↔ VPS | Home LAN ↔ VPS services, always on |
| **Road-Warrior** | WireGuard (native RouterOS) | RB4011, port 13231 | Phones/laptops to home (legacy/migration) |
| **Mobile Mesh** | **Headscale** (self-hosted Tailscale) | Home server Docker | Family phones — easier app, wife-friendly |

> **Strategy:** WireGuard stays for site-to-site (router-level, permanent). Headscale replaces WireGuard road-warrior for **family mobile devices** — simpler app, auto-reconnect, easier to maintain if Domen is incapacitated. Headscale traffic goes **through the site-to-site WireGuard tunnel** to reach VPS services.

---

## Layer 1: Site-to-Site (Home ↔ VPS)

### Tunnel
- **Home RB4011:** `10.255.40.1/30`
- **VPS WireGuard endpoint:** `10.255.40.2/30`
- Always on, no on-demand

### Routing
- Home router: static route `10.255.20.0/24 → via 10.255.40.2` (reach VPS services)
- VPS: route `10.10.0.0/16 → via 10.255.40.1` (reach home, backup destinations, DNS)

---

## Layer 2: Headscale (Mobile Mesh)

### Server
- Runs on home server Docker (Proxmox LXC: `docker-host`)
- Web UI: **Headscale-UI** for managing devices
- Default overlay subnet: `100.64.0.0/10`

### Clients
- Android phones (Tailscale app from Play Store)
- iOS devices (Tailscale app)
- Laptops

### Routing to Home LAN
- On RB4011: static route + firewall rules so Headscale subnet (`100.64.0.0/10`) reaches `10.10.1.0/24`
- Headscale traffic to VPS services goes through the site-to-site WireGuard tunnel

### Why Headscale for Family
- **Tailscale app** is dead simple — on/off toggle, no config files
- Auto-reconnects after network changes
- No need to manage WireGuard peer keys per device
- "Wife-friendly" == open app, tap connect, done
- Works even without the travel router (phones directly)

### Transition Plan
1. Family currently uses WireGuard on phones
2. Deploy Headscale on home server
3. Migrate family one-by-one to Tailscale app
4. Keep WireGuard road-warrior server running as fallback

---

## Layer 3: Travel Router

### Device
- **MikroTik hAP ac²** (existing spare — no new purchase)

### Network
| Interface | Role |
|-----------|------|
| `ether1` | Primary WAN (DHCP client, wired hotel connection) |
| `wlan1` (2.4 GHz) | Secondary WAN (station mode, connects to hotel Wi-Fi) |
| `bridge-trusted` | LAN: `192.168.123.0/24`, gateway `192.168.123.1` |
| `wlan2` (5 GHz) | Family SSID: "Family-Traveling" (WPA2-PSK) |

### Dual WAN (Active/Passive)
- `ether1` DHCP: route distance = 1 (preferred)
- `wlan1` DHCP: route distance = 2 (fallback)
- No netwatch scripts needed — route distance handles it

### Kill-Switch
- Firewall drops all traffic from `bridge-trusted` that does **not** exit through WireGuard interface
- If VPN goes down → LAN clients lose internet completely (no leak to hotel WAN)
- Management access (WinBox/SSH) still reachable from LAN side

### WireGuard Tunnel
- Site-to-site between travel hAP ac² and home RB4011
- Tunnel subnet: `10.99.99.0/31` (travel AP: `10.99.99.2`, home: `10.99.99.1`)
- Full tunnel: all internet traffic exits through home router (`AllowedIPs = 0.0.0.0/0`)

### Captive Portal — Hotel Wi-Fi Setup

The travel router provides a **family-friendly web interface** to connect to hotel Wi-Fi without WinBox or SSH.

**How it works (intended):**
1. Connect phone/laptop to `Family-Traveling` SSID
2. Open browser → visits `http://potovalni.vpn` (local DNS resolves to `192.168.123.1`)
3. Simple page: "Hotel Wi-Fi name" + "Hotel Wi-Fi password" + "Connect" button
4. Router applies settings to `wlan1` station, connects

**Implementation:** Uses MikroTik built-in Hotspot on `bridge-trusted` with:
- Custom `login.html` (Slovenian-language, friendly design)
- `on-login` script (HTTP-PAP, `use-user-details=yes`) that reconfigures `wlan1`
- Static DNS: `potovalni.vpn` → `192.168.123.1`

**⚠️ Status:** NOT YET PROTOTYPED — this is the highest technical risk component.

### Hotel Captive Portals (the double-hop problem)
If the hotel Wi-Fi itself has a captive portal:
1. Connect **phone directly** to hotel Wi-Fi first
2. Accept hotel's captive portal on the phone
3. Then connect phone to `Family-Traveling` and use the travel router normally

This limitation must be documented in the family guide.

### Fallback
If Sploax/KORP captive portal doesn't work reliably: **use Headscale** on individual devices instead. This is the backup plan.

---

## DNS on Travel Router

| Domain | Resolves via |
|--------|-------------|
| `potovalni.vpn` | Local static DNS → `192.168.123.1` |
| `*.home.kogler.si` | Forwarded through VPN → home DNS at `10.10.1.1` |
| Everything else | Public resolver (1.1.1.1), through VPN tunnel |

- Travel DHCP hands out `192.168.123.1` as DNS to LAN clients
- Router caches results for performance

---

## VPN Topology Summary

```
┌─────────────┐    WireGuard S2S     ┌──────────────┐
│  Home LAN   │◄───────────────────►│  Cloud VPS    │
│ 10.10.x.0   │  10.255.40.0/30     │ 10.255.20.0   │
└──────┬──────┘                      └──────────────┘
       │
       │ WireGuard S2S (full tunnel)
       │
┌──────▼──────┐                      ┌──────────────┐
│ Travel hAP  │     Headscale        │ Family Phones│
│ 192.168.123 │◄────────────────────│ (Tailscale    │
│ (Sploax)    │   100.64.0.0/10     │  app)         │
└─────────────┘                      └──────────────┘
```

---

## Family Usage Scenario

| Situation | How to Connect |
|-----------|---------------|
| **At home** | Connect to "Kogler" SSID — everything local |
| **Traveling with router** | Plug in travel router, connect phone to "Family-Traveling", open `potovalni.vpn` to set hotel Wi-Fi |
| **Traveling without router** | Open Tailscale app on phone → tap Connect → access home services |
| **Remote (no travel)** | Open Tailscale app → Connect → access Immich, OpenCloud, Home Assistant |