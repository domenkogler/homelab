#!/usr/bin/env bash
# ============================================================================
# vm-window.sh — cross-check ONE bench leg against VictoriaMetrics (HD-489)
#
# WHY THIS EXISTS, AND WHAT IT IS NOT. The engine's own counters already land in the
# VPS VictoriaMetrics (job="vllm", instance=spark.kogler.si — HD-368, cadence split by
# HD-420), so the funnel does not need a second load generator and must not write one.
# What the VM cannot do is tell the arms apart: all 16 HD-489 arms serve the SAME
# model_name (`spark/qwen3.8-flash-next`, a client anchor that must not move), so series
# attribution is BY TIMESTAMP WINDOW ONLY. This script is that window: it re-reads the
# engine's counters for one leg's [start,end] and compares them with what
# run-scenario.sh recorded off /metrics directly.
#
# It is a WITNESS, not the instrument. Two limits are structural, so the script enforces
# them instead of documenting them:
#   * the vllm:* latency histograms are the 60 s COLD set — a quantile over a short window
#     is smeared with everyone else's traffic, so corroboration is refused under 180 s;
#   * the counters are engine-global, so a window that contains another client's traffic
#     is not a clean leg: --expect-ok N is the exclusivity test (request_success must
#     move by exactly N).
# Reading the VM is legal for ANY session — /metrics-style reads are exactly what Rule 0
# (spark/llm-profiles/README.md) permits. PRODUCING the window is not: no leg may be run
# by a session served by spark/….
#
# Usage:
#   ./vm-window.sh --start 2026-10-02T19:00:00Z --end 2026-10-02T19:04:30Z \
#                  [--label u3-s8/C2] [--expect-ok 8]
#   ./vm-window.sh --csv results-v2.csv --ts 20261002-190000 [--expect-ok N]
#   ./vm-window.sh --dry-run --start … --end …        # print the PromQL, touch nothing
#
# Env:  VM_URL   REQUIRED, no default on purpose. The Victoria endpoint is IaC
#                `victoria_backend_host` (group_vars/all/main.yml) on :8428, reachable over
#                wg-s2s — a guessed default would silently query the wrong store.
#       creds    1Password `Homelab-ansible/victoria-metrics_api` via `op`, else
#                VM_USERNAME + VM_PASSWORD. Written to a 0600 curl config and unlinked on
#                exit — never argv, never printed, never in the repo.
# ============================================================================
set -euo pipefail

START=""; END=""; LABEL=""; EXPECT_OK=""; CSV=""; TS=""; DRY=0; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --start) START="${2:?--start needs an RFC3339Z timestamp}"; shift ;;
    --end)   END="${2:?--end needs an RFC3339Z timestamp}"; shift ;;
    --label) LABEL="${2:?--label needs a name}"; shift ;;
    --expect-ok) EXPECT_OK="${2:?--expect-ok needs the leg's N}"; shift ;;
    --csv)   CSV="${2:?--csv needs a results CSV}"; shift ;;
    --ts)    TS="${2:?--ts needs the row's RUN_TS}"; shift ;;
    --dry-run) DRY=1 ;;
    --force)   FORCE=1 ;;
    *) echo "unknown arg $1" >&2; exit 1 ;;
  esac
  shift
done

# A row already carries its window; prefer it over a hand-typed pair (typo = wrong leg).
if [ -n "$CSV" ] && [ -n "$TS" ]; then
  [ -f "$CSV" ] || { echo "ERROR: no such csv: $CSV (run-scenario.sh writes results-v2.csv)" >&2; exit 1; }
  ROW=$(awk -F',' -v ts="$TS" 'NR>1 && $2==ts {print; exit}' "$CSV")
  [ -n "$ROW" ] || { echo "ERROR: no row with ts=$TS in $CSV" >&2; exit 1; }
  [ -z "$START" ] && START=$(printf '%s' "$ROW" | cut -d, -f10)
  [ -z "$END" ]   && END=$(printf '%s' "$ROW" | cut -d, -f11)
  [ -z "$LABEL" ] && LABEL=$(printf '%s' "$ROW" | awk -F',' '{print $4"/"$3}')
  [ -z "$EXPECT_OK" ] && EXPECT_OK=$(printf '%s' "$ROW" | cut -d, -f19)
fi
[ -n "$START" ] && [ -n "$END" ] || { echo "ERROR: need --start and --end (or --csv + --ts)" >&2; exit 1; }

S=$(date -u -d "$START" +%s 2>/dev/null) || { echo "ERROR: cannot parse --start '$START' (want RFC3339 UTC, e.g. 2026-10-02T19:00:00Z)" >&2; exit 1; }
E=$(date -u -d "$END" +%s 2>/dev/null)   || { echo "ERROR: cannot parse --end '$END'" >&2; exit 1; }
[ "$E" -gt "$S" ] || { echo "ERROR: end must be after start" >&2; exit 1; }
DUR=$(( E - S ))
# One cold scrape of pad at each end: the histogram lines only move when a request
# COMPLETES, and the cold job samples once a minute, so the exact window edge loses a leg
# whose last request finished between two scrapes.
PAD=$(( DUR + 120 ))
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 needed to parse the query results" >&2; exit 1; }

# ---- the query set (printed verbatim by --dry-run, which is also the offline proof) --------
q(){ printf '%s\t%s\n' "$1" "$2"; }
QUERIES=$(cat <<EOF
$(q "gen_tok_delta           accepted-output tokens (5 s hot)"        "sum(increase(vllm:generation_tokens_total[${PAD}s]))")
$(q "prompt_tok_delta        prompt tokens (5 s hot)"                 "sum(increase(vllm:prompt_tokens_total[${PAD}s]))")
$(q "cached_tok_delta        prefix-cached prompt tokens (5 s hot)"   "sum(increase(vllm:prompt_tokens_cached_total[${PAD}s]))")
$(q "req_ok_delta            EXCLUSIVITY: must equal N"               "sum(increase(vllm:request_success_total[${PAD}s]))")
$(q "preempt_delta           preemptions (5 s hot)"                   "sum(increase(vllm:num_preemptions_total[${PAD}s]))")
$(q "recomp_tok_delta        re-computed prompt tokens = what a pin buys back" "sum(increase(vllm:request_prefill_kv_computed_tokens_sum[${PAD}s]))")
$(q "pfx_hit_delta           prefix-cache hit tokens (5 s hot)"        "sum(increase(vllm:prefix_cache_hits_total[${PAD}s]))")
$(q "pfx_query_delta         prefix-cache query tokens (5 s hot)"      "sum(increase(vllm:prefix_cache_queries_total[${PAD}s]))")
$(q "draft_tokens_delta      MTP drafts offered"                       "sum(increase(vllm:spec_decode_num_draft_tokens_total[${PAD}s]))")
$(q "accepted_spec_delta     MTP tokens accepted"                      "sum(increase(vllm:spec_decode_num_accepted_tokens_total[${PAD}s]))")
$(q "decode_tok_per_req_avg  engine-measured decode time per request"  "increase(vllm:request_decode_time_seconds_sum[${PAD}s])/increase(vllm:request_decode_time_seconds_count[${PAD}s])")
$(q "gen_tok_per_req_avg     output tokens per request (should be ~= OUT)" "increase(vllm:request_generation_tokens_sum[${PAD}s])/increase(vllm:request_generation_tokens_count[${PAD}s])")
$(q "preempt_running_max     peak concurrent requests in the window"   "max_over_time(sum(vllm:num_requests_running)[${PAD}s:5s])")
EOF
)
# Corroboration is quantiles over the LEG's padded window, not a 1-minute rate: measured
# 2026-10-02, `rate(vllm:time_to_first_token_seconds_bucket[1m])` evaluated at the window end
# returned EMPTY for TTFT p50/p95 because the cold job samples those once a minute and a rate
# needs two points. Anything shorter than two cold scrapes is not a measurement, it is a gap.
CORROB=$(cat <<EOF
$(q "ttft_p50  (corroboration only — over the leg window)"  "histogram_quantile(0.50, sum(rate(vllm:time_to_first_token_seconds_bucket[${PAD}s])) by (le))")
$(q "ttft_p95  (corroboration only — over the leg window)"  "histogram_quantile(0.95, sum(rate(vllm:time_to_first_token_seconds_bucket[${PAD}s])) by (le))")
$(q "tpot_p50  (corroboration only — over the leg window)"  "histogram_quantile(0.50, sum(rate(vllm:request_time_per_output_token_seconds_bucket[${PAD}s])) by (le))")
$(q "itl_p95   (corroboration only — over the leg window)"  "histogram_quantile(0.95, sum(rate(vllm:inter_token_latency_seconds_bucket[${PAD}s])) by (le))")
EOF
)

if [ "$DRY" = "1" ]; then
  echo "# dry run — window $START .. $END (${DUR}s, pad ${PAD}s), label=${LABEL:-unlabelled}"
  printf '%s\n' "$QUERIES" | sed 's/\t/\n    /; s/^/  /'
  if [ "$DUR" -ge 180 ] || [ "$FORCE" = "1" ]; then
    echo "# corroboration (cold-histogram quantiles, evaluate at --end):"
    printf '%s\n' "$CORROB" | sed 's/\t/\n    /; s/^/  /'
  else
    echo "# corroboration SKIPPED: ${DUR}s < 180 s = under 3 cold scrapes; VM quantiles for this"
    echo "#   window would mix in unrelated traffic. Trust run-scenario.sh's own ttft/itl columns."
  fi
  exit 0
fi

[ -n "${VM_URL:-}" ] || { echo "ERROR: VM_URL unset. Point it at the Victoria endpoint = IaC victoria_backend_host:8428" >&2; exit 1; }
if [ -z "${VM_USERNAME:-}" ] || [ -z "${VM_PASSWORD:-}" ]; then
  command -v op >/dev/null 2>&1 || { echo "ERROR: no op CLI and VM_USERNAME/VM_PASSWORD unset" >&2; exit 1; }
  VM_USERNAME=$(op read "op://Homelab-ansible/victoria-metrics_api/username" 2>/dev/null || true)
  VM_PASSWORD=$(op read "op://Homelab-ansible/victoria-metrics_api/password" 2>/dev/null || true)
fi
[ -n "${VM_USERNAME:-}" ] && [ -n "${VM_PASSWORD:-}" ] || { echo "ERROR: victoria-metrics_api credentials unreadable" >&2; exit 1; }
case "$VM_PASSWORD" in *\"*) echo "ERROR: credential contains a double quote; this script cannot embed it safely" >&2; exit 1;; esac

CFG=$(mktemp); chmod 0600 "$CFG"; trap 'rm -f "$CFG"' EXIT
printf 'user = "%s:%s"\n' "$VM_USERNAME" "$VM_PASSWORD" > "$CFG"
echo ">>> creds: user=${#VM_USERNAME} chars, secret=${#VM_PASSWORD} chars (values not printed)"

# Evaluate at the window END so increase()[<pad>] is anchored on the leg, not on "now".
ask(){ curl -sf -K "$CFG" -G --data-urlencode "query=$1" --data-urlencode "time=$E" "${VM_URL%/}/api/v1/query" \
       | python3 -c 'import sys,json
try:
    r = json.load(sys.stdin).get("data", {}).get("result", [])
except Exception:
    print("PARSE-FAIL"); raise SystemExit
print(r[0]["value"][1] if r else "EMPTY")'; }

echo ">>> leg ${LABEL:-unlabelled}  window $START .. $END  (${DUR}s, padded to ${PAD}s)"
echo ">>> counters (engine-side, over this window):"
printf '%s\n' "$QUERIES" | while IFS=$'\t' read -r name expr; do
  printf '  %-58s %s\n' "$name" "$(ask "$expr")"
done

# Exclusivity is a verdict, not a number to eyeball later.
OKD=$(ask "sum(increase(vllm:request_success_total[${PAD}s]))")
if [ -n "$EXPECT_OK" ]; then
  if [ "$(printf '%.0f' "$OKD" 2>/dev/null || echo x)" = "$(printf '%.0f' "$EXPECT_OK" 2>/dev/null || echo y)" ]; then
    echo ">>> EXCLUSIVITY OK — request_success moved by ${EXPECT_OK}, matching the leg's N. The window is the leg's."
  else
    echo ">>> EXCLUSIVITY FAILED — request_success moved by ${OKD}, the leg ran ${EXPECT_OK} requests."
    echo "    Someone else's traffic is inside this window: every counter delta above is theirs too."
    echo "    Do not use this window as arm-vs-arm evidence; re-run with the box quiet."
  fi
else
  echo ">>> EXCLUSIVITY UNCHECKED — no --expect-ok / no req_ok_delta column; compare req_ok_delta by hand."
fi

if [ "$DUR" -ge 180 ] || [ "$FORCE" = "1" ]; then
  echo ">>> corroboration ONLY (cold histograms over the leg's padded window — never the primary"
  echo "    timed number for a leg: run-scenario.sh's own ttft/itl columns are attributed to the"
  echo "    scenario, these also carry anything else that ran in the window):"
  printf '%s\n' "$CORROB" | while IFS=$'\t' read -r name expr; do
    printf '  %-58s %s\n' "$name" "$(ask "$expr")"
  done
else
  echo ">>> corroboration SKIPPED: ${DUR}s < 180 s (under 3 cold scrapes). Use C2L, or run --force"
  echo "    and accept that these quantiles include unrelated traffic. (--force prints them anyway.)"
fi
