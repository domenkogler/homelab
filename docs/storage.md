---
title: ZFS Storage Layout & Properties
role: ssot
domain: deployment
cross_cutting: true
status: active
tags: [storage, zfs, datasets, backup, media, nfs]
---
# ZFS Storage Layout & Properties

> **Role:** Single source of truth (cross-cutting) — ZFS dataset tree, per-dataset properties, snapshot/replication policy,
> NFS exports, nightly push jobs, Kopia scope, capacity budget, and the oldsrv rebuild-from-NAS runbook.
> **Links to:** `hardware-nas.md`, `backup.md`, `services.md`, `deployment-compose.md`, `deployment-ansible.md`, `observability.md`
> **Linked from:** `deployment.md`, `index.md`

---

## Principles

1. **Config lives in Git, secrets in 1Password, media is redownloadable.** Only **data** gets backed up.
2. **"Data" = everything that persists and is not Git / 1Password / re-pullable** — user files, DB dumps,
   service state (Forgejo, n8n), Immich originals and face thumbnails, **the VictoriaMetrics/VictoriaLogs
   observability stores (HD-341/342 — now Kopia-backed)**, Docker images, packages, model weights/ML
   model weights, and the media library are deliberately **not** backup targets.
3. **Live data is local.** DBs and service runtime state live on the host's NVMe/SSD — never on NFS.
   The NAS holds **backup artifacts** (dumps, state pushes). **OpenCloud user files + Immich originals live
   on the live Hetzner Box (CIFS/WebDAV — **SB-Data** `FSN1-BX2190`, Falkenstein, DE)**, not the NAS (HD-135) — the NAS keeps only ZFS snapshots/replicas
   of the box-facing datasets where retained.
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
    ├── services/        nightly state pushes (Forgejo dump, n8n sqlite, …)
    └── db-dumps/        tiredofit/db-backup output (push from oldsrv)   hourly+ snapshots, syncoid

bulk   (6 TB RAIDZ2 — WD Red + 3× Toshiba P300, consumer disks)  → MIXED ROLE
├── media/               ACTIVE *arr library + downloads (one dataset = hardlinks) — NOT backed up
│   ├── media/
│   │   ├── movies/
│   │   ├── tv/
│   │   └── ~~music/~~ *(music library is primary on the Hetzner Storage Box for Navidrome on the VPS — see Navidrome/store note below)*
│   └── downloads/       transient scratch (hardlink-import → media/, then prune)
│       ├── incomplete/{usenet,torrent}
│       └── complete/{movies,tv,music}   # TRaSH per-category (SABnzbd / qBittorrent)
├── data/                syncoid replicas of tank/data/* — same names, same snapshot schedules
│   ├── services/
│   └── db-dumps/
└── immich-thumbs/       face thumbnails, nightly rsync ← oldsrv — daily(7) snapshots, no syncoid send

oldsrv — two local disks (Kopia → Hetzner Storage Box backup, NAS-independent)
├── 960 EVO 500 GB (ext4) — OS/system only: `/`, `/var`, `/opt` — regenerable, no churn
└── 970 EVO 1 TB (ZFS pool "nvme") — ALL local data (immich dataset kept — immich-ml reads thumbs local):
    ├── nvme/docker-layers   /var/lib/docker         images/layers — re-pullable
    ├── nvme/docker          /srv/docker — per-service datasets (services; DBs/Immich moved to VPS — HD-135)
    │   └── nvme/docker/immich  /srv/docker/immich   thumbs read by immich-ml (kept, HD-151)
    ├── nvme/models          /srv/models             re-pullable, no backup  (TSDB moved to VPS — HD-135)
    └── nvme/dumps           /srv/dumps              Kopia source → push → tank/data/db-dumps
nas — MX300 525 GB (ext4) — OS/boot only; `tank`/`bulk` imported via ZFS cachefile
```
> **Superseded plans:** earlier `tank/important`, `tank/media`, `tank/downloads` and `tank/data`-with-media
> layouts. Media moved to its own dataset on the `bulk` pool; `tank` is now reserved for user data only.
> **Tank topology locked: MIRROR (owner decision, HD-207)** — raidz1 rejected even with
> OpenZFS 2.3+ RAIDZ expansion (mirror wins resilver/self-healing/random-I/O at 2× 4 TB). Growth = a new
> second mirror pair (contributes its full size) or replace-in-place autoexpand; never `zpool attach` a
> larger disk onto the existing pair (smallest-member cap). Detail: [`hardware-nas.md`](hardware-nas.md).

---

## Per-Dataset ZFS Properties

All datasets: `xattr=sa`, `acltype=posixacl` (NFS needs both), `atime=off`, `normalization=formD` (default).
No native encryption by default (homelab threat model; re-evaluate only if it changes).

| Dataset | recordsize | compression | Snapshots (sanoid) | syncoid → `bulk`? | Backed up off-site (Kopia)? |
|---------|-----------|-------------|--------------------|-------------------|-----------------------------|
| `tank/data/services` | 128K | zstd | hourly(24)+daily(7)+weekly(4)+monthly(3) | yes | yes (state dirs on oldsrv) |
| `tank/data/db-dumps` | 128K | zstd | hourly(24)+daily(7)+weekly(4)+monthly(3) | yes | yes (local scratch via Kopia) |
| `bulk/media` | 1M | lz4 | **none** | **no** | **no** — redownloadable |
| `bulk/data/*` | inherit | same as source | same as source (retained on the replica) | — (target) | — |
| `bulk/data/immich-thumbs` | 128K | lz4 | daily(7) | **no** (pushed, not sent) | yes |
| `nvme/docker/immich` (oldsrv) | 128K | lz4 | none | **no** | no — regenerable thumbs; immich-ml reads directly |

> **TRIM (HD-151):** `tank/data/immich`, `tank/data/documents`, `bulk/data/immich`,
> `bulk/data/documents`, `nvme/tsdb` and `nvme/docker/postgres` were removed from the `storage` role
> create-set — originals/user-files live on the live Hetzner Box, so the NAS-local retained archives added
> no recovery coverage (the Box + Kopia is the recovery path). `bulk/data/immich-thumbs` and
> `nvme/docker/immich` are **kept** — still written today.

Rationale: `recordsize=1M` matches large sequential photo/video files; `128K` is the sensible default for
services/dumps. Media and photos are already compressed by their codecs → `lz4` (cheap, tiny gain);
SQL dumps compress well → `zstd`. Snapshots of unbacked media are pure churn. Replication granularity
follows the snapshot cadence (≈ hourly), bounded by DB dump frequency (daily restore point) — worst
case a homelab loses <24 h of DB changes, acceptable.

---

## Snapshot & Replication (sanoid / syncoid)

- **sanoid** on nas snapshots `tank/data/*` (and `bulk/data/*` replicas + `bulk/data/immich-thumbs`).
  `bulk/media` is excluded from sanoid entirely.
- **syncoid** replicates `tank/data/* → bulk/data/*` (incremental `zfs send | zfs recv`). Timer checks
  every 15 min, sends only when a new source snapshot exists — effectively ≈ hourly for services/db-dumps.
- Replica datasets retain **independent** snapshot history on the `bulk` pool (protects against source
  deletion/error propagation; the replica is a rollback target of its own).
- `bulk/data/immich-thumbs` and `bulk/media` are **push targets** — no syncoid definition.
- Managed by **systemd timers** (`sanoid.timer`, `syncoid.timer`) — journaling, randomized schedules,
  failure tracking. Not raw cron.

---

## File-Version UI (per-file restore)

> **Post-HD-151:** the NAS `tank/data/documents` dataset is **gone** (trimmed HD-151) — OpenCloud user
> files live entirely on the live Hetzner Box, so per-file versioning is OpenCloud's native mechanism below;
> there is no NAS ZFS shadow-copy long tail anymore.

- **Family today:** OpenCloud's built-in per-file versions (`REV.*` in `.oc-nodes/`) + Trash — keep its
  revision retention short; retention is purely box-side now (config in the OpenCloud service, not ZFS).
- **Admin today:** cockpit-zfs (nas) for the remaining datasets + `.zfs/snapshot/*` + `zfs rollback`/`receive` (whole-tree or per-file copy out of a snapshot) where a dataset is retained.
- **Future:** OpenCloud FR [opencloud-eu/opencloud#1702](https://github.com/opencloud-eu/opencloud/issues/1702)
  would expose box-side snapshots in OpenCloud's version panel; don't plan around it (open, no ETA).

---

## NFS Exports (nas → oldsrv)

Three exports (one per pool + the face-thumbs push target — mounts can't span pools):

| Export | Mount (oldsrv) | Purpose |
|--------|----------------|---------|
| `tank/data` | `/mnt/nas/data` | user data: db dumps, service-state copies, archived datasets. **Immich originals + OpenCloud user files do NOT live here** — they are on the live Hetzner Box (CIFS/WebDAV) via storage templates (HD-135); no S3/MinIO |
| `bulk/media` | `/mnt/nas/media` | *arr library + downloads (Jellyfin, Sonarr/Radarr/Lidarr, SABnzbd, qBittorrent, Bazarr) |
| `bulk/data/immich-thumbs` | `/mnt/nas/thumbs` | face-thumbnail push target (nightly rsync from oldsrv) |

- Ownership uid/gid **`storage_uid`/`storage_gid` = 1005 (`media`)** — the neutral shared-data owner (HD-51/HD-94/HD-131), NOT domen/1000; matches *arr `PUID/PGID`, Jellyfin/OpenCloud `user:` and the Samba force user/group; NFS `root_squash` on.
- fstab mounts via Ansible (`storage` role). Hardlinks only ever cross paths **within** `bulk/media` — one dataset, one filesystem ✓.
- **The `storage` role applies NFS exports on-change only** — the `Reload NFS exports` handler (`exportfs -ra`) is `notify`-driven by the `Render /etc/exports` template task, so an **idempotent converge (file unchanged) never re-asserts the live nfsd export table**. If a live export is dropped for any reason (e.g. an earlier state where it was absent), subsequent converges won't restore it while `/etc/exports` is already correct — a client then errors `Stale file handle` on that automount. Recovery: `sudo /usr/sbin/exportfs -ra` on the NAS to re-apply (then clear the client's stale handle; runbook in [deployment-manual.md §Phase 2](../deployment-manual.md)). Robustness option: make exports ensure-present each run rather than notify-on-change.
- **SMB/Samba is implemented (HD-131 D4)** on the NAS via the `storage` role — its own section below, since
  it exposes a DIFFERENT tree than the NFS exports above and answers to different credentials.

---

## Samba (SMB) shares on the NAS

`roles/storage/tasks/samba.yml` + `templates/smb.conf.j2`, rendered on **nas** only. Three kinds of share,
the two shared ones force-owned by the neutral **`media`** account (`force user`/`force group`, uid/gid
1005 via `storage_user`/`storage_group`) so files land `media`-owned and stay usable by the arrs:

| Share | Path (nas) | Also visible on oldsrv as | `valid users` | Purpose |
|-------|------------|---------------------------|---------------|---------|
| `\\nas\media` | `/tank/data/shared` | `/mnt/nas/data/shared` | `@media` (any family account) | family shared tree (HD-131) |
| `\\nas\music` | `/bulk/media/media/music` | `/mnt/nas/media/media/music` | `shared` only | **the Lidarr rootFolder** — a laptop drops finished albums where the arr scans, no follow-up move (HD-362, added 2026-10-07) |
| `\\nas\<user>` | `/tank/data/users/<user>` | — | `<user>` | per-user private drive, NO force user (own uid = the isolation) |

**How a client addresses these shares (HD-1097, 2026-10-07).** `nas.kogler.si` answers on the LAN plane
and DHCP delivers the `kogler.si` suffix, so `\\nas\media` mounts over Wi-Fi as well as over cable.
Before that the zone carried no `nas` record at all and the UNC worked only through the NetBIOS/LLMNR
broadcast fallback — wired mounted, the same laptop on Wi-Fi did not, while mounting at the NAS's Home
address (SSOT row `nas` in [network-addresses-generated.md](network-addresses-generated.md)) mounted on
both. Keep that split as the diagnostic: **IP mounts and the name does not ⇒ resolution, not Samba**
— read the DNS answer before touching the share, the accounts or the firewall. Mechanism and the
decision not to paper over it with a `hosts` file:
[network-dns.md](network-dns.md) §Local Name Resolution & mDNS.

⚠ **Samba resolves these directives by NAME, not by id.** `force user = 1005` and
`valid users = @1005` parse fine, load fine, and resolve to NOTHING: authentication succeeds and
the **tree connect** then fails — `NT_STATUS_ACCESS_DENIED`, or `NT_STATUS_NO_SUCH_USER` when it is
the force-owner that is unresolvable. Both forms shipped until 2026-10-07, so `media` and `music`
had **never** been mountable by anyone; nothing noticed because no Samba account existed to
authenticate with either (measured in the matrix below). `storage_user`/`storage_group` carry the
names, and samba.yml asserts they still resolve to `storage_uid`/`storage_gid` — because the
failure mode is a client-side "wrong password", not a red converge.

### Accounts: local, and the repo is the SSOT

`passdb backend = tdbsam`. One **unix account + one Samba password per entry in
`storage_samba_users`** (`host_vars/nas.kogler.si.yml`): the converge creates the unix user, makes
its private tree owned by that user, and writes the password from 1Password `smb-<name>_login`
with `smbpasswd -a -s`. The member types that username+password at mount time; nothing federates
it. Live set (2026-10-07): `domen` (personal drive + `media`) and `shared` (a service account —
`drive: false`, no login shell — which is the credential for `\\nas\music`).

Three properties of this shape are deliberate, and each has a live lesson behind it:

- **No external dependency on the auth path.** Mounting a drive from the sofa touches the LAN and
  the NAS only. The design that used to sit here — Samba pulling auth from an Authentik LDAP
  outpost on the VPS (D7/HD-132/HD-360) — is **retired 2026-10-07**, for two independent measured
  reasons: (1) it made a family drive depend on the VPS, its outpost, its outpost *token* and the
  WG S2S tunnel (and that tunnel's `:3389` publish refused TCP from both `nas` and `oldsrv` when
  probed), and (2) it could never have worked — Samba answers a Windows NTLM challenge with
  `MD4(UTF-16LE(password))`, which an ldapsam backend reads out of the directory's
  `sambaNTPassword`, while Authentik stores PBKDF2 and its LDAP provider/outpost ship **no Samba
  attribute at all** (measured on 2026.5.6: zero `samba` matches in the server package and in the
  `/ldap` outpost binary; the only LDAP property mappings are `DN to User Path`, `Name`, `mail`).
  A user's portal password is therefore *not* a Samba credential, anywhere in this fleet. See
  [storage-rejected.md](storage-rejected.md).
- **Who can mount is a repo edit, not a directory sync.** The retired
  `sync-authentik-users.sh` glue (D5/HD-131) used to own this by reading the Authentik `family`
  group every hour. It is deleted, and so is the `include = /etc/samba/share-*.conf` drop-in hook it
  appended: the per-user share sections now come from the template. Its teardown tasks stop a unit
  that had never completed a run — `op` is not installed on the NAS, so it exited **127 on all 823
  runs since 2026-09-03** while the timer looked `active` (HD-1092, closed by the retirement).
- **Rotation needs one extra word.** A passdb write is a target-side act, so rotating the vault item
  changes nothing on the NAS by itself (CONVENTIONS §2 rotation propagation). Rotate the item, then
  converge with `-e storage_samba_password_force=<name>`. Without that flag the password task only
  fires when the account is absent from `pdbedit -L`, which is what keeps a routine converge from
  resetting a member's password on every run.
- ⚠ **`smbpasswd -a -s` exits 0 while writing nothing, and its stdin contract differs by case**
  (Samba 4.22.10 / Debian 13, measured on a throwaway account in all three combinations):
  a **new** entry reads `NEW`, `REENTER` — two identical lines, prints `Added user x.`, mounts.
  An **existing** entry reads `OLD`, `NEW`, `REENTER` — two lines leave it "Unable to get new
  password", **rc 0**, and the entry keeps the old hash. So the task removes the entry first and
  always takes the create path (one code path, not two), then proves the write by mounting
  `\\nas\media` over SMB with the value it just wrote — a green task is not evidence a client can
  authenticate. Re-adding can hand the account a new RID/SID; harmless while isolation is POSIX.

- **Proving it works is a tree connect, not a listing.** `smbclient -L` succeeds anonymously on this
  host, so it proves Samba is *serving* and nothing about auth. The honest probe (run it as a matrix,
  because a right answer on one share hides a wrong one on another — that is how the numeric-id bug
  survived):

  ```bash
  # on the NAS: creds go in through stdin so no password lands in argv (CONVENTIONS §6 never-print)
  printf '%s' "$PASS" | sudo tee /root/.c >/dev/null   # written as [global]/username/password
  sudo smbclient //localhost/<share> -A /root/.c -c 'ls' && echo OK
  ```
  The 2026-10-07 result, with `storage_samba_users = [domen, shared]`:

  | account | `media` | `music` | `domen` (private) |
  |---|---|---|---|
  | `domen` | ✅ | ⛔ by design | ✅ |
  | `shared` | ✅ | ✅ (its share) | ⛔ isolation |

  On the NAS itself: `sudo pdbedit -L` lists the accounts and `sudo testparm -s | grep -iE 'passdb|valid
  users|force '` shows what is rendered — read `testparm`, never the template, when a share misbehaves
  (and note `testparm` needs root here because it reports on the running config).
- **Why the `music` share exists**: the `bulk/media` export names the oldsrv Home address as its **only** client
  (`/etc/exports` is IaC-rendered; addresses live in [network-addresses-generated.md](network-addresses-generated.md)), so before
  it nothing Windows-facing could reach the library at all — `\\nas\media` points
  at a different pool. A manual add used to mean "copy to the share, then a privileged `mv` on oldsrv".
- ✅ **OpenCloud no longer needs anything the retired glue did.** Its step 4 had best-effort pre-seeded an
  OpenCloud account per family member with the `opencloud-service_api` service account, so that item and
  `authentik-nas_api` now have **no consumer** and are measured absent from the vault (`op item list`,
  134 items, 2026-10-07). OpenCloud JIT-provisions OIDC users on first login — **the owner logged into
  `file.kogler.si` the same day**, which closes the leg HD-149 registered as never observed. What was NOT
  measured is the account list itself: with no service-account item left there is no API seat to read it
  from, so an account-visibility audit would need a freshly minted Graph consumer.
- **Scoped converge:** `--tags samba` (or `storage,samba`) works only because BOTH halves of the HD-468 tag
  rule are in place — the `include_tasks: samba.yml` line carries the tag *and* every task inside does.
  Verified 2026-10-07 by measuring the opposite: with neither, the run printed `ok=24 changed=0 failed=0`
  and executed only `always`-tagged guards. A share change applied that way is a no-op that reports success.
  (The per-user private-tree task was one of the untagged ones until this change.)

---

## Nightly Push Jobs (oldsrv → nas)

| Job | Source (oldsrv) | Target (nas) | Method |
|-----|-----------------|--------------|--------|
| DB dumps | `/srv/dumps` — produced here by `push-db-dumps.service` → `storage-push-db-dumps.sh` (`pg_dumpall` per container in `storage_push_db_dumps_pg`), as `svc-backup` | `tank/data/db-dumps` — pushed by `push-db-dumps-push.service` (the timer's chain head), **as root**: the export maps root to `anonuid=1005`, which is the only identity it accepts writes from | rsync `-a --no-owner --no-group`, no `--delete`; preservation is not optional on this export, see [backup.md](backup.md) §What the 2026-09-28 sweep found |

**There used to be two more rows here.** `push-services` (Forgejo/n8n state) and `push-face-thumbs` were
removed 2026-09-28 (**HD-468**): both named payloads that live on the **VPS**, not on oldsrv, so neither
could ever exit 0 where it was installed. What the VPS should do instead, and why it cannot do it by NFS
to the NAS, is in [backup.md](backup.md) — the sweep section — and **HD-191**.

Key properties: dumps are written **locally first** (Kopia snapshots the local dir) and then pushed —
Kopia never reads NAS mounts, so off-site backup survives a dead NAS. All three jobs are systemd timers
deployed by the Ansible `storage` role.

---

## Kopia Policy (oldsrv agent → Hetzner Storage Box **SB-Backup** `HEL1-BX186`, Helsinki — off-site)

**Sources (all local, none on NAS):**
- `/srv/dumps` (SQL dump scratch)
- service state dirs (`/var/lib/forgejo-dump`, n8n backups, …)
- Immich face thumbnails (`thumbs/`)
- configs: `/opt/*` compose dirs, systemd units, HA config (/ etc — plus Git for the repo itself)

**Excluded:** docker named volumes (raw), downloaded model weights (GGUF/HuggingFace, re-pullable), Immich-ML weights,
`/mnt/nas/*` mounts entirely (NAS independence), `bulk/media` (not backed up by design).
> **Observability TSDB (VictoriaMetrics/VictoriaLogs) is Kopia-BACKED** (HD-341/342) — the old
> "Prometheus/Loki TSDB regenerable, not backed up" doctrine was reversed by the owner; VM/VL volumes
> are host binds under `/srv/docker/victoria-*/data`, snapshotted by the VPS kopia client.

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
| microSD (128 GB) | pi | ext4 | HA primary + RaspberryMatic + Technitium secondary + `traefik-ha` edge — lean, no ZFS, no backup surface |

```
970 EVO 1 TB → ZFS pool "nvme" (single-disk; every dataset is NAS-backed or regenerable, no mirror needed).
   Device path = SSOT var `storage_nvme_data_by_id` (host_vars/oldsrv.kogler.si.yml, HD-128/KOPS-057);
   automation only creates the pool on a fresh build and a fail-loud guard blocks it while the placeholder remains.
   ⚠ The 970 EVO still carries old Windows **NTFS partitions** from its pre-homelab life — if
   `zpool create` refuses on existing signatures at the Phase-3 playbook run, wipe them first
   (`wipefs -a` on that disk only; OS disk untouched).
├── nvme/docker-layers       /var/lib/docker        128K lz4   no snapshots (images re-pullable)
├── nvme/docker              /srv/docker (container, canmount=off)
│   ├── nvme/docker/immich   /srv/docker/immich     128K lz4   thumbs read by immich-ml (kept, HD-151)
│   └── nvme/docker/services /srv/docker/services   128K zstd  remaining local service state (post-HD-135 the public apps/DBs run on the VPS — oldsrv keeps the LAN core: DNS, signal-cli, media stack state; dozzle moved to VPS per HD-135b)
├── nvme/models              /srv/models 128K off   no snapshots, no backup (ollama + immich-ml weights)  (TSDB moved to VPS — HD-135)
└── nvme/dumps               /srv/dumps  128K zstd  db-backup scratch → Kopia + push → tank/data/db-dumps
```

- **Snapshots:** none on `nvme/*` (`storage_sanoid` covers the NAS pools only) — oldsrv-local state is
  protected by the nightly push jobs + Kopia instead (rollback-before-migrations convenience is traded
  for simplicity; the pool mirrors the NAS backup surface, it does not extend coverage).
- **Bind mounts, not named volumes** for stateful services: each service dir maps 1:1 to a dataset and
gives backup jobs/Kopia clean host paths (see `deployment-compose.md` → Volume Strategy).
- **Capacity budget:** keep `nvme` < 80% full (ZFS fragmentation). ~1 TB fits comfortably: thumbs+encoded ~150–300 GB over 5 yr, docker layers ~50–100 GB, models ~60–150 GB. (TSDB ~20–40 GB is on the VPS NVMe, not this pool — HD-135.)
- Docker stays on overlay2 over `nvme/docker-layers` (auto-snapshot off on that dataset).

### Pi (HA node) — `/opt/<svc>`, no ZFS

The Pi is a Docker node too (HA primary + RaspberryMatic + Technitium secondary + `traefik-ha` edge), but
its data is **tiny and already covered** — configs in Git, everything else re-syncs or regenerates, so it
adds **no backup surface** (no datasets, no Kopia policy). No ZFS: microSD + 4 GB RAM, and every byte is
already mirrored by the Pi→standby sync.

> **MicroSD wear is minimised separately** (HA recorder + Docker/OS logs), see
> [`observability.md`](observability.md) → *Pi SD-card wear strategy*: recorder is **trimmed, not disabled**
> (keeps Logbook / Energy-Dashboard LTS / history_stats); Pi logs are **streamed to VictoriaLogs** with only a tiny
> bounded Docker-log buffer (`local`, 10m×2); `/var/log` + journald run on **tmpfs/RAM**.

**Pi filesystem layout on microSD (ext4, single partition):**

```
Pi microSD (ext4 — 128 GB, no ZFS, no backup surface)
├── /                    ext4 (raspi.debian.net image, regenerable)
├── /var/log             tmpfs (RAM; `journald Storage=volatile`, OS logs lost on reboot → VictoriaLogs retains them)
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
`bulk`; per-pool, see `observability.md`). When `bulk` hits ~80%, offload `bulk/media` → a future 4 TB NVMe
(`hardware-spark.md`) — the planned media growth path. `tank` data stays put (mirror is the best disks).

---

## Service ↔ Storage Placement (VPS era) — which service lives on which storage

> **Decision (HD-135):** the public stack lives on the VPS; storage is split across three tiers
> by performance and access pattern. This is the authoritative placement table for the VPS-era layout.
> Keep it in sync with `backup.md` and `services-vps.md`.

| Tier | Medium | Latency | Holds | Services consuming it |
|------|--------|---------|-------|----------------------|
| **Local SSD** | VPS 512 GB NVMe (`/srv/docker/*`) | fast | DBs, thumbnails, caches, container runtime state, Linux root | authentik, opencloud (metadata), immich (DB+thumbs), forgejo, grafana, n8n, kopia, db-backup — **hot, random-I/O, synchronous** |
| **Cold/bulk tier** | Hetzner Storage Box **live** (`u653411`, CIFS `//u653411.your-storagebox.de/backup`) | slow (CIFS over internet) | big write-once / rarely-read / regenerable-but-bulk files | **Immich originals + encoded-video**, **OpenCloud user files (WebDAV)**, family SMB drives |
| **Local backup tier** | NAS ZFS `tank`/`bulk` + local oldSrv NVMe | LAN | snapshots, dumps, service-state pushes, media library | *arr stack (media), VPS→NAS push timers, Kopia scratch |

**Rule of thumb:** *hot/random/synchronous* on local SSD; *bulk/sequential/cold* on the live Box; *media + local backup* on the NAS.

**Music: NAS master + a Box serving copy (Navidrome on the VPS) — ruled 2026-10-07, HD-1088.** The FLAC **master** is
the Lidarr library on the NAS: `bulk/media/media/music` (Lidarr root `/media/music` — measured, empty today). The
Hetzner Storage Box **`music/`** is the **serving copy** Navidrome reads through its VPS-side CIFS mount
(`/mnt/storagebox/music` → `/music`, `rw`). ⚠ **What the previous version of this paragraph claimed had no mount
behind it:** it named the Box the *primary* and had Lidarr "copy-import" onto it, but `roles/cifs/tasks/main.yml`
asserts the Box mount onto the **VPS only** and neither oldsrv nor the NAS has one — so no `music → Box` leg exists
anywhere (the Box's `music/` has been empty since the mount went up). The leg is owed by **HD-1088**; until it lands,
only files the owner places on the Box by hand reach Navidrome.

Two consequences worth stating where the layout is read: **(a)** a push must carry the mountpoint guard and
read-back that `vps-state-push.sh` carries, and any `--delete` must be bounded (`--max-delete`) — a silent dead mount
on a *serving* tree means Navidrome serves an empty library while the timer reports green; **(b)** **neither copy is a
backup** — Kopia's remote is the *backup* box (`kopia_sftp_host`, a different server from the live Box) and `bulk` is
in the media "redownloadable, not backed up" tier, so a bad delete can reach both. That is acceptable for
usenet/torrent media and much less so for Soulseek FLAC, which is not reliably re-fetchable: the retention call is
HD-1088's, not a footnote here.

---

## VPS Storage Layout (netcup RS 2000 G12 — no ZFS)

> **Decision (HD-135):** the VPS uses **no ZFS** — the 512 GB NVMe is a single ext4 root disk
> (netcup default) and the live Hetzner Box is **CIFS**, not a block device, so ZFS-on-the-VPS is **rejected**.
> Recovery is app-level (OpenCloud `REV.*` versioning + Kopia → backup Box), not filesystem-snapshot-based.
> The three-tier placement table above is the authoritative decision; this layout documents the concrete paths.

```
netcup RS 2000 G12 (VPS) — 16 GB RAM, 512 GB NVMe (ext4, single root disk)
├── / (ext4, root)                    Debian + Docker CE — no ZFS, no btrfs
├── /srv/docker/<svc>/                per-app data (bind mounts — hot, random-I/O)
│   ├── authentik/   PostgreSQL + Redis + media
│   ├── immich/      Postgres + Valkey + upload/thumbs (NOT originals)
│   ├── opencloud/   OpenCloud instance + config + metadata
│   ├── forgejo/     Git repos
│   ├── ...          (full list = group_vars/vps.yml docker_services)
│   └── *.db         SQLite/state for other services (db-backup, n8n, …)
└── /mnt/storagebox/                 live Hetzner Box — CIFS (cold/bulk tier)
    ├── immich/      Immich originals + encoded-video (storage template)
    ├── opencloud/   OpenCloud user files (WebDAV)
    └── ...          (any other bulk, write-once, rarely-read data)
```

**What lives where:**

| Path | Backing | Recovery | Notes |
|------|---------|-------------------|-------|
| `/srv/docker/<svc>/*` | VPS NVMe (ext4) | Kopia → backup Box | Hot DBs, caches, live data. Restore = re-run Ansible + Kopia snapshot restore |
| `/mnt/storagebox/**` | live Hetzner Box (CIFS) | Kopia → backup Box | Cold/bulk: Immich originals, OpenCloud files. CIFS-mounted by the `cifs` role (`livebox_cifs`) |
| `/var/lib/docker` | VPS NVMe (ext4) | none (images re-pullable) | Overlay2, no bind mount |

**Why no ZFS here:** single NVMe disk with no redundancy to gain; CIFS (the actual bulk tier) is not a block
protocol ZFS can use; snapshot/rollback is covered by Kopia + OpenCloud versioning at the app layer. This also
means **`zfs`/`zpool` does not run anywhere in the VPS-era layout** — the only ZFS pools are `tank`/`bulk` (nas)
and `nvme` (oldsrv), documented above.

---

## Immich Hybrid Storage (VPS: app+DB+thumbs local, originals+encoded on the live Box, ML on oldsrv)

> **Decision (HD-135):** Immich runs **on the VPS**. Originals and encoded-video move to the
> **live Hetzner Box** (cold tier); thumbnails + Postgres DB stay on VPS NVMe (hot); ML offloaded to the
> oldsrv GPU. The older "originals on NAS/MinIO" plan is superseded — the live Box is CIFS, **not S3/MinIO**.

- **VPS NVMe (`/srv/docker/immich/`)**: Postgres DB + Valkey + `upload/thumbs` (small previews, hot random reads on every UI render).
- **Live Box (CIFS)**: **originals** (`library/`) **and encoded-video** (`encoded-video/`) — sequential reads, big files, safe off NVMe.
  - Enabled via Immich **storage template** (a DB/UI setting at deploy, not compose env): thumbnails stay under `upload/thumbs`; originals + encoded-video are templated out to the CIFS mount.
  - **The template question, answered (owner onboarding 2026-09-25): YES, default `{{y}}/{{y}}-{{MM}}-{{dd}}/{{filename}}`.** It is the mechanism this layout depends on — with it OFF, uploads simply
    **stay in `upload/`** (UUID-ish flat store) and nothing is filed into the date tree, so the Box layout and any "read the library without Immich" hope both fail. The default is upstream's, it is
    browsable, rsync/Kopia-friendly, and **reversible**: change the template and re-run the migration job.
  - ⚠ **Verify it actually saved.** Upstream shipped an onboarding bug where the storage-template choice was silently not persisted (immich #19395, fixed by PR #19405) — after onboarding, re-open
    Administration → Settings → Storage Template and read it back rather than trusting the wizard.
  - ⚠ **New uploads only.** Existing assets move when the **Storage Template Migration** job runs (Administration → Jobs). On the CIFS mount that is a mass rename: run it with nothing uploading,
    expect it to be slow, and expect one large Kopia snapshot delta.
  - ⏳ Durable gap: this lives in Immich's DB while everything around it is rendered, so a rebuilt Immich comes back with the template OFF. Encoding it (Immich's admin system-config API, not
    compose env) is the fix; the wizard click is a one-time bootstrap, not the SSOT.
- **ML on oldsrv GPU** (`IMMICH_MACHINE_LEARNING_URL` over WG): embeddings/face data in Postgres → covered by DB dumps.
- **Face thumbnail files** are backed up (Kopia → backup Box) because regenerating them means a full facial-recognition re-scan (expensive). Plain thumbnails and encoded-video are regenerable on demand (Immich reconstruct job), so only the large cold files move to the Box, not an extra backup copy.

---

## Rebuild-from-NAS Runbook (oldsrv total loss, **no off-site**)

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
7. Point Immich/OpenCloud at the live Box data — **no copy**: originals/user files are already there (the
   live Hetzner Box is the cold tier, HD-135). Media library is untouched (Jellyfin/*arr resume from the
   same `/mnt/nas/media`).

Also covers `nas` boot-SSD death: reinstall (preseed), `zpool import tank bulk`, re-run Ansible — no
image backup of the MX300 needed; pools are self-describing. `nas` total-loss behaves differently:
services keep running (their state is on oldsrv); Immich photos + OpenCloud files are on the **live
Hetzner Box** (cold tier), so they remain reachable — only the NAS-local archive datasets are
unavailable until the NAS is rebuilt (accepted, see `backup.md`).

---

## Related

- [Storage Review Queue](storage-review.md)
- [Storage Rejected / Dropped (decision log)](storage-rejected.md)