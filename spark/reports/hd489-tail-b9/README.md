# HD-489 tail — B9: weights or knobs? (the first boot to spend)

Authoring status: **AUTHORED + GATED GREEN** — boot/measure is owner-gated
(`spark_llm_allow_uncertified`).

## What B9 is

The funnel's headline was "+68 % is the AR weights" — but A4 showed the tier-2/tier-3
arms rendered a ~7-knob kernel-dispatch env bundle (`QWEN38NEXT_*`, `VLLM_VERIFY_TOPK`,
`VLLM_KEEP_DRAFT_BLOCKS`, `VLLM_MARLIN_USE_ATOMIC_ADD`, `VLLM_USE_DEEP_GEMM`,
`VLLM_FP8_HYBRID`) that tier-1 arms never got. B9 isolates: does the win survive
without those dispatch knobs?

## Authoring (done, this change)

- `ar-blk-lean` — clone of `ar-blk` (same AR-hybrid weights + FP8 mmap table +
  in-checkpoint MTP-3 block rejection), with `ple_dispatch: false` ⇒ the dispatch env
  is NOT rendered. Table set (`VLLM_PLE_MMAP*` + `VLLM_DRAFTER_EXPERTS_FP8`) kept.
- Gate: `ar-blk-lean` renders `ok` in the matrix, passes every invariant incl. the new
  `ple-dispatch-lean` (`a4-split=✓`), and its env is verified to contain **0** of the 7
  dispatch knobs.

## Semantics note (important, read before booting)

The A4 split landed, and **no profile currently declares `ple_dispatch: true`** — so
the live `ar-blk` running today already renders WITHOUT the dispatch knobs. That means:

- `ar-blk (live, no dispatch)` vs `ar-blk-lean (also no dispatch)` = **the same config**.
- The real A4 comparison is **`ar-blk` WITH dispatch** vs **`ar-blk` WITHOUT**.
- **So the B9 boot to spend should set `ple_dispatch: true` on `ar-blk`** (the
  "full-bundle" clone) and compare against the live lean baseline (39.7 tok/s C2L),
  NOT boot `ar-blk-lean` seeking a delta against an already-lean live.

Owner decision requested: confirm the B9 boot is **ar-blk + dispatch** (the meaningful
A4 comparison) rather than cloning lean-vs-lean.

## When the owner approves

1. `spark_llm_profile: ar-blk` (live) + `ple_dispatch: true` on that arm (or a
   `ar-blk-full` clone for one boot).
2. `spark_llm_allow_uncertified: true` in host_vars, converge detached.
3. Measure C2 + C2L. If 39.7 survives → the win is the checkpoint (quality risk real);
   if it falls to ~25 → the win is env (B10 is the cheap certified path).