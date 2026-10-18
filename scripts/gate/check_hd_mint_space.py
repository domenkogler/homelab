#!/usr/bin/env python3
"""check_hd_mint_space.py — the backlog id space, held open by a rule instead of by luck.

WHY THIS EXISTS. `scripts/next-hd.sh` mints the next id as max(HD)+1 across the whole tracked tree,
because a wide scan is the only scan that does not hand out an id a live row already holds. A wide
scan also reads a tool's own canary as evidence. The first answer was a LIST of excluded ids, and it
did not hold: `corpus_diff.py`'s classifier fixtures mint synthetic tokens of their own — they must
look like real tokens or the classifier is not being tested — so the list went stale the day a new
fixture appeared and the minter handed out an id four orders of magnitude above the registry. A list
is the wrong shape for "these numbers are not ids". So one block is reserved for synthetic tokens,
and this file is what keeps the reservation true in both directions:

  1. TOOL DECLARES A BLOCK — `RESERVED_RANGES` must exist in `scripts/next-hd.sh` and parse to at
     least one range. A silently-dropped default re-opens the whole defect, so this is exit 2, not a
     finding: the checker cannot judge a minter that stopped declaring its namespace.
  2. POISON — every id token in the tree is either a real id (at or below the real max) or inside the
     reserved block. A synthetic token OUTSIDE the block is exactly what poisoned the minter, so it
     reddens with file:line. Tokens above the block are a namespace nobody declared.
  3. EXCLUSIVITY — no `todo.md` ROW may be minted inside the block. Without this the filter makes an
     accidental collision invisible: the row would exist, the minter would never report it, and two
     unrelated items would share an id — the silent cross-link, which is the one backlog bug that
     never shows up as an error.
  4. PROSE AGREES — the block named in CONVENTIONS §1 and in todo.md §0 must be the block the TOOL
     uses, derived from the tool rather than compared against a constant. A widened range that forgot
     its prose is how a rule becomes two rules that disagree.

Both directions matter: rule 2 protects the minter from the fixtures, rule 3 protects the fixtures
from the minter.

Run:    python3 scripts/gate/check_hd_mint_space.py [--show] [--self-test]
        `--show` prints the derived block and the derived real max — print them, never type them.
Exit:   0 clean · 1 finding(s) · 2 could not run (no minter, no range declared, corpus floor).
Stdlib + git only. Wired into `validate-all.sh`.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root  # noqa: E402

ROOT = _hl_root(__file__)
MINTER = "scripts/next-hd.sh"
# The same token shape next-hd.sh scans. Deliberately a CLASS, not a literal: an authored `HD-<n>`
# inside this file would be picked up by the scan of the tree and make the checker cite itself.
TOKEN = re.compile(r"[Hh][Dd][-_+–]([0-9]+)")
# `| HD-495 |` — a registry row's first cell. Row ids are what collide; a citation is not a row.
# re.M is load-bearing: without it `^` matches only the file's first line and every row is invisible.
ROW = re.compile(r"^\|\s*HD-([0-9]+)\s*\|", re.M)
# A range written in prose, built from the parsed numbers so this check cannot itself go stale.
RANGE_SP = r"{lo}\s*[–-]\s*{hi}"
# Where the block must be written down: the rule index, and the file that owns the id lifecycle.
PROSE = ("CONVENTIONS.md", "todo.md")
# Floor, not a count to keep current: it counts the FILES THE WALK SAW A TOKEN IN (measured low
# hundreds repo-wide), and it exists only as the witness that the walk saw a tree at all — a broken
# root yields an empty scan and every rule below would print OK. Far below the real figure, so no
# ordinary commit can trip it.
CORPUS_FLOOR = 50


def tok(n: int) -> str:
    """Build an id token AT RUNTIME so this file's own text is not an id.

    This checker caught itself: a literal above the registry ceiling sitting in its own self-test is
    the exact defect it hunts, and the tree scan cannot tell the two apart — the same reason
    `check_script_layout.py` composes its fixture paths instead of writing them. Composing is not
    cosmetics: it is what keeps the probe from becoming its own finding.
    """
    return f"HD-{n}"


def git(root: Path, *args: str) -> str:
    proc = subprocess.run(["git", "-C", str(root), *args],
                          capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proc.returncode not in (0, 1):  # git grep exits 1 for "no match", which is not an error
        raise RuntimeError(f"git {' '.join(args)}: {proc.stderr.strip()[:200]}")
    return proc.stdout


def declared_block(root: Path) -> tuple[list[tuple[int, int]], set[int]]:
    """The reservation AS THE TOOL DECLARES IT — read out of next-hd.sh, never copied here.

    Reads the shell default of RESERVED_RANGES / RESERVED_IDS. The `${VAR-default}` form is matched
    on purpose: the default value is the policy, and an env override is a test, not the rule.
    """
    text = (root / MINTER).read_text(encoding="utf-8", errors="replace")
    ranges: list[tuple[int, int]] = []
    ids: set[int] = set()
    m = re.search(r'^RESERVED_RANGES="\$\{RESERVED_RANGES-([^"}]*)\}"', text, re.M)
    if m:
        for part in m.group(1).split(","):
            part = part.strip()
            if not part:
                continue
            lo, _, hi = part.partition("-")
            if not lo.strip().isdigit():
                raise RuntimeError(f"{MINTER}: unparsable RESERVED_RANGES part {part!r}")
            ranges.append((int(lo), int(hi) if hi.strip().isdigit() else int(lo)))
    m = re.search(r'^RESERVED_IDS="\$\{RESERVED_IDS-([^"}]*)\}"', text, re.M)
    if m:
        ids = {int(t) for t in m.group(1).split() if t.isdigit()}
    return ranges, ids


def tokens(root: Path, floor: int = CORPUS_FLOOR) -> list[tuple[str, int, int]]:
    """Every (path, line, id) HD token in the tracked tree, reports/ excluded — next-hd's scan set."""
    out: list[tuple[str, int, int]] = []
    hits = git(root, "grep", "-nIE", TOKEN.pattern, "--", ".", ":(exclude)reports")
    seen_files: set[str] = set()
    for line in hits.splitlines():
        path, _, rest = line.partition(":")
        num, _, body = rest.partition(":")
        seen_files.add(path)
        for m in TOKEN.finditer(body):
            out.append((path, int(num), int(m.group(1))))
    # The floor is the witness that the walk saw a tree; a fixture repo legitimately walks 4 files,
    # so the caller supplies it and the real run keeps the repo-wide floor.
    require_corpus(len(seen_files), floor, "check_hd_mint_space tree walk")
    return out


def check(root: Path, floor: int = CORPUS_FLOOR) -> tuple[list[str], dict[str, object]]:
    """The four rules. Returns (findings, derived values)."""
    bad: list[str] = []
    info: dict[str, object] = {}
    try:
        ranges, reserved_ids = declared_block(root)
    except (OSError, RuntimeError) as exc:
        raise SystemExit(f"CANNOT RUN: {exc}") from exc
    if not ranges:  # rule 1 — exit 2: a minter with no declared namespace cannot be judged
        raise SystemExit(f"CANNOT RUN: {MINTER} declares no RESERVED_RANGES — the mint space is "
                         "unreserved and every future id is a coin flip")

    def in_block(n: int) -> bool:
        return any(lo <= n <= hi for lo, hi in ranges)

    toks = tokens(root, floor)
    block_end = max(hi for _, hi in ranges)
    # The ceiling a REAL id cannot exceed is the REGISTRY, not the max of the tokens. That distinction
    # is the whole check: a synthetic token raises the token max, so "above the max" is a test the
    # poison passes by existing — which is exactly how the minter got fooled. Rows are the one source
    # poison cannot inflate.
    try:
        todo_text = (root / "todo.md").read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise SystemExit(f"CANNOT RUN: cannot read todo.md rows: {exc}") from exc
    rows = [int(m.group(1)) for m in ROW.finditer(todo_text)]
    if not rows:
        raise SystemExit("CANNOT RUN: todo.md yielded no registry rows — a broken read, not a clean tree")
    registry_max = max(rows)
    # Also shown for parity with `next-hd.sh --max`, whose scan is wider than the rows: a citation to
    # a row closed since can legitimately sit above the registry ceiling, and RESERVED_IDS is where
    # such an id is recorded. Deriving it keeps the two tools comparable without a constant here.
    minter_max = max((n for _, _, n in toks if not in_block(n) and n not in reserved_ids),
                     default=registry_max)
    info = {"ranges": ranges, "registry_max": registry_max, "minter_max": minter_max,
            "tokens": len(toks), "block_span": sum(hi - lo + 1 for lo, hi in ranges)}

    # rule 2: poison — synthetic id text outside the reserved block
    for path, line, n in sorted(set((p, l, n) for p, l, n in toks)):
        if in_block(n) or n <= registry_max or n in reserved_ids:
            continue
        if n > block_end:
            bad.append(f"{path}:{line}: HD-{n} is above the reserved block (ends {block_end}) — "
                       "an id in a namespace nobody declared")
        else:
            bad.append(f"{path}:{line}: HD-{n} sits above the registry ceiling ({registry_max}) and "
                       "outside the reserved block — synthetic id text that will poison the next "
                       f"mint. Move it into the block ({ranges[0][0]}-{block_end}), or if it IS a real "
                       f"closed id, record it in RESERVED_IDS in {MINTER}")

    # rule 3: exclusivity — no registry row inside the block
    for n in sorted(set(rows)):
        if in_block(n):
            bad.append(f"todo.md: a registry row carries HD-{n}, inside the reserved fixture block — "
                       "the minter FILTERS this id, so the collision would be invisible forever")

    # rule 4: prose agrees with the tool
    for rel in PROSE:
        try:
            text = (root / rel).read_text(encoding="utf-8", errors="replace")
        except OSError:
            bad.append(f"{rel}: unreadable, cannot confirm it states the reserved block")
            continue
        if not any(re.search(RANGE_SP.format(lo=lo, hi=hi), text) for lo, hi in ranges):
            bad.append(f"{rel}: does not state the reserved block "
                       f"({'/'.join(f'{lo}-{hi}' for lo, hi in ranges)}) that {MINTER} actually uses")
    return bad, info


# --- self-test: every rule bred, and seen to be caught -----------------------------------------
def self_test() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="hd-mint-space-"))
    repo = tmp / "repo"
    (repo / "scripts" / "gate").mkdir(parents=True)
    (repo / MINTER).write_text(
        '#!/usr/bin/env bash\nRESERVED_IDS="${RESERVED_IDS-900 901}"\n'
        'RESERVED_RANGES="${RESERVED_RANGES-9000-9999}"\n', encoding="utf-8")
    # A legal tree: two rows, a citation to a closed id, and fixture text INSIDE the block.
    (repo / "todo.md").write_text("# backlog\n\n| ID |\n|----|\n| HD-400 | one |\n| HD-401 | two |\n"
                                  "\n9000-9999 is the fixture block.\n", encoding="utf-8")
    (repo / "CONVENTIONS.md").write_text("| Backlog IDs | 9000-9999 is the fixture block |\n",
                                         encoding="utf-8")
    fixture = repo / "scripts" / "gate" / "fixture_tool.py"
    fixture.write_text(f"# classifier fixture\nX = '{tok(9001)}'\nY = '{tok(401)} is cited here'\n",
                       encoding="utf-8")
    subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)
    subprocess.run(["git", "-C", str(repo), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(repo), "-c", "user.email=t@t", "-c", "user.name=t",
                    "commit", "-qm", "fixture"], check=True)

    def run() -> list[str]:
        return check(repo, floor=0)[0]

    fails = 0

    def expect(label: str, want_red: bool, findings: list[str]) -> None:
        nonlocal fails
        if bool(findings) != want_red:
            print(f"SELFTEST FAIL [{label}]: wanted "
                  f"{'RED' if want_red else 'GREEN'}, got {findings[:2]}")
            fails += 1
        else:
            print(f"  ok  {label}: {'redens' if want_red else 'stays green'}")

    def patch(path: Path, old: str, new: str) -> None:
        path.write_text(path.read_text(encoding="utf-8").replace(old, new, 1), encoding="utf-8")

    try:
        # CONTROL — a legal tree, fixture tokens inside the block included, must be clean.
        expect("control: legal tree", False, run())

        # rule 2a: a synthetic id above the registry ceiling, outside the block — THE defect.
        patch(fixture, f"X = '{tok(9001)}'", f"X = '{tok(8123)}'")
        expect("rule 2: synthetic id outside the block", True, run())
        patch(fixture, f"X = '{tok(8123)}'", f"X = '{tok(9001)}'")

        # rule 2b: a token above the block — an undeclared namespace.
        patch(fixture, f"X = '{tok(9001)}'", f"X = '{tok(42000)}'")
        expect("rule 2: id above the block", True, run())
        patch(fixture, f"X = '{tok(42000)}'", f"X = '{tok(9001)}'")

        # rule 3: a real row minted into the fixture block.
        patch(repo / "todo.md", f"| {tok(401)} | two |", f"| {tok(9001)} | two |")
        expect("rule 3: registry row inside the block", True, run())
        patch(repo / "todo.md", f"| {tok(9001)} | two |", f"| {tok(401)} | two |")

        # rule 4: the prose stops matching the tool's block.
        patch(repo / "CONVENTIONS.md", "9000-9999", "8000-8999")
        expect("rule 4: prose disagrees with the tool", True, run())
        patch(repo / "CONVENTIONS.md", "8000-8999", "9000-9999")

        # rule 1: the minter loses its default — not a finding, a refusal to judge (exit 2).
        patch(repo / MINTER, '${RESERVED_RANGES-9000-9999}', '"${RESERVED_RANGES-}"')
        try:
            run()
            print("SELFTEST FAIL [rule 1: no block declared]: expected a refusal to run")
            fails += 1
        except SystemExit:
            print("  ok  rule 1: no block declared -> refuses to run")

        # rule 1 teeth: a tool that declares a DIFFERENT block must be judged by ITS block, not by
        # a constant in this file — otherwise the checker proves the fixture, not the rule.
        (repo / MINTER).write_text('RESERVED_RANGES="${RESERVED_RANGES-7000-7999}"\n',
                                   encoding="utf-8")
        patch(repo / "CONVENTIONS.md", "9000-9999", "7000-7999")
        patch(repo / "todo.md", "9000-9999", "7000-7999")
        patch(fixture, f"X = '{tok(9001)}'", f"X = '{tok(7500)}'")  # inside the NEW block
        expect("control: tool and prose moved to a different block together", False, run())
        patch(fixture, f"X = '{tok(7500)}'", f"X = '{tok(9001)}'")  # legal under the OLD block only
        expect("rule 2: an id legal under the OLD block is poison under the new one", True, run())
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)
    print("SELFTEST OK: the mint-space rules are seen to bite, and the legal shapes stay green"
          if not fails else f"SELFTEST FAILED: {fails} case(s)")
    return 1 if fails else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--show", action="store_true", help="print the derived block and real max")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    try:
        bad, info = check(ROOT)
    except RuntimeError as exc:
        print(f"CANNOT RUN: {exc}", file=sys.stderr)
        return 2
    block = "+".join(f"{lo}-{hi}" for lo, hi in info["ranges"])  # type: ignore[index]
    real_max = info["registry_max"]  # type: ignore[assignment]
    if args.show:
        print(f"mint space: block={block} registry_max={real_max} minter_max={info['minter_max']} "
              f"tokens={info['tokens']} ids set aside={info['block_span']}")
    for f in bad:
        print(f"FINDING: {f}", file=sys.stderr)
    if bad:
        print(f"check_hd_mint_space: {len(bad)} finding(s) — the id space is not held open",
              file=sys.stderr)
        return 1
    print(f"OK: mint space reserved — block {block}, registry ceiling {real_max}, "
          "no synthetic id outside the block, no registry row inside it "
          f"(next free: {int(real_max) + 1})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
