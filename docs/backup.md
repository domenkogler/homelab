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
**HTTPS on the WG S2S tunnel** (HD-318a) — **kopia 0.23.x rejects `http://`**, so the server serves a
persisted self-signed cert and the agent pins its stable SHA-256 fingerprint from the
`kopia-server_fingerprint` item. A cert that is regenerated per start makes every agent pin wrong at the
next restart — persist it, pin the fingerprint. — server port 51515 is bound **only to the VPS tunnel address**
(`wg_s2s_vps.ip`, never 0.0.0.0; loopback-only until the router peer key is provisioned), so reach stays
scoped by the S2S ACL (HD-155). Agent sources are oldsrv-local, read-only: `/opt/*` configs,
`/srv/dumps` scratch, the immich upload/thumb dir, and the signal-cli state volume.

> ✅ **Status: the oldsrv `kopia-agent` connects over HTTPS + fingerprint pin and takes snapshots**
> (`/opt/*` configs + signal-cli state; retention labels send them offsite to the backup Box). The
> fingerprint is seeded by a **VPS-only** task (`kopia-fingerprint-sync.yml`) — an agent-side task cannot
> produce it, which is why the pin used to be permanently missing.
>
> **HD-318a — kopia's server-auth model needs TWO things to agree:** the client's `user@host` identity must
> exist BOTH in the htpasswd (allowed `user@hostname` entries) AND as a repo user (`kopia server users add`)
> whose password equals the **repo master password** (what the client passes to `connect --password`). A
> non-repo-password user is `access denied` **at the session stage even with a matching htpasswd entry** —
> the confusing part is that the earlier stages succeed. The boot script writes both htpasswd entries and
> idempotently provisions the repo user. **Compose interpolation gotcha in the same file:** the command block
> must be `$$`-escaped, or single-`$` interpolation mangles the credential at parse time.
> `user@host` identity to exist BOTH in the htpasswd (`--htpasswd-file` = allowed `user@hostname` entries) AND as a
> repo user (`kopia server users add`) whose password equals the **repo master password** (the client's `connect
> --password`) — a non-repo-password user is `access denied` at the session stage even with a matching htpasswd
> entry. The kopia-server boot script now writes both htpasswd entries (server admin + `kopia_agent_user`) and
> idempotently provisions/re-seeds the repo user (`kopia server users add/set` with `KOPIA_PASSWORD`). The compose
> command block is `$$`-escaped (single-`$` compose interpolation was mangling the credential at parse time).

> **Kopia-server first-run gate (HD-271-followup):** the server's first-run
> bootstrap (`kopia repository create sftp`) must be gated on **`repository.config`** (kopia's
> repo-connection file) — NOT `config.json` (an unrelated technitium zone file). With the wrong gate
> and a repo already on the backup Box, every boot re-ran `create` → `found existing data in storage
> location` → `set -e` exit → crash-loop. Gate on `/app/config/repository.config` (create only when
> absent) and the server starts against the existing repo (maintenance/GC run normally).

```
tiredofit/db-backup (local scratch) →  Kopia agent (VPS + oldsrv) →  Hetzner Storage Box (backup) SSH/SFTP :23
   + service state + face thumbs       (encrypted, dedup)       (far-DC: Helsinki/Falkenstein — SB-Backup HEL1-BX186)
```

> **Off-site (HD-29/31): two Hetzner Storage Boxes.** **Live** box (nearest DC) serves
> Immich originals **+ encoded-video** and the family SMB/WebDAV drives (CIFS, **not S3** — HD-135); **backup** box (far DC) hosts the Kopia repo.
> **iDrive e2 dropped** (Hetzner cheaper per TB + SMB/WebDAV; single-provider risk accepted).
>
> **Box identifiers (Hetzner Storage Box console → robot.hetzner.com):**
>
> | Box | Hetzner identifier | Location | Purpose |
> |-----|--------------------|----------|---------|
> | **live** | **SB-Data** · `FSN1-BX2190` | **Falkenstein, Germany** (`eu-central`) | originals store (Immich + OpenCloud over CIFS/WebDAV, `//u653411.../backup`) |
> | **backup** | **SB-Backup** · `HEL1-BX186` | **Helsinki, Finland** (`eu-central`) | Kopia off-site repo (SSH/SFTP :23) |

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
| PostgreSQL DBs — **Authentik, Forgejo, Immich, Zipline** (HD-112), **LiteLLM runtime** (HD-247: `STORE_MODEL_IN_DB` ⇒ the DB holds keys/models/spend) — all on the **VPS** via `db-backup` `DB01–03` + `DB05–06` | VPS NVMe | ⚠ **daily dumps, ONE copy, on the same disk as the databases** — see §VPS-side coverage gap. The documented `→ tank/data/db-dumps (ZFS)` push and the Kopia snapshot of the dump volume **do not exist** | *(intended: ZFS `tank/data/db-dumps` + Storage Box via Kopia — **not live**)* |
| **`lan-litellm-db` on oldsrv** (the LAN inference gateway's Postgres) | oldsrv | ⚠ **no dump job exists on oldsrv at all** (no `db-backup` container; `/srv/dumps` was created 2026-09-03 and has been empty ever since, while the oldsrv `kopia-agent` snapshots that empty dir) — the same `STORE_MODEL_IN_DB` class the VPS closed with DB06 in HD-247 | *(nothing — open gap)* |
| **Matrix server state + signing identity + media store** (HD-49) — tuwunel: RocksDB room/user state, the **server signing key** + key-notary data, the E2EE key-backup, `media/` and `archive/` | VPS NVMe `/srv/docker/matrix` (single bind → `/var/lib/tuwunel`) | **Nothing backs it up today** — the path is not in any snapshot because there is no VPS-side Kopia client (§VPS-side coverage gap). Note there is **no separate key file to archive**: `database_path` is the data dir and probing it finds no `*.pem`/keystore file, so the signing identity lives inside the same RocksDB store as the rooms | *(pending the VPS client; then one row covers all of it)* — see §Matrix: what one path buys and what it does not |
| **RustDesk server keypair + client registrations** (HD-412) — `/srv/docker/rustdesk-server/data` | VPS NVMe | **Primary restore is 1Password `rustdesk_login`, not a snapshot** (the s6 unit re-seeds `/data/id_ed25519*` from `KEY_PUB`/`KEY_PRIV` when absent, so wiping the dir + re-converging restores the identity and enrolled clients keep working). The snapshot only has to cover `db_v2.sqlite3` (client/peer registrations) — losing it re-prompts devices, it does not lock anyone out | 1P (identity) + Kopia once the VPS client exists (registrations) |
| **Qdrant** vector store (`/srv/docker/qdrant`), HD-267/268 | VPS NVMe | **rebuildable cache** (docs/services-ai.md §5b) — snapshot/export via Qdrant REST `/snapshots` + Kopia-backed host bind; **not** a db-backup Postgres dump | `tank/data/services` (ZFS) + Hetzner Storage Box (Kopia) — *intended; same VPS-client caveat* |
| Docker Compose files / systemd units / configs | Git repo + host `/opt/*` (**VPS + oldsrv**) | Git (+ Kopia) | Forgejo + GitHub mirror / Hetzner Storage Box (backup) |
| Service state (Forgejo dump, n8n sqlite, **LiteLLM keys/spend → moved into litellm-db Postgres, dumped via db-backup DB06** (HD-247 models-in-DB: the DB is the critical state, `/srv/docker/litellm` keeps only misc app state), **OpenClaw config/state** — HD-104 on the **VPS**; **AI harness (pi-dev + DSH) workspaces** (`/srv/docker/pi-dev/workspace`, `/srv/docker/dsh/workspace`, HD-268c); **Seerr config + `seerr.db`** — HD-130/KOPS-059 on **oldsrv**; …) | VPS NVMe (edge/GitOps/AI tier) · oldsrv NVMe (*arr/LAN core) | nightly push + Kopia | `tank/data/services` (ZFS) + Hetzner Storage Box (backup) |
| **Zipline file payloads** (`/srv/docker/zipline/uploads` — datasource; HD-112) | VPS NVMe | **Kopia-EXCLUDED by design**: anonymous dropzone drops self-destruct at ≤ 6h TTL (guestbin quota-bounded); private-account files are owner-managed | — *(ephemeral/regenerable-by-design — observability-TSDB precedent)*. The metadata DB IS dumped (`db-backup` DB05). |
| Home Assistant configs | RPi 4 (+ standby on oldsrv) | Git + standby sync | repo / oldsrv (Kopia) |
| Router configs (`*.rsc`) | Git repo | Git + Kopia | Hetzner Storage Box (backup) |
| Immich **originals + encoded-video** (photos/videos) | **live Hetzner Box** (CIFS `//u653411.../backup`, VPS) | **live tier** (HD-135) | backed by **Kopia → backup Box** (off-site) **+ the Immich DB** (albums/faces/tags) — D3. *Supersedes the MinIO/S3-originals plan (HD-131 D1).* |
| Immich **face thumbnails** | oldsrv NVMe | nightly rsync + Kopia | `bulk/data/immich-thumbs` + Hetzner Storage Box (backup) |
| **Media library** (movies/tv/music) | **nas `bulk/media`** | **NOT backed up** | redownloadable via usenet/torrents |

> **Victoria observability (HD-342):** the VictoriaMetrics (VM, 365d metrics) + VictoriaLogs (VL, 90d logs) volumes are **Kopia-backed** (owner decision — reverses the old "regenerable, NOT backed up" doctrine for Prometheus 30d/Loki 14d). They live on the **VPS NVMe** (HD-135 backend placement) at `/srv/docker/victoria-metrics/data` + `/srv/docker/victoria-logs/data` (host binds). ⚠ **The snapshooting client for these — and for every other `/srv/docker` path on the VPS — does not exist yet: §VPS-side coverage gap. Until it does, "Kopia-backed" in this section is the policy, not the state.**

### VPS-side coverage gap

**What is true (probed 2026-09-21, read-only):**

- The VPS runs `kopia-server` — the **repository endpoint** that other hosts' agents push through (the
  repository itself is remote: `KOPIA_SFTP_*` in `/opt/kopia-server/docker-compose.yml`). oldsrv has run
  its own `kopia-agent` container since HD-102 and is what makes the home-side coverage real.
- The VPS has **no backup client of its own**: no `kopia` binary, no client config (`/root/.config/kopia`
  absent), no `kopia-agent` container in the registry. Every "Kopia-backed" / "nightly push" claim in this
  file about a **VPS path** is therefore policy-ahead-of-state (CONVENTIONS §3 calls this out by name).
- Measured consequences: `db-backup` keeps **767 MB of daily SQL dumps (oldest 2026-08-24) in one docker
  volume on the VPS NVMe** — the only copy of the Authentik/Forgejo/Immich/Zipline/LiteLLM state; the
  storage box mounted at `/mnt/storagebox` holds only `music`, so the intended `→ tank/data/db-dumps`
  push has never run; nothing under `/srv/docker/*` (Matrix, Headscale, CrowdSec, n8n, OpenCloud,
  Grafana, docling model cache, …) is in any off-site snapshot.
- **What a VPS NVMe loss costs today, honestly:** every VPS-hosted Postgres (Authentik = the IdP, so
  SSO for the whole homelab; Forgejo = the Git state that `deployment.md` calls the source of truth;
  Immich metadata; Zipline; LiteLLM keys/spend/models), the Matrix federation identity, Headscale
  (the tailnet control plane), CrowdSec decisions, n8n/OpenCloud/Grafana state. Configs and IaC survive
  (Git + Forgejo mirror), so the rebuild is mechanical — but the **data** is not covered.

**The fix is small and already precedented:** oldsrv's `kopia-agent` (include list = `/opt`,
`/srv/dumps`, `/srv/docker/immich/upload`, one docker volume) is the shape. A VPS-side agent needs
`/opt`, the `db-backup` dump volume and the `/srv/docker/*` service-state dirs. Until that lands, the
scope rows above stay written as *policy* and HD-49/HD-102/HD-238 stay open — adding a Matrix or
RustDesk row to an include list that has no client to attach to would only make the doc more fiction.

### Matrix: what one path buys and what it does not

- **One bind covers the server identity.** `tuwunel.toml` sets `database_path = /var/lib/tuwunel` →
  `/srv/docker/matrix`, and that directory holds RocksDB state + `media/` + `archive/`; there is no
  separate `*.pem`/keystore file (probed), so the **signing key that other servers trust is inside the
  same store as the room state**. Snapshotting one path therefore restores identity *and* history
  together — and a partial restore (state without media, or an older state than the media) leaves
  events pointing at missing attachments, so restore the pair as one unit.
- **Losing it without a snapshot is the externally-coupled class** (same shape as `rustdesk_login`):
  a fresh server generates a new signing key, other servers keep the old one in their key-notary caches,
  and rooms federated with those servers keep rejecting it. Recovery = re-federate under a new key and
  wait out notary expiry; there is no "re-enrol" button. This is why the row belongs to the *policy*
  section and not to "rebuildable".
- **Client-side E2EE room keys are out of scope of any server backup.** The server only stores the
  encrypted key *backup* (inside the same store); a client that has never restored its backup loses
  history regardless of what the server snapshot contains. Say so in the family-facing runbook rather
  than implying the server snapshot recovers readable history.

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
| **Originals store** | Hetzner Storage Box **live** — **SB-Data** (`FSN1-BX2190`, Falkenstein, Germany · `eu-central`; `//u653411.../backup`, CIFS-mounted to VPS) | Cloud | CIFS/SMB + WebDAV |
| **Local backup** | home NAS (snapshot / nightly push) | HDD | LAN (fast restore) |
| **Off-site backup** | Hetzner Storage Box **backup** — **SB-Backup** (`HEL1-BX186`, Helsinki, Finland · `eu-central`) (Kopia over **SSH/SFTP**, port 23, encrypted, NAS-independent) | Cloud | SSH/SFTP (port 23) |

> **Media is the deliberate exception** to 3-2-1: `bulk/media` is redownloadable, so 0-1-0 suffices
> (RAIDZ2 redundancy, no backup copy) — see [`storage.md`](storage.md).

> **Accepted residual risk (S13):** the off-site Kopia repo is encrypted but not immutable — a
> ransomware attacker holding the Box credentials/key could reach the backup copy. Accepted for now;
> mitigation options if ever needed: Storage Box snapshot/versioning, or a second cold credential.
> Restore-drill discipline (yearly) is the current integrity check.

---

## Disaster Recovery

### Runbook — restore the non-GPU tier on a replacement VPS (HD-238)

> Scope: the VPS-hosted (non-GPU) tier — edge/GitOps/IdP + the CPU AI legs. Registry-driven rebuild:
> the roster, pins and secrets come from Git, so the only open question in a real loss is **which state
> exists** — read §VPS-side coverage gap first, it changes what this runbook can achieve.

1. Rebuild the host to Debian at the provider panel, then land the runner path before anything else —
   [deployment-manual.md](../deployment-manual.md) §Phase 0 → §Phase 0.5 (SSH + `ansible-admin`).
   No other step works until that does.
2. Restore the address plane before the data plane. If the replacement got a **different public IPv4**,
   change these together in one commit (a stale one silently serves the dead box): `dns_primary_ip` in
   `IaC/ansible/group_vars/all/main.yml`, the Cloudflare A records for `*.kogler.si`, the Headscale
   API/`base-domain` config, and the Technitium primary records ([network-dns.md](network-dns.md)).
3. Converge in role order — `bash scripts/ansible-run.sh playbooks/vps.yml --limit vps` (hardening
   before `docker_services`; scoped runs need both tag classes per
   [scripts/README.md](../scripts/README.md); never `--diff`). Do not hand-build a service to "get it
   back quickly": the next converge will disagree with it.
4. Restore state in dependency order — the IdP before anything that authenticates against it:
   1. Stop the app containers that depend on a restore, restore, then start them.
   2. Kopia-restore each service dir to **its exact host-bind path** — the map is
      `docker inspect <svc> --format '{{range .Mounts}}{{.Source}} => {{.Destination}}{{end}}'`, and
      when the old box is gone the compose template in `templates/docker_services/<svc>/` is the map.
   3. Postgres: bring up the DB container alone, load the newest dump from the Kopia copy of the
      `db-backup` dump volume, then start the application container. Never restore into a live app.
   4. `kopia-server` before any agent: it needs the SFTP repository (connection-ref
      `Hertzner-SB-Backup` — the box survives the VPS) plus `kopia-server-internal_api` (server-admin +
      the per-client `…-agent@host` identity), `kopia_password` (the repo master password — kopia quirk:
      the repo user authenticates with this, not the API credential) and the agent-side
      `kopia-server_fingerprint` re-pinned to the new cert, or every home-side agent silently stops pushing.
      A backup path that fails silently is worse than one that is missing.
   5. Matrix: restore `/srv/docker/matrix` as one unit ([backup.md](backup.md) §Matrix) — it is the
      federation signing identity as well as the rooms.
5. Re-point the home side: oldsrv `kopia-agent`, the thin Alloy collectors, the WG S2S peers, and the
   Samba/nas paths that resolve VPS hostnames. Headscale caveat: if its state was lost, **every tailnet
   device re-enrols** — HD-220's peer import/key backup is the only shortcut, so budget for the
   re-enrolment sweep rather than promising a flip.
6. Verify the two-sided gate before calling it restored (CONVENTIONS §3): `docker ps` roster equals the
   registry's enabled set with no restart loops; `sso`/`git` return 302; the observability dashboards
   resume; the RustDesk relay answers (services-vps.md row 8); then write the dated evidence next to
   whatever ledger item this closes.
7. Record in this file what the restore actually cost — minutes, and which state was missing. A gap
   discovered *during* a restore is a ledger finding, not an incident detail.

### Restore drill (yearly)

1. Pick a snapshot at random (not the newest — a drill that always passes on the newest copy proves
   nothing about the retention tail).
2. Restore it to a **scratch path on a scratch container**; never onto a live host bind.
3. Prove the payload reads, not that the copy finished: query the restored DB, open the restored app
   dir, count files and compare with the source manifest.
4. Record: snapshot id, age, restore duration, restored size, and whether anything wrote to the source
   between snapshot and restore.
5. Repeat for one Postgres dump and for one `/srv/docker` service dir — they exercise different paths
   (application dump vs file-level snapshot).
6. Schedule the next drill in the same sitting as the one you just ran, and tick the ledger line with
   the dated result. A drill with no recorded result is a drill that did not happen.

### Restore Drills
- **Frequency: Yearly**
- Test: restore random service from Kopia snapshot, verify it works

### Recovery Paths

| Scenario | Recovery Steps |
|----------|---------------|
| **Single service crashes** | Kopia restore that service's data from latest snapshot |
| **Single file deleted/corrupted** | ZFS rollback to snapshot before deletion (seconds) |
| **VPS fails (the non-GPU tier)** | Imperative runbook: §Runbook — restore the non-GPU tier on a replacement VPS. ⚠ Read §VPS-side coverage gap first: today the VPS's own state has **no off-site copy**, so this path rebuilds config from Git and recovers **only** what the home side holds — the VPS Postgres dumps die with the disk |
| **oldsrv fails (Phase 1)** | Rebuild **from the NAS, no off-site** — runbook in [`storage.md`](storage.md): preseed reinstall → Ansible → mount NFS → restore DBs from dumps → unpack `tank/data/services` → copy thumbs back. ⚠ "restore DBs from dumps" covers the **VPS-side** dumps; oldsrv's own `lan-litellm-db` has no dump job (§What Gets Backed Up) |
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
- **VPS-side backup client (blocks HD-49 / HD-238 / the VPS rows above):** a `kopia-agent` on the VPS
  with `/opt` + the `db-backup` dump volume + the `/srv/docker/*` state dirs, or an equivalent push of
  the dump volume to the storage box. Until one exists, the VPS is the one host in the homelab whose
  own data has no second copy.
- **Bulk media off-site:** live + backup Hybrid Storage Boxes (BX11, bought/planned 2026); bulk media library stays local-only on NAS (ZFS), only configs/DBs + Immich originals go off-site. Off-site copy via Kopia over SSH/SFTP (port 23); **no S3 / Object Storage** (Hetzner Storage Box is not S3 — handled via CIFS mount + Kopia over SSH).