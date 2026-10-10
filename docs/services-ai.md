---
title: AI Platform — Chat, RAG & Agents (LiteLLM / Open WebUI / OpenClaw / Docling / Qdrant)
role: detail
domain: services
status: active
tags: [services, ai, llm, llm-gateway, rag, agents, okf, vector]
---
# AI Platform — Family Web AI Layer

> **Role:** Stack doc (detail) — the family-facing web AI platform: LLM routing (LiteLLM), chat + RAG UI
> (Open WebUI), agent orchestration (OpenClaw), OCR ingestion (Docling) and the **Qdrant** vector store.
> It is the single merged view of the locked architecture: Qdrant as the standalone vector store ·
> Forgejo-OKF wiki as knowledge SSOT · harness consumption going direct to the engine.
>
> Desktop/office AI (ONLYOFFICE, Word, email, presentations) stays in [`services-office.md`](services-office.md);
> this doc covers everything browser/agent-facing. Per-model GPU placement = §9 +
> [`hardware-gpu.md`](hardware-gpu.md); the spark engine itself = [`hardware-spark.md`](hardware-spark.md).
>
> **Links to:** `services-office.md`, `hardware-gpu.md`, `hardware-spark.md`, `services-authentik.md`,
> `services-traefik.md`, `deployment-secrets.md`, `services.md`, `pi-harness.md`
> **Linked from:** `services.md`, `index.md`

> **Status:** the VPS platform is **live** — LiteLLM spine (Postgres-backed, models in the DB, version
> pinned, scoped virtual keys minted by the bootstrap glue), Open WebUI at `ai.kogler.si`, Docling,
> OpenClaw, Qdrant. The **LAN LiteLLM** (`lan-litellm`) and the **pinned-AI tier** (`whisper`, `reranker`,
> `embed`) are **live on oldsrv** behind `llitellm.kogler.si`, and `spark/qwen3.8-flash-next` is registered
> as a model row in **both** LiteLLM instances.
>
> **What is NOT true on the box, whatever older text says:**
> - **There is one Open WebUI, not two.** `open-webui` runs once on the VPS (`ai.kogler.si`);
>   the `chat` service is **element-web** (Matrix), not a second OWUI instance. The public/internal
>   two-instance split is **open work (§10)**, not current state.
> - **`rag-mcp` and `forgejo-mcp` are stubs** (`enabled: false`, and `rag-mcp`'s compose file has no
>   `services:` block, so flipping the flag fails `docker compose config`). The rerank leg therefore
>   **ships dormant**: the container answers, the consumer does not exist (**§10**).
> - **No scoped consumer reaches the pinned-AI rows.** The VPS instance's `litellm_scoped_keys` still name
>   `ollama/*` model names that no longer exist; the `spark` row is named in one allow-list only — the LAN
>   `home-assistant` record (§4), which grants that named row and nothing else
>   (`group_vars/home_servers.yml`), so no LAN key names a pinned-AI row; probes so far ran on the
>   admin-grade master key.
>
> ⏳ Open work is listed in §10.

---

## 1. Philosophy

One **LiteLLM endpoint** is the spine for everything that must not hold an upstream credential. Every such
consumer talks to it and **never sees an upstream provider key**. Wired today: Open WebUI, OpenClaw, Qdrant's
embed/rerank path, and Home Assistant as the `home-assistant` record on the LAN instance
([smart-home-voice.md](smart-home-voice.md)). **Not wired yet:** Docling as a scoped consumer — open work
(§10), so the list below is the contract, not the current roster. All external **generation** uses one `openrouter_api` key; **embeddings, rerank
and STT are local on the oldsrv RX 7600** (§3a). Model routing, cost, rate limits and credential management
are centralized there.

The coding harnesses are the deliberate exception — they go **direct** to the spark name edge (§9 row 26,
§9b, [pi-harness.md](pi-harness.md) §1b).

**Two invariants of the knowledge layer:**
- **The vector store is independent of Open WebUI.** Qdrant stands alone (hybrid dense+sparse BM25), so
  retrieval is not locked to any single UI — an AI interface is a swappable shell.
- **Git is the source of truth for knowledge; the index is a rebuildable cache.** Forgejo OKF-llm-wiki repos
  hold the canonical `.md`; Qdrant indexes them and can always be rebuilt from the git floor.

---

## 2. Architecture

Three strictly isolated network zones on the VPS — no AI container touches the host OS directly:

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
 │   Open WebUI  ·  LiteLLM  ·  OpenClaw  ·  Docling            │
 │   Qdrant (hybrid vector, db-internal)  ·  rag-mcp (stub)     │
 └──────────────────────────────────────────────────────────────┘
```

### AI hosting split — family AI on the VPS, dev/pinned AI on oldsrv + spark

Split by **who consumes it and where the compute lives** (tier doctrine: VPS = reliable/authoritative;
oldsrv = RAM+GPU-heavy, declared disposable).

| Side | Hosted on | Services | Why |
|---|---|---|---|
| **Family AI** | **VPS** | `open-webui` (SSO-dependent), `docling`, `qdrant`, `openclaw`, `rag-mcp`+`forgejo-mcp` (stubs), **VPS LiteLLM** | SSO-bound, reliable, backed-up — the family-facing web AI |
| **Dev / pinned AI** | **oldsrv** + **spark** | `lan-litellm` (+ its Postgres), the **pinned-AI tier** (`whisper` STT, `reranker`, `embed`), `ollama` (embed fallback rung), `immich-ml`, `mcp-victoriametrics`, `mcp-victorialogs`; **spark** runs the generation engine; `OpenHands` + `Mem0` remain planned | RAM/GPU-hungry (oldsrv 48 GB + RX 7600); LAN-local consumers; state backs up to NAS/VPS |

Consequences:

- **LiteLLM runs as two instances** (VPS + LAN) because it must sit next to its consumers — `litellm:4000`
  Docker-DNS only resolves same-host. The VPS instance serves the family side; the LAN instance serves the
  simple-querier tier + the pinned-AI legs. **Each owns its own Postgres** (`litellm-db` / `lan-litellm-db`)
  + its own scoped keys, and both are Kopia-backed.
- **Per decision #26 the LAN instance's backend set is the pinned-AI legs + spark for simple queriers** —
  NOT the coding harnesses, which talk to spark directly.
- **Coding harnesses are not services.** `dsh` / `pi-dev` as `docker_services` entries are parked
  (`enabled: false` — kept so `template_dir` + the port contract survive a re-onboarding). They run
  as dedicated deployments / on the workstation and reach the engine directly. The tailnet `dsh`/`pi-dev`
  DNS records + `dsh-backend`/`pi-backend` routes still exist and answer **502 by design**, as documented in
  [network-vpn.md](network-vpn.md); deleting them is a separate change with its own reasoning.

### Docker networks

`open-webui` on `traefik-public` · OpenClaw + Docling + `lan-litellm` consumers on `services-internal` ·
**Qdrant on `db-internal`** (alongside the LiteLLM Postgres) · the **unauthenticated inference legs on
`llm-backend`** with **no published ports and no Traefik labels** · tailscale sidecars (Pattern A) for the
management plane. **No host `0.0.0.0` port binds** — overlays + Traefik for the public plane (Flaw C;
Patterns A/B in [network-vpn.md](network-vpn.md)).

> **Unauthenticated-inference isolation:** Whisper/llama.cpp/Ollama-style inference APIs have **no
> native server auth**, so they live on the dedicated `llm-backend` overlay reachable **only by LiteLLM**
> (the spine) — never on the flat `services-internal`. On that network the *network is the boundary*.

---

## 3. Components

| Service | Role | Network | Notes |
|---------|------|---------|-------|
| **LiteLLM (VPS)** | LLM gateway / router | `services-internal` + `llm-backend` + `tailnet-apps` | OpenAI-compatible spine (Postgres-backed). The only component holding upstream keys. Admin UI is **tailnet-only** at `litellm.kogler.si` (edge → `http://litellm:4000` via Docker DNS — the `tailnet-apps` overlay is the bridge that makes that resolve; never join the key-holder to `traefik-public`). `/ui/login` resolves on the pinned build — the "no SPA fallback, use `/fallback/login`" note (upstream #29340) does not reproduce; **§4c**. |
| **LiteLLM (LAN)** | Dev/pinned-side gateway | oldsrv, `llm-backend` + traefik-internal | `lan-litellm` + `lan-litellm-db`, exposed as **`llitellm.kogler.si`** on the oldsrv `traefik-internal` HOME edge (`http://oldsrv_home_ip:4000` backend, TLS + HSTS). Own Postgres, Kopia-backed. `bootstrap_keys` is **`true`** — one consumer minted (`home-assistant`), so the glue's fail-loud gate on an EMPTY spec list must never be re-triggered by emptying `litellm_scoped_keys`; the rest of the scoped allow-lists are pending (§10). |
| **Open WebUI** | chat + RAG UI | `traefik-public` | ONE instance today at `ai.kogler.si`, Authentik OIDC. The public/internal split + per-instance corpus is **open work (§10)**. |
| **Qdrant** | hybrid vector store | `db-internal` | Standalone Rust DB (dense + sparse BM25), **independent of OWUI's built-in RAG**. Dimension locks at first ingest — **1024**. Keep the snapshot seam (§5b). |
| **Forgejo (wiki repos)** | knowledge SSOT | `db-internal` / git | OKF `.md` repos per owner; git = truth; Qdrant = rebuildable cache. |
| **Docling** | OCR / document understanding | `services-internal` | **CPU on the VPS** (no GPU there). Model stack = layout detector + TableFormer + pluggable OCR; live engine **RapidOCR / onnxruntime (PP-OCRv6 small)** — read from the served log; `easyocr 1.7.2` is installed but never reached, because `OcrAutoModel` prefers rapidocr+onnxruntime (§Docling OCR engine selection). Slovenian is covered: `sl` is a first-class PP-OCRv6 code and the multilingual `rec_small` is baked. ⚠ Its accelerator set is `auto\|cpu\|cuda\|mps\|xpu` — **no Vulkan/ROCm**, so Docling cannot use the RX 7600. ⛔ **On light prose the live engine drops whole sentences (§10).** A 300 dpi image-only Slovenian scan returns `status: success` with real markdown: the layout stage's compiled kernels live on the `/cache` bind, because `/tmp` is a `noexec` tmpfs — §Operational facts. Free lever regardless: `do_ocr=false` per request, but **only for born-digital PDFs** (a scanner's own text layer carries no diacritics). |
| **OpenClaw** | AI agent / orchestration | `services-internal` | Version pinned. Models via a LiteLLM scoped key. |
| **kapa-inspired-rag-mcp** *(stub)* | MCP hybrid reader | `services-internal` | Intended flow: hybrid search in Qdrant → top-20 → rerank via LiteLLM `jina_ai/` → top-5 clean markdown. Not implemented — see the status block and §10. |
| **Forgejo MCP** *(planned)* | MCP read/write `.md` | `services-internal` | Bridge to the OKF wiki repos; agents read/write notes + open PRs. |
| **Ollama** | **embed fallback rung** | `llm-backend` | ⚠ **declared but not deployed** — IaC enables `ollama` on oldsrv, yet the host has no `/srv/docker/ollama`, nothing listens on `11434` on any box, and no edge route names it; the pin `0.35.1-rocm` is unused `bge-m3` (1024-dim, E2E-verified, 833–899 MiB VRAM, ~500 ms/chunk). The **documented fallback rung** of the same 1024-dim space (#27). **Not** a rerank host and **not** an STT host (§9c). |
| **whisper / reranker / embed** | pinned-AI tier | `llm-backend` | oldsrv RX 7600 / Vulkan — §3a. |
| **Mem0** *(planned)* | Long-term memory for OWUI | `services-internal` | Backed by Qdrant; per-user/per-project scoping (§5c D). Onboarding is open work (§10). |
| **OpenHands** *(planned)* | Agentic coding harness | oldsrv / spark | A third coding cockpit; would be served by the LAN LiteLLM (scoped key) + a PR-only Forgejo token. |

### 3a. Pinned AI inference tier — plan of record (decision #27)

The one table for **what AI runs on oldsrv, on what device, with which model**. Every latency/VRAM figure is
**measured on this box** — provenance and repro commands in [services-ai-bench.md](services-ai-bench.md).

| Leg | Engine | Model (quant) | Device | VRAM (measured) | Latency (measured) | Status |
|-----|--------|---------------|--------|-----------------|--------------------|--------|
| **Embeddings** | `llama.cpp server-vulkan` (`--embedding --pooling cls --embd-normalize 2`) | `bge-m3` **Q8_0** (634.6 MB) | RX 7600 / Vulkan | **~326 MiB** | **15 ms**/chunk · 51-doc batch 0.86–1.40 s · **0.45 s deployed** | ✅ live (`embed`, :9002, gateway row `bge-m3-vk`, dim 1024, ‖v‖=1.0) · cos 0.9996 vs the Ollama vectors ⇒ **no re-embed penalty** |
| ↳ embed fallback rung | `ollama:0.32.15-rocm` (`/api/embed`) | `bge-m3` (fp16) | RX 7600 / ROCm | **833–899 MiB** | ~470–545 ms/chunk | ⚠ **no runtime deployed** — the fallback rung of the SAME 1024-dim space; a **service + model, not a catalog row** |
| **Reranker** | `llama.cpp server-vulkan` (`--embedding --pooling rank --rerank`), routed as LiteLLM **`jina_ai/`** | `bge-reranker-v2-m3` **Q8_0** (635.7 MB) | RX 7600 / Vulkan | **~327 MiB** | **0.34–0.50 s** / 20 docs · **0.95 s** solo deployed · 1.15 s under three-way load | ✅ live (`reranker`, :9001, row `local-rerank`, ranking verified) · **ships DORMANT** (its consumer does not exist yet — §10) |
| **STT (voice)** | `whisper.cpp:main-vulkan` (`--inference-path /v1/audio/transcriptions`) | `large-v3-turbo` **fp16** (q5_0 = −1.0 GiB option) | RX 7600 / Vulkan | **1788 MiB** (Δ1722) · q5_0 **786** | **0.40 s** per 11 s WAV · **0.53–0.60 s** on real Slovenian radio speech | ✅ live (`whisper`, :9000, row `local-stt`) · CPU fallback native at init: 17.5 s |
| **Gateway** | `lan-litellm` + own Postgres | — | CPU | — | — | ✅ live; the three pinned rows are in its DB and each answered **through** the gateway (§4a) |
| **immich-ML** | immich's bundled ROCm | CLIP / face / doc | RX 7600 / ROCm | 0 idle · **3–5 GB** during a job | job-bound | ✅ live · **lowest priority**, pause-able (Sunshine glue) |
| **Sunshine** | VCE/AMF encode | — | RX 7600 | not a KFD compute consumer | — | ✅ live · gaming-first |
| **Piper TTS** | piper | — | **CPU in HA on the Pi** | — | instant | ✅ live |
| **Generation** | spark vLLM behind `llm.kogler.si` | `qwen3.8-flash-next`, 262k ctx | not on oldsrv | — | ~11 tok/s decode | ✅ live · harnesses reach it **directly** (#26) |
| **RAG reader** | `rag-mcp` · Qdrant · Docling | — | VPS | — | — | ⚠ stub — see the status block and §10 |

**Tier budget** (`mem_info_vram_used` deltas — treat as RELATIVE, [bench §3c](services-ai-bench.md)):
all-Vulkan tier = **~2.4 GiB of 8 GiB** (embed 0.33 + rerank 0.33 + STT 1.72; **2475 MiB measured with all
three warm**, idle baseline 66 MiB), host RSS **≈415 MiB** across the three legs, and **zero `/dev/kfd`
consumers in the AI tier** — which removes the per-ROCm-runtime host-RAM tax entirely. Three-way concurrency
(STT+rerank+embed simultaneously) costs ≈1.5–2× each and is **flat over 6× sustained** load, with **0
`amdgpu` hang/reset lines**; measured aggregate 1.25 s vs 2.00 s sequential. immich-ML (3–5 GB) co-resides at
the low end of its range (⚠ arithmetic, not live-verified — [hardware-gpu.md](hardware-gpu.md)).

**Engine family:** two published images, one backend family —
`ghcr.io/ggml-org/llama.cpp:server-vulkan` (embed + rerank) and
`ghcr.io/ggml-org/whisper.cpp:main-vulkan` (STT). Both are **mutable aliases ⇒ digest-pinned** per
CONVENTIONS §7, with GGUF/GGML model-fetch tasks verified against the sha256s in
[services-ai-bench.md](services-ai-bench.md) §1.

#### 3a-1. Deployed shape

The runbook values, so a re-deploy or a rebuilt DB does not re-derive them. All three legs sit on
`llm-backend` (`external: true`) with **no `ports:` and no Traefik labels** (the network *is* the
boundary and only `lan-litellm` may speak to them).

| Service | Image pin (`group_vars/all/versions.yml`) | Listen | Weights (`:ro`) | Model sha256 | Mem cap |
|---|---|---|---|---|---|
| `whisper` | `whisper_cpp_vulkan_image` (`main-vulkan@sha256:cf102ac3…`) | `:9000` (`ai_tier_whisper_port`) | `/srv/models/whisper/ggml-large-v3-turbo.bin` (1 624 555 275 B) | `1fc70f77…2bc69` | `4g` |
| `reranker` | `llama_cpp_vulkan_image` (`server-vulkan@sha256:7158edb4…`) | `:9001` | `/srv/models/reranker/bge-reranker-v2-m3-Q8_0.gguf` (635 676 416 B) | `a43c7c9b…a1d3` | `4g` |
| `embed` | same llama.cpp digest as reranker | `:9002` | `/srv/models/embed/bge-m3-q8_0.gguf` (634 553 760 B) | `aa473d51…a173` | `4g` |

**Why the GGUF caps are `4g`.** What the cap has to cover is the binary's **CPU-fallback path — 1.59 GiB
RSS**, the number this file carries on the whisper leg, plus headroom. A leg that falls back to CPU under a
cap below that peak is killed by its own limit, and the kernel reports that kill as GPU trouble:
`amdgpu: init_user_pages: Failed to get user pages: -1`, preceded by `Memory cgroup out of memory: Killed
process … (text-embeddings) total-vm:13095828k` (`CONSTRAINT_MEMCG`).

**What is deliberately NOT claimed:** the over-cap path was not reproduced. With the cap at 4g, a
318 KB / 120-item batch (58.6 s, 2.6 MB of vectors, `http 200`) peaked the cgroup at **200 MiB** with
`memory.events` all zero (`oom_kill 0`). So the cap removes a **documented** failure mode and aligns it with
the sibling leg's doctrine; it does not claim a reproduced one. If that `init_user_pages` line ever comes
back, look at the cgroup first, not the card.

**Judging a symptom bounded vs recurring:** read the rotated `/var/log/kern.log.*`, never the live `dmesg`
buffer — a wrapped ring buffer holds only the last window and makes a recurring symptom look bounded.

**Context and batch sizing (measured, not guessed):** both GGUF legs run
`--ctx-size 2048 / --batch-size 2048 / --ubatch-size 2048`
(`ai_tier_gguf_ctx_size` / `ai_tier_gguf_batch_size` / `ai_tier_gguf_ubatch_size`).
Reason: llama.cpp **truncates silently** beyond the window on the generation path and `llama-server`'s own
default is 512 — which would slice the documented ingest chunk (§5b: token-based **512/64**) in half. 2048 =
that spec with 4× headroom (bge-m3 supports 8192; paying KV memory for chunks that do not exist buys
nothing). **`--ubatch-size` is the binding limit, not `--ctx-size`** — finding 1 below. Re-derive when `rag-mcp` goes live (§10) and a real chunk size is measurable.

**Model fetch is generic, not bespoke:** `roles/docker_services/tasks/deploy-service.yml` has an opt-in
`svc.model_url` / `model_dir` / `model_file` / `model_sha256` hook (the same opt-in-registry-key pattern as
`bind_owner_uid` / `db_role_sync`). `get_url` + `checksum` is idempotent **by content**: a present file with
the right digest is a no-op; a digest mismatch **fails the converge** rather than booting an engine on half a
the model. There is no `default()` on the digest — `model_url` without `model_sha256` aborts the render
(fail-loud). Weights are public artifacts: never in git, never in the vault, and (like `ollama`/`spark-ai`)
these templates stay OUT of `_template_vault_items` and render with zero vault lookups.

**Device + gid:** the legs mount **only** `gpu_vulkan_render_node` = `/dev/dri/renderD129` (RX 7600
`gfx1102`); `renderD128` is the HD 630 iGPU — the desktop's Xorg device and the Jellyfin QSV transcoder, and
measured slower than CPU for this work. `group_add` uses `gpu_render_gid`, which is **992** on oldsrv
(measured); the Debian-table `104` is `ssl-cert` there. Details + the trap:
[hardware-gpu.md](hardware-gpu.md) §Group IDs.

**Onboarding steps 6.5 / 7 (CONVENTIONS §5):** weights live on the `nvme/models` dataset
(`/srv/models/<leg>`), which `roles/storage` treats as **regenerable** — no snapshots, not in the Kopia /
`db-backup` scope (same rule as `ollama`/`immich-ml`): gigabytes of public, digest-pinned weights are
cheaper to re-fetch than to back up. No dedicated exporter: the legs are covered by oldsrv's Alloy host
metrics plus the `amdgpu` sysfs `mem_info_vram_used` counter, and their logs use the stock Docker logging
driver. Nothing here adds a scrape target or a dashboard.

#### 3a-2. What the deploy actually proved (and did not)

`docker inspect` — not the Ansible RECAP — proves the spec: `devices=[/dev/dri/renderD129]` only, **no
`/dev/kfd` anywhere in the tier**, `ports=map[]`, `restart=unless-stopped`, `cap_drop=[ALL]`, image by digest.

| Measurement | Result on the deployed containers |
|---|---|
| Tier VRAM | **2475 MiB** all-warm (target ~2.4 GiB / 8 GiB — hit); idle baseline 66 MiB |
| Host RSS | **415 MiB** (whisper 96 + reranker 157 + embed 162) |
| Embed | dim **1024**, ‖v‖ = **1.000000**; **0.45 s** for a 51-document batch |
| Rerank | **0.95 s** solo for a 20-doc top-5 (real Slovenian), correct ranking (relevant −2.7 vs −11.0 irrelevant) |
| STT | **0.53–0.66 s** per ~7–13 s clip of **real Slovenian broadcast speech** (CJVT GOS corpus, converted in-container with the image's own `ffmpeg`) |
| Three-way concurrency | 1.15–1.19 s each simultaneously vs 0.60/0.95/0.45 s solo; **total 1.25 s < 2.00 s sequential** |
| Kernel | **0 `amdgpu` hang/reset.** ⚠ reading `dmesg` here needs `sudo` (`read kernel buffer failed` otherwise) — an unsprivileged count silently returns 0; a *falling* raw count is **ring eviction**, not recovery |

**Three things this does NOT establish** (each keeps its own owner):
1. **No scoped consumer reaches these rows** — every probe used the master key, so per-key routing and the
   allow-list are open work (**§10**). Nothing a family member runs changed behaviour.
2. **2475 MiB is a steady-state reading** — a one-shot startup peak (three simultaneous Vulkan inits) is
   invisible to `mem_info_vram_used` sampled after warm-up.
3. **The rank reranker's quality is unmeasured** — no nDCG@10 against labelled data, and the CPU-vs-GPU
   latencies come from two different harnesses, so treat the speedup as an estimate.

#### 3a-3. Three findings that only a live box produces

1. **`--ctx-size` is not the batch limit — `--ubatch-size` is.** With defaults, an 842-token chunk answered
   **HTTP 500 `input (842 tokens) is too large to process. increase the physical batch size (current batch
   size: 512)`** — and the first fix (`--batch-size 2048 --ubatch-size 512`) failed identically, because the
   number in the message is the **ubatch**. With both at 2048 the same request returns 200 and the log reads
   `n_tokens = 842, truncated = 0`. VRAM cost of ubatch 512→2048: **~15–35 MiB** (compute buffers scale with
   ubatch, not ctx). Note the direction matters: an **oversized** input on the **embedding** path is a loud
   500, not silent truncation — truncation is a generation-path hazard, so embeddings are safer than
   assumed, but a chunk over ~2048 tokens fails ingest loudly.
2. **The `llama.cpp` image hardcodes `HEALTHCHECK curl http://localhost:8080/health`.** Our legs listen on
   9001/9002, so both GGUF containers reported **`unhealthy` while answering 200** — a false alarm that
   poisons any "what is live" census. Fix: an explicit `healthcheck:` per leg on its own port
   (`start_period: 90s` for Vulkan init + weight load). **Any future leg on a non-8080 port must override it
   too.**
3. **LiteLLM's `openai/` embed provider forwards `encoding_format: null`, and llama.cpp rejects null**
   (`[json.exception.type_error.302] type must be string, but is null`) — the leg worked, the **gateway row
   did not**. `hosted_vllm/bge-m3` on the same `api_base` works (dim 1024 verified through the proxy), so the
   embed row is `hosted_vllm/…`. `user: null` is tolerated; `encoding_format: null` is not — invisible from
   the outside, hence recorded.

---

## 4. LLM routing & keys

- **Through the gateway (the rule):** any consumer that must not hold an upstream credential authenticates
  to **LiteLLM only**, via a per-consumer **scoped virtual key** — never `openrouter_api`, never the
  master key. Open WebUI, OpenClaw and Qdrant's embed/rerank path do this today, and so does Home Assistant
  through the LAN `home-assistant` record; Docling is covered by the rule but has **no key yet** (§10).
- **Direct to the engine:** the coding harnesses (workstation pi.dev, Continue.dev, future dedicated
  harness deploys) → `https://llm.kogler.si/v1`. Rationale in §9 row 26 + §9d; the client-side contract in
  [pi-harness.md](pi-harness.md) §1b.
- **External generation:** one `openrouter_api` key (api → credential) reused for **all** external
  chat/LLM models, declared in LiteLLM's `config.yaml`; any model on OpenRouter is selectable through the
  one LiteLLM dropdown.
- **spark generation:** `spark/qwen3.8-flash-next` is a **runtime DB entry in both instances**
  (`api_base https://llm.kogler.si/v1`, **no key in the row** — the bearer comes from the container's
  `OPENAI_API_KEY` env, see §9c for why a DB row cannot reference the vault). The container needs
  `extra_hosts` glue for `llm.kogler.si` (both hosts' `resolv.conf` is public-only by design and `/etc/hosts`
  is not inherited by containers). **https, not http:** spark's :80 edge is redirect-only and the OpenAI SDK
  does not follow a 307 on POST.
- **Embeddings / rerank / STT:** the three Vulkan legs on the oldsrv RX 7600 (§3a), reached through the LAN
  instance. Embeddings stay **1024-dim `bge-m3`** on both legs — the same vector space on either engine
  (cos 0.9996), so no corpus migration is needed.
- **Local models are listed via LiteLLM** so family sees local + cloud in one dropdown; local is the default
  where privacy/offline matters.

**Local model guidance** (office/voice workloads; this doc is the platform SSOT for model guidance):

| Model | VRAM | Best for |
|-------|------|----------|
| **Llama 3.1/3.2 8B** | ~6 GB | Everyday office, email drafting, summarization (via LiteLLM — OpenRouter today) |
| **Qwen 2.5/3.5 7B–14B** | ~6–12 GB | Complex document structuring, code generation (via LiteLLM) |
| **Phi-4 14B** | ~10 GB | Reasoning, logic, Microsoft workflow drop-in (via LiteLLM) |
| **`spark/qwen3.8-flash-next`** | spark 128 GB unified | Heavy programming / long-context reasoning — one big model, largest context, on the spark engine ([hardware-spark.md](hardware-spark.md)) |

**1Password (`Homelab-ansible`) items — see [`deployment-secrets.md`](deployment-secrets.md):**

| Item | type → `field=` | Used by |
|------|-----------------|---------|
| `openrouter_api` | api → `credential` | LiteLLM (all external LLM generation) |
| `litellm_api` | api → `credential` | admin/bootstrap ONLY — **this IS the master key** (`LITELLM_MASTER_KEY`); there is no `litellm_master_key` item, despite how the name gets typed |
| `litellm_db` | db → `password` | litellm-db runtime DB (models-in-DB) |
| scoped keys (`owui-public-chat_api`, `owui-public-rag_api`, `owui-int-wife_api`, `owui-int-owner_api`, `dsh_api`, `openclaw-litellm_api`, `rag-int-svc_api`) | api → `credential` | per-consumer minted keys |
| `spark-llm_api` | api → `credential` | the spark engine's bearer (container env, never a DB row) **and** the direct-harness copy in the rendered seat configs — until the gateway-credential switch below completes it is also what both gateways send upstream |
| `litellm-engine_api` | api → `credential` | **the gateway's own engine credential** — the second accepted `--api-key` value on the engine, and `OPENAI_API_KEY` in both LiteLLM containers once step (2) of the switch lands. Guard-listed in `provision-secrets.py`: rotating it needs a spark restart, like `spark-llm_api` |
| `openwebui_secret` | password → `password` | Open WebUI session/encryption secret |
| `qdrant_db` | api → `credential` | Qdrant (no username; single static API key via `QDRANT__SERVICE__API_KEY`) |

> Fail-closed secrets: no `default('')` — a missing item fails the render loudly.

**Scoped consumer keys:** Postgres-backed; models are Admin-UI-managed; bootstrap glue mints the
per-consumer virtual keys (lookups are fail-closed thereafter). Specs SSOT in `group_vars/vps.yml`:
`owui-public-chat` · `owui-public-rag` · `owui-int-wife` / `owui-int-owner` · `openclaw-litellm` ·
`rag-int-svc`; starting budgets/durations are Admin-UI-editable.
**The LAN instance has ONE minted consumer:** the record `home-assistant` → `home-assistant_api`, minted by
`bootstrap_keys: true` on `lan-litellm` inside that service's own deploy pass. Every other call on that side
still runs on the master key, and the pinned-AI legs still have no per-consumer caps — that is open work
(§10). The record **is** consumable: HA **2026.8** ships a stock `litellm` conversation integration (this repo
pins `2026.9.4`) that takes **any proxy URL + an optional virtual key** and lists its models from `/v1/models` — so
what the `home-assistant` row must satisfy is visibility of `spark/qwen3.8-flash-next` **to that key's
`/v1/models`**, the same endpoint the glue probes below
([smart-home-voice.md](smart-home-voice.md) §the LLM leg).
⚠ On the **VPS** instance the allow-lists still name `ollama/*` model names that no longer exist after
decision #27 — correcting them (and adding the real rows for the real consumers) is open work (§10), and the
model-catalog doctrine below governs how. The LAN instance's one record grants the named
`spark/qwen3.8-flash-next` row and nothing else — no wildcard, no `ollama/*`
(`litellm_scoped_keys` in `group_vars/home_servers.yml`).

**`spark-llm_api` is triple-used until the split completes.** The item is load-bearing in three places at once: the engine's own `--api-key`, the
`OPENAI_API_KEY` **both** LiteLLM instances send upstream, and the direct-harness credential in the rendered
seat configs — which is why
[deployment-ai-stack-secrets.md](deployment-ai-stack-secrets.md) §4a treats it as a set-rotation rather than a
value. A separate item, **`litellm-engine_api`** (catalog row + vault item, 32-char token, value verified
distinct), gives the **gateway leg its own credential**. It works because vLLM accepts MULTIPLE keys —
`--api-key` is `nargs='+'` (measured on the running build: `[--api-key API_KEY [API_KEY ...]]`) — so the
`spark-ai` template renders both accepted values, harness key **first**, because
`roles/spark/files/spark-oom-watchdog.sh` reads the token following the first `--api-key` as its `/metrics`
bearer. ⚠ **SGLang is the exception**: its `api_key` is `Optional[str]` (`server_args.py`, one key), so a
fast-sglang profile cannot carry both credentials and the gateway leg must be re-decided (edge allow-list or
a translation hop) before that profile ever goes live. ⚠ **Ordering is a landmine if inverted** — the engine
only accepts the new key from its **next boot** onward, so the switch is two converges, in this order:
**(1)** spark (`spark-ai`, an engine restart — PLE-table load, `start_period` ~20 min, so an owner-window
action, not a blind one), then **(2)** `lan-litellm` on oldsrv + `litellm` on the VPS with
`OPENAI_API_KEY: vault['litellm-engine_api'].credential`. Step (2) is deliberately **not rendered yet**; before
flipping it, prove the engine already accepts the new credential —
`curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $(op read 'op://Homelab-ansible/litellm-engine_api/credential')" https://llm.kogler.si/v1/models`
must answer **200**.
⚠ **The glue is CREATE-ONLY, and that decides what "grant a consumer" means**: a vault item that already holds a value is only *probed* (`GET /v1/models`; 200 = keep,
401/403 = `ABORT rc2`) — its server-side params are never updated. So editing `models:` or budgets on an
existing record (e.g. handing the four live `owui-*` keys the `spark/qwen3.8-flash-next` row) changes
nothing about the live key. Granting an existing consumer another model needs `/key/update` (not
implemented — open work, §10) or a deliberate re-mint (clear the item, delete the alias,
which invalidates the running consumer). Never report an allow-list edit as a shipped grant.

> 📋 Deploy checklist: [`deployment-ai-stack-secrets.md`](deployment-ai-stack-secrets.md).

### 4a. Model catalog rows — runbook (runtime DB)

Model rows live in the LiteLLM **DB**, never in git (decision #13). Create them with
`POST /model/new` against the target instance with the master key (read `op read
'op://Homelab-ansible/litellm_api/credential'` into a variable, never echo it). The pinned-AI rows below are
on **`lan-litellm`** (oldsrv); `spark/qwen3.8-flash-next` exists on **both** instances.

Current row ids (the handle for a later delete/replay): `local-rerank`
`08f7e525-6a7b-4258-b940-54e23433a47a` · `bge-m3-vk` `ac74a51f-ab6b-4eaa-a0c2-88cdb4ce40b6` · `local-stt`
`4a47bb86-39bc-412b-a46d-1a6a692a779d`.

```bash
# from the oldsrv shell (lan-litellm is on the same compose host, no publish needed)
K=$(op read 'op://Homelab-ansible/litellm_api/credential')   # master key; never echo $K

# 1. RERANK — provider jina_ai/, LITERAL api_base (DB rows do not expand os.environ/, §9c).
#    jina_ai's get_complete_url REPLACES the path with /v1/rerank → api_base carries NO path.
curl -s -H "Authorization: Bearer $K" -H content-type:application/json \
  -d '{"model_name":"local-rerank","litellm_params":{"model":"jina_ai/bge-reranker-v2-m3","api_base":"http://reranker:9001","api_key":"sk-none"}}' \
  http://localhost:4000/model/new

# 2. EMBED — llama.cpp serves OpenAI-shaped /v1/embeddings; here api_base DOES carry /v1.
#    ⚠ provider = hosted_vllm/, NOT openai/ (openai forwards encoding_format:null → llama.cpp 500, §3a-3).
curl -s -H "Authorization: Bearer $K" -H content-type:application/json \
  -d '{"model_name":"bge-m3-vk","litellm_params":{"model":"hosted_vllm/bge-m3","api_base":"http://embed:9002/v1","api_key":"sk-none"}}' \
  http://localhost:4000/model/new

# 3. STT — whisper-server serves the OpenAI path natively (--inference-path), no wrapper.
curl -s -H "Authorization: Bearer $K" -H content-type:application/json \
  -d '{"model_name":"local-stt","litellm_params":{"model":"openai/whisper-1","api_base":"http://whisper:9000/v1","api_key":"sk-none"}}' \
  http://localhost:4000/model/new
```

**Rules for this table:**
- **`lan-litellm` has no `curl`** — drive its API from the host against its `llm-backend` container address
  (`docker inspect` for the IP), or from any container shipping a client. Never write the bridge IP into a
  doc: it moves.
- **Admin endpoints (measured on the pre-v1.104.0 build, not on the current `litellm_version` pin — re-verify
  them there before trusting one):** `/model/list` is **not** usable with the master key (it answers
  `{"detail": …}`) — **`/model/info`** is the one that enumerates rows; and **`/model/delete` takes
  `{"id": …}`**, not `{"model_id": …}` (the latter is a 422 that says which field it wanted — do not assume).
  The KEY endpoints have the same shape trap: **`/key/list`**
  is the only enumerator (it returns `{keys:[<token hash>…]}`, the aliases are NOT in it), **`/key/info`
  404s without `?key=`**, and **`/key/delete` wants `{"keys":[…]}` or `{"key_aliases":[…]}`** — a singular
  `key` is a 422. The DB tables are quoted-mixed-case (`"LiteLLM_APIKey"`) and only reachable through the
  container's own psql.
- **The Ollama fallback is a rung, not a row.** The Vulkan embed leg has its own row; Ollama stays as the
  documented fallback of the SAME 1024-dim space. **Neither LiteLLM DB contains an `ollama/*` row**, so
  "keeping" it means keeping the service + the model (`bge-m3` re-verified at dim 1024). Re-pointing a
  consumer to either leg is open work (§10).
- **`bootstrap_keys` is `true` on the LAN instance**: the glue runs inside `lan-litellm`'s own deploy pass,
  and `home-assistant_api` mints from the converge (`rpm: 30`, ROW-only grant, no wildcard). Two standing
  constraints: an empty spec list is the ONLY thing the fail-loud gate protects (the record must never be
  emptied while the flag is on), and **the ordering contract in `home_servers.yml` is live, not inert** — a
  `bootstrap_keys` service must precede its consumers in the list because the glue refreshes the vault dict
  they render from.
- **⚠ An orphan virtual key lives in the DB that minted it, not in the DB that fails** — locate a stale alias
  by `/key/list` on **both** instances, never on the host where the symptom appeared. Deleting one needs an
  alias guard: `/key/info?key=` → exactly one match, `last_used=None`, `spend=0`, vault item confirmed absent
  first. The alias `dsh` is **absent by design**: its consumer is rejected (decision #26), so its record is
  never restored. ⚠ Same class, deliberately kept: alias `pi-harness` stands on the VPS and
  `pi-harness_openai_api` **still holds a value** — a parked key of a parked consumer, not an orphan.
  `test-probe-a0b651` (never used) is probe residue. `pi.dev laptop` (hand-created) is a **live consumer — do
  not delete it**.
- **Two traps:** a `--check --diff` on a LiteLLM converge renders **live keys into the log**; and a green
  **scoped** converge (`-e docker_services_scope=… --tags docker_services`) can **skip** the named service
  and still print `failed=0` — prove a deploy with `docker inspect` / the rendered file, never the RECAP.
- **Path composition (verified live):** LiteLLM appends `/embeddings` and `/audio/transcriptions` to the
  `api_base` it is given, so the `/v1` suffix belongs on the embed and STT rows and must **not** appear on
  the rerank row (jina_ai discards any path and posts to `/v1/rerank`).

### 4b. Model-catalog sync doctrine (⏳ glue not implemented)

Git is the source of truth for **what exists**; the LiteLLM DB + `litellm_scoped_keys` are what is
**available and to whom**. When the reconciler lands: **onboard** = idempotent upsert (`POST /model/new`,
vault-first, the bootstrap-keys glue pattern); **offboard** = delete the DB row **and** drop its allow-list
entry in the **same change** — a scoped key must never still authorize a model that no longer exists;
**manual / OpenRouter models are never touched** (deletes are scoped to previously-synced names, so a
hand-added model cannot be clobbered even on a name collision). Today the equivalent is this manual runbook.

### 4c. The LiteLLM admin UI (`/ui`) — what the pinned image actually serves

**The fleet pins `litellm_version: v1.104.0`**
([`../IaC/ansible/group_vars/all/versions.yml`](../IaC/ansible/group_vars/all/versions.yml)); on that build the
"no SPA fallback, use `/fallback/login`" diagnosis does not hold. Measured on both instances, from oldsrv, at
the app and through the edges:

* **The image contains no nginx at all** (`command -v nginx` → nothing; no `nginx.conf` anywhere in
  `/app`, no `_experimental`-serving web server). The UI is a **Next.js static export** shipped inside the Python
  package at `…/site-packages/litellm/proxy/_experimental/out/` and served by the FastAPI app itself (Starlette
  `StaticFiles(html=True)`) — there is no upstream `ui/nginx.conf` for it to ship.
* **`/ui/login` does not 404.** The export carries a real `login/index.html`, so the request gets
  **307 → `/ui/login/` → 200** (24.5 KB of HTML). Swept across every exported route on the LAN instance — `login`,
  `api-keys`, `teams`, `models-and-endpoints`, `model_hub`, `usage`, `cost-tracking`, `playground`,
  `router-settings`, `guardrails`, `mcp-servers`, `organizations`, `users`, `access-groups`, `budgets`, `caching`,
  `chat`, `prompts`, `skills`, `workflows`, `vector-stores`, `search-tools`, `tool-policies`, `transform-request`,
  `ui-theme`, `memory`, `logs` — **27 of 28 resolve**, and the one that did not (`agent-settings`) is not a route
  in the export at all. `/fallback/login` also answers 200; it is not the only way in.
* **The one honest wrinkle, and why it is not a bug:** the 307's `Location` is built **scheme-blind** (`http://…`,
  uvicorn runs without `--proxy-headers`), so the browser is told to hop to plain HTTP. Both edges absorb it: the
  home edge and the tailnet edge each run `:80` as **redirect-only** and put `hsts@file` on `websecure`, so the hop
  lands on `:80`, is 301'd back to HTTPS, and the page loads — measured `code=200` after 1 redirect against
  `https://llitellm.kogler.si/ui/login`, with `strict-transport-security: max-age=31536000; includeSubDomains` on the
  response so an HSTS-aware browser skips the hop entirely. One wasted round-trip, no user-visible failure.
* **A path below an exported route** (`/ui/teams/<id>`) has no directory and no
  `[param]` segment in the export, so it 404s server-side. Those URLs are client-side transitions inside the SPA,
  not deep links this homelab shares — if that ever changes, the fix is an nginx hop with `proxy_redirect` + a
  `/ui/`-scoped `error_page 404` fallback (⛔ not forward-auth on `/ui/*` route-wide, which breaks the same-host API
  bearer consumers), and the nginx hop belongs in front of the container's published port so the edges stay
  untouched. A sidecar for a defect that measures absent is how a lane invents its own failure surface.

---

## Docling OCR engine selection — measured on the live service

Measured against `quay.io/docling-project/docling-serve-cpu:v1.30.0` (the pin has since moved to `v1.36.0` — re-verify the numbers on it) against
**two real Slovenian scans** — a UKC Ljubljana discharge
summary, page 1 = crisp form + diagnosis table, page 2 = small light-print prose. A synthetic render is not a
scan, so everything below is measured on the real pages.

### What the deployed engine actually is

| Question | Measured answer |
|---|---|
| Which OCR engine does the served pipeline use? | **RapidOCR / onnxruntime, PP-OCRv6 small.** Served log, on every conversion: `Auto OCR model selected rapidocr with onnxruntime.` + `[RapidOCR] Using …/RapidOcr/PP-OCRv6_{det,rec}_small.onnx` + `ch_ppocr_mobile_v2.0_cls_mobile.onnx`. `OcrAutoModel` on Linux resolves nemotron → **rapidocr+onnxruntime** → easyocr, and this image has rapidocr, so EasyOCR is never reached |
| Is `rapidocr` installed in the pinned image? | **Yes** — `rapidocr 3.9.2`, alongside `easyocr 1.7.2`, `onnxruntime 1.28.0`, `docling-slim 2.118.0`, `docling-serve 1.30.0`, `torch 2.13.0+cpu` (`pip list` + `GET /version`) |
| Which image tag is live? | The IaC pin (`docling_version`) is **`v1.36.0`** — the pin is the SSOT for what is deployed; **2.118.0 is the docling-slim library version** that `/version` reports. Two different numbers, not pin drift |
| Does `sl` need a download? | **No.** `sl` is a first-class PP-OCRv6 code (`rapidocr.utils.model_resolver.PP_OCRV6_LANGS`, 52 codes, `sl in` → True) and PP-OCRv6 `rec_small` is **multilingual** — the same baked weights serve `ch` (docling's RapidOCR default) and `sl`. EasyOCR's `sl` → the `latin_g2` recognizer, also baked |

### Request-level levers on `/v1/convert/file` (measured, this build)

| Field | Verdict | Evidence |
|---|---|---|
| `do_ocr=false` | **honoured** — this is the free lever for born-digital PDFs | markdown changed (scan1 4370 → 4355 chars, scan2 2891 → 2872) with everything else fixed |
| `ocr_preset` (`easyocr` / `rapidocr` / `tesseract` / `auto`) | **honoured** | `ocr_preset=tesseract` produced `docling.models.stages.ocr.tesseract_ocr_cli_model - command: tesseract --psm 0 -l osd` then `-l fra+deu+spa+eng`, and a different markdown (md5 `12b3e42…`) |
| `ocr_lang` for tesseract | **honoured** | the `-l fra+deu+spa+eng` in the CLI line is docling's *default* `EasyOcrOptions.lang`, i.e. the request/default lang reaches the engine invocation |
| `ocr_lang` for rapidocr | **inert here** — byte-identical output for unset / `sl` / `latin` (md5 `bc05b6dc…` on both pages) | `sl`/`ch` resolve to the same baked multilingual rec; `latin`/`th` resolve to **PP-OCRv5**, whose weights are **not** baked, and the pipeline still produced the same bytes → with `artifacts_path` set, requesting a language cannot change the model file. A `sl` "language setting" is therefore not a lever on this engine at all |

### The Slovenian bench: same physical scan, both engines

Method: both pages rendered once from the PDF (pypdfium2, scale 2.0 ≈ 144 dpi) and fed to each engine
as the same PNG; warm engine, 4 CPUs, in a throwaway container from the pinned image (production
storage untouched). Engine loads: rapidocr 0.3 s, easyocr 2.1 s. Per-page wall time:

| Page | rapidocr (PP-OCR6, live engine) | easyocr (`lang_list=['sl']` → `latin_g2`) |
|---|---|---|
| scan1 (form + diagnosis table) | **2.9 s**, 100 lines / 2085 chars | 9.3 s, 109 lines / 2045 chars |
| scan2 (small light prose) | **2.7 s**, 40 lines / 2331 chars | 7.8 s, 48 lines / 2771 chars |

→ **EasyOCR is 3.2 – 3.4× slower** than the engine already running.

Failure inventory (mechanical, per page):

| Signal | rapidocr | easyocr-sl |
|---|---|---|
| Fragment-soup lines (≥ 6 one-letter tokens = a whole line lost) | 0 on scan1, **5 on scan2** | 0 and 0 |
| Word-merge / junk tokens (lower→upper glue, `_`) | 0 on scan1, 3 on scan2 (`ElN`, `OlT`, `eRp` — all real) | **8** on scan1 (`kirurškaklinkakozatravmatologijo`, `koait_dddelek`, `travmatologiio_EIN`, `dex_`, `WWW_`), 3 on scan2 |
| Diacritic marks recovered | 37 (scan1) / 33 (scan2) | 29 / 38 |

Adjudication of the words the two engines disagree on (Slovenian validity, not popularity):

- scan1, unique to **rapidocr**: `kirurška`, `kritični`, `izolacije` are **correct**; `intenzovne`,
  `zdravijenja` are wrong (→ `intenzivne`, `zdravljenja`).
- scan1, unique to **easyocr** (19): `kirurska`, `kriticni`, `stevilka`, `lececi`/`leceći`, `ijubljana`,
  `ljubljnna`, `izbolišanje`, `izolacie`, `einzaloška`, `kirurskaklinika`, `zaravljenja`, `ukcdj`,
  `travmatoloqijo_oddelek`, `gttlteden`, `ielml`… — i.e. **lost** `š`/`č` in caps, `l`→`j`/`n`, `,`→`;`,
  `:`→`.`, `/`→space, plus glued words. ~17 of 19 are defects.
- scan2, unique to **easyocr** (39): `priporočamo`, `preležaninam`, `pomoči`, `višanjem`, `obremenitev`,
  `fizioterapije`, `rehabilitacija`, `endokrinologu`, `osteoporoze`, `parametrov`, `vnetnih`,
  `napoti`, `izbrani`, `aktivacija(tio)`… — **37 of 39 are real content RapidOCR never emitted**: those
  are exactly the five fragment-soup lines (the Fragmin order, the rehabilitation sentence, the
  pressure-sore prevention sentence, the follow-up-labs sentence, the nephrology referral).
- Third independent source, the scanner's own embedded text layer (Canon IJ Scan Utility): 2128/2773
  chars with **0 diacritic marks** and `Zalo5ka`-class damage → the `do_ocr=false` lever must never be
  applied to scans, only to born-digital PDFs.

**Decision: keep RapidOCR. Do not switch to EasyOCR.** On the gate "keep RapidOCR only if quality ≥
EasyOCR": RapidOCR wins the crisp form/table page *including its diacritics* and is 3.2× faster.
EasyOCR wins only the light/small-print prose page, where
RapidOCR drops whole clinical sentences — that is a **recall gap worth its own decision**, not a reason
to buy a 3.2× CPU bill plus a new class of diacritic/merge defects. The gap is open work (§10),
with one measured cheap candidate: re-running rapidocr on the 288 dpi
render cut scan2's fragment-soup lines from **5 → 2 at the same 2.9 s** (rapidocr resizes internally, so
the extra pixels cost nothing at this scale), i.e. raster scale is a per-request knob
(`images_scale`/page rasterization at the call site) worth testing before any engine or model change.

### Where the model weights actually live

- The weights the served pipeline uses are **baked into the pinned image** at
  `/opt/app-root/src/.cache/docling/models` (871 MB), reached because
  `DOCLING_SERVE_ARTIFACTS_PATH` points there: `EasyOcr/{craft_mlt_25k, english_g2, latin_g2}.pth`,
  `RapidOcr/PP-OCRv6_{det,rec}_small.{onnx,pth}` + `ch_ppocr_mobile_v2.0_cls_mobile.onnx` +
  `ppocrv6_dict.txt`, plus the layout/TableFormer/FigureClassifier model dirs.
- The `/srv/docker/docling/models → /models` bind is **empty, root-owned, and unused** (`HF_HOME=/models`).
  A `docling` CLI run in the container dies on `PermissionError: [Errno 13] … '/models/hub'`.
- **Chowning that bind does not make a model reachable.** In production the artifacts directory itself is **read-only** (`read_only: true`
  rootfs; verified: `touch` → `Read-only file system`), and docling-jobkit prints
  `artifacts_path is set to a valid directory. No model weights will be downloaded at runtime.` —
  **3× in the served log** — so with `artifacts_path` set the served path never downloads at all.
  The remedy is therefore a **pre-seeded, writable artifacts location** (a bind carrying the weights,
  with `bind_owner_uid: "1001"` + `bind_dirs`, both already supported by the `docker_services` role) or
  an image that carries what is needed — not a `HF_HOME` repoint.
- Consequences that stand: a recreate is safe (nothing to re-download); anything **not** baked is
  unreachable, which today means **PP-OCRv5 recognisers** (`lang=latin`, `lang=th`), tesseract **`sl`**
  traineddata (the image ships only `eng` + `osd` → tesseract is not a Slovenian option here), and any
  pin bump that drops a baked weight.

### Operational facts

- **A real scan returns real markdown — live 2026-10-07.** `POST /v1/convert/file` answers
  `status: success` with **`md_content` 2021 chars / 317 words**, `layout_score 0.852`, `ocr_score 0.954`,
  `mean_grade excellent`, `errors: []`, with **zero** `failed to map segment` / `Stage … failed` lines in the
  container log (`restarts=0`, `mem=6442450944`). The shape that produces it: the compose runs
  `read_only: true` + `tmpfs: /tmp`, and Docker mounts tmpfs `noexec` (verified: `tmpfs on /tmp … noexec`),
  which torch inductor needs executable for its compiled layout-stage kernels — otherwise
  `OSError: /tmp/torchinductor_default/….main.so: failed to map segment from shared object … /tmp is
  mounted with noexec` and the endpoint returns **HTTP 200 with `status: failure` and empty markdown**.
  So `TORCHINDUCTOR_CACHE_DIR` + `TORCH_EXTENSIONS_DIR` live on `/cache`, a host bind pre-created 1001-owned
  by the role (`bind_owner_uid: "1001"`, `bind_dirs:
  ['models','cache']` in `group_vars/vps.yml`), and `/tmp` **keeps** its `noexec` tmpfs — the `/tmp:exec`
  alternative is rejected, it buys an OCR fix by making a `read_only` container's tmpfs writable+executable.
  The VPS root fs is `ext4 rw` with no `noexec`, which is what makes a bind dlopen-able at all.
  The test asset is a **derived scan** — `docs/assets/manuals/
  comtrend-grg-4260-in-neo-smartbox_navodila-za-priklop.pdf` (Slovenian) rasterized at 300 dpi and
  re-wrapped as an image-only 2-page PDF (0 extractable characters, so OCR is the only path) — chosen over
  a family document deliberately: same pipeline, no family data leaves the box. ⛔ It has not been re-run on a
  real scanner/family photo. Rebuild the same asset with:
  `gs -sDEVICE=pnggray -r300 -dFirstPage=1 -dLastPage=2 -o page-%d.png <manual>.pdf`, then an HTML page holding the
  two `<img>` at native pixel size with `page-break-after: always`, then `libreoffice --headless --convert-to pdf`
  — and **prove it is a scan** before trusting the run: `gs -sDEVICE=txtwrite -o - out.pdf | wc -c` must be 0.
- **Cold start vs the sync endpoint.** In a fresh container the *first* conversion takes ~121 s and the
  request returns **504** (measured 3×); the second returns in 12 s. On the current service the same document
  sent straight to the container's `services-internal` address, no proxy
  in the path, is **94.1 s cold / 11.2 s warm** (96 s / 14.0 s wall) — so the cold leg is survivable *when nothing
  between caller and docling has a shorter timeout*. What is NOT measured is the consumer's own timeout: an
  Open WebUI/OpenClaw ingest with a <90 s client still eats a cold start after every recreate. Warm-up or the
  async endpoint belongs to the **caller**, and is worth one measured real ingest before anyone builds
  machinery for it.
- **Each distinct options set costs another converter, in RAM.** docling-serve caches a converter per
  options hash, so an engine change is also a memory-budget change: a bench container capped at 7 GiB is
  **OOM-killed** while adding an EasyOCR converter on top of the preloaded auto+layout set (rapidocr path
  peak: 3.263 GiB sampled). The compose therefore renders `deploy.resources.limits.memory =
  {{ docling_memory_limit }}` = **6 GiB** (`group_vars/vps.yml`, ~1.8× the measured 3.263 GiB peak and
  below the 7 GiB the bench arm dies at), read back live as `HostConfig.Memory=6442450944`. The ceiling is
  a runaway guard, not a working-set reservation — the VPS is a 15 GB host with ~3 GB available and **no
  swap**, so an uncapped converter is the one shape that takes the host down with it.
- A bench needs a **throwaway container**, not production: production's `/models` bind cannot take a
  file, the container rootfs is read-only (`docker cp` → `container rootfs is marked read-only`), and
  calling the API from the host needs the container's `services-internal` address (no published port).
  From the VPS host: `IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
  docling)` then `curl -F "files=@scan.pdf" -F "do_ocr=true" http://$IP:5001/v1/convert/file`. A multipart
  rejection here means a missing/renamed `files` field, not a broken endpoint.

---

## 5. Knowledge SSOT & RAG pipeline

### 5a. Knowledge SSOT = Forgejo OKF-llm-wiki

- **Git is the source of truth** for `.md` knowledge. Private per-owner repos under Forgejo:
  `wiki-druzina` · `wiki-osebno-moj` · `wiki-sluzba-moj` · `wiki-osebno-zena` + a public KB cohort.
- **Every record = one `.md`** with OKF YAML front-matter: `title`, `type`, `tags`, `generated_at`.
- **`*-generated.md` are outside the corpus** — generated docs are never indexed as source.
- **OpenCloud remains the raw-asset ingress** (PDFs, scans, docs) — the *source* of documents, not the index
  SSOT. Large binaries are referenced, not embedded in the wiki.
- **Qdrant is a rebuildable cache** over that git floor; it is never the source of truth.

### 5b. Retrieval pipeline + decided parameters

1. **Ingest:** raw assets from OpenCloud → optional Docling OCR → canonical `.md` lands in the Forgejo wiki
   repo (git front-matter).
2. **Index:** chunk → embed via **bge-m3 (1024 dims)** on the oldsrv Vulkan `embed` leg through LiteLLM →
   dense+sparse vectors into Qdrant.
3. **Retrieve:** hybrid BM25+vector query → `rag-mcp` reads Qdrant → top-20 → **bge-reranker-v2-m3** rerank
   via LiteLLM → **top-5 clean markdown** → LiteLLM model answers.

| Parameter | Decided value |
|-----------|---------------|
| Extraction | Docling only (`CONTENT_EXTRACTION_ENGINE=docling`, `DOCLING_SERVER_URL=http://docling:5001`) |
| Embeddings | **bge-m3, 1024 dims** via the **Vulkan `embed` leg on oldsrv** (LiteLLM row `bge-m3-vk`) — Ollama `:rocm` is the fallback rung of the same space |
| Reranker | bge-reranker-v2-m3 **Q8_0** local via LiteLLM `/rerank` → `jina_ai/` → llama.cpp Vulkan cross-encoder on the RX 7600. ⚠ its consumer `rag-mcp` is the stub → the leg ships dormant |
| Hybrid | ON by default (dense + sparse BM25) |
| Retrieval | 20 candidates → rerank → top 5, threshold 0 |
| Chunking | token-based 512/64 (`RAG_TEXT_SPLITTER=token` mandatory) — **the number the GGUF legs size ctx/batch from**: an oversized chunk fails ingest loudly (§3a-3 finding 1) |
| Config ownership | `ENABLE_PERSISTENT_CONFIG=false` (env = SSOT) |
| Knowledge split | Public = Family-Manuals KB only; internal = personal / wife-work corpus |
| Vector index | Qdrant, **1024-dim** dense (+sparse) |

> **Dimension lock-in:** the vector dimension **freezes at first ingest**; changing embedding
> model or dimensions later = full re-ingest + backtest. The dim is **1024** (bge-m3). Verify it before the
> first real ingest — nothing has been RAG'd yet, so the choice is still free.

> **Backup posture:** Qdrant is a **rebuildable cache**, so its backup policy is *relaxed* — the
> irrecoverable source is the **Forgejo OKF wiki** + the raw-asset ingress. Still keep a Qdrant snapshot seam
> for iteration speed. Open WebUI + OpenClaw config/state → Kopia.

> **Qdrant `read_only` snapshot gotcha:** the compose sets `read_only: true` (container
> hardening), so Qdrant **cannot create its snapshots dir in the RO rootfs at startup** → panic
> `Can't create Snapshots directory: Read-only file system` → crash-loop. Fix: point the snapshots dir
> **inside the writable storage bind** via
> `QDRANT__STORAGE__SNAPSHOTS_PATH: /qdrant/storage/snapshots`. **This env must stay in the compose
> template.** Keep the `/snapshots` REST export + Kopia-backed host bind as the backup seam
> ([backup.md](backup.md)).

### 5c. Workflows (operational recipes)

The AI layer is a **swappable shell over a git-SSOT + vector-cache floor**.

**A) Ingest a large document (automated, n8n):** drop the file into an OpenCloud "import to RAG" folder →
n8n copies it into the target wiki repo's `/sources/` on Forgejo → chunk + embed through LiteLLM → write
dense+sparse vectors to Qdrant tagged with the project ID.

**B) Edit docs from the web (HITL):** log into Open WebUI (WAN/tailnet + Authentik), pick an agent model,
prompt e.g. "*V @wiki-sluzba dodaj nov konfiguracijski port 9090 v indeks*" → the agent edits the `.md`,
**lints the OKF header**, and opens a **Pull Request via Forgejo MCP** → you review the PR and deploy.

**C) Identity-aware orchestration:** OWUI reads the Authentik JWT and **shows only the MCP tools + wikis the
logged-in group is allowed** (e.g. `groups: ["admin", "sluzba"]`) — OWUI as a router over the permissioned
corpus, not a monolith.

**D) Mem0 long-term memory (planned):** user-scoped memory for OWUI backed by Qdrant, with
`user_id = f"{owui_user_id}-{model_id}"` so each (user, project) pair gets its own memory namespace — no
cross-user leakage. Store = a Qdrant collection, rebuildable like the RAG index.

**Elastic survival:** because knowledge is plain OKF `.md` in git and the index is a rebuildable cache, if
Open WebUI disappeared the whole structure, hybrid RAG and the coding agents keep working from a terminal.

---

## 6. Auth & exposure

- **`ai.kogler.si`** is the Open WebUI instance today, **public** behind **Authentik OIDC** (per-person SSO)
  + the `crowdsec-only` middleware at the Traefik edge (internet-facing → Flaw A). It must hold only
  capability-limited credentials (family-chat + embed keys, no agent keys).
- **`chat.kogler.si`** is **element-web** (Matrix), not an AI UI.
- The **internal, agent-capable OWUI instance is open work (§10)**, not current state.
- **Capability-tiering posture:** internet-facing = limited capability only; full power behind the tailnet;
  new admin/UI surfaces default tailscale-first ([security.md](security.md) §Capability-tiering,
  [network-vpn.md](network-vpn.md) Patterns A/B).
- Per-person history follows the fleet identity model; no shared admin login.

## 7. Integrations

| Integration | How |
|-------------|-----|
| **Open WebUI ↔ OpenClaw** | Register OpenClaw as a LiteLLM model/provider → chatting to the "OpenClaw" model invokes the agent. No bespoke glue. Agent-capable keys stay off the public instance (§10). |
| **Harness ↔ engine / Forgejo** | Per decision #26 the harnesses consume the engine **directly** (no LiteLLM hop) and propose via **Forgejo PRs only** (branch-protected main, no merge rights). Their scoped LiteLLM keys are parked. |
| **Qdrant ↔ rag-mcp ↔ OWUI** | Retrieval via Qdrant + rerank through LiteLLM `jina_ai/`, returning top-5 markdown. Author-side contract only — `rag-mcp` is a stub, so there is no live caller. |
| **Forgejo MCP ↔ wiki** | Agents read/write OKF `.md` and open PRs; never arbitrary filesystem access. |
| **OpenCloud ↔ RAG ingress** | Raw assets (read-only WebDAV) → Docling → wiki (git floor). |
| **OpenClaw ↔ OpenCloud** | WebDAV skill reads/writes family files (summarize, organize, OCR a scan via Docling, draft replies). |
| **Open WebUI ↔ MS Office** | Office MCP bridges (Windows 11 clients) surface Word/Excel/PowerPoint as tools over the tailnet; server-side python-docx/pptx/openpyxl for Linux. See [`services-office.md`](services-office.md). |

## 8. Security & operating notes

- **No host port binds** (Flaw C): overlays + Traefik only; loopback-only if ever needed.
- **Version pinning**: pin LiteLLM, Open WebUI, Docling, Qdrant, OpenClaw (young project) and
  **digest-pin** the mutable `whisper.cpp`/`llama.cpp` aliases. Keep Renovate tracking.
- **Memory:** spark = 128 GB unified, **big-model generation tier** governed by an explicit KV pool
  ([hardware-spark.md](hardware-spark.md) §Unified-memory budget); oldsrv RX 7600 8 GB = pinned AI tier
  (~2.4 GiB measured) + Sunshine encode + immich-ML batch (lowest priority,
  [hardware-gpu.md](hardware-gpu.md)); Piper TTS and Docling are CPU.
- **The legs are unauthenticated by design; the gateway is not** (decision #22). `whisper`/`reranker`/`embed`
  answer anyone reachable on `llm-backend` — the boundary is that network plus the absence of host ports.
  The gateway side is measured, not assumed: `/v1/embeddings` with a bogus bearer → **401 `Invalid proxy
  server token passed`**; with no token → **401 `No api key passed in`**. So only the master key or a real
  virtual key spends the gateway, and `api_keys: []` in `ai-allow` does **not** mean "any key accepted".
  What is still owed is *scoping* (one key per consumer, per-key routing and limits, §10) — not authentication.
- **Secret hygiene rule:** a value read via `op read` is **never printed**, not
  even truncated to prove the read worked — print its **length** and pipe it straight into the consumer; a
  diagnostic probe that prints a partial master-key fragment is the failure this prevents. **The key is not
  rotated for a leak of this class**: rotation moves both instances plus every consumer together, so the
  documented rotation procedure — not a reflex re-key — is what carries it.

---

## 9. Decision log (load-bearing rules)

Superseded/rejected options live in [services-ai-rejected.md](services-ai-rejected.md) and
[services-rejected.md](services-rejected.md). Numbers are the repo's
citation anchors; the wording below is the rule **as it stands**.

| # | Rule |
|---|------|
| 13 | LiteLLM is the spine: **models live in the DB, config in env**, per-consumer scoped virtual keys. |
| 22 | **spark (ThinkStation PGX / GB10) is the generation host**; Mem0 + OpenHands are spark candidates. |
| 24 | **Placement:** oldsrv RX 7600 = the **pinned-services tier** (STT + embed + rerank, small + latency-sensitive); **spark = the big-model generation tier** (one large model, largest context). Piper TTS stays CPU. immich-ML stays on the oldsrv GPU as **lowest priority**. |
| 26 | **Consumption boundary:** generation harnesses go **DIRECT** to the spark name edge; LiteLLM serves the **simple-querier tier**; external APIs are a **harness-side fallback, never a proxy fallback**. Evidence: §9d. Consequences: `dsh`/`pi-dev` parked as services; the LAN `litellm_scoped_keys` carry the one `home-assistant` record, the rest pending §10; hardening `spark-llm_api` belongs at the **edge** (router allow-list / a distinct client credential), not at a proxy. |
| 27 | **Pinned tier engine family = ggml/Vulkan** (§3a): STT `whisper.cpp:main-vulkan`, embed + rerank `llama.cpp:server-vulkan`, **Q8_0** quantization on both GGUF legs, Ollama the embed **fallback rung**. #24's placement stands. |
| 28 | **Vision:** the workstation runs vision as a **text cascade**; **spark is text-only**; the RX 7600 gets **no vision-LLM leg**. Detail: [hardware-workstation.md](hardware-workstation.md), [hardware-spark.md](hardware-spark.md) §Text-only engine mode. The workstation serves **FIM + vision on one GPU**, one resident at a time — `vision-qwen3vl-30b` (images; 23.84 t/s decode, ~56–66 t/s image prefill, 4042–4060 tokens and **61–72 s** for one full-resolution photo; **3.0 GiB of KV at 32k** on its own, so nothing else is resident with it) and `fim-coder-3b` (8 192, the only leg small enough to share the carve). **The agent leg is retired, not deferred**, and the reason is prefill, not the carve: one 20 816-token prompt cost **359 / 899 / 277 s** on three fresh loads of the SAME weights, and the same 10 610 bytes cost **259.15 s** once and **69.42 s** another time — minutes per turn, erratic, so no real agent work is possible on that leg, and `providers.laptop-lmstudio` offers no agent model. **The agent slot does NOT fall back to spark through this runtime** — #26 puts a generation harness **direct** on the spark name edge, so retiring this leg removes a surface, not a capability. `allow_uncertified: true` stays on the dial for the **FIM** leg (its trigger latency is still unmeasured), for no other reason. Rejected so it is not re-proposed: [services-ai-rejected.md](services-ai-rejected.md). Cascade rule: **describe once, freeze the text** — eight full-res photos are a third of the vision window and ~9 minutes of prefill, and re-asking the **same** question costs 2.0 s while a **new** question re-pays the ~60 s, so put the image before the question. Gemma takes no images on this engine at all (a long side over ~1120 px kills the runtime), which is one more reason the box has no Gemma leg. **The vision leg transcribes only when the target fills the frame** — the whole 8160×6120 rack photo read the switch as `CRS326-24G-2S+RM` (five greedy passes) where [network-rack.md](network-rack.md) says `CRS328-24P-4S+`, but a quarter-crop of the same photo read `CRS328-24P-4S-RM` and the repo's own label photo came back character-perfect for **528 tokens in 3.9 s**. Image tokens saturate (~4.1 k whether the input is 8160×6120 or a 3264×3672 quarter), so **crop, do not shrink**: a crop costs the same and reads. Still verify an identifier against the inventory, and when a reading disagrees, re-ask of a crop before believing either answer ([reports/hd474-laptop-leg](../reports/hd474-laptop-leg/) `raw/96`). |

### 9b. Coding plane — agent memory + runners

The **coding plane** (IaC/Ansible, C#, React/Vue, homelab epics) is a **separate plane** from the family
research plane (OWUI/Docling/Qdrant/Mem0). It runs on **oldsrv**, managed from the laptop.

- **Memory = agent-memory.dev, per project (this rule's wording is under an open owner call — see the
  probe note below).** ⏸ **The blueprint stays parked (owner): nothing installed, no plane chosen, no row
  minted.** The OQ-12/OQ-13 answers stand as recorded in the open calls below, OQ-14 stays unanswered, and no
  AI work waits on any of them (the durable negative also stands: LLM memory
  compression scored **R5 0/5** — it rewrites identifiers out of existence). One instance per project (project = 1+ repos), records tagged
  project+repo; **cross-project recall is opt-in, not default**. Data under `~/.agentmemory/<project>`,
  ports 3111+N, MCP = `@agentmemory/mcp`, consolidation LLM via a LiteLLM scoped key. **OpenViking is rejected
  outright**: both candidate roles are dead — the corpus index because its markdown index is
  lossy and not reversible (12/51 files byte-identical; files replaced by H1-title-slug directories), and the
  "memory only" fallback because its write path is LLM-bound per commit on a KV pool that is 1.97× one session,
  while this box measured its L0/L1 payload as worse than a free local extract. Evidence
  [`../reports/probe-ov-20260921.md`](../reports/probe-ov-20260921.md), decision rows
  [`services-ai-rejected.md`](services-ai-rejected.md). OV is **not** Docker-only — it installs venv-native in
  ~2 min — so that is not the reason. Mem0 stays in the OWUI plane.
- **Memory plane — probe note: measured, NOT decided** (`agentmemory` 0.9.29, ephemeral on oldsrv
  under the `domen` seat; interpretation
  [`../reports/probe-agentmemory-20260921.md`](../reports/probe-agentmemory-20260921.md), raw evidence in the
  sibling directory of the same name). Owner rulings on record: **(a)** the wanted
  shape is **ONE central instance**, not one per project — that *relaxes* the per-project rule above **as a
  direction only**; the bullet above is **not** amended until the owner accepts a shape that is implementable
  today; **(b)** "the quadrant" means **[Qdrant](https://qdrant.tech/)** (the vector store
  already live here), **not a host**; **(c)** **Hermes must not keep its own memory store.** What was measured:
  * **Keyless works, and it is the headline** — 7/10 hit@5 with **zero** LLM in the hot path, determinism 10/10
    (same query ×5 → identical ranking), **455 tok/query** injected vs **5,267** for OV, ≈0 spark tokens/session.
  * **The vector leg is an upgrade, not a dependency** — hybrid on our `bge-m3` @1024 beat keyless BM25-only
    **9/10 vs 7/10** hit@5 and **8/12 vs 6/12** exact-identifier recall, at ≈2× recall latency (398 vs 455 tok).
    Memory therefore does **not** depend on LiteLLM; if the leg is used, pin
    **`OPENAI_EMBEDDING_DIMENSIONS=1024`** (upstream `resolveDimensions()` falls back to **1536**) and, in **this
    product's** embedding call, send the model name **bare** (`openai/bge-m3-vk` → 400; `dimensions` is
    accepted-and-ignored on our leg). ⚠ The name rule is **per caller, not global**: OpenViking's own slot config
    needed the provider **prefix** and rejected the bare name (OV probe §2), while our leg rejects the prefix. Two
    callers, two rules — verify per caller, never copy one into the other.
  * **"Central" is not buildable as briefed on 0.9.29** — REST binds `127.0.0.1` and the CLI **re-renders that
    config every boot**, so a LAN bind needs an **authenticating forwarder/proxy** (upstream **#523**); auth is
    **one shared bearer** (no per-client tokens); **`TEAM_MODE`/`TEAM_ID`/`USER_ID` never reach
    `mem::search`/`mem::observe`**, so per-user isolation does not exist in the retrieval path — tenancy would be
    a `project` tag, not enforcement. Two unauthenticated surfaces ride along: the **viewer answers 200 with the
    secret set**, and `iii` listens on **`0.0.0.0:49134`**.
  * **Leave LLM compression OFF** — `CONSOLIDATION_ENABLED` + `GRAPH_EXTRACTION_ENABLED` +
    `AGENTMEMORY_AUTO_COMPRESS` scored **R5 retrieval-key 0/5**: the narratives read well and dropped every
    identifier (ports, timings, token counts, the decision numbers like `#26` and service names like `rag-mcp`).
    Same result as the OV lane's "LLM summary loses to a
    free 154-token extract", in another product with another model ⇒ **on this corpus LLM memory compression
    destroys the retrievable payload**.
  * **The Hermes ruling is implementable** — `memory.memory_enabled: false` + `user_profile_enabled: false` keep
    `MEMORY.md`/`USER.md` at **0 bytes** (0.19.0). ⚠ `hermes memory status` prints `Built-in: always active`
    regardless — **never verify by status** — and a model denied its memory tool wrote its own
    `PERMANENT_NOTES.md`, so a real deployment checks for side-files too. `memory reset` erases content and
    `memory off` disables only the *external* provider; neither is the disable.
  * **Ops facts** — `MAX_OBS_PER_SESSION=500` is a **write-time reject** (603 of 3,291 observations discarded);
    one `POST /search {limit:50}` **killed the worker** (all routes 404 until restart); `AGENTMEMORY_TOOLS=all`
    burns **5.8×** the context of `core` (≈6,044 vs ≈1,042 tokens) per client per session; snapshots are written
    into a **git repo the product creates** (key on `commitHash` — there is no `id`, and `/snapshot/restore`
    rejects `snapshotId`), so the Kopia `backup-snapshot-trigger.sh` seam fits poorly; exit is
    `GET /agentmemory/export` (plain JSON, no CLI verb) ⇒ **lock-in low**; the `iii` **0.11.2** binary ships **no
    verifiable license** (GitHub API `license: None`, no LICENSE file) — record those terms as unverified before
    it ships anywhere. Booting from a different cwd silently switches instance (`dataDirResolution`).
  * **Open owner calls** (measured, waiting on the owner — nothing here decides them): **OQ-12** single central
    plane (not as specified — needs a proxy + `project` tags); **OQ-13** Hermes' store (the central plane is the
    lower-cost option on evidence; **agentmemory can never target Qdrant by design**, so "Hermes on Qdrant +
    everyone on agentmemory" is two planes nobody reconciles — that arm stayed **unmeasured**, Qdrant is
    db-internal and unreachable from the seat); **OQ-14** whether the `bge-m3` leg is needed at all (keyless
    clears every gate; the leg is a measured +2).
  * **A trap that generalises beyond this product (confirmed twice):** a *falsy-but-set* key is a cloud-egress
    switch. `OPENAI_API_KEY=false` made agentmemory dial **`api.openai.com` once per observation**, and Hermes'
    `provider: custom` with a **non-loopback** `base_url` silently resolved to **`openrouter.ai`** (its trust
    check accepts only loopback hostnames). Keyless posture = **leave the var absent, never `false`**. And never
    `docker inspect` a container's env unfiltered.
- **Skills = git SSOT** (`skills/` + `sync-skills.sh`), never a service.
- **ZeroClaw = system-management agent** — laptop primary + oldsrv standby. **Never the VPS** (fleet
  credentials on an internet-facing host is the largest attack-surface increase available). Supervised
  approvals; MCP → agentmemory.
- **CrewAI** = long/epic homelab coding orchestration with mandatory human stop-points. Pilot starts only
  when the homelab is finished; kill criterion = a 2-week vertical slice or abandon. **Parked, not now** — no
  pilot, no spike, no compose; the re-open trigger is one real multi-agent epic
  that a single lane demonstrably mishandles.

### 9b-1. Coding-seat surfaces on oldsrv — the placement decision (`pi-web`, Paseo)

> **Not the Cockpit console.** "Cockpit" in this section means the coding seat's web front-end
> (`pi-web`). The management console at `cockpit-<host>.kogler.si` is [cockpit-project.org](https://cockpit-project.org/),
> a different thing with its own owning role (`roles/cockpit`, routes in `services-traefik.md` §Cockpit Routes,
> break-glass identity in [deployment-secrets.md](deployment-secrets.md)). The two are not the same "cockpit":
> `pi-web` is the surface with **no owning role** (open work, §10).

The owner chose **native host processes under the unprivileged `domen` account**, not containers, and
**not** behind gateway auth. Recorded here because it is a deliberate exception to the shape every other
service in this fleet follows:

| Surface | Runtime | Bind | Auth | Why not the house style |
|---|---|---|---|---|
| **pi-web** | `~/.pi/agent/bin/pi-web` (28 MB Go binary, installed as a **pi package**: `pi install npm:@ygncode/pi-web@beta`), systemd **user** unit `pi-web.service` under `domen`, linger enabled, two drop-ins: `loopback-bind.conf` + `pi-on-path.conf` (the unit must be told where `pi` lives — it shells out to it) | **loopback only**, on `cockpit_pi_web_port`, published as **`https://pi-oldsrv.ts.kogler.si`** by oldsrv's OWN `websecure-ts` listener on `traefik-internal` (`network_mode: host` reaches the host loopback). No LAN socket, no `0.0.0.0`, no VPS edge, no WG S2S hop: a `tailscale0`-address bind is plain HTTP, no cert, and unreachable from every other node in the fleet (`no matching peer`) | `PI_WEB_TOKEN` from `~/.config/pi-web/env` (0600). `?token=` → 302; no token → **401**. A non-loopback bind without a token is refused by the binary unless `-insecure` | A container would mount the whole home tree of the session it watches; the point of the cockpit is to read `~/.pi/agent/sessions/`, so the container boundary would be theatre. `domen` is the blast radius, and it is the account that already owns the sessions |
| **Paseo** | ⏳ **not installed** (parked, with a full resume sequence) — planned as `@getpaseo/cli` under the same account | would use `paseo_port` (6767, upstream's default) on the same tailnet bind | its own `PASEO_PASSWORD` | Same reasoning — and it stays parked because acceptance needs a hand on the phone, so no session can verify it end-to-end |

**Deliberately NOT behind gateway-auth (decision).** A "second host network + gateway-auth route, if the
existing gateway already carries it without contorting the gateway" does not fit, cleanly:
`gateway-auth` authenticates **real client identity** — a phone-driven cockpit has no browser
that can complete an Authentik flow inside a sub-request, and the daemon-to-origin hop would need a machine
credential. So the gate is the **tailnet ACL** (headscale decides which node may reach `31415`) **plus** the
per-daemon token, and TLS-into-Traefik stays with the tailnet/TLS lane.

**Ports are vars, never literals** (`cockpit_pi_web_port: 31415`, `paseo_port: 6767` in
`group_vars/all/main.yml`) — a port written twice is a port someone will change once.
`cockpit_pi_web_port` is read by the
`traefik-tailnet` `pi-oldsrv-backend`, so a port edit is one change instead of three. The unit, both drop-ins
and the token env render from vars via **roles/seat** (below), so they are converged, not hand-kept.
`pi.kogler.si` is not available for this seat's URL — that FQDN is the RPi4 node — hence the `-oldsrv`
host suffix.

**Where the seat's repository lives:** oldsrv carries **two** clones with two
jobs — `/home/ansible-admin/source/homelab` **converges** (and `scripts/ansible-run.sh` fast-forwards it
before every run, `--no-pull` to opt out) and `/home/domen/source/homelab` **is where dev work happens**, the
tree the seat actually edits.

**What is proven, and what is not:** pi + pi-web run under `domen`; the model
contract and provider auth on that box are **rendered from the spec** (`scripts/render-pi-config.py`),
so `pi --list-models` there is produced from git rather than copied by hand; the listener answers 401/302 as
above and the tailnet path is proven from a real peer (below). The tailnet leg stays **unprovable in the
negative direction** from inside this fleet, because every node reachable from a session is itself
ACL-scoped away from oldsrv (the VPS `tailscale-sidecar` answers `tailscale ping <oldsrv>` with
`no matching peer`, which is the ACL working, not a fault); the phone is the first genuine client by design.
Two known costs of choosing beta software: `@ygncode/pi-web` ships **no
README in the npm registry** (the GitHub README is the only contract), and the binary **hard-fails** when
`~/.pi/agent/sessions/` does not exist instead of creating it — so the directory is a documented prerequisite.

**The seat's model leg.** The rendered spark block matches the spec field-for-field and `pi --list-models` on that
box prints `spark | spark/qwen3.8-flash-next | 262.1K | 16.4K | yes | no` — the row
[pi-harness.md](pi-harness.md) §8 predicts — so the harness parses the contract it was rendered. The engine is
reachable **from oldsrv**, and reaching it is one host-resolver fact: oldsrv asks its
own Technitium instance first and the Pi tertiary second (`host_resolver_dns` in
[`host_vars/oldsrv.kogler.si.yml`](../IaC/ansible/host_vars/oldsrv.kogler.si.yml), applied by the
`nm-resolver` leg of `roles/network`), so `llm.kogler.si` resolves to spark's Home address **by DNS** (not
`/etc/hosts`) and the rest of the zone resolves too (`media.kogler.si` → the oldsrv edge, `ai.kogler.si` → the
VPS). Mechanism, the measured target matrix and the traps are
[network-dns.md](network-dns.md) §Host-side resolver. Measured with the
seat's own bearer, the token never leaving a pipe: `/v1/models` returns the row, a bare chat returns
`SMOKE_OK`, and `chat_template_kwargs.enable_thinking=false` → `reasoning_tokens: 0` — the compat block is
**effective**, not merely declared. Bypassing the resolver
(`curl --resolve llm.kogler.si:443:<spark_home_ip>`, no `-k`, certificate validated) proves the same.
The prerequisite that makes a host-side resolver safe is that every DNS instance **forwards** rather than
root-chasing: otherwise pointing a host at an instance trades a ~20 ms direct path for a chase.

⚠ On oldsrv `systemd-networkd` is **disabled and inactive** — NetworkManager holds the address, so the
role's netd renders there are inert and name an interface the box does not have. The per-host config-manager
decision is open work (§10); ask the host with `scripts/probe-net-manager.sh` before editing a manager file.

**The unit needs `pi` on PATH, and `pi-web` has no flag to be told where it is.** `pi-web` is a Go binary
that **shells out to `pi`** for the model list, for every chat turn, and for its own self-update — and
`pi-web -h` offers only `-host -p -token/-insecure -o -version`. A systemd **user** unit gets no login shell,
so it never sees `~/.profile`: `/proc/<pi-web>/environ` reads
`PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin`, while `pi` lives inside the pinned Node tarball
(`~/.local/share/pi-node/node-v22.23.3-linux-x64/bin/pi` — a seat's path changes only when
`install-pi-debian.sh` next runs). Without the `pi-on-path.conf` drop-in the client sees an **empty model
picker** and the API says so: `GET /api/models` → **HTTP 500**
`{"error":"pi executable not found: exec: "pi": executable file not found in $PATH"}`, while
`POST /api/check-update` answers 200 (it reads the registry, never runs pi). With the drop-in,
`GET /api/models` → 200 with **419 models** and
`spark | spark/qwen3.8-flash-next | 262144 | 16384 | reasoning true`.

Traps, each with the runbook step that prevents it ([../deployment-manual.md](../deployment-manual.md)):

- **The Node bin dir must be on PATH, not just `pi`.** `bin/pi` is a symlink to `dist/bundle/cli.js` whose
  shebang is `#!/usr/bin/env node`; with only a `pi` symlink reachable, the call dies as `env: 'node':
  No such file or directory`. A `~/.local/bin/pi` shim is therefore the wrong fix (and `~/.local/bin` is not
  on a user unit's PATH either — `.profile` is a login-shell file).
- **`?token=` is a cookie handshake, so it is useless for an API probe.** It answers 302 and sets a cookie;
  a bare `curl …/api/models?token=…` gets that 302 and no JSON. Drive it with a cookie jar (`-c`/`-b`).
- **A `gsub` on a `-F:` field that starts with a space erases the field** — a derive-the-port line prints
  empty exactly that way (`$2` = `" 31415 …"`, the match starts at character 1, so the whole field is
  deleted; `sub` is as wrong as `gsub`). Use a whitespace `awk`/`sed` form.
- **A `-type f` find cannot see `pi`**: `bin/pi ->
  ../lib/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js` is a symlink, so a `-type f` sweep
  over a home tree reports both the binary and its package as absent.

**The cockpit's Update button restarts `pi-web.service` itself** and leaves the drop-in directory untouched
(`Environment=PATH=…` still in effect after the restart, `NRestarts=0`); **updating pi-web does not update
`pi`**.

**The seat's harness defaults:** `~/.pi/agent/settings.json` carries the whole
[pi-harness.md](pi-harness.md) §5 block (`defaultProvider`/`defaultModel` = spark, `defaultThinkingLevel`,
timeouts, compaction) with the workstation key `packages` preserved, so a seat session starts on the local
engine instead of a cloud model. It is hand-written from §5 **by design**: `render-pi-config.py` has no
settings vendor and `models-spec.yml` states the boundary — the spec renders the *model contract*, never
settings. What the picker offers is 419 rows (openrouter 386 · opencode-go 30 · entrim 2 · **spark 1**)
— the defaults decide the first turn, not the list length.

**The seat, read from the workstation side:**

- **Reachability is proven from a real peer.** `curl https://pi-oldsrv.ts.kogler.si/` from the Windows side of
  the laptop returns **401 served from oldsrv's tailnet address** with the Let's Encrypt `*.ts.kogler.si` pair
  validating *without* `-k`, and the same name forced onto the node address from WSL answers **401 on
  `/api/models`** — so the ACL (`domen@kogler.si → tag:dev:443`), oldsrv's own `websecure-ts` listener and the
  loopback backend all work. The name itself resolves **on Windows and nowhere in WSL**, and that gap is
  DNS-only: the `.ts` plane is answered by the client's own netmap, the mechanism is
  [network-dns.md](network-dns.md) §The answer-plane model, and the sanctioned remedy is the generated alias
  artifact (open work, §10); a routing-domain split is ruled out. ⛔ A hand-typed `hosts` entry is the forbidden
  form — that doc's drift table names that violation.
- **Seat-vs-laptop divergence, measured:** the seat's `packages:` is `[@ygncode/pi-web@beta]` against the
  laptop's `pi-web-access` · `pi-subagents` · `pi-deepseek-optimized` · `context-mode@1.0.169`; `skills/` is
  deployed on **neither** seat (`scripts/sync-skills.sh --check` → "deploy target missing"); a seat clone can
  sit behind with leftover `homelab-wt-*` worktrees. The seat's model leg is right — `pi --list-models` there
  prints `spark | spark/qwen3.8-flash-next | 262.1K`.
- **The seat's SSH door rides the VPS jump.** `sshd -T` on oldsrv admits only `ansible-admin` + `ai-debug`,
  with `passwordauthentication no` and `kbdinteractive no`, so the seat account needs key-only admission plus
  its own `/home/domen/.ssh/authorized_keys`; `ssh oldsrv-domen` then lands `domen@oldsrv` with the
  `ProxyJump vps` hop carrying it. ⛔ Port 22 is not granted on the tailnet (`tag:dev:443` only). A laptop
  `Host oldsrv-domen` block must not disable the one method oldsrv accepts
  (`PubkeyAuthentication no` + `PreferredAuthentications keyboard-interactive,password` is the failure shape),
  and the WSL twin needs the same block.
- **How the seat is built.** The pi-web unit + BOTH drop-ins + the token env + linger + `tmux`
  render from vars via **roles/seat** — its own role, not `roles/cockpit` tasks, because the
  maint-console leg carries a vault-vs-box credential divergence that must stay a hard failure:
  rotating a console credential is an owner act, never a side effect of converging a seat. A bare-Debian
  rebuild is **scripts/install-pi-debian.sh**, not a memory.
  Both seats run the pinned **pi** (`pi_host_npm_version`) on the same pinned Node tarball (**22.23.3** ⏳)
  and the cockpit is
  **pi-web beta.38**; the seat's `settings.json`
  carries the [pi-harness.md](pi-harness.md) §5 block verbatim (`defaultThinkingLevel: high`, the
  900 s idle timeout, the 16 k/32 k compaction pair, the 8 k thinking budget) and a smoke turn on
  the spark leg answers.
  ⚠ **PATH splits by shell kind**: interactive shells get
  Node from `~/.bashrc`/`~/.profile` (which is why `ssh seat` works and `bash -l` sometimes does not),
  a **systemd USER unit gets neither** — that is what `pi-on-path.conf` exists for. A one-shot
  `ssh oldsrv-domen 'pi …'` reads neither file: use the absolute path. Neither may be "fixed" by
  copying a laptop `settings.json` (§1: settings have no renderer by design; §5 is the source).
  Seat commits are signed: the sign/auth keys live in `Homelab-ansible`, so the seat's read-scope SA token
  pulls them with no owner hand, and `user.signingkey` carries the key FILE, which needs no agent —
  CONVENTIONS §6.

### 9c. Ecosystem constraints (verified from primary sources)



Durable facts about the surrounding software — the reason several obvious designs are not used. Cited so the
questions are not re-litigated; the sources are upstream repos/trackers, read directly.

| Fact | Evidence | Consequence |
|------|----------|-------------|
| **Ollama serves no rerank API at any released version.** | v0.34.1 tree: `server/routes` exposes `/api/embed`, `/api/chat`, `/api/generate`; `grep -ri rerank` = 0 hits; PRs #11389 + #7219 closed unmerged; issue #3368 open. Bumping the pin will never add it. | No Ollama rerank host, ever, and LiteLLM has no Ollama rerank provider (`litellm/llms/ollama/rerank/transformation.py` → 404) — an Ollama-hosted reranker would be unroutable anyway. |
| **A cross-encoder cannot be reconstructed from two embeddings.** | `bge-reranker-v2-m3` scores `MLP([CLS] q [SEP] p [SEP])` — joint query+passage attention through all layers. | "Compute rerank from `/api/embed`" is not a shortcut, it is a silent quality loss: the result is a recomputed cosine ≈ the dense retrieval already performed. |
| **TEI has no RDNA3 path.** | `amd_gpu.md`: Instinct MI200/MI300 only, experimental; the CI matrix has one ROCm entry `rocm-gfx942-gfx950`; `grep -rniE 'gfx11\|gfx12\|rdna'` = 0 hits; PR #295 closed unmerged, issue #108 open. | Running TEI on `gfx1102` means a 7-step self-build with flash-attn dropped — and `requirements-amd.txt` pins old `transformers`/`numpy`. Rejected. |
| **`whisper.cpp` publishes no ROCm/HIP container artifact.** | `ghcr.io/ggml-org/whisper.cpp` tags: `main`, `main-musa`, `main-intel`, `main-cuda`, `main-vulkan`, `main-arm64`, `main-vulkan-arm64`; the HIP **Dockerfile exists** (ROCm 7.14/TheRock, `amdrocm-blas7.14-gfx1102`, native `gfx1102` target, no `HSA_OVERRIDE_GFX_VERSION`) but the CI matrix ships no ROCm entry; Docker Hub `ggmlorg/whisper.cpp` → 404. | HIP would be a self-build with **no Renovate digest trail**. STT therefore uses **`main-vulkan`**. |
| **`insanely-fast-whisper-rocm` runs gfx1030 code on this card.** | `Dockerfile`: `HSA_OVERRIDE_GFX_VERSION=10.3.0`; needs `ipc: host`, `shm_size: 8G`, `cap_add: SYS_PTRACE`, `security_opt: seccomp=unconfined`; pulls gradio + demucs + stable-ts (a subtitle toolchain). | Conflicts with this repo's hardening posture and the CWSR exposure ([hardware-gpu.md](hardware-gpu.md)); its features are not used by wake-word → STT → LLM → Piper. |
| **whisper-server can be made OpenAI-shaped by a flag.** | `--inference-path /v1/audio/transcriptions` relocates the route (`/inference` → 404, `/health` stays at root) and the OpenAI multipart fields (`model`, `language`, `response_format`) are accepted. | **No wrapper service needed**; HA Assist is satisfied by the flag alone. |
| **DB-stored `litellm_params` do NOT expand `os.environ/…`.** | Measured live on the pinned image: the literal string is forwarded upstream → engine 401, both through the proxy and in-process. | Keys for DB rows come from the **container env** (`OPENAI_API_KEY`), never from a `os.environ/` reference in the row. |
| **`jina_ai/` rerank accepts a custom `api_base` and rewrites the path.** | `litellm/llms/jina_ai/rerank/transformation.py` in the pinned image: `get_complete_url` replaces any path with `/v1/rerank`. | A llama.cpp `/v1/rerank` endpoint is routable through LiteLLM with **no path in `api_base`** — the answer to "how do we route a local reranker". |
| **`openai/` chat provider param allow-list looks narrow — and it does NOT govern what reaches the engine.** | `OpenAIGPTConfig.get_supported_openai_params` carries `temperature`, `top_p`, `max_tokens`, `stream_options`, `tools`, … and **not** `top_k`, `chat_template_kwargs`, `thinking_token_budget`. A repo-wide grep therefore predicts `drop_params: true` eats them. **Measured on the pin, it does not** (both gateways): the three knobs arrive at the engine unchanged through the `openai/` provider. | ⛔ **Do not re-derive param survival from that allow-list** — it is a conversion table, not the forwarded body. The reasoning/knob question is answered by measurement, in **§9d** (method + numbers). What the grep still legitimately governs: params LiteLLM itself *consumes* (`reasoning_effort`, `max_completion_tokens`, tool schemas) and provider selection for rerank/embed. |
| **ONNX Runtime ROCm / MIGraphX support is Instinct-only** (`gfx942`, `gfx950`). | AMD docs. | There is **no ONNX-GPU on RDNA3** — "CPU fallback if ONNX-GPU proves fragile" is a dead branch on this card. |
| **Per-runtime host RAM is the oldsrv constraint, not VRAM.** | Each ROCm/PyTorch process holds its own rocBLAS/hipBLASLt/MIOpen workspace (~0.5–1.5 GB RSS); a C++ ggml binary sits at ~150–350 MiB. | On a 48 GB host the binding constraint is **host RAM**, which is an argument for one backend family across the tier. |

---

### 9d. The thinking control THROUGH the gateway — measured on the pin

A source read and a live run disagree, so the pin is the referee. Same body in every
cell — one fixed arithmetic prompt, `temperature: 0`, `max_tokens: 320`, model row
`spark/qwen3.8-flash-next` (provider `openai/`, `api_base https://llm.kogler.si/v1`), **master key, no client
change**. Under test: LiteLLM `litellm_version: v1.104.0`
([`../IaC/ansible/group_vars/all/versions.yml`](../IaC/ansible/group_vars/all/versions.yml)) over engine build
`vllm-0.1.dev20073+g8e685d198`.

| Probe | LAN gateway (`llitellm.kogler.si`) | VPS gateway (`litellm.kogler.si`) | Direct engine (control, the decision #26 route) |
|---|---|---|---|
| bare — no switch | 200 · prompt 98 · reasoning **320** (the `max_tokens` cap) | 200 · reasoning **320** | 200 · reasoning **320** |
| `chat_template_kwargs {enable_thinking: false}` | 200 · prompt **58** · reasoning **0** | 200 · prompt **58** · reasoning **0** | 200 · prompt **58** · reasoning **0** |
| `thinking_token_budget: 96` | 200 · reasoning **95** | not re-run | 200 · reasoning **95** |
| `thinking_token_budget: 96` + thinking off | 200 · reasoning **0** | — | — |
| `top_k: -5` — the discriminator | **400** `top_k must be 0 (disable), or at least 1, got -5`, wrapped `OpenAIException` | **400**, the same engine text | **400** (engine directly) |
| `totally_bogus_param_zz: 123` | 200 (tolerated — not this path) | — | — |

**Verdict: the gateway IS thinking-controllable on the pin.** Every through-gateway number equals its direct-engine
control, and the `top_k` probe fails identically at both hops, so neither proxy drops nor rewrites these fields. The
live measurement **settles the §9c question in its favour**: the silent-thinking-ON regression is not real on
this pair, which is what the §9c row states.

**The method, because a 200 proves nothing here** (the failure mode is silent thinking ON at HTTP 200): two
discriminating shapes, each with its own bare-request control in the same run. (a) the **token-count signature** —
`reasoning_tokens` 320 → 0 *and* `prompt_tokens` 98 → 58, the thinking block vanishing from the rendered template is
something a proxy cannot fake by ignoring a field; (b) the **out-of-range value** — `top_k: -5` produces a 400 whose
message is vLLM's own validator, which can only appear if the field travelled end to end. A probe that would print
the same numbers without the switch is not evidence (CONVENTIONS §6).

**The proxy's own dropped-params log is not available evidence at the shipped log level.**
`docker logs lan-litellm` prints only the propagated 400; under `drop_params: true` with default
verbosity LiteLLM logs no drop line. ⛔ Do not raise the proxy log level to chase it: that logs token-bearing
request bodies. Use (a)+(b).

**What does not change:** decision #26 stands — generation harnesses still go **direct** to the engine, the gateway
serves the simple-querier tier, and nothing here moves the harness route. pi's
`compat.thinkingFormat: "qwen-chat-template"` control is proven at **both** hops
([pi-harness.md](pi-harness.md) §2 carries the harness-side numbers: 82 capped vs 121 uncapped on *its* prompt — the
absolute counts are prompt-dependent, the 0 / capped / uncapped relation is what generalises). `reasoning_effort`
is **not** tested through the gateway and stays unsupported there.

---

## 10. Open work (what is genuinely pending)

| Item | State |
|------|-------|
| **Coding-plane memory plane** | **Measured, undecided.** The `agentmemory` probe answered OQ-12/13/14 in one line each (§9b note + [`../reports/probe-agentmemory-20260921.md`](../reports/probe-agentmemory-20260921.md)); the owner call is open and nothing is installed. ⛔ Do not build a central instance before it: the shape the question assumed (LAN bind + per-client tokens + per-user isolation) does not exist in 0.9.29. |
| **Scoped-consumer tier** | Not shipped. `rpm` has a code path — a decided cap must never mint an uncapped key and look green. The first LAN record (`home-assistant`) is authored **and minted**. Held: the OWUI grant (the glue is create-only — see §4), Docling's key (its consumer does not exist yet), and the `llm`-router client credential that ends `spark-llm_api`'s triple use. |
| **`rag-mcp` + `forgejo-mcp` implementation** | Stub compose (no `services:` block). The rerank leg ships dormant until this exists. |
| **Qdrant cutover + OKF wiki tails** | Qdrant cutover verification + OKF wiki repos + first-ingest dimension check (1024). |
| **Open WebUI instance split** | One instance today; the public/internal capability split is undecided work. |
| **Docling prose-page recall** | On light prose the live RapidOCR engine drops whole sentences — a recall gap (§Docling OCR engine selection). One measured cheap candidate: raster scale, the 288 dpi render cut scan2's fragment-soup lines **5 → 2** at the same 2.9 s. |
| **Mem0 / OpenHands** | Planned spark services; neither onboarded. |
