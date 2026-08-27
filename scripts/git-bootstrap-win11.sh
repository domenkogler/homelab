#!/usr/bin/env bash
# =====================================================================
# git-bootstrap-win11.sh — Windows 11-side repo setup (git-bash / MSYS)
#
# Purpose: Win11 mirror of scripts/git-bootstrap.sh. The Windows transport
# differs from WSL/Debian in one key way: instead of pulling SSH keys out of
# 1Password via the `op` CLI, here the **1Password desktop app** holds the
# keys and runs its own SSH agent over the Windows named pipe
# `\\.\pipe\openssh-ssh-agent`. We only have to point git at **Windows
# OpenSSH** so it reaches that pipe. Idempotent.
#
# Why no ~/.ssh/config Host block here:
#   - Transport: git uses Windows OpenSSH (core.sshCommand) → named-pipe
#     agent → 1Password app. No IdentityFile / IdentityAgent line needed.
#   - Signing: gpg.ssh.program = op-ssh-sign.exe (the desktop app's signer),
#     and user.signingkey resolves from .gitconfig-github via includeIf
#     (fires once origin is an SSH url). No Host block involved.
#
# Usage:
#   bash scripts/git-bootstrap-win11.sh           # clone (or no-op) + report
#   bash scripts/git-bootstrap-win11.sh update     # force fetch + ff-only pull
#   bash scripts/git-bootstrap-win11.sh pull       # alias of update
#   bash scripts/git-bootstrap-win11.sh --reload   # informational: no repo/network
#   bash scripts/git-bootstrap-win11.sh --ssh-auth # wire 1Password SSH agent + signing
#
# Overridable env (bash shorthand):
#   SRC=$USERPROFILE/source · REPO=$SRC/homelab · REMOTE=<github homelab url>
#   GITUSER / GITEMAIL (local-to-clone identity)
#   OP_SIGN / OP_AUTH are NOT read here (desktop app owns the keys)
#
# SSH auth + commit signing (HD-265, desktop-app path, no `op` key-pull):
#   with `--ssh-auth`, ensures
#   • git uses Windows OpenSSH (core.sshCommand = C:/Windows/System32/OpenSSH/ssh.exe),
#   • .gitconfig-windows carries gpg.ssh.program = op-ssh-sign.exe,
#   • origin is flipped HTTPS -> SSH (git@github.com) so the .gitconfig-github
#     includeIf (gpg.format=ssh / commit.gpgsign / user.signingkey) fires,
#   • and reports 1Password-agent reachability.
#   Requires: git, Windows OpenSSH, and the 1Password desktop app **with the
#   SSH agent toggled ON** (Settings -> Developer -> "Use the SSH agent").
# =====================================================================
set -euo pipefail

# Windows-native home (git-bash $HOME usually == $USERPROFILE, but be explicit).
BASE="${USERPROFILE:-$HOME}"
SRC="${SRC:-$BASE/source}"
REPO="${REPOPATH:-$SRC/homelab}"
REMOTE="${REMOTE:-https://github.com/domenkogler/homelab.git}"
GITUSER="${GITUSER:-domenkogler}"
GITEMAIL="${GITEMAIL:-domen@kogler.si}"
MODE="${1:-}"

# Windows OpenSSH (used by git as the transport; reaches the 1Password pipe).
WINSH="${GIT_SSH:-C:/Windows/System32/OpenSSH/ssh.exe}"
GFCFG="$BASE/.gitconfig-windows"

SSH_AUTH=0
if [ "$MODE" = "--ssh-auth" ]; then SSH_AUTH=1; MODE=""; fi
[ "${OP_SSH_AUTH:-}" = "1" ] && SSH_AUTH=1

# --- --reload: informational only, never touches repo/network --------------
if [ "$MODE" = "--reload" ]; then
  echo "==> git-bootstrap-win11 (SRC=$SRC REPO=$REPO) — informational mode"
  if [ ! -d "$REPO/.git" ]; then
    echo "    repo not present at $REPO; run: bash scripts/git-bootstrap-win11.sh"
  else
    echo "    repo present; run: bash scripts/git-bootstrap-win11.sh update"
  fi
  echo "    then: bash scripts/ansible-run.sh playbooks/vps.yml --tags docker_services,headscale"
  exit 0
fi

echo "==> git-bootstrap-win11 (SRC=$SRC REPO=$REPO)"
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

# --- SSH auth + commit signing (HD-64): opt-in, idempotent, desktop-app path ----
if [ "$SSH_AUTH" = 1 ]; then
  echo "==> SSH auth/signing setup (1Password desktop agent; no op key-pull)"
  command -v "$WINSH" >/dev/null 2>&1 || [ -f "/c/Windows/System32/OpenSSH/ssh.exe" ] || {
    echo "FAIL: Windows OpenSSH not found at $WINSH" >&2; exit 1; }

  # 1. Ensure .gitconfig-windows sets core.sshCommand to Windows OpenSSH.
  #    (Reaches the 1Password named pipe \\.\pipe\openssh-ssh-agent automatically.)
  if ! git config --file "$GFCFG" --get core.sshCommand >/dev/null 2>&1; then
    git config --file "$GFCFG" core.sshCommand "$WINSH"
    echo "==> .gitconfig-windows: core.sshCommand = $WINSH"
  else
    echo "==> .gitconfig-windows: core.sshCommand already set ($(git config --file "$GFCFG" --get core.sshCommand))"
  fi

  # 2. Ensure .gitconfig-windows points gpg.ssh.program at the 1Password signer.
  SIGNER="$BASE/AppData/Local/Microsoft/WindowsApps/op-ssh-sign.exe"
  if ! git config --file "$GFCFG" --get gpg.ssh.program >/dev/null 2>&1; then
    git config --file "$GFCFG" gpg.ssh.program "$SIGNER"
    echo "==> .gitconfig-windows: gpg.ssh.program = $SIGNER"
  else
    echo "==> gpg.ssh.program already set ($(git config --file "$GFCFG" --get gpg.ssh.program))"
  fi

  # 3. Flip origin HTTPS -> SSH so the .gitconfig-github includeIf fires.
  cur="$(git remote get-url origin 2>/dev/null || true)"
  case "$cur" in
    https://github.com/*)
      new="git@github.com:${cur#https://github.com/}"
      echo "==> origin: $cur  ->  $new"
      git remote set-url origin "$new" ;;
    git@*)
      echo "==> origin already SSH: $cur (leaving as-is)" ;;
    *)
      echo "!! origin has no recognizable github url (${cur:-unset}); set REMOTE manually" >&2 ;;
  esac

  # 4. Reachability check for the 1Password SSH agent via Windows OpenSSH.
  echo "==> Testing agent against github.com ..."
  rc=0
  "$WINSH" -T git@github.com >/dev/null 2>&1 || rc=$?
  if [ "$rc" -le 1 ]; then
    echo "==> SSH agent OK: authenticated as git@github.com (rc=$rc)"
  else
    echo "  !! ssh -T git@github.com FAILED (rc=$rc). Toggle the agent:"
    echo "     1Password -> Settings -> Developer -> Use the SSH agent"
    echo "      (and ensure the GitHub keys are 1Password SSH-key items)." >&2
  fi

  # 5. Signing: report resolved settings (driven by includeIf on the SSH remote).
  echo "==> signing config: gpgsign=$(git config --get commit.gpgsign || echo '(unset)')"
  echo "             format=$(git config --get gpg.format || echo '(unset)')"
  echo "        signingkey  =$(git config --get user.signingkey || echo '(unset)')"
fi

# --- sync (fetch + ff-only pull) only when explicitly requested -------------
if [ "$MODE" = "update" ] || [ "$MODE" = "pull" ]; then
  echo "==> git fetch + ff-only pull origin/main"
  git fetch origin
  git pull --ff-only origin main \
    || echo "!! pull stopped (local commits / uncommitted changes) — resolve manually"
fi

echo "==> Done."