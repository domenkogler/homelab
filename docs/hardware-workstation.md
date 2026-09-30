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
  **⚠ Superseded 2026-09-28:** the owner has since set the UMA carve to **32 GiB**, so this row's “⇒ ≈8.4 GB reserved — not a 32 GB carve-out” is the measurement of the OLD setting and must not be quoted as current. Re-measure `MemTotal` in Windows and in the WSL2 guest before re-deriving the ledger (32 GiB carved is no longer “free” host RAM). See §Served leg.
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

**Resolved by probe, not by argument (2026-09-29, `raw/40-coder-probes.txt`).** The requirement
above and Qwen2.5-Coder's own model card were both true about DIFFERENT SURFACES, which is why the
argument never closed. Measured on the weights already on `D:`, same cursor gap, three shapes: the
raw `/v1/completions` gap **continues and ignores the suffix**; the literal marker tokens handed as
plain text are **echoed back** (these GGUF weights do not carry the FIM tokens as control tokens); and
the instruction + PREFIX/SUFFIX code fence that Continue's tab provider actually sends **infills
correctly, 3/3**. So this section holds for the raw/marker surface and the card holds for the
templated one; `fim_surface: instruction-fenced` records which shape the row was proven on, and
`probe-fim --self-test` (6/6) breeds one wrong verdict per failure shape so the detector cannot go
soft. **Open:** trigger latency inside the 150-400 ms budget (HD-401 gate 5).

## Leg 2 — Vision = visual judgment (not OCR, not split inference)

Model: **`Qwen3-VL-30B-A3B-Instruct`** GGUF (unsloth `UD-Q4_K_XL`, 17 715 664 608 B) with
`mmproj-BF16.gguf` (1 087 039 168 B) — **landed as profile `vision-qwen3vl-30b`, measured on this
engine 2026-09-30**. The **A3B MoE is preferred over a dense 8B** reasoning survives the 2026-09-27
correction and is in fact *stronger* on a ~90 GB/s bus, which punishes dense weights harder. What
does **not** survive is the speed figure, and here is the one that replaces it: **decode 23.84 t/s**,
which is *faster* than the agent leg's decode at the same depth (18.3 t/s at a 10.6 k-token prompt,
8.3 t/s at 31 k — the agent leg's speed table is below), so the community's ~100 t/s-class number is
dead and dense-4B is no longer needed as a fast-round-trip fallback — the MoE is the fast one here.

**What vision actually costs on this box** (`raw/68`, `raw/72`, `raw/73`, `raw/88`, `raw/91`,
`raw/92`): the untouched **8160×6120 / 10.6 MB** rack photo is accepted as-is — **4042–4060
prompt_tokens, 61–72 s**, i.e. **image prefill at ~56–66 t/s** — and the engine is still IDLE
afterwards. It sees: `CAT6` three times, the 1–24 patch-panel numbering, `Cloud Router Switch`, a
`CRS3xx` model. **It is not a transcription instrument, and that is a measurement, not a hunch**:
asked for the switch's model number five times — three at the file's sampling, twice greedy at
`temperature 0` — it answered `CRS326-24G-2S+RM` every single time, while
[network-rack.md](network-rack.md) U15 records `CRS328-24P-4S+` with a label photo behind it.
Greedy agreement rules out sampling noise, so this is perception. **This corrects the 2026-09-29
note here that it OCR'd `CRS328-24P-4S+RM` verbatim and thereby corroborated the rack doc: that
result is not reproducible, and the label photo — not the model — stays the authority.** Use the leg
for judgment (is the label legible, which slot is occupied, what is plugged in); verify any
transcribed identifier against the inventory. A 32k window of this model is **3.0 GiB of KV** (96
KiB/token) and the whole load measures **23.92 GiB**, so nothing else is resident while it runs.

**Ask a photo once, or ask it the same way twice.** Re-asking the *identical* question on the same
image costs **2.0 s**; asking a *different* question re-pays the full ~60 s (`raw/92`). The reason is
prefix caching: the text part sits before the image in the message, so changing the question
invalidates the cached image tokens. Any seam that asks several things of one photo must put the
image first or freeze the question — otherwise it pays image prefill per question.

**Why the agent leg does NOT also do images (this is the reason the legs are split).** Gemma 4 26B
A4B on this Vulkan build dies on any image whose **long side exceeds ~1120 px** — engine exit
`3221226505` = `STATUS_STACK_BUFFER_OVERRUN`, server answers `{"error":"terminated"}`. Reproduced on
TWO weight files (lmstudio-community Q4_K_M and unsloth QAT `UD-Q4_K_XL`) and on a **2000×160**
strip, which is a quarter of the pixels of a 1280×960 that fails: so it is not the quant, not the
file, not the pixel count — it is max side length. 320 / 640 / 896 / 1120 answer; 1280 and 2000 kill
it (`raw/62`, `raw/64`, `raw/66`). A capability whose failure mode is a dead runtime does not belong
in a client contract, so `agent-gemma-26b` is `input: [text]` and the projector is not even loaded
(a hard-linked folder without the mmproj — 1.11 GiB resident cheaper).

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

## Served leg — LM Studio as the runtime (HD-474, owner decision 2026-09-28)

**Decision:** the laptop serves its models from **LM Studio only** — both legs, and the FIM model
too. This closes the wrapper question the earlier drafts left open, and it was decided on
measurement, not preference.

**Why not Ollama, with the receipts:** on Windows neither wrapper has a ROCm path for this APU
(Ollama's Windows AMD list is discrete RX/PRO cards; LM Studio's ROCm engines report the same,
lmstudio-bug-tracker #883/#1903), so both end up on the **same llama.cpp Vulkan engine** and the
wrapper buys ~0 tokens/s. Ollama also carries two measured traps specific to this silicon: integrated
GPUs are skipped unless `OLLAMA_IGPU_ENABLE=1`, and 0.30+ dropped gfx1150 from the allow-list, which
runs the model **on the CPU** while still answering 200 (ollama #16690 → PR #16701). Decisive
instead: **vision.** LM Studio loads `--mmproj` for these arches today; Ollama's Modelfile has no
projector instruction at all (the documented set is FROM/PARAMETER/TEMPLATE/SYSTEM/ADAPTER/LICENSE/
MESSAGE), `ADAPTER mmproj` 500s (#15346), two `FROM` lines hang (#17491), and `qwen35moe` was unknown
to its vendored llama.cpp (#14730/#15898) until PR #15899 + #16031. LM Studio already reads the
152 GB library on `D:` — one library, zero duplicate bytes.

**The two legs, from one runtime, measured on the box (the catalogue is
`scripts/laptop-llm/profiles.yml`; the budget, the gate and the probes are `scripts/laptop-llm.py`;
the applier is `scripts/win/lmstudio-llm.ps1`). Owner ruling 2026-09-29: **two legs, one GPU** —
Gemma does the agentic work, Qwen-VL does images. Not one model doing both, and the reason is a
measured failure, not taste: this Gemma build kills the engine on an image whose long side exceeds
~1120 px (§Leg 2):**

| Profile | Model | Window | Budget against the 32 GiB carve (declared → measured) |
|---------|-------|--------|----------------------------------------------------------|
| **`agent-gemma-26b`** (active) | Gemma 4 26B A4B Q4_K_M, **text-only** — a hard-linked folder with NO mmproj in it | 32k f16 KV | 15.64 + 0 projector + 0.62 KV + 0.20 state + 3.00 floor = **19.46** ⇒ +12.54 margin · **measured 18.87 GiB** of PDH dedicated memory under a 2.21 GiB idle desktop |
| **`vision-qwen3vl-30b`** | Qwen3-VL-30B-A3B-Instruct UD-Q4_K_XL **+ mmproj-BF16** | 32k f16 KV | 16.50 + 1.01 + 3.00 KV + 0 + 3.00 floor = **23.51** ⇒ +8.49 margin · **measured 23.92 GiB** at 32k (`raw/ctx32k.out`) |
| `fim-coder-3b` | Qwen2.5-Coder-3B-Instruct Q4_K_M, q8_0 KV | 8k | 1.80 + 0.14 + floor = **4.94** (FIM probe passed; trigger latency still unmeasured) |
| `agent-unified` / `-mtp` / `-64k` | Qwen3.6-35B-A3B Q4_K_M — **weights not on `D:`** (~21 GB) | 32k / 64k | declared only. Nothing measured here certifies them, and the agent leg now beats `agent-unified` on margin without a download |

**One leg is resident. That is not a preference, it is the arithmetic.** Qwen3-VL holds 96 KiB/token
(48 layers × 4 KV heads × 128, no sliding window), so 32k of it is **3.0 GiB of KV** on top of
16.50 GiB of weights and 1.01 GiB of projector; the measured load sits at 23.92 GiB of the ~24 GiB
adapter. `lms unload --all` before every load, and the applier enforces it.

**What the client sees (and the trap in it).** `scripts/pi-config/models-spec.yml` carries BOTH rows
— `agent-gemma-26b` (`input: [text]`) and `vision-qwen3vl-30b` (`input: [text, image]`) — while
JIT loading is OFF, so only the resident one answers. The picker therefore shows two rows and one is
always dead until `lmstudio-llm.ps1 switch -Profile <name>` moves the GPU. **Do not trust the picker
to be honest for you, because the endpoint will not:** LM Studio's OpenAI server does **not** police
the `model` field. Measured 2026-09-30 with only the vision leg loaded — a request naming
`no-such-model-here` was answered (`'PONG'`, 0.4 s) **by the resident model**. So a dead row is not
loud on the text path, it is *silent and wrong*: you get an answer from the other leg and never know.
Images are the one path that IS policed (`400 "does not support image inputs"` in 0 s), which is why
the text-only leg fails correctly. The guard is `probe-client`, which now compares the row it
certifies against live `/v1/models` and FAILs when that leg is not resident. The other expensive
mistake is quiet by construction — an over-1120 px image at a Gemma leg. Both rules are written into
the spec next to the rows so whoever picks has them in front of them.

**Measured speed on this engine, this carve (2026-09-29/30, `raw/69`–`73`, `raw/80`, `raw/88`):**

| Leg | Decode | Prefill | TTFT | Note |
|-----|--------|---------|------|------|
| Gemma 4 26B A4B (text) | **21.1 / 18.3 / 8.3 t/s at 2 462 / 10 610 / 31 137 prompt tokens** — decode is NOT a constant on this box | **256 / 153 / 17 t/s** cold at those same sizes | **9.63 / 69.42 / 1806.83 s** cold; **0.30–0.38 s** warm on a prefix-cache hit at any size | thinking is ON and cannot be switched off server-side — budget ≥ 1024 reply tokens or `content` comes back empty (`raw/90`) |
| Qwen3-VL-30B-A3B | **23.84 t/s** | **~56–66 t/s image prefill** — the 8160×6120 rack photo = 4042–4060 tokens in 61–72 s; 31 809 text tokens in 915 s | — | 23.92 GiB at 32k; over-window requests are refused in 0 s (clean 400, no crash) |

**Memory is cheap, the prompt is the wall, and the wall is erratic.** Same weights, SAME 20 816-token
prompt, three fresh loads (`raw/80` phase 3): **359 s at `num_ctx 32 768`, 899 s at `49 152`, 277 s
at `65 536`**. Three readings of one prompt spanning 3.3× is the actual finding — prefill at ≥20 k
tokens on this iGPU is not repeatable enough to plan a session around, and it is not monotonic in
the window either, so do NOT read the 899 as "bigger window costs more". It has now been caught a
second way: one **10 610-token** prompt measured **259.15 s** on one load and **69.42 s** on another
(`raw/88` vs `raw/90`) — same bytes, same weights, same window. What IS monotonic is
memory, and it is cheap: **18.87 → 19.18 → 19.31 GiB** across 32k → 49k → 65k, i.e. ~0.4 GiB per
+16 k tokens ≈ 24 KiB/token, which lands on the predicted 20 KiB/token from the header arithmetic.
So the reason `client_context_window` stays **32 768** is latency and variance you can feel, not a
GiB you are out of — and recall at that depth is not the problem either: a needle buried at 92 % of
a 28 984-token prompt came back verbatim (`raw/80` phase 4). (For scale: the previous session's cold
31.2 k turn took 13+ min before it was killed, and the Qwen-VL leg took 915 s for 31 809 tokens.)

**Ledger correction — this family's KV is 20 KiB/token, not 96.** §Memory & residency's
“≈96 KiB/token” is right for **Qwen3-30B-A3B** (48 layers, 4 KV heads × 128 head_dim).
Qwen3.6-35B-A3B is **hybrid**: 40 layers in 10 × (3 × Gated DeltaNet → 1 × Gated Attention), so
only **10** layers hold a KV cache, at 2 KV heads × head_dim 256 ⇒ `2×10×2×256×2 = 20 480 B/token`.
The 30 linear layers hold a **constant** recurrent state per sequence instead. Consequence: a 32k
window costs 0.62 GiB, and q8_0 KV only saves 0.31 GiB — which is why `agent-unified` keeps **f16
KV**: llama.cpp honours a quantized KV cache **only with flash attention on**, FA-on-Vulkan for this
arch is unproven, and 1.6 % of the budget is not worth an unproven dependency plus an unmeasured
recall risk. `agent-unified-64k` is where q8_0 earns its keep (it halves a 1.25 GiB KV).

**MTP and vision cannot share a load.** Unsloth's own README: “`--mmproj` is not yet supported with
MTP” — so `agent-unified-mtp` is text-only by construction, and lmstudio-bug-tracker #1951 reports
MTP failing to initialise on the 35B **MoE** (the dense 9B got 40–60 %). MTP stays off until an A/B
on this box shows an actual gain.

**Closed 2026-09-30 (HD-474), and what is still open.** Closed: `runtime.version` is **pinned**
(`0.4.25+1`, read three ways — `resources\app\package.json`, the exe `FileVersion`, the uninstall
registry — all agreeing; `lms` CLI commit `69d945a`; `llmster v0.0.25+1` is the service). The
agent-leg and vision-leg weights are on `D:` and both booted. `fim_probe` is **passed** and the
§Leg 1 contradiction is settled: both papers were describing DIFFERENT SURFACES — the raw
`/v1/completions` gap ignores the suffix and literal `<|im_start|>` markers echo back (so
§Leg 1's "Instruct variants do not do it" is TRUE for that surface), while the instruction-fenced
shape Continue actually sends infills correctly (so Qwen's card is TRUE for that one).
`raw/40-coder-probes.txt`, `fim_surface: instruction-fenced`.
Still open, and the gate is what keeps them open: **FIM trigger latency** has never been measured
(HD-401 gate 5, sub-second is an assumption), the **Qwen3.6 `agent-unified*` arms have no weights on
disk**, `:1234` LAN exposure is an **owner decision that is still outstanding** (no firewall rule is
added as a side effect), and the client render is verified only by `probe-client` while 1Password is
signed out — `render-pi-config.py --check` needs `op`, which is a human step (§6).

**Client contract — and the seat it is addressed to (owner decision 2026-09-29):** local models are
served to **pi.dev running ON Win11**. `providers.laptop-lmstudio` in
`scripts/pi-config/models-spec.yml` therefore declares `native_only: true` next to `hosts:
[domenp14s]`, and `scripts/render-pi-config.py` omits it when rendering inside WSL2 — with
`networkingMode=Nat`, which is left exactly as configured because it is there for reasons that
outlive this leg, `127.0.0.1` inside the guest is the guest. Hostname alone cannot separate the two
seats, which is why the spec carries a flag rather than a second name — but NOTE the measured
hostname: `socket.gethostname()` on this box is **`Domen_P14s`**, not the `DomenP14s` every doc here
said. That one underscore silently dropped the provider from the Windows render AND made
`probe-client` SKIP instead of checking (2026-09-30); host matching is now normalised in
`render-pi-config.py:host_norm()` and `probe-client` imports that one matcher instead of keeping a
second opinion.
`laptop-llm.py probe-client` honours the same rule and SKIPs itself in the guest instead of failing a
contract that was never addressed to it. The drift check itself compares
`contextWindow`/`maxTokens`/`input` against the ACTIVE profile — pi's 400-mid-session class.

**Carve-out note (supersedes the ≈8.4 GB line above):** the BIOS UMA carve is now **32 GiB**. That
buys **residency**, never bandwidth — the ≈89.6 GB/s ceiling is untouched, so a dense model is still
bandwidth-bound and the MoE-A3B family is still the only one that answers (§Leg 2). It also removes
~24 GB from what Windows and the WSL2 guest can use; re-measure before trusting any ledger number.

**The session that finishes this leg runs on the Windows seat** — pin the engine version, fetch the
weights, boot, and run the six probes: the brief is [`prompt-lmstudio.md`](../prompt-lmstudio.md).

## NPU: out of the AI tier

| Question | Answer |
|---|---|
| Vision encoder on NPU? | **No.** XDNA wants static, bounded graphs; a Qwen3-VL tower is dynamic-resolution (patch count varies per image). No stack in AMD's XDNA toolchain runs a VL encoder there — it lands on the iGPU/CPU regardless |
| LLM on NPU? | Possible (`llm-aie` llama.cpp plugin / Ryzen AI SwarmLLM) but a curated, **repacked** model list, INT4-only, coupled to `amdxdna` kernel + NPU firmware versions |
| What it buys | **Watts only.** The NPU shares the same LPDDR5x pool, so it buys no bandwidth — the iGPU already serves both legs |
| Why it stays out anyway | It is exactly the fragility the homelab retired elsewhere: a mutable-plugin + pinned-driver stack with no artifact trail (`hardware-gpu.md` / decision #27 precedent: "no published artifact ⇒ self-build with no Renovate trail"; HD-335 dropped the ROCm pins for the same shape of reason) |

**Revisit trigger:** a concrete low-power, always-on consumer (fanless/battery ASR or an idle prefill
offload) — not "the NPU is there".

## Memory & residency (ledger re-derived 2026-09-27, GPU counters measured 2026-09-30)

The old sentence — two resident models inside 128 GB is "not a ledger problem" — was arithmetic on a machine
this is not. At 55.6 GB visible with a ~90 GB/s bus the honest version — **measured on the GPU
counter, not inferred from host RAM** — is: **one 30B-class leg fits, two do not.** The counter is
`\GPU Adapter Memory(luid_0x00000000_0x0001a051_phys_0)\Dedicated Usage` in **bytes**; the engine's
`offloaded N/N layers` line is absent at verbosity 3 on this Vulkan build, so it proves nothing here.
Idle desktop under a load reads **2.15–3.12 GiB** (two days of readings), the text-only Gemma leg at
32k reads **18.87 GiB**, the same weights with the projector **19.81 GiB**, and the Qwen-VL leg at 32k
**23.92 GiB** of a ~24 GiB adapter.

| Resident set | Footprint | Verdict |
|---|---|---|
| one agent leg: `agent-gemma-26b` (text-only, 32k) | 15.64 weights + 0.62 KV + 0.20 window state, **18.87 GiB measured** under a 2.21 GiB desktop | **this is the resident default.** ~5 GiB of adapter headroom left, and it is not enough for another 30B-class model |
| one vision leg instead: `vision-qwen3vl-30b` (32k) | 16.50 + 1.01 mmproj + **3.00 KV** (96 KiB/token), **23.92 GiB measured** | fits ALONE. It **replaces** the agent leg for the duration of a vision session; it does not join it |
| `fim-coder-3b` alongside either | ~1.93 + 0.14 KV | the only thing small enough to share, and LM Studio unloads on switch anyway — the applier keeps it one-at-a-time |

What the 2026-09-30 run proved about the second half of the old note (**"unloading must actually
return the allocation"**): it does. Every phase-3 step ran `lms unload --all` → reload at a bigger
window and the dedicated-memory counter came back to the same idle floor (2.15–2.28 GiB) before each
load, then rose by the model's own size. So the swap is a routine, not an experiment — with the
documented order: **unload → confirm release → load**, never optimistically start the second server.

## Pre-flight gates before this becomes config (HD-401)

1. **Where the stack runs at all** — **CLOSED 2026-09-29: Win11 native**, LM Studio `0.4.25+1`
   pinned in `scripts/laptop-llm/profiles.yml §runtime` (three independent reads agreeing), `llmster
   v0.0.25+1` as the service. Native Linux on the box stays the revisit trigger, not the plan.
2. **LLVM target:** `gfx1150` vs `gfx1151` is **still unconfirmed for this APU** (§Platform). It does
   not block this lane — the Vulkan engine is chosen by LM Studio's own build and no artifact here
   names a target — but it blocks any build, driver pin or quantization script that would.
3. **Bandwidth is ≈90 GB/s, not ≈256 GB/s** — **measured here 2026-09-30**: agent leg decode
   **17.5–17.8 t/s**, vision leg **23.84 t/s**, prefill ~250 t/s at 1.8–2.2k falling to ~58 t/s at
   20.8k. The FIM leg's ~150–400 ms budget is a claim about a THIRD model (`fim-coder-3b`, 3B dense)
   and its trigger latency is still unmeasured — so gate 5 is open even though gate 3 is not.
4. **VL multimodal path on the chosen backend** — **CLOSED: the tower runs on the GPU.** Image
   prefill measured **61.2 t/s** on the 8160×6120 photo (4060 tokens, 66 s) with dedicated memory at
   23.92 GiB; a CPU-side tower shows up as tens of seconds per image at a fraction of this rate, and
   it does not. What it also proved: the Gemma tower's ~1120 px long-side ceiling (§Leg 2).
5. **FIM:** `fim_probe` **passed** — 3/3 cursor-shaped infills on the instruction-fenced surface
   (`fim_surface: instruction-fenced`, `raw/40-coder-probes.txt`), which is also what settles the
   §Leg 1 vs model-card contradiction. **Still open: trigger latency** in the real Continue shape.
6. **Carve-out/GTT + unload/reload** — **CLOSED on 32 GiB carve** (owner set it 2026-09-28) and the
   reload proof is in `raw/80` phase 3: three unload → reload cycles at 32k/49k/65k, the dedicated
   counter returned to the idle floor each time and rose by the model's size, reload of the 16.8 GB
   file taking ~40 s. No GTT fallback was needed or used.

## Document Map / Related

- [`hardware.md`](hardware.md) roster · [`hardware-gpu.md`](hardware-gpu.md) (the 8 GiB card this doc deliberately
  does **not** use) · [`hardware-spark.md`](hardware-spark.md) §Text-only engine mode (HD-400)
- [`services-ai.md`](services-ai.md) §9 decision #28 (vision placement across tiers)
- [`pi-harness.md`](pi-harness.md) — the harness's model config on this machine (never duplicated here)
- [`../spark/`](../spark/) research: `resources/R1-hf-model-card.md` (architecture), `RESEARCH-VERDICTS.md`
