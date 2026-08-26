#!/usr/bin/env bash
# =====================================================================
# git-bootstrap.sh — Debian/WSL-side repo setup (ext4 primary)
#
# Purpose: make WSL Debian ext4 the PRIMARY source for pi.dev + Ansible
# runs + editing, instead of the slow /mnt/d (drvfs) mount. Idempotent.
#
# Usage:
#   bash scripts/git-bootstrap.sh                      # clone (or no-op) + report
#   bash scripts/git-bootstrap.sh update               # force fetch + ff-only pull
#   bash scripts/git-bootstrap.sh pull                 # alias of update
#   bash scripts/git-bootstrap.sh --reload             # informational: no repo/network
#
# Overridable env (bash shorthand):
#   SRC=$HOME/source · REPO=$SRC/homelab · REMOTE=<github homelab url>
#   GITUSER / GITEMAIL (local-to-clone identity)
#
# Requires: git (a Phase-0 prereq of bootstrap.sh). Read-only pull needs no
# GitHub auth on a public repo; push needs a credential helper / token.
#
# See ansible-enhancements.md §8.4 for the reasoning + caveats.
# Owner: user (this audit's proposal) — record in changelog if adopted.
# =====================================================================
set -euo pipefail

SRC="${SRC:-$HOME/source}"
REPO="${REPOPATH:-$SRC/homelab}"
REMOTE="${REMOTE:-https://github.com/domenkogler/homelab.git}"
GITUSER="${GITUSER:-domenkogler}"
GITEMAIL="${GITEMAIL:-domen@kogler.si}"
MODE="${1:-}"

# --- --reload: informational only, never touches repo/network --------------
if [ "$MODE" = "--reload" ]; then
  echo "==> git-bootstrap (SRC=$SRC REPO=$REPO) — informational mode"
  if [ ! -d "$REPO/.git" ]; then
    echo "    repo not present at $REPO; run: bash scripts/git-bootstrap.sh"
  else
    echo "    repo present; run: bash scripts/git-bootstrap.sh update"
  fi
  echo "    then: bash scripts/ansible-run.sh playbooks/vps.yml --tags docker_services,headscale"
  exit 0
fi

echo "==> git-bootstrap (SRC=$SRC REPO=$REPO)"
mkdir -p "$SRC"

# --- clone if absent (any non-reload mode) ----------------------------------
if [ ! -d "$REPO/.git" ]; then
  echo "==> Cloning $REMOTE -> $REPO"
  git clone "$REMOTE" "$REPO"
else
  echo "==> Repo present at $REPO"
fi

cd "$REPO"

# Idempotent local identity (scoped to this clone; never global).
git config user.name  "$GITUSER"
git config user.email "$GITEMAIL"

# Branch awareness + session-discipline nudge (CONVENTIONS §6 / guard-session.sh).
current="$(git branch --show-current)"
if [ "$current" = "main" ]; then
  echo "==> On main. Reminder: edit in a session worktree, not here (CONVENTIONS §6)."
else
  echo "==> On branch: $current"
fi

# --- sync (fetch + ff-only pull) only when explicitly requested -------------
if [ "$MODE" = "update" ] || [ "$MODE" = "pull" ]; then
  echo "==> git fetch + ff-only pull origin/main"
  git fetch origin
  git pull --ff-only origin main \
    || echo "!! pull stopped (local commits / uncommitted changes) — resolve manually"
fi

# --- Phase-0 sanity helper (venv + op SA token) — informational, not a gate --
if [ ! -d "$HOME/ansible-venv" ] || [ ! -f "$HOME/.config/op/homelab-sa-token" ]; then
  echo "==> Phase-0 not detected here; run IaC/bootstrap-ansible-client/bootstrap.sh first"
  echo "    (installs ansible venv, op CLI, SA token, SSH key)."
else
  echo "==> Phase-0 present (venv + op SA token)."
fi

echo "==> Done. Next:"
echo "    # stage the changes by dropping into a session worktree first:"
echo "    git switch -c work/git-bootstrap   # or follow guard-session.sh"
echo "    bash scripts/ansible-run.sh playbooks/vps.yml --tags docker_services,headscale"