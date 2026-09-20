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
> It is the single merged view of the architecture that HD-267 locked: Qdrant instead of PGVector ·
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
>   two-instance split is **open work (HD-248)**, not current state.
> - **`rag-mcp` and `forgejo-mcp` are stubs** (`enabled: false`, and `rag-mcp`'s compose file has no
>   `services:` block, so flipping the flag fails `docker compose config`). The rerank leg therefore
>   **ships dormant**: the container answers, the consumer does not exist (**HD-268b**).
> - **No scoped consumer reaches the pinned-AI rows or `spark/*`.** Both instances' `litellm_scoped_keys`
>   still name `ollama/*` model names that no longer exist, and `spark/*` is in no allow-list. Everything
>   measured so far ran on the admin-grade master key (**HD-384**).
>
> ⏳ **Open:** HD-384 (scoped-consumer allow-lists), HD-383 (parked stale `dsh_api` secret), HD-248 (the
> OWUI instance split), HD-268b (implement `rag-mcp`), HD-267 tails (Qdrant cutover verification, OKF wiki
> repos), HD-387 (re-measure the thinking parameter through a gateway), HD-402 (Docling OCR engine swap).
> Tracked in [`../todo.md`](../todo.md) (`source: services-ai`).

---

## 1. Philosophy

One **LiteLLM endpoint** is the spine for everything that must not hold an upstream credential. Every such
consumer (Open WebUI, OpenClaw, Docling, HomeAssistant, Qdrant's embed/rerank) talks to it and **never sees
an upstream provider key**. All external **generation** uses one `openrouter_api` key; **embeddings, rerank
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
  (`enabled: false`, HD-386 — kept so `template_dir` + the port contract survive a re-onboarding). They run
  as dedicated deployments / on the workstation and reach the engine directly. The tailnet `dsh`/`pi-dev`
  DNS records + `dsh-backend`/`pi-backend` routes still exist and answer **502 by design**; removing them is
  an owner call (HD-386 tail).

### Docker networks

`open-webui` on `traefik-public` · OpenClaw + Docling + `lan-litellm` consumers on `services-internal` ·
**Qdrant on `db-internal`** (alongside the LiteLLM Postgres) · the **unauthenticated inference legs on
`llm-backend`** with **no published ports and no Traefik labels** · tailscale sidecars (Pattern A) for the
management plane. **No host `0.0.0.0` port binds** — overlays + Traefik for the public plane (Flaw C /
HD-62; Patterns A/B in [network-vpn.md](network-vpn.md)).

> **Unauthenticated-inference isolation (HD-59):** Whisper/llama.cpp/Ollama-style inference APIs have **no
> native server auth**, so they live on the dedicated `llm-backend` overlay reachable **only by LiteLLM**
> (the spine) — never on the flat `services-internal`. On that network the *network is the boundary*.

---

## 3. Components

| Service | Role | Network | Notes |
|---------|------|---------|-------|
| **LiteLLM (VPS)** | LLM gateway / router | `services-internal` + `llm-backend` + `tailnet-apps` | OpenAI-compatible spine (Postgres-backed, HD-247). The only component holding upstream keys. Admin UI is **tailnet-only** at `litellm.kogler.si` (edge → `http://litellm:4000` via Docker DNS — the `tailnet-apps` overlay is the bridge that makes that resolve; never join the key-holder to `traefik-public`). ⚠ `/ui/login` deep-link 404s (no SPA fallback in the image, upstream #29340) → **use `/fallback/login`**. |
| **LiteLLM (LAN)** | Dev/pinned-side gateway | oldsrv, `llm-backend` + traefik-internal | `lan-litellm` + `lan-litellm-db`, exposed as **`llitellm.kogler.si`** on the oldsrv `traefik-internal` HOME edge (`http://oldsrv_home_ip:4000` backend, TLS + HSTS). Own Postgres, Kopia-backed. `litellm_scoped_keys` is currently **empty** → `bootstrap_keys: false` (the glue fail-louds on an empty spec list); the first records back are the HD-384 allow-lists. |
| **Open WebUI** | chat + RAG UI | `traefik-public` | ONE instance today at `ai.kogler.si`, Authentik OIDC. The public/internal split + per-instance corpus is **HD-248**. |
| **Qdrant** | hybrid vector store | `db-internal` | Standalone Rust DB (dense + sparse BM25), **independent of OWUI's built-in RAG**, replaces PGVector. Dimension locks at first ingest — **1024**. Keep the snapshot seam (§5b). |
| **Forgejo (wiki repos)** | knowledge SSOT | `db-internal` / git | OKF `.md` repos per owner; git = truth; Qdrant = rebuildable cache. |
| **Docling** | OCR / document understanding | `services-internal` | **CPU on the VPS** (no GPU there). Model stack = layout detector + TableFormer + pluggable OCR; current engine **EasyOCR** (dedicated `sl` model → Slovenian scans, HD-103). ⚠ Its accelerator set is `auto\|cpu\|cuda\|mps\|xpu` — **no Vulkan/ROCm**, so Docling cannot use the RX 7600. ⏳ **HD-402:** proposed swap EasyOCR → **RapidOCR-ONNX** (`latin` rec group includes `sl`) for CPU speed — **benchmark before applying** (script-grouped model vs dedicated `sl` model is a quality risk on `č ć š ž`); free lever regardless: `do_ocr=False` for born-digital PDFs. |
| **OpenClaw** | AI agent / orchestration | `services-internal` | Version pinned. Models via a LiteLLM scoped key. |
| **kapa-inspired-rag-mcp** *(stub)* | MCP hybrid reader | `services-internal` | Intended flow: hybrid search in Qdrant → top-20 → rerank via LiteLLM `jina_ai/` → top-5 clean markdown. Not implemented (**HD-268b**) — see the status block. |
| **Forgejo MCP** *(planned)* | MCP read/write `.md` | `services-internal` | Bridge to the OKF wiki repos; agents read/write notes + open PRs. |
| **Ollama** | **embed fallback rung** | `llm-backend` | `ollama:0.32.15-rocm` serving `bge-m3` (1024-dim, E2E-verified, 833–899 MiB VRAM, ~500 ms/chunk). Demoted from primary by measurement (decision #27) but **kept as the documented fallback** of the same 1024-dim space. **Not** a rerank host and **not** an STT host (§9c). |
| **whisper / reranker / embed** | pinned-AI tier | `llm-backend` | oldsrv RX 7600 / Vulkan — §3a. |
| **Mem0** *(planned)* | Long-term memory for OWUI | `services-internal` | Backed by Qdrant; per-user/per-project scoping (§5c D). Onboarding tracked in HD-335. |
| **OpenHands** *(planned)* | Agentic coding harness | oldsrv / spark | A third coding cockpit; would be served by the LAN LiteLLM (scoped key) + a PR-only Forgejo token. |

### 3a. Pinned AI inference tier — plan of record (decision #27)

The one table for **what AI runs on oldsrv, on what device, with which model**. Every latency/VRAM figure is
**measured on this box** — provenance and repro commands in [services-ai-bench.md](services-ai-bench.md).

| Leg | Engine | Model (quant) | Device | VRAM (measured) | Latency (measured) | Status |
|-----|--------|---------------|--------|-----------------|--------------------|--------|
| **Embeddings** | `llama.cpp server-vulkan` (`--embedding --pooling cls --embd-normalize 2`) | `bge-m3` **Q8_0** (634.6 MB) | RX 7600 / Vulkan | **~326 MiB** | **15 ms**/chunk · 51-doc batch 0.86–1.40 s · **0.45 s deployed** | ✅ live (`embed`, :9002, gateway row `bge-m3-vk`, dim 1024, ‖v‖=1.0) · cos 0.9996 vs the Ollama vectors ⇒ **no re-embed penalty** |
| ↳ embed fallback rung | `ollama:0.32.15-rocm` (`/api/embed`) | `bge-m3` (fp16) | RX 7600 / ROCm | **833–899 MiB** | ~470–545 ms/chunk | ✅ live — **kept** as the fallback rung of the SAME 1024-dim space; it is a **service + model, not a catalog row** |
| **Reranker** | `llama.cpp server-vulkan` (`--embedding --pooling rank --rerank`), routed as LiteLLM **`jina_ai/`** | `bge-reranker-v2-m3` **Q8_0** (635.7 MB) | RX 7600 / Vulkan | **~327 MiB** | **0.34–0.50 s** / 20 docs · **0.95 s** solo deployed · 1.15 s under three-way load | ✅ live (`reranker`, :9001, row `local-rerank`, ranking verified) · **ships DORMANT** (consumer = HD-268b) |
| **STT (voice)** | `whisper.cpp:main-vulkan` (`--inference-path /v1/audio/transcriptions`) | `large-v3-turbo` **fp16** (q5_0 = −1.0 GiB option) | RX 7600 / Vulkan | **1788 MiB** (Δ1722) · q5_0 **786** | **0.40 s** per 11 s WAV · **0.53–0.60 s** on real Slovenian radio speech | ✅ live (`whisper`, :9000, row `local-stt`) · CPU fallback native at init: 17.5 s |
| **Gateway** | `lan-litellm` + own Postgres | — | CPU | — | — | ✅ live; the three pinned rows are in its DB and each answered **through** the gateway (§4a) |
| **immich-ML** | immich's bundled ROCm | CLIP / face / doc | RX 7600 / ROCm | 0 idle · **3–5 GB** during a job | job-bound | ✅ live · **lowest priority**, pause-able (Sunshine glue) |
| **Sunshine** | VCE/AMF encode | — | RX 7600 | not a KFD compute consumer | — | ✅ live · gaming-first |
| **Piper TTS** | piper | — | **CPU in HA on the Pi** | — | instant | ✅ live |
| **Generation** | spark vLLM behind `llm.kogler.si` | `qwen3.8-flash-next`, 262k ctx | not on oldsrv | — | ~11 tok/s decode | ✅ live · harnesses reach it **directly** (#26) |
| **RAG reader** | `rag-mcp` · Qdrant · Docling | — | VPS | — | — | ⚠ stub — see status block (**HD-268b**) |

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
`llm-backend` (`external: true`) with **no `ports:` and no Traefik labels** (HD-59: the network *is* the
boundary and only `lan-litellm` may speak to them).

| Service | Image pin (`group_vars/all/versions.yml`) | Listen | Weights (`:ro`) | Model sha256 | Mem cap |
|---|---|---|---|---|---|
| `whisper` | `whisper_cpp_vulkan_image` (`main-vulkan@sha256:cf102ac3…`) | `:9000` (`ai_tier_whisper_port`) | `/srv/models/whisper/ggml-large-v3-turbo.bin` (1 624 555 275 B) | `1fc70f77…2bc69` | `4g` |
| `reranker` | `llama_cpp_vulkan_image` (`server-vulkan@sha256:7158edb4…`) | `:9001` | `/srv/models/reranker/bge-reranker-v2-m3-Q8_0.gguf` (635 676 416 B) | `a43c7c9b…a1d3` | `1g` |
| `embed` | same llama.cpp digest as reranker | `:9002` | `/srv/models/embed/bge-m3-q8_0.gguf` (634 553 760 B) | `aa473d51…a173` | `1g` |

**Context and batch sizing (measured, not guessed):** both GGUF legs run
`--ctx-size 2048 / --batch-size 2048 / --ubatch-size 2048`
(`ai_tier_gguf_ctx_size` / `ai_tier_gguf_batch_size` / `ai_tier_gguf_ubatch_size`).
Reason: llama.cpp **truncates silently** beyond the window on the generation path and `llama-server`'s own
default is 512 — which would slice the documented ingest chunk (§5b: token-based **512/64**) in half. 2048 =
that spec with 4× headroom (bge-m3 supports 8192; paying KV memory for chunks that do not exist buys
nothing). **`--ubatch-size` is the binding limit, not `--ctx-size`** — finding 1 below. Re-derive when
HD-268b goes live and a real chunk size is measurable.

**Model fetch is generic, not bespoke:** `roles/docker_services/tasks/deploy-service.yml` has an opt-in
`svc.model_url` / `model_dir` / `model_file` / `model_sha256` hook (the same opt-in-registry-key pattern as
`bind_owner_uid` / `db_role_sync`). `get_url` + `checksum` is idempotent **by content**: a present file with
the right digest is a no-op; a digest mismatch **fails the converge** rather than booting an engine on half a
model. There is no `default()` on the digest — `model_url` without `model_sha256` aborts the render (HD-65
fail-loud). Weights are public artifacts: never in git, never in the vault, and (like `ollama`/`spark-ai`)
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
   allow-list are still **HD-384 / HD-268b**. Nothing a family member runs changed behaviour.
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

- **Through the gateway:** Open WebUI, OpenClaw, Docling, HomeAssistant and Qdrant's embed/rerank
  authenticate to **LiteLLM only**, via per-consumer **scoped virtual keys** (HD-247) — they never hold
  `openrouter_api` or the master key.
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
  instance. Embeddings stay **1024-dim `bge-m3`** — the tier moved engines without changing the vector
  space (cos 0.9996), so no corpus migration.
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
| `litellm_api` | api → `credential` | admin/bootstrap ONLY — **this IS the master key** (`LITELLM_MASTER_KEY`); there is no `litellm_master_key` item, despite how the name gets typed (HD-247) |
| `litellm_db` | db → `password` | litellm-db runtime DB (models-in-DB) |
| scoped keys (`owui-public-chat_api`, `owui-public-rag_api`, `owui-int-wife_api`, `owui-int-owner_api`, `dsh_api`, `openclaw-litellm_api`, `rag-int-svc_api`) | api → `credential` | per-consumer minted keys (HD-247) |
| `spark-llm_api` | api → `credential` | the spark engine's bearer (container env, never a DB row) |
| `openwebui_secret` | password → `password` | Open WebUI session/encryption secret |
| `qdrant_db` | api → `credential` | Qdrant (no username; single static API key via `QDRANT__SERVICE__API_KEY`) |

> Fail-closed secrets: no `default('')` — a missing item fails the render loudly (HD-65/76).

**Scoped consumer keys (HD-247):** Postgres-backed; models are Admin-UI-managed; bootstrap glue mints the
per-consumer virtual keys (lookups are fail-closed thereafter). Specs SSOT in `group_vars/vps.yml`:
`owui-public-chat` · `owui-public-rag` · `owui-int-wife` / `owui-int-owner` · `openclaw-litellm` ·
`rag-int-svc`; starting budgets/durations are Admin-UI-editable.
**The LAN instance has no scoped consumers at all** (`litellm_scoped_keys: []` in
`group_vars/home_servers.yml`) — its dsh/pi-harness consumers were removed with the harnesses, so every
call on that side runs on the master key. That is also why the pinned-AI legs have no per-consumer
budgets yet: HD-384 has to create consumers on the LAN instance, not only widen VPS allow-lists.
⚠ The allow-lists still name `ollama/*` model names that no longer exist after decision #27 — correcting
them (and adding `spark/*` + the pinned rows for the real consumers) is **HD-384**, and the model-catalog
doctrine below governs how.

> 📋 Deploy checklist: [`deployment-ai-stack-secrets.md`](deployment-ai-stack-secrets.md).

### 4a. Model catalog rows — runbook (runtime DB)

Model rows live in the LiteLLM **DB**, never in git (decision #13 / HD-247). Create them with
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
- **Admin endpoints (v1.83.10, measured):** `/model/list` is **not** usable with the master key (it answers
  `{"detail": …}`) — **`/model/info`** is the one that enumerates rows; and **`/model/delete` takes
  `{"id": …}`**, not `{"model_id": …}` (the latter is a 422 that says which field it wanted — do not assume).
- **The Ollama fallback is a rung, not a row.** The Vulkan embed leg has its own row; Ollama stays as the
  documented fallback of the SAME 1024-dim space. **Neither LiteLLM DB contains an `ollama/*` row**, so
  "keeping" it means keeping the service + the model (`bge-m3` re-verified at dim 1024 after the blob
  cleanup). Re-pointing a consumer to either leg is HD-384 work.
- **`bootstrap_keys` stays `false` on the LAN instance** (HD-386): none of these legs has a scoped consumer
  yet, and the glue fail-louds on an empty spec list.
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
| Reranker | bge-reranker-v2-m3 **Q8_0** local via LiteLLM `/rerank` → `jina_ai/` → llama.cpp Vulkan cross-encoder on the RX 7600. ⚠ its consumer `rag-mcp` is the HD-268b stub → the leg ships dormant |
| Hybrid | ON by default (dense + sparse BM25) |
| Retrieval | 20 candidates → rerank → top 5, threshold 0 |
| Chunking | token-based 512/64 (`RAG_TEXT_SPLITTER=token` mandatory) — **the number the GGUF legs size ctx/batch from**: an oversized chunk fails ingest loudly (§3a-3 finding 1) |
| Config ownership | `ENABLE_PERSISTENT_CONFIG=false` (env = SSOT) |
| Knowledge split | Public = Family-Manuals KB only; internal = personal / wife-work corpus |
| Vector index | Qdrant, **1024-dim** dense (+sparse) |

> **Dimension lock-in (HD-267/246):** the vector dimension **freezes at first ingest**; changing embedding
> model or dimensions later = full re-ingest + backtest. The dim is **1024** (bge-m3). Verify it before the
> first real ingest — nothing has been RAG'd yet, so the choice is still free.

> **Backup posture (HD-307):** Qdrant is a **rebuildable cache**, so its backup policy is *relaxed* — the
> irrecoverable source is the **Forgejo OKF wiki** + the raw-asset ingress. Still keep a Qdrant snapshot seam
> for iteration speed, but it is not the metadata-fate risk class PGVector was. Open WebUI + OpenClaw
> config/state → Kopia.

> **Qdrant `read_only` snapshot gotcha (HD-271-followup):** the compose sets `read_only: true` (container
> hardening, HD-202), so Qdrant **cannot create its snapshots dir in the RO rootfs at startup** → panic
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
corpus, not a monolith. (Mechanism detail is an HD-307 follow-up.)

**D) Mem0 long-term memory (planned):** user-scoped memory for OWUI backed by Qdrant, with
`user_id = f"{owui_user_id}-{model_id}"` so each (user, project) pair gets its own memory namespace — no
cross-user leakage. Store = a Qdrant collection, rebuildable like the RAG index.

**Elastic survival:** because knowledge is plain OKF `.md` in git and the index is a rebuildable cache, if
Open WebUI disappeared the whole structure, hybrid RAG and the coding agents keep working from a terminal.

---

## 6. Auth & exposure

- **`ai.kogler.si`** is the Open WebUI instance today, **public** behind **Authentik OIDC** (per-person SSO)
  + the `crowdsec-only` middleware at the Traefik edge (internet-facing → Flaw A / HD-60). It must hold only
  capability-limited credentials (family-chat + embed keys, no agent keys).
- **`chat.kogler.si`** is **element-web** (Matrix), not an AI UI.
- The **internal, agent-capable OWUI instance is HD-248 work**, not current state.
- **Capability-tiering posture:** internet-facing = limited capability only; full power behind the tailnet;
  new admin/UI surfaces default tailscale-first ([security.md](security.md) §Capability-tiering,
  [network-vpn.md](network-vpn.md) Patterns A/B).
- Per-person history follows the HD-51 identity model; no shared admin login.

## 7. Integrations

| Integration | How |
|-------------|-----|
| **Open WebUI ↔ OpenClaw** | Register OpenClaw as a LiteLLM model/provider → chatting to the "OpenClaw" model invokes the agent. No bespoke glue. Agent-capable keys stay off the public instance (HD-248). |
| **Harness ↔ engine / Forgejo** | Per decision #26 the harnesses consume the engine **directly** (no LiteLLM hop) and propose via **Forgejo PRs only** (branch-protected main, no merge rights). Their scoped LiteLLM keys are parked (HD-386). |
| **Qdrant ↔ rag-mcp ↔ OWUI** | Retrieval via Qdrant + rerank through LiteLLM `jina_ai/`, returning top-5 markdown. Author-side contract only — `rag-mcp` is the HD-268b stub, so there is no live caller. |
| **Forgejo MCP ↔ wiki** | Agents read/write OKF `.md` and open PRs; never arbitrary filesystem access. |
| **OpenCloud ↔ RAG ingress** | Raw assets (read-only WebDAV) → Docling → wiki (git floor). |
| **OpenClaw ↔ OpenCloud** | WebDAV skill reads/writes family files (summarize, organize, OCR a scan via Docling, draft replies). |
| **Open WebUI ↔ MS Office** | Office MCP bridges (Windows 11 clients) surface Word/Excel/PowerPoint as tools over the tailnet; server-side python-docx/pptx/openpyxl for Linux. See [`services-office.md`](services-office.md). |

## 8. Security & operating notes

- **No host port binds** (Flaw C / HD-62): overlays + Traefik only; loopback-only if ever needed.
- **Version pinning** (HD-61/71): pin LiteLLM, Open WebUI, Docling, Qdrant, OpenClaw (young project) and
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
  What **HD-384** owes is *scoping* (one key per consumer, per-key routing and limits) — not authentication.
- **Secret hygiene rule (learned from a real slip):** a value read via `op read` is **never printed**, not
  even truncated to prove the read worked — print its **length** and pipe it straight into the consumer.
  A diagnostic probe leaked a partial master-key fragment into a terminal transcript. **Owner decision: the
  key is NOT rotated** (same class as HD-233/234, whose procedure carries any future rotation — both
  instances plus every consumer move together). Recorded closed so it is not re-raised.

---

## 9. Decision log (load-bearing rules)

Superseded/rejected options live in [services-rejected.md](services-rejected.md). Numbers are the repo's
citation anchors; the wording below is the rule **as it stands**.

| # | Rule |
|---|------|
| 13 | LiteLLM is the spine: **models live in the DB, config in env**, per-consumer scoped virtual keys. |
| 22 | spark (ThinkStation PGX / GB10) replaces the old Phase-2 Ryzen/R9700 build; Mem0 + OpenHands are spark candidates (HD-335). |
| 24 | **Placement:** oldsrv RX 7600 = the **pinned-services tier** (STT + embed + rerank, small + latency-sensitive); **spark = the big-model generation tier** (one large model, largest context). Piper TTS stays CPU. immich-ML stays on the oldsrv GPU as **lowest priority**. |
| 26 | **Consumption boundary:** generation harnesses go **DIRECT** to the spark name edge; LiteLLM serves the **simple-querier tier**; external APIs are a **harness-side fallback, never a proxy fallback**. Evidence: §9d. Consequences: `dsh`/`pi-dev` parked as services (HD-386); LAN `litellm_scoped_keys` empty until HD-384; hardening `spark-llm_api` belongs at the **edge** (router allow-list / a distinct client credential), not at a proxy. |
| 27 | **Pinned tier engine family = ggml/Vulkan** (§3a): STT `whisper.cpp:main-vulkan`, embed + rerank `llama.cpp:server-vulkan`, **Q8_0** quantization on both GGUF legs, Ollama demoted to the embed **fallback rung**. Kept #24's placement. |
| 28 | **Vision:** the workstation runs vision as a **text cascade**; **spark is text-only**; the RX 7600 gets **no vision-LLM leg**. Detail: [hardware-workstation.md](hardware-workstation.md), [hardware-spark.md](hardware-spark.md) §Text-only engine mode. |

### 9b. Coding plane — agent memory + runners

The **coding plane** (IaC/Ansible, C#, React/Vue, homelab epics) is a **separate plane** from the family
research plane (OWUI/Docling/Qdrant/Mem0). It runs on **oldsrv**, managed from the laptop.

- **Memory = agent-memory.dev, per project.** One instance per project (project = 1+ repos), records tagged
  project+repo; **cross-project recall is opt-in, not default**. Data under `~/.agentmemory/<project>`,
  ports 3111+N, MCP = `@agentmemory/mcp`, consolidation LLM via a LiteLLM scoped key. OpenViking is deferred
  (AGPL-accepted, Docker-only, future unified-context candidate); Mem0 stays in the OWUI plane.
- **Skills = git SSOT** (`skills/` + `sync-skills.sh`), never a service.
- **ZeroClaw = system-management agent** — laptop primary + oldsrv standby. **Never the VPS** (fleet
  credentials on an internet-facing host is the largest attack-surface increase available). Supervised
  approvals; MCP → agentmemory.
- **CrewAI** = long/epic homelab coding orchestration with mandatory human stop-points. Pilot starts only
  when the homelab is finished; kill criterion = a 2-week vertical slice or abandon.

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
| **`jina_ai/` rerank accepts a custom `api_base` and rewrites the path.** | `litellm/llms/jina_ai/rerank/transformation.py` in the pinned image: `get_complete_url` replaces any path with `/v1/rerank`. | A llama.cpp `/v1/rerank` endpoint is routable through LiteLLM with **no path in `api_base`** — this closed the "how do we route a local reranker" question. |
| **`openai/` chat provider param allow-list is narrow.** | `OpenAIGPTConfig.get_supported_openai_params` carries `temperature`, `top_p`, `max_tokens`, `stream_options`, `tools`, … and **not** `top_k`, `chat_template_kwargs`, `thinking_token_budget`; an **unknown** model alias (`OpenAIUnknownModelConfig`) gets that list **+ `reasoning_effort` only**. Repo-wide: `chat_template_kwargs` is handled by `hosted_vllm`/`together`/`fireworks`, `thinking_token_budget` by Bedrock only. | Under `drop_params: true` an unsupported key is **dropped silently**; for the thinking switch the silent outcome is thinking **ON** — a cost/latency regression that returns HTTP 200. (⚠ open contradiction to re-measure: a live run observed `reasoning_tokens: 0` through the gateway. The grep is from `main`, not the pinned image ⇒ **HD-387**; until measured on the pin, do not treat "thinking control works through the gateway" as true, and never let a harness depend on it.) |
| **ONNX Runtime ROCm / MIGraphX support is Instinct-only** (`gfx942`, `gfx950`). | AMD docs. | There is **no ONNX-GPU on RDNA3** — "CPU fallback if ONNX-GPU proves fragile" is a dead branch on this card. |
| **Per-runtime host RAM is the oldsrv constraint, not VRAM.** | Each ROCm/PyTorch process holds its own rocBLAS/hipBLASLt/MIOpen workspace (~0.5–1.5 GB RSS); a C++ ggml binary sits at ~150–350 MiB. | On a 48 GB host the binding constraint is **host RAM**, which is an argument for one backend family across the tier. |

---

## 10. Open work (what is genuinely pending)

| Item | State |
|------|-------|
| **HD-384** scoped-consumer allow-lists | Not started. The simple-querier tier (HA, Docling, OWUI) needs rows for `spark/*` + the pinned legs, and the existing `ollama/*` allow-lists name models that no longer exist. Until it lands, only the admin-grade master key is in play. |
| **HD-268b** implement `rag-mcp` (+ `forgejo-mcp`) | Stub compose (no `services:` block). The rerank leg ships dormant until this exists. |
| **HD-267 tails** | Qdrant cutover verification + OKF wiki repos + first-ingest dimension check (1024). |
| **HD-248** Open WebUI instance split | One instance today; the public/internal capability split is undecided work. |
| **HD-383** parked stale `dsh_api` secret | Parked with its consumer; remediation recorded there. Every `lan-litellm` converge aborts `rc2` until a record is restored or the item is cleared deliberately. |
| **HD-387** thinking-parameter re-measure | Open (see §9c). |
| **HD-402** Docling OCR engine | Proposed EasyOCR → RapidOCR-ONNX; benchmark-gated. |
| **Mem0 / OpenHands** | Planned spark services; neither onboarded. |
