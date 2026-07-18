# Questions for Clarification — Grouped by Theme

## 🧱 Theme A: Network & DNS Consolidation

### A1. DNS Architecture — One Layer or Two?
The main architecture doc recommends **AdGuard Home on Kids VLAN only** for parental controls. The Multi-VLAN DNS doc introduces **Technitium as central DNS router + Pi-hole + Cloudflare Families + Quad9** — a multi-layered DNS with per-subnet policies.

- **Is Technitium the intended central DNS for ALL VLANs, with Pi-hole and AdGuard as upstream filters?

YES

- **Or is the Multi-VLAN doc a "future enhancement" beyond the base €0 design?

NO, this is base desing, that if came after initial design.

- **Does the current RB4011 do any DNS filtering at all, or just forward to 1.1.1.1/8.8.8.8?

just forwards.

### A2. IPv6 — Enable or Disable?
The current RB4011 config has conflicting IPv6 settings (disabled in settings but active in addresses/firewall). The new architecture doc doesn't mention IPv6.

- **Fully disable IPv6, or fully enable it on the new design?

fully enable it

- **Does your ISP (Telekom Slovenije?) provide IPv6 via PPPoE?

yes it does, /56 prefix

### A3. CAPsMAN — Local Forwarding or Tunnel?
The architecture doc recommends `local-forwarding=no` but mentions local forwarding is also possible.

- **Which mode is preferred?**

I would like centrally managed vlans and leave configuration of APs to minimum

- **Are all APs hardwired (making local forwarding safe), or are there mesh hops?

all APs are wired

---

## 🖥️ Theme B: Home Server Hardware

### B1. Minisforum MS-A2 vs Custom Ryzen Server
The Slovenian voice assistant doc references **Minisforum MS-A2** (with NPU) as the AI processing brain. All hardware/cost docs describe the **custom Ryzen 9 9900X + Radeon AI PRO R9700** server.

- **Is the MS-A2 a separate, smaller device dedicated to voice processing?**

No, I woud like all llm procesing centrally managed. This is also the reason that M2 idea was omitted and new server idea emmerged
- **Or was MS-A2 an earlier idea replaced by the custom server?

Yes M2 was replaced with custom server. But since i allready have RX 7600 at home i will probably just try with this and if not sufficient i will go with the new custom server route. This was experiment to see how much does it costs.

- **If separate: where does it sit — in the rack, in the kitchen, elsewhere?**

Central LLM mashine (existing with RX 7600 or new with R 9700) will be inside the rack. In the rack the re already router, switch and ISP device and enough room for existing or new server.

### B2. Proxmox on the Home Server?
The new server is described as running Proxmox VE with LXC containers. But the hardware doc focuses heavily on bare-metal Ollama GPU passthrough.

- **Is Proxmox the intended hypervisor for the home server?**

YES

- **Will the R9700 GPU be passed through to a single VM/LXC, or shared across multiple?**

RX7600 or new R9700 will be used by 1 lcx for ollama and, , if possible, by VM/lcx for steam streaming

- **The VRAM management strategy (Programming/Family/Sleep modes) — is this automated by a script, Home Assistant, or Ollama's built-in `keep_alive`?**

Ollama's keep alive

### B3. Open-Frame Bench — Family Acceptance?
The ALAMENGDA open-frame bench sits horizontally on the rack floor — functionally brilliant but visually exposed.

- **Is the rack in a closed cabinet (so nobody sees it)?**

YES, rack is in the closed cabinet (one side is not present for better air circulation) and hidden. Rack as it is has hight family acceptance

- **Are there dust/pet/small-child concerns with an open-air build?**

rack is closed in cabinet and even with 1 side off is pet and kids safe.

- **Any plans for a dust filter or mesh cover?**

No plan. What do you reccomend?

### B4. Second GPU — When?
The motherboard was chosen for x8/x8 dual-GPU support. The cost breakdown lists only 1× R9700.

- **When is the second GPU planned?**

Mybe I can live in config everithing with existing RX7600, and maybe i will need 1 additional R9700. If I buy new server i want to be future proof, as i believe different uses for local llm will only rise, not fall.

- **What triggers the purchase — running out of VRAM for larger models, or specific new use cases?**

I will buy new server with GPU for interference when needed. I just want preview of expenses if i go this route and to put prices of public apis for llms into the perspective.

- **Will the second GPU also be a R9700, or a different model?**

It is not desided, maybe something newer in the future. Depends when there will be need of enought size for investment

---

## ☁️ Theme C: Cloud VPS

### C1. Dedicated Server or Cloud VPS?
The architecture doc favors a **dedicated Hetzner server** (~€35/mo) for Proxmox. The cheaper **CX43 cloud VPS** (~€15.90/mo) is listed as alternative.

- **Which path are you leaning toward?**

I am leaning tovard Contabo Storage VPS 30 for VPS (6 vCPU, 18 GB RAM
1 TB SSD), hertzner Storagebox (1TB) and Idrive e2 for Kopia storage

- **Do you actually need Proxmox on the VPS, or would Docker Compose suffice?**

I will start with athentik, traefik, immich, opencloud, tehnitium, pihole, but will add observability and monitoring services so i prefer proxmox.

- **Is the dedicated server overkill for 4 family members + 4 external users?**

Yes, absolutely

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

Immich is on VPS with remote machine learning at home server

- **If Immich is on VPS: are original-quality photos stored in the cloud? Privacy concerns?**

I now store photos at google photos, later, after completing this homelab i will store them on Hertzner storagebox

- **If photos are on the home server: how do you access them remotely?** (WireGuard site-to-site tunnel handles this)

photos should be publicly accessible, as are now with google photos.

- **Kopia: backing up the VPS, the home server, or both?**

kopia backing up both

### C3. "Pangolin" — What Is It?
The architecture doc mentions "Pangolin" as a WAF/reverse proxy alongside Traefik, but the družinski web sistem doc uses only Traefik.

- **Is Pangolin a specific product (https://github.com/fosrl/pangolin)?**
- **Is it still part of the plan, or did Traefik absorb its role?**

I will not use Pangolin, I will user Traefik.

---

## 🔐 Theme D: VPN & Remote Access

### D1. WireGuard vs Headscale — One, the Other, or Both?
The docs describe **both** natively:
- WireGuard on RB4011 for site-to-site and road-warrior
- Headscale (self-hosted Tailscale) on Docker for mobile mesh

- **Is Headscale an alternative TO WireGuard road-warrior, or complementary (for phones only)?**

its complementary for mobile devices and easier maintability if I am incapacitated

- **If both: does Headscale go through the WireGuard tunnel to the VPS?**

I would like this, yes


- **Which one does the family use on their phones?** (Headscale has a simpler mobile app)

At the moment they use wiregourd, but i would like to change this to Headscale

### D2. Travel Router — Which Device?
- hAP ac² (mentioned in `potovalni vpn prompt.md`)
- mAP lite (mentioned in architecture doc as €30 option)
- hEX ac (mentioned in `potovalni.vpn.md` — hEX is wired-only, should be hAP)

- **Which spare device becomes the travel router?**

hAP ac2, will not buy mAP lite for now

### D3. Travel Router WAN — Captive Portal Implementation
The Sploax/KORP concept is brilliant but the MikroTik Hotspot `on-login` script to reconfigure the wlan1 station is non-trivial.

- **Has this been tested or prototyped?**

not yet

- **What happens if the hotel Wi-Fi has its own captive portal (common)?** — The user would need to first connect a phone directly to hotel Wi-Fi, accept the portal, THEN switch to the travel AP... or does the travel AP somehow tunnel the hotel's captive portal through?

User has to connect phone directly to the hotel wifi first. This should be in the documentation.

- **Fallback plan if Sploax doesn't work as expected?**

use Headscale

---

## 🏠 Theme E: Smart Home & Voice

### E1. Voice Assistant Activation
The Guition ESP32-S3 listens for a wake word ("Hey Kogler"?) but the doc doesn't specify the wake word engine.

- **What wake word detection runs on the ESP32-S3?** (ESP-SR? microWakeWord? Custom?)

Dont know, suggest something.

- **What's the activation word?**

Not decided yet, must take meeting with wife and kids, but someting like 'Hey, asistant!'

- **Is the wake word in Slovenian?** (This significantly limits off-the-shelf options)

If slovenian language severily limit options i will tel my family to use english pronounciation

### E2. Home Assistant Entity List
The TileBoard/Grafana prompts are templates waiting for the actual entity list.

- **Do you have the Home Assistant entity list?** (The prompt says "[TUKAJ PRIPEPNAJ/VPIŠI SVOJ SEZNAM ENTITET]")

I have

- **Is the current HA instance running and accessible?**

yes, and in use every day

### E3. WiiM Bar — HDMI eARC
The WiiM Bar connects to your future TV via HDMI eARC.

- **Do you have the TV yet, or is it also planned?**

I have TV (14 years old), but new is planned and i will buy new TV and the soundbar at the same time

- **If no TV: does the WiiM Bar work standalone for music via Chromecast?**

I dont have soundbar yet.

---

## 🔧 Theme F: IaC & Automation

### F1. "deblab" — What Is It?
The Ansible inventory targets `deblab` at 10.10.1.125.

- **Is deblab the current test VM (Hyper-V or WSL2)?**

yes, this is test VM on WSL2

- **Will the new Ryzen server get a different hostname?**

probably yes

- **Is the Ansible workflow: laptop → deblab (test) → production server?**

I will use laptop to orcestrate test lab and production server

### F2. 1Password Integration
The Ansible playbook uses 1Password lookup for secrets (Kopia password, Authentik secrets, DB passwords).

- **Is the 1Password Service Account already set up?**

yes and in use everiday

- **Does the OP_SERVICE_ACCOUNT_TOKEN have the right vault access?**

yes, it works on test VM (deblab)

### F3. Ansible Roles — Prioritization
Three roles are commented out: `storage`, `identity`, `apps`.

- **What's the priority order for implementing these?**

No priority just  placeholders

- **Will you write them yourself or generate them?**

generate

---

## 📋 Theme G: Documentation & "Bus Factor"

### G1. Documentation Standard
The ultimate goal is that the family can replicate everything from GitHub + backups.

- **What format should the family documentation be?** (Markdown in repo, printed binder, wiki?)

markdown in repo

- **Should it be bilingual** (Slovenian for family, English for technical)?

yes, it should be in slovenian language, but some technical staff should stay in english

- **Where is the GitHub repo hosted?** (Forgejo on VPS? Public GitHub? Both mirrored?)

currently on private github account, goal is to live in selhosted forgeo eith backups and mirrored to my github account

### G2. Backup Validation
Kopia and db-backup are planned but not yet running.

- **How will you test restores?** (Quarterly restore drill?)

yes, but more yearly than quaterly

- **Who in the family knows the backup password?**

we have family safe and inside is a paper woth 1password master password and recovery codes. I will add link to this github repo (selhosted forgea and public github) with readme.md as starting point of documentation

- **Is the Kopia master password stored in 1Password?** (Ansible references `kopia_master_password`)

yes it is

### G3. Physical Backup
In case of fire/flood at home: the VPS is remote, but what about home server data?

- **Are critical configs pushed to the VPS Git server (off-site backup)?**

all conifg should be on github once homelab is finished. but yes, I already have all this files on github.

- **Are Immich photos also on the VPS, or only at home?**

currently on google photos, but i will move then to hertzner storagebox once everiting in configured with idempotent ansible scripts

---

## 🎯 Priority Questions (Top 5 for Next Discussion)

1. **Immich: VPS or home server?** — This determines storage layout, backup strategy, and monthly costs.

VPS

2. **Headscale vs WireGuard for family phones?** — This determines the "wife-friendly" remote access story.

Headscale

3. **Minisforum MS-A2: separate device or replaced?** — Resolves a hardware conflict.

replaced with custom server build, also it is not sure if i need new server, i will try with existing hardvare first

4. **Dedicated server or CX43 VPS?** — Budget impact and Proxmox requirement.

Contoso VPS, Hertzner storagebox, Idrive e2 for backup

5. **Wake word and voice pipeline for Slovenian?** — Feasibility of the local voice assistant.

In english, for more options. Its only 2 short words - but not desided which - yet.
