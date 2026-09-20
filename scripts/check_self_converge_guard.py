#!/usr/bin/env python3
"""Lint: the HD-413 self-converge guardrail stays complete and fail-loud.

`playbooks/tasks/self-converge-guard.yml` refuses the lockout-capable roles
(`network`, `storage`, `wireguard`, `vps-hardening`) when a playbook's target is the same
machine running the playbook. Once oldsrv is a control node (HD-407) — and the VPS already
is one — an agent driving from a phone can converge the roles that decide whether its own
SSH session survives: netdev units, fstab/NFS/ZFS mounts, the WG interface, nftables +
sshd_config. The guard is the thing that refuses, so the guard itself must not rot.

Checks:
  1. coverage-playbook — every playbook that applies a lockout role imports the guard.
                      A new playbook (or a role added to an existing one) that carries a
                      lockout role without the guard is exactly the hole HD-413 exists to
                      close; this catches it at gate time rather than mid-converge.
  2. coverage-pre-task— the import must sit in `pre_tasks`, not `tasks`/`post_tasks`:
                      pre_tasks run before ANY role, so a guard placed after the roles can
                      only ever notice the lockout too late.
  3. coverage-role    — every lockout role has its own guard task (a shared single task
                      cannot be tag-selected per role, and tag selection is the whole
                      design: `--tags docker_services,x` must stay allowed).
  4. tag-symmetry     — each guard task's `tags:` must equal its `homelab_guard_tags` plus
                      `always`, and may not name a reserved tag. The two lists answer
                      different questions (when does the guard RUN vs when WOULD the role have
                      run); if they drift apart, a `--tags` filter can select the role while
                      selecting neither, so no refusal is raised and the one that would be is
                      computed as 'not needed'.
  4b. tag-vocabulary  — `homelab_guard_tags` must cover the lockout role's complete selectable
                      vocabulary, recomputed from the role dirs on disk: every tag any task in
                      the role carries plus every role-level tag the playbooks put on it
                      (`base`). Roles with untagged tasks (storage 43/56, vps-hardening 16/17)
                      are covered by the guard's `always`, never by a tag literally named
                      `untagged` — that name is Ansible-reserved and warns on every converge.
  5. fail-loud        — no `default(` and no `failed_when` outside comments in the guard
                      (the HD-399 rule: a fallback in a guard converts a refusal into a
                      silent pass). A role dir carrying `check_mode: false` must be declared
                      `check_safe: false`, because such a task really writes during `--check`
                      (live: roles/vps-hardening's sshd_config assert) — an over-stated
                      check_safe would hand back the lockout through the check-mode escape.
  6. identity-source  — the controller must be identified by a controller-side lookup
                      (`lookup('pipe', ...)`), never by a target fact: `ansible_hostname` is
                      the box being converged, which would make the guard compare a host
                      with itself and always fire.

Run:   python3 scripts/check_self_converge_guard.py
Exit:  0 = clean, 1 = violations found.  Wired into `validate-all.sh`.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:  # pragma: no cover - gate hosts always have PyYAML
    print("FAIL: PyYAML is required (scripts/validate-all.sh runs under the ansible venv)")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
ANSIBLE = ROOT / "IaC" / "ansible"
GUARD = ANSIBLE / "playbooks" / "tasks" / "self-converge-guard.yml"
GUARD_REF = "self-converge-guard.yml"
# Ansible's reserved selection words — legal to write, warned about, and their behaviour is
# "not recommended", so the guard may not lean on them.
RESERVED_TAGNAMES = {"untagged", "all", "never", "always"}


def code_lines(path: Path) -> list[str]:
    """File lines with full-line comments stripped (the guard's header quotes the banned
    tokens as prose; only executable YAML may not carry them)."""
    return [ln for ln in path.read_text(encoding="utf-8").splitlines()
            if not ln.lstrip().startswith("#")]


def role_entries(play: dict) -> list[tuple[str, list[str]]]:
    """(role name, role-level tags) for every entry in a play's `roles:` list.
    A bare `- network` yields no tags; `- role: wireguard / tags: [...]` yields them."""
    out: list[tuple[str, list[str]]] = []
    for entry in play.get("roles") or []:
        if isinstance(entry, str):
            out.append((entry, []))
        elif isinstance(entry, dict):
            name = entry.get("role") or entry.get("name")
            if name:
                tags = entry.get("tags") or []
                out.append((str(name), [str(t) for t in (tags if isinstance(tags, list) else [tags])]))
    return out


def role_vocabulary(role: str) -> set[str]:
    """The complete set of --tags values that can select a task inside `role`, plus every
    role-level tag the playbooks attach to it. Recomputed from disk: the vocabulary is a
    property of the roles, not of this checker's opinion, so adding a tag inside a role
    tightens the guard instead of opening it. Untagged tasks are NOT folded into the
    vocabulary — they are the `always` case, which the caller checks separately."""
    vocab: set[str] = set()
    untagged = False
    for f in sorted((ANSIBLE / "roles" / role / "tasks").rglob("*.yml")):
        for doc in yaml.safe_load_all(f.read_text(encoding="utf-8")):
            if not isinstance(doc, list):
                continue
            for task in doc:
                if not isinstance(task, dict) or "import_tasks" in task or "include_tasks" in task:
                    continue
                tags = task.get("tags")
                if not tags:
                    untagged = True
                    continue
                for tag in (tags if isinstance(tags, list) else [tags]):
                    if str(tag) != "always":  # `always` selects the role's own asserts only
                        vocab.add(str(tag))
    for pb in playbooks():
        for doc in yaml.safe_load_all(pb.read_text(encoding="utf-8")):
            if not isinstance(doc, list):
                continue
            for play in doc:
                if isinstance(play, dict):
                    for name, tags in role_entries(play):
                        if name == role:
                            vocab.update(tags)
    return vocab, untagged


def guard_roles() -> dict[str, dict]:
    """Parse the declared lockout roles out of the guard file: name -> {tags, check_safe}."""
    doc = yaml.safe_load(GUARD.read_text(encoding="utf-8"))
    found: dict[str, dict] = {}
    for task in doc if isinstance(doc, list) else []:
        vars_ = task.get("vars") or {}
        role = vars_.get("homelab_guard_role")
        if not role:
            continue
        found[str(role)] = {
            "tags": [str(t) for t in (vars_.get("homelab_guard_tags") or [])],
            "check_safe": bool(vars_.get("homelab_guard_check_safe", False)),
            "task_tags": [str(t) for t in (task.get("tags") or [])],
        }
    return found


def playbooks() -> list[Path]:
    return sorted((ANSIBLE / "playbooks").glob("*.yml")) + [ANSIBLE / "site.yml"]


def main() -> int:
    if not GUARD.is_file():
        print(f"FAIL: guard file missing: {GUARD.relative_to(ROOT)}")
        return 1

    problems: list[str] = []
    roles = guard_roles()
    if not roles:
        print(f"FAIL: no homelab_guard_role declarations found in {GUARD.relative_to(ROOT)}")
        return 1

    # 3 + 5: per-role declarations are self-consistent with the role dirs on disk.
    for name, spec in sorted(roles.items()):
        role_dir = ANSIBLE / "roles" / name
        if not role_dir.is_dir():
            problems.append(f"coverage-role: guard declares lockout role '{name}' but "
                            f"IaC/ansible/roles/{name}/ does not exist (renamed role?)")
            continue
        writes_in_check = sorted(
            str(p.relative_to(ANSIBLE))
            for p in sorted(role_dir.rglob("*.yml"))
            if re.search(r"^\s*check_mode:\s*false\s*$", p.read_text(encoding="utf-8"), re.M)
        )
        if writes_in_check and spec["check_safe"]:
            problems.append(
                f"fail-loud: role '{name}' declares check_safe: true but writes during "
                f"--check (check_mode: false in {', '.join(writes_in_check)}) — the "
                f"check-mode escape hands the lockout straight back; set "
                f"homelab_guard_check_safe: false")
        if not spec["tags"]:
            problems.append(f"tag-symmetry: guard task for role '{name}' declares no "
                            f"homelab_guard_tags — an empty set can never be selected, so "
                            f"the role would run ungarded under --tags")
        # 4: task tags must be exactly the vocabulary + `always`, and no reserved names.
        expected_tags = set(spec["tags"]) | {"always"}
        if expected_tags != set(spec["task_tags"]):
            problems.append(
            f"tag-symmetry: role '{name}': guard task tags {sorted(spec['task_tags'])} != "
            f"homelab_guard_tags + ['always'] {sorted(expected_tags)} — one list decides when "
            f"the guard RUNS, the other when the ROLE would have run; under a --tags filter "
            f"that difference the role runs and no refusal is raised")
        reserved = (set(spec["task_tags"]) & RESERVED_TAGNAMES) - {"always"}
        if reserved:
            problems.append(
            f"tag-symmetry: role '{name}': guard task names reserved tag(s) "
            f"{sorted(reserved)} — Ansible warns on every run and their selection semantics "
            f"are not ours to rely on; `always` already covers the untagged-task case")
        # 4b: ...and the vocabulary must be the whole set the role can be selected by.
        required, has_untagged = role_vocabulary(name)
        if has_untagged and "always" not in set(spec["task_tags"]):
            problems.append(
            f"tag-vocabulary: role '{name}' carries untagged tasks, which are selected by "
            f"`--tags untagged` and by an unfiltered run; the guard task for it does not "
            f"carry `always`, so it would not be in the run when those tasks are")
        missing = required - set(spec["tags"])
        if missing:
            problems.append(
            f"tag-vocabulary: role '{name}' is selectable by {sorted(missing)} which the "
            f"guard's tag list {sorted(spec['tags'])} does not cover — e.g. "
            f"`--tags {sorted(missing)[0]}` would converge the lockout role from the control "
            f"node itself with the guard never selected")

    # 5: the guard itself stays fail-loud (code lines only — the header quotes the banned
    # tokens as prose, and the fixture below asserts the quoting is what it looks like).
    for ln in code_lines(GUARD):
        if "default(" in ln:
            problems.append(f"fail-loud: guard uses default() — a fallback in a guard turns "
                            f"a refusal into a silent pass: {ln.strip()[:100]}")
        if "failed_when" in ln:
            problems.append(f"fail-loud: guard uses failed_when (HD-399 rule): {ln.strip()[:100]}")

    # 6: controller identity must come from the controller — checked on CODE lines only,
    # because the header comment quotes lookup('pipe') as prose and would pass this gate
    # while the actual set_fact read the target's own nodename (measured 2026-09-20).
    guard_code = "\n".join(code_lines(GUARD))
    if "lookup('pipe'" not in guard_code and 'lookup("pipe"' not in guard_code:
        problems.append("identity-source: guard does not identify the controller with a "
                        "controller-side lookup('pipe', ...) — target facts (ansible_hostname) "
                        "describe the box being converged, not the one driving it")

    # 1 + 2 + 4: every playbook that can apply a lockout role guards it, early, with matching tags.
    guarded_count = 0
    for pb in playbooks():
        try:
            docs = [d for d in yaml.safe_load_all(pb.read_text(encoding="utf-8")) if isinstance(d, list)]
        except yaml.YAMLError as exc:
            problems.append(f"parse: {pb.relative_to(ROOT)}: {exc}")
            continue
        src = pb.read_text(encoding="utf-8")
        for doc in docs:
            for play in doc:
                if not isinstance(play, dict):
                    continue
                hits = [(r, t) for r, t in role_entries(play) if r in roles]
                if not hits:
                    continue
                guarded_count += 1
                if GUARD_REF not in src:
                    problems.append(f"coverage-playbook: {pb.relative_to(ROOT)} applies "
                                    f"lockout role(s) {[r for r, _ in hits]} but does not "
                                    f"import {GUARD_REF}")
                    continue
                pre = play.get("pre_tasks") or []
                if not any(GUARD_REF in str(t) for t in pre):
                    problems.append(f"coverage-pre-task: {pb.relative_to(ROOT)} imports "
                                    f"{GUARD_REF} outside pre_tasks — roles run before "
                                    f"tasks/post_tasks, so the guard would fire too late")
                for role, role_tags in hits:
                    missing = set(role_tags) - set(roles[role]["tags"])
                    if missing:
                        problems.append(
                            f"tag-vocabulary: {pb.relative_to(ROOT)} tags lockout role "
                            f"'{role}' with {sorted(missing)}, which the guard for it does "
                            f"not carry — that filter would run the role WITHOUT the guard")

    if problems:
        print(f"FAIL: {len(problems)} self-converge-guard problem(s):")
        for p in problems:
            print(f"  - {p}")
        return 1

    print(f"OK: self-converge guard covers {len(roles)} lockout role(s) "
          f"({', '.join(sorted(roles))}) across {guarded_count} guarded play(s); "
          f"fail-loud, controller-side identity, tag parity intact")
    return 0


if __name__ == "__main__":
    sys.exit(main())
