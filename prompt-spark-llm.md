# `prompt-spark-llm.md` — Lane brief · the spark engine: profiles, certify, bench evidence

> **Role:** dispatch note for **one** lane session on the **spark** GB10 engine. **The rows are the authority** for what is
> missing and how to do it — this file carries the contract, the order of work and the traps, nothing else:
> [todo.md](todo.md) **HD-469 · HD-473 · HD-475 · HD-489 · HD-494 · HD-376 · HD-400 · HD-359 · HD-367 · HD-380**
> (row ids as of `9e661845` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O9) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers and this brief deliberately restates none of them.

**Converge host + slot (O3):** **spark**, one converge in flight, and `spark-ai` is one service directory. Everything
timed runs **detached** (`nohup … &` + log + poll; engine cold boot ≈ 15–20 min). ⛔ **Do not share a wave with any other
spark-slot lane** — this host has a single slot, so a second lane here is never parallel work, only a collided converge;
pair instead with an oldsrv- or VPS-slot lane. A bench must never sit under a changed scrape cadence, and never beside a
probe lane standing things up on the same box.

**Rule 0 before anything timed:** `echo "provider=$PI_PROVIDER model=$PI_MODEL"` — a session whose own model is served by
`spark/…` may take **no timed number** (counter / log / `/metrics` / `docker inspect` reads are legal from any session).
Stamp every leg with `--client` and declare the seat in the session's first line.

**Read first:** [docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) (the catalogue, the arithmetic, §7 = what the dial
value `fast` means **today**) → [spark/llm-profiles/README.md](spark/llm-profiles/README.md) (rule 0 + the gate ladder =
the test plan) → [docs/hardware-spark.md](docs/hardware-spark.md) §Unified-memory budget + §GPU clock cap →
[spark/BENCHMARK-PLAN.md](spark/BENCHMARK-PLAN.md) §6/§6a/§9 → [docs/pi-harness.md](docs/pi-harness.md) §2–§3.

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-469** | Take the `reasoning` **under-cap baseline**: sustained `clocks.sm`/power/temp trace across a timed window + `MemAvailable` **and** `CmaFree` at both ends + `/metrics` counters, into [`spark/reports/hd469-reasoning/`](spark/reports/hd469-reasoning/README.md) | Only a `-l 5` trace **across** the window proves the regime: `clocks.max.sm` is a capability field and a spot read says the same capped and uncapped. From a non-spark-served session (rule 0) |
| 2 | **HD-469** | `reasoning` gates **5–6** for the refactored render: the needle at ≥ 90 % depth 3/3, then the accuracy battery | Gate 7 is **closed on the live regime** (HD-489 / HD-494 carry the read) — do not re-run it as this row's work. One `/tmp/hd469-<profile>-<HHMM>.log` per converge attempt: a retry truncates the only record of the failed one |
| 3 | **HD-473** | The engine-pin lane: pin a registry-verified **arm64** digest that carries fp8 main KV, re-anchor the primitive-ai PLE overlay to the new module paths, re-certify `reasoning` **before** touching `graded` | The first-pin rule is CONVENTIONS §7 and the verification goes in the **same** change. Verify, do not assume: the image `v0.30.0` does **not** carry vllm#55557 (it carries indexer-side fp8 #54890); patching site-packages is the rejected route |
| 4 | **HD-475** | Drop `VLLM_GDN_DECODE_KERNEL=triton` from the NVFP4 `fast` arm (or pre-warm the kernel shapes), converge detached, re-run gates 0–7 + the battery | Gate 3's 502 at ~105 s is JIT-at-inference, not memory (`RestartCount=0`, zero preemptions ruled that out). **Verify the staged artifacts, never re-fetch** the ~117 GB: the staged set is `.index-trimmed` with **no `ple-bf16-*`**, so do not gate on finding one |
| 5 | **HD-489** | The certificate's last line: gate 6's battery at `max_tokens 16 384` **with the B1 `reasoning` baseline re-run in the same change**, then rewrite `fast.certified_evidence` to the legs the 20 GB shape actually holds | The budget was **ruled, not applied** — it lives as `max_tokens:1024` in [spark/bench/accuracy-gate.sh](spark/bench/accuracy-gate.sh). Grading the reasoning arm against a baseline made under the old budget is not a measurement, so the two edits ship together or neither does. Gate 7 needs nothing here |
| 6 | **HD-494** | One **1 s `usable` sampler across one heavy prefill** on the current regime, hand the number over, and let the owner pick the floor (CRIT vs WARN) | The arithmetic is done and the **global value is deliberately unchanged**; the ledger's rest prediction is ~2.7 GiB optimistic, so the missing term is measured, not argued |
| 7 | **HD-376** | The **262k needle test** per profile, then promote the paper-only **`spark-lane` 64k** profile into IaC with the parent-vs-lane KV-contention measurement | Needle-test every profile at the depth it serves — a pass at 32k is not a pass at 262k (the ≥120k sm_12x corruption trap, sglang#36806 / #36845). 262,144 is the servable ceiling; "273k" is KV slots, never a client value |
| 8 | **HD-400** | Decide the text-only engine mode: `--limit-mm-per-prompt '{"image": 0, "video": 0}'` (≡ `--language-model-only`), optionally `--mm-processor-cache-gb 0` | **Proposed, bench-gated, NOT applied.** The win is memory, not speed (no image tokens ⇒ the ViT never runs ⇒ decode flat). The `image=0,video=0` comma form **errors** on the pinned vLLM (#39687) — JSON only — and an image part then becomes a hard **400** |
| 9 | **HD-359 · HD-367** | The ladder tails: the S2/S3 × SGLang lane (weights IaC exists in `roles/spark-artifacts`; missing = manifest entries + compose + harness param), the safe C3/warm re-run into [spark/BENCHMARK-PLAN.md](spark/BENCHMARK-PLAN.md) §9, the tool-call **EMPTY** fix and a true 3×87k fill | Accuracy is the anchor for both arms — NVFP4 is a throughput play, so it is accuracy-gated too. ⛔ Ladder #10 (LMCache KV offload) is in the rejected log: not open work, not to be re-proposed |
| 10 | **HD-380** | The never-taken measurement: prefix-cache hit rate + preemption counter off `/metrics` across one normal working day vs the pre-raise numbers ([spark/stability-test.md](spark/stability-test.md) §6a) | The standing `gpu_top_mib` **> 2 GiB/h under traffic that does not return at idle** condition is the only thing that re-arms C3 `--enforce-eager`; `--enforce-eager` stays off **on measurement**, not on deferral |

## ⛔ Traps that cost a round (re-grounded at this `HEAD`)

* **SSOT = live.** Read the engine's real values off the box **and** from `IaC/ansible/group_vars/spark.yml`; a bench table
  records what was benched, not what is live. `spark_llm_pool_ceiling_bytes` is **16 GiB** (`group_vars/spark.yml:303`) and
  the live `fast` profile overrides it **for itself** with `pool_ceiling_bytes: 20000000000` = 20 GB
  (`group_vars/spark.yml:981`). Never "restore" the global onto a profile, and **never raise** a `pool_ceiling_bytes`,
  `fixed_cost_bytes`, `spark_llm_device_hold_ceiling_bytes` or host floor to make a gate pass — the measurement is what
  changes, not the certified constant.
* Never raise `max_model_len` above **262,144** (an override needs YaRN + a fresh needle test); `gpu_memory_utilization`
  is a **dead config** on this build — the pool is owned by the per-profile `kv_cache_memory`; never pass `--quantization`
  on the CLI (checkpoints declare their own format). Do not work around a failing assert by editing the assert.
* **GB10 will not validate a clock value for you** (`--query-supported-clocks` → `[N/A]`, `-pl` unsupported). One clock
  regime per A/B arm: **no trace, no comparison** — see [docs/hardware-spark.md](docs/hardware-spark.md) §GPU clock cap.
* **Cold prefill is NVMe-bound** (first max-fill request after a restart ≫ a warm repeat): plan the window around it.
  `docker stop` of the engine inside the watchdog path is **intentional** — `unless-stopped` will not bring it back, so if
  you stop it you own restarting it via converge ([spark/stability-test.md](spark/stability-test.md) §5). **Never `reboot spark`.**
* `vllm bench serve` **401s every request** against the `--api-key` engine **and exits 0** — assert on counters, not on exit code.
* **fp8 KV is BLOCKED-ON-IMAGE** until the pin moves. Probe before touching a container: `scripts/spark-fp8-image-probe.py`
  already takes `--image`, so the built lineage is reachable without patching the script
  (`spark_vllm_ultrafast_image`, `group_vars/all/versions.yml:447`; the base pin is `versions.yml:418`). A `UNDECIDED` run
  is **not** a verdict; `REACHABLE` means the registry changed under us — say so loudly, never flip a profile on a grep.
* `spark_sglang_image` is **empty on purpose** (`group_vars/all/versions.yml:428`): `fast-sglang` must fail loud at the
  dial, which is the point of CONVENTIONS §7. Do not spike it in a normal window.
* Read-only beats reboot-first: `docker run --rm --entrypoint sh <image> -c '…'` is allowed — never `--gpus`, `-p`, or
  `-d`, and never during a converge. The probe refuses to pull.
* **Secrets:** the engine bearer is the `spark-llm_api` vault item, read via `op` or by the probe; it never reaches argv,
  a file, a commit or the transcript.
* **Owner-gated, never self-authorised:** any dial flip (an uncertified one carries a **per-run `-e`**, never a committed
  `spark_llm_allow_uncertified: true`), any edit to `spark_llm_ple_pairing`, `drop_caches`, a monitoring converge, or an
  arm already in [docs/services-ai-rejected.md](docs/services-ai-rejected.md) without the §8.3 exception note.

## Owns / never touches

**Owns:** `IaC/ansible/roles/spark/**`, `roles/spark-llm-profile/**`, `roles/spark-artifacts/**`,
`roles/spark-ultrafast-build/**`, `IaC/ansible/group_vars/spark.yml`, `spark/**` (bench plans, harness, `reports/**`),
`docs/hardware-spark.md`, `docs/spark-llm-profiles.md`, `docs/hardware-gpu.md` for spark's side, and your own `todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2) or any other brief's rows; `docs/services-ai*.md` and
`templates/docker_services/**` (the litellm lane's, O3); `roles/monitoring/**` and `roles/spark/files/spark-oom-watchdog.sh`
(no live brief owns them — read the row first, and never change the scrape cadence mid-bench); `roles/router/**`; the frozen
archives and generated `*-generated.md`.

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path counts as
not run. Concretely: the `reasoning` baseline trace in `spark/reports/hd469-reasoning/` · per-profile needle results with
the depth that passed or failed · `fast.certified_evidence` rewritten with the 16 384-token battery **and** its re-run B1
baseline in the same change · HD-475's re-cert with engine / template / thinking state / budget recorded beside every score
· HD-400 applied with a before/after memory table **or** "not applied, and here is the number that decided it" · the
`spark-lane` 64k profile in IaC with the contention number · nothing converged over a certified constant without a diff ·
closed rows deleted and the rest trimmed to their tails (no history in the row) · `bash scripts/validate-all.sh` green
**in this worktree** → **stop**.
