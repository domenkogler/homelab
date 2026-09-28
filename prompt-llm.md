# `prompt-llm.md` — Lane brief · converge + certify the spark LLM profiles (HD-469)

> **Entry:** the owner says **“read prompt-llm and run it”** — you are the operator. The repo-side work is
> already authored (worktree `../homelab-wt-20260928-1114-1114`, branch `session/spark-llm-profiles-1114`);
> your job is to make it **true on the box**, or report exactly where it stopped.
>
> **Read first, in this order:** [README.md](README.md) §0 + §1 → [CONVENTIONS.md](CONVENTIONS.md) §6/§7 →
> [docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) (what the profiles are + the arithmetic) →
> [spark/llm-profiles/README.md](spark/llm-profiles/README.md) (the certification gate = your test plan) →
> [docs/hardware-spark.md](docs/hardware-spark.md) §Unified-memory budget (why every number is what it is) →
> [docs/pi-harness.md](docs/pi-harness.md) §2 (the measured reasoning surface) →
> the `HD-469` + `HD-380` + `HD-376` rows in [todo.md](todo.md) §2.7.
>
> **Linked from:** [todo.md](todo.md) HD-469 · [docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) ·
> [docs/index.md](docs/index.md) · [prompt.md](prompt.md)

## Non-negotiables (each line cost an outage or a power-cycle)

* **You hold the spark converge slot.** `pgrep -af ansible-playbook` must be empty of other runs **and**
  no other session may be converging `spark` for the whole window. A half-applied converge on this host is
  measured, not theoretical ([`scripts/rotate-spark-llm-key.sh`](scripts/rotate-spark-llm-key.sh) header).
* **Every converge is DETACHED.** `nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark >/tmp/hd469-<profile>.log 2>&1 &` then poll the log. A
  tool-timeout-killed converge is worse than no converge (README §4.6). Engine cold boot is **~20 min**
  (first PLE-table load; `start_period: 1200s`), and a full converge re-checks 30 GB of tables first.
* **Never** `reboot spark`, never raise `gpu_memory_utilization` (removed from this build — it is dead
  config), never raise `max_model_len` above 262,144, never raise the KV pool past the certified 16 GiB
  ceiling, never `--quantization` on the CLI (the checkpoints declare their own format). The gate asserts
  all of these; **do not work around an assert by editing the assert** — fix the value or report it.
* **`docker stop vllm-qwen-spark` is intentional** in the watchdog path: `unless-stopped` will not bring it
  back. If you stop it, you own restarting it via converge.
* **No bench number while an agent session is attached** and never with your own model = spark
  (incident #6). A 262k session is ~56 % of the old pool. `vllm bench serve` 401s every request against
  the `--api-key` engine **and exits 0** (HD-380) — assert on counters.
* **Secrets:** the bearer is `spark-llm_api` in 1Password. Read it via `op` or let
  `scripts/spark-llm-probe.py` read it. It never goes in argv, a file, a commit, or the transcript.

## The switch you are testing

```bash
cd IaC/ansible
# what the gate would do, read-only, no writes, cheap — ALWAYS run this first:
ansible-playbook -i inventory.ini playbooks/spark.yml --limit spark \
  --tags spark-llm-profile --check --diff
```
It prints the resolved profile and refuses on: unknown profile · empty image pin · KV pool < `max_model_len`
· pool > ceiling · cudagraph cap > `max_num_seqs` · uncertified without the override · artifacts missing.
The dial is `spark_llm_profile` in `host_vars/spark.kogler.si.yml`; valid names are the keys of
`spark_llm_profiles` in `group_vars/spark.yml` (read them, do not hardcode them anywhere).

## Sequence

**0 · Local, before touching the box** (in the worktree — `git -C ../homelab-wt-20260928-1114-1114 status`):
```bash
bash scripts/validate-all.sh                                   # must be green (CONVENTIONS §6)
python3 scripts/validate-docker-services.py --only spark-ai    # renders, YAML parses
for p in reasoning graded fast fast-sglang; do \
  python3 scripts/spark-llm-probe.py --base-url http://127.0.0.1:1/v1 --token-env T profile $p; done
```
(T=dummy: `profile` makes no HTTP call and never reads the vault — it is the catalogue viewer.)

**1 · Prove the refactor on the certified shape.** `spark_llm_profile: reasoning` + converge detached.
Expect: gate summary prints `certified: true`, the container is **not** recreated for cosmetic reasons
(`reasoning` renders structurally equal to the pre-HD-469 template — verified), then:
```bash
python3 scripts/spark-llm-probe.py --base-url https://llm.ts.kogler.si/v1 all --profile reasoning
```
Baseline to compare against, so a regression cannot hide: `health`, thinking OFF emits no reasoning,
`ctx 262144` answers, `concurrent 4` all 200. If this step fails, **stop and roll back the branch** — the
refactor is broken and no other profile is worth testing on top of it.

**2 · Stage the `fast` artifacts — explicitly, in its own window** (≈117 GB over a 1 G link; ~296 GB was
free after B1 staging, re-check `df` before starting):
```bash
nohup ansible-playbook -i inventory.ini playbooks/spark.yml --limit spark --tags spark-artifacts \
  -e spark_artifacts_fetch='["b1-awq","ple-int4","nvfp4-mixed","ple-nvfp4"]' >/tmp/hd469-artifacts.log 2>&1 &
```
The `weights-trim` kind skips the checkpoint’s own BF16 PLE table (`ple-bf16-*`, 102.4 GB of 191.0) and
trims the `ngram` entries from `model.safetensors.index.json` — verify both landed: the dir has no
`ple-bf16-*`, and `<model dir>/.index-trimmed` says how many entries it dropped.

**3 · `graded` (fp8 KV, same weights — cheapest new datapoint).** Set `spark_llm_profile: graded` +
`spark_llm_allow_uncertified: true`, converge detached, then run gates 1–7 of
[spark/llm-profiles/README.md](spark/llm-profiles/README.md). The load-bearing numbers: fp8 should give
**~1.03 M token slots** in the same 16 GB pool (~3.9 × the window) — if `/metrics` shows preemptions at
`concurrent 4`, or the needle at ≥90 % depth fails, fp8 KV is **not** certifiable here and the profile
stays uncertified with the measurement recorded.

**4 · `fast` (NVFP4).** Same procedure with the override. Two things decide it, in this order:
(a) does it boot at all on the pinned vLLM fork with the PLE overlay + `ples_nvfp4` sidecar
(`VLLM_GDN_DECODE_KERNEL=triton` is set by the profile — the *plain* NVFP4 build must drop it);
(b) **accuracy** — the existing captures disagree (91/100 vs 98/100, and 99/100 elsewhere) because
engine/template/effort were not held constant. Run the fixed battery, and record engine, template,
thinking state and budget with the score, or the number is worthless.

**5 · `fast-sglang` — expect a refusal, and that is the pass.** `spark_sglang_image` is empty on purpose
(CONVENTIONS §7: no floating tag). The gate aborting is the correct outcome. Opening it needs a
registry-verified **arm64** digest pinned in `group_vars/all/versions.yml` **plus** an answer to the pool
problem: `--ple-offload-embedding` pins the 51.2 GB FP8 table in host RAM, which on GB10 *is* the
121.62 GiB device pool (the x86 recipe box has 96 GB **discrete** — do not copy its numbers).

**6 · The client half (owner gate, do not just do it).** The server flip does not change the harness.
If a profile serves a different window, `scripts/pi-config/models-spec.yml` → `~/.pi/agent/models.json`
must carry the profile’s `client_context_window` (the probe prints it) or pi 400s mid-session. Graded
reasoning is **client-side**: per-level `thinking_token_budget` in `~/.pi/agent/settings.json`, not
`reasoning_effort` — `python3 scripts/spark-llm-probe.py … effort high` is the measurement that keeps
`supportsReasoningEffort: false` honest. Both files are workstation-owned and carry the bearer: propose
the diff, let the owner apply it ([docs/pi-harness.md](docs/pi-harness.md) is the reference copy).

## Report + commit

Write the run into `spark/reports/hd469-<profile>/` (commands, timestamps, `MemAvailable`, preemption +
prefix-hit counters from `/metrics`, probe output) and cite it from the doc — `certified_evidence:` in the
catalogue takes a **link to that directory**, never prose. Then: sweep the stale claims the run produced
(docs + row tails), `bash scripts/validate-all.sh` green **in the worktree**, sign the commit, **stop**
(no merge). Row tails get shorter: strike what you proved, keep what you did not.

**Rollback** is the same operation in the safe direction: `spark_llm_profile: reasoning`,
`spark_llm_allow_uncertified: false`, converge detached. It needs no override and no download.
