---
title: Network — Rejected / Dropped Decision Log
role: log
domain: network
status: active
tags: [network, rejected, decision-log]
---
# Network — Rejected / Dropped

> **Role:** Append-only decision log — network tooling options the homelab evaluated and declined. Sorted by tool name. Each entry mirrors the `changelog.md` decision-log SSOT (do not re-decide without checking it).
> **Links to:** `network.md`
> **Linked from:** `index.md`, `network.md`

> ⚠️ **Append-only.** Never edit or reorder an entry after it lands. A changed decision is a new appended entry (do not strike/replace). Each row: `| <tool> | <rejected|dropped|superseded> | <date> | <why + evidence link> |`.
> ⚠️ **Evidence = the owning doc + changelog decision.** Dates are the changelog/git-attribution dates (advisory).

## Decisions

| Tool | Status | Date | Why |
|------|--------|------|-----|
| netplan | rejected | 2026-08-16 | Host network config-manager — Ubuntu-desktop default + extra python3/libnetplan translation layer; rejected in favor of native `systemd-networkd`. HD-56. · [network.md](network.md) |

> **Not a network-domain decision:** services / deploy / storage / smart-home rejections live in their own `<domain>-rejected.md`. See [`services-rejected.md`](services-rejected.md), [`deployment-rejected.md`](deployment-rejected.md), [`storage-rejected.md`](storage-rejected.md), [`smart-home-rejected.md`](smart-home-rejected.md).
> **SSOT note:** this log mirrors the changelog `*(decision)*` rows for the network domain.