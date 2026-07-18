# Questions for Clarification — Grouped by Theme

> These questions emerged from conflicts, gaps, and ambiguities across the 17 docs and 6 IaC files.  
> None of these are blockers — the architecture is already well-thought-out. These are refinement questions.

---

## 🧱 Theme A: Network & DNS Consolidation

### A1. DNS Architecture — One Layer or Two?
The main architecture doc recommends **AdGuard Home on Kids VLAN only** for parental controls. The Multi-VLAN DNS doc introduces **Technitium as central DNS router + Pi-hole + Cloudflare Families + Quad9** — a multi-layered DNS with per-subnet policies.

- **Is Technitium the intended central DNS for ALL VLANs, with Pi-hole and AdGuard as upstream filters?**
- **Or is the Multi-VLAN doc a "future enhancement" beyond the base €0 design?**
- **Does the current RB4011 do any DNS filtering at all, or just forward to 1.1.1.1/8.8.8.8?**

### A2. IPv6 — Enable or Disable?
The current RB4011 config has conflicting IPv6 settings (disabled in settings but active in addresses/firewall). The new architecture doc doesn't mention IPv6.

- **Fully disable IPv6, or fully enable it on the new design?**
- **Does your ISP (Telekom Slovenije?) provide IPv6 via PPPoE?**

### A3. CAPsMAN — Local Forwarding or Tunnel?
The architecture doc recommends `local-forwarding=no` but mentions local forwarding is also possible.

- **Which mode is preferred?**
- **Are all APs hardwired (making local forwarding safe), or are there mesh hops?**

---

## 🖥️ Theme B: Home Server Hardware

### B1. Minisforum MS-A2 vs Custom Ryzen Server
The Slovenian voice assistant doc references **Minisforum MS-A2** (with NPU) as the AI processing brain. All hardware/cost docs describe the **custom Ryzen 9 9900X + Radeon AI PRO R9700** server.

- **Is the MS-A2 a separate, smaller device dedicated to voice processing?**
- **Or was MS-A2 an earlier idea replaced by the custom server?**
- **If separate: where does it sit — in the rack, in the kitchen, elsewhere?**

### B2. Proxmox on the Home Server?
The new server is described as running Proxmox VE with LXC containers. But the hardware doc focuses heavily on bare-metal Ollama GPU passthrough.

- **Is Proxmox the intended hypervisor for the home server?**
- **Will the R9700 GPU be passed through to a single VM/LXC, or shared across multiple?**
- **The VRAM management strategy (Programming/Family/Sleep modes) — is this automated by a script, Home Assistant, or Ollama's built-in `keep_alive`?**

### B3. Open-Frame Bench — Family Acceptance?
The ALAMENGDA open-frame bench sits horizontally on the rack floor — functionally brilliant but visually exposed.

- **Is the rack in a closed cabinet (so nobody sees it)?**
- **Are there dust/pet/small-child concerns with an open-air build?**
- **Any plans for a dust filter or mesh cover?**

### B4. Second GPU — When?
The motherboard was chosen for x8/x8 dual-GPU support. The cost breakdown lists only 1× R9700.

- **When is the second GPU planned?**
- **What triggers the purchase — running out of VRAM for larger models, or specific new use cases?**
- **Will the second GPU also be a R9700, or a different model?**

---

## ☁️ Theme C: Cloud VPS

### C1. Dedicated Server or Cloud VPS?
The architecture doc favors a **dedicated Hetzner server** (~€35/mo) for Proxmox. The cheaper **CX43 cloud VPS** (~€15.90/mo) is listed as alternative.

- **Which path are you leaning toward?**
- **Do you actually need Proxmox on the VPS, or would Docker Compose suffice?**
- **Is the dedicated server overkill for 4 family members + 4 external users?**

### C2. What Lives Where?
The docs describe services split between VPS and home server, but boundaries are fuzzy:

| Service | VPS (družinski web) | Home Server (hardware docs) |
|---------|---------------------|-----------------------------|
| Immich | ✅ Listed | Has 4TB NVMe for media |
| OpenCloud | ✅ Listed | — |
| Kopia | ✅ Listed | Has /opt/kopia directories |
| LLM/Ollama | — | ✅ Primary GPU workload |
| Home Assistant | — | ✅ On-prem only |

- **Is Immich on the VPS (with Hetzner Storage Box for bulk) or on the home server (with local NVMe)?**
- **If Immich is on VPS: are original-quality photos stored in the cloud? Privacy concerns?**
- **If photos are on the home server: how do you access them remotely?** (WireGuard site-to-site tunnel handles this)
- **Kopia: backing up the VPS, the home server, or both?**

### C3. "Pangolin" — What Is It?
The architecture doc mentions "Pangolin" as a WAF/reverse proxy alongside Traefik, but the družinski web sistem doc uses only Traefik.

- **Is Pangolin a specific product (https://github.com/fosrl/pangolin)?**
- **Is it still part of the plan, or did Traefik absorb its role?**

---

## 🔐 Theme D: VPN & Remote Access

### D1. WireGuard vs Headscale — One, the Other, or Both?
The docs describe **both** natively:
- WireGuard on RB4011 for site-to-site and road-warrior
- Headscale (self-hosted Tailscale) on Docker for mobile mesh

- **Is Headscale an alternative TO WireGuard road-warrior, or complementary (for phones only)?**
- **If both: does Headscale go through the WireGuard tunnel to the VPS?**
- **Which one does the family use on their phones?** (Headscale has a simpler mobile app)

### D2. Travel Router — Which Device?
- hAP ac² (mentioned in `potovalni vpn prompt.md`)
- mAP lite (mentioned in architecture doc as €30 option)
- hEX ac (mentioned in `potovalni.vpn.md` — hEX is wired-only, should be hAP)

- **Which spare device becomes the travel router?**

### D3. Travel Router WAN — Captive Portal Implementation
The Sploax/KORP concept is brilliant but the MikroTik Hotspot `on-login` script to reconfigure the wlan1 station is non-trivial.

- **Has this been tested or prototyped?**
- **What happens if the hotel Wi-Fi has its own captive portal (common)?** — The user would need to first connect a phone directly to hotel Wi-Fi, accept the portal, THEN switch to the travel AP... or does the travel AP somehow tunnel the hotel's captive portal through?
- **Fallback plan if Sploax doesn't work as expected?**

---

## 🏠 Theme E: Smart Home & Voice

### E1. Voice Assistant Activation
The Guition ESP32-S3 listens for a wake word ("Hey Kogler"?) but the doc doesn't specify the wake word engine.

- **What wake word detection runs on the ESP32-S3?** (ESP-SR? microWakeWord? Custom?)
- **What's the activation word?**
- **Is the wake word in Slovenian?** (This significantly limits off-the-shelf options)

### E2. Home Assistant Entity List
The TileBoard/Grafana prompts are templates waiting for the actual entity list.

- **Do you have the Home Assistant entity list?** (The prompt says "[TUKAJ PRIPEPNAJ/VPIŠI SVOJ SEZNAM ENTITET]")
- **Is the current HA instance running and accessible?**

### E3. WiiM Bar — HDMI eARC
The WiiM Bar connects to your future TV via HDMI eARC.

- **Do you have the TV yet, or is it also planned?**
- **If no TV: does the WiiM Bar work standalone for music via Chromecast?**

---

## 🔧 Theme F: IaC & Automation

### F1. "deblab" — What Is It?
The Ansible inventory targets `deblab` at 10.10.1.125.

- **Is deblab the current test VM (Hyper-V or WSL2)?**
- **Will the new Ryzen server get a different hostname?**
- **Is the Ansible workflow: laptop → deblab (test) → production server?**

### F2. 1Password Integration
The Ansible playbook uses 1Password lookup for secrets (Kopia password, Authentik secrets, DB passwords).

- **Is the 1Password Service Account already set up?**
- **Does the OP_SERVICE_ACCOUNT_TOKEN have the right vault access?**

### F3. Ansible Roles — Prioritization
Three roles are commented out: `storage`, `identity`, `apps`.

- **What's the priority order for implementing these?**
- **Will you write them yourself or generate them?**

---

## 📋 Theme G: Documentation & "Bus Factor"

### G1. Documentation Standard
The ultimate goal is that the family can replicate everything from GitHub + backups.

- **What format should the family documentation be?** (Markdown in repo, printed binder, wiki?)
- **Should it be bilingual** (Slovenian for family, English for technical)?
- **Where is the GitHub repo hosted?** (Forgejo on VPS? Public GitHub? Both mirrored?)

### G2. Backup Validation
Kopia and db-backup are planned but not yet running.

- **How will you test restores?** (Quarterly restore drill?)
- **Who in the family knows the backup password?**
- **Is the Kopia master password stored in 1Password?** (Ansible references `kopia_master_password`)

### G3. Physical Backup
In case of fire/flood at home: the VPS is remote, but what about home server data?

- **Are critical configs pushed to the VPS Git server (off-site backup)?**
- **Are Immich photos also on the VPS, or only at home?**

---

## 🎯 Priority Questions (Top 5 for Next Discussion)

1. **Immich: VPS or home server?** — This determines storage layout, backup strategy, and monthly costs.
2. **Headscale vs WireGuard for family phones?** — This determines the "wife-friendly" remote access story.
3. **Minisforum MS-A2: separate device or replaced?** — Resolves a hardware conflict.
4. **Dedicated server or CX43 VPS?** — Budget impact and Proxmox requirement.
5. **Wake word and voice pipeline for Slovenian?** — Feasibility of the local voice assistant.
