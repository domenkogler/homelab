#!/usr/bin/env bash
# ============================================================================
# metrics-window.sh — HD-380's never-taken read: the prefix-cache hit rate and
# the preemption counter across ONE WORKING DAY, compared against the pre-raise
# numbers in spark/stability-test.md §6.
#
# WHY THIS WAS NEVER RUN, and why the reason was wrong. Every sitting that reached
# this measurement classed it "spark lane ⇒ Rule 0 ⇒ needs an externally-served
# session" and moved on. Rule 0 (spark/llm-profiles/README.md) bars a session whose own
# model is served by spark from PRODUCING A TIMED NUMBER, and the same sentence says what
# stays legal: "Context-capacity reads, `/metrics` counters, logs and `docker inspect`
# are fine; timed numbers are not." The standing rule that gates the whole backlog
# (todo-table.md §C rule 2) bans the same two things and nothing else: a bench, and any
# deliberate recycle of the engine. This is neither. It is five counters and two memory
# fields, read. So this leg needs no external model: Rule 0 bars timed numbers, and this
# takes none — which is why, unlike run-scenario.sh, usable-sampler.sh and
# hd469-baseline.sh, this script carries NO Rule 0 refusal. A refusal here is what cost
# the measurement weeks. Provenance is still recorded: every row carries the stamp
# <hostname>/agent:<PI_MODEL>, the shape run-scenario.sh puts on a leg.
#
# WHAT IT IS NOT. Not run-scenario.sh (no leg, no load, no tok/s, no TTFT), not
# usable-sampler.sh (no prefill inside the window), not vm-window.sh (that answers ONE leg
# from VictoriaMetrics; this answers a DAY from the engine's own socket, because the question
# is a rate over working hours and a 60 s-cold store smears that), not gate7-read.py (that
# reads the watchdog's gpu_top_mib for the growth watch; the same row still owes that half,
# and --report prints the pointer). And it is NOT a results CSV: check_bench_provenance.py
# reads a results CSV's `client` column and calls an `agent:spark/…` stamp a Rule-0 leg, so
# this file's stamp column is named `stamp` — a spark-served READ is the permitted case, and
# naming it `client` would hand a legal window to a gate built for timed legs.
#
# READ-ONLY against the box, by construction: ONE ssh session per sample batch, running
# two greps — `/metrics` through curl, then /proc/meminfo. The route is the on-box :8000 the
# sibling spark instruments already read; if a deployment does not expose it, every counter
# lands as MISSING and --report says so, because guessing a port is how a read becomes a 0. No tunnel, no listener, no
# docker state change, no converge, no render, no restart, and no session held open
# (one short ssh per sample is also what leaves nothing alive when the lane ends).
# --self-test asserts one command per sample and that no mutate verb reaches the transport.
#
# START-UP CARD — the PARENT starts this. A lane may not leave a running process
# (docs/orchestration.md §4, Lane residue), so no lane session runs the first line; the
# instrument, the fixtures and the exit contract are the lane's part, and they are done.
#
#   start   (detached; survives the seat closing). The mkdir is part of the line: the
#           redirect is the first thing to touch that path, and it does not create dirs.
#     mkdir -p /var/tmp/metrics-window
#     nohup bash scripts/bench/spark/metrics-window.sh --duration 9h \
#       >>/var/tmp/metrics-window/start.log 2>&1 & echo "started: $!"
#   poll    (read-only, side-effect-free, any session, any time):
#     bash scripts/bench/spark/metrics-window.sh --status
#   stop:
#     kill "$(cat /var/tmp/metrics-window/sampler.pid)"
#   read the answer:
#     bash scripts/bench/spark/metrics-window.sh --report
#
# Evidence lives OUTSIDE the repo tree by default (/var/tmp/metrics-window), because a
# sampler that writes inside a checkout for a working day leaves an untracked file that
# no gate can see and every gate trips over. --out moves it; when the row closes, the CSV
# and the report move into spark/reports/ beside the verdict.
#
# Usage
#   scripts/bench/spark/metrics-window.sh                      # sample one working day
#   scripts/bench/spark/metrics-window.sh --status             # alive? how many rows?
#   scripts/bench/spark/metrics-window.sh --report             # the read, offline
#   scripts/bench/spark/metrics-window.sh --once               # one sample and exit
#   scripts/bench/spark/metrics-window.sh --self-test          # fixtures, never a host
#
# Flags
#   --host spark             the box whose engine is read (default spark)
#   --interval 60            seconds between samples
#   --duration 9h            sampling length: N, Ns, Nm, Nh, Nd. Default 9h = one working
#                            day, the same window shape gate 7 takes off the watchdog.
#   --out DIR                where window.csv + sampler.pid live (default /var/tmp/metrics-window)
#   --csv FILE               the sample file itself (default <out>/window.csv)
#   --ref-doc PATH           the doc carrying the pre-raise numbers
#                            (default <repo>/spark/stability-test.md)
#   --hit-ref PCT            pre-raise hit rate, if the doc does not carry one
#   --preemptions-ref N      pre-raise preemption count, if the doc does not carry one
#   --since / --until RFC3339 UTC    narrow --report to part of the file
#
# Fixture hooks — what keeps --self-test off the box, which is the entire point on a seat
# whose own model IS the engine being read:
#   MW_SSH_CMD            command that receives each far-side command on stdin (the fixture
#                         transport; the bodies it answers with are built inside run_self_test)
#   MW_OUT / MW_LOG_DIR   where window.csv and metrics-window-<UTC>.log are written
#   MW_FAKE_SSH_FAIL=1    make the transport fail: proves a failed read is recorded as a
#                         FAILED read in the file, never as a reassuring row of zeros
#   MW_FAKE_NO_METRICS=1  answer with meminfo only: the shape of a box that is fine while
#                         :8000/metrics is not answering
#
# Exit: 0 measured · 1 a file is missing, empty or unreadable as columns · 2 usage ·
#       4 a window too thin to judge (zero traffic, or fewer than two usable samples).
#       There is deliberately NO Rule 0 exit code: this instrument produces no timed
#       number, so it has nothing to refuse, and --help says so instead.
# ============================================================================
set -euo pipefail
# Rates land in a CSV column and in a verdict line. Under a UTF-8 locale such as sl_SI
# awk's "%.2f" prints 90,00 — which splits a CSV field and never equals the hand-valued
# fixture it is tested against. The output format is fixed, not the operator's
# environment (same rule as usable-sampler.sh and hd469-baseline.sh).
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root FOUND, never assumed from a depth (CONVENTIONS §6 / lib/repo-root.sh): the
# pre-raise numbers are read out of the repo BY PATH, so a wrong depth reads the reference
# out of the wrong tree — or out of none, which would print NOT COMPARED and be a lie.
_hl_d="$SELF_DIR"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"        # sets REPO; FATAL when no root is found

HOST="spark"
INTERVAL=60
# One working day, stated as hours so the file says what the row asked for. The watchdog's
# gate 7 reads the same window off gpu_top_mib; this is its /metrics twin.
DURATION=32400
OUT="${MW_OUT:-/var/tmp/metrics-window}"
CSV=""
REF_DOC="$REPO/spark/stability-test.md"
HIT_REF=""
PREEMPT_REF=""
SINCE=""; UNTIL=""
SINCE_E=""; UNTIL_E=""                       # the same two as epochs, filled only by --report
MODE=sample                    # sample | report | status | self-test
ONCE=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --status)            MODE=status ;;
    --report)            MODE=report ;;
    --once)              ONCE=1 ;;
    --self-test)         MODE=self-test ;;
    --host)              HOST="${2:?--host needs the box name}"; shift ;;
    --interval)          INTERVAL="${2:?--interval needs seconds}"; shift ;;
    --duration)          DURATION="${2:?--duration needs seconds or <n>h/<n>m/<n>d}"; shift ;;
    --out)               OUT="${2:?--out needs the evidence directory}"; shift ;;
    --csv)               CSV="${2:?--csv needs the sample file}"; shift ;;
    --ref-doc)           REF_DOC="${2:?--ref-doc needs the doc that carries the pre-raise numbers}"; shift ;;
    --hit-ref)           HIT_REF="${2:?--hit-ref needs a percentage}"; shift ;;
    --preemptions-ref)   PREEMPT_REF="${2:?--preemptions-ref needs a count}"; shift ;;
    --since)             SINCE="${2:?--since needs RFC3339 UTC}"; shift ;;
    --until)             UNTIL="${2:?--until needs RFC3339 UTC}"; shift ;;
    -h|--help)           MODE=help ;;
    *)                   die "unknown arg $1 — see --help or the Usage block in the header" 2 ;;
  esac
  shift
done
CSV="${CSV:-$OUT/window.csv}"

usage() {
  # The loud header belongs in --help too: this is the one spark-lane instrument that is
  # legal from a spark-served session, and a reader who finds it by --help must learn that
  # here rather than by reading 60 lines of comment.
  printf '%s\n' \
    "metrics-window.sh — a READ of the engine's counters across one working day." \
    "" \
    "  WHAT IT IS: 5 vLLM counters (preemptions, prefix-cache hits and queries, cached" \
    "  prompt tokens, KV usage) plus MemAvailable and CmaFree, sampled every 60 s into a" \
    "  CSV, and a --report that turns the file into a prefix-cache HIT RATE and a" \
    "  PREEMPTION DELTA compared against the pre-raise numbers in spark/stability-test.md." \
    "" \
    "  WHY A SPARK-SERVED SESSION MAY RUN IT: Rule 0 (spark/llm-profiles/README.md) bars" \
    "  TIMED NUMBERS from a session whose own model spark serves, and names /metrics" \
    "  counter reads as fine from any session; todo-table.md §C rule 2 bans a bench and an" \
    "  engine recycle, and this is neither. So this instrument has no Rule 0 refusal —" \
    "  unlike run-scenario.sh, usable-sampler.sh and hd469-baseline.sh, which drive load" \
    "  through the engine and exit 3. It produces no timed number, no tok/s and no TTFT:" \
    "  a counter read, and the record shows who took it because every row is stamped" \
    "  <hostname>/agent:<PI_MODEL>." \
    "" \
    "  Modes: (default) sample the window · --status · --report · --once · --self-test" \
    "  Start-up, polling and stopping: the START-UP CARD in the header comment."
}
if [ "$MODE" = help ]; then usage; exit 0; fi

case "$INTERVAL" in (*[!0-9]*|'') die "--interval wants whole seconds, got '$INTERVAL'" 2 ;; esac
[ "$INTERVAL" -ge 5 ] || die "--interval $INTERVAL s over a working day is >100 k rows for a question that needs 60 s; the floor is 5" 2

# dur_seconds <9h|45m|2d|32400> — a working day has to be writable as `9h`, because the
# row says "one working day" and a flag that forces the operator to do arithmetic is how a
# 32400 becomes 86400 by accident.
dur_seconds() {
  local v="$1" n unit
  case "$v" in
    (*[!0-9smhdSMHD]*) return 1 ;;
    (*[smhdSMHD]) n="${v%"${v##[!0-9]}"}"; unit="$(printf '%s' "${v##*[0-9]}" | tr 'A-Z' 'a-z')"
                    [ -n "$n" ] || return 1
                    case "$unit" in (s) printf '%s' "$n" ;; (m) printf '%s' "$((n * 60))" ;;
                                    (h) printf '%s' "$((n * 3600))" ;; (d) printf '%s' "$((n * 86400))" ;;
                                    (*) return 1 ;; esac ;;
    (*)             printf '%s' "$v" ;;
  esac
}

# <hostname>/agent:<PI_MODEL> — run-scenario.sh's stamp. Here it is not a Rule 0 test (the
# instrument has nothing to refuse); it is the answer to "who took this read", which the
# row otherwise has to remember.
client_stamp() {
  printf '%s/%s' "${BENCH_CLIENT:-$(hostname -s 2>/dev/null || echo unknown)}" \
    "agent:${PI_MODEL:-none}" | tr -d ','
}

# One log per ATTEMPT, and a retry gets a NEW name: HD-469 lost the only record of a
# failed attempt by reusing its log, and a day-long window that is retried over a failed
# start must not overwrite what it already collected.
attempt_log() {
  local dir="${MW_LOG_DIR:-/tmp}" n=1 path
  mkdir -p "$dir"
  path="$dir/metrics-window-$1.log"
  while [ -e "$path" ]; do
    path="$dir/metrics-window-$1.$n.log"
    n=$((n + 1))
  done
  printf '%s' "$path"
}

# The ONE door to the far side. Everything sent through it is a read, and --self-test
# intercepts it here, so the fixture run exercises the real command strings.
host_read() {
  local cmd="$1"
  if [ -n "${MW_SSH_CMD:-}" ]; then
    printf '%s\n' "$cmd" | $MW_SSH_CMD
  else
    # No -N, no -L, no -D: a forward is a standing path into a production host whose
    # lifetime is the process, not the sample (docs/orchestration.md §4, Lane residue).
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$cmd"
  fi
}

# One sample = ONE far-side command = ONE ssh session. Opening a session per metric would
# be 7 handshakes a minute against a box that is doing real work, and it would let a
# sample straddle two different instants. The marker splits the two reads on the near side.
READ_SNIPPET='curl -s --max-time 10 localhost:8000/metrics | grep -E "^vllm:(num_preemptions_total|prefix_cache_hits_total|prefix_cache_queries_total|prompt_tokens_cached_total|kv_cache_usage_perc)([ {]|$)"; printf "%s\n" "#MEMINFO"; grep -E "^(MemAvailable|CmaFree):" /proc/meminfo'

# COUNTERS: name:awk-mode. `s` sums every series of a counter — a labelled counter carries
# more than one line and picking one reports a fraction of the truth (snapshot-metrics.sh
# learned this as sumget()). `m` is for kv_cache_usage_perc, which is a GAUGE: summing two
# models' usage percentages would print 1.4 and read as 140 % of the pool, so the busiest
# series is the honest single number.
COUNTERS="vllm:num_preemptions_total:s vllm:prefix_cache_hits_total:s vllm:prefix_cache_queries_total:s vllm:prompt_tokens_cached_total:s vllm:kv_cache_usage_perc:m"
# The stamp column is `stamp`, NOT `client`, on purpose: check_bench_provenance.py reads a
# results CSV's `client` column and calls `agent:spark/…` a RULE-0 finding, which is right for
# a timed leg and wrong for this file — a spark-served stamp on a READ is the permitted case.
# Naming the column differently is what stops one instrument's ledger being judged by the
# other instrument's gate.
CSV_HEADER="attempt,epoch,utc,stamp,num_preemptions_total,prefix_cache_hits_total,prefix_cache_queries_total,prompt_tokens_cached_total,kv_cache_usage_perc,mem_available_kib,cma_free_kib,usable_gib,read"

# counter_value <metrics-body> <metric> <s|m> -> a number, or MISSING. NEVER a zero for an
# absent series: a 0 in a preemption column means "the engine preempted nothing", and a
# MISSING means "we did not learn anything". Only the second one is not reassuring.
counter_value() {
  printf '%s\n' "$1" | awk -v m="$2" -v mode="$3" '
    !/^#/ {
      name = $1; sub(/[ \t].*$/, "", name)
      if (index(name, m) == 1) {
        rest = substr(name, length(m) + 1)
        if (rest == "" || substr(rest, 1, 1) == "{") {      # the ([ {]|$) guard, spelled portably
          n++; v = $NF + 0
          if (mode == "m") { if (n == 1 || v > mx) mx = v } else s += v
        }
      }
    }
    END { if (!n) print "MISSING"; else if (mode == "m") printf "%.4f", mx; else printf "%.0f", s }'
}

# mem_value <meminfo-body> <field> — KiB or MISSING. usable = MemAvailable − CmaFree is the
# gauge the watchdog, the alert rules and the bench guard all share: MemAvailable ALONE is
# falsified on GB10, because CMA counts as available and INFLATES as pressure rises.
mem_value() {
  printf '%s\n' "$1" | awk -v k="$2:" '$1 == k { print $2; exit }'
}

# csv_init — header ONLY into a file that does not exist or is empty. A second invocation
# therefore appends to the day it is resuming instead of truncating it, which is the whole
# resumability contract: a window that survived a reboot keeps its rows.
csv_init() {
  mkdir -p "$(dirname "$CSV")"
  if [ -s "$CSV" ]; then
    [ "$(head -1 "$CSV")" = "$CSV_HEADER" ] \
      || die "$CSV holds a different column set — refusing to compute a rate out of columns it cannot name. Header found: $(head -1 "$CSV")" 1
    return 0
  fi
  printf '%s\n' "$CSV_HEADER" > "$CSV"
}

# sample_once <attempt-id> — one ssh session, one appended row. Nothing here truncates.
sample_once() {
  local attempt="$1" out="" metrics mem entry name mode v line avail cma usable read_state=ok
  local miss_n=0 rc=0
  if out="$(host_read "$READ_SNIPPET" 2>/dev/null)"; then :; else rc=$?; fi
  if [ "$rc" != 0 ]; then
    # A failed read is recorded as a FAILED read with MISSING fields, never as a row of
    # zeros: a zero preemption column means "nothing was preempted", and that is a lie the
    # day the ssh is down.
    printf '%s,%s,%s,%s,MISSING,MISSING,MISSING,MISSING,MISSING,MISSING,MISSING,MISSING,ssh-fail\n' \
      "$attempt" "$(date +%s)" "$(date -u +%FT%TZ)" "$(client_stamp)" >> "$CSV"
    return 1
  fi
  metrics="$(printf '%s\n' "$out" | sed -n '1,/#MEMINFO/p' | grep -v '^#MEMINFO$')"
  mem="$(printf '%s\n' "$out" | sed -n '/#MEMINFO/,$p' | grep -v '^#MEMINFO$')"

  line="$attempt,$(date +%s),$(date -u +%FT%TZ),$(client_stamp)"
  for entry in $COUNTERS; do
    name="${entry%:*}"; mode="${entry##*:}"
    v="$(counter_value "$metrics" "$name" "$mode")"
    if [ "$v" = "MISSING" ]; then miss_n=$((miss_n + 1)); fi
    line="$line,$v"
  done

  avail="$(mem_value "$mem" MemAvailable)"
  cma="$(mem_value "$mem" CmaFree)"
  if [ -n "$avail" ] && [ -n "$cma" ]; then
    usable="$(awk -v a="$avail" -v c="$cma" 'BEGIN{printf "%.2f", (a-c)/1048576}')"
  else
    avail="${avail:-MISSING}"; cma="${cma:-MISSING}"; usable="MISSING"
  fi
  # `read` separates the three states a reader must not confuse: ok · no-metrics (:8000 not
  # answering, so every counter is MISSING) · ssh-fail. meminfo MISSING on its own still
  # says ok, because the counters — the question this row asks — arrived.
  if [ "$miss_n" = 5 ]; then read_state="no-metrics"; fi
  printf '%s,%s,%s,%s,%s\n' "$line" "$avail" "$cma" "$usable" "$read_state" >> "$CSV"
  return 0
}

# window_stats <csv> — the window's arithmetic as key=value lines. Counter deltas are
# ACCUMULATED INCREASES, not last-minus-first: the watchdog restarts the engine on CRIT
# (up to 2 per 2 h), and a restart resets the counters to zero, so a naive subtraction
# over a working day would print a negative preemption delta and a hit rate computed from
# a negative denominator. At a reset the value accrued since the restart is counted, which
# is the same rule PromQL's increase() applies.
window_stats() {
  awk -F',' -v since="$SINCE_E" -v until="$UNTIL_E" '
    function isnum(x) { return (x ~ /^-?[0-9]+(\.[0-9]+)?$/) }
    NR == 1 { next }
    {
      if (since != "" && $2 + 0 < since + 0) next
      if (until != "" && $2 + 0 > until + 0) next
      rows++
      if (first_e == "") { first_e = $2; first_u = $3 }
      last_e = $2; last_u = $3
      if (!seen_att[$1]++) na++
      if ($13 != "ok") { failed++; next }
      ok++
      for (i = 5; i <= 8; i++) {
        if (!isnum($i)) { miss[i]++; continue }
        if (i in prev) {
          d = $i + 0 - prev[i]
          if (d < 0) { delta[i] += $i + 0; resets++ } else delta[i] += d
        }
        prev[i] = $i + 0
      }
      if (isnum($9)) { kv_last = $9 + 0; if (!kv_n || $9 + 0 > kv_max) kv_max = $9 + 0; kv_n++ }
      if (isnum($10) && isnum($11)) {
        u = ($10 - $11) / 1048576
        if (!u_n) { u_min = u; u_max = u }
        if (u < u_min) u_min = u
        if (u > u_max) u_max = u
        u_n++
      }
    }
    END {
      printf "rows=%d\nok=%d\nfailed=%d\nresets=%d\nattempts=%d\n", rows + 0, ok + 0, failed + 0, resets + 0, na + 0
      printf "first_epoch=%s\nlast_epoch=%s\nfirst_utc=%s\nlast_utc=%s\n", first_e, last_e, first_u, last_u
      if (first_e != "") printf "span_s=%d\n", last_e - first_e
      printf "d_preempt=%d\nd_hits=%d\nd_queries=%d\nd_cached=%d\n", delta[5] + 0, delta[6] + 0, delta[7] + 0, delta[8] + 0
      printf "missing_preempt=%d\nmissing_hits=%d\nmissing_queries=%d\nmissing_cached=%d\n", miss[5] + 0, miss[6] + 0, miss[7] + 0, miss[8] + 0
      printf "kv_max=%s\nkv_last=%s\n", (kv_n ? sprintf("%.4f", kv_max) : "MISSING"), (kv_n ? sprintf("%.4f", kv_last) : "MISSING")
      printf "usable_min=%s\nusable_max=%s\n", (u_n ? sprintf("%.2f", u_min) : "MISSING"), (u_n ? sprintf("%.2f", u_max) : "MISSING")
    }' "$1"
}

# ref_value <doc> <hit|preempt> — the pre-raise number, read out of the OWNING DOC by
# path. Nothing is baked in here: a reference the doc does not carry is ABSENT, and the
# report then prints NOT COMPARED rather than inventing a baseline.
#
# The two patterns, stated because the reader has to be able to argue with them:
#   hit     a line naming the prefix-cache hit and a percentage on it. Today that is
#           spark/stability-test.md:167 "prefix-cache hit is ~92 %" — the doc's only
#           hit-rate figure. It is quoted WITH ITS PATH AND LINE in the report so nobody
#           mistakes it for a number this script measured.
#   preempt a preemption COUNT: "preemptions: 5", "5 preemptions", "preemptions = 5". A
#           percentage is rejected on purpose: §6's "Preemption under 94 % fill is real"
#           is a sentence about behaviour, and reading 94 out of it as a count would be
#           exactly the silent-fabrication failure this function exists to avoid.
ref_value() {
  local doc="$1" what="$2"
  [ -f "$doc" ] || return 0
  case "$what" in
    hit)
      awk '/prefix[ -]cache hit/ { if (match($0, /[0-9]+(\.[0-9]+)?[ \t]*%/)) { v = substr($0, RSTART, RLENGTH); gsub(/[^0-9.]/, "", v); print v; exit } }' "$doc" ;;
    preempt)
      awk '
        {
          s = $0
          if (match(s, /[Pp]reemptions?[^0-9%]{0,12}[0-9][0-9,]*/)) {
            tail = substr(s, RSTART + RLENGTH)
            if (tail ~ /^[ \t]*%/) next                       # a rate, not a count
            t = substr(s, RSTART, RLENGTH)
            if (match(t, /[0-9][0-9,]*$/)) { n = substr(t, RSTART, RLENGTH); gsub(/,/, "", n); print n + 0; exit }
          }
          if (match(s, /[0-9][0-9,]*[ \t]+preemptions?/)) { n = substr(s, RSTART, RLENGTH); sub(/[ \t].*$/, "", n); gsub(/,/, "", n); print n + 0; exit }
        }' "$doc" ;;
  esac
  return 0
}

ref_line() {   # <doc> <hit|preempt> -> path:line of the match, so the citation is checkable
  local doc="$1" what="$2"
  [ -f "$doc" ] || return 0
  if [ "$what" = hit ]; then
    awk '/prefix[ -]cache hit/ && /[0-9][ \t]*%/ { print FILENAME ":" FNR; exit }' "$doc"
  else
    awk '/[Pp]reemptions?/ { if (match($0, /[0-9][0-9,]*[ \t]*%/) == 0 && match($0, /[Pp]reemptions?[^0-9%]{0,12}[0-9]|[0-9][0-9,]*[ \t]+preemptions?/)) { print FILENAME ":" FNR; exit } }' "$doc"
  fi
}

# banner — the loud header every mode prints before it prints anything else: what this run
# is (a counter read), who is taking it, and why no Rule 0 refusal applies to it.
banner() {
  printf '>>> READ, NOT A LEG: counters and /proc/meminfo only. No timed number, no tok/s, no TTFT,\n'
  printf '>>> no bench, no load, no engine restart. Rule 0 bars TIMED numbers from a spark-served\n'
  printf '>>> session and names a /metrics read as legal from ANY session (spark/llm-profiles/README.md\n'
  printf '>>> Rule 0, todo-table.md §C rule 2) — so this instrument refuses nothing, and this line is\n'
  printf '>>> the record of what was read and by whom: %s on %s\n' "$(client_stamp)" "$HOST"
}

run_sample() {
  local dur start end n=0 fails=0
  dur="$(dur_seconds "$DURATION")" || die "--duration '$DURATION' is not N, Ns, Nm, Nh or Nd" 2
  [ "$dur" -ge "$INTERVAL" ] || die "--duration $dur s is shorter than --interval $INTERVAL s" 2
  mkdir -p "$OUT"
  # One sampler per CSV. Two of them appending to one window would double the rows and
  # quietly halve every rate computed from them, so the second one is refused by name.
  if [ -f "$OUT/sampler.pid" ]; then
    local old; old="$(cat "$OUT/sampler.pid" 2>/dev/null || echo '')"
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
      die "a sampler is already writing $CSV (pid $old). Stop it first: kill $old — see the START-UP CARD." 1
    fi
    printf 'NOTE: a stale pid file named pid %s (not running); replacing it.\n' "${old:-?}"
  fi
  csv_init
  banner
  printf '>>> sampling every %s s for %s s into %s (attempt %s, %s row(s) already in the file)\n' \
    "$INTERVAL" "$dur" "$CSV" "$(date -u +%Y%m%d-%H%M)" "$(( $(wc -l < "$CSV") - 1 ))"
  printf '>>> poll it:   bash %s --status\n>>> stop it:   kill "$(cat %s/sampler.pid)"\n' "$SELF_DIR/$(basename "${BASH_SOURCE[0]}")" "$OUT"
  [ "$ONCE" = 1 ] || printf '%s\n' "$$" > "$OUT/sampler.pid"
  trap 'if [ "$ONCE" != 1 ]; then rm -f "$OUT/sampler.pid"; fi
        printf ">>> stopped on signal after %s sample(s) — the window is still readable: --report\n" "$n"; exit 0' INT TERM
  start="$(date +%s)"; end=$(( start + dur ))
  while :; do
    if ! sample_once "$(date -u +%Y%m%d-%H%M)"; then
      fails=$(( fails + 1 ))
      printf '>>> %s the read failed (running total %s) — recorded as ssh-fail, never as a zero\n' "$(date -u +%FT%TZ)" "$fails"
    fi
    n=$(( n + 1 ))
    if [ "$ONCE" = 1 ]; then break; fi
    if [ "$(date +%s)" -ge "$end" ]; then break; fi
    sleep "$INTERVAL"
  done
  [ "$ONCE" = 1 ] || rm -f "$OUT/sampler.pid"
  printf '>>> %s sample(s) appended, %s failed read(s) · %s\n' "$n" "$fails" "$CSV"
  printf '>>> read it: bash %s --report --csv %s\n' "$SELF_DIR/$(basename "${BASH_SOURCE[0]}")" "$CSV"
}

run_status() {
  banner
  local rows last age pid="" state="not running"
  if [ -f "$OUT/sampler.pid" ]; then pid="$(cat "$OUT/sampler.pid" 2>/dev/null || echo '')"; fi
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then state="RUNNING (pid $pid)"; fi
  printf '>>> sampler: %s · file %s\n' "$state" "$CSV"
  if [ ! -s "$CSV" ]; then printf '>>> no rows yet — the file is empty or absent\n'; return 0; fi
  rows=$(( $(wc -l < "$CSV") - 1 ))
  last="$(tail -1 "$CSV" | cut -d, -f2)"
  case "$last" in (*[!0-9]*|'') printf '>>> %s row(s); the last row carries no epoch, so its age is unknown\n' "$rows"; return 0 ;; esac
  age=$(( $(date +%s) - last ))
  printf '>>> %s row(s) · last sample %s s ago · first %s · last %s\n' \
    "$rows" "$age" "$(sed -n '2p' "$CSV" | cut -d, -f3)" "$(tail -1 "$CSV" | cut -d, -f3)"
  # A row that is older than the interval by more than three intervals says the sampler is
  # gone, and the CSV keeps looking complete to anyone who only counts rows.
  if [ "$age" -gt $(( INTERVAL * 3 )) ]; then
    printf '>>> the last sample is more than %s s old — the sampler is NOT writing, whatever the row count says\n' "$(( INTERVAL * 3 ))"
  fi
  return 0
}

run_report() {
  local s rate tok pre span hours rows ok failed resets d_q d_h d_c
  local miss_p miss_h miss_q miss_c
  [ -f "$CSV" ] || die "no sample file at $CSV — the window was never started. See the START-UP CARD in the header." 1
  [ -s "$CSV" ] || die "$CSV is empty — no sample has been written yet" 1
  SINCE_E=""; UNTIL_E=""
  if [ -n "$SINCE" ]; then SINCE_E="$(date -u -d "$SINCE" +%s 2>/dev/null)" || die "--since '$SINCE' is not a UTC timestamp" 2; fi
  if [ -n "$UNTIL" ]; then UNTIL_E="$(date -u -d "$UNTIL" +%s 2>/dev/null)" || die "--until '$UNTIL' is not a UTC timestamp" 2; fi
  banner
  printf '>>> window file: %s\n' "$CSV"
  s="$(window_stats "$CSV")"
  kv() { printf '%s\n' "$s" | sed -n "s/^$1=//p"; }
  rows="$(kv rows)"; ok="$(kv ok)"; failed="$(kv failed)"; resets="$(kv resets)"
  span="$(kv span_s)"; d_q="$(kv d_queries)"; d_h="$(kv d_hits)"; d_c="$(kv d_cached)"; pre="$(kv d_preempt)"
  miss_p="$(kv missing_preempt)"; miss_h="$(kv missing_hits)"; miss_q="$(kv missing_queries)"; miss_c="$(kv missing_cached)"
  printf '>>> window %s .. %s (%s s, %s row(s): %s usable, %s failed read(s), %s attempt(s))\n' \
    "$(kv first_utc)" "$(kv last_utc)" "$span" "$rows" "$ok" "$failed" "$(kv attempts)"
  if [ "${failed:-0}" != 0 ]; then
    printf '>>> %s row(s) came from a FAILED read and are excluded from every delta below\n' "$failed"
  fi
  if [ "${resets:-0}" != 0 ]; then
    printf '>>> %s counter reset(s) inside the window = the engine restarted; every counter is summed ACROSS the restart, not subtracted through it\n' "$resets"
  fi
  if [ "$(( miss_p + miss_h + miss_q + miss_c ))" != 0 ]; then
    printf '>>> MISSING counters across the usable rows: preemptions %s · hits %s · queries %s · cached %s (of %s rows) — a MISSING counter is never counted as a zero\n' \
      "$miss_p" "$miss_h" "$miss_q" "$miss_c" "$ok"
  fi

  if [ "${ok:-0}" -lt 2 ]; then
    printf '>>> NOT MEASURED: %s usable sample(s). Two are the minimum for a delta, and a rate over one point is arithmetic on nothing.\n' "${ok:-0}"
    return 1
  fi
  # A counter that never arrived is NOT a zero counter. Both views are refused here rather
  # than printed as 0.00 %, because "the cache never hits" and "the engine never answered"
  # are opposite findings and a computed zero cannot tell them apart.
  if [ "${miss_q:-0}" -ge "${ok:-1}" ] || [ "${miss_h:-0}" -ge "${ok:-1}" ]; then
    printf '>>> NOT MEASURED: the prefix-cache counters were MISSING in every usable row — :8000/metrics never answered during this window. There is no hit rate here, and 0 %% would be a fabrication.\n'
    return 1
  fi
  hours="$(awk -v x="${span:-0}" 'BEGIN{printf "%.1f", x/3600}')"
  # A window whose rows all carry the same epoch cannot carry a rate per hour either; every
  # division below says n/a rather than dividing by zero and printing nothing.
  if [ "${span:-0}" -le 0 ]; then
    printf '>>> NOT MEASURED: every row in this window carries the same instant, so no rate over time exists to report.\n'
    return 1
  fi

  if [ "${d_q:-0}" -eq 0 ] && [ "$miss_q" = 0 ]; then
    # Case (e) of the self-test: the honest reading of an all-zero counter window is that
    # NOTHING ASKED THE CACHE ANYTHING. 0 hits / 0 queries is not a 0 % hit rate; a 0 %
    # would say the cache misses, and that is the opposite of what an idle day means.
    printf '>>> ZERO TRAFFIC: prefix_cache_queries_total did not move in this window, so the cache was never asked. The hit rate is NOT MEASURED — it is not 0 %%.\n'
    printf '>>> preemptions over the window: %s. Nothing ran, so nothing could preempt; that is a fact about the window, not about the pool.\n' "$pre"
    printf '>>> verdict: NOT DECIDED — an idle window cannot say whether the 16 GiB pool bought hit rate. Re-run across hours that carry traffic.\n'
    return 4
  fi

  rate="$(awk -v h="$d_h" -v q="$d_q" -v m="$miss_h" -v n="$ok" 'BEGIN{ if (q > 0 && m+0 < n+0) printf "%.2f", 100 * h / q; else printf "MISSING" }')"
  tok="$(awk -v c="$d_c" -v q="$d_q" -v m="$miss_c" -v n="$ok" 'BEGIN{ if (q > 0 && m+0 < n+0) printf "%.2f", 100 * c / q; else printf "MISSING" }')"
  printf '>>> prefix-cache HIT RATE over the window: %s %%  (+%s hits / +%s queries)\n' "$rate" "$d_h" "$d_q"
  printf '>>>   token-weighted view (prompt_tokens_cached/queries): %s %%  (+%s cached tokens)\n' "$tok" "$d_c"
  printf '>>>   the two are the SAME quantity on this build (prompt_tokens_cached_total == prefix_cache_hits_total, the identity vm-tokens.sh reads its prices off), so a gap between them is a finding about the counters, not about the cache\n'
  printf '>>> preemptions over the window: +%s  (%s per hour over %s h)\n' "$pre" \
    "$(awk -v p="$pre" -v x="$span" 'BEGIN{ if (x > 0) printf "%.3f", p / (x/3600); else printf "n/a" }')" "$hours"
  printf '>>> kv_cache_usage_perc: max %s · last %s (0..1 of the pool) · usable = MemAvailable − CmaFree: min %s · max %s GiB\n' \
    "$(kv kv_max)" "$(kv kv_last)" "$(kv usable_min)" "$(kv usable_max)"

  report_comparison "$rate" "$pre"

  printf '>>> still owed by this row, and NOT answerable from this file: the gpu_top_mib growth watch (>2 GiB/h under traffic that does not return at idle) — read it with scripts/bench/spark/gate7-read.py over the watchdog samples.\n'
  return 0
}

# report_comparison <window hit rate %> <window preemption delta> — the pre-raise numbers
# are read FROM THE DOC BY PATH, and a number the doc does not carry prints NOT COMPARED.
report_comparison() {
  local rate="$1" pre="$2" hit_src pre_ref src delta word
  hit_src="$(ref_value "$REF_DOC" hit)"; src="$(ref_line "$REF_DOC" hit)"
  pre_ref="$(ref_value "$REF_DOC" preempt)"
  if [ -n "$HIT_REF" ]; then hit_src="$HIT_REF"; src="operator-supplied via --hit-ref"; fi
  if [ -n "$PREEMPT_REF" ]; then pre_ref="$PREEMPT_REF"; src="operator-supplied via --preemptions-ref"; fi
  printf '>>> comparison against the pre-raise numbers (%s, read by path at report time):\n' "${REF_DOC#"$REPO"/}"
  if [ "$rate" = "MISSING" ]; then
    printf '>>>   hit rate     NOT MEASURED — nothing to compare, so nothing is compared\n'
  elif [ -n "$hit_src" ]; then
    delta="$(awk -v a="$rate" -v b="$hit_src" 'BEGIN{printf "%.2f", a - b}')"
    word="$(awk -v a="$rate" -v b="$hit_src" 'BEGIN{ print (a+0 > b+0) ? "improved" : ((a+0 < b+0) ? "did NOT improve" : "level") }')"
    printf '>>>   hit rate     %s %%  vs  pre-raise %s %%  →  %+.2f points %s   (ref %s)\n' \
      "$rate" "$hit_src" "$delta" "$word" "$src"
    printf '>>>   VERDICT: the row'"'"'s own test is "did the hit rate improve?" — across this window it is %+.2f points against the number the doc carries (%s). Whether that pays for the 7.8 GiB of usable the pool took is the owner'"'"'s call, not this line'"'"'s.\n' "$delta" "$word"
  else
    printf '>>>   hit rate     %s %%  vs  pre-raise NOT COMPARED — %s carries no parseable hit-rate figure. Pass --hit-ref PCT (it will be printed as operator-supplied) or --ref-doc <path>.\n' "$rate" "${REF_DOC##*/}"
    printf '>>>   VERDICT: NOT DECIDED — the comparison the row asks for needs the pre-raise number, and this script will not guess one.\n'
  fi
  if [ -n "$pre_ref" ]; then
    word="$(awk -v a="$pre" -v b="$pre_ref" 'BEGIN{ print (a+0 > b+0) ? "HIGHER" : ((a+0 < b+0) ? "LOWER" : "LEVEL") }')"
    printf '>>>   preemptions  +%s vs pre-raise %s  →  %s\n' "$pre" "$pre_ref" "$word"
  else
    printf '>>>   preemptions  +%s vs pre-raise NOT COMPARED — %s describes the pre-raise preemption behaviour in prose and carries no COUNT (§6, "Preemption under 94 %% fill is real and it is slow, not fatal"). The 8.2-era counts live in the reports under spark/reports/; pass --preemptions-ref N to pin the comparison and it will be printed as operator-supplied.\n' "$pre" "${REF_DOC##*/}"
  fi
}

# ---------------------------------------------------------------------------
# --self-test — fixtures only. Nothing here sshes, nothing reaches an engine,
# nothing reads a vault: on a spark-served seat that is the entire point, and it is
# what makes the instrument's two claims CHECKABLE rather than asserted — that a read
# is all it does, and that it can be run from the very session Rule 0 confines.
#
# The fixture pair is HAND-VALUED (a test that recomputes its own expectation cannot
# fail), and every case below is one of the five the row names:
#   (a) the parser: five counters out of a fixture /metrics body, a missing one MISSING
#   (b) the hit-rate arithmetic against that hand-valued pair
#   (c) append-not-truncate across two attempts, and a second sampler refused
#   (d) --report prints the comparison, and NOT COMPARED when the doc has no numbers
#   (e) a zero-counter window is ZERO TRAFFIC, never a 0 % hit rate
# plus the contract cases: read-only verbs, one ssh per sample, the stamp, and no
# Rule 0 refusal under PI_PROVIDER=spark.
# ---------------------------------------------------------------------------
run_self_test() {
  local t fails=0 out rc p1 p2 alive
  t="$(mktemp -d)"
  local self="$SELF_DIR/$(basename "${BASH_SOURCE[0]}")"
  mkdir -p "$t/bin" "$t/out" "$t/logs"
  : > "$t/commands.log"

  # The fixture /metrics body: three series for the labelled counters (summing every
  # series is the only correct read), a _created neighbour that must NOT be summed in,
  # and a gauge whose two series must be read as the busiest one, never as their sum.
  cat > "$t/metrics-full.txt" <<'FIX'
# HELP vllm:num_preemptions_total Cumulative number of preemption from the engine.
# TYPE vllm:num_preemptions_total counter
vllm:num_preemptions_total 173
vllm:prefix_cache_hits_total{model_name="spark/qwen3.8-flash-next"} 60
vllm:prefix_cache_hits_total{model_name="other"} 40
vllm:prefix_cache_hits_created{model_name="other"} 99999
vllm:prefix_cache_queries_total{model_name="spark/qwen3.8-flash-next"} 150
vllm:prefix_cache_queries_total{model_name="other"} 100
vllm:prompt_tokens_cached_total{model_name="spark/qwen3.8-flash-next"} 100
vllm:kv_cache_usage_perc{model_name="spark/qwen3.8-flash-next"} 0.6
vllm:kv_cache_usage_perc{model_name="other"} 0.42
FIX
  # The same body with prompt_tokens_cached_total absent: the parser must say MISSING.
  grep -v 'prompt_tokens_cached_total' "$t/metrics-full.txt" > "$t/metrics-gap.txt"
  cat > "$t/meminfo.txt" <<'FIX'
MemTotal:       127532360 kB
MemFree:          800000 kB
MemAvailable:   16900000 kB
CmaFree:            130000 kB
FIX

  # The reference doc, hand-valued so the comparison has a hand-checkable expectation.
  cat > "$t/ref-with.txt" <<'FIX'
## §6 — "How much more KV can I afford?"
* Never reuse a prompt: prefix-cache hit is ~75 %, so a repeated prompt prefills nothing.
* Preemption under load: preemptions: 17 across the run, all of them slow, none fatal.
FIX
  printf '## §6 — how much more KV\n\nNothing labelled here at all.\n' > "$t/ref-without.txt"

  # Hand-valued window, two samples an hour apart (the arithmetic case, not a sampler run):
  #   preemptions 173 → 176        = +3
  #   hits        100 → 900        = +800
  #   queries     250 → 1250       = +1000   ⇒ hit rate 80.00 %
  #   cached      100 → 900        = +800    ⇒ token view 80.00 %, the same quantity
  #   usable (16900000−130000)/1048576 = 15.99 GiB at the first sample,
  #          (16800000−120000)/1048576 = 15.91 GiB at the second — the min the report prints
  {
    printf '%s\n' "$CSV_HEADER"
    printf 'A,1792000000,2026-10-22T09:00:00Z,seat/agent:none,173,100,250,100,0.6000,16900000,130000,15.99,ok\n'
    printf 'A,1792003600,2026-10-22T10:00:00Z,seat/agent:none,176,900,1250,900,0.6100,16800000,120000,15.92,ok\n'
  } > "$t/window.csv"
  # The same window with an engine restart inside it: 250 → 1250 (+1000), then the
  # counters come back from 50 (the restart) ⇒ the day is 1000 + 50, NOT 50 − 250.
  {
    printf '%s\n' "$CSV_HEADER"
    printf 'A,1792000000,2026-10-22T09:00:00Z,seat/agent:none,173,100,250,100,0.6000,16900000,130000,15.99,ok\n'
    printf 'A,1792003600,2026-10-22T10:00:00Z,seat/agent:none,176,900,1250,900,0.6100,16800000,120000,15.92,ok\n'
    printf 'B,1792007200,2026-10-22T11:00:00Z,seat/agent:none,50,20,50,20,0.1000,16800000,120000,15.92,ok\n'
  } > "$t/window-reset.csv"
  # A day where nothing asked the cache anything: every counter identical.
  {
    printf '%s\n' "$CSV_HEADER"
    printf 'A,1792000000,2026-10-22T09:00:00Z,seat/agent:none,173,100,250,100,0.0000,16900000,130000,15.99,ok\n'
    printf 'A,1792003600,2026-10-22T10:00:00Z,seat/agent:none,173,100,250,100,0.0000,16900000,130000,15.99,ok\n'
  } > "$t/window-idle.csv"

  cat > "$t/bin/fake-host" <<'FIX'
#!/usr/bin/env bash
# Answers ONE far-side command read from stdin. "Unhandled" is a FAILURE: it means the
# sampler grew a new kind of host interaction, and the fixture refuses to let an
# unlisted command pass as a read.
cmd="$(cat)"
printf '%s\n' "$cmd" >> "${FAKE_LOG:?}"
case "$cmd" in
  *meminfo*)
    if [ "${MW_FAKE_SSH_FAIL:-0}" = "1" ]; then
      printf 'fake-host: simulated transport failure\n' >&2
      exit 255
    fi
    # MW_FAKE_NO_METRICS=1 answers with the meminfo half only: the shape of an engine
    # that is not answering on :8000 while the box is fine.
    if [ "${MW_FAKE_NO_METRICS:-0}" != "1" ]; then cat "${FAKE_METRICS:?}"; fi
    printf '#MEMINFO\n'
    cat "${FAKE_MEMINFO:?}" ;;
  *) printf 'fake-host: unhandled command: %s\n' "$cmd" >&2; exit 9 ;;
esac
FIX
  chmod +x "$t/bin/fake-host"

  ok()  { printf '  ok:   %s\n' "$1"; }
  bad() { printf '  FAIL: %s\n' "$1"; fails=$((fails + 1)); }
  want() { if printf '%s\n' "$out" | grep -qF -- "$1"; then ok "$2"; else bad "$2 (wanted \"$1\")"; fi; }
  never() { if printf '%s\n' "$out" | grep -qF -- "$1"; then bad "$2 (but found \"$1\")"; else ok "$2"; fi; }

  export FAKE_LOG="$t/commands.log"
  export MW_SSH_CMD="$t/bin/fake-host" MW_OUT="$t/out" MW_LOG_DIR="$t/logs"
  export FAKE_METRICS="$t/metrics-full.txt" FAKE_MEMINFO="$t/meminfo.txt"
  export PI_PROVIDER="other" PI_MODEL="other/model-not-spark"

  echo "self-test 1 (case a): the parser — five counters, a summed label, a gauge, and a MISSING that is not a zero"
  local got
  got="$(counter_value "$(cat "$t/metrics-full.txt")" vllm:num_preemptions_total s)"
  [ "$got" = "173" ] && ok "num_preemptions_total = 173" || bad "num_preemptions_total read '$got', want 173"
  got="$(counter_value "$(cat "$t/metrics-full.txt")" vllm:prefix_cache_hits_total s)"
  [ "$got" = "100" ] && ok "prefix_cache_hits_total = 60+40 = 100, every series summed" \
    || bad "prefix_cache_hits_total read '$got', want 100 (the _created neighbour must not be summed in)"
  got="$(counter_value "$(cat "$t/metrics-full.txt")" vllm:prefix_cache_queries_total s)"
  [ "$got" = "250" ] && ok "prefix_cache_queries_total = 150+100 = 250" || bad "queries read '$got', want 250"
  got="$(counter_value "$(cat "$t/metrics-full.txt")" vllm:prompt_tokens_cached_total s)"
  [ "$got" = "100" ] && ok "prompt_tokens_cached_total = 100" || bad "cached read '$got', want 100"
  got="$(counter_value "$(cat "$t/metrics-full.txt")" vllm:kv_cache_usage_perc m)"
  [ "$got" = "0.6000" ] && ok "kv_cache_usage_perc = 0.6000 — the BUSIEST series, not the sum of the gauges" \
    || bad "kv_cache_usage_perc read '$got', want 0.6000 (0.6+0.42 would print 1.0200 and read as 102 % of the pool)"
  got="$(counter_value "$(cat "$t/metrics-gap.txt")" vllm:prompt_tokens_cached_total s)"
  [ "$got" = "MISSING" ] && ok "a counter absent from the body is MISSING, not 0" \
    || bad "an absent counter read '$got' — a silent zero is exactly the failure this script exists to avoid"

  # The engine-not-answering shape: the counters are unread, and the report must say so
  # instead of computing a rate out of nothing.
  MW_FAKE_NO_METRICS=1 MW_OUT="$t/out2" bash "$self" --once >/dev/null 2>&1 || true
  got="$(tail -1 "$t/out2/window.csv")"
  case "$got" in
    *,no-metrics) ok "an engine that answers nothing lands as read=no-metrics, not as a row of zeros" ;;
    *) bad "the no-metrics shape landed as: $got" ;;
  esac
  out="$(bash "$self" --report --csv "$t/out2/window.csv" --ref-doc "$t/ref-with.txt" 2>&1)" && rc=0 || rc=$?
  [ "$rc" != 0 ] && ok "a window of unread counters is refused, not reported" || bad "an unread window reported as a measurement"

  echo "self-test 2 (case b): the hit-rate arithmetic against the hand-valued pair"
  local st dq dh dp
  st="$(SINCE_E= UNTIL_E= window_stats "$t/window.csv")"
  dq="$(printf '%s\n' "$st" | sed -n 's/^d_queries=//p')"
  dh="$(printf '%s\n' "$st" | sed -n 's/^d_hits=//p')"
  dp="$(printf '%s\n' "$st" | sed -n 's/^d_preempt=//p')"
  [ "$dq" = "1000" ] && ok "queries delta = 1000 (1250 − 250)" || bad "queries delta '$dq', want 1000"
  [ "$dh" = "800" ] && ok "hits delta = 800 (900 − 100)" || bad "hits delta '$dh', want 800"
  [ "$dp" = "3" ] && ok "preemption delta = +3 (176 − 173)" || bad "preemption delta '$dp', want 3"
  [ "$(awk -v h="$dh" -v q="$dq" 'BEGIN{printf "%.2f", 100*h/q}')" = "80.00" ] \
    && ok "hand-check: 800/1000 = 80.00 %" || bad "the hand-check itself disagrees"
  out="$(bash "$self" --report --csv "$t/window.csv" --ref-doc "$t/ref-without.txt" 2>&1)" || rc=$?
  want "prefix-cache HIT RATE over the window: 80.00 %" "the report prints 80.00 % (800/1000)"
  want "token-weighted view (prompt_tokens_cached/queries): 80.00 %" "the token view prints the same 80.00 %"
  want "preemptions over the window: +3" "the report prints the preemption delta +3"
  want "usable = MemAvailable − CmaFree: min 15.91" "the usable gauge is formed from BOTH meminfo fields ((16800000−120000)/1048576 = 15.91)"
  st="$(SINCE_E= UNTIL_E= window_stats "$t/window-reset.csv")"
  dq="$(printf '%s\n' "$st" | sed -n 's/^d_queries=//p')"
  [ "$dq" = "1050" ] && ok "an engine restart inside the window sums across it: 1000 + 50 = 1050, never −200" \
    || bad "the reset case summed to '$dq', want 1050"

  echo "self-test 3 (case c): append, never truncate; and a second sampler is refused by pid"
  : > "$t/commands.log"
  bash "$self" --once >/dev/null 2>&1 || true
  p1="$t/out/window.csv"
  [ "$(wc -l < "$p1")" = "2" ] && ok "the first attempt wrote the header plus one row" || bad "file holds $(wc -l < "$p1") lines after attempt 1"
  cp "$p1" "$t/after-first.csv"
  bash "$self" --once >/dev/null 2>&1 || true
  [ "$(wc -l < "$p1")" = "3" ] && ok "the second attempt APPENDED (3 lines), it did not truncate" \
    || bad "after two attempts the file holds $(wc -l < "$p1") lines"
  [ "$(head -1 "$p1")" = "$CSV_HEADER" ] && ok "the header is still the one contract line" || bad "the header moved or doubled"
  cmp -s <(head -2 "$t/after-first.csv") <(head -2 "$p1") \
    && ok "attempt 1 is byte-for-byte intact after the retry" || bad "the retry modified what attempt 1 wrote"
  sleep 30 & alive=$!
  printf '%s\n' "$alive" > "$t/out/sampler.pid"
  out="$(bash "$self" --once 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 1 ] && ok "a second sampler against a live window is refused" || bad "the second sampler was accepted (rc $rc)"
  want "already writing" "the refusal names the window it would have corrupted"
  kill "$alive" 2>/dev/null; wait "$alive" 2>/dev/null || true
  rm -f "$t/out/sampler.pid"
  local ltag; ltag="$(date -u +%Y%m%d-%H%M)"
  p1="$(attempt_log "$ltag")"; : > "$p1"; p2="$(attempt_log "$ltag")"
  if [ "$p1" != "$p2" ]; then ok "two attempts get two logs ($(basename "$p1"), $(basename "$p2"))"
  else bad "both attempts were pointed at $p1 — a retry would truncate the first attempt's record"; fi

  echo "self-test 4 (case d): --report compares against the doc BY PATH, and says NOT COMPARED"
  out="$(bash "$self" --report --csv "$t/window.csv" --ref-doc "$t/ref-with.txt" 2>&1)" || true
  want "80.00 %  vs  pre-raise 75 %" "the hit-rate comparison prints the number parsed from the fixture doc"
  want "ref $t/ref-with.txt:2" "the comparison cites the path and line it read the number from"
  want "preemptions  +3 vs pre-raise 17" "the preemption comparison prints the count parsed from the fixture doc"
  out="$(bash "$self" --report --csv "$t/window.csv" --ref-doc "$t/ref-without.txt" 2>&1)" || true
  want "pre-raise NOT COMPARED" "a reference the doc does not carry prints NOT COMPARED"
  never "vs pre-raise 0" "and never as a silent zero"
  [ "$(ref_value "$REF_DOC" hit)" = "92" ] \
    && ok "the real spark/stability-test.md parses today: pre-raise hit rate 92 % (\$REF_DOC line $(ref_line "$REF_DOC" hit))" \
    || bad "the real doc no longer parses — ref_value(hit) gave '$(ref_value "$REF_DOC" hit)'; fix the pattern or the doc moved"

  echo "self-test 5 (case e): a zero-counter window is ZERO TRAFFIC, not a 0 % hit rate"
  out="$(bash "$self" --report --csv "$t/window-idle.csv" --ref-doc "$t/ref-with.txt" 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 4 ] && ok "an idle window exits 4: too thin to judge, never a pass" || bad "idle window rc=$rc, want 4"
  want "ZERO TRAFFIC" "the report says the cache was never asked"
  never "HIT RATE over the window: 0.00 %" "and does not print a 0 % hit rate"
  want "verdict: NOT DECIDED" "the verdict line refuses to decide from an idle window"

  echo "self-test 6: the read-only contract, one ssh per sample, the stamp, and no Rule 0 refusal"
  : > "$t/commands.log"
  out="$(bash "$self" --once 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 0 ] && ok "the sampler ran against the fixture transport" || bad "sampler rc=$rc: $(printf '%s' "$out" | tail -3)"
  [ "$(wc -l < "$t/commands.log")" = "1" ] && ok "ONE command reached the box for the whole sample batch" \
    || bad "a sample sent $(wc -l < "$t/commands.log") commands (the batch must be one ssh session)"
  [ "$(tail -1 "$t/out/window.csv" | cut -d, -f4)" = "$(client_stamp)" ] \
    && ok "the CSV's stamp column carries <hostname>/agent:<PI_MODEL> — the record says who took the read" \
    || bad "the stamp column reads '$(tail -1 "$t/out/window.csv" | cut -d, -f4)', want $(client_stamp)"
  [ "$(tail -1 "$t/out/window.csv" | cut -d, -f3)" != "" ] \
    && ok "the row carries its UTC instant beside the epoch" || bad "the row has no instant"
  out="$(PI_PROVIDER=spark PI_MODEL=spark/qwen3.8-flash-next bash "$self" --once 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 0 ] && ok "PI_PROVIDER=spark does NOT refuse: a counter read is not a timed number" \
    || bad "the script grew a Rule 0 refusal (rc $rc) — that refusal is the mis-classification this row exists to close"
  want "READ, NOT A LEG" "the loud header line names what this run is"
  : > "$t/commands.log"
  MW_FAKE_SSH_FAIL=1 bash "$self" --once >/dev/null 2>&1 || true
  tail -1 "$t/out/window.csv" | grep -q 'ssh-fail' \
    && ok "a failed read is recorded as ssh-fail with MISSING fields, not as a row of zeros" \
    || bad "a failed read landed in the CSV as something else: $(tail -1 "$t/out/window.csv")"
  out="$(bash "$self" --status 2>&1)"
  want "row(s)" "--status reports the row count and the sampler's state"
  bad="$(grep -nE 'docker (restart|stop|rm|kill)|systemctl|reboot|shutdown|ansible|spark_llm_profile[[:space:]]*:|drop_caches|sed -i| -N |-L |-D ' "$t/commands.log" || true)"
  [ -z "$bad" ] && ok "no mutate verb and no tunnel flag in $(wc -l < "$t/commands.log") command(s)" \
    || bad "a mutate verb or a forward reached the box: $bad"

  rm -rf "$t"
  if [ "$fails" = 0 ]; then echo "SELF-TEST OK"; return 0; fi
  printf 'SELF-TEST FAILED: %s assertion(s)\n' "$fails"
  return 1
}

case "$MODE" in
  self-test) run_self_test; exit $? ;;
  report)    run_report; exit $? ;;
  status)    run_status; exit $? ;;
  sample)    LOG="$(attempt_log "$(date -u +%Y%m%d-%H%M)")"
             printf '>>> attempt log: %s\n' "$LOG"
             # pipefail makes the pipeline's status the run's status: logging never hides a failure.
             run_sample 2>&1 | tee -a "$LOG"
             exit "${PIPESTATUS[0]}" ;;
esac
die "unreachable mode '$MODE'" 2
