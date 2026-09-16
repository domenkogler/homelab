#!/usr/bin/env bash
# ============================================================================
# spark-oom-watchdog.sh — GB10 unified-memory forensics catcher (HD-380).
#
# WHY THIS EXISTS: spark's vLLM engine dies from the kernel GLOBAL OOM killer,
# not the container cage. Every prior incident reported `OOMKilled=false` /
# `ExitCode=0` (Docker only flags cgroup memory.max kills), so `docker inspect`
# is a FALSE NEGATIVE on this box — dmesg/journal is authoritative. Worse, the
# state that explains the kill (MemAvailable trend, per-pid GPU MiB, PSI, swap)
# is DESTROYED by the kill. Reading the log afterwards cannot answer "what was
# the trend in the 20 minutes before the kill, and what was the engine holding?"
#
# SO THIS DOES TWO THINGS:
#   1. sample-loop — cheap continuous sampler into a ring CSV (the pre-event
#      trail). This is the payload; a snapshot alone is never enough.
#   2. snapshot    — full forensic bundle, fired on: kernel OOM event (KILL),
#      engine restart (RESTART), MemAvailable/PSI threshold breach (CRIT/WARN).
#      Each bundle includes the TAIL OF THE SAMPLER RING so the pre-event curve
#      is preserved inside the bundle.
#
# On GB10 `nvidia-smi --query-gpu=memory.*` reports N/A, so the per-pid
# `--query-compute-apps` figure is the only device-side gauge available.
#
# Modes:
#   sample-loop              run forever (systemd default)
#   snapshot <tag> [reason]  take one bundle and exit (tag: KILL|CRIT|WARN|MANUAL)
#   status                   print current readings + last snapshot
#
# Cheap on purpose: bash + coreutils + awk + docker + nvidia-smi + journalctl.
# Runs as root with OOMScoreAdj=-1000 (see the unit) — it must NOT become the
# next OOM victim the way alloy did in incidents #2/#3.
# ============================================================================
set -uo pipefail

BASE_DIR="${SPARK_OOM_DIR:-/mnt/spark_nvme/oom-watchdog}"
STATE_DIR="$BASE_DIR/state"
SNAP_DIR="$BASE_DIR/snapshots"
SAMPLES="$STATE_DIR/samples.csv"
CTR="${VLLM_CONTAINER:-vllm-qwen-spark}"

INTERVAL="${SPARK_OOM_INTERVAL:-15}"          # seconds between samples
WARN_GIB="${SPARK_OOM_WARN_GIB:-24}"          # HD-375 threshold (host reserve)
CRIT_GIB="${SPARK_OOM_CRIT_GIB:-16}"
PSI_CRIT="${SPARK_OOM_PSI_CRIT:-25}"          # PSI memory full avg10 (%)
RING_ROWS="${SPARK_OOM_RING_ROWS:-20000}"     # ~3.5 days at 15 s
KEEP_SNAPS="${SPARK_OOM_KEEP_SNAPS:-20}"
WARN_COOLDOWN="${SPARK_OOM_WARN_COOLDOWN:-900}"    # s
CRIT_COOLDOWN="${SPARK_OOM_CRIT_COOLDOWN:-300}"    # s
VLLM_PORT="${SPARK_OOM_VLLM_PORT:-8000}"

mkdir -p "$STATE_DIR" "$SNAP_DIR"

# ---- readings ---------------------------------------------------------------
mem_field() { awk -v f="$1" '$1==f":"{printf "%.2f", $2/1048576; exit}' /proc/meminfo; }
psi_val() { # $1 = some|full, $2 = avg10
  awk -v k="$1" '$1==k{for(i=2;i<=NF;i++) if($i ~ /^avg10=/){split($i,a,"=");printf "%.1f", a[2]; exit}}' /proc/pressure/memory 2>/dev/null
}
gpu_mib() { timeout 8 nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null \
            | sort -t, -k2 -rn | head -1 | tr -d ' ' ; }
eng_field() { timeout 10 docker inspect "$CTR" --format "{{.RestartCount}} {{.State.StartedAt}} {{.State.OOMKilled}}" 2>/dev/null; }
mem_avail_gib() { mem_field MemAvailable; }

sample_line() {
  local now avail free cached anon swapu gpu restarts
  now=$(date +%s)
  avail=$(mem_avail_gib); free=$(mem_field MemFree); cached=$(mem_field Cached); anon=$(mem_field AnonPages)
  swapu=$(awk '/^SwapTotal:/{t=$2}/^SwapFree:/{f=$2}END{printf "%.2f",(t-f)/1048576}' /proc/meminfo)
  gpu=$(gpu_mib); gpu=${gpu:-NA}
  restarts=$(eng_field | awk '{print $1}')
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$now" "${avail:-NA}" "${free:-NA}" "${cached:-NA}" "${anon:-NA}" "${swapu:-NA}" \
    "$(psi_val some)" "$(psi_val full)" "$gpu" "${restarts:-NA}" "$(date -u +%H:%M:%S)"
}

ring_append() { # append + cap size
  sample_line >> "$SAMPLES"
  local n; n=$(wc -l < "$SAMPLES" 2>/dev/null || echo 0)
  if [ "${n:-0}" -gt "$RING_ROWS" ]; then
    { echo "epoch,mem_avail_gib,mem_free_gib,cached_gib,anon_gib,swap_used_gib,psi_some_avg10,psi_full_avg10,gpu_top_mib,restarts,utc"
      tail -n "$RING_ROWS" "$SAMPLES"; } > "$SAMPLES.tmp" && mv "$SAMPLES.tmp" "$SAMPLES"
  fi
}

ensure_ring_header() { [ -s "$SAMPLES" ] || echo "epoch,mem_avail_gib,mem_free_gib,cached_gib,anon_gib,swap_used_gib,psi_some_avg10,psi_full_avg10,gpu_top_mib,restarts,utc" > "$SAMPLES"; }

# ---- snapshot ---------------------------------------------------------------
snapshot() {
  local tag="${1:-MANUAL}" reason="${2:-manual request}"
  local d="$SNAP_DIR/$(date -u +%Y%m%d-%H%M%S)-${tag}"
  mkdir -p "$d" || return 1
  echo ">>> snapshot $d (tag=$tag reason=$reason)"

  { echo "tag=$tag"; echo "reason=$reason"; echo "utc=$(date -u +%FT%TZ)"; echo "boot=$(uptime -s 2>/dev/null)"
    echo "engine=$(eng_field)"; echo "gpu_top=$(gpu_mib)"; echo; uptime; } > "$d/00-meta.txt" 2>&1

  cp /proc/meminfo            "$d/01-meminfo.txt" 2>/dev/null
  { date -u; free -h; echo; grep -E "MemAvailable|MemFree|^Cached|^Mapped|AnonPages|^Shmem|SwapTotal|SwapFree|SUnreclaim|KernelStack|PageTables|SecPageTables" /proc/meminfo; } > "$d/02-free.txt" 2>&1
  cp /proc/pressure/memory    "$d/03-psiread.txt" 2>/dev/null
  cp /proc/pressure/io        "$d/03b-psidio.txt" 2>/dev/null

  # AUTHORITATIVE OOM evidence (never trust docker inspect here)
  { journalctl -k -b --no-pager -q 2>/dev/null | grep -E "invoked oom-killer|oom-kill:constraint|Out of memory: Killed process|Memory cgroup out of memory|NVRM.*NO_MEMORY" | tail -60; } > "$d/04-kernel-oom.txt" 2>&1
  journalctl -k -b --no-pager -q --since "-45 min" > "$d/04b-kernel-45min.txt" 2>&1

  ps -eo pid,user,rss,vsz,comm --sort=-rss | head -25 > "$d/05-top-rss.txt" 2>&1
  { for p in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
      s=$(awk '/^VmSwap/{print $2}' "/proc/$p/status" 2>/dev/null)
      [ -n "${s:-}" ] && [ "$s" -gt 50000 ] && printf '%s %s\n' "$s" "$(cat /proc/$p/comm 2>/dev/null)"
    done | sort -rn | head -15; } > "$d/06-top-swap.txt" 2>&1

  # device-side gauge (GB10: only per-pid works; memory.total/used are N/A)
  { date -u; timeout 10 nvidia-smi --query-compute-apps=pid,used_memory --format=csv 2>&1
    echo "--- name/util ---"; timeout 10 nvidia-smi --query-gpu=name,utilization.gpu,utilization.memory,power.draw,temperature.gpu --format=csv 2>&1; } > "$d/07-nvidia.txt" 2>&1

  { docker ps -a --format '{{.Names}}\t{{.Status}}'; echo "--- inspect ---"
    for c in $(docker ps --format '{{.Names}}' 2>/dev/null); do
      echo "$c $(docker inspect "$c" --format 'restarts={{.RestartCount}} oom={{.State.OOMKilled}} exit={{.State.ExitCode}} started={{.State.StartedAt}}' 2>/dev/null)"
    done; } > "$d/08-docker.txt" 2>&1

  # cgroup split — shows the cage never fired (memory.events oom_kill=0) vs global OOM
  { for c in $(docker ps -q 2>/dev/null); do
      id=$(docker inspect --format '{{.Id}}' "$c" 2>/dev/null); nm=$(docker inspect --format '{{.Name}}' "$c" 2>/dev/null | tr -d /)
      base="/sys/fs/cgroup/system.slice/docker-$id.scope"
      [ -d "$base" ] || continue
      echo "== $nm current=$(cat $base/memory.current 2>/dev/null) max=$(cat $base/memory.max 2>/dev/null) peak=$(cat $base/memory.peak 2>/dev/null)"
      echo "   events: $(tr '\n' ' ' < $base/memory.events 2>/dev/null)"
      grep -E "^(anon|file|inactive_file|workingset_refault_file|workingset_refault_anon|pgscan|pgsteal) " $base/memory.stat 2>/dev/null | tr '\n' ' '; echo
    done
    echo "== alloy cgroup"; base=/sys/fs/cgroup/system.slice/alloy.service
    [ -d "$base" ] && { cat $base/memory.current 2>/dev/null; grep -E "^(anon|file) " $base/memory.stat 2>/dev/null; }
    echo "== host slab/stacks"; grep -E "SUnreclaim|KernelStack|PageTables|SecPageTables|Slab" /proc/meminfo; } > "$d/09-cgroups.txt" 2>&1

  { echo "--- boot banners ---"; docker logs --timestamps "$CTR" 2>&1 | grep 'version 0.1.dev' | tail -10
    echo "--- budget lines ---"; docker logs "$CTR" 2>&1 | grep -E "Model loading took|Initial free memory|GPU KV cache size|Maximum concurrency|kv_cache_memory_bytes|Preempt|preempt" | tail -25
    echo "--- tail 600 ---"; docker logs --tail 600 "$CTR" 2>&1; } > "$d/10-vllm.txt" 2>&1

  curl -s -o /dev/null -w "health_http=%{http_code}\n" --max-time 5 "http://localhost:$VLLM_PORT/health" > "$d/11-health.txt" 2>&1
  # THE POINT OF THE BUNDLE: the pre-event curve travels with the snapshot.
  { echo "sampler tail (pre-event trail), interval=${INTERVAL}s"; tail -n 400 "$SAMPLES" 2>/dev/null; } > "$d/12-sampler-tail.csv" 2>&1
  dmesg -T 2>/dev/null | tail -300 > "$d/13-dmesg-tail.txt" 2>&1 || sudo -n dmesg -T 2>/dev/null | tail -300 > "$d/13-dmesg-tail.txt" 2>&1

  # rotate snapshots
  ls -1dt "$SNAP_DIR"/*/ 2>/dev/null | tail -n +$((KEEP_SNAPS + 1)) | xargs -r rm -rf
  date +%s > "$STATE_DIR/last_${tag}"
  return 0
}

# ---- triggers ---------------------------------------------------------------
cooldown_ok() { # $1 name, $2 seconds
  local f="$STATE_DIR/last_$1" now last
  [ -f "$f" ] || return 0
  now=$(date +%s); last=$(cat "$f" 2>/dev/null || echo 0)
  [ $(( now - ${last:-0} )) -ge "$2" ]
}

check_kill_events() {
  # Consume the kernel journal from a persisted cursor. First run replays boot →
  # we immediately capture a historical bundle of every OOM seen this boot.
  local n
  n=$(journalctl -k -q -b --no-pager -o short-iso --cursor-file="$STATE_DIR/journal.cursor" 2>/dev/null \
     | grep -c -E "oom-kill:constraint|Memory cgroup out of memory" || true)
  [ "${n:-0}" -gt 0 ] && snapshot KILL "kernel oom-kill lines seen: $n"
}

check_engine_restart() {
  local cur prev
  cur=$(eng_field); [ -z "$cur" ] && return 0
  prev=$(cat "$STATE_DIR/last_engine" 2>/dev/null || echo "")
  echo "$cur" > "$STATE_DIR/last_engine"
  if [ -n "$prev" ] && [ "$prev" != "$cur" ]; then
    snapshot RESTART "engine field changed: [$prev] -> [$cur]"
  fi
}

# ---- modes ------------------------------------------------------------------
case "${1:-sample-loop}" in
  snapshot) shift; snapshot "${1:-MANUAL}" "${2:-manual request}" ;;
  status)
    echo "engine: $(eng_field)"
    echo "mem: avail=$(mem_avail_gib) free=$(mem_field MemFree) cached=$(mem_field Cached) anon=$(mem_field AnonPages) GiB"
    echo "psi:  some avg10=$(psi_val some) full avg10=$(psi_val full)"
    echo "gpu top pid: $(gpu_mib)"
    echo "samples: $(wc -l < "$SAMPLES" 2>/dev/null || echo 0) rows in $SAMPLES"
    echo "last snapshots:"; ls -1dt "$SNAP_DIR"/*/ 2>/dev/null | head -5
    ;;
  sample-loop)
    ensure_ring_header
    echo "spark-oom-watchdog: dir=$BASE_DIR interval=${INTERVAL}s warn=${WARN_GIB}GiB crit=${CRIT_GIB}GiB psi=$PSI_CRIT"
    # capture whatever the kernel already reported this boot (cheap + immediately useful)
    check_kill_events
    while :; do
      ring_append
      check_kill_events
      check_engine_restart
      avail=$(mem_avail_gib); pfull=$(psi_val full)
      if awk -v a="${avail:-99}" -v c="$CRIT_GIB" 'BEGIN{exit !(a<c)}' \
         || awk -v p="${pfull:-0}" -v c="$PSI_CRIT" 'BEGIN{exit !(p>c)}'; then
        cooldown_ok CRIT "$CRIT_COOLDOWN" && snapshot CRIT "avail=${avail}GiB psi_full=${pfull} (crit ${CRIT_GIB}GiB / ${PSI_CRIT}%)"
      elif awk -v a="${avail:-99}" -v w="$WARN_GIB" 'BEGIN{exit !(a<w)}'; then
        cooldown_ok WARN "$WARN_COOLDOWN" && snapshot WARN "avail=${avail}GiB psi_full=${pfull} (warn ${WARN_GIB}GiB)"
      fi
      sleep "$INTERVAL"
    done
    ;;
  *) echo "usage: $0 {sample-loop|snapshot <tag> [reason]|status}" >&2; exit 2 ;;
esac
