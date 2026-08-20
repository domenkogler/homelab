# Prompt: HD-173 — Extend `check_doc_map.py` to scan links beyond `docs/index.md`

> Handoff written 2026-08-20. Goal: catch dead links repo-wide, so renames (`-generated`, domain
> splits) can't silently break in-doc links. **Prerequisite to HD-172.** **Analysis + Q/A first.**

## Task
Extend the doc-map linter so it validates markdown links **not just in `docs/index.md`** but across all
`.md` in the repo (at least `docs/`, `CONVENTIONS.md`, `README.md`), flagging any `[x](*.md)` target
that doesn't resolve.

## Context
- `scripts/check_doc_map.py` today checks only `docs/index.md`: every `.md` under `docs/` must appear in
  the `## Document Map` block, and every `[..](..md)` link in the index must resolve.
- Widespread renames (HD-172, HD-167/168/169/170) will otherwise silently break in-doc links in
  `CONVENTIONS.md`, `README.md`, and prose across `docs/*.md`.
- Wired into `validate-all.sh` today; the extension must stay wired.

## Sequence of Work (MANDATORY)
1. **Analysis.** Read the current `check_doc_map.py` + `validate-all.sh` + `CONVENTIONS.md` §8.5. Map
   today's checks (index doc-map coverage + index-only link resolution).
2. **Q/A.** Ask (written): scope — `docs/**` + root `.md` (README/CONVENTIONS) only, or also `IaC/**`,
   `manual/*`, `brainstorming/`? Ignore URLs (http), anchors (`#`), and `../` external? Relative-only —
   confirm.
3. **Execute** after Q/A: extend the link-scan to the agreed file set, keep the existing doc-map check,
   keep false-positive behavior (for `assets/`, symlinks, `manual/`), patch `validate-all.sh` to run it.
   Fix any dead links the new scan finds **in the same change** (only the ones it truly owns; don't
   collide with HD-167→171 renames).
4. **Validate.** `validate-all.sh` green. Update HD-173 → `changelog.md`, delete `prompt-hd173.md`.

## Guardrails
- No false failures on URLs / anchors / `../` / symlinks / `manual/*` family guides.
- Don't change existing doc-map semantics (docs-under-docs must be in the map) — only add the
  cross-file link scan.
- Coordinate with HD-167→171 so the link scan doesn't fight their in-progress renames.

## Definition of done
`check_doc_map.py` resolves links repo-wide (not just index); dead links fail the build; `validate-all.sh`
green; HD-173 → `changelog.md`; prompt deleted.