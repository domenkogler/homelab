## LLM serving profiles — one-var config switching (HD-469, 2026-09-28)

**The dial is `spark_llm_profile`** (`IaC/ansible/host_vars/spark.kogler.si.yml`) + one converge. The
catalogue `spark_llm_profiles` in `IaC/ansible/group_vars/spark.yml` is the SSOT for every engine
render key; the flat `spark_vllm_*` names stay as pass-throughs of the active profile because the
OOM watchdog reads two of them (`spark_vllm_memory_limit`, `spark_vllm_container`) and this doc has
always pointed at them. Names + live values: read the catalogue (`ansible_query.py --var
spark_llm_profiles`), never restate them here beyond the row that carries the *evidence*.

Every profile serves the **same client contract** — service `vllm-engine`, port
`spark_engine_port`, served id `spark/qwen3.8-flash-next`, bearer `spark-llm_api` (HD-370). Swapping
engine or quantization must not move any of those four, or every client breaks at once.

| Profile | Engine + weights | KV shape (measured constants below) | Sizing rationale | Status |
|---------|------------------|--------------------------------------|------------------|--------|
| `reasoning` | vLLM pinned fork · AWQ W4A16 + PLE **INT4** + MTP3 | `auto` (bf16) 16 GB pool = **515,679** token slots ≈ **1.97 ×** the 262,144 window | the certified S1 config; 3-rung load chain 2026-09-18 held 94.6 % of pool, 0 kernel OOM, worst `usable` **17.78 GiB** | **LIVE + certified** ([`spark/reports/hd469-reasoning/`](../spark/reports/hd469-reasoning/README.md) · [`spark/reports/stability/`](../spark/reports/stability/README.md)) — certification rests on the 2026-09-18 stability chain; the **under-cap baseline and gates 5–7 are still owed** (HD-469, see its row tail) |
| `graded` | same weights/engine | **fp8** 16 GB pool ≈ **876,664** slots ≈ **3.34 ×** window (fp8 = **1.70–1.89×**, NOT 2× — main K/V only) | graded thinking chains stop evicting each other at 4 concurrent sessions | **BLOCKED ON THE IMAGE PIN, measured 2026-09-28** — the pinned build's `qsa.py:70` declares `supported_kv_cache_dtypes = ["auto","bfloat16"]` and raises at :109/:188, so fp8 KV dies at EngineCore init ([evidence](../spark/reports/hd469-graded/README.md) · [image probe](../spark/reports/hd469-graded/image-probe-20260928.md)). Upstream merged it as vllm#55557 on 2026-09-16, after our tag's last push (2026-08-26); not in v0.30.0 either. Reaching it = engine-pin lane **HD-473** + re-cert, not a flip |
| `fast` | vLLM same fork · **NVFP4** (`primitive-ai mixed-NVFP4/FP8`) + PLE **NVFP4** sidecar + MTP3 | **`auto` (bf16)** — its fp8 half is HD-473's problem, so this profile measures ONE variable: the weights. 11 GB pool = **354,529** slots = **1.35 ×** window | the implementator lane: S2/S3 decode 40–46 tok/s expected; NVFP4 buys **decode speed**. The pool is SMALLER than `reasoning`'s on purpose: these weights are +≈5.2 GB heavier, and on GB10 that bill is paid out of the KV pool ([`R2-nvfp4.md`](../spark/resources/R2-nvfp4.md) §B) | staged + BOOTED 2026-09-29 (run #3: [`spark/reports/hd469-fast/`](../spark/reports/hd469-fast/README.md)) — engine printed `GPU KV cache size: 354,248 tokens, 1.35×`, `RestartCount=0`, so the DERIVED `fixed_cost_bytes` held; but **FAILS gate 3**: the profile's `VLLM_GDN_DECODE_KERNEL=triton` makes the plain mixed-NVFP4 build JIT-compile QSA/GDN kernels at inference and a 262k prefill 502s (60 s shm-broadcast timeout). **Stays uncertified** — rolled back to `reasoning` after the finding; the fix + re-cert is **HD-475** (drop the env for this build or pre-warm the shapes, then re-run gates 0–7, the accuracy battery, and gate 7 with the `/metrics` counters + sustained `clocks.sm` trace the first boot skipped) |
| `fast-sglang` | **SGLang** · RadixArk NVFP4 | SGLang pool semantics (`--mem-fraction-static 0.80` / `--max-total-tokens`), not `--kv-cache-memory-bytes`; the vendor's measured single-Spark pools are ~93k–174k tokens | proves the *engine* swap is also one var | authored + **gate-blocked** on three counts: no registry-verified arm64 digest (CONVENTIONS §7 — the only builds with support ≥ v0.5.20 + the #38121 loader are floating dev tags); the measured pool cannot hold our 262,144 window (closing it needs sglang fp8 KV = open PR #36644); and file-backed PLE (`--ple-offload-backend file`, #37068) needs a bind that is not wired yet. The vendor's own text confirms the arithmetic, including why plain `--ple-offload-embedding` does nothing on GB10 |

**Measured constants the arithmetic uses** (owner's numbers, not estimates — same basis as
[§Unified-memory budget](#unified-memory-budget--oom-governance)):
`spark_llm_kv_bytes_per_token` = 31,027 B/token at bf16/`auto` (the measured 30.3 KiB/token),
**18,251** at fp8 (= 31,027 / the worst measured 1.70×; the range across four upstream
measurements is 1.70–1.89×, because fp8 halves the main K/V and leaves the QSA indexer
side-caches + the GDN state in bf16 — a flat 2× over-promises by ~18 % and was the constant
this catalogue used until 2026-09-28). `spark_llm_pool_ceiling_bytes` = 16 GiB in decimal
bytes (the certified practical bf16 ceiling) and `spark_llm_device_hold_ceiling_bytes` =
104,113,000,000 B — MemTotal − 6.9 GiB held by OS/driver at engine start − the **17.78 GiB**
certified worst `usable` — which is what makes a weight change a POOL change.

"4 × 262k" was an *fp8 pool* claim built on the wrong constant; with the right one it fails
its own bound (≈905k, 3.45 ×), so no profile on this box claims four concurrent full
windows any more: `reasoning` and `fast` hold **1.97 ×** and **1.35 ×**, and four full
windows need fp8 KV, i.e. HD-473. **Never quote a projection where the engine prints the
number** — the authoritative pair is the boot log's `Available KV cache memory` +
`GPU KV cache size` lines, and `certified_evidence:` cites a report holding those, never a
calculated figure.

### What the gate refuses (`IaC/ansible/roles/spark-llm-profile`, runs before `spark-artifacts`)

Read-only asserts, cheapest failure first, so a bad flip dies **before** a ~20-minute engine
boot: unknown profile name · unknown engine · **empty image pin** (a floating tag would
violate [CONVENTIONS.md](../CONVENTIONS.md) §7 — this is what blocks `fast-sglang` today) ·
KV pool smaller than `max_model_len` · pool above the certified ceiling · **fixed cost + pool
above the host-floor ceiling** (the pool ceiling alone is blind to a profile that changed the
weights — `fast` fits 16 GiB of KV at NVFP4's weight cost and still walks the box into a
global OOM that Docker reports as `OOMKilled: false`) · CUDA-graph capture cap above
`max_num_seqs` (HD-380) · for SGLang: `--mem-fraction-static` > 0.80 (0.85 = DGX OS's
earlyoom threshold), `--max-total-tokens` below the advertised window, and
`--ple-offload-embedding` without `--ple-offload-backend file` · profile **not certified**
without `spark_llm_allow_uncertified: true` · artifacts not staged. It never downloads
anything: big weights are an explicit `--tags spark-artifacts -e
spark_artifacts_fetch='[…]'` act, and the profile flip refuses until they land (the
`spark_artifact_sets` names in the catalogue are the opt-in list).

**The gate is proven without the box.**
[`scripts/check_spark_llm_gate.py`](../scripts/check_spark_llm_gate.py) (validate-all item 22)
reads the role's own regexes + these constants, runs every profile, and breeds a canary per
invariant, refusing a canary that passes. Offline view of the whole matrix, one command,
no token: `python3 scripts/spark-llm-probe.py matrix`.

Parity guard for the certified lane: rendering `reasoning` produces a compose document **structurally
equal** to the pre-HD-469 template (old vs new render diffed), so a converge that does not change
`spark_llm_profile` does not recreate the running engine for cosmetic reasons.

### Client contract: the flip does NOT follow itself

The server var does not reach the harness. `contextWindow`/`max_tokens` live in
`scripts/pi-config/models-spec.yml` → `~/.pi/agent/models.json` (workstation), and each profile
carries the `client_context_window` that file must carry. A profile that serves a *smaller* window
while pi still sends a full-window conversation returns engine `400`s mid-session. Reasoning surface
is the same kind of split: the engine's own surface is measured in
[pi-harness.md](pi-harness.md) §2 (binary `enable_thinking` + `thinking_token_budget` honored;
top-level `reasoning_effort` accepted-and-**ignored**), so "graded reasoning" is client-side
per-level budgets until a profile proves otherwise — `scripts/spark-llm-probe.py effort high` is the
one command that re-measures it.

### Not a profile: Qwen3.8-27B is a SECOND served model, never a value of `spark_llm_profile`

Raised by the owner on 2026-09-28 ([SGLang's own 27B cookbook page](https://docs.sglang.io/cookbook/autoregressive/Qwen/Qwen3.8-27B)).
It is a dense hybrid-GDN **VL** model (`model_type: qwen3_5`, 27.78 B params, 64 layers = 48
linear-attention + 16 full-attention, GQA 24/4 @ head_dim 256, MTP head in-checkpoint, 262,144
native / 1 M extensible) and the only candidate whose **whole grid is measured on this box**: 80
configurations served on SM121/aarch64, each scored on the full 1319-question GSM8K (93.18–95.15 %;
the NVIDIA NVFP4 export 94.16–95.07 %).

* **Why it cannot be a profile:** serving a different model under `spark/qwen3.8-flash-next` voids
  every anchor HD-469 exists to protect — HD-376's depth proof, the reasoning-lane cert, the
  pi-harness 100-task score, and the AWQ/FP8/NVFP4 quality ladder. It is a second served model with
  its own cert, and on one 121.62 GiB pool the two cannot co-run.
* **Vendor-pinned constants (use these, do not re-derive):** `kv_bytes_per_token` = 16 attn layers ×
  4 KV heads × 256 × K+V = **32,768 B fp8 / 65,536 B bf16**; GDN state slot (48 × 48 × 128 × 128 +
  bf16 conv) = **153.9 MB fp32 / 78.4 MB bf16**; slots/request `S` = 5 (`extra_buffer`) / 4
  (`extra_buffer_lazy`) / 3 (`no_buffer`) / 1 (radix off); `D` = 4 verify states at MTP 3/1/4 (8 for
  DFLASH, 0 with spec off). The post-weight split between the worst-case-reserved **state pool** and
  the paged **KV pool** is `--mamba-full-memory-ratio`, default **0.9 = 90 % to KV**, which
  "over-provisions the KV pool and silently clamps concurrency".
* **The pool it buys on one Spark** at the page's `--mem-fraction-static 0.80` (= 102.4 GB static)
  minus weights, ~3 GB context/allocator, ~1.5 GB spec — **computed from those constants, NOT
  measured** (the page publishes no GB10 KV-pool size for this model):

  | checkpoint | weights | pools | KV @ fp8 | KV @ bf16 |
  |---|---|---|---|---|
  | NVFP4 (FP4 head) / NVIDIA export | 21.9 GB | ~76 GB | **~2.09 M tok** | ~1.04 M |
  | NVFP4 (BF16 head) | 25.1 GB | ~73 GB | ~2.0 M | ~1.0 M |
  | FP8 blockwise | ~28.5 GB | ~69 GB | ~1.9 M | ~0.95 M |
  | BF16 | ~55.6 GB | ~42 GB | ~1.16 M | ~0.58 M |

  One 262,144-token session = **8.59 GB** of KV at fp8 (17.18 GB bf16) + (S+D) × 153.9 MB of state
  ≈ 1.4 GB → **~10 GB ≈ 13 % of the NVFP4 pool**. Our AWQ lane today: 515,679 slots total =
  **1.97 ×** window, so one full-window session consumes ~half the box. **That gap — not decode
  speed, not accuracy — is the argument for this model**, and it is the same gap behind our
  0 %-prefix-hit re-prefill pain ([pi-harness.md](pi-harness.md): a 162 k-token session re-prefilling
  at 17,008 tok/s). 1 M context = 32.8 GB fp8 (fits the NVFP4/FP8 cells) but 65.5 GB bf16 (does not),
  so YaRN-to-1 M is fp8-KV-only and quality-unverified for our workloads either way.
* **Read the number, do not trust the arithmetic:** sglang's startup log (`max_total_num_tokens=`,
  `max_running_requests=`) is the authoritative readout — the RTX 5090 story on that page is exactly
  this failure mode (pool self-sized for 127,332 tokens against 9,216 needed, starving the state
  pool). `nvidia-smi` reports memory `Not Supported` on GB10; gate on `MemAvailable`.
* If it is ever taken up, it is its own lane: its own `client_context_window`, its own cert, its own
  served id, and an engine decision (the grid is a **SGLang** grid, and the pin problem in
  `fast-sglang` applies to it too — plus the binary/`reasoning_effort` surface differs per engine).

### Test loop (run it detached, boot is ~20 min)

`scripts/spark-llm-probe.py` reads the bearer from 1Password at runtime (never in argv/git) and reads
its expectations from the catalogue, so a probe cannot pass against a stale number. The two **local**
legs (`matrix`, `profile <name>`) touch the repo only — no HTTP, no vault, no token:
`matrix` → `profile <name>` (local, no HTTP) → `health` → `reasoning` → `budget <n>` →
`effort <level>` → `ctx <tokens>` → `concurrent <n>` → `all --profile <name>`. The accuracy + needle
gate for an uncertified profile is
[`spark/llm-profiles/README.md`](../spark/llm-profiles/README.md); the operator handoff for the whole
sequence is [`prompt-llm.md`](../prompt-llm.md). Timed legs (`ctx`, `concurrent`, anything feeding a
tok/s claim) must be run **from a session whose model is not spark** — see the gate README's rule 0.
