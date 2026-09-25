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
# THE POST-CONVERGE PROBE IS NOT `Running` (HD-436, 2026-09-25): the first version
#   of step 5 read `.State.Running` once and called the service alive. That is not
#   liveness. A container whose process exits on every start under `restart:
#   unless-stopped` reports `Running=true` in the window BETWEEN crashes, so a
#   crash loop passes a one-shot inspect — and the exact HD-436 hazard is that
#   shape: in the pinned headscale, `dns.extra_records` and `dns.extra_records_path`
#   are mutually exclusive, so setting both makes the process exit at startup. The
#   probe therefore samples repeatedly and requires three things of EVERY sample:
#     * `.State.Running` = true,
#     * `.RestartCount` not increasing across samples (the crash-loop signature),
#     * no health status of unhealthy/exited/dead,
#   plus, when `--probe` is given, an app-level command that must succeed on the
#   target every sample (for headscale: `curl -fsS localhost:8080/`). A service
#   that answers HTTP is alive; a service that is merely "running" is a claim.
#   Run `bash scripts/guarded-converge.sh --self-test` to see the verdict logic
#   refuse the crash-loop fixture — a probe that cannot fail is not evidence.
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
#        --playbook playbooks/vps.yml --limit vps --tags docker_services,headscale \
#        --probe 'curl -fsS localhost:8080/ >/dev/null'
#   bash scripts/guarded-converge.sh --self-test   # exercises the verdict logic
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
PROBE=""
SAMPLES=""
SAMPLE_INTERVAL=""
SELF_TEST=0
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
        --probe)       PROBE="${2:-}"; shift 2 ;;
        --samples)     SAMPLES="${2:-}"; shift 2 ;;
        --sample-interval) SAMPLE_INTERVAL="${2:-}"; shift 2 ;;
        --self-test)   SELF_TEST=1; shift ;;
        --foreground)  FOREGROUND=1; shift ;;
        -h|--help)     sed -n '2,62p' "$0"; exit 0 ;;
        *) echo "FAIL: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

[ "$ACTION" = "converge" ] || [ "$ACTION" = "prove" ] || { echo "FAIL: --action must be converge|prove" >&2; exit 2; }
if [ "$SELF_TEST" != 1 ]; then
    [ -n "$TARGET" ]    || { echo "FAIL: --target <ssh alias of the host running the service>" >&2; exit 2; }
    [ -n "$CONTAINER" ] || { echo "FAIL: --container <container name>" >&2; exit 2; }
fi
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
# The liveness probe is a WINDOW, not a glance: six samples ten seconds apart are
# what catches a container that restarts itself every few seconds. Overridable for
# services with a genuinely slow boot.
SAMPLES=${SAMPLES:-6}; SAMPLE_INTERVAL=${SAMPLE_INTERVAL:-10}
WATCHDOG="${REPO}/scripts/restart-watchdog.sh"
REMOTE_WATCHDOG="${REMOTE_DIR}/restart-watchdog.sh"
DISARM="${REMOTE_DIR}/${CONTAINER}.disarm"
WD_LOG="/tmp/${CONTAINER}-watchdog.log"
COMPOSE="${PROJECT}/docker-compose.yml"

log() { printf '%s guarded-converge[%s]: %s\n' "$(date -u +%H:%M:%S)" "$ACTION" "$*"; }
die() { log "FAIL: $*"; exit 1; }
bring_up() { ssh -o BatchMode=yes "$TARGET" docker compose -f "$COMPOSE" up -d; }

# ---- the liveness verdict (pure logic — self-testable, no ssh, no docker) ----
# stdin: one line per sample, "<running> <started> <restartcount> <health> [<probe_rc>]"
# prints the verdict reason on stdout; exit 0 = alive, 1 = NOT alive.
liveness_verdict() {
    local running started restarts health probe_rc prev=-1 first="" n=0 bad=""
    while read -r running started restarts health probe_rc; do
        [ -n "${running:-}" ] || continue
        n=$((n + 1))
        [ "$running" = "true" ] || bad="${bad} not-running@${n}"
        case "${health:-none}" in
            unhealthy|exited|dead) bad="${bad} health=${health}@${n}" ;;
        esac
        [ -n "$first" ] || first="${restarts:-0}"
        if [ "$prev" -ge 0 ] && [ "${restarts:-0}" -gt "$prev" ]; then
            bad="${bad} restartcount-was-climbing ${prev}->${restarts}@${n}"
        fi
        prev="${restarts:-0}"
        [ -z "${probe_rc:-}" ] || [ "$probe_rc" = "0" ] || bad="${bad} app-probe rc=${probe_rc}@${n}"
    done
    [ "$n" -gt 0 ] || { echo "no samples read — the probe measured nothing"; return 1; }
    [ -z "$bad" ] || { echo "liveness defects:${bad}"; return 1; }
    echo "samples=${n} restartcount=${first} stable"
    return 0
}

# One sample of live state. The probe runs on the TARGET and only its exit code
# comes back — never a value, never a log line (CONVENTIONS: no secret printing).
read_state() {
    local insp prc
    insp="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" \
        "docker inspect -f '{{.State.Running}} {{.State.StartedAt}} {{.RestartCount}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' ${CONTAINER} 2>/dev/null" \
        2>/dev/null || true)"
    [ -n "$insp" ] || { echo "false absent 0 none"; return 1; }
    prc=""
    if [ -n "$PROBE" ]; then
        ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" "$PROBE" >/dev/null 2>&1
        prc=$?
    fi
    echo "${insp} ${prc}"
}

# ---- self-test: the verdict must refuse a crash loop, not just accept health --
if [ "$SELF_TEST" = 1 ]; then
    fails=0
    check() { # check <name> <expected: green|red> <lines...>
        local name=$1 want=$2; shift 2
        local out rc
        out=$(printf '%s\n' "$@" | liveness_verdict); rc=$?
        if { [ "$want" = green ] && [ $rc -eq 0 ]; } || { [ "$want" = red ] && [ $rc -ne 0 ]; }; then
            echo "self-test ok: ${name} → ${want} (${out})"
        else
            echo "self-test FAIL: ${name} expected ${want}, got rc=${rc} (${out})"; fails=$((fails + 1))
        fi
    }
    check healthy-flat       green \
        'true 2026-09-25T09:00:00Z 0 healthy' \
        'true 2026-09-25T09:00:00Z 0 healthy' \
        'true 2026-09-25T09:00:00Z 0 healthy'
    check crash-loop         red \
        'true 2026-09-25T09:00:00Z 0 none' \
        'true 2026-09-25T09:00:11Z 1 none' \
        'true 2026-09-25T09:00:22Z 2 none'
    check both-extra-records red \
        'true 2026-09-25T09:00:00Z 0 none 1' \
        'true 2026-09-25T09:00:11Z 0 none 1'
    check down               red 'false 2026-09-25T09:00:00Z 3 none'
    check unhealthy          red 'true 2026-09-25T09:00:00Z 0 unhealthy'
    check empty-input        red ''
    # The fixture that makes an empty verdict provably impossible:
    check single-true-sample green 'true 2026-09-25T09:00:00Z 0 none'
    [ "$fails" = 0 ] || { echo "SELFTEST RED: ${fails} case(s)"; exit 1; }
    echo "SELFTEST OK: the verdict accepts liveness and refuses the crash-loop shape"
    exit 0
fi

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
# ---- 5. SAMPLED liveness, not a glance (see the header note) -----------------
log "post-converge probe: ${SAMPLES} samples x ${SAMPLE_INTERVAL}s — Running AND flat RestartCount AND health${PROBE:+ AND app probe}"
SAMPLES_TXT=""
for i in $(seq 1 "$SAMPLES"); do
    s="$(read_state)"; log "sample ${i}/${SAMPLES}: ${s}"
    SAMPLES_TXT+="${s}"$'\n'
    [ "$i" -lt "$SAMPLES" ] && sleep "$SAMPLE_INTERVAL"
done
VERDICT="$(printf '%s' "$SAMPLES_TXT" | liveness_verdict)"; VRC=$?
log "verdict: ${VERDICT}"
if [ "$VRC" -eq 0 ]; then
    ssh "$TARGET" "bash ${REMOTE_WATCHDOG} disarm --disarm ${DISARM}" || log "WARN: could not write the disarm marker"
    log "RESULT: GREEN — ${CONTAINER} is alive across ${SAMPLES} samples and the watchdog is disarmed"
else
    log "RESULT: RED — ${CONTAINER} is NOT provably alive (${VERDICT})."
    log "The watchdog is still ARMED and will re-enable it; live log: ssh ${TARGET} tail -40 ${WD_LOG}"
    [ "$RC" = 0 ] && RC=1
fi
exit "$RC"
