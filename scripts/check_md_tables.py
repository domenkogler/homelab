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
            yield i + 1, ncells(header), ncells(lines[i + 1]), body
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
        for hline, hcells, scells, body in tables(lines):
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
    return findings


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return self_test()
    files = [a for a in sys.argv[1:] if not a.startswith("-")] or tracked_md()
    findings = scan(files, ROOT)
    if findings:
        print(f"FAIL: {len(findings)} markdown table row(s) wider than their own header (HD-417):")
        for f in findings:
            print(f"  {f}")
        print("A row that widens is either a stray `|` inside a cell (escape it as `\\|`, including "
              "inside code spans) or two rows that lost the newline between them.")
        return 1
    print(f"OK: {len(files)} markdown file(s) — no table row is wider than its header (HD-417)")
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
"""

EXPECTED = 3  # `a|b` row, the swallowed-newline row, the short separator row


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
          "is caught; escaped pipes and short rows are not (HD-417)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
