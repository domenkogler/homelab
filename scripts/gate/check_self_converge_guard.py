#!/usr/bin/env python3
"""Lint: the HD-413 self-converge guardrail stays complete and fail-loud.

`playbooks/tasks/self-converge-guard.yml` refuses the lockout-capable roles
(`network`, `storage`, `wireguard`, `vps-hardening`, `tailscale-node`,
and the role that writes a PAM stack, `cockpit`) when a playbook's target is the same
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
                      silent pass). A `check_mode: false` task makes a role really execute
                      during `--check`, so a role whose such tasks CAN WRITE must declare
                      `check_safe: false` — an over-stated check_safe would hand back the
                      lockout through the check-mode escape (live: roles/vps-hardening's
                      sshd_config assert). Two halves, both load-bearing:
                        * the detector carries the trailing comment, because YAML ends a plain
                          scalar at ` #` and this repo's read-back lines all carry one — an
                          end-of-line anchor sees none of them, and the claim then holds only
                          by accident (measured 2026-10-19: cockpit's eight sites, zero seen);
                        * the site is CLASSIFIED by what its task does. A read-only module
                          (`stat`/`slurp`/`find`/`get_state`/`*_facts`) or a `command`/`shell`
                          declaring `changed_when: false` is a read-back and leaves
                          `check_safe: true` honest — HD-361's cockpit read-backs are exactly
                          that shape. Anything else, including a module this file does not
                          know, is a write and reddens naming `file:line`.
  6. identity-source  — the controller must be identified by a controller-side lookup
                      (`lookup('pipe', ...)`), never by a target fact: `ansible_hostname` is
                      the box being converged, which would make the guard compare a host
                      with itself and always fire.
  8. coverage-fixture -- `scripts/testdata/self-converge-guard/fixture.yml` claims in its own
                      header to mirror how the playbooks wire the guard. It is not in this
                      checker's corpus (playbooks() reads IaC/ansible/playbooks/*.yml +
                      site.yml) and `run.sh` asserts only on rc and stdout, so until this check
                      existed nothing static read the fixture at all, and the claim rotted: the
                      fixture was the last holder of the purged `HD-413 | Self-converge
                      guardrail` while all five playbooks had moved on. So: the fixture's
                      `pre_tasks` must import the guard file the playbooks import -- the same
                      target, resolved, not merely a string that looks like it.

Run:   python3 scripts/gate/check_self_converge_guard.py
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

# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root  # noqa: E402
ROOT = _hl_root(__file__)
ANSIBLE = ROOT / "IaC" / "ansible"
GUARD = ANSIBLE / "playbooks" / "tasks" / "self-converge-guard.yml"
GUARD_REF = "self-converge-guard.yml"
FIXTURE = ROOT / "scripts" / "testdata" / "self-converge-guard" / "fixture.yml"
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


# ── check 5's `check_mode: false` detector ------------------------------------------------
# YAML ends a plain scalar at the first ` #`, so `check_mode: false   # read-back` IS the boolean
# false for Ansible. A pattern anchored at end-of-line does not see it, which is the blind spot
# HD-1165 measured: `roles/cockpit/tasks/maint-user.yml` carries eight such lines, every one of
# them written in this file's own in-file style with a trailing comment, and the anchored detector
# counted zero — so a role that really writes during `--check` could keep the check-mode escape by
# adding a comment. The comment half is part of the pattern, not an afterthought.
CHECK_MODE_FALSE = re.compile(r"^\s*check_mode:\s*false\s*(?:#.*)?$")

# The task keywords, as ONE list for the YAML reader (`_module_of`) and the line reader below —
# two spellings of "is this line a module or a keyword" is how the two would drift apart.
TASK_KEYWORDS = ("name", "when", "vars", "tags", "become", "notify", "register",
                 "changed_when", "failed_when", "loop", "with_items", "no_log",
                 "check_mode", "block", "rescue", "always", "listen", "run_once",
                 "environment", "delegate_to", "ignore_errors", "until", "retries",
                 "delay", "throttle", "any_errors_fatal")

# What the CARRYING TASK can do decides whether `check_safe: true` is an honest claim, because
# step 1 alone would accuse every read-back in the fleet. A read-only module cannot write under
# `--check` however it is scheduled, and the `_facts` family is read-only by definition. A
# `command`/`shell` that declares `changed_when: false` declares itself a read-back — the shape
# HD-361 needed, where a task SKIPPED under `--check` yields an empty stdout and the assert beside
# it then fires on a healthy box. Everything else — copy/template/file/user/group/service/systemd/
# mount/lineinfile, an `include_tasks` whose children are unknown to this scan, or a module this
# list has never heard of — is a WRITE. The classifier answers "could this touch the box?" with
# yes whenever it cannot tell, because a false RED costs one `check_safe: false` line and a false
# GREEN costs the lockout HD-413 exists to refuse.
CHECK_MODE_READ_MODULES = ("stat", "slurp", "find", "get_state", "debug", "assert", "fail",
                           "set_fact", "meta", "ping", "wait_for_connection")
CHECK_MODE_CMD_MODULES = ("command", "shell")


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _is_list_item(line: str) -> bool:
    return bool(re.match(r"^\s*-\s", line))


def classify_check_mode_sites(role_dir: Path, rel_base: Path | None = None) -> tuple[list[str], list[str]]:
    """(writes, reads) — every `check_mode: false` under a role dir, as `path:line`.

    `rel_base` is what the named path is relative to (the tree's `IaC/ansible` in the gate, the
    fixture root in the self-test), so the message a reader acts on is a real path in both.

    Text, not YAML, on purpose: the finding is a LINE number, and `safe_load` throws the line away.
    Each site is attributed to the task that carries it by walking up to the nearest list item at a
    shallower indent (the task's own start line), then reading that task's key level for its module
    and for a `changed_when: false` at the SAME indent as the `check_mode` line — the task's own
    declaration, never one belonging to a task nested inside it.

    Reads and writes both come back named, because "which lines did the detector see at all" is the
    question HD-1165 was written to make answerable.
    """
    writes: list[str] = []
    reads: list[str] = []
    for f in sorted(role_dir.rglob("*.yml")):
        lines = f.read_text(encoding="utf-8").splitlines()
        starts = [i for i, ln in enumerate(lines) if _is_list_item(ln)]
        for i, line in enumerate(lines):
            if not CHECK_MODE_FALSE.match(line):
                continue
            # as_posix, not str(): on a Windows seat relative_to yields `wrote\tasks\main.yml`, and every
            # reader of this string compares a FORWARD-slash prefix (the self-test below asks
            # `startswith("wrote/")`, a caller greps `roles/x/tasks/main.yml`). A backslash answer is
            # therefore invisible rather than wrong — the five canaries read INVISIBLE and the checker
            # reports a detector that sees nothing, which is the one verdict a gate must never print.
            where = f"{f.relative_to(rel_base or role_dir.parent).as_posix()}:{i + 1}"
            key_indent = _indent(line)
            # The task that carries this line: the nearest list item ABOVE it at a shallower indent.
            start = next((j for j in sorted(starts, reverse=True) if j < i and _indent(lines[j]) < key_indent), None)
            if start is None:
                writes.append(f"{where} (no task found — cannot classify, so assumed)")
                continue
            # ...and the end of that task: the next list item at its own indent or shallower.
            task_indent = _indent(lines[start])
            end = next((j for j in starts if j > start and _indent(lines[j]) <= task_indent), len(lines))
            module, changed_never = "", False
            for j in range(start, end):
                body = lines[j].strip()
                if _indent(lines[j]) != key_indent or not body or body.startswith("#"):
                    continue
                m = re.match(r"^([\w.]+)\s*:", body)
                if not m:
                    continue
                key = m.group(1)
                if key == "changed_when":
                    changed_never = bool(re.match(r"changed_when:\s*false\s*(?:#.*)?$", body))
                elif key not in TASK_KEYWORDS and not module:
                    module = key.split(".")[-1]
            # A module written on the task's own dash line (`- copy: content=x`) carries no key line.
            if not module:
                m = re.match(r"^-\s+([\w.]+)\s*:", lines[start].lstrip())
                if m and m.group(1) not in TASK_KEYWORDS:
                    module = m.group(1).split(".")[-1]
            if module in CHECK_MODE_READ_MODULES or module.endswith("_facts"):
                reads.append(f"{where} ({module}: read-only module)")
            elif module in CHECK_MODE_CMD_MODULES and changed_never:
                reads.append(f"{where} ({module} + changed_when: false: read-back)")
            else:
                writes.append(f"{where} ({module or 'module not found'})")
    return writes, reads


def _module_of(task: dict) -> tuple[str, dict]:
    for key, val in task.items():
        if key in TASK_KEYWORDS:
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


def pre_task_imports(play: dict) -> list[str]:
    """Every import target a play runs before its roles. Empty when the play has none."""
    out: list[str] = []
    for task in play.get("pre_tasks") or []:
        if isinstance(task, dict):
            for key, val in task.items():
                if "import_tasks" in str(key) and isinstance(val, str):
                    out.append(val)
    return out


def imports_the_guard(target: str, base_dir: Path) -> bool:
    """Does this import path resolve to THE guard file, from the play's own directory?

    A playbook writes `tasks/self-converge-guard.yml` and the fixture writes
    `../../../IaC/ansible/playbooks/tasks/self-converge-guard.yml`; both are the same file, so
    the comparison is on the resolved path. An import of some other file that merely carries
    the name is not the guard.
    """
    if GUARD_REF not in target:
        return False
    try:
        return (base_dir / target).resolve() == GUARD.resolve()
    except OSError:  # a path this OS cannot resolve cannot import the guard either
        return False


def fixture_problems() -> list[str]:
    """8: the fixture's claimed mirror of the playbook wiring, enforced.

    `run.sh` runs the fixture against a throwaway inventory and asserts on rc and output, so a
    fixture wired differently still PASSES the behaviour matrix while testing a wiring no
    playbook ships. This is the static half of that claim.
    """
    if not FIXTURE.is_file():
        return [f"coverage-fixture: {FIXTURE.relative_to(ROOT)} is gone, so the HD-413 "
                f"behaviour matrix (validate-all item 17) has no play to run"]
    try:
        docs = [d for d in yaml.safe_load_all(FIXTURE.read_text(encoding="utf-8"))
                if isinstance(d, list)]
    except yaml.YAMLError as exc:
        return [f"parse: {FIXTURE.relative_to(ROOT)}: {exc}"]
    plays = [p for doc in docs for p in doc if isinstance(p, dict)]
    if not plays:
        return [f"parse: {FIXTURE.relative_to(ROOT)}: no play to read"]
    problems: list[str] = []
    for play in plays:
        targets = pre_task_imports(play)
        if not any(imports_the_guard(t, FIXTURE.parent) for t in targets):
            problems.append(
                f"coverage-fixture: {FIXTURE.relative_to(ROOT)} imports "
                f"{targets or ['nothing']} in pre_tasks, which is not the guard the playbooks "
                f"import ({GUARD_REF}) -- its header claims it mirrors how the playbooks wire the "
                f"guard, and run.sh asserts on rc and stdout only, so a fixture wired any other "
                f"way measures a wiring no playbook ships")
    return problems


def _check_mode_self_test() -> list[str]:
    """HD-1165: the `check_mode: false` detector must SEE the commented form the tree writes,
    and must then classify what it saw.

    Four arms, each built to differ under exactly one behaviour. Drop the `(?:#.*)?` from
    CHECK_MODE_FALSE and the two commented cases disappear, so arm 1 and arm 4 go silent-while-
    blind and this function reports them; drop the read-back clause and `readback` reddens; drop
    the read-only-module clause and `readonly` reddens; and a classifier that calls everything a
    write reddens exactly the two arms that must be reads. A mutation that cannot turn an arm red
    is not a test, which is the whole reason the cases are separate role dirs.
    """
    import tempfile

    cases = {
        # a WRITE carrying the in-file comment -- the case the old anchored pattern lost
        "wrote": ["- name: write the gate line",
                  "  ansible.builtin.copy:",
                  "    dest: /etc/pam.d/cockpit",
                  "  check_mode: false   # a comment here is not evidence of anything"],
        # a `command` that declares itself a read-back, commented like cockpit's eight
        "readback": ["- name: read the group set back",
                     "  ansible.builtin.command:",
                     "    cmd: id -nG maint",
                     "  changed_when: false",
                     "  check_mode: false   # a probe, not a mutation"],
        # a read-only module, commented
        "readonly": ["- name: is the file there",
                     "  ansible.builtin.stat:",
                     "    path: /etc/ssh/sshd_config",
                     "  check_mode: false   # a probe, not a mutation"],
        # the pre-existing uncommented case, so the fix cannot have traded the old detection away
        "plainwrite": ["- name: assert sshd hardening",
                       "  ansible.builtin.lineinfile:",
                       "    path: /etc/ssh/sshd_config",
                       "  check_mode: false"],
        # a command WITHOUT changed_when: the classifier cannot call it a read-back, so it is a write
        "barecmd": ["- name: run something",
                    "  ansible.builtin.command:",
                    "    cmd: systemctl restart sshd",
                    "  check_mode: false   # no changed_when, so no read-back claim"],
    }
    problems: list[str] = []
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        for name, lines in cases.items():
            d = root / "roles" / name / "tasks"
            d.mkdir(parents=True)
            (d / "main.yml").write_text("\n".join(lines) + "\n", encoding="utf-8")
        writes, reads = classify_check_mode_sites(root / "roles", root / "roles")
        seen = {n: (any(s.startswith(f"{n}/") for s in writes),
                    any(s.startswith(f"{n}/") for s in reads)) for n in cases}
        for name, (is_w, is_r) in seen.items():
            want = {"wrote": (True, False), "readback": (False, True), "readonly": (False, True),
                    "plainwrite": (True, False), "barecmd": (True, False)}[name]
            if (is_w, is_r) != want:
                problems.append(
                    f"check_mode self-test: role dir '{name}' classified as "
                    f"{'write' if is_w else 'read' if is_r else 'INVISIBLE'}"
                    f" — expected {'write' if want[0] else 'read'}")
        # The site must be named as file:line, because "role X writes" is not actionable and a
        # reader has to be able to land on the line that carries the claim.
        if not any(re.search(r":\d+$", s.split(" ")[0]) for s in writes + reads):
            problems.append("check_mode self-test: no site was named as file:line — the message "
                            "cannot be acted on")
    return problems


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
    problems += _check_mode_self_test()
    # The fixture witness (check 8), green case and red case together. The red case is the
    # wave-2 shape: a play whose pre_tasks no longer imports the guard. If the detector cannot
    # see that, the assertion can only ever pass and the fixture claim is unguarded again.
    plays_here = ANSIBLE / "playbooks"
    wired = {"pre_tasks": [{"name": "Self-converge guardrail",
                            "ansible.builtin.import_tasks": "tasks/self-converge-guard.yml"}]}
    if not any(imports_the_guard(t, plays_here) for t in pre_task_imports(wired)):
        problems.append("fixture self-test: a pre_tasks guard import was NOT recognised -- the "
                        "fixture assertion could never pass, and a green run would prove nothing")
    unwired = {"pre_tasks": [{"name": "Self-converge guardrail",
                              "ansible.builtin.debug": {"msg": "the import line is gone"}}]}
    if any(imports_the_guard(t, plays_here) for t in pre_task_imports(unwired)):
        problems.append("fixture self-test: a play with no guard import was accepted -- the new "
                        "fixture assertion cannot go red")
    elsewhere = {"pre_tasks": [{"ansible.builtin.import_tasks": "roles/self-converge-guard.yml"}]}
    if any(imports_the_guard(t, plays_here) for t in pre_task_imports(elsewhere)):
        problems.append("fixture self-test: an import of a same-named file in another directory "
                        "satisfied the claim -- the check compares a name, not the target it "
                        "resolves to, so a stub copy of the guard would pass")
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
    sites_seen: dict[str, str] = {}
    for name, spec in sorted(roles.items()):
        role_dir = ANSIBLE / "roles" / name
        if not role_dir.is_dir():
            problems.append(f"coverage-role: guard declares lockout role '{name}' but "
                            f"IaC/ansible/roles/{name}/ does not exist (renamed role?)")
            continue
        writes_in_check, reads_in_check = classify_check_mode_sites(role_dir, ANSIBLE)
        # Recorded for the closing line even when both are empty: the doc's claim that a
        # `--tags network --check` is read-only is THIS read, not a sentence in a table.
        sites_seen[name] = f"{len(writes_in_check)} write / {len(reads_in_check)} read-back"
        if writes_in_check and spec["check_safe"]:
            problems.append(
                f"fail-loud: role '{name}' declares check_safe: true but writes during "
                f"--check (check_mode: false at {', '.join(writes_in_check)}) — the "
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

    # 8: the fixture that stands in for the playbooks must wire the guard the way they do.
    problems += fixture_problems()

    if problems:
        print(f"FAIL: {len(problems)} self-converge-guard problem(s):")
        for p in problems:
            print(f"  - {p}")
        return 1

    print(f"[detected] {len(guarded_by_detector)} guarded role(s) justified by behaviour: "
          f"{', '.join(guarded_by_detector) or '-'}")
    # The check_mode: false inventory, printed rather than argued: "the gate sees the line" is the
    # claim this line exists to make re-checkable instead of a claim about a regex.
    print("[check_mode: false] " + ("; ".join(f"{k} -> {v}" for k, v in sorted(sites_seen.items()))
                                    or "no lockout role declared a role dir to read"))
    if exempt_rows:
        print(f"[exempt] {len(exempt_rows)} role(s) exempt by written argument: {', '.join(exempt_rows)}")
    require_corpus(len(roles), 5, "check_self_converge_guard lockout-role set")
    print(f"OK: self-converge guard covers {len(roles)} lockout role(s) "
          f"({', '.join(sorted(roles))}) across {guarded_count} guarded play(s); "
          f"fail-loud, controller-side identity, tag parity intact")
    return 0


if __name__ == "__main__":
    sys.exit(main())
