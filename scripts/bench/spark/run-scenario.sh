#!/usr/bin/env bash
# ============================================================================
# run-scenario.sh — run one benchmark scenario with before/after metrics,
# power sampling, and automatic CSV append to bench/results.csv
#
# Usage:
#   ./run-scenario.sh <STEP_ID> <C1|C2|C2L|C3|S1-N> [seed] [--router] [--warm] \
#                     [--profile <arm>] [--client <who-ran-it>]
#
#   STEP_ID   free-form tag matching the ladder, e.g. B1, step5-32k
#   C1        prefill-heavy : 32k in / 512 out,  concurrency 1
#   C2        decode        :  1k in / 512 out,  concurrency 1
#   C2L       long decode   :  1k in / 1k out,   concurrency 1, 12 prompts — sized so one leg
#             spans >3 cold scrape intervals (180 s), which is what makes the VICTORIAMETRICS
#             histogram corroboration admissible for that row (see cold_ok below)
#   C3        concurrent    :  8k in / 1k out,   concurrency 3  (NOTE: only for the S3/NVFP4 lane)
#   S1-N      S1 stability sweep probe (§6a) : ONE session at ~90% of ctx, conc 1 (defaults 32k/512/1)
#             S1N_IN/S1N_OUT/S1N_NUM_PROMPTS/S1N_CONC override ; run ONLY right after a util/ctx restart
#   seed      integer; pick a DIFFERENT seed per repeat for cache-free runs,
#             reuse the same seed with --warm to measure warm-prefix TTFT
#   --router  target llm-d router :8080 instead of engine :8000
#   --warm    skip prefix-flush caveat; reuses prompts (cache-hit measurement)
#   --profile HD-489 ONLY: the funnel arm this leg measured (u1-patch, u3-s8, ar-mmap, v16b…). Record
#             it. All 16 arms serve the SAME model_name (a client anchor that must not move), so the
#             engine cannot tell the arms apart — the row is the only place the arm identity lives.
#   --client  who ran the leg. Defaults to <hostname>/agent:<PI_MODEL>, and PI_MODEL is exactly the
#             point: Rule 0 (spark/llm-profiles/README.md) forbids a session served by spark/… from
#             producing timed numbers, and this column is how a later reader can invalidate such a
#             row instead of re-measuring the box to find out who ran it.
#
# Windows: every row carries vm_start_utc / vm_end_utc. Feed them to vm-window.sh to cross-check
# the leg against the engine's own counters in VictoriaMetrics. That cross-check also catches a
# contaminated window (another client's traffic inside it): the row's req_ok_delta must equal N.
#
# Env:  BENCH_DIR (default: dir of this script), VLLM_CONTAINER (default vllm-qwen-spark)
# ============================================================================
set -euo pipefail

STEP="${1:?usage: run-scenario.sh <STEP_ID> <C1|C2|C2L|C3> [seed] [--router] [--warm] [--profile <arm>] [--client <id>]}"
SCENARIO="${2:?scenario required: C1|C2|C2L|C3}"
shift 2 || true
SEED=42
ROUTER=0
WARM=0
PROFILE="${PROFILE:-unlabelled}"
# Commas would break the CSV row, and both strings end up in it verbatim.
PROFILE=$(printf '%s' "$PROFILE" | tr -d ',')
CLIENT=$(printf '%s/%s' "${BENCH_CLIENT:-$(hostname -s 2>/dev/null || echo unknown)}" \
         "agent:${PI_MODEL:-none}" | tr -d ',')
while [ $# -gt 0 ]; do
  case "$1" in
    --router) ROUTER=1 ;;
    --warm)   WARM=1 ;;
    --profile) PROFILE=$(printf '%s' "${2:?--profile needs the arm name, e.g. u1-patch}" | tr -d ','); shift ;;
    --client)  CLIENT=$(printf '%s' "${2:?--client needs an id}" | tr -d ','); shift ;;
    [0-9]*)   SEED="$1" ;;
    *) echo "unknown arg $1" >&2; exit 1 ;;
  esac
  shift
done

BENCH_DIR="${BENCH_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CONTAINER="${VLLM_CONTAINER:-vllm-qwen-spark}"
PORT=$(( ROUTER ? 8080 : 8000 ))
HOST_URL="http://localhost:${PORT}"
RAW="$BENCH_DIR/raw"; mkdir -p "$RAW"
# v2 ON PURPOSE (HD-489): the header gained profile / client / window / prefix-recompute /
# memory-at-rest columns. Appending new-schema rows into the old results.csv would let a reader
# join a decode number to the wrong column, which is worse than a missing file. The old file
# stays untouched as the pre-HD-489 record.
CSV="${RESULTS_CSV:-$BENCH_DIR/results-v2.csv}"
TS=$(date -u +%Y%m%d-%H%M%S)
# RUN_TS is IMMUTABLE run identity. TS gets clobbered by `source`-ing the
# snapshot-metrics .env (it exports its own TS=), which broke copy/parse/CSV
# alignment. All file names + the CSV row use RUN_TS.
RUN_TS="$TS"

# scenario: input_len output_len num_prompts concurrency (env-overridable; C3 safely sized on GB10)
# S1-N: S1 stability sweep probe (§6a) — ONE session at ~90% of ctx, max-concurrency 1, on the
#       engine directly. Run these only AFTER restarting with the sweep util/ctx, so the load-time
#       allocation itself is what's certified. In/out/conc/env-overridable via S1N_*.
case "$SCENARIO" in
  C1) IN=${C1_IN:-32768}; OUT=${C1_OUT:-512}; N=${C1_N:-8}; CONC=${C1_CONC:-1} ;;
  C2) IN=${C2_IN:-1024}; OUT=${C2_OUT:-512}; N=${C2_N:-8}; CONC=${C2_CONC:-1} ;;
  # C2L: the same decode shape as C2, long enough (12 x 1k out) that ONE leg spans >3 cold
  # scrape intervals. The vllm:* latency histograms land at 60 s (HD-420 hot/cold split), so a
  # 20 s leg has no VM-side corroboration at all — the row records that as cold_ok=no.
  C2L) IN=${C2L_IN:-1024}; OUT=${C2L_OUT:-1024}; N=${C2L_N:-12}; CONC=${C2L_CONC:-1} ;;
  # C3 default 12x8k@c3 OOM-kills the box on GB10 unified memory (2026-09-15).
  # Safe variant: 6 prompts x 8k @ conc 2 fits ~27 GiB host headroom.
  C3) IN=${C3_IN:-8192}; OUT=${C3_OUT:-1024}; N=${C3_N:-6}; CONC=${C3_CONC:-2} ;;
  # S1-N = S1 sweep run: DEFAULT is single-session, moderate output. Pass S1N_IN for a max-ctx probe
  # (≈0.9 × max_model_len) and S1N_NUM_PROMPTS=3 for a short multi-probe without changing conc.
  S1-*) IN=${S1N_IN:-32768}; OUT=${S1N_OUT:-512}; N=${S1N_NUM_PROMPTS:-1}; CONC=${S1N_CONC:-1} ;;
  *) echo "unknown scenario $SCENARIO" >&2; exit 1 ;;
esac

# Host-memory preflight (GB10 unified pool lesson, 2026-09-15): the engine idles at
# ~93 GB of a 121.6 GiB pool; C3 (12x8k @c3) made the engine RSS climb + host extras
# (alloy/dashboard/sshd) over the fence → global OOM killed sshd/NetworkManager.
# Guard: if USABLE (= MemAvailable − CmaFree) < FLOOR, refuse to launch (the OOM is not
# recoverable live).
# RAISED 8→14 GiB 2026-09-16 (HD-380): with the HD-374 KV governor live the box IDLES
# at ~16 GiB available, so an 8 GiB floor sat INSIDE the danger zone — it would have
# waved through both 2026-09-16 kills. Pair with stress-oom.sh, which adds a live guard
# that stops the engine on breach instead of letting the kernel pick the victim.
# GAUGE FIXED + RAISED 14→16 2026-09-18 (spark stability-certify close-out): this read raw `free -g`
# column 7 = MemAvailable, and MemAvailable is FALSIFIED on GB10 — CMA counts as
# available, so it INFLATES as pressure rises (measured CmaFree up to 6.61 GiB; at both
# real kills MemAvailable read ~10.4 GiB while usable was 1.6). On the 16 GiB KV pool the
# box idles at usable ~18.5, so a raw-avail floor both false-trips and reads healthy at
# the wrong moments. Same one gauge as the watchdog + alert rules.
USABLE_FLOOR_GIB="${USABLE_FLOOR_GIB:-${MEM_FLOOR_GB:-16}}"
if command -v awk >/dev/null 2>&1; then
  _usable=$(awk '/^MemAvailable:/{a=$2}/^CmaFree:/{c=$2}END{printf "%.1f",(a-c)/1048576}' /proc/meminfo)
  if [[ -n "$_usable" && $(awk -v x="${_usable:-0}" -v f="$USABLE_FLOOR_GIB" 'BEGIN{print (x<f)?1:0}') == "1" ]]; then
    echo "ERROR: only ${_usable} GiB usable (< ${USABLE_FLOOR_GIB} GiB floor) — would global-OOM the box (GB10 unified pool). Aborting." >&2
    exit 2
  fi
  echo ">>> host usable memory: ${_usable} GiB (floor ${USABLE_FLOOR_GIB} GiB, gauge = MemAvailable − CmaFree)"
fi

echo ">>> [$STEP] $SCENARIO profile=$PROFILE client=$CLIENT seed=$SEED conc=$CONC endpoint=:$PORT warm=$WARM start=$TS"

# CONTAINER IDENTITY — fail here, not in the numbers (HD-489). `vllm-engine` is the COMPOSE
# SERVICE name; the container is IaC `spark_vllm_container`, which resolves to
# spark_llm_profiles[<profile>].container (group_vars/spark.yml), and the ultrafast arms may
# run under a different one. A wrong name is the SAME silent-no-op class as the 401-exits-0
# defect below: inspect fails, the API key reads empty, every request 401s, and a bench that
# exits 0 still prints a throughput line for a run that measured nothing.
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" != "true" ]; then
  echo "ERROR: container '$CONTAINER' is not running (compose service 'vllm-engine' != container name;" >&2
  echo "       the name is IaC spark_vllm_container -> spark_llm_profiles[spark_llm_profile].container)." >&2
  echo "       Pass VLLM_CONTAINER=<name> for the arm you are measuring." >&2
  exit 6
fi

# --- 1. metrics BEFORE -------------------------------------------------------
BEFORE_ENV=$(bash "$BENCH_DIR/snapshot-metrics.sh" "before-${STEP}-${SCENARIO}-${SEED}" >/dev/null; ls -t "$RAW"/metrics-*-before*.env | head -1)
# shellcheck disable=SC1090
source "$BEFORE_ENV"
B_EPOCH=$(date +%s); B_ISO="${TS_ISO:-}"
B_PREEMPT="${PREEMPT:-0}"; B_GEN="${GEN_TOK:-0}"; B_ACC="${ACCEPTED:-0}"; B_DR="${DRAFT:-0}"
B_PFXH="${PFX_HITS:-0}"; B_PFXQ="${PFX_QUERIES:-0}"; B_CACHE="${PROMPT_CACHED:-0}"
B_RECOMP="${RECOMP_TOK:-0}"; B_OK="${REQ_SUCCESS:-0}"

# --- 1b. state AT REST (§6.2: the seqs=8 / piecewise arms strand memory in the one pool) ----
# A stranding delta is uninterpretable without a rest baseline, so take it here — before the
# power sampler, before any request. Per-pid nvidia-smi UNDER-COUNTS the engine by ~10 GiB on
# this box (docs/hardware-spark.md §Unified-memory budget), so the column is labelled what it
# is (engine-pid MiB / all-pid MiB) and the engine's own `Available KV cache memory` line is
# the authoritative one — recorded alongside it.
AT_REST="$RAW/atrest-${RUN_TS}-${STEP}-${SCENARIO}.txt"
{
  date -u +%FT%TZ
  nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null \
    || echo "nvidia-smi: unavailable"
  awk '/^MemAvailable:/{a=$2}/^CmaFree:/{c=$2}END{printf "usable_gib %.1f\n",(a-c)/1048576}' /proc/meminfo 2>/dev/null || true
  docker logs "$CONTAINER" 2>&1 | tr '\r' '\n' \
    | grep -oE 'Available KV cache memory: [0-9.]+ [A-Za-z]+' | tail -1 || true
} > "$AT_REST" 2>&1
ENGINE_PID=$(docker inspect -f '{{.State.Pid}}' "$CONTAINER" 2>/dev/null || true)
# HD-489 tail A1: the atrest file is `nvidia-smi --query-compute-apps=pid,used_memory`, so
# col 1 = PID, col 2 = MiB. The old awk summed col 2 and matched col 1 against the engine PID
# but LABELLED the pair `engine/all` — which the u2/u3/u1 reports then misread as MiB pairs and
# turned a PID swap into a fake "+40 GB stranding". Print the columns UNDER THEIR REAL NAMES:
# the engine row is spelled `pid <PID>` so a later reader cannot confuse the two numbers.
MEM_AT_REST=$(awk -F',' -v p="${ENGINE_PID:-0}" 'NF>=2 && $2+0>0 {if ($1+0==p+0) e=$2} END{printf "engine_pid %d mib", e+0}' "$AT_REST" 2>/dev/null || echo "?")
USABLE_REST=$(awk '/^usable_gib/{print $2}' "$AT_REST" 2>/dev/null || true)
KV_AVAIL=$(grep -oE 'Available KV cache memory: .*' "$AT_REST" 2>/dev/null | tail -1 | sed 's/^Available KV cache memory: //' | tr ' ' '_' || true)

# --- 2. power sampler (Wh per 1k output tokens) ------------------------------
POWER_LOG="$RAW/power-${RUN_TS}-${STEP}-${SCENARIO}.csv"
nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits -l 1 > "$POWER_LOG" 2>/dev/null &
POWER_PID=$!
trap 'kill $POWER_PID 2>/dev/null || true' EXIT

# --- 3. run bench inside the container --------------------------------------
# Save JSON to container /tmp (tmpfs, writable), docker cp it out.
# CONT_RESULT = deterministic filename via --result-filename (CLI auto-names otherwise).
CONT_RESULT="/tmp/bench-result.json"
START_EPOCH=$(date +%s)
# vLLM bench CLI in this build: `vllm bench serve` (not python3 -m vllm.benchmarks.serve —
# that module has no __main__, it silently exits 0). Flags from the random dataset + options groups.
# AUTH (live hit 2026-09-16, HD-380): the engine runs with --api-key. Without an
# Authorization header EVERY request 401s and `vllm bench serve` still exits 0 while
# reporting "Successful requests: 0" / "Total input tokens: 0" — a silent no-op that
# looks like a pass. Any bench number taken after the spark-llm_api vault item landed
# is invalid until re-run. Key is read from the container's own argv so it never
# enters the repo.
API_KEY="$(docker inspect "$CONTAINER" --format '{{join .Config.Cmd " "}}' 2>/dev/null \
  | awk '{for(i=1;i<NF;i++) if($i=="--api-key") print $(i+1)}')"

# SCRUB THE BEARER BEFORE IT REACHES DISK (2026-09-18). `vllm bench serve` prints its own
# parsed argv, which contains `--header Authorization=Bearer <key>` — so every raw bench log
# written under this harness carries the live spark-llm_api credential. That is exactly how a
# live key landed in git history (bench logs + the stability tars archived from them, shipped
# to origin/main twice). Gate at the point of WRITE: an archive-time or commit-time scan is a
# detection net, not a boundary, and the thing that failed here was the writer.
scrub(){ sed -u -E 's/(Authorization[= ]Bearer |Bearer )[A-Za-z0-9_.:+-]{16,}/\1«REDACTED:spark-llm_api»/g'; }
SERVED="$(docker inspect "$CONTAINER" --format '{{join .Config.Cmd " "}}' 2>/dev/null \
  | awk '{for(i=1;i<NF;i++) if($i=="--served-model-name") print $(i+1)}')"
AUTH=()
[ -n "${API_KEY:-}" ] && AUTH=(--header "Authorization=Bearer $API_KEY")   # KEY=VALUE form required
[ -n "${SERVED:-}" ] && AUTH+=(--served-model-name "$SERVED")

docker exec "$CONTAINER" vllm bench serve \
  --backend openai-chat --model /model "${AUTH[@]}" \
  --base-url "http://localhost:${PORT}" --endpoint /v1/chat/completions \
  --dataset-name random --random-input-len "$IN" --random-output-len "$OUT" \
  --num-prompts "$N" --max-concurrency "$CONC" --seed "$SEED" \
  --save-result --result-filename bench-result.json --result-dir /tmp 2>&1 | scrub | tee "$RAW/benchlog-${RUN_TS}-${STEP}-${SCENARIO}-${SEED}.txt"
# ZERO-LOAD GUARD: rc/tee tells you nothing (see AUTH note). A no-op run must not be
# recorded as a bench result.
_ok=$(grep -oE 'Successful requests:[[:space:]]*[0-9]+' "$RAW/benchlog-${RUN_TS}-${STEP}-${SCENARIO}-${SEED}.txt" | grep -oE '[0-9]+$' | tail -1)
if [ "${_ok:-0}" -lt "$N" ]; then
  echo "ERROR: only ${_ok:-0}/$N requests succeeded — this run measured NOTHING (check auth/quota). Refusing to record it." >&2
  exit 5
fi
# tmpfs /tmp inside the container is not visible to docker cp (mount namespace) —
# read the result out via docker exec cat instead.
for _ in $(seq 1 30); do
  docker exec "$CONTAINER" test -f "$CONT_RESULT" 2>/dev/null && break
  sleep 2
done
docker exec "$CONTAINER" cat "$CONT_RESULT" > "$RAW/result-${RUN_TS}-${STEP}-${SCENARIO}-${SEED}.json" 2>/dev/null || true
END_EPOCH=$(date +%s)
DURATION=$((END_EPOCH - START_EPOCH))

kill $POWER_PID 2>/dev/null || true; wait $POWER_PID 2>/dev/null || true
MEAN_W=$(awk -F',' '{s+=$1; n++} END{if(n)printf "%.0f", s/n; else print "?"}' "$POWER_LOG")

# --- 4. metrics AFTER --------------------------------------------------------
AFTER_ENV=$(bash "$BENCH_DIR/snapshot-metrics.sh" "after-${STEP}-${SCENARIO}-${SEED}" >/dev/null; ls -t "$RAW"/metrics-*-after*.env | head -1)
# shellcheck disable=SC1090
source "$AFTER_ENV"
A_PREEMPT="${PREEMPT:-0}"; A_GEN="${GEN_TOK:-0}"; A_ACC="${ACCEPTED:-0}"; A_DR="${DRAFT:-0}"
A_PFXH="${PFX_HITS:-0}"; A_PFXQ="${PFX_QUERIES:-0}"; A_CACHE="${PROMPT_CACHED:-0}"
A_RECOMP="${RECOMP_TOK:-0}"; A_OK="${REQ_SUCCESS:-0}"
A_ISO="${TS_ISO:-}"

# Float deltas from Prometheus (vLLM counters are float) — integer $(( )) would choke.
fdelta(){ awk -v a="${1:-0}" -v b="${2:-0}" 'BEGIN{printf "%.0f", a-b}'; }
PREEMPT_DELTA=$(fdelta "$A_PREEMPT" "$B_PREEMPT")
GEN_DELTA=$(fdelta "$A_GEN" "$B_GEN")
PFXH_DELTA=$(fdelta "$A_PFXH" "$B_PFXH")
PFXQ_DELTA=$(fdelta "$A_PFXQ" "$B_PFXQ")
CACHE_DELTA=$(fdelta "$A_CACHE" "$B_CACHE")
RECOMP_DELTA=$(fdelta "$A_RECOMP" "$B_RECOMP")
OK_DELTA=$(fdelta "$A_OK" "$B_OK")
# MTP acceptance ratio — float-safe (guard d>0; awk div-by-zero is a hard fail under set -u/e)
if [[ "${A_DR:-0}" != "${B_DR:-0}" && "${A_DR:-0}" != "0" && "${A_DR:-0}" != "0.0" ]]; then
  _acc_delta=$(awk -v a="${A_ACC:-0}" -v b="${B_ACC:-0}" 'BEGIN{printf "%.3f", a-b}')
  _dr_delta=$(awk -v a="${A_DR:-0}" -v b="${B_DR:-0}" 'BEGIN{printf "%.3f", a-b}')
  if awk -v d="$_dr_delta" 'BEGIN{exit !(d>0)}'; then
    MTP_RATIO=$(awk -v a="$_acc_delta" -v d="$_dr_delta" 'BEGIN{printf "%.3f", a/d}')
  else MTP_RATIO="n/a"; fi
else MTP_RATIO="n/a"; fi
WH_PER_1K="n/a"
if [[ "$MEAN_W" != "?" && -n "${GEN_DELTA:-}" && "${GEN_DELTA:-0}" != "0" ]]; then
  if awk -v t="${GEN_DELTA:-0}" 'BEGIN{exit !(t>0)}'; then
    WH_PER_1K=$(awk -v w="$MEAN_W" -v s="$DURATION" -v t="${GEN_DELTA:-0}" 'BEGIN{printf "%.2f", (w*s/3600)/(t/1000)}')
  fi
fi

# --- 5. parse bench JSON -----------------------------------------------------
RESULT_JSON=$(ls -t "$RAW"/result-"${RUN_TS}"-*.json 2>/dev/null | head -1 || true)
if [[ -n "$RESULT_JSON" ]] && command -v jq >/dev/null; then
  TTFT_P50=$(jq -r '.ttft_p50_ms // .median_ttft_ms // empty' "$RESULT_JSON")
  TTFT_P99=$(jq -r '.ttft_p99_ms // .p99_ttft_ms // empty' "$RESULT_JSON")
  ITL_P50=$(jq  -r '.itl_p50_ms // .median_itl_ms // .mean_itl_ms // empty' "$RESULT_JSON")
  ITL_P99=$(jq  -r '.itl_p99_ms // .p99_itl_ms // empty' "$RESULT_JSON")
  OUT_THR=$(jq  -r '.output_throughput // empty' "$RESULT_JSON")
  TOT_THR=$(jq  -r '.total_token_throughput // empty' "$RESULT_JSON")
else
  TTFT_P50=; TTFT_P99=; ITL_P50=; ITL_P99=; OUT_THR=; TOT_THR=
fi

# per-stream decode tok/s at concurrency C = output_throughput / CONC
DEC_PER_STREAM="n/a"
[[ -n "${OUT_THR:-}" ]] && DEC_PER_STREAM=$(awk -v o="$OUT_THR" -v c="$CONC" 'BEGIN{printf "%.1f", o/c}')

# --- 6. window verdicts + append CSV row -------------------------------------
# cold_ok: is this row long enough for the 60 s VictoriaMetrics histograms to corroborate it?
# Anything under 180 s (3 cold scrapes) has no usable VM-side quantile — say so IN THE ROW
# rather than letting a later join invent one.
COLD_OK=no; [ "${DURATION:-0}" -ge 180 ] && COLD_OK=yes
# flag: the window-exclusivity test. request_success must move by exactly N; more means
# somebody else's traffic is inside the window and every counter delta on this row is theirs too.
# (The engine cannot separate arms by label — model_name is a client anchor — so this is the only
# exclusivity proof available, and it is cheap.)
FLAG="ok"
if [ "${OK_DELTA:-0}" != "$N" ]; then FLAG="contaminated:req_ok_delta=${OK_DELTA:-?}_expected=${N}"; fi
if [ "${PREEMPT_DELTA:-0}" != "0" ]; then FLAG="${FLAG};preempt_delta=${PREEMPT_DELTA}"; fi

[[ -f "$CSV" ]] || echo "step,ts,scenario,profile,client,seed,endpoint,warm,vm_start_utc,vm_end_utc,duration_s,cold_ok,ttft_p50_ms,ttft_p99_ms,itl_p50_ms,itl_p99_ms,dec_tok_s_per_stream,out_throughput_total,total_throughput,req_ok_delta,preempt_delta,gen_tok_delta,pfx_hit_delta,pfx_query_delta,cached_tok_delta,recomp_tok_delta,mtp_accept,mem_at_rest_engine_over_all_mib,usable_at_rest_gib,kv_avail_gib,mean_power_W,wh_per_1k_out,flag" >> "$CSV"
echo "${STEP},${RUN_TS},${SCENARIO},${PROFILE},${CLIENT},${SEED},:$PORT,${WARM},${B_ISO},${A_ISO},${DURATION},${COLD_OK},${TTFT_P50:-},${TTFT_P99:-},${ITL_P50:-},${ITL_P99:-},${DEC_PER_STREAM},${OUT_THR:-},${TOT_THR:-},${OK_DELTA},${PREEMPT_DELTA},${GEN_DELTA},${PFXH_DELTA},${PFXQ_DELTA},${CACHE_DELTA},${RECOMP_DELTA},${MTP_RATIO},${MEM_AT_REST:-?},${USABLE_REST:-?},${KV_AVAIL:-?},${MEAN_W},${WH_PER_1K},${FLAG}" >> "$CSV"

echo ">>> done. profile=${PROFILE} ttft_p50=${TTFT_P50:-?}ms ttft_p99=${TTFT_P99:-?}ms itl_p50=${ITL_P50:-?}ms dec/stream=${DEC_PER_STREAM} total_out=${OUT_THR:-?} tok/s"
echo ">>>      window=${B_ISO}..${A_ISO} (${DURATION}s, cold_ok=${COLD_OK}) ok_delta=${OK_DELTA:-?}/$N preempts=+${PREEMPT_DELTA} mtp=${MTP_RATIO} power=${MEAN_W}W wh/1k=${WH_PER_1K}"
echo ">>>      pin: recomputed_tokens=+${RECOMP_DELTA} prefix_hits=+${PFXH_DELTA} queries=+${PFXQ_DELTA} cached=+${CACHE_DELTA}"
echo ">>>      at rest: engine/all pid MiB=${MEM_AT_REST:-?} usable=${USABLE_REST:-?} GiB KV_avail=${KV_AVAIL:-?} (detail: $AT_REST)"
[ "$FLAG" = "ok" ] || echo ">>>      FLAG=${FLAG}  <-- do NOT quote this row as arm-vs-arm evidence"
echo ">>>      cross-check it: bash vm-window.sh --csv $CSV --ts $RUN_TS"
echo ">>> appended to $CSV"
