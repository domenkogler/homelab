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

- **4 TB usable**, fully redundant mirror
- Datasets:
  - `tank/important` → backed up (photos, documents, Docker data) — separate from the media export
  - `tank/data` → backed up (bulk media + *arr library) — **single NFS export** → oldsrv `/mnt/nas/data`
    - `media/{movies,tv,music}` — long-term library (Jellyfin, Sonarr/Radarr/Lidarr)
    - `downloads/{incomplete,complete}` — TRaSH scratch: **hardlink-imported** into `media/`, then pruned.
      Hardlinks need one filesystem, so downloads live INSIDE the snapshotted dataset (accepted
      trade-off — coarser sanoid cadence bounds transient snapshot cost, see `backup.md`)
  - (older `tank/downloads`-as-dataset plan → **superseded**: a separate dataset would break TRaSH
    hardlinks; downloads now live under `tank/data`)

### NFS Export (→ oldsrv)

- Export: **`tank/data`** — a single export, no sub-mounts (hardlinks require one filesystem)
- Client mount: oldsrv at **`/mnt/nas/data`** (fstab / Ansible)
- Ownership: uid/gid **1000:1000** (domen) so *arr containers (`PUID/PGID 1000:1000`) can read/write
- `tank/important` is **not** part of this export (separate share, TBD)

> **TODO (IaC):** nas storage role — NFS export config (`tank/data`), `sanoid.conf` for `tank/data`
> (no 15-min tier → hourly(24)+daily(7)+weekly(4)+monthly(3); `tank/important` unchanged), and the
> oldsrv fstab mount. Doc-only in the planning phase.

---

## ZFS Pool "backup" (Local Target — RAIDZ2)

Connected via **miniSAS** to the SilverStone SST-TS43xx external disk enclosure (4-bay, miniSAS-only — no USB/eSATA).

| Drive | Model | Size | Hours | Health |
|-------|-------|------|-------|--------|
| sda | WD Red WD30EFRX | 3 TB | 45,500 | ✅ |
| sdc | Toshiba P300 HDWD130 | 3 TB | 6,481 | ✅ |
| sdf | Toshiba P300 HDWD130 | 3 TB | 8,093 | ✅ |
| sdg | Toshiba P300 HDWD130 | 3 TB | 8,156 | ✅ |

- **6 TB usable**, survives any 2 disk failures
- sde (Toshiba P300, 2,001 reallocated + 32 pending) was zeroed and physically removed
- Snapshot schedule: every 15 min (kept 4), hourly (24), daily (7), weekly (4), monthly (3)

### SilverStone SST-TS43xx (External Disk Enclosure)

The "backup" pool above lives on an external **SilverStone SST-TS43xx** 4-bay disk case
(miniSAS only — no USB/eSATA), attached to the MicroServer miniSAS card. It serves
as the **local backup target** via ZFS send/recv from the primary "tank" pool
(bulk/cold/scratch storage, 12 TB raw / 6 TB usable in RAIDZ2). `sde` was removed
(⚠️ critically failing: 2,001 reallocated + 32 pending sectors).

---

## Roles

- Primary ZFS pool "tank" — mirror, 4 TB usable
- Backup ZFS pool "backup" — RAIDZ2, 6 TB usable
- NAS / file server — NFS/SMB shares for media, photos, documents
- Local backup replication — ZFS send/recv (sanoid/syncoid) from tank → backup pool
- Web UI — Cockpit + cockpit-zfs (~150 MB RAM)
- Kopia relay — optional cloud relay to iDrive e2

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