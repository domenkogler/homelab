---
title: Harness — Rejected / Dropped Decision Log
role: log
domain: harness
status: active
tags: [harness, pi, agent-harness, seats, rejected, decision-log]
---
# Harness — Rejected / Dropped

> **Role:** Decision log — coding-harness / seat options this homelab evaluated and declined; the
> `harness` domain's **decision-log SSOT** ([`../CONVENTIONS.md`](../CONVENTIONS.md) §8.3). One row per
> decision, sorted by subject. The current-state fact a decision settled lives in the owning doc, not here.
> **Links to:** [`harness.md`](harness.md), [`harness-pi-engines.md`](harness-pi-engines.md),
> [`services-rejected.md`](services-rejected.md), [`services-ai-rejected.md`](services-ai-rejected.md)
> **Linked from:** [`index.md`](index.md), [`harness.md`](harness.md)

> Each row is `| <subject> | <rejected|dropped|superseded> | <why> |` — no dates, no links, no prose.
> **Append-only:** add rows, never rewrite or delete an existing one; rows are keyed by subject
> (`CONVENTIONS.md` §8.3). Evidence = the current-state text in the owning doc.

## Where the earlier harness decisions are — seed pointers

The `harness` domain was cut out of the `services` domain, so its **history did not move**. A harness
candidate is not researched until both logs below have been swept; a row here is only ever the *new*
decisions taken since the domain existed.

| Log | Harness subjects it holds |
|---|---|
| [`services-rejected.md`](services-rejected.md) | The harness-as-a-service shape: coding harnesses behind the gateway, `dsh` / `pi-dev` as catalog entries, seat surfaces in a container |
| [`services-ai-rejected.md`](services-ai-rejected.md) | The harness's engine relationship and seat plumbing: harnesses behind the LAN hop, the `spark/*` allow-list grant, the retired `host-status.ts` footer, the harness-side fallback rule, `pi.kogler.si` used as a seat URL |

## Decisions

| Subject | Status | Why |
|---------|--------|-----|
| `@ogulcancelik/pi-ssh-tools` | dropped | Owner runs no ssh from a seat |
| `@season179/pi-worktree` | dropped | Owner runs git worktrees by hand, not by command |
| The harness as an unprefixed cross-cutting doc | rejected | Harness candidates already carry a reject history |
| The subagent payload as a second settings-plane target | rejected | Coverage comes free in the matrix; a second target escapes it |
| The git identity as a pi-seat-sync plane | rejected | Own concern with own scripts under `scripts/git/`; the seat matrix stays out of it |
| Automatic failover to a hosted model | rejected | External use is owner-authorized per session; no external bench |
