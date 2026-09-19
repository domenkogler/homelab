# `prompt-391.md` — **CLOSED banner, not a brief** · pinned AI on oldsrv (HD-391)

> ✅ **LANE SHIPPED 2026-09-19 — do NOT start a session from this file.** The three oldsrv pinned-AI services
> are deployed **and live-verified**: `whisper` (:9000), `reranker` (:9001), `embed` (:9002) are `Up (healthy)`
> on `llm-backend`, and the LiteLLM rows `local-rerank` / `bge-m3-vk` / `local-stt` answered **through**
> `lan-litellm`. The row is deleted from `todo.md` per the lifecycle rule; the history is in git.
>
> **This file's durable content was promoted, so nothing is lost by closing it:**
> * [services-ai.md](docs/services-ai.md) **§3a** — the tier, with live rows and deploy-measured latencies
> * **§3a-1** — the deployed shape: ports, memory caps, model dirs/filenames, **image digests + model
>   sha256s**, the ctx/batch/ubatch derivation, `gpu_render_gid` **104 → 992** (`render:x:992` on the box; 104
>   is `ssl-cert`), the `/dev/dri/renderD129` node, and why observability stays at the host level
> * **§3a-2** — deployed measurements: **2475 MiB VRAM**, RSS **415 MiB**, embed/rerank/STT latencies including
>   **real Slovenian speech** (CJVT GOS), three-way concurrency, and the `dmesg` delta (0 hang/reset, zero new
>   `init_user_pages` lines, plus the two measurement traps: `sudo` is required and the raw count can *fall* by
>   ring eviction)
> * **§3a-3** — the three findings that only a deploy produces: **`--ubatch-size` is the real batch limit**
>   (the 500 message blames `batch_size`), the image's **:8080-hardcoded `HEALTHCHECK`** (healthy legs read
>   `unhealthy`), and **`openai/` embed forwarding `encoding_format: null`** → llama.cpp 500 ⇒ the row is
>   `hosted_vllm/`
> * **§4a** — the catalog runbook: executed payloads, the resulting row ids, `lan-litellm` has no `curl`,
>   `/model/list` is unusable with the master key (**use `/model/info`**), and **`/model/delete` takes `{"id":}`**
> * [services-ai-bench.md](docs/services-ai-bench.md) §3/§4/§5 — bench deltas only, per the no-restatement rule
> * [hardware-gpu.md](docs/hardware-gpu.md) — gid table + the sudo-required note
> * [deployment-compose.md](docs/deployment-compose.md) / [services.md](docs/services.md) — the `llm-backend`
>   network is now attached to **four** containers, not an unused reservation

**What rode out of this lane (do not re-open it for these):**
* ⏳ `ollama rm sendmeaiohyeah/whisper-large-v2 qllama/bge-reranker-v2-m3:q8_0` (~4 GB) — **HD-369 tail**
* ⏳ voice re-point `sherpa-onnx` → the Whisper leg — **HD-369 (d)**
* ⏳ any consumer allow-list / routing to the new rows, and `rag-mcp` itself (a compose **stub with no
  `services:` block**, not a flag to flip) — **HD-384 / HD-268b**
* ⏳ the Ollama embed fallback row stays (VPS instance; owner call 2026-09-19)

**Method notes worth keeping:** converge with `--tags docker_services,<name>` and prove it with `docker inspect`
(a scoped converge prints `changed=0` and a `RUNNING HANDLER` of only `docker login` when the named service is
disabled — false green); never `--diff` on a `docker_services` converge; never `-e ansible_host=` (it hijacks
`delegate_to`); the model-fetch task is idempotent (a pre-placed file with a matching digest comes back
`ok`, not `failed`).
