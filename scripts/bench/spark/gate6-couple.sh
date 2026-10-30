#!/usr/bin/env bash
# ============================================================================
# gate6-couple.sh — HD-489's gate 6 as ONE act: the B1 baseline and the accuracy
# battery, fired at the SAME max_tokens, in ONE invocation.
#
# WHY A DRIVER AND NOT TWO COMMANDS. The owner's ruling is that gate 6's battery budget goes
# 1024 -> 16 x 2^10 = 16384, and that the two edits ship together or neither does, because
# grading a reasoning arm against a baseline made under the OLD budget is not a measurement —
# it is two measurements stapled together. That is exactly what produced `code-fib` EMPTY at
# finish_reason=length in spark/reports/hd489-tail-gate6-20261006-2349/RESULTS.md: 1024
# completion tokens, all 1024 of them spent as reasoning_tokens, on an engine booted with
# `--reasoning-parser qwen3`. A ruling that lives in a row's tail binds only as far as someone
# remembers it, so the coupling moves into the argv: no invocation of this script runs the
# battery without having just run its baseline at the same budget, and the refusal is a
# self-test case rather than a sentence in a README.
#
# HOW THE PAIRING IS PROVEN RATHER THAN ASSERTED. accuracy-gate.sh now takes the budget as a
# call-site value (--max-tokens, whose default is still 1024) and can echo every request body
# it sends into a log. So the proof reads the budget BACK out of the bodies both legs put on the
# wire — not out of what this script hoped it asked for — and prints it against the engine
# identity and the two timestamps. A battery that quietly ignored the flag, or an engine that
# was restarted or re-dialled between the two legs, FAILS the pairing instead of printing a PASS.
#
# RULE 0 (spark/llm-profiles/README.md, restated in prompt-spark-llm.md): a session whose own
# model is served by spark refuses here before its first read. Gate 6 scores quality rather than
# tok/s, but this act still belongs off the served loop: its pairing proof asserts the window was
# quiet (preemption and prefix-cache deltas), and a spark-served session's own tokens land in
# precisely those counters while competing for the pool it is grading. Take the act from an
# externally-served session on the designated runner station (docs/orchestration.md §4,
# prompt-laptop-wsl.md §0/§1). The run is stamped <hostname>/agent:<PI_MODEL>, the shape
# run-scenario.sh writes into the results CSV's `client` column, so the seat is checkable after.
#
# READ-ONLY against the box by construction: every far-side command goes through host_read() and
# is a read (docker inspect, /proc/meminfo, /metrics, nvidia-smi). It never converges, never
# restarts a container, never writes a profile and never edits `certified_evidence` — the
# certificate's last line is AUTHORED in the evidence dir's README by a session, from the numbers
# this prints. --self-test runs the whole driver against fixtures and asserts both that no mutate
# verb reaches the transport and that nothing outside the evidence dir changed, so read-only is a
# CHECKED property, not a promise.
#
# Usage
#   scripts/bench/spark/gate6-couple.sh [--max-tokens N] [--url URL] [--host spark]
#       [--container NAME] [--arm-label LABEL] [--out DIR] [--window SECONDS]
#       [--dry-run] [--battery-only] [--self-test]
#
#   --host is the ssh NAME of the box (default spark). Away from the house name the hop:
#   `--host spark-vps`. A plain node name is the Home leg with no jump, so off-site it times
#   out and reads like a dead box (docs/network-vpn.md §The laptop alias contract rule 1).
#
#   --max-tokens    the ONE budget both legs get. Default 16384 = 16 x 2^10, the owner's ruling.
#                   1024 stays addressable — it is the historical basis — but only by naming it.
#   --url           the chat endpoint base handed to the battery as VLLM_URL. Defaults to
#                   http://localhost:8000, i.e. accuracy-gate.sh's own default, so an on-box run
#                   needs nothing. The bearer itself comes from the engine container's argv via
#                   `docker inspect` on the machine the battery runs on — never from here, never
#                   from the environment, never printed.
#   --arm-label     label the arm's captures are written under (default gate6-arm-<UTC tag>). The
#                   baseline leg's label is `B1`, the battery's reference label. Both legs write
#                   under the evidence dir, so a run NEVER touches the committed
#                   scripts/bench/spark/accuracy/B1 captures.
#   --battery-only  REFUSES, always, with exit 4. It exists so that the shortcut the ruling
#                   forbids ("the baseline ran yesterday, just re-fire the battery") is a named
#                   flag with a red exit instead of a hand-edited driver or a shell-history line.
#   --dry-run       prints the exact commands an operator would run and touches nothing.
#
# One attempt takes minutes at 1024 and, at 16384 with thinking on, roughly
# 10 items x 16384 tokens / ~40 tok/s PER LEG — plan the window. --window caps the clock sampler,
# not the legs.
#
# Fixture hooks — what keeps --self-test off the box and off the vault (and why it is the one arm
# Rule 0 does not have to refuse):
#   GATE6_SSH_CMD   command that receives each far-side command on stdin
#   GATE6_GATE      the battery to drive (default: accuracy-gate.sh beside this file)
#   GATE6_CURL_CMD  the transport the battery's requests go to (fixture use only)
#   GATE6_LOG_DIR   where the per-attempt gate6-*.log files are created
#
# Exit: 0 captured · 1 a capture missing or unparseable · 2 usage · 3 Rule 0 ·
#       4 PAIRING REFUSED — the battery did not get a baseline of its own, at its own budget, in
#         this invocation; or the engine moved underneath the two legs; or the budget that reached
#         the wire is not the budget this act promised ·
#       6 the engine container is not running
# ============================================================================
set -euo pipefail
# Numbers land in a markdown table and inside an equality test. Under an sl_SI locale awk's "%.2f"
# prints 15,99, which splits a field and never equals the hand-valued fixture it is tested against.
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root FOUND, never assumed from a depth (scripts/lib/repo-root.sh): the evidence dir lives
# under <root>/spark/reports, and a wrong depth writes evidence nobody finds.
_hl_d="$SELF_DIR"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"

RULED=16384                      # 16 x 2^10 — the owner's ruling, written once, printed everywhere
MAX_TOKENS="$RULED"
HOST="spark"
URL="${VLLM_URL:-http://localhost:8000}"
CONTAINER="${VLLM_CONTAINER:-vllm-qwen-spark}"
BASELINE_LABEL="B1"
ARM_LABEL=""
OUT=""
WINDOW=10800                     # cap on the clock sampler, seconds (it ends with the legs)
TEST=0
DRY=0
BATTERY_ONLY=0
GATE="${GATE6_GATE:-$SELF_DIR/accuracy-gate.sh}"
SELF_NAME="$(basename "${BASH_SOURCE[0]}")"

# Set by run_main; declared here so `set -u` never meets them unset.
CLIENT="" TAG="" RAW="" STAMP="" PAIRED_BUDGET="" TRACE_PID=""
TS_BASELINE="" TS_BASELINE_END="" TS_ARM="" TS_ARM_END=""

die() { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --max-tokens)
      [ $# -ge 2 ] || die "--max-tokens needs a token count, e.g. $RULED" 2
      MAX_TOKENS="$2"; shift ;;
    --url)       [ $# -ge 2 ] || die "--url needs the chat endpoint base" 2; URL="$2"; shift ;;
    --host)      [ $# -ge 2 ] || die "--host needs the box name" 2; HOST="$2"; shift ;;
    --container) [ $# -ge 2 ] || die "--container needs the engine container name" 2; CONTAINER="$2"; shift ;;
    --arm-label) [ $# -ge 2 ] || die "--arm-label needs the capture label" 2; ARM_LABEL="$2"; shift ;;
    --out)       [ $# -ge 2 ] || die "--out needs the evidence directory" 2; OUT="$2"; shift ;;
    --window)    [ $# -ge 2 ] || die "--window needs seconds" 2; WINDOW="$2"; shift ;;
    --dry-run)     DRY=1 ;;
    --battery-only) BATTERY_ONLY=1 ;;
    --self-test)   TEST=1 ;;
    *)           die "unknown arg $1 — see the Usage block" 2 ;;
  esac
  shift
done
case "$MAX_TOKENS" in
  ''|*[!0-9]*) die "--max-tokens wants a positive integer, got '$MAX_TOKENS'" 2 ;;
esac
[ "$MAX_TOKENS" -ge 1 ] || die "--max-tokens must be >= 1, got $MAX_TOKENS" 2
case "$WINDOW" in
  ''|*[!0-9]*) die "--window wants seconds, got '$WINDOW'" 2 ;;
esac

OUT="${OUT:-$REPO/spark/reports/hd489-tail-gate6-$(date -u +%Y%m%d)}"

# Rule 0, FIRST: before ssh, before the log file, before anything is read. A spark-served session
# IS the traffic whose quietness the pairing proof asserts. `--self-test` is the one exempt arm:
# it is fixture-only by construction (the transport is GATE6_SSH_CMD and the battery's HTTP goes
# to GATE6_CURL_CMD), so refusing it would make the refusal untestable from the very seat that
# needs the proof.
if [ "$TEST" != "1" ] && { [ "${PI_PROVIDER:-}" = "spark" ] || printf '%s' "${PI_MODEL:-}" | grep -q '^spark/'; }; then
  printf 'ERROR: Rule 0 — this session is served by spark (PI_PROVIDER=%s PI_MODEL=%s), so it may\n' \
    "${PI_PROVIDER:-unset}" "${PI_MODEL:-unset}" >&2
  printf '       take no timed number and no engine-quiet window, and this act drives both of its\n' >&2
  printf '       legs through that engine. Run it from an externally-served session on the\n' >&2
  printf '       designated runner station (the WSL Debian seat: prompt-laptop-wsl.md §0/§1,\n' >&2
  printf '       docs/orchestration.md §4). Counter, log and inspect READS stay legal from any\n' >&2
  printf '       session; this act is not one of them.\n' >&2
  exit 3
fi

# A fixture transport for the battery's HTTP. Exported here rather than on the call site, because
# an assignment word built by expansion is not reliably recognised as one.
if [ -n "${GATE6_CURL_CMD:-}" ]; then
  export ACCURACY_GATE_CURL_CMD="$GATE6_CURL_CMD"
fi

# <hostname>/agent:<PI_MODEL> — the stamp run-scenario.sh writes into the results CSV, so a leg
# taken off-station, or from a spark-served seat, is identifiable in the evidence afterwards.
client_stamp() {
  printf '%s/%s' "${BENCH_CLIENT:-$(hostname -s 2>/dev/null || echo unknown)}" \
    "agent:${PI_MODEL:-none}" | tr -d ','
}

# One log file per ATTEMPT (hd469-baseline.sh's shape): a retry inside the same minute gains .1,
# .2 …, because a retry that reopens the previous attempt's file truncates the only record of the
# attempt that failed.
attempt_log() {
  local dir="${GATE6_LOG_DIR:-/tmp}" n=1 path
  path="$dir/gate6-$(date +%H%M).log"
  while [ -e "$path" ]; do
    path="$dir/gate6-$(date +%H%M).$n.log"
    n=$((n + 1))
  done
  printf '%s' "$path"
}

# The ONE door to the far side. Everything sent through it is a read; --self-test intercepts it
# here, which is what lets the fixture arms exercise the real command strings.
host_read() {
  local cmd="$1"
  if [ -n "${GATE6_SSH_CMD:-}" ]; then
    printf '%s\n' "$cmd" | $GATE6_SSH_CMD
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$cmd"
  fi
}

STATE_SNIPPET="docker inspect -f '{{.State.Running}} {{.State.StartedAt}} restarts={{.RestartCount}}' @CONTAINER@"
ARGV_SNIPPET="docker inspect -f '{{join .Config.Cmd \" \"}}' @CONTAINER@"
MEMINFO_SNIPPET="grep -E '^(MemTotal|MemAvailable|CmaFree):' /proc/meminfo"
METRICS_SNIPPET="curl -s --max-time 10 localhost:8000/metrics | grep -E 'num_preemptions_total|prefix_cache|spec_decode'"
CLOCKS_SNIPPET="timeout @WINDOW@ nvidia-smi --query-gpu=timestamp,clocks.sm,power.draw,temperature.gpu --format=csv -l 1"

cleanup() {
  if [ -n "${TRACE_PID:-}" ]; then kill "$TRACE_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT

# engine_conf <argv> — the flags that decide what a battery score MEANS on this engine: model,
# template, thinking parser, pool, batch shape, speculation, tool parsing. `--api-key` is
# deliberately absent: this text is printed and committed, and the engine bearer is neither. The
# `grep -v '^--$'` removes grep's own group separator, which is not an engine flag.
engine_conf() {
  printf '%s\n' "$1" | tr ' ' '\n' \
    | grep -A1 -e '^--model$' -e '^--chat-template$' -e '^--tokenizer$' -e '^--reasoning-parser$' \
                  -e '^--kv-cache-memory-bytes$' -e '^--max-num-seqs$' -e '^--max-model-len$' \
                  -e '^--speculative-config$' -e '^--enable-auto-tool-choice$' -e '^--tool-call-parser$' \
    | grep -v '^--$' \
    | tr '\n' ' ' || true
}

# scrub_argv — a FILTER that removes the engine bearer from an argv dump. The engine's own argv
# carries `--api-key`, and a raw capture of a running system holds its own credentials:
# spark/reports/hd489-overnight-20261006-0226/raw/b10-boot.txt is the published leak that taught
# this repo that rule (HD-1170), and run-scenario.sh scrubs at the point of write for the same
# reason. Same rule, applied to this driver's captures.
scrub_argv() { sed -E 's/(--api-key[= ])[^ "]+/\1<scrubbed>/g'; }

# mem_pair <meminfo> <label> — "<avail_kib> <cma_kib> <usable_gib>", loud if a half is missing.
# Both fields are mandatory: MemAvailable ALONE is the falsified gauge on GB10, because CMA counts
# as available and INFLATES under pressure. Same rule as hd469-baseline.sh and the watchdog.
mem_pair() {
  local text="$1" label="$2" a c
  a=$(printf '%s\n' "$text" | awk '$1 == "MemAvailable:" {print $2; exit}') || true
  c=$(printf '%s\n' "$text" | awk '$1 == "CmaFree:" {print $2; exit}') || true
  [ -n "$a" ] || die "$label: the meminfo read holds no MemAvailable — a failed read is not a zero" 1
  [ -n "$c" ] || die "$label: the meminfo read holds no CmaFree — MemAvailable alone is the FALSIFIED gauge on GB10, refusing to read it as 0" 1
  printf '%s %s %s\n' "$a" "$c" \
    "$(awk -v a="$a" -v c="$c" 'BEGIN{printf "%.2f", (a-c)/1048576}')"
}

# counter_sum <metrics text> <metric> — sum EVERY series of a labelled counter: prefix_cache_*
# carries labels, so picking one line reports a fraction of the truth.
counter_sum() {
  printf '%s\n' "$1" | awk -v m="$2" '!/^#/ && $1 ~ "^"m"([ {]|$)" { s += $NF } END{printf "%.0f", s+0}'
}

trace_stat() {   # <csv> <column> [printf format] -> "min median max"
  awk -F',' -v c="$2" -v f="${3:-%.0f}" '
    NR > 1 { v = $c; gsub(/[^0-9.]/, "", v); if (v == "") next; n++; a[n] = v + 0 }
    END {
      if (!n) { print "n/a n/a n/a"; exit }
      for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (a[j] < a[i]) { t = a[i]; a[i] = a[j]; a[j] = t }
      lo = a[1]; med = (n % 2 ? a[(n + 1) / 2] : (a[n / 2] + a[n / 2 + 1]) / 2); hi = a[n]
      printf f" " f " " f"\n", lo, med, hi
    }' "$1"
}

# bodies_field <bodies.tsv> — the request bodies of one leg, one JSON per line. The log is
# `<key>\t<json>`, so field 2 onward is the body the engine was actually handed.
bodies_field() {
  [ -s "$1" ] || return 0
  cut -f2- "$1"
}

# budget_in_bodies <bodies.tsv> — the distinct budget(s) this leg put ON THE WIRE. THIS is the
# pairing evidence: what was asked for, read back, rather than what this script hoped it asked for.
budget_in_bodies() {
  local v
  v="$(bodies_field "$1" | jq -r '.max_tokens // "none"' 2>/dev/null | sort -u | paste -sd' ' - || true)"
  printf '%s' "${v:-none}"
}

# count_at <bodies.tsv> <budget> — how many of this leg's requests carried that exact budget.
count_at() {
  local n
  n="$(bodies_field "$1" | jq -r '.max_tokens // "none"' 2>/dev/null | grep -c "^$2\$" || true)"
  printf '%s' "${n:-0}"
}

body_lines() {
  [ -s "$1" ] && wc -l < "$1" || printf '0'
}

# ---------------------------------------------------------------------------
# THE GUARD. Everything else in this file is bookkeeping around this function.
# ---------------------------------------------------------------------------
require_pairing() {
  if [ -z "${PAIRED_BUDGET:-}" ]; then
    printf 'ERROR: PAIRING REFUSED — this invocation is about to fire the battery at %s WITHOUT\n' "$MAX_TOKENS" >&2
    printf '       having run its baseline in the SAME invocation.\n' >&2
    printf '       An arm graded against a baseline made under a different budget is not a\n' >&2
    printf '       measurement, so there is no flag that reuses one. Drop --battery-only and run\n' >&2
    printf '       the act whole: gate6-couple.sh --max-tokens %s\n' "$MAX_TOKENS" >&2
    printf '       The ruling + the basis it replaces:\n' >&2
    printf '       spark/reports/hd489-tail-gate6-20261006-2349/RESULTS.md\n' >&2
    if [ -n "${STAMP:-}" ] && [ -e "${STAMP:-}" ]; then
      printf '       A baseline from an EARLIER attempt sits at %s. It is deliberately not reused.\n' "$STAMP" >&2
    fi
    return 4
  fi
  if [ "$PAIRED_BUDGET" != "$MAX_TOKENS" ]; then
    printf 'ERROR: PAIRING REFUSED — the baseline leg of this invocation ran at %s, the battery is\n' "$PAIRED_BUDGET" >&2
    printf '       being asked for %s. Two budgets, two measurements, no verdict.\n' "$MAX_TOKENS" >&2
    return 4
  fi
  local stamped
  stamped="$(awk -F= '$1 == "max_tokens" {print $2}' "${STAMP:-/nonexistent}" 2>/dev/null || true)"
  if [ "$stamped" != "$MAX_TOKENS" ]; then
    printf 'ERROR: PAIRING REFUSED — the baseline stamp on disk says %s, the battery is asked for %s.\n' \
      "${stamped:-nothing}" "$MAX_TOKENS" >&2
    return 4
  fi
  return 0
}

# run_leg <role: baseline|arm> <label> — one pass of the battery, into its own folder under this
# attempt's raw/, with the request bodies logged so the budget is checkable afterwards.
run_leg() {
  local role="$1" label="$2" legdir rc captured failed
  legdir="$RAW/leg-$role"
  mkdir -p "$legdir"
  if [ "$role" = baseline ]; then
    STAMP="$RAW/leg-baseline.stamp"
    PAIRED_BUDGET=""
  else
    require_pairing || return 4
  fi
  printf '>>> leg %s: label=%s max_tokens=%s url=%s\n' "$role" "$label" "$MAX_TOKENS" "$URL"
  BENCH_DIR="$legdir" VLLM_URL="$URL" \
    ACCURACY_GATE_BODY_LOG="$RAW/leg-$role.bodies.tsv" \
    bash "$GATE" "$label" --max-tokens "$MAX_TOKENS" > "$RAW/leg-$role.log" 2>&1 && rc=0 || rc=$?
  captured="$(find "$legdir" -name '*.json' 2>/dev/null | wc -l || true)"
  failed="$(grep -c '^FAILED:' "$RAW/leg-$role.log" 2>/dev/null || true)"
  [ "${captured:-0}" -ge 1 ] || die "leg $role produced no responses at all (battery rc $rc, log: $RAW/leg-$role.log) — nothing was measured" 1
  [ "${captured:-0}" -gt "${failed:-0}" ] || die "leg $role: every item failed at HTTP level (battery rc $rc, log: $RAW/leg-$role.log). A 401 here means the bearer did not reach the request: the battery reads it from the engine container's argv, so the battery must run where that container is visible. This is not a battery result." 1
  PAIRED_BUDGET="$MAX_TOKENS"
  if [ "$role" = baseline ]; then
    printf 'max_tokens=%s\nlabel=%s\nutc=%s\nclient=%s\nbodies=%s\n' \
      "$MAX_TOKENS" "$label" "$(date -u +%FT%TZ)" "$CLIENT" "$captured" > "$STAMP"
  fi
  printf '>>> leg %s: %s item(s), %s HTTP failure(s), battery rc %s, budget on the wire: %s\n' \
    "$role" "$captured" "${failed:-0}" "$rc" "$(budget_in_bodies "$RAW/leg-$role.bodies.tsv")"
}

run_main() {
  local tag_prev state argv clk pow trace_csv trace_rows ready_i ready
  local mem_s mem_e pair_s pair_e met_s met_e pre_d pfx_h_d pfx_q_d conf_b conf_a boot_b boot_a
  local b_base b_arm n_base n_arm ok_base ok_arm wire_ok
  CLIENT="$(client_stamp)"
  TAG="$(date -u +%Y%m%d-%H%M%S)"
  RAW="$OUT/raw/$TAG"
  STAMP=""
  PAIRED_BUDGET=""
  TRACE_PID=""
  ARM_LABEL="${ARM_LABEL:-gate6-arm-$TAG}"
  mkdir -p "$RAW"
  printf '>>> gate6-couple out=%s tag=%s client=%s\n' "$OUT" "$TAG" "$CLIENT"
  if [ "$MAX_TOKENS" = "$RULED" ]; then
    printf '>>> budget BOTH legs get: max_tokens=%s (the ruled 16 x 2^10)\n' "$MAX_TOKENS"
  else
    printf '>>> budget BOTH legs get: max_tokens=%s — NOT the ruled %s. Name it only if that is the basis you mean.\n' \
      "$MAX_TOKENS" "$RULED"
  fi
  # A baseline from an earlier attempt is reported and then ignored: reusing one across attempts is
  # the exact act the ruling forbids, so the only way to "use" it is to re-run the act.
  for tag_prev in "$OUT"/raw/*/leg-baseline.stamp; do
    if [ -e "$tag_prev" ]; then
      printf '>>> NOTE: an earlier attempt baselined at %s. It is NOT reused; this run baselines again.\n' "${tag_prev#"$OUT"/}"
    fi
  done

  # Container identity FIRST (run-scenario.sh's lesson): with the wrong name every later read is
  # empty and the run still prints a complete-looking file set.
  state="$(host_read "${STATE_SNIPPET//@CONTAINER@/$CONTAINER}" 2>/dev/null || echo "false unknown")"
  if [ "$(printf '%s' "$state" | awk '{print $1}')" != "true" ]; then
    printf 'ERROR: container %s is not running on %s, so there is no engine to grade.\n' "$CONTAINER" "$HOST" >&2
    printf '       The name is IaC spark_vllm_container -> spark_llm_profiles[spark_llm_profile].container;\n' >&2
    printf '       pass --container <name> for the arm actually serving. Nothing was captured.\n' >&2
    exit 6
  fi
  boot_b="$(printf '%s' "$state" | cut -d' ' -f2-)"

  mem_s="$(host_read "$MEMINFO_SNIPPET")" || die "the opening /proc/meminfo read failed" 1
  pair_s="$(mem_pair "$mem_s" start)"
  printf '%s\n' "$mem_s" > "$RAW/gate6-$TAG-meminfo-start.txt"
  met_s="$(host_read "$METRICS_SNIPPET")" || true
  [ -n "$met_s" ] || die "the opening /metrics read came back empty on $HOST — if :8000/metrics is not exposed on the host, take it the container route used in spark/reports/hd494-rest-floor/RESULTS.md §4 and say so in the report." 1
  printf '%s\n' "$met_s" > "$RAW/gate6-$TAG-metrics-start.txt"

  # The clock trace spans BOTH legs: one sampler, started before the baseline and stopped after the
  # arm, so the window the pairing proof describes is the window that was measured. It is a RECORD,
  # not a timed leg — no tok/s, TTFT or ITL is computed anywhere in this file.
  trace_csv="$RAW/gate6-$TAG-clocks.csv"
  host_read "${CLOCKS_SNIPPET//@WINDOW@/$WINDOW}" > "$trace_csv" 2> "$RAW/gate6-$TAG-clocks.err" &
  TRACE_PID=$!
  # Wait for the sampler's FIRST row before the first request goes out: a sampler that dies at once
  # (no nvidia-smi, refused flag) must fail BEFORE the baseline spends its minutes. `kill -0` loses
  # that race, because a fast sampler is already reaped — the FILE is the signal.
  ready=0
  for ready_i in 1 2 3 4 5 6 7 8 9 10; do
    if [ "$(awk 'NR > 1' "$trace_csv" 2>/dev/null | grep -c . || true)" -ge 1 ]; then ready=1; break; fi
    sleep 1
  done
  [ "$ready" = 1 ] || die "the clock sampler produced no row at all, so there is no trace to take (far-side stderr: $RAW/gate6-$TAG-clocks.err)" 1

  argv="$(host_read "${ARGV_SNIPPET//@CONTAINER@/$CONTAINER}" || true)"
  printf '%s\n' "$argv" | scrub_argv > "$RAW/gate6-$TAG-engine-start.txt"
  conf_b="$(engine_conf "$argv")"
  TS_BASELINE="$(date -u +%FT%TZ)"

  # --- leg 1: the BASELINE, at the budget, in THIS invocation --------------------------------
  if [ "$BATTERY_ONLY" != 1 ]; then
    run_leg baseline "$BASELINE_LABEL"
  else
    printf '>>> leg baseline: SKIPPED on request (--battery-only). Nothing that follows is a result.\n'
  fi
  TS_BASELINE_END="$(date -u +%FT%TZ)"

  # --- leg 2: the battery, at the SAME budget, guarded by what leg 1 just did ----------------
  TS_ARM="$(date -u +%FT%TZ)"
  if ! run_leg arm "$ARM_LABEL"; then
    exit 4
  fi
  TS_ARM_END="$(date -u +%FT%TZ)"

  # The engine must be the same instrument for both legs: same boot, same restarts, same argv. A
  # restart or a dial flip in between means the two legs were graded on two different engines.
  state="$(host_read "${STATE_SNIPPET//@CONTAINER@/$CONTAINER}" 2>/dev/null || echo unknown)"
  boot_a="$(printf '%s' "$state" | cut -d' ' -f2-)"
  argv="$(host_read "${ARGV_SNIPPET//@CONTAINER@/$CONTAINER}" || true)"
  printf '%s\n' "$argv" | scrub_argv > "$RAW/gate6-$TAG-engine-end.txt"
  conf_a="$(engine_conf "$argv")"
  if [ "$conf_a" != "$conf_b" ] || [ "$boot_a" != "$boot_b" ]; then
    printf 'ERROR: PAIRING REFUSED — the engine moved between the two legs.\n' >&2
    printf '       state at baseline: %s\n' "$boot_b" >&2
    printf '       state at arm:      %s\n' "$boot_a" >&2
    printf '       config at baseline: %s\n' "$conf_b" >&2
    printf '       config at arm:      %s\n' "$conf_a" >&2
    printf '       The same budget on two different engines is still two measurements. Fix the\n' >&2
    printf '       restart or the dial, then re-run the act whole.\n' >&2
    exit 4
  fi

  cleanup
  TRACE_PID=""
  trace_rows="$(awk 'NR > 1' "$trace_csv" 2>/dev/null | grep -c . || true)"
  [ "${trace_rows:-0}" -ge 2 ] || die "the clock trace holds ${trace_rows:-0} sample(s): NO TRACE, NO COMPARISON (docs/hardware-spark.md §GPU clock cap). Far-side stderr: $RAW/gate6-$TAG-clocks.err" 1

  mem_e="$(host_read "$MEMINFO_SNIPPET")" || die "the closing /proc/meminfo read failed" 1
  pair_e="$(mem_pair "$mem_e" end)"
  printf '%s\n' "$mem_e" > "$RAW/gate6-$TAG-meminfo-end.txt"
  met_e="$(host_read "$METRICS_SNIPPET")" || true
  [ -n "$met_e" ] || die "the closing /metrics read came back empty" 1
  printf '%s\n' "$met_e" > "$RAW/gate6-$TAG-metrics-end.txt"

  pre_d="$(awk -v a="$(counter_sum "$met_e" vllm:num_preemptions_total)" -v b="$(counter_sum "$met_s" vllm:num_preemptions_total)" 'BEGIN{printf "%.0f", a-b}')"
  pfx_h_d="$(awk -v a="$(counter_sum "$met_e" vllm:prefix_cache_hits_total)" -v b="$(counter_sum "$met_s" vllm:prefix_cache_hits_total)" 'BEGIN{printf "%.0f", a-b}')"
  pfx_q_d="$(awk -v a="$(counter_sum "$met_e" vllm:prefix_cache_queries_total)" -v b="$(counter_sum "$met_s" vllm:prefix_cache_queries_total)" 'BEGIN{printf "%.0f", a-b}')"
  clk="$(trace_stat "$trace_csv" 2)"
  pow="$(trace_stat "$trace_csv" 3 %.1f)"

  # The budget equality, read off the wire rather than out of this script's own argv.
  b_base="$(budget_in_bodies "$RAW/leg-baseline.bodies.tsv")"
  b_arm="$(budget_in_bodies "$RAW/leg-arm.bodies.tsv")"
  n_base="$(body_lines "$RAW/leg-baseline.bodies.tsv")"
  n_arm="$(body_lines "$RAW/leg-arm.bodies.tsv")"
  ok_base="$(count_at "$RAW/leg-baseline.bodies.tsv" "$MAX_TOKENS")"
  ok_arm="$(count_at "$RAW/leg-arm.bodies.tsv" "$MAX_TOKENS")"
  wire_ok=1
  if [ "$b_base" != "$MAX_TOKENS" ] || [ "$b_arm" != "$MAX_TOKENS" ]; then wire_ok=0; fi
  if [ "${n_base:-0}" -lt 1 ] || [ "${n_arm:-0}" -lt 1 ]; then wire_ok=0; fi
  if [ "${ok_base:-0}" != "${n_base:-0}" ] || [ "${ok_arm:-0}" != "${n_arm:-0}" ]; then wire_ok=0; fi

  printf '>>> pairing: max_tokens  baseline=%s  arm=%s  ->  %s\n' "$b_base" "$b_arm" \
    "$([ "$b_base" = "$b_arm" ] && [ "$b_base" = "$MAX_TOKENS" ] && printf 'EQUAL (%s, both legs)' "$MAX_TOKENS" || printf 'MISMATCH')"
  printf '>>> pairing: engine %s on %s — %s, argv identical across both legs\n' "$CONTAINER" "$HOST" "$boot_b"
  printf '>>> pairing: template/thinking: %s\n' "$conf_b"
  printf '>>> pairing: baseline at %s .. %s · arm at %s .. %s · client %s\n' \
    "$TS_BASELINE" "$TS_BASELINE_END" "$TS_ARM" "$TS_ARM_END" "$CLIENT"
  printf '>>> window:  clocks.sm %s MHz over %s rows (-l 1) · power %s W · preemptions +%s · prefix +%s hits / +%s queries\n' \
    "$clk" "$trace_rows" "$pow" "$pre_d" "$pfx_h_d" "$pfx_q_d"
  printf '>>> usable (MemAvailable − CmaFree): %s -> %s GiB\n' \
    "$(printf '%s' "$pair_s" | awk '{print $3}')" "$(printf '%s' "$pair_e" | awk '{print $3}')"

  if [ "$wire_ok" != 1 ]; then
    printf 'ERROR: PAIRING REFUSED — the budgets on the wire are not the one this act promised.\n' >&2
    printf '       baseline: %s of %s request bodies carry %s (observed: %s)\n' "${ok_base:-0}" "$n_base" "$MAX_TOKENS" "$b_base" >&2
    printf '       arm:      %s of %s request bodies carry %s (observed: %s)\n' "${ok_arm:-0}" "$n_arm" "$MAX_TOKENS" "$b_arm" >&2
    printf '       A battery that ignores --max-tokens is a changed comparison basis, not a run.\n' >&2
    printf '       Nothing here may be certified from this attempt; the raw is kept for the diagnosis.\n' >&2
    exit 4
  fi

  write_pairing "$clk" "$pow" "$trace_rows" "$pre_d" "$pfx_h_d" "$pfx_q_d" "$pair_s" "$pair_e" "$b_base"
  printf '>>> verdict: the two legs were graded at the SAME budget on the SAME engine — the pairing holds.\n'
  printf '>>> evidence: %s\n>>>      raw:  %s\n' "$OUT/pairing-$TAG.md" "$RAW"
}

write_pairing() {
  local clk="$1" pow="$2" rows="$3" pre="$4" pfxh="$5" pfxq="$6" ps="$7" pe="$8" budget="$9"
  {
    printf '# gate 6 paired run — attempt %s\n\n' "$TAG"
    printf '**AUTHORED BY THE DRIVER — this is one attempt'"'"'s leg record, not the certificate.**\n'
    printf 'The proposed `fast.certified_evidence` rewrite is in [`README.md`](README.md) beside this\n'
    printf 'file; this file only records what one invocation measured.\n\n'
    printf '| pairing term | baseline leg | battery leg |\n|---|---|---|\n'
    printf '| label | `%s` | `%s` |\n' "$BASELINE_LABEL" "$ARM_LABEL"
    printf '| max_tokens, read back off the request bodies | %s | %s |\n' "$budget" "$budget"
    printf '| started / ended (UTC) | %s / %s | %s / %s |\n' "$TS_BASELINE" "$TS_BASELINE_END" "$TS_ARM" "$TS_ARM_END"
    printf '| captures | [`leg-baseline/`](raw/%s/leg-baseline/) | [`leg-arm/`](raw/%s/leg-arm/) |\n' "$TAG" "$TAG"
    printf '\nEngine (read at both ends; a difference between them fails the run, so this line is\n'
    printf 'earned, not typed): `%s` on `%s` — %s\n\n' "$CONTAINER" "$HOST" "$boot_b"
    printf 'Template / thinking / pool, out of the engine argv (never the bearer): %s\n\n' "$conf_b"
    printf 'Seat stamp: `%s` — Rule 0 asks the reader to check that this names an externally-served session.\n\n' "$CLIENT"
    printf '## Window\n\n'
    printf '· `clocks.sm` min/median/max %s MHz over %s rows at `-l 1` · power %s W\n' "$clk" "$rows" "$pow"
    printf '· `usable = MemAvailable − CmaFree` %s -> %s GiB (raw at both ends)\n' \
      "$(printf '%s' "$ps" | awk '{print $3}')" "$(printf '%s' "$pe" | awk '{print $3}')"
    printf '· preemptions +%s · prefix cache +%s hits / +%s queries\n\n' "$pre" "$pfxh" "$pfxq"
    printf '## Raw\n\n'
    printf '· request bodies per leg: `raw/%s/leg-baseline.bodies.tsv`, `raw/%s/leg-arm.bodies.tsv`\n' "$TAG" "$TAG"
    printf '· battery stdout per leg: `raw/%s/leg-baseline.log`, `raw/%s/leg-arm.log`\n' "$TAG" "$TAG"
    printf '· baseline stamp: `raw/%s/leg-baseline.stamp` — the token the guard refused to run without\n' "$TAG"
    printf '· engine argv, meminfo and /metrics at both ends, the clock CSV: `raw/%s/`\n' "$TAG"
  } > "$OUT/pairing-$TAG.md"
}

# The exact commands an operator would run, printed and touched nowhere. This is the dry-run half
# of the same guarantee: two legs, one budget, and the second line cannot stand on its own.
run_dry() {
  local raw
  raw="$OUT/raw/<UTC tag>"
  printf '# 1. the BASELINE leg — the battery under its reference label, at the budget\n'
  printf 'BENCH_DIR=%s/leg-baseline ACCURACY_GATE_BODY_LOG=%s/leg-baseline.bodies.tsv VLLM_URL=%s \\\n' "$raw" "$raw" "$URL"
  printf '  bash %s %s --max-tokens %s\n\n' "$GATE" "$BASELINE_LABEL" "$MAX_TOKENS"
  printf '# 2. the BATTERY leg — same budget, same engine, same invocation. Run alone, this half is\n'
  printf '#    what gate6-couple.sh refuses with exit 4 (PAIRING REFUSED).\n'
  printf 'BENCH_DIR=%s/leg-arm ACCURACY_GATE_BODY_LOG=%s/leg-arm.bodies.tsv VLLM_URL=%s \\\n' "$raw" "$raw" "$URL"
  printf '  bash %s %s --max-tokens %s\n\n' "$GATE" "${ARM_LABEL:-gate6-arm-<UTC tag>}" "$MAX_TOKENS"
  printf '# The read-only legs this act wraps around those two (all via `ssh %s`):\n' "$HOST"
  printf '  %s\n  %s\n  %s\n  %s\n  %s\n' \
    "${STATE_SNIPPET//@CONTAINER@/$CONTAINER}" "${ARGV_SNIPPET//@CONTAINER@/$CONTAINER}" \
    "$MEMINFO_SNIPPET" "$METRICS_SNIPPET" "${CLOCKS_SNIPPET//@WINDOW@/$WINDOW}"
  printf '\n# What the act leaves behind: raw/ for both legs under %s, one pairing-<tag>.md per\n# attempt, and NOTHING else — never README.md, never a profile, never certified_evidence.\n' "$OUT"
}

# ---------------------------------------------------------------------------
# --self-test — fixtures only. Nothing here sshes, nothing reads the vault, nothing reaches an
# engine: on a spark-served seat that is the entire point, so the Rule 0 refusal, the pairing
# guard and the read-only contract are PROVEN rather than asserted. The real accuracy-gate.sh is
# driven (GATE6_GATE only points elsewhere for the one mutation arm), so what is tested is the
# command line the act actually uses.
# ---------------------------------------------------------------------------
run_self_test() {
  local t fails=0 rc out stub snap_a snap_b d1 d2 n cmdlog curllog
  t="$(mktemp -d)"
  local self="$SELF_DIR/$SELF_NAME"
  mkdir -p "$t/bin" "$t/logs" "$t/repo/IaC/ansible" "$t/repo/docs" "$t/repo/spark/reports"
  : > "$t/repo/docs/index.md"
  printf 'certified_evidence: "do not touch me from a script"\n' > "$t/repo/IaC/ansible/spark.yml"
  cmdlog="$t/commands.log"; : > "$cmdlog"
  curllog="$t/curl.log";    : > "$curllog"

  # One fake box. It answers a READ and fails loud on anything else, so a new kind of host
  # interaction cannot slip through the fixture dressed up as "probably a read".
  cat > "$t/bin/fake-host" <<'FIX'
#!/usr/bin/env bash
cmd="$(cat)"
printf '%s\n' "$cmd" >> "${FAKE_LOG:?}"
case "$cmd" in
  *'.State.Running'*)
    # Counts the state reads so one arm can flip the engine UNDER the run (FAKE_RESTART_AFTER).
    c=0
    [ -n "${FAKE_COUNT:-}" ] && [ -e "${FAKE_COUNT:-}" ] && c="$(cat "$FAKE_COUNT")"
    [ -n "${FAKE_COUNT:-}" ] && printf '%s' "$((c + 1))" > "$FAKE_COUNT"
    r=0
    if [ -n "${FAKE_RESTART_AFTER:-}" ] && [ "$c" -ge "$FAKE_RESTART_AFTER" ]; then r=1; fi
    printf '%s\n' "true ${FAKE_BOOT:-2026-10-22T09:00:00Z} restarts=${r}" ;;
  *'.Config.Cmd'*)
    printf '%s\n' "${FAKE_ARGV:---model /model --reasoning-parser qwen3 --kv-cache-memory-bytes 20000000000 --max-num-seqs 8 --max-model-len 262144 --api-key REDACTED-IN-FIXTURE --speculative-config {\"method\":\"mtp\"}}" ;;
  *nvidia-smi*)
    printf 'timestamp, clocks.current.sm [MHz], power.draw [W], temperature.gpu\n'
    printf '20261022090000.000, 2401 MHz, 31.2 W, 58\n'
    printf '20261022090001.000, 2398 MHz, 33.0 W, 59\n'
    printf '20261022090002.000, 2405 MHz, 30.1 W, 58\n' ;;
  */proc/meminfo*)
    printf 'MemTotal:       127532360 kB\nMemAvailable:   16900000 kB\nCmaFree:            130000 kB\n' ;;
  */metrics*)
    printf 'vllm:num_preemptions_total 173\nvllm:prefix_cache_hits_total{model_name="m"} 100\nvllm:prefix_cache_queries_total{model_name="m"} 250\nvllm:spec_decode_num_accepted_tokens_total 900\nvllm:spec_decode_num_draft_tokens_total 2000\n' ;;
  *) printf 'fake-host: unhandled command: %s\n' "$cmd" >&2; exit 9 ;;
esac
FIX
  chmod +x "$t/bin/fake-host"

  # The battery's HTTP transport, kept so the driver can read the budget back off the wire exactly
  # as it does against a live engine.
  cat > "$t/bin/fake-curl" <<'FIX'
#!/usr/bin/env bash
body="" out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d) body="$2"; shift ;;
    -o) out="$2"; shift ;;
  esac
  shift
done
[ -n "$out" ] || { echo "fake-curl: no -o target" >&2; exit 22; }
printf '%s\n' "$body" >> "${FAKE_CURL_LOG:?}"
printf '%s\n' '{"choices":[{"message":{"content":"fixture-answer"}}],"usage":{"completion_tokens":1}}' > "$out"
FIX
  chmod +x "$t/bin/fake-curl"

  # A battery that IGNORES --max-tokens — the mutation that proves the wire check has teeth. It
  # honours the real file contract (BENCH_DIR, label, body log) and always asks for 1024.
  stub="$t/bin/stub-gate"
  cat > "$stub" <<'FIX'
#!/usr/bin/env bash
set -euo pipefail
label="${1:?label}"; shift || true
dir="$BENCH_DIR/accuracy/$label"; mkdir -p "$dir"
: > "${ACCURACY_GATE_BODY_LOG:-/dev/null}"
for key in code-fib json-extract logic; do
  printf '%s\n' '{"choices":[{"message":{"content":"stub"}}]}' > "$dir/$key.json"
  printf '%s\n' 'stub' > "$dir/$key.out"
  if [ -n "${ACCURACY_GATE_BODY_LOG:-}" ]; then
    printf '%s\t{"model":"m","messages":[],"max_tokens":1024,"temperature":0}\n' "$key" >> "$ACCURACY_GATE_BODY_LOG"
  fi
done
FIX
  chmod +x "$stub"

  ok()  { printf '  ok:   %s\n' "$1"; }
  bad() { printf '  FAIL: %s\n' "$1"; fails=$((fails + 1)); }
  want() { if printf '%s\n' "$out" | grep -qF -- "$1"; then ok "$2"; else bad "$2 (wanted \"$1\": $(printf '%s' "$out" | tail -3))"; fi; }

  # Drive the real script against the fixture repo. REPO is honoured by scripts/lib/repo-root.sh,
  # the same override the testdata fixtures use, so the evidence dir lands inside the sandbox.
  drive() {
    out="$(FAKE_LOG="$cmdlog" FAKE_CURL_LOG="$curllog" GATE6_SSH_CMD="$t/bin/fake-host" \
      GATE6_CURL_CMD="$t/bin/fake-curl" GATE6_LOG_DIR="$t/logs" REPO="$t/repo" \
      PI_PROVIDER=other PI_MODEL=other/model-not-spark \
      bash "$self" "$@" 2>&1)" && rc=0 || rc=$?
  }

  echo "case (a): a spark-served session is refused, naming Rule 0, before anything is read"
  out="$(PI_PROVIDER=spark PI_MODEL=spark/qwen3.8-flash-next REPO="$t/repo" GATE6_LOG_DIR="$t/logs" \
         GATE6_SSH_CMD="$t/bin/fake-host" bash "$self" 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 3 ] && ok "exits 3 under PI_PROVIDER=spark" || bad "spark-served rc=$rc, want 3"
  want "Rule 0" "the refusal names Rule 0"
  [ "$(wc -l < "$cmdlog")" -eq 0 ] && ok "no host command was sent" || bad "the refusal came after a host read"
  [ "$(find "$t/logs" -name 'gate6-*.log' | wc -l)" -eq 0 ] \
    && ok "no attempt log was opened either" || bad "the refusal still opened an attempt log"
  [ "$(find "$t/repo/spark/reports" -maxdepth 1 -name 'hd489-tail-gate6-*' | wc -l)" -eq 0 ] \
    && ok "no evidence dir was created" || bad "the refusal still created an evidence dir"

  echo "case (b): the battery at 16384 without a baseline of its own, in this invocation, is refused"
  : > "$cmdlog"; : > "$curllog"
  drive --battery-only --out "$t/repo/spark/reports/ev-b"
  [ "$rc" = 4 ] && ok "--battery-only exits 4" || bad "--battery-only gave rc=$rc, want 4"
  want "PAIRING REFUSED" "the refusal names the pairing"
  [ "$(wc -l < "$curllog")" -eq 0 ] && ok "no battery request reached the transport" \
    || bad "a battery request was sent anyway"
  [ "$(find "$t/repo/spark/reports/ev-b" -name 'pairing-*.md' | wc -l)" -eq 0 ] \
    && ok "no verdict file was written for the refused run" || bad "the refused run still wrote a verdict"
  # The same guard, reached from the other side: a battery that does not honour the flag.
  : > "$cmdlog"; : > "$curllog"
  out="$(FAKE_LOG="$cmdlog" FAKE_CURL_LOG="$curllog" GATE6_SSH_CMD="$t/bin/fake-host" \
    GATE6_GATE="$stub" GATE6_LOG_DIR="$t/logs" REPO="$t/repo" \
    PI_PROVIDER=other PI_MODEL=other/model-not-spark bash "$self" --out "$t/repo/spark/reports/ev-b2" 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 4 ] && ok "a battery that ignores --max-tokens exits 4" || bad "an ignoring battery gave rc=$rc, want 4"
  want "not the one this act promised" "the refusal says the wire budget is not the promised one"
  [ "$(cat "$t"/repo/spark/reports/ev-b2/raw/*/leg-*.bodies.tsv | cut -f2- | jq -r '.max_tokens' | sort -u)" = "1024" ] \
    && ok "the mutation leg really fired at 1024 only — the guard refused a real mismatch, not a typo" \
    || bad "the mutation leg's bodies are not the 1024-only set the stub produces"

  echo "case (c): the paired run passes and prints the two budgets EQUAL"
  : > "$cmdlog"; : > "$curllog"
  drive --out "$t/repo/spark/reports/ev-c"
  [ "$rc" = 0 ] && ok "the paired fixture run completes" || bad "paired run rc=$rc: $(printf '%s' "$out" | tail -4)"
  want "->  EQUAL (16384, both legs)" "the pairing proof prints the two budgets EQUAL"
  n="$(cat "$t"/repo/spark/reports/ev-c/raw/*/leg-*.bodies.tsv | cut -f2- | jq -r '.max_tokens' | grep -c '^16384$' || true)"
  [ "$n" -eq 20 ] && ok "all 20 request bodies (2 legs x 10 items) carried 16384" \
    || bad "$n/20 request bodies carried 16384"
  want "engine vllm-qwen-spark on spark" "the engine identity is printed once, for both legs"
  want "reasoning-parser qwen3" "the thinking state is printed"
  want "baseline at " "both timestamps are printed"
  want "the pairing holds" "the verdict prints that the pairing holds"

  echo "case (d): the evidence dir gets its raw, and a retry does not truncate the first attempt"
  d1="$t/repo/spark/reports/ev-d"
  mkdir -p "$d1"
  printf 'the authored README, owed by a session\n' > "$d1/README.md"
  snap_a="$(cd "$t/repo/IaC" && find . -type f -exec md5sum {} + | sort)"
  drive --out "$d1"
  [ "$rc" = 0 ] && ok "first attempt completes" || bad "attempt 1 rc=$rc: $(printf '%s' "$out" | tail -4)"
  n="$(find "$d1/raw" -name '*.json' | wc -l)"
  [ "$n" -eq 20 ] && ok "the raw for both legs is in the evidence dir (20 responses)" \
    || bad "$n responses under $d1/raw, want 20"
  [ "$(find "$d1/raw" -name '*.bodies.tsv' | wc -l)" -eq 2 ] \
    && ok "both legs' request bodies are there — the pairing is re-checkable after the fact" \
    || bad "the request bodies are missing"
  first_raw="$(find "$d1/raw" -mindepth 1 -maxdepth 1 -type d | sort | head -1)"
  cp -r "$first_raw" "$t/attempt1.copy"
  printf 'the authored README, owed by a session\n' > "$d1/README.md"   # idempotence: it must not change
  sleep 1
  drive --out "$d1"
  [ "$rc" = 0 ] && ok "the retry completes" || bad "retry rc=$rc: $(printf '%s' "$out" | tail -4)"
  want "It is NOT reused" "the retry names the earlier baseline it refused to reuse"
  second_raw="$(find "$d1/raw" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)"
  [ "$first_raw" != "$second_raw" ] \
    && ok "two attempts wrote two raw trees ($(basename "$first_raw"), $(basename "$second_raw"))" \
    || bad "the retry wrote over the first attempt's tree"
  if diff -r "$t/attempt1.copy" "$first_raw" >/dev/null 2>&1; then ok "attempt 1's raw is byte-for-byte intact"
  else bad "attempt 1's raw was modified by the retry"; fi
  [ "$(find "$d1" -name 'pairing-*.md' | wc -l)" -eq 2 ] \
    && ok "each attempt kept its own pairing file" || bad "a pairing file was overwritten"
  [ "$(find "$t/repo/spark/reports/ev-d" -name README.md -exec md5sum {} + | awk '{print $1}')" = \
        "$(printf 'the authored README, owed by a session\n' | md5sum | awk '{print $1}')" ] \
    && ok "README.md was left alone — the driver never writes the certificate's home" \
    || bad "the driver wrote README.md"
  snap_b="$(cd "$t/repo/IaC" && find . -type f -exec md5sum {} + | sort)"
  [ "$snap_a" = "$snap_b" ] && ok "nothing outside the evidence dir changed, IaC least of all" \
    || bad "a file outside the evidence dir was modified"
  [ "$(grep -cE 'docker (restart|stop|rm|kill)|systemctl|reboot|shutdown|ansible|drop_caches|sed -i|certified_evidence' "$cmdlog")" -eq 0 ] \
    && ok "no mutate verb reached the box in $(wc -l < "$cmdlog") command(s)" \
    || bad "a mutate verb reached the box: $(grep -nE 'docker (restart|stop|rm|kill)|systemctl|reboot|shutdown|ansible|drop_caches|sed -i|certified_evidence' "$cmdlog" | head -2)"
  for need in nvidia-smi /proc/meminfo /metrics docker; do
    grep -q -- "$need" "$cmdlog" && ok "the $need read was taken" || bad "the $need read never reached the box"
  done
  [ "$(grep -rl 'REDACTED-IN-FIXTURE' "$d1" 2>/dev/null | wc -l)" -eq 0 ] \
    && ok "no file in the evidence dir carries the engine's bearer shape" \
    || bad "a raw capture in the evidence dir holds a bearer ($(grep -rl 'REDACTED-IN-FIXTURE' "$d1" | head -1))"

  echo "case (e): --dry-run prints the operator's commands and touches nothing"
  : > "$cmdlog"; : > "$curllog"
  d2="$t/repo/spark/reports/ev-e"
  drive --dry-run --out "$d2"
  [ "$rc" = 0 ] && ok "--dry-run exits 0" || bad "--dry-run rc=$rc"
  want "accuracy-gate.sh B1 --max-tokens 16384" "the baseline command is printed verbatim"
  want "gate6-arm-<UTC tag> --max-tokens 16384" "the battery command is printed verbatim"
  want "refuses with exit 4" "the print says which half cannot stand alone"
  [ "$(wc -l < "$cmdlog")" -eq 0 ] && ok "no host command was sent" || bad "--dry-run still read the box"
  [ "$(wc -l < "$curllog")" -eq 0 ] && ok "no request was sent" || bad "--dry-run still sent a request"
  [ -e "$d2" ] && bad "--dry-run created the evidence dir" || ok "no evidence dir was created"

  echo "case (f): usage errors, refused before anything is read"  : > "$cmdlog"
  drive --max-tokens 0 --out "$t/repo/spark/reports/ev-f"
  [ "$rc" = 2 ] && ok "--max-tokens 0 refused with rc 2" || bad "--max-tokens 0 gave rc=$rc, want 2"
  : > "$cmdlog"
  drive --max-tokens 16k --out "$t/repo/spark/reports/ev-f"
  [ "$rc" = 2 ] && ok "--max-tokens 16k refused with rc 2" || bad "--max-tokens 16k gave rc=$rc, want 2"
  : > "$cmdlog"
  drive --max-tokens
  [ "$rc" = 2 ] && ok "a missing --max-tokens value is refused" || bad "missing value gave rc=$rc, want 2"
  : > "$cmdlog"
  drive --not-a-flag
  [ "$rc" = 2 ] && ok "an unknown flag is refused" || bad "unknown flag gave rc=$rc, want 2"
  [ "$(wc -l < "$cmdlog")" -eq 0 ] && ok "none of them read the box" || bad "a refused call still read the box"

  echo "case (g): an engine that restarts between the two legs is refused (same engine, not just same budget)"
  : > "$cmdlog"
  printf '0' > "$t/count"
  out="$(FAKE_LOG="$cmdlog" FAKE_CURL_LOG="$curllog" GATE6_SSH_CMD="$t/bin/fake-host" \
    GATE6_CURL_CMD="$t/bin/fake-curl" GATE6_LOG_DIR="$t/logs" FAKE_COUNT="$t/count" \
    FAKE_RESTART_AFTER=1 REPO="$t/repo" PI_PROVIDER=other PI_MODEL=other/model-not-spark \
    bash "$self" --out "$t/repo/spark/reports/ev-g" 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 4 ] && ok "a restart between the legs exits 4" || bad "restart-mid-run gave rc=$rc, want 4"
  want "the engine moved between the two legs" "the refusal says the engine, not the budget, is the problem"
  [ "$(find "$t/repo/spark/reports/ev-g" -name 'pairing-*.md' | wc -l)" -eq 0 ] \
    && ok "no verdict file was written for the run whose engine moved" || bad "a verdict was written anyway"

  rm -rf "$t"
  if [ "$fails" = 0 ]; then echo "SELF-TEST OK"; return 0; fi
  printf 'SELF-TEST FAILED: %s assertion(s)\n' "$fails"; return 1
}

if [ "$TEST" = 1 ]; then run_self_test; exit $?; fi
if [ "$DRY" = 1 ]; then run_dry; exit 0; fi

LOG="$(attempt_log)"
printf '>>> attempt log: %s\n' "$LOG"
# pipefail makes the pipeline's status the run's status, so the log never hides a refusal.
run_main 2>&1 | tee -a "$LOG"
