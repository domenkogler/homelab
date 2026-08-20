#!/usr/bin/env python3
"""Lint: every doc under docs/ is reachable from docs/index.md (and vice-versa),
plus repo-wide markdown-link resolution across all canonical .md files.

Two checks (HD-152 + HD-173):

  * map/missing (HD-152) — `docs/index.md` is the document map / AI dispatcher:
    every `.md` under `docs/` must be reachable from it, and the index must not
    reference files that don't exist. The authoritative reference is the
    `## Document Map` code block (a doc is "covered" if its basename appears).

  * cross-file link resolution (HD-173) — every `[label](path.md)` markdown
    link in canonical repo `.md` files (docs/**, root canonical docs,
    IaC/**) must resolve to a real file, so renames (e.g. `-generated`
    suffixes, domain splits) can never silently break in-doc links.

What is checked:
  * missing — a doc on disk under docs/ (excluding docs/assets/** and
               docs/manual/*, reachable via manual/README.md) whose basename
               is NOT in the Document Map block.
  * stale-all (HD-152+173) — a `[label](path.md)` link in ANY scanned canonical
    .md (including docs/index.md) whose target does not resolve from that
    file's directory.

False-positive guards (no false failures on):
  * URLs (http/https/mailto), in-page anchors (#)
  * glob/wildcard patterns in link text (e.g. `[x](*.md)` — literal prose)
  * link syntax inside inline code spans or fenced code blocks (used as
    examples in changelog.md / todo.md when describing this very linter)
  * `manual/*` family docs (checked for resolution, not map coverage)
  * symlinks and docs/assets (binary/in-progress, excluded)

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

# Root docs that are canonical content (always scanned for links).
ROOT_SCAN = {"README.md", "CONVENTIONS.md", "todo.md", "changelog.md",
             "deployment-tasks.md", "readme-humans.md"}

# basenames at repo root that are intentionally NOT under docs/ but are valid
# link targets (used in CONVENTIONS/README/root docs and in-doc links).
ROOT_DOCS = {"README.md", "CONVENTIONS.md", "todo.md", "CHANGELOG.md",
             "changelog.md", "prompt-next.md", "deployment-tasks.md",
             "readme-humans.md", "readme.md"}


def _strip_code(text: str) -> str:
    """Remove fenced code blocks and inline code spans so their contents are
    not treated as markdown links (e.g. `[x](*.md)` example prose)."""
    text = re.sub(r"```.*?```", "", text, flags=re.DOTALL)  # fenced blocks
    text = re.sub(r"`[^`]*`", "", text)                      # inline code spans
    return text


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
    """`[label](target.md)` links, excluding the Document Map block."""
    text = re.sub(r"^## Document Map\s*\n```.*?```", "", text,
                  flags=re.MULTILINE | re.DOTALL)
    return set(re.findall(r"\]\(([^()\s]+?\.md)\)", text))


def _iter_scan_files() -> list[Path]:
    """Every canonical .md file whose links we validate (order stable)."""
    files: set[Path] = set()
    files |= _on_disk_docs()                            # all docs/**
    for name in ROOT_SCAN:
        p = ROOT / name
        if p.exists():
            files.add(p)
    files |= set((ROOT / "IaC").rglob("*.md"))         # IaC/ docs incl. README
    # exclude brainstorming/ (freeform notes) and anything under docs/assets
    # (non-navigation). Exclude prompt-*.md handoffs (transient).
    out = []
    for f in files:
        relpos = f.as_posix()
        if "brainstorming/" in relpos:
            continue
        if "/assets/" in relpos:
            continue
        if f.name.startswith("prompt-"):
            continue
        out.append(f)
    return sorted(out)


def _is_ignorable_target(target: str) -> bool:
    """Non-traversable / non-file link targets (no .md resolution needed)."""
    if target.startswith(("http://", "https://", "mailto:")) or "://" in target:
        return True
    if target.startswith("#"):
        return True
    if target.startswith("//"):
        return True
    if "*" in target or "?" in target:   # glob/wildcard literal prose
        return True
    if not target.endswith(".md"):
        return True                      # anchor-only, directory, web path
    return False


def main() -> int:
    if not INDEX.exists():
        print(f"FAIL: {INDEX} not found", file=sys.stderr)
        return 1
    index_text = INDEX.read_text(encoding="utf-8")

    on_disk = _on_disk_docs()
    in_map = _document_map_basenames(index_text)

    bad = False

    # ---- Check 1 (HD-152): docs/ missing from Document Map ----
    missing = []
    for p in sorted(on_disk):
        rel = p.relative_to(DOCS).as_posix()
        if rel.startswith("manual/"):
            continue  # family guides covered by manual/README.md
        if p.name not in in_map:
            missing.append(rel)
    if missing:
        bad = True
        print(f"FAIL: {len(missing)} doc(s) under docs/ not in the Document Map:")
        for d in missing:
            print(f"  + {d}")

    # ---- Check 2+3 (HD-152+173): repo-wide cross-file link resolution ----
    # The general scan below covers docs/index.md links (index.md is in docs/),
    # so a stale/missing target in the index is caught, as is any other link
    # across all canonical .md files.
    broken_all: list[tuple[str, str]] = []
    # Append-only history: changelog.md rows may reference files renamed after
    # the row was written (e.g. docs/llm-office.md -> services-office.md). Those
    # historical links are intentionally left as written — allow them.
    CHANGELOG_STALE = {"docs/llm-office.md", "docs/ai-stack.md"}
    for f in _iter_scan_files():
        try:
            text = f.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        text = _strip_code(text)
        rel_src = f.relative_to(ROOT).as_posix()
        for tgt in sorted(_markdown_link_targets(text)):
            if _is_ignorable_target(tgt):
                continue
            # strip anchor fragment for path resolution
            path = tgt.split("#", 1)[0]
            candidate = (f.parent / path)
            if not candidate.exists():
                # allowlist for append-only changelog rows referencing pre-rename files
                if rel_src == "changelog.md" and path in CHANGELOG_STALE:
                    continue
                broken_all.append((rel_src, tgt, str(candidate.resolve())))

    if broken_all:
        bad = True
        print(f"FAIL: {len(broken_all)} link(s) across repo .md do not resolve:")
        for src, tgt, res in broken_all:
            print(f"  - {src} -> [{tgt}]  ({res})")

    if bad:
        print("\nSee docs/index.md → '## Document Map' + any unfound link target (HD-173).")
        return 1

    print(f"OK: {len(on_disk)} docs/ in Document Map; {len(_iter_scan_files())} "
          "canonical files scanned; all links resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main())