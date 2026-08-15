---
title: Local LLM for Office Tasks
role: detail
domain: services
status: active
tags: [services, llm, ollama, office]
---
# Local LLM for Office Tasks

> **Role:** Detail — AI-assisted office work, model recommendations, toolchain.
> **Links to:** `hardware-gpu.md`
> **Linked from:** `index.md`

---

## Strategy

Office AI tools run on the **same oldsrv GPU** as voice assistant and Immich ML. Ollama serves all workloads, switching models via `keep_alive`. See [`hardware-gpu.md`](hardware-gpu.md) for VRAM management.

---

## Toolchain

### Phase 1: ONLYOFFICE on Debian Desktop

oldsrv runs **Debian as its host OS** — family desktop uses ONLYOFFICE:

| Component | Role |
|-----------|------|
| **ONLYOFFICE Desktop Editors** | Native Linux office suite, Ribbon UI, full `.docx`/`.xlsx`/`.pptx` |
| **OpenCloud sync client** | Files sync automatically to OpenCloud |

> ⚠ **PENDING (HD-52):** the official OpenCloud sync client (`opencloud-eu/desktop`) ships as an **AppImage only** — no apt repo. Packaging decision open: AppImage → `/opt` + `.desktop` entry, or Debian `nextcloud-desktop` (protocol-equivalent), or skip until the docs/manual phase.
| **ttf-mscorefonts-installer** | Calibri, Cambria for document fidelity |

- No Wine, no VM, no Windows license — fully native Debian
- Zero cloud dependency for editing (works offline)
- AI queries go directly to local Ollama API (same machine, no network hop)

### Microsoft Word Integration (Windows Laptops)

| Component | Role |
|-----------|------|
| **Ollama** | Model hosting, OpenAI-compatible API |
| **AnythingLLM** | Local RAG — ingest `.docx` folders for context |
| **LocPilot / GPTLocalhost** | Word add-in connecting Word to local LLM API |

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
| **Ollama** (code-capable model) | Generates Python script |
| **python-pptx** | Compiles text into native `.pptx` slides |
| **Marp** (alternative) | Markdown → HTML/PDF slide decks |

---

## Recommended Models (2026)

| Model | VRAM | Best For |
|-------|------|----------|
| **Llama 3.1/3.2 8B** | ~6 GB | Everyday office, email drafting, summarization |
| **Qwen 2.5/3.5 7B–14B** | ~6–12 GB | Complex document structuring, code generation |
| **Phi-4 14B** | ~10 GB | Reasoning, logic, Microsoft workflow drop-in |
| **Qwen 2.5-Coder 32B** | ~24 GB | Heavy programming (Phase 2 GPU) |

---

## Privacy

- All documents, emails, and presentations **never leave the home network**
- n8n workflows are self-hosted
- AnythingLLM ingests local files only
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
4. AnythingLLM + LocPilot on Windows laptops
5. ONLYOFFICE on oldsrv desktop