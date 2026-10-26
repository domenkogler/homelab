#!/usr/bin/env python3
"""Fail when a timed spark leg's stamp names a runner that was not allowed to take it.

> **Role:** gate over the bench results CSV — a provenance reader. Read-only: it runs no leg, reaches no
> host, restarts nothing, and judges nothing but the bytes in a results CSV.
> **Linked from:** `scripts/README.md` (the validation gate), `spark/llm-profiles/README.md` Rule 0,
> `docs/orchestration.md` §4, `todo-table.md` §C rules 2 and 9

WHY THIS EXISTS. Rule 0 — "never produce a timed spark number from a session whose own model is spark"
— is backed by two incidents and enforced by prose. Measured, not assumed: `grep -rln PI_PROVIDER
scripts/bench/` answers NOTHING and no gate read the variable at all, so nothing in the repo could tell
whether the session that wrote a row of `tok/s` was served by the box it was measuring; the mentions
elsewhere are prose — the seat briefs, `docs/orchestration.md` §4 and one comment in
`IaC/ansible/group_vars/spark.yml`. The engine cannot tell
operators apart (all the profile arms share one `model_name`, which is a client anchor that must not
move), so the only mechanical record of who took a window is the `client` column that
`scripts/bench/spark/run-scenario.sh` writes — `<hostname>/agent:<PI_MODEL>`, one value per leg, already
sitting in the CSV. This gate reads that column and asks the two questions the prose has been asking by
hand.

THE TWO LEGS, each with its verdict word:

  * RULE-0 — a stamp whose model half carries the spark provider label (`agent:spark/…`) is a timed
    number taken BY a spark-served session. Its own traffic contaminated it and its deep legs competed
    with itself for the pool it was measuring, so the number is not evidence and re-measuring the box
    will not tell you who ran it. RED, named by row and stamp. **No exception line excuses such a
    leg** — an exception is a statement about a box, and Rule 0 is a statement about a model; the
    ledger of off-station legs is not a door into this one.
  * OFF-STATION — an externally-served run takes its timed legs from the designated runner station, the
    WSL Debian laptop seat (`docs/orchestration.md` §4, `todo-table.md` §C rule 9): off-box for every
    converge target, not the engine host, owner of no converge slot. A leg whose stamp names another
    box is RED **as off-station, not as a failed measurement** — the number may be perfectly good, what
    is missing is the provenance that lets anyone quote it. A ledger line naming that exact leg
    downgrades it to printed, counted NAMED DEBT.

The station test normalises the hostname rather than comparing it: this laptop answers `Domen_P14s`
from `socket.gethostname()` while the briefs write `DomenP14s`, and HD-474 measured that a
separator-blind comparison silently dropped a provider from one render and SKIPped a probe in the other.
So the comparison is `host_norm()` — the repo's ONE host-name normaliser, imported from
`scripts/harness/render-pi-config.py`, not a second opinion written here.

THE LEDGER. `scripts/gate/bench_provenance_exceptions.txt` holds one line per ACCEPTED off-station leg:
`<step><TAB><ts><TAB><reason>`. It is keyed on a single leg because that is the only key that cannot
become an amnesty: a line naming a host, a class of legs or a model would retro-actively excuse every
leg of that class ever written, which is how a debt register turns into a mute button. A line whose leg
is not in the CSV read is printed NOT MATCHED, so the book cannot quietly rot into a standing free pass;
a reason under `MIN_REASON` characters is refused, because the line's whole job is the argument.

WHAT IS NEVER A GREEN. No CSV → `NOT JUDGED`, exit 2. A CSV whose header carries no `client` column →
the legs are unattributable, `NOT JUDGED`, exit 2. A CSV holding a header and no row → nothing was read,
`NOT JUDGED`, exit 2. A ledger that cannot be parsed → exit 2, because an unread ledger would exempt
everything silently. A leg whose stamp carries no model half (`agent:none`, a headless run — which Rule 0
allows) is NOT judged by the Rule 0 leg and says so in the OK line, which is then marked PARTIAL: a
verdict about the station is not a verdict about the model.

WHAT IT CANNOT SEE, stated rather than left to be discovered:
  * It reads a CSV, not a host. `PI_PROVIDER` at the time of the leg is not in the file, so the Rule 0
    leg infers the serving provider from `PI_MODEL`, whose id carries the provider label
    (`spark/qwen3.8-flash-next` in `scripts/harness/pi/models-spec.yml`). A session that exported
    `PI_MODEL` under a different name while spark served it leaves no trace here — that is a seat-side
    lie, and the seat's own pre-flight is the instrument for it.
  * `--client <id>` is free text, so an operator can stamp anything. This gate makes a lie VISIBLE and
    cheap to spot (a stamp that contradicts the report around it), not impossible.
  * Which legs are timed is not decided here: every row `run-scenario.sh` appends is a timed leg by
    construction. A CSV from a different instrument is out of scope, and a header without `client` is
    refused rather than judged.
  * A leg's NUMBERS are not judged — window exclusivity is `vm-window.sh`, and the `flag` column already
    prints `contaminated` when the window was not the leg's alone.

Run:    python3 scripts/gate/check_bench_provenance.py [--csv F] [--exceptions F] [--show] [--self-test]
Exit:   0 = every leg in the CSV read is accounted for (on-station, or a named exception) and no leg is
          a Rule 0 leg · 1 = at least one RULE-0 / OFF-STATION / UNNAMED finding
        2 = NOT JUDGED: the CSV is absent, unattributable or empty, or the ledger could not be parsed —
          a run that could not read the stamp of a leg does not get to call it clean.
Stdlib only, plus one import of `host_norm()` from the harness renderer. It never touches a host.
"""
from __future__ import annotations

import argparse
import csv
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
from contextlib import redirect_stdout
from dataclasses import dataclass, field
from io import StringIO
from pathlib import Path

# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import root as _hl_root, script_path  # noqa: E402

ROOT = _hl_root(__file__)

# Where a leg lands. `run-scenario.sh` writes `${RESULTS_CSV:-$BENCH_DIR/results-v2.csv}` with
# `BENCH_DIR` defaulting to the writer's own directory, so the repo-side default is this path. The env
# var is honoured for the same reason the writer honours it, so the two cannot disagree about which
# file a lane's legs went into. It is deliberately NOT read out of the writer's text: the spark lane
# edits that file, and a gate that parses a neighbour's script breaks the day the neighbour improves it.
RESULTS_DEFAULT = "scripts/bench/spark/results-v2.csv"
RESULTS_ENV = "RESULTS_CSV"
EXCEPTIONS_DEFAULT = Path("scripts/gate/bench_provenance_exceptions.txt")

# The designated runner station: the WSL Debian laptop seat. A RULE, so it is written here rather than
# scraped out of a brief — and compared with host_norm(), because the box answers `Domen_P14s` while
# the briefs write `DomenP14s` (see the docstring; HD-474 is the measurement behind that sentence).
STATION = "domenp14s"

# The provider label Rule 0 bars. Model ids in scripts/harness/pi/models-spec.yml are
# `<provider>/<model>`, so `agent:spark/qwen3.8-flash-next` is spark-served and `agent:entrim/x` is not.
SPARK_PROVIDER = "spark"

STAMP_SEP = "/agent:"
CLIENT_COL = "client"
MIN_REASON = 40       # under 40 characters is not an argument — the floor check_self_converge_guard.py
                      # uses for a guard-exemption reason, kept identical so the two do not disagree.
MAX_PRINTED = 20


class Boundary(Exception):
    """The run could not judge — printed as NOT JUDGED with its reason, exit 2, never a green."""


# --------------------------------------------------------------------------- the stamp
def split_stamp(stamp: str) -> tuple[str, str]:
    """`(host, model)` halves of a `run-scenario.sh` client stamp.

    The writer's default is `<hostname -s>/agent:<PI_MODEL>`, but `--client` is free text: the HD-489
    overnight legs are stamped plain `--client oldsrv`, which has no `agent:` half at all. So a stamp
    without the separator is taken as a whole — a bare box name — and its model half is absent, which
    the Rule 0 leg reports as NOT JUDGED for that leg rather than as a pass."""
    head, sep, model = stamp.partition(STAMP_SEP)
    if not sep:
        return stamp.strip(), ""
    return head.strip(), model.strip()


def provider_of(model: str) -> str:
    """The provider label a model id names, or `''` when the stamp cannot tell us.

    `spark/qwen3.8-flash-next` -> `spark`; `agent:none` (a headless run, which Rule 0 explicitly
    sanctions) and a bare model id name no provider here, so the Rule 0 leg is NOT JUDGED for them."""
    label, sep, _rest = model.partition("/")
    return label.strip().lower() if sep else ""


def station_match() -> tuple[object, str]:
    """`(host_norm, why)` — the repo's one host-name normaliser, or a Boundary.

    Importing rather than re-spelling the rule is the point: HD-474's defect was two files holding two
    opinions about one laptop's spelling. A failed import is a boundary, not a fallback to `lower()`,
    because a gate that quietly degrades to the comparison that already failed once would be worse than
    no gate."""
    try:
        path = script_path("render-pi-config.py", ROOT)
        spec = importlib.util.spec_from_file_location("render_pi_config_for_provenance", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod.host_norm, "host_norm() from " + str(path.relative_to(ROOT))
    except Exception as exc:                                    # noqa: BLE001 — any failure is a boundary
        raise Boundary(f"the station test cannot load host_norm() from scripts/harness/render-pi-config.py "
                       f"({exc}) — comparing hostnames with a second opinion is how HD-474 happened") from exc


def is_on_station(host: str, norm) -> bool:
    return bool(norm(host)) and norm(host) == norm(STATION)


# --------------------------------------------------------------------------- inputs
@dataclass
class Parsed:
    legs: list = field(default_factory=list)
    notes: list = field(default_factory=list)     # what this run could NOT read, printed every time
    keyable: bool = True                          # are step+ts present, so ledger lines CAN be matched?


def read_legs(path: Path) -> Parsed:
    """Every data row of the results CSV, with the `client` column found BY HEADER NAME.

    Position is not part of the verdict: the writer's header is wide, and a writer that adds, drops or
    reorders one column would otherwise leave this gate reading a `profile` arm where an operator stamp
    used to sit — a false green with a straight face. A header without `client` is unattributable, which
    is NOT JUDGED rather than a finding, because nothing here can prove who took those legs."""
    if not path.exists():
        raise Boundary(f"{path} does not exist — the legs it would have listed were never read")
    if path.is_dir():
        raise Boundary(f"{path} is a directory, not a results CSV")
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise Boundary(f"{path} could not be read ({exc})") from exc
    rows = [r for r in csv.reader(text.splitlines()) if r and any(c.strip() for c in r)]
    if not rows:
        raise Boundary(f"{path} holds nothing at all — no header, no leg")
    header = [c.strip() for c in rows[0]]
    if CLIENT_COL not in header:
        raise Boundary(f"{path.name} has no `{CLIENT_COL}` column — the legs in it name nobody, so neither "
                       "Rule 0 nor the station rule can be judged from it (the pre-v2 results.csv is that "
                       "shape: the stamp column arrived with HD-489)")
    out, keyable = Parsed(), all(k in header for k in ("step", "ts"))
    notes = out.notes
    if not keyable:
        notes.append(f"{path.name} has no step/ts columns, so an exception line has nothing to match "
                     "against — off-station legs cannot be excused by this run")
    for i, raw in enumerate(rows[1:], start=2):
        if len(raw) != len(header):
            notes.append(f"{path.name} line {i} carries {len(raw)} field(s) against a {len(header)}-column "
                         "header — that row is NOT JUDGED")
            continue
        rec = dict(zip(header, (c.strip() for c in raw)))
        stamp = rec.get(CLIENT_COL, "")
        host, model = split_stamp(stamp)
        out.legs.append(Leg(line=i, step=rec.get("step", "?"), ts=rec.get("ts", "?"),
                            stamp=stamp, host=host, model=model))
    if not out.legs:
        raise Boundary(f"{path.name} holds a header and no leg — nothing was measured, so nothing is proven")
    out.keyable = keyable
    return out


@dataclass
class Leg:
    line: int
    step: str
    ts: str
    stamp: str
    host: str
    model: str


def read_exceptions(path: Path) -> tuple[dict, list]:
    """The ledger as `(step, ts) -> reason`. A missing book is NO exceptions; a malformed one is a
    boundary, because an unread line that exempts nothing must not read as an empty book."""
    if not path.exists():
        return {}, [f"no exception ledger at {path} — every off-station leg reddens; a missing book means "
                    "nothing has been accepted, not that everything has"]
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    book: dict = {}
    for i, line in enumerate(lines, start=1):
        if not line.strip() or line.startswith("#"):
            continue
        cols = [c.strip() for c in line.split("\t")]
        if len(cols) < 3 or not cols[0] or not cols[1]:
            raise Boundary(f"{path.name}:{i} is not `<step><TAB><ts><TAB><reason>` — an unread exception "
                            "line is not an absent one, and guessing would exempt a leg nobody accepted")
        if len(cols[2]) < MIN_REASON:
            raise Boundary(f"{path.name}:{i} carries a {len(cols[2])}-character reason — under "
                           f"{MIN_REASON} characters is an excuse, not an argument")
        book[(cols[0], cols[1])] = cols[2]
    return book, []


# --------------------------------------------------------------------------- verdict
@dataclass
class Finding:
    kind: str          # RULE-0 | OFF-STATION | UNNAMED
    leg: Leg
    why: str

    def line(self) -> str:
        return (f"{self.kind} {self.leg.step} {self.leg.ts} (line {self.leg.line}) "
                f"client={self.leg.stamp!r} — {self.why}")


@dataclass
class Verdict:
    findings: list = field(default_factory=list)
    named: list = field(default_factory=list)         # (leg, reason) excused by the ledger
    on_station: int = 0
    rule0_unjudged: int = 0                            # legs whose stamp cannot name a provider
    matched: set = field(default_factory=set)          # ledger keys a leg actually consumed
    rule0_ledgered: list = field(default_factory=list)  # lines that CANNOT excuse a Rule 0 leg
    notes: list = field(default_factory=list)


def judge(legs: list, book: dict, keyable: bool, norm) -> Verdict:
    v = Verdict()
    for leg in legs:
        # --- leg 1: Rule 0. The model half decides it; the hostname is irrelevant, because standing
        # on the station does not lift Rule 0 (todo-table.md §C rule 9 says exactly that).
        provider = provider_of(leg.model)
        if not provider:
            v.rule0_unjudged += 1
        elif provider == SPARK_PROVIDER:
            v.findings.append(Finding(
                "RULE-0", leg,
                "a timed leg taken by a session served by the engine it measures — Rule 0 bars it, and "
                "no exception line opens this door (an exception is about a box, this is about a model)"))
            if keyable and (leg.step, leg.ts) in book:
                v.rule0_ledgered.append((leg, book[(leg.step, leg.ts)]))
        # --- leg 2: the station. Both legs are judged for every row: a leg can be on-station and still
        # barred, and off-station with a clean model is a different finding with a different repair.
        if not leg.host:
            v.findings.append(Finding("UNNAMED", leg,
                                      "the stamp names no runner at all, so the leg cannot be attributed"))
            continue
        if is_on_station(leg.host, norm):
            v.on_station += 1
            continue
        reason = book.get((leg.step, leg.ts)) if keyable else None
        if reason:
            v.named.append((leg, reason))
            v.matched.add((leg.step, leg.ts))
        else:
            v.findings.append(Finding(
                "OFF-STATION", leg,
                f"taken on {leg.host!r}, not on the designated runner station {STATION!r} "
                "(off-box for every target, not the engine host, owner of no converge slot). This is a "
                "provenance finding, not a failed measurement — either re-take the leg on the station or "
                "add the line this leg needs to the exception ledger"))
    return v


def report(parsed: Parsed, v: Verdict, csv_path: Path, exc_path: Path, book: dict, norm_src: str) -> int:
    """Print the whole verdict — including what this run could NOT read.

    Two note kinds, worded apart on purpose: `NOT JUDGED` is a leg or a ledger line this run could not
    judge (a row that does not line up with its header, a book whose keys the CSV cannot carry), `NOTE`
    is a fact about the inputs that changes nothing (no ledger file, which means nothing has been
    accepted rather than everything having been)."""
    for note in parsed.notes:
        print(f"NOT JUDGED: {note}")
    for note in v.notes:
        print(f"NOTE: {note}")
    print(f"read {len(parsed.legs)} timed leg(s) from {csv_path}; station test is host_norm({STATION!r}"
          f") via {norm_src}; exception ledger {exc_path} carries {len(book)} line(s)")
    if v.rule0_ledgered:
        print(f"NOTE: {len(v.rule0_ledgered)} Rule 0 leg(s) have an exception line and it does NOT apply — "
              "the ledger excuses a box, never a spark-served session:")
        for leg, reason in v.rule0_ledgered:
            print(f"  {leg.step} {leg.ts} (line {leg.line}): {reason[:60]}")
    if v.named:
        print(f"NAMED DEBT: {len(v.named)} off-station leg(s) excused by {exc_path.name} — each is closed "
              "by re-taking the leg on the station, not by deleting the line:")
        for leg, reason in v.named:
            print(f"  {leg.step} {leg.ts} (line {leg.line}) client={leg.stamp!r} — {reason}")
    unmatched = sorted(k for k in book if k not in v.matched)
    if unmatched:
        head = ("no leg in this CSV matched" if parsed.legs else "the CSV was not read, so nothing matched")
        print(f"NOT MATCHED: {len(unmatched)} ledger line(s) {head} — a line keys ONE leg, so it excuses "
              "nothing while unmatched; delete it in the change that removes the leg it names")
        for step, ts in unmatched[:10]:
            print(f"  {step} {ts}")
    if v.findings:
        barred = len([f for f in v.findings if f.kind == "RULE-0"])
        print(f"FAIL: {len(v.findings)} leg(s) name a runner that was not allowed to take them — "
              f"{barred} Rule 0, {len(v.findings) - barred} off-station or unnamed:")
        for f in v.findings[:MAX_PRINTED]:
            print(f"  {f.line()}")
        if len(v.findings) > MAX_PRINTED:
            print(f"  … {len(v.findings) - MAX_PRINTED} more, same legs, not listed")
        return 1
    partial = ""
    if v.rule0_unjudged:
        partial = (f" — PARTIAL: Rule 0 was NOT JUDGED for {v.rule0_unjudged} leg(s) whose stamp carries no "
                   "model half (`agent:none`, a headless run): legal under Rule 0, but this run cannot "
                   "prove which model served them")
    if parsed.notes:
        partial += " — PARTIAL: see NOT JUDGED above"
    print(f"OK: {len(parsed.legs)} leg(s) — {v.on_station} named the station, {len(v.named)} carried as "
          f"named debt, none taken by a spark-served session{partial}")
    return 0


# --------------------------------------------------------------------------- self-test
HEADER = ["step", "ts", "scenario", "profile", "client", "seed", "flag"]


def _csv_text(rows: list, header: list | None = None) -> str:
    """A results CSV built from (step, ts, client) triples, with every value placed under its OWN column
    name — so a fixture can move the `client` column and the row moves with it (arm (e)'s subject)."""
    head = header or HEADER
    out = [",".join(head)]
    for step, ts, client in rows:
        vals = {"step": step, "ts": ts, "scenario": "C2", "profile": "unlabelled",
                "client": client, "seed": "42", "flag": "ok"}
        out.append(",".join(vals.get(k, "") for k in head))
    return "\n".join(out) + "\n"


def _run_text(text: str, book_lines: list | None = None) -> tuple:
    """Judge a fixture CSV (and optionally a fixture ledger) in-process, keeping the printed text."""
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "results-v2.csv"
        p.write_text(text, encoding="utf-8")
        exc = Path(td) / "exceptions.txt"
        if book_lines is not None:
            exc.write_text("\n".join(book_lines) + "\n", encoding="utf-8")
        norm, src = station_match()
        try:
            parsed = read_legs(p)
            book, notes = read_exceptions(exc)
        except Boundary as e:
            return 2, f"NOT JUDGED: {e}\n", None
        v = judge(parsed.legs, book, parsed.keyable, norm)
        v.notes += notes
        buf = StringIO()
        with redirect_stdout(buf):
            rc = report(parsed, v, p, exc, book, src)
        return rc, buf.getvalue(), v


def _run_path(path: Path) -> tuple:
    """The whole path a real run takes, including the boundary a missing CSV is. The ledger it reads is
    one that does not exist: an arm about the CSV must not depend on what this repo has accepted."""
    buf = StringIO()
    with redirect_stdout(buf):
        try:
            norm, src = station_match()
            parsed = read_legs(path)
            book, notes = read_exceptions(Path("no-such-ledger-for-this-fixture.txt"))
            v = judge(parsed.legs, book, parsed.keyable, norm)
            v.notes += notes
            rc = report(parsed, v, path, Path("bench_provenance_exceptions.txt"), book, src)
        except Boundary as exc:
            print(f"NOT JUDGED: {exc} — a missing file is not a green, and not a pass either")
            return 2, buf.getvalue()
    return rc, buf.getvalue()


def self_test() -> int:
    fails = arms = 0
    SPARK = "oldsrv/agent:spark/qwen3.8-flash-next"        # a spark-served session, off-station
    SPARK_STATION = "Domen_P14s/agent:spark/qwen3.8-flash-next"
    GOOD = "Domen_P14s/agent:entrim/deepseek"              # the station, externally served
    GOOD_ALT = "DomenP14s/agent:entrim/deepseek"           # the same box, the other spelling
    OFF = "oldsrv/agent:entrim/deepseek"
    LEDGER = ["# fixture ledger",
              "deep-C1\t20261018-071201\ttaken from oldsrv by an externally-served session while the "
              "station was offline for the window"]

    def check(label: str, ok: bool, detail: str = "") -> None:
        nonlocal fails, arms
        arms += 1
        fails += not ok
        print(f"  arm {label}: {'ok' if ok else 'FAIL'}{(' — ' + detail) if (detail and not ok) else ''}")

    # (a) RULE 0. A spark-served stamp reddens, wherever it was taken, and says which row and stamp.
    rc, out, _v = _run_text(_csv_text([("B7-C2", "20261018-071201", SPARK)]))
    check("(a) a `agent:spark/…` stamp reddens the Rule 0 leg",
          rc == 1 and "RULE-0" in out and "B7-C2" in out and SPARK in out, f"rc {rc}: {out[-160:]}")
    rc, out, _v = _run_text(_csv_text([("B7-C2", "20261018-071201", SPARK_STATION)]))
    check("(a1) on the station box it reddens too — the seat does not lift Rule 0",
          rc == 1 and "RULE-0" in out, f"rc {rc}: {out[-160:]}")
    rc, out, _v = _run_text(_csv_text([("deep-C1", "20261018-071201", SPARK)]), LEDGER)
    check("(a2) an exception line does NOT open a Rule 0 door",
          rc == 1 and "RULE-0" in out and "does NOT apply" in out, f"rc {rc}: {out[-200:]}")
    rc, out, _v = _run_text(_csv_text([("B7-C2", "20261018-071201", GOOD),
                                       ("B7-C1", "20261018-071301", "spark-host/agent:entrim/deepseek")]))
    check("(a3) a host NAMED spark with an external model is off-station, never a Rule 0 leg",
          rc == 1 and "RULE-0" not in out and "OFF-STATION" in out, f"rc {rc}: {out[-160:]}")

    # (b) the station, externally served, passes — under either spelling of the box's hostname.
    for label, stamp in (("station spelling `Domen_P14s`", GOOD), ("brief spelling `DomenP14s`", GOOD_ALT)):
        rc, out, _v = _run_text(_csv_text([("B7-C2", "20261018-071201", stamp)]))
        check(f"(b) a {label} stamp passes", rc == 0 and "OK:" in out, f"rc {rc}: {out[-160:]}")
    rc, out, _v = _run_text(_csv_text([("B7-C2", "20261018-071201", "Domen_P14s/agent:none")]))
    check("(b1) an unstamped model half passes the station rule and marks the run PARTIAL",
          rc == 0 and "PARTIAL" in out and "NOT JUDGED" in out, f"rc {rc}: {out[-200:]}")

    # (c) off-station: RED alone, NAMED DEBT with a line, and the line must not spread.
    rc, out, _v = _run_text(_csv_text([("B7-C2", "20261018-071201", OFF)]))
    check("(c) an off-station stamp with no ledger line reddens",
          rc == 1 and "OFF-STATION" in out and STATION in out, f"rc {rc}: {out[-160:]}")
    rc, out, _v = _run_text(_csv_text([("deep-C1", "20261018-071201", OFF)], ), LEDGER)
    check("(c1) the same leg with a ledger line passes as NAMED DEBT",
          rc == 0 and "NAMED DEBT" in out and "externally-served session" in out, f"rc {rc}: {out[-200:]}")
    rc, out, _v = _run_text(_csv_text([("deep-C1", "20261018-071201", OFF),
                                       ("deep-C2", "20261018-071401", OFF)], ), LEDGER)
    check("(c2) the line excuses ITS leg only — a second off-station leg stays red",
          rc == 1 and "NAMED DEBT: 1" in out and "OFF-STATION deep-C2" in out, f"rc {rc}: {out[-220:]}")
    rc, out, _v = _run_text(_csv_text([("deep-C1", "20261018-071201", OFF)]), LEDGER +
                            ["ghost-C9\t20260101-000000\tthis leg is not in the CSV read, so the line "
                             "excuses nothing and must be reported"])
    check("(c3) a ledger line whose leg is absent prints NOT MATCHED",
          rc == 0 and "NOT MATCHED" in out and "ghost-C9" in out, f"rc {rc}: {out[-200:]}")
    rc, out, _v = _run_text(_csv_text([("d", "1", OFF)]), ["# book", "d\t1\tit was fine"])
    check("(c4) a ledger reason under the floor is NOT JUDGED, not an exemption",
          rc == 2 and "NOT JUDGED" in out and "argument" in out, f"rc {rc}: {out[-200:]}")
    rc, out, _v = _run_text(_csv_text([("d", "1", OFF)], ), ["# book", "d  no tabs at all"])
    check("(c5) a malformed ledger line is NOT JUDGED rather than an unread free pass",
          rc == 2 and "NOT JUDGED" in out, f"rc {rc}: {out[-160:]}")

    # (d) a CSV that cannot be judged is never green.
    with tempfile.TemporaryDirectory() as td:
        rc, out = _run_path(Path(td) / "not-here.csv")
        check("(d) a missing CSV prints NOT JUDGED and is not green", rc == 2 and "NOT JUDGED" in out,
              f"rc {rc}: {out[-120:]}")
        empty = Path(td) / "empty.csv"
        empty.write_text(_csv_text([]), encoding="utf-8")
        rc2, out2 = _run_path(empty)
        check("(d1) a header-only CSV is NOT JUDGED — nothing was read", rc2 == 2 and "NOT JUDGED" in out2,
              f"rc {rc2}: {out2[-120:]}")
        old = Path(td) / "results.csv"
        old.write_text("step,ts,scenario,seed,dec_tok_s_per_stream\nB1,20260914-231732,C2,42,37.4\n",
                       encoding="utf-8")
        rc3, out3 = _run_path(old)
        check("(d2) a CSV with no `client` column is NOT JUDGED — the legs name nobody",
              rc3 == 2 and "NOT JUDGED" in out3, f"rc {rc3}: {out3[-120:]}")

    # (e) the parser reads the COLUMN, not the place where it used to sit.
    shuffled = ["step", "ts", "scenario", "profile", "seed", "flag", "client"]
    rc, out, _v = _run_text(_csv_text([("B7-C2", "20261018-071201", SPARK)], header=shuffled))
    check("(e) a leg still reddens when `client` is not the column it historically sat in",
          rc == 1 and "RULE-0" in out, f"rc {rc}: {out[-160:]}")
    rc, out, _v = _run_text(_csv_text([("B7-C2", "20261018-071201", GOOD)], header=shuffled))
    check("(e1) and still passes in that shape — the verdict moved with the header, not the index",
          rc == 0, f"rc {rc}: {out[-160:]}")
    short = _csv_text([("B7-C2", "20261018-071201", GOOD)]) + "B7-C3,20261018-071301,C2\n"
    rc, out, _v = _run_text(short)
    check("(e2) a row with fewer fields than the header is NOT JUDGED and marks the run PARTIAL",
          rc == 0 and "NOT JUDGED" in out and "PARTIAL" in out, f"rc {rc}: {out[-220:]}")

    # the shapes the rule must NOT accuse.
    rc, out, _v = _run_text(_csv_text([("B7-C2", "20261018-071201", "Domen_P14s/agent:spark-arms/v16b")]))
    check("(f) a provider label that merely starts like spark is not a Rule 0 leg",
          rc == 0 and "RULE-0" not in out, f"rc {rc}: {out[-160:]}")
    rc, out, _v = _run_text(_csv_text([("B7-C2", "20261018-071201", "/agent:entrim/deepseek")]))
    check("(f1) a stamp naming no box reddens as UNNAMED, never as a silent pass",
          rc == 1 and "UNNAMED" in out, f"rc {rc}: {out[-160:]}")

    print(f"check_bench_provenance.py --self-test: {arms} arms, {fails} failing arm(s)")
    if fails:
        return 1
    if os.environ.get("BENCH_PROV_MUTANT") == "1":
        return 0        # the mutation leg is skipped inside a mutant — it would recurse
    failed = mutation_test()
    print(f"check_bench_provenance.py --self-test mutations: {failed} mutant(s) escaped")
    return 1 if failed else 0


MUTATIONS = [
    # (label, source anchor, replacement, which arm must go red)
    ("the client column is read by position, not by header",
     '        stamp = rec.get(CLIENT_COL, "")',
     '        stamp = list(raw)[4] if len(raw) > 4 else ""',
     "the column-order arms"),
    ("the Rule 0 provider test is dropped",
     '        elif provider == SPARK_PROVIDER:',
     '        elif False:',
     "the Rule 0 arms"),
    ("the spark provider is matched by prefix, so `spark-arms` reddens too",
     '        elif provider == SPARK_PROVIDER:',
     '        elif provider.startswith(SPARK_PROVIDER):',
     "the near-miss control"),
    ("any box is the station",
     '        if is_on_station(leg.host, norm):',
     '        if True:',
     "the station arms"),
    ("the ledger excuses a whole class instead of one leg",
     '        reason = book.get((leg.step, leg.ts)) if keyable else None',
     '        reason = (next(iter(book.values())) if book else None) if keyable else None',
     "the one-leg-only arm"),
    ("a missing CSV is a green",
     '        raise Boundary(f"{path} does not exist — the legs it would have listed were never read")',
     '        return Parsed()',
     "the missing-CSV arm"),
    ("an unstamped model half counts as a judged Rule 0 pass",
     '        if not provider:\n            v.rule0_unjudged += 1',
     '        if False:\n            v.rule0_unjudged += 1',
     "the PARTIAL arm"),
    ("a Rule 0 leg is excused by an exception line too",
     '        elif provider == SPARK_PROVIDER:',
     '        elif provider == SPARK_PROVIDER and (leg.step, leg.ts) not in book:',
     "the no-exception-for-Rule-0 arm"),
]


def mutate(src: str, old: str, new: str) -> str | None:
    """Patch the CODE occurrence of `old`. The table above carries the same strings as data, so the
    table region is excluded — a checker that edited its own mutation table would prove nothing."""
    start = src.index("MUTATIONS = [")
    end = src.index("\n]", start)
    for m in re.finditer(re.escape(old), src):
        if not start <= m.start() < end:
            return src[:m.start()] + new + src[m.end():]
    return None


def mutation_test() -> int:
    """Self-mutation: patch THIS file's own parsing and verdict in a copy and require the arms to go red.
    A checker that cannot be broken is a claim, not a check (CONVENTIONS §6: a test that cannot fail is
    not evidence) — and this gate's whole subject is a column a reader could simply assume the position
    of, which is the assumption arm (e) exists to break."""
    src = Path(__file__).read_text(encoding="utf-8")
    failed = 0
    for label, old, new, must_break in MUTATIONS:
        mutated = mutate(src, old, new)
        if mutated is None:
            print(f"  mutate {label}: FAIL — the source anchor moved")
            failed += 1
            continue
        # The mutant needs scripts/lib/repo_root.py on its import path the way every gate resolves it,
        # so it goes into a throwaway scripts/gate/ with a copied lib, and $REPO points it back at THIS
        # checkout. A copy left inside the tree would be an untracked file every other gate has to read.
        with tempfile.TemporaryDirectory() as td:
            fake = Path(td) / "scripts"
            (fake / "lib").mkdir(parents=True)
            (fake / "gate").mkdir()
            shutil.copy(ROOT / "scripts" / "lib" / "repo_root.py", fake / "lib" / "repo_root.py")
            mutant = fake / "gate" / "bench_provenance_mutant.py"
            mutant.write_text(mutated, encoding="utf-8")
            r = subprocess.run([sys.executable, str(mutant), "--self-test"], capture_output=True,
                               text=True, encoding="utf-8", errors="replace", env=dict(os.environ, BENCH_PROV_MUTANT="1", REPO=str(ROOT)),
                               stdin=subprocess.DEVNULL)
        broke = sorted({ln.split(" arm ")[1].split(":")[0] for ln in (r.stdout or "").splitlines()
                        if ": FAIL" in ln})
        ok = r.returncode == 1 and broke
        failed += not ok
        detail = (f"{len(broke)} arm(s) red: {', '.join(broke[:3])}" if ok else
                  f"rc {r.returncode}, nothing broke: {(r.stdout or r.stderr).strip()[-110:]}")
        print(f"  mutate {label} (must break {must_break}): {'ok' if ok else 'FAIL'} — {detail}")
    return failed


# --------------------------------------------------------------------------- main
def default_csv() -> Path:
    env = os.environ.get(RESULTS_ENV)
    return Path(env) if env else ROOT / RESULTS_DEFAULT


def show(csv_path: Path, exc_path: Path) -> int:
    """The derived facts, so no count in any prose has to be remembered (CONVENTIONS §2)."""
    norm, src = station_match()
    me = os.uname().nodename if hasattr(os, "uname") else ""
    print(f"results csv : {csv_path}"
          f"{' (from $' + RESULTS_ENV + ')' if os.environ.get(RESULTS_ENV) else ' (the writer default)'}"
          f" — {'present' if csv_path.is_file() else 'ABSENT, which is NOT JUDGED, not a pass'}")
    print(f"station     : {STATION} — normalised by {src}; this box is {me!r} -> "
          f"{'THE STATION' if is_on_station(me, norm) else 'not the station'}")
    print(f"rule-0 mark : a stamp whose model half names provider {SPARK_PROVIDER!r} "
          f"(<host>{STAMP_SEP}{SPARK_PROVIDER}/<model>)")
    book, book_notes = read_exceptions(exc_path)
    for note in book_notes:
        print(f"NOTE: {note}")
    print(f"exceptions  : {exc_path} — {len(book)} line(s)")
    try:
        parsed = read_legs(csv_path)
    except Boundary as exc:
        print(f"legs        : NOT JUDGED — {exc}")
        return 0
    v = judge(parsed.legs, book, parsed.keyable, norm)
    kinds = {}
    for f in v.findings:
        kinds[f.kind] = kinds.get(f.kind, 0) + 1
    print(f"legs        : {len(parsed.legs)} read — on station {v.on_station}, named debt {len(v.named)}, "
          f"findings {len(v.findings)} {sorted(kinds.items()) if kinds else ''}, "
          f"Rule 0 NOT JUDGED {v.rule0_unjudged}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", help=f"the results CSV to judge (default: $RESULTS_CSV, else "
                                 f"{RESULTS_DEFAULT} — the file run-scenario.sh appends to)")
    ap.add_argument("--exceptions", help=f"the exception ledger (default: {EXCEPTIONS_DEFAULT})")
    ap.add_argument("--show", action="store_true", help="print the derived facts and the counts, no verdict")
    ap.add_argument("--self-test", action="store_true", help="prove every arm on fixtures, then mutate")
    args = ap.parse_args()
    if args.self_test:
        print("check_bench_provenance.py --self-test")
        return self_test()
    csv_path = Path(args.csv) if args.csv else default_csv()
    exc_path = Path(args.exceptions) if args.exceptions else ROOT / EXCEPTIONS_DEFAULT
    try:
        if args.show:
            return show(csv_path, exc_path)
        norm, src = station_match()
        parsed = read_legs(csv_path)
        book, notes = read_exceptions(exc_path)
        v = judge(parsed.legs, book, parsed.keyable, norm)
        v.notes += notes
        return report(parsed, v, csv_path, exc_path, book, src)
    except Boundary as exc:
        print(f"NOT JUDGED: {exc} — a run that could not read a leg's stamp does not get to call it clean")
        return 2


if __name__ == "__main__":
    sys.exit(main())
