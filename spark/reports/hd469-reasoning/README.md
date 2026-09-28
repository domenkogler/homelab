# HD-469 `reasoning` profile — the certified lane, and what it does NOT yet prove

Profile: `reasoning` — AWQ W4A16 + PLE **INT4** + MTP3 on the digest-pinned vLLM fork
(`vllm/vllm-openai:qwen38-flash-next@sha256:fc120ece…`), `kv_cache_dtype: auto`,
`kv_cache_memory: 16,000,000,000 B`. The owner's daily driver and the only profile whose
stability is certified.

This directory existed because the catalogue's `certified_evidence:` had **no report of its
own** — run #1 proved the lane against the live engine and wrote the result into `todo.md`
and the commit message instead of into an evidence directory (prompt-llm.md run #2 lists it
as a defect). So: what is actually on the record, with provenance, and what is still owed.

## What run #1 measured (2026-09-28, session `spark-llm-cert-1445`)

Recorded in `todo.md` HD-469 and in commits `ebe6956` (the mechanism) + `b1c7572` (the live
proof); re-stated here so `certified_evidence:` has a target:

| Gate | Measure | Result (as recorded) |
|------|---------|----------------------|
| 0 render | `validate-docker-services.py --only spark-ai` + probe `profile reasoning` | PASS; KV auto 16 GB = **515,679 slots** = 1.97 × the 262,144 window |
| 1 boot | converge, then `/health` + `RestartCount` | healthy, no cosmetic container recreation: the `reasoning` render is structurally equal to the pre-HD-469 template, and the container's argv matched the certified render |
| 2 non-interference | probe `health` + `reasoning` | PASS — `/health` 200; thinking OFF emits no reasoning, thinking ON emits reasoning (the field is `reasoning`, not `reasoning_content`, on this build) |
| 3 real depth | probe `ctx 262144` | PASS — HTTP 200 at **258,863 prompt tokens** (≥ 80 % of the ask) |
| 4 concurrency | probe `concurrent 4` | PASS — 4/4 HTTP 200 |
| 5 needle at depth | pi-harness §3 protocol at ≥ 90 % depth | **not run in that session** — inherited from the pre-HD-469 reasoning-lane evidence |
| 6 accuracy | fixed 15-prompt battery | **not run** — this is the live certified config, the accuracy anchor predates the refactor |
| 7 memory curve | oom-watchdog samples over a working day | **not re-run for the refactor** — the peak-bound verdict is the stability chain below |

The stability evidence this profile rides on is [`../stability/README.md`](../stability/README.md):
2026-09-18, 3-rung load chain, `2×240,000 = 480,105 tok ≈ 94.6 %` of the pool, 0 kills /
0 restarts, `usable` 18.84 → **worst 17.78 GiB**, engine top-pid +1,278 MiB over ~1.5 h.
**17.78 GiB is the number the whole host-floor arithmetic is gated on**
(`spark_llm_device_hold_ceiling_bytes` in `group_vars/spark.yml`).

## Read-only state check, 2026-09-28 18:5x (the HD-469 prep session)

Taken by a session that is **served by this engine**, which is exactly why it took
read-only state reads and no bench numbers (prompt-llm.md non-negotiables, incident #6).
Commands are one ssh round-trip each; re-run them, they are cheap:

```
$ ssh spark 'docker inspect -f "restarts={{.RestartCount}} status={{.State.Status}}" vllm-qwen-spark'
engine restarts=0 status=running
$ ssh spark 'awk "/MemAvailable|CmaFree/" /proc/meminfo'
MemAvailable: 25,880,580 kB     CmaFree: 143,528 kB      → usable ≈ 24.5 GiB (idle, healthy)
$ ssh spark 'nvidia-smi --query-gpu=clocks.sm,clocks.max.sm --format=csv'
2405 MHz, 3003 MHz
```

**The clock cap is NOT in effect on the box.** `clocks.max.sm = 3003`, not the 2418 the
`spark-gpu-clock-cap.service` (tag `clockcap`, `roles/spark`) asserts. That role is on the
HD-469 prep branch and has never been converged — so *every timed number in the repo*
(≈11 tok/s decode, 17,008 tok/s re-prefill, `SM_CLOCK` 2509 MHz) is a pre-cap, uncapped
reading, and the first under-cap run of this lane is the baseline from then on.

## Still owed on this lane (do not treat the row as done)

1. **The under-cap baseline.** Converge the clock cap, then re-run
   `spark-llm-probe.py --base-url https://llm.ts.kogler.si/v1 all --profile reasoning`
   from a session whose model is **not** spark, with `clocks.sm` / `clocks.max.sm` /
   power / temperature recorded at BOTH ends of the window, plus the engine's own
   `Available KV cache memory` + `GPU KV cache size` lines and the `/metrics` counters
   (preemptions, prefix hits, `vllm:spec_decode_*`).
2. **Gates 5–7 for the refactored render** (needle at depth, the accuracy battery, one
   working day of watchdog samples). The lane is certified on the *stability* chain, not on
   a post-refactor accuracy or memory-curve run.
3. **`certified_evidence:` maintenance** — it points here + at the stability report; a new
   run appends to THIS directory, it does not rewrite the table above.

## Rollback reference

This profile is the rollback target for every other profile: flip
`spark_llm_profile: reasoning`, `spark_llm_allow_uncertified: false`, converge **detached**
(~20 min cold boot). No override, no download.
