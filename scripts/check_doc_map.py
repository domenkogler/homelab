#!/usr/bin/env python3
"""Lint: every doc under docs/ is reachable from docs/index.md (and vice-versa).

Enforces the repo's documentation convention (CONVENTIONS.md §docs, HD-152):
`docs/index.md` is the document map / AI dispatcher — every `.md` under `docs/`
must be reachable from it, and the index must not reference files that don't
exist.

Authoritative reference: the `## Document Map` code block in docs/index.md. A
doc under `docs/` is "covered" if its basename appears in that block (the block
lists both top-level docs and `manual/*.md` family guides by basename).

Additionally validated: every `[label](path.md)` link elsewhere in the index
(`Which Document to Read First` table, prose) must resolve to a real file.

What is checked:
  * missing  — a doc on disk under `docs/` (excluding `docs/assets/**` and
               `docs/manual/*`, which are reachable via `manual/README.md`)
               whose basename is NOT in the Document Map block
  * stale    — a `[label](path.md)` link in index.md (outside the block) whose
               target does not exist

Run:   python scripts/check_doc_map.py
Exit:  0 = clean, 1 = violations found.  Wired into `validate-all.sh`.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
INDEX = DOCS / "index.md"

# Basenames that live at repo root and are intentionally NOT under docs/.
ROOT_DOCS = {"README.md", "CONVENTIONS.md", "todo.md", "CHANGELOG.md", "prompt-next.md"}


def _on_disk_docs() -> set[Path]:
    """All .md under docs/ (absolute), excluding docs/assets/."""
    out: set[Path] = set()
    for p in DOCS.rglob("*.md"):
        if p.is_symlink():
            continue
        rel = p.relative_to(DOCS).as_posix()
        if rel.startswith("assets/"):
            continue
        out.add(p)
    return out


def _document_map_basenames(text: str) -> set[str]:
    """Every `<name>.md` basename that appears in the Document Map block."""
    m = re.search(r"^## Document Map\s*\n(```.*?```)", text, re.MULTILINE | re.DOTALL)
    if not m:
        return set()
    block = m.group(1)
    return set(re.findall(r"([\w@.-]+\.md)", block))


def _markdown_link_targets(text: str) -> set[str]:
    """`[label](target.md)` links OUTSIDE the Document Map block."""
    # strip the Document Map block first so we don't double-count its tree
    text = re.sub(r"^## Document Map\s*\n```.*?```", "", text, flags=re.MULTILINE | re.DOTALL)
    return set(re.findall(r"\]\(([^()\s]+?\.md)\)", text))


def main() -> int:
    if not INDEX.exists():
        print(f"FAIL: {INDEX} not found", file=sys.stderr)
        return 1
    text = INDEX.read_text(encoding="utf-8")

    on_disk = _on_disk_docs()
    in_map = _document_map_basenames(text)

    # 1) Missing: docs on disk whose basename is not in the Document Map,
    #    excluding docs/assets (already filtered) and docs/manual/* (family
    #    guides are reachable via manual/README.md, listed by basename in the
    #    map but not required to be error if missing — they ARE in the map).
    missing = []
    for p in sorted(on_disk):
        rel = p.relative_to(DOCS).as_posix()
        if rel.startswith("manual/"):
            continue  # family guides covered by manual/README.md pointer
        if p.name not in in_map:
            missing.append(rel)

    # 2) Stale: markdown links outside the block must resolve to a real file.
    stale = []
    for link in sorted(_markdown_link_targets(text)):
        if link in ROOT_DOCS or link.startswith("../") or link.startswith("#"):
            continue
        # resolve relative to docs/
        if not (DOCS / link).exists():
            stale.append(link)

    bad = False
    if missing:
        bad = True
        print(f"FAIL: {len(missing)} doc(s) under docs/ not in the Document Map:")
        for d in missing:
            print(f"  + {d}")

    if stale:
        bad = True
        print(f"\nFAIL: {len(stale)} link(s) in docs/index.md point at a missing file:")
        for d in stale:
            print(f"  - {d}")

    if bad:
        print(
            f"\nSee docs/index.md → '## Document Map'. Add missing docs to the map; "
            "fix/remove links that point at files that don't exist."
        )
        return 1

    print(
        f"OK: {len(on_disk)} docs/ referenced in docs/index.md "
        f"(Document Map + links consistent)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
