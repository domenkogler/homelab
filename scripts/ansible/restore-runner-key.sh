#!/usr/bin/env bash
# =====================================================================
# restore-runner-key.sh — restore the vault-canonical ansible-admin_ssh key INTO
# ANY runner's ~/.ssh/ansible-admin_ssh[.pub] (1Password = source of truth).
#
# THE TARGET IS THE CANONICAL NAME, NOT SSH'S DEFAULT PATH. The installer never
# writes ~/.ssh/id_ed25519: that path is the superseded NAME the retirement list
# retires (docs/network-vpn.md §The Win11 `~/.ssh` retirement list, step 6), and a
# runner's legs resolve their identity from the alias-plane blocks — seeded at
# Phase 0 by bootstrap-runner.sh via scripts/harness/seed-seat-ssh-config.sh —
# which name this file (§The runner's alias plane). On a box whose default path
# already holds this same key, this script PLACES the canonical pair beside it and
# touches nothing else — the default-path copy retires with its own per-seat
# rename, not from here.
#
# Run AFTER bootstrap-runner.sh (and after any true-zero rebuild, deployment-tasks
# Phase 0): bootstrap-runner.sh generates a THROWAWAY key at the default path,
# which no managed host authorizes and which the blocks never name. Needs only the
# read-scope SA token file, so it works on a headless runner (oldsrv, HD-407)
# exactly as on the laptop. Verifies the pair is consistent, prints the path it
# installed at and the fingerprint — the public half only, never the private
# (CONVENTIONS §6).
#
# Expected fingerprint: SHA256:1uKzmwf… — a mismatch means the vault rotated: re-check
# the item rather than shipping a key nothing authorizes.
#
# It will NOT quietly replace a key that is already at the canonical path. What a
# long-lived box taught this rule (HD-407 prep): the file under the OLD target on
# oldsrv was not the throwaway but a hand-made `oldsrv-rsync` key with no vault
# item and no IaC reference — something on the OTHER end of an ssh/rsync may
# authorize exactly such a key and nothing in this repo would notice its absence
# until a backup silently stopped arriving. Replacing a differing key is a
# deliberate act, so it takes a flag:
#   --force-throwaway   the existing key at the canonical path is this script's own
#                       earlier install or a hand-moved throwaway (the Phase-0 /
#                       true-zero case): replace it, keeping a timestamped backup
#                       of what was there.
# Without the flag an existing, differing key is a REFUSAL with both fingerprints
# printed, so the operator can identify it before anything moves.
#
# Usage (any Debian runner):
#   bash scripts/ansible/restore-runner-key.sh [ --force-throwaway ]
# =====================================================================
set -euo pipefail

# The credential comes from the ONE rule (lib/vault-env.sh) rather than from a sourced file: this leg
# WRITES a vault value, so it must know which credential answered — an env token left over from an
# earlier window is the write-scoped one, and a silent file fallback would not say which it used.
# Sourced by name, upward, bounded — this script never sources repo-root.sh (it has its own root
# semantics), and vault-env.sh brings the rest of the lib with it. Parameter expansion rather than
# `dirname` so a trimmed PATH cannot spin the walk (CONVENTIONS §6).
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ -n "$_hl_d" ] && [ "$_hl_d" != / ] && [ ! -f "$_hl_d/lib/vault-env.sh" ]; do
  _hl_n="${_hl_d%/*}"; [ "$_hl_n" = "$_hl_d" ] && _hl_n="/"; _hl_d="$_hl_n"
done
# shellcheck source=/dev/null
. "$_hl_d/lib/vault-env.sh"
hl_vault_env || {
    echo "FAIL: no vault credential reachable on this seat — $(hl_vault_verdict)." >&2
    echo "      run scripts/ansible/bootstrap-runner.sh first." >&2
    exit 1
}
[ -d "$HOME/.config/op" ] && chmod 700 "$HOME/.config/op"   # op refuses world-accessible config dirs

FORCE=0
case "${1:-}" in
    "")            ;;
    --force-throwaway) FORCE=1 ;;
    *) echo "FAIL: unknown argument '$1' — refusing to guess (see --help shape above)" >&2; exit 2 ;;
esac

umask 077
mkdir -p "$HOME/.ssh"
# The canonical name (docs/network-vpn.md §Canonical identity file names). SSH's default path is
# deliberately NOT a target — installing the fleet key there is what kept the retirement rename
# blocked (§The runner's alias plane).
PRV="$HOME/.ssh/ansible-admin_ssh"
PUB="$HOME/.ssh/ansible-admin_ssh.pub"

# --- refuse to destroy a key someone else may depend on -------------------------------
# Fingerprints only (public half), never key material (CONVENTIONS §6).
if [ -f "$PRV" ]; then
    [ -f "$PUB" ] || ssh-keygen -y -f "$PRV" > "$PUB"
    EXISTING_FP="$(ssh-keygen -lf "$PUB" | awk '{print $2}')"
    EXISTING_CMT="$(ssh-keygen -lf "$PUB" | awk '{print $NF}')"
else
    EXISTING_FP=""
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
op read "op://Homelab-ansible/ansible-admin_ssh/private_key" > "$TMP/id_ed25519"
op read "op://Homelab-ansible/ansible-admin_ssh/public_key"  > "$TMP/id_ed25519.pub"
VAULT_FP="$(ssh-keygen -lf "$TMP/id_ed25519.pub" | awk '{print $2}')"

if [ -n "$EXISTING_FP" ] && [ "$EXISTING_FP" = "$VAULT_FP" ]; then
    echo "already canonical: $EXISTING_FP ($EXISTING_CMT) at $PRV — nothing to do"
    exit 0
fi

if [ -n "$EXISTING_FP" ] && [ "$FORCE" -eq 0 ]; then
    echo "FAIL: $PRV already holds a DIFFERENT key — refusing to overwrite it." >&2
    echo "      on this runner: $EXISTING_FP $EXISTING_CMT" >&2
    echo "      vault canonical: $VAULT_FP" >&2
    echo "      If that key is bootstrap-runner.sh's throwaway (the Phase-0 rebuild case)," >&2
    echo "      re-run with --force-throwaway (a timestamped backup is kept either way)." >&2
    echo "      If you cannot name it: STOP. Something on the far end of an ssh/rsync may" >&2
    echo "      authorize it, and it is in no vault — find out before it disappears." >&2
    exit 1
fi

if [ -n "$EXISTING_FP" ]; then
    STAMP="$(date +%Y%m%d-%H%M%S)"
    mv "$PRV" "$PRV.pre-restore-$STAMP"
    mv "$PUB" "$PUB.pre-restore-$STAMP"
    chmod 600 "$PRV.pre-restore-$STAMP"
    echo "kept the displaced key: $(basename "$PRV").pre-restore-$STAMP  ($EXISTING_FP $EXISTING_CMT)"
    echo "NOTICE: if that fingerprint is authorized anywhere (nas? storage box?), the job"
    echo "        that uses it now fails — re-point it deliberately, do not re-run this script."
fi

cp "$TMP/id_ed25519"     "$PRV"
cp "$TMP/id_ed25519.pub" "$PUB"
chmod 600 "$PRV"
chmod 644 "$PUB"

# pair-consistency + fingerprint evidence
if ssh-keygen -y -f "$PRV" | awk '{print $1" "$2}' | \
   diff -q - <(awk '{print $1" "$2}' "$PUB") >/dev/null; then
    echo "pair-consistent: yes"
else
    echo "FAIL: private/public mismatch" >&2
    exit 1
fi
echo "-- installed at $PRV (+ .pub) — the canonical name; ssh's default path (~/.ssh/id_ed25519) was NOT written"
echo "-- installed fingerprint (expect SHA256:1uKzmwfO8ljfYMX+nOuFPqFlxzGMF4LZa/0kZCdz7rU):"
ssh-keygen -lf "$PUB"
