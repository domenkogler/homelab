#!/usr/bin/env python3
"""Gate: `todo-table.md` §B9 holds EXACTLY the row ids `todo.md` carries — in both directions.

Why this file exists. §B9 is "the complete redundancy" — the one place the whole open backlog is
listed for whoever picks the next piece of work — and nothing in the suite compared its id set with
the registry's. The seam is written into the view's own header: re-syncs that found **13**, **8** and
**18** rows missing, each caught by a human typing `comm` at a shell. The hand is the weak part. A row
minted by a cleanup commit lands in the registry only, so it belongs to no index and is read by
nobody — which is how a falsified premise survives a week of sessions. The rule was never enforced.

Both directions matter, and they are different bugs:
  * a row `todo.md` carries and §B9 does not — work that exists in the registry and is invisible to
    the dispatch view (the recurrence above);
  * an id §B9 carries and `todo.md` does not — either a closed row that outlived its deletion
    (CONVENTIONS §4(a): the view loses the line with the row) or a view INVENTING a row, which is what
    a view edit that renumbers or mistypes an id looks like. A one-directional gate cannot see this
    half at all, and the second half is the one that would let the view become a second record.

The comparison is ONE regex applied to both files (`| HD-<id> |` at a row start), because a diff that
extracts the two sides differently is not a diff. The section is located by its heading, so the
appendix may move. Counts are derived at run time, never carried (CONVENTIONS §2). Ids are compared
with leading zeros normalised (`HD-04` and `HD-4` are one row); a renamed or renumbered id is prose
drift and belongs to the citation gates, not here — declared limit. A THIRD check exists because a set
diff cannot see it: §B9 listing one row twice leaves both id sets equal, so the view's row count
against its id count is a verdict here, not decoration (a duplicate in the REGISTRY is
`check_todo_done.py`'s stem-keyed rule; this is the view's half of the same defect).

`--show-baseline` prints the ledger body for a difference the repo has DECIDED to carry, in the shape
the other view gates use. Today nothing legitimately differs, so `scripts/gate/view_sync_baseline.txt`
is deliberately ABSENT and the diff is expected to be empty; a baseline line whose difference cleared
reddens, on the same principle as every other ratchet here — an entry that outlives its reason exempts
the next drift too.

Run:   python3 scripts/gate/check_view_registry_sync.py [--verbose] [--self-test] [--show-baseline]
Exit:  0 = the two id sets are equal and the index lists no row twice;
       1 = they differ — both directions printed, with their counts; or a baseline line went stale;
       2 = cannot judge: a file is missing, §B9's heading is gone, or the registry parsed too few rows.
Wired into `validate-all.sh` (every profile — two reads and a set difference) and listed in
`scripts/README.md`.
"""
from __future__ import annotations

import io
import os
import re
import shutil
import subprocess
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
BASELINE = ROOT / "scripts" / "gate" / "view_sync_baseline.txt"
# The appendix's heading — located by text, never by line number.
SECTION = "### B9."
# A row id at the start of a table row: `| HD-1170 | …`. The same extraction on both files IS the
# comparison, so it is one regex and not two.
ROW_RE = re.compile(r"^\|\s*HD-([0-9]+[A-Za-z]?)\s*\|")
# The identity is the numeric stem plus a letter suffix: `04` and `4` are one row. Same stem rule the
# duplicate-id gate uses, so the two cannot disagree about what an id is.
STEM_RE = re.compile(r"^0*(\d+)([A-Za-z]?)$")
MAX_PRINTED = 20


class ViewError(Exception):
    """The comparison cannot be made — a missing file or a vanished appendix. A loud boundary, and
    `main` turns it into exit 2: the alternative is an empty set, which reads as a clean view."""


def row_ids(text: str) -> list[str]:
    """Every row id a chunk of markdown carries, in file order, as written."""
    return [m.group(1) for line in text.splitlines() if (m := ROW_RE.match(line))]


def norm(raw: str) -> str:
    """`04` -> `HD-4`, `4a` -> `HD-4a`, `HD-04` -> `HD-4`: the stem without zero padding, suffix kept.
    Idempotent, because the extraction hands out bare stems and the reporter sees ids already run
    through here — a second pass that mangled an id would report every row as a difference."""
    stem = raw[3:] if raw.upper().startswith("HD-") else raw
    m = STEM_RE.match(stem)
    return f"HD-{m.group(1)}{m.group(2)}" if m else f"HD-{stem}"


def section(text: str, heading: str = SECTION, origin: str = "the view") -> str:
    """The named section's own text, up to the next heading of any level."""
    lines = text.splitlines()
    starts = [i for i, ln in enumerate(lines) if ln.startswith(heading)]
    if not starts:
        raise ViewError(f"{origin} has no section starting {heading!r} — the appendix this gate "
                        "compares against is GONE, and an empty set is not a clean view")
    start = starts[-1]  # the LAST one: a re-sync note quoting the heading is not the appendix
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("#")), len(lines))
    return "\n".join(lines[start:end])


def read(path: Path) -> str:
    if not path.is_file():
        raise ViewError(f"{path.name} is missing — the gate cannot compare two views when one is gone")
    return path.read_text(encoding="utf-8", errors="replace")


def read_baseline(path: Path) -> set[str]:
    """Ids a difference is agreed for. An absent file means nothing legitimately differs, which is the
    expected state: a baseline here is the exception path, not the normal one."""
    if not path.is_file():
        return set()
    return {ln.split("\t")[0].strip() for ln in path.read_text(encoding="utf-8").splitlines()
            if ln.strip() and not ln.startswith("#")}


def diff(reg: list[str], view: list[str], exempt: set[str]) -> tuple[list[str], list[str], list[str]]:
    """(rows the registry carries that the view does not, ids the view carries that the registry does
    not, baseline lines whose difference has cleared). The ONE place the verdict is decided."""
    r, v = {norm(x) for x in reg}, {norm(x) for x in view}
    missing = sorted(r - v - exempt)
    extra = sorted(v - r - exempt)
    cleared = sorted(exempt - (r ^ v))
    return missing, extra, cleared


def duplicates(view: list[str]) -> list[str]:
    """Ids the INDEX lists twice. A set comparison cannot see it — both sides hold the same ids — so the
    row count beside the id count is load-bearing here rather than decorative. (A duplicate in the
    REGISTRY is `check_todo_done.py`'s stem-keyed rule; this is the view's half of the same defect.)"""
    seen, out = set(), []
    for x in view:
        if x in seen and x not in out:
            out.append(x)
        seen.add(x)
    return sorted(out)


def report(reg: list[str], view: list[str], missing: list[str], extra: list[str],
           cleared: list[str], verbose: bool = False) -> int:
    dupes = duplicates(view)
    print(f"registry {REGISTRY.name}: {len({norm(x) for x in reg})} row id(s) over {len(reg)} row(s); "
          f"view {VIEW.name} {SECTION.strip()}: {len({norm(x) for x in view})} row id(s) "
          f"over {len(view)} row(s)")
    if missing:
        print(f"FAIL: {len(missing)} row(s) the registry carries and §B9 does NOT — work that is in the "
              "registry and invisible to the dispatch view, which is how a row stops being read:")
        for i in missing[:MAX_PRINTED]:
            print(f"  {i}  (in {REGISTRY.name}, not in {VIEW.name} {SECTION.strip()})")
        if len(missing) > MAX_PRINTED:
            print(f"  … {len(missing) - MAX_PRINTED} more, same direction")
    if extra:
        print(f"FAIL: {len(extra)} id(s) §B9 carries that the registry does NOT — a view is a VIEW, not "
              "a second record (CONVENTIONS §4(a)): either a deleted row outlived its line, or the view "
              "invented an id:")
        for i in extra[:MAX_PRINTED]:
            print(f"  {i}  (in {VIEW.name} {SECTION.strip()}, not in {REGISTRY.name})")
    if dupes:
        print(f"FAIL: §B9 lists {len(dupes)} id(s) twice — one row cannot have two index lines, and a "
              "set comparison cannot see this, so the row count above is the witness:")
        for i in dupes[:MAX_PRINTED]:
            print(f"  {i}  (twice in {VIEW.name} {SECTION.strip()})")
    if cleared:
        print(f"STALE baseline line(s): {len(cleared)} — the difference each one carries is gone, so the "
              "line is a free pass for the next drift; re-derive with --show-baseline:")
        for i in cleared[:10]:
            print(f"  {i}")
    if missing or extra or cleared or dupes:
        print("Fix the VIEW in the commit that moved the registry: re-derive §B9 from todo.md "
              "(the extraction this gate uses is `grep -oE '^\\| HD-[0-9]+[A-Za-z]?\\|'`), or name the "
              "difference in the baseline with its reason.")
        return 1
    print(f"OK: the registry and §B9 hold the same {len({norm(x) for x in reg})} row id(s) — the diff is "
          "empty in both directions"
          + (" (baseline file present)" if BASELINE.is_file() else " (no baseline: nothing legitimately differs)"))
    if verbose:
        print("ids: " + " ".join(sorted({norm(x) for x in reg})))
    return 0


# --------------------------------------------------------------------------- self-test
def _fixture(tmp: Path, reg_ids: list[str], view_ids: list[str],
             baseline: list[str] | None = None) -> tuple[Path, Path, Path]:
    """A throwaway registry + view + baseline. Nothing here touches the real tree — the pool runs
    read-only, and a self-test that rewrites a root view is HD-1117's flake class."""
    reg = tmp / "todo.md"
    reg.write_text("# registry\n\n| Row | P |\n|---|---|\n"
                   + "\n".join(f"| HD-{i} | 2 |" for i in reg_ids) + "\n", encoding="utf-8")
    view = tmp / "todo-table.md"
    view.write_text("# view\n\n> a note that quotes §B9 in prose: | HD-9777 | is not a row\n\n"
                    "### B9. index\n\n| Row | P |\n|---|---|\n"
                    + "\n".join(f"| HD-{i} | 2 |" for i in view_ids) + "\n\n## C. rules\n\nnothing\n",
                    encoding="utf-8")
    base = tmp / "baseline.txt"
    if baseline is None:
        base.unlink(missing_ok=True)
    else:
        base.write_text("# test baseline\n" + "\n".join(baseline) + "\n", encoding="utf-8")
    return reg, view, base


def self_test() -> int:
    fails = 0

    def check(label: str, ok: bool, detail: str = "") -> None:
        nonlocal fails
        fails += not ok
        print(f"  arm {label}: {'ok' if ok else 'FAIL'}{(' — ' + detail) if (detail and not ok) else ''}")

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)

        def run(reg_ids: list[str], view_ids: list[str],
                baseline: list[str] | None = None) -> tuple[int, str]:
            reg, view, base = _fixture(tmp, reg_ids, view_ids, baseline)
            r = [norm(x) for x in row_ids(reg.read_text(encoding="utf-8"))]
            v = [norm(x) for x in row_ids(section(view.read_text(encoding="utf-8")))]
            missing, extra, cleared = diff(r, v, read_baseline(base))
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = report(r, v, missing, extra, cleared)
            return rc, buf.getvalue()

        # (1) equal sets read green, and the counts printed are the ones derived a line above.
        rc, out = run(["1095", "1170"], ["1095", "1170"])
        check("equal sets GREEN, counts derived", rc == 0 and "2 row id(s)" in out,
              f"rc {rc}: {out.strip()[:110]}")

        # (2) the recurrence: a row the registry carries and §B9 lacks. This is the shape a commit that
        # MINTS a row produces, and it is the one every past re-sync note describes.
        rc, out = run(["1170", "1171", "1172"], ["1170"])
        fails_part = out.split("FAIL:")[1] if "FAIL:" in out else ""
        check("a row missing from §B9 REDDENS and names it",
              rc == 1 and "HD-1171" in out and "HD-1172" in out and "HD-1170" not in fails_part,
              f"rc {rc}: {out.strip()[:110]}")

        # (3) the direction nobody remembers: §B9 carries an id the registry does not. A view inventing
        # a row, or a deleted row outliving its line — invisible to a "is everything listed?" gate.
        rc, out = run(["1170"], ["1170", "9999"])
        check("an id in §B9 the registry does NOT have REDDENS", rc == 1 and "HD-9999" in out,
              f"rc {rc}: {out.strip()[:110]}")

        # (4) both halves print TOGETHER, so a red run cannot be mistaken for the other bug.
        rc, out = run(["1170", "1171"], ["1170", "9999"])
        check("both directions print together",
              rc == 1 and "HD-1171" in out and "HD-9999" in out and out.count("FAIL:") == 2,
              f"rc {rc}: {out.strip()[:150]}")

        # (5) zero padding is one row, not drift.
        rc, _o = run(["04", "6"], ["4", "6"])
        check("HD-04 and HD-4 are one row", rc == 0, "a padded id read as a difference")

        # (6) the ratchet both ways: a carried difference is quiet; a carried difference that went is
        # STALE, because a line nobody needs stops being a reason and becomes a mute.
        rc, out = run(["1170", "1171"], ["1170"], baseline=["HD-1171\tWHY the repo carries it"])
        check("a baselined difference is quiet", rc == 0, f"rc {rc}: {out.strip()[:110]}")
        rc, out = run(["1170"], ["1170"], baseline=["HD-1171\tcleared"])
        check("a baseline line whose difference cleared prints STALE", rc == 1 and "STALE" in out,
              f"rc {rc}: {out.strip()[:110]}")

        # (7) a view whose appendix vanished is a boundary, never an empty set read as clean.
        gone = tmp / "no-b9.md"
        gone.write_text("# view\n\n## B. something else\n\n| HD-1 | 2 |\n", encoding="utf-8")
        try:
            section(gone.read_text(encoding="utf-8"))
            check("a missing §B9 section is loud, not empty", False, "section() returned quietly")
        except ViewError as exc:
            check("a missing §B9 section is loud, not empty", "GONE" in str(exc), str(exc)[:80])

        # (8) a heading quoted inside a prose note is not the appendix: the LAST one wins.
        quoted = tmp / "quoted.md"
        quoted.write_text("### B9. index\n\n| HD-1 | 2 |\n\n> prose\n\n### B9. real index\n\n"
                          "| HD-2 | 2 |\n\n## C. rules\n", encoding="utf-8")
        check("the appendix is the LAST §B9 heading, not a quoted one",
              row_ids(section(quoted.read_text(encoding="utf-8"))) == ["2"],
              str(row_ids(section(quoted.read_text(encoding="utf-8")))))

        # (9) an empty registry is a broken walk, never a clean backlog.
        try:
            require_corpus(len(row_ids("# registry\n\nno rows\n")), 0, "todo.md rows")
            check("an empty registry refuses", False, "the corpus floor did not fire")
        except SystemExit:
            check("an empty registry refuses", True)

        # (10) the case a SET comparison cannot see: §B9 lists one row twice. The id sets match, so a
        # gate that only diffs sets prints OK over an index with a row in it twice.
        rc, out = run(["1170", "1171"], ["1170", "1170", "1171"])
        check("a row listed TWICE in §B9 REDDENS even though the id sets match",
              rc == 1 and "twice" in out and "HD-1170" in out, f"rc {rc}: {out.strip()[:120]}")

    print(f"check_view_registry_sync.py --self-test: {fails} failing arm(s)")
    if fails:
        return 1
    if os.environ.get("VIEW_GATE_MUTANT") == "1":
        return 0
    return 1 if mutation_test() else 0


MUTATIONS = [
    # (label, old source text, new source text, which arm must go red)
    ("only the remembered direction is compared",
     "    missing = sorted(r - v - exempt)\n    extra = sorted(v - r - exempt)",
     "    missing = sorted(r - v - exempt)\n    extra = []",
     "the invented-row arm"),
    ("the view is compared against the registry twice, never against itself",
     "    r, v = {norm(x) for x in reg}, {norm(x) for x in view}",
     "    r, v = {norm(x) for x in reg}, {norm(x) for x in reg}",
     "both direction arms"),
    ("the baseline outlives its reason and stays quiet",
     "    cleared = sorted(exempt - (r ^ v))",
     "    cleared = sorted(set())",
     "the STALE-baseline arm"),
    ("a row listed twice in the index is invisible, because the sets still match",
     "    if missing or extra or cleared or dupes:",
     "    if missing or extra or cleared:",
     "the duplicate-row arm"),
]


def mutate(src: str, old: str, new: str) -> str | None:
    """Patch the CODE occurrence of `old`. The table above carries the same strings as data, so the
    table region is excluded — a checker that edited its own mutation table would prove nothing."""
    start = src.index("MUTATIONS = [")
    end = src.index("\n]", start)
    for m in re.finditer(re.escape(old), src):
        if not start <= m.start() < end:
            return src[:m.start()] + new + src[m.end():]
    return None


def mutation_test() -> int:
    """Patch this file's own diff in a copy and require the arms to go red. A checker that cannot be
    broken is a claim, not a check."""
    src = Path(__file__).read_text(encoding="utf-8")
    failed = 0
    for label, old, new, must_break in MUTATIONS:
        mutated = mutate(src, old, new)
        if mutated is None:
            print(f"  mutate {label}: FAIL — the source anchor moved")
            failed += 1
            continue
        with tempfile.TemporaryDirectory() as td:
            fake = Path(td) / "scripts"
            (fake / "lib").mkdir(parents=True)
            (fake / "gate").mkdir()
            shutil.copy(ROOT / "scripts" / "lib" / "repo_root.py", fake / "lib" / "repo_root.py")
            mutant = fake / "gate" / "view-mutant.py"
            mutant.write_text(mutated, encoding="utf-8")
            r = subprocess.run([sys.executable, str(mutant), "--self-test"], capture_output=True,
                               text=True, env=dict(os.environ, VIEW_GATE_MUTANT="1", REPO=str(ROOT)),
                               stdin=subprocess.DEVNULL)
        broke = sorted({ln.split(" arm ")[1].split(":")[0] for ln in (r.stdout or "").splitlines()
                        if ": FAIL" in ln})
        ok = r.returncode == 1 and broke
        failed += not ok
        detail = (f"{len(broke)} arm(s) red: {', '.join(broke[:3])}" if ok else
                  f"rc {r.returncode}, nothing broke: {(r.stdout or r.stderr).strip()[-90:]}")
        print(f"  mutate {label} (must break the {must_break} arm): {'ok' if ok else 'FAIL'} — {detail}")
    return failed


# --------------------------------------------------------------------------- main
def main() -> int:
    argv = sys.argv[1:]
    if "--self-test" in argv:
        print("check_view_registry_sync.py --self-test")
        return self_test()
    try:
        reg = [norm(x) for x in row_ids(read(REGISTRY))]
        view = [norm(x) for x in row_ids(section(read(VIEW), SECTION, VIEW.name))]
    except ViewError as exc:
        print(f"SKIP: {exc} — an unreadable view is an environment boundary, not a green")
        return 2
    require_corpus(len(reg), 40, "todo.md registry rows")
    if "--show-baseline" in argv:
        # STDOUT is the ledger body, so every informational line goes to stderr (the same discipline
        # as check_doc_path_refs.py: the redirect must write a clean file).
        missing, extra, _c = diff(reg, view, set())
        print(f"# re-derived by scripts/gate/{Path(__file__).name} --show-baseline: "
              f"{len(missing) + len(extra)} differing id(s), both directions", file=sys.stderr)
        print("# one line per difference: <id>TAB<why the repo carries it>. A line whose difference "
              "cleared reddens, so this file is a ratchet and never a mute.", file=sys.stderr)
        for i in missing + extra:
            print(f"{i}\tWHY — name the reason; an unexplained line is a mute")
        print(f"--show-baseline: {len(missing) + len(extra)} line(s) for the {SECTION.strip()} diff — "
              "the expected answer here is zero", file=sys.stderr)
        return 0
    return report(reg, view, *diff(reg, view, read_baseline(BASELINE)), verbose="--verbose" in argv)


if __name__ == "__main__":
    sys.exit(main())
