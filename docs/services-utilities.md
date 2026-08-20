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

> ⚠️ **Planning phase — not yet deployed.** Utility services are IaC-authored but **not live**; deploy-gated against `deployment-tasks.md`.

---

## Catalog

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| n8n | auto | I | 200–400 / 700 | Alert router → Signal/email (also office automation) |
| signal-cli | — | I | 80–150 / 250 | Signal delivery (linked device, "Homelab Alerts") |
| PairDrop | pairdrop | I | 100–180 / 300 | **P2P file share** (HD-113) — browser WebRTC "AirDrop-style" transfers, local-network device discovery, internal-only via Forward-Auth (linuxserver image; no data persisted to disk) |
| Stirling PDF | pdf | I | 150–400 / 800 | **PDF toolkit** (HD-58) — merge/split/compress/convert/number/OCR (Tesseract `eng+slv`); anonymous mode + Forward-Auth, internal-only; no local online-PDF-editor dependency; **stateless (in-memory, no disk/backup)** |

## Automation & Alerting

- **n8n** is the alert **router** (dedup / tier / format) from Grafana Alerting — see [`observability.md`](observability.md).
- **signal-cli** is the Signal delivery leg that n8n drives ("Homelab Alerts" group).
- n8n also runs **office automation** flows — see [`services-office.md`](services-office.md).

## Related
- [Observability](observability.md) — alerting pipeline (Grafana → n8n → signal-cli)
- [Office stack](services-office.md) — n8n office automation flows
- [Services index](services.md) — catalog legend + network/subdomain SSOT