# HD-489 — arm `v16b` (tier 3: upstream as published — T80 drafter + 65536 draft-vocab + seqs=8 + 8192)

Measured 2026-10-03 11:13–11:20 UTC on spark. **The full upstream recipe does NOT beat
ar-blk, and it is memory-infeasible for the long corroboration leg.**

**Profile**: `v16b` — AR AutoRound-hybrid + FP8 PLE disk-mmap (enforce_eager boot fix) +
**T80 dense-MTP drafter** (`Qwen3.8-Flash-Next-W4A16-AutoRound-hybrid-mtpdense-g32`, converted
this session, +4.8 GiB) + **65,536-id draft-vocab slice** (`K=65536 of 248320 (26.39%), sliced
head 162.5 MiB vs 620.5 MiB, saving 458 MiB/draft pass`) + `max_num_seqs: 8` +
`max_num_batched_tokens: 8192` (upstream's value). `Resolved architecture:
Qwen3_8FlashNextMTP`.

## Fidelity (PASSED)

- Accuracy battery **0 failures, 10/10 outputs**.
- Slovenian accepted-length: 1373-token prompt, coherent Slovenian (+`😊`), `finish: stop`.
- Boot healthy, RestartCount 0, KV pool 515,786 / 1.97×.

## Speed legs (C2L UNAVAILABLE — OOM guard)

| leg | seed | dec/stream | TTFT p50 | ITL p50 | MTP | cold_ok | ok | preempt |
|-----|------|-----------|----------|---------|-----|---------|----|---------|
| C2  decode | 42 | 33.1 | 708 ms | 51.9 ms | 26.7% | no | 8/8 | 0 |
| C1  prefill | 43 | 16.2 | 16945 ms | 53.0 ms | 28.0% | **yes** | 8/8 | 0 |
| C2L long   | 44 | **REFUSED** | — | — | — | — | — | — |

## Memory wall — the C2L leg could not run

`run-scenario.sh` refused C2L with its own safety guard:
```
ERROR: only 10.8 GiB usable (< 16 GiB floor) — would global-OOM the box (GB10 unified pool).
```
The full v16b recipe holds ~1.6 TB VSZ (engine pid 1,644,792 MiB incl. drafter + model) on the
121.6 GiB pool; `free` shows only ~11 GiB available after the model + drafter + KV. The box
cannot sustain a long decode leg without risking the global-OOM that historically killed sshd
(HD-315-era incident). **v16b as published is memory-infeasible for sustained load on this box.**

## Reading — below ar-blk even on what it CAN measure

| metric | ar-blk (t2 winner) | **v16b** | delta |
|--------|--------------------|----------|-------|
| C2 dec/stream | 35.1 | 33.1 | −6% |
| C1 dec/stream | 17.4 | 16.2 | −7% |
| C2 MTP accept | 49.6% | 26.7% | **−23pp** |
| C1 MTP accept | 54.6% | 28.0% | −27pp |
| C2L | 39.7 (cold_ok=yes) | **cannot run** | — |

The T80 drafter + draft-vocab push **MTP acceptance down to ~27%** (vs ~50% on ar-blk's
in-checkpoint MTP) — the bigger drafter + vocab sample worse — and decode ends up *below*
ar-blk. The only v16b win is ITL (~52ms vs ~64ms). And its memory footprint blocks the long
corroboration leg.

**Reproduction check**: upstream publishes 74.1/212.2 tok/s on their shared-prefix method;
our C2 (33.1, no shared prefix, cold_ok=no) is not method-comparable, but ar-blk's 39.7
corroborated is the best we can produce, and v16b does not reach it.

## Verdict

**v16b loses to ar-blk on decode AND cannot run sustained load (memory).** The upstream's own
"as published" recipe is not the winner on this box; the leaner **ar-blk (in-checkpoint MTP-3,
no T80, no draft-vocab slice)** is faster AND memory-feasible.

## Evidence

- `raw/atrest-*`, `raw/result-*` (this dir)
- CSV rows: `spark/bench/results-v2.csv` (`t3-v16b,20261003-111352/111616`)
- OOM-guard refusal (above) — the C2L non-run is itself the finding.