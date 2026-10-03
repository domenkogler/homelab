# §E MMLU-Pro mini — run on `ar-blk` (in progress)

**Status: RUNNING (started 2026-10-03 ~18:42 UTC+2, conc 3).** Slow but live:
the engine shows 3 requests running / 0 waiting; `business` completed (acc 0.938-0.944
on 16-18 items), `engineering` in progress.

## Why it's slow (measured, not guessed)
- Decode-bound (ar-blk ~39.7 tok/s) × CoT-mandatory → each item generates long.
- The L0 finding: server-side `override_generation_config {temperature:1}` overrides
  client temp 0 ⇒ outputs are long/flaky, which the harness's retry/thinking amplifies.
- The brief's "2-3 h conc 3" estimate predates both.

## How to resume/check (from the laptop, tunnel up)
```
ssh -N -f -L 8000:127.0.0.1:8000 spark                 # if tunnel not up
export OPENAI_API_KEY="$(op item get spark-llm_api --vault Homelab-ansible --fields label=credential --reveal)"
cd /tmp/mmlu-pro-harness
MMLU_PRO_MINI=/tmp/mmlu-pro-harness/mini_test.json \
  /tmp/mmlu-venv/bin/python evaluate_from_apiX.py --url http://localhost:8000/v1 \
    -m spark/qwen3.8-flash-next -n 3 -o /tmp/mmlu-eval-arblk/ --retry 2 --retry_wrong 2
# then:
/tmp/mmlu-venv/bin/python compute_accuracy.py -p /tmp/mmlu-eval-arblk/generative/*results.json
```

## Reproducibility pins
- Harness: TIGER-AI-Lab/MMLU-Pro @ `f418b116` (shallow clone) — evaluate_from_apiX.py (patched:
  mini loader via MMLU_PRO_MINI + API_KEY from OPENAI_API_KEY + dev/val CoT supply).
- Mini slice: first 100/category × 14 = 1,400 rows, sha256 `e67bad86a84e25bc…`
  (deterministic; leading-space fix present = post-2026-01-18 revision).
- Engine: `ar-blk` (live), `spark/qwen3.8-flash-next`, external runner, Rule 0 clean.
