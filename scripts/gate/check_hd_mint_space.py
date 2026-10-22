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
  5. REUSE — the id the minter actually PROPOSES (it is RUN, never re-derived here) must be an id no
     commit ever wrote. The tree half of the minter cannot see a row that was deleted, so "above every
     id still standing in a file" is not the same statement as "never used". The commits that wrote
     the id are named in the finding, read off the DIFF LINES of one history pass: `git log -S` asks
     whether the occurrence COUNT changed on a path, so the commit that swaps an id's row for an
     id's citation inside one file changes nothing and disappears from that sweep — the id stays,
     the sweep forgets it, and a number that already has a history gets minted again.

Both directions matter: rule 2 protects the minter from the fixtures, rule 3 protects the fixtures
from the minter, rule 5 protects the minter from its own tree scan.

Run:    python3 scripts/gate/check_hd_mint_space.py [--show] [--self-test]
        `--show` prints the derived block, the derived real max and the id the minter proposes —
        print them, never type them.
Exit:   0 clean · 1 finding(s) · 2 could not run (no minter, no range declared, corpus floor, a
        history pass that saw no commit). A minter that refuses to mint (its bounded candidate window
        ran out) is not a finding here: it proposed nothing, so there is nothing to judge.
Stdlib + git + bash only. Wired into `validate-all.sh`.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root, script_path  # noqa: E402

ROOT = _hl_root(__file__)
MINTER = "scripts/next-hd.sh"
# The minter is RUN to learn what it proposes — found by name, so it stays the real tool wherever the
# tree moves it. A number re-derived in here would be a second implementation proving nothing.
MINTER_PATH = script_path("next-hd.sh", __file__)
# One commit per line, before its diff: the boundary the history pass needs to say WHO wrote an id.
COMMIT_MARK = "\x01"
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


def history_writers(root: Path) -> dict[int, list[str]]:
    """id -> the commits whose diff WROTE it, from one pass over every reachable commit.

    Line-level on purpose. `git log -S` compares the occurrence COUNT on a path, so a commit that
    adds one copy of an id and deletes another — a row swapped for its citation inside one file —
    answers "nothing changed" and vanishes from that sweep; streaming the +/- diff lines still sees it.
    `--diff-merges=first-parent` keeps merge commits in the walk (plain `git log -p` prints no diff
    for a merge, and the `-S` sweep cannot see one either). Same scan set as the minter's tree half:
    reports/ is archive-only, so an id that survives only there is an id no row ever held.
    """
    proc = subprocess.Popen(["git", "-C", str(root), "log", "--all", "--no-color",
                             f"--format={COMMIT_MARK}%h", "-p", "-U0",
                             "--diff-merges=first-parent", "--", ".", ":(exclude)reports"],
                            stdout=subprocess.PIPE, text=True, encoding="utf-8", errors="replace")
    writers: dict[int, list[str]] = {}
    sha, commits = "", 0
    for line in proc.stdout or "":
        if line.startswith(COMMIT_MARK):
            sha, commits = line[len(COMMIT_MARK):].strip(), commits + 1
            continue
        for m in TOKEN.finditer(line):
            hit = writers.setdefault(int(m.group(1)), [])
            if sha and sha not in hit:
                hit.append(sha)
    proc.wait()
    if proc.returncode != 0:
        raise RuntimeError(f"git log --all -p in {root}: the history pass failed")
    # A pass that saw no commit sees nothing, and "nothing written" would make every id look free.
    require_corpus(commits, 0, "check_hd_mint_space history pass")
    return writers


def run_minter(root: Path, mode: str = "--raw", *, history: bool = True,
               window: int | None = None) -> tuple[int, int | None, str]:
    """RUN the minter on `root` and read the number it prints: (rc, id, stderr).

    The reserved block/ids are passed back exactly as `root`'s own minter declares them, so a fixture
    that moved its block is judged by its block and the real repo is unchanged by the passing. The
    tool under test is the real script, not a copy of its logic written here.
    """
    ranges, ids = declared_block(root)
    env = {**os.environ, "REPO": str(root),
           "RESERVED_RANGES": ",".join(f"{lo}-{hi}" for lo, hi in ranges),
           "RESERVED_IDS": " ".join(str(i) for i in sorted(ids))}
    if not history:
        env["GIT_SCAN"] = "0"       # the tree half alone: what this script proposed before the fix
    if window is not None:
        env["CANDIDATE_WINDOW"] = str(window)
    try:
        proc = subprocess.run(["bash", str(MINTER_PATH), mode], cwd=str(root), env=env,
                              capture_output=True, text=True, encoding="utf-8", errors="replace")
    except OSError as exc:                      # no bash on this host — a refusal, never a silent pass
        raise SystemExit(f"CANNOT RUN: cannot exec bash {MINTER_PATH}: {exc}") from exc
    out = proc.stdout.strip()
    num = int(out) if out.isdigit() else None
    return proc.returncode, num, proc.stderr.strip()


def check_reuse(root: Path, proposal: int) -> list[str]:
    """Rule 5: the id about to be minted must be an id no commit ever wrote — named, not asserted."""
    written = sorted(history_writers(root).get(proposal, ()))
    if not written:
        return []
    return [f"{tok(proposal)} is not free: {len(written)} commit(s) already wrote it "
            f"({', '.join(written)}) — minting it again cross-links two rows and makes "
            f"`git log -S {tok(proposal)}`, the prior-art sweep §0 leans on, match the older row"]


def check(root: Path, floor: int = CORPUS_FLOOR) -> tuple[list[str], dict[str, object]]:
    """The five rules. Returns (findings, derived values)."""
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
            "tokens": len(toks), "block_span": sum(hi - lo + 1 for lo, hi in ranges),
            "proposal": None}

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

    # rule 5: reuse — ask the minter what it proposes, then ask history whether it is free.
    rc, proposal, err = run_minter(root, "--raw")
    if rc == 2:
        # The minter refused to mint (its bounded window ran out). It proposed nothing, so there is
        # nothing to judge here; the script itself failed loudly and that is its own contract.
        info["refused"] = err.splitlines()[-1] if err else "no id proposed"
    elif rc != 0 or proposal is None:
        raise SystemExit(f"CANNOT RUN: {MINTER} {err[:160] or f'exited {rc} with no id'}")
    else:
        info["proposal"] = proposal
        bad += check_reuse(root, proposal)
    return bad, info


# --- self-test: every rule bred, and seen to be caught -----------------------------------------
SEED_TOP = 401          # the highest row in the seeded fixture registry


def self_test() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="hd-mint-space-"))

    def seed(name: str) -> Path:
        """A legal mini-repo: two rows, a citation to a closed id, fixture text INSIDE the block."""
        repo = tmp / name
        (repo / "scripts" / "gate").mkdir(parents=True)
        (repo / MINTER).write_text(
            '#!/usr/bin/env bash\nRESERVED_IDS="${RESERVED_IDS-900 901}"\n'
            'RESERVED_RANGES="${RESERVED_RANGES-9000-9999}"\n', encoding="utf-8")
        (repo / "todo.md").write_text(
            "# backlog\n\n| ID |\n|----|\n"
            f"| {tok(SEED_TOP - 1)} | one |\n| {tok(SEED_TOP)} | two |\n"
            "\n9000-9999 is the fixture block.\n", encoding="utf-8")
        (repo / "CONVENTIONS.md").write_text("| Backlog IDs | 9000-9999 is the fixture block |\n",
                                             encoding="utf-8")
        (repo / "scripts" / "gate" / "fixture_tool.py").write_text(
            f"# classifier fixture\nX = '{tok(9001)}'\nY = '{tok(SEED_TOP)} is cited here'\n",
            encoding="utf-8")
        subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)
        subprocess.run(["git", "-C", str(repo), "add", "-A"], check=True)
        subprocess.run(["git", "-C", str(repo), "-c", "user.email=t@t", "-c", "user.name=t",
                        "commit", "-qm", "fixture"], check=True)
        return repo

    def commit(repo: Path, msg: str) -> None:
        subprocess.run(["git", "-C", str(repo), "add", "-A"], check=True)
        subprocess.run(["git", "-C", str(repo), "-c", "user.email=t@t", "-c", "user.name=t",
                        "commit", "-qm", msg], check=True)

    def mint_then_sweep(repo: Path, n: int) -> None:
        """Breed the shape the tree scan cannot see, in three commits. The id is minted as a row, then
        SWAPPED within the same file — the row goes, a citation line arrives, one path, one copy added
        and one deleted — so its occurrence COUNT does not change and `git log -S` does not name that
        commit at all. The third commit sweeps the citation. Afterwards no file carries the id and
        every commit that touched it still does.
        """
        todo = repo / "todo.md"
        row, cite = f"| {tok(n)} | minted |\n", f"\n> cited: {tok(n)}\n"
        text = todo.read_text(encoding="utf-8")
        todo.write_text(text + row, encoding="utf-8")
        commit(repo, f"mint {tok(n)}")
        todo.write_text(todo.read_text(encoding="utf-8").replace(row, cite, 1), encoding="utf-8")
        commit(repo, f"swap the {tok(n)} row for a citation in the same file")   # zero-delta for -S
        todo.write_text(todo.read_text(encoding="utf-8").replace(cite, "", 1), encoding="utf-8")
        commit(repo, "sweep the closed row")

    repo = seed("repo")
    fixture = repo / "scripts" / "gate" / "fixture_tool.py"

    def run() -> list[str]:
        return check(repo, floor=0)[0]

    fails = 0

    def expect_true(label: str, ok: bool, detail: str = "") -> None:
        nonlocal fails
        if ok:
            print(f"  ok  {label}")
        else:
            print(f"SELFTEST FAIL [{label}]{': ' + detail if detail else ''}")
            fails += 1

    def expect(label: str, want_red: bool, findings: list[str]) -> None:
        expect_true(f"{label}: {'redens' if want_red else 'stays green'}", bool(findings) == want_red,
                    f"wanted {'RED' if want_red else 'GREEN'}, got {findings[:2]}")

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
        patch(repo / "todo.md", f"| {tok(SEED_TOP)} | two |", f"| {tok(9001)} | two |")
        expect("rule 3: registry row inside the block", True, run())
        patch(repo / "todo.md", f"| {tok(9001)} | two |", f"| {tok(SEED_TOP)} | two |")

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

        # --- rule 5: REUSE. Two corpora, the same shape, one id apart: `used` minted the canary and
        # swept it out of the tree, so the tree max points at it again; `free` ran the identical
        # sequence one number higher, which leaves the canary genuinely unwritten.
        canary = SEED_TOP + 1
        used, free = seed("reuse-used"), seed("reuse-free")
        mint_then_sweep(used, canary)
        mint_then_sweep(free, canary + 1)

        # The tree half alone still proposes the canary — the minter's own answer, not a number this
        # file wrote down, and the exact shape the defect handed out as "free".
        rc, tree_only, err = run_minter(used, "--raw", history=False)
        expect_true(f"the tree half alone proposes the swept id {tok(canary)}",
                    rc == 0 and tree_only == canary, f"got rc={rc} {tree_only} :: {err[-160:]}")
        expect("rule 5: an id the tree forgot that history already wrote", True,
               check_reuse(used, canary))

        # The trap, witnessed: the count-based sweep names FEWER commits than the diff-line pass does,
        # because the commit that SWAPPED the row for a citation changed no count on that path. The
        # finding has to name all of them, including the one no `-S` invocation ever names.
        written = history_writers(used).get(canary, [])
        named = set(git(used, "log", "--all", "--format=%h", "-S" + tok(canary)).split())
        expect_true("the finding names a commit the count-based sweep never names",
                    bool(set(written) - named), f"pass={sorted(written)} sweep={sorted(named)}")

        # The minter as shipped walks past the used id, and what it lands on is clean.
        rc, shipped, err = run_minter(used, "--raw")
        expect_true(f"rule 5: the minter as shipped walks past it to {tok(canary + 1)}",
                    rc == 0 and shipped == canary + 1, f"got rc={rc} {shipped} :: {err[-160:]}")
        expect("rule 5: what it lands on is written by no commit", False,
               check_reuse(used, shipped or -1))
        expect("rule 5 end to end: the whole check on the reuse corpus", False, check(used, floor=0)[0])

        # The green half of the canary: the same corpus, the id genuinely unused, stays clean.
        expect("rule 5: the same corpus, the canary genuinely unused", False,
               check_reuse(free, canary))
        expect("control: and the whole check on it stays green", False, check(free, floor=0)[0])

        # The bound is load-bearing: given one candidate to look at, the minter must REFUSE to mint
        # rather than hand out the used id it has just proved is used.
        rc, nothing, err = run_minter(used, "--raw", window=1)
        expect_true("bound: a 1-wide candidate window refuses to mint (rc 2, no id printed)",
                    rc == 2 and nothing is None, f"got rc={rc} {nothing} :: {err[-160:]}")
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
    # The next free id is the minter's answer, read by running it — never this file's arithmetic.
    proposal = info["proposal"]
    free = str(proposal) if proposal is not None else \
        f"none minted: {info.get('refused', 'the minter printed no id')}"
    if args.show:
        print(f"mint space: block={block} registry_max={real_max} minter_max={info['minter_max']} "
              f"tokens={info['tokens']} ids set aside={info['block_span']} next_free={free}")
    for f in bad:
        print(f"FINDING: {f}", file=sys.stderr)
    if bad:
        print(f"check_hd_mint_space: {len(bad)} finding(s) — the id space is not held open",
              file=sys.stderr)
        return 1
    print(f"OK: mint space reserved — block {block}, registry ceiling {real_max}, "
          "no synthetic id outside the block, no registry row inside it, "
          f"the minter's id is written by no commit (next free: {free})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
