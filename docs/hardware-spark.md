---
title: spark — Lenovo ThinkStation PGX (NVIDIA GB10 Grace Blackwell)
role: detail
domain: hardware
status: planned
tags: [hardware, gpu, spark, gb10, grace-blackwell, ai]
---
# spark — Lenovo ThinkStation PGX (NVIDIA GB10 Grace Blackwell)

> **Role:** Detail — the headless AI inference node that **replaces the old Phase-2 Ryzen/Proxmox build**
> (HD-42, superseded). A small-form-factor NVIDIA **GB10 Grace Blackwell** superchip workstation
> (`spark.kogler.si`) serving the Triton Inference Server + NVFP4 model set as a LAN GPU tier.
> **Links to:** `hardware-gpu.md`, `services-ai.md`, `services-office.md`, `network-vlans.md`
> **Linked from:** `hardware.md`, `index.md`, `services-ai.md`

> **Status: 🟢 planned — hardware purchased; node not yet provisioned.** SSOT spec + intent only.
> The node is headless (no local display) and joins the homelab as a LAN GPU tier alongside oldsrv.
> ⏳ deploy-gated on the node bring-up (DGX OS install, Ansible role, network placement).

---

## What replaced the old Phase 2

The previously-planned **Phase 2 target build** (`hardware-phase2.md`: AMD Ryzen 9 9900X + Radeon AI PRO
R9700 + Proxmox VE, ~€4,449) is **superseded** by this purchase. The ThinkStation PGX is a
purpose-built, single-socket NVIDIA Grace Blackwell appliance — far more compute per € for local
inference, no hypervisor layer needed, no AMD ROCm toolchain. The old build is archived in the
decision log (`deployment-rejected.md`) + git history.

## Hardware

| Component | Specification |
|-----------|---------------|
| Superchip | **NVIDIA GB10 Grace Blackwell** (same silicon as DGX Spark) |
| CPU | NVIDIA Grace 20-core **Arm** — 10× Cortex-X925 + 10× Cortex-A725 |
| GPU | Blackwell — 5th-gen Tensor Cores, 4th-gen RT Cores, NVENC/NVDEC |
| AI performance | **1000 TOPS · 1 PFLOP (FP4, sparsity)** |
| Unified memory | **128 GB LPDDR5x** (256-bit, 273 GB/s) — shared CPU/GPU |
| Storage | 1 TB or 4 TB NVMe M.2 (self-encrypting, AES SED) |
| Power | **240 W** USB-C PD 3.1 PSU |
| Form factor | 1.13 L SFF (150 × 150 × 50.5 mm, ~1.2 kg) |
| Network | **10 GbE** RJ-45 + 2× QSFP (NVIDIA ConnectX-7) — 2-node scale-out to 405B |
| Wireless | Wi-Fi 7, Bluetooth 5.3 LE |
| Ports | 3× USB-C USB4 (20 Gb/s, DP 2.1), HDMI 2.1a, RJ-45 10GbE, 2× QSFP |
| OS | NVIDIA DGX OS / Ubuntu Pro with NVIDIA Base OS, **CUDA 13** |

## Planned role — headless Triton inference node

`spark` runs headless (no monitor, no desktop) as the homelab's **local LLM/inference tier** behind
the **NVIDIA Triton Inference Server** (`nvidia/tritonserver`), serving the NVFP4 model set below.
It complements — it does not replace — the existing VPS AI spine (LiteLLM/Qdrant/OWUI) and the
oldsrv Ollama GPU tier.

### Model set (NVFP4 / local, all fit within 128 GB unified memory)

| Model | Size (NVFP4) | Role |
|-------|-------------|------|
| **NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4** | ~30B (3B active, MoE/Mamba) | fast reasoning / default chat |
| **Qwen3-Next-80B** | ~80B | general instruction following |
| **Llama-3.3-70B-Instruct** | ~70B | general chat / RAG answer |
| **Qwen3-Coder-Next-80B** | ~80B | code generation |
| **bge-m3 + bge-reranker-v2-m3** | embedding + rerank | local embeddings / rerank for Qdrant RAG (replaces external Cohere) |
| **Whisper-large-v3-turbo + Whisper-large-v3** | STT | speech-to-text |
| **XTTS v2 + Piper TTS** | TTS | text-to-speech |

> **Embedding note:** bge-m3/bge-reranker-v2-m3 running locally on spark are the planned path to
> drop the external `cohere_api` for embeddings/rerank (see `services-ai.md` §4 / §5). Dimension
> lock-in (HD-267) means this is a deliberate, backtested change before any live swap.

## Planned services

Two new service-onboarding candidates land with spark (see `services-ai.md`):

1. **Mem0** — long-term memory for Open WebUI, backed by the existing **Qdrant** vector store
   (HD-267/268). Per-user/per-project scoping via a custom `user_id` = `<openwebui_user_id>-<model_id>`.
2. **OpenHands** — agentic coding harness (a third coding cockpit alongside pi.dev + DSH, HD-307/250).

## Network / placement

- Hostname **`spark.kogler.si`** — headless LAN GPU tier.
- Connects via **10 GbE** to the LAN (Home/Mgmt per the router port model); IP/reservation SSOT to be
  added to `network_static_hosts` at provision time (never hardcoded).
- Exposes the Triton gRPC/HTTP endpoint on the `llm-backend` overlay (or a `triton-backend` net),
  reachable **only by LiteLLM** — same isolation model as Ollama (HD-59). No host port binds.
- 2× QSFP ConnectX-7 ports reserved for a future 2-node scale-out (to 405B models) — not used now.

## Remote management

- Headless by design: no display, no local desktop. Managed over the LAN (SSH/Ansible) + the mgmt plane.
- 240 W USB-C PD power; check UPS coverage on the rack (PowerWalker VFI ICT/ICR IoT 3000, `hardware-ups.md`).

## Document Map

| For | Read |
|-----|------|
| GPU resource / VRAM / modes | [`hardware-gpu.md`](hardware-gpu.md) |
| AI platform (Triton, models, Mem0, OpenHands, LiteLLM) | [`services-ai.md`](services-ai.md) |
| Local LLM model guidance | [`services-ai.md`](services-ai.md) |
| Network / VLAN placement | [`network-vlans.md`](network-vlans.md) |
| Old superseded Phase-2 build | archived decision log ([`deployment-rejected.md`](deployment-rejected.md)) |
