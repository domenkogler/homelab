---
title: Utilities — Productivity Sidekicks
role: detail
domain: services
status: active
tags: [services, utilities, tools, automation]
---
# Utilities — Productivity Sidekicks

> **Role:** Detail — the lightweight internal productivity/utils slice of the services stack: PairDrop (P2P file share), Stirling PDF (PDF toolkit), n8n (automation + alert routing), Zipline (public bin / URL shortener, HD-112).
> **Links to:** `services-office.md`, `observability.md`, `services-authentik.md`, `services.md`
> **Linked from:** `services.md`

> 🟢 **VPS members live since 2026-08-22**: n8n (`auto.kogler.si`, the alert brain), PairDrop (public crowdsec-only tier on both subdomains per HD-230a), Stirling-PDF. ⏳ deploy-gated: signal-cli-rest-api (oldsrv, Phase 3 — reaches n8n over WG S2S once that tunnel is up, HD-03) · **Zipline** (HD-112 — IaC complete 2026-08-24, NOT deployed; deploy-gate runbook = the compose header checklist).

---

## Catalog

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| n8n | auto | I | 200–400 / 700 | Alert router → Signal/email (also office automation) |
| signal-cli | — | I | 80–150 / 250 | Signal delivery (linked device, "Homelab Alerts") |
| PairDrop | pairdrop | P | 100–180 / 300 | **P2P file share** (HD-230, supersedes HD-113) — browser WebRTC "AirDrop-style" transfers; PUBLIC since 2026-08-23 on `pairdrop.kogler.si` + `drop.kogler.si` via crowdsec-only tier (no Forward-Auth), traefik-public-only network isolation, built-in RATE_LIMIT (linuxserver image; no data persisted to disk) |
| Stirling PDF | pdf | I | 150–400 / 800 | **PDF toolkit** (HD-58) — merge/split/compress/convert/number/OCR (Tesseract `eng+slv`); anonymous mode + Forward-Auth, internal-only; no local online-PDF-editor dependency; **stateless (in-memory, no disk/backup)** |
| Zipline | bin | P | ~200–350 / 700 (est.) | **Public bin + URL shortener + QR** (HD-112) — v4.7.0 pin, VPS, local datasource; `crowdsec-only` tier; native-OIDC dashboard; guestbin dropzone (no-login uploads, 6h TTL, quota-bounded); 🟢 IaC done ⏳ deploy-gated |

## Automation & Alerting

- **n8n** is the alert **router** (dedup / tier / format) from Grafana Alerting — see [`observability.md`](observability.md).
- **signal-cli** is the Signal delivery leg that n8n drives ("Homelab Alerts" group).
- ⏳ **HD-249 (planned, v2):** n8n moves INTERNAL -- `auto.kogler.si` public route dropped, editor via tailnet-sidecar Pattern B, scoped LiteLLM key (+ budget cap) for AI workflow nodes. Prerequisite: audit external webhook dependencies before cutting the route.
- n8n also runs **office automation** flows — see [`services-office.md`](services-office.md).

## Zipline — public bin & shortener (HD-112)

> 🟢 **Decided + IaC authored 2026-08-24 — nothing deployed yet (⏳ deploy-gated).** Full decision record: [changelog.md](../changelog.md) (HD-112). Design source-verified against Zipline v4.7.0. Deploy-gate steps live in the compose header (`docker_services/zipline/docker-compose.yml.j2`).

**Purpose:** public temporary file bin (phone↔PC transfers via short link), URL shortener + QR codes; private persistent storage secondary (OpenCloud stays the family file cloud).

**Architecture decisions:**
- **Image/pin:** `zipline_version` = `v4.7.0` (`group_vars/all/versions.yml`); **local filesystem datasource** on VPS NVMe (HD-131-compliant — no S3).
- **Exposure:** ONE public host `bin.kogler.si`, middleware `crowdsec-only@file` (never zero edge protection). Viewer/shortener routes + guest upload API are anonymous BY DESIGN — no auth middleware on this host's public paths.
- **Auth:** dashboard gated by Zipline NATIVE OIDC — provider declared in the `ks-oidc.yml` Authentik blueprint (family-group binding only), `FEATURES_USER_REGISTRATION=false`, OAuth-registration off, local login bypassed. Forward-Auth deliberately NOT stacked (double-auth avoided; Immich/OpenCloud precedent).
- **Guestbin split (anonymous uploads):** dedicated Zipline-local user `guestbin` (no Authentik identity, never logs in) owns a `dropzone` folder with `allowUploads=true`. Guests upload unauthenticated via `POST /api/upload` with headers `x-zipline-folder: <id>` + hardcoded `x-zipline-deletes-at: 6h` — global default expiration stays UNSET so private uploads default permanent. Files attribute to guestbin and consume ITS small quota.
- **No content blockers:** global type/extension blocklists stay EMPTY (owner stores executables privately); `FILES_MAX_FILE_SIZE` generous — the public side is bounded by guestbin quota + 6h TTL + rate limit + CrowdSec, not by caps. Accepted residual risk: the bin can briefly host arbitrary files ≤ quota within TTL.
- **Backup split:** ephemeral dropzone volume EXCLUDED from Kopia (expires in 6h by design); persistent private-account data included (storage/backup rows land with the IaC change).
- **Phase 2 (deferred):** `/drop` static glue page via a higher-priority Traefik router (`PathPrefix(/drop) && Host(bin.kogler.si)` → static files, catch-all → Zipline) — same-origin API calls, no CORS, token in localStorage.
- **Storage & data location (§5 step 6.5):** datasource = `/srv/docker/zipline/uploads` on **VPS NVMe** (ephemeral guest drops + private files); Postgres metadata at `/srv/docker/zipline/postgres`. Uploads tree is **excluded from Kopia** ([backup.md](backup.md)); DB dumped via `db-backup` DB05.
- **Runtime tuning:** quota, size cap, expiry defaults, rate limits are all Server-Settings-editable post-deploy — starting values are non-binding.

## Related
- [Observability](observability.md) — alerting pipeline (Grafana → n8n → signal-cli)
- [Office stack](services-office.md) — n8n office automation flows
- [Services index](services.md) — catalog legend + network/subdomain SSOT