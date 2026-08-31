#!/usr/bin/env python3
"""Lint: the 1Password vault is named `Homelab-ansible` — nothing else.

Flags literal `Homelab` NOT followed by `-ansible` wherever it could be read
as a vault reference (HD-189). The repo renamed its vault to `Homelab-ansible`
(CONVENTIONS §1 / deployment-secrets.md); a stale bare name in prose,
comments or op:// URIs sends humans and scripts at a vault that must not exist.

Scan scope:
  * canonical .md — same rules as check_doc_map.py's _iter_scan_files
    (docs/**, canonical root docs, IaC/**/*.md; brainstorming/, docs/assets/,
    prompt-* handoffs excluded), MINUS reports/changelog.md + reports/deployment-journal.md:
    they are frozen archive and intentionally preserve names as written.
  * IaC/**/*.yml + IaC/**/*.j2 (group_vars, roles, playbooks, templates).
  * scripts/*.py (checker/render docstrings name the vault).

A line is flagged only when it carries vault context (`vault`, `1Password`,
`onepassword`, `op_vault`, `op://`) so project-name prose ("Kogler Homelab"),
Grafana folder names ("Homelab") and Signal group names ("Homelab Alerts")
stay clean without an allowlist.

Run:   python scripts/check_vault_name.py
Exit:  0 = clean, 1 = violations found.  Wired into `validate-all.sh`.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"

# Canonical root docs scanned for links by check_doc_map.py (kept in sync).
ROOT_SCAN = {"README.md", "CONVENTIONS.md", "todo.md",
             "deployment-tasks.md", "readme-humans.md"}

# Bare `Homelab` not followed by `-ansible` (word-boundary keeps `Homelable` out).
# Exception: "Homelab (human)" — the documented human/break-glass vault, distinct
# from the Ansible SA vault (two-vault model, deployment-tasks §0 table B, 2026-08-21):
# those occurrences are stripped before matching.
_HUMAN_VAULT = re.compile(r"\bHomelab \(human\)")
_HOMELAB = re.compile(r"\bHomelab\b(?!-ansible)")
# Vault-context tokens that make a bare `Homelab` a vault reference.
_VAULT_CTX = re.compile(r"vault|1 ?password|onepassword|op_vault|op://", re.IGNORECASE)


def _iter_scan_files() -> list[Path]:
    """Canonical .md (check_doc_map scope; frozen changelog/journal archives in
    reports/ are excluded) plus every IaC yml/j2 and scripts/*.py."""
    files: set[Path] = set()
    if DOCS.is_dir():
        files |= {p for p in DOCS.rglob("*.md") if not p.is_symlink()}
    for name in ROOT_SCAN:
        p = ROOT / name
        if p.exists():
            files.add(p)
    iac = ROOT / "IaC"
    if iac.is_dir():
        files |= set(iac.rglob("*.md"))
        for ext in ("*.yml", "*.yaml", "*.j2"):
            files |= set(iac.rglob(ext))
    scripts = ROOT / "scripts"
    if scripts.is_dir():
        files |= set(scripts.glob("*.py"))
    out = []
    me = Path(__file__).resolve()
    for f in files:
        if f.resolve() == me:
            continue                          # the linter does not flag its own docstring
        rel = f.as_posix()
        if "brainstorming/" in rel or "/assets/" in rel:
            continue
        if f.name.startswith("prompt-"):
            continue
        out.append(f)
    return sorted(out)


def main() -> int:
    violations: list[str] = []
    for path in _iter_scan_files():
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeDecodeError):
            continue
        for lno, line in enumerate(lines, 1):
            probe = _HUMAN_VAULT.sub("", line)   # canonical human-vault spelling is exempt
            if _HOMELAB.search(probe) and _VAULT_CTX.search(probe):
                violations.append(f"{path.relative_to(ROOT)}:{lno}: bare 'Homelab' "
                                  f"vault reference — use 'Homelab-ansible'")
    if violations:
        print(f"FAIL: {len(violations)} stale vault-name reference(s) "
              f"(vault is 'Homelab-ansible'):")
        for v in violations:
            print(f"  - {v}")
        return 1
    scanned = len(_iter_scan_files())
    print(f"OK: no bare 'Homelab' vault references in {scanned} scanned files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
