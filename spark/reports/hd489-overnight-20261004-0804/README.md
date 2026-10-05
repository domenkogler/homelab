# HD-489 — overnight run 20261004-0804: the `fast` suite, and the `reasoning` arm that never booted

**Why this exists.** The unattended-overnight run-sheet (MMLU-Pro-mini on the served engine at
`-n 8`, the gate legs still owed on the new 25 GB / `max_num_seqs 8` shape, an fp8 re-probe, then the
`reasoning` arm and the paired McNemar against it) lived in `prompt-gemma4.md`; that brief is retired
and the run-sheet now lives in
[`prompt-remaining-bench.md`](../../../prompt-remaining-bench.md) §Overnight driver. This is the
evidence directory for run `20261004-0804`, executed by `runner=DomenP14s/external-model` (raw files
in `raw/`, verbatim).

**Rule 0 status.** Every timed leg was taken by the external runner against
`https://llm.kogler.si/v1`; the session that wrote this directory ran no leg. Bearer values were
never written — every probe line records `bearer len=32 (value not printed)`.

## What the run measured

| leg | verdict | evidence |
|---|---|---|
| health pre-flight, `fast` | PASS HTTP 200 | `raw/health.log`, `raw/live.txt` (boot `2026-10-03T20:39:05Z`, `restarts=0`) |
| MMLU-Pro mini, `fast`, `-n 8` | **89.63 %**, n=1398, extraction-fail 0.86 % (12 null preds) | `raw/acc-fast.txt`, `raw/mmlu-fast.log`, `raw/mmlu-fast-items.csv`, `raw/mmlu-fast-summary.txt` |
| gate 4, solo | PASS — 200s=1/1, wall 1.5 s | `raw/g4-solo.log` |
| gate 4, **concurrency 8** (the leg that was owed on the 25 GB/seqs-8 shape) | **PASS — 200s=8/8, wall 3.0 s, lat min/med/max 2.6/2.7/3.0 s** | `raw/g4-c8.log` |
| depth 163,840 | PASS — http 200, prompt 161,813 tokens (98.8 % of the ask), 77.3 s | `raw/d163k.log` |
| depth 236,000 | PASS — http 200, prompt 233,033 tokens (98.7 %), 116.4 s | `raw/d236k.log` |
| fp8 KV re-probe | **BLOCKED-ON-IMAGE** — the pinned build declares `supported_kv_cache_dtypes = ["auto","bfloat16"]`; an engine-pin question (HD-473), not a config flip | `raw/fp8.log` (Leg A registry + the source grep that says so) |
| `reasoning` flip | **BLOCKED — engine crash-looped, `restarts=105`** | `RESULTS.md` line 1 verbatim below, `raw/health-reasoning.log` (`/models → HTTP 502`) |
| converge back to `fast` | restored, PASS | `raw/live-after.txt` (boot `2026-10-04T22:16:56Z`, `restarts=0`, `GPU KV cache size: 806,269 tokens`, 3.08× the window), `raw/health-final.log` |

The driver's own record, verbatim (it was `RESULTS.md` at the repo root before this directory was
made its home, and it stays word-for-word):

> BLOCKED: reasoning boot — profile reasoning crash-loops (restarts=105): vLLM api_server.py rejects
> --never-evict-kv-cache-prompt-includes --never-evict-kv-cache-max-fraction 0.25 in the reasoning
> cmd; those flags are fast-pool-only per §8; no re-converge per §7; going to §8 to restore fast.

That BLOCK is why the McNemar pair never ran, and it turned out to be a profile bug, not a runtime
condition: the `--never-evict-kv-cache-*` pair exists only in the patched `ultrafast` lineage, and the
2026-10-03 "ONE value for every profile" change had aliased it into `reasoning`/`graded`, whose image
has no such argument. Mechanism, ruling and the new invariant:
[docs/spark-llm-profiles.md](../../../docs/spark-llm-profiles.md) §Never-evict prompt pin ·
[the decision row](../../../docs/services-ai-rejected.md) ·
[the counter pass that followed](../hd489-never-evict-off/README.md).

## The score, at the resolution the next leg needs

`raw/mmlu-fast-summary.txt` carries per-category counts, nulls and wall, and the owner's 2026-10-05
subset (**computer science · math · other · health · biology**) at **446/500 = 89.20 %**, ±1.39 pts,
≈3.98 h at `-n 8` — the shape the next pass runs. `raw/mmlu-fast-items.csv` is the McNemar input:
`(question_id, category, correct, pred, answer)` for all 1398 items, 1398 unique ids, recomputed
here from the harness JSONs (1253 correct, 12 nulls — it reproduces `raw/acc-fast.txt` exactly). The
per-item CoT text stayed on the runner (`~/mmlu-eval-fast-20261004-0804/`, 2.0 MB, ephemeral); nothing
in this directory needs it, and the paired test needs only `correct` per id.

Note the budget finding: 14 categories took **15.48 h** wall (`raw/mmlu-fast.log`: 06:07:24Z →
21:36:16Z) against the brief's 5 h. That is why the brief now names the 5-category subset.

## What nearly lost this evidence

`spark/.gitignore:30` ignores `*.log`, and `EV=` pointed *inside* the worktree, so nine of this run's
fourteen raw files — every gate, depth, fp8 and health line, i.e. all of it except the MMLU totals —
were untracked and would have died with the worktree. They are force-added here, and the ignore now
exempts `spark/reports/**/raw/*.log`: the 19 `.log` files already tracked under
`spark/reports/stability/` show the bypass was the habit, and a run whose evidence silently
disappears is a run that did not happen.

## Reproduce / resume

```bash
# score the committed items file (no engine needed)
python3 - <<'EOF'
import csv; rows=list(csv.DictReader(open('raw/mmlu-fast-items.csv')))
c=sum(int(r['correct']) for r in rows); print(len(rows),'items', c, f'{100*c/len(rows):.2f} %')
EOF
# the reasoning arm, when it is owed (prompt-remaining-bench.md §Overnight driver), then pair on question_id:
#   b = {id: correct} for each arm; McNemar's exact test on (b_a=1,b_b=0) vs (b_a=0,b_b=1)
```

**Linked from:** [`todo.md`](../../../todo.md) HD-489 ·
[`docs/spark-llm-profiles.md`](../../../docs/spark-llm-profiles.md) ·
[`spark/reports/hd489-never-evict-off/README.md`](../hd489-never-evict-off/README.md)
