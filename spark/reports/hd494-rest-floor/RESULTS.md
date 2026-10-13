# HD-494 — the rest floor re-derived from the RECORDED history (no new probe)

Taken 2026-10-13 ~11:31–11:40 UTC from the worktree. Method constraint honored: the numbers below
come from persisted records (watchdog ring `samples.csv`, `enforce.log`, state files, `journalctl`,
`docker inspect`, and the engine's own cumulative `/metrics` counters read once). **No live sample of
`usable`/`CmaFree` was taken and no load probe was run** — this session is served by spark, so any
fresh memory reading it produces would be contaminated by its own inference traffic. The single
genuinely-live read (the `/metrics` counter dump) is labeled below; counters are cumulative state the
engine already carries, not a memory gauge.

Shape under measurement: `fast`, 20 GB pool, `max_num_seqs 8` — live since the engine boot at
**2026-10-06T11:49:52Z** (the pool was 25→20 GB two days earlier, so the 20 GB shape itself runs
since 2026-10-06; before that 25 GB, whose rest record is Incident #9, not this row).

## 1. Engine uptime and restarts

Command (read-only state, not a memory sample):

```
ssh spark 'docker inspect -f "{{.Name}} restarts={{.RestartCount}} started={{.State.StartedAt}} oomkilled={{.State.State.OOMKilled}} exit={{.State.ExitCode}} status={{.State.Status}}" $(docker ps -aq --filter name=vllm)'
ssh spark 'sudo journalctl -u spark-oom-watchdog --since "2026-10-03" --no-pager -o short-iso'
```

Output (2026-10-13T11:31:39Z): `/vllm-qwen-spark restarts=0 started=2026-10-06T11:49:52.286258184Z
oomkilled=false exit=0 status=running` — engine uptime **6 d 23 h 41 m (6.99 d), RestartCount 0,
no OOM-kill**. Host uptime 3 weeks 4 days (`uptime -p`).

Journal RESTART-tagged field-changes over the window (watchdog-recorded, the only engine restarts):
2026-10-06 01:03:36Z, 07:46:38Z, 08:17:31Z, 09:03:18Z, 09:41:33Z (the CRIT-ENFORCED one, pre-regime),
then a crash-loop with docker `restart=` climbing 1→20 between 10:53:13Z and 11:13:52Z (the B9
FAIL(BOOT) experiment), one boot at 11:19:07Z, and the live boot at **11:49:52Z**.
**Zero RESTART/CRIT/WARN/RECYCLE/KILL events after 2026-10-07T05:21:02Z** — 6.25 clean days.

State-file stamps (`cat /mnt/spark_nvme/oom-watchdog/state/last_*`), epoch anchor 1791891132 =
2026-10-13T11:32:12Z from the samples ring:

| stamp | epoch | UTC | note |
|---|---|---|---|
| `last_WARN` | 1791350463 | 2026-10-07T05:21:03Z | the regime's last WARN (`usable=11.93GiB psi_full=0.7`) |
| `last_RESTART` | 1791287395 | 2026-10-06T11:49:55Z | the live boot itself |
| `hysteresis_latch` | 1791279693 | 2026-10-06T09:41:33Z | the pre-regime CRIT-ENFORCED restart (`usable=5.98GiB`) |
| `last_RECYCLE` | 1790139011 | 2026-09-23T05:30Z | idle-recycle **disarmed** (`SPARK_OOM_RECYCLE=0`) since the owner decision that day — every `enforce.log` baseline line repeats "recycle DISABLED by config" |
| `last_KILL` | 1790693569 | 2026-09-29T14:52:49Z | pre-shape era |

Watchdog WARN snapshots in-regime (journal, `tag=WARN`): 2026-10-06 14:14:09Z, 14:29:17Z, 14:44:25Z,
14:59:33Z, 15:14:41Z with `usable=11.91 / 11.86 / 11.83 / 11.83 / 11.82 GiB, psi_full 0.0`, and
2026-10-07T05:21:02Z `usable=11.93 GiB psi_full=0.7`. That is the entire WARN history of the live
shape: the fill day dipped into the WARN band, never below it. (`enforce.log` carries the same
events; its last line is the 12:05:48Z baseline commit `engine top-pid = 93091 MiB`.)
One kernel line at 2026-10-06T14:13Z: `NVRM … Out of memory [NV_ERR_NO_MEMORY] _memdescAllocInternal`
— device-side allocation refusals during the same fill window; the engine absorbed it (no restart).

## 2. The rest distribution — percentiles, not a number

Ring: `/mnt/spark_nvme/oom-watchdog/state/samples.csv`, 20,001 lines (header + 20,000 samples @15 s)
covering **2026-10-09T23:33:40Z … 2026-10-13T11:34:43Z (3.47 d)** — the ring has overwritten the
first 3.5 days of the regime; that part of the window is carried by the gate-7 reads and the WARN
stamps above.

```
scp spark:/mnt/spark_nvme/oom-watchdog/state/samples.csv /tmp/hd494/
python3 <linear-interp percentiles over cols mem_avail_gib cma_free_gib usable_gib gpu_top_mib …>
```

| column | p0 | p1 | p5 | p10 | p25 | p50 | p75 | p90 | p100 |
|---|---|---|---|---|---|---|---|---|---|
| `usable_gib` (MemAvailable − CmaFree) | **15.75** | 16.48 | 16.58 | 16.60 | 16.76 | **16.84** | 16.88 | 16.92 | 17.14 |
| `cma_free_gib` | 0.12 | 0.12 | 0.12 | 0.12 | 0.13 | 0.13 | 0.16 | 0.36 | 1.33 |
| `mem_avail_gib` | 16.49 | 16.63 | 16.87 | 16.89 | 16.94 | 16.99 | 17.02 | 17.07 | 17.27 |
| `gpu_top_mib` | 99,749 in **20,000 / 20,000** samples (single value) | | | | | | | | |

`usable<12`: **0 rows. `usable<8`: 0 rows. restarts col: 0 everywhere. gpu_top_pid: one pid
(3813481) in every row.** `psi_full_avg10` > 0 in 161/20,000 rows (max 2.6) — real but light traffic
across this particular ring window.

Longer-window rest record (older rings, committed before the ring could rotate):
- gate-7 full read, 2026-10-06T11:19Z→10-07T08:48Z (21.49 h, *including the working day*): **host
  usable floor 11.73 GiB** (`spark/reports/hd489-tail-gate7-20261007/RESULTS.md:36`).
- the five WARN snapshots of 10-06 + one of 10-07: 11.82–11.93 GiB — independent witnesses of the
  same floor to ±0.2 GiB.
- the 2026-10-02→06 ring analysis (`spark/reports/hd489-overnight-20261006-0226/raw/b7-watchdog-rest-analysis.txt`):
  rest windows 12–46 GiB (median 21.8) — but most of that window predates the 20 GB shape.

**Rest floor for the live shape, recorded: p0 = 11.73 GiB (working-day window, engine at its fill
plateau), p50 ≈ 16.8 GiB (quiet rest).** The doc's former "rests at 9.83–9.90" claim belongs to a
CmaFree-4.03 reading that the record does not reproduce (ring CmaFree p90 = 0.36, max 1.33; the
4.77 GiB CMA excursion was Incident #9's traffic event, not a rest state).

## 3. Engine memory peak — the measured one, not the old certified number

- Ring plateau: **99,749 MiB flat in all 20,000 samples** (`gpu_top_mib`, command above).
- Gate-7 window plateau: 99,649 MiB (17–19 h flat after the single +5,626 MiB fill step).
- vs the watchdog committed baseline 93,091 MiB: **+6,658 MiB** (ring) / +6,558 (gate-7).
- vs the retired "certified peak" 96,235 MiB: **+3,514 / +3,414 MiB.**
- The recycle trigger is moot on this regime: `SPARK_OOM_RECYCLE=0` (disarmed), restated in every
  `enforce.log` baseline line of the window.

## 4. Preemptions and traffic — the engine's own counters, read once

```
ssh spark 'sudo docker exec vllm-qwen-spark sh -c "curl -s --max-time 5 localhost:8000/metrics" | grep -E "num_preemptions|request_success|num_requests_running"'
```

Cumulative since counter creation 2026-10-06T12:01:19Z (the live boot):
`vllm:num_preemptions_total = 173`, `request_success_total = 23,923 (stop) + 70 (length) = 23,993`,
error/abort 0. **173 preemptions ≈ 0.72 % of requests, with 0 CRIT events and 0 restarts across the
same window** — pool pressure stayed inside the pool.
⚠ `num_requests_running = 1` at read time is **contaminated by this session** (this lane is served
by spark) and is quoted for completeness only; the cumulative counters are state the engine already
persisted and the read moved nothing. The VictoriaMetrics route for a per-day split was attempted
(`scripts/bench/spark/vm-window.sh` auth path) and did not authenticate from this seat; the
cumulative counters above plus the zero-event journal are the traffic evidence used.

## 5. The re-derivation

Keeping the ledger's form (each term now measured instead of assumed):

```
ceiling = MemTotal − OS@boot − rest_floor
        = 130,593,136,640 − 4,934,000,000 − 11.73 GiB(= 12,594,991,595)
        = 113,064,145,045  →  landed 113,000,000,000 (truncation buys ~0.06 GiB of extra margin)
```

- `MemTotal` 127,532,360 kB = 130,593,136,640 B — unchanged measured constant.
- OS@boot 4.934e9 — the Incident-#6-method value (`MemTotal − MemAvailable` 15 s after the
  2026-10-06T09:22:45Z restart, recorded in hardware-spark.md §The fixed cost, MEASURED).
- rest_floor **11.73 GiB — the p0 of the recorded rest distribution (§2)**, replacing the stale
  17.78 GiB "worst usable reading" that the previous global carried.

Sanity vs the machine (the ledger trap): at the live hold `92.13e9 + 20e9 = 112.13e9` the ledger
predicts rest `130.593 − 4.934 − 112.13 = 13.53e9 = 12.60 GiB`; the box rests at p50 16.84 (quiet,
ledger ~2.6 GiB **optimistic** in the other direction on the OS term) and bottomed at **11.73** on
a filled working day (ledger **0.87 GiB optimistic**). The floor therefore had to come from the
samples' p0, not from the ledger — and the derived 113.0e9 is neither the ledger's A (112.774e9)
nor its B (104.113e9).

Consequences held by the new value:
- **The pool must not drift to 21 GB**: `pool_max = (113.0 − 92.13)e9 = 20.87e9` → 20 GB stays the
  largest 1-GB-rounded legal pool; a 21 GB pool (113.13e9 declared) exceeds the gate. The 20 GB
  pool, the profile arms and every certified constant are untouched; `fast`'s own tighter
  `device_hold_ceiling_bytes: 112.7e9` stays and keeps binding.
- **The regression guard is the watchdog WARN band**: `warn=12GiB` in the unit env (journal line
  `interval=15s gauge=MemAvailable-CmaFree warn=12GiB crit=8GiB enforce=1 recycle=0`) plus the
  monitoring rule `spark usable host memory < 12 GiB`. A rest regression breaches the recorded floor
  11.73 only after it has already printed WARN (12 GiB) — 0.27 GiB of visibility margin — and CRIT
  (8 GiB) enforces 3.7 GiB below the floor.
