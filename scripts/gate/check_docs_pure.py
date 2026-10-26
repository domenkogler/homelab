#!/usr/bin/env python3
"""check_docs_pure.py — docs state FACTS; commits state what changed (CONVENTIONS §6, §6.4).

> **Role:** state-only lint over the hand-authored docs corpus (`docs/**/*.md`) plus the root
> `README.md`. Read-only, no baseline, no seal, nothing to reseal.
> **Linked from:** `scripts/README.md` (the validation gate), `CONVENTIONS.md` §6 (the rule),
> §6.4 (why the prose half reminds and the id half blocks), §4 (the row→doc write path)

WHY THIS EXISTS. The gates in this family were not built over long files or over formatting: they exist
because the docs, the registry, the runbook and the backlog were **used as a changelog** — preserved
history, dated "as of" narration, session accounts of what was measured, and references to `HD-` rows
that had already been deleted. That text is a second copy of git that nothing re-renders: it goes false
the moment reality moves, and it buries the fact a reader came for. CONVENTIONS §6.4 records the motive;
this file is the machine half over the surface the others never read — `check_registry_prose.py` owns
`scripts/README.md`, `check_runbook_purity.py` owns the runbook, `check_backlog_prose.py` owns `todo.md`
and the briefs, `check_iac_identifiers.py` owns `IaC/`.

TWO SEVERITIES, split on purpose (CONVENTIONS §6.4):

  **HARD — a ticket id whose row is gone** (exit 1). An `HD-<n>` / `KOPS-<n>` token is legal in a doc
  ONLY while its `todo.md` row still exists, because the work is genuinely unfinished and the id is the
  pointer to it. When the row closes it is DELETED (§4(a)), and a doc still naming it is then pointing
  at nothing — the exact "deleted HDs mentioned in docs" shape that started this. So the check DERIVES
  the live id set from the `todo.md` rows on every run and reddens only what dangles. This half stays
  red because it deletes a doc's ability to close itself out quietly: the session that deletes the row
  must sweep the mentions in the same change.

  **WARN — the changelog-shaped sentence** (exit 0, printed). A past-tense evidence verb anchored to a
  date (`measured 2026-10-17`, `ruled 2026-10-19`), a diary phrase (`this session`, `as of`, `we found`,
  `previously`, `was renamed to`), or a run-recap token. The date is NOT the finding — the sentence is,
  and the token is only the tell that locates it, which is why the print quotes the whole sentence and
  the fix is to rewrite it as a fact or cut it. Warning-only for the reason in §6.4: prose judgement
  reddening a merge is how a gate gets muted, and a reminder that re-derives itself every run needs no
  ledger and cannot rot into permanent yellow.

STATE DATES ARE NOT FINDINGS. A date that IS state never warns: an expiry, `valid_until`, a renewal, a
firmware build date, and — explicitly, because it matters here — a **`live-verified` / as-built marker,
where the date is the information** ("how fresh is this claim?"). Only a verb anchoring evidence to the
date makes it history.

SCOPE. `walk_docs` is IMPORTED from `check_doc_size.py` (the one hand-authored-docs derivation in the
repo, §2), so the `docs/**/*-generated.md` render views are out of this rule by the same definition that
keeps them out of every other docs rule — their bytes belong to a render, not to a prose judgement
(CONVENTIONS §8.2, §8.5). The root `README.md` is scanned as well: it is the file every session reads
first, and a changelog there is read by everyone.

Run:   python3 scripts/gate/check_docs_pure.py [--verbose] [--show] [--strict] [--self-test]
Exit:  0 = no dangling id (warnings, if any, are printed) · 1 = a dangling ticket id, or --strict and any
       warning · 2 = could not run: `todo.md` or `docs/` missing, or a walk below the corpus floor — a
       checker that cannot see the rows cannot tell live ids from dead ones, and must not print OK.
Stdlib only; no vault, no network, no host.
"""
from __future__ import annotations

import argparse
import importlib.util
import re
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root, script_path  # noqa: E402

ROOT = _hl_root(__file__)
TODO = "todo.md"
ROOT_README = "README.md"
FENCE_RE = re.compile(r"^[ \t]*(?:```|~~~)")

# The grammar is IMPORTED, never re-typed: these are the lists `check_backlog_prose.py` already holds
# (the closed event-verb set behind a date, and the diary phrases) and `corpus_diff.py`'s token shape.
# A rule spelled twice is the CONVENTIONS §2 defect and would show up as two gates disagreeing.
def _peer(name: str):
    path = script_path(name, __file__)
    spec = importlib.util.spec_from_file_location(name[:-3] + "_for_docs_pure", path)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
        return mod
    except Exception as exc:                        # a sibling that will not load is not a grammar
        raise RuntimeError("cannot load the shared narrative grammar from %s (%s)"
                           % (name, exc)) from None


try:
    _backlog = _peer("check_backlog_prose.py")
    _corpus = _peer("corpus_diff.py")
    VERB_DATE_RE = _backlog.VERB_DATE_RE
    PHRASE_RE = _backlog.PHRASE_RE
    EVIDENCE_RE = _backlog.EVIDENCE_RE
    TOKEN_RE = _corpus.ID
    IDSH_RE = _corpus.IDSH
except Exception as exc:                            # pragma: no cover - a boundary, never a fallback
    print("CANNOT RUN: %s" % exc, file=sys.stderr)
    raise SystemExit(2)

# Supersession language: state about a thing that no longer exists (CONVENTIONS §6 — git keeps those).
SUPERSEDED_RE = re.compile(
    r"\b(previously|used to be|no longer exists|was renamed to|moved out of|replaced by [A-Z]|"
    r"retired in favour of|superseded by)\b", re.I)
NARRATIVE_RE = re.compile(PHRASE_RE.pattern + r"|(?:" + SUPERSEDED_RE.pattern + r")", re.I)
# A date the line's own text names as state. Class A of check_iac_identifiers.py / the STATE_DATE set of
# corpus_diff.py, widened to name the Markdown facts this corpus carries — and deliberately NARROW: the
# bare words "since" and "verified" are prose, not state keys (347 lines carry one of them), and an
# exemption that swallows a third of the corpus is not an exemption, it is blindness. The live-verified /
# as-built marker IS named, because there the date is the information (ruled 2026-10-26).
STATE_DATE_RE = re.compile(
    r"\b(valid_until|valid_from|not_after|expires?|expiry|renewal|renews?|renewed|due_by|deadline|"
    r"live[-\s]verified|as[-\s]built|read\s+back|firmware\s+dated|last\s+live\s+check)\b", re.I)
DATE_RE = re.compile(r"\b20\d\d-\d\d-\d\d\b")
ROW_RE = re.compile(r"^\|\s*([A-Z]+-\d+[a-z]?)\s*\|")
FIXTURE_BLOCK = range(9000, 10000)   # next-hd.sh's tool-fixture namespace: never a backlog row
DOC_FLOOR = 40                       # docs the walk must find (a broken root must not print OK)
MAX_PRINTED = 12
TOP_FILES = 10
SENT_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[A-Z`*])")


class ToolError(RuntimeError):
    """The tool could not measure — printed as a refusal (exit 2), never as a verdict."""


# ---------------------------------------------------------------- the derived sets
def load_doc_walk():
    """`walk_docs` — the corpus definition IMPORTED from the size gate (§2: one definition, no second
    list of which docs are hand-authored). The module of record is named here rather than resolved
    against ROOT, because a fixture run moves ROOT and the LOADER is not part of the tree."""
    path = script_path("check_doc_size.py", __file__)
    spec = importlib.util.spec_from_file_location("check_doc_size_for_docs_pure", path)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
        return mod.walk_docs
    except Exception as exc:
        raise ToolError("cannot load the hand-authored-docs derivation from scripts/gate/"
                        "check_doc_size.py (%s) — refusing to invent a second definition of the "
                        "same corpus" % exc) from None


def open_ticket_ids(todo_text: str) -> tuple[set[str], int]:
    """The ids whose registry row still exists, DERIVED from the todo rows on every run (never listed).

    Rows only — the fixture ids `check_todo_done.py` writes into throwaway copies, and the reserved
    9000-block `next-hd.sh` keeps for tool fixtures, are not backlog rows and never are.
    """
    ids = set()
    rows = 0
    for line in todo_text.splitlines():
        m = ROW_RE.match(line)
        if not m:
            continue
        rows += 1
        tok = m.group(1)
        num = re.match(r"[A-Z]+-(\d+)", tok)
        if num and int(num.group(1)) in FIXTURE_BLOCK:
            continue
        ids.add(tok)
    return ids, rows


def sentences(line: str) -> list[str]:
    """A line is a paragraph here: split into sentences so the FINDING is the text to rewrite, not a
    token inside it. Fences and table rows come back whole (one unit)."""
    parts = [s.strip() for s in SENT_SPLIT.split(line.strip())]
    return [s for s in parts if s]


def scan(rel: str, text: str, live: set[str]) -> tuple[list[str], list[str]]:
    """-> (hard findings, warnings) for one file, both naming the sentence rather than the token.

    Three exemption shapes are declared rather than left to be discovered, because a rule that fires on
    a Docker volume ID is a rule that gets ignored (CONVENTIONS §6.4):
      * an id inside an inline-code span, or carrying a path separator, is DATA not a citation — the
        `HD-1080p` precedent from `corpus_diff.py` (a video-quality value in a Sonarr table row);
      * inside a fenced block, prose is code and is judged by no rule here;
      * a TABLE ROW is an as-built catalog: the event-date and supersession rules still read it, but a
        backticked hex ID in a volume table is not a session's run recap.
    """
    hard: list[str] = []
    warn: list[str] = []
    fenced = False
    for i, line in enumerate(text.splitlines(), start=1):
        if FENCE_RE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        unit = " ".join(sentences(line)) or line.strip()
        if not unit:
            continue
        in_row = line.strip().startswith("|")
        gone = sorted({tok for pos, tok in _spans_with_tokens(line)
                       if tok not in live and not _inside_code(line, pos)
                       and "/" not in line[max(0, pos - 3):pos + len(tok) + 3]})
        for tok in gone:
            hard.append(f"dangling-id  {rel}:{i} {tok} — its todo.md row is gone: rewrite the sentence "
                        f"as a fact or cut it (CONVENTIONS §6): {unit[:160]}")
        if STATE_DATE_RE.search(line):
            continue          # the line names its own date as state — an expiry, a renewal, a verify
        m = VERB_DATE_RE.search(line)
        if m:
            warn.append(f"event-date   {rel}:{i} '{m.group(0)}' — a past-tense verb anchored to a date "
                        f"is a changelog sentence: state the fact, git keeps the event "
                        f"(CONVENTIONS §6): {unit[:160]}")
            continue
        m = NARRATIVE_RE.search(line)
        if m:
            warn.append(f"narrative    {rel}:{i} '{m.group(0)}' — a diary or supersession phrase in a "
                        f"state doc: rewrite as a fact or cut it (CONVENTIONS §6): {unit[:160]}")
            continue
        m = EVIDENCE_RE.search(line)
        if m and not in_row:
            warn.append(f"run-recap    {rel}:{i} '{m.group(0)}' — the recap of a run that already "
                        f"happened belongs to the commit (CONVENTIONS §6): {unit[:160]}")
    return hard, warn


def _spans_with_tokens(line: str) -> list[tuple[int, str]]:
    """(offset, id-shape) for the line. The SHAPE pattern is `corpus_diff.py`'s, so a value that only
    LOOKS like an id is recognised here as the same case that gate already names (§2, one grammar)."""
    return [(m.start(), m.group(0)) for m in IDSH_RE.finditer(line)]


def _inside_code(line: str, pos: int) -> bool:
    """True when `pos` sits inside a backticked span — code font is data (`HD-1080p`, a volume ID, a
    commit hash), not a citation of a backlog row."""
    return line.count("`", 0, pos) % 2 == 1


def files(root: Path) -> list[tuple[str, Path]]:
    walk_docs = load_doc_walk()
    out = [(rel, root / rel) for rel in walk_docs(root)]
    readme = root / ROOT_README
    if readme.is_file():
        out.append((ROOT_README, readme))
    return out


def report(pairs: list[tuple[str, Path]], live: set[str], todo_rows: int, verbose: bool = False,
           show: bool = False) -> tuple[int, int, int]:
    """Print the verdict block. -> (rc, n_hard, n_warn)."""
    hard: list[str] = []
    warn: list[str] = []
    per_file: dict[str, int] = {}
    unreadable = 0
    for rel, path in pairs:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            unreadable += 1
            continue
        h, w = scan(rel, text, live)
        hard += h
        warn += w
        per_file[rel] = len(h) + len(w)
    if show:
        print("docs prose: %d file(s), %d todo row(s) as the live-id basis, %d dangling, %d warning(s)"
              % (len(pairs), todo_rows, len(hard), len(warn)))
        return (1 if hard else 0), len(hard), len(warn)

    print("check_docs_pure — corpus %d file(s), live-id basis derived from %d todo.md row(s)"
          % (len(pairs), todo_rows))
    if unreadable:
        print("  %d file(s) unreadable and NOT judged" % unreadable)
    if hard:
        print("  FAIL dangling ticket ids: %d — a row was deleted while the doc kept naming it "
              "(CONVENTIONS §6):" % len(hard))
        shown = hard if verbose else hard[:MAX_PRINTED]
        for f in shown:
            print("    - %s" % f)
        if len(shown) < len(hard):
            print("    ... %d more (--verbose for all)" % (len(hard) - len(shown)))
    else:
        print("  ok   no dangling ticket id — every HD/KOPS mention names a row that still exists")
    if warn:
        print("  REMINDER prose-shape warnings: %d — non-blocking (CONVENTIONS §6.4). The finding is the "
              "SENTENCE: rewrite it as a fact or cut it; deleting a date and keeping the story clears "
              "nothing." % len(warn))
        ranked = sorted(per_file.items(), key=lambda kv: (-kv[1], kv[0]))[:TOP_FILES]
        for rel, n in ranked:
            if n:
                print("    %4d  %s" % (n, rel))
        if not verbose:
            print("    (top %d of %d files with warnings; --verbose lists every line)"
                  % (TOP_FILES, sum(1 for _, n in per_file.items() if n)))
        else:
            for f in warn:
                print("    - %s" % f)
    else:
        print("  ok   no changelog-shaped sentences found by the shared narrative grammar")
    return (1 if hard else 0), len(hard), len(warn)


# ---------------------------------------------------------------- self-test
def _fixture(tmp: Path, docs: dict, todo_rows: list[str], readme: str = "") -> Path:
    for rel, text in docs.items():
        p = tmp / "docs" / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
    (tmp / TODO).write_text(
        "| ID | D | Exec | P | Item |\n|----|---|------|---|------|\n"
        + "".join("| %s | 2 | AI | 1 | **x** — y ⏳ |\n" % r for r in todo_rows), encoding="utf-8")
    if readme:
        (tmp / ROOT_README).write_text(readme, encoding="utf-8")
    return tmp


def _run(tmp: Path) -> tuple[int, int, int, str]:
    """Run the report over one fixture. Verbose ON PURPOSE: the printed text is the evidence, and a
    canary that only checks a file COUNT could be satisfied by a warning that named the wrong thing."""
    old = globals()["ROOT"]
    globals()["ROOT"] = tmp
    try:
        live, rows = open_ticket_ids((tmp / TODO).read_text(encoding="utf-8"))
        buf = StringIO()
        with redirect_stdout(buf):
            rc, nhard, nwarn = report(files(tmp), live, rows, verbose=True)
        return rc, nhard, nwarn, buf.getvalue()
    finally:
        globals()["ROOT"] = old


def self_test() -> int:
    bad = 0
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        # NOTE: one `todo.md` per fixture — every case makes its own, because the live-id basis is what
        # the id half judges against, and a shared rows file would make an earlier case's ids dangle.

        def require(cond: bool, msg: str) -> None:
            nonlocal bad
            if cond:
                print("  ok   %s" % msg)
            else:
                print("  FAIL %s" % msg)
                bad += 1

        # 1 a dangling id reddens
        t = _fixture(tmp / "a", {"x.md": "The gap was closed (HD-900).\n"}, ["HD-10"])
        rc, h, w, out = _run(t)
        require(rc == 1 and h == 1 and "HD-900" in out, "an id with no todo row reddens")

        # 2 an id whose row is still open is legal — the work is genuinely unfinished
        t = _fixture(tmp / "b", {"x.md": "Pending live verify (HD-42).\n"}, ["HD-42"])
        rc, h, w, out = _run(t)
        require(rc == 0 and h == 0, "an id whose row still exists passes (in-progress exception)")

        # 3 the fixture namespace is never a live id, even if a row-like line carries it
        t = _fixture(tmp / "c", {"x.md": "cites HD-9001.\n"}, ["HD-9001"])
        rc, h, w, out = _run(t)
        require(rc == 1 and h == 1, "a reserved-block fixture id is never treated as a live row")

        # 4 a KOPS token with no row anywhere reddens
        t = _fixture(tmp / "d", {"x.md": "See KOPS-007.\n"}, ["HD-1"])
        rc, h, w, out = _run(t)
        require(rc == 1 and h == 1, "a KOPS id with no row reddens")

        # 5 a state date does NOT warn, even beside an evidence verb
        t = _fixture(tmp / "e", {"x.md": "Live-verified 2026-10-17 on all five hosts.\n"}, ["HD-1"])
        rc, h, w, out = _run(t)
        require(rc == 0 and w == 0, "a live-verified date is state and prints nothing")

        # 6 an event verb + date DOES warn, and the run stays green
        t = _fixture(tmp / "f", {"x.md": "Measured 2026-10-17 that the timer never fires.\n"}, ["HD-1"])
        rc, h, w, out = _run(t)
        require(rc == 0 and w == 1 and "Measured 2026-10-17" in out,
                "a dated event sentence warns without reddening")

        # 7 a narrative phrase warns, undated
        t = _fixture(tmp / "g", {"x.md": "This session moved the section out of the runbook.\n"}, ["HD-1"])
        rc, h, w, out = _run(t)
        require(rc == 0 and w == 1 and "This session" in out, "a diary phrase warns")

        # 8 supersession prose warns
        t = _fixture(tmp / "h", {"x.md": "The pin previously lived in group_vars.\n"}, ["HD-1"])
        rc, h, w, out = _run(t)
        require(rc == 0 and w == 1, "supersession prose warns")

        # 9 a render view is invisible to the rule
        t = _fixture(tmp / "i", {"x-generated.md": "Measured 2026-10-17 by the render.\nHD-777 cites.\n"},
                     ["HD-1"])
        rc, h, w, out = _run(t)
        require(rc == 0 and h == 0 and w == 0, "a generated render view is judged by no prose rule")

        # 10 a fenced example is not prose
        t = _fixture(tmp / "j", {"x.md": "```bash\n# this session measured 2026-10-17 (HD-99)\n```\n"},
                     ["HD-1"])
        rc, h, w, out = _run(t)
        require(rc == 0 and h == 0 and w == 0, "a fenced block is not judged as prose")

        # 11 the root README is in scope
        t = _fixture(tmp / "k", {"x.md": "clean\n"}, ["HD-1"], readme="This session added the DNS section.\n")
        rc, h, w, out = _run(t)
        require(rc == 0 and w == 1 and "README.md:1" in out, "the root README.md is inside the rule")

        # 12 the live basis is derived from the rows, so a re-seal can never launder a dangling id
        t = _fixture(tmp / "l", {"x.md": "cites HD-11.\n"}, ["HD-11"])
        live, rows = open_ticket_ids((t / TODO).read_text(encoding="utf-8"))
        require(rows == 1 and live == {"HD-11"}, "the live-id set is derived from the todo rows each run")

        # 12b a code-font value that only LOOKS like an id is data, not a citation (the HD-1080p
        #     precedent), and a recap token inside a table row is an as-built catalog, not a diary.
        t = _fixture(tmp / "l2", {"x.md": "| Sonarr | `HD-1080p` | ok=1 changed=0 |\n"}, ["HD-1"])
        rc, h, w, out = _run(t)
        require(rc == 0 and h == 0 and w == 0,
                "a code-font HD-shaped value and an in-row recap are not findings")

        # 13 a missing todo.md is a refusal at the driver, never a green over an empty id basis.
        # The fixture needs a corpus ABOVE the floor, or the floor refusal answers before todo.md.
        t = _fixture(tmp / "m", {"d%02d.md" % i: "clean prose.\n" for i in range(45)}, ["HD-1"])
        (t / TODO).unlink()
        old = globals()["ROOT"]
        argv = list(sys.argv)
        globals()["ROOT"] = t
        sys.argv = ["check_docs_pure.py"]
        try:
            buf = StringIO()
            with redirect_stdout(buf):
                rc = main()
            require(rc == 2, "a missing todo.md refuses (rc 2), it does not judge against no rows")
        finally:
            globals()["ROOT"] = old
            sys.argv = argv

        # 14 an empty corpus is a refusal too (require_corpus's SystemExit, not an OK line)
        empty = tmp / "n"
        (empty / "docs").mkdir(parents=True, exist_ok=True)
        globals()["ROOT"] = empty
        argv = list(sys.argv)
        sys.argv = ["check_docs_pure.py"]
        try:
            buf = StringIO()
            err = StringIO()
            with redirect_stdout(buf), redirect_stderr(err):
                rc = main()
            require(rc == 2, "a walk below the corpus floor refuses, it does not print OK")
        except SystemExit as exc:
            require(getattr(exc, "code", 1) == 2, "the corpus floor refuses with rc 2")
        finally:
            globals()["ROOT"] = old
            sys.argv = argv

    print("self-test:", "FAILED" if bad else "OK")
    return 1 if bad else 0


# ---------------------------------------------------------------- driver
def main() -> int:
    ap = argparse.ArgumentParser(
        prog="check_docs_pure.py",
        description="Docs state facts, commits state what changed. A ticket id whose row is gone is a "
                    "finding; changelog-shaped prose is a printed reminder. Read-only, no baseline.",
        epilog="exit 0 clean or warnings-only · 1 dangling id (or --strict + a warning) · 2 could not run")
    ap.add_argument("--verbose", action="store_true", help="print every warning line, not the top files")
    ap.add_argument("--show", action="store_true", help="counts only, no findings")
    ap.add_argument("--strict", action="store_true",
                    help="promote the prose warnings to exit 1 (off by default — CONVENTIONS §6.4)")
    ap.add_argument("--self-test", action="store_true", help="breed each shape and judge its severity")
    args = ap.parse_args()

    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
        except (AttributeError, ValueError):
            pass

    if args.self_test:
        return self_test()
    try:
        pairs = files(ROOT)
    except ToolError as exc:
        print("CANNOT RUN: %s" % exc, file=sys.stderr)
        return 2
    try:
        require_corpus(len(pairs), DOC_FLOOR, "check_docs_pure walked hand-authored docs/**.md")
    except SystemExit as exc:
        print("CANNOT RUN: %s" % exc, file=sys.stderr)
        return 2
    try:
        todo_text = (ROOT / TODO).read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        print("CANNOT RUN: cannot read %s — the live-id basis cannot be derived, and a checker that "
              "cannot tell a live row from a dead one must not print OK (%s)" % (TODO, exc),
              file=sys.stderr)
        return 2
    live, rows = open_ticket_ids(todo_text)
    if not live:
        print("CANNOT RUN: %s yielded no rows at all — the live-id basis is empty, so every id would "
              "read as dangling (a broken walk, not a clean tree)" % TODO, file=sys.stderr)
        return 2
    rc, _h, _w = report(pairs, live, rows, verbose=args.verbose, show=args.show)
    return rc


if __name__ == "__main__":
    sys.exit(main())
