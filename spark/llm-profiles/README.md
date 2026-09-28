# Spark LLM profile gate — how a profile becomes certified

Part of [spark/README.md](README.md) · config: `IaC/ansible/group_vars/spark.yml`
`spark_llm_profiles` · subsystem doc: [docs/spark-llm-profiles.md](../../docs/spark-llm-profiles.md) ·
operator handoff: [prompt-llm.md](../../prompt-llm.md)

A profile starts **uncertified** and `roles/spark-llm-profile` refuses to converge it without
`spark_llm_allow_uncertified: true`. That flag is the cheap part. This file is the expensive part:
what a profile must *survive* before `certified: true` is set in the catalogue.

Why a bar at all: the box has one 121.62 GiB unified pool shared by weights, KV and the OS, and a
cold engine boot is ~20 min. A profile that "boots and answers one prompt" has proven nothing about
whether it will survive an agent session.

> **Measured 2026-09-28: fp8 KV cannot boot on the IMAGE we pin — which is not the same
> sentence as "this model cannot do fp8 KV", and the difference is the whole lane.** The
> engine dies at EngineCore init with
> `NotImplementedError: Qwen3.8-Flash-Next QSA requires a BF16 main KV cache`
> (`…/qwen3_8_flash_next/nvidia/qsa.py`, raise at :109 and :188, declaration at :70
> `supported_kv_cache_dtypes = ["auto", "bfloat16"]`). Upstream **merged** fp8 main KV on the
> QSA path as vllm **#55557** on **2026-09-16** — three weeks *after* the last push of our
> tag (2026-08-26, registry-verified) — reproduced it on GB10/sm_121, and the fp8 plumbing
> (`kv_quant_mode`) is already in our build. It is not in vLLM v0.30.0 either.
> So `graded` is blocked on an **engine pin + re-cert (todo.md HD-473)**, not on the model:
> do not re-attempt it against this pin, do **not** vendor the AGPL overlay patch, do **not**
> hand-edit a container's site-packages. Evidence:
> [`reports/hd469-graded/README.md`](../../spark/reports/hd469-graded/README.md) +
> [`image-probe-20260928.md`](../../spark/reports/hd469-graded/image-probe-20260928.md);
> re-derive both with `scripts/spark-fp8-image-probe.py` (read-only, ~40 s, no GPU).

> **Rule 0 — whose session may run this gate.** If the session executing the gate is itself
> served by `spark/…`, every tok/s, TTFT and TPOT it measures is contaminated by its own
> traffic (incident #6), and the deep legs compete with itself for the pool it is measuring.
> Context-capacity reads, `/metrics` counters, logs and `docker inspect` are fine; **timed
> numbers are not**. Hand the timed legs to a session on a different model, or take them
> from a headless run. Record which session ran which leg, in the report.


## Gate order (each step is a command, not a vibe)

| # | Gate | Command / measure | Pass = |
|---|------|-------------------|--------|
| 0 | Render parity | `python3 scripts/validate-docker-services.py --only spark-ai` + `spark-llm-probe.py matrix` + `profile <name>` + `check_spark_llm_gate.py` | renders; the slot/host-floor math the probe prints matches the profile's intent; the gate's own canaries still bite |
| 1 | Boot | converge **detached**, then `/health` | `healthy`, `RestartCount=0` after 30 min, **and** the engine's own `Available KV cache memory` + `GPU KV cache size` lines in the report (they outrank any projection) |
| 2 | Non-interference | `spark-llm-probe.py … health` + `reasoning` while the box is otherwise idle | both PASS, host `usable = MemAvailable − CmaFree` ≥ **17.78 GiB** (the certified worst moment, [`../spark/stability-test.md`](../spark/stability-test.md) §2 / [`reports/stability/README.md`](../spark/reports/stability/README.md)) — that number, not a rounded one, is what `spark_llm_device_hold_ceiling_bytes` is built from |
| 3 | Real depth | `spark-llm-probe.py … ctx <max_model_len>` | HTTP 200, `prompt_tokens` ≥ 80 % of the ask, no preemption in `/metrics` |
| 4 | Concurrency | `spark-llm-probe.py … concurrent <max_num_seqs>` | all 200s, and the slowest latency is within 3× the solo latency |
| 5 | Needle | the [pi-harness.md §3](../../docs/pi-harness.md) needle protocol at the profile's operating depth (≥ 90 % of window) | the needle is recalled correctly at depth, 3/3 |
| 6 | Accuracy | the same fixed 15-prompt local-knowledge + tool-call battery used for the AWQ 98/100 and NVFP4 91-vs-99 captures ([R2-nvfp4.md §B](../resources/R2-nvfp4.md)) | score within the profile's declared tolerance **and** the engine/effort/template are recorded with it (that capture's contradiction came from unrecorded confounds) |
| 7 | Memory curve | one working day of `spark-oom-watchdog` samples (`/mnt/spark_nvme/oom-watchdog/state/samples.csv`, `gpu_top_mib`) | no growth > 2 GiB/h under traffic that fails to return at idle — the C3 re-arm rule in [docs/hardware-spark.md](../../docs/hardware-spark.md) §Unified-memory budget. **This is also the gate that falsifies a DERIVED `fixed_cost_bytes`** (the `fast` profile's pool is sized against one) |

Two gates exist only for **KV-dtype / quantization changes**, because every published
measurement in this space was taken without our two load-bearing conditions:

| # | Gate | Command / measure | Pass = |
|---|------|-------------------|--------|
| 8 | **MTP acceptance, old dtype vs new** | read `vllm:spec_decode_*` from `/metrics` before and after, same prompt class, same clock regime | acceptance within noise. Every upstream "decode unchanged" fp8 measurement ran with **speculative decoding OFF**; our profiles run `spec_method: mtp`. Quantised K/V perturbs target and draft independently, they agree less often, and the lost draft positions ARE the decode loss — a −10 % acceptance is a finding worth more than the pool gain |
| 9 | **Quality vs the model's own noise floor** | `prompt_logprobs=1, temperature 0` per position; compare `new − old` against `old − old` from the SAME build | within the noise floor. A **needle run is not evidence** here (one 32k run measured 14 % vs 25 % miss, p = 0.67), and keep the long-reasoning battery: the reference fp8 implementation measured **6/6 → 2/6** on long reasoning while needles still passed, because quantised keys perturb *what the indexer selects* |

Gate 9 has a second caveat written into it: **every published fp8 measurement is on NVFP4 or
FP8 checkpoints — ours is AWQ W4A16.** The published quality evidence does not cover our
weights. (nvfp4 KV, ~3.06× pool, exists in the still-open #54846 with perplexity +0.37–0.59 %
and 6/12 vs 8/8 on near-1M aggregation. Do not open that axis on this lane.)

Only after 0–9: set `certified: true` + `certified_evidence:` (a link to the run artifacts under
`spark/reports/`, not prose) in the catalogue, drop `uncertified_reason`, and converge once so the
override is no longer needed. Gates 8–9 apply to dtype/quant changes; 0–7 apply to every profile.

## Artifacts a profile needs (explicit, never implicit)

```bash
cd IaC/ansible
ansible-playbook -i inventory.ini playbooks/spark.yml --limit spark --tags spark-artifacts \
  -e spark_artifacts_fetch='["b1-awq","ple-int4","nvfp4-mixed","ple-nvfp4"]'
```
Sets are named in `spark_artifact_sets`; a profile lists the sets it needs in `artifact_sets`.
`nvfp4-mixed` uses `kind: weights-trim`, which skips the checkpoint's own BF16 PLE table
(`exclude: ["ple-bf16-*"]`, 102.4 GB of the 191.0 GB repo) **and** trims the `ngram` entries out of
`model.safetensors.index.json` — without the trim vLLM asks for shards that were never fetched
(the primitive-ai recipe: [R1-ple-quant-card-evidence.md](../resources/R1-ple-quant-card-evidence.md)).

## Rollback

`spark_llm_profile: reasoning` + converge (detached). `reasoning` needs no override, its artifacts
are the ones already staged, and it is the only profile whose stability is certified — so rollback is
the same operation as switching, in the safe direction. If a profile leaves the container in a
restart loop, stop the loop before it eats the pool:
`docker update --restart=no vllm-qwen-spark && docker stop vllm-qwen-spark`, flip the var, converge.

## Known-truthy things that are NOT a pass

- `/health` 200 says the API server is up, not that the model loaded (it answers for a while before
  the weights+PLE load; `start_period: 1200s` exists because of that).
- A green **scoped** converge (`-e docker_services_scope=…`) is not evidence the render landed —
  measured 2026-09-19 ([scripts/rotate-spark-llm-key.sh](../../scripts/rotate-spark-llm-key.sh)
  header). Read the rendered compose or the container argv.
- `vllm bench serve` against the `--api-key` engine 401s every request **and exits 0** (HD-380).
  Assert on the counters, not the exit code.
- A 262k `max_model_len` in the render with a pool that cannot hold `max_num_seqs` sequences is
  a preemption generator, not a capacity win — gate 4 is what distinguishes them.
- A **projected** slot count (pool bytes ÷ bytes-per-token) is not a measurement. fp8 is
  1.70–1.89× on this model, not 2× — the constant that was in `group_vars/spark.yml` until
  2026-09-28 said 2× and over-promised every fp8 number by ~18 %. The engine's own
  `Available KV cache memory` / `GPU KV cache size` boot-log pair is the number of record.
- A clock regime that was never read is not a regime. Every timed number must carry
  `nvidia-smi --query-gpu=clocks.sm,clocks.max.sm` **at both ends** of the window: the box's
  `clockcap` role is IaC that has not been converged yet (as of 2026-09-28 the box reads
  `clocks.max.sm = 3003`, i.e. uncapped), and GB10 has no thermal lever to fall back on
  ([docs/hardware-spark.md](../../docs/hardware-spark.md) §GPU clock cap).
