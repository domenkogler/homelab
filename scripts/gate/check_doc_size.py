#!/usr/bin/env python3
"""check_doc_size.py — a hand-authored doc may shrink freely and may not exceed its sealed count (HD-1199).

> **Role:** ratchet over the size of the hand-authored `docs/**/*.md`. Read-only; `--reseal` is the one
> write, and it belongs to the merge station, never to a lane.
> **Linked from:** `scripts/README.md` (the validation gate), `CONVENTIONS.md` §6 (the ratchet lesson),
> §8.5 (no wall clock in a derived file)

WHY THIS EXISTS. Nothing in this repo bounded a doc's length: the only size ceiling was the one on
`prompt.md` (`check_handoff_size.py`). The README tells every session *do not bulk-read the repo*,
which is the instruction a 2 000-line doc contradicts, and the corpus average sits above 300 lines.
A mass split is not the fix — CONVENTIONS §6 forbids cosmetic churn, and a gate that reports dozens
of findings on its first run is a gate that gets muted (§6). So the bound is a RATCHET: today's sizes
are sealed once, every one of them is allowed to stand, and the only direction a doc may move for
free is DOWN.

THE THREE RULES, each with its verdict word:

  GROWTH    a file the seal carries may not exceed its sealed count. Over by one line is a finding.
            Trimming is always free — this is what "a ratchet, never a cap" means: the gate never
            demands a doc be split, and it never reddens a doc for being what it already was.
  NEWDOC    a file the seal does NOT carry must be <= NEW_DOC_CEILING lines, so a doc is born bounded
            instead of being born at 900 lines and sealed there by the next re-seal.
  UNSEALED  an in-scope file the seal omits — the first direction of the seal's two-way check. It
            reddens whether or not the file is small, which is what stops a lane from clearing a
            GROWTH finding by DELETING that file's seal line: the omission is itself the finding.
            Adding a new doc is legitimate, so the fix here is a re-seal at the merge station.
  STALE     a seal line whose file has vanished — the second direction. A line that matches nothing
            is the next site's free pass (`check_doc_headings.py` and `check_handoff_size.py` state
            the same rule for their own ledgers).

SCOPE, and the one class deliberately outside it. The rule reads every hand-authored markdown under
`docs/`, at ANY depth — the set is DERIVED by walking that directory tree, never by a list in this
file. The walk is depth-free on purpose: the one-level glob this gate shipped with left the nested
guides (`docs/manual/**`) outside the seal, where a doc could outgrow any ceiling while the run still
printed a green corpus line. The `docs/**/*-generated.md` render views stay out of the baseline AND
out of the rule: their length is a property of what the IaC renders, so a docs gate must never be able
to redden on a render (CONVENTIONS §8.2, §8.5). That exclusion is enforced from both sides — the walk
skips the suffix at every depth, and a `-generated.md` line IN the baseline is a parse error, because a
sealed render view would be a number this gate can neither re-derive nor clear. A seal path that
escapes `docs/` is a parse error for the same reason: the body names docs inside the corpus, nowhere
else.

`--reseal` rewrites the whole body from the tree and prints what it froze — docs covered, total lines,
the largest file, and the delta against the previous seal with its direction. It is the only write
this script performs and it belongs to the merge station (the handoff seal's discipline). A GROWTH red
at the merge station means a doc GREW: trim the doc. Re-sealing over the growth is how this gate gets
muted, not kept.

`--show-baseline` prints the body a re-seal would write, so no count in this repo is ever quoted from
memory (CONVENTIONS §2 bans typed derived values).

WHAT THIS DOES NOT PROVE, stated rather than left to be discovered:
  * It does not prove any doc is SMALL. It proves the corpus cannot GROW, so splitting stays a human
    judgement about where a doc should be cut.
  * It counts LINES, not bytes or reading time. A doc of 300 very long lines is bounded by the GROWTH
    half alone, exactly like the doc it came from.
  * A rename is a GROWTH-free UNSEALED + STALE pair — both directions name it, and the re-seal books
    it. Renaming a doc is a doc edit, which is the same station's business.
  * `--reseal` freezes whatever the tree says, including an unsealed doc over the ceiling; it prints a
    warning when it does, because freezing is not the same as approving.

Run:   python3 scripts/gate/check_doc_size.py [--verbose] [--show-baseline] [--reseal] [--self-test]
Exit:  0 = every doc inside its seal · 1 = finding(s): a doc that grew, a doc over the new-doc ceiling,
         an in-scope doc the seal omits, or a seal line whose doc is gone · 2 = could not run: no
         baseline, a malformed baseline, or a walk below the corpus floor. A MISSING baseline is rc 2,
         never a silent pass — a gate that cannot see the seal cannot fail either.
Stdlib only; no vault, no network, no host.
"""
from __future__ import annotations

import argparse
import os
import re
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
BASELINE = "scripts/gate/doc_size_baseline.txt"
DOCS_DIR = "docs"
GENERATED_SUFFIX = "-generated.md"
# A doc that has never been sealed starts here. Measured against the corpus, not against a taste: the
# seal already carries docs under this number, so the ceiling only bites a doc written TODAY, and it
# is low enough that a new doc cannot be born at the size of the largest existing one.
NEW_DOC_CEILING = 200
# Floor, not measurement — it sits far below the corpus this walk derives, and the run prints that
# count (§2 is why no number for it is typed here). A walk that yields a handful of docs is a broken
# repo root, and a ratchet measured against a broken walk would freeze a stub baseline — which is
# worse than red, because the next run would be green.
DOC_FLOOR = 40
# `<path><TAB><line count>` and nothing else. Repo-relative, LF, and NESTED paths are legal: the walk
# is depth-free, so the body is one line per doc at any depth under docs/. No timestamp, no absolute
# path, no wall clock anywhere — CONVENTIONS §8.5 is why. Because `[^/\t]+` no longer bounds the path,
# the escape half is guarded on its own by ESCAPE_RE in parse_seal.
SEAL_LINE = re.compile(r"^(docs/[^\t]+\.md)\t(\d+)$")
ESCAPE_RE = re.compile(r"(?:^|/)\.\.(?:/|$)")
CLOCK_RE = re.compile(r"\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}:\d{2}:\d{2}\b|\b\d{9,11}\b")
MAX_PRINTED = 12

DEFAULT_HEADER = """\
# Per-file line counts sealed for scripts/gate/check_doc_size.py — a RATCHET, never a cap: a doc may
# shrink freely and may not exceed the count on its line. Read that script's docstring before editing
# this file; CONVENTIONS.md §8.5 is why no timestamp and no revision appear in it.
#
# One line per in-scope doc, two TAB-separated fields, sorted by path, LF only:
#     <path>TAB<line count>
# In scope: every hand-authored docs/**/*.md at any depth, a set the gate DERIVES by walking that
# directory tree. A docs/**/*-generated.md render view is out of this file and out of the rule — its
# length is an IaC-render property, so a docs gate must not be able to redden on a render (§8.2,
# §8.5). A line carrying that suffix, or a path that escapes docs/, is a parse error, not an exemption.
#
# Both directions fail, and that is the point: an in-scope doc this file omits reddens, and a line
# whose doc is gone reddens. A line that matches nothing is the next site's free pass.
#
# Re-derive the whole body at the merge station, never inside a lane, and never quote a count from
# this file (§2):
#     python3 scripts/gate/check_doc_size.py --reseal
#     python3 scripts/gate/check_doc_size.py --show-baseline
"""


class ToolError(Exception):
    """The gate cannot run. Refuse loudly: a green that measured nothing is worse than no green."""


# ---------------------------------------------------------------- the tree

def walk_docs(root: Path) -> list[str]:
    """The in-scope set, DERIVED from the tree: every hand-authored markdown under docs/, at any depth.

    A `-generated.md` render view is skipped here rather than filtered later, so there is exactly one
    place in this file where the exclusion lives (and its mirror in parse_seal, which refuses the same
    suffix from the other side). The walk is DEPTH-FREE: the one-level glob this gate shipped with
    could not see a nested doc at all, so every guide under `docs/manual/**` sat outside the seal —
    free to grow past any ceiling while the corpus line still read green. A path component beginning
    with `.` is skipped, the same exclusion `check_role_docs.discover_roles` applies to role dirs: a
    hidden directory is not part of the doc corpus."""
    docs = root / DOCS_DIR
    if not docs.is_dir():
        raise ToolError("%s/ is not a directory — the corpus this gate ratchets is gone, and an empty "
                        "walk would read as a clean tree" % DOCS_DIR)
    return sorted(p.relative_to(root).as_posix() for p in docs.rglob("*.md")
                  if p.is_file() and not p.name.endswith(GENERATED_SUFFIX)
                  and not any(part.startswith(".") for part in p.relative_to(root).parts))


def flat_walk_docs(root: Path) -> list[str]:
    """The walk this gate shipped with: `docs/*.md`, one directory level. Kept only so `--self-test`
    can PROVE the widened walk sees a nested doc the old one could not (CONVENTIONS §6: a canary has
    to be able to show the difference it claims). Not used by any verdict."""
    docs = root / DOCS_DIR
    return sorted("%s/%s" % (DOCS_DIR, p.name) for p in docs.glob("*.md")
                  if p.is_file() and not p.name.endswith(GENERATED_SUFFIX))


def measure(root: Path) -> tuple[dict, dict]:
    """({relpath: line count}, {relpath: why it did not read}). One line count per doc, from its bytes.

    An unreadable doc is kept as a FINDING rather than dropped: a file whose bytes cannot be read is a
    file this ratchet cannot hold, and the silently-missing file is the mute-failure class (HD-1118)."""
    counts: dict[str, int] = {}
    unreadable: dict[str, str] = {}
    for rel in walk_docs(root):
        try:
            counts[rel] = len((root / rel).read_text(encoding="utf-8").splitlines())
        except (UnicodeDecodeError, OSError) as exc:
            unreadable[rel] = ("%s: unreadable (%s), so its size is unknown and cannot be ratcheted"
                               % (rel, exc))
    return counts, unreadable


def require_docs(count: int, floor: int) -> int:
    return require_corpus(count, floor, "check_doc_size walked hand-authored %s/**/*.md" % DOCS_DIR)


# ---------------------------------------------------------------- the seal

def parse_seal(text: str) -> tuple[dict, list[str]]:
    """`({path: sealed lines}, [complaints])`. A line that is not `<path><TAB><count>` is a complaint,
    never a silent skip — an exemption that cannot match a doc exempts every future doc at its place.
    """
    seal: dict[str, int] = {}
    bad: list[str] = []
    if "\r" in text:
        bad.append("%s: the file carries CR bytes — the body is LF-only, and a CRLF body makes every "
                   "line unreadable to the parser on one platform and fine on the other" % BASELINE)
    for n, line in enumerate(text.split("\n"), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = SEAL_LINE.match(line)
        if not m:
            bad.append("%s:%d — want `<path><TAB><line count>`, read %r%s"
                       % (BASELINE, n, line[:70], _why_bad(line)))
            continue
        path, num = m.group(1), m.group(2)
        if path.endswith(GENERATED_SUFFIX):
            bad.append("%s:%d — %s is a render view: it is out of this rule entirely, and a sealed "
                       "render view is a number no docs gate can re-derive" % (BASELINE, n, path))
            continue
        if ESCAPE_RE.search(path):
            bad.append("%s:%d — %s walks out of %s/: the body names docs inside the corpus with "
                       "repo-relative paths, and a sealed line pointing elsewhere holds a count no "
                       "walk of this tree will ever produce" % (BASELINE, n, path, DOCS_DIR))
            continue
        if path in seal:
            bad.append("%s:%d — %s is sealed twice, so the two lines disagree about one doc"
                       % (BASELINE, n, path))
            continue
        if not num.isdigit():
            bad.append("%s:%d — the count for %s is not a plain number" % (BASELINE, n, path))
            continue
        seal[path] = int(num)
    return seal, bad


def _why_bad(line: str) -> str:
    """Name the shape a malformed line actually has, so the fix is visible from the finding."""
    low = line.strip().lower()
    if "\t" not in line:
        if " " in line:
            return " — a `<name> <value>` field line does not belong here: this body is one TAB-" \
                   "separated pair per in-scope doc, and a field is where a timestamp or a revision " \
                   "would sneak in (CONVENTIONS §8.5)"
        return " — no TAB, so neither a path nor a count was written"
    if low.startswith(("/", "c:", "\\\\", "..")):
        return " — an absolute or escaping path: the body cites repo-relative paths only"
    path = low.split("\t", 1)[0]
    if ESCAPE_RE.search(path):
        return " — a path that escapes docs/: the body names docs inside the corpus, nowhere else"
    if path.endswith(GENERATED_SUFFIX):
        return " — a render view is out of scope (§8.2, §8.5)"
    return ""


def render_seal(counts: dict) -> str:
    """The body: one `<path><TAB><count>` line per doc, sorted by path. render_seal and parse_seal are
    inverses, which arm (c3) proves rather than asserts."""
    return "".join("%s\t%d\n" % (rel, counts[rel]) for rel in sorted(counts))


def read_seal(path: Path) -> tuple[dict, list[str]]:
    if not path.is_file():
        raise ToolError("%s is missing, so every sealed count is unknown and each pre-existing size "
                        "would read as growth or as unsealed. Re-derive it at the merge station: "
                        "python3 scripts/gate/check_doc_size.py --reseal" % BASELINE)
    # read_bytes + decode, NOT read_text: text mode translates CRLF to \n on a Windows seat, so the
    # CR guard below would be blind on exactly the platform that can introduce the CR (CONVENTIONS §6,
    # "a gate that cannot see the file cannot fail either").
    try:
        text = path.read_bytes().decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ToolError("%s is not UTF-8 (%s)" % (BASELINE, exc)) from None
    seal, bad = parse_seal(text)
    if bad:
        raise ToolError("%s is malformed:\n  %s" % (BASELINE, "\n  ".join(bad)))
    if not seal:
        raise ToolError("%s parses but seals nothing — an empty seal would make every doc in the "
                        "tree read as unsealed, which is not a verdict about the docs" % BASELINE)
    return seal, bad


# ---------------------------------------------------------------- the verdict

def diff(tree: dict, seal: dict, unreadable=()) -> tuple[list, list, list, list]:
    """(growth, unsealed, newdoc-over-ceiling, stale) — the ONE place the verdict is decided.
    `unreadable` paths are excluded from STALE: their doc is present, its bytes just did not read,
    and reporting that as a vanished seal line would send the reader to the wrong file."""
    skip = set(unreadable)
    growth = sorted((rel, seal[rel], tree[rel]) for rel in tree
                    if rel in seal and tree[rel] > seal[rel])
    unsealed = sorted(rel for rel in tree if rel not in seal)
    newdoc = sorted((rel, tree[rel]) for rel in unsealed if tree[rel] > NEW_DOC_CEILING)
    stale = sorted(rel for rel in seal if rel not in tree and rel not in skip)
    return growth, unsealed, newdoc, stale


def summary(counts: dict) -> str:
    """The three numbers this gate was asked to measure and report: how many docs, the total, the
    largest. Derived here, printed always, never typed (CONVENTIONS §2)."""
    if not counts:
        return "0 docs"
    total = sum(counts.values())
    big = max(sorted(counts), key=lambda rel: counts[rel])
    return "%d doc(s), %d line(s) total, largest %s at %d" % (len(counts), total, big, counts[big])


def report(tree: dict, seal: dict, unreadable=(), verbose: bool = False,
           floor: int = DOC_FLOOR) -> int:
    if not tree and not unreadable:
        print("CANNOT RUN: no hand-authored %s/**/*.md were read. Either the walk is broken or this is "
              "not the repo root — and a ratchet measured against nothing would freeze an empty "
              "baseline, which reads green forever (HD-1118 Stage 1)." % DOCS_DIR)
        return 2
    growth, unsealed, newdoc, stale = diff(tree, seal, unreadable)
    print("scope %s/**/*.md hand-authored: %s" % (DOCS_DIR, summary(tree)))
    print("seal  %s: %s; a doc the seal omits must be <= %d lines"
          % (BASELINE, summary(seal), NEW_DOC_CEILING))
    for rel, sealed, now in growth:
        print("FAIL: %s: GROWTH — %d lines, %d over its sealed %d. The ratchet says a doc may shrink "
              "and may not grow: cut this doc or say in the merge why the growth is the outcome, then "
              "re-seal at the merge station — never raise a number here to make the red go away"
              % (rel, now, now - sealed, sealed))
    for rel in sorted(unreadable):
        print("FAIL: %s" % unreadable[rel])
    for rel in unsealed:
        also = (" and it is ALSO over the %d-line new-doc ceiling, which is the finding below" 
                % NEW_DOC_CEILING) if tree[rel] > NEW_DOC_CEILING else ""
        print("FAIL: %s: UNSEALED — %d lines, and the seal carries no line for it%s. The seal IS the "
              "population, so an in-scope doc it omits is an uncatalogued doc; re-derive the whole "
              "body at the merge station (python3 scripts/gate/check_doc_size.py --reseal)."
              % (rel, tree[rel], also))
    for rel, now in newdoc:
        print("FAIL: %s: NEWDOC — a doc the seal does not carry must start at <= %d lines and this one "
              "is %d. Split it or trim it BEFORE it is sealed: re-sealing a doc born over the ceiling "
              "buys the corpus a second oversized file, which is what the ceiling is for"
              % (rel, NEW_DOC_CEILING, now))
    for rel in stale:
        print("FAIL: %s: STALE — the seal carries %d line(s) for a doc that is no longer in the tree. "
              "A sealed line that matches nothing is the next doc's free pass: re-derive the body at "
              "the merge station, do not leave the line standing"
              % (rel, seal[rel]))

    n = len(growth) + len(unreadable) + len(unsealed) + len(newdoc) + len(stale)
    if n:
        print("\n%d finding(s): %d grown, %d unsealed (%d of them over the %d-line new-doc ceiling), "
              "%d stale seal line(s), %d unreadable."
              % (n, len(growth), len(unsealed), len(newdoc), NEW_DOC_CEILING, len(stale),
                 len(unreadable)))
        print("      This gate measures and reports; it does not trim. A red growth finding after a "
              "merge means a doc GREW — the fix is the doc, and `--reseal` belongs to the merge "
              "station.")
        return 1
    if verbose:
        print("  sealed docs: " + ", ".join("%s=%d" % (rel, seal[rel]) for rel in sorted(seal)))
    require_docs(len(tree), floor)
    print("OK: %s — nothing over its seal, nothing unsealed, nothing stale" % summary(tree))
    return 0


# ---------------------------------------------------------------- the flags

def reseal(root: Path, seal_path: Path, floor: int = DOC_FLOOR) -> int:
    """Rewrite the whole body from the tree and print what it froze. The merge station's act after a
    merge (the handoff seal's discipline); a lane never runs it. The header survives — it is the
    explanation, the body is the data.

    `floor` is a parameter only so the self-test can reseal a three-doc fixture tree; every real call
    site uses the corpus floor, because re-sealing from a walk that lost a directory would freeze a
    baseline that quietly un-seals half the corpus."""
    counts, unreadable = measure(root)
    require_docs(len(counts), floor)        # a broken walk must not freeze a stub baseline
    old: dict = {}
    header = DEFAULT_HEADER
    if seal_path.is_file():
        text = seal_path.read_bytes().decode("utf-8", "replace")
        keep = []
        for ln in text.split("\n"):
            if ln.strip() and not ln.lstrip().startswith("#"):
                break
            keep.append(ln)
        header = "\n".join(keep).rstrip("\n") + "\n"
        parsed, bad = parse_seal(text)
        if bad:
            print("NOTE: the old body did not parse (%s) — rewriting it from the tree"
                  % "; ".join(bad), file=sys.stderr)
        else:
            old = parsed
    seal_path.write_text(header.rstrip("\n") + "\n" + render_seal(counts), encoding="utf-8",
                         newline="\n")

    old_total, new_total = sum(old.values()), sum(counts.values())
    direction = ("first seal — no prior body to compare" if not old else
                 "UNCHANGED" if old_total == new_total
                 else "GREW +%d lines" % (new_total - old_total) if new_total > old_total
                 else "TRIMMED -%d lines" % (old_total - new_total))
    print("re-sealed %s" % seal_path)
    print("  tree : %s" % summary(counts))
    print("  seal : %s  (%s)" % (summary(old), direction))
    if old:
        added = sorted(rel for rel in counts if rel not in old)
        dropped = sorted(rel for rel in old if rel not in counts)
        grew = sorted((rel, old[rel], counts[rel]) for rel in counts
                      if rel in old and counts[rel] > old[rel])
        shrank = sorted((rel, old[rel], counts[rel]) for rel in counts
                        if rel in old and counts[rel] < old[rel])
        print("  docs +%d added, -%d gone, %d grew, %d shrank"
              % (len(added), len(dropped), len(grew), len(shrank)))
        for rel in added[:MAX_PRINTED]:
            print("    FREEZE  %s %d lines" % (rel, counts[rel]))
        for rel in dropped[:MAX_PRINTED]:
            print("    DROP    %s (was %d lines)" % (rel, old[rel]))
        for rel, was, now in grew[:MAX_PRINTED]:
            print("    GREW    %s %d -> %d (+%d) — a doc is supposed to SHRINK" % (rel, was, now,
                                                                                   now - was))
        for rel, was, now in shrank[:MAX_PRINTED]:
            print("    SHRANK  %s %d -> %d (-%d) — the direction this ratchet wants" % (rel, was, now,
                                                                                        was - now))
        if len(added) + len(dropped) + len(grew) + len(shrank) > MAX_PRINTED:
            print("    … more docs, same directions")
    if old and direction.startswith("GREW"):
        print("  ⚠ the corpus is BIGGER than its last seal. A red growth finding at the merge station "
              "means a doc GREW — trim the doc. Re-sealing over the growth is how this gate gets "
              "muted, not kept.")
    for rel, now in sorted((rel, n) for rel, n in counts.items()
                           if old and rel not in old and n > NEW_DOC_CEILING)[:MAX_PRINTED]:
        print("  ⚠ freezing %s at %d lines: a doc newly entering the seal is over the %d-line new-doc "
              "ceiling. Sealing it is not the same as approving it." % (rel, now, NEW_DOC_CEILING))
    for rel in sorted(unreadable):
        print("NOTE: %s — it is NOT in the body this run wrote, so the next run will read it as "
              "unsealed" % unreadable[rel])
    return 0


def show_baseline(root: Path, floor: int = DOC_FLOOR) -> int:
    """stdout = the body a re-seal would write, so one redirect reproduces it; the summary goes to
    stderr. The counts are derived here, never remembered (CONVENTIONS §2)."""
    counts, unreadable = measure(root)
    require_docs(len(counts), floor)
    sys.stdout.write("# body scripts/gate/check_doc_size.py --reseal would write, derived from the "
                     "tree at this moment; keep %s's header and replace its body with this\n"
                     % BASELINE)
    sys.stdout.write(render_seal(counts))
    print("--show-baseline: %s; %d line(s) to write" % (summary(counts), len(counts)),
          file=sys.stderr)
    for rel in sorted(unreadable):
        print("NOTE: %s" % unreadable[rel], file=sys.stderr)
    return 0


# ---------------------------------------------------------------- self-test

def _tree(tmp: Path, files: dict) -> Path:
    """A throwaway corpus: `files` is {relpath: line count}. Everything below is a mutation of THIS
    tree plus a seal rendered from it, so each arm is one difference and not a story about two."""
    for rel, n in files.items():
        p = tmp / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("".join("line %d\n" % i for i in range(1, n + 1)), encoding="utf-8")
    return tmp


def _seal(tmp: Path, counts: dict, body: str | None = None) -> Path:
    path = tmp / "baseline.txt"
    path.parent.mkdir(parents=True, exist_ok=True)
    text = body if body is not None else render_seal(counts)
    path.write_text("# fixture seal — not this repo's seal\n" + text, encoding="utf-8", newline="\n")
    return path


def self_test() -> int:
    """Breed each defect in a temp tree and refuse a run that did not catch it. The arms ARE the
    contract: a ratchet that cannot tell smaller from larger is a cap, and a seal that cannot watch its
    own population is a list. Nothing here writes near the real tree, and no arm reaches git, the
    network or a host."""
    fails = 0

    def arm(label: str, ok: bool, detail: str = "") -> None:
        nonlocal fails
        fails += not ok
        print("  arm %-72s %s%s" % (label, "ok" if ok else "FAIL",
                                    (" — " + detail) if (detail and not ok) else ""))

    def run(root: Path, seal: Path, verbose: bool = False, floor: int = 0) -> tuple[int, str]:
        """The whole pipeline on a fixture tree, with the real corpus floor set aside — a fixture is
        three docs, and the floor belongs to the tree (its own arms prove it below)."""
        buf = StringIO()
        try:
            with redirect_stdout(buf):
                counts, unreadable = measure(root)
                return report(counts, read_seal(seal)[0], unreadable, verbose=verbose, floor=floor), \
                    buf.getvalue()
        except ToolError as exc:
            return 2, str(exc)

    base = {"docs/alpha.md": 120, "docs/beta.md": 80, "docs/gamma.md": 3}

    with tempfile.TemporaryDirectory(prefix="check-doc-size-") as td:
        tmp = Path(td)

        # (a) The ratchet itself, from both sides.
        t = _tree(tmp / "a-green", base)
        rc, out = run(t, _seal(tmp / "a-green", base))
        arm("(a) a tree inside its own seal is GREEN, and the green names what it counted",
            rc == 0 and "3 doc(s)" in out and "largest docs/alpha.md at 120" in out,
            "rc %d: %s" % (rc, out[-260:]))
        t = _tree(tmp / "a-grow", dict(base, **{"docs/beta.md": 81}))
        rc, out = run(t, _seal(tmp / "a-grow", base))
        arm("(a) one line OVER a sealed count REDDENS as GROWTH and says by how much",
            rc == 1 and "GROWTH" in out and "docs/beta.md" in out and "1 over its sealed 80" in out,
            "rc %d: %s" % (rc, out[-260:]))
        t = _tree(tmp / "a-shrink", dict(base, **{"docs/alpha.md": 40}))
        rc, out = run(t, _seal(tmp / "a-shrink", base))
        arm("(a) SHRINKING a doc 80 lines past its seal is GREEN — a ratchet, never a cap",
            rc == 0 and "GROWTH" not in out, "rc %d: %s" % (rc, out[-260:]))

        # (b) The new-doc ceiling, and the proof it is not the same check as the seal.
        t = _tree(tmp / "b-over", dict(base, **{"docs/new.md": 201}))
        rc, out = run(t, _seal(tmp / "b-over", base))
        arm("(b) a doc the seal omits at 201 lines REDDENS as NEWDOC naming the ceiling",
            rc == 1 and "NEWDOC" in out and "must start at <= 200 lines" in out
            and "GROWTH" not in out, "rc %d: %s" % (rc, out[-260:]))
        t = _tree(tmp / "b-under", dict(base, **{"docs/new.md": 200}))
        rc, out = run(t, _seal(tmp / "b-under", base))
        arm("(b) the same doc at exactly the ceiling does NOT redden the ceiling rule — it reddens "
            "the seal rule, which is a different fact",
            rc == 1 and "NEWDOC" not in out and "UNSEALED" in out, "rc %d: %s" % (rc, out[-260:]))

        # (c) The seal in both directions — and the laundering case the two directions exist for.
        t = _tree(tmp / "c-omit", base)
        body = "".join("%s\t%d\n" % (rel, n) for rel, n in sorted(base.items()) if rel != "docs/alpha.md")
        rc, out = run(t, _seal(tmp / "c-omit", {}, body=body))
        arm("(c) an in-scope doc the seal omits REDDENS as UNSEALED even though it is small — deleting "
            "a seal line cannot launder growth",
            rc == 1 and "UNSEALED" in out and "docs/alpha.md" in out and "GROWTH" not in out,
            "rc %d: %s" % (rc, out[-260:]))
        t = _tree(tmp / "c-gone", {k: v for k, v in base.items() if k != "docs/gamma.md"})
        rc, out = run(t, _seal(tmp / "c-gone", base))
        arm("(c) a seal line whose doc vanished REDDENS as STALE — a line matching nothing is a free pass",
            rc == 1 and "STALE" in out and "docs/gamma.md" in out, "rc %d: %s" % (rc, out[-260:]))
        t = _tree(tmp / "c-reseal", dict(base, **{"docs/new.md": 40}))
        rc, out = run(t, _seal(tmp / "c-reseal", base))
        buf = StringIO()
        with redirect_stdout(buf):
            rc_seal = reseal(t, tmp / "c-reseal" / "baseline.txt", floor=0)
        rc2, out2 = run(t, tmp / "c-reseal" / "baseline.txt", verbose=True)
        arm("(c) --reseal rc 0 clears both directions and the tree then reads GREEN",
            rc == 1 and rc_seal == 0 and rc2 == 0,
            "run %d, seal %d, rerun %d: %s" % (rc, rc_seal, rc2, out2[-200:]))
        arm("(c) reseal printed the coverage it froze, the total and the largest, plus the delta",
            "tree : 4 doc(s)" in buf.getvalue() and "largest docs/alpha.md at 120" in buf.getvalue()
            and "FREEZE  docs/new.md 40 lines" in buf.getvalue(), buf.getvalue()[:300])
        kept = (tmp / "c-reseal" / "baseline.txt").read_text(encoding="utf-8")
        arm("(c) reseal kept the seal's own header and rewrote only the body",
            kept.startswith("# fixture seal") and "docs/new.md\t40" in kept, kept[:120])
        again = StringIO()
        with redirect_stdout(again):
            reseal(t, tmp / "c-reseal" / "baseline.txt", floor=0)
        arm("(c) resealing an unchanged tree says UNCHANGED", "UNCHANGED" in again.getvalue(),
            again.getvalue()[:200])
        shown = StringIO()
        with redirect_stdout(shown):
            show_baseline(t, floor=0)
        reparsed, bad2 = parse_seal(shown.getvalue())
        arm("(c) --show-baseline stdout parses back to exactly the tree's counts",
            not bad2 and reparsed == measure(t)[0], str(bad2))
        arm("(c) the bytes of the DOCS never change under --reseal — the only write is the seal",
            all((t / rel).read_text(encoding="utf-8") == "".join(
                "line %d\n" % i for i in range(1, n + 1)) for rel, n in
                dict(base, **{"docs/new.md": 40}).items()))

        # (d) The render views: out of the walk, out of the seal, out of the rule.
        gen = dict(base)
        t = _tree(tmp / "d-gen", gen)
        (t / "docs" / "huge-generated.md").write_text("".join("x\n" for _ in range(5000)),
                                                      encoding="utf-8")
        rc, out = run(t, _seal(tmp / "d-gen", gen))
        arm("(d) a 5 000-line `*-generated.md` render view is invisible to the walk, the seal and the "
            "ceiling — a docs gate cannot redden on a render",
            rc == 0 and "-generated" not in out and "3 doc(s)" in out, "rc %d: %s" % (rc, out[-260:]))
        rc, out = run(t, _seal(tmp / "d-line", {},
                               body="docs/huge-generated.md\t5000\n"))
        arm("(d) a `-generated.md` line IN the seal is a parse error (rc 2), not an exemption",
            rc == 2 and "render view" in out, "rc %d: %s" % (rc, out[:200]))
        t_ok = _tree(tmp / "d-ok", base)
        for label, body in (
                ("an absolute path", "/home/you/homelab/docs/alpha.md\t120\n"),
                ("a path that escapes docs/", "docs/../outside.md\t120\n"),
                ("a field line, where a timestamp would live", "sealed_at 0123456789abcdef\n"),
                ("a bare word", "everything-is-fine\n"),
                ("a non-numeric count", "docs/alpha.md\tmany\n"),
                ("a duplicated doc", "docs/alpha.md\t120\ndocs/alpha.md\t119\n")):
            rc, out = run(t_ok, _seal(tmp / ("d-bad" + label[:6]), {}, body=body))
            arm("(d) a seal line with %s is refused at rc 2, never silently skipped" % label,
                rc == 2, "rc %d: %s" % (rc, out[:140]))
        crlf = _seal(tmp / "d-crlf", base)   # makes the directory; the bytes below replace the body
        crlf.write_bytes(b"# fixture\n" + render_seal(base).replace("\n", "\r\n").encode())
        rc, out = run(_tree(tmp / "d-crlf-tree", base), crlf)
        arm("(d) a CRLF seal body is refused — a body is LF-only so the parse is one answer per line",
            rc == 2 and "CR bytes" in out, "rc %d: %s" % (rc, out[:140]))

        # (e) Fail-closed: every shape in which this gate must refuse instead of printing OK.
        rc, out = run(_tree(tmp / "e-none", base), tmp / "e-none" / "absent.txt")
        arm("(e) a missing baseline exits 2 — never a silent pass, never a green", rc == 2,
            "rc %d: %s" % (rc, out[:160]))
        empty = tmp / "e-empty"
        empty.mkdir()
        (empty / "docs").mkdir()
        rc, out = run(empty, _seal(tmp / "e-empty", base))
        arm("(e) an EMPTY corpus is refused at rc 2 — a ratchet over nothing would freeze an empty "
            "baseline and read green forever", rc == 2 and "CANNOT RUN" in out,
            "rc %d: %s" % (rc, out[:160]))
        for n, expect_refusal in ((DOC_FLOOR, True), (DOC_FLOOR + 1, False)):
            refused = None
            try:
                require_docs(n, DOC_FLOOR)
            except SystemExit as exc:
                refused = str(exc)
            if expect_refusal and refused:
                arm("(e) the corpus floor bites at exactly %d docs" % n, True)
            elif expect_refusal:
                arm("(e) the corpus floor bites at exactly %d docs" % n, False,
                    "a walk of %d docs passed" % n)
            else:
                arm("(e) a healthy walk of %d docs passes the floor" % n, not refused, refused or "")
        measured_real = len(walk_docs(ROOT))
        arm("(e) the REAL tree clears the floor (%d in-scope docs against floor %d)"
            % (measured_real, DOC_FLOOR), measured_real > DOC_FLOOR,
            "raise DOC_FLOOR with the corpus")
        real_text = (ROOT / BASELINE).read_bytes().decode("utf-8", "replace") \
            if (ROOT / BASELINE).is_file() else ""
        real_seal, real_bad = parse_seal(real_text)
        body_lines = [ln for ln in real_text.split("\n")
                      if ln.strip() and not ln.lstrip().startswith("#")]
        in_tree = set(walk_docs(ROOT))
        arm("(e) this repo's baseline exists, parses, is sorted by path, and carries no line for a doc "
            "this tree no longer holds", bool(real_text) and not real_bad
            and body_lines == sorted(body_lines) and set(real_seal) <= in_tree,
            "missing/malformed: %s; stale line(s): %s"
            % (str(real_bad)[:120], sorted(set(real_seal) - in_tree)[:6]))
        # Completeness is NOT asserted against the live corpus here: a seal the merge station has not
        # re-derived yet is a transient package state, and a red that is legitimate-but-temporary is the
        # noise that gets a gate muted (and on this seat a red run loses its summary block to HD-1135's
        # gawk bug, so nobody could read why). The rule keeps its teeth where it can be bred in BOTH
        # directions — arms (c) and (f) above: an in-scope doc with no seal line reddens UNSEALED, its
        # twin with a seal line stays green. What is left is a derived NOTE, so the lag is never hidden.
        lag = sorted(in_tree - set(real_seal))
        if lag:
            print("  note  this checkout's seal LAGS the walk: %d in-scope doc(s) carry no seal line yet"
                  " — %s%s. The solo run prints the same finding as UNSEALED; it is a package state, not"
                  " a blind checker. The merge station re-derives the body"
                  " (python3 scripts/gate/check_doc_size.py --reseal); a lane never does."
                  % (len(lag), ", ".join(lag[:4]), ", …" if len(lag) > 4 else ""))
        arm("(e) this repo's baseline carries no wall clock, no CR and no absolute path anywhere in it",
            bool(real_text) and not CLOCK_RE.search(real_text) and "\r" not in real_text
            and "\t/" not in real_text, "a clock, a CR or an absolute path leaked in")

        # (f) The WIDENED walk: a NESTED doc is part of the corpus. Each red here is paired with the
        # walk this gate shipped with, so the arm proves the difference it claims (CONVENTIONS §6) —
        # the one-level glob could not see `docs/sub/` at all, so nothing below could ever redden on a
        # nested doc, which is the gap HD-1201 was minted for.
        nest = dict(base, **{"docs/sub/x.md": 201})
        t = _tree(tmp / "f-nest", nest)
        rc, out = run(t, _seal(tmp / "f-nest", base))
        arm("(f) a NESTED doc the seal omits at 201 lines REDDENS as UNSEALED + NEWDOC, and the corpus "
            "line counts 4 docs where the flat walk counted 3",
            rc == 1 and "docs/sub/x.md" in out and "UNSEALED" in out and "NEWDOC" in out
            and "4 doc(s)" in out, "rc %d: %s" % (rc, out[-300:]))
        t = _tree(tmp / "f-nest-ok", nest)
        rc, out = run(t, _seal(tmp / "f-nest-ok", nest))
        arm("(f) its twin — the SAME nested doc with a seal line, at the same 201 lines, is GREEN: it is "
            "the seal's population that reddens, not the ceiling",
            rc == 0 and "4 doc(s)" in out, "rc %d: %s" % (rc, out[-240:]))
        arm("(f) and that red cannot come from the old shape: the nested path is in the widened walk "
            "and in no listing of the flat one — the same tree, walked two ways",
            "docs/sub/x.md" in walk_docs(t) and "docs/sub/x.md" not in flat_walk_docs(t)
            and len(flat_walk_docs(t)) == 3,
            "wide %s / flat %s" % (walk_docs(t), flat_walk_docs(t)))
        nest_seal = dict(nest, **{"docs/sub/x.md": 120})
        t = _tree(tmp / "f-grow", dict(nest_seal, **{"docs/sub/x.md": 121}))
        rc, out = run(t, _seal(tmp / "f-grow", nest_seal))
        arm("(f) a NESTED doc one line OVER its sealed count REDDENS as GROWTH — the ratchet holds at "
            "depth, it was never a rule about one directory",
            rc == 1 and "GROWTH" in out and "docs/sub/x.md" in out and "1 over its sealed 120" in out,
            "rc %d: %s" % (rc, out[-300:]))
        t = _tree(tmp / "f-gen", nest_seal)
        (t / "docs" / "sub" / "view-generated.md").write_text("".join("x\n" for _ in range(5000)),
                                                              encoding="utf-8")
        rc, out = run(t, _seal(tmp / "f-gen", nest_seal))
        arm("(f) a NESTED `*-generated.md` render view stays invisible — widening the walk did not widen "
            "the exclusion's depth (§8.2, §8.5)",
            rc == 0 and "-generated" not in out and "4 doc(s)" in out, "rc %d: %s" % (rc, out[-300:]))
        t = _tree(tmp / "f-reseal", nest)
        f_seal = _seal(tmp / "f-reseal", base)
        with redirect_stdout(StringIO()):
            rc_seal = reseal(t, f_seal, floor=0)
        f_body = [ln for ln in f_seal.read_text(encoding="utf-8").split("\n")
                  if ln.strip() and not ln.lstrip().startswith("#")]
        rc2, out2 = run(t, f_seal)
        arm("(f) --reseal books the nested doc on an ordinary `<path><TAB><count>` line, sorted with the "
            "rest, and the tree then reads GREEN: the seal's SHAPE is unchanged, only its population",
            rc_seal == 0 and rc2 == 0 and "docs/sub/x.md\t201" in f_body and f_body == sorted(f_body),
            "seal %d, rerun %d: %s" % (rc_seal, rc2, f_body))
        wide, flat_here = walk_docs(ROOT), flat_walk_docs(ROOT)
        arm("(f) on THIS checkout the widened walk yields strictly more hand-authored docs than the "
            "flat glob did — the nested guides are inside the seal's scope now",
            len(wide) > len(flat_here), "wide %d, flat %d" % (len(wide), len(flat_here)))

    if fails:
        print("FAIL: self-test — %d arm(s) did not behave" % fails)
        return 1
    print("OK: self-test — the ratchet tells growth from shrink with the shrink half proved, the "
          "new-doc ceiling is proved separate from the seal rule, the seal fails in both directions "
          "so deleting a line launders nothing, the render views are invisible to all three rules and "
          "refused from inside the seal, a malformed or missing seal and an empty corpus all refuse to "
          "print OK, a NESTED doc is proved in scope against the flat walk that could not see it, and "
          "--reseal writes the seal and nothing else")
    return 0


# ---------------------------------------------------------------- driver

def main() -> int:
    ap = argparse.ArgumentParser(
        prog="check_doc_size.py",
        description="Ratchet the hand-authored docs/**/*.md against their sealed line counts: shrink is "
                    "free, growth is a finding, a doc the seal omits is a finding, and a seal line "
                    "whose doc is gone is a finding. Read-only; --reseal writes only the baseline.",
        epilog="exit 0 inside the seal · 1 finding(s) · 2 could not run")
    ap.add_argument("--verbose", action="store_true", help="list every sealed doc with its count")
    ap.add_argument("--show-baseline", action="store_true",
                    help="print the body a re-seal would write (derived, never remembered)")
    ap.add_argument("--reseal", action="store_true",
                    help="rewrite the baseline from the tree and print the delta — the merge "
                         "station's act, run after a merge, never inside a lane")
    ap.add_argument("--self-test", action="store_true", help="breed each defect and require the red")
    args = ap.parse_args()

    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
        except (AttributeError, ValueError):
            pass

    if args.self_test:
        return self_test()
    try:
        if args.show_baseline:
            return show_baseline(ROOT)
        if args.reseal:
            return reseal(ROOT, ROOT / BASELINE)
        counts, unreadable = measure(ROOT)
        seal, _ = read_seal(ROOT / BASELINE)
        return report(counts, seal, unreadable, verbose=args.verbose)
    except ToolError as exc:
        print("CANNOT RUN: %s" % exc, file=sys.stderr)
        return 2
    except SystemExit:
        raise           # the corpus floor's own refusal — a boundary, printed by repo_root
    except OSError as exc:
        print("CANNOT RUN: %s" % exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
