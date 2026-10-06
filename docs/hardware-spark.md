---
title: spark — Lenovo ThinkStation PGX (NVIDIA GB10 Grace Blackwell)
role: detail
domain: hardware
status: active
tags: [hardware, gpu, spark, gb10, grace-blackwell, ai]
---
# spark — Lenovo ThinkStation PGX (NVIDIA GB10 Grace Blackwell)

> **Role:** Detail — the headless AI inference node (`spark.kogler.si`): the homelab's big-model generation
> tier. It replaced the planned Phase-2 Ryzen/Proxmox build
> ([deployment-rejected.md](deployment-rejected.md)).
> **Links to:** `hardware-gpu.md`, `services-ai.md`, `hardware-workstation.md`, `network-vlans.md`
> **Linked from:** `hardware.md`, `index.md`, `services-ai.md`

> **Status: 🟢 PROVISIONED + LIVE.** First-class IaC host alongside nas/oldsrv/vps/pi
> (`spark` inventory group, `host_vars/spark.kogler.si.yml`, `playbooks/spark.yml`).
> DGX OS on Ubuntu 24.04 (noble) arm64, headless (`multi-user.target`, sleep targets masked),
> GB10 with driver 580-open + CUDA 13.0 and **121 GiB unified memory**, NVMe `p3` = AI-data XFS at
> `/mnt/spark_nvme`. Engine = **vLLM `spark-ai`** (B1: Qwen3.8-Flash-Next AWQ+PLE+MTP-3), ✅ enabled and
> serving `spark/qwen3.8-flash-next` on `llm.kogler.si`.
> ⏳ Open: the long-context / agentic certification tails (§Bench + engine selection), the
> **text-only engine mode** (§Text-only engine mode) and the two LiteLLM tails below.
>
> **Remaining tails:** the LAN LiteLLM bootstrap-key glue aborts `rc2` on a stale `dsh` secret
> (**HD-383** — every `lan-litellm` converge is red until the owner remediates), and `spark/*` is not in
> any `litellm_scoped_keys` allowlist, so the dev harnesses cannot reach spark through the gateway
> (**HD-384** — an owner call, deliberately not granted as a side-effect of registering the model;
> see [services-rejected.md](services-rejected.md)).

> **Artifact store (HD-359):** the `spark-artifacts` role (`roles/spark-artifacts/`) downloads the
> GPU-inference store onto XFS from a **config-agnostic manifest** (`spark_artifacts:` in
> `group_vars/spark.yml`): B1 weights (`wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16` → `models/`), PLE overlay
> `.py` files, and INT4 tables (`primitive-ai/Qwen3.8-Flash-Next-PLE-quant` → `overlays/` +
> `ples_int4/`) — **one download per quant-artifact, shared by every engine profile** (a future
> NVFP4/SGLang repo = a separate download by design). Idempotent per repo; runnable standalone via
> `--tags spark-artifacts`. Weights are ~169 G + ~30 G of tables — **regenerable, not backed up**
> (same pattern as oldsrv `/srv/models/immich-ml`).

> **vLLM metrics → Grafana (HD-368):** the spark-ai compose publishes `:8000` **loopback-only**
> (`spark_metrics_publish: true`, `127.0.0.1`) so the spark Alloy can scrape vLLM's Prometheus
> `/metrics` (`prometheus.scrape "vllm"` — the same pattern as Traefik's `127.0.0.1:8082` metrics
> entryPoint) and remote-write it to the VPS VictoriaMetrics. Three Grafana dashboards ship with the
> monitoring role (`homelab-llm-inference`, `homelab-vllm-monitoring-v2`, `homelab-vllm-dashboard`).
> Verify: `curl 127.0.0.1:8000/metrics` on the box → `vllm:*` series in VictoriaMetrics → panels on
> `stats.kogler.si`. See [observability.md](observability.md) §Dashboards.

> **Engine-flag notes — why the flags are what they are (all learned on the live box, all in the SSOT):**
> 1. `--swap-space` does not exist in this vLLM build → passing it is an unknown-arg crash.
> 2. **Do not force `--quantization awq`** — the weights are `compressed-tensors`; vLLM reads the packed
>    format from the model config and the forced flag mismatches it.
> 3. `disable_by_batch_size` is gone from `SpeculativeConfig` (replaced by
>    `num_speculative_tokens_per_batch_size`) → B1 = plain **MTP-3**
>    (`{"method":"mtp","num_speculative_tokens":3}`).
> 4. `gpu_memory_utilization` is **dead config here** — see §Unified-memory budget.
> 5. The recognized KV flag is **`--kv-cache-memory-bytes`** (bytes, int). `--kv-cache-memory` does not
>    exist in this build (unknown-arg crash class).
> 6. CUDA graphs must be capped to the reachable batch sizes — see §Unified-memory budget.
> 7. Comma-syntax `--limit-mm-per-prompt image=0,video=0` errors on current vLLM (upstream #39687); the
>    JSON form is the supported one.

> **Name edge + OpenAI-API (HD-370/HD-389):** `traefik-spark` is the NAME edge — the DGX dashboard
> (`spark.kogler.si`, HD-451; legacy alias `db-spark.kogler.si`) + `llm.kogler.si` (OpenAI-API) on
> **:443** (TLS from a pulled wildcard pair, cert CONSUMER —
> the Pi/oldsrv pattern) + HSTS; `:80` is redirect-only. The engine binds loopback on
> `spark_engine_port` and serves `spark/qwen3.8-flash-next` with `--api-key` from the `spark-llm_api`
> vault item. VPS/tailnet reach is **over WG S2S** (spark in `wg_s2s_vps.allowed_ips` + router
> `vps_scoped_home`): the tailnet edge routes `db-spark`/`llm` → `https://spark_home_ip:443`
> (**TLS-in-TLS**), which requires (a) the `spark-tls-in-tls` serversTransport (insecureSkipVerify on the
> spark backends — the plain path fails `x509: no IP SAN`) and (b) a `wg-s2s` kernel route for spark's
> address ([network-vpn.md](network-vpn.md) §Layer 1: `wg set` installs no routes).
> The edge routes the **`.ts` twin names too** (`llm.ts.kogler.si` / `db-spark.ts.kogler.si`, serving the
> `*.ts.kogler.si` pair from the default store): the tailnet edge forwards the client's **SNI**, so a
> `.kogler.si`-only `Host()` rule gives a routerless-vHost 404 *before* auth on the twin.
> DNS split-horizon: `llm`/`db-spark`/`spark` resolve to spark on the **home instances only** — the VPS
> primary never answers them ([network-dns.md](network-dns.md)). Off-LAN the dashboard is
> **`spark.ts.kogler.si`** — a `.ts`-namespace MagicDNS record only (`tailnet_ts_only_subdomains`),
> never a public record; the plain `spark.kogler.si` is deliberately NOT published into MagicDNS
> because it is this box's host name (HD-451).
> **Model registration:** `spark/qwen3.8-flash-next` is a DB entry in **both** LiteLLM instances
> (`api_base https://llm.kogler.si/v1`, **no key in the row** — the bearer is the container's
> `OPENAI_API_KEY` env from `spark-llm_api`; the name resolves via `extra_hosts`, because neither
> LiteLLM container can resolve LAN-only names —
> [services-rejected.md](services-rejected.md) `os.environ/` row).

> **Cold start is SLOW and that is not an outage.** The engine healthcheck carries
> `start_period: 1200s` because the first PLE-table load runs ~20 min. During that window `/health` returns
> **000** and `llm.kogler.si/*` returns **502** — which reads exactly like a broken route. It is not:
> `docker inspect vllm-qwen-spark --format '{{.State.StartedAt}}'` + `docker logs vllm-qwen-spark | tail`
> settles it in one look (weight load, then `GPU KV cache size:`). **Check engine health before debugging
> the edge.** The watchdog can still restart the engine on purpose at CRIT (`usable < 8 GiB`), but the
> idle recycle is **off** (owner decision 2026-09-23, §Unified-memory budget), so a young `StartedAt` you
> did not cause is **signal, not noise**: read `state/enforce.log` (an `ENFORCE:`/`RECYCLE:` line names
> the watchdog) before assuming a crash — see §Unified-memory budget and
> [`../spark/stability-test.md`](../spark/stability-test.md). Since HD-494 an enforced restart also
> **latches the enforcer off** until `usable` is back above the WARN band (12 GiB), so "it restarted
> itself on the hour" is no longer a possible steady state: one planned restart, then the budget is a
> human problem (live precedent: [spark-incidents.md](spark-incidents.md) §Incident #9).

> **The idle-recycle baseline WAS a boot-time coin-flip (HD-395 — fixed and live-proven; the term is now
> OFF by owner decision).** The guard recycled at *first-post-boot top-pid + 8 GiB after 1800 s idle*, but
> on this box that first sample is not a constant — the same config has been read at the boot floor as
> **71,911 / 86,243 / 92,343 MiB**, because the 168 GiB PLE checkpoint loads unevenly and the sampler
> grabbed whatever the very first sample was. Two bad directions: a low baseline lets ordinary traffic
> cross the line (it **did** — `state/enforce.log` records three recycles on 2026-09-23 alone,
> `03:41`/`04:15`/`04:50`Z, each reading `92343 MiB > baseline 71911 + 8 GiB`, i.e. the guard was
> permanently armed against a healthy engine and every ~30-minute idle gap cost a ~20 min cold start plus
> an `llm.*` 502 window that reads as an outage); a high baseline puts the line above the traffic peak and
> the guard goes silent. There is no value that is right at both ends: the certified peak (96,235 MiB)
> sits **3.8 GiB** above the committed floor (92,309 MiB), so any margin that clears the peak is
> unreachable by ordinary traffic and any margin that fires, fires on a healthy engine.
> **The baseline machine now (kept, even with the term off):** `await-health` → `settling` → `collecting`
> → `committed` — `/health` 200, then a settle window, then the **max** of N plausible reads inside a span
> (a read below `spark_oom_watchdog_baseline_min_mib` is refused, which keeps recycle disarmed rather than
> armed on garbage). The acquisition is **persisted**, so restarting the watchdog UNIT — what every converge
> does — never re-baselines a running engine; only a new engine instance or the operator's
> `sudo /usr/local/bin/spark-oom-watchdog.sh rebaseline` does. The "ratchet the baseline DOWN" rule is
> deleted (it just re-manufactured the same defect) and `status` prints the stage, the committed value and
> the **boot-floor spread**.
> ✅ **Owner decision 2026-09-23: the idle-recycle term is DISABLED** (`spark_oom_watchdog_recycle: false`,
> proven live). Rationale measured, not assumed: the box is stable and a 5–20 min cold start buys nothing —
> with a *correct* baseline the trigger is 100,501 MiB, i.e. **above** the certified peak, so a reachable
> margin would mean recycling an engine that is merely healthy. OOM protection does **not** ride on this
> switch: `enforce` (planned ~4 min restart at `usable < 8 GiB`, max 2 per 2 h — HD-381 term B), WARN 12 /
> CRIT 8 GiB, the 15 s sampler, the forensic bundles and the HD-375 alert rules are all live and are
> baseline-free. `spark_oom_watchdog_recycle_grow_gib: 8` and `…_idle_s: 1800` stay as the dormant re-arm
> shape. **Re-arm condition (the only one):** `gpu_top_mib` in `state/samples.csv` growing **> 2 GiB/h
> under traffic and not returning at idle** — the same curve that re-arms C3/`--enforce-eager` in HD-380 —
> and then re-derive the margin from that curve rather than from a guess.
> ⚠ **`sudo … status` does not inherit the unit's `Environment=`**, so it reads the *script defaults* and
> can disagree with the deployed config (measured: it printed `recycle=1` while the unit ran
> `SPARK_OOM_RECYCLE=0`). `status` now prints `⚠ CONFIG DRIFT …` naming the disagreement, and the truth is
> `systemctl show -p Environment --value spark-oom-watchdog.service`.
> Evidence: `spark-oom-watchdog.sh status` (6-case / 29-assertion `self-test`, all 5 new guards mutant-
> killed), `state/enforce.log`, `state/samples.csv`.

---

## Unified-memory budget & OOM governance

> **Why this matters:** spark is a **unified-memory** appliance — there is no separate VRAM. Every GPU
> allocation is physically the same **121.62 GiB** LPDDR5x pool the OS, Docker, Alloy and the DGX dashboard
> run in. Every global-OOM incident on this box came from the same missing governance: **vLLM's percentage
> budget silently consumed the host's reserve, and the kernel global OOM killer — not the container memory
> cage — decided what died.** Dated incident forensics live in
> [spark-incidents.md](spark-incidents.md) (append-only).

### The measured allocation arithmetic (source: the vLLM boot log)

vLLM prints its full accounting at startup (`gpu_worker.py`); these are the numbers for the B1 engine
(Qwen3.8-Flash-Next AWQ+PLE+MTP3, Qwen `compressed-tensors`) **as measured with the old percentage budget
(`gpu_memory_utilization: 0.82`)** — kept because the fixed-cost terms are what the explicit governor is
derived from:

```
Device total                                     121.62 GiB   (MemTotal = 127,532,360 kB)
Free at startup                                  114.70 GiB   (~6.9 GiB already held by OS/driver/dashboard)
Budget   = util × total = 0.82 × 121.62           99.73 GiB
  ├─ weights + non-torch                           77.69 GiB   FIXED — independent of util
  ├─ peak activation                                2.99 GiB   FIXED — driven by max_num_batched_tokens=16384
  └─ CUDA graphs (uncapped)                         …          see §HD-380 correction: uncapped graphs
Fixed cost                                         ~81 GiB       strand ~7 GiB of the shared pool
KV pool  = budget − fixed                           19.04 GiB  → 658,902 tokens  (30.3 KiB/token)
Reserve left for Linux = 121.62 − budget            21.89 GiB
```

### The rule that governs this box

```
KV_pool_bytes = util × 121.62 GiB − fixed_cost          (percentage form — replaces memory the host needs)
KV_pool_bytes = --kv-cache-memory-bytes <bytes>         (explicit form — the correct governor here)
Host_reserve  = 121.62 GiB − (fixed_cost + KV_pool)
```

Four consequences, all non-obvious, all measured:

1. **`max_model_len` costs nothing.** It is *not* an allocation — it is a **boot-gate validation**
   (`pool_tokens ≥ max_model_len`, else `ValueError`). The KV *pool* is whatever the budget leaves over,
   sized in blocks. Raising ctx from 64k to 262k changed the pool by zero bytes; the engine merely refuses
   to boot if the pool cannot hold `max_model_len` tokens. "Less ctx" and "lower util" are **not** the same
   lever, and they are coupled: with a 262,144 `max_model_len`, a util that leaves < 262,144 tokens of pool
   is a **crash-on-start** setting, not a smaller-context setting.
2. **The container memory cage cannot protect the host.** GB10 `cuMemAlloc` pages are **not charged to the
   container cgroup** — `docker stats` reported the engine at **4.267 GiB / 105 GiB (4 %)** while the host
   was at **112 GiB used**. The kill is always `constraint=CONSTRAINT_NONE … global_oom`, and Docker reports
   **`OOMKilled: false` + `ExitCode: 0`** (Docker only flags cgroup `memory.max` kills). **A
   `docker inspect` showing `OOMKilled=false` on this host is a false negative — always read
   `dmesg`/`journalctl -k`.**
3. **`kv_cache_memory_bytes` IGNORES `gpu_memory_utilization` in this build** (verified in the container's
   own source: `CacheConfig` — "kv_cache_memory_bytes (when not-None) ignores gpu_memory_utilization";
   `gpu_worker.determine_available_memory()` short-circuits to `reserve_mm_ipc_gpu_memory(...)`, "This does
   not respect the gpu_memory_utilization config"). Once the explicit pool is set, **util is dead config**;
   keeping it is a false sense of a ceiling. The engine loads weights/activations/graphs, then reserves
   exactly `<bytes>` of KV on top — capped only by physical free at startup.
4. **`nvidia-smi` is not a memory gauge on GB10** (`memory.total`/`used`/`power.limit` = N/A). Headroom math
   uses `MemTotal` (121.62 GiB) minus host usage.

### Sizing table — util → pool → host reserve (reference; fixed cost ≈ 80.90 GiB, 30.3 KiB/token)

Kept as the arithmetic behind the governor choice. **The decision is the KV pool in BYTES, not a util.**

| util | budget GiB | KV pool GiB | KV tokens | conc @262k | host reserve | verdict |
|------|-----------|-------------|-----------|------------|--------------|---------|
| 0.82 | 99.73 | 18.83 | 651,579 | 2.49× | 21.9 GiB | **percentage budget — OOM'd under agentic load** |
| 0.80 | 97.30 | 16.40 | 567,403 | 2.16× | 24.3 GiB | marginal |
| 0.78 | 94.86 | 13.96 | 483,227 | 1.84× | 26.8 GiB | ok |
| 0.75 | 91.22 | 10.32 | 356,962 | 1.36× | 30.4 GiB | ≈ the 8.2 GiB pool, via util |
| 0.74 | 90.00 | 9.10 | 314,900 | 1.20× | 31.6 GiB | floor with margin |
| 0.73 | 88.78 | 7.88 | 272,786 | 1.04× | 32.8 GiB | razor thin — no slack for a 2nd request |
| 0.7275 | 88.47 | 7.58 | **262,144** | 1.00× | 33.1 GiB | **hard boot floor for 262k** |
| 0.72 | 87.57 | 6.67 | 230,698 | 0.88× | — | **REFUSES TO BOOT @262k** |
| 0.70 | 85.13 | 4.23 | 146,522 | 0.56× | — | **REFUSES TO BOOT @262k** |

### The budget METRIC: `usable = MemAvailable − CmaFree` (HD-381)

**`MemAvailable` / `free -h` is NOT the budget metric on GB10.** The two observed kills both recorded
`MemAvailable` ≈ 10.4 GiB while `CmaFree` was **8.81 / 8.78 GiB** — device-reserved CMA pages the allocator
will not give an unmovable `GFP_KERNEL` request (`Node 0 Normal free:9.63 GiB` with `free_cma:9.58 GiB`,
`all_unreclaimable? yes`). Claimable headroom at the kills: **1.64 / 1.62 GiB**.

```
usable_gib = MemAvailable − CmaFree       # THE budget metric
  WARN < 12 GiB      CRIT < 8 GiB         # + PSI memory (full avg10) as confirmation only
  re-arm (hysteresis) ≥ 12 GiB            # HD-494: one enforced restart, then wait for the budget fix
  kills observed at   1.64 / 1.62 GiB
  healthy idle measured 26.13 GiB usable (CmaFree 0.13 GiB)
```

(The `WARN 8 / CRIT 4` pair this block used to carry is the **pre-HD-381** raw-`MemAvailable` pair on
the corrected gauge — what actually runs is 12 / 8, in `roles/spark/defaults/main.yml` and the
`HD-375` alert rules, which are kept identical on purpose.)

> ⚠ **CRIT 8 is not a tuning knob, and "we dipped below it and survived" is not evidence**
> (HD-494, 2026-10-05, asked and answered in
> [`services-rejected.md`](services-rejected.md)). 8 was chosen from three measured numbers, not
> taste: healthy idle 26-30 GiB, **the instant of death 1.6 GiB**, and the lowest value a 60 s
> scrape ever recorded inside a kill window, **5.01 GiB**. A trigger at 5 therefore sits *below the
> last sample the monitoring path can see*, and the action it guards is not instant — up to 600 s
> of in-flight drain, then `docker restart`, and the memory returns only when the ~20 min reload
> finishes. Lead time is the whole design; the number that buys it is 8.

`MemAvailable` is not merely optimistic here — it **inflates as pressure rises**, because squeezing the GPU
carve grows `CmaFree` and CMA counts as available. Any threshold on this box is therefore expressed in
`MemAvailable − CmaFree`; the alert rules, the watchdog and the bench guards all use that one gauge.

> ⚠ **Rejected, so it is not re-proposed:** `usable = MemFree − CmaFree` (WARN 4 / CRIT 2). Measured, it is
> **INVERTED**: 0.74 GiB at healthy idle vs 2.17 / 2.14 GiB at the two kills. `MemFree` is *supposed* to be
> ≈1 GiB at steady state; under pressure reclaim evicts page cache and `MemFree` **rises**, mostly into CMA.
> It tracks "reclaimed but unconsumed", not headroom. On an enforcing watchdog those thresholds would
> **restart the engine continuously on a healthy box**. The ~0.05 GiB figure that motivated it is from the
> kernel's **per-zone** dump and is not reconstructible from global `meminfo`.

**PSI memory** is a genuine trigger (`psi_full` 97.8 / 92.5 at the kill samples) but has **no lead time**:
one kill sampled `0.0` for ten consecutive samples at 9.4 GiB available. Use it as confirmation, never as
the early warning.

### The growth mechanism: traffic-cumulative, flat at idle

A fresh boot sat at engine top-pid **88,773 MiB / avail 24.2 GiB, unchanged overnight with no traffic**,
then went **88,773 → 109,785 MiB (avail 24.5 → 9.6 GiB)** under ~30 min of **one light agent session**
(KV 43–59 %, prefix hit 94 %, 0 % util at the kill).

- The mechanism is **per-request allocator/graph growth that is never returned** — not KV occupancy, not a
  leak. Only a **restart** resets it; only **removing the mechanism** bounds it (`expandable_segments`,
  prefill-chunk size, eager mode).
- **A light session is enough** — session cost is not proportional to KV occupancy, so "small workload" is
  not a safety argument. Budget a session as a **GiB-scale** term, not a token-scale term.
- The pre-kill signature is a **frozen top-pid + saturating PSI** (4+ min at a constant ~109.7 GiB while
  `psi_full` hit 97.8 / 92.5). An enforcing governor acts on that; a recorder does not.
- **An "idle ratchet" is not the mechanism** — an apparent idle climb was the residue of prior traffic.

**Two facts to carry into every future sizing calculation:**

1. **Per-pid `nvidia-smi` under-counts the engine by ~10 GiB.** True footprint = the `MemAvailable` jump
   when the engine stops: **12.6 → 118.6 GiB** ⇒ the engine held **~106 GiB** of 121.62.
2. **Agent sessions are a first-class memory term.** A ~162k-token session = **56 % of the (8.2 GiB-era) KV
   pool**, and at prefix hit **0 %** every turn re-prefills the whole window (**17,008 tok/s** observed) —
   the largest transient on this box. Loop: big context → ~82 % KV occupancy → own prefix blocks evicted →
   0 % hit → full re-prefill → spike. Sizing for "casual/chat" occupancy (peak 15.5 %, max 36,800 tok) is
   **not** representative of agentic use.

### The fixed cost, MEASURED — and why a 25 GB pool left the box no host floor (HD-494, 2026-10-05)

The host-floor gate (`roles/spark-llm-profile`) adds a profile's declared `fixed_cost_bytes` to its
KV pool and compares the sum to `spark_llm_device_hold_ceiling_bytes`. On 2026-10-05 that gate was
**green on a box with no reserve at all**, because the declared fixed cost was a weight-load log
line, not a measurement of what the process ends up pinning:

| term | B | GiB | how it is known |
|---|---|---|---|
| `MemTotal` | 130.594e9 | 121.63 | `/proc/meminfo` |
| **engine hold, measured** | **117.134e9** | **109.09** | `MemAvailable` 7.94 → 117.03 GiB across the 09:22:45Z restart — the incident-#6 method |
| ├ the 25 GB KV pool | 25.000e9 | 23.28 | `--kv-cache-memory-bytes 25000000000` |
| └ **non-KV fixed cost** | **92.134e9** | **85.81** | hold − pool |
| `fixed_cost_bytes` as declared | 76.300e9 | 71.06 | boot-log derivation (`Model loading took 68.35 GiB`) |
| **undeclared gap** | **15.834e9** | **14.75** | the difference, and the whole incident |
| non-engine use at engine start | 4.934e9 | 4.60 | `MemTotal − MemAvailable` 15 s after the restart (`cached` then 5.43 GiB) — vs the **6.9 GiB** the global ceiling assumes |

So the engine sits **12.13 GiB over the certified 104.113e9 ceiling** at a 25 GB pool, and "usable
7.9 GiB" is that overflow, measured from the other side. The same model run backwards predicts the
box: `130.594e9 − 4.934e9 − 92.134e9 − 25e9 = 8.53e9 B` = **7.94 GiB**, against the 7.76-7.99 GiB
observed all morning — the ledger is validated against the machine, not merely balanced.

**The rule that falls out of it:** the pool is capped by what the *fixed cost* leaves over, and on
this checkpoint `pool_max = (MemTotal − OS − reserve) − fixed = 112.70e9 − 92.13e9 = 20.64 GB`.

> **Measured against the box, 90 min into the 20 GB shape (2026-10-05 14:00Z):** `usable` rests at
> **9.83–9.90 GiB** (`MemAvailable` 13.9 − `CmaFree` 4.03), i.e. **inside the WARN band (< 12), above
> CRIT (8)** — not the 12.60 GiB the ledger above predicts. Two readings of that 2.7 GiB gap, both kept:
> the model's OS term is a 15-second post-restart sample (4.93e9) while a served box carries more, and
> `CmaFree` itself moved from 0.13 GiB at boot to 4.03 GiB once the engine was serving. The verdict is
> unchanged — no enforcement fires at REST, which was the point of the change — but a lane must not read
> "pool_max 20.64 GB" as "12 GiB of reserve at rest": on this checkpoint the reserve at rest is ~9.9 GiB.
> This is also why `SPARK_OOM_REARM_GIB` matters (→ HD-494): with it unset, REARM defaults to WARN=12,
> so a latch at this resting point would never re-arm by itself.
> **Live state, 2026-10-06:** the 2026-10-05 14:26 converge deployed the engine half of HD-494 but not
> the watchdog half — the script on the box was still the 2026-09-23 build and its unit carried no
> `SPARK_OOM_REARM_GIB`, so hysteresis existed only in the tree. Converged with `--tags watchdog`:
> script sha now equals the tree, the unit env carries `SPARK_OOM_REARM_GIB=12`, and with the by-hand
> `no-enforce` flag removed `status` reports `hysteresis: armed (no latch)` at `usable` 13.27 GiB.
> Verify a watchdog claim on this host by reading the box (`sha256sum`, `systemctl show -p Environment
> --value spark-oom-watchdog.service`, `spark-oom-watchdog.sh status`), never by reading the commit.
With `reserve` = the watchdog's WARN band (12 GiB, i.e. "the rest state must not even sit in the
WARN band"), **20 GB is the largest 1-GB-rounded pool this profile may use**, and `fast` is set to
it (644,600 slots = 2.46 × the 262,144 window; 80,575 tokens/stream at the `seqs=8` ceiling).
The per-profile `device_hold_ceiling_bytes: 112.70e9` is a **measured exception, not a re-cert**:
every other profile stays gated at the global 104.113e9, and re-certifying the global on the
measured 4.93e9 OS term is the ⏳ half of HD-494.
> **The "one working day of samples" gate closed by owner decision (2026-10-06), not by the calendar.** The armed-era rest
> windows already in `samples.csv` (Oct 2–6, 20,000 samples, epoch-verified against the watchdog's own stamps) are the
> evidence: every rest window 12–46 GiB (median 21.8 GiB), `restarts` 0 since the Oct-4 crash-loop era, and the hysteresis
> latch fired exactly twice in the whole record — both times under live client traffic (Incident #9 at 09:22:41Z, and the
> 2026-10-06 09:41:29Z transient burst), never at rest. The waiver covers the **rest-window** half; the memory-curve half
> (HD-380's `gpu_top_mib` > 2 GiB/h, gate 7) accrues on the current regime since **2026-10-06 11:19Z** and is read when that
> window fills, and the global re-derive above stays open. Raw:
> [`spark/reports/hd489-overnight-20261006-0226/raw/b7-watchdog-rest-analysis.txt`](../spark/reports/hd489-overnight-20261006-0226/raw/b7-watchdog-rest-analysis.txt).

### Boot-floor numbers (the baselines future curves compare against)

| state | engine top-pid | `MemAvailable` | `usable = MemAvailable − CmaFree` |
|---|---|---|---|
| boot, weights loaded, no traffic (8.2 GiB pool) | 88,773 MiB | 24.2 GiB | healthy (flat overnight) |
| + ~30 min one light agent session (pre-governor) | 109,785 MiB | 9.6 GiB | 1.6 GiB at the kill |
| boot + `expandable_segments` + prefill cap (8.2 GiB pool) | 85,445 → 86,243 MiB | 26.9 GiB | 30.3 idle / **28.81 worst** |
| **boot + both + 16 GiB pool (CERTIFIED baseline)** | **92,343 → 93,621 MiB (+1,278)** | 18.5 → 24.9 idle-after | **17.78 worst** under 2×240k ≈ 94.6 % pool |
| **HD-395 recycle proof (2026-09-23, J1)** | **92,309 MiB committed** (re-baseline after an intentional `docker restart`; boot floor spread **71,911 → 92,309** recorded, the max not the first read) | 118.29 GiB moments after the restart (engine ≈106 GiB released), idle-after 24.3 GiB | recovery 000 → 200 in ~5 min; trigger **100,501 MiB > certified peak 96,235** — a margin that is both reachable and above the peak does not exist (peak − floor = 3.8 GiB), so the term was switched **OFF** by owner decision the same day |

The last row is the load-certified peak-bound number: the same class of box went **+21,012 MiB in ~30 min of
one light session** before the governor and **+1,278 MiB across ~1.5 h of the pessimal two-full-window
shape** after it. The C3 trigger in [`../spark/stability-test.md`](../spark/stability-test.md) (§4: >2 GiB/h
under traffic AND no return at idle) is **not** met → **`--enforce-eager` stays off**, now on measurement.

### Chosen governor (IaC, `group_vars/spark.yml`)

**Explicit `--kv-cache-memory-bytes` as the ONLY budget dial, with `--gpu-memory-utilization` REMOVED.**
The percentage form is *replace-by-percentage*: it always eats the headroom the host needs, on a box where
host and GPU share one pool — and in this build the two are mutually exclusive anyway.

```yaml
# group_vars/spark.yml  (this build's flag: --kv-cache-memory-bytes, bytes int)
spark_vllm_kv_cache_memory: "16000000000"   # LIVE + CERTIFIED: reserved 14.9 GiB = 515,786 tok = 1.97× @262k
spark_vllm_max_cudagraph_capture_size: 4    # graph term: default [1,2,4,8,16,24,32] is unreachable above max_num_seqs and strands ~7 GiB
spark_vllm_max_model_len: 262144            # unchanged; boot-gate only
spark_vllm_memory_limit: 105G               # backstop only — see "cage" note below
# spark_vllm_gpu_memory_utilization REMOVED — ignored when kv_cache_memory_bytes is set (HD-374)
```

Certified state and its costs, stated plainly:

- **Peak is bounded** at this setting: engine top-pid **+1,278 MiB** across ~1.5 h including
  **2×240,000-token** concurrent fresh prefills (≈ 94.6 % of pool), with **0 kernel OOM, 0 engine restarts,
  0 guard-fires**. Evidence [`../spark/reports/stability/README.md`](../spark/reports/stability/README.md),
  runbook [`../spark/stability-test.md`](../spark/stability-test.md).
- **16 GiB is the practical bf16 ceiling — do not raise it further.** The headroom arithmetic is runtime
  **+5.5 GiB** vs boot-side **+5.4 GiB (binding)**. The next KV byte was supposed to come from
  `--kv-cache-dtype fp8`, and the two things this bullet used to say about it were both wrong:
  fp8 buys **1.70–1.89×** tokens for the same GiB, **not ≈2×** (it halves the main K/V only — the
  QSA indexer side-caches and the GDN state stay bf16), and "unvalidated on this hybrid+MTP build"
  understates the finding: on the image we pin it **cannot boot at all**
  (`NotImplementedError: QSA requires a BF16 main KV cache`,
  [`../spark/reports/hd469-graded/README.md`](../spark/reports/hd469-graded/README.md)). That is the
  **build**, not the model: fp8 main KV merged upstream as vllm#55557 on 2026-09-16, three weeks
  after the last push of our tag ([`image-probe-20260928.md`](../spark/reports/hd469-graded/image-probe-20260928.md)),
  and is not in vLLM v0.30.0 either. Reaching it is the engine-pin lane (**HD-473**), not a config
  flip and not a bigger pool. Profile-level arithmetic + the host-floor gate:
  [spark-llm-profiles.md](spark-llm-profiles.md).
- **Costs paid:** idle `usable` fell **30.5 → 18.5 GiB** (margin to the 12 GiB reserve target is now
  6.5 GiB, not 18), and `NV_ERR_NO_MEMORY` occurrences rose slightly across the run (boot-load burst
  unchanged in character). Under the 94.6 % shape the engine served it but slowly: mean TTFT **631 s**, MTP
  acceptance **20.6 %** (35–44 % at small batch) — a capacity/latency cost, not a safety one.
- **Uncapped CUDA graphs are ~7 GiB of stranded pool:** this build captures graphs for batch sizes
  [1,2,4,8,16,24,32]; `max_num_seqs=4` caps the decode batch at 4, so 8/16/24/32 are captured and
  unreachable — dead memory in the one pool host and GPU share. Capping to 4 moved the engine per-pid
  **105,477 → 96,235 MiB** and `MemAvailable` **16.7 → 22.2 GiB**.
- **Still unbounded (known):** `--kv-cache-memory-bytes` makes vLLM **skip memory profiling**, so the
  non-KV, non-weight allocation (measured ~13 GiB, then ~22 GiB unaccounted at rest) is not governed by
  anything. The graph cap raised the *resting floor*; it did not bound the *peak*.
- **The 105 G cage is harmless but misleading:** it sits above the whole non-GPU budget and (per consequence
  #2) the GPU allocation is not cgroup-charged, so it can only ever catch a host-RSS runaway. It is retained
  as a backstop, **not** as the protection it reads as. The real protection is the explicit KV governor +
  the host-memory alert ([observability.md](observability.md) §Alerting → spark host memory).
- **Guards use ONE gauge:** every bench guard (`spark/bench/stress-oom.sh`, `run-scenario.sh`) and the chain
  preflight gate on **`usable = MemAvailable − CmaFree`** at a **16 GiB** floor — the same gauge as the
  watchdog and the alert rules. Guards that read raw `MemAvailable` would fire on a healthy box at usable
  18.5 and read healthy at 10.4 GiB, which is where the real kills happened.
- **Since HD-469 the pool is per-profile, so the line above is the `reasoning`/`graded` value, not "the
  live value".** What renders comes from `spark_llm_profiles[spark_llm_profile].kv_cache_memory`
  (`host_vars/spark.kogler.si.yml` picks the profile — today `fast`); `fast` renders **20 GB** as of
  2026-10-05 (was 25 GB; the 25 GB step left no host floor — §*The fixed cost, MEASURED* above), and
  the 16 GiB certified ceiling still binds every profile that does not declare its own. Catalogue +
  the host-floor gate: [spark-llm-profiles.md](spark-llm-profiles.md).

### KV-cache persistence across restarts (LMCache) — REJECTED (2026-09-20)

> **Decision:** the [`../spark/BENCHMARK-PLAN.md`](../spark/BENCHMARK-PLAN.md) §6 ladder **#10** (KV offload
> connector, LMCache → `/mnt/spark_nvme/kv_cache`) is **rejected — do not build it on this box.**
> Decision-log entry: [services-rejected.md](services-rejected.md).

**What it would have fixed — and what it cannot.** Cold start on this box is two different costs, and
LMCache reaches only the second:

| Cost | Today | LMCache effect |
|---|---|---|
| Engine boot (weights + PLE tables) | ~20 min (`start_period: 1200s`) | **none** — it is a KV layer, not a weight loader; the `llm.*` 502 window and the HD-395 recycle penalty stand |
| First token after boot (re-prefill of the recurring prefix) | ~13 min TTFT @250k cold / warm re-prefill ~1640 tok/s (§Bench caveat) | the real target — restore ~7.2 GiB of KV (250k × 30.3 KiB/token) instead of re-prefilling it |

`--enable-prefix-caching` is already on and the pool is 1.97× @262k, so *within* a boot the recurring prefix
already hits. Its only marginal win was **across** restarts/recycles — the same window **HD-395** (the
coin-flip idle recycle) manufactured at ~20 min a pop. Fixing HD-395 removes that cost instead of
mitigating it. *(2026-09-23: the recycle term is now OFF by owner decision, so this row's recycle penalty
is no longer live — the ~20 min boot cost and the blockers below stand on their own and the rejection
stands.)*

**Why rejected rather than deferred — three independent blockers:**

1. **Correctness on this model class (decisive).** Qwen3.8 is a hybrid Mamba/GDN model, and LMCache supports
   hybrids **only** via `LMCacheMPConnector`. LMCache's own docs list `Qwen3.8-27B` as validated (unified block
   size 784) — while its own tracker says otherwise on this hardware class. **LMCache #4247** (open) reproduces
   **silent** corruption ("multilingual token salad", no exception, every counter green) on **any shared-prefix
   hit** with **GB10 / aarch64 / cc 12.1 / CUDA 13.0 / TP=1** + Qwen3.x hybrid + FlashInfer; the fix **PR #4253
   is unmerged**, and **#4674** reports multi-session prefix hits still corrupting even with it. The **persistence
   tier — the only part worth having here — is separately broken: #4701** stores **1 of N kernel pages per
   chunk**, so restores report 95–99 % hit rates and return wrong answers. The trigger is *our* traffic shape:
   one large stable system prompt + tool schemas with varying turns = every agent turn is a shared-prefix hit.
   The ladder gate (`TTFT ↓ ≥50 %`) **passes** this failure, and the 10-prompt accuracy gate is short-prompt and
   already 8/10 — neither would have caught it. Silent-wrong is the one outcome this tier cannot ship.
2. **It spends pool this box does not have.** LMCache's L1 tier is **pinned CPU RAM allocated greedily up front**
   (5 GiB default) out of the same pool whose idle `usable` is **18.5 GiB against the 16 GiB guard floor**
   (§Chosen governor). The `lmcache server` is a second resident charged **neither** to the `105G` cage **nor**
   to the watchdog's gauge → it re-rolls the HD-395 baseline a second time.
3. **It breaks the image-pin contract.** aarch64 wheels exist only from **LMCache 0.5.4rc1** (cp310–cp313), and
   LMCache's own compatibility rule is *never copy a native wheel built for another PyTorch/CUDA channel into a
   stack-built image*. On GB10 the working recipe is a **source build**, not a wheel install — `TORCH_CUDA_ARCH_LIST="12.0" LMCACHE_CUDA_MAJOR=13 ENABLE_CXX11_ABI=1 pip install . --no-build-isolation --no-deps` — which means a rebuilt engine image and a new `spark_vllm_image` digest (HD-370), for a component with an open correctness bug.

**Re-decide trigger (cheap, and it is a correctness probe not a bench):** upstream merges the hybrid fix **and**
a buried-fact-across-restart probe passes on B1 — plant a random fact in a prompt longer than one chunk, restart
the engine **and** the cache server, require the exact answer from an **L2-only** hit, with `KV cache group edits
applied: {'subpaged-attention-view': N}` present in the boot log and `Engine KV Format` uniform across groups
(the missing edit key is the bug's only observable signal). Do not trust hit-rate counters here.
**vLLM's own `OffloadingConnector` is not an escape** — hybrid mamba+attention "can't use external KV cache
offloading out of the box" upstream either (vLLM #38230 / PR #38261), so this rejection covers the whole
"persistent KV tier" idea on this model class, not just the LMCache implementation.

### Restart-count semantics (how to tell a kill from a redeploy)

- `RestartCount` increments when the **same container** is re-exec'd by the restart policy → a host-side
  kill or process exit; the container ID is unchanged.
- A compose **replacement** creates a *new* container → the counter resets and
  `com.docker.compose.replace` is set. Distinguish before attributing a restart to OOM.
- Engine restart history is additionally countable from the boot banner:
  `docker logs --timestamps <ctr> | grep 'version 0.1.dev'`.

### Workload reality + safety notes

- **Occupancy reality:** the largest context ever served was **36,800 tokens** and peak occupancy **15.5 %**
  while the pool held 658,902 tokens — pinning the pool explicitly both covers 262k with block-rounding
  margin and returns GiB to Linux.
- **If 262k is not actually needed**, `--max-model-len 65536` (or 131072) shrinks the pool further and gives
  the host more relief; ctx length costs nothing in bytes, so capping it is free.
- **Do not rely on the OOM killer to pick politely.** It does not: it has killed the user-slice session
  (`pipewire`, `dbus`, `systemd`) before the engine, and in another incident `sshd`/`NetworkManager`/
  `polkitd`, wedging the box until a power-cycle.
- **Swap is a symptom, not a fix:** 16 GiB file-backed swap inside the same unified pool buys no headroom,
  and it produced a **~3.5 min log-write stall** during one incident. Consider zram only *after* the budget
  is settled.

---

### GPU clock cap — the only power lever on GB10 (HD-469)

GB10 has **no power-limit control** (`nvidia-smi -pl` unsupported, `power.limit` reads **N/A**) and, as probed
2026-09-28, **no writable temperature target either** — so a **graphics-clock ceiling** is the only software
power/thermal lever on this SoC. spark runs under one since 2026-09-28, owned by IaC, set at the **default
application clock** (2418 MHz):

- **The lever:** `nvidia-smi -lgc 300,2418` — the default application clock. **Range form, never a bare
  value** — a bare `-lgc 2418` pins min=max, so the GPU can never idle its clocks down on a box serving a
  live agent 24/7.
- **The IaC:** `spark_gpu_clock_cap_{enable,mhz,bin,ceiling_mhz}` in `roles/spark/defaults/main.yml`;
  the `spark` role installs `spark-gpu-clock-cap.service` (tag `clockcap`) **and** re-issues the lock on
  every converge (`-lgc 300,2418`, the range form). The read-back assert was REMOVED 2026-09-29 (owner
  ruling, `043ff4a`, decision log [services-rejected.md](services-rejected.md)): the driver ACCEPTS the
  lock yet **no query field reflects it** (falsification note below). Consequences now encoded in the
  role: `--check` prints the observed clock state as **context and claims no drift** (the old drift line
  keyed on the dead `clocks.max.sm`, so it claimed drift on every run — a signal that is always red is
  not a signal), and the apply task is `changed_when: false`, because a `changed` it cannot observe is
  not information either. The apply's **visible** failure mode stays loud: a non-zero `-lgc` exit = the
  driver refused the flag = the converge fails.
- **Why both a unit and a converge apply:** the lock is **runtime driver state, lost on every boot** —
  and this box has a documented power-cycle history (SMART row, §As-measured: "high power-cycle +
  unsafe-shutdown count"). The unit covers boots; the converge apply covers driver reloads and any
  hand-run `-rgc`.
- **Opt-out is real:** `spark_gpu_clock_cap_enable: false` stops the unit, whose `ExecStop` runs
  `nvidia-smi -rgc`. That matters because a runtime lock on a box nobody ever reboots would otherwise
  persist silently forever — permanent drift that `--check` cannot see.

**Why cap at all.** Upstream DGX Spark reports describe a **hard power-off under sustained GPU load at
~90 W that leaves no log**, and report the ceiling as the fix: *~20 log-less hard-offs in 3 weeks → zero
after `nvidia-smi -lgc 300,2200`* (in combination with memory-pressure mitigations), at a measured cost
of **~5 % throughput on bandwidth-bound LLM inference** (30.8 vs 32.3 tok/s on identical vLLM lanes).
Our own wedges in [spark-incidents.md](spark-incidents.md) are **OOM-class, not this class** — do not
retro-diagnose them as this.

**Why 2418 and not the 2150–2200 those reports used (owner ruling, 2026-09-28).** This unit has **never had a
hard power-off**, so it is not paying ~12 % of clock for insurance against a fault it has not demonstrated
(and the reports smell unit/PSU-specific: one survived a full platform firmware update, another needed a
firmware *downgrade*, and ours is a Lenovo chassis on a 240 W USB-C PD PSU the OS cannot even see).
What the cap buys at 2418 is therefore **a known measurement regime at ~3 % cost** plus a bound on peak
draw — *not* the crash mitigation those reports measured. If a hard-off ever does happen here, this var is
the first thing to lower, and the ceiling is derived from the range so the role's assert follows it with
no other edit.

**No thermal policy is available on this SoC — probed, not assumed** (`nvidia-smi -q -d TEMPERATURE /
- PERFORMANCE`, 2026-09-28): `GPU Target Temperature` **N/A**, `GPU Slowdown T.Limit Temp` **N/A**,
`GPU Shutdown T.Limit Temp` **N/A**, `GPU Max Operating T.Limit Temp` **0 C**, and `--help-gpu-queries`
offers no temp/slowdown key at all. So a temperature-threshold policy — the obvious "don't fix the
clock, cap the heat instead" idea — **cannot be set here**. It would also be the wrong tool if it could:
the upstream failure is an **electrical** power-off at ~90 W, and a thermal feedback loop cannot act on a
cold die pulling 90 W for seconds. Same gap family as `-pl` and `--query-supported-clocks`: GB10 exposes
none of the usual control surface.

The same probe is mildly reassuring about the driver's own loop though: **`SW Power Capping` =
1,335,107,735 µs ≈ 22 min cumulative**, while `SW Thermal Slowdown`, `HW Thermal Slowdown` and
`HW Power Braking` are all **0 µs** — the part already caps itself electrically and has never thermally
throttled. Read `GPU Current Temp 68 C` as sane; read **`GPU T.Limit Temp 26 C` as junk** (a 26 °C limit
below the current temp is not a real threshold — same class of bogus reading as `MEMORY_TEMP` = 0,
[observability.md](observability.md) §DCGM). ⚠ Driver has also moved under us: **580.178.04**
(`nvidia-driver-580-open`, re-measured 2026-09-28 via `dpkg -l`) where §Identity/§As-measured had recorded
**580.173.02** — DGX OS/apt changed the driver with no IaC change, so treat driver-version claims in this
doc as dated snapshots, not state.

**Measured on this unit** (2026-09-28, read-only `--query-gpu`): `clocks.sm` **2496 MHz** (2515 MHz on a
second read minutes later), `clocks.max.sm` **3003 MHz**, Default Applications Clocks **2418 MHz**, and
`--query-supported-clocks=graphics` → **[N/A]**. Two consequences: **2418 is only ~3 % below where this box
actually boosts**, so the cap is cheap and its throughput cost is close to noise; and the value **cannot
be validated by enumeration** — GB10 does not enumerate clocks any more than it enumerates memory.

**Falsified 2026-09-29: there is NO read-back field on this driver.** Every candidate was measured
live, and each fails for a different reason:

| Field | Reads | Why it cannot prove the `-lgc 300,2418` lock |
|---|---|---|
| `clocks.max.sm` | **3003** before AND after the lock | it is a **capability** field (matches `-q -d CLOCK` → *Max Clocks*), not the enforced limit |
| `clocks.applications.graphics` | **2418** | equals **Default Applications Clocks** (also 2418) — it reads 2418 with the lock and without it |
| `clocks.sm` (instantaneous) | **2405 at 29.5 W** post-cap; **2405** pre-cap in the prep session too | a single sample does not discriminate — the idle/low-load value was identical before the cap |
| `--query-supported-clocks` | **N/A** | nothing to enumerate, so the ceiling cannot be validated up front |
| `clocks_event_reasons.*` | `active = 0x0`, `sw_power_cap` Not Active | a lock is not a throttle reason; the driver reports nothing |

**The one discriminator is sustained `clocks.sm` UNDER LOAD**: this unit boosts to **2496–2515 MHz**
pre-cap (table above) and sat at **~2411 MHz** under the cap — consistent with a 2418 ceiling, and the
2405-idle coincidence above is exactly why a spot reading proves nothing. Sample it inside a bench
window from a session **not** served by spark (rule 0), never by hand mid-measurement:

```bash
ssh spark 'nvidia-smi --query-gpu=timestamp,clocks.sm,power.draw,temperature.gpu,clocks_event_reasons.active --format=csv -l 5'
```

⚠ **Exercised 2026-09-29 (run #3), with the caveat still open.** The first converge after the assert
landed FAILED on it: the driver accepted `-lgc 300,2418` (rc=0) while `clocks.max.sm` stayed 3003, so
the assert failed a converge that had in fact applied the cap. Per the brief it was REPORTED, not
skipped; the owner ruled to remove the re-read/assert (`043ff4a`) and the role converges clean.
**What remains unproven:** (a) the sustained-under-load sample above — the cap regime the run #3
baseline is named after was never recorded, so that baseline is **owed**, not measured
([hd469-reasoning](../spark/reports/hd469-reasoning/README.md)); (b) the **boot** path — the unit is
`enabled` but has `NRestarts=0` and an empty `ExecMainStartTimestamp`, i.e. it has never actually run
(no boot since it was enabled, and "never reboot spark" means it stays untested); the only proven
enforcement is the converge apply. Do **not** call `power.draw`, the OOM-watchdog sampling, or the
gate-7 memory curve the cap's falsifier — none of them measures clocks, and gate 7 has not been run anyway.

Corroboration from the prep session (2026-09-28, read-only ssh, no converge):
`nvidia-smi --query-gpu=clocks.sm,clocks.max.sm` → **2405 MHz / 3003 MHz** — the **pre-cap** state (the
cap first converged 2026-09-29 15:45). ⚠ Read it again as the falsification it is: **the same 2405
appears in the pre-cap and the post-cap readings**, which is exactly why the discriminator is clocks.sm
*sustained under load* and not a spot check.

**Read it in Grafana:** `DCGM_FI_DEV_SM_CLOCK` (already scraped —
[observability.md](observability.md) §DCGM, recorded at **2509 MHz** pre-cap) should now sit on a
**plateau at ≤ 2418 MHz under load**. A ceiling reading *below* 2418 under load is the driver's own power
capping doing its job (see the `SW Power Capping` counter above) — not a scheduler problem, and exactly
what the clock + power panel pair exists to separate.

## DGX Spark host limits the vendor measured for us (2026-09-28)

SGLang's own DGX Spark cookbook pages ([Qwen3.8-Flash-Next](https://docs.sglang.io/cookbook/autoregressive/Qwen/Qwen3.8-Flash-Next),
[Qwen3.8-27B](https://docs.sglang.io/cookbook/autoregressive/Qwen/Qwen3.8-27B)) run grids **on this
box** (SM121 / aarch64, GB10) and publish numbers for the failure modes we already paid for. Three of
them are host rules, not engine trivia:

* **`0.85 × 128 GB` is DGX OS's own earlyoom SIGTERM threshold.** Static allocation at 0.85 leaves
  ~8 GB for the OS, the first long prefill or boot-time graph capture dips under it, and the scheduler
  dies with **`exit code -15` and no traceback** (`journalctl -u earlyoom` shows the kill). In their
  GB10 grid **15 of 48 cells died that way at 0.85 and every cell served at 0.80**; "which cells" was
  margin noise. This is the same shape as our own `usable = MemAvailable − CmaFree` kills (§above), and
  it is why `--mem-fraction-static 0.80` in the `fast-sglang` profile is a **floor, not a preference** —
  now asserted (`roles/spark-llm-profile` refuses > 0.80) instead of being an uncited number.
  Note that the flash-next cells themselves run 0.85 with ~8–12 GiB free and report host memory never
  below 10 GiB: on a box that serves a live agent all day, 0.80 is the operating point we keep.
* **Docker GPU access on GB10 is CDI-only** — `--device nvidia.com/gpu=all`; **no `nvidia` runtime is
  registered**. Any future engine container in this stack must use CDI (our `spark-ai` compose pattern
  needs checking against that before an sglang spike, not after a boot failure).
* **`nvidia-smi` is not a memory gauge here** (`memory.*` → `Not Supported`, unified with the CPU) —
  gate a relaunch on `MemAvailable` in `/proc/meminfo` (our watchdog + bench guards already do), and
  budget a real load time before calling a boot hung: the BF16 27B checkpoint takes **~6.5 min just to
  load its 18 shards** from NVMe, ~10 min to READY. Our own 20 min `health_start_period` is sized for
  the vLLM PLE path; the SGLang file-backed-PLE path needs 4800 s (see the profile comment).

---

## Bench + engine selection

spark serves Qwen3.8-Flash-Next under several serving profiles (S1–S5, engine-neutral). The engine is
**not pre-decided** — vLLM and SGLang are benched apples-to-apples on this box and the winner per profile
gets promoted into the SSOT. Full plan: [`../spark/BENCHMARK-PLAN.md`](../spark/BENCHMARK-PLAN.md);
research + verdicts: [`../spark/resources/RESEARCH-VERDICTS.md`](../spark/resources/RESEARCH-VERDICTS.md).

> **Since HD-469 those benchmark lanes and the DEPLOYED config are the same dial.** The S-lanes above are
> bench shapes; the configs this box can actually boot are the Ansible profiles (`spark_llm_profile` →
> `spark_llm_profiles`): `reasoning` = the S1 shape, live as the rollback target; `graded` = S1 with fp8 KV
> (⛔ blocked on the image → HD-473); **`fast` = the live winner** — since 2026-10-03 that name carries the HD-489
> AR-hybrid arm (`ar-blk`), **not** the S2/S3 NVFP4 lane it named during HD-469 (that lane is a rejected-log row →
> HD-475), so never infer a checkpoint from the profile name; `fast-sglang` = the S5-shaped SGLang lane
> (gate-blocked). Catalogue,
> KV/quant arithmetic, the certifying gate and the client-contract split:
> [spark-llm-profiles.md](spark-llm-profiles.md); certification procedure:
> [`../spark/llm-profiles/README.md`](../spark/llm-profiles/README.md).

- **vLLM (live today):** the 98/100 AWQ+PLE accuracy recipe is vLLM-only (PLE n-gram overlay); NVFP4 on
  GB10 has an upstream Marlin fallback gap (#50925).
- **SGLang (candidate):** the native-GB10 NVFP4 route (262k ctx); long-context concurrency (S5) fits its
  pool semantics.
- **Certified on this box:** max ctx **262,144** = the model's native `max_position_embeddings` (300k is
  rejected at startup validation — it would need `VLLM_ALLOW_LONG_MAX_MODEL_LEN` + YaRN, needle-gated);
  250k @ 95 % fill with **0 preemptions**; the accuracy gate holds serially and at concurrency 3.
- ⏳ **Still pending before full production trust:** needle test at 262k (long-context correctness; the
  QSA/XQA trap starts ≥120k), the tool-call EMPTY fix (no tools registered today), a true 3×87k-token fill
  stress, and the NVFP4/SGLang lane. **Verdict today: production-ready for casual/chat inference; agentic
  and max-context work is gated on those tests.** Bench evidence: [`../spark/reports/`](../spark/reports/),
  runbook [`../spark/stability-test.md`](../spark/stability-test.md), and
  [spark-incidents.md](spark-incidents.md) for the failure history.

## Text-only engine mode (vision disabled) — ⏳ proposed, not applied (HD-400)

The staged checkpoint is **multimodal** (`Qwen4ExpForConditionalGeneration`; vision encoder 27 layers /
hidden 1152 → merger → LM hidden 2560, interleaved mrope `[11,11,10]` —
[`../spark/resources/R1-hf-model-card.md`](../spark/resources/R1-hf-model-card.md)). Every consumer of
`spark/qwen3.8-flash-next` is **text-only** today (pi.dev direct per decision #26, HD-376; the
simple-querier tier is text too), yet the live compose
([`IaC/ansible/templates/docker_services/spark-ai/docker-compose.yml.j2`](../IaC/ansible/templates/docker_services/spark-ai/docker-compose.yml.j2))
sets **no** `--limit-mm-per-prompt`, so vLLM loads the multimodal stack at its defaults (V1 default = 999
per modality).

**Proposed change (one variable, bench-gated — BENCHMARK-PLAN §6 step 11):**

```
--limit-mm-per-prompt '{"image": 0, "video": 0}'      # ≡ --language-model-only
--mm-processor-cache-gb 0                              # optional second row
```

- **What it is:** upstream vLLM skips the disabled modality's **modules**, so the ViT is not loaded
  (issue #21943, closed via #22299; `--language-model-only` is the documented equivalent).
  ⚠ **The pinned fork build must be measured, not assumed** — module-skipping is per-model-implementation
  and this is a fork build.
- **What it is NOT: a speed change.** With no image tokens the vision tower never executes, so decode tok/s
  is expected **flat**. The gain is memory returned to the ONE 121.62 GiB pool: the tower (~0.5–1 GiB
  device) + the mm processor cache (**default 4 GiB, host RAM** — same pool on GB10).
- **Where the gain lands:** the binding side is **boot headroom** (the certified 16 GiB pool leaves
  +5.4 GiB boot-side). 1 GiB ≈ **32.2k KV tokens** at the measured 30.3 KiB/token. Convert freed GiB into
  headroom or KV **as a separate bench row** — never in the same change, or the ledger cannot attribute
  either.
- ⚠ **Syntax trap:** the comma form `image=0,video=0` is the *old* parser and errors on current vLLM
  (upstream #39687). Use the JSON form.
- ⚠ **Consequence to accept:** `image: 0` makes an image part a hard **400**. Harmless for today's
  harnesses; it is a decision-consequence for HD-384 if a future gateway consumer (Open WebUI) ever
  receives pasted images. Vision lives on the workstation instead —
  [`hardware-workstation.md`](hardware-workstation.md) (decision #28).
- **Gate to keep:** boot per-pid MiB Δ + host `usable` Δ + C2 tok/s unchanged + accuracy gate 10/10
  unchanged (`spark/bench/accuracy-gate.sh`). Host-safety preflight (`MEM_FLOOR_GB`, the 105 G cage)
  unchanged.

## Current role in the AI tier

- **spark = the big-model generation tier** behind the gateway (LiteLLM / Qdrant / Open WebUI). It took
  over **generation** from the old host-LLM setup; oldsrv still runs a retained `ollama` container, but only
  as the embed **fallback rung** — it is not a chat or generation host anywhere in this design.
- **It does not run the pinned small services.** Whisper STT, bge-m3 embed and bge-reranker run on the
  **oldsrv RX 7600** (container-bundled runtimes); Piper TTS is CPU-only. Placement of every model is the
  plan of record in [`services-ai.md`](services-ai.md) §9, with measured numbers in
  [`services-ai-bench.md`](services-ai-bench.md).
- **Vision is NOT here** — decision #28 places visual judgment on the workstation
  ([`hardware-workstation.md`](hardware-workstation.md)); spark is text-only (§Text-only engine mode).
- Not on spark: immich-ML (oldsrv GPU, pause-able — see [`hardware-gpu.md`](hardware-gpu.md)); no
  host/venv inference — **container-native only**; no second GPU stack.
- ⏳ **Candidate future services on this node:** Mem0 (long-term memory for Open WebUI over the existing
  Qdrant store, per-user/per-project scoping via `user_id = <openwebui_user_id>-<model_id>`) and OpenHands
  (a third coding harness beside pi.dev + DSH). Neither is onboarded.

### Model-catalog sync (doctrine — ⏳ glue not yet implemented)

`group_vars/all/models.yml` + the `litellm-model-sync` glue are **planned, not in IaC today**; the live
mechanism is a manual DB row in both LiteLLM instances (see the name-edge note above). The rules the glue
must implement when it lands:

- **Git is the source of truth for what exists on spark**; the LiteLLM DB + `litellm_scoped_keys` are what
  is available and to whom.
- **Onboard** → idempotent upsert into the LiteLLM DB (`POST /model/new`, vault-first, the `bootstrap-keys`
  glue pattern).
- **Offboard** → delete it from the LiteLLM DB **and** remove its allowlist entry from
  `litellm_scoped_keys` in the **same change** — a scoped key must never still authorize a model that no
  longer exists.
- **Manual / OpenRouter models are never touched** — deletes are scoped to names the glue previously synced
  (tracked state), so a hand-added model cannot be clobbered, even on a name collision.

## Network / placement

- Hostname **`spark.kogler.si`** — headless inference node. Reserved statics live in
  `network_static_hosts` (SSOT) and are referenced as `spark_home_ip` / `spark_mgmt_ip`, **never literal**.
- **Single NIC** (`enP7s7`): Home VLAN 10 **untagged** + Mgmt VLAN 99 **tagged** (NM dual-home); the
  VLAN-99 SSOT row carries the same MAC as VLAN-10 because VLAN subinterfaces share the parent MAC. There
  is **no second NIC**. Router side: the `dhcp-mgmt` static renders in the converge template.
- **Physical port = RB4011 `ether8`** (the router's own `bridge-lan`, NOT the CRS328) — a router-local
  dual-home access port exactly like oldsrv/Pi. SSOT: `router_port_map.spark` (`group_vars/router.yml`) +
  `rb4011_converge.rsc.j2` (`pvid=10`; VLAN 10 untagged + VLAN 99 tagged on ether8) + the role's parity
  trunk task + `docs/rack-connections.json`. Verified live: link up, memberships present, both spark
  reservations bound, `enP7s7.99` reaches the router's Mgmt gateway.
- **Link speed is 1 Gb/s and that is the accepted permanent design point.** The NIC advertises 10 G, but
  **the RB4011iGS+ has no 10 G copper port**, so the upstream port is 10/100/1000; there is no other 10 G
  device in the homelab, so the link does not move to the CRS328. Consequence: **weight-staging bandwidth
  (~169 G of weights) over 1 G is a fixed input to the bench/planning math**, not an open network item.
  Re-check only if the physical path changes (§Reality deltas 1).
- **Engine reachability:** the engine binds loopback only; everything reaches it through the
  `traefik-spark` name edge (§Name edge above) — no host port bind.
- **2× QSFP ports are not usable:** no ConnectX/Mellanox PCI function is enumerated at all, and per Lenovo
  those ports do PGX↔PGX clustering only (never general networking) — §Reality deltas 2. Re-check after a
  DGX OS / UEFI update; it may be a firmware or module-probe gap rather than missing silicon.

## Remote management

- Headless by design: no display, no local desktop. Managed over the LAN + mgmt plane (SSH/Ansible).
- **Headless contract (HD-364, IaC-enforced):** the `spark` role masks `sleep/suspend/hibernate/
  hybrid-sleep.target` and sets `default.target = multi-user` whenever `spark_headless: true`
  (set false on a desktop-style DGX box to leave GDM + sleep as shipped). A headless box whose NIC is
  suspended is unrecoverable except by power-cycle — this happened once before the mask existed.
- **DGX Dashboard on the LAN (HD-364):** NVIDIA ships the dashboard bound to loopback only (no bind flag;
  remote access officially = SSH tunnel / NVIDIA Sync). The `spark-dashboard` Traefik sidecar (host-net,
  pinned `traefik_version`) publishes `spark_home_ip:11000 → 127.0.0.1:11000`, i.e. the dashboard is
  reachable at **`http://spark.kogler.si:11000`** on the Home VLAN with a local-user login (the dashboard's
  own auth sits in front; never `0.0.0.0`, no public record; its Software-Update flow still needs the
  SSH-tunnel path). Disable via the registry entry `enabled: false`.
- **URL of record = the short name (HD-451, 2026-09-23):** browse **`https://spark.kogler.si`** on the
  Home VLAN and **`https://spark.ts.kogler.si`** off-LAN. `db-spark.kogler.si` / `db-spark.ts.kogler.si`
  are **LEGACY** (owner decision 2026-09-23): still routed on both edges so old links work, but no new
  consumer may be written against them.
  - The short name reaches :443 through the `spark-dashboard-name` router (one rule matching both
    `spark.kogler.si` and `spark.ts.kogler.si`, hsts, TLS from the default store) and the
    `spark-dashboard-name-http` :80→:443 pair. Before HD-451 the plain name resolved and terminated
    TLS but had **no** :443 router → Traefik 404 (measured), while `:11000` answered 200.
  - **Off-LAN is `.ts`-only on purpose.** Publishing the plain host name into MagicDNS
    (`tailnet_subdomains`) would answer every tailnet client with the edge IP for the name the
    inventory, `docs/` and the humans use for the box itself — the HD-382/389 resolver-ambiguity trap,
    and a new VPS dependency for a page the LAN already serves. Neither name is ever a Cloudflare
    record (`dig A spark.kogler.si @1.1.1.1` = no answer, measured 2026-09-23, and it must stay so).
  - **Route edits on this edge must not restart it.** `spark-dashboard` is a file-provider edge
    (`--providers.file.watch=true`) AND the `llm.kogler.si` name edge, so a restart is a 502 window on
    inference: it is therefore in the restart-guard exclusion list in
    `roles/docker_services/tasks/deploy-service.yml` (HD-451). Proven 2026-09-23: the route converge
    re-rendered `dynamic/routes.yml` while `traefik-spark` kept its id and `StartedAt`, and
    `llm.kogler.si/health` stayed 200 throughout.
  - **The routes must use an explicit `Host(spark.kogler.si)` rule.** A `HostRegexp({host:.+})` catch-all
    silently matches nothing on this Traefik v3.7 → own 404 for every request including `/api` and `/ping`.
    **IP-host requests 404 by design** — browse by name.
  - The spark role sets `net.ipv4.ip_nonlocal_bind=1` so the LAN-address bind is deterministic at container
    start (otherwise `EADDRNOTAVAIL` until the interface settles).
  - The healthcheck must be `["CMD","traefik","healthcheck","--ping"]` — a stale duplicate `healthcheck:`
    block (probing `:8080`) silently overrides it and the container reports unhealthy/healthy wrongly.
  - **A socat bridge is not the pattern here:** one socat argv = exactly ONE address pair, so a four-argv
    compose command list crash-loops on every reboot. The Traefik file-provider sidecar replaced it.
- **Retired stack stays retired via a tombstone (HD-379):** the old `/opt/dgx-dashboard/docker-compose.yml`
  + its **enabled** `docker-compose@dgx-dashboard.service` boot unit resurrected the socat container on
  every boot, crash-looping forever (it can no longer bind `spark_home_ip:11000`; Traefik owns it).
  `group_vars/spark.yml` now carries a `dgx-dashboard` **tombstone** entry with `enabled: false`, so the
  role's "Tear down DISABLED services" + "Disable boot auto-start" tasks keep it gone on every converge and
  after a reboot (nothing renders from a disabled entry — the vault pre-pass and the deploy loops both skip
  it). ⏳ Delete the tombstone once the teardown has run green on spark twice.
- **JupyterLab on the LAN (HD-366):** the dashboard ships an **integrated JupyterLab** whose per-user ports
  are in `/opt/nvidia/dgx-dashboard-service/jupyterlab_ports.yaml` (nobody 11001 / **admin 11002** /
  ansible-admin 11003). NVIDIA's own remote path is a second SSH tunnel per assigned port; the same
  `spark-dashboard` Traefik edge also publishes `spark_home_ip:11002 → 127.0.0.1:11002` (add more by
  appending entrypoint+route pairs in the template). JupyterLab spawns **on demand** from the dashboard's
  JupyterLab panel — until a lab is Running, loopback:11002 has no listener and the route idles (the
  healthcheck stays on :11000 only). Once Running, browse to `http://spark.kogler.si:11002`.
- **GB10 bring-up reference:** [`martimramos/dgx-spark-ml-guide`](https://github.com/martimramos/dgx-spark-ml-guide) —
  PyTorch-nightly (sm_121), no ARM64 wheels, CPU/Python gotchas; run ML **container-native** (Docker
  isolates CUDA/Python — the guide's own recommended path).
- Power: 240 W USB-C PD; the OS cannot see the PSU at all (no `/sys/class/power_supply` entry), so UPS
  coverage is rack-side only ([`hardware-ups.md`](hardware-ups.md)).

---

## Hardware

> **Two tables on purpose.** §Vendor spec is what Lenovo/NVIDIA ship for MTM 30KL (PSREF + Lenovo Press
> LP2321). §As-measured is what THIS unit reports over `ssh spark` (commands in §Capture commands).
> Measured wins for placement/perf planning; §Reality deltas names every disagreement.

### Identity

| Field | Value | Source |
|-------|-------|--------|
| Vendor / model | Lenovo **ThinkStation PGX** (NVIDIA GB10) | `hostnamectl` Hardware Vendor/Model |
| Machine type (MTM) | `30KL0002GF` | `dmidecode -s system-product-name` (= `DGX_PLATFORM`) |
| **Serial number** | **`MP30A60N`** | `/etc/dgx-release` `DGX_SERIAL_NUMBER` = `sudo dmidecode -s system-serial-number` |
| SKU string | `LENOVO_MT_30KL_BU_Think_FM_ThinkStation PGX` | `dmidecode -s system-sku-number` |
| Firmware | UEFI **`S0QKT0EA`** dated 2026-07-13 (AMI), UEFI boot, TPM 2.0 (`/dev/tpm0` v2) | `hostnamectl` / `dmidecode -s bios-version` |
| OS | Ubuntu **24.04.5 LTS** (noble), kernel `7.0.0-1019-nvidia` arm64 | `/etc/os-release`, `uname -mr` |
| DGX OS | base image 7.4.0 → OTA **7.6.0** | `/etc/dgx-release` |
| GPU | UUID `GPU-d5ad56cc-01cf-7521-4c4e-e215e7ccd76b`, PCI id `10de:2e12` @ `000f:01:00.0`, driver **580.178.04** (`nvidia-driver-580-open`, re-measured 2026-09-28 — it read **580.173.02** when this row was taken), compute cap **12.1** = **sm_121** | `nvidia-smi --query-gpu=...`, `lspci -nn`, `dpkg -l` |
| CUDA / runtime | CUDA **13.0**, `nvidia-container-toolkit` **1.20.0** | `ls -d /usr/local/cuda-*`, `dpkg -l` |
| machine-id | `a7c5519de45d4244be889d2af3749476` | `/etc/machine-id` |
| Ethernet MAC | `38:a7:46:78:13:97` (`enP7s7`; `enP7s7.99` shares it — VLAN subinterface) | `ip -br link` |
| Wi-Fi MAC | `ec:3a:56:cc:9f:70` (`wlP9s9`) — **DOWN**, unused on a headless box | `ip -br link` |

> **Reading the serial on this platform (not obvious):** `/proc/device-tree/serial-number` does **not exist**
> here (the PGX carries identity in SMBIOS, not the Jetson-style device-tree) and
> `/sys/class/dmi/id/product_serial` reads **empty without root**. Two reliable reads:
> `cat /etc/dgx-release` (`DGX_SERIAL_NUMBER=`) or `sudo dmidecode -s system-serial-number`.
> `dmidecode -s system-vendor` and every `board-*` string return **EMPTY** on this firmware — take
> vendor/model from `hostnamectl`.

### As-measured

| Component | Measured on this unit |
|-----------|----------------------|
| Superchip | NVIDIA **GB10** Grace Blackwell — one SoC, no discrete PCIe GPU |
| CPU | 20 cores / 1 socket arm64: **10× Cortex-X925** (max 3900 MHz) + **10× Cortex-A725** (max 2808 MHz); L1d + L1i 1.3 MiB each (20 inst.), L2 25 MiB (20 inst.), L3 24 MiB (2 inst.); **single NUMA node** |
| Unified memory | **128 GB LPDDR5 @ 8533 MT/s**, one soldered package (`DIMM0`; SMBIOS max capacity 128 GB → **not expandable**), **no ECC**. Usable pool = `MemTotal` 127,532,360 kB ≈ **121.62 GiB** (rest held by SoC/ATF) |
| Swap | `/swap.img` **16 GiB** on root ext4 (no zram) — inside the same unified pool, so it buys no headroom |
| GPU function | `000f:01:00.0` driver `nvidia`; `memory.total` / `memory.used` / `power.limit` report **N/A** (unified memory). `LnkSta x1 (downgraded)` is an SoC-integrated artifact, **not** a slot negotiation |
| NVMe (the only disk) | **SK hynix `HFS001TEM4X169N` 1 TB** (`1c5c:1f69`), S/N `5SF1N437313401M59`, FW `61700A30`; by-id `nvme-eui.ace42e00650eb44a`; **PCIe 4.0 ×4 at full 16 GT/s** |
| Partition layout | `p1` 512 M vfat → `/boot/efi` · `p2` **450 G** ext4 → `/` (**the live root**) · `p3` **503.4 G** xfs → `/mnt/spark_nvme` (HD-363 carve, `noatime,nodiratime`) — the whole disk, **no unallocated room** |
| NVMe SMART | PASS · Percentage Used **0 %** · spare 100 % · media/integrity errors **0** · written ~1 TB / read ~7 TB · low power-on hours but a high power-cycle + unsafe-shutdown count (the documented wedges + power-cycles) · 48 °C (critical 87 °C) |
| Ethernet | **Realtek RTL8127** `10ec:8127` rev 05, driver **`r8127`**, iface `enP7s7`. Advertises 10000/2500/1000/100/10 — **partnered at 1000 Mb/s full-duplex** ⚠️ delta 1 |
| Wireless | **MediaTek MT7925** `14c3:7925` (Wi-Fi 7 class) on `wlP9s9` + BT `13d3:3630` — radio DOWN |
| USB | 6× xhci controllers = **12 root hubs** (each pair: one 480 M USB-2 + one 20000 M/x2 USB4-class root); no `usb4`/thunderbolt bus devices registered |
| Display | one DRM connector `card0-Unknown-1` (HDMI 2.1a) — unused, headless |
| Scale-out ports | **nothing enumerated** — no Mellanox (`15b3`) PCI function, no `infiniband` device, no extra netdev; `mlx5_core`/`mlx5_ib` loaded but unbound ⚠️ delta 2 |
| Security | UEFI + **TPM 2.0** present. AES SED self-encryption of the NVMe is a **vendor claim** — no readable SED state via `nvme id-ctrl`, NOT verified |
| Power | 240 W USB-C PD 3.1 PSU (vendor spec). **No `/sys/class/power_supply` entry** — UPS coverage is rack-side only (`hardware-ups.md`) |

### Reality deltas vs vendor spec

1. **10 GbE is not achieved on the wire** — the negotiated 1000 Mb/s is **structural**: the cable lands on
   RB4011 `ether8`, a 10/100/1000 port, and the RB4011iGS+ has **no 10 G copper port at all**. Accepted as
   final; no CRS328 move is planned (see §Network / placement). Planning consequence: weight staging over
   1 G is the real cost.
2. **No ConnectX-7 / QSFP function exists in the running system** — `lspci` shows zero Mellanox devices and
   two GB10 root ports training Gen1 x4 with nothing behind them. The "2-node scale-out to 405B" line is
   therefore **not usable today**; per Lenovo the QSFP pair is PGX↔PGX clustering only (cables sold
   separately), never general LAN. Re-check after a DGX OS / UEFI update.
3. **Storage is the 1 TB SKU**, not the 4 TB option — capacity planning must never assume 4 TB.
4. **"LPDDR5x" (PSREF) vs SMBIOS "LPDDR5 @ 8533 MT/s"** — same soldered part, different label; PSREF quotes
   273 GB/s. No action.
5. **`nvidia-smi` is not a memory gauge on GB10** — see §Unified-memory budget.

### Capture commands (re-derive, read-only)

```sh
ssh spark 'cat /etc/dgx-release; hostnamectl; uname -mr'
ssh spark 'sudo dmidecode -s system-serial-number; sudo dmidecode -s system-product-name; sudo dmidecode -s bios-version'
ssh spark 'lscpu | grep -E "Model name|CPU\(s\)|MHz|L2|L3"; grep MemTotal /proc/meminfo; sudo dmidecode -t 16 -t 17'
ssh spark 'nvidia-smi --query-gpu=name,driver_version,uuid,compute_cap,temperature.gpu,clocks.sm,clocks.max.sm --format=csv'
ssh spark 'sudo nvme list; sudo smartctl -H -A /dev/nvme0; ls -l /dev/disk/by-id/; lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS /dev/nvme0n1'
ssh spark 'lspci -nn; sudo ethtool enP7s7 | grep -E "Speed|link modes"; ip -br link'
```

(The other hosts use [`../scripts/collect-disk-facts.sh`](../scripts/collect-disk-facts.sh) from a
console/live USB; spark is SSH-reachable, so the inline sweep above is enough.)

### Vendor spec (Lenovo PSREF / Lenovo Press LP2321, MTM 30KL)

| Component | Specification |
|-----------|---------------|
| Superchip | **NVIDIA GB10 Grace Blackwell** (same silicon as DGX Spark) |
| CPU | NVIDIA Grace 20-core **Arm** — 10× Cortex-X925 + 10× Cortex-A725 |
| GPU | Blackwell — 5th-gen Tensor Cores, 4th-gen RT Cores, NVENC/NVDEC |
| AI performance | **1000 TOPS · 1 PFLOP (FP4, sparsity)** |
| Unified memory | **128 GB LPDDR5x** (256-bit, 273 GB/s) — shared CPU/GPU |
| Storage | 1 TB **or** 4 TB NVMe M.2 (self-encrypting, AES SED) — **this unit: 1 TB SK hynix** |
| Power | **240 W** USB-C PD 3.1 PSU |
| Form factor | 1.13 L SFF (150 × 150 × 50.5 mm, ~1.2 kg) |
| Network | 10 GbE RJ-45 (Realtek on this unit) + 2× QSFP 200 G for ConnectX-7 (2-node scale-out to 405B); ⚠️ **neither is live here** — link is 1 G, no ConnectX function enumerated |
| Wireless | Wi-Fi 7, Bluetooth 5.3 LE |
| Ports | 3× USB-C USB4 (20 Gb/s, DP 2.1), HDMI 2.1a, RJ-45 10GbE, 2× QSFP |
| OS | NVIDIA DGX OS / Ubuntu Pro with NVIDIA Base OS, **CUDA 13** — live: DGX Spark 7.6.0 on Ubuntu 24.04.5, CUDA 13.0, driver 580.178.04 (was 580.173.02) |
| Security | Self-encrypting NVMe (AES SED), **TPM 2.0**, NVLink-C2C enclave, NVIDIA FW recovery, AMI setup password, UEFI Secure Boot (only TPM 2.0 + UEFI verified here) |

## Bring-up order (what a true-zero rebuild needs)

Procedure steps live in [`../deployment-manual.md`](../deployment-manual.md); this is the ordering + the
reasons. IaC: inventory group `spark` + `host_vars/spark.kogler.si.yml` + the `spark` role (NVMe **p3** →
XFS for PLE/KV, HD-363 — **p2 is the live root**) + `playbooks/spark.yml`; the standalone `spark/ansible`
tree is the reference implementation.

1. DGX OS / Ubuntu Base OS install (headless; CUDA 13, GB10 `sm_121`), first-boot wizard →
   admin credential from the `spark_login` vault item, analytics off, updates + reboot.
2. Ansible placement: `network_static_hosts` reservations (never hardcoded), rack residency, UPS coverage,
   the headless contract (§Remote management).
3. **Reachability before inference work:** HD-155 `wg-s2s` AllowedIPs entry for spark + the router
   forward-accept delta — a network change, not inference config. Adding the AllowedIPs entry is not
   enough: the VPS route must be re-applied ([network-vpn.md](network-vpn.md) §Layer 1).
4. `spark-artifacts` staging (weights/overlays/tables onto XFS) — heavy and slow over 1 G, human-gated.
5. Engine (`spark-ai`) enable + the §Bench certification gates, then the name edge + LiteLLM registration.

## Document Map

| For | Read |
|-----|------|
| Client-side AI on the laptop (FIM autocomplete, visual judgment) | [`hardware-workstation.md`](hardware-workstation.md) |
| GPU resource / modes (oldsrv) | [`hardware-gpu.md`](hardware-gpu.md) |
| AI platform (models, LiteLLM, Open WebUI, agents) | [`services-ai.md`](services-ai.md) |
| Measured inference numbers behind the placement decisions | [`services-ai-bench.md`](services-ai-bench.md) |
| Network / VLAN placement | [`network-vlans.md`](network-vlans.md) |
| Spark benchmark + engine bench plan | [`../spark/BENCHMARK-PLAN.md`](../spark/BENCHMARK-PLAN.md) |
| **Unified-memory budget / GPU×host memory sizing** | this doc §Unified-memory budget & OOM governance |
| **OOM / engine-restart incidents (append-only)** | [`spark-incidents.md`](spark-incidents.md) |
| Old superseded Phase-2 build | decision log [`deployment-rejected.md`](deployment-rejected.md) |
