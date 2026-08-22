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
# Usage (from Windows, script-file indirection):
#   wsl -d Debian -- bash /mnt/d/source/domenkogler/homelab/scripts/ak-shell.sh '<python>'
#   echo '<python>' | wsl -d Debian -- bash /mnt/d/source/domenkogler/homelab/scripts/ak-shell.sh -
# Examples:
#   ak-shell.sh 'from authentik.core.models import User; print([u.username for u in User.objects.all()])'
#   ak-shell.sh - <<'PY'
#   from authentik.core.models import Token
#   print([(t.identifier, t.user.username) for t in Token.objects.all()])
#   PY
#
# Prereqs: WSL runner bootstrapped (Phase 0; canonical key at ~/.ssh/id_ed25519 —
# this path does NOT depend on the Windows 1Password agent). Noise filter drops
# authentik's own startup JSON log lines (they begin with '{"').
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: bash scripts/ak-shell.sh '<python>' | echo '<python>' | bash scripts/ak-shell.sh -" >&2
  exit 2
fi

if [ "$1" = "-" ]; then
  CODE=$(cat)
else
  CODE=$1
fi

B64=$(printf '%s' "$CODE" | base64 -w0)

out=$(ssh -o BatchMode=yes -o ConnectTimeout=10 ansible-admin@vps.kogler.si \
  "sudo docker exec authentik-worker ak shell -c \"\$(echo $B64 | base64 -d)\"" \
  2>/dev/null) || { echo "ak-shell: remote execution failed (runner key / VPS unreachable?)" >&2; exit 1; }

printf '%s\n' "$out" | grep -vE '^\{"' || true
