#!/usr/bin/env python3
"""Lint: every vault item the IaC reads is documented in the secrets master list.

`docs/deployment-secrets.md` §Master Secret List is the human-facing catalog a from-zero deployer
works from: the runbook tells them to seed what §1.1/§P3.1 lists, and `check-vault-items.sh`
answers "does the vault HAVE it". Neither answers the other question — **"is the item written
down anywhere?"** — and the answer was silently wrong for five items (`technitium_login` among
them: a hard gate whose absence fails the very first DNS seed of a true-zero rebuild).

The check derives the required set from the IaC itself, not from a hand-kept list:
  * every `lookup('community.general.onepassword', '<item>' ...)` in the playbooks/roles, and
  * every item named in `roles/docker_services/defaults/main.yml` `_service_vault_items`
    (declared-but-unconsumed entries count too — a scanner-required item has to be documented
    even if no task reads it yet; the doc row is where that oddity gets explained).

Run:   python3 scripts/check_vault_docs.py [--root DIR]
Exit:  0 = every referenced item is documented, 1 = undocumented items.  Wired into validate-all.sh.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT_DEFAULT = Path(__file__).resolve().parent.parent
LOOKUP_RE = re.compile(r"onepassword['\"]\s*,\s*['\"]([a-z0-9_.-]+)['\"]")
LOOKUP_CALL_RE = re.compile(r"onepassword\(\s*['\"]([a-z0-9_.-]+)['\"]")


def referenced_items(root: Path) -> dict[str, set[str]]:
    refs: dict[str, set[str]] = {}
    ansible = root / "IaC" / "ansible"
    for path in list(ansible.rglob("*.yml")) + list(ansible.rglob("*.j2")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        for found in (LOOKUP_RE.findall(text) + LOOKUP_CALL_RE.findall(text)):
            refs.setdefault(found, set()).add(str(path.relative_to(root)))
    defaults = ansible / "roles" / "docker_services" / "defaults" / "main.yml"
    if defaults.exists():
        for line in defaults.read_text(encoding="utf-8").splitlines():
            for item in re.findall(r"'([a-z0-9_.-]+)'", line):
                if item.endswith(("_api", "_login", "_password", "_db")) and "<" not in item:
                    refs.setdefault(item, set()).add(f"{defaults.relative_to(root)} (registry)")
    return refs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT_DEFAULT))
    args = ap.parse_args()
    root = Path(args.root).resolve()

    doc = root / "docs" / "deployment-secrets.md"
    if not doc.exists():
        print(f"FAIL: {doc} not found")
        return 1
    documented = set(re.findall(r"`([a-z0-9_.-]+)`", doc.read_text(encoding="utf-8")))

    refs = referenced_items(root)
    missing = {k: v for k, v in refs.items() if k not in documented}
    if missing:
        print(f"FAIL: {len(missing)} vault item(s) consumed by the IaC but absent from "
              f"docs/deployment-secrets.md §Master Secret List:")
        for item in sorted(missing):
            where = sorted(missing[item])[:2]
            print(f"  - {item}  ({'; '.join(where)})")
        print("\nAdd a row per item: type, consumer, who seeds it, and whether it is a "
              "placeholder-then-swap or deploy-provisioned value.")
        return 1
    print(f"OK: all {len(refs)} IaC-referenced vault items are documented in deployment-secrets.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
