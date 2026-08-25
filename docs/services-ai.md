---
title: AI Platform — Chat, RAG & Agents (LiteLLM / Open WebUI / OpenClaw / Docling / PGVector)
role: detail
domain: services
status: active
tags: [services, ai, llm, llm-gateway, rag, agents]
---
# AI Platform — Chat, RAG & Agents

> **Role:** Stack doc (detail) — family web AI platform: LLM routing (LiteLLM), chat + RAG UI (Open WebUI),
> agent orchestration (OpenClaw), OCR document ingestion (Docling), and the PGVector vector store.
> This is the **family-facing web AI layer**. Desktop/office AI (ONLYOFFICE, LocPilot, Word, email,
> presentations) stays in [`services-office.md`](services-office.md); this doc covers everything browser-facing.
> **Links to:** `services-office.md`, `hardware-gpu.md`, `services-authentik.md`, `services-traefik.md`,
> `deployment-secrets.md`, `services.md`
> **Linked from:** `services.md`, `index.md`

> **Status:** VPS platform **live since 2026-08-22** (Phase 1): LiteLLM spine, Open WebUI x2 (`chat.kogler.si` public family / `ai.kogler.si` internal tailnet-only -- v2 split, HD-248), Docling,
> PGVector, OpenClaw up on the VPS. ⏳ deploy-gated: Ollama + Immich-ML on the oldsrv GPU (Phase 3) and the
> RAG/agent live-tuning behind them. Supersedes the AnythingLLM path in `services-office.md`
> for the family web UI (AnythingLLM **removed**; **LocPilot kept** for Windows-Word inline only).
> Tracked via `todo.md` HD-1xx (`source: services-ai`).

---

## 1. Philosophy

One **LiteLLM endpoint** is the spine. Every consumer (Open WebUI, OpenClaw) talks to it and **never
sees an upstream provider key**. All external **generation** uses a single `openrouter_api` key;
**embeddings** are the one exception (Cohere embed-v4 needs its own `cohere_api` — OpenRouter carries
no embedding models). Model routing, cost, rate limits, and credential management are centralized
in one place.

---

## 2. Architecture

```
  chat.kogler.si (PUBLIC: CrowdSec + Authentik OIDC)     TAILNET (Headscale ACLs, Patterns A/B)
        | family browsers -- LIMITED keys only              | full-power keys (you + wife)
        v                                                  v
   OWUI-public --RAG--> PGVector.rag_public          OWUI-internal --RAG--> PGVector.rag_internal
        |            (Family Manuals KB ONLY)               |       (personal + wife work KBs)
        |                                                  |
        +------------> LiteLLM spine (:4000/v1) <-----------+-- DSH cockpit . OpenClaw gateway
                            |           |                  (all consumers: SCOPED virtual keys,
                            v           v                   master_key retired post-HD-247)
                      OpenRouter     Ollama* (llm-backend, Phase 3)
                      + Cohere embed/rerank   Docling (OCR ingestion, services-internal)

* Tailnet-exposed admin surfaces: litellm-ui . dsh . openclaw control . headplane (Patterns A/B -> network-vpn.md)
```

**Docker networks (v2):** OWUI-public on `traefik-public` (the `chat` route); OWUI-internal NOT edge-routed -- tailscale-sidecar Pattern A; DSH on `services-internal` (planned HD-250); LiteLLM, OpenClaw, Docling on `services-internal`; PGVector on `db-internal`; **Ollama on `llm-backend`** (HD-59). **No host `0.0.0.0` port binds** — overlays + Traefik for the public plane, tailscale serve for the management plane (Flaw C / HD-62; Patterns A/B in [network-vpn.md](network-vpn.md)).

> **Ollama isolation (HD-59):** Ollama has no native server auth, so it sits on the dedicated
> `llm-backend` overlay reachable **only by LiteLLM** (the spine), NOT on the flat `services-internal`
> network. LiteLLM's future compose joins `services-internal` (consumers) **+ `llm-backend`** (→ Ollama).

---

## 3. Components

| Service | Role | Network | Notes |
|---------|------|---------|-------|
| **LiteLLM** | LLM gateway / router | `services-internal` **+ `llm-backend`** | OpenAI-compatible spine. Own small DB (SQLite volume) for keys/spend. Only component holding upstream keys. Joins `llm-backend` to reach Ollama. |
| **Open WebUI x2** (v2, HD-248): `chat.kogler.si` PUBLIC (family, limited keys, Family-Manuals-only KB) + `ai.kogler.si` INTERNAL (tailnet-served; you+wife, agent-capable keys, `rag_internal`) | chat + RAG UI | `traefik-public` / tailnet sidecar | Auth = Authentik OIDC both; model backend = LiteLLM scoped keys each. |
| **PGVector** | RAG vector store | `db-internal` | Dedicated `pgvector/pgvector:pg16`. Add DBxx block to `db-backup`. |
| **Ollama** | Local LLM inference | **`llm-backend`** | GPU (RX 7600). Isolated from `services-internal` — reachable only by LiteLLM (HD-59). |
| **Docling** | OCR / document understanding | `services-internal` | Runs on **CPU** (spares the dGPU). Multilingual OCR (Slovenian scans). |
| **OpenClaw** | AI agent / orchestration | `services-internal` | Python framework (ex-Clawd). Models → LiteLLM. **Version pinned** (young project). |
| **DSH -- DeepSeek Harness** *(planned, HD-250)* | DevOps/IaC coding cockpit (pi.dev replacement) | `services-internal` + tailnet sidecar | Models via LiteLLM scoped key; Forgejo PAT PR-only/no-merge; 443 egress accepted. |

---

## 4. LLM routing & keys

- **One endpoint:** Open WebUI, DSH and OpenClaw authenticate to **LiteLLM only**, via per-consumer **scoped virtual keys** (HD-247) -- they never hold `openrouter_api`, `cohere_api`, or the master key.
- **Generation → Open Router:** one `openrouter_api` key (api → credential) reused for **all** external
  chat/LLM models, declared in LiteLLM's `config.yaml`.
- **Embeddings → Cohere:** `cohere_api` (api → credential). Cohere embed-v4 **multilingual** chosen
  deliberately for state-of-the-art multilingual embeddings (strong for Slovenian). Cloud call is an
  **accepted** trade-off (decision 2026-08-16) — only embedded vectors, not documents/chats, leave.
- **Local models:** LiteLLM also lists local Ollama models (RX 7600) so the family sees local + cloud
  models through one dropdown; local is default where privacy/offline matters.

**Local model recommendations** (office/voice workloads, moved from `services-office.md` — HD-199
boundary trim; this doc is the platform SSOT for model guidance):

| Model | VRAM | Best For |
|-------|------|----------|
| **Llama 3.1/3.2 8B** | ~6 GB | Everyday office, email drafting, summarization |
| **Qwen 2.5/3.5 7B–14B** | ~6–12 GB | Complex document structuring, code generation |
| **Phi-4 14B** | ~10 GB | Reasoning, logic, Microsoft workflow drop-in |
| **Qwen 2.5-Coder 32B** | ~24 GB | Heavy programming (Phase 2 GPU) |

1Password (`Homelab-ansible` vault) items — see [`deployment-secrets.md`](deployment-secrets.md):

| Item | type → `field=` | Used by |
|------|-----------------|---------|
| `openrouter_api` | api → `credential` | LiteLLM (all external LLM generation) |
| `cohere_api` | api → `credential` | LiteLLM (Cohere embed-v4, embeddings only) |
| `litellm_master_key` | api → `credential` | Open WebUI + OpenClaw authenticate to LiteLLM |
| `openwebui_secret` | password → `password` | Open WebUI session/encryption secret (optional) |
| `pgvector_db` | db → `password` (`username`=DB user) | PGVector (optional if dedicated) |

> **Fail-closed secrets:** no `default('')` on any of these — a missing item fails the render loudly
> (HD-65/76).
>
**Scoped consumer keys (v2 plan, HD-247):** LiteLLM runs Postgres-backed (`STORE_MODEL_IN_DB`) so models are edited in its Admin UI at runtime; Ansible owns bootstrap config only. One-time bootstrap glue mints per-consumer virtual keys into 1Password (fail-closed lookups thereafter):

| Key | Consumer | Scope |
|-----|----------|-------|
| `owui-public-chat` | OWUI-public | chat models (`ollama/*` + mid-tier cloud), budget caps, no agents |
| `owui-public-rag` | OWUI-public RAG | `cohere/embed-v4` only |
| `owui-int-wife` | OWUI-internal (wife) | agents + mid-tier cloud; capped |
| `owui-int-owner` | OWUI-internal (owner) | full incl. agent models |
| `dsh` | DeepSeek Harness | coding-model scope, budgeted |
| `openclaw` | OpenClaw gateway | agent scope, budgeted |
| `rag-int-svc` | OWUI-internal RAG | `cohere/embed-v4` only |

> 📋 **Deploy checklist:** see [`deployment-ai-stack-secrets.md`](deployment-ai-stack-secrets.md) for the
> step-by-step 1Password item-creation + Authentik OIDC wiring runbook (HD-105).

---

## 5. RAG pipeline

1. **Ingest:** family documents from **OpenCloud** (WebDAV/CIFS on the live Hetzner Box, mounted read-only,
   owned by the neutral `media` uid per HD-51/94).
2. **OCR / structure:** **Docling only** — converts scans, PDFs **and images** (JPEG/PNG/TIFF/BMP/WEBP are
   first-class inputs; layout, tables, reading order) → markdown. SPDF/Tesseract is deliberately OUT of
   the RAG path (`pdf.kogler.si` stays the searchable-PDF-artifact tool); vision models read images at
   chat time but are NOT an ingestion OCR path.
3. **Index:** chunk → embed via **cohere/embed-v4.0** (1536 dims, direct Cohere through LiteLLM —
   OpenRouter carries no embeddings endpoint) → store in **PGVector** (`db-internal`).
4. **Retrieve + answer:** hybrid BM25+vector search → Cohere rerank v4.0-pro → context + prompt to the
   LiteLLM model.

**Decided retrieval/ingestion parameters** (owner brainstorm 2026-08-25; implementation = HD-246):

| Parameter | Decided value | Lives in |
|-----------|---------------|----------|
| Extraction engine | Docling only — `CONTENT_EXTRACTION_ENGINE=docling`, `DOCLING_SERVER_URL=http://docling:5001` | open-webui compose env |
| Embeddings | `cohere/embed-v4.0`, **1536 dims** (v4 default, untruncated), `RAG_EMBEDDING_ENGINE=openai` → `http://litellm:4000/v1` (key = `litellm_master_key`) | litellm `config.yaml.j2` + OW env |
| Reranker | Cohere **rerank v4.0-pro**, external engine via LiteLLM `/rerank` (`RAG_RERANKING_ENGINE=external`; exact LiteLLM id string registry-verified at render) | litellm `config.yaml.j2` + OW env |
| Hybrid search | ON — `ENABLE_RAG_HYBRID_SEARCH=true`, `RAG_HYBRID_BM25_WEIGHT=0.5` (starting value) | OW env |
| Retrieval K | `RAG_TOP_K_RERANKER=20` candidates → rerank → `RAG_TOP_K=5`, `RAG_RELEVANCE_THRESHOLD=0.0` | OW env |
| Chunking | **token-based**: `RAG_TEXT_SPLITTER=token` (mandatory — otherwise CHUNK_SIZE counts *characters*), `CHUNK_SIZE=512`, `CHUNK_OVERLAP=64` (Cohere sweet spot) | OW env |
| Config ownership | `ENABLE_PERSISTENT_CONFIG=false` — rendered env vars are the SSOT; Admin-UI edits do NOT persist (the live DB would otherwise silently win over later env changes) | OW compose env |
| Knowledge split (v2, HD-248) | Public instance ingests **Family Manuals KB ONLY** (admin-only; user knowledge-creation disabled) -- same source folder also ingested on the internal instance into `rag_internal` (dual re-index step in this task) | OW env + UI ACLs |
| PGVector index | HNSW `vector_cosine_ops` @ 1536 — idempotent Ansible task, `no_log`, no hand-SQL (HD-220 rule), runs after OW schema init | deploy-service post-up task |

> **Dimension lock-in:** the PGVector vector column dimension freezes at first ingest — changing the
> embedding model or dims later means full re-ingest + re-index. 1536 chosen deliberately (untruncated v4).

**Backup:** the PGVector DB holds the RAG index + chat history — the same "irretrievable metadata"
risk class as Immich (KOPS-026). Add a `DBxx` block to `db-backup` and include the volume in Kopia.
Open WebUI + OpenClaw config/state → Kopia as well.

---

## 6. Auth & exposure

- **`chat.kogler.si` is public** (renamed from `ai.` -- v2, HD-248), behind **Authentik OIDC** (native SSO, per-person) + **`crowdsec-only`** middleware at the Traefik edge (internet-facing → Flaw A / HD-60). Holds ONLY capability-limited credentials: family-chat + embed keys, no agents.
- **`ai.kogler.si` is the INTERNAL instance** (tailnet-served via Pattern-A sidecar; public DNS record dropped/repointed). You + wife; agent-capable keys; `rag_internal`.
- **Capability-tiering posture:** internet-facing surfaces hold limited-capability credentials only; full power requires tailnet membership. New admin/UI surfaces default tailscale-first -- see [security.md](security.md) §Capability-tiering and [network-vpn.md](network-vpn.md) §Tailnet-exposed services (Patterns A/B).
- Per-person chat/history follows the HD-51 identity model (users = Authentik identities). No shared admin login exposed; admin surface is the OIDC account only.

---

## 7. Integrations

| Integration | How |
|-------------|-----|
| **Open WebUI ↔ OpenClaw** | Register OpenClaw as a **model/provider in LiteLLM** → chatting to the "OpenClaw" model in the UI invokes the agent (**internal instance only; public keys exclude agents**). No bespoke glue. |
| **DSH ↔ LiteLLM/Forgejo** *(planned, HD-250)* | Coding cockpit consumes a scoped LiteLLM key; proposes homelab changes via Forgejo PRs only (branch-protected main, service account without merge rights). |
| **Open WebUI ↔ OpenCloud** | Family documents from the **live Hetzner Box (WebDAV, HD-135)** mounted **read-only** into Open WebUI RAG ingestion; documents live in OpenCloud, Open WebUI indexes them. |
| **OpenClaw ↔ OpenCloud** | OpenClaw **WebDAV skill** reads/writes family files (summarize, organize, OCR a scan via Docling, draft replies). |
| **Open WebUI ↔ MS Office** | Office MCP bridges (Windows 11 clients) surface Word/Excel/PowerPoint as **tools** into Open WebUI over the Headscale tunnel — live COM edits; server-side python-docx/pptx/openpyxl path for Linux. See [`services-office.md`](services-office.md) (HD-106–111). |

---

## 8. Security & operating notes

- **No host port binds** (Flaw C / HD-62): overlay networks + Traefik only; loopback-only if needed.
- **Version pinning** (Flaw B / HD-61/71): pin LiteLLM, Open WebUI, Docling, PGVector, and **OpenClaw**
  (a young, fast-moving project — treat like Tuwunel, KOPS-030). Keep Renovate tracking.
- **VRAM/RAM budget:** RX 7600 = 8 GB VRAM, shared with Ollama + immich-ML + voice. Docling on **CPU**
  by default; size chat models ~7–8B q4; keep `keep_alive` sensible (see `hardware-gpu.md`).
- **AnythingLLM + LocPilot removed** for the family web UI — replaced by the **MS Office MCP path** in
  Open WebUI (HD-108), reflected in `services-office.md`.

---

## 9. Decision log

| # | Decision | Date |
|---|----------|------|
| 1 | Cohere embed-v4 **multilingual** (paid, cloud) for embeddings — SOTA chosen; cloud acceptable. | 2026-08-16 |
| 2 | `ai.kogler.si` **public**, Authentik OIDC + CrowdSec. | 2026-08-16 |
| 3 | OpenClaw **kept**, **version pinned** (supply-chain risk accepted). | 2026-08-16 |
| 4 | No host `0.0.0.0` port binds (loopback-only if ever needed). | 2026-08-16 |
| 5 | Single `openrouter_api` for all external LLM gen; **`cohere_api` separate** (embeddings not on OpenRouter). | 2026-08-16 |
| 6 | **LocPilot kept; AnythingLLM removed.** | 2026-08-16 |
| 7 | **OpenCloud = file SSOT · Open WebUI = chat/UX SSOT** — Office via MCP tools, not add-ins (HD-108). | 2026-08-16 |
| 8 | **Office MCP bridges are native Windows per-client** (no Docker), Headscale-only + token-auth, version-pinned (HD-106/109). | 2026-08-16 |
| 9 | **Docling-only OCR ingestion** — SPDF/Tesseract out of the RAG path (searchable-PDF artifact tool only); chat-time image reading = LiteLLM vision models, never an ingestion OCR. | 2026-08-25 |
| 10 | **RAG stack locked:** cohere/embed-v4.0 @1536 direct-Cohere · Cohere rerank v4.0-pro external via LiteLLM · hybrid BM25+vector ON (weight 0.5) · retrieve 20 → top 5 · token chunks 512/64 · `ENABLE_PERSISTENT_CONFIG=false` (env = SSOT). Implementation: HD-246. | 2026-08-25 |
| 11 | **Two-instance OWUI split** -- `chat.kogler.si` public (limited keys, Family-Manuals-only KB) / `ai.kogler.si` internal tailnet-served (full power); Element Web → `msg.kogler.si`. HD-248. | 2026-08-26 |
| 12 | **Capability-tiering posture** -- internet-facing surfaces hold limited-capability credentials only; agent-capable keys tailnet-only; new admin surfaces tailscale-first (security.md §10, network-vpn.md Patterns A/B). | 2026-08-26 |
| 13 | **LiteLLM v2** -- Postgres-backed runtime, models UI-managed (drift accepted); scoped consumer keys; master_key retired from templates (HD-247). | 2026-08-26 |
| 14 | **Public OWUI knowledge = Family Manuals KB only**, admin-only ingestion; user knowledge-creation disabled there. | 2026-08-26 |
| 15 | **n8n → internal tier** + scoped LiteLLM key with budget cap; webhook dependency audit first (HD-249). | 2026-08-26 |
| 16 | **DSH replaces Hermes placeholder** as DevOps/IaC cockpit; netns serve pattern; 443 egress accepted; Forgejo PAT PR-only/no-merge (HD-250). | 2026-08-26 |
| 17 | **Embeddings uniform** cohere/embed-v4 @1536; public corpus = Family Manuals only; wife's public-work corpora internal-only. | 2026-08-26 |

---

## 10. Not yet implemented

Depends on: oldsrv GPU operational + Ollama live · LiteLLM (spine) first · `openrouter_api` +
`cohere_api` + `litellm_master_key` in 1Password · Authentik OIDC provider for Open WebUI ·
OpenCloud + neutral `media` owner (HD-51) · PGVector DB + db-backup row · OpenClaw pinned.
See `todo.md` HD-1xx (`source: services-ai`). RAG retrieval wiring (OW env pins, litellm
rerank/embed-model fix, PGVector HNSW index): **HD-246**.
