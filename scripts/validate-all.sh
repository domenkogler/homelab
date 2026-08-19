#!/usr/bin/env bash
# Repo validation gate — run before committing any change.
#   bash scripts/validate-all.sh          (Linux, macOS, Windows git-bash)
#
# Runs every automated checker referenced in docs/index.md → Conventions:
#   1. validate-docker-services.py  — compose templates + group_vars list
#   2. validate_blueprints.py       — Authentik ks-oidc.yml blueprint shape
#   3. check_doc_ips.py            — no internal IP literals outside the SSOT
#   4. validate_doc_templates.py   — SSOT doc templates render with group_vars
#   5. validate-secrets.py         — no literal credentials in group_vars/templates
#   6. check_doc_map.py            — docs/index.md document map matches docs/ tree
#
# Exit 0 only when all pass. `set -e` stops at the first failure.
set -euo pipefail
cd "$(dirname "$0")/.."

# Python launcher: prefer python3 (Linux/CI), fall back to py -3 (Windows).
# PYTHONUTF8=1 keeps Windows console output from crashing on non-ASCII.
if command -v python3 >/dev/null 2>&1; then
  PY="python3"
elif command -v py >/dev/null 2>&1; then
  PY="py -3"
else
  echo "error: no python3 or py on PATH" >&2
  exit 1
fi
export PYTHONUTF8=1

echo "== validate-docker-services.py =="
$PY scripts/validate-docker-services.py

echo "== validate_blueprints.py =="
$PY scripts/validate_blueprints.py

echo "== check_doc_ips.py =="
$PY scripts/check_doc_ips.py

echo "== validate_doc_templates.py =="
$PY scripts/validate_doc_templates.py

echo "== validate-secrets.py =="
$PY scripts/validate-secrets.py

echo "== check_doc_map.py =="
$PY scripts/check_doc_map.py

echo "OK: all validators passed"
