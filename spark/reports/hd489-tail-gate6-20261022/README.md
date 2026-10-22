# HD-489 tail — gate 6 at the ruled budget, as ONE coupled act

**State: AUTHORED, NOT RUN.** This directory holds the instruction and the certificate text that
the remaining HD-489 leg owes; the `raw/` and `pairing-*.md` files arrive when the act is run. No
number in this file is measured by the session that wrote it — this session was served by spark,
so Rule 0 bound the whole run and no leg was taken here.

The battery's budget was **ruled** (owner, 2026-10-07): gate 6's `max_tokens` goes
`1024 → 16 × 2^10 = 16 384`, and when it is applied **the B1 `reasoning` baseline is re-run in the
same change** — grading a reasoning arm against a baseline made under the old budget is not a
measurement, it is two measurements stapled together. The reason it matters is in the prior run:
[`../hd489-tail-gate6-20261006-2349/RESULTS.md`](../hd489-tail-gate6-20261006-2349/RESULTS.md)
got `code-fib` EMPTY at `finish_reason=length` with **all 1024 completion tokens spent as
`reasoning_tokens`** on an engine booted with `--reasoning-parser qwen3`. That is the battery's
budget failing, not the engine's ability.

The coupling is now mechanical, not mnemonic:
[`scripts/bench/spark/gate6-couple.sh`](../../../scripts/bench/spark/gate6-couple.sh) is the ONE
act left on this row. It runs the baseline first and the battery second at the same budget in one
invocation, and **refuses** (exit 4, `PAIRING REFUSED`) any invocation that would fire the battery
without having just baselined at that budget. Its `--self-test` (7 arms) proves the refusal, the
Rule 0 refusal and the read-only contract; a battery that ignored the flag, or an engine that was
restarted between the legs, fails the run instead of printing a PASS.

## The act (one command, one seat)

⛔ **Seat:** take it from an **externally-served session on the designated runner station** (the
WSL Debian seat — [prompt-laptop-wsl.md](../../../prompt-laptop-wsl.md) §0/§1,
[docs/orchestration.md](../../../docs/orchestration.md) §4, standing rule 9 in
[todo-table.md](../../../todo-table.md) §C). The driver refuses a spark-served session with exit 3
naming Rule 0 — verified in situ on the session that authored this file. It reads the box over
`ssh spark` and stamps every run `<hostname>/agent:<PI_MODEL>`.

```bash
# 1. the act — both legs, one budget, one invocation (default --max-tokens 16384)
scripts/bench/spark/gate6-couple.sh --out /tmp/hd489-tail-gate6-<date>   # detached: minutes, not seconds
#    on-box shape: the battery authenticates from the engine container's own argv, so run it
#    where that container is visible — the detached-launch shape that took the previous gate 6.
#    --dry-run prints both exact battery commands and touches nothing.
# 2. copy the raw back in, then commit — a row may only cite an evidence dir that holds its raw
cp -r /tmp/hd489-tail-gate6-<date>/raw .
# 3. paste the printed pairing numbers into the block below, set the key in
#    IaC/ansible/group_vars/spark.yml, and close the row.
```

Nothing in the act needs a converge, a restart, a dial flip or a profile write. If the dial is not
already on the arm being graded, that is an **owner-gated** decision taken before the act, not
inside it — the driver prints the engine identity read at both ends, so a wrong dial is visible in
the evidence rather than silent in the score.

Why `16 384` and why together: [todo.md](../../../todo.md) row HD-489 (the ruling),
[spark/llm-profiles/README.md](../../llm-profiles/README.md) (the gate ladder, gate 6),
[docs/spark-llm-profiles.md](../../../docs/spark-llm-profiles.md) §7 (what `fast` is today).

## What the driver prints, and why each line is evidence

| line | the property it proves |
|---|---|
| `pairing: max_tokens baseline=… arm=… -> EQUAL (16384, both legs)` | read back out of the **request bodies both legs put on the wire** (`ACCURACY_GATE_BODY_LOG`), not out of what the driver hoped it asked for |
| `pairing: engine vllm-qwen-spark on spark — <StartedAt> restarts=<N>` | same boot, same restart count, same argv at **both** ends; a restart or dial flip between the legs exits 4 instead of scoring two engines as one |
| `pairing: template/thinking: …` | the confound ledger gate 6 demands: `--reasoning-parser`, `--chat-template`, pool, batch shape, speculation, tool parser. Never `--api-key` — the argv captures scrub it at the point of write (HD-1170's leak class) |
| `pairing: baseline at … .. … · arm at … .. … · client <host>/agent:<model>` | both timestamps and the seat, so Rule 0 is checkable afterwards |
| `window: clocks.sm … MHz · preemptions +N · prefix +N hits / +N queries` | the window was quiet enough to compare (the row's standing requirement; a `clocks.sm` trace is a record here, no tok/s is computed anywhere) |
| `usable (MemAvailable − CmaFree): … -> … GiB` | both ends, the only gauge that is honest on GB10 |

## The proposed `fast.certified_evidence` rewrite — AUTHORED, NOT APPLIED

The **only** slots to fill are the four `⟨…⟩` ones, and they come from the printed pairing file.
The argument below is settled; the external session's job is to run the driver and paste, **not to
re-derive**. Apply it as a single key — a second `certified_evidence:` line in the same profile
resolves to the last one and would silently certify `fast` with no evidence (the warning is already
in [spark.yml](../../../IaC/ansible/group_vars/spark.yml) above the key).

```yaml
    certified_evidence: >-
      ⟨pairing-<tag>.md path⟩ · spark/reports/hd489-ar-blk/README.md ·
      spark/reports/hd489-tail-b2/README.md · spark/reports/hd489-tail-b3/README.md ·
      spark/reports/hd489-legs-20261006-1228/RESULTS.md ·
      spark/reports/hd489-overnight-20261006-0226/RESULTS.md ·
      spark/reports/hd489-tail-gate6-20261006-2349/RESULTS.md ·
      spark/reports/hd489-tail-gate6-⟨date⟩/ ·
      spark/reports/hd489-tail-gate7-20261007/RESULTS.md · spark/llm-profiles/README.md —
      shape: 20 GB pool through a PER-PROFILE pool_ceiling_bytes (the certified 16 GiB global
      still binds every other profile) + max_num_seqs 8 = 644,599 slots = 2.46 × the 262,144
      window, argv confirmed on the live container, restarts=0. History: 16 GB / seqs 4, then
      25 GB + seqs 8, then 25 → 20 GB because 25 GB left the host no reserve; that is the live
      shape. SUPPORTED ON 20 GB: gate 1 boot (healthy, restarts=0, KV boot lines quoted in
      docs/spark-llm-profiles.md §7), gate 4 at conc 8 (8/8 in 2.7 s) and at conc 2,
      gate 5 needle at 92 % of window 3/3 with preemptions +0, gate 7 read twice over a working
      day (19.79 h and 21.49 h, both PASS, tail slope +0.0 MiB/h, 0 restarts — CLOSED), and
      gate 6 at the ruled max_tokens 16384 WITH its baseline re-run in the same invocation:
      baseline ⟨n⟩/10, arm ⟨n⟩/10, agreement ⟨Δ⟩, budgets equal by the request bodies, engine
      identity identical across the legs. NOT CLAIMED BY THIS SHAPE: gate 2's 17.78 GiB rest
      figure — that is the 16 GiB shape's number, priced from terms this arm overrides with its
      own device_hold_ceiling_bytes (112.700e9); the 20 GB arm rests at 9.83–9.90 GiB by design
      (docs/spark-llm-profiles.md §7) and its rest evidence is gate 7's 11.73 GiB floor over a
      working day, not the 17.78 figure. gate 3's discrete ctx-probe leg was last taken on the
      16 GB shape (hd489-tail-b2) — the depth claim on 20 GB rests on gate 5's 241.2k fill, and
      this key does not pretend the probe itself was re-taken. gates 8–9 (MTP acceptance across
      dtypes, quality vs the noise floor) and the ple-table-fp8 ↔ Qwen3.8-Flash-Next-AWQ pairing
      row remain UNVERIFIED — DECLINED by the owner, no workaround, do not re-open them on this
      profile. fast-vs-reasoning quality is carried instead by the paired McNemar on 500
      MMLU-Pro-mini items: −0.20 pts, p = 1.000. fixed_cost_bytes here is MEASURED by the
      MemAvailable-jump method (92.13e9), not derived from a boot log, so gate 7's
      falsifier-for-derived-costs does not apply to it; the rest-window half sits in HD-494.
```

### Which legs the 20 GB shape supports

| gate | on 20 GB | where |
|---|---|---|
| 0 render parity | PASS (offline, shape-independent, gated in `validate-all.sh`) | `scripts/bench/spark-llm-render-matrix.py`, `scripts/gate/check_spark_llm_gate.py` |
| 1 boot | PASS — healthy, `restarts=0`, the engine's own KV lines quoted | [hd489-ar-blk](../hd489-ar-blk/README.md), [legs](../hd489-legs-20261006-1228/RESULTS.md) converge-back lines |
| 2 non-interference | **NOT the 17.78 GiB figure** — that is the 16 GiB shape's number; this arm overrides the host floor and rests 9.83–9.90 GiB by design, rest evidence is gate 7's 11.73 GiB floor | [docs/spark-llm-profiles.md](../../../docs/spark-llm-profiles.md) §7, [gate 7](../hd489-tail-gate7-20261007/RESULTS.md) |
| 3 real depth | discrete `ctx 262144` probe **UNVERIFIED at 20 GB** (last taken at 16 GB); depth is carried by gate 5's 241.2k fill at +0 preemptions | [hd489-tail-b2](../hd489-tail-b2/README.md), [overnight](../hd489-overnight-20261006-0226/RESULTS.md) |
| 4 concurrency | PASS at conc 8 (8/8, 2.7 s) and conc 2 | [overnight step 2](../hd489-overnight-20261006-0226/RESULTS.md) |
| 5 needle at depth | PASS 3/3 at 92 % of the window | [overnight step 2](../hd489-overnight-20261006-0226/RESULTS.md) |
| 6 accuracy | PASS at 1024 with one named exception (budget, not ability); **the ruled 16 384 re-run with its paired baseline is what this act supplies** | [20261006-2349](../hd489-tail-gate6-20261006-2349/RESULTS.md) + this directory |
| 7 memory curve | **CLOSED** — read twice, PASS twice, 0 restarts; the fill it hands HD-494 is +5,626 MiB fixed cost, peak +6,558 MiB | [gate 7](../hd489-tail-gate7-20261007/RESULTS.md) |
| 8, 9 dtype/quant axes | **UNVERIFIED — DECLINED by the owner** (B10's gates 6/8/9), and the `ple-table-fp8 ↔ AWQ` pairing row stays UNVERIFIED with no workaround | [legs §grants](../hd489-legs-20261006-1228/RESULTS.md) |

## ⛔ What this act must NOT re-run

Closing a leg by re-running it is how a certified shape loses its evidence. Out of scope here:

* **gate 7 — CLOSED** on this regime (read twice, PASS twice). Re-reading it is not caution, it is
  a second measurement of a different window. HD-494 keeps the rest-window half.
* **B10's gates 6/8/9 — declined by the owner.** They stay UNVERIFIED, by decision, with no
  workaround and no re-propose.
* **B9, B5, B8 — closed with their findings**: `ple_dispatch` is constitutive, not dialable
  (B9 = FAIL(BOOT)); no cliff from a cold page cache or a co-resident allocator, state the ~20 %
  penalties (B5); monitoring live, with the cold-scrape exclusivity caveat (B8).
* **no certified constant moves** — `pool_ceiling_bytes`, `fixed_cost_bytes`,
  `spark_llm_pool_ceiling_bytes`, `spark_llm_device_hold_ceiling_bytes` and the host floors are not
  this act's to touch, and a gate that would pass only after raising one is a finding, not a pass.
* **no converge, no restart, no dial flip, no `drop_caches`** from this act. Rule 0 binds the seat.

## Files

* `README.md` — this file (the act, the pairing argument, the proposed certificate line).
* `pairing-<tag>.md` — written by the driver, one per attempt: the pairing proof for that
  invocation. A retry adds a file; it never truncates the attempt before it.
* `raw/<tag>/` — written by the driver: both legs' captures and request bodies, the baseline stamp
  the guard refused to run without, the engine argv (bearer-scrubbed) and meminfo/`/metrics` at
  both ends, and the `-l 1` clock CSV for the whole two-leg window.
