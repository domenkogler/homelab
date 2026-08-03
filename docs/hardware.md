# Hardware Overview

> **Role:** Broad context — all machines, phase strategy, role assignments.
> **Links to:** `hardware-oldsrv.md`, `hardware-gpu.md`, `hardware-nas.md`, `hardware-phase2.md`
> **Linked from:** `index.md`

---

## Strategy

- **Centralized LLM:** All AI/ML workloads run on the primary server GPU
- **Phased approach:**
  1. **Phase 1 (Immediate):** Use all existing hardware — no new purchases. i7-7700K serves as the sole Docker host. HP MicroServer Gen8 as ZFS storage server.
  2. **Phase 2 (Scale-up):** If insufficient → activate Contabo VPS ([`services-vps.md`](services-vps.md)), build dedicated Ryzen/Proxmox server ([`hardware-phase2.md`](hardware-phase2.md)), or both.
  3. **Phase 3 (Co-existence):** Selectively migrate services. Compose files and deployment config are host-agnostic — same Git repo, same Doco-CD.

---

## All Machines

| Machine | Phase 1 Role | Phase 2 Role |
|---------|-------------|-------------|
| **oldsrv** (i7-7700K + RX 7600 + 48 GB) | **Sole Docker host** — all Phase 1 services, family PC | AI/LLM only, or retired |
| **nas** (HP MicroServer, Xeon E3, 12 GB ECC) | ZFS pools (tank + backup), NFS, Cockpit | Permanent storage server |
| **SilverStone TS43xx** | Attached to nas via miniSAS — 4× 3 TB HDDs | Same |
| **Raspberry Pi 4** | Home Assistant (primary) | Stays primary HA |
| **VPS (Contabo)** | *Not used* | Public web stack |
| **custom** (Ryzen 9 + R9700) | *Not built* | Proxmox hypervisor |

---

## Storage Architecture

```
oldsrv (desk)
├── Samsung SSD 970 EVO 1TB    → OS, Docker volumes, DBs, LLM models
├── Samsung SSD 960 EVO 500GB  → bulk data, media
├── Kopia                      → off-site encrypted backup → iDrive e2
└── NFS mounts                → nas shares

nas (rack) — Debian 13, ZFS
├── Boot: Crucial MX300 525 GB SSD
├── ZFS pool "tank" (mirror) — HGST 4TB + Seagate IronWolf Pro 4TB
│   ├── tank/important          → backed up
│   ├── tank/media              → backed up
│   └── tank/downloads          → NOT backed up
├── ZFS pool "backup" (RAIDZ2) — SilverStone via miniSAS
│   └── WD Red 3TB + 3× Toshiba P300 3TB (6 TB usable)
└── ZFS snapshots → zfs send/recv → backup pool (sanoid/syncoid)
```

---

## Key Design Decisions

1. **Phase 1 uses zero new hardware** — everything is existing
2. **Dual GPU on oldsrv:** iGPU for desktop, dGPU for Docker AI containers
3. **Docker is portable** — same compose files deploy on bare metal, VPS, or Proxmox VM
4. **3-2-1 backup:** 3 copies (live + local ZFS + cloud Kopia), 2 media (SSD/HDD + cloud), 1 off-site (iDrive e2)
5. **Ansible is OS-only** — system provisioning once. App lifecycle is GitOps via Doco-CD.

---

## Document Map

| For | Read |
|-----|------|
| i7-7700K Docker host + family PC | [`hardware-oldsrv.md`](hardware-oldsrv.md) |
| Shared GPU resource (VRAM, topology) | [`hardware-gpu.md`](hardware-gpu.md) |
| NAS ZFS storage server (+ external SilverStone case) | [`hardware-nas.md`](hardware-nas.md) |
| Phase 2 Ryzen/Proxmox build | [`hardware-phase2.md`](hardware-phase2.md) |
| Subscriptions & costs | [`subscription.md`](subscription.md) |