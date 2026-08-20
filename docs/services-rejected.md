---
title: Services — Rejected / Dropped Decision Log
role: log
domain: services
status: active
tags: [services, rejected, decision-log]
---
# Services — Rejected / Dropped

> **Role:** Append-only decision log — services the `services` domain evaluated and declined. Sorted by service name. Each decision mirrors the `changelog.md` decision-log SSOT (do not re-decide without checking it).
> **Links to:** `services.md`, `CONVENTIONS.md` (§8.3)
> **Linked from:** `index.md`, `services.md`

> ⚠️ **Append-only.** Never edit or reorder an entry after it lands. A changed decision is a **new appended entry**, left alongside the old one — never strike/replace. Each row: `| <service> | <rejected|dropped|superseded> | <date> | <why, 1–2 lines + evidence link> |`.
> ⚠️ **Evidence = the owning doc + changelog decision.** The link below each row points to where the decision is recorded (SSOT). Dates are the changelog/git-attribution dates (advisory, per changelog.md header).

## Decisions

| Service | Status | Date | Why |
|---------|--------|------|-----|
| AnythingLLM | dropped | 2026-08-17 | Replaced by the MS Office MCP path (HD-108): Open WebUI is the family web AI layer, so AnythingLLM is removed from the web UI. · [services-ai.md](services-ai.md) |
| Ghostfolio | rejected | 2026-08-14 | Portfolio tracking is covered by Actual's tracking account (invested vs current value); XIRR/benchmarks/dividend calendar add a full service + Postgres + maintenance for no need. · [services-finance.md](services-finance.md) |
| GoCardless (Nordigen) | superseded | 2026-08-14 | Free personal sign-ups discontinued; replaced by Enable Banking (native Actual sync, account already held, UniCredit SI AISP confirmed). · [services-finance.md](services-finance.md) |
| LocPilot | superseded | 2026-08-17 | Superseded by the Office MCP path for the AI office stack; kept only as the Windows-Word inline helper, no longer a whole-family UI. · [services-ai.md](services-ai.md) |
| Pangolin | dropped | 2026-08-01 | Removed as reverse-proxy layer — Traefik handles all reverse proxy + auto-SSL (single edge). · [services.md](services.md) |
| TradeSight | rejected | 2026-08-14 | Unnecessary — Trade Republic offers a native structured CSV/Excel export, so no PDF-visual Ollama converter is needed. · [services-finance.md](services-finance.md) |

> **Not a services-domain decision:** hypervisor / deploy / storage / network / smart-home UI rejections (Proxmox, Doco-CD, iDrive, MinIO, TileBoard, netplan…) live in their own `<domain>-rejected.md` files — see [`deployment-rejected.md`](deployment-rejected.md), [`storage-rejected.md`](storage-rejected.md), [`network-rejected.md`](network-rejected.md), [`smart-home-rejected.md`](smart-home-rejected.md).
> **SSOT note:** this log mirrors the changelog `*(decision)*` rows for the services domain; a review may re-reference the owning doc.