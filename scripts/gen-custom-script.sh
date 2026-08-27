#!/usr/bin/env bash
# =====================================================================
# gen-custom-script.sh — build post_install_with_secrets.sh for the netcup
# SCP Custom-Script field (HD-206-era flow, deployment-preseed.md §netcup).
#
# Injects the two REAL public keys from the 1Password Homelab-ansible vault
# (items laptop-domen_ssh / ansible-admin_ssh, field public_key) into a copy
# of post_install.sh. The output is git-ignored (.gitignore) and must be
# DELETED after pasting into the netcup SCP field.
#
# Run on the management runner (WSL Debian — needs a working `op` session):
#   bash scripts/gen-custom-script.sh
# =====================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

OUT="$REPO/IaC/host/vps/post_install_with_secrets.sh"
SRC="$REPO/IaC/host/vps/post_install.sh"

command -v op >/dev/null || { echo "FAIL: op CLI not found"; exit 1; }

domen_pub=$(op read "op://Homelab-ansible/laptop-domen_ssh/public_key")
ansible_pub=$(op read "op://Homelab-ansible/ansible-admin_ssh/public_key")
[ -n "$domen_pub" ] && [ -n "$ansible_pub" ] || { echo "FAIL: empty key from 1Password"; exit 1; }

cp -- "$SRC" "$OUT"
chmod 600 "$OUT"
# Replace the two placeholder tokens with the real public keys.
sed -i "s|<PERSONAL_PUBKEY_FROM_1PASSWORD>|${domen_pub}|; s|<ANSIBLE_PUBKEY_FROM_1PASSWORD>|${ansible_pub}|" "$OUT"

if grep -q "_FROM_1PASSWORD>" "$OUT"; then
    echo "FAIL: placeholders remain in $OUT — aborting"; exit 1
fi

# Malformed-key guard (found live 2026-08-22, HD-209): the templates used to
# hardcode an "ssh-ed25519 " prefix while the injected public_key fields already
# carry one → doubled prefix → sshd silently ignores the line → SSH lockout.
if grep -qE 'ssh-(ed25519|rsa)[[:space:]]+ssh-' "$OUT"; then
    echo "FAIL: doubled algorithm prefix in $OUT — aborting"; exit 1
fi
grep -qF -- "${domen_pub} admin@laptop" "$OUT" || { echo "FAIL: personal key line malformed in $OUT"; exit 1; }
grep -qF -- "${ansible_pub} ansible" "$OUT" || { echo "FAIL: ansible key line malformed in $OUT"; exit 1; }

bash -n "$OUT"
echo "✔ $OUT written (0600, placeholders injected, syntax OK)."
echo "  Next: paste its FULL content into netcup SCP → Custom Script,"
echo "  then DELETE this file:  rm -- $OUT"
