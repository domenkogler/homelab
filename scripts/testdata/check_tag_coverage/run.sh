#!/usr/bin/env bash
# =====================================================================
# run.sh — the tag-cascade lab behind scripts/gate/check_tag_coverage.py (HD-1149)
#
# The static gate reasons about tags; this fixture PROVES the four rules it reasons with, by asking
# ansible itself. Each leg is one `ansible-playbook -i localhost, -c local` over debug-only tasks in
# ./IaC/ansible and one assertion about which `debug` messages appear. Nothing here can touch a
# managed host: the inventory is the literal `localhost`, the connection is `local`, and every task
# is `debug`.
#
# Why the lab ships with the gate: the four rules are counter-intuitive enough that nobody should
# have to re-derive them from the Ansible source the next time a filtered converge reads `failed=0`
# while shipping nothing — which is exactly the HD-1149 class. A verdict you can re-run in ten
# seconds is worth more than a paragraph that asserts it.
#
# Usage:  bash scripts/testdata/check_tag_coverage/run.sh
# Exit:   0 = the four rules hold as documented (or SKIP: no functional ansible-playbook),
#         1 = ansible disagreed with the documented rule anywhere.
# =====================================================================
set -uo pipefail

FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PB="$FIXTURE_DIR/IaC/ansible/playbooks/lab.yml"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export ANSIBLE_CONFIG="$FIXTURE_DIR/ansible.cfg"
export ANSIBLE_ROLES_PATH="$FIXTURE_DIR/IaC/ansible/roles"
export ANSIBLE_LOCALHOST_WARNING=False
unset ANSIBLE_INVENTORY

# Probe AFTER the env is set: `--syntax-check` resolves the roles, so probing first would report a
# missing role path as "no ansible here" and SKIP the lab into silence.
if ! command -v ansible-playbook >/dev/null 2>&1 || ! ansible-playbook --syntax-check -i localhost, -c local "$PB" >/dev/null 2>&1; then
    echo "SKIP: ansible-playbook not functional on this host — the tag-cascade lab needs it"
    rm -rf "$WORK"
    exit 0
fi

fails=0
checks=0

# leg <label> <want-present-msg|-> <want-absent-msg|-> [extra ansible args...]
leg() {
    local label="$1" want="$2" absent="$3"; shift 3
    local out rc
    out="$(ANSIBLE_FORCE_COLOR=0 ansible-playbook -i localhost, -c local ${@+"$@"} "$PB" 2>&1)"; rc=$?
    checks=$((checks + 1))
    if [ "$rc" -ne 0 ]; then
        echo "FAIL: $label — ansible-playbook exited $rc" >&2
        printf '%s\n' "$out" | tail -15 >&2
        fails=$((fails + 1)); return
    fi
    if [ "$want" != "-" ] && ! printf '%s' "$out" | grep -q "msg.*$want"; then
        echo "FAIL: $label — expected to see '$want' run, it did not" >&2
        printf '%s\n' "$out" | grep -E "TASK|msg|RECAP" | head -20 >&2
        fails=$((fails + 1)); return
    fi
    if [ "$absent" != "-" ] && printf '%s' "$out" | grep -q "msg.*$absent"; then
        echo "FAIL: $label — '$absent' ran, and the rule says it must not" >&2
        printf '%s\n' "$out" | grep -E "TASK|msg" | head -20 >&2
        fails=$((fails + 1)); return
    fi
    printf '  ok  %-58s %s\n' "$label" "$([ "$want" != "-" ] && echo "ran: $want" || true)$([ "$absent" != "-" ] && echo "  absent: $absent" || true)"
}

echo "-- the four cascade rules, asked of ansible itself (HD-1149) --"
# Rule 1: the role-level tag reaches an untagged child through an untagged dynamic include.
leg "rule 1  --tags rule1  reaches an untagged child"   rule1-sub   -            --tags rule1
# Rule 2: the include tag only opens the file; the untagged sibling is silently absent.
leg "rule 2  --tags rule2  loads the file, drops the untagged child" rule2-tagged rule2-untagged --tags rule2
# Rule 2 control: with no filter both children run, so the absence above is the filter's doing.
leg "rule 2  unfiltered runs both children"             rule2-untagged -
# Rule 3: `always` rescues a parsed task and cannot rescue one below an untagged include.
leg "rule 3  --tags always runs a top-level always, not one below" rule3-top-always rule3-sub-always --tags always
# Rule 3 again: any other filter leaves the whole untagged include unexpanded.
leg "rule 3  --tags rule1 leaves the untagged include unexpanded" - rule3-sub-always --tags rule1
# Rule 4: a static import inherits the role tag, so its untagged child needs none.
leg "rule 4  --tags rule4 runs an untagged child of an import" rule4-static -        --tags rule4
# Rule B: the child's own tag never opens the file, so that tag alone converges nothing — green.
leg "rule B  --tags subtopic silently runs nothing"     -           topic-child    --tags subtopic
# ...and the compound filter is what actually reaches it, which is the fix the gate asks for.
leg "rule B  --tags topic,subtopic reaches the child"   topic-child -              --tags topic,subtopic

if [ "$fails" -ne 0 ]; then
    echo "FAIL: $fails/$checks lab legs disagree with the documented rules" >&2
    exit 1
fi
echo "OK: the four cascade rules hold as scripts/gate/check_tag_coverage.py documents them ($checks legs)"
