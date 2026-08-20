# Prompt: HD-171 — Cross-cutting docs resolution (final)

> Handoff written 2026-08-20. Goal: decide the disposition of the cross-cutting docs, **last** — after
> HD-167→170 have absorbed what belongs to their owning domains. **Analysis + Q/A first.**

## Task
For each cross-cutting doc (`security.md`, `backup.md`, `storage.md`, `observability.md`,
`llm-office.md`) decide its final home per `CONVENTIONS.md` §8.4: it is cross-cutting if it is owned
by **no single deploying host**.

## Context
- Cross-cutting = owned by no single deploying host. Marked `cross_cutting: true` in frontmatter +
  `**Role:** … (cross-cutting)` in the header so the taxonomy analyzer doesn't relitigate them.
- The 2026-08-20 contract: absorb what belongs to an owning domain as domains are refactored; the
  cross-cutting file itself is re-evaluated when the domains it overlaps are edited, and its final
  disposition is this task.

## Sequence of Work (MANDATORY)
1. **Analysis.** Re-read `docs/index.md` + `CONVENTIONS.md` §8.4 + the 5 cross-cutting docs currently on
   the list (`security.md`, `backup.md`, `storage.md`, `observability.md`, `llm-office.md`). Determine,
   for each, whether it should (a) stay cross-cutting (`cross_cutting: true`), (b) fold wholly into an
   owning domain doc, or (c) shed sections into owning domains and keep a slim cross-cutting spine.
2. **Q/A.** Ask the owner (written list), per doc: stay / fold / shed-sections? Which domain owns each
   section you propose to move? Is the `cross_cutting: true` marker + `**Role:** … (cross-cutting)`
   header format agreed?
3. **Execute** after Q/A resolves: **apply the frontmatter + header marker to every doc that stays
   cross-cutting**; for docs that shed, move the sections to their owning domain docs and update the
   owning doc's index + `docs/index.md` Document Map; leave no orphaned or dead links.
4. **Validate.** `validate-all.sh` green. Update HD-171 → `changelog.md`, delete `prompt-hd171.md`.

## Guardrails
- Do **not** sweep cross-cutting content into a domain that hasn't been through its own refactor
  (HD-167→170) — cross-cutting runs **last** for a reason.
- The `cross_cutting: true` frontmatter is the machine-readable signal; don't drop it from docs that
  stay cross-cutting.
- Preserve the `*` SSOT direction (§8.5): sources stay in IaC; docs are views.

## Definition of done
Each cross-cutting doc has a decided disposition + correct header marker; moved sections are owned by
the right domain; no dead links; `validate-all.sh` green; HD-171 → `changelog.md`; prompt deleted.