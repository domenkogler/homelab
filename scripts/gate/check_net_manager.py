#!/usr/bin/env python3
"""Lint: every host DECLARES its network config-manager, and the declaration cannot be implied.

WHY THIS EXISTS. The role decided which manager a host used by asking whether a variable happened to
be defined — and that variable had a ROLE-LEVEL default (`netd_phys_name: eno1`), so the guard was
true on every host in the inventory. The result, measured host by host: oldsrv carried three
`/etc/systemd/network` files that a DISABLED systemd-networkd never reads while NetworkManager holds
the address; the Pi and the VPS got units naming `eno1`, an interface neither box has; spark ran BOTH
managers at once; nas ran NEITHER — its uplink belongs to classic ifupdown. Editing any of those dead
files is a green converge that changes nothing on the wire, which is the same silent-no-op class as a
duplicate YAML key (check_yaml_dup_keys.py) and an untagged repair block (HD-450).

THE RULES, each one a finding rather than a paragraph:

  1. declaration   — every host the `network` role is applied to declares network_manager AND
                     network_manager_target in ITS OWN host_vars, each inside the role's vocabulary.
                     A group_vars file supplying either is also a finding: that is how a fleet-wide
                     default comes back through the back door once a host-level one is missing.
  2. no-implied    — roles/network may not define netd_phys_name, network_manager or
                     network_manager_target. A role-level value is what made the old guard a
                     tautology; the facts belong to the host.
  3. render-gate   — every task that renders a systemd-networkd unit must gate on the DECLARED
                     manager, not on whether a var is defined. This is the half that keeps the root
                     fix from regrowing.
  4. freeze        — while a host's owner and its ruled target differ, that host declares no
                     netd_phys_name, appears in no NetworkManager dual-home list, and defines no
                     resolver/profile leg: an owed migration is a frozen host, not a half-written one.
  5. guard-live    — the role must still ask the BOX: the three refuses exist, the removal leg uses
                     the role's declared unit namespace (never a wider glob), the disarm of a second
                     manager carries all five of its safety conditions, and the post-disarm read-back
                     asserts the leg survived. No `default()` anywhere in that block — a fallback in a
                     guard converts a refusal into a silent pass.
  6. namespace     — no role other than `network` may write into the netd unit namespace the cleanup
                     leg deletes. The cleanup removes `20-*` / `30-*-tunnel.*`; if another role owned
                     one of those, the tidy-up would be an outage.
  7. probe-vocab   — scripts/ansible/probe-net-manager.sh must be able to PRINTER every declared
                     state. A state the operator tool cannot print is a state the next agent will
                     call an anomaly; `ifupdown` is why this rule exists.

Reads no host, runs no playbook: this is the static half. The live half is the role's own assert
block, which measures the box (`service_facts`, `/run/network/ifstate`, `nmcli`, `networkctl`) and
refuses a mismatch at converge time; `scripts/ansible/probe-net-manager.sh` is the read-only verdict.

Self-test:  python3 scripts/gate/check_net_manager.py --self-test
            breeds every rule on a copy of the tree and requires RED each time, plus two controls
            that must stay GREEN (a settled systemd-networkd host with a declared NIC, and an
            ifupdown host whose target is NetworkManager).
Run:        python3 scripts/gate/check_net_manager.py
Exit:       0 = clean · 1 = finding(s) · 2 = could not run (missing corpus).
Wired into scripts/validate-all.sh.
"""
from __future__ import annotations

import fnmatch
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

import yaml

sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import require_corpus, root as _hl_root  # noqa: E402

MANAGER_KEYS = ("network_manager", "network_manager_target")
NETD_TEMPLATE_MARKS = ("netd-phys", "netd-vlan", "netd-tunnel-route")
NETD_DEST_MARKS = ("/etc/systemd/network", "netd_dir")


def _load(path: Path):
    if not path.is_file():
        return None
    return yaml.safe_load(path.read_text(encoding="utf-8"))


# --- inventory + playbook expansion -----------------------------------------------------------

def inventory_groups(ansible: Path) -> dict[str, list[str]]:
    """group -> host list, with `:children` groups flattened. Minimal INI on purpose: this is
    the same grammar inventory.ini uses (one host per line, `#` comments, no inline attrs needed)."""
    inv = ansible / "inventory.ini"
    if not inv.is_file():
        raise FileNotFoundError(str(inv))
    groups: dict[str, list[str]] = {}
    children: dict[str, list[str]] = {}
    section = None
    for raw in inv.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            groups.setdefault(section.split(":")[0], [])
            continue
        if section is None:
            continue
        name = section.split(":")[0]
        if section.endswith(":children"):
            children.setdefault(name, []).append(line.split()[0])
        elif not section.endswith(":vars"):
            host = line.split()[0]
            if host != "localhost":
                groups[name].append(host)
    resolved: dict[str, list[str]] = {}

    def expand(g: str, seen: frozenset[str]) -> list[str]:
        if g in resolved:
            return resolved[g]
        if g in seen:
            return []          # a cycle would be a broken inventory; loud elsewhere, inert here
        out = list(groups.get(g, []))
        for child in children.get(g, []):
            out += expand(child, seen | {g})
        resolved[g] = sorted(set(out))
        return resolved[g]

    for g in list(groups) + list(children):
        expand(g, frozenset())
    return resolved


def network_role_hosts(ansible: Path) -> set[str]:
    """Every host the `network` role is applied to, derived from the playbooks that carry it."""
    groups = inventory_groups(ansible)
    hosts: set[str] = set()
    for pb in sorted(list((ansible / "playbooks").glob("*.yml")) + [ansible / "site.yml"]):
        for play in _load(pb) or []:
            if not isinstance(play, dict):
                continue
            entries = play.get("roles") or []
            names = [e if isinstance(e, str) else str(e.get("role") or e.get("name") or "")
                     for e in entries]
            if "network" not in names:
                continue
            target = play.get("hosts")
            for tgt in ([target] if isinstance(target, str) else (target or [])):
                hosts |= set(groups.get(str(tgt), []))
    return hosts


# --- the declaration corpus -------------------------------------------------------------------

def host_vars(ansible: Path, host: str) -> dict:
    return _load(ansible / "host_vars" / f"{host}.yml") or {}


def declared_kinds(ansible: Path) -> list[str]:
    """The vocabulary lives in the ROLE, so the gate and the role cannot mean different things."""
    kinds = (_load(ansible / "roles/network/vars/main.yml") or {}).get("network_manager_kinds")
    if not isinstance(kinds, list) or not kinds:
        raise ValueError("roles/network/vars/main.yml must define a non-empty network_manager_kinds")
    return [str(k) for k in kinds]


def _role_vars(role_dir: Path) -> dict:
    """The role's own var files, flattened one level — enough to resolve a `{{ ..._dir }}` in a
    dest. A dest built from a variable is invisible to a text scan, and the wireguard role writes its
    netdev units exactly that way, so the namespace rule would be blind to it without this."""
    out: dict[str, str] = {}
    for f in (role_dir / "defaults" / "main.yml", role_dir / "vars" / "main.yml"):
        doc = _load(f)
        if isinstance(doc, dict):
            for k, v in doc.items():
                if isinstance(v, (str, int, float, bool)):
                    out.setdefault(str(k), str(v))
    return out


def _resolve_dest(role_dir: Path, dest: str) -> str:
    if "{{" not in dest:
        return dest
    v = _role_vars(role_dir)
    return re.sub(r"\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}", lambda m: v.get(m.group(1), ""), dest)


def tasks_of(role_dir: Path) -> list[tuple[Path, dict]]:
    out: list[tuple[Path, dict]] = []
    for f in sorted((role_dir / "tasks").rglob("*.yml")):
        doc = _load(f)
        for task in doc or []:
            if isinstance(task, dict):
                out.append((f, task))
    return out


def whens(task: dict) -> list[str]:
    w = task.get("when")
    if w is None:
        return []
    if isinstance(w, (str, dict)):
        w = [w]
    return [str(x) for x in (w if isinstance(w, list) else [w])]


def dest_of(task: dict) -> str:
    for key in ("ansible.builtin.template", "template", "ansible.builtin.file", "file",
                "ansible.builtin.copy", "copy"):
        spec = task.get(key)
        if isinstance(spec, dict) and "dest" in spec:
            return str(spec["dest"])
    return ""


# --- rules ------------------------------------------------------------------------------------

def check(root_dir: Path) -> list[str]:
    ansible = root_dir / "IaC" / "ansible"
    problems: list[str] = []
    kinds = declared_kinds(ansible)
    hosts = network_role_hosts(ansible)
    require_corpus(len(hosts), 2, "hosts the network role is applied to")

    # 1 — declaration
    for host in sorted(hosts):
        hv = host_vars(ansible, host)
        for key in MANAGER_KEYS:
            if key not in hv:
                problems.append(
                    f"declaration: host_vars/{host}.yml declares no {key} — the host the network role "
                    f"writes must state which config-manager owns it (one of: {', '.join(kinds)})")
            elif str(hv[key]) not in kinds:
                problems.append(
                    f"declaration: host_vars/{host}.yml {key}={hv[key]!r} is outside the role's "
                    f"vocabulary {kinds}")
        for gv in sorted((ansible / "group_vars").rglob("*.yml")):
            doc = _load(gv)
            if isinstance(doc, dict) and any(k in doc for k in MANAGER_KEYS):
                problems.append(
                    f"declaration: {gv.relative_to(root_dir)} supplies a config-manager for a whole "
                    f"group — a group value re-imposes the fleet default that host_vars just removed")

    # 2 — no implied facts in the role
    role = ansible / "roles" / "network"
    for f in (role / "defaults" / "main.yml", role / "vars" / "main.yml"):
        doc = _load(f) or {}
        for key in ("netd_phys_name",) + MANAGER_KEYS:
            if key in doc:
                problems.append(
                    f"no-implied: {f.relative_to(root_dir)} defines {key} — a role-level value makes "
                    f"every `is defined` render guard true on every host, which is the defect this "
                    f"gate exists for; the NIC and the manager are facts of the host")

    # 3 — render guards ask the host
    for f, task in tasks_of(role):
        module = _module(task)
        blob = f"{task.get('src', '')} {_resolve_dest(role, dest_of(task))}"
        is_netd_render = module == "template" and (any(m in blob for m in NETD_TEMPLATE_MARKS)
                                                   or any(m in blob for m in NETD_DEST_MARKS))
        if not is_netd_render:
            continue
        if not any(re.search(r"network_manager\s*==\s*['\"]systemd-networkd['\"]", w)
                   for w in whens(task)):
            problems.append(
                f"render-gate: {f.relative_to(root_dir)}: task {task.get('name', '?')!r} renders a "
                f"systemd-networkd unit without gating on the declared manager "
                f"(`network_manager == 'systemd-networkd'`) — a render gated only on var definedness "
                f"is a tautology")

    # 4 — an owed migration freezes the host's legs
    dualhome = (_load(role / "defaults" / "main.yml") or {}).get("network_nm_dualhome_hosts") or []
    dualhome = [str(h) for h in (dualhome if isinstance(dualhome, list) else [])]
    for host in sorted(hosts):
        hv = host_vars(ansible, host)
        owner, target = str(hv.get("network_manager")), str(hv.get("network_manager_target"))
        if owner not in kinds or target not in kinds or owner == target:
            continue
        if "netd_phys_name" in hv:
            problems.append(
                f"freeze: {host} declares an owed migration ({owner} -> {target}) and still "
                f"declares netd_phys_name — a frozen host renders no address leg")
        if host in dualhome:
            problems.append(
                f"freeze: {host} declares an owed migration ({owner} -> {target}) and sits in "
                f"network_nm_dualhome_hosts — the keyfile leg belongs to the host that adopts the "
                f"target manager, not to the one still waiting for an owner-window migrate")
        for key in ("host_resolver_dns", "nm_oldsrv_profile"):
            if key in hv:
                problems.append(
                    f"freeze: {host} declares an owed migration ({owner} -> {target}) and still "
                    f"declares {key} — a resolver leg written under a manager that does not own the "
                    f"box resolves nothing")

    # 5 — the live guard is still there, still fail-loud, still conditioned
    tmain = (role / "tasks" / "main.yml").read_text(encoding="utf-8")
    tasks = tasks_of(role)
    names = [str(t.get("name", "")) for _, t in tasks]
    for needed in ("does not declare its config-manager",
                   "contradict the declaration",
                   "does not own the interface the default route rides"):
        if not any(needed in n for n in names):
            problems.append(f"guard-live: roles/network no longer refuses '{needed}' — the live half "
                            f"of the rule is gone and only this static gate is left")
    for _, task in tasks:
        name = str(task.get("name", ""))
        if "config-manager" not in name and "default route rides" not in name:
            continue
        if "default(" in yaml.safe_dump(task, sort_keys=False):
            problems.append(
                f"guard-live: the refuse task {name!r} uses default() — a fallback in a guard turns "
                f"a refusal into a silent pass")
    problems += live_cases(role / "tasks" / "main.yml", role / "vars" / "main.yml")
    disarm = [t for _, t in tasks
              if str(_module(t)) == "systemd" and "systemd-networkd" in str(_args(t).get("name", ""))
              and _args(t).get("state") == "stopped"]
    if not disarm:
        problems.append("guard-live: no task disarms a second running systemd-networkd, so the drift "
                        "class is a manual act again (a runbook line nobody remembers)")
    else:
        # The safety decision is defined ONCE (net_guard_disarm_ok) and read by both the refusal and
        # the disarm, so the terms are checked where they live — a `when:` that merely names the fact
        # proves nothing on its own.
        decide = next((t for _, t in tasks
                       if isinstance(t.get("ansible.builtin.set_fact"), dict)
                       and "net_guard_disarm_ok" in t["ansible.builtin.set_fact"]), None)
        if decide is None:
            problems.append("guard-live: no task defines net_guard_disarm_ok — the safety decision "
                            "has no single definition, so the refusal and the disarm can drift apart")
        else:
            conds = str(decide["ansible.builtin.set_fact"]["net_guard_disarm_ok"])
            for needed in ("network_manager == 'NetworkManager'", "net_manager_settled",
                           "net_guard_nm_owns_route", "net_guard_networkd_running",
                           "net_guard_networkd_held"):
                if needed not in conds:
                    problems.append(
                        f"guard-live: the disarm decision dropped the condition `{needed}` — without "
                        f"all of them it can stop a manager that is load-bearing (the VPS creates "
                        f"wg-s2s through networkd and would lose the site-to-site tunnel)")
            if not any("net_guard_disarm_ok" in w for w in whens(disarm[0])):
                problems.append("guard-live: the disarm no longer reads net_guard_disarm_ok, so it "
                                "decides safety on its own instead of on the measured decision")
    if not any("after the disarm" in n for n in names):
        problems.append("guard-live: nothing re-reads the devices after the disarm, so 'stopping it "
                        "moves no traffic' is asserted before the act and never after it")

    # 6 — the namespace the cleanup deletes belongs to one role
    namespace = (_load(role / "vars" / "main.yml") or {}).get("netd_unit_namespace") or []
    namespace = [str(p) for p in (namespace if isinstance(namespace, list) else [])]
    if not namespace:
        problems.append("namespace: roles/network/vars/main.yml defines no netd_unit_namespace — the "
                        "cleanup leg would have no stated pattern to delete")
    for role_dir in sorted((ansible / "roles").iterdir()):
        if role_dir.name == "network" or not (role_dir / "tasks").is_dir():
            continue
        for f, task in tasks_of(role_dir):
            dest = _resolve_dest(role_dir, dest_of(task))
            if not any(m in dest for m in NETD_DEST_MARKS):
                continue
            base = dest.rsplit("/", 1)[-1]
            hit = next((p for p in namespace if fnmatch.fnmatch(base, p)), None)
            if hit:
                problems.append(
                    f"namespace: roles/{role_dir.name} writes {base}, which matches the network "
                    f"role's netd namespace ({hit}) — the cleanup leg deletes that pattern on every "
                    f"host that declares no netd leg, so this file would be deleted under its owner")

    # 7 — the operator's probe can print every declared state
    probe = root_dir / "scripts" / "ansible" / "probe-net-manager.sh"
    if not probe.is_file():
        problems.append(f"probe-vocab: {probe.relative_to(root_dir)} does not exist")
    else:
        text = probe.read_text(encoding="utf-8")
        for kind in kinds:
            token = kind if kind != "systemd-networkd" else "networkd"
            if token not in text:
                problems.append(
                    f"probe-vocab: probe-net-manager.sh cannot print the declared state {kind!r} — a "
                    f"state the operator tool cannot name is one the next agent will call an anomaly")
    return problems


def _module(task: dict) -> str:
    for key, val in task.items():
        if key in ("name", "when", "vars", "tags", "become", "notify", "register",
                   "changed_when", "failed_when", "loop", "loop_control", "no_log",
                   "check_mode", "run_once", "block", "rescue", "always"):
            continue
        if isinstance(val, dict) or val is None:
            return str(key).split(".")[-1]
    return ""


def _args(task: dict) -> dict:
    for key, val in task.items():
        if _module(task) == str(key).split(".")[-1]:
            return val or {}
    return {}


# --- the live rule, evaluated offline ---------------------------------------------------------
# The refuses and the disarm are the runtime teeth, and a converge is the only place they usually
# run — which this gate may not do. So the role's OWN jinja is executed here against synthetic
# measurements: the set_fact expressions, the assert conditions and the disarm's `when` list are read
# out of roles/network/{tasks,vars}/main.yml and evaluated, exactly the way
# check_spark_llm_gate.py evaluates the spark profile gate without booting an engine. Editing a guard
# expression in the role therefore changes what this table says; the self-test proves that by editing
# one and requiring RED.

# (label, declared manager, declared target, raw measurement, expected outcome)
# Outcomes: pass | refuse-shape | refuse-owner | refuse-both | disarm
LIVE_CASES = [
    ("one NetworkManager box, networkd off", "NetworkManager", "NetworkManager",
     dict(services={"NetworkManager.service": {"state": "running"}}, route="enp0s31f6",
          ifstate=["lo=lo"], nm_devices={"enp0s31f6": "connected"}),
     "pass"),
    # The drift class: NM owns everything, networkd runs and has taken nothing → refuse the two-manager
    # state, and the disarm is allowed because stopping it moves no address and no route.
    ("NetworkManager declared, networkd also running", "NetworkManager", "NetworkManager",
     dict(services={"NetworkManager.service": {"state": "running"},
                    "systemd-networkd.service": {"state": "running"}},
          route="enP7s7", ifstate=["lo=lo"],
          nm_devices={"enP7s7": "connected", "enP7s7.99": "connected"},
          ctl=[("enP7s7", "unmanaged"), ("lo", "unmanaged"), ("docker0", "unmanaged")]),
     "disarm"),
    # Same two managers, but networkd HAS taken an interface: the disarm would remove a manager that
    # is load-bearing, so only the refusal is allowed.
    ("networkd holds an interface too", "NetworkManager", "NetworkManager",
     dict(services={"NetworkManager.service": {"state": "running"},
                    "systemd-networkd.service": {"state": "running"}},
          route="enP7s7", ifstate=["lo=lo"], nm_devices={"enP7s7": "connected"},
          ctl=[("enP7s7", "unmanaged"), ("wg-x", "configured")]),
     "refuse-shape"),
    # The third state, measured on nas: NM runs and is told to leave the port alone, ifupdown holds it.
    ("the third state: ifupdown owns the uplink", "ifupdown", "NetworkManager",
     dict(services={"NetworkManager.service": {"state": "running"}}, route="eno1",
          ifstate=["eno1=eno1", "lo=lo"],
          nm_devices={"eno1": "unmanaged", "lo": "connected (externally)"}),
     "pass"),
    ("ifupdown declared while networkd runs", "ifupdown", "ifupdown",
     dict(services={"systemd-networkd.service": {"state": "running"}}, route="eno1",
          ifstate=["eno1=eno1", "lo=lo"], ctl=[("eno1", "configured")]),
     "refuse-shape"),
    # The VPS shape: networkd is the declared manager, nothing runs beside it, and eth0's address
    # belongs to the provider image — so the owner rule may not claim anything about that uplink.
    ("netd box whose uplink address is not IaC's", "systemd-networkd", "systemd-networkd",
     dict(services={"systemd-networkd.service": {"state": "running"}}, route="eth0",
          ifstate=["lo=lo", "eth0=eth0"], netd_phys_name=None, ctl=[("eth0", "unmanaged")]),
     "pass"),
    # The defect this row exists for: units rendered for a NIC the box does not have.
    ("netd box declaring the WRONG NIC", "systemd-networkd", "systemd-networkd",
     dict(services={"systemd-networkd.service": {"state": "running"}}, route="eth4",
          ifstate=["lo=lo"], netd_phys_name="eno1"),
     "refuse-owner"),
    # NM runs and networkd runs, but the route is NOT NM's: disarm_ok must stay False, because
    # switching networkd off here could leave the interface with no manager at all.
    ("NM declared, networkd running, route not NM's", "NetworkManager", "NetworkManager",
     dict(services={"NetworkManager.service": {"state": "running"},
                    "systemd-networkd.service": {"state": "running"}},
          route="enP7s7", ifstate=["lo=lo"], nm_devices={"enP7s7": "unmanaged"},
          ctl=[("enP7s7", "unmanaged"), ("lo", "unmanaged")]),
     "refuse-both"),   # both halves refuse: the manager fights, and it does not own the route
    ("NetworkManager declared, ifupdown owns the route", "NetworkManager", "NetworkManager",
     dict(services={"NetworkManager.service": {"state": "running"}}, route="eno1",
          ifstate=["eno1=eno1", "lo=lo"], nm_devices={"eno1": "unmanaged"}),
     "refuse-owner"),
]


def _env():
    """A jinja environment carrying the handful of Ansible filters the guard block uses. Deliberately
    narrow: an unknown filter or test raises, so a role that starts using some other Ansible-only
    helper here is a finding, not a silently unevaluated condition."""
    global _ENV
    if _ENV is None:
        import base64
        import json as _json
        import re as _re

        import jinja2
        env = jinja2.Environment()
        env.filters["split"] = lambda v, sep=":": str(v).split(sep)
        env.filters["b64decode"] = lambda v: base64.b64decode(v).decode("utf-8")
        env.filters["from_json"] = lambda v: _json.loads(v)
        env.filters["regex_search"] = lambda v, pat: (_re.search(pat, str(v)) or None)
        # Ansible's `| bool`, not python truthiness: the string "false" is True in python.
        env.filters["bool"] = lambda v: (str(v).strip().lower()
                                         not in ("", "false", "no", "0", "none")) if isinstance(v, str) else bool(v)
        env.tests["match"] = lambda v, pat: _re.search(pat, str(v)) is not None
        _ENV = env
    return _ENV


_ENV = None


def _eval(expr, ctx: dict):
    """Evaluate one of the role's conditions or templates. Ansible accepts a `that:` item as a bare
    expression and a `set_fact:` value as a `{{ … }}` template, so both spellings are handled — and
    anything that does not parse is a finding, never a silently skipped condition."""
    import jinja2
    text = str(expr).strip()
    # A `set_fact:` value is a `{{ … }}` template; rendering it as a template would stringify a dict
    # and turn every later `.get(...)` into a type error, so a single-expression template is
    # evaluated as the expression itself — which is what Ansible hands the later tasks anyway.
    inner = text[2:-2].strip() if text.startswith("{{") and text.endswith("}}") and text.count("{{") == 1 else None
    try:
        return _env().compile_expression(inner if inner is not None else text)(**ctx)
    except jinja2.TemplateError as exc:      # a guard that cannot be read is a finding, never a skip
        raise RuntimeError(f"cannot evaluate the role's guard expression {text[:90]!r}: {exc}") from exc


def _task_by(tasks_doc, *needles) -> dict:
    for task in tasks_doc:
        name = str(task.get("name", ""))
        if all(n in name for n in needles):
            return task
    raise RuntimeError(f"no task named {' '.join(needles)!r}")


def _raw_ctx(case: dict, manager: str, target: str) -> dict:
    """The measurements, named the way the role names them: registered command results, the fact
    dicts, and the declaration. Everything else the guard reads is DERIVED below by running the
    role's own set_fact expressions."""
    import base64
    import json as _json
    lines = case.get("ifstate")
    ctl = case.get("ctl")
    declared = {} if "netd_phys_name" not in case or case["netd_phys_name"] is None else \
        {"netd_phys_name": case["netd_phys_name"]}
    return {**declared,
        "ansible_check_mode": bool(case.get("check_mode", False)),
        "network_manager": manager,
        "network_manager_target": target,
        # ABSENT, not None: the role's rule is written as `netd_phys_name is defined`, so a fixture
        # that sets it to None would claim "declared" and the case would prove nothing.
        "ansible_facts": {
            "services": case.get("services", {}),
            "default_ipv4": {"interface": case["route"]},
        },
        "net_guard_ifstate_file": {"stat": {"exists": bool(lines)}},
        "net_guard_ifstate_raw": {"content": base64.b64encode(
            "\n".join(lines).encode()).decode() if lines else ""},
        "net_guard_nm_devices": {"stdout_lines": [f"{k}:{v}" for k, v in (case.get("nm_devices") or {}).items()]},
        "net_guard_networkctl": {"stdout": _json.dumps(
            {"Interfaces": [{"Name": n, "AdministrativeState": s} for n, s in (ctl or [])]})},
    }


def _derive(tasks_doc, ctx: dict) -> dict:
    """Run the role's measurement-derivation tasks over the raw facts."""
    for task in tasks_doc:
        for key, expr in (task.get("ansible.builtin.set_fact") or {}).items():
            if str(key).startswith("net_guard"):
                ctx[key] = _eval(expr, ctx)
    return ctx


def live_cases(tasks_main: Path, role_vars_main: Path) -> list[str]:
    problems: list[str] = []
    try:
        tasks_doc = yaml.safe_load(tasks_main.read_text(encoding="utf-8"))
        role_vars = _load(role_vars_main) or {}
        if "net_manager_settled" not in role_vars:
            return ["guard-live: net_manager_settled is gone from roles/network/vars/main.yml, so the "
                    "freeze rule has no definition to evaluate"]
        shape = _task_by(tasks_doc, "contradict the declaration")["ansible.builtin.assert"]["that"]
        owner = _task_by(tasks_doc, "does not own the interface")["ansible.builtin.assert"]["that"]
        disarm = _task_by(tasks_doc, "Disarm the second config-manager")
        dmodule = next(v for k, v in disarm.items() if k.split(".")[-1] == "systemd")
        if dmodule.get("name") != "systemd-networkd" or dmodule.get("state") != "stopped":
            return ["guard-live: the disarm task no longer stops systemd-networkd — the drift class "
                    "is unhandled in this shape"]
        when = whens(disarm)   # a scalar `when:` is one condition, not a sequence of characters
    except (RuntimeError, KeyError, TypeError, StopIteration) as exc:
        return [f"guard-live: cannot read the live guard out of roles/network/tasks/main.yml — {exc}"]

    for label, manager, target, case, expect in LIVE_CASES:
        try:
            # Ansible resolves a role var lazily, so the freeze definition is rendered FIRST: the
            # disarm decision reads it, and evaluating the decision before it would judge a False
            # where the role would see the host's real pair.
            ctx = _raw_ctx(case, manager, target)
            ctx["net_manager_settled"] = _eval(role_vars["net_manager_settled"], ctx)
            ctx = _derive(tasks_doc, ctx)
            shape_ok = all(bool(_eval(c, ctx)) for c in shape)
            owner_ok = all(bool(_eval(c, ctx)) for c in owner)
            held = [i["Name"] for i in json.loads(ctx["net_guard_networkctl"]["stdout"])["Interfaces"]
                    if i["AdministrativeState"] != "unmanaged" and i["Name"] != "lo"]
            disarm_allowed = all(bool(_eval(c, ctx)) for c in when) and not held
        except RuntimeError as exc:
            problems.append(f"guard-live: {label!r}: {exc}")
            continue
        got = ("pass" if (shape_ok and owner_ok) else
               "refuse-both" if not (shape_ok or owner_ok) else
               "refuse-shape" if not shape_ok else "refuse-owner")
        if got == "pass" and disarm_allowed:
            got = "disarm"
        if got != expect:
            problems.append(
                f"guard-live: the case {label!r} must end as {expect} but the role's own conditions end "
                f"as {got} (networkd-held interfaces: {held}) — the live rule no longer separates this "
                f"shape, so a converge would either refuse the wrong box or accept the wrong one")
    return problems


# --- self-test --------------------------------------------------------------------------------

def _mutate(tmp: Path, rel: str, edit) -> None:
    """Round-trip one IaC/ansible YAML file through an edit. Comments are lost in the copy — that is
    fine for a fixture, and is why the canaries assert on structure, never on text."""
    p = tmp / "IaC" / "ansible" / rel
    doc = yaml.safe_load(p.read_text(encoding="utf-8"))
    edit(doc)
    p.write_text(yaml.safe_dump(doc, sort_keys=False, width=200), encoding="utf-8")


def _tasks(doc) -> list:
    return doc if isinstance(doc, list) else []


def _find_task(doc, *needles):
    for task in _tasks(doc):
        name = str(task.get("name", ""))
        if all(n in name for n in needles):
            return task
    raise AssertionError(f"no task matching {needles}")


def self_test(src: Path) -> int:
    fails = 0
    base = check(src)
    if base:
        print(f"CONTROL: the real tree is not clean, so nothing below can be trusted: {base[:3]}")
        return 1
    print(f"control: real tree clean ({len(network_role_hosts(src / 'IaC/ansible'))} hosts checked)")

    def drop_declaration(doc):
        doc.pop("network_manager")

    def bad_value(doc):
        doc["network_manager"] = "openbsd"

    def role_default(doc):
        doc["netd_phys_name"] = "eno1"

    def ungate_render(doc):
        task = _find_task(doc, "physical uplink")
        task["when"] = [w for w in task["when"] if "network_manager" not in str(w)]

    def freeze_leg(doc):
        doc["network_nm_dualhome_hosts"].append("nas.kogler.si")

    def _edit_fact(doc, key, old, new=""):
        for task in _tasks(doc):
            sf = task.get("ansible.builtin.set_fact") or {}
            if key in sf:
                text = str(sf[key])
                assert old in text, f"{old!r} is no longer in {key} — the canary is stale"
                sf[key] = text.replace(old, new)
                return
        raise AssertionError(f"no {key} definition to break")

    def drop_route_condition(doc):
        # The refusal must not disarm a box whose route the declared owner does not even hold.
        _edit_fact(doc, "net_guard_disarm_ok", "and (net_guard_nm_owns_route | bool)")

    def blind_held_probe(doc):
        # Static-only canary: the decision still names every condition, but the probe that answers
        # "did networkd take this interface" stops separating configured from unmanaged, so the
        # self-curing path quietly disappears. Only the live table can see this one.
        _edit_fact(doc, "net_guard_networkd_held",
                   "rejectattr('AdministrativeState', 'equalto', 'unmanaged')",
                   "rejectattr('AdministrativeState', 'equalto', 'nothing-matches-this')")

    def drop_refuse(doc):
        doc[:] = [t for t in _tasks(doc)
                  if "does not own the interface the default route rides" not in str(t.get("name", ""))]

    def foreign_unit(doc):
        task = _find_task(doc, "Render WireGuard .network")
        task["ansible.builtin.template"]["dest"] = "/etc/systemd/network/20-wg-x.network"

    def group_default(doc):
        doc["network_manager"] = "systemd-networkd"

    cases = [
        ("a host stops declaring its manager", ("host_vars/nas.kogler.si.yml", drop_declaration)),
        ("a declaration leaves the vocabulary", ("host_vars/pi.kogler.si.yml", bad_value)),
        ("the role default grows back", ("roles/network/vars/main.yml", role_default)),
        ("a netd render stops asking the host", ("roles/network/tasks/main.yml", ungate_render)),
        ("a frozen host joins the keyfile list", ("roles/network/defaults/main.yml", freeze_leg)),
        ("the disarm loses a safety condition", ("roles/network/tasks/main.yml", drop_route_condition)),
        ("the held-interface probe goes blind", ("roles/network/tasks/main.yml", blind_held_probe)),
        ("a refuse task is deleted", ("roles/network/tasks/main.yml", drop_refuse)),
        ("another role writes in the netd namespace", ("roles/wireguard/tasks/main.yml", foreign_unit)),
        ("a group_vars file re-imposes a manager", ("group_vars/home_servers.yml", group_default)),
    ]
    # canaries: every mutation must turn the checker RED
    for label, (rel, edit) in cases:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td) / "repo"
            shutil.copytree(src, tmp)
            _mutate(tmp, rel, edit)
            got = check(tmp)
            if not got:
                print(f"NOT CAUGHT: {label}")
                fails += 1
            else:
                print(f"caught: {label} -> {got[0].split(':')[0]}")

    # the probe rule needs a file edit, not a YAML rewrite
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td) / "repo"
        shutil.copytree(src, tmp)
        (tmp / "scripts/ansible/probe-net-manager.sh").write_text(
            "#!/usr/bin/env bash\nprintf 'networkd\\n'\n", encoding="utf-8")
        got = check(tmp)
        if not any(p.startswith("probe-vocab") for p in got):
            print(f"NOT CAUGHT: the probe loses a state -> {got[:2]}")
            fails += 1
        else:
            print(f"caught: the probe loses a state -> {got[0][:60]}")

    # controls: shapes that must stay GREEN, so the rules are not merely always-red
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td) / "repo"
        shutil.copytree(src, tmp)
        _mutate(tmp, "host_vars/vps.kogler.si.yml", lambda doc: doc.update(
            {"netd_phys_name": "eth0"}))
        got = check(tmp)
        if got:
            print(f"CONTROL FAILED: a settled netd host with a declared NIC is legal -> {got[:2]}")
            fails += 1
        else:
            print("control green: settled systemd-networkd host with a declared NIC still renders")

    # and the third state must be legal in itself: a host may declare ifupdown with nothing owed.
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td) / "repo"
        shutil.copytree(src, tmp)
        _mutate(tmp, "host_vars/nas.kogler.si.yml", lambda doc: doc.update(
            {"network_manager_target": "ifupdown"}))
        got = check(tmp)
        if got:
            print(f"CONTROL FAILED: an ifupdown host with nothing owed is a legal state -> {got[:2]}")
            fails += 1
        else:
            print("control green: the third state (ifupdown, settled) is legal, not an anomaly")
    return fails


def main() -> int:
    root_dir = _hl_root(__file__)
    if "--self-test" in sys.argv:
        return 1 if self_test(root_dir) else 0
    try:
        problems = check(root_dir)
    except (FileNotFoundError, ValueError) as exc:
        print(f"FAIL: cannot read the corpus: {exc}")
        return 2
    for p in problems:
        print(f"FAIL: {p}")
    if problems:
        return 1
    hosts = network_role_hosts(root_dir / "IaC" / "ansible")
    print(f"OK: {len(hosts)} network-role hosts declare their config-manager "
          f"({', '.join(sorted(h.split('.')[0] for h in hosts))}); "
          "no implied manager, every netd render asks the host")
    return 0


if __name__ == "__main__":
    sys.exit(main())
