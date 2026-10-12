#!/usr/bin/env bash
# =====================================================================
# provision-vault.sh — seed missing GENERATED 1Password items via
# scripts/secrets/provision-secrets.py, using the write-scoped SA token stored on
# the VPS (/etc/op/provision-token, HD-143). The token is pulled transiently
# over SSH into this process' environment only — never written to disk here.
#
# Usage (WSL Debian runner):
#   bash scripts/secrets/provision-vault.sh             # create missing items
#   bash scripts/secrets/provision-vault.sh --dry-run   # list the catalog only
# =====================================================================
set -euo pipefail

# HD-1118 Stage 1: the repo root is FOUND by scripts/lib/repo-root.sh, never assumed
# from a depth — "one level above me" is what turns a folder move into green-while-nothing.
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"   # sets REPO (an inherited $REPO still wins)
TOKEN="$(ssh -o BatchMode=yes ansible-admin@vps.kogler.si 'sudo cat /etc/op/provision-token')"
[ -n "$TOKEN" ] || { echo "FAIL: no token fetched from VPS" >&2; exit 1; }
export OP_SERVICE_ACCOUNT_TOKEN="$TOKEN"

cd "$REPO"
if [ "${1:-}" = "--dry-run" ]; then
    python3 scripts/secrets/provision-secrets.py --list
else
    python3 scripts/secrets/provision-secrets.py --create --yes
fi
