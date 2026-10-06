#!/usr/bin/env bash
# HD-489 tail, gate 6 (accuracy) on the live 20 GB `fast` shape — headless driver.
# Runs ON spark, writes everything under /tmp (nothing on the repo side is touched by the run).
# Rule 0 note: this driver has no LLM in the loop; the accuracy battery is not a timed leg,
# and the sustained clocks.sm trace is recorded so the window is auditable either way.
set -uo pipefail
LABEL="${1:?label}"; TS="${2:?ts}"
EV="/tmp/hd489-gate6-$TS"; mkdir -p "$EV/raw"
BENCH_DIR="$EV" export BENCH_DIR
GATE=/tmp/accuracy-gate.sh

{ date -u +"%F %TZ"; hostname; docker inspect -f '{{.State.StartedAt}} restarts={{.RestartCount}}' vllm-qwen-spark
  docker inspect -f '{{join .Config.Cmd " "}}' vllm-qwen-spark | tr ' ' '\n' \
    | grep -A1 -e '^--model$' -e '^--max-num-seqs$' -e '^--kv-cache-memory-bytes$' -e '^--reasoning-parser$' -e '^--speculative-config$' -e '^--chat-template$' -e '^--tokenizer$'
  curl -s -o /dev/null -w 'health=%{http_code}\n' localhost:8000/health
} > "$EV/raw/seat.txt" 2>&1

{ grep -E '^(MemAvailable|CmaFree|MemFree)' /proc/meminfo; } > "$EV/raw/meminfo-before.txt"
curl -s localhost:8000/metrics | grep -E 'num_preemptions_total|prefix_cache|spec_decode|num_requests_total' > "$EV/raw/metrics-before.txt" 2>&1

# sustained clock trace across the whole window (the gate doc requires it)
( for i in $(seq 1 3600); do
    printf '%s ' "$(date -u +%FT%TZ)"; nvidia-smi --query-gpu=clocks.sm,power.draw,temperature.gpu --format=csv,noheader,nounits; sleep 1
  done > "$EV/raw/clocks-gate6.txt" 2>&1 ) & TRACE=$!

bash "$GATE" "$LABEL" > "$EV/raw/battery.log" 2>&1
RC=$?
kill $TRACE 2>/dev/null; wait $TRACE 2>/dev/null

curl -s localhost:8000/metrics | grep -E 'num_preemptions_total|prefix_cache|spec_decode|num_requests_total' > "$EV/raw/metrics-after.txt" 2>&1
{ grep -E '^(MemAvailable|CmaFree|MemFree)' /proc/meminfo; } > "$EV/raw/meminfo-after.txt"
docker logs --since 30m vllm-qwen-spark 2>&1 | grep -ciE 'preempt|out of memory' > "$EV/raw/engine-warn-count.txt" 2>&1
echo "battery_rc=$RC" > "$EV/raw/rc.txt"
echo "DONE rc=$RC" >> "$EV/raw/battery.log"
