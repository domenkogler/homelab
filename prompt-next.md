# Next Session — Where to Start & What's Next

> ⚠ **SUPERSEDED, kept only as history (2026-09-21).** This 2026-09-15 spark S1 handoff is now content belonging to
> [`prompt-376.md`](prompt-376.md) — its §3 pending-tests list is that brief's row 1 — and the branch it says
> "needs merge" no longer exists (all 2026-09 session branches were merged and swept, see
> [todo-table.md](todo-table.md) §0). **Do not start a session from this file.** The standing handoff is
> [prompt.md](prompt.md); the dispatch rule for a session is [prompt.md](prompt.md) §4. The parent deletes this file
> in a §4 cleanup commit (O7) once lane 376 has taken its content, which it has.

> Handoff written **2026-09-15** at the end of the spark S1 stability-sweep session
> (`session/s1-stability-sweep-20260915-0801`).
> Read this first, then `todo.md` HD-367 + `spark/BENCHMARK-PLAN.md` §6a/§9, then `docs/hardware-spark.md`
> §Benchmark/engine selection.

---

## 1. State of spark (as of 2026-09-15, measured on the live box)

**Verdict: PRODUCTION-READY for casual/chat inference now. Gated for agentic/max-context work
pending the tests in §3.**

| Item | Value (certified on this box) |
|---|---|
| Live config | **vLLM, `gpu_memory_utilization 0.82`, `max_model_len 262,144`** (model native max), cage 105G, MTP-3, AWQ-W4A16+PLE-INT4 |
| Util ceiling | **0.82 max servable** (0.84/0.86 crash engine during serve — host wedge, power-cycle; 0.88 no headroom) |
| Max ctx | **262,144 native** (300k rejected at startup — needs `VLLM_ALLOW_LONG_MAX_MODEL_LEN`+YaRN, needle-gated) |
| Certified | 250k @ 95% fill, 0 preemptions, host alive; 200k/175k/150k all pass; acc-gate **8/10 serial + 8/10 concurrent-3** |
| Concurrency | 3 concurrent short prompts: engine 3 reqs/0 waiting, accuracy holds (8/10) |
| SSOT | `group_vars/spark.yml` updated to 0.82/262144 (converge on spark to apply) |

**Key operational facts:**
- **Cold prefill is NVMe-I/O-bound**: ~465 MB/s weight reads → first max-fill request after restart ~13 min TTFT. **Warm** repeat = ~1640 tok/s (weights hot in page cache). Production agent turns on the same boot are warm.
- **Never raise util above 0.82** — 0.84+ crashes the engine (and can wedge the host; power-cycle recovers).
- **Never raise ctx above 262,144** — startup validation rejects; override needs YaRN + needle-test.

## 2. Committed this session (on `session/s1-stability-sweep-20260915-0801`, needs merge)

```
fa85406 bench(spark): S1 stability sweep plan — drop C3 from S1, sweep util then ctx, 1 session only
```
Plus uncommitted close-out edits: BENCHMARK-PLAN §6a/§9 rows (200k/250k/262k/300k/acc-gate),
`group_vars/spark.yml` → 0.82/262144, `docs/hardware-spark.md` status line, `todo.md` HD-367
pointer. Run `validate-all.sh` green → commit → merge to main (fast-forward).

## 3. ⚠️ PENDING TESTS before full production trust (agentic / max-context)

1. **Needle-test at 262k** — long-context *correctness* (does it reason correctly at depth, not just not-crash?). The QSA/XQA corruption trap ≥120k on sm_12x is documented (sglang#36806/#36845) — needle-test every profile is mandatory.
2. **tool-call EMPTY fix** — `--enable-auto-tool-choice` is NOT registering tools (every acc-gate run: tool-call EMPTY). **This blocks agentic work.**
3. **True 3×87k-token fill stress** — the concurrent acc-gate used short prompts (~100 tok, KV 11.5%). A real 3×87k = 261k KV fill is untested.
4. **NVFP4 + FP8 KV lane (S2/S3)** — the "really fast on GB10" config (~40 tok/s decode, 100 @ 4-conc). Weights-download IaC EXISTS (`roles/spark-artifacts`, NVFP4-ready); missing = manifest entries + SGLang compose + harness param. Accuracy-anchor (98/100) is AWQ-only; NVFP4 = throughput play.
5. **FP8 KV (ladder #7)** — independent of weights, ~2× KV density; accuracy-gated (98/100 measured on bf16 KV); hold until needle-test done.

## 4. Notes / gotchas for the next session

- The `dgx-dashboard-socat` container is crash-looping (stale leftover — was supposed to be removed in HD-364; not blocking, but should be cleaned).
- Bench harness on box: `/home/ansible-admin/bench/` — `run-scenario.sh` (S1-N scenario added), `accuracy-gate.sh` (serial), `accuracy-gate-conc.sh` (concurrent, fixed 2026-09-15 — use this for concurrency; the first version had an associative-array-through-xargs bug that truncated prompts).
- Engine health: `curl localhost:8000/health`; metrics: `curl localhost:8000/metrics`.
- Config edits are done on the box at `/opt/spark-ai/docker-compose.yml` (rendered from the repo template + `group_vars/spark.yml` SSOT) — converge on spark to apply SSOT, or `sudo docker compose up -d vllm-engine` after a manual edit.
