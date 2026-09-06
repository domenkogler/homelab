---
title: AI Platform — Chat, RAG & Agents (LiteLLM / Open WebUI / OpenClaw / Docling / Qdrant)
role: detail
domain: services
status: active
tags: [services, ai, llm, llm-gateway, rag, agents, okf, vector]
---
# AI Platform — Family Web AI Layer

> **Role:** Stack doc (detail) — the family-facing web AI platform. LLM routing (LiteLLM), chat + RAG UI
> (Open WebUI ×2), agent orchestration (OpenClaw + dual coding harness), OCR ingestion (Docling), and the
> **Qdrant** vector store. This is the canonical owner for the **2026-08-27 AI modularisation decisions
> (HD-267)**: Qdrant-instead-of-PGVector · Forgejo-OKF wiki as knowledge SSOT · dual pi.dev+DSH harness.
> It is the **single merged view** that replaces both `ai-brainstorming.md` (deleted, folded here) and the
> pre-HD-267 PGVector-centric v2 text.
>
> Desktop/office AI (ONLYOFFICE, LocPilot, Word, email, presentations) stays in
> [`services-office.md`](services-office.md); this doc covers everything browser/agent-facing.
>
> **Links to:** `services-office.md`, `hardware-gpu.md`, `services-authentik.md`, `services-traefik.md`,
> `deployment-secrets.md`, `services.md`
> **Linked from:** `services.md`, `index.md`

> **Status:** VPS platform **live since 2026-08-22** (Phase 1): LiteLLM spine, Open WebUI x2
> (`chat.kogler.si` public family / `ai.kogler.si` internal tailnet-only -- v2/Hi-248 split), Docling,
> OpenClaw up on the VPS. **PGVector is being replaced by Qdrant** (HD-267; ⏳ migration/backtest +
> re-index before the live swap). ⏳ deploy-gated: Ollama + Immich-ML on the oldsrv GPU (Phase 3), Qdrant
> cutover, the OKF-wiki repos, and the RAG/agent live-tuning behind them. Supersedes the AnythingLLM path.
> Tracked via `todo.md` HD-1xx (`source: services-ai`).

---

## 1. Philosophy

One **LiteLLM endpoint** is the spine. Every consumer (Open WebUI ×2, OpenClaw, Qdrant's embed/rerank,
the dual coding harness) talks to it and **never sees an upstream provider key**. All external
**generation** uses a single `openrouter_api` key; **embeddings/rerank are local on spark** (bge-m3
1024-dim + bge-reranker-v2-m3 via Triton, 2026-09-06 — Cohere subscription retired). Model routing,
cost, rate limits, and credential management are centralized in one place.

**Two further invariants from HD-267:**
- **The vector store is independent of Open WebUI.** Qdrant stands alone (hybrid dense+sparse BM25) so the
  retrieval layer is not locked to any single UI — an AI interface is just a swappable shell (HD-267 ①).
- **Git is the source of truth for knowledge; the index is a rebuildable cache.** Forgejo OKF-llm-wiki
  repos hold the canonical `.md`; Qdrant indexes them and can always be rebuilt from the git floor
  (HD-267 ②).

---

## 2. Architecture

The system is split into **three strictly isolated network zones** on the VPS (no AI container touches the
host OS directly):

```
    [ PUBLIC INTERNET / WAN ]   (all ports closed except 443)
        │
        ▼
 ┌──────────────────────────────────────────────────────────────┐
 │ ZONE 1 — EDGE (public network)                               │
 │   Traefik (SSL, certs, routing)  ·  Authentik (OIDC, 2FA)    │
 └───────────────┬──────────────────────────────────────────────┘
                 ▼  (verified JWT identity)
 ┌──────────────────────────────────────────────────────────────┐
 │ ZONE 2 — DATA CORE (db-internal + Forgejo + OpenCloud)       │
 │   Forgejo Git  (canonical .md knowledge, OKF repos)          │
 │   OpenCloud    (raw asset ingress: PDFs, scans, docs)        │
 └───────────────┬──────────────────────────────────────────────┘
                 ▼  (internal API / MCP)
 ┌──────────────────────────────────────────────────────────────┐
 │ ZONE 3 — AI SANDBOX (services-internal)                      │
 │   Open WebUI ×2  ·  pi.dev  ·  DSH  ·  LiteLLM               │
 │   Qdrant (hybrid vector)  ·  rag-mcp (reader)  ·  Forgejo MCP │
 └──────────────────────────────────────────────────────────────┘
```

**Docker networks (HD-307):** OWUI-public on `traefik-public` (the `chat` route); OWUI-internal NOT
edge-routed -- tailscale-sidecar Pattern A; the AI harnesses (pi.dev, DSH) on `services-internal` via
netns tailscale serve (Pattern A); OpenClaw, Docling on `services-internal`; **Qdrant** on `db-internal`
(alongside the postgres/litellm-db); ~~Ollama on `llm-backend`~~ (HD-59, **removed 2026-09-06** — inference on spark). No host `0.0.0.0` port binds —
overlays + Traefik for the public plane, tailscale serve for the management plane (Flaw C / HD-62;
Patterns A/B in [network-vpn.md](network-vpn.md)).

> **Ollama isolation (HD-59):** Ollama has no native server auth, so it sits on the dedicated
> `triton-backend` overlay reachable **only by LiteLLM** (the spine), NOT on the flat `services-internal`
> network (same isolation as the removed Ollama, HD-59).

---

## 3. Components

| Service | Role | Network | Notes |
|---------|------|---------|-------|
| **LiteLLM** | LLM gateway / router | `services-internal` **+ `llm-backend`** | OpenAI-compatible spine (v2, Postgres-backed, HD-247). Only component holding upstream keys. Joins `llm-backend` to reach Ollama; serves embed/rerank to Qdrant/rag-mcp. |
| **Open WebUI ×2** (v2, HD-248) | chat + RAG UI | `traefik-public` / tailnet sidecar | `chat.kogler.si` PUBLIC (family, limited keys, **OKF Family-Manuals KB only**); `ai.kogler.si` INTERNAL (tailnet-served; you+wife, agent keys, `rag_internal`). Auth = Authentik OIDC both. |
| **Qdrant** | **hybrid vector store (HD-307)** | `db-internal` | Standalone Rust DB (dense+sparse BM25), **independent of OWUI built-in RAG**. Replaces PGVector. Vector dimension locks at first ingest (1536). Add a snapshot/backup seam. |
| **Forgejo (wiki repos)** | **knowledge SSOT** (HD-307) | `db-internal` / git | OKF `.md` repos per owner; git = truth; Qdrant = rebuildable cache. |
| **kapa-inspired-rag-mcp** *(planned)* | MCP hybrid reader | `services-internal` | On @wiki-<x> query: hybrid search in Qdrant → top-20 → Cohere rerank (via LiteLLM) → top-5 clean markdown. |
| **Forgejo MCP** *(planned)* | MCP read/write `.md` | `services-internal` | Bridge to the OKF wiki repos; agents read/write notes + open PRs. |
| ~~Ollama~~ *(removed 2026-09-06)* | ~~Local LLM inference~~ | ~~`llm-backend`~~ | **Removed** — inference consolidated on spark (Triton). No Ollama/ROCm on oldsrv. |
| **Triton Inference Server** *(planned, spark)* | NVFP4 local inference | `triton-backend` | On the **spark** GB10 node (HD-335) — **the sole local-inference tier** (2026-09-06). Serves the NVFP4 model set (Nemotron-30B, Qwen3-Next-80B, Llama-3.3-70B, Qwen3-Coder-Next-80B) + bge-m3/reranker + Whisper + XTTS/Piper. Reachable only by LiteLLM — same isolation as the removed Ollama (HD-59). **Model repo = Ansible-managed** (per-model `config.pbtxt` J2 templates + idempotent NVFP4 conversion + strict `1/` layout, `/srv/models/spark/`; see `hardware-spark.md` §Bring-up). **Model-catalog sync = git SSOT `models.yml` → LiteLLM DB** (reconciler: onboard upserts, offboard scoped-deletes git-sourced models only + same-change `litellm_scoped_keys` cleanup; manual OpenRouter models untouched). GB10 bring-up reference: [`dgx-spark-ml-guide`](https://github.com/martimramos/dgx-spark-ml-guide). |
| **Mem0** *(planned, spark)* | Long-term memory for OWUI | `services-internal` | Backed by **Qdrant** (HD-267/268). Per-user/per-project scoping via `user_id = <openwebui-user-id>-<model-id>`; `mem0.search(query=…, user_id=…)`. |
| **OpenHands** *(planned, spark)* | Agentic coding harness | tailnet sidecar | A third coding cockpit alongside pi.dev + DSH (HD-307/250); scoped LiteLLM key + PR-only Forgejo token. |
| **Docling** | OCR / document understanding | `services-internal` | CPU. Multilingual OCR (Slovenian scans). |
| **OpenClaw** | AI agent / orchestration | `services-internal` | Version pinned. Models → LiteLLM scoped key. |
| **pi.dev + DSH** *(dual harness, HD-307)* | DevOps/IaC coding cockpits (C# + IaC) | `services-internal` + tailnet sidecar | Concrete IaC services: **`pi-dev`** (pi coding-agent container, npm `@earendil-works/pi-coding-agent` + `pi-web-access`) and **`dsh`** (DeepSeek Harness `runzhliu/deepseek-harness`). **Both run side-by-side** (supersedes HD-250's "DSH replaces pi.dev"). Each consumes a scoped LiteLLM key (`pi-harness_openai_api` + `dsh_api`) + a PR-only Forgejo token; propose homelab via Forgejo PRs (PR-only, no-merge); 443 egress accepted (recorded risk). DSH WebUI = Pattern-A tailnet serve (:3080); pi = TUI/CLI (no web port). Compared by feature-keyed bake-off. |

---

## 4. LLM routing & keys

- **One endpoint:** Open WebUI ×2, OpenClaw, pi.dev, DSH, and Qdrant's embed/rerank authenticate to
  **LiteLLM only**, via per-consumer **scoped virtual keys** (HD-247) — they never hold `openrouter_api`,
  `cohere_api`, or the master key.
- **Generation → Open Router:** one `openrouter_api` key (api → credential) reused for **all** external
  chat/LLM models, declared in LiteLLM's `config.yaml`. The coding-embed path specifically routes
  **DeepSeek via OpenRouter** (the brainstorm's pi serve / DSH backend) + local Ollama; any model listed
  on OpenRouter is selectable through the one LiteLLM dropdown.
- **Embeddings → local spark (2026-09-06):** bge-m3 (1024-dim) via Triton; Cohere subscription retired.
  Previously Cohere embed-v4 multilingual @1536 (accepted 2026-08-16 — superseded).
- **Rerank → Cohere:** `cohere/rerank-v4.0-pro` external via LiteLLM `/rerank`.
- **Local models:** Ollama listed via LiteLLM so family sees local + cloud in one dropdown; local is
  default where privacy/offline matters. **spark (HD-335)** adds the **Triton** NVFP4 set + local embeddings
  (bge-m3/reranker) as further LiteLLM backends (details in [`hardware-spark.md`](hardware-spark.md)).

**Local model recommendations** (office/voice workloads, moved from `services-office.md` — HD-199
boundary trim; this doc is the platform SSOT for model guidance):

| Model | VRAM | Best For |
|-------|------|----------|
| **Llama 3.1/3.2 8B** | ~6 GB | Everyday office, email drafting, summarization (oldsrv RX 7600) |
| **Qwen 2.5/3.5 7B–14B** | ~6–12 GB | Complex document structuring, code generation (oldsrv RX 7600) |
| **Phi-4 14B** | ~10 GB | Reasoning, logic, Microsoft workflow drop-in (oldsrv RX 7600) |
| **NVFP4 30–80B set (Nemotron-Lightning-30B, Qwen3-Next-80B, Llama-3.3-70B, Qwen3-Coder-Next-80B)** | fits in **spark 128 GB unified** | Heavy programming / local reasoning — served by **Triton** on `spark` (HD-335, [`hardware-spark.md`](hardware-spark.md)) |

**1Password (`Homelab-ansible`) items — see [`deployment-secrets.md`](deployment-secrets.md):**

| Item | type → `field=` | Used by |
|------|-----------------|---------|
| `openrouter_api` | api → `credential` | LiteLLM (all external LLM generation) |
| ~~`cohere_api`~~ *retired 2026-09-06* | — | **Removed** — embeddings/rerank local on spark (bge-m3/1024 + bge-reranker), Cohere subscription cancelled. |
| `litellm_master_key` | api → `credential` | admin/bootstrap ONLY (HD-247) |
| `litellm_db` | db → `password` | litellm-db runtime DB (models-in-DB) |
| scoped keys (`owui-public-chat_api`, `owui-public-rag_api`, `owui-int-wife_api`, `owui-int-owner_api`, `dsh_api`, `openclaw-litellm_api`, `rag-int-svc_api`) | api → `credential` | per-consumer glow-minted keys (HD-247) |
| `openwebui_secret` | password → `password` | Open WebUI session/encryption secret |
| `qdrant_db` | api → `credential` | Qdrant hybrid vector store (HD-268; no username, single static API key via `QDRANT__SERVICE__API_KEY`) |

> Fail-closed secrets: no `default('')` — a missing item fails the render loudly (HD-65/76).

**Scoped consumer keys (v2, HD-247)** — Postgres-backed, models Admin-UI-managed; bootstrap glue mints
the per-consumer virtual keys (fail-closed lookups thereafter), specs SSOT in `group_vars/vps.yml`:
`owui-public-chat_api` (OWUI-public chat) · `owui-public-rag_api` (public RAG, embed+rerank) ·
`owui-int-wife_api` / `owui-int-owner_api` (internal) · `dsh_api` (DSH) · `openclaw-litellm_api`
(OpenClaw) · `rag-int-svc_api` (OWUI-internal RAG). Starting budgets/durations Admin-UI-editable.

> 📋 Deploy checklist: [`deployment-ai-stack-secrets.md`](deployment-ai-stack-secrets.md).

---

## 5. Knowledge SSOT & RAG pipeline (HD-267)

### 5a. Knowledge SSOT = Forgejo OKF-llm-wiki (HD-267 ②)
- **Git is the source of truth** for `.md` knowledge. Private per-owner repos under Forgejo:
  `wiki-druzina` (family) · `wiki-osebno-moj` (owner-personal) · `wiki-sluzba-moj` (owner-work) ·
  `wiki-osebno-zena` (wife-personal) + a public KB cohort.
- **Every record = one `.md`** with OKF YAML front-matter: `title`, `type`, `tags`, `generated_at`.
- **`*-generated.md` are explicitly outside the corpus** (generated docs are never indexed as source).
- **OpenCloud remains the raw-asset ingress** (PDFs, scans, docs) — the *source* of documents, not the
  index SSOT. Large binaries are referenced, not embedded in the wiki.
- **The vector index / Qdrant is a rebuildable cache** over that git floor — it can always be rebuilt;
  it is never the source of truth.

### 5b. Retrieval RAG results (rebuildable cache)
1. **Ingest:** raw assets from **OpenCloud** (WebDAV/CIFS live Box) → optional **Docling** OCR →
   canonical `.md` lands in the Forgejo wiki repo (git front-matter).
2. **Index:** chunk → embed via **bge-m3 (1024 dims)** on spark (Triton) through LiteLLM → write dense+sparse
   vectors to **Qdrant**.
3. **Retrieve:** hybrid BM25+vector query → kapa-inspired-mcp reads Qdrant → top-20 candidates → **Cohere
   rerank v4.0-pro** via LiteLLM → **top-5 clean markdown** context → LiteLLM model answers.

**Decided retrieval/ingestion parameters** (RAG knobs):
| Parameter | Decided value |
|-----------|---------------|
| Extraction | Docling only (`CONTENT_EXTRACTION_ENGINE=docling`, `DOCLING_SERVER_URL=http://docling:5001`) |
| Embeddings | **bge-m3, 1024 dims**, via Triton on spark (LiteLLM openai-compat, scoped rag key) — Cohere retired |
| Reranker | Cohere rerank v4.0-pro external via LiteLLM `/rerank` — same scoped key |
| Hybrid | ON default (dense+sparse BM25) |
| Retrieval | 20 candidates → rerank → top 5, threshold 0 |
| Chunking | token-based 512/64 (`RAG_TEXT_SPLITTER=token` mandatory) |
| Config ownership | `ENABLE_PERSISTENT_CONFIG=false` (env = SSOT) |
| Knowledge split | Public = Family-Manuals KB only; internal = personal/wife-work corpus |
| Vector index | Qdrant, **1024-dim** dense (+sparse), dimension locks at first ingest (1536→1024 free: nothing RAG'd yet) |

> **Dimension lock-in (HD-267 / ported from HD-246):** the vector dimension freezes at first ingest;
> changing embedding model/dims later = full re-ingest + backtest. **1024 chosen (bge-m3) — 2026-09-06**; 1536 Cohere superseded.

> **Backup (HD-307):** Qdrant is a **rebuildable cache** — so its backup policy is *relaxed* vs PGVector
> (PGVector held "irretrievable metadata"). The irrecoverable source is the **Forgejo OKF wiki** (the SS),
> so backup focuses on git + the raw-asset ingress; Qdrant is re-indexed from the wiki on loss. Still add a
> Qdrant snapshot seam for iteration speed, but it is NOT the metadata-fate risk class it was under
> PGVector. Open WebUI + OpenClaw config/state → Kopia.

> **Qdrant `read_only` snapshots gotcha (HD-271-followup, live 2026-08-28):** the compose sets
> `read_only: true` (container-hardening, HD-202), so qdrant 1.12.4 **cannot create its snapshots dir
> at startup in the RO rootfs** → panic `Can't create Snapshots directory: Read-only file system` at
> `toc/mod.rs:100` → crash-loop (`Restarting(101)`). Fix: point the snapshots dir INSIDE the writable
> storage bind via `QDRANT__STORAGE__SNAPSHOTS_PATH: /qdrant/storage/snapshots` (verified live: starts
> clean, `Up (healthy)`; dir auto-created on the bind). Keep `/snapshots` REST export + Kopia-backed
> host bind as the backup seam (backup.md): this env must stay in the compose template.

### 5c. Workflows (operational recipes)

The AI layer is a **swappable shell over a git-SSOT + vector-cache floor** — three canonical flows:

**A) Ingest a large document (automated, n8n):**
1. Drop a 300-page manual into an OpenCloud **“import to RAG”** folder.
2. **n8n** detects the file and copies it into the `/sources/` dir of the target wiki repo on Forgejo.
3. n8n (or a hook) chunks it, embeds via **LiteLLM** (cohere/embed-v4.0), and writes the **dense+sparse**
   vectors to Qdrant tagged with the project ID — ready for hybrid search immediately.

**B) Edit docs from the web (HITL, human-in-the-loop):**
1. Log into **Open WebUI** (WAN/Tailscale + Authentik), pick a **pi-agent** model.
2. Prompt eg. “*V @wiki-sluzba dodaj nov konfiguracijski port 9090 v indeks*”.
3. OWUI calls **pi serve** over the internal network.
4. The agent edits the `.md`, **lints the OKF header** (title/type/tags/generated_at), then opens a
   **Pull Request via Forgejo MCP** on your local Forgejo.
5. You later `git pull` on your WSL laptop, visually accept the PR and **deploy with Ansible** to prod VPS.

**C) Identity-aware orchestration (OWUI as orchestrator):**
- OWUI reads the Authentik JWT and **dynamically shows only the MCP tools + wikis the logged-in group is
  allowed** (e.g. `groups: ["admin", "sluzba"]` → role-filtered tools). Open WebUI is not a monolithic
  app but a router over the permissioned corpus. (Detail from the brainstorm — mechanism is a follow-up
  task under HD-307.)

**Elastic survival:** because knowledge is plain OKF `.md` in git and the index is a rebuildable Qdrant
cache, if Open WebUI goes away tomorrow the whole structure + hybrid RAG + coding agents keep working via
the WSL pi.dev terminal.

**D) Mem0 long-term memory (planned, spark — HD-335):** user-scoped memory for Open WebUI,
backed by **Qdrant** (HD-267/268). Per-user/per-project isolation via the OWUI identity split:

```python
user_id = body.get("user", {}).get("id")        # OWUI user id (Authentik identity)
model_id = body.get("model")                     # current Persona/Project (model) id
mem0_custom_user_id = f"{user_id}-{model_id}"     # per-user × per-project memory scope
mem0.search(query=user_prompt, user_id=mem0_custom_user_id)   # inject relevant context
```

- Scoping: each (user, model) pair gets its own memory namespace — no cross-user/project leakage.
- Store: Qdrant collection; rebuildable (same cache class as the RAG index under HD-267 ②).
- Full onboarding (compose/registry/edge) is tracked under HD-335.

---

## 6. Auth & exposure
- **`chat.kogler.si` is public** (renamed from `ai.` -- v2, HD-248), behind **Authentik OIDC** (native
  SSO, per-person) + **`crowdsec-only`** middleware at the Traefik edge (internet-facing → Flaw A /
  HD-60). Holds ONLY capability-limited credentials: family-chat + embed keys, no agents.
- **`ai.kogler.si` is the INTERNAL instance** (tailnet-served via Pattern-A sidecar; public DNS record
  dropped/repointed). You + wife; agent-capable keys; `rag_internal`.
- **Capability-tiering posture:** internet-facing = limited capability only; full power behind tailnet.
  New admin/UI surfaces default tailscale-first ([security.md](security.md) §Capability-tiering,
  [network-vpn.md](network-vpn.md) Patterns A/B).
- Per-person history follows the HD-51 identity model; no shared admin login.

## 7. Integrations
| Integration | How |
|-------------|-----|
| **Open WebUI ↔ OpenClaw** | Register OpenClaw as a LiteLLM model/provider → chatting to the “OpenClaw” model in the UI invokes the agent (**internal instance only; public keys exclude agents**). No bespoke glue. |
| **pi.dev / DSH ↔ LiteLLM/Forgejo** *(dual)* | Each harness consumes a scoped LiteLLM key; propose via Forgejo PRs only (branch-protected main, no merge rights). |
| **Qdrant ↔ rag-mcp ↔ OWUI** (HD-307) | kapa-mcp retrieves via Qdrant + Cohere rerank, returns top-5 markdown to OWUI |
| **Forgejo MCP ↔ wiki** | agents read/write OKF `.md`, open PRs; never arbitrary FS access |
| **OpenCloud ↔ RAG ingress** | raw assets (live Box WebDAV, read-only) → Docling → wiki (git floor) |
| **OpenClaw ↔ OpenCloud** | **WebDAV skill** reads/writes family files (summarize, organize, OCR a scan via Docling, draft replies). |
| **Open WebUI ↔ MS Office** | Office MCP bridges (Windows 11 clients) surface Word/Excel/PowerPoint as **tools** into OWUI over the Headscale tunnel — live COM edits; server-side python-docx/pptx/openpyxl path for Linux. See [`services-office.md`](services-office.md) (HD-106–111). |

## 8. Security & operating notes
- **No host port binds** (Flaw C / HD-62): overlays + Traefik only; loopback-only if ever needed.
- **Version pinning** (HD-61/71): pin LiteLLM, Open WebUI, Docling, **Qdrant**, OpenClaw (young project).
  Keep Renovate tracking.
- **VRAM/RAM:** spark = 128 GB unified (sole inference tier); oldsrv RX 7600 = Sunshine encode only; Docling on CPU; size chat models
  ~7–8B q4; keep `keep_alive` sensible (see `hardware-gpu.md`).
- **AnythingLLM + LocPilot removed** for the family web UI — replaced by MS Office MCP path (HD-108).

## 9. Decision log
| # | Decision | Date |
|---|----------|------|
| 1–17 | (original v2 lock) — Cohere embed-v4 multilingual · `ai.`→public→internal · OpenClaw pinned · no host binds · single openrouter · LocPilot kept/AnythingLLM removed · OpenCloud file SSOT · Office MCP · Docling-only OCR · RAG stack locked (PGVector) · two-instance OWUI · capability-tiering · LiteLLM v2 spine · public=Family Manuals · n8n internal · DSH · embeddings uniform. | 2026-08-16 → 08-26 |
| **18** | **Vector store = Qdrant** (hybrid dense+sparse, standalone Rust) — **replaces PGVector**; re-opens HD-246 store. Independent of OWUI. | 2026-08-27 |
| **19** | **Forgejo OKF-llm-wiki = knowledge SSOT**; Qdrant = rebuildable cache; per-owner private repos; OKF YAML front-matter; `*-generated.md` outside corpus. | 2026-08-27 |
| **20** | **Dual harness pi.dev + DSH** (supersedes HD-250's "DSH replaces pi.dev"); feature-keyed bake-off; agents via MCP-git/wiki, never FS. | 2026-08-27 |
| **21** | IO/embedding stay cohere/embed-v4 @1536; public corpus = Family Manuals only; wife-work corp internal-only. | 2026-08-26/27 |
| **22** | **spark (ThinkStation PGX / GB10) replaces the old Phase-2 Ryzen/R9700 build (HD-42 superseded).** Headless Triton inference node + NVFP4 model set + local bge embeddings; **Mem0** (OWUI memory on Qdrant) + **OpenHands** (agentic coding) onboard on spark. HD-335. | 2026-09-06 |
| **23** | **Inference consolidated on spark — single local-inference tier (2026-09-06).** All generation/embeddings/rerank/STT/TTS run on spark (Triton, GB10). **No Ollama/ROCm on oldsrv** (amd_rocm role dies, HD-318 unblocks). oldsrv GPU = **Sunshine gaming encode first, with immich-ML as a pause-able GPU batch consumer** (already GPU-templated; Sunshine prep-commands `docker pause/unpause immich-ml` enforce gaming-first — no CPU fallback needed; CPU path reserved only if ONNX-GPU proves fragile). **Cohere subscription retired** — bge-m3 (1024) + bge-reranker-v2-m3 replace embed-v4/rerank (Qdrant 1536→1024 free: nothing RAG'd yet). Voice = whisper-turbo + XTTS/Piper **pinned resident on spark, no fallback**. | 2026-09-06 |

> The whole 3-zone / OKF / Qdrant / MCP architecture (previously `ai-brainstorming.md`) is **folded into
> this doc**; that file is **deleted** (HD-307 lifecycle).

## 9b. Coding plane — agent memory + orchestration (HD-336, 2026-09-06)

The **coding plane** (your dev work: IaC/Ansible, C#, React/Vue, homelab epics) is a **separate
plane from the family research plane** (OWUI/Docling/Qdrant/Mem0). It runs on **oldsrv**
(managed from the laptop), not the laptop itself.

### Memory — agent-memory.dev (per-project)

- **Decision (2026-09-06): agent-memory.dev = the coding-memory plane**; OpenViking deferred
  (AGPL-accepted, Docker-only, future unified-context candidate); Mem0 stays OWUI-plane.
- **One instance per project** (project = 1+ repos); records tagged project+repo.
- **Cross-project recall = opt-in, not default** (one-instance scoped; no collision).
- Runs on **oldsrv** (where coding agents live); data dirs under `~/.agentmemory/<project>`,
  ports 3111+N; MCP = `@agentmemory/mcp`; consolidation LLM key → **LiteLLM scoped key**.
- **Skills = git SSOT** (`skills/` + `sync-skills.sh`, HD-254), never a service.

### Runners / automation

- **ZeroClaw = system-management agent** (laptop primary + oldsrv standby; NOT VPS — too risky;
  oldsrv does NOT self-provision). Supervised approvals; MCP → agentmemory.
- **CrewAI = long/epic homelab coding orchestration with human-signaling** (every decision point
  = a mandatory stop). **Pilot starts only when the homelab is fully finished** (kill criteria:
  2-week vertical slice or abandon).
- OpenHands commits to **spark** (HD-335).

### VPS runner: rejected

A ZeroClaw agent on the VPS with fleet credentials = the largest attack-surface increase in the
homelab (contradicts §10 capability-tiering). Rejected 2026-09-06; oldsrv is the remote runner.
## 10. Not yet implemented
Depends on: oldsrv GPU + Ollama live · LiteLLM spine + `openrouter_api`/`cohere_api`/`litellm_master_key`
in 1Password · Authentik OIDC for OWUI · OpenCloud + `media` owner (HD-51) · **Qdrant service + `qdrant_db`
item (replacing PGVector)** · **Forge OKF wiki repos + Forgejo/pi MCP** · **dual harness bring-up**.
Implementation tasks: **HD-307** (doc + tails) / **HD-268** (IaC: Qdrant swap + OKF repos + dual harness) — see the repo [`todo.md`](../todo.md) backlog.