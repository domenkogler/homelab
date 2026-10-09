---
title: Observability — Rejected / Dropped Decision Log
role: log
domain: observability
status: active
tags: [observability, alerting, rejected, decision-log]
---
# Observability — Rejected / Dropped

> **Role:** Append-only decision log — the `observability` domain's rejected mechanisms (what a signal will be taken
> from, what will not be instrumented, which exporter path is out). Sorted by the thing considered. This log is the
> per-domain **decision-log SSOT** ([CONVENTIONS.md](../CONVENTIONS.md) §8.3).
> **Links to:** `observability.md`, `services-ai.md` (decision #26, the reason one entry below reads the way it does)
> **Linked from:** `index.md`, `observability.md`

> ⚠️ **Append-only.** Never edit or reorder an entry after it lands. A changed decision is a **new appended entry**,
> left alongside the old one — never strike/replace. Each row:
> `| <thing> | <rejected|dropped|superseded> | <date> | <why, 1–2 lines + evidence link> |`.
> ⚠️ Seed 2026-10-09: this log exists because the observability domain had decisions recorded only in prose. Entries
> that predate it are **not** retro-minted — the ruling in [observability.md](observability.md) stays where it was
> written; consult this log and the owning doc, and append from here.

## Decisions

| Thing | Status | Date | Why |
|-------|--------|------|-----|
| LiteLLM as a **metering proxy** for the direct harness leg (per-client token attribution) | rejected | 2026-10-09 | **Owner decision (2026-10-09):** attribute at the **edge access log** (HD-1120) instead of routing harness traffic through a gateway. Decision #26 puts a generation harness **direct** on the engine name edge precisely to avoid the hop; a metering proxy re-buys the hop, the key management and the failure surface that decision removed. Engine counters stay the token SSOT; per-client **tokens** remain a labelled estimate. Wanting per-key spend *as measurement* re-opens #26 → an owner call, not an implementation detail. · [observability.md](observability.md) §LLM token accounting |
