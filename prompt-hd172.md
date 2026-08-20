# Prompt: HD-172 — `-generated` filename suffix: rename generated docs + add a linter

> Handoff written 2026-08-20. Goal: every machine-produced doc carries the `-generated` suffix in its
> **filename** (not just a header), enforced by a linter. **Analysis + Q/A first.**

## Task
Rename the generated docs to the `-generated` suffix and add an `-generated` name linter that fails the
build when a generated doc lacks the suffix (or a hand-authored doc wrongly carries it). Per
`CONVENTIONS.md` §8.2.

## Context
- Generated files today (from `render_network_addresses.py` / `render-docs.yml` /
  `render_rack_connections.py` and the `docker_services` role):
  - `inventory.md` → `services-inventory-generated.md`
  - `network-addresses.md` → `network-addresses-generated.md`
  - `subscriptions-table.md` → `subscriptions-table-generated.md`
  - `rack-connections.md` → `network-rack-generated.md` (also resolves the `network-rack.md` collision;
    this rename is coordinated with HD-168)
- Renaming touches in the same change: the renderer (`scripts/render_*.py`,
  `IaC/ansible/playbooks/render-docs.yml`, the `docker_services` role), all validators that
  whitelist/tokenize the name (`scripts/check_doc_ips.py`), and the `docs/index.md` doc map + prose
  references. The doc-map linter (`check_doc_map.py`) fails closed, so a stale ref breaks `validate-all.sh`.
- **Prerequisite:** HD-173 (link-scan) must land first so renames don't silently break in-doc links.

## Sequence of Work (MANDATORY)
1. **Analysis.** List every generated doc + its render source + every code reference (use `git grep` for
   the old names). Confirm HD-173 is done (link-map extended) before you start.
2. **Q/A.** Ask (written): confirm the 4 target names (`network-rack-generated.md` vs the HD-168 merge)? Is
   the linter separate (`scripts/check_generated_suffix.py`) or folded into `check_doc_map.py`? Strict
   naming (`*-generated.md` only) — any allowed exceptions?
3. **Execute, red/green:**
   a. Add the linter; wire it into `validate-all.sh`; run it — it **fails** (red) on the current names.
   b. Rename the files (git mv) + update the renderer output paths + every reference + the doc map.
   c. Re-run — **green**.
4. **Validate.** Full `validate-all.sh` green. Update HD-172 → `changelog.md`, delete `prompt-hd172.md`.

## Guardrails
- The rename must be one self-contained change (renderer + refs + doc map) — no half-migration.
- The `-generated` suffix is the SSOT (CONVENTIONS §8.2); headers are hints, not the convention.
- Don't touch hand-authored docs that don't carry the suffix.

## Definition of done
Generated docs carry the `-generated` filename; the linter is wired into `validate-all.sh`; a stale or
wrong-suffixed name fails the build; all references updated; HD-172 → `changelog.md`; prompt deleted.