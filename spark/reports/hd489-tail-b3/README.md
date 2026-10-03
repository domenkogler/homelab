# HD-489 tail — B3: depth at the real workload (`ar-blk`)

Measured 2026-10-03 against the **live `ar-blk`** engine on spark.

## Verdict

**PASS (with one honest caveat)** — the real workload (p50 163,840-token prompts and ~90 %
of the window) runs with 0 preemptions on the p50 shape; the single ~236k session recorded
**one preemption** (`preempt_delta=1`), which is the gate-5 needle question, still owed.

| leg | command (verbatim) | result |
|---|---|---|
| p50 prompt | `C1_IN=163840 ./run-scenario.sh B3-deep C1` | **8/8 ok**, TTFT p50 **95.1 s**, ITL p50 69 ms, MTP 50.3 %, 0 preempts, `cold_ok=yes` (891 s), 47 W |
| ~90 % window | `S1N_IN=236000 S1N_NUM_PROMPTS=1 ./run-scenario.sh B3-s1n S1-N` | **1/1 ok**, TTFT p50 **143.5 s** (236k prefill), ITL p50 69 ms, MTP 57.6 %, **1 preempt** |

## Reading

- **C1@163840** confirms the harness's 140 k-token-per-turn reality is servable: 8 full
  163,840-token prefills, all 200, 0 preempts, prefill-bound TTFT (95 s p50) as expected at
  ~1,900 tok/s prefill. The "harness pays 140 k-token prefills every turn" premise holds and
  the winner takes it.
- **S1-N@236000** ran a single ~90 %-of-window session: served (1/1), TTFT 143.5 s, decode
  healthy — but **one preemption** during the 236k session. At 1.97× pool a single 236k
  session is ~90 % of the window; the prefill eviction is the exact regime the brief says gate
  5 (needle at ≥90 % depth, 3/3) must judge. So: **gate-5 remains owed**, and this preempt is
  the honest signal that the deep single-session case is the tight one.
- usable at rest 22.7–23.5 GiB across both legs; power 46–47 W during deep prefill.

## Evidence

- `raw/atrest-*B3-*` · `raw/result-*B3-*` · `raw/power-*B3-*` · `raw/benchlog-*B3-*`
- CSV rows on spark: `~/bench/results-v2.csv` (`B3-deep-C1` at 20261003-155631,
  `B3-s1n-S1-N` at 20261003-161128)
- Runner: external seat (`agent:external`)