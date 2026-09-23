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
# HD-395 (2026-09-23) — THE BOOT BASELINE IS MEASURED, NOT GUESSED. Read this before
# touching the recycle term:
#   The idle-recycle trigger is `boot baseline + RECYCLE_GROW_GIB`. The baseline USED TO BE
#   the first sample of the engine top-pid after the unit started, and on this engine that
#   first read is a coin-flip: one config has been measured at 71,911 / 86,243 / 92,343 MiB
#   because the 168 GiB PLE checkpoint loads unevenly. BOTH ends of that spread are failures:
#   low floor  ⇒ the trigger sits under ordinary traffic and the watchdog restarts a HEALTHY
#                engine (two fired 35 min apart, ~20 min cold start + a 502 window);
#   high floor ⇒ the trigger sits above the traffic peak and recycle goes SILENT, which is
#                the failure direction the guard exists to prevent.
#   It is now acquired by a PERSISTED state machine: engine running → /health 200 →
#   BASELINE_SETTLE_S quiet → BASELINE_SAMPLES plausible readings inside BASELINE_SPAN_S →
#   commit the MAX of that window (the max is the floor that matters: a floor measured while
#   the checkpoint is still landing is not a floor). Acquisition is NEVER re-run on a unit
#   restart — a converge restarts the UNIT, not the engine, and a sampler restart must not
#   re-baseline a running engine to a fresh coin-flip. The only re-baseline paths are a NEW
#   ENGINE INSTANCE (check_engine_restart) and an explicit operator `rebaseline`.
#   The old "ratchet the baseline DOWN only" rule is GONE deliberately: it converted any
#   transient low read into a permanently low trigger — the same defect in a different hat.
#   SAFETY INVARIANT: a missing or partial baseline fails toward SILENCE with a logged
#   reason, NEVER toward `docker stop`. (A stop/restart here is intentional, so the engine's
#   `unless-stopped` will not bring it back on its own — see docs/hardware-spark.md.)
#   The +8 GiB margin is reported against the certified peak at commit time and in `status`:
#   at the high end of the measured spread (92,343 MiB) the trigger is 100,535 MiB, which is
#   ABOVE the certified peak of 96,235 MiB — i.e. a fixed margin over a variable floor cannot
#   be right on both ends. The watchdog now says so out loud instead of being quietly dead.
#
# Modes:
#   sample-loop              run forever (systemd default)
#   snapshot <tag> [reason]  take one bundle and exit (tag: KILL|CRIT|WARN|MANUAL)
#   status                   print current readings + baseline state + last snapshot
#   rebaseline               drop the committed baseline and re-acquire (operator action)
#   self-test                offline 6-case test of the baseline/recycle logic (stubs docker)
#   _margin                  INTERNAL (self-test): print the margin verdict only
#   _drift                   INTERNAL (self-test): print the unit/script drift note only
#   _tick                    INTERNAL (self-test): one governor tick, no sampling, no sleep
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
# OWNER DECISION 2026-09-23: DISABLED (`SPARK_OOM_RECYCLE=0`, set by the role). The box is
# stable and a ~5-20 min cold start is not worth buying anything: with a correct (max-of-N)
# baseline the trigger sits ~4 GiB ABOVE the certified peak, so a reachable margin would mean
# restarting an engine that is merely healthy. OOM protection does NOT depend on this term —
# enforce_crit() at usable < CRIT is absolute and baseline-free (HD-381 term B). Re-arm only on
# measurement: `gpu_top_mib` growing > 2 GiB/h under traffic and not returning at idle (the same
# re-arm condition as C3/--enforce-eager in HD-380).
RECYCLE="${SPARK_OOM_RECYCLE:-1}"
RECYCLE_GROW_GIB="${SPARK_OOM_RECYCLE_GROW_GIB:-8}"      # trigger above the boot baseline
RECYCLE_IDLE_S="${SPARK_OOM_RECYCLE_IDLE_S:-1800}"       # must be idle this long first

# ---- HD-395: how the boot baseline is acquired ----------------------------------------
# Chosen policy: BOTH gates, in order — (a) engine `/health` must answer 200, then (b) a
# settle window with no measurement, then (c) the MAX of N plausible samples inside a span.
# `/health` alone is not enough (it goes 200 before the PLE checkpoint has finished
# settling, which is exactly how a 71,911 MiB "first sample" was ever recorded); N samples
# alone is not enough (a window that starts too early averages in the loading ramp).
# MAX, not mean: we are looking for the floor the engine sits at when fully loaded, and the
# uneven checkpoint load can only ever make an early read read LOW.
BASELINE_SETTLE_S="${SPARK_OOM_BASELINE_SETTLE_S:-120}"   # quiet time after /health 200
BASELINE_SAMPLES="${SPARK_OOM_BASELINE_SAMPLES:-8}"       # plausible reads to collect
BASELINE_SPAN_S="${SPARK_OOM_BASELINE_SPAN_S:-600}"       # cap on the collection window
# A read below this is not the engine holding its weights — it is a partially loaded model,
# a different pid, or nvidia-smi answering nothing. Refuse it rather than commit a floor that
# would make the recycle trigger reachable by ordinary traffic.
BASELINE_MIN_MIB="${SPARK_OOM_BASELINE_MIN_MIB:-40000}"
# Certified arithmetic (hardware-spark.md §Unified-memory budget + HD-380's measured run):
# used ONLY to report whether the +8 GiB margin is reachable — it never moves the trigger.
CERTIFIED_PEAK_MIB="${SPARK_OOM_CERTIFIED_PEAK_MIB:-96235}"   # measured per-pid peak, post C1/C2
CERTIFIED_CAGE_MIB="${SPARK_OOM_CERTIFIED_CAGE_MIB:-107520}"  # spark_vllm_memory_limit = 105 GiB

# State dirs are created for every mode EXCEPT self-test, which runs entirely in a temp dir.
# (Unconditional mkdir made `self-test`/`status` on a dev box fail on the production XFS path.)
case "${1:-sample-loop}" in
  self-test) : ;;
  *) mkdir -p "$STATE_DIR" "$SNAP_DIR" ;;
esac

# ---- persisted state helpers (HD-395) -----------------------------------------------
# Every governor decision state lives in $STATE_DIR, one value per file, so it survives a
# unit restart AND is readable by a human over SSH without a parser.
st_read()  { head -1 "$STATE_DIR/$1" 2>/dev/null; }
st_write() { printf '%s\n' "$2" > "$STATE_DIR/$1" 2>/dev/null; }

# Is the integer in $1 at least $2? Non-numeric input is FALSE, never an error — the
# readings come from external tools and a garbage answer must fail toward inaction.
ge_int() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge "$2" ]; }

# ---- readings ---------------------------------------------------------------
mem_field() { awk -v f="$1" '$1==f":"{printf "%.2f", $2/1048576; exit}' /proc/meminfo; }
psi_val() { # $1 = some|full, $2 = avg10
  awk -v k="$1" '$1==k{for(i=2;i<=NF;i++) if($i ~ /^avg10=/){split($i,a,"=");printf "%.1f", a[2]; exit}}' /proc/pressure/memory 2>/dev/null
}
gpu_mib() { timeout 8 nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null \
            | sort -t, -k2 -rn | head -1 | tr -d ' ' ; }
eng_field() { timeout 10 docker inspect "$CTR" --format "{{.RestartCount}} {{.State.StartedAt}} {{.State.OOMKilled}}" 2>/dev/null; }
# HD-395: the baseline machine's two liveness questions. /health is NOT api-key gated (the
# snapshot's `health_http=` line has always read it without a bearer), so it is safe to poll
# on every tick; a 401/502/000 answer means "not measurable yet", never "baseline it".
engine_running()     { [ "$(timeout 10 docker inspect "$CTR" --format '{{.State.Running}}' 2>/dev/null)" = "true" ]; }
engine_health_code() { timeout 10 curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
                         "http://localhost:$VLLM_PORT/health" 2>/dev/null; }
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
    # New engine instance: the boot baseline is only valid per engine start, so drop it AND
    # the in-flight acquisition and let the state machine re-acquire it from scratch (HD-395:
    # health 200 → settle → max of N). This is the ONLY automatic re-baseline path; a UNIT
    # restart must never land here, because the engine field has not changed.
    rm -f "$STATE_DIR/last_busy_epoch" 2>/dev/null
    bl_reset_acquisition
    st_write baseline_stage await-health
    snapshot RESTART "engine field changed: [$prev] -> [$cur]"
  fi
}

# ---- enforcing governor (HD-381 term B) --------------------------------------
# Recorded decisions go to $STATE_DIR/enforce.log so "why did the watchdog restart my
# engine" is answerable without reconstructing it from the ring.
act_log() { echo "$(date -u +%FT%TZ) $*" >> "$STATE_DIR/enforce.log"; }

# A watchdog that declines to act must still say WHY, or "disarmed" and "dead" look identical
# (that symmetry is what made HD-395's silent-recycle direction hard to see). Rate-limited by
# key, because "baseline not ready yet" is NORMAL for the first minutes after a boot and must
# not fill enforce.log.
reason_note() { # $1 = key, $2 = window seconds, $3 = text
  cooldown_ok "note_$1" "$2" || return 0
  date +%s > "$STATE_DIR/last_note_$1" 2>/dev/null
  act_log "note[$1]: $3"
}

# ---- HD-395: the boot baseline state machine ------------------------------------------
# Stages: (unset)/await-health → settling → collecting → committed. Progress is driven one
# tick per sampler iteration and NEVER sleeps: the sampler loop already sets the cadence,
# and a blocking baseline acquisition would stall the forensics ring (the payload).
bl_stage() { st_read baseline_stage; }

bl_reset_acquisition() { # drop the in-flight acquisition, keep nothing stale
  rm -f "$STATE_DIR/baseline_stage" "$STATE_DIR/baseline_deadline" "$STATE_DIR/collect_n" \
        "$STATE_DIR/collect_max" "$STATE_DIR/boot_min_mib" "$STATE_DIR/boot_max_mib" \
        "$STATE_DIR/engine_baseline_mib" "$STATE_DIR/baseline_meta" 2>/dev/null
}

# Track the boot-floor SPREAD across the whole acquisition (including the waiting stages),
# so `status` can show a low floor and a high floor as one number instead of forcing the
# next reader into state/enforce.log.
bl_track_floor() {
  local top="$1" cur
  ge_int "$top" "$BASELINE_MIN_MIB" || return 0
  cur=$(st_read boot_min_mib); { [ -z "$cur" ] || [ "$top" -lt "$cur" ]; } && st_write boot_min_mib "$top"
  cur=$(st_read boot_max_mib); { [ -z "$cur" ] || [ "$top" -gt "$cur" ]; } && st_write boot_max_mib "$top"
  return 0
}

# The +8 GiB margin, stated against the certified peak. Reporting only — the trigger itself
# is RECYCLE_GROW_GIB over the baseline and nothing here changes it.
margin_verdict() {
  local base trigger
  # A verdict about a term that cannot run is a lie, not a readout (owner decision 2026-09-23).
  [ "$RECYCLE" = "1" ] || { echo "recycle DISABLED by config (SPARK_OOM_RECYCLE=0, owner decision 2026-09-23) — margin not evaluated"; return 0; }
  base=$(st_read engine_baseline_mib)
  ge_int "$base" 1 || { echo "no committed baseline ⇒ recycle DISARMED (silence by design)"; return 0; }
  trigger=$(( base + RECYCLE_GROW_GIB * 1024 ))
  if [ "$trigger" -gt "$CERTIFIED_CAGE_MIB" ]; then
    echo "trigger=${trigger} MiB > engine cage ${CERTIFIED_CAGE_MIB} MiB ⇒ recycle unreachable before the cage/OOM"
  elif [ "$trigger" -gt "$CERTIFIED_PEAK_MIB" ]; then
    echo "trigger=${trigger} MiB > certified peak ${CERTIFIED_PEAK_MIB} MiB ⇒ recycle will stay SILENT on ordinary traffic (HD-395 open margin question)"
  else
    echo "trigger=${trigger} MiB ≤ certified peak ${CERTIFIED_PEAK_MIB} MiB ⇒ recycle reachable (headroom $(( CERTIFIED_PEAK_MIB - trigger )) MiB)"
  fi
}

bl_commit() { # $1 = max plausible MiB seen in the collecting window
  local max="$1" n
  n=$(st_read collect_n)
  st_write engine_baseline_mib "$max"
  st_write baseline_stage committed
  st_write baseline_meta "value=${max}MiB samples=${n:-0}/${BASELINE_SAMPLES} window=${BASELINE_SPAN_S}s settle=${BASELINE_SETTLE_S}s boot_min=$(st_read boot_min_mib)MiB boot_max=$(st_read boot_max_mib)MiB committed=$(date -u +%FT%TZ)"
  act_log "baseline COMMITTED engine top-pid = ${max} MiB (n=${n:-0}, boot floor spread $(st_read boot_min_mib)–$(st_read boot_max_mib) MiB) | margin: $(margin_verdict)"
}

baseline_tick() {
  local stage now top n max hc
  now=$(date +%s)
  stage=$(bl_stage)
  [ "$stage" = "committed" ] && return 0
  top=$(engine_top_mib)
  bl_track_floor "$top"

  case "$stage" in
    ''|await-health)
      if ! engine_running; then
        reason_note baseline 900 "engine container not running — baseline acquisition waiting (recycle disarmed)"
        st_write baseline_stage await-health; return 0
      fi
      hc=$(engine_health_code)
      if [ "$hc" != "200" ]; then
        reason_note baseline 900 "engine /health answered '${hc:-no-answer}' — baseline acquisition waiting (recycle disarmed)"
        st_write baseline_stage await-health; return 0
      fi
      st_write baseline_stage settling
      st_write baseline_deadline $(( now + BASELINE_SETTLE_S ))
      act_log "baseline: /health 200 — settling ${BASELINE_SETTLE_S}s before measuring (HD-395: the first read is a coin-flip)"
      return 0 ;;
    settling)
      [ "$now" -lt "$(st_read baseline_deadline)" ] && return 0
      st_write baseline_stage collecting
      st_write baseline_deadline $(( now + BASELINE_SPAN_S ))
      st_write collect_n 0
      st_write collect_max 0
      return 0 ;;
    collecting)
      n=$(st_read collect_n); n=${n:-0}
      max=$(st_read collect_max); max=${max:-0}
      if ge_int "$top" "$BASELINE_MIN_MIB"; then
        n=$(( n + 1 )); st_write collect_n "$n"
        [ "$top" -gt "$max" ] && { max="$top"; st_write collect_max "$max"; }
      fi
      if [ "$n" -ge "$BASELINE_SAMPLES" ] || [ "$now" -ge "$(st_read baseline_deadline)" ]; then
        if ! ge_int "$max" "$BASELINE_MIN_MIB"; then
          # Fail toward silence: no plausible reading ⇒ no baseline ⇒ no recycle decision.
          reason_note baseline 300 "no plausible engine read in the ${BASELINE_SPAN_S}s window (n=$n max=${max:-0} < ${BASELINE_MIN_MIB} MiB) — baseline NOT committed, recycle disarmed"
          rm -f "$STATE_DIR/baseline_stage" "$STATE_DIR/collect_n" "$STATE_DIR/collect_max" 2>/dev/null
          return 0
        fi
        bl_commit "$max"
      fi
      return 0 ;;
    *) # unknown/corrupt stage marker ⇒ restart acquisition from the top, never act on it
      rm -f "$STATE_DIR/baseline_stage" 2>/dev/null
      st_write baseline_stage await-health; return 0 ;;
  esac
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
  # HD-395 SAFETY INVARIANT: no recycle decision without a COMMITTED baseline. A missing or
  # half-acquired one fails toward silence-with-a-reason, never toward `docker stop`.
  if [ "$(bl_stage)" != "committed" ] || ! ge_int "$(st_read engine_baseline_mib)" "$BASELINE_MIN_MIB"; then
    reason_note recycle 900 "recycle disarmed: baseline stage='$(bl_stage)', value='$(st_read engine_baseline_mib)' (needs stage=committed and >= ${BASELINE_MIN_MIB} MiB)"
    return 0
  fi
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

# A manual `sudo /usr/local/bin/spark-oom-watchdog.sh status` does NOT inherit the unit's
# `Environment=` lines, so it reads the SCRIPT DEFAULTS and can disagree with what the running
# guard actually does (measured live 2026-09-23: the unit ran SPARK_OOM_RECYCLE=0 while a sudo
# `status` printed `recycle=1` and a margin verdict for a term the unit cannot execute). The unit
# is what enforces, so say so out loud instead of letting the readout contradict the deploy.
# SPARK_OOM_UNIT_ENV lets the self-test inject the unit env offline; never set it in production.
config_drift_note() {
  local ue pair uvar svar got want drift=""
  ue="${SPARK_OOM_UNIT_ENV_OVERRIDE:-$(systemctl show -p Environment --value spark-oom-watchdog.service 2>/dev/null || true)}"
  [ -n "$ue" ] || return 0
  # unit-var : the variable THIS script actually parsed (the parsed value is what a manual
  # invocation enforces/reports — comparing the raw env name against itself would always agree).
  for pair in SPARK_OOM_ENFORCE:ENFORCE SPARK_OOM_RECYCLE:RECYCLE \
              SPARK_OOM_RECYCLE_GROW_GIB:RECYCLE_GROW_GIB SPARK_OOM_RECYCLE_IDLE_S:RECYCLE_IDLE_S \
              SPARK_OOM_WARN_GIB:WARN_GIB SPARK_OOM_CRIT_GIB:CRIT_GIB; do
    uvar=${pair%%:*}; svar=${pair##*:}
    got=$(printf '%s' "$ue" | tr ' ' '\n' | sed -n "s|^${uvar}=||p")
    want=$(eval "printf '%s' \"\${$svar:-}\"")
    [ -n "$got" ] && [ "$got" != "$want" ] && drift="$drift ${uvar}(unit=$got this-shell=$want)"
  done
  [ -n "$drift" ] || return 0
  echo "⚠ CONFIG DRIFT: this invocation read its own environment, not the unit's — the UNIT is what enforces:$drift"
  echo "  effective unit env: systemctl show -p Environment --value spark-oom-watchdog.service"
  return 0
}

# ---- self-test (HD-395) ---------------------------------------------------------------
# Offline by construction: everything external is stubbed on PATH (docker, nvidia-smi, curl,
# journalctl, dmesg, uptime) and every state file lands in a temp dir. It drives the REAL
# governor functions by invoking this same script as `_tick` — one process per tick, which is
# also how the persistence-across-a-unit-restart property is proved. `docker` here is a file
# append: the test can never touch a real engine.
# It is written to be RED-able, and the mutants are recorded HERE because the delivery note that
# used to carry them is deleted: C1 dies if the `/health`-200 or the settle gate in baseline_tick
# is dropped, or if bl_commit stores the first read instead of the max; C2 dies if a low read may
# down-ratchet the committed baseline; C3 dies if the growth/idle comparison in check_idle_recycle
# is inverted (a guard that cannot fire IS the bug); C4 dies if the `in_flight` ERR proof or the
# committed-baseline precondition is removed (silence must be earned, never assumed); C5 dies if
# the `[ "$RECYCLE" = "1" ]` early-return in check_idle_recycle or the DISABLED branch of
# margin_verdict is removed; C6 dies if the comparison in config_drift_note is dropped (it then
# stays silent while the unit and the script disagree) or inverted (it then cries on agreement).
self_test() {
  local SELF_SRC tmp bin st pass=0 fail=0
  local T_SETTLE=0 T_SAMPLES=3 T_SPAN=600 T_MINMIB=40000 T_GROW=8 T_IDLE=1800
  SELF_SRC=$(readlink -f "$0")
  tmp=$(mktemp -d /tmp/spark-oom-selftest.XXXXXX) || { echo "self-test: mktemp failed"; return 1; }
  bin="$tmp/bin"; st="$tmp/stub"
  mkdir -p "$bin" "$st"

  cat > "$bin/docker" <<'STUB'
#!/bin/sh
D=$SPARK_OOM_STUB_DIR
case " $* " in
  *'.State.Running'*)   cat "$D/running" 2>/dev/null; exit 0 ;;
  *'{{.RestartCount}}'*) printf '0 %s false\n' "$(cat "$D/started" 2>/dev/null)"; exit 0 ;;
  *'join .Args'*)        printf 'vllm serve --api-key stub-not-a-secret\n'; exit 0 ;;
  *restart*)             printf 'restart\n' >> "$D/restarts"; exit 0 ;;
esac
case " $* " in
  *'ps -q'*) printf 'stubid\n' ;;
  *'logs'*)  : ;;
  *'ps'*)    printf 'vllm-qwen-spark\tUp (stub)\n' ;;
esac
exit 0
STUB
  cat > "$bin/nvidia-smi" <<'STUB'
#!/bin/sh
case " $* " in
  *query-compute-apps*) printf '4242,%s\n' "$(cat "$SPARK_OOM_STUB_DIR/top_mib" 2>/dev/null || echo 0)" ;;
  *) printf 'stub,stub\n' ;;
esac
exit 0
STUB
  cat > "$bin/curl" <<'STUB'
#!/bin/sh
D=$SPARK_OOM_STUB_DIR
case " $* " in
  *health*)  printf '%s' "$(cat "$D/health" 2>/dev/null || echo 000)"; exit 0 ;;
  *metrics*) v=$(cat "$D/inflight" 2>/dev/null || echo ERR)
             [ "$v" = "ERR" ] && exit 0
             printf 'vllm:num_requests_running{model_name="stub"} %s\nvllm:num_requests_waiting{model_name="stub"} 0\n' "$v"
             exit 0 ;;
esac
printf '000'
STUB
  printf '#!/bin/sh\nexit 0\n' > "$bin/journalctl"; printf '#!/bin/sh\nexit 0\n' > "$bin/dmesg"
  printf '#!/bin/sh\ncase " $* " in *Environment*) printf "SPARK_OOM_ENFORCE=1 SPARK_OOM_RECYCLE=0\\n";; esac\nexit 0\n' > "$bin/systemctl"
  printf '#!/bin/sh\n[ "$1" = -s ] && { echo "2026-09-23 00:00:00"; exit 0; }\nprintf "up 0 mins (stub)\\n"\n' > "$bin/uptime"
  chmod +x "$bin"/*
  printf 'true' > "$st/running"; printf '2026-09-23T00:00:00Z' > "$st/started"
  printf '000' > "$st/health"; printf '0' > "$st/top_mib"; printf 'ERR' > "$st/inflight"
  : > "$st/restarts"

  tick() {
    env PATH="$bin:$PATH" SPARK_OOM_DIR="$tmp/base" SPARK_OOM_INTERVAL=1 \
        SPARK_OOM_STUB_DIR="$st" SPARK_OOM_KEEP_SNAPS=2 \
        SPARK_OOM_BASELINE_SETTLE_S="$T_SETTLE" SPARK_OOM_BASELINE_SAMPLES="$T_SAMPLES" \
        SPARK_OOM_BASELINE_SPAN_S="$T_SPAN" SPARK_OOM_BASELINE_MIN_MIB="$T_MINMIB" \
        SPARK_OOM_RECYCLE=1 SPARK_OOM_RECYCLE_GROW_GIB="$T_GROW" SPARK_OOM_RECYCLE_IDLE_S="$T_IDLE" \
        SPARK_OOM_ENFORCE=0 VLLM_CONTAINER=vllm-qwen-spark \
        bash "$SELF_SRC" _tick >/dev/null 2>&1
  }
  tick_off() {   # the SAME tick with the recycle term OFF (the owner-decided live config)
    env PATH="$bin:$PATH" SPARK_OOM_DIR="$tmp/base" SPARK_OOM_INTERVAL=1 \
        SPARK_OOM_STUB_DIR="$st" SPARK_OOM_KEEP_SNAPS=2 \
        SPARK_OOM_BASELINE_SETTLE_S="$T_SETTLE" SPARK_OOM_BASELINE_SAMPLES="$T_SAMPLES" \
        SPARK_OOM_BASELINE_SPAN_S="$T_SPAN" SPARK_OOM_BASELINE_MIN_MIB="$T_MINMIB" \
        SPARK_OOM_RECYCLE=0 SPARK_OOM_RECYCLE_GROW_GIB="$T_GROW" SPARK_OOM_RECYCLE_IDLE_S="$T_IDLE" \
        SPARK_OOM_ENFORCE=0 VLLM_CONTAINER=vllm-qwen-spark \
        bash "$SELF_SRC" _tick >/dev/null 2>&1
  }
  margin_line() { # $1 = SPARK_OOM_RECYCLE value; reads the state the last case left behind
    env PATH="$bin:$PATH" SPARK_OOM_DIR="$tmp/base" SPARK_OOM_STUB_DIR="$st" \
        SPARK_OOM_RECYCLE="$1" SPARK_OOM_RECYCLE_GROW_GIB="$T_GROW" \
        bash "$SELF_SRC" _margin 2>/dev/null | head -1
  }
  seed() { printf '%s' "$1" > "$st/health"; printf '%s' "$2" > "$st/running"
           printf '%s' "$3" > "$st/top_mib"; printf '%s' "$4" > "$st/inflight"; }
  new_case() { rm -rf "$tmp/base"; mkdir -p "$tmp/base/state" "$tmp/base/snapshots"; : > "$st/restarts"; }
  restarts()   { wc -l < "$st/restarts" 2>/dev/null | tr -d ' '; }
  stv()        { head -1 "$tmp/base/state/$1" 2>/dev/null; }
  commit_by_hand() { # $1 = MiB — a state dir a real acquisition would have produced
    printf 'committed\n' > "$tmp/base/state/baseline_stage"
    printf '%s\n' "$1" > "$tmp/base/state/engine_baseline_mib"; }
  idle_since() { printf '%s\n' "$(( $(date +%s) - $1 ))" > "$tmp/base/state/last_busy_epoch"; }
  ok()   { printf '  PASS %s\n' "$1"; pass=$((pass+1)); }
  bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }
  expect_eq() { if [ "$2" = "$3" ]; then ok "$1 = $3"; else bad "$1: got '$2' want '$3'"; fi; }

  printf 'self-test (HD-395 baseline + recycle governance), stubs in %s\n' "$tmp"

  # C1 — acquisition waits for a REAL engine, and a LOW first read must never become the
  #      baseline. Until it commits, the recycle path must be silent.
  new_case
  seed 200 false 92343 0            # container not running at all — nothing may be measured
  tick; tick
  expect_eq "C1 stage while engine not running" "$(stv baseline_stage)" "await-health"
  expect_eq "C1 no baseline while not running"  "$(stv engine_baseline_mib)" ""
  expect_eq "C1 no restart while not running"   "$(restarts)" "0"
  seed 503 true 71911 0
  tick; tick; tick; tick; tick
  expect_eq "C1 stage while /health is 503"  "$(stv baseline_stage)" "await-health"
  expect_eq "C1 no baseline while unhealthy" "$(stv engine_baseline_mib)" ""
  expect_eq "C1 restarts while unhealthy"    "$(restarts)" "0"
  seed 200 true 86243 0; tick                       # health 200 → settling
  expect_eq "C1 stage after health 200" "$(stv baseline_stage)" "settling"
  tick                                              # settle done → collecting (no sample this tick)
  expect_eq "C1 stage after settle" "$(stv baseline_stage)" "collecting"
  expect_eq "C1 restarts while acquiring" "$(restarts)" "0"
  seed 200 true 92343 0; tick
  seed 200 true 86243 0; tick
  seed 200 true 86243 0; tick
  expect_eq "C1 committed stage"   "$(stv baseline_stage)" "committed"
  expect_eq "C1 baseline = MAX not first read" "$(stv engine_baseline_mib)" "92343"
  expect_eq "C1 boot floor min recorded"       "$(stv boot_min_mib)" "71911"
  expect_eq "C1 boot floor max recorded"       "$(stv boot_max_mib)" "92343"
  expect_eq "C1 never restarted the engine"    "$(restarts)" "0"

  # C2 — a committed baseline survives new processes (unit restarts) and a LOW later read
  new_case
  seed 200 true 92343 0
  tick; tick; tick; tick; tick
  expect_eq "C2 committed" "$(stv engine_baseline_mib)" "92343"
  seed 200 true 71911 0
  tick; tick; tick; tick
  expect_eq "C2 no down-ratchet on a low read" "$(stv engine_baseline_mib)" "92343"
  expect_eq "C2 stage stays committed"         "$(stv baseline_stage)" "committed"
  expect_eq "C2 no restart"                    "$(restarts)" "0"

  # C3 — growth + proven idle ⇒ the guard DOES fire (a guard that cannot fire is the bug)
  new_case
  commit_by_hand 92343; idle_since 4000
  seed 200 true 101000 0            # 92343 + 8 GiB = 100535 < 101000
  tick
  expect_eq "C3 recycle fired once" "$(restarts)" "1"
  if grep -q 'RECYCLE' "$tmp/base/state/enforce.log" 2>/dev/null; then ok "C3 enforce.log records RECYCLE"; else bad "C3 enforce.log has no RECYCLE line"; fi

  # C4 — no positive proof of idle (or no baseline) ⇒ silence, never `docker stop`
  new_case
  commit_by_hand 92343; idle_since 4000
  seed 200 true 101000 ERR; tick
  expect_eq "C4a in-flight unreadable ⇒ no restart" "$(restarts)" "0"
  seed 200 true 101000 3;   tick
  expect_eq "C4b in-flight busy ⇒ no restart"       "$(restarts)" "0"
  new_case                                           # growth + idle but NO baseline
  idle_since 4000
  seed 200 true 101000 0; tick
  expect_eq "C4c no baseline ⇒ no restart" "$(restarts)" "0"
  if grep -q 'recycle disarmed' "$tmp/base/state/enforce.log" 2>/dev/null; then
    ok "C4c the silence is logged with a reason"
  else
    bad "C4c silence was not explained in enforce.log"
  fi

  # C5 — the owner-decided live config (2026-09-23): the recycle term is OFF. Everything that
  #      made C3 fire must now be silent, and the readout must SAY it is disabled instead of
  #      printing a margin verdict for a term that can never run.
  new_case
  commit_by_hand 92343; idle_since 4000
  seed 200 true 101000 0
  tick_off; tick_off
  expect_eq "C5 recycle disabled ⇒ no restart (C3's own trigger state)" "$(restarts)" "0"
  case "$(margin_line 0)" in
    *DISABLED*) ok "C5 status/margin says the term is disabled" ;;
    *) bad "C5 margin line does not say disabled: got '$(margin_line 0)'" ;;
  esac
  case "$(margin_line 1)" in
    *trigger=*) ok "C5 margin verdict is still computed when the term is on" ;;
    *) bad "C5 margin verdict missing with RECYCLE=1: got '$(margin_line 1)'" ;;
  esac

  # C6 — the readout must not contradict the deploy: a manual invocation whose environment
  #      differs from the running unit's must SAY so (sudo does not inherit unit Environment=).
  drift_line() { # $1 = SPARK_OOM_RECYCLE for this shell, $2 = the fake unit value
    env PATH="$bin:$PATH" SPARK_OOM_DIR="$tmp/base" SPARK_OOM_STUB_DIR="$st" \
        SPARK_OOM_RECYCLE="$1" SPARK_OOM_ENFORCE=1 SPARK_OOM_WARN_GIB=12 SPARK_OOM_CRIT_GIB=8 \
        SPARK_OOM_UNIT_ENV_OVERRIDE="SPARK_OOM_ENFORCE=1 SPARK_OOM_RECYCLE=$2" \
        bash "$SELF_SRC" _drift 2>/dev/null | head -1
  }
  new_case
  case "$(drift_line 1 0)" in
    *"CONFIG DRIFT"*) ok "C6 a unit/script disagreement is announced" ;;
    *) bad "C6 drift was hidden: got '$(drift_line 1 0)'" ;;
  esac
  expect_eq "C6 agreement stays silent" "$(drift_line 0 0)" ""

  printf 'self-test: %d assertions, %d failed ⇒ %s\n' "$((pass+fail))" "$fail" \
    "$([ "$fail" -eq 0 ] && echo 'ALL PASS (6/6 cases)' || echo RED)"
  rm -rf "$tmp"
  [ "$fail" -eq 0 ]
}

# The two governor calls the sampler loop makes per iteration, factored out so the self-test
# can drive the SAME code path one tick at a time (the CRIT/snapshot path is deliberately not
# part of it — it is exercised live, and driving it here would restart things).
_tick_body() { baseline_tick; check_idle_recycle; }

# ---- modes ------------------------------------------------------------------
case "${1:-sample-loop}" in
  snapshot) shift; snapshot "${1:-MANUAL}" "${2:-manual request}" ;;
  status)
    echo "engine: $(eng_field)"
    echo "budget: usable=$(usable_gib) GiB  (WARN<${WARN_GIB} CRIT<${CRIT_GIB})  = MemAvailable $(mem_avail_gib) - CmaFree $(cma_free_gib)"
    echo "        (MemFree $(mem_field MemFree) is NOT the gauge — see the header of this script)"
    echo "mem:    cached=$(mem_field Cached) anon=$(mem_field AnonPages) GiB"
    echo "psi:  some avg10=$(psi_val some) full avg10=$(psi_val full)"
    echo "gpu top pid: $(gpu_mib)"
    echo "baseline: stage=$(bl_stage) value=$(st_read engine_baseline_mib || echo NA) MiB"
    echo "          (acquisition: /health 200 → settle ${BASELINE_SETTLE_S}s → max of ${BASELINE_SAMPLES} plausible reads inside ${BASELINE_SPAN_S}s; plausible ≥ ${BASELINE_MIN_MIB} MiB)"
    [ -s "$STATE_DIR/baseline_meta" ] && echo "          $(st_read baseline_meta)"
    echo "          boot floor: min=$(st_read boot_min_mib || echo NA) max=$(st_read boot_max_mib || echo NA) MiB  ← the HD-395 coin-flip, as one spread"
    echo "          margin: $(margin_verdict)"
    echo "in flight: $(in_flight)"
    echo "governor: enforce=$ENFORCE (cooldown ${ENFORCE_COOLDOWN}s, max ${ENFORCE_MAX}/${ENFORCE_WINDOW}s, arm-off file $NO_ENFORCE_FILE) recycle=$RECYCLE (+${RECYCLE_GROW_GIB} GiB / ${RECYCLE_IDLE_S}s idle)"
    config_drift_note
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
      baseline_tick
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
  _tick) _tick_body ;;
  _margin) margin_verdict ;;
  _drift) config_drift_note ;;
  rebaseline) # operator action: drop the committed baseline and re-acquire from scratch
    act_log "rebaseline requested (operator): previous baseline=$(st_read engine_baseline_mib) stage=$(bl_stage)"
    bl_reset_acquisition; st_write baseline_stage await-health
    echo "baseline cleared; re-acquiring: /health 200 → settle ${BASELINE_SETTLE_S}s → max of ${BASELINE_SAMPLES} reads inside ${BASELINE_SPAN_S}s (plausible ≥ ${BASELINE_MIN_MIB} MiB)"
    ;;
  self-test) self_test; exit $? ;;
  *) echo "usage: $0 {sample-loop|snapshot <tag> [reason]|status|rebaseline|self-test}" >&2; exit 2 ;;
esac
