#!/usr/bin/env python3
"""Lint: the script registry states FACTS about tools, not history (CONVENTIONS §6, state-only docs).

`scripts/README.md` is the map an agent reads to decide WHICH tool to run. It had become a
changelog: ticket ids, dates and "we did X, it measured Y" narrative filling the `What it does`
column, so the fact a row exists to carry was buried under the story of the ticket that added it.
The same sweep already happened twice elsewhere and this file is what both of them skipped:
`check_iac_identifiers.py` for `IaC/` and `check_runbook_purity.py` for the runbook. `docs/*.md`
are near-clean under CONVENTIONS §6; the registry was covered by nothing, which is how it grew.

The rule is the state-only rule, applied to a tool map:
  * a row says what the script DOES NOW — its flags, its verdicts and exit contract, its declared
    limits — and where the durable detail lives;
  * it does not say when that happened, which ticket made it happen, or what a session measured
    while finding it out. Git keeps all three.

Checks (every floor is 0 — a registry that reports 41 findings on its first run is a registry
that gets muted, the width-rule lesson):
  1. ticket-id          — no `HD-<n>` token in the registry. An id names a queue entry that will
                          be deleted when the work closes; the fact outlives it.
  2. iso-date           — no `20YY-MM-DD`, unless the line's own text names the date as STATE
                          (an expiry, a renewal, a validity bound). That exemption is class A of
                          `check_iac_identifiers.py`, kept identical so the two do not disagree.
  3. narrative          — history tenses and diary phrases (`this session`, `found live`,
                          `renumbered from`, …) that turn a description into a record.
  4. status-glyph       — no ✅/✔/❌. Those are completion claims; a map has no status.
                          (⚠/⛔/⏳ stay — a caution, a refusal and a pending wiring are state.)
  5. column-count       — every row of a table carries exactly its header's cells. This is STRICTER
                          than `check_md_tables.py`, which is wider-only repo-wide (equality fires
                          41 times there). Here equality is affordable, and the missing cell it
                          finds is the row's OWNING SPEC — the link that row was pointing at for
                          the durable half.
  6. pipe-in-code       — no unescaped `|` inside inline code on a table line: GFM cuts the cell
                          there, the cell count stays legal, and the width rule cannot see it.
  7. duplicate-paragraph— the same passage twice inside one row (a botched edit leaves both copies,
                          and no identity rule sees it because the first cell is still unique).
  8. pointer-value      — the OWNING SPEC cell is RESOLVED, not counted. Rule 5 proves a row carries a
                          last cell; a last cell aimed at the wrong document is a clean row under a
                          cell count, which is the HD-1157 shape: presence checked, content unread.
                          The link is resolved with the resolution `check_doc_path_refs.py`
                          implements, so the two gates cannot disagree about where a link lands.

Run:   python3 scripts/gate/check_registry_prose.py [--show] [--self-test]
Exit:  0 = clean, 1 = findings (or a corpus too small to trust — a walk that found nothing is a
       broken root, not a clean file).  Wired into `validate-all.sh`.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root  # noqa: E402

ROOT = _hl_root(__file__)
TARGETS = [ROOT / "scripts" / "README.md"]
# The path resolution is OWNED by check_doc_path_refs.py. Importing it, rather than re-implementing a
# link resolver here, is what keeps this rule and that gate from growing two ideas of where a link
# lands (HD-1157: "with the same resolution check_doc_path_refs.py already implements").
sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_doc_path_refs as path_refs  # noqa: E402

TICKET_RE = re.compile(r"\bHD-\d+[a-z]?\b")
DATE_RE = re.compile(r"\b20\d\d-\d\d-\d\d\b")
# Exemption class A (same shape as check_iac_identifiers.py): the date IS the state, and the line
# says so. A date that no line names as state is history.
STATE_DATE_RE = re.compile(r"\b(valid_until|not_after|expires?|expiry|renewal|renews)\b", re.I)
NARRATIVE_RE = re.compile(
    r"\b(this session|as executed|live lesson|live fix|found live|close-out|dogfooded|"
    r"renumbered from|re-?minted|first run found|first proven|session #\d+|"
    r"\bwas (?:copy-?pasted|renamed|replaced|superseded) by)\b", re.I)
STATUS_GLYPHS = "✅✔❌"
# Row length under which "the same passage twice" cannot be told from a repeated column value.
DUP_WINDOW = 160
DUP_STRIDE = 80
# Floors, not targets (CONVENTIONS §6, the ratchet lesson): registry rows the walk must find.
ROW_FLOOR = 80
# A fixture row needs its own header, or the column-count rule has nothing to compare it to.
ROW_HEAD = "| Script | What it does | Owning spec |\n|---|---|---|\n"

LINK_CELL_RE = re.compile(r"^\|\s*\[")
SEP_RE = re.compile(r"^\|[\s:|-]+\|?\s*$")
# A link inside one table cell — the Owning-spec pointer rule 8 reads.
CELL_LINK_RE = re.compile(r"\[[^\]]*\]\(<?([^)>\s]+)>?\)")


def cells(line: str) -> list[str]:
    """Split a markdown table row on UNESCAPED pipes (the same rule check_md_tables.py uses)."""
    return re.split(r"(?<!\\)\|", line.strip().strip("|"))


def owns_pointer(cell: str, origin: str, exists) -> tuple[str, str]:
    """('', '') when every link in the cell lands; otherwise (target, where it resolved).
    LINKS ONLY: a bare path mention in prose is `check_doc_path_refs.py`'s jurisdiction, and the
    exemption list is that module's too (glob, placeholder, URL, frozen archive), so a shape it
    declares benign is benign here. A cell carrying no link carries no pointer to read — rule 5 owns
    the missing-cell half."""
    for target in CELL_LINK_RE.findall(cell):
        t = target.split("#")[0]
        if not t or not path_refs.usable(t):
            continue
        exempt, _why = path_refs.is_exempt(t, origin)
        if exempt:
            continue
        resolved = path_refs.resolve(origin, "link", t)
        if not exists(resolved):
            return t, resolved
    return "", ""


def scan(text: str, origin: Path | None = None, exists=None) -> tuple[list[str], int, int, int]:
    """Return (findings, registry_rows, exempt_date_sites, pointer_sites). `exists` is the filesystem
    probe, injectable so the self-test can breed a mis-aimed pointer without touching the tree."""
    if exists is None:
        exists = lambda p: (ROOT / p).exists() or (ROOT / p).is_dir()  # noqa: E731
    out: list[str] = []
    where = f"{origin}:" if origin else ""
    lines = text.splitlines()

    fence, open_fence = [], False
    for ln in lines:
        if ln.strip().startswith("```"):
            fence.append(open_fence)
            open_fence = not open_fence
        else:
            fence.append(open_fence)

    rows = 0
    exempt = 0
    pointers = 0
    header_cols = 0          # cells in the header of the table currently being read
    seen_dup: set[int] = set()
    # The origin is what a link is resolved AGAINST: `scripts/README.md`, so `../docs/x.md` lands in
    # docs/ the way the reader's browser would put it.
    origin_rel = str(origin).replace(os.sep, "/") if origin else "scripts/README.md"

    for i, raw in enumerate(lines, start=1):
        stripped = raw.strip()
        if not stripped:
            header_cols = 0
            continue
        if SEP_RE.match(stripped) and stripped.startswith("|"):
            header_cols = len(cells(stripped))
            continue
        is_row = stripped.startswith("|")
        if not is_row:
            header_cols = 0
        if LINK_CELL_RE.match(stripped):
            rows += 1
        if fence[i - 1]:
            continue

        tag = f"{where}{i}"

        for tok in TICKET_RE.findall(raw):
            out.append(f"ticket-id    {tag} {tok} — a queue id in a tool map: {stripped[:70]}")

        for dte in DATE_RE.findall(raw):
            if STATE_DATE_RE.search(raw):
                exempt += 1
            else:
                out.append(f"iso-date     {tag} {dte} — name the owning doc, not the date: "
                           f"{stripped[:70]}")

        m = NARRATIVE_RE.search(raw)
        if m:
            out.append(f"narrative    {tag} “{m.group(0)}” — the commit records what happened: "
                       f"{stripped[:70]}")

        glyphs = [g for g in STATUS_GLYPHS if g in raw]
        if glyphs:
            out.append(f"status-glyph {tag} {''.join(sorted(set(glyphs)))} — a completion claim "
                       f"in a map: {stripped[:70]}")

        if is_row and header_cols and len(cells(stripped)) != header_cols:
            out.append(f"column-count {tag} row has {len(cells(stripped))} cells, its header has "
                       f"{header_cols} — an Owning-spec cell dropped: {stripped[:60]}")

        if is_row:
            for m2 in re.finditer(r"`[^`\n]*`", stripped):
                if "|" in m2.group(0) and "\\|" not in m2.group(0):
                    out.append(f"pipe-in-code {tag} `{m2.group(0)[:40]}` — GFM cuts the cell, the "
                               f"width rule stays green")

        if is_row and len(stripped) > 2 * DUP_WINDOW and i not in seen_dup:
            for pos in range(0, len(stripped) - DUP_WINDOW, DUP_STRIDE):
                if stripped.count(stripped[pos:pos + DUP_WINDOW]) > 1:
                    out.append(f"dup-paragraph {tag} the same {DUP_WINDOW}-char passage twice in "
                               f"one row (first copy at offset {pos})")
                    seen_dup.add(i)
                    break

        # Rule 8. `header_cols` is only set once the separator row has been seen, so this never reads
        # a header cell as an owning spec.
        if is_row and header_cols >= 2:
            row_cells = cells(stripped)
            bad, resolved = owns_pointer(row_cells[-1], origin_rel, exists)
            if bad:
                out.append(f"pointer-value  {tag} the Owning-spec link resolves to {resolved!r}, "
                           f"which is not in the tree — a filled cell is not a right cell: "
                           f"{stripped[:60]}")
            elif CELL_LINK_RE.search(row_cells[-1]):
                pointers += 1

    return out, rows, exempt, pointers


def self_test() -> int:
    """Breed each rule and require it to be caught; require each exemption to stay quiet; and
    require an empty corpus to fail loud — the failure this tool exists to prevent is a checker
    that walks nothing and prints OK."""
    # The tree rule 8 resolves against. Links in a fixture are relative to scripts/README.md, so
    # `../docs/real.md` lands on docs/real.md — the same resolution the real run uses, with the disk
    # replaced so the arm tests the resolver and not this checkout.
    tree = {"docs/real.md", "scripts/gate/x.py"}
    exists = lambda p: p in tree  # noqa: E731
    cases = [
        ("ticket-id", "| [`x.py`](gate/x.py) | **Does a thing (HD-9)** — fact. | `doc.md` |", 1, []),
        ("iso-date", "| [`x.py`](gate/x.py) | **Fact** — added 2026-01-02. | `doc.md` |", 1, []),
        ("iso-date exempt", "| [`x.py`](gate/x.py) | **Fact** — the pin expires 2027-01-02. | `doc.md` |",
         0, ["iso-date"]),
        ("narrative", "| [`x.py`](gate/x.py) | **Fact** — this session found the bug. | `doc.md` |", 1, []),
        ("status-glyph", "| [`x.py`](gate/x.py) | ✅ **Fact** done. | `doc.md` |", 1, []),
        ("column-count", "| [`x.py`](gate/x.py) | **Fact** — carries no owning spec |", 1, []),
        ("pipe-in-code", "| [`x.py`](gate/x.py) | **Fact** — counts `A|B` here | `d.md` |\n"
                         "|---|---|---|", 1, []),
        ("dup-paragraph", "| [`x.py`](gate/x.py) | **Fact** — " + ("a long factual passage " * 14)
         + ("a long factual passage " * 14) + " | `doc.md` |", 1, []),
        # HD-1157: the owning-spec cell is FILLED and aimed at a document that is not there. Every
        # cell count is legal, so only a pointer-value read can see it.
        ("pointer-value", "| [`x.py`](gate/x.py) | **Fact** — reads the pin, prints a verdict. "
         "| [spec](../docs/gone.md) |", 1, []),
        ("pointer-value exempt", "| [`x.py`](gate/x.py) | **Fact** — reads the pin, prints a "
         "verdict. | [spec](../docs/real.md) |", 0, ["ticket-id", "iso-date", "narrative",
                                                    "status-glyph", "column-count",
                                                    "pipe-in-code", "dup-paragraph",
                                                    "pointer-value"]),
        ("pointer exempt shapes", "| [`x.py`](gate/x.py) | **Fact** — reads the pin. "
         "| [glob](../docs/*.md) · [ext](https://e.com/x.md) |", 0,
         ["ticket-id", "iso-date", "narrative", "status-glyph", "column-count", "pipe-in-code",
          "dup-paragraph", "pointer-value"]),
        ("clean control", "| [`x.py`](gate/x.py) | **Fact** — reads the pin, prints a verdict, "
         "refuses without one. | `doc.md` |", 0, ["ticket-id", "iso-date", "narrative",
                                                  "status-glyph", "column-count", "pipe-in-code",
                                                  "dup-paragraph"]),
    ]
    bad = 0
    for name, text, want, muted in cases:
        findings, rows, exempt, pointers = scan(ROW_HEAD + text, None, exists)
        kinds = {f.split()[0] for f in findings}
        if want == 0:
            if findings:
                print(f"  FAIL {name}: clean fixture produced {sorted(kinds)}")
                bad += 1
            continue
        if not (kinds - set(muted)):
            print(f"  FAIL {name}: canary NOT caught (found {sorted(kinds)})")
            bad += 1
    # the empty-corpus arm: a checker that lost its target must not be able to say OK
    findings, rows, exempt, pointers = scan("", None, exists)
    if rows:
        print("  FAIL empty-corpus: a walk of nothing counted rows")
        bad += 1
    try:
        require_corpus(rows, 0, "registry rows")
        print("  FAIL empty-corpus: the walk of nothing passed the corpus floor")
        bad += 1
    except SystemExit:
        print("  ok   an empty corpus fails loud")
    print("self-test:", "FAILED" if bad else "OK")
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--show", action="store_true", help="counts only, no verdict")
    args = ap.parse_args()
    if args.self_test:
        return self_test()

    findings: list[str] = []
    rows = 0
    exempt = 0
    pointers = 0
    for target in TARGETS:
        if not target.exists():
            print(f"FAIL: {target} not found — the registry the gate exists to guard is missing")
            return 1
        f, r, e, p = scan(target.read_text(encoding="utf-8"), target.relative_to(ROOT))
        findings += f
        rows += r
        exempt += e
        pointers += p
    require_corpus(rows, ROW_FLOOR, "registry rows")

    if args.show:
        print(f"registry: {rows} linked rows, {exempt} state-date exempt site(s), "
              f"{pointers} resolved owning-spec pointer(s), {len(findings)} finding(s)")
        return 0

    if findings:
        print(f"FAIL: {len(findings)} registry-prose finding(s) — the map must say what the tool "
              f"does, not what a ticket did:")
        for f in findings:
            print(f"  - {f}")
        return 1
    print(f"OK: the registry is facts-only — {rows} linked rows, no ticket ids, no dated "
          f"narrative, every row carries its owning spec and that spec resolves "
          f"({pointers} pointer(s) read, {exempt} state-date exempt site(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
