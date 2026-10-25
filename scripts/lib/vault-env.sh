#!/usr/bin/env bash
# =====================================================================
# lib/vault-env.sh — the ONE answer to "which 1Password credential answers this leg?"
# ---------------------------------------------------------------------
# WHY: every vault leg of the gate (`check_secret_leak.py` and its 143 `op item get` reads,
# `check_host_reporting.py`, `check_ssh_grants.py`, `check-vault-items.sh`, `render-pi-config.py`)
# carried its own copy of "if the shell has no token, read the 0600 file". On a Debian seat that
# fallback lands on `~/.config/op/homelab-sa-token` and `op` answers in a second. On the Win11 seat
# the file does not exist — that seat holds no vault credential of its own — so `op.exe` fell back to
# the DESKTOP APP, which authorises a key against a requesting process: a consent dialog per read,
# 8–12 s each, in a harness that starts a fresh shell per command. The gate there needed a human.
#
# THE ANSWER: the Windows seat already has a headless path to the same read-scoped credential — the
# Debian engine under WSL, whose 0600 install this repo documents and rotates. Resolution order, in
# one place:
#
#   1. OP_SERVICE_ACCOUNT_TOKEN already in the environment     route=env
#   2. $HOME/.config/op/homelab-sa-token on THIS seat          route=file
#   3. on the win11 seat only: that file, read from the Debian engine across the door
#                                                              route=door:<distro>
#   4. nothing else is allowed to answer                       route=none, rc 1
#
# Step 3 is the point: the token is not copied to the Windows disk and not installed on that seat, so
# the seat keeps holding no credential of its own, and an `op_api` rotation reaches it through the
# engine's install with no second re-seat. Step 4 is the safety half: a leg that finds no credential
# STOPS, because calling `op` with nothing in the environment is silently the desktop app again — and
# a suppressed prompt is not a refusal, it is a wait.
#
# WHAT THIS FILE IS NOT: not a vault client, not a door. The door — which seat, which distro, the
# MSYS path-conversion pins, the far rc — belongs to `lib/wsl-route.sh`; this file asks it ONE
# question (`hl_wsl_class`) and honors `HL_WSL=off` the way every other leg does. `hl_wsl_probe` is
# deliberately not called: it validates the engine's interpreters and git, which is a different
# question and would refuse a leg for reasons unrelated to whether the credential is reachable.
#
# HYGIENE (CONVENTIONS §2/§6): the value never reaches the stdout of a logged command, never a
# command line, never a file this lib writes. `--emit` exists for the python legs and refuses a TTY
# (rc 3), so the only way out is a pipe held by the calling process. What IS printed is provenance:
# `route=`, `len=`, `sha256[:12]=` and, with `--identity`, the Integration ID — because `op vault
# list` cannot tell the read-scoped and write-scoped accounts apart and a seat seeded from the wrong
# item reads green anyway.
#
# USE — bash, sourced:
#   hl_source_lib "${BASH_SOURCE[0]}" repo-root.sh     # or the repo-root bootstrap; sets REPO
#   hl_source_lib "${BASH_SOURCE[0]}" vault-env.sh
#   hl_vault_env || exit 2    # exports the token or says why it cannot; sets HL_VAULT_ROUTE,
#                             # HL_VAULT_LEN, HL_VAULT_SHA, HL_VAULT_WHY
# USE — python: scripts/lib/vault_env.py wraps `--emit` so there is one implementation, not two.
#
# MODES (run directly):
#   --check [--identity]   resolve and print the verdict; nothing but route/len/hash [+ Integration ID]
#   --emit                 print the value to a PIPE only (a terminal is refused, rc 3)
#   --self-test            fixture arms (stub door + throwaway HOME); reads no vault, needs no token
#
# SELF-TEST ARMS: env wins over a file that disagrees; a local file wins over a door that disagrees;
# a CRLF or quoted value arrives quote-free and CR-free (the trap that turns a good token into a 403);
# the door answers when the seat has nothing of its own; a dead door is rc 1 and exports NOTHING;
# `HL_WSL=off` and a non-win11 class never cross; `--emit` refuses a TTY and pipes the value byte-exact;
# a value under the length floor is refused; and a ratchet that reddens when a second file under
# `scripts/` starts reading the token path by itself.
#
# LIMITS, stated: len/hash is a sanity floor, not authenticity — `--identity` is what proves scope. On
# a seat with neither a local install nor a door this reports a boundary; it never falls back to
# `op signin`, to the desktop app, or to a credential in a repo file, and no mode of it installs one.
# =====================================================================

_hl_self="${BASH_SOURCE[0]}"
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
[ -f "$_hl_d/lib/repo-root.sh" ] && . "$_hl_d/lib/repo-root.sh"      # sets REPO; an inherited $REPO wins
_d="$_hl_d"
while [ -n "$_d" ] && [ "$_d" != / ]; do
  if [ -f "$_d/lib/wsl-route.sh" ]; then
    # shellcheck source=/dev/null
    . "$_d/lib/wsl-route.sh"
    break
  fi
  _d="$(dirname "$_d")"
done

: "${HL_VAULT_FILE:=$HOME/.config/op/homelab-sa-token}"   # the documented 0600 install path
: "${HL_VAULT_GUEST_PATH:=.config/op/homelab-sa-token}"   # engine side, RELATIVE to the engine's $HOME
: "${HL_VAULT_STUB_OUT:=}"        # fixture: bytes that stand in for the engine's answer
: "${HL_VAULT_STUB_FAIL:=0}"      # fixture: 1 = the door is there and answers nothing
: "${HL_VAULT_TTY:=0}"            # fixture: 1 = behave as if stdout were a terminal
: "${HL_VAULT_CLASS:=}"           # fixture: inject the seat class instead of asking uname
HL_VAULT_ROUTE="none"
HL_VAULT_LEN=0
HL_VAULT_SHA="n/a"
HL_VAULT_WHY="not resolved"
HL_VAULT_RAW=""
HL_VAULT_MIN=32                   # a service-account token is long; shorter is a parse bug, not a credential

# hl_vault_file_first <path> — the assignment line of a token file, into HL_VAULT_RAW. An OUT
# PARAMETER, not `$( )`: a command substitution on a Windows seat applies text-mode translation and
# can HIDE the CR this lib exists to strip (CONVENTIONS §6), so a substitution-read CRLF fixture would
# pass the parse while proving nothing about the seat that has the bug.
hl_vault_file_first() {
  local _f="$1" _line=""
  HL_VAULT_RAW=""
  [ -r "$_f" ] || return 1
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in *OP_SERVICE_ACCOUNT_TOKEN=*) HL_VAULT_RAW="$_line"; return 0 ;; esac
  done < "$_f"
  return 1
}

# hl_vault_set <line> — parse one `export OP_SERVICE_ACCOUNT_TOKEN=…` line and EXPORT it. Strips the
# assignment, one layer of matching quotes, and every CR. The CR half is load-bearing: a value that
# crossed `wsl.exe` (or a Windows-authored file) can carry a trailing \r, `op` sends it verbatim, and
# the vault answers 403 exactly as it would to a dead token.
hl_vault_set() {
  local v="${1:-}"
  HL_VAULT_ROUTE="none"; HL_VAULT_LEN=0; HL_VAULT_SHA="n/a"; HL_VAULT_WHY=""
  v="${v//$'\r'/}"
  v="${v%$'\n'}"
  case "$v" in export\ *) v="${v#export }" ;; esac
  case "$v" in *OP_SERVICE_ACCOUNT_TOKEN=*) v="${v#*OP_SERVICE_ACCOUNT_TOKEN=}" ;; esac
  case "$v" in \"*\") v="${v#\"}"; v="${v%\"}" ;; esac
  case "$v" in \'*\') v="${v#\'}"; v="${v%\'}" ;; esac
  if [ -z "$v" ]; then
    HL_VAULT_WHY="no OP_SERVICE_ACCOUNT_TOKEN value after parse"
    return 1
  fi
  if [ "${#v}" -lt "$HL_VAULT_MIN" ]; then
    HL_VAULT_WHY="parsed value is ${#v} chars — under the ${HL_VAULT_MIN}-char floor, so this is a parse bug and not a token"
    return 1
  fi
  export OP_SERVICE_ACCOUNT_TOKEN="$v"
  HL_VAULT_LEN="${#v}"
  HL_VAULT_SHA="$(printf %s "$v" | sha256sum 2>/dev/null | cut -c1-12)"
  [ -n "$HL_VAULT_SHA" ] || HL_VAULT_SHA="n/a"
  return 0
}

# hl_vault_env — resolve in the documented order and EXPORT the answer. rc 1 with a reason and
# NOTHING exported when no source answered, so a caller can turn that into a Boundary SKIP instead of
# mistaking a desktop-app fallback for a credential.
hl_vault_env() {
  local cls=""
  if [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    hl_vault_set "export OP_SERVICE_ACCOUNT_TOKEN=$OP_SERVICE_ACCOUNT_TOKEN" || return 1
    HL_VAULT_ROUTE="env"
    return 0
  fi
  if [ -e "$HL_VAULT_FILE" ]; then
    if ! hl_vault_file_first "$HL_VAULT_FILE"; then
      HL_VAULT_ROUTE="none"
      HL_VAULT_WHY="$HL_VAULT_FILE exists but holds no OP_SERVICE_ACCOUNT_TOKEN line"
      return 1
    fi
    if hl_vault_set "$HL_VAULT_RAW"; then
      HL_VAULT_ROUTE="file"
      return 0
    fi
    HL_VAULT_WHY="$HL_VAULT_FILE: $HL_VAULT_WHY"
    return 1
  fi
  if [ "$HL_VAULT_STUB_FAIL" = 1 ]; then
    HL_VAULT_ROUTE="none"
    HL_VAULT_WHY="the door answered nothing — the Debian engine's token file is absent or unreadable"
    return 1
  fi
  cls="${HL_VAULT_CLASS:-$(hl_wsl_class 2>/dev/null)}"
  if [ "$cls" != win11 ]; then
    HL_VAULT_ROUTE="none"
    HL_VAULT_WHY="no OP_SERVICE_ACCOUNT_TOKEN and no $HL_VAULT_FILE on a ${cls:-unknown} seat — nothing to borrow from"
    return 1
  fi
  if [ "${HL_WSL:-auto}" = off ]; then
    HL_VAULT_ROUTE="none"
    HL_VAULT_WHY="no local credential and HL_WSL=off — the Debian engine is refused and this seat holds none of its own"
    return 1
  fi
  if [ -n "$HL_VAULT_STUB_OUT" ]; then
    hl_vault_file_first "$HL_VAULT_STUB_OUT" || HL_VAULT_RAW=""
  else
    command -v -- "${HL_WSL_EXE:-wsl.exe}" >/dev/null 2>&1 || {
      HL_VAULT_ROUTE="none"
      HL_VAULT_WHY="no credential here and no ${HL_WSL_EXE:-wsl.exe} door on this Windows seat"
      return 1
    }
    # The ENGINE expands its own $HOME: a Windows-side `~` is Git-Bash's home and a hardcoded
    # /home/<name> is a guess about the distro's user. Converter pins per lib/wsl-route.sh; the NUL
    # padding belongs to wsl.exe's own messages.
    HL_VAULT_RAW="$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
      "${HL_WSL_EXE:-wsl.exe}" -d "${HL_WSL_DISTRO:-Debian}" -- sh -c \
      "cat \"\$HOME/$HL_VAULT_GUEST_PATH\" 2>/dev/null" | tr -d '\000' | head -1)"
  fi
  if [ -n "$HL_VAULT_RAW" ] && hl_vault_set "$HL_VAULT_RAW"; then
    HL_VAULT_ROUTE="door:${HL_WSL_DISTRO:-Debian}"
    return 0
  fi
  HL_VAULT_ROUTE="none"
  if [ -n "$HL_VAULT_RAW" ]; then
    HL_VAULT_WHY="the engine's token line did not parse: $HL_VAULT_WHY"
  else
    HL_VAULT_WHY="the engine answered nothing — no \$HOME/$HL_VAULT_GUEST_PATH in ${HL_WSL_DISTRO:-Debian}"
  fi
  return 1
}

hl_vault_verdict() { printf 'route=%s len=%s sha256[:12]=%s' \
  "$HL_VAULT_ROUTE" "$HL_VAULT_LEN" "$HL_VAULT_SHA"; }

hl_vault_usage() {
  cat <<'EOF'
Usage:
  bash scripts/lib/vault-env.sh --check [--identity]   resolve; print route/len/hash [+ Integration ID]
  bash scripts/lib/vault-env.sh --emit                 print the value to a PIPE only (a terminal -> rc 3)
  bash scripts/lib/vault-env.sh --self-test            fixture arms; reads no vault, needs no token
Exit: 0 resolved · 1 no credential reachable (an environment boundary, not a caller bug)
      2 usage · 3 --emit refused a terminal
EOF
}

# --- self-test -------------------------------------------------------------------------
# Fixture values are SYNTHESISED at run time rather than left as literals in a tracked file: this lib
# is about credentials, and a high-entropy string sitting in it is exactly the shape the tree scanners
# are paid to find. The stub door answers from a temp file, so the arms grade the PARSER, the ORDER
# and the refusals; the door itself is `lib/wsl-route.sh --self-test`'s job. Each arm captures its rc
# on its own line — an arm that grades the last grep is an arm that cannot fail.
hl_vault_self_test() {
  local tmp fails=0 rc v_env v_file v_quoted v_door readers LIB
  tmp="$(mktemp -d)" || { printf 'SELFTEST FAILED: no temp dir\n'; return 1; }
  trap 'rm -rf "$tmp"' EXIT
  fails=0
  check() { if [ "$2" = 1 ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); fi; }
  LIB="$_hl_self"

  v_env="envv_$(printf 'e%.0s' {1..40})"
  v_file="filev_$(printf 'f%.0s' {1..40})"
  v_quoted="quotedv_$(printf 'q%.0s' {1..40})"
  v_door="doorv_$(printf 'd%.0s' {1..40})"
  printf 'export OP_SERVICE_ACCOUNT_TOKEN=%s\n' "$v_file"       > "$tmp/tok_file"
  printf 'export OP_SERVICE_ACCOUNT_TOKEN="%s"\r\n' "$v_quoted" > "$tmp/tok_quoted"
  printf 'export OP_SERVICE_ACCOUNT_TOKEN=%s\n' "$v_door"       > "$tmp/tok_door"
  printf 'export OP_SERVICE_ACCOUNT_TOKEN=short\n'              > "$tmp/tok_short"

  # Arm 1 — an ambient token wins; a file that disagrees never speaks.
  mkdir -p "$tmp/h1/.config/op"; cp "$tmp/tok_file" "$tmp/h1/.config/op/homelab-sa-token"
  ( env -u OP_SERVICE_ACCOUNT_TOKEN "HOME=$tmp/h1" "OP_SERVICE_ACCOUNT_TOKEN=$v_env" \
      "HL_VAULT_FILE=$tmp/h1/.config/op/homelab-sa-token" "HL_VAULT_STUB_OUT=$tmp/tok_door" \
      bash "$LIB" --check ) > "$tmp/a1" 2>&1
  rc=$?
  check "an ambient token wins over a file that disagrees" \
    "$([ "$rc" = 0 ] && grep -q 'route=env' "$tmp/a1" && grep -q "len=${#v_env} " "$tmp/a1" && echo 1 || echo 0)"

  # Arm 2 — no env, a local file: the door is never opened, even when it could answer.
  mkdir -p "$tmp/h2/.config/op"; cp "$tmp/tok_file" "$tmp/h2/.config/op/homelab-sa-token"
  ( env -u OP_SERVICE_ACCOUNT_TOKEN "HOME=$tmp/h2" "HL_VAULT_FILE=$tmp/h2/.config/op/homelab-sa-token" \
      HL_VAULT_CLASS=win11 "HL_VAULT_STUB_OUT=$tmp/tok_door" bash "$LIB" --check ) > "$tmp/a2" 2>&1
  rc=$?
  check "a local install wins over the door" \
    "$([ "$rc" = 0 ] && grep -q 'route=file' "$tmp/a2" && grep -q "len=${#v_file} " "$tmp/a2" \
        && ! grep -q 'route=door' "$tmp/a2" && echo 1 || echo 0)"

  # Arm 3 — CRLF + quotes: what reaches the environment carries neither (the 403 trap).
  mkdir -p "$tmp/h3/.config/op"; cp "$tmp/tok_quoted" "$tmp/h3/.config/op/homelab-sa-token"
  ( env -u OP_SERVICE_ACCOUNT_TOKEN "HOME=$tmp/h3" "HL_VAULT_FILE=$tmp/h3/.config/op/homelab-sa-token" \
      HL_VAULT_CLASS=win11 bash "$LIB" --check ) > "$tmp/a3" 2>&1
  rc=$?
  check "a CRLF/quoted file value arrives quote-free and CR-free (len=${#v_quoted})" \
    "$([ "$rc" = 0 ] && grep -q 'route=file' "$tmp/a3" && grep -q "len=${#v_quoted} " "$tmp/a3" && echo 1 || echo 0)"

  # Arm 4 — nothing local, the door answers: the win11 seat borrows the engine's install.
  mkdir -p "$tmp/h4"
  ( env -u OP_SERVICE_ACCOUNT_TOKEN "HOME=$tmp/h4" "HL_VAULT_FILE=$tmp/h4/.config/op/homelab-sa-token" \
      HL_VAULT_CLASS=win11 "HL_VAULT_STUB_OUT=$tmp/tok_door" bash "$LIB" --check ) > "$tmp/a4" 2>&1
  rc=$?
  check "the win11 seat borrows the engine's install across the door" \
    "$([ "$rc" = 0 ] && grep -q 'route=door:' "$tmp/a4" && grep -q "len=${#v_door} " "$tmp/a4" && echo 1 || echo 0)"

  # Arm 5 — a dead door is a boundary that exports NOTHING (never a silent desktop-app fallback).
  mkdir -p "$tmp/h5"
  ( env -u OP_SERVICE_ACCOUNT_TOKEN "HOME=$tmp/h5" "HL_VAULT_FILE=$tmp/h5/.config/op/homelab-sa-token" \
      HL_VAULT_CLASS=win11 HL_VAULT_STUB_FAIL=1 bash "$LIB" --check ) > "$tmp/a5" 2>&1
  rc=$?
  check "a dead door is rc 1 with a reason and route=none" \
    "$([ "$rc" = 1 ] && grep -q 'route=none' "$tmp/a5" && grep -qi 'door answered nothing' "$tmp/a5" && echo 1 || echo 0)"

  # Arm 6 — the refusals: HL_WSL=off on the win11 seat, and a seat that is not the win11 one.
  mkdir -p "$tmp/h6"
  ( env -u OP_SERVICE_ACCOUNT_TOKEN "HOME=$tmp/h6" HL_WSL=off \
      "HL_VAULT_FILE=$tmp/h6/.config/op/homelab-sa-token" HL_VAULT_CLASS=win11 \
      "HL_VAULT_STUB_OUT=$tmp/tok_door" bash "$LIB" --check ) > "$tmp/a6" 2>&1
  rc=$?
  check "HL_WSL=off refuses the door on the win11 seat" \
    "$([ "$rc" = 1 ] && grep -q 'HL_WSL=off' "$tmp/a6" && echo 1 || echo 0)"
  mkdir -p "$tmp/h6b"
  ( env -u OP_SERVICE_ACCOUNT_TOKEN "HOME=$tmp/h6b" \
      "HL_VAULT_FILE=$tmp/h6b/.config/op/homelab-sa-token" HL_VAULT_CLASS=linux \
      "HL_VAULT_STUB_OUT=$tmp/tok_door" bash "$LIB" --check ) > "$tmp/a6b" 2>&1
  rc=$?
  check "a Debian seat never crosses to borrow a credential" \
    "$([ "$rc" = 1 ] && grep -q 'route=none' "$tmp/a6b" && echo 1 || echo 0)"

  # Arm 7 — --emit refuses a terminal and discloses nothing there.
  ( env -u OP_SERVICE_ACCOUNT_TOKEN "HL_VAULT_FILE=$tmp/none" HL_VAULT_CLASS=win11 \
      "HL_VAULT_STUB_OUT=$tmp/tok_door" HL_VAULT_TTY=1 bash "$LIB" --emit ) > "$tmp/a7" 2>&1
  rc=$?
  check "--emit refuses a terminal and discloses nothing" \
    "$([ "$rc" = 3 ] && ! grep -q "$v_door" "$tmp/a7" && echo 1 || echo 0)"

  # Arm 8 — --emit hands the value down a pipe byte-exact (what the python legs depend on). cmp, not a
  # string compare through $( ): byte truth on a Windows seat.
  ( env -u OP_SERVICE_ACCOUNT_TOKEN "HL_VAULT_FILE=$tmp/none" HL_VAULT_CLASS=win11 \
      "HL_VAULT_STUB_OUT=$tmp/tok_door" bash "$LIB" --emit 2>/dev/null ) > "$tmp/a8"
  printf %s "$v_door" > "$tmp/exp"
  check "--emit hands the value down a pipe, byte-exact" "$(cmp -s "$tmp/a8" "$tmp/exp" && echo 1 || echo 0)"

  # Arm 9 — the ratchet: one reader of the token PATH per leg class, and the tree is the fixture.
  # The ALLOWED list is a floor, not a target — the Debian-seat-side legs still read the file inline,
  # each one a copy of the rule this lib replaces, and the fold is that lane's edit, not this one's.
  # What the arm forbids from now on is a NEW file naming the path: the list can only shrink.
  # `\.md` is excluded because a registry row that NAMES the path is documentation, not a reader.
  readers="$(cd "$REPO" 2>/dev/null && git grep -l 'homelab-sa-token' -- scripts/ 2>/dev/null     | grep -v -e '\.md$' -e '^scripts/lib/vault-env\.sh$' -e '^scripts/testdata/'              -e '^scripts/ansible/bootstrap-runner\.sh$'              -e '^scripts/ansible/ansible-run\.sh$'              -e '^scripts/ansible/restore-runner-key\.sh$'              -e '^scripts/ansible/routeros-apply-delta\.sh$'              -e '^scripts/git/git-bootstrap\.sh$'              -e '^scripts/secrets/rotate-spark-llm-key\.sh$' || true)"
  # A git that cannot open this checkout answers with NOTHING, and "nothing new" must not read as a
  # passed arm (a Linux git pointed at a Windows worktree reads the `gitdir:` file as relative and
  # dies — lib/wsl-route.sh records it). Not judged is printed as not judged.
  if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    printf '  NOTE %s — the tree is unreadable from here, so the arm is not judged (never counted ok)
'       "no new file under scripts/ reads the token path"
  elif [ -z "$readers" ]; then
    check "no new file under scripts/ reads the token path" 1
  else
    printf '       new reader(s): %s
' "$(printf '%s' "$readers" | tr '
' ' ')"
    check "no new file under scripts/ reads the token path" 0
  fi

  # Arm 10 — a short value is a parse bug, refused rather than exported.
  ( env -u OP_SERVICE_ACCOUNT_TOKEN "HL_VAULT_FILE=$tmp/tok_short" HL_VAULT_CLASS=win11 \
      bash "$LIB" --check ) > "$tmp/a10" 2>&1
  rc=$?
  check "a value under the length floor is refused" \
    "$([ "$rc" = 1 ] && grep -q 'floor' "$tmp/a10" && echo 1 || echo 0)"

  if [ "$fails" = 0 ]; then printf 'vault-env.sh --self-test: OK (10 arms)\n'; return 0
  else printf 'SELFTEST FAILED: %s arm(s)\n' "$fails"; return 1; fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:---check}" in
    --self-test) hl_vault_self_test; exit $? ;;
    --usage|-h|--help) hl_vault_usage; exit 0 ;;
    --emit)
      # stdout is the pipe the caller holds; the verdict goes to stderr, so a mis-wired `echo $(…)`
      # in a run log cannot carry a value.
      if [ -t 1 ] || [ "$HL_VAULT_TTY" = 1 ]; then
        printf 'vault-env: --emit refuses a terminal — a value travels down a pipe, never onto a tty\n' >&2
        exit 3
      fi
      if ! hl_vault_env; then printf 'vault-env: %s\n' "$HL_VAULT_WHY" >&2; exit 1; fi
      printf '%s\n' "$(hl_vault_verdict)" >&2
      printf '%s' "$OP_SERVICE_ACCOUNT_TOKEN"
      exit 0 ;;
    --check)
      if hl_vault_env; then
        printf 'vault-env: %s\n' "$(hl_vault_verdict)"
        if [ "${2:-}" = --identity ] && command -v op >/dev/null 2>&1; then
          # `op vault list` cannot tell the two service accounts apart; the Integration ID can.
          op whoami 2>&1 | grep -E '^(User Type|Integration ID)' | tr -s ' ' | sed 's/^/vault-env: /'
        fi
        exit 0
      fi
      printf 'vault-env: %s\n' "$(hl_vault_verdict)"
      printf 'vault-env: %s\n' "$HL_VAULT_WHY"
      exit 1 ;;
    *) hl_vault_usage >&2; exit 2 ;;
  esac
fi
