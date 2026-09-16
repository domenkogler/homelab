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
| 3 | 2026-09-16 09:26 | **agent session running against spark's own endpoint** | `global_oom` 09:22→09:26: user-slice `pipewire`/`pipewire-pulse`/`dbus-daemon`/`systemd`/`(sd-pam)` first, then **`python3` pid=1023317 (container PID-1)** @ 09:26:17 | `RestartCount=3`, `StartedAt=09:26:20Z`; the client session got **502** and died | **this change (2026-09-16)** — explicit `--kv-cache-memory-bytes 8800000000`, util removed (see `hardware-spark.md` §Chosen governor) |

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

> **Append-only.** New incidents get a row in the table + a numbered narrative section. The *knowledge*
> (why the numbers work, what the governor should be) updates in `hardware-spark.md`, not here.