---
title: spark — Lenovo ThinkStation PGX (NVIDIA GB10 Grace Blackwell)
role: detail
domain: hardware
status: active
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
> **S1 stability sweep COMPLETE + LIVE (2026-09-15, `session/s1-stability-sweep-20260915-0801`):** max servable util **0.82** (0.84/0.86 crash engine during serve — host wedge, power-cycle needed; 0.88 no headroom); max ctx **262,144** = model native max_position_embeddings (300k rejected at startup validation — would need `VLLM_ALLOW_LONG_MAX_MODEL_LEN` + YaRN, needle-gated). **Live config = 0.82 util / 262k ctx / cage 105G** (SSOT `group_vars/spark.yml`). Certified: 250k@95% fill 0 preemptions; acc-gate 8/10 serial + 8/10 concurrent-3; concurrency accuracy holds. **⚠️ Pending before full production trust:** needle-test at 262k (long-context correctness, QSA/XQA trap ≥120k), tool-call EMPTY fix (no tools registered), true 3×87k-token fill stress, NVFP4/SGLang lane (S2/S3, the fast-on-GB10 config). **Verdict: production-ready for casual/chat inference now; agentic/max-context work gated on the pending tests.**
>
> **Name edge + OpenAI-API (HD-370, LIVE 2026-09-15, commit `362f9d9`):** `traefik-spark` is the NAME edge — `db-spark.kogler.si` (dashboard) + `llm.kogler.si` (OpenAI-API) on **:443** (TLS from a pulled wildcard pair, cert CONSUMER — Pi/oldsrv pattern) + HSTS; :80 is redirect-only. The engine binds loopback `spark_engine_port` (8000 today; SGLang port later) + serves `spark/qwen3.8-flash-next` with `--api-key` from the `spark-llm_api` vault item. VPS/tailnet reach **over WG S2S** (spark in `wg_s2s_vps.allowed_ips` + router `vps_scoped_home`) — the tailnet edge routes `db-spark`/`llm` (+`.ts`) → `https://spark_home_ip:443` (TLS-in-TLS). LAN only: spark's own edge. **HD-389 (2026-09-18, LIVE):** the spark edge now ALSO routes the `.ts` twin names (`llm.ts.kogler.si` / `db-spark.ts.kogler.si`) + serves the `*.ts.kogler.si` wildcard pair from the default store — the tailnet edge TLS-in-TLS-forwards the client's SNI, so the `.ts` names previously hit a routerless vHost on this edge (live 404, `todo HD-389`). **Live-verified 2026-09-15:** the TLS-in-TLS hop works end-to-end (tailnet edge :4443 with the bearer key → `/v1/models` returns `spark/qwen3.8-flash-next`); the old 500 'x509: no IP SAN' is fixed via the `spark-tls-in-tls` serversTransport (insecureSkipVerify on the spark backends); the VPS→spark WG route was missing (`wg set` installs no kernel routes — the wireguard oneshot now `ip route replace`s every AllowedIPs /32). DNS split-horizon: `llm`/`db-spark`/`spark` resolve to spark on the home instances only; the VPS primary never answers them. ✅ **Model entries LANDED 2026-09-17 (HD-382):** `spark/qwen3.8-flash-next` is registered in BOTH LiteLLM DBs (`api_base https://llm.kogler.si/v1`, no key in the row — the bearer is the container `OPENAI_API_KEY` env from `spark-llm_api`, name via `extra_hosts`); ⏳ Remaining: the LAN bootstrap-keys glue aborts rc2 on a stale `dsh` secret (**HD-383**, every `lan-litellm` converge is red until the owner remediates) + spark is not yet in any scoped-key allowlist (**HD-384**).


> **Headless + dashboard (HD-364, 2026-09-14):** the sleep-mask + multi-user default.target are now enforced **from IaC** (`spark_headless: true` in `host_vars/spark.kogler.si.yml` / `group_vars/spark.yml`; role `roles/spark` masks `sleep/suspend/hibernate/hybrid-sleep` + `systemctl set-default multi-user.target`). The NVIDIA **DGX Dashboard** (loopback-only, `dgx-dashboard.service` :11000) AND its integrated **JupyterLab** (admin user :11002, per `jupyterlab_ports.yaml`) are exposed on the LAN via a **Traefik file-provider edge on spark** (HD-364 rework; registry service `spark-dashboard` — host-net, entrypoints `{{ spark_home_ip }}:11000`/`:11002` → `127.0.0.1:11000`/`:11002`, pinned `traefik_version`; replaced the original alpine/socat bridge, which crash-looped on reboot with "exactly 2 addresses required (there are 4)" — socat takes ONE address pair per invocation and the compose `command:` list handed it all four). Reach them at `http://spark.kogler.si:11000` (Home VLAN) with a local user login; admin's JupyterLab = `http://spark.kogler.si:11002`. Details: §Remote management.
>
> **Dashboard LAN edge FIXED + LIVE (2026-09-15):** `http://spark.kogler.si:11000` serves the real dashboard HTML **200** (LAN client verified; `traefik-spark` **healthy**, `traefik healthcheck --ping` passes). Root cause of the 404: the routes used a **`HostRegexp({host:.+})` catch-all rule that silently matched nothing** (Traefik's own "404 page not found") — likely because Traefik v3 host-matching on IP-host requests doesn't treat the catch-all as applying; **the fix is an explicit `Host(spark.kogler.si)` rule** (name-based; same pattern as the oldsrv home edge). IP-host requests (`curl http://spark.kogler.si:11000/` via the raw Home IP) are expected 404 — they don't match the Host rule; the browser hits the name and works. Secondary fixes in the same change: (1) spark role now sets `net.ipv4.ip_nonlocal_bind=1` (headless-gated, `sysctl.d/dgx-lan-bind.conf`) so the LAN bind `spark_home_ip:11000/11002` is deterministic at container start (was EADDRNOTAVAIL until the interface settled); (2) removed the stale duplicate `healthcheck:` block (`wget …:8080`) that overrode the correct `["CMD","traefik","healthcheck","--ping"]` → container now reports healthy; (3) re-render landed `--api.insecure`/`--ping` in the live command (the debug API is at `127.0.0.1:8080` — the built-in `traefik` entrypoint, not 11000). Legacy crash-looping `dgx-dashboard-socat` container removed. Jupyter :11002 intentionally NOT touched (owner instruction; its entrypoint stays, untested).
>
> **Unified-memory budget governance + explicit KV-pool sizing — 2026-09-16 (`session/hd373-vllm-oom-20260916`):** a third global-OOM in 24 h (2026-09-16 09:26 UTC — the engine's own session, 502s, including this repo's tooling) is now root-caused with measured numbers and a durable fix is selected. The mechanics live in **§Unified-memory budget & OOM governance** below; the dated incident records live in **[spark-incidents.md](spark-incidents.md)** (append-only). Implemented as IaC in `group_vars/spark.yml`: **`spark_vllm_kv_cache_memory: "8800000000"` (8.8e9 bytes ≈ 8.2 GiB ≈ 275k tok) as the ONLY governor, `--gpu-memory-utilization` REMOVED (this build ignores it when `--kv-cache-memory-bytes` is set), `max_model_len` unchanged at 262,144** — replace-by-percentage arithmetic is the root defect, not the workload. **0.82 util was certified for casual/chat only — it is NOT survivable for sustained agentic/window-heavy inference.**
>
> **✅ Peak-bound CERTIFIED + KV pool raised 8.2 → 16 GiB and promoted to the stable config (2026-09-18, `session/spark-stability-20260918-0000`):** the load test that answers the question the whole OOM lane was built to answer — *does C1+C2 actually bound the peak, under the traffic shape that produced incidents #1–#8?* — **PASSED**. Runbook [`../spark/stability-test.md`](../spark/stability-test.md), evidence [`../spark/reports/stability/`](../spark/reports/stability/README.md).
>
> * **The load was real:** 3 rungs, 59 steps, all `ok=N/N`. `rung123` (18 shape-churn steps + prefill rungs 2/3/4 concurrent × 49,152 tok = **196,816 tok in flight**) → `compact` (2 × 200,000 = **400,105 tok**, ~77 % of the pool) → `fullwindow` (2 × 240,000 = **480,105 tok ≈ 94.6 % of the 16 GiB pool** — two fresh full-context sessions, nothing cached: the pessimal real-world shape).
> * **The host never blinked:** `invoked oom-killer` **3 → 3** (no new), engine `RestartCount` **0 → 0**, guard-fires **0**, reboots **0**, `/health` **200** at the end.
> * **The peak is bounded (this is the verdict that was missing):** engine top-pid **92,343 → 93,621 MiB = +1,278 MiB across ~1.5 h of the hardest shape**, against the pre-governor **88,773 → 109,785 MiB (+21,012 MiB) in ~30 min of one light session**. The §4 C3 trigger (>2 GiB/h under traffic AND no return at idle) is **not** met → **`--enforce-eager` stays off**, and it is now a measured call rather than an inference from a 3.5 h idle-ish curve.
> * **`usable` worst moment 17.78 GiB** (idle 18.84 → 24.88 after) vs the **12 GiB reserve target**, with both historical kills at **1.62/1.64**. Margin: 5.8× the kill point.
> * **KV ceiling found, and it is boot, not runtime:** the run's own arithmetic gives runtime **+5.5 GiB** and boot-side **+5.4 GiB** ⇒ **16 GiB is the practical bf16 ceiling; do not raise further.** The next byte of KV must come from `--kv-cache-dtype fp8` (≈2× tokens for the same GiB, unvalidated on this hybrid+MTP build), not from Linux's reserve.
> * **Costs paid, recorded honestly:** idle `usable` fell **30.5 → 18.5 GiB** (margin to the WARN 12 line is now 6.5 GiB, not 18), and `NV_ERR_NO_MEMORY` **234 → 243 (+9)** across the run (boot-load burst unchanged in character). Under the 94.6 % shape the engine served it but slowly: **mean TTFT 631 s**, MTP acceptance **20.6 %** (35–44 % at small batch) — capacity/latency, not safety.
> * **Harness fix that came out of reading the numbers (stability-certify close-out, 2026-09-18):** the bench guard's floors ran on **raw `MemAvailable`**, the falsified gauge — it would have `GUARD FIRE`n a **healthy** box at usable 18.5 (MemAvailable dips read low) and read healthy at **10.4 GiB** when incidents #7/#8 were actually at usable **1.6**. Both bench guards (`stress-oom.sh`, `run-scenario.sh`) + the chain preflight now gate on **`usable = MemAvailable − CmaFree`** at **16 GiB**, one gauge with the watchdog and the alert rules. Measured margin, not guesswork: the passing run's worst moment (17.78) sat **0.72 GiB** above that floor.
> * **ID collision, recorded so nobody re-derives it:** this work was registered in todo.md as "HD-389"
> (`f5c3f85`, 2026-09-17 23:26) while a parallel worktree was landing the spark name-edge `.ts` fix under
> **the same ID** (`ef7c4f3`, live state in §Name edge + [network-vpn.md](network-vpn.md)) — two sessions
> both took the next free ID. Resolution: **HD-389 = the name-edge fix** (it owns the docs); this stability
> lane is **closed with no HD row of its own** (CONVENTIONS §4(a) — the row was deleted on 2026-09-18), and
> its record is this section + [`../spark/stability-test.md`](../spark/stability-test.md) +
> [`../spark/reports/stability/README.md`](../spark/reports/stability/README.md). Do not file new work as 389.
> * **Still open (unchanged by this PASS):** the 262k **needle test**, the `spark-lane` 64 k profile, and the tool-call/accuracy tails — see HD-376/HD-367. The PASS certifies *memory safety*, not long-context correctness.


---

## Unified-memory budget & OOM governance (2026-09-16)

> **Why this section exists:** spark is a **unified-memory** appliance — there is no separate VRAM. Every
> GPU allocation is physically the same 121.62 GiB LPDDR5x pool the OS, Docker, Alloy and the DGX
> dashboard run in. Three global-OOM incidents in 24 h (2026-09-15 ×2, 2026-09-16 ×1) all came from the
> same missing governance: **vLLM's percentage budget silently consumed the host's reserve, and the
> kernel global OOM killer — not the container memory cage — decided what died.**

### The measured allocation arithmetic (source: vLLM boot log, 2026-09-15 restart)

vLLM prints its full accounting at startup (`gpu_worker.py:919`); these are the real numbers for the
B1 engine (Qwen3.8-Flash-Next AWQ+PLE+MTP3, Qwen `compressed-tensors`) with `gpu_memory_utilization: 0.82`:

```
Device total                                     121.62 GiB   (MemTotal = 127,532,360 kB)
Free at startup                                  114.70 GiB   (~6.9 GiB already held by OS/driver/dashboard)
Budget   = util × total = 0.82 × 121.62           99.73 GiB
  ├─ weights + non-torch                          77.69 GiB   FIXED — independent of util
  ├─ peak activation                               2.99 GiB   FIXED — driven by max_num_batched_tokens=16384
  └─ CUDA graphs                                    0.22 GiB   FIXED
Fixed cost                                        80.90 GiB
KV pool  = 99.73 − 80.90                          19.04 GiB  → 658,902 tokens  (30.3 KiB/token)
Actual usage reported                             77.69 GiB consumed + 2.99 peak + 0.22 graphs
Reserve left for Linux = 121.62 − 99.73           21.89 GiB
```

### The rule that governs this box

```
KV_pool_bytes = util × 121.62 GiB − 80.90 GiB        (percentage form — replaces memory the host needs)
KV_pool_bytes = --kv-cache-memory-bytes <bytes>    (explicit form — the correct governor here)
Host_reserve  = 121.62 GiB − (80.90 GiB + KV_pool)
```

Two consequences, both non-obvious and both previously misread:

1. **`max_model_len` costs nothing.** It is *not* an allocation — it is only a **boot-gate validation**
   (`pool_tokens ≥ max_model_len`, else `ValueError`). The KV *pool* is whatever the budget leaves over,
   sized in blocks. Raising ctx from 64k to 262k changed the pool by zero bytes; the engine merely
   refuses to boot if the pool cannot hold `max_model_len` tokens. So "less ctx" and "lower util" are not
   the same lever — lowering util cannot be traded for ctx.
2. **The container memory cage cannot protect the host.** GB10 `cuMemAlloc` pages are **not charged to the
   container cgroup** — at diagnosis `docker stats` reported the engine at **4.267 GiB / 105 GiB (4%)**
   while the host was at **112 GiB used**. The `deploy.resources.limits.memory: 105G` cage therefore never
   triggers; the kill is always `constraint=CONSTRAINT_NONE ... global_oom`, and Docker reports
   **`OOMKilled: false` + `ExitCode: 0`** (Docker only flags cgroup `memory.max` kills). **A `docker inspect`
   showing `OOMKilled=false` on this host is a false negative — always read `dmesg`/`journalctl -k`.**
3. **`kv_cache_memory_bytes` IGNORES `gpu_memory_utilization` entirely in this build** (verified in the
   container's own source): `CacheConfig` docs "kv_cache_memory_bytes (when not-None) ignores
   gpu_memory_utilization", and `gpu_worker.determine_available_memory()` short-circuits to
   `reserve_mm_ipc_gpu_memory(kv_cache_memory_bytes, …)` — "This does not respect the
   gpu_memory_utilization config". So once the explicit pool is set, **util is dead config**; keeping it
   is a false sense of a ceiling. The engine still loads weights/activations/graphs, then reserves
   exactly `<bytes>` of KV on top — capped only by physical free at startup.
4. **The recognized flag in this build is `--kv-cache-memory-bytes`** (an `int`, bytes) — NOT
   `--kv-cache-memory` (which does not exist here; passing it would be an unknown-arg argv crash).

### Restart-count semantics (how to tell a kill from a redeploy)

- `RestartCount` increments when the **same container** is re-exec'd by the restart policy → a host-side
  kill or process exit. The container ID is unchanged.
- A compose **replacement** creates a *new* container → the counter resets and
  `com.docker.compose.replace` is set. Distinguish before attributing a restart to OOM.
- Engine restart history is additionally countable from the boot banner: `docker logs --timestamps
  <ctr> | grep 'version 0.1.dev'`. On 2026-09-16 that showed 3 starts (11:52 UTC initial, 22:31 UTC #1,
  23:06 UTC #2) plus the 09:26 UTC #3 kill → `RestartCount=3`.

### Sizing table — util → pool → host reserve (reference; fixed cost 80.90 GiB, 30.3 KiB/token)

Used to pick the pool for the chosen governor (below). **Decision = KV pool bytes, not util.**

| util | budget GiB | KV pool GiB | KV tokens | conc @262k | host reserve | verdict |
|------|-----------|-------------|-----------|------------|--------------|---------|
| 0.82 | 99.73 | 18.83 | 651,579 | 2.49× | 21.9 GiB | **was live — OOM'd under agentic load** |
| 0.80 | 97.30 | 16.40 | 567,403 | 2.16× | 24.3 GiB | marginal |
| 0.78 | 94.86 | 13.96 | 483,227 | 1.84× | 26.8 GiB | ok |
| **0.75** | **91.22** | **10.32** | **356,962** | **1.36×** | **30.4 GiB** | **≈ the 8.2 GiB pool below, via util** |
| 0.74 | 90.00 | 9.10 | 314,900 | 1.20× | 31.6 GiB | floor with margin |
| 0.73 | 88.78 | 7.88 | 272,786 | 1.04× | 32.8 GiB | razor thin — no slack for a 2nd request |
| 0.7275 | 88.47 | 7.58 | **262,144** | 1.00× | 33.1 GiB | **hard boot floor for 262k** |
| 0.72 | 87.57 | 6.67 | 230,698 | 0.88× | — | **REFUSES TO BOOT @262k** |
| 0.70 | 85.13 | 4.23 | 146,522 | 0.56× | — | **REFUSES TO BOOT @262k** |

> **0.70 was never a "less context" setting — it is a crash-on-start setting** for a 262,144 config:
> `ValueError: The model's max seq len (262144) is larger than the maximum number of tokens that can be
> stored in KV cache (146522)`. (0.70 was correct on 2026-09-15 only because `max_model_len` was 65536
> at the time.) These are two coupled dials and must be changed together.

### ⚠ Correction — the 2026-09-16 budget model was falsified the same day (HD-380)

The "reserve ≈ 32.5 GiB" figure below was **derived, never measured, and wrong**. Two more global
OOMs landed within hours of the HD-374 deploy (#4 with **no client attached**, #5 at 18% of window
combined). Measured at rest: engine per-pid **103,449 → 105,477 MiB** (ratcheting +2 GiB / 45 min
idle), host `MemAvailable` **16.7 GiB**, vLLM's own accounting only **83.4 GiB** → **~22 GiB
unaccounted**.

The `graphs 0.22 GiB` term was **wrong by ~40×**. This build captures CUDA graphs for batch sizes
**[1,2,4,8,16,24,32]**; `max_num_seqs=4` caps the decode batch at 4, so **8/16/24/32 are captured and
unreachable** — dead memory in the one pool host and GPU share.

**Governor now has TWO terms** (`group_vars/spark.yml`):

| term | value | effect (measured) |
|---|---|---|
| KV pool | `--kv-cache-memory-bytes 8800000000` | 8.2 GiB / 283,398 tok — fixed at boot, **never grows**, so `GPU KV cache usage %` is **scheduler occupancy, NOT RAM** |
| graph cap | `--max-cudagraph-capture-size 4` | per-pid **105,477 → 96,235 MiB**; `MemAvailable` **16.7 → 22.2 GiB** |

**Still the live defect:** ~**13 GiB** of non-KV, non-weight allocation remains unprofiled and
unbounded — `--kv-cache-memory-bytes` makes vLLM **skip memory profiling**, so nothing governs it.
The cap raised the *resting floor*; it did **not** bound the *peak* (incident #6 proves this).

### ⚠ Second correction — the budget METRIC was wrong too, and the “idle ratchet” was not a ratchet (HD-381, incidents #7/#8)

Two more global OOMs landed after the capture-size cap (#7 2026-09-16 23:26Z, #8 2026-09-17 14:55Z).
They falsified two more assumptions:

**1. `MemAvailable` / `free -h` is NOT the budget metric on GB10.** Both kills recorded `MemAvailable`
≈ 10.4 GiB while `CmaFree` was **8.81 / 8.78 GiB** — device-reserved CMA pages the allocator will not
give an unmovable `GFP_KERNEL` request (`Node 0 Normal free:9.63 GiB` with `free_cma:9.58 GiB`,
`all_unreclaimable? yes`). Claimable headroom at the kill: **1.64 GiB (#7) / 1.62 GiB (#8)**.

```
usable_gib = MemAvailable − CmaFree       # THE budget metric
  WARN  < 8 GiB      CRIT < 4 GiB        # + PSI memory (full avg10) as confirmation only
  kills observed at   1.64 / 1.62 GiB
  healthy idle measured 26.13 GiB usable (CmaFree 0.13 GiB)
```

`MemAvailable` is not merely optimistic here — it **inflates as the pressure rises**, because squeezing
the GPU carve grows `CmaFree` and CMA counts as available. That is precisely why the HD-375 alert rules
(24 / 16 GiB on raw `MemAvailable`) could never have warned usefully before the cliff, and why the
watchdog kept narrating after the fact. Any threshold on this box is expressed in
`MemAvailable − CmaFree`; the alert rules and the watchdog now agree on that one gauge.

> ⚠ **Rejected alternative, recorded so it is not re-proposed:** `usable = MemFree − CmaFree`
> (WARN 4 / CRIT 2), the form in the original HD-381 plan. Measured, it is **INVERTED**: 0.74 GiB at
> healthy idle vs 2.17 / 2.14 GiB at the two kills. `MemFree` is *supposed* to be ≈1 GiB at steady
> state; under pressure reclaim evicts page cache and `MemFree` **rises**, mostly into CMA. It tracks
> “reclaimed but unconsumed”, not headroom. On an enforcing watchdog those thresholds would
> **restart the engine continuously on a healthy box** — the safety net would have caused the outage.
> The ~0.05 GiB figure that motivated it is from the kernel's **per-zone** dump (`Node 0 Normal
> free:9.63 GiB free_cma:9.58 GiB`) and is not reconstructible from global `meminfo`.

PSI memory is a genuine trigger (`psi_full` 97.8 / 92.5 at the kill samples) but has **no lead time**:
in #8 it read **0.0 for ten consecutive samples** at avail 9.4 GiB and then the box died. Use it as
confirmation, never as the early warning.

**2. The growth is traffic-cumulative and FLAT at idle.** A fresh boot sat at engine top-pid **88,773 MiB
/ avail 24.2 GiB, unchanged from 23:35Z to 03:27Z overnight with no traffic**, then went
**88,773 → 109,785 MiB (avail 24.5 → 9.6 GiB)** under ~30 min of **one light pi session** (KV 43–59 %,
prefix hit 94 %, 0 % util at kill). HD-380 open item 5 (“idle ratchet”) is **retracted** — it was the
residue of prior traffic. Implications:

- The mechanism is **per-request allocator/graph growth that is never returned**, not KV occupancy and
  not a leak. Only a **restart** resets it; only **removing the mechanism** bounds it (C1
  `expandable_segments`, C2 prefill-chunk size, C3 eager).
- **A light session is enough** — session cost is not proportional to KV occupancy, so “small workload”
  is not a safety argument. Budget a session as a GiB-scale term, not a token-scale term.
- The pre-kill signature is a **frozen top-pid + saturating PSI** (109,681 / 109,785 MiB constant for
  4+ min while `psi_full` hit 97.8 / 92.5). An enforcing governor acts on that; a recorder does not.

**Boot-floor numbers (the baseline every future curve is compared against):**

| state | engine top-pid | `MemAvailable` | `usable = MemAvailable − CmaFree` |
|---|---|---|---|
| boot, weights loaded, no traffic (8.2 GiB pool) | 88,773 MiB | 24.2 GiB | healthy (flat overnight) |
| + ~30 min one light agent session | 109,785 MiB | 9.6 GiB | 1.6 GiB at kill (#8) |
| boot + C1/C2 applied (2026-09-17 15:28Z, 8.2 GiB pool) | 85,445 → 86,243 MiB | 26.9 GiB | 30.3 idle / **28.81 worst** under the pre-raise chain |
| **boot + C1/C2 + 16 GiB pool (2026-09-18, CERTIFIED baseline)** | **92,343 → 93,621 MiB (+1,278)** | 18.5 → 24.9 idle-after | **17.78 worst** under 2×240k ≈ 94.6 % pool |

> **Why the +1,278 MiB row is the important one:** it is the first *load*-certified number for the
> peak-bound question. Compare with the #8 row above it: the same class of box went **+21,012 MiB in
> ~30 min of one light session** before C1/C2, and **+1,278 MiB across ~1.5 h of the pessimal
> two-full-window shape** after. §"C3 decision rule" in
> [`../spark/stability-test.md`](../spark/stability-test.md) (§4) stays unsatisfied → `--enforce-eager`
> stays off, now on measurement.

**Two facts that must be carried into every future sizing calculation:**
1. **Per-pid `nvidia-smi` under-counts the engine by ~10 GiB.** True footprint = the `MemAvailable`
   jump when the engine stops: **12.6 → 118.6 GiB** ⇒ the engine held **~106 GiB** of 121.62.
2. **Agent sessions are a first-class memory term.** A ~162k-token session = **56% of the KV pool**,
   and at prefix hit **0%** every turn re-prefills the whole window (**17,008 tok/s** observed) — the
   largest transient on this box. Loop: big context → ~82% KV occupancy → own prefix blocks evicted →
   0% hit → full re-prefill → spike. Sizing for "casual/chat" occupancy (peak 15.5%, max 36,800 tok)
   is **not** representative of agentic use.

### Chosen governor (IaC, `group_vars/spark.yml`)

**Use explicit `--kv-cache-memory-bytes <bytes>` as the ONLY dial — and REMOVE `--gpu-memory-utilization`.**
The percentage form is *replace-by-percentage*: it always eats the headroom the host needs, on a box where
host and GPU share one pool. And in this build the two are mutually exclusive — once `kv_cache_memory_bytes`
is set, util is ignored (see consequence #3 above) — so keeping util is dead config and a false sense of a
ceiling.

> ✅ **LIVE-VERIFIED 2026-09-16** (detached converge, commit `3f2aab0` + `016a654`): engine boots with
> `kv_cache_memory_bytes=8800000000` (non-default args), `gpu_worker.py:621` logs the exact
> short-circuit ("reserved 8.2 GiB … skipped memory profiling. This does not respect the
> gpu_memory_utilization config"), KV pool **283,398 tokens** (1.08× @262k), `/health` 200, host
> `MemAvailable` 24 GiB during load (was ~9–13 GiB pre-fix). `RestartCount=0`, no `ValueError`/OOM.
>
> ✅ **SUPERSEDED 2026-09-18 — the pool is now 16 GiB and it is CERTIFIED, not just booted.** Same log
> signature at the new size (`Initial free memory 114.07 GiB, reserved 14.9 GiB … skipped memory
> profiling` → `GPU KV cache size: 515,786 tokens, Maximum concurrency … 1.97x`), then the 3-rung load
> chain passed against it: 0 kernel OOM, 0 engine restarts, 0 guard-fires, `usable` worst **17.78 GiB**,
> engine top-pid **+1,278 MiB** across ~1.5 h incl. **2×240,000-token** concurrent fresh prefills
> (≈ 94.6 % of pool). Evidence: [`../spark/reports/stability/README.md`](../spark/reports/stability/README.md)
> · runbook [`../spark/stability-test.md`](../spark/stability-test.md).
> **The headroom question is now closed for bf16: runtime +5.5 GiB, boot-side +5.4 GiB (binding) ⇒ 16 GiB
> is the ceiling. The next KV byte must come from `--kv-cache-dtype fp8`, not from Linux's reserve.**

```yaml
# group_vars/spark.yml  (this build's flag: --kv-cache-memory-bytes, bytes int)
spark_vllm_kv_cache_memory: "16000000000"  # 16 GiB nominal → reserved 14.9 GiB = 515,786 tok = 1.97× @262k. LIVE + CERTIFIED 2026-09-18 (was 8.2 GiB / 283,398 tok / 1.08×). Idle usable fell 30.5 → 18.5 GiB; boot-side allowance spent (+5.4 GiB left) — do NOT raise further in bf16.
spark_vllm_max_cudagraph_capture_size: 4  # graph term (HD-380): default [1,2,4,8,16,24,32] is unreachable above max_num_seqs and strands ~7 GiB of the shared pool
spark_vllm_max_model_len: 262144          # unchanged; boot-gate only
# spark_vllm_gpu_memory_utilization REMOVED — ignored when kv_cache_memory_bytes is set (HD-374)
```

> The compose arg is `--kv-cache-memory-bytes` — NOT `--kv-cache-memory` (which is not a flag in this
> build; passing it would be an unknown-arg argv crash, the `--swap-space` failure class).

- **Workload reality check (from the logs):** the largest context ever served was **36,800 tokens** and
  peak occupancy was **15.5%** — the pool was 658,902 tokens serving ~102k tokens of actual work. Pinning
  ~275k tokens covers 262k with block-rounding margin and returns ~8 GiB to Linux.
- **If 262k is not actually needed**, `--max-model-len 65536` (or 131072) lets the KV pool shrink
  further (its size is a choice, not a consequence of util — util is gone) and gives even more host
  relief; ctx length costs nothing in bytes, so capping it is free.
- **Do not rely on the OOM killer to pick politely.** It does not: on 2026-09-16 it killed the user-slice
  session (`pipewire`, `dbus`, `systemd`) before the engine, and in the earlier C3 incident it killed
  `sshd`/`NetworkManager`/`polkitd`, wedging the box until a power-cycle.
- **Swap is a symptom, not a fix:** 16 GiB file-backed swap on XFS, already 4–8 GiB in use; it is what
  produced the **~3.5 min log-write stall** during the incident (log lines with internal timestamps
  22:52–22:56 reached the json-file driver at 22:59:24). Consider zram only *after* the budget is fixed.

### Trailing risk — the 105 GiB cage vs the ~30 GiB reserve

`spark_vllm_memory_limit: 105G` is now **harmless but misleading**: it is above the whole non-GPU
budget, and (per point 2 above) the GPU allocation is not cgroup-charged anyway, so it can only ever
catch a *host-RSS* runaway (a secondary, rarer failure). It is retained as a backstop, **not** as the
protection it reads as. The real protection is the explicit KV-pool governor + a host `MemAvailable`
alert (see [observability.md](observability.md) §Alerting → spark host memory).

---

## OOM / restart incident log (append-only)

**Moved to [`spark-incidents.md`](spark-incidents.md) (2026-09-16)** — this section keeps the permanent
knowledge only; dated incident forensics (table + narratives + invariants + diagnosis recipe) live in the
append-only incident log. Same failure class through 2026-09-16: **global kernel OOM, not cgroup** —
`OOMKilled: false` / `ExitCode: 0` are false negatives on this box; always read `dmesg`. See
[spark-incidents.md](spark-incidents.md) §Diagnosis recipe.

---

## What replaced the old Phase 2

The previously-planned **Phase 2 target build** (`hardware-phase2.md`: AMD Ryzen 9 9900X + Radeon AI PRO
R9700 + Proxmox VE, ~€4,449) is **superseded** by this purchase. The ThinkStation PGX is a
purpose-built, single-socket NVIDIA Grace Blackwell appliance — far more compute per € for local
inference, no hypervisor layer needed, no AMD ROCm toolchain. The old build is archived in the
decision log (`deployment-rejected.md`) + git history.

## Hardware

> **Two tables on purpose.** §Vendor spec is what Lenovo/NVIDIA ship for MTM 30KL (PSREF + Lenovo
> Press LP2321). §As-measured is what THIS unit reports over `ssh spark` (capture **2026-09-16**,
> commands in §Capture commands). Measured wins for placement/perf planning; §Reality deltas names
> every disagreement.

### Identity (measured 2026-09-16)

| Field | Value | Source |
|-------|-------|--------|
| Vendor / model | Lenovo **ThinkStation PGX** (NVIDIA GB10) | `hostnamectl` Hardware Vendor/Model |
| Machine type (MTM) | `30KL0002GF` | `dmidecode -s system-product-name` (= `DGX_PLATFORM`) |
| **Serial number** | **`MP30A60N`** | `/etc/dgx-release` `DGX_SERIAL_NUMBER` = `sudo dmidecode -s system-serial-number` = `chassis-serial-number` |
| SKU string | `LENOVO_MT_30KL_BU_Think_FM_ThinkStation PGX` | `dmidecode -s system-sku-number` |
| Firmware | UEFI **`S0QKT0EA`** dated 2026-07-13 (AMI), UEFI boot, TPM 2.0 (`/dev/tpm0` v2) | `hostnamectl` / `dmidecode -s bios-version` |
| OS | Ubuntu **24.04.5 LTS** (noble), kernel `7.0.0-1019-nvidia` arm64 | `/etc/os-release`, `uname -mr` |
| DGX OS | base image **7.4.0** (swbuild 2026-01-26) → OTA **7.6.0** (2026-09-14) | `/etc/dgx-release` |
| GPU | UUID `GPU-d5ad56cc-01cf-7521-4c4e-e215e7ccd76b`, PCI id `10de:2e12` @ `000f:01:00.0`, driver **580.173.02** (`nvidia-driver-580-open`), compute cap **12.1** = **sm_121** | `nvidia-smi --query-gpu=...`, `lspci -nn` |
| CUDA / runtime | CUDA **13.0** (`/usr/local/cuda-13.0`), `nvidia-container-toolkit` **1.20.0** | `ls -d /usr/local/cuda-*`, `dpkg -l` |
| machine-id | `a7c5519de45d4244be889d2af3749476` | `/etc/machine-id` |
| Ethernet MAC | `38:a7:46:78:13:97` (`enP7s7`; `enP7s7.99` shares it — VLAN subinterface) | `ip -br link` |
| Wi-Fi MAC | `ec:3a:56:cc:9f:70` (`wlP9s9`) — **DOWN**, unused on a headless box | `ip -br link` |

> **Reading the serial on this platform (not obvious):** `/proc/device-tree/serial-number` does
> **not exist** here (the PGX carries identity in SMBIOS, not the Jetson-style device-tree) and
> `/sys/class/dmi/id/product_serial` reads **empty without root**. Two reliable reads: `cat
> /etc/dgx-release` (`DGX_SERIAL_NUMBER=`) or `sudo dmidecode -s system-serial-number`.
> `dmidecode -s system-vendor` and every `board-*` string return **EMPTY** on this firmware — take
> vendor/model from `hostnamectl` ("Lenovo / ThinkStation PGX").

### As-measured hardware (2026-09-16)

| Component | Measured on this unit |
|-----------|----------------------|
| Superchip | NVIDIA **GB10** Grace Blackwell — one SoC, no discrete PCIe GPU |
| CPU | 20 cores / 1 socket arm64: **10× Cortex-X925** (max 3900 MHz) + **10× Cortex-A725** (max 2808 MHz); L1d + L1i 1.3 MiB each (20 inst.), L2 25 MiB (20 inst.), L3 24 MiB (2 inst.); **single NUMA node** |
| Unified memory | **128 GB LPDDR5 @ 8533 MT/s**, one soldered package (`DIMM0`; SMBIOS max capacity 128 GB → **not expandable**), **no ECC** (`Error Correction Type: None`). Usable pool = `MemTotal` 127,532,364 kB ≈ **121.62 GiB** (rest held by SoC/ATF) |
| Swap | `/swap.img` **16 GiB** on root ext4 (no zram) — it is inside the same unified pool, so it does not buy headroom |
| GPU function | `000f:01:00.0` driver `nvidia`; `memory.total` / `memory.used` / `power.limit` report **N/A** (unified memory — `nvidia-smi` does not account the pool); temp 51 °C, P0. Its `LnkSta x1 (downgraded)` is an SoC-integrated artifact, **not** a slot negotiation |
| NVMe (the only disk) | **SK hynix `HFS001TEM4X169N` 1 TB** (`1c5c:1f69`), S/N `5SF1N437313401M59`, FW `61700A30`; by-id `nvme-eui.ace42e00650eb44a` = `nvme-SKHynix_HFS001TEM4X169N_5SF1N437313401M59`; **PCIe 4.0 ×4 at full 16 GT/s** |
| Partition layout | `p1` 512 M vfat → `/boot/efi` · `p2` **450 G** ext4 → `/` · `p3` **503.4 G** xfs → `/mnt/spark_nvme` (HD-363 carve, `noatime,nodiratime`) — the whole disk, **no unallocated room** |
| NVMe SMART | PASS · Percentage Used **0 %** · spare 100 % · media/integrity errors **0** · written 996 GB / read 7.05 TB · **9 power-on hours**, **99 power cycles**, **8 unsafe shutdowns** (the documented wedges + power-cycles) · 48 °C (critical 87 °C) |
| Ethernet | **Realtek RTL8127** `10ec:8127` rev 05, driver **`r8127`**, iface `enP7s7`. Advertises 10000/2500/1000/100/10 — **partnered at 1000 Mb/s full-duplex** ⚠️ delta 1 |
| Wireless | **MediaTek MT7925** `14c3:7925` (Wi-Fi 7 class) on `wlP9s9` + BT module `13d3:3630` (IMC Networks) — radio DOWN |
| USB | 6× xhci controllers = **12 root hubs** (each pair: one 480 M USB-2 + one **20000 M/x2** USB4-class root); no `usb4`/thunderbolt bus devices registered |
| Display | one DRM connector `card0-Unknown-1` (HDMI 2.1a) — unused, headless |
| Scale-out ports | **nothing enumerated** — no Mellanox (`15b3`) PCI function, no `infiniband` device, no extra netdev; `mlx5_core`/`mlx5_ib` loaded but unbound ⚠️ delta 2 |
| Security | UEFI + **TPM 2.0** present. AES SED self-encryption of the NVMe is a **vendor claim** (PSREF) — no readable SED state via `nvme id-ctrl`, NOT verified |
| Power | 240 W USB-C PD 3.1 PSU (vendor spec). **No `/sys/class/power_supply` entry** — the OS cannot see the PSU at all; UPS coverage is rack-side only (`hardware-ups.md`) |

### Reality deltas vs vendor spec (measured 2026-09-16)

1. **10 GbE is not achieved on the wire.** The NIC advertises `10000baseT/Full`, link is up, but it
   negotiated **1000 Mb/s** (`/sys/class/net/enP7s7/speed` = 1000) — the limit is upstream (router /
   switch port or the patch path), not the box. Consequence is concrete: multi-hundred-GB weight
   staging (B1 = 169 G) over 1 G is the real staging cost. Check the switch port + cable rating.
   **Resolved 2026-09-17:** the upstream port is **RB4011 `ether8` = 10/100/1000** — the RB4011 has no
   10 G copper port, so 1 Gb/s is structural, not a cable fault. **Accepted as final** (owner): no 10 G
   device exists besides spark → no CRS328 move. See §Network / placement.
2. **No ConnectX-7 / QSFP function exists in the running system.** `lspci` shows **zero** Mellanox
   devices and two GB10 root ports (`0000:00:00.0`, `0002:00:00.0`) train at Gen1 x4 with **no device
   behind them** — the plausible QSFP positions. So the "2-node scale-out to 405B" line is **not
   usable today** (nothing to configure). Per Lenovo the QSFP pair is *PGX↔PGX clustering only*
   (cables sold separately), never general LAN connectivity — nothing else is lost. Re-check after a
   DGX OS / UEFI update: this may be a firmware or module-probe gap, not missing silicon.
3. **Storage is the 1 TB SKU**, not the 4 TB option — p2 (450 G) + p3 (503.4 G) is the entire device,
   so capacity planning must never assume the 4 TB figure.
4. **"LPDDR5x" vs SMBIOS "LPDDR5 @ 8533 MT/s"** — same soldered part, different label; PSREF quotes
   273 GB/s bandwidth. No action.
5. **`nvidia-smi` is not a memory gauge on GB10** (`memory.total`/`used` = N/A). Headroom math uses
   `MemTotal` (121.62 GiB) minus host usage — every `gpu_memory_utilization` incident above came from
   forgetting this.

### Capture commands (re-derive, read-only)

```sh
ssh spark 'cat /etc/dgx-release; hostnamectl; uname -mr'
ssh spark 'sudo dmidecode -s system-serial-number; sudo dmidecode -s system-product-name; sudo dmidecode -s bios-version'
ssh spark 'lscpu | grep -E "Model name|CPU\(s\)|MHz|L2|L3"; grep MemTotal /proc/meminfo; sudo dmidecode -t 16 -t 17'
ssh spark 'nvidia-smi --query-gpu=name,driver_version,uuid,compute_cap,temperature.gpu --format=csv'
ssh spark 'sudo nvme list; sudo smartctl -H -A /dev/nvme0; ls -l /dev/disk/by-id/; lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS /dev/nvme0n1'
ssh spark 'lspci -nn; sudo ethtool enP7s7 | grep -E "Speed|link modes"; ip -br link'
```

(The other hosts use [`../scripts/collect-disk-facts.sh`](../scripts/collect-disk-facts.sh) from a
console/live USB; spark is SSH-reachable, so the inline sweep above is enough — no new script.)

### Vendor spec (Lenovo PSREF / Lenovo Press LP2321, MTM 30KL)

| Component | Specification |
|-----------|---------------|
| Superchip | **NVIDIA GB10 Grace Blackwell** (same silicon as DGX Spark) |
| CPU | NVIDIA Grace 20-core **Arm** — 10× Cortex-X925 + 10× Cortex-A725 |
| GPU | Blackwell — 5th-gen Tensor Cores, 4th-gen RT Cores, NVENC/NVDEC |
| AI performance | **1000 TOPS · 1 PFLOP (FP4, sparsity)** |
| Unified memory | **128 GB LPDDR5x** (256-bit, 273 GB/s) — shared CPU/GPU |
| Storage | 1 TB **or** 4 TB NVMe M.2 (self-encrypting, AES SED) — **this unit: 1 TB SK hynix** (§As-measured) |
| Power | **240 W** USB-C PD 3.1 PSU |
| Form factor | 1.13 L SFF (150 × 150 × 50.5 mm, ~1.2 kg) |
| Network | **10 GbE** RJ-45 (Realtek on this unit) + 2× QSFP 200 G for NVIDIA ConnectX-7 — 2-node scale-out to 405B; ⚠️ **neither is live here**: link is 1 G, no ConnectX function enumerated (§Reality deltas 1–2) |
| Wireless | Wi-Fi 7, Bluetooth 5.3 LE |
| Ports | 3× USB-C USB4 (20 Gb/s, DP 2.1), HDMI 2.1a, RJ-45 10GbE, 2× QSFP |
| OS | NVIDIA DGX OS / Ubuntu Pro with NVIDIA Base OS, **CUDA 13** — live: DGX Spark **7.6.0** on Ubuntu 24.04.5, CUDA 13.0, driver 580.173.02 |
| Security | Self-encrypting NVMe (AES SED), **TPM 2.0**, NVLink-C2C enclave, NVIDIA FW recovery, AMI setup password, UEFI Secure Boot (only TPM 2.0 + UEFI verified on this unit) |

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
- **Physical port (wired 2026-09-17, owner; final placement):** direct patch to **RB4011 `ether8`** — the router's
  own `bridge-lan` (NOT the CRS328), so spark is a router-local dual-home access port exactly like
  oldsrv/Pi. Folded into SSOT: `router_port_map.spark` (`group_vars/router.yml`) +
  `rb4011_converge.rsc.j2` (bridge port `pvid=10`; VLAN 10 `untagged=…ether8…`; VLAN 99
  `tagged=…ether8…`) + the role's parity trunk task + `docs/rack-connections.json`.
  **Verified live 2026-09-17** (read-only API + host probe): ether8 link up, `pvid=10`, VLAN-10
  untagged + VLAN-99 tagged memberships present; spark's Home static lease (**bound**) and Mgmt static
  reservation both resolve per the `spark` rows in [network-addresses-generated.md](network-addresses-generated.md)
  (`spark_home_ip` / `spark_mgmt_ip`, never literals here); host `enP7s7.99` carries the Mgmt address
  and `ping -I enP7s7.99` reaches the router's Mgmt gateway. Nothing left to apply on the router — the
  manual edit matched the SSOT port model.
- Connects via the box's **10 GbE-capable RJ-45** to the LAN (Home/Mgmt per the router port model),
  negotiated at **1 Gb/s** on today's path. IP/reservation SSOT lives in `network_static_hosts`
  (never hardcoded). ⚠️ **Live 2026-09-16: the link negotiates at 1000 Mb/s** on `enP7s7` although the
  NIC advertises 10 G — the port/cable path, not the NIC (see §Reality deltas 1). **Explained + closed
  2026-09-17:** the cable lands on **RB4011
  `ether8`** — an Atheros **10/100/1000** port; the RB4011iGS+ has **no 10 G copper port at all**, so
  **1 Gb/s is the accepted, permanent design point (owner decision 2026-09-17)** — there is no 10 G
  device in the homelab besides spark, so the CRS328 (whose 10 G is SFP+/2.5 G only) stays 1 G for
  this link and **no move is planned**. Weight-staging bandwidth is therefore a fixed input to the
  bench/planning math, not an open network item.
- Exposes the Triton gRPC/HTTP endpoint on the `llm-backend` overlay (or a `triton-backend` net),
  reachable **only by LiteLLM** — same isolation model as Ollama (HD-59). No host port binds.
- 2× QSFP ConnectX-7 ports reserved for a future 2-node scale-out (to 405B models) — **not used now,
  and not currently usable**: no ConnectX/Mellanox PCI function is enumerated at all, and per Lenovo
  those ports do PGX↔PGX clustering only (never general networking) — §Reality deltas 2.

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

* **Retired socat stack removed from the box (HD-379, 2026-09-16).** The HD-364 replacement above
  left the OLD stack behind on disk: `/opt/dgx-dashboard/docker-compose.yml` + an **enabled**
  `docker-compose@dgx-dashboard.service` boot unit. Because the unit was never disabled, every
  boot resurrected the socat container, which then crash-looped forever (`Restarting (0)` — it can
  no longer bind `spark_home_ip:11000`, Traefik owns it). Removed live
  (`systemctl disable --now docker-compose@dgx-dashboard` + `docker rm -f`), **and made it durable
  in IaC**: `group_vars/spark.yml` now carries a `dgx-dashboard` **tombstone** entry with
  `enabled: false`, so the role's own "Tear down DISABLED services" + "Disable boot auto-start"
  tasks (the HD-375 tube-archivist pattern) keep it gone on every converge *and* after a reboot —
  nothing renders from a disabled entry (the vault pre-pass and deploy loops both skip it). Delete
  the tombstone once the teardown has run green on spark twice.
  Verified unaffected: `https://db-spark.kogler.si/` → **200** (its router is Traefik's `lm`
  entrypoint on `:443` → `127.0.0.1:11000`, i.e. it never depended on socat — socat had been
  crash-looping for days) and the dashboard backend answers 200 on loopback `:11000`.
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
| **Unified-memory budget / GPU×host memory sizing** | [this doc](hardware-spark.md) §Unified-memory budget & OOM governance |
| **OOM / engine-restart incidents (append-only)** | [`spark-incidents.md`](spark-incidents.md) |
| Old superseded Phase-2 build | archived decision log ([`deployment-rejected.md`](deployment-rejected.md)) |
