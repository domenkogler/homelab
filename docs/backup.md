---
title: Backup & Disaster Recovery
role: detail
domain: deployment
cross_cutting: true
status: active
sensitivity: infra
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
- **Scope:** ONLY `tank/data/*` (services, db-dumps) — retained archives; the live Box + Kopia is the
  recovery path for everything else. The media library
  (`bulk/media`) is intentionally **NOT snapshotted or replicated** — it is redownloadable, see
  [`services.md`](services.md) / [`storage.md`](storage.md)
- Snapshot schedule: data datasets hourly (24), daily (7), weekly (4), monthly (3); photo/dump datasets
  stay hourly (photos change by upload, dumps daily); snapshotting unbacked media is pure churn
- Replication: syncoid timer checks every 15 min, sends when a new source snapshot exists (≈ hourly)
- Managed via **sanoid/syncoid**, run by **systemd timers** (sanoid.timer + syncoid.timer) — not raw cron; gives journaling, randomized schedules, and failure tracking

- **This layer is a name-only layer on the `tank` side: the two source datasets carry no payload, and the
  invariant that decides it is a mount, not a policy.** `tank/data` is `canmount=off` with
  `mountpoint=none`, and `tank/data/services` / `tank/data/db-dumps` inherit that `mountpoint=none`, so
  **neither child is ever mounted** — `zfs get mounted` reads `no` and the paths do not exist in the
  namespace (`/tank/data/services` is simply absent). sanoid and syncoid name datasets, so both run green,
  take their hourly snapshots and send their incrementals against a dataset whose `refer` sits at the
  empty-dataset floor (`96K`) and whose snapshots all report `used=0B`: a snapshot of a dataset nothing can
  write is a snapshot of nothing, and the stream is metadata-sized. Two consequences, both measured:
  **the state-push half has no writer at all** — nothing in the tree, no unit and no script, targets
  `tank/data/services`, and the directory has never existed on either side of the NFS mount; **the dump-push
  half does fire, but lands in the wrong dataset** — `storage-push-db-dumps.sh` writes
  `/mnt/nas/data/db-dumps`, the export of `/tank/data` resolves that path into the **parent `tank`
  filesystem** (`findmnt -T` names `tank`, whose own `refer` carries the ~14 MB of dumps), while
  `tank/data/db-dumps` stays at `96K`. So the nightly dumps are protected by **Kopia** from the oldsrv
  scratch dir, not by this layer, and `tank` itself has no sanoid policy at all. **The rule to carry
  forward:** a dataset a backup tool names must also be mounted and have a writer; the same shape as a
  reserved dump slot that no dump takes — a policy row that points at an unmounted dataset renders green,
  fires on schedule and protects nothing. The destination mirror is the same story in miniature:
  `bulk/data/services` is unmounted too and its snapshot history is `used=0B` all the way down.

### Layer 2: Kopia (Off-Site — Application-Level, NAS-independent)

Configs, DB dumps, service state, face thumbnails, and VPS/oldsrv local state go off-site via Kopia.
The oldsrv agent's sources are local paths, so that coverage keeps working while the NAS is fully down;
the one exception is ruled and named — the **NAS music master**, snapshotted by its own guarded line, so a
NAS outage costs that snapshot alone.
Kopia targets the **backup Box over SSH/SFTP (port 23)** — the Hetzner Storage Box supports **SSH/SFTP
only, NOT S3**. One source is NAS-resident (the music master) and is snapshotted by its own guarded line;
see §What Gets Backed Up and [`storage.md`](storage.md) §Kopia Policy.

The **oldsrv agent runs containerized**: it connects to `kopia-server` on the VPS over
**HTTPS on the WG S2S tunnel** — **kopia 0.23.x rejects `http://`**, so the server serves a
persisted self-signed cert and the agent pins its stable SHA-256 fingerprint from the
`kopia-server_fingerprint` item. A cert that is regenerated per start makes every agent pin wrong at the
next restart — persist it, pin the fingerprint. The item is `NOT_AUTO_ROTATABLE`: replacing the
certificate means re-seeding it and re-rendering every agent, or every connect fails on trust.

**Rotating the certificate** (the item cannot be `--rotate`d; the cert IS the value):

1. Move `tls.crt`, `tls.key`, `tls-sha256` out of `/srv/docker/kopia-server/config/` and restart
   `kopia-server` — its boot script is the generator, and it writes `tls-sha256` next to the pair.
   **Check the SAN after it regenerates**: the boot command reads
   `subjectAltName=IP:${KOPIA_SERVER_ADDR_HOST:-127.0.0.1}` at container RUNTIME, while the value is
   rendered into the project `.env`, which this compose never lists under `env_file:` — so the fallback
   fires and the pair comes back with a **loopback-only** SAN while the agent dials `wg_s2s_vps.ip`.
   Mint the pair with `CN=kopia-server` + `subjectAltName=IP:<wg_s2s_vps.ip>,IP:127.0.0.1`, 4096-bit,
   3650 days, and write `tls-sha256` from the cert (the same shape the boot script intends).
2. Converge the VPS `docker_services` leg with `kopia_server`/`kopia_fingerprint` tags and
   `-e docker_services_scope=kopia-server`: `kopia-fingerprint-sync.yml` reads the LIVE cert into the
   item — that task IS the propagation, so a hand-write to the item is a divergence, not a rotation.
3. Re-render the agent (`--tags docker_services,kopia-agent -e docker_services_scope=kopia-agent`
   on oldsrv) and then **move the cached `/srv/docker/kopia-agent/config/repository.config` aside**.
   The agent's boot script connects only when that file is absent, so without this step the container
   comes back on the NEW pin in its environment and the OLD pin in its cache, and every snapshot fails.
   The re-connect needs the repo master password, which the compose already renders from
   `kopia_password` — no human hand. ⛔ rotating the fingerprint never touches `kopia_password`.
4. Prove both directions with a scratch `--config-file` (never the agent's own):
   `kopia repository connect server` with the live pin must exit **0**, with the superseded pin
   **non-zero**; then `kopia repository status`, `kopia snapshot list` and one `kopia ls <root>` must
   answer. ⛔ never read that connect line back: kopia prints the server URL **with userinfo**, so a
   `docker logs kopia-agent` after a reconnect is a secret read — exit codes and subcommand verdicts
   only. Server
port 51515 is bound **only to the VPS tunnel address**
(`wg_s2s_vps.ip`, never 0.0.0.0; loopback-only until the router peer key is provisioned), so reach stays
scoped by the S2S ACL. Agent sources are oldsrv-local, read-only: `/opt/*` configs, `/srv/dumps` scratch
(`lan-litellm-db` dumps, retention 14 — populated, and the push leg lands nightly), the signal-cli state volume,
and a `/srv/docker/immich/upload` line that reads an **empty tree**: Immich runs on the VPS, so that source has
held 0 files and every snapshot of it is an identical empty tree — the thumbs row in §What Gets Backed Up names
the live location. Plus **the NAS music
master** (`/mnt/nas/media/media/music`), the one NAS-resident source, snapshotted by its own line behind a
mount-and-emptiness guard so a NAS outage costs that one snapshot and nothing else.

> **A source the agent cannot read is snapshotted as whatever it CAN read.** The image runs as root and
> `cap_drop: ALL` leaves `CapEff=0`; without `CAP_DAC_OVERRIDE` the DAC check binds root too, so a `drwx------`
> directory owned by a service uid — a named volume's state dir, e.g. the signal gateway store — answers
> `Permission denied`. kopia records those errors **inside** the snapshot, uploads what the one world-readable
> file amounts to, and can still exit 0, so the loop's failure branch stays quiet and retention happily keeps the
> near-empty copy. The agent therefore carries `cap_add: [DAC_OVERRIDE]`: widening reads, across mounts that are
> all `:ro`, never writes. The same asymmetry is why the source manifest is proved by a restore — see
> §Restore drill (yearly), never by `kopia snapshot list`.

> ✅ **Status: the oldsrv `kopia-agent` connects over HTTPS + fingerprint pin and takes snapshots**
> (the `/opt/*` configs, the dump scratch, the pinned signal volume and the NAS music master; retention labels
> send them offsite to the backup Box). The
> fingerprint is seeded by a **VPS-only** task (`kopia-fingerprint-sync.yml`) — an agent-side task cannot
> produce it.
>
> **Kopia's server-auth model needs TWO things to agree:** the client's `user@host` identity must exist
> BOTH in the htpasswd (`--htpasswd-file` = the allowed `user@hostname` entries) AND as a repo user
> (`kopia server users add`) whose password equals the **repo master password** (what the client passes to
> `connect --password`). A non-repo-password user is `access denied` **at the session stage even with a
> matching htpasswd entry** — the confusing part is that the earlier stages succeed. The kopia-server boot
> script writes both htpasswd entries (server admin + `kopia_agent_user`) and idempotently
> provisions/re-seeds the repo user (`kopia server users add/set` with `KOPIA_PASSWORD`). **Compose
> interpolation gotcha in the same file:** the command block must be `$$`-escaped, or single-`$`
> interpolation mangles the credential at parse time.

> **The connect line carries the credential, so the agent's log carries it too.** kopia 0.23 carries
> server Basic auth in the URL **userinfo** (`--server-username`/`--server-password` were dropped
> upstream), and `kopia repository connect server` echoes the URL it was handed. The agent's first-connect
> line therefore prints `kopia-server-internal_api.credential` in plaintext into the container log, which
> `docker logs` replays and the log tail ships into VictoriaLogs, where it sits for the retention window
> (90 d) — and the shipped lines carry **no host label**, so which box emitted a line is not answerable
> from the store. Anyone who can read the logs reads the credential (CONVENTIONS §3, Secret output
> hygiene). Two consequences: the connect output has to be scrubbed before it reaches a log, and rotating
> the item **re-connects the agent**, because the credential is also cached in its `repository.config` —
> a re-render alone leaves an agent authenticating with the retired value.

> **Kopia-server first-run gate:** the server's first-run bootstrap (`kopia repository create sftp`) must
> be gated on **`repository.config`** (kopia's repo-connection file) — NOT `config.json` (an unrelated
> technitium zone file). Gate on `/app/config/repository.config` (create only when absent) and the server
> starts against the existing repo (maintenance/GC run normally); a gate on the wrong file re-runs `create`
> against an existing repo — `found existing data in storage location`, `set -e` exit, crash-loop.

```
tiredofit/db-backup (local scratch) →  Kopia agent (VPS + oldsrv) →  Hetzner Storage Box (backup) SSH/SFTP :23
   + service state + face thumbs       (encrypted, dedup)       (far-DC: Helsinki/Falkenstein — SB-Backup HEL1-BX186)
```

> **Two Hetzner Storage Boxes.** The **live** box (nearest DC) serves
> Immich originals **+ encoded-video** and the family SMB/WebDAV drives (CIFS, **not S3**); the **backup** box (far DC) hosts the Kopia repo.
> Single-provider risk is accepted.
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
| **Scope** | User data (`tank/data/*` → `bulk/data/*`) | Configs, DB dumps, service state, face thumbnails, **live Box originals + encoded-video (CIFS)**, the **NAS music master** |
| **Speed** | Block-level incremental (very fast) | File-level with dedup |
| **Encryption** | Optional (ZFS native) | Client-side (before leaving) |
| **Target** | nas `bulk` pool (local) | Hetzner Storage Box (backup), far DC (off-site) |
| **Recovery** | Instant `zfs rollback` / `zfs recv` back | Kopia restore from cloud |

---

## What Gets Backed Up

| Data | Location | Method | Target |
|------|----------|--------|--------|
| PostgreSQL DBs — **Authentik, Forgejo, Immich** (`db-backup` `DB01–03`), **LiteLLM runtime** (`DB04` — `STORE_MODEL_IN_DB` ⇒ the DB holds keys/models/spend), **Zipline** (`DB05`) and **ONLYOFFICE** (`DB06`) — all on the **VPS** | VPS NVMe | daily dumps in the `db-backup` volume, **mirrored off-box every night by `vps-state-push` (§VPS state push)**. The `→ tank/data/db-dumps (ZFS)` push and a Kopia snapshot of the dump volume **do not exist** | Hetzner Storage Box `vps-state/vps.kogler.si/dumps` (rsync, **not encrypted at rest**); Kopia still unattached |
| **`lan-litellm-db` on oldsrv** (the LAN inference gateway's Postgres) | oldsrv | **dump job exists**: `storage-push-db-dumps.sh` runs `pg_dumpall` inside `lan-litellm-db`, gzip-tests the dump, refuses to ship an empty one, and rsyncs with owner/group preservation OFF — the export is `root_squash,anonuid=1005`, so `rsync -a` could only ever die on `chown` (rc 23). Local retention 14, no `--delete` on the NAS side (sanoid owns retention) | oldsrv `/srv/dumps` → `tank/data/db-dumps` (ZFS) |
| **Matrix server state + signing identity + media store** — tuwunel: RocksDB room/user state, the **server signing key** + key-notary data, the E2EE key-backup, `media/` and `archive/` | VPS NVMe `/srv/docker/matrix` (single bind → `/var/lib/tuwunel`) | **Nothing backs it up today** — the path is not in any snapshot because there is no VPS-side Kopia client (§VPS-side coverage gap). Note there is **no separate key file to archive**: `database_path` is the data dir and probing it finds no `*.pem`/keystore file, so the signing identity lives inside the same RocksDB store as the rooms | *(pending the VPS client; then one row covers all of it)* — see §Matrix: what one path buys and what it does not |
| **RustDesk server keypair + client registrations** — `/srv/docker/rustdesk-server/data` | VPS NVMe | **Primary restore is 1Password `rustdesk_login`, not a snapshot** (the s6 unit re-seeds `/data/id_ed25519*` from `KEY_PUB`/`KEY_PRIV` when absent, so wiping the dir + re-converging restores the identity and enrolled clients keep working). The snapshot only has to cover `db_v2.sqlite3` (client/peer registrations) — losing it re-prompts devices, it does not lock anyone out | 1P (identity) + Kopia once the VPS client exists (registrations) |
| **Qdrant** vector store (`/srv/docker/qdrant`) | VPS NVMe | **rebuildable cache** (docs/services-ai.md §5b) — snapshot/export via Qdrant REST `/snapshots` + Kopia-backed host bind; **not** a db-backup Postgres dump | `tank/data/services` (ZFS) + Hetzner Storage Box (Kopia) — *intended; same VPS-client caveat* |
| Docker Compose files / systemd units / configs | Git repo + host `/opt/*` (**VPS + oldsrv**) | Git (+ Kopia) | GitHub (the repo's only remote) / Hetzner Storage Box (backup) |
| Service state (Forgejo dump, n8n sqlite, **LiteLLM keys/spend — the litellm-db Postgres, dumped by `db-backup` `DB04`; `/srv/docker/litellm` keeps only misc app state**, **OpenClaw config/state** on the **VPS**; **AI harness (pi-dev + DSH) workspaces** (`/srv/docker/pi-dev/workspace`, `/srv/docker/dsh/workspace`); **Seerr config + `seerr.db`** on **oldsrv**; …) | VPS NVMe (edge/GitOps/AI tier) · oldsrv NVMe (*arr/LAN core) | VPS: `vps-state-push` mirrors the dumps, every `/opt/*/docker-compose.yml` + `.env` and the n8n sqlite trio to the Storage Box nightly (§VPS state push); oldsrv: Kopia + the dump push | `vps-state/…` on the Storage Box (rsync, unencrypted at rest) + `tank/data/services` (ZFS) and Hetzner Storage Box (backup) |
| **Zipline file payloads** (`/srv/docker/zipline/uploads` — datasource) | VPS NVMe | **Kopia-EXCLUDED by design**: anonymous dropzone drops self-destruct at ≤ 6h TTL (guestbin quota-bounded); private-account files are owner-managed | — *(ephemeral/regenerable-by-design — the observability-TSDB precedent)*; the metadata DB is dumped as `db-backup DB05` |
| Home Assistant configs | RPi 4 (+ standby on oldsrv) | Git + standby sync | repo / oldsrv (Kopia) |
| Router configs (`*.rsc`) | Git repo | Git + Kopia | Hetzner Storage Box (backup) |
| Immich **originals + encoded-video** (photos/videos) | **live Hetzner Box** (CIFS `//u653411.../backup`, VPS) | **live tier** | backed by **Kopia → backup Box** (off-site) **+ the Immich DB** (albums/faces/tags) |
| Immich **face thumbnails** | **VPS** NVMe `/srv/docker/immich/upload/thumbs` (measured 1.2 MB; immich-server/-postgres/-valkey all run there) — **not** oldsrv, which runs only the immich-ml leg and holds no user data | ⚠ **unbacked**: the VPS has no Kopia client and no push path (§VPS-side coverage gap) | `bulk/data/immich-thumbs` + Hetzner Storage Box (backup) |
| **Media library — movies/TV** | **nas `bulk/media`** | **NOT backed up** — no sanoid, no syncoid, no Kopia | redownloadable via usenet/torrents |
| **Music master (FLAC)** | **nas `bulk/media/media/music`** — a directory inside the `bulk/media` dataset, Lidarr root `/media/music` | **Kopia snapshot** by the oldsrv agent (its own guarded line: mount witness + non-empty floor, so a dead NFS mount can never prune the last good copy) **+** an rsync/SFTP serving push to the live Box | off-site Kopia repo (backup Box, encrypted) + the live Box `music/` serving copy — a Soulseek FLAC is not re-fetchable, so this tree is deliberately NOT part of the unbacked media tier |

> **Victoria observability:** the VictoriaMetrics (VM, 365d metrics) + VictoriaLogs (VL, 90d logs) volumes are **Kopia-backed**. They live on the **VPS NVMe** at `/srv/docker/victoria-metrics/data` + `/srv/docker/victoria-logs/data` (host binds). ⚠ **The snapshooting client for these — and for every other `/srv/docker` path on the VPS — does not exist yet: §VPS-side coverage gap. Until it does, "Kopia-backed" in this section is the policy, not the state.**

### VPS-side coverage gap

**What is true (probed read-only):**

- The VPS runs `kopia-server` — the **repository endpoint** that other hosts' agents push through (the
  repository itself is remote: `KOPIA_SFTP_*` in `/opt/kopia-server/docker-compose.yml`). oldsrv runs its
  own `kopia-agent` container, which is what makes the home-side coverage real.
- The VPS has **no backup client of its own**: no `kopia` binary, no client config (`/root/.config/kopia`
  absent), no `kopia-agent` container in the registry. Every "Kopia-backed" / "nightly push" claim in this
  file about a **VPS path** is therefore policy-ahead-of-state (CONVENTIONS §3 calls this out by name).
- **Not in any off-site snapshot:** nothing under `/srv/docker/*` (Matrix, Headscale, CrowdSec, n8n,
  OpenCloud, Grafana, docling model cache, …). The `db-backup` dump volume is mirrored nightly by
  `vps-state-push` (§VPS state push), but the intended `→ tank/data/db-dumps` push has never
  run and no Kopia snapshot of that volume exists.
- **What a VPS NVMe loss costs today, honestly:** every VPS-hosted Postgres (Authentik = the IdP, so
  SSO for the whole homelab; Forgejo = the Git state of the repos it holds — the homelab repo itself is not
  among them, its only remote is GitHub; Immich metadata; Zipline; LiteLLM keys/spend/models), the Matrix
  federation identity, Headscale
  (the tailnet control plane), CrowdSec decisions, n8n/OpenCloud/Grafana state. Configs and IaC survive
  (Git on GitHub), so the rebuild is mechanical — but the **data** is not covered.

**The fix is small and already precedented:** oldsrv's `kopia-agent` (include list = `/opt`,
`/srv/dumps`, `/srv/docker/immich/upload`, one docker volume, and the NAS music master over its NFS export) is the shape. A VPS-side agent needs
`/opt`, the `db-backup` dump volume and the `/srv/docker/*` service-state dirs. Until that lands, the
scope rows above stay written as *policy* — adding a Matrix or RustDesk row to an include list that has
no client to attach to would only make the doc more fiction.

Off-site coverage moves incrementally: a source joins an agent's include list as its host lands on the
plan. Until every source is declared, the live repository and the IaC include lists are two sources of
truth and are reconciled by hand — a row in this file is neither.

### VPS state push — what runs now

**The VPS's own state has ONE copy on ONE disk.** `vps-state-push.service` + `.timer` (installed by
the `docker_services` role on the VPS; daily 23:15 after db-backup's 20:01 fire, `Persistent=true`,
`Nice=10`/`IOSchedulingClass=idle` because this box serves production from 16 GB) moves it off the box
over the CIFS mount the `cifs` role maintains — the same transport the Immich originals tier uses, so
no second mechanism exists. Payload, in one rsync pass:

| what | source (measured, not assumed) | on the box |
|---|---|---|
| every Postgres dump db-backup keeps | `/var/lib/docker/volumes/db-backup_db-backups/_data` (1.4 GB, 319 files — root `du`, live-verified 2026-10-30) | `vps-state/vps.kogler.si/dumps/` |
| the declarative state of every service | `/opt/*/docker-compose.yml` + `/opt/*/.env` (41 files, 0.2 MiB) | `vps-state/vps.kogler.si/state/opt/` |
| n8n's database (runs `DB_TYPE: sqlite`, so it has **no dump path**) | `/srv/docker/n8n/data/database.sqlite*` | `state/n8n-sqlite/` |

* **The guard is the point.** If `/mnt/storagebox` is not a CIFS/SMB mount the unit exits **90**
  instead of rsyncing: a dead mount is an empty directory on the VPS's own disk, and the "off-box
  copy" would then be a same-disk copy that reports success — the self-pull class, same
  shape, different transport. The test accepts `cifs` from findmnt **or** `smb2` from statfs and
  reads the *innermost* entry of the mount stack — the box sits under an `autofs` layer, so a string
  equality on `findmnt --target` is not enough.
* **CIFS carries no unix symlinks.** db-backup marks each DB's newest dump with a `latest-*`
  symlink; mirroring them fails `Input/output error (5)` (rsync rc 23). The aliases are excluded
  and the unit rebuilds the index as a plain `dumps/LATEST.txt`.
* **Acceptance is read back, not inferred:** the expected bytes present through the mount, `zstd -t` of the
  newest dump inside the unit (exit 91 if that fails), and **a real restore** — the Forgejo dump
  into a scratch `postgres:16.15-alpine` gave **130 tables against production's 130**.
* **Restore recipe these dumps actually need** (they are written by pg_dump **18.3** against
  servers running **16.15**): drop `SET transaction_timeout = 0;` (a PG 18-only GUC — aborts a
  PG 16 restore at line 12) and the new `\restrict`/`\unrestrict` meta-commands, and `CREATE ROLE
  <dbuser>` before restoring, or every `OWNER TO` fails.
* **Still not covered:** Matrix/tuwunel (RocksDB state *and* the signing identity),
  Headscale, CrowdSec decisions, Qdrant, OpenCloud, Grafana, the **Forgejo git repos**, and any Immich
  original not yet on the Box. The rule is the **live Hetzner Box** for originals — what the `cifs` role
  mounts and [`storage.md`](storage.md) §Immich Hybrid Storage states — so an original sitting on VPS NVMe is
  misplaced rather than duplicated, and this push neither carries it nor needs to. ⏳ Residue to move, measured
  under root `du` (live-verified 2026-10-30): **295 MB / 36 files under `/srv/docker/immich/upload`**, which is
  NOT all originals — `backups/` 254 MB, `library/` 25 MB (the originals), `encoded-video/` 15 MB, `thumbs/`
  1.2 MB; `immich-server` mounts that one directory as `/data` and nothing else, so no path of the service
  reaches the CIFS mount today. The Immich storage-template migration job is what
  files them onto the CIFS mount. And this is rsync to a CIFS share, **not** the
  encrypted snapshot Kopia would give: the kopia-client gap above is unchanged.

**The slot-numbering rule.** `tiredofit/db-backup` builds one `dbbackup-NN` scheduler per configured
block but numbers those slots **sequentially from 01**, while each slot's job reads `DB{NN}_*`. A gap in
the numbering therefore leaves a slot reading a block that does not exist: it logs `No 'appropriate
database type' Entered!` on every fire and dumps **nothing**, while `docker ps` shows db-backup "Up" —
only a manual `backupNN-now` run says so. The rule: blocks are numbered **contiguously from DB01** and a
number is never reserved for a database that does not exist yet (a reserved number *is* a broken block).
The set is `DB01` authentik-postgres, `DB02` forgejo-db, `DB03` immich-postgres, `DB04` litellm-db,
`DB05` zipline-db, `DB06` onlyoffice-postgres — rendered contiguously on the box today, so **`DB07` is the
next free slot**. A payload that is not a database takes **no slot at all**: a file tree such as the music
master enters scope through an agent's include list, and giving it a `DB{NN}` block would be the reserved
number with no block — green container, no output. **The general rule:
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

> **Excluded — media + *arr scratch:** the movies/TV library and `downloads/` are partially or fully
> redownloadable via usenet/torrents, so they carry **no** sanoid snapshots, no syncoid and no Kopia.
> The single exception inside that dataset is **`media/music`** — the FLAC master, snapshotted by Kopia
> (see the table above), because a Soulseek FLAC is not re-fetchable the way a movie is. Splitting it out
> with sanoid is not available: it is a directory, not a dataset, and sanoid names datasets only
> (§The slot-numbering rule). Immich thumbs/encoded-video and ML weights are regenerable, also excluded
> (face thumbnails are the one exception — see above).

---

### The oldsrv dump-push identity split

The job is **two units because one run user cannot serve both halves**:

- `push-db-dumps.service` → `storage-push-db-dumps.sh` runs **as `svc-backup`** (docker group, owns
  `/srv/dumps`), dumps every Postgres in `storage_push_db_dumps_pg`, gzip-tests it and fails on an empty
  dump.
- `push-db-dumps-push.service` → `storage-push-db-dumps-push.sh` runs **as root**, asserts the target really
  is the `nas.kogler.si:/tank/data` mount, copies with owner/group preservation OFF and then confirms a fresh
  file exists on the far side.

The timer arms the push unit, which `Requires=`/`After=` the producer, so a failed dump cannot be papered
over by pushing yesterday's file. No `--delete` — retention belongs to sanoid, not to a copy job.

⚠ **The boot catch-up is where the mount assert bites, and the ordering is the fix.** The timer is
`Persistent=true`, so the run missed during an outage fires at activation — and at first activation
`findmnt -no SOURCE,FSTYPE -T /mnt/nas/data` holds only the `systemd-1 autofs` line, because `findmnt -T`
does not wake an `x-systemd.automount` trigger. The guard is right (that assertion is exactly what stops a
failed mount from becoming a quietly LOCAL "backup"), so the remedy is ordering, not weakening:
`RequiresMountsFor=/mnt/nas/data` (and/or `After=` on the `mnt-nas-data.automount` unit) so the mount is up
before the assert runs, with the `findmnt` re-read once after a single bounded touch of `$TARGET` so a
genuinely dead mount still fails loudly. Until that ordering lands, the scheduled nightly runs are fine and
the boot-adjacent catch-up — the run that follows an outage — is the one that fails.

⚠ **Preservation flags and the split are both forced by the export, not by taste.** `rsync -a` cannot chown
onto an export mounted `root_squash,anonuid=1005` (rc 23), and the target directory is
`drwxr-xr-x media:media`, so `media` — the anonid the export maps root to — is the only identity that
accepts writes. Running the push half as `svc-backup` answers `rsync [receiver] mkstemp … Permission denied
(13)`. Least-privilege and this export's identity model are in genuine conflict; the resolution is that only
the half needing the docker socket is unprivileged, and both unit files say so, so nobody "harmonises" them
back into one user.

**The asymmetry that bounds all of this:** nas exports `/tank/data`, `/bulk/media` and
`/bulk/data/immich-thumbs` each to a single `/32` — **oldsrv's own address, and nothing else**
(the export lines are in `roles/storage/templates/exports.j2`; the address itself is in
[network-addresses-generated.md](network-addresses-generated.md)). The VPS therefore **cannot push to the
NAS over NFS at all**, which is why its `db-backup` dumps (Postgres for Authentik/Forgejo/Immich/Zipline/
LiteLLM) and the n8n sqlite have no off-box path but `vps-state-push` (§VPS state push).


## VPS-side backup client

**OQ-15 — the VPS-side backup client — is answered.** The shape is **a `kopia-agent` container on the VPS**,
in oldsrv's agent shape: include list `/opt`, the
`db-backup` dump volume and the `/srv/docker/*` service-state dirs, pushing through the `kopia-server`
endpoint already on the box (the repository's own SFTP credential sits in
`/opt/kopia-server/docker-compose.yml`, so no new class of secret lands on an internet-facing host). It is
the client the "Kopia-backed" rows above already assume, and it is the only shape that reaches what no dump
carries — Matrix/tuwunel room state *and* the signing identity inside the same RocksDB store, Headscale,
CrowdSec, OpenCloud, Grafana, the Forgejo git repos.

Two bounds on it, both load-bearing:

- **A file-level snapshot of a live database directory is not a dump.** `db-backup` stays the restore path
  for the Postgres tier; the agent carries what a dump cannot.
- **The exclusions belong to the include list.** A new client inherits nothing, so the Zipline dropzone and
  the regenerable paths are re-declared here or the agent snapshots an anonymous dropzone.

Push-only coverage — no client on the VPS, an equivalent push of the dump volume to the Storage Box — is not
the shape: it is what already runs, so it settles nothing (every `/srv/docker/*` dir stays single-copy on
VPS NVMe and the Box target is unencrypted at rest), and its NAS leg cannot exist because nas exports
`/tank/data` to oldsrv's `/32` and nothing else. The rejected alternative is rowed in
[storage-rejected.md](storage-rejected.md).

**The sizes, measured before any include list was written** (root `du -sh` on the VPS, live-verified
2026-10-30; a non-root read under-reads `/opt` by the one directory it cannot enter, so these are root's numbers):

| include root | size | what dominates it |
|---|---|---|
| `/opt` | **497 MB** | `/opt/traefik` 459 MB (certificates + static), `/opt/technitium` 38 MB, the rest per-service config dirs |
| the `db-backup` dump volume (`db-backup_db-backups`) | **1.4 GB / 319 files** | the retained Postgres dumps `vps-state-push` also mirrors |
| `/srv/docker` | **3.6 GB** | `open-webui` 890 MB, `immich` 626 MB, `authentik` 551 MB, `victoria-metrics` 362 MB, `grafana` 269 MB, `kopia-server` 217 MB |

So the first pass is a ~4 GB push and every path the §What Gets Backed Up table calls "Kopia-backed" on this
host finally has a client to attach to. What the repository costs is measurable rather than guessed: the repo
holds **9238 blobs / 3.2 GB packed**, and the oldsrv agent's own nightly delta on a 1.4–1.5 GB `/opt` root is
**64–79 MB of new data per snapshot at 0 % compression** (most payloads — `.sql.gz`, media — arrive already
compressed, which is why the repo's overall compression reads 0.1 %). The only throughput number this repo has
measured is the **restore** direction over the same WG S2S path: 9.7 MB in 21 s (≈ 0.5 MB/s) for a store whose
chunks were not in the local cache, against 15.5 MB in 5 s (≈ 3 MB/s) for one partly cached — so a ~4 GB first
pass is an **hours** event at the cold end, which is why the client's first snapshot belongs in a window and not
in the timer's first night. What is still unmeasured is the push side of that path, and measuring it needs a
`repository connect server` carrying the credential in the URL userinfo — so it runs on the same window as the
`kopia-server-internal_api` rotation (§Layer 2: the connect line and the credential), never on a scratch command
line. Until the client exists,
every "Kopia-backed" line in this file that names a **VPS path** is policy, not state (§VPS-side coverage gap).

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
   (⚠ the VPS has no push of its own and no client — §VPS-side coverage gap)
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

> **Accepted residual risk:** the off-site Kopia repo is encrypted but not immutable — a
> ransomware attacker holding the Box credentials/key could reach the backup copy. Accepted for now;
> mitigation options if ever needed: Storage Box snapshot/versioning, or a second cold credential.
> Restore-drill discipline (yearly) is the current integrity check.

---

## Disaster Recovery

### Runbook — restore the non-GPU tier on a replacement VPS

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
3. Converge in role order — `bash scripts/ansible/ansible-run.sh playbooks/vps.yml --limit vps` (hardening
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
   device re-enrols** — the peer import/key backup is the only shortcut, so budget for the
   re-enrolment sweep rather than promising a flip.
6. Verify the two-sided gate before calling it restored (CONVENTIONS §3): `docker ps` roster equals the
   registry's enabled set with no restart loops; `sso`/`git` return 302; the observability dashboards
   resume; the RustDesk relay answers (services-vps.md row 8).
7. Fold what the restore actually cost — minutes, and which state was missing — back into the coverage
   rows of this file, not into a dated log. A gap discovered *during* a restore is a coverage finding,
   not an incident detail.

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
6. Schedule the next drill in the same sitting as the one you just ran, and record its result with a
   date. A drill with no recorded result is a drill that did not happen.

### Restore Drills
- **Frequency: Yearly.** The pass criterion is step 3 above: the payload reads, not the copy finished.
- **Legs, and what each one buys** (last drill 2026-10-30, live-verified on oldsrv: three NON-newest snapshots,
  restored into a scratch tmpfs path — never onto a live host bind):

  | leg | the snapshot restored | verdict |
  |---|---|---|
  | application dump | the `/mnt/src/dumps` weekly-3 snapshot (2026-10-18): 14 files / 8.3 MB, 2 s | ✅ every restored `.sql.gz` passes `gunzip -t` and carries 59 `CREATE TABLE` + 59 `COPY` blocks — a loadable `lan-litellm-db` dump, names spanning 2026-10-05 to 2026-10-18 |
  | file-level service state | one subtree (`technitium`) of the `/mnt/src/opt` weekly-3 snapshot: 928 files / 15.5 MB, 5 s | ✅ config and zone files present in the restored tree |
  | a pinned named volume | `/mnt/src/signal-cli-data` — the same source with and without the cap | ❌ without `CAP_DAC_OVERRIDE` the store's `drwx------` dirs are unreadable at snapshot time (§Layer 2), so a restore of that source yields **1 file / 46 B** where the live volume holds **144 files / 9.7 MB**. A/B on the same mount: 1 file without the cap, 144 with it. ✅ with the cap the source snapshots `files:144 dirs:11` with **no `errors:`** and restores 144 files / 9.7 MB in 21 s — `data/accounts.json` and the SQLite store present, so the pin is verified at the restore, not in the include list |

  The ❌ half is the reason this section exists: a `kopia snapshot list` that shows a source under a full
  retention label is a state that coexists with an unrecoverable service.
- **Legs a drill on oldsrv cannot exercise:** one `/srv/docker/<service>` dir — those paths are on the VPS and the
  VPS has no client, so §Runbook step 4.2 has no snapshot to restore from yet (§VPS-side coverage gap). Naming
  that is part of the drill result, not a footnote to it.

### Recovery Paths

| Scenario | Recovery Steps |
|----------|---------------|
| **Single service crashes** | Kopia restore that service's data from latest snapshot |
| **Single file deleted/corrupted** | ZFS rollback to snapshot before deletion (seconds) |
| **VPS fails (the non-GPU tier)** | Imperative runbook: §Runbook — restore the non-GPU tier on a replacement VPS. ⚠ Read §VPS-side coverage gap first: the VPS has no Kopia client, so this path rebuilds config from Git and recovers what `vps-state-push` mirrored to the Box (dumps, `/opt` compose + `.env`, the n8n sqlite) plus what the home side holds — everything else under `/srv/docker/*` dies with the disk |
| **oldsrv fails (Phase 1)** | Rebuild **from the NAS, no off-site** — runbook in [`storage.md`](storage.md): preseed reinstall → Ansible → mount NFS → restore DBs from dumps → unpack `tank/data/services` → copy thumbs back. ⚠ The dumps under `/mnt/nas/data/db-dumps` are the oldsrv-side ones (`lan-litellm-db`); the VPS-side dumps live on the Box under `vps-state/…` (§VPS state push) |
| **HA Pi fails** | Forward takeover to oldsrv standby (manual) — see [`smart-home-failover.md`](smart-home-failover.md); rebuild Pi as fresh peer, reverse-sync standby→Pi, flip VIP back |
| **nas fails** | Services keep running (state is on oldsrv); Immich photos + OpenCloud files are on the **live Hetzner Box** (cold tier) so they stay reachable — only NAS-local archive datasets are unavailable until rebuild. Pools are self-describing: reinstall from preseed, `zpool import tank bulk`, re-run Ansible |
| **Both nas pools lost** | Media: re-download. Data (`tank/data/*`): restore from `bulk` if it survived, else Storage Box (backup) via Kopia (slow — last resort) |
| **Router dies** | 1. Replace RB4011 2. Restore `.rsc` from Git 3. Adjust WAN MAC if needed |
| **Total house loss** | 1. VPS + Storage Box (backup) survive (off-site; NAS is lost with the house) 2. Rebuild from Git + Ansible 3. Restore data from Kopia (backup box) 4. Replace hardware |

---

## Family Access

- **Kopia master password:** 1Password (vault: `Homelab-ansible`)
- **1Password master password + recovery codes:** Paper in family safe
- **Family safe also contains:** Link to the Git repo (GitHub — its only remote)
- See [`deployment-secrets.md`](deployment-secrets.md)

---

## Open Questions

- **Kopia Web GUI vs CLI:** Web GUI is sufficient for now; CLI needs assessed at first restore drill
- **Bulk media off-site:** live + backup Hybrid Storage Boxes; bulk media library stays local-only on NAS (ZFS), only configs/DBs + Immich originals go off-site. Off-site copy via Kopia over SSH/SFTP (port 23); **no S3 / Object Storage** (Hetzner Storage Box is not S3 — handled via CIFS mount + Kopia over SSH).

## Postgres major upgrades — what the 16 → 18 legs need

Every number below came off the boxes, not off a wiki.

**In scope:** the five VPS sidecars — `authentik-postgres`, `forgejo-db`, `litellm-db`,
`onlyoffice-postgres`, `zipline-db` — plus `lan-litellm-db` on oldsrv.

**Status read-back (the fleet truth, re-derive before trusting it):** `postgres:18.6-alpine` —
`litellm-db`, `authentik-postgres`. `postgres:16.15-alpine` — `forgejo-db`, `zipline-db`,
`onlyoffice-postgres`, `lan-litellm-db`. `immich-postgres` is 14.19 on an upstream composite and is not in
this migration at all. Check with:
`for c in authentik-postgres forgejo-db litellm-db onlyoffice-postgres zipline-db; do docker inspect -f
"{{.Config.Image}}" $c; done` on the VPS, and `lan-litellm-db` on oldsrv.

Pre-flight measurement (`server_version_num=160015`): app data totals **362 MB** fleet-wide and nothing exceeds 1 GB, so
each window is dominated by procedure overhead, not data. `pg_dump -Fc` of the largest cluster
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
   `ORDER BY`, different index ordering, no error. The templates pin
   `POSTGRES_INITDB_ARGS: "--locale=en_US.utf8 --locale-provider=libc"` on all seven Postgres
   services (harmless on 16 and ignored on a non-empty datadir).
   A scratch `postgres:18.6-alpine` must read `datcollate=en_US.utf8` ✓. `--locale-provider`
   has existed since PG 15, which is why landing it early costs nothing.
2. **There is no `postgres` role anywhere.** Every cluster's superuser is the **service name**
   (`-U authentik`, `-U forgejo`, …), so any command copy-pasted as `-U postgres` fails with a
   confusing auth error.
3. **A per-database dump silently drops cluster roles.** `pg_dump -Fc` carries no roles;
   `forgejo-db` has a **`metabase_ro`** role created outside compose env. Run
   `pg_dumpall --roles-only -U <svc>` first and re-apply it into the new cluster before the data
   restore, or owners and grants vanish.
4. **`onlyoffice-postgres` is dumped, but its datadir is invisible to a `/srv/docker` checklist.**
   `db-backup` covers DB01 `authentik-postgres`, DB02 `forgejo-db`, DB03 `immich-postgres`,
   DB04 `litellm-db`, DB05 `zipline-db`, DB06 `onlyoffice-postgres` — and ONLYOFFICE keeps its
   datadir in a **named volume** (`onlyoffice-docs_onlyoffice-pgdata`), not under `/srv/docker/*`,
   so any checklist that derives targets from `/srv/docker` misses it. Its compose comment calls
   that state "REGENERABLE"; that is a reason to move fast, not a reason to migrate blind — take a
   fresh dump before the window.

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

Rollback is deliberately boring: the `.16-<date>` datadir stays on disk, so flip the pin back and
move the directory back. Keep it until the next snapshot cycle proves the new cluster. Verify after
each leg that `db-backup` still dumps that cluster (it addresses services by container name, so it
survives a name-preserving leg — but "survives" has to be read back, not assumed), and re-run the
restore spot-check: a real restore into a scratch `postgres:16.15-alpine`, table counts against
production (Forgejo: 130 against production's 130).

### What PG 18 actually requires (three things)

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
matches the pre-migration dump.

The acceptance read that actually works is `pg_controldata -D /var/lib/postgresql/data` ->
`pg_control version number: 1800`. Grep it case-insensitively: the neighbouring line says `Catalog version
number`, so `grep "catalog version"` matches nothing and a green cluster then looks like a failed one.
**Sequencing by blast radius:** `litellm-db` → `onlyoffice-postgres` (+ the RabbitMQ 3.13 → 4.3
question in the same window, while ONLYOFFICE is already down) → `forgejo-db` → `zipline-db` →
`lan-litellm-db` on oldsrv → **`authentik-postgres` last**, because it is the fleet's SSO and every
other leg depends on it.
