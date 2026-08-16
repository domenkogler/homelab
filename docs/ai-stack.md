---
title: AI Stack — Chat, RAG & Agents
role: detail
domain: services
status: planning
tags: [services, ai, llm, llm-gateway, rag, agents]
---
# AI Stack — Chat, RAG & Agents

> **Role:** Detail — family web AI platform: LLM routing (LiteLLM), chat + RAG UI (Open WebUI),
> agent orchestration (OpenClaw), OCR document ingestion (Docling), and the PGVector vector store.
> This is the **family-facing web AI layer**. Desktop/office AI (ONLYOFFICE, LocPilot, Word, email,
> presentations) stays in [`llm-office.md`](llm-office.md); this doc covers everything browser-facing.
> **Links to:** `llm-office.md`, `hardware-gpu.md`, `services-authentik.md`, `services-traefik.md`,
> `deployment-secrets.md`, `services.md`
> **Linked from:** `index.md`

> **Status:** Planning — nothing deployed yet. Supersedes the AnythingLLM path in `llm-office.md`
> for the family web UI (AnythingLLM **removed**; **LocPilot kept** for Windows-Word inline only).
> Tracked via `todo.md` HD-1xx (`source: ai-stack`).

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
         family browsers (ai.kogler.si)   ← public, Authentik OIDC + crowdsec-only
                      │
                      ▼
                 Open WebUI  ──RAG──▶  PGVector (db-internal)
                   │   │                ▲        ▲
   chat / tools    │   │  Docling OCR  │  embed │  (ingest family docs)
        │          │   └───────────────┤   _v4  │
        ▼          ▼                   │ (Cohere)│
    OpenClaw ──▶ LiteLLM (spine)  ─────┘        │
      │            │  └──▶ OpenRouter (openrouter_api) — all external LLM gen
      │            │  └──▶ Cohere embed-v4 (cohere_api) — embeddings only
      │            │
      └── OpenCloud (read/write family files, WebDAV)
```

**Docker networks:** Open WebUI on `traefik-public` (via the `ai` route); LiteLLM, OpenClaw, Docling
on `services-internal`; PGVector on `db-internal`. **No host `0.0.0.0` port binds** — everything is
reached over the overlay networks + Traefik (Flaw C / HD-62). Loopback-only if a raw port is ever
required.

---

## 3. Components

| Service | Role | Network | Notes |
|---------|------|---------|-------|
| **LiteLLM** | LLM gateway / router | `services-internal` | OpenAI-compatible spine. Own small DB (SQLite volume) for keys/spend. Only component holding upstream keys. |
| **Open WebUI** (`ai.kogler.si`) | Family chat + RAG UI | `traefik-public` | Auth = Authentik **OIDC** (per-user chat/history). Model backend = LiteLLM. |
| **PGVector** | RAG vector store | `db-internal` | Dedicated `pgvector/pgvector:pg16`. Add DBxx block to `db-backup`. |
| **Docling** | OCR / document understanding | `services-internal` | Runs on **CPU** (spares the dGPU). Multilingual OCR (Slovenian scans). |
| **OpenClaw** | AI agent / orchestration | `services-internal` | Python framework (ex-Clawd). Models → LiteLLM. **Version pinned** (young project). |

---

## 4. LLM routing & keys

- **One endpoint:** Open WebUI and OpenClaw authenticate to **LiteLLM only** (`litellm_master_key`).
  They never hold `openrouter_api` or `cohere_api`.
- **Generation → Open Router:** one `openrouter_api` key (api → credential) reused for **all** external
  chat/LLM models, declared in LiteLLM's `config.yaml`.
- **Embeddings → Cohere:** `cohere_api` (api → credential). Cohere embed-v4 **multilingual** chosen
  deliberately for state-of-the-art multilingual embeddings (strong for Slovenian). Cloud call is an
  **accepted** trade-off (decision 2025-08-16) — only embedded vectors, not documents/chats, leave.
- **Local models:** LiteLLM also lists local Ollama models (RX 7600) so the family sees local + cloud
  models through one dropdown; local is default where privacy/offline matters.

1Password (`Homelab` vault) items — see [`deployment-secrets.md`](deployment-secrets.md):

| Item | type → `field=` | Used by |
|------|-----------------|---------|
| `openrouter_api` | api → `credential` | LiteLLM (all external LLM generation) |
| `cohere_api` | api → `credential` | LiteLLM (Cohere embed-v4, embeddings only) |
| `litellm_master_key` | api → `credential` | Open WebUI + OpenClaw authenticate to LiteLLM |
| `openwebui_secret` | password → `password` | Open WebUI session/encryption secret (optional) |
| `pgvector_db` | db → `password` (`username`=DB user) | PGVector (optional if dedicated) |

> **Fail-closed secrets:** no `default('')` on any of these — a missing item fails the render loudly
> (HD-65/76).

---

## 5. RAG pipeline

1. **Ingest:** family documents from **OpenCloud** (mounted read-only, owned by the neutral `media`
   uid per HD-51/94).
2. **OCR / structure:** **Docling** converts scans + PDFs (layout, tables, reading order) → markdown.
3. **Index:** chunk → embed via **Cohere embed-v4 multilingual** → store in **PGVector** (`db-internal`).
4. **Retrieve + answer:** Open WebUI queries PGVector, sends context + prompt to LiteLLM model.

**Backup:** the PGVector DB holds the RAG index + chat history — the same "irretrievable metadata"
risk class as Immich (KOPS-026). Add a `DBxx` block to `db-backup` and include the volume in Kopia.
Open WebUI + OpenClaw config/state → Kopia as well.

---

## 6. Auth & exposure

- **`ai.kogler.si` is public** (decision 2025-08-16), behind **Authentik OIDC** (native SSO, per-person)
  + **`crowdsec-only`** middleware at the Traefik edge (internet-facing → Flaw A / HD-60).
- Per-person chat/history follows the HD-51 identity model (users = Authentik identities). No shared
  admin login exposed; admin surface is the OIDC account only.

---

## 7. Integrations

| Integration | How |
|-------------|-----|
| **Open WebUI ↔ OpenClaw** | Register OpenClaw as a **model/provider in LiteLLM** → chatting to the "OpenClaw" model in the UI invokes the agent. No bespoke glue. |
| **Open WebUI ↔ OpenCloud** | Family-docs dataset (neutral `media` owner) mounted **read-only** into Open WebUI RAG ingestion; documents live in OpenCloud, Open WebUI indexes them. |
| **OpenClaw ↔ OpenCloud** | OpenClaw **WebDAV skill** reads/writes family files (summarize, organize, OCR a scan via Docling, draft replies). |

---

## 8. Security & operating notes

- **No host port binds** (Flaw C / HD-62): overlay networks + Traefik only; loopback-only if needed.
- **Version pinning** (Flaw B / HD-61/71): pin LiteLLM, Open WebUI, Docling, PGVector, and **OpenClaw**
  (a young, fast-moving project — treat like Tuwunel, KOPS-030). Keep Renovate tracking.
- **VRAM/RAM budget:** RX 7600 = 8 GB VRAM, shared with Ollama + immich-ML + voice. Docling on **CPU**
  by default; size chat models ~7–8B q4; keep `keep_alive` sensible (see `hardware-gpu.md`).
- **AnythingLLM removed** for the family web UI; **LocPilot kept** (Windows-Word inline only) — both
  reflected in `llm-office.md`.

---

## 9. Decision log

| # | Decision | Date |
|---|----------|------|
| 1 | Cohere embed-v4 **multilingual** (paid, cloud) for embeddings — SOTA chosen; cloud acceptable. | 2025-08-16 |
| 2 | `ai.kogler.si` **public**, Authentik OIDC + CrowdSec. | 2025-08-16 |
| 3 | OpenClaw **kept**, **version pinned** (supply-chain risk accepted). | 2025-08-16 |
| 4 | No host `0.0.0.0` port binds (loopback-only if ever needed). | 2025-08-16 |
| 5 | Single `openrouter_api` for all external LLM gen; **`cohere_api` separate** (embeddings not on OpenRouter). | 2025-08-16 |
| 6 | **LocPilot kept; AnythingLLM removed.** | 2025-08-16 |

---

## 10. Not yet implemented

Depends on: oldsrv GPU operational + Ollama live · LiteLLM (spine) first · `openrouter_api` +
`cohere_api` + `litellm_master_key` in 1Password · Authentik OIDC provider for Open WebUI ·
OpenCloud + neutral `media` owner (HD-51) · PGVector DB + db-backup row · OpenClaw pinned.
See `todo.md` HD-1xx (`source: ai-stack`).
