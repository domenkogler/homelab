#!/usr/bin/env python3
"""check_role_docs.py — every Ansible role in the tree is named by a hand-authored doc (HD-1200).

> **Role:** coverage gate over `IaC/ansible/roles/` — the tree→docs direction of the docs seam.
> Read-only, offline, stdlib only.
> **Linked from:** `scripts/README.md` (the validation gate), `docs/index.md` (Validation)

WHY THIS EXISTS. `check_doc_path_refs.py` proves the paths a doc cites exist in the tree, and
`check_doc_map.py` proves every doc under `docs/` is reachable from `docs/index.md`. Both read
docs→tree. Nothing read the other way, so a new role directory could land with no doc of its own and
the suite would say `OK` — the silent half of the same seam, and the expensive kind, because the thing
a role's doc holds (why it exists, what it must never do, how it fails) is exactly what nobody writes
after the merge.

HOW IT DIFFERS FROM ITS NEIGHBOURS, so this repo does not grow a second gate for one seam:
`check_doc_map.py` proves a doc is REACHABLE from `docs/index.md` and that the markdown links a doc
carries resolve — docs→tree, over documents. `check_view_registry_sync.py` diffs two hand-written
views of one id set (`todo.md` rows against `todo-table.md` §B9), so both of its sides are prose lists
that can drift from each other. This gate runs the opposite direction over two DIFFERENT substrates:
one set is derived from a directory listing (`IaC/ansible/roles/`), the other from the text of the
hand-authored `docs/*.md`. There is therefore no second view to keep in step and no baseline to
freeze — the rule is a COVERAGE FLOOR (no role may be undocumented), not a set equality, and its floor
value is 0 findings: the day it was written every role was already named, so its whole value is
prospective. An undocumented role cannot ship.

THE SET IS DERIVED, NEVER LISTED. No role name appears in this file. The universe is whatever
directories exist one level under `IaC/ansible/roles/`, so adding, renaming or deleting a role moves
the rule instead of the script — the same property `check_doc_domain.py` gets from `domain:`
frontmatter.

WHAT COUNTS AS NAMING A ROLE, and why the finding says more than "undocumented":

  path        the doc cites `roles/<name>` or `<name>/tasks/…` — a path into the role. The strongest
              shape: a path is a claim about the tree.
  code        the name sits in an inline code span or a fenced block, i.e. it is used as an
              identifier rather than as an English word.
  cell        the name is the whole content of a markdown table cell — the shape of a role catalogue.
  entry       an ansible-shaped reference: `- name` under `roles:`, `role: name`, `roles: [a, b]`.

  incidental  everything else: the string occurs in prose. For `common`, `network`, `storage`,
              `switch`, `access` and `seat` that is almost always the English word, not the role.

A role is DOCUMENTED when at least one occurrence has an OWNING shape. A role whose only occurrences
are incidental is a finding, and the finding LISTS those sites, because the two fixes are different:
zero sites means "write the doc", incidental-only sites mean "the corpus talks around this role
already — name it where you meant it".

A `docs/*-generated.md` render view is not an author. The corpus is the hand-authored `docs/*.md`, and
the derivation is IMPORTED from `check_doc_size.py` rather than re-spelled here, so the two gates
cannot hold two opinions about what "hand-authored" means (CONVENTIONS §2). A role whose only mention
lives in a render view is undocumented, and the finding says so, because a renderer's output is a
property of the IaC — the thing whose doc is in question (CONVENTIONS §8.2, §8.5).

WHAT THIS DOES NOT PROVE, stated rather than left to be discovered:
  * Not one mention is the RIGHT mention. Code font proves a token is an identifier, not that the
    identifier is this role — `` `docker` `` in backticks most often means the engine. So the floor is
    ONE owning mention and every finding prints its sites: this is coverage, not ownership. Use
    `--verbose` for the per-role doc list and read the owning site before calling a role documented.
  * A name written with the wrong separator (`docker-services` for `docker_services`) is not this
    role's name and reads as a gap. The failure goes the honest way: a gap the gate shows you, not one
    it hides.
  * The corpus is `docs/*.md` one level deep. A role named only in `docs/manual/**` (or only in a root
    doc) reads as undocumented here — the family plane names services, not roles, and the doc that
    owns a role lives with the agent-facing corpus.
  * A role directory that exists but is referenced by no playbook is NOT this gate's finding;
    reachability of a role from a playbook is IaC's own question, and a dead role with a doc passes
    here, which is correct — the rule is about documentation, not about use.

Run:   python3 scripts/gate/check_role_docs.py [--verbose] [--self-test]
Exit:  0 = every role dir is named by >=1 hand-authored doc · 1 = undocumented role(s), each with its
         sites · 2 = could not run: no `IaC/ansible/roles/` to walk, no hand-authored docs, a doc whose
         bytes cannot be read, or a walk below a corpus floor. A gate that cannot see the tree cannot
         fail either, so it refuses instead of printing OK.
"""
from __future__ import annotations

import argparse
import importlib.util
import re
import sys
import tempfile
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root, script_path  # noqa: E402

ROOT = _hl_root(__file__)
ROLES_REL = "IaC/ansible/roles"
# Floors, not measurements: 27 role dirs and 75 hand-authored docs/*.md in the tree when this was
# written. Both sit far below the tree on purpose — they fire on a broken root or a blind walk, never
# on an ordinary commit that adds one role.
ROLE_FLOOR = 8
DOC_FLOOR = 40
FENCE_RE = re.compile(r"^[ \t]*(?:```|~~~)")
MAX_PRINTED = 8


class ToolError(Exception):
    """The gate cannot run. A boundary is printed and exits 2; it is never a green and never a SKIP."""


def load_doc_walk():
    """`(walk_docs, GENERATED_SUFFIX, origin)` — the ONE hand-authored-docs derivation, imported.

    Spelled a second time here it would be a second source: two gates disagreeing about which docs are
    hand-authored is the CONVENTIONS §2 defect, and it would show up as one gate reddening a corpus the
    other one has never seen. A failed import is a boundary, never a local fallback."""
    path = script_path("check_doc_size.py", __file__)
    spec = importlib.util.spec_from_file_location("check_doc_size_for_role_docs", path)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
        return mod.walk_docs, mod.GENERATED_SUFFIX, str(path.relative_to(ROOT))
    except Exception as exc:                        # a sibling that will not load is not a corpus
        raise ToolError("cannot load the hand-authored-docs derivation from %s (%s) — refusing to "
                        "invent a second definition of the same corpus"
                        % (path.relative_to(ROOT) if path else "scripts/gate/check_doc_size.py",
                           exc)) from None


# ---------------------------------------------------------------- the derived sets

def discover_roles(root: Path) -> list[str]:
    """The role set: every directory one level under IaC/ansible/roles/. Nothing else — no list here,
    no list in a var file, so a new role is a new fact the gate reads the moment it appears."""
    roles = root / ROLES_REL
    if not roles.is_dir():
        raise ToolError("%s/ is not a directory — with no role tree there is nothing to prove named, "
                        "and an empty set would read as a clean fleet" % ROLES_REL)
    return sorted(p.name for p in roles.iterdir() if p.is_dir() and not p.name.startswith("."))


def read_docs(root: Path) -> tuple[dict, dict]:
    """({relpath: text}, {relpath: why it did not read}) for the hand-authored docs."""
    walk, _suffix, _origin = load_doc_walk()
    texts: dict[str, str] = {}
    unreadable: dict[str, str] = {}
    try:
        paths = walk(root)
    except Exception as exc:            # the sibling gate raises ITS boundary class, not mine
        raise ToolError("the hand-authored-docs walk refused: %s" % exc) from None
    for rel in paths:
        try:
            texts[rel] = (root / rel).read_bytes().decode("utf-8")
        except (UnicodeDecodeError, OSError) as exc:
            unreadable[rel] = "%s: unreadable (%s), so it cannot be shown to name any role" % (rel, exc)
    return texts, unreadable


# ---------------------------------------------------------------- the mention test

def token_re(name: str) -> re.Pattern:
    """One role name as a TOKEN, not a substring. The boundaries are the rule:
      * `spark` must NOT match inside `spark-llm-profile` (both neighbours blocked),
      * `roles/<name>/tasks/main.yml` MUST match (`/` is not a boundary char on either side),
      * `network-vpn.md` and `common.yml` must NOT match the roles `network` and `common` — a file
        name is not a role name, which is why `.` is blocked on both sides.
    Case-insensitive, because a doc may capitalise a name it means; the SHAPE test below is what
    separates a mention from an English word, not the spelling."""
    return re.compile(r"(?<![A-Za-z0-9_.\-])" + re.escape(name) + r"(?![A-Za-z0-9_.\-])", re.I)


def occurrences(text: str, name: str) -> list[tuple[int, tuple, str]]:
    """`[(line, shapes, the line as written)]` for one role in one doc, fenced blocks tracked.

    A name inside a fenced block is a code shape: docs quote `roles:` blocks and directory trees, and
    that quoting IS a reference to the role."""
    rx = token_re(name)
    lines = text.split("\n")
    in_code: list[bool] = []
    fenced = False
    for ln in lines:
        if FENCE_RE.match(ln):
            fenced = not fenced
            in_code.append(True)
            continue
        in_code.append(fenced)
    out = []
    for n, ln in enumerate(lines, 1):
        for m in rx.finditer(ln):
            shapes = []
            before = ln[:m.start()]
            if re.search(r"(?:^|[\s`(=\\[{}|\"'])roles/$", before) or ln[m.end():m.end() + 1] == "/":
                shapes.append("path")
            if in_code[n - 1] or before.count("`") % 2 == 1:
                shapes.append("code")
            if ln.lstrip().startswith("|") and m.group(0).lower() in [c.strip().lower() for c in
                                                                      ln.split("|")]:
                shapes.append("cell")
            if re.search(r"^\s*-\s+" + re.escape(name) + r"\s*(?:\{\{[^}]*\}\})?\s*(?:#.*)?$", ln, re.I) \
                    or re.search(r"(?:role|roles)\s*:\s*(?:\[[^\]]*)?$", before, re.I) \
                    or re.search(r"(?:^|[,\s\[])role:\s*$", before, re.I):
                shapes.append("entry")
            out.append((n, tuple(shapes) or ("incidental",), ln.strip()[:90]))
    return out


def scan(roles: list[str], docs: dict, unreadable=()) -> tuple[list, dict]:
    """The verdict, pure over (role names, {doc: text}) so --self-test needs no repo. Returns
    (findings, stats). Every number in stats is derived here and printed, never typed (CONVENTIONS §2)."""
    findings: list[str] = []
    per_role: dict[str, dict] = {}
    for role in roles:
        own: list[str] = []
        inc: list[str] = []
        own_docs: set[str] = set()
        inc_docs: set[str] = set()
        for rel in sorted(docs):
            for line, shapes, text in occurrences(docs[rel], role):
                site = "%s:%d" % (rel, line)
                if "incidental" in shapes:
                    inc.append("%s %s" % (site, text))
                    inc_docs.add(rel)
                if [s for s in shapes if s != "incidental"]:
                    own.append("%s %s" % (site, "+".join(s for s in shapes if s != "incidental")))
                    own_docs.add(rel)
        per_role[role] = {"own": own, "inc": inc, "own_docs": sorted(own_docs),
                          "inc_docs": sorted(inc_docs)}
        if own:
            continue
        if inc:
            more = "" if len(inc) <= MAX_PRINTED else ", … %d more" % (len(inc) - MAX_PRINTED)
            findings.append(
                "FAIL: role %s: undocumented — no hand-authored doc NAMES it. The string occurs in %d "
                "incidental site(s) across %d doc(s): %s%s — and an English word that happens to appear "
                "is not a mention of the role. Name the role where you meant it: a `roles/%s` path, a "
                "code span, a catalogue cell, or prose about the role itself"
                % (role, len(inc), len(inc_docs), "; ".join(inc[:MAX_PRINTED]), more, role))
        else:
            findings.append(
                "FAIL: role %s: undocumented — the name occurs in NO hand-authored docs/*.md, so this "
                "role ships with nothing that says why it exists, what it must never do, or how it "
                "fails. Write or link the owning doc (`docs/index.md` is the map); the role set is "
                "derived from %s/, so this finding disappears when a doc names it"
                % (role, ROLES_REL))
    for rel in sorted(unreadable):
        findings.append("FAIL: %s" % unreadable[rel])
    stats = {"roles": len(roles),
             "owning": sum(len(p["own"]) for p in per_role.values()),
             "incidental": sum(len(p["inc"]) for p in per_role.values()),
             "docs": len(docs),
             "gaps": len([r for r in roles if not per_role[r]["own"]]),
             "per_role": per_role}
    return findings, stats


# ---------------------------------------------------------------- the verdict

def report(roles: list[str], docs: dict, unreadable=(), verbose: bool = False,
           role_floor: int = ROLE_FLOOR, doc_floor: int = DOC_FLOOR, origin: str = "") -> int:
    if not roles:
        print("CANNOT RUN: %s/ yielded no role directories. That is a broken walk or a wrong root, "
              "not a documented fleet — an empty set satisfies every one-way rule (HD-1118 Stage 1)."
              % ROLES_REL)
        return 2
    if not docs and not unreadable:
        print("CANNOT RUN: no hand-authored docs/*.md were read, so nothing could count as a mention "
              "and every role would be reported undocumented by a broken walk rather than by a real "
              "gap.")
        return 2
    require_corpus(len(roles), role_floor, "check_role_docs walked %s/" % ROLES_REL)
    require_corpus(len(docs) + len(unreadable), doc_floor,
                   "check_role_docs read hand-authored docs/*.md")
    findings, stats = scan(roles, docs, unreadable)
    print("corpus: %d role dir(s) under %s%s, %d hand-authored docs/*.md"
          % (stats["roles"], ROLES_REL, (" (derived from this tree)" if origin else ""), stats["docs"]))
    for line in findings:
        print(line)
    if findings:
        print("\n%d undocumented role(s) of %d. The role set is DERIVED from the directory listing, so "
              "the fix is never a list in a script — it is the doc."
              % (stats["gaps"], stats["roles"]))
        return 1
    if verbose:
        for role in sorted(stats["per_role"]):
            p = stats["per_role"][role]
            print("  %-24s %s" % (role, ", ".join(p["own_docs"])
                                  or "(no owning mention)"))
            for site in p["own"][:3]:
                print("      %s" % site)
            if p["inc"] and not p["own"]:
                print("      incidental only: %d site(s)" % len(p["inc"]))
    print("OK: %d role dir(s) under %s, each named by >=1 hand-authored docs/*.md — %d owning "
          "mention(s), %d incidental, %d gap(s)"
          % (stats["roles"], ROLES_REL, stats["owning"], stats["incidental"], stats["gaps"]))
    return 0


# ---------------------------------------------------------------- self-test

def _tree(tmp: Path, roles: list[str], docs: dict) -> Path:
    """A throwaway repo: role DIRECTORIES and docs. Breeding a role here is how the derived set is
    proved derived — the script never sees a role name until the tree contains one."""
    for role in roles:
        (tmp / ROLES_REL / role / "tasks").mkdir(parents=True, exist_ok=True)
        (tmp / ROLES_REL / role / "tasks" / "main.yml").write_text("---\n- name: x\n  debug: {}\n",
                                                                   encoding="utf-8")
    for rel, text in docs.items():
        (tmp / rel).parent.mkdir(parents=True, exist_ok=True)
        (tmp / rel).write_text(text, encoding="utf-8")
    return tmp


DOC_OK = """---
domain: deployment
role: detail
---
# Roles

| role | owns |
|---|---|
| alpha | the alpha thing |

`beta` is applied by the playbook, see `roles/gamma/tasks/main.yml`.
The spark pair is `spark` plus `spark-llm-profile`; `docker_services` owns the compose dirs.
"""
DOC_PROSE_ONLY = """# Notes

The gamma role is not named here, only the word gamma in a sentence, and gamma.yml is a file.
"""


def self_test() -> int:
    """Each rule bred in a temp tree, then reverted and required to go quiet. The arms ARE the contract:
    a gate that lists its roles in a string has no canary that can breed one, and a gate that counts any
    occurrence has no arm that can tell a mention from an English word."""
    fails = 0

    def arm(label: str, ok: bool, detail: str = "") -> None:
        nonlocal fails
        fails += not ok
        print("  arm %-78s %s%s" % (label, "ok" if ok else "FAIL",
                                    (" — " + detail) if (detail and not ok) else ""))

    def run(root: Path, verbose: bool = False, role_floor: int = 0, doc_floor: int = 0) -> tuple:
        buf = StringIO()
        try:
            with redirect_stdout(buf):
                docs, unreadable = read_docs(root)
                rc = report(discover_roles(root), docs, unreadable, verbose=verbose,
                            role_floor=role_floor, doc_floor=doc_floor)
        except ToolError as exc:
            return 2, str(exc)
        except SystemExit as exc:            # a floor's refusal is a verdict of its own, not a crash
            return 3, str(exc)
        return rc, buf.getvalue()

    roles = ["alpha", "beta", "gamma", "spark", "spark-llm-profile", "docker_services"]

    with tempfile.TemporaryDirectory(prefix="check-role-docs-") as td:
        tmp = Path(td)

        # (a) The derived set, proved in BOTH directions by touching the tree and nothing else.
        t = _tree(tmp / "a-all", roles, {"docs/x.md": DOC_OK})
        rc, out = run(t)
        arm("(a) every role named by the tree's docs is GREEN, and the OK line counts what it walked",
            rc == 0 and "6 role dir(s)" in out and "0 gap(s)" in out, "rc %d: %s" % (rc, out[-260:]))
        t = _tree(tmp / "a-new", roles + ["undocumented_role"], {"docs/x.md": DOC_OK})
        rc, out = run(t)
        arm("(a) breeding an UNDOCUMENTED ROLE in a temp tree REDDENS and names the role",
            rc == 1 and "undocumented" in out and "undocumented_role" in out,
            "rc %d: %s" % (rc, out[-260:]))
        t = _tree(tmp / "a-gone", roles[:3], {"docs/x.md": DOC_OK})
        rc, out = run(t)
        arm("(a) and deleting a role dir REMOVES it from the rule with no edit to this script — the "
            "set is derived, not listed", rc == 0 and "3 role dir(s)" in out,
            "rc %d: %s" % (rc, out[-200:]))

        # (b) Owning versus incidental, both arms on the SAME word.
        t = _tree(tmp / "b-prose", ["gamma"], {"docs/x.md": DOC_PROSE_ONLY})
        rc, out = run(t)
        arm("(b) a role that appears ONLY as an English word in prose REDDENS — a word is not a mention",
            rc == 1 and "incidental" in out and "gamma" in out, "rc %d: %s" % (rc, out[-260:]))
        arm("(b) and the finding names the docs that carry the incidental sites, so the reader can see "
            "the difference", "docs/x.md:" in out, out[-200:])
        t = _tree(tmp / "b-named", ["gamma"], {"docs/x.md": DOC_PROSE_ONLY + "\nNow `gamma` names it.\n"})
        rc, out = run(t)
        arm("(b) the same doc with ONE code-font mention is GREEN — the shape test, not the count",
            rc == 0, "rc %d: %s" % (rc, out[-260:]))

        # (c) The token boundary: which strings are the role's name.
        edge = [
            ("roles/gamma/tasks/main.yml", ["gamma"], 0, "a path into the role"),
            ("see `spark-llm-profile` refuses", ["spark", "spark-llm-profile"], 1,
             "`spark` may not match inside `spark-llm-profile`"),
            ("the `docker_services` role", ["docker_services"], 0, "an underscore name"),
            ("docs/network-vpn.md and common.yml", ["network", "common"], 2,
             "a file name is not a role name"),
        ]
        for text, named, want_gaps, why in edge:
            t = _tree(tmp / ("c" + why[:8].replace(" ", "")), named, {"docs/e.md": text + "\n"})
            rc, out = run(t)
            arm("(c) %-52s → %s" % (why, "green" if want_gaps == 0 else "%d gap(s)" % want_gaps),
                (rc == 0 if want_gaps == 0 else rc == 1 and out.count("FAIL: role") == want_gaps),
                "rc %d: %s" % (rc, out[-160:]))

        # (d) A render view is not an author.
        other = "# Other\n\nA hand-authored doc that says nothing about the delta role.\n"
        t = _tree(tmp / "d-gen", ["delta"], {"docs/view-generated.md": "roles/delta\n`delta`\n",
                                            "docs/other.md": other})
        rc, out = run(t)
        arm("(d) a role named ONLY by a `docs/*-generated.md` render view is UNDOCUMENTED — the renderer"
            " is the thing whose doc is in question (§8.2, §8.5)",
            rc == 1 and "delta" in out, "rc %d: %s" % (rc, out[-200:]))
        t = _tree(tmp / "d-hand", ["delta"], {"docs/view.md": "roles/delta\n`delta`\n",
                                             "docs/other.md": other})
        rc, out = run(t)
        arm("(d) the same bytes in a HAND-AUTHORED doc are GREEN — the exemption is about authorship, "
            "not content", rc == 0, "rc %d: %s" % (rc, out[-200:]))
        t = _tree(tmp / "d-count", ["delta"], {"docs/view-generated.md": "roles/delta\n",
                                              "docs/other.md": other})
        rc, out = run(t)
        arm("(d) the render view never enters the corpus the run counts — the OK/cannot-run line reads "
            "1 hand-authored doc, not 2", "1 hand-authored docs/*.md" in out, out[:160])

        # (e) Fail-closed boundaries: none of these may print OK.
        empty = tmp / "e-empty"
        (empty / ROLES_REL).mkdir(parents=True)
        (empty / "docs").mkdir()
        rc, out = run(empty)
        arm("(e) MUST NOT BE GREEN ON AN EMPTY CORPUS: no roles and no docs is rc 2, never OK",
            rc == 2 and "CANNOT RUN" in out, "rc %d: %s" % (rc, out[:160]))
        t = _tree(tmp / "e-docs", ["alpha"], {})
        (t / "docs").mkdir(exist_ok=True)
        rc, out = run(t)
        arm("(e) a role tree with NO hand-authored docs is rc 2, not 'every role is undocumented'",
            rc == 2 and "CANNOT RUN" in out, "rc %d: %s" % (rc, out[:160]))
        no_roles = tmp / "e-roles"
        (no_roles / "docs").mkdir(parents=True)
        rc, out = run(no_roles)
        arm("(e) a missing %s/ is rc 2 — an empty set would satisfy the rule silently" % ROLES_REL,
            rc == 2 and "is not a directory" in out, "rc %d: %s" % (rc, out[:160]))
        for n, expect in ((ROLE_FLOOR, True), (ROLE_FLOOR + 1, False)):
            refused = None
            try:
                require_corpus(n, ROLE_FLOOR, "role dirs")
            except SystemExit as exc:
                refused = str(exc)
            arm("(e) the role floor bites at exactly %d dir(s)%s" % (n, ", one more passes"
                                                                    if not expect else ""),
                bool(refused) == expect, refused or "passed")

        # (f) This checkout, read the honest way: the numbers the run derives, never quoted from here.
        rc, out = run(ROOT, role_floor=ROLE_FLOOR, doc_floor=DOC_FLOOR)
        n_roles = len(discover_roles(ROOT))
        arm("(f) this tree reads GREEN at its real floors and the run prints the role count it derived "
            "(%d dir(s))" % n_roles, rc == 0 and ("%d role dir(s)" % n_roles) in out and n_roles >
            ROLE_FLOOR, "rc %d: %s" % (rc, out[-200:]))
        arm("(f) and the floor is not propped up by a stale number: the derived set is what the tree "
            "holds, never a list in this file",
            not re.search(r"^[A-Z_]+\s*=\s*\[\s*[\"']", Path(__file__).read_text(encoding="utf-8"),
                          re.M), "a role list appeared in the source")

    if fails:
        print("FAIL: self-test — %d arm(s) did not behave" % fails)
        return 1
    print("OK: self-test — the role set is proved derived in both directions by touching only the "
          "tree, an undocumented role reddens, a prose-only mention reddens with its sites named while "
          "one code-font mention clears it, the token boundary refuses a neighbour role's name and a "
          "file name, a render view cannot document a role its own bytes describe, and an empty corpus, "
          "a missing role tree, a doc-less tree and a below-floor walk all refuse to print OK")
    return 0


# ---------------------------------------------------------------- driver

def main() -> int:
    ap = argparse.ArgumentParser(
        prog="check_role_docs.py",
        description="Every directory under IaC/ansible/roles/ must be named by at least one "
                    "hand-authored docs/*.md. The role set is derived from the tree; the doc set is "
                    "derived from the corpus check_doc_size.py seals. Read-only.",
        epilog="exit 0 every role named · 1 undocumented role(s) · 2 could not run")
    ap.add_argument("--verbose", action="store_true",
                    help="print each role with the docs that name it and its owning sites")
    ap.add_argument("--self-test", action="store_true", help="breed each defect in a temp tree")
    args = ap.parse_args()

    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
        except (AttributeError, ValueError):
            pass

    if args.self_test:
        return self_test()
    try:
        roles = discover_roles(ROOT)
        docs, unreadable = read_docs(ROOT)
    except ToolError as exc:
        print("CANNOT RUN: %s" % exc, file=sys.stderr)
        return 2
    try:
        return report(roles, docs, unreadable, verbose=args.verbose)
    except SystemExit as exc:          # require_corpus's own refusal — a boundary, printed by lib
        print("CANNOT RUN: %s" % exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
