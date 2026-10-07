# HD-489 tail — gate 7 PARTIAL read (12.24 h of the accruing window), 2026-10-06

Read-only. Command (run from the repo root on oldsrv):

```
ssh spark 'cat /mnt/spark_nvme/oom-watchdog/state/samples.csv' \
  | python3 spark/bench/gate7-read.py --since 2026-10-06T11:19:00Z --baseline-mib 93091
```

Window start = the current engine boot (2026-10-06T11:49:52Z container start; the CSV row at 11:19Z
is the watchdog's own first sample of the boot). The gate asks for a **working day**; this is 12.2 h,
so it is a pre-read, not the verdict.

## Output (verbatim)
```
window: 3024 samples, 2922 on the dominant gpu_top_pid 3813481 (96.6 %); other pids seen: 1 — those samples are EXCLUDED, not averaged
span 12.27 h over 13 hourly maxima: first 94023 MiB, last 99649 MiB, max 99649 MiB
hourly maxima (MiB): 94023 94023 99645 99649 99649 99649 99649 99649 99649 99649 99649 99649 99649
worst single-hour jump = +5622 MiB/h at hour +2; least-squares slope = +340.1 MiB/h
shape: BOUNDED FILL — one step of +5626 MiB reaching the plateau at hour +3, then flat for the last 4 h (spread 0 MiB, tail slope +0.0 MiB/h). The step is fixed-cost arithmetic, not a leak.
host usable floor in window = 11.73 GiB (watchdog WARN is 12 GiB, CRIT 8 GiB)
engine restarts in window: max 0
vs the watchdog's committed baseline 93091 MiB: peak is +6558 MiB — a DERIVED fixed_cost_bytes must hold that headroom
PASS: bounded — the tail holds under the 2048 MiB/h gate (report the fill step to HD-494's ceiling arithmetic, do not score it as a leak)
exit=0
```

## Self-test of the tool (same commit)
```
self-test ok   flat     want=0 got=0  (PASS: bounded — the tail holds under the 2048 MiB/h gate (report the f)
self-test ok   leak     want=1 got=1  (FAIL: gate 7 is ≤ 2048 MiB/h and this window is not)
self-test ok   twopid   want=0 got=0  (PASS: bounded — the tail holds under the 2048 MiB/h gate (report the f)
self-test ok   empty    want=2 got=2  (UNDECIDED: only 0 usable samples in the window (gate 7 asks for a work)
self-test ok   short    want=2 got=2  (UNDECIDED: only 38 usable samples in the window (gate 7 asks for a wor)
self-test ok   fill     want=0 got=0  (PASS: bounded — the tail holds under the 2048 MiB/h gate (report the f)
self-test ok   fillleak want=1 got=1  (FAIL: gate 7 is ≤ 2048 MiB/h and this window is not)
self-test ok   artifact  mixed-pid window stays quiet (got 0 MiB/h)
SELFTEST OK: gate 7 accepts a flat curve and refuses a leak, a spike-only window and a mixed-pid window
exit=0
```

## What this does and does not establish

* **Does:** the curve's shape over 12 h is a bounded fill — one +5,626 MiB step at hour +2 and then
  9 h at exactly 99,649 MiB with 0 restarts. A >2 GiB/h leak is not happening in this window.
* **Does:** the plateau sits 6,558 MiB above the committed 93,091 MiB baseline and 1,634 MiB below
  the recycle trigger (101,283 MiB) — 3.4 GiB above the 96,235 MiB certified peak HD-395 priced
  its margin against. HD-494's global ceiling re-derive must carry this, and the recycle-silence
  assumption is now thinner than the row states.
* **Does not:** close gate 7 (needs the full day under traffic that fails to return at idle), and
  it is not a clock measurement — no timed number was taken by this spark-served session (rule 0).
