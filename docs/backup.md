---
title: Backup & Disaster Recovery
role: detail
domain: deployment
status: active
tags: [deployment, backup, zfs, kopia]
---
# Backup & Disaster Recovery

> **Role:** Detail — LAST document. Dual-layer backup (ZFS + Kopia), DR scenarios, restore drills.
> **Links to:** `hardware-nas.md`, `deployment-secrets.md`
> **Linked from:** `index.md`

---

## Backup Architecture (Dual Layer)

### Layer 1: ZFS (Local — Block-Level)

User data on nas ZFS pools, replicated locally at block level:

```
nas ZFS pool "tank"  ──zfs send/recv──→  nas ZFS pool "bulk"
  (mirror)             incremental,        (RAIDZ2, SilverStone via miniSAS)
                       hourly sends
```

- ZFS snapshots are instantaneous, immutable, cheap (only changed blocks)
- `zfs send/recv`: block-level incremental — 10–50× faster than file-level scan for TB-scale
- **Scope:** ONLY `tank/data/*` (immich, documents, services, db-dumps). The media library
  (`bulk/media`) is intentionally **NOT snapshotted or replicated** — it is redownloadable, see
  [`services.md`](services.md) / [`storage-zfs.md`](storage-zfs.md)
- Snapshot schedule: data datasets hourly (24), daily (7), weekly (4), monthly (3); **`documents` gets an
  additional 5-min tier retained 8 h (`5m(96)`)** for fine-grained per-file versioning — photo/dump
  datasets stay hourly (photos change by upload, dumps daily); snapshotting unbacked media is pure churn
- Replication: syncoid timer checks every 15 min, sends when a new source snapshot exists (≈ hourly;
  ≈ 5 min for `documents`)
- Managed via **sanoid/syncoid**, run by **systemd timers** (sanoid.timer + syncoid.timer) — not raw cron; gives journaling, randomized schedules, and failure tracking

### Layer 2: Kopia (Off-Site — Application-Level, NAS-independent)

Configs, DB dumps, service state, and face thumbnails go off-site via Kopia — **oldsrv-local sources
only, never NAS mounts**, so off-site backup keeps working while the NAS is fully down:

```
tiredofit/db-backup (local scratch) →  Kopia agent (oldsrv) →  iDrive e2 (S3)
   + service state + face thumbs       (encrypted, dedup)       (cloud)
```

DB dumps are written to a **local scratch dir first** (Kopia snapshots it), then pushed to
`tank/data/db-dumps` for the ZFS path — the two layers are independent.

---

## Why Two Layers?

| | ZFS send/recv | Kopia |
|---|---|---|
| **Scope** | User data (`tank/data/*` → `bulk/data/*`) | Configs, DB dumps, service state, face thumbnails |
| **Speed** | Block-level incremental (very fast) | File-level with dedup |
| **Encryption** | Optional (ZFS native) | Client-side (before leaving) |
| **Target** | nas `bulk` pool (local) | iDrive e2 cloud (off-site) |
| **Recovery** | Instant `zfs rollback` / `zfs recv` back | Kopia restore from cloud |

---

## What Gets Backed Up

| Data | Location | Method | Target |
|------|----------|--------|--------|
| PostgreSQL DBs (Authentik, Immich, OpenCloud) | oldsrv NVMe | daily dumps → **local scratch** → push | `tank/data/db-dumps` (ZFS) **and** iDrive e2 (Kopia) |
| Docker Compose files / systemd units / configs | Git repo + oldsrv `/opt/*` | Git (+ Kopia) | Forgejo + GitHub mirror / iDrive e2 |
| Service state (Forgejo dump, n8n sqlite, …) | oldsrv NVMe | nightly push + Kopia | `tank/data/services` (ZFS) + iDrive e2 |
| Home Assistant configs | RPi 4 (+ standby on oldsrv) | Git + standby sync | repo / oldsrv (Kopia) |
| Router configs (`*.rsc`) | Git repo | Git + Kopia | iDrive e2 |
| Immich **originals** (photos/videos) | nas `tank/data/immich` | ZFS send/recv | `bulk/data/immich` |
| Immich **face thumbnails** | oldsrv NVMe | nightly rsync + Kopia | `bulk/data/immich-thumbs` + iDrive e2 |
| **Media library** (movies/tv/music) | **nas `bulk/media`** | **NOT backed up** | redownloadable via usenet/torrents |

> **Excluded — by design:** observability TSDB (Prometheus 30d + Loki 14d) is **regenerable and NOT backed up**. It lives on oldsrv local disk; losing it loses only rolling metric/log history. See [`observability.md`](observability.md).

> **Excluded — media + *arr scratch:** `bulk/media` (library **and** `downloads/`) is partially or fully
> redownloadable via usenet/torrents, so the whole dataset is **unbacked** — no sanoid snapshots, no
> syncoid, no Kopia. Immich thumbs/encoded-video and ML weights are regenerable, also excluded (face
> thumbnails are the one exception — see above).

---

## Backup Flow

```
── ZFS path (user data, local) ──
1. sanoid snapshots `tank/data/*` (immich, documents, services, db-dumps) — hourly(24)+daily(7)+weekly(4)+monthly(3)
2. syncoid replicates `tank/data/*` → `bulk/data/*` via zfs send/recv (≈ hourly incremental)
3. `bulk` retains the same snapshot schedules independently (rollback target of its own)
4. `bulk/media` → no snapshots (unbacked); `bulk/data/immich-thumbs` → daily(7), no send

── Kopia path (configs + state, off-site — NAS-independent) ──
1. systemd timer runs db-backup → SQL dumps to a LOCAL scratch dir
2. push job copies dumps → `tank/data/db-dumps` (the ZFS path) — Kopia never reads NAS mounts
3. Kopia snapshots: local scratch + service state + face thumbnails + configs
4. Kopia pushes the encrypted snapshot to iDrive e2
5. Old local dump files pruned (already snapshotted by Kopia)
```

---

## 3-2-1 Rule

| Copy | Location | Medium | Transport |
|------|----------|--------|-----------|
| **Live data** | oldsrv NVMe + nas ZFS `tank` | SSD + HDD | — |
| **Local backup** | nas ZFS `bulk` (send/recv + nightly pushes) | HDD | Block-level (fast) |
| **Off-site backup** | iDrive e2 (Kopia encrypted, NAS-independent) | Cloud | S3 (encrypted) |

> **Media is the deliberate exception** to 3-2-1: `bulk/media` is redownloadable, so 0-1-0 suffices
> (RAIDZ2 redundancy, no backup copy) — see [`storage-zfs.md`](storage-zfs.md).

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
| **oldsrv fails (Phase 1)** | Rebuild **from the NAS, no iDrive** — runbook in [`storage-zfs.md`](storage-zfs.md): preseed reinstall → Ansible → mount NFS → restore DBs from dumps → unpack `tank/data/services` → copy thumbs back |
| **HA Pi fails** | Forward takeover to oldsrv standby (manual) — see [`smart-home-failover.md`](smart-home-failover.md); rebuild Pi as fresh peer, reverse-sync standby→Pi, flip VIP back |
| **nas fails** | Services keep running (state is on oldsrv); Immich photos + OpenCloud files unavailable until rebuild. Pools are self-describing: reinstall from preseed, `zpool import tank bulk`, re-run Ansible |
| **Both nas pools lost** | Media: re-download. Data (`tank/data/*`): restore from `bulk` if it survived, else iDrive e2 via Kopia (slow — last resort) |
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
- **Bulk media off-site:** Does iDrive e2 have space/cost headroom for full media library? If not, bulk media stays local-only (ZFS) and only configs/DBs go off-site