#!/usr/bin/env python3
"""Lint: strings that were byte-equal at the baseline revision are still byte-equal.

Wave 2 severed two twins by purging one side only: five playbooks lost `HD-413 | ` from
`- name: Self-converge guardrail` while scripts/testdata/self-converge-guard/fixture.yml
kept it, and one base task name `Configure management services (lockdown - HD-301 parity)`
came out as `(lockdown)` in roles/router and `(lockdown parity)` in roles/switch. No
validator could see either one, because each side still looked fine in its own file. This
is the permanent half of that check: a claim about the DIFF, so it needs no allowlist.

The rule under test (RULES.md R-2: ids inside code strings are code). Take the literals this
repo writes or renders at a pinned baseline revision B, and the same literals now. Group them
by their EXACT base bytes. A group spanning >= 2 files at B is a twin group: two files
shipped one string, so they are one fact in two places. If such a group's current sides are
not byte-equal, the wave severed the twin -- it renamed one side and not the other, which is
how a `find where comment=` selector loses its target and how `--start-at-task=` starts
needing one task name per role.

"Now" means what the commit SHIPS, decided by `git ls-files`, not what a directory listing
happens to find: the bytes a `git rm --cached` left in the working tree belong to a side this
commit is deleting, so reading them as present would certify a twin against a file the commit
drops.

Why this is green on day one BY CONSTRUCTION: the population is *defined* by byte-equality at
B. A family whose sides already differed at B cannot form an exact group, so the families this
repo has never agreed on are not members -- no allowlist, no exemptions, nothing to sign.
What the gate cannot see it says out loud instead of hiding: see BLIND SPOTS.

The baseline is pinned in scripts/gate/twin_baseline.txt:

    baseline_rev <sha>       the revision the population is read from
    twin_groups <n>          how many >=2-file groups that revision yields
    group_keys_sha256 <hex>  sha256 over the sorted group keys -- sha256 per key, then the
                             hash of that stream, so a key containing a newline cannot shift
                             the digest of its neighbours

Those last two are the canary, the same job scripts/gate/iac_identifier_allowlist.txt does for the
identifier lint: the population is a pure function of (baseline_rev, the extractor, the
scope), so moving B or narrowing the extractor changes the digest, and the run refuses to
pretend the population is still the one that was reviewed. Re-baseline at a wave tip -- B :=
wave tip, deliberately, in a commit that publishes all three values (`--show-baseline` prints
them, and one extra `proven-by-presence:` line that is a run statistic, never a fourth field to
paste back). B is never more than one wave old: STALE_AFTER_COMMITS refuses a staler one, because
the per-file difflib alignment below degrades on a big feature commit and an old B turns
refactors into false severs.

Side states -- a base occurrence's current side is decided in this order:
    1  PRESENT: the exact base value still occurs somewhere in that file now. Alignment plays
       no part here, so a reordering can never invent a change, and this answer never has to
       agree with what the alignment went on to say;
    2  MOVED: the difflib opcode pairs it to a literal in the same SHORT local run (a
       replace/delete block of <= LOCAL_RUN base literals, in a file that is still anchored) ->
       the specific value it became. GONE is the same answer when nothing replaced it;
    3  ABSENT-UNCERTAIN: the base value is gone from that file and the run around it is too
       long to pair, so what took its place is unknown. Unknown content is still evidence -- it
       proves the base bytes are NOT in that file any more;
    4  ALIGN-UNCERTAIN: the file as a whole kept too few of its literal anchors (below
       GLOBAL_RATIO), so nothing inside it is evidence. Excluded from the verdict and reported
       by name -- a mis-aligned file may never be the reason a twin is called severed.

The verdict, and why it needs no alignment for the case that matters. "Are these sides
byte-identical now?" is answered by presence-in-file (state 1) wherever a side still carries
the base bytes, which is the case a bulk purge in one file produces:
  * any side PRESENT and any side that is not -> SEVERED, whatever the alignment says about the
    other side. One file ships the base bytes, another no longer ships them at all, so no
    pairing can make them equal and no uncertainty can be claimed: both sides are named as
    file:line. A one-sided rename hidden inside a 10-literal run in an otherwise untouched file
    is exactly this, and it used to read OK.
  * no side PRESENT, and every side that can answer agrees on one value W which every silent
    side's own file carries -- in a class the twin is itself written in, exactly once -> MOVED on
    every side in one commit: green, the documented good case. This is the one place the gate
    decides a group it cannot align, so the proof it falls back on is the same presence test
    state 1 uses, narrowed twice: W must be bytes an extractor lifted that ALSO lifts the twin
    (a W that survives only in a `msg:` string does not prove a `name:` twin is still there), and
    W must occur once. Twice is `AMBIGUOUS (n)`: which occurrence the twin became is not a fact
    bytes can settle, so the gate says so instead of choosing.
  * anything else -- a side whose content is unknown with no agreed value to look for, an agreed
    value missing from a silent side or sitting there in the wrong kind of literal or more than
    once, or a group whose only sides are mis-aligned files -> NOT PROVEN: printed by name, with
    the reason, exit 1. A gate that cannot decide may not report OK, because a silent green on an
    undecidable group is the same hole as a silent green on a sever.
Both presence tests -- PRESENT, and the agreed-value test that settles a side the alignment could
not place -- ask where the BYTES are and never where they SIT: one occurrence anywhere in that
file, at any line, answers. That is their whole strength and their whole limit -- a side whose
copy of the string survived on some other line of the same kind reads green, and no position is
ever compared. The run counts the groups it settled by the agreed value and prints
`proven-by-presence: N`; a jump in N is what a widening of this rule looks like from outside.
A purge is a short local run, so it is read exactly. A rewrite of 30 literals is not, so it is
reported rather than accused -- but it is never silent.

BLIND SPOTS, stated because a gate read as stronger than it is gets trusted wrongly:
  * payload only -- YAML block scalars, shell heredocs, Jinja-rendered values and `#` comment
    prose are not literals. Nothing here sees a twin living inside a `|` block, and one Jinja
    expression makes two identical sources look different.
  * families that never agreed -- a twin whose sides already differed at B is not a member
    (the ~94 families the wave audit counted). `--families` prints a REPORT-ONLY normalized
    view of them and cannot fail the run, because a normalized bucket under-reports -- the
    audit's normalized buckets missed a real sever until a paren-dropping variant was added --
    so a verdict built on that number would be decoration.
  * a twin renamed on every side in one commit is no longer keyed at B -- the new spelling is
    not a base value, so PRESENT can never fire for it again and the group is judged from here
    on by what the alignment pairs and by the agreed-value presence test above. A later one-sided
    rename of the NEW spelling is still caught when any side can name a value or still carries
    the one the others agree on; when nothing can, the group comes back NOT PROVEN rather than
    green. What stays genuinely blind is the presence limit stated above: the gate compares bytes
    a file carries, in the twin's own kind of literal and only where there is exactly one such
    occurrence, never the position they sit at -- and it has no allowlist to make up for either.

Run:   python3 scripts/gate/check_string_twins.py [--control REV] [--families] [--show-baseline]
       python3 scripts/gate/check_string_twins.py --self-test
Exit:  0 clean; 1 severed twin(s) and/or twin group(s) this run could not prove, each side named
       as file:line; 2 the gate could not measure (no full history, a baseline more than one
       wave old, a baseline file that does not match the population it describes, an unreadable
       revision). Not proven is exit 1, never exit 0: it is a verdict the run reached, not a
       refusal to run.
Wired into scripts/validate-all.sh.
"""
from __future__ import annotations

import ast
import difflib
import hashlib
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import root as _hl_root  # noqa: E402
ROOT = _hl_root(__file__)
BASELINE = "scripts/gate/twin_baseline.txt"
PREFIXES = ("IaC/", "scripts/")

# RULES: the literal set is the wave audit's (lane FX, gate 5) -- the same population the
# audit proved sensitive on, with the same reason for every class. name/msg/comment/
# Description/title/legendFormat/description/content values; RouterOS comment= / comment:
# values written onto a device object; double-quoted strings; every ast string constant in a
# .py. `#` comment prose is NOT a literal: the invariant is about text a device or a renderer
# receives, not about narration.
KEY_VALUE = re.compile(r'^\s*(?:-\s+)?["\']?(?P<key>name|msg|comment|Description|title|legendFormat'
                       r'|description|content)["\']?\s*[:=]\s*(?P<val>.*)$')
ROS_COMMENT = re.compile(r'comment\s*[:=]\s*(?P<q>"|\'|)(?P<val>.*?)(?P=q)\s*(?:$|\s)')
QUOTED = re.compile(r'"([^"\\\n]{2,})"')
# A block scalar or an anchor is payload (see BLIND SPOTS), not a value written on this line.
SCALAR_PREFIX = ("|", ">", "&", "*")
# A double-quoted string is only lifted out of a file where `"` is a string delimiter;
# elsewhere the same bytes are prose in a banner or a heading.
QUOTED_SUFFIXES = (".yml", ".yaml", ".py", ".sh", ".j2", ".rsc", ".json", ".cfg", ".ini",
                   ".service", ".timer", ".conf", ".ps1", ".txt")

# A literal is (line, value, classes): the classes are the extractors that lifted it, so a value
# found later by presence can be asked whether it is the KIND of literal the twin is written in.
# KEY_VALUE classes carry their key (`name:`, `msg:`, `comment:`...), ROS_COMMENT's carries its
# marker, and the two whole-file extractors are `quoted` and `py-string`.
Lit = tuple[int, str, frozenset[str]]
# file -> value -> the classes of each occurrence of that value, in the file as it stands now.
Carries = dict[str, dict[str, list[frozenset[str]]]]
CLS_ROS_COMMENT = "comment="
CLS_QUOTED = "quoted"
CLS_PY = "py-string"

GONE = "\x00gone"
UNCERTAIN = "\x00uncertain"      # the FILE did not align: no vote, reported by name
UNCLARABLE = "\x00unclarable"    # base bytes gone from the file, the run too long to pair it
SIDE_NOTE = {GONE: "GONE (this side no longer carries the base value at all)",
             UNCERTAIN: "ALIGN-UNCERTAIN (excluded from this group's verdict)",
             UNCLARABLE: "ABSENT-UNCERTAIN (this file no longer carries the base value and the "
                         "run around it is too long to say what took its place)"}
# A replace/delete run this long is not one local edit any more; the pairing inside it stops
# being evidence about WHAT the side became. It stays evidence that the base bytes are no longer
# in that file, which is the half of the verdict that needs no pairing: ABSENT-UNCERTAIN.
LOCAL_RUN = 6
# ...and a file that kept less than this share of its literal anchors is mis-aligned as a
# whole, so no pairing inside it counts however short each individual run looks.
GLOBAL_RATIO = 0.5
GLOBAL_MIN = 10
# One wave measured 176 commits (34e77f82 -> 953255b8). Past this many the baseline is no
# longer "the current wave", which is the only window this gate is honest about.
STALE_AFTER_COMMITS = 300

# The positive control is a PAIR of revisions, not a revision. 8b28edd3 is the tip before the
# wave-2 twin repairs, where exactly this many twin groups had been severed, and 34e77f82 is the
# revision that claim was measured against. Both ends are pinned because baseline_rev moves: a
# re-baseline (a wave tip, a folder move) silently turns "base -> 8b28edd3" into a run that
# measures backwards, and the witness becomes an artifact of wherever the baseline happens to
# sit. Pinning the base keeps the historical claim -- 6 severs, a real one-side rename -- and the
# self-test proves it reads 6 while the RECORDED baseline is some later commit.
CONTROL_BASE_REV = "34e77f82"
CONTROL_REV = "8b28edd3"
CONTROL_SEVERS = 6


class ToolError(Exception):
    """The gate cannot measure: no history, no baseline, a revision that is not there."""


def _git(repo: Path, *args: str) -> bytes:
    out = subprocess.run(["git", "-C", str(repo), *args], capture_output=True)
    if out.returncode != 0:
        raise ToolError((out.stderr.decode("utf-8", "replace").strip()
                         or f"git {args[0] if args else ''} failed in {repo}"))
    return out.stdout


def _scoped(paths) -> list[str]:
    return sorted(p for p in paths if p.startswith(PREFIXES))


def files_at_rev(repo: Path, rev: str) -> list[str]:
    out = _git(repo, "ls-tree", "-r", "--name-only", "-z", rev, "--", *PREFIXES)
    return _scoped(p for p in out.decode("utf-8", "replace").split("\0") if p)


def _at_rev(repo: Path, rev: str, rel: str) -> str | None:
    """The revision's bytes, or None when the path is not in that revision."""
    try:
        raw = _git(repo, "show", f"{rev}:{rel}")
    except ToolError:
        return None
    return None if b"\0" in raw else raw.decode("utf-8", "replace")


def _in_worktree(repo: Path, rel: str) -> str | None:
    try:
        raw = (repo / rel).read_bytes()
    except OSError:
        return None
    return None if b"\0" in raw else raw.decode("utf-8", "replace")


def _read(repo: Path, rev: str | None, rel: str) -> str | None:
    return _at_rev(repo, rev, rel) if rev else _in_worktree(repo, rel)


def strip_comment(line: str) -> str:
    """The line without its `#` comment: narration is not a literal, the value before it is."""
    if line.lstrip().startswith("#"):
        return ""
    out, quote, i = [], None, 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == quote:
                quote = None
            out.append(c)
        elif c in "\"'":
            quote = c
            out.append(c)
        elif c == "#" and (i == 0 or line[i - 1] in " \t"):
            break
        else:
            out.append(c)
        i += 1
    return "".join(out)


def _dequote(v: str) -> str:
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


def literals(rel: str, text: str) -> list[Lit]:
    """(line, value, classes) for every literal this file writes or renders, in document order.

    `classes` says which extractor lifted the bytes. Two extractors lifting the same bytes off
    the same line -- RouterOS `comment="X"` is lifted by ROS_COMMENT and by QUOTED -- are ONE
    occurrence carrying BOTH classes, so the sequence of values and their order, which is what
    the alignment and the population are built from, is exactly what it was before classes.
    """
    found: list[Lit] = []
    for n, raw in enumerate(text.splitlines(), 1):
        code = strip_comment(raw)
        if not code.strip():
            continue
        m = KEY_VALUE.match(code)
        if m:
            v = _dequote(m.group("val"))
            if v and not v.startswith(SCALAR_PREFIX):
                found.append((n, v, frozenset({m.group("key") + ":"})))
        for mm in ROS_COMMENT.finditer(code):
            v = _dequote(mm.group("val"))
            if v:
                found.append((n, v, frozenset({CLS_ROS_COMMENT})))
        if rel.endswith(QUOTED_SUFFIXES):
            for mm in QUOTED.finditer(code):
                found.append((n, mm.group(1), frozenset({CLS_QUOTED})))
    if rel.endswith(".py"):
        try:
            for node in ast.walk(ast.parse(text)):
                if isinstance(node, ast.Constant) and isinstance(node.value, str) \
                        and len(node.value) >= 2:
                    found.append((getattr(node, "lineno", 0), node.value, frozenset({CLS_PY})))
        except SyntaxError:
            pass  # a file that does not parse is the portability sweep's problem, not this one
    merged: dict[tuple[int, str], Lit] = {}
    for ln, v, cls in found:
        at = (ln, v)
        earlier = merged.get(at)
        merged[at] = (ln, v, cls if earlier is None else earlier[2] | cls)
    return list(merged.values())


def tracked(repo: Path) -> set[str]:
    """The paths a working-tree read may vouch for: the index, i.e. what would be committed."""
    out = _git(repo, "ls-files", "-z", "--", *PREFIXES)
    return set(_scoped(p for p in out.decode("utf-8", "replace").split("\0") if p))


def load(repo: Path, rev: str | None, paths: list[str]) -> dict[str, list[Lit]]:
    """Literal lists for `paths`, from one revision or from the index + working tree. On a
    working-tree read a path the index dropped is an absent side -- its bytes may still sit on
    disk after `git rm --cached`, and the commit is deleting it."""
    shipped = set(paths) if rev else tracked(repo)
    out: dict[str, list[Lit]] = {}
    for rel in paths:
        text = _read(repo, rev, rel) if rel in shipped else None
        out[rel] = literals(rel, text) if text is not None else []
    return out


def file_sides(base: list[Lit], now: list[Lit]) -> tuple[list[str], bool]:
    """One current side per base occurrence, in base order; second value = mis-aligned.

    Order of proof is in the module docstring. `GONE` means the side no longer carries the base
    value and a short run says nothing replaced it there; `UNCLARABLE` means the side no longer
    carries the base value and the run is too long to say what did -- both still prove the base
    bytes are absent from this file. `UNCERTAIN` means the FILE moved too much for any pairing
    here to count, and it must never be counted as a change.
    """
    a = [v for _ln, v, _cls in base]        # classes play no part in aligning a file
    b = [v for _ln, v, _cls in now]
    present = set(b)
    ops = difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes()
    anchors = sum(i2 - i1 for tag, i1, i2, _j1, _j2 in ops if tag == "equal")
    misaligned = bool(base) and len(base) >= GLOBAL_MIN and anchors / len(base) < GLOBAL_RATIO
    paired: list[str] = [GONE] * len(base)
    for tag, i1, i2, j1, j2 in ops:
        if tag == "equal":
            for k in range(i2 - i1):
                paired[i1 + k] = b[j1 + k]
            continue
        if misaligned:
            for k in range(i2 - i1):        # nothing inside a mis-anchored file is evidence
                paired[i1 + k] = UNCERTAIN
            continue
        trustworthy = (i2 - i1) <= LOCAL_RUN
        span = min(i2 - i1, j2 - j1)
        for k in range(i2 - i1):
            if not trustworthy:
                paired[i1 + k] = UNCLARABLE   # absent here for sure, unknown as to what now
            elif k < span:
                paired[i1 + k] = b[j1 + k]
    return [v if v in present else paired[i] for i, v in enumerate(a)], misaligned


def group_keys_sha256(keys) -> str:
    """sha256 of the sorted keys, hashed one digest per key so a key may contain a newline."""
    h = hashlib.sha256()
    for k in sorted(keys):
        h.update(hashlib.sha256(k.encode("utf-8", "surrogatepass")).digest())
    return h.hexdigest()


def twins(base_lits: dict[str, list[Lit]]) -> dict[str, list[tuple[str, int]]]:
    """base value -> [(file, line)] for values at least TWO files shipped at the baseline."""
    groups: dict[str, list[tuple[str, int]]] = {}
    for rel, lits in base_lits.items():
        for ln, v, _cls in lits:
            groups.setdefault(v, []).append((rel, ln))
    return {k: v for k, v in groups.items() if len({f for f, _ in v}) >= 2}


def _agreed_value_proof(value: str, silent: list[str], carries: Carries,
                        classes: frozenset[str]) -> list[str]:
    """Why the agreed value does (an empty list) or does not settle the sides that went silent.

    Presence is the proof, but proof of a specific kind, and the two conditions are separate
    on purpose so each is testable on its own -- self-test xi reddens if the class test goes,
    xii reddens if the count test goes:
      * the occurrence must be in a class the twin is itself written in. `W` surviving in a
        `msg:` string or in prose does not prove the `name:` twin is still in that file;
      * it must occur EXACTLY ONCE in those classes. Twice means which occurrence the twin
        became cannot be told, which is a thing to report, not a thing to guess at.
    """
    why: list[str] = []
    for f in sorted(silent):
        occ = carries.get(f, {}).get(value, [])
        hits = [cls for cls in occ if cls & classes]
        if len(hits) == 1:
            continue
        found_in = frozenset().union(*occ) if occ else frozenset()
        if not hits:
            where = ("it does not occur in that file at all" if not found_in else
                     f"it occurs there only as {'/'.join(sorted(found_in))}, never as "
                     f"{'/'.join(sorted(classes))}")
            why.append(f"{f}: the agreed value {value[:80]!r} proves nothing there -- {where}")
        else:
            why.append(f"{f}: the agreed value {value[:80]!r} occurs {len(hits)} times there "
                       f"(AMBIGUOUS) -- which of them the twin became cannot be told")
    return why


def group_verdict(key: str, members: list[tuple[str, int, str]],
                  carries: Carries, classes: frozenset[str]) -> tuple[str, list[str]]:
    """'sever' | 'unproven' | 'ok' | 'presence', plus the reason lines, for one twin group --
    presence first, difflib only after.

    A side's content now is KNOWN when it is PRESENT (the base value), MOVED (the value the
    alignment paired it to) or GONE (nothing); it is unknown only when the side is
    ABSENT-UNCERTAIN, and even that proves the base bytes are not in that file. ALIGN-UNCERTAIN
    sides take no part, exactly as GT built them: a file that did not anchor is reported, not
    accused. 'presence' is an ok decided by the agreed-value test, counted separately because it
    is the one decision here that does not come from the alignment. `classes` is every extractor
    that lifted the twin at the baseline, which is what the agreed value has to match. The reason
    lines are what an unproven group prints under its own name.
    """
    known = [None if s == UNCLARABLE else s for _f, _l, s in members if s != UNCERTAIN]
    if not known:
        return "unproven", ["no side can be paired: every side of this twin sits in a file "
                            "that did not align"]
    here = sum(1 for k in known if k == key)
    if here and here < len(known):
        return "sever", []                     # one file still ships it, another no longer does
    decided = {k for k in known if k is not None}
    if len(decided) > 1:
        return "sever", []                     # the sides that can answer answer differently
    if all(k is not None for k in known):
        return "ok", []                        # all PRESENT, or all MOVED to one identical value
    # Something cannot say what it became. Presence still settles it: if the sides that CAN
    # answer agree on one value and each silent side's file carries that value in the twin's own
    # kind of literal, exactly once, the sides are byte-identical now. Anything less is said so.
    named = decided - {GONE}
    if len(named) == 1:
        value = next(iter(named))
        why = _agreed_value_proof(value, [f for f, _l, s in members if s == UNCLARABLE],
                                  carries, classes)
        return ("presence", []) if not why else ("unproven", why)
    return "unproven", ["no side can name a value that could have replaced the base bytes"]


def evaluate(base_lits: dict[str, list[Lit]],
             now_lits: dict[str, list[Lit]]) -> dict:
    """The verdict on one base population read two ways. Pure: no git, no filesystem."""
    groups = twins(base_lits)
    sides: dict[str, list[tuple[str, int, str]]] = {}
    uncertain: list[str] = []
    carries: Carries = {}
    for rel, lits in now_lits.items():
        every: dict[str, list[frozenset[str]]] = {}
        for _ln, v, cls in lits:
            every.setdefault(v, []).append(cls)
        carries[rel] = every
    # The classes a twin was written in, so the agreed value cannot be proved by an unrelated
    # literal of its own file. A twin lifted as both `comment=` and `quoted` is proved by either.
    classes: dict[str, frozenset[str]] = {}
    for lits in base_lits.values():
        for _ln, v, cls in lits:
            classes[v] = classes.get(v, frozenset()) | cls
    for rel, bl in base_lits.items():
        got, misaligned = file_sides(bl, now_lits.get(rel, []))
        if misaligned:
            uncertain.append(rel)
        for (ln, v, _cls), side in zip(bl, got):
            sides.setdefault(v, []).append((rel, ln, side))
    severs: dict[str, list[tuple[str, int, str]]] = {}
    unproven: dict[str, list[tuple[str, int, str]]] = {}
    reasons: dict[str, list[str]] = {}
    presence = 0
    for key, members in groups.items():
        verdict, why = group_verdict(key, sides[key], carries, classes.get(key, frozenset()))
        if verdict == "sever":
            severs[key] = sides[key]
        elif verdict == "unproven":
            unproven[key] = sides[key]
            reasons[key] = why
        elif verdict == "presence":
            presence += 1
    return {"groups": groups, "severs": severs, "unproven": unproven,
            "unproven_reasons": reasons, "proven_by_presence": presence,
            "uncertain_files": sorted(uncertain),
            "files": len(base_lits), "literals": sum(len(v) for v in base_lits.values())}


def normalize(v: str) -> str:
    """Family stem: drop ` (...)` and `HD-<n>`, collapse whitespace. Report-only view."""
    stem = re.sub(r"\s*\([^)]*\)", " ", v)
    stem = re.sub(r"HD-\d+", " ", stem)
    return re.sub(r"\s+", " ", stem).strip()


def families(base_lits: dict[str, list[Lit]]) -> dict[str, list[tuple[str, int, str]]]:
    """Normalized families spanning >=2 files -- a hint about what the exact gate cannot see.

    A normalized bucket merges spellings that were never twins and splits a purge that dropped
    other prose, so the number it prints is neither a verdict nor evidence of one.
    """
    out: dict[str, list[tuple[str, int, str]]] = {}
    for rel, lits in base_lits.items():
        for ln, v, _cls in lits:
            out.setdefault(normalize(v), []).append((rel, ln, v))
    return {k: v for k, v in out.items() if len({f for f, _l, _v in v}) >= 2}


def read_baseline(repo: Path, strict: bool = True) -> dict[str, str]:
    """The three recorded fields. `--show-baseline` may read a half-written file, because
    that is exactly how a re-baseline is produced: point baseline_rev at the wave tip, then
    paste the numbers back in."""
    path = repo / BASELINE
    if not path.is_file():
        raise ToolError(f"{BASELINE} is missing, so the population this gate was reviewed "
                        f"against is unknown")
    fields: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.lstrip().startswith("#"):
            parts = line.split(None, 1)
            if len(parts) == 2:
                fields[parts[0]] = parts[1].strip()
    want = ("baseline_rev", "twin_groups", "group_keys_sha256") if strict else ("baseline_rev",)
    for key in want:
        if key not in fields:
            raise ToolError(f"{BASELINE} has no `{key}` field")
    return fields


def check(repo: Path, control: str | None = None, base: str | None = None) -> dict:
    """One run against a repo. Returns rc, the lines to print, and the numbers behind them.

    `base` pins the BASE revision instead of the recorded baseline_rev, and only the self-test's
    positive control passes it -- no command-line form reaches it (`--control` moves the NOW
    side, never the base). It exists so the control keeps measuring the pair it was measured on
    after a re-baseline moves baseline_rev; see CONTROL_BASE_REV.
    """
    started = time.monotonic()
    fields = read_baseline(repo)
    base_rev = base or fields["baseline_rev"]
    _git(repo, "rev-parse", "--git-dir")
    if _git(repo, "rev-parse", "--is-shallow-repository").decode().strip() == "true":
        return _refuse("ERROR: needs full history",
                       "this clone is shallow, so the baseline revision is not reachable")
    try:
        _git(repo, "cat-file", "-e", f"{base_rev}^{{commit}}")
    except ToolError:
        raise ToolError(f"needs full history -- {base_rev}, the baseline_rev recorded in "
                        f"{BASELINE}, is not in this clone's object store") from None
    try:
        _git(repo, "merge-base", "--is-ancestor", base_rev, "HEAD")
    except ToolError:
        return _refuse(f"ERROR: {base_rev} is not an ancestor of HEAD",
                       "the baseline has to be a revision on the history being checked")
    # Staleness is the window THIS run aligns over: base -> the revision it compares against. A
    # real run compares against the working tree, so that end is HEAD. A pinned replay -- the
    # self-test's positive control, the only caller that passes `base` -- compares two fixed
    # historical revisions, so its window is fixed too and cannot age with the tree.
    window_end = "HEAD" if base is None else control
    behind = int(_git(repo, "rev-list", "--count", f"{base_rev}..{window_end}").decode().strip())
    if behind > STALE_AFTER_COMMITS:
        return _refuse(f"ERROR: the baseline is {behind} commits behind {window_end}",
                       f"that is more than one wave (the cap is {STALE_AFTER_COMMITS}, a wave "
                       f"measured 176): alignment against a stale baseline turns refactors into "
                       f"false severs, so this gate measures the CURRENT wave or says nothing. "
                       f"Re-baseline at the wave tip -- point baseline_rev at HEAD and publish "
                       f"the twin_groups and group_keys_sha256 that --show-baseline prints")

    paths = files_at_rev(repo, base_rev)
    base = load(repo, base_rev, paths)
    now = load(repo, control, paths)
    result = evaluate(base, now)
    elapsed = time.monotonic() - started
    groups = result["groups"]
    try:
        recorded = int(fields["twin_groups"])
    except ValueError:
        raise ToolError(f"{BASELINE} records twin_groups {fields['twin_groups']!r}, which is "
                        f"not a count") from None
    # The recorded fingerprint describes the RECORDED baseline's population, so a replay with a
    # pinned base is not that population and is not measured against it.
    if (base is None and (len(groups) != recorded
                          or group_keys_sha256(groups) != fields["group_keys_sha256"])):
        return _refuse(
            "ERROR: the population does not match the baseline file",
            f"recomputed {len(groups)} twin groups at {base_rev}; {BASELINE} records "
            f"{recorded} with group_keys_sha256 "
            f"{fields['group_keys_sha256'][:16]}... A population that shrinks or changes shape "
            f"is a decision, not a detail: publish all three values together, in the commit "
            f"that moves baseline_rev")

    lines = [f"scanned {result['files']} files at {base_rev}: {result['literals']:,} base "
             f"literals, {len(groups):,} cross-file twin groups, {behind} commits of history "
             f"between, {elapsed:.1f} s"]
    if result["uncertain_files"]:
        lines.append(f"ALIGN-UNCERTAIN: {len(result['uncertain_files'])} file(s) did not align "
                     f"against {base_rev}. Their changed literals were checked for presence in "
                     f"the file only and never counted as severs:")
        lines += [f"      {f}" for f in result["uncertain_files"][:20]]
    lines.append(f"proven-by-presence: {result['proven_by_presence']} group(s) decided where a "
                 f"side could not be aligned")
    if result["severs"]:
        lines.append(f"FAIL: {len(result['severs'])} twin group(s) byte-equal at {base_rev} "
                     f"are not byte-identical now:")
        for key, members in sorted(result["severs"].items()):
            lines.append(f"  base value {key[:120]!r}")
            lines += [f"      {f}:{ln}  {SIDE_NOTE.get(s, repr(s))}" for f, ln, s in members]
        lines.append("A twin is one fact in two places. Rename every side in this commit (the "
                     "base bytes win), or -- if the twin really is gone now -- re-baseline at "
                     "the wave tip so the population records that out loud.")
    if result["unproven"]:
        lines.append(f"NOT PROVEN: {len(result['unproven'])} twin group(s) byte-equal at "
                     f"{base_rev} cannot be shown byte-identical now: no side carries the base "
                     f"bytes and at least one side cannot say what took them.")
        for key, members in sorted(result["unproven"].items()):
            lines.append(f"  unproven base value {key[:120]!r}")
            lines += [f"      {f}:{ln}  {SIDE_NOTE.get(s, repr(s))}" for f, ln, s in members]
            lines += [f"    reason: {r}" for r in result["unproven_reasons"].get(key, [])]
        lines.append("Not proven is not OK. An agreed value settles a silent side only when it "
                     "occurs there once, in a kind of literal the twin is itself written in -- "
                     "anything less is reported here, never assumed. Re-baseline at the wave tip "
                     "so the spelling the sides now agree on becomes the reviewed population, or "
                     "put the base bytes back on every side -- a run that cannot decide a twin "
                     "does not get to print OK about it.")
    if result["severs"] or result["unproven"]:
        return {"rc": 1, "lines": lines, "severs": len(result["severs"]),
                "unproven": len(result["unproven"]), "result": result}
    lines.append(f"OK: {len(groups):,} string twins from {base_rev} are byte-identical on "
                 f"every side ({elapsed:.1f} s)")
    return {"rc": 0, "lines": lines, "severs": 0, "unproven": 0, "result": result}


def _refuse(head: str, why: str) -> dict:
    return {"rc": 2, "lines": [head, f"      {why}"], "severs": 0, "result": {}}


def self_test() -> int:
    """Twelve cases. Ten are planted, one is the positive control, one is this tree -- the
    properties the gate claims, each built so it cannot pass by accident.

    Case iv used to read a live family in this repo. It cannot: the witness was "this family's
    sides differ AT the baseline", and main's 8b5b348c/8695baee converged those spellings, so
    the fact stopped existing the moment the baseline moved past them. A witness about what a
    baseline shows must not depend on which family history happened to leave divergent, so it
    is a fixture now -- same verdict, and it cannot be quietly deleted by a future commit that
    agrees two spellings for real."""
    fails: list[str] = []

    def record(name: str, ok: bool, said: str) -> None:
        print(f"{'PASS' if ok else 'FAIL'}  {name}")
        if not ok:
            fails.append(f"{name} -- {said}")

    pair = {"IaC/a.yml": "- name: Reboot the box (HD-1)\n",
            "IaC/b.yml": "- name: Reboot the box (HD-1)\n"}
    res = _fixture(pair, {"IaC/a.yml": "- name: Reboot the box\n"})
    named = [f"{f}:{ln}" for m in res["result"]["severs"].values() for f, ln, _s in m]
    record("i    a planted cross-file sever turns the gate red",
           res["rc"] == 1 and "IaC/a.yml:1" in named and "IaC/b.yml:1" in named,
           f"rc={res['rc']} sides={named}")
    res = _fixture(pair, {"IaC/a.yml": "- name: Reboot the box\n",
                          "IaC/b.yml": "- name: Reboot the box\n"})
    record("ii   a twin renamed on both sides in one commit stays green",
           res["rc"] == 0, f"rc={res['rc']} {res['lines']}")
    many = "".join(f"- name: Step {i} (HD-1)\n" for i in range(30))
    rewritten = "".join(f"- name: Stage {i}\n" for i in range(30))
    res = _fixture({"IaC/a.yml": many, "IaC/b.yml": many}, {"IaC/a.yml": rewritten})
    record("iii  a rewritten file is ALIGN-UNCERTAIN, never a sever",
           res["rc"] == 0 and res["result"]["uncertain_files"] == ["IaC/a.yml"],
           f"rc={res['rc']} uncertain={res['result']['uncertain_files']}")

    # Spelled as its own literal on purpose, not interpolated: this exact string is a twin of the
    # task names in roles/{router,switch}/tasks/main.yml and rb4011_converge.rsc.j2, so the file
    # that tests the twin rule has to keep the base bytes like every other side does.
    base_spell = "Drop mgmt services from non-mgmt sources"
    divergent = {
        "IaC/a.yml": f"- name: {base_spell}\n- name: Reboot the box (HD-1)\n",
        "IaC/b.yml": f"- name: {base_spell}, mgmt sources only\n- name: Reboot the box (HD-1)\n",
    }
    res = _fixture(divergent, divergent)
    grouped = sorted(res["result"]["groups"])
    record("iv   a family divergent at base is not a member, an agreed twin in the same pair is",
           res["rc"] == 0 and grouped == ["Reboot the box (HD-1)"],
           f"rc={res['rc']} groups={grouped} severs={sorted(res['result']['severs'])}")

    try:
        res = check(ROOT, CONTROL_REV, base=CONTROL_BASE_REV)
        moved = check(ROOT, CONTROL_REV)
        record(f"v    the positive control {CONTROL_BASE_REV} -> {CONTROL_REV} reads "
               f"{CONTROL_SEVERS} severed twins at a baseline of its own",
               res["rc"] == 1 and res["severs"] == CONTROL_SEVERS
               and CONTROL_BASE_REV != read_baseline(ROOT)["baseline_rev"]
               and moved["severs"] != CONTROL_SEVERS,
               f"pinned rc={res['rc']} severs={res['severs']} | "
               f"unpinned severs={moved['severs']} | {' | '.join(res['lines'])[:160]}")
    except ToolError as exc:
        record(f"v    the positive control {CONTROL_BASE_REV} -> {CONTROL_REV} reads "
               f"{CONTROL_SEVERS} severed twins", False, f"cannot run: {exc}")
    try:
        res = check(ROOT)
        record("vi   this tree reads no severed twin", res["rc"] == 0 and res["severs"] == 0,
               f"rc={res['rc']} severs={res['severs']}: {' | '.join(res['lines'])[:200]}")
    except ToolError as exc:
        record("vi   this tree reads no severed twin", False, f"cannot run: {exc}")

    # The now side is the index, not the directory: a side staged for deletion whose bytes are
    # still on disk is GONE. Before the filter this case read the disk and went green.
    res = _fixture(pair, {}, ("IaC/b.yml",))
    sides = sorted((f, s) for m in res["result"]["severs"].values() for f, _l, s in m)
    record("vii  a side git rm --cached, bytes still on disk, is GONE and severs the twin",
           res["rc"] == 1 and sides == [("IaC/a.yml", "Reboot the box (HD-1)"),
                                       ("IaC/b.yml", GONE)],
           f"rc={res['rc']} sides={sides}")

    # viii-xii: the shape a bulk purge produces, and the hole the P1 review proved. ONE literal
    # of the twin changes inside a run LONGER than LOCAL_RUN in a file that kept all its other
    # anchors, so the difflib pairing gives up on it and says ABSENT-UNCERTAIN. Presence does not
    # give up: it knows the base bytes are no longer in that file.
    anchored = "".join(f"- name: Anchor {i}\n" for i in range(20))
    steps = "".join(f"- name: Step {i}\n" for i in range(9))
    qsteps = "".join(f"- name: QStep {i}\n" for i in range(9))
    twin = "- name: Reboot the box (HD-1)\n"
    moved_twin = "- name: Reboot the box now (HD-1)\n"
    long_run = anchored + steps + twin
    long_run_moved = anchored + qsteps + moved_twin
    # a.yml's side is the SAME ABSENT-UNCERTAIN in viii, ix and x: the three differ only in what
    # the other side did, so no change can make all three pass by being uniformly stricter.
    a_side = file_sides(literals("IaC/a.yml", long_run),
                        literals("IaC/a.yml", long_run_moved))[0][-1]
    res = _fixture({"IaC/a.yml": long_run, "IaC/b.yml": twin}, {"IaC/a.yml": long_run_moved})
    named = sorted(f"{f}:{ln}" for m in res["result"]["severs"].values() for f, ln, _s in m)
    record("viii a sever inside a long run in an anchored file is red, every side named",
           res["rc"] == 1 and a_side == UNCLARABLE and res["result"]["uncertain_files"] == []
           and named == ["IaC/a.yml:30", "IaC/b.yml:1"],
           f"rc={res['rc']} a_side={a_side!r} sides={named} "
           f"uncertain={res['result']['uncertain_files']}: {' | '.join(res['lines'])[:160]}")

    # ix is viii with the other side renamed too: nothing carries the base bytes, both files
    # carry the one new value, and the run that could not pair either side still prints OK.
    res = _fixture({"IaC/a.yml": long_run, "IaC/b.yml": twin},
                   {"IaC/a.yml": long_run_moved, "IaC/b.yml": moved_twin})
    record("ix   the same long run renamed on every side stays green, proven by presence",
           res["rc"] == 0 and res["severs"] == 0 and res["result"]["unproven"] == {}
           and res["result"]["proven_by_presence"] == 1
           and file_sides(literals("IaC/a.yml", long_run),
                          literals("IaC/a.yml", long_run_moved))[0][-1] == UNCLARABLE,
           f"rc={res['rc']} severs={res['severs']} unproven={res['result']['unproven']} "
           f"presence={res['result']['proven_by_presence']}")

    # x  no side carries the base bytes and no side can name the value that took them: the gate
    # cannot decide, so it names the group and exits non-zero rather than printing OK.
    res = _fixture({"IaC/a.yml": long_run, "IaC/b.yml": twin},
                   {"IaC/a.yml": long_run_moved, "IaC/b.yml": ""})
    named = sorted(f"{f}:{ln}" for m in res["result"]["unproven"].values() for f, ln, _s in m)
    record("x    sides that all lost the base bytes with nothing to compare are NOT PROVEN",
           res["rc"] == 1 and res["severs"] == 0
           and list(res["result"]["unproven"]) == ["Reboot the box (HD-1)"]
           and named == ["IaC/a.yml:30", "IaC/b.yml:1"],
           f"rc={res['rc']} severs={res['severs']} unproven={list(res['result']['unproven'])} "
           f"sides={named}")

    # xi and xii narrow that rescue: finding the agreed value in the silent file is proof only of
    # the right KIND and only of ONE occurrence. Both cases are ix with one fact changed, so
    # neither can be satisfied by a rescue that simply got stricter about everything.
    # xi  the value survived in a.yml, but as `msg:` prose while the twin is a `name:`: the bytes
    # are there, the twin is not proven to be, so the group comes back NOT PROVEN and says where
    # it did find them.
    res = _fixture({"IaC/a.yml": long_run, "IaC/b.yml": twin},
                   {"IaC/a.yml": anchored + qsteps + "- msg: Reboot the box now (HD-1)\n",
                    "IaC/b.yml": moved_twin})
    why = " ".join(r for lines_ in res["result"]["unproven_reasons"].values() for r in lines_)
    record("xi   an agreed value that survives only in another kind of literal is NOT PROVEN",
           res["rc"] == 1 and res["severs"] == 0
           and list(res["result"]["unproven"]) == ["Reboot the box (HD-1)"]
           and res["result"]["proven_by_presence"] == 0
           and "IaC/a.yml" in why and "msg:" in why and "name:" in why
           and res["result"]["uncertain_files"] == [],
           f"rc={res['rc']} severs={res['severs']} unproven={list(res['result']['unproven'])} "
           f"presence={res['result']['proven_by_presence']} reason={why!r}")

    # xii the value survived twice in the twin's own class, in a file the run cannot align: which
    # of the two the twin became is not a fact bytes can settle, so AMBIGUOUS with the count.
    res = _fixture({"IaC/a.yml": long_run, "IaC/b.yml": twin},
                   {"IaC/a.yml": anchored + qsteps + moved_twin + moved_twin,
                    "IaC/b.yml": moved_twin})
    why = " ".join(r for lines_ in res["result"]["unproven_reasons"].values() for r in lines_)
    record("xii  an agreed value that occurs twice in that class is NOT PROVEN, AMBIGUOUS",
           res["rc"] == 1 and res["severs"] == 0
           and list(res["result"]["unproven"]) == ["Reboot the box (HD-1)"]
           and res["result"]["proven_by_presence"] == 0
           and "AMBIGUOUS" in why and "2 times" in why and "IaC/a.yml" in why,
           f"rc={res['rc']} severs={res['severs']} unproven={list(res['result']['unproven'])} "
           f"presence={res['result']['proven_by_presence']} reason={why!r}")

    if fails:
        print(f"FAIL: check_string_twins.py self-test, {len(fails)} case(s) wrong:")
        for f in fails:
            print(f"  - {f}")
        return 1
    print("OK: self-test -- a planted sever is named by file:line, a twin that moved on both "
          "sides is fine, a family that never agreed at base is outside the population, the "
          f"control revision still reads {CONTROL_SEVERS} and this tree reads 0, a mis-aligned "
          "file is reported instead of accused, the now side is the index rather than the "
          "directory, a sever hidden inside a long change run is named by presence in the file, "
          "a group this run cannot decide comes back red instead of OK, and the agreed value that "
          "settles a silent side has to be the twin's own kind of literal and occur exactly once")
    return 0


def _fixture(base_files: dict[str, str], now_files: dict[str, str],
             untracked: tuple[str, ...] = ()) -> dict:
    """A throwaway repo: commit 1 is the baseline, commit 2 records it, the working tree is
    `now`, and `untracked` paths are then dropped from the index by `git rm --cached` with
    their bytes left in place. Nothing outside a temp dir is touched, nothing is pushed."""
    d = Path(tempfile.mkdtemp(prefix="string-twins-"))
    env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_AUTHOR_NAME="t",
               GIT_AUTHOR_EMAIL="t@t.invalid", GIT_COMMITTER_NAME="t",
               GIT_COMMITTER_EMAIL="t@t.invalid")

    def run(*cmd: str) -> None:
        subprocess.run(cmd, cwd=d, env=env, check=True, capture_output=True)

    try:
        run("git", "init", "-q")
        for rel, text in base_files.items():
            (d / rel).parent.mkdir(parents=True, exist_ok=True)
            (d / rel).write_text(text, encoding="utf-8")
        run("git", "add", "-A")
        run("git", "commit", "-q", "-m", "baseline")
        rev = _git(d, "rev-parse", "HEAD").decode().strip()
        groups = twins(load(d, rev, files_at_rev(d, rev)))
        (d / BASELINE).parent.mkdir(parents=True, exist_ok=True)
        (d / BASELINE).write_text(f"baseline_rev {rev}\n"
                                  f"twin_groups {len(groups)}\n"
                                  f"group_keys_sha256 {group_keys_sha256(groups)}\n",
                                  encoding="utf-8")
        run("git", "add", "-A")
        run("git", "commit", "-q", "-m", "record the baseline")
        for rel, text in now_files.items():
            (d / rel).write_text(text, encoding="utf-8")
        for rel in untracked:
            run("git", "rm", "-q", "--cached", "--", rel)  # stages the delete, keeps the bytes
        return check(d)
    finally:
        subprocess.run(["rm", "-rf", str(d)], check=False)


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    try:
        if "--show-baseline" in argv:
            rev = read_baseline(ROOT, strict=False)["baseline_rev"]
            paths = files_at_rev(ROOT, rev)
            base = load(ROOT, rev, paths)
            groups = twins(base)
            settled = evaluate(base, load(ROOT, None, paths))["proven_by_presence"]
            print(f"baseline_rev {rev}\ntwin_groups {len(groups)}\n"
                  f"group_keys_sha256 {group_keys_sha256(groups)}")
            # A run statistic, not a fourth baseline field: --show-baseline is how a
            # re-baseline is produced, and pasting this line in would achieve nothing.
            print(f"proven-by-presence: {settled} group(s) decided where a side could not be "
                  f"aligned")
            return 0
        control = argv[argv.index("--control") + 1] if "--control" in argv else None
        res = check(ROOT, control)
        print("\n".join(res["lines"]))
        if "--families" in argv:
            report_families(res)
    except ToolError as exc:
        print(f"ERROR: {exc}")
        return 2
    return res["rc"]


def report_families(res: dict) -> None:
    """The normalized view, printed after the exact verdict and unable to change it."""
    rev = read_baseline(ROOT)["baseline_rev"]
    fam = families(load(ROOT, rev, files_at_rev(ROOT, rev)))
    split = {k: v for k, v in fam.items() if len({s for _f, _l, s in v}) > 1}
    print(f"REPORT-ONLY (this cannot fail the run, and a zero here is not evidence): "
          f"{len(fam)} normalized families span >=2 files, {len(split)} of them carry more "
          f"than one spelling at {rev}")
    for key, members in sorted(split.items())[:25]:
        print(f"  {key!r}")
        for f, ln, s in sorted(members):
            print(f"      {f}:{ln}  {s!r}")
    print("Normalized buckets under-report: they merge spellings that were never twins and "
          "split a purge that dropped other prose. The exact verdict is the one above.")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
