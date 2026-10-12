---
title: Office Stack — Local LLM, Documents & Office Automation
role: detail
domain: services
cross_cutting: true
status: active
tags: [services, llm, ollama, office]
---
# Office Stack — Local LLM, Documents & Office Automation

> **Role:** Stack doc (detail, cross-cutting) — the office workload slice of the services stack: ONLYOFFICE/WOPI + OpenCloud collaboration, MS fonts, family device/client matrix, Office MCP bridges, toolchain. AI platform details (models, routing) live in [`services-ai.md`](services-ai.md).
> **Links to:** `hardware-gpu.md`, `services-ai.md`, `services-authentik.md`, `services-traefik.md`
> **Linked from:** `services.md`, `index.md`

> 🟢 **Server side live**: OpenCloud (`file.kogler.si`) + ONLYOFFICE WOPI integration — the `collaboration` service runs, WOPI discovery answers, one shared REVA/JWT secret, CSP `upgrade-insecure-requests` on the office router; the `.docx` round-trip PASSES incl. two-browser co-editing. ⏳ deploy-gated/future: the oldsrv desktop toolchain (Phase 3) and the Office MCP bridge on client PCs — this doc remains the spec for those parts.

---

## Strategy

**Office AI is a gateway consumer, not a GPU resident.** Generation for office work runs wherever the
gateway routes it (the spark tier today); the oldsrv GPU holds only the small pinned legs (embed / rerank /
STT) alongside immich-ML and Sunshine, and the voice pipeline that will share it is not built yet
([smart-home-voice.md](smart-home-voice.md)).

The AI **platform** — routing, models, keys — is owned by [`services-ai.md`](services-ai.md); the gateway is
the only path to any model, local or paid. This doc covers only the office slice. VRAM management:
[`hardware-gpu.md`](hardware-gpu.md).

---

## Toolchain


### Family Device Stack (one document, any screen)

| Platform | File Syncing & Access | Document Editing (Word/Excel/PP) | Why This Works Best |
|: --- |: --- |: --- |: --- |
| **🌐 Web Browser** | OpenCloud Web Interface | **ONLYOFFICE Docs Server** (via WOPI) | Perfect for quick edits or when a family member is on a guest computer. |
| **💻 Windows 11** | **OpenCloud Desktop Client** for Windows | **Microsoft Office Suite** (Local) | Your files sync to a local folder, and MS Office opens them with maximum feature compatibility. |
| **🐧 Linux** | **OpenCloud Desktop Client** for Linux | **ONLYOFFICE Desktop Editors** | ONLYOFFICE preserves Microsoft formatting much better than LibreOffice or OpenOffice. |
| **📱 Phone (Android/iOS)** | **OpenCloud mobile app** (native OIDC → Authentik SSO, photo backup) | **"Open in web" → the ONLYOFFICE Docs tab**, or ONLYOFFICE Documents for a downloaded copy | The phone never holds a file-server password: it holds a short-lived SSO token, like every other family surface. |

#### Mobile: which app is the storage surface

> **Decision: on phones the OpenCloud app is the file surface; the ONLYOFFICE Documents app is an
> editor, not a cloud client.** ONLYOFFICE Documents ships its own connector list (ONLYOFFICE
> Docs/DocSpace, Nextcloud, ownCloud, kDrive, OneDrive, Dropbox, "Other WebDAV") and **every one of
> them authenticates with username + password / app token** — none of them can present an Authentik
> session, so choosing any entry there means parking a long-lived file credential on a device that
> leaves the house. WebDAV + an OpenCloud **app token** is a legitimate *fallback* (the same
> scoped-credential pattern as the OpenClaw service user (`openclaw-opencloud_api`), and
> OpenCloud documents app tokens for WebDAV clients) — but it is not SSO and not the family default.
>
> **OpenCloud Android app SSO — ✅ LIVE** (login through sso, file list shown; the acceptance check is
> server-side: a `RefreshToken` row whose scope still contains `offline_access`). Two server-side
> requirements behind the errors the native client throws, both recorded in
> [services-authentik.md](services-authentik.md) §"Blueprint authoring notes" facts 7 + 9 — (a) the
> native clients **discover** their client_id from WebFinger and Authentik binds one client_id to one
> issuer, so every platform must share the single `web` client; (b) a refresh token is minted only if
> `offline_access` is a property mapping on the provider. Family steps: [manual/opencloud.md](manual/opencloud.md).
> **From a handset:** tapping a document hands a browser tab to the WOPI editor — the app-provider chain
> works from a phone, not just a desktop browser.
> Photo backup is deliberately **not** enabled here: Immich owns family photos, so a second photo copy in
> OpenCloud would only double the storage bill and the restore surface.

> OpenCloud ships a native **`collaboration` service** that connects to ONLYOFFICE / Collabora / Microsoft **via WOPI** (no third-party glue). Not enabled by default — start manually with `opencloud collaboration server`. Key vars: `COLLABORATION_APP_PRODUCT=OnlyOffice`, `COLLABORATION_APP_ADDR` (editing app URL), `COLLABORATION_WOPI_SRC` (public WOPI callback), plus `OC_URL`, `OC_JWT_SECRET`, `OC_REVA_GATEWAY`, `MICRO_REGISTRY_ADDRESS`. [Docs](https://docs.opencloud.eu/docs/dev/server/services/collaboration/information/).

#### ONLYOFFICE Docs Server — deployment & auth

**What it is:** a WOPI-helper Docker container (`onlyoffice/documentserver`) that renders the in-browser editor for OpenCloud documents at `office.kogler.si`. Brings browser editing (Word/Excel/PPT) to the**"🌐 Web Browser" row** above — desktop sync/edit is unchanged (native ONLYOFFICE Desktop Editors / MS Office).

**Auth — NOT an identity surface (no Authentik client, no Forward-Auth):**

```
 Browser (user's Authentik session)──► Traefik ──► ONLYOFFICE Docs (`office.kogler.si`)
                                        │                   │
                                        │                   │  WOPI (shared JWT secret,
                                        │                   │  NOT user identity)
                                        ▼                   ▼
                                    OpenCloud ◄─────────────┘
                                    (`file.kogler.si`, `collaboration` svc)
```

- **The browser** authenticates the *user* (Authentik OIDC).
- **ONLYOFFICE** is a **background worker**: it never sees family logins. OpenCloud and ONLYOFFICE trust each other over **cryptographically signed WOPI calls**, so no `office_*` Authentik client is needed and the route is **not** behind Forward-Auth (it would break the editor's iframe/API calls). The trust secret must be **one consistent value** (`opencloud-collab_password`, 1P) across FOUR envs so both the DS and OpenCloud's reva token-manager validate the same tokens: OpenCloud `OC_JWT_SECRET` (system-wide reva `token_manager.jwt_secret` — REQUIRED, else REVA-mint vs verify split-brain → 401), OpenCloud `COLLABORATION_JWT_SECRET`, OpenCloud `COLLABORATION_WOPI_SECRET`, and ONLYOFFICE `JWT_SECRET` (see [deployment-secrets.md](deployment-secrets.md)).
- **Consequence for IaC:** no Authentik Blueprint path — no provider, no app, no secret-egress item. In place: Traefik cert (``Host(`office.kogler.si`)``) + pinned `onlyoffice_version` + `OC_ADD_RUN_SERVICES: collaboration` + `COLLABORATION_APP_*`/`WOPI_SRC` env on the opencloud compose + `opencloud-collab_password` (shared JWT, 1Password, same value on BOTH sides) + CSP `office.kogler.si` in frame-src/connect-src.

- **🟢 LIVE:** `.docx` round-trip PASSES — editor opens, edit + save persist, and **live co-editing works** (two browsers simultaneously). `collaboration` runs, `/hosting/discovery` answers 200.
  - **Service set:** the running set = defaults − `OC_EXCLUDE_RUN_SERVICES` + `OC_ADD_RUN_SERVICES`, so `OC_ADD_RUN_SERVICES: collaboration` must not be cancelled by an `OC_EXCLUDE_RUN_SERVICES` that still names `collaboration` — EXCLUDE is `"idp"` only.
  - **WOPI on the DS:** `WOPI_ENABLED: "true"` — the image default is `false`, which answers `/hosting/discovery` 404. The DS keypair is auto-generated (regenerable).
  - **Secret chain:** `COLLABORATION_WOPI_SECRET` = the shared value, and `OC_JWT_SECRET` = the same shared 1P value. Without `OC_JWT_SECRET`, auth mints reva tokens with the init-generated yaml `token_manager.jwt_secret` while collaboration verifies with `COLLABORATION_JWT_SECRET` → `DismantleToken` "token signature is invalid" → DS checkFileInfo 401. Changing it invalidates existing sessions → one-time user RE-LOGIN.
  - **Mixed content:** the DS emits browser-facing cache URLs (`/cache/files/data/<id>/Editor.bin`) with an **http:// scheme**, delivered over the WOPI session websocket, and an https page blocks the fetch → "Prenos ni uspel!" + an empty document (upstream [ONLYOFFICE/DocumentServer#2186](https://github.com/ONLYOFFICE/DocumentServer/issues/2186) class; the DS ignores `X-Forwarded-Proto` when building these URLs — no server-side knob exists). The fix is the Traefik middleware `onlyoffice-csp` (`Content-Security-Policy: upgrade-insecure-requests` response header) attached to the office router — the browser upgrades every http:// request on this origin to https://.
  - **Gotcha:** `opencloud.yaml` is a persistent bind mount; `opencloud init` does NOT regenerate it, so stale yaml values persist forever — **runtime config comes from env overrides** (envdecode), not from that file. Don't debug yaml contents; verify the container env.
  - **`COLLABORATION_APP_INSECURE`** is the mapped env var for `collaboration.app.insecure` ("Skip TLS certificate verification when connecting to the WOPI app") — upstream [app.go](https://github.com/opencloud-eu/opencloud/blob/v7.4.0/services/collaboration/pkg/config/app.go). Load order is config file → defaults → **env last = highest precedence** ([parse.go](https://github.com/opencloud-eu/opencloud/blob/v7.4.0/services/collaboration/pkg/config/parser/parse.go)); default `false`, and nothing propagates `OC_INSECURE` into this flag ([defaultconfig.go](https://github.com/opencloud-eu/opencloud/blob/v7.4.0/services/collaboration/pkg/config/defaults/defaultconfig.go)). Keep `"false"`: `office.kogler.si` presents a valid public Let's Encrypt cert at the Traefik edge → verify it. `OC_INSECURE:"true"` is a separate knob (OpenCloud's internal HTTP/TLS stance), uncoupled here.

### Phase 1: ONLYOFFICE on Debian Desktop

oldsrv runs **Debian as its host OS** — family desktop uses ONLYOFFICE:

| Component | Role |
|-----------|------|
| **ONLYOFFICE Desktop Editors** | Native Linux office suite, Ribbon UI, full `.docx`/`.xlsx`/`.pptx` |
| **OpenCloud sync client** | Files sync automatically to OpenCloud (AppImage, manual install) |
| **ttf-mscorefonts-installer** | Calibri, Cambria for document fidelity |

> ⚠ **Debian 13 only:** the official OpenCloud sync client (`opencloud-eu/desktop`) ships as an **AppImage only** — no apt repo. **Decision:** install it manually per client; Ansible preps **`libfuse2t64`** (FUSE). Auth via native **OIDC → Authentik** (multi-redirect provider + CSP), not Traefik Forward-Auth.

> ⚠ The ONLYOFFICE apt repo signs `squeeze/Release` with the
> **Ascensio key `E09C A29F 6E17 8040 EF22 B409 8320 CA65 CB2D E8E5`** (rsa4096, good-signature verified
> against `dists/squeeze/InRelease`). The published `onlyoffice.key` file only carries the two 2014 keys
> and does NOT include Ascensio — so the `office` role fetches it from a keyserver instead of the
> stale key file. `squeeze` codename itself is CORRECT (ONLYOFFICE uses it for all Debian).

- No Wine, no VM, no Windows license — fully native Debian
- Zero cloud dependency for editing (works offline)
- AI queries route through the LiteLLM spine ([`services-ai.md`](services-ai.md)) — **consumers never call an engine directly**: generation lands on spark's vLLM, the pinned embed/rerank/STT legs on oldsrv's GPU, and anything non-Vulkan stays on the CPU fallback

### MS Office via Open WebUI MCP Tools (Windows 11 Clients)

> Live Word/Excel/PowerPoint interaction from the **same browser UX as Open WebUI** — MS Office apps become **MCP tool-servers**, surfaced into Open WebUI over the Headscale tunnel.
>
> **`client/office-bridge/` is a first-class, tracked repo component**: it is the SSOT
> package for the native Windows/COM Office MCP bridge — version-pinned (PyPI + binary SHA256), tracked
> by Renovate (`pip_requirements` on its `requirements.txt`), **deployed per-client over the Headscale
> tunnel by `install.ps1`/`update.ps1`, NOT via Ansible** (by design: Ansible manages server Docker, not
> Windows endpoints). It is not an untracked/adjacent folder — it is documented in `docs/index.md`,
> `scripts/README.md`, `IaC/README.md` and this doc, and cross-referenced by Renovate. See the folder
> README for the exact Headscale/token/OWUI-registration contract.
>
> **OpenCloud = file SSOT · Open WebUI = chat/UX SSOT.** AnythingLLM and LocPilot are **retired**.

| Component | Role |
|-----------|------|
| **Open Web UI** | SSOT chat + RAG + all tools (browser UX) |
| **OpenCloud** | File SSOT — Office files round-trip here (`file.kogler.si`) |
| **Office MCP bridge** (client PC) | Native Windows per-client MCP server exposing Word + Excel + PowerPoint tool-groups via COM to the running Office apps |
| **LiteLLM gateway** | Model backend: a function-calling model from the consumer's allow-list (local spark tier today, paid upstreams only where an allow-list permits) |

**Topology (two edit paths):**

| Channel | What you get | Latency | Where it runs |
|---------|--------------|---------|---------------|
| **Windows COM MCP bridge** | Live edits pushed into the *open* Office app (Word/Excel/PowerPoint) | ms–s | native on the **Windows 11 client**, next to the running app |
| **Server-side file tools** | File regenerated by python-docx/pptx/openpyxl → OpenCloud → sync client | s–tens of s | server (Linux-capable, no Office/license needed) |

- **Windows 11 clients:** the MCP bridge drives Word/Excel/PowerPoint live via COM. Distributed from the **first-class repo component `client/office-bridge/`** (version-pinned) — served read-only over Headscale and pulled by `install.ps1` (this is a per-client install, **not** an Ansible-deployed server service). See [`client/office-bridge/`](../client/office-bridge/) for the package.
- **Linux clients:** server-side python-docx/pptx/openpyxl only — results land in the synced OpenCloud folder, opened in ONLYOFFICE. No live COM.
- **Exposure:** MCP bridges bind to the **Headscale interface only**, token-auth, never public.
- **One unified bridge per client** is the goal (Word+Excel+PPT tool-groups on one Headscale endpoint + one token); feasibility of unify/extend beyond `@ykuwai/ppt-mcp` (PPT) is open.

### Email Automation

| Component | Role |
|-----------|------|
| **n8n** (self-hosted, Docker) | Automation workflows with local LLM node — **also the observability alert router** (see [`observability.md`](observability.md)) |
| **Gateway LLM** | Drafting / summarization model — reached through the gateway, never as a direct engine URL |
| **IMAP/SMTP** | Connects n8n to email inbox |

Workflow: n8n monitors inbox → new email triggers LLM → draft saved for human review → approve and send.

### Presentation Generation

| Component | Role |
|-----------|------|
| **Live (`@ykuwai/ppt-mcp`)** | MCP bridge → running `powerpoint.exe` via COM (150+ tools), edits open slides in real time |
| **python-pptx** (server) | Compiles text into native `.pptx` → OpenCloud (Linux/standalone path) |
| **Marp** (alternative) | Markdown → HTML/PDF slide decks |

Word + Excel get matching MCP tools by parallel/extending the Office MCP bridge, so all three Office apps
are covered.

---

## Model Recommendations

Model choice + routing are owned by the AI platform SSOT — see [`services-ai.md`](services-ai.md)
(§LLM routing & keys, incl. the local-model recommendations for office/voice workloads) and
[`hardware-gpu.md`](hardware-gpu.md) for the RX 7600 VRAM budget.

---

## Privacy

- All documents, emails, and presentations **never leave the home network**
- n8n workflows are self-hosted
- Open WebUI + Qdrant = RAG; OpenCloud = file store; Office MCP bridges are Headscale-only
- No API keys, no subscription costs, no data sharing

---

## Cost Comparison

| Solution | Cost |
|----------|------|
| Microsoft Copilot Pro | €22/user/month |
| ChatGPT Plus | €20/month |
| **Local (this plan)** | **€0/month** (after hardware) |

Phase 1: €0 additional. Phase 2 hardware is one-time capital expense.

---

## Not Yet Implemented

Depends on:
1. oldsrv with GPU operational
2. The gateway reachable and the office consumer's allow-list carrying a function-calling model
3. n8n Docker setup
4. **Office MCP bridge via Open WebUI** — Windows COM bridge + server-side python-docx/pptx/openpyxl path
5. ONLYOFFICE on oldsrv desktop

AnythingLLM + LocPilot are **retired**: their functionality lives in the Open WebUI MCP path.