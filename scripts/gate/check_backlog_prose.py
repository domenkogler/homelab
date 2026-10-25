#!/usr/bin/env python3
"""check_backlog_prose.py — the work-tracking surfaces stay state-only: retrospective narrative is
counted and ratcheted, and a row may shrink freely and may not grow.

> **Role:** gate over `todo.md` rows and the `prompt-*.md` lane briefs — the surfaces the state-only
> rule (CONVENTIONS §4 post-task housekeeping, §6) governs in prose and no earlier checker read.
> Read-only; `--reseal` is the one write, and it belongs to the merge station, never to a lane.
> **Linked from:** `scripts/README.md` (the validation gate), CONVENTIONS §4/§6 (Post-task housekeeping), §6 (Docs are state-only)

WHY THIS EXISTS. The rules are semantic — "a row is a work queue, not a changelog", "a resolved item
LEAVES the file" — and a token-level cleanup (HD ids, dates) leaves the retrospective PROSE standing,
because stripping tokens out of "measured X on <date>" still leaves "measured X". Every earlier
prose gate covers a surface this prose does not live on: `check_iac_identifiers.py` (IaC comments),
`check_runbook_purity.py` (the runbook), `check_registry_prose.py` (the script registry),
`check_handoff_size.py` (`prompt.md` alone), `check_todo_done.py` (a FULLY-done row, not a half-done
row wearing a changelog). The backlog rows and the briefs were covered by nothing, which is how the
corpus grew to half a megabyte of rows. The state-only sweep trimmed it; this gate is what keeps it
trimmed — a trim without a gate just re-opens the space the next session fills.

THE TWO HALVES, each with its verdict word:

  * NARRATIVE (the prose rules): per (file, rule) finding COUNTS are sealed, and growth is a
    finding. The rules are marker-based, because a marker grammar is checkable and "is this sentence
    a story?" is not:
      - glyph      — ✅/✔ in a row or a brief is a completion claim; the queue and the brief carry
                     ⏳ (owed), ⛔ (refusal) and ⚠ (caution), which are state.
      - verb-date  — `<past-tense verb> <ISO date>` ("measured 2026-09-29", "ruled 2026-10-20"):
                     evidence anchored to when it was taken. A date that IS the state (an expiry, a
                     renewal, a scheduled window) names no verb and stays legal — the grammar targets
                     the verb, not the date, because CONVENTIONS §6 keeps ISO decision dates legal
                     in the queue.
      - phrase     — diary phrases ("this session", "found live", "owner confirmed",
                     "premise corrected", …) that turn a rule into a record.
      - evidence   — execution-recap tokens (`ok=N changed=N`, a bare `failed=N`, `sha256 <hex>`,
                     a backticked commit hash). The command that proves a claim is a clue the row MAY
                     carry; the recap of a run that already happened is not.
    The count ratchet is per (file, rule), not one global number, so improvement cannot be traded
    across surfaces. Its known blind spot, stated rather than hidden: adding one narrative sentence
    while deleting another nets to zero within the same file and rule. The per-row seal below is
    what catches bulk accretion anyway.

  * SIZE (the ratchet half, `check_doc_size.py`'s shape applied where the growth actually happens):
      - ROW    — every todo row is sealed at its byte size; any byte over the seal is a finding;
                 trimming is always free.
      - BRIEF  — every `prompt-*.md` brief is sealed at its line count; growth is a finding.
      - NEWROW — a row the seal does not carry must start at <= NEW_ROW_CEILING bytes: a row is
                 born lean (owed work + clues), not born at 6 KB and sealed there.
      - NEWBRIEF — a brief the seal does not carry must start at <= NEW_BRIEF_CEILING lines.

TWO DELIBERATE DEVIATIONS FROM `check_doc_size.py`, both because the queue's lifecycle is different
from a doc's:
  * STALE is a NOTE here, not a finding. A fully-done row is DELETED in its closing change (§4(a))
    and a brief dies with its lane (O7) — deletion is the lifecycle working, so reddening on it
    would punish the one pattern the rules mandate and mute the gate. The free-pass argument does
    not apply: an HD id is minted once (max+1, never reused), so a stale row line can never match a
    different row; a stale reseal prunes it.
  * An UNSEALED row/brief under its ceiling is a NOTE, not a finding. Rows are minted every session;
    "new row, not yet sealed" must not block a green run. The ceiling is the tooth: a row or brief
    BORN over it is a finding whose fix is the doc, and re-sealing it at the merge station books the
    oversized birth instead of approving it.

`--reseal` rewrites the whole body from the tree and prints what it froze (the doc-size discipline:
merge station, never a lane). `--show-baseline` prints the body a re-seal would write, so no count
is ever quoted from memory (CONVENTIONS §2).

Run:   python3 scripts/gate/check_backlog_prose.py [--show] [--show-baseline] [--reseal] [--self-test]
Exit:  0 = clean · 1 = finding(s) · 2 = could not run (missing/malformed baseline, corpus below its
       floor). Stdlib only; no vault, no network, no host.
"""
from __future__ import annotations

import argparse
import re
import sys
import tempfile
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

# The repo root is FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus as _require_corpus, root as _hl_root  # noqa: E402

ROOT = _hl_root(__file__)
BASELINE = "scripts/gate/backlog_prose_baseline.txt"
TODO = "todo.md"
BRIEF_GLOB = "prompt-*.md"
BRIEF_EXCLUDE = {"prompt.md"}      # the standing handoff: check_handoff_size.py's subject
NEW_ROW_CEILING = 2000             # bytes; the median row is ~1.6 KB, so a lean row passes
NEW_BRIEF_CEILING = 350            # lines; the largest live brief is ~310
ROW_FLOOR = 120                    # rows the walk must find (the registry the gate ratchets)
BRIEF_FLOOR = 8                    # briefs the walk must find
MAX_PRINTED = 12

# ---------------------------------------------------------------- the narrative grammar

GLYPHS = "✅✔"
# The date is legal; the VERB anchoring evidence to it is the history. Deliberately a closed list:
# open-ended past-tense matching would redden state prose ("expires 2027-01-02", "the window is
# owner-set"), and a closed list is auditable.
VERB_DATE_RE = re.compile(
    r"\b(measured|ruled|decided|closed|landed|re-?proved|re-?probed|fixed|applied|deployed|"
    r"published|entered|confirmed|un-?parked|done)\s+20\d\d-\d\d-\d\d\b", re.I)
PHRASE_RE = re.compile(
    r"\b(this session|found live|live lesson|live fix|owner confirmed|premise corrected|"
    r"found while verifying|re-?grounded|as executed|we did|we found|session account|"
    r"has been fixed|was measured|was fixed|is now fixed|measured twice)\b", re.I)
EVIDENCE_RE = re.compile(
    r"\bok=\d+\s+changed=\d+"          # an ansible recap of a run that happened
    r"|\bfailed=\d+\b"                 # a bare recap half
    r"|sha256\s+[0-9a-f]{6,}"          # a content hash pasted as evidence
    r"|`[0-9a-f]{7,40}`",              # a backticked commit hash (`0c391a3`) — the curve name
)                                      # `ed25519` stays legal because it is not backticked hex

RULES = ("glyph", "verb-date", "phrase", "evidence")

# ---------------------------------------------------------------- the baseline

SEAL_LINE = re.compile(r"^(FIND|ROW|BRIEF)\t([^\t]+)\t(\d+)$")
ESCAPE_RE = re.compile(r"(?:^|/)\.\.(?:/|$)")
CLOCK_RE = re.compile(r"\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}:\d{2}:\d{2}\b|\b\d{9,11}\b")

DEFAULT_HEADER = """\
# Sealed state for scripts/gate/check_backlog_prose.py — a RATCHET, never a cap: the work-tracking
# surfaces (todo.md rows, the prompt-*.md briefs) may shrink freely and may not grow. Read that
# script's docstring before editing this file; CONVENTIONS.md §8.5 is why no timestamp appears in it.
#
# Three TAB-separated line kinds, LF only, sorted within each kind:
#     FIND<TAB><file>TAB<rule>TAB<count>     findings-at-rest per (surface, rule): growth refused,
#                                            improvement free; the grammar lives in the checker.
#     ROW<TAB><HD-id>TAB<bytes>              every todo row sealed at its byte size; any byte over
#                                            the seal is a finding, trimming always free.
#     BRIEF<TAB><file>TAB<lines>             every prompt-*.md brief sealed at its line count.
# A row/brief the seal omits must start at or under its ceiling (NEW_ROW_CEILING / NEW_BRIEF_CEILING,
# constants in the checker); a row born over the ceiling is a finding, not a seal candidate.
# A seal line whose row/brief is gone is a NOTE, not a finding — deleting a closed row or a dead
# brief is the lifecycle working (§4(a), O7), and an HD id is never reused, so the line is inert
# until the next re-seal prunes it.
#
# Re-derive the whole body at the merge station, never inside a lane, and never quote a count from
# this file (§2):
#     python3 scripts/gate/check_backlog_prose.py --reseal
#     python3 scripts/gate/check_backlog_prose.py --show-baseline
"""


class ToolError(Exception):
    """The gate cannot run. Refuse loudly: a green that measured nothing is worse than no green."""


# ---------------------------------------------------------------- the tree

def walk_briefs(root: Path) -> list[str]:
    """The brief set, DERIVED by glob, never a list in this file: prompt-*.md minus the standing
    handoff, which is check_handoff_size.py's subject and would otherwise be sealed twice."""
    return sorted(p.name for p in root.glob(BRIEF_GLOB)
                  if p.is_file() and p.name not in BRIEF_EXCLUDE)


def read_row(line: str) -> str | None:
    """A todo row starts `| HD-<n>` and is ONE line — the queue's whole shape."""
    return line if re.match(r"^\| HD-\d+[a-z]? ", line) else None


def measure(root: Path) -> tuple[dict, dict, dict, dict]:
    """(find_counts {(file, rule): n}, rows {id: bytes}, briefs {file: lines}, problems [str]).

    Everything is derived from the tree at this moment; a file that cannot be read is a problem, not
    a silent skip — the silently-missing surface is the mute-failure class."""
    find: dict[tuple, int] = {}
    rows: dict[str, int] = {}
    briefs: dict[str, int] = {}
    problems: list[str] = []
    todo_path = root / TODO
    if not todo_path.is_file():
        problems.append("%s is missing — the queue this gate ratchets is gone" % TODO)
    else:
        text = todo_path.read_text(encoding="utf-8")
        row_lines = [l for l in text.splitlines() if read_row(l)]
        for rule, rx in (("glyph", re.compile("[" + GLYPHS + "]")), ("verb-date", VERB_DATE_RE),
                         ("phrase", PHRASE_RE), ("evidence", EVIDENCE_RE)):
            find[(TODO, rule)] = sum(len(rx.findall(l)) for l in row_lines)
        for l in row_lines:
            rid = re.match(r"^\| (HD-\d+[a-z]?) ", l).group(1)
            rows[rid] = len(l.encode("utf-8"))
        if len(set(rows)) != len(row_lines):
            problems.append("%s carries a duplicated row id — the minting gate owns that class, and "
                            "a duplicated id would seal one size for two rows" % TODO)
    for name in walk_briefs(root):
        try:
            text = (root / name).read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError) as exc:
            problems.append("%s: unreadable (%s)" % (name, exc))
            continue
        for rule, rx in (("glyph", re.compile("[" + GLYPHS + "]")), ("verb-date", VERB_DATE_RE),
                         ("phrase", PHRASE_RE), ("evidence", EVIDENCE_RE)):
            find[(name, rule)] = len(rx.findall(text))
        briefs[name] = len(text.splitlines())
    return find, rows, briefs, problems


def require_corpus(rows: int, briefs: int, floors=(ROW_FLOOR, BRIEF_FLOOR)) -> None:
    _require_corpus(rows, floors[0], "check_backlog_prose walked %s rows" % TODO)
    _require_corpus(briefs, floors[1], "check_backlog_prose walked %s briefs" % BRIEF_GLOB)


# ---------------------------------------------------------------- the seal

def parse_seal(text: str) -> tuple[dict, dict, dict, list[str]]:
    """(find_seal {(file, rule): n}, row_seal {id: bytes}, brief_seal {file: lines}, complaints)."""
    find: dict[tuple, int] = {}
    rows: dict[str, int] = {}
    briefs: dict[str, int] = {}
    bad: list[str] = []
    if "\r" in text:
        bad.append("%s: the file carries CR bytes — the body is LF-only, and a CRLF body makes every "
                   "line unreadable to the parser on one platform and fine on the other" % BASELINE)
    for n, line in enumerate(text.split("\n"), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = SEAL_LINE.match(line)
        if not m:
            bad.append("%s:%d — want `FIND|ROW|BRIEF<TAB><key>TAB<count>`, read %r"
                       % (BASELINE, n, line[:70]))
            continue
        kind, key, num = m.group(1), m.group(2), m.group(3)
        if ESCAPE_RE.search(key):
            bad.append("%s:%d — %r walks out of the repo: the body names in-tree surfaces with "
                       "repo-relative keys" % (BASELINE, n, key))
            continue
        if not num.isdigit():
            bad.append("%s:%d — the count for %r is not a plain number" % (BASELINE, n, key))
            continue
        if kind == "FIND":
            file, _, rule = key.rpartition("/")
            if file not in (TODO,) and not file.startswith("prompt-") or rule not in RULES:
                bad.append("%s:%d — %r: FIND keys are `<file>/<rule>` with rule one of %s"
                           % (BASELINE, n, key, "|".join(RULES)))
                continue
            if (file, rule) in find:
                bad.append("%s:%d — %r is sealed twice" % (BASELINE, n, key))
                continue
            find[(file, rule)] = int(num)
        elif kind == "ROW":
            if not re.fullmatch(r"HD-\d+[a-z]?", key):
                bad.append("%s:%d — %r: ROW keys are bare HD ids" % (BASELINE, n, key))
                continue
            if key in rows:
                bad.append("%s:%d — %s is sealed twice" % (BASELINE, n, key))
                continue
            rows[key] = int(num)
        else:
            if key in briefs:
                bad.append("%s:%d — %s is sealed twice" % (BASELINE, n, key))
                continue
            briefs[key] = int(num)
    return find, rows, briefs, bad


def render_seal(find: dict, rows: dict, briefs: dict) -> str:
    """The body, sorted within each kind; parse_seal is its inverse, which the self-test proves."""
    body = ["FIND\t%s/%s\t%d" % (f, r, find[(f, r)]) for (f, r) in sorted(find)]
    body += ["ROW\t%s\t%d" % (rid, rows[rid]) for rid in sorted(rows)]
    body += ["BRIEF\t%s\t%d" % (b, briefs[b]) for b in sorted(briefs)]
    return "".join(x + "\n" for x in body)


def read_seal(path: Path) -> tuple[dict, dict, dict]:
    if not path.is_file():
        raise ToolError("%s is missing, so every sealed count is unknown and each pre-existing size "
                        "would read as growth. Re-derive it at the merge station: "
                        "python3 scripts/gate/check_backlog_prose.py --reseal" % BASELINE)
    try:
        text = path.read_bytes().decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ToolError("%s is not UTF-8 (%s)" % (BASELINE, exc)) from None
    find, rows, briefs, bad = parse_seal(text)
    if bad:
        raise ToolError("%s is malformed:\n  %s" % (BASELINE, "\n  ".join(bad)))
    if not (find or rows or briefs):
        raise ToolError("%s parses but seals nothing — an empty seal would make every surface read "
                        "as unsealed, which is not a verdict about the prose" % BASELINE)
    return find, rows, briefs


# ---------------------------------------------------------------- the verdict

def diff(find, rows, briefs, f_seal, r_seal, b_seal):
    """(find_growth, row_growth, row_over_ceiling, brief_growth, brief_over_ceiling,
        stale_rows, stale_briefs) — the ONE place the verdict is decided."""
    find_growth = sorted((f, r, f_seal[(f, r)], find[(f, r)]) for (f, r) in find
                         if (f, r) in f_seal and find[(f, r)] > f_seal[(f, r)])
    row_growth = sorted((rid, r_seal[rid], rows[rid]) for rid in rows
                        if rid in r_seal and rows[rid] > r_seal[rid])
    row_new = sorted(rid for rid in rows if rid not in r_seal)
    row_over = [rid for rid in row_new if rows[rid] > NEW_ROW_CEILING]
    brief_growth = sorted((b, b_seal[b], briefs[b]) for b in briefs
                          if b in b_seal and briefs[b] > b_seal[b])
    brief_new = sorted(b for b in briefs if b not in b_seal)
    brief_over = [b for b in brief_new if briefs[b] > NEW_BRIEF_CEILING]
    stale_rows = sorted(rid for rid in r_seal if rid not in rows)
    stale_briefs = sorted(b for b in b_seal if b not in briefs)
    return (find_growth, row_growth, row_over, brief_growth, brief_over,
            stale_rows, stale_briefs)


def report(find, rows, briefs, f_seal, r_seal, b_seal) -> int:
    if not rows and not briefs:
        print("CANNOT RUN: no rows and no briefs were read — a ratchet measured against nothing "
              "would freeze an empty baseline, which reads green forever.")
        return 2
    (find_growth, row_growth, row_over, brief_growth, brief_over,
     stale_rows, stale_briefs) = diff(find, rows, briefs, f_seal, r_seal, b_seal)
    print("scope %s rows (%d, largest %d B) + %d brief(s) (%d lines largest)"
          % (TODO, len(rows), max(rows.values(), default=0), len(briefs),
             max(briefs.values(), default=0)))
    print("seal  %s: %d FIND class(es), %d row(s), %d brief(s); a new row starts at <= %d B, a new "
          "brief at <= %d lines" % (BASELINE, len(f_seal), len(r_seal), len(b_seal),
                                    NEW_ROW_CEILING, NEW_BRIEF_CEILING))
    for f, r, sealed, now in find_growth:
        print("FAIL: %s %s: GROWTH — %d narrative finding(s) against a sealed %d. The queue states "
              "what is missing and how to do it; the story of what already happened goes to the "
              "owning doc and the commit. Trim the prose (do not tune the grammar to make it pass): "
              "%s" % (f, r, now, sealed, "the grammar lives in check_backlog_prose.py"))
    for rid, sealed, now in row_growth:
        print("FAIL: %s: GROWTH — %d B, %d over its sealed %d. A row may shrink (it does, every "
              "time a finding lands in its owning doc) and may not grow: trim it to the owed work "
              "+ the clues, or re-seal at the merge station with the reason"
              % (rid, now, now - sealed, sealed))
    for rid in row_over:
        print("FAIL: %s: NEWROW — a row the seal does not carry must start at <= %d B and this one "
            "is %d. A row is born lean (what is missing + the clues); the durable half goes to the "
            "owning doc BEFORE the row is sealed" % (rid, NEW_ROW_CEILING, rows[rid]))
    for b, sealed, now in brief_growth:
        print("FAIL: %s: GROWTH — %d lines, %d over its sealed %d. A brief carries the contract, "
            "the order of work and the traps — the rows are the authority, and it never restates "
            "them; trim it, or re-seal at the merge station with the reason"
            % (b, now, now - sealed, sealed))
    for b in brief_over:
        print("FAIL: %s: NEWBRIEF — a brief the seal does not carry must start at <= %d lines and "
            "this one is %d" % (b, NEW_BRIEF_CEILING, briefs[b]))
    for rid in stale_rows:
        print("note  ROW %s: seal line for a row that is gone — the lifecycle working (a done row "
              "is deleted, §4(a)); the next re-seal prunes it" % rid)
    for b in stale_briefs:
        print("note  BRIEF %s: seal line for a brief that is gone — a brief dies with its lane "
              "(O7); the next re-seal prunes it" % b)

    n = len(find_growth) + len(row_growth) + len(row_over) + len(brief_growth) + len(brief_over)
    if n:
        print("\n%d finding(s): %d narrative growth, %d row growth, %d row(s) born over the ceiling, "
              "%d brief growth, %d brief(s) born over the ceiling."
              % (n, len(find_growth), len(row_growth), len(row_over), len(brief_growth),
                 len(brief_over)))
        return 1
    print("OK: the work-tracking surfaces are state-only and inside their seals — %d row(s), %d "
          "brief(s), every narrative count at or under its seal" % (len(rows), len(briefs)))
    return 0


# ---------------------------------------------------------------- the flags

def reseal(root: Path, seal_path: Path, floors=(ROW_FLOOR, BRIEF_FLOOR)) -> int:
    """Rewrite the whole body from the tree and print what it froze; stale lines are pruned. The
    merge station's act; a lane never runs it. `floors` is a parameter only so the self-test can
    reseal a fixture tree; every real call site uses the corpus floors."""
    find, rows, briefs, problems = measure(root)
    require_corpus(len(rows), len(briefs), floors)
    for p in problems:
        print("NOTE: %s" % p, file=sys.stderr)
    old_find, old_rows, old_briefs = {}, {}, {}
    header = DEFAULT_HEADER
    if seal_path.is_file():
        text = seal_path.read_bytes().decode("utf-8", "replace")
        keep = []
        for ln in text.split("\n"):
            if ln.strip() and not ln.lstrip().startswith("#"):
                break
            keep.append(ln)
        header = "\n".join(keep).rstrip("\n") + "\n"
        parsed = parse_seal(text)
        if parsed[3]:
            print("NOTE: the old body did not parse (%s) — rewriting it from the tree"
                  % "; ".join(parsed[3]), file=sys.stderr)
        else:
            old_find, old_rows, old_briefs = parsed[0], parsed[1], parsed[2]
    seal_path.write_text(header.rstrip("\n") + "\n" + render_seal(find, rows, briefs),
                         encoding="utf-8", newline="\n")
    pruned_rows = sorted(rid for rid in old_rows if rid not in rows)
    pruned_briefs = sorted(b for b in old_briefs if b not in briefs)
    grew_rows = sorted((rid, old_rows[rid], rows[rid]) for rid in rows
                       if rid in old_rows and rows[rid] > old_rows[rid])
    grew_find = sorted(((f, r), old_find[(f, r)], find[(f, r)]) for (f, r) in find
                       if (f, r) in old_find and find[(f, r)] > old_find[(f, r)])
    print("re-sealed %s" % seal_path)
    print("  tree : %d row(s) + %d brief(s), %d FIND class(es)" % (len(rows), len(briefs), len(find)))
    print("  seal : %d row(s), %d brief(s), %d FIND class(es); pruned %d stale row line(s), %d stale "
          "brief line(s)" % (len(old_rows), len(old_briefs), len(old_find), len(pruned_rows),
                             len(pruned_briefs)))
    for rid, was, now in grew_rows[:MAX_PRINTED]:
        print("    GREW    %s %d -> %d B (+%d) — a row is supposed to SHRINK"
              % (rid, was, now, now - was))
    for (f, r), was, now in grew_find[:MAX_PRINTED]:
        print("    GREW    %s/%s %d -> %d finding(s)" % (f, r, was, now))
    born_over = [rid for rid in rows if rid not in old_rows and rows[rid] > NEW_ROW_CEILING]
    for rid in born_over[:MAX_PRINTED]:
        print("  ⚠ freezing %s at %d B: a row newly entering the seal is over the %d B ceiling. "
              "Sealing it is not the same as approving it." % (rid, rows[rid], NEW_ROW_CEILING))
    return 0


def show_baseline(root: Path, floors=(ROW_FLOOR, BRIEF_FLOOR)) -> int:
    find, rows, briefs, problems = measure(root)
    require_corpus(len(rows), len(briefs), floors)
    for p in problems:
        print("NOTE: %s" % p, file=sys.stderr)
    sys.stdout.write("# body scripts/gate/check_backlog_prose.py --reseal would write\n")
    sys.stdout.write(render_seal(find, rows, briefs))
    print("--show-baseline: %d row(s), %d brief(s), %d FIND class(es)"
          % (len(rows), len(briefs), len(find)), file=sys.stderr)
    return 0


# ---------------------------------------------------------------- self-test

def _fixture(tmp: Path, todo_rows: list[str], briefs: dict) -> Path:
    tmp.mkdir(parents=True, exist_ok=True)
    # newline="\n" everywhere, and that is not decoration: a text-mode write on the Windows seat
    # translates every \n it writes into \r\n, so a fixture seal arrives with CR bytes and the parser
    # refuses the whole body — which is how 14 arms went red on that seat at a commit that was green on
    # the Debian ones (HD-1202 class 3, the same CRLF story the NOTE above prints).
    (tmp / TODO).write_text("# header\n" + "\n".join(todo_rows) + "\n", encoding="utf-8", newline="\n")
    for name, body in briefs.items():
        (tmp / name).write_text(body, encoding="utf-8", newline="\n")
    return tmp


ROW_A = ("| HD-100 | 2 | AI | 1 | **The exporter is declared and not deployed** — the pin lives in "
         "versions.yml. ⏳ converge `--tags monitoring` and read the series back. · [x.md](docs/x.md) |")
ROW_LONG = "| HD-101 | 2 | AI | 1 | **" + ("very long owed work prose " * 90) + "⏳ pending. |"


def self_test() -> int:
    """Breed each defect in a temp tree and refuse a run that did not catch it. Nothing here writes
    near the real tree, and no arm reaches git, the network or a host."""
    fails = 0

    def arm(label, ok, detail=""):
        nonlocal fails
        fails += not ok
        print("  arm %-70s %s%s" % (label, "ok" if ok else "FAIL",
                                    (" — " + detail) if (detail and not ok) else ""))

    def run(root: Path, seal: Path):
        buf = StringIO()
        try:
            with redirect_stdout(buf):
                find, rows, briefs, _ = measure(root)
                fs, rs, bs = read_seal(seal)
                return report(find, rows, briefs, fs, rs, bs), buf.getvalue()
        except ToolError as exc:
            return 2, str(exc)

    def seal_for(root: Path, name="baseline.txt") -> Path:
        p = root / name
        find, rows, briefs, _ = measure(root)
        p.write_text("# fixture seal\n" + render_seal(find, rows, briefs), encoding="utf-8", newline="\n")
        return p

    base_rows = [ROW_A, "| HD-102 | 2 | AI | 2 | **Second row** — states the gap. ⏳ pending. |"]
    base_briefs = {"prompt-alpha.md": "brief body\n" * 40}

    with tempfile.TemporaryDirectory(prefix="check-backlog-prose-") as td:
        tmp = Path(td)

        # (a) the seals, from both sides
        t = _fixture(tmp / "a-green", base_rows, base_briefs)
        rc, out = run(t, seal_for(t))
        arm("(a) a tree inside its own seal is GREEN and names what it counted",
            rc == 0 and "2 row(s)" in out and "1 brief(s)" in out, "rc %d: %s" % (rc, out[-200:]))
        t = _fixture(tmp / "a-row-grow", base_rows, base_briefs)
        grown = ROW_A.replace("⏳ converge", "⏳ converge, and here is a new clause that grew the row")
        (t / TODO).write_text("# header\n" + grown + "\n" + base_rows[1] + "\n", encoding="utf-8", newline="\n")
        rc, out = run(t, seal_for(_fixture(tmp / "a-sealsrc", base_rows, base_briefs)))
        arm("(a) a row grown by even one clause REDDENS as GROWTH naming the bytes",
            rc == 1 and "HD-100: GROWTH" in out, "rc %d: %s" % (rc, out[-200:]))
        t = _fixture(tmp / "a-row-shrink", [ROW_A.split(" ⏳")[0] + " ⏳ pending. |", base_rows[1]],
                     base_briefs)
        rc, out = run(t, seal_for(_fixture(tmp / "a-seal3", base_rows, base_briefs)))
        arm("(a) a row TRIMMED far below its seal is GREEN — a ratchet, never a cap",
            rc == 0 and "GROWTH" not in out, "rc %d: %s" % (rc, out[-200:]))

        # (b) the narrative rules each catch their canary — and a NEW ✅ grows the sealed count
        narrative_rows = [
            "| HD-110 | 2 | AI | 1 | **Gap one** — ✅ the fix landed. ⏳ pending. |",
            "| HD-111 | 2 | AI | 1 | **Gap two** — measured 2026-10-01 at the edge. ⏳ pending. |",
            "| HD-112 | 2 | AI | 1 | **Gap three** — this session found the cause. ⏳ pending. |",
            "| HD-113 | 2 | AI | 1 | **Gap four** — the run recapped ok=12 changed=3. ⏳ pending. |",
        ]
        t = _fixture(tmp / "b-narr", narrative_rows, base_briefs)
        rc, out = run(t, seal_for(_fixture(tmp / "b-seal", base_rows, base_briefs)))
        kinds = [w for w in ("glyph", "verb-date", "phrase", "evidence") if w in out]
        arm("(b) all four narrative rules redden on their canary in one run",
            rc == 1 and kinds == ["glyph", "verb-date", "phrase", "evidence"],
            "rc %d, kinds %s: %s" % (rc, kinds, out[-300:]))
        rc, out = run(t, seal_for(t))
        arm("(b) the same tree against its own seal is GREEN — findings at rest are sealed, growth "
            "is the finding", rc == 0, "rc %d: %s" % (rc, out[-200:]))
        more = narrative_rows + ["| HD-114 | 2 | AI | 1 | **Gap five** — ✅ another claim. ⏳ pending. |"]
        t = _fixture(tmp / "b-grow", more, base_briefs)
        rc, out = run(t, seal_for(_fixture(tmp / "b-seal2", narrative_rows, base_briefs)))
        arm("(b) one NEW ✅ over the sealed glyph count REDDENS — decorating a row is not free",
            rc == 1 and "glyph" in out and "against a sealed 1" in out, "rc %d: %s" % (rc, out[-240:]))
        clean = "| HD-115 | 2 | AI | 1 | **Gap six** — the exporter ships the pin; the store expires " \
                "2027-01-02. ⏳ pending. |"
        t = _fixture(tmp / "b-clean", [clean], base_briefs)
        rc, out = run(t, seal_for(_fixture(tmp / "b-seal3", base_rows, base_briefs)))
        arm("(b) a state date (an expiry) with no verb and no glyph is GREEN — the grammar targets "
            "the verb, not the date", rc == 0 and "glyph" not in out and "verb-date" not in out
            and "phrase" not in out, "rc %d: %s" % (rc, out[-240:]))

        # (c) the ceilings: born lean, or a finding
        t = _fixture(tmp / "c-born-big", [ROW_LONG, base_rows[1]], base_briefs)
        rc, out = run(t, seal_for(_fixture(tmp / "c-seal", base_rows, base_briefs)))
        arm("(c) a NEW row born over the %d B ceiling REDDENS as NEWROW" % NEW_ROW_CEILING,
            rc == 1 and "NEWROW" in out, "rc %d: %s" % (rc, out[-240:]))
        t = _fixture(tmp / "c-born-ok", [ROW_A, base_rows[1]], base_briefs)
        rc, out = run(t, seal_for(_fixture(tmp / "c-seal2", [ROW_A], base_briefs)))
        arm("(c) a NEW row under the ceiling is a sealable state, not a finding",
            rc == 0, "rc %d: %s" % (rc, out[-200:]))
        fat_brief = dict(base_briefs, **{"prompt-beta.md": "line\n" * (NEW_BRIEF_CEILING + 5)})
        t = _fixture(tmp / "c-fat-brief", base_rows, fat_brief)
        rc, out = run(t, seal_for(_fixture(tmp / "c-seal3", base_rows, base_briefs)))
        arm("(c) a NEW brief born over the %d-line ceiling REDDENS as NEWBRIEF" % NEW_BRIEF_CEILING,
            rc == 1 and "NEWBRIEF" in out, "rc %d: %s" % (rc, out[-240:]))

        # (d) the lifecycle: deleted rows/briefs are NOTEs, never findings
        t = _fixture(tmp / "d-gone", [base_rows[1]], base_briefs)
        rc, out = run(t, seal_for(_fixture(tmp / "d-seal", base_rows, base_briefs)))
        arm("(d) a DELETED row against its seal line is a NOTE and the run stays GREEN — closing a "
            "row must never redden the gate", rc == 0 and "note  ROW HD-100" in out,
            "rc %d: %s" % (rc, out[-240:]))
        t = _fixture(tmp / "d-brief-gone", base_rows, {})
        rc, out = run(t, seal_for(_fixture(tmp / "d-seal2", base_rows, base_briefs)))
        arm("(d) a dead BRIEF's seal line is a NOTE too — a brief dies with its lane (O7)",
            rc == 0 and "note  BRIEF prompt-alpha.md" in out, "rc %d: %s" % (rc, out[-240:]))

        # (e) fail-closed, and --reseal writes the seal and nothing else
        rc, out = run(t, tmp / "e-none" / "absent.txt")
        arm("(e) a missing baseline exits 2 — never a silent pass", rc == 2, "rc %d: %s" % (rc, out[:140]))
        (tmp / "e-bad" / "baseline.txt").parent.mkdir(parents=True, exist_ok=True)
        (tmp / "e-bad" / "baseline.txt").write_text("GARBAGE LINE\n", encoding="utf-8", newline="\n")
        rc, out = run(_fixture(tmp / "e-bad-tree", base_rows, base_briefs),
                      tmp / "e-bad" / "baseline.txt")
        arm("(e) a malformed baseline line is refused at rc 2, never silently skipped",
            rc == 2 and "malformed" in out, "rc %d: %s" % (rc, out[:160]))
        empty = tmp / "e-empty"
        empty.mkdir()
        rc, out = run(empty, seal_for(_fixture(tmp / "e-seal", base_rows, base_briefs)))
        arm("(e) an EMPTY corpus is refused at rc 2 — a ratchet over nothing would freeze an empty "
            "baseline and read green forever", rc == 2 and "CANNOT RUN" in out,
            "rc %d: %s" % (rc, out[:160]))
        t = _fixture(tmp / "f-reseal", [ROW_LONG, base_rows[1]], base_briefs)
        sp = seal_for(_fixture(tmp / "f-sealsrc", base_rows, base_briefs), name="bl.txt")
        # copy the seal next to the fat tree, then reseal there
        sp2 = t / "bl.txt"
        sp2.write_text(sp.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
        buf = StringIO()
        with redirect_stdout(buf):
            rc_seal = reseal(t, sp2, floors=(0, 0))
        rc2, out2 = run(t, sp2)
        arm("(f) --reseal rc 0 books the over-ceiling row and the tree then reads GREEN",
            rc_seal == 0 and rc2 == 0, "seal %d, rerun %d: %s" % (rc_seal, rc2, out2[-200:]))
        arm("(f) reseal printed the born-over-ceiling freeze warning and kept the header",
            ("⚠ freezing" in buf.getvalue() or "FREEZE" in buf.getvalue())
            and sp2.read_text(encoding="utf-8").startswith("# fixture seal"), buf.getvalue()[:300])
        shown = StringIO()
        with redirect_stdout(shown):
            show_baseline(t, floors=(0, 0))
        reparsed = parse_seal(shown.getvalue())
        arm("(f) --show-baseline stdout parses back to exactly the tree's state",
            not reparsed[3] and reparsed[1] == measure(t)[1], str(reparsed[3])[:160])
        arm("(f) the bytes of the SURFACES never change under --reseal — the only write is the seal",
            (t / TODO).read_text(encoding="utf-8").startswith("# header"))

        # (g) the real tree clears its floors and its seal is sane
        real_find, real_rows, real_briefs, real_problems = measure(ROOT)
        arm("(g) the REAL tree clears the corpus floors (%d rows, %d briefs against %d/%d)"
            % (len(real_rows), len(real_briefs), ROW_FLOOR, BRIEF_FLOOR),
            len(real_rows) > ROW_FLOOR and len(real_briefs) > BRIEF_FLOOR, str(real_problems)[:160])
        real_text = (ROOT / BASELINE).read_bytes().decode("utf-8", "replace") \
            if (ROOT / BASELINE).is_file() else ""
        arm("(g) this repo's baseline exists, carries no wall clock, no CR and no escaping key",
            bool(real_text) and not CLOCK_RE.search(real_text) and "\r" not in real_text
            and not ESCAPE_RE.search(real_text), "a clock, a CR or an escape leaked in")

    if fails:
        print("FAIL: self-test — %d arm(s) did not behave" % fails)
        return 1
    print("OK: self-test — both ratchets tell growth from shrink with the shrink half proved, all "
          "four narrative rules catch their canary while a state date stays legal, the ceilings "
          "redden a born-fat row/brief, the lifecycle's deletions are NOTEs and never findings, a "
          "missing/malformed baseline and an empty corpus refuse to print OK, and --reseal writes "
          "the seal and nothing else")
    return 0


# ---------------------------------------------------------------- driver

def main() -> int:
    ap = argparse.ArgumentParser(
        prog="check_backlog_prose.py",
        description="Ratchet the work-tracking surfaces (todo.md rows, prompt-*.md briefs): "
                    "narrative finding counts and per-row/per-brief sizes are sealed; shrink is "
                    "free, growth is a finding. Read-only; --reseal writes only the baseline.",
        epilog="exit 0 inside the seal · 1 finding(s) · 2 could not run")
    ap.add_argument("--show", action="store_true", help="counts only, no verdict")
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
        find, rows, briefs, problems = measure(ROOT)
        require_corpus(len(rows), len(briefs))
        if args.show:
            for p in problems:
                print("NOTE: %s" % p)
            print("todo.md: %d row(s), largest %d B; narrative counts: %s"
                  % (len(rows), max(rows.values(), default=0),
                     ", ".join("%s/%s=%d" % (f, r, n) for (f, r), n in sorted(find.items()))))
            print("briefs: %s" % ", ".join("%s=%d lines" % (b, n) for b, n in sorted(briefs.items())))
            return 0
        if args.show_baseline:
            return show_baseline(ROOT)
        if args.reseal:
            return reseal(ROOT, ROOT / BASELINE)
        f_seal, r_seal, b_seal = read_seal(ROOT / BASELINE)
        for p in problems:
            print("NOTE: %s" % p)
        return report(find, rows, briefs, f_seal, r_seal, b_seal)
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
