# Backup & Disaster Recovery

> **Canonical doc.** Merges backup sections from `družinski web sistem.md`, `chosen db backup service.md`, answers from Theme G.

---

## Backup Architecture

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
- **Backs up: Both** VPS and home server
- **Target:** iDrive e2 (S3-compatible)
- **Features:**
  - Client-side encryption (data encrypted before leaving the server)
  - Incremental snapshots (dedup across time)
  - Multi-threaded compression
  - Reed-Solomon error correction
  - Web GUI (exposed via Traefik, protected by Authentik SSO — sufficient for now; CLI needs TBD at first restore drill)
- **Master password:** Stored in 1Password vault (`Homelab`)

---

## Backup Flow

```
1. Cron triggers db-backup
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
| Home server LXC configs | Home server | Kopia | iDrive e2 |
| Router configs (`*.rsc`) | Git repo | Git + Kopia | iDrive e2 |
| Immich **photos** (raw) | Hetzner Storage Box | Kopia → iDrive e2 | iDrive e2 |

> Immich photos on Storage Box are also backed up via Kopia to iDrive e2 for off-site redundancy.

> **⚠️ Immich photos on Hetzner Storage Box:** The Storage Box has built-in RAID/data protection. If additional off-site backup of photos is needed, that's a separate decision (iDrive e2 or another S3 bucket).

---

## Disaster Recovery

### Restore Drills
- **Frequency: Yearly**
- Test: restore a random service from Kopia snapshot, verify it works

### Recovery Paths by Scenario

| Scenario | Recovery Steps |
|----------|---------------|
| **Single service crashes** | Kopia restore that service's data from latest snapshot |
| **VPS destroyed** | 1. Provision new VPS (or reprovision existing) 2. Run Ansible playbook to install Docker + dirs 3. Kopia restore data 4. `docker compose up` |
| **Home server fails** | 1. Reinstall Proxmox 2. Run Ansible orchestration 3. Restore LXC configs + data from Kopia |
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

## Open Question

- **Restic was rejected for no Web GUI — is Kopia's Web GUI sufficient, or is CLI scripting needed too?**