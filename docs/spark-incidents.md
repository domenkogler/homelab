---
title: spark — OOM / engine-restart incident log
role: incident-log
domain: hardware
status: active
tags: [hardware, spark, gb10, oom, incidents, append-only]
---
# spark — OOM / engine-restart incident log

> **Role:** Incident log for the spark (GB10) vLLM engine — the global-OOM / restart class. Every entry is a
> **durable failure mode**: the symptom it leaves, the mechanism behind it, and the guard the system now
> enforces.
> **Links to:** `hardware-spark.md` (§Unified-memory budget & OOM governance = the *reason*/knowledge),
> `observability.md` (§Alerting → spark host memory), `hardware-gpu.md`
> **Linked from:** `hardware-spark.md`, `index.md`

> **Why separate:** `hardware-spark.md` holds the permanent memory-organization knowledge (the budget model,
> the sizing table, the governor choice); this file holds the **failure modes that knowledge was measured
> from** — coupled to it, because every entry is an instance of the model in
> `hardware-spark.md` §Unified-memory budget. Live numbers (thresholds, pools, paths, ports, model names) are
> stated there and in `IaC/ansible/group_vars/spark.yml`; a number quoted here is **evidence taken during the
> incident**, and the live value is always the catalogue's.

## Incident index

Same failure class, escalating evidence.

| # | Symptom | Separating evidence | Mechanism | Guard now enforced |
|---|---------|---------------------|-----------|--------------------|
| 0a | the box OOMs at **every boot**, during model load | `global_oom` + `NVRM NV_ERR_NO_MEMORY`, victim `nvidia-persistenced` | a pool sized by **percent** of the pool leaves no host floor | the pool is named in **bytes** (`--kv-cache-memory-bytes`) and the profile gate refuses a `fixed cost + pool` above the host-floor ceiling |
| 0b | the **host** wedges under a bench step while the container survives the cage | `NVRM` memdesc + global OOM; victims `sshd`, `NetworkManager`, `polkitd` | a bench step can ask for more RAM than the pool's reserve leaves | the harness refuses to run a step below its `USABLE_FLOOR_GIB` preflight floor and keeps C3 at 6×8k@c2 |
| 1 | the engine looks hung mid-request, then comes back with a new boot banner | no kernel `oom-kill` line; `shm_broadcast` 60 s stalls | the box was **thrashing** (swap-flush stall), and a stall reads as an engine hang | a restart with no `oom-kill` line is read off `state/samples.csv` + `state/enforce.log`, not called a crash |
| 2 | engine restarts with a long request in flight; `RestartCount` increments | `global_oom`: `VLLM::Worker` (total-vm 151 GB), `VLLM::EngineCor`, `python3`, `torch_shm_manag`; collateral `alloy`, `traefik`, `nvidia-smi`, `dozzle`, `fwupd` | global OOM, not a cgroup kill — Docker reports `OOMKilled=false` / `ExitCode 0` | `dmesg` is authoritative for the kill; `docker inspect` never is |
| 4 | the engine is replaced with **nothing attached** — zero clients, engine idle | `global_oom`: `python3` in the vLLM scope (total-vm 55.4 GB), then `alloy` (uid 996) | the engine's non-KV growth is traffic-cumulative and flat at idle, so **past** traffic is the load | an idle-box OOM is a budget finding, not a workload finding; the budget metric is `MemAvailable − CmaFree` |
| 5 | two sessions at ~9 % of the window each are enough | `global_oom`: `python3` → `VLLM::Worker` (total-vm 155.6 GB) → `VLLM::EngineCor`; collateral `dcgm-exporter`, `alloy` | a session costs more than its KV occupancy — the allocator grows per request shape and never returns it | sizing carries a *light* session's non-KV growth, not only its tokens |
| 6 | the engine stays down after a guard run that stopped it on purpose; `Exited (137)` | **no** `oom-kill` line anywhere; the watchdog's own CRIT bundle holds the last engine log | `docker stop` is an **intentional** stop, and `restart: unless-stopped` does not answer one | the guard brings the engine back itself (`docker start`), and the bench asserts on its counters |
| 7 | an OOM at a comfortable-looking `MemAvailable` (~10 GiB): engine survives, box wedges | `global_oom` ×9 — `torch_shm_manag`, `dozzle`, `traefik`, `nvidia-smi`, `dashboard-servi`/`dashboard-admin`, `fwupd`, `cups-browsed`, `colord`; `CmaFree` 8.81 GiB inside `MemAvailable` 10.45 GiB → **1.64 GiB** usable | CMA pages are device-reserved: an unmovable `GFP_KERNEL` allocation cannot take them, so `MemAvailable` overstates headroom by up to ~9.5 GiB and **inflates as pressure rises** | the watchdog's WARN/CRIT bands sit on `MemAvailable − CmaFree`; PSI memory is confirmation only (bands: `hardware-spark.md` §The budget METRIC) |
| 8 | the engine itself is killed **despite** `oom_score_adj=-500` | `global_oom` with `all_unreclaimable? yes`; `Node 0 Normal free:9.63 GiB` was `free_cma:9.58 GiB`; top-pid frozen at 109,785 MiB for 4+ min; PSI full 92.5 | nothing reclaimable was left, so kill order became a lottery; the freeze is the allocator failing to get pages | a flat `gpu_top_mib` with saturating PSI is the pre-kill state the enforcer acts on, not just records |
| 9 | "spark crashed" with nothing crashed: host up, `RestartCount=0`, `OOMKilled=false`, `ExitCode=0`, 72 h of kernel log with no `oom-killer` line | `state/enforce.log`: `CRIT-ENFORCED usable=7.94GiB psi_full=0.0` after in-flight deferrals | the declared `fixed_cost_bytes` understated the measured hold (92.13e9 B), so the pool passed its ceiling with no host floor — and a CRIT reading that is a **REST value** is re-derived identically by every restart | enforcement is hysteretic: an enforced restart latches the enforcer **off** until `usable` re-arms at `SPARK_OOM_REARM_GIB` |

---

## Incident #3 — the self-referential OOM

**Symptom.** An agent session running against spark's own vLLM endpoint dies with repeated
**502 Bad Gateway** while the box OOMs, and the victims are the desktop/user slice first
(`pipewire`, `pipewire-pulse`, `dbus-daemon`, `systemd`, `(sd-pam)`), then the vLLM container's **PID-1**
(`python3`, `total-vm:24,165,964kB`, `anon-rss:76kB` — thrashed out, not full). `docker inspect` reads
`OOMKilled=false`.

**Mechanism.** The config carried the pool as a *fraction* of the device, which left ~21.9 GiB for the
entire OS, and the GPU carve-out is **not cgroup-charged** — so the `105G` cage never triggers, Docker
reports a false negative, and the kernel's OOM killer reaches the user session before the engine. The load
that exhausted the reserve was sustained **agentic / window-heavy** inference, a shape the certified
config never claimed.

**Guard.** A profile names its pool in **bytes** (`--kv-cache-memory-bytes` — the only dial; this build
ignores `gpu_memory_utilization` when the bytes flag is set), and the profile gate refuses a profile whose
`fixed cost + pool` crosses the host-floor ceiling. The reserve the fix bought was a *projection*, and the
projection was wrong (§#4/#5) — hence the standing rule in `spark-llm-profiles.md`: **never quote a
projection where the engine prints the number** (`Initial free memory` + `GPU KV cache size` from the boot
log).

**Side-effect lesson.** An agent session against spark's own endpoint means this repo's own tooling can OOM
the box it runs on. The answer is budget governance, not workload discipline — policing which sessions may
run where is a rejected alternative (`services-ai-rejected.md`).

---

## Incidents #4/#5/#6 — the projected reserve never existed

The arithmetic predicted a ~32.5 GiB host reserve from `weights + activations + graphs + KV`. Global OOMs
followed within hours — #4 with **no client attached at all**, #5 with two 9 %-context sessions. Measured at
rest, engine idle, the prediction was false:

```
nvidia-smi --query-compute-apps  →  engine pid 103,449 MiB, later 105,477 MiB  (RATCHETING +2.0 GiB / 45 min idle)
/proc/meminfo                   →  MemAvailable 16.7 GiB (not 32.5), MemFree 0.8 GiB, swap 8.3 GiB used
vLLM's own accounting           →  weights 75.17 + KV 8.2 = 83.4 GiB  ⇒ ~22 GiB unaccounted
```

### The CUDA-graph capture hole

The `graphs` line of that budget was **wrong by ~40×**. The build captures CUDA graphs for batch sizes
**[1,2,4,8,16,24,32]**, while the `max_num_seqs: 4` of that shape caps the decode batch at 4 — so
8/16/24/32 are **captured and can never be used**, and on GB10 every one of them is a hole in the single
121.62 GiB pool. Capping the capture size at the decode-batch ceiling (`--max-cudagraph-capture-size`, which
the profile gate requires to be ≤ `max_num_seqs`):

| | capture cap 32 | capture cap 4 |
|---|---|---|
| engine per-pid, at rest | 105,477 MiB | **96,235 MiB** (−7.2 GiB) |
| host `MemAvailable` | 16.7 GiB | **22.2 GiB** (+5.5 GiB) |

**The cap raises the resting floor; it does not bound the peak.** ~13 GiB of non-KV, non-weight allocation
remains unprofiled and unbounded, because `--kv-cache-memory-bytes` makes vLLM *skip memory profiling* by
design. `max_cudagraph_capture_size > max_num_seqs` is a gate refusal, not a tuning choice.

### The self-reinforcing prefill loop (incident #6)

The engine's own log, preserved in the watchdog's CRIT bundle:

```
prompt throughput 17008.1 tok/s   KV usage 81.9%   Prefix cache hit rate 0.0%
```

A ~162k-token agent session is **56 % of the KV pool it ran against** (283,398 slots on that shape; the
live pool is the catalogue's), and with a **0 %** prefix hit every turn re-prefills the **entire window** —
the largest transient this engine can produce. Big context → one session occupies most of KV → its own
prefix blocks are evicted between turns → hit rate → 0 % → full re-prefill every turn → maximum spike.
Combined with a stress step it took `MemAvailable` 21.5 → 12.6 GiB in ~22 s. **The guard ended it, not the
kernel: no `oom-kill` line exists at that moment.**

### Tooling failure modes (each one cost real availability)

1. `docker stop` is an **intentional** stop → `restart: unless-stopped` does **not** restart the container.
   A guard's stop therefore looks exactly like an engine crash and leaves the family without an LLM for
   ~14 min. The guard now issues the `docker start` itself (self-heal) after draining the pool.
2. `vllm bench serve` against the `--api-key` engine 401s **every request and still exits 0**, reporting
   `Successful requests: 0`. A run can therefore "pass" every step while applying **zero load**. Both the
   bench and the stress harness now assert on the counters; **any bench number that predates that assert is
   invalid**, and a number taken after the `spark-llm_api` vault item landed must be re-run to count.

### Ruled out, with numbers — do not re-litigate

- **`dcgm-exporter` leak:** `memory.peak` **0.19 GiB** lifetime against a 256 MiB cap, `max/oom/oom_kill`
  events **0**, killed at **3 resident pages**, 51 s *after* the engine; it was already hard-capped.
- **More swap** (`hardware-rejected.md`): the killer fired with **SwapFree 8.25 of 16.77 GiB** — swap was
  half unused.
- **zram** (`hardware-rejected.md`): whole-box `AnonPages` **0.55 GiB** with 8.3 GiB already swapped, and
  refault **file:anon = 42:1**. zram only acts on anon, and spends the very DRAM the GPU carve needs.
- **Concurrency as the cause (#5):** 46.9k tokens combined = 18 % of the window. But #6 shows a single
  large session **is** a first-class memory term — different magnitude, same class as #3.

---

## Incidents #7/#8 — `MemAvailable` is the wrong gauge

Two more global OOMs **after** the capture-size cap had already lowered the resting floor (105,477 →
96,235 MiB). Both forensic bundles are intact under
`/mnt/spark_nvme/oom-watchdog/snapshots/` (`*-KILL`).

### Finding A — on GB10, `MemAvailable` overstates headroom by up to ~9.5 GiB

Both kills recorded a kernel `Node 0 Normal free` that was almost entirely **`free_cma`** — device-reserved
pages the CMA allocator will not hand to an unmovable `GFP_KERNEL` allocation:

| | #7 | #8 |
|---|---|---|
| `MemAvailable` (what the gauge watched) | 10.43 GiB | 10.39 GiB |
| `MemFree` | 10.97 GiB | 10.91 GiB |
| **`CmaFree`** | **8.81 GiB** | **8.78 GiB** |
| **usable = `MemAvailable` − `CmaFree`** | **1.64 GiB** | **1.62 GiB** |
| *(healthy idle, same box)* | *26.25* → **26.13 usable** | *same* |
| last sampler `psi_full_avg10` | 97.8 | 92.5 |

`free -h` says "~10 GiB free" while **~85 % of that figure is CMA** the device will not surrender. Worse, as
the GPU carve is squeezed `CmaFree` *grows*, and CMA counts as available — the metric **inflates as pressure
rises**, which is why an alert on it keeps missing the cliff.

> ⚠ **The obvious alternative gauge is inverted here — do not re-propose it**
> ([`services-rejected.md`](services-rejected.md)). `usable = MemFree − CmaFree` (the proposed WARN 4 /
> CRIT 2) measures 0.74 GiB at healthy
> idle and 2.17 / 2.14 GiB at the two kills: it reads *lower* at rest than at a kill, so any band that fires
> at a kill fires permanently, and an enforcing action on it **restart-storms a healthy engine** — an outage
> caused by the safety net. `MemFree` is meant to sit ≈1 GiB at steady state (the rest is page cache doing
> its job), and under pressure reclaim *evicts* cache, so `MemFree` **rises** — mostly CMA-attributed. It
> measures "reclaimed but not yet consumed": high in a storm, low at rest. The 0.05 GiB figure that motivated it
> came from the kernel's **per-zone** dump (`Node 0 Normal free:9.63 GiB free_cma:9.58 GiB`), which is
> zone/migratetype-local and not reconstructible from global `meminfo`.

PSI is a valid *confirmation* trigger and carries **no lead time**: ten consecutive `psi_full_avg10` samples
read 0.0 at 9.4 GiB usable, then the kill. It cannot be the primary early warning
(`hardware-rejected.md`).

```bash
usable_gib = MemAvailable − CmaFree      # THE budget metric; bands in hardware-spark.md §The budget METRIC
```

### Finding B — the climb is traffic-cumulative and FLAT at idle

| Condition | Engine top-pid | `MemAvailable` |
|---|---|---|
| cold boot, no traffic at all | 88,773 MiB | 24.2 GiB — **flat overnight** |
| same boot, + one light session ~30 min | 88,773 → **109,785 MiB** | 24.5 → **9.6 GiB** |
| post-cap cold boot, light load | 85,445 MiB load → 86,243 | 26.9 GiB |

There is **no idle ratchet**: what looks like a leak is the residue of prior traffic. The engine grows **per
request shape and never returns it** — an allocator/graph-growth mechanism, not a KV-pressure mechanism — so
a restart is the only reset, and only removing the mechanism bounds the peak (allocation config, prefill
chunk size, eager mode). It also makes an agent session a first-class memory term *beyond* its KV occupancy:
**a light session is enough**.

### The top-pid freeze is the signature to watch

At both kills `gpu_top_mib` was **constant for minutes** (109,681 and 109,785) while `psi_full` saturated. A
flat top-pid + saturating PSI means the allocator can no longer get pages: it is the predictable pre-kill
state an enforcing governor must act on, not merely record.

### Why #8 kills the engine and #7 does not

#7's victims are collateral (traefik, dashboard, dozzle, fwupd…) — the killer goes after unprivileged
user-slices first, and the box wedges anyway. #8 kills **engine PID-1 despite `oom_score_adj=-500`**: with
`all_unreclaimable? yes` there is nothing else left. Kill order is not engine-first (invariant 3), and the
cage cannot protect the host.

---

## Incident #9 — nothing crashed: a REST state inside the CRIT band

**The symptom is "spark crashed" and nothing crashed.** `RestartCount=0`, `OOMKilled=false`, `ExitCode=0`,
and 72 h of kernel log with no `oom-killer` line at all. What happened: `spark-oom-watchdog`'s enforcing
governor read CRIT, deferred for in-flight traffic, and restarted the engine **on purpose**. Read
`state/enforce.log` before believing any crash story: the rule in `hardware-spark.md` §*Cold start is SLOW*
worked as intended, and this is a **sizing** failure wearing a **fault** mask.

```
CRIT snapshot   usable 3.43 GiB    ← MemAvailable 8.20, CmaFree 4.77, psi_full 12.3
CRIT ×4         usable 7.55-7.99   psi_full 0.0   (in-flight deferrals)
CRIT-ENFORCED   usable 7.94        → docker restart vllm-qwen-spark   (~20 min cold start)
next sample     usable jumps to 117.03 GiB   ← the jump IS the measurement: the engine held 109.09 GiB
then            usable pinned 7.76-7.99 GiB, psi_full 0.0, "suppressed by enforce cooldown" every 5 min
cooldown ends   the next restart is already scheduled
```

Two findings, both durable:

1. **The engine's real non-KV footprint is 92.13e9 B, not the declared 76.3e9 B.** The pool passed its own
   gate on paper while the box had no host floor: declared `fixed + pool` fit the ceiling, the measured hold
   was **12.13 GiB over the certified ceiling** — which is exactly what "usable 7.9 GiB" is. Ledger +
   derivation: `hardware-spark.md` §*The fixed cost, MEASURED*.
2. **A CRIT reading can be a REST state, not an excursion.** The value did not *fall* to 7.9 GiB, it *lived*
   there with zero PSI stall, so the enforcer held a standing order to restart once per cooldown. A restart
   cannot fix a rest value — the cold load re-derives the same number. Hence **hysteresis** (fire once,
   re-arm above the WARN band) rather than a lower threshold:
   [`services-rejected.md`](services-rejected.md) and invariant 7 below.

The excursion that invites "just lower CRIT": usable fell to **3.43 GiB** while `MemAvailable` sat at a
*normal* 8.20 GiB — the dip is `CmaFree` rising 0.15 → 4.77 GiB (the device taking CMA pages under traffic)
with `psi_full` at 12.3 %. It needed no action because the in-flight wait deferred and traffic moved on, not
because 3.4 GiB is comfortable: 1.8 GiB below it is the measured kill point (§#7/#8).

**The live state of the guard.** `/usr/local/bin/spark-oom-watchdog.sh` matches the tree hash, the unit
environment carries `SPARK_OOM_REARM_GIB=12`, the by-hand arm-off file
`/mnt/spark_nvme/oom-watchdog/no-enforce` is absent, and `sudo /usr/local/bin/spark-oom-watchdog.sh status`
reads `hysteresis: armed (no latch)`. A live claim in this repo is checked against **the artifact on the
box**, never against a commit message (`CONVENTIONS.md` §6) — a converged pool value does not imply the
watchdog script or the unit env converged with it.

### The transient burst is not the REST state

On the corrected regime the sustained CRIT band does **not** recur at rest; sessions hold ≥19.5 GiB usable.
What remains is a single sub-15 s burst: usable 20.02 → 5.92 GiB (vLLM loggers: 1 running request, 800–1500
tok/s prefill — a live session, not rest), one in-flight-drain deferral, then an enforced restart, with the
engine healthy again after the cold load and steady near 43 GiB after. That transient burst (prefill
activations against the pool) is still **un-conserved** by the `device_hold` re-derive — the open host-floor
work in `hardware-spark.md` §The GLOBAL ceiling — and it is **not** a leak (anon returns in <15 s) and **not**
the REST condition above. The governor behaved as designed in both cases.

---

## Cross-incident invariants

1. **`OOMKilled: false` / `ExitCode: 0` every time** — Docker never sees it (global OOM, not cgroup).
2. **The engine's `RSS` is tiny at kill time** (`anon-rss:112kB` on a 151 GB total-vm process; `76kB` in #3)
   — it had been **swapped out**: the box is *thrashing*, not merely full. A swap-flush stall (minutes, long
   enough that buffered log lines reach the json-file driver well after the events they carry) precedes the
   kill and looks like an engine hang.
3. **Kill order is not engine-first.** User-slice/systemd processes die before the engine, so the observed
   symptom is often "session/SSH died", not "model crashed".
4. **It recurs whenever load returns.** Moving the OOM later is not removing it; only an explicit, measured
   budget removes it.
5. **`MemAvailable` alone is not the budget metric on GB10** (#7/#8) — up to ~9 GiB of it can be `CmaFree`,
   which the device will not surrender to an unmovable kernel allocation. Budget in
   **`MemAvailable − CmaFree`**, with PSI memory as confirmation only (it carries *no* lead time). **Not**
   `MemFree − CmaFree` — that is inverted here (0.74 GiB idle vs 2.17 GiB at a kill).
6. **The engine's non-KV footprint grows with traffic and never returns** (#7/#8) — flat at idle, so a
   restart is the only reset, and only removing the allocation mechanism bounds the peak.
7. **A CRIT reading is not always an emergency** (#9) — it can be the box's REST state, and then a restart
   only rebuilds the same number after a ~20 min cold load. Tell them apart by trend and corroboration: a
   value *pinned* below CRIT for tens of minutes at `psi_full` ≈ 0 is a budget that was never sized; a value
   *falling* through CRIT with PSI climbing is the event the enforcer exists for. One planned restart, then
   a human — an enforcer that cannot tell the two becomes a restart loop that reads as a flaky engine
   (`SPARK_OOM_REARM_GIB`).

---

## Diagnosis recipe (read-only, safe, run this first)

```bash
# 1. What the container says (NOT authoritative for OOM)
docker inspect <ctr> --format 'RestartCount={{.RestartCount}} OOMKilled={{.State.OOMKilled}} StartedAt={{.State.StartedAt}}'

# 2. What the kernel says (AUTHORITATIVE — is it a global OOM?)
sudo dmesg -T | grep -E 'invoked oom-killer|oom-kill:|Out of memory: Killed process' | tail -30
#    key selector: constraint=CONSTRAINT_NONE ... global_oom → host-wide kill (cgroup limit NOT hit)
#    task_memcg=/system.slice/docker-<id>.scope + task=<name> → which container the victim belonged to

# 3. Engine restart history (counts boot banners, not redeploys)
docker logs --timestamps <ctr> | grep 'version 0.1.dev'

# 4. The budget numbers (feeds the sizing table in hardware-spark.md §Unified-memory budget)
docker logs <ctr> | grep -E 'Model loading took|Available KV cache memory|GPU KV cache size|Free memory on device'

# 5. How hot is the box — the CORRECTED gauge (#7/#8), not `free -h`
awk '/^MemAvailable|^MemFree|^CmaFree|^AnonPages|^SwapFree/{print}' /proc/meminfo
awk 'BEGIN{while((getline l<"/proc/meminfo")>0){split(l,a," ");if(a[1]=="MemAvailable:")v=a[2];if(a[1]=="CmaFree:")c=a[2]}printf "usable_gib=%.2f\n",(v-c)/1048576}'
#    bands (WARN / CRIT / re-arm) live in hardware-spark.md §The budget METRIC and in the unit's Environment=
```

**`dmesg` is authoritative; `docker inspect` is not.** A `RestartCount` increment with `OOMKilled=false` on
this box means a global OOM until proven otherwise — and the third possibility, an intentional watchdog
restart, is proven or refuted by `state/enforce.log`.

### The watchdog's bundles — read these BEFORE digging by hand

`spark-oom-watchdog.service` (roles/spark, OOM-immune `OOMScoreAdjust=-1000`) samples every 15 s and freezes
a forensic bundle on a kernel OOM, an engine restart, or a threshold breach:

```bash
systemctl status spark-oom-watchdog
sudo /usr/local/bin/spark-oom-watchdog.sh status      # prints the hysteresis state; use the unit env for config
ls -t /mnt/spark_nvme/oom-watchdog/snapshots/ | head  # KILL | CRIT | WARN | RESTART | MANUAL
tail -50 /mnt/spark_nvme/oom-watchdog/state/samples.csv   # the PRE-event curve (the payload)
# columns: epoch,mem_avail_gib,mem_free,cached,anon,swap_used,psi_some,psi_full,gpu_top_pid_mib,restarts,utc
```

**The footprint trick (#6):** `nvidia-smi --query-compute-apps` reports only the **largest pid** and
under-counts the engine's multi-process pool by ~10 GiB. The true footprint is the **`MemAvailable` jump on
stopping the engine** — avail went **12.6 → 118.6 GiB** across one stop, i.e. the engine held **~106 GiB** of
the 121.62 GiB pool while its top pid reported 96,235 MiB.

> **Append-only.** A new incident gets a row in the index and a numbered section carrying the symptom, the
> mechanism and the guard it produced — never a timeline, a run name or a task id. The *knowledge* (why the
> numbers work, what the governor should be) updates in `hardware-spark.md`, not here; a decision **not** to
> do something becomes a row in the owning domain's `*-rejected.md` log.
