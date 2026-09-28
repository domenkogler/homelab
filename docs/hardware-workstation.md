---
title: Workstation — admin laptop (AMD Strix Point, Radeon 890M) as the client-side inference tier
role: detail
domain: hardware
status: active
tags: [hardware, ai, workstation, strix-point, fim, vision, gpu]
---
# Workstation — admin laptop (AMD Strix Point)

> **Role:** Detail — the **admin workstation (laptop)** and its role in the AI tier: the two model legs that
> must run **locally** (FIM autocomplete + visual judgment), why the vision hand-off to spark is a
> **cascade** and not token-level split inference, and why the **NPU stays out** of the AI tier. Owning doc
> for the *placement* decision of these two legs; the pi.dev harness's model config stays in
> [`pi-harness.md`](pi-harness.md), spark's engine config in [`hardware-spark.md`](hardware-spark.md).
> **Links to:** `hardware-gpu.md`, `hardware-spark.md`, `services-ai.md`, `pi-harness.md`, `network-vpn.md`
> (laptop alias contract), [`../todo.md`](../todo.md) (HD-401)
> **Linked from:** `hardware.md`, `index.md`

> ⚠ **Evidence status (2026-09-20 → corrected 2026-09-27):** the platform block is now **measured on-device**
> (Windows CIM queries driven from the WSL seat). The correction is not cosmetic — this box is **not** the
> Strix Halo / 128 GB / ~256 GB/s machine this doc was written against, and both legs' placement rationale had
> inherited those three numbers. The A3B-over-dense rationale survives; the *speed* figures do not: every `t/s`
> quoted below is a 256 GB/s-class, 40-CU community measurement, still unverified here. Same discipline as
> [`services-ai-bench.md`](services-ai-bench.md): measure before any of it becomes config.

## Platform (measured on-device 2026-09-27)

| Item | Value |
|---|---|
| SoC | AMD **Ryzen AI 9 HX PRO 370 w/ Radeon 890M** — Strix **Point**, 12 C / 24 T. iGPU **Radeon 890M**, RDNA 3.5, PCI `VEN_1002&DEV_150E`. ⚠ **Not** the Strix Halo `Ryzen AI MAX+ 395` / `Radeon 8060S` recorded here until 2026-09-27: different product, roughly a third of the memory bandwidth and ~40 % of the compute units |
| LLVM target | **unconfirmed.** AMD's support matrix lists `gfx1150` and `gfx1151` together with no per-APU mapping, and the `gfx1151` recorded here was inherited from the wrong SoC. Confirm on-device (`rocminfo`, or the llama.cpp build log) before it drives a build or a driver pin |
| Memory | **64.0 GB** — 2 × 32 GB **DDR5-5600 SODIMM** (`FormFactor=12`, `TotalWidth=DataWidth=64`, `ConfiguredClockSpeed=5600`) ⇒ dual-channel 128-bit ⇒ **≈89.6 GB/s peak** (~2.9× below the 256 GB/s previously claimed, and **not** the soldered LPDDR5x / 256-bit fabric those figures came from) |
| Memory visible | **55.6 GB to Windows** (⇒ ≈8.4 GB firmware/BIOS reserved — not a 32 GB carve-out); WSL2 guest `MemTotal` **27.2 GiB** (undocumented 50 % default; `.wslconfig` carries only `networkingMode=Nat`); host free at idle **30.4 GB** with `vmmemWSL` at **2.72 GB** |
| Driver | `32.0.22024.19001`, one video controller. WMI `AdapterRAM` reads 4 GiB because the property is **capped at 4 GiB** — it is not a VRAM reading, do not quote it |
| NPU | XDNA2 (Ryzen AI) — **explicitly not used** (§NPU: out of the AI tier) |
| OS | **Windows 11 Pro** + **WSL2** (kernel `6.6.114.1-microsoft-standard-WSL2`, Debian 13 guest). The SSH alias contract for both `~/.ssh/config` files lives in [`network-vpn.md`](network-vpn.md) §The laptop alias contract |
| GPU access from WSL | **None usable.** `/dev/dxg` is present but there is **no `/dev/dri` and no `/dev/kfd`**, and no Vulkan ICD is installed in the guest — so no native Vulkan and no native ROCm. Docker-in-WSL inherits exactly this, and a different distro changes nothing: the nodes come from the WSL kernel and the Windows driver, not from the distro. → the legs run **on Windows**, or the box runs native Linux (gate 1) |
| Hostname / IP | client-class device (no server role, no `kogler.si` service record) |

## Role in the AI tier (decision #28 in [`services-ai.md`](services-ai.md) §9)

| Tier | Host | Runs | Why there |
|---|---|---|---|
| Generation | **spark** (GB10) | `spark/qwen3.8-flash-next`, **text-only** | one big model, one huge context window |
| **Client-side inference** | **workstation (this doc)** | **FIM autocomplete** + **vision = visual judgment** | typing-time latency budget + the model must be up when the network isn't |
| Pinned services | **oldsrv** RX 7600 | STT + embed + rerank (Vulkan, decision #27) | always-on, small, latency-sensitive |
| Ingest / CPU OCR | **VPS** | Docling (CPU) | no GPU on that host; born-digital docs need no OCR |

**The workstation owns exactly two legs, and both are local by necessity — not preference.**

## Leg 1 — FIM autocomplete (fill-in-middle, Continue.dev tab-completion)

**Why local, in order of weight:**
1. **Latency contract.** Tab-completion fires on typing pauses with a ~150–400 ms budget, and *prefill of
   the FIM window is paid on every trigger*. Local removes both the network RTT and the queue behind
   STT/embed/rerank on the RX 7600 (measured co-residency contention 1.5–2×,
   [`services-ai-bench.md`](services-ai-bench.md) §6) — a 200 ms stall is felt on every keystroke pause.
2. **It does not fit the 7600 anyway.** A 7B-class FIM model is ~4–5 GiB against an 8 GiB card whose pinned
   tier already holds ~2.4 GiB ([`hardware-gpu.md`](hardware-gpu.md) §VRAM) — a direct collision.
3. **Privacy.** Source code stays on the laptop.

**Hard model requirement:** the model must be **FIM-trained**. Instruct and VL variants do not do it, so
"one model for everything" is not available here. Candidate set (pick by measurement, pp-bound):
`Qwen2.5-Coder-{1.5B,3B,7B}` (`<|fim_prefix|>`/`<|fim_middle|>`) or `StarCoder2-{3B,7B}`.

## Leg 2 — Vision = visual judgment (not OCR, not split inference)

Model: **`Qwen3-VL-30B-A3B-Instruct`** GGUF (Q4_K_M class). The **A3B MoE is preferred over a dense 8B**
reasoning survives the 2026-09-27 correction and is in fact *stronger* on a ~90 GB/s bus, which punishes dense
weights harder. What does **not** survive is the speed figure: the community's ~100 t/s-class results are
256 GB/s / 40 CU Strix Halo numbers, so "dense-4B-ish speed" is **unmeasured here** (gate 3) and dense 4B stays
the fallback for fast round-trips.

**This leg is scoped to *judgment*, not reading:**

| Job | Where | Why |
|---|---|---|
| "Does this layout match the mock / what looks wrong here" | **workstation VL** | needs the bigger brain; dev-only availability is correct |
| Screenshot→text, OCR-ish reading, camera-snapshot description | not here (deferred, see [`hardware-gpu.md`](hardware-gpu.md)) | reading is a small-model job; it does not need to be on the laptop |

**Why the engine cannot "receive vision tokens" from here (settled 2026-09-20, HD-400/HD-401):** the only
pre-computed-vision seam vLLM offers is *multimodal embeddings*, and those must live in the target model's
own visual-token space. `Qwen3.8-Flash-Next` is `Qwen4ExpForConditionalGeneration` — vision encoder 27
layers / hidden 1152 → its own merger → LM hidden **2560**, positioned by interleaved mrope
(`mrope_section: [11,11,10]`). A Qwen3-VL encoder's output is trained against a different geometry and a
different LM; feeding it in yields confidently-wrong output at HTTP 200. Upstream also gates the embedding
input path behind the same `--limit-mm-per-prompt` limits, so "disable the modality **and** accept
embeddings" is not a stock-flag combination. **Image tokens additionally cost *context*, not just encoder
weights** — a transplanted embedding would still spend spark's KV. There is no architecture here to build.

**So the seam is a cascade: vision → text.** Working shapes:
- **Describer** — screenshot → compact structured observation (layout, components, visible console/error
  text) spliced into the harness context.
- **Verifier/judge** ⭐ — build → screenshot → VL returns pass/fail + patch instructions → spark writes code.
  Each model runs where it is strong, and no caption is ever mistaken for the codebase.

**Seam rules (all three are load-bearing):**
1. **Describe once, freeze.** Hash by image bytes and reuse the same text, so the description becomes part
   of the *stable prefix* — otherwise every screenshot churns the prompt and re-prefills the whole
   (agent-sized) context. Keeping images out of spark's window is the real context win: a 1280×800
   screenshot ≈ **1–2.5k tokens**, and a frontend loop accumulates 5–10 of them in history.
2. **Pass-through, not a router.** The seam rewrites `image_url`/`image` parts and forwards everything else
   byte-identical. It must **not** become a LiteLLM-style proxy: decision #26 exists because unsupported
   keys are dropped silently, and here the silent failure mode is *visual input that quietly disappears*.
3. **Loud.** Count and surface every rewrite. With spark started text-only (HD-400), an un-rewritten image
   part **400s** instead of degrading silently — that is the invariant, and it is the reason `image=0` is
   a feature rather than a loss.

Also worth weighing before building anything: much frontend signal is better as **text** (DOM subtree,
computed styles, console/network errors, axe violations) — cheap, deterministic, prefix-cacheable. Vision
earns its place on *visual* judgment.

## NPU: out of the AI tier

| Question | Answer |
|---|---|
| Vision encoder on NPU? | **No.** XDNA wants static, bounded graphs; a Qwen3-VL tower is dynamic-resolution (patch count varies per image). No stack in AMD's XDNA toolchain runs a VL encoder there — it lands on the iGPU/CPU regardless |
| LLM on NPU? | Possible (`llm-aie` llama.cpp plugin / Ryzen AI SwarmLLM) but a curated, **repacked** model list, INT4-only, coupled to `amdxdna` kernel + NPU firmware versions |
| What it buys | **Watts only.** The NPU shares the same LPDDR5x pool, so it buys no bandwidth — the iGPU already serves both legs |
| Why it stays out anyway | It is exactly the fragility the homelab retired elsewhere: a mutable-plugin + pinned-driver stack with no artifact trail (`hardware-gpu.md` / decision #27 precedent: "no published artifact ⇒ self-build with no Renovate trail"; HD-335 dropped the ROCm pins for the same shape of reason) |

**Revisit trigger:** a concrete low-power, always-on consumer (fanless/battery ASR or an idle prefill
offload) — not "the NPU is there".

## Memory & residency (ledger re-derived 2026-09-27)

The old sentence — two resident models inside 128 GB is "not a ledger problem" — was arithmetic on a machine
this is not. At 55.6 GB visible with a ~90 GB/s bus the honest version is: **two** resident models fit, **three**
do not.

| Resident set | Footprint | Verdict |
|---|---|---|
| FIM `Qwen2.5-Coder-3B` Q4 **+** `Qwen3-30B-A3B-Instruct-2507` Q4_K_M | ~2 GB + KV ~0.3 GB @8k, and ~18–19 GB + KV ~3 GB @32k (≈96 KiB/token) | fits: measured host free **30.4 GB** ⇒ ~6 GB margin, and with `-ngl 99` + mmap the GGUF mapping is reclaimable page-cache, not private RAM |
| **+** the 30B-A3B VL (~20 GB) as a third resident | | **does not fit.** The VL **replaces** the 30B for the duration of a vision session; it does not join it |

Two things must be proven before that swap is a routine rather than an experiment. First, unchanged from the
original note: the **BIOS iGPU carve-out / GTT** range, so the iGPU can allocate past the UMA aperture. Second,
new: **unloading a model must actually return the allocation** — `pause` frees compute, not memory, and the
`amdgpu` VRAM OOM is not graceful with no arbiter for two on-demand consumers ([`hardware-gpu.md`](hardware-gpu.md)
§findings, the 7600 lesson). A swap is therefore strictly unload → confirm release → load, never
optimistically start the second server.

## Pre-flight gates before this becomes config (HD-401)

1. **Where the stack runs at all** (replaces the old "ROCm vs RADV" gate, which is moot): the WSL guest has no
   `/dev/dri` and no `/dev/kfd`, so the real choice is **Win11 native** (LM Studio already installed, models dir
   empty) or **native Linux on this box**. ROCm-inside-WSL for this family is its own newer path (AMD: ROCDXG
   with Adrenalin 26.2.2 + ROCm 7.2.1). Pick one, record the version.
2. **LLVM target:** `gfx1150` vs `gfx1151` is **unconfirmed for this APU** (§Platform) — re-derive it before any
   build, driver pin or quantization script names it.
3. **Bandwidth is ≈90 GB/s, not ≈256 GB/s.** Re-measure decode **and** prefill here before the FIM leg's
   ~150–400 ms budget is treated as reachable at a useful model size: prefill is paid on every trigger, it is
   the compute-bound half, and this iGPU has 16 CU, not 40.
4. **VL multimodal path on the chosen backend:** confirm the `mmproj` vision tower actually runs on GPU and
   does not fall back to CPU — measure prefill with `--image`, don't assume.
5. **FIM:** model is FIM-trained, and measured trigger latency inside the budget with the real Continue
   prompt shape.
6. **Carve-out/GTT** check, plus the unload/reload proof (VRAM returned, reload latency of a ~19 GB model) from
   §Memory & residency.

## Document Map / Related

- [`hardware.md`](hardware.md) roster · [`hardware-gpu.md`](hardware-gpu.md) (the 8 GiB card this doc deliberately
  does **not** use) · [`hardware-spark.md`](hardware-spark.md) §Text-only engine mode (HD-400)
- [`services-ai.md`](services-ai.md) §9 decision #28 (vision placement across tiers)
- [`pi-harness.md`](pi-harness.md) — the harness's model config on this machine (never duplicated here)
- [`../spark/`](../spark/) research: `resources/R1-hf-model-card.md` (architecture), `RESEARCH-VERDICTS.md`
