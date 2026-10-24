#!/usr/bin/env python3
"""check_open_questions.py — an open question is an addressable `Options` section, and this proves it.

WHY THIS EXISTS. CONVENTIONS §8.3: an open question lives in an `Options` section in its OWNING doc, keyed by
its `OQ-<n>` id — the counterpart of the `<domain>-rejected.md` log, and its open half. Before that landed, an
unresolved choice was prose in `todo.md` §1 or a sentence in a doc, and `rg '^## Options' docs/` answered with
nothing while two docs carried an ad-hoc `## Open Questions` heading. Two docs now carry the shape (OQ-14 in
`docs/services-ai.md` §9b, OQ-15 in `docs/backup.md`); nothing mechanical said so, which makes "the table is
shaped to the grammar" a row's word rather than a fact. Four rules, each with a canary in `--self-test`:

  shape        the section — from its heading to the next heading of the same or a higher level — carries a
               table with the header exactly `| Option | For | Against | Cost | Cheap test |`, TWO OR MORE
               option rows, and a non-empty `Cheap test` cell in every row. The cheap test is what makes the
               section cheaper to answer than to argue; a row without one is a wish, and an "option set" of
               one row is a verdict with a table around it. A row whose cell count differs from the header's is
               a finding too: the rows are read POSITIONALLY, so a sixth cell shifts `Cheap test` out of the
               column the rule is reading and every check below it silently reads the wrong column.
  key          the section names the `OQ-<n>` id it answers — that is what makes the inventory addressable
               instead of a heading census.
  no-verdict   no `recommend…` / `decided` / `decision:` wording inside the section. An option is never a
               decision dressed as an option: the ruling is the owner's act and when it lands it lands as
               state prose in the doc, or as a row in `<domain>-rejected.md` (§8.3, and the state-only rule in
               §6). §8.3 also says an ANSWERED question leaves no `Options` section behind, so a section that
               states the answer is a changelog wearing a table.
  mint         the id space is DERIVED and printed (max, the sorted list, the next id), because §8.3 and §2 ban
               typing the number: the next id is max+1 over every `OQ-<n>` already in the tracked `*.md`. A
               section naming an id above max+1 typed a number rather than deriving one, and a hand-typed id is
               how two docs minting at once collide. The mint basis deliberately EXCLUDES the `Options` heading
               lines themselves: a rule that reads the number from the same line it audits can never fire, so an
               id would certify itself. max+1 is still legal, which is what lets a fresh derived mint through —
               the gate blocks a typed number, never a derived one.

The run prints the inventory command it mirrors, `rg -n '^#{2,3} Options' docs/`, so the list a reader could
re-type is the list the gate actually read.

WHAT THIS DOES NOT CHECK, on purpose:
  * an open choice written as `## Open Questions` bullets or as prose is INVISIBLE here. The gate shapes what
    EXISTS; the inventory command is a floor, not a census. That is the row's declared blind spot, and §8.3 is
    explicit that a to-do checklist is not a choice: `docs/services-finance.md`, `docs/smart-home.md` and
    `docs/smart-home-failover.md` keep prose headings on purpose and are not to be converted.
  * not `# Options` at level 1, and not a setext heading — §8.3 binds level 2 or 3, and the mirrored `rg`
    pattern is ATX-only, so the gate and the inventory command stay blind in exactly the same places.
  * not whether the CONTENT is a real option set: no gate can tell an argument from a genuine pair. It counts
    rows, cells and words.
  * not the answered-question rule beyond the wording ban — deciding that a question IS answered is the
    owner's act, and the answer leaves as state prose plus a `-rejected.md` row.
  * not a heading outside `docs/`. The section scan walks tracked `docs/**/*.md` (the inventory command's own
    scope); the mint basis walks every tracked `*.md`, because ids are named in `todo.md`, the briefs and the
    frozen `reports/` probes too.

Run:   python3 scripts/gate/check_open_questions.py [--show] [--verbose] [--self-test]
Exit:  0 clean · 1 finding(s) · 2 could not run (no tracked docs, or a mint corpus that could not be read — a
       corpus a gate cannot read is never a pass). Stdlib + git only; no network, no vault, no host.
"""
from __future__ import annotations

import argparse
import contextlib
import io
import re
import subprocess
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass
# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root  # noqa: E402

ROOT = _hl_root(__file__)

# The grammar §8.3 defines, in ONE place. `OPTION_HEADER` is what the section must carry; `HEADER_TEXT` is how
# the finding writes it back so the reader can diff the two without opening the convention.
OPTION_HEADER = ["Option", "For", "Against", "Cost", "Cheap test"]
HEADER_TEXT = "| " + " | ".join(OPTION_HEADER) + " |"
INVENTORY_CMD = r"rg -n '^#{2,3} Options' docs/"
MINT_CMD = r"git grep -hoE 'OQ-[0-9]+' -- '*.md' | sed 's/OQ-//' | sort -n | tail -1"

HEAD_RE = re.compile(r"^(#{1,6})[ \t]+(.*)$")
OPTIONS_HEAD = re.compile(r"^#{2,3}[ \t]+Options\b")
FENCE_RE = re.compile(r"^[ \t]*(?:```|~~~)")
ROW_RE = re.compile(r"^[ \t]*\|")
SEP_ROW_RE = re.compile(r"^[ \t]*\|?[\s:|-]+\|[\s:|-]*$")
OQ_RE = re.compile(r"\bOQ-(\d+)\b")
# §8.3's ban is a WORDING ban, so it is checkable: `recommend*` and `decided` anywhere in the section, and
# `decision:` with a colon. A hyphenated tail (`re-decided`) sits on a word boundary and trips it too — the
# section has to phrase the open state without decision verbs, and an argument that needs one is arguing.
VERDICT_RE = re.compile(r"\b(?:recommend\w*|decided)\b|decision[ \t]*:", re.I)

# Floors, not measurements (the HD-1118 mute-failure class: a gate that cannot see the files cannot fail
# either). MEASURED 2026-10-24: 92 tracked `.md` under docs/, 287 tracked `.md` in the whole tree.
# MINT_FLOOR sits above the docs-only count on purpose: a tree-wide scan that silently narrows to `docs/`
# reads 92 and would otherwise mint ids from a basis it never finished reading.
WALK_FLOOR = 80
MINT_FLOOR = 200


def cells(line: str) -> list[str]:
    """Split a table row on UNESCAPED pipes — the check_md_tables.py / check_registry_prose.py rule, so the
    three gates that read a table agree about where its cells are."""
    return [c.strip() for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]


def sections(text: str):
    """[(lineno, level, heading, section_text)] for every `## Options` / `### Options` heading.

    The section runs to the next heading of the SAME OR A HIGHER level, which is what makes a `#### Sub-option`
    belong to its `### Options` and a `## Next section` end it. Code fences are tracked, because a `#` at column
    0 inside a fenced block is a comment, not a heading — and `docs/backup.md`, the file this gate's own subject
    lives in, is full of fenced diagrams.
    """
    lines = text.splitlines()
    out = []
    in_fence = False
    for n, ln in enumerate(lines):
        if FENCE_RE.match(ln):
            in_fence = not in_fence
            continue
        if in_fence or not OPTIONS_HEAD.match(ln):
            continue
        level = len(HEAD_RE.match(ln).group(1))
        end = len(lines)
        fenced = False
        for m in range(n + 1, len(lines)):
            if FENCE_RE.match(lines[m]):
                fenced = not fenced
                continue
            if fenced:
                continue
            nxt = HEAD_RE.match(lines[m])
            if nxt and len(nxt.group(1)) <= level:
                end = m
                break
        out.append((n + 1, level, lines[n].strip(), "\n".join(lines[n:end])))
    return out


def option_table(body: str):
    """(header_lineno, rows [(lineno, cells)]) for the option table in a section — ([], []) when it has none.

    The FIRST header row matching the grammar wins; a section may hold a second, unrelated table (§9b's does)
    and that table is not this rule's subject.
    """
    lines = body.splitlines()
    for n, ln in enumerate(lines):
        if ROW_RE.match(ln) and cells(ln) == OPTION_HEADER:
            rows = []
            for m in range(n + 1, len(lines)):
                nxt = lines[m]
                if not ROW_RE.match(nxt):
                    break
                if SEP_ROW_RE.match(nxt):
                    continue
                rows.append((m + 1, cells(nxt)))
            return n + 1, rows
    return None, []


def first_table_header(body: str):
    """The section's first table header row, for the finding text — so a near-miss header is QUOTED back."""
    lines = body.splitlines()
    for n, ln in enumerate(lines):
        if not ROW_RE.match(ln):
            continue
        nxt = lines[n + 1] if n + 1 < len(lines) else ""
        if SEP_ROW_RE.match(nxt):
            return n + 1, ln.strip()
    return None, ""


def check_section(where: str, lineno: int, heading: str, body: str, mint_max: int) -> list[str]:
    findings: list[str] = []
    head_ln, rows = option_table(body)
    if head_ln is None:
        _, near = first_table_header(body)
        detail = (f"the section's first table header is `{near}`" if near
                  else "the section carries no table at all")
        findings.append(f"FAIL: {where}:{lineno}: shape — an `Options` section must carry "
                        f"`{HEADER_TEXT}`; {detail} (CONVENTIONS §8.3)")
    else:
        after = body.splitlines()[head_ln:head_ln + 1]
        if not after or not SEP_ROW_RE.match(after[0]):
            findings.append(f"FAIL: {where}:{head_ln}: shape — the header row has no `|---|` separator line "
                            "under it, so Markdown renders it as a paragraph, not a table")
        if len(rows) < 2:
            findings.append(f"FAIL: {where}:{head_ln}: shape — {len(rows)} option row(s); §8.3 needs TWO or "
                            "more, because one row is a verdict with a table around it")
        for rln, row in rows:
            if len(row) != len(OPTION_HEADER):
                findings.append(f"FAIL: {where}:{rln}: shape — the row carries {len(row)} cell(s) against a "
                                f"{len(OPTION_HEADER)}-cell header. Rows are read positionally, so a shifted "
                                "row puts something other than the Cheap test in the column the rule checks")
                continue
            if not row[OPTION_HEADER.index("Cheap test")].strip():
                findings.append(f"FAIL: {where}:{rln}: shape — an empty `Cheap test` cell. The cheapest "
                                "experiment that would settle the row is what makes an option cheaper to test "
                                "than to argue; without it the row is a wish (CONVENTIONS §8.3)")
    ids = [int(m.group(1)) for m in OQ_RE.finditer(body)]
    if not ids:
        findings.append(f"FAIL: {where}:{lineno}: key — the section names no `OQ-<n>` id, so it is a heading "
                        "and not an addressable open question — `§Options — OQ-<n> (the question as asked)`")
    for oid in sorted(set(ids)):
        if oid > mint_max + 1:
            findings.append(f"FAIL: {where}:{lineno}: mint — the section names OQ-{oid}, and the derived space "
                            f"tops at {mint_max}, so the highest derivable id is {mint_max + 1}. A number above "
                            "that was typed, not derived (CONVENTIONS §8.3 + §2): re-derive with "
                            f"`{MINT_CMD}`")
    for m in VERDICT_RE.finditer(body):
        line = body[:m.start()].count("\n") + lineno
        findings.append(f"FAIL: {where}:{line}: no-verdict — an `Options` section states a ruling (`"
                        f"{m.group(0)}`). An option is never a decision dressed as an option: the ruling is the "
                        "owner's act and it belongs in the doc's state prose or in `<domain>-rejected.md` "
                        "(CONVENTIONS §8.3)")
    return findings


def scan(corpus: dict[str, str], mint_ids: set[int]):
    """corpus {relpath: text} (docs only) + the derived id set -> (findings, stats). Pure: no git, no disk."""
    findings: list[str] = []
    n_sections = 0
    mint_max = max(mint_ids) if mint_ids else 0
    for rel in sorted(corpus):
        for lineno, _level, heading, body in sections(corpus[rel]):
            n_sections += 1
            findings += check_section(rel, lineno, heading, body, mint_max)
    return findings, {"sections": n_sections, "docs": len(corpus), "mint_ids": sorted(mint_ids),
                      "mint_max": mint_max}


def mint_lines(corpus_all: dict[str, str]) -> set[int]:
    """The minted id space, derived from every tracked `.md` — MINUS the `Options` heading lines.

    Excluding the heading lines is what gives rule (d) teeth. The alternative reads the number off the very
    line it is auditing, so `## Options — OQ-47` would be its own proof and the rule could never fire. Every
    other mention — a doc's cross-reference, a `todo.md` row, a probe report — counts as a declaration.
    """
    ids: set[int] = set()
    for text in corpus_all.values():
        for ln in text.splitlines():
            if OPTIONS_HEAD.match(ln):
                continue
            ids.update(int(m.group(1)) for m in OQ_RE.finditer(ln))
    return ids


def id_space(stats: dict) -> None:
    ids = stats["mint_ids"]
    lst = ", ".join(str(i) for i in ids) if ids else "(none)"
    nxt = stats["mint_max"] + 1 if ids else 1
    print(f"OQ id space read from the tracked `*.md` ({len(ids)} id(s), max {stats['mint_max']}): {lst}")
    print(f"  next derived id = {nxt} — derive it, never type it (`{MINT_CMD}`)")
    print(f"  inventory this gate mirrors (the same list, re-derivable by hand): {INVENTORY_CMD}")


def report(corpus: dict[str, str], mint_ids: set[int], verbose: bool = False, unreadable=()) -> int:
    """The verdict half — separate from main() so --self-test can drive it with a synthetic corpus."""
    if not corpus and not unreadable:
        print("CANNOT RUN: no tracked docs were read. `git ls-files` answered with nothing under docs/, and a "
              "gate that sees nothing cannot fail either (HD-1118 Stage 1).")
        return 2
    findings, stats = scan(corpus, mint_ids)
    findings = list(unreadable) + findings
    id_space(stats)
    if verbose:
        for rel in sorted(corpus):
            for lineno, level, heading, _body in sections(corpus[rel]):
                print(f"  {rel}:{lineno}  (level {level})  {heading}")
    for line in findings:
        print(line)
    if findings:
        print(f"\n{len(findings)} finding(s) across {stats['sections']} `Options` section(s). Every fix here is "
              "an edit to the section, not to this file — except the id, which is derived.")
        return 1
    require_corpus(stats["docs"], WALK_FLOOR, "check_open_questions walked tracked .md under docs/")
    print(f"OK: {stats['sections']} `Options` section(s) in {stats['docs']} docs, each keyed, shaped and "
          f"verdict-free; id space tops at {stats['mint_max']}")
    return 0


def tracked(pathspec: str | None = None) -> list[str]:
    """Tracked `.md` for one pathspec (`None` = the whole tree) — the corpus, derived from git, never listed."""
    argv = ["git", "-C", str(ROOT), "ls-files", "-z"] + (["--", pathspec] if pathspec else [])
    r = subprocess.run(argv, capture_output=True)
    if r.returncode != 0:
        print(f"ERROR: {' '.join(argv[3:]) or 'git ls-files'} failed: "
              f"{r.stderr.decode('utf-8', 'replace').strip()}", file=sys.stderr)
        raise SystemExit(2)
    return [p for p in r.stdout.decode("utf-8", "replace").split("\0")
            if p.endswith(".md") and "/assets/" not in "/" + p]


def read(files: list[str]):
    """(corpus, unreadable findings) — an unreadable file is a FINDING, never a silent skip."""
    corpus, unreadable = {}, []
    for f in files:
        try:
            corpus[f] = (ROOT / f).read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            unreadable.append(f"FAIL: {f}: unreadable as UTF-8, so its `Options` sections cannot be checked "
                              "(a file a gate cannot read is never a pass)")
    return corpus, unreadable


def self_test() -> int:
    """Every rule seen RED on a mutation of a legal tree, then the same tree seen GREEN."""
    ok = True
    legal_docs = {
        "docs/services-ai.md": (
            "# Services AI\n\n### Options — OQ-14 (vector leg)\n\n"
            "The choice, open. Facts live above this heading.\n\n"
            + HEADER_TEXT + "\n|---|---|---|---|---|\n"
            "| Stay keyless | measured 7/10 | +2 elsewhere | nothing | one recall number against the floor |\n"
            "| Hybrid leg | +2 hit@5 | 2x latency | one env var | the same query set, both arms |\n\n"
            "### Next section\n\nstate prose\n"),
        "todo.md": "| HD-9 | 2 | AI | 2 | the memory plane, OQ-12 and OQ-13 decided, OQ-14 funded |\n",
    }
    mint = mint_lines(legal_docs)          # {12, 13} + nothing from the heading line

    def all_findings(corpus):
        return scan(corpus, mint_lines(corpus))[0]

    def red(label, tag, mutate):
        nonlocal ok
        mutant = dict(legal_docs)
        mutate(mutant)
        caught = [f for f in all_findings(mutant) if f": {tag} —" in f]
        if not caught:
            print(f"  FAIL  {label}: bred `{tag}`, nothing was reported. Findings: {all_findings(mutant)}")
            ok = False
            return
        print(f"  RED   {label}: {caught[0]}")
        clean = all_findings(legal_docs)
        if clean:
            print("  FAIL  the unmutated tree is not clean: " + "\n    ".join(clean))
            ok = False

    def green(label, corpus):
        nonlocal ok
        findings = all_findings(corpus)
        if findings:
            print(f"  FAIL  {label}: expected silence, got: " + "\n    ".join(findings))
            ok = False
        else:
            print(f"  GREEN {label}")

    # 0 — the control: the legal tree, and the fence rule that keeps a fenced `#` from ending a section.
    green("the legal tree", legal_docs)
    if sections("### Options — OQ-1 (q)\n\n```\n# not a heading\n```\n\nstill the section\n")[0:1]:
        fenced = dict(legal_docs)
        fenced["docs/fenced.md"] = ("### Options — OQ-12 (q)\n\n" + HEADER_TEXT + "\n|---|---|---|---|---|\n"
                                    "| a | b | c | d | run it |\n| e | f | g | h | run that |\n\n```\n"
                                    "# a comment, not a heading\n```\n\nstill here\n")
        if all_findings(fenced):
            print(f"  FAIL  a fenced `#` ended an `Options` section: {all_findings(fenced)}")
            ok = False
        else:
            print("  GREEN a `#` inside a code fence does not end the section")
    else:
        print("  FAIL  the section walker found no heading — every arm below would prove nothing")
        ok = False

    # 1 — shape: no table, a near-miss header (quoted back), one row, an empty cheap test, a shifted row.
    def no_table(mutant):
        mutant["docs/services-ai.md"] = "### Options — OQ-14 (vector leg)\n\nprose only\n"
    red("shape: no table", "shape", no_table)

    def wrong_header(mutant):
        mutant["docs/services-ai.md"] = mutant["docs/services-ai.md"].replace(
            HEADER_TEXT, "| Option | Pros | Cons | Cost | Notes |")
    red("shape: a near-miss header", "shape", wrong_header)

    def one_row(mutant):
        lines = mutant["docs/services-ai.md"].splitlines()
        lines = [ln for ln in lines if not ln.startswith("| Hybrid leg")]
        mutant["docs/services-ai.md"] = "\n".join(lines) + "\n"
    red("shape: one option row", "shape", one_row)

    def empty_cheap(mutant):
        mutant["docs/services-ai.md"] = mutant["docs/services-ai.md"].replace(
            "| the same query set, both arms |", "|  |")
    red("shape: an empty Cheap test cell", "shape", empty_cheap)

    def shifted(mutant):
        mutant["docs/services-ai.md"] = mutant["docs/services-ai.md"].replace(
            "| Hybrid leg | +2 hit@5 | 2x latency | one env var | the same query set, both arms |",
            "| Hybrid leg | +2 hit@5 | 2x latency | one env var | the same query set | and a sixth cell |")
    red("shape: a row with a sixth cell", "shape", shifted)

    # 1b — the separator line: without it the header renders as a paragraph and the "table" is a lie.
    def no_sep(mutant):
        mutant["docs/services-ai.md"] = mutant["docs/services-ai.md"].replace("\n|---|---|---|---|---|\n", "\n")
    red("shape: no separator row under the header", "shape", no_sep)

    # 2 — key: a shaped section nobody can address, because it names no id.
    def no_key(mutant):
        mutant["docs/services-ai.md"] = mutant["docs/services-ai.md"].replace(
            "### Options — OQ-14 (vector leg)", "### Options (vector leg, undecided)")
    red("key: no OQ id named", "key", no_key)

    # 3 — no-verdict: each banned wording, in a section that stays perfectly shaped otherwise.
    for word, text in (("recommend", "| Hybrid leg | recommended: +2 hit@5 | 2x latency | one env var | both arms |"),
                       ("decided", "| Hybrid leg | decided already | 2x latency | one env var | both arms |"),
                       ("decision:", "| Hybrid leg | decision: hybrid | 2x latency | one env var | both arms |")):
        def plant(mutant, text=text):
            mutant["docs/services-ai.md"] = mutant["docs/services-ai.md"].replace(
                "| Hybrid leg | +2 hit@5 | 2x latency | one env var | the same query set, both arms |", text)
        red(f"no-verdict: `{word}` wording inside the section", "no-verdict", plant)

    # 3b — the state prose OUTSIDE the section is not this rule's business: a doc may state its ruling in its
    # own facts, and a rule that reads the whole file would reddening every doc that has ever decided anything.
    elsewhere = dict(legal_docs)
    elsewhere["docs/services-ai.md"] += "\n**Decision: keep the keyless leg.** That is the owner's ruling.\n"
    green("a ruling stated in the doc's own state prose, outside the section", elsewhere)

    # 4 — mint: a typed number above the derived ceiling reddens; a derived mint and a reused id stay quiet.
    def typed_id(mutant):
        mutant["docs/services-ai.md"] = mutant["docs/services-ai.md"].replace("OQ-14", "OQ-47")
    red("mint: a typed id above max+1", "mint", typed_id)
    reuse = {k: (v.replace("OQ-14", "OQ-12") if k.endswith("services-ai.md") else v)
             for k, v in legal_docs.items()}
    green("an id already in the derived space (a re-open under its old key)", reuse)
    derived = {k: (v.replace("OQ-14", "OQ-13") if k.endswith("services-ai.md") else v)
               for k, v in legal_docs.items()}
    green("the next derived id (max+1) — a fresh mint is legal, never a finding", derived)

    # 5 — an `Options` heading at level 1 is out of scope, and a heading that merely contains the word is too:
    # both stay silent so the gate and the mirrored `rg` pattern agree about what the inventory is.
    silent = dict(legal_docs)
    silent["docs/level1.md"] = "# Options\n\nprose\n"
    silent["docs/word.md"] = "## Other Options\n\nprose\n"
    if all_findings(silent) != all_findings(legal_docs):
        print("  FAIL  a level-1 or embedded `Options` heading entered scope: "
              f"{[f for f in all_findings(silent) if f not in all_findings(legal_docs)]}")
        ok = False
    else:
        print("  GREEN `# Options` and `## Other Options` stay out of scope, as the mirrored rg pattern does")

    # 6 — the empty corpus may never read as a clean tree, and an unreadable doc may not be skipped.
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = report({}, set())
    if rc == 2:
        print("  OK    an empty corpus is refused with rc 2, never `OK: 0 sections` — "
              + buf.getvalue().splitlines()[-1])
    else:
        print(f"  FAIL  an empty corpus returned rc {rc} instead of 2 — a gate that sees nothing cannot fail")
        ok = False
    with contextlib.redirect_stdout(io.StringIO()):
        rc = report({}, set(), unreadable=["FAIL: docs/x.md: unreadable as UTF-8"])
    if rc == 1:
        print("  OK    an unreadable doc is a finding (rc 1), never a silent pass")
    else:
        print(f"  FAIL  an unreadable doc returned rc {rc} instead of 1")
        ok = False

    # 6b — the mint floor, proved at its own boundary: exactly MINT_FLOOR paths must be refused and one more
    # must pass. The point of the number is that it sits ABOVE the docs-only count (92 today, printed by arm
    # 6c), so a tree-wide scan that silently narrows to `docs/` is a red run rather than ids minted from a
    # basis the gate never finished reading.
    for n, expect_refusal in ((MINT_FLOOR, True), (MINT_FLOOR + 1, False)):
        refused = None
        try:
            require_corpus(n, MINT_FLOOR, "check_open_questions read the tree-wide mint basis")
        except SystemExit as e:
            refused = str(e)
        if expect_refusal and not refused:
            print(f"  FAIL  mint floor: {n} files passed. Minting from a half-read space is the bug")
            ok = False
        elif expect_refusal:
            print(f"  RED   mint floor: a basis of {n} files is refused — {refused.splitlines()[0]}")
        elif refused:
            print(f"  FAIL  mint floor: a healthy basis of {n} files was refused — {refused.splitlines()[0]}")
            ok = False
        else:
            print(f"  GREEN mint floor: {n} files pass, {MINT_FLOOR} does not (the docs-only walk is "
                  f"{len(_count('docs'))} today, under the floor)")

    # 6c — floor vs drift: the two measurements the floors sit under, re-taken now.
    for label, files, floor, measured_at in (("docs/", _count("docs"), WALK_FLOOR, 92),
                                             ("whole-tree", _count(None), MINT_FLOOR, 287)):
        n = len(files)
        if not n:
            print(f"  SKIP  no `git ls-files` here, so the {label} floor is proved at its boundary only")
        elif n <= floor:
            print(f"  FAIL  the real {label} walk yields {n} tracked .md, at or below its floor {floor} "
                  f"(measured {measured_at} on 2026-10-24) — raise the floor with the tree")
            ok = False
        else:
            print(f"  OK    the real {label} walk yields {n} tracked .md, above its floor {floor}")

    print("self-test: " + ("all canaries caught, control clean" if ok else "NOT PROVEN"))
    return 0 if ok else 1


def _count(pathspec) -> list[str]:
    """The real walk for the floor-vs-drift arm; an empty answer means no git here, which is a SKIP."""
    try:
        return tracked(pathspec)
    except (SystemExit, OSError):
        return []


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        prog="check_open_questions.py",
        description="CONVENTIONS §8.3 — an open question is an `Options` section keyed by its OQ id, shaped, "
                    "verdict-free, and minted by derivation.",
        epilog="exit 0 clean · 1 finding(s) · 2 could not run")
    ap.add_argument("--show", action="store_true", help="print the id space and every section the gate read")
    ap.add_argument("--verbose", action="store_true", help="list each `Options` section with file:line")
    ap.add_argument("--self-test", action="store_true", help="breed each defect and require the red")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    doc_files = tracked("docs")
    if not doc_files:
        print("CANNOT RUN: `git ls-files -- docs` reports no tracked .md — either the walk is broken or this "
              "is not the repo root. A gate that sees nothing cannot fail either.")
        return 2
    require_corpus(len(doc_files), WALK_FLOOR, "check_open_questions walked tracked .md under docs/")
    tree_files = tracked()
    require_corpus(len(tree_files), MINT_FLOOR, "check_open_questions read the tree-wide mint basis")
    tree_corpus, unreadable = read(tree_files)
    corpus = {f: tree_corpus[f] for f in doc_files if f in tree_corpus}
    mint_ids = mint_lines(tree_corpus)
    _, stats = scan(corpus, mint_ids)
    if args.show:
        id_space(stats)
        for rel in sorted(corpus):
            for ln, lvl, head, _b in sections(corpus[rel]):
                print(f"  {rel}:{ln}  (level {lvl})  {head}")
        return 0
    return report(corpus, mint_ids, args.verbose, unreadable)


if __name__ == "__main__":
    sys.exit(main())
