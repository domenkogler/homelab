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

The 16 GiB ladder (rung123 → compact → fullwindow 2×240k ≈ 94.6 % pool) results will land here
as `evidence-20260918-1XXX` once you run it.