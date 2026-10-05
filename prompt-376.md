# `prompt-376.md` — Lane brief · prove spark's long context, then give the harness a window (HD-376 · HD-400 · HD-359/HD-367 ladder tails · HD-380)

> **Role:** dispatch note for **one** lane session on the **spark** engine. **The rows are the authority** for what is
> missing and how to do it: [todo.md](todo.md) HD-376 · HD-400 · HD-359 · HD-367 · HD-380. This file carries the contract,
> the order of work, the hard floor and the traps — nothing else. History lives in the owning docs and in git.
> **Linked from:** [prompt.md](prompt.md) §3 · [todo.md](todo.md) · [todo-table.md](todo-table.md)

**Contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O8), which overrides README §4 / CONVENTIONS §6 at the
items it numbers. One session, one worktree, one branch, one brief. Never edit `prompt.md` or `todo-table.md` (O2); edit
**only your own `todo.md` rows**. **You hold the spark converge slot** (O3) and every long run is **detached**
(`nohup … &` + log + poll). Owner gate → **park and continue** (O4): with no bench window, write the exact command sequence
into the row tail and do the repo-side work only. Close-out = `docs/hardware-spark.md` + `spark/**` + row tails + signed
commit + `bash scripts/validate-all.sh` green **in this worktree** → **stop**.

**This lane needs an owner bench window:** detached runs only, **never with an agent session attached**, and never driven
from a session whose own model is spark (rule 0 — the chain's preflight refuses to start unless in-flight is 0).
⛔ Never in the same wave as [prompt-llm.md](prompt-llm.md) (both converge spark, and a bench under a changed scrape
cadence is not the certified measurement); pair with [prompt-384.md](prompt-384.md) **only** inside an open bench window.

**Read first:** [spark/BENCHMARK-PLAN.md](spark/BENCHMARK-PLAN.md) §6/§6a/§9 ·
[spark/llm-profiles/README.md](spark/llm-profiles/README.md) (rule 0 + the gate ladder) ·
[docs/hardware-spark.md](docs/hardware-spark.md) §Unified-memory budget · [docs/pi-harness.md](docs/pi-harness.md) §2.

## Order of work

| # | Row | Do | Gate / note |
|---|-----|----|-------------|
| 1 | **HD-376** | The **262k needle test**, then promote the **`spark-lane` 64k profile** into IaC, then measure parent-vs-lane KV contention | Needle-test **every** profile at the depth it serves (the ≥120k corruption trap on sm_12x: sglang#36806 / #36845). A 262k session ≈ 56 % of the OLD pool — which is *why* agent lanes need a smaller window. Also owed: the tool-call **EMPTY** fix and a true 3×87k-token fill (HD-367's row carries both) |
| 2 | **HD-400** | Decide the text-only engine mode: `--limit-mm-per-prompt '{"image": 0, "video": 0}'` (≡ `--language-model-only`), optionally `--mm-processor-cache-gb 0` | **Proposed, bench-gated, NOT applied.** It is not a speed change — no image tokens ⇒ the ViT never runs ⇒ decode expected flat; the win is **memory** on the boot-bound side (ViT ≈0.5–1 GiB + the 4 GiB mm-cache default; 1 GiB ≈ 32.2k KV tokens). ⚠ the comma form `image=0,video=0` **errors** on the pinned vLLM (#39687) — JSON only; module-skipping is per-model-implementation (#21943), so measure on the pinned build. An image part becomes a hard **400** — weigh it in HD-476 |
| 3 | **HD-359 / HD-367** | The ladder tails: the **S2/S3 × SGLang** lane (weights IaC exists in `roles/spark-artifacts`; missing = manifest entries + SGLang compose + harness param) | Accuracy anchor is AWQ-only; NVFP4 is a throughput play, so it is accuracy-gated too. ⛔ Ladder #10 (LMCache KV offload) is **REJECTED** — it corrupts shared-prefix output for hybrid GDN models on this hardware (its own #4247/#4701, fix unmerged). Not open work, not to be re-proposed |
| 4 | **HD-380** | Passive watch: `samples.csv` growing **> 2 GiB/h** under traffic that does not return at idle re-arms C3 — plus the never-measured prefix-cache / preemption check across the pool raise | A standing watch, not a fix. `--enforce-eager` (C3) stays off **on measurement**, not on deferral |

## ⛔ The hard floor (each line cost an outage or a power-cycle)

* **SSOT = live.** Read the engine's real values from `IaC/ansible/group_vars/spark.yml` (and off the box), **not** from a
  bench table — a bench table records what was benched, not what is live. The certified global pool ceiling is 16 GiB; the
  live `fast` profile runs a larger pool under a **named per-profile** `pool_ceiling_bytes`, so never "restore" a pool size.
* Never raise `max_model_len` above **262,144** (startup validation rejects; an override needs YaRN + a needle test).
  `gpu_memory_utilization` is **gone from this build** — `--kv-cache-memory-bytes` owns the pool; a dead config line is not a knob.
* **Never raise a profile's `fixed_cost_bytes` or the host-floor ceiling to make a gate pass** — the measurement is the
  thing to change, not the constant ([docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) §The gate).
* **Cold prefill is NVMe-bound** (first max-fill request after a restart ≫ a warm repeat). Plan the window around it.
  `docker stop` of the engine is **intentional** in the watchdog path — `unless-stopped` will not bring it back
  ([spark/stability-test.md](spark/stability-test.md) §5); if you stop it, you own restarting it via converge.
* **Decision #28 stands:** spark is the **text-only** generation tier; token-level split inference is unbuildable, not
  merely expensive ([docs/services-ai.md](docs/services-ai.md) §9 #28).

## First action

Re-read the live engine config **off the box** *and* from `group_vars/spark.yml`, confirm they agree, and confirm no
converge or watchdog recycle is in flight ([docs/hardware-spark.md](docs/hardware-spark.md)); say which build/render you
are benching, or the numbers are unattributable.

## Owns / never touches

**Owns:** `IaC/ansible/roles/spark/**`, `roles/spark-artifacts/**`, `IaC/ansible/group_vars/spark.yml`, `spark/**` (bench
plans, harness, `reports/**`), `docs/hardware-spark.md`, `docs/hardware-gpu.md` **for spark's side**, your own `todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2); `roles/monitoring/**`, `templates/docker_services/spark-dcgm/**`,
`roles/spark/files/spark-oom-watchdog.sh` (unowned by any live brief — read the row before touching, and never change the
scrape cadence mid-bench); `roles/router/**`; `docs/services-ai.md` + `roles/docker_services/**`
([prompt-384.md](prompt-384.md)); the frozen archives and generated `*-generated.md`.

## Acceptance

Needle results **per profile** with the depth that failed or passed (a pass at 32k is not a pass at 262k) · the
`spark-lane` 64k profile in IaC with the contention measurement quoted · HD-400's before/after memory table **or** an
explicit "not applied, and here is the number that decided it" · the S2/S3 verdict written into
[spark/BENCHMARK-PLAN.md](spark/BENCHMARK-PLAN.md) §9 · nothing converged over the certified values without a diff shown ·
closed rows deleted, others trimmed · `bash scripts/validate-all.sh` green **in this worktree** → **stop**.
