# Prompt: HD-168 — Network docs refactor

> Handoff written 2026-08-20. Goal: make `network.md` the network **index** over `network-*.md` stack
> docs, and merge/delete the redundant `rack-connections.md`. **Analysis + Q/A first, edits only when
> clear.**

## Task
Restructure the network docs to follow `CONVENTIONS.md` §8.1 (domain index → `-sub` docs), and resolve
the `rack-connections.md` vs `network-rack.md` duplication.

## Context
- Network docs today: `network.md` (broad), `network-vlans.md`, `network-dns.md`, `network-vpn.md`,
  `network-ops.md`, `network-rack.md`, `network-addresses-generated.md`.
- `rack-connections.md` duplicates SSOT-only physical-link info whose real source is
  `rack-connections.json` → renders `network-rack.md`. Per the thread, it is a merge/delete candidate,
  and `network-rack(-generated).md` may become the generated view.

## Sequence of Work (MANDATORY)
1. **Analysis.** Read `network*.md` + `docs/index.md` + `CONVENTIONS.md` §8.1/§8.2. Decide whether
   `network.md` should be the index over the `network-*` stack docs, and where `rack-connections.md`
   content goes (merge into `network-rack.md`, or delete as pure duplication).
2. **Q/A.** Ask the owner (written list): Is `network.md` the intended index? What is the exact
   `-generated` rename (+ renderer + reference updates per §8.2)? Is `rack-connections.md` fully
   redundant or does any info live only there?
3. **Execute** after Q/A resolves: set `network.md` as index (`role: index`, links to `network-*`),
   move or delete `rack-connections.md` per the decision, align the Document Map in `docs/index.md`,
   and — **only if this task owns the rename** — apply the `*-generated` filename + renderer/reference
   updates (otherwise hand that to HD-172 and just note the collision here).
4. **Validate.** `validate-all.sh` green. Update HD-168 → `changelog.md`, delete `prompt-hd168.md`.

## Guardrails
- `-generated` renames and the link-map linter are **owned by HD-172/HD-173** — if you touch a
  generated filename, coordinate; otherwise leave the mechanical rename to that task and only adjust
  prose/doc-map here.
- Keep shared SSOT facts (VLAN table, subnets, firewall rules, IP SSOT pointer) in exactly one owner.
- Don't chase cosmetic fixes (CONVENTIONS §6).

## Definition of done
`network.md` = network index; `rack-connections.md` merged/deleted; links resolve; `validate-all.sh`
green; HD-168 → `changelog.md`; prompt deleted.