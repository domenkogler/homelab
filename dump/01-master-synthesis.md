# Homelab Master Synthesis — Connected Architecture

> **Status:** Brainstorming / Refinement Phase  
> **Goal:** A configuration-driven, documented homelab that any family member can replicate from GitHub + backups.

---

## 🗺️ System Overview

This homelab spans **three physical locations** connected by permanent VPN tunnels:

```
┌─────────────────────┐     WireGuard S2S     ┌──────────────────────┐
│   HOME (Kogler)     │◄────────────────────►│   CLOUD VPS (Hetzner)│
│   RB4011 + Servers  │                      │   Public-facing apps  │
│   10.10.0.0/16      │                      │   10.255.0.0/16       │
└─────────┬───────────┘                      └──────────────────────┘
          │
          │ WireGuard Road-Warrior
          │
┌─────────▼───────────┐
│  TRAVEL (Road)      │
│  hAP ac² / mAP lite│
│  192.168.123.0/24   │
└─────────────────────┘
```

---

## 1️⃣ NETWORK ARCHITECTURE (Home LAN)

**Source:** `Home Lab & Family Network Architecture.md` (= `Homelab network architecture.md` — identical content)  
**Source:** `Multi-VLAN DNS Integration Architecture.md`

### Hardware
| Device | Model | Role |
|--------|-------|------|
| Router | MikroTik RB4011iGS+ | PPPoE, VLAN routing, firewall, WireGuard server, CAPsMAN |
| Switch | MikroTik CRS328-24P-4S+ | Layer-2 VLAN-aware, PoE for APs |
| APs | hAP ac, hAP ac² (×2 + 1 spare) | CAPsMAN-managed Wi-Fi |

### VLAN Plan
| VLAN ID | Name | Subnet | Purpose |
|---------|------|--------|---------|
| 1 | Management | 10.10.99.0/24 | Router, switch, AP management |
| 10 | Home | 10.10.1.0/24 | Trusted family devices, servers, NAS, Home Assistant |
| 20 | IoT | 10.10.20.0/24 | Smart-home (KNX, Shelly) — isolated |
| 30 | Guest | 10.10.30.0/24 | Internet-only, client isolation |
| 40 | Kids | 10.10.40.0/24 | Filtered DNS, restricted access |

### Firewall Logic
- Default-deny inter-VLAN forwarding
- Home → IoT: allowed for MQTT/HA control (established + new from specific IPs)
- IoT → Home: **deny all** (only reply traffic)
- Guest → any LAN: **deny all**
- Kids → Home: Drop, DNS forced through AdGuard filter
- All → WAN: allowed (masqueraded)

### DNS Architecture (Refined from Multi-VLAN DNS doc)
- **Technitium** on management VLAN as central DNS router
- **Pi-hole** on management VLAN as upstream for Main LAN (aggressive ad-blocking)
- **AdGuard Home** on Kids VLAN (10.10.40.10) — adult content filtering
- Per-subnet DNS policy via Technitium group mapping:
  - Main LAN → Pi-hole
  - Kids → Cloudflare Families (1.1.1.3)
  - IoT → Quad9 (9.9.9.9, malware blocking)

> **⚠️ Note:** The main architecture doc recommends only AdGuard Home for Kids VLAN. The Multi-VLAN DNS doc introduces Technitium + Pi-hole. These are **compatible layers** — Technitium is the central DNS router, Pi-hole/AdGuard are upstream filters. This needs a consolidated decision.

---

## 2️⃣ HOME SERVER HARDWARE

**Source:** `nov strežnik.md`, `new home server hardware configuration summary.md`, `Stroškovnik za novi strežnik.md`

### Evolution of Hardware Choices

The hardware design evolved across docs. Here's the **resolved final** (based on the cost breakdown being the most specific):

| Component | Final Choice | Cost |
|-----------|-------------|------|
| Motherboard | **ASUS ProArt B850-Creator WiFi NEO** (x8/x8 PCIe) | €300 |
| CPU | **AMD Ryzen 9 9900X** (12C/24T) | €330 |
| CPU Cooler | **Thermalright Peerless Assassin 120 SE** | €35 |
| GPU | **AMD Radeon AI PRO R9700 32GB** (×1, later ×2) | €1,350 |
| RAM | **Crucial Pro 64GB Kit DDR5** (CP2K32G64C40U5B) | €640 |
| PSU | **Corsair HX1500i** (1500W Platinum) | €290 |
| NVMe 1 (AI/OS) | **Biwin Black Opal X570 PRO 2TB Gen5** | €180 |
| NVMe 2 (Media) | **Lexar NM990 4TB Gen5** | €310 |
| Chassis | **ALAMENGDA ALE01 Open-Frame Test Stand** (horizontal on rack floor) | €130 |
| Remote Mgmt | **GL.iNet Comet KVM (GL-RM1) + PoE** | €120 |
| Network | **10Gtek SFP-10G-T** (5Gbps to MikroTik) | €45 |
| **Total** | | **~€4,449** |

### Resolved Conflict: Chassis
- **Earlier:** 4U rackmount case (in `nov strežnik.md`)
- **Later:** Open-frame ALAMENGDA bench on rack floor (in `new home server hardware configuration summary.md` and cost breakdown)
- **Winner: Open-frame** — verified rack dimensions: 16.5 cm height fits under 35 cm limit, 26.7 cm depth fits in 58 cm cabinet, leaves room for cables and airflow

### Resolved Conflict: Motherboard
- **Earlier:** MSI PRO X870E WIFI (in `nov strežnik.md`)
- **Later:** ASUS ProArt B850-Creator WiFi NEO (in cost breakdown and hardware summary)
- **Winner: ASUS ProArt** — seems to be the final choice, x8/x8 PCIe confirmed

### Remote Management
- **GL.iNet Comet KVM** (≈ PiKVM alternative with PoE) — connects to iGPU HDMI, provides BIOS-level control, virtual media, ATX power control
- Replaces the earlier PiKVM concept; adds PoE power

### VRAM Management Strategy (Proxmox + Ollama)
| Mode | Trigger | Models in VRAM | GPU Power |
|------|---------|---------------|-----------|
| **Programming** | Domen working | Qwen 2.5-Coder 32B (~32GB) | Full |
| **Family Home** | Family phones on Wi-Fi | Whisper STT + Llama HA LLM + Piper TTS (~7GB) | Medium |
| **Sleep/Work** | Schedule or house empty | All models unloaded | ~12W idle |

---

## 3️⃣ SMART HOME & VOICE ASSISTANT

**Source:** `Načrt Homelab sistema_ Lokalni slovenski glasovni asistent in avdio sistem.md`  
**Source:** `Homeassistant rework prompt.md` / `Homeassistant rework.md`

### 100% Local Slovenian Voice Pipeline

```
[User Voice] → [Guition ESP32-S3 / Android Phone] → Wi-Fi
     → [Minisforum MS-A2 NPU] → Whisper STT (Slovenian)
     → [Local LLM] → Response
     → [Home Assistant] → [WiiM Bar / Audio Pro Speaker]
```

> **⚠️ Note:** The voice doc references **Minisforum MS-A2** as the AI brain with NPU, but the hardware docs settle on the custom-built **Ryzen 9 9900X + Radeon AI PRO R9700** server. The R9700 has a dedicated AI accelerator — this is **consistent** in capability, just different hardware. Need confirmation: is MS-A2 a separate dedicated device, or was it an earlier idea replaced by the custom server?

### Smart Home Components
| Device | Location | Protocol | Function |
|--------|----------|----------|----------|
| Guition Round ESP32-S3 | Kitchen | ESPHome / Wi-Fi | Voice wake-word, timer display, rotary knob |
| Android phones | All rooms | HA Companion / Willow | Voice satellites (free, excellent mics) |
| WiiM Bar | Living room/TV | HDMI eARC + Chromecast | Dolby Atmos soundbar, multi-room audio |
| Audio Pro A10 MKII | Portable | Wi-Fi + Bluetooth | Portable multi-room speaker |
| KNX devices | Whole house | KNX | Lights, blinds |
| Shelly RGBW2 | Whole house | Wi-Fi | LED strip control |
| Nvidia Shield | Living room | Wi-Fi | Media playback |

### Dashboards
- **TileBoard** — Fast control: lights, blinds, Shelly RGBW, media (tablet/PC wall-mounted)
- **Grafana** — Analytics: weather station, heat-recovery ventilator, MikroTik traffic
- **Home Assistant** — Central hub, family "single pane of glass"
- Grafana iframe panels embedded into TileBoard via `TYPES.IFRAME`

---

## 4️⃣ CLOUD VPS (Hetzner)

**Source:** `Home Lab & Family Network Architecture.md` (Section 3–5)  
**Source:** `družinski web sistem.md`  
**Source:** `Varnostni načrt za zaščito VPS.md`

### VPS Specs
| Option | Specs | Cost |
|--------|-------|------|
| **Dedicated Server (recommended)** | i5-12500, 64GB RAM, 2×512GB NVMe, 1Gbps unmetered | ~€35/mo |
| **Cloud VPS (alternative)** | CX43: 4vCPU, 16GB RAM, 160GB NVMe | ~€15.90/mo |

### Application Stack (The "Družinski Web Sistem")
```
┌─────────────────────────────────────────────┐
│                  INTERNET                    │
└─────────────────┬───────────────────────────┘
                  │ :443
         ┌────────▼────────┐
         │   Cloudflare    │ (DDoS protection, geo-blocking)
         └────────┬────────┘
                  │
         ┌────────▼────────┐
         │    Traefik      │ (Reverse proxy, auto-SSL)
         │  + CrowdSec     │ (Brute-force protection)
         └────────┬────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
┌───▼───┐   ┌─────▼─────┐  ┌───▼──────┐
│Authentik│  │ OpenCloud │  │  Immich  │
│ (SSO)   │  │(File sync)│  │ (Photos) │
└───┬─────┘  └─────┬─────┘  └─────┬────┘
    │              │              │
    └──────────────┼──────────────┘
                   │
         ┌─────────▼──────────┐
         │ Hetzner Storage Box│ (1TB — CIFS mounted)
         │ (bulk files only)  │
         └────────────────────┘

  DBs + thumbnails → local VPS SSD (speed)
  Large files       → Storage Box (economy)
```

### Service Choices
| Service | Choice | Why |
|---------|--------|-----|
| Reverse Proxy | Traefik | Auto-SSL, Docker-native labels |
| Identity | Authentik | SSO, OIDC, MFA (WebAuthn/TOTP), Forward Auth |
| Files | **OpenCloud** (not Nextcloud) | Go-based, ~100MB RAM, WebDAV, OIDC |
| Photos | Immich | C++/Go, fast, AI face recognition, mobile apps |
| Email/Calendar | **Infomaniak kSuite** (Swiss, paid) | EU privacy, CalDAV/VTODO, catch-all aliases |
| Backup | Kopia + tiredofit/db-backup | Encrypted, dedup, Web GUI, DB dumps pre-backup |
| Git | Forgejo/Gitea (on VPS) | Lightweight, OIDC-compatible |

### Connections: 1Password + Authentik + Family
- Family uses 1Password Families for credential storage
- Authentik set to **Compatibility Mode** so 1Password autofill works
- Passkeys via 1Password (WebAuthn) for biometric login
- Conditional access: at home (LAN/VPN) → skip MFA; remote → require MFA

### VPS Security Layers
1. Cloudflare proxy (orange cloud) — hides real IP, absorbs DDoS
2. Cloudflare WAF geo-blocking — block countries family doesn't visit
3. Traefik security headers (XSS, clickjacking, HSTS)
4. CrowdSec (community threat intel) on Authentik + Traefik logs
5. Authentik Forward Auth — no app exposes its own login
6. Docker network isolation — separate public/internal networks
7. `AUTHENTIK_TRUSTED_PROXIES` configured to avoid proxy lockout

---

## 5️⃣ VPN & REMOTE ACCESS

**Source:** `Home Lab & Family Network Architecture.md` (Section 6)  
**Source:** `Road warrior plan.md`  
**Source:** `potovalni vpn prompt.md`  
**Source:** `potovalni.vpn.md`

### Two VPN Layers (Complementary)

| Layer | Technology | Purpose | Endpoint |
|-------|-----------|---------|----------|
| Site-to-Site | WireGuard (native RouterOS) | Home ↔ VPS permanent tunnel | RB4011 ↔ VPS |
| Road-Warrior | WireGuard (native RouterOS) | Phones/laptops to home | RB4011 server, clients on port 13231 |
| Road-Warrior (alt) | Headscale (self-hosted Tailscale) | Mesh overlay, easier mobile | Homelab Docker server |

> **⚠️ Key Question:** The docs describe TWO separate road-warrior approaches:
> 1. **Native WireGuard on RB4011** — simpler, fewer moving parts, split/full-tunnel profiles
> 2. **Headscale (Tailscale) on homelab Docker** — mesh overlay, easier NAT traversal, mobile app (wife-friendly)
>
> The `potovalni.vpn.md` and `Road warrior plan.md` seem to **combine both**: WireGuard for site-to-site (router-level) + Headscale for mobile devices (user-level). This needs explicit confirmation.

### Travel Router Setup
- **Device:** MikroTik hAP ac² (spare/repurposed) or mAP lite
- **Local subnet:** 192.168.123.0/24
- **Dual WAN:** ether1 (wired, priority) + wlan1 (hotel Wi-Fi station)
- **Kill-switch:** LAN traffic blocked from WAN if VPN drops
- **Wife-friendly portal:** Sploax/KORP captive portal at `potovalni.vpn` — pick hotel Wi-Fi, enter password, done
- **DNS:** Local DNS resolves `potovalni.vpn` → 192.168.123.1; `.home.kogler.si` forwarded through VPN to home DNS

### Auto-VPN for Phones
- Android: Tasker detects SSID → enable/disable full-tunnel
- iOS: WireGuard "On-Demand Activation" with SSID matching
- Headscale: Always-on mesh, auto-reconnects

---

## 6️⃣ LOCAL LLM FOR OFFICE TASKS

**Source:** `local llm agent for word mail and presentations.md`

### Local AI Office Stack
| Task | Tool | How |
|------|------|-----|
| Word integration | AnythingLLM + Ollama/LM Studio | Local RAG, .docx ingestion, LocPilot add-in |
| Email automation | n8n (self-hosted) + Ollama | IMAP/SMTP, draft responses for review |
| Presentations | Ollama → python-pptx or Marp | Python script to .pptx, or Markdown → slides |
| Models | Llama 3.1/3.2 8B, Qwen 2.5/3.5 7-14B, Phi-4 14B | Office-optimized, low VRAM |

### Connection to Home Server
- These workloads **run on the same R9700 GPU** in the home server
- Fits the "Programming Mode" in the VRAM management strategy
- n8n can also connect to Home Assistant for smart home automations

---

## 7️⃣ IaC & AUTOMATION

**Source:** `Iaac/ansible/`, `Iaac/bootstrap-ansible-client/`, `Iaac/host/`

### Current State (Testing Phase)
- Ansible playbook for "deblab" server (10.10.1.125)
- Common role: Docker installation, `/opt` directory structure
- Secrets via 1Password lookup plugin (NOT in plaintext)
- Bootstrap script for management laptop (WSL2 Debian)
- Host setup: WSL2 with mirrored networking for proper IPs

### Planned Roles (Commented Out)
- `storage` — file services
- `identity` — Authentik
- `apps` — application stack

### Directory Structure
```
/opt/
  kopia/config/
  kopia/cache/
  authentik/
  nextcloud/html/    ← may change to opencloud/
  nextcloud/db/      ← may change to opencloud/
  immich/
  homeassistant/
```

### Testing Approach
- Current "deblab" is likely a Hyper-V VM or WSL2 instance for testing
- Production target: the new Ryzen 9 server (Proxmox VE)

---

## 8️⃣ DATABASE BACKUP STRATEGY

**Source:** `chosen db backup service.md`, `družinski web sistem.md` (Section 3)

### Two-Layer Backup
1. **tiredofit/db-backup** — runs as long-lived service with internal cron
   - Dumps PostgreSQL, MySQL, etc.
   - Compresses (Gzip/Bzip2/Xz/Zstd), creates checksums
   - Pushes to S3/MinIO/Azure
   - Handles retention cleanup

2. **Kopia** — encrypted incremental snapshots
   - Client-side encryption
   - Multi-threaded compression
   - Web GUI (exposed via Traefik, SSO-protected)
   - Reed-Solomon error correction

### Backup Flow
```
Cron → db-backup dumps DB → local SSD
     → Kopia snapshots the dump + configs
     → Pushes to Hetzner Storage Box (or home NAS)
     → Cleanup temp dumps
```

---

## 📊 DECISION STATUS TABLE

| Decision | Status | Notes |
|----------|--------|-------|
| VLAN architecture (€0 design) | ✅ Decided | 4 VLANs, default-deny, firewall on RB4011 |
| Router/switch hardware | ✅ In place | RB4011 + CRS328 already owned |
| AP hardware | ✅ In place | hAP ac + hAP ac² |
| Home server chassis | ⚠️ Settled but unusual | Open-frame bench on rack floor — verify wife-acceptance |
| Home server motherboard | ✅ Decided | ASUS ProArt B850-Creator (final) |
| Home server GPU | ✅ Decided | Radeon AI PRO R9700 (×1, expand to ×2) |
| Cloud VPS provider | ✅ Decided | Hetzner (dedicated or CX43) |
| Cloud VPS hypervisor | ⚠️ Depends | Proxmox on dedicated, Docker on CX43 |
| File sync app | ✅ Decided | OpenCloud (replaced Nextcloud/OCIS) |
| Photo app | ✅ Decided | Immich |
| Email/Calendar | ✅ Decided | Infomaniak kSuite (Swiss, paid) |
| Backup | ✅ Decided | Kopia + db-backup |
| Identity provider | ✅ Decided | Authentik |
| Reverse proxy | ✅ Decided | Traefik |
| Dashboard | ✅ Decided | TileBoard (control) + Grafana (analytics) |
| VPN: site-to-site | ✅ Decided | WireGuard (native RouterOS) |
| VPN: road-warrior | ❓ Needs decision | Native WireGuard vs Headscale vs both |
| Travel router portal | ✅ Decided | Sploax/KORP captive portal at potovalni.vpn |
| DNS architecture | ❓ Needs consolidation | Technitium+Pi-hole vs AdGuard-only |
| Voice assistant hardware | ❓ Needs clarification | MS-A2 vs custom server? |
| Local LLM for office | ✅ Decided | Ollama + AnythingLLM + n8n on same GPU |
| IaC tool | ✅ Decided | Ansible with 1Password secrets |
| Management host | ✅ In place | WSL2 Debian with bootstrap script |
