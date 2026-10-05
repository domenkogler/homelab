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

> ⚠ **Both constants in that ceiling are now known to be wrong for the AR-hybrid checkpoint, and
> HD-494 measured by how much** (2026-10-05): the non-engine term is **4.93e9 B**, not 6.9 GiB, and
> the 17.78 GiB "worst usable" belongs to the AWQ/16 GiB lane. Measured on the box, `fast`'s real
> non-KV hold is **92.13e9 B**, not the 76.3e9 its boot log implied — which is how a 25 GB pool
> passed this gate while the host had no reserve at all. `fast` therefore carries its own
> `device_hold_ceiling_bytes: 112.70e9` (measured: MemTotal − 4.93e9 − a 12 GiB WARN reserve), a
> named exception that leaves every other profile gated at 104,113,000,000. Re-deriving the global
> from the measured OS term is owed. Ledger: [hardware-spark.md](hardware-spark.md) §The fixed
> cost, MEASURED.

"4 × 262k" was an *fp8 pool* claim built on the wrong constant; with the right one it fails
its own bound (≈905k, 3.45 ×), so no profile on this box claims four concurrent full
windows any more: `reasoning` and `fast` hold **1.97 ×** and **1.35 ×**, and four full
windows need fp8 KV, i.e. HD-473. **Never quote a projection where the engine prints the
number** — with `--kv-cache-memory-bytes` the engine SKIPS memory profiling, so the
authoritative pair is the boot log's `Initial free memory` + `GPU KV cache size` lines
(the `Available KV cache memory` line only exists on the memory-profiling path, which this
config does not use), and `certified_evidence:` cites a report holding those, never a
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

---

## 7. The ultra-fast funnel (HD-489)

Upstream [qwen3.8-Flash-DGX-UltraFast](https://github.com/dime-online/qwen3.8-Flash-DGX-UltraFast)
v16b (Apache-2.0, pinned `0c391a3` in `group_vars/all/versions.yml`) arrives as **12 candidate
arms on this dial**, not as a second stack. Lane brief: [../prompt-remaining-bench.md](../prompt-remaining-bench.md)
(the funnel itself is measured and closed; the tail is what is left).

**A profile now NAMES things instead of hardcoding them** — `image: base|ultrafast|sglang`,
`models_root: xfs|os`, `ple_host_base: mount|models`, one PLE mechanism (`ple_overlay` XOR
`ple_mmap`). The compose template is the only place those names become paths, so a profile has
one representation and the gate can refuse a bad name with a remediation. Shared defaults live
in the `_x` merge anchor (keys starting with `_` are anchors, not profiles — the gate, the
checker, the probe and the render matrix all refuse to treat them as servable).

**Tiers** (each arm is `certified: false` until it wins a leg):

- **tier 1** `u1-patch` · `u2-blk` · `u3-s8` · `u4-pin` — the patch stack on the AWQ weights
  already staged on XFS. Cheapest to test, and the control that says whether upstream's +15 %
  is the patches or the weights.
- **tier 1b** `nv-patch` — NVFP4 + patches, to see whether the patches rescue that quant.
- **tier 2** `ar-mmap` · `ar-blk` · `ar-dv` — upstream's AutoRound W4A16 hybrid + the FP8 PLE
  table served by mmap (`VLLM_PLE_MMAP=1`, 4.25 GB resident instead of ~48 GB in the pool).
- **tier 3** `v16b` · `v16b-s4` · `v16b-pin` — the recipe as published (`seqs=8`, piecewise
  CUDA graphs, T80 drafter, 65 536-id draft vocabulary), a seqs=4 control for the client
  contract, and the never-evict prompt pin.
- **tier 4** — certification of whatever survives; the rest is deleted.

**The winner's name is `fast`, not `ar-blk` (2026-10-03, owner decision).** `spark_llm_profile` is
`fast`, and the name was taken from the retired NVFP4 lane (now a rejected-log row, superseded by
HD-475 if anyone ever wants that quant back). Everything above this line keeps the funnel's
historical arm names — the reports under `spark/reports/hd489-*` are dated evidence and are not
> ✅ **Deployed 2026-10-05 14:26 CEST.** The engine's own boot line is the number of record and it confirms the projection: > `GPU KV cache size: 644,732 tokens, Maximum concurrency for 262,144 tokens per request: 2.46x` against a projected 644,599 (0.02 % off), > with `--kv-cache-memory-bytes 20000000000` on the running container, `restarts=0`, `/health` 200, and `MemAvailable` 21.4 GB at rest where the > 25 GB shape rested at 7.9 GB. Gate 4 at conc 8 and gate 5 are owed again on this shape (both were taken at 25 GB) — `fast`'s > `certified_evidence` says so, and a certification that quietly inherits the previous shape's evidence is the failure mode §7 refuses.

renamed. What `fast` renders today differs from the arm that won: pool **`20 GB`** (per-profile
`pool_ceiling_bytes`, so the certified 16 GiB global still binds every other profile) and
`max_num_seqs: 8`. It stepped up to 25 GB on 2026-10-03 and back down to 20 GB on **2026-10-05
(HD-494)**: 25 GB bought 0.61 extra windows and cost the host its entire reserve — `usable` RESTED
at 7.76-7.99 GiB and the watchdog restarted the engine for a steady state, not an incident
([spark-incidents.md](spark-incidents.md) §Incident #9). 20 GB is the largest pool the MEASURED
fixed cost leaves inside a 12 GiB reserve (`pool_max` = 20.64 GB): 644,599 slots = 2.46 × the
262,144 window, 80,575 tokens/stream at the seqs-8 ceiling — and it is the shape 05012de booted
clean with gates green.

Gate 4 at conc 8 on the 25 GB shape is **measured PASS**
(`spark/reports/hd489-overnight-20261004-0804/raw/g4-c8.log` — 8/8 200s in 3.0 s, 2.7 s median); it
is a short-prompt batch probe, so it proves the batch shape serves and stays in budget, not
throughput under batch. The 20 GB revert re-opens that leg (it was taken at 25 GB), and what the
shape still owes either way is **gate 5 (the needle at depth)** and a working day of watchdog
`usable` samples.

**Why the arms live on `/`**: XFS had 185 G free and holds 505 GB of certified weights plus
two candidates nobody wants to re-download. The root partition measured 345 G free
(2026-10-02), so `spark_models_dir_os: /opt/homelab/models` takes the ~130 GB AR-hybrid
checkpoint and the FP8 table. **Nothing was deleted to make room**, and the gate asserts a
150 GB floor on that partition before an `os`-rooted arm boots.

**Two gates were open on purpose; both are closed now.** `spark_vllm_ultrafast_image` was empty
until a human recorded the ID the build prints — **closed 2026-10-02**: `versions.yml:311` pins
the built image `sha256:4900c13e…` (built from iter6c `sha256:54759ef1…` on the pinned base
`sha256:fc120ece…`). The other was `v16b-pin`'s `never_evict_prompt` — **closed 2026-10-03** by
removing it as a per-arm choice altogether: `spark_llm_never_evict_prompt` in `group_vars/spark.yml`
is now the ONE value (the operator's pi global-instructions text, inlined because the offline render
gate mocks `lookup()` and would happily render `<secret:file>` green), aliased by **every** profile as
`*nev`, with `spark_llm_never_evict_max_fraction` as the shared cap and `u4-pin`/`v16b-pin` keeping
their recorded `0.03` override. **That ONE value is EMPTY since 2026-10-05 — the mechanism was
measured and rejected** ([§Never-evict prompt pin — REJECTED](#never-evict-prompt-pin--rejected-2026-10-05));
the alias, the cap and both asserts are kept so a re-decide is one line in one place. Two things
came out of wiring it:

* the compose template passed the value as `"'" ~ prompt ~ "'"`, so **argv received the quote
  characters inside the string** — the engine matched `'<text>'`, found nothing, and the pin was an
  invisible no-op. It is `| to_json` now, which is also the only form that survives a multi-line
  value in the `- {{ a }}` emission. `scripts/spark-llm-render-matrix.py` asserts the rendered
  argument is BYTE-EQUAL to the declared text (presence was never the risk; the flag rendered).
* what the pin is worth was UNMEASURED for two days — `u4-pin`/`v16b-pin` both measured a synthetic
  bench that never engages it, so the honest claim was "authored, gated, rendering, unproven".
  Proof = prefix-cache hits from `/metrics` across a real session, never another synthetic leg
  (§6 rule). **Measured 2026-10-05 on live sessions: it buys nothing here → REJECTED**
  ([§Never-evict prompt pin — REJECTED](#never-evict-prompt-pin--rejected-2026-10-05)).

Both made `roles/spark-llm-profile` REFUSE the profile; `scripts/spark-llm-render-matrix.py` and
`scripts/check_spark_llm_gate.py` print them as `GATED` rather than letting an authored-but-unrunnable
arm read as either green or broken.

**What upstream does NOT change**: it runs `--kv-cache-dtype auto`, so `fp8` KV and `graded`
stay blocked here, and its `gpu_mem=0.01` measures the PLE table leaving the CUDA pool — it is
not headroom for a bigger pool. Do not quote it as such.

**Delivery surface for this lane** (the leg report is ephemeral; CONVENTIONS §audit reports):
raw evidence per leg in `spark/reports/HD-489/` — bench JSON, the engine's own
`Initial free memory` + `GPU KV cache size` lines, per-pid GPU memory at rest, the
accepted-length trace (including the Slovenian set), the pinned image ID + build report.
Durable findings fold into
[hardware-spark.md](hardware-spark.md) §Bench + engine selection (measured numbers),
[services-ai.md](services-ai.md) §9 (client-facing numbers),
[services-ai-rejected.md](services-ai-rejected.md) (one paragraph per retired arm + the number
that killed it), [spark/llm-profiles/README.md](../spark/llm-profiles/README.md) (the gate ladder, 0–9 — evidence for whatever turns
`certified: true`) — and the todo row is deleted when the lane closes live, not before.

### The timed instrument (a correction that cost a lane, 2026-10-02)

The timed legs of this funnel run through [`spark/bench/run-scenario.sh`](../spark/bench/run-scenario.sh),
which drives `vllm bench serve` inside the engine container and writes one CSV row per leg (TTFT and ITL
p50/p99, per-stream decode tok/s, MTP acceptance, preemption/generation-token deltas, Wh per 1k output
tokens, arm identity via `--profile`, the Rule-0 client stamp via `--client`). Around it:
`snapshot-metrics.sh` (before/after `/metrics`), `vm-window.sh` (the VictoriaMetrics cross-check and the
only way to attribute a series to a leg), `stress-oom.sh`, `stability-overnight.sh`, `accuracy-gate.sh`.

Two absences were asserted from a `scripts/`-only search and both were false — there is no
`scripts/llm_serving_bench.py` and no `spark/llm-profiles/acceptance/`, and the follow-on claim that
"the repo has no timed-throughput tool" was wrong the same way. **A tool no index reaches does not exist
for the next reader**, which is why `docs/index.md`, `scripts/README.md` §Adjacent tooling and this
section all name `spark/bench/`; a search that stops at `scripts/` is not an absence proof.

**Winner: arm `ar-blk`, dial name `fast`** — the AutoRound-hybrid weights + FP8 PLE disk-mmap +
in-checkpoint MTP-3 with block rejection, `enforce_eager: true`, `spec{mtp,3,block,probabilistic}`.
Measured 2026-10-03: C2L decode **39.7 tok/s** (cold_ok=yes, 324 s window), TTFT p50 ~0.7 s, ITL p50
~65 ms, MTP accept 49–55 %, 0 preemptions ([`spark/reports/hd489-ar-blk/README.md`](../spark/reports/hd489-ar-blk/README.md)).
It is `certified: true` on the 16 GB / seqs-4 shape (gates 3–4 measured, `hd489-tail-b2`/`-b3`) and on the
25 GB / seqs-8 shape it runs today (gate 4 at conc 8, `hd489-overnight-20261004-0804`); what no
certificate covers is **gate 5 — the needle at depth**, owed for the whole box since HD-469.

### Never-evict prompt pin — REJECTED (2026-10-05)

`--never-evict-kv-cache-prompt-includes <text>` (up to `--never-evict-kv-cache-max-fraction` of the
pool) pins the KV blocks of every prompt CONTAINING that text. It was authored as the answer to the
"~0 % prefix-hit re-prefill every long session pays" note. **Decision: off, all profiles, all arms**
— `spark_llm_never_evict_prompt: ""`; the compose `{% if %}` therefore renders neither flag.

What killed it is the engine's own instrumentation, read on the live box over 13 h of real pi
sessions after the 2026-10-04 22:16 UTC boot: the `[never-evict] holding …` line never printed, so the
pin reserved nothing (`log_never_evict_pin()` prints only when `reserved > 0`; the boot-time `armed:`
line is not match evidence); `num_preemptions_total` **0**; prefix caching already served **95.1 %** of
prompt tokens; recomputed share **4.9 %** against the pre-pin **3.70 % (24 h) / 4.57 % (7 d)** baseline;
and the needle — the operator's pi global instructions — appeared in no request, because the client
serving this box (WSL pi) loads no `AGENTS.md`. Counter values, commands and the attribution checks are
in [`spark/reports/hd489-never-evict-off/README.md`](../spark/reports/hd489-never-evict-off/README.md).

The causal agent was the **pool**, not the pin: 25 GB = 3.08 × the 262,144-token window is what lets
a long session keep its own prefix resident. (The pool is 20 GB = 2.46 × since HD-494 on 2026-10-05
— still more than the two concurrent full-window sessions the owner's day actually runs, and the
measurement that retired the pin stands: it was capacity doing the work, not the flag.) And the
mechanism is not free — pinned blocks leave
`get_num_free_blocks()`, which drives admission control, so up to 25 % of the pool (142 of 569
blocks ≈ 0.20 M tokens ≈ 0.77 × one window) can be held out for one prompt shape, to the benefit of
the client that matches the marker and the cost of every other stream sharing the GPU.

**The lineage rule (this is what actually burned the box).** The patch exists ONLY in the built
ultrafast lineage: `4900c13e…` declares the pair in `vllm/engine/arg_utils.py`, `config/cache.py`
and `v1/core/block_pool.py`; the pinned base `fc120ece…` (vLLM `0.1.dev20073+g8e685d198`) has **no
such argument**. When the 2026-10-03 "ONE value for every profile" change aliased the pin into
`reasoning`/`graded` (`image: base`), a flip to `reasoning` wrote argv `api_server` cannot parse →
exit at parse → Docker restart-loop, **`restarts=105`** before the overnight run restored `fast`
(evidence: [`spark/reports/hd489-overnight-20261004-0804/`](../spark/reports/hd489-overnight-20261004-0804/README.md)). The gate was green the whole time,
because nothing compared the flag to the image. So:

* `spark_llm_never_evict_capable_images: [ultrafast]` is the SSOT for which lineage may carry the
  flag, and both `roles/spark-llm-profile` and `scripts/check_spark_llm_gate.py` refuse a non-empty
  pin anywhere else (canary-proven); `scripts/spark-llm-render-matrix.py` fails a render that puts
  the flag on an uncapable image.
* A needle is matched as a **token subsequence** (`tokenizer.encode(marker)` minus the first and
  last token, then `_contains_subseq` over the prompt) — all-or-nothing, no partial matching: one
  edited character anywhere in a multi-file concatenation stops the whole pin, silently, while the
  boot log still prints `armed`.
* The pin is single-slot: each matching request **replaces** the pinned set, so concurrent sessions
  evict each other's pin — a second reason it is the wrong tool for a mixed-traffic box.

**Re-arm conditions** (a re-decide needs an exception note per §8.3): a needle proven to be a
byte-substring of a prompt a REAL session sends (not a synthetic bench), on a lineage listed in
`spark_llm_never_evict_capable_images`, with the before/after read off
`prompt_tokens_by_source` + `num_preemptions_total` across matched windows. Re-open it if the
recomputed share climbs past ~10 % or a preemption appears.
