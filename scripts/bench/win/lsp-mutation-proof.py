#!/usr/bin/env python3
"""lsp-mutation-proof.py — do the PATH-adopt and win11 `.cmd` arms REDDEN when they are broken?

WHY THIS EXISTS. `scripts/lib/pi-seat.sh`'s PATH-adopt key (`hl_path_dir_norm` · `hl_path_exports` ·
`hl_path_persist` · `hl_path_rhs`) and `scripts/harness/seat-lsp-binaries.sh`'s win11 `.cmd` read and
adopt report each ship `--self-test` arms, and an arm's GREEN only says the suite ran. This driver
breaks one BRANCH at a time — 15 mutations, each an edit of one arm of that code — and demands that a
canary redden.

    A MUTATION THAT REDDENS NOTHING IS A BLIND SPOT, NOT A PASS.

That sentence is why the file exists. Two shapes answer it: a mutation that leaves both suites GREEN is
a branch no test reads, and a mutation whose anchor is ABSENT (`PATCH-FAILED`) is a mutation that was
never applied — both print as "proved nothing" and both exit 1, because a table that quietly skipped a
missing anchor would report 15 caught while testing 14. An rc that is non-zero with NO canary line is
reported separately and counted the same way: usually the patch broke bash's syntax (rc 2) rather than
the branch, and a run that never reached its assertions has reddened nothing either.

WHAT IT RUNS, and what a verdict is worth. Every mutation is graded against BOTH `--self-test` suites,
so a mutation of the lib is also asked whether the plane's adopt report noticed.
`bench/win/gate-parity.sh` is the sibling instrument and answers a different question: that one compares
one leg across the WSL door, this one breaks one branch at home. Neither subsumes the other.

THE FIXTURE, AND WHERE IT MAY LIVE. Each run mints a FRESH tree in the ENGINE's own `/tmp` (its native
filesystem — `ext4` by default, `tmpfs` when `wsl.conf` mounts one) and mutates ONLY that copy. Never a
seat clone, never the 9P `/mnt/<drive>/` mount: the fixture is a scratch tree this process owns and
throws away, and no checkout is edited at any point — which is also why a run is safe from another lane.
The tree is marker-complete (`IaC/ansible` + `docs/index.md`, the two markers `lib/repo-root.sh` looks
for) so the suites resolve a repo instead of a dump, and it carries the WHOLE `scripts/` tree because the
lib's registry arms resolve plane owners by a globstar walk — a fixture holding one owner script reads
as a broken registry rather than as a repo. The fixture location is REFUSED, with rc 2, when it resolves
under `/mnt/<drive>/` or inside the source tree.

WHY THE ENGINE AND NOT THE WIN11 SEAT: one `fork`+`exec` costs ≈0.66 ms on the engine against 16–44 ms
on Git-Bash with the box quiet and 560–995 ms with it loaded. This table spends 32 suite invocations
(both suites, once per state), so the seat pays hundreds of seconds for the same 15 answers and a
Git-Bash pass of this table does not finish in 26 minutes. The engine is the only seat where the table
is worth running.

RUN IT FROM GIT-BASH ON THE DEBIAN ENGINE (`MSYS_NO_PATHCONV` and `MSYS2_ARG_CONV_EXCL` are a COMMAND
PREFIX, never exported — exported globally they stop the MSYS converter rewriting the path arguments of
every LATER command in the session, which is a broken session that looks fine until it is not):

    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' wsl.exe -d Debian -u domen -- bash -c \
      'cd <this worktree> && python3 scripts/bench/win/lsp-mutation-proof.py'

The source tree is the one this file lives in (found by `lib/repo_root.py`, never by a depth), so the
command above grades its own worktree. `PATHNATIVE="$(cygpath -aw "$PATH")"` in front of a `py -3` run
on the Windows seat hands the children the native PATH spelling — see `run_suite`.

THE BASELINE IS A PRECONDITION, NOT A LOG LINE. Both suites run UNMUTATED first and both must print
GREEN. The reason is the same one the whole table rests on: "the mutation reddened nothing" and "the
suite was already unable to answer" are indistinguishable from the output, so a red baseline turns every
row into noise. Enforced in code — `--baseline` applies no mutation at all and exits 2 if either suite
is red, and the mutation sweep refuses with rc 2 before it applies its first patch.

    python3 scripts/bench/win/lsp-mutation-proof.py --baseline    # the precondition, on its own
    python3 scripts/bench/win/lsp-mutation-proof.py --list        # the 15 names, no execution
    python3 scripts/bench/win/lsp-mutation-proof.py               # baseline, then all 15

WHAT THIS PROVES, AND WHAT IT CANNOT SEE. It proves that the arms DISCRIMINATE — that each branch of
that code is read by an assertion somewhere. It says NOTHING about a seat's live state: it installs
nothing, reads no seat, and reaches no host. A green table here and a seat whose language servers are
invisible are entirely compatible; `bash scripts/harness/seat-lsp-binaries.sh` on that seat is the leg
that answers the live question, and `--push` there writes the PATH block this table only proves the key
for. Re-derive any single row by hand with the anchor it names:

    grep -n 'hl_path_dir_norm()' scripts/lib/pi-seat.sh           # the M2–M5 arms
    grep -n 'hl_path_rhs()' scripts/lib/pi-seat.sh                # the M10–M10b arms
    grep -n 'DRIFT(invisible)' scripts/harness/seat-lsp-binaries.sh   # the M12/M13 arms

EXIT CONTRACT
  0  every mutation reddened a canary — the arms discriminate
  1  BLIND SPOT: a mutation reddened nothing, reddened only an rc with no canary line, or its anchor was
     absent (PATCH-FAILED). The printed table names which.
  2  CANNOT PROVE: no repo root, no fixture location this file is willing to mutate, no bash that can
     read a suite, or a suite RED before any mutation was applied.
"""
from __future__ import annotations

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

# The repo root is FOUND, not derived from a depth: scripts/lib/repo_root.py owns that, and its
# `hl_bash` owns the other question this file would otherwise get wrong on a Windows seat — which bash
# can actually READ the script it is about to exec (a bare `bash` there resolves to the WSL launcher,
# which sees no Windows paths, and the run then "reddens nothing" for a reason that is not the code).
sys.path.insert(0, str(next(p for p in pathlib.Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import RepoRootError, hl_bash, require_corpus, root as _hl_root  # noqa: E402

LIB = "scripts/lib/pi-seat.sh"
PLANE = "scripts/harness/seat-lsp-binaries.sh"
SUITES = (LIB, PLANE)
# The fixture must hold the whole scripts/ tree (see the header); a copy that landed almost nothing is a
# broken root, and a suite graded against an empty registry is a green that checked nothing.
FIXTURE_MIN_SCRIPTS = 40
# The 9P mount: every fork there is the price the header prices the run at, and a fixture written there
# is a fixture the engine reads through a door instead of an exec.
MNT_PATH = re.compile(r"^/mnt/[A-Za-z](/|$)")

# name, file, exact anchor, replacement — every anchor is a BRANCH of that code, never a comment.
MUTS = [
  ("M1 adopt key reads the spelling (the pre-fix grep)", LIB,
   'if hl_path_exports "$__f" "$__dnorm"; then',
   "if grep -E '^[[:space:]]*(export[[:space:]]+)?PATH=' \"$__f\" 2>/dev/null | grep -qF -- \"$__dir\"; then"),
  ("M2 no $HOME expansion in the key", LIB,
   '  __v="${__v//\\$HOME/$HOME}"', '  :'),
  ("M3 no ${HOME} expansion in the key", LIB,
   '  __v="${__v//\\$\\{HOME\\}/$HOME}"', '  :'),
  ("M4 tilde dropped with a REMOVE pattern (the trap)", LIB,
   "case \"$__v\" in '~'/*) __v=\"$HOME/${__v:2}\" ;; '~') __v=\"$HOME\" ;; esac",
   "case \"$__v\" in '~'/*) __v=\"$HOME/${__v#~/}\" ;; '~') __v=\"$HOME\" ;; esac"),
  ("M5 no trailing-slash normalisation", LIB,
   '  while [ "$__v" != "/" ]; do case "$__v" in */) __v="${__v%/}" ;; *) break ;; esac; done',
   '  :'),
  ("M6 always adopt (so never write)", LIB,
   '  done < "$__f"\n  return 1\n}',
   '  done < "$__f"\n  return 0\n}'),
  ("M7 never adopt (so always write)", LIB,
   '  while IFS= read -r __line || [ -n "$__line" ]; do',
   '  while false; do'),
  ("M8 PATH line read as one entry, not a list", LIB,
   '      __part="${__rhs%%:*}"', '      __part="$__rhs"'),
  ("M9 blind to a last line with no newline", LIB,
   '  while IFS= read -r __line || [ -n "$__line" ]; do',
   '  while IFS= read -r __line; do'),
  ("M10 the quoted text not lifted (comment wins)", LIB,
   '    hl_path_rhs __rhs "${__line#PATH=}"',
   '    __rhs="${__line#PATH=}"'),
  ("M11 quotes never open (the value is read as bare text)", LIB,
   '        "\'" | \'"\') __q="$__c" ;;   # a segment opens; the quote itself is never part of the value',
   '        "\'" | \'"\') : ;;'),
  ("M10b the unquoted comment read as part of the value", LIB,
   "        '#') break ;;                # UNQUOTED, so this is the comment: everything after it is prose",
   "        '#') __acc=\"$__acc$__c\" ;;"),
  ("M12 win11 .cmd fallback removed", PLANE,
   '[ "${SEAT:-}" = win11 ] || { RES[$i]="DRIFT(invisible)"; continue; }',
   '{ RES[$i]="DRIFT(invisible)"; continue; }'),
  ("M13 win11 .cmd fallback made universal", PLANE,
   '[ "${SEAT:-}" = win11 ] || { RES[$i]="DRIFT(invisible)"; continue; }',
   'true'),
  ("M14 the adopt report swallowed", PLANE,
   '[ "${HL_PATH_WROTE:-0}" = 0 ] && [ "${HL_PATH_ADOPTED:-0}" = 1 ] && \\',
   '[ "${HL_PATH_WROTE:-0}" = 0 ] && [ "0" = 1 ] && \\'),
]


def readf(p: pathlib.Path) -> str:
    # BYTE round-trip, never write_text(): on a Windows seat text-mode writing turns the fixture's LF
    # into CRLF, and every run after the first dies on `$'\r': command not found` — a driver that
    # reports 15 caught mutations because it corrupted its own fixture is the worst kind of green.
    return p.read_bytes().decode("utf-8")


def writef(p: pathlib.Path, s: str) -> None:
    p.write_bytes(s.encode("utf-8"))


class Refused(RuntimeError):
    """This run cannot be made — the header's rc-2 half, raised in one place so no refusal is ever
    reported as a finding. rc 1 means a mutation proved nothing; it must never mean 'did not run'."""


def fixture_root(src: pathlib.Path) -> pathlib.Path:
    """Mint the fixture root, or refuse. The two refusals are the header's two rules, and both are
    cheap: a fixture on the 9P mount costs the run the mount's fork price, and a fixture INSIDE a
    checkout is a mutation applied to somebody's tree. A refusal removes the directory it made — a
    checker that litters the tree it is refusing to grade is its own kind of finding."""
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="lspmut-")).resolve()
    why = ""
    if MNT_PATH.match(str(tmp)):
        why = (f"the fixture would land on the 9P mount ({tmp}) — the mount is priced at the whole run, "
               "so run this on the Debian engine, where the engine's own /tmp is a native filesystem")
    elif src == tmp or src in tmp.parents:
        why = (f"the fixture would land inside the graded tree ({tmp}) — this driver mutates a copy, "
               "never a checkout. Set TMPDIR outside the worktree.")
    if why:
        shutil.rmtree(tmp, ignore_errors=True)
        raise Refused(why)
    return tmp


def build_fixture(src: pathlib.Path, fix: pathlib.Path) -> int:
    """A marker-complete, repo-shaped copy of the tree the suites read. Returns the file count."""
    (fix / "IaC" / "ansible" / "group_vars" / "all").mkdir(parents=True)
    (fix / "docs").mkdir(parents=True)
    # the WHOLE scripts/ tree: the lib's registry arms resolve plane OWNERS by a globstar walk, so a
    # fixture holding one owner script reads as a broken registry rather than as a repo.
    shutil.copytree(src / "scripts", fix / "scripts", dirs_exist_ok=True)
    shutil.copy2(src / "IaC" / "ansible" / "group_vars" / "all" / "versions.yml",
                 fix / "IaC" / "ansible" / "group_vars" / "all" / "versions.yml")
    # BOTH structural markers lib/repo-root.sh looks for, so the fixture reads as a repo and not as a dump
    (fix / "IaC" / "ansible" / "README.md").write_text("# fixture\n", encoding="utf-8")
    (fix / "docs" / "index.md").write_text("# fixture\n", encoding="utf-8")
    return require_corpus(sum(1 for p in (fix / "scripts").rglob("*") if p.is_file()),
                          FIXTURE_MIN_SCRIPTS, "the fixture's scripts/ tree")


def run_suite(fix: pathlib.Path, rel: str) -> tuple[int, str]:
    """One suite's `--self-test`, inside the fixture. -> (rc, combined output)"""
    # REPO is dropped rather than merely absent: lib/repo_root.root() HONOURS it, so an inherited value
    # would point the fixture's suites back at the real checkout and every patch would land on code no
    # suite is running.
    env = {k: v for k, v in os.environ.items() if k != "REPO"}
    # A native python child on the Windows side inherits the MSYS PATH in POSIX spelling and then every
    # external it execs answers 127 — a driver reporting "reddened nothing" for a run that never
    # executed. `PATHNATIVE=$(cygpath -aw $PATH)` supplies the native spelling when asked for.
    if os.environ.get("PATHNATIVE"):
        env["PATH"] = os.environ["PATHNATIVE"]
    script = fix / rel
    argv, form = hl_bash(script)      # the probe, not the name: a bash that can READ this script
    p = subprocess.run([*argv, form, "--self-test"], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", cwd=str(fix), env=env)
    return p.returncode, p.stdout + p.stderr


def verdicts(fix: pathlib.Path) -> list:
    """Both suites as they stand -> [(red, suite, rc, canary lines, output)]. A canary is the suite's
    own `NOT CAUGHT` line: the suites mutate themselves, so a suite that exits 0 while printing one is
    RED, and an rc alone is never the verdict."""
    out = []
    for rel in SUITES:
        rc, txt = run_suite(fix, rel)
        hits = [line for line in txt.splitlines() if line.startswith("NOT CAUGHT") or " NOT CAUGHT" in line]
        out.append((rc != 0 or bool(hits), rel, rc, hits, txt))
    return out


def tail(txt: str, n: int) -> str:
    lines = txt.strip().splitlines()
    return (lines[-1] if lines else "(no output)")[:n]


def report_baseline(fix: pathlib.Path) -> bool:
    """The precondition, printed. Green on BOTH suites is what buys the mutation table."""
    green = True
    for red, rel, rc, hits, txt in verdicts(fix):
        print(f"baseline {'RED' if red else 'green'}  {rel}  rc={rc}")
        if red:
            green = False
            print("        " + ("; ".join(hits)[:300] or tail(txt, 300)))
    return green


def main(argv: list) -> int:
    ap = argparse.ArgumentParser(
        prog="lsp-mutation-proof.py",
        description="mutation proof for the PATH-adopt key (scripts/lib/pi-seat.sh) and the win11 "
                    "`.cmd` read + adopt report (scripts/harness/seat-lsp-binaries.sh): 15 branch "
                    "mutations, and a canary must redden for each one",
        epilog="exit 0 every mutation caught · exit 1 blind spot or absent anchor · "
               "exit 2 nothing could be proved (baseline red, no fixture, no bash)")
    ap.add_argument("--baseline", action="store_true",
                    help="apply no mutation; exit 2 if either suite is red, 0 if both are green")
    ap.add_argument("--list", action="store_true", help=f"print the {len(MUTS)} mutation names and stop")
    args = ap.parse_args(argv)

    if args.list:
        for name, rel, _old, _new in MUTS:
            print(f"{name}\t{rel}")
        return 0

    tmp = None                      # set once a directory has actually been minted — see the finally
    try:
        src = _hl_root(__file__)
        tmp = fixture_root(src)
        fix = tmp / "fix"
        print(f"fixture: {fix}\nsource:  {src}\n")
        try:
            build_fixture(src, fix)
        except SystemExit as exc:
            # require_corpus's CORPUS FLOOR stop: the copy landed nearly empty, which is a broken root
            # rather than a fixture, and a suite graded against an empty registry is a free green.
            print(f"CANNOT RUN: {exc}", file=sys.stderr)
            return 2
        print(f"baseline: running both suites UNMUTATED in the fixture "
              f"({' + '.join(s for s in SUITES)})")
        if not report_baseline(fix):
            print("ABORT: the fixture is red before any mutation, so this run could prove nothing — "
                  "fix the suite, then re-run")
            return 2
        if args.baseline:
            print(f"\nbaseline green on both suites — {len(MUTS)} mutations NOT applied (this was --baseline)")
            return 0

        blind = 0
        for name, rel, old, new in MUTS:
            path = fix / rel
            keep = path.read_bytes()
            text = readf(path)
            if old not in text:
                print(f"{name:48} PATCH-FAILED  anchor absent — the arm it should redden may not exist")
                blind += 1
                continue
            writef(path, text.replace(old, new, 1))
            res = verdicts(fix)
            path.write_bytes(keep)
            canary = [f"{os.path.basename(s)}: {'; '.join(h)[:150]}" for red, s, rc, h, _ in res if h]
            silent = [f"{os.path.basename(s)} rc={rc} tail={tail(t, 110)}"
                      for red, s, rc, h, t in res if red and not h]
            if canary:
                print(f"{name:48} caught: {canary[0][:190]}")
            elif silent:
                # rc!=0 with no canary line is a run that never reached its assertions — usually a bash
                # syntax error (exit 2) from the patch itself. That is NOT a caught mutation.
                print(f"{name:48} !!! RED WITH NO CANARY (the patch, not the branch): {silent[0][:190]}")
                blind += 1
            else:
                print(f"{name:48} *** REDDENED NOTHING — blind spot ***")
                blind += 1

        print(f"\n{len(MUTS)} branch mutations, {blind} proved nothing")
        return 1 if blind else 0
    except (RepoRootError, Refused) as exc:
        # The rc-2 half: no repo root, no fixture location this file is willing to write, or no bash
        # that can read a suite (`hl_bash`'s refusal). Nothing was graded, so nothing is a finding.
        print(f"CANNOT RUN: {exc}", file=sys.stderr)
        return 2
    finally:
        if tmp is not None:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
