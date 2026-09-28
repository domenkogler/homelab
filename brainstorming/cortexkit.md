# CortexKit Magic Context — fit analysis + coding-seat model placement

> **Role:** brainstorming note (research, not SSOT). Session output 2026-09-27: evaluating
> [`cortexkit/magic-context`](https://github.com/cortexkit/magic-context) against this fleet's AI architecture, and
> the resulting local-model placement for the coding seat on the laptop.
> It **does not** amend any decision row. Every claim is labelled **measured** (this session, on this box) /
> **doc** (from a cited source) / **unverified** (must be measured before it is load-bearing).
> **Links to:** [`docs/services-ai.md`](../docs/services-ai.md) §9b/§9c · [`docs/hardware-workstation.md`](../docs/hardware-workstation.md) ·
> [`docs/hardware-gpu.md`](../docs/hardware-gpu.md) · [`docs/pi-harness.md`](../docs/pi-harness.md) ·
> probes in [`../reports/`](../reports/) · OQ-12/OQ-13/OQ-14 in [`../todo.md`](../todo.md) §1

---

## 1. What it is, and which layer it occupies

Magic Context (MC) = context-window management + cross-session project memory, as a **native harness
plugin** (OpenCode 1.x/2.x, Pi, OMP; a Rust module `ck-mc` serves Claude Code via the Thalamus gateway).
Current `v0.43.2`, MIT, ~2k stars, very high release cadence. Three npm packages on one version line.

**The layer distinction that decides everything:**

| Component | Job | Store | Interface |
|---|---|---|---|
| `rag-mcp` (HD-268b, stub) | *corpus* retrieval over OKF wiki | **Qdrant** (1024, rebuildable cache over git SSOT) | **MCP**, multi-consumer |
| Mem0 (planned, HD-335) | per-user long-term memory for OWUI | Qdrant collection | server-side |
| agentmemory (probed, undecided) | coding-plane agent memory | own store, ports 3111+N | **MCP** |
| **Magic Context** | *session* context management + agent-private project memory | SQLite, `~/.local/share/cortexkit/magic-context/context.db` | **native harness hooks** |

**MC is not a substitute for the qdrant+MCP plan.** Three hard non-fits (source-verified, not inferred):

1. **It can never target Qdrant.** `embedding.provider` is `local | openai-compatible | off`; vectors are
   stored as plain SQLite blobs compared in memory. Same class of constraint already recorded for
   agentmemory ("can never target Qdrant by design") ⇒ the OQ-13 "two planes nobody reconciles" arm still applies.
2. **It is not an MCP server.** Its `ctx_*` tools are native harness tools. So `ZeroClaw → MCP → memory` and
   `OWUI → MCP → memory` structurally cannot reach it.
3. **Store is per-machine.** Shared across harnesses on one box, never synced between boxes. Laptop **and**
   oldsrv both running MC on this repo = two divergent histories that Kopia cannot merge.

**What MCP structurally cannot do, and MC can** (this is the only reason MC is interesting here): rewriting the
message array every round-trip, deferring drops to cache-safety boundaries, deterministic decay tiers instead of
a compaction cliff, and the `m[0]`/`m[1]` frozen-baseline layout. No MCP server can decide what the model is
*not* shown, and none can avoid busting the cached prefix while doing it.

## 2. Verdict against existing decisions

| Existing rule | MC's relationship |
|---|---|
| #26 harnesses go **direct** to spark | Compatible. MC's *hidden-agent* tier (historian/dreamer) is selectable per harness and per task, which is a knob the flat pi config does not have. |
| "the vector store is independent of any UI"; Qdrant = the vector store | **Conflict** if MC's memory half runs: it is a third durable store after OKF git + Qdrant. |
| Hermes ruling (c): "must not keep its own memory store" | Same category as MC with `memory.enabled: true`. **Dissolves** with `memory.enabled: false`. |
| Probe: "LLM memory compression destroys the retrievable payload" (consolidation ON → retrieval-key 0/5, dropped `9002`, `0.34`, `515,786`, `#26`, `HD-268`) | MC's historian **is** LLM compression. Mitigating nuance: MC keeps a **raw floor** (`ctx_expand` recovers originals; raw-message index stays searchable) — i.e. "git is truth, index is rebuildable cache" restated. Prediction still holds: compartments will shed identifiers. |
| OV rejection reason: "write path is LLM-bound per commit" | MC's fact-promotion is LLM-bound per historian run. Same pattern. |
| §10 ⛔ "do not build a central instance before the owner call" | That gates *agentmemory*. MC would settle OQ-12/13/14 by accident rather than by decision. |
| §9b-1 owner decision: coding seat = native host process, not container | MC fits unchanged: in-process extension, no daemon, no LAN bind. **Dodges agentmemory's OQ-12 blocker** (upstream #523: REST on `127.0.0.1`, needs an authenticating forwarder) because MC has no server to forward. |

**Recommended posture if trialled:** run the **context half only** — `memory.enabled: false` **and**
`embedding.provider: "off"` (note: `memory.enabled: false` alone still silently embeds session history). No third
durable store is created, Qdrant+`rag-mcp` stays the retrieval plane actually decided, and the compaction-cliff
removal is kept.

Clean integration seams if the vector leg is wanted later: MC's `embedding: { provider: "openai-compatible",
endpoint, api_key }` → **`bge-m3-vk` through LAN LiteLLM** (sends the model name **bare**, which matches this leg;
MC has **no dimension knob**, so no agentmemory-style `resolveDimensions()` → 1536 fallback bug), and
`historian.pi` / `dreamer.pi` behind an **HD-384** LAN scoped key — the first real consumer of an allow-list that
is empty today. `profiles` (work/personal) and `workspaces` (`share_categories`, default `["CONSTRAINTS"]`,
read-only) map onto "cross-project recall is opt-in, not default".

## 3. Measured on this box (2026-09-27, DomenP14s)

| Fact | Value | Label |
|---|---|---|
| Harness location | **WSL2** (`6.6.114.1-microsoft-standard-WSL2`), Debian 13 trixie, `WSL_DISTRO_NAME=Debian` | measured |
| GPU compute nodes | **`/dev/dxg` present; NO `/dev/dri`; NO `/dev/kfd`** | measured |
| Vulkan userspace in guest | none (`/usr/share/vulkan/icd.d/` empty, no `vulkaninfo`); no ROCm packages | measured |
| RAM installed | **64.0 GB** (2×32 GB, reported 5600 MT/s) | measured |
| RAM visible to Windows | **55.6 GB** (⇒ ~8.4 GB reserved, **not** a 32 GB hard carve-out) | measured |
| WSL guest `MemTotal` | **27.2 GiB** (WSL2 default 50% cap; `.wslconfig` carries only `networkingMode=Nat`) | measured |
| Host free RAM at idle | **30.4 GB**; `vmmemWSL` working set **2.72 GB** (balloon is lazy) | measured |
| LM Studio | installed (`/mnt/c/Program Files/LM Studio`), **models dir empty (0 B, zero `.gguf`)**; `~/.ollama` has no manifests | measured |
| gfx1151 ROCm on **Windows** | Runtime ✅ + HIP SDK ✅ | [doc](https://rocm.docs.amd.com/projects/install-on-windows/en/latest/reference/system-requirements.html) |
| gfx1151 ROCm in **WSL** | production path = **ROCDXG, needs Adrenalin 26.2.2 + ROCm 7.2.1**; [ROCm#4952](https://github.com/ROCm/ROCm/issues/4952) = card not recognised with the older WSL driver | doc |
| Bandwidth "~256 GB/s class" | reported 5600 MT/s implies materially less | **unverified — measure** |

**Consequence of the two GPU rows:** no WSL distro can reach the iGPU through a native stack today — no
`/dev/dri` means no RADV Vulkan, no `/dev/kfd` means no ROCm, and **Docker-in-WSL inherits exactly this** (it
cannot invent device nodes). Choosing Ubuntu over Debian changes nothing: the nodes come from the WSL kernel +
Windows driver, not the distro. → **the inference server belongs on Win11** (LM Studio is already installed), and
reaching it from WSL needs either LM Studio bound to `0.0.0.0` + a firewall allow for the NAT vSwitch, or
`networkingMode=mirrored` so `localhost` works (the latter matches the "no `0.0.0.0` host binds" instinct).

## 4. Decisions taken this session (coding-seat model placement)

**Two resident local models, each shaped for its own bottleneck:**

| Leg | Model | Size | Why |
|---|---|---|---|
| **FIM** (tab completion) | `Qwen2.5-Coder-3B-Instruct` Q4 | ~2 GB + ~0.3 GB KV @8k (~36 KiB/tok) | **prefill-dominated at a 150–400 ms budget**; must be FIM-trained (`Instruct`/`VL` variants of non-coder models do not do it — existing hard requirement) |
| **Historian** (MC summarizer) | `Qwen3-30B-A3B-Instruct-2507` Q4_K_M | ~18–19 GB + ~3 GB KV @32k (~96 KiB/tok) | **decode-heavy, tolerant of seconds**; A3B = 3.3B active ⇒ ~100 t/s class at 30B quality |
| VL (`Qwen3-VL-30B-A3B-Instruct`) | **deferred**; loaded *instead of* the 30B when needed | ~+20 GB | owner decision this session |

Ledger: ~23.5 GB of 30.4 GB free ⇒ **~6 GB margin**. With `-ngl 99` + mmap the GGUF mapping stays reclaimable
page-cache rather than private RAM. ⚠ `TotalCachedMemory` reported 0.0 GB is a known-bad property — do not trust it.

**Model-variant facts (settled from primary sources, not folklore):**

- `Qwen3-30B-A3B-Instruct-2507` — 30.5B total / **3.3B activated**, 48 layers, 4 KV heads, **262,144 native**
  (same number as spark's `--max-model-len`, coincidentally symmetric with the pi-harness contract). Card:
  *"supports only non-thinking mode and does not generate `<|im_start|>` blocks; specifying
  `enable_thinking=False` is no longer required."* ⇒ **use this one.**
- `Qwen3-30B-A3B-Thinking-2507` — thinking-**only**. Wrong for a summarizer: it always pays reasoning tokens,
  MC's validator rejects "unusable output" ⇒ retries, and MC's `thinking_level` cannot disable thinking that is
  baked into post-training.
- Original `Qwen3-30B-A3B` — the hybrid toggle (`enable_thinking` / `/think`). Do not install: its text sibling is
  far stronger — MMLU-Pro **78.4 vs 69.1**, MMLU-Redux 89.3 vs 84.1, RULER avg **86.8 vs 72.0**.
- `Qwen2.5-Coder` sizes: 0.5/1.5/3/7/14/32B; **32,768 native** (128K–131K only via YaRN).
- `Qwen3-Coder-30B-A3B-Instruct` exists and **does** document a FIM mode — the "one weight for both" candidate.
  Caveat: its FIM path is a chat-template mode, not `<|fim_prefix|>` tokens, so it lands the friction on the
  latency-critical leg. Not chosen.

**Why a coder model is a defensible summarizer (and why the split still won):** the historian's failure mode in
our probes was *copy fidelity* (dropped identifiers), not reasoning — and code-trained models reproduce identifiers
verbatim better. But two things pushed to the split: (a) FIM is prefill-bound and the historian is decode-bound, so
one weight is the wrong shape for one of them; (b) **32,768 is the real limit, not the IQ** — see §5.

## 5. The two real risks in this plan

### 5.1 MC silently reroutes to spark while the VL is loaded

Plan assumption was "unload the 30B ⇒ historian idles." MC's documented chain says otherwise
([`CONFIGURATION.md`](https://github.com/cortexkit/magic-context/blob/master/CONFIGURATION.md) L478–483):
*"There is no built-in fallback chain…"* then *"if the configured primary fails (auth, transient, or returns
unusable output), the fallback order is: 1. explicit `fallback_models` … 2. **Historian only: your active session
model, as a last resort**."* The active session model is `spark/qwen3.8-flash-next`.

⇒ Most likely outcome: **the KV pool you were protecting gets spent on summarization, silently, with HTTP 200.**
⚠ That paragraph is framed around OMP block-precedence — **verify on the Pi harness**. The other possible outcome
is retry-and-fail → `Magic Context — history comparting needs attention`, history not summarized.
Choose deliberately: author `historian.pi.fallback_models: ["spark/qwen3.8-flash-next"]` if the fallback is
wanted, or accept the notice and rely on §5.2.

### 5.2 No-LLM relief lanes are what save the session

All deterministic, all riding a pass that is already busting:

| Lane | Mechanism (doc) |
|---|---|
| Age reclaim | drops old tool outputs ≥250 tokens outside the protected window; two-step watermark so it never surprises a pass |
| Heuristic cleanup | dedups repeated read-only tool results (newest kept full), strips injected system content |
| **Force band** `max(85%, execute_threshold + 2%)` | emergency drop to `fixedFloor + 0.30 × (ceiling − fixedFloor)` (~30% of working space); **one latched batch per continuous stay** |
| **Caveman compression** (opt-in, default **off**) | deterministic age-tiered compression of old user/assistant text, `lite`/`full`/`ultra`, **preserving code, paths and similar regions** |

Protected window default: `clamp(round(0.05 × usableSoft), min(16,000, round(0.08 × usableSoft)), 64,000)`.
End of the ladder: **at a provider-proven 95% with nothing folded, the turn is refused.**

⇒ **Turn `caveman_text_compression` on.** It is the designed no-LLM substitute for the historian, it preserves
exactly the identifier/path content our probes say is the payload, and it turns a VL window into a degraded period
instead of a cliff.

### 5.3 The 32k ceiling bites this workload specifically

`producer-window-guard.ts` refuses a prompt **before dispatch** (`producer_prompt_exceeds_window`) when prompt +
output reserve doesn't fit the usable window with a 3% margin; the reserve comes from `maxTokens` or the catalog,
capped at **25% of the context window**. Chunk size derives from the **main** model:
`trigger_budget = main_context × execute_threshold × 5%`, clamped `[5K, 50K]`, `min_clusters: 3`.
An over-large atomic component is **split at its largest result boundary with a truncation marker**.

⇒ With a 32k historian row: declare `contextWindow: 32768` honestly and set `historian.maxTokens` (~2048)
explicitly, or the reserve silently eats a quarter of the window. And on sessions full of Ansible /
`docker compose config` / playbook tails, 32k means **more truncation markers** — i.e. loss of exactly the payload
that matters. A 262k-context historian never hits this. This is the strongest argument for the split, and the
strongest argument against `Qwen2.5-Coder-3B` as a one-model answer.

## 6. Operational traps that transfer from the 7600 findings

1. **`pause` does NOT free VRAM** — compute only; the allocation is held until the process exits. "Unload the 30B"
   must be a real model unload / process exit.
2. **The `amdgpu` VRAM OOM is not graceful**, and there is no arbiter for two on-demand consumers on one card ⇒
   strictly ordered swap: **unload → confirm release → load VL.** Never start the second server optimistically.
3. **`--sleep-idle-seconds` verifiably returning VRAM is still unmeasured** — an open revisit condition on the
   7600 and never measured on the workstation (HD-401 gate 4 is carve-out/GTT). Measure it, and time the reload of
   a ~19 GB model (our 7600 analogue: "a 3–4 GB model from NVMe is seconds").
4. **Bus contention is shared and non-divisible.** Measured analogue on the 7600: **1.5–2×** co-residency
   contention. A historian run is ~20–40 s of bus-heavy work ⇒ FIM's 150–400 ms budget will degrade during it.
   Keep the historian server at `--parallel 1`; measure FIM latency *during* a historian run, not after.
5. **`.wslconfig` holds only `networkingMode=Nat`** ⇒ the guest's 27.2 GiB ceiling is an undocumented default
   sharing the same LPDDR5x pool the iGPU allocates from. Re-measure `vmmemWSL` at the end of a long session and
   pin `memory=` explicitly if it climbs (explicit-over-default, per the usual doctrine).

## 7. Doc defects this session surfaced (NOT yet corrected — no files were edited)

- [`docs/hardware-workstation.md`](../docs/hardware-workstation.md) §Platform claims **128 GB unified LPDDR5x**;
  measured **64.0 GB installed / 55.6 GB visible to Windows**. The section is honestly labelled
  *"owner-stated 2026-09-20, unverified"* and HD-401's own warning says every platform figure there is
  unmeasured — so this is a pre-flight gate firing correctly, not a doc bug.
- Same doc, §Memory & residency: *"Two resident models … inside 128 GB unified is not a ledger problem"* —
  re-derive at 55.6 GB. **Two** models fit with ~6 GB margin; **three** (FIM + 30B + VL) do not.
- Bandwidth "~256 GB/s class" and the community "~100 t/s on gfx1151" are both **unverified on this box**;
  reported 5600 MT/s implies less. If the ceiling is ~150–180 GB/s, expect ~60–75 t/s for the A3B (historian run
  ~35–50 s instead of ~20–35 s) — which is still fine for a batch leg, but re-do the FIM budget arithmetic on it.
- MC on Pi has two open upstream issues directly on this workload:
  [#224](https://github.com/cortexkit/magic-context/issues/224) transform degrades as messages accumulate
  (TUI lag) and [#225](https://github.com/cortexkit/magic-context/issues/225) `/clone` on a long session blows the
  window. Multi-week homelab sessions are exactly the trigger.

## 8. Gate before this becomes config

Do not treat any of the above as accepted until measured — the discipline is the one already used for
agentmemory and OpenViking, so the numbers stay comparable:

1. **Identifier-recall gate**, not vibes: run the existing probe question set against MC's compartments and report
   `hit@5` + exact-identifier recall + tokens-injected, same metric as
   [`../reports/probe-agentmemory-20260921.md`](../reports/probe-agentmemory-20260921.md).
2. **Refusal/truncation counters**: `producer_prompt_exceeds_window` and truncation-marker frequency from
   `$MAGIC_CONTEXT_LOG_PATH` and `/ctx-status`.
3. **Pi fallback-chain behaviour** (§5.1) — which model actually answers when the configured primary is dead.
4. **Unload/reload VRAM release + latency** (§6.3) before the VL swap becomes a routine.
5. **Bandwidth + t/s on this box** (§7) — HD-401's own gate 1–3 still stand.

Also still unresolved from §1: **which seat owns the long-lived session.** MC's store is per-machine and its pitch
is one session per project for months, and both the laptop and oldsrv carry this repo. That choice decides where
the store lives and which box needs the always-on summarizer; the model placement above is the laptop's answer,
not a fleet answer.

---

## 9. Correction applied 2026-09-28 — the §7 defect list was understated

The §7 entries came from a measurement pass that stopped at RAM. Re-measuring the SoC itself turned the finding
from "a stale number" into "the wrong machine":

| §Platform claim | Measured 2026-09-27 (Windows CIM, from the WSL seat) |
|---|---|
| `Ryzen AI MAX+ 395` (Strix **Halo**), iGPU `Radeon 8060S` | **`AMD Ryzen AI 9 HX PRO 370 w/ Radeon 890M`** — Strix **Point**, 12 C / 24 T, PCI `VEN_1002&DEV_150E`, driver `32.0.22024.19001` |
| 128 GB unified LPDDR5x | **64.0 GB** — 2 × 32 GB DDR5-5600 **SODIMM** (`FormFactor=12`, `TotalWidth=DataWidth=64`) |
| ~256 GB/s class, "same bandwidth class as spark's 273 GB/s" | dual-channel 128-bit DDR5-5600 ⇒ **≈89.6 GB/s peak** — ~2.9× below the claim, and not the soldered 256-bit LPDDR fabric the community figures were measured on |
| `gfx1151` | **unconfirmed** — AMD's matrix pairs `gfx1150` + `gfx1151` with no per-APU row; the recorded target was inherited from the wrong SoC |
| Windows + WSL2 | Win11 Pro + WSL2 `6.6.114.1-microsoft-standard-WSL2`, Debian 13 guest. **No `/dev/dri`, no `/dev/kfd`** ⇒ no native Vulkan and no native ROCm in any WSL distro, Docker included |

**What this does to the §4 decision.** The split itself stands — two legs with opposite bottlenecks, A3B for the
tolerant batch job — and the A3B-over-dense argument gets *stronger* on a narrower bus. What the correction
removes is the **margin**: at ~90 GB/s the FIM leg's 150–400 ms budget becomes the open question rather than a
formality (prefill is the compute-bound half, and this iGPU has 16 CU, not the 8060S's 40), and the historian run
should be budgeted at ~50–80 s instead of the ~20–35 s implied by 256 GB/s-class numbers. Both are still workable;
neither is promised until HD-401's bandwidth gate is measured on this box.

Applied in [`docs/hardware-workstation.md`](../docs/hardware-workstation.md) plus the two one-line repeats of the
wrong facts ([`docs/hardware.md`](../docs/hardware.md) roster, [`docs/index.md`](../docs/index.md) map).
Deliberately **not** applied: [`../todo.md`](../todo.md) / `todo-table.md` — HD-401's gate list and decision #28's
evidence row now need an owner pass, and a registry edit is its own change.
