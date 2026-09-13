# Spark Baseline → Tuning Benchmark Plan

> **Rule:** one variable at a time, benchmark before/after, record in the results
> table at the bottom. If a change fails its gate, revert the single flag and move on.

---

## 1. Baselines

| ID | Config | Compose file | Status |
|----|--------|--------------|--------|
| **B0 (current)** | fp8 KV, swap 32, no auto-tool-choice, disable_by_batch_size 6 | `spark-compose.yaml` | what runs today |
| **B1 (proven)** | bf16 KV, swap 4, auto-tool-choice, plain MTP-3 | `spark-compose.proven.yaml` | **new reference point** |

B1 is a strict return to proven recipes (WonderRico 98/100 + UltrMgns 170K +
primitive-ai overlay card). Expected outcome: same or better decode, more KV
headroom (−28 GB swap on unified memory), working tool calls. B0 is kept only
so we can quantify what the fp8/swap32 deviations were actually doing.

---

## 2. Benchmark harness

Run benchmarks **direct against the engine** (`:8000`) to measure vLLM; run
scenario C again through the **router** (`:8080`) to catch e2e overhead.

The `vllm/vllm-openai:qwen38-flash-next` image ships the benchmark CLI:

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

Note: the container rootfs is read-only and `/mnt/spark_nvme` isn't mounted
into it — either run the benchmark CLI from a side container that *does* mount
XFS, or `docker cp` the JSON out afterwards.

### Always record (from `:8000/metrics` right after each run)

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

## 3. Proposed change ladder

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

### Execution order

```
B1 deploy → C1/C2/C3 ×2 → accuracy snapshot
  → #2 → bench → keep/drop
  → #3 → bench → keep/drop
  → #4 → bench → keep/drop
  → #5 (16384↔24576↔32768 sweep) → bench → keep/drop
  → #6 (A/B on real traffic mix) → bench → keep/drop
  → #7 → accuracy gate → bench → keep/drop
  → #8 → accuracy gate → bench → keep/drop
  → #9 → accuracy gate → bench → keep/drop
  → #10 (separate work item)
```

Each kept change folds into the running "best" config; each dropped change is
reverted before the next step so the ladder stays one-variable-at-a-time.

---

## 4. Target metrics (from the proven posts)

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

---

## 5. Tooling & timing (`bench/`)

| Script | Purpose |
|---|---|
| `bench/snapshot-metrics.sh <label>` | Grabs preemption/cache/MTP/token counters from `:8000/metrics` into `bench/raw/metrics-*.txt` + a `.env` file of parsed values, appends a summary line to `bench/metrics-summary.log`. |
| `bench/run-scenario.sh <STEP> <C1\|C2\|C3> [seed] [--router] [--warm]` | Full automation: metrics BEFORE → `nvidia-smi` power sampler → `vllm bench serve` inside the container → metrics AFTER → parses TTFT/ITL/throughput + computes preemption delta, MTP acceptance delta, Wh per 1k output tokens → appends one CSV row to `bench/results.csv`. |
| `bench/accuracy-gate.sh <LABEL>` | Fixed 10-prompt sanity set (incl. one tool-call prompt that exercises `--enable-auto-tool-choice`). Saves raw outputs to `bench/accuracy/<LABEL>/` for diffing vs `bench/accuracy/B1/`. |

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

## 6. Results log (fill in as you go)

| Step | Config delta | C1 TTFT p50/p99 | C2 tok/s @1 | C3 tok/s @3 | Preemptions | Cache hit % | Accuracy | Verdict |
|------|--------------|-----------------|-------------|-------------|-------------|-------------|----------|---------|
| B1 | proven baseline | | | | | | | |
| #2 | OMP=4 | | | | | | | |
| #3 | expandable_segments | | | | | | | |
| #4 | async-scheduling | | | | | | | |
| #5 | batched-tokens 32768 | | | | | | | |
| #6 | MTP disable@3 | | | | | | | |
| #7 | fp8 KV | | | | | | | |
| #8 | NVFP4 tables | | | | | | | |
| #9 | GDN triton | | | | | | | |
| #10 | KV offload | | | | | | | |
