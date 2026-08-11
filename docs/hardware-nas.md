---
title: HP MicroServer Gen8
role: detail
domain: hardware
status: active
tags: [hardware, nas, zfs]
---
# HP MicroServer Gen8

> **Role:** Detail — dedicated ZFS storage server.
> **Links to:** `backup.md`
> **Linked from:** `hardware.md`, `deployment-preseed.md`, `deployment-ansible.md`

---

## Hardware

| Component | Detail |
|-----------|--------|
| Model | HP ProLiant MicroServer Gen8 |
| CPU | Intel Xeon E3-1230 V2 @ 3.30 GHz (4C/8T, Ivy Bridge) |
| RAM | 12 GB DDR3 ECC (AdvancedECC) — 1× 4 GB + 1× 8 GB, DDR3-1600 |
| Boot | Crucial MX300 525 GB SSD (Crucial_CT525MX300SSD4) |
| HDD 1 | HGST 4 TB (HDN726040ALE614) — 60,070h |
| HDD 2 | Seagate IronWolf Pro 4 TB (ST4000NT001) — new, 7200rpm |
| SATA mode | AHCI / non-RAID (B120i disabled — ZFS direct disk access) |
| NIC | Embedded dual-port Broadcom |
| iLO | 4 (integrated) — FW 2.55, IP `ilo` per [`network-addresses.md`](network-addresses.md) (VLAN 99) |
| OS | Debian 13 (Trixie) minimal, headless, ZFS 2.3+ |
| Expansion | PCIe x16 Gen3 → miniSAS card → SilverStone |
| Location | Rack cabinet |

---

## ZFS Pool "tank" (Primary — Mirror)

| Drive | Model | Size | Hours | Health |
|-------|-------|------|-------|--------|
| sdb | HGST HDN726040ALE614 | 4 TB | 60,070 | ✅ |
| — | Seagate IronWolf Pro ST4000NT001 | 4 TB | new | ✅ |

- **4 TB usable**, fully redundant mirror — reserved for **user data** (backed up). No media.
- Datasets (all snapshotted + syncoid-replicated to `bulk`):
  - `tank/data/immich` → Immich **originals** only (photos/videos) — `recordsize=1M`
  - `tank/data/documents` → OpenCloud files — `recordsize=128K`
  - `tank/data/services` → nightly state pushes from oldsrv (Forgejo dump, n8n sqlite, …)
  - `tank/data/db-dumps` → tiredofit/db-backup output (pushed from oldsrv local scratch)
  - (older `tank/important` / `tank/data`-with-media plans → **superseded**: media moved to the `bulk`
    pool; only user data remains on `tank`. Full layout: [`storage-zfs.md`](storage-zfs.md))

### NFS Exports (→ oldsrv)

- Export **`tank/data`** (user data) → oldsrv **`/mnt/nas/data`**
- Export **`bulk/media`** (the *arr library + downloads) → oldsrv **`/mnt/nas/media`**
- Ownership: uid/gid **1000:1000** (domen) so *arr containers (`PUID/PGID 1000:1000`) can read/write
- Two exports because the datasets live on **different pools** (tank vs bulk) — they can't share one mount.
  TRaSH hardlinks only need a single filesystem **within** `bulk/media`, which is one dataset ✓
- Full layout/properties: [`storage-zfs.md`](storage-zfs.md)

> **TODO (IaC):** nas `storage` role — pool import, dataset creation with properties (see
> `storage-zfs.md`), `sanoid.conf` + systemd timers (sanoid.timer/syncoid.timer), NFS exports
> (`tank/data`, `bulk/media`), oldsrv fstab mounts, and the nightly push jobs (db dumps, service state,
> face thumbnails). Doc-only in the planning phase.

---

## ZFS Pool "bulk" (Local Secondary — RAIDZ2, mixed role)

Connected via **miniSAS** to the SilverStone SST-TS43xx external disk enclosure (4-bay, miniSAS-only — no USB/eSATA).

| Drive | Model | Size | Hours | Health |
|-------|-------|------|-------|--------|
| sda | WD Red WD30EFRX | 3 TB | 45,500 | ✅ |
| sdc | Toshiba P300 HDWD130 | 3 TB | 6,481 | ✅ |
| sdf | Toshiba P300 HDWD130 | 3 TB | 8,093 | ✅ |
| sdg | Toshiba P300 HDWD130 | 3 TB | 8,156 | ✅ |

- **6 TB usable**, survives any 2 disk failures
- sde (Toshiba P300, 2,001 reallocated + 32 pending) was zeroed and physically removed
- **Mixed role:** hosts the **syncoid replicas** of `tank/data/*` AND the **active media library**
  (`bulk/media`, no snapshots — redownloadable) AND the face-thumbnail copy (`bulk/data/immich-thumbs`,
  daily snapshots). Replica datasets retain the source snapshot schedules independently. Detail:
  [`storage-zfs.md`](storage-zfs.md)

### SilverStone SST-TS43xx (External Disk Enclosure)

The "bulk" pool above lives on an external **SilverStone SST-TS43xx** 4-bay disk case
(miniSAS only — no USB/eSATA), attached to the MicroServer miniSAS card. It serves
as the **local secondary pool**: syncoid replicas of `tank/data/*` (ZFS send/recv) plus the
**active media library** (`bulk/media`) and the face-thumbnail push target (`bulk/data/immich-thumbs`)
— 12 TB raw / 6 TB usable in RAIDZ2 on consumer disks. `sde` was removed
(⚠️ critically failing: 2,001 reallocated + 32 pending sectors).

---

## Roles

- Primary ZFS pool "tank" — mirror, 4 TB usable — **user data only** (backed up)
- Secondary ZFS pool "bulk" — RAIDZ2, 6 TB usable — active media (unbacked) + data replicas + thumb copies
- NAS / file server — NFS shares: `tank/data` (user data), `bulk/media` (media); SMB for family deferred
- Local replication — sanoid/syncoid: `tank/data/*` → `bulk/data/*` (incremental, ≈ hourly)
- Web UI — Cockpit + cockpit-zfs (~150 MB RAM)
- **Kopia does not run on nas** — off-site backup originates from oldsrv (NAS-independent, see `backup.md`)

---

## Network

| Port | VLAN | Purpose |
|------|------|---------|
| 1 | 10 (Home) | Access port — file sharing, backup |
| 1 | 99 (Mgmt) | Native — management access |

Dual-port NIC. Option: single trunk (VLAN 10 tagged + 99 native) or dedicated ports.

---

## iLO4 Remote Management

Built-in — no external KVM needed.

| Feature | Detail |
|---------|--------|
| iLO IP | static — `ilo` (VLAN 99), see [`network-addresses.md`](network-addresses.md) |
| Firmware | 2.55 (Aug 2017) |
| Access | Web UI HTTPS, Redfish API, SSH, IPMI |
| iKVM | HTML5 remote console — BIOS-level, virtual ISO |
| Power | Remote on/off/reset, boot order, PXE |
| Health | Temperatures, fans, power, hardware logs |
| Auth | Local admin account |

---

## Boot Drive

| Drive | Model | Size | Hours | Health |
|-------|-------|------|-------|--------|
| sdd | Crucial MX300 525 GB | 525 GB | 55,828 | ✅ (81% life left) |

- Boot only — no L2ARC/SLOG
- L2ARC skipped: 12 GB RAM insufficient for benefit
- SLOG skipped: SSD lacks power-loss protection (PLP)