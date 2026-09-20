#!/usr/bin/env bash
# =====================================================================
# ansible-run.sh — run an Ansible playbook from THIS runner with the correct
# environment: venv activation, the 1Password read-scope SA token, and explicit
# ANSIBLE_CONFIG / ANSIBLE_ROLES_PATH exports.
#
# Machine-agnostic by design (HD-407): every path is derived from this script's own
# location, so the same file works from the WSL ext4 primary, from a session worktree
# (CONVENTIONS §6) and from oldsrv's own clone. It never hardcodes a host, a user or a
# drive letter. The two exports are not decoration:
#   ANSIBLE_CONFIG      — Ansible ignores a cwd ansible.cfg on a world-writable /mnt
#                         drive (the original WSL motivation) and never searches upward
#                         from an absolute playbook path; naming it explicitly makes
#                         host_key_checking/pipelining/fact-cache apply on every runner.
#   ANSIBLE_ROLES_PATH  — ansible.cfg resolves `roles_path = roles` relative to CWD,
#                         which only works when CWD is IaC/ansible. Pin it absolutely.
#
# Usage (any runner, from anywhere):
#   bash scripts/ansible-run.sh playbooks/vps.yml
#   bash scripts/ansible-run.sh playbooks/home_servers.yml --check
#   bash scripts/ansible-run.sh playbooks/vps.yml --check --diff
#   bash scripts/ansible-run.sh IaC/ansible/test-1password.yml
#
# From Windows (git-bash or PowerShell), invoke through wsl.exe — pass this
# SCRIPT FILE, never inline commands (MSYS mangles wsl.exe arguments):
#   cmd //c "wsl -d Debian -- bash $REPO/scripts/ansible-run.sh playbooks/vps.yml"
#   (where $REPO = the repo root — the script self-derives it from its own path;
#    on this machine that is /home/domen/source/homelab, the WSL ext4 primary)
#
# Requires Phase 0 bootstrap on whichever machine runs it:
#   ~/ansible-venv + ~/.config/op/homelab-sa-token  (scripts/bootstrap-runner.sh),
#   plus the vault-canonical runner key (scripts/restore-runner-key.sh).
#
# HD-413: some legs refuse when this runner IS the target (network / storage /
# wireguard / vps-hardening). That is the guardrail, not a fault — the off-box path and
# the check-mode legs that stay open are in docs/deployment-ansible.md.
# =====================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ANSIBLE_CONFIG="$REPO/IaC/ansible/ansible.cfg"
export ANSIBLE_ROLES_PATH="$REPO/IaC/ansible/roles"

if [ -f "$HOME/.config/op/homelab-sa-token" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.config/op/homelab-sa-token"
else
    echo "FAIL: $HOME/.config/op/homelab-sa-token missing — run scripts/bootstrap-runner.sh first" >&2
    exit 1
fi

if [ -d "$HOME/ansible-venv" ]; then
    # shellcheck disable=SC1091
    source "$HOME/ansible-venv/bin/activate"
else
    echo "FAIL: ~/ansible-venv missing — run scripts/bootstrap-runner.sh first" >&2
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
