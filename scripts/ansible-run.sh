#!/usr/bin/env bash
# =====================================================================
# ansible-run.sh — run an Ansible playbook from the WSL Debian runner with
# the correct environment: venv activation, 1Password read-scope SA token,
# and explicit ANSIBLE_CONFIG / ANSIBLE_ROLES_PATH (required because Ansible
# ignores cwd ansible.cfg on world-writable /mnt drives).
#
# Usage (inside WSL Debian):
#   bash scripts/ansible-run.sh playbooks/vps.yml
#   bash scripts/ansible-run.sh playbooks/vps.yml --check --diff
#   bash scripts/ansible-run.sh IaC/ansible/test-1password.yml
#
# From Windows (git-bash or PowerShell), invoke through wsl.exe — pass this
# SCRIPT FILE, never inline commands (MSYS mangles wsl.exe arguments):
#   cmd //c "wsl -d Debian -- bash /mnt/d/source/domenkogler/homelab/scripts/ansible-run.sh playbooks/vps.yml"
#
# Requires Phase 0 bootstrap: ~/ansible-venv + ~/.config/op/homelab-sa-token.
# =====================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ANSIBLE_CONFIG="$REPO/IaC/ansible/ansible.cfg"
export ANSIBLE_ROLES_PATH="$REPO/IaC/ansible/roles"

if [ -f "$HOME/.config/op/homelab-sa-token" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.config/op/homelab-sa-token"
else
    echo "FAIL: $HOME/.config/op/homelab-sa-token missing — run IaC/bootstrap-ansible-client/bootstrap.sh first" >&2
    exit 1
fi

if [ -d "$HOME/ansible-venv" ]; then
    # shellcheck disable=SC1091
    source "$HOME/ansible-venv/bin/activate"
else
    echo "FAIL: ~/ansible-venv missing — run IaC/bootstrap-ansible-client/bootstrap.sh first" >&2
    exit 1
fi

PLAYBOOK="${1:?usage: ansible-run.sh <playbook> [extra ansible-playbook args]}"
shift
case "$PLAYBOOK" in
    /*) ;;                                    # absolute path — use as-is
    IaC/*) PLAYBOOK="$REPO/$PLAYBOOK" ;;      # repo-relative
    *) PLAYBOOK="$REPO/IaC/ansible/$PLAYBOOK" ;;  # bare playbook name — runner default root
esac

cd "$REPO/IaC/ansible"
exec ansible-playbook -i inventory.ini "$PLAYBOOK" "$@"
