# `prompt-remaining-bench.md` — Lane brief · the HD-489 tail: finish the winner's evidence, then certify (HD-489)

> **Role:** dispatch note for **one** lane session. **The row is the authority** for what is missing, in what order and what
> is forbidden: [todo.md](todo.md) HD-489. The funnel itself is measured and closed — `ar-blk` won and runs today as the
> profile **`fast`** — so this lane produces **evidence, not speed**. Durable method + numbers:
> [docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) §7 and
> [spark/llm-profiles/README.md](spark/llm-profiles/README.md) (rule 0, the gate ladder, the paired-quality design, the public
> suites, the seat rules). This file carries the contract, the leg list and the commands — nothing else.
> **Linked from:** [prompt.md](prompt.md) §3 · [todo.md](todo.md) HD-489

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

Cheapest-information first: **B6 → B9 → B2 → B3 → B1 → the §E suites**.

| # | Leg | How | Cost | What it retires |
|---|-----|-----|------|-----------------|
| B6 | fp8 KV on the **built** image | `python3 scripts/spark-fp8-image-probe.py` against `spark_vllm_ultrafast_image` (it reads `spark_vllm_image` only — add `--image`, ~10 lines, or run leg B by hand) | no GPU · ~15 min | HD-473's "blocked" verdict was taken on the **base** tag; the ultrafast lineage is newer than vllm#55557. Measured 2026-10-05 on the built pin: **still BLOCKED-ON-IMAGE** — re-derive, do not re-argue |
| B9 | **weights or knobs?** `ar-blk-lean` | same checkpoint + table, `ple_dispatch: false` → C2 + C2L | 1 boot · ~30 min | ⚠ `ple_dispatch` turned out **load-bearing** (without the A4 dispatch env the AR arm fails to boot, 2026-10-03), so this arm measures the knobs' cost and may not boot — a boot failure is the answer, not a blocker. Highest information per boot |
| B2 | concurrency on the winner | `spark-llm-probe.py … ctx 262144` then `concurrent <max_num_seqs>`, plus `C3` and a `C2L_CONC=2` | 0 boots · ~30 min | gate 4. Measured PASS at conc 8 on the 25 GB/seqs-8 shape (`spark/reports/hd489-overnight-*/raw/g4-c8.log`) — a **short-prompt batch probe**: it proves the shape serves, not throughput under batch |
| B3 | depth at the real workload | `C1_IN=163840` (the harness's p50 prompt is 137,821 tok, p95 200,000) + an `S1-N` at `S1N_IN≈236000`, **and the gate-5 needle at ≥90 % depth, 3/3** | 0 boots · ~45 min | C1 at 32k in is not the workload; depth PASSed at 163,840 and 236,000 (1 preemption) — **the needle is the open half**, and agentic work is gated on it |
| B1 | `reasoning` control legs | flip the dial to `reasoning` (`allow_uncertified: false`), run C2/C1/C2L, flip **back** | 2 boots · ~1.5 h | without it every "+X % vs the certified lane" is inferred from the *patched* lineage. Run-sheet: §Overnight driver below |
| B5 | page-cache cliff of the mmap table | C2L after `echo 3 > /proc/sys/vm/drop_caches` (owner-only), and C2L while a co-resident container allocates (`spark/bench/stress-oom.sh`) | 0 boots · ~40 min | the winner `preadv`s a 47.7 GiB FP8 table per step and keeps ~4 GB resident. If ITL collapses, the win is conditional on an idle box and must be stated that way |
| B7 | the pool constant | ~~16.3e9 under `ar-blk`~~ — **moot**: live `fast` runs 25 GB under a named per-profile `pool_ceiling_bytes` | 1 boot | what is owed is the **evidence for that exception**: gate 4 at conc 2 + one working day of watchdog `usable` |
| B8 | VM corroboration | `spark/bench/vm-window.sh --profile` per leg, after the spark monitoring converge | converge · ~20 min | the "monitoring not converged" caveat on every HD-489 report; `req_ok_delta == N` is the window-exclusivity proof |
| B10 | AWQ on the winner's machinery (`awq-mmap`) | AWQ weights + `image: ultrafast` + `ple_mmap: true` + block rejection → C2 + C2L. Pre-flight done offline: `ple-table-fp8` **does** carry the trained n-gram tensor (33 shards); `ples_nvfp4` does not, `ples_int4` is a layout the mmap loader cannot read | 1 boot (2–4 h if the table must be re-staged) | the owner's question: today's AWQ ceiling is 23.6 tok/s **with graphs**; eager AWQ + the bundle is unmeasured. ⛔ **Gate gap:** nothing ties a checkpoint to a PLE table and `models_root` is per-profile — a mis-pair renders green and dies at boot, so **add that assert first** |

**Every leg** carries: `--profile`, `--client`, the leg window, the **sustained `clocks.sm`/power/temperature sampler across
the whole window** (required by the gate doc; **no HD-489 leg has one yet**), and `MemAvailable − CmaFree` at both ends.
Write the report under `spark/reports/hd489-tail-<name>/` **with the raw in `raw/`** — an evidence dir a row cites must
contain the raw. Basis for the estimates: boot 15–20 min (weights 549 s, KV line at +10.2 min); C2 2–4 min, C1 4–11 min,
C2L 5.5–10 min; prefill ≈ 1,900 tok/s.

**Owner-gated (an agent may not self-authorise):** every dial flip incl. `spark_llm_allow_uncertified` (B1/B9/B10) · B5's
`drop_caches` · B7's constant · B8's monitoring converge · B10's checkpoint↔table pairing.

## Overnight driver (unattended: the `reasoning` arm + the paired McNemar)

The `fast` half is measured and committed with its McNemar input in
[`spark/reports/hd489-overnight-20261004-0804/`](spark/reports/hd489-overnight-20261004-0804/README.md) — **do not re-run
it**; McNemar scores only the key intersection, so a `reasoning` pass over the same 5 categories pairs against it. Re-run the
`fast` legs only if the engine, weights or harness changed.

**Rules:** never stop, never ask — a leg you cannot finish gets one line `BLOCKED: <why> — <log>` in `$EV/RESULTS.md` and you
take the NEXT leg; ≤2 retries per leg; one leg at a time; edit nothing but your evidence dir (no IaC, no constants, no
ceilings, no restart, no reboot); never write the bearer anywhere, only its length (32). Budgets: boot 40 min, MMLU 5 h,
converge-back 45 min — hit a budget, `pkill -f evaluate_from_apiX`, log `BLOCKED: budget`, next leg. **The converge-back and
the commit are never skipped.**

```bash
cd ~/source/homelab && git log --oneline -1
WT=../homelab-wt-$(date +%Y%m%d-%H%M); git worktree add "$WT" -b session/hd489-$(date +%H%M) && cd "$WT"
export TS=$(date +%Y%m%d-%H%M) EV=spark/reports/hd489-overnight-$TS URL=https://llm.kogler.si/v1; mkdir -p "$EV/raw"
export OPENAI_API_KEY="$(op item get spark-llm_api --vault Homelab-ansible --fields label=credential --reveal)"
echo "bearer len=${#OPENAI_API_KEY}"; echo "runner=$(hostname)/${PI_MODEL:-unset} TS=$TS" | tee "$EV/raw/seat.txt"
curl -s -o /dev/null -w 'endpoint http=%{http_code}\n' -H "Authorization: Bearer $OPENAI_API_KEY" "$URL/models"   # want 200
ssh spark "grep -A1 -e '--kv-cache-memory-bytes' -e '--max-num-seqs' /opt/spark-ai/docker-compose.yml" | tee "$EV/raw/live.txt"
```

`401` → retry once, else `BLOCKED: endpoint` and jump to the converge-back. Use `https://llm.kogler.si/v1`, **never**
`spark.kogler.si/v1` (302 to `/`); if the endpoint is unreachable, `ssh -N -f -L 8000:127.0.0.1:8000 spark` and point at
`http://127.0.0.1:8000/v1`.

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

Not healthy in 40 min → `BLOCKED: reasoning boot`, no re-converge, go straight to the converge-back. A boot failure **is a
finding** now: the never-evict flag that crash-looped this arm on 2026-10-04 is REJECTED and renders nowhere. Partial is
fine — the test scores only what both arms have; report `n_paired` **first** (under ~300 paired items resolves nothing below
~20 points), then the McNemar line with the pre-registered rule
(`≤2 pts keep · 3–5 pts decide on the pi-harness tasks · >5 pts the speed win is void`) — the script and the exact
binomial-exact form are in `spark/llm-profiles/README.md` §Measuring "is it as smart?".

```bash
nohup bash scripts/ansible-run.sh playbooks/spark.yml --limit spark --no-pull >/tmp/cg-back-$TS.log 2>&1 &
sleep 300; tail -20 /tmp/cg-back-$TS.log
ssh spark "grep -A1 -e '--kv-cache-memory-bytes' -e '--max-num-seqs' -e 'never-evict' /opt/spark-ai/docker-compose.yml" > "$EV/raw/live-after.txt"   # never-evict: expect NO hit
ssh spark "docker logs vllm-qwen-spark --since 60m 2>&1 | grep -m2 -e 'GPU KV cache size' -e 'Initial free memory'" >> "$EV/raw/live-after.txt"
python3 scripts/spark-llm-probe.py --base-url "$URL" --profile fast health 2>&1 | tail -6 | tee "$EV/raw/health-final.log"
{ echo "# run $TS"; cat "$EV/raw/seat.txt"; grep -h -e 'arm=' -e 'n_paired=' "$EV"/raw/*.txt 2>/dev/null; } >> "$EV/RESULTS.md"
git add -A "$EV" && git commit -s -m "test(spark-llm): HD-489 overnight run $TS — reasoning arm + McNemar, box left on fast"
```

PASS = `failed=0`, `restarts=0`, the KV line present, health green, `25000000000` / `8`. **Never leave the box on
`reasoning`.** An assert in the log → `BLOCKED: gate — <first line>` and change NOTHING. Not healthy 40 min after a reboot →
`BLOCKED: engine down` on the FIRST line of `RESULTS.md`, do not restart it. Do not merge, do not remove the worktree — the
parent does both.

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

B1–B3 + B6 + **B9** done with reports and raw in tree · **B10** attempted or explicitly declined with the reason in the row ·
the needle (gate 5) 3/3 · MMLU-Pro-mini on **both** arms with the pre-registered rule and a verdict in
[docs/spark-llm-profiles.md](docs/spark-llm-profiles.md) · A-class doc fixes landed · then `certified: true` +
`certified_evidence:` (links to artifacts, not prose) with `uncertified_reason` dropped, one converge without the override,
and **the HD-489 row deleted**. **Acceptance:** every item returns `PASS / FAIL / BLOCKED` + the number + the evidence path;
a claim with no path counts as not run.
