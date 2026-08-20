# Prompt: HD-169 — Hardware docs refactor

> Handoff written 2026-08-20. Goal: make `hardware.md` the hardware **index** over `hardware-*.md`
> stack docs, per `CONVENTIONS.md` §8.1. **Analysis + Q/A first, edits only when clear.**

## Task
Align the hardware docs to the domain-index pattern.

## Context
- Hardware docs: `hardware.md` (broad), `hardware-oldsrv.md`, `hardware-gpu.md`, `hardware-nas.md`,
  `hardware-ups.md`, `hardware-phase2.md`. `hardware.md` already acts as a broad pointer — likely just
  needs `role: index` normalization + link tightening.
- This is a **lighter** refactor than services/network (few cross-refs, mostly naming/frontmatter).

## Sequence of Work (MANDATORY)
1. **Analysis.** Read `hardware*.md` + `docs/index.md` + `CONVENTIONS.md` §8.1. Determine whether
   `hardware.md` is the index and whether any `hardware-*` doc needs splitting/merging (e.g.
   `hardware-phase2.md` is a deferred Phase-2 doc — keep or align its status marker).
2. **Q/A.** Ask the owner (written list): Should `hardware.md` get `role: index`? Is `hardware-phase2.md`
   still deferred or merged? Any renames?
3. **Execute** after Q/A: set `hardware.md` as index (`role: index`, links to `hardware-*`), touch
   frontmatter/status on the sub-docs, keep the Document Map in `docs/index.md` consistent.
4. **Validate.** `validate-all.sh` green. Update HD-169 → `changelog.md`, delete `prompt-hd169.md`.

## Guardrails
- Don't chase cosmetic changes (CONVENTIONS §6); this is a structural/naming task.
- Keep hardware-vs-network SSOT boundaries: rack/device wiring belongs to network domain, compute/GPU
  hardware to hardware domain.

## Definition of done
`hardware.md` = hardware index; `hardware-*` sub-docs aligned; doc-map consistent; `validate-all.sh`
green; HD-169 → `changelog.md`; prompt deleted.