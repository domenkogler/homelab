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
# GAUGE CORRECTION (HD-381, incidents #7/#8) — read before touching thresholds:
#   usable_gib = MemAvailable - CmaFree
# The 2026-09-17 plan proposed `MemFree - CmaFree`. That gauge is INVERTED on this box:
#     state            MemAvail  CmaFree  avail-Cma   MemFree-Cma (the bad gauge)
#     healthy idle       26.25     0.13     26.13          0.74
#     #7 KILL            10.45     8.81      1.64          2.17
#     #8 KILL            10.39     8.77      1.62          2.14
# It reads LOWER at healthy idle than at a kill, so WARN 4 / CRIT 2 on it fires
# permanently and an enforcing CRIT action would restart-storm the engine — the fix
# would have caused the outage it was meant to prevent. WHY: MemFree is *meant* to sit
# near 1 GiB at steady state (the rest is page cache doing its job); under pressure
# reclaim EVICTS cache, so MemFree RISES to ~11 GiB, most of it CMA-attributed. The
# quantity is therefore "reclaimed but not yet consumed" — high in a storm, low at rest.
# The plan's ~0.05 GiB figure came from the kernel's PER-ZONE dump (`Node 0 Normal
# free:9.63 GiB free_cma:9.58 GiB`), which is a zone/migratetype-local number and is
# not reconstructible from global meminfo. `MemAvailable - CmaFree` is the global gauge
# that is monotone with danger and is what both this watchdog and the HD-375 alert rules
# (roles/monitoring) use.
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
# Thresholds are on usable_gib = MemAvailable - CmaFree (see the gauge correction above).
# Measured: healthy idle 26-30 GiB; the instant of death 1.6 GiB; the lowest value a
# 60 s SCRAPE ever recorded in those windows was 5.01. CRIT is therefore 8, NOT the 1.6
# death figure — a restart takes ~4 min, so it has to start while there is still margin,
# and a threshold below what the monitoring path can observe is just a rule that cannot
# fire. Kept identical to the HD-375 alert pair (roles/monitoring/vars/main.yml).
WARN_GIB="${SPARK_OOM_WARN_GIB:-12}"          # was 24 on raw MemAvailable
CRIT_GIB="${SPARK_OOM_CRIT_GIB:-8}"           # was 16 on raw MemAvailable; death at 1.6
PSI_CRIT="${SPARK_OOM_PSI_CRIT:-25}"          # PSI memory full avg10 (%)
RING_ROWS="${SPARK_OOM_RING_ROWS:-20000}"     # ~3.5 days at 15 s
KEEP_SNAPS="${SPARK_OOM_KEEP_SNAPS:-20}"
WARN_COOLDOWN="${SPARK_OOM_WARN_COOLDOWN:-900}"    # s
CRIT_COOLDOWN="${SPARK_OOM_CRIT_COOLDOWN:-300}"    # s
VLLM_PORT="${SPARK_OOM_VLLM_PORT:-8000}"

# ---- enforcing governor (HD-381 term B) --------------------------------------
# The watchdog used to only NARRATE. At CRIT the choice is a PLANNED engine restart
# (~4 min, chosen when nothing is in flight) or a kernel global OOM that takes Traefik,
# the DGX dashboard, alloy and dcgm with it and wedges the box (invariants #1/#3).
ENFORCE="${SPARK_OOM_ENFORCE:-1}"                   # 0 = forensics-only (old behaviour)
ENFORCE_COOLDOWN="${SPARK_OOM_ENFORCE_COOLDOWN:-1800}"   # s between enforced restarts
ENFORCE_MAX="${SPARK_OOM_ENFORCE_MAX:-2}"                # enforced restarts per window
ENFORCE_WINDOW="${SPARK_OOM_ENFORCE_WINDOW:-7200}"       # s
ENFORCE_WAIT_MAX="${SPARK_OOM_ENFORCE_WAIT_MAX:-600}"    # s to wait for an in-flight drain
NO_ENFORCE_FILE="$BASE_DIR/no-enforce"                   # touch this to arm-off, by hand
# Idle-recycle: the non-KV engine footprint grows per request shape and NEVER returns
# (flat at idle, +21 GiB per ~30 min of light agent traffic). Predictable recycling is
# harmless at idle and removes the cumulative term before it can become a kill.
RECYCLE="${SPARK_OOM_RECYCLE:-1}"
RECYCLE_GROW_GIB="${SPARK_OOM_RECYCLE_GROW_GIB:-8}"      # trigger above the boot baseline
RECYCLE_IDLE_S="${SPARK_OOM_RECYCLE_IDLE_S:-1800}"       # must be idle this long first

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
cma_free_gib()  { mem_field CmaFree; }

# THE budget metric (see the gauge correction in the header).
usable_gib() {
  awk '/^MemAvailable:/{a=$2} /^CmaFree:/{c=$2} END{printf "%.2f", (a-c)/1048576}' /proc/meminfo 2>/dev/null
}

# In-flight work. The engine runs with --api-key, so /metrics needs the bearer token;
# read it from the container's OWN argv (never logged) — same trick as spark/bench.
# CRITICAL: it must distinguish "0 requests" from "I could not read anything". HD-380 was
# bitten by exactly this shape: `vllm bench serve` 401s EVERY request against the keyed
# engine and still exits 0 — an unreadable read that looks like "idle" would let the
# governor restart a busy engine and hand its sessions a 502. Echoes ERR when unknown.
in_flight() {
  local key out
  key=$(timeout 10 docker inspect "$CTR" --format '{{join .Args " "}}' 2>/dev/null \
        | awk '{for(i=1;i<NF;i++) if($i=="--api-key") print $(i+1)}')
  [ -n "$key" ] || { echo ERR; return 1; }
  out=$(timeout 10 curl -s --max-time 8 -H "Authorization: Bearer $key" \
        "http://localhost:$VLLM_PORT/metrics" 2>/dev/null \
        | awk '/^vllm:num_requests_(running|waiting)\{/ {s+=$2; n++}
               END{ if (n>0) printf "%d", s+0; else print "ERR" }')
  echo "${out:-ERR}"
}

# Engine top-pid (EngineCore) device MiB — the series that ratchets. gpu_mib emits "pid,mib".
engine_top_mib() { gpu_mib | awk -F, 'END{print $2+0}'; }

sample_line() {
  local now avail free cached anon swapu gpu restarts cma use
  now=$(date +%s)
  avail=$(mem_avail_gib); free=$(mem_field MemFree); cached=$(mem_field Cached); anon=$(mem_field AnonPages)
  cma=$(cma_free_gib); use=$(usable_gib)
  swapu=$(awk '/^SwapTotal:/{t=$2}/^SwapFree:/{f=$2}END{printf "%.2f",(t-f)/1048576}' /proc/meminfo)
  gpu=$(gpu_mib); gpu=${gpu:-NA,NA}
  restarts=$(eng_field | awk '{print $1}')
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$now" "${avail:-NA}" "${free:-NA}" "${cached:-NA}" "${anon:-NA}" "${swapu:-NA}" \
    "$(psi_val some)" "$(psi_val full)" "$gpu" "${cma:-NA}" "${use:-NA}" "${restarts:-NA}" "$(date -u +%H:%M:%S)"
}

# NOTE: gpu_mib emits "pid,mib", so a data row is 14 fields wide. The pre-HD-381 header
# declared 11 names while gpu_mib already emitted two values, so every column after
# psi_full_avg10 was shifted one position in the data rows (what the header called
# gpu_top_mib column 9 was the PID; the MiB figure was column 10). The header below is
# authoritative for rows written from HD-381 on, and a ring written by the old binary is
# rotated out rather than appended to — see ensure_ring_header().
RING_HEADER="epoch,mem_avail_gib,mem_free_gib,cached_gib,anon_gib,swap_used_gib,psi_some_avg10,psi_full_avg10,gpu_top_pid,gpu_top_mib,cma_free_gib,usable_gib,restarts,utc"

ring_append() { # append + cap size
  sample_line >> "$SAMPLES"
  local n; n=$(wc -l < "$SAMPLES" 2>/dev/null || echo 0)
  if [ "${n:-0}" -gt "$RING_ROWS" ]; then
    { echo "$RING_HEADER"; tail -n "$RING_ROWS" "$SAMPLES"; } > "$SAMPLES.tmp" && mv "$SAMPLES.tmp" "$SAMPLES"
  fi
}

ensure_ring_header() {
  # Width change is a schema change: archive the v1 ring instead of writing a new
  # header over rows recorded with the old column meaning.
  if [ -s "$SAMPLES" ] && ! head -1 "$SAMPLES" | grep -q "cma_free_gib"; then
    mv "$SAMPLES" "$SAMPLES.v1-$(date -u +%Y%m%d-%H%M%S)" 2>/dev/null || rm -f "$SAMPLES"
  fi
  [ -s "$SAMPLES" ] || echo "$RING_HEADER" > "$SAMPLES"
}

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
    # New engine instance: the boot baseline for idle-recycling is only valid per engine
    # start, so drop it and let the next samples re-establish it.
    rm -f "$STATE_DIR/engine_baseline_mib" "$STATE_DIR/last_busy_epoch"
    snapshot RESTART "engine field changed: [$prev] -> [$cur]"
  fi
}

# ---- enforcing governor (HD-381 term B) --------------------------------------
# Recorded decisions go to $STATE_DIR/enforce.log so "why did the watchdog restart my
# engine" is answerable without reconstructing it from the ring.
act_log() { echo "$(date -u +%FT%TZ) $*" >> "$STATE_DIR/enforce.log"; }

# Boot baseline: the engine's top-pid device MiB shortly after it finished loading.
# The recycle term is measured AGAINST this, not against an absolute figure, because
# 88,773 MiB is normal here and 109,785 MiB is what kills the box.
update_engine_baseline() {
  local started top cur
  started=$(eng_field | awk '{print $2}'); top=$(engine_top_mib)
  if [ -z "$top" ] || [ "$top" -lt 1000 ]; then return 0; fi
  if [ ! -s "$STATE_DIR/engine_baseline_mib" ]; then
    echo "$top" > "$STATE_DIR/engine_baseline_mib"
    act_log "baseline engine top-pid = ${top} MiB (started=$started)"
    return 0
  fi
  # Ratchet the baseline DOWN only (a smaller true floor means the knobs changed);
  # never up — growing above the baseline is exactly the thing we recycle for.
  cur=$(cat "$STATE_DIR/engine_baseline_mib" 2>/dev/null || echo 0)
  [ "$top" -lt "${cur:-0}" ] && echo "$top" > "$STATE_DIR/engine_baseline_mib"
}

restart_engine() { # $1 = tag, $2 = reason
  local tag="$1" reason="$2"
  act_log "$tag: $reason — restarting $CTR"
  date +%s >> "$STATE_DIR/enforce_stamps"
  # Snapshot FIRST: after a restart the pre-event state is gone. The RESTART detector
  # fires a second bundle when the engine field actually changes.
  snapshot "$tag" "$reason"
  timeout 60 docker restart "$CTR" && act_log "$tag: docker restart issued ok" \
    || act_log "$tag: docker restart FAILED/rc=$?"
  date +%s > "$STATE_DIR/last_enforce"
  echo "$tag" > "$STATE_DIR/last_enforce_tag"
}

# Count enforced restarts inside the rate-limit window. Kept as a plain timestamp list
# so the state is readable by hand and survives the log rotating.
enforce_rate_ok() {
  local now keep
  now=$(date +%s)
  local f="$STATE_DIR/enforce_stamps"
  [ -f "$f" ] || : > "$f"
  keep=$(awk -v now="$now" -v w="$ENFORCE_WINDOW" '$1 >= now-w' "$f" 2>/dev/null)
  printf '%s\n' "$keep" > "$f"
  [ "$(printf '%s\n' "$keep" | grep -c .)" -lt "$ENFORCE_MAX" ]
}

# Wait for the engine to go idle before taking it down (a planned restart with nothing
# in flight costs nobody a request; a restart mid-generation is a 502 for that session).
# An UNREADABLE answer is treated as proceed-with-recorded-reason: an engine that cannot
# answer /metrics is already the emergency we are acting on, and refusing to act would
# leave the kernel as the only executioner. The asymmetry with check_idle_recycle below
# is deliberate — CRIT is an emergency, recycling is opportunistic.
wait_for_idle() {
  local waited=0 n
  while [ "$waited" -lt "$ENFORCE_WAIT_MAX" ]; do
    n=$(in_flight)
    case "$n" in
      ERR|'') act_log "in-flight unreadable (engine not answering /metrics) — proceeding with enforce"; return 0 ;;
      0)      return 0 ;;
    esac
    [ "$waited" -eq 0 ] && act_log "waiting up to ${ENFORCE_WAIT_MAX}s for in-flight drain (n=$n)"
    sleep 15; waited=$(( waited + 15 ))
  done
  return 1
}

# CRIT action: planned restart instead of a kernel kill that takes Traefik/dashboard/
# alloy/dcgm with it (invariants #1/#3) and wedges the box.
enforce_crit() { # $1 = reason
  local reason="$1"
  [ "$ENFORCE" = "1" ] || { act_log "CRIT (observe-only): $reason"; return 0; }
  [ -e "$NO_ENFORCE_FILE" ] && { act_log "CRIT (arm-off, $NO_ENFORCE_FILE exists): $reason"; return 0; }
  cooldown_ok enforce "$ENFORCE_COOLDOWN" || { act_log "CRIT suppressed by enforce cooldown: $reason"; return 0; }
  enforce_rate_ok || { act_log "CRIT suppressed by enforce rate limit (${ENFORCE_MAX}/${ENFORCE_WINDOW}s): $reason"; return 0; }
  wait_for_idle || { act_log "CRIT NOT enforced: still ${ENFORCE_WAIT_MAX}s of in-flight traffic — $reason"; return 0; }
  restart_engine CRIT-ENFORCED "$reason"
}

# Idle recycle: the cumulative term is per-request allocator growth that NEVER returns
# (flat at idle, +21 GiB per ~30 min of light agent traffic). Recycling at idle is free
# and removes the term before it can compound into a kill.
check_idle_recycle() {
  local top base infl now
  [ "$RECYCLE" = "1" ] || return 0
  [ -s "$STATE_DIR/engine_baseline_mib" ] || { update_engine_baseline; return 0; }
  [ -e "$NO_ENFORCE_FILE" ] && return 0
  top=$(engine_top_mib); base=$(cat "$STATE_DIR/engine_baseline_mib" 2>/dev/null || echo 0)
  [ -z "$top" ] && return 0
  infl=$(in_flight)
  now=$(date +%s)
  # Recycling is opportunistic, so it requires POSITIVE proof of idle: ERR (cannot read)
  # means we cannot prove it, and a needless restart of a healthy busy engine is exactly
  # the outage this watchdog exists to prevent. (CRIT is different — see wait_for_idle.)
  if [ -z "$infl" ] || [ "$infl" = "ERR" ] || [ "${infl:-1}" -gt 0 ]; then
    echo "$now" > "$STATE_DIR/last_busy_epoch"; return 0
  fi
  local last_busy; last_busy=$(cat "$STATE_DIR/last_busy_epoch" 2>/dev/null || echo "$now")
  [ $(( now - ${last_busy:-0} )) -ge "$RECYCLE_IDLE_S" ] || return 0
  [ "$top" -gt $(( ${base:-0} + RECYCLE_GROW_GIB * 1024 )) ] || return 0
  cooldown_ok recycle "$RECYCLE_IDLE_S" || return 0
  restart_engine RECYCLE "engine ${top} MiB > baseline ${base} + ${RECYCLE_GROW_GIB} GiB and idle > ${RECYCLE_IDLE_S}s"
}

# ---- modes ------------------------------------------------------------------
case "${1:-sample-loop}" in
  snapshot) shift; snapshot "${1:-MANUAL}" "${2:-manual request}" ;;
  status)
    echo "engine: $(eng_field)"
    echo "budget: usable=$(usable_gib) GiB  (WARN<${WARN_GIB} CRIT<${CRIT_GIB})  = MemAvailable $(mem_avail_gib) - CmaFree $(cma_free_gib)"
    echo "        (MemFree $(mem_field MemFree) is NOT the gauge — see the header of this script)"
    echo "mem:    cached=$(mem_field Cached) anon=$(mem_field AnonPages) GiB"
    echo "psi:  some avg10=$(psi_val some) full avg10=$(psi_val full)"
    echo "gpu top pid: $(gpu_mib)  baseline=$(cat "$STATE_DIR/engine_baseline_mib" 2>/dev/null || echo NA) MiB"
    echo "in flight: $(in_flight)"
    echo "governor: enforce=$ENFORCE (cooldown ${ENFORCE_COOLDOWN}s, max ${ENFORCE_MAX}/${ENFORCE_WINDOW}s, arm-off file $NO_ENFORCE_FILE) recycle=$RECYCLE (+${RECYCLE_GROW_GIB} GiB / ${RECYCLE_IDLE_S}s idle)"
    [ -s "$STATE_DIR/enforce.log" ] && { echo "governor actions:"; tail -5 "$STATE_DIR/enforce.log"; }
    echo "samples: $(wc -l < "$SAMPLES" 2>/dev/null || echo 0) rows in $SAMPLES"
    echo "last snapshots:"; ls -1dt "$SNAP_DIR"/*/ 2>/dev/null | head -5
    ;;
  sample-loop)
    ensure_ring_header
    echo "spark-oom-watchdog: dir=$BASE_DIR interval=${INTERVAL}s gauge=MemAvailable-CmaFree warn=${WARN_GIB}GiB crit=${CRIT_GIB}GiB psi=$PSI_CRIT enforce=$ENFORCE recycle=$RECYCLE"
    # capture whatever the kernel already reported this boot (cheap + immediately useful)
    check_kill_events
    while :; do
      ring_append
      check_kill_events
      check_engine_restart
      update_engine_baseline
      use=$(usable_gib); pfull=$(psi_val full)
      if awk -v u="${use:-999}" -v c="$CRIT_GIB" 'BEGIN{exit !(u<c)}' \
         || awk -v p="${pfull:-0}" -v c="$PSI_CRIT" 'BEGIN{exit !(p>c)}'; then
        # PSI alone must NOT enforce: it has no lead time (it read 0.0 for ten samples
        # before #8 died). Only the memory gauge is allowed to pull the trigger.
        reason="usable=${use}GiB psi_full=${pfull} (crit ${CRIT_GIB}GiB / ${PSI_CRIT}%)"
        if cooldown_ok CRIT "$CRIT_COOLDOWN"; then
          if awk -v u="${use:-999}" -v c="$CRIT_GIB" 'BEGIN{exit !(u<c)}'; then
            snapshot CRIT "$reason"
            enforce_crit "$reason"
          else
            snapshot CRIT "$reason [psi-only — memory gauge above crit, no enforce]"
          fi
        fi
      elif awk -v u="${use:-999}" -v w="$WARN_GIB" 'BEGIN{exit !(u<w)}'; then
        cooldown_ok WARN "$WARN_COOLDOWN" && snapshot WARN "usable=${use}GiB psi_full=${pfull} (warn ${WARN_GIB}GiB)"
      fi
      check_idle_recycle
      sleep "$INTERVAL"
    done
    ;;
  enforce-status) echo "see status" ;;
  *) echo "usage: $0 {sample-loop|snapshot <tag> [reason]|status}" >&2; exit 2 ;;
esac
