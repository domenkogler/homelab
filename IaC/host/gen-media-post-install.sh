#!/usr/bin/env bash
# =====================================================================
# gen-media-post-install.sh — build post_install_with_secrets.sh for the
# homelab USB install media (oldsrv / nas preseed installs).
#
# The committed IaC/host/post_install.sh is PLACEHOLDER-ONLY (repo law:
# keys never in Git). At media-build time this generator injects the three
# REAL public keys from the 1Password Homelab-ansible vault
#   laptop-domen_ssh · ansible-admin_ssh · ai_ssh   (field public_key)
# into a git-ignored copy. The output is what the preseed late_command
# expects on the media as  /preseed/post_install.sh  (next to the host's
# preseed.cfg). DELETE the generated file after copying it to the stick.
#
# Run on the management runner (WSL Debian — needs a working `op` session):
#   cd IaC/host && ./gen-media-post-install.sh [/media/usb0]   # mountpoint optional
#
# Wrong-script guard (see deployment-preseed.md): the VPS uses its OWN
# two-key post_install (no ai-debug on a public box). This generator is for
# the LAN hosts only and injects all THREE keys.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

OUT=post_install_with_secrets.sh
SRC=post_install.sh

command -v op >/dev/null || { echo "FAIL: op CLI not found"; exit 1; }

domen_pub=$(op read "op://Homelab-ansible/laptop-domen_ssh/public_key")
ansible_pub=$(op read "op://Homelab-ansible/ansible-admin_ssh/public_key")
ai_pub=$(op read "op://Homelab-ansible/ai_ssh/public_key")
[ -n "$domen_pub" ] && [ -n "$ansible_pub" ] && [ -n "$ai_pub" ] \
    || { echo "FAIL: empty key from 1Password"; exit 1; }

cp -- "$SRC" "$OUT"
chmod 600 "$OUT"
# Replace the three placeholder tokens with the real public keys. The
# placeholders do NOT hardcode an algorithm prefix — the injected public_key
# fields already carry one (HD-209 lesson).
sed -i "s|<PERSONAL_PUBKEY_FROM_1PASSWORD>|${domen_pub}|; s|<ANSIBLE_PUBKEY_FROM_1PASSWORD>|${ansible_pub}|; s|<AI_PUBKEY_FROM_1PASSWORD>|${ai_pub}|" "$OUT"

if grep -qE '<(PERSONAL|ANSIBLE|AI)_PUBKEY_FROM_1PASSWORD>' "$OUT"; then
    echo "FAIL: placeholders remain in $OUT — aborting"; exit 1
fi

# Malformed-key guard (HD-209): doubled algorithm prefix → sshd silently
# ignores the line → lockout (no root password, KOPS-044).
if grep -qE 'ssh-(ed25519|rsa)[[:space:]]+ssh-' "$OUT"; then
    echo "FAIL: doubled algorithm prefix in $OUT — aborting"; exit 1
fi
grep -qF -- "${domen_pub} admin@laptop" "$OUT" || { echo "FAIL: personal key line malformed in $OUT"; exit 1; }
grep -qF -- "${ansible_pub} ansible" "$OUT" || { echo "FAIL: ansible key line malformed in $OUT"; exit 1; }
grep -qF -- "${ai_pub} openrouter_ai" "$OUT" || { echo "FAIL: ai key line malformed in $OUT"; exit 1; }

bash -n "$OUT"
echo "✔ $OUT written (0600, three keys injected, syntax OK)."

# Optional: copy straight onto the mounted USB media where late_command wants it
if [ $# -ge 1 ]; then
    MEDIA="$1/preseed"
    [ -d "$MEDIA" ] || { echo "FAIL: $MEDIA not found — is $1 the mounted install media (preseed/ dir at its root)?"; exit 1; }
    cp -- "$OUT" "$MEDIA/post_install.sh"
    sync
    echo "✔ copied to $MEDIA/post_install.sh — media is ready to boot."
    echo "  Now DELETE the local secrets copy:  rm -- $OUT"
else
    echo "  Next: copy it onto the USB media as preseed/post_install.sh (next to"
    echo "  IaC/host/oldsrv/preseed.cfg), then DELETE this file:  rm -- $OUT"
    echo "  Or re-run with the mountpoint:  ./gen-media-post-install.sh /media/<usb>"
fi
