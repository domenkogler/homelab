# Lifecycle Documents — Proposals for `todo.md`, `changelog.md`, `deployment-tasks.md`

> **Role:** Change-proposal for the three lifecycle/backlog/runbook documents — where they overlap, where to split, merge, rewrite, or add.
> **Pairs with:** `docs-changes.md`, `conventions-proposal.md`.
> **Current state (2026-08-19, planning):** `todo.md` 66 open · 0 decisions · 1 purchase · 10 parked · 63 done; `changelog.md` append-only; `deployment-tasks.md` phase-based build order.

---

## 1. What's healthy now (keep — no change)

- **`changelog.md`** is a correct **append-only decision/implementation log** (decisions migrated out of `todo.md` once, `changelog` = decision-log SSOT). This is the right pattern — keep it.
- **`todo.md` §0 lifecycle rules** (one row = one outcome; done → changelog; decision written once; ⏳ deploy-gat tail) are clear and already enforced pretty well.
- **`deployment-tasks.md`** phase-based build order + dependency graph is the right shape.

## 2. What to change

### A. `todo.md` — the §3c "⏳ Deploy-gated" list is great, but grows stale because it duplicates §2 markers
- **Issue:** `todo.md` §3c ("Consolidated, one-screen view of every `⏳ deploy-gated` row") is an **explicit derived view** but currently lists ~25 rows, each redeclaring the pending-live step already in the owning module. It is a **second ledger by design**, which is exactly what §0 warns against ("1 row = 1 outcome", "no duplicate").
- **Resolution (recommend):** keep it **only if** the derived view is *generated* (a small script pulls `⏳`-marked active rows from §2 into a fresh table) OR keep it as a **living checkpoint** but add a **consistency guard**: any addition to §3c must be matched by the same task's `⏳` tail in §2, enforced by `validate-todo.py` (new) — mirroring the `validate-all.sh` philosophy. Prefer **generation** over duplicate hand-maintenance.

### B. `todo.md` — the "1 purchase" (HD-30 Infomaniak) and "10 parked" need an explicit **inactive/blocked** grouping
- **Issue:** §1 Purchases has 1 open buy (Infomaniak) and §3 Park has 10 real parked items. These are *different* from open work but currently only distinguished by section not by a status column.
- **Resolution:** add a tiny `status:` inline tag to **parked** rows (`parked`, `blocked`), and a `⏳`/`🚧` marker where a human action gates (already partly present). Keeps the "0 decisions" honestly computable. Minor.

### C. `changelog.md` — split "decisions & research" from "implementation & tooling"
- **Issue (already solved, verify):** the file now has two tables (`## Decisions & research` + `## Implementation & tooling`) — **good**. 
- **Recommendation (keep-pattern):** do **not** split into a separate file; the single-changelog with the two sub-tables is the right degree. Optionally **add a `## Pending/planned` section** pointing forward to `todo.md` open rows, so a reader of the changelog can also see what's *next* — but **only as a pointer**, never a duplicate list.

### D. `deployment-tasks.md` — the biggest drift risk: it references HD-numbers that moved/closed
- **Issue:** `deployment-tasks.md` Phase 7 lists `HD-13` (Homematic full-local) and `HD-28` (Office AI) with *"RaspberryMatic", "*arr"* etc. — but **HD-13 is parked (2026-08-18)** and **HD-28 was absorbed/superseded** by the Open WebUI MCP path (HD-106–111); Phase 9 lists HD-39 (watchtower — **decided no**, HD-39 closed) and HD-35 (fixed). The phase doc's prose doesn't always show the resolved/decided state.
- **Resolution:**
  1. In each Phase header, add a **"ℹ️ Current status:"** line (decided/dropped/superseded per `changelog.md`) so the runbook isn't read as a to-do of stale/decided tasks.
  2. **Prune decided/dropped rows** from the phase tables (HD-39 watchtower decided; HD-02 Doco-CD dropped → already noted; HD-13 parked → already noted) or keep them **struck-through** like the entries in `todo.md`/`changelog.md` already do.
  3. **Add a "Not-in-scope / decided away" appendix** listing the decided-no-go items (watchtower, Doco-CD, TileBoard, /arr v-anything) so the runbook is unambiguous.

### E. `deployment-tasks.md` vs `todo.md` — clarify the master/child relationship
- **Issue:** `deployment-tasks.md` starts "Status tracking for sub-tasks: `todo.md` (HD-XX IDs)". Good — but `todo.md` §3c is described as "the deploy-gated checklist" while `deployment-tasks.md` also lists phases with many of the same HDs. Two places to learn "what must be live" = drift (observability placement moved, S3 vs CIFS).
- **Recommendesolution:** make `deployment-tasks.md` the **build-order/runbook** and `todo.md` the **status/backlog**. In `deployment-tasks.md`, reference HD-IDs only; in `todo.md`, carry the ⏳/done state. Avoid re-stating *what* a phase deploys in both prose and HD rows.

### F. `todo.md` housingkeeping macro-rule — already in §0 §5 but not enforced
- `todo.md` §0 §5 "Tally" (66 open, per-module counts) is hand-maintained and already can drift (the module tallies `ai=8, backup=2, …, observ=0` — check vs the actual §2 list). **Recommend** computing the tally (or dropping it to "regenerate from §2 HD-IDs") to stop the hand-count class of bug.

### G. New document candidates (suggested)
- A **`deployment-tasks.md` → "service cutover" checklist** does NOT need a new file; keep in Phase 1/1.5.
- A **`status.md`*** (live-status per host/service) — currently split across `todo.md` (§3c) + `deployment-tasks.md` (verify gates) + `docs/*` owning docs. **Recommend a single generated `status.md`** (★) that renders "who is live / ⏳ pending" from `group_vars` + HD rows, so the "is it deployed yet" question is one answer. This directly serves the post-go-live era.

---

## Summary of recommended lifecycle-doc changes

| Doc | Change | Priority |
|-----|--------|----------|
| `todo.md` | §3c derived-⏳ → generate (script) or add consistency-lint; add `status` markers to Park/Blocked; compute tally | high |
| `todo.md` | add validate-todo lint (like validate-all) | med |
| `changelog.md` | keep split; add forward-pointer to `todo.md` open rows | low |
| `deployment-tasks.md` | add "ℹ current status" per phase; strike decided/dropped; add legacy-not-implemented appendix | high |
| `deployment-tasks.md` | make runbook-only (HD refs via `todo.md`, no re-state) | med |
| `*status.md` (new) | generated live "what is live & ⏳" view | med (post-go-live) |