#!/usr/bin/env bash
# =====================================================================
# restore-runner-key.sh — restore the canonical ansible-admin_ssh key into
# the WSL runner's ~/.ssh/id_ed25519[.pub] (1Password = source of truth).
#
# Run AFTER a true-zero WSL rebuild (deployment-tasks Phase 0): bootstrap.sh
# generates a THROWAWAY key that must be replaced so SSH to managed hosts
# works. Verifies the fingerprint at the end (expect SHA256:1uKzmwf…).
#
# Usage (WSL Debian runner): bash scripts/restore-runner-key.sh
# =====================================================================
set -euo pipefail

[ -f "$HOME/.config/op/homelab-sa-token" ] || {
    echo "FAIL: SA token file missing — run IaC/bootstrap-ansible-client/bootstrap.sh first" >&2
    exit 1
}
chmod 700 "$HOME/.config/op"   # op refuses world-accessible config dirs
# shellcheck disable=SC1091
source "$HOME/.config/op/homelab-sa-token"

umask 077
mkdir -p "$HOME/.ssh"
op read "op://Homelab-ansible/ansible-admin_ssh/private_key" > "$HOME/.ssh/id_ed25519"
op read "op://Homelab-ansible/ansible-admin_ssh/public_key"  > "$HOME/.ssh/id_ed25519.pub"
chmod 600 "$HOME/.ssh/id_ed25519"
chmod 644 "$HOME/.ssh/id_ed25519.pub"

# pair-consistency + fingerprint evidence
if ssh-keygen -y -f "$HOME/.ssh/id_ed25519" | awk '{print $1" "$2}' | \
   diff -q - <(awk '{print $1" "$2}' "$HOME/.ssh/id_ed25519.pub") >/dev/null; then
    echo "pair-consistent: yes"
else
    echo "FAIL: private/public mismatch" >&2
    exit 1
fi
echo "-- fingerprint (expect SHA256:1uKzmwfO8ljfYMX+nOuFPqFlxzGMF4LZa/0kZCdz7rU):"
ssh-keygen -lf "$HOME/.ssh/id_ed25519.pub"
