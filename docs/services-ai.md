---
title: AI Platform — Chat, RAG & Agents (LiteLLM / Open WebUI / OpenClaw / Docling / Qdrant)
role: detail
domain: services
status: active
tags: [services, ai, llm, llm-gateway, rag, agents, okf, vector]
---
# AI Platform — Family Web AI Layer

> **Role:** Stack doc (detail) — the family-facing web AI platform. LLM routing (LiteLLM), chat + RAG UI
> (Open WebUI ×2), agent orchestration (OpenClaw + dual coding harness), OCR ingestion (Docling), and the
> **Qdrant** vector store. This is the canonical owner for the **2026-08-27 AI modularisation decisions
> (HD-267)**: Qdrant-instead-of-PGVector · Forgejo-OKF wiki as knowledge SSOT · dual pi.dev+DSH harness.
> It is the **single merged view** that replaces both `ai-brainstorming.md` (deleted, folded here) and the
> pre-HD-267 PGVector-centric v2 text.
>
> Desktop/office AI (ONLYOFFICE, LocPilot, Word, email, presentations) stays in
> [`services-office.md`](services-office.md); this doc covers everything browser/agent-facing.
>
> **Links to:** `services-office.md`, `hardware-gpu.md`, `services-authentik.md`, `services-traefik.md`,
> `deployment-secrets.md`, `services.md`
> **Linked from:** `services.md`, `index.md`

> **Status:** VPS platform **live since 2026-08-22** (Phase 1): LiteLLM spine — **the HD-100/HD-247
> cutover is complete and those rows are deleted**: `litellm_api` + `litellm_version` pinned
> (`v1.83.10-stable`, verified on the running container), models live in the DB, scoped keys minted by
> the bootstrap glue. Do not re-do the cutover; the open LiteLLM questions are HD-384 (who may call
> what) and HD-373/387. ⚠ **“Open WebUI x2” is NOT true on the box (checked 2026-09-18):** the VPS
> runs ONE `open-webui` (`openwebui/open-webui:0.11.0`) at `Host(ai.kogler.si)` and the `chat` service
> is **element-web**, not a second OWUI instance — correct this banner as part of HD-248, which is
> still open. Historical wording: Open WebUI x2
> (`chat.kogler.si` public family / `ai.kogler.si` internal tailnet-only -- v2/Hi-248 split), Docling,
> OpenClaw up on the VPS. **Immich-ML is LIVE on oldsrv (Phase 3) and the `immich-app→immich-ml`
> cross-host round-trip is VERIFIED (2026-09-08)** — the VPS server health-checks the oldsrv ML
> endpoint over WG S2S (SSOT-derived `immich_ml_url` → oldsrv Home IP, HD-184; app log "Machine
> learning server became healthy", `/ping` 200 from the VPS over `wg-s2s`). Ollama is **disabled** —
> generation consolidated on spark (Triton/GB10, decision #23, 2026-09-06; **refined 2026-09-15,
> decision #24**: the small pinned services — STT/embed/rerank — move to the oldsrv RX 7600, spark
> keeps the big-model generation tier; **per-leg stack settled 2026-09-17, decision #25**: rerank went
> back to **CPU**, STT is **`whisper.cpp` GGML_HIP (native gfx1102)**, embed stays Ollama). **PGVector is being
> replaced by Qdrant** (HD-267; ⏳ migration/backtest + re-index before the live swap). ⏳ deploy-gated:
> Qdrant cutover, the OKF-wiki repos, and the RAG/agent live-tuning behind them. Supersedes the
> AnythingLLM path.
> Tracked via `todo.md` HD-1xx (`source: services-ai`).

---

## 1. Philosophy

One **LiteLLM endpoint** is the spine. Every consumer (Open WebUI ×2, OpenClaw, Qdrant's embed/rerank,
the dual coding harness) talks to it and **never sees an upstream provider key**. All external
**generation** uses a single `openrouter_api` key; **embeddings/rerank are local on spark** (bge-m3
1024-dim + bge-reranker-v2-m3 via Triton, 2026-09-06 — Cohere subscription retired). Model routing,
cost, rate limits, and credential management are centralized in one place.

**Two further invariants from HD-267:**
- **The vector store is independent of Open WebUI.** Qdrant stands alone (hybrid dense+sparse BM25) so the
  retrieval layer is not locked to any single UI — an AI interface is just a swappable shell (HD-267 ①).
- **Git is the source of truth for knowledge; the index is a rebuildable cache.** Forgejo OKF-llm-wiki
  repos hold the canonical `.md`; Qdrant indexes them and can always be rebuilt from the git floor
  (HD-267 ②).

---

## 2. Architecture

The system is split into **three strictly isolated network zones** on the VPS (no AI container touches the
host OS directly):

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
 │   Open WebUI ×2  ·  pi.dev  ·  DSH  ·  LiteLLM               │
 │   Qdrant (hybrid vector)  ·  rag-mcp (reader)  ·  Forgejo MCP │
 └──────────────────────────────────────────────────────────────┘
```

### AI hosting split (decided 2026-09-10) — family AI on the VPS, dev/ops AI on oldsrv

The AI estate is split by **who consumes it and where the compute lives** (tier doctrine: VPS = reliable/authoritative; oldsrv = RAM+GPU-heavy, declared-disposable):

| Side | Hosted on | Services | Why |
|---|---|---|---|
| **Family AI** | **VPS** | `open-webui` (SSO-dependent), `docling`, `qdrant`, `openclaw`, `rag-mcp`, `forgejo-mcp`, **VPS LiteLLM** | SSO-bound, reliable, backed-up — the family-facing web AI |
| **Dev AI** | **oldsrv** + `spark` | ~~`dsh` + `pi-dev`~~ **PARKED 2026-09-17 (HD-386, decision #26)** — removed by the owner; coding harnesses are dedicated deployments reached DIRECTLY, not docker_services, `OpenHands` (planned, spark), `immich-ml`, `mcp-victoriametrics`, `mcp-victorialogs`, **LAN LiteLLM (NEW, deploy-gated on spark)**, **pinned AI services (Whisper STT + bge-m3 embed — decision #24, restacked by #25 2026-09-17: rerank on CPU)** | RAM/GPU-hungry (oldsrv 48 GB + RX 7600); LAN-local consumers; state backs up to NAS/VPS |

Consequences of the split:
- **LiteLLM splits into two instances** (VPS + LAN) — it must sit next to its consumers (`litellm:4000` Docker-DNS only resolves same-host). VPS LiteLLM serves the family side (open-webui, openclaw, docling, qdrant, rag-mcp); **LAN LiteLLM (new)** serves the dev side. Per **decision #26 (2026-09-17)** its backend set is **spark (GB10) + the pinned-AI legs** for the **simple-querier tier** (HomeAssistant, Docling, OWUI-class consumers) — NOT the coding harnesses, which talk to spark directly. The LAN instance is **LIVE 2026-09-15** (`lan-litellm` Up/healthy on oldsrv behind `llitellm.kogler.si`). Each instance owns its own Postgres (`litellm-db`) + scoped keys, and both are Kopia-backed.
- **dsh + pi-dev move to oldsrv** and **lose their tailscale sidecars** / `*.ts.kogler.si` tailnet-node names (mobile access restored via the VPS `traefik-tailnet` edge → WG → `oldsrv_home_ip` host ports — the same bridge as media; still Authentik forward-auth on the edge, not public).

**IaC state (2026-09-10, HD-355/356) + VPS leg LIVE (2026-09-14):** the VPS `docker_services` no longer contains dsh/pi-dev; the sidecars are removed and the Web UIs publish on **`oldsrv_home_ip:3080` (dsh) / `oldsrv_home_ip:8080` (pi-dev)** — the media-bridge pattern (precedent: `immich-ml` on `{{ oldsrv_home_ip }}:3003`). `dsh_tailnet_sidecar_enabled`/`pi_dev_tailnet_sidecar_enabled` are **false** on the VPS; the clean-URL DNS still resolves dsh/pi-dev to the tailnet edge, which host-routes them **over WG** to the oldsrv backends. **✅ VPS leg verified LIVE 2026-09-14 (`547f905`):** the still-running `/opt/dsh` + `/opt/pi-dev` projects (containers `dsh`/`dsh-tailscale`/`pi-dev`/`pi-dev-tailscale`) were torn down (one-time ssh-vps cleanup) — no dsh/pi-dev containers or compose projects remain on the VPS; a latent duplicate-`pi-backend:` routes.yml bug (invalid YAML, entire tailnet routes file dropped) was fixed; the edge now serves `stats.ts.kogler.si` → 302 and `dsh.ts`/`pi-dev.ts` → 502/401 (backends reach `oldsrv_home_ip:3080/:8080` over WG, not yet serving — oldsrv session's scope). **2026-09-14: dsh/pi-dev model-backend re-pointed to the LAN LiteLLM** (`OPENAI_BASE_URL` → `http://lan-litellm:4000/v1` for dsh, `PI_MODEL_PROVIDER_BASE_URL` → `http://lan-litellm:4000/v1` for pi-dev) as the HD-356 future target. The **LAN LiteLLM** is authored (`templates/docker_services/lan-litellm/`) and referenced from the oldsrv list **deploy-gated on spark**: `enabled: false` until HD-335/HD-337. ⏳ **HD-356 UNBLOCKED + DEPLOYED 2026-09-15 (HD-370 session, owner go):** `config.yaml.j2` authored + rendered, compose `./config.yaml` mount added, `bootstrap_keys: true` (glue parameterized per-instance: scoped-keys SSOT per group_vars file + container from svc.name; host-side op CLI + `vps-op-write_api` token prerequisites added for bootstrap_keys hosts), vault derive-map entry added, registry order fixed (lan-litellm BEFORE dsh/pi-dev). dsh/pi-harness scoped-key records MOVED off vps.yml to home_servers.yml (same vault items; orphaned VPS-DB alias keys deleted server-side). ✅ `lan-litellm`+`lan-litellm-db` Up/healthy on oldsrv; serving via `llitellm.kogler.si` (307/401 verified). ~~⏳ tail: confirm the glue minted dsh_api/pi-harness into the LAN DB~~ **SUPERSEDED 2026-09-17 (HD-386, decision #26):** the harness consumers were removed, their scoped-key records are parked and `bootstrap_keys` is off on that instance — the LAN instance's scoped-consumer set starts with HD-384 (simple queriers).

**Spark artifact store (general, HD-359, 2026-09-14):** `roles/spark-artifacts/` downloads the GPU-inference store onto the spark XFS data partition from a **config-agnostic manifest** (`spark_artifacts:` in `group_vars/spark.yml`): B1 weights (`wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16` → `models/`), PLE overlay `.py` files, and INT4 tables (`primitive-ai/Qwen3.8-Flash-Next-PLE-quant` → `overlays/` + `ples_int4/`) — **one download per quant-artifact, shared by every engine profile** (vLLM B1 today; future NVFP4/SGLang repos = separate downloads by design). **STAGED LIVE on spark 2026-09-14** (169G weights + 3 overlays + 30G tables); idempotent per repo; runnable pre-bench via `--tags spark-artifacts`; the B1 engine (`spark-ai`) stays `enabled: false` until bench certifies a winner.


**Docker networks (HD-307):** OWUI-public on `traefik-public` (the `chat` route); OWUI-internal NOT
edge-routed -- tailscale-sidecar Pattern A; the AI harnesses (pi.dev, DSH) on `services-internal` via
netns tailscale serve (Pattern A); OpenClaw, Docling on `services-internal`; **Qdrant** on `db-internal`
(alongside the postgres/litellm-db); ~~Ollama on `llm-backend`~~ (HD-59, **removed 2026-09-06** — inference on spark). No host `0.0.0.0` port binds —
overlays + Traefik for the public plane, tailscale serve for the management plane (Flaw C / HD-62;
Patterns A/B in [network-vpn.md](network-vpn.md)).

> **Ollama isolation (HD-59):** Ollama has no native server auth, so it sits on the dedicated
> `triton-backend` overlay reachable **only by LiteLLM** (the spine), NOT on the flat `services-internal`
> network (same isolation as the removed Ollama, HD-59).

---

## 3. Components

| Service | Role | Network | Notes |
|---------|------|---------|-------|
| **LiteLLM** | LLM gateway / router | `services-internal` **+ `llm-backend`** **+ `tailnet-apps`** | OpenAI-compatible spine (v2, Postgres-backed, HD-247). Only component holding upstream keys. Joins `llm-backend` to reach Ollama; serves embed/rerank to Qdrant/rag-mcp. **HD-370:** admin reached at `litellm.kogler.si` **tailnet-only** (+`.ts`; tailnet edge → `http://litellm:4000`, docker DNS) — never public. **HD-372 (2026-09-15, ✅ LIVE):** the spine joins the **`tailnet-apps`** app→edge overlay (the dedicated bridge the `traefik-tailnet` edge already shares with dsh/pi-dev, HD-296) so the edge's backend route resolves it via Docker DNS — **NOT the flat `traefik-public`** (HD-59 keeps the key-holder isolated from public-route apps). Live-verified (edge `http://litellm:4000/health/liveliness` → "I'm alive!"; `litellm.kogler.si` → Swagger/UI 200). **HD-373 (2026-09-15, open):** `/ui/login` deep-link 404s (container has no nginx SPA fallback, upstream #29340) → **admin UI via `https://litellm.kogler.si/fallback/login`** (intended fallback login; master-key `litellm_api` works). Its spark generation entry uses `https://llm.kogler.si/v1`. **HD-382 (2026-09-17, LIVE + E2E-verified):** `spark/qwen3.8-flash-next` is registered in this DB with **NO `api_key` in the row** — the bearer arrives from the container's `OPENAI_API_KEY` env (1P `spark-llm_api`), because v1.83.10 does **not** expand `os.environ/…` inside DB-stored `litellm_params` (it forwards the literal upstream → engine 401; live-proven through the proxy and in-process). The container also needs `extra_hosts` glue for `llm.kogler.si` (VPS resolv.conf is public-only and the VPS primary must never answer the LAN-only name — reach was never the gap: it routes `spark_home_ip` via `wg-s2s`). **https, not http:** spark's :80 edge is redirect-only and the OpenAI SDK does not follow a 307 on POST. `chat_template_kwargs` thinking control survives `drop_params: true` (measured `reasoning_tokens: 0`). **HD-389 (2026-09-18, LIVE):** the tailnet path to the spark entry (`base_url https://llm.kogler.si/v1` from this VPS instance over WG) needed spark's name edge to also route the `.ts` twins — done (spark-dashboard routes + `*.ts` cert pair; see `network-vpn.md` reach matrix). |
| **Open WebUI ×2** (v2, HD-248) | chat + RAG UI | `traefik-public` / tailnet sidecar | `chat.kogler.si` PUBLIC (family, limited keys, **OKF Family-Manuals KB only**); `ai.kogler.si` INTERNAL (tailnet-served; you+wife, agent keys, `rag_internal`). Auth = Authentik OIDC both. |
| **Qdrant** | **hybrid vector store (HD-307)** | `db-internal` | Standalone Rust DB (dense+sparse BM25), **independent of OWUI built-in RAG**. Replaces PGVector. Vector dimension locks at first ingest (1536). Add a snapshot/backup seam. |
| **Forgejo (wiki repos)** | **knowledge SSOT** (HD-307) | `db-internal` / git | OKF `.md` repos per owner; git = truth; Qdrant = rebuildable cache. |
| **kapa-inspired-rag-mcp** *(planned)* | MCP hybrid reader | `services-internal` | On @wiki-<x> query: hybrid search in Qdrant → top-20 → bge-reranker-v2-m3 rerank (via LiteLLM `jina_ai/` → **`llama.cpp server-vulkan` on the oldsrv RX 7600**, decision #27 accepted 2026-09-18 — was “CPU reranker” under #25, measured 5.3 s vs 0.34–0.50 s) → top-5 clean markdown. ⚠ Service is `enabled: false` on the VPS today ⇒ the rerank leg has **no live consumer** yet. |
| **Forgejo MCP** *(planned)* | MCP read/write `.md` | `services-internal` | Bridge to the OKF wiki repos; agents read/write notes + open PRs. |
| ~~Ollama~~ *(removed 2026-09-06)* → **re-armed 2026-09-15 (HD-369)** | ~~Local LLM inference~~ → **embeddings host** | `llm-backend` | **Correction:** the 2026-09-06 removal was reversed by decision #24/#25 — `ollama:0.32.15-rocm` is **LIVE on oldsrv** and serves `bge-m3` embeddings (1024-dim, E2E-verified, 833–899 MiB VRAM, ~500 ms/chunk). It is **not** a rerank host (no `/api/rerank` at any version, §9c) and **not** an STT host. Under decision #27 it is **demoted to the embed fallback rung** and retires once the Vulkan embed leg is live-verified (HD-391). |
| **Triton Inference Server** *(planned, spark)* | NVFP4 local inference | `triton-backend` | On the **spark** GB10 node (HD-335) — **the big-model generation tier** (decision #24, 2026-09-15; was "sole local-inference tier" #23). Serves the NVFP4 generation set (Nemotron-30B, Qwen3-Next-80B, Llama-3.3-70B, Qwen3-Coder-Next-80B) — **one big model with the largest context** (Qwen3-Coder-Next-80B, 262k ctx via SGLang). The small pinned services (Whisper STT, bge-m3 embed, bge-reranker) **moved to the oldsrv RX 7600** (decision #24). Reachable only by LiteLLM — same isolation as the removed Ollama (HD-59). **Model repo = Ansible-managed** (per-model `config.pbtxt` J2 templates + idempotent NVFP4 conversion + strict `1/` layout, `/srv/models/spark/`; see `hardware-spark.md` §Bring-up). **Model-catalog sync = git SSOT `models.yml` → LiteLLM DB** (reconciler: onboard upserts, offboard scoped-deletes git-sourced models only + same-change `litellm_scoped_keys` cleanup; manual OpenRouter models untouched). GB10 bring-up reference: [`dgx-spark-ml-guide`](https://github.com/martimramos/dgx-spark-ml-guide). |
| **Mem0** *(planned, spark)* | Long-term memory for OWUI | `services-internal` | Backed by **Qdrant** (HD-267/268). Per-user/per-project scoping via `user_id = <openwebui-user-id>-<model-id>`; `mem0.search(query=…, user_id=…)`. |
| **OpenHands** *(planned, spark)* | Agentic coding harness | oldsrv / spark | A third coding cockpit alongside pi.dev + DSH (HD-307/250); served by the **LAN LiteLLM** (scoped key) + PR-only Forgejo token.
| **Docling** | OCR / document understanding | `services-internal` | **CPU on the VPS** (that host has no GPU). Model stack = layout detector + TableFormer + a pluggable OCR engine; current engine **EasyOCR** (has a dedicated `sl` model → Slovenian scans, HD-103). ⚠ Its accelerator set is `auto\|cpu\|cuda\|mps\|xpu` — **no Vulkan/ROCm**, so Docling cannot use the oldsrv RX 7600. ⏳ **HD-402:** proposed engine swap EasyOCR → **RapidOCR-ONNX** (`latin` rec group, includes `sl`) for CPU speed — **benchmark before applying** (script-grouped model vs the dedicated `sl` model = a quality risk on `č ć š ž`); free lever available regardless: `do_ocr=False` for born-digital PDFs. |
| **OpenClaw** | AI agent / orchestration | `services-internal` | Version pinned. Models → LiteLLM scoped key. |
| **pi.dev + DSH** *(dual harness, HD-307)* | **PARKED as services 2026-09-17 (HD-386, decision #26)** — DevOps/IaC coding cockpits (C# + IaC) | **dedicated deployments** (not docker_services); the workstation harness runs on the admin laptop | **Status 2026-09-17 (decision #26):** both harnesses are REMOVED — the VPS originals were torn down 2026-09-14 and the oldsrv pair never became a working consumer — and the registry entries are `enabled: false` (kept so `template_dir` + the port contract survive a re-onboarding; see `group_vars/home_servers.yml`). They will run as **dedicated deployments**, and per decision #26 they reach the engine **DIRECTLY** at `llm.kogler.si`, NOT through LiteLLM (reasons + the measured parameter-loss risk: §9 row 26 + [pi-harness.md](pi-harness.md) §1b; the probe that would reopen it: HD-387). Historical shape, for the record: `pi-dev` (pi coding-agent container, npm `@earendil-works/pi-coding-agent` + `pi-web-access`) and `dsh` (`runzhliu/deepseek-harness`) ran side-by-side (supersedes HD-250; decision #20), each on a **scoped LAN-LiteLLM key** (`pi-harness_openai_api` + `dsh_api`, both items still in the vault, records parked) + a PR-only Forgejo token; propose homelab via Forgejo PRs (PR-only, no-merge); 443 egress accepted (recorded risk); Web UIs published on `oldsrv_home_ip:3080` (dsh) / `:8080` (pi-dev) with pi itself TUI/CLI; mobile reach via the VPS tailnet edge over WG behind Authentik forward-auth. ⏳ The tailnet `dsh`/`pi-dev` records + `dsh-backend`/`pi-backend` routes still exist and answer **502 by design** — removing them is an owner call (HD-386 tail). **Harness-side model config** (workstation pi.dev → `spark/qwen3.8-flash-next`: 262k context, thinking control, timeouts, parallel-lane KV rule) is owned by [`pi-harness.md`](pi-harness.md) (HD-376) |

| **LiteLLM (LAN / dev) *(NEW, spark-deploy-gated)* ** | Dev-side LLM gateway | oldsrv, ⏳ spark | **LAN instance** of the split LiteLLM (HD-356). Scope re-set by **decision #26 (2026-09-17): the SIMPLE-QUERIER tier** (HomeAssistant, Docling, OWUI-class) + the pinned-AI legs (decision #25) — **not** the coding harnesses, which go direct. Own Postgres (`lan-litellm-db`), Kopia-backed. ⚠ Its `litellm_scoped_keys` list is currently EMPTY (harness records parked with their consumers, HD-386), so `bootstrap_keys: false` on the registry entry; the first records back are the simple-querier allow-lists of HD-384. **`enabled: false`** in the oldsrv list (2026-09-14 re-affirmed — spark not certified; the template also still lacks a `config.yaml.j2` render (compose references `./config.yaml`) + a `bootstrap_keys` flag to mint its scoped keys, so it is NOT runnable until those land + spark flips). dsh/pi-dev already point at `lan-litellm:4000` as the target. ⏳ Full enable = spark-certify → add config.yaml.j2 + bootstrap_keys → flip + converge oldsrv. **HD-370 (2026-09-15):** exposes as **`llitellm.kogler.si`** on the oldsrv traefik-internal HOME edge (llogs pattern; `http://oldsrv_home_ip:4000` backend; TLS + HSTS); its spark model entry (**LIVE 2026-09-17, HD-382**) uses **`https://llm.kogler.si/v1`** as base_url (LAN name → spark's own :443 name edge) with **no key in the DB row** — the bearer comes from the container's `OPENAI_API_KEY` env (1P `spark-llm_api`) and the name arrives via `extra_hosts` (oldsrv's resolv.conf is public-only by WAN-out-survival design and `/etc/hosts` is not inherited by containers). The earlier `http://` spec was wrong: spark's :80 is redirect-only → a 307 on POST, which the SDK does not follow.

### 3a. Pinned AI inference tier — plan of record (decision #27, **accepted 2026-09-18**)

> The one table for “what AI runs on oldsrv, on what device, with which model”. Every latency/VRAM figure is
> **measured on this box**, not estimated — provenance and repro commands in
> [services-ai-bench.md](services-ai-bench.md). ⚠ **The ⏳ rows are NOT deployed**: IaC is HD-391, so until
> that lands this table describes the *target* state; today only `embed (Ollama)`, `lan-litellm`, `immich-ML`,
> `Sunshine` and the observability MCPs are live.
>
> **2026-09-19 — ALL THREE LEGS ARE LIVE + LIVE-VERIFIED (HD-391).** Authored, converged (`failed=0`,
> twice more for two implementation findings below) and measured on this box the same evening: `whisper`,
> `reranker`, `embed` are `Up (healthy)` on `llm-backend`, reached through `lan-litellm`, at **2475 MiB** of
> 8 GiB VRAM. The measured numbers per leg are in §3a-2; the three implementation findings the bench could not
> produce (ubatch, the image healthcheck, and the LiteLLM embed provider) are in §3a-3.

| Leg | Engine — target state | Model (quant) | Device | VRAM (measured) | Latency (measured) | Status |
|-----|----------------------|---------------|--------|-----------------|--------------------|--------|
| **Embeddings** | `llama.cpp server-vulkan` (`--embedding --pooling cls`, `--embd-normalize 2`) | `bge-m3` **Q8_0** (634.6 MB) | RX 7600 / Vulkan | **~326 MiB** | **15 ms**/chunk · 51-doc batch 0.86–1.40 s · **deploy: 0.45 s for a 51-doc batch** | ✅ **LIVE 2026-09-19** (`embed`, :9002, gateway row `bge-m3-vk` · dim 1024, ‖v‖=1.0) · cos 0.9996 ⇒ no re-embed |
| ↳ embed fallback rung | `ollama:0.32.15-rocm` (`/api/embed`) | `bge-m3` (fp16) | RX 7600 / ROCm | **833–899 MiB** | ~470–545 ms/chunk · batch 1.83–1.93 s | ✅ **LIVE + E2E-verified** — **KEPT as the fallback rung** (owner 2026-09-19, it does NOT retire now). ⚠ Two things measured the same evening: **no LiteLLM instance carries an `ollama/*` row** (each had exactly one row, `spark/*` — §4a), so this rung is a service + model, not a catalog entry; and the two retired blobs were deleted from disk while **`bge-m3` stayed and re-verified at dim 1024 afterwards** |
| **Reranker** | `llama.cpp server-vulkan` (`--embedding --pooling rank --rerank`), routed as LiteLLM **`jina_ai/`** | `bge-reranker-v2-m3` **Q8_0** (635.7 MB) | RX 7600 / Vulkan | **~327 MiB** | **0.34–0.50 s** for 20 docs (top-20) · **deploy: 0.95 s solo / 1.15 s under three-way load** | ✅ **LIVE 2026-09-19** (`reranker`, :9001, gateway row `local-rerank`, ranking verified) · **ships DORMANT** (consumer = HD-268b stub) · TEI CPU rejected by measurement |
| **STT (voice)** | `whisper.cpp:main-vulkan` (`--inference-path /v1/audio/transcriptions`) | `large-v3-turbo` **fp16** (q5_0 = −1.0 GiB option) | RX 7600 / Vulkan | **1788 MiB** (Δ1722) · q5_0 **786** | **0.40 s** per 11 s WAV · **deploy: 0.53–0.60 s per ~7–13 s of real Slovenian radio speech** | ✅ **LIVE 2026-09-19** (`whisper`, :9000, gateway row `local-stt`; real Slovenian verified — CJVT GOS corpus) · CPU fallback native (init-time): 17.5 s |
| ↳ iGPU option | ~~HD 630~~ | — | iGPU | 798 MiB **host RAM** | 5.8–22.8 s per rerank request | ❌ **rejected by measurement** — slower than CPU, Gen 9.5 driver stack frozen, contends with Xorg + Jellyfin QSV ([bench §4](services-ai-bench.md)) |
| **Gateway** | `lan-litellm` (+ own Postgres) | — | CPU | — | — | ✅ live · ✅ **the three pinned-AI rows are IN the DB since 2026-09-19** (`local-rerank`, `bge-m3-vk`, `local-stt`) and each was answered **through** the gateway — §4a |
| **immich-ML** | immich’s own bundled ROCm | CLIP / face / doc | RX 7600 / ROCm | 0 idle · **3–5 GB during a job** | job-bound | ✅ live · **lowest priority**, pause-able (Sunshine glue) |
| **Sunshine** | VCE/AMF encode | — | RX 7600 | not a KFD compute consumer | — | ✅ live · gaming-first: its prep-commands pause `immich-ml` |
| **Observability MCPs** | victoriametrics / victorialogs MCP | — | CPU | — | — | ✅ live |
| **Piper TTS** | piper (CPU) | — | **not on oldsrv** — CPU in HA on the Pi | — | instant | ✅ live (unchanged by #27) |
| **Generation** | spark vLLM behind `llm.kogler.si` | `qwen3.8-flash-next`, 262k ctx | **not on oldsrv** (decision #24/#26 — harnesses go direct) | — | ~11 tok/s decode | ✅ live |
| **RAG reader / Qdrant / Docling** | `rag-mcp` · Qdrant · Docling | — | **VPS** | — | — | ⚠ `rag-mcp` is **not a service yet** — its compose file is an HD-268b STUB with no `services:` block, so `enabled: false` is not a flag to flip (flipping it fails `docker compose config`). **Owner call 2026-09-19: the reranker ships DORMANT with the tier**, implementation stays parked as **HD-268b**, and the rerank leg is verified by a LiteLLM probe + a synthetic consumer — **not** by live RAG traffic |

**Tier budget (VRAM, `mem_info_vram_used` deltas — treat as RELATIVE, [bench §3c](services-ai-bench.md)):**
target all-Vulkan tier = **~2.4 GiB of 8 GiB** (embed 0.33 + rerank 0.33 + STT 1.72) with **host RSS ≈ 0.5 GiB
across all three legs** (157 MiB each) and **zero `/dev/kfd` consumers in the AI tier** — which also removes the
per-ROCm-runtime RAM tax §9c made the central argument of decision #25. The measured three-way concurrency case
(STT + rerank + embed simultaneously) cost ≈1.5–2× each and was **flat over 6× sustained** load, with **0
`amdgpu` hang/reset lines**. immich-ML (3–5 GB during a job) still co-resides at the low end of its range.

**Engine-family consequence:** the tier becomes **two published images, one backend family**
(`ghcr.io/ggml-org/llama.cpp:server-vulkan` for embed+rerank, `ghcr.io/ggml-org/whisper.cpp:main-vulkan` for
STT), both **mutable aliases ⇒ digest-pinned** per CONVENTIONS §7, with GGUF/GGML model-fetch tasks verified
against the sha256s in [services-ai-bench.md](services-ai-bench.md) §1.

#### 3a-1. Deployed shape (HD-391 — deployed + live-verified 2026-09-19)

The runbook values, so a re-deploy or a rebuilt DB does not have to re-derive them. All three legs sit on
`llm-backend` (`external: true`) with **no `ports:` and no Traefik labels** — HD-59 doctrine: these APIs have
no auth, so the network *is* the boundary and only `lan-litellm` may speak to them.

| Service | Image pin (`group_vars/all/versions.yml`) | Listen (llm-backend only) | Weights (`:ro`) | Model sha256 (VERIFIED on the bytes) | Hard mem cap |
|---|---|---|---|---|---|
| `whisper` | `whisper_cpp_vulkan_image` (`main-vulkan@sha256:cf102ac3…`) | `:9000` (`ai_tier_whisper_port`) | `/srv/models/whisper/ggml-large-v3-turbo.bin` (1 624 555 275 B) | `1fc70f77…2bc69` | `4g` (`ai_tier_whisper_memory_limit`) |
| `reranker` | `llama_cpp_vulkan_image` (`server-vulkan@sha256:7158edb4…`) | `:9001` (`ai_tier_reranker_port`) | `/srv/models/reranker/bge-reranker-v2-m3-Q8_0.gguf` (635 676 416 B) | `a43c7c9b…a1d3` | `1g` |
| `embed` | same llama.cpp digest as reranker | `:9002` (`ai_tier_embed_port`) | `/srv/models/embed/bge-m3-q8_0.gguf` (634 553 760 B) | `aa473d51…a173` | `1g` |

Both GGUF legs run `--ctx-size` **2048** (`ai_tier_gguf_ctx_size`): llama.cpp **truncates silently** beyond the
window and `llama-server`'s own default is 512, which would slice the documented ingest chunk (§5b =
token-based **512/64**) in half. 2048 = that spec with 4× headroom; bge-m3 supports 8192, and paying KV memory
for chunks that do not exist yet buys nothing. Re-derive when HD-268b goes live and a real chunk size becomes
measurable. **The ctx-size alone was not enough — `--batch-size`/`--ubatch-size` had to move with it, and that
is a measured story, not a theory: §3a-3 finding 1.**

**Model fetch is generic, not bespoke (HD-391):** `roles/docker_services/tasks/deploy-service.yml` grew an
opt-in `svc.model_url` / `model_dir` / `model_file` / `model_sha256` hook — the same opt-in-registry-key
pattern as `bind_owner_uid` and `db_role_sync`, so no new hook mechanism was invented. `get_url` + `checksum`
is idempotent **by content**: a present file with the right digest is an ok-not-changed no-op, and a digest
mismatch **fails the converge** instead of booting an engine on half a model. There is no `default()` on the
digest — an entry with `model_url` and no `model_sha256` aborts the render (HD-65 fail-loud). Weights are
public artifacts: never in git, never in the vault, and (like `ollama`/`spark-ai`) these three templates stay
OUT of `_template_vault_items` and render with zero vault lookups.

**Device + gid (measured, and a live correction):** the legs mount **only** `gpu_vulkan_render_node` =
`/dev/dri/renderD129` (RX 7600 `gfx1102`); `renderD128` is the HD 630 iGPU — the desktop's Xorg device and the
Jellyfin QSV transcoder, and measured slower than CPU for this work. `group_add` uses `gpu_render_gid`, whose
value was **corrected 2026-09-19 from the assumed Debian 104 to the live 992**: on oldsrv `getent group 104` =
`ssl-cert` while `render` = **992**, so every GPU leg (`ollama`, `immich-ml`, `jellyfin`, `sunshine`) had been
adding the **ssl-cert** group to its container. It never broke anything only because the render nodes are
world-rw on this desktop box (`getfacl /dev/dri/renderD129` → `other::rw-` + a `lightdm` ACL) — the wrong gid
was masked, not harmless by design. See [hardware-gpu.md](hardware-gpu.md).

**Onboarding steps 6.5 / 7 (CONVENTIONS §5) — storage and observability:** the weights live on the `nvme/models`
.dataset (`/srv/models/<leg>`; 897 G free measured 2026-09-19), which `roles/storage` treats as regenerable —
no snapshots and **not in the Kopia / `db-backup` scope**, the same rule `ollama` and `immich-ml` already follow:
2.8 GB of public, digest-pinned weights is cheaper to re-fetch than to back up. No dedicated exporter either:
the legs are covered by oldsrv's Alloy host metrics plus the `amdgpu` sysfs `mem_info_vram_used` counter that
the §3a budget is measured against, and their logs use the stock Docker logging driver. Nothing here adds a
scrape target or a dashboard. Step 9 (the deploy gate) was cleared 2026-09-19 with a dry render, the
`docker compose config` pre-validation the role runs (HD-162) and a `failed=0` converge.

#### 3a-2. Deployed + measured (2026-09-19, first live converge)

Converged with `--tags docker_services,whisper,reranker,embed` — **`failed=0`**, three containers `Up
(healthy)`, `docker inspect` proves the spec (not the RECAP): `devices=[/dev/dri/renderD129]` only, **no
`/dev/kfd` anywhere in the tier**, `ports=map[]`, `restart=unless-stopped`, `cap_drop=[ALL]`, image by digest.

| Measurement | Target | **Measured on the deployed containers** |
|---|---|---|
| Tier VRAM | ~2.4 GiB / 8 GiB | **2475 MiB** with all three warm (`mem_info_vram_used`; idle baseline was 66 MiB) — the target, hit |
| Host RSS | ≈ 0.5 GiB | **415 MiB** (whisper 96 + reranker 157 + embed 162) |
| Embed | 15 ms/chunk | dim **1024**, ‖v‖ = **1.000000**; **0.45 s** for a 51-document batch |
| Rerank | 0.34–0.50 s / 20 docs | **0.95 s** solo for a 20-doc top-5 (real Slovenian sentences), correct ranking (the copy/backup doc −2.7 vs −11.0 for the irrelevant one) |
| STT | 0.40 s / 11 s WAV | **0.53–0.66 s** per ~7–13 s clip of **real Slovenian broadcast speech** (CJVT GOS corpus, converted in-container with the image's own `ffmpeg`) — e.g. *“Ljubljana …, rahlo sneži in nič … Maribor …, snegom dve stopinji celzija”* and *„… bo delno jasno spremenljivo oblačnostjo, če pogledamo skozi okno …“*. The bench only ever ran `jfk.wav` (English), so this is new evidence |
| Three-way concurrency | ≈1.5–2× each, flat | each leg **1.15–1.19 s** simultaneously vs 0.60/0.95/0.45 s solo; **total wall 1.25 s < the 2.00 s sequential sum** — the contention the bench predicted, and the aggregate still beats serial |
| `dmesg` (HD-393 baseline 1,296 / 0) | 0 hang/reset | **0 hang/reset.** Last `init_user_pages` line is still `[780804.8]` while uptime passed **875842 s** → **zero new lines** from this deploy. (The raw count read 1226 after, i.e. **ring eviction**, not recovery — the same trap that made HD-393's count grow while the episode was over. ⚠ reading `dmesg` here needs `sudo`: `dmesg: read kernel buffer failed` otherwise, and an unsprivileged count silently returns 0.) |

> **Three things this deploy did NOT establish** (each keeps its own owner): (1) **no scoped consumer reaches
> these rows** — every probe above used the master key, so per-key routing and the allow-list are still
> **HD-384 / HD-268b**, and nothing a family member runs changed behaviour; the legs are reachable on the admin
> path only. (2) **2475 MiB is a steady-state reading** — a one-shot startup peak (three simultaneous Vulkan
> inits) is not visible to `mem_info_vram_used` sampled after warm-up; the bench's triple-start probe saw 0
> `amdgpu` lines, which is the closest evidence we have. (3) **the rank reranker's quality is still unmeasured**
> — no nDCG@10 against labelled data (§3a's standing caveat), and the CPU-vs-GPU rerank latencies come from two
> different harnesses, so treat the speedup as an estimate.

#### 3a-3. Three findings the bench could not produce (each one broke or would break a real call)

1. **`--ctx-size` is not the batch limit — `--ubatch-size` is.** With the defaults the embed endpoint answered
   **HTTP 500 `input (842 tokens) is too large to process. increase the physical batch size (current batch
   size: 512)`**. The first fix (`--batch-size 2048 --ubatch-size 512`) **still failed with the same message**,
   because the number it reports is the **ubatch**. So both legs run `--batch-size 2048 --ubatch-size 2048`
   (`ai_tier_gguf_batch_size` / `ai_tier_gguf_ubatch_size`); after that the same 842-token chunk returns 200
   and the log line reads `n_tokens = 842, truncated = 0`. **VRAM cost of ubatch 512 → 2048: ~15–35 MiB**
   (2440–2460 → 2475 MiB) — cheap, and the compute buffers scale with ubatch, not with ctx. Note the
   behaviour differs by endpoint and by direction: an **oversized** input (> ctx) is a **loud 500**, not the
   silent truncation §5b/§3a-1 warned about — silent truncation is a generation-path hazard, so embeddings are
   actually safer than assumed, but a chunk over ~2048 tokens fails the ingest loudly.
2. **The `llama.cpp` image hardcodes `HEALTHCHECK curl http://localhost:8080/health`.** Our legs listen on
   9001/9002, so both GGUF containers reported **`unhealthy` while answering 200** — a false alarm that would
   poison every future "what is actually live" census. Fixed with an explicit `healthcheck:` per leg pointed
   at its own port (`start_period: 90s` for Vulkan init + weight load). Any future leg on a non-8080 port must
   override it too.
3. **LiteLLM's `openai/` embed provider forwards `encoding_format: null`, and llama.cpp rejects null** —
   `[json.exception.type_error.302] type must be string, but is null` → the leg worked, the **gateway row did
   not**. `hosted_vllm/bge-m3` on the same `api_base` works (verified dim 1024 through the proxy). So the embed
   row is `hosted_vllm/…`, and `user: null` is tolerated while `encoding_format: null` is not — the distinction
   is invisible from the outside, so it is recorded here.

---

## 4. LLM routing & keys

- **One endpoint — for the tier that has one (decision #26, 2026-09-17):** Open WebUI ×2, OpenClaw,
  Docling, HomeAssistant and Qdrant's embed/rerank authenticate to **LiteLLM only**, via per-consumer
  **scoped virtual keys** (HD-247) — they never hold `openrouter_api` or the master key. **The coding
  harnesses are the deliberate exception** (pi.dev/Continue.dev/dedicated deploys → the spark name edge
  directly): rationale in §9 row 26, the client-side contract in [pi-harness.md](pi-harness.md) §1b.
- **Generation → Open Router:** one `openrouter_api` key (api → credential) reused for **all** external
  chat/LLM models, declared in LiteLLM's `config.yaml`. The coding-embed path specifically routes
  **DeepSeek via OpenRouter** (the brainstorm's pi serve / DSH backend) + local Ollama; any model listed
  on OpenRouter is selectable through the one LiteLLM dropdown.
- **Generation → spark (HD-382, 2026-09-17):** `spark/qwen3.8-flash-next` is a runtime DB entry in BOTH
  LiteLLM instances (`api_base https://llm.kogler.si/v1`, key from the container env, never in the DB row).
  ⚠ It is **not yet reachable by scoped consumers**: `litellm_scoped_keys` allowlists stay
  `ollama/*,openrouter/*` on the VPS spine and the LAN list is now EMPTY (its harness records were parked
  with their consumers, HD-386) — so the LAN instance currently has **no scoped consumer at all** and its
  key-minting glue is switched off (`bootstrap_keys: false`; the glue fail-louds on an empty spec list).
  **HD-384 is now the simple-querier allow-list** (`spark/*` + `ollama/*` for ha/docling/owui), not the
  harness question that blocked it (decision #26 settled that: harnesses go direct). The stale `dsh_api`
  secret behind **HD-383** is parked, not fixed — its remediation is recorded there for whenever a record
  is restored. Until HD-384 lands the gateway path serves the master key / admin path only.
- **Embeddings → the Vulkan `embed` leg on oldsrv (decision #27, 2026-09-18; LIVE since 2026-09-19, HD-391 shipped):** `bge-m3` **Q8_0**, **1024-dim unchanged**, `llama.cpp server-vulkan`. History kept for the audit trail: Cohere retired 2026-09-06 (previously embed-v4 @1536, accepted 2026-08-16), then local `bge-m3/1024` via **Ollama `:rocm`** on the RX 7600 (decision #24) — which #27 demotes to the **fallback rung**, not the primary (measured 15 ms vs ~500 ms per chunk, 326 vs 899 MiB VRAM, cosine 0.9996 ⇒ same vector space). “via Triton on spark” was the 2026-09-06 framing and is superseded by #24/#27: the pinned tier is oldsrv’s, spark is the generation tier.
- **Rerank → the Vulkan `reranker` leg on oldsrv (decision #27; was “→ CPU” under #24/#25; **LIVE since 2026-09-19 but DORMANT** — the container answers, its consumer is the HD-268b stub):** `bge-reranker-v2-m3` **Q8_0** as a `llama.cpp` cross-encoder (`--pooling rank --rerank`), reached via LiteLLM **`jina_ai/`** (provider-routing question CLOSED: `litellm/llms/jina_ai/rerank/transformation.py` accepts a custom `api_base` and rewrites the path to `/v1/rerank` — read in the pinned v1.83.10 image on the box, 2026-09-19). The CPU placement is **superseded by measurement** (5.3 s vs 0.34–0.50 s, [bench §3/§5](services-ai-bench.md)). **Still not Ollama** — Ollama serves no rerank API at ANY released version and LiteLLM has no Ollama rerank provider; the old “needs ollama ≥ 0.5.x” note is retracted (§9 #25, [hardware-gpu.md](hardware-gpu.md)).
- **Local models:** Ollama listed via LiteLLM so family sees local + cloud in one dropdown; local is
  default where privacy/offline matters. **spark (HD-335)** adds the **Triton** NVFP4 set + local embeddings
  (bge-m3/reranker) as further LiteLLM backends (details in [`hardware-spark.md`](hardware-spark.md)).

**Local model recommendations** (office/voice workloads, moved from `services-office.md` — HD-199
boundary trim; this doc is the platform SSOT for model guidance):

| Model | VRAM | Best For |
|-------|------|----------|
| **Llama 3.1/3.2 8B** | ~6 GB | Everyday office, email drafting, summarization (via LiteLLM — OpenRouter today; local when spark/Triton is provisioned, HD-335) |
| **Qwen 2.5/3.5 7B–14B** | ~6–12 GB | Complex document structuring, code generation (via LiteLLM) |
| **Phi-4 14B** | ~10 GB | Reasoning, logic, Microsoft workflow drop-in (via LiteLLM) |
| **NVFP4 30–80B set (Nemotron-Lightning-30B, Qwen3-Next-80B, Llama-3.3-70B, Qwen3-Coder-Next-80B)** | fits in **spark 128 GB unified** | Heavy programming / local reasoning — served by **Triton** on `spark` (HD-335, [`hardware-spark.md`](hardware-spark.md)) |

**1Password (`Homelab-ansible`) items — see [`deployment-secrets.md`](deployment-secrets.md):**

| Item | type → `field=` | Used by |
|------|-----------------|---------|
| `openrouter_api` | api → `credential` | LiteLLM (all external LLM generation) |
| ~~`cohere_api`~~ *retired 2026-09-06* | — | **Removed** — embeddings/rerank local on spark (bge-m3/1024 + bge-reranker), Cohere subscription cancelled. |
| `litellm_api` | api → `credential` | admin/bootstrap ONLY (HD-247) |
| `litellm_db` | db → `password` | litellm-db runtime DB (models-in-DB) |
| scoped keys (`owui-public-chat_api`, `owui-public-rag_api`, `owui-int-wife_api`, `owui-int-owner_api`, `dsh_api`, `openclaw-litellm_api`, `rag-int-svc_api`) | api → `credential` | per-consumer glow-minted keys (HD-247) |
| `openwebui_secret` | password → `password` | Open WebUI session/encryption secret |
| `qdrant_db` | api → `credential` | Qdrant hybrid vector store (HD-268; no username, single static API key via `QDRANT__SERVICE__API_KEY`) |

> Fail-closed secrets: no `default('')` — a missing item fails the render loudly (HD-65/76).

**Scoped consumer keys (v2, HD-247)** — Postgres-backed, models Admin-UI-managed; bootstrap glue mints
the per-consumer virtual keys (fail-closed lookups thereafter), specs SSOT in `group_vars/vps.yml`:
`owui-public-chat_api` (OWUI-public chat) · `owui-public-rag_api` (public RAG, embed+rerank) ·
`owui-int-wife_api` / `owui-int-owner_api` (internal) · `dsh_api` (DSH) · `openclaw-litellm_api`
(OpenClaw) · `rag-int-svc_api` (OWUI-internal RAG). Starting budgets/durations Admin-UI-editable.

> 📋 Deploy checklist: [`deployment-ai-stack-secrets.md`](deployment-ai-stack-secrets.md).

### 4a. Pinned-AI catalog rows — runbook (runtime DB; HD-391)

Model rows live in the LiteLLM **DB**, never in git (decision 13 / HD-247). They are created with
`POST /model/new` against **`lan-litellm`** on oldsrv using the master key — the vault item is **`litellm_api`
(field `credential`)**, which IS the master key (`LITELLM_MASTER_KEY` in both compose templates); there is no
item named `litellm_master_key`, despite how that name gets typed. Read it into a variable, never echo it.

✅ **EXECUTED 2026-09-19 against the live LAN instance.** Before: **one** row (`spark/qwen3.8-flash-next`).
After: `local-rerank`, `bge-m3-vk`, `local-stt` added, each answered **through** the gateway (§3a-2). Two things
this corrected: the embed provider (**`hosted_vllm/`, not `openai/`** — §3a-3 finding 3) and a premise this lane
carried in from its tasking: **there is no `ollama/bge-m3` catalog row anywhere.** Both gateway instances were
listed the same evening (`/model/info`) and **each returned exactly one row, `spark/qwen3.8-flash-next`** — so
“do not delete the `ollama/bge-m3` row” was satisfied trivially, and the fallback rung is the **Ollama service
plus its `bge-m3` model** (re-verified after the blob cleanup: dim 1024), not a gateway row. Giving a consumer
either rung is **HD-384** work.

Row ids are recorded because they are the handle for a later delete/replay: `local-rerank`
`08f7e525-6a7b-4258-b940-54e23433a47a` · `bge-m3-vk` `ac74a51f-ab6b-4eaa-a0c2-88cdb4ce40b6` · `local-stt`
`4a47bb86-39bc-412b-a46d-1a6a692a779d`.

```bash
# from the oldsrv shell (lan-litellm is on the same compose host, no publish needed)
K=$(op read 'op://Homelab-ansible/litellm_api/credential')   # the master key; never echo $K

# 1. RERANK — provider jina_ai/, literal api_base (HD-382: DB-stored litellm_params do NOT
#    expand os.environ/, they forward the literal and upstream 401s).
#    Verified in the pinned v1.83.10 image: jina_ai's get_complete_url REPLACES the path with
#    /v1/rerank, so api_base carries NO path — `http://reranker:9001`, not .../v1/rerank.
curl -s -H "Authorization: Bearer $K" -H content-type:application/json \
  -d '{"model_name":"local-rerank","litellm_params":{"model":"jina_ai/bge-reranker-v2-m3","api_base":"http://reranker:9001","api_key":"sk-none"}}' \
  http://localhost:4000/model/new

# 2. EMBED — llama.cpp serves OpenAI-shaped /v1/embeddings; here the api_base DOES carry /v1.
#    ⚠ provider = hosted_vllm/, NOT openai/: the openai provider forwards `encoding_format: null` and
#    llama.cpp answers 500 "type must be string, but is null" (leg healthy, gateway row broken — §3a-3).
#    Dimension stays 1024, so this is routing, not a corpus migration (no HD-268 re-index).
curl -s -H "Authorization: Bearer $K" -H content-type:application/json \
  -d '{"model_name":"bge-m3-vk","litellm_params":{"model":"hosted_vllm/bge-m3","api_base":"http://embed:9002/v1","api_key":"sk-none"}}' \
  http://localhost:4000/model/new

# 3. STT — whisper-server serves the OpenAI path natively (--inference-path), so no wrapper.
curl -s -H "Authorization: Bearer $K" -H content-type:application/json \
  -d '{"model_name":"local-stt","litellm_params":{"model":"openai/whisper-1","api_base":"http://whisper:9000/v1","api_key":"sk-none"}}' \
  http://localhost:4000/model/new
```

**Rules for this table:**
* **`lan-litellm` has no `curl`** — drive its API from the host against its `llm-backend` container address
  (`http://<the ip docker inspect gives for lan-litellm on llm-backend>:4000`) or from any container that ships
  a client. Deliberately not written down as a literal: bridge IPs are exactly what the no-hardcoded-IPs rule
  in §2 exists to keep out of docs, and this one moved once during the converge.
* **Admin endpoints, v1.83.10, measured:** `/model/list` is not usable with the master key (it answers a
  `{"detail": …}`), **`/model/info`** is the one that enumerates rows; and **`/model/delete` takes `{"id": …}`**,
  not `{"model_id": …}` (the latter is a 422 that says exactly which field it wanted — do not assume).
* **The Ollama fallback is a rung, not a row.** Owner call 2026-09-19: the Vulkan embed leg got its own row and
  Ollama stays as the documented fallback of the SAME 1024-dim space (cos 0.9996). Measured the same evening,
  **neither LiteLLM DB contains an `ollama/*` row**, so “keeping” it means keeping the service and the model —
  and re-pointing a consumer to either leg is HD-384. No consumer re-pointed here; these three rows are
  reachable on the admin path only.
* **`bootstrap_keys` stays `false`** (HD-386): none of these legs has a scoped consumer yet (the rerank
  consumer is the HD-268b stub), so no key-minting glue is restored here.
* **Two traps, both earned:** a `--check --diff` on a LiteLLM converge renders live keys into the log; and a
  green **scoped** converge (`-e docker_services_scope=…` with only `--tags docker_services`) SKIPS the named
  service and still prints `failed=0` — prove a deploy with `docker inspect` / the rendered file, never with
  the RECAP.
* Verify the two path compositions once, live, and record the result here if they differ: LiteLLM appends
  `/embeddings` and `/audio/transcriptions` to the `api_base` it is given, so the `/v1` suffix belongs on the
  embed and STT rows and must NOT appear on the rerank row. **Verified 2026-09-19 — that is exactly right:**
  jina_ai's `get_complete_url` discards any path and posts to `/v1/rerank`, while the embed/STT rows are
  reached at `<api_base>/embeddings` and `<api_base>/audio/transcriptions`.

---

## 5. Knowledge SSOT & RAG pipeline (HD-267)

### 5a. Knowledge SSOT = Forgejo OKF-llm-wiki (HD-267 ②)
- **Git is the source of truth** for `.md` knowledge. Private per-owner repos under Forgejo:
  `wiki-druzina` (family) · `wiki-osebno-moj` (owner-personal) · `wiki-sluzba-moj` (owner-work) ·
  `wiki-osebno-zena` (wife-personal) + a public KB cohort.
- **Every record = one `.md`** with OKF YAML front-matter: `title`, `type`, `tags`, `generated_at`.
- **`*-generated.md` are explicitly outside the corpus** (generated docs are never indexed as source).
- **OpenCloud remains the raw-asset ingress** (PDFs, scans, docs) — the *source* of documents, not the
  index SSOT. Large binaries are referenced, not embedded in the wiki.
- **The vector index / Qdrant is a rebuildable cache** over that git floor — it can always be rebuilt;
  it is never the source of truth.

### 5b. Retrieval RAG results (rebuildable cache)
1. **Ingest:** raw assets from **OpenCloud** (WebDAV/CIFS live Box) → optional **Docling** OCR →
   canonical `.md` lands in the Forgejo wiki repo (git front-matter).
2. **Index:** chunk → embed via **bge-m3 (1024 dims)** on spark (Triton) through LiteLLM → write dense+sparse
   vectors to **Qdrant**.
3. **Retrieve:** hybrid BM25+vector query → kapa-inspired-mcp reads Qdrant → top-20 candidates → **bge-reranker-v2-m3
   rerank** via LiteLLM → **top-5 clean markdown** context → LiteLLM model answers.

**Decided retrieval/ingestion parameters** (RAG knobs):
| Parameter | Decided value |
|-----------|---------------|
| Extraction | Docling only (`CONTENT_EXTRACTION_ENGINE=docling`, `DOCLING_SERVER_URL=http://docling:5001`) |
| Embeddings | **bge-m3, 1024 dims** via the **Vulkan `embed` leg on oldsrv** (LiteLLM `bge-m3-vk`, §4a) — Ollama `:rocm` stays the fallback rung; Cohere retired; “via Triton on spark” was the pre-#24/#27 framing |
| Reranker | bge-reranker-v2-m3 **Q8_0** local via LiteLLM `/rerank` → **`jina_ai/` → llama.cpp Vulkan cross-encoder on the RX 7600** (decision #27; #25's CPU CrossEncoder stack superseded by measurement). ⚠ its consumer `rag-mcp` is the HD-268b stub — leg ships dormant |
| Hybrid | ON default (dense+sparse BM25) |
| Retrieval | 20 candidates → rerank → top 5, threshold 0 |
| Chunking | token-based 512/64 (`RAG_TEXT_SPLITTER=token` mandatory) — **this is the number the GGUF legs size their context AND batch from**: `--ctx-size/--batch-size/--ubatch-size = 2048/2048/2048` (§3a-1), because the documented 512-token chunk plus its 64 overlap and special tokens must fit one ubatch pass — at the 512 default the endpoint answers a loud **HTTP 500** (measured; §3a-3 finding 1), it does NOT silently truncate on this path |
| Config ownership | `ENABLE_PERSISTENT_CONFIG=false` (env = SSOT) |
| Knowledge split | Public = Family-Manuals KB only; internal = personal/wife-work corpus |
| Vector index | Qdrant, **1024-dim** dense (+sparse), dimension locks at first ingest (1536→1024 free: nothing RAG'd yet) |

> **Dimension lock-in (HD-267 / ported from HD-246):** the vector dimension freezes at first ingest;
> changing embedding model/dims later = full re-ingest + backtest. **1024 chosen (bge-m3) — 2026-09-06**; 1536 Cohere superseded.

> **Backup (HD-307):** Qdrant is a **rebuildable cache** — so its backup policy is *relaxed* vs PGVector
> (PGVector held "irretrievable metadata"). The irrecoverable source is the **Forgejo OKF wiki** (the SS),
> so backup focuses on git + the raw-asset ingress; Qdrant is re-indexed from the wiki on loss. Still add a
> Qdrant snapshot seam for iteration speed, but it is NOT the metadata-fate risk class it was under
> PGVector. Open WebUI + OpenClaw config/state → Kopia.

> **Qdrant `read_only` snapshots gotcha (HD-271-followup, live 2026-08-28):** the compose sets
> `read_only: true` (container-hardening, HD-202), so qdrant 1.12.4 **cannot create its snapshots dir
> at startup in the RO rootfs** → panic `Can't create Snapshots directory: Read-only file system` at
> `toc/mod.rs:100` → crash-loop (`Restarting(101)`). Fix: point the snapshots dir INSIDE the writable
> storage bind via `QDRANT__STORAGE__SNAPSHOTS_PATH: /qdrant/storage/snapshots` (verified live: starts
> clean, `Up (healthy)`; dir auto-created on the bind). Keep `/snapshots` REST export + Kopia-backed
> host bind as the backup seam (backup.md): this env must stay in the compose template.

### 5c. Workflows (operational recipes)

The AI layer is a **swappable shell over a git-SSOT + vector-cache floor** — three canonical flows:

**A) Ingest a large document (automated, n8n):**
1. Drop a 300-page manual into an OpenCloud **“import to RAG”** folder.
2. **n8n** detects the file and copies it into the `/sources/` dir of the target wiki repo on Forgejo.
3. n8n (or a hook) chunks it, embeds via **LiteLLM** (ollama/bge-m3 on oldsrv RX 7600), and writes the **dense+sparse**
   vectors to Qdrant tagged with the project ID — ready for hybrid search immediately.

**B) Edit docs from the web (HITL, human-in-the-loop):**
1. Log into **Open WebUI** (WAN/Tailscale + Authentik), pick a **pi-agent** model.
2. Prompt eg. “*V @wiki-sluzba dodaj nov konfiguracijski port 9090 v indeks*”.
3. OWUI calls **pi serve** over the internal network.
4. The agent edits the `.md`, **lints the OKF header** (title/type/tags/generated_at), then opens a
   **Pull Request via Forgejo MCP** on your local Forgejo.
5. You later `git pull` on your WSL laptop, visually accept the PR and **deploy with Ansible** to prod VPS.

**C) Identity-aware orchestration (OWUI as orchestrator):**
- OWUI reads the Authentik JWT and **dynamically shows only the MCP tools + wikis the logged-in group is
  allowed** (e.g. `groups: ["admin", "sluzba"]` → role-filtered tools). Open WebUI is not a monolithic
  app but a router over the permissioned corpus. (Detail from the brainstorm — mechanism is a follow-up
  task under HD-307.)

**Elastic survival:** because knowledge is plain OKF `.md` in git and the index is a rebuildable Qdrant
cache, if Open WebUI goes away tomorrow the whole structure + hybrid RAG + coding agents keep working via
the WSL pi.dev terminal.

**D) Mem0 long-term memory (planned, spark — HD-335):** user-scoped memory for Open WebUI,
backed by **Qdrant** (HD-267/268). Per-user/per-project isolation via the OWUI identity split:

```python
user_id = body.get("user", {}).get("id")        # OWUI user id (Authentik identity)
model_id = body.get("model")                     # current Persona/Project (model) id
mem0_custom_user_id = f"{user_id}-{model_id}"     # per-user × per-project memory scope
mem0.search(query=user_prompt, user_id=mem0_custom_user_id)   # inject relevant context
```

- Scoping: each (user, model) pair gets its own memory namespace — no cross-user/project leakage.
- Store: Qdrant collection; rebuildable (same cache class as the RAG index under HD-267 ②).
- Full onboarding (compose/registry/edge) is tracked under HD-335.

---

## 6. Auth & exposure
- **`chat.kogler.si` is public** (renamed from `ai.` -- v2, HD-248), behind **Authentik OIDC** (native
  SSO, per-person) + **`crowdsec-only`** middleware at the Traefik edge (internet-facing → Flaw A /
  HD-60). Holds ONLY capability-limited credentials: family-chat + embed keys, no agents.
- **`ai.kogler.si` is the INTERNAL instance** (tailnet-served via Pattern-A sidecar; public DNS record
  dropped/repointed). You + wife; agent-capable keys; `rag_internal`.
- **Capability-tiering posture:** internet-facing = limited capability only; full power behind tailnet.
  New admin/UI surfaces default tailscale-first ([security.md](security.md) §Capability-tiering,
  [network-vpn.md](network-vpn.md) Patterns A/B).
- Per-person history follows the HD-51 identity model; no shared admin login.

## 7. Integrations
| Integration | How |
|-------------|-----|
| **Open WebUI ↔ OpenClaw** | Register OpenClaw as a LiteLLM model/provider → chatting to the “OpenClaw” model in the UI invokes the agent (**internal instance only; public keys exclude agents**). No bespoke glue. |
| **pi.dev / DSH ↔ the engine / Forgejo** *(dual)* | Per decision #26 the harnesses consume the **engine directly** (no LiteLLM hop) and propose via Forgejo PRs only (branch-protected main, no merge rights). The scoped LiteLLM keys for them are parked (HD-386). |
| **Qdrant ↔ rag-mcp ↔ OWUI** (HD-307) | kapa-mcp retrieves via Qdrant + bge-reranker-v2-m3 rerank (LiteLLM → **`jina_ai/` → llama.cpp Vulkan on the oldsrv RX 7600**, decision #27 — was “CPU reranker” under #25), returns top-5 markdown to OWUI. ⚠ `rag-mcp` itself is still the **HD-268b stub** (no `services:` block, `enabled: false`), so this integration has an author-side contract and no live caller |
| **Forgejo MCP ↔ wiki** | agents read/write OKF `.md`, open PRs; never arbitrary FS access |
| **OpenCloud ↔ RAG ingress** | raw assets (live Box WebDAV, read-only) → Docling → wiki (git floor) |
| **OpenClaw ↔ OpenCloud** | **WebDAV skill** reads/writes family files (summarize, organize, OCR a scan via Docling, draft replies). |
| **Open WebUI ↔ MS Office** | Office MCP bridges (Windows 11 clients) surface Word/Excel/PowerPoint as **tools** into OWUI over the Headscale tunnel — live COM edits; server-side python-docx/pptx/openpyxl path for Linux. See [`services-office.md`](services-office.md) (HD-106–111). |

## 8. Security & operating notes
- **No host port binds** (Flaw C / HD-62): overlays + Traefik only; loopback-only if ever needed.
- **Version pinning** (HD-61/71): pin LiteLLM, Open WebUI, Docling, **Qdrant**, OpenClaw (young project).
  Keep Renovate tracking.
- **VRAM/RAM:** spark = 128 GB unified (**big-model generation tier** — one large model, largest context, decision #24); oldsrv RX 7600 dGPU (8 GB) = **pinned AI services (Whisper STT ~2 GB + bge-m3 embed ~1–2 GB ≈ 3–4 GB; the bge-reranker moved to CPU — decision #25) + Sunshine gaming encode + immich-ML batch (lowest priority)**; Piper TTS = **CPU** (CPU-only engine); Docling on CPU; size chat models
  ~7–8B q4; keep `keep_alive` sensible (see `hardware-gpu.md`).
- **AnythingLLM + LocPilot removed** for the family web UI — replaced by MS Office MCP path (HD-108).

- **The legs are unauthenticated by design; the gateway is not** (decision #22). `whisper`/`reranker`/`embed`
  answer anyone reachable on `llm-backend` — the boundary is that network plus the absence of host ports. On
  2026-09-19 the gateway side was measured rather than assumed: `/v1/embeddings` on `lan-litellm` with a bogus
  bearer token → **401 `Invalid proxy server token passed`**, with no token → **401 `No api key passed in`**.
  So only the master key or a real virtual key spends the gateway, and `api_keys: []` in `ai-allow` does **not**
  mean “any key accepted”. What **HD-384** still owes is *scoping* (one key per consumer, per-key model routing
  and limits), not authentication that is missing — and until it lands, the only key in play is the admin-grade
  master key, which is why every HD-391 probe used it and none of them prove a scoped path.
- **Session-side secret-hygiene slip, 2026-09-19 (HD-391 close-out):** a diagnostic probe printed a **partial
  `LITELLM_MASTER_KEY` fragment** into a terminal transcript while resolving the vault item — separators masked,
  roughly half the characters visible. The key value never entered git and the vault item is unchanged; **whether
  to rotate it is the owner's call** (same class as **HD-233 / HD-234** — an admin-grade value reaching a
  human-facing surface that is not a secret store; rotation procedure lives there). The mechanical rule this
  teaches: a value read via `op read` is never printed, not even truncated to prove the read worked — print its
  **length** and pipe it straight into the consumer.
  **Owner decision 2026-09-19: the key is NOT rotated.** Recorded here as closed-by-decision so no later session
  re-raises it; if the key ever rotates for another reason, HD-233/234 carry the procedure and both LiteLLM
  instances plus every consumer move together.

## 9. Decision log
| # | Decision | Date |
|---|----------|------|
| 1–17 | (original v2 lock) — Cohere embed-v4 multilingual · `ai.`→public→internal · OpenClaw pinned · no host binds · single openrouter · LocPilot kept/AnythingLLM removed · OpenCloud file SSOT · Office MCP · Docling-only OCR · RAG stack locked (PGVector) · two-instance OWUI · capability-tiering · LiteLLM v2 spine · public=Family Manuals · n8n internal · DSH · embeddings uniform. | 2026-08-16 → 08-26 |
| **18** | **Vector store = Qdrant** (hybrid dense+sparse, standalone Rust) — **replaces PGVector**; re-opens HD-246 store. Independent of OWUI. | 2026-08-27 |
| **19** | **Forgejo OKF-llm-wiki = knowledge SSOT**; Qdrant = rebuildable cache; per-owner private repos; OKF YAML front-matter; `*-generated.md` outside corpus. | 2026-08-27 |
| **20** | **Dual harness pi.dev + DSH** (supersedes HD-250's "DSH replaces pi.dev"); feature-keyed bake-off; agents via MCP-git/wiki, never FS. | 2026-08-27 |
| **21** | IO/embedding stay cohere/embed-v4 @1536; public corpus = Family Manuals only; wife-work corp internal-only. | 2026-08-26/27 |
| **22** | **spark (ThinkStation PGX / GB10) replaces the old Phase-2 Ryzen/R9700 build (HD-42 superseded).** Headless Triton inference node + NVFP4 model set + local bge embeddings; **Mem0** (OWUI memory on Qdrant) + **OpenHands** (agentic coding) onboard on spark. HD-335. | 2026-09-06 |
| **23** | **Inference consolidated on spark — single local-inference tier (2026-09-06).** All generation/embeddings/rerank/STT/TTS run on spark (Triton, GB10). **No Ollama/AMD-noble ROCm on oldsrv** (ollama disabled 2026-09-07; amd_rocm role kept but Debian-native only, HD-318). oldsrv GPU = **Sunshine gaming encode first, with immich-ML as a pause-able GPU batch consumer** (already GPU-templated; Sunshine prep-commands `docker pause/unpause immich-ml` enforce gaming-first — no CPU fallback needed; CPU path reserved only if ONNX-GPU proves fragile). **Cohere subscription retired** — bge-m3 (1024) + bge-reranker-v2-m3 replace embed-v4/rerank (Qdrant 1536→1024 free: nothing RAG'd yet). Voice = whisper-turbo + XTTS/Piper **pinned resident on spark, no fallback**. | 2026-09-06 |
| **24** | **RX 7600 = pinned-services tier; spark = big-model generation tier (2026-09-15).** Reverses #23's "sole inference tier" for the *small pinned services*: **Whisper STT (~2 GB) + bge-m3 embed (~1–2 GB) + bge-reranker (~1–2 GB) move to the oldsrv RX 7600** (container-bundled ROCm, ≈5–6 GB of 8 GB, pause-able for gaming — same pattern as immich-ML). **Piper TTS stays CPU** (CPU-only engine, ~0.5 GB, instant). **spark (GB10, 128 GB unified) keeps the big-model generation tier** — one large model with the largest context (Qwen3-Coder-Next-80B, 262k ctx via SGLang). immich-ML stays on oldsrv GPU as **lowest priority** (paused when voice/embed active). Rationale: pinned services are small + latency-sensitive (voice); spark is a 128 GB monster that should do the heavy lifting, not babysit a 2 GB Whisper. Risk accepted: ROCm-on-RDNA3 container-bundled path (immich-ML precedent). | 2026-09-15 |
| **25** | **Pinned-AI service stack per leg (owner-approved 2026-09-17, research 2026-09-17).** Settles the three legs HD-369 left open, keeping the decision #24 placement (RX 7600 = pinned tier) unchanged: **(a) embed** — stays **Ollama `:rocm` `bge-m3`** (already E2E-verified: 1024-dim, 100 % GPU); TEI was investigated and rejected for this card (§9c). **(b) rerank** — **CPU cross-encoder**, owner call 2026-09-17: 568 M params, 20 pairs ≈ 10–30 ms/pair against a 300–800 ms LLM leg, so GPU residency buys nothing while costing 1.5 GB VRAM + a ROCm runtime; also removes the rerank leg from the RX 7600 VRAM budget entirely. **Ollama is NOT a rerank host** — no GGUF reranker path exists (§9c). **(c) STT** — **`whisper.cpp` built with `GGML_HIP` + native `AMDGPU_TARGETS=gfx1102`** (`.devops/main-rocm.Dockerfile`, ROCm 7.14/TheRock) instead of PyTorch `insanely-fast-whisper-rocm`, which needs `HSA_OVERRIDE_GFX_VERSION=10.3.0` (gfx1030 = ISA-adjacent JIT risk) and drags gradio/demucs/stable-ts + `seccomp=unconfined`/`SYS_PTRACE`/`ipc:host`/`shm 8G` — none of which the wake-word → STT → LLM → Piper pipeline needs. Native gfx1102 also removes the CWSR compute-preemption exposure (§9c + [hardware-gpu.md](hardware-gpu.md)). Consequence: **RX 7600 hosts 2 GPU legs (embed + STT), rerank is CPU** → pinned-AI VRAM ~3–4 GB, and immich-ML (3–5 GB) can co-reside instead of being paused. ⏳ **Open, non-blocking:** LiteLLM `/rerank` has no Ollama provider (`litellm/llms/ollama/rerank/transformation.py` → 404), so the CPU reranker must be exposed as an endpoint type LiteLLM *can* route (Jina `/v1/rerank` / `cohere` / `hosted_vllm` compat) — verify the provider before wiring (HD-385). | 2026-09-17 |

| **26** | **Consumption boundary: generation harnesses go DIRECT to the spark name edge; LiteLLM serves the simple-querier tier; external APIs are a harness-side fallback, never a proxy fallback (owner decision 2026-09-17).** Splits the consumer set explicitly: **(a) THROUGH LiteLLM** — the simple queriers (HomeAssistant, Docling, Open WebUI ×2, OpenClaw) + the pinned-AI legs (embed/STT/rerank, decision #25) + anything that must not hold an upstream credential: per-consumer scoped virtual keys, one dropdown, spend/latency records. **(b) DIRECT to `llm.kogler.si`** — the coding harnesses (workstation pi.dev, Continue.dev, future dedicated harness deploys). Three measured/engineered reasons, not taste: **(1) silent parameter loss.** pi's harness contract is a wire-format contract; the `openai/` provider's allow-list is `OpenAIGPTConfig.get_supported_openai_params` **plus `reasoning_effort` only** for an alias it does not recognize (`OpenAIUnknownModelConfig`, `litellm/llms/openai/chat/gpt_transformation.py`, read 2026-09-17) — `chat_template_kwargs` and `thinking_token_budget` appear in that provider tree only for `hosted_vllm`/`together`/`fireworks`/Bedrock, and `top_k` for none of them. With `drop_params: true` an unsupported key is **dropped without an error**, and for the thinking switch the failure mode is silent thinking-ON (the engine's default), i.e. a cost/quality regression that looks like success. Re-measurement is tracked as HD-387. **(2) retry/fallback amplification on one KV pool.** The pool is ONE shared budget with `max_num_seqs: 4`; incident #6 measured a 0 %-prefix-hit 162k-token re-prefill at 17,008 tok/s driving `MemAvailable` 21.5→12.6 GiB in 22 s — a router that retries/falls back on timeout does exactly that **automatically, under load**. **(3) topology.** Direct is 1 hop (`pi → traefik-spark → engine`); via the LAN instance it is 3 proxies + 2 extra TLS terminations, which makes the coding cockpit depend on oldsrv (which also hosts Kopia/arr/immich/whisper/embed) and re-bases pi's 900 s idle / 1800 s request budget onto two Traefiks and the proxy. **Fallback placement:** a proxy that swaps the model behind the client's back also invalidates the client's `contextWindow`/compaction math (§pi-harness.md §3) and its tool-call parser assumptions, so **fallback lives in the harness**, which knows the target's window. **Consequences:** `dsh` + `pi-dev` as docker_services entries are PARKED (`enabled: false`, HD-386 — they never became working consumers; both render a deliberately-EMPTY vault item); `litellm_scoped_keys` on the LAN instance is empty until the simple-querier tier registers (HD-384), which forces `bootstrap_keys: false` there (the glue fail-louds on an empty spec list); the workstation keeps `spark-llm_api` locally, so hardening that credential moves to the edge (spark `llm` router allow-list / a distinct client credential) rather than to a proxy — recorded as an open tail in HD-384. | 2026-09-17 |
| **27** | **ADOPTED — accepted 2026-09-18 by owner instruction (“write this to the SSOTs”); implemented and ADOPTED 2026-09-19 (HD-391 shipped and live-verified) — all three pinned-AI legs move to the ggml/Vulkan backend family on the RX 7600: STT `ghcr.io/ggml-org/whisper.cpp:main-vulkan` (digest-pinned, `large-v3-turbo`, GPU-first with native CPU fallback) · rerank `ghcr.io/ggml-org/llama.cpp:server-vulkan` + `gpustack/bge-reranker-v2-m3-GGUF` Q8_0 (routed as LiteLLM `jina_ai/`) · embed `llama.cpp:server-vulkan` + `ggml-org/bge-m3-Q8_0-GGUF` (Ollama `:rocm` demoted to the fallback rung).** **Quantization is settled by measurement — Q8_0 on both GGUF legs:** FP16 costs **+269 MiB/leg** and **+18 %** embed latency for one more nine of fidelity (cos 0.99996 vs 0.99960) and changes **no** rerank top-5 ([services-ai-bench.md](services-ai-bench.md) §3c). Re-decides **#25(c)** (GGML_HIP → Vulkan: the HIP recipe has **no published artifact**, so the only alternative is a self-build with no Renovate trail — §9c corrected 2026-09-18), **#25(b)** (CPU → dGPU: measured **0.50 s vs 5.3 s** for a top-20 rerank at **425 MiB** VRAM instead of the assumed 1.5 GB, and CPU rerank is 10–20× slower than #25(b)'s 10–30 ms/pair premise) and **#25(a)** (embed leaves Ollama even though it works: **15 ms vs ~500 ms** per query chunk, 2.3× ingest, **326 MiB vs 899 MiB** VRAM, 157 MiB vs 2.19 GiB host RSS, and **cosine 0.9996 / min 0.9986 against the live Ollama vectors** ⇒ the same vector space, so the move costs no correctness-driven re-embed — [services-ai-bench.md](services-ai-bench.md) §3b). **Plan-of-record table for the whole tier: §3a.** **Keeps #24's placement** (RX 7600 = pinned tier). Evidence: [services-ai-bench.md](services-ai-bench.md) §2–§7 (device sweep, TEI landmines, iGPU verdict, co-residency ledger: whole pinned tier = **2.9 GiB of 8 GiB**, 0 `amdgpu` hang/reset lines across ~25 min of Vulkan compute). Consequences to accept: **three** Vulkan clients share one card (measured contention factor ≈1.5–2× under simultaneous load, flat when sustained; the tier measures **~2.4 GiB of 8 GiB** once embed moves, and the AI tier then needs **no `/dev/kfd`/ROCm userspace at all**); `main-vulkan` + `server-vulkan` are **mutable aliases** ⇒ §7 MUST-pin by digest; the rerank + embed legs gain GGUF model-fetch tasks (sha256-verified) and rerank loses the `huggingface/`-provider wiring while embed re-points the LiteLLM rows off `ollama/bge-m3`; `--ctx-size` on the embed leg must cover the real ingest chunk (bge-m3 supports 8192; llama.cpp truncates silently beyond the window). **⚠ corrected at deploy (2026-09-19, [services-ai-bench.md](services-ai-bench.md) §3 / [services-ai.md](services-ai.md) §3a-3 finding 1): the binding limit on the embedding path is `--ubatch-size`, not `--ctx-size`, and an over-window input 500s loudly rather than truncating — the legs therefore run 2048/2048/2048.** | 2026-09-18 |
| **28** | **Vision-tier placement: vision runs on the workstation as a text cascade; spark is text-only; the RX 7600 gets no vision-LLM leg (2026-09-20).** Settles where multimodal lives in a homelab whose only large model is a text-only engine. **(a) spark = text-only** — `--limit-mm-per-prompt '{"image": 0, "video": 0}'` (≡ `--language-model-only`) is proposed as BENCHMARK-PLAN §6 step 11; it returns pool memory (ViT ~0.5–1 GiB + mm processor cache default **4 GiB host RAM**) but **buys no decode tok/s** — with no image tokens the tower never executes. Detail + gate: [`hardware-spark.md`](hardware-spark.md) §Text-only engine mode (HD-400). **(b) Token-level split inference is REJECTED as unbuildable** — the only pre-computed-vision seam vLLM offers is *multimodal embeddings*, which must live in the target model’s own visual-token space. Qwen3.8-Flash-Next = `Qwen4ExpForConditionalGeneration` (encoder 27L/hidden 1152 → its own merger → LM hidden 2560, interleaved mrope `[11,11,10]`); a Qwen3-VL encoder is trained against different geometry + a different LM ⇒ garbage-in-at-HTTP-200. Upstream also gates the embedding-input path behind the same `--limit-mm-per-prompt` limits. And image tokens cost **context**, not just encoder weights, so a transplanted embedding would still spend spark’s KV. **(c) Vision therefore runs as a cascade (vision → text) on the workstation** (Strix Halo, `Qwen3-VL-30B-A3B-Instruct` on the iGPU) for **visual judgment**, scoped by three load-bearing rules: describe-once-and-freeze by image-byte hash (keeps the prompt prefix warm — a 1280×800 screenshot ≈ 1–2.5k tokens), pass-through rewrite (NOT a proxy that can silently drop keys — the decision-#26 failure class), and loud rewrite counting. **FIM autocomplete is also local** (typing-time latency budget + a 7B-class FIM model does not fit the 7600’s 8 GiB + source stays on the laptop). **XDNA/NPU stays out of the AI tier** (no VL-encoder path; buys watts, not bandwidth; repack+driver pinning). Owning doc: [`hardware-workstation.md`](hardware-workstation.md) (HD-401). **(d) RX 7600 = no vision-LLM leg now** — the ledger is arithmetically closed: pinned 2.4 GiB + VL 2B/4B (3–4.5) + immich-ML (3–5) = **8.4–11.9 GiB > 8 GiB**, and `pause` does not free VRAM ([`hardware-gpu.md`](hardware-gpu.md)); revisit gates are written there (mmproj-on-Vulkan, `--sleep-idle-seconds` actually returning VRAM on `gfx1102`). Logged in [`services-rejected.md`](services-rejected.md). **Consequence to accept:** `image: 0` ⇒ an image part becomes a hard 400, which must be weighed in **HD-384** if Open WebUI ever joins the scoped-consumer set. Docling stays CPU/VPS and is **not** a consumer of any vision leg here (its accelerator set has no Vulkan/ROCm). | 2026-09-20 |

> **2026-09-15 live-verify guard (post-converge):** Ollama deployed on oldsrv (`:rocm` 0.32.15), **bge-m3 embed verified end-to-end** (real 1024-dim vector, model resident 100% GPU). **Two defects surfaced at first-boot against the authored plan** — (1) **model names**: `whisper-large-v3-turbo` + `bge-reranker-v2-m3` do **NOT exist** in the ollama library; corrected pulls are `sendmeaiohyeah/whisper-large-v2` (STT) + `qllama/bge-reranker-v2-m3:q8_0` (rerank) — update any LiteLLM Admin-UI entries to these names; (2) **API cap**: ollama `0.32.15` has **no `/api/rerank`** (404) and whisper cannot be serviced via the pinned build's chat path. ⚠️ **The follow-up sentence written here on 2026-09-15 — “rerank landed in ollama ≥ 0.5.x / blocked until the pin is bumped” — was WRONG and is corrected in §9c: no released ollama serves rerank.** Resolved instead by decision #25 (rerank → CPU, STT → `whisper.cpp` GGML_HIP); tracked in HD-385. **⚠ This note's instruction to “update any LiteLLM Admin-UI entries to these names” is itself superseded by decision #27: neither community model is pulled at all any more — rerank and STT are the `reranker`/`whisper` Vulkan containers (§3a) and their gateway rows are `local-rerank`/`local-stt`. Ollama holds `bge-m3` only, as the embed fallback rung. Kept as dated evidence of what the first boot actually found.
> The whole 3-zone / OKF / Qdrant / MCP architecture (previously `ai-brainstorming.md`) is **folded into
> this doc**; that file is **deleted** (HD-307 lifecycle).

## 9d. Consumption-boundary evidence (2026-09-17)

> **Role:** dated evidence appendix for decision #26 — what was READ, and what is still only INFERRED,
> so the "why not put the coding harnesses behind the gateway" question is not re-litigated from vibes.
> Primary sources read 2026-09-17 from the `BerriAI/litellm` tree (`main`), plus the live measurements
> already recorded in [pi-harness.md](pi-harness.md) §2 and [spark-incidents.md](spark-incidents.md).

### Why direct — the three legs of decision #26

| Leg | Evidence | Consequence |
|-----|----------|-------------|
| **Param allow-list** | `litellm/llms/openai/chat/gpt_transformation.py`: `OpenAIGPTConfig.get_supported_openai_params` base list carries `temperature`, `top_p`, `max_tokens`, `stream_options`, `tools`, … and **not** `top_k`, **not** `chat_template_kwargs`, **not** `thinking_token_budget`. `OpenAIUnknownModelConfig` (the class a proxy alias like `openai/spark/…` selects, `litellm/llms/openai/openai.py` `_gpt_config_for_model`) = that same list **+ `reasoning_effort` only**. Repo-wide grep: `chat_template_kwargs` is handled by `hosted_vllm`/`together`/`fireworks` only; `thinking_token_budget` by Bedrock only | A harness feature that is not on the list is **dropped silently** under `drop_params: true`. For the thinking switch the silent outcome is thinking **ON** (engine default, pi-harness.md §2) — a cost/latency regression that returns HTTP 200 |
| **Retry/fallback amplification** | [spark-incidents.md](spark-incidents.md) #6: one ~162k-token agent session, prefix hit **0 %** → 17,008 tok/s full-window re-prefill, `MemAvailable` 21.5 → 12.6 GiB in 22 s. Pool = ONE budget, `max_num_seqs: 4` ([hardware-spark.md](hardware-spark.md)) | A proxy that retries or falls back on timeout reproduces that spike **automatically under load**. Governance the gateway *can* offer (`rpm`/`tpm` per key) is admission control, not KV isolation |
| **Topology + client contract** | Direct = `pi → traefik-spark :443 → engine :8000` (1 proxy). Via the LAN instance = `→ traefik-internal(oldsrv) :443 → lan-litellm:4000 → traefik-spark :443 → engine` (3 proxies, 2 extra TLS terminations), and the cockpit inherits oldsrv availability. `pi` reads `contextWindow`/`reasoning`/`compat`/`samplingParams` from its **local** `models.json` ([pi docs, models.md](https://github.com/badlogic/pi-mono)) — it cannot consume LiteLLM `model_info` | The gateway saves **zero** client config for a harness while adding a serial dependency and a timeout chain under pi's 900 s idle / 1800 s request budget. What it *does* save (sampling, thinking switch) is exactly the part §9d row 1 says is lossy |

### ⚠ Contradiction to re-measure (this is HD-387, not a settled fact)

HD-382 recorded, from a live run: *"`chat_template_kwargs` thinking control survives `drop_params: true`
(measured `reasoning_tokens: 0`)"*. The table above says the `openai/` provider does **not** carry that
key on `main`. One of the two is wrong for the pinned image (`v1.83.10-stable` — **not** `main`, so the
source read above is not authoritative for it). Either the key rides a path this grep does not show
(`litellm_params` merge / `extra_body`), or `reasoning_tokens: 0` had another cause that day. **Until
HD-387 measures it on the pinned image, do not treat "thinking control works through the gateway" as
true**, and never let a harness depend on it. The probe protocol is written into `todo.md` HD-387.

## 9c. Pinned-AI stack research record (2026-09-17)

> **Role:** dated evidence appendix for decision #25 — primary-source citations only, so a future
> session does not re-litigate a settled question. Verdicts live in §9 row 25; this section is the proof.

All findings below were read from primary sources (repo files / upstream trackers) on **2026-09-17**,
not from search-engine summaries.

### Corrected prior record

| Item | Was recorded | Verified 2026-09-17 |
|------|--------------|---------------------|
| HD-369 defect cause | “no `/api/rerank` in 0.32.15; **rerank landed in ollama ≥ 0.5.x**” → plan was to **bump the `:rocm` pin** | **Wrong — bumping will never fix it.** `git clone --branch v0.34.1` (latest stable, 2026-09-14) + `grep -ri rerank` over the whole tree = **0 hits**; `server/routes` exposes `/api/embed`, `/api/chat`, `/api/generate` — **no `/api/rerank`**; 40 most recent release bodies mention rerank **0 times**; PR **#11389** and **#7219** both **closed, not merged**; issue **#3368 “Reranking models” still open (113 comments)**. `0.34.1-rocm` and `rocm` tags do exist on Docker Hub — bumping is fine for other reasons, **not** for rerank. |
| Ollama GGUF reranker | assumed loadable | **No such path.** Nothing consumes a reranker architecture in the codebase (row above). |
| “Adapter computes rerank from `/api/embed`” | proposed upstream as elegant | **Mathematically impossible for a cross-encoder.** `bge-reranker-v2-m3` scores `MLP([CLS] q [SEP] p [SEP])` — joint query+passage attention through all 12 layers. Two independent embeddings cannot be recombined into that score; the result is a recomputed cosine similarity ≈ the dense retrieval the system already performs, behind an extra network hop. Silent quality loss, no error. |

### Rerank — CPU decision evidence (decision #25b)

| Source | Finding |
|--------|---------|
| `ollama/ollama` @ `v0.34.1` tree + `server/routes*.go` | no rerank route / no rerank model type (see above) |
| `huggingface/text-embeddings-inference` `README.md:109-112` | TEI does serve `/rerank` (XLM-RoBERTa / GTE / ModernBERT families) — but not on this card (next table) |
| `litellm/llms/ollama/rerank/transformation.py` | **HTTP 404** — LiteLLM has **no Ollama rerank provider**, so an Ollama-hosted reranker would be unroutable even if ollama served it. The CPU service must therefore expose an endpoint type LiteLLM *does* route. ⚠️ Which provider (Jina `/v1/rerank`, Cohere, `hosted_vllm`) is **still unverified** — HD-385 |
| `Theroxenes/local-reranker-rocm` (fork of `olafgeibig/local-reranker`) | ready-made FastAPI **`/v1/rerank`** (Jina-compatible) over `sentence-transformers` CrossEncoder, py3.12, “CPU or GPU depending on model”. Reusable **CPU mode only** — do not take its ROCm path. ⏳ Not yet vetted: license, maintenance activity. |
| ONNX Runtime ROCm / MIGraphX EP (AMD docs) | supported targets are **Instinct only** (`gfx942`, `gfx950`). The “CPU fallback only if ONNX-**GPU** proves fragile” note in §5 is a **dead branch on this card** — there is no ONNX-GPU on RDNA3 to be fragile. |

### Rerank — ⚠ measured revision of the CPU premise (2026-09-18, [services-ai-bench.md](services-ai-bench.md) §3)

The paper arithmetic behind #25(b) — “20 pairs ≈ 10–30 ms/pair against a 300–800 ms LLM leg, so GPU residency
buys nothing while costing 1.5 GB VRAM” — **does not survive contact with the hardware.** Measured on oldsrv
with the same `bge-reranker-v2-m3` weights, real Slovenian chunks, `top_n: 5`:

| Path | 5 docs × 100 w | 10 docs | **20 docs** | Memory | Host cost |
|------|----------------|---------|-------------|--------|-----------|
| `llama.cpp server-vulkan` → **RX 7600** | 0.14 s | 0.27 s | **0.50 s** | **425 MiB VRAM** | ~0 % CPU |
| TEI `cpu-1.9.4` ORT INT8 | 1.1 s | 2.6 s | **5.3 s** | 2.66 GiB RSS | **~790 % CPU** |
| `llama.cpp` CPU (Q8_0) | — | 3.9 s | 8.0 s | 158 MiB | load 1.7 |
| `llama.cpp` Vulkan → **HD 630 iGPU** | 5.8 s | 11.4 s | 22.8 s | 798 MiB host RAM | (also contends with Xorg + Jellyfin QSV) |

Measured slope ≈ **260 ms per 100-word chunk on all 8 cores** (AVX2 only — INT8 buys **1.8×**, not 4×, because
Kaby Lake has no VNNI), i.e. **10–20× worse** than the 10–30 ms/pair assumption; and the GPU path costs
**0.42 GB**, not 1.5 GB, and needs **no ROCm runtime** (Vulkan/RADV). The iGPU is measurably slower than the
CPU and driver-frozen ([services-ai-bench.md](services-ai-bench.md) §4). Also corrected here: **“no GGUF reranker
path exists”** is true of **Ollama** (verified, unchanged) but not of `llama.cpp`, which ships the endpoint
(`--embedding --pooling rank --rerank` → `POST /v1/rerank` → `{results:[{index, relevance_score}]}`) and whose
GGUF source `gpustack/bge-reranker-v2-m3-GGUF` (Apache-2.0) matches LiteLLM's `jina_ai/` provider exactly.
⇒ **decision #27** (§9 row 27, **ACCEPTED 2026-09-18**; implementation HD-391; plan-of-record table §3a) moves rerank back to the dGPU on Vulkan.

### Embed — TEI on RDNA3 rejected (decision #25a)

The `todo.md` HD-369 claim “TEI ROCm targets Instinct MI200/MI300, not RDNA3” is **confirmed correct**, now with citations:

| Source | Finding |
|--------|---------|
| `docs/source/en/amd_gpu.md` + HF `/docs/text-embeddings-inference/amd_gpu` | “supports AMD Instinct GPUs (**MI200, MI300 series**); ROCm support is **experimental**. Only AMD Instinct GPUs are tested.” |
| `.github/workflows/matrix.json` | single ROCm entry: **`rocm-gfx942-gfx950`** (`imageNamePrefix: rocm-`, `runOn: always`) → the public image is `ghcr.io/huggingface/text-embeddings-inference:rocm-*` |
| `Dockerfile-rocm:60` | base `rocm/pytorch:rocm7.2.2_ubuntu22.04_py3.10_pytorch_release_2.10.0` |
| `Dockerfile-rocm:75-77` | “The wheel is built for **gfx942** (MI300X/MI300A) and **gfx950** (MI350)” — hard-coded `flash_attn` wheel from AMD’s `gfx942-gfx950` index |
| `grep -rniE 'gfx11\|gfx12\|rdna'` whole repo | **0 hits** — no RDNA target anywhere in the build |
| PR **#295 “ROCm support”** | **closed, never merged**; issue **#108 “Support TEI on AMD GPUs”** still **open** (9 comments) |

Running TEI on gfx1102 would mean a **self-built** container: the 7-step DIY recipe from `amd_gpu.md`
rustup → `pip install --no-deps -r backends/python/server/requirements-amd.txt` → hand-generated
protobuf stubs → `cargo build --release --features python,http` — with flash-attn dropped (PyTorch
`sdpa` fallback). That is build debt to reach parity with a leg that is **already live and verified**
on Ollama → **no change**. Also note `requirements-amd.txt` pins `transformers==4.51.3` / `numpy==1.26.4`:
old enough to conflict with anything else sharing that image.

### STT — `whisper.cpp` GGML_HIP chosen over `insanely-fast-whisper-rocm` (decision #25c)

| Source | Finding |
|--------|---------|
| `ggml-org/whisper.cpp` `.devops/main-rocm.Dockerfile` + `.github/workflows/docker.yml` | **⚠ CORRECTED 2026-09-18 (measured, [services-ai-bench.md](services-ai-bench.md) §7):** the *recipe* exists but **the artifact does not**. The row below was true about the Dockerfile only — the **docker CI matrix publishes no ROCm entry at all**: `ghcr.io/ggml-org/whisper.cpp` tags are `main`, `main-musa`, `main-intel`, `main-cuda`, `main-vulkan`, `main-arm64`, `main-vulkan-arm64`, and Docker Hub `ggmlorg/whisper.cpp` → **404**. Reaching gfx1102 therefore means **self-building** = a new build-task pattern with no Renovate digest trail, which is why the STT engine moved to **`main-vulkan`** (HD-391). The Dockerfile facts stand for the record: builds **ROCm 7.14 / TheRock** (`repo.amd.com/rocm/packages-multi-arch/rhel10`) and installs **`amdrocm-blas7.14-gfx1102`** |
| same file, build stage | `make base.en CMAKE_ARGS="-DGGML_HIP=1 -DAMDGPU_TARGETS=\"gfx1100;gfx1101;**gfx1102**;gfx1103;gfx1150;gfx1151;gfx1152;gfx1200;gfx1201\""` → **native gfx1102, no `HSA_OVERRIDE_GFX_VERSION` needed**. Caveat: the published recipe builds the **`base.en`** model target; `large-v3-turbo` needs a local build, and models come from `whisper.cpp/models` GGML URLs (not HF) → a download step is missing from IaC. |
| `insanely-fast-whisper-rocm` `Dockerfile:2,10,11` | `FROM python:3.10-slim`, `ROCM_PATH=/opt/rocm`, **`HSA_OVERRIDE_GFX_VERSION=10.3.0`** → runs **gfx1030 (RDNA2) code on an RDNA3 card**: works, but ISA-adjacent JIT risk (their documented success reports are gfx1030/gfx1032, **not** gfx1102). |
| same, `requirements-rocm-v7-0.txt` | `torch 2.8.0+rocm7.0.0`, `transformers 4.57.3`, **plus** `gradio 6.7`, `demucs 4.0.1`, `stable-ts 2.19.1`, `datasets`, `optimum`, `onnxruntime-rocm 1.22.1` — a subtitle-production dependency set, not a voice-assistant one. Wheels from `rocm-rel-6.4.1` / `rocm-rel-7.0` manylinux (older userspace than TheRock). |
| same, `docker-compose.yaml` | needs `ipc: host`, `shm_size: 8G`, `cap_add: SYS_PTRACE`, **`security_opt: seccomp=unconfined`** → conflicts with this repo’s container hardening posture; whisper.cpp needs only `/dev/dri` + `/dev/kfd` (already covered by the `amd_rocm` udev rules). |
| same, `.env.example` | default `distil-whisper/distil-large-v3.5`, `float16`, `USE_READABLE_SUBTITLES=true`, SRT CPS constraints (`MAX_CPS=17.0`) — subtitle features the [wake word → STT → LLM → Piper] pipeline in [smart-home-voice.md](smart-home-voice.md) does not use. |
| `whisper.cpp/examples/server/server.cpp:62,175` | the bundled server is **not OpenAI-shaped by default**: `POST {prefix}/inference`, `multipart/form-data` WAV, plus `/load` and `/health`. **⚠ CORRECTED 2026-09-18 by measurement ([services-ai-bench.md](services-ai-bench.md) §2): no wrapper is needed** — `--inference-path /v1/audio/transcriptions` relocates the route (`POST /v1/audio/transcriptions` → `200 {"text":…}`, `/inference` → 404, `/health` stays at root) and the extra OpenAI multipart fields (`model`, `language`, `response_format`) are accepted. HA Assist is satisfied by the flag alone. |

**Why it matters here:** RSS per GPU runtime. Each ROCm/PyTorch process holds its own rocBLAS /
hipBLASLt / MIOpen workspace (~0.5–1.5 GB host RSS); whisper.cpp is a C++ binary at roughly
200–400 MB. With four ROCm containers the binding constraint on a 48 GB oldsrv is **host RAM, not
8 GB VRAM** — which is the actual argument for two GPU legs (embed + STT) plus a CPU reranker.

## 9b. Coding plane — agent memory + orchestration (HD-336, 2026-09-06)

The **coding plane** (your dev work: IaC/Ansible, C#, React/Vue, homelab epics) is a **separate
plane from the family research plane** (OWUI/Docling/Qdrant/Mem0). It runs on **oldsrv**
(managed from the laptop), not the laptop itself.

### Memory — agent-memory.dev (per-project)

- **Decision (2026-09-06): agent-memory.dev = the coding-memory plane**; OpenViking deferred
  (AGPL-accepted, Docker-only, future unified-context candidate); Mem0 stays OWUI-plane.
- **One instance per project** (project = 1+ repos); records tagged project+repo.
- **Cross-project recall = opt-in, not default** (one-instance scoped; no collision).
- Runs on **oldsrv** (where coding agents live); data dirs under `~/.agentmemory/<project>`,
  ports 3111+N; MCP = `@agentmemory/mcp`; consolidation LLM key → **LiteLLM scoped key**.
- **Skills = git SSOT** (`skills/` + `sync-skills.sh`, HD-254), never a service.

### Runners / automation

- **ZeroClaw = system-management agent** (laptop primary + oldsrv standby; NOT VPS — too risky;
  oldsrv does NOT self-provision). Supervised approvals; MCP → agentmemory.
- **CrewAI = long/epic homelab coding orchestration with human-signaling** (every decision point
  = a mandatory stop). **Pilot starts only when the homelab is fully finished** (kill criteria:
  2-week vertical slice or abandon).
- OpenHands commits to **spark** (HD-335).

### VPS runner: rejected

A ZeroClaw agent on the VPS with fleet credentials = the largest attack-surface increase in the
homelab (contradicts §10 capability-tiering). Rejected 2026-09-06; oldsrv is the remote runner.
## 10. Not yet implemented
Depends on: oldsrv GPU + Ollama live · LiteLLM spine + `openrouter_api`/`litellm_api`
in 1Password · Authentik OIDC for OWUI · OpenCloud + `media` owner (HD-51) · **Qdrant service + `qdrant_db`
item (replacing PGVector)** · **Forge OKF wiki repos + Forgejo/pi MCP** · **dual harness bring-up**.
Implementation tasks: **HD-307** (doc + tails) / **HD-268** (IaC: Qdrant swap + OKF repos + dual harness) — see the repo [`todo.md`](../todo.md) backlog.