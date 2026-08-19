# Prompt: HD-157 — Add secrets-lint + doc-map/count lint to validate-all

> Handoff written 2026-08-19. Goal: turn docs-drift + credential leaks into **lint failures**.

## Task

Extend `scripts/validate-all.sh` so three checks become part of the pre-commit gate:

**(a) secrets-lint** — literal credential values must never appear in IaC.
**(b) doc-map reconciliation** — every `docs/*.md` reachable from `docs/index.md` (and vice-versa).
**(c) count-lint** — doc-claimed counts (templates, roles, services) match the actual dirs.

## Current state (important!)

The other session already wrote **two scripts** that are sitting UNTRACKED in `scripts/`:

- `scripts/validate-secrets.py` (198 lines) — greps for literal credential patterns in
  group_vars/templates (per the plan)
- `scripts/check_doc_map.py` (127 lines) — checks `docs/index.md` map vs `find docs -name '*.md'`

They are **NOT yet wired into `validate-all.sh`** and **NOT yet committed**. This task is:
1. **Review both scripts** for correctness/coverage (do they match the HD-157 intent? do they have
   false-positive risks? are they idempotent/fast?)
2. **Wire them into `scripts/validate-all.sh`** (add `== validate-secrets.py ==` +
   `== check_doc_map.py ==` steps, matching the existing pattern + exit-code discipline)
3. **Add the count-lint (c)** — a check that doc-stated counts (e.g. "49 templates",
   "8 OIDC providers") match reality; either extend an existing script or add a small
   `validate-counts.py`. Reference `CONVENTIONS.md` §2 (counts are derived, never hand-entered).
4. **Fix any drift they find** (e.g. `docs/index.md` missing a doc, a stale count in prose).
5. Update **HD-157 row in `todo.md`** (done) + commit the two scripts AND the wiring together.

## Guardrails
- The two untracked scripts belong to this task — commit them here (they're HD-157's deliverable).
- Do NOT commit other session's unrelated untracked files (`brainstorming/authentik blueprint.md`,
  `scripts/check_doc_map.py` is part of this task, but double-check ownership before including).
- The secrets-lint must **not** flag the 1Password `lookup()` calls or the placeholder keys in
  `post_install.sh` (`<PERSONAL_PUBKEY_FROM_1PASSWORD>` etc.) — those are intentional placeholders.
- Keep exit-code contract: 0 = pass, 1 = fail; `set -e` in validate-all.sh stops on first failure.

## Definition of done
`validate-all.sh` runs all checks green on the current tree; the two scripts committed; count-lint
in place; any found drift fixed; HD-157 row closed; one clean commit (validate-all.sh green before).
