#!/usr/bin/env python3
"""render_all.py — unified entry point for every SSOT → generated-doc render.

Consolidates (HD-163): a single pure-Python entry over the previously scattered
render paths, so **no Ansible / WSL / 1Password CLI is needed** to regenerate
every `*-generated.md` doc on this Windows host.

Rendered outputs (do NOT hand-edit — SSOT direction is IaC → generated):
    docs/network-addresses-generated.md   <- group_vars/all/main.yml + host_vars   [render_network_addresses.py]
    docs/services-inventory-generated.md  <- docker_services (all Docker hosts) [inline, Ansible hostvars-equivalent]
    docs/subscriptions-table-generated.md <- group_vars/subscriptions.yml      [inline]
    docs/network-rack-generated.md        <- docs/rack-connections.json        [render_rack_connections.py]
    docs/rack-layout.mmd                  <- docs/rack-connections.json        [render_rack_connections.py]

Design (HD-163 decision B): the two single-purpose renderers
`render_network_addresses.py` and `render_rack_connections.py` remain the
authoritative implementations and are **imported** (not re-implemented). The
inventory + subscription renders previously existed only as Ansible playbook
tasks; those two are implemented here in pure Python.

NOT covered (intentionally out of scope): `IaC/ansible/playbooks/render-routeros.yml`
injects 1Password secrets into device `.rsc` bootstrap files — stays Ansible-only.

Usage:
    python scripts/render_all.py               # render everything (default: all)
    python scripts/render_all.py network-addresses
    python scripts/render_all.py inventory
    python scripts/render_all.py subscriptions
    python scripts/render_all.py rack
    python scripts/render_all.py all
    python scripts/render_all.py --check        # render then diff vs index; exit 1 on drift (no tree mutation)

After any edit to `group_vars/*.yml` / `host_vars/*.yml` / `rack-connections.json`,
run `python scripts/render_all.py`, then `bash scripts/validate-all.sh`, then
`git diff --exit-code` to confirm no unintended drift.
"""
from __future__ import annotations

import argparse
import importlib
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml
from jinja2 import Environment, StrictUndefined

ROOT = Path(__file__).resolve().parent.parent
ANSIBLE = ROOT / "IaC" / "ansible"
DOCS = ROOT / "docs"
GROUP_VARS = ANSIBLE / "group_vars"
HOST_VARS = ANSIBLE / "host_vars"
TEMPLATES = ANSIBLE / "templates"

# Canonical managed-header for every generated doc. MUST equal Ansible's built-in
# `ansible_managed` value so render_all.py and a real Ansible render stay byte-
# identical: the templates emit `{{ ansible_managed | comment }}` → `# Ansible managed`.
MANAGED = "Ansible managed"

# Host key (Ansible inventory FQDN) -> docker_services group vars file.
# Order dictates section order in services-inventory-generated.md.
DOCKER_HOST_GROUPVARS = [
    ("vps.kogler.si", "vps.yml"),
    ("oldsrv.kogler.si", "home_servers.yml"),
    ("pi.kogler.si", "raspberry_pi.yml"),
]


def _load_yml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def _render_template(template_path: Path, dest: Path, ctx: dict) -> None:
    env = Environment(undefined=StrictUndefined, trim_blocks=True, lstrip_blocks=True)

    def comment(text, style="plain", begin="", end="", decoration="#"):
        result = []
        lines = text.split("\n")
        if style == "plain":
            if begin:
                result.append(begin)
            for line in lines:
                result.append(f"{decoration} {line}")
            if end:
                result.append(end)
        return "\n".join(result)

    env.filters["comment"] = comment
    rendered = env.from_string(template_path.read_text(encoding="utf-8")).render(**ctx)
    dest.write_text(rendered, encoding="utf-8", newline="\n")
    print(f"Rendered {dest.resolve()}")


def _iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# --------------------------------------------------------------------------- #
# Renderers — each returns the list of files it produced.
# --------------------------------------------------------------------------- #
def render_network_addresses() -> list[Path]:
    mod = importlib.import_module("render_network_addresses")
    rc = mod.main()
    if rc != 0:
        raise SystemExit(f"render_network_addresses.py exited {rc}")
    return [DOCS / "network-addresses-generated.md"]


def render_inventory() -> list[Path]:
    all_hostvars = []
    for host, groupfile in DOCKER_HOST_GROUPVARS:
        gv = _load_yml(GROUP_VARS / groupfile)
        svcs = gv.get("docker_services")
        if svcs is None:
            continue
        all_hostvars.append({"key": host, "value": {"_docker_services": svcs}})

    all_yml = _load_yml(GROUP_VARS / "all" / "main.yml")
    ctx = {
        "ansible_managed": MANAGED,
        "ansible_date_time": {"iso8601": _iso_now()},
        "all_hostvars": all_hostvars,
        "domain_public": all_yml.get("domain_public", "kogler.si"),
    }
    dest = DOCS / "services-inventory-generated.md"
    _render_template(TEMPLATES / "inventory.md.j2", dest, ctx)
    return [dest]


def render_subscriptions() -> list[Path]:
    subs = _load_yml(GROUP_VARS / "subscriptions.yml")
    ctx = {
        "ansible_managed": MANAGED,
        "ansible_date_time": {"iso8601": _iso_now()},
        "subscriptions": subs.get("subscriptions", []),
    }
    dest = DOCS / "subscriptions-table-generated.md"
    _render_template(TEMPLATES / "subscription-table.md.j2", dest, ctx)
    return [dest]


def render_rack() -> list[Path]:
    mod = importlib.import_module("render_rack_connections")
    rc = mod.main()
    if rc != 0:
        raise SystemExit(f"render_rack_connections.py exited {rc}")
    return [DOCS / "network-rack-generated.md", DOCS / "rack-layout.mmd"]


_JOBS = {
    "network-addresses": render_network_addresses,
    "inventory": render_inventory,
    "subscriptions": render_subscriptions,
    "rack": render_rack,
}


def _run_target(name: str) -> list[Path]:
    return _JOBS[name]()


def _run_all() -> None:
    for name in _JOBS:
        _JOBS[name]()


def _check_target(name: str) -> bool:
    """Snapshot each produced file, run the renderer, then `git diff` each produced
    file against the index (committed) state. Returns True if any drifted. The
    working tree is restored to its pre-run state on completion."""
    produced = _run_target(name)
    snapshots = [(p, p.read_bytes() if p.exists() else None) for p in produced]
    try:
        drifted = False
        for dest in produced:
            if not dest.exists():
                print(f"DRIFT  {dest.name}: renderer produced nothing")
                drifted = True
                continue
            rc = subprocess.run(
                ["git", "diff", "--exit-code", "--", str(dest)],
                capture_output=True,
                text=True,
            )
            if rc.returncode != 0:
                print(f"DRIFT  {dest.name}: differs from committed index state")
                drifted = True
            else:
                print(f"ok     {dest.name}: matches index")
    finally:
        for p, b in snapshots:
            if b is None:
                p.unlink(missing_ok=True)
            else:
                p.write_bytes(b)
    return drifted


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument(
        "target",
        nargs="?",
        default="all",
        choices=["all", *list(_JOBS)],
        help="which render(s) to run (default: all)",
    )
    ap.add_argument(
        "--check",
        action="store_true",
        help="render then git-diff against the committed (index) state; exit 1 on drift (tree not mutated)",
    )
    args = ap.parse_args()

    if args.check:
        targets = list(_JOBS) if args.target == "all" else [args.target]
        any_drift = False
        for name in targets:
            if _check_target(name):
                any_drift = True
        return 1 if any_drift else 0

    if args.target == "all":
        _run_all()
    else:
        _run_target(args.target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())