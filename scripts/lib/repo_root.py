#!/usr/bin/env python3
"""lib/repo_root.py — the ONE repo-root resolver for python (HD-1118 Stage 1).

Why (the same reason as lib/repo-root.sh, in the other language): 33 python
files wrote `ROOT = Path(__file__).resolve().parent.parent` (or `parents[1]`),
which hardcodes "I am one directory below the repo root". Add one folder level
under `scripts/` and every one of them resolves to `scripts/`, every tree walk
finds nothing, and the validator prints `OK: 0 files` — green while checking
nothing, the HD-417 mute-failure class. The fix has to be in place before any
file changes directory, which is why Stage 1 is structure-neutral.

Use at an old `ROOT = ...` site (works at `scripts/x.py` and `scripts/<f>/x.py`):

    sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                                if p.name == "scripts") / "lib"))
    from repo_root import root            # noqa: E402
    ROOT = root(__file__)

Also here, because both are root-shaped problems the move would otherwise break:

  require_corpus(count, floor, what)  — the corpus-non-empty assertion (Stage 1.2):
      a walk that found (almost) nothing is a BROKEN ROOT, not a clean tree, so it
      must raise instead of printing OK. One implementation, 20 call sites.
  script_path(name)                   — resolve a `scripts/` file by NAME at any
      depth. `render_all.py` imports its renderers by MODULE name (so they must
      live in its own directory) and two checkers do a same-directory
      `sys.path.insert` for the same reason; after Stage 3 those folders differ,
      and the failure would be a silently un-rendered doc. A name lookup beats a
      literal name→path map: the tree stays written down in exactly one place.

Self-test:  python3 scripts/lib/repo_root.py --self-test
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Both markers, same as lib/repo-root.sh: either one alone could be a subtree.
MARKERS = ("IaC/ansible", "docs/index.md")
SCRIPTS_DIR_NAME = "scripts"


class RepoRootError(RuntimeError):
    """No repo root found — loud on purpose, never an empty Path."""


def find_root(start) -> Path:
    """Walk up from a file or directory until the repo markers show up. Depth-neutral."""
    p = Path(start).resolve()
    if p.is_file():
        p = p.parent
    for d in (p, *p.parents):
        if all((d / m).exists() for m in MARKERS):
            return d
    raise RepoRootError(f"no repo root above {p} (looked for {', '.join(MARKERS)})")


def root(caller_file=None) -> Path:
    """The repo root: an explicit $REPO wins (wrappers/fixtures), else resolve.

    `caller_file` should be the caller's __file__ so the scan starts at the CALLER,
    not at this helper (they are the same tree today, but the caller is the honest
    starting point and it keeps the helper relocatable).
    """
    env = os.environ.get("REPO")
    if env:
        return Path(env)
    return find_root(caller_file or __file__)


def scripts_dir(caller_file=None) -> Path:
    """The scripts/ directory itself, found by NAME — no depth assumption."""
    p = Path(caller_file or __file__).resolve()
    start = p.parent if p.is_file() else p
    for d in (start, *start.parents):
        if d.name == SCRIPTS_DIR_NAME and (d / "lib" / "repo_root.py").is_file():
            return d
    # Normal case for anything under scripts/: the ancestor named "scripts".
    for d in (start, *start.parents):
        if d.name == SCRIPTS_DIR_NAME:
            return d
    return root(caller_file) / SCRIPTS_DIR_NAME


def script_path(name, caller_file=None) -> Path:
    """Resolve one `scripts/` file by NAME at whatever depth it currently lives.

    Raises when the name is missing or ambiguous — both are loud, because the
    silent alternative is render_all importing nothing and a generated doc going
    stale while the gate stays green.
    """
    base = scripts_dir(caller_file)
    hits = sorted(p for p in base.rglob(name) if p.is_file() and "testdata" not in p.parts)
    if not hits:
        raise RepoRootError(f"no scripts/**/{name} under {base}")
    if len(hits) > 1:
        raise RepoRootError(f"ambiguous scripts/{name}: {[str(p.relative_to(base)) for p in hits]}")
    return hits[0]


# --- which bash execs a repo script: PROBE, not name -------------------------------------------
# WHY: on a Windows seat that has WSL installed, `subprocess.run(["bash", script, …])` does NOT get
# the bash the session is in. Windows resolves the bare name through the App Execution Aliases, so the
# child is born in the WSL kernel: it answers `uname -s` = Linux, `pwd` = /mnt/d/…, and the Windows
# path of the script it was handed is simply not a file there. The symptom is a `No such file or
# directory` about a script that is sitting on disk — on ONE seat only, while the same commit is green
# on the two Debian seats. Same class as the gate's Python launcher: a NAME is never the answer, and
# the probe is the one question that cannot lie — can you read the file you are about to run?
# CACHED per process: a probe costs one exec, and an exec is what is expensive on this host (HD-1135).
_BASH_SEEN: dict = {}


def _bash_candidates() -> list:
    """Candidate bash executables, best-informed first. Each is a PROPOSAL the probe confirms."""
    cands = [v for v in (os.environ.get("HL_BASH"), os.environ.get("BASH")) if v]
    if os.name == "nt":
        # The bash belonging to the git this checkout uses — derived from git's own location, so a
        # portable install (winget, D:\, PortableGit) resolves and no drive letter is hardcoded.
        git = shutil.which("git")
        if git:
            for p in Path(git).resolve().parents:
                if p.name.lower() == "git":
                    cands.append(str(p / "usr" / "bin" / "bash.exe"))
                    break
    cands.append("bash")                        # the POSIX answer; last, because on Windows it may lie
    out = []
    for c in cands:
        if c not in out:
            out.append(c)
    return out


def hl_bash(script):
    """-> (argv, path_string): a bash that can READ `script`, and the path form IT understands.

    Raises RepoRootError when no candidate can see the file — a refusal naming what was tried, never
    an exec that dies with a misleading `No such file or directory`, and never a silent pass.
    """
    sp = Path(script)
    key = (str(sp), os.environ.get("HL_BASH", ""), os.environ.get("BASH", ""))
    if key in _BASH_SEEN:
        return _BASH_SEEN[key]
    forms = [sp.as_posix(), str(sp)]
    if os.name == "nt":                         # /mnt/<drive>/… is how a WSL-born child reads it
        forms.append(re.sub(r"^([A-Za-z]):", lambda m: "/mnt/" + m.group(1).lower(), sp.as_posix()))
    tried = []
    for cand in _bash_candidates():
        for form in forms:
            try:
                got = subprocess.run([cand, "-c", 'test -f "$1" && echo CANARY_OK', "x", form],
                                     capture_output=True, text=True, encoding="utf-8",
                                     errors="replace", timeout=15)
            except (OSError, subprocess.SubprocessError) as exc:
                tried.append(f"{cand} [{form}]: {type(exc).__name__}")
                continue
            if got.stdout.strip() == "CANARY_OK":
                _BASH_SEEN[key] = ([cand], form)
                return [cand], form
            tried.append(f"{cand} [{form}]: cannot read the script")
    raise RepoRootError(
        "CANNOT RUN: no bash on this host can read " + sp.as_posix() + " — tried: " + "; ".join(tried)
        + ". A Windows seat with WSL resolves the bare name `bash` to the WSL launcher, which sees no "
        "Windows paths at all; set HL_BASH to the bash that owns this session — in Git bash, "
        "HL_BASH=$(cygpath -w $BASH). A leg that cannot exec is a refusal, never a pass."
    )


def require_corpus(count: int, floor: int, what: str) -> int:
    """Assert a walk actually saw files. Returns count; raises when it did not.

    WHY this exists: with a broken root the tree walk yields nothing, and every
    checker here is shaped like `if findings: fail; print("OK")` — so a broken root
    prints OK. A floor per checker is the cheap witness that the probe saw a corpus
    (the check_md_tables.py model, generalised). Floor values are deliberately far
    below the real counts, so they only fire on a root/walk regression, never on an
    ordinary commit that deletes one file.
    """
    if count <= floor:
        raise SystemExit(
            f"CORPUS FLOOR: {what} — walked {count} file(s), expected more than {floor}. "
            "That is a broken repo root or a wrong walk, not a clean tree (HD-1118 Stage 1): "
            "a gate that cannot see the files cannot fail either."
        )
    return count


def self_test() -> int:
    """Returns the number of arms NOT caught."""
    fails = 0
    tmp = Path(tempfile.mkdtemp(prefix="repotest-"))
    try:
        # Depth-neutral canary: the SAME resolver at two depths of a fake repo.
        fake = tmp / "repo"
        (fake / "IaC" / "ansible").mkdir(parents=True)
        (fake / "docs").mkdir(parents=True)
        (fake / "docs" / "index.md").write_text("# index\n", encoding="utf-8")
        lib = fake / "scripts" / "lib"
        lib.mkdir(parents=True)
        shutil.copy(Path(__file__), lib / "repo_root.py")
        for rel in ("scripts", "scripts/gate"):
            d = fake / rel
            d.mkdir(parents=True, exist_ok=True)
            (d / "caller.py").write_text(
                "import sys\n"
                "from pathlib import Path\n"
                "sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents"
                " if p.name == 'scripts') / 'lib'))\n"
                "from repo_root import root\n"
                "print(root(__file__))\n",
                encoding="utf-8",
            )
            got = subprocess.run([sys.executable, str(d / "caller.py")], capture_output=True, text=True)
            want = str(fake)
            if (got.stdout or "").strip() == want:
                print(f"ok: python root resolves from {rel} (structure-neutral)")
            else:
                print(f"NOT CAUGHT: python root from {rel} = {(got.stdout or got.stderr).strip()} (want {want})")
                fails += 1

        # No markers → a loud failure, never a plausible-looking wrong root.
        stray = tmp / "stray" / "scripts"
        stray.mkdir(parents=True)
        (stray / "caller.py").write_text(
            f"import sys\nsys.path.insert(0, {str(lib)!r})\nfrom repo_root import find_root\n"
            "print(find_root(__file__))\n",
            encoding="utf-8",
        )
        got = subprocess.run([sys.executable, str(stray / "caller.py")], capture_output=True, text=True)
        if got.returncode != 0 and "no repo root" in got.stderr:
            print("ok: a non-repo directory fails loud (python)")
        else:
            print(f"NOT CAUGHT: a non-repo directory resolved (rc={got.returncode})")
            fails += 1

        # require_corpus: the assertion must be able to fail, and must not fire at rest.
        try:
            require_corpus(0, 5, "test walk")
            print("NOT CAUGHT: require_corpus accepted an empty walk")
            fails += 1
        except SystemExit:
            print("ok: require_corpus fails on an empty walk")
        try:
            require_corpus(400, 5, "test walk")
            print("ok: require_corpus passes a real corpus")
        except SystemExit:
            print("NOT CAUGHT: require_corpus fired on a full corpus")
            fails += 1

        # script_path: finds this checkout's renderers by name, and is loud on a
        # name that does not exist.
        p = script_path("render_all.py", __file__)
        if p.is_file() and p.parent.name == "scripts":
            print("ok: script_path resolves a name at its current depth")
        else:
            print(f"NOT CAUGHT: script_path returned {p}")
            fails += 1
        try:
            script_path("definitely-not-a-real-script-xyz.py", __file__)
            print("NOT CAUGHT: script_path tolerated a missing name")
            fails += 1
        except RepoRootError:
            print("ok: script_path is loud on a missing name")

        # hl_bash: which bash execs a repo script. Three arms, because the defect it prevents is a
        # child born in the WRONG SUBSYSTEM (a Windows seat with WSL resolves the bare name `bash` to
        # the WSL launcher, which cannot see a Windows path at all) — a leg that dies with "No such
        # file or directory" about a file that exists, on one seat only.
        _BASH_SEEN.clear()
        blind = tmp / "blind-bash.sh"
        # A fixture that answers every `test -f` as NOT FOUND: the wrong-subsystem bash, bred rather
        # than described. Without this arm the resolver could pass by never probing at all.
        blind.write_text("#!/usr/bin/env bash\nexit 1\n", encoding="utf-8", newline="\n")
        os.chmod(blind, 0o755)
        real = Path(__file__).resolve().parent / "repo_root.py"
        os.environ["HL_BASH"] = str(blind)
        try:
            argv, form = hl_bash(real)
            got = subprocess.run([*argv, "-c", 'test -f "$1" && echo CANARY_OK', "x", form],
                                 capture_output=True, text=True, encoding="utf-8", errors="replace")
            if got.stdout.strip() == "CANARY_OK" and argv != [str(blind)]:
                print(f"ok: hl_bash skipped a bash that could not read the script ({argv[0]})")
            else:
                print(f"NOT CAUGHT: hl_bash returned {argv} and the answer does not read the script")
                fails += 1
        except RepoRootError as exc:
            print(f"NOT CAUGHT: hl_bash refused when a working bash exists ({exc})")
            fails += 1
        # Arm 2: when NOTHING can see the file, the answer is a refusal that names what was tried —
        # never an exec that will print a misleading error, and never a silent pass.
        _BASH_SEEN.clear()
        keep_cands = _bash_candidates
        globals()["_bash_candidates"] = lambda: [str(blind)]
        try:
            hl_bash(real)
            print("NOT CAUGHT: hl_bash answered with a bash that cannot read the script")
            fails += 1
        except RepoRootError as exc:
            print("ok: hl_bash refuses loud when no bash can read the script" if "tried" in str(exc)
                  else f"NOT CAUGHT: hl_bash refused without naming what it tried: {exc}")
            fails += 0 if "tried" in str(exc) else 1
        globals()["_bash_candidates"] = keep_cands
        _BASH_SEEN.clear()
        os.environ.pop("HL_BASH", None)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return fails


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        _f = self_test()
        if _f:
            print(f"repo_root self-test: {_f} arm(s) NOT caught", file=sys.stderr)
        sys.exit(1 if _f else 0)
    print(root(__file__))
