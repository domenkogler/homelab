---
title: Harness — Review Queue
role: queue
domain: harness
status: active
sensitivity: infra
tags: [harness, review, queue, agent-harness]
---
# Harness Review Queue

> **Role:** Intake queue — coding-harness and seat-plane candidates heard of but not yet researched.
> Near-empty by design: this is a queue, not a backlog.
> **Links to:** [`harness.md`](harness.md), [`harness-rejected.md`](harness-rejected.md)
> **Linked from:** [`index.md`](index.md), [`harness.md`](harness.md)

> ⚠️ **Planning phase — nothing here is live.** Treat every row as a *candidate to evaluate*, not a
> commitment to install on a seat.

> **Lifecycle (per [`../CONVENTIONS.md`](../CONVENTIONS.md) §8.3 — it owns the promotion target and the stale rule):**
> 1. **Before adding** a row, check [`harness-rejected.md`](harness-rejected.md) first, including its seed
>    pointers into the two `services` logs — a previous rejection is consulted, not auto-blocking
>    (re-review only with an exception note).
> 2. **Promote** → move the row out to the tracked backlog and delete it from this file; `-review` has no
>    "accepted" state. A candidate that becomes a **plane** lands in
>    [`../scripts/lib/seat-planes.yml`](../scripts/lib/seat-planes.yml) with its owning script, not here.
> 3. **Stale** — any row untouched for **30 days** must be promoted or moved to
>    [`harness-rejected.md`](harness-rejected.md). Review is a queue, not a backlog.

---

## Queue (intake)

| Candidate | URL | Why (3 words) |
|-----------|-----|---------------|
| — | — | — |

> *(Deliberately near-empty. Candidates already evaluated live in the decision logs; candidates already
> built live in the seat-plane registry. Add a row only for a harness, seat tool or terminal-layer piece
> that is heard of but not yet researched.)*
