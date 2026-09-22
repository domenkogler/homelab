#!/usr/bin/env bash
# =====================================================================
# restart-watchdog.sh — an INDEPENDENT timed re-enable for one docker
#   compose service, disarmed by a marker file. HD-415.
#
# WHY THIS EXISTS (owner safety condition, 2026-09-22):
#   Landing a headscale config/policy change is a stop/start of the tailnet
#   control plane, and every tailnet device's remote path depends on that
#   control plane being up. A driving session that dies mid-restart (SSH drop,
#   laptop sleep, killed ansible) must NOT be able to leave the control plane
#   down. The converge wrapper's `trap` is only half the answer: a trap does not
#   run if the shell running it is SIGKILLed. So the recovery is a SECOND,
#   independent mechanism: this watchdog runs on the TARGET host, detached, with
#   no controlling terminal and no dependency on the session that armed it.
#
# Contract:
#   * arm     = "if this service is not running by <grace> and stays down for
#              <consecutive> checks inside the <window>, bring it up with
#              `docker compose up -d`" — it NEVER brings anything down.
#   * disarm  = write the marker file; the watchdog sees it at its next check and
#              takes no further action. Explicit, on-purpose action only.
#   * status  = report the marker, no side effects.
#   * self-test = prove BOTH branches (auto-re-enable fires when down, marker
#              stops it) against a stubbed docker. Run it before trusting the net.
#
# It always exits 0: a rescue net that can fail loudly is still a rescue net, but
# it must never be the thing that breaks a converge's exit status.
#
# Usage (normally on the target host, detached by guarded-converge.sh):
#   setsid nohup bash restart-watchdog.sh arm \
#       --container headscale --project /opt/headscale \
#       --grace 240 --window 900 --interval 10 --consecutive 3 \
#       --disarm /tmp/headscale-watchdog.disarm >/tmp/headscale-watchdog.log 2>&1 &
#   bash restart-watchdog.sh disarm --disarm /tmp/headscale-watchdog.disarm
#   bash restart-watchdog.sh self-test
# =====================================================================
set -uo pipefail

CONTAINER=""
PROJECT=""
GRACE=240
WINDOW=900
INTERVAL=10
CONSECUTIVE=3
DISARM="/tmp/restart-watchdog.disarm"
COMPOSE_FILE=""

say() { printf '%s restart-watchdog: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

need_target() {
    [ -n "$CONTAINER" ] || { echo "FAIL: --container <name> required" >&2; exit 2; }
    if [ -z "$PROJECT" ]; then
        PROJECT="/opt/${CONTAINER}"
    fi
    [ -n "$COMPOSE_FILE" ] || COMPOSE_FILE="${PROJECT}/docker-compose.yml"
    if [ ! -f "$COMPOSE_FILE" ]; then
        # Fail loud at ARM time, not at rescue time: a watchdog pointed at a
        # compose file that does not exist is not a safety net.
        echo "FAIL: compose file '$COMPOSE_FILE' not found (set --project or --compose-file)" >&2
        exit 2
    fi
}

running() {
    # Anything other than a clean "true" (missing container, daemon hiccup) counts
    # as down — the recovery command `docker compose up -d` is idempotent, so a
    # false "down" reading costs one no-op call, a false "up" reading costs the net.
    [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ]
}

bring_up() {
    say "RE-ENABLING: docker compose -f ${COMPOSE_FILE} up -d"
    if docker compose -f "$COMPOSE_FILE" up -d 2>&1; then
        say "re-enable command returned 0"
    else
        say "re-enable command FAILED (rc=$?) — the net fired, the service is still down"
    fi
}

cmd_arm() {
    local waited=0 down=0
    say "armed: container=${CONTAINER} compose=${COMPOSE_FILE} grace=${GRACE}s window=${WINDOW}s interval=${INTERVAL}s consecutive=${CONSECUTIVE} disarm=${DISARM} pid=$$"
    while [ "$waited" -lt "$GRACE" ]; do
        if [ -e "$DISARM" ]; then say "disarm marker present during grace — taking no action, exiting"; return 0; fi
        sleep "$INTERVAL"
        waited=$((waited + INTERVAL))
    done
    local elapsed=0
    say "window open"
    while [ "$elapsed" -lt "$WINDOW" ]; do
        if [ -e "$DISARM" ]; then say "disarm marker present at +${elapsed}s — standing down, no action"; return 0; fi
        if running; then
            down=0
        else
            down=$((down + 1))
            say "not running (miss ${down}/${CONSECUTIVE}) at +${elapsed}s into the window"
            if [ "$down" -ge "$CONSECUTIVE" ]; then
                bring_up
                down=0
            fi
        fi
        sleep "$INTERVAL"
        elapsed=$((elapsed + INTERVAL))
    done
    say "window expired after ${WINDOW}s — exiting (service was: $(running && echo up || echo 'down at expiry'))"
    return 0
}

cmd_disarm() {
    : > "$DISARM" 2>/dev/null || { echo "FAIL: cannot write disarm marker '$DISARM'" >&2; return 2; }
    say "disarm marker written at ${DISARM}"
    return 0
}

cmd_status() {
    if [ -e "$DISARM" ]; then
        say "status: DISARMED (marker ${DISARM} exists)"
    else
        say "status: ARMED (no marker at ${DISARM})"
    fi
    return 0
}

# ---------------------------------------------------------------------
# self-test: a stubbed `docker` in a private PATH, driven by a state file.
# Proves the two branches that matter. Without the consecutive-miss + marker
# logic in cmd_arm these assertions cannot both hold, so the test can fail.
# ---------------------------------------------------------------------
cmd_self_test() {
    local tmp rc=0
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT
    mkdir -p "$tmp/bin"
    printf 'down\n' > "$tmp/state"
    cat > "$tmp/bin/docker" <<STUB
#!/usr/bin/env bash
case "\$1" in
  inspect) [ "\$(cat '$tmp/state')" = "up" ] && echo true || echo false ;;
  compose) printf 'compose-up-called\n' >> '$tmp/calls' ;;
esac
exit 0
STUB
    chmod +x "$tmp/bin/docker"
    : > "$tmp/docker-compose.yml"
    export PATH="$tmp/bin:$PATH"

    # Case A: service stays down -> the watchdog MUST run compose up.
    : > "$tmp/calls"
    CONTAINER=x PROJECT="$tmp" COMPOSE_FILE="$tmp/docker-compose.yml" \
      GRACE=1 WINDOW=4 INTERVAL=1 CONSECUTIVE=2 DISARM="$tmp/nope" cmd_arm >/dev/null 2>&1
    if [ -s "$tmp/calls" ]; then
        say "self-test A PASS: down service was re-enabled ($(wc -l < "$tmp/calls" | tr -d ' ') compose call(s))"
    else
        say "self-test A FAIL: service was down and nothing was re-enabled"
        rc=1
    fi

    # Case B: the real sequence — armed first, disarmed DURING the window.
    # This is the branch that carries the authorization, so it is timed off the
    # watchdog's own "window open" line (no sub-second races) and is run with
    # CONSECUTIVE=2: if the in-window marker check were missing, the watchdog
    # would fire before the test could be accused of winning a race.
    : > "$tmp/calls"
    CONTAINER=x PROJECT="$tmp" COMPOSE_FILE="$tmp/docker-compose.yml" \
      GRACE=1 WINDOW=8 INTERVAL=2 CONSECUTIVE=2 DISARM="$tmp/disarmed" \
      cmd_arm > "$tmp/b.log" 2>&1 &
    local bpid=$! waited=0
    while [ "$waited" -lt 20 ] && ! grep -q 'window open' "$tmp/b.log" 2>/dev/null; do
        sleep 0.5; waited=$((waited + 1))
    done
    : > "$tmp/disarmed"
    wait "$bpid" 2>/dev/null
    if [ -s "$tmp/calls" ]; then
        say "self-test B FAIL: the disarm marker did not stop the watchdog mid-window"
        rc=1
    elif grep -q 'standing down' "$tmp/b.log"; then
        say "self-test B PASS: disarm marker honoured mid-window, no action taken"
    else
        say "self-test B FAIL: the watchdog never reached the disarm branch (log below)"
        sed 's/^/    /' "$tmp/b.log"
        rc=1
    fi

    # Case C: disarm marker already present at arm time -> stands down in the grace
    # phase and never even opens the recovery window (the timing assertion is what
    # makes this case distinct from B: without the grace-phase check the watchdog
    # would still end up standing down, one interval later, via the window branch).
    : > "$tmp/calls"
    : > "$tmp/disarmed"
    CONTAINER=x PROJECT="$tmp" COMPOSE_FILE="$tmp/docker-compose.yml" \
      GRACE=1 WINDOW=3 INTERVAL=1 CONSECUTIVE=1 DISARM="$tmp/disarmed" cmd_arm > "$tmp/c.log" 2>&1
    if [ -s "$tmp/calls" ]; then
        say "self-test C FAIL: an already-disarmed watchdog still acted"
        rc=1
    elif grep -q 'window open' "$tmp/c.log"; then
        say "self-test C FAIL: pre-existing marker did not stop it in the grace phase"
        rc=1
    else
        say "self-test C PASS: pre-existing disarm marker honoured before the window"
    fi

    # Case D: service up the whole time -> the watchdog MUST NOT act.
    : > "$tmp/calls"
    printf 'up\n' > "$tmp/state"
    CONTAINER=x PROJECT="$tmp" COMPOSE_FILE="$tmp/docker-compose.yml" \
      GRACE=1 WINDOW=4 INTERVAL=1 CONSECUTIVE=1 DISARM="$tmp/nope" cmd_arm >/dev/null 2>&1
    if [ -s "$tmp/calls" ]; then
        say "self-test D FAIL: watchdog restarted a service that was running"
        rc=1
    else
        say "self-test D PASS: a running service is left alone"
    fi

    [ "$rc" = 0 ] && say "self-test: GREEN" || say "self-test: RED"
    return "$rc"
}

usage() {
    sed -n '2,30p' "$0"
}

CMD="${1:-}"
shift || true
while [ $# -gt 0 ]; do
    case "$1" in
        --container)    CONTAINER="${2:-}"; shift 2 ;;
        --project)      PROJECT="${2:-}"; shift 2 ;;
        --compose-file) COMPOSE_FILE="${2:-}"; shift 2 ;;
        --grace)        GRACE="${2:-}"; shift 2 ;;
        --window)       WINDOW="${2:-}"; shift 2 ;;
        --interval)     INTERVAL="${2:-}"; shift 2 ;;
        --consecutive)  CONSECUTIVE="${2:-}"; shift 2 ;;
        --disarm)       DISARM="${2:-}"; shift 2 ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "FAIL: unknown argument '$1'" >&2; usage; exit 2 ;;
    esac
done

case "$CMD" in
    arm)     need_target; cmd_arm ;;
    disarm)  cmd_disarm ;;
    status)  cmd_status ;;
    self-test) cmd_self_test ;;
    *) usage; exit 2 ;;
esac
