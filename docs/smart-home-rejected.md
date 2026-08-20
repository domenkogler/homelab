---
title: Smart Home — Rejected / Dropped Decision Log
role: log
domain: smart-home
status: active
tags: [smart-home, rejected, decision-log]
---
# Smart Home — Rejected / Dropped

> **Role:** Append-only decision log — smart-home UI / device options the homelab declined. Sorted by name. Each entry mirrors the `changelog.md` decision-log SSOT (do not re-decide without checking it).
> **Links to:** `smart-home.md`, `interfaces.md`
> **Linked from:** `index.md`, `smart-home.md`

> ⚠️ **Append-only.** Never edit or reorder an entry after it lands. A changed decision is a new appended entry (do not strike/replace). Each row: `| <tool> | <rejected|dropped|superseded> | <date> | <why + evidence link> |`.
> ⚠️ **Evidence = the owning doc + changelog decision.** Dates are the changelog/git-attribution dates (advisory).

## Decisions

| Tool | Status | Date | Why |
|------|--------|------|-----|
| TileBoard | dropped | 2026-08-18 | Obsolete/unmaintained — retired and consolidated onto the native Home Assistant Dashboard (maintained, PWA-installable, declarative YAML). HD-24. · [interfaces.md](interfaces.md) |

> **Not a smart-home-domain decision:** services / deploy / storage / network rejections live in their own `<domain>-rejected.md`. See [`services-rejected.md`](services-rejected.md), [`deployment-rejected.md`](deployment-rejected.md), [`storage-rejected.md`](storage-rejected.md), [`network-rejected.md`](network-rejected.md).
> **SSOT note:** this log mirrors the changelog `*(decision)*` rows for the smart-home domain.