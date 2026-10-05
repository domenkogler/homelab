# Brief: HD-489 tail — the benches that are still missing, and the four findings that need no boot

> **Role:** single-lane brief for the **measurement tail of HD-489** (the funnel's 12 arms are all
> measured; this brief closes the evidence and the claims around the winner).
> **Linked from:** [`todo.md`](todo.md) HD-489 row · [`prompt.md`](prompt.md) §3 wave table ·
> successor to [`prompt-fast.md`](prompt-fast.md) (read it for the funnel shape; its Corrections 1–2
> are load-bearing and must be copied into `docs/spark-llm-profiles.md` §7 before that brief dies).
> **Rule 0 first.** A session whose own model is served by `spark/…` may take **no timed number**.
> Counter/log/`docker inspect` reads are legal from any session; legs are not. Stamp every leg with
> `--client` (`run-scenario.sh` defaults it to hostname + `PI_MODEL`). Evidence:
> [`spark/llm-profiles/README.md`](spark/llm-profiles/README.md) §Rule 0.
>
> **Operator fills in at dispatch (blank until then):** `engine under test = ________` ·
> `runner = ________`. If either is blank when the session starts, ask once, then proceed and write the
> answer into the leg reports' confound ledger — an unstated seat is how a contaminated number gets
> into a doc. See §Runner seat and engine placement.

## Where the lane actually stands

Done: 12 arms measured with C2/C1/C2L, `ar-blk` declared winner and **live** (verified 2026-10-03:
`vllm-qwen-spark` healthy, `RestartCount=0`, `--enforce-eager`, `spec{mtp,3,block,probabilistic}`,
AR-hybrid 71 G + FP8 table 49 G on `/`, `GPU KV cache size: 515,786 tokens / 1.97x`), losers written
into [`docs/services-ai-rejected.md`](docs/services-ai-rejected.md), image pin recorded
(`versions.yml:311`).

Not done: `ar-blk` is `certified: false` while `host_vars/spark.kogler.si.yml:30` runs it with
`spark_llm_allow_uncertified: false` — **the next spark converge refuses**; the owning docs hold no
`ar-blk` number at all; the accuracy outputs for every HD-489 arm exist only on the box; and the
quality axis of the winner (a different checkpoint from a different quantizer) is **unmeasured**.

Also open, and cheap to close: the funnel's own client seats (`prompt.md` wave table) never said which
runner may take which leg — see the next section.

## Runner seat and engine placement — declare both in the first line of the session

The brief is seat-agnostic on purpose, but two of its halves invert depending on the answer. State it
as: **engine under test = `spark` | `laptop-lmstudio`** and **runner = `external` | `laptop-local`**.
Rule 0 then reduces to one test: **the runner's own model must not be the engine under test** — the
client stamp (`--client`, hostname + `PI_MODEL`) is what makes that checkable afterwards, so never
override it. Funnel precedent in `results-v2.csv`: `runner.external/deepseek-ai-DeepSeek-V4-Flash`.

**If engine = `spark` (the default for everything in §A/§B/§C).** Every §B item is a spark instrument:
`run-scenario.sh` drives `vllm bench serve` **inside the engine container**, `spark-llm-probe.py` reads
its expectations from `spark_llm_profiles`, `vm-window.sh` needs the `vllm:` series, and B2/B3 legs ask
for a **262,144** window. The laptop lane's equivalents are `scripts/laptop-llm/profiles.yml` +
`laptop-llm.py gate|probe-health|probe-client|probe-tools` — a different harness, and not in this brief.

**Runner capability, measured (HD-474, `agent-gemma-26b` = Gemma 4 26B A4B Q4_K_M, LM Studio
0.4.25+1 on loopback `:1234`):** window **32,768** at `--parallel 1`, decode **17.5–17.8 t/s**, cold
prefill **~250 t/s**, recall passing at **28,984 tokens** — certified *at* its ceiling. Mandatory reading
for this repo (README + CONVENTIONS + `docs/index.md` + the gate README + `spark-llm-profiles.md` +
`services-ai-bench.md` + this brief) is **159 KB ≈ 40 k tokens**, i.e. **it does not fit the leg**.
A laptop-local runner therefore executes this brief with the contract already evicted — the exact
failure class this lane keeps re-filing (dangling citations, evidence dirs without raw, prose that reads
as verified).

| work in this brief | laptop-local runner | external runner |
|---|---|---|
| §A repo fixes (append-only rejected-log row, worktree, signed commit, `validate-all`) | **no** — pure CONVENTIONS lawyering | yes |
| authoring/flipping B1, B7, B9, B10 (one-variable discipline, owner gates) | **no** | yes |
| the §E verdict, McNemar, `certified: true` | **no** | yes |
| B2/B3/B5 legs, B6's probe, §E driver invocations, L0 | **yes** — command is literal here, output is a number | yes |
| overnight §E babysitting (poll the log, spot a stall, alert) | **best tool for it** | overkill |

**Fence for any laptop-local child:** ONE deliverable per run · command pasted **verbatim** from this
brief, never re-derived · output in the acceptance format (`PASS / FAIL / BLOCKED` + number + path) ·
~10 min cap · on *any* error: stop and paste it, no improvising · no file edits, no commits, no dial
flips. Give each one a check that **can** fail — a check that cannot fail is not evidence (CONVENTIONS §6).

**If engine = `laptop-lmstudio`:** §A still applies as written, **§B does not exist** (no dial, no PLE,
no 262 k pool, no `vllm:` metrics, no OOM watchdog), and §C/§E run against `http://127.0.0.1:1234/v1`
with these measured costs — **prefill-bound, unlike spark** (250 t/s vs ~1,900):

| suite | laptop 26B A4B | spark `ar-blk` | note |
|---|---|---|---|
| MMLU-Pro **smoke 100** | ~1.5 h | ~10 min | the right laptop job: fits the 32 k window |
| MMLU-Pro mini 1,400 | ~21.6 h | 8.4 h c1 / ~2.8 h c3 | a weekend on a machine you also want to use |
| MMLU-Pro full | ~185 h | ~24 h c3 | not viable |
| SWE-bench Verified | ~20 h single-shot, ~135 h agentic | ~3.2 h | **and mostly invalid**: Verified contexts run 15–40 k against a 32 k window |

Use the laptop as the *driver* (it is off-spark, so Rule 0 is satisfied by construction and it costs
nothing) and the external seat for the three decision points: B9's verdict, §E's verdict, certification.

## A. Fix these four before spending another boot (no GPU, one commit)

1. **The memory-at-rest column was misread, and one rejected-arm verdict rests on it.**
   `atrest-*.txt` is `nvidia-smi --query-compute-apps=pid,used_memory` — **col 1 is a PID**. The
   reports read it as MiB. Re-read from the committed raw files: `u2-blk` 92,333 MiB vs `u3-s8`
   92,324 MiB — the "`seqs=8` strands **+40 GB** (317,638 vs 276,855 MiB)" finding in
   `hd489-u3-s8` + the `services-ai-rejected.md` row is **a PID swap, not a stranding**. Same for
   `u1-patch`'s "175903/92975". Fix: append a correction entry to the rejected log (append-only,
   §8.3 — a new row, not an edit; the arm stays rejected on its *speed*, which is real), correct the
   two reports, and fix the `MEM_AT_REST` awk in `spark/bench/run-scenario.sh` so the CSV stops
   producing the ambiguous `engine/all` string.
2. **The line the docs call authoritative is never printed.** With `--kv-cache-memory-bytes` the
   engine skips profiling: it logs `Initial free memory 114.87 GiB, reserved 14.9 GiB … and skipped
   memory profiling` + `GPU KV cache size: 515,786 tokens`. `grep "Available KV cache memory"` is
   empty, which is why the CSV's `kv_avail_gib` column is `?` in every HD-489 row. The rule in
   `spark-llm-profiles.md` / `hardware-spark.md` ("never quote a projection; the `Available KV cache
   memory` line is authoritative") is unsatisfiable on this config path — restate it as
   `Initial free memory` + `GPU KV cache size`.
3. **`ar-blk`'s `fixed_cost_bytes` can now stop being a vendor number.** Measured at rest: engine-pid
   88,075 MiB − 14.9 GiB KV = **71.1 GiB ≈ 76.4e9 B** vs the declared vendor 76.3e9 — agrees. But the
   `run-scenario.sh` header warns per-pid **under-counts by ~10 GiB**, and the boot log says model
   load took **68.35 GiB**, so two derivations disagree. Pick one, document the derivation, and set
   `fixed_cost_basis: "MEASURED …"` — the host-floor assert is the only thing standing between a dial
   and a global OOM that Docker reports as `OOMKilled: false`.
4. **`ple_mmap: true` drags a 17-item env bundle, so the headline "+68 % is the AR weights" is
   confounded.** `spark_llm_ple_mmap_env` (`group_vars/spark.yml:1163+`) is rendered for **every**
   arm that sets `ple_mmap: true` — i.e. all of tier 2/3 and none of tier 1. Beyond the `VLLM_PLE_MMAP_*`
   knobs it sets `QWEN38NEXT_LOW_LATENCY_GEMM=1`, `QWEN38NEXT_LLG_PDL=0`, `VLLM_MARLIN_USE_ATOMIC_ADD=1`,
   `VLLM_USE_DEEP_GEMM=0`, `VLLM_VERIFY_TOPK_TRITON=1`, `VLLM_KEEP_DRAFT_BLOCKS=1`, `VLLM_FP8_HYBRID=1`,
   `VLLM_DRAFTER_EXPERTS_FP8=1`. Tier-1 (AWQ) arms rendered `env_extra: []` from `_x`. So the funnel
   compared **weights + table path + ~7 kernel-dispatch knobs** against **weights + table path**, and
   `ar-mmap`'s prose ("better per-step kernels compensate for eager") is exactly the sentence those
   knobs would explain. Two legs settle it: **B9** (drop the dispatch knobs on the winner) and **B10**
   (give AWQ the same bundle). Fix in IaC either way: split the list into `…_mmap_env` (table
   plumbing) and `…_dispatch_env` (knobs) so a profile can declare them separately.
   *Correction to an earlier draft of this brief:* `VLLM_PLE_MMAP_FAST_PATH` is **not** inert — the
   `Unknown vLLM environment variable` warning is vLLM core not knowing a plugin's vars; upstream's
   `serve.sh` maps `PLE_FAST_PATH:-1 → VLLM_PLE_MMAP_FAST_PATH` (module default `"0"`) and the boot
   log printed `max_rows=262144` = **our** `VLLM_PLE_MMAP_FAST_MAX_ROWS` (code default 8192). The env
   is honoured; nothing to fix.

## B. The benches, in value order

Every leg: `--profile ar-blk` (or the arm), `--client`, the leg window, the sustained
`clocks.sm/power/temperature` sampler across the whole window (the gate README requires it and **no
HD-489 leg has it**), and `MemAvailable − CmaFree` at both ends. Write the leg report under
`spark/reports/hd489-tail-<name>/` with the raw in `raw/` — the rule `hd469-reasoning` filed twice:
**an evidence dir a row cites must contain the raw output.**

**Cheapest-information-first order (not table order):** B6 (40 s, no GPU) → **B9** (1 boot, decides
whether the quality question even matters) → B1 → B2 + B3 (0 boots, the winner is live) → L0/L1 of §C →
B5 → B10 → B7 → B8 → the §E suites, which run unattended overnight.

| # | Bench | Command / shape | Cost | Retires |
|---|-------|-----------------|------|---------|
| B1 | **`reasoning` control legs** ⚠flip | dial `reasoning` (+`allow_uncertified: false`) → C2, C1, C2L → dial back | **2 boots · ~1.5 h** | the funnel has **no base-image AWQ row at all**: every "+X % vs the certified lane" is currently inferred from `u1-patch`/`u2-blk`, which are the *patched* lineage. This is the only leg that makes the headline honest |
| B2 | **Concurrency on the winner** | `spark-llm-probe.py … ctx 262144` then `concurrent 4`, + `C3` and a C2L at `C2L_CONC=2` | **0 boots · ~30 min** | gate 4 is unproven for every `ar-*` arm; **all funnel numbers are conc 1**, and `enforce_eager` is exactly the regime where per-step launch overhead shows up under batching. Gate 4's pass rule: all 200s and slowest ≤ 3× solo |
| B3 | **Depth at the real workload** | `C1_IN=163840` (p50 prompt = 137,821 tok; p95 200,000 — `hd489-pin-premise`) and an `S1-N` at `S1N_IN≈236000` | **0 boots · ~45 min** | C1 today is 32 k in; the harness pays 140 k-token prefills every turn. Also the pi-harness §3 **needle at ≥90 % depth, 3/3** (gate 5) — pending for the whole box since HD-469, and "agentic/max-context work is gated on it" |
| B4 | **Correctness / smartness §C** | the paired protocol below | **0–1 flip · ~1.5 h** | "the accuracy battery passed 10/10" is not a quality claim: n=10, no baseline diff committed, no confidence interval |
| B5 | **Page-cache cliff of the mmap table** | C2L after `echo 3 > /proc/sys/vm/drop_caches` (owner-only), and C2L while a co-resident container allocates (or `stress-oom.sh`) | **0 boots · ~40 min** | the winner reads a **47.7 GiB FP8 table by `preadv` per step** and keeps ~4 GB resident in page cache. No gate exercises the case where the cache is reclaimed. If ITL collapses, the win is conditional on an idle box and must be stated as such |
| B6 | **fp8 KV on the *built* image** | `scripts/spark-fp8-image-probe.py` leg B against `spark_vllm_ultrafast_image` — it currently reads `spark_vllm_image` only, so add `--image` (10 lines) or run leg B by hand | **no GPU · ~15 min** | fp8 KV = **876,664 slots = 3.34× window** for free. The HD-473 "blocked on image" verdict was taken on the **base** tag (`fc120ece`, last pushed 2026-08-26); the ultrafast lineage is newer than vllm#55557 (merged 2026-09-16) and nobody has re-probed it. If it reads `fp8`, `graded` becomes a dial and every ctx answer below changes |
| B7 | **The 2.00× pool leg** | `kv_cache_memory: "16300000000"` under `ar-blk` → C2L + `concurrent 2` + one watchdog hour | **1 boot · ~1.5–2 h** | 262,144 × 2 × 31,027 B = **16.27e9 B** — the second full window fits **inside the certified `spark_llm_pool_ceiling_bytes` = 17,179,869,184** and inside the host-floor assert (76.3e9 + 16.3e9 ≤ 104.1e9). Today's 16.0e9 sits at 1.97× and cannot run two full windows. Owner decision: a constant change either way |
| B8 | **VM corroboration** | `spark/bench/vm-window.sh --profile` per leg after the spark monitoring converge; `req_ok_delta == N` as the window-exclusivity proof | **converge · ~20 min** | every HD-489 report carries the same "monitoring not converged" caveat, so no leg has an independent witness |
| **B9** | **Weights or knobs? (first boot to spend)** | clone `ar-blk` as `ar-blk-lean`: same checkpoint + mmap table, the `spark_llm_ple_mmap_env` **dispatch knobs removed** (keep `VLLM_PLE_MMAP_*` + `VLLM_DRAFTER_EXPERTS_FP8`) → C2 + C2L | **1 boot · ~30 min** | A4. If 39.7 survives, the win is the checkpoint and the quality risk is real; if it falls to ~25, the win is env and **B10 becomes a fallback we can certify without touching quality**. Highest information-per-boot in this brief |
| **B10** | **AWQ on the winner's machinery** (`awq-mmap`) | `model_subdir: Qwen3.8-Flash-Next-AWQ` + `image: ultrafast` + `ple_mmap: true` (FP8 table) + block rejection → C2 + C2L. **Pre-flight already done offline:** `ple-table-fp8` **does** carry `…ple.ple_embedding.ngram_embedding.shard_0…130.weight` (33 shards, +1024 fp8 expert `weight_scale_inv`) — unlike `ples_nvfp4`, which is why `nv-patch` died; `ples_int4` is a different layout (`weight_i4` + `weight_scale`) the mmap loader cannot read; the AR checkpoint ships only `ngram_heads_offsets` / `ngram_heads_vocab_sizes`. So the FP8 table is the trained n-gram tensor, not AR-specific — but its loader pairs with `VLLM_FP8_HYBRID`: plausible-and-unverified, not obviously nonsense | **1 boot · ~1 h** (2–4 h if the pairing fails and needs a re-staged table) | the owner's question. Today's AWQ ceiling is `u2-blk` 23.6 **with graphs**; eager AWQ + the bundle is unmeasured. Expected 22–28 tok/s → the quality fallback would cost ~30 % speed, not ~40 % |

> ⚠ **A gate gap B10 exposes:** `roles/spark-llm-profile` asserts `ple_mmap XOR ple_overlay`, the table
> subdir, `¬ple_offload` and `ple_container_dir == '/ple-table'` — but **nothing ties a checkpoint to a
> PLE table**, and `models_root` is per-profile, so AWQ-on-`xfs` with a table on `os` renders happily and
> mis-pairs (or dies) at boot. If B10 is attempted, add that assert, same shape as the existing one.

### B-cost: where the hours go

**Basis (so the estimates are checkable, not vibes):** a boot is **15–20 min** (weights load 549 s, engine
reaches `GPU KV cache size` at +10.2 min, healthy after warm-up; always launched detached); legs from the
funnel's own CSV rows — **C2 2–4 min, C1 4–11 min, C2L 5.5–10 min**; prefill ≈ **1,900 tok/s**
(32 k in / TTFT p50 17.1 s), which is why a 262 k `ctx` leg is ~2.3 min and `C1_IN=163840` × 8 is ~11 min.

| tier | items | box time |
|---|---|---|
| no boot, winner live | B6 15 m + B2 30 m + B3 45 m + B5 40 m + L0 15 m | **~2.5 h** |
| boot tier | B9 30 m + B1 90 m + B4 90 m (1 flip) + B7 105 m + B10 60 m | **~5 h** |
| **decisive subset** | B6 → B9 → B2 → B3 → B1 → B4 | **~7 h = one working day** |
| with the §E suites | + MMLU-Pro-mini ×2 arms (~6–8 h unattended) + Verified 500 ×2 arms (~6 h gen + 2–4 h grading, +1–2 h first-time image pulls) | **~24–30 h over a weekend** |

**Owner-gated (an agent may not self-authorise):** every dial flip incl. B1/B4's second arm and B9/B10
(`spark_llm_allow_uncertified`) · B5's `drop_caches` · B7's pool-constant change · B8's monitoring
converge · B10's checkpoint↔table pairing. Everything else runs from the runner under Rule 0.

**If only three get run:** **B6** (15 min, may hand back 3.34× ctx for free), **B9** (30 min, decides
whether the quality question applies at all), **§E MMLU-Pro-mini** (one night, the first comparison on
this box that can resolve a quantisation delta).

## C. How to measure "correctness / smartness" of `reasoning` vs `ar-blk` reliably

Two quantisations of one architecture, same engine lineage → **paired designs are valid and
unpaired ones are not**. Rules, each bought with a number already in this repo:

- **L0 — self-consistency floor (first, 30 prompts × 2 at `temperature 0`).** If the same build is not
  token-identical to itself, that flake rate is the floor of every comparison. Do it under the winner's
  real `spec{mtp,3,block}` + `enforce_eager`, at conc 1 **and** conc 2.
- **L1 — noise floor, then delta (gate 9).** `prompt_logprobs=1, temperature 0` per position:
  `new − old` must be inside `old − old` from the same build. A needle run is **not** evidence here
  (one 32 k run measured 14 % vs 25 % miss, p = 0.67), and keep the long-reasoning battery: the
  reference fp8 implementation went **6/6 → 2/6 on long reasoning while needles still passed**.
- **L2 — verifiable-answer sets, scored by a machine, never by reading.** Exact-match math (GSM8K-style,
  boxed answer), the 15-prompt local-knowledge battery over **this repo** as corpus
  (`spark/resources/R2-nvfp4.md` §B), JSON-schema-strict extraction, tool-call items with a real
  `tools` schema (every HD-489 tool-call item was `EMPTY` because the probe sends no schema), a
  Slovenian set scored exact-match + a 2-rubric annotator, short code tasks with a `pytest` oracle —
  and the two public suites in **§E**, which is where the statistical power actually comes from.
- **L3 — end-to-end: the pi-harness task list** on both profiles. That score is the certified lane's
  anchor; a profile that wins tok/s and loses tasks is not a win.
- **Statistics.** Paired binary items → **McNemar exact test**, report `n`, both discordant cells and a
  95 % CI. Minimum `n` for 80 % power at α = 0.05 two-sided, at a ~10 % discordance rate:
  **5 pts → 314 · 3 pts → 873 · 2 pts → 1,963**. The current 10-prompt battery resolves nothing below
  ~20 points, and the 100-task SWE capture in `R2-nvfp4` resolves ~10. Pre-register the pass rule before
  running: `Δ ≤ 2 pts → keep`, `3–5 pts → decide on L3`, `> 5 pts → the speed win is void`.
- **Confound ledger, printed in every row of every table:** image digest · checkpoint + revision ·
  `tool_call_parser` (ours is `qwen3_coder`, not upstream's `qwen3_xml`) · `enable_thinking` **and**
  `thinking_token_budget` (top-level `reasoning_effort` is accepted-and-**ignored** on this build —
  `probe … effort high` re-measures it) · `override_generation_config` · seed · `--client` ·
  sustained `clocks.sm`. The 91 ↔ 98 ↔ 99 spread in our own captures came from these, not from quant.
- **Anti-Goodhart:** keep a held-out slice nobody tunes on, plus canary items with known-impossible
  answers. What we already know about the winner: `enforce_eager` and block rejection do not change the
  output distribution, so **the entire quality delta is the AutoRound int4/int8/fp8-hybrid checkpoint** —
  and our only prior on that axis (`R2-nvfp4` claims 9–12) is that AWQ keeps attention bf16 and the quant
  that does not scored 91 vs 98, with the honest caveat that another capture scored 99/100 on SGLang.

## E. Two public suites to adopt (they are what gives the comparison power)

Both are **machine-scored and paired**, which is the whole point: they turn "10/10 outputs looked
fine" into a McNemar test. Add them as a third axis next to the timed legs — same CSV discipline, same
identity columns (`--profile`, `--client`, window), raw predictions under
`spark/reports/hd489-eval-<suite>-<arm>/`.

| suite | what it is | n | license | wall-clock on `ar-blk` (39.7 tok/s, decode-bound) | resolves |
|---|---|---|---|---|---|
| **MMLU-Pro mini** | 14-domain reasoning MCQ, 10 options; **CoT is mandatory** (direct drops up to 19 %) — 100/domain, fixed seed | 1,400 | dataset MIT, code Apache-2.0 (`TIGER-AI-Lab/MMLU-Pro`) | ~8 h conc 1, ~2–3 h conc 3 **per arm** → ~6–8 h for `ar-blk` + `reasoning` | ~3 pts |
| MMLU-Pro full | same, every item | 12,032 | 〃 | ~67 h conc 1, ~17 h conc 4 | ~2 pts |
| **SWE-bench Verified** | 500 real merged-PR issues, graded by the repo's own tests | 500 | code Apache-2.0; task data per-repo | ~5 h conc 1 single-shot (~3 h conc 2) **per arm** + 2–4 h grading (+1–2 h first-time image pulls) · ~18 h agentic | ~4 pts |

**How they plug in** — MMLU-Pro already ships an OpenAI-compatible multithreaded runner, so it talks to
our endpoint directly:

```bash
python evaluate_from_apiX.py --url http://spark.kogler.si:8000/v1 -m spark/qwen3.8-flash-next \
       -n 3 -o eval_results/ --retry 2 --retry_wrong 2          # -n is the ONLY concurrency knob
python compute_accuracy.py -p eval_results/generative/ai2OKIQASolver_results.json
```

SWE-bench v5 splits generation from grading, which is exactly the split we want (generate against
spark, grade in Docker elsewhere):

```bash
swebench infer verified -m <openai-endpoint-model> -o preds -w 2      # or single-shot patch preds
swebench eval verified -p preds --run-id <profile>-<date> -j 4        # containers live HERE, not on spark
```

Rules that keep the number honest (each one is a way this lane has already been fooled):

1. **Pin the revision.** Harness + dataset commit and a sha256 go in `group_vars/all/versions.yml`
   (§7), fetched explicitly, never at deploy time. For MMLU-Pro use a **post-2026-01-18** revision —
   the leading-space-in-options fix; a whitespace shortcut is exactly what would move a re-quantised
   model and read as a quality delta.
2. **Run the harness OFF spark.** SWE-bench instances execute untrusted repo code; and on aarch64 the
   prebuilt task images need `--task-repo` + Buildx rebuilds anyway. Laptop or nas → spark's endpoint
   also satisfies Rule 0 by construction, and keeps `spark` free of the eval's own token traffic.
3. **Report the extraction-failure rate beside the score.** A quantisation that changes answer format
   (regex `Answer: \\((.)\\)`) shows up as accuracy loss unless `--rerun-unknown` / a lenient matcher
   separates "didn't answer" from "answered wrong".
4. **CoT state is a confound, not a setting.** Same prompt template, same shots, same
   `enable_thinking` + `thinking_token_budget`, `temperature 0`, same `tool_call_parser`, in every row
   of the ledger — the 91 ↔ 98 ↔ 99 spread in our own captures came from these.
5. **Comparisons, never absolutes.** Public items live in pretraining corpora and the MMLU-Pro paper
   itself notes unanswerable/mis-annotated items cap the ceiling; a 74 vs 72 means nothing without the
   paired discordant cells. Keep the repo-local-knowledge and Slovenian axes: they are the only ones
   that measure *our* workload, and neither suite contains a token of Slovenian.
6. The agentic SWE-bench variant is double-duty: it is the first real exercise of tool calling on this
   engine (parser `qwen3_coder`, `--enable-auto-tool-choice` on, and every HD-489 arm's tool-call item
   was `EMPTY`). Prefer it **after** the single-shot pass, so a tool-calling bug cannot masquerade as a
   model-quality result.

## D. Evidence close-out (repo, not box)

`spark/bench/results-v2.csv` and the per-arm `spark/bench/accuracy/hd489-*` outputs are **only on
spark** (`/home/ansible-admin/bench/`); only `B1` is committed. Either commit them (scrubbed — the CSV
scrubs the bearer at the point of write) or stop citing CSV rows in reports. Thin dirs:
`hd489-nv-patch`, `hd489-pin-premise`, `hd489-tier3-drafter` have `raw=0`; `hd489-v16b-pin` has 2.
Stale text to fix in the same commit family: `docs/spark-llm-profiles.md` §7 still says the two
deliberate gates are open (image pin recorded `versions.yml:311`; the `never_evict_prompt` half is
now a rejection — `docs/services-ai-rejected.md`); the HD-489 `todo.md` row is fully stale and cites **`hardware-spark.md`
§LLM serving profiles, which does not exist** (third occurrence of the dangling-reference class this
lane already filed twice); and `prompt.md:44` still says "⛔ no timed-throughput tool in `scripts/`",
which Correction 2 already refuted.

## Do-not-do

Do not raise `spark_llm_pool_ceiling_bytes` or `fixed_cost_bytes` as a side effect of a leg — each is a
certified constant with its own evidence. Do not attempt fp8 KV by editing a container; the probe first,
then a dial. Do not vendor the AGPL overlay patch, do not hand-edit site-packages, do not add a
`never_evict` pin anywhere — the mechanism is REJECTED (`docs/services-ai-rejected.md`).
Do not re-run arms already in the rejected log without an exception note (§8.3). Do not delete `ar-blk`'s
artifacts (`ar-hybrid`, `ple-fp8`) — 120 G on `/`, gate floor 150 G, and it is the live config. Do not
delete the AWQ + `ples_int4` artifacts: `reasoning` is the rollback target. Do **not** run SWE-bench
task containers on spark (untrusted repo code on the serving box, and aarch64 images need local rebuilds
anyway) — grade on the runner. Do not report a public-suite score without its revision pin, CoT state
and extraction-failure rate attached. Do not take a timed leg from a **laptop-local** runner when the
engine under test is the laptop leg itself (Rule 0, same rule, other seat), and do not let a
laptop-local session author a profile delta at all — its 32 k window cannot hold the contract (see
§Runner seat).

## Definition of done for this brief

B1–B3 + B6 + **B9** done with reports and raw in-tree · **B10** attempted or explicitly declined (with
the reason in the row) · B4's L0/L1 + **§E MMLU-Pro-mini on both arms** run with the pre-registered pass
rule and a verdict in `spark-llm-profiles.md` · A1–A4 fixed · D landed · then `ar-blk` gets
`certified: true` + `certified_evidence:` (links to artifacts, not prose) with `uncertified_reason`
dropped, one converge without the override, and the `todo.md` row deleted. **Acceptance:** each item
returns `PASS / FAIL / BLOCKED` + the number + the evidence path; a claim with no path counts as not run.

## What more ctx is actually available (the arithmetic, so nobody re-derives it)

| option | slots | × window | state |
|---|---|---|---|
| today: 16.0e9 @ bf16 `auto` | 515,680 (engine prints 515,786) | **1.97×** | live |
| 16.27e9 @ bf16 (two full windows) | 524,288 | 2.00× | **fits under the certified 17.18e9 ceiling** and under the host-floor assert — B7, needs an owner decision + gate 4 |
| 17.18e9 (the ceiling itself) | 553,707 | 2.11× | +7 % only; still no third window |
| 16.0e9 @ fp8 KV | 876,664 | **3.34×** | blocked on the image — **re-probe first (B6)**, HD-473's verdict is about the old tag |
| host-floor max pool at `fixed_cost` 76.3e9 | 896,413 | 3.42× | arithmetic only; `spark_llm_pool_ceiling_bytes` binds first, and the certified constant is 16 GiB |
| > 262,144 tokens | — | — | native `max_position_embeddings` = 262,144; the YaRN + `VLLM_ALLOW_LONG_MAX_MODEL_LEN` route is already rejected as ungated (needle first) |

Physical room is real and ar-blk is what reveals it: the boot log says **114.87 GiB free at engine
start, 68.35 GiB taken by weights, 14.9 GiB reserved for KV → ~31.6 GiB of pool unallocated**, and the
winner's legs never sampled usable below **22.6 GiB** (`u2-blk`: 20.3 / 22.8 / 24.3) against the
17.78 GiB certified worst the whole host-floor constant is built from — headroom exists, it is just
not currently allocated to anything. What keeps ctx at 1.97× is not memory, it is the two
certified constants and the missing gate-4/gate-7 evidence.
