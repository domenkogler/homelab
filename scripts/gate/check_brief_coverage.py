#!/usr/bin/env python3
"""Gate: the row→brief map is ONE map, not three.

Why this file exists. Which brief carries which row is written down in three places, and nothing in
the suite compared them:

  * `todo-table.md` §B0 — the dispatch index. A table whose rows are briefs and whose "Rows it
    carries" cell lists the ids that brief owns;
  * every root `prompt-<domain>.md` brief — its dispatch header names the ids it carries
    ([todo.md](todo.md) **HD-436 · HD-435 · …**) and its prose names the rows its lane will read;
  * `prompt.md` §2 — the ranked pointer list, each item ending `→ [prompt-x.md]`, plus the parked
    table's `📋 brief` column.

Three copies of one decision is the shape this gate family exists to close. §B0 can hand a row to a
brief that never mentions it and the lane dispatched from that brief never reads work it owns (a row
no brief carries is read by nobody — the §B0 tail says so out loud); a brief can name a row §B0 gives
to a different lane, which is two writers on one row; and a dead id can sit in a brief unnoticed.
The neighbours are held and this seam is not: `check_view_registry_sync.py` holds the §B9 index
against `todo.md`, `check_todo_done.py --refs` holds brief-cited ids against `todo.md` rows.

Five rules, one finding line each, named by the FILE AND LINE that holds the claim:

  (a) §B0 assigns a row to a brief and the brief never cites it — dispatched, never read;
  (b) a brief claims a row that §B0 assigns to NO brief, or to a DIFFERENT brief (one id that §B0
      hands to two briefs is the same bug seen from the other side: one row, two lanes);
  (c) an id cited by any root `prompt*.md` is not an open `todo.md` row — the promise
      `check_todo_done.py --refs` already makes, extended to the ids that gate cannot see (rule (d));
  (d) a §B0↔brief relationship reachable only through cluster shorthand (`HD-480/481/482/483` or
      `HD-1120 · 1121 · 1122`) — printed separately, because `--refs` checks an abbreviated cluster by
      its HEAD only, so a relationship that exists only in shorthand is invisible to it;
  (e) `prompt.md` hands a row to a brief — in a §2 item block or a parked-table row — and §B0's cell
      omits it: the handoff and the dispatch index holding two opinions about who owns the work.

CLAIM versus CITATION is the distinction the rules turn on, and it is a declared limit, not an
accident. A brief's CLAIM is its dispatch header, the blockquote under its title: that is where a
brief states which rows it carries, and it is the list §B0's cell is supposed to mirror. Every other
id in a brief is a CITATION — a cross-reference to another lane's row ("HD-191 is the dependency, not
your work"), and the tree is full of legitimate ones; making prose mentions claims would print dozens
of findings that are all correct prose, which is the muted-gate failure every other gate here
documents having avoided. So (b) reads claims and (a)/(c) read citations: containment may be lenient,
a claim may not.

Counts are derived at run time and printed by the run (CONVENTIONS §2). An unbriefed total typed into
a view decays the moment a row is minted; this gate prints the live one, red or green alike. Ids are
compared on the numeric stem like the other view gates (`HD-04` and `HD-4` are one row) and a
letter-suffixed id is satisfied by its parent row exactly as `--refs` allows, so the two gates cannot
disagree about whether a row exists. Declared limits: an id §B0's cell writes as a bare bold number
with no `HD-` prefix is read as an id (that is the view's own convention and its own re-derive
command), and the same shape anywhere in PROSE is not — a bare number is prose (CONVENTIONS §4).

Carried debt lives in `scripts/gate/brief_coverage_baseline.txt`, keyed by the (brief, id) RELATION
rather than a bare id, and it fails in both directions like the other ledgers here: an uncarried
difference reddens, and a line whose difference cleared reddens as STALE.

Run:   python3 scripts/gate/check_brief_coverage.py [--verbose] [--self-test] [--show-baseline]
Exit:  0 = the three maps agree (the derived counts print either way);
       1 = any of the five rules fired, or a baseline line went stale;
       2 = cannot judge: a file is missing, §B0's table or its bounding heading vanished, a brief
           lost its dispatch header, or a corpus came back too small to trust.
Not wired into `validate-all.sh` yet; when it is, it belongs with the other view gates.
"""
from __future__ import annotations

import io
import re
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root  # noqa: E402

ROOT = _hl_root(__file__)
REGISTRY = ROOT / "todo.md"
VIEW = ROOT / "todo-table.md"
HANDOFF = ROOT / "prompt.md"
BASELINE = ROOT / "scripts" / "gate" / "brief_coverage_baseline.txt"

B0_HEAD = "### B0."
B0_TAIL = "### 🔥 Active lanes"       # §B0 is bounded by its neighbour heading, never by a line count
B0_ROW = re.compile(r"^\|\s*\[(prompt-[a-z0-9-]+\.md)\]")
B0_COL = "rows it carries"
# §B0's cell grammar IS the view's own documented re-derive command: `**469**` or `HD-1118`.
B0_ID = re.compile(r"\*\*(\d{2,4})\*\*|(?<![A-Za-z0-9])HD-(\d{1,4}[A-Za-z]?)")
ROW_RE = re.compile(r"^\|\s*HD-([0-9]+[A-Za-z]?)\s*\|")
STEM_RE = re.compile(r"^0*(\d+)([A-Za-z]?)$")
# The three shapes an id is written in. A cluster's TAIL numbers carry no `HD-` prefix, which is
# exactly what makes them invisible to a gate that greps the prefix — rule (d)'s whole subject. Two
# digits minimum everywhere: a single bare digit is prose (CONVENTIONS §4 — repeat the prefix).
ID_FORMS = (
    ("explicit", re.compile(r"(?<![A-Za-z0-9])HD-(\d{1,4}[A-Za-z]?)(?![\w-])")),
    ("slash", re.compile(r"(?<![A-Za-z0-9])HD-(\d{2,4}[A-Za-z]?)((?:/[ \t]*\d{2,4}[A-Za-z]?)+)"
                         r"(?![\w/-])")),
    ("dot", re.compile(r"(?<![A-Za-z0-9])HD-(\d{2,4}[A-Za-z]?)"
                       r"((?:[ \t]*(?:\n[ \t]*)?·[ \t]*(?:\n[ \t]*)?\d{2,4}[A-Za-z]?){1,8})(?![\w-])")),
)
ARROW = re.compile(r"→\s*\[(prompt-[a-z0-9-]+\.md)\]")
BRIEF_LINK = re.compile(r"\[(prompt-[a-z0-9-]+\.md)\]")
PARKED_COL = "📋 brief"
SHORTHAND = ("slash", "dot")
MAX_PRINTED = 20
RULE_HEADS = {
    "a": "row(s) §B0 assigns to a brief that never cites them — dispatched work nobody reads, which "
         "is how a row stops being real",
    "b": "row(s) a brief claims that §B0 assigns elsewhere or nowhere — a row cannot have two owners, "
         "and a row with none is read by nobody",
    "c": "id(s) a root brief cites that is not an open row — a closed row that outlived its citation "
         "(CONVENTIONS §4: the record goes to the doc + git, the line leaves the view)",
    "d": "row(s) whose §B0↔brief relationship exists only in cluster shorthand — "
         "check_todo_done.py --refs reads a cluster by its HEAD, so this link is invisible to it",
    "e": "row(s) prompt.md hands to a brief that §B0's cell omits — the handoff and the dispatch "
         "index disagree about who owns the work",
}


class BriefError(Exception):
    """The comparison cannot be made — a missing file, a vanished §B0 table, a brief whose header
    moved. A loud boundary; `main` turns it into exit 2, because the alternative is an empty map that
    reads as an agreement."""


def norm(raw: str) -> str:
    """`04` -> `HD-4`, `4a` -> `HD-4a`, `HD-04` -> `HD-4`. Idempotent: §B0's cells hand out bare bold
    numbers and the briefs hand out prefixed ids, so one difference in spelling would print as a
    difference in who owns the work."""
    stem = raw[3:] if raw.upper().startswith("HD-") else raw
    m = STEM_RE.match(stem)
    return f"HD-{m.group(1)}{m.group(2)}" if m else f"HD-{stem}"


def split_cells(line: str) -> list[str]:
    r"""A markdown row's cells, split on UNESCAPED pipes — the `check_md_tables.py` rule, so an
    escaped pipe inside a cell cannot shift which column this gate reads."""
    return [c.strip() for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]


def read(path: Path) -> str:
    if not path.is_file():
        raise BriefError(f"{path.name} is missing — the row→brief map has three copies and one is gone")
    return path.read_text(encoding="utf-8", errors="replace")


def key_of(name: str, ident: str) -> str:
    return f"{name}|{ident}"


# --------------------------------------------------------------------------- the three maps
def parse_registry(text: str) -> dict[str, int]:
    """Open `todo.md` rows as id -> line. ONE extraction with `check_view_registry_sync.py`: a row is
    a table row whose first cell is the id, and a fully-done row is deleted (CONVENTIONS §4), so what
    is in this file is what is open."""
    out: dict[str, int] = {}
    for n, ln in enumerate(text.splitlines(), 1):
        if (m := ROW_RE.match(ln)):
            out.setdefault(norm(m.group(1)), n)
    return out


def section(text: str, head: str, origin: str, tail: str | None = None) -> tuple[list[str], int]:
    """(the named section's lines, its first line number). The LAST heading wins, so a prose note
    quoting it is not mistaken for the section — the `check_view_registry_sync.py` rule. A named
    bounding heading that has gone is a boundary, never a guess."""
    lines = text.splitlines()
    starts = [i for i, ln in enumerate(lines) if ln.startswith(head)]
    if not starts:
        raise BriefError(f"{origin} has no section starting {head!r} — the copy of the row→brief map "
                         "this gate compares against is GONE, and an empty map is not an agreement")
    start = starts[-1]
    end = len(lines)
    if tail is not None:
        stops = [i for i in range(start + 1, len(lines)) if lines[i].startswith(tail)]
        if not stops:
            raise BriefError(f"{origin} §B0 is not bounded by {tail!r}: where the lane-brief table "
                             "ends is where this gate stops reading, and guessing that line would "
                             "read the next table's rows as brief assignments")
        end = stops[0]
    return lines[start:end], start + 1


def parse_b0(view_text: str) -> dict[str, dict[str, int]]:
    """brief -> {id: §B0 line}, read out of the lane-brief table's "Rows it carries" column. The
    column is found by its HEADER text, so a view that re-orders its columns is read correctly or
    refused — never read as some other column."""
    lines, offset = section(view_text, B0_HEAD, VIEW.name, B0_TAIL)
    header = next((i for i, ln in enumerate(lines) if ln.startswith("| Brief |")), None)
    if header is None:
        raise BriefError(f"{VIEW.name} §B0 has no `| Brief |` header row — the lane-brief table is "
                         "not the table this gate was written against")
    cols = split_cells(lines[header])
    wanted = next((i for i, c in enumerate(cols) if B0_COL in c.lower()), None)
    if wanted is None:
        raise BriefError(f"{VIEW.name} §B0 has no {B0_COL!r} column — the cell this gate reads ids "
                         "out of has moved or been renamed")
    out: dict[str, dict[str, int]] = {}
    for i, ln in enumerate(lines):
        m = B0_ROW.match(ln)
        if not m:
            continue
        cells = split_cells(ln)
        if len(cells) <= wanted:
            raise BriefError(f"{VIEW.name}:{offset + i} is a brief row with {len(cells)} cell(s) "
                             f"against a {len(cols)}-cell header — a wrapped view row hides every "
                             "cell after the break (check_md_tables.py)")
        for mm in B0_ID.finditer(cells[wanted]):
            out.setdefault(m.group(1), {}).setdefault(norm(mm.group(1) or mm.group(2)), offset + i)
    return out


def dispatch_header(text: str, origin: str) -> tuple[str, int]:
    """The brief's CLAIM block: the blockquote under its `# ` title, where a brief states "the rows
    are the authority … [todo.md](todo.md) **HD-x · HD-y**". Located structurally, so a brief that
    re-wraps its header is still read; a brief whose header moved is a boundary, because without the
    claim/citation boundary this gate cannot tell a claim from a cross-reference."""
    lines = text.splitlines()
    title = next((i for i, ln in enumerate(lines) if ln.startswith("# ")), None)
    if title is None:
        raise BriefError(f"{origin} has no `# ` title — its dispatch header cannot be located")
    body: list[str] = []
    for i in range(title + 1, len(lines)):
        ln = lines[i]
        if ln.startswith(">"):
            body.append(ln)
        elif body or ln.strip():
            break
    if not body:
        raise BriefError(f"{origin} has no blockquote under its title — a brief states the rows it "
                         "carries there, and this gate cannot tell a claim from a cross-reference "
                         "without it")
    return "\n".join(body), title + 1


def cites(text: str, line0: int = 1) -> dict[str, dict[str, int]]:
    """id -> {form: line} for every id a chunk of markdown cites, in each shape it is written in. A
    cluster's HEAD is recorded in the cluster's form and in `explicit`; a TAIL number appears only in
    the cluster's form — that asymmetry IS rule (d)."""
    out: dict[str, dict[str, int]] = {}
    for form, rx in ID_FORMS:
        for m in rx.finditer(text):
            line = line0 + text.count("\n", 0, m.start())
            found = [m.group(1)]
            if m.lastindex and m.lastindex > 1 and m.group(2):
                found += re.findall(r"\d{2,4}[A-Za-z]?", m.group(2))
            for raw in found:
                out.setdefault(norm(raw), {}).setdefault(form, line)
    return out


def parse_handoff(text: str) -> list[tuple[str, str, int, int]]:
    """[(brief, id, first line, last line)] for every row the handoff hands to a brief: each §2 item
    block — a numbered item, closed by the `→ [prompt-x.md]` that names its brief, which may sit after
    a line break — and the parked table, whose `📋 brief` column names the brief for that row."""
    lines, offset = section(text, "## 2.", HANDOFF.name)
    found: list[tuple[str, str, int, int]] = []
    begin: int | None = None
    for i, ln in enumerate(lines):
        if re.match(r"^\s*\d+\.\s", ln):
            begin = i                      # a new item starts a new claim block
        arrow = ARROW.search(ln)
        end = i
        if not arrow and ln.rstrip().endswith("→") and i + 1 < len(lines):
            # The arrow may ride the wrap: `… →` here, the brief's link on the next line.
            arrow, end = BRIEF_LINK.search(lines[i + 1]), i + 1
        if arrow and begin is not None:
            for ident in cites("\n".join(lines[begin:end + 1]), offset + begin):
                found.append((arrow.group(1), ident, offset + begin, offset + end))
            begin = None
    # The parked table is the third copy of the map. It may legitimately be ABSENT — nothing parked
    # is a real state — but a table keyed on `HD` whose brief column was renamed is a map this gate
    # would read as empty, and an empty read is the failure mode every gate here refuses.
    head = next((i for i, ln in enumerate(lines) if PARKED_COL in ln), None)
    if head is None:
        keyed = next((i for i, ln in enumerate(lines) if re.match(r"^\|\s*HD\s*\|", ln)), None)
        if keyed is not None:
            raise BriefError(f"{HANDOFF.name}:{offset + keyed} is an `HD`-keyed table with no "
                             f"{PARKED_COL!r} column — a parked row with no brief named is a copy of "
                             "the row→brief map this gate cannot read")
        return found
    for i in range(head + 1, len(lines)):
        if not lines[i].startswith("|"):
            break
        cells = split_cells(lines[i])
        brief = next((m.group(1) for c in cells if (m := BRIEF_LINK.search(c))), None)
        if not brief:
            continue
        # The row's own cells, minus the brief cell: a filename is not a row claim.
        for ident in cites(" ".join(c for c in cells if not BRIEF_LINK.search(c)), offset + i):
            found.append((brief, ident, offset + i, offset + i))
    return found


def read_baseline(path: Path) -> dict[tuple[str, str], str]:
    """(brief, id) -> why the repo carries the difference. An absent file means nothing legitimately
    differs, which is the expected state: a baseline here is the exception path, not the normal one."""
    if not path.is_file():
        return {}
    out: dict[tuple[str, str], str] = {}
    for ln in path.read_text(encoding="utf-8").splitlines():
        if ln.strip() and not ln.startswith("#"):
            parts = ln.split("\t")
            if len(parts) >= 2:
                out[(parts[0].strip(), norm(parts[1]))] = parts[2].strip() if len(parts) > 2 else ""
    return out


# --------------------------------------------------------------------------- the verdict
def analyse(registry: str, view: str, handoff: str,
            briefs: dict[str, str]) -> dict:
    """All three maps, from file text. One place builds them so the self-test can breed a canary by
    editing text instead of a tree."""
    claims: dict[str, dict[str, dict[str, int]]] = {}
    quoted: dict[str, dict[str, dict[str, int]]] = {}
    for name, text in briefs.items():
        header, start = dispatch_header(text, name)
        claims[name] = cites(header, start + 1)
        quoted[name] = cites(text)
    all_cites = dict(quoted)
    all_cites[HANDOFF.name] = cites(handoff)
    return {"rows": parse_registry(registry), "b0": parse_b0(view), "claims": claims,
            "cites": quoted, "all_cites": all_cites, "handoff": parse_handoff(handoff)}


def owner_of(b0: dict[str, dict[str, int]], ident: str) -> list[str]:
    return sorted(brief for brief, ids in b0.items() if ident in ids)


def is_open(rows: dict[str, int], ident: str) -> bool:
    """A letter-suffixed id is satisfied by its PARENT row — the `check_todo_done.py --refs` rule,
    kept identical so the two gates cannot disagree about whether a row exists."""
    if ident in rows:
        return True
    m = re.match(r"^(HD-\d+)[A-Za-z]$", ident)
    return bool(m) and m.group(1) in rows


def counts(rows: dict[str, int], b0: dict[str, dict[str, int]]) -> tuple[int, int, int]:
    """(open rows, briefed, unbriefed) — counted here, never carried. §B0 may still name an id that is
    no longer a row; only ids that ARE rows can count as briefed, or the two halves would not add up
    to the registry, and that is the sum the §B0 tail quotes."""
    briefed = {ident for ids in b0.values() for ident in ids if ident in rows}
    return len(rows), len(briefed), len(rows) - len(briefed)


def verdict(data: dict) -> tuple[dict[str, dict[str, str]], dict[str, str]]:
    """(findings by rule, the fired relations by key). The second half is what makes a baseline line
    PROVABLE: it is the set a carried difference is checked against, so a line whose difference has
    gone cannot stay behind as a mute with a reason attached."""
    rows, b0, claims = data["rows"], data["b0"], data["claims"]
    quoted, all_cites = data["cites"], data["all_cites"]
    out: dict[str, dict[str, str]] = {k: {} for k in RULE_HEADS}
    fired: dict[str, str] = {}

    def add(rule: str, name: str, ident: str, text: str) -> None:
        # One line per relation, naming its FIRST site: the same claim written twice is one finding,
        # and a baseline line keyed on the pair must not depend on which copy was read last.
        fired.setdefault(key_of(name, ident), text)
        out[rule].setdefault(key_of(name, ident), text)

    # (a) §B0 assigns it, the brief never cites it: dispatched, and never read.
    for brief, ids in sorted(b0.items()):
        missing_file = brief not in quoted      # the index names a brief that is not in the tree
        for ident, line in sorted(ids.items()):
            if ident in quoted.get(brief, {}):
                continue
            add("a", brief, ident,
                f"{VIEW.name}:{line}  {ident} → {brief} — "
                + (f"§B0 assigns this row to a brief that is NOT in the tree, so no lane can be "
                   f"dispatched from it" if missing_file else
                   "§B0 assigns this row to the brief and the brief never cites it: the lane is "
                   "dispatched FROM the brief, so the work is never read"))
    # (b) a brief claims a row the index does not give it — or gives to somebody else too.
    for brief, ids in sorted(claims.items()):
        for ident, forms in sorted(ids.items()):
            line, owners = min(forms.values()), owner_of(b0, ident)
            if brief not in owners:
                add("b", brief, ident,
                    f"{brief}:{line}  {ident} — the brief claims this row and §B0 assigns it to "
                    + ("NO brief, so it sits in the unbriefed tail and no lane reads it"
                       if not owners else "another brief: " + ", ".join(owners)))
            elif len(owners) > 1:
                add("b", brief, ident,
                    f"{brief}:{line}  {ident} — §B0 assigns this one row to {len(owners)} briefs ("
                    + ", ".join(owners) + "): two lanes, one row")
    # (c) an id any root brief names that is not an open row: a dead id in a dispatch note.
    for name, ids in sorted(all_cites.items()):
        for ident, forms in sorted(ids.items()):
            if not is_open(rows, ident):
                add("c", name, ident,
                    f"{name}:{min(forms.values())}  {ident} — cited by a root brief, no open row in "
                    f"{REGISTRY.name} (written as: {', '.join(sorted(forms))})")
    # (d) the relationship holds only through shorthand, which a prefix-grep cannot see.
    for brief, ids in sorted(b0.items()):
        for ident, line in sorted(ids.items()):
            forms = quoted.get(brief, {}).get(ident, {})
            if forms and all(f in SHORTHAND for f in forms):
                add("d", brief, ident,
                    f"{VIEW.name}:{line}  {ident} → {brief} — the brief cites it only as "
                    + "/".join(sorted(forms)) + " shorthand, so check_todo_done.py --refs (which "
                    "checks a cluster by its HEAD) cannot see this relationship")
    for brief, ids in sorted(claims.items()):
        for ident, forms in sorted(ids.items()):
            if all(f in SHORTHAND for f in forms) and brief in owner_of(b0, ident):
                add("d", brief, ident,
                    f"{brief}:{min(forms.values())}  {ident} — the brief claims it only through "
                    "cluster shorthand, so no prefix-grep can see that this brief carries the row")
    # (e) the handoff and the index disagree about who carries the row.
    for brief, ident, first, last in sorted(data["handoff"], key=lambda x: (x[0], x[2])):
        if not is_open(rows, ident):
            continue     # a closed row belongs to no cell: §4(a) deletes the view's line with the row
        owners = owner_of(b0, ident)
        if brief not in owners:
            span = str(first) if first == last else f"{first}-{last}"
            add("e", brief, ident,
                f"{HANDOFF.name}:{span}  {ident} → {brief} — the handoff hands this row to that brief "
                "and §B0's cell for it omits it (§B0 gives it to "
                + (", ".join(owners) if owners else "nobody") + ")")
    return out, fired


def report(data: dict, exempt: dict[tuple[str, str], str], verbose: bool = False) -> int:
    out, fired = verdict(data)
    carried = {key_of(*combo) for combo in exempt}
    hits = {rule: {k: v for k, v in items.items() if k not in carried} for rule, items in out.items()}
    stale = sorted(key for key in exempt if key_of(*key) not in fired)
    open_rows, briefed, unbriefed = counts(data["rows"], data["b0"])
    print(f"{VIEW.name} §B0 {sum(len(v) for v in data['b0'].values())} assignment(s) over "
          f"{len(data['b0'])} brief(s); {len(data['claims'])} brief header(s); {len(data['handoff'])} "
          f"handoff assignment(s); {len(data['rows'])} open row(s)"
          + (f"; {len(exempt)} difference(s) carried in the baseline" if exempt else ""))
    if stale:
        print(f"STALE baseline line(s): {len(stale)} — the difference each one carries is gone, so the "
              "line is no longer a reason, it is a free pass for the next drift; re-derive with "
              "--show-baseline:")
        for key in stale[:MAX_PRINTED]:
            print(f"  {key_of(*key)}")
    total = 0
    for rule, items in sorted(hits.items()):
        if not items:
            continue
        total += len(items)
        print(f"FAIL({rule}): {len(items)} {RULE_HEADS[rule]}:")
        for line in list(items.values())[:MAX_PRINTED]:
            print(f"  {line}")
        if len(items) > MAX_PRINTED:
            print(f"  … {len(items) - MAX_PRINTED} more, same rule")
    print(f"DERIVED: {open_rows} open row(s) in {REGISTRY.name} · {briefed} briefed (§B0) · "
          f"{unbriefed} unbriefed — counted by this run, never copied from prose")
    if verbose:
        for brief, ids in sorted(data["b0"].items()):
            print(f"  {brief}: §B0 {len(ids)} row(s) · header claims "
                  f"{len(data['claims'].get(brief, {}))} · cites {len(data['cites'].get(brief, {}))}")
    if total or stale:
        print("Fix the map in the commit that moved the row: §B0's cell, the brief's dispatch header "
              "and prompt.md's pointer must say the same thing in ONE commit. A difference the repo "
              "decides to CARRY goes in brief_coverage_baseline.txt with its reason "
              "(--show-baseline re-derives the body).")
        return 1
    print(f"OK: §B0, the {len(data['claims'])} brief header(s) and prompt.md name the same rows — the "
          "diff is empty in every direction"
          + ("" if exempt else " (no baseline: nothing legitimately differs)"))
    return 0


# --------------------------------------------------------------------------- self-test
B0_TAIL_ROW = "\n" + B0_TAIL + "\n\n| HD | Goal |\n|----|------|\n"


def brief_text(rows: str, body: str = "") -> str:
    return ("# `prompt-alpha.md` — Lane brief · the alpha domain\n\n"
            "> **Role:** dispatch note for one lane. **The rows are the authority:** "
            f"[todo.md](todo.md) {rows}.\n"
            "> **Linked from:** [todo-table.md](todo-table.md) §B0\n\n"
            f"{body}\n")


def fixture(tmp: Path, rows: list[str], b0_rows: list[str], briefs: dict[str, str],
            handoff: str) -> dict[str, str]:
    """The three maps as text in one throwaway directory — the pool runs read-only and a self-test
    that rewrote a root view would be the flake class the repo already retired."""
    (tmp / "todo.md").write_text("# registry\n\n"
                                 + "\n".join(f"| HD-{i} | 2 | AI | 1 | **row {i}** |" for i in rows)
                                 + "\n", encoding="utf-8")
    (tmp / "todo-table.md").write_text(
        "# view\n\n### B0. Lane briefs\n\n| Brief | Wave | Rows it carries | Converge host |\n"
        "|-----|------|-----------------|---------------|\n" + "\n".join(b0_rows) + B0_TAIL_ROW
        + "\n## C. rules\n", encoding="utf-8")
    (tmp / "prompt.md").write_text(handoff, encoding="utf-8")
    for name, text in briefs.items():
        (tmp / name).write_text(text, encoding="utf-8")
    texts = {name: (tmp / name).read_text(encoding="utf-8") for name in briefs}
    texts[HANDOFF.name] = (tmp / "prompt.md").read_text(encoding="utf-8")
    return texts


def self_test() -> int:
    fails = 0

    def check(label: str, ok: bool, detail: str = "") -> None:
        nonlocal fails
        fails += not ok
        print(f"  arm {label}: {'ok' if ok else 'FAIL'}{(' — ' + detail) if (detail and not ok) else ''}")

    PAIR = ("# handoff\n\n## 2. Next tasks\n\n1. ⏳ **The alpha lane** — **HD-100** and **HD-101** "
            "in one window. →\n   [prompt-alpha.md](prompt-alpha.md)\n")
    B0_PAIR = ("| [prompt-alpha.md](prompt-alpha.md) the alpha domain | **1** | **100** · **101** | "
               "oldsrv |")

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)

        def breed(rows: list[str], b0_rows: list[str], briefs: dict[str, str], handoff: str,
                  baseline: list[str] | None = None) -> tuple[int, str]:
            texts = fixture(tmp, rows, b0_rows, briefs, handoff)
            data = analyse((tmp / "todo.md").read_text(encoding="utf-8"),
                           (tmp / "todo-table.md").read_text(encoding="utf-8"),
                           texts[HANDOFF.name],
                           {k: v for k, v in texts.items() if k != HANDOFF.name})
            exempt: dict[tuple[str, str], str] = {}
            if baseline is not None:
                path = tmp / "baseline.txt"
                path.write_text("# test baseline\n" + "\n".join(baseline) + "\n", encoding="utf-8")
                exempt = read_baseline(path)
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = report(data, exempt)
            return rc, buf.getvalue()

        brief = brief_text("**HD-100 · HD-101**")

        # (0) the reconciled pair: three maps that agree, and the counts DERIVED rather than quoted.
        rc, out = breed(["100", "101"], [B0_PAIR], {"prompt-alpha.md": brief}, PAIR)
        check("the reconciled §B0/brief pair is GREEN and prints derived counts",
              rc == 0 and "DERIVED: 2 open row(s)" in out and "2 briefed (§B0)" in out
              and "0 unbriefed" in out and "FAIL" not in out, f"rc {rc}: {out.strip()[:160]}")

        # (a) §B0 hands the brief a row it never mentions — dispatched work the lane never reads. This
        # is the shape a §B0 edit that widens a cell without touching the brief produces.
        rc, out = breed(["100", "101", "102"],
                        [B0_PAIR.replace("**101**", "**101** · **102**")],
                        {"prompt-alpha.md": brief}, PAIR)
        check("(a) a row §B0 assigns that the brief never cites REDDENS, naming both sides",
              rc == 1 and "FAIL(a)" in out and "HD-102" in out and "prompt-alpha.md" in out
              and f"{VIEW.name}:" in out, f"rc {rc}: {out.strip()[:160]}")
        # …and the same pair reconciled: the brief now names the row, and the finding is gone.
        rc, out = breed(["100", "101", "102"],
                        [B0_PAIR.replace("**101**", "**101** · **102**")],
                        {"prompt-alpha.md": brief_text("**HD-100 · HD-101 · HD-102**")},
                        PAIR.replace("**HD-100** and **HD-101**", "**HD-100**, **HD-101**, **HD-102**"))
        check("(a) the same pair with the brief updated is GREEN", rc == 0, f"rc {rc}: {out.strip()[:160]}")

        # (b) the brief claims a row the index gives to nobody…
        rc, out = breed(["100", "101"], [B0_PAIR.replace(" · **101**", "")],
                        {"prompt-alpha.md": brief}, PAIR)
        check("(b) a brief claims a row §B0 assigns to NO brief → RED",
              rc == 1 and "FAIL(b)" in out and "HD-101" in out and "NO brief" in out,
              f"rc {rc}: {out.strip()[:160]}")
        # …and the same row handed to a second brief: one row, two lanes.
        beta = brief_text("**HD-101**").replace("prompt-alpha.md", "prompt-beta.md")
        rc, out = breed(["100", "101"],
                        [B0_PAIR, "| [prompt-beta.md](prompt-beta.md) beta | **1** | **101** | nas |"],
                        {"prompt-alpha.md": brief, "prompt-beta.md": beta}, PAIR)
        check("(b) one row assigned to TWO briefs → RED, naming both",
              rc == 1 and "FAIL(b)" in out and "2 briefs" in out, f"rc {rc}: {out.strip()[:160]}")

        # (c) a dead id in a brief — in the shape --refs already catches, and in the shape it cannot.
        rc, out = breed(["100", "101"], [B0_PAIR],
                        {"prompt-alpha.md": brief_text("**HD-100 · HD-999**")}, PAIR)
        check("(c) an id a brief cites with no open row → RED",
              rc == 1 and "FAIL(c)" in out and "HD-999" in out and "prompt-alpha.md:3" in out,
              f"rc {rc}: {out.strip()[:160]}")
        rc, out = breed(["100", "101"], [B0_PAIR],
                        {"prompt-alpha.md": brief_text("**HD-100** and HD-101/999 are one writer")}, PAIR)
        check("(c) a dead id reachable ONLY through slash shorthand → RED (the --refs blind spot)",
              rc == 1 and "FAIL(c)" in out and "HD-999" in out and "slash" in out,
              f"rc {rc}: {out.strip()[:160]}")

        # (d) the relationship holds, but only because of shorthand.
        rc, out = breed(["100", "101"], [B0_PAIR],
                        {"prompt-alpha.md": brief_text("**HD-100** — the resolver work in "
                                                       "HD-100/101 is one writer")}, PAIR)
        check("(d) a §B0↔brief link carried only by cluster shorthand is printed as its own rule",
              rc == 1 and "FAIL(d)" in out and "shorthand" in out and "HD-101" in out,
              f"rc {rc}: {out.strip()[:160]}")

        # (e) the handoff's §2 item, then its parked table — the third copy of the map.
        split = B0_PAIR.replace(" · **101**", "") + ("\n| [prompt-beta.md](prompt-beta.md) beta | "
                                                     "**1** | **101** | nas |")
        rc, out = breed(["100", "101"], [split],
                        {"prompt-alpha.md": brief_text("**HD-100**"),
                         "prompt-beta.md": brief_text("**HD-101**").replace("prompt-alpha.md",
                                                                            "prompt-beta.md")}, PAIR)
        check("(e) prompt.md hands a row to a brief §B0 gives to ANOTHER brief → RED, naming both",
              rc == 1 and "FAIL(e)" in out and "prompt.md:" in out and "prompt-beta.md" in out
              and "FAIL(b)" not in out, f"rc {rc}: {out.strip()[:160]}")
        rc, out = breed(["100", "101"], [B0_PAIR],
                        {"prompt-alpha.md": brief_text("**HD-100 · HD-101**")}, PAIR)
        check("(e) the same handoff item whose brief §B0 also names is GREEN",
              rc == 0, f"rc {rc}: {out.strip()[:160]}")
        pair100 = PAIR.replace(" and **HD-101**", "")     # so the parked row is the only claim here
        parked = pair100 + ("\n| HD | the one blocked action | host | " + PARKED_COL
                         + " |\n|----|---------------------|------|-----------|\n"
                         "| **HD-101** | one owner act | nas | [prompt-alpha.md](prompt-alpha.md) |\n")
        rc, out = breed(["100", "101"], [split],
                        {"prompt-alpha.md": brief_text("**HD-100**"),
                         "prompt-beta.md": brief_text("**HD-101**").replace("prompt-alpha.md",
                                                                           "prompt-beta.md")}, parked)
        check("(e) a parked-table row that §B0's cell omits → RED, naming the parked line",
              rc == 1 and "FAIL(e)" in out and "prompt.md:10" in out, f"rc {rc}: {out.strip()[:160]}")
        # …and the reconciled parked row: §B0 names it, so the third copy agrees with the other two.
        rc, out = breed(["100", "101"], [B0_PAIR], {"prompt-alpha.md": brief}, parked)
        check("(e) a parked row §B0 also names is GREEN", rc == 0, f"rc {rc}: {out.strip()[:160]}")

        # the ledger ratchet both ways: carried debt is quiet, cleared debt is STALE.
        rc, out = breed(["100", "101"], [B0_PAIR.replace(" · **101**", "")],
                        {"prompt-alpha.md": brief}, PAIR,
                        baseline=["prompt-alpha.md\tHD-101\tWHY — a seat brief claims legs, not rows"])

        check("a baselined (brief, id) relation is quiet and says so",
              rc == 0 and "carried in the baseline" in out, f"rc {rc}: {out.strip()[:160]}")
        rc, out = breed(["100", "101"], [B0_PAIR], {"prompt-alpha.md": brief}, PAIR,
                        baseline=["prompt-alpha.md\tHD-999\tWHY — cleared"])
        check("a baseline line whose difference cleared prints STALE",
              rc == 1 and "STALE" in out, f"rc {rc}: {out.strip()[:160]}")

        # boundaries: a vanished §B0, a §B0 whose bounding heading moved, a brief whose header moved.
        try:
            parse_b0("# view\n\n## B. something\n\n" + B0_PAIR + "\n")
            check("a vanished §B0 is loud, never an empty map", False, "parse_b0() returned quietly")
        except BriefError as exc:
            check("a vanished §B0 is loud, never an empty map", "GONE" in str(exc), str(exc)[:90])
        try:
            parse_b0("# view\n\n" + B0_HEAD + "\n\n" + B0_PAIR + "\n\n## C. rules\n")
            check("a §B0 without its bounding heading refuses to be guessed", False, "it guessed")
        except BriefError as exc:
            check("a §B0 without its bounding heading refuses to be guessed", "bounded" in str(exc),
                  str(exc)[:90])
        try:
            dispatch_header("# no header\n\nprose only\n", "prompt-x.md")
            check("a brief with no dispatch header is loud", False, "it returned quietly")
        except BriefError as exc:
            check("a brief with no dispatch header is loud", "blockquote" in str(exc), str(exc)[:90])

        # an empty corpus is a broken root, never a clean tree — the rule every checker here obeys.
        # Both probes PARSE a file: a floor that never sees a real walk proves nothing about the walk.
        bare_reg = tmp / "bare-todo.md"
        bare_reg.write_text("# registry\n\n| Row | P |\n|-----|---|\n", encoding="utf-8")
        bare_view = tmp / "bare-view.md"
        bare_view.write_text("# view\n\n" + B0_HEAD + "\n\n| Brief | Wave | Rows it carries | Host |\n"
                             "|-------|------|------------------|------|" + B0_TAIL_ROW, encoding="utf-8")
        for what, probe in (("todo.md rows", parse_registry(bare_reg.read_text(encoding="utf-8"))),
                            ("§B0 brief rows", parse_b0(bare_view.read_text(encoding="utf-8")))):
            try:
                require_corpus(len(probe), 40, what)
                check(f"an empty corpus refuses: {what}", False, "the floor did not fire")
            except SystemExit:
                check(f"an empty corpus refuses: {what}", True)

        # the grammars, pinned directly: cluster tails are seen, dates and prose numbers are not ids.
        found = cites("HD-480/481/482/483/488 and **HD-1120 · 1121 · 1122**")
        check("slash and dot clusters read their tails",
              set(found) == {"HD-480", "HD-481", "HD-482", "HD-483", "HD-488",
                             "HD-1120", "HD-1121", "HD-1122"}, str(sorted(found)))
        check("a cluster tail is shorthand, its head is not — that is what rule (d) reads",
              set(found["HD-488"]) == {"slash"} and "explicit" in found["HD-480"],
              str(found["HD-488"]))
        noise = cites("**HD-436** (owner 2026-10-20): 3 rules · 1 window · 4 converge slots")
        check("a date, a bare number and a `·`-separated count are prose, not rows",
              set(noise) == {"HD-436"}, str(sorted(noise)))
        check("HD-04 and HD-4 are one row", norm("04") == norm("4") == norm("HD-04") == "HD-4",
              norm("04"))

    print(f"check_brief_coverage.py --self-test: {fails} failing arm(s)")
    return 1 if fails else 0


# --------------------------------------------------------------------------- main
def main() -> int:
    argv = sys.argv[1:]
    if "--self-test" in argv:
        print("check_brief_coverage.py --self-test")
        return self_test()
    try:
        registry, view, handoff = read(REGISTRY), read(VIEW), read(HANDOFF)
        briefs = {p.name: read(p) for p in sorted(ROOT.glob("prompt-*.md"))}
    except BriefError as exc:
        print(f"SKIP: {exc} — an unreadable view is an environment boundary, not a green")
        return 2
    rows, b0 = parse_registry(registry), parse_b0(view)
    require_corpus(len(rows), 40, "todo.md registry rows")
    require_corpus(len(b0), 8, "brief rows in todo-table.md §B0")
    require_corpus(len(briefs), 8, "root prompt-*.md briefs")
    require_corpus(sum(len(v) for v in b0.values()), 30, "ids §B0 assigns to briefs")
    require_corpus(len(parse_handoff(handoff)), 5, "row→brief assignments in prompt.md")
    data = analyse(registry, view, handoff, briefs)
    if "--show-baseline" in argv:
        # STDOUT is the ledger body, so every informational line goes to stderr — the redirect must
        # write a clean file (the check_doc_path_refs.py discipline).
        out, _fired = verdict(data)
        print(f"# re-derived by scripts/gate/{Path(__file__).name} --show-baseline", file=sys.stderr)
        print("# one line per difference: <brief file>TAB<id>TAB<why the repo carries it>. A line "
              "whose difference cleared reddens, so this file is a ratchet and never a mute.",
              file=sys.stderr)
        lines = 0
        for rule, items in sorted(out.items()):
            for combo, text in items.items():
                brief, _, ident = combo.partition("|")
                print(f"{brief}\t{ident}\tWHY (rule {rule}) — name the reason; an unexplained line "
                      "is a mute")
                print(f"# {text}", file=sys.stderr)
                lines += 1
        print(f"--show-baseline: {lines} line(s) — carry one only for a difference the repo has "
              "DECIDED to keep", file=sys.stderr)
        return 0
    return report(data, read_baseline(BASELINE), verbose="--verbose" in argv)


if __name__ == "__main__":
    sys.exit(main())
