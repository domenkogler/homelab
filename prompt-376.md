# `prompt-376.md` — Lane brief · prove spark's long context, then give the lanes a window (HD-376 · HD-400 · HD-359/HD-367 ladder tails · HD-380)

> **Role:** the **spark engine lane** — the measurements that stand between "certified for casual chat" and
> "trusted for agentic max-context", plus the engine-mode question. **Wave 3.** It needs an **owner bench window**:
> detached runs only, **never with an agent session attached**, and **never driven from a session whose own model is
> spark** (incidents #3 + #6 — the chain's preflight refuses to start unless in-flight is 0 for exactly this reason).
> This brief also **absorbs the stale `prompt-next.md`** handoff (2026-09-15, deleted by the parent 2026-09-22 per
> [prompt.md](prompt.md) §4 O7): its §3 pending-tests list is row 1 of this lane.
> Start with [README.md](README.md) §0 → §1 mandatory context → [prompt.md](prompt.md) **§4 (orchestrator mode)** →
> this file → [`spark/BENCHMARK-PLAN.md`](spark/BENCHMARK-PLAN.md) §6/§6a/§9 → the rows in [todo.md](todo.md) §2 (spark).
> **Linked from:** [prompt.md](prompt.md) §2 + §4 · [todo.md](todo.md) · [todo-table.md](todo-table.md)
>
> **Lane contract (orchestrator mode — the authority is [prompt.md](prompt.md) §4, which OVERRIDES parts of
> README §4 and CONVENTIONS §6 at items O1–O8; where §4 is silent, README + CONVENTIONS stand and outrank this
> brief).** One session, one worktree, one branch; the parent creates them (`../homelab-wt-<YYYYMMDD>-<HHMM>` /
> `session/376-spark-<YYYYMMDD>-<HHMM>`). **You hold the spark converge slot** (O3) and every long run is
> **detached** (`nohup … &` + log + poll). Owner gate → **park and continue** (O4): without a bench window, write the
> exact command sequence into the row tail and do the repo-side work only. Close-out =
> `docs/hardware-spark.md` + `spark/*` + row tails + signed commit + `bash scripts/validate-all.sh` green **in this
> worktree** → **stop**.

## Rows

| # | HD | Action | Gate / note |
|---|----|--------|-------------|
| 1 | **HD-376** | **The 262k needle test** (long-context *correctness*, not just "did not crash"), then promote the **`spark-lane` 64k profile**, then measure parent-vs-lane KV contention | ⚠ The corruption trap **≥120k on sm_12x** is documented (sglang#36806 / #36845) — needle-test **every** profile. A 262k session ≈ **56 %** of the OLD pool, which is *why* agent lanes need a smaller window. Absorbs `prompt-next.md` §3 items 1–3: needle at 262k, the **tool-call EMPTY** fix (`--enable-auto-tool-choice` registers nothing — it blocks agentic work), and a **true 3×87k-token fill** (the concurrent gate used ~100 tok prompts) |
| 2 | **HD-400** | **Proposed, bench-gated, NOT applied:** `--limit-mm-per-prompt '{"image": 0, "video": 0}'` (≡ `--language-model-only`) ± `--mm-processor-cache-gb 0` | ⚠ **It is not a speed change** — no image tokens ⇒ the ViT never executes ⇒ C2 decode expected **flat**; the win is memory on the boot-bound side (ViT ≈0.5–1 GiB + the 4 GiB mm-cache default), where **1 GiB ≈ 32.2k KV tokens**. ⚠ the comma form `image=0,video=0` **errors** on current vLLM (#39687) — JSON only; module-skipping on disable is per-model-implementation upstream (#21943) — **measure on the pinned fork**. Spend the freed GiB in a **separate** row. Consequence accepted upstream: an image part becomes a hard **400** — weigh it in HD-384 · [hardware-workstation.md](docs/hardware-workstation.md) |
| 3 | **HD-359 / HD-367** | The ladder tails that remain: the **S2/S3 NVFP4 × SGLang** lane (weights-download IaC exists in `roles/spark-artifacts`; missing = manifest entries + SGLang compose + harness param) | Accuracy-anchor 98/100 is **AWQ-only**; NVFP4 is a throughput play, so it is accuracy-gated too. ⛔ **Ladder #10 (LMCache KV offload) is REJECTED 2026-09-20** — it silently corrupts shared-prefix output for hybrid GDN models on this hardware class (its own #4247/#4701, fix unmerged). Not open work, not to be re-proposed |
| 4 | **HD-380** | Passive: watch `samples.csv` for a curve growing **> 2 GiB/h** under traffic that does not return at idle — that, and only that, re-arms C3 — plus the never-measured prefix-cache / preemption check across the 16 GiB raise | Certified state is stable; this is a standing watch, not a fix. `--enforce-eager` (C3) stays **off on measurement**, not on deferral |

## ⛔ The hard floor (each of these has cost an outage or a wedge)

* **Never raise `gpu_memory_utilization` above 0.82** — 0.84+ crashes the engine during serve and can **wedge the
  host** (power-cycle recovers). **Never raise ctx above 262,144** — startup validation rejects; an override needs
  YaRN + a needle test.
* **SSOT = live**: the certified config is `spark_vllm_kv_cache_memory: "16000000000"` (16 GiB pool, 515,786 tok,
  1.97× @262k) — **do not converge spark back to the pre-cert 8.2 GiB**, and re-read the live values from
  `group_vars/spark.yml`, **not** from the §9 bench table (that records what was benched, not what is live).
* **16 GiB is the bf16 ceiling**; idle `usable` is **18.5 GiB** (`MemAvailable − CmaFree`, CRIT 8 / WARN 12), so
  anything new installed on spark spends a **6.5 GiB margin**, and more KV is `--kv-cache-dtype fp8`'s job, not
  Linux's reserve.
* **Cold prefill is NVMe-bound** (~465 MB/s → ~13 min TTFT for the first max-fill request after a restart; warm
  repeat ≈ 1640 tok/s). Plan the window around that; `docker stop` is **intentional** so `unless-stopped` will not
  bring the engine back ([`spark/stability-test.md`](spark/stability-test.md) §5).
* **Decision #28 stands:** spark is the **text-only** generation tier; token-level split inference is
  **unbuildable**, not merely expensive. The RX 7600 takes no vision-LLM leg · [services-ai.md](docs/services-ai.md) §9 #28.

## First action

Re-read the live engine config off the box **and** from `group_vars/spark.yml`, confirm they agree, and confirm the
watchdog is not mid-recycle (HD-395 is in [`prompt-420.md`](prompt-420.md) — if that lane has merged, the baseline
rule may already have changed; say which version you benched on).

## Lane rules (Wave 3 — pair with [`prompt-384.md`](prompt-384.md) **only**, and only in an open bench window)

* **Owns:** `IaC/ansible/roles/spark/**`, `IaC/ansible/roles/spark-artifacts/**`, `IaC/ansible/group_vars/spark.yml`,
  `spark/**` (bench plans, harness scripts, `reports/**`), `docs/hardware-spark.md`,
  `docs/hardware-gpu.md` **for spark's side**, and **your own `todo.md` rows**.
* **Never touches:** `prompt.md` / `todo-table.md` (O2) — the third file that rule used to name, `prompt-next.md`,
  is deleted 2026-09-22;
  `IaC/ansible/roles/monitoring/**` + `templates/docker_services/spark-dcgm/**` +
  `roles/spark/files/spark-oom-watchdog.sh` (all [`prompt-420.md`](prompt-420.md) — ⛔ **never the same wave as 420**:
  both converge spark, and a bench under a changed scrape cadence is not the certified measurement);
  `roles/router/**` (414); `docs/services-ai.md` + `roles/docker_services/**` (384); the frozen archives and
  generated `*-generated.md`.

## Acceptance

Needle-test results **per profile** with the depth that failed or passed recorded (a pass at 32k is not a pass at
262k) · the `spark-lane` 64k profile in IaC with the contention measurement quoted · HD-400's before/after memory
table **or** an explicit "not applied, and here is the number that decided it" · the S2/S3 verdict written into
[BENCHMARK-PLAN.md](spark/BENCHMARK-PLAN.md) §9 · nothing converged over the certified values without a diff shown ·
closed rows deleted, others trimmed · `bash scripts/validate-all.sh` green **in this worktree** → **stop**
([prompt.md](prompt.md) §4).
