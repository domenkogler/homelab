# Home Lab & Family Network Architecture Request

## Context
Home network serving a family, expanding to include cloud VPS services and secure remote access for devices and users.  
Current infrastructure is MikroTik‑based, with a bridged ISP ONT and a Home Assistant smart home setup.

---

## Design Principles
- **Security by default**: deny‑all firewall posture, network segmentation, encrypted transport for all remote access
- **Manageability**: GUI‑first for ongoing operations (MikroTik WebFig / WinBox acceptable); infrastructure‑as‑code for initial provisioning and disaster recovery  
- **Availability**: maintenance windows ≤ 4 h for core internet, ≤ 24 h for auxiliary services; UPS already present  
- **Family‑friendliness**: services accessible via a single portal (Authentik SSO); DNS‑based parental controls for children

---

## Definitions (to avoid ambiguity)

| Term | Meaning |
|------|---------|
| **Easy manageable** | Configuration changes via GUI after initial CLI/setup; central dashboard preferred (e.g., CAPsMAN, Home Assistant); git‑versioned configs for rollback |
| **Safe** | Default‑deny inter‑VLAN traffic; IoT isolated; authenticated services only; VPN tunnels for all remote access; reverse proxy with WAF and auth |
| **Production isolation** | Family‑used services (Authentik, Pangolin, Immich) must not be impacted by experimental services; separate VLANs/VMs with resource limits |

---

## Current Infrastructure

### Physical & Logical Topology

#### ISP & Edge
- **Comtrend GRG‑4260us** (Telekom Slovenije) – optical, **bridged**, not routing  
- **MikroTik RB4011iGS+** – main router, establishes PPPoE session for internet, provides inter‑VLAN routing  
- Internet speed: **1 Gbps symmetrical**

#### Core Switching
- **MikroTik CRS328-24P-4S+** – 24‑port PoE+ switch, connects all wired devices and APs

#### Wireless Access Points (all MikroTik, wired to the switch)
- **RB962UiGS-5HacT2HnT** (hAP ac) – currently used as AP  
- **RBD52G-5HacD2HnD** (hAP ac²) – currently used as AP  
- **hAP ac²** – spare, unused  
- All APs support both 2.4 GHz and 5 GHz radios

#### Smart Home & IoT
- **Raspberry Pi 4** running Home Assistant OS  
- **Gira IP Router KXIPRT01** – KNX integration (shutters, lighting) via Home Assistant  
- **Shelly RGBW2** devices (multiple) – Wi‑Fi connected, managed by Home Assistant  
- IoT protocols: Wi‑Fi (2.4 GHz), KNX; no Zigbee/Z‑Wave yet

#### User Devices
- Main desktop PC – wired to router  
- Laptop + docking station – wired to router  
- Phones, tablets, TVs, gaming consoles – mostly wireless

#### Power
- UPS protects critical infrastructure (router, switch, ONT, HA Pi)

#### Configuration
- Current `rb4011_config.rsc` will be **audited** for VLANs, firewall rules, and hygiene; starting fresh is acceptable if recommended

---

## Planned Additions (within € 1000 budget)

### Cloud VPS (propose specs)
- Provider / specs to be recommended; must run Proxmox VE  
- Will host:
  - **Authentik** – SSO / Identity Provider  
  - **Pangolin** – (assumed: web application firewall / gateway)  
  - **Reverse proxy** – Traefik, Caddy, or Nginx (decision needed)  
  - **Immich** – photo backup  
  - **Git server** – Forgejo or Gitea (stores device configs, Home Assistant, Ansible scripts)  
  - **Isolated lab environment** – for learning/testing without affecting production services

### Travel Router
- Repurpose an existing MikroTik device (or purchase new) as a portable AP that tunnels **all traffic via home static IP** when abroad, to access Slovenian geo‑blocked content

### DNS / Parental Controls
- A DNS‑based filtering solution (to be proposed) for children’s devices, integrated with the segmented network design

---

## Technical Requirements

### Home Network
1. Create separate **VLANs/subnets**:
   - Management (network devices)
   - Home (trusted user devices)
   - IoT (isolated, internet‑only unless explicitly allowed)
   - Guest (internet‑only, client isolation)
   - Possibly a dedicated “Kids” VLAN for filtered DNS
2. Default‑deny inter‑VLAN routing, with fine‑grained exceptions  
3. Centralised management:
   - Option A: MikroTik CAPsMAN for all APs  
   - Option B: Home Assistant dashboard for network status  
   - Git versioning of all network device configs
4. VPN server for secure remote access to home subnet(s) from phones and laptops (split‑tunnel preferred when on trusted networks, full‑tunnel when on untrusted)
5. Travel AP auto‑connects to home VPN and routes all client traffic through it
6. Existing Home Assistant and IoT devices must continue to function without interruption; IoT VLAN changes must be carefully migrated

### Cloud VPS
1. Proxmox VE with separate **bridge/network segments**:
   - Management (Proxmox host, SSH)
   - DMZ (reverse proxy, WAF)
   - Services (Authentik, Pangolin, Immich, Git)
   - Lab (isolated testing)
2. Production services **must be isolated** from lab VMs (resource limits, no network leakage)
3. Secure site‑to‑site VPN tunnel between the VPS and the home router
4. All VPS services accessible **only** via the reverse proxy with Authentik SSO (no direct exposure)
5. Configuration‑as‑code: Ansible playbooks stored in Git, reproducible deployment

### Cross‑Site Connectivity
- Site‑to‑site VPN (home ↔ VPS) always on, routed such that:
  - Home devices can reach VPS services via private IPs
  - VPS can reach home management VLAN for backups/configuration
- Road‑warrior VPN server (same or separate instance) for client devices, with automatic on‑demand connection when off‑home‑Wi‑Fi

---

## Threat Model & Constraints
- **Adversary**: opportunistic (script kiddies, mass scanners), not targeted APT  
- **Compliance**: GDPR‑adjacent (personal data, no regulated medical/financial)  
- **Physical security**: home physically secured, VPS is cloud‑provider responsibility  
- **Downtime budget**: core internet ≤ 4 h; auxiliary services ≤ 24 h  
- **Backup**: router configs, Home Assistant, Immich photos (strategy to be defined)  
- **Budget**: € 0 (existing hardware only) and € 1000 (expansion) scenarios required

---

## Success Criteria (measurable outcomes)
- [ ] IoT device cannot initiate connection to Home VLAN  
- [ ] Guest network has internet only, with client isolation  
- [ ] Family members access all services via single SSO portal (Authentik)  
- [ ] Phones/laptops automatically use VPN only when off‑home‑network  
- [ ] Travel AP tunnels all traffic through home static IP when abroad  
- [ ] VPS services reachable only via authenticated reverse proxy  
- [ ] Configuration changes are rollback‑capable (git versioning)  
- [ ] Parental controls enforce safe DNS on kids’ VLAN without user intervention

---

## Requested Deliverables (Tasks)

1. **Audit** current `rb4011_config.rsc` – identify security/hygiene issues and comment on whether a clean slate is advisable.
2. **Propose a new home network architecture** using only existing hardware (€ 0).
3. **Propose an enhanced architecture** with the € 1000 budget, including an **itemised bill of materials**.
4. **Design the cloud VPS networking** – recommend provider, specs (CPU, RAM, storage, bandwidth), VLAN layout, firewall, and VPN integration.
5. **Recommend a management strategy** – CAPsMAN, Ansible, git‑ops, monitoring – with justification.
6. **VPN plan** – topology, protocol (WireGuard/IPsec), routing design for all three use‑cases (road‑warrior, site‑to‑site, travel AP).
7. **Parental control solution** – DNS‑based service or local resolver with filtering.
8. **Migration plan** – step‑by‑step from current state to the chosen target architecture, with rollback points.

---

*Please provide all deliverables in a single, structured response, with network diagrams described in text (or ASCII art), firewall rules summarised as logical tables, and device‑specific configuration snippets where critical.*