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


def walk_tasks(nodes, out: list[dict]) -> list[dict]:
    """Flatten a task list, descending into `block:` / `rescue:` / `always:`.

    Ansible applies a `tags:` on a nested task, and the run-time selector sees it, so a
    scan that walks only the top level reports a NARROWER vocabulary than reality: the gate
    would then bless a guard whose tag list cannot select the task a `--tags` run does
    select. Measured in this repo: `roles/spark` carries 7 tagged tasks inside blocks.
    """
    for task in nodes or []:
        if not isinstance(task, dict):
            continue
        out.append(task)
        for key in ("block", "rescue", "always"):
            if isinstance(task.get(key), list):
                walk_tasks(task[key], out)
    return out


def tags_in(tasks: list[dict]) -> tuple[set[str], bool]:
    """(selectable tags, has_untagged_tasks) for one flattened task list. One
    implementation on purpose: the self-test and the gate must ask the same question."""
    found: set[str] = set()
    untagged = False
    for task in tasks:
        tg = task.get("tags")
        if not tg:
            untagged = True
            continue
        for tag in (tg if isinstance(tg, list) else [tg]):
            if str(tag) != "always":   # `always` selects the guard's own asserts only
                found.add(str(tag))
    return found, untagged


def load_docs(path: Path) -> list[list[dict]]:
    """Parse a tasks file into lists of flattened task dicts."""
    docs = []
    for doc in yaml.safe_load_all(path.read_text(encoding="utf-8")):
        if isinstance(doc, list):
            docs.append(walk_tasks(doc, []))
    return docs


def role_vocabulary(role: str) -> set[str]:
    """The complete set of --tags values that can select a task inside `role`, plus every
    role-level tag the playbooks attach to it. Recomputed from disk: the vocabulary is a
    property of the roles, not of this checker's opinion, so adding a tag inside a role
    tightens the guard instead of opening it. Untagged tasks are NOT folded into the
    vocabulary — they are the `always` case, which the caller checks separately."""
    vocab: set[str] = set()
    untagged = False
    for f in sorted((ANSIBLE / "roles" / role / "tasks").rglob("*.yml")):
        for tasks in load_docs(f):
            found, has_untagged = tags_in([t for t in tasks
                                           if "import_tasks" not in t and "include_tasks" not in t])
            vocab |= found
            untagged = untagged or has_untagged
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


# -----------------------------------------------------------------------------------
# Which roles COULD cut the driving session — derived from what they do, not from a list
# of names somebody remembered. The lockout set used to be a hand-maintained list, which
# means a new role that restarts `tailscaled` joins the fleet silently and stays un-guarded
# until a human notices (that is exactly how `tailscale-node` arrived, from another lane).
# Now: any role whose tasks touch one of these is either guarded or explicitly exempt with a
# written reason, and `validate-all.sh` goes red otherwise.
# -----------------------------------------------------------------------------------
CRITICAL_UNITS = (
    "tailscaled", "wg-quick", "wireguard", "systemd-networkd", "networking",
    "NetworkManager", "systemd-resolved", "ssh", "sshd", "nftables", "firewalld",
    "iptables", "ip6tables",
)
CRITICAL_COMMANDS = (
    r"\bnft\b", r"\biptables\b", r"\bip\s+(route|link|addr|rule)\b",
    r"\bwg\s|\bwg-quick\b", r"\btailscale\s+(up|down|logout|set)\b",
    r"\bnmcli\b", r"\bnetplan\b", r"\bsystemctl\s+\S*\s*(restart|reload|stop)\b",
    r"\bservice\s+\S+\s+(restart|stop)\b", r"\b(um|)mount\s+-",
)
CRITICAL_PATHS = (
    "/etc/ssh/", "/etc/systemd/network", "/etc/NetworkManager/", "/etc/netplan/",
    "/etc/network/", "/etc/nftables", "/etc/iptables", "/etc/wireguard/",
    "/etc/fstab", "/etc/pam.d/", "/etc/sudoers", "/etc/security/",
    "/root/.ssh", "authorized_keys",
)
FILE_MODULES = ("copy", "template", "file", "blockinfile", "lineinfile", "replace",
                "assemble", "ini_file", "htpasswd")
MOUNT_MODULES = ("mount", "mount_facts", "zfs", "zfs_facts", "filesystem")
# A `dest:` rendered from a variable (`{{ netd_dir }}/20-eth0.network`) is opaque to a
# static scanner, so match the RAW string too. This is a heuristic and it is honest about
# being one: it over-matches a benign path containing the word `network` (which costs one
# written exemption line) rather than under-matching a netdev unit written through a var
# (which would cost a lockout). roles/network is exactly this shape, all over.
PATH_HINTS = ("netd_dir", "netd_", "netdev", "netplan", "nmconnection", "nm_keyfile",
              "sshd", "ssh_config", "ssh/authorized_keys", "authorized_keys", "sudoers",
              "fstab", "nftables", "nft.conf", "iptables", "wireguard", "wg-quick",
              "resolved.conf")
# Deliberately NOT hinted: the bare words "network" and "ssh". `/opt/network-clients-exporter`
# is not a netdev unit, and the absolute paths above already cover what matters. Measured:
# hinting "network" flagged `monitoring` for writing its own exporter directory — a gate
# that cries wolf here gets its exemptions written lazily, which is worse than no gate.
CMD_MODULES = ("command", "shell", "raw", "script", "expect")
UNIT_MODULES = ("systemd", "systemd_service", "service")

# Out of the model ON PURPOSE, and named so the next reader does not mistake the silence
# for coverage: container-level damage (a compose converge that stops the stack the runner
# is inside), and RouterOS / switch configuration driven over network_cli (no local session
# to cut, and these patterns are Linux primitives by construction).
DETECTOR_LIMITS = ("community.docker", "ansible.builtin.docker", "uri", "get_url")


def _module_of(task: dict) -> tuple[str, dict]:
    for key, val in task.items():
        if key in ("name", "when", "vars", "tags", "become", "notify", "register",
                   "changed_when", "failed_when", "loop", "with_items", "no_log",
                   "check_mode", "block", "rescue", "always", "listen", "run_once",
                   "environment", "delegate_to", "ignore_errors", "until", "retries",
                   "delay", "throttle", "any_errors_fatal"):
            continue
        if isinstance(val, dict) or val is None:
            return str(key).split(".")[-1], (val or {})
    return "", {}


def session_critical_hits(role: str) -> list[str]:
    """Human-readable 'what this role does to a session' hits for ROLE. Empty = the
    detector sees no way for it to sever the driving connection."""
    hits: list[str] = []
    tdir = ANSIBLE / "roles" / role / "tasks"
    for f in sorted(tdir.rglob("*.yml")) if tdir.is_dir() else []:
        for tasks in load_docs(f):
            for task in tasks:
                mod, args = _module_of(task)
                where = f"{f.relative_to(ANSIBLE / 'roles' / role)}: {task.get('name', '?')}"
                if mod in UNIT_MODULES:
                    unit = str(args.get("name", ""))
                    if any(u in unit for u in CRITICAL_UNITS):
                        hits.append(f"{where} → restarts/manages '{unit}'")
                elif mod in CMD_MODULES:
                    line = str(args.get("cmd") or args.get("_raw_params") or "")
                    for pat in CRITICAL_COMMANDS:
                        if re.search(pat, line):
                            hits.append(f"{where} → runs `{line.strip()[:60]}`")
                            break
                elif mod in FILE_MODULES:
                    dest = str(args.get("dest") or args.get("path") or "")
                    low = dest.lower()
                    if any(dest.startswith(pfx) or f"/{pfx.strip('/')}" in low for pfx in CRITICAL_PATHS) \
                       or any(hint in low for hint in PATH_HINTS):
                        hits.append(f"{where} → writes {dest}")
                elif mod in MOUNT_MODULES:
                    state = str(args.get("state", "mounted"))
                    if state in ("mounted", "present", "enabled"):
                        hits.append(f"{where} → {mod}: state={state} on {args.get('name') or args.get('path') or args.get('src') or '?'}")
    return hits


def lockout_exemption(role: str) -> str:
    """The role's written argument for why it is NOT lockout-capable, if it declared one."""
    dfile = ANSIBLE / "roles" / role / "defaults" / "main.yml"
    if not dfile.is_file():
        return ""
    try:
        for doc in yaml.safe_load_all(dfile.read_text(encoding="utf-8")):
            if isinstance(doc, dict):
                reason = doc.get("homelab_lockout_exempt_reason")
                if isinstance(reason, str) and reason.strip():
                    return reason.strip()
    except yaml.YAMLError:
        return ""
    return ""


def self_test() -> list[str]:
    """Prove the two scanners can see the things they claim to see.

    This exists because a fix was once claimed in a commit message while the code change
    behind it was never committed, and the 'proof' run reported a vocabulary that looked
    identical either way — the tags it checked also existed at top level, so the test could
    not have failed. Every case below is built to differ under exactly one behaviour.
    """
    problems: list[str] = []
    pos = {
        "systemd restarts sshd": [{"ansible.builtin.systemd_service": {"name": "sshd", "state": "restarted"}}],
        "command runs nft": [{"ansible.builtin.command": {"cmd": "nft -f /etc/nft.conf"}}],
        "writes sshd_config": [{"ansible.builtin.copy": {"dest": "/etc/ssh/sshd_config", "content": "x"}}],
        "tailscale up": [{"ansible.builtin.command": {"cmd": "tailscale up --login-server=x"}}],
        "wg-quick restart": [{"ansible.builtin.service": {"name": "wg-quick@wg0", "state": "restarted"}}],
        "writes a netdev unit through a variable": [{"ansible.builtin.copy":
            {"dest": "{{ netd_dir }}/20-eth0.network", "content": "x"}}],
        "mounts a filesystem": [{"ansible.posix.mount": {"path": "/tank/data", "state": "mounted"}}],
        "nested one deep in a block": [{"block": [{"block": [{"ansible.builtin.systemd":
            {"name": "systemd-networkd", "state": "restarted"}}]}]}],
    }
    neg = {
        "a debug task": [{"ansible.builtin.debug": {"msg": "restarting sshd would be bad"}}],
        "writes an unrelated file": [{"ansible.builtin.template": {"dest": "/etc/motd", "src": "x.j2"}}],
        "installs a package": [{"ansible.builtin.apt": {"name": "nginx", "state": "present"}}],
        "starts a container (declared limit)": [{"community.docker.docker_container": {"name": "immich"}}],
        "rewrites /etc/hosts (declared limit)": [{"ansible.builtin.copy": {"dest": "/etc/hosts", "content": "x"}}],
    }
    for label, docs in pos.items():
        if not _hits_from_docs(docs):
            problems.append(f"detector self-test: '{label}' was NOT flagged as session-critical")
    for label, docs in neg.items():
        if _hits_from_docs(docs):
            problems.append(f"detector self-test: '{label}' was wrongly flagged (would nag every session)")
    # The vocabulary scanner, with the tag living ONLY inside a block: a top-level-only scan
    # returns the empty set here, so this case cannot pass by accident.
    collected, _ = tags_in(walk_tasks([{"block": [{"name": "inner", "tags": ["only-in-block"]}]}], []))
    if "only-in-block" not in collected:
        problems.append(f"vocabulary self-test: a block-only tag was not collected (got {sorted(collected)})")
    return problems


def _hits_from_docs(docs: list[dict]) -> bool:
    """The detector's decision for one task list, without touching the filesystem."""
    for task in walk_tasks(docs, []):
        mod, args = _module_of(task)
        if mod in UNIT_MODULES and any(u in str(args.get("name", "")) for u in CRITICAL_UNITS):
            return True
        if mod in CMD_MODULES and any(re.search(p, str(args.get("cmd") or args.get("_raw_params") or ""))
                                      for p in CRITICAL_COMMANDS):
            return True
        if mod in FILE_MODULES:
            dest = str(args.get("dest") or args.get("path") or "")
            low = dest.lower()
            if any(dest.startswith(pfx) or f"/{pfx.strip('/')}" in low for pfx in CRITICAL_PATHS) \
               or any(hint in low for hint in PATH_HINTS):
                return True
        if mod in MOUNT_MODULES and str(args.get("state", "mounted")) in ("mounted", "present", "enabled"):
            return True
    return False


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

    # First: prove this checker can see what it claims to see. A gate nobody can falsify is
    # decoration, and one that nags on every benign role gets worked around, so both halves
    # are asserted here rather than argued in a commit message.
    problems += self_test()

    roles = guard_roles()
    if not roles:
        print(f"FAIL: no homelab_guard_role declarations found in {GUARD.relative_to(ROOT)}")
        return 1

    # 7: the set is CLOSED against what the roles actually do, not against what anyone
    # remembered to add. A role that restarts a session-critical unit, rewrites a firewall /
    # sshd / netdev file or drives mounts must be guarded, or must carry
    # homelab_lockout_exempt_reason in defaults/main.yml arguing why it cannot cut a session.
    guarded_by_detector: list[str] = []
    exempt_rows: list[str] = []
    for role_dir in sorted((ANSIBLE / "roles").iterdir()):
        if not (role_dir / "tasks").is_dir():
            continue
        name = role_dir.name
        hits = session_critical_hits(name)
        if not hits:
            continue
        if name in roles:
            guarded_by_detector.append(name)
            continue
        reason = lockout_exemption(name)
        if reason:
            exempt_rows.append(name)
            if len(reason) < 40:
                problems.append(
                    f"classification: role '{name}' claims a lockout exemption but the reason "
                    f"is {len(reason)} chars — write the actual argument (what it touches, and "
                    f"why that cannot sever the driving session), not a placeholder")
            continue
        problems.append(
            f"classification: role '{name}' touches session-critical state but is neither "
            f"guarded nor exempt — {hits[0]}"
            + (f" (+{len(hits) - 1} more)" if len(hits) > 1 else "")
            + ". Either add it to the lockout set (a guard task + its tag vocabulary, in one "
              "change), or declare homelab_lockout_exempt_reason in its defaults/main.yml "
              "saying why it cannot cut a session.")

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

    print(f"[detected] {len(guarded_by_detector)} guarded role(s) justified by behaviour: "
          f"{', '.join(guarded_by_detector) or '-'}")
    if exempt_rows:
        print(f"[exempt] {len(exempt_rows)} role(s) exempt by written argument: {', '.join(exempt_rows)}")
    print(f"OK: self-converge guard covers {len(roles)} lockout role(s) "
          f"({', '.join(sorted(roles))}) across {guarded_count} guarded play(s); "
          f"fail-loud, controller-side identity, tag parity intact")
    return 0


if __name__ == "__main__":
    sys.exit(main())
