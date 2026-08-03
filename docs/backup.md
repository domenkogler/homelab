# Backup & Disaster Recovery

> **Role:** Detail — LAST document. Dual-layer backup (ZFS + Kopia), DR scenarios, restore drills.
> **Links to:** `hardware-gen8.md`, `hardware-silverstone.md`, `deployment-secrets.md`
> **Linked from:** `index.md`

---

## Backup Architecture (Dual Layer)

### Layer 1: ZFS (Local — Block-Level)

Bulk data on gen8 ZFS pools, replicated locally at block level:

```
gen8 ZFS pool "tank"  ──zfs send/recv──→  gen8 ZFS pool "backup"
  (HGST + IronWolf)     incremental,        (SilverStone via miniSAS)
                         block-level,
                         every 15 min
```

- ZFS snapshots are instantaneous, immutable, cheap (only changed blocks)
- `zfs send/recv`: block-level incremental — 10–50× faster than file-level scan for TB-scale
- Snapshot schedule: every 15 min (kept 4), hourly (24), daily (7), weekly (4), monthly (3)
- Managed via **sanoid/syncoid**

### Layer 2: Kopia (Off-Site — Application-Level)

Configs, databases, and critical small files go off-site via Kopia:

```
tiredofit/db-backup  →  Kopia  →  iDrive e2 (S3)
   (SQL dumps)          (encrypted,    (cloud)
                         dedup)
```

---

## Why Two Layers?

| | ZFS send/recv | Kopia |
|---|---|---|
| **Scope** | Bulk data (media, ISOs, archives) | Configs, DB dumps, critical files |
| **Speed** | Block-level incremental (very fast) | File-level with dedup |
| **Encryption** | Optional (ZFS native) | Client-side (before leaving) |
| **Target** | gen8 local backup pool | iDrive e2 cloud |
| **Recovery** | Instant `zfs rollback` | Kopia restore from cloud |

---

## What Gets Backed Up

| Data | Location | Method | Target |
|------|----------|--------|--------|
| PostgreSQL DBs (Authentik, Immich, OpenCloud) | debhost SSD | db-backup → Kopia | iDrive e2 |
| Docker Compose files | Git / debhost | Kopia | iDrive e2 |
| Docker configs (`/opt/*`) | debhost | Kopia | iDrive e2 |
| systemd units | debhost | Kopia | iDrive e2 |
| Home Assistant configs | RPi 4 | Kopia | iDrive e2 |
| Router configs (`*.rsc`) | Git repo | Git + Kopia | iDrive e2 |
| **Bulk media** (photos, videos, ISOs) | **gen8 ZFS tank** | **ZFS send/recv** | **gen8 ZFS backup pool** |
| Immich raw photos | gen8 / Storage Box | Kopia → iDrive e2 | iDrive e2 |

> **Excluded — by design:** observability TSDB (Prometheus 30d + Loki 14d) is **regenerable and NOT backed up**. It lives on debhost local disk; losing it loses only rolling metric/log history. See [`observability.md`](observability.md).

---

## Backup Flow

```
── ZFS path (bulk data, local) ──
1. sanoid takes ZFS snapshots every 15 min on gen8 "tank" pool
2. syncoid replicates to SilverStone "backup" pool via zfs send/recv
3. Backup pool retains same snapshot schedule independently

── Kopia path (configs + DBs, off-site) ──
1. Cron triggers db-backup on debhost
2. db-backup dumps all databases to local SSD
3. Kopia snapshots: dump files + configs + compose files
4. Kopia pushes encrypted snapshot to iDrive e2
5. Temp dump files cleaned up
```

---

## 3-2-1 Rule

| Copy | Location | Medium | Transport |
|------|----------|--------|-----------|
| **Live data** | debhost NVMe + gen8 ZFS tank | SSD + HDD | — |
| **Local backup** | gen8 SilverStone pool (ZFS send/recv) | HDD | Block-level (fast) |
| **Off-site backup** | iDrive e2 (Kopia encrypted) | Cloud | S3 (encrypted) |

---

## Disaster Recovery

### Restore Drills
- **Frequency: Yearly**
- Test: restore random service from Kopia snapshot, verify it works

### Recovery Paths

| Scenario | Recovery Steps |
|----------|---------------|
| **Single service crashes** | Kopia restore that service's data from latest snapshot |
| **Single file deleted/corrupted** | ZFS rollback to snapshot before deletion (seconds) |
| **debhost fails (Phase 1)** | 1. Reinstall Debian 2. Ansible: `common → docker → amd_rocm → desktop → kopia → docker_services` 3. Kopia restore `/opt/` + systemd units + package list |
| **gen8 fails** | 1. ZFS backup pool on SilverStone is separate enclosure — import on new machine 2. Replace gen8, import pools |
| **Both gen8 pools lost** | Restore bulk data from iDrive e2 via Kopia (slow — last resort) |
| **Router dies** | 1. Replace RB4011 2. Restore `.rsc` from Git 3. Adjust WAN MAC if needed |
| **Total house loss** | 1. VPS + iDrive e2 survive (off-site) 2. Rebuild from Git + Ansible 3. Restore data from Kopia 4. Replace hardware |

---

## Family Access

- **Kopia master password:** 1Password (vault: `Homelab`)
- **1Password master password + recovery codes:** Paper in family safe
- **Family safe also contains:** Link to Git repo (Forgejo + GitHub mirror)
- See [`deployment-secrets.md`](deployment-secrets.md)

---

## Open Questions

- **Kopia Web GUI vs CLI:** Web GUI is sufficient for now; CLI needs assessed at first restore drill
- **Sanoid/Syncoid vs cron + zfs send -i:** Start with cron for simplicity, migrate to sanoid once pools stable
- **Bulk media off-site:** Does iDrive e2 have space/cost headroom for full media library? If not, bulk media stays local-only (ZFS) and only configs/DBs go off-site