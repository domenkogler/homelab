# `prompt-llm.md` — Lane brief · certify the spark LLM profiles (HD-469 · HD-473 · HD-475) — run #4

> **Role:** dispatch note for **one** lane session on **spark**. **The rows are the authority** for what is missing and how
> to do it: [todo.md](todo.md) HD-469 · HD-473 · HD-475. This file carries the contract, the order of work, the hard rules
> and the commands — nothing else. History lives in the owning docs, in `spark/reports/**` and in git.
> **Entry:** the owner says **"read prompt-llm and run it"** — you are the operator.
> **Linked from:** [prompt.md](prompt.md) §3 · [todo.md](todo.md) · [docs/spark-llm-profiles.md](docs/spark-llm-profiles.md)

**Contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O8), which overrides README §4 / CONVENTIONS §6 at the
items it numbers. One session, one worktree, one branch. Never edit `prompt.md` / `todo-table.md` (O2); edit **only your own
`todo.md` rows**. **You hold the spark converge slot** (O3): `pgrep -af ansible-playbook` empty of other runs, and every
converge **detached** (`nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull >/tmp/hd469-<profile>-<HHMM>.log 2>&1 &`,
then poll — a tool-timeout-killed converge is worse than none, README §4.6). Engine cold boot ≈ **20 min**. Close-out =
owning docs + row tails + signed commit + `bash scripts/validate-all.sh` green **in this worktree** → **stop** (no merge).

**Rule 0 binds before anything else:**

```bash
echo "provider=$PI_PROVIDER model=$PI_MODEL"     # PI_PROVIDER=spark → you may take NO timed number
```

If your own model is spark: read-only state, logs and `/metrics` reads only, hand the timed legs over, or stop and tell the
owner. **Run #4 must be a non-spark-served session** — that is precisely why step 1 is still open.

**Read first, in this order:** [README.md](README.md) §0 + §1 → [CONVENTIONS.md](CONVENTIONS.md) §6/§7 →
[docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) (the catalogue, the arithmetic, what the gate refuses) →
[spark/llm-profiles/README.md](spark/llm-profiles/README.md) (**rule 0 + the gate ladder = your test plan, 0–9**) →
[docs/hardware-spark.md](docs/hardware-spark.md) §Unified-memory budget + §GPU clock cap → [docs/pi-harness.md](docs/pi-harness.md) §2 →
the three rows.

## Sequence

**0 · Local, before touching the box** (own fresh worktree, CONVENTIONS §6):

```bash
bash scripts/validate-all.sh                              # green, or stop
python3 scripts/check_spark_llm_gate.py                   # the gate + its canaries, offline
python3 scripts/validate-docker-services.py --only spark-ai
python3 scripts/spark-llm-probe.py matrix                 # every profile, no token needed
```

**1 · The under-cap baseline — the valuable leg, and the only one never recorded.** `spark_llm_profile` stays `reasoning`.
The clock cap **converged** (2026-09-29) but has **no read-back**: `clocks.max.sm` is a capability field (3003 lock or no
lock) and `clocks.applications.graphics` reads the default app clock — so only a **sustained `clocks.sm` trace under load**
proves the regime (2496–2515 pre-cap vs ~2411 capped). From a session that is not spark-served:

```bash
nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull >/tmp/hd469-reasoning-$(date +%H%M).log 2>&1 &
ssh spark 'nvidia-smi --query-gpu=timestamp,clocks.sm,power.draw,temperature.gpu,clocks_event_reasons.active --format=csv -l 5' >/tmp/hd469-baseline-clocks-$(date +%H%M).log 2>&1 &
python3 scripts/spark-llm-probe.py --base-url https://llm.ts.kogler.si/v1 all --profile reasoning
awk '/MemAvailable|CmaFree/' /proc/meminfo                # at BOTH ends of the window
ssh spark 'curl -s localhost:8000/metrics | grep -E "num_preemptions_total|prefix_cache|spec_decode"'
```

Paste the **raw** outputs into [`spark/reports/hd469-reasoning/`](spark/reports/hd469-reasoning/README.md) — that
directory, not the row, is what makes the baseline exist (a row may not cite a directory for a number it does not contain).
Expect: gate summary `certified: true`; the container is **not** recreated for cosmetic reasons; `clockcap` reports `ok`
**not** `changed` (`changed_when: false` by design). **This run becomes the under-cap baseline**; anything older is history,
not an A/B arm. If the render fails here, **stop and roll back the branch** — nothing downstream is testable.

**2 · `graded` — the correct outcome is a report, not a converge** (fp8 KV is blocked on the image → HD-473):

```bash
python3 scripts/spark-fp8-image-probe.py --tag-filter 'qwen|flash'    # exit 0 = verdict reached, ~40 s, no GPU
```

`REACHABLE` ⇒ the registry changed under us and HD-473 is open again — say so loudly, and do not flip a profile on the
strength of a grep. `UNDECIDED` means a leg could not run: that is **not** a verdict.

**3 · The NVFP4/PLE artifacts are already STAGED — verify, do not re-fetch** (a needless 117 GB re-fetch on a shrinking
disk is how you fill the data store):

```bash
ssh spark 'cat /mnt/spark_nvme/models/Qwen3.8-Flash-Next-mixed-NVFP4-FP8/.index-trimmed; find /mnt/spark_nvme -maxdepth 2 -name "ple-bf16-*" | head; df -h /mnt/spark_nvme | tail -1'
```

Re-run the fetch **only if a verify fails**, detached, naming the missing kinds
(`--tags spark-artifacts -e spark_artifacts_fetch='["nvfp4-mixed","ple-nvfp4"]'`).

**4 · The NVFP4 candidate profile is HD-475's, and it is CODE-FIRST.** It booted healthy (`GPU KV cache size: 354,248` =
1.35×, `RestartCount=0`, so the derived `fixed_cost_bytes` held) and **failed gate 3**: the 262k leg 502s at ~105 s and
`concurrent 4` fails 0/4 with memory ruled out — the QSA/GDN kernels JIT **at inference** because the profile sets
`VLLM_GDN_DECODE_KERNEL=triton`, which the plain mixed-NVFP4 build must not carry. **Fix the profile first** (drop that env
or pre-warm the shapes), then flip + converge detached from a non-spark session and run gates 0–7 + the accuracy battery.
⚠ **Name warning:** the dial value `fast` was reused 2026-10-03 for the HD-489 winner (AR-hybrid, live); this step's `fast`
is the retired NVFP4 lane — read [docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) §7 before touching the dial. Record
engine / template / thinking state / budget with **every** accuracy score: the existing captures disagree (91 / 98 / 99) for
exactly that reason. Evidence: [`spark/reports/hd469-fast/README.md`](spark/reports/hd469-fast/README.md).

**5 · `fast-sglang` — expect a refusal, and that is the pass.** `spark_sglang_image` is empty on purpose (CONVENTIONS §7: no
floating tag), and three blockers are documented in the catalogue comments +
[docs/hardware-spark.md](docs/hardware-spark.md) §DGX Spark host limits. **Do not spike it in this window.** If a spike is
ever authorised: production engine stopped, own window, `MemAvailable` watchdog, CDI device access,
`--ple-offload-backend file` with the NVMe bind in IaC, and the previous `ple_table_*.bin` deleted before boot.

**6 · The client half is an owner gate.** Every profile serves the same 262,144 window today, so
`scripts/pi-config/models-spec.yml` needs nothing. If a profile ever serves a different window, that profile's
`client_context_window` must ship in the **same** change or pi 400s mid-session. Graded reasoning is **client-side**
(`thinking_token_budget` per level, not `reasoning_effort`). Both client files are workstation-owned and carry the bearer:
propose the diff, the owner applies it ([docs/pi-harness.md](docs/pi-harness.md) is the reference copy).

## ⛔ Non-negotiables (each line cost an outage or a power-cycle)

* **Never** raise `max_model_len` above 262,144; never raise a profile's `fixed_cost_bytes` or the host-floor ceiling to
  make a gate pass; never `--quantization` on the vLLM CLI (checkpoints declare their own format); `gpu_memory_utilization`
  is a **dead config** in this build — do not resurrect it. **Do not work around an assert by editing the assert.**
* **No bench numbers while an agent session is attached**, and never with your own model = spark. `vllm bench serve` 401s
  every request against the `--api-key` engine **and exits 0** (HD-380) — assert on counters.
* **Read-only beats reboot-first**: `docker run --rm --entrypoint sh <image> -c '…'` is allowed (never `--gpus`, never `-p`,
  never `-d`, never during a converge); `scripts/spark-fp8-image-probe.py` refuses to pull. **Never `reboot spark`.**
  `docker stop` of the engine is intentional in the watchdog path — if you stop it, you own restarting it via converge.
* **Timed legs carry the clock trace.** `clocks.max.sm` stays 3003 with the cap on and a spot `clocks.sm` read proves
  nothing; only a `--format=csv -l 5` trace **across** the window does. GB10 will not validate a clock value for you
  (`--query-supported-clocks` → `[N/A]`, `-pl` unsupported, every read-back field is a capability or a default mirror) — see
  [docs/hardware-spark.md](docs/hardware-spark.md) §GPU clock cap. One regime per A/B: **no trace, no comparison**.
* **Secrets:** the bearer is `spark-llm_api` in 1Password, read via `op` or by the probe. It never goes in argv, a file, a
  commit or the transcript.

## Report + commit

Write the run into `spark/reports/hd469-<profile>/`: commands, timestamps, `MemAvailable` **and** `CmaFree` at **both ends**
(the metric is `usable = MemAvailable − CmaFree`), the sustained `clocks.sm`/power/temp **trace** across each timed window,
the preemption + prefix-hit + `vllm:spec_decode_*` counters **from `/metrics`**, the engine's own
`Initial free memory` + `GPU KV cache size` lines, and probe output **verbatim**. `certified_evidence:` takes a **link to
that directory**, never prose and never a projected slot count. Then sweep the claims your run made stale (docs + row
tails), `bash scripts/validate-all.sh` green **in the worktree**, sign, **stop**. One `/tmp` log per converge attempt — a
retry truncates the only record of the failed one.

**Rollback** is the same operation in the safe direction: `spark_llm_profile: reasoning`,
`spark_llm_allow_uncertified: false`, converge detached. No override, no download.
