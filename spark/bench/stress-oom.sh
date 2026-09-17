#!/usr/bin/env bash
# ============================================================================
# stress-oom.sh — reproduce / disambiguate the spark GB10 GLOBAL-OOM class.
#
# NOT the same thing as C1/C2/C3 (those certify throughput). This targets the
# mechanism that actually killed the box, and it is deliberately NOT "fill the
# KV cache": the KV pool is carved at boot (--kv-cache-memory-bytes 8.8e9 = 8.2
# GiB) and NEVER GROWS, so "GPU KV cache usage: 34%" is scheduler occupancy, not
# RAM. Filling KV to 100% exercises preemption/recompute — a graceful in-engine
# path — and would pass while leaving the killer untouched. A test that cannot
# fail is not a test. See docs/hardware-spark.md §Unified-memory budget.
#
# PHASES
#   A shape-churn    alternating concurrency 1/2/3 with mixed input lengths →
#                    forces vLLM to capture NEW cudagraph/inductor shapes lazily
#                    mid-serve. This is the 2026-09-16 20:21Z kill: two sessions
#                    at 8.8%/9.1% ctx (18% of window combined, 34.7% of KV) —
#                    nowhere near memory-limited — preceded by the engine's own
#                    "shm_broadcast ... 60 seconds" stall 18 s before the kill.
#   B prefill-burst  N CONCURRENT *fresh* (unique-seed) large prefills. This is
#                    the unprofiled activation transient that --kv-cache-memory-
#                    bytes does not bound (it makes vLLM SKIP memory profiling),
#                    and it is gated by --max-num-batched-tokens (live: 16384).
#                    Escalating ladder; every rung is a separate decision.
#   C idle-decay     PASSIVE — the deployed spark-oom-watchdog sampler answers
#                    this (2026-09-16 16:31Z OOMed with NO client attached).
#                    This script prints where to read the curve.
#
# PROMPT-CACHE TRAP: prefix-cache hit rate on this engine is ~96%. Re-sending the
# same prompt means the prefill never runs and you measure nothing. Every step
# uses a fresh --seed for exactly that reason (never pass --warm here).
#
# GUARDS (why this is safe to run on a box that has wedged twice)
#   * MEM_FLOOR_GB preflight, default 14. The old run-scenario.sh floor of 8 GiB
#     sits INSIDE the danger zone — the box now idles at ~16 GiB available.
#   * live guard: stops the ENGINE on floor breach or PSI breach, so the kernel
#     global OOM killer never gets to pick the victim (it has taken sshd,
#     NetworkManager, polkitd, alloy, dcgm-exporter and pipewire).
#   * engine RestartCount sampled per step: a change marks that step DEAD, and
#     the watchdog (installed by roles/spark) captures the forensic bundle.
#
# RUN IT FROM THE LAPTOP, never from an agent session whose own model is spark:
# 2026-09-16 09:26Z an agent session drove spark's own endpoint and OOMed the box
# it was running on (incident #3). Invoke as:
#   ssh spark 'bash -s' -- < spark/bench/stress-oom.sh
#   ssh spark 'SPARK_STRESS_MAX_RUNG=2 bash /path/to/stress-oom.sh'
# ============================================================================
set -uo pipefail

CONTAINER="${VLLM_CONTAINER:-vllm-qwen-spark}"
PORT="${VLLM_PORT:-8000}"
MEM_FLOOR_GB="${MEM_FLOOR_GB:-14}"      # GB10: box idles ~16 GiB avail post-fix
PSI_FULL_MAX="${PSI_FULL_MAX:-30}"      # PSI memory full avg10 (%)
PSI_ABORT="${PSI_ABORT:-50}"            # hard abort mid-step
SPARK_STRESS_MAX_RUNG="${SPARK_STRESS_MAX_RUNG:-3}"
RUNG_PAUSE="${RUNG_PAUSE:-45}"          # s between rungs: let the pool settle
BENCH_IN="${BENCH_IN:-49152}"           # large-prefill size (~19% of 262k ctx)
TS="$(date -u +%Y%m%d-%H%M%S)"
OUTDIR="${STRESS_OUT:-$(cd "$(dirname "$0")" && pwd)/raw}"
LOG="$OUTDIR/stress-oom-$TS.log"
mkdir -p "$OUTDIR"
ABORT_MARK="${STRESS_ABORT_MARK:-/tmp/stress-oom-ABORTED-$TS}"

# ---- auth + served name (LIVE HIT 2026-09-16: silent zero-load bench) ------
# The engine runs with --api-key, so every `vllm bench serve` request without an
# Authorization header gets 401 Unauthorized — and `vllm bench serve` STILL EXITS 0
# while reporting "Successful requests: 0". The first HD-380 run therefore looked
# like a clean pass across 21 steps while applying ZERO load (Total input tokens: 0).
# run-scenario.sh has the same defect: any bench number taken after the spark-llm_api
# vault item landed is measuring nothing. Never trust rc — assert on the counters.
API_KEY="$(docker inspect "$CONTAINER" --format '{{join .Config.Cmd " "}}' 2>/dev/null \
  | awk '{for(i=1;i<NF;i++) if($i=="--api-key") print $(i+1)}')"
SERVED="$(docker inspect "$CONTAINER" --format '{{join .Config.Cmd " "}}' 2>/dev/null \
  | awk '{for(i=1;i<NF;i++) if($i=="--served-model-name") print $(i+1)}')"
AUTH=()
[ -n "${API_KEY:-}" ] && AUTH=(--header "Authorization=Bearer $API_KEY")   # KEY=VALUE form required
[ -n "${SERVED:-}" ] && AUTH+=(--served-model-name "$SERVED")

log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$LOG"; }
die()   { log "FATAL: $*"; exit 1; }

avail_gib() { awk '/^MemAvailable:/{printf "%.1f",$2/1048576}' /proc/meminfo; }
psi_full()  { awk '$1=="full"{for(i=2;i<=NF;i++) if($i~/^avg10=/){split($i,a,"=");printf "%.0f",a[2];exit}}' /proc/pressure/memory; }
restarts()  { docker inspect "$CONTAINER" --format '{{.RestartCount}}' 2>/dev/null || echo NA; }
gpu_mib()   { timeout 8 nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null \
              | sort -t, -k2 -rn | head -1 | cut -d, -f2 | tr -d ' '; }

# ---- live guard ------------------------------------------------------------
guard_stop_engine() {
  log "GUARD FIRE: $1 — stopping $CONTAINER so the KERNEL does not choose the victim"
  touch "$ABORT_MARK" 2>/dev/null
  docker stop -t 20 "$CONTAINER" >>"$LOG" 2>&1
  # WHY THIS MUST BRING THE ENGINE BACK (live hit 2026-09-16 22:15Z): `docker stop` is
  # an INTENTIONAL operator stop, so `restart: unless-stopped` deliberately does NOT
  # restart it — that policy means "restart on crash UNLESS a human stopped it". The
  # first guard fire therefore left the family without an LLM for ~14 min until a
  # manual `docker start`, and it was indistinguishable from an engine crash.
  # So: drain the pool, then self-heal, then still abort the run.
  local i a
  for i in $(seq 1 24); do
    a=$(avail_gib)
    awk -v x="${a:-0}" -v f="$((MEM_FLOOR_GB + 4))" 'BEGIN{exit !(x>=f)}' && break
    sleep 5
  done
  log "pool drained to ${a} GiB — restarting $CONTAINER (guard aborts the run, not the service)"
  docker start "$CONTAINER" >>"$LOG" 2>&1 && log "engine restart issued; weight reload ~170s"
  log "guard exiting. Forensics: /mnt/spark_nvme/oom-watchdog/snapshots/"
  exit 3
}

guard_loop() {
  while :; do
    [ -f "$ABORT_MARK" ] && exit 0
    a=$(avail_gib); p=$(psi_full)
    awk -v x="${a:-99}" -v f="$MEM_FLOOR_GB" 'BEGIN{exit !(x<f)}' && guard_stop_engine "MemAvailable ${a} GiB < floor ${MEM_FLOOR_GB} GiB"
    awk -v x="${p:-0}" -v m="$PSI_ABORT"  'BEGIN{exit !(x>m)}' && guard_stop_engine "PSI full avg10 ${p}% > ${PSI_ABORT}%"
    sleep 5
  done
}

preflight() { # refuse to start/continue a step that is guaranteed to OOM the box
  local a p; a=$(avail_gib); p=$(psi_full)
  log "preflight: MemAvailable=${a}GiB PSI-full=${p}% engine-restarts=$(restarts) gpu-top=$(gpu_mib)MiB"
  awk -v x="${a:-0}" -v f="$MEM_FLOOR_GB" 'BEGIN{exit !(x<f)}' && die "only ${a} GiB available (< ${MEM_FLOOR_GB} GiB floor) — would global-OOM the box"
  awk -v x="${p:-0}" -v m="$PSI_FULL_MAX" 'BEGIN{exit !(x>m)}' && die "PSI full avg10 ${p}% > ${PSI_FULL_MAX}% — pool already thrashing, not a valid test window"
}

serve() { # in out conc seed label
  local in=$1 out=$2 conc=$3 seed=$4 label=$5 r0 STEPLOG
  r0=$(restarts)
  STEPLOG="$OUTDIR/step-$label-$TS.log"
  log "STEP $label: in=$in out=$out conc=$conc seed=$seed avail=$(avail_gib)GiB"
  timeout "${STEP_TIMEOUT:-900}" docker exec "$CONTAINER" vllm bench serve \
    --backend openai-chat --model /model "${AUTH[@]}" \
    --base-url "http://localhost:$PORT" --endpoint /v1/chat/completions \
    --dataset-name random --random-input-len "$in" --random-output-len "$out" \
    --num-prompts "$conc" --max-concurrency "$conc" --seed "$seed" \
    >"$STEPLOG" 2>&1
  local rc=$? r1; r1=$(restarts)
  # ZERO-LOAD GUARD: rc is meaningless here (see auth note above). Threshold SCALES
  # with the requested load — a flat floor wrongly aborts short steps (live hit
  # 2026-09-16: in=512 conc=1 aborted on in_tok=564). Require all requests OK and at
  # least half the requested input tokens actually processed.
  local ok tok want; ok=$(grep -oE 'Successful requests:[[:space:]]*[0-9]+' "$STEPLOG" | grep -oE '[0-9]+$' | tail -1)
  tok=$(grep -oE 'Total input tokens:[[:space:]]*[0-9]+' "$STEPLOG" | grep -oE '[0-9]+$' | tail -1)
  want=$(( in * conc / 2 ))
  log "STEP $label: rc=$rc ok=${ok:-?}/${conc} in_tok=${tok:-?} after: avail=$(avail_gib)GiB gpu-top=$(gpu_mib)MiB restarts=$r1 $([ "$r0" != "$r1" ] && echo '*** ENGINE DIED ***')"
  if [ "${ok:-0}" -lt "$conc" ] || [ "${tok:-0}" -lt "$want" ]; then
    log "INVALID RUN: step $label applied no real load (ok=${ok:-0}/$conc, in_tok=${tok:-0})."
    log "  first error: $(grep -m1 -iE 'Error [0-9]+:|Unauthorized|Traceback' "$STEPLOG" | cut -c1-120)"
    log "  A no-op step cannot certify anything — aborting instead of reporting a pass."
    kill "$GUARD" 2>/dev/null || true
    exit 4
  fi
  [ "$r0" != "$r1" ] && log "ENGINE RESTARTED during $label — watchdog bundle is the evidence; check /mnt/spark_nvme/oom-watchdog/snapshots/"
  return 0
}

# ---- preflight -------------------------------------------------------------
docker inspect "$CONTAINER" --format '{{.State.Status}}' 2>/dev/null | grep -q running \
  || die "$CONTAINER is not running"
curl -sf --max-time 5 "http://localhost:$PORT/health" >/dev/null || die "engine :$PORT/health not 200"
command -v nvidia-smi >/dev/null || log "WARN: nvidia-smi absent — device-side gauge disabled"
[ -d /mnt/spark_nvme/oom-watchdog ] || log "WARN: OOM watchdog dir absent — install roles/spark watchdog before stressing"

log "=== stress-oom $TS | floor=${MEM_FLOOR_GB}GiB psi_max=${PSI_FULL_MAX}% max_rung=$SPARK_STRESS_MAX_RUNG prefill_in=$BENCH_IN ==="
preflight
log "engine per-pid at REST: $(gpu_mib) MiB | MemAvailable $(avail_gib) GiB   <-- the baseline every phase is judged against"

guard_loop & GUARD=$!
trap 'kill $GUARD 2>/dev/null || true' EXIT

# ---- PHASE A: shape churn --------------------------------------------------
log "--- PHASE A: shape churn (lazy cudagraph/inductor capture under mixed batch shapes) ---"
i=0
for conc in 1 2 3 2 1 3; do
  for in in 512 4096 16384; do
    i=$((i+1)); preflight
    serve "$in" 128 "$conc" "$((1000+i*7))" "A${i} c$conc in$in"
  done
done

# ---- PHASE B: fresh large-prefill bursts (escalating) ---------------------
log "--- PHASE B: concurrent FRESH large prefills (unprofiled activation transient) ---"
log "KV pool is FIXED at 8.2 GiB / 283,398 tok — rungs below are sized by PREFILL, not by KV occupancy"
for rung in 1 2 3; do
  [ "$rung" -gt "$SPARK_STRESS_MAX_RUNG" ] && break
  conc=$((rung + 1))                      # rung1=2 sessions, 2=3, 3=4 (max_num_seqs=4)
  log "RUNG $rung: $conc concurrent x ${BENCH_IN}-token FRESH prefills (~$(( conc * BENCH_IN / 1024 ))k tok in flight)"
  preflight
  serve "$BENCH_IN" 256 "$conc" "$((5000+rung*13))" "B$rung x$conc"
  log "post-rung: avail=$(avail_gib)GiB gpu-top=$(gpu_mib)MiB — pausing ${RUNG_PAUSE}s to let the pool settle"
  sleep "$RUNG_PAUSE"
done

kill $GUARD 2>/dev/null || true
log "=== DONE. rest: avail=$(avail_gib)GiB gpu-top=$(gpu_mib)MiB restarts=$(restarts) ==="
log "PHASE C (idle decay) is PASSIVE: systemctl status spark-oom-watchdog; read the pre-event curve with"
log "  tail -50 /mnt/spark_nvme/oom-watchdog/state/samples.csv   # watch gpu_top_mib ratchet upward while idle"
log "  spark-oom-watchdog.sh status"
log "log: $LOG"
