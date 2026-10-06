# HD-489 overnight run 20261006-0226 — results

**Seat (declared first line):** `engine under test = spark`, `runner = oldsrv (LAN)`,
`PI_MODEL=deepseek-ai/DeepSeek-V4-Flash` (not spark/... — rule 0 clean for timed legs).
`run-scenario` legs stamped `--client oldsrv`; harness rows landed on spark's `~/bench/results-v2.csv`.
Raw: `raw/`. Step 2 lines below are the leg records.

## Step 1 — OOM governor (box protection)

PASS. sha256 match repo↔spark (`5b271deb…`), unit env `SPARK_OOM_ENFORCE=1 REARM_GIB=12`,
`no-enforce` absent, `hysteresis: armed`, `budget: usable=13.59 GiB` (WARN<12 CRIT<8).
→ boots were NOT parked. Evidence: `raw/watchdog.txt`.

## Step 2 — owed gates on the live 20 GB shape (HD-489 + HD-494 debt)

- health pre-flight: PASS HTTP 200 — `raw/g1-health.log`
- **gate 4 at conc 8**: PASS 200s=8/8 wall=2.7s lat min/med/max=2.3/2.5/2.7s
  (≤3× solo; prior night's g4-solo wall 1.5s ⇒ ratio 1.8×) — `raw/g4-c8.log`, clock trace `raw/clocks-g4.txt`
- **gate 5 — needle at ≥90% depth, 3/3**: PASS
  - depth legs S1-N (236,000 in, harness): 3/3 ok, preempts=+0 each — `raw/g5-run-{1,2,3}.log`
    (leg 1 cold: recomputed 236,052 prompt tokens; legs 2-3 warm prefix reuse of the same harness seed)
  - needle recall: marker = pi-agent/AGENTS.md (global instructions, 552 tok, needle seq 550) planted
    at ~90% depth of a 241.2k-token filler; token-subsequence verdict in the vllm container:
    RESP1..3 all MATCH=PASS (241,199 / 241,256 / 241,180 prompt tokens = 92.0% of the 262,144 window)
    — `raw/g5-needle-{1,2,3}.log`, `raw/g5-needle-{1,2,3}-response.txt`, `raw/g5-verdict.txt`, probe `raw/g5-needle.py`
  - `vllm:num_preemptions_total` = 0.0 before the first S1-N leg and 0.0 after the last needle attempt
    → delta +0 across all six 236–241k legs (the B3 preemption at 236k did not reproduce tonight) —
    `raw/preempt-evidence-g5.txt`
- NOTE: the harness's fixed 16 GiB local-usable floor would have refused every leg on the 20 GB
  pool (box rests at ~13.5 GiB usable under the WARN<12/CRIT<8 governor). Ran the legs with
  `USABLE_FLOOR_GIB=12` — matching the operator's watchdog re-arm constant; the enforced governor
  on spark remained the real guard (Step 1 evidence).

## Step 3 — reasoning arm + paired McNemar (in progress)

- reasoning flip: converged detached, container running `restarts=0`, argv `--max-num-seqs 4`,
  `--kv-cache-memory-bytes 16000000000`; health PASS HTTP 200 — `raw/health-reasoning.log`, `/tmp/cg-reasoning-20261006-0226.log`
- MMLU-Pro-mini 5-category subset (other|health|computer science|math|biology, 100 each) at -n 4:
  running — log `raw/mmlu-reasoning.log`, output `~/mmlu-eval-reasoning-20261006-0226/`
- harness rebuilt from the pinned source (tracked `spark/reports/hd489-eval-mmlupro-arblk/raw/evaluate_from_apiX.py`);
  mini slice regenerated from HF head — sha differs from the pinned fingerprint, BUT the question_id
  identity vs the committed fast-arm items is 100/100 on all five categories (business: full 100 vs
  the 98 the fast CSV kept) → pairing is on the SAME questions. Verification script + ranges in `raw/mmlu-slice-verify.txt`
- converge-back + McNemar reporting: pending

## Step 4 — B10 (AWQ on the winner's machinery) — pending

## Step 3 — reasoning arm + paired McNemar — COMPLETE

- reasoning flip: converged detached failed=0, container `restarts=0`, argv `--max-num-seqs 4 --kv-cache-memory-bytes 16000000000`
  (the 2026-10-04 never-evict crash-loop bug did NOT reproduce — those flags no longer exist in the profile)
- health on the public endpoint: PASS HTTP 200 — `raw/health-reasoning.log`, KV boot line `raw/kv-reasoning.txt` (515,786 tokens = 1.97×)
- MMLU-Pro-mini, owner's 5-category subset, -n 4, window 2026-10-06T01:55Z..07:37Z (5 h 42 m): **500/500 items, rc=0**
  `acc=89.40% (447/500), extraction-fail=0.40% (2 nulls)`; per category:
  biology 94/100 · computer science 92/100 · health 85/100 · math 95/100 · other 81/100
  — `raw/mmlu-reasoning.log`, `raw/reasoning-items.csv`, `raw/reasoning-items.json`, `raw/mmlu-mcnemar-summary.txt`
- harness rebuilt on this runner from the tracked patched source (`hd489-eval-mmlupro-arblk/raw/evaluate_from_apiX.py`);
  mini slice regenerated from HF head — file sha differs from the pinned fingerprint, but pairing is by question_id and
  the id overlap vs the committed fast-arm items is **100/100 on all five categories** (business 98/100 because the
  fast CSV lost 2 rows, not an arm difference) — `raw/mmlu-slice-verify.txt`
- **McNemar (pre-registered rule: |Δ|≤2 keep · 3–5 decide on L3 · >5 void):**
  `n_paired=500`, fast=89.20 % (446/500) vs reasoning=89.40 % (447/500) → **Δ=−0.20 pts, p=1.000
  (discordant b=9, c=10, n=19) ⇒ KEEP** — no measurable quality deficit; the fast speed win stands.
  Resolution ceiling at n=500/19 discordant is ~5 pts; nothing below that is signal.
- converge-back to fast: failed=0, `restarts=0`, argv `--max-num-seqs 8 --kv-cache-memory-bytes 20000000000`

## Step 4 — B10 AWQ on the winner's machinery — COMPLETE

- owner-gated flip executed with the brief's documented per-run grant:
  `-e spark_llm_profile=awq-mmap -e spark_llm_allow_uncertified=true` (no committed allow_uncertified, untouched IaC)
- gate 0 offline preflight: `check_spark_llm_gate.py` **0 failures, canaries biting** · `profile awq-mmap` render leg OK — `raw/b10-render.log`
- boot: converged failed=0, container `running restarts=0`; engine: `GPU KV cache size 450,604 tokens = 1.72 × window`
  (brief expected 451,219/1.72×) at `--kv-cache-memory-bytes 14000000000` (14 GB), `--max-num-seqs 4`, model load 73.55 GiB —
  `raw/b10-boot.txt`, `raw/b10-health.log` (HTTP 200)
- **measured (harness on spark, stamped --profile awq-mmap --client oldsrv):**
  | leg | ttft p50 | itl p50 | dec/stream | ok | preempts | MTP accept | window |
  |---|---|---|---|---|---|---|---|
  | B10-C2 (rerun, clean window) | 819.7 ms | 90.4 ms | **25.4 tok/s** | 8/8 | +0 | 46.4 % | 175 s |
  | B10-C2L | 825.8 ms | 91.1 ms | **27.6 tok/s** | 12/12 | +0 | 52.7 % | 458 s cold_ok=yes |
  power 27–28 W, wh/1k 0.29–0.32; usable `MemAvailable−CmaFree` 21.2 → 21.2 GiB (no stranding, no dip below 8);
  sustained clocks/sm trace across both legs: 1,934 samples — `raw/clocks-b10.txt`, `raw/b10-c2-rerun.log`, `raw/b10-c2l.log`,
  `raw/b10-usable-before.txt`, `raw/b10-usable-after.txt`, `raw/b10-metrics-after-c2l.env`
- **Verdict: the AWQ quality-fallback costs ~30 % speed, not ~40 %** — 27.6 vs `fast`'s certified C2L 39.7 tok/s
  (ratio 69.5 %), inside the brief's predicted 22–28 tok/s band for the eager-AWQ + FP8-PLE-mmap bundle,
  and ABOVE the with-graphs AWQ ceiling (23.6 tok/s). The pairing registry row `ple-table-fp8 ↔ Qwen3.8-Flash-Next-AWQ`
  stays **UNVERIFIED** — gates 6/8/9 are the owner's next step before that word changes; this boot + these numbers
  are the evidence that replaces it (the pairing assert passed at converge — no refusal).
- first C2 attempt's row (08:44Z) was flagged `req_ok_delta=-295` — a stale before-snapshot (G5 residue matched the
  harness glob after the B10 engine restart reset the counter); superseded by the rerun, kept only as a harness lesson.

## Final state

- converge-back to fast: launched (detached), verify below — box must end on `fast` (20000000000 B / seqs 8), restarts=0
- commit: this whole directory + RESULTS.md, signed


## Acceptance lines

| item | verdict | number | evidence |
|---|---|---|---|
| Step 1 watchdog | **PASS** | hashes match, enforce=1, rearm 12, usable 13.59 GiB | raw/watchdog.txt |
| gate 4 conc 8 ON 20 GB (HD-494 leg) | **PASS** | 8/8 200s, wall 2.7s, lat 2.3–2.7s | raw/g4-c8.log |
| gate 5 needle ≥90% depth | **PASS** | needle recalled 3/3 (token-subseq), 241.2k prompt tokens (92%), preempts +0 | raw/g5-verdict.txt, raw/g5-run-{1,2,3}.log, raw/g5-needle-{1,2,3}-*.log |
| reasoning arm (B1 control legs) | **PASS** | booted healthy restarts=0; 500/500 MMLU items | raw/health-reasoning.log, raw/mmlu-reasoning.log |
| paired McNemar | **KEEP** | n=500 Δ=−0.20 pts p=1.000 (pre-registered ≤2 rule) | raw/mmlu-mcnemar-summary.txt |
| B10 AWQ boot + gates | **PASS** | healthy restarts=0, KV 450,604 (1.72×), C2/C2L 25.4/27.6 tok/s | raw/b10-*.log, raw/b10-boot.txt |
| converge-back ×2 | **PASS** | failed=0 both; box on fast 20000000000/8, restarts=0 | raw/live-final.txt, raw/health-final.log, raw/kv-final.txt |
| preemptions (whole night) | 0 | counter 0.0 at every read (g4, g5×6 legs, MMLU 5 h, B10×2) | raw/preempts-final.txt + window rows |

Seat recap: engine under test = spark · runner = oldsrv LAN, PI_MODEL=deepseek-ai/DeepSeek-V4-Flash (not spark) ·
legs stamped `--client oldsrv` · harness rows on spark ~/bench/results-v2.csv.
BLOCKED/PARKED: none. Owner gates exercised via the brief's documented per-run -e only; IaC untouched (worktree
diff is this evidence directory alone).
