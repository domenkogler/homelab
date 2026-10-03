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
> [`../reports/probe-agentmemory-20260921.md`](../reports/probe-agentmemory-20260921.md),
> [`CONVENTIONS.md`](../CONVENTIONS.md) §8.3
> **Linked from:** [`index.md`](index.md), [`services-ai.md`](services-ai.md)

> ⚠️ **Append-only.** Do not edit or reorder an entry after it lands. A changed decision is a **new appended
> entry**, left alongside the old one — never a strike/replace. Each row:
> `| <service> | <rejected|dropped|superseded> | <date> | <why, 1–2 lines + evidence link> |`.
> A re-review is allowed **only with an exception note** ("re-evaluating X because Y changed"), per §8.3.

## Decisions

| Service | Status | Date | Why |
|---------|--------|------|-----|
| **OpenViking** — as the **corpus / knowledge index** | **rejected** | 2026-09-21 | Measured on this box against this repo, all four gates **pre-registered before measuring** (falsifiable), and the index gate failed outright: of 51 files only **12/51 came back byte-identical** and **20/51 had under 95 % of their lines recoverable**; a `.md` is replaced by a directory tree **named from its H1 title slug** (filename gone, so the index is not reversible), and 7 files lost content with **zero** embedding errors, so the loss is in OV's sectioning and not only in the size cap. `skills/mikrotik/SKILL.md` lost 197 of 261 lines and grepping all 265 stored chunks for its own H1 finds nothing — dropped, not reflowed. Corpus indexing stays `rag-mcp` + Qdrant (HD-268b). · [`../reports/probe-ov-20260921.md`](../reports/probe-ov-20260921.md) §4 |
| **OpenViking** — as the **memory plane** (the "memory only" fallback) | **rejected** | 2026-09-21 | **Owner decision (2026-09-21):** *"OV at most memory-only does not make any sense"* — the fallback is retired with the rest, so OV is out of the architecture entirely. The measurement supports it rather than merely permitting it: OV's memory payload **is** the LLM-distilled L0/L1 layer, and that layer lost to a free local extract on this same box (**R5 retrieval-key 1/16 vs 18/20**, 887 vs 154 tokens per doc, one invented number in 16 docs), while its write path is **LLM-bound by construction** (`compressor_v3` builds a VLM ReAct agent per session-commit) on a KV pool that is **1.97×** one session — the shared engine went **0.27 s → 8.7 s (32×)** under load. The dev memory plane is agent-memory.dev (HD-336), which captures, indexes and recalls **keyless, with no LLM in the hot path** and stores JSON on disk — **confirmed by measurement 2026-09-21** (keyless 7/10 hit@5, determinism 10/10, ≈455 tok/query, ≈0 spark tokens; and its own limits are in [`services-ai.md`](services-ai.md) §9b). Running OV for memory would mean a second substrate, an AGPL dependency and a per-commit model tax to do a job the decided plane does without a model. · [`../reports/probe-ov-20260921.md`](../reports/probe-ov-20260921.md) §6, [`../reports/probe-agentmemory-20260921.md`](../reports/probe-agentmemory-20260921.md) (the follow-on lane that measured that plane) |
| OV deferral reason recorded as *"Docker-only"* | **rejected — the fact was wrong** | 2026-09-21 | This doc previously deferred OV partly because it was believed **Docker-only**. That was false: `openviking==0.4.21` ships a `cp310-abi3` wheel, installed into a **venv on py3.13 in about 2 minutes** with no Rust toolchain, ran as the unprivileged `domen` seat on loopback `:1933`, no container. Recorded so the next reader does not inherit a false constraint (HD-431's bug class: docs that read as verified). The rejection above stands on the measured fidelity and cost numbers instead. · [`../reports/probe-ov-20260921.md`](../reports/probe-ov-20260921.md) §3 |
| `nv-patch` (HD-489 tier-1b: NVFP4 + patches) | **rejected — cannot boot** | 2026-10-03 | The staged **`ples_nvfp4` PLE table (128 shards, 27 G) contains ZERO `ngram_embedding.weight` keys** the patched lineage's PLE offload worker requires → `PLE offload checkpoint did not load all materialized parameters: [...layers.1.ple.ple_embedding.ngram_embedding.weight]` → hard EngeCore-init failure → **crash-restart loop (RestartCount 39)**. The INT4 u-arms boot because they use `ple_overlay: true` (code overlay into `ple_layer.py`), not the offload-table path that needs ngram weights. Recovering it = re-staging the NVFP4 PLE artifact with ngram embeddings (an artifact decision, not a dial flip) — not worth it in this funnel: NVFP4's PLE path is the blocker, not the patch. · [`../spark/reports/hd489-nv-patch/README.md`](../spark/reports/hd489-nv-patch/README.md) |
| `ar-mmap` / `ar-dv` (HD-489 tier-2: AR-hybrid + FP8 PLE mmap) | loser — beat by ar-blk | 2026-10-03 | Initially blocked by mmap×CUDA-graph pinning (unpinned CPU tensor in capture); fixed with `enforce_eager: true` (owner-approved). **`ar-mmap`** (spec OFF): eager decode 20.3 / 20.4 tok/s C2L, TTFT ~0.7s, ITL ~49ms — on par with tier-1 but lower TTFT/ITL; **the control, not a candidate. **`ar-dv`** (+65,536-id draft-vocab slice): C2L 35.8 tok/s, MTP 36.8% — the vocab slice **lowers MTP acceptance** (54.7→36.8%) and decode (−10%) vs ar-blk; regression. Evidence: [`../spark/reports/hd489-ar-mmap/README.md`](../spark/reports/hd489-ar-mmap/README.md), [`../spark/reports/hd489-ar-dv/README.md`](../spark/reports/hd489-ar-dv/README.md) |
| `u1-patch` (HD-489 t1) | loser — baseline, beat by ar-blk | 2026-10-03 | The isolation control (patched lineage + AWQ, no spec): decode 17.9/20.9 C2/C2L, TTFT ~2.9s. Establishes the +13% that u2-blk's block rejection adds — not a candidate. · [`../spark/reports/hd489-u1-patch/README.md`](../spark/reports/hd489-u1-patch/README.md) |
| `u3-s8` (HD-489 t1) | loser — seqs=8 strands memory, no win | 2026-10-03 | u2-blk + seqs=8 + piecewise graphs: decode 19.6/22.7 ≈ u2-blk, but **strands +40 GB** engine pid (317,638 vs 276,855 MiB) — the §6.2 stranding rule fires; memory-heavy no-win. · [`../spark/reports/hd489-u3-s8/README.md`](../spark/reports/hd489-u3-s8/README.md) |
| `u4-pin` (HD-489 t1) | loser — pin neutral | 2026-10-03 | u2-blk + never-evict 0.03: decode 20.7/23.7 ≈ u2-blk; `recomp_tok_delta` identical to non-pin arms (bench prompts lack the pinned substring), preempt 0 — **the pin buys nothing measurable** on synthetic benches. · [`../spark/reports/hd489-u4-pin/README.md`](../spark/reports/hd489-u4-pin/README.md) |
| `v16b` (HD-489 t3) | loser — slower than ar-blk + **memory-infeasible C2L** | 2026-10-03 | Full upstream recipe (T80 drafter + 65,536-id draft-vocab + seqs=8 + 8192): decoder 33.1/16.2 C2/C1, MTP ~27% — **below ar-blk**, and the OOM guard refused C2L (10.8 GiB usable < 16 floor — the recipe holds ~1.6 TB VSZ on a 121.6 GiB pool). · [`../spark/reports/hd489-v16b/README.md`](../spark/reports/hd489-v16b/README.md) |
| `v16b-s4` (HD-489 t3) | loser — below ar-blk | 2026-10-03 | seqs=4 freed memory (C2L ran: 384s, 33.1 tok/s, MTP 25.7%) but **still −17% vs ar-blk (39.7)**; the T80+draft-vocab drag, not the batch shape. · [`../spark/reports/hd489-v16b-s4/README.md`](../spark/reports/hd489-v16b-s4/README.md) |
| `v16b-pin` (HD-489 t3) | loser — pin neutral, recipe below ar-blk | 2026-10-03 | v16b-s4 + never-evict 0.03: dec 29.1, MTP 19.3%, recomp +8608 (pin never engages synthetically), preempt 0 — confirms the pin is neutral (as u4-pin) and the recipe is slower than ar-blk. · [`../spark/reports/hd489-v16b-pin/README.md`](../spark/reports/hd489-v16b-pin/README.md) |
| `u3-s8` at-rest column (HD-489 t1) | **CORRECTION** of the row above (append-only) | 2026-10-03 | The "**strands +40 GB** engine pid (317,638 vs 276,855)" claim **read the wrong column**: `atrest-*.txt` is `nvidia-smi --query-compute-apps=pid,used_memory`, so **col 1 = PID, col 2 = MiB**. `317,638` and `276,855` are the engine PIDs of two different boots (u3-s8 vs u2-blk); the MiB column reads **92,324 vs 92,333** — a PID swap, not a +40 GB stranding. Same misread in `u1-patch`'s "175903/92975" report. The **arm stays rejected on its SPEED** (19.6/22.7 vs 20.2/23.6 — a real −3/−4 %), which the row above records. The seqs=8 batch shape was correctly kept out on cost/benefit, just not on the memory claim it printed. · committed raws: [`../spark/reports/hd489-u3-s8/raw/atrest-*.txt`](../spark/reports/hd489-u3-s8/raw/atrest-20261002-222812-t1-u3-C2.txt) · [`../spark/reports/hd489-u2-blk/raw/atrest-*.txt`](../spark/reports/hd489-u2-blk/raw/atrest-20261002-215129-t1-u2-C2.txt) |

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
