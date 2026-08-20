# Prompt: HD-167 — Services docs stack refactor

> Handoff written 2026-08-20. Goal: make `docs/services.md` the **central stack index** and split the
> ~260-line catalog into per-domain `services-<x>.md` stack docs. This task is **analysis + Q/A first,
> file edits only when everything is clear** (see §Sequence of work).

## Task

Restructure `docs/services.md` from one flat catalog into a stack index + per-domain stack docs, per
`CONVENTIONS.md` §8.1.

## Context

- `services.md` is currently the *only* service document: `role: broad`, a single catalog table
  (~60 services), Docker Networks, Domain & Subdomain Plan, *arr/media section, observability summary,
  and the URL→backend edge-case table.
- `CONVENTIONS.md` §8.1: a **domain** = a set of services deployed together under one owning doc; the
  domain's index `<domain>.md` links to `<domain>-<sub>.md` docs. The **central service stack index**
  = `docs/services.md`, the only pointer from `docs/index.md` for service layout. The catalog must not
  become a single multi-hundred-line table.
- Existing per-domain docs: `services-traefik.md`, `services-authentik.md`, `services-matrix.md`,
  `services-finance.md`, `services-vps.md`. These are candidates to *stay* as stack docs or be merged
  according to the retained catalog.

## Sequence of Work (MANDATORY)

1. **Analysis pass.** Read `docs/index.md` + `docs/services.md` + `CONVENTIONS.md` §8. Decide the
   **target stack split**: propose the `services-<x>.md` docs you will create (candidates:
   `services-arr.md`, `services-downloads.md`, `services-media.md`, `services-dns.md`,
   `services-observability.md`, plus how traefik/authentik/matrix/finance/vps map). For each, list the
   catalog rows that move into it.
2. **Q/A pass.** Ask the owner a **written list of questions** (as this conversation did) covering:
   - Which catalog sections stay in `services.md` vs move to a stack doc?
   - What is the exact `services-<x>.md` naming set + its `role:` frontmatter?
   - Where do the shared facts live (Docker Networks, Domain & Subdomain Plan, URL→backend table)?
   - How are existing `services-traefik.md` etc. affected — renamed, kept, or folded into the new split?
   Wait for answers. Do NOT edit files until the Q/A is resolved.
3. **Execute.** Only after Q/A: create the new `services-<x>.md` stack docs (move the relevant catalog
   rows + their detail), trim `services.md` back to an index (catalog legend + links to each stack doc,
   keeping the shared SSOT facts: Docker Networks, Domain & Subdomain Plan, Subnet backend table),
   and register every new `.md` in the `docs/index.md` Document Map (doc-map linter enforces).
4. **Validate.** `bash scripts/validate-all.sh` green (doc-map + link-map must pass). Update the
   `HD-167` row in `todo.md` (✅ done) → move it to `changelog.md`, then **delete `prompt-hd167.md`**.

## Guardrails
- Do **not** rename `services-traefik/authentik/matrix/finance/vps.md` unless the Q/A decides to — the
  SSOT-frontmatter `role:` and the `docs/index.md` map must stay consistent.
- Keep shared SSOT facts (networks, domains/subdomains, exposure) in exactly **one** owning doc (either
  `services.md` or the stack doc), never both.
- Preserve `*`-generated marker and the `-generated` filename rule (CONVENTIONS §8.2) — do not touch
  any `*-generated` file as part of this refactor.
- Cross-cutting docs (`observability.md`, `security.md`, …) are **out of scope** here — handled by
  HD-171.

## Definition of done
`services.md` is a stack index; `services-<x>.md` stack docs own each catalog section; `docs/index.md`
Document Map is consistent; `validate-all.sh` green; HD-167 moved to `changelog.md`; prompt deleted.