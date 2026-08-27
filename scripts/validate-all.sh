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
#  11. testdata/check-vault-items/run.sh — check-vault-items.sh scanner self-test
#                                     (HD-244/245): *_item registry-key parsing + --strict
#                                     contract asserted on a committed synthetic mini-tree
#  12. Portability sweep — bash -n (all POSIX/bash shebang scripts) + python3 -m py_compile
#                                     (all scripts/*.py), so scripts cannot regress on the
#                                     Debian/WSL ext4 primary (HD-256); bash -n is a no-op on
#                                     hosts without bash (CI/Linux only, never Windows)
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

echo "== testdata/check-vault-items/run.sh (scanner self-test, HD-244/245) =="
bash scripts/testdata/check-vault-items/run.sh

echo "== portability sweep (bash -n + python3 -m py_compile, HD-256) =="
# bash -n every POSIX/bash shebang script under scripts/ (incl. the testdata runner).
# bash-shebang scripts must parse cleanly on the Debian/WSL ext4 primary (HD-259);
# POSIX 'sh' scripts (collect-disk-facts.sh, collect-smart-live.sh) are checked here
# too because bash is a POSIX superset and the repo gates run under bash. Silent no-op
# on hosts without bash (Windows) — those scripts are exercised under WSL/CI.
if command -v bash >/dev/null 2>&1; then
  bash_fail=0
  for f in scripts/*.sh scripts/testdata/check-vault-items/run.sh; do
    [ -f "$f" ] || continue
    case "$(head -n1 "$f")" in
      *bash|*sh)
        bash -n "$f" >/dev/null 2>&1 || { echo "bash -n FAIL: $f" >&2; bash_fail=$((bash_fail+1)); }
        ;;
    esac
  done
  [ "$bash_fail" -eq 0 ] || exit 1
  echo "OK: all bash/sh scripts pass bash -n"
else
  echo "SKIP: bash not on PATH — bash -n sweep runs under WSL/CI"
fi

# python3 -m py_compile every scripts/*.py (byte-compiles to gitignored __pycache__).
if command -v python3 >/dev/null 2>&1; then
  py_fail=0
  for f in scripts/*.py; do
    [ -f "$f" ] || continue
    python3 -m py_compile "$f" >/dev/null 2>&1 || { echo "py_compile FAIL: $f" >&2; py_fail=$((py_fail+1)); }
  done
  [ "$py_fail" -eq 0 ] || exit 1
  echo "OK: all scripts/*.py compile under python3"
else
  echo "SKIP: python3 not on PATH — py_compile sweep skipped"
fi

echo "== ansible-playbook --syntax-check (WSL/CI-gated) =="
# HD-197: catch unresolvable modules / broken YAML in every playbook at gate time.
# Requires the Ansible venv (WSL/CI); skipped gracefully on native Windows like the
# Ansible render path (see scripts/README.md).
# HD-256: like ansible-run.sh, export ANSIBLE_CONFIG + ANSIBLE_ROLES_PATH so the
# role path resolves when running from the repo root on the Debian/WSL primary
# (otherwise ansible finds no config here and every `roles: - xxx` fails to resolve).
REPO_ROOT="$(pwd)"
export ANSIBLE_CONFIG="$REPO_ROOT/IaC/ansible/ansible.cfg"
export ANSIBLE_ROLES_PATH="$REPO_ROOT/IaC/ansible/roles"
if command -v ansible-playbook >/dev/null 2>&1 && ansible-playbook --version >/dev/null 2>&1; then
  for pb in IaC/ansible/site.yml IaC/ansible/playbooks/*.yml; do
    ansible-playbook -i IaC/ansible/inventory.ini "$pb" --syntax-check >/dev/null
  done
  echo "OK: all playbooks pass --syntax-check"
else
  echo "SKIP: ansible-playbook not functional on this host (absent or native-Windows WinError 87) — syntax gate runs under WSL/CI"
fi

echo "OK: all validators passed"
