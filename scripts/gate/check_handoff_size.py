#!/usr/bin/env python3
"""
check_handoff_size.py — keep the standing handoff a handoff: bounded, story-free, count-free.

> **Role:** gate over `prompt.md` — the regrowth guard. Read-only; `--reseal` is the one write, and
> it belongs to the merge station, never to a lane.
> **Linked from:** `scripts/README.md` (the validation gate), `CONVENTIONS.md` §4 (Session close-out
> (5) and (6)), `docs/orchestration.md` §4 (Merge + cleanup, step 4)

WHY THIS EXISTS. The standing handoff promises "a lean handoff, a pointer index and nothing else",
and it accreted to 99,317 bytes over ~20 commits while that promise stood. Nothing bounded the
file, and the close-out rule read as "every prior open item must appear **or be explicitly
resolved**" — so a resolved item stayed, its ✅ narrative kept as proof that it had appeared, and
every later session added its own proof. The fix has two halves: the RULE (CONVENTIONS §4,
close-out (5): a resolved item LEAVES the handoff, its destination named in one clause, the record
being the owning doc + the commit) and this file, so the rule cannot be honoured in words and
undone by the next handoff. A trim without this gate just re-opens the space the next session fills.

THE THREE RULES, each with its verdict word:

  * CEILING — the file over `baseline_bytes + GROWTH_TOLERANCE_BYTES`, or over
    `baseline_lines + GROWTH_TOLERANCE_LINES`, is RED. Both tolerances are set off the handoff's own
    line shape (mean line ~113 B), so an ordinary TWO-LINE addition passes and a one-PARAGRAPH
    story reddens. `--self-test` proves that sentence from both sides, and proves neither half is
    dead code: one long line reddens the byte half alone, a run of short lines reddens the line half
    alone.
  * HISTORY — a §2 entry whose status markers are only ✅/✔/⏸, with no ⏳ anywhere in it and no ⛔
    durable "never" content, is a resolved item that did not leave: RED. Markers are the test, not
    prose, because a marker grammar is checkable and "is this sentence a story?" is not.
  * DERIVED — a typed computable count (`NN rows`, `NN docs`, `NN items`, `NN rules`, `NN samples`,
    `NN snapshots`, `ok=N problems=N`) is RED unless its site is in the frozen list: CONVENTIONS
    §close-out (6) says such a value is re-derived by running, so a number typed into a handoff is a
    defect no later session can tell from a current one.

THE FROZEN SEAL, and why the verdict is a DIFF. The handoff this gate was written against already
carries history and typed counts, so a bare "fail on any finding" gate is red at rest and gets
muted — the lesson `gate/doc_headings_baseline.txt` and `gate/iac_identifier_allowlist.txt` each
record. So the population is sealed in `scripts/gate/handoff_baseline.txt`: `baseline_bytes`,
`baseline_lines`, `sealed_at <rev>`, and the frozen-site list. A site is matched by KEY and never by
line number — one re-wrap moves every number below it, and a list keyed on position would report an
unrelated edit as new debt. Two directions fail: GROWTH (a site the seal does not carry) and STALE (a
sealed line whose site is gone, which would otherwise be a free pass for the next site written at
that key). Clearing a site is therefore an act the seal has to record, which is what `--reseal` is.

`--reseal` rewrites the seal from the current file and PRINTS what it froze: the ceiling before and
after with its direction, and every frozen line added, dropped or count-changed, by key. It never
touches the handoff — a seal is a claim about the file, not about the work. After a trim lands the
parent re-seals in the cleanup commit (`docs/orchestration.md` §4, Merge + cleanup step 4), and a
ceiling red at the merge station means the handoff GREW, not that the baseline needs raising.

WHAT IT CANNOT SEE, stated rather than left to be discovered:
  * It cannot tell a durable dispatch rule from a story. That is why HISTORY keys on markers, why a
    ⛔ in the entry excuses it, and why the frozen list exists: an ⏸ row holding a standing ruling
    reads as history and is sealed rather than deleted.
  * It reads `prompt.md` only. A domain brief accreting the same way is the same defect with no
    gate; briefs die with their lanes, which is the only reason that is cheap.
  * HISTORY walks §2 only. §1 is prose rather than entries, so a ✅ narrative there is bounded by the
    ceiling alone.
  * A count in a shape the two regexes do not list (`42 templates`, `3 hosts`, a date) is not
    DERIVED. The ban is a vocabulary, and the vocabulary is this file's.
  * A story that also carries a live ⏳ in the same entry reads as live. Planting ⏳ on a closed item
    to keep its prose is the cheat this declares; the ceiling bounds what it can buy.

Run:   python3 scripts/gate/check_handoff_size.py [--verbose] [--show-baseline] [--reseal] [--self-test]
Exit:  0 = inside the seal · 1 = finding(s): a grown file, history that stayed, a typed count, or a
         sealed line whose site is gone · 2 = could not run (no handoff, no §2 to walk, a missing or
         malformed seal) — a gate that cannot see the file cannot fail either, so it refuses.
Stdlib + git only; git is asked for the seal revision and its age, and neither answer is typed.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
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
HANDOFF = "prompt.md"
BASELINE = "scripts/gate/handoff_baseline.txt"

# What an ordinary edit gets before the ceiling closes, measured off the handoff's own shape (mean
# line 113 B): roughly three lines, in bytes and in count. Small enough that a paragraph-sized story
# cannot cross it, wide enough that "one pointer replaced by two lines" never reddens. The two
# self-test arms below are the proof of that sentence; widening either number without re-running
# them turns the guard into a formality.
GROWTH_TOLERANCE_BYTES = 384
GROWTH_TOLERANCE_LINES = 3

PENDING = "\u23f3"                  # ⏳ open work still owed
DONE = ("\u2705", "\u2714")         # ✅ / ✔ a completion claim
PARKED = "\u23f8"                   # ⏸ ruled or parked with nothing left to do here
NEVER = "\u26d4"                    # ⛔ durable "never" content — a rule, not a story

# The exemption that keeps a DECISION INDEX from reading as history. Naming a closed ruling is not a
# record of work done; re-deciding a settled question is the cost the line pays to prevent. So a
# completed §2 entry is LAWFUL while it stays one clause that says where the ruling lives:
#   * it names a destination — a link, a doc path, a § anchor or a todo row id;
#   * and it is one clause — no stated measurement, no more of it than CLAUSE_LIMIT_BYTES.
# Lose either half and it is a story about a decision, which the owning doc and the commit hold.
CLAUSE_LIMIT_BYTES = 260
DESTINATION_RE = re.compile(r"\]\([^)]*\)|[\w./-]+\.md\b|\bHD-\d+\b|§[ \t]*[A-Za-z0-9]")
TELL_RE = re.compile(r"\b(?:measured|observed|benchmarked|timed|rc[ \t]+\d+|exit[ \t]+\d+)\b"
                     r"|\d(?:\.\d+)?[ \t]?(?:ms|min|kB|MB|s)\b|\d+(?:\.\d+)?%", re.I)

ITEM_RE = re.compile(r"^(?P<ind>[ \t]*)(?:\d+[.)]|[-*+])[ \t]+\S")
HEAD2_RE = re.compile(r"^##[ \t]+2[.\s]")
HEAD_RE = re.compile(r"^##[ \t]+\S")
FENCE_RE = re.compile(r"^[ \t]*(?:```|~~~)")
DERIVED_RES = (
    re.compile(r"(?<![\w.])\d+[ \t]+(?:rows|docs|items|rules|samples|snapshots)\b", re.I),
    re.compile(r"\bok=\d+[ \t]+problems=\d+", re.I),
)
CLASSES = ("history", "derived")
FIELDS = ("baseline_bytes", "baseline_lines", "sealed_at")
REV_RE = re.compile(r"^[0-9a-f]{7,40}$")
MAX_PRINTED = 12
# A git fixture must not reach the tree that is running it (HD-1179): these six are scrubbed from
# every git call here, so a caller exporting GIT_DIR cannot move --reseal's rev or --self-test's reads.
GIT_VARS = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR",
            "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES")

DEFAULT_HEADER = """\
# Frozen seal for scripts/gate/check_handoff_size.py — the handoff size it was sealed at, plus the
# sites this gate reports and this repo has agreed to CARRY. Read that file's docstring before
# editing this one: the two directions this file fails on (a site the seal does not carry, and a
# carried site whose text is gone) are the whole point of it.
#
# Fields, one per line, `<name> <value>` — always re-derived by --reseal, never hand-typed, because
# a count in prose is a defect (CONVENTIONS §2):
#     baseline_bytes <n>   the handoff's byte size at the seal; the ceiling is this + the tolerance
#     baseline_lines <n>   its line count at the same commit, same ceiling
#     sealed_at <rev>      the commit both numbers were taken at
#
# Frozen sites — five TAB-separated fields, matched by KEY and never by line number:
#     exempt<TAB><class><TAB><path><TAB><count><TAB><the site as written>
#   class `history`  a §2 entry already history-shaped at the seal — an ⏸ row holding a standing
#                    ruling reads as history, so it is sealed here rather than deleted from the file.
#   class `derived`  a typed computable count still standing in the handoff: debt owed to the next
#                    trim, NOT a licence for the next session to type another one.
#
# Re-derive the body after a trim lands — at the merge station, never inside a lane:
#     python3 scripts/gate/check_handoff_size.py --reseal
"""


class ToolError(Exception):
    """The gate cannot run. Refuse loudly; a green that measured nothing is worse than no green."""


class Site:
    """One site's identity: its class, the file, the normalized text the seal keys on, and how many
    copies the file carries. A line number is never part of the key — one re-wrap above the site
    would otherwise read as one site cleared plus one site grown."""

    __slots__ = ("cls", "path", "key", "token", "count", "lines")

    def __init__(self, cls: str, path: str, key: str, token: str = ""):
        self.cls, self.path, self.key, self.token = cls, path, key, token
        self.count, self.lines = 0, []

    @property
    def id(self) -> tuple:
        return (self.cls, self.path, self.key)

    def where(self) -> str:
        """Where the site is NOW. A sealed line carries no lines of its own, so a stale site prints
        as the file alone plus its key — the reader needs the key to find what stopped matching."""
        if not self.lines:
            return "%s (no longer in the file)" % self.path
        return "%s:%s" % (self.path, ",".join(str(n) for n in self.lines[:4]))

    def show(self) -> str:
        return "%-8s x%-3d %s%s" % (self.cls.upper(), self.count, self.where(),
                                    ("  " + self.token) if self.token else "")


class Block:
    """One §2 list item: its own lines, its nested items, and the two views of it HISTORY needs."""

    __slots__ = ("line", "indent", "own", "children")

    def __init__(self, line: int, indent: int):
        self.line, self.indent, self.own, self.children = line, indent, [line], []

    def own_text(self, lines: list[str]) -> str:
        return "\n".join(lines[i] for i in self.own)

    def inclusive(self, lines: list[str]) -> str:
        return "\n".join([self.own_text(lines)] + [c.inclusive(lines) for c in self.children])

    def title(self, lines: list[str]) -> str:
        """The key a HISTORY site is sealed under: the entry line, whitespace folded."""
        return " ".join(lines[self.line].split())


# ---------------------------------------------------------------- the scan

def read_text(path: Path) -> str:
    if not path.is_file():
        raise ToolError("%s is not a file — the handoff this gate guards is gone (moved? renamed?). "
                        "Say so where the rule lives; do not let the gate go quiet" % path)
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise ToolError("%s is not UTF-8 (%s)" % (path, exc)) from None


def masked(text: str) -> list[str]:
    """The file's lines with fenced blocks emptied: a command example is not a claim the handoff
    makes about the fleet. Line numbers survive, because every finding cites one."""
    out, fence = [], False
    for ln in text.split("\n"):
        if FENCE_RE.match(ln):
            fence = not fence
            out.append("")
            continue
        out.append("" if fence else ln)
    return out


def section2(lines: list[str]) -> tuple[int, int]:
    """[start, end) of the §2 pointer list — the section the close-out rule speaks about."""
    start = next((i for i, ln in enumerate(lines) if ln.strip() and HEAD2_RE.match(ln)), None)
    if start is None:
        raise ToolError("no §2 heading in the handoff, so there is no entry list to walk and this "
                        "gate would print OK having read nothing. A renamed section is a rule change: "
                        "fix the heading or fix the gate, in this commit")
    end = next((i for i in range(start + 1, len(lines)) if HEAD_RE.match(lines[i])), len(lines))
    return start, end


def entries(lines: list[str], lo: int, hi: int) -> list[Block]:
    """§2 split into blocks: every list item at any depth, continuation lines attached. A bullet is
    a block of its own, so an answered bullet under a live numbered item is judged on its own
    markers — that nesting IS the shape that grew the file."""
    roots: list[Block] = []
    stack: list[Block] = []
    for i in range(lo, hi):
        raw = lines[i]
        if not raw.strip():
            continue
        m = ITEM_RE.match(raw)
        if m:
            indent = len(m.group("ind").expandtabs(4))
            while stack and indent <= stack[-1].indent:
                stack.pop()
            blk = Block(i, indent)
            (stack[-1].children if stack else roots).append(blk)
            stack.append(blk)
            continue
        if stack:
            stack[-1].own.append(i)
    return roots


def is_lawful_ruling(text: str) -> bool:
    """The one-clause decision index: completed, and pointing somewhere instead of retelling.

    This is what keeps the trimmed handoff's ruled-decision bullets lawful — they exist so a later
    session does not re-decide a settled question, which is content the ceiling would happily pay
    for. A ✅ that recites measurements, or a ✅ that runs past one clause even with a link in it, is
    the narrative this rule is for, so BOTH halves are required and a pointer cannot whitewash a
    story."""
    if not DESTINATION_RE.search(text) or TELL_RE.search(text):
        return False
    return len(text.encode("utf-8")) <= CLAUSE_LIMIT_BYTES


def is_history(text: str) -> bool:
    """Markers, not prose: at least one completion or ruling claim, nothing still owed, no durable
    ⛔ content that would make the entry a rule rather than a record, and no lawful one-clause
    ruling with a destination to read."""
    marked = any(g in text for g in DONE) or PARKED in text
    return marked and PENDING not in text and NEVER not in text and not is_lawful_ruling(text)


def census(text: str) -> str:
    """What the reader of a HISTORY finding needs: which markers the entry actually carried."""
    return " ".join("%s x%d" % (g, text.count(g))
                    for g in DONE + (PARKED,) if text.count(g))


def bucket(sites: list[Site], candidate: Site) -> Site:
    """Sites aggregate by key, so the same text twice is ONE site with a count of two — a story
    copy-pasted must not read as two frozen exemptions."""
    for s in sites:
        if s.id == candidate.id:
            return s
    sites.append(candidate)
    return candidate


def history_sites(lines: list[str], roots: list[Block], path: str) -> list[Site]:
    """The outermost §2 entries that are nothing but completion or ruling markers. An entry with an
    ⏳ anywhere in it, or with ⛔ durable content, is not reported as a whole — and is descended into,
    so a live item cannot shelter an answered bullet under it, and its own narrative line is judged
    on its own markers for the same reason."""
    out: list[Site] = []

    def add(blk: Block, body: str) -> None:
        site = bucket(out, Site("history", path, blk.title(lines), census(body)))
        site.lines.append(blk.line + 1)
        site.count += 1

    def walk(blk: Block) -> None:
        body = blk.inclusive(lines)
        if is_history(body):
            add(blk, body)
            return
        if blk.children and is_history(blk.own_text(lines)):
            add(blk, blk.own_text(lines))
        for kid in blk.children:
            walk(kid)

    for root in roots:
        walk(root)
    return out


def derived_sites(lines: list[str], path: str) -> list[Site]:
    """Every typed computable count in the file, one site per line keyed on that line's text."""
    out: list[Site] = []
    for i, ln in enumerate(lines):
        tokens = [m.group(0).strip() for rx in DERIVED_RES for m in rx.finditer(ln)]
        if not tokens:
            continue
        site = bucket(out, Site("derived", path, " ".join(ln.split()),
                                ", ".join(dict.fromkeys(tokens))))
        site.lines.append(i + 1)
        site.count += 1
    return out


def scan_text(text: str, path: str) -> tuple[dict, list[Site]]:
    """The whole population of one handoff: its two size numbers and its sites, both classes. Over
    text, so the self-test never needs to write near the real tree."""
    lines = masked(text)
    lo, hi = section2(lines)
    roots = entries(lines, lo, hi)
    require_corpus(len(roots), 0, "check_handoff_size §2 entries in %s" % path)
    sites = history_sites(lines, roots, path) + derived_sites(lines, path)
    return {"bytes": len(text.encode("utf-8")), "lines": len(text.splitlines()), "path": path}, sites


def scan(handoff: Path) -> tuple[dict, list[Site]]:
    try:
        path = handoff.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        path = handoff.name          # a fixture tree, outside this checkout
    return scan_text(read_text(handoff), path)


# ---------------------------------------------------------------- the seal

def parse_seal(text: str) -> tuple[dict, list[Site], list[str]]:
    """`({field: value}, [sites], [complaints])`. A malformed line is a complaint, never a silent
    skip: an exemption that cannot match a site exempts everything at its key."""
    fields: dict = {}
    sites: list[Site] = []
    bad: list[str] = []
    for n, line in enumerate(text.split("\n"), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith("exempt"):
            parts = line.split("\t")
            if len(parts) != 5 or parts[1] not in CLASSES or not parts[2].strip() \
                    or not parts[3].isdigit() or not parts[4].strip():
                bad.append("%s:%d — want exempt<TAB><class>%s<TAB><path>TAB<count>TAB<site>"
                           % (BASELINE, n, "|".join(CLASSES)))
                continue
            site = bucket(sites, Site(parts[1], parts[2], parts[4]))
            site.count += int(parts[3])
            continue
        if " " in line:
            key, _, val = line.partition(" ")
            fields[key.strip()] = val.strip()
            continue
        bad.append("%s:%d — neither a field nor an exempt line: %r" % (BASELINE, n, line[:60]))
    for f in FIELDS:
        if f not in fields:
            bad.append("%s — the field %s is missing, so the value it feeds is unknown" % (BASELINE, f))
    if bad:
        return fields, sites, bad
    for f in ("baseline_bytes", "baseline_lines"):
        if not fields[f].isdigit():
            bad.append("%s — %s must be a plain count, read %r" % (BASELINE, f, fields[f]))
    if not REV_RE.match(fields.get("sealed_at", "")):
        bad.append("%s — sealed_at must be a commit sha, read %r" % (BASELINE, fields.get("sealed_at")))
    return fields, sites, bad


def read_seal(path: Path) -> tuple[dict, list[Site]]:
    if not path.is_file():
        raise ToolError("%s is missing, so the size and the sites this gate is ratcheted to are "
                        "unknown and every pre-existing finding would read as growth. Re-derive it at "
                        "the merge station: python3 scripts/gate/check_handoff_size.py --reseal"
                        % BASELINE)
    fields, sites, bad = parse_seal(path.read_text(encoding="utf-8"))
    if bad:
        raise ToolError("%s is malformed:\n  %s" % (BASELINE, "\n  ".join(bad)))
    return fields, sites


def render_seal(fields: dict, sites: list[Site]) -> str:
    """The body: three fields, then one sorted `exempt` line per site key. Rendering and parsing are
    inverses here, which self-test arm (g) proves rather than asserts."""
    body = "".join("%s %s\n" % (f, fields[f]) for f in FIELDS)
    return body + "".join("exempt\t%s\t%s\t%d\t%s\n" % (s.cls, s.path, s.count, s.key)
                          for s in sorted(sites, key=lambda s: (s.cls, s.path, s.key)))


def git_run(args: list[str], cwd: Path) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items() if k not in GIT_VARS}
    return subprocess.run(args, cwd=str(cwd), env=env, capture_output=True, text=True)


def git_rev(cwd: Path) -> str:
    r = git_run(["git", "rev-parse", "HEAD"], cwd)
    if r.returncode != 0:
        raise ToolError("git rev-parse HEAD failed, so sealed_at could be printed instead of assumed: "
                        "%s" % r.stderr.strip())
    return r.stdout.strip()


def git_age(cwd: Path, rev: str) -> str:
    """How many commits have passed since the seal — printed when provable, never assumed, and an
    unreadable rev prints its own state instead of passing as a verdict (CONVENTIONS §6)."""
    r = git_run(["git", "-C", str(cwd), "rev-list", "--count", "%s..HEAD" % rev], cwd)
    if r.returncode != 0:
        return "age not provable from this clone"
    return "%s commit(s) ago" % r.stdout.strip()




# ---------------------------------------------------------------- the verdict

def ceilings(size: dict, fields: dict) -> list[str]:
    """The ceiling complaints, each naming both numbers it compared — a verdict that does not say
    what it measured against is a verdict nobody can re-check."""
    out = []
    for key, base_field, tol in (("bytes", "baseline_bytes", GROWTH_TOLERANCE_BYTES),
                                 ("lines", "baseline_lines", GROWTH_TOLERANCE_LINES)):
        cap = int(fields[base_field]) + tol
        if size[key] > cap:
            out.append("CEILING %s: %s is %s %s, %d over the ceiling (%s = %s + %d tolerance)"
                       % (key, size["path"], size[key], key, size[key] - cap, base_field,
                          fields[base_field], tol))
    return out


def diff_sites(measured: list[Site], sealed: list[Site]) -> tuple[list, list]:
    """(growth, stale) by key, on budget semantics — the `gate/doc_headings_baseline.txt` rule: one
    sealed line pays for that many copies of that site, no more and no fewer. A copy-paste of a
    frozen story therefore reads as growth, not as a second exemption."""
    budget: dict = {}
    for s in sealed:
        budget[s.id] = budget.get(s.id, 0) + s.count
    left, grown = dict(budget), []
    for s in sorted(measured, key=lambda s: s.lines[0] if s.lines else 0):
        extra = max(0, s.count - left.get(s.id, 0))
        left[s.id] = max(0, left.get(s.id, 0) - s.count)
        if extra:
            grown.append((s, extra))
    stale = [(s, left[s.id]) for s in sorted(sealed, key=lambda s: (s.cls, s.path, s.key))
             if left[s.id] > 0]
    return grown, stale


def _row(s: Site, n: int) -> str:
    return "  %-8s x%-3d %s%s" % (s.cls.upper(), n, s.where(), ("  " + s.token) if s.token else "")


def report(handoff: Path, seal_path: Path, verbose: bool = False, age: bool = True) -> int:
    size, sites = scan(handoff)
    fields, sealed = read_seal(seal_path)
    red = ceilings(size, fields)
    grown, stale = diff_sites(sites, sealed)

    print("handoff %s: %d B / %d lines, sealed at %s%s; ceilings +%d B / +%d lines"
          % (size["path"], size["bytes"], size["lines"], fields["sealed_at"],
             (" (%s)" % git_age(handoff.parent, fields["sealed_at"])) if age else "",
             GROWTH_TOLERANCE_BYTES, GROWTH_TOLERANCE_LINES))
    print("rules: CEILING (bytes, then lines, over the sealed size), HISTORY (§2 entries marked only "
          "%s/%s/%s with no %s, no %s, and no one-clause ruling naming a destination), DERIVED (a "
          "typed computable count)" % (DONE[0], DONE[1], PARKED, PENDING, NEVER))
    for line in red:
        print("  " + line)

    def block(title: str, rows: list, why: str) -> None:
        if not rows:
            return
        print("  %s %d site(s) — %s" % (title, len(rows), why))
        for s, n in rows[:MAX_PRINTED]:
            print(_row(s, n))
            if title == "STALE":
                print("             sealed as: %s" % s.key[:110])
        if len(rows) > MAX_PRINTED:
            print("    … %d more, same direction" % (len(rows) - MAX_PRINTED))

    block("NEW", grown, "not in the seal — a resolved item that stayed, or a count typed into prose")
    block("STALE", stale, "sealed, but its text is gone. A carried line that matches nothing is the "
                          "next site's free pass: delete it, or carry it again, in this commit")
    if verbose:
        frozen = [s for s in sites if not any(s.id == g[0].id for g in grown)]
        print("  FROZEN %d site(s) — reported, not failed:" % sum(s.count for s in frozen))
        for s in sorted(frozen, key=lambda s: (s.cls, s.key)):
            print(_row(s, s.count))

    if red or grown or stale:
        print("FAIL: %d ceiling breach(es), %d new HISTORY site(s), %d new DERIVED site(s), "
              "%d stale seal line(s)"
              % (len(red), len([g for g in grown if g[0].cls == "history"]),
                 len([g for g in grown if g[0].cls == "derived"]), len(stale)))
        print("      A resolved §2 item LEAVES the handoff — name its destination in one clause and "
              "let the owning doc plus the commit hold the record (CONVENTIONS §4, close-out (5)); a "
              "computable count is re-derived by running, never typed (§close-out (6)).")
        return 1
    print("OK: inside the seal — %d B / %d lines, %d frozen site(s) carried, nothing new, nothing "
          "stale" % (size["bytes"], size["lines"], sum(s.count for s in sealed)))
    return 0


# ---------------------------------------------------------------- the flags

def reseal(handoff: Path, seal_path: Path, rev: str | None = None) -> int:
    """Rewrite the seal from the current handoff and PRINT what it froze. This is the merge station's
    act after a trim lands (docs/orchestration.md §4, Merge + cleanup step 4); a lane never runs it.
    The header survives, because it is the explanation and the body is the data."""
    size, sites = scan(handoff)
    fields = {"baseline_bytes": str(size["bytes"]), "baseline_lines": str(size["lines"]),
              "sealed_at": rev or git_rev(handoff.parent)}
    header, old_fields, old_sites = DEFAULT_HEADER, {}, []
    if seal_path.is_file():
        text = seal_path.read_text(encoding="utf-8")
        keep = []
        for ln in text.split("\n"):
            if ln.strip() and not ln.lstrip().startswith("#"):
                break
            keep.append(ln)
        header = "\n".join(keep).rstrip("\n") + "\n"
        f, s, bad = parse_seal(text)
        if bad:
            print("NOTE: the old seal did not parse (%s) — rewriting its body from this file"
                  % "; ".join(bad), file=sys.stderr)
        else:
            old_fields, old_sites = f, s

    seal_path.write_text(header + render_seal(fields, sites), encoding="utf-8")

    ob = int(old_fields.get("baseline_bytes", size["bytes"]))
    direction = ("UNCHANGED" if ob == size["bytes"]
                 else "GREW +%d B" % (size["bytes"] - ob) if size["bytes"] > ob
                 else "TRIMMED -%d B" % (ob - size["bytes"]))
    print("re-sealed %s" % seal_path)
    print("  bytes %d -> %s (%s)   lines %s -> %s   sealed_at %s"
          % (ob, fields["baseline_bytes"], direction, old_fields.get("baseline_lines", "?"),
             fields["baseline_lines"], fields["sealed_at"]))
    if direction.startswith("GREW"):
        print("  ⚠ the handoff is BIGGER than its last seal. A ceiling red after a merge means the "
              "handoff GREW — trim it. Raising a ceiling is how this guard gets muted, not kept.")
    old_ids: dict = {}
    for s in old_sites:
        old_ids[s.id] = old_ids.get(s.id, 0) + s.count
    new_ids: dict = {}
    for s in sites:
        new_ids[s.id] = new_ids.get(s.id, 0) + s.count
    added = sorted(i for i in new_ids if i not in old_ids)
    dropped = sorted(i for i in old_ids if i not in new_ids)
    changed = sorted(i for i in new_ids if i in old_ids and new_ids[i] != old_ids[i])
    print("  frozen sites %d -> %d (+%d frozen now, -%d cleared, %d count-changed)"
          % (len(old_ids), len(new_ids), len(added), len(dropped), len(changed)))
    for group, word in ((added, "FROZEN "), (dropped, "CLEARED"), (changed, "COUNT   ")):
        for i in group[:MAX_PRINTED]:
            detail = ""
            if word == "COUNT   ":
                detail = "%d -> %d  " % (old_ids[i], new_ids[i])
            print("    %s %-8s %s%s" % (word, i[0], detail, i[2][:100]))
        if len(group) > MAX_PRINTED:
            print("    … %d more %s" % (len(group) - MAX_PRINTED, word.strip().lower()))
    if [i for i in added if i[0] == "derived"]:
        print("  ⚠ a NEW typed count is now frozen. Sealing it buys silence until the next trim; "
              "deleting the number is the cheaper fix and the one CONVENTIONS §close-out (6) asks for.")
    return 0


def show_baseline() -> int:
    """stdout = the body a re-seal would write, so one redirect reproduces it; the summary goes to
    stderr. This is `check_doc_headings.py --show-baseline`'s shape: the numbers are derived, so they
    are never remembered (CONVENTIONS §2)."""
    size, sites = scan(ROOT / HANDOFF)
    sys.stdout.write("# body check_handoff_size.py --reseal would write, derived from %s at the "
                     "revision below; replace the body of %s with this and keep its header\n"
                     % (HANDOFF, BASELINE))
    sys.stdout.write(render_seal({"baseline_bytes": str(size["bytes"]),
                                  "baseline_lines": str(size["lines"]),
                                  "sealed_at": git_rev(ROOT)}, sites))
    print("--show-baseline: %d frozen line(s) for %d site(s); the ceiling would become %d B / %d lines"
          % (len(sites), sum(s.count for s in sites), size["bytes"], size["lines"]), file=sys.stderr)
    return 0


# ---------------------------------------------------------------- self-test

FIXTURE_REV = "0123456789abcdef0123456789abcdef01234567"
FIXTURE = """> **Role:** the standing handoff fixture — small on purpose, so every byte it grows is
> attributable to the arm that grew it.
> **Linked from:** nothing but this file's own self-test

## 1. Environment

Prose. A count a command prints here is `ok=1 problems=0`, and the seal carries that site.

## 2. Next tasks (the rows are the authority; this is only the ranked pointer list)

1. ⏳ **A live item** — one ordinary handoff line, pointing at [todo.md](todo.md).
   - ⏳ **A live bullet** — the part still owed.

## 3. Not walked by the history rule

A ✅ that stayed outside §2, to prove HISTORY is scoped to the pointer list and not to the file.
"""


def _pair(tmp: Path, sealed_text: str, handoff_text: str | None = None) -> tuple[Path, Path]:
    """A fixture handoff plus the seal rendered from `sealed_text`. One argument makes the pair GREEN
    by construction, so every arm below is a single mutation rather than a story about two; two
    arguments split the seal from the file, which is how GROWTH and STALE are bred."""
    tmp.mkdir(parents=True, exist_ok=True)
    handoff, seal = tmp / HANDOFF, tmp / "handoff_baseline.txt"
    handoff.write_text(handoff_text if handoff_text is not None else sealed_text, encoding="utf-8")
    size, sites = scan_text(sealed_text, HANDOFF)
    seal.write_text("# fixture seal — nothing here is the repo's seal\n" + render_seal(
        {"baseline_bytes": str(size["bytes"]), "baseline_lines": str(size["lines"]),
         "sealed_at": FIXTURE_REV}, sites), encoding="utf-8")
    return handoff, seal


def _grown(*lines: str, blank: bool = True) -> str:
    """FIXTURE with `lines` appended to §2, where the pointer list ends and §3 has to go on.
    `blank=False` splices without the separator line, for arms that must stay inside the ceiling."""
    return FIXTURE.replace("## 3.", "".join(lines) + ("\n## 3." if blank else "## 3."))


def self_test() -> int:
    """Breed each defect in a temp tree and refuse a run that did not catch it. The arms ARE the
    contract: a ceiling that cannot tell two lines from a paragraph is not a ceiling, and a ratchet
    that cannot watch its own debt vanish is not a ratchet. Nothing here writes near the real tree,
    and no arm reaches git — the seal revision is injected, so the test reads the same in every
    clone and in every fixture environment (the HD-1179 rule about a gate's own fixture)."""
    fails = 0

    def arm(label: str, ok: bool, detail: str = "") -> None:
        nonlocal fails
        fails += not ok
        print("  arm %-64s %s%s" % (label, "ok" if ok else "FAIL",
                                    (" — " + detail) if (detail and not ok) else ""))

    def run(handoff: Path, seal: Path, verbose: bool = False) -> tuple[int, str]:
        buf = StringIO()
        try:
            with redirect_stdout(buf):
                rc = report(handoff, seal, verbose=verbose, age=False)
        except ToolError as exc:
            return 2, str(exc)
        return rc, buf.getvalue()

    def rows_under(out: str, heading: str) -> list[str]:
        """The rows printed under one block heading, and nothing after it. An `in` test on the whole
        output is meaningless here: the rules banner and the FAIL summary both name every class."""
        lines = out.splitlines()
        try:
            start = next(i for i, ln in enumerate(lines) if ln.startswith("  %s " % heading))
        except StopIteration:
            return []
        stop = ("NEW", "STALE", "FROZEN")
        rows = []
        for ln in lines[start + 1:]:
            if any(ln.strip().startswith(h) for h in stop) or ln[:1] in "FO":
                break
            rows.append(ln)
        return rows

    def found(out: str, cls: str) -> list[str]:
        return [ln for ln in rows_under(out, "NEW") if ln.strip().startswith(cls.upper())]

    def stale_rows(out: str) -> list[str]:
        return rows_under(out, "STALE")

    def cap(fn, *a, **kw):
        buf = StringIO()
        with redirect_stdout(buf):
            out = fn(*a, **kw)
        return out, buf.getvalue()

    with tempfile.TemporaryDirectory(prefix="check-handoff-size-") as td:
        tmp = Path(td)

        # (a) The machinery itself: a handoff inside its own seal is green, and the green saw a site.
        h, s = _pair(tmp / "green", FIXTURE)
        rc, out = run(h, s)
        arm("(a) a handoff inside its own seal is GREEN", rc == 0, "rc %d: %s" % (rc, out[-200:]))
        rc, out = run(h, s, verbose=True)
        arm("(a) and that green saw the site it froze — an empty walk may not print OK",
            rc == 0 and "FROZEN 1 site" in out, "rc %d: %s" % (rc, out[-260:]))

        # (b) The tolerance, proved from both sides: two ordinary lines pass, a paragraph does not.
        two = ("2. ⏳ **Another pointer** — one ordinary handoff line of about a hundred bytes, "
               "pointing at its row.\n"
               "3. ⏳ **And one more** — another ordinary handoff line of roughly the same size, "
               "pointing at its owning doc.\n")
        rc, out = run(*_pair(tmp / "two", FIXTURE, _grown(two)))
        arm("(b) an ordinary two-line addition stays GREEN", rc == 0, "rc %d: %s" % (rc, out[-220:]))
        para = ("2. ⏳ **The story of the thing** — first the context, which runs to several lines and "
                "     nobody asked for it; then the finding, in similar detail; then what was done,\n"
                "     with the command that did it; then the read-back, with the output it printed; "
                "     and last the lesson at length, because the lesson is the part that always\n"
                "     escapes into the handoff instead of the owning doc, which is exactly the move\n"
                "     this ceiling exists to refuse.\n")
        rc, out = run(*_pair(tmp / "para", FIXTURE, _grown(para)))
        arm("(b) a one-paragraph story REDDENS the ceiling", rc == 1 and "CEILING" in out,
            "rc %d: %s" % (rc, out[-220:]))

        # (c) Neither half of the ceiling is dead code: bytes alone, then lines alone.
        long_line = "2. ⏳ **X** — " + "y" * 500 + "\n"
        rc, out = run(*_pair(tmp / "long", FIXTURE, _grown(long_line)))
        arm("(c) one long line REDDENS the byte rule alone",
            rc == 1 and "CEILING bytes" in out and "CEILING lines" not in out, out[-220:])
        short = "".join("%d. a\n" % (i + 2) for i in range(GROWTH_TOLERANCE_LINES + 3))
        rc, out = run(*_pair(tmp / "short", FIXTURE, _grown(short)))
        arm("(c) a run of short lines REDDENS the line rule alone",
            rc == 1 and "CEILING lines" in out and "CEILING bytes" not in out, out[-220:])

        # (d) HISTORY keys on markers, not on prose. The answered bullet IS the shape that grew file.
        answered = "   - ✅ **The thing — ANSWERED: yes, and it landed in the owning doc.**\n"
        grown = _grown(answered)
        rc, out = run(*_pair(tmp / "hist", FIXTURE, grown))
        arm("(d) an answered §2 bullet REDDENS as HISTORY",
            rc == 1 and bool(found(out, "history")), "rc %d: %s" % (rc, out[-220:]))
        rc, out = run(*_pair(tmp / "hist-frozen", grown))
        arm("(d) and GREEN once the seal carries it — frozen debt is reported, not failed",
            rc == 0, "rc %d: %s" % (rc, out[-220:]))
        rc, out = run(*_pair(tmp / "live", FIXTURE, _grown("   - ⏳ **A live bullet** — owed.\n")))
        arm("(d) the same bullet with an ⏳ is GREEN — the marker says it is still owed",
            rc == 0, "rc %d: %s" % (rc, out[-220:]))
        rc, out = run(*_pair(tmp / "never", FIXTURE,
                             _grown("   - ⛔ **Never re-type that count** — a rule, not a record.\n")))
        arm("(d) a ⛔ rule line is GREEN — durable content is not a story", rc == 0,
            "rc %d: %s" % (rc, out[-220:]))
        rc, out = run(*_pair(tmp / "park", FIXTURE, _grown("   - ⏸ **Ruled: yes, and scheduled.**\n")))
        arm("(d) an unsealed ⏸ ruling REDDENS — seal it or delete it, do not leave it implicit",
            rc == 1 and bool(found(out, "history")), "rc %d: %s" % (rc, out[-220:]))
        rc, out = run(*_pair(tmp / "outside", FIXTURE,
                             FIXTURE.replace("A ✅ that stayed outside §2",
                                             "A ✅ narrative that stayed here, outside §2")))
        arm("(d) a ✅ outside §2 is not HISTORY — the ceiling alone bounds §1 and §3 (declared)",
            rc == 0, "rc %d: %s" % (rc, out[-220:]))

        # The DECISION-INDEX exemption, both arms. A ruled decision that says where the ruling lives
        # is content the handoff is ASKED to keep — re-deciding a settled question costs more than the
        # line — so it must read GREEN with no seal line behind it. Each half of the exemption is
        # proved separately, because a rule that only looked for a link is a rule a paragraph could
        # satisfy by pasting one in.
        ruled = ("   - ✅ **Ruled: the deltas retire on schedule, not here** — the procedure and its "
                 "trigger live in [docs/storage.md](docs/storage.md), row **HD-123**.\n")
        rc, out = run(*_pair(tmp / "ruled", FIXTURE, _grown(ruled)))
        arm("(d) a one-clause ✅ ruling naming its destination is GREEN unsealed (decision index)",
            rc == 0, "rc %d: %s" % (rc, out[-240:]))
        told = ("   - ✅ **Ruled: retire them — measured 4.2 s to 1.1 s on the seat, rc 0, twelve "
                "entries rewritten, and the finding was that the seed lagged; procedure in "
                "[docs/storage.md](docs/storage.md).**\n")
        rc, out = run(*_pair(tmp / "ruled-told", FIXTURE, _grown(told)))
        arm("(d) the same ruling reciting its measurements REDDENS — a link cannot whitewash a story",
            rc == 1 and bool(found(out, "history")), "rc %d: %s" % (rc, out[-240:]))
        padded = ("   - ✅ **Ruled: retire them, and the whole reasoning behind the schedule belongs "
                  "here too because it took a session to reach: first the options, then why two were "
                  "refused, then what the constraint turned out to be, and the order to do it in** — "
                  "[docs/storage.md](docs/storage.md).\n")
        assert len(padded.encode("utf-8")) > CLAUSE_LIMIT_BYTES, "the arm must exceed the limit"
        rc, out = run(*_pair(tmp / "ruled-long", FIXTURE, _grown(padded)))
        arm("(d) and that ruling padded past one clause REDDENS with its link present",
            rc == 1 and bool(found(out, "history")), "rc %d: %s" % (rc, out[-240:]))

        # (e) DERIVED: every listed shape reddens; a fenced example is not a claim the file makes.
        for tok in ("42 rows", "7 docs", "3 items", "9 rules", "5 samples", "8 snapshots",
                    "ok=4 problems=1"):
            text = _grown("   It printed %s on the seat, counted by hand.\n" % tok)
            rc, out = run(*_pair(tmp / ("der" + tok.replace("=", "").replace(" ", "")), FIXTURE, text))
            arm("(e) a typed `%s` REDDENS as DERIVED" % tok,
                rc == 1 and bool(found(out, "derived")), "rc %d: %s" % (rc, out[-220:]))
        fenced = _grown("   ```\n   RESULT ok=9 problems=0\n   ```\n", blank=False)
        rc, out = run(*_pair(tmp / "fence", FIXTURE, fenced))
        arm("(e) a count inside a code fence is not a claim — GREEN", rc == 0,
            "rc %d: %s" % (rc, out[-220:]))

        # (f) The ratchet's second direction: a frozen site whose text left the handoff.
        trimmed = FIXTURE.replace("`ok=1 problems=0`", "re-derived by running it")
        rc, out = run(*_pair(tmp / "stale", FIXTURE, trimmed))
        arm("(f) a frozen site whose text is gone REDDENS as STALE",
            rc == 1 and bool(stale_rows(out)) and not found(out, "derived"), "rc %d: %s" % (rc, out[-280:]))
        rc, out = run(*_pair(tmp / "stale-fixed", trimmed))
        arm("(f) and GREEN once the seal is re-derived from the trimmed file", rc == 0,
            "rc %d: %s" % (rc, out[-220:]))

        # (g) Fail-closed: every shape in which this gate must refuse instead of printing OK.
        rc, out = run(tmp / "absent" / HANDOFF, tmp / "absent" / "handoff_baseline.txt")
        arm("(g) a missing handoff exits 2 and never a green", rc == 2, "rc %d" % rc)
        d = tmp / "nohead"
        d.mkdir()
        (d / HANDOFF).write_text("# handoff\n\nno section headings at all\n", encoding="utf-8")
        _, good_seal = _pair(tmp / "nohead-seal", FIXTURE)
        rc, out = run(d / HANDOFF, good_seal)
        arm("(g) a handoff with no §2 exits 2 — the walk would have read nothing", rc == 2, out[-160:])
        h, s = _pair(tmp / "badseal", FIXTURE)
        s.write_text("# fixture\nbaseline_bytes not-a-number\nbaseline_lines 10\nsealed_at zzz\n",
                     encoding="utf-8")
        rc, out = run(h, s)
        arm("(g) a malformed seal exits 2", rc == 2, "rc %d: %s" % (rc, str(out)[:160]))
        _, got, bad = parse_seal("# f\nbaseline_bytes 1\nbaseline_lines 1\nsealed_at %s\n"
                                 "exempt\tderived\n" % FIXTURE_REV)
        arm("(g) a malformed exempt line is a complaint, never a silent skip",
            bool(bad) and not got, str(bad))
        _, _, bad = parse_seal("# f\nbaseline_bytes 1\nbaseline_lines 1\n")
        arm("(g) a missing field is a complaint too", bool(bad), str(bad))

        # (h) --reseal rewrites the population it just read, and PRINTS the delta it wrote.
        h, s = _pair(tmp / "reseal", FIXTURE, grown)
        rc_seal, seal_out = cap(reseal, h, s, rev=FIXTURE_REV)
        rc, out = run(h, s)
        arm("(h) --reseal rc 0, and the sealed file then reads GREEN", rc_seal == 0 and rc == 0,
            "seal rc %d; run rc %d: %s" % (rc_seal, rc, out[-200:]))
        fields, sites, bad = parse_seal(s.read_text(encoding="utf-8"))
        arm("(h) the seal it wrote parses back, with the injected rev and no complaints",
            not bad and fields["sealed_at"] == FIXTURE_REV and sum(x.count for x in sites) >= 2,
            str(bad))
        arm("(h) reseal printed the ceiling direction and the site delta",
            "GREW +" in seal_out and "FROZEN " in seal_out and "frozen sites" in seal_out,
            seal_out[:200])
        arm("(h) reseal kept the seal's own header (explanation survives, data is rewritten)",
            s.read_text(encoding="utf-8").startswith("# fixture seal"), "header gone")
        _, seal_out = cap(reseal, h, s, rev=FIXTURE_REV)
        arm("(h) resealing an unchanged file says UNCHANGED", "UNCHANGED" in seal_out,
            seal_out[:200])
        prose_trim = grown.replace(" — small on purpose, so every byte it grows is\n> attributable "
                                   "to the arm that grew it.", " — small on purpose.")
        rc, out = run(*_pair(tmp / "reseal-trim", grown, prose_trim))
        arm("(h) TRIMMING bytes off a looser seal is GREEN — smaller is always free", rc == 0,
            "rc %d: %s" % (rc, out[-200:]))
        rc, out = run(*_pair(tmp / "reseal-grow", trimmed, grown))
        arm("(h) GROWTH against a tighter seal REDDENS, which is the whole point of the guard",
            rc == 1 and "CEILING" in out, "rc %d: %s" % (rc, out[-200:]))

    if fails:
        print("FAIL: self-test — %d arm(s) did not behave" % fails)
        return 1
    print("OK: self-test — the ceiling tells two lines from a paragraph with neither half dead code, "
          "HISTORY keys on markers, its ⏳/⛔ and one-clause-ruling exemptions and its §2 scope proved, "
          "DERIVED reddens "
          "on every listed count shape and ignores a fenced example, the seal is proved in both "
          "directions, and --reseal prints what it froze")
    return 0


# ---------------------------------------------------------------- driver

def main() -> int:
    ap = argparse.ArgumentParser(
        prog="check_handoff_size.py",
        description="Prove the standing handoff cannot regrow: a size ceiling, a history-shape rule "
                    "and the derived-values ban. Read-only; --reseal writes only the seal.",
        epilog="exit 0 inside the seal · 1 finding(s) · 2 could not run")
    ap.add_argument("--verbose", action="store_true", help="list the frozen sites as well")
    ap.add_argument("--show-baseline", action="store_true",
                    help="print the seal body a re-seal would write (derived, never remembered)")
    ap.add_argument("--reseal", action="store_true",
                    help="rewrite the seal from the current handoff and print the delta — the merge "
                         "station's act, run after a trim lands")
    ap.add_argument("--self-test", action="store_true", help="breed each defect and require the red")
    args = ap.parse_args()

    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="backslashreplace")
        except (AttributeError, ValueError):
            pass

    if args.self_test:
        return self_test()
    if args.show_baseline:
        return show_baseline()
    if args.reseal:
        return reseal(ROOT / HANDOFF, ROOT / BASELINE)
    return report(ROOT / HANDOFF, ROOT / BASELINE, verbose=args.verbose)


if __name__ == "__main__":
    sys.exit(main())
