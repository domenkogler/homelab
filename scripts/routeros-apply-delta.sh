#!/usr/bin/env bash
# =====================================================================
# routeros-apply-delta.sh — apply a transient/steady-state RouterOS delta
# `.rsc` to a MikroTik device via the ansible SSH identity + /import
# ---------------------------------------------------------------------
# Automates the manual apply loop in docs/network-ops.md §Apply workflow
# (and deployment-manual.md §1.5.3c) that has been typed by hand for every
# live fix (HD-308 bridge-vlan delta, HD-304 pi delta, HD-309 WAN delta):
#
#   1. Pull the `ansible-admin_ssh` PRIVATE key from 1Password
#      (vault Homelab-ansible), strip shell-quoting pollution, and
#      PARSE-VERIFY it. A corrupt/truncated private key (e.g. a 1P
#      SSHKEY item whose private half was mangled — live-found 2026-09-01)
#      otherwise fails far later with a cryptic `error in libcrypto`.
#   2. Pin the device's CURRENT SSH host key (TOFU — RouterOS rotates it
#      at every reset); refuse a blank key.
#   3. SCP the rendered delta to the device root.
#   4. /import it over SSH (ansible identity).
#
# The delta MUST already be rendered into IaC/router/rendered/ (run
# playbooks/render-converge.yml first, or cp the .j2 for a no-secret delta).
# Secret hygiene: the private key is written to a 0600 temp file and
# deleted on exit; the script never prints key material (probes print
# lengths/fingerprints only — CONVENTIONS §Secrets / HD-233-234).
#
# Usage:
#   bash scripts/routeros-apply-delta.sh <device-host> <delta-file>
#     e.g. bash scripts/routeros-apply-delta.sh 10.10.99.1 rb4011_wan_delta.rsc
#   Env: ROS_SSH_USER (default: ansible)
#
# Requires: 1Password CLI signed in (Homelab-ansible vault, human session —
#   the SA token cannot read these items), openssh client + ssh-keygen.
# =====================================================================
set -euo pipefail

DEVICE_HOST="${1:-}"
DELTA_FILE="${2:-}"
ROS_SSH_USER="${ROS_SSH_USER:-ansible}"
VAULT="Homelab-ansible"
ITEM="ansible-admin_ssh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDERED="$REPO/IaC/router/rendered/$DELTA_FILE"

# --- arg validation ---------------------------------------------------------
if [ -z "$DEVICE_HOST" ] || [ -z "$DELTA_FILE" ]; then
    echo "FAIL: usage: bash scripts/routeros-apply-delta.sh <device-host> <delta-file>" >&2
    echo "      e.g. bash scripts/routeros-apply-delta.sh 10.10.99.1 rb4011_wan_delta.rsc" >&2
    exit 2
fi
if [ ! -f "$RENDERED" ]; then
    echo "FAIL: rendered delta not found: $RENDERED" >&2
    echo "      Render it first: bash scripts/ansible-run.sh playbooks/render-converge.yml" >&2
    echo "      (or cp the .j2 for a no-secret delta; rendered/ is gitignored)." >&2
    exit 2
fi

# --- 1Password CLI ----------------------------------------------------------
if ! command -v op >/dev/null 2>&1; then
    echo "FAIL: 1Password CLI 'op' not found in PATH" >&2
    exit 2
fi
if ! op account list >/dev/null 2>&1; then
    echo "FAIL: 1Password CLI is not signed in. Run: op signin" >&2
    exit 2
fi

TMPDIR_X="$(mktemp -d "${TMPDIR:-/tmp}/ros-apply.XXXXXX")"
KEY_FILE="$TMPDIR_X/ansible_key"
HOSTKEYS="$TMPDIR_X/hostkeys"
trap 'rm -rf "$TMPDIR_X"' EXIT

# --- 1. Pull + normalize + parse-verify the private key ---------------------
# `op item get --reveal` is the ONLY way to read the private field; the CLI's
# stdout sometimes carries a leading `"` + trailing `"` (shell-quoting residue
# observed 2026-09-01). Normalize, then structurally verify BEFORE use.
priv="$(op item get "$ITEM" --vault "$VAULT" --field "private key" --reveal 2>/dev/null || true)"
if [ -z "$priv" ]; then
    echo "FAIL: cannot read 1Password item '$ITEM' private key (op signin needed?)" >&2
    exit 1
fi
# Strip the wrapping quotes + surrounding whitespace (HD-233 hygiene note)
norm="$(printf '%s' "$priv" | sed -e 's/^"//' -e 's/"$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
printf '%s\n' "$norm" > "$KEY_FILE"
chmod 0600 "$KEY_FILE"

# Structural verify: an OpenSSH ed25519 private key must decode to a body
# whose private-key section contains the 32-byte seed + comment + padding.
# A truncated key (live-found 2026-09-01: priv section = 51 bytes, missing
# the seed/comment) fails here with a CLEAR message instead of a cryptic
# `error in libcrypto` later.
python3 - "$KEY_FILE" <<'PYEOF'
import base64, struct, sys
path = sys.argv[1]
raw = open(path, 'rb').read().strip()
if not raw.startswith(b'-----BEGIN OPENSSH PRIVATE KEY-----'):
    print("FAIL: key is not an OpenSSH private key (BEGIN marker missing) — check the vault item")
    sys.exit(1)
b64 = b''.join(raw.split(b'\n')[1:-1])
try:
    dec = base64.b64decode(b64)
except Exception as e:
    print(f"FAIL: key base64 decode error: {e}")
    sys.exit(1)
def rd(o):
    n = struct.unpack('>I', dec[o:o+4])[0]
    return dec[o+4:o+4+n], o+4+n
try:
    off = 15
    cipher, off = rd(off); kdf, off = rd(off); kdfopts, off = rd(off)
    nkeys = struct.unpack('>I', dec[off:off+4])[0]; off += 4
    n, off = struct.unpack('>I', dec[off:off+4])[0], off + 4
    priv = dec[off:off+n]
    # priv section: keytype + public + private(seed) + comment + padding
    p = 0
    nl = struct.unpack('>I', priv[p:p+4])[0]; p += 4
    kt = priv[p:p+nl]; p += nl
    nl = struct.unpack('>I', priv[p:p+4])[0]; p += 4
    pub = priv[p:p+nl]; p += nl
    nl = struct.unpack('>I', priv[p:p+4])[0]; p += 4
    seed = priv[p:p+nl]; p += nl
    rem = priv[p:]
    if nkeys != 1:
        print(f"FAIL: unexpected key count {nkeys} in OpenSSH key"); sys.exit(1)
    if kt != b'ssh-ed25519' or len(seed) != 32:
        print(f"FAIL: key structure invalid (type={kt!r} seed_len={len(seed)}); the 1P item's private key looks truncated/corrupt.")
        print("      Owner action: regenerate or re-import the correct ansible-admin_ssh private key in 1Password.")
        sys.exit(1)
except (struct.error, IndexError) as e:
    print(f"FAIL: key structure unparseable ({e}); the 1P item's private key looks truncated/corrupt.")
    print("      Owner action: regenerate or re-import the correct ansible-admin_ssh private key in 1Password.")
    sys.exit(1)
print(f"OK: key structure valid (ed25519, seed={len(seed)}B, cipher={cipher!r}, kdf={kdf!r})")
PYEOF

# Also confirm the local ssh can load it (guards the OpenSSH 10.x loader path)
if ! ssh-keygen -y -f "$KEY_FILE" >/dev/null 2>&1; then
    echo "FAIL: ssh-keygen cannot load the ansible key (see error above) — cannot authenticate." >&2
    exit 1
fi

# --- 2. Pin the device host key (TOFU — rotates at reset) -------------------
if ! ssh-keyscan -T 5 -t ed25519,rsa "$DEVICE_HOST" > "$HOSTKEYS" 2>/dev/null; then
    echo "FAIL: cannot ssh-keyscan $DEVICE_HOST (unreachable?)" >&2
    exit 1
fi
if [ ! -s "$HOSTKEYS" ]; then
    echo "FAIL: no host key obtained for $DEVICE_HOST — refuse to connect blindly" >&2
    exit 1
fi
echo "--- pinned host key fingerprint(s) ---"
ssh-keygen -lf "$HOSTKEYS" 2>/dev/null | sed 's/^/  /'

# --- 3. SCP the delta --------------------------------------------------------
echo "--- uploading $DELTA_FILE to $DEVICE_HOST ---"
scp -q -i "$KEY_FILE" \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$HOSTKEYS" \
    "$RENDERED" "${ROS_SSH_USER}@${DEVICE_HOST}:/${DELTA_FILE}"

# --- 4. /import over SSH -----------------------------------------------------
echo "--- importing on $DEVICE_HOST ---"
ssh -i "$KEY_FILE" \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$HOSTKEYS" \
    "${ROS_SSH_USER}@${DEVICE_HOST}" "/import ${DELTA_FILE}"

echo ""
echo "OK: ${DELTA_FILE} applied to ${DEVICE_HOST}."
echo "Verify live state via the read-only API, then FOLD the delta into the"
echo "converge template + router role and DELETE the delta (network-ops.md 3-tier)."