#!/usr/bin/env bash
# ============================================================================
# snapshot-metrics.sh — grab vLLM Prometheus counters into a timestamped file
# and print a one-line summary. Run BEFORE and AFTER every benchmark run.
#
# Usage:  ./snapshot-metrics.sh <label>          e.g. ./snapshot-metrics.sh before-C3
# Env:    VLLM_URL  (default http://localhost:8000)   — use :8080 for router view
# ============================================================================
set -euo pipefail

LABEL="${1:?usage: snapshot-metrics.sh <label>}"
BENCH_DIR="${BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
OUT_DIR="$BENCH_DIR/raw"
mkdir -p "$OUT_DIR"

TS=$(date -u +%Y%m%d-%H%M%S)
SAFE_LABEL=$(echo "$LABEL" | tr -c 'A-Za-z0-9_-_' '_')
FILE="$OUT_DIR/metrics-${TS}-${SAFE_LABEL}.txt"
METRICS_URL="${VLLM_URL:-http://localhost:8000}/metrics"

curl -sf "$METRICS_URL" > "$FILE" || { echo "ERROR: cannot reach $METRICS_URL" >&2; exit 1; }

get() { grep -E "^${1}\b" "$FILE" | tail -1 | awk '{print $2}'; }

PREEMPT=$(get 'vllm:num_preemptions_total')
GPU_CACHE=$(get 'vllm:gpu_cache_usage_perc')
ACCEPTED=$(get 'vllm:spec_decode_num_accepted_tokens_total')
DRAFT=$(get 'vllm:spec_decode_num_draft_tokens_total')
PROMPT_TOK=$(get 'vllm:prompt_tokens_total')
GEN_TOK=$(get 'vllm:generation_tokens_total')
RUNNING=$(get 'vllm:num_requests_running')
WAITING=$(get 'vllm:num_requests_waiting')

# MTP acceptance ratio (guard div-by-zero)
ACCEPT_RATIO="n/a"
if [[ -n "${ACCEPTED:-}" && -n "${DRAFT:-}" && "${DRAFT:-0}" != "0" && "${DRAFT:-0}" != "None" ]]; then
  ACCEPT_RATIO=$(awk -v a="${ACCEPTED:-0}" -v d="${DRAFT:-0}" 'BEGIN{printf "%.3f", a/d}')
fi

# Cache hit naming varies by vLLM version; capture whatever exists, raw.
CACHE_LINE=$(grep -E "cache" "$FILE" | grep -vE "^#" | tail -5 || true)

SUMMARY="ts=${TS} label=${SAFE_LABEL} running=${RUNNING:-?} waiting=${WAITING:-?} preempt_total=${PREEMPT:-?} gpu_cache=${GPU_CACHE:-?}% mtp_accept=${ACCEPT_RATIO} prompt_tok=${PROMPT_TOK:-?} gen_tok=${GEN_TOK:-?}"

echo "$SUMMARY"
echo "$SUMMARY" >> "$BENCH_DIR/metrics-summary.log"
[[ -n "$CACHE_LINE" ]] && { echo "--- cache metrics (raw) ---"; echo "$CACHE_LINE"; } >> "$BENCH_DIR/metrics-summary.log"

# Emit machine-readable values for the runner script (KEY=value lines)
cat > "$OUT_DIR/metrics-${TS}-${SAFE_LABEL}.env" <<EOF
TS=${TS}
PREEMPT=${PREEMPT:-}
GPU_CACHE=${GPU_CACHE:-}
ACCEPTED=${ACCEPTED:-}
DRAFT=${DRAFT:-}
PROMPT_TOK=${PROMPT_TOK:-}
GEN_TOK=${GEN_TOK:-}
EOF
echo "$OUT_DIR/metrics-${TS}-${SAFE_LABEL}.env"
