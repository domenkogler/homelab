# Spark GB10 research handoff — engine/precision/context research spike

> **Role:** Self-contained handoff for a research session with **web search enabled**. Contains the
> full context of the planning thread (2026-09-13) plus all research questions. Everything needed
> to execute the research should be derivable **from this file alone** — no repo access assumed,
> but repo doc references are included where the reader has them.
> **Linked from:** `todo.md` (to be registered as the research HD row), `docs/hardware-spark.md`,
> `docs/services-ai.md`, `spark/BENCHMARK-PLAN.md`, `spark/README.md`
> **Scope:** research + fact-checking only. No IaC changes, no execution.

---

## 1. The setup (what hardware, what model, what goal)

### Hardware: DGX Spark-class node `spark.kogler.si`
- Lenovo ThinkStation PGX — **NVIDIA GB10 Grace Blackwell** superchip (same silicon as DGX Spark).
- **20-core Arm** (10× Cortex-X925 + 10× Cortex-A725) + Blackwell GPU, compute capability **sm_121**.
- **128 GB unified LPDDR5x** — CPU and GPU share ONE pool, ~**273 GB/s** memory bandwidth.
  ⚠️ This makes "CPU offload" meaningless (same pool) and makes *bandwidth contention between
  co-resident models* a first-class concern, not just capacity.
- 1 TB / 4 TB self-encrypting NVMe; XFS partition for mmap offload (see disk layout below).
- 1 PFLOP FP4 tensor-core peak. Runs **DGX OS / Ubuntu + CUDA 13**. Headless, managed by Ansible.
- Not yet provisioned (deploy-gated) — that is why this is a research/plan phase.
- Known bring-up reference for GB10 + Arm quirks (no ARM64 wheels for some stacks, run ML
  container-native): `github.com/martimramos/dgx-spark-ml-guide`.

### Model (the ONLY model in scope): Qwen3.8-Flash-Next
- HF repos currently used by the stack:
  - Quantized inference checkpoint: **`wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16`** (AWQ W4A16)
  - PLE quantization overlay + INT4 n-gram tables: **`primitive-ai/Qwen3.8-Flash-Next-PLE-quant`**
    (files: `worker_image_quant.py`, `ple_layer_quant.py`, `connector_mrv2.py`; tables `ples_int4/*`, ~32 GB)
- Architecture: **hybrid GDN** (gated-delta-net / linear-attention hybrid, Qwen3-Next family style)
  with a fraction of full-attention layers + **MTP** (multi-token prediction) head for speculative decoding.
  ⚠️ Consequence: KV bytes/token is NOT comparable to a standard transformer — the linear layers have
  (near-)constant state; only the full-attention fraction scales with context. KV/token must be **measured**.
- Proven community recipe (r/LocalLLaMA threads `1w7c4ej` and `1w2b2j0`): **98/100 reasoning accuracy**
  (10-prompt gate) at AWQ W4A16 + PLE INT4 tables, **170K context** (max_model_len 173,400),
  MTP-3 acceptance ~87% on code/JSON.
- OpenAI-compatible serving, tool calling required (`--enable-auto-tool-choice` + parser).

### Goal
Four serving scenarios (profiles) on spark, **all with Qwen3.8-Flash-Next only**:

| # | Scenario | Priority | Rough shape |
|---|---|---|---|
| S1 | **Best reasoning, single session** | accuracy first | bf16 (FP16) weights/KV, ~173k context |
| S2 | **Fastest single session** | latency/throughput first | AWQ+PLE (proven) or NVFP4, ~173–256k |
| S3 | **Fastest 3–5 concurrent sessions** | aggregate throughput | NVFP4 (or AWQ+PLE), MTP tradeoffs, ≤256k |
| S4 | **Max context per scenario** | per-row ceiling | 256k → 512k target; **1M agreed OUT of scope** |

A fifth axis for S2/S3/S4: the pinned "assistants" small models may be co-resident (see §4) —
the bench must measure both clean and pinned states.

---

## 2. The proven config (baseline B1) — reproduce verbatim for A1 control

From `spark/ansible/group_vars/spark_nodes.yml` (vLLM, image `vllm/vllm-openai:qwen38-flash-next` —
**digest still unpinned, placeholder `REPLACE_WITH_ACTUAL_DIGEST`**):

```yaml
max_num_seqs: 4
max_model_len: 173400
enable_chunked_prefill: true
max_num_batched_tokens: 16384
enable_prefix_caching: true
gpu_memory_utilization: 0.95
kv_cache_dtype: "auto"            # bf16 — proven; fp8 is an unproven ladder step
memory_limit: "126G"
swap_space: 4                     # NOT 32 — unified memory! 32 GB swap stole ~28 GB from KV in B0
shm_size: "32g"
speculative_method: "mtp"         # 3 tokens, plain; no disable threshold in proven baseline
speculative_tokens: 3
enable_auto_tool_choice: true     # required with tool-call-parser
reasoning_parser: "qwen3"
tool_call_parser: "qwen3_coder"
distributed_executor_backend: "mp"   # LOAD-BEARING for single-GPU PLE offload
quantization: "awq"
cpu_offload: 1
disable_flashinfer_autotune: true
override_generation_config: '{"temperature":1,"top_p":0.95,"top_k":20}'  # Qwen3 recommended sampling
enforce_eager: false              # CUDA graphs + torch.compile ON
pytorch_cuda_alloc_conf: "max_split_size_mb:512"
```

Plus routing: **llm-d Router** (`ghcr.io/llm-d/router:latest`, port 8080 → vLLM :8000,
`max_concurrent_sessions: 3`, FIFO, flow control). Storage: XFS on NVMe second partition
(`agcount=16`, `noatime,nodiratime,logbufs=8,logbsize=256k,nobarrier`) mounted `/mnt/spark_nvme`
holding KV cache dir, INT4 tables, vllm/triton compile caches (persisted = faster restarts).
Compose baseline: B1 = `spark-compose.proven.yaml` (bf16 KV, swap 4, tool calls ON) vs
B0 legacy = `spark-compose.yaml` (fp8 KV, swap 32, tool calls not enabled) — B0 kept only to
quantify the deviation.

**Unified-memory budget rule (must hold for every profile):**
`gpu_memory_utilization budget (~121 GB @ 0.95) + swap_space + PLE table page cache (~32 GB mmap'd)
+ pinned small models (~4–5 GB) + KV cache ≤ 128 GB`.

---

## 3. Research questions (R1–R6) — execute these with web search

| # | Question | What to find / where to look | Blocks |
|---|---|---|---|
| **R1** | Do **original bf16 weights** of Qwen3.8-Flash-Next exist on HF? (The AWQ repo `wtdcode/Qwen3.8-Flash-Next-AWQ-W4A16` may not carry them.) Which repo/size? If they don't exist, is dequantizing AWQ→bf16 viable as a benchmark reference, or must A0 be dropped? | HF model card + repo file listing; search "Qwen3.8-Flash-Next" | S1 (bf16 profile), NVFP4 conversion |
| **R2a** | Does an **NVFP4 recipe exist for hybrid GDN / Qwen3-Next-family** models (llm-compressor `NVFP4` scheme)? Any precedent of someone running NVFP4 of this model/arch? | llm-compressor docs/releases, HF `compressed-tensors` models, r/LocalLLaMA | A2, S2/S3 NVFP4 profiles |
| **R2b** | Do **NVFP4 PLE tables** exist (primitive-ai shipped INT4, ~32 GB; an NVFP4 variant ~28.8 GB is hypothesized)? If not, does NVFP4-without-PLE still pass an accuracy gate? | primitive-ai HF page, r/LocalLLaMA threads | A2 |
| **R3** | What is the model's **native/extended context window**? Does its `config.json` (RoPE / YaRN scaling) support >173k? Has anyone run 256k/512k on this model or the Qwen3-Next family? What rope-scaling config did they use? | model config.json, Qwen3-Next family docs, r/LocalLLaMA long-context reports | D context sweep (256k/512k) |
| **R4** | The pinned vLLM image `vllm/vllm-openai:qwen38-flash-next` — which build is it, does it support **GB10 sm_121 + aarch64**, where is it published, what is the **digest to pin**? If it's a community build, what is the cleanest supported alternative (official vLLM release with the needed flags) on GB10? | Docker Hub / GHCR inspection, vLLM release notes (sm_121/Blackwell support status), dgx-spark-ml-guide | EVERYTHING (bench plan existence) |
| **R5** | **SGLang on GB10**: build/runtime status on sm_121 + aarch64, Qwen3-Next hybrid-GDN support, long-context support, any DGX Spark perf reports vs vLLM. | SGLang releases/issues, r/LocalLLaMA, DGX Spark community benchmarks | escape-hatch decision only |
| **R6** | **TensorRT-LLM on GB10/DGX Spark**: official support path, perf reports vs vLLM, model-build complexity for a hybrid-GDN MTP model. | NVIDIA DGX Spark docs, TRT-LLM release notes, NGC catalogs | escape-hatch decision only |

**Deliverable:** updated readiness table (§6) + a verdict per question, before any IaC is written.

---

## 4. The RX 7600 (oldsrv) motivation — why spark may NOT host everything

**Decision #23 (2026-09-06, repo SSOT):** oldsrv (AMD Radeon **RX 7600, 8 GB**, RDNA3/gfx1102) was
set to *Sunshine gaming-encode only — no AI/ROCm/Ollama; ALL inference consolidated on spark (Triton)*.
The plan under discussion **partially re-opens** this: pin the small "assistants" models on the RX 7600
so spark's 128 GB unified pool is spent on the ONE big model instead.

| Pinned on RX 7600 | VRAM (fp16 / int8) | Runtime note on RDNA3 |
|---|---|---|
| bge-m3 embeddings (568M) | ~1.2 / ~0.7 GB | `onnxruntime-rocm` or Ollama embeddings — solid on gfx1102 |
| bge-reranker-v2-m3 (568M) | ~1.2 / ~0.7 GB | same runtime |
| Whisper **large-v3-turbo** (809M) — NOT large-v3 | ~1.5–1.8 GB | ⚠️ faster-whisper/CTranslate2 is **CUDA-only** → use **whisper.cpp** (Vulkan/HIP) on AMD |
| Piper TTS (VITS) | ~0.1 GB | trivial; CPU-fine |
| XTTS v2 (750M) — optional | ~1.6 GB | ⚠️ Coqui-on-ROCm fragile → recommendation: XTTS on CPU or drop; don't pin |
| Sunshine (gaming encode, always first) | ~0.3–0.5 GB | coexists fine |
| immich-ML on demand (ONNX GPU) | ~1.5–3 GB | GPU only for first-upload backfill, then CPU; existing pause pattern |

Totals: pin embed+rerank+turbo+Piper ≈ **4–5 GB pinned** → leaves ~3 GB for immich-ML burst ✅.
Pin XTTS too → ~6 GB → too tight.

**Why this matters for the spark bench:** those 4–5 GB come straight out of spark's KV budget.
At bf16 KV (~140 KB/token estimated from the 217k-tokens-on-96GB reference), 5 GB ≈ **~35k tokens of
context lost**. At 256k bf16 that is likely the difference between fits and preempts — hence the
bench's "clean vs pinned" states per context size, and hence S4's per-scenario max-context answers
depend on where the small models live. If spark co-residency costs ≈ nothing, everything stays on
spark and decision #23 survives untouched; if contention is real, the RX 7600 plan is the ready-made
fallback (and the re-decide gets documented with bench evidence).

---

## 5. Triton vs vLLM — reasoning that led here (so the research doesn't re-litigate)

- Original repo SSOT: spark = **Triton Inference Server** serving an NVFP4 **multi-model set**
  (Nemotron-30B, Qwen3-Next-80B, Llama-3.3-70B, coder, bge-m3/reranker, Whisper, XTTS/Piper).
- A standalone project (`spark/`) exists with a **vLLM + llm-d** proven recipe for Qwen3.8-Flash-Next.
- Insight that reshaped the plan: the small models (embed/rerank/voice/immich-ML) move to oldsrv's
  RX 7600 → spark needs **only ONE generation model** → Triton's multi-model advantage disappears.
- Therefore: the real decision is **precision + co-residency + context ceiling** on vLLM, benched
  apples-to-apples; Triton is dropped **unless** the conditional Phase C trigger fires (co-residency
  contention, or a desire to document the drop with measured data).
- Engine landscape (research, not bench-by-default): **vLLM = default because the PLE offload overlay
  — the entire 98/100 recipe — is vLLM-only.** TRT-LLM = NVIDIA's official GB10 path, likely best raw
  perf, but no PLE recipe and heavy model-build complexity. SGLang = middle ground (RadixAttention
  prefix caching suits agent traffic; hybrid-GDN support reported) — cheapest port if vLLM fails.
  **Pre-declared escape-hatch rule:** vLLM loses the default slot only if it fails a Phase-D context
  target (256k/512k) or the accuracy gate; then SGLang gets the spike first, TRT-LLM second.

---

## 6. Bench plan (as agreed; execute AFTER the research spike clears R1–R4)

Context sizes **256k and 512k only** (1M pre-declared OUT — see skip criterion). Estimated grand
total ~6.5–8 h benching + ½ day unattended prep. Every scenario = an **Ansible profile**; switching
is one group_vars line + playbook run; bench harness calls the switch.

| Phase | What runs | States |
|---|---|---|
| **Prep** | downloads (AWQ, bf16 base, INT4 tables), NVFP4 conversion (llm-compressor, idempotent), B1 deploy | — |
| **A-cal** | KV/token calibration at 173k (read `vllm:gpu_cache_usage_perc` → bytes/token). Everything in D becomes arithmetic from this. | 1 |
| **A** precision ladder @173k | C1 (32k prefill×8,c1) / C2 (1k decode×8,c1) / C3 (8k+1k×12,c3), each ×2 fresh seeds + 1 warm run + 10-prompt accuracy gate | A1 AWQ+PLE (control) · A0 bf16 · A2 NVFP4 · A3 fp8 (optional) |
| **D** context sweep | per state: `D-L-single` (1 stream, in≈90% L) + `D-L-conc3` (3 × L/2) + needle-in-haystack sanity at L + engine restart (max_model_len is a startup flag) | {256k, 512k} × {clean, pinned} = 4 cycles |
| **B** co-residency @173k | winner precision + pinned small models (2nd small vLLM for embed pooler + faster-whisper container): C-block ×2 + warm + accuracy gate + embed-burst-during-C3 stress | B-vLLM |
| **C** conditional | identical block with small models served by Triton next to vLLM gen | B-Triton — **only if** B shows contention, or to document Triton's drop with data |
| **Post-verdict** | tuning ladder (OMP threads, expandable segments, async-scheduling, batched-tokens, MTP disable@3, fp8 KV, NVFP4 tables, GDN kernel, KV offload) on the final profile | ~1 working day |

**Pre-declared skip criterion (1M):** if A-cal arithmetic says the fp8 KV pool < 1M even clean and
minimal-swap → skip, record "1M not achievable on 128 GB for this model; use Qdrant RAG beyond 512k".
**Expected (to be replaced by A-cal):** 256k marginal at bf16 clean / needs fp8 when pinned;
512k feasible at fp8; 1M out.
**Standing metrics every run:** TTFT p50/p99, decode tok/s, total tok/s, preemption delta,
prefix cache hit %, KV pool usage, MTP acceptance, Wh/1k output tokens (power integral).
**Keep/drop rule:** relative to B1 on the same box, never vs RTX 6000 Pro absolute numbers (GB10 has
273 GB/s unified vs GDDR7 — different bandwidth class).

### Scenario → profile mapping (the four serving profiles to certify at verdict time)

| Profile | Weights | KV | max_model_len | max_num_seqs | Notes |
|---|---|---|---|---|---|
| `serving_reasoning_fp16` (S1) | bf16 | bf16 | 173400 | 1 | best accuracy; needs R1 |
| `serving_fast_single` (S2) | AWQ+PLE or NVFP4 (A-verdict) | winner's | ≤256k | 1 | |
| `serving_concurrent_3_5` (S3) | NVFP4 or AWQ+PLE | winner's | ≤256k | 3–5 | MTP disable-threshold maybe |
| `serving_longctx_512k` (S4) | winner | fp8 | 512000 | 1 | needs R3 + D verdict |
| `bench_awq_ple` (control) | AWQ+PLE | bf16 | 173400 | 4 | = B1 verbatim |

Each profile needs model files pre-downloaded (switch = restart, not re-download), and each carries
`assistants_pinned: true/false` for the clean/pinned bench states.

---

## 7. Config readiness (pre-research)

| Profile | Status | Missing |
|---|---|---|
| AWQ+PLE @173k | ✅ proven | only the image **digest pin** (R4) |
| bf16 @173k | ⚠️ | bf16 weights existence (R1) |
| NVFP4 | ❌ | conversion recipe for hybrid GDN + NVFP4 PLE tables (R2) |
| fp8 KV | ⚠️ | accuracy unvalidated on hybrid GDN (gate covers it) |
| 256k/512k | ⚠️ | RoPE/YaRN >173k support (R3) + A-cal numbers |
| small-models runtime | ✅ runtime known | config templates unwritten (IaC port) |

---

## 8. Timing reference (from the existing harness; measured numbers replace estimates)

C1 ~1.5–3 min/run · C2 ~1 min/run · C3 ~1.5–2.5 min/run · full block (C1/C2/C3 ×2 + warm) ~10–20 min ·
accuracy gate ~3–5 min · engine restart ~6–20 min (cold INT4 table load 333–417 s; warm compile caches
on XFS cut it; NVFP4 state has no PLE tables to load) · NVFP4 conversion ~2–4 h (estimate) ·
downloads ~75 GB model + ~32 GB tables (background/overnight).

---

## 9. Expected research outcomes (what a clean result looks like)

1. R1–R4 all green → write the full IaC port + profiles, run the bench plan as tabled in §6.
2. R1 red (no bf16 weights) → drop S1-as-bf16; best-reasoning profile becomes AWQ+PLE (the 98/100
   config) or dequantized reference, documented as such.
3. R2 red (no NVFP4 for hybrid GDN) → S2/S3 stay AWQ+PLE; NVFP4 becomes a "future" row; A2 dropped.
4. R3 red (no >173k support) → D shrinks to {256k} or dies entirely; max-context answer = 173k.
5. R4 red (no sm_121 image) → **hard blocker**: the whole bench plan needs a different engine base
   (this is where R5/R6 stop being optional).
6. R5/R6 → only inform the escape hatch; do NOT triple the bench matrix "just in case".
