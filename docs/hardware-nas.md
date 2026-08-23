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
| HDD 1 | HGST 4 TB (HDN726040ALE614) — 60,452h |
| HDD 2 | Seagate IronWolf Pro 4 TB (ST4000NT001) — 399h, 7200rpm |
| SATA mode | AHCI / non-RAID (B120i disabled — ZFS direct disk access) |
| NIC | Embedded dual-port Broadcom |
| iLO | 4 (integrated) — FW 2.55, IP `ilo` per [`network-addresses-generated.md`](network-addresses-generated.md) (VLAN 99) |
| OS | Debian 13 (Trixie) minimal, headless, ZFS 2.3+ |
| Expansion | PCIe x16 Gen3 → miniSAS card → SilverStone |
| Location | Rack cabinet |

> **VT-d/DMAR note (observed live 2026-08-23):** Debian 13 enables DMA remapping on this box;
> heavy I/O produces benign `DMAR: ERROR: DMA PTE … already set` console spam (B120i quirk).
> Harmless — zero accompanying block-layer faults across a full 4 T migration — but if it
> persists post-reinstall, consider `intel_iommu=off` (no passthrough is planned here).

---

## ZFS Pool "tank" (Primary — Mirror)

> **Disk reference SSOT = `/dev/disk/by-id/`** (captured 2026-08-21 on the pre-reinstall Debian).
> `sdX` letters are boot-specific and already shifted once — never use them in preseed/pool commands.

| by-id (`/dev/disk/by-id/`) | Model | Size | Hours | Health |
|-------|-------|------|-------|--------|
| `ata-HGST_HDN726040ALE614_K4K9LBGB` | HGST HDN726040ALE614 | 4 TB | 60,452 | ✅ |
| `ata-ST4000NT001-3M2101_WX122FLD` | Seagate IronWolf Pro ST4000NT001 | 4 TB | 399 | ✅ |

- **4 TB usable**, fully redundant mirror — reserved for **user data** (backed up). No media.
- Datasets (all snapshotted + syncoid-replicated to `bulk`):
  - `tank/data/services` → nightly state pushes from oldsrv (Forgejo dump, n8n sqlite, …)
  - `tank/data/db-dumps` → tiredofit/db-backup output (pushed from oldsrv local scratch)
  - *(`tank/data/immich` + `tank/data/documents` were trimmed HD-151 — originals/user-files live on the live Box, no NAS copy.)*
  - (older `tank/important` / `tank/data`-with-media plans → **superseded**: media moved to the `bulk`
    pool; only user data remains on `tank`. Full layout: [`storage.md`](storage.md))

> **Topology locked: MIRROR, not raidz1 (2026-08-21, owner decision — todo HD-207).** Even though
> OpenZFS 2.3+ adds single-disk RAIDZ expansion, mirror wins at this size: fast block-copy resilver,
> per-block self-healing (reads the good copy directly), better random I/O. Future growth paths:
> ① `zpool add tank mirror <d3> <d4>` — a NEW second top-level pair contributes its FULL size
> (e.g. 2× 8 TB ⇒ ~12 TB usable total; existing data stays on the old vdev, new writes spread by free
> space; mirror vdevs are even removable later via device_removal); ② `zpool replace` both disks
> one-by-one → autoexpand to one bigger mirror. **Never `zpool attach` a larger disk onto the existing
> pair** — a mirror is exactly as large as its smallest member, so the extra space is wasted.
> When buying: CMR only (WD Red Plus / IronWolf / Toshiba N300 — no SMR).

### NFS Exports (→ oldsrv)

- Export **`tank/data`** (user data) → oldsrv **`/mnt/nas/data`**
- Export **`bulk/media`** (the *arr library + downloads) → oldsrv **`/mnt/nas/media`**
- Ownership: uid/gid **`storage_uid`/`storage_gid` = `1005` (`media`)** (HD-94/HD-131) so *arr containers
  (`PUID/PGID={{ storage_uid }}:{{ storage_gid }}`) can read/write; SMB/NFS anonuid/anongid follow the same
- Three exports because they live on two **different pools** (`tank/data`, `bulk/media`) plus the
  `bulk/data/immich-thumbs` push target — they can't share one mountpoint. TRaSH hardlinks only need a
  single filesystem **within** `bulk/media`, which is one dataset ✓
- Full layout/properties: [`storage.md`](storage.md)

---

## ZFS Pool "bulk" (Local Secondary — RAIDZ2, mixed role)

Connected via **miniSAS** to the SilverStone SST-TS43xx external disk enclosure (4-bay, miniSAS-only — no USB/eSATA).

| by-id (`/dev/disk/by-id/`) | Model | Size | Hours | Health |
|-------|-------|------|-------|--------|
| `ata-WDC_WD30EFRX-68EUZN0_WD-WCC4N6YFD1UU` | WD Red WD30EFRX | 3 TB | 45,903 | ✅ |
| `ata-TOSHIBA_HDWD130_98M0ZZYAS` | Toshiba P300 HDWD130 | 3 TB | 6,885 | ✅ |
| `ata-TOSHIBA_HDWD130_98M101SAS` | Toshiba P300 HDWD130 | 3 TB | 8,560 | ✅ |
| `ata-TOSHIBA_HDWD130_98M0X0TAS` | Toshiba P300 HDWD130 | 3 TB | 8,497 | ✅ |

> Hours re-read per serial 2026-08-23 over SSH on the running system
> ([smart-report-nas-20260823T105831.txt](../reports/smart-report-nas-20260823T105831.txt)):
> all six HDDs PASS with zero reallocated/pending/offline-uncorrectable/CRC counters —
> closes the earlier unattributable-range caveat.

- **6 TB usable**, survives any 2 disk failures
- sde (Toshiba P300, 2,001 reallocated + 32 pending) was zeroed and physically removed
- **Mixed role:** hosts the **syncoid replicas** of `tank/data/*` AND the **active media library**
  (`bulk/media`, no snapshots — redownloadable) AND the face-thumbnail copy (`bulk/data/immich-thumbs`,
  daily snapshots). Replica datasets retain the source snapshot schedules independently. Detail:
  [`storage.md`](storage.md)

### SilverStone SST-TS43xx (External Disk Enclosure)

The "bulk" pool above lives on an external **SilverStone SST-TS43xx** 4-bay disk case
(miniSAS only — no USB/eSATA), attached to the MicroServer miniSAS card. It serves
as the **local secondary pool**: syncoid replicas of `tank/data/*` (ZFS send/recv) plus the
**active media library** (`bulk/media`) and the face-thumbnail push target (`bulk/data/immich-thumbs`)
— 12 TB raw / 6 TB usable in RAIDZ2 on consumer disks. `sde` was removed
(⚠️ critically failing: 2,001 reallocated + 32 pending sectors).

---

## Pool-Creation Runbook (one-time bootstrap, BEFORE the preseed reinstall)

> ✅ **EXECUTED 2026-08-23 — see the as-built entry in [deployment-journal.md §Phase 1a](../deployment-journal.md)**
> (pools created, verified, exported; installer-ready). Reality deltas vs the text below:
> the legacy payload lived in pool **`new-pool`** (single disk ST4000NT001) and a second
> single-disk pool **`backup`** (61.9 G gen8 dumps) existed — the owner declared `backup`
> disposable and it was destroyed after migration verification instead of being migrated.
> Two operational notes learned live: `zfs receive` does NOT create intermediate datasets
> (create `bulk/migrate` explicitly first), and RAIDZ2 physical ALLOC runs ≈1.67× the logical
> stream size (parity + stripe padding). The Ansible `storage` role is
> **import-only** for `tank`/`bulk` (`allow_create: false`, import-first rule in
> `roles/storage/tasks/zfs_common.yml`) — pool creation is a human bootstrap step; datasets +
> properties are then applied by the role from its defaults SSOT. The preseed wipes **only the OS SSD**
> (`ata-Crucial_CT525MX300SSD4_173818D02FF0`); pools live on their data disks and survive the reinstall.
> Create pools with `ashift=12`; `-O` props mirror the [`storage.md`](storage.md) all-datasets row.

```bash
sudo apt update && sudo apt install -y zfsutils-linux

# -- 0. wipe stale labels (all six HDDs carry old ZFS part1/part9 tables) ----------------------
sudo wipefs -a \
  /dev/disk/by-id/ata-WDC_WD30EFRX-68EUZN0_WD-WCC4N6YFD1UU \
  /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M0X0TAS \
  /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M0ZZYAS \
  /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M101SAS

# -- 1. bulk FIRST (RAIDZ2) — it becomes the migration target ----------------------------------
sudo zpool create -o ashift=12 \
  -O xattr=sa -O acltype=posixacl -O atime=off -O normalization=formD \
  bulk raidz2 \
    /dev/disk/by-id/ata-WDC_WD30EFRX-68EUZN0_WD-WCC4N6YFD1UU \
    /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M0X0TAS \
    /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M0ZZYAS \
    /dev/disk/by-id/ata-TOSHIBA_HDWD130_98M101SAS

# -- 2. migrate the legacy single-disk pool OFF the IronWolf (it has no redundancy) ------------
sudo zpool import                                   # list importable pools, note NAME + datasets
# rename-on-import avoids a name clash with the new tank/bulk; readonly protects the source:
sudo zpool import -o readonly=on -R /mnt/legacy <legacy-pool-name> legacy-migrate
sudo zfs list -r legacy-migrate
sudo zfs snapshot -r legacy-migrate/<dataset>@migrate
sudo zfs send -R legacy-migrate/<dataset>@migrate | sudo zfs receive bulk/migrate/<dataset>
diff -r /mnt/legacy/<dataset> /bulk/migrate/<dataset>        # spot-check before wiping anything
sudo zpool export legacy-migrate

# -- 3. tank (MIRROR — never raidz1 for 2 disks; docs/storage.md layout) -----------------------
sudo wipefs -a \
  /dev/disk/by-id/ata-HGST_HDN726040ALE614_K4K9LBGB \
  /dev/disk/by-id/ata-ST4000NT001-3M2101_WX122FLD
sudo zpool create -o ashift=12 \
  -O xattr=sa -O acltype=posixacl -O atime=off -O normalization=formD \
  tank mirror \
    /dev/disk/by-id/ata-HGST_HDN726040ALE614_K4K9LBGB \
    /dev/disk/by-id/ata-ST4000NT001-3M2101_WX122FLD

# -- 4. final home of the migrated data (open decision, todo.md HD-207) ------------------------
# media library -> zfs rename bulk/migrate/<dataset> bulk/media   (role applies documented props)
# user data     -> decide against storage.md first (NAS-local user datasets were trimmed HD-151)
zfs destroy -r bulk/migrate@unused || true          # clean the landing zone once decided

# -- 5. export BOTH pools before booting the preseed installer ---------------------------------
sudo zpool export bulk tank
```

Rules: create **no datasets by hand** beyond the `bulk/migrate` landing zone — the storage role owns
the tree (`bulk/media`, `bulk/data/*`, `tank/data/*`). After the preseed install,
`playbooks/storage.yml` imports both pools and applies datasets/props; verify with `zpool status`
(Phase 2 checklist in `deployment-tasks.md`).

---

## Roles

- Primary ZFS pool "tank" — mirror, 4 TB usable — **user data only** (backed up)
- Secondary ZFS pool "bulk" — RAIDZ2, 6 TB usable — active media (unbacked) + data replicas + thumb copies
- NAS / file server — NFS shares: `tank/data` (user data), `bulk/media` (media); **Samba/SMB shares live on the NAS** (HD-131 D4): shared `media` + per-user private drives
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
| iLO IP | static — `ilo` (VLAN 99), see [`network-addresses-generated.md`](network-addresses-generated.md) |
| Firmware | 2.55 (Aug 2017) |
| Access | Web UI HTTPS, Redfish API, SSH, IPMI |
| iKVM | HTML5 remote console — BIOS-level, virtual ISO |
| Power | Remote on/off/reset, boot order, PXE |
| Health | Temperatures, fans, power, hardware logs |
| Auth | Local admin account |

---

## Boot Drive

| by-id (`/dev/disk/by-id/`) | Model | Size | Hours | Health |
|-------|-------|------|-------|--------|
| `ata-Crucial_CT525MX300SSD4_173818D02FF0` | Crucial MX300 525 GB | 525 GB | 55,828 | ✅ (81% life left) |

- Boot only — no L2ARC/SLOG
- L2ARC skipped: 12 GB RAM insufficient for benefit
- **Boot chain quirk:** this SSD sits on an internal SATA port the Gen8 cannot boot from →
  GRUB lives on the **USB stick** (preseed §8 `grub-installer/bootdev` = usb by-id, HD-206);
  the stick must stay plugged for the box to boot
- SLOG skipped: SSD lacks power-loss protection (PLP)