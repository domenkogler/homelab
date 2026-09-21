---
title: AI Platform — Rejected / Dropped Decision Log
role: log
domain: services
status: active
tags: [services, ai, rejected, decision-log, rag, memory]
---
# AI Platform — Rejected / Dropped

> **Role:** Append-only decision log for the **AI platform plane** (gateway / RAG / memory / agent
> harnesses) — candidates the `services-ai` domain evaluated and declined, with the measured evidence that
> closed them. This log is that plane's decision-log SSOT (`CONVENTIONS.md` §8.3).
> **Links to:** [`services-ai.md`](services-ai.md), [`../reports/probe-ov-20260921.md`](../reports/probe-ov-20260921.md),
> [`../prompt-agentmemory.md`](../prompt-agentmemory.md), [`CONVENTIONS.md`](../CONVENTIONS.md) §8.3
> **Linked from:** [`index.md`](index.md), [`services-ai.md`](services-ai.md)

> ⚠️ **Append-only.** Do not edit or reorder an entry after it lands. A changed decision is a **new appended
> entry**, left alongside the old one — never a strike/replace. Each row:
> `| <service> | <rejected|dropped|superseded> | <date> | <why, 1–2 lines + evidence link> |`.
> A re-review is allowed **only with an exception note** ("re-evaluating X because Y changed"), per §8.3.

## Decisions

| Service | Status | Date | Why |
|---------|--------|------|-----|
| **OpenViking** — as the **corpus / knowledge index** | **rejected** | 2026-09-21 | Measured on this box against this repo, all four gates **pre-registered before measuring** (falsifiable), and the index gate failed outright: of 51 files only **12/51 came back byte-identical** and **20/51 had under 95 % of their lines recoverable**; a `.md` is replaced by a directory tree **named from its H1 title slug** (filename gone, so the index is not reversible), and 7 files lost content with **zero** embedding errors, so the loss is in OV's sectioning and not only in the size cap. `skills/mikrotik/SKILL.md` lost 197 of 261 lines and grepping all 265 stored chunks for its own H1 finds nothing — dropped, not reflowed. Corpus indexing stays `rag-mcp` + Qdrant (HD-268b). · [`../reports/probe-ov-20260921.md`](../reports/probe-ov-20260921.md) §4 |
| **OpenViking** — as the **memory plane** (the "memory only" fallback) | **rejected** | 2026-09-21 | **Owner decision (2026-09-21):** *"OV at most memory-only does not make any sense"* — the fallback is retired with the rest, so OV is out of the architecture entirely. The measurement supports it rather than merely permitting it: OV's memory payload **is** the LLM-distilled L0/L1 layer, and that layer lost to a free local extract on this same box (**R5 retrieval-key 1/16 vs 18/20**, 887 vs 154 tokens per doc, one invented number in 16 docs), while its write path is **LLM-bound by construction** (`compressor_v3` builds a VLM ReAct agent per session-commit) on a KV pool that is **1.97×** one session — the shared engine went **0.27 s → 8.7 s (32×)** under load. The dev memory plane is agent-memory.dev (HD-336), which captures, indexes and recalls **keyless, with no LLM in the hot path** and stores JSON on disk. Running OV for memory would mean a second substrate, an AGPL dependency and a per-commit model tax to do a job the decided plane does without a model. · [`../reports/probe-ov-20260921.md`](../reports/probe-ov-20260921.md) §6, [`../prompt-agentmemory.md`](../prompt-agentmemory.md) |
| OV deferral reason recorded as *"Docker-only"* | **rejected — the fact was wrong** | 2026-09-21 | This doc previously deferred OV partly because it was believed **Docker-only**. That was false: `openviking==0.4.21` ships a `cp310-abi3` wheel, installed into a **venv on py3.13 in about 2 minutes** with no Rust toolchain, ran as the unprivileged `domen` seat on loopback `:1933`, no container. Recorded so the next reader does not inherit a false constraint (HD-431's bug class: docs that read as verified). The rejection above stands on the measured fidelity and cost numbers instead. · [`../reports/probe-ov-20260921.md`](../reports/probe-ov-20260921.md) §3 |

## What would reopen OV (exception-note triggers only)

Do not re-litigate on vibes. Per §8.3 a re-review needs an exception note naming what changed; the changes
that would actually move this decision are:

1. **Fidelity** — OV ships a mode that stores source documents verbatim and reversibly (filename preserved),
   and passes the same 8-check rubric in
   [`../reports/probe-ov-20260921/p1_metrics.py`](../reports/probe-ov-20260921/p1_metrics.py) at **≥ 45/51**
   byte-identical on this repo's 51-file slice.
2. **Write path** — an **LLM-free capture/commit mode** (or a documented way to run the commit path on a
   non-shared engine), so a memory plane stops taxing the KV pool the agent is talking on.
3. **Compile cost** — ingest throughput better than **~740 prompt + 250 completion tokens per KB** of docs
   (measured: ~14 min per 163 KB at `max_concurrent=3`; the whole repo extrapolates to ≈ 3.8 M prompt /
   1.25 M completion tokens and 7–30 h).
4. **A requirement we do not have today** — one plane across harnesses *including* a hosted tier, with
   per-user/agent ACL as a hard need. That is the only axis where OV's scope/ACL model beat the alternatives.

Two side effects of the probe survive regardless, and are **not** rejections: `local-rerank` (HD-425) keeps a
real consumer class (Jina-format rerank callers), and the **OV-vs-grep retrieval baseline** it produced
(**8/10 hit@5 at 5,267 tokens per question** vs grep **5/10 at 92,004**) is the number `rag-mcp` (HD-268b) is
now on the hook to match — retrieval efficiency was OV's genuine strength; fidelity and cost were not.
