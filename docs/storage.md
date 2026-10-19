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
   observability stores (Kopia-backed)**, Docker images, packages, model weights/ML
   model weights, and the media library are deliberately **not** backup targets.
3. **Live data is local.** DBs and service runtime state live on the host's NVMe/SSD — never on NFS.
   The NAS holds **backup artifacts** (dumps, state pushes). **OpenCloud user files + Immich originals live
   on the live Hetzner Box (CIFS/WebDAV — **SB-Data** `FSN1-BX2190`, Falkenstein, DE)**, not the NAS — the NAS keeps only ZFS snapshots/replicas
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
├── media/               ACTIVE *arr library + downloads (one dataset = hardlinks) — NOT backed up, except its `media/music` tree (the FLAC master, Kopia scope; see §Kopia Policy)
│   ├── media/
│   │   ├── movies/
│   │   ├── tv/
│   │   └── music/       the FLAC MASTER — a directory inside this dataset, snapshotted by Kopia and pushed to the live Box (see §Kopia Policy, §Service ↔ Storage Placement)
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
    ├── nvme/docker          /srv/docker — per-service datasets (the public apps/DBs run on the VPS)
    │   └── nvme/docker/immich  /srv/docker/immich   thumbs read by immich-ml
    ├── nvme/models          /srv/models             re-pullable, no backup  (the TSDB is on the VPS NVMe)
    └── nvme/dumps           /srv/dumps              Kopia source → push → tank/data/db-dumps
nas — MX300 525 GB (ext4) — OS/boot only; `tank`/`bulk` imported via ZFS cachefile
```
> **`tank` is reserved for user data only**; media and downloads are `bulk` datasets. **Tank topology is
> MIRROR.** Growth = a new second mirror pair (contributes its full size) or replace-in-place autoexpand;
> never `zpool attach` a larger disk onto the existing pair (smallest-member cap).
> Detail: [`hardware-nas.md`](hardware-nas.md).

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


Rationale: `recordsize=1M` matches large sequential photo/video files; `128K` is the sensible default for
services/dumps. Media and photos are already compressed by their codecs → `lz4` (cheap, tiny gain);
SQL dumps compress well → `zstd`. Snapshots of unbacked media are pure churn. Replication granularity
follows the snapshot cadence (≈ hourly), bounded by DB dump frequency (daily restore point) — worst
case a homelab loses <24 h of DB changes, acceptable.

---

## Snapshot & Replication (sanoid / syncoid)

- **sanoid** on nas snapshots `tank/data/*` (and `bulk/data/*` replicas + `bulk/data/immich-thumbs`).
  `bulk/media` is excluded from sanoid entirely (`autosnap = no`), which is the fact to read back —
  `zfs list -t snapshot bulk/media` must stay empty.
- **The one part of `bulk/media` that IS backed up is the music master, and sanoid is not how.**
  `bulk/media/media/music` is a DIRECTORY inside the `bulk/media` dataset (TRaSH hardlinks require one
  filesystem), and sanoid names **datasets**: a row naming that path renders a valid config, sanoid exits
  0, and nothing is ever snapshotted — the reserved-slot class in [backup.md](backup.md) §The
  slot-numbering rule. Snapshotted `bulk/media` as a whole would instead snapshot the re-downloadable
  movies/TV tier and the `downloads/` scratch with it. The master therefore enters backup scope through
  the oldsrv Kopia agent's include list (§Kopia Policy), which works on paths; the movies/TV tier stays
  unbacked by design.
- **A policy snapshot is named `@autosnap_<date>_<time>_<tier>`** — `hourly`, `daily`, `weekly`,
  `monthly`. Grep `@hourly.` and a working sanoid reads as having produced nothing; the read that
  works is `zfs list -t snapshot | grep _hourly`.
- Cadence lives in the `storage_sanoid` map in `roles/storage/defaults/main.yml`. `frequently` is 0
  on every template, so the 5-minute timer fires are due-and-prune checks, not 5-minute snapshots.
- **The unit that runs sanoid is generated here** (the Debian `sanoid` package ships no unit file) and
  its `ExecStart` must name `/usr/sbin/sanoid`, where the package installs the binary. A wrong path
  fails the fire with `status=203/EXEC` before sanoid runs, which no idempotent converge can see.
  The package's `/etc/cron.d/sanoid` is not a backstop either: its command is guarded by
  `[ ! -d /run/systemd/system ]` and self-skips on any systemd boot, so **the timer is the only
  scheduler** and there is no dual scheduling to manage.
- **A snapshot story is proved by reads, not by the recap**: the last-fire result
  (`systemctl show sanoid.service -p Result -p ExecMainStatus`) plus fresh policy snapshots on the
  configured datasets. A green `failed=0` converge says nothing about either.
- **syncoid** replicates `tank/data/* → bulk/data/*` (incremental `zfs send | zfs recv`). Timer checks
  every 15 min, sends only when a new source snapshot exists — effectively ≈ hourly for services/db-dumps.
  ⏳ A send that never exits freezes this leg **and** retention: sanoid prints
  `deferring pruning of <snap> — <dataset> is currently in zfs send or receive`, so a stuck send shows
  up as a snapshot count that grows past the configured window (`hourly = 24` holding **43 on
  `tank/data/services` as of 2026-10-19** — measured per dataset in §Reading the activating state below; the "100" was prose)
  as a red unit. The read that separates the two causes is
  `sanoid --prune-snapshots --readonly --verbose` next to `systemctl status storage-syncoid.service`
  — a leg sitting in `activating` for days has not replicated since its start time.
- Replica datasets retain **independent** snapshot history on the `bulk` pool (protects against source
  deletion/error propagation; the replica is a rollback target of its own).
- `bulk/data/immich-thumbs` and `bulk/media` are **push targets** — no syncoid definition.
- Managed by **systemd timers** (`sanoid.timer`, `storage-syncoid.timer`) — journaling, randomized
  schedules, failure tracking. Not raw cron.

### Reading the activating state — sanoid and syncoid, measured 2026-10-19 (read-only)

Two causes were on the row: sanoid's retention, and a stuck `zfs receive`. **Neither explains the state on
the box tonight.** The reads, in the order that settles it:

| Read | Value |
|---|---|
| `systemctl cat sanoid.service` | `Type=oneshot`, `ExecStart=/usr/sbin/sanoid --cron` — the path the role generates |
| `systemctl show sanoid.service -p Result,ExecMainStatus` | `Result=success`, `ExecMainStatus=0`, last fire `2026-10-19 01:25:00`, `sanoid.timer` next fire 01:30 — a 5-minute cadence that is a prune/snapshot check, as this section says |
| `zfs list -t snapshot -o name \| grep -c _hourly$` | **134** policy snapshots, and the per-dataset counts are the honest ones: `tank/data/services` **43**, `tank/data/db-dumps` **24** (at window), and the same on the two `bulk/data/*` replicas — `sanoid.conf` gives `bulk/data/services` and `bulk/data/db-dumps` `use_template = data`, so the replica snapshots its own history by config, which is the "independent replica history" bullet above, not an accident |
| `systemctl show storage-syncoid.service` | `activating (start)` since **2026-10-18 06:45:04** (18 h 43 min at read time), `NRestarts=0`, `Job=3164`, `JobTimeoutUSec=infinity` — nothing will ever time this out |
| `systemctl status` cgroup | 5 tasks: `bash storage-syncoid.sh` → `syncoid --force-delete tank/data/services bulk/data/services` → the syncoid tee helper → `sh -c "zfs send -I tank/data/services@syncoid_nas_2026-10-08:21:00:08 tank/data/services@syncoid_nas_2026-10-18:06:45:05 \| mbuffer \| pv -p -t -e -r -b -s 23712 \| zfs receive -s -F bulk/data/services"` → **`pv`** |
| Is a receive running? | **No.** `zfs send`, `mbuffer` and `zfs receive` are absent from the process table and from the unit's cgroup; `zfs get receive_resume_token bulk/data/services` → empty |
| `cat /proc/<pv>/io`, twice 6 s apart | `rchar: 4980  wchar: 0  syscr: 10  syscw: 0` — identical both times; `State: R (running)`, unit CPU `18 h 41 min` against 18 h 43 min of wall clock |

**The cause is the progress pipe, not the replication.** `zfs receive` exited (which is why the destination
still reads `bulk/data/services used=140K`); `pv` was left writing into a pipe with no reader, and instead of
dying on the EPIPE it has been spinning in `R` at 100 % of one core since 06:45 — 0 bytes written, 0 write
syscalls completed, forever. `sh -c` waits for every pipeline member, so it never returns; `syncoid` never
returns; a `Type=oneshot` unit whose main process has not exited sits in `activating (start)` — and with
`JobTimeoutUSec=infinity` systemd will never end it. The row's "stuck `zfs receive`" and "sanoid defers
pruning" are both descriptions of a different night: what must be reaped is a **wedged `pv`**, and killing it
kills the whole unit's process tree.

The stream itself was never the problem: `pv -s 23712` says the incremental send was **23 KB**. Eight
`syncoid_*` snapshots exist, three of them on 2026-10-18 at 06:26 / 06:30 / 06:45 — the 15-minute timer
(`Persistent=true`) firing new attempts into a unit that had not finished, and `zfs list` shows the newest
`@autosnap_*_hourly` on **both** pools at 01:00, so snapshots kept running the whole time.

```bash
# the reads above, in one pass (read-only)
ssh nas 'systemctl show storage-syncoid.service -p ActiveState,SubState,ExecMainStartTimestamp,NRestarts,Job'
ssh nas 'systemctl show sanoid.service -p Result,ExecMainStatus,ExecMainStartTimestamp'
ssh nas 'sudo -n ps -o pid,ppid,stat,cmd -p $(systemctl show -p MainPID --value storage-syncoid.service)'
ssh nas 'sudo -n cat /proc/$(pgrep -f "pv -p -t -e -r -b")/io'      # unchanged across two reads = wedged
ssh nas 'zfs list -t snapshot -o name -s creation | grep "_hourly$" | awk -F"@" "{print \$1}" | sort | uniq -c'
```

⛔ **The reap is an owner act and is parked on HD-1107**: stopping the unit (`systemctl stop
storage-syncoid.service`, which SIGKILLs the wedged `pv` and its tree) and then letting the next timer fire is
a live act on the replication leg, and a `zfs receive -F` that ended without a clean finish should be observed
through one full cycle by whoever is awake for it. Nothing was signalled on the host from this pass.

---

## File-Version UI (per-file restore)

> OpenCloud user files live entirely on the live Hetzner Box, so per-file versioning is OpenCloud's native
> mechanism below — there is no NAS ZFS shadow-copy path.

- **Family:** OpenCloud's built-in per-file versions (`REV.*` in `.oc-nodes/`) + Trash — keep its
  revision retention short; retention is purely box-side (config in the OpenCloud service, not ZFS).
- **Admin:** cockpit-zfs (nas) for the remaining datasets + `.zfs/snapshot/*` + `zfs rollback`/`receive` (whole-tree or per-file copy out of a snapshot) where a dataset is retained.
- **Future:** OpenCloud FR [opencloud-eu/opencloud#1702](https://github.com/opencloud-eu/opencloud/issues/1702)
  would expose box-side snapshots in OpenCloud's version panel; don't plan around it (open, no ETA).

---

## NFS Exports (nas → oldsrv)

Three exports (one per pool + the face-thumbs push target — mounts can't span pools):

| Export | Mount (oldsrv) | Purpose |
|--------|----------------|---------|
| `tank/data` | `/mnt/nas/data` | user data: db dumps, service-state copies, archived datasets. **Immich originals + OpenCloud user files do NOT live here** — they are on the live Hetzner Box (CIFS/WebDAV) via storage templates; no S3/MinIO |
| `bulk/media` | `/mnt/nas/media` | *arr library + downloads (Jellyfin, Sonarr/Radarr/Lidarr, SABnzbd, qBittorrent, Bazarr) |
| `bulk/data/immich-thumbs` | `/mnt/nas/thumbs` | face-thumbnail push target (nightly rsync from oldsrv) |

- Ownership uid/gid **`storage_uid`/`storage_gid` = 1005 (`media`)** — the neutral shared-data owner, NOT domen/1000; matches *arr `PUID/PGID`, Jellyfin/OpenCloud `user:` and the Samba force user/group; NFS `root_squash` on.
- fstab mounts via Ansible (`storage` role). Hardlinks only ever cross paths **within** `bulk/media` — one dataset, one filesystem ✓.
- **The `storage` role applies NFS exports on-change only** — the `Reload NFS exports` handler (`exportfs -ra`) is `notify`-driven by the `Render /etc/exports` template task, so an **idempotent converge (file unchanged) never re-asserts the live nfsd export table**. If a live export is dropped for any reason, subsequent converges won't restore it while `/etc/exports` is already correct — a client then errors `Stale file handle` on that automount. Recovery: `sudo /usr/sbin/exportfs -ra` on the NAS to re-apply (then clear the client's stale handle; runbook in [deployment-manual.md §Phase 2](../deployment-manual.md)). Robustness option: make exports ensure-present each run rather than notify-on-change.
- **Nothing else publishes these paths.** ZFS share control is off on every dataset
  (`sharenfs`/`sharesmb` = `off`), so the distro `zfs-share.service` — which runs `zfs share -a` —
  owns no export here and is **disabled** on nas; its SMB half fails on `sharesmb=on` properties left
  on the `bulk/migrate` migration-remnant datasets, which no share of this layout serves. The two
  writers of the live nfsd table are `exportfs -ra` (the `storage` role's reload handler, on change)
  and `nfs-server.service`'s own `exportfs -r` at boot. Read back with `exportfs -v` — it must match
  `/etc/exports` row for row.
- **SMB/Samba is implemented** on the NAS via the `storage` role — its own section below, since
  it exposes a DIFFERENT tree than the NFS exports above and answers to different credentials.

---

## Samba (SMB) shares on the NAS

`roles/storage/tasks/samba.yml` + `templates/smb.conf.j2`, rendered on **nas** only. Three kinds of share,
the two shared ones force-owned by the neutral **`media`** account (`force user`/`force group`, uid/gid
1005 via `storage_user`/`storage_group`) so files land `media`-owned and stay usable by the arrs:

| Share | Path (nas) | Also visible on oldsrv as | `valid users` | Purpose |
|-------|------------|---------------------------|---------------|---------|
| `\\nas\media` | `/tank/data/shared` | `/mnt/nas/data/shared` | `@media` (any family account) | family shared tree |
| `\\nas\music` | `/bulk/media/media/music` | `/mnt/nas/media/media/music` | `shared` only | **the Lidarr rootFolder** — a laptop drops finished albums where the arr scans, no follow-up move |
| `\\nas\<user>` | `/tank/data/users/<user>` | — | `<user>` | per-user private drive, NO force user (own uid = the isolation) |

**winbind runs, and it authenticates nothing.** The server role is standalone and the passdb is local
`tdbsam`, so there is no domain, no trust and no user mapping through winbindd — `wbinfo -t` answering
`could not check secret` is the correct answer on this host, not a fault. The unit ships enabled with
the `samba`/`winbind` packages and the role asserts it running, because `/etc/nsswitch.conf` names
`winbind` in `passwd:`/`group:` and the name-service stack calls into the daemon on every lookup. It
is never disabled to silence a red — that leaves NSS naming a socket nobody serves — and when it has
failed the cause has been the passdb it initialized at that boot (a retired `ldapsam` backend), not
winbind itself, so a retry after the config lands is the fix.

**How a client addresses these shares.** `nas.kogler.si` answers on the LAN plane
and DHCP delivers the `kogler.si` suffix, so `\\nas\media` mounts over Wi-Fi as well as over cable.
Keep the split as the diagnostic: **IP mounts and the name does not ⇒ resolution, not Samba**
— read the DNS answer before touching the share, the accounts or the firewall. Mechanism and the
decision not to paper over it with a `hosts` file:
[network-dns.md](network-dns.md) §Local Name Resolution & mDNS.

⚠ **Samba resolves these directives by NAME, not by id.** `force user = 1005` and
`valid users = @1005` parse fine, load fine, and resolve to NOTHING: authentication succeeds and
the **tree connect** then fails — `NT_STATUS_ACCESS_DENIED`, or `NT_STATUS_NO_SUCH_USER` when it is
the force-owner that is unresolvable. `storage_user`/`storage_group` carry the names, and samba.yml
asserts they still resolve to `storage_uid`/`storage_gid` — because the
failure mode is a client-side "wrong password", not a red converge.

### Accounts: local, and the repo is the SSOT

`passdb backend = tdbsam`. One **unix account + one Samba password per entry in
`storage_samba_users`** (`host_vars/nas.kogler.si.yml`): the converge creates the unix user, makes
its private tree owned by that user, and writes the password from 1Password `smb-<name>_login`
with `smbpasswd -a -s`. The member types that username+password at mount time; nothing federates
it. Live set: `domen` (personal drive + `media`) and `shared` (a service account —
`drive: false`, no login shell — which is the credential for `\\nas\music`).

These properties of the shape are deliberate:

- **No external dependency on the auth path.** Mounting a drive from the sofa touches the LAN and
  the NAS only — passdb is local `tdbsam`, never a directory lookup. A user's Authentik portal
  password is therefore *not* a Samba credential, anywhere in this fleet: Authentik stores PBKDF2 and
  its LDAP provider/outpost ship **no Samba attribute at all**, so there is no NT hash to answer a
  Windows NTLM challenge. See [storage-rejected.md](storage-rejected.md).
- **Who can mount is a repo edit, not a directory sync.** Membership is `storage_samba_users`; the
  per-user share sections come from the template, with no `include = /etc/samba/share-*.conf` drop-in.
  ⚠ **HD-1092's premise — an Authentik → NAS provisioning script that had to be finished — is void as
  written, and was void before anyone read it tonight** (measured 2026-10-19, §Reading the family accounts below).
- **Rotation needs one extra word.** A passdb write is a target-side act, so rotating the vault item
  changes nothing on the NAS by itself (CONVENTIONS §2 rotation propagation). Rotate the item, then
  converge with `-e storage_samba_password_force=<name>` — without that flag the password task only
  fires when the account is absent from `pdbedit -L`, which is what keeps a routine converge from
  resetting a member's password on every run. **The vault is currently ahead of the box:** both
  family items are rotated and the passdb is not, so the next `nas` converge with that flag closes
  the gap — read `pdbedit -L` back afterwards.
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
  because a right answer on one share hides a wrong one on another):

  ```bash
  # on the NAS: creds go in through stdin so no password lands in argv (CONVENTIONS §6 never-print)
  printf '%s' "$PASS" | sudo tee /root/.c >/dev/null   # written as [global]/username/password
  sudo smbclient //localhost/<share> -A /root/.c -c 'ls' && echo OK
  ```
  The live matrix, with `storage_samba_users = [domen, shared]`:

  | account | `media` | `music` | `domen` (private) |
  |---|---|---|---|
  | `domen` | ✅ | ⛔ by design | ✅ |
  | `shared` | ✅ | ✅ (its share) | ⛔ isolation |

  On the NAS itself: `sudo pdbedit -L` lists the accounts and `sudo testparm -s | grep -iE 'passdb|valid
  users|force '` shows what is rendered — read `testparm`, never the template, when a share misbehaves
  (and note `testparm` needs root here because it reports on the running config).
- **Why the `music` share exists**: the `bulk/media` export names the oldsrv Home address as its **only**
  client (`/etc/exports` is IaC-rendered; addresses live in
  [network-addresses-generated.md](network-addresses-generated.md)), so nothing Windows-facing can reach
  the library through it — `\\nas\media` points at a different pool.
- ✅ **OpenCloud needs no pre-seeded accounts.** OpenCloud JIT-provisions OIDC users on first login; the
  `opencloud-service_api` and `authentik-nas_api` items have **no consumer** and are absent from the vault
  (`op item list`). With no service-account item left there is no API seat to read the account list from, so
  an account-visibility audit would need a freshly minted Graph consumer.
- **Scoped converge:** `--tags samba` (or `storage,samba`) works only because BOTH halves of the tag
  rule are in place — the `include_tasks: samba.yml` line carries the tag *and* every task inside does.
  A share change applied without both halves is a no-op that reports success.

---

### Reading the family accounts — the glue is gone, the drives exist, and the gid the row asked for is not the gid the design uses (2026-10-19, read-only)

The row was written on 2026-10-07 from `sync-authentik-users.timer` exiting 127. Every half of that premise
has since moved, so the row is corrected here rather than executed:

| The row's claim | Live state on nas, 2026-10-19 |
|---|---|
| "`sync-authentik-users.timer` fires hourly and exits 127 (823 failed runs)" | **Gone from the host and from the tree**: no `/usr/local/sbin/sync-authentik-users.sh`, no unit files, `systemctl is-enabled` → `not-found`, timer `inactive`. `roles/storage/tasks/samba.yml` now owns only the **teardown** (stop + disable + `file: absent` + `reset-failed`), so a re-derive could not reproduce the failure even on a rebuild |
| "`op` is not installed on the NAS" — so install it and give it a scoped SA token | Still not installed, and **no longer wanted**: the secret half of that path was a PUSH of a Samba password, which the `ldapsam` ruling rejected ([storage-rejected.md](storage-rejected.md)); the password comes from `smb-<name>_login` at converge. Item (1) of the row is answered, and answered the other way |
| "`/tank/data/users` does not exist, no family unix users exist" | **Void.** `/tank/data/users` exists (created 2026-10-07 18:12, `drwxr-xr-x media media`) and `/tank/data/users/domen` exists, `drwx------ domen media` — a plain directory under the `tank/data` dataset, not a per-user ZFS dataset, which is what the template does and why "no per-user datasets" was never a defect |
| "verify `id <member>` returns a uid with **primary gid 1005**" | **Void as written.** `id domen` → `uid=1007(domen) gid=1008(domen) groups=1008(domen),27(sudo),1005(media)`; `id shared` → `uid=1008(shared) gid=1009(shared) groups=1009(shared),1005(media)`; `getent group 1005` → `media:x:1005:domen,shared`. A member's primary gid is **their own group** and 1005 is **supplementary** — by design: the private drive is owned by the member (that IS the isolation, no `force user`), while `@media` and `force group` on the shared trees need group membership, not a primary group. A converge that set primary gid 1005 would strip every member's own group. The task that does this is `groups: "{{ storage_gid }}", append: true` in `samba.yml`, which is exactly what the box shows |
| "`/etc/samba/share-*.conf` is absent, so the glue's fragments were never written" + the latent `include` bug | Moot, and safe: `/etc/samba/` holds only `smb.conf` (rendered, no `include` line) and no `share-*.conf` exists to be deleted by the next storage converge. The bug the row warned about needed both halves — a runtime writer and a template that drops its include — and the writer is gone |

What is left of the row is one leg, and it is not a read: **prove a member can tree-connect their private
drive from a client.** The doc already carries that matrix (§Accounts, `domen` → `domen` ✅); re-proving it
means an authenticated `smbclient` session with the member's password, which is a credential-bearing act on
a second host, not a read — it stays parked on the row.

---

---

## Nightly Push Jobs (oldsrv → nas)

| Job | Source (oldsrv) | Target (nas) | Method |
|-----|-----------------|--------------|--------|
| DB dumps | `/srv/dumps` — produced here by `push-db-dumps.service` → `storage-push-db-dumps.sh` (`pg_dumpall` per container in `storage_push_db_dumps_pg`), as `svc-backup` | `tank/data/db-dumps` — pushed by `push-db-dumps-push.service` (the timer's chain head), **as root**: the export maps root to `anonuid=1005`, which is the only identity it accepts writes from | rsync `-a --no-owner --no-group`, no `--delete`; preservation is not optional on this export, see [backup.md](backup.md) §The oldsrv dump-push identity split |

What the VPS does instead, and why it cannot do it by NFS to the NAS, is in [backup.md](backup.md).

Key properties: dumps are written **locally first** (Kopia snapshots the local dir) and then pushed.
The job is deployed by the Ansible `storage` role and driven by systemd timers.

**One leg leaves the house rather than the box: the music serving push.** `push-music.timer` →
`storage-push-music.sh` (oldsrv, root) rsyncs the NAS music master to the live Storage Box over
**SSH/SFTP on port `:23`** — ruled shape B: no Box mount is created on oldsrv, so `roles/cifs` keeps
asserting the Box mount onto the **VPS only**. It carries three gates, all load-bearing: a `findmnt`
assert that the source really is `nas.kogler.si:/bulk/media`; a **non-empty floor** (a bound-but-dead
NFS mount passes the assert and reads as an empty directory); and a **bounded `--max-delete`**, because
an unbounded delete of an empty source would empty the library Navidrome serves while the timer reads
green. The bound is a **cap, not an abort**: measured on rsync 3.5.0, a run that would delete more
entries than the limit deletes exactly the limit, stops deleting the rest and exits 25
(`Deletions stopped due to --max-delete limit`) — so the per-fire blast radius is `max_delete`
entries and the two asserts, which run BEFORE any rsync, are what actually protect the library.
Strict host-key pinning (`UserKnownHostsFile`, `StrictHostKeyChecking=yes`) — the same discipline
as kopia's `--known-hosts`, not TOFU on a root timer. The timer renders **unarmed** until the Box SSH
identity exists on oldsrv (port 23 is key-auth-only), and the acceptance read is the file count **on the
far side**, not rsync's exit code. What the leg is unarmed on is the identity, not the code: with no
`/root/.ssh/livebox_push` the script aborts at its own identity assert before the mount assert, so the
mount assert cannot fire in the live path until the key exists — and `findmnt` against a non-NFS path
reproduces the refusal on the box.

---

## Kopia Policy (oldsrv agent → Hetzner Storage Box **SB-Backup** `HEL1-BX186`, Helsinki — off-site)

**Sources:**
- `/srv/dumps` (SQL dump scratch) — oldsrv-local
- service state dirs (`/var/lib/forgejo-dump`, n8n backups, …) — oldsrv-local
- Immich face thumbnails (`thumbs/`) — oldsrv-local
- configs: `/opt/*` compose dirs, systemd units, HA config (/ etc — plus Git for the repo itself) — oldsrv-local
- the signal-cli state volume — oldsrv-local (a docker volume)
- **the music master `/mnt/nas/media/media/music` (`bulk/media/media/music` on the NAS)** — the ONE
  NAS-resident source, mounted read-only through the `/bulk/media` export the `storage` role owns.
  It is snapshotted by its **own** line behind a mount witness (`/proc/self/mountinfo` names the export,
  or statfs reports `nfs`) **and** a non-empty floor: kopia reports an empty tree as a *successful*
  snapshot, and the next prune would retire the last snapshot that held the FLACs. So a NAS outage fails
  that one line loudly and every oldsrv-local source keeps working — which is what "NAS-independent"
  has always been for: coverage of local state must not ride on the NAS.

**Excluded:** docker named volumes (raw), downloaded model weights (GGUF/HuggingFace, re-pullable), Immich-ML weights,
`/mnt/nas/*` other than the music master above, and the rest of `bulk/media` (movies/TV + `downloads/`
are re-fetchable and stay unbacked by design).
> **Observability TSDB (VictoriaMetrics/VictoriaLogs) is Kopia-BACKED** — VM/VL volumes
> are host binds under `/srv/docker/victoria-*/data` on the VPS, snapshotted by the VPS kopia client.

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
   Device path = SSOT var `storage_nvme_data_by_id` (host_vars/oldsrv.kogler.si.yml);
   automation only creates the pool on a fresh build and a fail-loud guard blocks it while the placeholder remains.
   ⚠ The 970 EVO still carries old Windows **NTFS partitions** from its pre-homelab life — if
   `zpool create` refuses on existing signatures at the Phase-3 playbook run, wipe them first
   (`wipefs -a` on that disk only; OS disk untouched).
├── nvme/docker-layers       /var/lib/docker        128K lz4   no snapshots (images re-pullable)
├── nvme/docker              /srv/docker (container, canmount=off)
│   ├── nvme/docker/immich   /srv/docker/immich     128K lz4   thumbs read by immich-ml
│   └── nvme/docker/services /srv/docker/services   128K zstd  local service state (the public apps/DBs run on the VPS — oldsrv keeps the LAN core: DNS, signal-cli, media stack state)
├── nvme/models              /srv/models 128K off   no snapshots, no backup (ollama + immich-ml weights)  (the TSDB is on the VPS NVMe)
└── nvme/dumps               /srv/dumps  128K zstd  db-backup scratch → Kopia + push → tank/data/db-dumps
```

- **Snapshots:** none on `nvme/*` (`storage_sanoid` covers the NAS pools only) — oldsrv-local state is
  protected by the nightly push jobs + Kopia instead (rollback-before-migrations convenience is traded
  for simplicity; the pool mirrors the NAS backup surface, it does not extend coverage).
- **Bind mounts, not named volumes** for stateful services: each service dir maps 1:1 to a dataset and
gives backup jobs/Kopia clean host paths (see `deployment-compose.md` → Volume Strategy).
- **Capacity budget:** keep `nvme` < 80% full (ZFS fragmentation). ~1 TB fits comfortably: thumbs+encoded ~150–300 GB over 5 yr, docker layers ~50–100 GB, models ~60–150 GB. (The TSDB, ~20–40 GB, is on the VPS NVMe, not this pool.)
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

---

## Capacity Budget & Alerts

| Pool | Now | Growth | Headroom |
|------|-----|--------|----------|
| `tank` (4 TB) | data < 1 TB | ~+0.5 TB/yr (family data) | ~5 yrs before 80% alert |
| `bulk` (6 TB) | media + replicas ≈ 1.5–2 TB | media grows fastest | **tight side** — ~2.5 TB media headroom yr 1, sliding to full by ~yr 4 |

Alerts cover the **nas pools** — Warning **≥ 70%**, Critical **≥ 80%** (both `tank`,
`bulk`; per-pool, see `observability.md`). When `bulk` hits ~80%, offload `bulk/media` → a future 4 TB NVMe
(`hardware-spark.md`) — the planned media growth path. `tank` data stays put (mirror is the best disks).

---

## Service ↔ Storage Placement (VPS era) — which service lives on which storage

> The public stack lives on the VPS; storage is split across three tiers
> by performance and access pattern. This is the authoritative placement table for the VPS-era layout.
> Keep it in sync with `backup.md` and `services-vps.md`.

| Tier | Medium | Latency | Holds | Services consuming it |
|------|--------|---------|-------|----------------------|
| **Local SSD** | VPS 512 GB NVMe (`/srv/docker/*`) | fast | DBs, thumbnails, caches, container runtime state, Linux root | authentik, opencloud (metadata), immich (DB+thumbs), forgejo, grafana, n8n, kopia, db-backup — **hot, random-I/O, synchronous** |
| **Cold/bulk tier** | Hetzner Storage Box **live** (`u653411`, CIFS `//u653411.your-storagebox.de/backup`) | slow (CIFS over internet) | big write-once / rarely-read / regenerable-but-bulk files | **Immich originals + encoded-video**, **OpenCloud user files (WebDAV)**, family SMB drives |
| **Local backup tier** | NAS ZFS `tank`/`bulk` + local oldSrv NVMe | LAN | snapshots, dumps, service-state pushes, media library | *arr stack (media), VPS→NAS push timers, Kopia scratch |

**Rule of thumb:** *hot/random/synchronous* on local SSD; *bulk/sequential/cold* on the live Box; *media + local backup* on the NAS.

**Music: NAS master + a Box serving copy (Navidrome on the VPS).** The FLAC **master** is
the Lidarr library on the NAS: `bulk/media/media/music` (Lidarr root `/media/music`). The
Hetzner Storage Box **`music/`** is the **serving copy** Navidrome reads through its VPS-side CIFS mount
(`/mnt/storagebox/music` → `/music`, `rw`).

**The master is inside backup scope.** It is snapshotted by the oldsrv Kopia agent as its own guarded
source (§Kopia Policy) — encrypted, deduplicated, retention-managed, on the **backup** Box
(a different Storage Box server from the live one) — and it is *not* covered by sanoid, because sanoid
snapshots datasets and this master is a directory inside `bulk/media` (§Snapshot & Replication). A
Soulseek FLAC is not re-fetchable the way a movie is, which is exactly why the master is snapshotted
while the movies/TV tier beside it stays unbacked; the two tiers must not be folded back together.
Retention follows the agent's existing snapshot-retention policy — the read that shows it is
`kopia policy get /mnt/src/music` inside the `kopia-agent` container.

**The serving copy is a push, not a mount.** `oldsrv` pushes the master to the Box over rsync/SFTP on
port `:23` (§Nightly Push Jobs) — no new mount anywhere, so `roles/cifs/tasks/main.yml` keeps asserting
the Box mount onto the **VPS only** (measured: `mount | grep cifs` on oldsrv answers nothing, and neither
the NAS nor oldsrv has a Box mount). The push carries a mountpoint assert, a non-empty floor and a
bounded `--max-delete`, because a dead mount is an empty directory and an empty directory is what
Navidrome would then serve while the timer reads green. The leg is deployed unarmed until the Box SSH
identity exists on oldsrv, so until it is armed the Box's `music/` still receives nothing on its own —
only files placed there by hand (or by an owner's own SMB mount) reach Navidrome, and a music import
that appears to work on the NAS has not reached the serving copy.

---

## VPS Storage Layout (netcup RS 2000 G12 — no ZFS)

> The VPS uses **no ZFS** — the 512 GB NVMe is a single ext4 root disk
> (netcup default) and the live Hetzner Box is **CIFS**, not a block device.
> Recovery is app-level (OpenCloud `REV.*` versioning + Kopia → backup Box), not filesystem-snapshot-based.
> The three-tier placement table above is authoritative; this layout documents the concrete paths.

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

> Immich runs **on the VPS**. Originals and encoded-video live on the
> **live Hetzner Box** (cold tier); thumbnails + the Postgres DB stay on VPS NVMe (hot); ML is offloaded to the
> oldsrv GPU. The live Box is CIFS, **not S3/MinIO**.

- **VPS NVMe (`/srv/docker/immich/`)**: Postgres DB + Valkey + `upload/thumbs` (small previews, hot random reads on every UI render).
- **Live Box (CIFS)**: **originals** (`library/`) **and encoded-video** (`encoded-video/`) — sequential reads, big files, safe off NVMe.
  - Enabled via Immich **storage template** (a DB/UI setting at deploy, not compose env): thumbnails stay under `upload/thumbs`; originals + encoded-video are templated out to the CIFS mount.
  - **The template question, answered: YES, default `{{y}}/{{y}}-{{MM}}-{{dd}}/{{filename}}`.** It is the mechanism this layout depends on — with it OFF, uploads simply
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
   live Hetzner Box is the cold tier). Media library is untouched (Jellyfin/*arr resume from the
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