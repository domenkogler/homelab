> **Role:** single-lane handoff for **HD-391 — author + deploy the three pinned-AI services on oldsrv** (`whisper`, `reranker`, `embed`) on the ggml/**Vulkan** family per decision #27. Self-contained: the digests, model digests, flags, file paths, converge commands and the verification protocol are all below, so you can start without opening the bench doc.
> **Linked from:** [`prompt.md`](prompt.md) §2 · [todo.md](todo.md) HD-391 · siblings [`prompt-397.md`](prompt-397.md) (how to reach oldsrv from anywhere) and [`prompt-398.md`](prompt-398.md) (why the mgmt leg is dead).
> **Baseline:** authored on `main` at `47a71c7`, 2026-09-19.

---

## 0. Start here (the ritual, then the shortcuts)

1. `git worktree add ../homelab-wt-$(date +%Y%m%d-%H%M)` — **before any edit** (CONVENTIONS §6, mechanically enforced).
2. Ansible always via `bash scripts/ansible-run.sh playbooks/home_servers.yml --limit oldsrv.kogler.si …`.
3. Converge rules, each earned by an incident: **real converges DETACHED** (`nohup … > /tmp/converge-oldsrv-<ts>.log 2>&1 &`, then poll for `PLAY RECAP`); **never `--diff` on a `docker_services` run** (renders live keys into the log); a scoped service deploy needs **both** tags (`--tags docker_services,<svc>`); `--check` is the only safe foreground form.
4. Reaching oldsrv: Home leg through the VPS jump. Today that means `Host 10.10.1.30` (or `-o ProxyCommand="ssh -W %h:%p vps"`). **Never** `-e ansible_host=<ip>` on a real run — it is a global extra-var and hijacks `delegate_to` targets (`ok=367 changed=52 failed=1`, proven 2026-09-19). Until HD-397 lands, expect to name the host explicitly; a **full** unscoped converge of oldsrv is also acceptable and avoids the scope trap.
5. Never print a secret value — hashes/lengths only.
6. Finish: `bash scripts/validate-all.sh` green → signed commit → fast-forward into `main`.

**Do NOT re-litigate (all closed by measurement or by decision — re-reading them costs an hour and changes nothing):**

- **Decision #27 is ACCEPTED** (2026-09-18): all three legs move to ggml/Vulkan on the RX 7600. Plan of record [docs/services-ai.md](docs/services-ai.md) §3a; bench provenance [docs/services-ai-bench.md](docs/services-ai-bench.md).
- **The HD 630 iGPU is a dead end** — 5.8–22.8 s per rerank (slower than CPU), it holds *host* RAM, Gen 9.5 `legacy1` stack is frozen, and it is the Xorg + Jellyfin QSV device. `--device` is **`/dev/dri/renderD129` only**.
- **No `whisper.cpp` ROCm/HIP image is published** → Vulkan is the only digest-pinnable artifact path; do not plan a self-build.
- **TEI `cpu-1.9.4` is a fallback, never primary** (5.3 s for a 20-doc rerank at ~790 % CPU; warmup hit 10.8 GiB RSS unless `--max-batch-tokens 2048 --max-client-batch-size 32`; `OMP_NUM_THREADS` must stay **unset** — 4/8 never became ready).
- **Embed moves without re-embedding:** cosine mean **0.99960** / min 0.99856 vs the live Ollama vectors, dim **1024** unchanged → this is routing, not a corpus migration (do not re-open HD-268's re-index for this).
- **Q8_0 on both GGUF legs** (FP16 measured: +269 MiB/leg, +18 % embed latency, no ranking change).
- **`main-vulkan` / `server-vulkan` are mutable aliases ⇒ digest-pin them** (CONVENTIONS §7).
- **Do not** set `amdgpu.cwsr_enable=0` up front, and **do not** introduce `amdgpu-dkms` on oldsrv ([docs/hardware-gpu.md](docs/hardware-gpu.md) CWSR section).
- **Do not** re-scope the ollama `:rocm` flip: `ollama` stays `enabled: true` as the **embed fallback rung** until the Vulkan embed leg is live-verified, then it is demoted (not deleted) — and never bump the ollama pin "for rerank": no released ollama serves `/api/rerank`.

---

## Lane coordination — read before starting

**Run this lane solo.** It is the long pole (authoring + repeated detached converges + on-box GPU verification whose numbers have to be transcribed accurately) and that cadence does not mix with the access/ACL doc work. It is **not blocked** by HD-397/HD-398 — §0.4 carries the working oldsrv path as it stands today.

- **Files this session owns:** `IaC/ansible/templates/docker_services/{whisper,reranker,embed}/` · `IaC/ansible/group_vars/all/versions.yml` (the two new pins) · the three registry lines in `IaC/ansible/group_vars/home_servers.yml` (append near the `ollama` entry — the HD-397 lane edits a *different* hunk of this same file, the top-level `ansible_ssh_common_args` key) · [docs/services-ai.md](docs/services-ai.md) §3a/§4/§7 · [docs/services-ai-bench.md](docs/services-ai-bench.md) (deploy-measured additions only, no restatement).
- **Do not touch:** [docs/network-vpn.md](docs/network-vpn.md) — the HD-397/398 lane owns it. If a reachability fact changed while you worked, put it in the commit message and let that lane write it.
- **Converge etiquette:** your runs are long and detached. Before starting one, confirm nobody is doing a network experiment (the HD-397 hotspot pass kills converges mid-restart) and that no converge is already running — but **`pgrep -f ansible-playbook` is not a valid gate**, it matches its own argv. Better: look for the log file and the actual `ansible-playbook` process with `ps -eo args | grep -c '[a]nsible-playbook'`.
- **todo.md:** only HD-391 (deleted when its list is empty) and trimming HD-369's superseded tail, which §6.3 of this brief explicitly authorizes. Never renumber or touch another lane's row.
- **Cadence:** `git pull --ff-only origin main` before starting and before every commit — especially because a converge can run 10–30 min while `main` moves; merge, re-run `validate-all.sh`, then fast-forward.
- **Never** converge or bench **spark** from a session whose own model is spark (incidents #3/#6). This row is oldsrv work; if you get pulled into spark-side work, take a different session.

---

## 1. Mission + definition of done

Author `whisper`, `reranker`, `embed` as first-class `docker_services` entries, deploy them on oldsrv, wire the LiteLLM catalog, and verify live: VRAM, three-way concurrency, real Slovenian STT, `dmesg` clean.

**Done when:**

- [ ] `templates/docker_services/{whisper,reranker,embed}/docker-compose.yml.j2` exist, validate (`scripts/validate-docker-services.py` runs inside validate-all), and are registered in `IaC/ansible/group_vars/home_servers.yml`.
- [ ] Both images are **digest-pinned** in `IaC/ansible/group_vars/all/versions.yml` (no `latest`, no mutable tag in a rendered compose).
- [ ] Model-fetch tasks are **sha256-verified, idempotent** (skip on match), and land under the service's model dir with `:ro` mounts.
- [ ] oldsrv converged `failed=0`, three containers `Up`, and each endpoint answers with the expected shape (§5).
- [ ] `docker ps` shows **no `/dev/kfd` in any of the three** (Vulkan uses `/dev/dri` only), and the measured tier VRAM is ≈ **2.4 GiB of 8 GiB** (embed 0.33 + rerank 0.33 + STT 1.72), host RSS ≈ 0.5 GiB total.
- [ ] LiteLLM catalog (runtime DB, `POST /model/new`): rerank leg present as **`jina_ai/…`**, embed re-pointed **off `ollama/bge-m3`** to the Vulkan leg, STT reachable on `/v1/audio/transcriptions`; the old ollama embed row removed or re-pointed, and the change recorded in the owning doc as a runbook.
- [ ] Dead pulls swept out of `templates/docker_services/ollama/docker-compose.yml.j2` + `vps.yml` comments: `sendmeaiohyeah/whisper-large-v2`, `qllama/bge-reranker-v2-m3:q8_0`, and the retracted "needs ollama ≥ 0.5.x for rerank" claim.
- [ ] Three-way concurrency re-measured on the deployed (not probe) containers, `dmesg` delta recorded vs the 1,296-line `init_user_pages` baseline (HD-393) with **0 hang/reset**.
- [ ] [docs/services-ai.md](docs/services-ai.md) §3a flips the ⏳ rows to live + dated; [todo.md](todo.md) HD-391 deleted (done ⇒ deleted, CONVENTIONS §4(a)).

---

## 2. Plan of record — the values to use verbatim

| Leg | Image (pin by digest) | Entrypoint + flags | Model (quant, size) | Measured |
|---|---|---|---|---|
| **STT** | `ghcr.io/ggml-org/whisper.cpp@sha256:cf102ac361a0978ce2b225c7fa9eccedc781915b7be4d198692ea5fe2261597f` | `--entrypoint /app/build/bin/whisper-server` … `--inference-path /v1/audio/transcriptions --host 0.0.0.0 --port <p> -m /models/ggml-large-v3-turbo.bin -l auto` | `ggml-large-v3-turbo.bin` **fp16** (q5_0 = −1.0 GiB option, 786 MiB) | 1788 MiB (Δ1722) · **0.4 s per 11 s WAV** |
| **Rerank** | `ghcr.io/ggml-org/llama.cpp@sha256:7158edb447f837734142c899183e255538d89d63a037f60077b26fc1c7f95353` (v0.4.1 b11028) | `--entrypoint /app/llama-server` … `-m /models/bge-reranker-v2-m3-Q8_0.gguf --embedding --pooling rank --rerank --device Vulkan0 --host 0.0.0.0 --port <p>` | `gpustack/bge-reranker-v2-m3-GGUF` **Q8_0**, 635,676,416 B, `sha256 a43c7c9b11a4c1517e5bf95151960e1621d1b72f7a493364b01e386cf1aaa1d3` | ~327 MiB · **0.34–0.50 s** top-20 (CPU TEI: 5.3 s) |
| **Embed** | same llama.cpp digest as rerank | `--entrypoint /app/llama-server` … `-m /models/bge-m3-Q8_0.gguf --embedding --pooling cls --embd-normalize 2 --device Vulkan0 --host 0.0.0.0 --port <p>` (+ `--ctx-size`, §3) | `ggml-org/bge-m3-Q8_0-GGUF` **Q8_0**, 634,553,760 B, HF LFS OID `sha256 aa473d51f451a22f0fcf39ba3330c14bed38a385712b1113440f69df4047a173` | ~326 MiB · **15 ms/chunk** (Ollama fp16: ~500 ms, 899 MiB) |

Shared plumbing (from the bench §9 probes, which ran green on this exact box): `--device /dev/dri/renderD129`, `--group-add 992` (= `render` gid on oldsrv; use the existing `gpu_render_gid` fact, not a literal), model dir mounted `:ro`. `GGML_VK_VISIBLE_DEVICES` is only needed if you ever point at the iGPU — you will not.

⚠ **The whisper GGML has no recorded sha256** in the bench doc (only URL: ggerganov/whisper.cpp release assets). Fetch once, record the digest in `versions.yml` next to the pin, and pin the task to it — closing that gap is part of this row.

---

## 3. Shape of the code (repo patterns to follow, not invent)

- **Registry entry** — `IaC/ansible/group_vars/home_servers.yml`, next to the `ollama` line, one-line dict like its neighbours:
  `- { name: whisper, template_dir: whisper, enabled: true }` (repeat for `reranker`, `embed`). Keep `ollama` enabled as the fallback rung.
- **Compose template** — `IaC/ansible/templates/docker_services/<name>/docker-compose.yml.j2`. Copy the **ollama** template's house style: header comment explaining the decision + why this engine, `networks: [llm-backend]` (`external: true`), **no `ports:`** (the bench probes published to `127.0.0.1:<port>`; the deployed legs are reachable only on `llm-backend` — same isolation doctrine as ollama: the network *is* the boundary, its API has no auth), **no Traefik labels**, `cap_drop: ["ALL"]`, no host binds, `devices: [/dev/dri/renderD129]`, `group_add: ["{{ gpu_render_gid }}"]`, `restart: unless-stopped`, `TZ: "{{ timezone | default('Europe/Ljubljana') }}"` (copy the exact form the ollama template uses) and **hard `mem_limit`** like other GPU legs.
- **Pins** — `IaC/ansible/group_vars/all/versions.yml`: `whisper_cpp_vulkan_version` + `llama_cpp_vulkan_version` holding **`<image>@sha256:<digest>`** in the shape the other digest-pinned entries use (check an existing pin in that file for the convention before inventing one), each with a dated `# registry-verified YYYY-MM-DD` comment.
- **Model fetch** — a task per model using `ansible.builtin.get_url` with `checksum: "sha256:<digest>"`, `creates`-style idempotence (or `stat` + `when`), dest under the service's model dir (nvme dataset, follow the ollama `/srv/models/…` layout, not the root FS), `mode`/owner correct for the container uid, and **verify the fetched digest matches the table in §2** — if the `ggml-org` LFS OID does not match the downloaded bytes, record which artifact you actually pinned rather than silently swapping mirrors.
- **Extra rendered files** go through `_extra_templates[<template_dir>]` (see `roles/docker_services/tasks/deploy-service.yml`) — do not invent a new hook.
- **`--ctx-size` on the embed leg:** the bench probe used ~**150-token** chunks and bge-m3 supports **8192**; **llama.cpp truncates silently beyond the window.** Read the real chunk size from the RAG ingest path (rag-mcp / Qdrant wiring, [docs/services-ai.md](docs/services-ai.md) §5b), set `--ctx-size` above it with headroom, and put a test in the verification log that proves a full-size chunk is not truncated (compare vector counts / a long-text probe).
- `llama-server` has **no keep-alive / LRU unloading**; `--sleep-idle-seconds` exists but costs a reload. Decide explicitly and comment the template: resident (budget allows ~2.4 of 8 GiB) is the expected answer.

---

## 4. LiteLLM catalog work (runtime DB — decision 13: never git-rendered)

Model rows live in the LiteLLM **DB**, created via the Admin UI / `POST /model/new` against `lan-litellm` with the master key (`litellm_master_key` from the vault — never echo it). Required changes:

- **rerank** → provider **`jina_ai/<model>`** pointed at the reranker's `llm-backend` address via a **literal `api_base`** + a dummy key. **Why literal:** LiteLLM v1.83.10 does **not** expand `os.environ/` inside DB-stored `litellm_params` (it forwards the string, upstream 401s) — HD-382's finding.
- **embed** → re-point off `ollama/bge-m3` to the Vulkan leg; **dimension stays 1024** (no re-index).
- **STT** → the OpenAI-ish `/v1/audio/transcriptions` path is served natively by `whisper-server`, **no wrapper needed** (decision #27 (c)).
- Leave `bootstrap_keys` as-is (`false`, HD-386) — no scoped consumer for these legs yet.
- Record the exact `POST /model/new` payloads (redacted) in the owning doc so the next VPS/DB rebuild can replay them.

**Traps here:** `--check --diff` on a LiteLLM converge leaks keys; a green **scoped** converge (`-e docker_services_scope=…` with only `--tags docker_services`) SKIPS the service you named and still prints `failed=0` — prove deploys with `docker inspect` / the rendered file, never with the RECAP.

---

## 5. Verification protocol (run it, paste the numbers into the doc)

```bash
# reachability (Home leg via the jump) — see prompt-397.md
O='ssh -o ProxyCommand="ssh -W %h:%p vps" ansible-admin@10.10.1.30'

# 1. state + no /dev/kfd + no host port publish
$O 'docker ps --format "{{.Names}}\t{{.Status}}" | grep -E "whisper|rerank|embed|ollama"
    for c in whisper reranker embed; do docker inspect $c --format "$c devices={{.HostConfig.Devices}} restart={{.HostConfig.RestartPolicy.Name}} ports={{.HostConfig.PortBindings}}"; done'

# 2. VRAM (host has NO rocm-smi — ROCm is container-bundled by design; use sysfs)
$O 'cat /sys/class/drm/card1/device/mem_info_vram_used'   # expect ≈2.4 GiB with the tier warm

# 3. endpoints (from the oldsrv shell, on the llm-backend bridge)
$O 'curl -s -F file=@/tmp/slo.wav http://<whisper>:<p>/v1/audio/transcriptions'   # real Slovenian sample
$O 'curl -s -d "{\"model\":\"local-reranker\",\"query\":\"…\",\"top_n\":5,\"documents\":[\"…\",\"…\"]}" http://<reranker>:<p>/v1/rerank'
$O 'curl -s -d "{\"model\":\"bge-m3\",\"input\":\"…\"}" http://<embed>:<p>/v1/embeddings'   # len == 1024

# 4. GPU pids — INSIDE a container that ships rocm-smi (immich-ml), not on the host
$O 'docker exec immich-ml rocm-smi --showpids | head'

# 5. dmesg delta vs the recorded baseline (capture NOW: the ring wraps)
$O 'dmesg | grep -c "init_user_pages"; dmesg | grep -icE "amdgpu.*(hang|reset)"'   # baseline 1,296 / 0
```

Then the **three-way concurrency** case (STT + rerank + embed simultaneously): the bench measured ≈1.5–2× each and flat over 6× sustained with **0 hang/reset** — reproduce on the deployed containers, and note immich-ML co-resides at 3–5 GB during a job (lowest priority; Sunshine's prep-commands pause it — gaming stays first).

---

## 6. Gates and judgement calls (make them explicitly, don't absorb them)

1. **`rag-mcp` is `enabled: false` ⇒ the reranker has no live consumer.** Ship the leg with the tier (dormant, cost ≈327 MiB) **or park it explicitly** (`enabled: false` + a reason in the registry comment). Both are fine; silently deploying an unused GPU resident is not.
2. **VRAM headroom:** tier target ~2.4 GiB of 8 GiB with immich-ML (3–5 GB) and Jellyfin/Sunshine on the same card. If the STT leg is the pressure point, q5_0 is the pre-approved relief (−1.0 GiB) — record the swap as a measurement, not a preference.
3. **Adjacent, NOT this row:** HD-369(c) LiteLLM recreate for the *ollama-era* model names is superseded by the §4 work (say so in the HD-369 row so nobody executes it literally); HD-369(d) voice re-point (Whisper→oldsrv, Piper→CPU, LLM→spark) rides **after** this row; HD-393 (`init_user_pages` attribution) is pre-existing — but capture `dmesg` before the ring wraps, because your deploy is the natural before/after boundary; HD-268 (Qdrant re-index) is **not** triggered by this (cosine 0.9996).
4. **Never bench or converge `spark` from a session whose own model is spark** (incidents #3/#6). This row is oldsrv work and is fine from a spark-backed session, but if you get pulled into spark-side work, switch sessions.

---

## 7. Close-out

1. [docs/services-ai.md](docs/services-ai.md) §3a: flip the three ⏳ rows to ✅ live + dated + the measured VRAM/latency deltas; keep the fallback rungs documented; update §4/§7 integration rows and the LiteLLM model-row table.
2. [docs/services-ai-bench.md](docs/services-ai-bench.md): do **not** restate the deployment; add only what the deploy measured that the bench could not (real chunk size, deployed-container concurrency).
3. [docs/hardware-gpu.md](docs/hardware-gpu.md): the tier's device/gid/budget facts if they changed; [docs/smart-home-voice.md](docs/smart-home-voice.md) only when HD-369(d) actually re-points voice.
4. [deployment-tasks.md](deployment-tasks.md): tick the deploy item with the date if one covers this.
5. [todo.md](todo.md): delete HD-391 when its list is genuinely empty; trim HD-369's now-superseded tail. Then `bash scripts/validate-all.sh` green (it lints prompt↔todo consistency and stale done-rows — a row you marked ✅ with no ⏳ tail must be deleted).
6. Signed commit on the session branch → fast-forward into `main`.
