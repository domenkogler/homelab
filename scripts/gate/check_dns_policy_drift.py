#!/usr/bin/env python3
"""Prove the DNS-policy SSOT and the seed that applies it cannot drift apart.

Beside `check_dns_seed_drift.py`, which guards the RECORD half of the same seed role: that
checker renders which address a name gets, this one guards which BEHAVIOUR the instances run with.
Both exist because the settings they cover were, for a long time, live-state product default that
no file owned — a web-UI change or a version-default shift moved fleet-wide resolver behaviour with
nothing to diff against, and the only sign anything had changed was a `dig` at 3am.

The policy has two halves and this checker treats them differently, on purpose:

  * the APPLIED half — the tuning dict and the block lists — must be written by exactly ONE task,
    with a read-back that compares values. A second task writing the same key is the defect this
    file exists to catch: two owners of one setting is how the tier ended up with `logQueries`
    documented on and switched off.
  * the DECLARED half — `upstreams`, per group — is intent, not state. The pinned Technitium has no
    per-client-group upstream surface (endpoint probe, the shipped console JS and `APIDOCS.md`, all
    in docs/network-dns.md §Per-Subnet DNS Policy), so nothing may wire it. If a future change
    wires it, the doc's capability claim is wrong first and must be corrected in that same change —
    which is what the DECLARED check forces into the open rather than letting a half-built
    "policy" look enforced.

Checks (all offline: no host, no API, no vault):
  A1  every key the owning doc names as drift-prone is present in `technitium_resolver_settings`;
  A2  one writer only — no IaC file outside the dict writes any of those settings keys;
  A3  the seed's write is followed by a value-comparing read-back over the same dict;
  A4  the per-instance override is a subset of the fleet dict (an override key the fleet dict does
      not carry is a key nobody else is accountable for);
  B1  `technitium_dns_policy` names each group once, every group's VLAN exists in `network_vlans`,
      and the group set equals the Group column of the doc's policy table (doc and SSOT agree);
  B2  the declared half stays declared — no IaC file reads `upstreams` out of the policy list;
  B3  a group that declares no block list cannot enable blocking: the seed DERIVES `enableBlocking`
      from the list rather than carrying an independently typed flag.

Run:    python3 scripts/gate/check_dns_policy_drift.py
Exit:   0 = the policy and the seed agree; 1 = drift, or a check that could not run (fail loud —
        an unreadable SSOT or an empty policy list would otherwise pass vacuously).
Wired into `validate-all.sh` + scripts/README.md.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

# HD-1118 discipline: the repo root is FOUND by name, never assumed from a depth.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import root as _hl_root  # noqa: E402

ROOT = _hl_root(__file__)
ANSIBLE = ROOT / "IaC" / "ansible"
SEED = ANSIBLE / "roles/docker_services/tasks/technitium-seed.yml"
DOC = ROOT / "docs/network-dns.md"

# The key set the owning doc names as the un-owned tuning. Naming it HERE (not reading it from the
# dict) is the point: a key quietly dropped from the dict is exactly the drift class, and a checker
# that derived the set from the dict could not see it go.
DOC_NAMED_KEYS = [
    "resolverTimeout", "resolverRetries", "maxConcurrentResolutionsPerCore",
    "cacheMaximumEntries", "dnssecValidation", "qnameMinimization", "serveStale", "logQueries",
]
# Settings whose value the seed owns. A second writer anywhere in IaC is the defect (A2).
OWNED_SETTINGS = DOC_NAMED_KEYS + ["maxLogFileDays", "enableBlocking"]

POLICY_VAR = "technitium_dns_policy"
SETTINGS_VAR = "technitium_resolver_settings"

# Task keys that are modules. A dotted key is always an FQCN action; the short names are the ones
# still written unqualified in this role.
_SHORT_ACTIONS = {"uri", "shell", "command", "copy", "template", "file", "assert", "debug",
                  "set_fact", "lineinfile", "replace", "stat", "slurp", "find", "get_url",
                  "unarchive", "apt", "ping", "script", "service", "systemd", "user", "group",
                  "cron", "pip"}


def _fail(findings: list[str], text: str) -> None:
    findings.append(text)


def _load_group_vars() -> dict:
    out: dict = {}
    for rel in ("group_vars/all/main.yml", "group_vars/all/versions.yml"):
        path = ANSIBLE / rel
        try:
            out.update(yaml.safe_load(path.read_text(encoding="utf-8")) or {})
        except (OSError, yaml.YAMLError) as exc:
            raise RuntimeError(f"cannot parse {path}: {exc}") from exc
    return out


def _walk(node):
    """Every LEAF task dict in a task tree, including inside block/rescue/always.

    A block is not yielded: stringifying one pulls in every task below it, and a containment test
    would then count the same task twice — from the outside in.
    """
    if isinstance(node, dict):
        if not any(k in node for k in ("block", "rescue", "always")):
            yield node
        for key in ("block", "rescue", "always"):
            yield from _walk(node.get(key) or [])
    elif isinstance(node, list):
        for item in node:
            yield from _walk(item)


def _seed_tasks() -> list[dict]:
    try:
        data = yaml.safe_load(SEED.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        raise RuntimeError(f"cannot parse {SEED}: {exc}") from exc
    return list(_walk(data))


def _iac_sources() -> list[Path]:
    """Every IaC file that could write a Technitium setting (group_vars/all excluded — that is
    where the dict lives, and it is checked by name instead of by grep)."""
    skip = {"all"}
    files: list[Path] = []
    for path in sorted(ANSIBLE.rglob("*")):
        if not path.is_file() or path.suffix not in {".yml", ".yaml", ".j2"}:
            continue
        if any(part in {".git", "group_vars"} for part in path.parts):
            continue
        files.append(path)
    for gv in sorted((ANSIBLE / "group_vars").rglob("*.yml")):
        if gv.parent.name not in skip:
            files.append(gv)
    return files


def _doc_group_column() -> set[str]:
    try:
        text = DOC.read_text(encoding="utf-8")
    except OSError as exc:
        raise RuntimeError(f"cannot parse {DOC}: {exc}") from exc
    rows = re.findall(r"^\|\s*([A-Za-z][^|\n]*?)\s*\|\s*([^|\n]*?)\s*\|", text, re.M)
    groups: set[str] = set()
    for source, group in rows:
        if "Source VLAN" in source or source.startswith("---"):
            continue
        for cell in (group, source):
            if re.fullmatch(r"[A-Za-z-]+-Group", cell.strip()):
                groups.add(cell.strip())
    return groups


def main() -> int:
    findings: list[str] = []
    try:
        gv = _load_group_vars()
        tasks = _seed_tasks()
        seed_text = SEED.read_text(encoding="utf-8")
    except RuntimeError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    settings = gv.get(SETTINGS_VAR)
    policy = gv.get(POLICY_VAR)
    if not isinstance(settings, dict) or not settings:
        print(f"FAIL: {SETTINGS_VAR} is missing or empty in group_vars/all/main.yml — the resolver "
              f"tuning has no owner again", file=sys.stderr)
        return 1
    if not isinstance(policy, list) or not policy:
        print(f"FAIL: {POLICY_VAR} is missing or empty — an empty policy list would make every "
              f"check below pass vacuously", file=sys.stderr)
        return 1

    # A1 — the doc's list of drift-prone settings must all be owned by the dict.
    missing = [k for k in DOC_NAMED_KEYS if k not in settings]
    if missing:
        _fail(findings, f"A1: {SETTINGS_VAR} does not carry {missing}; docs/network-dns.md names "
                        f"them as the tuning no role owns")

    # A2 — one writer per setting. The per-instance override block is the one sanctioned exception
    # (it is the same owner speaking per box, and A4 constrains what it may say), so it is stripped
    # before the sweep rather than excused by hand.
    for path in _iac_sources():
        try:
            body = _strip_overrides(path.read_text(encoding="utf-8"))
        except OSError as exc:                      # unreadable is not "clean"
            _fail(findings, f"A2: cannot read {path}: {exc}")
            continue
        if path == SEED:
            continue
        for key in OWNED_SETTINGS:
            if re.search(rf"\b{key}\b\s*:", body):
                _fail(findings, f"A2: {path.relative_to(ROOT)} writes `{key}:` outside "
                                f"{SETTINGS_VAR} — two owners of one resolver setting")

    # A3 — the write must be proved by a read-back that compares values. Tasks nest their arguments
    # under the module key, so the test is on the rendered task, not on a top-level field.
    if SETTINGS_VAR not in seed_text or "_tech_settings_wanted" not in seed_text:
        _fail(findings, f"A3: no seed task builds the wanted settings from {SETTINGS_VAR}")
    writes = [t for t in tasks if "settings/set" in str(t) and "_tech_settings_body" in str(t)]
    if len(writes) != 1:
        _fail(findings, f"A3: expected exactly one seed task posting the built settings body to "
                        f"settings/set, found {len(writes)}")
    if "_tech_settings_wanted | dict2items" not in seed_text:
        _fail(findings, "A3: the settings write has no value-comparing read-back over the wanted "
                        "dict — trusting the POST is the defect this row exists to end")

    # A4 — an override may only change a key the fleet dict already carries.
    for entry in _service_entries():
        name = entry.get("name", "?")
        override = entry.get("technitium_settings")
        if not isinstance(override, dict):
            continue
        stray = sorted(set(override) - set(settings))
        if stray:
            _fail(findings, f"A4: {name}.technitium_settings carries {stray}, which "
                            f"{SETTINGS_VAR} does not define — a per-instance key nobody else owns")

    # A5 — one action per task. `ansible-playbook --syntax-check` does NOT catch a task carrying two
    # action keys; only a run does, and by then the run has already died halfway through a seed.
    for t in tasks:
        actions = [k for k in t if ("." in k) or k in _SHORT_ACTIONS]
        if len(actions) > 1:
            _fail(findings, f"A5: task {t.get('name', '?')!r} declares {sorted(actions)} — "
                            f"'conflicting action statements' kills the run at execution, not at "
                            f"--syntax-check")

    # B1 — the policy list and the doc's table must name the same groups, once each, on real VLANs.
    vlans = {v.get("id") for v in gv.get("network_vlans", [])}
    names: list[str] = []
    for row in policy:
        group, vlan = row.get("group"), row.get("vlan")
        if not group:
            _fail(findings, f"B1: a {POLICY_VAR} entry has no group: {row}")
            continue
        names.append(str(group))
        if vlan not in vlans:
            _fail(findings, f"B1: group {group} names VLAN {vlan}, which network_vlans does not list")
        if "block_lists" not in row or "upstreams" not in row:
            _fail(findings, f"B1: group {group} is missing `block_lists` or `upstreams` — an absent "
                            f"key reads as empty and silently changes the policy")
    dupes = {n for n in names if names.count(n) > 1}
    if dupes:
        _fail(findings, f"B1: {POLICY_VAR} names {sorted(dupes)} more than once")
    doc_groups = _doc_group_column()
    if not doc_groups:
        _fail(findings, "B1: no *-Group cells found in docs/network-dns.md — the policy table moved "
                        "and this checker is now reading nothing")
    elif doc_groups != set(names):
        _fail(findings, f"B1: doc and SSOT name different groups: doc {sorted(doc_groups)} vs "
                        f"{POLICY_VAR} {sorted(set(names))}")

    # B2 — the declared half stays declared.
    for path in _iac_sources():
        try:
            body = path.read_text(encoding="utf-8")
        except OSError as exc:
            _fail(findings, f"B2: cannot read {path}: {exc}")
            continue
        if re.search(r"technitium_dns_policy[^#\n]*upstreams", body):
            _fail(findings, f"B2: {path.relative_to(ROOT)} applies the policy list's `upstreams` — "
                            f"the pin exposes no per-client-group upstream API, so correct "
                            f"docs/network-dns.md §Per-Subnet DNS Policy in the same change")

    # B3 — blocking is derived from the lists, never typed beside them.
    if "technitium_dns_block_lists" not in seed_text:
        _fail(findings, "B3: the seed does not derive enableBlocking from the policy's block lists — "
                        "a typed flag beside the list is how blocking stays on over an empty tier")

    if findings:
        for f in findings:
            print(f"FAIL: {f}", file=sys.stderr)
        print(f"FAIL: {len(findings)} DNS-policy drift finding(s)", file=sys.stderr)
        return 1

    print(f"OK: {len(names)} policy groups, {len(settings)} owned resolver settings, "
          f"one writer, read-back asserted, declared upstreams still declared")
    return 0


def _strip_overrides(text: str) -> str:
    """Blank out `technitium_settings: { … }` override blocks — A4 checks those by name."""
    return re.sub(r"technitium_settings:\s*\{[^}]*\}", "", text)


def _service_entries() -> list[dict]:
    """Every docker_services entry across the host group_vars — the per-instance overrides."""
    out: list[dict] = []
    for path in sorted((ANSIBLE / "group_vars").glob("*.yml")):
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except (OSError, yaml.YAMLError) as exc:
            raise RuntimeError(f"cannot parse {path}: {exc}") from exc
        entries = data.get("docker_services")
        if isinstance(entries, list):
            out.extend(e for e in entries if isinstance(e, dict))
    return out


if __name__ == "__main__":
    sys.exit(main())
