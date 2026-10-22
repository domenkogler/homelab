#!/usr/bin/env bash
# ============================================================================
# needle-window.sh — HD-376's ONE act: the needle test for EVERY profile in the
# catalogue, each at the depth THAT profile serves.
#
# WHY A DRIVER AND NOT A SENTENCE IN A ROW. The row says "needle-test EVERY profile
# at the depth it will serve — a pass at 32k is not a pass at 262k". A row's tail binds
# exactly as far as someone remembers it, so the picking of a depth has to be a program.
# Three traps are encoded here instead of being remembered:
#
#   1. DEPTH IS PER PROFILE, NOT PER RUN. The plan comes out of the catalogue through the
#      probe's OWN legs (`catalogue()` / `servable()` / `active_profile()` in
#      spark-llm-probe.py), so the depth a profile is needle-tested at is that profile's own
#      `max_model_len`, never a number typed into a command line. The fixture catalogue holds
#      three different windows and the self-test asserts all three depths reach the probe, and
#      that adding a profile to the catalogue changes the plan with no edit in this file:
#      "derived, not typed" is a CHECKED property.
#   2. 262,144 IS THE SERVABLE CEILING AND "273k" IS NOT A CONTEXT. 262,144 is
#      `--max-model-len` == the checkpoint's `max_position_embeddings` — a boot gate the engine
#      answers 400 past, not an allocation. ~268–275k is KV POOL CAPACITY IN TOKEN SLOTS summed
#      across concurrent sequences, and 273 GB/s is LPDDR5x bandwidth; neither is a client value
#      (docs/harness-pi-engines.md §3). Any depth above 262,144 is REFUSED with exit 5 and that
#      reason — including a catalogue profile that declares one, refused per row and never
#      silently clamped, because above the ceiling needs YaRN rope scaling AND a fresh needle
#      test: a decision, not a flag.
#   3. THE >=120k CORRUPTION TRAP RIDES IN THE REPORT HEADER. On sm_12x the QSA decode path
#      through XQA corrupts long-context requests WHILE ANSWERING HTTP 200 (sglang#36806 /
#      #36845, spark/BENCHMARK-PLAN.md §Correctness trap). HTTP 200 with a big `prompt_tokens`
#      is exactly the shape that trap is invisible in, so a depth pass is always printed beside
#      this line, never instead of it.
#
# WHAT THE ACT RUNS for a profile the box is actually serving, at that profile's depth:
#   · the existing needle/depth probe, REPS times (gate 5 asks 3/3): `spark-llm-probe.py …
#     ctx <depth>` — the probe that already plants a NEEDLE code word in a deep prompt and reads
#     `prompt_tokens` back. Reused, not reinvented. A leg counts as PASS-DEPTH on HTTP 200 AND
#     `prompt_tokens` >= 80 % of the ask, which is gate 3's own bar and the highest the probe can
#     construct (it sizes its body to 0.9 × 0.9 of the ask); a higher bar here would be a bar no
#     real run can clear, i.e. a permanent false FAIL — see DEPTH_FLOOR_FRACTION.
#   · `/metrics` at both ends of the window, so "no preemption" (gate 3) is a number in the
#     report and not a hope. That half is a counter READ, legal from any session.
#   · ONE timed leg through `run-scenario.sh … S1-N` at 90 % of ctx on the box, stamped
#     `--profile <name> --client <hostname>/agent:<PI_MODEL>` — the record that makes a depth leg
#     quotable afterwards (its `req_ok_delta` proves the window was the leg's own). `--no-window`
#     skips it.
# The token-subsequence RECALL judgement (docs/spark-llm-profiles.md) is made with the engine's
# own tokenizer inside the container and NO landed instrument carries it, so this driver does not
# fake one: `http=200 prompt_tokens=…` proves the window was HELD, not that the needle came back,
# and the report says so in the same breath as the verdict.
#
# WHICH PROFILE A RESULT BELONGS TO IS READ, NOT ASSUMED. One container serves one profile at a
# time and a flip re-creates `spark-ai` (a ~20 min boot), so most rows in a plan cannot have run
# in this window. This driver is READ-ONLY: it never converges and never recycles the engine. A
# row whose profile is not the one `host_vars` says is live prints NOT-SERVED with the exact
# detached flip command an owner runs, and `--profile <name>` naming a profile the box is not
# serving exits 4 rather than attributing someone else's engine to it. A live engine whose argv
# depth disagrees with the profile's declared one is DRIFT and its legs do not run. Attributing a
# needle result to the wrong profile is the same defect as a typed depth, one level up.
#
# RULE 0 (spark/llm-profiles/README.md Rule 0, todo-table.md §C rule 2): A NEEDLE TEST ISSUES
# INFERENCE REQUESTS AGAINST THE ENGINE. A session whose own model is served by spark is that
# engine's client while measuring it, and deep legs contend for the very pool being probed — so
# this script REFUSES before its first read and before it opens a file (`PI_PROVIDER=spark` or
# `PI_MODEL=spark/…` exits 3, naming the rule). Take the act from an externally-served session on
# the designated runner station, the WSL Debian seat (docs/orchestration.md §4, todo-table.md §C
# rule 9, prompt-laptop-wsl.md §1). The run is stamped <hostname>/agent:<PI_MODEL>, the shape
# run-scenario.sh writes into the results CSV's `client` column, so the seat is checkable after.
# The contrast that decides which sibling script carries no guard at all: `/metrics`, `docker
# inspect` and a `config.json` produce no timed number and no inference call and stay legal from
# any seat — see snapshot-metrics.sh and text-only-preflight.sh beside this file.
#
# Usage
#   scripts/bench/spark/needle-window.sh [--profile NAME …] [--depth N] [--reps 3]
#       [--base-url URL] [--host spark] [--bench-dir DIR] [--out DIR] [--no-window]
#       [--dry-run] [--self-test]
#
#   --profile     restrict the run to one (or a few) catalogue names. A name outside the
#                 catalogue is a usage error, and a named profile the box is NOT serving exits 4
#                 — that is the point of naming it.
#   --depth       override the depth for every profile named; refused above 262,144 (exit 5).
#                 For a YaRN arm or a "does it still hold at 32k" check, never a way to skip
#                 reading the profile's own window.
#   --reps        attempts per profile (default 3 — gate 5's 3/3).
#   --base-url    the endpoint the clients use. Default https://llm.ts.kogler.si/v1, reachable
#                 from the runner station; http://localhost:8000/v1 is on-box only. The bearer is
#                 read by the probe from 1Password `spark-llm_api`; it never passes through this
#                 file and only its LENGTH is ever printed.
#   --bench-dir   where run-scenario.sh lives ON THE BOX (the copy the deployment manual runs:
#                 /home/ansible-admin/bench). The window leg is the only far-side command here
#                 that is not a read, and --no-window is the switch that skips it.
#   --out         evidence dir. Default <repo>/spark/reports/hd376-needle-<UTC date>, each run
#                 under its own raw/<UTC tag>/ so a fresh run never lands on a stale one.
#
# A full sweep is minutes per profile at 235k+ prefill (cold prefill is NVMe-bound), so run it
# detached: `nohup … > /tmp/… 2>&1 &`, then poll the attempt logs.
#
# Fixture hooks — what keeps --self-test off the box and off the vault (and why it is the one arm
# Rule 0 does not have to refuse):
#   NEEDLE_SSH_CMD    command that receives each far-side command on stdin
#   NEEDLE_PROBE_CMD  replaces the probe invocation for the LEGS (fixture use only; the PLAN
#                     always comes from the real probe module reading $REPO, so a fixture cannot
#                     flatter the derivation it is supposed to be testing)
#   NEEDLE_LOG_DIR    where the per-attempt hd376-<profile>-<HHMM>.log files are created
#   NEEDLE_TOKEN_ENV  passed through as the probe's --token-env (fixtures set it; a real run
#                     leaves it unset so the probe reads 1Password)
#
# Exit: 0 every profile in the plan got its verdict · 1 a leg produced nothing parseable, or a
#         profile's needle FAILED ·
#       2 usage (unknown profile, bad depth, empty catalogue) ·
#       3 RULE 0 — this session is served by spark ·
#       4 ATTRIBUTION REFUSED — the box is not serving the profile named, so no leg of this run
#         may be recorded against it ·
#       5 CEILING REFUSED — a depth above 262,144 was asked for ·
#       6 the engine container is not running (measured, not assumed)
# A FAIL verdict is a RESULT, not a crash: the report is what this driver is judged on, and the
# probe's own exit code is recorded beside every attempt.
# ============================================================================
set -euo pipefail
# Depths and prompt_tokens land in a markdown table and inside an equality test. Under an sl_SI
# locale awk's "%.2f" prints 15,99, which splits a field and never equals the hand-valued fixture
# it is tested against. The output format is fixed, not the environment's.
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root FOUND, never assumed from a depth (lib/repo-root.sh): the evidence dir lives under
# <root>/spark/reports, and a wrong depth writes evidence nobody finds.
_hl_d="$SELF_DIR"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"

CEILING=262144                 # --max-model-len ceiling = the checkpoint's max_position_embeddings
WINDOW_FRACTION=90             # the S1-N window leg: ONE session at ~90 % of ctx (run-scenario.sh)
DEPTH_FLOOR_FRACTION=80        # gate 3: the depth leg passes at prompt_tokens >= 80 % of the ask.
                               # NOT 90: spark-llm-probe.py sizes its body to 0.9 x 0.9 of the ask
                               # (measured 5.2 chars/token), so it can only ever reach ~81 % — a
                               # floor above that is unsatisfiable by construction and would turn
                               # every honest run into a false FAIL. An unreachable bar is not rigor.
KV_SLOTS_QUOTE='273k'          # the number the row keeps quoting — a slot projection, not a context
CORRUPTION_TRAP='sglang#36806 / sglang#36845 (QSA decode via XQA on sm_12x, answers HTTP 200)'
PROBE="${NEEDLE_PROBE:-$SELF_DIR/../spark-llm-probe.py}"
# The legs' probe invocation. The fixture replaces it; a real run gets the probe beside here.
if [ -n "${NEEDLE_PROBE_CMD:-}" ]; then PROBE_CMD="$NEEDLE_PROBE_CMD"; else PROBE_CMD="python3 $PROBE"; fi

PROFILE_FILTER=""              # accumulated --profile values, newline separated
DEPTH_OVERRIDE=""
REPS=3
BASE_URL="${NEEDLE_BASE_URL:-https://llm.ts.kogler.si/v1}"
HOST="spark"
BENCH_DIR="/home/ansible-admin/bench"
OUT=""
WINDOW=1                       # 0 = --no-window
TEST=0
DRY=0
SELF_NAME="$(basename "${BASH_SOURCE[0]}")"

# Set by run_main; declared so `set -u` never meets them unset.
CLIENT="" TAG="" RAW="" ROWS="" PLAN_TSV=""

die() { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   [ $# -ge 2 ] || die "--profile needs a catalogue name, e.g. reasoning" 2
                 PROFILE_FILTER="$PROFILE_FILTER$2
"; shift ;;
    --depth)     [ $# -ge 2 ] || die "--depth needs a token count" 2; DEPTH_OVERRIDE="$2"; shift ;;
    --reps)      [ $# -ge 2 ] || die "--reps needs a count" 2; REPS="$2"; shift ;;
    --base-url)  [ $# -ge 2 ] || die "--base-url needs the endpoint" 2; BASE_URL="$2"; shift ;;
    --host)      [ $# -ge 2 ] || die "--host needs the box name" 2; HOST="$2"; shift ;;
    --bench-dir) [ $# -ge 2 ] || die "--bench-dir needs the on-box run-scenario.sh folder" 2
                 BENCH_DIR="$2"; shift ;;
    --out)       [ $# -ge 2 ] || die "--out needs the evidence directory" 2; OUT="$2"; shift ;;
    --no-window) WINDOW=0 ;;
    --dry-run)   DRY=1 ;;
    --self-test) TEST=1 ;;
    *)           die "unknown arg $1 — see the Usage block" 2 ;;
  esac
  shift
done
case "$REPS" in ''|*[!0-9]*) die "--reps wants a positive integer, got '$REPS'" 2 ;; esac
[ "$REPS" -ge 1 ] || die "--reps must be >= 1, got $REPS" 2
if [ -n "$DEPTH_OVERRIDE" ]; then
  case "$DEPTH_OVERRIDE" in ''|*[!0-9]*) die "--depth wants a token count, got '$DEPTH_OVERRIDE'" 2 ;; esac
fi

OUT="${OUT:-$REPO/spark/reports/hd376-needle-$(date -u +%Y%m%d)}"

# The ceiling guard, in ONE place, called for every depth this run could use.
refuse_ceiling() {
  local d="$1" why="$2"
  printf 'ERROR: CEILING REFUSED — %s asks for %s tokens, above the servable ceiling %s.\n' \
    "$why" "$d" "$CEILING" >&2
  printf '       262,144 is `--max-model-len` = the checkpoint'"'"'s max_position_embeddings: a\n' >&2
  printf '       boot gate the engine answers 400 past, not an allocation to be raised.\n' >&2
  printf '       The oft-quoted %s is KV POOL CAPACITY IN TOKEN SLOTS summed across concurrent\n' "$KV_SLOTS_QUOTE" >&2
  printf '       sequences, and 273 GB/s is LPDDR5x bandwidth. Neither is a client value.\n' >&2
  printf '       Above the ceiling needs VLLM_ALLOW_LONG_MAX_MODEL_LEN + YaRN rope scaling AND a\n' >&2
  printf '       fresh needle test — a decision, never a depth typed into a probe.\n' >&2
  printf '       Basis: docs/harness-pi-engines.md §3, docs/hardware-spark.md §Unified-memory budget.\n' >&2
  exit 5
}
if [ -n "$DEPTH_OVERRIDE" ] && [ "$DEPTH_OVERRIDE" -gt "$CEILING" ]; then
  refuse_ceiling "$DEPTH_OVERRIDE" "--depth"
fi

# ---------------------------------------------------------------------------
# THE GUARD. A needle test issues inference requests against the engine, so Rule 0 binds it.
# FIRST: before ssh, before the log file, before anything is read. `--self-test` is the one
# exempt arm: it is fixture-only by construction (the transport is NEEDLE_SSH_CMD, the legs are
# NEEDLE_PROBE_CMD, the catalogue is $REPO), so refusing it would make the refusal untestable
# from the very seat that needs the proof.
# ---------------------------------------------------------------------------
if [ "$TEST" != "1" ] && { [ "${PI_PROVIDER:-}" = "spark" ] || printf '%s' "${PI_MODEL:-}" | grep -q '^spark/'; }; then
  printf 'ERROR: Rule 0 — this session is served by spark (PI_PROVIDER=%s PI_MODEL=%s).\n' \
    "${PI_PROVIDER:-unset}" "${PI_MODEL:-unset}" >&2
  printf '       A needle test ISSUES REQUESTS AGAINST THE ENGINE: it would be measuring the pool\n' >&2
  printf '       while filling it, and its own tokens would land in the preemption and prefix-cache\n' >&2
  printf '       counters this act reads to prove the window was quiet.\n' >&2
  printf '       Basis: spark/llm-profiles/README.md Rule 0, todo-table.md §C rule 2.\n' >&2
  printf '       Run it from an externally-served session on the designated runner station\n' >&2
  printf '       (docs/orchestration.md §4, todo-table.md §C rule 9, prompt-laptop-wsl.md §1).\n' >&2
  printf '       /metrics, logs and `docker inspect` READS stay legal from any seat — see\n' >&2
  printf '       snapshot-metrics.sh and text-only-preflight.sh; this act is not one of them.\n' >&2
  exit 3
fi

client_stamp() {
  printf '%s/%s' "${BENCH_CLIENT:-$(hostname -s 2>/dev/null || echo unknown)}" \
    "agent:${PI_MODEL:-none}" | tr -d ','
}

# One log file per ATTEMPT (hd469-baseline.sh's shape): a retry inside the same minute gains .1,
# .2 …, because a retry that reopens the previous attempt's file truncates the only record of the
# attempt that failed.
attempt_log() {
  local dir="${NEEDLE_LOG_DIR:-/tmp}" profile="$1" n=1 path
  path="$dir/hd376-$profile-$(date +%H%M).log"
  while [ -e "$path" ]; do
    path="$dir/hd376-$profile-$(date +%H%M).$n.log"
    n=$((n + 1))
  done
  printf '%s' "$path"
}

# The ONE door to the far side. Everything sent through the read half is a read (docker inspect,
# /metrics); --self-test intercepts it here, which is what lets the fixture arms exercise the real
# command strings. The single non-read is the run-scenario.sh window leg, and --no-window skips it.
host_read() {
  local cmd="$1"
  if [ -n "${NEEDLE_SSH_CMD:-}" ]; then
    printf '%s\n' "$cmd" | $NEEDLE_SSH_CMD
  else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "$cmd"
  fi
}

STATE_SNIPPET="docker inspect -f '{{.State.Running}} {{.State.StartedAt}} restarts={{.RestartCount}}' @CONTAINER@"
ARGV_SNIPPET="docker inspect -f '{{join .Config.Cmd \" \"}}' @CONTAINER@"
METRICS_SNIPPET="curl -s --max-time 10 localhost:8000/metrics | grep -E 'num_preemptions_total|prefix_cache'"

# scrub_argv — removes the engine bearer from an argv dump AT THE POINT OF WRITE. The engine's own
# argv carries `--api-key`, and a raw capture of a running system holds its own credentials:
# spark/reports/hd489-overnight-20261006-0226/raw/b10-boot.txt is the published leak this rule
# came from. run-scenario.sh and gate6-couple.sh scrub for the same reason.
scrub_argv() { sed -E 's/(--api-key[= ])[^ "]+/\1<scrubbed>/g'; }

# engine_flag <argv> <flag> — one flag's value out of an argv dump, or empty.
engine_flag() {
  printf '%s\n' "$1" | tr ' ' '\n' \
    | awk -v f="$2" '{ if (prev == f) { print; exit } prev = $0 }' || true
}

# counter_sum <metrics text> <metric> — sum EVERY series of a labelled counter: prefix_cache_*
# carries labels, so picking one line reports a fraction of the truth (snapshot-metrics.sh's
# sumget() is the same rule for the same reason).
counter_sum() {
  printf '%s\n' "$1" | awk -v m="$2" '!/^#/ && $1 ~ "^"m"([ {]|$)" { s += $NF } END{printf "%.0f", s+0}'
}

pct_of()   { awk -v d="$1" -v p="$WINDOW_FRACTION"        'BEGIN{printf "%.0f", d*p/100}'; }
floor_of() { awk -v d="$1" -v p="$DEPTH_FLOOR_FRACTION"   'BEGIN{printf "%.0f", d*p/100}'; }

# row <profile> <verdict> <depth> <what the verdict rests on> <certified> <live> — one report
# row, NEWLINE-terminated on purpose: a verdict table that glues two profiles onto one line is a
# table where a depth belongs to the wrong profile, which is the exact error this driver exists
# to prevent.
row() {
  ROWS="${ROWS}$1|$2|$3|$4|$5|$6
"
}

# probe_cmd <depth> — the one needle/depth command this act issues, printed by --dry-run AND run
# by the legs from the same line, so the report and the wire cannot drift apart.
probe_cmd() {
  printf '%s --base-url %s%s ctx %s' "$PROBE_CMD" "$BASE_URL" \
    "${NEEDLE_TOKEN_ENV:+ --token-env $NEEDLE_TOKEN_ENV}" "$1"
}

# ---------------------------------------------------------------------------
# THE PLAN — derived, never typed. The profile set, each profile's own window, its container and
# which one host_vars would converge RIGHT NOW all come out of the probe's own legs, so an HD-489
# merge anchor cannot be probed as if it were a profile, a profile added to the catalogue appears
# in the plan with no edit here, and no depth in this file is a number a human wrote.
# ---------------------------------------------------------------------------
plan_tsv() {
  python3 - "$PROBE" <<'PY'
import importlib.util, sys

path = importlib.util.spec_from_file_location("spark_llm_probe", sys.argv[1])
if path is None or path.loader is None:
    sys.exit(f"ERROR: cannot load the profile probe at {sys.argv[1]}")
mod = importlib.util.module_from_spec(path)
path.loader.exec_module(mod)

cat = mod.catalogue()
active = mod.active_profile(cat)
for name, p in mod.servable(cat["spark_llm_profiles"]).items():
    print("\t".join(str(x) for x in (
        name, p.get("engine"), int(p["max_model_len"]), p.get("container"),
        "yes" if p.get("certified") else "no", "yes" if name == active else "no")))
PY
}

# The flip an OWNER runs between profiles — printed here, never executed. Re-pointing
# spark_llm_profile re-creates the engine container (~20 min boot), which is an owner-window act
# under todo-table.md §C rule 2, not a needle driver's to take.
flip_cmd() {
  printf 'cd %s && bash scripts/ansible/ansible-run.sh playbooks/spark.yml --limit spark \\\n' "$REPO"
  printf '      --tags docker_services,spark-ai -e spark_llm_profile=%s </dev/null > /tmp/converge-<epoch>.log 2>&1 &\n' "$1"
  printf '# an UNCERTIFIED arm also needs a per-run -e spark_llm_allow_uncertified=true, never a\n'
  printf '# committed value — spark/llm-profiles/README.md Rule 0 + gate 1.\n'
}

# one_attempt <profile> <depth> <n> — one needle/depth leg, into its own attempt log. Returns 0
# when the probe says HTTP 200 AND the prompt_tokens it read back reach gate 3's floor, 80 % of the
# depth asked for. An unparseable probe line is a hard error, never a zero.
one_attempt() {
  local profile="$1" depth="$2" n="$3" log out rc http pt want
  log="$(attempt_log "$profile")"
  want="$(floor_of "$depth")"
  printf '>>> attempt %s/%s profile=%s depth=%s (floor %s = %s%% of it) log=%s\n' \
    "$n" "$REPS" "$profile" "$depth" "$want" "$DEPTH_FLOOR_FRACTION" "$log"
  if [ "$DRY" = 1 ]; then
    printf '    (dry-run) %s\n' "$(probe_cmd "$depth")"
    return 0
  fi
  # shellcheck disable=SC2086  # PROBE_CMD is a word-separated command (the fixture hook)
  out="$($PROBE_CMD --base-url "$BASE_URL" ${NEEDLE_TOKEN_ENV:+--token-env "$NEEDLE_TOKEN_ENV"} ctx "$depth" 2>&1)" && rc=0 || rc=$?
  {
    printf '=== needle-window %s attempt %s/%s depth=%s client=%s probe-rc=%s\n' \
      "$profile" "$n" "$REPS" "$depth" "$CLIENT" "$rc"
    printf '%s\n' "$out"
  } > "$log"
  http="$(printf '%s\n' "$out" | grep -oE 'http=[0-9]+' | tail -1 | cut -d= -f2 || true)"
  pt="$(printf '%s\n' "$out" | grep -oE 'prompt=[0-9]+' | tail -1 | cut -d= -f2 || true)"
  [ -n "$http" ] || die "the probe printed no http= field for $profile at $depth (rc $rc) — a failed read is not a zero, and no needle result may be recorded from it" 1
  [ -n "$pt" ] || die "the probe printed no prompt= field for $profile at $depth (rc $rc) — the depth a needle actually ran at is the only number that makes the result mean anything" 1
  printf '%s\n' "$out" > "$RAW/$profile-attempt-$n.probe.txt"
  if [ "$http" = 200 ] && [ "$pt" -ge "$want" ]; then
    printf '    PASS-DEPTH  http=%s prompt_tokens=%s (asked %s, floor %s)\n' "$http" "$pt" "$depth" "$want"
    return 0
  fi
  printf '    FAIL-DEPTH  http=%s prompt_tokens=%s (asked %s, floor %s)\n' "$http" "$pt" "$depth" "$want"
  return 1
}

# window_leg <profile> <depth> — the timed row on the box, stamped. S1-N is run-scenario.sh's own
# shape for ONE session at ~90 % of ctx, conc 1; the leg is what carries the client stamp and the
# window-exclusivity proof into results-v2.csv.
window_leg() {
  local profile="$1" depth="$2" in_tok cmd
  in_tok="$(pct_of "$depth")"
  cmd="cd $BENCH_DIR && S1N_IN=$in_tok S1N_OUT=512 S1N_NUM_PROMPTS=$REPS S1N_CONC=1 bash run-scenario.sh hd376-$profile-needle S1-N 42 --profile $profile --client $CLIENT"
  if [ "$DRY" = 1 ]; then
    printf '    (dry-run) ssh %s %s\n' "$HOST" "$cmd"
    return 0
  fi
  printf '>>> window leg: run-scenario.sh S1-N in=%s x %s prompts on %s (%s)\n' \
    "$in_tok" "$REPS" "$HOST" "$BENCH_DIR"
  # A non-zero window leg is recorded, not fatal: the needle verdict is the probe's, and the bench
  # log says what happened. run-scenario.sh owns its own zero-load refusal.
  host_read "$cmd" > "$RAW/$profile-scenario.log" 2>&1 \
    || printf '    window leg exited non-zero — its verdict is in %s\n' "$RAW/$profile-scenario.log"
}

# run_profile <name> <engine> <mlen> <container> <certified> <active> — one row of the plan.
run_profile() {
  local name="$1" engine="$2" mlen="$3" container="$4" certified="$5" active="$6"
  local depth status why why_note st argv live_m live_flag n ok pre_s pre_e pre_d
  if [ -n "$DEPTH_OVERRIDE" ]; then depth="$DEPTH_OVERRIDE"; else depth="$mlen"; fi

  if [ "$depth" -gt "$CEILING" ]; then
    printf 'ERROR: CEILING REFUSED — the %s profile declares max_model_len=%s, above the servable\n' "$name" "$depth" >&2
    printf '       ceiling %s. The row is neither clamped to the ceiling nor probed: an above-window\n' "$CEILING" >&2
    printf '       arm needs YaRN rope scaling + a fresh needle test first (harness-pi-engines.md §3).\n' >&2
    printf '>>> %s: CEILING-REFUSED (depth %s) — the sweep did NOT test this profile.\n' "$name" "$depth"
    row "$name" CEILING-REFUSED "$depth" "above the $CEILING servable ceiling — no leg ran" "$certified" "$active"
    return 1
  fi

  if [ "$active" != "yes" ]; then
    if [ -n "$PROFILE_FILTER" ]; then
      printf 'ERROR: ATTRIBUTION REFUSED — %s was named on the command line but host_vars\n' "$name" >&2
      printf '       spark_llm_profile is not %s, so the box is not serving it and no leg of this\n' "$name" >&2
      printf '       run may be recorded against it. Flip the dial (an engine recreate, an owner\n' >&2
      printf '       window), then re-run — or drop --profile and take the whole plan as a plan.\n' >&2
      exit 4
    fi
    printf '>>> %s: NOT-SERVED — host_vars spark_llm_profile is not %s, so no leg of this run may\n' "$name" "$name"
    printf '       be recorded against it. The flip is an engine recreate + ~20 min boot and this\n'
    printf '       driver never converges. The act, for an owner window:\n'
    flip_cmd "$name" | sed 's/^/       /'
    row "$name" NOT-SERVED "$depth" "the box is not serving this profile — flip it, then re-run" "$certified" "$active"
    return 0
  fi

  st="$(host_read "${STATE_SNIPPET//@CONTAINER@/$container}" 2>/dev/null || echo "false unknown")"
  if [ "$(printf '%s' "$st" | awk '{print $1}')" != "true" ]; then
    printf 'ERROR: container %s (profile %s) is not running on %s, and host_vars says it should be.\n' \
      "$container" "$name" "$HOST" >&2
    printf '       The name resolves as IaC spark_vllm_container -> spark_llm_profiles[<p>].container;\n' >&2
    printf '       pass --profile for the arm actually serving. Nothing was captured.\n' >&2
    exit 6
  fi
  argv="$(host_read "${ARGV_SNIPPET//@CONTAINER@/$container}" || true)"
  printf '%s\n' "$argv" | scrub_argv > "$RAW/$name-engine-argv.txt"
  live_flag="--max-model-len"
  [ "$engine" = "sglang" ] && live_flag="--context-length"
  live_m="$(engine_flag "$argv" "$live_flag")"
  # IaC says one window, the engine boots another: the box drifted, or the dial moved after the
  # plan was read. Either way a leg recorded against this name measured a different engine.
  if [ -z "$DEPTH_OVERRIDE" ] && [ -n "$live_m" ] && [ "$live_m" != "$depth" ]; then
    printf 'ERROR: ATTRIBUTION REFUSED — %s declares max_model_len=%s; the live engine boots\n' "$name" "$depth" >&2
    printf '       %s=%s. Re-point --profile to the arm actually serving, or flip the dial.\n' "$live_flag" "$live_m" >&2
    if [ -n "$PROFILE_FILTER" ]; then exit 4; fi
    printf '>>> %s: DRIFT — declared %s, live engine %s. Legs NOT run.\n' "$name" "$depth" "$live_m"
    row "$name" DRIFT "$depth" "declared $depth, live engine $live_m — not attributed" "$certified" "$active"
    return 1
  fi
  # A --depth override may sit BELOW the window the engine booted (that is a legitimate shallow
  # arm); it may never sit ABOVE it, where the engine would answer 400 and the row would claim a
  # depth this box was never booted to serve.
  if [ -n "$live_m" ] && [ "$live_m" -lt "$depth" ]; then
    printf 'ERROR: ATTRIBUTION REFUSED — asked for %s tokens at %s, but the live engine boots\n' "$depth" "$name" >&2
    printf '       %s=%s. Above that the engine answers 400, so no number taken here would mean\n' "$live_flag" "$live_m" >&2
    printf '       what the row would say. Drop --depth, or boot the window you mean to test.\n' >&2
    exit 4
  fi
  if [ -n "$DEPTH_OVERRIDE" ] && [ -n "$live_m" ] && [ "$live_m" != "$depth" ]; then
    printf '>>> %s: legs run at the OVERRIDE depth %s while the engine boots %s — a shallow arm,\n' \
      "$name" "$depth" "$live_m"
    printf '       not a verdict on the window %s declares.\n' "$name"
    why_note="override depth $depth, engine window $live_m"
  else
    why_note=""
  fi

  pre_s="$(host_read "$METRICS_SNIPPET" || true)"
  printf '%s\n' "$pre_s" > "$RAW/$name-metrics-start.txt"
  if [ -z "$pre_s" ]; then
    printf '>>> NOTE: the opening /metrics read came back empty, so "no preemption in the window"\n' >&2
    printf '        cannot be claimed for %s. The depth verdict still stands on its own read.\n' "$name" >&2
  fi

  ok=1
  for n in $(seq 1 "$REPS"); do
    one_attempt "$name" "$depth" "$n" || ok=0
  done
  if [ "$WINDOW" = 1 ]; then window_leg "$name" "$depth"; fi

  pre_e="$(host_read "$METRICS_SNIPPET" || true)"
  printf '%s\n' "$pre_e" > "$RAW/$name-metrics-end.txt"
  pre_d='not read'
  if [ -n "$pre_s" ] && [ -n "$pre_e" ]; then
    pre_d="$(awk -v a="$(counter_sum "$pre_e" vllm:num_preemptions_total)" \
                  -v b="$(counter_sum "$pre_s" vllm:num_preemptions_total)" 'BEGIN{printf "%+d", a-b}')"
  fi
  if [ "$ok" = 1 ]; then status=PASS; else status=FAIL; fi
  why="$REPS attempt(s) at $depth, preemptions $pre_d across the window"
  [ -n "$why_note" ] && why="$why — $why_note"
  row "$name" "$status" "$depth" "$why" "$certified" "$active"
  printf '>>> %s: %s — %s\n' "$name" "$status" "$why"
  [ "$ok" = 1 ]
}

run_main() {
  local name engine mlen container certified active rc_all=0
  CLIENT="$(client_stamp)"
  TAG="$(date -u +%Y%m%d-%H%M%S)"
  RAW="$OUT/raw/$TAG"
  ROWS=""
  mkdir -p "$RAW"
  printf '>>> needle-window out=%s tag=%s client=%s endpoint=%s reps=%s window=%s\n' \
    "$OUT" "$TAG" "$CLIENT" "$BASE_URL" "$REPS" "$([ "$WINDOW" = 1 ] && printf yes || printf no)"
  PLAN_TSV="$(plan_tsv)" \
    || die "the plan could not be derived from the catalogue at $REPO — the probe's local leg failed, and a typed fallback is not an option" 1
  [ -n "$PLAN_TSV" ] || die "the catalogue yielded an empty profile list — a plan with no rows is a broken root, not a clean sweep" 1
  printf '%s\n' "$PLAN_TSV" > "$RAW/plan.tsv"

  # The header prints BEFORE any leg, so the traps travel with the numbers, not behind them.
  printf '>>> trap: a pass at 32k is NOT a pass at 262k — depth is per profile, read off the catalogue.\n'
  printf '>>> trap: %s is the servable ceiling; "%s" is KV pool slots, never a client value.\n' "$CEILING" "$KV_SLOTS_QUOTE"
  printf '>>> trap: >=120k corruption on sm_12x (%s) — HTTP 200 AT DEPTH IS NOT A CLEAN READ.\n' "$CORRUPTION_TRAP"

  while IFS=$'\t' read -r name engine mlen container certified active; do
    [ -n "$name" ] || continue
    if [ -n "$PROFILE_FILTER" ] && ! printf '%s\n' "$PROFILE_FILTER" | grep -qxF -- "$name"; then
      continue
    fi
    run_profile "$name" "$engine" "$mlen" "$container" "$certified" "$active" || rc_all=1
  done <<< "$PLAN_TSV"

  # A name that is not in the catalogue would otherwise vanish silently into the filter above.
  for name in $(printf '%s\n' "$PROFILE_FILTER"); do
    printf '%s\n' "$PLAN_TSV" | cut -f1 | grep -qxF -- "$name" \
      || die "--profile $name is not in the catalogue at $REPO (valid: $(printf '%s\n' "$PLAN_TSV" | cut -f1 | paste -sd' ' -))" 2
  done

  write_report
  printf '>>> verdict file: %s\n>>> raw:          %s\n' "$OUT/needle-$TAG.md" "$RAW"
  return "$rc_all"
}

write_report() {
  local p v d w c a
  {
    printf '# The needle sweep at the depth each profile serves\n\n'
    printf '**AUTHORED BY THE DRIVER — one run'"'"'s leg record, not a certificate.** The\n'
    printf '`certified_evidence` a catalogue row needs is authored by a session from these\n'
    printf 'numbers (spark/llm-profiles/README.md, gates 3 and 5).\n\n'
    printf '## Read these first\n\n'
    printf '· **A pass at 32k is not a pass at 262k.** Depth is per profile and comes from the\n'
    printf '  catalogue, not from a flag: `raw/%s/plan.tsv`.\n' "$TAG"
    printf '· **%s is the servable ceiling** (`--max-model-len` = `max_position_embeddings`, a boot\n' "$CEILING"
    printf '  gate). The oft-quoted **%s is KV pool slots** summed across concurrent sequences —\n' "$KV_SLOTS_QUOTE"
    printf '  never a client value (docs/harness-pi-engines.md §3).\n'
    printf '· **The >=120k corruption trap on sm_12x** — %s — corrupts a\n' "$CORRUPTION_TRAP"
    printf '  long-context request while answering **HTTP 200**. A depth pass below is a *depth*\n'
    printf '  pass, read with this trap and not instead of it (BENCHMARK-PLAN.md §Correctness trap).\n'
    printf '· **Recall is judged separately.** The token-subsequence rule\n'
    printf '  (docs/spark-llm-profiles.md) runs against the engine'"'"'s own tokenizer inside the\n'
    printf '  container and no landed instrument automates it. `http=200 prompt_tokens=…` proves the\n'
    printf '  window was HELD; it does not prove the needle came back.\n\n'
    printf 'Seat: `%s` — Rule 0 asks the reader to check that this names an externally-served\n' "$CLIENT"
    printf 'session on the designated runner station. Endpoint `%s`, %s attempt(s) per profile.\n\n' \
      "$BASE_URL" "$REPS"
    printf '## Verdicts\n\n'
    printf '| profile | verdict | depth asked | what the verdict rests on | certified | live |\n'
    printf '|---|---|---|---|---|---|\n'
    while IFS='|' read -r p v d w c a; do
      [ -n "$p" ] || continue
      printf '| %s | %s | %s | %s | %s | %s |\n' "$p" "$v" "$d" "$w" "$c" "$a"
    done <<< "$ROWS"
    printf '\n`NOT-SERVED` is not a failure: it is the row the flip command belongs to. One\n'
    printf 'container serves one profile, so a full sweep is one run of this driver per boot window\n'
    printf 'and the rows accumulate in this folder as the windows pass.\n\n'
    printf '## Raw\n\n'
    printf '· plan as derived: `raw/%s/plan.tsv`\n' "$TAG"
    printf '· probe stdout per attempt: `raw/%s/<profile>-attempt-N.probe.txt`\n' "$TAG"
    printf '· engine argv, bearer scrubbed at the point of write: `raw/%s/<profile>-engine-argv.txt`\n' "$TAG"
    printf '· `/metrics` at both ends of each window: `raw/%s/<profile>-metrics-{start,end}.txt`\n' "$TAG"
    printf '· the timed leg'"'"'s own log: `raw/%s/<profile>-scenario.log`\n' "$TAG"
    printf '· per attempt: `/tmp/hd376-<profile>-<HHMM>.log` — a retry gains `.1` and never\n'
    printf '  truncates the attempt that failed.\n'
  } > "$OUT/needle-$TAG.md"
}

run_dry() {
  local name engine mlen container certified active depth
  printf '# the exact legs this act would run — nothing below is sent, nothing is written\n\n'
  printf 'client stamp: %s\nendpoint:       %s\nreps:           %s\nwindow leg:     %s\n\n' \
    "$(client_stamp)" "$BASE_URL" "$REPS" "$([ "$WINDOW" = 1 ] && printf yes || printf 'no (--no-window)')"
  PLAN_TSV="$(plan_tsv)" || die "the plan could not be derived from the catalogue at $REPO" 1
  printf '# the plan, derived from the catalogue (never typed):\n'
  printf '%s\n' "$PLAN_TSV" | awk -F'\t' '{printf "#   %-14s engine=%-7s max_model_len=%-7s container=%-18s certified=%-3s live=%s\n", $1, $2, $3, $4, $5, $6}'
  printf '\n# per profile the box is actually serving:\n'
  while IFS=$'\t' read -r name engine mlen container certified active; do
    [ -n "$name" ] || continue
    if [ -n "$DEPTH_OVERRIDE" ]; then depth="$DEPTH_OVERRIDE"; else depth="$mlen"; fi
    printf '\n## %s (depth %s)\n' "$name" "$depth"
    printf '  %s\n' "$(probe_cmd "$depth")"
    printf '  ssh %s %s\n' "$HOST" "${STATE_SNIPPET//@CONTAINER@/$container}"
    printf '  ssh %s %s\n' "$HOST" "${ARGV_SNIPPET//@CONTAINER@/$container}"
    printf '  ssh %s %s\n' "$HOST" "$METRICS_SNIPPET"
    if [ "$WINDOW" = 1 ]; then
      printf '  ssh %s "cd %s && S1N_IN=%s S1N_OUT=512 S1N_NUM_PROMPTS=%s S1N_CONC=1 bash run-scenario.sh hd376-%s-needle S1-N 42 --profile %s --client <stamp>"\n' \
        "$HOST" "$BENCH_DIR" "$(pct_of "$depth")" "$REPS" "$name" "$name"
    fi
    if [ "$active" != "yes" ]; then
      printf '  # NOT-SERVED — the flip an owner runs first (this driver never converges):\n'
      flip_cmd "$name" | sed 's/^/  # /'
    fi
  done <<< "$PLAN_TSV"
  printf '\n# writes: %s/needle-<UTC tag>.md and raw/<UTC tag>/ — never a README, never a profile.\n' "$OUT"
}

# ---------------------------------------------------------------------------
# --self-test — fixtures only. Nothing here sshes, nothing reaches an engine, nothing reads
# the vault, so the Rule 0 refusal, the ceiling guard and the DERIVED plan are proven and not
# asserted — from the seat that needs the proof.
# ---------------------------------------------------------------------------
run_self_test() {
  local t fails=0 rc out cmdlog probe_calls d1 d2 first second snap_a snap_b n logcount report
  t="$(mktemp -d)"
  local self="$SELF_DIR/$SELF_NAME"
  mkdir -p "$t/bin" "$t/logs" "$t/repo/IaC/ansible/group_vars" "$t/repo/docs" "$t/repo/spark/reports"
  : > "$t/repo/docs/index.md"

  # A catalogue with THREE different windows and no default anywhere in it: a plan built from
  # typed numbers could not reproduce these rows, which is the point of the fixture.
  cat > "$t/repo/IaC/ansible/group_vars/spark.yml" <<'YML'
spark_llm_profile: small
spark_llm_kv_bytes_per_token: {bfloat16: 31040, auto: 31040}
spark_llm_pool_ceiling_bytes: 17179869184
spark_llm_device_hold_ceiling_bytes: 118251536384
spark_llm_profiles:
  _x: {max_model_len: 262144, engine: vllm, container: vllm-qwen-spark}
  small: {max_model_len: 32768, engine: vllm, container: vllm-qwen-spark, certified: true,
          kv_cache_dtype: auto, kv_cache_memory: 16000000000, model_subdir: M}
  mid: {max_model_len: 131072, engine: vllm, container: vllm-qwen-spark,
        kv_cache_dtype: auto, kv_cache_memory: 16000000000, model_subdir: M}
  full: {max_model_len: 262144, engine: vllm, container: vllm-qwen-spark,
         kv_cache_dtype: auto, kv_cache_memory: 20000000000, model_subdir: M}
YML

  cmdlog="$t/commands.log"; : > "$cmdlog"
  probe_calls="$t/probe.log"; : > "$probe_calls"

  # One fake box: answers a READ and fails loud on anything else, so a new kind of host
  # interaction cannot slip through the fixture dressed up as "probably a read".
  cat > "$t/bin/fake-host" <<'FIX'
#!/usr/bin/env bash
cmd="$(cat)"
printf '%s\n' "$cmd" >> "${FAKE_LOG:?}"
case "$cmd" in
  *'.State.Running'*) printf '%s\n' "true ${FAKE_BOOT:-2026-10-22T09:00:00Z} restarts=0" ;;
  *'.Config.Cmd'*)
    printf '%s\n' "--model /model --served-model-name spark/m --max-model-len ${FAKE_MAX_LEN:-32768} --kv-cache-memory-bytes 16000000000 --api-key REDACTED-IN-FIXTURE" ;;
  */metrics*)
    printf 'vllm:num_preemptions_total 173\nvllm:prefix_cache_hits_total{model_name="m"} 100\nvllm:prefix_cache_queries_total{model_name="m"} 250\n' ;;
  *run-scenario.sh*) printf 'row appended\n' ;;
  *) printf 'fake-host: unhandled command: %s\n' "$cmd" >&2; exit 9 ;;
esac
FIX
  chmod +x "$t/bin/fake-host"

  # A probe stand-in that speaks the real legs' output shape and logs the depth it was handed, so
  # the self-test checks the depth the act ASKED FOR, not the depth it hoped to ask for.
  cat > "$t/bin/fake-probe" <<'FIX'
#!/usr/bin/env bash
depth=""
for a in "$@"; do depth="$a"; done
printf '%s\n' "$depth" >> "${FAKE_PROBE_LOG:?}"
pt="${FAKE_PROMPT:-}"
[ -n "$pt" ] || pt="$(awk -v d="$depth" 'BEGIN{printf "%.0f", d*0.95}')"
printf 'endpoint http://fixture/v1  bearer len=40 (value not printed)\n'
printf '  %s  ctx %s: http=%s prompt=%s (asked~=%s, body 1.1 MB) completion=24 3.0s \n' \
  "${FAKE_VERDICT:-PASS}" "$depth" "${FAKE_HTTP:-200}" "$pt" "$depth"
printf '\n1/1 probes passed\n'
FIX
  chmod +x "$t/bin/fake-probe"

  ok()  { printf '  ok:   %s\n' "$1"; }
  bad() { printf '  FAIL: %s\n' "$1"; fails=$((fails + 1)); }
  want() { if printf '%s\n' "$out" | grep -qF -- "$1"; then ok "$2"; else bad "$2 (wanted \"$1\": $(printf '%s' "$out" | tail -3))"; fi; }

  drive() {
    out="$(FAKE_LOG="$cmdlog" FAKE_PROBE_LOG="$probe_calls" FAKE_MAX_LEN="${FAKE_MAX_LEN:-32768}" \
      NEEDLE_SSH_CMD="$t/bin/fake-host" NEEDLE_PROBE_CMD="$t/bin/fake-probe" \
      NEEDLE_LOG_DIR="$t/logs" NEEDLE_TOKEN_ENV=FIXTURE REPO="$t/repo" \
      PI_PROVIDER=other PI_MODEL=other/model-not-spark \
      bash "$self" "$@" 2>&1)" && rc=0 || rc=$?
  }
  live_is() {   # flip WHICH profile the fixture box serves — the only change that must move the depth
    sed -i "s/^spark_llm_profile: .*/spark_llm_profile: $1/" "$t/repo/IaC/ansible/group_vars/spark.yml"
    FAKE_MAX_LEN="$2"
  }

  echo "case (a): a spark-served session is refused, naming Rule 0, before anything is read"
  out="$(PI_PROVIDER=spark PI_MODEL=spark/qwen3.8-flash-next REPO="$t/repo" \
         NEEDLE_SSH_CMD="$t/bin/fake-host" NEEDLE_PROBE_CMD="$t/bin/fake-probe" \
         NEEDLE_LOG_DIR="$t/logs" bash "$self" 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 3 ] && ok "exits 3 under PI_PROVIDER=spark" || bad "spark-served rc=$rc, want 3"
  want "Rule 0" "the refusal names Rule 0"
  want "ISSUES REQUESTS AGAINST THE ENGINE" "and says why a needle test is not a counter read"
  [ "$(wc -l < "$cmdlog")" -eq 0 ] && ok "no host command was sent" || bad "the refusal came after a host read"
  [ "$(wc -l < "$probe_calls")" -eq 0 ] && ok "no inference leg was issued" || bad "the refusal still probed the engine"
  [ "$(find "$t/logs" -name 'hd376-*.log' | wc -l)" -eq 0 ] \
    && ok "no attempt log was opened either" || bad "the refusal still opened an attempt log"
  [ "$(find "$t/repo/spark/reports" -maxdepth 1 -name 'hd376-needle-*' | wc -l)" -eq 0 ] \
    && ok "no evidence dir was created" || bad "the refusal still created an evidence dir"

  echo "case (b): above the ceiling is refused; 262,144 itself is accepted; a catalogue depth above it never runs"
  : > "$cmdlog"; : > "$probe_calls"
  drive --depth 262145 --out "$t/repo/spark/reports/ev-b"
  [ "$rc" = 5 ] && ok "--depth 262145 exits 5" || bad "over-ceiling rc=$rc, want 5"
  want "CEILING REFUSED" "the refusal names the ceiling"
  want "273k is KV POOL CAPACITY IN TOKEN SLOTS" "and says 273k is slots, not context"
  want "YaRN" "and names what going above the ceiling actually costs"
  [ "$(wc -l < "$probe_calls")" -eq 0 ] && ok "nothing was probed at an over-ceiling depth" \
    || bad "an over-ceiling depth reached the engine"
  [ -e "$t/repo/spark/reports/ev-b" ] && bad "the refused run still wrote an evidence dir" \
    || ok "the refused run wrote nothing"
  : > "$cmdlog"; : > "$probe_calls"
  FAKE_MAX_LEN=262144 drive --depth 262144 --profile small --out "$t/repo/spark/reports/ev-b2"
  [ "$rc" = 0 ] && ok "--depth 262144 is accepted — the ceiling is inclusive" || bad "rc=$rc: $(printf '%s' "$out" | tail -3)"
  [ "$(tail -1 "$probe_calls")" = "262144" ] && ok "and the probe was asked for exactly 262144" \
    || bad "the probe was asked for $(tail -1 "$probe_calls")"
  # Now the per-ROW arm: a catalogue profile that declares an above-ceiling window. Appended,
  # tested, removed — the rest of the arms need a catalogue the sweep can fully judge.
  printf '  over: {max_model_len: 300000, engine: vllm, container: vllm-qwen-spark,\n         kv_cache_dtype: auto, kv_cache_memory: 16000000000, model_subdir: M}\n' \
    >> "$t/repo/IaC/ansible/group_vars/spark.yml"
  : > "$probe_calls"
  drive --out "$t/repo/spark/reports/ev-b3"
  [ "$rc" = 1 ] && ok "an above-ceiling catalogue profile reddens the sweep instead of passing quietly" \
    || bad "rc=$rc, want 1"
  grep -qF 'CEILING-REFUSED' "$(find "$t/repo/spark/reports/ev-b3" -name 'needle-*.md' | head -1)" \
    && ok "the row reads CEILING-REFUSED" || bad "the above-ceiling row is missing from the report"
  [ "$(grep -c '^300000$' "$probe_calls" 2>/dev/null || true)" = "0" ] \
    && ok "and it was never probed at 300k — refused per row, never silently clamped" \
    || bad "a 300k depth reached the probe"
  grep -qF 'over:' "$t/repo/IaC/ansible/group_vars/spark.yml" \
    && ok "the catalogue was read, not rewritten, by the refusal" || bad "the catalogue changed under the run"
  sed -i '/^  over:/,+1d' "$t/repo/IaC/ansible/group_vars/spark.yml"

  echo "case (c): the plan is DERIVED — the depth follows the catalogue, never a typed constant"
  : > "$probe_calls"
  drive --out "$t/repo/spark/reports/ev-c"
  [ "$rc" = 0 ] || bad "sweep rc=$rc: $(printf '%s' "$out" | tail -4)"
  report="$(find "$t/repo/spark/reports/ev-c" -name 'needle-*.md' | head -1)"
  for n in 32768 131072 262144; do
    grep -qF "| $n |" "$report" && ok "the plan carries the fixture window $n" \
      || bad "depth $n is not in the plan — it looks typed, not derived"
  done
  [ "$(tail -1 "$probe_calls")" = "32768" ] \
    && ok "the legs ran at the LIVE profile's own window (32768)" || bad "legs ran at $(tail -1 "$probe_calls")"
  live_is mid 131072
  : > "$probe_calls"
  drive --out "$t/repo/spark/reports/ev-c-mid"
  [ "$(tail -1 "$probe_calls")" = "131072" ] \
    && ok "flipping ONLY the catalogue's live profile moves the depth to 131072 — nothing here was edited" \
    || bad "the depth did not follow the catalogue ($(tail -1 "$probe_calls"))"
  live_is small 32768
  printf '  big: {max_model_len: 65536, engine: vllm, container: vllm-qwen-spark,\n       kv_cache_dtype: auto, kv_cache_memory: 16000000000, model_subdir: M}\n' \
    >> "$t/repo/IaC/ansible/group_vars/spark.yml"
  live_is big 65536
  : > "$probe_calls"
  drive --out "$t/repo/spark/reports/ev-c-big"
  [ "$(tail -1 "$probe_calls")" = "65536" ] \
    && ok "a profile ADDED to the catalogue is planned and probed with no edit here" \
    || bad "a new catalogue profile did not reach the probe — the plan is typed after all"
  live_is small 32768
  grep -qF '_x' "$(find "$t/repo/spark/reports/ev-c" -name 'plan.tsv' -path '*raw*' | head -1)" \
    && bad "the merge anchor _x was planned as a profile" \
    || ok "the merge-anchor key _x is not probed as a profile"
  want "a pass at 32k is NOT a pass at 262k" "the trap header rides with the numbers"
  want "HTTP 200 AT DEPTH IS NOT A CLEAN READ" "the sm_12x corruption trap is in the header"
  want "sglang#36806" "and it carries its issue numbers"
  n="$(find "$t/repo/spark/reports/ev-c" -name 'needle-*.md' | wc -l)"
  [ "$n" = 1 ] && ok "one verdict file per run, under the dated evidence dir" || bad "$n verdict files, want 1"
  grep -qF 'NOT-SERVED' "$report" \
    && ok "a profile the box is not serving is NOT-SERVED, not passed" \
    || bad "a non-live profile was given a verdict it did not earn"
  grep -qF 'agent:' "$report" \
    && ok "the seat stamp is in the report, so Rule 0 is checkable afterwards" || bad "no client stamp in the report"
  want "never converges" "the flip command is printed for an owner, never run here"
  [ "$(grep -cE 'ansible-playbook|docker (restart|stop|rm|kill)|systemctl|reboot|sed -i' "$cmdlog")" -eq 0 ] \
    && ok "no mutate verb reached the box in $(wc -l < "$cmdlog") command(s)" \
    || bad "a mutate verb reached the box: $(grep -nE 'ansible-playbook|docker (restart|stop|rm|kill)|systemctl|reboot|sed -i' "$cmdlog" | head -2)"
  [ "$(grep -rl 'REDACTED-IN-FIXTURE' "$t/repo/spark/reports/ev-c" 2>/dev/null | wc -l)" -eq 0 ] \
    && ok "no capture in the evidence dir carries the engine's bearer shape" \
    || bad "a raw capture holds a bearer"
  snap_a="$(cd "$t/repo/IaC" && find . -type f -exec md5sum {} + | sort)"
  drive --out "$t/repo/spark/reports/ev-c-snap"
  snap_b="$(cd "$t/repo/IaC" && find . -type f -exec md5sum {} + | sort)"
  [ "$snap_a" = "$snap_b" ] && ok "nothing outside the evidence dir changed, IaC least of all" \
    || bad "a file outside the evidence dir was modified"

  echo "case (d): one log per attempt, and a retry does not truncate the first run's raw"
  rm -f "$t"/logs/hd376-*.log
  d1="$t/repo/spark/reports/ev-d"
  drive --out "$d1"
  [ "$rc" = 0 ] || bad "attempt set 1 rc=$rc: $(printf '%s' "$out" | tail -3)"
  logcount="$(find "$t/logs" -name 'hd376-small-*.log' | wc -l)"
  [ "$logcount" -eq "$REPS" ] && ok "each of the $REPS attempts got its own log file" \
    || bad "$logcount logs for $REPS attempts — they either share a file or the count is wrong"
  first="$(find "$d1/raw" -mindepth 1 -maxdepth 1 -type d | sort | head -1)"
  cp -r "$first" "$t/attempt1.copy"
  sleep 1
  drive --out "$d1"
  [ "$rc" = 0 ] || bad "the retry rc=$rc: $(printf '%s' "$out" | tail -3)"
  second="$(find "$d1/raw" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)"
  [ "$first" != "$second" ] && ok "two runs wrote two raw trees ($(basename "$first"), $(basename "$second"))" \
    || bad "the retry wrote over the first run's tree"
  if diff -r "$t/attempt1.copy" "$first" >/dev/null 2>&1; then ok "the first run's raw is byte-for-byte intact"
  else bad "the first run's raw was modified by the retry"; fi
  [ "$(find "$d1" -name 'needle-*.md' | wc -l)" -eq 2 ] \
    && ok "each run kept its own verdict file" || bad "a verdict file was overwritten"
  [ "$(find "$t/logs" -name 'hd376-small-*.log' | wc -l)" -eq "$((REPS * 2))" ] \
    && ok "the retry opened $REPS NEW logs instead of reopening attempt 1" \
    || bad "the retry reused or dropped attempt logs ($(find "$t/logs" -name 'hd376-small-*.log' | wc -l) total)"

  echo "case (e): --dry-run prints the exact commands and sends nothing"
  : > "$cmdlog"; : > "$probe_calls"
  d2="$t/repo/spark/reports/ev-e"
  drive --dry-run --out "$d2"
  [ "$rc" = 0 ] && ok "--dry-run exits 0" || bad "--dry-run rc=$rc"
  want "ctx 32768" "the probe command is printed at the live profile's own depth"
  want "run-scenario.sh hd376-small-needle S1-N" "the timed leg is printed too, with its stamp"
  want "max_model_len=131072" "the derived plan is printed, mid included"
  [ "$(wc -l < "$cmdlog")" -eq 0 ] && ok "no host command was sent" || bad "--dry-run still read the box"
  [ "$(wc -l < "$probe_calls")" -eq 0 ] && ok "no inference leg was issued" || bad "--dry-run still probed the engine"
  [ -e "$d2" ] && bad "--dry-run created the evidence dir" || ok "no evidence dir was created"

  echo "case (f): usage refusals, before anything is read"
  : > "$cmdlog"; : > "$probe_calls"
  drive --profile nosuchprofile --out "$t/repo/spark/reports/ev-f"
  [ "$rc" = 2 ] && ok "an unknown --profile is refused with rc 2" || bad "unknown profile rc=$rc, want 2"
  want "not in the catalogue" "and it names the catalogue as the authority"
  : > "$cmdlog"
  drive --depth 16k --out "$t/repo/spark/reports/ev-f"
  [ "$rc" = 2 ] && ok "--depth 16k refused with rc 2" || bad "rc=$rc, want 2"
  : > "$cmdlog"
  drive --not-a-flag
  [ "$rc" = 2 ] && ok "an unknown flag is refused" || bad "unknown flag rc=$rc, want 2"
  [ "$(wc -l < "$cmdlog")" -eq 0 ] && ok "none of them read the box" || bad "a refused call still read the box"

  echo "case (g): attribution — naming a profile the box is not serving, or an engine that moved"
  : > "$cmdlog"; : > "$probe_calls"
  drive --profile full --out "$t/repo/spark/reports/ev-g"
  [ "$rc" = 4 ] && ok "naming a non-served profile exits 4" || bad "rc=$rc, want 4"
  want "ATTRIBUTION REFUSED" "and it names attribution as the reason"
  [ "$(wc -l < "$probe_calls")" -eq 0 ] && ok "no leg ran against someone else's engine" \
    || bad "legs ran while the named profile was not live"
  # The mutation arm that gives the check its teeth: the live profile's argv depth is not its
  # declared one, so the legs must not run even though the name matches.
  : > "$cmdlog"; : > "$probe_calls"
  out="$(FAKE_LOG="$cmdlog" FAKE_PROBE_LOG="$probe_calls" FAKE_MAX_LEN=131072 \
    NEEDLE_SSH_CMD="$t/bin/fake-host" NEEDLE_PROBE_CMD="$t/bin/fake-probe" NEEDLE_LOG_DIR="$t/logs" \
    REPO="$t/repo" PI_PROVIDER=other PI_MODEL=other/model-not-spark \
    bash "$self" --out "$t/repo/spark/reports/ev-g2" 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 1 ] && ok "a live engine whose argv depth differs from the profile's is DRIFT (rc 1)" \
    || bad "drift rc=$rc, want 1"
  [ "$(wc -l < "$probe_calls")" -eq 0 ] && ok "no leg ran on an engine that does not match its profile" \
    || bad "legs ran despite the argv mismatch"
  grep -qF 'DRIFT' "$(find "$t/repo/spark/reports/ev-g2" -name 'needle-*.md' | head -1)" \
    && ok "the report carries the DRIFT row" || bad "the DRIFT row never reached the report"

  echo "case (h): a FAIL is a RESULT — recorded, not hidden"
  : > "$probe_calls"
  out="$(FAKE_LOG="$cmdlog" FAKE_PROBE_LOG="$probe_calls" FAKE_HTTP=400 FAKE_VERDICT=FAIL \
    NEEDLE_SSH_CMD="$t/bin/fake-host" NEEDLE_PROBE_CMD="$t/bin/fake-probe" NEEDLE_LOG_DIR="$t/logs" \
    REPO="$t/repo" PI_PROVIDER=other PI_MODEL=other/model-not-spark \
    bash "$self" --out "$t/repo/spark/reports/ev-h" 2>&1)" && rc=0 || rc=$?
  [ "$rc" = 1 ] && ok "a FAIL-DEPTH run exits 1 (a result, not a crash)" || bad "FAIL run rc=$rc, want 1"
  want "FAIL-DEPTH" "the attempt prints its own verdict with its numbers"
  grep -qF '| FAIL |' "$(find "$t/repo/spark/reports/ev-h" -name 'needle-*.md' | head -1)" \
    && ok "the verdict file carries the FAIL" || bad "the FAIL did not reach the report"

  echo "case (i): the depth floor is reachable AND has teeth — the number a false FAIL turns on"
  : > "$probe_calls"
  drive --no-window
  depth_asked="$(tail -1 "$probe_calls")"
  live_prof="$(awk '/^spark_llm_profile:/{print $2}' "$t/repo/IaC/ansible/group_vars/spark.yml")"
  # spark-llm-probe.py sizes its prompt to 0.9 x 0.9 of the ask, so ~81 % is the truest reading a
  # healthy engine can return. A floor above that is not rigour, it is a permanent false FAIL.
  FAKE_PROMPT="$(awk -v d="$depth_asked" 'BEGIN{printf "%.0f", d*0.81}')" drive --profile "$live_prof" --no-window
  want "PASS-DEPTH" "a reading of 81 % of the ask passes — the floor is reachable by construction"
  [ "$rc" = 0 ] && ok "and that run exits 0" || bad "reachable reading rc=$rc, want 0"
  FAKE_PROMPT="$(awk -v d="$depth_asked" 'BEGIN{printf "%.0f", d*0.79}')" drive --profile "$live_prof" --no-window
  want "FAIL-DEPTH" "and 79 % of the ask fails — the floor is enforced, not decorative"
  [ "$rc" = 1 ] && ok "the sub-floor run exits 1" || bad "sub-floor reading rc=$rc, want 1"
  want "floor $(awk -v d="$depth_asked" 'BEGIN{printf "%.0f", d*0.80}') = 80% of it" \
    "the printed floor is 80 % of the depth the run asked for ($depth_asked)"

  rm -rf "$t"
  if [ "$fails" = 0 ]; then echo "SELF-TEST OK"; return 0; fi
  printf 'SELF-TEST FAILED: %s assertion(s)\n' "$fails"; return 1
}

if [ "$TEST" = 1 ]; then run_self_test; exit $?; fi
if [ "$DRY" = 1 ]; then run_dry; exit 0; fi

LOG="$(attempt_log sweep)"
printf '>>> attempt log: %s\n' "$LOG"
# pipefail makes the pipeline's status the run's status, so the log never hides a refusal.
run_main 2>&1 | tee -a "$LOG"
