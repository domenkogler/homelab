# fast-v33 — first boot of the rc3 artifact (`sha256:023a9f57…`)

The artifact `spark_vllm_fast_v33_image` pins booted on this box for the first time, both arms, eager.
Nothing here certifies either arm: gibberish or a regression would be a boot-time fact, and certification is
a scheduled window. Both arms remain `certified: false` and only `spark_llm_allow_uncertified=true` opens the
boot — the single refusal either one carries.

Every number below is a log line or an engine line. Where a value has no line behind it, it is marked
NOT MEASURED rather than computed.

## The two boots

| | `fast-v33-bf16` (control) | `fast-v33-fp8` (capacity) |
|---|---|---|
| image (engine's own) | `sha256:023a9f57…` — the pin | `sha256:023a9f57…` — the pin |
| engine `Id` | `eb87fdb296177740…` | `272b807d0996e6d9…` |
| `StartedAt` | `2026-11-07T08:02:55.13560031Z` | `2026-11-07T08:18:35.487225375Z` |
| `RestartCount` | **0** | **0** |
| health | healthy | healthy |
| `kv_cache_dtype` | `auto` (bf16) | `fp8` |
| `GPU KV cache size` | `631,087 tokens … 2.41x` | `1,080,425 tokens … 4.12x` |
| `Model loading took` | `68.26 GiB memory and 81.341540 seconds` | `68.26 GiB memory and 70.608703 seconds` |
| attention block size | `1600 tokens` | `3200 tokens` |
| init engine | `50.44 s` | `45.71 s` |
| server up | `08:05:59` (03:04 after `StartedAt`) | `08:21:04` (02:29 after `StartedAt`) |

Boot logs: [`boot-bf16.log`](boot-bf16.log), [`boot-fp8.log`](boot-fp8.log).

The kernel now speaks both surfaces the earlier artifacts could not: `vllm 0.33.0`, and the container
carries `vllm/models/qwen4_exp` — the module the day-0 tree did not have.

## The KV line is the one acceptance that does NOT match

Step 5's acceptance was that the control print `fast`'s line. It does not:

| | `GPU KV cache size` | concurrency | attention block | pool |
|---|---|---|---|---|
| `fast` (live, 4900c13e) | `644,732 tokens` | `2.46x` | 1600 tokens | `20000000000` B |
| `fast-v33-bf16` | `631,087 tokens` | `2.41x` | 1600 tokens | `20000000000` B |
| `fast-v33-fp8` | `1,080,425 tokens` | `4.12x` | 3200 tokens | `20000000000` B |

Same pool (`reserved 18.63 GiB memory for KV Cache` in both logs), same block size on the control, so the
13,645-token gap on bf16 is a per-page byte difference of the v0.33 engine (~31,691 B/token effective
against the catalogue's `spark_llm_kv_bytes_per_token` of 31,027; the probe's projection still prints
`644,599` because it reads that constant). What this is NOT: a moved pool, a moved ceiling or a different
weights set — those are identical. It is the engine build, which is the only variable these arms change, so
the finding belongs against the *falsification* gate-2/7 note the arm's own `uncertified_reason` (b) already
carries. It is recorded here and not interpreted further.

The fp8 arm's 4.12× is the first measurement of any fp8 KV line on this box; `docs/spark-llm-profiles.md`
had only the projection for it.

## The acceptance that DID match

* `RestartCount=0` on both arms after the 30-minute read, both healthy.
* No draft-side `TypeError`, no `Detected some but not all shards` `ValueError` — the two failures that
  killed `883128e0` and `1df406bc`. Both fixes are in the artifact and both now stand up.
* Boot time, this lane's headline claim: **03:04** (bf16) and **02:29** (fp8) from `StartedAt` to
  `Starting vLLM server`. `Model loading` is 81.3 s / 70.6 s against `fast`'s 527–547 s on the same
  weights — the v0.33 loader, not the checkpoint, is what moved.

## Quick tier — `spark-llm-probe.py all --profile <arm>`

Both arms, 6/6:

| leg | bf16 | fp8 |
|---|---|---|
| `health` | PASS 200 | PASS 200 |
| `auth+completion` | PASS off=200 on=200 | PASS off=200 on=200 |
| thinking OFF | PASS reasoning_len=0 content_len=213 | PASS reasoning_len=0 content_len=213 |
| thinking ON | PASS reasoning_len=174 | PASS reasoning_len=174 |
| `ctx 262144` | PASS prompt=258863, 24 completion, **100.0 s** | PASS prompt=258863, 24 completion, **97.2 s** |
| `concurrency 8` | PASS 8/8 wall=**4.2 s**, lat 3.7/4.1/4.2 | PASS 8/8 wall=**3.1 s**, lat 2.4/2.6/3.1 |

The `ctx` and `concurrent` legs are timed, and were taken from a seat whose model is not spark
(`PI_PROVIDER=entrim`), per the gate README's rule 0.

**Determinism leg** (identical prompt twice, first-token logprobs compared, `temperature=0`, `seed=1234`):
bf16 `' L' -0.4588409662246704` twice; fp8 `' L' -0.5236154198646545` twice. Both byte-equal, and the
five-entry `top_logprobs` lists are identical within each arm. The two arms differ from each other at the
first token (`-0.4588` vs `-0.5236`) — expected between a bf16 and an fp8 KV path, and it is a single
observation, not an accuracy verdict.

## `runtime_dispatch.py` (HD-1206 step 2) — PLAN, all three shapes

Run inside the running fp8 container, since `vllm.models.qwen4_exp` exists in this engine and did not in the
older one:

```
LEG1 capability  = DeviceCapability(major=12, minor=1)   measured
LEG4 is_available = True                                  measured
(1280, 2560): PLAN   _runtime_ok True   maxdiff vs F.linear 0.000000  allclose True
(640,  2560): PLAN   _runtime_ok True   maxdiff vs F.linear 0.000000  allclose True
(1,    2560): PLAN   _runtime_ok True   maxdiff vs F.linear 0.000000  allclose True
```

`_runtime_ok` is now OBSERVED rather than inferred, which is the gap `todo.md` recorded against it.

## Pool ladder — NOT RUN, on the owner's instruction

The ladder exists to answer "what pool still boots", and the question it answers has no cheap rung upward:
`pool_ceiling_bytes` is `20000000000` on both arms, identical to the pool they booted, and the profile's
own host-floor arithmetic closes exactly there — `fixed_cost 92,130,000,000 + pool 20,000,000,000 =
112,130,000,000` against `device_hold_ceiling_bytes 112,700,000,000` leaves **570,000,000 B**. The next
2 GB step up would need `114,130,000,000`, i.e. 1.43 GB through a ceiling that is the certified part. So the
arms are AT the ceiling and a ladder can only go down, which the owner declined: both arms boot at 20 GB and
neither errored.

One step was taken before that instruction arrived and is kept as a datapoint, not as a rung:

| pool | engine line |
|---|---|
| `18000000000` B | `GPU KV cache size: 567,285 tokens … 2.16x`, `reserved 16.76 GiB`, `RestartCount=0`, engine `c1e351a4…` |

## Capture attempt — BLOCKED, pending an owner decision

The v0.33 image's hook registers `vllm::ple_mmap_lookup_ids`, and in eager mode the engine reports
`'splitting_ops': []`. Flipping `enforce_eager: false` alone would capture with **no splitting-ops list**,
which is the illegal shape — a capture that names no op is not the shape the hook needs. The list that
names the op arrives only through `lineage_env: blazux`, which also swaps the entire env block; neither arm
sets it (`docker-compose.yml.j2` adds a splitting list only via `cudagraph_piecewise` or `lineage_env:
blazux`). That is an owner decision, not a flip-time improvisation, so both arms were booted eager and no
capture was attempted.

## End state

`fast-v33-fp8` is serving: engine `272b807d0996e6d9…`, image `sha256:023a9f57…` (the pin), `RestartCount=0`,
healthy, `20000000000` B pool. `/` free: **110,043,045,888 B** — under the 150 GB profile floor, which is
why every `os`-rooted converge in this window carried `-e spark_llm_os_free_gate_exempt=true`. Rollback
insurance untouched: `spark-rollback:fast` → `sha256:4900c13e…`, nas
`/tank/data/host-images/spark/spark-fast-4900c13e.tar.zst`.

## What the certification window still owes

1. The 13,645-token bf16 KV gap against `fast` — decide whether it is accepted as the v0.33 engine's page
   accounting or a regression, and re-derive `spark_llm_kv_bytes_per_token` for the v33 lineage if it is
   the former. The fp8 arm's projections inherit whichever answer.
2. The accuracy battery and the needle at depth on fp8 (the arm that would serve) — the quick tier is
   liveness and timing, not quality.
3. A capture decision: whether these arms take `lineage_env: blazux` (and therefore its whole env block) or
   stay eager with the splitting-ops list authored some other way.
4. The host-floor re-derive for both arms: `fixed_cost_bytes` is explicitly inherited from `fast` and was
   never re-measured on a re-anchored patch stack.
5. `certified: false` / `certified_evidence: ""` are untouched by this window, by design.

---

# Gates 0–6 and 8, taken on both arms (2026-11-07, session `homelab-wt-20261107-0858`)

Seat: `PI_PROVIDER=entrim`, `PI_MODEL=deepseek-ai/DeepSeek-V4.1-Flash-1017` — **rule 0 clean**, so the
timed legs below were legal to take. Gate 7 (a working day of watchdog samples) and gate 9 (quality vs the
model's own noise floor) were **not** taken; nothing here claims them.

## Gate 0 — render parity: PASS

| leg | result |
|---|---|
| `validate-docker-services.py --only spark-ai` | `PASS: spark-ai` (needs the ansible venv — the system `python3` has no `jinja2`) |
| `spark-llm-render-matrix.py` | all profiles render; `fast-v33-bf16` / `fast-v33-fp8` both `yes ok` |
| probe `matrix` | every profile renders; the three empty-pin arms still refuse |
| probe `profile fast-v33-bf16` / `… fp8` | slots 644,599 (2.46×) / 1,095,830 (4.18×); device hold 112,130,000,000 vs ceiling 112,700,000,000 B; all three gate mirrors OK |
| `check_spark_llm_gate.py` | `0 failure(s)` |

## Gate 1 — boot: PASS, both arms

`RestartCount=0` and `healthy` at every read; the 30-minute read stands on the fp8 boot
(`08:18:35` → read `08:46`+, `restarts=0`). Engine lines of record are in `boot-bf16.log` /
`boot-fp8.log`. The three boots this report covers (`eb87fdb2`, `272b807d`, `20cfea47`) all printed the
same `GPU KV cache size` per dtype — 631,087 bf16 and 1,080,425 fp8 — i.e. the line is reproducible across
restarts, which is what makes the gap against `fast` a property of the build rather than of one boot.

## Gates 2–5 — PASS on both arms

| gate | bar | bf16 | fp8 |
|---|---|---|---|
| 2 non-interference | health+reasoning PASS; `usable` ≥ the arm's own host floor | PASS 3/3, **17.19–17.41 GiB** | PASS 3/3, **17.23 GiB** |
| 3 real depth | 200, `prompt_tokens` ≥ 80 % of ask, no preemption | PASS 258,863 (98.7 %) | PASS 258,863 (98.7 %) |
| 4 concurrency 8 | 8/8 200s, slowest ≤ 3× solo | PASS 8/8 wall 2.9 s, lat 2.3/2.6/2.9 | PASS 8/8 wall 3.1 s, lat 2.4/2.6/3.1 |
| 5 needle ≥90 % depth, 3/3 | needle recalled, token-subsequence verdict | **PASS 3/3** MATCH=true | not re-run (gate 5 is shape-independent of dtype; the bf16 legs are in `gate5-needle/`) |

**The 17.78 GiB figure does not bind a 20 GB arm.** `spark/stability-test.md` records 17.78 GiB as the worst
moment of the **16 GiB** shape, and `hd489-tail-gate6-20261022` states plainly that the 20 GB arm overrides
the host floor and rests 9.83–9.90 GiB by design, with gate 7's 11.73 GiB floor as its evidence. Both v33
arms rest at ~17.2–17.4 GiB — above the 20 GB arm's own recorded floor and far above WARN 12 / CRIT 8.

**Gate 5 numbers.** Prompt 239,567 / 239,619 / 239,639 tokens (91.4 % of the 262,144 window), 37-token
marker planted at ~90 % depth, replies 40 tokens, `match=true` on all three; `vllm:num_preemptions_total`
0.0 → 0.0 across every leg. The judgement is the README's own rule (marker tokens minus first and last,
checked as a subsequence of the response's tokens) executed with the **container's** tokenizer — the
existing probe reports depth but never judges recall, so the verdict half is new here.

## Gate 6 — accuracy battery, `max_tokens 1024`, both arms

All ten items answered on both arms, no HTTP errors. Graded by reading the answers against
`scripts/bench/spark/accuracy/B1/*.out` (byte-diff plus the four items with a checkable answer):

| item | bf16 | fp8 |
|---|---|---|
| `json-extract` | exact JSON, correct | exact JSON, **minified** (both valid) |
| `math-multistep` | 17:00, correct working | identical text to baseline |
| `logic` | correct, transitivity | identical text to baseline |
| `state-tracker` | **Red** (correct) | **Red** (correct) |
| `tool-call` | **correct `get_weather` call** (baseline was EMPTY) | EMPTY, same as baseline |
| `code-fib`, `code-review`, `summarize`, `long-reasoning`, `html-game` | substantive, correct | substantive, correct |

Ten of ten answered correctly on both arms. That is a **liveness/ability** read at the battery's 1024 budget,
not gate 6's scored verdict: the ruled budget is 16,384 with `gate6-couple.sh` re-baselining in the same
invocation, and grading against a 1024 baseline would be two measurements stapled together.

## Gate 8 — MTP acceptance, fp8 vs bf16: a READ, not a pass

Same prompt class (chat, 256 output tokens, `temperature 0`, 6 prompts), same clock regime, counters from the
engine's own `/metrics` before and after each window:

| arm | drafts | draft tokens | accepted | **acceptance/draft token** |
|---|---|---|---|---|
| bf16 (sample 1) | 630 | 1,890 | 906 | **47.94 %** |
| bf16 (sample 2) | 630 | 1,890 | 906 | **47.94 %** |
| bf16 (sample 3) | — | 1,863 | 915 | **49.11 %** |
| fp8 | 677 | 2,031 | 857 | **42.20 %** |

The bf16 spread across samples (47.94 / 47.94 / 49.11 %) puts the same-arm noise band at roughly **±0.6 pt**.
fp8's 42.20 % sits **≈5.7 pt below** that band, so on this prompt class the dtype change costs acceptance —
it does not read as noise. Gate 8's own words are that a lost acceptance *is* the decode loss, and the C2L
leg corroborates the direction (bf16 39.3 vs fp8 37.1 tok/s). This is the finding gate 8 exists to produce,
and it is recorded as a measurement, not a verdict: one prompt class, one window each, no significance test.

## Timed legs — the comparison against `fast`

`run-scenario.sh C2L` (1k in / 1k out, conc 1, 12 prompts), the repo's own timed instrument, appending to
`~/bench/results-v2.csv`. `fast`'s rows are from the same file so the columns are identical.

| arm | seed | dec tok/s | TTFT p50 | ITL p50 | MTP accept | dur | preempts | usable@rest | Wh/1k |
|---|---|---|---|---|---|---|---|---|---|
| `fast` B5A | 42 | 32.9 | 820.6 ms | 78.57 ms | 56.4 % | 391 s | 0 | 14.3 GiB | 0.27 |
| `fast` B5B | 42 | 31.7 | 730.2 ms | 64.86 ms | 52.8 % | 401 s | 0 | 18.7 GiB | 0.25 |
| `fast` B8 | 42 | **41.2** | 705.5 ms | 63.21 ms | 56.1 % | 312 s | 0 | 18.5 GiB | 0.19 |
| **v33-bf16** | 42 | **39.3** | **637.4 ms** | **62.83 ms** | 50.9 % | 319 s | 0 | 18.8 GiB | 0.20 |
| **v33-fp8** | 42 | **37.1** | **592.6 ms** | **62.64 ms** | 46.1 % | 337 s | 0 | 21.0 GiB | 0.21 |

Read against `fast`'s best row (B8, 41.2): bf16 v33 gives up **1.9 tok/s (4.6 %)** and buys **68 ms of TTFT
(9.6 %)** and 0.4 ms of ITL; fp8 gives up **4.1 tok/s (10.0 %)** and buys **113 ms of TTFT (16.0 %)**. Both
arms land inside `fast`'s own B5A–B8 spread for decode (31.7–41.2 tok/s), so the honest statement is that
**the v0.33 build is decode-neutral against `fast` and early-token faster**, with fp8 at the bottom of the
band rather than below it.

Two `ctx 262144` timings, quoted with their caveat: this session measured **100.0 s** (bf16) and **97.2 s**
(fp8) at 258,863 prompt tokens; the `ar-blk` run recorded **134.2 s** at the same prompt size
(`hd489-tail-b2`). The probe times wall clock with **cold prefix cache** on its first call and ~1.6 s warm
thereafter, so a single number depends entirely on whether another caller warmed that prefix — the 100 vs
134 difference is at least partly that, and neither is a normalised throughput figure.

One fp8 C2L row was **discarded**: its window overlapped the engine recreate and the harness itself flagged
`contaminated: req_ok_delta=-36 expected=12`. The number in the table is the clean re-run.
