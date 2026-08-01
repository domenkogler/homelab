# SilverStone SST-TS43xx Bulk Storage

> **Role:** Detail — external 4-bay HDD enclosure for bulk storage.
> **Links to:** `hardware-gen8.md`
> **Linked from:** `hardware.md`

---

## Hardware

| Component | Detail |
|-----------|--------|
| Model | SilverStone SST-TS43xx |
| Connection | **miniSAS only** (no USB, no eSATA) |
| Host | Connected to HP MicroServer Gen8 miniSAS card |
| Location | Rack cabinet |

---

## Drives

| Drive | Model | Size | Hours | Health |
|-------|-------|------|-------|--------|
| sda | WD Red WD30EFRX (5400rpm CMR) | 3 TB | 45,500 | ✅ |
| sdc | Toshiba P300 HDWD130 (7200rpm) | 3 TB | 6,481 | ✅ |
| sdf | Toshiba P300 HDWD130 (7200rpm) | 3 TB | 8,093 | ✅ |
| sdg | Toshiba P300 HDWD130 (7200rpm) | 3 TB | 8,156 | ✅ |
| sde | *(removed — critically failing)* | — | — | ❌ |

- **12 TB raw / 6 TB usable** in RAIDZ2 (2-disk fault tolerance)
- sde was zeroed and physically removed after showing 2,001 reallocated sectors + 32 pending

---

## Roles

- **Media archive** — raw Immich photos, video files, downloads
- **Cold data** — infrequently accessed files, old backups
- **Scratch space** — large temporary data before triage
- Serves as the **local backup target** via ZFS send/recv from gen8's "tank" pool

---

## Connection Decision

| Option | Pros | Cons |
|--------|------|------|
| **HP Gen8 (chosen)** | miniSAS card available; everything in rack | Extra network hop for debhost |
| i7-7700K | Direct access from Docker services | Needs separate HBA card (no miniSAS on motherboard) |

> SilverStone is miniSAS-only. gen8 is the only machine with a free miniSAS port.