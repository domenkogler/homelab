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
| PostgreSQL DBs — **Authentik, Forgejo, Immich** (`db-backup` `DB01–03`) and **LiteLLM runtime** (HD-247: `STORE_MODEL_IN_DB` ⇒ the DB holds keys/models/spend; block `DB04` **since 2026-10-07** — as `DB06` it was never dumped once, §The slot-numbering rule) — all on the **VPS**. **Zipline has no block at all** (the old `DB05` claim was fiction) | VPS NVMe | daily dumps in the `db-backup` volume, **mirrored off-box every night since 2026-10-07 by `vps-state-push` (§VPS state push, HD-470)** — before that: ONE copy on the same disk as the databases. The documented `→ tank/data/db-dumps (ZFS)` push and a Kopia snapshot of the dump volume still **do not exist** | Hetzner Storage Box `vps-state/vps.kogler.si/dumps` (rsync, **not encrypted at rest**); Kopia still unattached |
| **`lan-litellm-db` on oldsrv** (the LAN inference gateway's Postgres) | oldsrv | **dump job now exists (HD-468, 2026-09-28)**: `storage-push-db-dumps.sh` runs `pg_dumpall` inside `lan-litellm-db`, gzip-tests the dump, refuses to ship an empty one, and rsyncs with owner/group preservation OFF — the export is `root_squash,anonuid=1005`, so `rsync -a` could only ever die on `chown` (rc 23). Local retention 14, no `--delete` on the NAS side (sanoid owns retention) | oldsrv `/srv/dumps` → `tank/data/db-dumps` (ZFS) |
| **Matrix server state + signing identity + media store** (HD-49) — tuwunel: RocksDB room/user state, the **server signing key** + key-notary data, the E2EE key-backup, `media/` and `archive/` | VPS NVMe `/srv/docker/matrix` (single bind → `/var/lib/tuwunel`) | **Nothing backs it up today** — the path is not in any snapshot because there is no VPS-side Kopia client (§VPS-side coverage gap). Note there is **no separate key file to archive**: `database_path` is the data dir and probing it finds no `*.pem`/keystore file, so the signing identity lives inside the same RocksDB store as the rooms | *(pending the VPS client; then one row covers all of it)* — see §Matrix: what one path buys and what it does not |
| **RustDesk server keypair + client registrations** (HD-412) — `/srv/docker/rustdesk-server/data` | VPS NVMe | **Primary restore is 1Password `rustdesk_login`, not a snapshot** (the s6 unit re-seeds `/data/id_ed25519*` from `KEY_PUB`/`KEY_PRIV` when absent, so wiping the dir + re-converging restores the identity and enrolled clients keep working). The snapshot only has to cover `db_v2.sqlite3` (client/peer registrations) — losing it re-prompts devices, it does not lock anyone out | 1P (identity) + Kopia once the VPS client exists (registrations) |
| **Qdrant** vector store (`/srv/docker/qdrant`), HD-267/268 | VPS NVMe | **rebuildable cache** (docs/services-ai.md §5b) — snapshot/export via Qdrant REST `/snapshots` + Kopia-backed host bind; **not** a db-backup Postgres dump | `tank/data/services` (ZFS) + Hetzner Storage Box (Kopia) — *intended; same VPS-client caveat* |
| Docker Compose files / systemd units / configs | Git repo + host `/opt/*` (**VPS + oldsrv**) | Git (+ Kopia) | Forgejo + GitHub mirror / Hetzner Storage Box (backup) |
| Service state (Forgejo dump, n8n sqlite, **LiteLLM keys/spend → moved into litellm-db Postgres, dumped via db-backup DB06** (HD-247 models-in-DB: the DB is the critical state, `/srv/docker/litellm` keeps only misc app state), **OpenClaw config/state** — HD-104 on the **VPS**; **AI harness (pi-dev + DSH) workspaces** (`/srv/docker/pi-dev/workspace`, `/srv/docker/dsh/workspace`, HD-268c); **Seerr config + `seerr.db`** — HD-130/KOPS-059 on **oldsrv**; …) | VPS NVMe (edge/GitOps/AI tier) · oldsrv NVMe (*arr/LAN core) | ⚠ **the push fails every night** — `push-services` dumps `forgejo`/`n8n` containers that exist only on the VPS while the unit is installed on oldsrv (**HD-468**) — + Kopia | `tank/data/services` (ZFS) + Hetzner Storage Box (backup) — ⚠ the oldsrv unit that named these containers was REMOVED 2026-09-28 (HD-468): they are vps-side, and the vps dump is ONE copy on ONE disk — **changed 2026-10-07 for the VPS half only:** `vps-state-push` mirrors the dumps, every `/opt/*/docker-compose.yml` + `.env` and the n8n sqlite trio to the Storage Box nightly (§VPS state push); the oldsrv half of this row is untouched |
| **Zipline file payloads** (`/srv/docker/zipline/uploads` — datasource; HD-112) | VPS NVMe | **Kopia-EXCLUDED by design**: anonymous dropzone drops self-destruct at ≤ 6h TTL (guestbin quota-bounded); private-account files are owner-managed | — *(ephemeral/regenerable-by-design — observability-TSDB precedent)*. ✅ **The metadata DB is dumped as of 2026-10-07** (`db-backup DB05`) — but it was **never** dumped before that: the compose had no `DB05` block at all, so the claim in this table was fiction for months (measured, and the reason is §The slot-numbering rule). First dump: `pgsql_zipline_zipline-db_20261007-031636.sql.zst`, mirrored to the box the same night. |
| Home Assistant configs | RPi 4 (+ standby on oldsrv) | Git + standby sync | repo / oldsrv (Kopia) |
| Router configs (`*.rsc`) | Git repo | Git + Kopia | Hetzner Storage Box (backup) |
| Immich **originals + encoded-video** (photos/videos) | **live Hetzner Box** (CIFS `//u653411.../backup`, VPS) | **live tier** (HD-135) | backed by **Kopia → backup Box** (off-site) **+ the Immich DB** (albums/faces/tags) — D3. *Supersedes the MinIO/S3-originals plan (HD-131 D1).* |
| Immich **face thumbnails** | **VPS** NVMe `/srv/docker/immich/upload/thumbs` (measured 1.2 MB; immich-server/-postgres/-valkey all run there) — **not** oldsrv, which runs only the immich-ml leg and holds no user data | ⚠ **unbacked**: the oldsrv `push-face-thumbs` unit named a path that does not exist there and was REMOVED 2026-09-28 (**HD-468**); the VPS has no push path (**HD-191**) — + Kopia covers VPS NVMe where the tree actually is | `bulk/data/immich-thumbs` + Hetzner Storage Box (backup) |
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

### VPS state push — what runs now (HD-470, live 2026-10-07)

`vps-state-push.service` + `.timer` (installed by the `docker_services` role on the VPS; daily
23:15 after db-backup's 20:01 fire, `Persistent=true`, `Nice=10`/`IOSchedulingClass=idle` because
this box serves production from 16 GB). Payload, in one rsync pass to the box the `cifs` role
already mounts:

| what | source (measured, not assumed) | on the box |
|---|---|---|
| every Postgres dump db-backup keeps | `/var/lib/docker/volumes/db-backup_db-backups/_data` (1.3 GiB, 286 files) | `vps-state/vps.kogler.si/dumps/` |
| the declarative state of every service | `/opt/*/docker-compose.yml` + `/opt/*/.env` (41 files, 0.2 MiB) | `vps-state/vps.kogler.si/state/opt/` |
| n8n's database (runs `DB_TYPE: sqlite`, so it has **no dump path**) | `/srv/docker/n8n/data/database.sqlite*` | `state/n8n-sqlite/` |

* **The guard is the point.** If `/mnt/storagebox` is not a CIFS/SMB mount the unit exits **90**
  instead of rsyncing: a dead mount is an empty directory on the VPS's own disk, and the "off-box
  copy" would then be a same-disk copy that reports success — the HD-450 self-pull class, same
  shape, different transport. The test accepts `cifs` from findmnt **or** `smb2` from statfs and
  reads the *innermost* entry of the mount stack (the box sits under an `autofs` layer; a string
  equality on `findmnt --target` failed on the first live run for exactly that reason).
* **CIFS carries no unix symlinks.** db-backup marks each DB's newest dump with a `latest-*`
  symlink; mirroring them fails `Input/output error (5)` (rsync rc 23). The aliases are excluded
  and the unit rebuilds the index as a plain `dumps/LATEST.txt`.
* **Acceptance was read back, not inferred:** 1.3 GiB present through the mount, `zstd -t` of the
  newest dump inside the unit (exit 91 if that fails), and **a real restore** — the Forgejo dump
  into a scratch `postgres:16.15-alpine` gave **130 tables against production's 130**.
* **Restore recipe these dumps actually need** (they are written by pg_dump **18.3** against
  servers running **16.15**): drop `SET transaction_timeout = 0;` (a PG 18-only GUC — aborts a
  PG 16 restore at line 12) and the new `\restrict`/`\unrestrict` meta-commands, and `CREATE ROLE
  <dbuser>` before restoring, or every `OWNER TO` fails. Verified end to end, not theorized.
* **Still not covered, said plainly:** Matrix/tuwunel (RocksDB state *and* the signing identity),
  Headscale, CrowdSec decisions, Qdrant, OpenCloud, Grafana, the **Forgejo git repos**, and the
  immich originals — the box holds only an empty `music/`, so the immich originals are on the VPS
  disk too (289 MB under `/srv/docker/immich/upload`), which also makes the `cifs` role header's
  "Immich originals live on the Box" claim stale. And this is rsync to a CIFS share, **not** the
  encrypted snapshot Kopia would give: the kopia-client gap below is unchanged.

**The slot-numbering rule (found the hard way, 2026-10-07, and it was costing real state).**
`tiredofit/db-backup` builds one `dbbackup-NN` scheduler per configured block but numbers those
slots **sequentially from 01**, while each slot's job reads `DB{NN}_*`. With blocks
`DB01/DB02/DB03/DB06` the fourth slot looked for `DB04_*`, logged `No 'appropriate database type'
Entered!` on every fire, and dumped **nothing** — so **LiteLLM's keys/models/spend (HD-247,
classified CRITICAL, irretrievable-metadata) had never been dumped**, weeks after its block was
added, while `docker ps` showed db-backup "Up" and `backup04-now` was the only command that would
say so. The same mechanism left a retired `pgvector` block dumping nothing since 2026-08-27. Fix:
blocks are numbered **contiguously from DB01** — LiteLLM is `DB04` now, and a number is never
reserved for a database that does not exist yet (a reserved number *is* a broken block). First
LiteLLM dump in history: `pgsql_litellm_litellm-db_20261007-030224.sql.zst`. **The general rule:
any component whose config is read once at container init, not at run time, needs its container
recreated after a config change — and a block that never produces output is a fault, so its
"did it run today" signal has to be the output, not the unit's `active` state.**

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

### ⚠ What the 2026-09-28 sweep of the oldsrv push legs found (HD-468)

Three red timers, three different truths, and only one of them was the one the failures named:

- `push-db-dumps` — **two stacked defects.** `rsync -a` cannot chown onto an export mounted
  `root_squash,anonuid=1005` (rc 23 every night), **and there was no producer at all** — `/srv/dumps`
  was an empty directory, so fixing only the rsync flags would have produced a green timer shipping
  nothing. Both fixed, and the fix is **two units because one run user cannot serve both halves**:
  `push-db-dumps.service` → `storage-push-db-dumps.sh` runs **as `svc-backup`** (docker group, owns
  `/srv/dumps`), dumps every Postgres in `storage_push_db_dumps_pg`, gzip-tests it and fails on an empty
  dump; `push-db-dumps-push.service` → `storage-push-db-dumps-push.sh` runs **as root**, asserts the
  target really is the `nas.kogler.si:/tank/data` mount, copies with owner/group preservation off and
  then confirms a fresh file exists on the far side. The timer arms the push unit, which
  `Requires=`/`After=` the producer, so a failed dump cannot be papered over by pushing yesterday's file.
  No `--delete` — retention belongs to sanoid, not to a copy job.

  **Why the push half is root and not `svc-backup`, since it looks like a privilege regression:** the
  export maps root to `anonuid=1005` (`media`), and the target directory is `drwxr-xr-x media:media`,
  so `media` is the only identity the export accepts writes from. Running the push as `svc-backup` was
  tried first and measured: `rsync [receiver] mkstemp … Permission denied (13)`. Least-privilege and
  this export's identity model are in genuine conflict; the resolution is to make only the half that
  needs the docker socket unprivileged, and to say so in both unit files so nobody "harmonises" them
  back into one user and reintroduces the failure.
- `push-services` — it ran `docker exec forgejo` / `docker exec n8n`, and **neither container exists on
  oldsrv** (`group_vars/vps.yml` owns both). Removed. Skipping the missing containers so it could exit 0
  was the available shortcut and is exactly the fake-green this repo forbids, so the leg went away.
- `push-face-thumbs` — same class: its source does not exist on oldsrv, which runs only the immich **ml**
  leg; the thumb tree is on the VPS (measured 1.2 MB). Removed, and this table's "Location" cell for face
  thumbnails — which said oldsrv — corrected.

**The asymmetry worth more than the three fixes:** nas exports `/tank/data`, `/bulk/media` and
`/bulk/data/immich-thumbs` each to a single `/32` — **oldsrv's own address, and nothing else**
(the export lines are in `roles/storage/templates/exports.j2`; the address itself is in
[network-addresses-generated.md](network-addresses-generated.md)). The VPS cannot push to the NAS over NFS
at all today, which is why its `db-backup` dumps (Postgres for Authentik/Forgejo/Immich/Zipline/LiteLLM,
plus the forgejo archive and n8n sqlite that used to be this unit's payload) sit as a single copy on a
single disk. Closing **HD-191** is what makes those legs real; editing these units again is not.


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
   (⚠ today the oldsrv push exits 23 on `chown` and the VPS has no push at all — **HD-468** / **HD-191**)
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

## Postgres major upgrades (HD-1100) — what the 16 → 18 legs actually need

Measured 2026-10-08 from the VPS runner, read-only, against the live clusters. This is the input
that replaced my assumptions; every number below came off the boxes, not off a wiki.

**In scope:** the five VPS sidecars — `authentik-postgres`, `forgejo-db`, `litellm-db`,
`onlyoffice-postgres`, `zipline-db` — plus `lan-litellm-db` on oldsrv.

**Status read-back (the fleet truth, re-derive before trusting it):** `postgres:18.6-alpine` —
`litellm-db`, `authentik-postgres`. `postgres:16.15-alpine` — `forgejo-db`, `zipline-db`,
`onlyoffice-postgres`, `lan-litellm-db` (held by owner ruling until the two completed legs were
proven, which they were). `immich-postgres` is 14.19 on an upstream composite and is not in this
migration at all. Check with:
`for c in authentik-postgres forgejo-db litellm-db onlyoffice-postgres zipline-db; do docker inspect -f
"{{.Config.Image}}" $c; done` on the VPS, and `lan-litellm-db` on oldsrv.

At the time of the pre-flight all six were `16.15-alpine` (`server_version_num=160015`), with app
data totalling **362 MB** fleet-wide. Nothing exceeds 1 GB, so
each window is dominated by procedure overhead, not data: `pg_dump -Fc` of the largest cluster
(authentik, 171 MB app DB) took **1.80 s**, `pg_restore --list` 0.49 s / 1 819 TOC entries.
Restore-side wall time was **not** measured and is normally 2–5× the dump — still minutes.

**Out of scope, and it is not a 16 → 18 hop:** `immich-postgres` is **14.19** on an immich-owned
composite (`14-vectorchord0.4.3-pgvectors0.2.0`) that ships PG 14 only, with **`vchord/0.4.3` and
`vector/0.8.1` live in the schema** (`face_index`, `clip_index` use `USING vchordrq`). Those two are
the only out-of-tree extensions in the fleet and their PG 18 availability is **unverified**; the
composite also runs `data_checksums=on`, which rules out `pg_upgrade --link` there anyway. immich
moves when upstream ships a composite, not when we bump a pin.

### Four traps, each of which breaks a leg written the obvious way

1. **Collation, the one that fails silently.** All six clusters are libc `en_US.utf8`
   (`datcollate=en_US.utf8`, provider = default/libc). **PG 18 `initdb` defaults to ICU.** A new
   18 cluster created with defaults restores the same rows with different sort semantics — wrong
   `ORDER BY`, different index ordering, no error. The templates now pin
   `POSTGRES_INITDB_ARGS: "--locale=en_US.utf8 --locale-provider=libc"` on all seven Postgres
   services (landed first, before any pin moves; harmless on 16 and ignored on a non-empty datadir).
   Verified against a scratch `postgres:18.6-alpine`: `datcollate=en_US.utf8` ✓. `--locale-provider`
   has existed since 15, which is why landing it early costs nothing.
2. **There is no `postgres` role anywhere.** Every cluster's superuser is the **service name**
   (`-U authentik`, `-U forgejo`, …), so any command copy-pasted as `-U postgres` fails with a
   confusing auth error — that is exactly how a first probe of these clusters came back empty.
3. **A per-database dump silently drops cluster roles.** `pg_dump -Fc` carries no roles;
   `forgejo-db` has a **`metabase_ro`** role created outside compose env. Run
   `pg_dumpall --roles-only -U <svc>` first and re-apply it into the new cluster before the data
   restore, or owners and grants vanish.
4. **`onlyoffice-postgres` is in no dump target.** `db-backup` covers DB01 `authentik-postgres`,
   DB02 `forgejo-db`, DB03 `immich-postgres`, DB04 `litellm-db`, DB05 `zipline-db` — and ONLYOFFICE
   keeps its datadir in a **named volume** (`onlyoffice-docs_onlyoffice-pgdata`), not under
   `/srv/docker/*`, so both the backup config and any checklist that derives targets from
   `/srv/docker` miss it. Its compose comment calls that state "REGENERABLE" (HD-230); that is a
   reason to move fast, not a reason to migrate blind — dump it by hand first.

### One leg, in order (do one cluster per window)

```
SVC=<service> C=<db container> U=<svc user>            # NOT postgres — see trap 2
docker exec $C pg_dumpall -U $U --roles-only > /root/pg18/$SVC/roles.sql
docker exec $C pg_dump -Fc -U $U -d $U        > /root/pg18/$SVC/data.dump     # ~2 s at this size
pg_restore --list /root/pg18/$SVC/data.dump | wc -l                          # prove the dump is readable
# record pre-migration counts (tables + row counts for the 3 largest tables) to /root/pg18/$SVC/pre.txt
docker compose -f /opt/$SVC/docker-compose.yml stop <app> && docker compose -f /opt/$SVC/docker-compose.yml stop db
mv /srv/docker/$SVC/postgres /srv/docker/$SVC/postgres.16-$(date +%Y%m%d)     # named volume: RENAME it, never rm
mkdir -p /srv/docker/$SVC/postgres && chown 70:70 "$_" && chmod 700 "$_"        # MUST be empty: a nested
                                                                              #   mountpoint left by an earlier
                                                                              #   shape makes initdb abort
# flip <var> to 18.6-alpine, converge THIS service only — initdb runs with the pinned libc locale
docker compose -f /opt/$SVC/docker-compose.yml up -d db                        # wait: healthy
docker exec -i $C psql -U $U -d $U < $W/roles.sql                              # trap 3: roles first (STDIN)
docker exec -i $C pg_restore -U $U -d $U --no-owner < $W/data.dump             # STDIN: rootfs is read-only
# re-run the counts into post.txt and DIFF against pre.txt, then start the app and test it FOR REAL
```

Rollback is deliberately boring: the `.16-<date>` datadir is still on disk, so flip the pin back and
move the directory back. Keep it until the next snapshot cycle proves the new cluster. Verify after
each leg that `db-backup` still dumps that cluster (it addresses services by container name, so it
survives a name-preserving leg — but "survives" has to be read back, not assumed), and re-run the
restore spot-check the way the Forgejo dump was proven (130 tables against production's 130).

### What PG 18 actually requires (three things, all measured 2026-10-08 on the litellm leg)

1. **Pin `PGDATA`.** The 18 images default it to the version-specific `/var/lib/postgresql/18/docker` and their
   entrypoint refuses to start when the cluster sits elsewhere. `PGDATA: /var/lib/postgresql/data` in the DB env
   keeps ONE mount shape for 16 and 18.
2. **Do NOT use the upstream parent mount on this fleet.** It needs the entrypoint to create `/var/lib/postgresql/18`
   as root inside the container, but our DB services run `cap_drop: ALL` (adds: CHOWN, DAC_READ_SEARCH, FOWNER,
   SETUID, SETGID — **no `CAP_DAC_OVERRIDE`**), so writing the uid-70 `0700` bind dir fails: `mkdir: can't create
   directory '/var/lib/postgresql/18/': Permission denied`. A bind target conditional in the template is therefore
   wrong; if `pg_data_mount` ever reappears, it is stale.
3. **Move dumps over STDIN, not `docker cp`.** The DB containers are `read_only: true`, so `docker cp f C:/f` fails
   with `container rootfs is marked read-only` — the restore then dies on a missing file *after* the datadir swap.
   `docker exec -i C pg_restore -U <svc> -d <db> --no-owner < dump` (and `psql -f -` for roles) works; `/tmp` is a
   tmpfs and writable if a file is genuinely needed.

Expected, not drift: `pg_roles` goes **15 → 17** because PG 18 adds two default roles (`pg_checkpoint`,
`pg_maintain`), and an anonymous volume appears at `/var/lib/postgresql` because the image declares it. Verify the
leg with `pg_controldata /var/lib/postgresql/data` (the directory argument is required — without it the command
prints nothing useful), `datcollate=en_US.utf8`, pre/post table counts, and a `pg_dump --list` TOC count that
matches the pre-migration dump. Both authorized legs closed 2026-10-08 on `18.6-alpine` - litellm: 83 tables, 189
`_prisma_migrations` rows, TOC 457 in / 457 out, readiness `{"db":"connected"}`; authentik (fleet SSO): 230
tables, 827 indexes, 60 sequences, `core_user`=5 / `core_group`=4 / `core_token`=2 identical before and after,
live `200`, login flow `200`, worker error-free with tasks completing.

The acceptance read that actually works is `pg_controldata -D /var/lib/postgresql/data` ->
`pg_control version number: 1800`. Grep it case-insensitively: the neighbouring line says `Catalog version
number`, so `grep "catalog version"` matches nothing and a green cluster then looks like a failed one (it cost
me a false alarm on this leg).
**Sequencing by blast radius:** `litellm-db` → `onlyoffice-postgres` (+ the RabbitMQ 3.13 → 4.3
question in the same window, while ONLYOFFICE is already down) → `forgejo-db` → `zipline-db` →
`lan-litellm-db` on oldsrv → **`authentik-postgres` last**, because it is the fleet's SSO and every
other leg depends on it.
