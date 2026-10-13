#!/usr/bin/env python3
"""check_tag_coverage.py — a task reachable only through a dynamic include must be selectable (HD-1149).

WHY. `ansible-playbook --tags X` does NOT evaluate tags top-down the way a playbook reads. A DYNAMIC
include (`include_tasks`, `include_role`) is itself a task, and a filter that does not select it means
the file is never opened — the children below it are never even PARSED, so nothing about their tags can
be considered, and the recap still reads `failed=0`. A filtered converge can execute a fraction of an
included file and report green, changed=0. Tonight's audit commits (`0b42ce2c`, `55107dca`, `b7dc0c6f`)
fixed live instances of it; this file is the enforcement half, so the class cannot come back on the
next include line nobody thought about.

THE FOUR RULES — measured, not recalled, with `ansible-playbook -i localhost, -c local` over a
debug-only lab that ships with this gate (`scripts/testdata/check_tag_coverage/`, run `run.sh`):

  1. CASCADE. A tag on a playbook `roles:` entry reaches EVERY task of that role, including the ones
     inside a dynamic include, even when neither the include nor the child carries a tag. Measured:
     role pulled `{role: r1, tags: [t1]}`, `include_tasks: sub.yml` untagged, child untagged →
     `--tags t1` ran the child.
  2. AN INCLUDE TAG ONLY GATES LOADING. A tag on the `include_tasks` statement decides whether the
     FILE loads; the children are then filtered on their OWN tags. Measured: include tagged `t2`, one
     child untagged + one child tagged `t2` → `--tags t2` ran the tagged child and the untagged one
     never appeared in the output at all. Green, and silently absent.
  3. AN UNTAGGED INCLUDE IS DEAD UNDER ANY FILTER. Once `--tags` is in play an untagged dynamic
     include is never expanded — not for its `tags: always` children either, because `always` can only
     rescue a task that was parsed. Measured: `--tags always` ran an `always` task at the top of
     main.yml and NOT the `always` task one untagged include below it.
  4. A STATIC IMPORT INHERITS. `import_tasks` is expanded at parse time, so its children inherit the
     import statement's tags — rule 1's shape. Tagging them is unnecessary and this gate does not ask.

WHAT IS DECIDED for each statement, with

  cascade  = the tags on the playbook `roles:` entries that pull the role        (rule 1)
  own      = the tags written on the statement/block itself
  inh      = what the parser hands down without asking: cascade ∪ enclosing blocks ∪ static imports
  gate     = own ∪ inh of one dynamic include; LOAD = the intersection along the include path
  A  gate empty                    → the file never loads under any filter            (rule 3)
  B  a task's own_eff ∖ LOAD ≠ ∅    → that tag alone never opens the file, so the task silently
                                      does not run                                     (rules 2, 3)
  C  a task's own_eff is empty      → no filter can select it, while an unfiltered run can (rule 2)
  Static `import_tasks`/`import_role` children are exempt from A and their tags pass down through
  `inh`, because rule 4 says inheritance already holds. `always` in a task's tags satisfies B and C —
  it is the documented wildcard; whether the FILE holding it can load is rule A's question, asked
  separately and about the include line, which is where the fix belongs.

Output names the role, the include line, the file and the offending task, so the fix is a tag and not
an investigation.

Run:   python3 scripts/gate/check_tag_coverage.py [--root DIR] [--iac DIR] [--show]
       python3 scripts/gate/check_tag_coverage.py --self-test
Exit:  0 = coverage holds · 1 = finding(s), including a file the gate could not read · 2 = could not
run (no IaC tree — a silent 0 there would read as "checked everything, found nothing"). Stdlib +
PyYAML only, no network, no ansible, deterministic ordering.

STATUS: authored and self-tested for HD-1149, NOT registered in scripts/validate-all.sh — the
`item_q` line is the owner's checkpoint.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import root as _hl_root  # noqa: E402

try:
    import yaml
except ImportError as exc:  # fail loud, never silently skip (CONVENTIONS §6)
    print(f"FAIL: PyYAML is required (it ships with ansible in ~/ansible-venv): {exc}", file=sys.stderr)
    sys.exit(2)

ROOT = _hl_root(__file__)
IAC = "IaC/ansible"
ROLES = "roles"
PLAYBOOKS = "playbooks"
SELF = "check_tag_coverage.py"

# Dynamic: expanded at RUN time, so the filter decides whether the file is opened at all.
DYNAMIC_TASK = {"include_tasks", "ansible.builtin.include_tasks"}
DYNAMIC_ROLE = {"include_role", "ansible.builtin.include_role"}
# Static: expanded at PARSE time, so the children inherit (rule 4).
STATIC_TASK = {"import_tasks", "ansible.builtin.import_tasks"}
STATIC_ROLE = {"import_role", "ansible.builtin.import_role"}
INCLUDES = DYNAMIC_TASK | DYNAMIC_ROLE | STATIC_TASK | STATIC_ROLE

# Everything a task mapping can carry that is not its action. `_line` is this file's own marker
# (see `with_lines`) and must never be mistaken for a module name.
NOT_ACTION = {"name", "when", "tags", "vars", "block", "rescue", "always", "become", "become_user",
              "become_method", "become_flags", "become_exe", "register", "notify", "loop", "loop_control",
              "until", "retries", "delay", "poll", "delegate_to", "delegate_facts", "run_once",
              "ignore_errors", "ignore_unreachable", "failed_when", "changed_when", "check_mode",
              "diff", "throttle", "timeout", "environment", "no_log", "args", "connection",
              "any_errors_fatal", "listen", "module_defaults", "local", "action", "remote_user",
              "user", "password", "port", "host", "collections", "module", "_line"}

TEMPLATE = "{{"
# A tag written as a Jinja expression (`tags: "{{ svc.name }}"`) is a real tag at run time and an
# unknowable one at parse time. Calling it a miss would be a false positive on a per-service loop, so
# it is a WILDCARD that satisfies both a gate and a task — and it is counted, because coverage argued
# from a template is not a static guarantee.
WILDCARD = "*"
ALWAYS = "always"
MAX_DEPTH = 8


class GateError(Exception):
    """A file the gate must read cannot be read — reported loudly, never as a pass."""


# --------------------------------------------------------------------------- YAML reading ------
def _conv(node):
    """Compose-node tree → plain Python, remembering each mapping's start line."""
    if isinstance(node, yaml.MappingNode):
        out = {}
        for key_node, val_node in node.value:
            out[_conv(key_node)] = _conv(val_node)
        out["_line"] = node.start_mark.line + 1
        return out
    if isinstance(node, yaml.SequenceNode):
        return [_conv(c) for c in node.value]
    if isinstance(node, yaml.ScalarNode):
        return node.value
    return None


def load_yaml(path: Path):
    """Parse a file, keeping task line numbers. A parse error is a GateError, never a silent None."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise GateError(f"{path}: cannot read: {exc}") from exc
    try:
        docs = list(yaml.compose_all(text))
    except yaml.YAMLError as exc:
        raise GateError(f"{path}: not parseable YAML: {exc}") from exc
    if not docs:
        return None
    return _conv(docs[0])


def tags_of(task: dict):
    """Normalised tag set of one task/block/roles-entry mapping. None = the `tags:` key is absent."""
    if "tags" not in task:
        return None
    val = task["tags"]
    if val is None:
        return frozenset()
    if isinstance(val, str):
        return frozenset({WILDCARD if TEMPLATE in val else val.strip()})
    if isinstance(val, list):
        out = set()
        for v in val:
            if isinstance(v, str):
                out.add(WILDCARD if TEMPLATE in v else v.strip())
            else:
                out.add(WILDCARD)
        return frozenset(out)
    return frozenset({WILDCARD})


def action_of(task: dict):
    """(module, value) for the single action a task carries; None for a block or a shorthand entry."""
    for key, val in task.items():
        if key in NOT_ACTION or str(key).startswith("with_"):
            continue
        return str(key), val
    return None, None


def include_kind(action):
    if action in DYNAMIC_TASK or action in DYNAMIC_ROLE:
        return "dynamic"
    if action in STATIC_TASK or action in STATIC_ROLE:
        return "static"
    return None


def include_target(action, value):
    """('file', path) | ('role', name, tasks_from) | ('unknown', why)."""
    if include_kind(action) is None:
        return ("unknown", "not an include")
    if action in DYNAMIC_TASK or action in STATIC_TASK:
        if isinstance(value, str):
            return ("file", value)
        if isinstance(value, dict):
            return ("file", str(value.get("file") or value.get("_raw_params") or ""))
        return ("unknown", "unreadable include target")
    if isinstance(value, str):
        return ("role", value, "main")
    if isinstance(value, dict):
        return ("role", str(value.get("name") or value.get("role") or ""),
                str(value.get("tasks_from") or "main"))
    return ("unknown", "unreadable include_role target")


def rel(root: Path, path: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return str(path)


# ------------------------------------------------------------------------------ the walk -------
def _fmt_chain(chain) -> str:
    return " -> ".join(chain)


class Findings:
    """SITES FIRST, VERDICTS AFTER.

    One task file is reached by several paths — two playbooks, or a pre-pass include and a per-service
    loop — and a task is covered when ANY path delivers its tag. Judging each walk separately made a
    task reached both by a `tags: [docker_services, secrets]` include and by a loop include reading as
    unreachable, which is wrong: one invocation does reach it. So the walk records what each path
    delivers and the verdict is taken over the union — with the paths where it does NOT reach named in
    the message, because "covered in vps.yml, dead in storage.yml" is the finding worth reading."""

    def __init__(self):
        self.items: set[str] = set()
        self.unreadable: set[str] = set()
        self.stats = {"roles": 0, "refs": 0, "files": 0, "tasks": 0, "dynamic": 0, "static": 0,
                      "wildcard_tags": 0, "unresolved": 0}
        self.includes: dict[tuple, dict] = {}
        self.tasksites: dict[tuple, dict] = {}

    def count(self, key: str, n: int = 1) -> None:
        self.stats[key] = self.stats.get(key, 0) + n

    def include_site(self, role, loc, action) -> dict:
        return self.includes.setdefault((role, loc), {
            "role": role, "loc": loc, "action": action, "ok": set(), "bad": set(),
            "no_tag": set(), "disjoint": set()})

    def task_site(self, role, loc, name) -> dict:
        return self.tasksites.setdefault((role, loc, name), {
            "role": role, "loc": loc, "name": name, "own": frozenset(), "inh": frozenset(),
            "loads": frozenset(), "unconstrained": False, "wild_load": False, "paths": set()})

    # -- verdicts, taken over every path that reached the site --------------------------------
    def emit(self) -> None:
        for key in sorted(self.includes):
            s = self.includes[key]
            if not s["bad"]:
                continue
            ctx = ", ".join(sorted(s["bad"]))
            covered = ", ".join(sorted(s["ok"]))
            if s["no_tag"]:
                why = (f"the include carries no tag and {' or '.join(sorted(s['no_tag']))} pull the "
                       "role with no role-level tag either, so under ANY --tags filter from those "
                       "playbooks the file is never opened and nothing inside it can match — not "
                       "even `always` (rule 3)")
            else:
                why = (f"its tags are disjoint from the tags that open the file it sits in "
                       f"({' | '.join(sorted(s['disjoint'])[:2])}), so no single --tags filter can "
                       "reach this file (rule 3 on the second hop)")
            if covered:
                why += f" (it does load under {covered})"
            self.items.add(f"A DEAD INCLUDE {s['role']}: {s['loc']} — {why}\n"
                           "        fix: put a tag the filtered run actually uses on this include "
                           "line, or on the roles: entry that pulls the role")
        for key in sorted(self.tasksites):
            s = self.tasksites[key]
            if s["unconstrained"] or s["wild_load"]:
                continue    # reachable without a gate, or gated only by a templated tag
            own_eff = s["own"] | s["inh"]
            if WILDCARD in own_eff or ALWAYS in own_eff:
                continue    # a templated tag or the documented `always` wildcard
            if not own_eff:
                self.items.add(
                    f"C UNTAGGED CHILD {s['role']}: {s['loc']} `{s['name']}` — an untagged task "
                    f"below a dynamic include (reached via {'; '.join(sorted(s['paths'])[:4])}), so "
                    "every --tags run skips it while the recap stays green (rule 2)\n"
                    "        fix: tag the task with the tag the include carries, or tag the "
                    "roles: entry")
                continue
            missing = own_eff - s["loads"]
            if missing:
                self.items.add(
                    f"B TAG NEVER LOADS THE FILE {s['role']}: {s['loc']} `{s['name']}` — "
                    f"tag{'s' if len(missing) > 1 else ''} {', '.join(sorted(missing))} "
                    f"{'names' if len(missing) == 1 else 'name'} this task, but no include on any "
                    "path to it carries "
                    f"{'it' if len(missing) == 1 else 'them'}, so `--tags <that tag>` never opens the "
                    "file and this task silently does not run (rules 2, 3). Reached via: "
                    f"{'; '.join(sorted(s['paths'])[:4])}\n"
                    "        fix: add the tag to the include line, or to the roles: entry that "
                    "pulls the role")


class Walker:
    def __init__(self, iac: Path, f: Findings):
        self.iac = iac
        self.roles = iac / ROLES
        self.f = f

    def from_playbooks(self, refs) -> None:
        mains = {p.parent.parent.name: p for p in sorted(self.roles.glob("*/tasks/main.yml"))}
        self.f.stats["roles"] = len(mains)
        by_role: dict[str, dict[frozenset, list[str]]] = {}
        for pb, role, tags in refs:
            by_role.setdefault(role, {}).setdefault(frozenset(tags), []).append(rel(self.iac, pb))
        for role in sorted(by_role):
            main = mains.get(role)
            if main is None:
                continue        # a role with no tasks/main.yml has no include to cover
            self.f.count("refs", sum(len(v) for v in by_role[role].values()))
            # One walk per distinct role-entry tag SET — the verdict depends on the set, not on which
            # playbook carried it — with every playbook named, because "tagged in vps.yml and bare in
            # storage.yml" is exactly what a reader has to see.
            for cascade in sorted(by_role[role], key=lambda s: sorted(s)):
                ctx = ", ".join(sorted(set(by_role[role][cascade])))
                self.file(main, role, frozenset(cascade), None, [ctx], [], 0)

    def file(self, path: Path, role, inh, load, chain, stack, depth) -> None:
        if depth > MAX_DEPTH:
            self.f.unreadable.add(f"{rel(self.iac, path)}: include chain deeper than {MAX_DEPTH}")
            return
        if path in stack:
            return      # a file that includes itself: the line is already reported by its own edge
        try:
            doc = load_yaml(path)
        except GateError as exc:
            self.f.unreadable.add(str(exc))
            return
        self.f.count("files")
        if isinstance(doc, list):
            self.tasks(doc, path, role, inh, load, chain, stack + [path], depth)

    def tasks(self, nodes, path, role, inh, load, chain, stack, depth) -> None:
        for item in nodes:
            if isinstance(item, dict):
                self.task(item, path, role, inh, load, chain, stack, depth)

    def task(self, task, path, role, inh, load, chain, stack, depth) -> None:
        own = tags_of(task) or frozenset()
        if WILDCARD in own:
            self.f.count("wildcard_tags")
        self.f.count("tasks")
        line = task.get("_line", "?")
        action, value = action_of(task)
        kind = include_kind(action)

        # A block hands its tags down to its children the way a static import does — statically, at
        # parse time — so they join `inh` rather than a child's `own`, and they join the block's gate.
        block_inh = inh | own
        for key in ("block", "rescue", "always"):
            if isinstance(task.get(key), list):
                self.tasks(task[key], path, role, block_inh, load, chain, stack, depth)

        loc = f"{rel(self.iac, path)}:{line}"
        if kind is None:
            name = str(task.get("name", "(unnamed task)"))
            site = self.f.tasksites.get((role, loc, name))
            if site is None and load is None:
                return      # nothing dynamic above it: this gate is not about ordinary tasks
            if site is None:
                site = self.f.task_site(role, loc, name)
            site["own"] |= own
            site["inh"] |= inh
            if load is None or WILDCARD in load:
                site["unconstrained"] = site["unconstrained"] or load is None
                site["wild_load"] = site["wild_load"] or (load is not None and WILDCARD in load)
            else:
                site["loads"] |= load
            site["paths"].add(_fmt_chain(chain))
            return

        self.f.count("dynamic" if kind == "dynamic" else "static")
        gate = own | inh
        if kind == "dynamic":
            reachable = intersect(load, gate)
            site = self.f.include_site(role, loc, action)
            (site["ok"] if reachable else site["bad"]).add(_fmt_chain(chain))
            if not gate:
                site["no_tag"].add(_fmt_chain(chain))
            elif not reachable:
                site["disjoint"].add(_fmt_chain(chain))
            child_load, child_inh = reachable, inh
        else:
            # Parsed already: no gate can close on a static import (rule 4), and its tags are
            # inherited by everything in the imported file.
            child_load, child_inh = load, inh | own
        self.enter(action, value, path, role, loc, child_inh, child_load, chain, stack, depth)

    def enter(self, action, value, path, role, loc, inh, load, chain, stack, depth) -> None:
        target = include_target(action, value)
        sub_chain = chain + [f"{rel(self.iac, path)}:{loc.split(':')[1]}"]
        if target[0] == "file":
            dest = resolve_file(path, target[1])
            if dest is None:
                if TEMPLATE in target[1]:
                    self.f.count("unresolved")
                    return
                self.f.unreadable.add(f"{rel(self.iac, path)}:{loc} includes {target[1]}, which "
                                      "does not exist")
                return
            self.file(dest, role, inh, load, sub_chain, stack, depth + 1)
        elif target[0] == "role":
            name, tasks_from = target[1], target[2]
            dest = self.roles / name / "tasks" / f"{tasks_from}.yml"
            if not dest.is_file():
                if TEMPLATE in name or TEMPLATE in tasks_from:
                    self.f.count("unresolved")
                    return
                self.f.unreadable.add(f"{rel(self.iac, path)}:{loc} includes role {name}:"
                                      f"{tasks_from}, which does not exist")
                return
            self.file(dest, name, inh, load, sub_chain, stack, depth + 1)


def resolve_file(from_file: Path, target: str):
    """`include_tasks: foo.yml` resolves against the INCLUDING file's directory."""
    cand = (from_file.parent / target.strip()).resolve()
    return cand if cand.is_file() else None


def intersect(a, b):
    """Intersection of two gates, with a templated tag as the wildcard it behaves like: a tag that
    matches every filter constrains nothing, so the other side is what survives."""
    if a is None:
        return b
    if b is None:
        return a
    if WILDCARD in a:
        return b
    if WILDCARD in b:
        return a
    return a & b


def playbook_refs(playbooks: list[Path]):
    """(playbook, role, tags) for every `roles:` entry. A bare role name is NOT a tag."""
    refs = []
    for pb in playbooks:
        doc = load_yaml(pb)
        if not isinstance(doc, list):
            continue
        for play in doc:
            if not isinstance(play, dict):
                continue
            for entry in play.get("roles") or []:
                if isinstance(entry, str):
                    refs.append((pb, entry, frozenset()))
                elif isinstance(entry, dict):
                    name = entry.get("role") or entry.get("name")
                    if name:
                        refs.append((pb, str(name), tags_of(entry) or frozenset()))
    return refs


def scan(iac: Path) -> Findings:
    playbooks = [p for p in [*(iac / PLAYBOOKS).glob("*.yml"), *(iac / PLAYBOOKS).glob("*.yaml"),
                             iac / "site.yml"] if p.is_file()]
    f = Findings()
    refs = playbook_refs(sorted(set(playbooks)))
    Walker(iac, f).from_playbooks(refs)
    f.emit()
    return f


def run(iac: Path, show: bool) -> int:
    iac = Path(iac)
    if not iac.is_dir():
        print(f"CANNOT RUN: {iac} is not a directory — there is no tree to read, and a silent 0 "
              "here would mean 'checked every include, found nothing'", file=sys.stderr)
        return 2
    if not (iac / ROLES).is_dir() or not (iac / PLAYBOOKS).is_dir():
        print(f"CANNOT RUN: {iac} has no {ROLES}/ or {PLAYBOOKS}/ — nothing to read (exit 2)",
              file=sys.stderr)
        return 2
    try:
        f = scan(iac)
    except GateError as exc:
        print(f"CANNOT RUN: {exc}", file=sys.stderr)
        return 2
    findings = sorted(f.items)
    for why in sorted(f.unreadable):
        print(f"UNREADABLE {why}")
    for item in findings:
        print(item)
    tally = {k: sum(1 for x in findings if x.startswith(k)) for k in "ABC"}
    print(f"tally: A dead includes {tally['A']} · B unreachable tags {tally['B']} · "
          f"C untagged children {tally['C']}")
    st = f.stats
    print(f"scanned {st['roles']} role(s) with tasks/main.yml, {st['refs']} playbook roles: "
          f"reference(s), {st['files']} task file(s), {st['tasks']} task/block(s), "
          f"{st['dynamic']} dynamic include(s), {st['static']} static import(s), "
          f"{st['wildcard_tags']} templated tag set(s), {st['unresolved']} unresolvable target(s)")
    if f.unreadable:
        print(f"FAIL: {len(f.unreadable)} file reference(s) the gate could not read — a file it "
              "cannot read cannot fail either, so that is a finding (CONVENTIONS §6)")
        return 1
    if findings:
        print(f"FAIL: {len(findings)} tag-coverage finding(s): a task under a dynamic include that "
              "no --tags filter can reach. Tag the task, the include line, or the roles: entry.")
        return 1
    if show:
        print(f"(show) tally above, over {st['dynamic']} dynamic include(s) under {iac}")
    print(f"OK: every task reachable through a dynamic include under {iac} is selectable by some tag")
    return 0


# --------------------------------------------------------------------------- self-test ---------
def _write(root: Path, files: dict) -> None:
    for relpath, text in files.items():
        p = root / relpath
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")


def _analyse(iac: Path) -> str:
    f = scan(iac)
    return "\n".join(sorted(f.items) + [f"UNREADABLE {u}" for u in sorted(f.unreadable)])


def _case(tmp: Path, name: str, files: dict, want: str | None) -> bool:
    """Plant one shape in a private temp tree and assert the verdict. `want=None` means 'must be
    green' — the positive controls matter as much as the reds, or a gate that reports everything
    would pass its own self-test."""
    iac = tmp / name.replace(" ", "_") / "IaC" / "ansible"
    _write(iac, files)
    got = _analyse(iac)
    hits = [l for l in got.splitlines() if l[:2] in ("A ", "B ", "C ") or l.startswith("UNREADABLE")]
    ok = (want in got) if want else not hits
    print(f"  {'ok  ' if ok else 'FAIL'}  {name}")
    if not ok:
        print("\n".join(f"        {l}" for l in got.splitlines()))
    return ok


def self_test() -> int:
    """Planted shapes in temp dirs — never the calling repo's IaC tree: a fixture that runs against
    the live tree passes by weather and fails by weather too."""
    ok = True
    tmp = Path(tempfile.mkdtemp(prefix="tag-coverage-selftest-"))
    try:
        cases = [
            ("untagged include with tagged children fails rule 3", {
                "playbooks/p.yml": "- hosts: t\n  roles:\n    - deadrole\n",
                "roles/deadrole/tasks/main.yml": "- name: inc\n  include_tasks: sub.yml\n",
                "roles/deadrole/tasks/sub.yml": "- name: child\n  debug: msg=1\n  tags: [x]\n"},
             "A DEAD INCLUDE"),
            ("tagged include with tagged children passes", {
                "playbooks/p.yml": "- hosts: t\n  roles:\n    - okrole\n",
                "roles/okrole/tasks/main.yml": "- name: inc\n  include_tasks: sub.yml\n  tags: [x]\n",
                "roles/okrole/tasks/sub.yml": "- name: child\n  debug: msg=1\n  tags: [x]\n"}, None),
            ("static import with untagged children passes rule 4", {
                "playbooks/p.yml": "- hosts: t\n  roles:\n    - statrole\n",
                "roles/statrole/tasks/main.yml": "- name: imp\n  import_tasks: sub.yml\n  tags: [x]\n",
                "roles/statrole/tasks/sub.yml": "- name: child\n  debug: msg=1\n"}, None),
            ("roles entry cascade covers untagged children rule 1", {
                "playbooks/p.yml": "- hosts: t\n  roles:\n    - role: cascrole\n      tags: [x]\n",
                "roles/cascrole/tasks/main.yml": "- name: inc\n  include_tasks: sub.yml\n",
                "roles/cascrole/tasks/sub.yml": "- name: child\n  debug: msg=1\n"}, None),
            ("untagged child under a tagged include fails rule 2", {
                "playbooks/p.yml": "- hosts: t\n  roles:\n    - crole\n",
                "roles/crole/tasks/main.yml": "- name: inc\n  include_tasks: sub.yml\n  tags: [x]\n",
                "roles/crole/tasks/sub.yml": "- name: child\n  debug: msg=1\n"}, "C UNTAGGED CHILD"),
            ("a child tag no gate carries fails rule 2 again", {
                "playbooks/p.yml": "- hosts: t\n  roles:\n    - brole\n",
                "roles/brole/tasks/main.yml": "- name: inc\n  include_tasks: sub.yml\n  tags: [x]\n",
                "roles/brole/tasks/sub.yml": "- name: child\n  debug: msg=1\n  tags: [y]\n"},
             "B TAG NEVER LOADS THE FILE"),
            ("an always child under an untagged include is still rule A", {
                "playbooks/p.yml": "- hosts: t\n  roles:\n    - arole\n",
                "roles/arole/tasks/main.yml": "- name: inc\n  include_tasks: sub.yml\n",
                "roles/arole/tasks/sub.yml": "- name: child\n  debug: msg=1\n  tags: [always]\n"},
             "A DEAD INCLUDE"),
            ("a nested dynamic include inherits the gate intersection", {
                "playbooks/p.yml": "- hosts: t\n  roles:\n    - nrole\n",
                "roles/nrole/tasks/main.yml": "- name: inc\n  include_tasks: a.yml\n  tags: [x]\n",
                "roles/nrole/tasks/a.yml": "- name: inc2\n  include_tasks: b.yml\n  tags: [x]\n",
                "roles/nrole/tasks/b.yml": "- name: child\n  debug: msg=1\n  tags: [x]\n"}, None),
            ("a nested include whose inner gate drops the tag fails", {
                "playbooks/p.yml": "- hosts: t\n  roles:\n    - nrole2\n",
                "roles/nrole2/tasks/main.yml": "- name: inc\n  include_tasks: a.yml\n  tags: [x]\n",
                "roles/nrole2/tasks/a.yml": "- name: inc2\n  include_tasks: b.yml\n  tags: [z]\n",
                "roles/nrole2/tasks/b.yml": "- name: child\n  debug: msg=1\n  tags: [x]\n"},
             "A DEAD INCLUDE"),
            ("a tagged block inside an included file covers its children", {
                "playbooks/p.yml": "- hosts: t\n  roles:\n    - brole2\n",
                "roles/brole2/tasks/main.yml": "- name: inc\n  include_tasks: sub.yml\n  tags: [x]\n",
                "roles/brole2/tasks/sub.yml":
                    "- name: blk\n  tags: [x]\n  block:\n    - name: child\n      debug: msg=1\n"},
             None),
            ("a templated tag is a wildcard, not a miss", {
                "playbooks/p.yml": "- hosts: t\n  roles:\n    - trole\n",
                "roles/trole/tasks/main.yml":
                    "- name: inc\n  include_tasks: sub.yml\n  tags: \"{{ svc.name }}\"\n",
                "roles/trole/tasks/sub.yml": "- name: child\n  debug: msg=1\n"}, None),
        ]
        for name, files, want in cases:
            if not _case(tmp, name, files, want):
                ok = False

        # The committed lab tree is COPIED into the temp dir and analysed there — the same shapes the
        # live run.sh proves with ansible, so the two witnesses must agree.
        src = ROOT / "scripts" / "testdata" / "check_tag_coverage" / "IaC" / "ansible"
        if src.is_dir():
            dst = tmp / "committed-lab" / "IaC" / "ansible"
            dst.parent.mkdir(parents=True)
            shutil.copytree(src, dst)
            got = _analyse(dst)
            for needle, why in [("A DEAD INCLUDE", "rule 3 (an untagged include pulled bare)"),
                                ("B TAG NEVER LOADS THE FILE", "rules 2/3 (a tag no gate carries)"),
                                ("C UNTAGGED CHILD", "rule 2 (an untagged child, no cascade)")]:
                if needle in got:
                    print(f"  ok    the committed lab still proves {why}")
                else:
                    print(f"  FAIL  the committed lab no longer proves {why}\n{got}")
                    ok = False
        else:
            print(f"  FAIL  the committed lab {src} is missing — the gate shipped without its fixture")
            ok = False

        # exit 2, not a silent 0: no tree means no verdict, and "OK: 0 findings" would be the mute
        # failure this repo has been burned by before.
        empty = tmp / "no-iac"
        empty.mkdir(parents=True)
        for label, path, want in [("a missing IaC tree exits 2", empty / "IaC" / "ansible", 2),
                                  ("a tree with no roles dir exits 2", empty / "half", 2)]:
            _write(empty / "half", {"playbooks/p.yml": "- hosts: t\n  roles: []\n"})
            rc = run(path, False)
            print(f"  {'ok  ' if rc == want else 'FAIL'}  {label} (got {rc})")
            ok = ok and rc == want

        # a tree with nothing to cover is green (the gate is not a tag-for-everything rule), and a
        # dangling include is LOUD rather than an empty pass.
        d = tmp / "nothing-to-cover"
        _write(d, {"IaC/ansible/roles/x/tasks/main.yml": "- name: t\n  debug: msg=1\n",
                   "IaC/ansible/playbooks/p.yml": "- hosts: t\n  roles:\n    - x\n"})
        rc = run(d / "IaC" / "ansible", False)
        print(f"  {'ok  ' if rc == 0 else 'FAIL'}  a tree with no dynamic includes is green (got {rc})")
        ok = ok and rc == 0

        d = tmp / "dangling-include"
        _write(d, {"IaC/ansible/roles/x/tasks/main.yml":
                   "- name: inc\n  include_tasks: nope.yml\n  tags: [x]\n",
                   "IaC/ansible/playbooks/p.yml": "- hosts: t\n  roles:\n    - x\n"})
        rc = run(d / "IaC" / "ansible", False)
        print(f"  {'ok  ' if rc == 1 else 'FAIL'}  an include target that does not exist fails (got {rc})")
        ok = ok and rc == 1
    finally:
        subprocess.run(["rm", "-rf", str(tmp)], check=False)
    if not ok:
        print("FAIL: check_tag_coverage.py self-test — at least one rule is not being enforced")
        return 1
    print("OK: self-test — each of the four cascade rules seen holding and seen failing when planted; "
          "a missing tree exits 2 and a dangling include turns the gate red")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog=SELF, description=__doc__.splitlines()[0])
    ap.add_argument("--root", type=Path, default=ROOT, help="repo root (default: the resolved one)")
    ap.add_argument("--iac", type=Path, default=None,
                    help="check this ansible tree instead of <root>/IaC/ansible (a fixture tree)")
    ap.add_argument("--show", action="store_true", help="extra tally output on a green run")
    ap.add_argument("--self-test", action="store_true", help="run the planted-shape canaries")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    return run(args.iac if args.iac else args.root / IAC, args.show)


if __name__ == "__main__":
    sys.exit(main())
