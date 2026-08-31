#!/usr/bin/env bash
# =====================================================================
# git-bootstrap.sh — Debian/WSL-side repo setup (ext4 primary)
#
# Purpose: make WSL Debian ext4 the PRIMARY source for pi.dev + Ansible
# runs + editing, instead of the slow /mnt/d (drvfs) mount. Idempotent.
#
# Usage:
#   bash scripts/git-bootstrap.sh           # clone (or no-op) + report
#   bash scripts/git-bootstrap.sh update               # force fetch + ff-only pull
#   bash scripts/git-bootstrap.sh pull                 # alias of update
#   bash scripts/git-bootstrap.sh --reload             # informational: no repo/network
#   bash scripts/git-bootstrap.sh --ssh-auth            # 1Password SSH auth + signing setup
#
# Overridable env (bash shorthand):
#   SRC=$HOME/source · REPO=$SRC/homelab · REPOPATH=$SRC/homelab · REMOTE=<github homelab url>
#   GITUSER / GITEMAIL (local-to-clone identity)
#   OP_VAULT=Private · OP_SIGN_ITEM="GitHub sign" · OP_AUTH_ITEM="GitHub auth"
#
# SSH auth + commit signing (HD-265, op CLI-only, no desktop app):
#   if `--ssh-auth` (or OP_SSH_AUTH=1) is passed, this idempotently
#   • ensures a HUMAN `op` sign-in (a Service Account can't read the Private vault),
#   • pulls the two GitHub SSH keys (sign + auth) from 1Password into ~/.ssh,
#   • adds them to the ssh-agent,
#   • flips origin from HTTPS to SSH (git@github.com), and
#   • configures commit signing (gpg.format=ssh + user.signingkey from the `key::` form).
#   Requires: git, op (Phase-0 prereq of bootstrap-runner.sh). Read-only pull needs no
#   GitHub auth; push + signing go over SSH with `--ssh-auth`.
#
# See ansible-enhancements.md §8.4 for the reasoning + caveats.
# Owner: user (this audit's proposal) — record in the owning doc if adopted.
# =====================================================================
set -euo pipefail

SRC="${SRC:-$HOME/source}"
REPO="${REPOPATH:-$SRC/homelab}"
REMOTE="${REMOTE:-https://github.com/domenkogler/homelab.git}"
GITUSER="${GITUSER:-domenkogler}"
GITEMAIL="${GITEMAIL:-domen@kogler.si}"
MODE="${1:-}"

# HD-265 SSH auth + signing (CLI-only, no desktop app). Keys live in the user's
# PRIVATE vault — a Service Account cannot reach it, so a human `op` sign-in is required.
OP_VAULT="${OP_VAULT:-Private}"
OP_SIGN_ITEM="${OP_SIGN_ITEM:-GitHub sign}"    # spaces kept literal (op read uses raw spaces, not %20)
OP_AUTH_ITEM="${OP_AUTH_ITEM:-GitHub auth}"    # spaces kept literal (op read uses raw spaces, not %20)

# Whether to also configure SSH auth + signing. Enabled by `--ssh-auth` mode, or
# by OP_SSH_AUTH=1. When absent it stays a no-op (safe against network/agent).
SSH_AUTH=0
if [ "$MODE" = "--ssh-auth" ]; then SSH_AUTH=1; MODE=""; fi
[ "${OP_SSH_AUTH:-}" = "1" ] && SSH_AUTH=1

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

# --- SSH auth + commit signing (HD-265): opt-in, idempotent, CLI-only ----------
# Requires a HUMAN 1Password sign-in (a Service Account can't read the Private vault).
if [ "$SSH_AUTH" = 1 ]; then
  echo "==> SSH auth/signing setup (CLI-only; needs a human 'op' sign-in)"
  command -v op >/dev/null 2>&1 || { echo "FAIL: op not installed — run scripts/bootstrap-runner.sh first" >&2; exit 1; }
  command -v ssh-add >/dev/null 2>&1 || { echo "FAIL: ssh-add not found" >&2; exit 1; }

  # 1. Human sign-in (idempotent). The SA session sees only Homelab-ansible, so a
  #    human session must be able to read the Private vault. A human account is configured
  #    via 'op account add --address <id>' + 'op signin' (interactive, ~30 min session).
  #    Allow override via OP_ACCOUNT (the human account shorthand or sign-in address).
  ACC="${OP_ACCOUNT:-}"
  if ! op vault list 2>/dev/null | grep -qi "^.*\bPrivate\b"; then
    echo "==> Need a human session that can read the Private vault."
    if [ -z "$ACC" ]; then
      echo "FAIL: no human 1Password account configured. Run:"
      echo "    op account add --address https://my.1password.eu   # then op signin"
      echo "  or set OP_ACCOUNT=<account-shorthand-or-address> and re-run." >&2
      exit 1
    fi
    op signin --account "$ACC" >/dev/null 2>&1 || true
    op vault list 2>/dev/null | grep -q "^.*\bPrivate\b" || {
      echo "FAIL: still can't read the Private vault after op signin --account '$ACC'." >&2; exit 1; }
  fi

  SSH_DIR="$HOME/.ssh"; mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"

  # 2. Pull the two GitHub keys from the Private vault (raw-space item + field names; see op read docs).
  SIGN_KEY="$SSH_DIR/github_signing"
  AUTH_KEY="$SSH_DIR/github_auth"
  echo "==> Reading 'GitHub sign' / 'GitHub auth' private keys from $OP_VAULT"
  op read "op://${OP_VAULT}/${OP_SIGN_ITEM}/private key" > "$SIGN_KEY" 2>/dev/null \
    || { echo "FAIL: could not read 'GitHub sign' private key from $OP_VAULT" >&2; exit 1; }
  chmod 600 "$SIGN_KEY"
  op read "op://${OP_VAULT}/${OP_AUTH_ITEM}/private key" > "$AUTH_KEY" 2>/dev/null \
    || { echo "FAIL: could not read 'GitHub auth' private key from $OP_VAULT" >&2; exit 1; }
  chmod 600 "$AUTH_KEY"

  # 3. Ensure an ssh-agent is reachable, then load both keys + derive public halves.
  #    Prefer the systemd per-user agent socket (see systemctl --user status ssh-agent); fall back
  #    to starting our own background agent when none is advertised.
  AGENT_SOCK="${SSH_AUTH_SOCK:-}"
  if [ -z "$AGENT_SOCK" ] || [ ! -S "$AGENT_SOCK" ]; then
    candidate="$(find /run/user/$(id -u) -maxdepth 2 -name openssh_agent 2>/dev/null | head -n1)"
    if [ -n "$candidate" ] && [ -S "$candidate" ]; then AGENT_SOCK="$candidate"; fi
  fi
  if [ -n "$AGENT_SOCK" ] && [ -S "$AGENT_SOCK" ]; then
    export SSH_AUTH_SOCK="$AGENT_SOCK"
  else
    eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
  fi
  ssh-add "$SIGN_KEY" 2>/dev/null || true
  ssh-add "$AUTH_KEY" 2>/dev/null || true
  ssh-keygen -y -f "$AUTH_KEY" > "$AUTH_KEY.pub" 2>/dev/null || true
  ssh-keygen -y -f "$SIGN_KEY" > "$SIGN_KEY.pub" 2>/dev/null || true

  # 4. ~/.ssh/config: force github.com to use the AUTH key (IdentitiesOnly).
  #    Create the config file if missing; only append the block once.
  touch "$SSH_DIR/config" 2>/dev/null || true
  if ! grep -q "Host github.com" "$SSH_DIR/config" 2>/dev/null; then
    cat >> "$SSH_DIR/config" <<EOF

Host github.com
    HostName github.com
    User git
    IdentityFile $AUTH_KEY
    IdentitiesOnly yes
EOF
    chmod 600 "$SSH_DIR/config"
  fi

  # 5. Flip origin HTTPS -> SSH (only the transport; never touches the working tree).
  cur="$(git remote get-url origin 2>/dev/null || true)"
  if [ -n "$cur" ] && [[ "$cur" == https://* ]]; then
    new="git@github.com:${cur#https://github.com/}"
    echo "==> origin: $cur  ->  $new"
    git remote set-url origin "$new"
  elif [ -n "$cur" ]; then
    echo "==> origin already SSH or other: $cur (leaving as-is)"
  fi

  # 6. Signing config (git uses the private key's public half as the signing key).
  if [ -s "$SIGN_KEY.pub" ]; then
    git config user.signingkey "key::$(awk '{print $1" "$2}' "$SIGN_KEY.pub")"
    git config gpg.format ssh
    git config commit.gpgsign true
    # allowed-signers so `git log --show-signature` can VERIFY our own signed commits.
    ALLOWED="$SSH_DIR/allowed_signers"
    touch "$ALLOWED" 2>/dev/null || true
    if ! grep -qF "$GITEMAIL" "$ALLOWED" 2>/dev/null; then
      printf '%s namespaces="git" %s\n' "$GITEMAIL" "$(awk '{print $1" "$2}' "$SIGN_KEY.pub")" >> "$ALLOWED"
    fi
    git config gpg.ssh.allowedSignersFile "$ALLOWED"
    echo "==> commit signing: gpg.format=ssh + GitHub sign key"
  else
    echo "!! no public half for GitHub sign key — skipping signing config" >&2
  fi

  echo "==> OK: SSH auth (github.com via GitHub auth) + commit signing (GitHub sign) configured."
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
  echo "==> Phase-0 not detected here; run scripts/bootstrap-runner.sh first"
  echo "    (installs ansible venv, op CLI, SA token, SSH key)."
else
  echo "==> Phase-0 present (venv + op SA token)."
fi

echo "==> Done. Next:"
echo "    # stage the changes by dropping into a session worktree first:"
echo "    git switch -c work/git-bootstrap   # or follow guard-session.sh"
echo "    bash scripts/ansible-run.sh playbooks/vps.yml --tags docker_services,headscale"