#!/usr/bin/env bash
# =====================================================================
# restore-runner-key.sh — restore the canonical ansible-admin_ssh key into
# ANY runner's ~/.ssh/id_ed25519[.pub] (1Password = source of truth).
#
# Run AFTER bootstrap-runner.sh (and after any true-zero rebuild, deployment-tasks
# Phase 0): bootstrap-runner.sh generates a THROWAWAY key, which no managed host
# authorizes. Needs only the read-scope SA token file, so it works on a headless
# runner (oldsrv, HD-407) exactly as on the laptop. Verifies the pair is consistent
# and prints the fingerprint — the public half only, never the private (CONVENTIONS §6).
#
# Expected fingerprint: SHA256:1uKzmwf… — a mismatch means the vault rotated: re-check
# the item rather than shipping a key nothing authorizes.
#
# It will NOT quietly replace a key that is already there. On a runner that has been
# alive for a while, ~/.ssh/id_ed25519 is not necessarily the throwaway: measured on
# oldsrv (HD-407 prep, 2026-09-20) it held `oldsrv-rsync` — a hand-made key with no
# vault item and no IaC reference, i.e. something on the OTHER end of an ssh/rsync
# may authorize it and nothing in this repo would notice its absence until a backup
# silently stopped arriving. Replacing it is a deliberate act, so it takes a flag:
#   --force-throwaway   the existing key is bootstrap-runner.sh's throwaway (the
#                       Phase-0 / true-zero path): replace it, keeping a timestamped
#                       backup of what was there.
# Without the flag an existing, differing key is a REFUSAL with both fingerprints
# printed, so the operator can identify it before anything moves.
#
# Usage (any Debian runner):
#   bash scripts/restore-runner-key.sh [ --force-throwaway ]
# =====================================================================
set -euo pipefail

[ -f "$HOME/.config/op/homelab-sa-token" ] || {
    echo "FAIL: SA token file missing — run scripts/bootstrap-runner.sh first" >&2
    exit 1
}
chmod 700 "$HOME/.config/op"   # op refuses world-accessible config dirs
# shellcheck disable=SC1091
source "$HOME/.config/op/homelab-sa-token"

FORCE=0
case "${1:-}" in
    "")            ;;
    --force-throwaway) FORCE=1 ;;
    *) echo "FAIL: unknown argument '$1' — refusing to guess (see --help shape above)" >&2; exit 2 ;;
esac

umask 077
mkdir -p "$HOME/.ssh"
PRV="$HOME/.ssh/id_ed25519"
PUB="$HOME/.ssh/id_ed25519.pub"

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
    echo "already canonical: $EXISTING_FP ($EXISTING_CMT) — nothing to do"
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
echo "-- installed fingerprint (expect SHA256:1uKzmwfO8ljfYMX+nOuFPqFlxzGMF4LZa/0kZCdz7rU):"
ssh-keygen -lf "$PUB"
