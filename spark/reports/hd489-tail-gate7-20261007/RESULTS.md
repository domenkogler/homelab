# HD-489 tail — gate 7 memory-curve read (19.79 h of the accruing window), 2026-10-07

Read-only. Command (run from the repo root on oldsrv, where this session runs):

```
ssh spark 'cat /mnt/spark_nvme/oom-watchdog/state/samples.csv' \
  | python3 -I spark/bench/gate7-read.py --since 2026-10-06T11:19:00Z --baseline-mib 93091
```

Window start = the current engine boot's first watchdog sample (2026-10-06T11:19Z; container start
11:49:52Z). Read taken **2026-10-07 07:38Z**, so the window is **19.79 h** — the row asks for a *working
day*, which fills at **2026-10-07 11:19Z**; this is 3 h 41 min short of it and is labelled accordingly.
The raw series stays where the watchdog writes it (`spark:/mnt/spark_nvme/oom-watchdog/state/samples.csv`,
15 s cadence); no copy is committed because the verdict is re-derivable from that one file.

## Seat (rule 0, stated before any number)

This session's own model **is** `spark/qwen3.8-flash-next`. **No tok/s, TTFT or ITL is claimed anywhere in
this file** — gate 7 scores the shape of a memory curve, and reading a CSV adds nothing to it. What the
seat *does* contaminate is the window's traffic: the driving session's own requests hit the engine under
test, so this is **not** a traffic-free window. That direction of contamination produces *fills*, which is
precisely what the tool separates from growth (per-hour maxima of one and the same pid, then the tail's
slope) — and the tail is flat to the MiB. A timed leg of any kind must still be taken from outside the
served loop.

## Output (verbatim)

```
window: 4814 samples, 4712 on the dominant gpu_top_pid 3813481 (97.9 %); other pids seen: 1 — those samples are EXCLUDED, not averaged
span 19.79 h over 20 hourly maxima: first 94023 MiB, last 99649 MiB, max 99649 MiB
hourly maxima (MiB): 94023 94023 99645 99649 99649 99649 99649 99649 99649 99649 99649 99649 99649 99649 99649 99649 99649 99649 99649 99649
worst single-hour jump = +5622 MiB/h at hour +2; least-squares slope = +152.3 MiB/h
shape: BOUNDED FILL — one step of +5626 MiB reaching the plateau at hour +3, then flat for the last 6 h (spread 0 MiB, tail slope +0.0 MiB/h). The step is fixed-cost arithmetic, not a leak.
host usable floor in window = 11.73 GiB (watchdog WARN is 12 GiB, CRIT 8 GiB)
engine restarts in window: max 0
vs the watchdog's committed baseline 93091 MiB: peak is +6558 MiB — a DERIVED fixed_cost_bytes must hold that headroom
PASS: bounded — the tail holds under the 2048 MiB/h gate (report the fill step to HD-494's ceiling arithmetic, do not score it as a leak)
exit=0
```

## Self-test of the tool (same commit, `--self-test`)

```
self-test ok   flat     want=0 got=0  (green: bounded — the tail holds under the 2048 MiB/h gate (report the )
self-test ok   leak     want=1 got=1  (red: gate 7 is ≤ 2048 MiB/h and this window is not)
self-test ok   twopid   want=0 got=0  (green: bounded — the tail holds under the 2048 MiB/h gate (report the )
self-test ok   empty    want=2 got=2  (UNDECIDED: only 0 usable samples in the window (gate 7 asks for a work)
self-test ok   short    want=2 got=2  (UNDECIDED: only 38 usable samples in the window (gate 7 asks for a wor)
self-test ok   fill     want=0 got=0  (green: bounded — the tail holds under the 2048 MiB/h gate (report the )
self-test ok   fillleak want=1 got=1  (red: gate 7 is ≤ 2048 MiB/h and this window is not)
self-test ok   artifact  mixed-pid window stays quiet (got 0 MiB/h)
SELFTEST OK: gate 7 accepts a flat curve and refuses a leak, a spike-only window and a mixed-pid window
exit=0
```

## What this does and does not establish

**Does:**
* Over 19.79 h on the live `fast` 20 GB shape there is **no leak**: one +5,626 MiB fixed-cost step at
  hour +2, then **17 consecutive hours at exactly 99,649 MiB** with `spread 0 MiB`, tail slope 0.0 MiB/h,
  least-squares slope +152.3 MiB/h against the 2,048 MiB/h gate, **0 engine restarts**.
* The >2 GiB/h condition that would re-arm C3 `--enforce-eager` (HD-380) is **not met**, and this read
  covers 7.5 h more of the same regime than `hd489-gate7-partial-20261006/` did — the two reads agree to
  the MiB (same plateau, same pid, same step), so the 12.2 h pre-read was not a lucky window.
* The number **HD-494** carries is now measured rather than inferred twice over: the peak sits
  **+6,558 MiB** above the watchdog's committed 93,091 MiB baseline, 3,414 MiB above the 96,235 MiB
  "certified peak" HD-395 priced against, and 1,634 MiB under the recycle trigger. A derived
  `fixed_cost_bytes` must hold that headroom or the arithmetic is fiction.
* `host usable floor` over the whole window is **11.73 GiB** — inside the watchdog's 12 GiB WARN band for
  the duration, which is the shape HD-375 warned about and is not the same claim as "low".

**Does not:**
* It is **not** the working day. The day completes at 11:19Z today; re-run the one command above after
  that and the line to update is the `span … over … hourly maxima` line. Nothing in the shape is expected
  to move — the last 17 h are flat — but "re-read" is the row's condition, not a formality to assert.
* It says nothing about *leaks that need more than a day* (a slow one at 1 GiB/day is invisible to a
  2 GiB/h gate by construction). This gate was specified as a growth-rate check, and that is what passed.
* It is not gate 6. The accuracy battery's `max_tokens 1024` confound (reasoning-on spends the whole
  budget, `code-fib` returns empty) is separate, was named in `hd489-tail-gate6-20261006-2349/`, and the
  owner has since ruled the battery up to **16 × 2^10 = 16,384** — recorded, **not applied**, and when it
  is applied the B1 baseline must be re-run in the same change or the comparison basis moves on one side
  only.
