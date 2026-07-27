# Home Server Hardware

> **Canonical doc.** Merges: `Stroškovnik za novi strežnik.md`, `new home server hardware configuration summary.md`, `nov strežnik.md` (superseded).  
> The MS-A2 mini-PC idea is **replaced** — all LLM processing is centralized on this server.

---

## Strategy

- **Centralized LLM:** All AI/ML workloads run here (voice STT/TTS, LLM inference, office AI tools)
- **Two-phase approach:**
  1. **Phase 1 (Immediate):** Use **all existing hardware** — no new purchases. The i7-7700K serves as the primary Debian desktop + Docker host; the HP MicroServer Gen8 serves as backup target / NAS; the SilverStone TS43xx provides bulk storage. See [Phase 1: Existing Hardware](#phase-1-existing-hardware-immediate) below.
  2. **Phase 2 (Future):** If the RX 7600 GPU is insufficient for LLM workloads → buy the dedicated Ryzen server (priced out for budget awareness). See [Phase 2: Target Build](#phase-2-target-build-if-phase-1-is-insufficient).

---

## Phase 1: Existing Hardware (Immediate)

This phase uses **all existing hardware** without any new purchases. Three machines work together:

| Machine | Role |
|---------|------|
| **i7-7700K Desktop** | Primary server — family PC + 24/7 Docker host (LLM, DNS, backup agent) |
| **HP MicroServer Gen8** | Backup target + NAS — secondary storage, Kopia repository server |
| **SilverStone TS43xx** | Bulk storage enclosure — media archive, photo archive, cold data |

---

### Primary Server — i7-7700K Desktop

Bare-metal Debian, simultaneously serves as the family desktop PC and a 24/7 Docker host.

#### Hardware

| Component | Detail |
|-----------|--------|
| CPU | Intel i7-7700K (4C/8T, 4.2 GHz base, 4.5 GHz boost) |
| iGPU | Intel HD 630 → dedicated to Linux desktop (family PC) |
| dGPU | AMD Radeon RX 7600 8 GB → dedicated to Docker AI containers |
| NIC | Intel i350-T2 (one port used — VLAN trunk to CRS328 switch) |
| RAM | 48 GB DDR4 |
| Storage | Local NVMe SSD |
| OS | Debian with XFCE or GNOME desktop |
| Location | Workstation desk (not rack-mounted) |

#### Dual GPU Topology

- **Intel HD 630 (iGPU):** Primary display — Xorg runs exclusively here. Monitor connected to motherboard HDMI/DP. Family gets a responsive desktop for browsing, ONLYOFFICE, and OpenCloud sync.
- **Radeon RX 7600 (dGPU):** No monitor attached. Docker containers access it via `/dev/dri` and `/dev/kfd`. Used by Ollama (LLM inference), Immich-ML (face recognition), and optionally Sunshine (game streaming).
- **No SR-IOV, no PCI passthrough** — clean separation at Xorg level. Xorg config ensures the dGPU is never used for desktop compositing.

#### Headless Boot

Docker containers start at boot via systemd units — **before any user logs in**:
- `restart: always` on all AI containers
- Scheduled system reboot at 04:00 (systemd timer)
- All services auto-restore in the background after reboot
- Family member logging out, switching users, or closing the desktop session does NOT affect running containers

#### GPU VRAM Strategy

`OLLAMA_KEEP_ALIVE=5m` is set as an environment variable — after 5 minutes of LLM inactivity, Ollama unloads the model and frees VRAM. The RX 7600 then idles at low power until the next request.

| Mode | Active Models | VRAM Usage | Trigger |
|------|--------------|------------|---------|
| **LLM Active** | Qwen 2.5-Coder 14B or Llama 3.1 8B | 6–12 GB | API request received |
| **Voice + Vision** | Whisper STT + Piper TTS + Immich-ML | ~3–5 GB | Voice command or photo upload |
| **Idle** | None (after 5 min) | ~0 GB (GPU ~12 W) | No activity for 5 minutes |
| **Gaming** | None (Ollama + Immich-ML stopped) | 0 GB (GPU at full power) | User manually stops AI containers → launches Sunshine |

> **LLM is priority over gaming.** After gaming, `docker compose up -d ollama immich-ml` restores AI services.

#### Remote Management

**GL.iNet Comet KVM (GL-RM1):**
- Connects to motherboard iGPU HDMI (no impact on desktop display)
- PoE-powered from CRS328 switch
- BIOS-level control, remote power/reset, virtual ISO mounting
- Works even if Debian crashes (OS-independent)

#### Docker Services (Phase 1)

```
Debian Host (i7-7700K):
├─ ollama (Docker)          → LLM inference, GPU via /dev/dri + /dev/kfd
├─ immich-ml (Docker)       → Face recognition, GPU via /dev/dri + /dev/kfd
├─ headscale (Docker)       → Tailscale coordination server
├─ technitium (Docker)      → Central DNS router (VLAN-aware)
├─ pihole (Docker)          → Ad-blocking DNS
├─ sunshine (Docker)        → Game streaming (manual start, secondary priority)
├─ kopia (Docker)           → Off-site backup agent → iDrive e2
├─ sanoid/syncoid (cron)    → ZFS snapshots + replication to HP Gen8
```

---

### Backup & Storage Server — HP MicroServer Gen8

A dedicated secondary machine for ZFS-based storage, local backup replication, and network-attached storage. Runs Debian headless with ZFS on all drives.

#### Hardware

| Component | Detail |
|-----------|--------|
| Model | HP ProLiant MicroServer Gen8 |
| CPU | Intel Xeon E3 (unknown variant) |
| RAM | 16 GB DDR3 ECC |
| HDD 1 | WD Red 3 TB (WD30EFRX) |
| HDD 2 | HGST 4 TB (SATA 6 Gb/s) |
| OS | Debian minimal (headless) with ZFS |
| Expansion | Additional PCIe card with 2× miniSAS external ports |
| Location | Rack cabinet |

#### Roles

- **Primary ZFS storage pool** — WD Red 3TB + HGST 4TB (mirror or separate datasets)
- **ZFS backup pool** — SilverStone drives via miniSAS (ZFS send/recv target from primary pool)
- **NAS / file server** — NFS/SMB shares for media, documents, and ISO images
- **Local backup replication** — incremental ZFS snapshots sent from the primary pool to the backup pool
- **Kopia relay** — optional cloud relay for off-site backup to iDrive e2

#### Network

| Port | VLAN | Purpose |
|------|------|---------|
| 1 | 10 (Home) | Access port — file sharing, backup traffic |
| 1 | 99 (Mgmt) | Native — management access |

> **Note:** Only one port on the CRS328. If the Gen8 has a single NIC, use a trunk port (VLAN 10 tagged, VLAN 99 native). If dual NIC, dedicate one to each VLAN.

---

### Bulk Storage — SilverStone SST-TS43xx

External 4-bay enclosure connected to either the i7-7700K or the HP MicroServer.

#### Hardware

| Component | Detail |
|-----------|--------|
| Model | SilverStone SST-TS43xx |
| HDDs | 4× Toshiba P300 3 TB (12 TB raw) |
| Connection | **miniSAS only** (no USB, no eSATA) — connects to HP Gen8 miniSAS card |
| Location | Rack cabinet (near server) |

#### Roles

- **Media archive** — raw Immich photos, video files, downloads
- **Cold data** — infrequently accessed files, old backups
- **Scratch space** — large temporary data before triage

#### Connection Decision

| Connect to | Pros | Cons |
|------------|------|------|
| **HP MicroServer** | miniSAS card available; everything in the rack | Extra network hop for i7-7700K access |
| **i7-7700K** | Direct access from Docker services | Would need a separate HBA card (no miniSAS on motherboard) |

> **Decision: SilverStone → HP Gen8 miniSAS card.** The SilverStone is miniSAS-only (no USB or eSATA). The HP Gen8 is the only machine with a free miniSAS port. All 6 HDDs live in the rack, managed by the Gen8.

---

### Storage Architecture & Data Flow

```
i7-7700K Desktop (desk)
├── NVMe SSD (local)          → OS, Docker volumes, DBs, LLM models
├── Kopia                      → off-site encrypted backup
│   └── to iDrive e2 / B2    via WAN (encrypted, dedup, S3)
└── NFS mounts                → HP MicroServer shares (media, bulk data)

HP MicroServer Gen8 (rack) — 16 GB ECC RAM
├── ZFS pool "tank" (primary storage)
│   ├── bay 1: WD Red 3TB (WD30EFRX)
│   ├── bay 2: HGST 4TB
│   ├── bay 3: (free — can host 2× Toshiba from SilverStone)
│   └── bay 4: (free)
├── ZFS pool "backup" (local backup target — ZFS send/recv)
│   └── SilverStone TS43xx via miniSAS
│       └── 2–4× Toshiba P300 3TB → RAIDZ or mirror
├── ZFS snapshots              → automated via sanoid/syncoid or cron
│   └── zfs send/recv         → incremental block-level replication to "backup" pool
└── Kopia (optional)           → snapshots critical datasets → iDrive e2 (cloud)
```

#### Backup Strategy: ZFS + Kopia (Dual Layer)

| Copy | Location | Medium | Transport | Speed |
|------|----------|--------|-----------|-------|
| **Live data** | i7-7700K NVMe + HP Gen8 ZFS pool | SSD + HDD | — | — |
| **Local backup** | HP Gen8 SilverStone pool (ZFS send/recv) | HDD | Block-level incremental | Fast (LAN) |
| **Off-site backup** | iDrive e2 (Kopia encrypted snapshots) | Cloud | Object storage | Slow (WAN) |

**Why ZFS + Kopia instead of Kopia-only:**

| Layer | Tool | What It Does |
|-------|------|-------------|
| **Filesystem** | ZFS | Block-level checksums, snapshots, compression, self-healing |
| **Local replication** | ZFS send/recv | Incremental block-level sync to backup pool — 10–50× faster than Kopia walking the filesystem for TB-scale data |
| **Off-site backup** | Kopia | Client-side encryption, cross-time dedup, S3-compatible cloud push |

- ZFS snapshots are **instantaneous and immutable** — no window where a backup tool is mid-scan while files change
- ZFS send/recv transfers only changed blocks since the last snapshot, not re-scanned files
- Kopia remains for cloud off-site (encryption + dedup + S3) — it's the right tool for that

- **3 copies:** live (tank) + local (backup pool) + off-site (iDrive e2)
- **2 media:** SSD + HDD + cloud
- **1 off-site:** cloud storage

> **Hardware failure scenario:** If the i7-7700K dies, HP Gen8 holds the authoritative ZFS pool. If the HP Gen8 dies, the SilverStone backup pool is a physically separate enclosure. If both die, restore from cloud via Kopia.

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

## Hypervisor: Proxmox VE (Phase 2)

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

## All Hardware & Role Assignment

| Device | Phase 1 Role | Phase 2 Role | Age |
|--------|-------------|-------------|-----|
| **Intel i7-7700K** + RX 7600 + 48 GB DDR4 | Primary server — Debian + Docker (LLM, DNS, AI) | Retired or repurposed | ~7 years |
| **HP MicroServer Gen8** (Xeon E3) + WD Red 3TB + HGST 4TB | Backup target + NAS | Stays as backup server | ~10-12 years |
| **SilverStone SST-TS43xx** + 4× Toshiba P300 3TB | Bulk storage enclosure | Bulk storage enclosure | Unknown |
| **Raspberry Pi 4** | Home Assistant (primary) | Stays as primary HA (backup LXC on Phase 2 server) | ~4 years |
| **Rack cabinet** | Houses router, switch, ISP ONT | + Phase 2 server | — |

---

## Home Assistant

- **Stays on Raspberry Pi 4** (in daily use — not worth migration risk)
- **Phase 1:** Backup as a Docker container on the Debian desktop (systemd unit, disabled by default — enable to promote)
- **Phase 2:** Backup LXC on Proxmox server as cold standby
- **HA configs** move from their own GitHub repo into this homelab repo