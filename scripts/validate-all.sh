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
#   7. check_generated_suffix.py    — every machine-generated doc carries the -generated suffix
#   8. check_vault_name.py          — vault is 'Homelab-ansible' (no bare Homelab refs, HD-189)
#   9. check_placeholders.py        — placeholder tokens only in designated bootstrap files (HD-201)
#  10. guard-session.sh             — session-discipline hard-gate + sandboxed self-test (HD-253):
#                                     --validate-mode fails on primary+main+DIRTY; clean-main
#                                     merge-station runs pass silently; self-test fixture asserts
#                                     the guard contract inside throwaway temp repos
#   + ansible-playbook --syntax-check across all playbooks (WSL/CI-gated, HD-197)
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

echo "== guard-session.sh --validate-mode (session-discipline hard gate, HD-253) =="
bash scripts/guard-session.sh --validate-mode

echo "== guard-session.sh --self-test (sandboxed guard fixture, HD-253) =="
bash scripts/guard-session.sh --self-test

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

echo "== check_generated_suffix.py =="
$PY scripts/check_generated_suffix.py

echo "== check_vault_name.py =="
$PY scripts/check_vault_name.py

echo "== check_placeholders.py =="
$PY scripts/check_placeholders.py

echo "== ansible-playbook --syntax-check (WSL/CI-gated) =="
# HD-197: catch unresolvable modules / broken YAML in every playbook at gate time.
# Requires the Ansible venv (WSL/CI); skipped gracefully on native Windows like the
# Ansible render path (see scripts/README.md).
if command -v ansible-playbook >/dev/null 2>&1 && ansible-playbook --version >/dev/null 2>&1; then
  for pb in IaC/ansible/site.yml IaC/ansible/playbooks/*.yml; do
    ansible-playbook -i IaC/ansible/inventory.ini "$pb" --syntax-check >/dev/null
  done
  echo "OK: all playbooks pass --syntax-check"
else
  echo "SKIP: ansible-playbook not functional on this host (absent or native-Windows WinError 87) — syntax gate runs under WSL/CI"
fi

echo "OK: all validators passed"
