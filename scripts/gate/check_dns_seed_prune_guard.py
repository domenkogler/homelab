#!/usr/bin/env python3
"""Prove the Technitium seed's prune leg cannot delete a record the SSOT lists.

The seed's add half calls `zones/records/add`; its delete half removes what a retirement left
behind. A delete leg on a live DNS tier is only safe because of ONE expression — the per-item
guard on the delete task — and a guard is worth exactly as much as the check that exercises it.
This checker renders THAT expression (read out of the real task, never a copy of it) against
every name the catalog lists, on all three instances, and requires every one of them to evaluate
NOT deletable. Then it requires a retired name to evaluate deletable, because a guard that
refused everything would pass the first half while being dead code.

Why this exists beside `check_dns_seed_drift.py`: that checker renders the SSOT and so cannot see
a record that exists only in live zone state — an orphan survives every static gate and every
re-seed. This file is the guard proof for the leg that acts on live state; it is still a static
check and reads no DNS.

Checks (all offline, no host, no API):
  * the delete task exists, and carries a `when` — a missing guard is RED, never skipped;
  * EVERY name in the keep list (`zone_kogler_si_all_names`) evaluates NOT deletable, per instance
    — the refusal;
  * every name on the retirement ledger evaluates deletable — the teeth;
  * the ledger and the keep list are disjoint — a name cannot be both listed and retired;
  * both sets are non-trivial — an empty keep list would make the refusal pass vacuously.

`--self-test` mutates the guard in a throwaway copy and requires the verdict to go RED three ways:
a guard that refuses nothing, a guard that allows nothing, and a ledger that names a listed name.
Without those, "the guard refuses every listed record" would be a sentence about a checker that
cannot fail.

Run:    python3 scripts/gate/check_dns_seed_prune_guard.py [--self-test]
Exit:   0 = guard holds; 1 = the prune leg could delete something it must not (or has gone dead).
Wired into `validate-all.sh` + scripts/README.md.
"""
from __future__ import annotations

import argparse
import ast
import sys
import tempfile
from pathlib import Path

import yaml

# HD-1118 discipline: find the repo root and the render module by name, not by depth.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import root as _hl_root  # noqa: E402
sys.path.insert(0, str(_hl_root(__file__) / "scripts" / "ansible"))
import zone_kogler_si_render as zr  # noqa: E402  # renders the REAL seed task

ROOT = _hl_root(__file__)
ANSIBLE = ROOT / "IaC" / "ansible"
SEED_FILE = ANSIBLE / "roles/docker_services/tasks/technitium-seed.yml"
DELETE_TASK = "Technitium: delete retired records the zone still holds ({{ svc.name }})"
INSTANCES = ["primary", "secondary", "secondary-pi"]
# Floor, not a count to keep current: below this the keep list is a render that went wrong, and an
# empty keep list would turn the whole refusal check into a pass that proves nothing.
KEEP_FLOOR = 10


def _ssot_vars() -> dict:
    out: dict = {}
    for rel in ("group_vars/all/main.yml", "group_vars/all/versions.yml"):
        p = ANSIBLE / rel
        try:
            out.update(yaml.safe_load(p.read_text(encoding="utf-8")) or {})
        except (OSError, yaml.YAMLError) as exc:
            raise zr.RenderError(f"cannot parse {p}: {exc}") from exc
    return out


def _walk_tasks(node):
    if isinstance(node, dict):
        if node.get("name") == DELETE_TASK:
            yield node
        for key in ("block", "rescue", "always"):
            yield from _walk_tasks(node.get(key) or [])
    elif isinstance(node, list):
        for item in node:
            yield from _walk_tasks(item)


def _guard(path: Path) -> str:
    """The delete task's per-item `when`, verbatim — the guard under test, not a paraphrase."""
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        raise zr.RenderError(f"cannot parse {path}: {exc}") from exc
    for task in _walk_tasks(doc):
        when = task.get("when")
        if when is None:
            raise zr.RenderError(
                f"task {DELETE_TASK!r} has no `when` — the prune leg has no guard, so it would "
                "delete every ledger name on every instance whatever the SSOT lists")
        return str(when)
    raise zr.RenderError(f"delete task {DELETE_TASK!r} not found in {path} — the check would be vacuous")


def _keep_list(gv: dict, instance: str) -> list[str]:
    """`zone_kogler_si_all_names` rendered to real strings for one instance."""
    ctx = zr.build_context(extra={"svc": {"instance": instance}})
    try:
        out = zr._render_expr(gv["zone_kogler_si_all_names"], ctx)
    except (zr.RenderError, KeyError) as exc:
        raise zr.RenderError(f"cannot render the keep list for {instance}: {exc}") from exc
    try:
        names = ast.literal_eval(out)
    except (ValueError, SyntaxError) as exc:
        raise zr.RenderError(f"keep list for {instance} is not a list: {out[:80]!r}") from exc
    if not isinstance(names, list) or not all(isinstance(n, str) for n in names):
        raise zr.RenderError(f"keep list for {instance} is not a list of names: {out[:80]!r}")
    return [n.lower() for n in names]


def _deletes(guard: str, gv: dict, name: str, instance: str) -> bool:
    """Does the real guard select `name` for deletion on `instance`?"""
    ctx = zr.build_context(extra={"svc": {"instance": instance}})
    ctx["zone_kogler_si_all_names"] = _keep_list(gv, instance)
    out = zr._render_expr(guard, dict(ctx, item={"name": name, "ip": "192.0.2.1"}), is_expr=True)
    if out.strip() not in ("True", "False"):
        raise zr.RenderError(f"guard for {name!r} on {instance} is not a boolean: {out[:80]!r}")
    return out.strip() == "True"


def verdict(path: Path = SEED_FILE, ledger_override: list[str] | None = None) -> list[str]:
    """Every way the prune leg can be unsafe, as findings. Empty list = the guard holds.

    `ledger_override` exists for the self-test's contradiction canary, so the canary exercises
    THIS function rather than a paraphrase of it.
    """
    findings: list[str] = []
    gv = _ssot_vars()
    guard = _guard(path)

    keep_by_inst = {inst: _keep_list(gv, inst) for inst in INSTANCES}
    for inst, keep in keep_by_inst.items():
        if len(keep) < KEEP_FLOOR:
            findings.append(f"{inst}: keep list holds {len(keep)} names (<{KEEP_FLOOR}) — the "
                            "refusal check cannot be meaningful against an emptied zone SSOT")

    ledger = ([str(n).lower() for n in (ledger_override if ledger_override is not None
                                        else (gv.get("zone_kogler_si_retired") or []))])
    if not ledger:
        findings.append("the retirement ledger is empty — nothing exercises the delete leg, so a "
                        "guard that refuses everything would look identical to a correct one")

    for inst, keep in keep_by_inst.items():
        for name in keep:
            if _deletes(guard, gv, name, inst):
                findings.append(f"{inst}: {name} is LISTED in zone_kogler_si yet the prune guard "
                                "selects it for deletion — the leg could remove a live record")
        for name in ledger:
            if name in keep:
                findings.append(f"{inst}: {name} is both listed and retired — the ledger must name "
                                "a service the catalog no longer has")
            elif not _deletes(guard, gv, name, inst):
                findings.append(f"{inst}: {name} is retired but the guard refuses to delete it — "
                                "the prune leg has no teeth and the orphan survives every re-seed")
    return findings


def _mutated(seed: Path, old: str, new: str) -> Path:
    """A throwaway copy of the seed file with the guard rewritten — the canary's fixture."""
    text = seed.read_text(encoding="utf-8")
    if old not in text:
        raise zr.RenderError(f"self-test fixture does not match the seed any more: {old!r}")
    tmp = Path(tempfile.mkdtemp(prefix="hl-prune-")) / "technitium-seed.yml"
    tmp.write_text(text.replace(old, new), encoding="utf-8")
    return tmp


def self_test() -> int:
    """Each mutation must turn the verdict RED. A silent canary is a missing canary."""
    cases = [
        ("a guard that refuses nothing",
         "when: item.name not in zone_kogler_si_all_names", "when: 'true'"),
        ("a guard that allows nothing (a dead leg)",
         "when: item.name not in zone_kogler_si_all_names", "when: 'false'"),
    ]
    failed = 0
    for label, old, new in cases:
        got = verdict(_mutated(SEED_FILE, old, new))
        print(f"  canary: {label}: {'RED as required' if got else 'GREEN — the check is blind'}")
        if not got:
            failed += 1
    # The contradiction canary: force a listed name into the ledger and require RED from the same
    # verdict function the gate runs.
    listed = _keep_list(_ssot_vars(), "primary")[0]
    got = verdict(SEED_FILE, ledger_override=[listed])
    print(f"  canary: ledger names a listed record ({listed}): "
          f"{'RED as required' if got else 'GREEN — the check is blind'}")
    if not got:
        failed += 1
    return 1 if failed else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true", help="prove the guard check can fail")
    args = ap.parse_args()
    try:
        if args.self_test:
            print("check_dns_seed_prune_guard --self-test")
            return self_test()
        findings = verdict()
    except zr.RenderError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    if findings:
        print("FAIL: the DNS seed's prune guard is not safe:", file=sys.stderr)
        for f in findings:
            print(f"  - {f}", file=sys.stderr)
        return 1
    print("OK: the prune leg refuses every record zone_kogler_si lists and still removes a retired one")
    return 0


if __name__ == "__main__":
    sys.exit(main())
