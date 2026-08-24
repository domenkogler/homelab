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

> 🟢 **IaC done, not yet live — ⏳ deploy-gated.** The office/AI toolchain (ONLYOFFICE on oldsrv desktop, Open WebUI MCP for Word/Excel/PPT) depends on oldsrv being live (Phase 3) and the AI stack (HD-100…111); this is the authoring spec, not a live system.

---

## Strategy

Office AI tools run on the **same oldsrv GPU** as voice assistant and Immich ML. The AI **platform**
(routing, models, keys) is owned by [`services-ai.md`](services-ai.md) — the LiteLLM spine is the only
path to Ollama/upstream providers; this doc covers only the office slice. VRAM management:
[`hardware-gpu.md`](hardware-gpu.md).

---

## Toolchain


### Family Device Stack (one document, any screen)

| Platform | File Syncing & Access | Document Editing (Word/Excel/PP) | Why This Works Best |
| :--- | :--- | :--- | :--- |
| **🌐 Web Browser** | OpenCloud Web Interface | **ONLYOFFICE Docs Server** (via WOPI) | Perfect for quick edits or when a family member is on a guest computer. |
| **💻 Windows 11** | **OpenCloud Desktop Client** for Windows | **Microsoft Office Suite** (Local) | Your files sync to a local folder, and MS Office opens them with maximum feature compatibility. |
| **🐧 Linux** | **OpenCloud Desktop Client** for Linux | **ONLYOFFICE Desktop Editors** | ONLYOFFICE preserves Microsoft formatting much better than LibreOffice or OpenOffice. |

> ✅ **Verified (`docs.opencloud.eu/dev`):** OpenCloud ships a native **`collaboration` service** that connects to ONLYOFFICE / Collabora / Microsoft **via WOPI** (no third-party glue). Not enabled by default — start manually with `opencloud collaboration server`. Key vars: `COLLABORATION_APP_PRODUCT=OnlyOffice`, `COLLABORATION_APP_ADDR` (editing app URL), `COLLABORATION_WOPI_SRC` (public WOPI callback), plus `OC_URL`, `OC_JWT_SECRET`, `OC_REVA_GATEWAY`, `MICRO_REGISTRY_ADDRESS`. [Docs](https://docs.opencloud.eu/docs/dev/server/services/collaboration/information/).

#### ONLYOFFICE Docs Server — deployment & auth decision (HD-166)

**What it is:** a WOPI-helper Docker container (`onlyoffice/documentserver`) that renders the in-browser editor for OpenCloud documents at `office.kogler.si`. Brings browser editing (Word/Excel/PPT) to the **"🌐 Web Browser" row** above — desktop sync/edit is unchanged (native ONLYOFFICE Desktop Editors / MS Office).

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
- **ONLYOFFICE** is a **background worker**: it never sees family logins. OpenCloud and ONLYOFFICE trust each other over **cryptographically signed WOPI calls** (shared `OC_JWT_SECRET`), so no `office_*` Authentik client is needed and the route is **not** behind Forward-Auth (it would break the editor's iframe/API calls).
- **Consequence for IaC (HD-166):** clear the Authentik Blueprint path — no provider, no app, no secret-egress item. Implemented: Traefik cert (``Host(`office.kogler.si`)``) + pinned `onlyoffice_version` (`9.3.0.1`) + `OC_ADD_RUN_SERVICES: collaboration` + `COLLABORATION_APP_*`/`WOPI_SRC` env on the opencloud compose + `opencloud-collab_password` (shared JWT, 1Password, same value on BOTH sides) + CSP `office.kogler.si` in frame-src/connect-src.

- **Live status 2026-08-24 (HD-166 tail, NOT closed):** stack deployed + healthy (onlyoffice-docs up, JWT+WOPI+collab env set, `office.kogler.si` 200), but owner round-trip shows `.txt` preview/edit/save works while **`.docx` fails — “No preview available … download instead”** (ONLYOFFICE editor never opens office docs). Suspected: OpenCloud `frontend.app_handler`/app-provider not authoring office MIME; `COLLABORATION_STORE=nats-js-kv` with **no NATS broker** (no registry/store); and rendered `collaboration.app.insecure: true` despite env `false`. See deployment-journal.md Phase 1.5 + plan/20260824-netredo/t1-report.md for the fix path (NATS/app-provider for office MIME, then re-test `.docx`).

### Phase 1: ONLYOFFICE on Debian Desktop

oldsrv runs **Debian as its host OS** — family desktop uses ONLYOFFICE:

| Component | Role |
|-----------|------|
| **ONLYOFFICE Desktop Editors** | Native Linux office suite, Ribbon UI, full `.docx`/`.xlsx`/`.pptx` |
| **OpenCloud sync client** | Files sync automatically to OpenCloud (AppImage, manual install — HD-52) |

> ⚠ **HD-52 (Debian 13 only):** the official OpenCloud sync client (`opencloud-eu/desktop`) ships as an **AppImage only** — no apt repo. **Decision (2026-08-18):** install the company manually per client; Ansible preps **`libfuse2t64`** (FUSE). Auth via native **OIDC → Authentik** (multi-redirect provider + CSP), not Traefik Forward-Auth.
| **ttf-mscorefonts-installer** | Calibri, Cambria for document fidelity |

- No Wine, no VM, no Windows license — fully native Debian
- Zero cloud dependency for editing (works offline)
- AI queries route through the LiteLLM spine ([`services-ai.md`](services-ai.md)) to local Ollama — consumers never call Ollama directly

### MS Office via Open WebUI MCP Tools (Windows 11 Clients)

> **HD-106–111.** Live Word/Excel/PowerPoint interaction from the **same browser UX as Open WebUI** — MS Office apps become **MCP tool-servers**, surfaced into Open WebUI over the Headscale tunnel. Supersedes AnythingLLM + LocPilot.
>
> **OpenCloud = file SSOT · Open WebUI = chat/UX SSOT.** AnythingLLM and LocPilot are **retired** (HD-108).

| Component | Role |
|-----------|------|
| **Open Web UI** | SSOT chat + RAG + all tools (browser UX) |
| **OpenCloud** | File SSOT — Office files round-trip here (`file.kogler.si`) |
| **Office MCP bridge** (client PC) | Native Windows per-client MCP server exposing Word + Excel + PowerPoint tool-groups via COM to the running Office apps |
| **LiteLLM / Ollama** | Model backend; function-calling model (e.g. Qwen, Claude via OpenRouter) for tool calls |

**Topology (two edit paths):**

| Channel | What you get | Latency | Where it runs |
|---------|--------------|---------|---------------|
| **Windows COM MCP bridge** | Live edits pushed into the *open* Office app (Word/Excel/PowerPoint) | ms–s | native on the **Windows 11 client**, next to the running app |
| **Server-side file tools** | File regenerated by python-docx/pptx/openpyxl → OpenCloud → sync client | s–tens of s | server (Linux-capable, no Office/license needed) |

- **Windows 11 clients:** the MCP bridge drives Word/Excel/PowerPoint live via COM. Distributed from a repo-owned `client/office-bridge/` (version-pinned, see HD-106) served over Headscale.
- **Linux clients:** server-side python-docx/pptx/openpyxl only — results land in the synced OpenCloud folder, opened in ONLYOFFICE. No live COM (see HD-107).
- **Exposure:** MCP bridges bind to the **Headscale interface only**, token-auth, no public (HD-109).
- **One unified bridge per client** is the goal (Word+Excel+PPT tool-groups on one Headscale endpoint + one token); feasibility of unify/extend beyond `@ykuwai/ppt-mcp` (PPT) is open — HD-110 research gates HD-111.

### Email Automation

| Component | Role |
|-----------|------|
| **n8n** (self-hosted, Docker) | Automation workflows with local LLM node — **also the observability alert router** (see [`observability.md`](observability.md)) |
| **Ollama** | LLM backend for drafting, summarizing |
| **IMAP/SMTP** | Connects n8n to email inbox |

Workflow: n8n monitors inbox → new email triggers LLM → draft saved for human review → approve and send.

### Presentation Generation

| Component | Role |
|-----------|------|
| **Live (`@ykuwai/ppt-mcp`)** | MCP bridge → running `powerpoint.exe` via COM (150+ tools), edits open slides in real time |
| **python-pptx** (server) | Compiles text into native `.pptx` → OpenCloud (Linux/standalone path) |
| **Marp** (alternative) | Markdown → HTML/PDF slide decks |

Word + Excel get matching MCP tools by parallel/extending the Office MCP bridge (HD-110/HD-111), so all three Office apps are covered — not just PowerPoint/LocPilot.

---

## Model Recommendations

Model choice + routing are owned by the AI platform SSOT — see [`services-ai.md`](services-ai.md)
(§LLM routing & keys, incl. the local-model recommendations for office/voice workloads) and
[`hardware-gpu.md`](hardware-gpu.md) for the RX 7600 VRAM budget.

---

## Privacy

- All documents, emails, and presentations **never leave the home network**
- n8n workflows are self-hosted
- Open WebUI + PGVector = RAG; OpenCloud = file store; Office MCP bridges are Headscale-only
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
2. Ollama + model downloads
3. n8n Docker setup
4. **Office MCP bridge via Open WebUI** (HD-111) — Windows COM bridge + server-side python-docx/pptx/openpyxl path
5. ONLYOFFICE on oldsrv desktop

AnythingLLM + LocPilot are **retired** (HD-108): their functionality moves into the Open WebUI MCP path.