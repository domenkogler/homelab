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
#   bash scripts/git-bootstrap-win11.sh --git-identity # HD-495: make the UNATTENDED git
#       #      identity the seat default (no 1Password modals). Wired into
#       #      scripts/provision-win11.sh, so a fresh Win11 pi.dev seat gets it by default.
#   bash scripts/git-bootstrap-win11.sh --check    # report which route git will take
#   bash scripts/git-bootstrap-win11.sh --1password # opt BACK to the 1Password route
#
# The two identity modes are inverses; both back up every file they touch as
# <file>.bak-YYYYmmdd-HHMMSS first and are idempotent. WHY the default flipped (2026-10-07,
# owner decision): 1Password authorises an SSH key per PROCESS, pi starts a fresh shell per
# command, so the interactive config blocks on a consent dialog on every single git call —
# proven 2026-10-03 (commit signed 10.9 s, push 40.3 s, both with a window). The modal-free
# route and its four traps are documented in docs/deployment-secrets.md
# (§"What actually raises a 1Password prompt on the Win11 seat").
#
# Overridable env (bash shorthand):
#   SRC=$USERPROFILE/source · REPO = the checkout the script was invoked from, else $SRC/homelab
#     (REPOPATH=<path> overrides both — set it if the clone lives off $USERPROFILE, e.g. D:/source)
#   REMOTE=<github homelab url> · GITUSER / GITEMAIL (local-to-clone identity)
#   KEYDIR=$BASE/.ssh · NIGHTLY_SRC · GIT_BUNDLED_SSH · OP_SIGN (identity modes)
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
REMOTE="${REMOTE:-https://github.com/domenkogler/homelab.git}"
GITUSER="${GITUSER:-domenkogler}"
GITEMAIL="${GITEMAIL:-domen@kogler.si}"
MODE="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prefer the checkout the script was invoked FROM, then an explicit REPOPATH, then the
# $SRC default (which is what a brand-new box clones into). Without this, a repo that lives
# somewhere other than $USERPROFILE/source — e.g. D:/source/... — would get a second clone
# before the identity steps ran.
CASE="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
SRC="${SRC:-$BASE/source}"
REPO="${REPOPATH:-${CASE:-$SRC/homelab}}"
SIGNER="${OP_SIGN:-$BASE/AppData/Local/Microsoft/WindowsApps/op-ssh-sign.exe}"
# Windows OpenSSH (used by git as the transport; reaches the 1Password pipe).
WINSH="${GIT_SSH:-C:/Windows/System32/OpenSSH/ssh.exe}"
GFCFG="$BASE/.gitconfig-windows"
GITCFG="$BASE/.gitconfig"
# The unattended identity: repo payload -> ~/.gitconfig-nightly, included LAST from ~/.gitconfig.
NIGHTLY_SRC="${NIGHTLY_SRC:-$SCRIPT_DIR/git/gitconfig-nightly}"
NIGHTLY_CFG="$BASE/.gitconfig-nightly"
NIGHTLY_INCLUDE=".gitconfig-nightly"
# Git for Windows' own ssh: reads the PKCS#8 key FILES directly, so no agent is needed.
GITSH="${GIT_BUNDLED_SSH:-C:/PROGRA~1/Git/usr/bin/ssh.exe}"
KEYDIR="${KEYDIR:-$BASE/.ssh}"

# POSIX path -> Windows path with forward slashes (git config values are read by MSYS sh,
# which mangles C:\ and does not expand ~ in user.signingkey / sshCommand).
winpath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1" | tr '\\' '/'; else printf '%s' "${1//\\//}"; fi
}
WINHOME="$(winpath "$BASE")"   # diagnostics only (the config itself paths off __KEYDIR__)

# Back up a file before an in-place edit (O3-style: every mutation is preceded by a backup).
backup() {
  [ -f "$1" ] || return 0
  local b="$1.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$1" "$b"
  echo "    backup: $b"
}

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

# --- --check: which git identity route will this seat take? read-only ------------
if [ "$MODE" = "--check" ]; then
  echo "==> git identity route as resolved in $(pwd)"
  prog="$(git config --get gpg.ssh.program 2>/dev/null || true)"
  key="$(git config --get user.signingkey 2>/dev/null || true)"
  echo "    gpg.ssh.program = ${prog:-(absent)}"
  echo "    user.signingkey = ${key:-(absent)}"
  echo "    core.sshCommand = $(git config --get core.sshCommand 2>/dev/null || echo '(absent)')"
  echo "    includes         : $(git config --global --get-all include.path 2>/dev/null | tr '\n' ' ')(global) $(git config --file "$REPO/.git/config" --get-all include.path 2>/dev/null | tr '\n' ' ')(local)"
  if [ -z "$prog" ] && [ -n "$key" ] && [ -f "$key" ]; then
    echo "==> route: UNATTENDED — signs from a key file, no 1Password window possible"
  elif [ -n "$prog" ]; then
    echo "==> route: 1PASSWORD — every git call can block on a consent dialog"
    echo "    modal-free instead: bash scripts/git-bootstrap-win11.sh --git-identity"
  else
    echo "==> route: INCOMPLETE — commit signing will fail (signingkey does not resolve to a file)"
  fi
  exit 0
fi

# --- UNATTENDED git identity: the Win11 seat default (HD-495) -------------------
# Payload -> ~/.gitconfig-nightly, included LAST from ~/.gitconfig, and gpg.ssh.program
# removed everywhere it appears. The order is the whole mechanism: git cannot "unset" a key
# from a later include, so the program line has to go, and the per-remote includeIf blocks
# (.gitconfig-github -> user.signingkey = PUBLIC-KEY STRING) only lose because this include is
# appended after them.
install_unattended_identity() {
  [ -f "$NIGHTLY_SRC" ] || { echo "FAIL: payload not found: $NIGHTLY_SRC" >&2; exit 1; }
  [ -d "$KEYDIR" ] || { echo "FAIL: no key dir at $KEYDIR — run git-bootstrap-win11.sh --ssh-auth first,"
                        echo "      or copy the Homelab-ansible items from the vault (HD-495)." >&2; exit 1; }

  # 1. Install the payload with the seat's key dir and identity substituted.
  tmp="$NIGHTLY_CFG.tmp.$$"
  sed -e "s|__KEYDIR__|$(winpath "$KEYDIR")|g" -e "s|__GITUSER__|$GITUSER|g" -e "s|__GITEMAIL__|$GITEMAIL|g" \
      "$NIGHTLY_SRC" > "$tmp"
  grep -q '__KEYDIR__\|__GIT' "$tmp" && { echo "FAIL: placeholder survived substitution" >&2; rm -f "$tmp"; exit 1; }
  if [ -f "$NIGHTLY_CFG" ] && cmp -s "$tmp" "$NIGHTLY_CFG"; then
    echo "==> $NIGHTLY_CFG already current"
  else
    backup "$NIGHTLY_CFG"; mv "$tmp" "$NIGHTLY_CFG"; echo "==> installed $NIGHTLY_CFG"
  fi
  [ -f "$tmp" ] && rm -f "$tmp"
  for k in github_signing github_auth; do
    [ -f "$KEYDIR/$k" ] || echo "  !! $KEYDIR/$k missing — that half will fail closed (no dialog, just an error)" >&2
  done
  # Git for Windows' own ssh is the transport; System32's OpenSSH cannot read these key files.
  [ -e "$GITSH" ] || echo "  !! bundled ssh not at $GITSH — check git.core.sshCommand (auth will fail closed)" >&2

  # 2. Include it LAST from ~/.gitconfig (append -> new [include] section at EOF).
  if git config --global --get-all include.path 2>/dev/null | grep -qxF "$NIGHTLY_INCLUDE"; then
    echo "==> ~/.gitconfig already includes $NIGHTLY_INCLUDE"
  else
    backup "$GITCFG"; git config --global --add include.path "$NIGHTLY_INCLUDE"
    echo "==> ~/.gitconfig: appended [include] path = $NIGHTLY_INCLUDE (last -> wins)"
  fi

  # 3. gpg.ssh.program must be ABSENT, not empty (an empty value makes git spawn ""
  #    -> "cannot spawn : No such file or directory"; proven 2026-10-07).
  for f in "$GFCFG" "$GITCFG"; do
    if git config --file "$f" --get gpg.ssh.program >/dev/null 2>&1; then
      backup "$f"; git config --file "$f" --unset-all gpg.ssh.program
      echo "==> unset gpg.ssh.program in $f (was the modal)"
    fi
  done

  # 4. The repo's own .git/config outranks every global file: rewrite a public-key-string
  #    pin to the key FILE (git-bootstrap.sh wrote the string form; see pitfalls in
  #    docs/deployment-secrets.md).
  if [ -d "$REPO/.git" ]; then
    cur="$(git -C "$REPO" config --local --get user.signingkey 2>/dev/null || true)"
    want="$(winpath "$KEYDIR")/github_signing"
    case "$cur" in
      "") : ;;
      "$want") echo "==> $REPO: local user.signingkey already the key file" ;;
      *) backup "$REPO/.git/config"; git -C "$REPO" config --local user.signingkey "$want"
         echo "==> $REPO: local user.signingkey -> $want (was a public-key string = modal/no-sign)" ;;
    esac
  fi

  # 5. Fail closed if the seat did not end up on the modal-free route.
  prog="$(git config --get gpg.ssh.program 2>/dev/null || true)"
  key="$(git config --get user.signingkey 2>/dev/null || true)"
  [ -z "$prog" ] || { echo "FAIL: gpg.ssh.program still resolves to $prog" >&2; exit 1; }
  case "$key" in
    ssh-*) echo "FAIL: user.signingkey resolves to a public-key string ($key) — that is the modal route" >&2; exit 1 ;;
  esac
  [ -f "$key" ] || { echo "FAIL: user.signingkey resolves to $key, which is not a file" >&2; exit 1; }
  echo "==> route: UNATTENDED (signingkey=$key, gpg.ssh.program absent)"
  echo "    off switch: bash scripts/git-bootstrap-win11.sh --1password"
}

revert_to_1password() {
  [ -f "$GFCFG" ] || { echo "FAIL: $GFCFG not present; nothing to revert to" >&2; exit 1; }
  [ -f "$SIGNER" ] || echo "  !! signer not at $SIGNER — the dialog route will fail instead of prompting" >&2
  backup "$GFCFG"; git config --file "$GFCFG" gpg.ssh.program "$SIGNER"
  echo "==> .gitconfig-windows: gpg.ssh.program = $SIGNER"
  if git config --global --get-all include.path 2>/dev/null | grep -qxF "$NIGHTLY_INCLUDE"; then
    backup "$GITCFG"
    git config --global --unset include.path "^${NIGHTLY_INCLUDE//./\\.}$" \
      && echo "==> removed the $NIGHTLY_INCLUDE include" \
      || echo "  !! could not remove the include by regex; remove the [include] block by hand" >&2
  fi
  # With op-ssh-sign back, the signer looks the key up in the agent BY PUBLIC-KEY STRING;
  # a file path here makes it fail with "bad output from command" (measured 2026-10-03).
  pub="$(git config --file "$BASE/.gitconfig-github" --get user.signingkey 2>/dev/null \
        || (ls "$KEYDIR"/*.pub 2>/dev/null | head -1 | xargs -r cat))"
  if [ -n "$pub" ] && [ -d "$REPO/.git" ]; then
    backup "$REPO/.git/config"; git -C "$REPO" config --local user.signingkey "$pub"
    echo "==> $REPO: local user.signingkey -> public-key string (agent route)"
  fi
  echo "==> route: 1PASSWORD (a consent dialog may appear on the next git call)"
}

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

# --- identity modes run against a real clone (the clone block above made it) ------
case "$MODE" in
  --git-identity) install_unattended_identity; exit 0 ;;
  --1password)    revert_to_1password; exit 0 ;;
esac

# --- SSH auth + commit signing (HD-265): opt-in, idempotent, desktop-app path ----
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
  #    NOTE: this is the MODAL route — scripts/git-bootstrap-win11.sh --git-identity is the
  #    seat default and removes this key again (HD-495).
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