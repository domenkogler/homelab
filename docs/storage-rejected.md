---
title: Storage — Rejected / Dropped Decision Log
role: log
domain: storage
status: active
tags: [storage, rejected, decision-log]
---
# Storage — Dropped/Aligned

> **Role:** Append-only decision log — storage (S3/MinIO/off-site box) options the homelab declined. Sorted by name. This log is the per-domain **decision-log SSOT**.
> **Links to:** `storage.md`, `backup.md`
> **Linked from:** `index.md`, `storage.md`

> ⚠️ **Append-only.** Never edit or reorder an entry after it lands. A changed decision is a new appended entry (do not strike/replace). Each row: `| <tool> | <rejected|dropped|superseded> | <date> | <why + evidence link> |`.
> ⚠️ **Evidence = the owning doc + this decision log.** Dates are the decision dates in the owning doc / git-attribution dates (advisory).

## Decisions

| Tool | Status | Date | Why |
|------|--------|------|-----|
| iDrive e2 (S3) | dropped | 2026-08-18 | Not chosen for the S3 backend — Hetzner Storage Box is cheaper per TB + offers SMB/WebDAV; single-provider risk deliberately accepted. HD-29. · [backup.md](backup.md) |
| MinIO | dropped | 2026-08-18 | Immich originals are **not** S3/MinIO-backed — they live on the live Hetzner Box (CIFS). MinIO removed from `home_servers.yml`. HD-139. · [storage.md](storage.md) |

> **Not a storage-domain decision:** hypervisor / services / deploy / network / smart-home rejections live in their own `<domain>-rejected.md` files. Keep  [`deployment-rejected.md`](deployment-rejected.md), [`services-rejected.md`](services-rejected.md), [`network-rejected.md`](network-rejected.md), [`smart-home-rejected.md`](smart-home-rejected.md).
> **SSOT note:** this log is the decision-log SSOT for the storage domain.