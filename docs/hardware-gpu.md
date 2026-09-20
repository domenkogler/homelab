---
title: Shared GPU Resource
role: cross-cutting
domain: hardware
cross_cutting: true
status: active
tags: [hardware, gpu, rocm, cross-cutting]
---
# Shared GPU Resource

> **Role:** Cross-cutting detail — the shared GPU resource across AI/vision (immich-ML), voice and gaming.
> **oldsrv RX 7600** = pinned AI services (STT + embed + rerank) + Sunshine encode + immich-ML batch.
> **spark (GB10)** is the separate big-model generation tier; vision judgment lives on the
> **workstation**. Per-model placement is the plan of record in [`services-ai.md`](services-ai.md) §9;
> measured numbers in [`services-ai-bench.md`](services-ai-bench.md).
> **Links to:** `services-ai.md`, `services-ai-bench.md`, `smart-home-voice.md`, `hardware-workstation.md`
> **Linked from:** `hardware-oldsrv.md`, `hardware-spark.md`, `deployment-compose.md`

---

## oldsrv — AMD Radeon RX 7600 (8 GB)

The card is a **real AI consumer**, not "gaming encode only". Three workload classes share it:

1. **Pinned AI services** — Whisper STT + bge-m3 embed + bge-reranker, all on **Vulkan**
   (`llama.cpp server-vulkan` for embed+rerank, `whisper.cpp main-vulkan` for STT).
   **Measured 2475 MiB (2.4 GiB) with all three legs warm.**
2. **Sunshine game-streaming encode** (VCE path, not KFD compute).
3. **immich-ML batch inference** — container-bundled ROCm, **lowest priority**.

Excluded from this card by decision: **host LLM inference / big-model generation** (that is spark) and
**any vision-LLM leg** (that is the workstation — §Vision-LLM leg below).
Host ROCm stays **Debian-trixie-native tooling only** (`rocm-opencl-icd` / `rocminfo` / `hipcc`, no external
AMD repo — the Ubuntu-noble AMD repo is incompatible with trixie).

| Spec | Value |
|------|-------|
| VRAM | 8 GB GDDR6 (~276 GB/s) |
| Interface | PCIe 4.0 x8 |
| Docker access | `/dev/dri`, `/dev/kfd` |
| Render node | **`/dev/dri/renderD129` = the dGPU** (`renderD128` is the HD 630 iGPU) |
| Host GPU | Intel HD 630 (iGPU, desktop only) — Xorg primary |

### Compute-preemption (CWSR) exposure — gfx1102

> **Why this matters:** on this card the *build target* of a GPU container is a **safety** property, not a
> performance detail. Read this before adding any long-running compute workload to the dGPU.

**CWSR = Compute Wavefront Save/Restore** — the KFD (`drivers/gpu/drm/amd/amdkfd/`) mechanism that preempts
*compute* work: VGPRs are saved into a reserved area on wavefront switch. The userspace runtime
(ROCr/thunk) historically **hard-coded that area's size**; when the kernel needs more, the buffer is
truncated and register state is corrupted on restore → `HW Exception by GPU node-N reason: GPU Hang` —
a **hard hang of the whole card**, not a container crash.

Why this card is in scope:

| Source | Finding |
|---|---|
| `linux/…/amdkfd/kfd_device.c` | `supports_cwsr = true` is set for the **entire SOC15 family — gfx1102 included** |
| `linux/…/amdgpu/amdgpu_drv.c` | `int cwsr_enable = 1; module_param(…, 0444)` → **on by default**, changeable only via kernel cmdline (`amdgpu.cwsr_enable=0`) |
| `ROCm/rocm-systems` PR #2200 | userspace fix: read the CWSR/control-stack size from KFD instead of hard-coding it |
| `linux` commit `2b0386d` | kernel-side `u32` → `u64` + `check_mul_overflow` on `total_cwsr_size` |
| `beecave-homelab/insanely-fast-whisper-rocm` #61 | symptom + affected set: gfx1030/gfx1032 and gfx1151 confirmed; **gfx1102 is NOT on the confirmed list** |

**Honest scope of the risk:** gfx1102 has **no confirmed hang report**. The exposure is inferred from (a)
CWSR being enabled for SOC15 and (b) images that force `HSA_OVERRIDE_GFX_VERSION=10.3.0`, i.e. run
**gfx1030 code** — the confirmed-affected family — on this card. Do not treat that as proof.

**Why the card is quiet today:** Sunshine uses the VCE encode path (not KFD compute), immich-ML is a short
intermittent batch, and the host packages are `rocm-opencl-icd` + `rocminfo` — none sustain compute long
enough to trigger preemption. The pinned-AI legs run on **Vulkan (RADV)**, which does not use the KFD
compute path at all.

**Chosen posture:**
- Build/run for the **native `gfx1102` target so no HSA override is needed**; prefer images that carry the
  userspace size fixes. Running gfx1030 code under an override is the pattern that creates the exposure.
- **`cwsr_enable=0` is deliberately NOT set in advance** — it is a grub change + reboot, and the cost is
  silent compute-efficiency loss.
- **No `amdgpu-dkms`**: it would replace the in-tree `amdgpu` module that the `amd_rocm` role and the
  working Sunshine path depend on (`roles/amd_rocm/tasks/main.yml`: "NO amdgpu-dkms — the Debian kernel
  already supports the card").

Pre-work check + burn-in (both non-destructive):

```bash
cat /sys/module/amdgpu/parameters/cwsr_enable      # expected: 1
dkms status | grep -i amdgpu                        # expected: empty (in-tree module)
# then: ~15 min sustained compute on the card while watching the kernel ring
journalctl -kf | grep -iE 'gpu|kfd|amdgpu|hws'
```

### GPU consumers on this card

| Consumer | Runtime | GPU path | Note |
|---|---|---|---|
| `bge-m3` embed | `llama.cpp server-vulkan` (Q8_0 GGUF) | **RADV Vulkan** | ~0.33 GiB, and it holds **no `/dev/kfd`** — the ROCm `:rocm` runtime now belongs only to the retained ollama embed-fallback and immich-ML |
| `bge-reranker-v2-m3` | `llama.cpp server-vulkan` (same image) | **RADV Vulkan** | ~0.42 GiB; measured 0.34–0.50 s on-GPU vs **5.3 s on CPU** for a 20-doc Slovenian rerank |
| Whisper STT | `whisper.cpp main-vulkan` | **RADV Vulkan** | ~1.72 GiB VRAM / 34 MiB RSS; **no published ROCm/HIP artifact exists**, so HIP would be a self-build with no Renovate trail |
| immich-ML | container-bundled ROCm | KFD compute | existing AMD precedent; shortest, lowest-priority consumer |
| Sunshine | VCE encode | not compute | game streaming |

### Dual GPU Topology

- **Intel HD 630 (iGPU):** Xorg primary — monitor on the motherboard output, family desktop compositing,
  and the **Jellyfin QSV transcoder**. It is also why the iGPU is not an AI device
  ([services-ai-bench.md](services-ai-bench.md) §4: slower than CPU, and it *is* host RAM).
- **Radeon RX 7600 (dGPU):** no monitor; consumers as above. Containers need only
  `/dev/dri`+`/dev/kfd`+udev; the AI containers bundle their own runtime.
- Xorg config fragment `/etc/X11/xorg.conf.d/10-igpu-primary.conf` forces the iGPU and excludes the dGPU.

### Vision-LLM leg: none — this card gets no vision model (decision #28)

The card **stays without a vision-LLM leg**, and it is not a cost/perf call — the VRAM ledger is
arithmetically closed: pinned tier **2.4 GiB** + a Qwen3-VL 2B/4B (~3–4.5 GiB) + immich-ML (3–5 GiB) =
**8.4–11.9 GiB > 8 GiB**. Vision for judgment lives on the workstation
([`hardware-workstation.md`](hardware-workstation.md)); decision **#28** in
[`services-ai.md`](services-ai.md) §9, deferral logged in
[`services-rejected.md`](services-rejected.md).

⚠ **Two traps that make "just run it on demand" harder than it looks** (both measured):

1. **`docker pause` does NOT free VRAM** — it frees *compute* only; the allocation stays held until the
   process re-runs. The on-demand mechanism is llama.cpp's **`--sleep-idle-seconds`** (PR #18228) or
   stopping the container — and it costs a reload on the next request (the STT leg's cold/warm delta,
   0.85 s vs 0.40 s, is the scale; a 3–4 GB model from NVMe is seconds).
2. **No arbiter exists.** Two on-demand consumers on one card with no scheduler means both can load, and
   the `amdgpu` VRAM OOM is not graceful. An arbiter/priority policy is a prerequisite, not a nicety.

**Revisit gates (both must be measured first, bench-doc style):** (a) does the pinned `server-vulkan`
image run a **Qwen3-VL `mmproj` vision tower on Vulkan** or fall back to CPU; (b) does
`--sleep-idle-seconds` **actually return VRAM on `gfx1102`** (sysfs `mem_info_vram_used`) and what is the
reload latency. A third ceiling: ~276 GB/s puts a 4B VL at ~6–9 s to read a screenshot — fine for
*reading*, not for an interactive loop.

---

## spark — NVIDIA GB10 Grace Blackwell (128 GB unified)

The old planned Phase-2 GPU (AMD Radeon AI PRO R9700 32 GB in a Ryzen build) is **superseded**
([deployment-rejected.md](deployment-rejected.md)). GB10 is not a discrete GPU — it is a unified CPU+GPU
superchip with **128 GB shared LPDDR5x** (no separate VRAM division) and **1 PFLOP FP4**.

| Spec | Value |
|------|-------|
| Superchip | NVIDIA GB10 Grace Blackwell (20-core Arm + Blackwell GPU) |
| Unified memory | **128 GB** LPDDR5x (shared CPU/GPU, 256-bit, 273 GB/s) — usable pool **121.62 GiB** |
| AI performance | **1000 TOPS · 1 PFLOP (FP4)** |
| Node | `spark.kogler.si` — ThinkStation PGX SFF |

> ⚠️ **There IS a hard memory budget on GB10 — it is a HOST-RAM budget.** Every GPU allocation is the same
> 121.62 GiB pool the OS runs in, so a percentage-style GPU budget silently eats the host's reserve, and
> **the container memory cage cannot protect the host** (GPU pages are not cgroup-charged). The only real
> governor is vLLM's explicit `--kv-cache-memory-bytes`. Mechanics, sizing table, metric definition and
> incident history: [hardware-spark.md](hardware-spark.md) **§Unified-memory budget & OOM governance** +
> [spark-incidents.md](spark-incidents.md). Do not treat "128 GB unified" as "no budget".

Serving profiles and the current engine are in
[hardware-spark.md](hardware-spark.md) §Bench + engine selection; model placement is
[services-ai.md](services-ai.md) §9.

---

## VRAM / memory modes

### oldsrv RX 7600 (8 GB)

| Mode | Active | GPU usage | Trigger |
|------|--------------|------------|---------|
| **Pinned AI tier** (embed + rerank + voice STT) | `llama.cpp server-vulkan` (embed + rerank, Q8_0 GGUFs) + `whisper.cpp main-vulkan` (STT) | **2475 MiB measured with all three legs warm** (≈0.33 + ≈0.42 + ≈1.72) → ~5.5 GiB free | Voice command / RAG ingest-query |
| **immich-ML batch** | Immich-ML (face/object recognition, container ROCm) | ~3–5 GB | Photo/ML job — **lowest priority** |
| **Gaming** | None (Sunshine active) | pinned-AI + immich-ML paused | User launches Sunshine (manual) |
| **Idle** | None | ~0 GB (GPU ~5 W) | — |

### spark (GB10)

Big-model generation with a **certified 16 GiB KV pool** and a bounded peak; concurrency and context are
governed by the explicit KV pool, not by "load everything". See
[hardware-spark.md](hardware-spark.md) §Unified-memory budget & OOM governance.

---

## GPU Consumers (cross-domain index)

| Consumer | Domain | Where | Doc |
|----------|--------|-------|-----|
| Whisper STT | Voice (speech-to-text) | oldsrv RX 7600 (Vulkan) | [`smart-home-voice.md`](smart-home-voice.md) |
| Piper TTS | Voice (text-to-speech) | **CPU** (CPU-only engine) | [`smart-home-voice.md`](smart-home-voice.md) |
| bge-m3 embed | RAG embeddings | oldsrv RX 7600 (Vulkan) | [`services-ai.md`](services-ai.md) |
| bge-reranker | RAG rerank | oldsrv RX 7600 (Vulkan) | [`services-ai.md`](services-ai.md) §9c |
| Big-model generation (`spark/qwen3.8-flash-next`) | Family chat / agents | **spark** | [`services-ai.md`](services-ai.md), [`hardware-spark.md`](hardware-spark.md) |
| FIM autocomplete + visual judgment | Workstation-local inference | **workstation** | [`hardware-workstation.md`](hardware-workstation.md) |
| **Immich-ML** | Photo face recognition / ML batch | oldsrv RX 7600, **lowest priority** | [`services.md`](services.md) |
| **Sunshine** | Game streaming (manual start) | oldsrv RX 7600 | [`hardware-oldsrv.md`](hardware-oldsrv.md) |

---

## Priority Rules

- **Gaming-first:** Sunshine owns the GPU for streams; pinned-AI + immich-ML run in free GPU time. Sunshine
  prep-commands `docker pause`/`unpause` freeze/resume the AI consumers at stream start/end — no lost work,
  instant resume (kernel freeze). ⚠ `pause` frees **compute**, not VRAM.
- **Priority order:** gaming > pinned-AI (voice/embed/rerank) > immich-ML.
  At 2.4 GiB of pinned AI, immich-ML (~3–5 GB) has room for real co-residency (~5.5 GiB free).
  ⚠ That co-residency is **arithmetic, not live-verified** — confirm with `rocm-smi` during a concurrent
  voice + photo-ML job before relying on it.
- Sunshine `restart: "no"` (manual start); idle GPU ~5 W.
- No automated preemption beyond the pause mechanism; CPU fallback for immich-ML only if its GPU path proves
  fragile (not the default).

---

## Docker Device Mappings

```yaml
# For GPU-enabled containers (immich-ml, sunshine):
devices:
  - /dev/dri:/dev/dri
  - /dev/kfd:/dev/kfd
```

Udev rules set `/dev/kfd` mode 0666 and `/dev/dri/render*` mode 0666 for container access.

### Group IDs on oldsrv — verified on the host

| Fact | Measured |
|---|---|
| `render` group | **gid 992** (`render:x:992:ansible-admin`) — **NOT** the Debian-table 104 |
| gid 104 | **`ssl-cert`** — which is what `gpu_render_gid` used to add to every GPU container |
| `video` group | gid 44 (matches the Debian static allocation) |
| `getfacl /dev/dri/renderD129` | `user::rw- group::rw- other::rw-` + a `user:lightdm:rw-` ACL |

`gpu_render_gid: 104` came from the Debian table ("render:104 since bullseye"), but on this machine that gid
belongs to **ssl-cert**, so every GPU container was granted the ssl-cert group while *not* being granted
render. Nothing broke only because the udev rules make the render nodes world-rw — **the wrong gid was
masked by mode 0666, not harmless.** It is `992` (measured) now. The Vulkan tier is the first consumer that
cares about naming the render node deliberately: `gpu_vulkan_render_node: /dev/dri/renderD129` (dGPU only —
`renderD128` is the HD 630 iGPU: the desktop's Xorg device, the Jellyfin QSV transcoder, and measured slower
than CPU for AI work). If a future host needs a different gid, make it a **host var** — never re-guess a
distribution default.
