# spark stability test — is the memory peak actually bounded?

A load test you run over `ssh spark`, with live progress and a final PASS/FAIL verdict.

**What it certifies:** that the two peak-bound terms — `expandable_segments:True` (C1) and
`--max-num-batched-tokens 4096` (C2) — keep the **host** alive under the traffic shape that produced
global OOMs #1–#8. **What it does NOT certify:** throughput (that is `spark/BENCHMARK-PLAN.md`), KV
capacity, or long-context accuracy (the 262k needle test is still open, HD-376).

Knowledge: [`docs/hardware-spark.md`](../docs/hardware-spark.md) §Unified-memory budget ·
forensics: [`docs/spark-incidents.md`](../docs/spark-incidents.md) #7/#8 · harness:
[`bench/stress-oom.sh`](bench/stress-oom.sh).

---

## The two things you must not get wrong

**1. The gauge is `usable = MemAvailable − CmaFree`, not `free -h`.** On GB10 the GPU carve is CMA, and
CMA counts as "available" — so raw `MemAvailable` **inflates as pressure rises** (by up to ~9.5 GiB here).

| state | usable |
|---|---|
| healthy idle (measured) | **30.4 GiB** |
| boot floor, no traffic | 26.1 GiB |
| watchdog WARN / CRIT | < 12 / < 8 GiB |
| **both observed kills** | **1.62 / 1.64 GiB** |

**2. Filling the KV cache is not a memory test.** The KV pool is carved at boot (`--kv-cache-memory-bytes
8800000000` = 8.2 GiB / 283,398 tokens) and **never grows**, so `GPU KV cache usage: 90 %` is scheduler
occupancy, not RAM. Filling it exercises preemption/recompute — a *graceful* path. Preemptions going up
during this test is **normal**; a kernel OOM line is the failure.

The killer here was never KV: it was per-request allocator/graph growth that is never returned
(incident #7/#8: engine top-pid 88,773 → 109,785 MiB in ~30 min of *one light* session, FLAT at idle).
Post-C1/C2 the same curve measured **86,243 → 86,725 MiB in 3.5 h of three live sessions**.

---

## §0 Preflight — records the baseline (do not skip)

Everything else is judged against what this writes to `/tmp/stability-baseline.env`.

```bash
ssh spark 'bash -s' <<'REMOTE'
set -u
usable(){ awk '/^MemAvailable:/{a=$2}/^CmaFree:/{c=$2}END{printf "%.2f",(a-c)/1048576}' /proc/meminfo; }
top_mib(){ nvidia-smi --query-compute-apps=used_memory --format=csv,noheader,nounits | sort -rn | head -1; }
CTR=vllm-qwen-spark
INFLIGHT=$(curl -s localhost:8000/metrics | awk '/^vllm:num_requests_running/{s+=$2}END{print s+0}')
{
  echo "BASE_EPOCH=$(date +%s)"
  echo "BASE_USABLE=$(usable)"
  echo "BASE_TOP=$(top_mib)"
  echo "BASE_RESTARTS=$(docker inspect $CTR --format '{{.RestartCount}}')"
  echo "BASE_OOM=$(sudo journalctl -k -b 0 --no-pager | grep -c 'invoked oom-killer')"
  echo "BASE_NVRM=$(sudo dmesg | grep -c NV_ERR_NO_MEMORY)"
} | tee /tmp/stability-baseline.env
echo "--- engine: $(curl -s -o /dev/null -w '%{http_code}' localhost:8000/health) | in-flight requests: ${INFLIGHT:-?} ---"
sudo /usr/local/bin/spark-oom-watchdog.sh status | sed -n '1,8p'
REMOTE
```

**GO only if:** `/health` = 200 · `BASE_USABLE ≥ 26` · in-flight **0** · the watchdog prints
`budget: usable=…` (the corrected gauge).

> **Close every agent session that runs on spark first — including the assistant session you are typing
> in.** An agent session is a first-class memory term here (incident #6: one 162k-token session = 56 % of
> the KV pool; incident #3: a diagnosis session OOMed the box it was running on). Verify with the
> in-flight line above.
>
> `sudo` is required for `journalctl -k` and `dmesg` — **without it you silently read zero kernel OOM
> lines** and conclude the box is clean. That mistake happened while writing this page.

---

## §1 Terminal A — live progress (leave it running)

One line every 10 s: the real gauge, the engine's footprint, the kernel's verdict, and the harness's
current step. `Ctrl-C` to stop. If this line keeps moving, the test is still running.

```bash
ssh spark 'bash -s' <<'REMOTE'
while true; do
  U=$(awk '/^MemAvailable:/{a=$2}/^CmaFree:/{c=$2}END{printf "%.2f",(a-c)/1048576}' /proc/meminfo)
  T=$(nvidia-smi --query-compute-apps=used_memory --format=csv,noheader,nounits | sort -rn | head -1)
  R=$(docker inspect vllm-qwen-spark --format '{{.RestartCount}}')
  K=$(sudo journalctl -k -b 0 --no-pager 2>/dev/null | grep -c 'invoked oom-killer')
  P=$(awk '$1=="full"{for(i=2;i<=NF;i++) if($i~/^avg10=/){split($i,x,"=");printf "%s",x[2];exit}}' /proc/pressure/memory)
  L=$(ls -t /tmp/stress/*.log 2>/dev/null | head -1)
  S=$([ -n "$L" ] && tail -1 "$L" | cut -c1-90 || echo "(no run yet)")
  printf '%s  usable=%-6s top=%-6s restarts=%-2s oom-kill=%-2s psi_full=%-4s :: %s\n' \
    "$(date +%T)" "${U}G" "${T}M" "$R" "$K" "${P}%" "$S"
  sleep 10
done
REMOTE
```

`oom-kill` must **not move** during the test. `usable` should stay above ~20 GiB.

---

## §2 Terminal B — run the ladder

Copy the harness to the box once, then run detached (`nohup`) so a dropped SSH does not abort the run.
Each run writes `/tmp/stress/<name>.log` and drops a `<name>.done` marker carrying its exit code.

```bash
ssh spark 'cat > /tmp/stress-oom.sh' < spark/bench/stress-oom.sh
ssh spark 'mkdir -p /tmp/stress'
```

### Run 1 — the full ladder (≈ 60–90 min)

Phase A churns batch shapes (lazy cudagraph/inductor capture — the #4/#5 kill mechanism), then Phase B
escalates concurrent *fresh* large prefills (the activation transient that C2 governs): rung 1 = 2
sessions, 2 = 3, 3 = 4 (`max_num_seqs`), each at 48k input tokens.

```bash
ssh spark 'SPARK_STRESS_MAX_RUNG=3 MEM_FLOOR_GB=18 STRESS_OUT=/tmp/stress \
  nohup bash -c "bash /tmp/stress-oom.sh; echo rc=\$? > /tmp/stress/rung123.done" \
      > /tmp/stress/rung123.log 2>&1 & echo "started: $!"'
```

### Run 2 — the decisive one: two simultaneous full windows (≈ 30–45 min)

Wait for `rung123.done` to exist (§3 tells you how). This is the **compaction-vs-compaction** shape: two
concurrent fresh prefills against the pool. **2026-09-18: the pool target is 16 GiB (553.7k token pool,
2.11 windows vs today's 1.08) and the full-window rung is sized at 240k** (`BENCH_IN=240000`): a
262,144-token chat request carries ~20.5k template tokens → ~282.7k > `max_model_len: 262144` → vLLM
rejects it 400 before any load (live rung B1 x2 on 2026-09-17: `ok=0/2 in_tok=0 Bad Request`). 240k →
~260.5k actual, undershoot; **2×240k ≈ 94.6 % of a 16 GiB pool** — the strictest worst case the
configured engine can actually serve, and the shape a real auto-compaction in *two* sessions would make.

```bash
ssh spark 'SPARK_STRESS_MAX_RUNG=1 BENCH_IN=240000 MEM_FLOOR_GB=16 RUNG_PAUSE=120 STRESS_OUT=/tmp/stress \
  nohup bash -c "bash /tmp/stress-oom.sh; echo rc=\$? > /tmp/stress/fullwindow.done" \
      > /tmp/stress/fullwindow.log 2>&1 & echo "started: $!"'
```

(When the pool is back at 8.2 GiB / 283.4k tokens, keep this rung at `BENCH_IN=200000` = 400k tok vs the
283.4k pool — the compaction-vs-compaction shape. At 16 GiB, 240k is the analogous 2×~95 % worst case.)

**Notes**

* `MEM_FLOOR_GB=16` is deliberately above the script's default 14: at the 16 GiB KV pool the idle usable
  drops to ~21–24 GiB (was ~30), so 16 leaves some margin; the script's floor is on raw `MemAvailable`
  (the falsified gauge).
* The harness's live guard **stops and then restarts the engine** if `MemAvailable` crosses the floor or
  PSI-full crosses 50 %, so the kernel never picks the victim. `RestartCount` +1 with a `GUARD FIRE`
  line = the guard did its job; that is a governor PASS and an *inconclusive* peak result.
* Never pass `--warm` or reuse a prompt: prefix-cache hit is ~92 %, so a repeated prompt prefills nothing
  and you measure zero (the fresh `--seed` per step is what prevents that).
* `MEM_FLOOR_GB`/`SPARK_STRESS_MAX_RUNG`/`BENCH_IN` are per-run env vars — set them on the run line, not
  in the copy.
* The OOM watchdog is **enforcing** (CRIT < 8 GiB usable → planned `docker restart`, max 2 per 2 h; plus
  an idle recycle at baseline + 8 GiB). To read raw numbers without it interfering:
  `ssh spark 'sudo touch /mnt/spark_nvme/oom-watchdog/no-enforce'` — and **remove it afterwards**
  (`sudo rm -f` the same path). Re-arm state: `ssh spark 'sudo tail /mnt/spark_nvme/oom-watchdog/state/enforce.log'`.

---

## §3 The verdict

Run this at any time. It reports progress, and once the run has finished it prints the verdict.

```bash
ssh spark 'bash -s' <<'REMOTE'
set -u
[ -f /tmp/stability-baseline.env ] || { echo "NO BASELINE — run §0 first"; exit 2; }
. /tmp/stability-baseline.env
CSV=/mnt/spark_nvme/oom-watchdog/state/samples.csv
RUN=$(ls -t /tmp/stress/*.done 2>/dev/null | head -1)
LOG=$(ls -t /tmp/stress/*.log 2>/dev/null | head -1)

# ---- still running? -------------------------------------------------------
if pgrep -f "stress-oom.sh" >/dev/null 2>&1; then
  echo "STATUS: RUNNING — last step: $(tail -1 "$LOG" 2>/dev/null | cut -c1-90)"
  echo "        steps done: $(grep -c 'STEP .*:' "$LOG" 2>/dev/null) | see §1 for the live gauge"
  exit 0
fi
[ -n "$RUN" ] || { echo "STATUS: no run found in /tmp/stress — start one (§2)"; exit 2; }
echo "STATUS: finished ($(basename "$RUN" .done) $(cat "$RUN"))"

# ---- judge ---------------------------------------------------------------
NOW_OOM=$(sudo journalctl -k -b 0 --no-pager | grep -c 'invoked oom-killer')
NOW_RST=$(docker inspect vllm-qwen-spark --format '{{.RestartCount}}')
NOW_H=$(curl -s -o /dev/null -w '%{http_code}' localhost:8000/health)
# the $1 ~ /^[0-9]+$/ guard matters: the sampler file carries its header line in the middle
# (after a ring rotation), and a string "epoch" > "1789..." is TRUE — without the guard the
# header row's non-numeric usable field reads as 0 and every run "fails at 0 GiB".
read MIN_U MAX_T <<<"$(awk -F, -v b="$BASE_EPOCH" '$1 ~ /^[0-9]+$/ && $1+0>b+0 && NF>11 {if(!s||$12+0<m)m=$12+0; if($10+0>t)t=$10+0; s=1} END{if(s) printf "%.2f %d", m, t; else printf "NONE 0"}' "$CSV")"
STEPS=$(grep -h 'STEP .*: rc=' "$LOG" 2>/dev/null | wc -l)
BAD=$(grep -h 'STEP .*: rc=' "$LOG" 2>/dev/null | grep -cv 'ok=[0-9]*/' || true)
GUARD=$(grep -l 'GUARD FIRE' /tmp/stress/*.log 2>/dev/null | head -1)
FAIL=""
[ "${NOW_OOM:-0}" -gt "${BASE_OOM:-0}" ]        && FAIL="$FAIL
  - kernel global OOM x$((NOW_OOM-BASE_OOM)): THE box died, that is the whole failure mode"
[ "${NOW_RST:-0}" -gt "${BASE_RESTARTS:-0}" ]   && FAIL="$FAIL
  - engine restarts +$((NOW_RST-BASE_RESTARTS))$([ -n "$GUARD" ] && echo ' (guard-fired: governor PASS, peak test inconclusive)')"
awk -v x="${MIN_U:-99}" -v f=8 'BEGIN{exit !(x<f)}' && FAIL="$FAIL
  - usable bottomed at ${MIN_U} GiB (< 8 GiB = the watchdog CRIT line, 1.6 GiB = the kills)"
awk -v x="$(echo "$MAX_T-$BASE_TOP" | bc)" -v l=2048 'BEGIN{exit !(x>l)}' \
  && FAIL="$FAIL
  - engine grew ${MAX_T} MiB vs ${BASE_TOP} MiB baseline (> 2 GiB = the cumulative-growth mechanism is back)"
[ "${NOW_H:-0}" != "200" ]                      && FAIL="$FAIL
  - engine /health = ${NOW_H} after the run"

echo "----- evidence -----"
echo "usable      baseline ${BASE_USABLE} GiB  ->  min during run ${MIN_U} GiB   (kill line 1.6)"
echo "engine top  baseline ${BASE_TOP} MiB  ->  max during run ${MAX_T} MiB"
echo "kernel oom-kill  ${BASE_OOM} -> ${NOW_OOM}   restarts ${BASE_RESTARTS} -> ${NOW_RST}   health ${NOW_H}"
echo "steps applied real load: ${STEPS} (a zero-load step aborts the run by design)"
echo "watchdog snapshots: ls -t /mnt/spark_nvme/oom-watchdog/snapshots/ | head"
echo "----------------------------------------------------------------"
if [ -n "$FAIL" ]; then
  echo "RESULT: FAILED ❌$FAIL"
  echo "Next lever: docs/hardware-spark.md §Unified-memory budget → then C3 --enforce-eager."
  echo "Do NOT reach for more KV cache: usable pays for it 1:1 and the killer was never KV."
else
  echo "RESULT: PASSED ✅ — the peak stayed bounded; C1+C2 hold under this load."
  echo "Next: record the numbers in docs/spark-incidents.md (append-only) and go do (c): spark-lane profile."
fi
REMOTE
```

### Pass criteria

| check | pass | why |
|---|---|---|
| kernel `invoked oom-killer` delta | **0** | a global OOM = the host wedge; nothing else matters |
| engine `RestartCount` delta | **0** | engine died; the watchdog bundle has the cause |
| min `usable` during run | **≥ 8 GiB** | 8 = the CRIT line; 1.6 = where both kills actually landed |
| max `gpu_top_mib` − baseline | **≤ 2 GiB** | bigger = allocator growth is back → that is the C3 trigger |
| every step `ok=N/N`, `in_tok` ≥ ½ requested | all | a zero-load step cannot certify anything |
| `/health` after the run | 200 | it answered at the end, not just survived |

Preemptions **may** rise (in-flight queueing is graceful). `nvidia-smi` memory is "Not Supported" on
GB10; the per-pid figure under-counts the engine by ~10 GiB, which is why the verdict uses the sampler's
`usable_gib`, not `nvidia-smi`.

---

## §4 If it FAILED — read it this way

| signature | meaning | next lever |
|---|---|---|
| kernel OOM with `usable` collapsing while KV occupancy was low (< 60 %) | allocator/graph growth per request still unbounded | **C3 `--enforce-eager`** (`spark_vllm_enforce_eager: true`) — re-measure the boot floor after each step, one change at a time |
| guard fired (`GUARD FIRE` in the log) | the governor acted before the kernel | **PASS of the governor**; re-run with `no-enforce` for raw numbers if you need them |
| `usable` fine, but steps time out / preemptions spike | KV capacity, not memory | KV is the constraint, and it is a *capacity* conversation: `--kv-cache-dtype fp8` (≈2× tokens for the same 8.2 GiB, unvalidated on this hybrid+MTP build) or the client-side `spark-lane` 64k profile (HD-376). **Not** a KV raise paid for out of `usable` |
| `ok=0/N` on the first step | the harness is measuring nothing (401 / key drift) | fix auth before believing any number |

**C3 decision rule (so it stays honest):** apply `--enforce-eager` only if the engine's top-pid grows
> 2 GiB/hour under traffic *and* does not return toward the baseline at idle. Measured post-C1/C2:
**+482 MiB over 3.5 h** — so today C3 is **not** warranted, and it costs decode throughput on every turn.

---

## §2b — Unattended: run it tonight, read it in the morning

Two scripts, split deliberately:

| script | runs on | job |
|---|---|---|
| [`bench/stability-overnight.sh`](bench/stability-overnight.sh) | **spark** | the chain (ladder → compaction shape → full-window shape), keeps state on **XFS** so it survives a wedge *and* a power-cycle, and **resumes at the first unfinished run** |
| [`bench/stability-supervise.sh`](bench/stability-supervise.sh) | **this laptop (WSL)** | syncs both scripts, launches the chain detached, then **relaunches it after a crash** and pulls the evidence off the box |

Why the split: the failure we are hunting is a *global* kernel OOM, and its historical kill list
includes `sshd` (#2/#3). A chain living on spark therefore dies together with the evidence it exists
to collect — and after a reboot `journalctl -k -b 0` is the **new** boot, so those OOM lines are gone.
With the supervisor here, the chain gets relaunched, and every kill snapshots kernel + watchdog +
engine state to XFS *and* to this laptop.

**Continue-on-crash policy (owner call):** a kill is recorded and the chain **carries on**, so you get
the whole picture — which shape broke, and whether the later shapes still survive. It is still a
**FAILED** verdict. Two brakes keep this from turning an engine restart into a morning power-cycle of a
box that is now in the rack: after a kill the chain **cools down and waits until `usable` has actually
recovered** before applying load again, and it stops at the **2nd kill** (the #4/#5/#7/#8 pattern is a
cascade, and cascades are what ended in wedges).

```bash
# 1. before bed — this laptop, from the repo root. Ctrl-C stops supervising, NOT the chain.
bash spark/bench/stability-supervise.sh

# 2. any time afterwards, from any terminal — read-only, safe, no side effects:
bash spark/bench/stability-supervise.sh --status
#   (or straight at the box:  ssh spark 'bash /mnt/spark_nvme/stability/stability-overnight.sh --status')
```

Progress while it runs: the supervisor prints one line per poll —
`RUNNING | usable=24.7G top=88100M done=[rung123] | RUN compact START …`. The verdict lands in
`spark:/mnt/spark_nvme/stability/OVERNIGHT.done`, is printed by the supervisor, and is copied to
`spark/bench/overnight/` on the laptop (git-ignored).

Keep the laptop awake or nobody relaunches the chain:
```powershell
powershell.exe -Command 'Start-Process powercfg -ArgumentList "/change","standby-timeout-ac","0" -WindowStyle Hidden'
```

Preconditions the chain refuses to start without (it tells you, instead of producing a fake number):
engine `/health` 200 · **zero in-flight requests** · `usable ≥ 26 GiB` · the bench harness present.
**Close every agent session running on spark — including the assistant you are typing in.**

Useful knobs (env on the supervisor): `STABILITY_RESERVE_GIB` (12) · `STABILITY_MAX_KILLS` (2) ·
`STABILITY_COOLDOWN` (300 s) · `STABILITY_POLL` (60 s). To verify the plumbing without touching the
box: `STABILITY_DRYRUN=1 STABILITY_FAKE_KILL=1 STABILITY_POLL=8 bash spark/bench/stability-supervise.sh`
— it drives the crash/relaunch/resume path with zero load. To start over:
`ssh spark 'rm -f /mnt/spark_nvme/stability/{OVERNIGHT.done,state.env}'`.

---

## §6 — "How much more KV can I afford, without fp8?"

The verdict **prints this number** — here is where it comes from, so you can argue with it.

`usable` and the KV pool are paid out of the **same** 121.62 GiB, so the exchange rate is exact:

```
extra_KV_GiB   = worst_usable_observed − reserve_target          # reserve_target = 12 GiB (WARN line)
extra_tokens   = extra_KV_GiB × 1073741824 / (30.3 KiB × 1024)   # measured 30.3 KiB/token
extra_windows = extra_tokens / 262144
```

…because the KV pool is the only engine term that is a *choice*: weights (73.55 GiB), the PLE CPU
mirror and the CUDA graphs do not change when you raise `spark_vllm_kv_cache_memory`.

There are **two** ceilings and the verdict takes the lower one:

* **runtime** — the worst `usable` moment observed during the whole run, minus the reserve you want to
  keep. That is what §3 measures; you cannot know it without the load test.
* **boot** — the pool is carved **at boot**, out of whatever was free *then* (`Initial free memory` in
  the boot log, 114.6 GiB on the current boot). `boot_allowance = free_at_boot − engine_hold − reserve`.
  On a full pool the box already logs a burst of `NV_ERR_NO_MEMORY` during weight load, so boot is
  where a too-bold pool fails — and it fails **before** you get a single request answered.

Measured on a **dry run** (no load ⇒ worst moment = idle), which is therefore an *upper bound*:

```
  runtime: usable 29.95 - 12  = +17.5 GiB
  boot   : 114.6 - 91.7 - 12  = +10.9 GiB   <-- BINDING
  => pool 8.2 -> ~16-19 GiB = ~550-640k tokens = ~2.1-2.4 concurrent 262k windows (today 1.08)
```

**2026-09-18 target: pool 16 GiB** (candidate, NOT YET CONVERGED — awaiting this ladder to pass).
16 GiB / 30.3 KiB-per-tok ≈ 553.7k tokens = 2.11 windows — inside both ceilings (runtime +7.8 < 16.5;
boot +7.8 < +10.9), at ~94.6 % of the pool when two full-context sessions are fresh. **Consequences**
of the raise that must be re-verified live, not assumed:

* **Idle `usable` drops** from ~30.5 to ~22.7 GiB — the WARN 12 / CRIT 8 lines still clear, but the
  steady-state margin to WARN shrinks ~8 GiB. The rung floor must come down to `MEM_FLOOR_GB=16` (Run 2
  above) and the host-mem alert thresholds (`IaC/ansible/roles/monitoring/vars/main.yml`) should be
  re-checked against the new idle so a routine transient cannot false-fire.
* **Boot is still the binding gate.** The pool is carved at boot; after any 8.2→16 converge, verify
  `Initial free memory` in the boot log still leaves the host reserve and the `NV_ERR_NO_MEMORY` count
  does not grow at weight-load (it already bursts ~218 at boot today).
* **vLLM will schedule / preempt under 94 % fill.** Two fresh 240k at 16 GiB is the pessimal case —
  expect higher TTFT / some evictions; that is the point (proves the host survives), not a bug.

The real run will report a smaller runtime figure — that is the point of running it. Take
**min(runtime, boot)** and round **down** to a 2 GiB step, then verify after the change:

```bash
ssh spark 'sudo docker logs vllm-qwen-spark 2>&1 | grep -E "Initial free memory|GPU KV cache size|Maximum concurrency"'
ssh spark 'grep -E "MemAvailable|CmaFree" /proc/meminfo'   # usable = the difference
```

Three honest caveats: (a) this is a *memory* answer — whether more KV actually helps you is a
prefix-cache-hit question, measure it before and after; (b) `max_num_seqs: 4` caps concurrency anyway,
so beyond ~4 windows the extra pool buys headroom, not parallelism; (c) fp8 would roughly **double**
the tokens for the *same* GiB and is the only lever that does not spend `usable` at all — excluded here
by your request, still the biggest single win on the table.

---

## §5 Recovery, if you need it

```bash
ssh spark 'sudo docker start vllm-qwen-spark'        # if the engine is down (weight reload ~180 s)
ssh spark 'curl -s -o /dev/null -w "%{http_code}\n" localhost:8000/health'   # 200 when back
ssh spark 'sudo /usr/local/bin/spark-oom-watchdog.sh status'
ssh spark 'ls -t /mnt/spark_nvme/oom-watchdog/snapshots/ | head -3'
```

`docker stop` is an *intentional* stop — `restart: unless-stopped` will **not** bring the engine back by
itself (that cost 14 min of downtime once). The bench guard and the watchdog both re-start it explicitly;
a manual `docker stop` from you does not.
