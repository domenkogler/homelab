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

> **Measured 2026-09-28 (HD-469 cert): fp8 KV CANNOT boot on Qwen3.8-Flash-Next.** The engine
> dies at EngineCore init with
> `NotImplementedError: Qwen3.8-Flash-Next QSA requires a BF16 main KV cache`
> (`vllm/models/qwen3_8_flash_next/nvidia/qsa.py:187`) — the hybrid model's QSA (sparse attention)
> layer hard-requires a BF16 main KV cache. So the `graded` profile (fp8 KV) is architecturally
> impossible on this model/build. Do not re-attempt fp8 KV here without a model/engine change;
> evidence: [`spark/reports/hd469-graded/README.md`](../../spark/reports/hd469-graded/README.md).

## Gate order (each step is a command, not a vibe)

| # | Gate | Command / measure | Pass = |
|---|------|-------------------|--------|
| 0 | Render parity | `python3 scripts/validate-docker-services.py --only spark-ai` + `spark-llm-probe.py profile <name>` | renders, and the KV-slot math the probe prints matches the profile's intent |
| 1 | Boot | converge **detached**, then `/health` | `healthy`, `RestartCount=0` after 30 min |
| 2 | Non-interference | `spark-llm-probe.py … health` + `reasoning` while the box is otherwise idle | both PASS, host `MemAvailable` ≥ the value in [stability-test.md §2](../stability-test.md) (18.12 GiB floor from the certified run) |
| 3 | Real depth | `spark-llm-probe.py … ctx <max_model_len>` | HTTP 200, `prompt_tokens` ≥ 80 % of the ask, no preemption in `/metrics` |
| 4 | Concurrency | `spark-llm-probe.py … concurrent <max_num_seqs>` | all 200s, and the slowest latency is within 3× the solo latency |
| 5 | Needle | the [pi-harness.md §3](../../docs/pi-harness.md) needle protocol at the profile's operating depth (≥ 90 % of window) | the needle is recalled correctly at depth, 3/3 |
| 6 | Accuracy | the same fixed 15-prompt local-knowledge + tool-call battery used for the AWQ 98/100 and NVFP4 91-vs-99 captures ([R2-nvfp4.md §B](../resources/R2-nvfp4.md)) | score within the profile's declared tolerance **and** the engine/effort/template are recorded with it (that capture's contradiction came from unrecorded confounds) |
| 7 | Memory curve | one working day of `spark-oom-watchdog` samples (`/mnt/spark_nvme/oom-watchdog/state/samples.csv`, `gpu_top_mib`) | no growth > 2 GiB/h under traffic that fails to return at idle — the C3 re-arm rule in [docs/hardware-spark.md](../../docs/hardware-spark.md) §Unified-memory budget |

Only after 0–7: set `certified: true` + `certified_evidence:` (a link to the run artifacts under
`spark/reports/`, not prose) in the catalogue, drop `uncertified_reason`, and converge once so the
override is no longer needed.

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
- A 262k `max_model_len` in the render with an fp8 pool that cannot hold `max_num_seqs` sequences is
  a preemption generator, not a capacity win — gate 4 is what distinguishes them.
