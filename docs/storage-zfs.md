---
title: ZFS Storage Layout & Properties
role: ssot
domain: storage
status: active
tags: [storage, zfs, datasets, backup, media, nfs]
---
# ZFS Storage Layout & Properties

> **Role:** Single source of truth — ZFS dataset tree, per-dataset properties, snapshot/replication policy,
> NFS exports, nightly push jobs, Kopia scope, capacity budget, and the oldsrv rebuild-from-NAS runbook.
> **Links to:** `hardware-nas.md`, `backup.md`, `services.md`, `deployment-compose.md`, `deployment-ansible.md`, `observability.md`
> **Linked from:** `index.md`

---

## Principles

1. **Config lives in Git, secrets in 1Password, media is redownloadable.** Only **data** gets backed up.
2. **"Data" = everything that persists and is not Git / 1Password / re-pullable** — user files, DB dumps,
   service state (Forgejo, n8n), Immich originals and face thumbnails. Docker images, packages, Ollama/ML
   model weights, TSDB (Prometheus/Loki), and the media library are deliberately **not** backup targets.
3. **Live data is local.** DBs and service runtime state live on the host's NVMe/SSD — never on NFS.
   The NAS holds only **big write-once files** (Immich originals) and **backup artifacts** (dumps, state pushes).
4. **TRaSH hardlinks need one filesystem.** `downloads/` and `media/` live in a **single dataset**
   (`bulk/media`) — ZFS hardlinks cannot cross dataset boundaries.
5. **No raw disk/NVMe images, ever.** IaC (preseed + Ansible) replaces *config* backup; ZFS pools are
   self-describing (pool config lives on the data disks). Only **state** is backed up.
6. **Kopia is NAS-independent.** Off-site backup sources are oldsrv-local only; it must work with the NAS
   fully dead.

---

## Dataset Tree

```
tank   (4 TB mirror — HGST + IronWolf, 24/7-rated)         → BACKED UP
└── data/
    ├── immich/          Immich originals (photos/videos) only   hourly+ snapshots, syncoid
    ├── documents/       OpenCloud files — 5-min snapshots (8 h), syncoid
    ├── services/        nightly state pushes (Forgejo dump, n8n sqlite, …)
    └── db-dumps/        tiredofit/db-backup output (push from oldsrv)   hourly+ snapshots, syncoid

bulk   (6 TB RAIDZ2 — WD Red + 3× Toshiba P300, consumer disks)  → MIXED ROLE
├── media/               ACTIVE *arr library + downloads (one dataset = hardlinks) — NOT backed up
│   ├── media/
│   │   ├── movies/
│   │   ├── tv/
│   │   └── music/
│   └── downloads/       transient scratch (hardlink-import → media/, then prune)
│       ├── incomplete/{usenet,torrent}
│       └── complete/{movies,tv,music}   # TRaSH per-category (SABnzbd / qBittorrent)
├── data/                syncoid replicas of tank/data/* — same names, same snapshot schedules
│   ├── immich/
│   ├── documents/
│   ├── services/
│   └── db-dumps/
└── immich-thumbs/       face thumbnails, nightly rsync ← oldsrv — daily(7) snapshots, no syncoid send

oldsrv — two local disks (Kopia → iDrive, NAS-independent)
├── 960 EVO 500 GB (ext4) — OS/system only: `/`, `/var`, `/opt` — regenerable, no churn
└── 970 EVO 1 TB (ZFS pool "nvme") — ALL local data:
    ├── nvme/docker-layers   /var/lib/docker         images/layers — re-pullable
    ├── nvme/docker          /srv/docker — per-service datasets (DBs, Immich thumbs, services)
    ├── nvme/tsdb            /srv/tsdb               30d/14d regenerable, no backup
    ├── nvme/models          /srv/models             re-pullable, no backup
    └── nvme/dumps           /srv/dumps              Kopia source → push → tank/data/db-dumps
nas — MX300 525 GB (ext4) — OS/boot only; `tank`/`bulk` imported via ZFS cachefile
```

> **Superseded plans:** earlier `tank/important`, `tank/media`, `tank/downloads` and `tank/data`-with-media
> layouts. Media moved to its own dataset on the `bulk` pool; `tank` is now reserved for user data only.

---

## Per-Dataset ZFS Properties

All datasets: `xattr=sa`, `acltype=posixacl` (NFS needs both), `atime=off`, `normalization=formD` (default).
No native encryption by default (homelab threat model; re-evaluate only if it changes).

| Dataset | recordsize | compression | Snapshots (sanoid) | syncoid → `bulk`? | Backed up off-site (Kopia)? |
|---------|-----------|-------------|--------------------|-------------------|-----------------------------|
| `tank/data/immich` | 1M | lz4 | hourly(24)+daily(7)+weekly(4)+monthly(3) | yes | via dumps (DB) — **originals moved to S3 (MinIO, HD-131 D1)**; this holds MinIO's object blocks / any local cache, not the originals as a ZFS copy |
| `tank/data/documents` | 128K | zstd | **5m(96)**+hourly(24)+daily(7)+weekly(4)+monthly(3) | yes | optional (small) |
| `tank/data/services` | 128K | zstd | hourly(24)+daily(7)+weekly(4)+monthly(3) | yes | yes (state dirs on oldsrv) |
| `tank/data/db-dumps` | 128K | zstd | hourly(24)+daily(7)+weekly(4)+monthly(3) | yes | yes (local scratch via Kopia) |
| `bulk/media` | 1M | lz4 | **none** | **no** | **no** — redownloadable |
| `bulk/data/*` | inherit | same as source | same as source (retained on the replica) | — (target) | — |
| `bulk/data/immich-thumbs` | 128K | lz4 | daily(7) | **no** (pushed, not sent) | yes |

Rationale: `recordsize=1M` matches large sequential photo/video files; `128K` is the sensible default for
documents/dumps/git. Media and photos are already compressed by their codecs → `lz4` (cheap, tiny gain);
documents/SQL dumps compress well → `zstd`. Snapshot cadence is **hourly** for immich/services/db-dumps
(photos change by upload, dumps change daily) — with one deliberate exception: **`tank/data/documents`
gets a 5-min tier retained 8 h (`5m(96)`)** for fine-grained per-file versioning (see File-Version UI
below). Snapshots of unbacked media are pure churn. Replication granularity follows the snapshot cadence
(≈ hourly; 5-min for documents), bounded by DB dump frequency (daily restore point) — worst case a
homelab loses <24 h of DB changes, acceptable.

---

## Snapshot & Replication (sanoid / syncoid)

- **sanoid** on nas snapshots `tank/data/*` (and `bulk/data/*` replicas + `bulk/data/immich-thumbs`).
  `bulk/media` is excluded from sanoid entirely.
- **syncoid** replicates `tank/data/* → bulk/data/*` (incremental `zfs send | zfs recv`). Timer checks
  every 15 min, sends only when a new source snapshot exists — so `documents` pushes ≈ every 5 min, the
  rest ≈ hourly.
- Replica datasets retain **independent** snapshot history on the `bulk` pool (protects against source
  deletion/error propagation; the replica is a rollback target of its own).
- `bulk/data/immich-thumbs` and `bulk/media` are **push targets** — no syncoid definition.
- Managed by **systemd timers** (`sanoid.timer`, `syncoid.timer`) — journaling, randomized schedules,
  failure tracking. Not raw cron.

---

## File-Version UI (per-file restore from snapshots)

- **Family today:** OpenCloud's built-in per-file versions (`REV.*` in `.oc-nodes/`) + Trash — keep its
  revision retention short; ZFS owns the long tail.
- **Admin today:** cockpit-zfs (nas) + `.zfs/snapshot/*` + `zfs rollback`/`receive` (whole-tree or per-file copy out of a snapshot).
- **Optional later:** serve `tank/data/documents` over SMB with `vfs objects = shadow_copy_zfs` → Windows
  Explorer *Properties → Previous Versions* per file, straight from these snapshots (~5 lines in smb.conf;
  Samba shares are now live (HD-131 D4) — this only adds the ZFS Previous-Versions VFS module on top).
- **Future:** OpenCloud FR [opencloud-eu/opencloud#1702](https://github.com/opencloud-eu/opencloud/issues/1702)
  would expose ZFS snapshots inside OpenCloud's version panel — our sanoid naming plugs straight in; don't
  plan around it (open, no ETA).

---

## NFS Exports (nas → oldsrv)

Three exports (one per pool + the face-thumbs push target — mounts can't span pools):

| Export | Mount (oldsrv) | Purpose |
|--------|----------------|---------|
| `tank/data` | `/mnt/nas/data` | user data: OpenCloud documents, db dumps, service-state copies + MinIO S3 object store backing — **Immich originals live in MinIO S3 (HD-131 D1)**, not directly on this NFS tree |
| `bulk/media` | `/mnt/nas/media` | *arr library + downloads (Jellyfin, Sonarr/Radarr/Lidarr, SABnzbd, qBittorrent, Bazarr) |
| `bulk/data/immich-thumbs` | `/mnt/nas/thumbs` | face-thumbnail push target (nightly rsync from oldsrv) |

- Ownership uid/gid **`storage_uid`/`storage_gid` = 1005 (`media`)** — the neutral shared-data owner (HD-51/HD-94/HD-131), NOT domen/1000; matches *arr `PUID/PGID`, Jellyfin/OpenCloud `user:` and the Samba force user/group; NFS `root_squash` on.
- fstab mounts via Ansible (`storage` role). Hardlinks only ever cross paths **within** `bulk/media` — one dataset, one filesystem ✓.
- **SMB/Samba is now implemented (HD-131 D4)** on the NAS via the `storage` role: one shared `media` share (any family user) + per-user private shares (`valid users = <user>`) for family mapped drives (Win11 + Linux).

---

## Nightly Push Jobs (oldsrv → nas)

| Job | Source (oldsrv) | Target (nas) | Method |
|-----|-----------------|--------------|--------|
| DB dumps | `/srv/dumps` (local scratch) | `tank/data/db-dumps` | rsync/cp after db-backup completes |
| Service state | Forgejo `forgejo dump` archive, n8n `sqlite3 .backup`, Authentik state | `tank/data/services/<svc>/` | rsync |
| Face thumbnails | Immich `thumbs/` face files | `bulk/data/immich-thumbs` | rsync over NFS (deltas) |

Key properties: dumps are written **locally first** (Kopia snapshots the local dir) and then pushed —
Kopia never reads NAS mounts, so off-site backup survives a dead NAS. All three jobs are systemd timers
deployed by the Ansible `storage` role.

---

## Kopia Policy (oldsrv agent → iDrive e2)

**Sources (all local, none on NAS):**
- `/srv/dumps` (SQL dump scratch)
- service state dirs (`/var/lib/forgejo-dump`, n8n backups, …)
- Immich face thumbnails (`thumbs/`)
- configs: `/opt/*` compose dirs, systemd units, HA config (/ etc — plus Git for the repo itself)

**Excluded:** Prometheus/Loki TSDB, docker named volumes (raw), Ollama models, Immich-ML weights,
`/mnt/nas/*` mounts entirely (NAS independence), `bulk/media` (not backed up by design).

---

## Compute-Host Local Disks (oldsrv + nas OS)

**Filesystem policy:** OS/boot disks are **ext4** on both hosts. The OS is 100% regenerable (preseed +
Ansible) and holds no unique data, so ZFS-on-root would only add boot/initramfs complexity with no
backup value. `tank`/`bulk` import at boot via the ZFS cachefile — root filesystem type is irrelevant.

| Disk | Host | Filesystem | Role |
|------|------|------------|------|
| 960 EVO 500 GB (200 TBW) | oldsrv | ext4 | OS/system only: `/`, `/var`, `/opt` — no churn, no Docker |
| 970 EVO 1 TB (600 TBW) | oldsrv | **ZFS pool `nvme`** | all local data — writes balanced on the durable/fast disk |
| MX300 525 GB | nas | ext4 | OS/boot only; `tank`/`bulk` imported via cachefile |
| microSD (32–64 GB) | pi | ext4 | HA primary + RaspberryMatic + Technitium secondary + `traefik-ha` edge — lean, no ZFS, no backup surface |

```
970 EVO 1 TB → ZFS pool "nvme" (single-disk; every dataset is NAS-backed or regenerable, no mirror needed)
├── nvme/docker-layers       /var/lib/docker        128K lz4   no snapshots (images re-pullable)
├── nvme/docker              /srv/docker (container, canmount=off)
│   ├── nvme/docker/postgres /srv/docker/postgres   8K   lz4   no snapshots (dumps = recovery point)
│   ├── nvme/docker/immich   /srv/docker/immich     128K lz4   thumbs + encoded-video; face thumbs → bulk
│   └── nvme/docker/services /srv/docker/services   128K zstd  forgejo, n8n, authentik, traefik, … (pushes + Kopia)
├── nvme/tsdb                /srv/tsdb   16K lz4    no snapshots, no backup (30d/14d regenerable)
├── nvme/models              /srv/models 128K off   no snapshots, no backup (ollama + immich-ml weights)
└── nvme/dumps               /srv/dumps  128K zstd  db-backup scratch → Kopia + push → tank/data/db-dumps
```

- **Snapshots:** only `nvme/docker/services` daily(7) (rollback before migrations); everything else none —
  the pool mirrors the NAS backup surface (dumps + services + face-thumbs) and adds convenience, not coverage.
- **Bind mounts, not named volumes** for stateful services: each service dir maps 1:1 to a dataset and
gives backup jobs/Kopia clean host paths (see `deployment-compose.md` → Volume Strategy).
- **Capacity budget:** keep `nvme` < 80% full (ZFS fragmentation). ~1 TB fits comfortably: DBs < 50 GB,
thumbs+encoded ~150–300 GB over 5 yr, docker layers ~50–100 GB, models ~60–150 GB, TSDB ~20–40 GB.
- Docker stays on overlay2 over `nvme/docker-layers` (auto-snapshot off on that dataset).

### Pi (HA node) — `/opt/<svc>`, no ZFS

The Pi is a Docker node too (HA primary + RaspberryMatic + Technitium secondary + `traefik-ha` edge), but
its data is **tiny and already covered** — configs in Git, everything else re-syncs or regenerates, so it
adds **no backup surface** (no datasets, no Kopia policy). No ZFS: microSD + 4 GB RAM, and every byte is
already mirrored by the Pi→standby sync.

> **MicroSD wear is minimised separately** (HA recorder + Docker/OS logs), see
> [`observability.md`](docs/observability.md) → *Pi SD-card wear strategy*: recorder is **trimmed, not disabled**
> (keeps Logbook / Energy-Dashboard LTS / history_stats); Pi logs are **streamed to Loki** with only a tiny
> bounded Docker-log buffer (`local`, 10m×2); `/var/log` + journald run on **tmpfs/RAM**.

**Pi filesystem layout on microSD (ext4, single partition):**

```
Pi microSD (ext4 — 32–64 GB, no ZFS, no backup surface)
├── /                    ext4 (raspi.debian.net image, regenerable)
├── /var/log             tmpfs (RAM; `journald Storage=volatile`, OS logs lost on reboot → Loki retains them)
├── /var/lib/docker      ext4 (overlay2 on microSD — images/containers; log driver capped to avoid heavy SD writes)
└── /opt/<svc>/          ext4 (Docker service configs + small state — see tree below)
```

```
/opt/<svc>/                  per-service: compose (docker_services role) + small data together
├── homeassistant/           HA Container (home_assistant role)
│   └── config/              configuration.yaml (templated from repo) + .storage/ + trimmed recorder DB
├── traefik-ha/              VIP-bound HA edge — compose + dynamic routes from repo
│   └── certs/               wildcard *.kogler.si rsync from oldsrv (ACME off on Pi) — regenerable
├── raspberrymatic/          CCU3 config — pairing lives on the HmIP-RFUSB *stick* (moves on failover)
└── technitium-secondary/    config.json + zones.db — secondary zones AXFR-replicate from oldsrv primary
```

- Coverage: HA `config/` → Git + 15-min rsync to `oldsrv` standby (+ optional Kopia); recorder DB →
  best-effort/regenerable; RaspberryMatic config → same 15-min rsync, pairing on the stick; Technitium
  zones → AXFR from primary; `traefik-ha` certs → re-rsync/re-issue from oldsrv ACME (single issuer).
- Pi data deliberately stays under `/opt/<svc>` (unlike oldsrv's `/srv/docker/<svc>`) — small footprint,
  and the role already pins `/opt/traefik-ha/certs/` as the cert-sync target.
- SD-card wear: HA recorder already trimmed (observability TODO); consider tmpfs for `/var/log`/`/var/tmp`.

---

## Capacity Budget & Alerts

| Pool | Now | Growth | Headroom |
|------|-----|--------|----------|
| `tank` (4 TB) | data < 1 TB | ~+0.5 TB/yr (family data) | ~5 yrs before 80% alert |
| `bulk` (6 TB) | media + replicas ≈ 1.5–2 TB | media grows fastest | **tight side** — ~2.5 TB media headroom yr 1, sliding to full by ~yr 4 |

Mitigations: extend Grafana alerts to **nas pools** — Warning **≥ 70%**, Critical **≥ 80%** (both `tank`,
`bulk`; per-pool, see `observability.md`). When `bulk` hits ~80%, offload `bulk/media` → **Phase 2 4 TB NVMe**
(`hardware-phase2.md`) — the planned media growth path. `tank` data stays put (mirror is the best disks).

---

## Immich Hybrid Storage (originals on NAS, thumbs/ML local)

- `UPLOAD_LOCATION` = **local NVMe** dir — `upload/thumbs` + `upload/encoded-video` + ML cache stay local.
- Enable **storage template** → originals land in `{UPLOAD_LOCATION}/library/...`.
- Bind-mount nas `tank/data/immich` → `{UPLOAD_LOCATION}/library` (NFS) — only big write-once originals cross NFS.
- Postgres + Immich-ML model weights local. ML **embeddings/face data live in Postgres** → covered by
  DB dumps; **face thumbnail files** are backed up (bulk + Kopia) because regenerating them means a full
  facial-recognition re-scan of the library (the expensive, non-obvious part). Plain thumbnails and
  encoded-video are regenerable on demand (Immich reconstruct job) — not backed up.

---

## Rebuild-from-NAS Runbook (oldsrv total loss, **no iDrive**)

Design invariant: with the NAS alive, a dead oldsrv is a config/DB restore, not a data migration —
all user data lives on the NAS and re-attaches via NFS.

1. Reinstall Debian from `preseed.cfg` (repo, GitHub mirror ok) on the replacement box.
2. `ansible-playbook site.yml` from the repo — needs **1Password** access (family safe recovery codes);
   images/weights pulled from registries/HuggingFace.
3. `storage` role mounts NFS: `tank/data → /mnt/nas/data`, `bulk/media → /mnt/nas/media`.
4. Restore DBs: fresh Postgres ← latest dumps from `/mnt/nas/data/db-dumps` (or local scratch if re-pushed).
5. Unpack service state from `/mnt/nas/data/services/*` (Forgejo dump, n8n sqlite + 1Password key,
   Authentik DB already in dumps).
6. Copy face thumbnails back from `bulk/data/immich-thumbs` (NFS) → local `thumbs/`.
7. Point Immich/OpenCloud at the existing NAS data — **no copy**: originals/documents/media are already
   there. Media library is untouched (Jellyfin/*arr resume from the same `/mnt/nas/media`).

Also covers `nas` boot-SSD death: reinstall (preseed), `zpool import tank bulk`, re-run Ansible — no
image backup of the MX300 needed; pools are self-describing. `nas` total-loss behaves differently:
services keep running (their state is on oldsrv), Immich photos + OpenCloud files are unavailable until
the NAS is rebuilt (accepted, see `backup.md`).

---

## Proposed IaC (`storage` Ansible role — stub for `deployment-ansible.md`)

Install `zfsutils-linux`, `sanoid`, `syncoid`; **import** pools — `tank`/`bulk` on nas, `nvme` on oldsrv
(never re-create; pools are self-describing); create datasets with the properties above; template
`sanoid.conf`; enable `sanoid.timer`/`syncoid.timer`; render `/etc/exports` (`tank/data`, `bulk/media`);
oldsrv `/etc/fstab` mounts + push timers; wire Kopia sources.
Run after `common`+`network`, before `docker_services` (containers need the NFS mounts).