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
**Spark is the homelab's single AI-inference tier** (2026-09-06 decision): all local inference —
generation, embeddings, rerank, STT, TTS — runs here via Triton. It complements — does not replace —
the VPS AI *spine* (LiteLLM/Qdrant/OWUI), but it **replaces** the oldsrv Ollama GPU tier (no Ollama/
ROCm on oldsrv; oldsrv GPU = Sunshine gaming encode only).

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

> **Embeddings (2026-09-06):** bge-m3 (1024-dim) + bge-reranker-v2-m3 on spark **replace Cohere
> entirely** — the `cohere_api` subscription is retired. **Nothing is RAG'd yet**, so the Qdrant
> dimension lock (1536→1024) costs nothing now; embed/rerank become local on spark.

## Planned services

Two new service-onboarding candidates land with spark (see `services-ai.md`):

1. **Mem0** — long-term memory for Open WebUI, backed by the existing **Qdrant** vector store
   (HD-267/268). Per-user/per-project scoping via a custom `user_id` = `<openwebui_user_id>-<model_id>`.
2. **OpenHands** — agentic coding harness (a third coding cockpit alongside pi.dev + DSH, HD-307/250).

## Bring-up plan (HD-337, 2026-09-06)

Order of execution at node bring-up (spec lives here; todo.md HD-337 is the pointer):

1. **DGX OS / Ubuntu Base OS install** (headless; CUDA 13, GB10 sm_121 — see bring-up guide above).
2. **Ansible role + placement**: add to `network_static_hosts` (never hardcode); Rack residency,
   UPS coverage (PowerWalker), 10 GbE to LAN.
3. **Reachability**: HD-155 `wg-s2s` AllowedIPs + router forward-accept delta to add **spark**
   (VPS/LiteLLM → spark over the tunnel). This is a network change, not just inference config.
4. **Triton Inference Server** (container-native; Docker isolates CUDA/Python per bring-up guide)
   on a `triton-backend` overlay, reachable **only by LiteLLM** (HD-59 isolation). The server is a
   standard `docker_services` entry (`template_dir: triton`, pinned image tag in `versions.yml`,
   Renovate-tracked) — same management as every other service.
5. **Model serve — the model repository is Ansible-managed** (this is the role's core job): NVFP4 gen
   set + bge-m3/1024 + bge-reranker + whisper-turbo + XTTS/Piper.
   - **Strict repo layout** rendered by the role: `/srv/models/spark/triton/<model>/1/{model.nvfp4,…}`
     (version dir `1/`), per-model `config.pbtxt` as **J2 templates** (backend: tensorrt_llm/vllm vs
     ONNX; input/output tensor names, `max_batch_size`, instance_group, dynamic batching — version-
     sensitive, error-prone-by-hand → must be rendered, never hand-touched).
   - **Conversion pipeline**: role pulls base weights → runs NVFP4/engine converter (llm-compressor/
     TensorRT-LLM) **idempotently** (skip if engine artifact exists), tagged per model — a heavy,
     human-gated first-boot step (like render→review→apply), not a blind one-shot.
   - **Residency policy** (voice pinned resident / gen-embed on-demand) rendered into `config.pbtxt`
     scheduling + Triton model-control config — the role owns the baseline; tuning is config (like
     `versions.yml`), not deployment.
   - **Staging**: `/srv/models/spark/` (regenerable from repo floor + staged weights; not backed up —
     same pattern as oldsrv `/srv/models/immich-ml`).

6. **Model-catalog sync (`litellm-model-sync`) — git ↔ LiteLLM DB reconciled (2026-09-06).** The
   **git SSOT is the source of truth for Triton models** (`group_vars/all/models.yml`: name, triton
   repo, litellm name, backend, dims, residency). A sync glue reconciles **git → LiteLLM DB**:
   - **Onboard** (model enters `models.yml` + Triton repo) → glue **upserts** it into the LiteLLM DB
     (`POST /model/new`, idempotent, vault-first — `bootstrap-keys` glue pattern).
   - **Offboard** (model leaves `models.yml` + Triton repo) → glue **deletes it from the LiteLLM DB**
     (it must not stay advertised when gone from Triton), **and** the model's allowlist entry is
     removed from `litellm_scoped_keys` (vps.yml) in the **same change** (same-change rule; a scoped
     key must not still authorize a model that no longer exists).
   - **Manual/OpenRouter models are NEVER touched by the glue** — the delete is **scoped** to names
     the glue previously synced (tracked in a `litellm_synced_models` state), so a hand-added
     OpenRouter model can never be clobbered, even on name collision.
   - **Per-user availability** stays `litellm_scoped_keys` (vps.yml): a model is reachable by a user
     **iff** it matches that key's `models:` allowlist (+ budget). Git = what exists on spark;
     DB + scoped keys = what/whom is available.
6. **Embedding cutover (Cohere retirement)**: switch LiteLLM embed/rerank → bge-m3,
   Qdrant 1536→1024 (free — nothing RAG'd yet), drop `cohere_api` + cancel Cohere subscription.
7. **Mem0 (OWUI)** + **OpenHands** onboarding.

### Not on spark
- immich-ML (oldsrv GPU, pause-able — see `hardware-gpu.md`). No second GPU stack.
- No RTMP/host venv inference — container-native only.
## Network / placement

- Hostname **`spark.kogler.si`** — headless LAN GPU tier.
- Connects via **10 GbE** to the LAN (Home/Mgmt per the router port model); IP/reservation SSOT to be
  added to `network_static_hosts` at provision time (never hardcoded).
- Exposes the Triton gRPC/HTTP endpoint on the `llm-backend` overlay (or a `triton-backend` net),
  reachable **only by LiteLLM** — same isolation model as Ollama (HD-59). No host port binds.
- 2× QSFP ConnectX-7 ports reserved for a future 2-node scale-out (to 405B models) — not used now.

## Remote management

- Headless by design: no display, no local desktop. Managed over the LAN (SSH/Ansible) + the mgmt plane.
- **GB10 bring-up reference:** [`martimramos/dgx-spark-ml-guide`](https://github.com/martimramos/dgx-spark-ml-guide) —
  PyTorch-nightly (sm_121), no ARM64 wheels, CPU/Python gotchas; run ML **container-native** (Docker
  isolates CUDA/Python — the guide's own recommended path).
- 240 W USB-C PD power; check UPS coverage on the rack (PowerWalker VFI ICT/ICR IoT 3000, `hardware-ups.md`).

## Document Map

| For | Read |
|-----|------|
| GPU resource / VRAM / modes | [`hardware-gpu.md`](hardware-gpu.md) |
| AI platform (Triton, models, Mem0, OpenHands, LiteLLM) | [`services-ai.md`](services-ai.md) |
| Local LLM model guidance | [`services-ai.md`](services-ai.md) |
| Network / VLAN placement | [`network-vlans.md`](network-vlans.md) |
| Old superseded Phase-2 build | archived decision log ([`deployment-rejected.md`](deployment-rejected.md)) |
