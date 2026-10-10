---
title: Utilities — Productivity Sidekicks
role: detail
domain: services
status: active
tags: [services, utilities, tools, automation]
---
# Utilities — Productivity Sidekicks

> **Role:** Detail — the lightweight internal productivity/utils slice of the services stack: PairDrop (P2P file share), Stirling PDF (PDF toolkit), n8n (automation + alert routing), Zipline (public bin / URL shortener).
> **Links to:** `services-office.md`, `observability.md`, `services-authentik.md`, `services.md`
> **Linked from:** `services.md`

> **Live on the VPS:** n8n (`auto.kogler.si` — also the observability alert router), PairDrop (`drop.`,
> public and CrowdSec-gated, WebRTC signaling only), Stirling-PDF (`pdf.`, internal, OCR `eng+slv`),
> Zipline (`bin.`, public), and the LAN-only `dsh`/`pi-dev` rows are **parked** (registry
> `enabled: false`).
>
> ⏳ **Open:** **`signal-cli-rest-api`** runs on oldsrv and is published on its Home-VLAN address so the VPS
> alert brain can reach it (observability's alert-router leg), but **Signal delivery is still owner-gated —
> no device is linked**, so that leg delivers nothing until it is
> ([observability.md](observability.md) §Alert delivery).


---

## Catalog

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| n8n | auto | I | 200–400 / 700 | Alert router → Signal/email (also office automation) |
| signal-cli | — | I | 80–150 / 250 | Signal delivery (linked device, "Homelab Alerts") |
| PairDrop | pairdrop | P | 100–180 / 300 | **P2P file share** — browser WebRTC "AirDrop-style" transfers; PUBLIC on `pairdrop.kogler.si` + `drop.kogler.si` via crowdsec-only tier (no Forward-Auth), traefik-public-only network isolation, built-in RATE_LIMIT (linuxserver image; no data persisted to disk). ✅**live-verified**: container healthy, `drop.kogler.si` → 200 crowdsec-only, signaling/WebRTC routed through Traefik |
| Stirling PDF | pdf | P | 150–400 / 800 | **PDF toolkit** — merge/split/compress/convert/number/OCR (Tesseract `eng+slv`, `-fat` image bundles all langs); anonymous mode inside app + Authentik Forward-Auth at the Traefik edge (public `pdf.kogler.si`, SSO-gated); no local online-PDF-editor dependency;**stateless (in-memory, no disk/backup)**. ✅**live-verified**: container healthy, `pdf.kogler.si` → 302 Forward-Auth chain, OCR `eng+slv` |
| Zipline | bin | P | ~200–350 / 700 (est.) | **Public bin + URL shortener + QR** — v4.7.0 pin, VPS, local datasource; `crowdsec-only` tier; native-OIDC dashboard; guestbin dropzone (no-login uploads, 6h TTL, quota-bounded); 🟢 IaC done ⏳ deploy-gated |

## Automation & Alerting

- **n8n** is the alert **router** (dedup / tier / format) from Grafana Alerting — see [`observability.md`](observability.md).
- **signal-cli** is the Signal delivery leg that n8n drives ("Homelab Alerts" group).
- n8n holds **exactly one workflow** (`homelab-alerts`, active); its only inbound surface is **one production
  webhook** `POST /webhook/homelab-alerts`, whose only caller is **Grafana's contact point** posting to
  `http://n8n:5678/webhook/homelab-alerts` on the docker network (`grafana_alert_webhook_url`,
  [observability.md](observability.md)).
- `auto.kogler.si` appears **only** in `traefik-tailnet` routes — **zero** hits in `traefik-public` — so n8n has
  no public inbound path. `WEBHOOK_URL=https://auto.kogler.si` is only the URL n8n *advertises*
  (editor/callback links), never the alert path.
- ⚠ **The workflow has no AI or LangChain node** — n8n makes no LLM call, so it holds no LiteLLM credential, and
  minting one now would add an unused vault item + an unused LiteLLM key. The SHAPE for the day an AI node
  appears: **no `max_budget` cap, local rows only** (`spark/qwen3.8-flash-next`; `rpm` as KV-contention
  protection), minted through the **LAN** instance (`lan-litellm` → `home_servers.yml` `litellm_scoped_keys`),
  which is where every internal querier's key lives.
- n8n also runs **office automation** flows — see [`services-office.md`](services-office.md).

## Zipline — public bin & shortener

> ✅ **Deployed** — `zipline` + `zipline-db` Up/healthy on the VPS. The registry row is
> `enabled: true`, so a converge owns keeping it up; this section is the spec behind it. Deploy-gate steps live
> in the compose header (`docker_services/zipline/docker-compose.yml.j2`).

**Purpose:** public temporary file bin (phone↔PC transfers via short link), URL shortener + QR codes; private persistent storage secondary (OpenCloud stays the family file cloud).

**Architecture decisions:**
- **Image/pin:** `zipline_version` = `v4.7.0` (`group_vars/all/versions.yml`);**local filesystem datasource** on VPS NVMe (no S3).
- **Exposure:** ONE public host `bin.kogler.si`, middleware `crowdsec-only@file` (never zero edge protection). Viewer/shortener routes + guest upload API are anonymous BY DESIGN — no auth middleware on this host's public paths.
- **Auth:** dashboard gated by Zipline NATIVE OIDC — provider declared in the `ks-oidc.yml` Authentik blueprint (family-group binding only), `FEATURES_USER_REGISTRATION=false`, OAuth-registration off, local login bypassed. Forward-Auth deliberately NOT stacked (double-auth avoided; Immich/OpenCloud precedent).
- **Guestbin split (anonymous uploads):** dedicated Zipline-local user `guestbin` (no Authentik identity, never logs in) owns a `dropzone` folder with `allowUploads=true`. Guests upload unauthenticated via `POST /api/upload` with headers `x-zipline-folder: <id>` + hardcoded `x-zipline-deletes-at: 6h` — global default expiration stays UNSET so private uploads default permanent. Files attribute to guestbin and consume ITS small quota.
- **No content blockers:** global type/extension blocklists stay EMPTY (owner stores executables privately); `FILES_MAX_FILE_SIZE` generous — the public side is bounded by guestbin quota + 6h TTL + rate limit + CrowdSec, not by caps. Accepted residual risk: the bin can briefly host arbitrary files ≤ quota within TTL.
- **Backup split:** ephemeral dropzone volume EXCLUDED from Kopia (expires in 6h by design); persistent private-account data included.
- **Phase 2 (deferred):** `/drop` static glue page via a higher-priority Traefik router (`PathPrefix(/drop) && Host(bin.kogler.si)` → static files, catch-all → Zipline) — same-origin API calls, no CORS, token in localStorage.
- **Storage & data location (§5 step 6.5):** datasource = `/srv/docker/zipline/uploads` on **VPS NVMe** (ephemeral guest drops + private files); Postgres metadata at `/srv/docker/zipline/postgres`. Uploads tree is **excluded from Kopia** ([backup.md](backup.md)); DB dumped via `db-backup` DB05.
- **Runtime tuning:** quota, size cap, expiry defaults, rate limits are all Server-Settings-editable post-deploy — starting values are non-binding.

## Related
- [Observability](observability.md) — alerting pipeline (Grafana → n8n → signal-cli)
- [Office stack](services-office.md) — n8n office automation flows
- [Services index](services.md) — catalog legend + network/subdomain SSOT