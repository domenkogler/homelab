# Home Server Hardware

> **Canonical doc.** Merges: `Stroškovnik za novi strežnik.md`, `new home server hardware configuration summary.md`, `nov strežnik.md` (superseded).  
> The MS-A2 mini-PC idea is **replaced** — all LLM processing is centralized on this server.

---

## Strategy

- **Centralized LLM:** All AI/ML workloads run here (voice STT/TTS, LLM inference, office AI tools)
- **Two-phase approach:**
  1. **Phase 1 (Immediate):** Use existing **i7-7700K + Radeon RX 7600** (already owned) as bare-metal Debian desktop — full hybrid homelab + family PC. See [Phase 1](#phase-1-bare-metal-debian-desktop-immediate) below.
  2. **Phase 2 (Future):** If RX 7600 is insufficient → buy the dedicated Ryzen server below (priced out for budget awareness). See [Phase 2: Target Build](#phase-2-target-build-if-phase-1-is-insufficient).

---

## Phase 1: Bare-Metal Debian Desktop (Immediate)

This phase uses the existing PC hardware **without any new purchases**. The machine simultaneously serves as the family desktop PC and a 24/7 Docker host for homelab services.

### Hardware

| Component | Detail |
|-----------|--------|
| CPU | Intel i7-7700K (4C/8T, 4.2 GHz base, 4.5 GHz boost) |
| iGPU | Intel HD 630 → dedicated to Linux desktop (family PC) |
| dGPU | AMD Radeon RX 7600 8 GB → dedicated to Docker AI containers |
| NIC | Intel i350-T2 (one port used — VLAN trunk to CRS328 switch) |
| RAM | 32 GB DDR4 |
| Storage | Local NVMe SSD |
| OS | Debian with XFCE or GNOME desktop |
| Location | Workstation desk (not rack-mounted) |

### Dual GPU Topology

- **Intel HD 630 (iGPU):** Primary display — Xorg runs exclusively here. Monitor connected to motherboard HDMI/DP. Family gets a responsive desktop for browsing, ONLYOFFICE, and OpenCloud sync.
- **Radeon RX 7600 (dGPU):** No monitor attached. Docker containers access it via `/dev/dri` and `/dev/kfd`. Used by Ollama (LLM inference), Immich-ML (face recognition), and optionally Sunshine (game streaming).
- **No SR-IOV, no PCI passthrough** — clean separation at Xorg level. Xorg config ensures the dGPU is never used for desktop compositing.

### Headless Boot

Docker containers start at boot via systemd units — **before any user logs in**:
- `restart: always` on all AI containers
- Scheduled system reboot at 04:00 (systemd timer)
- All services auto-restore in the background after reboot
- Family member logging out, switching users, or closing the desktop session does NOT affect running containers

### GPU VRAM Strategy

`OLLAMA_KEEP_ALIVE=5m` is set as an environment variable — after 5 minutes of LLM inactivity, Ollama unloads the model and frees VRAM. The RX 7600 then idles at low power until the next request.

| Mode | Active Models | VRAM Usage | Trigger |
|------|--------------|------------|---------|
| **LLM Active** | Qwen 2.5-Coder 14B or Llama 3.1 8B | 6–12 GB | API request received |
| **Voice + Vision** | Whisper STT + Piper TTS + Immich-ML | ~3–5 GB | Voice command or photo upload |
| **Idle** | None (after 5 min) | ~0 GB (GPU ~12 W) | No activity for 5 minutes |
| **Gaming** | None (Ollama + Immich-ML stopped) | 0 GB (GPU at full power) | User manually stops AI containers → launches Sunshine |

> **LLM is priority over gaming.** After gaming, `docker compose up -d ollama immich-ml` restores AI services.

### Remote Management

**GL.iNet Comet KVM (GL-RM1):**
- Connects to motherboard iGPU HDMI (no impact on desktop display)
- PoE-powered from CRS328 switch
- BIOS-level control, remote power/reset, virtual ISO mounting
- Works even if Debian crashes (OS-independent)

### Docker Services (Phase 1)

```
Debian Host:
├─ ollama (Docker)          → LLM inference, GPU via /dev/dri + /dev/kfd
├─ immich-ml (Docker)       → Face recognition, GPU via /dev/dri + /dev/kfd
├─ headscale (Docker)       → Tailscale coordination server
├─ technitium (Docker)      → Central DNS router (VLAN-aware)
├─ pihole (Docker)          → Ad-blocking DNS
├─ sunshine (Docker)        → Game streaming (manual start, secondary priority)
└─ kopia (Docker)           → Backup agent → iDrive e2
```

---

## Phase 2: Target Build (if Phase 1 is insufficient)

| Component | Model | Cost (€) |
|-----------|-------|----------|
| Motherboard | **ASUS ProArt B850-Creator WiFi NEO** (PCIe x8/x8) | 300 |
| CPU | **AMD Ryzen 9 9900X** (12C/24T, AM5) | 330 |
| CPU Cooler | **Thermalright Peerless Assassin 120 SE** (dual-tower air, 15.5 cm) | 35 |
| GPU | **AMD Radeon AI PRO R9700 32GB** (blower, 2-slot) | 1,350 |
| RAM | **Crucial Pro 64GB Kit DDR5** (CP2K32G64C40U5B) | 640 |
| PSU | **Corsair HX1500i** (1500W Platinum, digital monitoring) | 290 |
| NVMe 1 (AI/OS) | **Biwin Black Opal X570 PRO 2TB PCIe Gen5** (4GB DRAM) | 180 |
| NVMe 2 (Media) | **Lexar NM990 4TB PCIe Gen5** (TLC) | 310 |
| Chassis | **ALAMENGDA ALE01 DIY PC Test Stand** (open-frame, horizontal) | 130 |
| Remote Mgmt | **GL.iNet Comet KVM (GL-RM1)** + PoE + ATX kit | 120 |
| Network | **10Gtek SFP-10G-T Multi-Gigabit** (5Gbps to MikroTik) | 45 |
| **Total** | | **~4,449** |

### Physical Fit (Rack Clearance)

- **Total height:** 16.5 cm (fits under 35 cm limit — 18.5 cm air pocket above)
- **Depth:** 26.7 cm (fits in 58 cm cabinet — 31.3 cm buffer for cables)
- **PSU orientation:** Fan facing **up** (open air above, not choked against floor)
- **Isolation:** Rubber feet or anti-static mat between frame and rack floor

### Second GPU

- Motherboard chosen for **x8/x8** dual-GPU support
- Second GPU **not planned now** — only when LLM workloads demand it
- Could be a second R9700 or a future model (depends on timing)

### Dust Protection

> **Recommendation:** Since the rack is in a closed cabinet (even with one side open), dust is less of a concern than in open-air rooms. However, for peace of mind:
> - Add a **magnetic 120mm/140mm dust filter mesh** over any intake fan openings (€5–10 on Amazon)
> - The open-frame itself doesn't trap dust — periodic compressed-air dusting (every 6 months) is sufficient
> - The closed cabinet acts as a natural dust barrier

---

## Hypervisor: Proxmox VE

> **Why Proxmox on bare metal but not on VPS:** The Contabo VPS is already virtualized — nesting Proxmox adds overhead without benefit. Docker on Debian is lighter and sufficient for web services. Phase 2 bare metal is different: real hardware with a 32 GB GPU to share across services, 12 cores with headroom to spare, and a future Windows VM for gaming. Proxmox snapshots before Ansible runs mean instant rollback if something breaks — valuable when DNS and AI share the same box. Phase 1 on bare-metal Debian proves the GPU-sharing approach first; Phase 2 can stay Debian or move to Proxmox based on real experience.

### VM/LXC Layout

```
Proxmox Host (hostname TBD):
├─ LXC: ollama (unprivileged, GPU mapped via AMD ROCm)
│   └─ Ollama, Whisper STT, Piper TTS, LLM models
├─ LXC: docker-host
│   ├─ Home Assistant (or dedicated LXC?)
│   ├─ Headscale
│   ├─ Technitium DNS
│   ├─ n8n (office automation)
│   └─ Grafana + InfluxDB (monitoring)
├─ VM/LXC: steam-streaming (GPU shared if possible)
├─ (future) VM: Windows/Linux lab VMs
└─ Storage:
    ├─ NVMe Gen5 2TB → LXC root disks, DBs, LLM models
    └─ NVMe Gen5 4TB → media files (if not on VPS)
```

### GPU Strategy

- GPU mapped to **one LXC** for Ollama via AMD ROCm drivers
- If Steam streaming needs GPU: investigate sharing (AMD multi-user GPU support)
- **VRAM management:** Ollama's built-in `keep_alive` handles model loading/unloading:
  - **Programming mode:** Qwen 2.5-Coder 32B loaded (~32GB VRAM)
  - **Family mode:** Whisper + HA LLM + Piper TTS loaded (~7GB VRAM)
  - **Sleep mode:** All models unloaded, GPU idles at ~12W

---

## Remote Management (Phase 2)

**GL.iNet Comet KVM (GL-RM1):**
- Connects to motherboard iGPU HDMI (no impact on GPU)
- PoE-powered (from CRS328 switch)
- BIOS-level control, remote power/reset, virtual ISO mounting
- Works even if Proxmox crashes

---

### Existing Hardware (Phase 1 Active)

| Device | Phase 1 Role | Phase 2 Role |
|--------|-------------|-------------|
| Radeon RX 7600 | Primary AI GPU in Debian desktop | Retired or repurposed (replaced by R9700 32 GB) |
| Intel i7-7700K | Phase 1 host CPU | Retired or repurposed |
| Raspberry Pi 4 | Home Assistant (primary) | Stays as primary HA (backup LXC on Phase 2 server) |
| Rack cabinet | Houses router, switch, ISP ONT | + Phase 2 server |

---

## Home Assistant

- **Stays on Raspberry Pi 4** (in daily use — not worth migration risk)
- **Phase 1:** Backup as a Docker container on the Debian desktop (systemd unit, disabled by default — enable to promote)
- **Phase 2:** Backup LXC on Proxmox server as cold standby
- **HA configs** move from their own GitHub repo into this homelab repo