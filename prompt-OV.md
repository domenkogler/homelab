# `prompt-OV.md` — Probe brief · OpenViking vs the decided RAG + memory floor (no HD row; measurement only)

> **Role:** self-sufficient lane brief. It carries **all** context needed to run the probes and report, so
> **read this file and nothing else** (the Step-0 ritual of [README.md](README.md) §0 still applies:
> `git status` + a fresh session worktree before any write). It registers **no new `HD-XX` row** and opens
> **no todo.md work item** — this lane produces a *measurement report* that the owner uses to decide the
> architecture. Do not implement, do not deploy permanently, do not decide.
> **Linked from:** owner's direct request (2026-09-21). It is deliberately **not** listed in `prompt.md` §2
> yet — it is a probe, not a build lane; add the line only when the owner accepts the outcome.
> **Hard constraint (owner's, 2026-09-21): 100 % local.** spark + the oldsrv dGPU legs only. **No paid or
> external endpoint anywhere in this lane** — no OpenRouter, no Volcengine/Doubao, no hosted API. If a
> measurement genuinely cannot be made locally, **stop and ask**; do not spend, do not substitute.
> **Excluded from validators by design:** `check_doc_map.py`, `check_doc_ips.py`, `check_placeholders.py`
> all skip root `prompt-*` handoffs, so this file may name hosts and paths freely.

---

## 0. What to do, in one paragraph

Stand up **OpenViking (OV)** ephemerally on oldsrv as a *venv process under the `domen` seat* (never a
container — see §7.4), point its embedding / VLM / rerank slots at the **already-live local** AI legs, import
a deliberately adversarial 40–60-file slice of this repo, and answer four measured questions: **does OV store
my Markdown faithfully (P1)**, **does its retrieval beat `grep`+read on the same corpus (P2)**, **does spark
write L0/L1 summaries good enough to be a retrieval key, and does thinking-mode or the LLM help at all
(P3, local arms only)**, and **what does a corpus compile cost in tokens and wall-clock (P4)**. Then report
in the format of §9. Budget: **P1+P2 ≈ 3–4 h; all four ≈ 6–7 h.**

---

## 1. The decision this feeds (and what it must NOT decide)

The owner has accepted **lock-in as acceptable** (see §6.3 exit analysis) but wants the number before the
architecture. Two open questions hang on this report:

| ID | Question | Owner decides after this report |
|----|----------|--------------------------------|
| **OQ-10** | Corpus index: **build** (`rag-mcp` + Qdrant, HD-268b) or **adopt** (OV as the knowledge store)? | yes |
| **OQ-11** | If OV: does it take **memory only**, or **memory + corpus**, i.e. how much of `services-ai.md` §5b survives as written? | yes |

Out of scope for this lane: the harness bake-off (pi.dev / OpenClaw / Hermes / OpenHands on oldsrv), placement
of Qdrant/reader (VPS vs oldsrv), `HD-384` scoped-key design, first-ingest scope, and the
`HD-407`/`HD-409` ordering. Those are separate owner calls. **Do not start any of them.**

---

## 2. Ground truth of what is already live (verified 2026-09-21; re-verify only what you doubt)

**Two planes, decided.** *Family/research* = VPS: one Open WebUI (`ai.kogler.si`, Authentik OIDC), VPS
LiteLLM (Postgres, models-in-DB), Qdrant (`db-internal`), Docling, OpenClaw. *Dev/coding* = oldsrv + spark:
`lan-litellm` (`llitellm.kogler.si`) + its own Postgres, the pinned-AI tier on the RX 7600, and the harnesses
which reach the engine **directly** at `https://llm.kogler.si/v1` (**decision #26** — a gateway cannot
transmit client-side semantics, and a proxy fallback reproduces the incident-#6 memory spike).

| Piece | Live state (all measured on this box) |
|---|---|
| Generation | **spark** vLLM, `spark/qwen3.8-flash-next`, `--max-model-len 262144`, `spark_vllm_max_num_seqs: 4`, KV pool `spark_vllm_kv_cache_memory: 16000000000` = **515 786 tokens ≈ 1.97×** one full 262k session; certified worst case 2×240k ≈ **94.6 %** of pool; decode **~11 tok/s**; cold TTFT @250k recorded **~13 min**; `tool-call EMPTY` fix and the **262k needle test are still open** |
| oldsrv | i7-7700K **4C/8T**, **48 GB**, RX 7600 8 GB; already hosts the whole `docker_services` set; `docker_services --check` is **currently broken (HD-399)** — do not interpret that as your failure |
| Pinned-AI tier (`llm-backend`, **no published ports**, only LiteLLM may reach it) | `embed` :9002 llama.cpp Vulkan `bge-m3` **Q8_0**, **dim 1024**, ‖v‖=1.0, **15 ms/chunk**, ~326 MiB → LiteLLM row **`bge-m3-vk`** (`hosted_vllm/…`, api_base **carries** `/v1`); `reranker` :9001 `bge-reranker-v2-m3` Q8_0, **0.34–0.50 s / 20 docs**, ~327 MiB → row **`local-rerank`** (`jina_ai/…`, api_base **carries NO path**); `whisper` :9000 large-v3-turbo, 1788 MiB → row **`local-stt`**. Tier total **2475 MiB of 8 GiB**, **0 `amdgpu` hang/reset** |
| Qdrant | VPS, hybrid dense+sparse, **dim 1024 locks at first ingest**, `QDRANT__STORAGE__SNAPSHOTS_PATH` must stay inside the writable bind (read-only rootfs crash) |
| **The corpus** | **nothing has been RAG'd yet** — OKF wiki skeletons uncreated (HD-268a); the reranker **ships dormant (~327 MiB)** because its consumer does not exist |
| **`rag-mcp` (HD-268b)** | **a stub.** `IaC/ansible/templates/docker_services/rag-mcp/docker-compose.yml.j2` is a TODO comment block with **no `services:` section**; `enabled: false` in `group_vars/vps.yml` is **not** a flag to flip (flipping fails `docker compose config`) |
| OpenClaw | container Up, **never onboarded** (HD-104); its scoped key still names dead `ollama/*` models |
| Mem0 / agent-memory.dev / OpenHands | planned, **none onboarded** (HD-335 / HD-336) |

**Decided retrieval parameters (`services-ai.md` §5b — the thing OQ-11 may rewrite):** extraction Docling only
(`CONTENT_EXTRACTION_ENGINE=docling`, `DOCLING_SERVER_URL=http://docling:5001`); embed **bge-m3 1024**; rerank
bge-reranker-v2-m3 via LiteLLM `jina_ai/`; **hybrid ON**; **20 candidates → rerank → top 5, threshold 0**;
chunk **token 512 / 64 overlap**; `ENABLE_PERSISTENT_CONFIG=false`; generated `*-generated.md` are **outside
the corpus**.

**Decided memory:** family/OWUI plane = **Mem0** over Qdrant, `user_id = "<owui_user_id>-<model_id>"`; dev
plane = **agent-memory.dev per project**, skills stay git SSOT, **OpenViking was written once as "deferred"
and has NO row in any `*-rejected.md`** → it was never triaged (CONVENTIONS §8.3). That is a governance hole
this probe closes with evidence, whichever way it lands.

**Capacity constraints that shape every number you measure:** one KV pool at **1.97×** a full session,
**~11 tok/s** decode, and an oldsrv box that is 4 cores with the family stack on it. Standing rules: **never
bench or converge spark from a session whose own model is spark**; live converges run detached;
`--check` is the only safe foreground form.

---

## 3. What OpenViking actually is (verified from the source tree + docs, 2026-09-21)

`volcengine/OpenViking` — ByteDance/Volcengine, **AGPL-3.0** (confirmed in `LICENSE`), Python 3.10+ with Rust
crates, image `ghcr.io/volcengine/openviking:latest`, `pip install openviking`, own storage engine (vendored
leveldb + its own vector index, `VikingFS`, `viking://` URIs), server on **:1933** with API keys, Caddy
ingress, snapshot/encryption/telemetry guides.

A **context database**, not only a memory: one virtual filesystem holding **knowledge + memory + skills**,
browsed with `ls / tree / read / grep / find`. Three load tiers — **L0 abstract → L1 overview → L2 full** —
so an agent judges relevance before reading (a *token* feature on this box). Sessions commit to Markdown;
`ov add-resource <git-url>` ingests a repository; `ov compile` builds a wiki / knowledge graph.

### 3.1 Model slots (all three take `api_base` ⇒ OV can run entirely on our stack)

| Slot | Providers | Notes |
|---|---|---|
| **embedding** | `openai · azure · volcengine · vikingdb · jina · ollama · gemini · voyage · dashscope · minimax · cohere · `**`litellm`**` · local` | explicit **`dimension`** key (their examples use **1024**); circuit breaker for transient provider failures (`max_retries`, `reset_timeout`) |
| **vlm** | `volcengine · openai · openai-codex · kimi · glm`, multi-provider with failover, LiteLLM passthrough | drives L0/L1, session-commit extraction, `ov compile`, optional per-query expansion/compression |
| **rerank** | `vikingdb · cohere · openai · `**`litellm`** | `openviking_cli/utils/config/rerank_config.py`; defaults `model_name: doubao-seed-rerank`, `model_version: 251028`, **`threshold: 0.1`** (ours is 0), `max_input_tokens: 0`, `timeout: 30.0` |

⚠ **Two claims from earlier drafts were wrong and are corrected here:** (1) OV **does** have a reranker, so
**our `local-rerank` leg keeps a consumer** if OV is adopted; (2) most of §5b survives adoption because
embed/rerank/threshold/token caps are *config*, not internals. What genuinely changes under adoption:
`threshold` default **0.1 vs our 0**, and **sparse** — OV treats sparse as a *provider capability*, and our
`bge-m3-vk` emits **dense only**, so "hybrid" would degrade to dense + directory-scoped search unless we
extend the embed leg. **Verify both in P1/P2 rather than trusting this line.**

### 3.2 OV's actual default models, and whether they beat ours (the owner's question, answered)

There is **no bundled weight**: `openviking-server init` prompts. But the shipped *defaults per slot* are in
the config classes, and they are answerable exactly:

| Slot | OV's default | What it is | Better fit than ours? |
|---|---|---|---|
| embedding | `provider: "volcengine"` (`embedding_config.py:70`), `input: "multimodal"` (default!), openai dim table ada-002/3-small **1536**, 3-large **3072** | cloud **Doubao-embedding** (multimodal) at `ark.cn-beijing…` | **No.** Cloud + CN egress + a multimodal embedder we cannot serve (decision #28 makes the box text-only) |
| embedding, *local* variant | **`DEFAULT_LOCAL_DENSE_MODEL = "bge-small-zh-v1.5-f16"`** (`local_embedders.py:22`), GGUF fetched from HF into `~/.cache/openviking/models`, query instruction **`为这个句子生成表示以用于检索相关文章：`** | a **small, Chinese-tuned BGE** — their zero-config self-host fallback | **No — strictly worse for us.** bge-small-zh is a 512-dim Chinese retrieval model; ours is **`bge-m3` Q8_0 @ 1024**, live, unit-verified (‖v‖=1.0) and cross-engine certified (cos 0.9996 vs vLLM). Switching = re-index + a worse encoder for an EN/SV technical corpus. **Pin the model explicitly; never let it fall back to `local`** |
| vlm | default `provider: "volcengine"`; the docs' **local** recipe is `provider: "litellm"`, `model: "ollama/llama3.1"`, `api_base: http://127.0.0.1:11434`, `extra_request_body: {think: false}` | home turf = a frontier hosted **multimodal** model (the LoCoMo run used **Doubao 2.0 Pro**); documented local path = a mid-size OSS model | **Unknown — this is the only slot worth measuring.** Nothing in OV requires frontier quality (they document a plain `llama3.1`), and vision is *optional*: `media.enabled` **defaults to `False`**, and image/table understanding (`openviking/parse/vlm.py`, `get_vision_completion`) is gated on `vlm.is_available()` + capability checks ⇒ **a text-only VLM is a supported configuration**, which is decision #28-compatible. Our binding constraint is **throughput/contention (11 tok/s, 1.97× KV)**, not model class → P3 measures spark against local baselines, not against a paid model |
| rerank | `provider: "vikingdb"`, **`model_name: "doubao-seed-rerank"`, `model_version: "251028"`**, `threshold 0.1`, `max_input_tokens 0` (no cap), `timeout 30` | a **cloud rerank API**; no open-weight equivalent ships | **No.** Our **`bge-reranker-v2-m3`** on the dGPU is *exactly* what the `openai`/`litellm` rerank provider path expects — the local standard. Nothing to gain, and it is currently idle anyway |

**Net answer:** on **two of three slots OV's defaults are strictly worse for this box** (cloud CN endpoints; the
local embedder fallback is a weaker Chinese small-model), and on the third (VLM) their default is a frontier
hosted model we are not buying — their own docs run the slot on an ordinary local model. So the probe runs
**our** models, and the only open question is whether spark's summaries are good enough, which P3 measures
locally and free.

**Why its published benchmark is not ours:** the numbers
(**LoCoMo: OpenClaw 24.20 %→82.08 %, Hermes 33.38 %→82.86 %, Claude Code 57.21 %→80.32 %; tokens −34…91 %;
tau2-bench +6.87/+11.87 pp**) was run with **Doubao 2.0 Pro as VLM + `doubao-embedding-vision`** — a
frontier hosted model and a **multimodal** embedder. Our engine is **text-only by decision #28**, so
**those numbers are not reproducible here and are not evidence.** P3 exists to replace them with ours.

### 3.3 Integration surface (why it is a serious multi-harness candidate)

| Consumer | OV surface |
|---|---|
| **pi.dev** | **native pi extension** — its docs state plainly *"pi does not support MCP"*; auto-recall before every prompt, per-turn capture, native tools `viking_search / viking_read / viking_browse / viking_remember / viking_forget / viking_add_resource / viking_archive_expand`, `/viking` command, footer status, and **"context takeover"**: it replaces committed history with an archive overview in pi's `context` hook, using a branch watermark for `pi -c`; knobs `recallTokenBudget`, `profileTokenBudget`, `resumeContextBudget`, `commitTokenThreshold`; installs into `~/.pi/agent/extensions/openviking` (an auto-discovery root — `pi install` on the same path double-loads) |
| **Hermes** | **built-in memory provider** (no plugin): `memory.provider: openviking`, `OPENVIKING_ENDPOINT/_API_KEY/_ACCOUNT/_USER/_AGENT`; talks HTTP, so OV need not live in Hermes' venv; **only one external memory provider may be active at a time**, and Hermes' own `MEMORY.md`/`USER.md` are always on |
| **OpenClaw** | context-engine plugin |
| **OpenHands / any MCP client** | built-in **`/mcp`** endpoint + an Agent Plugins 1.0 package |
| Also | Claude Code, Codex, Cursor, TRAE, OpenCode, **DSH**, LangChain/LangGraph, SDKs (Python/Go/TS) |

Latency knobs (per-query model calls): `OPENVIKING_RECALL_QUERY_EXPANSION=off`,
`OPENVIKING_RECALL_COMPRESS=off`.

### 3.4 Egress / exit facts

**OVPack** (`docs/en/guides/09-ovpack.md`) is the documented export/import format: file content, semantic
sidecars, portable index scalar fields and **optional dense vector snapshots**; `export/import` covers
`viking://resources/...` and `viking://user/...`; **`backup/restore`** packages whole scope roots incl.
`user/{id}/sessions/...` and requires **ROOT/ADMIN**. ⚠ **Exports are plaintext ZIP even when storage
encryption is enabled** — possession of the `.ovpack` is possession of the content.

---

## 4. The other candidates, so the report can compare without re-research

| | Fact (verified) |
|---|---|
| **agentmemory** (agent-memory.dev, dev-plane memory decision HD-336) | *"It is not a vector database. There is no Qdrant…"* — **zero external DBs**, single Node process, JSON on disk, **BM25 + vector + knowledge-graph RRF**, 12 auto-capture hooks, 53 MCP tools (8 exposed by default), ports **3111** (REST/MCP HTTP) **3112 3113 49134**, data dir `$XDG_DATA_HOME/agentmemory` / `--data-dir` / `AGENTMEMORY_DATA_DIR` (**not** the `~/.agentmemory/<project>` path §9b currently types), and **native plugins for pi, Hermes, OpenClaw** + MCP for the rest. ⇒ **the dev memory plane can never be pointed at Qdrant** |
| **Mem0** (family/OWUI plane, HD-335 tail) | library or **self-hosted server** (FastAPI :8888 + dashboard :3000, per-user API keys, audit log) or **cloud**. Qdrant is a supported vector store (`collection_name`, `embedding_model_dims` default **1536** → must be **1024**). ⚠ **`@mem0/mcp-server` is Cloud-only**; the OWUI integration is a **Pipelines filter** (`open-webui/pipelines/examples/filters/mem0_memory_filter_pipeline.py`, MIT; `cloudsbird/mem0-owui` self-hosted). ⚠ dims trap: its `openai` embedder sends `dimensions` **only if you set `embedding_dims`**, and vLLM/llama.cpp-class backends **reject** that parameter; leaving it unset makes Mem0 assume 1536. Probe before wiring |
| **Open WebUI** | native **MCP since v0.6.31** (Streamable HTTP), requires `WEBUI_SECRET_KEY`; **External Knowledge Sources = Qdrant / Milvus / pgvector**, queried at chat time, never re-ingested; **Markdown Header Splitting (H1–H6) + Chunk Min Size Target** run *before* the token splitter; the Docling hook is the *document conversion* engine under Tools→Documents (and OWUI once called `/v1alpha/convert/file` while docling-serve ≥1.0.1 serves `/v1/convert/file`, #15955) ⇒ **a `.md` upload needs no Docling at all**, and an OWUI upload is **not** the corpus |
| **pi MCP adapter** | `npm:pi-mcp-adapter` (nicobailon), MIT, v2.31.0, ~252 k weekly, updated 2026-08-28; one proxy tool ≈200 tokens, lazy servers + cached metadata, `url` = **StreamableHTTP with SSE fallback**, `includeTools/excludeTools`, `approveTools`, `caFile`, `.mcp.json` layered config; forks (`@nklisch/`, `@icefairy/`, `@cansiny0320/`, …) are variants of the same tree |
| **context-mode** | MCP server **+ native pi extension** (hooks `tool_call/tool_result/session_before_compact/…`), SQLite + **FTS5** + BM25 over *session events and tool output*, sandboxed execution, claims 315 KB→5.4 KB, **Elastic License 2.0**. **Phase 2 only, and OFF during any bake-off**: it changes what every harness sees, adds a second (transient) retrieval substrate, and its compaction hooks interact with `pi-harness.md` §5 |
| **Hermes memory providers** | `openviking · honcho · mem0 · hindsight · holographic · retaindb · byterover · supermemory`, **one active at a time**; `hermes memory setup mem0 --mode oss --oss-vector qdrant` is how "Hermes reuses Qdrant" would be done — **not recommended** while agentmemory is the dev substrate (a third memory store makes the comparison unmeasurable) |

---

## 5. The ingest reasoning the probes interpret (decided by the owner's framing, not by this lane)

* **n8n stays the universal *trigger*** (OpenCloud drop folder, webhooks, OCR fan-out, notify, HITL) but is
  **not the chunker**. Roslyn is a .NET library and n8n is Node, so "n8n does C#" physically becomes
  *n8n → exec → a .NET container*; deterministic upsert + stale-chunk sweep is typed, tested code
  (`id = UUIDv5(project+path+chunk_index)`), and a workflow canvas is outside `validate-all.sh` + review.
  **One contract, universal trigger, one worker container.** A nightly full-reconcile is the sweeper.
* **`.md` must not pass through Docling** — Docling re-emits Markdown in its own representation and would
  damage OKF front-matter, fences and pipes. Route: pdf/office/images → Docling; `.md`/`.txt` →
  markdown-header split → token 512/64; code → tree-sitter; `.cs` → Roslyn (with a `tests/fixtures/` C#
  corpus **before** any C# project exists — an unexecuted chunker is a hope, not support).
* **Browser uploads are not knowledge.** "Use in this chat" = OWUI's own store (fine, transient);
  "make this knowledge" = a git commit → indexer → index. OWUI reads the corpus as an **external** vector
  source, so it never owns embeddings.

---

## 6. Lock-in, as accepted by the owner (context for the recommendation)

AGPL is irrevocable for released versions; they may relicense future ones, split CE/EE, or drift to hosted.
Our existing digest-pinning + Renovate discipline blunts that. Removal cost by scenario: license flip ≈ 0
(freeze the pin); abandonment ≈ 0 (images + AGPL source are ours); **gating existing features 2–4 days**;
**full removal → rebuild `rag-mcp` ≈ 1–2 weeks**, mostly *building* what was skipped. The real lock-in is
not the data (OVPack + Markdown substrate), but **(a)** capability we would stop building (the reader),
**(b)** the L0/L1 summary tree (LLM cost to rebuild), **(c)** behavioural coupling — `viking_*` tool names,
`context takeover` owning compaction, prompts written around it.

**Insurance rules that cap it, and that belong in the adoption proposal if adoption happens:**
1. nothing lives only in OV — git stays SSOT, the corpus is re-importable by construction, `user/`+`memories/`
   get a Kopia seam because those are genuinely irrecoverable;
2. nightly `ov export` → Kopia, treated like the Qdrant snapshot seam (relaxed posture, HD-307) **with the
   plaintext-archive caveat written into `backup.md`**;
3. pin by **digest** in `group_vars/all/versions.yml`, keep Renovate, record the license;
4. prompts stay product-agnostic — *"use your memory and retrieval tools"*, never *"run `ov find`"*;
5. **the family plane never touches OV** (OWUI + Mem0 + Qdrant stay boring) so a dev-plane exit never
   reaches the household.

---

## 7. THE PROBES

### 7.1 Substrate (ephemeral, non-container, non-IaC)

```bash
# oldsrv, under the `domen` seat (HD-409 seat). NO docker run — see §7.4.
python3 -m venv ~/ovprobe/venv && ~/ovprobe/venv/bin/pip install -U openviking
~/ovprobe/venv/bin/openviking-server init        # or hand-write ~/.openviking/ov.conf
~/ovprobe/venv/bin/openviking-server doctor
~/ovprobe/venv/bin/openviking-server --data-dir ~/ovprobe/data &   # :1933
curl -s localhost:1933/health
```
`OPENVIKING_DATA_DIR` / `--data-dir` on a scratch path, reused on every restart. Nothing family-facing
lives in that directory.

### 7.2 Config (`ov.conf`) — 100 % local, every slot onto a leg we already run

```
embedding: provider "litellm" (or "openai") · api_base → lan-litellm · model "bge-m3-vk" · dimension 1024
           · input "text" · encoding_format "float" · max_input_tokens 2048 · batch_size 4
vlm:       provider "litellm"                · api_base → lan-litellm · model "spark/qwen3.8-flash-next"
           · extra_request_body {"chat_template_kwargs": {"enable_thinking": false}}
           · media { enabled: false }                    # already the default; set it explicitly
rerank:    provider "litellm"                · model "local-rerank" · threshold 0
           · max_input_tokens 2048 · timeout 60
```

**Every non-default value above is a repo finding, not a preference — reproduce them and say so in the
report:**

| Key | OV default | We set | Because |
|---|---|---|---|
| `embedding.input` | **`"multimodal"`** | `"text"` | `embedding_config.py:48`. A multimodal request against our text-only leg is a guaranteed failure class |
| `embedding.encoding_format` | OpenAI-SDK default (**base64**) | **`"float"`** | OV's own docs: set `float` "when the upstream gateway cannot deserialize base64 embedding payloads". Our chain is OV → LiteLLM `hosted_vllm/…` → **llama.cpp, which emits floats** — this is the **§3a-3 finding #3** failure (`encoding_format: null` → llama.cpp 500) wearing a different hat |
| `embedding.max_input_tokens` | **`4096`** | **`2048`** | our embed leg runs `--parallel 4 --ubatch 32`, and a chunk over ~2048 tokens **fails loudly with HTTP 500** (§3a-3 finding #4). 4096 estimated raw tokens sails past that |
| `embedding.batch_size` | `32` | `4` | match the leg's `--parallel 4`; a 32-wide batch against 4 slots is queue pressure on the same dGPU the family uses |
| `embedding.model` + `dimension` | provider `volcengine`; if it ever falls to `provider: "local"` it fetches **`bge-small-zh-v1.5-f16`** with a **Chinese query instruction** | pin `bge-m3-vk` / `1024` | never let the fallback decide our encoder (§3.2). `doctor` must print provider + model + dim before P1 starts |
| `rerank.threshold` | `0.1` | `0` | `services-ai.md` §5b decided 0 — don't let a default silently re-tune retrieval |
| `rerank.max_input_tokens` | **`0` = no cap** | `2048` | the rerank leg runs `ctx 2048 / ubatch 2048`; oversized pairs fail loudly (finding #1). Cap it, don't discover it mid-import |
| `vlm.extra_request_body` | unset | `chat_template_kwargs.enable_thinking=false` | `pi-harness.md` §2: thinking is the engine's **binary** knob and `qwen3.8-flash-next` **defaults ON**. OV supports this key (its own local example passes `{think: false}`) → **the probe also answers HD-387's open question** (does the flag survive the hop?) for free: send one request with `include_usage`, count `reasoning_completion_tokens`; if it leaks through LiteLLM unset, that is a *finding*, not your bug — record and continue |
| `vlm.media.enabled` | `false` | explicit `false` | decision #28 (text-only). Also note OV's image/table understanding (`openviking/parse/vlm.py`) would **duplicate Docling**, which is already our extraction tier on the CPU — leaving it off is the design, not a limitation |

* **`lan-litellm` has no `curl` inside the container** — drive its API from the host or any container that
  ships a client, and never write a bridge IP into a doc. `llitellm.kogler.si` is served on the oldsrv
  `traefik-internal` HOME edge (TLS).
* Keys: the **master key** (`op read 'op://Homelab-ansible/litellm_api/credential'` into a variable,
  **never echoed, never printed — not even truncated**) is acceptable for a probe because HD-384 has not
  created scoped consumers yet; say so in the report. `bootstrap_keys` stays `false`; do **not** flip it.
* **No external endpoint.** If `litellm`/`openai` provider config in OV insists on a non-local `api_base`,
  or a slot refuses to run against LiteLLM, **stop and report** — do not reach for a cloud key to unblock.
* **Path-symmetry trap (ours, learned live):** LiteLLM appends `/embeddings` and `/audio/transcriptions` to
  the `api_base` it is given, but the `jina_ai/` rerank path **discards** the path. OV likewise says it
  *appends the mode-specific endpoint path automatically, so do not include it*. **Test both directions with
  one curl each** and record which suffix each slot wants — this is the #1 predicted blocker.

### 7.3 P1 — round-trip fidelity (the owner's chosen probe)

**Import** a deliberately adversarial slice (~40–60 files; pick the worst, not the average):
`docs/services-ai.md`, `CONVENTIONS.md`, `docs/network-rejected.md`, `readme-humans.md`, `docs/manual/*.md`
(Slovenian), one code-fence-heavy doc, one table-heavy doc, `IaC/ansible/group_vars/vps.yml`, a 500-line
slice of `todo.md`, and **one `*-generated.md`** (to test whether the exclusion rule can even be enforced).

```bash
ov add-resource <path-or-repo>     # async: capture the task_id
ov task status <task_id>           # poll until completed
ov ls viking://resources/ ; ov tree viking://resources/<x> -L 3
ov grep "<string that exists verbatim in the original>" ; ov read <uri>
```

**Diff script (~50 lines Python, reads the HTTP API or `ov read`) — eight checks, per file pass/fail + a
list of failure classes:**

| # | Check | Why this one |
|---|---|---|
| 1 | byte-identical to the git blob | gold test |
| 2 | identical after whitespace normalisation | separates *reflowed* from *rewrote* |
| 3 | OKF front-matter keys intact (`title` `type` `tags` `generated_at`) | `services-ai.md` §5a contract |
| 4 | **markdown header count + ATX levels unchanged** | OV injects `.abstract.md`/`.overview.md` — does it touch yours? |
| 5 | **unescaped `|` count per table row** | the exact defect that merged two registry rows on 2026-09-21 (HD-417) |
| 6 | code-fence count + `j2`/YAML block-scalar survival | our templates are the corpus's most fragile text |
| 7 | Slovenian diacritics (`č ć š ž`) intact | |
| 8 | `*-generated.md` excluded on import and on re-import | the corpus's own exclusion rule |

**Pass:** 1 or 2 passes for every file **and** 3–7 pass **and** 8 behaves correctly.
**Partial:** whitespace-only reflow (2 passes) — record exactly what moved; it decides whether git can stay
the diff target.
**Fail:** rewritten headers, rewritten front-matter, mangled pipes/fences/diacritics ⇒ **OV would break the
"index is a rebuildable cache over git" invariant** — that alone answers OQ-10 as *build*.

### 7.4 Why no container

HD-394 exists precisely because this fleet has hand-run containers (`confident_shamir`, `pgvector`) that no
converge can see or clean. A probe that leaves a fifth container is a defect, not a shortcut. Venv +
scratch data dir, removed with two `rm -rf`s. **Record the teardown commands in the report.**

### 7.5 P2 — retrieval fidelity vs the today-baseline

Write **10 questions with known answers and a known source file** (ports, VLAN ids, HD numbers, "which host
runs X", "what did we decide about Y"). Run them three ways and score **top-5 hit / answer correctness**:
(a) `ov find` (+ `ov read`), (b) `grep`/read agentic search — **this is what we do today, and it must be
scored, not assumed to be the loser**, (c) if `rag-mcp` is still unbuilt (it is), note that the *decided*
design was never measured, so (b) is the honest baseline. Record tokens in, calls made, and latency per
question.

### 7.6 P3 — is spark good enough as OV's summariser? (local arms only, no spend)

OV's LLM does **compressive** work: L0 abstracts, L1 overviews, session-commit extraction, `ov compile`. The
owner's question is *"is OV's default model better than mine"* — answered in §3.2 (on two of three slots OV's
default is strictly worse for this box; the third is exactly what this probe measures). Since the lane is
100 % local, P3 compares **spark against local baselines**, not against a paid model. Same **20 documents**,
three arms:

| Arm | What writes L0/L1 | What it proves |
|---|---|---|
| **(a)** | `spark/qwen3.8-flash-next`, thinking **off** (`enable_thinking: false`) | the intended production config — the baseline quality bar |
| **(b)** | same model, thinking **on** (OV's `vlm.thinking` / no override) | does reasoning buy retrieval-grade summaries, or is it pure latency + `reasoning_tokens` on a 1.97× KV pool? If (b) ≈ (a), **turn thinking off permanently for this slot** — a free, local win |
| **(c)** | **no LLM at all**: first-N non-empty lines + header outline as a stand-in L1 (a 15-line script) | **the load-bearing arm.** Our docs already carry §5a front-matter + headers, so a cheap extract may already serve as a retrieval key. If (c) ≈ (a), OV's whole L0/L1 layer costs KV and buys nothing on *our* corpus — and that single fact should drive OQ-10/11 harder than any benchmark |

Judge by eye, 5-line rubric per doc: *names the right subsystem · right host · every number verbatim · invents
nothing · usable as a retrieval key?* ~1 h total. Also record the **HD-387 micro-result** (does
`chat_template_kwargs` reach spark through LiteLLM, measured by `reasoning_completion_tokens`) — it is free
and it unblocks a live row.

**Optional arm (d), off by default:** a small instruct model on the dGPU via the already-live `ollama`
container. Do **not** run it unless the owner asks: the pinned tier is **2475 MiB of 8 GiB** with `immich-ML`
claiming 3–5 GB when active, so a 7–8 B Q4 (≈4–5 GiB) fits only when immich is idle, and CPU fallback on
4C/8T would be glacial. If it is run, that VRAM math goes in the report with the measurement that proves it.

### 7.7 P4 — cost / throughput (falls out of P3, do not skip)

Per 20-doc compile, **per arm**: **prompt + completion tokens (incl. any `reasoning_completion_tokens` leak),
wall-clock, and concurrent KV pressure** (pool = 515 786 tokens ≈ 1.97× one 262k session; decode ~11 tok/s).
Extrapolate to the real corpus size and state plainly whether a full compile on spark is an overnight job that
competes with coding lanes — and what it costs to *re*-compile after a corpus change. Also record whether the
per-query knobs (`OPENVIKING_RECALL_QUERY_EXPANSION=off`, `OPENVIKING_RECALL_COMPRESS=off`) had to be turned
off to keep recall latency acceptable, since those are per-turn costs on the same engine the harnesses use.

### 7.8 Predicted blockers (each is a fact worth reporting, not an excuse)

1. **Embed wire-format (most likely blocker, and we have seen this film):** OV/OpenAI-SDK default to
   `encoding_format: "base64"` and may send `dimensions`; our chain is LiteLLM `hosted_vllm/…` → **llama.cpp**,
   which emits floats and **rejects unknown parameters** (§3a-3 finding #3: `encoding_format: null` → 500).
   Set `encoding_format: "float"` and `input: "text"`, then distinguish *"sets the expected dim"* from *"sends
   the parameter"* — only the second one breaks.
2. **Oversized embed request:** OV's `max_input_tokens` default is **4096**; our leg **500s** over ~2048 tokens
   (§3a-3 finding #4). Set 2048 and confirm the failure actually disappears rather than moving elsewhere.
3. **Silent encoder fallback:** if the embed slot ever resolves to `provider: "local"`, OV downloads
   **`bge-small-zh-v1.5-f16`** with a Chinese query instruction — a wrong-index situation, not an error.
   `openviking-server doctor` must print the pinned provider/model/dimension before P1.
4. `api_base` suffix rules for each slot (see §7.2).
5. Which path the `litellm` rerank client posts to (`/rerank` vs `/reranks`) — our row answers `/v1/rerank`
   upstream via `jina_ai/`.
6. Import is async and L0/L1 generation is LLM-bound: **"not there yet" is not "failed"** — poll, then judge.
7. The `chat_template_kwargs` flag may **not** survive LiteLLM (open question in **HD-387**). If thinking
   leaks anyway, record it as the answer to that row; it is **not** a reason to stop the probe.
8. `lan-litellm` has no shell client; `dmesg` on oldsrv needs `sudo`; `rocm-smi` lives inside containers, not
   on the host.

### 7.9 Standing safety rules for this lane

- Fresh session worktree before any write (CONVENTIONS §6, mechanically enforced by `scripts/guard-session.sh`
  and `validate-all.sh`); **manage only your own worktree**, never `rm`/rename another's; a pre-existing
  `../homelab-wt-*` belongs to somebody else.
- **Do not add, change or converge any IaC.** No `docker_services` entry, no vault item, no LiteLLM model row.
- **Never print a secret value** — lengths, prefixes, item ids and hashes only (CONVENTIONS §6).
- **No family data in the probe corpus.** This repo only.
- **No spend, no external endpoint** (owner's constraint): spark + the oldsrv dGPU legs only. If a measurement
  needs anything else, stop and ask.
- Do not bench or converge spark from a spark-backed session; do not run this probe's P3a against spark while
  another lane is converging.
- `validate-all.sh` must end green; **a test that cannot fail is not evidence** — for each check, show the
  input that would fail it.
- Teardown in the same breath as the setup, and prove the teardown (data dir gone, port 1933 closed).

---

## 8. What the outcomes mean (read this before reporting, not after)

| If the probe shows… | Then the recommendation is… |
|---|---|
| P1 **fails** (rewrites markdown/front-matter/pipes) | **Build** `rag-mcp` (HD-268b) as the corpus reader. OV may still be trialled later for *memory only* — but never as the corpus index, because git stops being diff-able truth |
| P1 passes, P2 **≤ grep baseline** | Build `rag-mcp`; OV's index earns nothing here. Re-defer OV with a real row in `services-rejected.md` (the §8.3 hole closes) |
| P1 passes, P2 clearly better, P3 arm (a) holds (≥ (c)) | **Adopt OV as memory + corpus for the dev plane**, keep **Qdrant + curated corpus for the family plane and Mem0**, keep `local-rerank` as OV's reranker (correcting §5b's "no consumer" line), and adopt the five insurance rules (§6) **in the same change**. §5b edit: threshold 0.1 default, sparse caveat, rerank-as-config |
| P1 passes, P2 clearly better, but P3 shows **(c) ≈ (a)** (the free extract wins) | Adopt OV **as memory + tree/browse only**, and **stop buying L0/L1 summaries** — either run OV with `text_source: content_only` or build `rag-mcp` for the corpus. This is the outcome that makes §5b's pipeline the cheaper one; write it plainly |
| P1 passes, P2 clearly better, P3 arm (a) holds and (b) > (a) | Same as the row above **plus** overnight local compiles sized by P4 (thinking-on costs tokens we may not have); still keep the family plane on Mem0 (blast-radius rule) |
| P1 *partially* passes | Adopt only as **memory**, keep the corpus on Qdrant + `rag-mcp`; the partial rewrite is exactly the thing you must not inherit for git-diffable docs |

Whatever the result: **write one row so this is never re-litigated** — either a numbered decision in
`services-ai.md` §9 (+ §5b/§9b corrections listed in §3.1/§4 above) or a `services-rejected.md` row. The
current state ("deferred", one prose line, no row) is the governance defect this lane exists to close.

---

## 9. Report format (return exactly this)

```
PROBE REPORT — prompt-OV.md · date · session branch + worktree
1. SETUP PROVEN         ov version/digest or pip version, config block actually used (keys redacted,
                        lengths only), `curl :1933/health` output, import task_ids completed
2. P1 FIDELITY          per-file table (8 checks × N files) + failure classes ranked by severity +
                        2 worked examples (original vs OV text, ≤20 lines each)
3. P2 RETRIEVAL         10 questions × (ov find / grep baseline): hit@5, correctness, tokens, latency
4. P3 SUMMARISER        20 docs × arms (a) spark-thinking-off / (b) spark-thinking-on / (c) no-LLM extract:
                        rubric score per doc, 3 verbatim failure examples per arm, and the HD-387
                        reasoning_tokens result. State explicitly that no external model was used
5. P4 COST              tokens + wall-clock per 20 docs, extrapolated full-corpus figure,
                        KV-concurrency verdict, which recall knobs had to be turned off
6. ANSWERS              OQ-10 build|adopt, OQ-11 memory-only|memory+corpus — each with the ONE number
                        that decided it, and confidence (high/medium/low)
7. BLOCKERS FOUND       every §7.8 item: hit or missed, with the curl/error line
8. WHAT THIS PROBE DID NOT TEST   (be honest: no external/frontier model comparison (owner's 100%-local
                        constraint, so "is a hosted model better" stays unanswered by design), no rerank
                        quality (no labelled set), no multi-user scoping, no context-takeover safety on
                        `pi -c`, no long-run stability, no sparse/hybrid (our leg is dense-only), no
                        image/table understanding (media off, decision #28), no family-plane suitability)
9. TEARDOWN PROVEN      commands run + proof the venv, data dir and :1933 are gone; `git status` clean;
                        NO IaC touched (proof: `git status` empty for IaC/)
10. RECOMMENDATION      pick the matching row of §8, name the doc rows it forces, and the residual risk
```

---

## 10. Source list (all read 2026-09-21 — do not re-derive)

Repo: `docs/services-ai.md` §1/§2/§3/§3a/§4/§5/§9/§9b/§9c · `docs/pi-harness.md` §1b/§2/§4/§5/§6 ·
`docs/hardware-spark.md` (unified-memory budget, certified KV) · `docs/hardware-oldsrv.md` ·
`docs/services-rejected.md` (PGVector superseded; TEI rejected) · `docs/index.md` · `todo.md`
HD-104/103/111/248/249/267/268/335/336/336b/337/344/367/384/386/387/388/402/407/409 ·
`brainstorming/Code-RAG system.md` + `brainstorming/recent/Razvojna platforma.md` §D (superseded
FastGPT/nomic-768 chassis; the durable bits are the UUIDv5 determinant and the chunker intent) ·
`IaC/ansible/templates/docker_services/rag-mcp/docker-compose.yml.j2` (the stub) ·
`CONVENTIONS.md` §5/§6/§8.3.

External (verified directly): OpenViking repo `LICENSE`, `docker-compose.yml`,
`openviking_cli/utils/config/{rerank,vlm,embedding}_config.py` (defaults quoted in §3.2/§7.2: provider
`volcengine`, `input="multimodal"`, `batch_size=32`, rerank `doubao-seed-rerank`/`251028`/`threshold 0.1`/
`max_input_tokens 0`, `vlm.media.enabled=false`, `extra_request_body` support),
`openviking/models/embedder/{local,litellm,jina,gemini,cohere,dashscope,volcengine}_embedders.py` (
`DEFAULT_LOCAL_DENSE_MODEL="bge-small-zh-v1.5-f16"` + its Chinese query instruction, the OpenAI dim table,
`litellm.embedding()` usage, `LITELLM_LOCAL_MODEL_COST_MAP=True`), `openviking/parse/vlm.py` (image/table →
L0/L1/L2), `openviking/utils/{summarizer,resource_processor,skill_processor,media_processor}.py`,
`openviking/storage/queuefs/semantic_processor.py` (`vlm.is_available()` gating),
`docs/en/guides/01-configuration.md` (`text_source`, `max_input_tokens` 4096, `encoding_format` float-for-
gateways, the local `vlm: provider litellm / ollama/llama3.1 / think:false` recipe),
`docs/en/guides/09-ovpack.md`, `docs/en/agent-integrations/{01-overview,05-hermes,11-pi}.md`,
`README.md` (LoCoMo/tau2 numbers) · agent-memory.dev docs + `rohitg00/agentmemory` ·
Mem0 docs (`/open-source/configuration`, `/components/vectordbs/dbs/qdrant`, `/open-source/setup`,
`/platform/mem0-mcp`) + `mem0/embeddings/openai.py` + `open-webui/pipelines` mem0 filter ·
Open WebUI docs (`/features/extensibility/mcp/`, `/features/chat-conversations/rag/` incl. external
knowledge sources, `/reference/env-configuration/`) · NousResearch `hermes-agent` memory-provider docs ·
`nicobailon/pi-mcp-adapter` README + source · `mksglu/context-mode` README/Pi adapter.
