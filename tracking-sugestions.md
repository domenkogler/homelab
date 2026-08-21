# Tracking Docs — Suggestions (Audit Round 2)

> **Role:** Audit deliverable — proposals for `todo.md`, `changelog.md`, `deployment-tasks.md`
> (and adjacent meta files): split/merge/rewrite/update. Produced 2026-08-21 per `prompt.md`.
> **Linked from:** `prompt.md`; siblings: `docs-vs-iac.md` (§I summarizes tracking contradictions),
> `docs-changes.md`, `iac-changes.md`, `conventions-sugestions.md`, `architecture.md`, `security.md`.

---

## 1. State of the three files (what works)

- **todo.md** — the module-based restructure is good: one row = one outcome, executors, priorities,
  Stage N/10 markers, park section, deploy-gated pointer to deployment-tasks. Keep the model.
- **changelog.md** — decision-log + implementation log split works; append-only discipline is
  consistently applied; entries carry evidence links.
- **deployment-tasks.md** — phase model (0→10) with per-phase 1Password prerequisites and
  "Deploy-gated verification" blocks is exactly right as the operational SSOT.

The problems are **drift, not design**: phase text that predates decisions it references, hand-entered
derived numbers, and two markdown defects that hide rows.

## 2. deployment-tasks.md — phase-text sweep (highest value)

Fix in one pass; each item is a claim contradicted by IaC or by a closed decision.
Stale-date sweep result (exact): `2025-08` typos sit in **deployment-tasks.md (2), docs/security.md (4),
docs/services-ai.md (10), docs/services-vps.md (1), docs/hardware-oldsrv.md (1)** plus 3 inside older
changelog rows' quoted rationale — fix the five docs, leave changelog rows as written (append-only).

| Phase | Fix |
|-------|-----|
| Header | "✅ Decisions (2025-08-16 …)" → 2026 date sweep. |
| Phase 3 step 3 | Service list still shows headscale/kopia-server/n8n/metabase on oldsrv + "remove/downgrade per HD-135" — the split is already applied in group_vars; rewrite the list to the actual oldsrv subset (ollama, immich-ml, technitium, pihole, homepage, dozzle, signal-cli, sunshine, jellyfin+*arr, HA-standby). |
| Phase 3 verify | "Grafana/Forgejo reachable" belongs to VPS verification; keep only internal-surface checks here. |
| Phase 4 steps 2–3 | Pi docker_services = home-assistant-primary, technitium-secondary, traefik-ha (no pihole/raspberrymatic); role order = docker_services before home_assistant; delete the local-Homematic instruction (HD-13 parked) or mark it ⏳ parked. |
| Phase 6 | HD-14 row mentions TileBoard — retired (HD-24); say "HA Dashboard lovelace". |
| Phase 7 item 7 | AnythingLLM + LocPilot superseded (HD-108) → Office MCP path (HD-111). |
| Phase 9 | HD-35 (network-devices link) resolved; HD-39 (watchtower) decided — both rows are done work listed as open tasks. |
| Host→Playbook table | vps chain missing vps-hardening/cifs/wireguard; nas chain missing storage role; pi chain order wrong — align with the playbook files (this table contradicts the same file's Phase 1 text). |
| Phase 2 step 2 | Chain omits the storage role (it is in playbooks/storage.yml between network and nut). |

Also consider: the file duplicates the 1Password prerequisite lists three times (per-phase blocks +
phase recap + §0 tables). Keep §0 as the master and make phases link to it with only *deltas*
("new this phase") — today's duplication already drifted once (op_api story).

## 3. todo.md — structural repairs

1. **Broken markdown (fix immediately):**
   - §2.4 has a duplicated `| ID | D | Exec | P | Item |` header row mid-table.
   - §2.6 table is split by a blank line after HD-72 → HD-14…HD-27 render as loose paragraphs
     outside any table in strict renderers.
2. **§4 dependency notes** reference "HD-60/61/62/63/64/94" as open ⏳ rows — those are closed in
   changelog; refresh the example list (or drop examples; the rule statement suffices).
3. **§0 lifecycle:** add one line codifying what changelog already practices: implementation-done
   rows move to changelog even when deploy-gated follow-ups exist — the ⏳ lives in
   deployment-tasks' phase block, not as a second todo row (currently true in practice; make it text).
4. **Numbering:** nothing wrong internally — but CONVENTIONS §1 says "next free = HD-114"; change
   that pointer to "see todo.md / max(HD)+1" so it can't rot again.

## 4. changelog.md — light touch

- **Date sweep:** several decision rows carry 2025-08-16 inside otherwise-2026 entries (HD-51/92/93
  rationale lines; security.md mirrors them). Fix the year; do not reorder anything (append-only).
- **Naming drift inside old rows:** HD-53 says `network-snmp_login`; canonical is now
  `network-snmp_api`. Per append-only rules, do NOT edit the row — instead add a one-line footnote
  under the Decisions section header: "item names reflect naming at decision time; current names per
  deployment-secrets.md rename map."
- **Section headers:** "Decisions & research" vs "Implementation & tooling" is clean. Optionally
  state the sort order (currently newest-first within sections?) explicitly at the top — entries
  appear roughly reverse-chronological but not strictly.
- **Size:** ~60 KB and growing; fine for years at current velocity. If it ever hurts, split by year
  (`changelog-2026.md`) with the current file keeping the latest year — no action needed now.

## 5. readme-humans.md + root meta

- `readme-humans.md`: service table lists foto/file/git/chat — will grow; consider generating the
  family-visible service list from the same SSOT as Homepage (or accept hand-maintenance; it's 4 rows).
- `prompt.md` itself: once this audit round is triaged, archive it into `brainstorming/obsolete/` or
  delete — root should hold only living documents (same lifecycle as audit reports,
  `conventions-sugestions.md` §A3).
- The seven new audit reports from this round: apply the A3 lifecycle — fold actionable items into
  owning docs + HD rows, then delete the reports in the closing change.

## 6. Cross-file consistency rules worth pinning (pointer to conventions)

These recur across all three tracking files; they belong in CONVENTIONS (see
`conventions-sugestions.md` §A1/A3/B6) rather than being re-fixed by hand each time:

1. Derived numbers/pointers are never hand-entered (next-HD, counts, record lists).
2. Audit/prompt deliverables are ephemeral with an explicit fold-or-delete ending.
3. Decision dates are ISO and swept for year typos.
4. When a decision closes, its *mention* in other docs gets swept in the same change
   (TileBoard/AnythingLLL/watchtower class of stale mentions).

## 7. Suggested execution order

1. todo.md markdown repair (5 min, un-hides rows).
2. deployment-tasks.md phase sweep (one focused PR; biggest contradiction killer).
3. Date sweep across changelog/security/services-ai/deployment-tasks.
4. CONVENTIONS amendments (A1/A3 + next-HD pointer) so the drift class dies permanently.
