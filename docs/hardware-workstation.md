---
title: Workstation — admin laptop (AMD Strix Halo) as the client-side inference tier
role: detail
domain: hardware
status: active
tags: [hardware, ai, workstation, strix-halo, fim, vision, gpu]
---
# Workstation — admin laptop (AMD Strix Halo)

> **Role:** Detail — the **admin workstation (laptop)** and its role in the AI tier: the two model legs that
> must run **locally** (FIM autocomplete + visual judgment), why the vision hand-off to spark is a
> **cascade** and not token-level split inference, and why the **NPU stays out** of the AI tier. Owning doc
> for the *placement* decision of these two legs; the pi.dev harness's model config stays in
> [`pi-harness.md`](pi-harness.md), spark's engine config in [`hardware-spark.md`](hardware-spark.md).
> **Links to:** `hardware-gpu.md`, `hardware-spark.md`, `services-ai.md`, `pi-harness.md`, `network-vpn.md`
> (laptop alias contract), [`../todo.md`](../todo.md) (HD-401)
> **Linked from:** `hardware.md`, `index.md`

> ⚠ **Evidence status (2026-09-20):** the platform below is **owner-stated, not yet measured on-device**.
> Every `t/s`, VRAM and driver figure in this doc is a **community reference expectation** from the Strix
> Halo llama.cpp ecosystem, not a measurement on this box — same discipline as
> [`services-ai-bench.md`](services-ai-bench.md): measure before any of it becomes config.

## Platform (owner-stated 2026-09-20, unverified)

| Item | Value |
|---|---|
| SoC | AMD **Ryzen AI MAX+ 395** (Strix Halo, `gfx1151`, RDNA 3.5) — iGPU **Radeon 8060S** |
| Memory | **128 GB unified LPDDR5x** — no VRAM partition; ~256 GB/s class bandwidth (same bandwidth class as spark's GB10 273 GB/s) |
| NPU | XDNA2 (Ryzen AI) — **explicitly not used** (§NPU: out of the AI tier) |
| OS | Windows + **WSL2** (the SSH alias contract for both `~/.ssh/config` files lives in [`network-vpn.md`](network-vpn.md) §The laptop alias contract) |
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

Model: **`Qwen3-VL-30B-A3B-Instruct`** GGUF (Q4_K_M class). On this platform an **A3B MoE is preferred over
a dense 8B** — the 30B-A3B text siblings are the community's ~100 t/s-class results on `gfx1151`, so an A3B
VL gives 8B-plus perception at dense-4B-ish speed. Dense 4B/8B remain the fallback for fast round-trips.

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

## Memory & residency

Two resident models (FIM 2–7 GB + a 30B-A3B VL ~18 GB) inside 128 GB unified is **not** a ledger problem —
unlike the 8 GiB card on oldsrv. The one thing to verify on-device: the **BIOS iGPU carve-out / GTT** range,
so Vulkan and ROCm can allocate past the UMA aperture.

## Pre-flight gates before this becomes config (HD-401)

1. **ROCm/gfx1151 stack:** the community break is `ROCm 7.2.1` (gfx1151 is *not* supported on 7.0); Vulkan/RADV
   is the fallback. Pick one, record the version.
2. **VL multimodal path on the chosen backend:** confirm the `mmproj` vision tower actually runs on GPU and
   does not fall back to CPU — measure prefill with `--image`, don't assume.
3. **FIM:** model is FIM-trained, and measured trigger latency inside the budget with the real Continue
   prompt shape.
4. **Carve-out/GTT** check above.

## Document Map / Related

- [`hardware.md`](hardware.md) roster · [`hardware-gpu.md`](hardware-gpu.md) (the 8 GiB card this doc deliberately
  does **not** use) · [`hardware-spark.md`](hardware-spark.md) §Text-only engine mode (HD-400)
- [`services-ai.md`](services-ai.md) §9 decision #28 (vision placement across tiers)
- [`pi-harness.md`](pi-harness.md) — the harness's model config on this machine (never duplicated here)
- [`../spark/`](../spark/) research: `resources/R1-hf-model-card.md` (architecture), `RESEARCH-VERDICTS.md`
