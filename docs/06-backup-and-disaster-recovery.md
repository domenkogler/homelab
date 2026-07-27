# Backup & Disaster Recovery

> **Canonical doc.** Merges backup sections from `družinski web sistem.md`, `chosen db backup service.md`, answers from Theme G.

---

## Backup Architecture (Dual Layer)

### Layer 1: ZFS (Local — Block-Level)

Home server bulk data (media, photos, documents, ISOs) lives on ZFS pools and is replicated locally at block level:

```
┌──────────────────────────┐     zfs send/recv      ┌──────────────────────────┐
│   HP MicroServer Gen8    │ ───────────────────────→ │   HP MicroServer Gen8    │
│   ZFS pool "tank"        │    incremental, block-   │   ZFS pool "backup"      │
│   (WD Red + HGST)        │    level, every 15 min   │   (SilverStone miniSAS)  │
└──────────────────────────┘                          └──────────────────────────┘
```

- ZFS snapshots are instantaneous, immutable, and cheap (only changed blocks consume space)
- `zfs send/recv` transfers only changed blocks since the last snapshot — 10–50× faster than file-level scan for TB-scale data
- Snapshot schedule: every 15 min (kept 4), hourly (24), daily (7), weekly (4), monthly (3)
- Managed via **sanoid/syncoid** or cron-driven `zfs send -i`

### Layer 2: Kopia (Off-Site — Application-Level)

Application configs, databases, and critical small data go off-site via Kopia:

```
                   ┌──────────────────────────┐
                   │   tiredofit/db-backup    │
                   │   (on VPS, internal cron) │
                   │   Dumps PostgreSQL etc.   │
                   └───────────┬──────────────┘
                               │ SQL dump files
                               ▼
                   ┌──────────────────────────┐
                   │         Kopia            │
                   │  (on VPS + home server)  │
                   │  Encrypted, dedup, Web UI│
                   └───────────┬──────────────┘
                               │
                               ▼
                   ┌──────────────────────────┐
                   │      iDrive e2           │
                   │   (S3-compatible target) │
                   └──────────────────────────┘
```

### Why Two Layers?

| | ZFS send/recv | Kopia |
|---|---|---|
| **Scope** | Bulk data (media, ISOs, archives) | Configs, DB dumps, critical small files |
| **Speed** | Block-level incremental (very fast) | File-level with dedup (good for small files) |
| **Encryption** | Optional (ZFS native encryption) | Client-side (encrypted before leaving) |
| **Target** | HP Gen8 local backup pool | iDrive e2 cloud |
| **Recovery** | Instant zfs rollback to any snapshot | Kopia restore from cloud |

---

## Components

### tiredofit/db-backup (VPS)
- Long-lived Docker service with internal cron scheduler
- Supports: PostgreSQL, MySQL, MariaDB, MongoDB, InfluxDB, Redis, MSSQL
- Compression: Gzip, Bzip2, Xz, Zstd
- Verification: MD5/SHA1 checksums
- Retention: automatic cleanup of old dumps
- Upload connectors: S3, MinIO, Azure Blob Storage

### Kopia (VPS + Home Server)
- **Backs up: Both** VPS and home server configs, databases, and critical small files
- **Target:** iDrive e2 (S3-compatible)
- **Scope:** Configs, DB dumps, system files — NOT bulk media (that's ZFS send/recv)
- **Features:**
  - Client-side encryption (data encrypted before leaving the server)
  - Incremental snapshots (dedup across time)
  - Multi-threaded compression
  - Reed-Solomon error correction
  - Web GUI (exposed via Traefik, protected by Authentik SSO — sufficient for now; CLI needs TBD at first restore drill)
- **Master password:** Stored in 1Password vault (`Homelab`)

### ZFS (HP MicroServer Gen8 — Local)
- **Backs up:** Bulk data on the HP Gen8 ZFS pools
- **Target:** Local SilverStone backup pool via miniSAS
- **Features:**
  - Block-level incremental replication (`zfs send/recv`)
  - Instantaneous, immutable snapshots
  - Checksums detect and repair bit rot
  - No additional software needed — built into ZFS
  - Managed via sanoid/syncoid (community-standard snapshot & replication tool)

---

## Backup Flow

```
── ZFS path (bulk data, local) ──
1. sanoid takes ZFS snapshots every 15 min on HP Gen8 "tank" pool
2. syncoid replicates snapshots to SilverStone "backup" pool via zfs send/recv
3. Backup pool retains same snapshot schedule independently

── Kopia path (configs + DBs, off-site) ──
1. Cron triggers db-backup on VPS
2. db-backup dumps all databases to local SSD (/tmp or dedicated path)
3. Kopia snapshots: dump files + OpenCloud config + Immich metadata + Traefik configs
4. Kopia pushes encrypted snapshot to iDrive e2
5. Temp dump files cleaned up
```

---

## What Gets Backed Up

| Data | Location | Backup Method | Target |
|------|----------|---------------|--------|
| PostgreSQL DBs (Authentik, Immich, OpenCloud) | VPS SSD | db-backup → Kopia | iDrive e2 |
| OpenCloud configs | VPS SSD | Kopia | iDrive e2 |
| Immich metadata/thumbnails | VPS SSD | Kopia | iDrive e2 |
| Traefik + Authentik configs | VPS SSD | Kopia | iDrive e2 |
| Docker Compose files | VPS SSD | Kopia | iDrive e2 |
| Home Assistant configs | Home server/RPi | Kopia | iDrive e2 |
| Home server Docker configs | Home server | Kopia | iDrive e2 |
| Home server `/opt/` directories | Home server | Kopia | iDrive e2 |
| Home server systemd units (`/etc/systemd/system/docker-compose@*.service`) | Home server | Kopia | iDrive e2 |
| Home server package list (`dpkg --get-selections`) | Home server | Kopia | iDrive e2 |
| Home server ROCm config (`/etc/apt/sources.list.d/rocm.list`) | Home server | Kopia | iDrive e2 |
| Router configs (`*.rsc`) | Git repo | Git + Kopia | iDrive e2 |
| **Bulk media (photos, videos, ISOs, documents)** | **HP Gen8 ZFS tank** | **ZFS send/recv** | **HP Gen8 ZFS backup pool** |
| Immich **photos** (raw) | Hetzner Storage Box | Kopia → iDrive e2 | iDrive e2 |

> Bulk media on the HP Gen8 is replicated locally via ZFS send/recv to the SilverStone backup pool. This is much faster than Kopia for TB-scale data. Critical off-site copies of media go via Kopia from the HP Gen8 to iDrive e2.

---

## Disaster Recovery

### Restore Drills
- **Frequency: Yearly**
- Test: restore a random service from Kopia snapshot, verify it works

### Recovery Paths by Scenario

| Scenario | Recovery Steps |
|----------|---------------|
| **Single service crashes** | Kopia restore that service's data from latest snapshot |
| **Single file deleted/ corrupted** | ZFS rollback to snapshot before deletion (seconds) |
| **VPS destroyed** | 1. Provision new VPS (or reprovision existing) 2. Run Ansible playbook to install Docker + dirs 3. Kopia restore data 4. `docker compose up` |
| **Home server fails (Phase 1)** | 1. Reinstall Debian (same version) 2. Run Ansible: `common → docker → amd_rocm → desktop → kopia → docker_services` 3. Kopia restore `/opt/` + systemd units + package list |
| **HP Gen8 fails** | 1. ZFS backup pool on SilverStone is a separate physical enclosure — import it on a new machine 2. Replace Gen8 hardware, import pools |
| **Both HP Gen8 pools lost** | Restore bulk data from iDrive e2 via Kopia (slow — last resort) |
| **Home server fails (Phase 2)** | 1. Reinstall Proxmox 2. Run Ansible orchestration 3. Restore LXC configs + data from Kopia |
| **Router dies** | 1. Replace RB4011 2. Restore `.rsc` from Git 3. Adjust WAN MAC if needed |
| **Total house loss** | 1. VPS + iDrive e2 survive (off-site) 2. Rebuild home server from Git + Ansible 3. Restore data from Kopia 4. Replace networking hardware |

---

## Family Access to Backups

### Backup Password
- **Kopia master password:** In 1Password (vault: `Homelab`)
- **1Password master password + recovery codes:** On paper in **family safe**
- **Family safe also contains:** Link to this GitHub repo (self-hosted Forgejo + public GitHub mirror)

### For the Family
- README.md at repo root is the starting point
- Family safe has everything needed to bootstrap access
- No single point of failure (1Password cloud + paper backup + Git mirrors)

---

## Git Repository

- **Primary:** Self-hosted Forgejo on VPS (Authentik OIDC)
- **Mirror:** GitHub (public or private)
- **Contents:** All Ansible playbooks, Docker Compose files, RouterOS scripts, documentation
- **Goal:** `git clone` + `ansible-playbook` = fully rebuilt infrastructure
- All configs already on GitHub today

---

## Open Questions

- **Restic was rejected for no Web GUI — is Kopia's Web GUI sufficient, or is CLI scripting needed too?**
- **Sanoid/Syncoid vs. plain cron + zfs send -i:** sanoid/syncoid adds snapshot management, pruning, and monitoring. Start with cron for simplicity, migrate to sanoid once pools are stable.
- **Kopia for bulk media off-site:** Does iDrive e2 have enough space/cost-headroom for the full media library? If not, bulk media stays local-only (ZFS) and only configs/DBs go off-site.