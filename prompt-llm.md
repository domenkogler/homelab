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
> the `HD-469` / `HD-473` / `HD-380` / `HD-376` rows in [todo.md](todo.md) §2.7.
>
> **Linked from:** [todo.md](todo.md) HD-469 · HD-473 · [docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) ·
> [docs/index.md](docs/index.md) · [prompt.md](prompt.md)

## 0 · Already settled — do not spend your window re-deriving it

| Thing | State on this branch | Proof |
|---|---|---|
| **fp8 KV verdict.** Run #1 wrote “architecturally impossible, do not re-attempt” in four places. It is **false**: the boot failure is real, the build is the cause. The pinned image’s own `qsa.py:70` declares `supported_kv_cache_dtypes = ["auto","bfloat16"]` and raises at :109/:188; vllm **#55557** merged the read path **2026-09-16**, three weeks after this tag was last pushed (**2026-08-26**, digest unchanged, and no newer tag of this model exists in the registry); vLLM v0.30.0 does not carry it either. ⇒ `graded` is **HD-473** (engine pin + re-cert), not a flip, and **not** a container patch: the third-party recipes hand-edit site-packages, which this lane rejects. | swept in all four docs + the catalogue; new evidence dir | [`spark/reports/hd469-graded/README.md`](spark/reports/hd469-graded/README.md) · [`image-probe-20260928.md`](spark/reports/hd469-graded/image-probe-20260928.md) |
| **The ×2 arithmetic.** fp8 halves the **main K/V only** → measured **1.70–1.89×**, not 2×. `spark_llm_kv_bytes_per_token.fp8` is now 18,251; `graded` = **876,664** slots (3.34×), not 1,031,326. The `fast` profile’s “4.06 × window ≥ the 4 × 262,144 bound” failed its own bound with the correct constant and is gone. | constant in `group_vars/spark.yml`, gate + probe read it | [`scripts/check_spark_llm_gate.py`](scripts/check_spark_llm_gate.py) |
| **The pool ceiling was not an OOM guard.** A profile that changes the **weights** changes the fixed cost; NVFP4’s core is 88.6 GB vs the AWQ lane’s whole measured 81 GiB. Every vLLM profile now declares `fixed_cost_bytes` and the gate asserts `fixed + pool ≤ 104,113,000,000 B` (= MemTotal − 6.9 GiB held at engine start − the certified **17.78 GiB** worst `usable`). `fast` therefore runs an **11 GB** pool, not 16.5 GB. | gate + catalogue + canary | same |
| **The gate is proven without the box.** Item 22 of `validate-all.sh` extracts the role’s own regexes + the constants, runs every profile and breeds a canary per invariant; both canaries are also refused by the real `ansible.builtin.assert` tasks (run against localhost). | `bash scripts/validate-all.sh` | `scripts/check_spark_llm_gate.py` |
| **SGLang facts** (file-backed PLE #37068, the ~93k/174k pools, `--mem-fraction-static 0.80` vs the earlyoom threshold, the ~55-minute table re-write, CDI-only docker GPU access, thinking cannot be turned off). | in the `fast-sglang` catalogue comments + [docs/hardware-spark.md](docs/hardware-spark.md) §DGX Spark host limits | SGLang’s own DGX Spark cookbook pages |
| **The clock cap CONVERGED (run #3, 2026-09-29 15:45) and has no read-back.** The assert installed by run #2 failed that converge while the converge had in fact applied the cap: `clocks.max.sm` is a **capability** field (3003 lock or no lock) and `clocks.applications.graphics` reads 2418 because that **is** the default app clock — no field on this driver reflects a `-lgc` range lock. Owner ruling: the re-read/assert is gone (`043ff4a`), the role re-issues the lock every converge with `changed_when: false`. ⇒ the regime of a measurement window is proven only by **sustained `clocks.sm` under load** (2496–2515 pre-cap, ~2411 capped), which run #3 never recorded — so **the under-cap baseline is still owed** and no number in the repo is a certified under-cap number. | measured 2026-09-29 + log | [`spark/reports/hd469-reasoning/README.md`](spark/reports/hd469-reasoning/README.md) · [docs/hardware-spark.md](docs/hardware-spark.md) §GPU clock cap |

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

> **Run #4 state (2026-09-29, after run #3 — read this before spending a window):** step 1 the
> baseline is **OWED** (the cap converged 15:45 but no clock-regime trace exists — this is the
> valuable leg, and it is why run #4 must be a non-spark-served session); step 2 `graded` **DONE**
> (BLOCKED-ON-IMAGE, re-derivable in 40 s, no box work); step 3 artifacts **STAGED** (verify only, do
> not re-fetch); step 4 `fast` is **HD-475 and code-first** (it booted and failed gate 3 — do not flip
> it to rediscover that); step 5 sglang **do not spike**; step 6 client half **no change needed**
> (every profile serves the same 262,144 window, so `models-spec.yml` needs nothing today).

**0 · Local, before touching the box** (your own fresh worktree — CONVENTIONS §6):
```bash
git -C ../homelab-wt-<date>-<HHMM> status
bash scripts/validate-all.sh                                   # must be green (CONVENTIONS §6)
python3 scripts/check_spark_llm_gate.py                        # the gate + its canaries, offline
python3 scripts/validate-docker-services.py --only spark-ai    # renders, YAML parses
python3 scripts/spark-llm-probe.py matrix                      # every profile, no token needed
```

**1 · Prove the certified lane, and take the baseline the last run only claimed.** `spark_llm_profile`
stays `reasoning`; the `clockcap` unit converged on 2026-09-29, so this is the refactor check plus the
baseline that run #3 wrote into the row without writing into its evidence directory.
```bash
# --no-pull is deliberate: a session worktree has no upstream, so the runner would
# otherwise refuse (uncommitted) or converge the wrong commit. Read the NOTE it prints.
nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull >/tmp/hd469-reasoning.log 2>&1 &
tail -f /tmp/hd469-reasoning.log          # poll, do not block a tool timeout on it
```
Expect: gate summary `certified: true`; the container is **not** recreated for cosmetic reasons;
`clockcap` reports `ok` **not** `changed` (the apply is `changed_when: false` by design — a `changed`
it cannot observe would be noise, and the old dead-field gate made every converge report one). Then,
**from a session that is not served by spark**, with the clock trace running across the whole window:
```bash
ssh spark 'nvidia-smi --query-gpu=timestamp,clocks.sm,power.draw,temperature.gpu,clocks_event_reasons.active --format=csv -l 5' >/tmp/hd469-baseline-clocks-$(date +%H%M).log 2>&1 &
python3 scripts/spark-llm-probe.py --base-url https://llm.ts.kogler.si/v1 all --profile reasoning
awk '/MemAvailable|CmaFree/' /proc/meminfo   # at BOTH ends of the window
ssh spark 'curl -s localhost:8000/metrics | grep -E "num_preemptions_total|prefix_cache|spec_decode"'
```
Paste the **raw** outputs into `spark/reports/hd469-reasoning/` — that directory, not the row, is what
makes the baseline exist. One log file per converge attempt (`-$(date +%H%M)`): run #3's failed first
converge was erased when the retry truncated `/tmp/hd469-reasoning.log`.
Baseline to compare against (run #1, pre-cap): `health` 200, thinking OFF emits no reasoning,
`ctx 262144` answered at 258,863 prompt tokens, `concurrent 4` all 200, `RestartCount=0`. **This run
is the under-cap baseline from now on**; anything older is history, not an A/B arm. If this step
fails, **stop and roll back the branch** — nothing downstream is testable on a broken render.

**2 · `graded` — the correct outcome is a report, not a converge.** fp8 KV is blocked on the image
(§0). Re-derive the evidence in ~40 s instead of booting anything:
```bash
python3 scripts/spark-fp8-image-probe.py --tag-filter 'qwen|flash'      # exit 0 = verdict reached
```
If it prints `REACHABLE`, the registry or the image changed under us and `graded` (HD-473) is open
again — say so loudly, and do not flip the profile on the strength of a grep. If it prints
`BLOCKED-ON-IMAGE` (the expected answer), record the run, and the lane’s `graded` half is **done**:
no box work, no risk, a pass. `UNDECIDED` means one leg could not run — that is not a verdict; fix
the leg or write “OPEN” in the report.

**3 · The `fast` artifacts are ALREADY STAGED — verify, do not re-fetch.** Run #3 staged
`nvfp4-mixed` + `ple-nvfp4` (~117 GB) in its own window and both landed; re-checked read-only on
2026-09-29: `Qwen3.8-Flash-Next-mixed-NVFP4-FP8/.index-trimmed` = **130 entries dropped
(pattern=ngram)**, **no `ple-bf16-*`** anywhere, `ples_nvfp4/` flat (`META.json` + shards, no nested
dir left by the flatten step). ⚠ **Disk headroom is now ~185 GB, not the ~296 GB this brief assumed**
— a needless re-fetch of a 117 GB set on a 504 GB store is how you walk into a full data disk, so the
artifacts tag is NOT run by default:
```bash
ssh spark 'cat /mnt/spark_nvme/models/Qwen3.8-Flash-Next-mixed-NVFP4-FP8/.index-trimmed; find /mnt/spark_nvme -maxdepth 2 -name "ple-bf16-*" | head; df -h /mnt/spark_nvme | tail -1'
```
If — and only if — a verify fails, re-run the fetch **detached, in its own window**, naming the kinds
that are actually missing (never the whole set): `--tags spark-artifacts -e
spark_artifacts_fetch='["nvfp4-mixed","ple-nvfp4"]'`.

**4 · `fast` is HD-475's, and it is CODE-FIRST — do not flip the profile to re-prove gate 3.** Run #3
staged the weights, booted the profile healthy (`GPU KV cache size: 354,248 tokens / 1.35×`,
`RestartCount=0`, so the DERIVED `fixed_cost_bytes` held and the 11 GB pool is real) and it **failed
gate 3**: the 262,144-token leg 502s at ~105 s and `concurrent 4` fails 0/4, with `RestartCount=0`,
`OOMKilled=false` and zero preemptions ruling memory out — the engine's jit_monitor lines show the
QSA/GDN kernels compiling **at inference** because the profile sets
`VLLM_GDN_DECODE_KERNEL=triton`, which the plain mixed-NVFP4 build must not carry, and the full-window
prefill then trips the engine's 60 s `shm_broadcast` timeout. Evidence + the exact next steps:
[`spark/reports/hd469-fast/README.md`](spark/reports/hd469-fast/README.md).

So the order is: **first** change the profile (drop that env, or pre-warm the kernel shapes — the fix
is a code edit, and a converge that boots the old argv buys nothing but a 14-minute boot and a repeat
502); **then** set `spark_llm_profile: fast` + `spark_llm_allow_uncertified: true`, converge
**detached**, and run gates 0–7 of [spark/llm-profiles/README.md](spark/llm-profiles/README.md) from a
session that is not spark-served. (b) **accuracy** — the existing captures disagree (91/100 vs 98/100,
and 99/100 elsewhere) because engine/template/effort were not held constant, so record engine,
template, thinking state and budget with every score or the number is worthless. Gate 7 is not
optional here either: the profile's `fixed_cost_bytes` is **DERIVED**, and what falsifies it is one
working day of OOM-watchdog `usable` samples **plus** the pool the engine itself reports (run #3
verified the pool from the boot line and never ran the day) — if `usable` drops toward 17.78 GiB or the
reported pool is smaller than 11 GB's worth of slots, shrink the pool and record the measured fixed
cost. Timed legs carry the sustained `clocks.sm` trace and the `/metrics` counters (§Timed
measurements); one `/tmp/hd469-fast-<HHMM>.log` per converge attempt.

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

* **Verify at both ends of every timed window — and know that the read-back cannot do it.**
  `nvidia-smi --query-gpu=clocks.max.sm` **stays 3003 with the cap on** (it is a capability field), and
  a spot `clocks.sm` read 2405 both pre-cap and post-cap, so neither proves the regime. What does:
  a `--format=csv -l 5` `clocks.sm` trace **running across** the window, under load, pasted into the
  report (2496–2515 = uncapped, ~2411 = capped). The cap is IaC-owned; an ad-hoc `-lgc`/`-rgc` inside a
  measurement window destroys the thing you are measuring — never reach for it.
* The cap sits at the **default application clock** (~3 % under where this unit actually boosts — it
  read 2496–2515 MHz), so pre-cap figures (≈11 tok/s decode, 17,008 tok/s re-prefill, `SM_CLOCK`
  2509 MHz) stay roughly comparable — but “roughly” is not “identically”: **the under-cap baseline has
  still never been recorded** (run #3 asserted one and left no measurement), so until it exists there
  is no under-cap arm to compare against at all. **One regime per A/B**: no trace, no comparison.
* **GB10 will not validate a clock value for you:** `--query-supported-clocks=graphics` → `[N/A]`,
  `-pl` is unsupported, every temperature target reads `N/A`, **and every clock read-back field is
  either a capability (3003) or a default mirror (2418)** — a graphics-clock ceiling is the *entire*
  software control surface on this SoC and sustained `clocks.sm` under load is the only proof. Details
  + the `SW Power Capping` counter: [docs/hardware-spark.md](docs/hardware-spark.md) §GPU clock cap.

## Report + commit

Write the run into `spark/reports/hd469-<profile>/` (commands, timestamps, `MemAvailable` **and
`CmaFree`** — the metric is `usable = MemAvailable − CmaFree` — at **both ends**, the sustained
`clocks.sm`/power/temp **trace** across each timed window (`-l 5`, not a spot read: `clocks.max.sm`
proves nothing here), preemption + prefix-hit + `vllm:spec_decode_*` counters **captured from
`/metrics`**, the engine’s own `Available KV cache memory` / `GPU KV cache size` lines, probe output
**verbatim**) and cite it from the catalogue — `certified_evidence:` takes a **link to that
directory**, never prose, and never a projected slot count. ⚠ **A row may not cite an evidence
directory for a number that directory does not contain** — run #3 did exactly that for the reasoning
baseline and the claim was retracted in that directory on 2026-09-29.

Already fixed for you, so do not re-do it: `hd469-graded/README.md` no longer has `(link TBD)`,
`Post-boot graded: TBD`, criteria-in-place-of-measurements in rows 3–7, the 2→7 numbering jump, or
“fixed, uncommitted” for committed code; `hd469-reasoning/` now exists and names what that lane still
owes (under-cap baseline, gates 5–7 for the refactored render).

Then: sweep the stale claims your run produced (docs + row tails), `bash scripts/validate-all.sh`
green **in the worktree**, sign the commit, **stop** (no merge). Row tails get shorter: strike what
you proved, keep what you did not — and never write “uncommitted” in a row.

**Rollback** is the same operation in the safe direction: `spark_llm_profile: reasoning`,
`spark_llm_allow_uncertified: false`, converge detached. It needs no override and no download.
