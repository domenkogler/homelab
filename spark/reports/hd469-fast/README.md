# HD-469 `fast` profile — first live boot + gate 3 finding (2026-09-29, run #3)

Profile: `fast` — NVFP4 (`primitive-ai mixed-NVFP4/FP8`) weights + **bf16** KV,
`ple-nvfp4` sidecar + PLE overlay, MTP3, `kv_cache_dtype: auto`, 11 GB pool
(`fixed_cost_bytes` DERIVED 92.1 GB → host floor 103.1 of 104.1 GB ceiling).
This directory records the first real boot of that profile on the box.

## What was done

1. Staged `nvfp4-mixed` (weights-trim) + `ple-nvfp4` (~117 GB, own window, detached):
   - model dir `Qwen3.8-Flash-Next-mixed-NVFP4-FP8`: 83 GB core (repo is 191 GB;
     its own BF16 PLE table skipped via `exclude: ["ple-bf16-*"]`), **0 `ple-bf16-*`**
     entries on disk, `.index-trimmed` = **130 entries dropped (pattern=ngram)** ✓
   - `ples_nvfp4/`: 27 GB tables, validated flat (128 shards + META.json)
   - Post-staging disk: 185 GB free on /mnt/spark_nvme.
2. Fixed two IaC gaps surfaced by staging:
   - `ples_nvfp4` missing from `roles/spark` `xfs.directories` → added (the mount
     root is root-owned; artifact staging cannot create a new child unprivileged).
   - tables-flatten task could report `changed` while the nested dir was still full
     (transient mv failure) → hardened to verify + fail loud (exit 9).
3. Flipped `spark_llm_profile: fast` + `spark_llm_allow_uncertified: true`, converged
   detached. Gate 0/1 passed, engine booted healthy, `RestartCount=0`.

## Gate results

| Gate | Command / measure | Result |
|------|-------------------|--------|
| 0 render | `validate-docker-services.py --only spark-ai` + `check_spark_llm_gate.py` + `probe matrix/profile` | PASS — gate coherent; fast = 354,529 slots (1.35×) as authored |
| 1 boot | converge detached → `/health` | **PASS** — healthy in ~14 min, `RestartCount=0`; engine's own line: **`GPU KV cache size: 354,248 tokens, Maximum concurrency for 262,144 tokens per request: 1.35x`** — the DERIVED fixed cost held (pool ≈ 11 GB's worth ✓) |
| 2 non-interference | `probe … health` + `reasoning` | PASS — /health 200; thinking OFF emits no reasoning, ON emits reasoning |
| 3 real depth | `probe … ctx 262144` | **FAIL — HTTP 502 at 105.1 s**, prompt=None. see finding |
| 4 concurrency | `probe … concurrent 4` | FAIL (0/4, 18 s, Bad Gateway) — cascades from gate 3 |
| 5 needle | pi-harness §3 at depth | not run (gate 3 blocked) |
| 6 accuracy | fixed 15-prompt battery | not run (gate 3 blocked) |
| 7 memory curve | oom-watchdog over a day | not run (profile rolled back) — pool size itself verified via boot log |

## The gate-3 finding

The 262,144-token leg 502s (**Bad Gateway**) after ~105 s, and concurrency 4 fails
the same way. Engine diagnostics:

- `RestartCount=0`, `OOMKilled=false`, **zero preemptions**, zero OOM lines — NOT memory.
- Boot/run logs (09-29 14:50-14:51) show the cause: **Triton kernel JIT compilation
  during inference** — `_qsa_mqa_paged_kernel`, `_qsa_sparse_paged_gqa_splitk_kernel`,
  `_compute_local_logits_stats_kernel`, `_rejection_kernel`, `_resample_kernel`,
  `_expand_qsa_indices_kernel`, `_qsa_pre_indexer_kernel` all compiled lazily at
  request time (jit_monitor WARNING: "causes a latency spike; consider extending
  warmup to cover this shape/config").
- The profile sets `VLLM_GDN_DECODE_KERNEL=triton` (verified in the container env).
  The **plain mixed-NVFP4/FP8 build must DROP it** — with it set, the QSA/GDN kernels
  are NOT precompiled at engine start; the 1.1 MB full-window prefill hit the
  `No available shared memory broadcast block found in 60 seconds` engine timeout
  (`shm_broadcast.py:801`) → 502.

This is the exact condition prompt-llm.md step 4(a) warned about:
"`VLLM_GDN_DECODE_KERNEL=triton` is set by the profile — the *plain* NVFP4 build
must drop it". It is a **config/weights-build incompatibility**, not a gate defect.

## What this means for the catalogue

`fast` stays **uncertified** (correct). It cannot serve the certified 262,144 window
as authored. The fix is a profile change (drop `VLLM_GDN_DECODE_KERNEL=triton` for
this build, or pre-warm the kernels at startup), then re-run gates 0-7. The engine
itself is sound (boots, serves small requests, KV count matches the derived pool);
gate 7's falsification of the DERIVED fixed cost did NOT occur — the pool is real.
The accuracy battery and needle gate are still owed AFTER the triton fix.

## Rollback performed

After the finding, `spark_llm_profile` was returned to `reasoning` +
`spark_llm_allow_uncertified: false` and converged detached (the box must keep
serving the certified daily driver). Evidence: the reasoning restart + its own
boot log's `GPU KV cache size: 515,786 tokens` (1.97×) confirmed back.

## Commands run (timestamps, read-only where possible)

```
# staging (detached, ~17 min)
nohup ansible-playbook -i inventory.ini playbooks/spark.yml --limit spark --tags spark-artifacts \
  -e spark_artifacts_fetch='["b1-awq","ple-int4","nvfp4-mixed","ple-nvfp4"]' >/tmp/hd469-artifacts.log 2>&1 &

# flip to fast (detached)
python3 - <<EOF  # host_vars: spark_llm_profile: fast, allow_uncertified: true
nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull >/tmp/hd469-fast.log 2>&1 &

# probes from a session NOT served by spark (entrim)
python3 scripts/spark-llm-probe.py --base-url https://llm.kogler.si/v1 all --profile fast

# rollback (detached)
# host_vars: spark_llm_profile: reasoning, allow_uncertified: false
nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull >/tmp/hd469-rollback.log 2>&1 &
```

Clock regime: the converge **applied** the cap (`/tmp/hd469-fast.log` header `Converging 8f6698b`,
stamp 16:33, the `clockcap` apply task ran) — but this report's numbers carry an **assumed**, not a
measured, regime: no sustained-under-load `clocks.sm` trace was captured, and `clocks.sm` read 2405 in
the **pre-cap** probe too, so a spot reading cannot prove 2418 was holding
([hardware-spark.md §GPU clock cap](../../docs/hardware-spark.md)). Anyone A/B-ing these `fast` numbers
against `reasoning` must re-sample the regime in the same window. `clocks.max.sm` is a capability field
and stays 3003 either way. MemAvailable/CmaFree at window end: 122,741,948 / 5,658,828 kB →
usable ≈ 117.1 GB (one end only — both ends next time).

⚠ Two capture gaps, so the next run does not repeat them: the probe leg here ran against
`https://llm.kogler.si/v1` while the brief names `https://llm.ts.kogler.si/v1` — record which endpoint
leg, or the number is not attributable across legs. And "zero preemptions / OOMKilled=false" was read
out of **logs**; the `/metrics` counters the brief asks for (`num_preemptions_total`, prefix hits,
`vllm:spec_decode_*`) were never captured, so gate 7's pool claim rests on the boot line alone
(pool size ✓) and **not** on a memory curve (never run). No timed number in this report was taken by a
spark-served session.
