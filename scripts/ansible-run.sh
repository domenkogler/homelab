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
#   bash scripts/ansible-run.sh playbooks/vps.yml --no-pull   # converge THIS tree as-is
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
# wireguard / tailscale-node / vps-hardening / cockpit — the last one because HD-361 made
# that role write /etc/pam.d, i.e. it can revoke the web console a converge is driven from).
# That is the guardrail, not a fault — the
# off-box path and the check-mode legs that stay open are in docs/deployment-ansible.md.
#
# RUNNER SELF-UPDATE (owner decision 2026-09-23, reversing this script's original
# stance). It used to say "NOTHING HERE PULLS", and the reason was sound: a runner that
# updates itself mid-run is a runner whose behaviour you did not choose. What that trade
# bought turned out to be worse — the oldsrv runner clone sat on a 2026-09-23 commit while
# main had moved, and nothing in any run said so: a converge could be run against code the
# repo had already replaced, silently. So the update is now the DEFAULT and the escape
# hatch is the flag:
#   default            git pull --ff-only on the runner clone, then converge that commit
#   --no-pull          converge the working tree as-is (deliberate: hotfixes, session
#                      branches, offline work)
# Non-negotiables kept: it NEVER merges (ff-only or die), NEVER touches a dirty tree
# (loud refusal, because stashing someone else's WIP is how the 2026-08-23 worktree
# incident started), and NEVER invents an upstream (a session worktree with no upstream
# is reported, not guessed at). On a box with two clones (oldsrv: the ansible-admin
# runner clone that converges, the `domen` clone that authors — see
# docs/deployment-ansible.md §Runner placement) only the RUNNER clone is updated here.
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

PLAYBOOK="${1:?usage: ansible-run.sh <playbook> [--no-pull] [extra ansible-playbook args]}"
shift

# Consume our own flag before the args are handed to ansible-playbook.
PULL=1
_ARGS=()
for _a in "$@"; do
    case "$_a" in
        --no-pull) PULL=0 ;;
        *) _ARGS+=("$_a") ;;
    esac
done
set -- ${_ARGS[@]+"${_ARGS[@]}"}
case "$PLAYBOOK" in
    /*) ;;                                    # absolute path — use as-is
    IaC/*) PLAYBOOK="$REPO/$PLAYBOOK" ;;      # repo-relative
    *) PLAYBOOK="$REPO/IaC/ansible/$PLAYBOOK" ;;  # bare playbook name — runner default root
esac

cd "$REPO/IaC/ansible"

# --- Runner self-update (see the header; --no-pull opts out) --------------------------
if [ "$PULL" = "1" ]; then
    BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
    # Tracked changes only: untracked files (a stray __pycache__, an editor swap file,
    # the rendered docs a previous run left behind) must not block every converge.
    if [ -n "$(git -C "$REPO" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        echo "FAIL: $REPO has uncommitted changes — a runner converges a COMMITTED state." >&2
        echo "      Commit it in a session worktree (CONVENTIONS §6), or pass --no-pull to" >&2
        echo "      converge this working tree deliberately." >&2
        exit 1
    fi
    if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
        echo "NOTE: detached HEAD in $REPO — nothing to pull." >&2
    elif ! git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        echo "NOTE: branch '$BRANCH' has no upstream (a session worktree) — NOT pulling." >&2
    else
        echo "==> Runner self-update: git -C $REPO pull --ff-only"
        git -C "$REPO" pull --ff-only
    fi
else
    echo "NOTE: --no-pull — converging the working tree as-is." >&2
fi
echo "==> Converging $(git -C "$REPO" rev-parse --short HEAD) ($(git -C "$REPO" log -1 --format='%ad %s' --date=short))"

exec ansible-playbook -i inventory.ini "$PLAYBOOK" "$@"
