---
title: Services — Rejected / Dropped Decision Log
role: log
domain: services
status: active
tags: [services, rejected, decision-log]
---
# Services — Rejected / Dropped

> **Role:** Append-only decision log — services the `services` domain evaluated and declined. Sorted by service name. This log is the per-domain **decision-log SSOT**.
> **Links to:** `services.md`, `CONVENTIONS.md` (§8.3)
> **Linked from:** `index.md`, `services.md`

> ⚠️ **Append-only.** Never edit or reorder an entry after it lands. A changed decision is a **new appended entry**, left alongside the old one — never strike/replace. Each row: `| <service> | <rejected|dropped|superseded> | <date> | <why, 1–2 lines + evidence link> |`.
> ⚠️ **Evidence = the owning doc + this decision log.** The link below each row points to where the decision is recorded (SSOT). Dates are the decision dates in the owning doc / git-attribution dates (advisory).

## Decisions

| Service | Status | Date | Why |
|---------|--------|------|-----|
| AnythingLLM | dropped | 2026-08-17 | Replaced by the MS Office MCP path (HD-108): Open WebUI is the family web AI layer, so AnythingLLM is removed from the web UI. · [services-ai.md](services-ai.md) |
| Ghostfolio | rejected | 2026-08-14 | Portfolio tracking is covered by Actual's tracking account (invested vs current value); XIRR/benchmarks/dividend calendar add a full service + Postgres + maintenance for no need. · [services-finance.md](services-finance.md) |
| GoCardless (Nordigen) | superseded | 2026-08-14 | Free personal sign-ups discontinued; replaced by Enable Banking (native Actual sync, account already held, UniCredit SI AISP confirmed). · [services-finance.md](services-finance.md) |
| LocPilot | superseded | 2026-08-17 | Superseded by the Office MCP path for the AI office stack; kept only as the Windows-Word inline helper, no longer a whole-family UI. · [services-ai.md](services-ai.md) |
| Pangolin | dropped | 2026-08-01 | Removed as reverse-proxy layer — Traefik handles all reverse proxy + auto-SSL (single edge). · [services.md](services.md) |
| Edge model — Option A: "one public + one internal all-app edge" | decided | 2026-09-04 | **HD-331 (owner + AI, 2026-09-04):** long-term reverse-proxy architecture = **one PUBLIC edge (WAN-only, public apps) + one INTERNAL all-app edge (serves EVERY app, public + internal) reached over Headscale tailnet AND WireGuard S2S**. The internal all-app edge is implemented as the growth of the existing `traefik-tailnet` VPS instance (file-provider routes; no docker-provider to avoid router conflicts) + a second listener on the `wg-s2s` VPS side + tailnet/WG ACL allow. The public edge stays Docker-labels + single ACME issuer. Same-zone split-horizon DNS resolves the same names everywhere; `traefik-ha` remains the physical HA-VIP failover edge (not the internal all-app edge). Rationale: single always-on public host (VPS), WG-S2S + tailnet already route to the VPS, home nodes Phase-3 unprovisioned. Alternatives declined — (B) home-host internal edge (Pi/oldsrv) as base: better home latency but needs router hairpin + oldsrv live + complicates certs/one-instance; (C) keep 3 edges as-is: leaves `ha` broken with Tailscale on. Implementation HDs: HD-332 (catalog `public:` flag + internal-edge growth), HD-333 (WG reach + ACL), HD-334 (per-device DNS via Pi-first VLAN-10 + seed `vpn`/`home`/`dns`). Owning doc: [services-traefik.md](services-traefik.md) §Edge model; decision log cross-ref: [network-dns.md](network-dns.md) (DNS unchanged), [todo.md](../todo.md) HD-331. |
| TradeSight | rejected | 2026-08-14 | Unnecessary — Trade Republic offers a native structured CSV/Excel export, so no PDF-visual Ollama converter is needed. · [services-finance.md](services-finance.md) |

> **Not a services-domain decision:** hypervisor / deploy / storage / network / smart-home UI rejections (Proxmox, Doco-CD, iDrive, MinIO, TileBoard, netplan…) live in their own `<domain>-rejected.md` files — see [`deployment-rejected.md`](deployment-rejected.md), [`storage-rejected.md`](storage-rejected.md), [`network-rejected.md`](network-rejected.md), [`smart-home-rejected.md`](smart-home-rejected.md).
> **SSOT note:** this log is the decision-log SSOT for the services domain.