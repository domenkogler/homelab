---
title: Hardware Overview
role: index
domain: hardware
status: active
tags: [hardware, phases]
---
# Hardware Overview

> **Role:** Index — the hardware domain hub. Machine roster, phase strategy, and links to each `hardware-*.md` stack doc.
> **Links to:** `hardware-oldsrv.md`, `hardware-gpu.md`, `hardware-nas.md`, `hardware-ups.md`, `hardware-spark.md`
> **Linked from:** `index.md`

---

## Strategy

- **Centralized LLM:** All AI/ML workloads run on the primary server GPU
- **Phased approach:**
  1. **Phase 1 (Immediate, HD-93 day-one-edge):** existing hardware (i7-7700K as GPU/LAN host, HP MicroServer Gen8 as ZFS storage) **+ the netcup VPS** (active from day one as the public/observability tier). No other purchases.
  2. **Phase 2 (Scale-up):** dedicated NVIDIA GB10 **spark** node ([`hardware-spark.md`](hardware-spark.md)) — replaces the earlier planned Ryzen/Proxmox build (HD-42, superseded).
  3. **Co-existence:** services migrate selectively. Compose files and deployment config are host-agnostic — same Git repo, same Ansible.

---

## All Machines

| Machine | Role (Phase 1 — day-one edge) | Phase 2 Role |
|---------|-------------|-------------|
| **oldsrv** (i7-7700K + RX 7600 + 48 GB) | **GPU/LAN host** — ollama, immich-ml, jellyfin/*arr, sunshine, DNS, HA standby, homepage; thin Alloy collector → VPS (VPS self-observes on loopback + Dozzle on VPS, HD-135b) | AI/LLM + LAN core, or retired |
| **nas** (HP MicroServer, Xeon E3, 12 GB ECC) | ZFS pools (tank + backup), NFS, Cockpit | Permanent storage server |
| **SilverStone TS43xx** | Attached to nas via miniSAS — 4× 3 TB HDDs | Same |
| **Raspberry Pi 4** | Home Assistant (primary, Debian+HA Container) + RaspberryMatic/HmIP-RFUSB + Technitium secondary DNS | Stays primary HA |
| **VPS (netcup)** | **Public edge + live-data apps + observability backend** (HD-93/HD-40A, active day one) | Public tier + more |
| **spark** (ThinkStation PGX, NVIDIA GB10, 128 GB) | *Headless AI inference node (purchased, not yet provisioned)* | **Triton + NVFP4 model set** (replaces the planned Ryzen/R9700 build) |
| **PowerWalker VFI ICT/ICR IoT 3000** (UPS) | Protects nas + rack infra (see [`hardware-ups.md`](hardware-ups.md)) | Same |

---

## Storage Architecture

```
oldsrv (desk)
├── Samsung SSD 960 EVO 500GB  → OS/system (ext4), configs — light writes (200 TBW)
├── Samsung SSD 970 EVO 1TB    → ZFS pool "nvme": DBs, service data, TSDB, models, dumps
├── Kopia                      → off-site encrypted backup → Hetzner Storage Box (backup, far DC)
└── NFS mounts                → nas shares

nas (rack) — Debian 13, ZFS
├── Boot: Crucial MX300 525 GB SSD (no image backup — pools are self-describing)
├── ZFS pool "tank" (mirror) — HGST 4TB + Seagate IronWolf Pro 4TB — user data, BACKED UP
│   └── data/{immich, documents, services, db-dumps}
├── ZFS pool "bulk" (RAIDZ2) — SilverStone via miniSAS — MIXED role
│   ├── media/                active *arr library + downloads (hardlinks, NOT backed up)
│   ├── data/                 syncoid replicas of tank/data/* (hourly)
│   └── immich-thumbs/        face thumbnails (daily rsync ← oldsrv)
├── NFS exports → oldsrv: tank/data → /mnt/nas/data · bulk/media → /mnt/nas/media · bulk/data/immich-thumbs → /mnt/nas/thumbs
└── ZFS snapshots → sanoid/syncoid → bulk pool (data datasets only)
```

> Full dataset tree, properties, and replication: [`storage.md`](storage.md)

---

## Key Design Decisions

1. **Phase 1 uses zero new hardware** — everything is existing
2. **Dual GPU on oldsrv:** iGPU for desktop, dGPU for Docker AI containers
3. **Docker is portable** — same compose files deploy on bare metal, VPS, or Proxmox VM
4. **3-2-1 backup:** 3 copies (live + local ZFS + cloud Kopia), 2 media (SSD/HDD + cloud), 1 off-site (Hetzner Storage Box backup, far DC)
5. **Ansible deploys everywhere** — base system AND app lifecycle (VPS + oldsrv), one path.

---

## Document Map

| For | Read |
|-----|------|
| i7-7700K Docker host + family PC | [`hardware-oldsrv.md`](hardware-oldsrv.md) |
| Shared GPU resource (VRAM, topology) | [`hardware-gpu.md`](hardware-gpu.md) |
| NAS ZFS storage server (+ external SilverStone case) | [`hardware-nas.md`](hardware-nas.md) |
| Rack UPS — links, Modbus TCP, NUT/shutdown status | [`hardware-ups.md`](hardware-ups.md) |
| NVIDIA GB10 Triton node (spark) | [`hardware-spark.md`](hardware-spark.md) |
| Subscriptions & costs | [`subscription.md`](subscription.md) |

## Related

- [oldsrv — i7-7700K Docker Host](hardware-oldsrv.md)
- [Shared GPU Resource](hardware-gpu.md)
- [HP MicroServer Gen8](hardware-nas.md)
- [PowerWalker VFI ICT/ICR IoT 3000 (UPS)](hardware-ups.md)
- [spark — NVIDIA GB10 Triton node](hardware-spark.md)
