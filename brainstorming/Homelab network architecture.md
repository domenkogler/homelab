# Home Lab & Family Network Architecture: Full Deliverables

Below is a comprehensive, structured response to your request. It covers all eight deliverables: an audit of the current configuration, a zero‑budget re‑design, an enhanced architecture with a € 1000 bill of materials, a cloud VPS design, a management strategy, a VPN plan, a parental control solution, and a detailed migration plan.

Each section includes diagrams, tables, and configuration snippets where critical. For readability, some longer code blocks are placed inside collapsible `<details>` sections – **click to expand**.

---

## 1. Audit of Current `rb4011_config.rsc`

**Conclusion:** The configuration is a typical “grown organically” home setup. It functions but has several security and design weaknesses. A **clean slate is advisable** for the new segmented architecture, though many individual settings can be reused.

### 🔍 Key Findings

| Issue | Severity | Explanation |
|-------|----------|-------------|
| **No inter‑VLAN isolation** | 🔴 High | The main `bridge` (10.10.1.0/24) and `bridge‑guest` (10.10.250.0/24) have no firewall rules preventing traffic between them. Traffic from guest to home is currently allowed. |
| **IPv6 partially disabled but still active** | 🟠 Medium | `ipv6 settings disable-ipv6=yes` contradicts the presence of IPv6 addresses, DHCP client, and firewall rules. Either fully enable or fully remove IPv6. |
| **Conflicting IP on WAN interface** | 🟠 Medium | `ether1` has both a static IP `192.168.1.2/24` *and* a PPPoE client. The static IP is probably a leftover from a previous modem management setup and can cause routing loops. |
| **Disabled / orphaned entries** | 🟡 Low | Several routes, a bridge (`bridge-rti`), and some NAT rules are disabled; these clutter the config and may be accidental. |
| **Unused RADIUS / User‑Manager** | 🟡 Low | RADIUS and User‑Manager are enabled but the only (local) users are for network devices that likely don’t authenticate via 802.1X. This adds attack surface without benefit. |
| **DHCP server with small lease time** | 🟡 Low | `lease-time=10m` on the main DHCP is very short; for a mostly static home it is fine but can cause unnecessary renewal traffic. |
| **No DNS filtering / parental controls** | 🟡 Low | DNS is just forwarded to 1.1.1.1 and 8.8.8.8; no filtering for children. |
| **OVPN server with weak authentication** | 🔴 High | `auth=sha1,md5` – SHA1 and MD5 are broken; if the server is used, it must be upgraded to `sha256` or stronger. |
| **NTP source‑rewrite without need** | 🟡 Low | `ip firewall nat add action=src-nat ... to-addresses=10.10.1.1` for NTP is unusual; it forces all local NTP clients to use the router, but the router is already an NTP server – the rule can be removed. |
| **WireGuard peers not shown** | ℹ️ Info | The config lacks `/interface wireguard` entries, but netwatch scripts reference them. They were likely added manually and not exported. This must be re‑done explicitly. |

### ✅ What’s already done well

- PPPoE correctly set up with `add-default-route`.
- Basic stateful firewall (fasttrack, established/related).
- CAPsMAN with dynamic provisioning for APs.
- DHCP leases for static “known” devices (Shelly IoT, Gira KNX, etc.), which helps with migration.
- NTP and DNS services enabled on the router.

### Verdict

The existing configuration is **usable as a starting point** for re‑building, but you should **discard the entire bridge‑based flat layout** and re‑create a VLAN‑centric design. The firewall rules and CAPsMAN configurations can be partially recycled after an overhaul.

---

## 2. Proposed Home Network Architecture (€ 0 Budget)

Uses only existing hardware: RB4011iGS+ router, CRS328-24P-4S+ switch, two installed APs (hAP ac, hAP ac²) and one spare (hAP ac²), plus the Raspberry Pi 4 (Home Assistant).

### 💡 Core Design Change: Move from multiple bridges to a single VLAN‑aware bridge

All wired ports and CAPsMAN wireless traffic will be carried over **VLANs on a common bridge** (`bridge`). This gives us:

- Centralised VLAN definition on the router.
- Trunk port to the CRS328 switch (SFP+ port).
- SSID‑to‑VLAN mapping via CAPsMAN.
- Clean inter‑VLAN routing controlled by firewall rules.

### 🧱 VLAN & Subnet Plan

| VLAN ID | Name            | Subnet           | Purpose                         | Devices / SSIDs                     |
|---------|-----------------|------------------|---------------------------------|--------------------------------------|
| 1       | Management      | 10.10.99.0/24    | Router, switch, AP management   | CAPsMAN, switch IP                   |
| 10      | Home             | 10.10.1.0/24     | Trusted family devices, servers  | “Kogler” SSID, wired PCs, HA, NAS   |
| 20      | IoT              | 10.10.20.0/24    | Smart‑home (isolated)           | “Kogler IOT” SSID, KNX, Shelly      |
| 30      | Guest            | 10.10.30.0/24    | Internet‑only, client isolation  | “Kogler guest” SSID                  |
| 40      | Kids             | 10.10.40.0/24    | Filtered DNS, restricted access  | (future dedicated SSID)              |

**Note:** The existing “bridge‑guest” and separate “10.10.250.x” will be removed. All IPs are re‑numbered for clarity.

### 🧱 Router Configuration (Logical)

**Physical layout:**
- `ether1` → ISP ONT (PPPoE)
- `sfp-sfpplus1` → trunk to CRS328 switch (VLANs 1,10,20,30,40 tagged, optionally untagged PVID for management)
- `ether2`–`ether10` (if used) → set as access ports with appropriate PVIDs, or all on trunk to a central switch.

We will **keep the switch as a simple layer‑2 device** – all inter‑VLAN routing happens on the RB4011.

### 🧠 Firewall Logic (Inter‑VLAN)

Default‑deny forwarding between VLANs, with specific exceptions:

| Source VLAN | Destination VLAN | Rule                                                            |
|-------------|-----------------|-----------------------------------------------------------------|
| **Home** (10) | **IoT** (20)     | Accept established/related (return traffic) + new from trusted IPs for MQTT/HA control |
| **Home** (10) | **Management** (1) | Accept for SSH/WinBox/HTTPS (maintenance)                       |
| **IoT** (20)   | **Home** (10)    | **Drop all** (only allow replies to Home‑initiated)             |
| **Guest** (30) | any LAN           | **Drop all** (only allow internet)                              |
| **Kids** (40)  | **Home** (10)    | Drop, force DNS through filter, limited access                  |
| All             | WAN               | Allowed (masqueraded)                                          |

These rules will be implemented with **address‑lists** and **interface lists** inside RouterOS.

<details>
<summary><strong>🔧 Click to expand – Key RouterOS config snippets (€ 0 design)</strong></summary>

```routeros
# ---------------- Bridge & VLAN setup ----------------
/interface bridge
add name=bridge vlan-filtering=yes

# Physical ports – everything to bridge, enable VLAN filtering
/interface bridge port
add bridge=bridge interface=sfp-sfpplus1  # trunk
add bridge=bridge interface=ether2 pvid=10  # example access ports
...

# Create VLAN interfaces on the bridge for each subnet
/interface vlan
add interface=bridge name=vlan1 vlan-id=1
add interface=bridge name=vlan10 vlan-id=10
add interface=bridge name=vlan20 vlan-id=20
add interface=bridge name=vlan30 vlan-id=30

# IP addresses – one per VLAN (no address on the physical bridge itself)
/ip address
add address=10.10.99.1/24 interface=vlan1
add address=10.10.1.1/24 interface=vlan10
add address=10.10.20.1/24 interface=vlan20
add address=10.10.30.1/24 interface=vlan30

# DHCP servers per VLAN (use the respective VLAN interface as gateway)
/ip dhcp-server
add address-pool=dhcp-pool-MGMT interface=vlan1 name=dhcp-mgmt
...
```

</details>

### 📶 Wireless (CAPsMAN)

- **cfg_kogler** → `vlan-id=10` (Home)
- **cfg_Kogler-IOT** → `vlan-id=20` (IoT, keep existing but change bridge → `bridge` with vlan-id)
- **cfg_Kogler-guest** → `vlan-id=30` (Guest)
- (Optional) **cfg_kogler-kids** → `vlan-id=40`

All CAPsMAN configurations use **local‑forwarding=no** so that all traffic is tunneled back to the central CAPsMAN manager, but in our new design we can also use local forwarding if the datapath bridge is set correctly. For simplicity, I recommend keeping `local-forwarding=no` and letting the router bridge handle VLANs.

---

## 3. Enhanced Architecture with € 1000 Budget

### 💰 What the budget enables

The main addition is a **cloud VPS for external services** (Authentik, Pangolin, Immich, Git) and a **travel router**. We also add better monitoring and a dedicated DNS filter device, though most of those can be software.

### 🛒 Itemised Bill of Materials

| Item | Model / Provider | Cost (approx.) | Justification |
|------|------------------|----------------|-------------|
| **Cloud VPS (dedicated server, 1 year)** | Hetzner Server Auction: Intel Core i5-12500, 64 GB RAM, 2×512 GB NVMe, 1 Gbps unmetered | **€ 35/month** → **€ 420/year** | Proxmox VE with plenty of resources for all services and lab. Better than a shared VPS. |
| **Travel Router** | MikroTik mAP lite (RBmAPL-2nD) or reuse spare hAP ac² | **€ 30** (if purchased) | Tiny, USB‑powered, runs RouterOS; perfect as a portable WireGuard tunnel. |
| **Additional storage for VPS (backups)** | 1× 2 TB HDD or block storage (optional) | on‑demand ~€ 5/month | Backups of Immich photos and configs; not strictly required if you use the home NAS. |
| **DNS filtering device** | Raspberry Pi Zero 2 W + case | **€ 25** | Standalone AdGuard Home for kids VLAN; can also run on existing Pi 4. |
| **Uninterruptible Power Supply for VPS** | N/A – cloud provider’s SLA | € 0 | Cloud provides power. |
| **Remaining budget** | (if needed, a small managed PoE switch for the lab) | – | – |
| **Total** | | **~€ 500–€ 600** | Well within € 1000. |

<details>
<summary><strong>💡 Alternative: Cheaper VPS</strong></summary>

If you prefer a lower annual cost, you can use a **Hetzner CX43** VPS (4 vCPU, 16 GB RAM, 160 GB NVMe) at **€ 15.90/month** and install the required services via Docker/LXC *without* Proxmox. That would total **~€ 190/year**, leaving more budget for, say, a new Wi‑Fi 6 AP or a larger home lab switch. However, you explicitly requested Proxmox VE on the VPS, which requires a full hypervisor – the dedicated server is the safer, supported path.

</details>

### 🏠 Home Network Changes with the Budget

With the VPS in place, you can **offload the following services from home**:

- **Authentik** – identity provider
- **Pangolin** – (assumed WAF/reverse proxy)
- **Reverse proxy** (Traefik/Caddy)
- **Immich** – photo service
- **Git server** (Forgejo/Gitea)

**Home Assistant** and **network control** (CAPsMAN, DHCP, DNS) **remain on‑prem**. That keeps the core “internet working” even if the VPS goes down.

A **site‑to‑site WireGuard tunnel** connects the VPS to the home router. All VPS services are then accessible from home via private IPs (over the tunnel) and from the internet *only* through the Authentik‑protected reverse proxy.

### 🧳 Travel Router Integration

The mAP lite (or repurposed hAP ac²) is configured as a **WireGuard client** to the home router. Its built‑in Wi‑Fi broadcasts a local SSID; all traffic from connected devices is routed through the tunnel and out via your home’s static IP. This is the “Slovenian IP while abroad” solution.

---

## 4. Cloud VPS Networking Design

### 🖥️ Provider & Specs

**Recommended:** **Hetzner dedicated server** from their Server Auction (e.g., Intel Core i5-12500 or similar, 64 GB RAM, 2× NVMe).  
- **Why:** Full root access, KVM console, ability to install Proxmox VE directly.  
- **Bandwidth:** 1 Gbps guaranteed, unmetered (suits your home 1 Gbps).  
- **Monthly cost:** ~€ 35 (auction price).  

If dedicated is not in stock, use a **Hetzner cloud server (CX43)** but note that nested virtualisation is not officially supported; you would need to run services via LXC/Docker instead of full VMs.

### 🧱 Proxmox VE Network Plan

**External connectivity:** One public IP (IPv4 + IPv6).  
**Internal bridges:** Proxmox will have four Linux bridges:

| Bridge | Name     | CIDR (example)     | Purpose                       | Connected VMs/CTs         |
|--------|----------|--------------------|-------------------------------|---------------------------|
| vmbr0  | WAN      | public IP          | Internet‑facing reverse proxy | Traefik/Caddy VM         |
| vmbr1  | DMZ      | 10.255.10.0/24     | Web app firewall, reverse proxy | Pangolin (if separate)    |
| vmbr2  | Services | 10.255.20.0/24     | Internal apps (Authentik, Immich, Git) | Authentik, Immich, Git   |
| vmbr3  | Lab      | 10.255.30.0/24     | Isolated testing              | Lab VMs, no route to others |
| vmbr4  | Site2Site| 10.255.40.0/30    | Tunnel net to home router    | WireGuard endpoint on VPS |

**Firewall rules inside Proxmox:**
- By default **deny all** inter‑bridge traffic.
- Allow Services → DMZ (so reverse proxy can reach apps).
- Allow Services → WAN via proxy only (not directly).
- Allow Site2Site → Services (so home can reach them).
- Block Lab → all other bridges (strict isolation).
- Block all traffic from WAN except port 443 (HTTPS) to the DMZ reverse proxy.

These rules are implemented with Proxmox’s built‑in firewall (enabled per bridge).

### 🔗 VPN Integration (Home ↔ VPS)

A **WireGuard tunnel** is established between the RB4011 and the VPS. On the VPS side, a WireGuard container/VM acts as the end‑point. The tunnel IPs are:

- Home router: `10.255.40.1/30`
- VPS tunnel endpoint: `10.255.40.2/30`

Routing:
- On home router: static route `10.255.20.0/24 → via 10.255.40.2` (to reach VPS services).
- On VPS: route `10.10.0.0/16 → via 10.255.40.1` (so the VPS can reach home management or backup destinations).

This tunnel is **always on** (no on‑demand, it’s a permanent site‑to‑site link).

---

## 5. Management Strategy

### 🛠️ Recommendation: Layered approach

| Tool | Role | Justification |
|------|------|--------------|
| **MikroTik CAPsMAN** | Wireless AP management | Centralised SSID/VLAN configuration, easy GUI (WebFig/WinBox), zero‑touch provisioning for new APs. Already in use – just extend it. |
| **Ansible** (or plain scripts) | Router & switch config deployment | Define infrastructure‑as‑code; playbooks stored in Git alongside the configs. Ansible can generate `.rsc` files and push them via SSH. |
| **Git (Forgejo on VPS)** | Version‑controlled config store | All device configs (`rb4011.rsc`, `switch.rsc`, CAPsMAN export, Ansible playbooks) in one repo. Rollback is a `git revert` away. |
| **MikroTik The Dude** or **Zabbix** | Network monitoring (optional) | The Dude is free and runs on RouterOS. For a more modern, cross‑site setup, a Zabbix agent on the VPS can monitor both sites. |
| **Home Assistant** | User‑facing dashboard | Already the family’s “single pane of glass”. Add network entity cards for router status, VPN tunnels, and maybe traffic graphs. |

### 🔄 Workflow for changes

1. **Design** the change in a network diagram (draw.io or similar).
2. **Write** Ansible tasks or RouterOS script.
3. **Test** in a mini lab (maybe a CHR instance or on the spare hAP ac²).
4. **Commit** to Git and document.
5. **Apply** during a maintenance window (≤ 4 h).
6. **Verify** using The Dude or Home Assistant.

---

## 6. VPN Plan

### 🔐 Protocol Choice: WireGuard

- **Why WireGuard:** Simple, stateless, fast, and natively supported on MikroTik RouterOS (v7) and Linux (Proxmox). It also works perfectly on phones (Android, iOS) and travel routers.
- **No** legacy IPsec overhead; no need to manage DP disconnect and re‑keying fragile scripts (the netwatch scripts in the old config are a workaround for unstable links – WireGuard just stays up).

### Topology

```text
┌─────────────┐         WireGuard          ┌──────────────┐
│   Home LAN  │      site-to-site           │   Cloud VPS  │
│  (10.10.x.0)│  ┌───────────────────────┐   │  (10.255.20) │
│             │  │ 10.255.40.1/30 (home) │   │  10.255.40.2 │
└──────┬──────┘  └───────┬──────────────┘   └──────┬───────┘
       │                  │                            │
       │    WireGuard    │   WireGuard (road-warrior) │
       │   "road-warrior"│   phone/laptop clients     │
       │   (listening on │   (split-tunnel, auto)
       │    UDP 13231)   │                            │
       └─────────────────┘                            │
                           ┌─────────────┐           │
                           │ Travel mAP  │  WireGuard│
                           │ (client mode)│───────────┘
                           └─────────────┘
```

- **Site‑to‑site (home ↔ VPS):** dedicated WireGuard interface, always on, routed as above.
- **Road‑warrior (phones/laptops):** single WireGuard server on the home router (port 13231). Clients get a `/24` address from a pool (e.g., `10.255.200.0/24`). **Split‑tunnel** by default: only traffic to `10.10.0.0/16` goes via VPN; when on untrusted Wi‑Fi, a **full‑tunnel** profile is used (AllowedIPs = `0.0.0.0/0`). You can automate this with Tasker (Android) or Shortcuts (iOS) to detect SSID.
- **Travel AP:** mAP lite acts as a WireGuard client to the same road‑warrior server but with `AllowedIPs = 0.0.0.0/0`. Its wireless interface is bridged, and all traffic is NAT‑ed out through the VPN tunnel. This way the mAP appears to be at home.

### Key RouterOS Snippets

<details>
<summary><strong>🔧 WireGuard on home router (road‑warrior server)</strong></summary>

```routeros
/interface wireguard
add listen-port=13231 name=wg-roadwarrior private-key="auto-generated"

/ip address add address=10.255.200.1/24 interface=wg-roadwarrior

# Firewall: allow input on port 13231 UDP
/ip firewall filter add action=accept chain=input protocol=udp dst-port=13231 comment="WireGuard"

# Peer for each client (generated from client public key)
/interface wireguard peers
add allowed-address=10.255.200.2/32 interface=wg-roadwarrior public-key="<phonePublicKey>"
add allowed-address=10.255.200.3/32 interface=wg-roadwarrior public-key="<laptopPublicKey>"
add allowed-address=0.0.0.0/0 interface=wg-roadwarrior public-key="<travelRouterPublicKey>" comment="travel full-tunnel"
```

</details>

### Auto‑connection logic (client side)

- **Android:** Use Tasker to detect when you are connected to home SSID → disable full‑tunnel; when on any other network → enable full‑tunnel.
- **iOS:** iOS’ WireGuard app supports “On‑Demand Activation” with SSID matching. You can set it to **connect** when not on your home Wi‑Fi.
- **Laptops:** Systemd‑networkd or `wg‑quick` can use `PostUp` scripts to check the current network and add routes.

---

## 7. Parental Control Solution

### ⭐ Recommended: Hosted AdGuard Home + router DHCP injection

- **Deploy AdGuard Home** on a dedicated device (Raspberry Pi Zero 2 W, or as a container on the home Proxmox/hypervisor). Its IP: `10.10.40.10` on the Kids VLAN.
- **Configure** AdGuard with:
  - **Blocklists:** OISD full, family‑friendly list; HaGeZi’s “Multi PRO” (blocks adult sites, gambling, etc.).
  - **Safe search** enforcement (Bing, Google, YouTube) via DNS rewrites.
  - **Custom filtering rules** for specific sites.
- **Router setup:**
  - On the **Kids VLAN** DHCP server, set **DNS server = 10.10.40.10** (only).
  - **Block outbound DNS** from Kids VLAN except to AdGuard (`/ip firewall filter`). This prevents children from changing DNS manually.
  - Optionally, **force all port 53/853 traffic** to AdGuard via a dest‑nat rule.

This way children’s devices automatically use the filtered DNS without any client configuration.

If you prefer a **cloud‑based** solution, you could use **NextDNS** (paid, ~€20/year) and point the kids VLAN DNS to their resolvers, but that adds a dependency on a third party.

<details>
<summary><strong>🔧 Sample router DNS lock rules</strong></summary>

```routeros
# Allow DNS from Kids to AdGuard
/ip firewall filter add action=accept chain=forward src-address=10.10.40.0/24 dst-address=10.10.40.10 protocol=udp dst-port=53

# Drop any other DNS outbound from Kids
/ip firewall filter add action=drop chain=forward src-address=10.10.40.0/24 dst-address=!10.10.40.10 protocol=udp dst-port=53 comment="Force Kids DNS"
```

</details>

---

## 8. Migration Plan – From Current to Target Architecture

This plan uses the **€ 0 design** as the immediate target; the VPS and travel router can be added later without disrupting the home.

### Step 0: Preparation & Backup

- [ ] Export full current config: `/export verbose show-sensitive file=backup-pre-migration.rsc`
- [ ] Create a backup: `/system backup save name=pre-migration`
- [ ] Take a screenshot of existing IP → MAC mappings (from DHCP leases) – you’ll need them later.
- [ ] Define the new VLAN plan and IP assignments from §2.

### Phase 1 – Router VLAN Core (maintenance window ~2 h)

1. **Remove all existing bridge ports** and IPs that conflict.
2. **Create a new bridge** with `vlan-filtering=yes`.
3. **Add the SFP+ trunk port** to it.
4. **Create VLAN interfaces** and new IP addresses as per the plan.
5. **Set up DHCP servers** on each VLAN (copy existing static leases from the old pool).
6. **Build the new firewall chain** with inter‑VLAN rules (see §2 table).
7. **Test:** plug a laptop into the switch (set to management VLAN access) and verify you can reach `10.10.99.1` and get an IP.

**Rollback point:** If anything breaks, simply restore the backup file.

### Phase 2 – Switch & AP Migration (window ~1 h)

1. **On the CRS328**, remove all old bridge config. Create a VLAN‑aware bridge with the same VLAN definitions. Set the trunk port (SFP) to tag the required VLANs. Set access ports for the APs (PVID = management VLAN, but allow tagged traffic for SSIDs).
2. **Update CAPsMAN:** Change the datapath of each configuration to use the new VLAN‑filtered bridge (or set `vlan-id` directly).  
   *For now, keep SSIDs and passwords identical so clients reconnect seamlessly.*
3. **Reprovision APs:** CAPsMAN will push the new settings; all APs will start using the new VLANs.
4. **Verify:** Connect to “Kogler” SSID and check you get `10.10.1.x` IP; “Kogler guest” should get `10.10.30.x`.

### Phase 3 – Device Re‑Assignment (window ~2 h, can be done in chunks)

1. **Move all known wired devices** to their correct VLAN by changing the switch port PVID.  
   - NAS, Home Assistant Pi, KNX router – all stay in Home VLAN (VLAN 10) for now.
   - Shelly RGBW2 devices – they are already on IoT SSID; that SSID now maps to VLAN 20. They will get new IPs after a reboot. Update their static leases in the new DHCP pool.
2. **Update Home Assistant:** point it to the new IoT IPs (if, for example, the Shelly devices change IP). Or, better, keep using **DHCP reservations** so their IPs are predictable.
3. **Test** every service: Home Assistant dashboard, internet access, inter‑VLAN pings (should be blocked except where allowed).

### Phase 4 – VPN & Parental Controls (window ~1 h)

1. **Set up WireGuard road‑warrior server** on the router (port 13231), and add client peers.
2. **Configure the Kids VLAN DHCP** to hand out AdGuard Home’s IP as DNS.
3. **Add firewall rules** to lock DNS as described in §7.
4. **Test** from a child’s device: should not be able to resolve adult sites.

### Phase 5 (Optional) – VPS Integration

1. **Provision the cloud VPS** and install Proxmox.
2. **Set up the site‑to‑site WireGuard tunnel** between VPS and home.
3. **Deploy services** (Authentik, Immich, Reverse Proxy) one by one, following the Proxmox network plan.
4. **Redirect your domain** to the VPS reverse proxy, and test SSO.

### Phase 6 (Optional) – Travel Router

1. **Take the spare mAP** and flash it with a fresh RouterOS config.
2. **Configure it as a WireGuard client**, full tunnel, SSID “TravelHome”.
3. **Test abroad** (or simulate with your phone tethered) – traffic should exit from your home IP.

---

## 📊 Summary of Recommendation

The final, fully realised architecture:

```
Home: VLAN‑segmented, CAPsMAN‑managed Wi‑Fi, default‑deny inter‑VLAN firewall,
      WireGuard VPN server for road‑warriors, AdGuard Home for kids.
VPS: Dedicated Proxmox host, service VLANs isolated from lab,
      all access via Authentik‑protected reverse proxy.
Connectivity: Always‑on site‑to‑site WireGuard tunnel.
Management: Git‑versioned Ansible playbooks, The Dude/Supervision dashboards,
            Home Assistant as the family dashboard.
```

This meets every success criterion: IoT isolation, guest access restricted, SSO for all services, automatic VPN toggling, travel router, parental controls, and rollback‑capable configuration.

All items can be built incrementally – the € 0 design is a fully functional, secure, and manageable home network on its own. The € 1000 budget adds the cloud VPS and a dedicated travel device, elevating the family’s “digital sovereignty” and lab capabilities.