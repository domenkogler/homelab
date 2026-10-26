#!/usr/bin/env python3
"""check_doc_size.py — a REMINDER about the size of the hand-authored `docs/**/*.md`. Read-only, always green.

> **Role:** size reminder over the hand-authored doc corpus. No write, no baseline, no verdict.
> **Linked from:** `scripts/README.md` (the validation gate), `CONVENTIONS.md` §6.4 (why this reminds and
> does not block), §8.2/§8.5 (the generated views this walk excludes)

WHY THIS EXISTS, AND WHY IT NO LONGER BLOCKS. Nothing in this repo bounded a doc's length until HD-1199
landed a ratchet; the reason the corpus needed bounding at all is recorded in CONVENTIONS §6.4 — the docs
had been used as a changelog, so length was the visible symptom of a prose defect. A line count is only
ever a PROXY for that defect: a long doc made of facts is a placement question (§8.1 — split a catalog out
of an index), never an error. So this half of the rule runs as a REMINDER: it prints, it never reddens
(CONVENTIONS §6.4, ruled 2026-10-26).

THE TRIGGER IS THE DOC, NOT A LEDGER. Growth used to be decided against `gate/doc_size_baseline.txt`, a
per-file seal. That seal is RETIRED, for a reason stated rather than discovered: a warning measured
against a frozen number is a warning nobody can clear without re-writing the number, so it either blocks
(it was never a warning) or rots into permanent yellow (it was never read). A reminder must re-derive its
finding on every run, so the bound here is DERIVED from `NEW_DOC_CEILING` at run time and a doc is flagged
purely by being over it. The free direction is still the only enforced one: trimming always removes a
reminder, and no doc is demanded to split.

WHAT IS IN SCOPE. Every hand-authored markdown under `docs/`, at ANY depth — the set is DERIVED by
walking that tree, never listed here. `walk_docs` is the ONE definition of that corpus in the repo and
`check_role_docs.py` imports it rather than re-spelling it (§2). The `docs/**/*-generated.md` render
views stay out of the walk: their length is a property of what the IaC renders, so a docs reminder must
never have anything to say about a render (CONVENTIONS §8.2, §8.5). A path component beginning with `.`
is not part of the corpus.

Run:   python3 scripts/gate/check_doc_size.py [--verbose] [--show] [--self-test]
Exit:  0 = always, whether or not a doc is over the soft ceiling — this gate has no verdict.
       A refusal to measure (no `docs/` directory, a walk below the corpus floor) is exit 2: a gate that
       cannot see the files cannot remind either, and printing a green corpus line for an empty walk is
       the HD-1118 mute-failure class.
Stdlib only; no vault, no network, no host.
"""
from __future__ import annotations

import argparse
import sys
import tempfile
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root  # noqa: E402

ROOT = _hl_root(__file__)
DOCS_DIR = "docs"
GENERATED_SUFFIX = "-generated.md"
# The born-lean reference for a NEW doc (the same number `check_backlog_prose.py` states for a brief).
NEW_DOC_CEILING = 200
# The soft reminder bound, DERIVED from the born-lean reference rather than sealed per file: twice the
# size a doc is asked to be born at. It is a nudge about placement, so it is deliberately generous — a
# reminder that fires on every doc says nothing about any of them (CONVENTIONS §6.4).
SOFT_FACTOR = 2
# Floor, not measurement — it sits far below the corpus this walk derives, and the run prints that count
# (§2 is why no number for it is typed here). A walk that yields a handful of docs is a broken repo root,
# and a corpus line printed from a broken walk would read as a clean tree.
DOC_FLOOR = 40
MAX_PRINTED = 12
TOP_FILES = 10


class ToolError(RuntimeError):
    """The tool could not measure — printed as a refusal (exit 2), never as a verdict."""


# ---------------------------------------------------------------- the corpus
def walk_docs(root: Path) -> list[str]:
    """The in-scope set, DERIVED from the tree: every hand-authored markdown under docs/, at any depth.

    A `-generated.md` render view is skipped here rather than filtered later, so there is exactly one
    place in this file where the exclusion lives. The walk is DEPTH-FREE: the one-level glob this gate
    shipped with could not see a nested doc at all, so every guide under `docs/manual/**` sat outside
    every rule that reads this walk. A path component beginning with `.` is skipped, the same exclusion
    `check_role_docs.discover_roles` applies to role dirs: a hidden directory is not part of the corpus."""
    docs = root / DOCS_DIR
    if not docs.is_dir():
        raise ToolError("%s/ is not a directory — the doc corpus is gone, and an empty walk would read "
                        "as a clean tree" % DOCS_DIR)
    return sorted(p.relative_to(root).as_posix() for p in docs.rglob("*.md")
                  if p.is_file() and not p.name.endswith(GENERATED_SUFFIX)
                  and not any(part.startswith(".") for part in p.relative_to(root).parts))


def flat_walk_docs(root: Path) -> list[str]:
    """The walk this gate shipped with: `docs/*.md`, one directory level. Kept only so `--self-test`
    can PROVE the widened walk sees a nested doc the old one could not (CONVENTIONS §6: a canary has to
    be able to show the difference it claims). Not used by any verdict."""
    docs = root / DOCS_DIR
    return sorted("%s/%s" % (DOCS_DIR, p.name) for p in docs.glob("*.md")
                  if p.is_file() and not p.name.endswith(GENERATED_SUFFIX))


def measure(root: Path) -> tuple[dict, dict]:
    """({relpath: line count}, {relpath: why it did not read}). One line count per doc, from its bytes."""
    counts: dict[str, int] = {}
    unreadable: dict[str, str] = {}
    for rel in walk_docs(root):
        try:
            counts[rel] = len((root / rel).read_bytes().splitlines())
        except OSError as exc:
            unreadable[rel] = str(exc)
    return counts, unreadable


def soft_ceiling() -> int:
    """The derived bound. A function, so nothing anywhere can hold a copy of the number (§2)."""
    return NEW_DOC_CEILING * SOFT_FACTOR


def summary(counts: dict, unreadable: dict | None = None) -> str:
    unreadable = unreadable or {}
    if not counts:
        return "no docs walked"
    big = max(counts, key=lambda k: counts[k])
    line = ("%d doc(s), %d line(s) total, largest %s at %d; soft reminder ceiling %d "
            "(= %d x the %d-line new-doc reference)"
            % (len(counts), sum(counts.values()), big, counts[big], soft_ceiling(),
               SOFT_FACTOR, NEW_DOC_CEILING))
    if unreadable:
        line += " (%d unreadable)" % len(unreadable)
    return line


def report(counts: dict, unreadable: dict | None = None, verbose: bool = False,
           show: bool = False) -> int:
    """Print the corpus line and the over-ceiling docs. ALWAYS returns 0: this is a reminder."""
    unreadable = unreadable or {}
    over = sorted(((n, rel) for rel, n in counts.items() if n > soft_ceiling()), reverse=True)
    if show:
        print("corpus %s" % summary(counts, unreadable))
        print("over the soft ceiling: %d doc(s) — a reminder about placement (CONVENTIONS §8.1), "
              "not a defect" % len(over))
        return 0
    print("REMINDER check_doc_size — corpus %s" % summary(counts, unreadable))
    if not over:
        print("  nothing over the soft ceiling — no size reminder owed")
        return 0
    print("  %d doc(s) over the soft ceiling — placement, not correctness (CONVENTIONS §6.4, §8.1):"
          % len(over))
    shown = over if verbose else over[:MAX_PRINTED]
    for n, rel in shown:
        print("    %5d  %s" % (n, rel))
    if len(shown) < len(over):
        print("    ... %d more (--verbose for all)" % (len(over) - len(shown)))
    for rel, why in sorted(unreadable.items()):
        print("    unreadable: %s (%s)" % (rel, why))
    print("  non-blocking: a long doc of facts is a split question (§8.1), never a red; trimming is free.")
    return 0


# ---------------------------------------------------------------- self-test
def _tree(tmp: Path, files: dict) -> Path:
    for rel, text in files.items():
        p = tmp / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
    return tmp


def self_test() -> int:
    bad = 0
    ceil = soft_ceiling()
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        # arm 1: an over-ceiling doc PRINTS and still returns 0 — this is a reminder, not a ratchet.
        t = _tree(tmp / "a", {"docs/big.md": "x\n" * (ceil + 5), "docs/small.md": "x\n" * 10})
        counts, unread = measure(t)
        buf = StringIO()
        with redirect_stdout(buf):
            rc = report(counts, unread)
        out = buf.getvalue()
        if rc != 0 or "docs/big.md" not in out or "over the soft ceiling: 0" in out:
            print("  FAIL reminder-half: an over-ceiling doc must print AND return 0 (rc %d)" % rc)
            bad += 1
        else:
            print("  ok   a doc over the ceiling prints and the run stays green")
        # arm 2: a doc at exactly the ceiling prints nothing — the bound is a bound, not a mood.
        t2 = _tree(tmp / "b", {"docs/exact.md": "x\n" * ceil})
        buf = StringIO()
        with redirect_stdout(buf):
            report(*measure(t2))
        if "doc(s) over the soft ceiling" in buf.getvalue():
            print("  FAIL boundary: a doc AT the ceiling printed a reminder")
            bad += 1
        else:
            print("  ok   a doc at the ceiling prints no reminder")
        # arm 3: the ceiling is DERIVED — raising the new-doc reference moves it, nothing is sealed.
        if soft_ceiling() != NEW_DOC_CEILING * SOFT_FACTOR:
            print("  FAIL derived: the ceiling is not a function of NEW_DOC_CEILING")
            bad += 1
        else:
            print("  ok   the ceiling is derived from the new-doc reference, no ledger in sight")
        # arm 4: a render view is invisible to the walk at any depth.
        t4 = _tree(tmp / "c", {"docs/x-generated.md": "x\n" * 5000,
                               "docs/manual/deep/nested.md": "x\n" * (ceil + 1)})
        walked = walk_docs(t4)
        if any(p.endswith(GENERATED_SUFFIX) for p in walked) or "docs/manual/deep/nested.md" not in walked:
            print("  FAIL corpus: walk=%s — a render view was seen or a nested doc was missed" % walked)
            bad += 1
        else:
            print("  ok   a render view is invisible and a nested doc is in the corpus")
        # arm 5: the old flat walk could NOT have seen that nested doc (the canary proves the widening).
        if "docs/manual/deep/nested.md" in flat_walk_docs(t4):
            print("  FAIL canary: flat_walk_docs saw the nested doc — no difference to prove")
            bad += 1
        else:
            print("  ok   the flat walk still misses the nested doc (the widening is proved, not claimed)")
        # arm 6: no baseline exists any more — the file this gate used to be measured against is gone.
        if (ROOT / "scripts" / "gate" / "doc_size_baseline.txt").exists():
            print("  FAIL retired: scripts/gate/doc_size_baseline.txt still exists — a warning must not "
                  "lean on a ledger nobody reseals")
            bad += 1
        else:
            print("  ok   no per-file seal exists — the reminder re-derives everything each run")
        # arm 7: a broken root refuses, it does not print a corpus line.
        empty = tmp / "empty"
        empty.mkdir(parents=True, exist_ok=True)
        try:
            walk_docs(empty)
            print("  FAIL boundary: a missing docs/ walked as an empty corpus")
            bad += 1
        except ToolError:
            print("  ok   a missing docs/ is a refusal, never an empty corpus line")
    print("self-test:", "FAILED" if bad else "OK")
    return 1 if bad else 0


# ---------------------------------------------------------------- driver
def main() -> int:
    ap = argparse.ArgumentParser(
        prog="check_doc_size.py",
        description="REMIND about the size of the hand-authored docs/**/*.md against a derived soft "
                    "ceiling. Read-only, non-blocking: there is no baseline and there is no verdict.",
        epilog="exit 0 always · 2 could not run (no docs/ directory, a walk below the corpus floor)")
    ap.add_argument("--verbose", action="store_true", help="list every over-ceiling doc, not the top few")
    ap.add_argument("--show", action="store_true", help="counts only, no reminder lines")
    ap.add_argument("--self-test", action="store_true", help="prove the reminder half and the boundaries")
    args = ap.parse_args()

    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
        except (AttributeError, ValueError):
            pass

    if args.self_test:
        return self_test()
    try:
        counts, unreadable = measure(ROOT)
    except ToolError as exc:
        print("CANNOT RUN: %s" % exc, file=sys.stderr)
        return 2
    require_corpus(len(counts), DOC_FLOOR, "check_doc_size walked hand-authored %s/**/*.md" % DOCS_DIR)
    return report(counts, unreadable, verbose=args.verbose, show=args.show)


if __name__ == "__main__":
    sys.exit(main())
