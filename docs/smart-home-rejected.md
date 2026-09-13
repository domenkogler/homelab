---
title: Smart Home — Rejected / Dropped Decision Log
role: log
domain: smart-home
status: active
tags: [smart-home, rejected, decision-log]
---
# Smart Home — Rejected / Dropped

> **Role:** Append-only decision log — smart-home UI / device options the homelab declined. Sorted by name. This log is the per-domain **decision-log SSOT**.
> **Links to:** `smart-home.md`, `interfaces.md`
> **Linked from:** `index.md`, `smart-home.md`

> ⚠️ **Append-only.** Never edit or reorder an entry after it lands. A changed decision is a new appended entry (do not strike/replace). Each row: `| <tool> | <rejected|dropped|superseded> | <date> | <why + evidence link> |`.
> ⚠️ **Evidence = the owning doc + this decision log.** Dates are the decision dates in the owning doc / git-attribution dates (advisory).

## Decisions

| Tool | Status | Date | Why |
|------|--------|------|-----|
| TileBoard | dropped | 2026-08-18 | Obsolete/unmaintained — retired and consolidated onto the native Home Assistant Dashboard (maintained, PWA-installable, declarative YAML). HD-24. · [interfaces.md](interfaces.md) |
| HmIP-RFUSB stick (local Homematic) | rejected | 2026-09-08 | The HmIP-RFUSB USB stick will **not be purchased** — the local-RF Homematic path (RaspberryMatic + stick, HD-13/HD-18) is dropped for good: the HmIP-HAP stays in cloud mode, HA keeps talking to the cloud AP, and the stick-move pairing-transfer test (HD-18) is moot. IP devices (KNX, Shelly) already fail over via the VIP; Homematic rides the cloud HAP. · [smart-home.md](smart-home.md) §Local RF plan (deferred) · [smart-home-failover.md](smart-home-failover.md) |

> **Not a smart-home-domain decision:** services / deploy / storage / network rejections live in their own `<domain>-rejected.md`. See [`services-rejected.md`](services-rejected.md), [`deployment-rejected.md`](deployment-rejected.md), [`storage-rejected.md`](storage-rejected.md), [`network-rejected.md`](network-rejected.md).
> **SSOT note:** this log is the decision-log SSOT for the smart-home domain.