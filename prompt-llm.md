# `prompt-llm.md` — Lane brief · converge + certify the spark LLM profiles (HD-469) · run #2

> **Entry:** the owner says **“read prompt-llm and run it”** — you are the operator. The repo-side work is
> merged (`ebe6956` + `b1c7572`, both on `main`); your job is to finish the certification, or report exactly
> where it stopped and why.
> **Run #1 (2026-09-28) is merged and one of its conclusions is WRONG.** It recorded fp8 KV as “architecturally
> impossible on this model/build — do not re-attempt”. That is false, it is written in three docs, and it will
> make you skip the lane you were sent to run. **Read §0 before the docs.**
>
> **Read first, in this order:** this file §0–§1 → [README.md](README.md) §0 + §1 → [CONVENTIONS.md](CONVENTIONS.md) §6/§7 →
> [docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) (what the profiles are + the arithmetic) →
> [spark/llm-profiles/README.md](spark/llm-profiles/README.md) (the certification gate = your test plan) →
> [docs/hardware-spark.md](docs/hardware-spark.md) §Unified-memory budget (why every number is what it is) →
> [docs/pi-harness.md](docs/pi-harness.md) §2 (the measured reasoning surface) →
> the `HD-469` + `HD-380` + `HD-376` rows in [todo.md](todo.md) §2.7.
>
> **Linked from:** [todo.md](todo.md) HD-469 · [docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) ·
> [docs/index.md](docs/index.md) · [prompt.md](prompt.md)

## 0 · What run #1 got wrong (the fp8 KV verdict)

Run #1 set `graded` (fp8 KV), the engine crash-looped at `EngineCore` init with
`NotImplementedError: Qwen3.8-Flash-Next QSA requires a BF16 main KV cache`
(`vllm/models/qwen3_8_flash_next/nvidia/qsa.py:187`), and it concluded the model cannot do fp8 KV.
That line is a **dtype guard in the engine build we pin**, not a property of the model:

| Fact | Evidence |
|---|---|
| Only the **read side of the QSA Triton kernel** was missing — “the write path (`reshape_and_cache_flash`), the KV spec (`kv_quant_mode`) and the per-layer scales are already in place” | vllm **PR #55557** body, `[Model] Qwen4Exp: fp8_e4m3 main KV cache on the QSA path` |
| **#55557 was MERGED 2026-09-16T15:07Z** (`labels: ready, qwen`) — 12 days *before* run #1 | https://github.com/vllm-project/vllm/pull/55557 |
| Our engine self-reports **`vllm-0.1.dev20073+g8e685d198`** (module then named `qwen3_8_flash_next`) — a day-0 build that predates the merge. #54846's author ran his fp8 code *through the numerical tests on that exact build* and states “the QSA files of that build are identical to `main` apart from the module rename” | our measured version string ([docs/pi-harness.md](docs/pi-harness.md):90, todo HD-376) + #54846 Test Plan |
| fp8 KV was reproduced on **GB10 / sm_121, TP2 across two Sparks, with MTP speculative decoding active** | #55557 conversation, `de1tydev` 2026-09-07 |
| Two public recipes apply it to **this image** as a two-file overlay and say the guard verbatim: stock kernels “declare `supported_kv_cache_dtypes = ["auto","bfloat16"]` and raise … otherwise” | `MiaAI-Lab/Qwen3.8-Flash-Next-{Single,Dual}-DGX-Spark`, `files/patch_qsa_fp8_kv.py` (AGPL-3.0-or-later) |

**Correct state: fp8 KV is merged upstream and absent from the image we pin. Blocked on an image, not on the model.**
Run #1's own evidence is still valid and stays: on `b1c7572`'s engine, fp8 KV does not boot. What must change is
the *generalisation* — four places, and they are step 1 below.

### 0.1 Undo these four claims (they are now false and they gate the next agent)

* `docs/spark-llm-profiles.md` `graded` row — “**DEAD on this model** … architecturally impossible on this build”.
* `spark/llm-profiles/README.md` banner — “fp8 KV CANNOT boot on Qwen3.8-Flash-Next … **Do not re-attempt**”.
* `todo.md` HD-469 row — “architecturally impossible”, plus three `uncommitted` claims that are stale (run #1's
  probe/artifacts/compose fixes are committed in `b1c7572`; the worktree is gone). A row states what is **missing**.
* `IaC/ansible/group_vars/spark.yml` → `graded.uncertified_reason` — still the pre-run wording “**unvalidated** on
  this hybrid-GDN + MTP build”.

Wording to use instead (say the build, name the PR, keep the measurement):

> `graded` is blocked on the **pinned image**, not on the model: fp8 main KV on the QSA path merged upstream
> 2026-09-16 as vllm#55557; it is absent from the day-0 build we pin (`fc120ece`, self-reporting
> `vllm-0.1.dev20073+g8e685d198`) — measured 2026-09-28 as a boot-time `NotImplementedError` at
> `qsa.py:187` ([evidence](spark/reports/hd469-graded/README.md)) — and it is **not** in vLLM v0.30.0 either.
> Reaching it is an engine-pin change (HD-470), not a config flip.

### 0.2 Fix the `×2` arithmetic (catalogue comment, docs table, probe projection)

fp8 does **not** halve the pool's bytes/token — only the main K/V halves. The QSA indexer side caches
(raw-key ring, compressed keys) and the GDN state stay bf16. Measured ratios on this model:
**1.77×** (#55557, SM120, spec off) · **1.89×** (#54846) · **1.70×** (2× Spark GB10) · **1.85×** (1× Spark GB10).
Arithmetic that matches the model's shape: main KV ≈ 24,576 B of ≈ 29,294 B/token = 84 % → `1/(1 − 0.84/2) ≈ 1.72×`.

* `graded`: `515,679 × 1.70–1.77` ≈ **877k–913k slots = 3.3–3.5 × window**, not `1,031,326 = 3.93 ×`.
* `fast`: the claim “fp8 16.5 GB = 1.063M slots = **4.06 × window**” fails its **own ≥ 4 × 262,144
  no-preemption design bound** with the corrected constant (≈ 905k = 3.45 ×). Say so; do not re-state 4.06.
* **Never quote a projection where the engine prints the number.** Take `Available KV cache memory` +
  `GPU KV cache size` from the container log; those two lines are the same number in bytes and tokens, and
  they are what `certified_evidence:` and the probe's expectations must be reconciled against.

## 1 · The vLLM version question — answered, and it is an owner gate

* **On the box:** `vllm/vllm-openai:qwen38-flash-next@sha256:fc120ece0a388cc0aa1caad4a9f1cd92113484ab7ec2fd0efadd62585be05bf8`
  (`IaC/ansible/group_vars/all/versions.yml:282`, the only spark image pin), self-reporting `vllm-0.1.dev20073+g8e685d198`.
  **It is not a tagged vLLM release** — it is the day-0 model-specific build, so “update vLLM” here means
  *choose a different image and re-certify*, not bump a version string.
* **Upstream at 2026-09-28:** latest release **v0.30.0 (2026-09-22)**; v0.29.0 (2026-09-09) is where
  Qwen3.8-Flash-Next support landed (#53896).
* **A bump to v0.30.0 does NOT buy fp8 KV.** #55557 merged 2026-09-16 but is not in the v0.30 notes — v0.30 carries
  the **indexer**-side fp8 (#54890), not the main-KV path — and the MiaAI v0.30 lane says it from the other side:
  *“BF16 KV (v0.30's QSA accepts only BF16)”*, shipping a backport *“to delete once the image is vLLM 0.31+”*.
  So fp8 main KV lives in `main`/nightly and in whatever `qwen38-flash-next` tag was rebuilt after 2026-09-16. **Verify, do not assume.**
* **What a bump *does* buy** (why it is tempting): #54371 **UVA PLE offload / `--engram-config`** in v0.30 = native
  CPU-offload of the PLE table — the exact thing that makes `fast-sglang` arithmetically impossible today
  (51.2 GB pinned in host RAM = the pool), plus fused PLE kernels (#54517), split prefill/decode QSA indexer
  kernels (#54513), padded-index skipping (#54873), fused PLE residual + QSA output gate (#55309).
* **Recommendation (owner's call; default = do not bundle):** pin change = **its own lane, register HD-470**, because
  a new image invalidates the *certified* `reasoning` lane evidence (S1 stability, argv parity, the primitive-ai PLE
  overlay's anchors) and needs a full re-cert. One variable per change — the HD-400 row states the rule.
  HD-469's deliverable is the profile mechanism + the gate; it is complete except for `fast`.

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
* **No bench number while an agent session is attached** and never with your own model = spark (incident #6).
  **This one binds you directly:** if the session running this brief is itself served by `spark/...`, every
  tok/s and every latency you take is contaminated — measure on a different model, or hand the timed steps
  to a session that is not. Context-capacity, log and `/metrics` counter reads are not bench numbers.
  A 262k session is ~56 % of the old pool. `vllm bench serve` 401s every request against the `--api-key` engine
  **and exits 0** (HD-380) — assert on counters.
* **Read-only beats reboot-first.** The decisive probes in step 2 (registry manifest list, grep the image's own
  `qsa.py`) cost seconds and need no engine boot, no converge and no GPU. Do them before you touch the box.
  `docker run --rm` for a source grep is allowed: never `--gpus`, never `-p`, never `-d`, never while a converge runs.
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

**0 · Local, before touching the box** (in your own fresh worktree — CONVENTIONS §6; run #1's is gone):
```bash
git -C ../homelab-wt-<date>-<HHMM> status
bash scripts/validate-all.sh                                   # must be green (CONVENTIONS §6)
python3 scripts/validate-docker-services.py --only spark-ai    # renders, YAML parses
for p in reasoning graded fast fast-sglang; do \
  python3 scripts/spark-llm-probe.py --base-url http://127.0.0.1:1/v1 --token-env T profile $p; done
```
(T=dummy: `profile` makes no HTTP call and never reads the vault — it is the catalogue viewer.)

**1 · The docs sweep (§0.1 + §0.2).** Free, laptop-only, and it un-gates whoever reads these docs after you.
Do it first so a future session cannot be talked out of the lane by a stale “do not re-attempt”.

**2 · Is fp8 KV reachable at all? Decide it without booting anything.**
```bash
# (a) What does the tag point at NOW, and for which arch? (registry-verified = CONVENTIONS §7 language)
T=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:vllm/vllm-openai:pull" | jq -r .token)
for tag in qwen38-flash-next qwen38-flash-next-arm64-cu130; do
  curl -s -H "Authorization: Bearer $T" "https://registry-1.docker.io/v2/vllm/vllm-openai/manifests/$tag" \
    -H 'Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json' \
    | jq -r --arg t "$tag" '"\($t): \(.manifests[]? | .platform.architecture + "/" + .platform.os + " " + .digest)"'
done
# (b) Does that build carry the fp8 QSA read path? Read the image's own source — read-only, no GPU:
ssh spark 'docker run --rm --entrypoint sh <image-or-digest> -c
  "P=\$(python3 -c \"import vllm,os;print(os.path.dirname(vllm.__file__))\");
   grep -rn \"supported_kv_cache_dtypes\|IS_FP8\|BF16 main KV\" \$P/models/q*/nvidia/qsa.py | head -20"'
```
Not done for you: the registry probe above was **inconclusive on the laptop** — the agent sandbox reported
`MISSING jq/curl` on the first attempt and produced nothing parseable on the second, which does not tell us
whether egress or `jq` was the cause. So **no digest, push date or architecture here is verified** — run (a) for
real and treat every image claim below as unverified until you do.
Record: our pinned digest's **actual architecture** (`docker image inspect <pin> --format '{{.Architecture}}/{{.Os}}'`
— `versions.yml` claims a multi-arch manifest and Docker Hub renders an amd64 entry next to that digest; verify and
record which one spark actually runs), the date of the newest tag push, and the grep result.
**Decision, and it is a report, not a converge:** if no pinnable digest carries `IS_FP8`, then `graded` is
**blocked on the image** (HD-470 territory) and the correct outcome is that verdict plus the sweep in step 1 —
that is a pass, not a failure. Do **not** vendor the AGPL overlay patch, and do not hand-edit a container's
site-packages, on this lane.

**3 · Confirm the certified lane is still the live state** (run #1 proved it: gate `certified: true`, KV auto
515,679 slots, argv == certified render, probe 6/6 incl. `ctx 262144` answered at 258,863 prompt tokens). Re-run
`python3 scripts/spark-llm-probe.py --base-url https://llm.ts.kogler.si/v1 all --profile reasoning` only if this
tree changes the render, and re-check `RestartCount=0`. If this fails, **stop** — nothing else is testable on top.

**4 · `fast` on bf16 KV — the valuable thing left, and it needs no engine change.** The NVFP4 question
(“does the implementator lane boot, and what is its accuracy delta?”) is orthogonal to KV dtype. Stage the
artifacts explicitly, in its own window (≈117 GB over a 1 G link; re-check `df` first — ~296 GB free after B1 staging):
```bash
nohup ansible-playbook -i inventory.ini playbooks/spark.yml --limit spark --tags spark-artifacts \
  -e spark_artifacts_fetch='["b1-awq","ple-int4","nvfp4-mixed","ple-nvfp4"]' >/tmp/hd469-artifacts.log 2>&1 &
```
The `weights-trim` kind skips the checkpoint's own BF16 PLE table (`ple-bf16-*`, 102.4 GB of 191.0) and trims the
`ngram` entries from `model.safetensors.index.json` — verify both landed: no `ple-bf16-*` in the dir, and
`<model dir>/.index-trimmed` says how many entries it dropped. Then test `fast` **with `kv_cache_dtype: auto`**
(one variable = the weights; the fp8 half of `fast` is HD-470's problem). Two things decide it, in order:
(a) does it boot at all with the PLE overlay + `ples_nvfp4` sidecar (`VLLM_GDN_DECODE_KERNEL=triton` is set by the
profile — the *plain* NVFP4 build must drop it); (b) **accuracy** — the captures disagree (91/100 vs 98/100, and
99/100 elsewhere) because engine/template/effort were not held constant. Record engine, template, thinking state
and budget with the score, or the number is worthless.

**5 · `fast-sglang` — expect a refusal, and that is the pass. But rewrite WHY it is blocked.**
`spark_sglang_image` is empty on purpose (CONVENTIONS §7: no floating tag), and the gate aborting is the correct
outcome. What changed: **SGLang now documents this model on DGX Spark**, and its own text confirms our arithmetic
while replacing our fix. Read it before writing anything about this lane into the docs:
`https://docs.sglang.io/cookbook/autoregressive/Qwen/Qwen3.8-Flash-Next` (the “DGX Spark notes” bullets).

* **Our `--ple-offload-embedding` plan is dead, in the vendor's words:** *“the NVFP4 checkpoint is 126 GiB …
  it does not fit one DGX Spark's 128 GB … and `--ple-offload-embedding` does not help there: on GB10 the
  ‘offloaded’ pinned-host table comes out of the same pool as the GPU weights.”* Exactly the blocker in the row.
* **The single-Spark answer is a different flag:** `--ple-offload-embedding --ple-offload-backend file`
  (sglang **#37068**, merged into `qwen4-main-squashed`) — a sparse 47.7 GiB file on NVMe
  (`--ple-offload-dir`, page-cache RSS capped by `SGLANG_QWEN4_PLE_FILE_RSS_BUDGET_GB`, default 8), resident
  set 0 while serving. 78.3 GiB of experts+dense stay resident and `--mem-fraction-static 0.85` leaves
  ~12–18 GB for the pools.
* **And the measured ceiling kills the window anyway:** with that fix the single-Spark KV pool is **93k tokens**
  (RadixArk export, MTP on) or **174k** (NVIDIA export, MTP on) — **both below our 262,144 servable window**.
  Our profile's `--max-total-tokens 1048576` is a community number our own comment already marks UNVERIFIED;
  at 85 % static fraction it is fantasy on this box. The knobs we do have (`--mamba-ssm-dtype bfloat16`,
  `extra_buffer_lazy` = 4 slots/request, and **dropping `--mamba-track-interval 64`** → default 256 buys ~40 %
  more KV) move this by tens of percent, not 3×. Concurrency reality per the vendor: 8 requests with MTP,
  24 without — read the effective number from the startup log, not `/get_server_info`.
* **fp8 KV is not a luxury on this lane, it is the enabling condition** — and it is **unmerged** here: sglang
  **#36644** (`[Qwen3.8] Fix FP8 KV cache support in QSA`, open since 2026-08-27, stacked on #36497 because
  “the Qwen3.8/QSA implementation is not on `main` yet”). It measured **+88.9 % KV capacity, GSM8K −0.30 pp
  (McNemar p = 0.45), throughput flat**, and a third party ran it on **GB10/sm_121** (2× Spark, TP2, NEXTN)
  by `git apply`-ing it to `lmsysorg/sglang:qwen38flashnext` — without it, fp8 KV dies at CUDA-graph capture
  with `unsupported SM121 QSA call: expected BF16 D=256 …`. Doubling 174k clears 262k; doubling 93k does not.
  So: vLLM fp8 KV = **merged upstream, wait for an image**; SGLang fp8 KV = **an open PR on a branch that is not
  `main`, carried forever**. Prefer the first.
* **Pin problem, unchanged and sharper:** support needs sglang **≥ v0.5.20**; the NVIDIA NVFP4 export needs the
  loader from **#38121**, which `lmsysorg/sglang:qwen38flashnext` **predates** (“cannot load this export”) —
  only `dev-qwen38-next-local` (or the Python install path) ships it, and both are **floating dev tags**, which
  CONVENTIONS §7 rejects without a registry-verified arm64 digest. For that export: do **not** pass
  `--quantization` (resolves to `modelopt_mixed`) and pin `--moe-runner-backend flashinfer_cutlass` — the
  auto-default picks `flashinfer_trtllm` on GB10 and the NVFP4 MoE method rejects it at autotune.
  (Our block passes `--fp4-gemm-backend flashinfer_cutlass`; check the flag still exists before trusting it.)
* **Boot-time trap that breaks our health gate:** every boot rewrites the whole table through the mapping —
  ~17 MB/s, **~55 min** on an already-populated file (`MADV_RANDOM` read-modify-write); a *fresh* sparse file
  fills at GB/s and boots in ~10 min. Until upstream fixes it, the previous `ple_table_*.bin` must be deleted
  before each boot. `health_start_period: 1200s` (20 min) **cannot pass** on the 55-minute path — raise it or
  own the delete step in the role, do not let the container look unhealthy and get restarted into a worse loop.
* **Do not try it during this window regardless.** A failed sglang boot competes with the certified engine for the
  same 121.62 GiB pool, and the vendor's own warning matches our incident history: unified-memory exhaustion
  “can take the whole box down and needs a power cycle to recover”. If a sglang spike is ever authorised, it runs
  with the production engine stopped, in its own window, with a `MemAvailable` watchdog.
* Record in the row (it is not in it today): SGLang states thinking **cannot be turned off** on this model and
  depth is requested via `reasoning_effort` — the `enable_thinking` / `supportsReasoningEffort: false` model in
  [docs/pi-harness.md](docs/pi-harness.md) is a **vLLM-engine** measurement. A sglang profile must not inherit
  the binary reasoning surface without re-measuring it.

**6 · The client half (owner gate, do not just do it).** The server flip does not change the harness.
If a profile serves a different window, `scripts/pi-config/models-spec.yml` → `~/.pi/agent/models.json`
must carry the profile's `client_context_window` (the probe prints it) or pi 400s mid-session. Graded
reasoning is **client-side**: per-level `thinking_token_budget` in `~/.pi/agent/settings.json`, not
`reasoning_effort` — `python3 scripts/spark-llm-probe.py … effort high` is the measurement that keeps
`supportsReasoningEffort: false` honest. Both files are workstation-owned and carry the bearer: propose
the diff, let the owner apply it ([docs/pi-harness.md](docs/pi-harness.md) is the reference copy).

## Gates fp8 KV must pass *when it becomes possible* (two that run #1's bar does not have)

* **MTP acceptance, bf16 vs fp8, same prompt class.** Every upstream “decode unchanged” fp8 measurement ran with
  **speculative decoding off** (#55557 author says so explicitly). Our profiles run `spec_method: mtp, spec_tokens: 3`.
  The sm_121 corroborator found the missing interaction: fp8 K/V perturbs target and draft independently, they
  agree less often, and the lost draft positions **are** the decode loss. Read the `vllm:spec_decode_*` counters
  from `/metrics` before/after; a −10 % acceptance is a finding worth more than the pool gain.
* **Quality: parity against the model's own noise floor, not a needle run.** Use `prompt_logprobs=1, temperature 0`
  per-position and compare `fp8 − bf16` against `bf16 − bf16` from the same build (#55557's method; the reference
  numbers there: 0.170 σ vs 0.155 σ noise on a 150k-token aggregation prompt). Needles are weak evidence on this
  model — a single run at 32k measured 14 % vs 25 % miss, p = 0.67. Keep the long-reasoning battery too: the
  reference implementation measured **6/6 → 2/6** on long reasoning with fp8 KV while needles still passed, because
  quantised keys perturb *what the indexer selects*. And note the transfer gap: **every published fp8 measurement
  is on NVFP4 or FP8 checkpoints; ours is AWQ W4A16** — the published quality evidence does not cover our weights.
  (Also: nvfp4 KV, 3.06× pool, is available in the still-open #54846 — it measured perplexity +0.37…0.59 % worse
  with CIs excluding 0 and 6/12 vs 8/8 on near-1M aggregation. Do not open that axis here.)

## Report + commit

Write the run into `spark/reports/hd469-<profile>/` (commands, timestamps, `MemAvailable`, preemption +
prefix-hit + `spec_decode` counters from `/metrics`, the engine's own `Available KV cache memory` /
`GPU KV cache size` lines, probe output) and cite it from the doc — `certified_evidence:` in the catalogue takes a
**link to that directory**, never prose. Fix what run #1 left half-done: `spark/reports/hd469-graded/README.md`
still has `… (link TBD)`, `Post-boot graded: TBD`, a gate table whose rows 3–7 hold *criteria* instead of
measurements (rows 3–7 never ran — say `not run: engine did not boot`), notes numbering that jumps 2 → 7, and
the wording “fixed, uncommitted” for code that is committed. The `reasoning` proof has **no report directory at
all** (`spark/reports/hd469-reasoning/`) — create it and put the probe output there. Then: sweep the stale claims
the run produced (docs + row tails), `bash scripts/validate-all.sh` green **in the worktree**, sign the commit,
**stop** (no merge). Row tails get shorter: strike what you proved, keep what you did not — and never write
“uncommitted” in a row.

**Rollback** is the same operation in the safe direction: `spark_llm_profile: reasoning`,
`spark_llm_allow_uncertified: false`, converge detached. It needs no override and no download.
