#!/usr/bin/env python3
"""check_script_layout.py — the ratchet that makes HD-1118's folder tree STAY (Stage 4).

WHY THIS EXISTS, in one sentence: Stage 3 moved 79 scripts into 8 folders with a sweep, and a sweep
is a one-time act — every rule below is the form a one-time act takes when it becomes a property, so
"the scripts are grouped" stops being a fact about today's tree and starts being something a commit
cannot quietly undo.

Five rules, each with a FLOOR rather than a target, because a ratchet that reports 41 findings the
first run is a ratchet that gets silenced (the width-rule lesson, check_md_tables.py):

  1. REGISTRY   — every tracked file under scripts/ has EXACTLY ONE row in scripts/README.md, and
                  every path the README names under scripts/ exists. This is the rule that would
                  have caught `pi-self-update.sh` shipping a whole seat plane with no registry row.
  2. COMMANDS   — every `scripts/<path>` literal that is used as a command target resolves to a
                  file. Deliberately overlaps check_doc_path_refs.py: that one is fail-closed on
                  markdown LINKS, this one on COMMANDS, and a moved script breaks both kinds.
  3. DEPTH      — no fixed-depth repo-root derivation survives outside scripts/lib/. Stage 1 replaced
                  54 of them; this is what stops one growing back in a file nobody reviewed.
  4. ONE OF EACH — one pin(), one repo-root resolver, one plane registry. Floor 1, in lib/.
  5. ROOT       — scripts/ top level holds the entry points and README.md, nothing else: no .ps1,
                  no data file, no stray executable. testdata/** is excluded everywhere (fixtures
                  are trees, not tools).

Everything is corpus-asserted: the walk, the README rows and the literal scan each have a floor, so
a broken repo root makes this FAIL LOUD instead of printing OK: 0 files — the failure mode HD-1118
was whole about.

--self-test breeds each rule in a synthetic tree and fails if the breeding was not caught, and also
proves the checker is not silently green on an empty corpus.

Exit: 0 clean · 1 finding(s) · 2 could not run. Stdlib + git only.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root  # noqa: E402

ROOT = _hl_root(__file__)
REGISTRY = ROOT / "scripts" / "README.md"
# Fixture paths are COMPOSED (`f"{S}/stray.sh"`), not literals: to `git grep scripts/[a-z-]*\.\w+` —
# which IS HD-1118's acceptance test — a literal `scripts/<name>.sh` inside a fixture string is
# indistinguishable from a reference to a real repo path. A gate that fails the repo's own
# cleanliness check because of its own test data teaches the reader nothing.
S = "scripts"

# --- rule 3: fixed-depth root derivation (the Stage 1 class) -------------------------------
DEPTH_PATTERNS = (
    ("python fixed depth", re.compile(r"Path\(__file__\)\.resolve\(\)\.parent\.parent\b")),
    ("python parents[N]", re.compile(r"Path\(__file__\)\.resolve\(\)\.parents\s*\[")),
    ("bash $SCRIPT_DIR/..", re.compile(r"""["']?\$?\{?SCRIPT_DIR\}?/\.\./?""")),
    ("bash B_SOURCE/..", re.compile(r"""BASH_SOURCE\[0\]\}"?\)?/\.\.""")),
    ("bash $0/..", re.compile(r"""dirname "\$0"\)?/\.\.""")),
    ("powershell fixed depth", re.compile(r"\$PSScriptRoot[\\/]\.\.[\\/]")),
)
# --- rule 4: the one-of-each shapes ---------------------------------------------------------
ONE_EACH = (
    ("pin()", re.compile(r"^\s*(?:function\s+)?pin\(\)\s*\{", re.M), 1),
    ("repo-root resolver", re.compile(r"^\s*(?:function\s+)?(?:find_repo_root|repo_root)\(\)\s*\{", re.M), 1),
    # The driver's old shape: plane argv as string constants. The registry replaced them; a new one
    # here means somebody wrote a plane list again instead of adding a row to lib/seat-planes.yml.
    ("plane argv constant", re.compile(r"^[A-Z_]+_[CP]='(?:bash|python3|powershell)", re.M), 0),
    ("hand-written plane list", re.compile(r"^\s*(?:local\s+)?common=\"[^\n]*\|bash scripts", re.M), 0),
)
# --- rule 5: what may live at scripts/ top level -------------------------------------------
ROOT_ALLOWED = {"README.md", "validate-all.sh", "render_all.py", "next-hd.sh"}
DATA_SUFFIX = (".txt", ".yml", ".yaml", ".json", ".csv", ".ini", ".conf", ".toml", ".md")
ARTIFACT_PARTS = ("/raw/", "/accuracy/", "/testdata/")
# Dated records cite the tree as it was; check_doc_path_refs owns that exemption for links, and
# this checker keeps the same rule for commands so the two do not disagree about reality.
FROZEN_PREFIX = ("reports/", "brainstorming/")
# COMMAND-POSITION ONLY — and that restriction is the whole reason this rule is not 20 false
# positives on its first run. A bare mention in prose is check_doc_path_refs' territory (it owns the
# placeholder / "the prose SAYS this is missing" / frozen-archive exemptions, and re-deriving them
# here would give two checkers two opinions about the same sentence). What nobody else catches is an
# INVOCATION: `bash scripts/<name>.sh`, `$REPO/scripts/<name>.py`. Those are the references that break a run,
# not a paragraph.
_Q = '[' + "\"" + chr(39) + ']*'   # an optional opening quote, spelled so this file stays readable
CMD_HEAD = (r'(?:(?:bash|sh|zsh|python3|python|pwsh|powershell(?:\.exe)?)\s+' + _Q +
            r'|(?:REPO\}|REPO|\$\{?REPO\}?|\$\{?PWD\}?)/)')
CMD_LITERAL = re.compile(CMD_HEAD + r'scripts/([A-Za-z0-9_./-]+\.(?:sh|py|ps1))(?![A-Za-z0-9_-])')
PLACEHOLDER = re.compile(r"[*?\[\]{}$<>]")
UNFINISHED = re.compile(r"(?i)create if missing|todo|not yet (built|created)|proposed|would need")


SELF = re.compile(r"(^|/)check_script_layout\.py$")


def is_self(rel: str) -> bool:
    """A scanner's own source contains the shapes it looks for — the pattern strings, the fixture
    text it writes in --self-test, and the `scripts/<name>.py` examples in its docstring. HD-1118
    Stage 4 proved this matters the lazy way: this file was UNTRACKED while I iterated, so the tree
    scan skipped it and its first commit is the first run that read its own source — and it found
    four violations in a file that only DESCRIBES violations. Same device check_secrets.py uses
    (its `SELF` exemption), same reason, basename-scoped for the same reason: a move must not break
    it, and a neighbour file with the same shape must still be reported (the fixture tree proves
    that half)."""
    return bool(SELF.search(rel))


def tracked() -> list[str]:
    out = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z"],
                         capture_output=True, text=True, check=True).stdout
    return [p for p in out.split("\0") if p]


def is_artifact(rel: str) -> bool:
    return any(part in "/" + rel for part in ARTIFACT_PARTS)


def scripts_files(files: list[str]) -> list[str]:
    """Tracked files under scripts/ that the registry must account for: executables and declared
    data. Evidence (bench raw/accuracy) and fixtures (testdata) are excluded — a row per captured
    csv would be noise that trains the reader to ignore the table."""
    keep = []
    for rel in files:
        if not rel.startswith("scripts/") or rel == "scripts/README.md" or is_artifact(rel):
            continue
        if (ROOT / rel).is_file():
            keep.append(rel)
    return keep


def registry_rows(text: str) -> list[str]:
    return text.splitlines()


def check_registry(files: list[str], text: str, root: Path) -> list[str]:  # noqa: C901
    findings: list[str] = []
    all_lines = text.splitlines()
    # Only rows BELOW the marker are registry rows. The file's own "what lives where" table names
    # lib/seat-planes.yml and friends in prose, and an intro paragraph that happens to sit in a
    # table is not a registry entry — the marker says where the registry starts, and its absence is
    # an error rather than a silent zero.
    try:
        start = next(i for i, ln in enumerate(all_lines) if "REGISTRY ROWS BELOW" in ln)
    except StopIteration:
        return [f"REGISTRY: {REGISTRY} carries no 'REGISTRY ROWS BELOW' marker — the layout gate "
                "cannot tell an index table from a registry, and guessing is how a file ends up with "
                "zero rows and a green gate"]
    rows = [ln for ln in all_lines[start:] if ln.startswith("| ")]
    # Self-scaling floor: a registry that reads almost no rows is a registry that was not READ (an
    # absolute 40 would also make the fixture tree impossible to test, and a checker you cannot
    # exercise is a checker you cannot trust).
    require_corpus(len(rows), max(1, len(scripts_files(files)) // 4),
                   "check_script_layout registry rows in scripts/README.md")
    for rel in scripts_files(files):
        folder, name = os.path.split(rel)
        # A row may cite the path (scripts/gate/x.py), the folder-relative link target
        # (gate/x.py, after the sweep rewrote links) or the bare name in prose.
        hits: list[int] = []
        for n, ln in enumerate(all_lines, 1):
            if n <= start or not ln.startswith("| "):
                continue        # registry rows live BELOW the marker, see above
            # A row is KEYED by its FIRST CELL — the same rule check_md_tables.py uses for its
            # duplicate-identity half. Prose in a later cell that mentions another script ("the
            # playbook twin of scripts/ansible/ansible-run.sh") is not that script's row, and
            # counting it invented duplicates that sent the reader hunting for a table that was
            # already correct.
            first = ln.split("|")[1] if ln.count("|") > 1 else ""
            # Registry rows are grouped per folder, and a row's link is relative to ITS SECTION
            # (`](win/install-nerd-font.ps1)` inside `## scripts/harness/`). Resolving links
            # without that context reported a real, correctly-linked row as MISSING — the worse
            # kind of false positive, because it teaches the reader to add a duplicate row.
            section = ""
            for back in range(n - 1, start, -1):
                h = all_lines[back]
                if h.startswith("## `scripts/"):
                    section = h.split("`scripts/")[1].split("/`")[0] if "/" in h.split("`scripts/")[1] else ""
                    break
            if name.endswith(tuple(DATA_SUFFIX)) and not os.access(root / rel, os.X_OK):
                if f"`{name}`" in first or rel in first or f"{folder.replace('scripts/', '')}/{name}" in first:
                    hits.append(n)
                continue
            if rel in first:
                hits.append(n)
            else:
                # Both shapes are accepted: the folder-prefixed target the sweeps produced
                # (`](gate/x.py)` anywhere) and the section-relative one a hand-written row uses
                # (`](win/x.ps1)` under ## scripts/harness/).
                here = "scripts/" + (section + "/" if section else "")
                for m in re.finditer(r"\]\(([^)#]+)", first):
                    tgt = m.group(1)
                    while tgt.startswith("../"):
                        tgt = tgt[3:]
                    tgt = tgt[len("scripts/"):] if tgt.startswith("scripts/") else tgt
                    if here + tgt == rel or ("scripts/" + tgt) == rel:
                        hits.append(n)
                        break
        if not hits:
            findings.append(f"REGISTRY: {rel} has NO row in scripts/README.md "
                            f"(this is how pi-self-update.sh shipped a seat plane nobody could find)")
        elif len(hits) > 1:
            findings.append(f"REGISTRY: {rel} has {len(hits)} rows (lines "
                            f"{', '.join(map(str, hits))}) — a dispatcher that lists a file twice is "
                            "a dispatcher that will update one of them")
    # LINK targets only. A prose mention is check_doc_path_refs' jurisdiction (it owns the
    # placeholder and "the prose says this is missing" exemptions) — this rule is about the paths
    # the registry PROMISES, and an example like `scripts/<name>.py` inside another script's row is not
    # a promise, it is an illustration of a different checker.
    for m in re.finditer(r"\]\(([^)\s#]+?\.(?:sh|py|ps1|yml|json|csv|txt|conf))(?:#[^)]*)?\)", text):
        cand = m.group(1)
        while cand.startswith("../"):
            cand = cand[3:]
        if not cand.startswith("scripts/"):
            continue
        if PLACEHOLDER.search(cand) or (root / cand).exists():
            continue
        if not any((root / "scripts").rglob(os.path.basename(cand))):
            findings.append(f"REGISTRY: scripts/README.md names {cand}, which does not exist and "
                            "did not merely move")
    return findings


def check_commands(files: list[str]) -> list[str]:
    findings: list[str] = []
    scanned = 0
    for rel in files:
        if rel.startswith(FROZEN_PREFIX) or rel.endswith(".log") or is_artifact(rel):
            continue
        if is_self(rel):
            continue        # fixture text this file WRITES is not an invocation by this file
        try:
            raw = (ROOT / rel).read_bytes()
        except OSError:
            continue
        if b"\0" in raw:
            continue
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            continue
        scanned += 1
        if rel.startswith("skills/"):
            # Inside a skill, `scripts/<name>.py` is the SKILL's own scripts/ directory — skills/shelly
            # documents `python scripts/shelly.py` and means skills/shelly/scripts/shelly.py. The
            # sweep tools learned this the hard way (31 hits in shelly alone); a gate that "fixes"
            # it invents scripts/gate/shelly.py and then reports a dangling path that never existed.
            continue
        for m in CMD_LITERAL.finditer(text):
            line = text[:m.start()].rsplit("\n", 1)[-1] + text[m.start():].split("\n", 1)[0]
            if UNFINISHED.search(line):
                # Explicitly unfinished: "(create if missing)", a TODO, a proposal. check_doc_path_refs
                # exempts the same shape for links under "placeholder"; this is that rule for commands.
                continue
            if m.start() and text[m.start() - 1] == "/" and not text[max(0, m.start() - 8):m.start()].endswith(("REPO/", "REPO}/")):
                continue   # a DIFFERENT scripts/ dir: skills/<skill>/scripts/<tool>.py is not this folder
            target = "scripts/" + m.group(1)
            if (ROOT / target).exists():
                continue
            base = os.path.basename(target)
            moved = [p for p in (ROOT / "scripts").rglob(base) if not is_artifact(str(p))]
            if moved:
                findings.append(f"COMMANDS: {rel} invokes {target}, which moved to "
                                f"{moved[0].relative_to(ROOT)}")
            else:
                findings.append(f"COMMANDS: {rel} invokes {target}, which does not exist anywhere "
                                "under scripts/")
    # Self-scaling for the same reason as the registry floor: the fixture tree is 7 files, and a
    # floor that only the real repo can clear is a floor the self-test can never exercise.
    require_corpus(scanned, max(1, len(files) // 3),
                   "check_script_layout command-literal corpus (tracked files scanned)")
    return findings


def check_depth(files: list[str]) -> list[str]:
    findings: list[str] = []
    for rel in files:
        if not rel.startswith("scripts/") or rel.startswith("scripts/lib/") or is_artifact(rel):
            continue
        if is_self(rel):
            continue        # see SELF's note: this file contains the shapes it hunts
        if not rel.endswith((".sh", ".py", ".ps1", ".bash")):
            continue
        try:
            text = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for label, pat in DEPTH_PATTERNS:
            for n, ln in enumerate(text.splitlines(), 1):
                # Scan the EXECUTABLE part of the line. HD-1118's own commits left sentences like
                # "it used to be `$(dirname "$0")/..`" in comments, and a ratchet that reports
                # prose gets switched off by the next person who documents a fix — the width-rule
                # lesson again. A `#` inside a quoted string can hide a real hit; that trade is
                # deliberate and stated here rather than discovered later.
                if pat.search(ln.split("#", 1)[0]):
                    findings.append(f"DEPTH: {rel}:{n} derives the repo root from a DEPTH ({label}) — "
                                    "use scripts/lib/repo-root.sh or repo_root.root(); a fixed depth "
                                    "is what turns a folder move into a gate that checks nothing")
    return findings


def check_one_each(files: list[str]) -> list[str]:
    findings: list[str] = []
    for rel in files:
        if not rel.startswith("scripts/") or is_artifact(rel) or rel.endswith(".md"):
            continue
        if is_self(rel):
            continue        # the ONE_EACH patterns appear in this file as PATTERNS, not definitions
        try:
            text = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        in_lib = rel.startswith("scripts/lib/")
        for label, pat, floor in ONE_EACH:
            n = len(pat.findall(text))
            if n == 0:
                continue
            if in_lib:
                if n > floor:
                    findings.append(f"ONE OF EACH: {rel} defines {n} {label} definitions (floor {floor})")
                continue
            findings.append(f"ONE OF EACH: {rel} defines {label} outside scripts/lib/ — the shared "
                            "helper exists so the seat family cannot drift apart one copy at a time")
    return findings


def check_root(files: list[str]) -> list[str]:
    findings: list[str] = []
    for rel in files:
        parts = rel.split("/")
        if len(parts) != 2 or parts[0] != "scripts":
            continue
        name = parts[1]
        if name in ROOT_ALLOWED:
            continue
        if name.endswith(".ps1"):
            findings.append(f"ROOT: {rel} is a PowerShell script at scripts/ top level — every .ps1 "
                            "belongs with the platform it runs on")
        elif name.endswith(DATA_SUFFIX):
            findings.append(f"ROOT: {rel} is a data file at scripts/ top level — data lives with the "
                            "tool that owns it (a scratch pad at the root is how utils.txt became "
                            "the only copy of four commands)")
        elif os.access(ROOT / rel, os.X_OK):
            findings.append(f"ROOT: {rel} is an executable at scripts/ top level; the root keeps "
                            f"{sorted(ROOT_ALLOWED)}")
    return findings


def check(files: list[str], text: str, root: Path = ROOT) -> list[str]:
    return (check_registry(files, text, root) + check_commands(files)
            + check_depth(files) + check_one_each(files) + check_root(files))


def self_test() -> int:
    # The fixture tree has to BE the repo for the duration, so the module-level ROOT/REGISTRY are
    # swapped and restored — the alternative is passing a root through every rule, which is how a
    # checker ends up testing a path that is not the one production reads.
    global ROOT, REGISTRY
    fails = 0
    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp)
        (t / "scripts" / "lib").mkdir(parents=True)
        (t / "scripts" / "gate").mkdir(parents=True)
        (t / "docs").mkdir()
        (t / "docs" / "index.md").write_text("# root marker\n")
        (t / "IaC").mkdir()
        (t / "IaC" / "ansible").mkdir()
        good = t / "scripts" / "gate" / "good.py"
        good.write_text("from pathlib import Path\nROOT = Path(__file__).resolve().parents[3]\n")
        (t / "scripts" / "lib" / "repo-root.sh").write_text("#!/usr/bin/env bash\n")
        (t / "scripts" / "lib" / "pi-seat.sh").write_text("#!/usr/bin/env bash\npin() {\n  :\n}\n")
        (t / "scripts" / "stray.sh").write_text("#!/usr/bin/env bash\nREPO=\"$(cd \"$SCRIPT_DIR/..\" && pwd)\"\n")
        (t / "scripts" / "utils.txt").write_text("a note\n")
        (t / "scripts" / "thing.ps1").write_text("# ps\n")
        (t / "scripts" / "README.md").write_text(
            "<!-- REGISTRY ROWS BELOW -->\n| file | what | doc |\n|---|---|---|\n"
            "| [`good.py`](gate/good.py) | names nothing that is missing | docs/index.md |\n")
        files = ["scripts/lib/repo-root.sh", "scripts/lib/pi-seat.sh", "scripts/gate/good.py",
                 f"{S}/stray.sh", f"{S}/utils.txt", f"{S}/thing.ps1", f"{S}/README.md"]
        real_root, real_reg = ROOT, REGISTRY
        ROOT, REGISTRY = t, t / "scripts" / "README.md"
        try:
            out = "\n".join(check(files, REGISTRY.read_text(), t))

            def expect(needle: str, what: str) -> None:
                nonlocal fails
                if needle in out:
                    print(f"  OK    {what} — caught")
                else:
                    print(f"  FAIL  {what} — NOT CAUGHT\n{out}", file=sys.stderr)
                    fails += 1

            expect("has NO row", "a script with no registry row")
            expect("DEPTH:", "a fixed-depth root derivation outside lib/")
            expect("ROOT: scripts/utils.txt", "a data file at scripts/ top level")
            expect(f"ROOT: {S}/thing.ps1", "a .ps1 at scripts/ top level")
            # A resolving literal and the lib/ helper must NOT be reported: an exemption that
            # fires on the wrong file is how a ratchet gets turned off.
            if any(f.startswith("COMMANDS:") for f in out.splitlines()):
                print("  FAIL  a command literal that resolves was reported", file=sys.stderr)
                fails += 1
            else:
                print("  ok    a resolving command literal is not reported")
            if any("ONE OF EACH" in f and "scripts/lib/" in f for f in out.splitlines()):
                print("  FAIL  the lib/ exemption did not hold (the helper IS the one allowed copy)",
                      file=sys.stderr)
                fails += 1
            else:
                print("  ok    lib/ stays exempt")
            # and a second pin() OUTSIDE lib must be caught
            (t / "scripts" / "gate" / "other.sh").write_text("#!/usr/bin/env bash\npin() {\n  :\n}\n")
            out2 = "\n".join(check(files + ["scripts/gate/other.sh"], REGISTRY.read_text(), t))
            if any("ONE OF EACH" in f and "other.sh" in f for f in out2.splitlines()):
                print("  OK    a second pin() outside lib/ — caught")
            else:
                print("  FAIL  a second pin() outside lib/ — NOT CAUGHT", file=sys.stderr)
                fails += 1
            # A registry without the marker must be a STOP, never "zero rows, all present".
            (t / "scripts" / "README.nomark.md").write_text("| file | what | doc |\n|---|---|---|\n")
            nomark = "\n".join(check(files, (t / "scripts" / "README.nomark.md").read_text(), t))
            if "REGISTRY ROWS BELOW" in nomark:
                print("  OK    a registry with no section marker — caught")
            else:
                print("  FAIL  a registry with no section marker was silently treated as empty", file=sys.stderr)
                fails += 1
            # and the corpus floor must not let an empty tree read as clean
            try:
                require_corpus(0, 200, "fixture corpus")
                print("  FAIL  an empty corpus passed the floor", file=sys.stderr)
                fails += 1
            except SystemExit:
                print("  ok    an empty corpus fails loud (the HD-1118 failure mode, fenced)")
        finally:
            ROOT, REGISTRY = real_root, real_reg
    return 1 if fails else 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return self_test()
    files = tracked()
    require_corpus(len([f for f in files if f.startswith("scripts/")]), 60,
                   "check_script_layout tracked scripts/ corpus")
    if not REGISTRY.is_file():
        print(f"FATAL: no registry at {REGISTRY} — a layout gate with no registry to read "
              "checks nothing", file=sys.stderr)
        return 2
    findings = check(files, REGISTRY.read_text(encoding="utf-8"))
    n_scripts = len(scripts_files(files))
    if findings:
        print(f"FAIL: scripts/ layout: {len(findings)} finding(s) across {n_scripts} tracked file(s) "
              f"(HD-1118 Stage 4):")
        for f in findings[:40]:
            print(f"  {f}")
        if len(findings) > 40:
            print(f"  … {len(findings) - 40} more")
        print("The rules and their floors are in this file's docstring; the tree decision itself is "
              "in prompt-scripts.md and the folder-by-folder history is in the HD-1118 commits.")
        return 1
    print(f"OK: scripts/ layout holds — {n_scripts} tracked file(s), each with one registry row; "
          "no fixed-depth root derivation outside lib/; one pin() / one resolver / one plane registry; "
          "scripts/ top level is entry points only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
