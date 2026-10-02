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

---

## Run #3 (2026-09-29): the clock cap converged; the "under-cap baseline" is NOT on the record

**session `hd469-run3-0019`** · rule 0 respected (the run's own model was not served by spark).

### ⚠ Correction (2026-09-29 follow-up review): item 1 below is still OPEN

This run's commit (`277691a`) and the `todo.md` row both asserted that the under-cap baseline "is
measured" and pointed at this directory for the numbers. **They are not in this directory and never
were** — so this directory is not the evidence the row cites, and the claim is retracted here rather
than repeated. What was checked, line by line:

| What the commit/row pointed here for | In this file? | Independent check |
|---|---|---|
| `ctx 262144` → 200 at **258,863 prompt tokens** | ✗ (the only `258,863` here is **run #1**'s, same section header it was attributed to run #3) | identical to run #1's value → indistinguishable from a carried-forward copy |
| `concurrent 4` all 200 · `RestartCount=0` | ✗ | both also run #1's values |
| `GPU KV cache size 515,786` | ✗ (0 hits) | re-read live from the engine on 2026-09-29: **515,786 / 1.97×** ✓ true — but it is the **rollback** boot's line (16:54), not a baseline-window reading |
| clocks + `MemAvailable`/`CmaFree` at **both** ends of the window | ✗ | — |
| `/metrics`: preemptions, prefix hits, `vllm:spec_decode_*` | ✗ | — |
| raw probe stdout | ✗ | nothing retained in `/tmp` either — only the five ansible logs |

This is the **same defect** run #2 filed against run #1 (results in the row and the commit message,
none in the evidence dir), re-introduced. Rule it enforces, restated: **an evidence directory that a
row cites must contain the raw output, or the row must not cite it.**

### What run #3 did prove, with retained evidence

- **The clock cap converged.** `/tmp/hd469-reasoning.log`, `--limit spark --no-pull`, header
  `Converging 043ff4a`, start stamp **2026-09-29 15:45:03**, recap `ok=132 changed=3 failed=0`; the
  `clockcap` apply task ran (`changed`) and the boot unit installed + `enabled`.
- **`clocks.max.sm` is a dead field for this purpose** — 3003 before and after the lock, because it is
  a *capability* field (`-q -d CLOCK` → *Max Clocks*). Removing the read-back assert was therefore
  correct, not a workaround: the assert failed a converge that had genuinely applied the cap. Owner
  ruling `043ff4a`; decision logged in
  [`docs/services-rejected.md`](../../../docs/services-rejected.md); the falsified-field table and the
  surviving discriminator (sustained `clocks.sm` **under load**: 2496–2515 pre-cap, ~2411 capped) are
  in [hardware-spark.md §GPU clock cap](../../../docs/hardware-spark.md).
- **The box was rolled back correctly** — live re-read: `reasoning`, `restarts=0`, `healthy`, KV line
  `515,786 tokens / 1.97×`, `host_vars` back to `reasoning` + `allow_uncertified: false`.

### Two findings the run's own report got wrong

1. **"Converge 1 (00:23, `043ff4a`): FAILED at the clockcap assert"** is not a possible statement —
   `043ff4a` *is* the commit that removes that assert (15:44:55), so it cannot have failed on it. The
   failed converge's own log is gone: the brief's fixed log path (`>/tmp/hd469-reasoning.log`) meant
   the retry **truncated the only evidence of the failure**. New rule for this lane: one log file per
   attempt (`/tmp/hd469-<profile>-<HHMM>.log`) — a failed converge is the most valuable log you have.
2. **"the cap's real signal is `clocks.sm` sitting at 2411 under load + idling to 305 at rest"** was
   written without the sample: no command, no timestamp, no load definition, no trace file. And it is
   not self-eviding — the prep session's **pre-cap** read-only probe recorded `clocks.sm` **2405**, so
   a spot reading cannot discriminate. The sustained-under-load trace is owed (below).

### Still owed: the under-cap baseline (handover, exact)

**Rule 0 binds whoever takes this:** `PI_PROVIDER=spark` bars the session from every timed leg — which
includes this follow-up review session, so it was NOT taken here. A non-spark-served session must run,
in one window, with the sampler running alongside:

```bash
ssh spark 'nvidia-smi --query-gpu=timestamp,clocks.sm,power.draw,temperature.gpu,clocks_event_reasons.active --format=csv -l 5' >/tmp/hd469-baseline-clocks-<HHMM>.log 2>&1 &
awk '/MemAvailable|CmaFree/' /proc/meminfo          # at BOTH ends
python3 scripts/spark-llm-probe.py --base-url https://llm.ts.kogler.si/v1 all --profile reasoning  # RAW stdout, verbatim
ssh spark 'docker logs vllm-qwen-spark 2>&1 | grep -E "Available KV cache memory|GPU KV cache size|Maximum concurrency"'
ssh spark 'curl -s localhost:8000/metrics | grep -E "num_preemptions_total|prefix_cache|spec_decode"'
```

Paste the outputs into this directory as `baseline-<date>.md`. Only then may `todo.md` say the
under-cap baseline exists. Gates 5–7 (§Still owed above) are untouched by any of this.

