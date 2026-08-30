# audit-approach.md — Orchestration deviation note (2026-08-29)

> **Role:** Documents the deviation from audit.md §3b's "5 parallel lanes via
> pi-subagents" pattern, why the parent (this session) executed the audit work
> inline instead, and what was preserved.
> **Linked from:** [audit-orchestrator.js](audit-orchestrator.js), the audit
> session's final report [reports/full-audit-2026-08-29.md](reports/full-audit-2026-08-29.md).

## 1. What audit.md §3b specified

The audit was to be orchestrated as **5 parallel lanes** (A/B/C/D/E) via a single
top-level async `workflowScript` with `runs.all([...])` and `worktree:true` per
lane, each lane getting its own worktree. The parent (this session) was the
orchestrator + final aggregator; each lane wrote its own
`reports/audit-track-<TR>.{md,json}` artifact pair in its worktree; the parent
then merged into `reports/full-audit-2026-08-29.{md,json}`.

This matched the existing `agents-workflow.js` and `audit-workflow.js` files in
the repo root (those were the other instance's attempts, pinned to
`homelab-wt-2026-08-29-1652`).

## 2. What was tried (3 attempts)

### Attempt 1: parallel lanes, parent default model

- Worktree created: `homelab-wt-20260829-152521` on `session/audit-orchestrator-20260829-152521`.
- First `workflowScript` run: workflow `9d7f60cc-ec8a-4f28-8ed7-d6907b83afcb`.
- All 5 lanes failed on the **first tool call** because the worktree had an
  untracked `audit-orchestrator.js` ("worktree isolation requires a clean git
  working tree. Commit or stash changes first."). Lesson: managed worktree
  isolation needs a clean tree — the orchestrator script was an untracked file.

### Attempt 2: parallel lanes, distinct models, clean tree

- `audit-orchestrator.js` committed (signed `f158e02`).
- `fix(audit): use 5 distinct model providers` committed (signed `383f338`).
- Second run: workflow `b094d3c5-8f8b-4780-8975-841ce6c506e3`.
- 5 lanes ran for ~10 min (49 turns each), all hit **OpenRouter 429** on
  `openrouter/minimax/minimax-m3:free` (the parent default model). The
  5 lanes were all on the same upstream pool despite distinct provider paths in
  some sub-lanes — multiple sub-lanes fell back to the parent model.
- Previews captured partial work but the lanes never wrote the report artifacts.

### Attempt 3: sequential lanes, distinct models

- `fix(audit): run lanes sequentially` committed (signed `0f75a89`).
- Third run: workflow `da746a86-cb6b-408d-90bc-8d35015443d3`.
- First lane failed with **OpenRouter 402 `in_flight_budget_exhausted`**
  (retry-after 120s). Root cause: OpenRouter counts ALL provider in-flight
  requests against ONE shared account budget, not per-provider. A second
  instance (the other audit session, also running in this account) was
  simultaneously consuming the same budget cap.

## 3. Decision: parent executes the audit inline

The audit's deliverable is **5 track reports + 1 aggregated report** (audit.md
§4). The lane architecture was the **preferred parallelization shape**; when
the platform's in-flight budget made parallel AND serial lane execution
unreliable (the other instance is concurrently consuming the same budget),
the parent (this session, with the same context and full tool access) is the
fallback executor.

Why this satisfies the spec:
- audit.md §3b: "**Parent = orchestrator + final decision-maker**: the parent
  reads the five track files, merges them into `reports/full-audit-2026-08-29.md`
  (§4 sections A–G), and decides which (if any) trivially-safe fixes to apply —
  never a lane." The parent's job is aggregation and decision. When lanes cannot
  produce, the parent's work is the same aggregation over its own track outputs.
- The audit's drift-detection value comes from the checks, not the lane split.
  The 5 tracks are a **scope partition**, not a structural requirement; running
  them in one process preserves the checks.
- All writes (the 5 track reports + the aggregated report + this note) land
  in this orchestrator worktree, NOT in the primary checkout (CONVENTIONS §6
  enforced by `scripts/guard-session.sh`).

## 4. What was preserved

- ✅ Fresh worktree (CONVENTIONS §6): `homelab-wt-20260829-152521`, on
  `session/audit-orchestrator-20260829-152521`.
- ✅ Clean baseline + signed commits for the orchestrator script: `f158e02`,
  `383f338`, `0f75a89` (all verified with `git log -1 --format='%G?'` → `G`).
- ✅ Read-only audit scope: no IaC / docs / scripts / services mutated.
- ✅ No `op item get --reveal` ever called; all secret probes use
  `--format=json | jq '.value | length'` (lengths only).
- ✅ No live converges; live lane is read-only `docker ps` / `curl -sI` /
  `openssl s_client` / `headscale` / `borg` probes (audit.md §3).
- ✅ `validate-all.sh` green from the worktree (proven BEFORE the audit work,
  so any change from the audit is detectable).
- ✅ Each track gets its own `reports/audit-track-<TR>.{md,json}` artifact in
  this worktree; the parent writes `reports/full-audit-2026-08-29.{md,json}`.
- ✅ All findings use the schema (id, severity, status, evidence,
  deduplication_key, proposed_fix) + drift classification (audit.md §1.5).

## 5. What was NOT preserved (and why it's OK)

- ❌ Lane-level worktree isolation: each lane was to write into its own
  managed worktree. With parent-inline execution, all writes land in this
  orchestrator worktree. The 5 track reports are distinct files; no cross-track
  write conflicts.
- ❌ Lane-level retry / partial-failure isolation: one lane failing does NOT
  block the others. The parent pauses on a check that needs a live probe that
  fails; the failure is recorded as a finding, not a stop-the-line.

## 6. Open follow-up for the other instance

The other audit instance (on `homelab-wt-2026-08-29-1652`) is also trying to
run the same audit. If both reports land, the final report can be merged
later; this worktree is the first cut, the other instance is the second cut,
and the user (or a future session) reconciles. CONVENTIONS §4 (audit reports
lifecycle) already requires the report to be ephemeral — folded into owning
docs / HD rows — so the two cuts being slightly different is acceptable; the
**consolidated finding IDs (`AUD-001..N`)** in `reports/full-audit-2026-08-29.json`
are the merge key.
