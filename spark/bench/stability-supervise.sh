#!/usr/bin/env bash
# ============================================================================
# stability-supervise.sh — LAPTOP side (WSL Debian) supervisor for the spark
# stability chain. Run this from the repo root before you go to bed:
#
#   bash spark/bench/stability-supervise.sh
#
# It does three things a chain running on spark cannot do for itself:
#   1. sync the two scripts to spark and launch the chain detached;
#   2. KEEP THE CHAIN ALIVE: spark is a unified-memory box whose global-OOM kill
#      list has historically included sshd, so the chain can die mid-run. When that
#      happens this supervisor waits for spark to answer again and RE-LAUNCHES the
#      chain, which resumes at its first unfinished run (state on XFS);
#   3. pull the evidence off spark at the end, so a morning power-cycle cannot
#      delete the proof.
#
# Progress: one line per poll. Verdict: printed at the end + spark:/mnt/spark_nvme/
# stability/OVERNIGHT.done. Re-attach at any time (safe, read-only):
#   bash spark/bench/stability-supervise.sh --status
#
# KEEP THE LAPTOP AWAKE (WSL on Windows):
#   powershell.exe -Command 'Start-Process powercfg -ArgumentList "/change","standby-timeout-ac","0" -WindowStyle Hidden'
# and leave the lid open — a sleeping supervisor is just a chain nobody relaunches.
#
# Env: STABILITY_HOST (spark) · STABILITY_MAX_RELAUNCH (6) · STABILITY_POLL (60 s)
#      STABILITY_RESERVE_GIB (12) · STABILITY_MAX_KILLS (2) · STABILITY_COOLDOWN (300 s)
#      STABILITY_RECOVER_WAIT (600 s) · STABILITY_HEALTH_WAIT (600 s)
#      STABILITY_DRYRUN=1 (no load) · STABILITY_FAKE_KILL=1 (dry-run + exercise the
#      crash/relaunch path without ever putting the box under pressure)
# ============================================================================
set -uo pipefail

HOST="${STABILITY_HOST:-spark}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE/stability-overnight.sh"
BENCH="$HERE/stress-oom.sh"
REMOTE_DIR="/mnt/spark_nvme/stability"
OUT="${STABILITY_OUT:-$HERE/overnight}"
MAX_RELAUNCH="${STABILITY_MAX_RELAUNCH:-6}"
POLL="${STABILITY_POLL:-60}"
RESERVE_GIB="${STABILITY_RESERVE_GIB:-12}"
MAX_KILLS="${STABILITY_MAX_KILLS:-2}"
DRY="${STABILITY_DRYRUN:-0}"
SSHCTL=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=15 -o ServerAliveCountMax=4
        -o ControlMaster=auto -o "ControlPath=/tmp/.stability-sup-%r@%h:%p" -o ControlPersist=180)
MAIN="$OUT/supervisor.log"
mkdir -p "$OUT"

log(){ printf '%s %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$MAIN"; }
R(){ timeout 45 ssh "${SSHCTL[@]}" "$HOST" "$1" 2>/dev/null | tr -d '\r'; }
R_ok(){ timeout 15 ssh "${SSHCTL[@]}" "$HOST" true >/dev/null 2>&1; }
chain_alive(){ R " pgrep -f 'stability-overnigh[t].sh' | head -1" | grep -q '[0-9]'; }
verdict(){ R "cat $REMOTE_DIR/OVERNIGHT.done 2>/dev/null"; }

sync_up(){
  R_ok || return 1
  R "sudo mkdir -p $REMOTE_DIR/logs $REMOTE_DIR/evidence && sudo chown -R \$(id -un) $REMOTE_DIR" >/dev/null
  ssh "${SSHCTL[@]}" "$HOST" "cat > $REMOTE_DIR/stability-overnight.sh" < "$RUNNER" || return 1
  ssh "${SSHCTL[@]}" "$HOST" "cat > $REMOTE_DIR/stress-oom.sh" < "$BENCH" || return 1
  R "chmod +x $REMOTE_DIR/*.sh" >/dev/null
  log "synced to $HOST:$REMOTE_DIR (runner + bench harness)"
  return 0
}

launch(){
  local args=""
  [ "$DRY" = "1" ] && args="--dry-run"
  [ "${STABILITY_FAKE_KILL:-0}" = "1" ] && args="--fake-kill"
  R "setsid nohup env STABILITY_RESERVE_GIB=$RESERVE_GIB STABILITY_MAX_KILLS=$MAX_KILLS \
      STABILITY_COOLDOWN=${STABILITY_COOLDOWN:-300} STABILITY_RECOVER_WAIT=${STABILITY_RECOVER_WAIT:-600} \
      STABILITY_HEALTH_WAIT=${STABILITY_HEALTH_WAIT:-600} \
      bash $REMOTE_DIR/stability-overnight.sh $args </dev/null >$REMOTE_DIR/logs/launch.out 2>&1 & echo LAUNCHED" >/dev/null
  sleep 3
  chain_alive && { log "chain running on spark"; return 0; }
  log "WARN: chain not visible right after launch"; return 1
}

status(){
  echo "=== spark stability chain — $(date -u '+%Y-%m-%d %H:%M UTC') ==="
  R_ok || { echo "spark UNREACHABLE"; exit 0; }
  chain_alive && echo "chain: RUNNING on spark" || echo "chain: not running"
  echo "live: usable=$(R "awk '/^MemAvailable:/{a=\$2}/^CmaFree:/{c=\$2}END{printf \"%.2f\",(a-c)/1048576}' /proc/meminfo") GiB  top=$(R "nvidia-smi --query-compute-apps=used_memory --format=csv,noheader,nounits | sort -rn | head -1") MiB  health=$(R "curl -s -o /dev/null -w '%{http_code}' --max-time 4 localhost:8000/health")  oom-kill=$(R "sudo journalctl -k -b 0 --no-pager | grep -c 'invoked oom-killer'")"
  echo "state: $(R "grep -E '^(RUNS_DONE|KILLS|REBOOTS)=' $REMOTE_DIR/state.env 2>/dev/null | tr '\n' ' ')")"
  echo "--- chain log tail ---"; R "tail -20 $REMOTE_DIR/chain.log 2>/dev/null"
  echo "--- verdict ---"
  local v; v=$(R "cat $REMOTE_DIR/OVERNIGHT.done 2>/dev/null")
  [ -n "$v" ] && echo "$v" || echo "(not finished)"
  exit 0
}

pull_evidence(){
  local D="$OUT/evidence-$(date +%Y%m%d-%H%M)"
  mkdir -p "$D"
  R "tar -C $REMOTE_DIR -cf - evidence logs chain.log state.env OVERNIGHT.done 2>/dev/null" > "$D/chain-bundle.tar" 2>/dev/null
  ( cd "$D" && tar -xf chain-bundle.tar 2>/dev/null )
  log "evidence pulled to $D ($(du -sh "$D" 2>/dev/null | cut -f1))"
}

# ---- modes -----------------------------------------------------------------
[ "${1:-}" = "--status" ] && status
R_ok || { echo "spark unreachable — fix connectivity first"; exit 1; }
sync_up || { echo "sync failed"; exit 1; }

if [ -n "$(verdict)" ]; then
  echo "A previous chain already finished. Its verdict:"; verdict
  echo; echo "to re-run:  ssh spark 'rm -f $REMOTE_DIR/OVERNIGHT.done $REMOTE_DIR/state.env'"
  pull_evidence; exit 0
fi

if chain_alive; then
  log "chain already running on spark — supervising it (no new launch)"
else
  launch || { echo "could not launch the chain"; exit 1; }
fi

RELAUNCH=0
log "supervising (poll ${POLL}s, relaunch cap $MAX_RELAUNCH). Ctrl-C stops supervising, NOT the chain."
while true; do
  sleep "$POLL"
  if ! R_ok; then
    log "spark UNREACHABLE (wedge? reboot?) — waiting, the chain cannot survive this"
    while ! R_ok; do sleep 30; done
    log "spark BACK at $(date +%H:%M:%S) — relaunching the chain to resume"
    RELAUNCH=$((RELAUNCH + 1))
    if [ "$RELAUNCH" -gt "$MAX_RELAUNCH" ]; then log "relaunch cap reached — leaving it to you"; exit 1; fi
    launch
    continue
  fi
  V=$(verdict)
  if [ -n "$V" ]; then
    log "chain finished"
    pull_evidence
    echo "$V" | tee -a "$MAIN"
    echo "$V" | grep -q 'RESULT: PASSED' && exit 0 || exit 1
  fi
  if chain_alive; then
    U=$(R "awk '/^MemAvailable:/{a=\$2}/^CmaFree:/{c=\$2}END{printf \"%.2f\",(a-c)/1048576}' /proc/meminfo")
    T=$(R "nvidia-smi --query-compute-apps=used_memory --format=csv,noheader,nounits | sort -rn | head -1")
    ST=$(R "grep -E '^RUNS_DONE=' $REMOTE_DIR/state.env 2>/dev/null | cut -d= -f2")
    LAST=$(R "grep -E '^(RUN|  )' $REMOTE_DIR/chain.log 2>/dev/null | tail -1")
    log "RUNNING | usable=${U}G top=${T}M done=[${ST}] | ${LAST:0:80}"
  else
    RELAUNCH=$((RELAUNCH + 1))
    log "chain is DEAD with no verdict (crash #${RELAUNCH}) — relaunching to resume"
    if [ "$RELAUNCH" -gt "$MAX_RELAUNCH" ]; then
      log "relaunch cap reached — spark crashed too many times; leaving the evidence for you"
      pull_evidence; exit 1
    fi
    sleep 30
    launch
  fi
done
