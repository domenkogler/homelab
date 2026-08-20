# Prompt: HD-170 — Smart-home docs refactor

> Handoff written 2026-08-20. Goal: align the smart-home docs to `CONVENTIONS.md` §8.1. **Analysis +
> Q/A first, edits only when clear.**

## Task
`smart-home.md` already follows the domain-index pattern (`smart-home.md` → `smart-home-{voice,audio,
failover}.md`). Complete the alignment: normalize `smart-home.md` frontmatter to `role: index`, and
align the remaining smart-home docs (`smart-home-*.md` + `home-assistant-current.md`) so each fits the
index/sub-doc shape without an overgrown index.

## Context
- `smart-home.md` (broad) links `smart-home-voice.md`, `smart-home-audio.md`, `smart-home-failover.md`.
  `home-assistant-current.md` documents the *live* HAOS instance (a status doc, arguably detail of the
  smart-home domain).
- This is a **lighter** refactor — mostly frontmatter + link/index normalization, not content moves.

## Sequence of Work (MANDATORY)
1. **Analysis.** Read `smart-home*.md` + `home-assistant-current.md` + `docs/index.md` + `CONVENTIONS.md`
   §8.1. Decide whether `smart-home.md` is the canonical index and whether `home-assistant-current.md`
   should be folded in or stay a sibling detail doc.
2. **Q/A.** Ask the owner (written list): Is `smart-home.md` the intended index? Does
   `home-assistant-current.md` stay a sibling or fold in? Any renames?
3. **Execute** after Q/A: normalize frontmatter (`role: index`), make the index's link list exact, fix
   dead links, keep the Document Map consistent (incl. `manual/smart-home.md` family guide).
4. **Validate.** `validate-all.sh` green. Update HD-170 → `changelog.md`, delete `prompt-hd170.md`.

## Guardrails
- Don't move HA config/IaC — this is docs only.
- Preserve the smart-home cross-links to `interfaces.md`, `network-dns.md`, `deployment-ansible.md`.

## Definition of done
`smart-home.md` = domain index with exact link list; sub-docs aligned; `home-assistant-current.md`
resolved; links valid; `validate-all.sh` green; HD-170 → `changelog.md`; prompt deleted.