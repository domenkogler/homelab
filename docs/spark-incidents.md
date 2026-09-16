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

## Cross-incident invariants (all four incidents)

1. **`OOMKilled: false` / `ExitCode: 0` every time** — Docker never sees it (global OOM, not cgroup).
2. **The engine's `RSS` was tiny** at kill time (`anon-rss:112kB` on a 151 GB total-vm process in #2;
   `76kB` in #3) — it had been **swapped out**: the box was *thrashing*, not merely full. A swap-flush
   stall (~3.5 min; observed: log lines with internal timestamps 22:52–22:56 reached the json-file
   driver at 22:59:24) precedes the kill and looks like an engine hang.
3. **Kill order is not engine-first.** User-slice/systemd processes die before the engine, so the
   observed symptom is often "session/SSH died", not "model crashed".
4. **It recurs whenever load returns** — each fix moved the OOM later, it did not remove it, until the
   budget became explicit (#3, this change).

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

# 5. How hot is the box
free -h; grep -E 'MemTotal|MemFree|MemAvailable|AnonPages|Cached|SwapTotal|SwapFree' /proc/meminfo
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