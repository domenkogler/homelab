# R4 — The pinned vLLM image and GB10/aarch64 support (HARD GATE)

Question ID: R4 · Question: Does `vllm/vllm-openai:qwen38-flash-next` exist, what digest/arch is it, which vLLM is it based on, does anything official support GB10 (sm_121, aarch64), and is the PLE overlay portable?
Date: 2026-09
**VERDICT: PARTIAL** — image existence and overlay mechanics are well-evidenced from local captures; the registry-level facts (digest, architecture list, vLLM base version) and the official GB10/DGX Spark support story could NOT be verified (no web/bash in this lane; supervisor confirmed local-only policy). Nothing found so far BLOCKS the bench plan, but the aarch64 question is open and is the single largest risk.

---

## Findings

1. **Claim:** The Docker Hub tag `vllm/vllm-openai:qwen38-flash-next` exists and is the canonical serving image for this model; it is used unchanged by at least three independent parties.
   **Sources:** primitive-ai PLE card serve section (https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant#serve, capture: `spark/resources/primitive-aiQwen3.8-Flash-Next-PLE.md`); u/UltrMgns k0s Deployment yaml, 2026-08-30 (https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/, capture: `spark/resources/Qwen3.8-Flash-Next at 170K context on a single 96 GB card 110 t-s.md`); u/WonderRico full docker run, 2026-09-04 (https://www.reddit.com/r/LocalLLaMA/comments/1w7c4ej/, capture: `spark/resources/vLLM based recipe for Qwen 3.8 Flash Next now up to 98-100.md`).
   **Support:** direct evidence (three independent runnable configs all pull the same tag; two mount overlay files into its internal paths).
   **Confidence:** high (existence); the DIGEST, architecture list (amd64 vs aarch64), and exact last-updated date are **[unverified — registry API not reachable from this lane]**.

2. **Claim:** The image last changed on or before 2026-09-03.
   **Sources:** primitive-ai PLE card Notes: "The current image (unchanged as of 2026-09-03) predates a fix for a startup race in the PLE offload path".
   **Support:** direct evidence (the card tracks the image and states it was unchanged as of that date).
   **Confidence:** high for "≤ 2026-09-03"; exact build date and whether it changed after 2026-09-03 **[unverified]**.

3. **Claim:** The image is a model-specific vLLM build carrying a vendored model tree at `vllm/models/qwen3_8_flash_next/nvidia/` (contains `ple_layer.py`), and the image's stock PLE offload worker does NOT support quantized tables (rejects `ngram_embedding.weight_scale`).
   **Sources:** primitive-ai PLE card (Notes + Format + Serve sections), local capture.
   **Support:** direct evidence for the vendored path and the stock-worker rejection.
   **Confidence:** high. Researcher inference: a tag named `qwen38-flash-next` on vllm/vllm-openai is a day-0 model-specific snapshot (SGLang has the exact analog: `lmsysorg/sglang:qwen38flashnext`, "day-0 preview tag (pushed 2026-08-26, branch qwen4-main-squashed)" carrying "still-unmerged model support from #36497", per u/Dull-Giraffe in the 170K-context thread) — so the vLLM base is likely a pre-release branch, not a stable release. Exact base version/tag: **[unverified]**.

4. **Claim:** PR/issue status as of the PLE card's last update (≤ 2026-09-06):
   - vllm-project/vllm#53960 (boot hang after CUDA graph capture, looping `No available shared memory broadcast block`): fixed 2026-08-29 **in the offload PR branch #53899**, described as "still unmerged". The image predates the fix; the card ships the fixed file as `connector_mrv2.py` to mount over `.../vllm/v1/ple_offload/connector.py`.
   - vllm-project/vllm#53899 (PLE offload PR): branch loads FP8 and NVFP4 **global-scale** tables since 2026-08-30; merge-into-release status unverified.
   - vllm-project/vllm#54070 (BF16-table disk path, no model-file hook): merge status **[unverified]**.
   - vllm-project/vllm#54129 (memory-maps FP8 table out of checkpoint shards): described as working "at one scale per table"; merge status **[unverified]**.
   **Sources:** primitive-ai PLE card Notes section, local capture (links therein to github.com/vllm-project/vllm PRs/issues).
   **Support:** direct evidence from the card author, who reproduces the failures on their own box.
   **Confidence:** high for what the card states (≤ 2026-09-06); current merge state needs a live check.

5. **Claim:** The PLE overlay is tied to this image's exact filesystem layout: `worker_image_quant.py` → `/usr/local/lib/python3.12/dist-packages/vllm/v1/ple_offload/worker.py` and `ple_layer_quant.py` → `/usr/local/lib/python3.12/dist-packages/vllm/models/qwen3_8_flash_next/nvidia/ple_layer.py` (optional third mount: `connector_mrv2.py` → `.../vllm/v1/ple_offload/connector.py`).
   **Sources:** primitive-ai PLE card: "The overlay targets this exact image; the gather hook lives in a vendored model file (`vllm/models/qwen3_8_flash_next/nvidia/ple_layer.py`), which is why this ships as an overlay rather than a vLLM PR."
   **Support:** direct evidence.
   **Confidence:** high. **Portability caveat (researcher inference):** the overlay works in any image with (a) the same python3.12/dist-packages layout, (b) the same vendored `qwen3_8_flash_next/nvidia/` model tree, and (c) surrounding code compatible with the overlaid files' expectations (file contents are replaced wholesale). Any future official vLLM release that restructures the ple_offload package or renames the model module will break the mounts. Treat the recipe as pinned-to-this-image-digest until a merged upstream path (#54070/#54129) exists.

6. **Claim:** GB10 / DGX Spark (sm_121) official vLLM support: **NO local evidence.** Nothing in the five captures mentions sm_121, DGX Spark docs, NGC containers, or aarch64.
   **Support:** absence of evidence in local captures only.
   **Confidence:** n/a — **[unverified]**. What local captures DO show: every community data point is x86_64 (Threadripper air-cooled, Ryzen 9 9900X, Intel desktop, EPYC 7742 hosts); quantized PLE overlay dequantizes gathered rows on CPU (~100–200 KB/token); kernels in play are triton/flashinfer/cutlass (NVFP4 MoE via FLASHINFER_CUTLASS / Humming backends). Two Spark-named artifacts exist but both require source patches → **NOT candidates** under the build-from-source rule: `edougawa/Qwen3.8-Flash-Next-W4A16-PLE4-MTP-Spark` ("needs their vLLM patch") and HamboneLabs `Qwen3.8-Flash-Next-uint3-g64` ("their patch set") — per the primitive-ai card. Whether either ships prebuilt wheels/images: **[unverified]**.

7. **Claim:** Operational envelope of the image+overlay recipe, measured on one RTX PRO 6000 Blackwell 96 GB (relevant for sizing on 128 GB unified GB10):
   - Defaults trap: image default `--max-num-seqs` 1024 exceeds available Mamba state blocks at 0.92 gpu-mem-util (598) → CUDA graph capture aborts; set `--max-num-seqs` explicitly.
   - KV budget trap: at native 262,144 ctx + MTP, KV needs 7.57 GiB where only 5.95 GiB remains after the draft head (96 GB card); measured configs used 32,768/36, 135,168/64, or 173,400.
   - Whole recipe validated inside a 48 GB container cgroup (INT4 table): 80.5 tool-calling, 79.4 tok/s @1, 486 @32 — a 128 GB GB10 pool is not the constraint; bandwidth (273 GB/s LPDDR5x) is.
   - Env vars: `VLLM_PLE_CPU_OFFLOAD=1`, `VLLM_PLE_QUANT_DIR=/ples_int4`, `VLLM_PLE_OFFLOAD_READY_TIMEOUT`; `VLLM_GDN_DECODE_KERNEL=triton` needed for the mixed NVFP4/FP8 checkpoint, drop for plain NVFP4.
   - Host security caveat: offload worker + GPU worker exchange a CUDA IPC fd via `pidfd_getfd(2)`; hangs after graph capture if seccomp denies it or Yama `ptrace_scope=1` (bare-metal default) → `--cap-add=SYS_PTRACE` (docker) or `sysctl kernel.yama.ptrace_scope=0`; u/WonderRico's working docker run indeed carries `--cap-add SYS_PTRACE --security-opt seccomp=unconfined`.
   - CPU cost: the offload worker keeps three cores in a busy loop (95 °C on an air-cooled Threadripper until capped at 4.5 GHz) — relevant to the 20-core Arm GB10 thermal envelope.
   **Sources:** primitive-ai PLE card (Measured/Notes) and u/WonderRico command, local captures.
   **Support:** direct evidence.
   **Confidence:** high for x86_64 hosts; **aarch64 behavior of every kernel involved (triton GDN decode, INT4 dequant gather, MTP) is [unverified]**.

## Bench plan implications

- Everything in the vLLM lane hinges on one artifact: the pinned image. First provisioning step must be the registry inspection (commands below): if the tag is amd64-only, the ENTIRE vLLM+overlay recipe is dead on GB10 and the fallback ladder is (1) NVIDIA's official DGX Spark vLLM path (docs.nvidia.com / NGC aarch64 image) + merged upstream PLE path (#54070/#54129) if it exists, (2) SGLang lane (`lmsysorg/sglang:qwen38flashnext` — same aarch64 question), (3) llama.cpp/ik_llama (works but ~5x slower decode per community).
- If the image IS multi-arch: pin by digest, mount the three overlay files, and expect the ptrace/seccomp + max-num-seqs + KV-budget traps; on GB10 the 48 GB-container validation and 5.95 GiB-KV numbers both relax, so 262k context + MTP becomes plausible, gated by unified-memory bandwidth, not capacity.
- The 98/100-accuracy vLLM recipe (AWQ W4A16 + PLE INT4 overlay + MTP3) is the accuracy champion; the NVFP4+plain-image path is the throughput one. Both share the same pinned image, so the aarch64 answer covers both.

## Open gaps for parent verification (web-dependent, [unverified])

1. Registry manifest for `vllm/vllm-openai:qwen38-flash-next` — pin digest (sha256), architecture list (amd64/aarch64?), last-updated. Commands (needs network):
   `curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:vllm/vllm-openai:pull"` → TOKEN;
   `curl -s -H "Authorization: Bearer $TOKEN" https://registry-1.docker.io/v2/vllm/vllm-openai/tags/list`;
   `curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json" https://registry-1.docker.io/v2/vllm/vllm-openai/manifests/qwen38-flash-next`
2. vLLM base version of the image (inspect image labels / release notes); current merge state of #53899, #54070, #54129, #53960 into a tagged release.
3. Official DGX Spark inference-framework support list (docs.nvidia.com DGX Spark docs) and NGC catalog: is there an official aarch64/sm_121 vLLM container? Does official vLLM (any release) ship sm_121 + aarch64?
4. Whether edougawa/HamboneLabs Spark packages ship prebuilt artifacts (would upgrade them from NOT-a-candidate).
5. Whether the pidfd_getfd/seccomp caveat applies under DGX OS defaults, and aarch64 performance of the triton GDN-decode + INT4-dequant path.

## Sources

- Kept: primitive-ai/Qwen3.8-Flash-Next-PLE-quant model card (https://huggingface.co/primitive-ai/Qwen3.8-Flash-Next-PLE-quant) — primary source for image targeting, overlay paths, PR/issue status, measured numbers; already captured locally as `primitive-aiQwen3.8-Flash-Next-PLE.md` (reuse it as the R4 primary capture; do not duplicate).
- Kept: r/LocalLLaMA "Qwen3.8-Flash-Next at 170K context..." (https://www.reddit.com/r/LocalLLaMA/comments/1w2b2j0/) — decisive community config (k0s yaml) pinning the image; captured locally.
- Kept: r/LocalLLaMA "vLLM based recipe ... 98-100" (https://www.reddit.com/r/LocalLLaMA/comments/1w7c4ej/) — full docker run command incl. security caps; captured locally.
- Deprioritized: fastest-setup thread and Templates-Comparison thread — no R4-relevant image facts beyond SGLang-image existence; kept in shared context only.
- Not capturable this run: Docker Hub registry JSON, GitHub PR pages, docs.nvidia.com DGX Spark docs, NGC catalog — no web access in lane.


---

## Parent verification addendum (2026-09-13, parent lane with web/registry access)

**Registry — VERIFIED (see R4-dockerhub-registry.md for raw JSON):**
- Tag `vllm/vllm-openai:qwen38-flash-next` EXISTS on Docker Hub. Manifest-list digest to pin:
  **sha256:fc120ece0a388cc0aa1caad4a9f1cd92113484ab7ec2fd0efadd62585be05bf8**
- **Multi-arch: arm64 AND amd64 variants present** (arm64 = sha256:3b0e188ffceb..., amd64 = sha256:0aea30240f3e...).
  → The "single largest risk" (amd64-only image) is RESOLVED: the image is pullable on GB10/aarch64.
- Explicit arch/CUDA tags also published: `qwen38-flash-next-arm64-cu129`, `qwen38-flash-next-arm64-cu130`,
  `qwen38-flash-next-x86_64-cu129`, `qwen38-flash-next-x86_64-cu130` → DGX Spark (CUDA 13) candidate
  tag: `qwen38-flash-next-arm64-cu130` (or the multi-arch tag, which resolves to arm64 on the host).

**vLLM sm_121 upstream status (search evidence, 2026-09-13):**
- PR #31740 "Add SM121/GB10 Blackwell-class GPU support" — still OPEN (created 2026-01-05).
- PR #38484 "Add SM121 to published build targets" — still OPEN. PR #52708 (same goal, 2026-08-18)
  shows a merge commit in search metadata but state is ambiguous — verify at bench time.
- Issue #50925: **NVFP4 MoE falls back to Marlin on sm_121 in published builds** → on the unified
  121.63 GiB pool the expansion makes the model unservable; building from source with CUTLASS path
  fixes it (out of scope for us — no building). ⇒ **vLLM + NVFP4 on GB10 via published images is
  NOT a clean candidate.**
- NVIDIA developer forum (Run VLLM in Spark thread): upstream wheels gaining DGX Spark fixes;
  "FP4 support is not there yet for vLLM on GB10 — better performance using AWQ quants."
- Community reproducible image: timothystewart6/vllm-gb10 (pinned-by-digest, linux/arm64,
  TORCH_CUDA_ARCH_LIST=12.1a) — a prebuilt alternative, no building required (pull only).

**vLLM serving THIS model on GB10 — VERIFIED working (see R4-madeye-dgx-spark-vllm-nvfp4.md):**
- madeye: single Spark TP1, NVIDIA NVFP4 checkpoint, patched vLLM nightly 8a728663, staged NVMe
  PLE, FP8 KV, 262k ctx, MTP3 → 36.8 prose / 45.8 code tok/s single, 100.2 tok/s aggregate @4,
  prefill 1.6–1.8k tok/s, KV pool 507,810 tokens. NOTE: uses patched image + NVMe-staged PLE —
  closest published single-Spark vLLM recipe; requires the same class of file-overlay mounts our
  PLE recipe already uses (community recipe, not source build).

**Revised R4 verdict: GREEN for aarch64 pull-ability of the pinned image (digest above); PARTIAL→
GREEN-leaning for vLLM-on-GB10 viability overall (two independent published recipes: SGLang-based
hashd1ve, vLLM-based madeye+tonyd2wild), with the standing caveat that published vLLM builds have
the NVFP4-Marlin fallback trap on sm_121 (#50925) — AWQ W4A16 + PLE INT4 overlay remains the
accuracy champion and the better-supported vLLM quant on GB10.**

## Remaining open items for bench time
1. Verify #52708/#38484 merge state and whether a NEWER vllm/vllm-openai build (or the arm64-cu130
   tag) contains SM121 cubins; else use timothystewart6/vllm-gb10 or madeye's pinned nightly.
2. Confirm pidfd_getfd/seccomp behavior under DGX OS docker defaults (--cap-add=SYS_PTRACE fallback).
3. Read the arm64 image labels for the vLLM base version at pull time (skopeo inspect --config).
