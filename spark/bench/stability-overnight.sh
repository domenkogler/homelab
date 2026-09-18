#!/usr/bin/env bash
# ============================================================================
# stability-overnight.sh — spark stability chain. RUNS ON SPARK, RESUMABLE.
#
# Companion: bench/stability-supervise.sh runs ON THE LAPTOP and relaunches this
# script after a crash/wedge. That split is deliberate:
#   * the chain belongs on the box (fast probes, docker/nvidia-smi, no ssh per read);
#   * a global kernel OOM can kill sshd (#2/#3), so the chain dies with it — and on a
#     reboot `journalctl -k -b 0` becomes the NEW boot, so that evidence is gone;
#   * therefore ALL state and evidence live on XFS (/mnt/spark_nvme), which survives a
#     power-cycle, and the OOM-immune spark-oom-watchdog (OOMScoreAdjust=-1000) keeps
#     snapshotting even when this script cannot.
#   * on relaunch this script finds out what happened while it was dead (boot_id change,
#     the watchdog's last_KILL marker) and RESUMES at the first unfinished run.
#
# Launch it via the supervisor, or directly:
#   ssh spark 'setsid nohup bash /opt/stability/stability-overnight.sh >/dev/null 2>&1 </dev/null &'
#   ssh spark 'bash /opt/stability/stability-overnight.sh --status'
#
# Exit: 0 PASSED · 1 FAILED · 2 preflight refused · 3 all runs already finished
# ============================================================================
set -uo pipefail

CTR="${VLLM_CONTAINER:-vllm-qwen-spark}"
PORT="${VLLM_PORT:-8000}"
DIR="${STABILITY_DIR:-/mnt/spark_nvme/stability}"      # XFS: survives the wedge AND a power-cycle
CSV=/mnt/spark_nvme/oom-watchdog/state/samples.csv
WD_STATE=/mnt/spark_nvme/oom-watchdog/state
STENV="$DIR/state.env"
MAIN="$DIR/chain.log"
DONE="$DIR/OVERNIGHT.done"
BENCH="${STABILITY_BENCH:-$DIR/stress-oom.sh}"
RESERVE_GIB="${STABILITY_RESERVE_GIB:-12}"     # the worst observed moment stays this far above zero
MAX_KILLS="${STABILITY_MAX_KILLS:-2}"          # continue through this many, then stop (cascade guard)
COOLDOWN="${STABILITY_COOLDOWN:-300}"          # s of quiet after a kill before the next run
RECOVER_WAIT="${STABILITY_RECOVER_WAIT:-600}"  # s to let usable come back after a kill
HEALTH_WAIT="${STABILITY_HEALTH_WAIT:-600}"    # s for the engine (weight reload ~180 s)
KV_KIB_PER_TOK=30.3                            # measured: 8.2 GiB / 283,398 tok
CTX="${STABILITY_CTX:-262144}"
# 2026-09-18: the full-window rung is sized at 240000, NOT $CTX. A 262,144-token chat
# request costs +~20.5k template tokens → lands at ~282.7k > max_model_len 262144 →
# vLLM rejects it 400 before any load (live: rung B1 x2 ok=0/2, in_tok=0, Bad Request).
# 240k → ~260.5k actual, undershoot; 2×240k ≈ 94.6% of a 16 GiB pool = the intended
# "two full-context sessions, nothing cached" worst case.
mkdir -p "$DIR/logs" "$DIR/evidence"

log(){ printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$MAIN"; }
usable(){ awk '/^MemAvailable:/{a=$2}/^CmaFree:/{c=$2}END{printf "%.2f",(a-c)/1048576}' /proc/meminfo; }
top_mib(){ nvidia-smi --query-compute-apps=used_memory --format=csv,noheader,nounits | sort -rn | head -1; }
oom_ct(){ sudo journalctl -k -b 0 --no-pager 2>/dev/null | grep -c 'invoked oom-killer'; }
nvrm_ct(){ sudo dmesg 2>/dev/null | grep -c NV_ERR_NO_MEMORY; }
rst(){ docker inspect "$CTR" --format '{{.RestartCount}}' 2>/dev/null || echo 0; }
health(){ curl -s -o /dev/null -w '%{http_code}' --max-time 5 "localhost:$PORT/health"; }
inflight(){ curl -s --max-time 5 "localhost:$PORT/metrics" | awk '/^vllm:num_requests_running/{s+=$2}END{print s+0}'; }
boot_id(){ cat /proc/sys/kernel/random/boot_id; }
kv_gib(){ docker inspect "$CTR" --format '{{join .Config.Cmd " " }}' | awk '{for(i=1;i<NF;i++) if($i=="--kv-cache-memory-bytes") printf "%.1f", $(i+1)/1073741824}'; }
n(){ printf '%s' "${1:-0}" | tr -dc '0-9'; }
save(){ { echo "BASE_EPOCH=$BASE_EPOCH"; echo "BASE_USABLE=$BASE_USABLE"; echo "BASE_TOP=$BASE_TOP"
         echo "BASE_RESTARTS=$BASE_RESTARTS"; echo "BASE_OOM=$BASE_OOM"; echo "BASE_NVRM=$BASE_NVRM"
         echo "BOOT_ID=$BOOT_ID"; echo "KV_GIB=$KV_GIB"; echo "KILLS=$KILLS"; echo "REBOOTS=$REBOOTS"
         echo "RUNS_DONE=\"${RUNS_DONE[*]}\""; echo "CKPT_EPOCH=$(date +%s)"; } > "$STENV"; }

RUNS=(
  "rung123|SPARK_STRESS_MAX_RUNG=3 MEM_FLOOR_GB=18|full ladder: shape churn + prefill rungs 1-3"
  "compact|SPARK_STRESS_MAX_RUNG=1 BENCH_IN=200000 RUNG_PAUSE=90 MEM_FLOOR_GB=18|two concurrent 200k fresh prefills = 400k tok vs a 283,398-tok pool (compaction-vs-compaction)"
  "fullwindow|SPARK_STRESS_MAX_RUNG=1 BENCH_IN=240000 RUNG_PAUSE=120 MEM_FLOOR_GB=16|two concurrent ~full-window uncached prefills (2×240k ≈ 94.6% of a 16 GiB pool; hardest realistic case — one pi auto-compaction is ONE of these; sized to undershoot max_model_len, see CTX note above)"
)
if [ -n "${STABILITY_RUNS:-}" ]; then IFS=';' read -r -a RUNS <<<"$STABILITY_RUNS"; fi

# ---- --status -------------------------------------------------------------
if [ "${1:-}" = "--status" ]; then
  echo "=== spark stability chain — $(date -u '+%Y-%m-%d %H:%M UTC') ==="
  pgrep -f 'stability-overnigh[t].sh' >/dev/null 2>&1 && echo "STATE: running on spark" || echo "STATE: not running"
  echo "live: usable=$(usable) GiB top=$(top_mib) MiB restarts=$(rst) oom-kill=$(oom_ct) health=$(health)"
  [ -f "$STENV" ] && { echo "--- state ---"; cat "$STENV"; }
  echo "--- chain log (tail) ---"; tail -20 "$MAIN" 2>/dev/null || echo "(none)"
  echo "--- verdict ---"; cat "$DONE" 2>/dev/null || echo "(not finished)"
  exit 0
fi

DRY=0; FAKE_KILL=0; FRESH=0
[ "${1:-}" = "--dry-run" ] && DRY=1
[ "${1:-}" = "--fake-kill" ] && { DRY=1; FAKE_KILL=1; }
[ "${1:-}" = "--fresh" ] && FRESH=1
[ "$FRESH" = "1" ] && { rm -f "$DONE" "$STENV"; log "--fresh: state + verdict cleared"; }

# ---- resume or start fresh -------------------------------------------------
RUNS_DONE=(); KILLS=0; REBOOTS=0; BASE_EPOCH=0
if [ -f "$DONE" ]; then
  echo "The chain already finished. Verdict:"; cat "$DONE"
  echo "(to re-run: rm $DONE $STENV)"; exit 3
fi
if [ -f "$STENV" ]; then
  . "$STENV"
  # RUNS_DONE is persisted as one quoted string; source it back into an array (a scalar
  # would silently swallow `+=` and report the wrong count).
  _done_str="${RUNS_DONE:-}"; unset RUNS_DONE; RUNS_DONE=()
  for _w in $_done_str; do RUNS_DONE+=("$_w"); done; unset _done_str _w
  NEWBOOT=$(boot_id)
  log "=== RESUMING: ${#RUNS_DONE[@]}/${#RUNS[@]} runs done, kills so far $KILLS ==="
  if [ "$NEWBOOT" != "${BOOT_ID:-}" ]; then
    REBOOTS=$((REBOOTS + 1)); KILLS=$((KILLS + 1))
    log "  the box REBOOTED since the last checkpoint — that is a wedge, counted as a kill"
    BOOT_ID="$NEWBOOT"
  fi
  # the watchdog is OOM-immune: its markers tell us what we missed while we were dead
  if [ -f "$WD_STATE/last_KILL" ]; then
    kmt=$(stat -c %Y "$WD_STATE/last_KILL" 2>/dev/null || echo 0)
    [ "${kmt:-0}" -gt "${CKPT_EPOCH:-0}" ] && { KILLS=$((KILLS + 1)); log "  watchdog recorded a kernel OOM while this chain was dead (last_KILL @ $(date -u -d @$kmt +%H:%M:%S))"; }
  fi
  save
else
  # --- fresh start: preflight, then baseline ---
  [ -f "$BENCH" ] || { echo "FATAL: bench harness missing at $BENCH (copy stress-oom.sh there first)"; exit 2; }
  [ "$(health)" = "200" ] || { log "PREFLIGHT FAIL: engine /health=$(health)"; echo "RESULT: NOT RUN — engine unhealthy" > "$DONE"; exit 2; }
  IF=$(inflight)
  if [ "${IF:-1}" != "0" ] && [ "$DRY" = "0" ]; then
    log "PREFLIGHT FAIL: $IF request(s) in flight — close the agent sessions running ON spark"; echo "RESULT: NOT RUN — $IF requests in flight" > "$DONE"; exit 2; fi
  BASE_USABLE=$(usable)
  awk -v x="${BASE_USABLE:-0}" -v f=26 'BEGIN{exit !(x<f)}' && { log "PREFLIGHT FAIL: usable ${BASE_USABLE} GiB < 26 GiB"; echo "RESULT: NOT RUN — usable ${BASE_USABLE} GiB at start" > "$DONE"; exit 2; }
  BASE_EPOCH=$(date +%s); BASE_TOP=$(top_mib); BASE_RESTARTS=$(n "$(rst)")
  BASE_OOM=$(n "$(oom_ct)"); BASE_NVRM=$(n "$(nvrm_ct)"); BOOT_ID=$(boot_id); KV_GIB=$(kv_gib); KV_GIB=${KV_GIB:-8.2}
  save
  log "=== stability-overnight start (reserve ${RESERVE_GIB} GiB, ctx ${CTX}, kills cap ${MAX_KILLS}) ==="
  log "baseline: usable=${BASE_USABLE}GiB top=${BASE_TOP}MiB restarts=${BASE_RESTARTS} oom-kill=${BASE_OOM} nvrm=${BASE_NVRM} kv=${KV_GIB}GiB"
  [ "$DRY" = "1" ] && log "DRY-RUN: no load applied"
fi

FAILED=0; STOPREASON=""

wait_healthy(){ local i; for i in $(seq 1 $((HEALTH_WAIT/10))); do [ "$(health)" = "200" ] && return 0; sleep 10; done; return 1; }

capture_evidence(){ # the box may be power-cycled by morning — snapshot to XFS now
  local tag=$1
  local D="$DIR/evidence/$(date +%Y%m%d-%H%M%S)-$tag"   # separate statements: bash expands all local words first
  mkdir -p "$D"
  { echo "tag=$tag utc=$(date -u -Is) usable=$(usable) top=$(top_mib) restarts=$(rst)"; uptime; } > "$D/00-state.txt"
  sudo journalctl -k -b 0 --no-pager 2>/dev/null | grep -iE 'oom-kill|Out of memory|Killed process' | tail -80 > "$D/01-kernel-oom.txt"
  sudo dmesg -T 2>/dev/null | grep -i 'NV_ERR_NO_MEMORY' | tail -30 > "$D/02-nvrm.txt"
  /usr/local/bin/spark-oom-watchdog.sh status > "$D/03-watchdog.txt" 2>&1
  tail -300 "$CSV" > "$D/04-sampler-tail.csv" 2>/dev/null
  sudo docker logs --tail 150 "$CTR" > "$D/05-engine-tail.txt" 2>&1
  free -g > "$D/06-mem.txt"
  log "  evidence snapshotted: $D"
}

recover_gate(){ local from=$1 waited=0 u
  log "  cooldown ${COOLDOWN}s after the kill from $from"; sleep "$COOLDOWN"
  while [ "$waited" -lt "$RECOVER_WAIT" ]; do
    u=$(usable)
    awk -v x="${u:-0}" -v f="$RESERVE_GIB" 'BEGIN{exit !(x>=f)}' && { log "  recovered: usable=${u} GiB"; return 0; }
    sleep 30; waited=$((waited + 30))
  done
  STOPREASON="host did not recover after the kill from $from (usable stuck at $(usable) GiB < ${RESERVE_GIB} GiB) — refusing to hammer an exhausted box"
  log "  $STOPREASON"; return 1
}

register_kill(){ # ONE place that counts a kill, snapshots evidence, and applies the cascade guard
  local from=$1
  KILLS=$((KILLS + 1)); capture_evidence "kill-$from"
  log "  KILL #$KILLS recorded from $from — continuing per policy (cap $MAX_KILLS)"
  save
  if [ "$KILLS" -ge "$MAX_KILLS" ]; then
    STOPREASON="$KILLS kills — that is the #4/#5/#7/#8 cascade pattern; stopping so the box is still alive in the morning"
    return 1
  fi
  wait_healthy || { docker start "$CTR" >/dev/null 2>&1 && log "  docker start issued (weight reload ~180s)"; }
  wait_healthy || { STOPREASON="engine not healthy within ${HEALTH_WAIT}s after a kill"; return 1; }
  recover_gate "$from"
}

run_one(){ # name env desc
  local name=$1 envs=$2 desc=$3 rc o1 r1 o2 r2 gu steps
  local dn; for dn in "${RUNS_DONE[@]:-}"; do [ "$dn" = "$name" ] && { log "SKIP $name (already completed)"; return 0; }; done
  o1=$(n "$(oom_ct)"); r1=$(n "$(rst)")
  log "RUN $name START — $desc"
  if [ "$DRY" = "1" ]; then sleep 5; rc=0; : > "$DIR/logs/$name.log"
  else
    env $envs STRESS_OUT="$DIR/logs" bash "$BENCH" > "$DIR/logs/$name.log" 2>&1; rc=$?
  fi
  o2=$(n "$(oom_ct)"); r2=$(n "$(rst)")
  gu=$(n "$(grep -c 'GUARD FIRE' "$DIR/logs/$name.log" 2>/dev/null)")
  steps=$(n "$(grep -c 'STEP .*: rc=' "$DIR/logs/$name.log" 2>/dev/null)")
  log "RUN $name END rc=$rc steps=$steps oom-kill ${o1}->${o2} restarts ${r1}->${r2} guard-fires=$gu"
  [ -s "$DIR/logs/$name.log" ] && log "  last: $(tail -1 "$DIR/logs/$name.log" | cut -c1-110)"

  # a zero-load step is not a stability finding, it is an invalid measurement: a PASS here would be fake
  [ "$rc" = "4" ] && { STOPREASON="$name applied no real load (zero-load step) — a pass would be fake"; return 1; }

  local died=0 why=""
  [ "$FAKE_KILL" = "1" ] && o2=$((o1 + 1))
  if [ "$o2" -gt "$o1" ]; then died=1; why="kernel global OOM x$((o2-o1))"; fi
  if [ "$r2" -gt "$r1" ] && [ "$gu" -le 0 ]; then died=1; why="${why:+$why + }engine restarted with no GUARD FIRE"; fi
  [ "$rc" = "3" ] && log "  ($name: the guard stopped/restarted the engine on its own floor = governor PASS, peak INCONCLUSIVE)"

  if [ "$died" = "1" ]; then
    log "  $why during $name — recorded"
    RUNS_DONE+=("$name"); save
    register_kill "$name" || return 1
  else
    RUNS_DONE+=("$name"); save
    wait_healthy || { STOPREASON="$name: engine not healthy after the run"; return 1; }
  fi
  return 0
}

for entry in "${RUNS[@]}"; do
  IFS='|' read -r name envs desc <<<"$entry"
  if run_one "$name" "$envs" "$desc"; then log "RUN $name -> continue (kills $KILLS/${MAX_KILLS})"
  else FAILED=1; log "CHAIN STOP: $STOPREASON"; break; fi
done

# ---- verdict + KV arithmetic ----------------------------------------------
MIN_U=""; MAX_T=0
if [ -f "$CSV" ]; then
  read MIN_U MAX_T <<<"$(awk -F, -v b="$BASE_EPOCH" '$1 ~ /^[0-9]+$/ && $1+0>b+0 && NF>11 {v=$10+0;u=$12+0; if(!s||u<m)m=u; if(v>t)t=v; s=1} END{if(s) printf "%.2f %d", m, t; else printf "NONE 0"}' "$CSV")"
fi
SAMPLES_OK=1
if [ -z "$MIN_U" ] || [ "$MIN_U" = "NONE" ]; then
  # the sampler writes every 15 s — a very short run can produce zero rows in the window.
  # Do NOT let an empty sample read "usable hit 0 GiB"; fall back to the live value and say so.
  SAMPLES_OK=0; MIN_U=$(usable); MAX_T=$(top_mib)
  log "WARN: no sampler rows in the run window (<15 s run?) — judging on the live reading instead"
fi
NOW_OOM=$(n "$(oom_ct)"); NOW_RST=$(n "$(rst)"); NOW_H=$(health); NOW_NVRM=$(n "$(nvrm_ct)"); IDLE_U=$(usable)
[ "$KILLS" -gt 0 ] && FAILED=1
[ "$NOW_OOM" -gt "${BASE_OOM:-0}" ] && FAILED=1
[ -n "$STOPREASON" ] || {
  if   [ "$KILLS" -gt 0 ]; then STOPREASON="$KILLS kill(s) during the chain — a global OOM IS the failure mode (the chain continued through them, so you have the whole picture)"
  elif [ "$NOW_OOM" -gt "${BASE_OOM:-0}" ]; then STOPREASON="kernel global OOM detected in the final check"
  elif [ "${NOW_H:-0}" != "200" ]; then STOPREASON="engine /health=$NOW_H after the run"
  elif awk -v x="${MIN_U:-99}" -v f="$RESERVE_GIB" 'BEGIN{exit !(x<f)}'; then STOPREASON="usable bottomed at ${MIN_U} GiB, below the ${RESERVE_GIB} GiB reserve target"
  elif awk -v x="$(( ${MAX_T:-0} - ${BASE_TOP:-0} ))" -v l=2048 'BEGIN{exit !(x>l)}'; then STOPREASON="engine top-pid grew $(( ${MAX_T:-0} - ${BASE_TOP:-0} )) MiB > 2 GiB = allocator growth is back (C3 --enforce-eager territory)"
  fi
}

# Boot-side constraint: the pool is reserved at boot, out of whatever was free THEN.
INIT_FREE=$(sudo docker logs "$CTR" 2>&1 | grep -oE 'Initial free memory [0-9.]+' | grep -oE '[0-9.]+' | tail -1)
MODEL_LOAD=$(sudo docker logs "$CTR" 2>&1 | grep -oE 'Model loading took [0-9.]+ GiB' | grep -oE '[0-9.]+' | head -1)
HELD_IDLE=$(awk -v t="$(awk '/^MemTotal:/{print $2/1048576}' /proc/meminfo)" -v a="${IDLE_U:-0}" 'BEGIN{printf "%.1f", t-a}')
KV_TABLE=$(awk -v min="${MIN_U:-0}" -v idle="$IDLE_U" -v res="$RESERVE_GIB" -v now="${KV_GIB:-8.2}" \
              -v kib="$KV_KIB_PER_TOK" -v ctx="$CTX" -v initfree="${INIT_FREE:-0}" -v held="${HELD_IDLE:-0}" \
              -v mload="${MODEL_LOAD:-0}" 'BEGIN{
  if (min <= 0) { print "  (no sampler rows in the run window — cannot compute)"; exit }
  aff = int((min - res) * 2) / 2; if (aff < 0) aff = 0
  printf "  worst observed usable : %.2f GiB  (idle after the run %.2f GiB)\n", min, idle
  printf "  reserve target        : %.2f GiB  (watchdog CRIT 8.0; both real kills landed at 1.6)\n", res
  printf "  => EXTRA KV AFFORDABLE: %.1f GiB -> pool %.1f -> %.1f GiB   (bf16, no fp8)\n", aff, now, now+aff
  if (aff > 0) { tok = aff*1073741824/(kib*1024)
    printf "     +%.0f tokens = +%.2f full %d-token windows\n", tok, tok/ctx, ctx
    printf "     pool %.1f GiB = %.0f tokens = %.2f windows  (today 283,398 tok = 1.08)\n", \
           now+aff, (now+aff)*1073741824/(kib*1024), ((now+aff)*1073741824/(kib*1024))/ctx }
  print "  projection, usable at the worst moment IF the peak stays as measured:"
  for (d = 0; d <= 16; d += 4) printf "     KV +%-2d GiB (%-4.1f total) -> worst usable %.1f GiB %s\n", \
      d, now+d, min-d, (min-d < res ? "<-- below target" : "")
  if (initfree+0 > 0) {
    boot = initfree - held - res
    if (boot < 0) boot = 0
    printf "  BOOT check (the pool is reserved at boot, out of what was free then):\n"
    printf "     free at boot %.1f GiB  (weights alone took %.1f GiB) | engine holds ~%.1f GiB now\n", initfree, mload, held
    printf "     => boot-side allowance ~%.1f GiB\n", boot
    if (boot < aff) printf "     BINDING CONSTRAINT IS BOOT, NOT RUNTIME: cap extra KV at ~%.1f GiB\n", boot
    else printf "     boot side is not the binding constraint (runtime is)\n"
  } else print "  BOOT check: could not read Initial-free-memory from the engine log — verify manually."
}')

{
  echo "=============================================================="
  [ "$FAILED" = "0" ] && echo "RESULT: PASSED ✅ — spark stayed up and the peak stayed bounded." \
                      || echo "RESULT: FAILED ❌ — $STOPREASON"
  echo "=============================================================="
  echo "runs completed  ${#RUNS_DONE[@]}/${#RUNS[@]} | kills continued through $KILLS (cap $MAX_KILLS) | box reboots $REBOOTS"
  echo "usable          ${BASE_USABLE} GiB -> worst ${MIN_U} GiB   (the two observed kills landed at 1.6)"
  [ "$SAMPLES_OK" = "1" ] || echo "                ^ live reading: the run was too short for sampler rows — not a worst-case figure"
  echo "engine top-pid  ${BASE_TOP} MiB -> max ${MAX_T} MiB (delta $(( ${MAX_T:-0} - ${BASE_TOP:-0} )) MiB)"
  echo "kernel oom-kill ${BASE_OOM} -> ${NOW_OOM} | restarts ${BASE_RESTARTS} -> ${NOW_RST} | health $NOW_H"
  echo "NVRM NV_ERR_NO_MEMORY ${BASE_NVRM} -> ${NOW_NVRM}  (a burst during weight-load at boot is normal;"
  echo "                                                    steady-state growth during the run is not)"
  echo "--------------------------------------------------------------"
  echo "HOW MUCH MORE KV CAN I AFFORD (bf16, no fp8)?"
  echo "$KV_TABLE"
  echo "--------------------------------------------------------------"
  echo "Not covered here — check before touching spark_vllm_kv_cache_memory:"
  echo "  * the pool is allocated AT BOOT: the boot log's 'Initial free memory … reserved N GiB' must"
  echo "    still leave Linux its reserve. This box already logs NV_ERR_NO_MEMORY during weight load,"
  echo "    so raise in +2 GiB steps and re-check the boot log each time."
  echo "  * KV is CAPACITY, not stability. After a raise, re-measure prefix-cache hit rate and"
  echo "    preemptions — fewer evictions is the whole point, not a bigger number."
  echo "  * fp8 KV would roughly DOUBLE the tokens for the SAME GiB — deliberately excluded here."
  echo "  * the parallel-lane rule stands: one shared pool, max_num_seqs=4."
  echo "=============================================================="
  echo "evidence: $DIR/evidence + $DIR/logs | on-box watchdog bundles: /mnt/spark_nvme/oom-watchdog/snapshots/"
} | tee "$DONE" | tee -a "$MAIN"

exit "$FAILED"
