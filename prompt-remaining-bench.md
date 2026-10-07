# `prompt-remaining-bench.md` — Lane brief · the HD-489 tail: finish the winner's evidence, then certify (HD-489)

> **Role:** dispatch note for **one** lane session. **The row is the authority** for what is missing, in what order and what
> is forbidden: [todo.md](todo.md) HD-489. **HD-494's two legs in this lane are done** — gate 4 at conc 8 and the gate-5 needle
> were taken on the live 20 GB shape on 2026-10-06 ([`spark/reports/hd489-overnight-20261006-0226/`](spark/reports/hd489-overnight-20261006-0226/RESULTS.md));
> re-taking one is only correct after a pool/seqs change. This brief edits **only** its own `todo.md` rows (O2).
> The funnel itself is measured and closed — `ar-blk` won and runs today as the
> profile **`fast`** — so this lane produces **evidence, not speed**. Durable method + numbers:
> [docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) §7 and
> [spark/llm-profiles/README.md](spark/llm-profiles/README.md) (rule 0, the gate ladder, the paired-quality design, the public
> suites, the seat rules). This file carries the contract, the leg list and the commands — nothing else.
> **Linked from:** [prompt.md](prompt.md) §3 · [todo.md](todo.md) HD-489 · HD-494

**Contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O8), which overrides README §4 / CONVENTIONS §6 at the
items it numbers. One session, one worktree, one branch. Never edit `prompt.md` / `todo-table.md` (O2); edit **only your own
`todo.md` rows**. **You hold the spark converge slot** (O3) — every boot is detached, `nohup … &` + log + poll, ~15–20 min.
Owner gate → **park and continue** (O4). Close-out = docs + row tail + leg reports + signed commit +
`bash scripts/validate-all.sh` green **in this worktree** → **stop**.

**Rule 0:** a session whose own model is served by `spark/…` may take **no timed number**; counter / log / `docker inspect`
reads are legal from any session. Stamp every leg with `--client`. **Declare the seat in the session's first line** —
`engine under test = spark | laptop-lmstudio`, `runner = external | laptop-local` — an unstated seat is how a contaminated
number reaches a doc.

## Legs, in value order (the row owns the ⏳ list; this is the how)

What is left: **the gate-7 curve read (accruing since 2026-10-06 11:19Z — read it with
`spark/bench/gate7-read.py`, self-testing and wired into `validate-all.sh`) → the
`fast.certified_evidence` rewrite**. **Gate 6 on the live shape is DONE** (2026-10-06,
[`spark/reports/hd489-tail-gate6-20261006-2349/`](spark/reports/hd489-tail-gate6-20261006-2349/RESULTS.md)):
PASS, and the one EMPTY item is the battery spending all 1024 tokens on `reasoning_tokens` — raising
that budget or scoring with thinking off changes a FIXED comparison basis, so it is an owner call and
never a quiet edit to `accuracy-gate.sh`. The 2026-10-06 legs session closed **B9 · B5 · B8** and the owner declined **B10's gates
6/8/9** ([`spark/reports/hd489-legs-20261006-1228/`](spark/reports/hd489-legs-20261006-1228/RESULTS.md)); keep the closed rows
below for their commands and pass rules, not as work.

| # | Leg | How | Cost | What it retires |
|---|-----|-----|------|-----------------|
| B6 | fp8 KV on the **built** image | `python3 scripts/spark-fp8-image-probe.py` against `spark_vllm_ultrafast_image` (it reads `spark_vllm_image` only — add `--image`, ~10 lines, or run leg B by hand) | no GPU · ~15 min | HD-473's "blocked" verdict was taken on the **base** tag; the ultrafast lineage is newer than vllm#55557. Measured 2026-10-05 on the built pin: **still BLOCKED-ON-IMAGE** — re-derive, do not re-argue |
| B9 | **weights or knobs?** `ar-blk-lean` | same checkpoint + table, `ple_dispatch: false` → C2 + C2L | 1 boot · ~30 min | ✅ **CLOSED 2026-10-06 — FAIL (BOOT)**, which is the answer: the lean arm dies at the first safetensors shard (`AttributeError: 'MergedColumnParallelLinear' object has no attribute 'data'`, `hd489-legs-20261006-1228/raw/b9-crash.txt`) on every attempt. `ple_dispatch` is **constitutive**, not dialable, so "what the knobs cost" cannot be measured by deletion and the 39.7 tok/s win stands as-is |
| B2 | concurrency on the winner | `spark-llm-probe.py … ctx 262144` then `concurrent <max_num_seqs>`, plus `C3` and a `C2L_CONC=2` | 0 boots · ~30 min | ✅ **DONE 2026-10-06 on the 20 GB shape** — conc 8 PASS (8/8, wall 2.7 s, `spark/reports/hd489-overnight-20261006-0226/raw/g4-c8.log`) and conc 2 PASS (`raw/b7-conc2.log`); this closed **HD-494's** conc-8 leg too. Re-take only after a shape change |
| B3 | depth at the real workload | `C1_IN=163840` (the harness's p50 prompt is 137,821 tok, p95 200,000) + an `S1-N` at `S1N_IN≈236000`, **and the gate-5 needle at ≥90 % depth, 3/3** | 0 boots · ~45 min | ✅ **DONE 2026-10-06** — the needle recalled **3/3** at 92 % of the window with `num_preemptions_total` delta +0 (`raw/g5-verdict.txt`); agentic work is no longer gated on it |
| B1 | `reasoning` control legs | flip the dial to `reasoning` (`allow_uncertified: false`), run C2/C1/C2L, flip **back** | 2 boots · ~1.5 h | ✅ **DONE 2026-10-06** — booted healthy, 500/500 paired items, McNemar **KEEP** (Δ=−0.20 pts, p=1.000): the `fast` speed win stands. Run-sheet: §Overnight run, Step 3 |
| B5 | page-cache cliff of the mmap table | C2L after `echo 3 > /proc/sys/vm/drop_caches` (owner-only), and C2L while a co-resident container allocates (`spark/bench/stress-oom.sh`) | 0 boots · ~40 min | ✅ **CLOSED 2026-10-06 — no cliff**: cold page cache ≈ **17–20 %** decode / ITL p50 78.6 ms, no collapse; co-resident allocator ≈ **20 %** decode with ITL p50 flat at ~65 ms and a tail-only ~2× p95; 0 preemptions, no OOM, no stranding (`hd489-legs-20261006-1228/`). State the ~20 % penalties, not a cliff |
| B7 | the pool constant | ~~16.3e9 under `ar-blk`~~ — **moot**: live `fast` runs **20 GB** under a named per-profile `pool_ceiling_bytes` | 1 boot | ✅ **CLOSED 2026-10-06** — gate 4 at conc 2 PASS + the watchdog rest-window record; the 24 h `usable`-sample wait was closed by owner decision. The global re-derive that removes the exception is **HD-494's** row, not a leg here |
| B8 | VM corroboration | `spark/bench/vm-window.sh --profile` per leg, after the spark monitoring converge | converge · ~20 min | ✅ **CLOSED 2026-10-06** — monitoring was **already live** on spark, histograms verified in VM end-to-end from the VPS (`raw/b8-vm-proof.txt`). ⚠ The strict `req_ok_delta == N` cold-scrape exclusivity cannot certify even a quiet leg exactly (10/12 seen) — read corroboration with that limitation logged, not as a failed leg |
| B10 | AWQ on the winner's machinery (`awq-mmap`) | AWQ weights (on **XFS** — `models_root: xfs`; the `os` this arm used to name has never held AWQ) + `image: ultrafast` + `ple_mmap: true` + block rejection, pool **14 GB** → C2 + C2L. Pre-flight offline: `ple-table-fp8` **does** carry the trained n-gram tensor (33 shards); `ples_nvfp4` does not, `ples_int4` is a layout the mmap loader cannot read | 1 boot · ~1 h | the owner's question is answered: the AWQ ceiling was 23.6 tok/s **with graphs**, and the eager bundle measured **C2L 27.6 tok/s ⇒ ~30 %** (2026-10-06, boot + both speed legs). **Its gates 6/8/9 were declined by the owner (2026-10-06)**, so the pairing row stays UNVERIFIED and this arm is not booted again without a new owner instruction. **The gate gap is closed (2026-10-06):** the pair is decided in `spark_llm_ple_pairing` (this one reads UNVERIFIED) and the role re-reads the staged checkpoint's own `config.json` quantization, so a mis-pair is refused at converge instead of dying at boot — invariant `ple-pairing` in the offline matrix, canaries included. Run-sheet: §Overnight run, Step 4 |

**Every leg** carries: `--profile`, `--client`, the leg window, the **sustained `clocks.sm`/power/temperature sampler across
the whole window** (required by the gate doc; the 2026-10-06 run is the first HD-489 report that carries one —
`spark/reports/hd489-overnight-20261006-0226/raw/clocks-b10.txt`, 1,934 samples — so every leg keeps using the `trace()`
helper in §Overnight run), and `MemAvailable − CmaFree` at both ends.
Write the report under `spark/reports/hd489-tail-<name>/` **with the raw in `raw/`** — an evidence dir a row cites must
contain the raw. Basis for the estimates: boot 15–20 min (weights 549 s, KV line at +10.2 min); C2 2–4 min, C1 4–11 min,
C2L 5.5–10 min; prefill ≈ 1,900 tok/s.

**Owner-gated (an agent may not self-authorise):** every dial flip — an uncertified one carries the grant as a
**per-run `-e`**, never as a committed `spark_llm_allow_uncertified: true` (a standing `true` leaves every later
converge of this host permitted to boot an arm): B1 `-e spark_llm_profile=reasoning` · B10
`-e spark_llm_profile=awq-mmap -e spark_llm_allow_uncertified=true` · B9 `-e spark_llm_profile=ar-blk-lean -e
spark_llm_allow_uncertified=true` · B5's
`drop_caches` · B7's constant · B8's monitoring converge · **any edit to `spark_llm_ple_pairing`** — that registry is
where a checkpoint↔table pair is *decided*, so a boot that disagrees with it is a report to the owner, not a typo
to work around.

## Overnight run — one unattended session, four steps (the whole lane's night; §"Overnight driver" in the pre-2026-10-06 wording, which the dated reports still cite)

**Seat, declared in the first line of the session:** `engine under test = spark`, `runner = laptop-local`
and — the part that decides what you may measure — **`PI_MODEL` must not be `spark/…`**. If it is, you are
inside the loop you are measuring: take **no** timed number, write `BLOCKED: seat (PI_MODEL=…)` as the first
line of `RESULTS.md`, and run only the offline legs. Never stop, never ask: a step you cannot finish gets one
line `BLOCKED: <why> — <log path>` in `$EV/RESULTS.md` and you take the next one. ≤2 retries per leg, one leg
at a time, and edit nothing but `$EV` (no IaC, no constants, no ceilings, no restart, no reboot). The
converge-back and the commit are never skipped.

**Budgets:** boot 40 min · one MMLU category 5 h · converge-back 45 min. Hit a budget: `pkill -f
evaluate_from_apiX`, log `BLOCKED: budget`, next step.

```bash
cd ~/source/homelab && git log --oneline -1
WT=../homelab-wt-$(date +%Y%m%d-%H%M); git worktree add "$WT" -b session/hd489-$(date +%H%M) && cd "$WT"
export TS=$(date +%Y%m%d-%H%M) EV=spark/reports/hd489-overnight-$TS URL=https://llm.kogler.si/v1; mkdir -p "$EV/raw"
export OPENAI_API_KEY="$(op item get spark-llm_api --vault Homelab-ansible --fields label=credential --reveal)"
echo "bearer len=${#OPENAI_API_KEY}"; echo "runner=$(hostname)/${PI_MODEL:-unset} TS=$TS" | tee "$EV/raw/seat.txt"
curl -s -o /dev/null -w 'endpoint http=%{http_code}\n' -H "Authorization: Bearer $OPENAI_API_KEY" "$URL/models"   # want 200
ssh spark "grep -A1 -e '--kv-cache-memory-bytes' -e '--max-num-seqs' /opt/spark-ai/docker-compose.yml" | tee "$EV/raw/live.txt"
```

`401` → retry once, else `BLOCKED: endpoint` and jump to Step 4. Use `https://llm.kogler.si/v1`, **never**
`spark.kogler.si/v1` (302 to `/`); if the endpoint is unreachable, `ssh -N -f -L 8000:127.0.0.1:8000 spark`
and point at `http://127.0.0.1:8000/v1`. Every leg window also gets the trace the reports have been missing:

```bash
trace(){ ssh spark 'for i in $(seq 1 2400); do date -u +%FT%TZ; nvidia-smi --query-gpu=clocks.sm,power.draw,temperature.gpu --format=csv,noheader,nounits; sleep 1; done' > "$EV/raw/clocks-$1.txt" 2>/dev/null & echo $!; }
# TRACE=$(trace <leg>); …the leg…; kill $TRACE   — plus the harness's own power log under spark/reports/raw/
```

### Step 1 — is the box protected? (5 min, decides whether Steps 2–3 may boot anything)

The night boots two profiles on the box's tightest memory ledger, so it boots them only with the OOM
governor actually armed. **Read the box, not the docs** (the 2026-10-05 lesson,
[docs/spark-incidents.md](docs/spark-incidents.md) §Incident #9):

```bash
{ sha256sum IaC/ansible/roles/spark/files/spark-oom-watchdog.sh
  ssh spark 'sha256sum /usr/local/bin/spark-oom-watchdog.sh
             systemctl show -p Environment --value spark-oom-watchdog.service | tr " " "\n" | grep -e REARM -e ENFORCE=
             ls -l /mnt/spark_nvme/oom-watchdog/no-enforce 2>&1 | tail -1
             sudo -n /usr/local/bin/spark-oom-watchdog.sh status | grep -e "governor:" -e "hysteresis:" -e "budget:"'
} | tee "$EV/raw/watchdog.txt"
```

PASS = the two sha256 lines **match**, the unit env carries `SPARK_OOM_REARM_GIB=12`, `no-enforce` does **not**
exist, `hysteresis: armed`, and `budget:` reads `usable` ≥ 12 GiB. **If `no-enforce` is present, or the hashes
differ: park the boots** (`park: watchdog armed-off / not deployed` in `RESULTS.md`), run Step 2 anyway (it
needs no boot), skip Step 3, and leave the exact command in `RESULTS.md` for the owner — an agent does not
decide to re-arm a governor at 03:00.

### Step 2 — ✅ DONE 2026-10-06 (both legs PASS): gate 4 + **gate 5** — this was HD-494's debt too

Both numbers are in `spark/reports/hd489-overnight-20261006-0226/`; the commands below stay for a **re-take after a shape
change** (a different pool or `max_num_seqs`), not as an open leg.

Box is on `fast` / 20 GB / seqs 8. Take these **first** when a re-take is owed: they cost nothing and they are the two
numbers agentic work is gated on.

```bash
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast health 2>&1 | tee "$EV/raw/g1-health.log"
TRACE=$(trace g4); python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast concurrent 8 --max-tokens 64 2>&1 | tee "$EV/raw/g4-c8.log"; kill $TRACE
spark/bench/snapshot-metrics.sh before-G5 | tee "$EV/raw/metrics-before-g5.txt"
# gate 5 — the needle at ≥90 % of window, 3/3. Plant the marker (the pi global-instructions text,
# docs/pi-harness.md) inside a ~236k-token filler and ask for it back; matching is the token-subsequence
# rule in spark/llm-profiles/README.md. Depth, not prompt length: ≥ 235 000 prompt_tokens per attempt.
for i in 1 2 3; do S1N_IN=236000 S1N_NUM_PROMPTS=1 ./spark/bench/run-scenario.sh "G5-needle-$i" S1-N \
    --profile fast --client "$(hostname)" 2>&1 | tee "$EV/raw/g5-run-$i.log"; done
spark/bench/snapshot-metrics.sh after-G5 | tee "$EV/raw/metrics-after-g5.txt"
```

PASS gate 4 = 8/8 200s with the slowest within 3× solo. PASS gate 5 = the needle recalled **3/3** with
`num_preemptions_total` delta recorded per attempt — the one preemption B3 saw at 236k is exactly what this
gate judges, so record it whether or not the recall succeeded. Either leg failing is a finding, not a blocker;
write the number and move on.

### Step 3 — ✅ DONE 2026-10-06 — the `reasoning` arm + the paired McNemar (verdict **KEEP**, Δ=−0.20 pts, p=1.000)

The `fast` half is measured and committed with its McNemar input in
[`spark/reports/hd489-overnight-20261004-0804/`](spark/reports/hd489-overnight-20261004-0804/README.md) — **do not
re-run it**; McNemar scores only the key intersection, so a `reasoning` pass over the same 5 categories pairs
against it. Re-run the `fast` legs only if the engine, weights or harness changed.

```bash
N=$(python3 -c "import yaml;print(yaml.safe_load(open('IaC/ansible/group_vars/spark.yml'))['spark_llm_profiles']['reasoning']['max_num_seqs'])")
nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull -e spark_llm_profile=reasoning >/tmp/cg-reasoning-$TS.log 2>&1 &
sleep 300; tail -20 /tmp/cg-reasoning-$TS.log            # every 5 min, ≤40 min (~20 min boot)
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile reasoning health 2>&1 | tail -6 | tee "$EV/raw/health-reasoning.log"
export OUT2=~/mmlu-eval-reasoning-$TS && mkdir -p "$OUT2"
for s in other health "computer science" math biology; do   # the owner's 5-category subset, slowest first
  MMLU_PRO_MINI=/tmp/mmlu-pro-harness/mini_test.json NO_COLOR=1 TERM=dumb \
    /tmp/mmlu-venv/bin/python /tmp/mmlu-pro-harness/evaluate_from_apiX.py --url "$URL" \
    -m spark/qwen3.8-flash-next -n "$N" -a "$s" -o "$OUT2" --retry 2 --retry_wrong 2 </dev/null >> "$EV/raw/mmlu-reasoning.log" 2>&1
done
```

Not healthy in 40 min → `BLOCKED: reasoning boot`, no re-converge, go straight to the converge-back. A boot
failure **is a finding**: the never-evict flag that crash-looped this arm on 2026-10-04 is REJECTED and renders
nowhere. Partial is fine — the test scores only what both arms have; report `n_paired` **first** (under ~300
paired items resolves nothing below ~20 points), then the McNemar line with the pre-registered rule
(`≤2 pts keep · 3–5 pts decide on the pi-harness tasks · >5 pts the speed win is void`) — script and exact
binomial-exact form in [`spark/llm-profiles/README.md`](spark/llm-profiles/README.md) §Measuring "is it as smart?".

Converge back to the live profile before anything else, so the night never depends on the box being flipped:

```bash
nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull >/tmp/cg-back-$TS.log 2>&1 &
sleep 300; tail -20 /tmp/cg-back-$TS.log
ssh spark "grep -A1 -e '--kv-cache-memory-bytes' -e '--max-num-seqs' -e 'never-evict' /opt/spark-ai/docker-compose.yml" > "$EV/raw/live-after-reasoning.txt"   # never-evict: expect NO hit
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast health 2>&1 | tail -6 | tee "$EV/raw/health-final.log"
```

### Step 4 — B10: AWQ on the winner's machinery — ✅ booted + measured 2026-10-06; gates 6/8/9 **declined by owner**

The question the owner asked is answered: today's AWQ ceiling was **23.6 tok/s with graphs**, `fast` measures 39.7 C2L, and
the eager bundle measured **27.6 C2L ⇒ the quality fallback costs ~30 %, not ~40 %**. The owner declined the three quality
gates on 2026-10-06, so this row is closed — the commands below are here only if that ruling is ever revisited.

The pair is decided in `spark_llm_ple_pairing`, where `ple-table-fp8 ↔ Qwen3.8-Flash-Next-AWQ` is recorded **UNVERIFIED** —
**gates 6/8/9** (accuracy battery, MTP acceptance, quality noise floor) are what replace the word. Do not "fix" the registry
entry; report what the run says.

```bash
python3 scripts/check_spark_llm_gate.py | tail -3                       # must be 0 failures, canaries biting
python3 scripts/spark-llm-probe.py --base-url "$URL" profile awq-mmap 2>&1 | tee "$EV/raw/b10-render.log"
nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull \
     -e spark_llm_profile=awq-mmap -e spark_llm_allow_uncertified=true >/tmp/cg-b10-$TS.log 2>&1 &
sleep 300; tail -20 /tmp/cg-b10-$TS.log                                  # every 5 min, ≤40 min
```

`An assert in the log → BLOCKED: gate — <first line>` and change NOTHING (the pairing assert in particular
means the arm you aimed at is not the pair the registry decided — that is a decision for the owner, not a
typo to work around). Healthy (`restarts=0`, `/health` 200, the engine's own `GPU KV cache size` line in
`docker logs`, expect **451,219** slots = 1.72× the window at 14 GB) → measure it:

```bash
TRACE=$(trace b10); ./spark/bench/run-scenario.sh B10-C2  C2  --profile awq-mmap --client "$(hostname)" 2>&1 | tee "$EV/raw/b10-c2.log"
./spark/bench/run-scenario.sh B10-C2L C2L --profile awq-mmap --client "$(hostname)" 2>&1 | tee "$EV/raw/b10-c2l.log"; kill $TRACE
ssh spark "docker logs vllm-qwen-spark --since 60m 2>&1 | grep -m4 -e 'GPU KV cache size' -e 'Available KV cache' -e 'Model loading took' -e 'ple'" >> "$EV/raw/b10-boot.txt"
```

Record tok/s, TTFT/ITL p50, MTP accept %, preemptions, `MemAvailable − CmaFree` at both ends — and if usable
drops under 8 GiB, say so loudly: this arm's fixed cost is the AWQ lane's, which has **no** term for the FP8
mmap table's resident set (B5), and the pool was cut 16→14 GB to keep 3.2 GB of margin. Then converge back and
commit; **never leave the box on `reasoning` or `awq-mmap`**:

```bash
nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull >/tmp/cg-back2-$TS.log 2>&1 &
sleep 300; tail -20 /tmp/cg-back2-$TS.log
ssh spark "docker inspect -f '{{join .Args " "}}' vllm-qwen-spark" | tr ' ' '\n' | grep -A1 -e '^--model$' -e '^--kv-cache-memory-bytes$' | tee "$EV/raw/live-final.txt"
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast health 2>&1 | tail -6 | tee -a "$EV/raw/health-final.log"
{ echo "# run $TS"; cat "$EV/raw/seat.txt"; grep -h -e 'arm=' -e 'n_paired=' "$EV"/raw/*.txt 2>/dev/null; } >> "$EV/RESULTS.md"
git add -A "$EV" && git commit -s -m "test(spark-llm): HD-489 overnight run $TS — gate 4/5 on 20 GB, reasoning arm + McNemar, B10 boot, box left on fast"
```

**Acceptance for the night:** every step returns `PASS / FAIL / BLOCKED / PARKED` + the number + the evidence
path — a claim with no path counts as not run. PASS (final health) = `failed=0`, `restarts=0`, the KV line
present, and the box serving `fast` at `20000000000` / `8`. Not healthy 40 min after a reboot →
`BLOCKED: engine down` on the **first** line of `RESULTS.md`, do not restart it, do not merge, do not remove
the worktree — the parent does both.

## ⛔ Never

raise `spark_llm_pool_ceiling_bytes`, `…_device_hold_ceiling_bytes` or `fixed_cost_bytes` as a side effect of a leg (each is
a certified constant with its own evidence) · attempt fp8 KV by editing a container — **probe first, then a dial** · vendor
the AGPL overlay, hand-edit site-packages, or add a `never_evict` pin anywhere (REJECTED:
[docs/services-ai-rejected.md](docs/services-ai-rejected.md)) · re-run an arm already in the rejected log without an
exception note (CONVENTIONS §8.3) · delete `ar-hybrid`/`ple-fp8` (live config) or the AWQ + `ples_int4` artifacts
(`reasoning` is the rollback target) · run SWE-bench task containers on spark · report a public-suite score without its
revision pin, CoT state and extraction-failure rate · take a timed leg from a **laptop-local** runner when the laptop leg is
the engine under test, or let a laptop-local session author a profile delta at all (its 32k window cannot hold the contract).

## Definition of done

Done and in tree with raw: **B1–B3**, **B6** (BLOCKED-ON-IMAGE), **B7**, **B9** (FAIL-BOOT), **B5** (no cliff), **B8**
(monitoring live) and **B10's boot + both speed legs** — the `hd489-overnight-20261006-0226/` and `hd489-legs-20261006-1228/`
reports plus the `hd489-tail-*` dirs. **B10's gates 6/8/9 are closed as declined-by-owner; do not re-litigate them.**
What remains: the **gate 7** curve read (`spark/bench/gate7-read.py --since 2026-10-06T11:19:00Z --baseline-mib 93091`;
the 12.2 h partial read is already on file as a **bounded fill**, and its plateau — 99,649 MiB flat — is HD-494's
peak, not a verdict here) · then rewrite `fast`'s `certified_evidence:` to the 20 GB legs it now holds (links to artifacts, not
prose) — `fast` is already `certified: true` with no `uncertified_reason`, and a converge with no override is on record, so the
certificate itself is not the open item. **`fast`'s gate 6 was taken 2026-10-06 — do not re-run the battery**; the open question
around it is its `max_tokens` budget, which belongs to the owner. Then **delete the HD-489 row**.
**HD-494's legs this lane carries are closed** (gate 4 at conc 8 and gate 5, reported on the 20 GB shape 2026-10-06 and
written into HD-494's row by the orchestrator); this brief changes nothing in HD-494's row or docs (O2).
**Acceptance:** every item returns `PASS / FAIL / BLOCKED / PARKED` + the number + the evidence path;
a claim with no path counts as not run.
