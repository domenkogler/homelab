# Home Server Hardware

> **Canonical doc.** Merges: `Stroškovnik za novi strežnik.md`, `new home server hardware configuration summary.md`, `nov strežnik.md` (superseded).  
> The MS-A2 mini-PC idea is **replaced** — all LLM processing is centralized on this server.

---

## Strategy

- **Centralized LLM:** All AI/ML workloads run here (voice STT/TTS, LLM inference, office AI tools)
- **Two-phase approach:**
  1. **Immediate:** Try with existing **Radeon RX 7600** (already owned) to validate workloads
  2. **Future:** If RX 7600 is insufficient → buy the new server below (priced out for budget awareness)
- **Location:** Inside a **closed rack cabinet** (one side open for airflow, pet/kid safe, hidden, high family acceptance)

---

## Target Build (if existing RX 7600 is insufficient)

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

## Remote Management

**GL.iNet Comet KVM (GL-RM1):**
- Connects to motherboard iGPU HDMI (no impact on GPU)
- PoE-powered (from CRS328 switch)
- BIOS-level control, remote power/reset, virtual ISO mounting
- Works even if Proxmox crashes

---

## Existing Hardware (Intermediate Phase)

| Device | Current Role | Future Role |
|--------|-------------|-------------|
| Radeon RX 7600 | Test GPU for LLM feasibility | Retired or repurposed if new server built |
| Raspberry Pi 4 | Home Assistant | Stays as primary HA (backup LXC on server) |
| Rack cabinet | Houses router, switch, ISP ONT | + new server |

---

## Home Assistant

- **Stays on Raspberry Pi 4** (in daily use — not worth migration risk)
- **Backup LXC on home server** as a cold standby (can be promoted if Pi fails)
- **HA configs** move from their own GitHub repo into this homelab repo