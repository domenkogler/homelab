---
title: spark — OOM / engine-restart incident log
role: incident-log
domain: hardware
status: active
tags: [hardware, spark, gb10, oom, incidents, append-only]
---
# spark — OOM / engine-restart incident log

> **Role:** Append-only incident log for the spark (GB10) vLLM engine — the global-OOM / restart class.
> Each entry records what was live, what the kernel did, and what changed.
> **Links to:** `hardware-spark.md` (§Unified-memory budget & OOM governance = the *reason*/knowledge),
> `observability.md` (§Alerting → spark host memory), `hardware-gpu.md`
> **Linked from:** `hardware-spark.md`, `index.md`

> **Why separate:** `hardware-spark.md` holds the permanent memory-organization knowledge (the budget
> model, sizing table, governor choice); this file holds the **dated incident forensics**. The two are
> coupled: every incident below is an instance of the model in `hardware-spark.md` §Unified-memory budget.

---

## Incident table

Same failure class, escalating evidence. Summary row per incident; full narrative below.

| # | Date (UTC) | During | Kernel evidence | Outcome | Fix landed |
|---|-----------|--------|-----------------|---------|-----------|
| 0a | 2026-09-15 00:50 | model load @ util 0.93 / ctx 173400 | `global_oom` + `NVRM NV_ERR_NO_MEMORY` took `nvidia-persistenced` down | box OOM at **every** boot | util 0.93→**0.70**, ctx→**65536**, cage 126G→**105G** (`session/spark-b1-memfit-20260915-0050`) |
| 0b | 2026-09-15 02:50 | C3 sanity bench 12×8k @ concurrency 3 | `NVRM` memdesc + global OOM; killed `sshd`/`NetworkManager`/`polkitd` | container survived cage; **host wedged** → power-cycle | harness: C3→6×8k@c2 + `MEM_FLOOR_GB` preflight |
| 1 | 2026-09-15 22:31 | serve, engine wedged mid-request | no kernel OOM; engine hung (`shm_broadcast` 60 s stalls) | container restarted (new boot banner) | attributed post-hoc to thrash, not a kill |
| 2 | 2026-09-15 23:06 | serve, long request in flight (`num_computed_tokens=36800`, +4864 scheduled) | `global_oom` 23:05:53→23:06:32: `VLLM::Worker` (total-vm 151 GB), `VLLM::EngineCor`, `python3`, `torch_shm_manag`; collateral `alloy`/`traefik`/`nvidia-smi`/`dozzle`/`fwupd` | `unless-stopped` restart @ 23:06:34 → `RestartCount=2` | none (diagnosis only — session died) |
| 4 | 2026-09-16 16:31 | **NOTHING attached — zero clients, engine idle** | `global_oom` 16:31:20: `python3` in the vLLM scope (total-vm 55.4 GB), then `alloy` (uid 996) | container replaced → boot banner 16:31:38Z | none at the time — **the unexplained one: no workload to blame** |
| 5 | 2026-09-16 20:21 | **two agent sessions at 8.8% / 9.1% of ctx** (46.9k tok combined) | `global_oom` 20:21:07→20:22:05: `python3` → `VLLM::Worker` (total-vm **155.6 GB**) → `VLLM::EngineCor` → `python3`; collateral `dcgm-exporter`, `alloy` | `RestartCount=4`, `StartedAt=20:22:11Z`; both client sessions `stopReason=error` | none at the time (diagnosis session = this one) |
| 7 | 2026-09-16 23:26 | serve, **one light pi session**, KV 43–59 %, prefix hit 94 %, engine 0 % util at kill | `global_oom` ×9 23:23:28→23:26:00: `torch_shm_manag`, `dozzle`, **`traefik`**, `nvidia-smi`, `dashboard-servi`/`dashboard-admin`, `fwupd`, `cups-browsed`, `colord` — engine itself survived; `CmaFree` **8.81 GiB** inside `MemAvailable` 10.45 GiB → **1.64 GiB** actually claimable | engine `Exited (137)`; host wedge + LLM outage; load avg 36.4 | C1+C2 (HD-381) applied; **gauge correction → B** |
| 8 | 2026-09-17 14:55 | serve, same profile, 1 h 34 m after boot | `global_oom` ×3 14:55:31: **`python3` = engine PID-1 (`oom_score_adj=-500`)**, `dcgm-exporter`, `alloy`; `Node 0 Normal free:9.63 GiB` was **`free_cma:9.58 GiB`**, `all_unreclaimable? yes` | engine top-pid **frozen at 109,785 MiB for 4+ min before the kill** (allocator stall, not a burst); PSI full **92.5** | C1+C2 converged 15:28Z (same boot) |
| 6 | 2026-09-16 22:15 | **agent session ~162k tok + stress step A6 (16k × conc 2)** | **NO kernel OOM** (last kill 20:22Z) — bench guard ran `docker stop`; engine `Exited (137)` | avail **21.5 → 12.6 GiB in ~22 s**; watchdog WARN 22:13:49 → CRIT 22:15:22 (avail 18.6, PSI 27.2); **~14 min outage** because `unless-stopped` ignores an intentional stop | **HD-380** — capture-size cap + watchdog + self-healing guard + zero-load bench assertion |

## Incident #3 — the self-referential OOM (2026-09-16)

**Timeline (all UTC; local = UTC+2):**

- 08:55–09:21 — an agent session **on the laptop** ran against spark's own vLLM endpoint
  (`spark/qwen3.8-flash-next`) doing live diagnosis of the previous restarts; at 09:21 it read
  `docs/hardware-spark.md` (the intended SSOT write).
- 09:22–09:26 — kernel `global_oom` cascade: user-slice processes first (`pipewire`,
  `pipewire-pulse`, `dbus-daemon`, `systemd`, `(sd-pam)` — the `admin`/user-1001 desktop session),
  then **`python3` pid=1023317 = the vLLM container's PID-1** at 09:26:17.
- 09:26:20 — `localhost:8000` went away → the client session received **502 Bad Gateway**
  (repeatedly) and terminated (session log shows consecutive 502s).

**Evidence (verified live on the box, read-only):**

```
docker inspect  → RestartCount=3, OOMKilled=false, StartedAt=2026-09-16T09:26:20Z
dmesg           → 09:26:17 global_oom, task_memcg=/system.slice/docker-0efc3204...scope,
                  task=python3, pid=1023317, total-vm:24,165,964kB, anon-rss:76kB  (thrashed out)
free -h now     → Mem 108/121 GiB used, 3.3 GiB free, 4.4 GiB swap in use  (still hot)
```

**Why it happened (the mechanism, per `hardware-spark.md` §Unified-memory budget):** the engine was
running the *certified casual* config (0.82 util / 262k ctx), which leaves only ~21.9 GiB for the
entire OS, and the GPU carve-out is **not cgroup-charged** → the `105G` cage never triggered, Docker
reported `OOMKilled=false`/`ExitCode 0` (false negative), and the kernel's OOM killer picked the user
session before the engine. Sustained **agentic/window-heavy** inference (the exact workload the S1
sweep had explicitly NOT certified — it was certified for *casual/chat*) exhausted the reserve.

**Fix (this change):** explicit `--kv-cache-memory-bytes 8800000000` (the ONLY dial — this build
ignores `gpu_memory_utilization` when the bytes flag is set, so util is removed) → host reserve
~21.9 → ~32.5 GiB. See `hardware-spark.md` §Chosen governor. **Side-effect lesson:** running an
agent session against spark's own endpoint means *this repo's own tooling* can OOM the box it runs on;
the fix is governance, not workload discipline.

> ✅ **DEPLOYED + LIVE-VERIFIED 2026-09-16** (detached spark converge `converge-spark-hd374-20260916-123756.log`,
> failed=0, ok=96 changed=13). Boot log: `gpu_worker.py:621` — *"Initial free memory 114.65 GiB, reserved
> 8.2 GiB memory for KV Cache as specified by kv_cache_memory_bytes config and skipped memory profiling.
> This does not respect the gpu_memory_utilization config"*; `GPU KV cache size: 283,398 tokens`,
> concurrency @262k **1.08x**; `/health` **200**; model load 75.17 GiB / 170 s; **host `MemAvailable` 24 GiB
> during load** (pre-fix: ~9–13 GiB at the OOM). `RestartCount=0`, no `ValueError`, no OOM.

---

## Incidents #4/#5/#6 — the HD-374 fix did NOT hold, and what it was actually hiding (2026-09-16)

HD-374 (deployed + live-verified 2026-09-16 ~12:37Z) predicted **host reserve ≈ 32.5 GiB**
from `weights 77.69 + act 2.99 + graphs 0.22 + KV 8.2 ≈ 89.1 GiB`. Two global OOMs followed
within hours (#4 with **no client attached at all**, #5 with two 9%-context sessions), and the
predicted reserve **never existed**.

**Measured, at rest, engine idle:**

```
nvidia-smi --query-compute-apps  →  engine pid 103,449 MiB, later 105,477 MiB  (RATCHETING +2.0 GiB / 45 min idle)
/proc/meminfo                   →  MemAvailable 16.7 GiB (not 32.5), MemFree 0.8 GiB, swap 8.3 GiB used
vLLM's own accounting           →  weights 75.17 + KV 8.2 = 83.4 GiB  ⇒ ~22 GiB unaccounted
```

The `graphs 0.22 GiB` line in that budget was **wrong by ~40×**. This build captures CUDA graphs
for batch sizes **[1,2,4,8,16,24,32]**, but `max_num_seqs=4` caps the decode batch at 4 — so sizes
8/16/24/32 are **captured and can never be used**, and on GB10 every one of them is a hole in the
single 121.62 GiB pool. Capping to 4 (`--max-cudagraph-capture-size 4`, HD-380):

| | before (cap 32) | after (cap 4) |
|---|---|---|
| engine per-pid, at rest | 105,477 MiB | **96,235 MiB** (−7.2 GiB) |
| host `MemAvailable` | 16.7 GiB | **22.2 GiB** (+5.5 GiB) |

**Still open after the cap:** ~13 GiB of non-KV, non-weight allocation remains — unprofiled and
unbounded, because `--kv-cache-memory-bytes` makes vLLM *skip memory profiling* by design. The cap
raised the resting floor; **it did not bound the peak.** Incident #6 proves the peak is still live.

**Incident #6 — the measured version of incident #3.** The engine's own log (preserved inside the
watchdog's CRIT bundle) shows what a large agent session costs:

```
22:48:07  prompt throughput 17008.1 tok/s   KV usage 81.9%   Prefix cache hit rate 0.0%
```

An agent session at ~162k tokens = **56% of the 283,398-token KV pool by itself**, and with prefix
hit **0%** every turn re-prefills the **entire window** — the largest transient this engine can
produce. Combined with stress step A6 (16k × conc 2) it took `MemAvailable` 21.5 → 12.6 GiB in ~22 s.
**Self-reinforcing loop:** big context → one session occupies ~82% of KV → its own prefix blocks are
evicted between turns → hit rate → 0% → full re-prefill every turn → max spike. Note the guard,
not the kernel, ended it: **no `oom-kill` line exists at 22:15Z**.

**Tooling failure modes found (both cost real availability):**
1. `docker stop` is an **intentional** stop → `restart: unless-stopped` does **not** restart it. The
   guard's stop therefore looked exactly like an engine crash and left the family without an LLM for
   ~14 min. Guard now self-heals (`cbd6960`).
2. `vllm bench serve` against the `--api-key` engine 401s **every request and still exits 0**,
   reporting `Successful requests: 0`. The first HD-380 run "passed" 21 steps while applying **zero
   load**. **Any bench number taken after the `spark-llm_api` vault item landed is invalid until
   re-run** (`run-scenario.sh` carried the same defect; both now assert on the counters).

**Ruled out, with numbers — do not re-litigate:**
- **dcgm-exporter leak:** `memory.peak` **0.19 GiB** lifetime against a 256 MiB cap, `max/oom/oom_kill`
  events **0**, killed at **3 resident pages**, 51 s *after* the engine. HD-379 had already capped it
  42 min before the next kill.
- **More swap:** the killer fired with **SwapFree 8.25 of 16.77 GiB** — swap was half unused.
- **zram:** whole-box `AnonPages` **0.55 GiB** with 8.3 GiB already swapped, and refault
  **file:anon = 42:1**. zram only acts on anon, and spends the very DRAM the GPU carve needs.
- **Concurrency as cause (#5):** 46.9k tokens combined = 18% of window. But #6 shows an agent session
  at ~162k **is** a first-class memory term — different magnitude, same class as #3.

---

## Incidents #7/#8 — `MemAvailable` is the wrong gauge, and the growth is traffic-cumulative (2026-09-16/17)

Two more global OOMs **after** HD-380's capture-size cap had already lowered the floor
(105,477 → 96,235 MiB). Both bundles are intact: `/mnt/spark_nvme/oom-watchdog/snapshots/20260916-232600-KILL/`
and `…/20260917-145531-KILL/`. These are the two findings that changed the plan.

### Finding A — on GB10, `MemAvailable` overstates headroom by up to ~9.5 GiB

Both kills recorded a kernel `Node 0 Normal free` that was almost entirely **`free_cma`** —
device-reserved pages the CMA allocator will not hand to an unmovable `GFP_KERNEL` allocation:

| | #7 (23:26:00Z) | #8 (14:55:31Z) |
|---|---|---|
| `MemAvailable` (what the watchdog watched) | 10.43 GiB | 10.39 GiB |
| `MemFree` | 10.97 GiB | 10.91 GiB |
| **`CmaFree`** | **8.81 GiB** | **8.78 GiB** |
| **usable = `MemAvailable` − `CmaFree`** | **1.64 GiB** | **1.62 GiB** |
| *(healthy idle, same box)* | *26.25* → **26.13 usable** | *same* |
| last sampler `psi_full_avg10` | 97.8 | 92.5 |

`free -h` therefore said “~10 GiB free” while **~85 % of that figure was CMA** the device
would not surrender to an unmovable allocation. The HD-375 / HD-380 thresholds (WARN 24 /
CRIT 16 GiB on `MemAvailable`) were **overstated by up to ~9 GiB**, and worse: as the GPU
carve is squeezed `CmaFree` *grows*, and CMA counts as available — so the metric
**inflates as pressure rises**. That is why an alert on it kept missing the cliff and the
watchdog had to narrate after the fact.

> ⚠ **The first proposed fix was wrong — do not re-propose it.** The 2026-09-17 plan
> prescribed `usable = MemFree − CmaFree` with WARN 4 / CRIT 2. Measured on this box that
> gauge is **INVERTED**: healthy idle = **0.74 GiB**, the two kills = **2.17 / 2.14 GiB** — it
> reads *lower* at rest than at a kill, so those thresholds fire permanently and the planned
> enforcing CRIT action would have **restart-stormed the engine on a healthy box** (an outage
> caused by the safety net). `MemFree` is meant to sit ≈1 GiB at steady state — the rest is
> page cache doing its job — and under pressure reclaim *evicts* cache, so `MemFree` **rises**
> to ~11 GiB, mostly CMA-attributed. It measures “reclaimed but not yet consumed”: high in a
> storm, low at rest. The 0.05 GiB figure that motivated it came from the kernel's **per-zone**
> dump (`Node 0 Normal free:9.63 GiB free_cma:9.58 GiB`), which is zone/migratetype-local and
> not reconstructible from global `meminfo`.
> Correct global gauge: **`MemAvailable − CmaFree`** — monotone with danger (26.1 idle → 1.6
> at both kills).

PSI is a valid *confirmation* trigger but carries **no lead time**: in #8 `psi_full_avg10` read
**0.0 for ten consecutive samples** at avail 9.4 GiB, then the kill. It cannot be the primary
early warning.

```bash
usable_gib = MemAvailable − CmaFree     # WARN < 8 GiB, CRIT < 4 GiB (kills measured at 1.6)
```

Both kills passed the PSI trigger (`psi_full` 97.8 / 92.5) at the same sample as the kill — PSI is a
valid independent trigger and stays.

### Finding B — the climb is traffic-cumulative and FLAT at idle (corrects HD-380 open item 5)

| Boot | Engine top-pid | `MemAvailable` | Traffic |
|---|---|---|---|
| 2026-09-16 12:59 | 88,773 MiB | 24.2 GiB | **none 23:35Z → 03:27Z, flat overnight** |
| same, +1 light pi session ~30 min | 88,773 → **109,785 MiB** | 24.5 → **9.6 GiB** | one pi session, KV 43–59 %, prefix hit 94 %, 0 % util at kill |
| 2026-09-17 15:28 (post-C1+C2) | 85,445 MiB load → 86,243 | 26.9 GiB | light |

There is **no idle ratchet** — HD-380 open item 5 (“idle-ratchet trend resumed after restart”) is
retracted: what looked like a leak was the residue of prior traffic. The engine grows **per request
shape and never returns it**, which is an allocator/graph-growth mechanism, not a KV pressure
mechanism — and it is therefore reset only by a restart, and bounded only by removing the mechanism
(C1 `expandable_segments`, C2 smaller prefill chunks, C3 eager). It also makes an agent session a
first-class memory term *beyond* its KV occupancy: **a light session is enough**.

### The top-pid freeze is the signature to watch

At both kills `gpu_top_mib` was **constant for minutes** (109,681 and 109,785) while `psi_full`
saturated. A flat top-pid + saturating PSI = the allocator can no longer get pages; it is the
predictable pre-kill state an enforcing governor (plan item **B**) must act on, not merely record.

### Why #8 killed the engine and #7 did not

#7's victims were collateral (traefik, dashboard, dozzle, fwupd…) — the killer went after unprivileged
user-slices first, and the box wedged anyway. #8 killed **engine PID-1 despite `oom_score_adj=-500`**:
with `all_unreclaimable? yes` there was nothing else left. Confirms invariant #3 (kill order is not
engine-first) is a lottery, and that the cage cannot protect the host (invariant #1).

---

## Cross-incident invariants

1. **`OOMKilled: false` / `ExitCode: 0` every time** — Docker never sees it (global OOM, not cgroup).
2. **The engine's `RSS` was tiny** at kill time (`anon-rss:112kB` on a 151 GB total-vm process in #2;
   `76kB` in #3) — it had been **swapped out**: the box was *thrashing*, not merely full. A swap-flush
   stall (~3.5 min; observed: log lines with internal timestamps 22:52–22:56 reached the json-file
   driver at 22:59:24) precedes the kill and looks like an engine hang.
3. **Kill order is not engine-first.** User-slice/systemd processes die before the engine, so the
   observed symptom is often "session/SSH died", not "model crashed".
4. **It recurs whenever load returns** — each fix moved the OOM later, it did not remove it, until the
   budget became explicit (#3, this change).
5. **`MemAvailable` alone is not the budget metric on GB10** (#7/#8) — up to ~9 GiB of it can be
   `CmaFree`, which the device will not surrender to an unmovable kernel allocation. Budget in
   **`MemAvailable − CmaFree`** (+ PSI memory as confirmation, which carries *no* lead time).
   **Not** `MemFree − CmaFree` — that is inverted here (0.74 GiB idle vs 2.17 GiB at a kill).
6. **The engine's non-KV footprint grows with traffic and never returns** (#7/#8) — flat at idle, so a
   restart is the only reset, and only removing the allocation mechanism bounds the peak.

---

## Diagnosis recipe (read-only, safe, run this first)

```bash
# 1. What the container says (NOT authoritative for OOM — see invariant #1)
docker inspect <ctr> --format 'RestartCount={{.RestartCount}} OOMKilled={{.State.OOMKilled}} StartedAt={{.State.StartedAt}}'

# 2. What the kernel says (AUTHORITATIVE — is it a global OOM?)
sudo dmesg -T | grep -E 'invoked oom-killer|oom-kill:|Out of memory: Killed process' | tail -30
#    key selector: constraint=CONSTRAINT_NONE ... global_oom → host-wide kill (cgroup limit NOT hit)
#    task_memcg=/system.slice/docker-<id>.scope + task=<name> → which container the victim belonged to

# 3. Engine restart history (counts boot banners, not redeploys)
docker logs --timestamps <ctr> | grep 'version 0.1.dev'

# 4. The budget numbers (feeds the sizing table in hardware-spark.md §Unified-memory budget)
docker logs <ctr> | grep -E 'Model loading took|Available KV cache memory|GPU KV cache size|Free memory on device'

# 5. How hot is the box — use the CORRECTED gauge (#7/#8), not free -h
awk '/^MemAvailable|^MemFree|^CmaFree|^AnonPages|^SwapFree/{print}' /proc/meminfo
awk 'BEGIN{while((getline l<"/proc/meminfo")>0){split(l,a," ");if(a[1]=="MemAvailable:")v=a[2];if(a[1]=="CmaFree:")c=a[2]}printf "usable_gib=%.2f  (WARN<8 CRIT<4)\n",(v-c)/1048576}'
```

**`dmesg` is authoritative; `docker inspect` is not.** A `RestartCount` increment + `OOMKilled=false`
on this box means a global OOM until proven otherwise.

### Instrumented since 2026-09-16 (HD-380) — read this BEFORE manually digging

`spark-oom-watchdog.service` (roles/spark, OOM-immune `OOMScoreAdjust=-1000`) samples every 15 s and
freezes a forensic bundle on kernel-OOM / engine-restart / threshold breach:

```bash
systemctl status spark-oom-watchdog
sudo /usr/local/bin/spark-oom-watchdog.sh status
ls -t /mnt/spark_nvme/oom-watchdog/snapshots/ | head      # KILL | CRIT | WARN | RESTART | MANUAL
tail -50 /mnt/spark_nvme/oom-watchdog/state/samples.csv    # the PRE-event curve (the payload)
# columns: epoch,mem_avail_gib,mem_free,cached,anon,swap_used,psi_some,psi_full,gpu_top_pid_mib,restarts,utc
```

**New measurement trick (incident #6):** `nvidia-smi --query-compute-apps` reports only the **largest
pid** and under-counts the engine's multi-process pool footprint by ~10 GiB. The true footprint is the
**`MemAvailable` jump on stopping the engine** — at 22:15Z avail went **12.6 → 118.6 GiB**, i.e. the
engine held **~106 GiB** of the 121.62 GiB pool while its top pid reported 96,235 MiB.

> **Append-only.** New incidents get a row in the table + a numbered narrative section. The *knowledge*
> (why the numbers work, what the governor should be) updates in `hardware-spark.md`, not here.