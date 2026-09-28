# `prompt-llm.md` — Lane brief · converge + certify the spark LLM profiles (HD-469) · run #3

> **Entry:** the owner says **“read prompt-llm and run it”** — you are the operator. Everything
> that could be settled from the repo and from read-only probes **is settled** (run #2 authored it,
> the prep session `session/spark-llm-iac-prep-1845` executed the free parts and merged the shape
> into this branch). Your job is the part that needs the box: **make it true on spark**, or report
> exactly where it stopped and why.
>
> **Run #3 is written for a session that is NOT served by spark.** Check it before you start:
>
> ```bash
> echo "provider=$PI_PROVIDER model=$PI_MODEL"      # if PI_PROVIDER=spark → see rule 0 below
> ```
>
> **Read first, in this order:** this file §0 → [README.md](README.md) §0 + §1 →
> [CONVENTIONS.md](CONVENTIONS.md) §6/§7 → [docs/spark-llm-profiles.md](docs/spark-llm-profiles.md)
> (the catalogue, the arithmetic, what the gate refuses) →
> [spark/llm-profiles/README.md](spark/llm-profiles/README.md) (**rule 0 + the gate table = your test
> plan, now 0–9**) → [docs/hardware-spark.md](docs/hardware-spark.md) §Unified-memory budget +
> §GPU clock cap + §DGX Spark host limits → [docs/pi-harness.md](docs/pi-harness.md) §2 →
> the `HD-469` / `HD-471` / `HD-380` / `HD-376` rows in [todo.md](todo.md) §2.7.
>
> **Linked from:** [todo.md](todo.md) HD-469 · HD-471 · [docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) ·
> [docs/index.md](docs/index.md) · [prompt.md](prompt.md)

## 0 · Already settled — do not spend your window re-deriving it

| Thing | State on this branch | Proof |
|---|---|---|
| **fp8 KV verdict.** Run #1 wrote “architecturally impossible, do not re-attempt” in four places. It is **false**: the boot failure is real, the build is the cause. The pinned image’s own `qsa.py:70` declares `supported_kv_cache_dtypes = ["auto","bfloat16"]` and raises at :109/:188; vllm **#55557** merged the read path **2026-09-16**, three weeks after this tag was last pushed (**2026-08-26**, digest unchanged, and no newer tag of this model exists in the registry); vLLM v0.30.0 does not carry it either. ⇒ `graded` is **HD-471** (engine pin + re-cert), not a flip, and **not** a container patch: the third-party recipes hand-edit site-packages, which this lane rejects. | swept in all four docs + the catalogue; new evidence dir | [`spark/reports/hd469-graded/README.md`](spark/reports/hd469-graded/README.md) · [`image-probe-20260928.md`](spark/reports/hd469-graded/image-probe-20260928.md) |
| **The ×2 arithmetic.** fp8 halves the **main K/V only** → measured **1.70–1.89×**, not 2×. `spark_llm_kv_bytes_per_token.fp8` is now 18,251; `graded` = **876,664** slots (3.34×), not 1,031,326. The `fast` profile’s “4.06 × window ≥ the 4 × 262,144 bound” failed its own bound with the correct constant and is gone. | constant in `group_vars/spark.yml`, gate + probe read it | [`scripts/check_spark_llm_gate.py`](scripts/check_spark_llm_gate.py) |
| **The pool ceiling was not an OOM guard.** A profile that changes the **weights** changes the fixed cost; NVFP4’s core is 88.6 GB vs the AWQ lane’s whole measured 81 GiB. Every vLLM profile now declares `fixed_cost_bytes` and the gate asserts `fixed + pool ≤ 104,113,000,000 B` (= MemTotal − 6.9 GiB held at engine start − the certified **17.78 GiB** worst `usable`). `fast` therefore runs an **11 GB** pool, not 16.5 GB. | gate + catalogue + canary | same |
| **The gate is proven without the box.** Item 22 of `validate-all.sh` extracts the role’s own regexes + the constants, runs every profile and breeds a canary per invariant; both canaries are also refused by the real `ansible.builtin.assert` tasks (run against localhost). | `bash scripts/validate-all.sh` | `scripts/check_spark_llm_gate.py` |
| **SGLang facts** (file-backed PLE #37068, the ~93k/174k pools, `--mem-fraction-static 0.80` vs the earlyoom threshold, the ~55-minute table re-write, CDI-only docker GPU access, thinking cannot be turned off). | in the `fast-sglang` catalogue comments + [docs/hardware-spark.md](docs/hardware-spark.md) §DGX Spark host limits | SGLang’s own DGX Spark cookbook pages |
| **The clock cap is IaC that has never converged.** Read-only on 2026-09-28: `clocks.max.sm = 3003 MHz`, i.e. **uncapped** — so every timed number already in the repo is pre-cap, and your first converge is what installs the ceiling (and its assert is what proves the ceiling works on this unit). | measured | [`spark/reports/hd469-reasoning/README.md`](spark/reports/hd469-reasoning/README.md) |

**The Qwen3.8-27B question** the owner raised is answered and moved out of this brief: it is a
**second served model**, never a value of `spark_llm_profile` — the vendor's measured GB10 grid, the
pool arithmetic that makes it attractive, and why taking it up would void every anchor HD-469 protects
are in [docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) §Not a profile. Out of scope here.

**Rule 0 (from the gate README) binds you before anything else:** if your own model is served by
spark, you may not take timed numbers — `ctx`, `concurrent`, any tok/s/TTFT/TPOT — and the deep legs
compete with your own session for the pool you are measuring. Read-only state, logs and `/metrics`
counter reads are fine. If `PI_PROVIDER=spark`, either run only the untimed steps and hand the timed
ones over, or stop and tell the owner.

## Non-negotiables (each line cost an outage or a power-cycle)

* **You hold the spark converge slot.** `pgrep -af ansible-playbook` must be empty of other runs
  **and** no other session may be converging `spark` for the whole window. A half-applied converge on
  this host is measured, not theoretical ([`scripts/rotate-spark-llm-key.sh`](scripts/rotate-spark-llm-key.sh) header).
* **Every converge is DETACHED.** `nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark >/tmp/hd469-<profile>.log 2>&1 &` then poll the log. A
  tool-timeout-killed converge is worse than no converge (README §4.6). Engine cold boot is **~20 min**
  (first PLE-table load; `start_period: 1200s`), and a full converge re-checks 30 GB of tables first.
* **Never** `reboot spark`, never raise `gpu_memory_utilization` (removed from this build — dead
  config), never raise `max_model_len` above 262,144, never raise the KV pool past the certified
  16 GiB ceiling **and never raise a profile’s `fixed_cost_bytes` or the host-floor ceiling to make a
  gate pass** (the measurement is the thing to change, not the constant), never `--quantization` on
  the vLLM CLI (the checkpoints declare their own format). **Do not work around an assert by editing
  the assert** — fix the value or report it.
* **`docker stop vllm-qwen-spark` is intentional** in the watchdog path: `unless-stopped` will not
  bring it back. If you stop it, you own restarting it via converge.
* **No bench number while an agent session is attached** and never with your own model = spark
  (incident #6; rule 0). A 262k session is ~56 % of the old pool. `vllm bench serve` 401s every
  request against the `--api-key` engine **and exits 0** (HD-380) — assert on counters.
* **Read-only beats reboot-first.** `docker run --rm --entrypoint sh <image> -c '…grep…'` is allowed
  (never `--gpus`, never `-p`, never `-d`, never while a converge runs, and `scripts/spark-fp8-image-probe.py`
  refuses to pull — it runs the local image by ID). Context/memory/`/metrics` reads cost nothing; use them.
* **Secrets:** the bearer is `spark-llm_api` in 1Password. Read it via `op` or let
  `scripts/spark-llm-probe.py` read it. It never goes in argv, a file, a commit, or the transcript.

## The switch you are testing

```bash
cd IaC/ansible
# 0 · the whole catalogue, offline, no token — read this before you pick anything:
python3 scripts/spark-llm-probe.py matrix
# 1 · what the gate would do, read-only, no writes, cheap — ALWAYS run this next:
ansible-playbook -i inventory.ini playbooks/spark.yml --limit spark \
  --tags spark-llm-profile --check --diff
```
The gate prints the resolved profile and refuses on: unknown profile · unknown engine · empty image
pin · KV pool < `max_model_len` · pool > the 16 GiB ceiling · **fixed cost + pool > the host-floor
ceiling** · cudagraph cap > `max_num_seqs` · (SGLang) `--mem-fraction-static` > 0.80 ·
`--max-total-tokens` < the advertised window · `--ple-offload-embedding` without `--ple-offload-backend file` ·
uncertified without the override · artifacts missing. The dial is `spark_llm_profile` in
`host_vars/spark.kogler.si.yml`; valid names are the keys of `spark_llm_profiles` in
`group_vars/spark.yml` — read them, hardcode none of them.

## Sequence

**0 · Local, before touching the box** (your own fresh worktree — CONVENTIONS §6):
```bash
git -C ../homelab-wt-<date>-<HHMM> status
bash scripts/validate-all.sh                                   # must be green (CONVENTIONS §6)
python3 scripts/check_spark_llm_gate.py                        # the gate + its canaries, offline
python3 scripts/validate-docker-services.py --only spark-ai    # renders, YAML parses
python3 scripts/spark-llm-probe.py matrix                      # every profile, no token needed
```

**1 · Prove the certified lane, and install the clock cap, in ONE converge.** `spark_llm_profile`
stays `reasoning`; the branch carries `roles/spark`’s `clockcap` unit for the first time, so this
converge is both the refactor check and the cap check.
```bash
# --no-pull is deliberate: a session worktree has no upstream, so the runner would
# otherwise refuse (uncommitted) or converge the wrong commit. Read the NOTE it prints.
nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull >/tmp/hd469-reasoning.log 2>&1 &
tail -f /tmp/hd469-reasoning.log          # poll, do not block a tool timeout on it
```
Expect: gate summary `certified: true`; the container is **not** recreated for cosmetic reasons; the
`clockcap` assert passes (if it fails, this unit is in the documented `-lgc`-is-accepted-and-does-nothing
class — report it, do not `--skip-tags clockcap` and carry on). Then, **from a session that is not
served by spark**:
```bash
python3 scripts/spark-llm-probe.py --base-url https://llm.ts.kogler.si/v1 all --profile reasoning
ssh spark 'nvidia-smi --query-gpu=clocks.sm,clocks.max.sm,power.draw,temperature.gpu --format=csv'  # must read 2418
```
Baseline to compare against (run #1, pre-cap): `health` 200, thinking OFF emits no reasoning,
`ctx 262144` answered at 258,863 prompt tokens, `concurrent 4` all 200, `RestartCount=0`. **This run
is the under-cap baseline from now on**; anything older is history, not an A/B arm. If this step
fails, **stop and roll back the branch** — nothing downstream is testable on a broken render.

**2 · `graded` — the correct outcome is a report, not a converge.** fp8 KV is blocked on the image
(§0). Re-derive the evidence in ~40 s instead of booting anything:
```bash
python3 scripts/spark-fp8-image-probe.py --tag-filter 'qwen|flash'      # exit 0 = verdict reached
```
If it prints `REACHABLE`, the registry or the image changed under us and `graded` (HD-471) is open
again — say so loudly, and do not flip the profile on the strength of a grep. If it prints
`BLOCKED-ON-IMAGE` (the expected answer), record the run, and the lane’s `graded` half is **done**:
no box work, no risk, a pass. `UNDECIDED` means one leg could not run — that is not a verdict; fix
the leg or write “OPEN” in the report.

**3 · Stage the `fast` artifacts — explicitly, in its own window** (≈117 GB over a 1 G link; ~296 GB
was free after B1 staging, re-check `df` first):
```bash
nohup ansible-playbook -i inventory.ini playbooks/spark.yml --limit spark --tags spark-artifacts \
  -e spark_artifacts_fetch='["b1-awq","ple-int4","nvfp4-mixed","ple-nvfp4"]' >/tmp/hd469-artifacts.log 2>&1 &
```
The `weights-trim` kind skips the checkpoint’s own BF16 PLE table (`ple-bf16-*`, 102.4 GB of 191.0)
and trims the `ngram` entries from `model.safetensors.index.json` — verify both landed: no
`ple-bf16-*` in the dir, and `<model dir>/.index-trimmed` says how many entries it dropped.

**4 · `fast` — the valuable thing left, and it needs no engine change.** The catalogue already
carries the decision this run used to have to make: `fast` is **NVFP4 weights on bf16 KV** with an
**11 GB** pool (`kv_cache_dtype: auto`), because the fp8 half belongs to HD-471 and the weights cost
+≈5.2 GB of the shared pool. One variable = the weights. Set `spark_llm_profile: fast` +
`spark_llm_allow_uncertified: true`, converge **detached**, then run gates 0–7 of
[spark/llm-profiles/README.md](spark/llm-profiles/README.md). Two things decide it, in order:
(a) **does it boot** with the PLE overlay + `ples_nvfp4` sidecar (`VLLM_GDN_DECODE_KERNEL=triton` is
set by the profile — the *plain* NVFP4 build must drop it); (b) **accuracy** — the existing captures
disagree (91/100 vs 98/100, and 99/100 elsewhere) because engine/template/effort were not held
constant, so record engine, template, thinking state and budget with every score or the number is
worthless. Gate 7 is not optional here: the profile’s `fixed_cost_bytes` is **DERIVED**, and the
watchdog curve is what falsifies it — if `usable` drops toward 17.78 GiB or the pool the engine
reports is smaller than 11 GB’s worth of slots, shrink the pool and record the measured fixed cost.

**5 · `fast-sglang` — expect a refusal, and that is the pass.** `spark_sglang_image` is empty on
purpose (CONVENTIONS §7: no floating tag); the gate aborting is the correct outcome. The *why* was
rewritten against the vendor’s own GB10 measurements and now lives in the catalogue comments and
[docs/hardware-spark.md](docs/hardware-spark.md) §DGX Spark host limits — read them before writing
anything about this lane. Three blockers, in cost order: no registry-verified **arm64** digest (the
only builds with support ≥ v0.5.20 + the #38121 export loader are floating dev tags); the vendor’s
measured single-Spark pools (~93k RadixArk / ~174k NVIDIA export, MTP on) cannot hold the 262,144
window we serve, and closing that needs sglang fp8 KV = sglang **#36644**, still open; and a failed
sglang boot competes with the certified engine for the same 121.62 GiB pool — “can take the whole box
down and needs a power cycle to recover”. **Do not spike it in this window.** If a spike is ever
authorised: production engine stopped, own window, `MemAvailable` watchdog, CDI device access,
`--ple-offload-backend file` with the NVMe bind wired in IaC, and the previous `ple_table_*.bin`
deleted before boot (or `health_start_period: 4800s` covers the ~55-minute re-write).

**6 · The client half (owner gate, do not just do it).** The server flip does not change the harness.
If a profile serves a different window, `scripts/pi-config/models-spec.yml` → `~/.pi/agent/models.json`
must carry that profile’s `client_context_window` (`matrix` prints it per profile) or pi 400s
mid-session. Graded reasoning is **client-side**: per-level `thinking_token_budget` in
`~/.pi/agent/settings.json`, not `reasoning_effort` — `spark-llm-probe.py … effort high` is the
measurement that keeps `supportsReasoningEffort: false` honest **on the vLLM engine**; SGLang is the
opposite (thinking cannot be off, depth via `reasoning_effort`), which is why `fast-sglang` declares
`reasoning_surface: always-on-effort-unmeasured` instead of inheriting that finding. Both client
files are workstation-owned and carry the bearer: propose the diff, let the owner apply it
([docs/pi-harness.md](docs/pi-harness.md) is the reference copy).

## Timed measurements: read the clock regime, do not assume it

* **Verify at both ends of every timed window:**
  `ssh spark 'nvidia-smi --query-gpu=clocks.sm,clocks.max.sm,power.draw,temperature.gpu --format=csv'`
  must read `clocks.max.sm = 2418` once the cap has converged. It read **3003** on 2026-09-28, i.e.
  the ceiling is not on the box until step 1 lands. If it still does not read 2418 after a successful
  converge, that is a **host finding for the report**, not something to fix by hand mid-run: the role
  owns that state, and an ad-hoc `-lgc`/`-rgc` inside a measurement window destroys the thing you are
  measuring.
* The cap sits at the **default application clock** (~3 % under where this unit actually boosts — it
  read 2496–2515 MHz), so pre-cap figures (≈11 tok/s decode, 17,008 tok/s re-prefill, `SM_CLOCK`
  2509 MHz) stay roughly comparable — but “roughly” is not “identically”: the first under-cap run is
  the baseline. **One regime per A/B**: if the cap is missing on one arm, the A/B is void.
* **GB10 will not validate a clock value for you:** `--query-supported-clocks=graphics` → `[N/A]`,
  `-pl` is unsupported, and every temperature target reads `N/A` — a graphics-clock ceiling is the
  *entire* software control surface on this SoC, and the read-back is the only proof. Details + the
  `SW Power Capping` counter: [docs/hardware-spark.md](docs/hardware-spark.md) §GPU clock cap.

## Report + commit

Write the run into `spark/reports/hd469-<profile>/` (commands, timestamps, `MemAvailable` **and
`CmaFree`** — the metric is `usable = MemAvailable − CmaFree`, `clocks.sm`/`clocks.max.sm`/power/temp
at the **start and end** of each timed window, preemption + prefix-hit + `vllm:spec_decode_*` counters
from `/metrics`, the engine’s own `Available KV cache memory` / `GPU KV cache size` lines, probe
output) and cite it from the catalogue — `certified_evidence:` takes a **link to that directory**,
never prose, and never a projected slot count.

Already fixed for you, so do not re-do it: `hd469-graded/README.md` no longer has `(link TBD)`,
`Post-boot graded: TBD`, criteria-in-place-of-measurements in rows 3–7, the 2→7 numbering jump, or
“fixed, uncommitted” for committed code; `hd469-reasoning/` now exists and names what that lane still
owes (under-cap baseline, gates 5–7 for the refactored render).

Then: sweep the stale claims your run produced (docs + row tails), `bash scripts/validate-all.sh`
green **in the worktree**, sign the commit, **stop** (no merge). Row tails get shorter: strike what
you proved, keep what you did not — and never write “uncommitted” in a row.

**Rollback** is the same operation in the safe direction: `spark_llm_profile: reasoning`,
`spark_llm_allow_uncertified: false`, converge detached. It needs no override and no download.
