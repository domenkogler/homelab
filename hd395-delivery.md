# `hd395-delivery.md` — HD-395 spark watchdog idle-recycle baseline (offline lane)

## METADATA
- Branch `session/395-watchdog-20260923-0904`, worktree `/home/domen/source/homelab-wt-20260923-0904-395`, off `main` at `cd691fa`.
- Ran as a spark-backed session (`PI_CODING_AGENT=true`, `PI_CONFIG_DIR=/home/domen/.pi`) ⇒ per `todo-table.md` §C2 this lane took **no** live action; the live half is PARKED.
- Date 2026-09-23 (CET).
- Touched, in scope: `IaC/ansible/roles/spark/files/spark-oom-watchdog.sh` (+390/−24), `IaC/ansible/roles/spark/defaults/main.yml` (+13), `IaC/ansible/roles/spark/templates/spark-oom-watchdog.service.j2` (+6), and the **HD-395 row only** in `todo.md`.
- Commits: `9dd52c2` (code), `e4407da` (row), this file's commit (delivery).
- `bash scripts/validate-all.sh` in this worktree, with the code + row changes in the tree:
  ```
  ```
OK: all playbooks pass --syntax-check
OK: all validators passed
RC=0
```
  ```

## CHANGE
**`roles/spark/files/spark-oom-watchdog.sh`**
- New acquisition state machine `baseline_tick()`: `await-health` → `settling` → `collecting` → `committed`, one step per sampler tick, **never blocks** — the loop owns the cadence and a blocking acquisition would stall the forensics ring, which is the payload.
- Commits the **max** of N plausible reads. Max, not first and not mean: the uneven 168 GiB PLE load can only make an early read read LOW, and what we need is the floor the engine sits at *fully loaded*.
- New probes: `engine_running()` (`docker inspect .State.Running`) and `engine_health_code()` (`GET /health` — not api-key gated; the snapshot's `health_http=` line has always read it without a bearer).
- **Deleted** the "ratchet the baseline DOWN only" rule: it turned any transient low read into a permanently low trigger — this defect in a different hat. Re-baseline now happens only on a new engine instance (`check_engine_restart`, which now also clears the acquisition files) or by the new `rebaseline` mode.
- `check_idle_recycle()` refuses to decide without `stage=committed` **and** a plausible value, and says why via the new rate-limited `reason_note()` (`note[recycle]` in `enforce.log`) — so "disarmed" and "dead" are no longer the same colour.
- `margin_verdict()` states the +8 GiB margin against the certified peak at commit time and in `status`. Reporting only; it never moves the trigger.
- `status` gains the baseline stage, the committed value, the `baseline_meta` line, the **boot-floor spread** (`boot_min`/`boot_max`, tracked from the first plausible read onward) and the margin verdict. The old one-line `baseline=…` echo is gone (a second, poorer source of the same number).
- New modes: `rebaseline` (operator), `self-test`, and internal `_tick`, which calls `_tick_body() { baseline_tick; check_idle_recycle; }` — the same two calls the loop makes per iteration, minus the CRIT/snapshot path.
- The state-dir `mkdir -p` is skipped for `self-test` only, so the test never touches the production XFS path.

**`roles/spark/defaults/main.yml` + `templates/spark-oom-watchdog.service.j2`**: the four new tunables, with the coin-flip measurements written beside them so the *why* survives, exported as `Environment=` lines.

Unchanged on purpose: the gauge is still `usable = MemAvailable − CmaFree` (the inverted `MemFree − CmaFree` form stays documented as a mistake in the header and is **not** reintroduced); idle usable 18.5 GiB; CRIT 8 / WARN 12; KV 16 GiB reserved (14.9 GiB accounted / 515,786 tok / 1.97× @262k); engine cage 105 GiB; `--enforce-eager` (C3) still OFF on measurement; the CRIT enforce path and the sampler schema are untouched.

## SELF-TEST
`bash IaC/ansible/roles/spark/files/spark-oom-watchdog.sh self-test` — offline by construction: `docker`, `nvidia-smi`, `curl`, `journalctl`, `dmesg`, `uptime` are stubbed on a temp `PATH`, state lands in a temp dir, and the `docker` stub is a file append, so the test cannot reach an engine. It drives the real governor by invoking this script as `_tick`, one **process per tick** — which is also how the survives-a-unit-restart property is proved.

```
self-test (HD-395 baseline + recycle governance), stubs in /tmp/spark-oom-selftest.v71s6b
  PASS C1 stage while engine not running = await-health
  PASS C1 no baseline while not running = 
  PASS C1 no restart while not running = 0
  PASS C1 stage while /health is 503 = await-health
  PASS C1 no baseline while unhealthy = 
  PASS C1 restarts while unhealthy = 0
  PASS C1 stage after health 200 = settling
  PASS C1 stage after settle = collecting
  PASS C1 restarts while acquiring = 0
  PASS C1 committed stage = committed
  PASS C1 baseline = MAX not first read = 92343
  PASS C1 boot floor min recorded = 71911
  PASS C1 boot floor max recorded = 92343
  PASS C1 never restarted the engine = 0
  PASS C2 committed = 92343
  PASS C2 no down-ratchet on a low read = 92343
  PASS C2 stage stays committed = committed
  PASS C2 no restart = 0
  PASS C3 recycle fired once = 1
  PASS C3 enforce.log records RECYCLE
  PASS C4a in-flight unreadable ⇒ no restart = 0
  PASS C4b in-flight busy ⇒ no restart = 0
  PASS C4c no baseline ⇒ no restart = 0
  PASS C4c the silence is logged with a reason
self-test: 24 assertions, 0 failed ⇒ ALL PASS (4/4 cases)
```

## MUTANTS
Each mutant removes ONE guard, applied to a **copy** in `/tmp` — the tracked file was never modified (`git status --porcelain` after the round showed only `todo.md`; `diff -q` against a pre-round copy: identical). Harness: `/tmp/hd395-mutants.sh`.

```
M1-no-baseline-tick: RED as expected (11 failing assertions) — [C1 stage while engine not running: got '' want 'await-health'] [C1 stage while /health is 503: got '' want 'await-health'] [C1 stage after health 200: got '' want 'settling'] 
M2-no-running-check: RED as expected (6 failing assertions) — [C1 stage while engine not running: got 'collecting' want 'await-health'] [C1 stage while /health is 503: got 'committed' want 'await-health'] [C1 no baseline while unhealthy: got '71911' want ''] 
M3-no-health-gate: RED as expected (5 failing assertions) — [C1 stage while /health is 503: got 'committed' want 'await-health'] [C1 no baseline while unhealthy: got '71911' want ''] [C1 stage after health 200: got 'committed' want 'settling'] 
M4-first-not-max: RED as expected (1 failing assertions) — [C1 baseline = MAX not first read: got '86243' want '92343'] 
M5-idle-on-err: RED as expected (2 failing assertions) — [C4a in-flight unreadable ⇒ no restart: got '1' want '0'] [C4b in-flight busy ⇒ no restart: got '2' want '0'] 
M6-recycle-without-baseline: RED as expected (2 failing assertions) — [C4c no baseline ⇒ no restart: got '1' want '0'] [C4c silence was not explained in enforce.log] 
M7-down-ratchet: RED as expected (1 failing assertions) — [C2 no down-ratchet on a low read: got '71911' want '92343'] 
=== mutant suite: ALL MUTANTS KILLED ===
```

Two mutants survived the first pass and both were real findings, not harness noise: one drove a `_tick` arm split across comment lines (so the mutation never applied — now factored into `_tick_body`, mutation-visible), and one showed that **no case exercised a not-running engine** (C1 now does, and M2 kills it).

## TUNABLES
| Knob | Value | Why |
|---|---|---|
| `SPARK_OOM_BASELINE_SETTLE_S` | 120 | quiet time after `/health` 200. `/health` is not the finish line — it answers 200 before the PLE checkpoint has settled, which is exactly how a 71,911 MiB "first sample" was ever recorded |
| `SPARK_OOM_BASELINE_SAMPLES` | 8 | ~2 min of reads at `INTERVAL=15`: straddles the load ramp without letting a late traffic-driven rise pose as the floor |
| `SPARK_OOM_BASELINE_SPAN_S` | 600 | the row's "~10 min" cap; commits on whichever comes first (N reads or the span) so a busy engine still gets a baseline |
| `SPARK_OOM_BASELINE_MIN_MIB` | 40000 | below this a read is not "the engine at rest" (partial load / wrong pid / `nvidia-smi` answering nothing). Refusing keeps recycle **disarmed** — the safe direction |
| `SPARK_OOM_RECYCLE_GROW_GIB` | 8 (unchanged) | deliberately not re-tuned — see PARKED #2 |
| `CERTIFIED_PEAK_MIB` / `CERTIFIED_CAGE_MIB` | 96,235 / 107,520 | HD-380's measured per-pid peak post C1/C2, and `spark_vllm_memory_limit` (105 GiB). Used ONLY to report whether the margin is reachable |

**Policy chosen** (the brief allowed one of two): **both** gates — `/health` 200 **and** a settle window, **then** the max of N samples. `/health` alone commits during the load ramp; N samples alone averages the ramp in.

## CONVERGE
```bash
nohup bash scripts/ansible-run.sh playbooks/spark.yml --tags watchdog --limit spark.kogler.si \
  > /tmp/hd395-watchdog.log 2>&1 && echo done &
```
- `--tags watchdog` is the whole ask: the watchdog tasks carry `tags: [spark, watchdog]`. **Do not** use `--tags spark,watchdog` — in Ansible that is a *union*, and it also drags the XFS/sysctl/headless tasks this row does not need. `docker_services` and `network` are outside the tag set, so this run cannot touch the engine.
- Detached always (HD-370); **never `--diff`** (`monitoring`/`spark` templates can render vault material).
- What it does: re-renders the unit (four new `Environment=` lines) and copies the script; the `Restart spark OOM watchdog` handler restarts the **unit only**. Acquisition then restarts from `await-health` for the CURRENT engine instance and must **not** recycle it; the first committed value appears as `baseline COMMITTED …` in `state/enforce.log`.
- Pre-announce text for the separate live proof (it restarts the engine on purpose): *"Planned spark engine restart for the HD-395 live proof. ~20 min cold start; `llm.*` will 502 for the duration. The engine is stopped INTENTIONALLY by the watchdog, so `unless-stopped` will not bring it back — the watchdog (or we) restart it. No agent session attached; the unit restart during the converge is NOT this restart."*
- Acceptance read-back: `sudo /usr/local/bin/spark-oom-watchdog.sh status` → `baseline: stage=committed`, a value, `boot floor: min=… max=…`, and a margin verdict. **A low boot floor must NOT be the committed baseline.**

## ROW
⏳ **Remaining = the scoped converge + the live recycle proof.** Command: `bash scripts/ansible-run.sh playbooks/spark.yml --tags watchdog --limit spark.kogler.si` run **detached** (`nohup … &` + log file) and **never with `--diff`** — `--tags watchdog` is the whole ask (`--tags spark,watchdog` is a *union* and also drags the XFS/sysctl/headless tasks, which this row does not need). The live proof restarts the engine **intentionally**: pre-announce it, run it with no agent session attached, never from a session whose own model is spark, and remember `docker stop`/`restart` is intentional in this unit so `unless-stopped` will not bring the engine back. Read-back: `sudo /usr/local/bin/spark-oom-watchdog.sh status` — the boot floor must be recorded and a low floor must NOT be the committed baseline. · [hardware-spark.md](docs/hardware-spark.md) §Unified-memory budget · [spark/stability-test.md](spark/stability-test.md) · 📋 [`prompt-420.md`](prompt-420.md)

## PARKED
1. **The live proof.** It needs one intentional engine restart on a box whose own model is spark, driven by a session that is not. Every self-test case stubs `docker`; nothing here has ever met a real engine.
2. **The +8 GiB margin is two-sided and I did not re-tune it.** With the fix the baseline commits near the TOP of the measured spread (~92,343 MiB), so the trigger is ~100,535 MiB while the certified peak is 96,235 MiB ⇒ recycle will likely stay silent. The defect as written ("low floor restarts a healthy engine") is fixed; the high-floor direction is now *visible* rather than fixed, because shrinking `RECYCLE_GROW_GIB` or redefining the baseline (absolute ceiling vs boot floor) needs a measured curve, not this lane's opinion. `status` prints the verdict every time; the live proof should capture it and the owner decides.
3. **Docs.** `docs/hardware-spark.md` §Unified-memory budget should name the baseline machine and `rebaseline`; `docs/**` is not owned by this lane, so the owning session writes it from this file's CHANGE section.

## RED LINES
- No `ssh`, no ansible, no converge, no `docker`, no engine call — offline by instruction (§C2). The only commands run were `bash -n`, the stubbed `self-test`, the temp-copy mutant harness, `validate-all.sh`, and git.
- Untouched: `prompt.md`, `todo-table.md`, any `prompt-*.md`, `docs/**`, `scripts/**`, `roles/docker_services/**`, `roles/monitoring/**`, `group_vars/**`, any `*-generated.md`; in `todo.md` only the HD-395 row (row-local hunk, no re-sort).
- No merge, push, rebase, branch/worktree deletion, or parent step.
- Did not silently widen the converge tag: the `--tags spark,watchdog` form in the task text is corrected in CONVERGE and the row rather than copied through.
- No secret printed — `in_flight`'s key path is untouched and the `docker` stub's key is the literal `stub-not-a-secret`.
