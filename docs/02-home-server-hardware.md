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
| **HP MicroServer Gen8** | Main ZFS storage server — tank mirror (4 TB) + backup RAIDZ2 (6 TB), NFS, Cockpit, iLO4 remote mgmt |
| **SilverStone TS43xx** | Bulk storage enclosure — media archive, photo archive, cold data |

---

### Primary Server — i7-7700K Desktop

Bare-metal Debian, simultaneously serves as the family desktop PC and a 24/7 Docker host.

#### Hardware

| Component | Detail |
|-----------|--------|
| CPU | Intel i7-7700K (4C/8T, 4.2 GHz base, 4.5 GHz boost, Kaby Lake, 14 nm) |
| Motherboard | ASRock Z270 Extreme4 (AMI UEFI BIOS, Z270 chipset) |
| iGPU | Intel HD 630 → dedicated to Linux desktop (family PC) |
| dGPU | AMD Radeon RX 7600 8 GB → dedicated to Docker AI containers |
| NIC | Intel i350-T2 (one port used — VLAN trunk to CRS328 switch) |
| RAM | 48 GB DDR4 (4× Corsair Vengeance LPX, DDR4-2400) |
| └ DIMM 1 | 8 GB CMK16GX4M2A2400C14 (SK Hynix) |
| └ DIMM 2 | 16 GB CMK32GX4M2A2400C14 (Samsung) |
| └ DIMM 3 | 8 GB CMK16GX4M2A2400C14 (SK Hynix) |
| └ DIMM 4 | 16 GB CMK32GX4M2A2400C14 (Samsung) |
| Storage | 2× NVMe SSDs |
| └ Drive 1 | Samsung SSD 970 EVO 1TB — OS, Docker volumes, DBs, LLM models |
| └ Drive 2 | Samsung SSD 960 EVO 500GB — bulk data, media, second-stage storage |
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
| CPU | Intel Xeon E3-1230 V2 @ 3.30 GHz (4C/8T, Ivy Bridge) |
| RAM | 12 GB DDR3 ECC (AdvancedECC mode) — 1× 4 GB HP + 1× 8 GB, DDR3-1600 UDIMMs |
| Boot | Crucial MX300 525 GB SSD (Crucial_CT525MX300SSD4) |
| HDD 1 | HGST 4 TB (HDN726040ALE614) — 60,070h, healthy |
| HDD 2 | Seagate IronWolf Pro 4 TB (ST4000NT001) — new, 7200rpm |
| SATA mode | AHCI / non-RAID (HP B120i controller disabled — ZFS has direct disk access) |
| NIC | Embedded dual-port Broadcom (1c:98:ec:0e:0d:38 / 39) |
| iLO | 4 (integrated) — FW 2.55 (Aug 2017), IP 10.10.1.49 (VLAN 99) |
| OS | Debian 13 (Trixie) minimal, headless, with ZFS 2.3+ |
| Expansion | PCIe x16 Gen3 slot → miniSAS card → SilverStone TS43xx |
| Location | Rack cabinet |

#### Roles

- **Primary ZFS pool "tank"** — Mirror: HGST 4TB + Seagate IronWolf Pro 4TB (4 TB usable, fully redundant)
- **Backup ZFS pool "backup"** — RAIDZ2: WD Red 3TB + 3× Toshiba P300 3TB via miniSAS (6 TB usable, 2-disk fault tolerance)
- **NAS / file server** — NFS/SMB shares for media, photos, documents, and Docker volumes
- **Local backup replication** — incremental ZFS snapshots (sanoid/syncoid) from tank → backup pool
- **Web UI** — Cockpit + cockpit-zfs for lightweight monitoring (~150 MB RAM)
- **Kopia relay** — optional cloud relay for off-site backup to iDrive e2 (critical datasets only)

#### Network

| Port | VLAN | Purpose |
|------|------|---------|
| 1 | 10 (Home) | Access port — file sharing, backup traffic |
| 1 | 99 (Mgmt) | Native — management access |

> **Note:** The Gen8 has a **dual-port embedded Broadcom NIC** (both ports available). Two options:
> - **Single trunk:** One port carries VLAN 10 (tagged) + VLAN 99 (native) — frees the second port for a future dedicated backup network
> - **Dedicated ports:** Port 1 → VLAN 10 (Home, file sharing), Port 2 → VLAN 99 (Mgmt, iLO)

#### Remote Management (iLO4 Integrated)

The Gen8 has a built-in **HP iLO4** management controller — no external KVM needed:

| Feature | Detail |
|---------|--------|
| **iLO IP** | 10.10.1.49 (VLAN 99) |
| **Firmware** | 2.55 (Aug 2017) — latest is 2.82 |
| **Access** | Web UI via HTTPS, Redfish API, SSH, IPMI |
| **iKVM** | HTML5 remote console (Java-free) — BIOS-level, virtual ISO mounting |
| **Power control** | Remote power on/off/reset, boot order, PXE |
| **Health monitoring** | Temperatures, fan speed, power draw, hardware logs |
| **Authentication** | Local admin account (`Administrator`) |

> **Note:** iLO is on VLAN 99 (management) and is accessible even when the host OS is down. No separate GL-RM1 KVM is needed for the Gen8 — the iLO4 covers all remote management needs for this machine.

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
├── Samsung SSD 970 EVO 1TB    → OS, Docker volumes, DBs, LLM models
├── Samsung SSD 960 EVO 500GB  → bulk data, media, second-stage storage
├── Kopia                      → off-site encrypted backup
│   └── to iDrive e2 / B2    via WAN (encrypted, dedup, S3)
└── NFS mounts                → HP MicroServer shares (media, bulk data)

HP MicroServer Gen8 (rack) — 12 GB ECC RAM, Debian 13 (Trixie)
├── Boot: Crucial MX300 525 GB SSD (boot only — no L2ARC/SLOG)
├── ZFS pool "tank" (primary storage — mirror)
│   ├── HGST 4TB (HDN726040ALE614)            — 60,070h, healthy
│   └── Seagate IronWolf Pro 4TB (ST4000NT001) — new, 7200rpm
│   └── Datasets:
│       ├── tank/important     → backed up (photos, documents, Docker data)
│       ├── tank/media         → backed up (movies, music, Immich library)
│       └── tank/downloads     → NOT backed up (GDrive/OneDrive syncs, temp data)
├── ZFS pool "backup" (local backup target — RAIDZ2)
│   └── SilverStone TS43xx via miniSAS
│       ├── WD Red 3TB (WD30EFRX)             — 45,500h
│       ├── Toshiba P300 3TB (HDWD130)        — 6,481h
│       ├── Toshiba P300 3TB (HDWD130)        — 8,093h
│       └── Toshiba P300 3TB (HDWD130)        — 8,156h
│       └── 6 TB usable, survives any 2 disk failures
├── ZFS snapshots              → automated via sanoid/syncoid
│   └── zfs send/recv         → incremental block-level replication to "backup" pool
│       └── Only tank/important and tank/media — excludes tank/downloads
└── Kopia (optional)           → critical datasets only → iDrive e2 (cloud)
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

### SMART Data Collection (Completed — July 2026)

All 7 drives were scanned via `smartctl` on a SystemRescue live ISO. Full report saved in `scripts/smart-report-20260728-172714.txt`.

| Device | Model | Size | Hours | Reallocated | Pending | Health |
|--------|-------|------|-------|-------------|---------|--------|
| sda | WD Red WD30EFRX (5400rpm CMR) | 3 TB | 45,500 | 0 | 0 | ✅ OK |
| sdb | HGST HDN726040ALE614 (7200rpm) | 4 TB | 60,070 | 0 | 0 | ✅ OK |
| sdc | Toshiba P300 HDWD130 (7200rpm) | 3 TB | 6,481 | 0 | 0 | ✅ OK |
| sdd | Crucial MX300 525 GB (SSD) | 525 GB | 55,828 | 0 (NAND) | 0 | ✅ OK (81% life left) |
| sde | Toshiba P300 HDWD130 (7200rpm) | 3 TB | 8,156 | **2,001** | **32** | ❌ **CRITICAL — zeroed & disposed** |
| sdf | Toshiba P300 HDWD130 (7200rpm) | 3 TB | 8,093 | 0 | 0 | ✅ OK |
| sdg | Toshiba P300 HDWD130 (7200rpm) | 3 TB | 8,156 | 0 | 0 | ✅ OK |

Additional SMART data collected from the **i7-7700K Desktop** (NVMe SSDs, via `smartctl` on Windows):

| Device | Model | Size | Hours | Used | Temp | Spare | Health |
|--------|-------|------|-------|------|------|-------|--------|
| nvme0 | Samsung SSD 970 EVO 1TB | 1 TB | 12,943 | 770 GB / 1 TB | ⚠️ **66°C / 87°C** | 98% | ✅ PASSED |
| nvme1 | Samsung SSD 960 EVO 500GB | 500 GB | 11,360 | 440 GB / 500 GB | ✅ 41°C / 50°C | 100% | ✅ PASSED |

**Key NVMe findings:**
- **970 EVO 1TB** has 48.8 TB written, 2% usage, 0 media errors. **Temperature sensor 2 reads 87°C** — above the critical threshold (85°C). Check case airflow around the M.2 slot.
- **960 EVO 500GB** has 30.5 TB written, 5% usage, 0 media errors. **226 unsafe shutdowns** — significantly more than the 970 EVO (39). D: drive has seen many power losses.

**Key decisions driven by SMART data:**
- **sde (Toshiba P300)** was critically failing (2,001 reallocated sectors + 32 pending, SMART: "FAILING_NOW") → zeroed with `dd if=/dev/zero of=/dev/sde bs=1M` and physically removed from the SilverStone enclosure
- **WD Red (45,500h)** and **HGST (60,070h)** are old but healthy (zero reallocated sectors) → placed in the backup pool (RAIDZ2 with 2-disk parity) for safe retirement
- **Crucial MX300 (55,828h, 81% life)** → boot drive only. No L2ARC or SLOG: 12 GB RAM is insufficient for L2ARC benefit, and the SSD lacks power-loss protection (PLP) needed for safe SLOG use
- **Seagate IronWolf Pro 4TB (ST4000NT001)** purchased new to pair with the HGST as a matched-speed (7200rpm) mirror for the main tank pool

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
| **Samsung SSD 970 EVO 1TB** | i7-7700K OS + Docker boot drive | Boot + apps | ~1.5 years |
| **Samsung SSD 960 EVO 500GB** | i7-7700K bulk data drive | Bulk data | ~1.3 years |
| **HP MicroServer Gen8** (Xeon E3, 12 GB RAM) | Main ZFS server — tank mirror + backup RAIDZ2 | Stays as storage server | ~10-12 years |
| **Crucial MX300 525 GB (SSD)** | Gen8 boot drive | Boot | ~6 years |
| **HGST 4TB + Seagate IronWolf Pro 4TB** | tank pool (mirror) | Primary storage | New + ~7 years |
| **SilverStone SST-TS43xx** + WD Red 3TB + 3× Toshiba P300 3TB | backup pool (RAIDZ2) | Local backup target | Mixed (old + new) |
| **Raspberry Pi 4** | Home Assistant (primary) | Stays as primary HA (backup LXC on Phase 2 server) | ~4 years |
| **Rack cabinet** | Houses router, switch, ISP ONT | + Phase 2 server | — |

---

## Home Assistant

- **Stays on Raspberry Pi 4** (in daily use — not worth migration risk)
- **Phase 1:** Backup as a Docker container on the Debian desktop (systemd unit, disabled by default — enable to promote)
- **Phase 2:** Backup LXC on Proxmox server as cold standby
- **HA configs** move from their own GitHub repo into this homelab repo