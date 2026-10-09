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
> ⏳ **Open:** HD-384 (scoped-consumer allow-lists), HD-248 (the
> OWUI instance split), HD-268b (implement `rag-mcp`), HD-267 tails (Qdrant cutover verification, OKF wiki
> repos), HD-387 (re-measure the thinking parameter through a gateway), HD-472 (RapidOCR prose-page recall gate).
> Closed since this line was written: HD-471 (empty markdown on real scans — the `noexec /tmp` layout-stage kill,
> fixed 2026-10-07 by the `/cache` bind, see §Operational facts) and HD-103 (its live conversion gate).
> Tracked in [`../todo.md`](../todo.md) (`source: services-ai`).

---

## 1. Philosophy

One **LiteLLM endpoint** is the spine for everything that must not hold an upstream credential. Every such
consumer talks to it and **never sees an upstream provider key**. Wired today: Open WebUI, OpenClaw, Qdrant's
embed/rerank path. **Not wired yet:** Home Assistant (no consumer, no key, no env) and Docling as a scoped
consumer — both are HD-384 work, so the list below is the contract, not the current roster. All external **generation** uses one `openrouter_api` key; **embeddings, rerank
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
  DNS records + `dsh-backend`/`pi-backend` routes still exist and answer **502 by design** — decided and
  documented in [network-vpn.md](network-vpn.md); deleting them is a separate change with its own reasoning.

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
| **LiteLLM (LAN)** | Dev/pinned-side gateway | oldsrv, `llm-backend` + traefik-internal | `lan-litellm` + `lan-litellm-db`, exposed as **`llitellm.kogler.si`** on the oldsrv `traefik-internal` HOME edge (`http://oldsrv_home_ip:4000` backend, TLS + HSTS). Own Postgres, Kopia-backed. `bootstrap_keys: true` **since 2026-09-27** — one consumer minted (`home-assistant`), so the glue's fail-loud gate on an EMPTY spec list must never be re-triggered by emptying `litellm_scoped_keys`; the rest of the HD-384 allow-lists are pending. |
| **Open WebUI** | chat + RAG UI | `traefik-public` | ONE instance today at `ai.kogler.si`, Authentik OIDC. The public/internal split + per-instance corpus is **HD-248**. |
| **Qdrant** | hybrid vector store | `db-internal` | Standalone Rust DB (dense + sparse BM25), **independent of OWUI's built-in RAG**, replaces PGVector. Dimension locks at first ingest — **1024**. Keep the snapshot seam (§5b). |
| **Forgejo (wiki repos)** | knowledge SSOT | `db-internal` / git | OKF `.md` repos per owner; git = truth; Qdrant = rebuildable cache. |
| **Docling** | OCR / document understanding | `services-internal` | **CPU on the VPS** (no GPU there). Model stack = layout detector + TableFormer + pluggable OCR; live engine **RapidOCR / onnxruntime (PP-OCRv6 small)** — measured 2026-09-28 from the served log; `easyocr 1.7.2` is installed but never reached, because `OcrAutoModel` prefers rapidocr+onnxruntime (§Docling OCR engine selection). Slovenian is covered: `sl` is a first-class PP-OCRv6 code and the multilingual `rec_small` is baked. ⚠ Its accelerator set is `auto\|cpu\|cuda\|mps\|xpu` — **no Vulkan/ROCm**, so Docling cannot use the RX 7600. ⛔ **On light prose the live engine drops whole sentences (**HD-472**).** The old ⛔ "cannot convert a real scan" is closed: the `noexec /tmp` layout-stage kill was fixed 2026-10-07 (HD-471, `/cache` bind) and a 300 dpi image-only Slovenian scan now returns `status: success` with real markdown — §Operational facts measured on the way. Free lever regardless: `do_ocr=false` per request, but **only for born-digital PDFs** (a scanner's own text layer carries no diacritics). |
| **OpenClaw** | AI agent / orchestration | `services-internal` | Version pinned. Models via a LiteLLM scoped key. |
| **kapa-inspired-rag-mcp** *(stub)* | MCP hybrid reader | `services-internal` | Intended flow: hybrid search in Qdrant → top-20 → rerank via LiteLLM `jina_ai/` → top-5 clean markdown. Not implemented (**HD-268b**) — see the status block. |
| **Forgejo MCP** *(planned)* | MCP read/write `.md` | `services-internal` | Bridge to the OKF wiki repos; agents read/write notes + open PRs. |
| **Ollama** | **embed fallback rung** | `llm-backend` | `ollama:0.32.15-rocm` serving (live; pin is `0.35.1-rocm` since 2026-10-08 ⏳ — the container moves at the oldsrv converge) `bge-m3` (1024-dim, E2E-verified, 833–899 MiB VRAM, ~500 ms/chunk). Demoted from primary by measurement (decision #27) but **kept as the documented fallback** of the same 1024-dim space. **Not** a rerank host and **not** an STT host (§9c). |
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
| `reranker` | `llama_cpp_vulkan_image` (`server-vulkan@sha256:7158edb4…`) | `:9001` | `/srv/models/reranker/bge-reranker-v2-m3-Q8_0.gguf` (635 676 416 B) | `a43c7c9b…a1d3` | `4g` |
| `embed` | same llama.cpp digest as reranker | `:9002` | `/srv/models/embed/bge-m3-q8_0.gguf` (634 553 760 B) | `aa473d51…a173` | `4g` |

**Why both GGUF caps moved `1g` → `4g` (HD-393, 2026-09-28).** The doctrine two paragraphs above says
*measured peak, then headroom*; these two values came from `host RSS 157 MiB + 606 MiB weights`, which is
a reload-time reading. What the cap actually has to cover is the binary's **CPU-fallback path — 1.59 GiB
RSS**, a number this file already carries on the whisper leg (which is why whisper had 4g and the two GGUF
legs did not). A leg that falls back to CPU under a 1g cap is killed by its own limit, and the kernel
reports that kill as GPU trouble: `amdgpu: init_user_pages: Failed to get user pages: -1`, **2,881 lines**
in `kern.log.2.gz` across three bursts (09-15 12:xx = 721, 09-18 16/18/19 = 1,728, 09-19 23:xx = 432), each
following `Memory cgroup out of memory: Killed process 517641 (text-embeddings) total-vm:13095828k`
(`CONSTRAINT_MEMCG`, 2.5 min after that scope started). Zero such lines since, in `kern.log.1` (09-20 →
09-27) or in the boot that follows the power cycle.

**What is deliberately NOT claimed:** the over-cap path was not reproduced. With the cap already at 4g, a
318 KB / 120-item batch (58.6 s, 2.6 MB of vectors, `http 200`) peaked the cgroup at **200 MiB** with
`memory.events` all zero (`oom_kill 0`). So this change removes a **documented** failure mode and aligns
the cap with the sibling leg's doctrine; it does not claim a reproduced one. The recurrence test is whether
that `init_user_pages` line ever comes back — and if it does, look at the cgroup first, not the card.

**And the method correction, because it cost a week of wrong belief:** the 2026-09-19 reading concluded
\*"one bounded ~1.8 h episode"* from `dmesg`, which had already **wrapped** and only still held the last
1.8 h of a five-day spread. A wrapped ring buffer makes a recurring symptom look bounded. Judge bounded-vs-
recurring from the rotated `/var/log/kern.log.*`, not from the live buffer.

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

- **Through the gateway (the rule):** any consumer that must not hold an upstream credential authenticates
  to **LiteLLM only**, via a per-consumer **scoped virtual key** (HD-247) — never `openrouter_api`, never the
  master key. Open WebUI, OpenClaw and Qdrant's embed/rerank path do this today; Docling and Home Assistant
  are covered by the rule but **not yet provisioned a key** (HD-384).
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
**The LAN instance now has ONE minted consumer.** The record (`home-assistant` → `home-assistant_api`, HD-384,
authored 2026-09-26) minted on 2026-09-27 when `bootstrap_keys` flipped to `true` on `lan-litellm`, and the
glue exited 0 on that service's deploy pass. Every other call on that side still runs on the master key, and
the pinned-AI legs still have no per-consumer caps — that is the rest of HD-384. ✅ And the record **is** consumable the moment it
mints: HA **2026.8** ships a stock `litellm` conversation integration (this repo pins `2026.9.4` since 2026-10-08; verified at the
release tag) that takes **any proxy URL + an optional virtual key** and lists its models from `/v1/models` — so
what the `home-assistant` row must satisfy is visibility of `spark/qwen3.8-flash-next` **to that key's
`/v1/models`**, the same endpoint the glue probes below
([smart-home-voice.md](smart-home-voice.md) §the LLM leg).
⚠ The allow-lists still name `ollama/*` model names that no longer exist after decision #27 — correcting
them (and adding the real rows for the real consumers) is **HD-384**, and the model-catalog doctrine
below governs how.
⚠ **The glue is CREATE-ONLY, and that decides what "grant a consumer" means** (read off the template
2026-09-26): a vault item that already holds a value is only *probed* (`GET /v1/models`; 200 = keep,
401/403 = `ABORT rc2`) — its server-side params are never updated. So editing `models:` or budgets on an
existing record (e.g. handing the four live `owui-*` keys the `spark/qwen3.8-flash-next` row) changes
nothing about the live key. Granting an existing consumer another model needs `/key/update` (not
implemented — it is HD-384's remaining half) or a deliberate re-mint (clear the item, delete the alias,
which invalidates the running consumer). Never report an allow-list edit as a shipped grant.

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
  The KEY endpoints have the same shape trap (measured 2026-09-28 while retiring HD-383): **`/key/list`**
  is the only enumerator (it returns `{keys:[<token hash>…]}`, the aliases are NOT in it), **`/key/info`
  404s without `?key=`**, and **`/key/delete` wants `{"keys":[…]}` or `{"key_aliases":[…]}`** — a singular
  `key` is a 422. The DB tables are quoted-mixed-case (`"LiteLLM_APIKey"`) and only reachable through the
  container's own psql.
- **The Ollama fallback is a rung, not a row.** The Vulkan embed leg has its own row; Ollama stays as the
  documented fallback of the SAME 1024-dim space. **Neither LiteLLM DB contains an `ollama/*` row**, so
  "keeping" it means keeping the service + the model (`bge-m3` re-verified at dim 1024 after the blob
  cleanup). Re-pointing a consumer to either leg is HD-384 work.
- **`bootstrap_keys` is `true` on the LAN instance since 2026-09-27** (HD-386 → HD-384 → HD-403 step 2): the
  flip ran with the token leg HD-442 already fixed, the glue runs inside `lan-litellm`'s own deploy pass, and
  `home-assistant_api` mints from the converge (`rpm: 30`, ROW-only grant, no wildcard). Two things the flip
  settled: an empty spec list is the ONLY thing the fail-loud gate protects (the record must never be emptied
  while the flag is on), and **the ordering contract in `home_servers.yml` is live now, not inert** — a
  `bootstrap_keys` service must precede its consumers in the list because the glue refreshes the vault dict
  they render from.
- **⚠ An orphan virtual key lives in the DB that minted it, not in the DB that fails.** The `dsh` alias
  (HD-383) was deleted from the **VPS** LiteLLM DB — `lan-litellm`'s own `/key/list` returned two keys and
  neither was `dsh`, while the VPS carried it. The row's own wording ("VPS-DB-era value") had the answer and
  the fix location was inferred from the *symptom's* host instead. Deleted behind an alias guard (`/key/info?key=`
  → exactly one `dsh`, `last_used=None`, `spend=0`, vault item confirmed absent first): **9 keys → 8**,
  re-listed. ⚠ Same class, deliberately untouched: alias `pi-harness` still stands on the VPS and
  `pi-harness_openai_api` **still holds a value** (a parked key of a parked consumer = HD-386's call, not an
  orphan), and `test-probe-a0b651` (2026-08-27, never used) is probe residue. `pi.dev laptop` (hand-created
  2026-09-17) is a **live consumer — do not delete it**. (All of the above is in §4a, where the measured
  endpoint shapes live.)
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

## Docling OCR engine selection (HD-402) — measured, bench closed 2026-09-28

Measured on the **live VPS service** (`quay.io/docling-project/docling-serve-cpu:v1.30.0`, container up
5 weeks at the time of the probe) against **two real Slovenian scans** — a UKC Ljubljana discharge
summary, page 1 = crisp form + diagnosis table, page 2 = small light-print prose. Chosen because the
row asked for a decision "one measurement away" and the 2026-09-21 probe could not get one (a synthetic
render is not a scan). Everything below is a probe, not inference.

### What the deployed engine actually is

| Question | Measured answer (2026-09-28) |
|---|---|
| Which OCR engine does the served pipeline use? | **RapidOCR / onnxruntime, PP-OCRv6 small.** Served log, on every conversion: `Auto OCR model selected rapidocr with onnxruntime.` + `[RapidOCR] Using …/RapidOcr/PP-OCRv6_{det,rec}_small.onnx` + `ch_ppocr_mobile_v2.0_cls_mobile.onnx`. `OcrAutoModel` on Linux resolves nemotron → **rapidocr+onnxruntime** → easyocr, and this image has rapidocr, so EasyOCR is never reached |
| Is `rapidocr` installed in the pinned image? | **Yes** — `rapidocr 3.9.2`, alongside `easyocr 1.7.2`, `onnxruntime 1.28.0`, `docling-slim 2.118.0`, `docling-serve 1.30.0`, `torch 2.13.0+cpu` (`pip list` + `GET /version`) |
| Was the 2026-09-21 entry in this section wrong? | **On three counts, kept visible so nobody re-litigates the old text:** (1) "`rapidocr` distribution absent" — it is installed; (2) "running engine = EasyOCR" — the runtime log has said rapidocr since 2026-08-23; (3) "pinned `docling-serve-cpu:2.118.0`" — the tag is **`v1.30.0`**, which is the IaC pin (`docling_version`), while **2.118.0 is the docling-slim library version** reported by `/version`. Mis-attribution, not pin drift |
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

→ **EasyOCR is 3.2 – 3.4× slower** than the engine already running. The old "35 % CPU saving" number
was an understatement for this workload.

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

**Decision (closes HD-402): keep RapidOCR. Do not switch to EasyOCR.** The row's own gate was "keep
RapidOCR only if quality ≥ EasyOCR" — measured, RapidOCR wins the crisp form/table page *including its
diacritics*, is 3.2× faster, and the swap direction was inverted anyway (the premise that production
ran EasyOCR is what the probe disproved). EasyOCR wins only the light/small-print prose page, where
RapidOCR drops whole clinical sentences — that is a **recall gap worth its own decision**, not a reason
to buy a 3.2× CPU bill plus a new class of diacritic/merge defects. The gap is tracked in
[todo.md](../todo.md) (HD-472), with one measured cheap candidate: re-running rapidocr on the 288 dpi
render cut scan2's fragment-soup lines from **5 → 2 at the same 2.9 s** (rapidocr resizes internally, so
the extra pixels cost nothing at this scale), i.e. raster scale is a per-request knob
(`images_scale`/page rasterization at the call site) worth testing before any engine or model change.

### Where the model weights actually live (corrected 2026-09-28 — supersedes the 2026-09-21 notes)

- The weights the served pipeline uses are **baked into the pinned image** at
  `/opt/app-root/src/.cache/docling/models` (871 MB, image build 2026-08-07), reached because
  `DOCLING_SERVE_ARTIFACTS_PATH` points there: `EasyOcr/{craft_mlt_25k, english_g2, latin_g2}.pth`,
  `RapidOcr/PP-OCRv6_{det,rec}_small.{onnx,pth}` + `ch_ppocr_mobile_v2.0_cls_mobile.onnx` +
  `ppocrv6_dict.txt`, plus the layout/TableFormer/FigureClassifier model dirs.
- The `/srv/docker/docling/models → /models` bind is **empty, root-owned, and unused** (`HF_HOME=/models`).
  A `docling` CLI run in the container dies on `PermissionError: [Errno 13] … '/models/hub'`.
- **Corrected mechanism (this is what HD-421 now rests on):** chowning that bind does **not** make a
  model reachable. In production the artifacts directory itself is **read-only** (`read_only: true`
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

### Operational facts measured on the way (each is a row, not a footnote)

- **Production converted a real scan to *nothing* — FIXED + LIVE 2026-10-07 (HD-471).** `POST /v1/convert/file` on the live service returned
  **HTTP 200 with `status: failure`, empty markdown**, and the layout stage error:
  `OSError: /tmp/torchinductor_default/….main.so: failed to map segment from shared object … /tmp is
  mounted with noexec`. Cause: the compose ran `read_only: true` + `tmpfs: /tmp`, and Docker mounts
  tmpfs `noexec` (verified: `tmpfs on /tmp … noexec`), which torch inductor needs for its compiled
  kernels. Canary (a test that could have failed): the same image + same scan in a container with
  `--tmpfs /tmp:rw,exec` converted both pages fine.
  **Fix taken (the bind, not the exec-bit):** `TORCHINDUCTOR_CACHE_DIR` + `TORCH_EXTENSIONS_DIR` moved to
  `/cache`, a host bind pre-created 1001-owned by the role (`bind_owner_uid: "1001"`, `bind_dirs:
  ['models','cache']` in `group_vars/vps.yml`), so `/tmp` **keeps** its `noexec` tmpfs — the `/tmp:exec`
  alternative was rejected, it buys an OCR fix by making a `read_only` container's tmpfs writable+executable.
  The VPS root fs is `ext4 rw` with no `noexec`, which is what makes a bind dlopen-able at all.
  Live acceptance, 2026-10-07 (converge GREEN, `restarts=0`, `mem=6442450944`):
  `status: success`, **`md_content` 2021 chars / 317 words**, `layout_score 0.852`, `ocr_score 0.954`,
  `mean_grade excellent`, `errors: []`, and **zero** `failed to map segment` / `Stage … failed` lines in
  the container log since the recreate. The test asset is a **derived scan** — `docs/assets/manuals/
  comtrend-grg-4260-in-neo-smartbox_navodila-za-priklop.pdf` (Slovenian) rasterized at 300 dpi and
  re-wrapped as an image-only 2-page PDF (0 extractable characters, so OCR is the only path) — chosen over
  a family document deliberately: same pipeline, no family data leaves the box. **Provenance gap stated:
  nobody has re-run this on a real scanner/family photo since the fix.** Rebuild the same asset with:
  `gs -sDEVICE=pnggray -r300 -dFirstPage=1 -dLastPage=2 -o page-%d.png <manual>.pdf`, then an HTML page holding the
  two `<img>` at native pixel size with `page-break-after: always`, then `libreoffice --headless --convert-to pdf`
  — and **prove it is a scan** before trusting the run: `gs -sDEVICE=txtwrite -o - out.pdf | wc -c` must be 0.
- **Cold start beats the sync endpoint — re-measured on the fixed service (2026-10-07).** In a fresh container the *first* conversion took ~121 s and
  the request returned **504** (measured 3×); the second returned in 12 s. Today the pair is **94.1 s cold /
  11.2 s warm** (96 s / 14.0 s wall, same document, straight to the container's `services-internal` address, no
  proxy in the path) — so the cold leg is survivable *when nothing between caller and docling has a shorter
  timeout*. What is NOT measured is the consumer's own timeout: an Open WebUI/OpenClaw ingest with a <90 s client
  still eats a cold start after every recreate. Warm-up or the async endpoint belongs to the **caller**, and is
  worth one measured real ingest before anyone builds machinery for it.
- **Each distinct options set costs another converter, in RAM.** docling-serve caches a converter per
  options hash; a bench container capped at 7 GiB was **OOM-killed twice** while adding an EasyOCR
  converter on top of the preloaded auto+layout set (rapidocr path peak: 3.263 GiB sampled). The
  production container had **no memory limit** on a 15 GB host with ~3 GB available and **no swap** —
  so an engine change is also a memory-budget change, to be measured before it is proposed.
  ✅ **Closed 2026-10-07 (HD-471):** the compose now renders `deploy.resources.limits.memory =
  {{ docling_memory_limit }}` = **6 GiB** (`group_vars/vps.yml`, ~1.8× the measured 3.263 GiB peak and
  below the 7 GiB the bench arm died at), read back live as `HostConfig.Memory=6442450944`. The ceiling is
  a runaway guard, not a working-set reservation — with no swap on the VPS, an uncapped converter is the
  one shape that takes the host down with it.
- A bench needs a **throwaway container**, not production: production's `/models` bind cannot take a
  file, the container rootfs is read-only (`docker cp` → `container rootfs is marked read-only`), and
  calling the API from the host needs the container's `services-internal` address (no published port).
  From the VPS host: `IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
  docling)` then `curl -F "files=@scan.pdf" -F "do_ocr=true" http://$IP:5001/v1/convert/file` — the
  2026-09-21 "API rejected the multipart" note was a missing/renamed `files` field, the endpoint is fine.

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
| 28 | **Vision:** the workstation runs vision as a **text cascade**; **spark is text-only**; the RX 7600 gets **no vision-LLM leg**. Detail: [hardware-workstation.md](hardware-workstation.md), [hardware-spark.md](hardware-spark.md) §Text-only engine mode. **Measured on the workstation 2026-09-30 (HD-474/476); legs amended by the owner 2026-10-09:** the workstation serves **FIM + vision on one GPU**, one resident at a time — `vision-qwen3vl-30b` (images; 23.84 t/s decode, ~56–66 t/s image prefill, 4042–4060 tokens and **61–72 s** for one full-resolution photo; **3.0 GiB of KV at 32k** on its own, so nothing else is resident with it) and `fim-coder-3b` (8 192, the only leg small enough to share the carve). **The agent leg is retired, not deferred**, and the reason is prefill, not the carve: one 20 816-token prompt cost **359 / 899 / 277 s** on three fresh loads of the SAME weights, and the same 10 610 bytes cost **259.15 s** once and **69.42 s** another time — minutes per turn, erratic, so no real agent work is possible on that leg. `agent-gemma-26b` and the three declared `agent-unified*` arms are therefore out of [`../scripts/laptop-llm/profiles.yml`](../scripts/laptop-llm/profiles.yml), `client_context_window: 150016` is **deleted** (not reduced), and `providers.laptop-lmstudio` no longer offers an agent model. **The agent slot does NOT fall back to spark through this runtime** — #26 puts a generation harness **direct** on the spark name edge, so retiring this leg removes a surface, not a capability. `allow_uncertified: true` stays on the dial for the **FIM** leg (its trigger latency is still unmeasured, HD-401 gate 5), for no other reason. Rejected so it is not re-proposed: [services-ai-rejected.md](services-ai-rejected.md). The cascade rule is unchanged and now has a number on it: describe once, freeze the text, because eight full-res photos are a third of the vision window and ~9 minutes of prefill — and re-asking the **same** question costs 2.0 s while a **new** question re-pays the ~60 s, so put the image before the question. Gemma takes no images on this engine at all (a long side over ~1120 px kills the runtime), which is one more reason the box has no Gemma leg. **The vision leg transcribes only when the target fills the frame** — the whole 8160×6120 rack photo read the switch as `CRS326-24G-2S+RM` (five greedy passes) where [network-rack.md](network-rack.md) says `CRS328-24P-4S+`, but a quarter-crop of the same photo read `CRS328-24P-4S-RM` and the repo's own label photo came back character-perfect for **528 tokens in 3.9 s**. Image tokens saturate (~4.1 k whether the input is 8160×6120 or a 3264×3672 quarter), so **crop, do not shrink**: a crop costs the same and reads. Still verify an identifier against the inventory, and when a reading disagrees, re-ask of a crop before believing either answer ([reports/hd474-laptop-leg](../reports/hd474-laptop-leg/) `raw/96`). |

### 9b. Coding plane — agent memory + runners

The **coding plane** (IaC/Ansible, C#, React/Vue, homelab epics) is a **separate plane** from the family
research plane (OWUI/Docling/Qdrant/Mem0). It runs on **oldsrv**, managed from the laptop.

- **Memory = agent-memory.dev, per project (the wording of this rule is under an open owner call — see the
  2026-09-21 probe note below).** ⏸ **Deferred 2026-10-08 (owner): the blueprint stays parked** — nothing
  installed, no plane chosen, no row minted; the OQ-12/OQ-13 answers stand as recorded in [../todo.md](../todo.md)
  §1, OQ-14 stays unanswered, and no AI work waits on any of them (the durable negative also stands: LLM memory
  compression scored **R5 0/5** — it rewrites identifiers out of existence). One instance per project (project = 1+ repos), records tagged
  project+repo; **cross-project recall is opt-in, not default**. Data under `~/.agentmemory/<project>`,
  ports 3111+N, MCP = `@agentmemory/mcp`, consolidation LLM via a LiteLLM scoped key. **OpenViking is rejected
  outright** (2026-09-21, owner): both candidate roles are dead — the corpus index because its markdown index is
  lossy and not reversible (12/51 files byte-identical; files replaced by H1-title-slug directories), and the
  "memory only" fallback because its write path is LLM-bound per commit on a KV pool that is 1.97× one session,
  while this box measured its L0/L1 payload as worse than a free local extract. Evidence
  [`../reports/probe-ov-20260921.md`](../reports/probe-ov-20260921.md), decision rows
  [`services-ai-rejected.md`](services-ai-rejected.md). ⚠ The reason previously recorded here ("Docker-only")
  was **wrong** — OV installs venv-native in ~2 min; the rejection does not rest on it. Mem0 stays in the OWUI plane.
- **Memory plane — 2026-09-21 probe note: measured, NOT decided** (`agentmemory` 0.9.29, ephemeral on oldsrv
  under the `domen` seat; interpretation
  [`../reports/probe-agentmemory-20260921.md`](../reports/probe-agentmemory-20260921.md), raw evidence in the
  sibling directory of the same name). Owner rulings taken **before** the run (2026-09-21): **(a)** the wanted
  shape is **ONE central instance**, not one per project — that *relaxes* the per-project rule above **as a
  direction only**; the bullet above is **not** amended until the owner accepts a shape that is implementable
  today; **(b)** "the quadrant" in earlier discussion meant **[Qdrant](https://qdrant.tech/)** (the vector store
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
  * **Phantom ids to ignore:** both probe reports cite **HD-423 / HD-425 / HD-426** as registry rows. They never
    existed — no such row in any commit of [todo.md](../todo.md), no commit message naming them, and HD-421 was the
    next-free id while both lanes ran. The rules they gestured at are the bullets above plus the **HD-233/HD-234**
    rotation-and-readback precedent in [CONVENTIONS.md](../CONVENTIONS.md) §6. If a probe reuses those ids again,
    that is the drift to correct, not a row to re-create.
  * **"Central" is not buildable as briefed on 0.9.29** — REST binds `127.0.0.1` and the CLI **re-renders that
    config every boot**, so a LAN bind needs an **authenticating forwarder/proxy** (upstream **#523**); auth is
    **one shared bearer** (no per-client tokens); **`TEAM_MODE`/`TEAM_ID`/`USER_ID` never reach
    `mem::search`/`mem::observe`**, so per-user isolation does not exist in the retrieval path — tenancy would be
    a `project` tag, not enforcement. Two unauthenticated surfaces ride along: the **viewer answers 200 with the
    secret set**, and `iii` listens on **`0.0.0.0:49134`**.
  * **Leave LLM compression OFF** — `CONSOLIDATION_ENABLED` + `GRAPH_EXTRACTION_ENABLED` +
    `AGENTMEMORY_AUTO_COMPRESS` scored **R5 retrieval-key 0/5**: the narratives read well and dropped every
    identifier (`9002`, `0.34`, `515,786`, `#26`, `HD-268`). Same result as the OV lane's "LLM summary loses to a
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
    clears every gate; the leg is a measured +2). Tracked in [todo.md](../todo.md) §1.
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
  when the homelab is finished; kill criterion = a 2-week vertical slice or abandon. ✅ **Park reaffirmed
  2026-10-08 (owner): not now** — no pilot, no spike, no compose; re-open trigger is one real multi-agent epic
  that a single lane demonstrably mishandles (HD-491).

### 9b-1. Coding-seat surfaces on oldsrv — the placement decision (HD-409 pi-web, HD-411 Paseo)

> **Not the Cockpit console.** "Cockpit" in this section means the coding seat's web front-end
> (`pi-web`). The management console at `cockpit-<host>.kogler.si` is [cockpit-project.org](https://cockpit-project.org/),
> a different thing with its own owning role (`roles/cockpit`, routes in `services-traefik.md` §Cockpit Routes,
> break-glass identity in HD-361). Two docs used to call both a "cockpit", which is how a session came to
> report "the cockpit has no owning role" about the one component that plainly does — HD-445 is about `pi-web`.

The owner chose **native host processes under the unprivileged `domen` account**, not containers, and
**not** behind gateway auth. Recorded here because it is a deliberate exception to the shape every other
service in this fleet follows:

| Surface | Runtime | Bind | Auth | Why not the house style |
|---|---|---|---|---|
| **pi-web** (HD-409) | `~/.pi/agent/bin/pi-web` (28 MB Go binary, installed as a **pi package**: `pi install npm:@ygncode/pi-web@beta`), systemd **user** unit `pi-web.service` under `domen`, linger enabled, two drop-ins: `loopback-bind.conf` + `pi-on-path.conf` (the unit must be told where `pi` lives — it shells out to it) | **owner decision 2026-09-23: loopback only**, on `cockpit_pi_web_port`, published as **`https://pi-oldsrv.ts.kogler.si`** by oldsrv's OWN `websecure-ts` listener on `traefik-internal` (`network_mode: host` reaches the host loopback). No LAN socket, no `0.0.0.0`, no VPS edge, no WG S2S hop. It used to bind the `tailscale0` address — plain HTTP, no cert, and unreachable from every other node in the fleet (`no matching peer`) | `PI_WEB_TOKEN` from `~/.config/pi-web/env` (0600). `?token=` → 302; no token → **401**. A non-loopback bind without a token is refused by the binary unless `-insecure` | A container would mount the whole home tree of the session it watches; the point of the cockpit is to read `~/.pi/agent/sessions/`, so the container boundary would be theatre. `domen` is the blast radius, and it is the account that already owns the sessions |
| **Paseo** (HD-411) | ⏳ **not installed** (parked 2026-09-23 with a full resume sequence in the row) — planned as `@getpaseo/cli` under the same account | would use `paseo_port` (6767, upstream's default) on the same tailnet bind | its own `PASEO_PASSWORD` | Same reasoning — and the reason it stayed parked is that its acceptance needs a hand on the phone, so nothing I could verify end-to-end tonight |

**Deliberately NOT behind gateway-auth (decision).** The row allowed "a second host network + gateway-auth
route, if the existing gateway already carries it without contorting the gateway". Measured answer: it does
not, cleanly. `gateway-auth` authenticates **real client identity** — a phone-driven cockpit has no browser
that can complete an Authentik flow inside a sub-request, and the daemon-to-origin hop would need a machine
credential. So the gate is the **tailnet ACL** (headscale decides which node may reach `31415`) **plus** the
per-daemon token, and TLS-into-Traefik stays with the tailnet/TLS lane (old lane 414; tracked in [todo.md](../todo.md)).

**Ports are vars, never literals** (`cockpit_pi_web_port: 31415`, `paseo_port: 6767` in
`group_vars/all/main.yml`) — HD-344 moved MCP off a shared port precisely because a port written twice is
a port someone will change once. (This paragraph used to name `paseo_port: 31416`, which the SSOT explicitly
freed — HD-404 class.) Since 2026-09-23 `cockpit_pi_web_port` is no longer a reservation nobody reads: the
`traefik-tailnet` `pi-oldsrv-backend` consumes it, so a port edit is now one change instead of three. What
has NOT changed: **no role owns the unit files** (HD-445), which is why the unit + drop-in are hand-installed
and written out in the deployment manual rather than converged. `pi.kogler.si` was never available for this
seat's URL — that FQDN is the RPi4 node — hence the `-oldsrv` host suffix.

**Where the seat's repository lives (owner decision 2026-09-23):** oldsrv carries **two** clones with two
jobs — `/home/ansible-admin/source/homelab` **converges** (and `scripts/ansible-run.sh` now fast-forwards it
before every run, `--no-pull` to opt out) and `/home/domen/source/homelab` **is where dev work happens**, the
tree the seat actually edits. Neither path appears in this doc before today, which is how a session could say
"the coding plane runs on oldsrv" while the account the cockpit watches had **no repository at all**.

**Measured 2026-09-23, and what is NOT proven:** pi 0.87.1 + pi-web beta.36 run under `domen`; the model
contract and provider auth on that box are **rendered from the HD-388 spec** (`scripts/render-pi-config.py`),
so `pi --list-models` there is produced from git rather than copied by hand; the listener was confirmed on the
**derived `tailscale0` address, port 31415** and answers 401/302 as above. ⚠ That is the *pre-decision* state:
the loopback re-bind + `pi-oldsrv-ts` router are authored and validated but **not converged**, so until Phase 4c
runs the seat has no loopback socket and the new URL 404s by construction. **Unproven:** the tailnet path from a
real peer — and it stays unprovable from inside this fleet, because every node reachable from a session is itself
ACL-scoped away from oldsrv (the VPS `tailscale-sidecar` answers `tailscale ping <oldsrv>` with `no matching peer`,
which is the ACL working, not a fault). The phone is the first genuine client by design. Measured the same night: no `.git` anywhere under
`/home/domen` and `~/.pi/agent/sessions` is **empty** — the listener had nothing to drive. Two known costs of choosing beta software: `@ygncode/pi-web` ships **no
README in the npm registry** (the GitHub README is the only contract), and the binary **hard-fails** when
`~/.pi/agent/sessions/` does not exist instead of creating it — so the directory is a documented prerequisite.

**Measured 2026-09-30 — the seat's model leg is configured right and blocked by one host-resolver fact.** The
config half is sound: the rendered spark block matches the spec field-for-field and `pi --list-models` on that
box prints `spark | spark/qwen3.8-flash-next | 262.1K | 16.4K | yes | no` — the row
[pi-harness.md](pi-harness.md) §8 predicts — so the harness parses the contract it was rendered. The engine is
also reachable **from oldsrv**: with the resolver bypassed (`curl --resolve llm.kogler.si:443:<spark_home_ip>`,
no `-k`, so the certificate validated too), `/v1/models` returns `['spark/qwen3.8-flash-next']` on the seat's
own bearer, a bare chat comes back with thinking ON (`reasoning_tokens: 32`), and the harness's control works
from that box: `chat_template_kwargs.enable_thinking=false` → `reasoning_tokens: 0`, content `SMOKE_OK`. The
compat block is therefore **effective**, not merely declared.

✅ **2026-10-01 — the seat's model leg is now closed, and it was one host-resolver fact.** oldsrv asks its
own Technitium instance first and the Pi tertiary second (`host_resolver_dns` in
[`host_vars/oldsrv.kogler.si.yml`](../IaC/ansible/host_vars/oldsrv.kogler.si.yml), applied by the
`nm-resolver` leg of `roles/network`); mechanism, the measured target matrix and the three traps are
[network-dns.md](network-dns.md) §Host-side resolver. Re-measured on the box after the converge, with the
seat's own bearer and the token never leaving a pipe: `llm.kogler.si` resolves to spark's Home address
**by DNS** (not `/etc/hosts`), `/v1/models` returns the row, a bare chat returns `SMOKE_OK` with
`chat_template_kwargs.enable_thinking=false` → `reasoning_tokens: 0`, and the rest of the zone resolves too
(`media.kogler.si` → the oldsrv edge, `ai.kogler.si` → the VPS). The prerequisite that made this safe was
**HD-476** (every instance forwards rather than root-chasing, 2026-09-30): before it, pointing a host at an
instance traded a ~20 ms direct path for a chase.

⚠ **Correction to what this section used to say about the box:** it claimed oldsrv "runs **both** the role's
systemd-networkd units **and** NetworkManager, and NM wins". Measured 2026-10-01: `systemd-networkd` is
**disabled and inactive** there — no race, the netd renders are inert and name an interface the box does not
have. The half-finished config-manager decision is **HD-487**.

**Measured 2026-10-01 — the phone's "no model available" and "Update failed" were one defect: the unit had no
`pi` on PATH.** First real client on the cockpit (HD-444's phone) reached the seat and got an empty model
picker. Root cause, measured on the box: `pi-web` is a Go binary that **shells out to `pi`** for the model
list, every chat turn, and its own self-update — and **no flag overrides that path** (`pi-web -h` offers only
`-host -p -token/-insecure -o -version`). A systemd **user** unit gets no login shell, so it never sees
`~/.profile`: `/proc/<pi-web>/environ` read `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin`, while
`pi` lives inside the pinned Node tarball (`~/.local/share/pi-node/node-v22.23.3-linux-x64/bin/pi — pin bumped 2026-10-08; a seat's path changes only when `install-pi-debian.sh` next runs`). The
failure is not subtle once you ask the API itself — A/B on the live unit, one restart each way:

| `pi-on-path.conf` drop-in | `GET /api/models` | `POST /api/check-update` |
|---|---|---|
| absent | **HTTP 500** — `{"error":"pi executable not found: exec: "pi": executable file not found in $PATH"}` | 200 (it reads the registry, never runs pi) |
| present | 200, **419 models**, `spark \| spark/qwen3.8-flash-next \| 262144 \| 16384 \| reasoning true` | 200, `beta.36 → beta.38` pending |

Three traps fell out of it, all recorded in the runbook step that now prevents them
([../deployment-manual.md](../deployment-manual.md) Phase 4c):

- **The Node bin dir must be on PATH, not just `pi`.** `bin/pi` is a symlink to `dist/bundle/cli.js` whose
  shebang is `#!/usr/bin/env node`; with only a `pi` symlink reachable, the call dies as `env: 'node':
  No such file or directory`. A `~/.local/bin/pi` shim is therefore the wrong fix (and `~/.local/bin` is not
  on a user unit's PATH either — `.profile` is a login-shell file).
- **`?token=` is a cookie handshake, so it is useless for an API probe.** It answers 302 and sets a cookie;
  a bare `curl …/api/models?token=…` gets that 302 and no JSON. Drive it with a cookie jar (`-c`/`-b`).
- **A `gsub` on a `-F:` field that starts with a space erases the field.** The runbook's derive-the-port
  line printed empty for exactly this reason (`$2` = `" 31415 …"`, the match starts at character 1, so the
  whole field is deleted — `sub` is as wrong as `gsub` here). Replaced with a whitespace `awk`/`sed` form.

**Correction to the claim this section carried from the same day:** it said a `find` over `/home/domen`
found **no `pi` binary and no `pi-coding-agent` package**. It did not — `pi` **is** installed (0.87.1, run
against the rendered `models.json`), it is simply a **symlink** (`bin/pi ->
../lib/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js`), and a `-type f` find cannot see a
symlink. The version gap is now measured rather than inferred: **seat pi 0.87.1 + pi-web beta.36** (beta.38
available) vs **laptop pi 0.99.2**.

✅ **2026-10-01, later the same hour — the seat self-updated on the phone.** The UI's Update button is what
the missing PATH had been killing; with the drop-in in place it ran end-to-end and the seat is now
**pi-web beta.38**. Two facts worth keeping: the updater **restarts `pi-web.service` itself** and leaves the
drop-in directory untouched (`Environment=PATH=…` still in effect after the restart, `NRestarts=0`), and
**updating pi-web does not update `pi`** — the harness is still 0.87.1, which is exactly HD-484's remaining
tail.

✅ **2026-10-01 — the seat's harness defaults are landed too** (HD-484's last seat-local half):
`~/.pi/agent/settings.json` now carries the whole [pi-harness.md](pi-harness.md) §5 block
(`defaultProvider`/`defaultModel` = spark, `defaultThinkingLevel: off`, timeouts, compaction) with the
workstation key `packages` preserved, so the phone's session starts on the local engine instead of a cloud
model and stops thinking every turn. It is hand-written from §5 **by design**: `render-pi-config.py` has no
settings vendor and `models-spec.yml` states the boundary — the spec renders the *model contract*, never
settings. What the picker offers is still 419 rows (openrouter 386 · opencode-go 30 · entrim 2 · **spark 1**)
— the defaults decide the first turn, not the list length.

**What is still owed on the seat (HD-484's remaining tail):** the pi-version bump itself (seat 0.87.1 →
the laptop's 0.99.2 — the seat pins its npm prefix inside the Node tarball, so it is one `npm i -g` + a
re-read of §5), and the packaging that keeps all of this out of hand-keeping: **HD-445** (no role owns the
unit/drop-ins/env — including the `pi-on-path.conf` above) and **HD-446** (the missing
`scripts/install-pi-debian.sh`, whose trap list this measurement just grew).

**Measured 2026-10-05 — the seat is reachable from the laptop over the tailnet, and the seat trails the laptop.**
Two halves, both read from this workstation:

- **Reachability is now proven from a real peer.** `curl https://pi-oldsrv.ts.kogler.si/` from the Windows side of
  the laptop returned **401 served from oldsrv's tailnet address** with the Let's Encrypt `*.ts.kogler.si` pair validating *without*
  `-k`, and the same name forced onto the node address from WSL answered **401 on `/api/models`** as well — so the
  ACL (`domen@kogler.si → tag:dev:443`), oldsrv's own `websecure-ts` listener and the loopback backend all work.
  The name itself resolved **on Windows and nowhere in WSL**, and that gap is DNS-only: the `.ts` plane is answered
  by the client's own netmap, the mechanism is [network-dns.md](network-dns.md) §The answer-plane model, the
  sanctioned remedy is **HD-436**'s generated alias artifact, and **HD-432** already ruled out a routing-domain
  split. ⛔ A hand-typed `hosts` entry is the forbidden form — that doc's drift table names that violation.
- **The seat trails the laptop and nothing owned the gap** → registered as **HD-493**: seat `packages:` is
  `[@ygncode/pi-web@beta]` against the laptop's `pi-web-access` · `pi-subagents` · `pi-deepseek-optimized` ·
  `context-mode@1.0.169`; seat `defaultThinkingLevel: medium` against §5's `high` (owner 2026-10-05); seat commits
  unsigned (`user.signingkey`/`commit.gpgsign` unset, `%G?` = `N`); `skills/` deployed on **neither** seat
  (`scripts/sync-skills.sh --check` → "deploy target missing"); `tmux` absent on oldsrv (HD-445's package call);
  seat clone 1 behind with a leftover `homelab-wt-20261001-1315-1315` worktree. **Versions, corrected as measured
  (the paragraph above is stale):** seat **pi 0.99.2 + pi-web beta.38**, laptop **pi 1.0.2**. The seat's model leg
  is right, though — `pi --list-models` there prints `spark │ spark/qwen3.8-flash-next │ 262.1K`.
- **And the seat has no SSH door** → **HD-492**. `sshd -T` on oldsrv: `allowusers ansible-admin` + `ai-debug`,
  `passwordauthentication no`, `kbdinteractive no`, and **no `/home/domen/.ssh/authorized_keys`**, so the seat
  account the HD-443 ruling already names cannot log in; the laptop's `Host oldsrv-domen` block disables the one
  method oldsrv accepts (`PubkeyAuthentication no` + `PreferredAuthentications keyboard-interactive,password`) and
  the WSL twin has no such block at all. Read-back: `ssh oldsrv-domen` → `Permission denied (publickey)` while the
  `ProxyJump vps` hop itself succeeds. ⛔ Port 22 is not granted on the tailnet (`tag:dev:443` only), so this door
  rides the VPS jump.

- **The seat moved onto the box (2026-10-05, seat lane: HD-442/443/445/446/484/492/493).** What
  §9b-1 described as hand-kept is now converged, and the seat is reachable the way a seat has to be:
  `ssh oldsrv-domen` lands a `domen@oldsrv` shell key-only (HD-492 — `domen` was admitted by nobody
  and had no `authorized_keys`), the pi-web unit + BOTH drop-ins + the token env + linger + `tmux`
  render from vars via **roles/seat** (HD-445 — its own role, not `roles/cockpit` tasks, because the
  maint-console leg carries a vault-vs-box credential divergence that must stay a hard failure:
  rotating a console credential is an owner act, never a side effect of converging a seat), and a
  bare-Debian rebuild is a script now, not a memory (**scripts/install-pi-debian.sh**, HD-446).
  Both seats run **pi 1.0.3** on the same pinned Node tarball (22.23.3 since 2026-10-08 ⏳, was 22.23.2), the seat's `settings.json`
  carries the [pi-harness.md](pi-harness.md) §5 block verbatim (`defaultThinkingLevel: high`, the
  900 s idle timeout, the 16 k/32 k compaction pair, the 8 k thinking budget) and a smoke turn on
  the spark leg answered, so "the seat moved" is measured, not inferred.
  ⚠ **PATH splits by shell kind, and the seat is on the wrong side of both**: interactive shells get
  Node from `~/.bashrc`/`~/.profile` (which is why `ssh seat` works and `bash -l` sometimes does not),
  a **systemd USER unit gets neither** — that is what `pi-on-path.conf` exists for. A one-shot
  `ssh oldsrv-domen 'pi …'` reads neither file: use the absolute path. Neither may be "fixed" by
  copying a laptop `settings.json` (§1: settings have no renderer by design; §5 is the source).
  Seat commits are signed since 2026-10-06 (HD-495): the sign/auth keys moved into
  `Homelab-ansible`, so the seat's read-scope SA token pulls them with no owner hand, and
  `user.signingkey` carries the key FILE, which needs no agent. See CONVENTIONS §6.

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
| **Memory plane for the coding plane** | **Measured, undecided.** The 2026-09-21 `agentmemory` probe answered OQ-12/13/14 in one line each (§9b note + [`../reports/probe-agentmemory-20260921.md`](../reports/probe-agentmemory-20260921.md)); the owner call is open and nothing was installed. ⛔ Do not build a central instance before it: the shape the question assumed (LAN bind + per-client tokens + per-user isolation) does not exist in 0.9.29. |
| **HD-384** scoped-consumer tier | **Started 2026-09-26, not shipped.** The `rpm` field now has a code path (it had none — a decided cap minted an uncapped key and looked green); the first LAN record is authored **and minted** (`home-assistant`, 2026-09-27). Held: the OWUI grant (the glue is create-only — see §4), Docling's key (its consumer does not exist yet — HD-471/421; HD-402 closed 2026-09-28), and the `llm`-router client credential that ends `spark-llm_api`'s triple use. |
| **HD-268b** implement `rag-mcp` (+ `forgejo-mcp`) | Stub compose (no `services:` block). The rerank leg ships dormant until this exists. |
| **HD-267 tails** | Qdrant cutover verification + OKF wiki repos + first-ingest dimension check (1024). |
| **HD-248** Open WebUI instance split | One instance today; the public/internal capability split is undecided work. |
| **HD-383** stale `dsh_api` bearer | **CLOSED 2026-09-28** — vault-side CLEARED 2026-09-26 (the consumer stays rejected, decision #26: do not restore the record) and the orphan alias `dsh` deleted from the **VPS** DB (9 → 8, behind an alias guard). Findings, including the endpoint shapes and the untouched same-class residue: §4a above. |
| **HD-387** thinking-parameter re-measure | Open (see §9c). |
| **HD-402** Docling OCR engine | **Closed 2026-09-28 by measurement: keep RapidOCR.** The swap premise was inverted (production already runs RapidOCR, not EasyOCR) and EasyOCR is 3.2–3.4× slower with its own diacritic/merge defects on the same real Slovenian scans. Full numbers + method: §Docling OCR engine selection. Residual work became **HD-471** (empty markdown, `noexec /tmp`) and **HD-472** (prose-page recall). |
| **Mem0 / OpenHands** | Planned spark services; neither onboarded. |
