#!/usr/bin/env bash
# ============================================================================
# hd469-baseline.sh — HD-469's `reasoning` UNDER-CAP baseline, in ONE act.
#
# WHY A DRIVER AND NOT FIVE SHELL LINES. The handover in
# spark/reports/hd469-reasoning/README.md §"Still owed: the under-cap baseline
# (handover, exact)" is five commands and a paste instruction, and that form lost
# the measurement twice: run #1 and run #2 both left the numbers in a `todo.md` row
# and in a commit message with NOTHING in the evidence dir the row cited (run #3's
# correction, same file), and a retry that reused /tmp/hd469-reasoning.log
# truncated the only record of the failed attempt. A driver cannot repeat either
# defect: it writes the RAW under the directory the row cites before it prints any
# verdict, and every attempt gets its own log file.
#
# WHAT ACTUALLY PROVES THE CLOCK REGIME (docs/hardware-spark.md §GPU clock cap): a
# SUSTAINED `clocks.sm` trace taken ACROSS the load window. `clocks.max.sm` is a
# capability field — it read 3003 before and after the lock — and a spot read of
# clocks.sm says the same thing capped and uncapped. So the -l 5 sampler runs
# ALONGSIDE the probe and is stopped when the probe returns, never before it.
#
# RULE 0 (spark/llm-profiles/README.md, restated in prompt-spark-llm.md): a session
# whose own model is served by spark may produce no timed number — and this driver
# drives load through that engine, so it refuses before its first read and before it
# opens a file. Take the leg from an externally-served session standing on the
# designated runner station (docs/orchestration.md §4, docs/harness-pi-seat-
# identity.md §5a, prompt-laptop-wsl.md §0/§1). The driver stamps every run
# <hostname>/agent:<PI_MODEL> — the shape run-scenario.sh lines 48-49 put in the
# results CSV's `client` column — so provenance is checkable afterwards.
#
# READ-ONLY against the box by construction: every far-side command goes through
# host_read() and is a read (nvidia-smi, /proc/meminfo, docker logs, /metrics,
# docker inspect). No converge, no container restart, no profile write — and
# --self-test runs the whole driver against fixtures and asserts the forbidden verbs
# never reach the command log, so read-only is a CHECKED property, not a promise.
#
# Usage
#   scripts/bench/spark/hd469-baseline.sh [--profile reasoning] [--host spark]
#       [--container NAME] [--base-url URL] [--interval 5] [--window 1800]
#       [--out DIR] [--self-test]
#
#   --host is the ssh NAME of the box (default spark). Away from the house name the hop:
#   `--host spark-vps`. A plain node name is the Home leg with no jump, so off-site it times
#   out and reads like a dead box (docs/network-vpn.md §The laptop alias contract rule 1).
#
# Fixture hooks — what keeps --self-test off the box and off the vault (and why it is the one
# arm Rule 0 does not have to refuse):
#   HD469_SSH_CMD    command that receives each far-side command on stdin
#   HD469_PROBE_CMD  replaces the probe leg (word-split; fixture use only)
#   HD469_LOG_DIR    where the per-attempt hd469-*.log files are created
#
# Exit: 0 captured · 1 a capture missing or unparseable · 2 usage · 3 Rule 0 ·
#       6 the engine container is not running (measured, not assumed)
# A probe verdict of FAIL is a RESULT, not an exit code: the file set is what this
# driver is judged on, and `probe exit N` is recorded beside it.
# ============================================================================
set -euo pipefail
# Numbers here land in a CSV column and in a markdown table. Under a UTF-8 locale such as
# sl_SI awk's "%.2f" prints 15,99 — which splits a CSV field and never equals the hand-valued
# fixture it is tested against. The output format is fixed, not the operator's environment.
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root FOUND, never assumed from a depth (CONVENTIONS §6 / lib/repo-root.sh): the evidence
# dir is <root>/spark/reports/hd469-reasoning, and a wrong depth writes evidence nobody finds.
_hl_d="$SELF_DIR"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"        # sets REPO; FATAL when no root is found
# The probe leg is RUN with the interpreter lib/python.sh probes: `python3` on the Win11 seat is the
# Microsoft Store alias STUB (on PATH, rc 49, not an interpreter), so a name here is a red on one seat.
hl_source_lib "${BASH_SOURCE[0]}" python.sh

PROFILE="reasoning"
HOST="spark"
CONTAINER="${VLLM_CONTAINER:-vllm-qwen-spark}"   # IaC spark_vllm_container -> the profile's container
BASE_URL="https://llm.ts.kogler.si/v1"           # the endpoint the clients actually use
INTERVAL=5                                       # the handover's -l 5
WINDOW=1800                                      # hard cap on the trace, seconds (it ends with the probe)
OUT=""
TEST=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   PROFILE="${2:?--profile needs the arm, e.g. reasoning}"; shift ;;
    --host)      HOST="${2:?--host needs the box name}"; shift ;;
    --container) CONTAINER="${2:?--container needs the engine container name}"; shift ;;
    --base-url)  BASE_URL="${2:?--base-url needs the endpoint}"; shift ;;
    --interval)  INTERVAL="${2:?--interval needs seconds}"; shift ;;
    --window)    WINDOW="${2:?--window needs seconds}"; shift ;;
    --out)       OUT="${2:?--out needs the evidence directory}"; shift ;;
    --self-test) TEST=1 ;;
    *)           die "unknown arg $1 — see the Usage block" 2 ;;
  esac
  shift
done
OUT="${OUT:-$REPO/spark/reports/hd469-reasoning}"

# Rule 0, FIRST: before ssh, before the log file, before anything is read. A spark-served
# session IS the load it would be measuring — its own tokens land in the engine's prefix
# cache, in its preemption counter and in the clocks trace it would then quote.
# `--self-test` is the one exempt arm: it is fixture-only by construction (the transport is
# replaced by HD469_SSH_CMD, and an arm of the test asserts no unlisted command can pass as a
# read), so refusing it would make the refusal itself untestable from the very seat that
# needs the proof.
if [ "$TEST" != "1" ] && { [ "${PI_PROVIDER:-}" = "spark" ] || printf '%s' "${PI_MODEL:-}" | grep -q '^spark/'; }; then
  printf 'ERROR: Rule 0 — this session is served by spark (PI_PROVIDER=%s PI_MODEL=%s), so it may\n' \
    "${PI_PROVIDER:-unset}" "${PI_MODEL:-unset}" >&2
  printf '       take NO timed number, and this driver drives load through that engine. Run it from\n' >&2
  printf '       an externally-served session on the designated runner station (the WSL Debian seat:\n' >&2
  printf '       prompt-laptop-wsl.md §0/§1, docs/orchestration.md §4). Counter, log and inspect\n' >&2
  printf '       READS stay legal from any session; this leg is not one of them.\n' >&2
  exit 3
fi

# <hostname>/agent:<PI_MODEL> — the same stamp run-scenario.sh writes into the results CSV, so a
# leg taken off-station or from a spark-served seat is identifiable in the evidence afterwards.
client_stamp() {
  printf '%s/%s' "${BENCH_CLIENT:-$(hostname -s 2>/dev/null || echo unknown)}" \
    "agent:${PI_MODEL:-none}" | tr -d ','
}

# One log file per ATTEMPT: /tmp/hd469-<profile>-<HHMM>.log. A retry must never open the
# previous attempt's file, so within the same minute the name gains .1, .2 … — HD-469 lost its
# only record of a failed converge exactly this way.
attempt_log() {
  local dir="${HD469_LOG_DIR:-/tmp}" n=1 path
  path="$dir/hd469-$1-$(date +%H%M).log"
  while [ -e "$path" ]; do
    path="$dir/hd469-$1-$(date +%H%M).$n.log"
    n=$((n + 1))
  done
  printf '%s' "$path"
}

# The ONE door to the far side. Everything sent through it is a read; --self-test intercepts
# it here, which is what lets the fixture run exercise the real command strings.
host_read() {
  local cmd="$1"
  if [ -n "${HD469_SSH_CMD:-}" ]; then
    printf '%s\n' "$cmd" | $HD469_SSH_CMD
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$cmd"
  fi
}

MEMINFO_SNIPPET="grep -E '^(MemTotal|MemAvailable|CmaFree):' /proc/meminfo"
METRICS_SNIPPET="curl -s --max-time 10 localhost:8000/metrics | grep -E 'num_preemptions_total|prefix_cache|spec_decode'"
KV_SNIPPET='docker logs --tail 40000 @CONTAINER@ 2>&1 | tr "\r" "\n" | grep -E "Available KV cache memory|GPU KV cache size|Maximum concurrency"'

# mem_pair <meminfo text> <label> -> "<avail_kib> <cma_kib> <usable_gib>", loud if half is missing.
# BOTH fields are mandatory: MemAvailable ALONE is falsified on GB10, because CMA counts as
# available and it INFLATES as pressure rises (both real kills read ~10.4 GiB available at 1.6
# GiB usable). usable = MemAvailable − CmaFree is the same gauge as the watchdog and the alert rule.
mem_pair() {
  local text="$1" label="$2" a c
  a=$(printf '%s\n' "$text" | awk '$1 == "MemAvailable:" {print $2; exit}') || true
  c=$(printf '%s\n' "$text" | awk '$1 == "CmaFree:" {print $2; exit}') || true
  [ -n "$a" ] || die "$label: the meminfo read holds no MemAvailable — a failed read is not a zero" 1
  [ -n "$c" ] || die "$label: the meminfo read holds no CmaFree — MemAvailable alone is the FALSIFIED gauge on GB10, refusing to read it as 0" 1
  printf '%s %s %s\n' "$a" "$c" \
    "$(awk -v a="$a" -v c="$c" 'BEGIN{printf "%.2f", (a-c)/1048576}')"
}

# counter_sum <metrics text> <metric> — sum EVERY series of a labelled counter. `prefix_cache_*`
# carries labels, so picking one line would report a fraction of the truth (snapshot-metrics.sh
# has the same rule as sumget()).
counter_sum() {
  printf '%s\n' "$1" | awk -v m="$2" '!/^#/ && $1 ~ "^"m"([ {]|$)" { s += $NF } END{printf "%.0f", s+0}'
}

# trace_stat <csv> <column> -> "min median max" of the numbers in that column (units stripped).
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

run_main() {
  local client tag raw csv probe probe_rc running mem_start mem_end pair_s pair_e met_start met_end
  local kv pre_d pfx_hit_d pfx_q_d spec_d clk pow trace_rows md

  client="$(client_stamp)"
  tag="$(date -u +%Y%m%d-%H%M%S)"
  raw="$OUT/raw"
  mkdir -p "$raw"
  printf '>>> hd469-baseline profile=%s host=%s container=%s client=%s\n' \
    "$PROFILE" "$HOST" "$CONTAINER" "$client"

  # Container identity FIRST (run-scenario.sh's lesson): with the wrong name every later read
  # returns nothing and the run still prints a complete-looking set of files.
  running=$(host_read "docker inspect -f '{{.State.Running}}' $CONTAINER" 2>/dev/null || echo false)
  if [ "$running" != "true" ]; then
    printf 'ERROR: container %s is not running on %s, so there is no engine to measure.\n' "$CONTAINER" "$HOST" >&2
    printf '       The name is IaC spark_vllm_container -> spark_llm_profiles[spark_llm_profile].container;\n' >&2
    printf '       pass --container <name> for the arm actually serving. Nothing was captured.\n' >&2
    exit 6
  fi

  # --- opening end ------------------------------------------------------------------------
  mem_start="$(host_read "$MEMINFO_SNIPPET")" || die "the opening /proc/meminfo read failed" 1
  pair_s="$(mem_pair "$mem_start" "start")"
  printf '%s\n' "$mem_start" > "$raw/baseline-$tag-meminfo-start.txt"
  printf '>>> start: %s\n' "$pair_s"

  # --- /metrics BEFORE: the counters are cumulative, so a single end-of-window read cannot
  #     say what happened INSIDE the window, which is the only question preemptions ask ------
  met_start="$(host_read "$METRICS_SNIPPET")" || true
  [ -n "$met_start" ] || die "the opening /metrics read came back empty on $HOST. If :8000/metrics is not exposed on the host, take it the container route that worked in spark/reports/hd494-rest-floor/RESULTS.md §4 and say so in the report." 1
  printf '%s\n' "$met_start" > "$raw/baseline-$tag-metrics-start.txt"

  # --- the trace, ACROSS the window: the half that proves the regime -----------------------
  csv="$raw/baseline-$tag-clocks.csv"
  host_read "timeout $((WINDOW + 60)) nvidia-smi --query-gpu=timestamp,clocks.sm,power.draw,temperature.gpu,clocks_event_reasons.active --format=csv -l $INTERVAL" \
    > "$csv" 2> "$raw/baseline-$tag-clocks.err" &
  printf '>>> clock trace: nvidia-smi -l %s across the window, capped at %s s\n' "$INTERVAL" "$((WINDOW + 60))"
  local trace_pid=$! ready_i ready=0
  # Wait for the sampler's FIRST row before the window opens: a sampler that fails at once (no
  # nvidia-smi, refused flag) must fail BEFORE the probe spends the window. The file is the only
  # signal — `kill -0` was tried and lost the race, because a fast sampler is already reaped by
  # the time it is asked about, and a reaped child makes the parent look dead while its output
  # is sitting complete in the file.
  for ready_i in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(awk 'NR > 1' "$csv" 2>/dev/null | grep -c . || true)" -ge 1 ] && { ready=1; break; }
    sleep 1
  done
  [ "$ready" = 1 ] || die "the clock sampler produced no row at all, so there is no trace to take (far-side stderr: $raw/baseline-$tag-clocks.err)" 1

  # --- the load: verbatim raw stdout, no reformatting --------------------------------------
  # Verbatim is safe here because spark-llm-probe.py reads the bearer from 1Password and prints
  # only its LENGTH. If that ever changes, this is the line to gate — run-scenario.sh scrubs at
  # the point of write for exactly that reason.
  probe="$raw/baseline-$tag-probe.txt"
  if [ -n "${HD469_PROBE_CMD:-}" ]; then
    printf '>>> probe: %s\n' "$HD469_PROBE_CMD"
    $HD469_PROBE_CMD > "$probe" 2>&1 && probe_rc=0 || probe_rc=$?
  else
    printf '>>> probe: %s scripts/bench/spark-llm-probe.py --base-url %s all --profile %s\n' "${HL_PYTHON[*]}" "$BASE_URL" "$PROFILE"
    "${HL_PYTHON[@]}" "$REPO/scripts/bench/spark-llm-probe.py" --base-url "$BASE_URL" all --profile "$PROFILE" \
      > "$probe" 2>&1 && probe_rc=0 || probe_rc=$?
  fi
  printf '>>> probe exit %s — recorded, not repaired (a FAIL here IS the under-cap baseline)\n' "$probe_rc"

  # stop the trace, then prove it actually ran
  kill "$trace_pid" 2>/dev/null || true
  wait "$trace_pid" 2>/dev/null || true          # the remote `timeout` may have won the race
  trace_rows=$(awk 'NR > 1' "$csv" 2>/dev/null | grep -c . || true)
  [ "${trace_rows:-0}" -ge 2 ] || die "the clock trace holds ${trace_rows:-0} sample(s): NO TRACE, NO COMPARISON (docs/hardware-spark.md §GPU clock cap). Far-side stderr: $raw/baseline-$tag-clocks.err" 1

  # --- closing end ------------------------------------------------------------------------
  mem_end="$(host_read "$MEMINFO_SNIPPET")" || die "the closing /proc/meminfo read failed" 1
  pair_e="$(mem_pair "$mem_end" "end")"
  printf '%s\n' "$mem_end" > "$raw/baseline-$tag-meminfo-end.txt"
  printf '>>> end:   %s\n' "$pair_e"

  kv=$(host_read "${KV_SNIPPET//@CONTAINER@/$CONTAINER}") || true
  if [ -n "$kv" ]; then printf '%s\n' "$kv" > "$raw/baseline-$tag-kv.txt"
  else printf '%s\n' "no KV boot line in this log window — the engine booted before docker logs rotated" \
    > "$raw/baseline-$tag-kv.txt"; fi

  met_end="$(host_read "$METRICS_SNIPPET")" || true
  [ -n "$met_end" ] || die "the closing /metrics read came back empty" 1
  printf '%s\n' "$met_end" > "$raw/baseline-$tag-metrics-end.txt"

  pre_d=$(awk -v a="$(counter_sum "$met_end" vllm:num_preemptions_total)" \
               -v b="$(counter_sum "$met_start" vllm:num_preemptions_total)" 'BEGIN{printf "%.0f", a-b}')
  pfx_hit_d=$(awk -v a="$(counter_sum "$met_end" vllm:prefix_cache_hits_total)" \
                   -v b="$(counter_sum "$met_start" vllm:prefix_cache_hits_total)" 'BEGIN{printf "%.0f", a-b}')
  pfx_q_d=$(awk -v a="$(counter_sum "$met_end" vllm:prefix_cache_queries_total)" \
                  -v b="$(counter_sum "$met_start" vllm:prefix_cache_queries_total)" 'BEGIN{printf "%.0f", a-b}')
  spec_d="accepted $(counter_sum "$met_end" vllm:spec_decode_num_accepted_tokens_total) / draft $(counter_sum "$met_end" vllm:spec_decode_num_draft_tokens_total) (cumulative since boot)"

  clk="$(trace_stat "$csv" 2)"
  pow="$(trace_stat "$csv" 3 %.1f)"

  md="$OUT/baseline-$tag.md"
  {
    printf '# HD-469 under-cap baseline — %s\n\n' "$tag"
    printf 'Stamps: client `%s` · host `%s` · container `%s` · profile `%s` · probe exit `%s`\n' "$client" "$HOST" "$CONTAINER" "$PROFILE" "$probe_rc"
    printf 'Endpoint `%s` · trace `-l %s` across a %s s cap · Rule 0: the stamp names the seat and the serving model, check it names an externally-served one.\n\n' "$BASE_URL" "$INTERVAL" "$((WINDOW + 60))"
    printf '## The regime discriminator\n\n'
    printf '`clocks.sm` min/median/max over %s trace rows: %s MHz. `clocks.max.sm` is deliberately absent: it is a capability field and reads 3003 capped and uncapped (docs/hardware-spark.md §GPU clock cap).\n\n' "$trace_rows" "$clk"
    printf '`power.draw` min/median/max: %s W. `temperature.gpu` and `clocks_event_reasons.active` are columns 4 and 5 of the raw CSV.\n\n' "$pow"
    printf '## Host memory at BOTH ends (usable = MemAvailable − CmaFree)\n\n'
    printf '| end | MemAvailable KiB | CmaFree KiB | usable GiB |\n|---|---|---|---|\n'
    printf '| start | %s |\n' "$(printf '%s' "$pair_s" | awk '{print $1" | "$2" | "$3}')"
    printf '| end | %s |\n\n' "$(printf '%s' "$pair_e" | awk '{print $1" | "$2" | "$3}')"
    printf '## Engine counters\n\n'
    printf '· `num_preemptions_total` +%s across this window\n· prefix cache +%s hits / +%s queries\n· spec decode: %s\n\n' "$pre_d" "$pfx_hit_d" "$pfx_q_d" "$spec_d"
    printf '## Raw\n\n'
    printf '· probe stdout, verbatim: [`raw/baseline-%s-probe.txt`](raw/baseline-%s-probe.txt)\n' "$tag" "$tag"
    printf '· clock trace: [`raw/baseline-%s-clocks.csv`](raw/baseline-%s-clocks.csv)\n' "$tag" "$tag"
    printf '· meminfo both ends, KV lines, /metrics both ends: `raw/baseline-%s-meminfo-start.txt`, `-meminfo-end.txt`, `-kv.txt`, `-metrics-start.txt`, `-metrics-end.txt`\n' "$tag"
  } > "$md"

  printf '>>> clocks.sm min/median/max = %s MHz over %s rows · power %s W\n' "$clk" "$trace_rows" "$pow"
  printf '>>> preemptions +%s · prefix +%s hits / +%s queries · probe exit %s\n' "$pre_d" "$pfx_hit_d" "$pfx_q_d" "$probe_rc"
  printf '>>> evidence: %s\n>>>      raw:  %s\n' "$md" "$raw"
}

# ---------------------------------------------------------------------------
# --self-test — fixtures only. Nothing here sshes, nothing reads the vault, nothing
# reaches an engine: on a spark-served seat that is the entire point, so the refusal
# and the read-only contract are PROVEN rather than asserted.
# ---------------------------------------------------------------------------
run_self_test() {
  local t fails=0 out rc p1 p2 cmdlog pairv bad_cmd
  t="$(mktemp -d)"
  local self="$SELF_DIR/$(basename "${BASH_SOURCE[0]}")"
  mkdir -p "$t/bin" "$t/out" "$t/logs"
  cmdlog="$t/commands.log"; : > "$cmdlog"

  cat > "$t/bin/fake-host" <<'FIX'
#!/usr/bin/env bash
# Answers ONE far-side command read from stdin. "Unhandled" is a FAILURE: it means
# the driver grew a new kind of host interaction, and the fixture refuses to let an
# unlisted command pass as a read.
cmd="$(cat)"
printf '%s\n' "$cmd" >> "${FAKE_LOG:?}"
case "$cmd" in
  *docker\ inspect*) printf '%s\n' "${FAKE_RUNNING:-true}" ;;
  *nvidia-smi*)
    printf 'timestamp, clocks.current.sm [MHz], power.draw [W], temperature.gpu, clocks_event_reasons.active\n'
    printf '20261022000000.000, 2415 MHz, 140.23 W, 58, 0x0\n'
    printf '20261022000005.000, 2409 MHz, 142.10 W, 59, 0x0\n'
    printf '20261022000010.000, 2411 MHz, 139.88 W, 58, 0x0\n' ;;
  */proc/meminfo*)
    printf 'MemTotal:       127532360 kB\nMemFree:          800000 kB\nMemAvailable:   16900000 kB\nCmaFree:            130000 kB\n' ;;
  */metrics*)
    printf 'vllm:num_preemptions_total 173\nvllm:prefix_cache_hits_total{model_name="m"} 100\nvllm:prefix_cache_queries_total{model_name="m"} 250\nvllm:spec_decode_num_accepted_tokens_total 900\nvllm:spec_decode_num_draft_tokens_total 2000\n' ;;
  *docker\ logs*)
    printf 'Available KV cache memory: 18.63 GiB\nGPU KV cache size: 644,599 tokens\n' ;;
  *) printf 'fake-host: unhandled command: %s\n' "$cmd" >&2; exit 9 ;;
esac
FIX
  chmod +x "$t/bin/fake-host"

  ok()  { printf '  ok:   %s\n' "$1"; }
  bad() { printf '  FAIL: %s\n' "$1"; fails=$((fails + 1)); }
  want() { if printf '%s\n' "$out" | grep -qF -- "$1"; then ok "$2"; else bad "$2 (wanted \"$1\")"; fi; }

  export FAKE_LOG="$cmdlog"
  export HD469_SSH_CMD="$t/bin/fake-host" HD469_LOG_DIR="$t/logs"
  export HD469_PROBE_CMD="printf probe-stdout-line\n"
  export PI_PROVIDER="other" PI_MODEL="other/model-not-spark"

  echo "self-test 1: a spark-served env refuses, before any read and before any file"
  out="$(PI_PROVIDER=spark PI_MODEL=spark/qwen3.8-flash-next bash "$self" --out "$t/out" 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 3 ] && ok "exits 3 under PI_PROVIDER=spark" || bad "spark-served rc=$rc, want 3"
  want "Rule 0" "the refusal names Rule 0"
  [ "$(wc -l < "$cmdlog")" -eq 0 ] && ok "no host command was sent" || bad "the refusal came after a host read"
  [ "$(ls -1 "$t/logs" | grep -c 'hd469-' || true)" -eq 0 ] \
    && ok "no attempt log was created either" || bad "the refusal still opened an attempt log"

  echo "self-test 2: two attempts get two distinct log paths (a retry never truncates)"
  : > "$cmdlog"
  out="$(bash "$self" --out "$t/out" 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 0 ] && ok "the fixture run completes" || bad "fixture run rc=$rc: $(printf '%s' "$out" | tail -3)"
  p1="$(printf '%s\n' "$out" | sed -n 's/^>>> attempt log: //p' | head -1)"
  cp "$p1" "$t/attempt1.copy" 2>/dev/null || true
  out="$(bash "$self" --out "$t/out" 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 0 ] && ok "the retry also completes" || bad "retry rc=$rc: $(printf '%s' "$out" | tail -3)"
  p2="$(printf '%s\n' "$out" | sed -n 's/^>>> attempt log: //p' | head -1)"
  [ -n "$p1" ] && [ -n "$p2" ] && [ "$p1" != "$p2" ] \
    && ok "two attempts wrote two files ($(basename "$p1"), $(basename "$p2"))" \
    || bad "the two attempts shared one log path ($p1 vs $p2)"
  if [ -f "$t/attempt1.copy" ] && cmp -s "$t/attempt1.copy" "$p1"; then ok "attempt 1 is byte-for-byte intact"
  else bad "attempt 1 was modified by the retry"; fi

  echo "self-test 3: the meminfo parser yields BOTH fields at BOTH ends, and refuses a half"
  pairv="$(mem_pair 'MemTotal:       127532360 kB
MemAvailable:   16900000 kB
CmaFree:            130000 kB' end)" || pairv=""
  [ "$(printf '%s' "$pairv" | awk '{print $1}')" = "16900000" ] \
    && ok "MemAvailable parsed (16900000 KiB)" || bad "MemAvailable parsed as '$pairv'"
  [ "$(printf '%s' "$pairv" | awk '{print $2}')" = "130000" ] \
    && ok "CmaFree parsed (130000 KiB)" || bad "CmaFree parsed as '$pairv'"
  [ "$(printf '%s' "$pairv" | awk '{print $3}')" = "15.99" ] \
    && ok "usable = 15.99 GiB by hand-check ((16900000-130000)/1048576)" \
    || bad "usable printed as '$pairv', want 15.99"
  out="$(mem_pair 'MemTotal: 127532360 kB
MemAvailable: 16900000 kB' start 2>&1)" && rc=0 || rc=$?
  [ "$rc" != 0 ] && ok "a read with no CmaFree is refused, never zero-filled" \
    || bad "a CmaFree-less meminfo read was accepted"
  want "CmaFree" "the refusal names the field that is missing"

  echo "self-test 4: a container reported not running is refused (measured, not assumed)"
  : > "$cmdlog"
  out="$(FAKE_RUNNING=false bash "$self" --out "$t/out" 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 6 ] && ok "exits 6 when the engine container reports false" || bad "not-running rc=$rc, want 6"
  want "is not running" "the refusal says the engine is not running"
  [ "$(wc -l < "$cmdlog")" -eq 1 ] && ok "it stopped at the identity check — nothing else was read" \
    || bad "it kept reading the box after the container check failed ($(wc -l < "$cmdlog") commands)"

  echo "self-test 5: every command the driver sends is a read"
  : > "$cmdlog"
  bash "$self" --out "$t/out" >/dev/null 2>&1 || true
  bad_cmd="$(grep -nE 'docker (restart|stop|rm|kill)|systemctl|reboot|shutdown|ansible|spark_llm_profile[[:space:]]*:|drop_caches|sed -i' "$cmdlog" || true)"
  [ -z "$bad_cmd" ] && ok "no mutate verb in $(wc -l < "$cmdlog") command(s)" \
    || bad "a mutate verb reached the box: $bad_cmd"
  if grep -q 'nvidia-smi' "$cmdlog" && grep -q '/proc/meminfo' "$cmdlog" \
     && grep -q '/metrics' "$cmdlog" && grep -q 'docker logs' "$cmdlog"; then
    ok "all four captures were taken (trace, meminfo, /metrics, KV lines)"
  else bad "a capture never reached the box"; fi

  rm -rf "$t"
  [ "$fails" = 0 ] && { echo "SELF-TEST OK"; return 0; }
  echo "SELF-TEST FAILED: $fails assertion(s)"; return 1
}

if [ "$TEST" = 1 ]; then run_self_test; exit $?; fi

LOG="$(attempt_log "$PROFILE")"
printf '>>> attempt log: %s\n' "$LOG"
# pipefail makes the pipeline's status the run's status: writing the log never hides a failure.
run_main "$@" 2>&1 | tee -a "$LOG"
