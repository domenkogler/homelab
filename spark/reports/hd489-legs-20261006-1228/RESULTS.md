# HD-489 legs session 20261006-1228 — B9, B5, B8 (+ B7 closed, A2 done)

**Seat (declared first line):** engine under test = spark · runner = oldsrv (LAN, hostname=oldsrv) ·
PI_MODEL = deepseek-ai/DeepSeek-V4-Flash (not spark/... → rule 0 clean for timed legs).
All legs stamped `--profile <arm> --client oldsrv`; harness rows in spark `~/bench/results-v2.csv`.
**Grants on record** (owner explicit instruction 2026-10-06: "Do A2, B9, B5, B8. I will skip/reject
B10."): B9 per-run `-e spark_llm_profile=ar-blk-lean -e spark_llm_allow_uncertified=true`; B5 `drop_caches`
+ `stress-oom.sh` co-resident; B8 monitoring converge. **B10 gates 6/8/9 SKIPPED per owner decision**
(reason recorded in the todo row tail: owner skip/reject; the boot + C2/C2L numbers stand in
`spark/reports/hd489-overnight-20261006-0226/`).

## B7 closure + A2 (parent chores) — done at the start of this session

- B7 CLOSED by owner decision ("long enough yesterday"): gate-4-conc-2 PASS + rest-window evidence
  (multi-day samples, latch fired only under live traffic, never at rest) — from the previous session's
  work, merged to main as part of A2 (`raw` refs in `spark/reports/hd489-overnight-20261006-0226/`).
- A2 done: `session/hd489-0225` fast-forward merged to main + pushed (`615efdbd..d3f7c33e`), that
  worktree removed, this session in a fresh worktree `homelab-wt-20261006-1227`,
  branch `session/hd489-legs-1227`.

## B9 ar-blk-lean — FAIL (BOOT) = the answer, per the brief  (~10:51–11:13Z)

- Flip: `-e spark_llm_profile=ar-blk-lean -e spark_llm_allow_uncertified=true`; converged
  `ok=158 changed=4 failed=0`. Rendered argv: `--kv-cache-memory-bytes 16000000000`, MTP-3,
  `enforce_eager` — the lean (no A4 dispatch env) arm.
- **Deterministic crash at the first safetensors shard (0/68):**
  `AttributeError: 'MergedColumnParallelLinear' object has no attribute 'data'` — the model load path
  requires the tensors the A4 dispatch env supplies; without them the WorkerProc dies every attempt
  (`raw/b9-crash.txt`). Docker restart-policy churned restarts 4→20, health 500/502.
- Rollback per the brief's loop rule: `docker update --restart=no && docker stop` (loop frozen), then
  converge back to `fast` (`failed=0`, argv 20000000000/8, `restarts=0`).
- **VERDICT: `ple_dispatch` is load-bearing — re-derived on the current pin** (matches the 2026-10-03
  root-cause note in the row). There is no bootable lean arm; the dispatch knobs are constitutive of the
  AR arm, so "what the knobs cost" cannot be measured by deletion and the 39.7 tok/s win stands as-is.
  HD-489 row: B9 item removed (finding recorded in `docs/spark-llm-profiles.md` §7).

## B5 page-cache / co-resident cliff — DONE (box on fast, healthy, restarts=0)

**B5-a — C2L immediately after `drop_caches`** (owner-granted; usable 21.15 → 14.36 GiB at the drop —
the 47.7 GiB FP8 table's page cache went cold): `raw/b5a-c2l.log`, `raw/b5a-pre.txt` ·
window 2026-10-06T11:32:27..11:38:58Z (391 s, cold_ok=yes) ·
**dec/stream 32.9 tok/s** (certified solo 39.7) · ITL p50 **78.6 ms** (certified ~65 ms) · TTFT p50 0.82 s ·
12/12 · preempts +0 · MTP 56.4 %.
→ A cold page cache costs **~17–20 %** decode and ~20 % ITL. **Not a collapse** — the win is NOT
conditional on a warm cache at the loss-of-service level; state the ~20 % cold-cache penalty, not a cliff.

**B5-b — C2L with a co-resident allocator** (`stress-oom.sh` RUNG=1, BENCH_IN=24576, live-guard floor 12;
its phase-B 24576-token prefill burst ran inside the window): `raw/b5b-c2l.log`,
`raw/stress-b5b3.log`, `raw/b5b-pre3.txt`, `raw/b5b-post2.txt` ·
window 12:09:42..12:16:24Z (401 s, cold_ok=yes) ·
**dec/stream 31.7 tok/s** · ITL p50 **64.9 ms — FLAT vs certified** · TTFT p50 0.73 s / p99 2.58 s
(head-of-line latency under co-resident prefills — the tail, not the median) ·
12/12 + ~20 stress requests (expected contamination, attributed from stress's own log) · preempts +0 ·
MTP 52.8 % · engine restarts=0 throughout.
→ The allocator costs **decode throughput (~20 % vs solo, contention)** and the **tail** (VM-verified
p95 ITL ~0.136 s, ~2× the clean 0.074 s) — **not the median ITL; no preemption, no OOM, no stranding**
(rest usable 18.5 GiB; the 21.2→18.5 drift between legs is page-cache warmth after B5-a's drop, not KV
pool growth — the clean 41.2 tok/s leg below after recovery confirms the box restored fully).

**Bonus live finding from the first B5-b attempt:** `stress-oom.sh` at its default 49k prefill sizes does
not stop cleanly — its INVALID-RUN abort path STOPPED the engine (container exit 137 at 11:46:09Z,
byte-equal to its own `INVALID RUN` timestamp; watchdog uninvolved, no CRIT in enforce.log; live guard
trip candidate): `raw/stress-b5b.log`, `raw/b5b-evidence.txt`. Recovered via
`docker start` (restart policy `unless-stopped` intact via compose) — ~17 min cold start, then the clean
B8-C2L below.

## B8 VM corroboration — DONE (with the honest exclusivity finding)

- **Monitoring is already converged on spark**: the live `/etc/alloy/config.alloy` scrape of
  `127.0.0.1:8000` (job=vllm) keeps all three latency-histogram families + engine counters, and
  VictoriaMetrics returns data for tonight's windows — the "monitoring not converged" caveat that
  attached to every prior HD-489 report is **retired**.
- vm-window.sh runs from **vps** (VM binds loopback + wg-s2s; no route from oldsrv itself); creds from
  1P `victoria-metrics_api`, never written to the transcript (`raw/b8-vm-proof.txt` holds the queries'
  key lines by window).
- **Quantile corroboration vs the harness rows** (VM, legitimately smeared by anything in the +120 s pad):
  - B10-C2L (08:53:45–09:01:25): VM ttft_p50 0.846 s vs harness 0.826 s (~2 %), itl_p95 0.099 s ✓
  - B5-a (11:32:27–11:38:58): VM ttft_p50 0.870 vs 0.820 ✓
  - B5-b (12:09:42–12:16:24): VM ttft_p50 3.44 s (the co-resident loader sits in the window — expected),
    itl_p95 0.136 s = the ~2× tail finding above ✓
  - B8-C2L (13:17:00–13:22:12): VM ttft_p50 0.625 vs harness 0.706 s (within scrape smear) ✓
- **Exclusivity finding, stated plainly (B8's real output):** the strict `req_ok_delta == N` equality,
  evaluated on the 60 s cold scrape set with +120 s pads, does **not** certify even a purposefully quiet
  leg: the clean isolated B8-C2L window measured 10/12 (under-count at scrape/import edges), B5-a's
  window +14 (my own health polls inside the pad), B5-b +20 (the stress requests, counted in its log),
  B10-C2L 16 vs 12 (the preceding C2 leg's pad overlap). Directional reading: real third-party traffic
  shows as large positive deltas/misses; sub-N or attributed-source counts are the honest pass band.
  Recommend treating exclusivity failures with their logged cause, not as flat invalidators.
- Therfore the B8 deliverable = monitoring-live proof + per-leg VM windows + this limitation, and the
  row's B8 item is closed.

## Final control leg — clean hands-off C2L on the live shape (13:17:00–13:22:12Z, 312 s, cold_ok=yes)

**dec/stream 41.2 tok/s · ITL p50 63.2 ms · TTFT p50 0.71 / p99 0.74 s · ok_delta 12/12 CLEAN · preempts
+0 · MTP 56.1 % · power 27 W** — a pristine confirmation of the certified `fast` number after all of
tonight's flips (B9 loop, B5 stresses). `raw/b8-c2l.log` + `raw/clocks-b5a.txt`/`clocks-b5b.txt`
(sustained clocks/sm + power + temperature traces for the B5 legs).

## Final state

Box on `fast` (20 GB / seqs 8), `restarts=0`, health 200 on the public endpoint, preemptions 0.0,
KV 644,732 (2.46× — unchanged from the overnight 20 GB number). validate-all.sh green. Worktree
`homelab-wt-20261006-1227` (branch `session/hd489-legs-1227`) commits below, ready for the parent merge
(A2-style). prompt.md / todo-table untouched (O2 — this lane only edits its own todo rows).

**Leg tally tonight:** B9 = FAIL(BOOT)/finding · B5 = DONE (no cliff; ~20 % cold-cache / contention
penalties, tail-only, median flat) · B8 = DONE (monitoring live; vm-window proofs + exclusivity
limitation) · B10 gates = skipped per owner (row tail records it).