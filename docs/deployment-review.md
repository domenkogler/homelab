---
title: Deployment — Review Queue
role: queue
domain: deployment
status: active
tags: [deployment, review, queue]
---
# Deployment Review Queue

> **Role:** Intake queue — deploy-toolchain / VPS-host candidates heard of but not yet researched. Near-empty by design: this is a queue, not a backlog.
> **Links to:** `deployment.md`
> **Linked from:** `index.md`, `deployment.md`

> ⚠️ **Planning phase — nothing live yet (except the netcup VPS, which has no services deployed).**

> **Lifecycle (per CONVENTIONS.md §8.3 — it owns the promotion target and the stale rule):**
> 1. **Before adding**, check [`deployment-rejected.md`](deployment-rejected.md) first (consulted, not auto-blocking; re-review only with an exception note).
> 2. **Promote** → move the row out to the tracked backlog and delete it from this file; `-review` has no "accepted" state.
> 3. **Stale** — any row untouched for **30 days** must be promoted or moved to [`deployment-rejected.md`](deployment-rejected.md). Review is a queue, not a backlog.

---

## Queue (intake)

| Service | URL | Why (3 words) |
|---------|-----|---------------|
| — | — | — |

> *(Deliberately near-empty. Add a row only when a tool is heard of but not yet researched.)*