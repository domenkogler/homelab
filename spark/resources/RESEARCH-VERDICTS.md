# Research spike verdicts — R1–R6 (Qwen3.8-Flash-Next on spark/GB10)

> **Role:** Synthesis of the 2026-09-13 research spike (summary.md handoff, R1–R6). One verdict per
> question, scenario→profile mapping for S1–S5, GB10 calibration numbers, and the proposed updated
> readiness table (proposal for summary.md §7 — NOT yet applied).
> **Linked from:** `summary.md`, per-question digests `R1-*.md` … `R6-*.md` (raw captures alongside).
> **Method:** 6 parallel research lanes mined the 5 local captures; parent lane (web/registry access)
> verified all lane-flagged gaps and folded addenda into each digest. All verdicts below are
> parent-verified. Bench candidates = pullable checkpoints/images + documented flags only; no engine
> building/patching (community file-overlay recipes are treated as published artifacts, flagged).

---

## 1. Verdicts at a glance

| Q | Question | Verdict | One-line result |
|---|----------|---------|-----------------|
| R1 | Original bf16 weights exist? | **GREEN** (existence) / **S1-as-bf16 RED** (fit) | Canonical repo `Qwen/Qwen3.8-Flash-Next` verified (624k dl/mo, bf16). bf16 ≈ 250 GB, FP8 172.8 GB — **neither fits 121.63 GiB**. S1 must be quantized; bf16 = provenance anchor only. |
| R2 | NVFP4 weights + PLE tables | **GREEN** (with GB10 engine caveat) | 4 pre-quantized checkpoints (`nvidia/`, `RadixArk/`, `primitive-ai/` ×2) + `ples_nvfp4` 28.8 GB sidecar. BUT: stock vLLM on GB10 = NVFP4→Marlin fallback, unservable (#50925); NVFP4 on GB10 = **SGLang** (2 published recipes) or patched vLLM nightly. |
| R3 | Context beyond 173k | **GREEN** | Native **262,144** (config.json `rope_type: "default"`, no YaRN); officially **extensible to 1M** via YaRN factor 4.0 (official commands for vLLM `--hf-overrides` / SGLang `--json-model-override-args`; factor 2.0 recommended for ~512k use). Needle 4/4 at 120k/190k/210k on GB10 (with correct kernel path). |
| R4 | vLLM image + GB10 gate | **GREEN** (was the hard gate) | Tag exists on Docker Hub; **multi-arch arm64+amd64 confirmed**; digest to pin `sha256:fc120ece0a388cc0aa1caad4a9f1cd92113484ab7ec2fd0efadd62585be05bf8`; dedicated `…-arm64-cu130` tag = DGX Spark candidate. Published vLLM sm_121 support still incomplete upstream (#31740/#38484 open) — NVFP4 trap + possible community image `timothystewart6/vllm-gb10` as fallback. |
| R5 | SGLang on GB10 | **GREEN** — strongest single-Spark recipe | Official NVIDIA playbook + `lmsysorg/sglang:spark`; this exact model runs on 1 Spark (hashd1ve: 126 GiB checkpoint, 41.5 tok/s code, full 262k, GSM8K-verified) and 2× Spark TP2 (tonyd2wild day-0). Watch issue #36716 (4 single-device bugs) and the QSA kernel-path trap (#36845 fix mandatory). |
| R6 | TRT-LLM on GB10 | **RED** for this model today | TRT-LLM officially ships for DGX Spark (playbook, container 1.2.0) — but NO Qwen3.8-Flash-Next path, Qwen-MoE NVFP4 export broken on GB10 (#12762), no PLE-table story. Future row; revisit only per escape-hatch rule (SGLang first anyway). |

**No RED blockers for the bench plan.** R4's aarch64 risk — the one flagged as gating everything —
is resolved by the multi-arch manifest.

## 2. GB10 calibration (measured, single Spark — replaces x86 RTX 6000 Pro numbers)

| Metric | Value | Source |
|---|---|---|
| Decode, single stream | **36.8 prose / 45.8 code tok/s** (NVFP4, MTP3, FP8 KV) · 41.5 (SGLang, code) · ~43–44 (forum) · 64 peak (NVIDIA NVFP4, 1–4 Sparks thread) | madeye; hashd1ve; NVIDIA forum |
| Aggregate decode | **100.2 tok/s @ 4 concurrent** (NVFP4, TP1) | madeye 2026-09-10 |
| Prefill | **1.6–1.8k tok/s** (8k–33k prompts) | madeye |
| TTFT | ~0.2–0.26 s single | madeye |
| MTP acceptance | 65.7% (mixed workload; vs ~87% code-only on x86) | madeye |
| Context demonstrated | 262k native (SGLang + vLLM); **524,288 via YaRN** (`serve-500k.sh`, single Spark) | hashd1ve; madeye |
| KV pool | **507,810 tokens @ 7.44 GiB** (FP8 KV, 6 slots, after weights+PLE) | madeye |
| Checkpoint anatomy (RadixArk NVFP4) | 68 GB NVFP4 experts + 47.7 GiB FP8 PLE + 16 GB BF16 rest = 126.0 GiB | hashd1ve |
| Memory mechanics | PLE "offload to host RAM" frees **nothing** on unified memory → PLE must go to NVMe (mmap, <3% wall-clock cost) | hashd1ve; Qwen tech report §2.3.2 |
| Correctness trap | QSA decode via XQA on sm_12x silently corrupts ≥120k-context requests (token-id-0, HTTP 200); Triton varlen (#36845) is the fix — **bench must needle-test every profile** | hashd1ve; sglang#36806/#36845 |
| Keep/drop rule | Confirmed: ~20× less bandwidth than RTX 6000 Pro ⇒ compare vs B1-on-box only | — |

## 3. Scenario → profile mapping (proposal for summary.md §6 tables)

| Profile | Scenario | Engine (primary / fallback) | Weights | KV | Context | Notes |
|---|---|---|---|---|---|---|
| `serving_reasoning` (S1) | best reasoning, 1 session | vLLM (pinned image + PLE overlay) / SGLang | **AWQ W4A16 + PLE INT4** (98/100 recipe) — bf16 dropped (R1) | bf16 | 173,400 (B1) | accuracy anchor; stays essentially B1 |
| `serving_fast_single` (S2) | fastest single | SGLang (hashd1ve recipe) / patched vLLM (madeye) | NVFP4 (nvidia/) + FP8 PLE on NVMe | fp8 | ≤262k native | GB10 single-stream ≈ 40–46 tok/s |
| `serving_concurrent_3_5` (S3) | 3–5 sessions | vLLM (madeye TP1 config: 6 slots) / SGLang | NVFP4 | fp8 | ≤262k | 100 tok/s aggregate @4 measured; mamba/seq-slot flags critical |
| `serving_longctx_512k` (S4) | max ctx, 1 session | SGLang or vLLM | NVFP4 (or AWQ if accuracy-gated) | fp8 | **524,288 via YaRN factor 2.0** | official recipe; madeye 500k demo exists; needle-gate mandatory |
| `serving_longctx_conc3_5` (S5) | max ctx × 3–5 sessions | SGLang (`--context-length` + `--max-total-tokens` pool semantics) | NVFP4 | fp8 | per-request ≤262k native + pool ≥3×(L/2) | SGLang pool semantics fit S5 better than vLLM's per-request max_model_len; new profile — needs its own A-cal + D cycle |
| `bench_awq_ple` (control) | = B1 verbatim | vLLM pinned image | AWQ+PLE | bf16 | 173,400 | unchanged |

Cross-profile requirements (all): PLE tables on the XFS NVMe mount (unified memory makes RAM-offload
pointless); needle-test at operating depth per profile (XQA corruption trap); `--max-num-seqs` set
explicitly (default 1024 aborts CUDA-graph capture); ptrace/seccomp check under DGX OS.

## 4. Proposed updated readiness table (summary.md §7 replacement — for review)

| Profile | Status | Missing |
|---|---|---|
| AWQ+PLE @173k (S1/control) | ✅ proven on x86 | GB10 re-validation of arm64 image + overlay paths (R4 digest now has digest+tags) |
| bf16 @any ctx (old S1) | ❌ **dropped** | n/a — doesn't fit 121.63 GiB (R1); dequantized-AWQ optional offline reference only |
| NVFP4 (S2/S3) | ✅ two published GB10 recipes | engine choice (SGLang vs patched vLLM); PLE-format support on GB10 loaders |
| 512k (S4) | ✅ official YaRN recipe + single-Spark demo | needle-gate + YaRN-factor choice (2.0 vs 4.0) at bench |
| 3–5 concurrent (S3/S5) | ⚠️ partial | S3 has measured data; S5 (long-ctx × concurrency) is new — needs config design + A-cal |
| TRT-LLM | ❌ not a candidate | n/a — no model path; documented future row (R6) |
| small-models runtime | ✅ unchanged | config templates unwritten (IaC port, out of research scope) |

## 5. Open items carried into bench prep (not research blockers)

1. Pin exact image(s) per engine at bench time: `vllm/vllm-openai@sha256:fc120ece…` (+ verify the
   arm64 manifest matches `…-arm64-cu130` tag); check `lmsysorg/sglang:qwen38flashnext` aarch64
   manifest; evaluate `timothystewart6/vllm-gb10` if published builds lack sm_121 kernels.
2. Verify #52708/#38484 merge state (SM121 in published vLLM build targets) — decides stock vs
   community image for the vLLM lanes.
3. Confirm the hashd1ve two patches (#36845 QSA varlen; NVMe PLE mmap) are inside the current
   cookbook image or must ship as file overlays (same mechanism as our PLE overlay — still "no
   building", but must be recorded in the IaC port if needed).
4. A-cal must measure KV/token for FP8 KV on GB10 directly (507,810-token pool datapoint exists but
   is config-dependent).
5. Downloads for prep phase: nvidia/Qwen3.8-Flash-Next-NVFP4 (+ FP8 PLE), wtdcode AWQ + ples_int4 —
   ~155 GB total, overnight.
6. HF model card default settings worth carrying into profiles: preserve_thinking ON (KV
   utilization), sampling temp 1.0 / top_p 0.95 / top_k 20 (already in B1).

## 6. Deliverables produced by this spike (all in spark/resources/)

- Digests: `R1-bf16-weights.md`, `R2-nvfp4.md`, `R3-context.md`, `R4-vllm-image-gb10.md`,
  `R5-sglang-gb10.md`, `R6-trtllm-gb10.md` (each with lane findings + parent-verification addendum)
- Captures: `R1-hf-model-card.md` (official card incl. YaRN recipe + config.json highlights),
  `R1-ple-quant-card-evidence.md`, `R1-nvfp4-shard-structure.md`, `R3-170k-192k-context-96GB.md`,
  `R3-sglang-460k-total-tokens-config.md`, `R4-dockerhub-registry.md` (raw registry JSON + digest),
  `R4-madeye-dgx-spark-vllm-nvfp4.md`, `R5-hashd1ve-dgx-spark-sglang.md`,
  `R5-sglang-flash-next-day0-image-dull-giraffe.md`, `R5-sglang-nvfp4-recipe-turbulent.md`,
  `R5-sglang-rtxpro6000-hicache-accuracy.md`
- No other repo files touched; no HD row created (per instruction).
