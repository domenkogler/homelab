# HD-489 — arm `u4-pin` (tier 1: never-evict prompt pin, fraction 0.03)

Measured 2026-10-02 23:09–23:32 UTC on spark. Same image/weights as u1/u2/u3 (patched
lineage, AWQ + INT4), **one delta vs u2-blk**: `--never-evict-kv-cache-prompt-includes
"# Global instructions (loaded at every session start by pi)"` + `--never-evict-kv-cache-max-fraction 0.03`
(the owner-approved pin, verified in the live container argv). `max_num_seqs: 4` (inherited
from `_x`).

## Fidelity (PASSED)

- Accuracy battery **0 failures, 10/10 outputs**.
- KV pool unchanged: `GPU KV cache size: 515,786 tokens, 1.97x`.

## Speed legs (all clean)

| leg | seed | window (UTC) | dur | ttft_p50 | dec/stream | recomp_tok_delta | preempt | MTP | ok |
|-----|------|--------------|-----|----------|------------|------------------|---------|-----|----|
| C2  decode | 42 | 23:09:06–23:12:43 | 216s | 3577 ms | 20.7 | 8612 | 0 | 48.1% | 8/8 |
| C1  prefill | 43 | 23:12:48–23:22:56 | 608s | 53652 ms | 7.0 | 262560 | 0 | 51.5% | 8/8 |
| C2L long   | 44 | 23:23:00–23:31:59 | 538s | 2269 ms | 23.7 | 12915 | 0 | 46.5% | 12/12 |

## Reading — the pin is neutral on synthetic benches (as the premise predicted)

- **Decode 20.7–23.7 tok/s ≈ u2-blk (20.2–23.6)** — the pin costs nothing.
- **`recomp_tok_delta` identical to the non-pin arms** (8612/262560/12915): the bench dataset
  prompts do NOT contain the pinned "Global instructions" substring, so the pin never engages
  in synthetic legs. Its benefit can only show in **real sessions** whose project_context
  carries the substring (the premise's own caveat).
- **`preempt_delta=0` everywhere** — no eviction pressure to save, matching the pin-premise
  report's finding (5 preemptions in 3.2 days): there is nothing contending, so a pin has
  nothing to protect.
- **Worker GPU memory ~90.2 GB at rest** — identical to u2-blk/u3-s8; the 0.03 pin (~480 MB
  of the 16 GB pool) is invisible at this resolution. (Earlier "+119 GB" scare was a
  pid-column misread; col1 is the pid, col2 is MiB.)

## Verdict for the funnel

On synthetic pressure the pin is **neutral** (no cost, no benefit). Its justification is the
real-session prefix-hit rescue — and the premise report already measured that at **p95 ~11.3k
recomputed tokens ≈ 0.66 s TTFT effect**, which is ~2% of the tail. Unless a real long-session
trace shows the 0%-hit loop returning under occupancy, this arm has no number that beats
u2-blk. **Provisional: u4-pin is below u2-blk as a candidate** — the pin buys nothing measurable
on any bench we can run.

## Evidence

- `raw/atrest-*`, `raw/result-*`
- CSV rows: `spark/bench/results-v2.csv` (`t1-u4,20261002-230906/231248/232300`)
- VM cross-check: same monitoring-not-converged caveat.