# HD-489 — arm `nv-patch` (tier 1b: NVFP4 + patches) — **FAILED TO BOOT**

Measured attempt 2026-10-02 23:34 UTC on spark. Retired as a candidate; the arm cannot boot
with the currently staged artifacts.

**Profile**: `nv-patch` — NVFP4 (`Qwen3.8-Flash-Next-mixed-NVFP4-FP8`) + patched lineage + the
`ples_nvfp4` PLE offload table (tier-1b: "whether the patches rescue that quant").

## Failure (hard, reproducible)

The engine enter a **crash-restart loop** (`RestartCount` climbed to 39). Root cause (engine log):

```
(PleOffloadWorker pid=314) RuntimeError: PLE offload checkpoint did not load all materialized
parameters: ['language_model.model.layers.1.ple.ple_embedding.ngram_embedding.weight']
```

## Root-cause analysis (verified)

- The `ples_nvfp4` table **is** staged (128 shards, 27 G) and **is** mounted into the container
  (`/mnt/spark_nvme/ples_nvfp4 -> /ples_nvfp4`, verified via `docker inspect`).
- But a full scan of **all 128 shards** (`safe_open` over every shard) found **ZERO keys
  containing "ngram"** anywhere — the table has **no `ngram_embedding.weight`** for any layer.
- The PLE offload worker (activated on the NVFP4 offload path) requires
  `.../ple_embedding/ngram_embedding.weight` per layer; the table lacks them all → init aborts.

## Why the INT4 arms (u1–u4) booted fine

The u-arms use `ple_overlay: true` — a **code overlay** bind-mounting over the image's
`ple_layer.py` (the primitive-ai INT4 path), which does NOT load a shard-table ngram weight.
nv-patch is the first arm exercising the **offload-table path** that requires ngram keys — and
the `ples_nvfp4` artifact is incomplete for it.

## Verdict

**nv-patch is retired** (recorded in `docs/services-ai-rejected.md`): the staged NVFP4 PLE table
is missing the ngram embeddings the patched lineage's offload loader requires. Recovering it =
re-staging/re-building the `ples_nvfp4` artifact with the ngram weights (an artifact decision,
not a dial flip), then re-running this gate. Not worth it in this funnel: NVFP4 was the "does the
patch rescue that quant" probe, and the quant's PLE path is the blocker, not the patch.

## Evidence

- Engine logs (PLE offload worker RuntimeError, RestartCount 39) — captured above.
- Shard scan: `ples_nvfp4` 128 shards, 0 ngram keys (this report).
- The box was flipped back to `u2-blk` (best tier-1) to break the crash loop.