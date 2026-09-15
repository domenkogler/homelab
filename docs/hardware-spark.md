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

> **Status: 🟢 PROVISIONED + LIVE (2026-09-14).** DGX OS first-boot wizard completed (see `deployment-manual.md` §Phase 5): English / Europe/Ljubljana, admin → 1P `spark_login`, analytics disabled, updates + reboot; auto-suspend masked after the post-update L2 blackout (headless suspend kills the NIC — power-cycle recovered). GPU verified: GB10, driver 580.173.02, CUDA 13.0, 121 Gi unified, NVMe p1 EFI + p2 root (see HD-363: p3 = AI data XFS carve). First-contact bootstrap done (key-only `ansible-admin`, sshd hardening, 2 keys) + `spark.yml` converge **failed=0** (ok=53): common/network/docker/spark/monitoring; **p3 = 503.4G XFS at `/mnt/spark_nvme`** (fstab-durable, dirs `kv_cache/models/overlays/ples_int4/triton_cache/vllm_cache`); docker role now Ubuntu-noble-aware; XFS mount-opts corrected (nobarrier → removed). Spark is a first-class IaC host alongside nas/oldsrv/vps/pi.

>
> **Artifact store (general, HD-359):** the `spark-artifacts` role (`roles/spark-artifacts/`) downloads the GPU-inference store onto XFS from a **config-agnostic manifest** (`spark_artifacts:` in `group_vars/spark.yml`): B1 weights (`wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16` → `models/`), PLE overlay `.py` files, and INT4 tables (`primitive-ai/Qwen3.8-Flash-Next-PLE-quant` → `overlays/` + `ples_int4/`) — **one download per quant-artifact, shared by every engine profile** (vLLM B1 today; future NVFP4/SGLang repos = separate downloads by design). Idempotent per repo; runnable pre-bench via `--tags spark-artifacts`. **STAGED LIVE on the box 2026-09-14** (weights 169G + overlays 3×.py + tables 30G/129 files; 296G free) — the B1 engine (`spark-ai`) stays `enabled: false` until bench certifies a winner.
> ⏳ deploy-gated on the AI stack (`spark-ai.enabled: true` after bench S1–S5 on the live box → vLLM live → promote winner). **2026-09-14 HD-367: llm-d REMOVED** — the real llm-d is a Kubernetes inference-pool stack (endpoint-picker/disagg-sidecar route Envoy+K8s pools), not a single-node gateway; LiteLLM is the router in front of vLLM :8000.
>
> **vLLM metrics → Grafana (HD-368, 2026-09-14):** the spark-ai compose publishes `:8000` **loopback-only** (`spark_metrics_publish: true`, 127.0.0.1) so the spark Alloy can scrape vLLM's Prometheus `/metrics` (`prometheus.scrape "vllm"` — same pattern as traefik's 127.0.0.1:8082 metrics entryPoint) and remote-write it to the VPS VictoriaMetrics. Three Grafana dashboards were added to the monitoring role (`homelab-llm-inference`, `homelab-vllm-monitoring-v2`, `homelab-vllm-dashboard` — gnet 25502/24756/25043). The engine was flipped `spark-ai.enabled: true` (HD-367 Track 1, `9445d35`) — **live-verify:** vLLM `/metrics` on the loopback (curl the box: `curl 127.0.0.1:8000/metrics | head`) + vllm:* series in VM + panels on `stats.kogler.si`. See [observability.md](observability.md) §Dashboards.
>
> **B1 engine boot — TRACK 1 (2026-09-14, `session/spark-s1-converge`):** `spark-ai.enabled: true` flipped + converged; the engine's FIRST real boot (it had never started before — deploy-gated) surfaced + fixed **4 blockers**, all now in the SSOT (validate-all green): (1) `--swap-space` removed in this vLLM build (`0.1.dev20073+g8e685d198`) → dropped the flag + var; (2) `--quantization awq` mismatched the weights' `compressed-tensors` quant_method → removed the forced flag, vLLM reads the packed format from config; (3) `disable_by_batch_size` dropped from `SpeculativeConfig` (new `num_speculative_tokens_per_batch_size` schedule) → B1 = plain **MTP-3** (`{"method":"mtp","num_speculative_tokens":3}`); (4) `gpu_memory_utilization` 0.95 overflowed with the DGX dashboard co-resident (free 114.76 < 115.54 GiB) → **0.93**. 
> **B1 memory-fit fix — 2026-09-15 (`session/spark-b1-memfit-20260915-0050`):** the 0.93 config OOM'd the WHOLE box at model-load every boot (global kernel OOM took nvidia-persistenced down; NVRM `NV_ERR_NO_MEMORY`). Root cause = GB10 **unified memory**: 0.93 ≈ 113 GiB GPU reserve + ~57 GiB CPU PLE mirror ≈ 170 GiB on a 121.62 GiB pool. Fix: `gpu_memory_utilization 0.70` (≈85 GiB), memory cage `105G` (relapse kills container only, not the driver), `max_model_len 65536` (64k; KV ~112k tokens fits). **Engine now boots stable + healthy**: /:8000 200, warmup returns reasoning tokens. **B1 sanity certified C1×2 + C2×2** (harness fixed for the `vllm bench serve` CLI; see [BENCHMARK-PLAN §9](../spark/BENCHMARK-PLAN.md)). ⏳ **C3 (12×8k@c3) OOM'd the host at 02:50** (NVRM memdesc + global OOM; the vLLM container survived the cage; sshd/NetworkManager/polkitd died → box wedged until sshd revived) — harness now defaults C3→6×8k@c2 with a `MEM_FLOOR_GB` preflight; C3×2+warm re-run pending → merge `session/spark-b1-memfit` certifies `spark-ai.enabled: true`.


> **Headless + dashboard (HD-364, 2026-09-14):** the sleep-mask + multi-user default.target are now enforced **from IaC** (`spark_headless: true` in `host_vars/spark.kogler.si.yml` / `group_vars/spark.yml`; role `roles/spark` masks `sleep/suspend/hibernate/hybrid-sleep` + `systemctl set-default multi-user.target`). The NVIDIA **DGX Dashboard** (loopback-only, `dgx-dashboard.service` :11000) AND its integrated **JupyterLab** (admin user :11002, per `jupyterlab_ports.yaml`) are exposed on the LAN via a **Traefik file-provider edge on spark** (HD-364 rework; registry service `spark-dashboard` — host-net, entrypoints `{{ spark_home_ip }}:11000`/`:11002` → `127.0.0.1:11000`/`:11002`, pinned `traefik_version`; replaced the original alpine/socat bridge, which crash-looped on reboot with "exactly 2 addresses required (there are 4)" — socat takes ONE address pair per invocation and the compose `command:` list handed it all four). Reach them at `http://spark.kogler.si:11000` (Home VLAN) with a local user login; admin's JupyterLab = `http://spark.kogler.si:11002`. Details: §Remote management.
>
> **Dashboard LAN edge FIXED + LIVE (2026-09-15):** `http://spark.kogler.si:11000` serves the real dashboard HTML **200** (LAN client verified; `traefik-spark` **healthy**, `traefik healthcheck --ping` passes). Root cause of the 404: the routes used a **`HostRegexp({host:.+})` catch-all rule that silently matched nothing** (Traefik's own "404 page not found") — likely because Traefik v3 host-matching on IP-host requests doesn't treat the catch-all as applying; **the fix is an explicit `Host(spark.kogler.si)` rule** (name-based; same pattern as the oldsrv home edge). IP-host requests (`curl http://spark.kogler.si:11000/` via the raw Home IP) are expected 404 — they don't match the Host rule; the browser hits the name and works. Secondary fixes in the same change: (1) spark role now sets `net.ipv4.ip_nonlocal_bind=1` (headless-gated, `sysctl.d/dgx-lan-bind.conf`) so the LAN bind `spark_home_ip:11000/11002` is deterministic at container start (was EADDRNOTAVAIL until the interface settled); (2) removed the stale duplicate `healthcheck:` block (`wget …:8080`) that overrode the correct `["CMD","traefik","healthcheck","--ping"]` → container now reports healthy; (3) re-render landed `--api.insecure`/`--ping` in the live command (the debug API is at `127.0.0.1:8080` — the built-in `traefik` entrypoint, not 11000). Legacy crash-looping `dgx-dashboard-socat` container removed. Jupyter :11002 intentionally NOT touched (owner instruction; its entrypoint stays, untested).

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

`spark` runs headless (no monitor, no desktop) as the homelab's **big-model generation tier** behind
the **NVIDIA Triton Inference Server** (`nvidia/tritonserver`), serving the NVFP4 generation set below.
**Spark is the homelab's big-model generation tier** (2026-09-06 decision #23, **refined 2026-09-15
decision #24**): the large generation models run here via Triton — **one big model with the largest
context** (Qwen3-Coder-Next-80B, 262k ctx via SGLang). The small pinned services (Whisper STT, bge-m3
embed, bge-reranker) **moved to the oldsrv RX 7600** (decision #24). It complements — does not replace —
the VPS AI *spine* (LiteLLM/Qdrant/OWUI), but it **replaces** the oldsrv Ollama GPU tier (no host Ollama/
AMD-noble ROCm on oldsrv). oldsrv's RX 7600 dGPU now runs **pinned AI (STT/embed/rerank) + Sunshine
gaming-encode + immich-ML batch (lowest priority)** — the containers bundle their own ROCm runtime
(owner correction 2026-09-09, decision #24 2026-09-15).

### Model set (NVFP4 / local, all fit within 128 GB unified memory)

| Model | Size (NVFP4) | Role |
|-------|-------------|------|
| **NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4** | ~30B (3B active, MoE/Mamba) | fast reasoning / default chat |
| **Qwen3-Next-80B** | ~80B | general instruction following |
| **Llama-3.3-70B-Instruct** | ~70B | general chat / RAG answer |
| **Qwen3-Coder-Next-80B** | ~80B | code generation |
> **Moved to oldsrv RX 7600 (decision #24, 2026-09-15):** bge-m3 embed + bge-reranker + Whisper STT
> now run on the oldsrv RX 7600 (container-bundled ROCm, ≈5–6 GB of 8 GB). Piper TTS stays CPU
> (CPU-only engine). spark keeps only the **generation** set below.

> **Embeddings (2026-09-06, placement refined 2026-09-15):** bge-m3 (1024-dim) + bge-reranker-v2-m3
> **replace Cohere entirely** — the `cohere_api` subscription is retired. **Nothing is RAG'd yet**, so
> the Qdrant dimension lock (1536→1024) costs nothing now; embed/rerank run on the oldsrv RX 7600
> (decision #24).

## Planned services

Two new service-onboarding candidates land with spark (see `services-ai.md`):

1. **Mem0** — long-term memory for Open WebUI, backed by the existing **Qdrant** vector store
   (HD-267/268). Per-user/per-project scoping via a custom `user_id` = `<openwebui_user_id>-<model_id>`.
2. **OpenHands** — agentic coding harness (a third coding cockpit alongside pi.dev + DSH, HD-307/250).

## Bring-up plan (HD-337, 2026-09-06; updated 2026-09-14 — folded into IaC)

> **IaC status (2026-09-14):** spark is now a **first-class IaC host** — not a standalone
> `spark/ansible` project. Inventory group `spark` + `host_vars/spark.kogler.si.yml` + the
> `spark` role (NVMe p3 → XFS for PLE/KV, HD-363 — p2 is the live root!) + `playbooks/spark.yml` exist; reserved statics
> live in `network_static_hosts` (SSOT — mounted via `spark_home_ip`/`spark_mgmt_ip`, never
> literal here). The engine-neutral
> bench plan + research live in [`../spark/BENCHMARK-PLAN.md`](../spark/BENCHMARK-PLAN.md) and
> [`../spark/resources/RESEARCH-VERDICTS.md`](../spark/resources/RESEARCH-VERDICTS.md). The
> standalone `spark/ansible` tree remains the **reference/template** implementation.

Order of execution at node bring-up (spec lives here; todo.md HD-337/HD-359 are the pointers):

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
   set (Nemotron-30B, Qwen3-Next-80B, Llama-3.3-70B, Qwen3-Coder-Next-80B). **The small pinned
   services (bge-m3 embed, bge-reranker, Whisper STT) moved to the oldsrv RX 7600 (decision #24,
   2026-09-15); Piper TTS stays CPU.**
   - **Strict repo layout** rendered by the role: `/srv/models/spark/triton/<model>/1/{model.nvfp4,…}`
     (version dir `1/`), per-model `config.pbtxt` as **J2 templates** (backend: tensorrt_llm/vllm vs
     ONNX; input/output tensor names, `max_batch_size`, instance_group, dynamic batching — version-
     sensitive, error-prone-by-hand → must be rendered, never hand-touched).
   - **Conversion pipeline**: role pulls base weights → runs NVFP4/engine converter (llm-compressor/
     TensorRT-LLM) **idempotently** (skip if engine artifact exists), tagged per model — a heavy,
     human-gated first-boot step (like render→review→apply), not a blind one-shot.
   - **Residency policy** (generation on-demand; pinned services on oldsrv RX 7600, decision #24)
     rendered into `config.pbtxt` scheduling + Triton model-control config — the role owns the
     baseline; tuning is config (like `versions.yml`), not deployment.
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
- **Reserved statics (2026-09-14, SSOT `network_static_hosts`):** Home VLAN (SSH + inference endpoint)
  + Mgmt VLAN (management plane) — referenced via `spark_home_ip`/`spark_mgmt_ip`, never literal.
  MAC learned from the live lease at first boot 2026-09-14 (Home VLAN 10); authored into
  `network_static_hosts` (VLAN-10 row). **HD-367 (2026-09-14): the mgmt leg rides the SAME single
  NIC (enP7s7) — Home untagged + Mgmt VLAN-99 tagged via NM dual-home** (the VLAN-99 SSOT row
  carries the same MAC as VLAN-10; VLAN subinterfaces share the parent NIC MAC). The old "mgmt
  NIC not cabled" note is OBSOLETE — there is NO second NIC. Router-side: the `dhcp-mgmt` static
  for spark's mgmt IP renders in the converge template (standard `render-converge.yml`→/import).
- Connects via **10 GbE** to the LAN (Home/Mgmt per the router port model); IP/reservation SSOT to be
  added to `network_static_hosts` at provision time (never hardcoded).
- Exposes the Triton gRPC/HTTP endpoint on the `llm-backend` overlay (or a `triton-backend` net),
  reachable **only by LiteLLM** — same isolation model as Ollama (HD-59). No host port binds.
- 2× QSFP ConnectX-7 ports reserved for a future 2-node scale-out (to 405B models) — not used now.

## Remote management

- Headless by design: no display, no local desktop. Managed over the LAN (SSH/Ansible) + the mgmt plane.
- **Headless contract (HD-364, IaC-enforced):** the `spark` role masks `sleep/suspend/hibernate/
  hybrid-sleep.target` + sets `default.target = multi-user` whenever `spark_headless: true`
  (host_vars/group_vars default; set false on a desktop-style DGX box to leave GDM + sleep as shipped).
  The old one-time MANDATORY manual step (deployment-manual.md §5.2) is now idempotent IO.
- **DGX Dashboard on the LAN (HD-364):** NVIDIA ships the dashboard bound to loopback only (no
  bind flag; remote access officially = SSH tunnel / NVIDIA Sync). The `spark-dashboard` Traefik
  sidecar (host-net, pinned `traefik_version`) publishes `spark_home_ip:11000 → 127.0.0.1:11000`
  = dashboard reachable at `http://spark.kogler.si:11000` on the Home VLAN with a local-user login
  (the dashboard's own auth sits in front; never 0.0.0.0 — Home-VLAN-only, no public record;
  its Software-Update flow still requires the SSH-tunnel path). Disable by setting the registry
  entry `enabled: false`. (Originally an alpine/socat bridge (`dgx-dashboard`); replaced because
  one socat argv = exactly ONE address pair, so the four-argv compose list crash-looped on
  reboot — Traefik file-provider has none of that fragility.) **Live fix 2026-09-15 (404 → 200):**
  the routes file used `HostRegexp({host:.+})`, which matched nothing on this v3.7 Traefik →
  own 404 for every request incl. `/api`/`/ping`… replaced with an explicit
  `Host(spark.kogler.si)` rule (name-based; IP-host requests 404 by design); the spark role also
  sets `net.ipv4.ip_nonlocal_bind=1` (deterministic LAN bind) and the stale duplicate
  `:8080`-probing healthcheck was removed in favor of `["CMD","traefik","healthcheck","--ping"]`.
  Reach it at **`http://spark.kogler.si:11000`** (not the IP — the Host rule needs the name).
- **JupyterLab on the LAN (HD-366):** the dashboard ships an **integrated JupyterLab** whose per-user
  ports are in `/opt/nvidia/dgx-dashboard-service/jupyterlab_ports.yaml` (nobody 11001 / **admin
  11002** / ansible-admin 11003). NVIDIA's remote path is a second SSH tunnel per assigned port.
  The same `spark-dashboard` Traefik edge ALSO publishes `spark_home_ip:11002 → 127.0.0.1:11002`
  (admin's port; add more ports by appending entrypoint+route pairs in the template). JupyterLab
  spawns **on demand** from the dashboard's JupyterLab panel (Start) — until a lab is Running,
  loopback:11002 has no listener and the route idles (healthcheck stays on :11000 only). Once
  Running, browse to `http://spark.kogler.si:11002` on the Home VLAN; auth is the dashboard's
  local-user login in front of the same loopback policy as :11000.
- **GB10 bring-up reference:** [`martimramos/dgx-spark-ml-guide`](https://github.com/martimramos/dgx-spark-ml-guide) —
  PyTorch-nightly (sm_121), no ARM64 wheels, CPU/Python gotchas; run ML **container-native** (Docker
  isolates CUDA/Python — the guide's own recommended path).
- 240 W USB-C PD power; check UPS coverage on the rack (PowerWalker VFI ICT/ICR IoT 3000, `hardware-ups.md`).

## Benchmark / engine selection (2026-09-14)

spark serves Qwen3.8-Flash-Next under four serving profiles (S1–S5, engine-neutral). The engine is
**not pre-decided** — vLLM and SGLang are benched apples-to-apples on this box and the winner per
profile gets promoted into the SSOT. Full plan: [`spark/BENCHMARK-PLAN.md`](../spark/BENCHMARK-PLAN.md).
Research + verdicts: [`spark/resources/RESEARCH-VERDICTS.md`](../spark/resources/RESEARCH-VERDICTS.md).
- **vLLM**: the 98/100 AWQ+PLE accuracy recipe is vLLM-only (PLE n-gram overlay); NVFP4 on GB10 has an
  upstream Marlin fallback gap (#50925).
- **SGLang**: native-GB10 NVFP4 route (262k ctx); long-context concurrency (S5) fits its pool semantics.
- Bench runs on the box once provisioned (deploy-gate); until then configs stay uncommitted to SSOT.

## Document Map

| For | Read |
|-----|------|
| GPU resource / VRAM / modes | [`hardware-gpu.md`](hardware-gpu.md) |
| AI platform (Triton, models, Mem0, OpenHands, LiteLLM) | [`services-ai.md`](services-ai.md) |
| Local LLM model guidance | [`services-ai.md`](services-ai.md) |
| Network / VLAN placement | [`network-vlans.md`](network-vlans.md) |
| Spark benchmark + engine bench plan | [`spark/BENCHMARK-PLAN.md`](../spark/BENCHMARK-PLAN.md) |
| Old superseded Phase-2 build | archived decision log ([`deployment-rejected.md`](deployment-rejected.md)) |
