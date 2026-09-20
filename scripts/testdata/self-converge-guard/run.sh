#!/usr/bin/env bash
# =====================================================================
# run.sh — HD-413 self-converge guard fixture (wired into validate-all.sh)
#
# Asserts the REFUSE/ALLOW matrix of
#   IaC/ansible/playbooks/tasks/self-converge-guard.yml
# against a throwaway inventory whose ONLY hosts are this machine (so the
# controller-vs-target condition is genuinely exercised) and a decoy that is not.
# The roles are inert debug stubs in ./roles — no managed host is contacted and
# nothing here can converge anything.
#
# Why a runtime fixture instead of a static lint: the static checker
# (scripts/check_self_converge_guard.py) proves the wiring is complete, but the
# first draft of the guard passed every static reading AND still allowed the
# unfiltered `ansible-run.sh playbooks/home_servers.yml` from the box itself, because
# `ansible_run_tags` is a TUPLE and `ansible_run_tags == ['all']` is silently always
# False. Only executing the expression catches that class. Both gates are load-bearing.
#
# Usage:  bash scripts/testdata/self-converge-guard/run.sh
# Exit:   0 = matrix as expected (or SKIP: no functional ansible-playbook / no uname),
#         1 = the guard disagreed with the expected verdict anywhere.
# =====================================================================
set -uo pipefail

FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v uname >/dev/null 2>&1; then
    echo "SKIP: uname not on PATH (native Windows) — self-converge guard fixture runs under WSL/CI"
    exit 0
fi
if ! command -v ansible-playbook >/dev/null 2>&1 || ! ansible-playbook --version >/dev/null 2>&1; then
    echo "SKIP: ansible-playbook not functional on this host — self-converge guard fixture runs under WSL/CI"
    exit 0
fi

SELF="$(uname -n)"
case "$SELF" in
    '') echo "FAIL: uname -n returned nothing — the fixture cannot name the controller" >&2; exit 1 ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# Host 1: this machine, reached locally -> controller == target.
# Host 2: a name that cannot be this machine -> controller != target (the off-box case).
DECOY="hd413-not-the-controller.invalid"
cat > "$WORK/hosts.ini" <<EOF
$SELF ansible_connection=local
$DECOY ansible_connection=local
EOF

export ANSIBLE_CONFIG="$FIXTURE_DIR/ansible.cfg"
export ANSIBLE_ROLES_PATH="$FIXTURE_DIR/roles"
export ANSIBLE_LOCALHOST_WARNING=False
unset ANSIBLE_INVENTORY

PB="$FIXTURE_DIR/fixture.yml"
INV="$WORK/hosts.ini"

fails=0
checks=0

# expect <REFUSE|ALLOW> <limit> [extra args...] [expect-no-dummy|expect-dummy]
expect() {
    local want="$1"; shift
    local limit="$1"; shift
    # Trailing marker: assert on whether the (inert) role tasks actually ran. Stripped
    # here so it never reaches ansible-playbook's argument parser.
    local want_dummy=""
    local args=("$@")
    local n=${#args[@]}
    if [ "$n" -gt 0 ]; then
        case "${args[n-1]}" in
            expect-no-dummy|expect-dummy)
                want_dummy="${args[n-1]}"
                unset 'args[n-1]'
                ;;
        esac
    fi

    local out rc
    out="$(ansible-playbook -i "$INV" "$PB" --limit "$limit" ${args[@]+"${args[@]}"} 2>&1)"
    rc=$?
    checks=$((checks + 1))

    local got="ALLOW"
    if printf '%s' "$out" | grep -q "SELF-CONVERGE GUARD"; then
        got="REFUSE"
    elif [ "$rc" -ne 0 ]; then
        echo "FAIL (harness): unexpected non-guard failure for: --limit $limit $*" >&2
        printf '%s\n' "$out" | tail -15 >&2
        fails=$((fails + 1))
        return
    fi

    local label="limit=$limit ${args[*]:-<no --tags>}"
    if [ "$got" != "$want" ]; then
        echo "FAIL: $label -> guard said $got, expected $want" >&2
        printf '%s\n' "$out" | grep -E "SELF-CONVERGE GUARD|fatal:|PLAY RECAP" | head -5 >&2
        fails=$((fails + 1))
        return
    fi

    if [ -n "$want_dummy" ]; then
        local n; n="$(printf '%s' "$out" | grep -c "DUMMY" || true)"
        if [ "$want_dummy" = "expect-no-dummy" ] && [ "$n" -ne 0 ]; then
            echo "FAIL: $label -> allowed, but $n lockout-role task(s) ran (expected none)" >&2
            fails=$((fails + 1)); return
        fi
        if [ "$want_dummy" = "expect-dummy" ] && [ "$n" -eq 0 ]; then
            echo "FAIL: $label -> allowed, but no role task ran at all (fixture is broken)" >&2
            fails=$((fails + 1)); return
        fi
    fi
    printf '  ok  %-46s %s\n' "$label" "$got"
}

echo "-- self-converge guard fixture (controller == target) --"
# The unfiltered case FIRST: it is the whole reason the guard exists, and the case the
# tuple bug let through.
expect REFUSE "$SELF"
expect REFUSE "$SELF" --tags network
expect REFUSE "$SELF" --tags netd
expect REFUSE "$SELF" --tags base
expect REFUSE "$SELF" --tags storage
expect REFUSE "$SELF" --tags untagged
expect REFUSE "$SELF" --tags wireguard
expect REFUSE "$SELF" --tags hardening
# vps-hardening really writes /etc/ssh/sshd_config under --check (check_mode: false), so
# the check-mode escape must NOT open for it.
expect REFUSE "$SELF" --tags hardening --check
# A full --check of a vps-hardening-bearing play is refused for the same reason: --check is
# not "read-only" when a task opts out of it (this is the `vps.yml --check` from the VPS case).
expect REFUSE "$SELF" --check
echo "-- self-converge guard fixture (legs that must stay open) --"
# HD-407 proves the oldsrv runner with --check legs; if these ever refuse, the guard has
# become the thing blocking the migration it protects.
expect ALLOW "$SELF" --tags network --check
expect ALLOW "$SELF" --tags storage --check
expect ALLOW "$SELF" --tags docker_services,pi-web expect-no-dummy

echo "-- self-converge guard fixture (off-box: controller != target) --"
expect ALLOW "$DECOY" expect-dummy
expect ALLOW "$DECOY" --tags network expect-dummy

if [ "$fails" -ne 0 ]; then
    echo "FAIL: $fails/$checks self-converge guard expectations not met" >&2
    exit 1
fi
echo "OK: self-converge guard verdict matrix holds ($checks cases)"
