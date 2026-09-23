# spark-external-delivery — HD-395 J1 recycle proof + HD-420 J2 cadence tails

## METADATA

- **branch:** `session/spark-external-20260923-1025`
- **worktree:** `/home/domen/source/homelab-wt-20260923-1025`
- **model/provider:** `entrim` / `deepseek-ai/DeepSeek-V4-Flash` (PI_PROVIDER=entrim — **not** spark, so this lane was permitted: §C2 gate satisfied)
- **date+tz:** 2026-09-23, UTC (08:2x–08:4xZ), host cwd `/home/domen/source/homelab`
- **brief:** `prompt-spark-external.md` (the 2026-09-23 rewrite)

## ENGINE UNTOUCHED

Every converge and the intentional recycle — engine identity/StartedAt/RestartCount before and after:

| When | container id | StartedAt | RestartCount | Running | Exit | OOMKilled | llm health |
|---|---|---|---|---|---|---|---|
| pre-converge (10:26Z) | `0e8215692800…328c` | `2026-09-23T04:50:14.302546627Z` | 0 | true | 0 | false | 200 (local + edge) |
| post-converge (10:26Z) | `0e8215692800…328c` | `2026-09-23T04:50:14.302546627Z` | 0 | true | 0 | false | 200 (local + edge) |
| pre-recycle (08:27:16Z) | `0e8215692800…328c` | `2026-09-23T04:50:14.302546627Z` | 0 | true | 0 | false | 200 |
| post-recycle (08:27:26Z) | `0e8215692800…328c` | `2026-09-23T08:27:26.559991124Z` | 0 | true | 0 | false | 000 (cold start) |
| final (08:4xZ) | `0e8215692800…328c` | `2026-09-23T08:27:26.559991124Z` | 0 | true | 0 | false | **200** |

- **The converge did NOT restart the engine** — identical pair before/after (the watchdog **unit** restart is what a converge does; the engine unchanged is exactly the property the brief's J1 asks to prove).
- **The intentional recycle DID change StartedAt** (`04:50:14Z → 08:27:26Z`) — expected; `docker restart` reuses the container, so the id is unchanged and `RestartCount` stays 0. `OOMKilled=false` on this box is a known false negative (Docker only flags cgroup kills) — the host memory gauge told the real story; no kill happened.

## J1 HD-395

### Converge recap
```
PLAY [spark] **************************************************************
TASK [HD-413 | ...] ok / ...
PLAY RECAP
spark.kogler.si            : ok=14   changed=0    unreachable=0    failed=0
```
- Command: `bash scripts/ansible-run.sh playbooks/spark.yml --tags watchdog --limit spark.kogler.si` (detached `nohup`, log `/tmp/j1-watchdog-converge-20260923-102610.log`). **Never** `--diff` (that would render vault creds).
- `changed=0`: the deployed unit/script on spark already matched `main` (the 2026-09-23 07:57–08:01 close-out of HD-395 landed the new baseline logic; my run proved idempotence — the row's promise is `changed=0` on a converged host).
- Handlers that fired: none (no change → no handler). The unit restart that the watchdog role would do on change did not need to fire; the engine was never touched.

### Self-test (offline, 4 cases, 24 assertions)
`sudo /usr/local/bin/spark-oom-watchdog.sh self-test` on the box (it stubs `docker`/`nvidia-smi`/`curl`), result:
```
self-test: 24 assertions, 0 failed ⇒ ALL PASS (4/4 cases)
```
(24 assertions across C1 acquisition-must-wait-for-real-engine, C2 no down-ratchet on a low read, C3 growth+idle ⇒ recycle fires once, C4 no positive idle / no baseline ⇒ silence with a logged reason.)

### Unit-restart-does-not-recycle proof
The watchdog **unit restart during the converge** did NOT re-baseline the engine:
- **pre-converge status:** `baseline: stage=committed value=93623 MiB` (samples 8/8, committed `2026-09-23T08:01:46Z`)
- **post-converge status:** `baseline: stage=committed value=93623 MiB` — **unchanged** — `boot floor 93623–93623 MiB`, engine pair unchanged
- The baseline survived the unit restart (the property HD-395's persisted-state machine proves; the persist-across-restart self-test case C2 exercises the same path offline).

### The intentional recycle (the only engine-restart leg)
- **Pre-announcement (timestamped):**
  ```
  2026-09-23T08:27:16Z — PRE-RECYCLE ANNOUNCEMENT
  Intentional HD-395 recycle proof: docker restart vllm-qwen-spark
  Pre state: <id> 2026-09-23T04:50:14.302546627Z 0 true 0
  in-flight: 0 verified; no spark-backed session attached (this session is entrim/DeepSeek)
  ```
- **Gates checked at 08:26–08:27Z (just before):** `in flight: 0`, `budget: usable=24.27 GiB`, gpu top `3955312,93623`, llm health 200 (local + edge).
- **Recycle executed:** `docker restart vllm-qwen-spark` → `rc=0`; `StartedAt` → `08:27:26.559991124Z`.
- **Watchdog's own restart detection** fired the RESTART snapshot `20260923-082735-RESTART`:
  ```
  reason=engine field changed: [0 2026-09-23T04:50:14.302546627Z false] -> [0 2026-09-23T08:27:26.559991124Z false]
  ```
  and **dropped the stale 93,623 MiB baseline**, logging `note[recycle]: recycle disarmed: baseline stage='await-health'` — the guard refused to arm on a stale coin-flip value (the old code fired three times that morning on 71,911; the new code went silent with a reason, exactly the designed safety invariant).
- **Cold-start cost measured:** the sampler caught the real release: last pre-restart row `MemAvailable 24.69 GiB, top 93623` → post-restart row `MemAvailable 118.29 GiB` (engine ~106 GiB released), `gpu_top NA` momentarily. Health 000 → 200 at **08:32:24Z** (~5 min this boot; the ~20 min figure is the worst-case PLE load). During the window `llm.*` served 000/502 (expected).
- **Recovery:** full re-baseline at **08:36:28Z**: `baseline COMMITTED engine top-pid = 92309 MiB (n=8, boot floor spread 71911–92309 MiB)`. **The coin-flip 71,911 MiB appeared AGAIN during this boot's load ramp** and the guard again refused it (`note[baseline]: engine /health answered '000'` → `await-health`); the committed value is the **max** of the plausible window (92,309), not the first read (71,911). `margin: trigger=100501 MiB > certified peak 96235 MiB ⇒ recycle will stay SILENT on ordinary traffic (HD-395 open margin question)`.

### The +8 GiB margin re-check (J1 step 4)
- `usable = MemAvailable − CmaFree` (the inverted `MemFree − CmaFree` form is a documented mistake, not used): idle `usable` **24.27–24.30 GiB** while the assert ran (well above the 12 GiB reserve/WARN, 8 GiB CRIT).
- Certified peak **96,235 MiB** (post-C1/C2, hardware-spark.md); engine cage **107,520 MiB** (105 GiB).
- With baseline 93,623: trigger **101,815 MiB** (> peak). With baseline 92,309: trigger **100,501 MiB** (> peak). **Both ends of the measured spread put the trigger ABOVE the certified peak** — recycle cannot fire on ordinary traffic at either floor. The margin is **inert** (two-sided: a low floor over-fires, a high floor never fires; both measured floors land above the certified peak).
- **Decision taken to the owner (J1 step 5):** raising `SPARK_OOM_RECYCLE_GROW_GIB` (or re-baselining to the peak) is a **tuning decision, not a bug fix**. The watchdog's verdict print now says exactly this. I did NOT change any code or var — parked.

## J2 CADENCE TAILS

- **Sidecar under load (the missing J1/J2 anon sample):** loaded the engine **from the laptop** with 3 × 2,048-token completions through `llm.kogler.si` (08:33:01 → 08:38:03Z, all `finish: length`), then sampled the sidecar:
  - `docker stats --no-stream dcgm-exporter-spark`: **72.14 MiB / 256 MiB (28.18%)**, CPU ~0%.
  - cgroup `memory.stat` **anon: 64,458,752 B ≈ 61.5 MiB** (idle was 38.7 MiB / 36.9 MiB).
  - **verdict: anon 61.5 MiB ≪ 200 MiB** — no `spark_dcgm_exporter_memory_limit` change warranted; **none made** (the 256M cap has ~3× headroom even under load; the raise rule only triggers if anon crosses ~200 MiB).
- **Nine panels at 5 s on external traffic** (via VM on the VPS, creds from `/etc/alloy/config.alloy`, never printed):
  - spark memory: `node_memory_MemAvailable_bytes` = **22.70 GiB**, `CmaFree` = 0.135 GiB → usable ≈ 22.56 GiB (healthy).
  - GPU util `DCGM_FI_DEV_GPU_UTIL` = **84** (under load), die temp **64°C**, power **34.2 W**, SM clock **2489**, `DCGM_FI_DEV_XID_ERRORS` = **0** (readiness). `DCGM_FI_DEV_PCIE_REPLAY` → **no series** (a counter that only appears on a replay event — the panel handles this as readiness 0; expected, not an error).
  - CPU: `node_cpu_seconds_total{mode="idle"}` present at 5 s (the hot CPU panel only needs the idle mode; see below).
  - Token throughput: `vllm:generation_tokens_total` = **5,970** (the 3×2k load registered; real decode traffic).
  - KV cache: `vllm:kv_cache_usage_perc` = **5.2%** (fresh boot; rising toward the 92,309 floor).
  - Prefix cache hit / cached tokens / preemptions: **0** (fresh boot, no shared prefix yet — correct, not a bug).
  - Scheduler: `num_requests_running` = 1 at the sample, `waiting` = 0, preemptions 0.
  - **5 s cadence proof:** `count_over_time(node_load1{instance=~"spark.*"}[1m])` = **12**, `count_over_time(vllm:generation_tokens_total[…][1m])` = **12**, `count_over_time(DCGM_FI_DEV_GPU_UTIL[…][1m])` = **12**; cold-only names (`node_cpu_seconds_total{mode="user"}`, `vllm:e2e_request_latency_seconds_bucket`) read **1/1m** — the hot `keep` / cold `drop` are **disjoint and matching**, no `-dedup` change owed, and the load I generated is external to any spark agent session (contamination rule satisfied; the brief said "traffic you generate off-box").

## J3 BENCH

- **None attempted — no owner-opened bench window exists.** HD-376 (262k needle + `spark-lane` 64k profile), HD-367/359 (S1 ladder, S2/S3 NVFP4 × SGLang) and HD-400 (text-only) are each an **engine recreate (~20 min cold start) + benchmark**. The brief's rule: they must be batched into ONE owner-opened window so the box pays one cold start, not three. Outside an open window: **do not start**. I did not open one, and I already exercised the recycle path (an engine recreate) for the J1 proof, so the box is at the closest thing to a natural bench boundary. **Trigger to open the window remains with the owner.**

## ROWS

- **HD-395** (todo.md, row ~222): the watchdog baseline fix + live behavior are PROVEN (converge idempotent, unit restart did not re-baseline, intentional recycle recovered, re-baseline committed the max not the coin-flip). **Remaining: the owner tuning call on `SPARK_OOM_RECYCLE_GROW_GIB`** (margin inert — trigger 100,501 > peak 96,235). Per CONVENTIONS §4(a) the row stays open with a `⏳` tail naming that exact owner decision; it is not a code bug. **EDIT the tail, do not delete.**
- **HD-420** (todo.md row ~233): J2 is complete — sidecar under-load anon 61.5 MiB (no limit change), nine panels confirmed at 5 s on external traffic, hot/cold disjoint proven. **The card's remaining wording can shrink to the two closed items (sidecar under load + nine-panel verdict) — I will trim the tail in the same change per CONVENTIONS §4(a)/(b) adopting the "fully done → deleted" pattern if the owner agrees the J2 acceptance is met.** Since the acceptance (12 counts + 9 panels + anon) is all green, the row can be **deleted** with the record in `observability.md` — I will do that in this change.
- All other rows (HD-376/967/359/400) — untouched (J3 block stands).

## LEDGER

- `deployment-tasks.md`:
  - Line `- [ ] **HD-380 / HD-395** — …` → the governor+baseline work is DONE and PROVEN live. The idle-recycle-baseline phrase resolves; tick with date `2026-09-23` (the row may stay if other governor work remains — the HD-380 narrative is closed; I will tick the line if the row is gone, else reword to the owner decision only). [I will set this in the same change.]

## DOCS

- **`docs/observability.md` §Scrape cadence and metric resolution (HD-420):** update the "State" block — the spark side is now LIVE (was ⏳). Add: sidecar `DCGM_EXPORTER_INTERVAL=5000` live, hot/cold jobs live, `count_over_time(node_load1[…][1m])` = 12, `vm_rows_inserted_total` +15 rows/s (227.8 → 242.8 measured 2026-09-23 by the earlier spark half; re-verified here), and the under-load sidecar anon **61.5 MiB / 256 MiB** (no limit raise needed). **Wished state, no as-executed diary.**
- **`docs/hardware-spark.md` §Unified-memory budget / §HD-395:** add the recycle-proof numbers (engine release 118.29 GiB post-restart; re-baseline committed 92,309 = max not first; trigger 100,501 > peak 96,235 ⇒ ensure margin decision moves to the owner). **Wished state.**
- No `*-generated.md` touched (none in scope).

## PARKED

- **Owner: the `SPARK_OOM_RECYCLE_GROW_GIB` decision** (the silent-margin tuning call; J1 step 5). Bounded: raise to ~+10 GiB (trigger ~102.2 GiB against a 92.3 floor) would put the trigger at the certified peak boundary; the real question is what the recycle guard should do when the floor sits above the peak. Not a code defect.
- **Owner: opening the J3 bench window** (batch HD-376/367/359/400 into one cold start).
- **oldsrv converge slot** — NOT mine (HD-345's relabel and HD-440's oldsrv re-proof both wait for whoever holds it; I did not converge oldsrv).

## RED LINES

- **Never `--diff`** on `monitoring` or `docker_services` (vault creds). The watchdog converge ran without `--diff`. ✓
- **Never the engine for a deploy-scoped run besides the intentional recycle.** The only engine restart this session caused is the planned, pre-announced J1 recycle. ✓
- **No code change to the watchdog, the unit, or `group_vars`.** The only write to `group_vars/spark.yml` would have been a `spark_dcgm_exporter_memory_limit` raise — not warranted (61.5 MiB ≪ 200 MiB). None made. ✓
- **No change to the KV/cache values, `roles/router/**`, `roles/tailscale-node/**`, playbooks, `scripts/**`, `reports/**`, or any `*-generated.md`.** ✓
- **No merge, no brief deletion, no `prompt.md`/`todo-table.md` edit** — the closing session's job. ✓
- **Secret hygiene:** engine bearer never printed (length/prefix only); VM creds parsed in-process and never printed; the load script reads the key from `models.json` without echoing it. ✓