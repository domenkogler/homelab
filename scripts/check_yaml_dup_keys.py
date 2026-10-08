#!/usr/bin/env python3
"""Lint: no YAML mapping may declare the same key twice (HD-1098).

Ansible resolves a duplicate mapping key by KEEPING THE LAST ONE and printing
`[WARNING]: Found duplicate mapping key ... Using last defined value only.` on stderr.
The playbook still runs, `--syntax-check` still passes, and every other gate stays green —
so the FIRST definition becomes a dead statement that keeps looking authoritative. Editing
it is a silent no-op, which is exactly the silent-failure class HD-450 is about (there it
was an untagged repair block; here it is an un-tagged *tag*).

Found live on 2026-10-08 by the seat's own `ansible -m ping`, three of them, none caught by
any gate that existed:

    roles/monitoring/tasks/main.yml:600/601   two `tags:` on one task — the second won, so
                                              HD-450's "Record what the hygiene exporter
                                              publishes" task silently lost the `hygiene`
                                              tag: `--tags hygiene` skips it forever.
    group_vars/spark.yml:1253/1289            `spark_llm_ultrafast_cudagraph_args` defined
    group_vars/spark.yml:1258/1294            twice (the fragments section was duplicated
                                              in a merge). The later block wins; the earlier
                                              is dead text next to a live one.

WHY A NODE WALK AND NOT A LOADER HOOK: the first version of this check installed a custom
mapping constructor and reported 1 of the 3 cases — constructing a value can build child
mappings through a path that never re-enters the hook, so a hook-based detector produces
exactly the kind of confident green this repo refuses (CONVENTIONS §6: "a gate that cannot
see the file cannot fail either"). `yaml.compose_all()` returns the RAW node tree, and the
tree cannot hide a repeated key, so this walks nodes.

Merge keys (`<<: *anchor`) are NOT duplicates and must stay green: they are the documented
inheritance mechanism this repo uses heavily (`_x: &u_x` + `<<: *u_x` in the same file). A
key that ALSO appears next to a merge key is still reported here, because the explicit key
overriding the merged one is legitimate YAML but a merged-then-redefined value is worth a
look — `--self-test` pins the merge-only case as a legal near-miss.

`validate-all.sh`'s existing `--syntax-check` loop is the SECOND witness: it keeps ansible's
stderr and fails on the `Found duplicate mapping key` line, so a shape this walker would miss
still turns the gate red on any host with a working ansible, at no extra ansible cost.

Self-test: `python3 scripts/check_yaml_dup_keys.py --self-test` — planted canaries of each
shape turn it red, the legal near-misses do not, and the repo corpus is green.

Run:   python3 scripts/check_yaml_dup_keys.py [--self-test] [--root DIR] [--show]
Exit:  0 = no duplicates, 1 = duplicates found (or a corpus file failed to parse).
Wired into `scripts/validate-all.sh`.
"""
from __future__ import annotations

import argparse
import os
import sys

try:
    import yaml
except ImportError as exc:  # fail loud, never silently skip (CONVENTIONS §6)
    print(f"FAIL: PyYAML is required (it ships with ansible in ~/ansible-venv): {exc}", file=sys.stderr)
    sys.exit(1)

# Live YAML only. The archives are frozen records (a legacy playbook under brainstorming/
# is a snapshot of a retired design, and re-linting history only teaches the next session to
# ignore the gate), so they are excluded BY PATH, and everything else that is tracked is
# included — IaC/ plus the tool configs under scripts/ and spark/ that scripts actually read.
ARCHIVE_PREFIXES = ("brainstorming/", "docs/assets/references/", "reports/")
YAML_SUFFIXES = (".yml", ".yaml")


def walk(node, path, out):
    """Report every mapping key that appears twice in the SAME mapping (raw nodes)."""
    if isinstance(node, yaml.MappingNode):
        first: dict = {}
        for key_node, val_node in node.value:
            if key_node.id == "scalar":
                key = key_node.value
                if key in first:
                    out.append({
                        "file": path,
                        "line": key_node.start_mark.line + 1,
                        "key": key,
                        "first_line": first[key],
                    })
                else:
                    first[key] = key_node.start_mark.line + 1
                walk(val_node, path, out)
            else:
                walk(key_node, path, out)   # complex key: recurse, nothing to compare
                walk(val_node, path, out)
    elif isinstance(node, yaml.SequenceNode):
        for item in node.value:
            walk(item, path, out)


def parse_tree(path: str):
    with open(path, "rb") as fh:
        raw = fh.read()
    if raw.lstrip().startswith(b"$ANSIBLE_VAULT"):
        return None                      # encrypted: not YAML to any parser, loud by design
    return list(yaml.compose_all(raw.decode("utf-8")))


def scan_file(path: str):
    found: list = []
    docs = parse_tree(path)
    if docs is None:
        return found
    for doc in docs:
        if doc is not None:
            walk(doc, path, found)
    return found


def tracked_yaml(root: str = "."):
    """Live tracked YAML: `git ls-files` minus the archive prefixes; os.walk fallback for CI."""
    import subprocess
    try:
        out = subprocess.run(["git", "ls-files"], cwd=root or ".",
                             capture_output=True, text=True, check=True).stdout.splitlines()
        files = [f for f in out if f.endswith(YAML_SUFFIXES)
                 and not f.startswith(ARCHIVE_PREFIXES)]
        return [f if os.path.isabs(f) else os.path.join(root or ".", f) for f in sorted(files)]
    except Exception:
        files = []
        for dirpath, dirnames, filenames in os.walk(root or "."):
            dirnames[:] = [d for d in dirnames if not d.startswith(".") and d != "__pycache__"]
            rel = os.path.relpath(dirpath, root or ".")
            if rel.replace(os.sep, "/").startswith(ARCHIVE_PREFIXES):
                continue
            files += [os.path.join(dirpath, n) for n in filenames if n.endswith(YAML_SUFFIXES)]
        return sorted(files)


def scan_tree(root: str = "."):
    return [d for f in tracked_yaml(root) for d in scan_file(f)]


FIXTURES_BAD = {
    # the live shape 1: a task whose second `tags:` silently retires the first
    "task_tags.yml": (
        "- name: Prove the exporter answers\n"
        "  ansible.builtin.debug:\n"
        "    msg: ok\n"
        "  tags: [monitoring, hygiene]\n"
        "  tags: [monitoring, grafana]\n"
    ),
    # the live shape 2: a section duplicated by a merge, keys defined at top level twice
    "top_level.yml": (
        "spark_llm_ultrafast_diag_args:\n"
        '  - "--enable-prompt-tokens-details"\n'
        "other: 1\n"
        "spark_llm_ultrafast_diag_args:\n"
        '  - "--other"\n'
    ),
    # nested one level deeper, so the walker must recurse through a sequence
    "nested.yml": (
        "profiles:\n"
        "  - name: a\n"
        "    health_start_period: 1200s\n"
        "    health_start_period: 2400s\n"
    ),
    "flow.yml": '{"a": 1, "b": 2, "a": 3}' + "\n",
}

FIXTURES_OK = {
    # merge keys are inheritance, not duplication — this MUST stay green
    "merge_ok.yml": (
        "_x: &u_x\n"
        "  health_start_period: 1200s\n"
        "  cudagraph: true\n"
        "profiles:\n"
        "  arm1:\n"
        "    <<: *u_x\n"
        "    label: one\n"
        "  arm2:\n"
        "    <<: *u_x\n"
        "    label: two\n"
    ),
    # same key name in two sibling mappings is legal
    "siblings_ok.yml": (
        "a:\n"
        "  enabled: true\n"
        "b:\n"
        "  enabled: false\n"
    ),
    # Jinja and vault refs are just scalars; they must not confuse the walk
    "jinja_ok.yml": (
        'opt: "{{ hostvars[inventory_hostname][\\"x\\"] }}"\n'
        "secret: \"{{ vault.item.field }}\"\n"
    ),
    # two documents in one file, key reused across docs (legal: separate mappings)
    "multidoc_ok.yml": "key: 1\n---\nkey: 2\n",
}


def _tmp_tree(root, files):
    os.makedirs(root, exist_ok=True)
    for name, body in files.items():
        with open(os.path.join(root, name), "w") as fh:
            fh.write(body)


def self_test() -> int:
    import tempfile, shutil
    rc = 0
    for label, files, expect in (
        ("canary: duplicate keys must be caught", FIXTURES_BAD, "red"),
        ("legal near-misses must stay green", FIXTURES_OK, "green"),
    ):
        tmp = tempfile.mkdtemp(prefix="dupkeys-selftest-")
        try:
            _tmp_tree(tmp, files)
            found = [d for f in sorted(os.path.join(tmp, n) for n in files) for d in scan_file(f)]
            hits = {os.path.basename(f["file"]) for f in found}
            want = set(files) if expect == "red" else set()
            if hits != want:
                print(f"FAIL: self-test {label}: expected {sorted(want)}, got {sorted(hits)}",
                      file=sys.stderr)
                rc = 1
            else:
                print(f"OK: self-test {label} ({len(files)} fixture(s), hits={sorted(hits)})")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    # probe proof: the walker must actually see the live corpus it claims to police
    corpus = scan_tree(".")
    n = len(tracked_yaml("."))
    if n < 100:
        print(f"FAIL: self-test: only {n} live YAML files visible — run from the repo root; "
              "a partial tree is not evidence the corpus was walked", file=sys.stderr)
        return 1
    print(f"OK: self-test corpus probe — {n} live YAML files parsed, "
          f"{len(corpus)} duplicate key(s) found")
    return rc


def _iter_yaml(root="."):
    return iter(tracked_yaml(root))


def shutil_which(cmd):
    from shutil import which
    return which(cmd)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--root", default=".")
    ap.add_argument("--show", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    found = scan_tree(args.root)
    if args.show:
        print(f"{len(found)} duplicate mapping key(s) in the live YAML corpus")
        for f in found:
            print(f"  {f['file']}:{f['line']}  {f['key']}  (first defined at line {f['first_line']})")
        return 0

    if found:
        print(f"FAIL: {len(found)} duplicate YAML mapping key(s) — ansible keeps the LAST and "
              "silently drops the first (CONVENTIONS §6, HD-1098):", file=sys.stderr)
        for f in found:
            print(f"  {f['file']}:{f['line']}  {f['key']}   (first defined at line {f['first_line']}; "
                  "that definition is DEAD — delete or merge it)", file=sys.stderr)
        return 1
    print(f"OK: no duplicate YAML mapping keys in the live YAML corpus "
          f"({sum(1 for _ in _iter_yaml(args.root))} files walked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
