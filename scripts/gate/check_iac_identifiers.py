#!/usr/bin/env python3
"""Lint: an IaC/ file may not carry a changelog identifier (CONVENTIONS.md s3).

Wave 1 removed the changelog prose from IaC/ comments; wave 2 removed the same tokens
from the strings that are deployed -- task names, systemd Description=, RouterOS
comment= values, msg:/fail_msg, dashboard descriptions, payload. What is left is the
forward half: nothing may put them back. CONVENTIONS.md s3 "Comment hygiene" is the
rule -- no ticket ids (`HD-<n>`, `KOPS-<n>`), no dates that are not real state -- and
this file is the machine half of it, so the rule survives the next refactor.

Position is deliberately NOT part of the verdict. An id hidden in a task name, in a
`comment=` value, in a dashboard `description`, or inside a block scalar says just as
much about what used to happen as one in a `#` line, and a rule that only reads
comments is the rule wave 1 had to re-learn twice (trailing comments, then payload).
So every tracked byte under IaC/ is scanned, and only two exemption classes are legal:

  A  state dates. The token is a date and the line's own key names it as state
     (valid_until, expires, not_after, since, ...). Mirrors the word set already
     proven in /tmp/iac-purge/tools/corpus_diff.py STATE_DATE, tightened to the key:
     `since:` is a state field, the English word "since" in a sentence is not.

  B  identifier-class sites, listed in scripts/gate/iac_identifier_allowlist.txt, one line
     per exemption: <path>TAB<exact trimmed line text>TAB<reason>. These are ids that
     are a HANDLE, not a mention -- a RouterOS `find where comment=` selector and the
     `comment=` value it matches, an Ansible `tags:` item, a `line:`/`regexp:` pair, a
     scalar whose whole value is a name another task looks up. Deleting one changes
     WHICH object is found, so it is code, not history. Keyed on the trimmed line text
     and NOT on line numbers, because numbers rot the moment a line is inserted above.
     A token is exempt only when BOTH path and trimmed line match, and a stale entry
     (file present, line text gone) is itself a violation: an exemption that no longer
     matches anything must not survive as a silent free pass for the next id.

Run:   python3 scripts/gate/check_iac_identifiers.py [--repo DIR] [--allowlist FILE]
       python3 scripts/gate/check_iac_identifiers.py --self-test
Prints one `VIOLATION path:line <token> -- why` per hit, then
       OK: <files> files, <M> exempt sites   (exit 0)   or
       FAIL: <k> violations                  (exit 1)
A site is one token occurrence on one line, so exempt sites + violations = total.
Wired into scripts/validate-all.sh.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import root as _hl_root  # noqa: E402
ROOT = _hl_root(__file__)
SCAN = "IaC"
ALLOW = "scripts/gate/iac_identifier_allowlist.txt"

# RULES: the token set is the wave counter's (scan.py), so the gate and the count that
# closed wave 1 can never disagree about what a token is.
TOKEN = re.compile(r"HD-\d+|KOPS-\d+|20\d\d-\d\d-\d\d")
DATE = re.compile(r"20\d\d-\d\d-\d\d")
# RULES: exemption A. The words are corpus_diff.py's STATE_DATE set plus `since`; a
# date under one of these keys is a fact about the present (an expiry, a start), so it
# is state and must survive -- and it must stay a fact, not become a citation.
STATE_KEYS = {"valid_until", "valid_from", "valid_to", "not_after", "not_before",
              "expires", "expiry", "renewal", "renew_by", "renew_date", "due_by",
              "deadline", "since"}
KEY = re.compile(r"(?:^|[\s,{/])([A-Za-z_][\w.]*)\s*[:=]")


def is_state_date(line: str, token: str) -> bool:
    """Exemption A: a date whose own line keys it as state."""
    return bool(DATE.fullmatch(token)) and any(k in STATE_KEYS for k in KEY.findall(line))


def tracked_files(root: Path) -> list[Path]:
    """Every tracked file under IaC/ -- the tree as it deploys, not as it sits dirty."""
    out = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--", SCAN],
                         capture_output=True)
    if out.returncode != 0:
        raise SystemExit(f"FAIL: git ls-files failed in {root}: {out.stderr.decode(errors='replace').strip()}")
    return [root / os.fsdecode(p) for p in out.stdout.split(b"\0") if p]


def read_lines(path: Path) -> list[str] | None:
    """Text lines, or None for a binary file (no prose to lint in a gz or a knxproj)."""
    try:
        raw = path.read_bytes()
    except OSError:
        return None
    if b"\0" in raw:
        return None
    return raw.decode("utf-8", "replace").split("\n")


def load_allowlist(path: Path) -> tuple[dict[str, list[dict]], list[str]]:
    """Exemption B. Returns {rel path: [entry]} plus malformed-entry violations."""
    entries: dict[str, list[dict]] = {}
    bad: list[str] = []
    if not path.is_file():
        return entries, [f"VIOLATION {ALLOW} (file) -- the exemption list is missing, so every "
                         "identifier-class site would read as a violation and the real ones would "
                         "be drowned in false positives"]
    text = read_lines(path) or []
    for n, line in enumerate(text, 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3 or not parts[2].strip():
            bad.append(f"VIOLATION {ALLOW}:{n} -- want <path>TAB<exact trimmed line>TAB<reason>; "
                       "an exemption without a reason is an unsigned claim")
            continue
        rel, want, reason = (p.strip() for p in parts)
        entries.setdefault(rel, []).append({"text": want, "reason": reason, "at": n, "used": False})
    return entries, bad


def scan(root: Path, allow: Path) -> tuple[list[str], dict[str, int]]:
    entries, violations = load_allowlist(allow)
    st = {"files": 0, "binary": 0, "tokens": 0, "state": 0, "allow": 0}
    visited: set[str] = set()
    for path in sorted(tracked_files(root)):
        rel = path.relative_to(root).as_posix()
        st["files"] += 1
        lines = read_lines(path)
        if lines is None:
            st["binary"] += 1
            continue
        visited.add(rel)
        by_text: dict[str, list[int]] = {}
        for i, line in enumerate(lines, 1):
            by_text.setdefault(line.strip(), []).append(i)
        exempt: set[int] = set()
        for e in entries.get(rel, []):
            if e["text"] in by_text:
                e["used"] = True
                exempt.update(by_text[e["text"]])
            else:
                violations.append(f"VIOLATION {ALLOW}:{e['at']} {rel} -- stale exemption: the file "
                                  "is still here but no line reads the exempted text any more, so "
                                  "this entry protects nothing and must go with the line it cited")
        for i, line in enumerate(lines, 1):
            for m in TOKEN.finditer(line):
                tok = m.group(0)
                st["tokens"] += 1
                if i in exempt:
                    st["allow"] += 1
                    continue
                if is_state_date(line, tok):
                    st["state"] += 1
                    continue
                why = ("a ticket id is changelog: git history is the only changelog"
                       if not DATE.fullmatch(tok) else
                       "a date that no key names as state is changelog: git history is the only "
                       "changelog")
                violations.append(f"VIOLATION {rel}:{i} {tok} -- {why} (CONVENTIONS.md s3)")
    for rel, group in entries.items():
        if rel in visited:
            continue
        for e in group:
            violations.append(f"VIOLATION {ALLOW}:{e['at']} {rel} -- stale exemption: the path is "
                              "no longer a tracked file under IaC/, so the exemption cites nothing")
    return violations, st


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    root = ROOT
    allow = ROOT / ALLOW
    if "--repo" in argv:
        root = Path(argv[argv.index("--repo") + 1]).resolve()
        allow = root / ALLOW
    if "--allowlist" in argv:
        allow = Path(argv[argv.index("--allowlist") + 1]).resolve()
    violations, st = scan(root, allow)
    for v in violations:
        print(v)
    print(f"scanned {st['files']} files ({st['binary']} binary, skipped), {st['tokens']} tokens = "
          f"{st['state']} exempt by state-date key + {st['allow']} exempt by allowlist + "
          f"{len(violations)} violations")
    if violations:
        print(f"FAIL: {len(violations)} violations")
        print("Either state the fact without the id (CONVENTIONS.md s3), or -- if the token IS a "
              f"handle a selector matches on -- add the exact line to {ALLOW} with a reason.")
        return 1
    print(f"OK: {st['files']} files, {st['state'] + st['allow']} exempt sites")
    return 0


def _fixture(files: dict[str, str], allow: str | None = None) -> Path:
    """A throwaway git repo: `git add` makes the files tracked, no commit needed."""
    d = Path(tempfile.mkdtemp(prefix="iac-ident-")).resolve()
    for rel, text in files.items():
        p = d / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
    if allow is not None:
        # The fixture writes the allowlist at its REAL path, so the directory the moved
        # checker reads has to exist here too — a fixture that cannot be written is a fixture
        # that never ran.
        (d / ALLOW).parent.mkdir(parents=True, exist_ok=True)
        (d / ALLOW).write_text(allow, encoding="utf-8")
    env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", HOME=str(d))
    for cmd in (["git", "init", "-q"], ["git", "add", "-A"]):
        subprocess.run(cmd, cwd=d, env=env, check=True, capture_output=True)
    return d


def self_test() -> int:
    """Five canaries. The fifth is the point of the whole design: a stale exemption fails."""
    cases = [
        ("i    an id + date planted in a comment",
         {"IaC/a.yml": "# fixed by HD-9 on 2026-01-02\n"}, "# no sites\n", 1, []),
        ("ii   an id inside a task name (a code string)",
         {"IaC/a.yml": "- name: Do thing (HD-9)\n  ansible.builtin.debug:\n    msg: ok\n"},
         "# no sites\n", 1, []),
        ("iii  a date on a valid_until line is state",
         {"IaC/a.yml": "sub:\n  valid_until: \"2027-01-02\"\n"}, "# no sites\n", 0, []),
        ("iv   an allowlisted identifier-class line",
         {"IaC/a.rsc": ':if ([/ip firewall filter find where comment="drop dns (HD-9)"] = "") do={\n'},
         "IaC/a.rsc\t:if ([/ip firewall filter find where comment=\"drop dns (HD-9)\"] = \"\") do={\t"
         "RouterOS find-where selector\n", 0, []),
        ("v    a stale exemption (path lives, line changed) fails",
         {"IaC/a.rsc": ':if ([/ip firewall filter find where comment="drop dns (HD-10)"] = "") do={\n'},
         "IaC/a.rsc\t:if ([/ip firewall filter find where comment=\"drop dns (HD-9)\"] = \"\") do={\t"
         "RouterOS find-where selector\n", 1, ["stale exemption"]),
    ]
    bad: list[str] = []
    for name, files, allow, want_rc, want_in in cases:
        d = _fixture(files, allow)
        try:
            violations, _ = scan(d, d / ALLOW)
        finally:
            subprocess.run(["rm", "-rf", str(d)], check=False)
        rc = 1 if violations else 0
        joined = "\n".join(violations)
        if rc != want_rc:
            bad.append(f"case {name}: exit {rc}, wanted {want_rc} -- {joined[:160]}")
            continue
        if any(s not in joined for s in want_in):
            bad.append(f"case {name}: said the wrong thing -- {joined[:160]}")
            continue
        print(f"PASS  {name}: {'red' if want_rc else 'green'} as required")
    if bad:
        print("FAIL: check_iac_identifiers.py self-test:")
        for b in bad:
            print(f"  - {b}")
        return 1
    print("OK: self-test -- comments, code strings and payload all count; a state-date key and a "
          "matching allowlist entry pass; an exemption that stopped matching turns the gate red")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
