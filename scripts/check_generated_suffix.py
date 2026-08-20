#!/usr/bin/env python3
"""Lint: generated docs carry the `-generated` filename suffix (CONVENTIONS §8.2).

Every machine-produced doc (rendered by scripts/Ansible from an IaC/SSOT)
must live at a `*-generated.md` filename, never a hand-authored-looking base.
And no hand-authored doc may wrongly carry the `-generated` suffix.

Two checks:

  * missing — each expected generated file must exist under docs/ at its
    `-generated.md` path (a render target that lost the suffix fails the build).
  * stray   — every `.md` under docs/ whose basename contains `-generated`
    must be one of the known generated outputs. A hand-authored doc that
    picked up `-generated` (or a render that wrote the wrong name) is flagged.

The concrete expected set is the authoritative list in docs/index.md Document
Map + this module's EXPECTED_GENERATED. Keep the two in sync; editing either
without the other should fail closed (this lint surfaces it).

Run:   python scripts/check_generated_suffix.py
Exit:  0 = clean, 1 = violations found.  Wired into `validate-all.sh`.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"

# The canonical machine-generated doc set (CONVENTIONS §8.2 + docs/index.md map).
# SSOT: IaC/ansible group_vars + rack-connections.json. Rendered by:
#   - network-addresses-generated.md   <- scripts/render_network_addresses.py / render-docs.yml
#   - services-inventory-generated.md  <- render-docs.yml / docker_services role
#   - subscriptions-table-generated.md <- render-docs.yml
#   - network-rack-generated.md        <- scripts/render_rack_connections.py (SSOT rack-connections.json)
EXPECTED_GENERATED = {
    "network-addresses-generated.md",
    "services-inventory-generated.md",
    "subscriptions-table-generated.md",
    "network-rack-generated.md",
}


def _on_disk_md() -> list[Path]:
    """All .md under docs/ excluding assets/ and symlinks."""
    out = []
    for p in DOCS.rglob("*.md"):
        if p.is_symlink():
            continue
        rel = p.relative_to(DOCS).as_posix()
        if rel.startswith("assets/"):
            continue
        out.append(p)
    return out


def main() -> int:
    on_disk = {p.name for p in _on_disk_md()}
    bad = False

    # 1) Missing: every expected generated file must exist with the suffix.
    missing = sorted(EXPECTED_GENERATED - on_disk)
    if missing:
        bad = True
        print(f"FAIL: {len(missing)} expected generated doc(s) missing/unsuffixed:")
        for m in missing:
            print(f"  + expected docs/{m}")

    # 2) Stray: a -generated doc that is not in the expected set = a hand
    #    authored doc wrongly carrying the suffix (or an unregistered render).
    stray = [f for f in sorted(on_disk) if "-generated" in f and f not in EXPECTED_GENERATED]
    if stray:
        bad = True
        print(f"\nFAIL: {len(stray)} docs/{'-generated'} filename not in the generated set:")
        for s in stray:
            print(f"  - {s}")

    if bad:
        print("\nSee CONVENTIONS.md §8.2 (Generated docs). Rename the renderer output to "
              "`*-generated.md`, or add the doc to EXPECTED_GENERATED if it is truly machine-produced.")
        return 1

    print(f"OK: {len(EXPECTED_GENERATED)} generated docs carry the -generated suffix; "
          "no hand-authored doc wrongly carries it")
    return 0


if __name__ == "__main__":
    sys.exit(main())