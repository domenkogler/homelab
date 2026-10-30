---
title: Utilities — Productivity Sidekicks
role: detail
domain: services
status: active
sensitivity: infra
tags: [services, utilities, tools, automation]
---
# Utilities — Productivity Sidekicks

> **Role:** Detail — the lightweight internal productivity/utils slice of the services stack: PairDrop (P2P file share), Stirling PDF (PDF toolkit), n8n (automation + alert routing), Zipline (public bin / URL shortener).
> **Links to:** `services-office.md`, `observability.md`, `services-authentik.md`, `services.md`
> **Linked from:** `services.md`

> **Live on the VPS:** n8n (`auto.kogler.si` — also the observability alert router), PairDrop (`drop.`,
> public and CrowdSec-gated, WebRTC signaling only), Stirling-PDF (`pdf.`, internal, OCR `eng+slv`) and
> Zipline (`bin.`, public — the bin / URL shortener; registry `enabled: true`, so it is deployed). The
> LAN-only `dsh`/`pi-dev` rows are gone — deleted with the harness IaC, not parked.
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

## Credential rotation that has no machine channel

- **`opencloud_login` (the OpenCloud `admin` break-glass login) is not lane-rotatable — the owner act is
  `docker exec -it opencloud opencloud idm resetpassword -u admin` with the `opencloud` container STOPPED,
  then write the item.** Measured on the live instance: the vault value IS the credential the app accepts
  (an Argon2 hash in `/var/lib/opencloud/idm/idm.boltdb` verifies against it — verdict by a self-checked
  verifier, the hash itself never printed), but neither propagation path answers from a seat:
  *the render cannot move it* — `IDM_ADMIN_PASSWORD` is consumed by `opencloud init`, and `/etc/opencloud/opencloud.yaml`
  still carries its first-boot timestamp across container restarts, so re-rendering + recreating changes the env
  and not the stored credential; *the CLI cannot be driven live* — `opencloud idm resetpassword` takes the new
  password from a TTY only (no flag: `Error reading password: inappropriate ioctl for device` on a pipe) and it
  opens `idm.boltdb` **exclusively**, so against a running instance it dies with `Failed to open database:
  'timeout' … requires exclusive access`. The password is also not the user-facing login: `OC_EXCLUDE_RUN_SERVICES`
  drops the built-in `idp` and the web/App login is Authentik OIDC, so this item is break-glass for the local
  `admin` seat only.
  ⛔ **A vault-only write is the divergence this list exists to name** — the vault would move, the store would
  not, and the next time anyone needs the break-glass seat it fails. The item's only IaC site is the compose
  render, and the render is not the propagator: re-converging the service moves nothing at the store.
  · [deployment-secrets.md](deployment-secrets.md) §Master Secret List row
- **`openclaw_gateway_token` is not rotatable yet, because the thing that would check it does not exist —
  the blocked act is HD-104's `openclaw onboard` leg, not a rotation.** Measured on the live gateway: there is
  **no `openclaw.json`** (`/home/node/.openclaw/` has the state dirs and no config), so the container runs
  `gateway --allow-unconfigured` and **authenticates with nothing** — the WebSocket upgrade answers `101` with
  no credential and with a wrong one alike, and every probed HTTP path answers identically either way. The env
  var is correct (`OPENCLAW_GATEWAY_TOKEN` == the vault value, digest-compared), it simply gates nothing.
  ⛔ So a rotation here has no far end: it cannot be proved new-accepted / superseded-refused, and a vault write
  would be the divergence this list names. `openclaw onboard --non-interactive` **does** exist (with
  `--accept-risk`, and `--gateway-token` / `--gateway-token-ref-env <NAME>`), so the machine path is real — but
  running it is the **first-time bring-up of the agent** (auth providers, models, workspace, channels, skills),
  which is HD-104's deploy act and Stage 4/10, never a secret rotation.
  **The design fact worth keeping:** onboard with `--gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN` makes
  `openclaw.json` *reference the env var* instead of embedding a token — after that the compose render **is** the
  far end and the item becomes lane-rotatable (`--rotate` is refused: the item sits in `NOT_AUTO_ROTATABLE`, so
  the vault write is the round-trip form) with the container recreate as the propagation and the WS handshake as
  the two-way verdict. Until then it stays here.
  · [deployment-ai-stack-secrets.md](deployment-ai-stack-secrets.md) §item 7 · [services-ai.md](services-ai.md)

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
- ⚠ **`n8n-webhook_api` has no enforcing far end.** The compose renders `N8N_BASIC_AUTH_ACTIVE: "true"`
  with both `N8N_BASIC_AUTH_USER` and `N8N_BASIC_AUTH_PASSWORD` non-empty, and the running build still
  answers `GET /` **200 with no credential** — basic auth is not active at the pinned `n8n_version`, so
  the Grafana contact point's `basicAuthPassword` (observability.md §Alerting) is a credential the app
  never checks. **A rotation of this item buys nothing until basic auth actually enforces in this
  version** — it is a park, not a lane-rotatable rotation; what protects the alert route today is its
  placement (tailnet-only, no public path) and n8n's own credential store, not this token.
- n8n also runs **office automation** flows — see [`services-office.md`](services-office.md).

## Zipline — public bin & shortener

> ✅ **Deployed** — `zipline` + `zipline-db` Up/healthy on the VPS. The registry row is
> `enabled: true`, so a converge owns keeping it up; this section is the spec behind it.

**Deploy gate (CONVENTIONS §5 step 9) — the manual half, in order:**

- **Pre-deploy:** run `playbooks/dns.yml` once so the IaC-tracked CNAME makes `bin.kogler.si` resolve —
  a Traefik route alone is NOT reachable.
- **Post-up seeding** — all runtime-editable in the admin UI / Server Settings, nothing here is a
  one-way door:
  1. First-boot admin: `https://bin.kogler.si/auth/setup` (local admin).
  2. OIDC verify: log in via Authentik — the **first** OIDC login auto-creates the account
     (`FEATURES_OAUTH_REGISTRATION=true`), family-only because the Authentik app is bound to the family
     group. Then flip OAuth **bypass-local-login** ON in Server Settings; it stays OFF until the local
     break-glass account is proven.
  3. Create user `guestbin` (admin panel; small storage quota ~100 MB; **no password minted into any
     vault** — it must never log in), then folder `dropzone` with `allowUploads=true`; paste its folder id
     into the family drop script.
  4. Verify: an anonymous upload carrying both headers returns a short URL, the viewer route serves it
     logged-out, and the file is gone after 6 h (`tasks.deleteInterval` sweep).

**Purpose:** public temporary file bin (phone↔PC transfers via short link), URL shortener + QR codes; private persistent storage secondary (OpenCloud stays the family file cloud).

**Architecture decisions:**
- **Image/pin:** `zipline_version` in `group_vars/all/versions.yml` — read the pin, do not quote a version here; 4.8.0 crashes on its Prisma migration ledger, so a bump is data-format work, not a renovate commit;**local filesystem datasource** on VPS NVMe (no S3).
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