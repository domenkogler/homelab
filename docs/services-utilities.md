---
title: Utilities — Productivity Sidekicks
role: detail
domain: services
status: active
tags: [services, utilities, tools, automation]
---
# Utilities — Productivity Sidekicks

> **Role:** Detail — the lightweight internal productivity/utils slice of the services stack: PairDrop (P2P file share), Stirling PDF (PDF toolkit), n8n (automation + alert routing).
> **Links to:** `services-office.md`, `observability.md`, `services-authentik.md`, `services.md`
> **Linked from:** `services.md`

> 🟢 **VPS members live since 2026-08-22**: n8n (`auto.kogler.si`, the alert brain), PairDrop (public crowdsec-only tier on both subdomains per HD-230a), Stirling-PDF. ⏳ deploy-gated: signal-cli-rest-api (oldsrv, Phase 3 — reaches n8n over WG S2S once that tunnel is up, HD-03).

---

## Catalog

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| n8n | auto | I | 200–400 / 700 | Alert router → Signal/email (also office automation) |
| signal-cli | — | I | 80–150 / 250 | Signal delivery (linked device, "Homelab Alerts") |
| PairDrop | pairdrop | P | 100–180 / 300 | **P2P file share** (HD-230, supersedes HD-113) — browser WebRTC "AirDrop-style" transfers; PUBLIC since 2026-08-23 on `pairdrop.kogler.si` + `drop.kogler.si` via crowdsec-only tier (no Forward-Auth), traefik-public-only network isolation, built-in RATE_LIMIT (linuxserver image; no data persisted to disk) |
| Stirling PDF | pdf | I | 150–400 / 800 | **PDF toolkit** (HD-58) — merge/split/compress/convert/number/OCR (Tesseract `eng+slv`); anonymous mode + Forward-Auth, internal-only; no local online-PDF-editor dependency; **stateless (in-memory, no disk/backup)** |

## Automation & Alerting

- **n8n** is the alert **router** (dedup / tier / format) from Grafana Alerting — see [`observability.md`](observability.md).
- **signal-cli** is the Signal delivery leg that n8n drives ("Homelab Alerts" group).
- n8n also runs **office automation** flows — see [`services-office.md`](services-office.md).

## Related
- [Observability](observability.md) — alerting pipeline (Grafana → n8n → signal-cli)
- [Office stack](services-office.md) — n8n office automation flows
- [Services index](services.md) — catalog legend + network/subdomain SSOT