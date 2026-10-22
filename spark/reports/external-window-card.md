# spark external-window card — one ordered run over eight rows

> **Role:** the dispatcher for ONE externally-served sitting of the spark rows — which leg runs in which
> order, what must already be true when it runs, and what it must never touch. Every instrument named here
> but the image probe is landed and registered with `--self-test` (`scripts/validate-all.sh:1489-1495`);
> this page is an ORDER, not an instrument and not a verdict.
> **Linked from:** [`todo.md`](../../todo.md) rows HD-469 · HD-473 · HD-475 · HD-489 · HD-494 · HD-376 ·
> HD-400 · HD-380, and one line in [`prompt-spark-llm.md`](../../prompt-spark-llm.md).
> **Authority: none.** The owning doc named in §3 wins wherever this page disagrees with it. Flags,
> verdicts and exit codes below are read out of the scripts, with the line cited, not from memory.

---

## 1. Who may run this at all

`echo "provider=$PI_PROVIDER model=$PI_MODEL"` — if the provider is `spark`, every timed leg on this page is
barred for the **whole run, children included** (Rule 0 in
[`spark/llm-profiles/README.md`](../llm-profiles/README.md); the dispatch filter in
[`docs/orchestration.md`](../../docs/orchestration.md) §4), because the session's own tokens land in the
pool and in the counters it would then quote. The designated runner station is the **WSL Debian seat**
([`prompt-laptop-wsl.md`](../../prompt-laptop-wsl.md) §0/§1, `todo-table.md` §C rule 9) — and standing on
that seat does **not** lift Rule 0: the seat answers *which box*, the model answers *whether a timed leg is
allowed at all*, and rule 9 says the exclusion binds "the whole run wherever it sits".

Two instruments stay legal from **any** session, a spark-served one included, because a read is not a timed
number: [`text-only-preflight.sh`](../../scripts/bench/spark/text-only-preflight.sh) reads a `config.json`,
`docker inspect` argv and the repo tree and issues no request, which is why it carries no guard at all
(`:14-22`); [`metrics-window.sh`](../../scripts/bench/spark/metrics-window.sh) samples five `/metrics`
counters plus `MemAvailable`−`CmaFree` and prints the same argument from its own `--help` (`:152-175`, and
the deliberate absence of a Rule 0 exit code at `:93-94`). Everything else on this page drives load through
the engine and **refuses a spark-served seat on its own first line**.

## 2. The order of legs

Order rule: reads first — they cost nothing and can invalidate a later leg; then the legs that run on the
profile **already serving**; then anything needing a flip, because a flip is an owner-window engine recreate
of ~20 min, so legs are grouped one profile per boot window.

| Row | Script and the flags that decide it | Acceptance, one line | Must already be true | Must NOT touch |
|---|---|---|---|---|
| **HD-380** | [`metrics-window.sh`](../../scripts/bench/spark/metrics-window.sh) `--report` (`--status` to poll) — **already running, §6** | `--report` prints a hit rate and a preemption delta beside the pre-raise numbers read **by path** out of [`spark/stability-test.md`](../stability-test.md) — today the hit figure at its `:167`, quoted with path and line (`metrics-window.sh:385-397`) | ≥ 2 usable samples in the window file; `--interval` has a 5 s floor (`:179`) | nothing — one ssh per sample, no mutate verb (`:33-40`); a second sampler writing one CSV is refused by name (`:456-461`) |
| **HD-400** | [`text-only-preflight.sh`](../../scripts/bench/spark/text-only-preflight.sh) (`--config-file` judges a staged checkpoint off-line; `--dry-run` prints the four reads and contacts nothing, `:386-398`) | exit 0 with all four answers printed — "the ViT is loaded" is a FINDING, not a failure (`:63-64`) | the container is running, else exit 6 (`:281`); or `--config-file` was passed instead | nothing — and applying the `args_extra` line it prints is an **owner-window** IaC act that re-creates `spark-ai` (`:264-267`) |
| **HD-473** | [`spark-fp8-image-probe.py`](../../scripts/bench/spark-fp8-image-probe.py) `--skip-box` (registry leg only) or the box leg | a verdict line and exit 0; at this HEAD it reads **`BLOCKED-ON-IMAGE`** (`:311-319`) — an undecided leg exits 1 and is NOT a verdict (`:29-31`). Leg A's walk is bounded by `pages=4` (`:115`); the sweep that decided this row went wider, over all 688 tags, so quote the sweep and not the default | egress for Leg A; for the box leg, no converge in flight — the probe refuses one with exit 2 (`:277-280`) | the container's state: Leg B is `docker run --rm --entrypoint sh`, never `--gpus`, `-p` or `-d`, and it pulls nothing (`:20-24`) |
| **HD-489** | [`gate6-couple.sh --max-tokens 16384`](../../scripts/bench/spark/gate6-couple.sh) (the default already *is* the ruling, `:92`; `--dry-run` prints both legs and touches nothing, `:527-542`) | both legs graded at the SAME budget read back **off the wire**, on an engine whose boot identity did not move between them | an externally-served session on the runner station, and the battery running where the engine container is visible — it reads the bearer out of `docker inspect` | `--battery-only`, which refuses always (exit 4); never `accuracy-gate.sh` alone at 16 384 — its own default stays 1024 (`accuracy-gate.sh:35`) |
| **HD-494** | [`usable-sampler.sh`](../../scripts/bench/spark/usable-sampler.sh) (`--profile fast` is the default, `:78`; `--tokens` only if IaC cannot answer, `:229-230`) | the floor over the window, the ledger's prediction and the delta between them — and **no** floor choice, which stays the owner's | the box serves the profile named; `MemAvailable` and `CmaFree` both arrive, since a missing field is never read as a zero | the certified constants — it reads the declared hold out of IaC and writes only its own evidence dir |
| **HD-376** | [`needle-window.sh`](../../scripts/bench/spark/needle-window.sh) `--profile <name> [--reps 3] [--no-window]` (`--dry-run` prints the plan the catalogue derived, `:568-595`) | PASS-DEPTH per profile = HTTP 200 **and** `prompt_tokens` ≥ 80 % of that profile's own `max_model_len` (`:133` — the floor gate 3 can actually clear) | the named profile is the one serving (a name the box is not serving exits 4, `:407`); an uncertified arm also needs the per-run `-e spark_llm_allow_uncertified=true` (`:327-331`) | any depth above 262,144 (exit 5, `:200`); any flip of its own — it never converges; and any claim that the needle *recalled*: this proves the window HELD |
| **HD-469** | [`hd469-baseline.sh`](../../scripts/bench/spark/hd469-baseline.sh) (`--profile reasoning` is the default, `:66`; `--interval 5 --window 1800`, `:70-71`) | the file set under `spark/reports/hd469-reasoning/`, with the `clocks.sm` trace taken ACROSS the window and usable at BOTH ends — a spot read proves nothing | `reasoning` serving: `host_vars/spark.kogler.si.yml:46` says `fast`, so this leg waits on an owner-window flip | no converge, no restart, no profile write — every far-side command is a read, and `--self-test` asserts that (`:30-34`) |
| **HD-475** | the flip converge (the exact detached line `needle-window.sh` prints at `:327-331`), then [`spark-llm-probe.py`](../../scripts/bench/spark-llm-probe.py) `ctx 262144` and `concurrent 4`, then the two rows above | gate 3's full-window leg answers HTTP 200 instead of 502-ing at ~105 s, `concurrent 4` returns 4/4, and the battery is scored with engine / template / thinking / budget beside every score | the staged set is intact **as staged** — `.index-trimmed`, no `ple-bf16-*`, so do not gate on finding one | never re-fetch the ~117 GB; never `--quantization` on the CLI; never a raised `pool_ceiling_bytes` / `fixed_cost_bytes` to make a gate close |

**Refusals are not failures** — a guard firing is a different fact from a measurement failing:

| Exit | Fires in | What it means |
|---|---|---|
| 3 | `hd469-baseline.sh:107`, `usable-sampler.sh:126`, `gate6-couple.sh:154`, `needle-window.sh:224` | Rule 0 — this seat is served by spark; move the act to an externally-served session |
| 4 | `gate6-couple.sh:419,438,488` pairing · `needle-window.sh:407,435,447` attribution · `text-only-preflight.sh:307` comma syntax · `usable-sampler.sh:312` prefill leg failed · `metrics-window.sh:563` window too thin | the act's own precondition went unmet, so nothing it printed is a result |
| 5 | `needle-window.sh:200` | a depth above the servable ceiling 262,144 — above it is a YaRN decision, never a typed flag |
| 6 | every driver except `metrics-window.sh` | the engine container is not running; the name resolves as `spark_vllm_container` → the profile's `container`, so pass `--container` |
| 2 | all of them | usage. `metrics-window.sh` deliberately has **no** Rule 0 exit code, because it takes no timed number (`:93-94`) |

## 3. Read-first — three docs, and this page is the last of them

| Doc | What it owns, and where it outranks this page |
|---|---|
| [`docs/spark-llm-profiles.md`](../../docs/spark-llm-profiles.md) | the catalogue, the KV arithmetic, and §7 = what the dial value `fast` means **today** |
| [`spark/llm-profiles/README.md`](../llm-profiles/README.md) | Rule 0 and the gate ladder 0–9 — the test plan every leg above is a slice of |
| [`docs/hardware-spark.md`](../../docs/hardware-spark.md) | the unified-memory budget, the host-floor ceiling, and §GPU clock cap — why a trace and not a spot read |

Each row's own links name further owning docs (`docs/harness-pi-engines.md` §3 for HD-376's ceiling,
`spark/stability-test.md` for HD-380's pre-raise numbers); wherever this page and any of them disagree,
they win and this page is wrong.

## 4. Do not re-run

* **Gate 7 is CLOSED.** Read twice, PASS both — 19.79 h and 21.49 h of one accruing window
  ([`hd489-tail-gate7-20261007/RESULTS.md`](hd489-tail-gate7-20261007/RESULTS.md)). A third read measures a
  different window, not more evidence.
* **B10's gates 6/8/9 were declined by the owner.** That pairing row stays `UNVERIFIED`; there is no
  workaround and no flag that would make it honest.
* **B9 · B5 · B8 are closed**, with their findings in
  [`hd489-legs-20261006-1228/RESULTS.md`](hd489-legs-20261006-1228/RESULTS.md).
* **HD-400 stays NOT applied.** The pre-flight is landed and legal from any seat; its IaC line is an
  owner-window act, so a sitting that found "just the one flag" easy to add has broken the row, not closed it.
* **HD-473 is blocked upstream, not here.** Re-running the probe proves the verdict still holds; it does not
  open the row. Nothing on this box is waiting on an externally-served model.

## 5. Rollback

The rows' own rollback is a variable and a detached converge, not a recipe: `spark_llm_profile: reasoning`
with `spark_llm_allow_uncertified: false` (committed off, `group_vars/spark.yml:285`), converged **detached**
— [`spark/llm-profiles/README.md`](../llm-profiles/README.md) §Rollback. `reasoning` needs no override, its
artifacts are the ones already staged, and it is the only profile whose stability is certified, so rollback
and switching are one operation in opposite directions.

Standing, and not negotiable inside a window: live converges run **detached** (`nohup … &` + log + poll —
`todo-table.md` §C rule 2), `--check` is the only safe foreground form and proves scoping only, and **never
`reboot spark`** ([`prompt-spark-llm.md`](../../prompt-spark-llm.md) §Traps). A restart loop is stopped with
`docker update --restart=no vllm-qwen-spark && docker stop vllm-qwen-spark`, the var flipped, and a converge
to raise it again — whoever stops the engine owns bringing it back.

## 6. The live window — HD-380 is already accruing; never start a second one

Started from the START-UP CARD by the **parent** session on the pi-dev seat (a lane may not leave a running
process behind, so no lane runs the start line):

| | |
|---|---|
| sampler | `bash scripts/bench/spark/metrics-window.sh --duration 9h` — pid `153123` |
| first sample | `2026-10-22T11:55:54Z` |
| window file | `/var/tmp/metrics-window/window.csv` |
| poll | `bash scripts/bench/spark/metrics-window.sh --status` — read-only, side-effect-free, any session |
| stop | `kill "$(cat /var/tmp/metrics-window/sampler.pid)"` |

It is a `/metrics` **read**, so Rule 0 never barred it and HD-380 does **not** wait on an externally-served
model. A second sampler pointed at the same directory is refused while the first lives
(`metrics-window.sh:456-461`), and the pid file now leaves only with its owner (`:446-448`) — both defects
measured on 2026-10-22 across exactly this pair of pids. When the window fills, `--report` is the answer;
the `gpu_top_mib` growth half belongs to `gate7-read.py` over the watchdog samples, and gate 7 is already
closed (§4).
