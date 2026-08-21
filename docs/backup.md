---
title: Backup & Disaster Recovery
role: detail
domain: deployment
cross_cutting: true
status: active
tags: [deployment, backup, zfs, kopia]
---
# Backup & Disaster Recovery

> **Role:** Detail (cross-cutting) — LAST document. Dual-layer backup (ZFS + Kopia), DR scenarios, restore drills.
> **Links to:** `hardware-nas.md`, `deployment-secrets.md`
> **Linked from:** `deployment.md`, `index.md`

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
- **Scope:** ONLY `tank/data/*` (services, db-dumps) — retained archives. (The old `immich`/`documents`
  datasets were trimmed HD-151 — the live Box + Kopia is recovery.) The media library
  (`bulk/media`) is intentionally **NOT snapshotted or replicated** — it is redownloadable, see
  [`services.md`](services.md) / [`storage.md`](storage.md)
- Snapshot schedule: data datasets hourly (24), daily (7), weekly (4), monthly (3); photo/dump datasets
  stay hourly (photos change by upload, dumps daily); snapshotting unbacked media is pure churn
- Replication: syncoid timer checks every 15 min, sends when a new source snapshot exists (≈ hourly)
- Managed via **sanoid/syncoid**, run by **systemd timers** (sanoid.timer + syncoid.timer) — not raw cron; gives journaling, randomized schedules, and failure tracking

### Layer 2: Kopia (Off-Site — Application-Level, NAS-independent)

Configs, DB dumps, service state, face thumbnails, and VPS/oldsrv local state go off-site via Kopia —
**local sources only, never NAS mounts**, so off-site backup keeps working while the NAS is fully down.
Kopia targets the **backup Box over SSH/SFTP (port 23)** — the Hetzner Storage Box supports **SSH/SFTP
only, NOT S3** (HD-31/HD-135); iDrive e2 S3 was dropped.

The **oldsrv agent runs containerized** (HD-191/HD-204): it connects to `kopia-server` on the VPS over
the **WG S2S tunnel** — server port 51515 is bound **only to the VPS tunnel address** (`wg_s2s_vps.ip`,
never 0.0.0.0; loopback-only until the router peer key is provisioned), so reach stays scoped by the
S2S ACL (HD-155). Agent sources are oldsrv-local, read-only: `/opt/*` configs, `/srv/dumps` scratch,
the immich upload/thumb dir, and the signal-cli state volume.

```
tiredofit/db-backup (local scratch) →  Kopia agent (VPS + oldsrv) →  Hetzner Storage Box (backup) SSH/SFTP :23
   + service state + face thumbs       (encrypted, dedup)       (far-DC: Helsinki/Falkenstein)
```

> **Off-site (HD-29/31, 2026-08-18): two Hetzner Storage Boxes.** **Live** box (nearest DC) serves
> Immich originals **+ encoded-video** and the family SMB/WebDAV drives (CIFS, **not S3** — HD-135); **backup** box (far DC) hosts the Kopia repo.
> **iDrive e2 dropped** (Hetzner cheaper per TB + SMB/WebDAV; single-provider risk accepted).

DB dumps are written to a **local scratch dir first** (Kopia snapshots it), then pushed to
`tank/data/db-dumps` for the ZFS path — the two layers are independent.

---

## Why Two Layers?

| | ZFS send/recv | Kopia |
|---|---|---|
| **Scope** | User data (`tank/data/*` → `bulk/data/*`) | Configs, DB dumps, service state, face thumbnails, **live Box originals + encoded-video (CIFS, HD-135)** |
| **Speed** | Block-level incremental (very fast) | File-level with dedup |
| **Encryption** | Optional (ZFS native) | Client-side (before leaving) |
| **Target** | nas `bulk` pool (local) | Hetzner Storage Box (backup), far DC (off-site) |
| **Recovery** | Instant `zfs rollback` / `zfs recv` back | Kopia restore from cloud |

---

## What Gets Backed Up

| Data | Location | Method | Target |
|------|----------|--------|--------|
| PostgreSQL DBs (Authentik, Immich, Forgejo, **PGVector** — HD-102; all bundled on the **VPS**, `db-backup` DB01–04) | VPS NVMe | daily dumps → **local scratch** → push | `tank/data/db-dumps` (ZFS) **and** Hetzner Storage Box (backup) (Kopia) |
| Docker Compose files / systemd units / configs | Git repo + host `/opt/*` (**VPS + oldsrv**) | Git (+ Kopia) | Forgejo + GitHub mirror / Hetzner Storage Box (backup) |
| Service state (Forgejo dump, n8n sqlite, **LiteLLM keys/spend** — HD-100, **OpenClaw config/state** — HD-104 on the **VPS**; **Seerr config + `seerr.db`** — HD-130/KOPS-059 on **oldsrv**; …) | VPS NVMe (edge/GitOps/AI tier) · oldsrv NVMe (*arr/LAN core) | nightly push + Kopia | `tank/data/services` (ZFS) + Hetzner Storage Box (backup) |
| Home Assistant configs | RPi 4 (+ standby on oldsrv) | Git + standby sync | repo / oldsrv (Kopia) |
| Router configs (`*.rsc`) | Git repo | Git + Kopia | Hetzner Storage Box (backup) |
| Immich **originals + encoded-video** (photos/videos) | **live Hetzner Box** (CIFS `//u653411.../backup`, VPS) | **live tier** (HD-135) | backed by **Kopia → backup Box** (off-site) **+ the Immich DB** (albums/faces/tags) — D3. *Supersedes the MinIO/S3-originals plan (HD-131 D1).* |
| Immich **face thumbnails** | oldsrv NVMe | nightly rsync + Kopia | `bulk/data/immich-thumbs` + Hetzner Storage Box (backup) |
| **Media library** (movies/tv/music) | **nas `bulk/media`** | **NOT backed up** | redownloadable via usenet/torrents |

> **Excluded — by design:** observability TSDB (Prometheus 30d + Loki 14d) is **regenerable and NOT backed up**. It lives on the **VPS NVMe** (HD-135 backend placement); losing it loses only rolling metric/log history. See [`observability.md`](observability.md).

> **Excluded — media + *arr scratch:** `bulk/media` (library **and** `downloads/`) is partially or fully
> redownloadable via usenet/torrents, so the whole dataset is **unbacked** — no sanoid snapshots, no
> syncoid, no Kopia. Immich thumbs/encoded-video and ML weights are regenerable, also excluded (face
> thumbnails are the one exception — see above).

---

## Backup Flow

```
── ZFS path (user data, local) ──
1. sanoid snapshots `tank/data/*` (services, db-dumps) — hourly(24)+daily(7)+weekly(4)+monthly(3)
2. syncoid replicates `tank/data/*` → `bulk/data/*` via zfs send/recv (≈ hourly incremental)
3. `bulk` retains the same snapshot schedules independently (rollback target of its own)
4. `bulk/media` → no snapshots (unbacked); `bulk/data/immich-thumbs` → daily(7), no send

── Kopia path (configs + state, off-site — NAS-independent) ──
1. systemd timer runs db-backup → SQL dumps to a LOCAL scratch dir
2. push job copies dumps → `tank/data/db-dumps` (the ZFS path) — Kopia never reads NAS mounts
3. Kopia snapshots: local scratch + service state + face thumbnails + configs
4. Kopia pushes the encrypted snapshot to Hetzner Storage Box (backup)
5. Old local dump files pruned (already snapshotted by Kopia)
```

---

## 3-2-1 Rule

| Copy | Location | Medium | Transport |
|------|----------|--------|-----------|
| **Live data** | netcup VPS NVMe (Immich DB, thumbs, configs) | SSD | — |
| **Originals store** | Hetzner Storage Box **live** (`//u653411.../backup`, CIFS-mounted to VPS) | Cloud | CIFS/SMB + WebDAV |
| **Local backup** | home NAS (snapshot / nightly push) | HDD | LAN (fast restore) |
| **Off-site backup** | Hetzner Storage Box **backup** (Kopia over **SSH/SFTP**, port 23, encrypted, NAS-independent) | Cloud | SSH/SFTP (port 23) |

> **Media is the deliberate exception** to 3-2-1: `bulk/media` is redownloadable, so 0-1-0 suffices
> (RAIDZ2 redundancy, no backup copy) — see [`storage.md`](storage.md).

> **Accepted residual risk (S13):** the off-site Kopia repo is encrypted but not immutable — a
> ransomware attacker holding the Box credentials/key could reach the backup copy. Accepted for now;
> mitigation options if ever needed: Storage Box snapshot/versioning, or a second cold credential.
> Restore-drill discipline (yearly) is the current integrity check.

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
| **oldsrv fails (Phase 1)** | Rebuild **from the NAS, no off-site** — runbook in [`storage.md`](storage.md): preseed reinstall → Ansible → mount NFS → restore DBs from dumps → unpack `tank/data/services` → copy thumbs back |
| **HA Pi fails** | Forward takeover to oldsrv standby (manual) — see [`smart-home-failover.md`](smart-home-failover.md); rebuild Pi as fresh peer, reverse-sync standby→Pi, flip VIP back |
| **nas fails** | Services keep running (state is on oldsrv); Immich photos + OpenCloud files are on the **live Hetzner Box** (cold tier) so they stay reachable — only NAS-local archive datasets are unavailable until rebuild. Pools are self-describing: reinstall from preseed, `zpool import tank bulk`, re-run Ansible |
| **Both nas pools lost** | Media: re-download. Data (`tank/data/*`): restore from `bulk` if it survived, else Storage Box (backup) via Kopia (slow — last resort) |
| **Router dies** | 1. Replace RB4011 2. Restore `.rsc` from Git 3. Adjust WAN MAC if needed |
| **Total house loss** | 1. VPS + Storage Box (backup) survive (off-site; NAS is lost with the house) 2. Rebuild from Git + Ansible 3. Restore data from Kopia (backup box) 4. Replace hardware |

---

## Family Access

- **Kopia master password:** 1Password (vault: `Homelab-ansible`)
- **1Password master password + recovery codes:** Paper in family safe
- **Family safe also contains:** Link to Git repo (Forgejo + GitHub mirror)
- See [`deployment-secrets.md`](deployment-secrets.md)

---

## Open Questions

- **Kopia Web GUI vs CLI:** Web GUI is sufficient for now; CLI needs assessed at first restore drill
- **Bulk media off-site:** live + backup Hybrid Storage Boxes (BX11, bought/planned 2026); bulk media library stays local-only on NAS (ZFS), only configs/DBs + Immich originals go off-site. Off-site copy via Kopia over SSH/SFTP (port 23); **no S3 / Object Storage** (Hetzner Storage Box is not S3 — handled via CIFS mount + Kopia over SSH).