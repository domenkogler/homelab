#!/bin/bash
# ak-shell.sh — run a Python snippet inside the authentik-worker container (VPS)
# from the WSL Debian runner, without multi-layer quoting pain.
#
# WHY THIS EXISTS (Phase 1 live deploy, 2026-08-22): driving `ak shell -c` needs
# git-bash -> wsl.exe -> ssh -> sudo docker exec -> ak shell quoting to line up;
# every inline attempt eventually mangles the embedded quotes. This script is the
# ONE sanctioned indirection: call it INSIDE WSL (script-file invocation, never
# inline commands through wsl.exe), pass the Python as ONE argument or via stdin.
#
# Usage (from Windows, script-file indirection; $REPO = the repo root, self-derived
#   from this script's own path — on this machine /home/domen/source/homelab):
#   wsl -d Debian -- bash $REPO/scripts/ansible/ak-shell.sh '<python>'
#   echo '<python>' | wsl -d Debian -- bash $REPO/scripts/ansible/ak-shell.sh -
# Examples:
#   ak-shell.sh 'from authentik.core.models import User; print([u.username for u in User.objects.all()])'
#   ak-shell.sh - <<'PY'
#   from authentik.core.models import Token
#   print([(t.identifier, t.user.username) for t in Token.objects.all()])
#   PY
#
# Prereqs: WSL runner bootstrapped (Phase 0; the canonical automation key at
# ~/.ssh/ansible-admin_ssh — docs/network-vpn.md §Canonical identity file names. This path does NOT
# depend on the Windows 1Password agent). Noise filter drops
# authentik's own startup JSON log lines (they begin with '{"').
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: bash scripts/ansible/ak-shell.sh '<python>' | echo '<python>' | bash scripts/ansible/ak-shell.sh -" >&2
  exit 2
fi

if [ "$1" = "-" ]; then
  CODE=$(cat)
else
  CODE=$1
fi

B64=$(printf '%s' "$CODE" | base64 -w0)

# The identity is NAMED, not inherited (HD-1125). `vps.kogler.si` is the name TYPED, and OpenSSH
# matches the name actually typed (docs/network-vpn.md §The laptop alias contract rule 2), so a leg
# with no IdentityFile here resolves no alias block and offers ssh's DEFAULT identity instead — on
# the Debian seats that default path holds the fleet's automation key under a superseded name, which
# makes this work by accident. Naming the canonical file with IdentitiesOnly is the wiring; `-n` is
# the CONVENTIONS §6 stdin rule.
out=$(ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes \
  -o IdentityFile=~/.ssh/ansible-admin_ssh ansible-admin@vps.kogler.si \
  "sudo docker exec authentik-worker ak shell -c \"\$(echo $B64 | base64 -d)\"" \
  2>/dev/null) || { echo "ak-shell: remote execution failed (runner key / VPS unreachable?)" >&2; exit 1; }

printf '%s\n' "$out" | grep -vE '^\{"' || true
