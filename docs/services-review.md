---
title: Services — Review Queue
role: queue
domain: services
status: active
tags: [services, review, queue]
---
# Services Review Queue

> **Role:** Intake queue — services heard of but not yet researched. Near-empty by design: this is a queue, not a backlog.
> **Links to:** `services.md`, `services-inventory-generated.md`
> **Linked from:** `index.md`, `services.md`

> ⚠️ **Planning phase — nothing live yet.** Treat every service here as a *candidate to evaluate*, not a commitment to deploy.

> **Lifecycle (per CONVENTIONS.md §8.3):**
> 1. **Before adding** a row, check the decision log [`services-rejected.md`](services-rejected.md) first — a previous rejection is consulted, not auto-blocking (re-review only with an exception note).
> 2. **Promote** → move the row to `todo.md` as an HD-XXX (pointer back here), then delete it from this file. There is no "accepted" state in review.
> 3. **Stale** — any row untouched for **30 days** must be promoted to `todo.md` or moved to `services-rejected.md`. Review is a queue, not a backlog.

---

## Queue (intake)

| Service | URL | Why (3 words) |
|---------|-----|---------------|
| Navidrome | navidrome.com | Subsonic-API self-hosted music server — fits Lidarr downloads + Jellyfin ecosystem (research: Authentik OIDC, Jellyfin users import) |

> *(Deliberately near-empty. Add a row only when a service is heard of but not yet researched; promotions and 30-day stale moves keep this thin.)*