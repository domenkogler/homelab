# Local LLM for Office Tasks

> **Canonical doc.** Based on `local llm agent for word mail and presentations.md`.  
> All processing on the home server GPU — zero cloud dependency.

---

## Strategy

Office AI tools run on the **same home server GPU** as the voice assistant and Immich ML. The Ollama instance serves all workloads, switching models via `keep_alive`.

---

## Toolchain

### Microsoft Word Integration

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

| Mode | Active Models | Office Use |
|------|--------------|------------|
| **Programming** | Qwen 2.5-Coder 32B loaded | Full office + coding capability |
| **Family Home** | Whisper + HA LLM + Piper (~7GB) | Lighter models for quick office tasks (swaps out after idle) |
| **Sleep** | None (GPU ~12W) | — |

---

## Privacy

- All documents, emails, and presentations **never leave the home network**
- n8n workflows are self-hosted
- AnythingLLM ingests local files only
- No API keys, no subscription costs, no data sharing

---

## Not Yet Implemented

This is planned but not running yet. Depends on:
1. Home server with GPU (RX 7600 or new build)
2. Ollama + model downloads
3. n8n setup (Docker Compose)
4. AnythingLLM + LocPilot installation

---

## Cost Comparison

| Solution | Cost |
|----------|------|
| Microsoft Copilot Pro | €22/user/month |
| ChatGPT Plus | €20/month |
| **Local (this plan)** | **€0/month** (after hardware purchase) |

The hardware cost (~€4,449 or just the existing RX 7600) is a one-time capital expense. It also serves voice, image recognition, and coding — not just office.