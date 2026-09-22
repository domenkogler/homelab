#!/usr/bin/env bash
# =====================================================================
# seed-runner-ssh.sh — make a Debian control node able to USE the jump the inventory
# already carries (HD-407).
#
# WHY THIS EXISTS. `ansible_ssh_common_args: "-o ProxyJump=vps"` lives in
# group_vars/{home_servers,storage,raspberry_pi,spark}.yml, so the jump travels in the
# inventory and a runner needs no `-e` and no laptop hack (HD-397). But OpenSSH resolves the
# jump NAME `vps` in the runner's OWN ~/.ssh/config — on a fresh control node that block does
# not exist, so every behind-NAT target fails before the first task runs. This script writes
# exactly that one block and nothing else.
#
# It deliberately does NOT rebuild the laptop's alias contract: docs/network-vpn.md
# §The laptop alias contract is the SSOT for the human aliases and belongs to the workstation,
# and a runner does not need the per-host blocks — Ansible types the inventory address and the
# group var supplies the jump (network-vpn.md §Traps, point 2). The `Host <ip>` blocks on the
# laptop are for scp/rsync/humans, "useful, not load-bearing".
#
# Idempotent (marker-guarded, never overwrites a config that already names the jump), TOFU for
# the jump's host key (prints the fingerprint — never key material), and it FAILS LOUD if the
# jump does not authenticate: a half-seeded runner is worse than none.
#
# Usage (on the machine that will run playbooks):
#   bash scripts/seed-runner-ssh.sh            # write the block + prove the jump
#   bash scripts/seed-runner-ssh.sh --check    # report only, write nothing
# =====================================================================
set -euo pipefail

JUMP_HOST="${RUNNER_JUMP_HOST:-vps}"
JUMP_ADDR="${RUNNER_JUMP_ADDR:-vps.kogler.si}"   # name, never an IP literal: split-horizon answers it
JUMP_USER="${RUNNER_JUMP_USER:-ansible-admin}"
KEY="${RUNNER_IDENTITY:-$HOME/.ssh/id_ed25519}"
CFG="$HOME/.ssh/config"
MARKER_START="# >>> seed-runner-ssh: $JUMP_HOST jump (HD-407) >>>"
MARKER_END="# <<< seed-runner-ssh: $JUMP_HOST jump (HD-407) <<<"

# The block. IdentityFile + IdentitiesOnly because hosts run `maxauthtries 3` (HD-154):
# offering the wrong key three times is an auth failure with a non-auth cause.
#
# AddressFamily inet is NOT decoration (measured on oldsrv, 2026-09-22): `vps.kogler.si` carries
# an AAAA and a dual-stack control node puts it FIRST, while TCP/22 to the VPS over IPv6 times out
# (`ssh -4 vps` OK, `ssh -6 vps` timeout, both deterministic). Every `-o ProxyJump=vps` leg from the
# box then dies with `Connection timed out during banner exchange / Connection to UNKNOWN port 65535
# timed out` — including the run against the runner's OWN address, which reads like a dead host and
# is not. The laptop never sees this because it has no IPv6 at all. The real defect (VPS-side IPv6,
# and its `ip protocol icmp` rule which is IPv4-only so ICMPv6 is dropped whole) is NOT this file:
# see todo HD-407's tail + deployment-ansible.md §Runner placement.
block() {
    cat <<EOF
$MARKER_START
Host $JUMP_HOST
  HostName $JUMP_ADDR
  User $JUMP_USER
  IdentityFile $KEY
  IdentitiesOnly yes
  AddressFamily inet
# <<< seed-runner-ssh: $JUMP_HOST jump (HD-407) <<<
EOF
}

CHECK_ONLY=0
case "${1:-}" in
    "")        ;;
    --check)   CHECK_ONLY=1 ;;
    *) echo "FAIL: unknown argument '$1' (only --check is accepted)" >&2; exit 2 ;;
esac
if [ $# -gt 1 ]; then
    echo "FAIL: expected at most one argument, got $# — refusing to guess" >&2
    exit 2
fi

umask 077
mkdir -p "$HOME/.ssh"

if [ -f "$CFG" ] && grep -qF "$MARKER_START" "$CFG"; then
    # Our own block, from an earlier run. A stale block must not silently keep a broken jump
    # (the AddressFamily line below was added after the first oldsrv seed proved why), so a block
    # that is missing it is REPLACED in place — never blindly trusted because it exists.
    if sed -n "/$(printf '%s' "$MARKER_START" | sed 's/[]\/[.*^$]/\\&/g')/,/$(printf '%s' "$MARKER_END" | sed 's/[]\/[.*^$]/\\&/g')/p" "$CFG" | grep -q "AddressFamily"; then
        echo "already seeded and current: $CFG names Host $JUMP_HOST with AddressFamily pinned"
    elif [ "$CHECK_ONLY" = "1" ]; then
        echo "STALE: our Host $JUMP_HOST block predates the AddressFamily pin (run without --check to replace it)"
        exit 1
    else
        cp -p "$CFG" "$CFG.pre-seed-$(date +%Y%m%d-%H%M%S)"
        awk -v s="$MARKER_START" -v e="$MARKER_END" '
            $0 == s { inside = 1; next }
            $0 == e  { inside = 0; next }
            !inside  { print }
        ' "$CFG" > "$CFG.awk.tmp"
        { printf '\n'; block; } >> "$CFG.awk.tmp"
        mv "$CFG.awk.tmp" "$CFG"
        chmod 600 "$CFG"
        echo "replaced our Host $JUMP_HOST block in $CFG (backup kept beside it)"
    fi
elif [ -f "$CFG" ] && grep -qE "^Host $JUMP_HOST([ \$]|$)" "$CFG"; then
    # A block somebody else authored (the laptop's alias contract). Never rewrite a human's file.
    echo "already present (not authored here): $CFG names Host $JUMP_HOST — left alone"
elif [ "$CHECK_ONLY" = "1" ]; then
    echo "MISSING: $CFG has no Host $JUMP_HOST block (run without --check to write it)"
    exit 1
else
    if [ -f "$CFG" ]; then
        cp -p "$CFG" "$CFG.pre-seed-$(date +%Y%m%d-%H%M%S)"
    fi
    # Append, never rewrite: a human's other blocks survive.
    { printf '\n'; block; } >> "$CFG"
    chmod 600 "$CFG"
    echo "wrote the $JUMP_HOST jump block into $CFG (mode $(stat -c %a "$CFG" 2>/dev/null || stat -f %Lp "$CFG"))"
fi

# TOFU host key. ssh in batch mode REFUSES an unknown host key, which would look like a dead
# jump; pin it now and print the fingerprint so it can be compared out-of-band.
if ! ssh-keygen -F "$JUMP_ADDR" >/dev/null 2>&1; then
    echo "pinning $JUMP_ADDR (TOFU):"
    ssh-keyscan -t ed25519 "$JUMP_ADDR" 2>/dev/null | tee /tmp/.seed-runner-known.$$ >> "$HOME/.ssh/known_hosts"
    ssh-keygen -lf /tmp/.seed-runner-known.$$ | sed 's/^/  /' || true
    rm -f /tmp/.seed-runner-known.$$
else
    echo "host key already present for $JUMP_ADDR"
fi

echo "-- proving the jump authenticates as $JUMP_USER@$JUMP_HOST (rc 0 is the proof):"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$JUMP_HOST" 'echo JUMP_OK; hostname'
