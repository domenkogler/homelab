#!/usr/bin/env python3
"""Lint: no merge-conflict marker may reach a commit (HD-453).

Why this gate exists (measured, not theorised): a `>>>>>>>` line survived a bad
rebase resolution into a rebased commit of a root view file and `validate-all.sh`
printed OK. The text validators look for TODO-shapes, IP literals, placeholders
and secret shapes — none of them looks for a merge artefact — so `main` can carry
a conflict marker in `prompt.md` and every gate stays green. A marker in a doc is
also silently load-bearing: the `=======` line is a Markdown table/heading
separator and the `<<<<<<<` / `>>>>>>>` lines become plain paragraph text, so the
file renders as garbage instead of failing.

What is flagged (exit 1):
  * `^<{7,}`   — the "ours" marker
  * `^>{7,}`   — the "theirs" marker
  * `^\\|{7,}` — the `diff3`/`zdiff3` base marker
  * `^={7}$`   — the divider, at git's exact width (see the DIVIDER comment: the
                 width-`+` version is a false-positive machine on this repo's raw
                 evidence, and the repo's `=`-ruled banners are 50–60 chars).
                 In a `.md` file this one is CONTEXT-SENSITIVE, and the reason is
                 Markdown itself: a line of `=` under a text line is a setext H1
                 underline, which is legal Markdown, not an artefact. A divider is
                 therefore flagged only when the preceding line is blank/absent (a
                 setext underline MUST sit under its heading text).

Scope: files tracked by git in the WORKING TREE (so it also fires before the
commit that would ship the marker). Binary/undecodable files are skipped.
`git` is required; without it the gate SKIPs (exit 0, loud) rather than silently
passing — same convention as the Ansible-gated gates in `validate-all.sh`.

Self-test (the pattern `check_self_converge_guard.py` uses — a gate that cannot
fail is not a gate):
    python3 scripts/check_merge_markers.py --self-test
Builds a throwaway repo in a temp dir, asserts every marker shape turns the
scanner red, and asserts the two things that must stay GREEN: clean content, and
a Markdown setext H1 (the near-miss that would otherwise mute this gate in its
first week, because this repo's `docs/` predates ATX headings in places).

Run:   python3 scripts/check_merge_markers.py
Exit:  0 = clean (or skipped with a printed reason), 1 = violations found.
Wired into `scripts/validate-all.sh` (scan + self-test).
"""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

PRIMARY = re.compile(r"^(?:<{7,}|>{7,}|\|{7,})")
# The divider is matched at git's own width (exactly 7) and nothing else. That is
# not pedantry: this repo's tracked RAW evidence (disk-facts dumps, spark bench
# logs) is ruled with 50–60-character `=` banners, and a first draft that matched
# `^={7,}` reported 78 false positives on the first run — a gate that shouts at
# evidence files gets muted inside a week, which is the failure mode HD-417 names.
# A line of EXACTLY seven `=` with nothing else on it is a git artefact.
DIVIDER = re.compile(r"^={7}$")

MAX_REPORT = 40  # a marker storm is one finding class, not a wall of text


def _iter_tracked_files(root: Path) -> list[Path]:
    out = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        capture_output=True, check=True,
    ).stdout
    return [root / p.decode("utf-8", "replace") for p in out.split(b"\0") if p]


def scan(root: Path) -> list[str]:
    """Return findings as '<relpath>:<line>: <shape>: <preview>'."""
    findings: list[str] = []
    for path in _iter_tracked_files(root):
        try:
            raw = path.read_bytes()
        except OSError:
            continue
        if b"\0" in raw[:8192]:
            continue  # binary
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            continue  # undecodable (e.g. the .knxproj/.zip artifacts) — nothing to grep
        rel = path.relative_to(root).as_posix()
        lines = text.split("\n")
        markdown = rel.lower().endswith((".md", ".markdown"))
        for n, line in enumerate(lines, start=1):
            if PRIMARY.match(line):
                findings.append(f"{rel}:{n}: marker: {line[:72]}")
            elif DIVIDER.match(line) and (not markdown or not (lines[n - 2].strip() if n > 1 else "")):
                findings.append(f"{rel}:{n}: divider: {line[:72]}")
    return findings


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return self_test()
    try:
        subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--git-dir"],
                       capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("SKIP: git unavailable — merge-marker gate needs the tracked file list")
        return 0
    findings = scan(ROOT)
    if findings:
        print(f"FAIL: {len(findings)} merge-conflict marker line(s) in tracked files "
              "(a resolved conflict must not keep the markers):")
        for f in findings[:MAX_REPORT]:
            print(f"  {f}")
        if len(findings) > MAX_REPORT:
            print(f"  ... {len(findings) - MAX_REPORT} more (same class)")
        print("Fix: resolve the conflict properly (git checkout --theirs/--ours then edit), "
              "or `git checkout -- <file>` and redo the merge.")
        return 1
    print("OK: no merge-conflict markers in tracked files (HD-453)")
    return 0


# --------------------------------------------------------------------------- self-test
CASES = {
    "conflict_ours.txt": "<<<<<<< HEAD\nkept\n",
    "conflict_theirs.txt": "kept\n>>>>>>> feature\n",
    "conflict_base.txt": "<<<<<<< HEAD\nkept\n||||||| merged common ancestors\nbase\n=======\ntheirs\n",
    "conflict_divider_only.txt": "kept\n\n=======\n\nother\n",
    "conflict_in_md.md": "# Title\n\n<<<<<<< HEAD\nours\n=======\ntheirs\n\nbody\n",
}
CLEAN = {
    # The near-miss: a Markdown setext H1 is legal, and this repo has real ones.
    "heading.md": "Homelab Setext Heading\n====================\n\nbody\n",
    # Near-miss: six angle brackets / six equals are prose, not markers.
    "short.md": "```\n<<<<<<\n=====\n>>>>>>\n```\n",
    "arrow.txt": "a <= b and a >= c, and --- six dashes ------ and |||||| (six)\n",
    "equals_in_text.txt": "the sum ===== is in a sentence mid-line, not at line start\n",
    # Near-miss that actually exists in this repo: raw evidence ruled with `=` banners.
    "banner.txt": "Disk facts\n" + "=" * 60 + "\nmodel: WDC\n" + "=" * 60 + "\n",
    "banner_padded.txt": "============ Serving Benchmark Result ============\nreq/s: 43\n",
    "underlines.md": "Sub\n-------\n\nSetext Seven\n=======\n\nbody\n",
}


def self_test() -> int:
    import os
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="hd453-canary-") as td:
        repo = Path(td)
        for name, body in {**CLEAN, **CASES}.items():
            (repo / name).write_text(body, encoding="utf-8")
        env = {**os.environ, "GIT_AUTHOR_NAME": "canary", "GIT_AUTHOR_EMAIL": "c@x",
               "GIT_COMMITTER_NAME": "canary", "GIT_COMMITTER_EMAIL": "c@x"}
        for cmd in (["git", "init", "-q"], ["git", "add", "-A"], ["git", "commit", "-qm", "fixture"]):
            subprocess.run(cmd, cwd=repo, check=True, capture_output=True, env=env)

        # 1. the fixture as committed must flag every conflicted file, and only those.
        found = scan(repo)
        flagged = {f.split(":")[0] for f in found}
        for name in CASES:
            if name not in flagged:
                failures.append(f"canary {name}: marker NOT detected (gate would stay green)")
        for name in CLEAN:
            if name in flagged:
                hits = [f for f in found if f.startswith(name + ":")]
                failures.append(f"canary {name}: FALSE POSITIVE -> {hits}")

        # 2. proof the gate reacts to an UNCOMMITTED edit too (it scans the working tree).
        (repo / "clean_edit.md").write_text("# ok\n", encoding="utf-8")
        subprocess.run(["git", "add", "-A"], cwd=repo, check=True, capture_output=True, env=env)
        subprocess.run(["git", "commit", "-qm", "clean"], cwd=repo, check=True,
                       capture_output=True, env=env)
        before = len(scan(repo))
        (repo / "clean_edit.md").write_text("# ok\n\n<<<<<<< HEAD\nmine\n=======\ntheirs\n", encoding="utf-8")
        after = len(scan(repo))
        if after <= before:
            failures.append("working-tree edit with a marker was not detected (pre-commit blind spot)")

        # 3. and it goes quiet again once the conflict is resolved the right way.
        (repo / "clean_edit.md").write_text("# ok\n\ntheirs\n", encoding="utf-8")
        still = [f for f in scan(repo) if f.startswith("clean_edit.md:")]
        if still:
            failures.append(f"resolved file still flagged: {still}")

    if failures:
        print(f"FAIL: check_merge_markers.py self-test — {len(failures)} problem(s):")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"OK: self-test — {len(CASES)} marker shapes caught, {len(CLEAN)} legal near-misses "
          "left alone (incl. the Markdown setext heading), working-tree edits caught, "
          "resolution clears (HD-453)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
