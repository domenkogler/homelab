# Stability-run archive

Finished `spark/bench/overnight/` evidence, archived here deliberately (the live telemetry
dir `spark/bench/overnight/` itself stays git-ignored; these reports are the durable record).

Each `evidence-<ts>/` is one supervised stability-chain pull:

- `supervisor.log` — laptop-side supervisor transcript (sync, launch, polls, pull)
- `logs/launch.out` — the chain `launch.out` from spark (run START/END + verdict)
- `logs/rung*.log` — per-run step log (shape-churn + prefill rungs)
- `logs/step-*.log` — per-step `vllm bench serve` detail (the zero-load/Bad-Request evidence)
- `chain-bundle.tar` — the on-box bundle as pulled

Interpretation lives in the runbook: `spark/stability-test.md`.

## Index

| dir | date (UTC) | pool at run | verdict |
|---|---|---|---|
| `evidence-20260918-0042` | 2026-09-18 00:42 | **8.2 GiB** (pre-raise) | FAILED ❌ — full-window rung applied no real load (2×262,144-token chat = ~282.7k > `max_model_len` → 400 Bad Request, `ok=0/2 in_tok=0`); the harness correctly refused a fake pass. C1+C2 held: 0 OOM, 0 growth, usable 30.32→28.81 GiB, engine 86,725 MiB flat |
| `evidence-20260918-1113` | 2026-09-18 11:13 | **8.2 GiB** (same pre-raise chain re-pulled) | FAILED ❌ — same old-chain verdict; pulled again by `supervise.sh` before the 16 GiB floor re-tune |
| `evidence-20260918-1254` | 2026-09-18 12:54 | **16 GiB** (reserved 14.9 / 515,786 tok / 1.97×) | **PASSED ✅** — 3/3 runs, 0 kills, 0 reboots, 0 guard-fires, `restarts 0→0`, `/health` 200. Load was REAL: rung3 4×49,152 = 196,816 tok; compact 2×200k = **400,105 tok** (~77 % pool); fullwindow **2×240,000 = 480,105 tok ≈ 94.6 % pool**, ok=2/2. `usable` 18.84 → **worst 17.78** (kill point 1.62/1.64; WARN 12 / CRIT 8); engine top-pid 92,343 → **93,621 (+1,278 MiB)** across ~1.5 h of the hardest shape — this is the peak-bound verdict C1+C2 were waiting for. `oom-kill 3→3`; `NV_ERR_NO_MEMORY 234→243` (+9, see the tail in hardware-spark.md). Headroom answer: runtime +5.5 / boot **+5.4 GiB (binding)** → **16 GiB is the bf16 ceiling**. |

The two FAILED rows are the **same pre-raise chain**, not a stability finding: the full-window rung asked
for 2×262,144 tokens, which with the ~20.5k chat-template overhead lands at ~282.7k > `max_model_len` →
vLLM `400 Bad Request`, `ok=0/2 in_tok=0`. The harness refused to call zero load a pass — correct
behaviour, and the reason the 240k sizing exists. The 12:54 run re-ran that rung with real load and passed.

Interpretation lives in the runbook: [`spark/stability-test.md`](../../stability-test.md) (§3 verdict
mechanics, §4 how to read a failure, §6 the KV arithmetic — now carrying the certified 16 GiB numbers).