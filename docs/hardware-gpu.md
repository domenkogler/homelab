---
title: Shared GPU Resource
role: cross-cutting
domain: hardware
cross_cutting: true
status: active
tags: [hardware, gpu, rocm, cross-cutting]
---
# Shared GPU Resource

> **Role:** Cross-cutting detail — shared GPU resource across AI/vision (immich-ML), voice, and gaming. oldsrv RX 7600 = **pinned AI services (STT + embed) + Sunshine encode + immich-ML batch**; the **reranker is CPU** (decision #25, 2026-09-17; ⏳ **under re-decision #27, proposed 2026-09-18 on measured data — 0.50 s on-GPU vs 5.3 s on CPU at 425 MiB**, [services-ai-bench.md](services-ai-bench.md) §3); spark (GB10) is the separate **big-model generation tier** (decision #24, 2026-09-15).
> **Links to:** `services-office.md`, `smart-home-voice.md`, `services.md`
> **Linked from:** `hardware-oldsrv.md`, `hardware-spark.md`, `deployment-compose.md`

---

## Phase 1: AMD Radeon RX 7600 — Sunshine gaming encode + immich-ML batch inference (AI)

> **Corrected 2026-09-09 (owner), refined 2026-09-15 (decision #24):** the RX 7600 is **NOT "gaming
> encode only / no AI."** It serves (a) Sunshine game-streaming encode, (b) **immich-ML batch
> inference**, and (c) — **NEW 2026-09-15** — the **pinned AI services: Whisper STT + bge-m3 embed +
> bge-reranker** (container-bundled ROCm, ≈5–6 GB of 8 GB). **Amended 2026-09-17 (decision #25): the
> bge-reranker moved off the dGPU to CPU**, so pinned-AI is now ≈3–4 GB — see §Compute-preemption (CWSR)
> exposure and [services-ai.md](services-ai.md) §9c for the research. What is *excluded* from the dGPU is
> **host LLM inference and big-model generation**: Ollama is disabled on oldsrv and the large
> generation models run on **spark** (Triton, GB10 — HD-335). `amd_rocm` host userland stays
> Debian-trixie-native tooling only (no external AMD repo, HD-318).

| Spec | Value |
|------|-------|
| VRAM | 8 GB GDDR6 |
| Interface | PCIe 4.0 x8 |
| Docker access | `/dev/dri`, `/dev/kfd` |
| GPU workloads | **Pinned AI services (Whisper STT + bge-m3 embed — decision #24 + #25) + Sunshine gaming-encode + immich-ML batch inference (AI)** — container-bundled ROCm / GGML_HIP |
| Host GPU | Intel HD 630 (iGPU, desktop only) — Xorg primary |

### Compute-preemption (CWSR) exposure — gfx1102 (research 2026-09-17, decision #25)

> **Role:** why the *build target* of a GPU container is a safety property on this card, not a
> performance detail. Read before adding any long-running compute workload to the dGPU.

**CWSR = Compute Wavefront Save/Restore** — the KFD (`drivers/gpu/drm/amd/amdkfd/`) mechanism that
preempts *compute* work: VGPRs are saved into a reserved area on wavefront switch. The userspace
runtime (ROCr/thunk) historically **hard-coded that area's size**; when the kernel needs more, the
buffer is truncated and register state is corrupted on restore → `HW Exception by GPU node-N reason:
GPU Hang` — a **hard hang of the whole card**, not a container crash.

Why this card is in scope at all:

| Source (read 2026-09-17) | Finding |
|---|---|
| `linux/drivers/gpu/drm/amd/amdkfd/kfd_device.c:207` | `supports_cwsr = true` is set for the **entire SOC15 family — gfx1102 included** |
| `linux/drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c:758-765` | `int cwsr_enable = 1; module_param(cwsr_enable, int, 0444)` → **on by default**, changeable only via kernel cmdline (`amdgpu.cwsr_enable=0`) |
| `ROCm/rocm-systems` PR **#2200** (merged 2025-12-16) | userspace fix: read the CWSR/control-stack size from KFD instead of hard-coding it ("allow VGPR size to be determined dynamically") |
| `linux` commit `2b0386d` (`drm/amdkfd: fix 32-bit overflow in CWSR total size calculation`) | kernel-side `u32` → `u64` + `check_mul_overflow` on `total_cwsr_size` |
| `beecave-homelab/insanely-fast-whisper-rocm` issue **#61** | documents the symptom + affected set: **gfx1030/gfx1032 and gfx1151 confirmed; gfx1102 is NOT on the confirmed list** |

**Honest scope of the risk:** gfx1102 has **no confirmed hang report**. The exposure is inferred from
(a) CWSR being enabled for SOC15 and (b) images that force `HSA_OVERRIDE_GFX_VERSION=10.3.0`, i.e.
run gfx1030 code — the confirmed-affected family — on this card. Do not treat that as proof.

**Why the card is quiet today:** Sunshine uses the **VCE encode path (not KFD compute)**, immich-ML is
a short intermittent batch, and the host packages are `rocm-opencl-icd` + `rocminfo`
(`group_vars/home_servers.yml`) — none of them sustain compute long enough to trigger preemption.

**Mitigation (chosen 2026-09-17):** build for the **native `gfx1102` target so no HSA override is
needed** (`whisper.cpp` `-DAMDGPU_TARGETS=…gfx1102…`, ROCm 7.14/TheRock userspace which carries the
size fixes) instead of running gfx1030 code on top of an override. **`cwsr_enable=0` is deliberately
NOT set in advance** — it is a grub change + reboot, and the cost is silent compute-efficiency loss.
`amdgpu-dkms` is likewise **not** introduced: it would replace the in-tree `amdgpu` module that the
`amd_rocm` role and the working Sunshine path depend on (`roles/amd_rocm/tasks/main.yml`: “NO
amdgpu-dkms — the Debian kernel already supports the card”).

Pre-work check + burn-in (both non-destructive):

```bash
cat /sys/module/amdgpu/parameters/cwsr_enable      # expected: 1
dkms status | grep -i amdgpu                        # expected: empty (in-tree module)
# then: ~15 min sustained compute on the card while watching the kernel ring
journalctl -kf | grep -iE 'gpu|kfd|amdgpu|hws'
```

### CWSR / GPU consumers — what runs where (2026-09-17)

| Consumer | Runtime | GPU target | Why |
|---|---|---|---|
| `bge-m3` embed | Ollama `:rocm` · ⏳ **#27 proposed → `llama.cpp server-vulkan`** (same image as rerank) | container runtime (verified live) / **RADV Vulkan** | live + E2E-verified today, but measured **15 ms vs ~500 ms** per query chunk, **326 vs 899 MiB** VRAM, **157 MiB vs 2.19 GiB** RSS, and **cosine 0.9996 vs the live vectors** ⇒ no re-embed penalty ([services-ai-bench.md](services-ai-bench.md) §3b) |
| Whisper STT | **`whisper.cpp` GGML_HIP** · ⏳ **#27 proposed → `main-vulkan` digest-pin** (the HIP image is **not published**) | **native `gfx1102`** (HIP) / **RADV Vulkan** | no HSA override, no PyTorch runtime; **measured RSS 34 MiB**, 1.72 GiB VRAM, 0.40 s / 11 s WAV ([services-ai-bench.md](services-ai-bench.md) §2) |
| `bge-reranker-v2-m3` | **CPU** (TEI `cpu-1.9.4` INT8 or `llama.cpp` CPU) · ⏳ **#27 proposed → `llama.cpp server-vulkan` on this card** | — | #25 assumed “1.5 GB VRAM + a ROCm runtime” and **10–30 ms/pair**; measured: **425 MiB**, no ROCm, **0.50 s** vs **5.3 s CPU** for top-20 ([services-ai-bench.md](services-ai-bench.md) §3) |
| immich-ML | container ROCm | container runtime | existing AMD precedent in this house |
| Sunshine | VCE encode | — | not a KFD compute consumer |

### Dual GPU Topology

- **Intel HD 630 (iGPU):** Xorg primary — monitor on motherboard output. Family desktop compositing.
- **Radeon RX 7600 (dGPU):** No monitor. **Pinned AI services (Whisper STT + bge-m3 embed, decision
  #24; reranker → CPU per decision #25) + Sunshine game-streaming encode** + **immich-ML batch inference (AI)** — all pause-able
  GPU consumers (2026-09-06) whose containers bundle their own ROCm runtime and only need
  `/dev/dri`+`/dev/kfd`+udev. No **Ollama/LLM** on oldsrv (disabled 2026-09-07 — big-model generation on
  spark/Triton, HD-335). **Host ROCm = Debian-trixie-native tooling only** (`rocm-opencl-icd`/`rocminfo`/`hipcc`,
  no external AMD repo — HD-318 2026-09-07: the Ubuntu-noble AMD repo is incompatible with trixie).
- Xorg config fragment in `/etc/X11/xorg.conf.d/10-igpu-primary.conf` forces iGPU, excludes dGPU.

---

## Phase 2: NVIDIA GB10 Grace Blackwell (spark)

The old planned Phase 2 GPU (AMD Radeon AI PRO R9700 32 GB, Ryzen build) is **superseded** by the
NVIDIA **GB10 Grace Blackwell** superchip in the ThinkStation PGX (`hardware-spark.md`). Not a
discrete GPU — a unified CPU+GPU superchip with **128 GB shared LPDDR5x** memory (no separate VRAM
division) and **1 PFLOP FP4**.

| Spec | Value |
|------|-------|
| Superchip | NVIDIA GB10 Grace Blackwell (20-core Arm + Blackwell GPU) |
| Unified memory | **128 GB** LPDDR5x (shared CPU/GPU, 256-bit, 273 GB/s) |
| AI performance | **1000 TOPS · 1 PFLOP (FP4)** |
| Node | `spark.kogler.si` — ThinkStation PGX SFF |

---

## VRAM Management

> **Legacy note:** `OLLAMA_KEEP_ALIVE`/Ollama-era modes were removed (Ollama disabled on oldsrv
> 2026-09-07). Current dGPU consumers = Sunshine (gaming) + immich-ML (batch); LLM inference runs on
> spark (GB10).

### Phase 1 Modes (RX 7600, 8 GB)

| Mode | Active Models | VRAM Usage | Trigger |
|------|--------------|------------|---------|
| **Pinned AI (voice/embed)** | Whisper STT (~2 GB) + bge-m3 embed (~1–2 GB) — **reranker is CPU since decision #25 (2026-09-17)** | **~3–4 GB** (was ~5–6 GB with the reranker on-GPU) · **measured 2026-09-18: 2.9 GiB with all three legs on-GPU** (embed 0.82 + rerank 0.33 + STT 1.72), 5.26 GiB free — [services-ai-bench.md](services-ai-bench.md) §6 | Voice command / RAG ingest-query |
| **Immich-ML batch (AI)** | Immich-ML (face/object recognition, container ROCm) | ~3–5 GB | Photo/ML job — **lowest priority** |
| **Gaming** | None (Sunshine active) | 0 GB (pinned-AI + immich-ML paused) | User launches Sunshine (manual) |
| **Idle** | None | ~0 GB (GPU ~5 W) | No Sunshine stream, no pinned-AI, no immich-ML job |

### Phase 2 Modes (spark — GB10, 128 GB unified)

`spark` runs the **big-model generation tier** (decision #24, 2026-09-15) — the NVFP4 generation set
(see `hardware-spark.md`). With 128 GB unified memory there is no tight VRAM budget — models load
concurrently; model swapping is Triton/KeepAlive-driven, not a manual gaming preempt. The small
pinned services (STT/embed/rerank) moved to the oldsrv RX 7600 (decision #24).

> ⚠️ **2026-09-16 correction:** earlier wording here ("no tight VRAM budget — models load concurrently")
> is **wrong for vLLM today**. There IS a hard budget — but it is a **host-RAM budget**: on GB10 every GPU
> allocation is the same 121.62 GiB pool the OS runs in, and vLLM's `gpu_memory_utilization`
> replace-by-percentage arithmetic eats the host's reserve. Three global-OOM incidents in 24 h
> (2026-09-15 ×2, 2026-09-16 ×1; kernel killed the user session before the engine on the third).
> Budget mechanics, sizing table, incident log + diagnosis recipe: [hardware-spark.md](hardware-spark.md)
> **§Unified-memory budget & OOM governance**. Simply put: the *only* real governor of host headroom on
> this box is vLLM's `--kv-cache-memory-bytes` (or `gpu_memory_utilization` pre-HD-374); the container
> memory cage cannot protect the host (GPU pages are not cgroup-charged).

| Mode | Active Models | Memory (approx) | Trigger |
|---|---|---|---|
| **Programming / Coding** | Qwen3-Coder-Next-80B | ~50 GB (NVFP4) | Coding session |
| **Family Chat / RAG** | Nemotron-Lightning-30B or Llama-3.3-70B | ~15–40 GB | Chat / retrieval |
| **Idle** | None (Triton model swap / KeepAlive) | ~0–few GB | No activity |

---

## GPU Consumers

| Consumer | Domain | Doc |
|----------|--------|-----|
| ~~Ollama~~ | ~~LLM inference~~ — **removed from oldsrv** (disabled 2026-09-07; big-model generation on spark/Triton, HD-335) | [`services-ai.md`](services-ai.md) |
| Whisper STT | Voice (speech-to-text) — **oldsrv RX 7600** (decision #24, 2026-09-15) | [`smart-home-voice.md`](smart-home-voice.md) |
| Piper TTS | Voice (text-to-speech) — **CPU** (CPU-only engine, decision #24) | [`smart-home-voice.md`](smart-home-voice.md) |
| bge-m3 embed | RAG embeddings — **oldsrv RX 7600** (decision #24) | [`services-ai.md`](services-ai.md) |
| bge-reranker | RAG rerank — **CPU** (decision #25, 2026-09-17: off the dGPU — no Ollama rerank API, and 1.5 GB VRAM + a ROCm runtime buys nothing at 20 pairs) | [`services-ai.md`](services-ai.md) §9c |
| **Immich-ML** | **Photo face recognition / ML batch inference (AI)** — container-bundled ROCm, **lowest priority** | [`services.md`](services.md) |
| **Sunshine** | Game streaming (manual start) — gaming-encode | [`hardware-oldsrv.md`](hardware-oldsrv.md) |

> oldsrv RX 7600 GPU consumers = **pinned AI (STT + embed, decision #24 + #25) + Sunshine (gaming encode) + Immich-ML (AI batch, lowest priority)**; the **reranker moved to CPU** (decision #25). Spark (GB10) is the separate **big-model generation tier**.

---

## Priority Rules

- **Gaming-first (2026-09-06):** Sunshine owns the GPU for streams; pinned-AI + immich-ML batch run in
  free-GPU time. Sunshine prep-commands `docker pause/unpause` freeze/resume the AI consumers at
  stream start/end — **no lost work, instant resume** (kernel freeze).
- **Priority order (decision #24, amended by #25 2026-09-17):** gaming > pinned-AI (voice/embed) > immich-ML.
  With the reranker on CPU, pinned-AI is ≈3–4 GB, so **immich-ML (≈3–5 GB) can now co-reside** instead of
  being paused; pause-mechanism remains the guard if the two ever overlap near the 8 GB ceiling.
  ⚠️ This co-residency is **inference from the arithmetic, not live-verified** — confirm with `rocm-smi`
  during a concurrent voice + photo-JML job before relying on it (HD-385).
- Sunshine `restart: "no"` (manual-start); idle GPU ~5 W when neither gaming nor AI-active.
- `docker pause` frees compute instantly; VRAM stays allocated until the process re-runs
  (non-issue at 8 GB/5–6 GB pinned-AI footprint).
- No automated preemption beyond the pause-mechanism; CPU fallback for immich-ML only if
  ONNX-GPU proves fragile (not the default).

---

## Docker Device Mappings

```yaml
# For GPU-enabled containers (immich-ml, sunshine):
devices:
  - /dev/dri:/dev/dri
  - /dev/kfd:/dev/kfd
```

Udev rules set `/dev/kfd` mode 0666 and `/dev/dri/render*` mode 0666 for container access.