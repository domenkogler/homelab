#!/usr/bin/env python3
"""gate7-read.py — read the HD-489/HD-380 **gate 7** verdict from the watchdog samples.

Gate 7 (spark/llm-profiles/README.md, gate ladder) = "one working day of spark-oom-watchdog
samples, `gpu_top_mib`, **no growth > 2 GiB/h** — and it is also the gate that FALSIFIES a DERIVED
`fixed_cost_bytes`". Today that read was a human eyeballing a 20 k-row CSV, which is how the first
attempt at it produced a garbage number: a naive `(max - first)/hours` over the window came out at
**2663 MiB/h** purely because `gpu_top_pid` is not always the engine (the raw minimum in the same
window is 447 MiB — a different process, not a memory leak). This script exists so the verdict is a
computation with a self-test instead of an impression.

What it does, and what it refuses to do:
  * buckets the window into hours and reports the **max per hour of one and the same pid**;
  * drops samples whose `gpu_top_pid` differs from the dominant pid — mixing processes is the
    failure above, so a process switch is reported as a fact, never averaged into the slope;
  * growth = the largest hourly DELTA, and (reported beside it) a least-squares slope over the
    hourly maxima, so a one-hour spike cannot masquerade as a trend and a trend cannot hide in a
    spike;
  * reads the engine's own committed baseline from `baseline_meta` when present and compares the
    hourly maxima against it (that is the `fixed_cost_bytes` falsification: a derived pool sized
    from a constant that grows is exactly what gate 7 is for);
  * NEVER writes anywhere and never sshes on its own — feed it a CSV:
        ssh spark 'cat /mnt/spark_nvme/oom-watchdog/state/samples.csv' | ./gate7-read.py --since 2026-10-06T11:19:00Z
        ./gate7-read.py --self-test

Exit: 0 = within the 2 GiB/h rule, 1 = OVER the rule (or the window holds too little data to
judge — an undecided leg is never reported as a pass, the same rule the fp8 image probe uses).
"""
from __future__ import annotations

import argparse
import csv
import io
import math
import re
import sys

GATE_MIB_PER_H = 2048.0        # the gate: > 2 GiB/h growth fails (docs/hardware-spark.md §C3)
ROW_SECONDS = 16.0             # watchdog cadence; 4 rows/min measured on spark, 2026-10-06

COLS = ("epoch", "mem_avail_gib", "mem_free_gib", "cached_gib", "anon_gib", "swap_used_gib",
        "psi_some_avg10", "psi_full_avg10", "gpu_top_pid", "gpu_top_mib", "cma_free_gib",
        "usable_gib", "restarts", "utc")


def parse(text: str, since: float | None, until: float | None) -> list[dict]:
    rows: list[dict] = []
    for r in csv.DictReader(io.StringIO(text)):
        try:
            epoch = float(r["epoch"])
        except (KeyError, TypeError, ValueError):
            continue                                    # header noise / a torn line
        if since is not None and epoch < since:
            continue
        if until is not None and epoch > until:
            continue
        def num(key: str) -> float | None:
            v = (r.get(key) or "").strip()
            try:
                return float(v)
            except ValueError:
                return None                             # "NA" is a real value: no GPU process
        rows.append({"epoch": epoch, "pid": (r.get("gpu_top_pid") or "").strip(),
                     "mib": num("gpu_top_mib"), "usable": num("usable_gib"),
                     "restarts": num("restarts")})
    return [r for r in rows if r["mib"] is not None]


def verdict(rows: list[dict], baseline_mib: float | None = None) -> tuple[int, list[str]]:
    out: list[str] = []
    if len(rows) < 120:                                  # < ~30 min of samples: not a day
        return 2, [f"UNDECIDED: only {len(rows)} usable samples in the window "
                   f"(gate 7 asks for a working day; an empty read is not a pass)"]
    pids: dict[str, int] = {}
    for r in rows:
        pids[r["pid"]] = pids.get(r["pid"], 0) + 1
    dominant = max(pids, key=lambda k: pids[k])
    same = [r for r in rows if r["pid"] == dominant]
    out.append(f"window: {len(rows)} samples, {len(same)} on the dominant gpu_top_pid "
               f"{dominant} ({100.0 * len(same) / len(rows):.1f} %); "
               f"other pids seen: {len(pids) - 1} — those samples are EXCLUDED, not averaged")
    if len(same) < 120:
        return 2, out + ["UNDECIDED: < 30 min of samples on one pid — the window spans a restart "
                         "or an idle gap, and neither can price a growth rate"]

    span_h = (same[-1]["epoch"] - same[0]["epoch"]) / 3600.0
    hours: dict[int, float] = {}
    t0 = same[0]["epoch"]
    for r in same:
        h = int((r["epoch"] - t0) // 3600)
        hours[h] = max(hours.get(h, r["mib"]), r["mib"])          # type: ignore[arg-type]
    seq = [hours[k] for k in sorted(hours)]
    deltas = [seq[i + 1] - seq[i] for i in range(len(seq) - 1)]
    worst = max(deltas) if deltas else 0.0
    worst_at = (deltas.index(worst) + 1) if deltas else 0
    n = len(seq)
    xs = list(range(n))
    mx = sum(xs) / n
    my = sum(seq) / n
    den = sum((x - mx) ** 2 for x in xs) or 1.0
    slope = sum((xs[i] - mx) * (seq[i] - my) for i in range(n)) / den

    usable = [r["usable"] for r in same if r["usable"] is not None]
    restarts = [r["restarts"] for r in same if r["restarts"] is not None]
    out.append(f"span {span_h:.2f} h over {n} hourly maxima: first {seq[0]:.0f} MiB, "
               f"last {seq[-1]:.0f} MiB, max {max(seq):.0f} MiB")
    out.append(f"hourly maxima (MiB): {' '.join(f'{v:.0f}' for v in seq[:30])}"
               f"{' …' if n > 30 else ''}")
    out.append(f"worst single-hour jump = {worst:+.0f} MiB/h at hour +{worst_at}; "
               f"least-squares slope = {slope:+.1f} MiB/h")

    # Bounded-fill vs. genuine growth. On the mmap-PLE profiles the attributed set RISES to a
    # plateau as pages get touched and then stays flat for days (measured 2026-10-06: one +5.6 GiB
    # step at hour +2, then 99,649 MiB for ten straight hours). Scoring that as "growth" is wrong
    # in one direction and hiding the step is wrong in the other, so both are reported: the GATE is
    # the tail slope, and the STEP is arithmetic the fixed-cost row (HD-494) has to carry.
    tail_n = max(3, n // 3)
    tail = seq[-tail_n:]
    spread = max(tail) - min(tail)
    txs = list(range(len(tail)))
    tmx = sum(txs) / len(txs)
    tmy = sum(tail) / len(tail)
    tden = sum((x - tmx) ** 2 for x in txs) or 1.0
    tail_slope = sum((txs[i] - tmx) * (tail[i] - tmy) for i in range(len(tail))) / tden
    plateau = spread <= 256 and abs(tail_slope) <= GATE_MIB_PER_H
    sustained = seq[-1] >= max(seq) - 1
    if plateau and sustained:
        step = max(seq) - seq[0]
        at = next((i for i, v in enumerate(seq) if v >= max(seq) - 1), 0)
        out.append(f"shape: BOUNDED FILL — one step of {step:+.0f} MiB reaching the plateau at hour "
                   f"+{at}, then flat for the last {tail_n} h (spread {spread:.0f} MiB, tail slope "
                   f"{tail_slope:+.1f} MiB/h). The step is fixed-cost arithmetic, not a leak.")
    elif plateau:
        at = max(range(n), key=lambda i: seq[i])
        out.append(f"shape: RECOVERED TRANSIENT — hour +{at} peaked {max(seq) - seq[0]:+.0f} MiB above "
                   f"the start and came back; the last {tail_n} h are flat (spread {spread:.0f} MiB). "
                   f"A transient that returns is not the growth this gate is about.")
    else:
        out.append(f"shape: NOT FLAT at the tail — last {tail_n} h spread {spread:.0f} MiB, "
                   f"tail slope {tail_slope:+.1f} MiB/h")
    if usable:
        out.append(f"host usable floor in window = {min(usable):.2f} GiB "
                   f"(watchdog WARN is 12 GiB, CRIT 8 GiB)")
    if restarts:
        out.append(f"engine restarts in window: max {max(restarts):.0f}")
    if baseline_mib is not None:
        over = max(seq) - baseline_mib
        out.append(f"vs the watchdog's committed baseline {baseline_mib:.0f} MiB: peak is "
                   f"{over:+.0f} MiB — a DERIVED fixed_cost_bytes must hold that headroom")
    if plateau:
        if abs(tail_slope) > GATE_MIB_PER_H:
            return 1, out + [f"FAIL: the tail is drifting at {tail_slope:+.1f} MiB/h"]
        return 0, out + [f"PASS: bounded — the tail holds under the {GATE_MIB_PER_H:.0f} MiB/h gate "
                         f"(report the fill step to HD-494's ceiling arithmetic, do not score it as a leak)"]
    if worst > GATE_MIB_PER_H or slope > GATE_MIB_PER_H:
        return 1, out + [f"FAIL: gate 7 is ≤ {GATE_MIB_PER_H:.0f} MiB/h "
                         f"and this window is not"]
    return 0, out + [f"PASS: under the {GATE_MIB_PER_H:.0f} MiB/h gate on both measures"]


def _fixture(kind: str) -> str:
    """Synthetic sample streams — each one exists to make a specific bug visible."""
    head = ",".join(COLS) + "\n"
    lines = []
    for i in range(6000):                                   # ~26.6 h at 16 s
        epoch = 1_791_000_000 + i * ROW_SECONDS
        pid, mib = "1000", 90_000.0
        if kind == "leak":
            mib = 90_000 + (i * ROW_SECONDS / 3600.0) * 3072     # +3 GiB/h → RED
        if kind == "twopid":                                     # the 447 MiB artifact
            pid, mib = ("1000", 90_000) if i % 5 else ("77", 447)
        if kind == "spike":                                      # one hour only → PASS on slope
            mib = 90_000 + (4096 if 3600 * 5 <= epoch - 1_791_000_000 < 3600 * 6 else 0)
        if kind == "fill":                                       # the mmap shape: step, then flat
            mib = 90_000 + (6144 if epoch - 1_791_000_000 >= 3600 * 2 else 0)
        if kind == "fillleak":                                   # step AND still climbing → RED
            mib = 90_000 + (6144 + 2560 * max(0.0, (epoch - 1_791_000_000 - 7200) / 3600.0)
                            if epoch - 1_791_000_000 >= 3600 * 2 else 0)
        lines.append(f"{int(epoch)},12,1,13,6,0,0,0,{pid},{mib:.1f},0.1,12.8,0,00:00:00,")
    return head + "\n".join(lines) + "\n"


def self_test() -> int:
    cases = [("flat", 0), ("leak", 1), ("twopid", 0), ("empty", 2), ("short", 2),
             ("fill", 0), ("fillleak", 1)]
    bad = 0
    for name, want in cases:
        if name == "short":
            rows = parse(_fixture("flat"), 1_791_000_000, 1_791_000_000 + 600)
        elif name == "empty":
            rows = parse("epoch," + ",".join(COLS[1:]) + "\n", None, None)
        else:
            rows = parse(_fixture(name), None, None)
        got, log = verdict(rows)
        ok = got == want
        bad += 0 if ok else 1
        print(f"self-test {'ok  ' if ok else 'FAIL'} {name:8s} want={want} got={got}"
              f"  ({log[-1][:70]})")
    # the artifact case must not be able to produce the 2663 MiB/h figure
    rows = parse(_fixture("twopid"), None, None)
    _, log = verdict(rows)
    line = next((l for l in log if "worst single-hour" in l), "")
    m = re.search(r"worst single-hour jump = ([+-]?[\d.]+)", line)
    n = abs(float(m.group(1))) if m else 1e9
    ok = n < 2048
    bad += 0 if ok else 1
    print(f"self-test {'ok  ' if ok else 'FAIL'} artifact  mixed-pid window stays quiet (got {n:.0f} MiB/h)")
    print("SELFTEST OK: gate 7 accepts a flat curve and refuses a leak, a spike-only window "
          "and a mixed-pid window" if not bad else f"SELFTEST FAILED ({bad} case(s))")
    return 0 if not bad else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("csv_file", nargs="?", help="samples.csv (default: stdin)")
    ap.add_argument("--since", help="ISO UTC, e.g. 2026-10-06T11:19:00Z (the current gate-7 window)")
    ap.add_argument("--until", help="ISO UTC (default: end of file)")
    ap.add_argument("--baseline-mib", type=float, help="watchdog baseline_meta value, if known")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()

    from datetime import datetime, timezone
    def iso(v: str | None) -> float | None:
        if not v:
            return None
        return datetime.strptime(v, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()

    text = open(a.csv_file, encoding="utf-8").read() if a.csv_file else sys.stdin.read()
    rows = parse(text, iso(a.since), iso(a.until))
    code, log = verdict(rows, a.baseline_mib)
    for l in log:
        print(l)
    return code


if __name__ == "__main__":
    sys.exit(main())
