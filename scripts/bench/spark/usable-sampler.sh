#!/usr/bin/env bash
# ============================================================================
# usable-sampler.sh — HD-494's owed measurement: ONE 1 s `usable` sampler held
# across ONE heavy prefill, and the arithmetic that sets the number beside the
# ledger's rest prediction.
#
# WHY THIS IS STILL OWED. spark/reports/hd494-rest-floor/RESULTS.md derived the
# global ceiling from RECORDED history on purpose — that sitting was served by
# spark, so any fresh memory reading it produced would have been contaminated by its
# own inference traffic. The report says the consequence plainly: the ledger's rest
# prediction came out 0.9–2.6 GiB optimistic against those samples, so the missing
# term is MEASURED, not argued (§5). What no record can answer is what `usable`
# bottoms at DURING a heavy prefill — the watchdog ring samples at 15 s and a prefill
# dip is shorter than that. 1 s is the cadence the question needs.
#
# THE GAUGE is usable = MemAvailable − CmaFree. MemAvailable ALONE is falsified on
# GB10: CMA counts as available, so it INFLATES as pressure rises. Same gauge as the
# watchdog, the alert rule and run-scenario.sh's launch floor.
#
# THE ARITHMETIC — the form of docs/hardware-spark.md §The GLOBAL ceiling, used by
# spark/reports/hd494-rest-floor/RESULTS.md §5, and it decides nothing:
#
#     ledger rest = MemTotal − OS@boot − declared device hold
#     delta       = min(usable over this window) − ledger rest
#
# MemTotal comes from the box, the declared hold from IaC through the probe's LOCAL
# profile leg, and only OS@boot is a recorded constant (4.934e9 — the restart-delta
# measurement in docs/hardware-spark.md §The fixed cost, MEASURED). A negative delta
# says the ledger is OPTIMISTIC by that much. That number is what the owner picks the
# floor from (CRIT vs WARN); the choice is not this script's.
#
# RULE 0 (spark/llm-profiles/README.md): a session served by spark may take no timed
# number, and this driver both samples a window and drives load through that engine,
# so it refuses before its first read and before it opens a file. Run it from an
# externally-served session on the designated runner station (the WSL Debian seat:
# prompt-laptop-wsl.md §0/§1, docs/orchestration.md §4). Every run is stamped
# <hostname>/agent:<PI_MODEL>, the shape run-scenario.sh lines 48-49 use.
#
# READ-ONLY against the box by construction: the far side runs one read loop over
# /proc/meminfo plus a `docker inspect` for the identity check; the only load is the
# HTTP prefill through the endpoint the clients already use. No converge, no
# container restart, no profile write — and --self-test asserts no mutate verb is
# ever sent. The prefill bearer is read from 1Password by the probe, so it never
# reaches argv, a file or the transcript; the probe prints only its LENGTH.
#
# Usage
#   scripts/bench/spark/usable-sampler.sh [--profile fast] [--host spark]
#       [--container NAME] [--base-url URL] [--tokens N] [--interval 1]
#       [--window 900] [--tail 15] [--out DIR] [--os-at-boot-bytes N]
#       [--declared-hold-bytes N] [--self-test]
#
# Fixture hooks — what keeps --self-test off the box and off the vault:
#   HD494_SSH_CMD             command that receives each far-side command on stdin
#   HD494_SAMPLE_FILE         replay this stream instead of sampling the box
#   HD494_PREFILL_CMD         replaces the prefill leg (word-split; fixture only)
#   HD494_PROFILE_LEG_FILE    replay this text instead of the probe's local leg
#   HD494_LOG_DIR             where the per-attempt hd494-*.log files are created
#
# Exit: 0 captured · 1 a capture missing or unparseable · 2 usage · 3 Rule 0 ·
#       4 the prefill leg failed, so the window may hold rest and not a prefill ·
#       6 the engine container is not running (measured, not assumed)
# ============================================================================
set -euo pipefail
# Numbers here land in a CSV column and in a markdown table. Under a UTF-8 locale such as
# sl_SI awk's "%.2f" prints 11,73 — which splits a CSV field and never equals the hand-valued
# fixture it is tested against. The output format is fixed, not the operator's environment.
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root FOUND, never assumed from a depth (CONVENTIONS §6 / lib/repo-root.sh): the profile
# leg and the evidence dir are both addressed from the root, and a wrong depth would read a
# profile out of the wrong tree.
_hl_d="$SELF_DIR"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"        # sets REPO; FATAL when no root is found
# The probe legs are RUN with the interpreter lib/python.sh probes — `python3` is the Microsoft Store
# alias STUB on the Win11 seat (on PATH, rc 49, not an interpreter), which reads as a broken profile
# leg there and as nothing at all on the Debian seats.
hl_source_lib "${BASH_SOURCE[0]}" python.sh

PROFILE="fast"                                  # the current regime; --profile names the arm measured
HOST="spark"
CONTAINER="${VLLM_CONTAINER:-vllm-qwen-spark}"  # IaC spark_vllm_container -> the profile's container
BASE_URL="https://llm.ts.kogler.si/v1"
TOKENS=""                                       # empty = the profile's own max_model_len, read from IaC
INTERVAL=1                                      # the cadence this row owes: 1 s, not the ring's 15 s
WINDOW=900                                      # hard cap on the sampler, seconds (it stops after the prefill)
TAIL=15                                         # seconds of sampling AFTER the prefill returns
OUT=""
OS_AT_BOOT_BYTES=4934000000                     # docs/hardware-spark.md §The fixed cost, MEASURED
HOLD=""
TEST=0

die() { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)              PROFILE="${2:?--profile needs the arm, e.g. fast}"; shift ;;
    --host)                 HOST="${2:?--host needs the box name}"; shift ;;
    --container)            CONTAINER="${2:?--container needs the engine container name}"; shift ;;
    --base-url)             BASE_URL="${2:?--base-url needs the endpoint}"; shift ;;
    --tokens)               TOKENS="${2:?--tokens needs a token count}"; shift ;;
    --interval)             INTERVAL="${2:?--interval needs seconds}"; shift ;;
    --window)               WINDOW="${2:?--window needs seconds}"; shift ;;
    --tail)                 TAIL="${2:?--tail needs seconds}"; shift ;;
    --out)                  OUT="${2:?--out needs the evidence directory}"; shift ;;
    --os-at-boot-bytes)     OS_AT_BOOT_BYTES="${2:?--os-at-boot-bytes needs bytes}"; shift ;;
    --declared-hold-bytes)  HOLD="${2:?--declared-hold-bytes needs bytes}"; shift ;;
    --self-test)            TEST=1 ;;
    *)                      die "unknown arg $1 — see the Usage block" 2 ;;
  esac
  shift
done
OUT="${OUT:-$REPO/spark/reports/hd494-rest-floor}"

# Rule 0, FIRST: before ssh, before the log file, before anything is read. A spark-served
# session IS the traffic whose dip it would be sampling — and `usable` is exactly the gauge
# that traffic moves.
# `--self-test` is the one exempt arm: it is fixture-only by construction (the transport, the
# sample stream, the prefill and the profile leg are each replaceable, and an arm of the test
# asserts that no unlisted command can pass as a read), so refusing it would make the refusal
# untestable from the very seat that needs the proof.
if [ "$TEST" != "1" ] && { [ "${PI_PROVIDER:-}" = "spark" ] || printf '%s' "${PI_MODEL:-}" | grep -q '^spark/'; }; then
  printf 'ERROR: Rule 0 — this session is served by spark (PI_PROVIDER=%s PI_MODEL=%s), so it may\n' \
    "${PI_PROVIDER:-unset}" "${PI_MODEL:-unset}" >&2
  printf '       take NO timed number, and this driver both samples a window and drives load\n' >&2
  printf '       through that engine. Run it from an externally-served session on the designated\n' >&2
  printf '       runner station (the WSL Debian seat: prompt-laptop-wsl.md §0/§1, docs/orchestration.md §4).\n' >&2
  exit 3
fi

# <hostname>/agent:<PI_MODEL> — run-scenario.sh's stamp, so a leg taken off-station stays
# identifiable in the evidence afterwards instead of being remembered.
client_stamp() {
  printf '%s/%s' "${BENCH_CLIENT:-$(hostname -s 2>/dev/null || echo unknown)}" \
    "agent:${PI_MODEL:-none}" | tr -d ','
}

# One log per ATTEMPT: a retry gets a new name, never the previous attempt's file.
attempt_log() {
  local dir="${HD494_LOG_DIR:-/tmp}" n=1 path
  path="$dir/hd494-$1-$(date +%H%M).log"
  while [ -e "$path" ]; do
    path="$dir/hd494-$1-$(date +%H%M).$n.log"
    n=$((n + 1))
  done
  printf '%s' "$path"
}

# The ONE door to the far side. Everything sent through it is a read; --self-test intercepts
# it here, so the fixture run exercises the real command strings.
host_read() {
  local cmd="$1"
  if [ -n "${HD494_SSH_CMD:-}" ]; then
    printf '%s\n' "$cmd" | $HD494_SSH_CMD
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$cmd"
  fi
}

# The far-side sample loop: ONE ssh session, one line per second. Opening a session per sample
# would be ~60 handshakes a minute on a box under prefill — the sampling would become the load.
# MemTotal rides along because the ledger's first term must come from THIS box, not from a doc.
# A read that loses MemAvailable or CmaFree prints MISSING instead of a zero: the gauge cannot
# be formed from half a read, and a silent zero would print a floor that is not there.
SAMPLE_SNIPPET='END=$(( $(date +%s) + @DUR@ )); while :; do T=$(date +%s); [ "$T" -ge "$END" ] && break; L=$(awk '"'"'/^MemTotal:/{t=$2+0} /^MemAvailable:/{a=$2+0; ha=1} /^CmaFree:/{c=$2+0; hc=1} END{ if (!ha || !hc) { print "0 0 0 MISSING"; exit } printf "%d %d %d ok", t, a, c }'"'"' /proc/meminfo); printf "%s\t%s\t%s\n" "$T" "$(date -u +%FT%TZ)" "$L"; sleep @INTERVAL@; done'

# profile_leg — the probe's LOCAL leg: repo only, no bearer, no HTTP, no network.
profile_leg() {
  if [ -n "${HD494_PROFILE_LEG_FILE:-}" ]; then cat "$HD494_PROFILE_LEG_FILE"
  elif hl_python; then "${HL_PYTHON[@]}" "$REPO/scripts/bench/spark-llm-probe.py" profile "$PROFILE"; fi
}

leg_max_len() { printf '%s\n' "$1" | awk '$1 == "max_model_len" { print $3; exit }'; }   # `  max_model_len  = 262144`
# leg_hold — the DECLARED device hold (fixed_cost + pool, resolved per profile by the probe), so
# the ledger's hold term comes from IaC and can never be an operator-typed number.
leg_hold() { printf '%s\n' "$1" | awk '/device hold/ { for (i = 1; i <= NF; i++) if ($i == "=") { gsub(/,/, "", $(i + 1)); print $(i + 1); exit } }'; }

# emit_csv <stream tsv> <csv> <prefill start epoch> <prefill end epoch> — one row per sample.
# The phase column is what makes the file readable afterwards: a floor found in `rest-after`
# answers a different question than one found inside the prefill.
emit_csv() {
  awk -F'\t' -v ps="$3" -v pe="$4" '
    BEGIN { print "epoch,utc,phase,mem_total_kib,mem_available_kib,cma_free_kib,usable_gib" }
    NF >= 6 && $6 == "ok" {
      u = ($4 - $5) / 1048576
      ph = ($1 + 0 < ps + 0) ? "rest-before" : (($1 + 0 <= pe + 0) ? "prefill" : "rest-after")
      printf "%s,%s,%s,%s,%s,%s,%.2f\n", $1, $2, ph, $3, $4, $5, u
    }' "$1" > "$2"
}

# csv_summary <csv> — the whole window's arithmetic in one pass, printed as key=value lines.
csv_summary() {
  awk -F',' '
    NR > 1 {
      n++
      if (n == 1 || $7 + 0 < min) min = $7 + 0
      if ($3 == "prefill") { pn++; if (pn == 1 || $7 + 0 < pmin) pmin = $7 + 0 }
      if (mt == 0) mt = $4 + 0
    }
    END { printf "samples=%d\nprefill_n=%d\nmin=%.2f\nmin_prefill=%s\ntotal_kib=%d\n",
                  n, pn + 0, min, (pn ? sprintf("%.2f", pmin) : "n/a"), mt }' "$1"
}

run_main() {
  local client tag raw tsv csv prefile leg running hold tokens start_e end_e pre_rc
  local summary sample_n prefill_n min_gib min_prefill total_kib ledger_gib delta_gib verdict md i

  client="$(client_stamp)"
  tag="$(date -u +%Y%m%d-%H%M%S)"
  raw="$OUT/raw"
  mkdir -p "$raw"
  tsv="$raw/usable-$tag-stream.tsv"
  csv="$OUT/usable-$tag.csv"
  prefile="$raw/usable-$tag-prefill.txt"
  printf '>>> usable-sampler profile=%s host=%s container=%s interval=%s s client=%s\n' \
    "$PROFILE" "$HOST" "$CONTAINER" "$INTERVAL" "$client"

  # Identity FIRST, then the ledger terms: both are cheap and both invalidate the whole run.
  running=$(host_read "docker inspect -f '{{.State.Running}}' $CONTAINER" 2>/dev/null || echo false)
  if [ "$running" != "true" ]; then
    printf 'ERROR: container %s is not running on %s, so there is no engine to prefill.\n' "$CONTAINER" "$HOST" >&2
    printf '       The name is IaC spark_vllm_container -> spark_llm_profiles[spark_llm_profile].container;\n' >&2
    printf '       pass --container <name> for the arm actually serving. Nothing was captured.\n' >&2
    exit 6
  fi

  leg="$(profile_leg)" || die "the probe's local profile leg failed — the ledger's declared hold cannot be read from IaC" 1
  hold="${HOLD:-$(leg_hold "$leg")}"
  [ -n "$hold" ] || die "the profile leg for $PROFILE carries no 'device hold' line, so the declared hold term is missing and the delta would be arithmetic on nothing" 1
  printf '%s\n' "$leg" > "$raw/usable-$tag-profile-leg.txt"
  tokens="${TOKENS:-$(leg_max_len "$leg")}"
  [ -n "$tokens" ] || die "no max_model_len for $PROFILE in the profile leg, so the prefill depth is unknown — pass --tokens" 1
  printf '>>> declared hold %s B (from IaC) · OS@boot %s B (recorded) · prefill depth %s tokens\n' \
    "$hold" "$OS_AT_BOOT_BYTES" "$tokens"

  # --- the sampler, held across the whole window -------------------------------------------
  if [ -n "${HD494_SAMPLE_FILE:-}" ]; then
    cat "$HD494_SAMPLE_FILE" > "$tsv" &
  else
    local cmd="${SAMPLE_SNIPPET//@DUR@/$((WINDOW + 60))}"
    cmd="${cmd//@INTERVAL@/$INTERVAL}"
    host_read "$cmd" > "$tsv" 2> "$raw/usable-$tag-sampler.err" &
  fi
  local sampler_pid=$!
  # The FILE decides, not the process: a fast sampler is reaped before anyone can ask whether it
  # is alive, and a reaped child looks dead while its output sits complete on disk.
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(grep -c . "$tsv" 2>/dev/null || true)" -ge 1 ] && break
    sleep 1
  done
  [ "$(grep -c . "$tsv" 2>/dev/null || true)" -ge 1 ] \
    || die "the sampler produced no row at all, so there is nothing to compute (far-side stderr: $raw/usable-$tag-sampler.err)" 1
  if grep -q 'MISSING' "$tsv"; then
    die "the far-side read lost MemAvailable or CmaFree — usable cannot be formed, and a missing field is not a zero" 1
  fi

  # --- the heavy prefill, inside the window -------------------------------------------------
  start_e="$(date +%s)"
  if [ -n "${HD494_PREFILL_CMD:-}" ]; then
    printf '>>> prefill: %s\n' "$HD494_PREFILL_CMD"
    $HD494_PREFILL_CMD > "$prefile" 2>&1 && pre_rc=0 || pre_rc=$?
  else
    printf '>>> prefill: %s scripts/bench/spark-llm-probe.py --base-url %s ctx %s\n' "${HL_PYTHON[*]}" "$BASE_URL" "$tokens"
    "${HL_PYTHON[@]}" "$REPO/scripts/bench/spark-llm-probe.py" --base-url "$BASE_URL" ctx "$tokens" \
      > "$prefile" 2>&1 && pre_rc=0 || pre_rc=$?
  fi
  end_e="$(date +%s)"
  printf '>>> prefill exit %s over %s s (recorded, not repaired)\n' "$pre_rc" "$((end_e - start_e))"

  sleep "$TAIL"                       # the recovery is the half that says floor vs transient
  kill "$sampler_pid" 2>/dev/null || true
  wait "$sampler_pid" 2>/dev/null || true          # the remote `timeout` may have won the race

  # --- the CSV, then the arithmetic ---------------------------------------------------------
  emit_csv "$tsv" "$csv" "$start_e" "$end_e"
  summary="$(csv_summary "$csv")"
  sample_n="$(printf '%s\n' "$summary" | sed -n 's/^samples=//p')"
  prefill_n="$(printf '%s\n' "$summary" | sed -n 's/^prefill_n=//p')"
  min_gib="$(printf '%s\n' "$summary" | sed -n 's/^min=//p')"
  min_prefill="$(printf '%s\n' "$summary" | sed -n 's/^min_prefill=//p')"
  total_kib="$(printf '%s\n' "$summary" | sed -n 's/^total_kib=//p')"
  [ "${sample_n:-0}" -ge 2 ] || die "only ${sample_n:-0} usable sample(s) survived the parse — a two-point window cannot hold a floor" 1
  [ "${total_kib:-0}" -gt 0 ] || die "no MemTotal reached the CSV, so the ledger's first term is unknown" 1

  ledger_gib=$(awk -v k="$total_kib" -v os="$OS_AT_BOOT_BYTES" -v h="$hold" \
    'BEGIN{printf "%.2f", (k * 1024 - os - h) / 1073741824}')
  delta_gib=$(awk -v m="$min_gib" -v l="$ledger_gib" 'BEGIN{printf "%.2f", m - l}')
  verdict=$(awk -v d="$delta_gib" 'BEGIN{ if (d < 0) printf "the ledger is %.2f GiB OPTIMISTIC against this window", -d
                                                else printf "the ledger is %.2f GiB PESSIMISTIC against this window", d }')

  md="$OUT/usable-$tag.md"
  {
    printf '# HD-494 — the 1 s `usable` floor across one heavy prefill (%s)\n\n' "$tag"
    printf 'Stamps: client `%s` · host `%s` · container `%s` · profile `%s` · prefill exit `%s`\n' "$client" "$HOST" "$CONTAINER" "$PROFILE" "$pre_rc"
    printf 'Cadence `%s s` · sampler capped at `%s s` · `%s s` of sampling after the prefill · prefill depth `%s tokens`.\n\n' "$INTERVAL" "$((WINDOW + 60))" "$TAIL" "$tokens"
    printf '## The arithmetic\n\n'
    printf 'Form: docs/hardware-spark.md §The GLOBAL ceiling, as used by `RESULTS.md` §5. It prices the gap; it decides nothing.\n\n'
    printf '· `MemTotal`, read from this box: %s KiB = %s B\n' "$total_kib" "$(awk -v k="$total_kib" 'BEGIN{printf "%.0f", k * 1024}')"
    printf '· `OS@boot`, the recorded constant (overridable with --os-at-boot-bytes): %s B — docs/hardware-spark.md §The fixed cost, MEASURED\n' "$OS_AT_BOOT_BYTES"
    printf '· declared device hold for `%s`, read from IaC through the probe'"'"'s local leg: %s B\n' "$PROFILE" "$hold"
    printf '· **ledger rest prediction: %s GiB**\n' "$ledger_gib"
    printf '· **measured floor over this window: %s GiB** (%s samples at %s s; inside the prefill phase itself: %s GiB)\n' "$min_gib" "$sample_n" "$INTERVAL" "$min_prefill"
    printf '· **delta: %s GiB** — %s. Which floor that means (CRIT vs WARN) is the owner'"'"'s call, not this file'"'"'s.\n\n' "$delta_gib" "$verdict"
    printf 'Samples falling inside the prefill window: %s of %s.\n\n' "$prefill_n" "$sample_n"
    printf '## Files\n\n'
    printf '· every sample: [`usable-%s.csv`](usable-%s.csv) — the `phase` column splits rest from prefill\n' "$tag" "$tag"
    printf '· far-side stream verbatim: `raw/usable-%s-stream.tsv` · profile leg as read: `raw/usable-%s-profile-leg.txt` · prefill stdout verbatim: `raw/usable-%s-prefill.txt`\n' "$tag" "$tag" "$tag"
  } > "$md"

  printf '>>> %s samples · floor %s GiB · ledger prediction %s GiB · delta %s GiB (%s)\n' \
    "$sample_n" "$min_gib" "$ledger_gib" "$delta_gib" "$verdict"
  [ "${prefill_n:-0}" -gt 0 ] || printf '>>> WARNING: no sample fell inside the prefill window, so this prices rest, not a prefill\n'
  printf '>>> report: %s\n>>>     csv: %s\n>>>     raw: %s\n' "$md" "$csv" "$raw"
  [ "$pre_rc" = 0 ] || { printf '>>> the prefill leg exited %s — see %s\n' "$pre_rc" "$prefile"; exit 4; }
}

# ---------------------------------------------------------------------------
# --self-test — fixtures only. Nothing here sshes, nothing reads the vault, nothing
# reaches an engine: on a spark-served seat the refusal and the read-only contract
# have to be PROVEN, not asserted.
# ---------------------------------------------------------------------------
run_self_test() {
  local t fails=0 out rc p1 p2 cmdlog bad_cmd csvrow summary
  t="$(mktemp -d)"
  local self="$SELF_DIR/$(basename "${BASH_SOURCE[0]}")"
  mkdir -p "$t/bin" "$t/out" "$t/logs"
  cmdlog="$t/commands.log"; : > "$cmdlog"

  # One fixture PAIR, hand-valued (a test that recomputes its own expectation cannot fail):
  #   MemTotal   127,532,360 KiB        = 130,593,136,640 B   (this box's measured constant)
  #   declared hold                     = 112,130,000,000 B   (`fast`: 92.13e9 + 20e9)
  #   OS@boot                           =   4,934,000,000 B
  #   => ledger rest 13,529,136,640 B   = 12.60 GiB
  #   the dip row: (12,330,000 − 30,000) = 12,300,000 KiB     = 11.73 GiB
  #   => delta 11.73 − 12.60 = −0.87 GiB — the same optimism §5 of the report derived
  cat > "$t/samples.tsv" <<'FIX'
1792000001	2026-10-22T09:00:01Z	127532360	17000000	130000	ok
1792000002	2026-10-22T09:00:02Z	127532360	12330000	30000	ok
1792000003	2026-10-22T09:00:03Z	127532360	12600000	40000	ok
1792000004	2026-10-22T09:00:04Z	127532360	16900000	130000	ok
FIX
  cat > "$t/leg.txt" <<'FIX'
local leg (profile) — repo only, no bearer read, no HTTP
  max_model_len         = 262144
  kv_cache_memory       = 20000000000
  fixed_cost_bytes      = 92130000000
  device hold           = 112,130,000,000 B vs ceiling 112,700,000,000 B  (per-profile)
FIX
  printf 'local leg (profile) — no fixed_cost_bytes declared\n' > "$t/leg-broken.txt"

  cat > "$t/bin/fake-host" <<'FIX'
#!/usr/bin/env bash
# Answers ONE far-side command read from stdin. "Unhandled" FAILS: a command the fixture
# has not been told is a read must never pass as one.
cmd="$(cat)"
printf '%s\n' "$cmd" >> "${FAKE_LOG:?}"
case "$cmd" in
  *docker\ inspect*) printf '%s\n' "${FAKE_RUNNING:-true}" ;;
  */proc/meminfo*)
    for s in 1 2 3; do
      printf '%s\t%s\t127532360\t16900000\t130000\tok\n' "$((1792000000 + s))" "2026-10-22T09:00:0${s}Z"
      sleep 0.2
    done ;;
  *) printf 'fake-host: unhandled command: %s\n' "$cmd" >&2; exit 9 ;;
esac
FIX
  chmod +x "$t/bin/fake-host"

  ok()  { printf '  ok:   %s\n' "$1"; }
  bad() { printf '  FAIL: %s\n' "$1"; fails=$((fails + 1)); }
  want() { if printf '%s\n' "$out" | grep -qF -- "$1"; then ok "$2"; else bad "$2 (wanted \"$1\")"; fi; }

  export FAKE_LOG="$cmdlog"
  export HD494_SSH_CMD="$t/bin/fake-host" HD494_LOG_DIR="$t/logs"
  export HD494_PREFILL_CMD="printf 'prefill fixture\n'\n" HD494_PROFILE_LEG_FILE="$t/leg.txt"
  export HD494_SAMPLE_FILE="$t/samples.tsv"
  export PI_PROVIDER="other" PI_MODEL="other/model-not-spark"

  echo "self-test 1: a spark-served env refuses, before any read and before any file"
  out="$(PI_PROVIDER=spark PI_MODEL=spark/qwen3.8-flash-next bash "$self" --out "$t/out" --tail 0 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 3 ] && ok "exits 3 under PI_PROVIDER=spark" || bad "spark-served rc=$rc, want 3"
  want "Rule 0" "the refusal names Rule 0"
  [ "$(wc -l < "$cmdlog")" -eq 0 ] && ok "no host command was sent" || bad "the refusal came after a host read"
  [ "$(ls -1 "$t/logs" | grep -c 'hd494-' || true)" -eq 0 ] \
    && ok "no attempt log was created either" || bad "the refusal still opened an attempt log"

  echo "self-test 2: the parser — one CSV row per sample, both fields, three phases"
  : > "$cmdlog"
  out="$(bash "$self" --out "$t/out" --tail 0 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 0 ] && ok "the fixture run completes" || bad "fixture run rc=$rc: $(printf '%s' "$out" | tail -3)"
  csvrow="$(ls -1 "$t/out"/usable-*.csv | tail -1)"
  [ "$(head -1 "$csvrow")" = "epoch,utc,phase,mem_total_kib,mem_available_kib,cma_free_kib,usable_gib" ] \
    && ok "one field per column, header first" || bad "CSV header reads '$(head -1 "$csvrow")'"
  [ "$(awk -F',' 'NR == 3 {print $7}' "$csvrow")" = "11.73" ] \
    && ok "the dip row parses to 11.73 GiB ((12330000-30000)/1048576)" \
    || bad "the dip row printed $(awk -F',' 'NR == 3 {print $7}' "$csvrow"), want 11.73"
  [ "$(awk -F',' 'NR > 1 {print $4}' "$csvrow" | sort -u | wc -l)" -eq 1 ] \
    && ok "MemTotal rides along on every row" || bad "MemTotal is not carried per row"
  emit_csv "$t/samples.tsv" "$t/phases.csv" 1792000002 1792000003
  [ "$(awk -F',' 'NR > 1 {print $3}' "$t/phases.csv" | sort -u | tr '\n' ' ')" = "prefill rest-after rest-before " ] \
    && ok "the phase column splits rest-before / prefill / rest-after" \
    || bad "phases read: $(awk -F',' 'NR > 1 {print $3}' "$t/phases.csv" | sort -u | tr '\n' ' ')"
  printf '1792000001\t2026-10-22T09:00:01Z\t127532360\t0\t0\tMISSING\n' > "$t/bad.tsv"
  out="$(HD494_SAMPLE_FILE="$t/bad.tsv" bash "$self" --out "$t/out" --tail 0 2>&1)" && rc=0 || rc=$?
  [ "$rc" != 0 ] && ok "a stream that lost a field is refused, never zero-filled" || bad "a MISSING stream was accepted"
  want "CmaFree" "the refusal names the gauge it could not form"

  echo "self-test 3: the delta arithmetic against the fixture pair (hand-valued)"
  summary="$(csv_summary "$csvrow")"
  [ "$(printf '%s' "$summary" | sed -n 's/.*total_kib=//p')" = "127532360" ] \
    && ok "MemTotal term 127532360 KiB" || bad "MemTotal term: $summary"
  [ "$(awk -v k=127532360 -v os=4934000000 -v h=112130000000 'BEGIN{printf "%.2f", (k*1024-os-h)/1073741824}')" = "12.60" ] \
    && ok "hand-check: the ledger rest prediction is 12.60 GiB" || bad "hand-check of the prediction failed"
  out="$(bash "$self" --out "$t/out" --tail 0 2>&1)"
  want "delta -0.87 GiB" "the summary line prints the delta 11.73 − 12.60 = −0.87 GiB"
  out="$(cat "$(ls -1 "$t/out"/usable-*.md | tail -1)")"
  want "ledger rest prediction: 12.60 GiB" "the report states the prediction ((130593136640 − 4934000000 − 112130000000)/1073741824)"
  want "measured floor over this window: 11.73 GiB" "the report states the measured floor 11.73 GiB"
  want "delta: -0.87 GiB" "the report states the delta 11.73 − 12.60 = −0.87 GiB"
  want "OPTIMISTIC" "a negative delta is called OPTIMISTIC, not a rounding error"

  echo "self-test 4: a declared hold that cannot be read from IaC is refused"
  out="$(HD494_PROFILE_LEG_FILE="$t/leg-broken.txt" bash "$self" --out "$t/out" --tail 0 2>&1)" && rc=0 || rc=$?
  [ "$rc" != 0 ] && ok "no 'device hold' line -> refused" || bad "a profile leg with no declared hold was accepted"
  want "device hold" "the refusal names the term it could not read"

  echo "self-test 5: the box route is sampled, every command is a read, and two attempts write two logs"
  : > "$cmdlog"
  out="$(HD494_SAMPLE_FILE= bash "$self" --out "$t/out" --tail 0 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 0 ] && ok "the transport path runs against the fixture transport" || bad "box-route run rc=$rc: $(printf '%s' "$out" | tail -3)"
  grep -q '/proc/meminfo' "$cmdlog" && ok "the 1 s sampler reached the box through the door" || bad "the sampler command never reached the box"
  p1="$(printf '%s\n' "$out" | sed -n 's/^>>> attempt log: //p' | head -1)"
  out="$(bash "$self" --out "$t/out" --tail 0 2>&1)"; p2="$(printf '%s\n' "$out" | sed -n 's/^>>> attempt log: //p' | head -1)"
  [ -n "$p1" ] && [ -n "$p2" ] && [ "$p1" != "$p2" ] && ok "two attempts wrote two files" || bad "both attempts wrote $p1"
  bad_cmd="$(grep -nE 'docker (restart|stop|rm|kill)|systemctl|reboot|shutdown|ansible|spark_llm_profile[[:space:]]*:|drop_caches|sed -i' "$cmdlog" || true)"
  [ -z "$bad_cmd" ] && ok "no mutate verb in $(wc -l < "$cmdlog") command(s)" || bad "a mutate verb reached the box: $bad_cmd"

  rm -rf "$t"
  [ "$fails" = 0 ] && { echo "SELF-TEST OK"; return 0; }
  echo "SELF-TEST FAILED: $fails assertion(s)"; return 1
}

if [ "$TEST" = 1 ]; then run_self_test; exit $?; fi

LOG="$(attempt_log "$PROFILE")"
printf '>>> attempt log: %s\n' "$LOG"
# pipefail makes the pipeline's status the run's status: writing the log never hides a failure.
run_main "$@" 2>&1 | tee -a "$LOG"
