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
    python scripts/render_all.py --check        # render then diff vs index; exit 1 on drift; tree restored to its pre-run state
    python scripts/render_all.py --self-test    # prove --check can read green twice AND still redden, in a throwaway repo

Determinism: a rendered file is a pure function of its SSOT, so `--check` can read green on an
up-to-date tree. No render context carries a wall clock — see CONVENTIONS.md §8.5.

After any edit to `group_vars/*.yml` / `host_vars/*.yml` / `rack-connections.json`,
run `python scripts/render_all.py`, then `bash scripts/validate-all.sh`, then
`git diff --exit-code` to confirm no unintended drift.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml
from jinja2 import Environment, StrictUndefined

# HD-1118 Stage 1: FOUND, not assumed from a depth — scripts/lib/repo_root.py.
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents
                            if p.name == "scripts") / "lib"))
from repo_root import root as _hl_root, script_path as _hl_script_path  # noqa: E402
ROOT = _hl_root(__file__)
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



# --------------------------------------------------------------------------- #
# Renderers — each returns the list of files it produced.
# --------------------------------------------------------------------------- #
def _load_renderer(name: str):
    """Import a renderer by NAME from wherever it lives (HD-1118 Stage 1).

    `importlib.import_module("render_network_addresses")` only ever worked because
    the renderer sat in THIS file's directory (sys.path[0] is the script dir). That
    is a same-directory assumption wearing an import: Stage 3 moves the renderers
    into `ansible/` and this umbrella stays at the root, so the module name would
    stop resolving — and the shape of the failure is the bad part, not a red gate.
    Looking the name up under `scripts/**` keeps the tree written down in one place
    (no literal name→path map to fall out of step with the move).
    """
    path = _hl_script_path(f"{name}.py", __file__)
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"render_all: cannot load renderer {path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def render_network_addresses() -> list[Path]:
    mod = _load_renderer("render_network_addresses")
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
        "subscriptions": subs.get("subscriptions", []),
    }
    dest = DOCS / "subscriptions-table-generated.md"
    _render_template(TEMPLATES / "subscription-table.md.j2", dest, ctx)
    return [dest]


def render_rack() -> list[Path]:
    mod = _load_renderer("render_rack_connections")
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


def _snapshot_generated() -> dict[Path, bytes | None]:
    """Every file a renderer can overwrite, read BEFORE anything is written.

    The set is the repo's own naming rule (CONVENTIONS §8.2: machine-produced docs carry
    `-generated.md`) applied to `docs/` — the only dir the jobs write into — plus the one
    non-md output. That is a SAFE SUPERSET of what the jobs produce, so no path is listed
    twice and a new renderer needs no edit here.
    """
    paths = list(dict.fromkeys(sorted(DOCS.glob("*-generated.md")) + [DOCS / "rack-layout.mmd"]))
    return {p: (p.read_bytes() if p.exists() else None) for p in paths}


def _check_target(name: str) -> bool:
    """Render, then `git diff` each produced file against the index (committed) state; returns
    True if any drifted. The working tree is restored to its **pre-run** state afterwards.

    ⚠ The snapshot must be taken BEFORE the render. It used to be taken after `_run_target()`, so
    the "restore" wrote back the bytes the renderer had just produced: `--check` left the tree
    MUTATED while its own help said "tree not mutated", and — worse — any uncommitted edit to a
    generated doc was replaced by the render and then restored as the render, so the edit was
    destroyed on a command that promised not to touch the tree. Measured 2026-10-09: `--check` on
    a clean tree left 2 files dirty, and run from the primary checkout on `main` that dirtiness is
    a CONVENTIONS §6 hard gate failure. The `--self-test` below asserts this restore, and it runs
    in a throwaway repo reached through `$REPO` — so the fixture's `docs/` takes the writes and
    this tree never does.
    """
    snap = _snapshot_generated()
    produced = _run_target(name)
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
        for p, b in snap.items():
            if b is None:
                p.unlink(missing_ok=True)
            else:
                p.write_bytes(b)
    return drifted


# --------------------------------------------------------------------------- #
# Self-test — the proof that `--check` can read green (CONVENTIONS §6: a test that
# cannot fail is not evidence).
#
# Why these arms and not a mocked diff: a wall clock stamped into a render makes its own
# `--check` red forever — the diff is the clock, not the data — and the only way to SEE that is
# to run the check twice over a real render of real templates. So the legs run the real entry
# point against a throwaway git repo whose root is handed over with `$REPO` (the fixture hook in
# `lib/repo_root.py`): `--check` writes into `docs/`, and the fixture's `docs/` is the one thing
# this may touch. The templates are the repo's OWN files, copied in — a fixture template of my
# own invention could stay clock-free while the real one stamped a time.
# --------------------------------------------------------------------------- #

# A minimal SSOT shaped like the real one: TEST-NET/EXAMPLE values only, never a homelab value.
_FIXTURE_ALL_MAIN = """\
network_vlans:
  - {id: 10, name: Home, subnet: 192.0.2.0/24, pool: "192.0.2.100-192.0.2.199", ssid: fixture}
network_static_hosts:
  - {name: oldsrv, vlan: 10, ip: 192.0.2.10, role: fixture server}
  - {name: pi, vlan: 10, ip: 192.0.2.12, role: fixture pi}
network_ranges:
  - {name: mgmt, cidr: 198.51.100.0/24, purpose: fixture management}
ha_vip: 192.0.2.200
dns_primary_ip: 203.0.113.10
domain_public: example.invalid
"""

_FIXTURE_DOCKER = {
    "vps.yml": "docker_services:\n  - {name: kopia, subdomain: backup}\n",
    "home_servers.yml": "docker_services:\n  - {name: traefik, subdomain: edge}\n",
    "raspberry_pi.yml": "docker_services:\n  - {name: technitium, subdomain: dns}\n",
}

# target -> (template it renders from, doc it writes, SSOT file to mutate, (old, new) for the
# mutation arm). One entry per template that ever carried a stamp.
_FIXTURE_TARGETS = {
    "network-addresses": ("network-addresses.md.j2", "network-addresses-generated.md",
                          "IaC/ansible/group_vars/all/main.yml", ("192.0.2.10", "192.0.2.11")),
    "inventory": ("inventory.md.j2", "services-inventory-generated.md",
                  "IaC/ansible/group_vars/vps.yml", ("name: kopia", "name: kopia-renamed")),
}

_GIT_BASE = ["-c", "commit.gpgsign=false", "-c", "core.autocrlf=false",
             "-c", "user.name=render-self-test", "-c", "user.email=self-test@invalid"]


def _git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    """git inside the fixture only. `commit.gpgsign=false` because a signing key an agent has to
    ask about would BLOCK the fixture commit — the trap CONVENTIONS §6 records for real commits."""
    return subprocess.run(["git", *_GIT_BASE, *args], cwd=str(repo),
                          capture_output=True, text=True)


def _run_self(args: list[str], repo: Path) -> subprocess.CompletedProcess:
    """One run of THIS entry point against a fixture root ($REPO is the fixture hook)."""
    return subprocess.run([sys.executable, str(Path(__file__).resolve()), *args],
                          cwd=str(repo), env={**os.environ, "REPO": str(repo)},
                          capture_output=True, text=True)


def _fixture(repo: Path) -> None:
    """A mini-tree that is a repo by the lib's own markers, with the REAL render templates."""
    (repo / "IaC" / "ansible" / "group_vars" / "all").mkdir(parents=True, exist_ok=True)
    tpl = repo / "IaC" / "ansible" / "templates"
    tpl.mkdir(parents=True, exist_ok=True)
    (repo / "docs").mkdir(parents=True, exist_ok=True)
    (repo / "docs" / "index.md").write_text("# fixture index\n", encoding="utf-8")
    (repo / "IaC" / "ansible" / "group_vars" / "all" / "main.yml").write_text(
        _FIXTURE_ALL_MAIN, encoding="utf-8")
    for name, body in _FIXTURE_DOCKER.items():
        (repo / "IaC" / "ansible" / "group_vars" / name).write_text(body, encoding="utf-8")
    for name, _, _, _ in _FIXTURE_TARGETS.values():
        shutil.copy(TEMPLATES / name, tpl / name)


def self_test() -> int:
    """Run the legs; returns the number of arms NOT caught."""
    arms = fails = 0

    def arm(ok: bool, name: str, detail: str = "") -> None:
        nonlocal arms, fails
        arms += 1
        if ok:
            print(f"  ok   {name}")
        else:
            fails += 1
            print(f"  FAIL {name}" + (f" — {detail}" if detail else ""))

    tmp = Path(tempfile.mkdtemp(prefix="render-all-selftest-"))
    try:
        for target, (tpl_name, doc_name, ssot_rel, (old, new)) in _FIXTURE_TARGETS.items():
            repo = tmp / target
            repo.mkdir(parents=True)
            if _git(repo, "init", "-q").returncode != 0:
                raise SystemExit("render_all --self-test: git is unavailable, the fixture legs "
                                 "cannot run — a check that never executed is not a green")
            _fixture(repo)
            setup = _run_self([target], repo)
            if setup.returncode != 0:
                raise SystemExit(f"render_all --self-test: the fixture cannot render "
                                 f"{target}: {(setup.stderr or setup.stdout).strip()[-400:]}")
            _git(repo, "add", "-A")
            committed = _git(repo, "commit", "-q", "--no-verify", "-m", "fixture")
            if committed.returncode != 0:
                raise SystemExit(f"render_all --self-test: fixture commit failed: "
                                 f"{committed.stderr.strip()[-400:]}")
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()

            first = _run_self(["--check", target], repo)
            arm(first.returncode == 0, f"{target}: --check is green on an up-to-date tree",
                (first.stdout or first.stderr).strip()[-200:])
            second = _run_self(["--check", target], repo)
            arm(second.returncode == 0,
                f"{target}: --check is green a SECOND time (a stamped clock reddens here)",
                (second.stdout or second.stderr).strip()[-200:])
            dirty = _git(repo, "status", "--porcelain").stdout.strip()
            arm(dirty == "", f"{target}: --check left the tree exactly as it found it",
                f"dirty: {dirty!r}")

            # mutation: a real SSOT change must still redden the check — the arms above pass for an
            # always-green check too, so without this one they prove nothing.
            ssot = repo / ssot_rel
            original = ssot.read_text(encoding="utf-8")
            if old not in original:
                arm(False, f"{target}: the SSOT value to mutate is present", f"{ssot_rel} has no {old!r}")
            else:
                ssot.write_text(original.replace(old, new, 1), encoding="utf-8")
                mutated = _run_self(["--check", target], repo)
                arm(mutated.returncode != 0 and doc_name in mutated.stdout,
                    f"{target}: a changed SSOT value reddens it", "check stayed green on a real change")
                ssot.write_text(original, encoding="utf-8")

            # a hand edit is a FORBIDDEN act against a render view (CONVENTIONS §8.2), and what
            # `--check` owes here is narrower than it looks: the diff is SSOT-render vs the INDEX, so
            # an UNCOMMITTED edit is not drift — it must instead come back unharmed (the 2026-10-09
            # bug was `--check` quietly replacing it), and a COMMITTED one must redden.
            doc = repo / "docs" / doc_name
            doc.write_text(doc.read_text(encoding="utf-8") + "\n<!-- hand-edited -->\n",
                           encoding="utf-8")
            handed = _run_self(["--check", target], repo)
            arm("hand-edited" in doc.read_text(encoding="utf-8"),
                f"{target}: --check does not destroy an uncommitted edit to a render view",
                (handed.stdout or handed.stderr).strip()[-200:])
            _git(repo, "add", "-A")
            _git(repo, "commit", "-q", "--no-verify", "-m", "hand edit")
            committed_edit = _run_self(["--check", target], repo)
            arm(committed_edit.returncode != 0 and doc_name in committed_edit.stdout,
                f"{target}: a COMMITTED hand edit of a render view reddens it",
                "check stayed green over a hand edit")
            _git(repo, "reset", "--hard", "-q", base)

            # the fix is structural, not a deleted line: the render context carries no clock, so a
            # template that asks for one DIES instead of stamping it.
            tpl = repo / "IaC" / "ansible" / "templates" / tpl_name
            tpl.write_text(tpl.read_text(encoding="utf-8") + "\n> {{ ansible_date_time.iso8601 }}\n",
                           encoding="utf-8")
            clock = _run_self([target], repo)
            arm(clock.returncode != 0,
                f"{target}: a template that asks for a wall clock cannot render",
                "the clock is back in the context")
        print(f"SELF-TEST {'FAIL' if fails else 'OK'}: {arms} arms, {fails} failure(s)")
        return fails
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


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
        help="render then git-diff against the committed (index) state; exit 1 on drift (the tree is restored to its pre-run state)",
    )
    ap.add_argument(
        "--self-test",
        action="store_true",
        help="prove --check can read green twice and still redden, in a throwaway fixture repo (nothing is written into this tree)",
    )
    args = ap.parse_args()

    if args.self_test:
        return 1 if self_test() else 0

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