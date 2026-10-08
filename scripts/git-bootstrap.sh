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
#   OP_VAULT=Homelab-ansible · OP_SIGN_ITEM="GitHub sign" · OP_AUTH_ITEM="GitHub auth"
#
# SSH auth + commit signing (HD-265, op CLI-only, no desktop app):
#   if `--ssh-auth` (or OP_SSH_AUTH=1) is passed, this idempotently
#   • requires a session that can READ the vault holding the keys — since HD-495 that is
#     `Homelab-ansible`, so the Phase-0 read-scope Service Account token is enough and no
#     interactive `op signin` is needed (it used to be the blocker: the keys sat in `Private`,
#     which an SA cannot read, which is what made seat signing owner-gated),
#   • pulls the two GitHub SSH keys (sign + auth) from 1Password into ~/.ssh,
#   • adds them to the ssh-agent,
#   • flips origin from HTTPS to SSH (git@github.com), and
#   • configures commit signing (gpg.format=ssh + user.signingkey; the form is CHOSEN, see 6).
#   Requires: git, op (Phase-0 prereq of bootstrap-runner.sh). Read-only pull needs no
#   GitHub auth; push + signing go over SSH with `--ssh-auth`.
#
# See CONVENTIONS §6 (worktree/merge-station discipline) + deployment-manual.md §0.1 (ext4 primary) for the reasoning.
# Owner: user (this audit's proposal) — record in the owning doc if adopted.
# =====================================================================
set -euo pipefail

if [ "${1:-}" = "--self-test" ]; then
  SELF=$(cd "$(dirname "$0")" && pwd)/git-bootstrap.sh
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  # SANDBOX, not decoration: a child that gets PAST the vault check goes on to write
  # $HOME/.ssh/github_signing and rewrite the clone's `origin` URL. So HOME and SRC are both
  # redirected and the "repo" is a throwaway `git init` — nothing under the real $HOME or the
  # real clone is reachable from here.
  mkdir -p "$TMP/home" "$TMP/src"
  git init -q "$TMP/src/homelab"
  run() { PATH="$1:$PATH" HOME="$TMP/home" SRC="$TMP/src" \
              XDG_RUNTIME_DIR="/run/user/$(id -u)" OP_VAULT="${3:-}" \
              bash "$SELF" --ssh-auth 2>&1 || true; }
  mk() { mkdir -p "$TMP/$1"; printf '#!/bin/sh\ncase "$1 $2" in\n%s\nesac\n' "$2" > "$TMP/$1/op"; chmod +x "$TMP/$1/op"; }
  ACCT='"account list") echo "SHORTHAND    URL"; echo "my           https://my.1password.eu"; exit 0;;'
  # signed out — op refuses, but the account IS on disk (real op lists accounts either way)
  mk signedout "  \"vault list\") echo '[ERROR] You are not currently signed in.' >&2; exit 1;;
    $ACCT"
  # no account configured at all — real op says THIS, not "not signed in", and the branch order
  # depends on the difference (my first fixture faked the wrong message and the test went red)
  mk noacct "  \"vault list\") echo '[ERROR] No accounts configured for use with 1Password CLI.' >&2; exit 1;;
    \"account list\") exit 0;;"
  # a witness `op` for the runtime-dir guard: if the script reaches it, the guard did not fire first
  mk noop "  *) echo 'OP-WAS-CALLED'; exit 0;;"
  # signed in as the WRONG identity: answers fine, sees one vault that is NOT the target.
  # ⚠ Two ways this case goes vacuous; both were measured here, not reasoned about:
  #  1. The decoy may not be the target vault. It used to be `Homelab-ansible` while the target was
  #     `Private`; HD-495 moved the target, so the fixture would then show the very vault it claims
  #     is invisible. Verified: with the decoy set to the target, this case goes RED (rc 1).
  #  2. `run()` must NOT default OP_VAULT itself. It carried `${3:-Private}`, which pinned every
  #     refusal case to the pre-HD-495 default — with that pin in place the SAME mutation stayed
  #     GREEN, i.e. the harness was testing a default the script no longer has. It now passes
  #     `${3:-}` so the child resolves its own production default.
  mk wrongvault "  \"vault list\") echo 'ID                            NAME'
    echo 'nv2tq7d4bfglpe6az3icxuvymk    Personal'; exit 0;;
    $ACCT"
  # canary fixture: the target vault IS visible, but the key read fails — proves the vault check
  # is live (the child gets past it) while stopping before anything could be written as a key
  mk vaultok "  \"vault list\") echo 'Homelab-ansible'; exit 0;;
    $ACCT
    \"read\") exit 1;;"
  fails=0
  check() { # <fixture> <expected> <must-not-say>
    out=$(run "$TMP/$1" "" "${3:-}")
    printf '%s' "$out" | grep -qi "$2" \
      || { echo "SELFTEST FAIL [$1]: expected /$2/ — got: $(printf '%s' "$out" | tail -3)"; fails=$((fails+1)); }
    if [ -n "${4:-}" ] && printf '%s' "$out" | grep -qi "$4"; then
      echo "SELFTEST FAIL [$1]: must NOT say /$4/ — a misreporting diagnostic sent the operator into an 'op signin' loop"
      fails=$((fails+1))
    fi
  }
  check signedout   "has no session"              ""  "no human 1Password account"
  check noacct      "no human 1Password account"  ""
  check wrongvault  "vault is NOT among"          ""  "has no session"
  # the runtime-dir guard must fire BEFORE any op call. PATH keeps a real shell (a bare
  # PATH=/nonexistent breaks `bash` itself, which is how the first draft of this case failed) and
  # supplies a witness op: reaching it would print OP-WAS-CALLED.
  # ⚠ The stripped PATH must still carry `git`, which the throwaway clone above needs. Hardcoding
  #   `/usr/bin:/bin` is a Debian-ism: on Git-Bash `git` lives in `/mingw64/bin`, so the child died
  #   `git: command not found` at the first `git config` and this case reported a PATH failure as a
  #   guard failure (measured 2026-10-07 on the Win11 seat: SELFTEST FAIL [xdg-guard] got "Repo
  #   present at …"). The `dirname` of the real `git` is `/usr/bin` on Debian, so this adds nothing
  #   there; when `git` is absent it degrades to `/usr/bin` rather than `.` (no CWD on the PATH).
  GITDIR=$(dirname "$(command -v git 2>/dev/null || echo /usr/bin/git)")
  out=$(run "$TMP/noop" "" "")
  out=$(PATH="$TMP/noop:/usr/bin:/bin:$GITDIR" HOME="$TMP/home" SRC="$TMP/src" XDG_RUNTIME_DIR="/run/user/999999" \
        bash "$SELF" --ssh-auth 2>&1 || true)
  printf '%s' "$out" | grep -qi "XDG_RUNTIME_DIR is" \
    || { echo "SELFTEST FAIL [xdg-guard]: expected the runtime-dir refusal — got: $(printf '%s' "$out" | tail -2)"; fails=$((fails+1)); }
  printf '%s' "$out" | grep -q "OP-WAS-CALLED" \
    && { echo "SELFTEST FAIL [xdg-guard]: the guard let the script reach op first"; fails=$((fails+1)); }
  # canary: with the target vault visible the refusal must DISAPPEAR (a check that always fires
  # would pass all three assertions above while checking nothing)
  out=$(run "$TMP/vaultok" "" "Homelab-ansible")
  if printf '%s' "$out" | grep -qi "vault is NOT among"; then
    echo "SELFTEST FAIL [canary]: the vault check refuses a vault it can see — the check is dead"
    fails=$((fails+1))
  fi
  if [ -e "$TMP/home/.ssh/github_signing" ] && [ -s "$TMP/home/.ssh/github_signing" ]; then
    echo "SELFTEST FAIL [sandbox]: a non-empty key file escaped into the sandbox home"
    fails=$((fails+1))
  fi
  if [ "$fails" = 0 ]; then
    echo "SELFTEST OK: git-bootstrap refuses each state with the right message (5 cases, sandboxed)"
    exit 0
  fi
  exit 1
fi


SRC="${SRC:-$HOME/source}"
REPO="${REPOPATH:-$SRC/homelab}"
REMOTE="${REMOTE:-https://github.com/domenkogler/homelab.git}"
GITUSER="${GITUSER:-domenkogler}"
GITEMAIL="${GITEMAIL:-domen@kogler.si}"
MODE="${1:-}"

# HD-265 SSH auth + signing (CLI-only, no desktop app). HD-495 (2026-10-06, owner): both
# GitHub keys moved from the `Private` vault into `Homelab-ansible`, so the read-scope
# Service Account token a Phase-0 runner already carries can pull them — a human `op signin`
# is no longer part of this path on any Debian seat. `Private` still works as an override for a
# machine that was set up before the move.
OP_VAULT="${OP_VAULT:-Homelab-ansible}"
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

# --- SSH auth + commit signing (HD-265/HD-495): opt-in, idempotent, CLI-only ----
# Needs a session that can read $OP_VAULT. That is either the read-scope SA token (the normal
# runner/seat case since HD-495) or a human sign-in — whichever can see the vault wins.
# --- --self-test: the three refusal states, each bred by a fixture -------------
# Why this exists rather than a prose note: the ORIGINAL failure was a message that described the
# wrong state ("no human 1Password account configured" while `op account list` showed one, because
# one grep was answering two questions). A diagnostic that misreports is worse than none — it sent
# the operator to re-run `op signin` in a loop. So each state gets a fixture and an assertion.
if [ "$SSH_AUTH" = 1 ]; then
  echo "==> SSH auth/signing setup (CLI-only; needs a session that can read $OP_VAULT)"
  command -v op >/dev/null 2>&1 || { echo "FAIL: op not installed — run scripts/bootstrap-runner.sh first" >&2; exit 1; }
  command -v ssh-add >/dev/null 2>&1 || { echo "FAIL: ssh-add not found" >&2; exit 1; }

  # 1. Any identity that can read $OP_VAULT is accepted: the SA token (one vault, exactly
  #    Homelab-ansible) or a human session. A human account, when one is used, is configured via
  #    'op account add --address <id>' + 'op signin' (interactive, ~30 min session).
  #    Allow override via OP_ACCOUNT (the human account shorthand or sign-in address).
  ACC="${OP_ACCOUNT:-}"
  # Preflight the runtime dir BEFORE anything touches `op`: the CLI needs to write its daemon
  # pid/socket under $XDG_RUNTIME_DIR, and a session that inherited another user's (a `su` from the
  # ansible runner identity leaves it pointing at /run/user/<other-uid>, mode 700) fails with
  # `couldn't start daemon: … permission denied`. Sign-in can then NEVER succeed, and the real
  # reason is a file permission, so nothing downstream can diagnose it.
  WANT_XDG="/run/user/$(id -u)"
  if [ "${XDG_RUNTIME_DIR:-}" != "$WANT_XDG" ]; then
    echo "FAIL: XDG_RUNTIME_DIR is '${XDG_RUNTIME_DIR:-<unset>}', but this shell runs as uid $(id -u)." >&2
    echo "      1Password CLI cannot start its daemon there, so 'op signin' cannot work. Fix it first:"
    echo "        export XDG_RUNTIME_DIR=$WANT_XDG" >&2
    exit 1
  fi

  # Three states, three messages — collapsed into one they lie. Measured 2026-10-01: a signed-in
  # human session that could see only `Homelab-ansible` got reported as "no account configured",
  # then as "no session token", and both sent the operator off to re-sign-in forever.
  # NB: greps $OP_VAULT, not a literal 'Private' — the vault name is overridable, so a correct
  # `OP_VAULT=<other> --ssh-auth` used to be refused by a hardcoded test.
  VAULT_SEEN="$(op vault list 2>&1)" || true
  if ! printf '%s' "$VAULT_SEEN" | grep -qi "\b${OP_VAULT}\b"; then
    echo "==> Need a session that can read the '$OP_VAULT' vault (override with OP_VAULT=<name>)."
    # ORDER MATTERS: test the session text we already hold BEFORE `op account list`, because that
    # subcommand's table header is a version/locale-fragged string — keying on it first made a plain
    # signed-out state print "no account configured" (caught by the fixture matrix, not by reading).
    if printf '%s' "$VAULT_SEEN" | grep -qi "not currently signed in\|not signed in"; then
      echo "FAIL: an account IS configured, but this context has no session." >&2
      printf '%s\n' "$VAULT_SEEN" | sed 's/^/      op: /' >&2 || true
      echo "      Sign in IN THIS SHELL (an interactive password/2FA prompt cannot be answered from"
      echo "      a non-interactive context):"
      echo '        eval "$(op signin --account '"${ACC:-my}"')"'
      echo "      then re-run: bash scripts/git-bootstrap.sh --ssh-auth" >&2
      exit 1
    fi
    if ! op account list 2>/dev/null | grep -qi "SHORTHAND\|1password"; then
      echo "FAIL: no human 1Password account configured on this machine. Run:"
      echo "    op account add --address https://my.1password.eu   # then: eval \"\$(op signin)\""
      echo "  or set OP_ACCOUNT=<account-shorthand-or-address> and re-run." >&2
      exit 1
    fi
    echo "FAIL: signed in, but the '$OP_VAULT' vault is NOT among the vaults this identity can see." >&2
    printf '%s\n' "$VAULT_SEEN" | sed 's/^/      op: /' >&2 || true
    echo "      A read-scope Service Account sees exactly one vault and cannot read the private one,"
    echo "      so a visible-but-wrong vault list means the SERVICE ACCOUNT is answering, not the human"
    echo "      session. Check this context: env | grep -c OP_SERVICE_ACCOUNT_TOKEN"
    echo "      (unset it here, or sign in as the human account that holds '$OP_VAULT')." >&2
    exit 1
  fi

  SSH_DIR="$HOME/.ssh"; mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"

  # 2. Pull the two GitHub keys from the vault (raw-space item + field names; see op read docs).
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

  # 6. Signing config. THE FORM IS CHOSEN, NOT HARDCODED (measured 2026-10-06, git 2.47.3, both
  #    halves in a throwaway repo): `user.signingkey=key::<pub>` asks the ssh-agent and dies in
  #    every shell without SSH_AUTH_SOCK — `error: Couldn't get agent socket?` + `fatal: failed to
  #    write commit object` — which is every non-interactive shell (pi, cron, a converge, a cron'd
  #    `git fetch`). A FILE PATH signs with no agent at all (`%G?` → G). So: unencrypted key →
  #    file path; passphrase-protected key → the `key::` form, because ssh-keygen would otherwise
  #    block on a prompt that no non-interactive shell can answer.
  if [ -s "$SIGN_KEY.pub" ]; then
    if ssh-keygen -y -P '' -f "$SIGN_KEY" >/dev/null 2>&1; then
      git config user.signingkey "$SIGN_KEY"
      echo "==> commit signing: user.signingkey = the key file (agent-free; works in any shell)"
    else
      git config user.signingkey "key::$(awk '{print $1" "$2}' "$SIGN_KEY.pub")"
      echo "==> commit signing: key:: form — the key has a passphrase, so an agent is REQUIRED"
    fi
    git config gpg.format ssh
    # Commit signing RETIRED 2026-10-08 (HD-1116, owner decision): the key is gone from GitHub,
    # so signing would hang the next non-interactive committer (cron, a converge, pi's bash).
    # The key files and the form choice above are kept: if a key is ever re-registered, this
    # line is the one thing that flips back.
    git config commit.gpgsign false
    # allowed-signers so `git log --show-signature` can VERIFY our own signed commits.
    ALLOWED="$SSH_DIR/allowed_signers"
    touch "$ALLOWED" 2>/dev/null || true
    if ! grep -qF "$GITEMAIL" "$ALLOWED" 2>/dev/null; then
      printf '%s namespaces="git" %s\n' "$GITEMAIL" "$(awk '{print $1" "$2}' "$SIGN_KEY.pub")" >> "$ALLOWED"
    fi
    git config gpg.ssh.allowedSignersFile "$ALLOWED"
    echo "==> allowed-signers: $ALLOWED (without it git reports N on signed commits)"
    echo "    note: this writes the CLONE's config; worktrees share it, other repos need"
    echo "          'git config --global' equivalents (the oldsrv seat carries a global ~/.gitconfig)."
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