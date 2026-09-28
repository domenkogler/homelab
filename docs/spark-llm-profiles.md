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
| `reasoning` | vLLM pinned fork · AWQ W4A16 + PLE **INT4** + MTP3 | `auto` (bf16) 16 GB pool = **~515.8k** token slots ≈ **1.97 ×** the 262,144 window | the certified S1 config; 3-rung load chain 2026-09-18 held 94.6 % of pool, 0 kernel OOM | **LIVE + certified** ([`spark/reports/stability/README.md`](../spark/reports/stability/README.md)) |
| `graded` | same weights/engine | **fp8** 16 GB pool ≈ **~1.03M** slots ≈ **3.9 ×** window (fp8 halves bytes/token) | graded thinking chains stop evicting each other at 4 concurrent sessions | authored, **uncertified** — fp8 KV "unvalidated on this hybrid+MTP build" ([§Unified-memory budget](#unified-memory-budget--oom-governance)) |
| `fast` | vLLM same fork · **NVFP4** (`primitive-ai mixed-NVFP4/FP8`) + PLE **NVFP4** sidecar + MTP3 | fp8 **16.5 GB** pool = ~1.063M slots = **4.06 ×** the window (≥ the 4 × 262,144 no-preemption bound, still under the 16 GiB ceiling) | the implementator lane: S2/S3 decode 40–46 tok/s expected; NVFP4 buys **decode speed**, not KV room (core ≈ 88.6 GB vs AWQ fixed cost 83.4 GB) | authored, **uncertified** — never benched here; NVFP4-vs-AWQ accuracy delta still unresolved ([`spark/resources/R2-nvfp4.md`](../spark/resources/R2-nvfp4.md) §B) |
| `fast-sglang` | **SGLang** · RadixArk NVFP4 | SGLang pool semantics (`--mem-fraction-static` / `--max-total-tokens`), not `--kv-cache-memory-bytes` | proves the *engine* swap is also one var | authored + **gate-blocked**: `spark_sglang_image` carries no digest, and `--ple-offload-embedding` **pins** the 51.2 GB FP8 table in host RAM = the 121.62 GiB pool on GB10 → 84 GB + 51.2 GB does not fit. The x86 recipe box is 96 GB **discrete** ([`spark/resources/R5-sglang-nvfp4-recipe-turbulent.md`](../spark/resources/R5-sglang-nvfp4-recipe-turbulent.md)) |

**Measured constants the arithmetic uses** (owner's numbers, not estimates — same basis as
[§Unified-memory budget](#unified-memory-budget--oom-governance)):
`spark_llm_kv_bytes_per_token` = 31,027 B/token at bf16/`auto` (the measured 30.3 KiB/token), 15,514
at fp8; `spark_llm_pool_ceiling_bytes` = 16 GiB in decimal bytes, the certified practical ceiling.
"4 × 262k" is therefore a *fp8 KV pool* claim (~16.3 GB), not a 1 M-context-per-session claim: a
single 1M session is out of reach on the certified 262,144 window.

### What the gate refuses (`IaC/ansible/roles/spark-llm-profile`, runs before `spark-artifacts`)

Read-only asserts, cheapest failure first, so a bad flip dies **before** a ~20-minute engine boot:
unknown profile name · unknown engine · **empty image pin** (a floating tag would violate
[CONVENTIONS.md](../CONVENTIONS.md) §7 — this is what blocks `fast-sglang` today) · KV pool smaller
than `max_model_len` · pool above the certified ceiling · CUDA-graph capture cap above `max_num_seqs`
(HD-380) · profile **not certified** without `spark_llm_allow_uncertified: true` · artifacts not
staged. It never downloads anything: big weights are an explicit
`--tags spark-artifacts -e spark_artifacts_fetch='[…]'` act, and the profile flip refuses until they
land (the `spark_artifact_sets` names in the catalogue are the opt-in list).

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

### Test loop (run it detached, boot is ~20 min)

`scripts/spark-llm-probe.py` reads the bearer from 1Password at runtime (never in argv/git) and reads
its expectations from the catalogue, so a probe cannot pass against a stale number:
`profile <name>` (local, no HTTP) → `health` → `reasoning` → `budget <n>` → `effort <level>` →
`ctx <tokens>` → `concurrent <n>` → `all --profile <name>`. The accuracy + needle gate for an
uncertified profile is [`spark/llm-profiles/README.md`](../spark/llm-profiles/README.md); the
operator handoff for the whole sequence is [`prompt-llm.md`](../prompt-llm.md).
