#!/usr/bin/env bash
# ============================================================================
# accuracy-gate.sh — fire a fixed 10-prompt sanity set and save raw outputs
# for comparison against the B1 baseline outputs.
#
# Usage:  ./accuracy-gate.sh <CONFIG_LABEL>     e.g. ./accuracy-gate.sh step7-fp8kv
#
# After each run, diff/eyeball:
#   diff bench/accuracy/B1/code-fib.json.out bench/accuracy/<LABEL>/code-fib.json.out
#
# KEEP the change only if no visible degradation vs B1. For a stricter gate,
# extend PROMPTS with your own scored tool-calling items (primitive's protocol
# style: pass/fail per item, keep if mean score within ±1.5 of baseline).
# ============================================================================
set -euo pipefail

LABEL="${1:?usage: accuracy-gate.sh <CONFIG_LABEL>}"
BENCH_DIR="${BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT_DIR="$BENCH_DIR/accuracy/$LABEL"; mkdir -p "$OUT_DIR"
URL="${VLLM_URL:-http://localhost:8000}/v1/chat/completions"
MODEL="${MODEL_NAME:-/model}"

declare -A PROMPTS=(
  [code-fib]="Write a Python function computing the nth Fibonacci number with memoization. Then show the first 10 values as a comment."
  [json-extract]="Extract {name, date, amount} from this text as strict JSON, nothing else: 'On March 3rd, Ada Lovelace invoiced 1,250 EUR for consulting.'"
  [math-multistep]="A train leaves at 14:00 traveling 90 km/h. A second train leaves the same station at 15:00 at 120 km/h. At what time does the second overtake the first? Show your reasoning briefly."
  [logic]="All bloops are razzies. All razzies are lazzies. Are all bloops definitely lazzies? Answer yes or no and justify in one sentence."
  [code-review]="Review this snippet for bugs and fix them: def avg(xs): return sum(xs)/len(xs)"
  [html-game]="Write a complete single-file HTML tic-tac-toe game with an unbeatable AI using minimax. Include the full code."
  [summarize]="Summarize in exactly 3 bullet points: Photosynthesis converts light energy into chemical energy in chloroplasts. The Calvin cycle fixes CO2 into glucose using ATP and NADPH. Oxygen is released as a byproduct of water splitting."
  [tool-call]="What is the weather in Ljubljana right now? Use the provided get_weather tool."   # tests tool parsing (needs --enable-auto-tool-choice)
  [state-tracker]="I have a red box, a blue box, and a green box. I move the marble from red to blue, then from blue to green, then from green to red. Where is the marble now? One word answer plus one sentence."
  [long-reasoning]="Prove briefly that the square root of 2 is irrational."
)

ORDER=(code-fib json-extract math-multistep logic code-review html-game summarize tool-call state-tracker long-reasoning)

for key in "${ORDER[@]}"; do
  echo ">>> [$key]"
  PROMPT=$(printf '%s' "${PROMPTS[$key]}")
  BODY=$(jq -n --arg m "$MODEL" --arg p "$PROMPT" '{model:$m, messages:[{role:"user",content:$p}], max_tokens:1024, temperature:0}')
  if curl -sf -X POST "$URL" -H "Content-Type: application/json" -d "$BODY" \
      -o "$OUT_DIR/${key}.json"; then
    jq -r '.choices[0].message.content // .error.message // "EMPTY"' "$OUT_DIR/${key}.json" > "$OUT_DIR/${key}.out" 2>/dev/null || echo "PARSE-ERROR" > "$OUT_DIR/${key}.out"
    head -c 200 "$OUT_DIR/${key}.out"; echo; echo "---"
  else
    echo "FAILED: $key (HTTP error)" | tee "$OUT_DIR/${key}.out"
  fi
done

echo ">>> saved to $OUT_DIR"
echo ">>> diff against baseline:"
echo "    for f in $BENCH_DIR/accuracy/B1/*.out; do diff \$f $OUT_DIR/\$(basename \$f) | head -20; done"
