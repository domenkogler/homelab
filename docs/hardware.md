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

- **Inference is tiered, not centralized:** **spark** = the AI inference tier (family LLM/RAG serving),
  **oldsrv** = the pinned local-model legs it cannot host + media/ML sidecars, the **workstation** =
  client-side inference (FIM + vision). Per-model placement is decision-of-record in
  [`services-ai.md`](services-ai.md) §9, measured numbers in [`services-ai-bench.md`](services-ai-bench.md).
- **Phased build-out (the sequencing that was used):**
  1. **Phase 1 — existing hardware + the netcup VPS** (i7-7700K as GPU/LAN host, HP MicroServer Gen8 as ZFS
     storage, VPS active from day one as the public/observability tier; HD-93). No purchases.
  2. **Phase 2 — the dedicated NVIDIA GB10 spark node** ([`hardware-spark.md`](hardware-spark.md)); it
     replaced the planned Ryzen/Proxmox build
     ([deployment-rejected.md](deployment-rejected.md)).
  3. **Co-existence:** services migrate selectively. Compose files and deployment config are host-agnostic —
     same Git repo, same Ansible.

---

## All Machines

| Machine | Current role | Note |
|---------|-------------|------|
| **oldsrv** (i7-7700K + RX 7600 + 48 GB) | **GPU/LAN host** — jellyfin/*arr, immich-ml, sunshine, DNS secondary, HA standby, LAN (dev) tier + the pinned Vulkan STT/embed/rerank legs; thin Alloy collector → VPS | Family desktop too; **no family-LLM serving tier here** — generation is on spark; the only retained `ollama` container is the embed **fallback rung**, not a chat host) |
| **nas** (HP MicroServer, Xeon E3, 12 GB ECC) | ZFS pools (tank + bulk), NFS, Cockpit, NUT master, Kopia agent | Permanent storage server |
| **SilverStone TS43xx** | Attached to nas via miniSAS — 4× 3 TB HDDs | `bulk` pool |
| **Raspberry Pi 4** | Home Assistant **primary** (Debian + HA Container) + RaspberryMatic/HmIP-RFUSB + Technitium **tertiary** + `traefik-ha` edge + exit node | HA service VIP = `ha.kogler.si` |
| **VPS (netcup)** | **Public edge + live-data apps + observability backend + DNS primary + tailnet control** (HD-93/HD-40A) | The only public address = the away-access door |
| **spark** (ThinkStation PGX, NVIDIA GB10, 128 GB unified) | **AI inference node** — vLLM serving the pinned model set behind LiteLLM (`llm.kogler.si`) | Provisioned + live; text-only mode is the plan of record ([services-ai.md](services-ai.md) §9 #28) |
| **workstation** (admin laptop, AMD Strix Halo, 128 GB unified) | Client-side AI: **FIM autocomplete + visual judgment** locally; never a generation tier ([`hardware-workstation.md`](hardware-workstation.md)) | — |
| **PowerWalker VFI ICT/ICR IoT 3000** (UPS) | Protects nas + rack infra (see [`hardware-ups.md`](hardware-ups.md)) | — |

---

## Storage Architecture

```
oldsrv (desk)
├── Samsung SSD 960 EVO 500GB  → OS/system (ext4), configs — light writes (200 TBW)
├── Samsung SSD 970 EVO 1TB    → ZFS pool "nvme": DBs, service data, metrics, models, dumps
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
| NVIDIA GB10 vLLM node (spark) | [`hardware-spark.md`](hardware-spark.md) |
| Admin laptop = client-side inference (FIM + vision, NPU out) | [`hardware-workstation.md`](hardware-workstation.md) |
| Subscriptions & costs | [`subscription.md`](subscription.md) |

## Related

- [oldsrv — i7-7700K Docker Host](hardware-oldsrv.md)
- [Shared GPU Resource](hardware-gpu.md)
- [HP MicroServer Gen8](hardware-nas.md)
- [PowerWalker VFI ICT/ICR IoT 3000 (UPS)](hardware-ups.md)
- [spark — NVIDIA GB10 vLLM node](hardware-spark.md)
- [workstation — admin laptop as client-side inference tier](hardware-workstation.md)
