#!/usr/bin/env bash
# =====================================================================
# git-bootstrap-win11.sh — Windows 11-side repo setup (git-bash / MSYS)
#
# Purpose: Win11 mirror of scripts/git/git-bootstrap.sh. The Windows transport
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
#   bash scripts/git/git-bootstrap-win11.sh           # clone (or no-op) + report
#   bash scripts/git/git-bootstrap-win11.sh update     # force fetch + ff-only pull
#   bash scripts/git/git-bootstrap-win11.sh pull       # alias of update
#   bash scripts/git/git-bootstrap-win11.sh --reload   # informational: no repo/network
#   bash scripts/git/git-bootstrap-win11.sh --ssh-auth # wire 1Password SSH agent + signing
#   bash scripts/git/git-bootstrap-win11.sh --git-identity # HD-495: make the UNATTENDED git
#       #      identity the seat default (no 1Password modals), raising the transport key from
#       #      the vault if the seat has never had one. Wired into scripts/provision-win11.sh, so
#       #      a fresh Win11 pi.dev seat gets it by default.
#   bash scripts/git/git-bootstrap-win11.sh --raise-key # plant ~/.ssh/github_auth from the vault
#       #      (temp file, parse-verified, never over an existing key) and report by fingerprint
#   bash scripts/git/git-bootstrap-win11.sh --check    # report which route git will take
#   bash scripts/git/git-bootstrap-win11.sh --1password # opt BACK to the 1Password route
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
#   OP_VAULT=Homelab-ansible · OP_AUTH_ITEM="GitHub auth" — read by the RAISE path only (the
#     modal-free seat default, which plants the transport key file). The desktop-app `--ssh-auth`
#     route reads neither: there the app holds the key and serves it on the named pipe.
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
# Resolved against the REPO, not `$SCRIPT_DIR/git/`: HD-1118 Stage 3 moved this installer INTO
# scripts/git/, which would have made `$SCRIPT_DIR/git/gitconfig-nightly` point at a scripts/git/git/
# that never exists — and because this is an env-overridable default, the failure surfaces on a
# from-zero Windows seat as "payload not found", not in any gate here.
NIGHTLY_SRC="${NIGHTLY_SRC:-$REPO/scripts/git/gitconfig-nightly}"
NIGHTLY_CFG="$BASE/.gitconfig-nightly"
NIGHTLY_INCLUDE=".gitconfig-nightly"
# The payload is included PER REMOTE, not globally. A plain [include] would hand its
# core.sshCommand (which pins ~/.ssh/github_auth and IdentityAgent=none) to EVERY remote this box
# knows — ~/.gitconfig carries includeIf blocks for git.stroka.si and git.kogler.si, and those legs
# authenticate with a credential helper, not with this key. The pattern is the same hasconfig: one
# the .gitconfig-github block already uses, so the payload still lands last for github remotes.
# Always used quoted: the globbing characters must reach git verbatim.
NIGHTLY_MATCH='hasconfig:remote.*.url:*github.com*/**'
NIGHTLY_INCLUDE_KEY="includeIf.$NIGHTLY_MATCH.path"
# Git for Windows' own ssh: reads the PKCS#8 key FILES directly, so no agent is needed.
GITSH="${GIT_BUNDLED_SSH:-C:/PROGRA~1/Git/usr/bin/ssh.exe}"
KEYDIR="${KEYDIR:-$BASE/.ssh}"
OP_VAULT="${OP_VAULT:-Homelab-ansible}"
OP_AUTH_ITEM="${OP_AUTH_ITEM:-GitHub auth}"   # raw spaces: `op read` uses them, not %20

# ---- the ONE vault-credential resolution this script uses (lib/vault-env.sh) --------------------
# The seat's read-scope token is a `0600` FILE whose path the lib owns, never an environment
# variable, and `op` reads only the environment. On THIS seat the lib has a third source: the Debian
# engine's install, read across the WSL door — so the Windows disk keeps holding no credential of
# its own and a rotation reaches this box through the engine's install. Resolution order and the
# CR/quote parse belong to that lib, never to this file.
HL_LIB_DIR=""
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ -n "$_hl_d" ] && [ "$_hl_d" != / ] && [ ! -f "$_hl_d/lib/vault-env.sh" ]; do
  _hl_n="${_hl_d%/*}"; [ "$_hl_n" = "$_hl_d" ] && _hl_n="/"; _hl_d="$_hl_n"
done
[ -n "${_hl_d:-}" ] && [ -f "$_hl_d/lib/vault-env.sh" ] && HL_LIB_DIR="$_hl_d"
HL_VAULT_RESOLVED=0
hl_vault_ask() {
  [ -n "$HL_LIB_DIR" ] || return 1
  [ "$HL_VAULT_RESOLVED" = 1 ] && return 0
  # shellcheck disable=SC1091
  . "$HL_LIB_DIR/lib/vault-env.sh"
  if hl_vault_env; then HL_VAULT_RESOLVED=1; return 0; fi
  return 1
}

# POSIX path -> Windows path with forward slashes (git config values are read by MSYS sh,
# which mangles C:\ and does not expand ~ in user.signingkey / sshCommand).
winpath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1" | tr '\\' '/'; else printf '%s' "${1//\\//}"; fi
}
WINHOME="$(winpath "$BASE")"   # diagnostics only (the config itself paths off __KEYDIR__)

# Back up a file before an in-place edit (O3-style: every mutation is preceded by a backup).
# The first backup of a second wins: one run can edit ~/.gitconfig more than once inside the same
# second, and overwriting the earlier copy would throw away the pristine state.
backup() {
  [ -f "$1" ] || return 0
  local b="$1.bak-$(date +%Y%m%d-%H%M%S)"
  [ -e "$b" ] && return 0
  cp -p "$1" "$b"
  echo "    backup: $b"
}

# Is the payload wired into ~/.gitconfig, and by which form? `if` = the per-remote includeIf this
# script appends (HD-1126); `plain` = a bare [include] left by a pre-HD-1126 run, which leaks the
# github-only transport onto every remote. Defined before --check, which is the first caller.
nightly_included() {
  case "$1" in
    if)    git config --global --get-all "$NIGHTLY_INCLUDE_KEY" 2>/dev/null | grep -qxF "$NIGHTLY_INCLUDE" ;;
    plain) git config --global --get-all include.path           2>/dev/null | grep -qxF "$NIGHTLY_INCLUDE" ;;
  esac
}

# The route verdict, as a function, so `--check`, `--git-identity`'s own fail-closed assertion and
# the self-test all answer from ONE implementation. The question is "will a git call on this box ever
# wait for a human?" — NOT "does the signing key exist?". Commit signing is retired (the vault item is
# deleted and the key left GitHub), so a seat holding no `github_signing` file is CORRECT and used to
# read here as `INCOMPLETE`: a seat whose route verdict hinged on a key policy removed, and a rebuilt
# seat could not be put on the seat default at all. Only an ENABLED `commit.gpgsign` makes a missing
# sign key a defect — that is the HANG (git waits on an agent for a key nothing can validate, in the
# shells nobody watches). An unset `commit.gpgsign` is git's own default, which is false.
route_verdict() {
  local prog="$1" key="$2" sshc="$3" gpg="$4" agent=1
  [ "$gpg" = true ] || gpg=false
  case "$sshc" in *IdentityAgent=none*) agent=0 ;; esac
  if [ -n "$prog" ]; then printf 'MODAL'; return 0; fi
  if [ "$gpg" = true ] && { [ -z "$key" ] || [ ! -e "$key" ]; }; then printf 'INCOMPLETE'; return 0; fi
  if [ "$agent" = 0 ]; then printf 'UNATTENDED'; else printf 'PARTIAL'; fi
}

# Raise the seat's TRANSPORT key from the vault instead of asking a human to copy it. Three rules,
# each one a failure this repo has already paid for: the credential is resolved through
# lib/vault-env.sh BEFORE `op` is asked anything (a seat that holds the token file but exported
# nothing otherwise fails its own preflight and gets told to sign in interactively); the value lands
# in a TEMP file and must PARSE as a passphrase-free private key before anything existing is touched;
# and an existing key is never rewritten or truncated — deleting a seat's working transport key in
# the name of hygiene is data loss. `op.exe` may emit CRLF, and a stray \r reads as a dead key, so
# CRs are stripped before the parse check. Git's OWN ssh-keygen does the check: System32's OpenSSH is
# LibreSSL and answers `invalid format` on these PKCS#8 halves, so a PATH lookup there would refuse a
# good key (measured, docs/deployment-secrets.md §per-route transport).
raise_auth_key() {
  local dst="$KEYDIR/github_auth" tmp opbin keygen pub=""
  if [ -s "$dst" ]; then
    echo "==> $dst present ($(wc -c <"$dst") bytes, fp $(ssh-keygen -lf "$dst" 2>/dev/null | awk '{print $2}')) — left untouched"
    return 0
  fi
  if [ -e "$dst" ]; then
    echo "  !! $dst exists but is EMPTY — replacing it (backup taken first)"
    backup "$dst"
  fi
  opbin="$(command -v op 2>/dev/null || command -v op.exe 2>/dev/null || true)"
  if [ -z "$opbin" ]; then
    echo "FAIL: no op CLI on PATH — cannot raise $dst from the '$OP_VAULT' vault" >&2
    return 1
  fi
  if hl_vault_ask; then
    echo "==> vault credential resolved ($(hl_vault_verdict)) — headless read, no consent dialog"
  else
    echo "  !! no vault credential resolved${HL_VAULT_WHY:+ — $HL_VAULT_WHY}; op may fall back to the desktop app, which needs a human" >&2
  fi
  mkdir -p "$KEYDIR"
  tmp="$dst.tmp.$$"
  if ! "$opbin" read "op://${OP_VAULT}/${OP_AUTH_ITEM}/private key" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    echo "FAIL: could not read '$OP_AUTH_ITEM' from $OP_VAULT — $dst left exactly as it was" >&2
    return 1
  fi
  # PRIVATE IMMEDIATELY: the temp file lands at the seat's umask (0644 on a 022 umask), and ssh-keygen
  # refuses a key that is group-readable — it prints the `@@@…` UNPROTECTED-KEY banner and exits non-zero,
  # so verifying before this chmod reads a perfectly good key as garbage (measured on the Debian seat,
  # where it aborted the raise; Git-for-Windows' build tolerated the mode, so this is not portable luck).
  chmod 600 "$tmp" 2>/dev/null || true
  if LC_ALL=C grep -qU $'\r' "$tmp" 2>/dev/null; then
    tr -d '\r' < "$tmp" > "$tmp.nocr" && mv -f "$tmp.nocr" "$tmp"
  fi
  keygen="${GITSH%/*}/ssh-keygen.exe"
  [ -x "$keygen" ] || keygen="$(command -v ssh-keygen 2>/dev/null || true)"
  if [ -z "$keygen" ]; then
    rm -f "$tmp"; echo "FAIL: no ssh-keygen to verify what the vault returned — $dst left as it was" >&2
    return 1
  fi
  if ! "$keygen" -y -P '' -f "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    echo "FAIL: what the vault returned is not a passphrase-free private key this box can read — $dst left as it was" >&2
    return 1
  fi
  mv -f "$tmp" "$dst"; chmod 600 "$dst" 2>/dev/null || true
  "$keygen" -y -f "$dst" > "$dst.pub" 2>/dev/null || true
  pub="$($keygen -lf "$dst" 2>/dev/null | awk '{print $2}')"
  echo "==> raised $dst from '$OP_AUTH_ITEM' in $OP_VAULT (fp ${pub:-<unreadable>}; the pub half is derived, never copied)"
}

# --- early dispatches: no clone, no config, no network ------------------------------------------
# `--route-verdict <prog> <key> <sshCommand> <gpgsign>` is the self-test's SEAM into route_verdict:
# the same function --check calls, fed fixture values instead of the live config. It exists because a
# verdict that can only be reached through a real seat's ~/.gitconfig cannot be canaried.
if [ "$MODE" = "--route-verdict" ]; then
  route_verdict "${2:-}" "${3:-}" "${4:-}" "${5:-}"
  printf '\n'
  exit 0
fi
if [ "$MODE" = "--raise-key" ]; then
  mkdir -p "$KEYDIR"
  raise_auth_key; exit $?
fi

if [ "$MODE" = "--self-test" ]; then
  SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-bootstrap-win11.sh"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  mkdir -p "$TMP/home/.ssh" "$TMP/home/.config/op" "$TMP/bin" "$TMP/src"
  git init -q "$TMP/repo"
  # A REAL key pair as the vault's answer: the parse check is the arm under test, so the fixture must
  # be bytes ssh-keygen can read, not a marker string that would make every arm fail for one reason.
  ssh-keygen -q -t ed25519 -N '' -C hd495-fixture -f "$TMP/vault_auth" 2>/dev/null \
    || { echo "SELFTEST FAIL [fixture]: ssh-keygen could not make the fixture key"; exit 1; }
  cat > "$TMP/bin/op" <<'EOS'
#!/bin/sh
# A vault that is visible ONLY to a shell holding a credential — which is how the seat's 0600 token
# file is proved to reach `op` rather than being assumed to. Reads the answer key from the path in
# HL_FIXTURE_KEY so the fixture and the assertions never share a literal.
case "$1" in
  vault)   [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && { echo 'Homelab-ansible'; exit 0; }
           echo '[ERROR] You are not currently signed in.' >&2; exit 1;;
  account) echo 'SHORTHAND    URL'; echo 'my           https://my.1password.eu'; exit 0;;
  read)    case "$2" in
             *"GitHub auth"*) [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && { cat "${HL_FIXTURE_KEY:-/dev/null}"; exit 0; }
                              exit 1;;
           esac
           exit 1;;
esac
exit 1
EOS
  chmod +x "$TMP/bin/op"
  fails=0

  # Arm 1 — THE RAISE (HD-495's Win11 leg): a seat that has never had the transport key gets it from
  # the vault, with the token arriving as the FILE the lib reads (no ambient env, and the WSL door
  # stubbed shut so no fixture run ever crosses it or prints a real route). The path goes through the
  # lib's `HL_VAULT_FILE` seam — the lib's ratchet arm reddens if a second file under scripts/ names
  # the fleet's install path, and a fixture has no business spelling it.
  TOKF="$TMP/home/op-sa-token"
  printf 'export OP_SERVICE_ACCOUNT_TOKEN=%s\n' "sat-$(printf 'x%.0s' $(seq 1 60))" > "$TOKF"
  chmod 600 "$TOKF"
  out=$(HL_FIXTURE_KEY="$TMP/vault_auth" HL_VAULT_CLASS=win11 HL_VAULT_STUB_FAIL=1 \
        HL_VAULT_FILE="$TOKF" \
        SRC="$TMP/src" REPOPATH="$TMP/repo" NIGHTLY_SRC="$TMP/nope" USERPROFILE="$TMP/home" \
        HOME="$TMP/home" KEYDIR="$TMP/home/.ssh" PATH="$TMP/bin:$PATH" \
        bash "$SELF" --raise-key 2>&1 || true)
  if [ ! -s "$TMP/home/.ssh/github_auth" ]; then
    echo "SELFTEST FAIL [raise]: no key was raised — a rebuilt seat still needs the hand 'op read' (got: $(printf '%s' "$out" | tail -2))"
    fails=$((fails+1))
  elif ! cmp -s "$TMP/home/.ssh/github_auth" "$TMP/vault_auth"; then
    echo "SELFTEST FAIL [raise]: what landed is not what the vault holds"
    fails=$((fails+1))
  fi
  printf '%s' "$out" | grep -qi 'raised' \
    || { echo "SELFTEST FAIL [raise]: the raise never said what it did"; fails=$((fails+1)); }

  # Arm 2 — NEVER over a working key: the same call with different bytes already in place must leave
  # them byte-identical, proveing the raise is a fill-in and not a re-plant that can truncate.
  head -c 200 /dev/zero | tr '\0' 'Z' > "$TMP/home/.ssh/github_auth"
  cp -p "$TMP/home/.ssh/github_auth" "$TMP/before"
  out=$(HL_FIXTURE_KEY="$TMP/vault_auth" HL_VAULT_CLASS=win11 HL_VAULT_STUB_FAIL=1 \
        HL_VAULT_FILE="$TOKF" \
        SRC="$TMP/src" REPOPATH="$TMP/repo" USERPROFILE="$TMP/home" HOME="$TMP/home" \
        KEYDIR="$TMP/home/.ssh" PATH="$TMP/bin:$PATH" \
        bash "$SELF" --raise-key 2>&1 || true)
  cmp -s "$TMP/before" "$TMP/home/.ssh/github_auth" \
    || { echo "SELFTEST FAIL [no-clobber]: an existing key moved — the raise is not fill-in-only"; fails=$((fails+1)); }
  printf '%s' "$out" | grep -qi 'left untouched' \
    || { echo "SELFTEST FAIL [no-clobber]: the seat was not told its key was left alone"; fails=$((fails+1)); }

  # Arm 3a — no credential AND no key: the refusal names the item, and NOTHING is created (the shape a
  # Phase-0 gap looks like; an empty key file is worse than no key, because it fails as a dead key).
  rm -f "$TOKF" "$TMP/home/.ssh/github_auth"
  out=$(HL_FIXTURE_KEY="$TMP/vault_auth" HL_VAULT_CLASS=win11 HL_VAULT_STUB_FAIL=1 \
        HL_VAULT_FILE="$TOKF" \
        SRC="$TMP/src" REPOPATH="$TMP/repo" USERPROFILE="$TMP/home" HOME="$TMP/home" \
        KEYDIR="$TMP/home/.ssh" PATH="$TMP/bin:$PATH" \
        bash "$SELF" --raise-key 2>&1 || true)
  [ -e "$TMP/home/.ssh/github_auth" ] \
    && { echo "SELFTEST FAIL [no-credential]: a failed read created a key file (it must leave absent absent)"; fails=$((fails+1)); }
  printf '%s' "$out" | grep -qi "could not read '$OP_AUTH_ITEM'" \
    || { echo "SELFTEST FAIL [no-credential]: the refusal never named the item that failed (got: $(printf '%s' "$out" | tail -2))"; fails=$((fails+1)); }

  # Arm 3b — a ZERO-LENGTH key (the shape a previous `op read > file` failure leaves) plus a working
  # read: the old bytes get a backup, the key is replaced, and the PUB half is derived. What each half
  # catches: no backup = a hygiene run destroying seat state; no pub = a raise that leaves the seat
  # unable to prove which key it holds; both = the truncation shape this branch exists to clean up.
  printf '' > "$TMP/home/.ssh/github_auth"
  printf 'export OP_SERVICE_ACCOUNT_TOKEN=%s\n' "sat-$(printf 'z%.0s' $(seq 1 60))" > "$TOKF"
  out=$(HL_FIXTURE_KEY="$TMP/vault_auth" HL_VAULT_CLASS=win11 HL_VAULT_STUB_FAIL=1 \
        HL_VAULT_FILE="$TOKF" \
        SRC="$TMP/src" REPOPATH="$TMP/repo" USERPROFILE="$TMP/home" HOME="$TMP/home" \
        KEYDIR="$TMP/home/.ssh" PATH="$TMP/bin:$PATH" \
        bash "$SELF" --raise-key 2>&1 || true)
  cmp -s "$TMP/home/.ssh/github_auth" "$TMP/vault_auth" \
    || { echo "SELFTEST FAIL [empty-key]: an empty key file was not replaced by the vault's (got: $(printf '%s' "$out" | tail -2))"; fails=$((fails+1)); }
  ls "$TMP/home/.ssh"/github_auth.bak-* >/dev/null 2>&1 \
    || { echo "SELFTEST FAIL [empty-key]: the seat's file was replaced with no backup taken"; fails=$((fails+1)); }
  cmp -s "$TMP/home/.ssh/github_auth.pub" "$TMP/vault_auth.pub" \
    || { echo "SELFTEST FAIL [empty-key]: the pub half was not derived — the seat cannot name the key it holds"; fails=$((fails+1)); }
  rm -f "$TMP/home/.ssh/github_auth" "$TMP/home/.ssh/github_auth.pub" \
       "$TMP/home/.ssh"/github_auth.bak-* "$TOKF"

  # Arm 4 — the verdict matrix, through the seam. Line by line, because the defect this closed was ONE
  # cell: a keyless-but-unsigned seat accused of being INCOMPLETE.
  v=$(bash "$SELF" --route-verdict "" "$TMP/absent" "ssh -o IdentityAgent=none" "false")
  [ "$v" = "UNATTENDED" ] || { echo "SELFTEST FAIL [verdict]: unsigned + no sign key reads $v — WANT UNATTENDED"; fails=$((fails+1)); }
  v=$(bash "$SELF" --route-verdict "" "$TMP/absent" "ssh -o IdentityAgent=none" "")
  [ "$v" = "UNATTENDED" ] || { echo "SELFTEST FAIL [verdict]: unset gpgsign (git's default IS false) reads $v"; fails=$((fails+1)); }
  v=$(bash "$SELF" --route-verdict "" "$TMP/absent" "ssh -o IdentityAgent=none" "true")
  [ "$v" = "INCOMPLETE" ] || { echo "SELFTEST FAIL [verdict]: gpgsign=true with no key file reads $v — that is the HANG and must be loud"; fails=$((fails+1)); }
  v=$(bash "$SELF" --route-verdict "op-ssh-sign.exe" "$TMP/vault_auth" "ssh" "false")
  [ "$v" = "MODAL" ] || { echo "SELFTEST FAIL [verdict]: gpg.ssh.program present reads $v — WANT MODAL"; fails=$((fails+1)); }
  v=$(bash "$SELF" --route-verdict "" "$TMP/vault_auth" "C:/Windows/System32/OpenSSH/ssh.exe" "false")
  [ "$v" = "PARTIAL" ] || { echo "SELFTEST FAIL [verdict]: an agent-reaching transport reads $v — WANT PARTIAL"; fails=$((fails+1)); }

  if [ "$fails" = 0 ]; then
    echo "SELFTEST OK: git-bootstrap-win11 raises the seat payload safely and verdicts the route by the modal question (5 arms, sandboxed)"
    exit 0
  fi
  exit 1
fi

SSH_AUTH=0
if [ "$MODE" = "--ssh-auth" ]; then SSH_AUTH=1; MODE=""; fi
[ "${OP_SSH_AUTH:-}" = "1" ] && SSH_AUTH=1

# --- --reload: informational only, never touches repo/network --------------
if [ "$MODE" = "--reload" ]; then
  echo "==> git-bootstrap-win11 (SRC=$SRC REPO=$REPO) — informational mode"
  if [ ! -d "$REPO/.git" ]; then
    echo "    repo not present at $REPO; run: bash scripts/git/git-bootstrap-win11.sh"
  else
    echo "    repo present; run: bash scripts/git/git-bootstrap-win11.sh update"
  fi
  echo "    then: bash scripts/ansible/ansible-run.sh playbooks/vps.yml --tags docker_services,headscale"
  exit 0
fi

echo "==> git-bootstrap-win11 (SRC=$SRC REPO=$REPO)"
mkdir -p "$SRC"

# --- --check: which git identity route will this seat take? read-only ------------
if [ "$MODE" = "--check" ]; then
  echo "==> git identity route as resolved in $(pwd)"
  prog="$(git config --get gpg.ssh.program 2>/dev/null || true)"
  key="$(git config --get user.signingkey 2>/dev/null || true)"
  sshc="$(git config --get core.sshCommand 2>/dev/null || true)"
  echo "    gpg.ssh.program = ${prog:-(absent)}"
  echo "    user.signingkey = ${key:-(absent)}"
  echo "    core.sshCommand = ${sshc:-(absent)}"
  echo "    includes         : $(git config --global --get-all include.path 2>/dev/null | tr '\n' ' ')(global) $(git config --file "$REPO/.git/config" --get-all include.path 2>/dev/null | tr '\n' ' ')(local)"
  # Both include forms are reported: --check would otherwise print an empty global list on a seat
  # that is correctly configured, and a legacy plain include would be invisible in the list it does
  # print. The key it reads here is the same key --1password has to clean.
  nightly_via=""
  if nightly_included if; then nightly_via="includeIf \"$NIGHTLY_MATCH\""; fi
  if nightly_included plain; then nightly_via="${nightly_via:+$nightly_via + }a global [include] (legacy, hits every remote)"; fi
  echo "    nightly payload  : ${nightly_via:-NOT included — this seat is on the 1Password route}"
  # The transport belongs in the verdict, not just the key list: the payload fires on github remotes
  # only, so anywhere else (a bare directory, a stroka clone) core.sshCommand resolves back to
  # .gitconfig-windows' Windows OpenSSH, which reaches the 1Password pipe. Naming that is the point.
  gpg="$(git config --get commit.gpgsign 2>/dev/null || true)"
  # One function, three callers (--check, --git-identity, --self-test): what decides the route is
  # whether a git call can WAIT for a human, not whether the retired signing key exists.
  verdict="$(route_verdict "$prog" "$key" "$sshc" "$gpg")"
  if [ "$gpg" != true ] && [ -n "$key" ] && [ ! -e "$key" ]; then
    echo "    signing key    : absent (signing is retired — commits stay unsigned, \`%G?\` = N is expected)"
  fi
  case "$verdict" in
    MODAL) echo "==> route: 1PASSWORD — every git call can block on a consent dialog"
           echo "    modal-free instead: bash scripts/git/git-bootstrap-win11.sh --git-identity" ;;
    INCOMPLETE)
           echo "==> route: INCOMPLETE — commit.gpgsign resolves true and the signingkey does not resolve to a key file"
           echo "    that is the HANG shape (cron, a converge, pi's bash), not an unsigned commit:"
           echo "    either re-seat the key (bash scripts/git/git-bootstrap-win11.sh --raise-key) or retire signing" ;;
    UNATTENDED)
           echo "==> route: UNATTENDED — key-file transport over IdentityAgent=none, no 1Password window possible" ;;
    PARTIAL)
           echo "==> route: PARTIAL — the payload is modal-free, but the transport resolved here reaches the 1Password agent"
           echo "    no github remote in scope: the payload is included by hasconfig:, so in a directory"
           echo "    without one git falls back to ${sshc%% *}. Re-run inside a github clone:"
           echo "    cd <github clone> && bash scripts/git/git-bootstrap-win11.sh --check" ;;
  esac
  exit 0
fi

# --- UNATTENDED git identity: the Win11 seat default (HD-495) -------------------
# Payload -> ~/.gitconfig-nightly, included LAST from ~/.gitconfig FOR GITHUB REMOTES, and
# gpg.ssh.program removed everywhere it appears. Two things are the whole mechanism: the order —
# git cannot "unset" a key from a later include, so the program line has to go and the
# .gitconfig-github block (user.signingkey = PUBLIC-KEY STRING) only loses because this include is
# appended after it — and the scope: a plain [include] would hand the payload's github-only
# transport to the stroka and kogler clones too (HD-1126).
install_unattended_identity() {
  [ -f "$NIGHTLY_SRC" ] || { echo "FAIL: payload not found: $NIGHTLY_SRC" >&2; exit 1; }
  # A missing key dir is a fresh seat, not a reason to stop: this mode RAISES the transport key from
  # the vault (raise_auth_key), which is the half that used to be a `[MANUAL]` hand `op read` in the
  # runbook — and whose "op read is a prompt" premise is false on the headless route.
  if [ ! -d "$KEYDIR" ]; then
    mkdir -p "$KEYDIR" && echo "==> created $KEYDIR (fresh seat — the transport key is raised below)"
  fi

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
  # 1b. The seat payload. The AUTH half is the transport and load-bearing: absent means this seat
  #     cannot push at all, so it is RAISED from the vault here (fill-in only, verified, never over an
  #     existing key). The SIGN half is retired — an absent `github_signing` is the CORRECT state, and
  #     a seat that still holds one keeps it only so `allowed_signers` can verify signed history.
  if [ ! -s "$KEYDIR/github_auth" ]; then
    raise_auth_key || { echo "FAIL: the seat has no transport key at $KEYDIR/github_auth and it could not be raised." >&2
                        echo "      Nothing was pushed: fix the vault read (Phase-0 token) and re-run." >&2; exit 1; }
  else
    echo "==> $KEYDIR/github_auth present — transport key left as the seat holds it"
  fi
  if [ ! -e "$KEYDIR/github_signing" ]; then
    echo "==> $KEYDIR/github_signing absent — SIGNING IS RETIRED, so this is the expected state (commits stay unsigned)"
  fi
  # Git for Windows' own ssh is the transport; System32's OpenSSH cannot read these key files.
  [ -e "$GITSH" ] || echo "  !! bundled ssh not at $GITSH — check git.core.sshCommand (auth will fail closed)" >&2

  # 2. Include it for github remotes, read AFTER the block that pins the pubkey string. `git config
  #    --add` appends the value to the [includeIf] section with this exact pattern, so the path lands
  #    below .gitconfig-github's (a seat without that section gets a new one at EOF) — last for
  #    github remotes either way, which is what the order is for. The form is scoped, not a plain
  #    [include]: this payload's sshCommand names the GITHUB key, and a pre-HD-1126 run may have left
  #    a global include that also points the stroka / kogler legs at it. Remove that one.
  if nightly_included if; then
    echo "==> ~/.gitconfig already includes $NIGHTLY_INCLUDE for github remotes (read last)"
  else
    backup "$GITCFG"; git config --global --add "$NIGHTLY_INCLUDE_KEY" "$NIGHTLY_INCLUDE"
    echo "==> ~/.gitconfig: [includeIf \"$NIGHTLY_MATCH\"] path += $NIGHTLY_INCLUDE (after .gitconfig-github -> wins)"
  fi
  if nightly_included plain; then
    backup "$GITCFG"
    git config --global --unset include.path "^${NIGHTLY_INCLUDE//./\\.}$" \
      && echo "==> removed the global [include] of $NIGHTLY_INCLUDE (pre-HD-1126 form: it pinned every remote)" \
      || echo "  !! could not remove the plain include by regex; remove the [include] block by hand" >&2
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

  # 5. Fail closed if the seat did not end up on the modal-free route. The hard assertions are the two
  #    that decide whether a git call can ever WAIT: gpg.ssh.program must be ABSENT, and a seat with
  #    signing ENABLED must resolve a real key file. A pubkey-string pin or a missing sign key is only
  #    a defect while `commit.gpgsign` is true — with signing retired (the vault item deleted, the key
  #    gone from GitHub) both are inert, and failing on them used to make a correctly-key-less seat
  #    impossible to put on the seat default at all.
  prog="$(git config --get gpg.ssh.program 2>/dev/null || true)"
  key="$(git config --get user.signingkey 2>/dev/null || true)"
  gpg="$(git config --get commit.gpgsign 2>/dev/null || true)"
  sshc="$(git config --get core.sshCommand 2>/dev/null || true)"
  [ -z "$prog" ] || { echo "FAIL: gpg.ssh.program still resolves to $prog — that is the modal" >&2; exit 1; }
  verdict="$(route_verdict "$prog" "$key" "$sshc" "$gpg")"
  if [ "$verdict" = INCOMPLETE ]; then
    echo "FAIL: commit.gpgsign resolves true but user.signingkey ($key) is not a key file." >&2
    echo "      That is the HANG (git waits on an agent for a key nothing can validate — cron, a" >&2
    echo "      converge, pi's bash), not an unsigned commit. Re-seat the key or retire signing." >&2
    exit 1
  fi
  case "$key" in
    ssh-*) echo "  !! user.signingkey resolves to a public-key string ($key) — inert while commits stay unsigned" >&2 ;;
  esac
  if [ "$gpg" != true ] && [ -n "$key" ] && [ ! -e "$key" ]; then
    echo "==> signing key file absent by design — commits stay unsigned; \`%G?\` = N is the EXPECTED value"
  fi
  echo "==> route: $verdict (gpg.ssh.program absent, commit.gpgsign=${gpg:-<unset → git default false>})"
  [ "$verdict" = PARTIAL ] && echo "    PARTIAL is honest HERE: the payload fires by hasconfig:, so outside a github"
  [ "$verdict" = PARTIAL ] && echo "    clone the transport falls back to ${sshc%% *} — re-run --check inside a clone"
  echo "    off switch: bash scripts/git/git-bootstrap-win11.sh --1password"
}

revert_to_1password() {
  [ -f "$GFCFG" ] || { echo "FAIL: $GFCFG not present; nothing to revert to" >&2; exit 1; }
  [ -f "$SIGNER" ] || echo "  !! signer not at $SIGNER — the dialog route will fail instead of prompting" >&2
  backup "$GFCFG"; git config --file "$GFCFG" gpg.ssh.program "$SIGNER"
  echo "==> .gitconfig-windows: gpg.ssh.program = $SIGNER"
  # Both include forms have to go. An includeIf block left behind by a previous --git-identity keeps
  # the modal-free transport for github remotes, which would make this revert report a route it is
  # not on (HD-1126).
  for key in include.path "$NIGHTLY_INCLUDE_KEY"; do
    if ! git config --global --get-all "$key" 2>/dev/null | grep -qxF "$NIGHTLY_INCLUDE"; then
      continue
    fi
    backup "$GITCFG"
    git config --global --unset "$key" "^${NIGHTLY_INCLUDE//./\\.}$" \
      && echo "==> removed the $NIGHTLY_INCLUDE include ($key)" \
      || echo "  !! could not remove the include at $key by regex; remove the [include…] block by hand" >&2
  done
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
  #    NOTE: this is the MODAL route — scripts/git/git-bootstrap-win11.sh --git-identity is the
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