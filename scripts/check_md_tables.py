#!/usr/bin/env python3
r"""Lint: no markdown table row may be WIDER than its own header (HD-417).

Two self-inflicted misses on 2026-09-21, both passing every other gate:

  * a dropped newline merged two `todo.md` registry rows into one — one row of 9 cells
    where the header has 5, so the second row's identity silently disappeared; and
  * a description that quoted a pipe-delimited pattern widened a 3-cell row to 12, which
    GitHub renders as garbage.

Both are the same physical fact: **a row with more cells than the table's header**. A row
that WIDENS is always a bug — either a stray unescaped `|` or a swallowed newline — because
GFM pads missing trailing cells but never invents extra ones.

Why wider-only, and not "cell count must equal the header" (measured 2026-09-25 over the
545 table blocks in this repo): a row NARROWER than its header is legal markdown and there
were ~14 of them lying around (deliberate 2-cell rows inside a 3-column §A decision-record
table, struck-through PARKED rows that dropped their last column). Asserting equality would
have made the first run print 41 findings in 12 files, and a gate that prints 41 findings
gets muted inside a week — the HD-417 lesson, restated in its own row. Wider-only prints
the ~11 lines that are actually broken.

The escape convention is `\|` inside a cell, **including inside code spans**: GFM splits
table cells before inline parsing, so `` `a|b` `` still cuts the cell. That is what bit
`scripts/README.md` — the row describing the merge-marker gate quoted `|||||||` in a code
span and cut itself into 9 cells.

Scope: tracked `*.md`, minus `reports/**`, `docs/assets/**` and `brainstorming/**` — RAW EVIDENCE
and archived design material. Concretely the exclusions cover 2 of the 13 findings on the first run:
`brainstorming/obsolete/**/testing-checklist.md` quotes RouterOS `/ip route print where
dst-address=…|…` filters, which are archived vendor syntax, not a table this repo maintains.
(session transcripts, probe dumps, audit outputs). They are the record of what a tool
printed, and a record that gets "fixed" stops being evidence. Same rule `check_doc_ips.py`
follows for other classes of edit.

Run:   python3 scripts/check_md_tables.py            (repo-wide)
       python3 scripts/check_md_tables.py path …     (specific files)
       python3 scripts/check_md_tables.py --self-test
Exit:  0 = clean, 1 = findings. Wired into `scripts/validate-all.sh`.

## Second rule (2026-10-06): a LINKED row may not be keyed twice in one table

`scripts/README.md` shipped the `install-pi-wsl.sh` row TWICE (l.109 and l.113) and every gate stayed
green: `check_merge_markers.py` sees only conflict markers, `check_todo_done.py`'s HD-485 duplicate-id
rule is `todo.md`-only, and this file's width rule compares a row to its OWN HEADER, never a row to
another row. A dispatcher index that lists one tool twice is how the next reader picks the wrong half
of them, which is exactly the HD-489 "a tool no index reaches does not exist" failure seen from the
other side.

Why LINKED keys only, measured before writing the rule: keying on "first cell repeated in one table"
fired **58 times** across the tree — `docs/network-vlans.md` legitimately repeats `Home (10)` for
per-subnet rows, `docs/observability.md` repeats `Exporter`, `prompt.md` repeats `**3**` as a priority
column. A rule that prints 58 findings gets muted in a week; that is HD-417's own lesson, restated.
Keying on a first cell that IS a markdown link (`[`x`](y)`, optionally a `+`-joined pair of links) is
**0 findings across the 176 tracked files** at rest — because in this repo a link in column 1 means
"this row IS that file", which is an identity, not a column value. It catches the real pair (proved
against `HEAD~1:scripts/README.md`, lines 109/113) and stays silent on the 58. `--self-test` asserts
BOTH halves: a duplicated linked row must be caught, and a repeated PLAIN first cell (`ok`) plus the
same link in two DIFFERENT tables must stay green — so the narrowness cannot drift back into an
assertion-shaped mess, and the per-table scope cannot drift into a per-file one.
"""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Raw evidence: never edited to satisfy a formatting gate.
EXCLUDE = ("reports/", "docs/assets/", "brainstorming/", "node_modules/", ".pi/")
SEP_RE = re.compile(r"^\s*\|?(?:\s*:?-{2,}:?\s*\|)+\s*$")
# First cell that IS an identity rather than a value: a markdown link, or two links joined by `+`
# (the `laptop-llm.py + profiles.yml` dispatcher shape). Deliberately narrow — see the docstring:
# the loose form ("any repeated first cell") prints 58 findings here and would be muted.
LINK_KEY_RE = re.compile(r"^(?:\[[^\[\]]*\]\([^()]*\)\s*(?:\+\s*)?)+$")


def split_cells(line: str) -> list[str]:
    """Split a table row on UNESCAPED pipes. `\\|` is cell content, not a separator."""
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|") and not s.endswith("\\|"):
        s = s[:-1]
    cells: list[str] = []
    cur: list[str] = []
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == "\\" and i + 1 < len(s) and s[i + 1] == "|":
            cur.append("|")
            i += 2
            continue
        if ch == "|":
            cells.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(ch)
        i += 1
    cells.append("".join(cur))
    return cells


def ncells(line: str) -> int:
    return len(split_cells(line))


def tables(lines: list[str]):
    """Yield (header_lineno, header_cells, [(lineno, line), …]) for every GFM table block."""
    i = 0
    n = len(lines)
    while i < n:
        if (lines[i].lstrip().startswith("|")
                and i + 1 < n and SEP_RE.match(lines[i + 1])):
            header = lines[i]
            body: list[tuple[int, str]] = []
            j = i + 2
            while j < n and lines[j].lstrip().startswith("|"):
                body.append((j + 1, lines[j]))
                j += 1
            # HD-417's own blind spot, found 2026-09-27. The body run above stops at the first
            # line that does not start with `|` — so a row that was SOFT-WRAPPED across lines
            # ends the table as far as this scanner is concerned, and every row below it stops
            # being checked while the gate prints GREEN. Measured cost: one wrapped row in
            # todo-table.md hid a wide row four rows beneath it for the whole life of both; it
            # only surfaced when an unrelated row deletion moved the boundary. So collect the
            # lines that broke the run: if any of them ENDS with `|`, the table did not really
            # end — a row was wrapped — and that is reported instead of being silently skipped.
            tail: list[tuple[int, str]] = []
            k = j
            while k < n and lines[k].strip() and not lines[k].lstrip().startswith("|"):
                tail.append((k + 1, lines[k]))
                k += 1
            yield i + 1, ncells(header), ncells(lines[i + 1]), body, tail
            i = j
        else:
            i += 1


def tracked_md() -> list[str]:
    out = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z", "*.md"],
                         capture_output=True, text=True, check=True).stdout
    files = []
    for f in out.split("\0"):
        if f and not f.startswith(EXCLUDE):
            files.append(f)
    return files


def scan(files: list[str], root: Path) -> list[str]:
    findings: list[str] = []
    for rel in files:
        p = root / rel
        if not p.is_file():
            continue
        try:
            lines = p.read_text(encoding="utf-8").split("\n")
        except (UnicodeDecodeError, OSError):
            continue
        for hline, hcells, scells, body, tail in tables(lines):
            if scells != hcells:
                findings.append(f"{rel}:{hline + 1}: separator row has {scells} cells, "
                                f"header has {hcells} — the table is half-written")
            for lineno, line in body:
                c = ncells(line)
                if c > hcells:
                    snippet = line.strip()[:100]
                    findings.append(
                        f"{rel}:{lineno}: row has {c} cells, header (line {hline}) has {hcells} — "
                        f"escape the stray pipe(s) as \\| or the newline was swallowed: {snippet}")
            for lineno, line in tail:
                if line.rstrip().endswith("|"):
                    findings.append(
                        f"{rel}:{lineno}: a table row is WRAPPED across lines here. That ends the "
                        f"table for this scanner, which silently UN-CHECKS every row below it — "
                        f"join the row back onto one line: {line.strip()[:100]}")
                    break
            # One keyed row per table (2026-10-06): a first cell that is a link declares the row's
            # identity, so the same link twice in one table means the index lists one thing twice.
            keyed: dict[str, int] = {}
            for lineno, line in body:
                cells = split_cells(line)
                if not cells:
                    continue
                key = cells[0].strip()
                if not LINK_KEY_RE.match(key):
                    continue
                if key in keyed:
                    findings.append(
                        f"{rel}:{lineno}: duplicates the row at line {keyed[key]} of this table "
                        f"(same key {key[:70]}). A dispatcher table that lists one target twice is "
                        f"how the next reader picks the wrong row — merge them into one row "
                        f"(keep the superset, the row with more owning-spec links) and delete the "
                        f"other; per-table scope, so the same link in ANOTHER table is fine.")
                else:
                    keyed[key] = lineno
    return findings


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return self_test()
    files = [a for a in sys.argv[1:] if not a.startswith("-")] or tracked_md()
    findings = scan(files, ROOT)
    if findings:
        print(f"FAIL: {len(findings)} markdown table finding(s) (HD-417 width rule + 2026-10-06 "
              f"duplicate-key rule):")
        for f in findings:
            print(f"  {f}")
        print("A row that widens is either a stray `|` inside a cell (escape it as `\\|`, including "
              "inside code spans) or two rows that lost the newline between them. A duplicated key "
              "means the table lists the same target twice.")
        return 1
    print(f"OK: {len(files)} markdown file(s) — no table row is wider than its header, no linked row "
          f"is keyed twice in one table (HD-417 + duplicate-key rule)")
    return 0


FIXTURE = """\
# Fixture

| A | B | C |
|---|---|---|
| ok | row | here |
| short | row |
| `a\\|b` | legal escape | cell |
| `a|b` | stray pipe cuts this cell | third | extra |
| ok | row | here |
| **X** | **one merged row that lost its newline** | y | z | w | v | u |

| H1 | H2 |
|----|-----|
| a | b |

| Bad | Sep |
|-----|
| a | b |

| W1 | W2 |
|----|----|
| ok | row |
| wrapped | this row was soft-
wrapped onto a second line |
| hidden | this row is below the wrap and would otherwise go UNCHECKED | extra |

| Tool | What | Note |
|------|------|------|
| [`dup.md`](dup.md) | listed once | ok |
| [`other.md`](other.md) | a different target | ok |
| [`dup.md`](dup.md) | the same target again | must be caught |

| Tool | What | Note |
|------|------|------|
| [`dup.md`](dup.md) | same link, DIFFERENT table | must stay green |
"""

EXPECTED = 5  # `a|b` row, the swallowed-newline row, the short separator row, the WRAPPED row,
              # and the duplicated linked key (one per fixture table — the repeat in the SECOND
              # table is the negative half and must NOT be counted)


def self_test() -> int:
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="hd417-") as td:
        root = Path(td)
        (root / "fixture.md").write_text(FIXTURE, encoding="utf-8")
        got = scan(["fixture.md"], root)
        if len(got) != EXPECTED:
            failures.append(f"expected {EXPECTED} findings, got {len(got)}:")
            for g in got:
                print(f"    {g}")
        joined = "\n".join(got)
        if "stray" not in joined and "extra" not in joined:
            failures.append("the escaped-pipe fixture row was not caught")
        if "WRAPPED" not in joined:
            failures.append("the soft-wrapped fixture row was not reported — without it, a wrapped row "
                            "still ends the table and silently un-checks the rows below it")
        if "duplicates the row at line" not in joined:
            failures.append("the duplicated linked key was NOT caught — this is the rule that would "
                            "have caught scripts/README.md listing install-pi-wsl.sh twice")
        # Negative half of the SAME rule: `| ok | row | here |` already appears twice above, and the
        # repeated link sits in a SECOND table. Neither may be flagged, or the rule has grown back
        # into the loose "any repeated first cell" form that prints 58 findings repo-wide.
        if joined.count("duplicates the row at line") != 1:
            failures.append("the duplicate-key rule flagged more than the one planted canary — it is "
                            "over-reaching into repeated non-link keys or into other tables")
        clean = "| A | B | C |\n|---|---|---|\n| `a\\|b` | ok | `c\\|d` |\n| fewer | cells |\n"
        (root / "clean.md").write_text(clean, encoding="utf-8")
        if scan(["clean.md"], root):
            failures.append("a clean table with escaped pipes and a short row was flagged — the rule "
                            "must only reject rows WIDER than the header")
        if not unicodedata:  # pragma: no cover
            failures.append("import vanished")
    if failures:
        print("FAIL: check_md_tables.py self-test:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("OK: self-test — a widened row (stray pipe, even inside a code span, or a swallowed newline) "
          "is caught; escaped pipes and short rows are not (HD-417); a linked key duplicated in one "
          "table is caught while a repeated plain key and the same link in another table stay green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
