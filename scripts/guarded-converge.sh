#!/usr/bin/env bash
# =====================================================================
# guarded-converge.sh — converge (or restart-proof) ONE docker compose
#   service behind an independent auto-re-enable armed on the target.
#   HD-415.
#
# WHY THIS EXISTS (owner safety condition, 2026-09-22): landing a headscale
# config/policy change is a stop/start of the tailnet control plane, and every
# tailnet device's remote path rides that control plane. A driving session that
# dies mid-restart must NOT be able to leave it down. Two independent halves:
#
#   converge:  1. self-test the watchdog logic
#              2. copy + ARM the watchdog on the TARGET, detached (setsid, no
#                 tty) — it survives an SSH drop, a laptop death, a killed
#                 ansible, and an untrapped converge
#              3. PROVE it is alive (process + its own "armed:" log line) and
#                 only then touch the service — see the live lesson below
#              4. run the converge in a wrapper whose TRAP brings the service
#                 up on any exit (the cheap half — a trap does not run on SIGKILL)
#              5. verify the container runs, and only THEN disarm
#
#   prove:     arm → assert → `docker stop` the real container → WATCH it come
#              back with nothing but the watchdog allowed to act. This is the
#              acceptance the HD-415 authorization asks for ("build and PROVE the
#              auto-re-enable before the first stop"). Costs one short outage.
#
# LIVE LESSON (2026-09-22, this repo, first proof attempt): a proof script that
# copied the watchdog in an earlier step stopped headscale anyway when the copy
# had silently not happened — the net was never armed and the control plane sat
# down for 2m20s until a manual `compose up`. Hence: every destructive step in
# this script is behind an assert that re-reads live state (file present + md5
# match + watchdog process + its "armed:" line), and `prove` refuses to stop
# anything unless all of them pass in the SAME run.
#
# Usage:
#   bash scripts/guarded-converge.sh --action prove    --target vps --container headscale
#   bash scripts/guarded-converge.sh --action converge --target vps --container headscale \
#        --playbook playbooks/vps.yml --limit vps --tags docker_services,headscale
# Both tag classes are mandatory for docker_services (inner per-service tasks
# carry `tags: svc.name` — deployment-ansible.md "silent no-op"), so the default
# tag set is `docker_services,<container>`.
#
# Re-executes itself under setsid+nohup and prints the log path; poll that log.
# `--foreground` runs it inline.
# =====================================================================
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ACTION="converge"
TARGET=""
CONTAINER=""
PROJECT=""
PLAYBOOK="playbooks/vps.yml"
LIMIT=""
TAGS=""
EXTRA=""
GRACE=""
WINDOW=""
INTERVAL=""
CONSECUTIVE=""
REMOTE_DIR="/tmp/restart-watchdog"
RUNNER_TAG=""
FOREGROUND=0
ARGS=("$@")

while [ $# -gt 0 ]; do
    case "$1" in
        --action)      ACTION="${2:-}"; shift 2 ;;
        --target)      TARGET="${2:-}"; shift 2 ;;
        --container)   CONTAINER="${2:-}"; shift 2 ;;
        --project)     PROJECT="${2:-}"; shift 2 ;;
        --playbook)    PLAYBOOK="${2:-}"; shift 2 ;;
        --limit)       LIMIT="${2:-}"; shift 2 ;;
        --tags)        TAGS="${2:-}"; shift 2 ;;
        --extra)       EXTRA="${2:-}"; shift 2 ;;
        --grace)       GRACE="${2:-}"; shift 2 ;;
        --window)      WINDOW="${2:-}"; shift 2 ;;
        --interval)    INTERVAL="${2:-}"; shift 2 ;;
        --consecutive) CONSECUTIVE="${2:-}"; shift 2 ;;
        --foreground)  FOREGROUND=1; shift ;;
        -h|--help)     sed -n '2,44p' "$0"; exit 0 ;;
        *) echo "FAIL: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

[ "$ACTION" = "converge" ] || [ "$ACTION" = "prove" ] || { echo "FAIL: --action must be converge|prove" >&2; exit 2; }
[ -n "$TARGET" ]    || { echo "FAIL: --target <ssh alias of the host running the service>" >&2; exit 2; }
[ -n "$CONTAINER" ] || { echo "FAIL: --container <container name>" >&2; exit 2; }
[ -n "$PROJECT" ]   || PROJECT="/opt/${CONTAINER}"
[ -n "$TAGS" ]      || TAGS="docker_services,${CONTAINER}"
# Timing defaults differ by action: `converge` must outlast a legitimate scoped
# converge before it may act (a watchdog that fires during a normal restart is a
# race, not a net), while `prove` is a deliberate short outage under observation.
if [ "$ACTION" = "prove" ]; then
    GRACE=${GRACE:-20}; WINDOW=${WINDOW:-120}; INTERVAL=${INTERVAL:-5}; CONSECUTIVE=${CONSECUTIVE:-2}
else
    GRACE=${GRACE:-240}; WINDOW=${WINDOW:-900}; INTERVAL=${INTERVAL:-10}; CONSECUTIVE=${CONSECUTIVE:-3}
fi
[ -n "$RUNNER_TAG" ] || RUNNER_TAG="$(date +%Y%m%d-%H%M%S)"
WATCHDOG="${REPO}/scripts/restart-watchdog.sh"
REMOTE_WATCHDOG="${REMOTE_DIR}/restart-watchdog.sh"
DISARM="${REMOTE_DIR}/${CONTAINER}.disarm"
WD_LOG="/tmp/${CONTAINER}-watchdog.log"
COMPOSE="${PROJECT}/docker-compose.yml"

log() { printf '%s guarded-converge[%s]: %s\n' "$(date -u +%H:%M:%S)" "$ACTION" "$*"; }
die() { log "FAIL: $*"; exit 1; }
bring_up() { ssh -o BatchMode=yes "$TARGET" docker compose -f "$COMPOSE" up -d; }

# ---- detach unless asked to run inline -------------------------------------
if [ "$FOREGROUND" != 1 ]; then
    LOG="/tmp/guarded-${ACTION}-${CONTAINER}-${RUNNER_TAG}.log"
    setsid nohup bash "$0" --action "$ACTION" --foreground "${ARGS[@]}" </dev/null >"$LOG" 2>&1 &
    echo "detached (pid $!) — log: $LOG"
    echo "poll: tail -f $LOG"
    exit 0
fi

log "target=${TARGET} container=${CONTAINER} compose=${COMPOSE}"
log "watchdog: grace=${GRACE}s window=${WINDOW}s interval=${INTERVAL}s consecutive=${CONSECUTIVE} disarm=${DISARM}"

# ---- 1. prove the net's LOGIC before anything else -------------------------
[ -f "$WATCHDOG" ] || die "watchdog script missing: $WATCHDOG"
bash "$WATCHDOG" self-test || die "watchdog self-test is RED — refusing to touch ${CONTAINER}"

# ---- 2. put the watchdog ON THE TARGET and prove the copy ------------------
ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" true \
    || die "cannot ssh ${TARGET} — nothing was changed"
ssh "$TARGET" "install -d -m 0755 ${REMOTE_DIR} && cat > ${REMOTE_WATCHDOG}" < "$WATCHDOG" \
    || die "could not copy the watchdog to ${TARGET}:${REMOTE_WATCHDOG}"
LOCAL_MD5="$(md5sum "$WATCHDOG" | awk '{print $1}')"
REMOTE_MD5="$(ssh "$TARGET" "md5sum ${REMOTE_WATCHDOG} 2>/dev/null | cut -d' ' -f1")"
[ "$LOCAL_MD5" = "$REMOTE_MD5" ] || die "watchdog md5 mismatch on ${TARGET} (local ${LOCAL_MD5} != remote ${REMOTE_MD5})"
log "watchdog present on ${TARGET} (md5 ${LOCAL_MD5})"

# ---- 3. arm it, and prove it is ALIVE before anything may break ------------
ssh "$TARGET" "rm -f ${DISARM}" || die "could not clear a stale disarm marker on ${TARGET}"
ssh "$TARGET" "setsid nohup bash ${REMOTE_WATCHDOG} arm --container ${CONTAINER} --project ${PROJECT} \
      --grace ${GRACE} --window ${WINDOW} --interval ${INTERVAL} --consecutive ${CONSECUTIVE} \
      --disarm ${DISARM} > ${WD_LOG} 2>&1 < /dev/null & echo launched" >/dev/null \
    || die "could not launch the watchdog on ${TARGET}"
sleep 3
ALIVE="$(ssh "$TARGET" "pgrep -fc 'restart-watchdog.sh arm' || true")"
ARMED_LINE="$(ssh "$TARGET" "grep -c 'armed:' ${WD_LOG} || true")"
{ [ "${ALIVE:-0}" -ge 1 ] && [ "${ARMED_LINE:-0}" -ge 1 ]; } \
    || die "watchdog is NOT provably alive on ${TARGET} (procs=${ALIVE:-0} armed-lines=${ARMED_LINE:-0}) — refusing to touch ${CONTAINER}. Log: ssh ${TARGET} cat ${WD_LOG}"
log "watchdog ARMED and alive on ${TARGET} (log: ${WD_LOG})"
ssh "$TARGET" "docker inspect -f 'PRE-STATE running={{.State.Running}} started={{.State.StartedAt}}' ${CONTAINER} 2>/dev/null || echo 'PRE-STATE: container absent'"

if [ "$ACTION" = "prove" ]; then
    # ---- 4. stop it, and let ONLY the watchdog bring it back ---------------
    PRE_STARTED="$(ssh "$TARGET" "docker inspect -f '{{.State.StartedAt}}' ${CONTAINER}")"
    log "stopping ${CONTAINER} — this session will NOT start it again"
    ssh "$TARGET" "docker stop -t 10 ${CONTAINER}" >/dev/null || die "docker stop failed (watchdog still armed — wait for it or bring it up manually)"
    DEADLINE=$(( $(date +%s) + WINDOW + 60 ))
    BACK=""
    while [ "$(date +%s)" -lt "$DEADLINE" ]; do
        sleep 5
        if [ "$(ssh "$TARGET" "docker inspect -f '{{.State.Running}}' ${CONTAINER} 2>/dev/null")" = "true" ]; then
            BACK=$(date -u +%H:%M:%S); break
        fi
        log "still down at $(date -u +%H:%M:%S)"
    done
    [ -n "$BACK" ] || die "${CONTAINER} did NOT come back within $((WINDOW + 60))s — bring it up NOW: ssh ${TARGET} docker compose -f ${COMPOSE} up -d"
    POST_STARTED="$(ssh "$TARGET" "docker inspect -f '{{.State.StartedAt}}' ${CONTAINER}")"
    [ "$PRE_STARTED" != "$POST_STARTED" ] || die "running but StartedAt unchanged (${POST_STARTED}) — something other than a real restart is going on"
    FIRED="$(ssh "$TARGET" "grep -c 'RE-ENABLING' ${WD_LOG} || true")"
    log "recovered at ${BACK}; new StartedAt ${POST_STARTED}; watchdog 'RE-ENABLING' entries=${FIRED}"
    [ "${FIRED:-0}" -ge 1 ] || die "${CONTAINER} came back but the watchdog log shows no RE-ENABLING — the recovery was NOT the net, so this proves nothing"
    ssh "$TARGET" "bash ${REMOTE_WATCHDOG} disarm --disarm ${DISARM}" || log "WARN: could not write the disarm marker"
    log "RESULT: GREEN — the watchdog re-enabled ${CONTAINER} by itself; marker now written"
    exit 0
fi

# ---- 4. the converge, detached, with a bring-it-up trap --------------------
log "playbook=${PLAYBOOK} limit=${LIMIT:-<none>} tags=${TAGS} extra=${EXTRA:-<none>}"
RUNNER="/tmp/guarded-converge-runner-${CONTAINER}-${RUNNER_TAG}.sh"
cat > "$RUNNER" <<RUNNER_SH
#!/usr/bin/env bash
# Generated by guarded-converge.sh — trap + converge, nothing else.
set -uo pipefail
ensure_up() {
    echo "[\$(date -u +%H:%M:%S)] TRAP FIRED — re-enabling ${CONTAINER} on ${TARGET}"
    ssh -o BatchMode=yes ${TARGET} docker compose -f ${COMPOSE} up -d
    echo "[\$(date -u +%H:%M:%S)] trap re-enable command returned"
}
trap 'ensure_up' EXIT INT TERM HUP
bash '${REPO}/scripts/ansible-run.sh' ${PLAYBOOK}${LIMIT:+ --limit ${LIMIT}} --tags '${TAGS}' ${EXTRA}
RUNNER_SH
chmod +x "$RUNNER"
bash "$RUNNER"
RC=$?
log "converge returned rc=$RC"

# ---- 5. verify, then disarm ------------------------------------------------
sleep 3
STATE="$(ssh "$TARGET" "docker inspect -f '{{.State.Running}} {{.State.StartedAt}}' ${CONTAINER} 2>&1" || true)"
log "post-state: ${STATE}"
case "$STATE" in
    true*)
        ssh "$TARGET" "bash ${REMOTE_WATCHDOG} disarm --disarm ${DISARM}" || log "WARN: could not write the disarm marker"
        log "RESULT: GREEN — ${CONTAINER} is running after the converge and the watchdog is disarmed"
        ;;
    *)
        log "RESULT: RED — ${CONTAINER} is NOT running."
        log "The watchdog is still ARMED and will re-enable it; live log: ssh ${TARGET} tail -40 ${WD_LOG}"
        ;;
esac
exit "$RC"
