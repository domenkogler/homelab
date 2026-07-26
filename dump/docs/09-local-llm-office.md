# Local LLM for Office Tasks

> **Canonical doc.** Based on `local llm agent for word mail and presentations.md`.  
> All processing on the home server GPU — zero cloud dependency.

---

## Strategy

Office AI tools run on the **same home server GPU** as the voice assistant and Immich ML. The Ollama instance serves all workloads, switching models via `keep_alive`.

---

## Toolchain

### Phase 1: ONLYOFFICE on Debian Desktop

Since the Phase 1 home server runs **Debian as its host OS**, the family desktop uses **ONLYOFFICE Desktop Editors** as the native office suite:

| Component | Role |
|-----------|------|
| **ONLYOFFICE Desktop Editors** | Native Linux office suite — Ribbon UI identical to MS Office, full `.docx`/`.xlsx`/`.pptx` compatibility |
| **OpenCloud sync client** | Files saved in ONLYOFFICE sync automatically to OpenCloud on the VPS — accessible from any device |
| **ttf-mscorefonts-installer** | Microsoft core fonts (Calibri, Cambria, etc.) for document fidelity |

**Key advantages:**
- No Wine, no VM, no Windows license — fully native Debian application
- Zero cloud dependency for editing (works offline)
- Files sync to OpenCloud when online, just like the family's Windows laptops
- For AI-assisted writing from the Debian desktop, queries go directly to the local Ollama API (same machine, no network hop)

> **The MS Word AI toolchain below (LocPilot/AnythingLLM) remains planned for family Windows laptops** — it is not replaced, just not needed on the Debian desktop.

### Microsoft Word Integration (Windows Laptops)

| Component | Role |
|-----------|------|
| **Ollama** (or LM Studio) | Model hosting, OpenAI-compatible API |
| **AnythingLLM** | Local RAG — ingest `.docx` folders, provide context to LLM |
| **LocPilot / GPTLocalhost** | Word add-in that connects Word to local LLM API |

**Workflow:** Write/edit in Word → LocPilot sends context to AnythingLLM → AnythingLLM queries local model with relevant documents → response appears in Word.

### Email Automation

| Component | Role |
|-----------|------|
| **n8n** (self-hosted, Docker) | Automation workflows with local LLM node |
| **Ollama** | LLM backend for drafting, summarizing |
| **IMAP/SMTP** | Connects n8n to email inbox |

**Workflow:** n8n monitors inbox → new email triggers LLM → drafts response saved as "Draft" for human review → user approves and sends.

Alternative: **Thunderbird + local AI add-ons** for on-the-fly rephrasing and tone changes inside compose window.

### Presentation Generation

| Component | Role |
|-----------|------|
| **Ollama** (code-capable model) | Generates Python script |
| **python-pptx** | Compiles text into native `.pptx` slides |
| **Marp** (alternative) | Markdown → HTML/PDF slide decks |

**Workflow:** Describe presentation to LLM → LLM outputs python-pptx script or Marp Markdown → run locally → `.pptx` or PDF slides.

---

## Recommended Models (2026)

| Model | VRAM | Best For |
|-------|------|----------|
| **Llama 3.1/3.2 8B** | ~6 GB | Everyday office tasks, email drafting, summarization |
| **Qwen 2.5/3.5 7B–14B** | ~6–12 GB | Complex document structuring, code generation for presentations |
| **Phi-4 14B** | ~10 GB | Reasoning, logic, Microsoft workflow drop-in |
| **Qwen 2.5-Coder 32B** | ~24 GB | Heavy programming sessions (loaded in "Programming Mode") |

---

## Integration with VRAM Management

The Ollama `keep_alive` strategy from the hardware doc applies here too:

| Mode | Active Models | VRAM | Office Use |
|------|--------------|------|------------|
| **Programming** | Qwen 2.5-Coder 32B | ~24 GB | Full office + coding capability |
| **Family Home** | Whisper + HA LLM + Piper | ~7 GB | Lighter models for quick office tasks (swaps out after idle) |
| **Idle** | None (after 5 min) | ~0 GB (GPU ~12 W) | GPU ready for next request |
| **Gaming** | None (containers stopped) | 0 GB (GPU at full) | Sunshine game streaming — manual start, LLM has priority |

### GPU Coexistence: LLM vs Game Streaming

Sunshine game streaming uses the same RX 7600 GPU. **LLM always has priority:**
- `OLLAMA_KEEP_ALIVE=5m` ensures VRAM is freed when AI is idle
- Gaming session: user manually runs `docker compose stop ollama immich-ml` to release full 8 GB VRAM
- After gaming: `docker compose up -d ollama immich-ml` restores AI services
- No automated preemption — manual switch keeps the family in control
- If a family member is gaming and an AI task is needed, Domen decides which to pause

---

## Privacy

- All documents, emails, and presentations **never leave the home network**
- n8n workflows are self-hosted
- AnythingLLM ingests local files only
- No API keys, no subscription costs, no data sharing

---

## Not Yet Implemented

This is planned but not running yet. Depends on:
1. Home server with GPU (Phase 1: existing RX 7600 in Debian desktop; Phase 2: new server)
2. Ollama + model downloads
3. n8n setup (Docker Compose)
4. AnythingLLM + LocPilot installation (Windows laptops only)
5. ONLYOFFICE installation (Phase 1 Debian desktop only)

---

## Cost Comparison

| Solution | Cost |
|----------|------|
| Microsoft Copilot Pro | €22/user/month |
| ChatGPT Plus | €20/month |
| **Local (this plan)** | **€0/month** (after hardware purchase) |

Phase 1 uses existing hardware at **€0 additional cost**. Phase 2 hardware (~€4,449) is a future one-time capital expense. The GPU also serves voice AI, image recognition, and coding — not just office.