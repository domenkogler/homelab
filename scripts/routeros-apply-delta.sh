#!/usr/bin/env bash
# =====================================================================
# routeros-apply-delta.sh — apply a transient/steady-state RouterOS delta
# `.rsc` to a MikroTik device via the ansible SSH identity + /import
# ---------------------------------------------------------------------
# Automates the manual apply loop in docs/network-ops.md §Apply workflow
# (and deployment-manual.md §1.5.3c) that has been typed by hand for every
# live fix (HD-308 bridge-vlan delta, HD-304 pi delta, HD-309 WAN delta):
#
#   1. Pull the `ansible-admin_ssh` PRIVATE key from 1Password via
#      `op read` (canonical clean PEM) and VERIFY it loads (ssh-keygen).
#      Using `op item get --reveal` piped through shell is fragile — its
#      stdout carries an inconsistent leading quote/newline wrapper that
#      corrupts the file and surfaces as OpenSSH's cryptic
#      `error in libcrypto` (self-inflicted 2026-09-01; the vault key was
#      fine). Fail loud here instead of after a device round-trip.
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

# --- 1. Pull + verify the private key -------------------------------------
# `op read` is the canonical, clean path: it emits the PEM bare (CRLF
# line endings, no shell-quote/caret wrapper). `op item get --reveal` wraps
# stdout inconsistently (observed 2026-09-01: a leading `"` + `\n`, or a
# stray prefix depending on call site) — avoid it here. Then prove the key
# loads with ssh-keygen (ground truth) BEFORE touching the device; this
# surfaces a broken/rotated vault key with a clear message instead of a
# cryptic `error in libcrypto` from scp/ssh later.
if ! op read "op://${VAULT}/${ITEM}/private key" > "$KEY_FILE" 2>/dev/null; then
    echo "FAIL: cannot read 1Password item '$ITEM' private key (op signin needed?)" >&2
    exit 1
fi
chmod 0600 "$KEY_FILE"
# Normalize CRLF -> LF (ssh-keygen accepts CRLF, but keep the file canonical)
sed -i 's/\r$//' "$KEY_FILE"

if ! ssh-keygen -y -f "$KEY_FILE" >/dev/null 2>&1; then
    echo "FAIL: ssh-keygen cannot load the ansible key (see error above)." >&2
    echo "      Check the vault item '$ITEM' (field 'private key') is a complete" >&2
    echo "      OpenSSH private key; re-import/regenerate if the vault copy is stale." >&2
    exit 1
fi
echo "OK: ansible key loads (fingerprint: $(ssh-keygen -lf "$KEY_FILE" | awk '{print $2}'))"

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