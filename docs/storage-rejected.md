---
title: Storage — Rejected / Dropped Decision Log
role: log
domain: storage
status: active
tags: [storage, rejected, decision-log]
---
# Storage — Rejected / Dropped

> **Role:** Decision log — storage/backup options this homelab evaluated and declined; the per-domain
> **decision-log SSOT**. One row per decision, sorted by subject. The current-state fact a decision
> settled lives in the owning doc, not here.
> **Links to:** `storage.md`, `backup.md`
> **Linked from:** `index.md`, `storage.md`

> Each row is `| <subject> | <rejected|dropped|superseded> | <why> |` — no dates, no links, no prose.
> **Append-only:** add rows, never rewrite or delete an existing one; rows are keyed by subject
> (`CONVENTIONS.md` §8.3). Evidence = the current-state text in the owning doc.

## Decisions

| Subject                                                             | Status     | Why                                                         |
|--------------------------------------------------------------------|-----------|------------------------------------------------------------|
| Authentik group sync for Samba accounts (`sync-authentik-users.sh`) | superseded | membership is a repo edit now                             |
| Authentik LDAP outpost as the Samba passdb (ldapsam)                | superseded | serves no sambaNTPassword; LAN mount would need the WAN   |
| `bulk/media` (media library) backups                                | rejected   | redownloadable via usenet/torrents                        |
| `docker cp` into a DB container for restores                        | rejected   | the DB rootfs is read-only; pipe over STDIN               |
| Hetzner Box as the music master (Lidarr copy-import)                | superseded | the NAS Lidarr library is the master                      |
| `hosts`-file entry for UNC mounts over Wi-Fi                        | rejected   | the zone `nas` record is the fix, not a laptop override   |
| iDrive e2 (S3)                                                      | dropped    | Hetzner Box is cheaper per TB and does SMB/WebDAV         |
| Immich face thumbnails treated as regenerable                       | superseded | regenerating means a full facial-recognition re-scan      |
| Immich `library/` storage-template subpath                          | rejected   | flattens every asset into one directory                   |
| Immich originals on the NAS                                         | superseded | the live Box (CIFS) is the originals tier                 |
| immich's bundled PG 14 composite, in the 16 → 18 legs              | rejected   | ships PG 14 only; data_checksums blocks `--link`          |
| Kopia snapshots of VPS db-backup dumps                              | dropped    | no Kopia client on the VPS; dumps are one copy            |
| Local tdbsam Samba accounts (`pdbedit`)                             | superseded | its first rejection is void, re-adopted as the design     |
| Manual music ingest: copy plus a privileged `mv`                    | superseded | the `music` share writes the Lidarr root directly         |
| MinIO                                                               | dropped    | Immich originals are Box CIFS; the Box is not S3          |
| NAS ZFS snapshots as the family per-file version UI                 | superseded | OpenCloud native versions on the Box                      |
| NAS-local `immich`/`documents` archive datasets                     | dropped    | the Box + Kopia is the recovery path                      |
| Numeric uid/gid in `force user` / `valid users`                     | rejected   | Samba resolves by name; an id resolves to nothing         |
| oldsrv `push-face-thumbs` unit                                      | dropped    | the thumb tree lives on the VPS                           |
| oldsrv `push-services` unit (Forgejo/n8n state)                     | dropped    | those containers live on the VPS                          |
| Pre-seeded OpenCloud accounts via a service account                 | dropped    | OIDC users JIT-provision on first login                   |
| Prometheus/Loki TSDB excluded from backup                           | superseded | the VictoriaMetrics/VictoriaLogs volumes are Kopia-backed |
| RAIDZ1 for `tank`, even with RAIDZ expansion                        | rejected   | mirror wins resilver, self-healing and random I/O         |
| `rsync -a` owner/group preservation onto the NAS export             | rejected   | the export accepts writes from `media` only               |
| Skipping missing containers so a push exits 0                       | rejected   | a green unit that ships nothing is fake green             |
| The upstream parent image's `/var/lib/postgresql/18` bind           | superseded | `cap_drop: ALL` cannot mkdir it; the path is stale        |
| Untagged tasks inside `samba.yml` under a scoped converge           | superseded | include line and every task carry the tag                 |
| VPS → NAS NFS push for VPS state                                   | rejected   | the NAS exports to the oldsrv /32 only                    |
| ZFS on the VPS                                                      | rejected   | one ext4 disk; the bulk tier is CIFS                      |
| Zipline upload payloads in Kopia                                    | rejected   | anonymous drops self-destruct at ≤ 6h TTL                |

> **Not a storage-domain decision:** hypervisor / services / deploy / network / smart-home rejections
> live in their own `<domain>-rejected.md` files:
> [`deployment-rejected.md`](deployment-rejected.md), [`services-rejected.md`](services-rejected.md),
> [`network-rejected.md`](network-rejected.md), [`smart-home-rejected.md`](smart-home-rejected.md).
