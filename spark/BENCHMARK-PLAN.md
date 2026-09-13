# Spark Benchmark Plan — engine-neutral (vLLM + SGLang candidates)

> **Role:** Baseline → tuning benchmark plan for Qwen3.8-Flash-Next on spark/GB10, **engine-neutral**.
> No engine is pre-assigned a default: vLLM and SGLang are both bench candidates, decided by data at
> bench time (owner re-decide 2026-09-14). A benchmark goal — per engine × per config × per context
> state — is measured and the winning engine/config per serving profile gets promoted into the SSOT
> (`group_vars` / compose files) after verification.
> **Linked from:** `spark/README.md`, `spark/spark.md`, `docs/hardware-spark.md`, `todo.md`
> **Supersedes:** the pre-research handoff `summary.md` (deleted 2026-09-14; research artifacts +
> this plan now OWN the bench direction).

---

## 1. Baselines

| ID | Config | Compose file | Status |
|----|--------|--------------|--------|
| **B0 (legacy)** | fp8 KV, swap 32, no auto-tool-choice, disable_by_batch_size 6 | `spark-compose.yaml` | kept only to quantify B0/B1 deviation |
| **B1 (proven)** | bf16 KV, swap 4, auto-tool-choice, plain MTP-3 | `spark-compose.proven.yaml` | **control reference** — the AWQ+PLE x86-proven recipe |

**Engine-axis driver (owner re-decide 2026-09-14):** engine precedence is deliberately **unset**.
Research (2026-09-13 spike, `spark/resources/RESEARCH-VERDICTS.md`) showed: the 98/100 AWQ+PLE
recipe is vLLM-only (PLE n-gram overlay), while stock vLLM on GB10 cannot serve NVFP4 (falls back to
a Marlin path, upstream #50925) — SGLang is the native-GB10 NVFP4 route (hashd1ve recipe, 262k
context) — and long-context concurrency (S5) is a SGLang pool-semantics strength. Which engine wins
**your** workflows is measured here, apples-to-apples.

B1 is the strict return to proven recipes (WonderRico 98/100 + UltrMgns 170K + primitive-ai overlay
card). B0 is kept only to quantify what the fp8/swap32 deviations were doing.

---

## 2. Serving profiles to certify (S1–S5) + recommended engine per profile

Profiles map the five serving scenarios to bench cells. Engines are **candidates to sweep** — the
first bench column that satisfies the profile's gate gets certified and promoted to the SSOT.
Reference expectations (from the 2026-09-13 research, `RESEARCH-VERDICTS.md` §2/§3) are community
reports only — **not measured on this box** — used to size the sweep, never as verdicts.

| Profile | Scenario | Weights | KV | Context | Engines to bench | Reference expectation (research; verify) |
|---|---|---|---|---|---|---|
| `serving_reasoning` (S1) | best reasoning, 1 session | **AWQ W4A16 + PLE INT4** (98/100 recipe) — bf16 dropped (R1: 250 GB won't fit) | bf16 | 173,400 (B1) | **vLLM** (pinned image + PLE overlay) · SGLang (if PLE lands on GB10) | vLLM accuracy anchor (~87% MTP acceptance); PLE is vLLM-only today |
| `serving_fast_single` (S2) | fastest single session | NVFP4 (nvidia/) + FP8 PLE on NVMe | fp8 | ≤262k native | **SGLang** (hashd1ve) · vLLM (patched nightly if NVFP4 serving works) | GB10 single-stream ≈ 40–46 tok/s code (SGLang) |
| `serving_concurrent_3_5` (S3) | 3–5 concurrent sessions | NVFP4 | fp8 | ≤262k | **vLLM** (madeye TP1: 6 slots) · SGLang | 100 tok/s aggregate @4 measured (vLLM madeye) |
| `serving_longctx_512k` (S4) | max context, 1 session | NVFP4 (or AWQ if accuracy-gated) | fp8 | 524,288 via YaRN factor 2.0 | **SGLang** (official YaRN + `serve-500k.sh`) · vLLM | madeye 500k demo; needle-gate mandatory |
| `serving_longctx_conc3_5` (S5) | max ctx × 3–5 sessions | NVFP4 | fp8 | per-request ≤262k native; pool ≥3×(L/2) | **SGLang** (pool semantics) · vLLM per-request max_model_len | in-scope for bench (2026-09-14); SGLang pool fits S5 |
| `bench_awq_ple` (control) | = B1 verbatim | AWQ+PLE | bf16 | 173,400 | vLLM pinned image | unchanged control |

Cross-profile requirements (all): PLE tables on the XFS NVMe mount (unified memory makes RAM-offload
pointless); needle-test at operating depth per profile (XQA corruption trap #36845); `--max-num-seqs`
set explicitly (default 1024 aborts CUDA-graph capture); ptrace/seccomp check under DGX OS.

---

## 3. Benchmark harness

Run benchmarks **direct against each engine** (`:8000` engine / `:8080` router) so both engines and
their router pass are measured for e2e overhead. The vLLM image ships `vllm.benchmarks.serve`;
SGLang ships its own benchmark CLI (`python3 -m sglang.bench_serving`). Harness scripts are
engine-parameterised (below); today they assume the vLLM container name — SGLang runs reuse the same
scripts with a different container/URL baseline.

```bash
# PREFILL-heavy: 32k in / 512 out, single stream (cache-free)
docker exec vllm-qwen-spark python3 -m vllm.benchmarks.serve \
  --backend openai-chat --model /model \
  --host http://localhost:8000 \
  --dataset-name random --random-input-len 32768 --random-output-len 512 \
  --num-prompts 8 --max-concurrency 1 --seed 42 \
  --save-result --result-dir /mnt/spark_nvme/bench/C1-prefill-32k.json

# DECODE: 1k in / 512 out, concurrency 1
docker exec vllm-qwen-spark python3 -m vllm.benchmarks.serve \
  --backend openai-chat --model /model \
  --host http://localhost:8000 \
  --dataset-name random --random-input-len 1024 --random-output-len 512 \
  --num-prompts 8 --max-concurrency 1 --seed 42 \
  --save-result --result-dir /mnt/spark_nvme/bench/C2-decode-1.json

# 3 CONCURRENT: 8k in / 1k out, concurrency 3 (your target scenario)
docker exec vllm-qwen-spark python3 -m vllm.benchmarks.serve \
  --backend openai-chat --model /model \
  --host http://localhost:8000 \
  --dataset-name random --random-input-len 8192 --random-output-len 1024 \
  --num-prompts 12 --max-concurrency 3 --seed 42 \
  --save-result --result-dir /mnt/spark_nvme/bench/C3-concurrent-3.json
```

(SGLang equivalents — `python3 -m sglang.bench_serving --backend sglang|openai … --input-len …
--output-len … --concurrency …` — to be pasted here once the SGLang image/profile is pinned.)

Note: the container rootfs is read-only and `/mnt/spark_nvme` isn't mounted
into it — either run the benchmark CLI from a side container that *does* mount
XFS, or `docker cp` the JSON out afterwards.

### Engine-neutral harness script changes (bench prep, no IaC yet)

`bench/run-scenario.sh` + `bench/snapshot-metrics.sh` are vLLM-specific today:
- `snapshot-metrics.sh` greps `vllm:*` Prometheus counters — SGLang needs its metrics (SGLang exposes
  `/metrics` with different names; capture raw + map at the parser).
- `run-scenario.sh` execs `vllm.benchmarks.serve` + `docker cp` from the vLLM container — SGLang has
  its own serving-benchmark CLI; parametrize `ENGINE` (`vllm`|`sglang`), container, port, and both
  CLIs behind one command.
- Power sampling (`nvidia-smi` `power.draw`) is engine-agnostic — keep.

These are IaC/bench-prep items (see §7/§8), not doc-only.

### Always record (from each engine's `:8000/metrics` right after each run)

| Metric | Why |
|---|---|
| TTFT p50 / p99 | prefill speed |
| Mean ITL / decode tok/s per stream | decode speed |
| Total output tok/s | aggregate @ c3 |
| `vllm:cache_hit_rate` (prefix) | caching story |
| `vllm:num_preemptions_total` (delta) | c3 degradation signature |
| `vllm:gpu_cache_usage_perc` peak | KV headroom |
| MTP acceptance (`spec_decode_num_accepted_tokens_per_pos`) | speculation health |
| Wh per 1k output tokens (`nvidia-smi` power integral) | Spark-specific cost; primitive measured 2.1–2.3 Wh/1k |

Repeat every scenario **2× minimum**, keep both seeds, discard nothing.

### Accuracy gate (required for every T3 change)

Fixed 10-prompt reasoning sanity set (mix: code, JSON extraction, one HTML
game task, one multi-step math prompt) — saved outputs diffed against B1's
outputs for manual review. Optional stricter gate: 20-item tool-calling
mini-suite scored like primitive's protocol. A T3 change is kept only if no
visible degradation vs B1.

---

## 4. Bench matrix (engine × config × context states)

The engine is a first-class matrix axis, so the phases matrix over **engine** and **context state**:

| Phase | What runs | Axis / states |
|---|---|---|
| **Prep** | downloads (AWQ, NVFP4, PLE INT4 + FP8 tables, bf16 reference), NVFP4 conversion (llm-compressor, idempotent), B1 deploy | — |
| **A-cal** | KV/token calibration at 173k per engine × KV dtype (`gpu_cache_usage_perc` → bytes/token; SGLang equivalent). Everything in D becomes arithmetic from this | per engine |
| **A** precision ladder @173k | C1 (32k prefill×8,c1) / C2 (1k decode×8,c1) / C3 (8k+1k×12,c3), each ×2 fresh seeds + 1 warm run + 10-prompt accuracy gate | **per engine** (vLLM AWQ+PLE control `bench_awq_ple` · vLLM NVFP4 if servable · SGLang NVFP4 · SGLang AWQ if PLE lands) |
| **D** context sweep | per state: `D-L-single` (1 stream, in≈90% L) + `D-L-conc3` (3 × L/2) + needle-in-haystack sanity at L + engine restart (max_model_len is startup) | {256k, 512k} × {clean, pinned} × per engine |
| **B** co-residency @173k | winner precision + pinned small models (2nd small engine for embed pooler + faster-whisper container): C-block ×2 + warm + accuracy gate + embed-burst-during-C3 stress | per engine |
| **C** conditional | identical block with small models served by Triton next to the gen engine | B-Triton — only if B shows contention, or to document Triton's drop |
| **F** tuning ladder (best engine) | §6 ladder (OMP threads, expandable segments, async-scheduling, batched-tokens, MTP disable@3, fp8 KV, NVFP4 tables, GDN kernel, KV offload) | on the winning engine |

Pre-declared skip criterion (1M): if A-cal says the fp8 KV pool < 1M even clean and minimal-swap →
skip, record "1M not achievable on 128 GB for this model; use Qdrant RAG beyond 512k". **1M remains
OUT of scope** (owner 2026-09-13).

---

## 5. Improved target metrics (from the proven posts)

| Metric | Proven reference | Baseline target for B1 |
|---|---|---|
| Decode @ 1 (code/JSON, MTP ~87%) | 102–140 tok/s (RTX 6000 Pro, INT4+MTP) | ≥ 100 tok/s |
| Decode @ c3 aggregate | 282–296 tok/s @ c4 on 6000 Pro | scale by memory bandwidth; record |
| Prefill 8k→128k | ~28k tok/s (6000 Pro) | record; judge relative gains only |
| TTFT (cached prefix) | ~90%+ hits on long-horizon | prefix hit rate ≥ 90% on agent traffic |
| KV pool | 217k tokens bf16+MTP (6000 Pro) | ≥ 500k tokens fp8-equivalent after #7, or ≥ 260k bf16 |
| Stability @ c3 | no degradation | `num_preemptions` delta = 0 per run |

Do **not** compare absolute tok/s against RTX 6000 Pro numbers — GB10 has
~273 GB/s unified bandwidth vs GDDR7. Use them only as sanity bounds; all
keep/drop decisions are relative to B1 on the same box.

Also **do not** compare vLLM absolute vs SGLang absolute across engines — each engine's keep/drop
decisions are relative to B1 on the same box **and** the engine's own B1-identical run. Engine
rankings come from the bench matrix (above) on your real workloads.

---

## 6. Engine tuning ladder (runs on the winning engine, post A/D verdict)

One variable at a time on the engine that wins phase A/D; each change measured with engines' B1
identical control as its own baseline. Steps #1–10 from the pre-research plan carry over:

| # | Change | Tier | Compose edit | Expected gain | Risk | Gate to keep |
|---|--------|------|--------------|---------------|------|--------------|
| 1 | **Deploy B1 proven baseline** | T0 proven | new file `spark-compose.proven.yaml` | parity + tool calls fixed + ~28 GB freed vs B0 | none (return to proven) | must pass C1–C3 sanity |
| 2 | `OMP_NUM_THREADS` 1 → 4 | T1 safe | env | small prefill gain (gather/dequant is CPU-side; Spark has 20 cores) | none observable | C1 TTFT ↓ or equal |
| 3 | `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` | T1 safe | env | less fragmentation → fewer OOM/preemptions at c3 | none | C3 preemptions = 0 |
| 4 | `--async-scheduling` | T1 safe | flag | few-% throughput | none | C3 total tok/s ↑ |
| 5 | `--max-num-batched-tokens` 16384 → 32768 | T2 A/B | flag | prefill t/s ↑ (bandwidth amortization) | VRAM spike w/ chunked prefill + MTP; back off to 24576 on OOM | C1 TTFT ↓ ≥10%, C3 stable |
| 6 | MTP `disable_by_batch_size: 3` | T2 A/B | flag | aggregate t/s @ c3 ↑ when traffic is chat-heavy (acceptance ~40%); code-heavy may prefer status quo | profile-dependent | C3 total tok/s ↑ on **your real traffic mix** |
| 7 | KV cache dtype fp8 (vs B1 bf16) | T3 gate | flag | 2× KV tokens/GB → bigger cache, more concurrent full-length sessions | accuracy unvalidated on hybrid GDN; 98/100 measured on bf16 | C1–C3 pass **and** accuracy gate passes |
| 8 | PLE tables INT4 → NVFP4 (`ples_nvfp4`, 28.8 GB) | T3 gate | volume path + re-download | +3.2 GB to KV; equal-or-better accuracy per primitive's table (78.7 vs 78.2) | needs its own boot + gate | accuracy gate passes |
| 9 | `VLLM_GDN_DECODE_KERNEL=triton` | T3 gate | env | unknown on AWQ build (proven only on mixed NVFP4/FP8) | decode regression possible | accuracy gate + C2 decode ↑ |
| 10 | KV offload connector (LMCache → `/mnt/spark_nvme/kv_cache`) | T4 infra | new dependency + config | warm prefix cache across restarts; cache ≫ VRAM; biggest TTFT lever on recurring long contexts | new component, cold-start behavior, version pinning needed | C-prefill-repeat scenario TTFT ↓ ≥50% |

Engine-specific ladder rows added if a winner engine shows a distinct tuning knob (SGLang: RadixAttention
prefix caching, `--max-total-tokens` pool, mamba flags).

### TRT-LLM — future row, not a current bench candidate

TensorRT-LLM is **not** a bench candidate for Qwen3.8-Flash-Next on this box today, and stays as a
future row. Rationale (R6 digest + NVIDIA sources checked 2026-09-14):
- **Model path is missing for single-GB10.** NVIDIA's official Day-0 TRT-LLM support + deployment
guide (`nvidia.github.io/TensorRT-LLM/latest/deployment-guide/deployment-guide-for-qwen3.8-qwen3.5-on-trtllm.html`)
cover the **`Qwen3.8-2.4T-A95B`** MoE (min 16× GB200/GB300) and **`Qwen3.5-397B-A17B`** (min 4×) — no
single-G10 GB10 path, and the validated GPU table is B200/B300/GB200/GB300 only. The blog's
"also runs on local hardware" mentions DGX Spark **clusters** (2×), not a single Spark, and not via
TRT-LLM.
- **No single-GB10 TRT-LLM serving report exists** for this model (community single-Spark runs are
vLLM-patched/SGLang/llama.cpp only).
- **PLE n-gram table has no TRT-LLM story** (vLLM-overlay/patched-vLLM artifacts only).
- NVIDIA's own engine is the right call on **rack-scale/multi-GPU** (blog: 16K tok/s/GPU on GB300), so
this row gets revisited when upstream ships a `sm_121` path **or** we go 2× Spark (TP2) — TRT-LLM is
then likely the top perf engine, and gets its own lane.

Until then, engine candidates are **vLLM + SGLang** only (both have documented containers/recipes for
this model on GB10). See `spark/resources/R6-trtllm-gb10.md` + sources above.

---

## 7. Tooling & timing (`bench/`)

| Script | Purpose |
|---|---|
| `bench/snapshot-metrics.sh <label>` | Grabs preemption/cache/MTP/token counters from the engine's `:8000/metrics` into `bench/raw/metrics-*.txt` + a `.env` file of parsed values (vLLM names today; SGLang mapping is bench-prep). |
| `bench/run-scenario.sh <STEP> <C1\|C2\|C3> [seed] [--router] [--warm]` | Full automation: metrics BEFORE → `nvidia-smi` power sampler → bench CLI inside the container → metrics AFTER → parses TTFT/ITL/throughput + computes preemption delta, MTP acceptance delta, Wh per 1k output tokens → appends one CSV row to `bench/results.csv`. Engine-parameterised (vLLM today; SGLang bench-prep adds `ENGINE`). |
| `bench/accuracy-gate.sh <LABEL>` | Fixed 10-prompt sanity set (incl. one tool-call prompt that exercises `--enable-auto-tool-choice`). Saves raw outputs to `bench/accuracy/<LABEL>/` for diffing vs `bench/accuracy/B1/`. |

Engine-neutral means the **same CSV schema, same raw/ dir, same labels** — only the underlying
container/CLI changes per engine.

Typical ladder step (run these on the Spark host, `bash`):

```bash
# warmup after every restart (also populates CUDA graphs / prefix cache path)
curl -s http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"/model","messages":[{"role":"user","content":"hi"}],"max_tokens":8}' > /dev/null

./bench/accuracy-gate.sh B1
cp -r bench/accuracy/B1 bench/accuracy/B1-ref   # keep as comparison target
./bench/run-scenario.sh B1 C1 42 && ./bench/run-scenario.sh B1 C1 43   # repeat w/ new seed = cache-free
./bench/run-scenario.sh B1 C2 42 && ./bench/run-scenario.sh B1 C2 43
./bench/run-scenario.sh B1 C3 42 && ./bench/run-scenario.sh B1 C3 43
./bench/run-scenario.sh B1 C1 42 --warm                 # same seed = warm-prefix TTFT
./bench/run-scenario.sh B1 C3 42 --router               # e2e through llm-d, end of ladder only
```

**Seed rule:** different seed per repeat → fresh random prompts → cache-free perf.
Same seed + `--warm` → identical prompts → warm-prefix cache measurement.

### How long does everything take?

| Item | Duration |
|---|---|
| C1 (32k prefill × 8, c1) | ~1.5–3 min/run |
| C2 (1k decode × 8, c1) | ~1 min/run |
| C3 (8k/1k × 12, c3) | ~1.5–2.5 min/run |
| Full C1+C2+C3 ×2 + warm run | **~10–20 min** per config state |
| Accuracy gate | ~3–5 min (10 prompts, ≤1024 tok out) |
| **Per ladder step, total** | **~15–25 min** of benchmarking |
| Engine restart between steps | ~6–20 min (cold INT4 table load 333–417 s; warm compile caches on XFS cut this substantially — the first restart after a change is the slow one) |
| Dropped change + revert + rebench | ×2 cost for that step |
| **Full 9-step ladder (T1–T3)** | **~1 working day** realistically, with the T3 accuracy gates adding ~30 min |
| T4 (KV offload) | separate work item (dependency install, cold-start tuning) |

Note: `run-scenario.sh` reports its own `duration_s` per row, so actual timings replace these estimates in `results.csv` from the very first run.

---

## 8. Reference expectations for the bench (community data — NOT measured on this box)

These replace neither A-cal nor per-engine results; they size the sweep and sanity-bound keep/drop.
Sources: `spark/resources/RESEARCH-VERDICTS.md` §2 (GB10 calibration) + `BENCHMARK-PLAN.md` target
metrics. **GB10 measured numbers, not x86:** GB10 unified 273 GB/s vs RTX 6000 Pro GDDR7 — never
compare absolute tok/s across boxes.

| Metric | Value (GB10, single Spark) | Source |
|---|---|---|
| Decode, single stream | 36.8 prose / 45.8 code tok/s (NVFP4, MTP3, FP8 KV) · 41.5 (SGLang, code) | madeye; hashd1ve; NVIDIA forum |
| Aggregate decode | 100.2 tok/s @ 4 concurrent (NVFP4, TP1) | madeye 2026-09-10 |
| Prefill | 1.6–1.8k tok/s (8k–33k prompts) | madeye |
| TTFT | ~0.2–0.26 s single | madeye |
| MTP acceptance | 65.7% mixed (vs ~87% code-only x86) | madeye |
| Context demonstrated | 262k native (SGLang + vLLM); 524,288 via YaRN | hashd1ve; madeye |
| KV pool | 507,810 tokens @ 7.44 GiB (FP8 KV, 6 slots, after weights+PLE) | madeye |
| Correctness trap | QSA decode via XQA on sm_12x corrupts ≥120k-context requests (HTTP 200); Triton varlen #36845 fixes — needle-test every profile | hashd1ve; sglang#36806/#36845 |
| Keep/drop rule | ~20× less bandwidth than RTX 6000 Pro ⇒ compare vs B1-on-box only | — |

**Sanity targets (from the proven posts, x86 reference):** decode @1 ≥ 100 tok/s (MTP, code) · zero
preemptions @3 concurrent · prefix hit ≥ 90% on agent traffic · KV ≥ 260k bf16 / ≥ 500k fp8 (A-cal
replaces these targets). Do **not** promote any §8 number into the SSOT config: specifications come
only from benches on this box.

---

## 9. Results log (fill in as you go)

| Step | Engine | Config delta | C1 TTFT p50/p99 | C2 tok/s @1 | C3 tok/s @3 | Preemptions | Cache hit % | Accuracy | Verdict |
|------|--------|--------------|-----------------|-------------|-------------|-------------|-------------|----------|---------|
| B1 | vLLM | proven baseline | | | | | | | |
| A2 | SGLang | NVFP4 | | | | | | | |
| A3 | vLLM | NVFP4 | | | | | | | |
| D256 | vLLM | YaRN 262k | | | | | | | |
| D512 | SGLang | YaRN 524k | | | | | | | |
| S5 | SGLang | longctx ×3 | | | | | | | |
| #2 | vLLM | OMP=4 | | | | | | | |
| #3 | vLLM | expandable_segments | | | | | | | |
| #4 | vLLM | async-scheduling | | | | | | | |
| #5 | vLLM | batched-tokens 32768 | | | | | | | |
| #6 | vLLM | MTP disable@3 | | | | | | | |
| #7 | vLLM | fp8 KV | | | | | | | |
| #8 | vLLM | NVFP4 tables | | | | | | | |
| #9 | vLLM | GDN triton | | | | | | | |
| #10 | vLLM | KV offload | | | | | | | |

---

## 10. Post-bench SSOT promotion (after benches certify)

Once a profile's gate is met (accuracy + performance + stability), promote that config into the SSOT:

| SSOT file | When to update | What lands |
|---|---|---|
| `spark/ansible/group_vars/spark_nodes.yml` | after a profile wins on this box | winning engine + precision + KV + context (today it still carries B0 legacy fp8/swap32 values — bench decides which profile replaces them) |
| `spark/spark-compose.proven.yaml` | after B1 revalidate + any engine switch | promoted compose per certified profile (vLLM today; SGLang compose added when it wins) |
| `spark/README.md` | after verdict | engine set + certified profiles table + digest (already pinned `sha256:fc120ece…`) |
| `docs/hardware-spark.md` | after verdict | link to this plan (§Bench) + the certified profile matrix as the node's launcher config |
| `docs/services-ai.md` | after verdict | LiteLLM routing to the winning engine/port |