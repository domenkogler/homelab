## LLM serving profiles — one-var config switching

**The dial is `spark_llm_profile`** (`IaC/ansible/host_vars/spark.kogler.si.yml`) + one converge. The
catalogue `spark_llm_profiles` in `IaC/ansible/group_vars/spark.yml` is the SSOT for every engine
render key; the flat `spark_vllm_*` names stay as pass-throughs of the active profile because the
OOM watchdog reads two of them (`spark_vllm_memory_limit`, `spark_vllm_container`). Names + live
values: read the catalogue (`ansible_query.py --var spark_llm_profiles`), never restate them here
beyond the row that carries the *evidence*.

Every profile serves the **same client contract** — service `vllm-engine`, port
`spark_engine_port`, served id `spark/qwen3.8-flash-next`, bearer `spark-llm_api`. Swapping
engine or quantization must not move any of those four, or every client breaks at once.

| Profile | Engine + weights | KV shape (measured constants below) | Sizing rationale | Status |
|---------|------------------|--------------------------------------|------------------|--------|
| `reasoning` | vLLM pinned fork · AWQ W4A16 + PLE **INT4** + MTP3 | `auto` (bf16) 16 GB pool = **515,679** token slots ≈ **1.97 ×** the 262,144 window | the certified S1 config; the 3-rung load chain holds 94.6 % of pool, 0 kernel OOM, worst `usable` **17.78 GiB** | **LIVE + certified** ([`spark/reports/hd469-reasoning/`](../spark/reports/hd469-reasoning/README.md) · [`spark/reports/stability/`](../spark/reports/stability/README.md)); the **under-cap baseline and gates 5–7 are still owed** |
| `graded` | same weights/engine | **fp8** 16 GB pool ≈ **876,664** slots ≈ **3.34 ×** window (fp8 = **1.70–1.89×**, NOT 2× — main K/V only) | graded thinking chains stop evicting each other at 4 concurrent sessions | **BLOCKED ON THE IMAGE PIN** — the pinned build's `qsa.py:70` declares `supported_kv_cache_dtypes = ["auto","bfloat16"]` and raises at :109/:188, so fp8 KV dies at EngineCore init ([evidence](../spark/reports/hd469-graded/README.md) · [image probe](../spark/reports/hd469-graded/image-probe-20260928.md)). Upstream merged fp8 KV as vllm#55557 after our tag was built; it is not in v0.30.0 either. Reaching it = an engine-pin change + re-cert, not a flip |
| `fast` | vLLM same fork · AutoRound **W4A16 AR-hybrid** + FP8 PLE **disk-mmap** + in-checkpoint MTP-3 with block rejection, `enforce_eager: true`, `spec{mtp,3,block,probabilistic}` | `auto` (bf16) 20 GB pool = **644,599** slots = **2.46 ×** window, 80,575 tokens/stream at the `max_num_seqs: 8` ceiling | the implementator lane: C2L decode **39.7 tok/s**, TTFT p50 ~0.7 s, ITL p50 ~65 ms, MTP accept 49–55 %, 0 preemptions | **LIVE + certified** on the 20 GB / seqs-8 shape ([`spark/reports/hd489-ar-blk/`](../spark/reports/hd489-ar-blk/README.md) · [`spark/reports/hd489-legs-20261006-1228/`](../spark/reports/hd489-legs-20261006-1228/RESULTS.md)); the catalogue's `certified_evidence` names the gates and the one battery re-run still owed |
| `fast-sglang` | **SGLang** · RadixArk NVFP4 | SGLang pool semantics (`--mem-fraction-static 0.80` / `--max-total-tokens`), not `--kv-cache-memory-bytes`; the vendor's measured single-Spark pools are ~93k–174k tokens | proves the *engine* swap is also one var | authored + **gate-blocked** on three counts: no registry-verified arm64 digest (CONVENTIONS §7 — the only builds with support ≥ v0.5.20 + the #38121 loader are floating dev tags); the measured pool cannot hold our 262,144 window (closing it needs sglang fp8 KV = open PR #36644); and file-backed PLE (`--ple-offload-backend file`, #37068) needs a bind that is not wired yet. The vendor's own text confirms the arithmetic, including why plain `--ple-offload-embedding` does nothing on GB10 |

**Measured constants the arithmetic uses** (owner's numbers, not estimates — same basis as
[§Unified-memory budget](#unified-memory-budget--oom-governance)):
`spark_llm_kv_bytes_per_token` = 31,027 B/token at bf16/`auto` (the measured 30.3 KiB/token),
**18,251** at fp8 (= 31,027 / the worst measured 1.70×; the range across four upstream
measurements is 1.70–1.89×, because fp8 halves the main K/V and leaves the QSA indexer
side-caches + the GDN state in bf16 — a flat 2× over-promises by ~18 %).
`spark_llm_pool_ceiling_bytes` = 16 GiB in decimal bytes (the certified practical bf16 ceiling)
and `spark_llm_device_hold_ceiling_bytes` = 104,113,000,000 B — MemTotal − 6.9 GiB held by
OS/driver at engine start − the **17.78 GiB** certified worst `usable` — which is what makes a
weight change a POOL change.

> ⚠ **Both terms behind that global ceiling are wrong for the AR-hybrid checkpoint.** The non-engine
> term is **4.93e9 B**, not 6.9 GiB, and the 17.78 GiB "worst usable" belongs to the AWQ/16 GiB lane.
> Measured on the box, `fast`'s real non-KV hold is **92.13e9 B**, so `fast` carries its own
> `device_hold_ceiling_bytes: 112.70e9` (measured: MemTotal − 4.93e9 − a 12 GiB WARN reserve), a named
> exception that leaves every other profile gated at 104,113,000,000. Re-deriving the global from the
> measured OS term is owed. Ledger: [hardware-spark.md](hardware-spark.md) §The fixed cost, MEASURED.

No profile on this box claims four concurrent full windows: `reasoning` and `fast` hold **1.97 ×** and
**2.46 ×**, and four full windows need fp8 KV. A "4 × 262k" claim is an fp8-pool claim built on the
flat-2× constant and it fails its own bound (≈905k, 3.45 ×). **Never quote a projection where the engine
prints the number** — with `--kv-cache-memory-bytes` the engine SKIPS memory profiling, so the
authoritative pair is the boot log's `Initial free memory` + `GPU KV cache size` lines (the
`Available KV cache memory` line only exists on the memory-profiling path, which this config does not
use), and `certified_evidence:` cites a report holding those, never a calculated figure.

### What the gate refuses (`IaC/ansible/roles/spark-llm-profile`, runs before `spark-artifacts`)

Read-only asserts, cheapest failure first, so a bad flip dies **before** a ~20-minute engine
boot: unknown profile name · unknown engine · **empty image pin** (a floating tag would
violate [CONVENTIONS.md](../CONVENTIONS.md) §7 — this is what blocks `fast-sglang` today) ·
KV pool smaller than `max_model_len` · pool above the certified ceiling · **fixed cost + pool
above the host-floor ceiling** (the pool ceiling alone is blind to a profile that changed the
weights — `fast` fits 16 GiB of KV at NVFP4's weight cost and still walks the box into a
global OOM that Docker reports as `OOMKilled: false`) · CUDA-graph capture cap above
`max_num_seqs` · for SGLang: `--mem-fraction-static` > 0.80 (0.85 = DGX OS's
earlyoom threshold), `--max-total-tokens` below the advertised window, and
`--ple-offload-embedding` without `--ple-offload-backend file` · profile **not certified**
without `spark_llm_allow_uncertified: true` · **a checkpoint that is not the checkpoint the
profile names**, and **a checkpoint/PLE-table combination that was never weighed** (both below)
· artifacts not staged. It never downloads
anything: big weights are an explicit `--tags spark-artifacts -e
spark_artifacts_fetch='[…]'` act, and the profile flip refuses until they land (the
`spark_artifact_sets` names in the catalogue are the opt-in list).

**The checkpoint ↔ PLE-table tie.** A profile names a checkpoint
(`model_subdir` + `models_root`) AND a PLE sidecar (`ple_host_subdir` + `ple_host_root`), and the
two coordinates are independent — so nothing structural says the table beside the weights is the
table those weights were built for. Two asserts close it:

| assert | what it reads | what it refuses |
|---|---|---|
| `spark_llm_checkpoints` + "the staged checkpoint is the checkpoint this profile names" | the staged `config.json`'s own `quantization_config` (`quant_method`, and `weight_format` for compressed-tensors builds) | a directory whose contents disagree with the name the profile gives it — the failure a per-profile `models_root` makes invisible |
| `spark_llm_ple_pairing` | the registry in `group_vars/spark.yml`, one entry per (table → checkpoint) with a graded basis: `CERTIFIED` · `MEASURED` · `UNVERIFIED` · `REFUSED` · `MEASURED-BAD` | an unweighed pair, an unregistered checkpoint, an ungraded basis, an arm whose pair is `REFUSED`/`MEASURED-BAD`, and a **certified** profile standing on an `UNVERIFIED` pair |

The registry, not a comment, holds the basis: `ple-table-fp8 ↔ Qwen3.8-Flash-Next-AWQ` is
`UNVERIFIED` — a pair that has never been weighed — and `models_root` is checked against the staged
`config.json` because a per-profile root can name a directory that does not exist (the AWQ weights are
staged on XFS; only the FP8 *table* legitimately lives on `/`).

**The gate is proven without the box.**
[`scripts/check_spark_llm_gate.py`](../scripts/check_spark_llm_gate.py) (validate-all item 22)
reads the role's own regexes + these constants, runs every profile, and breeds a canary per
invariant, refusing a canary that passes. Offline view of the whole matrix, one command,
no token: `python3 scripts/spark-llm-probe.py matrix`.

Parity guard for the certified lane: a render of `reasoning` is diffed against the render that served
before the profile dial existed and must stay **structurally equal**, so a converge that does not change
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

Reference: [SGLang's own 27B cookbook page](https://docs.sglang.io/cookbook/autoregressive/Qwen/Qwen3.8-27B).
It is a dense hybrid-GDN **VL** model (`model_type: qwen3_5`, 27.78 B params, 64 layers = 48
linear-attention + 16 full-attention, GQA 24/4 @ head_dim 256, MTP head in-checkpoint, 262,144
native / 1 M extensible) and the only candidate whose **whole grid is measured on this box**: 80
configurations served on SM121/aarch64, each scored on the full 1319-question GSM8K (93.18–95.15 %;
the NVIDIA NVFP4 export 94.16–95.07 %).

* **Why it cannot be a profile:** serving a different model under `spark/qwen3.8-flash-next` voids
  every anchor this catalogue protects — the depth proof, the reasoning-lane cert, the
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
  ≈ 1.4 GB → **~10 GB ≈ 13 % of the NVFP4 pool**. Our AWQ lane: 515,679 slots total =
  **1.97 ×** window, so one full-window session consumes ~half the box. **That gap — not decode
  speed, not accuracy — is the argument for this model**, and it is the same gap behind the
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
[`spark/llm-profiles/README.md`](../spark/llm-profiles/README.md). Timed legs (`ctx`, `concurrent`,
anything feeding a tok/s claim) must be run **from a session whose model is not spark** — see the gate
README's rule 0.

---

## 7. The ultra-fast funnel

Upstream [qwen3.8-Flash-DGX-UltraFast](https://github.com/dime-online/qwen3.8-Flash-DGX-UltraFast)
v16b (Apache-2.0, pinned `0c391a3` in `group_vars/all/versions.yml`) is **12 candidate
arms on this dial**, not a second stack.

**A profile NAMES things instead of hardcoding them** — `image: base|ultrafast|sglang`,
`models_root: xfs|os`, `ple_host_base: mount|models`, one PLE mechanism (`ple_overlay` XOR
`ple_mmap`). The compose template is the only place those names become paths, so a profile has
one representation and the gate can refuse a bad name with a remediation. Shared defaults live
in the `_x` merge anchor (keys starting with `_` are anchors, not profiles — the gate, the
checker, the probe and the render matrix all refuse to treat them as servable).

**The arms** (each is `certified: false` until it wins a leg; every loser is a row in
[services-ai-rejected.md](services-ai-rejected.md), and the reports under `spark/reports/hd489-*`
keep the raw evidence under their own names):

- **tier 1** `u1-patch` · `u2-blk` · `u3-s8` · `u4-pin` — the patch stack on the AWQ weights
  already staged on XFS: the control that says whether upstream's +15 % is the patches or the weights.
- **tier 1b** `nv-patch` — NVFP4 + patches, to see whether the patches rescue that quant.
- **tier 2** `ar-mmap` · `ar-blk` · `ar-dv` — upstream's AutoRound W4A16 hybrid + the FP8 PLE
  table served by mmap (`VLLM_PLE_MMAP=1`, 4.25 GB resident instead of ~48 GB in the pool).
- **tier 3** `v16b` · `v16b-s4` · `v16b-pin` — the recipe as published (`seqs=8`, piecewise
  CUDA graphs, T80 drafter, 65 536-id draft vocabulary), a seqs=4 control for the client
  contract, and the never-evict prompt pin.

**Winner: arm `ar-blk`, dial name `fast`** — the AutoRound-hybrid weights + FP8 PLE disk-mmap +
in-checkpoint MTP-3 with block rejection, `enforce_eager: true`, `spec{mtp,3,block,probabilistic}`.
C2L decode **39.7 tok/s** (`cold_ok=yes`, 324 s window), TTFT p50 ~0.7 s, ITL p50
~65 ms, MTP accept 49–55 %, 0 preemptions ([`spark/reports/hd489-ar-blk/`](../spark/reports/hd489-ar-blk/README.md)).
The `fast` name is the one the retired NVFP4 lane held; that lane is a rejected-log row.

**What `fast` renders**: pool **20 GB** (per-profile `pool_ceiling_bytes`, so the certified 16 GiB
global still binds every other profile) and `max_num_seqs: 8`. 20 GB is the largest pool the MEASURED
fixed cost leaves inside a 12 GiB reserve (`pool_max` = 20.64 GB): 644,599 slots = **2.46 ×** the
262,144 window, 80,575 tokens/stream at the seqs-8 ceiling. The engine's own boot line is the number
of record and it confirms the projection — `GPU KV cache size: 644,732 tokens, Maximum concurrency for
262,144 tokens per request: 2.46x` — with `--kv-cache-memory-bytes 20000000000` on the running
container, `restarts=0`, `/health` 200, and `usable` resting at **9.83–9.90 GiB**, inside the 12 GiB
WARN band and above CRIT ([hardware-spark.md](hardware-spark.md) §Unified-memory budget). A
certification that quietly inherits another shape's evidence is the failure mode this lane refuses, so
`certified_evidence:` names the shape each gate was taken on.

**Gate 4 at conc 8 is measured PASS on the live shape** (8/8 200s in 2.7 s,
[`spark/reports/hd489-overnight-20261006-0226/raw/g4-c8.log`](../spark/reports/hd489-overnight-20261006-0226/raw/g4-c8.log));
it is a short-prompt batch probe, so it proves the batch shape serves and stays in budget, not
throughput under batch. What the live shape still owes is one re-run of the **gate 6** accuracy battery
together with its baseline, and the host-floor re-derive — the catalogue's `certified_evidence` is the
ledger for both.

**Measured on the winner's shape** ([`spark/reports/hd489-overnight-20261006-0226/`](../spark/reports/hd489-overnight-20261006-0226/RESULTS.md)):

* **The needle at depth: PASS 3/3.** The pi global-instructions marker (`pi-agent/AGENTS.md`, 552 tok,
  needle seq 550) planted at ~90 % depth of a **241.2k-token** filler (92 % of the 262,144 window) is
  recalled verbatim 3/3, judged by the token-subsequence rule with the engine's own tokenizer in the
  container (each response 553 tok). `num_preemptions_total` delta **+0** across all six 236–241k legs.
* **Quality vs `reasoning`, paired McNemar** on the owner's 5-category MMLU-Pro-mini subset (500 items,
  100 % `question_id`-paired): `fast` **89.20 %** vs `reasoning` **89.40 %**, Δ = −0.20 pts, p = 1.000
  (discordant 9/10, n = 500) ⇒ **no measurable quality deficit; the `fast` speed win stands.**
* **The AWQ quality fallback costs ~30 %**: eager AWQ + FP8-PLE-mmap boots healthy at 14 GB (engine's own
  KV 450,604 tok = 1.72×) and decodes C2L **27.6 tok/s** vs `fast`'s 39.7 (inside the predicted 22–28
  band, above the 23.6 with-graphs ceiling); TTFT p50 ~0.82 s, ITL p50 ~91 ms, MTP accept 46–53 %,
  0 preemptions. The pairing registry row `ple-table-fp8 ↔ Qwen3.8-Flash-Next-AWQ` stays `UNVERIFIED` —
  its accuracy / MTP-acceptance / quality-noise-floor gates were declined.
* **The `ple_dispatch` knobs are constitutive, not dialable**: `ar-blk-lean` — the same checkpoint and
  table without that env — dies at the first safetensors shard (`AttributeError:
  'MergedColumnParallelLinear' object has no attribute 'data'`,
  [`spark/reports/hd489-legs-20261006-1228/raw/b9-crash.txt`](../spark/reports/hd489-legs-20261006-1228/raw/b9-crash.txt)),
  so "what the knobs cost" is unmeasurable by deletion and the 39.7 tok/s win stands as-is.
* **No cliff** from a cold page cache (~20 % decode/ITL penalty, no collapse) or a co-resident allocator
  (~20 % decode contention, ITL p50 flat at ~65 ms, tail-only p95 ~2×; no preemption, no OOM, no
  stranding).
* spark's LLM histograms are **live** in VictoriaMetrics. The strict `req_ok_delta == N` cold-scrape
  exclusivity cannot certify even a quiet leg exactly (10/12 seen) — treat it with its logged source.

**Why the arms live on `/`**: XFS holds 505 GB of certified weights plus two candidates nobody wants to
re-download (185 G free), so `spark_models_dir_os: /opt/homelab/models` takes the ~130 GB AR-hybrid
checkpoint and the FP8 table; the root partition measures 345 G free. The gate asserts a 150 GB floor on
that partition before an `os`-rooted arm boots.

**The never-evict prompt pin is authored, gated and empty.** `spark_llm_never_evict_prompt` in
`group_vars/spark.yml` is the ONE value (the operator's pi global-instructions text, inlined because the
offline render gate mocks `lookup()` and would happily render `<secret:file>` green), aliased by **every**
profile as `*nev`, with `spark_llm_never_evict_max_fraction` as the shared cap. It is `""` because the
mechanism is [rejected](#never-evict-prompt-pin--rejected); the alias, the cap and both asserts are kept so
a re-decide is one line in one place. Two facts came out of wiring it:

* the compose template must pass the value through `| to_json`. Passing it as `"'" ~ prompt ~ "'"` puts
  the quote characters inside the argv string: the engine matches `'<text>'`, finds nothing, and the pin is
  an invisible no-op while the flag still renders. `| to_json` is also the only form that survives a
  multi-line value in the `- {{ a }}` emission, and `scripts/spark-llm-render-matrix.py` asserts the
  rendered argument is BYTE-EQUAL to the declared text.
* proof of a pin is prefix-cache hits from `/metrics` across a real session — a synthetic bench never
  engages it.

An arm with an intentionally unfilled input (`spark_vllm_ultrafast_image`, a `never_evict` needle) makes
`roles/spark-llm-profile` REFUSE the profile; `scripts/spark-llm-render-matrix.py` and
`scripts/check_spark_llm_gate.py` print it as `GATED` rather than letting an authored-but-unrunnable arm
read as either green or broken. `spark_vllm_ultrafast_image` is pinned in `versions.yml` to the built image
`sha256:4900c13e…` (built from iter6c `sha256:54759ef1…` on the pinned base `sha256:fc120ece…`).

**What upstream does NOT change**: it runs `--kv-cache-dtype auto`, so `fp8` KV and `graded`
stay blocked here, and its `gpu_mem=0.01` measures the PLE table leaving the CUDA pool — it is
not headroom for a bigger pool. Do not quote it as such.

### The timed instrument

The timed legs of this funnel run through [`spark/bench/run-scenario.sh`](../spark/bench/run-scenario.sh),
which drives `vllm bench serve` inside the engine container and writes one CSV row per leg (TTFT and ITL
p50/p99, per-stream decode tok/s, MTP acceptance, preemption/generation-token deltas, Wh per 1k output
tokens, arm identity via `--profile`, the Rule-0 client stamp via `--client`). Around it:
`snapshot-metrics.sh` (before/after `/metrics`), `vm-window.sh` (the VictoriaMetrics cross-check and the
only way to attribute a series to a leg), `stress-oom.sh`, `stability-overnight.sh`, `accuracy-gate.sh`.

There is no `scripts/llm_serving_bench.py` and no `spark/llm-profiles/acceptance/`. **A tool no index
reaches does not exist for the next reader**, which is why `docs/index.md`, `scripts/README.md`
§Adjacent tooling and this section all name `spark/bench/`; a search that stops at `scripts/` is not an
absence proof.

### Never-evict prompt pin — REJECTED

`--never-evict-kv-cache-prompt-includes <text>` (up to `--never-evict-kv-cache-max-fraction` of the
pool) pins the KV blocks of every prompt CONTAINING that text. **Off in every profile and every arm**
— `spark_llm_never_evict_prompt: ""`; the compose `{% if %}` therefore renders neither flag.

What closes it is the engine's own instrumentation: `log_never_evict_pin()` prints `[never-evict]
holding …` only when `reserved > 0` (the boot-time `armed:` line is not match evidence) and it never
prints, so the pin reserves nothing; `num_preemptions_total` is **0**; prefix caching already serves
**95.1 %** of prompt tokens, with a recomputed share of **4.9 %** against the **3.70 % (24 h) /
4.57 % (7 d)** baseline; and the needle — the operator's pi global instructions — appears in no request,
because the client serving this box (WSL pi) loads no `AGENTS.md`. Counter values, commands and the
attribution checks are in
[`spark/reports/hd489-never-evict-off/README.md`](../spark/reports/hd489-never-evict-off/README.md).

The causal agent is the **pool**, not the pin: 20 GB = 2.46 × the 262,144-token window is what lets a
long session keep its own prefix resident — more than the two concurrent full-window sessions a working
day actually runs. The mechanism is not free: pinned blocks leave `get_num_free_blocks()`, which drives
admission control, so up to 25 % of the pool (142 of 569 blocks ≈ 0.20 M tokens ≈ 0.77 × one window) can
be held out for one prompt shape, to the benefit of the client that matches the marker and the cost of
every other stream sharing the GPU. The pin is single-slot: each matching request **replaces** the pinned
set, so concurrent sessions evict each other's pin — a second reason it is the wrong tool for a
mixed-traffic box.

**The lineage rule.** The patch exists ONLY in the built ultrafast lineage: `4900c13e…` declares the pair
in `vllm/engine/arg_utils.py`, `config/cache.py` and `v1/core/block_pool.py`; the pinned base
`fc120ece…` (vLLM `0.1.dev20073+g8e685d198`) has **no such argument** — a profile on `image: base` with a
non-empty pin writes argv `api_server` cannot parse, which exits at parse and puts the container in a
Docker restart-loop while every gate stays green. So:

* `spark_llm_never_evict_capable_images: [ultrafast]` is the SSOT for which lineage may carry the
  flag, and both `roles/spark-llm-profile` and `scripts/check_spark_llm_gate.py` refuse a non-empty
  pin anywhere else (canary-proven); `scripts/spark-llm-render-matrix.py` fails a render that puts
  the flag on an uncapable image.
* A needle is matched as a **token subsequence** (`tokenizer.encode(marker)` minus the first and
  last token, then `_contains_subseq` over the prompt) — all-or-nothing, no partial matching: one
  edited character anywhere in a multi-file concatenation stops the whole pin, silently, while the
  boot log still prints `armed`.

**Re-arm conditions** (a re-decide needs an exception note per §8.3): a needle proven to be a
byte-substring of a prompt a REAL session sends (not a synthetic bench), on a lineage listed in
`spark_llm_never_evict_capable_images`, with the before/after read off
`prompt_tokens_by_source` + `num_preemptions_total` across matched windows. Re-open it if the
recomputed share climbs past ~10 % or a preemption appears.
