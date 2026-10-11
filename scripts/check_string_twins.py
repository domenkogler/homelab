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

Why this is green on day one BY CONSTRUCTION: the population is *defined* by byte-equality at
B. A family whose sides already differed at B cannot form an exact group, so the families this
repo has never agreed on are not members -- no allowlist, no exemptions, nothing to sign.
What the gate cannot see it says out loud instead of hiding: see BLIND SPOTS.

The baseline is pinned in scripts/twin_baseline.txt:

    baseline_rev <sha>       the revision the population is read from
    twin_groups <n>          how many >=2-file groups that revision yields
    group_keys_sha256 <hex>  sha256 over the sorted group keys -- sha256 per key, then the
                             hash of that stream, so a key containing a newline cannot shift
                             the digest of its neighbours

Those last two are the canary, the same job scripts/iac_identifier_allowlist.txt does for the
identifier lint: the population is a pure function of (baseline_rev, the extractor, the
scope), so moving B or narrowing the extractor changes the digest, and the run refuses to
pretend the population is still the one that was reviewed. Re-baseline at a wave tip -- B :=
wave tip, deliberately, in a commit that publishes all three values (`--show-baseline` prints
them). B is never more than one wave old: STALE_AFTER_COMMITS refuses a staler one, because
the per-file difflib alignment below degrades on a big feature commit and an old B turns
refactors into false severs.

Degradation, and why a refactor cannot produce a false sever -- a base occurrence's current
side is decided in this order:
    1  the exact base value still occurs somewhere in that file now -> unchanged (alignment
       plays no part here, so a reordering can never invent a change);
    2  otherwise the difflib opcode pairs it to a literal in the same SHORT local run (a
       replace/delete block of <= LOCAL_RUN base literals, and the file as a whole still
       anchored) -> the value it became, or GONE;
    3  otherwise -> ALIGN-UNCERTAIN: excluded from the verdict, reported by name. A
       mis-aligned file may never be the reason a twin is called severed; it is the reason the
       gate says it could not tell.
A purge is a short local run, so it is read exactly. A rewrite of 30 literals is not, so it
gets reported rather than accused.

BLIND SPOTS, stated because a gate read as stronger than it is gets trusted wrongly:
  * payload only -- YAML block scalars, shell heredocs, Jinja-rendered values and `#` comment
    prose are not literals. Nothing here sees a twin living inside a `|` block, and one Jinja
    expression makes two identical sources look different.
  * families that never agreed -- a twin whose sides already differed at B is not a member
    (the ~94 families the wave audit counted). `--families` prints a REPORT-ONLY normalized
    view of them and cannot fail the run, because a normalized bucket under-reports -- the
    audit's normalized buckets missed a real sever until a paren-dropping variant was added --
    so a verdict built on that number would be decoration.
  * a twin renamed on every side in one commit leaves the population: the new spelling is not
    keyed at B, so the gate is blind to it until the next re-baseline. That is the price of
    having no allowlist.

Run:   python3 scripts/check_string_twins.py [--control REV] [--families] [--show-baseline]
       python3 scripts/check_string_twins.py --self-test
Exit:  0 clean; 1 severed twin(s), each side named as file:line; 2 the gate could not measure
       (no full history, a baseline more than one wave old, a baseline file that does not
       match the population it describes, an unreadable revision).
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

ROOT = Path(__file__).resolve().parent.parent
BASELINE = "scripts/twin_baseline.txt"
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

GONE = "\x00gone"
UNCERTAIN = "\x00uncertain"
SIDE_NOTE = {GONE: "GONE (this side no longer carries the base value at all)",
             UNCERTAIN: "ALIGN-UNCERTAIN (excluded from this group's verdict)"}
# A replace/delete run this long is not one local edit any more; the pairing inside it stops
# being evidence and becomes ALIGN-UNCERTAIN.
LOCAL_RUN = 6
# ...and a file that kept less than this share of its literal anchors is mis-aligned as a
# whole, so no pairing inside it counts however short each individual run looks.
GLOBAL_RATIO = 0.5
GLOBAL_MIN = 10
# One wave measured 176 commits (34e77f82 -> 953255b8). Past this many the baseline is no
# longer "the current wave", which is the only window this gate is honest about.
STALE_AFTER_COMMITS = 300

# The positive control: the tip before the wave-2 twin repairs, where exactly this many twin
# groups had been severed. The self-test re-reads it, so a gate that lost its teeth reddens.
CONTROL_REV = "8b28edd3"
CONTROL_SEVERS = 6

# A family the exact gate CANNOT be a member of, kept as a live self-test case rather than a
# claim in a report: at the baseline only the roles/router side carried the id, so no exact
# group spans all three sites, and the gate is green here by construction. If a change ever
# makes these spellings byte-equal, the exact group starts existing and the gate starts
# guarding them -- which is the whole point.
DIVERGENT_FAMILY = "Drop mgmt services from non-mgmt sources"
DIVERGENT_FILES = ("IaC/ansible/roles/router/tasks/main.yml",
                   "IaC/ansible/roles/switch/tasks/main.yml",
                   "IaC/router/templates/rb4011_converge.rsc.j2")


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


def literals(rel: str, text: str) -> list[tuple[int, str]]:
    """(line, value) for every literal this file writes or renders, in document order."""
    found: list[tuple[int, str]] = []
    for n, raw in enumerate(text.splitlines(), 1):
        code = strip_comment(raw)
        if not code.strip():
            continue
        m = KEY_VALUE.match(code)
        if m:
            v = _dequote(m.group("val"))
            if v and not v.startswith(SCALAR_PREFIX):
                found.append((n, v))
        for mm in ROS_COMMENT.finditer(code):
            v = _dequote(mm.group("val"))
            if v:
                found.append((n, v))
        if rel.endswith(QUOTED_SUFFIXES):
            for mm in QUOTED.finditer(code):
                found.append((n, mm.group(1)))
    if rel.endswith(".py"):
        try:
            for node in ast.walk(ast.parse(text)):
                if isinstance(node, ast.Constant) and isinstance(node.value, str) \
                        and len(node.value) >= 2:
                    found.append((getattr(node, "lineno", 0), node.value))
        except SyntaxError:
            pass  # a file that does not parse is the portability sweep's problem, not this one
    seen, deduped = set(), []
    for ln, v in found:
        if (ln, v) not in seen:
            seen.add((ln, v))
            deduped.append((ln, v))
    return deduped


def load(repo: Path, rev: str | None, paths: list[str]) -> dict[str, list[tuple[int, str]]]:
    """Literal lists for `paths`, from one revision or from the working tree."""
    out: dict[str, list[tuple[int, str]]] = {}
    for rel in paths:
        text = _read(repo, rev, rel)
        out[rel] = literals(rel, text) if text is not None else []
    return out


def file_sides(base: list[tuple[int, str]], now: list[tuple[int, str]]) -> tuple[list[str], bool]:
    """One current side per base occurrence, in base order; second value = mis-aligned.

    Order of proof is in the module docstring. `GONE` means the side no longer carries the
    base value and the alignment says nothing replaced it there; `UNCERTAIN` means the file
    moved too much for this run to answer, and it must never be counted as a change.
    """
    a = [v for _ln, v in base]
    b = [v for _ln, v in now]
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
        trustworthy = (i2 - i1) <= LOCAL_RUN and not misaligned
        span = min(i2 - i1, j2 - j1)
        for k in range(i2 - i1):
            if not trustworthy:
                paired[i1 + k] = UNCERTAIN
            elif k < span:
                paired[i1 + k] = b[j1 + k]
    return [v if v in present else paired[i] for i, v in enumerate(a)], misaligned


def group_keys_sha256(keys) -> str:
    """sha256 of the sorted keys, hashed one digest per key so a key may contain a newline."""
    h = hashlib.sha256()
    for k in sorted(keys):
        h.update(hashlib.sha256(k.encode("utf-8", "surrogatepass")).digest())
    return h.hexdigest()


def twins(base_lits: dict[str, list[tuple[int, str]]]) -> dict[str, list[tuple[str, int]]]:
    """base value -> [(file, line)] for values at least TWO files shipped at the baseline."""
    groups: dict[str, list[tuple[str, int]]] = {}
    for rel, lits in base_lits.items():
        for ln, v in lits:
            groups.setdefault(v, []).append((rel, ln))
    return {k: v for k, v in groups.items() if len({f for f, _ in v}) >= 2}


def evaluate(base_lits: dict[str, list[tuple[int, str]]],
             now_lits: dict[str, list[tuple[int, str]]]) -> dict:
    """The verdict on one base population read two ways. Pure: no git, no filesystem."""
    groups = twins(base_lits)
    sides: dict[str, list[tuple[str, int, str]]] = {}
    uncertain: list[str] = []
    for rel, bl in base_lits.items():
        got, misaligned = file_sides(bl, now_lits.get(rel, []))
        if misaligned:
            uncertain.append(rel)
        for (ln, v), side in zip(bl, got):
            sides.setdefault(v, []).append((rel, ln, side))
    severs: dict[str, list[tuple[str, int, str]]] = {}
    undecidable = 0
    for key, members in groups.items():
        decided = [s for _f, _l, s in sides[key] if s != UNCERTAIN]
        if not decided:
            undecidable += 1
        elif len(set(decided)) > 1:
            severs[key] = sides[key]
    return {"groups": groups, "severs": severs, "uncertain_files": sorted(uncertain),
            "undecidable_groups": undecidable,
            "files": len(base_lits), "literals": sum(len(v) for v in base_lits.values())}


def normalize(v: str) -> str:
    """Family stem: drop ` (...)` and `HD-<n>`, collapse whitespace. Report-only view."""
    stem = re.sub(r"\s*\([^)]*\)", " ", v)
    stem = re.sub(r"HD-\d+", " ", stem)
    return re.sub(r"\s+", " ", stem).strip()


def families(base_lits: dict[str, list[tuple[int, str]]]) -> dict[str, list[tuple[str, int, str]]]:
    """Normalized families spanning >=2 files -- a hint about what the exact gate cannot see.

    A normalized bucket merges spellings that were never twins and splits a purge that dropped
    other prose, so the number it prints is neither a verdict nor evidence of one.
    """
    out: dict[str, list[tuple[str, int, str]]] = {}
    for rel, lits in base_lits.items():
        for ln, v in lits:
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


def check(repo: Path, control: str | None = None) -> dict:
    """One run against a repo. Returns rc, the lines to print, and the numbers behind them."""
    started = time.monotonic()
    fields = read_baseline(repo)
    base_rev = fields["baseline_rev"]
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
    behind = int(_git(repo, "rev-list", "--count", f"{base_rev}..HEAD").decode().strip())
    if behind > STALE_AFTER_COMMITS:
        return _refuse(f"ERROR: the baseline is {behind} commits behind HEAD",
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
    if len(groups) != recorded or group_keys_sha256(groups) != fields["group_keys_sha256"]:
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
        if result["undecidable_groups"]:
            lines.append(f"      ({result['undecidable_groups']} group(s) had no decidable "
                         f"side at all -- green here means not proven, not checked)")
    if result["severs"]:
        lines.append(f"FAIL: {len(result['severs'])} twin group(s) byte-equal at {base_rev} "
                     f"are not byte-identical now:")
        for key, members in sorted(result["severs"].items()):
            lines.append(f"  base value {key[:120]!r}")
            lines += [f"      {f}:{ln}  {SIDE_NOTE.get(s, repr(s))}" for f, ln, s in members]
        lines.append("A twin is one fact in two places. Rename every side in this commit (the "
                     "base bytes win), or -- if the twin really is gone now -- re-baseline at "
                     "the wave tip so the population records that out loud.")
        return {"rc": 1, "lines": lines, "severs": len(result["severs"]), "result": result}
    lines.append(f"OK: {len(groups):,} string twins from {base_rev} are byte-identical on "
                 f"every side ({elapsed:.1f} s)")
    return {"rc": 0, "lines": lines, "severs": 0, "result": result}


def _refuse(head: str, why: str) -> dict:
    return {"rc": 2, "lines": [head, f"      {why}"], "severs": 0, "result": {}}


def divergent_family(repo: Path, base_rev: str) -> dict:
    """What the exact gate sees of one known-divergent family in this repo (self-test iii)."""
    paths = [p for p in files_at_rev(repo, base_rev) if p in DIVERGENT_FILES]
    base = load(repo, base_rev, paths)
    exact: dict[str, list[str]] = {}
    for rel, lits in base.items():
        for _ln, v in lits:
            if v.startswith(DIVERGENT_FAMILY):
                exact.setdefault(v, []).append(rel)
    fam_files = sorted({f for k, v in families(base).items() if k == normalize(DIVERGENT_FAMILY)
                        for f, _l, _s in v})
    verdict = evaluate(base, load(repo, None, paths))
    return {"exact": {k: sorted(set(fs)) for k, fs in exact.items()},
            "family_files": fam_files,
            "severs": sorted(verdict["severs"])}


def self_test() -> int:
    """Six cases. Two are planted, one is a real family in this repo, one is the positive
    control, one is this tree, one is the degradation guard -- the five properties the gate
    claims, each built so it cannot pass by accident."""
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

    try:
        rev = read_baseline(ROOT)["baseline_rev"]
        fam = divergent_family(ROOT, rev)
        spans = sorted({f for fs in fam["exact"].values() for f in fs})
        lone = [k for k, fs in fam["exact"].items() if len(fs) == 1]
        record("iv   a family divergent at base is not a member (Drop mgmt services ...)",
               fam["severs"] == [] and len(fam["exact"]) > 1 and lone
               and set(spans) <= set(fam["family_files"]) and len(spans) >= 3,
               f"exact={fam['exact']} family_files={fam['family_files']} severs={fam['severs']}")
    except ToolError as exc:
        record("iv   a family divergent at base is not a member (Drop mgmt services ...)",
               False, f"cannot read this repo: {exc}")

    for rev, want, name in ((CONTROL_REV, CONTROL_SEVERS,
                             f"v    the positive control {CONTROL_REV} reads "
                             f"{CONTROL_SEVERS} severed twins"),
                            (None, 0, "vi   this tree reads no severed twin")):
        try:
            res = check(ROOT, rev)
        except ToolError as exc:
            record(name, False, f"cannot run: {exc}")
            continue
        record(name, res["rc"] == (0 if want == 0 else 1) and res["severs"] == want,
               f"rc={res['rc']} severs={res['severs']}: {' | '.join(res['lines'])[:200]}")

    if fails:
        print(f"FAIL: check_string_twins.py self-test, {len(fails)} case(s) wrong:")
        for f in fails:
            print(f"  - {f}")
        return 1
    print("OK: self-test -- a planted sever is named by file:line, a twin that moved on both "
          "sides is fine, a family that never agreed at base is outside the population, the "
          f"control revision still reads {CONTROL_SEVERS} and this tree reads 0, and a "
          "mis-aligned file is reported instead of accused")
    return 0


def _fixture(base_files: dict[str, str], now_files: dict[str, str]) -> dict:
    """A throwaway repo: commit 1 is the baseline, commit 2 records it, the working tree is
    `now`. Nothing outside a temp dir is touched, and nothing is pushed anywhere."""
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
        return check(d)
    finally:
        subprocess.run(["rm", "-rf", str(d)], check=False)


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    try:
        if "--show-baseline" in argv:
            rev = read_baseline(ROOT, strict=False)["baseline_rev"]
            groups = twins(load(ROOT, rev, files_at_rev(ROOT, rev)))
            print(f"baseline_rev {rev}\ntwin_groups {len(groups)}\n"
                  f"group_keys_sha256 {group_keys_sha256(groups)}")
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
