#!/usr/bin/env bash
# =====================================================================
# provision-vault.sh — seed missing GENERATED 1Password items via
# scripts/provision-secrets.py, using the write-scoped SA token stored on
# the VPS (/etc/op/provision-token, HD-143). The token is pulled transiently
# over SSH into this process' environment only — never written to disk here.
#
# Usage (WSL Debian runner):
#   bash scripts/provision-vault.sh             # create missing items
#   bash scripts/provision-vault.sh --dry-run   # list the catalog only
# =====================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOKEN="$(ssh -o BatchMode=yes ansible-admin@vps.kogler.si 'sudo cat /etc/op/provision-token')"
[ -n "$TOKEN" ] || { echo "FAIL: no token fetched from VPS" >&2; exit 1; }
export OP_SERVICE_ACCOUNT_TOKEN="$TOKEN"

cd "$REPO"
if [ "${1:-}" = "--dry-run" ]; then
    python3 scripts/provision-secrets.py --list
else
    python3 scripts/provision-secrets.py --create --yes
fi
