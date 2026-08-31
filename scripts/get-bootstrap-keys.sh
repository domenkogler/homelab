#!/usr/bin/env bash
# =====================================================================
# get-bootstrap-keys.sh — materialize the two MikroTik bootstrap .pub files
# ---------------------------------------------------------------------
# The render-routeros.yml templates import two SSH public keys on every
# device during the Phase 1.5 network-redo reset:
#
#   /user ssh-keys import public-key-file=admin.pub   user=admin     (human)     RB4011
#   /user ssh-keys import public-key-file=ansible.pub user=ansible   (Ansible)   RB4011
#   /user ssh-keys import public-key-file=flash/admin.pub   user=admin     (human)     CRS328 + APs
#   /user ssh-keys import public-key-file=flash/ansible.pub user=ansible   (Ansible)   CRS328 + APs
#
# FLASH-PERSISTENCE (HD-304): on the switch + APs the .pub files MUST be placed in
# the device's flash/ folder — files in the root are WIPED on reboot, and the
# /user ssh-keys import runs post-reset from flash/. The RB4011 boots off flash
# and is immune, so its .pub files stay in root.
#
# Canonical store = 1Password vault "Homelab-ansible":
#   admin.pub   ← item "laptop-domen_ssh"      (human admin)
#   ansible.pub ← item "ansible-admin_ssh"     (Ansible automation)
#
# Each is an SSH_KEY category item with a "public key" field. The script
# writes only the public half (never the private key) and verifies the
# fingerprint against the expected SHA256 from the same 1Password item
# (read-only `op item get` exposes the fingerprint without revealing
# the private key). Exit non-zero on fingerprint mismatch so a stale
# vault or wrong-item mistake surfaces immediately.
#
# Usage:
#   bash scripts/get-bootstrap-keys.sh                # write to IaC/router/rendered/
#   bash scripts/get-bootstrap-keys.sh /path/to/dir   # write to a custom dir
#
# Requires: 1Password CLI signed in (human sign-in to the vault is needed
# because the items are in Homelab-ansible, not the SA token's Private
# vault). On this host, the same `op` session that pulls the
# ansible-run.sh SA-token + renders .rsc also works for this script
# (the SA token does NOT have access to these items — interactive
# `op signin` is required first; the script will tell you if so).
# =====================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$REPO/IaC/router/rendered}"
VAULT="Homelab-ansible"

# --- 1Password CLI availability --------------------------------------------
if ! command -v op >/dev/null 2>&1; then
    echo "FAIL: 1Password CLI 'op' not found in PATH (install per scripts/bootstrap-runner.sh)" >&2
    exit 2
fi
if ! op account list >/dev/null 2>&1; then
    echo "FAIL: 1Password CLI is not signed in. Run: op signin" >&2
    exit 2
fi

# --- Pair: file-name <-> 1P item + expected SHA256 fingerprint ------------
# Fingerprints come from `op item get <item> --vault Homelab-ansible` →
# `fingerprint:` field. They are public metadata (NOT secret) and serve
# as the fail-loud anchor: if the vault rotates a key without us noticing
# the script will refuse to write a stale .pub to the rendered/ dir.
# Update these by re-running:
#   op item get <item> --vault Homelab-ansible --fields fingerprint
declare -A KEYS=(
    ["admin.pub"]="laptop-domen_ssh|SHA256:XTmK3tR59IMnok1HbEW7n3ZK0v4bd7miPS+0r7lSPTA"
    ["ansible.pub"]="ansible-admin_ssh|SHA256:1uKzmwfO8ljfYMX+nOuFPqFlxzGMF4LZa/0kZCdz7rU"
)

mkdir -p "$OUT_DIR"

fail=0
for file in "${!KEYS[@]}"; do
    spec="${KEYS[$file]}"
    item="${spec%|*}"
    expected_fp="${spec#*|}"
    out="$OUT_DIR/$file"
    tmp="$(mktemp "${TMPDIR:-/tmp}/bootstrap-key.XXXXXX.pub")"
    trap 'rm -f "$tmp"' EXIT

    # Pull the public key. `op read` against an SSH_KEY item's "public key"
    # field is the canonical command (HD-86 secret-output hygiene: never
    # `op item get --reveal` here — we only need the public half).
    if ! pub="$(op read "op://${VAULT}/${item}/public key" 2>/dev/null)"; then
        echo "FAIL: cannot read 1Password item '$item' from vault '$VAULT' (op signin needed?)" >&2
        fail=1
        continue
    fi

    # Compare fingerprint against the expected anchor. `ssh-keygen -lf`
    # prints SHA256:<base64>; op prints the same form. Fail loud on drift.
    printf '%s\n' "$pub" > "$tmp"
    actual_fp="$(ssh-keygen -E sha256 -lf "$tmp" 2>/dev/null | awk '{print $2}')"
    if [ "$actual_fp" != "$expected_fp" ]; then
        echo "FAIL: $file — fingerprint drift (expected $expected_fp, got $actual_fp)" >&2
        echo "      Re-anchor by running: op item get $item --vault $VAULT --fields fingerprint" >&2
        fail=1
        continue
    fi

    # Atomically install the verified public key
    mv "$tmp" "$out"
    chmod 0644 "$out"
    trap - EXIT
    echo "OK: $out  (item=$item  fp=$actual_fp)"
done

if [ "$fail" -ne 0 ]; then
    echo "FAIL: at least one key was not written — see above" >&2
    exit 1
fi

echo ""
echo "Wrote 2 .pub files to $OUT_DIR"
echo "Next (HD-304 flash-persistence): drag-drop the 4 .rsc files to device ROOT + the 2 .pub files into"
echo "      the flash/ folder on the CRS328 + APs (RB4011: root is fine for the .pub files),"
echo "      then run the per-device reset. See deployment-manual.md § Phase 1.5."
