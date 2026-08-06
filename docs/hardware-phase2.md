---
title: Phase 2 Target Build (Ryzen + Proxmox)
role: detail
domain: hardware
status: deferred
tags: [hardware, phase2, proxmox]
---
# Phase 2 Target Build (Ryzen + Proxmox)

> **Role:** Detail — future scale-up server. Only built if Phase 1 hardware is insufficient.
> **Links to:** `hardware-gpu.md`, `services-vps.md`
> **Linked from:** `hardware.md`

---

## Bill of Materials

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

---

## Physical Fit

- **Total height:** 16.5 cm (fits under 35 cm rack limit — 18.5 cm air pocket above)
- **Depth:** 26.7 cm (fits in 58 cm cabinet — 31.3 cm buffer)
- **PSU orientation:** Fan facing up (open air, not choked against floor)
- **Isolation:** Rubber feet or anti-static mat between frame and rack floor

---

## Second GPU

- Motherboard chosen for **x8/x8** dual-GPU support
- Second GPU **not planned now** — only when LLM workloads demand it

---

## Hypervisor: Proxmox VE

### VM/LXC Layout

```
Proxmox Host:
├─ VM: docker-host (Docker + Doco-CD)
│   ├─ Edge: Traefik, CrowdSec
│   ├─ Identity: Authentik
│   ├─ Platform: OpenCloud, Immich, Forgejo
│   ├─ AI: Ollama, Immich-ML (GPU passthrough)
│   ├─ DNS: Technitium, Pi-hole
│   ├─ VPN: Headscale
│   ├─ Backup: Kopia, DB Backup
│   ├─ Observe: Alloy, Prometheus, Loki, Grafana, blackbox
│   └─ Dashboard: Homepage
├─ LXC: home-assistant (backup to RPi 4 primary)
├─ LXC: n8n (office automation — reuses the Phase-1 n8n alert router)
├─ VM/LXC: steam-streaming (GPU shared if possible)
├─ (future) VM: Windows/Linux lab VMs
└─ Storage:
    ├─ NVMe Gen5 2TB → VM root disks, DBs, LLM models
    └─ NVMe Gen5 4TB → media files
```

### GPU Strategy

- GPU mapped to docker-host VM/LXC via AMD ROCm drivers
- If Steam streaming needs GPU: investigate sharing (AMD multi-user GPU support)
- See [`hardware-gpu.md`](hardware-gpu.md) for VRAM modes

---

## Why Proxmox (Only on Bare Metal)

- Contabo VPS is already virtualized — nesting Proxmox adds overhead
- Phase 2 bare metal: real hardware, 32 GB GPU to share, 12 cores
- Proxmox snapshots before Ansible runs = instant rollback if DNS/AI breaks
- Phase 1 on bare-metal Debian proves the GPU-sharing approach first

---

## Remote Management

**GL.iNet Comet KVM (GL-RM1):**
- Motherboard iGPU HDMI
- PoE-powered from CRS328
- BIOS-level control, remote power/reset, virtual ISO mounting
- Works if Proxmox crashes

---

## Phase 2 vs VPS Co-existence

| Target | CD Tool | Why |
|--------|---------|-----|
| **oldsrv** (local Docker) | Doco-CD | Fast, drift-correcting, no SSH |
| **Phase 2 Proxmox** (local VM Docker) | Doco-CD | Same container, same config — portable |
| **VPS** (remote Docker) | Forgejo Actions + Ansible | Doco-CD needs socket access; SSH for remote |