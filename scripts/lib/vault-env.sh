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
# The same rule answers for the entry points that are not gate legs at all — `ansible/ansible-run.sh`,
# `ansible/restore-runner-key.sh`, `git/git-bootstrap.sh` and `secrets/rotate-spark-llm-key.sh` (the last
# one INVERTS the order on purpose: there the ambient env is the suspect, so it is dropped and re-resolved).
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
# The walk is parameter expansion, NOT `dirname`: an empty `$PATH` makes `$(dirname …)` answer empty,
# and `[ "" != / ]` is forever true — the loop spins with no external command able to end it. A fixture
# that trims PATH (or a seat whose PATH is broken) must not be able to hang the harness. Same trap as
# CONVENTIONS §6's "a fork-free loop must still terminate".
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ -n "$_hl_d" ] && [ "$_hl_d" != / ] && [ ! -f "$_hl_d/lib/repo-root.sh" ]; do
  _hl_n="${_hl_d%/*}"; [ "$_hl_n" = "$_hl_d" ] && _hl_n="/"; _hl_d="$_hl_n"
done
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

# --- vault IDs: the half that costs quota -----------------------------------------------------
# A NAME is not a free address. `op item get` and `op read` aimed at a name resolve that name first,
# and 1Password bills the resolving: 3 reads for a name-addressed get, 1 for an ID-addressed one
# (developer.1password.com/docs/service-accounts/use-with-1password-cli — "Commands that make multiple
# requests"). The ceiling that binds is not the token's 1000 reads/hour but the ACCOUNT's 1000
# requests/24 h shared by every service account on it (Families/Personal; `op service-account ratelimit`
# prints both), so 143 name-addressed gets spend ~429 of them: THREE gate runs empty the day for every
# other automation on the account. This is why the legs pass IDs. Names stay as the FALLBACK, because a
# renamed item must never become a wrong answer: a miss refreshes the map once and says so.
#
# The map is one file per vault, shared by the bash and python faces: line 1 `# vault_id=<id>`, then
# `title\titem_id` rows. IDs are not secrets, so the file is state, not a credential — but it is still
# written 0600 and atomically, because a half-written map would answer wrong IDs.
hl_vault_state_dir() { printf '%s' "${HL_VAULT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/homelab}"; }

hl_vault_map_file() { local v="${1//\//_}"; printf '%s/op-map-%s.tsv' "$(hl_vault_state_dir)" "$v"; }

# hl_vault_map_refresh <vault> — rebuild the map from ONE `op item list` (2 reads by vault name, 1 by
# vault ID). rc 1 with HL_VAULT_WHY and the OLD map left in place: a failed read must not widen ignorance.
hl_vault_map_refresh() {
  local vault="$1" tmp err out rc=0
  HL_VAULT_WHY=""
  [ -n "$vault" ] || { HL_VAULT_WHY="no vault named"; return 1; }
  hl_vault_env >/dev/null || { HL_VAULT_WHY="no vault credential ($(hl_vault_verdict))"; return 1; }
  command -v op >/dev/null 2>&1 || { HL_VAULT_WHY="no op CLI on PATH"; return 1; }
  command -v jq >/dev/null 2>&1 || { HL_VAULT_WHY="no jq to read the item list"; return 1; }
  mkdir -p "$(hl_vault_state_dir)" 2>/dev/null || { HL_VAULT_WHY="cannot create $(hl_vault_state_dir)"; return 1; }
  tmp="$(mktemp)" || { HL_VAULT_WHY="mktemp failed"; return 1; }
  err="$(mktemp)" || { rm -f -- "$tmp"; HL_VAULT_WHY="mktemp failed"; return 1; }
  if op item list --vault "$vault" --format json >"$tmp" 2>"$err"; then
    out="$(hl_vault_state_dir)/.op-map-$$.tsv"
    if { printf '# vault_id=%s\n' "$(jq -r '[.[].vault.id] | first // ""' "$tmp" 2>/dev/null)";
         jq -r '.[] | [.title, .id] | @tsv' "$tmp" 2>/dev/null; } >"$out" 2>/dev/null \
       && [ "$(wc -l <"$out")" -gt 1 ]; then
      chmod 600 "$out" 2>/dev/null || true
      mv -f -- "$out" "$(hl_vault_map_file "$vault")" || rc=1
    else
      rm -f -- "$out" 2>/dev/null || true
      rc=1; HL_VAULT_WHY="\`op item list --vault $vault\` answered no usable rows"
    fi
  else
    rc=1; HL_VAULT_WHY="\`op item list --vault $vault\` rc $?: $(head -c 120 "$err" 2>/dev/null | tr -d '\r\n')"
  fi
  rm -f -- "$tmp" "$err" 2>/dev/null || true
  return $rc
}

# hl_vault_id <vault> — the vault's ID when the map knows it, else rc 1 (the caller keeps the name).
hl_vault_id() {
  local f="$(hl_vault_map_file "${1:-}")" v
  [ -f "$f" ] || return 1
  v="$(head -1 "$f" 2>/dev/null | sed -n 's/^# vault_id=//p')"
  [ -n "$v" ] && [ "$v" != "null" ] || return 1
  printf '%s\n' "$v"
}

# hl_vault_item_id <vault> <title> — the item's ID; a miss refreshes the map ONCE and retries, so a
# renamed item costs 2 reads and then answers right forever.
hl_vault_item_id() {
  local vault="$1" title="$2" f id
  f="$(hl_vault_map_file "$vault")"
  [ -f "$f" ] || hl_vault_map_refresh "$vault" >/dev/null 2>&1 || return 1
  id="$(awk -F'\t' -v t="$title" '$1 == t { print $2; exit }' "$f" 2>/dev/null)"
  [ -n "$id" ] || { hl_vault_map_refresh "$vault" >/dev/null 2>&1 || return 1
                    id="$(awk -F'\t' -v t="$title" '$1 == t { print $2; exit }' "$f" 2>/dev/null)"; }
  [ -n "$id" ] || return 1
  printf '%s\n' "$id"
}

hl_vault_usage() {
  cat <<'EOF'
Usage:
  bash scripts/lib/vault-env.sh --check [--identity]   resolve; print route/len/hash [+ Integration ID]
  bash scripts/lib/vault-env.sh --emit                 print the value to a PIPE only (a terminal -> rc 3)
  bash scripts/lib/vault-env.sh --map <vault>          rebuild/point at the name->ID map (quota, see head)
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
  readers="$(cd "$REPO" 2>/dev/null && git grep -l 'homelab-sa-token' -- scripts/ 2>/dev/null     | grep -v -e '\.md$' -e '^scripts/lib/vault-env\.sh$' -e '^scripts/testdata/'              -e '^scripts/ansible/bootstrap-runner\.sh$'                                                                  || true)"
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

  # Arms 11-14 — the ID map, which is the read-budget half: a name-addressed `op item get` costs 3
  # reads against an ACCOUNT ceiling of 1000 requests/24 h; an ID-addressed one costs 1. A stub `op`
  # that COUNTS its calls answers instead of a vault, so these arms prove the cache, not the network.
  local mapdir="$tmp/state" mapcalls="$tmp/op.calls" fakebin="$tmp/bin" cold=""
  mkdir -p "$mapdir" "$fakebin"
  cat > "$tmp/items.json" <<'FIXTURE'
[{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaa","title":"item_one",
  "vault":{"id":"xvh7vv7aaaaaaaaaaaaaaaaaaaaaaaaaa","name":"Test-vault"}}]
FIXTURE
  cat > "$fakebin/op" <<'FAKEOP'
#!/usr/bin/env bash
if [ -n "${HL_VAULT_CALLS:-}" ]; then printf x >> "$HL_VAULT_CALLS"; fi
case "$*" in
  *"item list"*) cat "$HL_VAULT_FIXTURE_JSON"; exit 0 ;;
esac
exit 1
FAKEOP
  chmod +x "$fakebin/op"
  : > "$mapcalls"
  # The fixture state dir keeps the REAL seat's map out of the arm; the stub PATH keeps a real `op`
  # out of it; HL_VAULT_FILE=/nonexistent stops a seat install from answering instead of the fixture.
  export HL_VAULT_STATE_DIR="$mapdir" HL_VAULT_CALLS="$mapcalls" HL_VAULT_FILE=/nonexistent
  export HL_VAULT_FIXTURE_JSON="$tmp/items.json"
  PATH="$fakebin:$PATH" OP_SERVICE_ACCOUNT_TOKEN="$v_env" hl_vault_item_id Test-vault item_one >/dev/null 2>&1
  check "a cold title resolves to the item ID" \
    "$( [ "$(hl_vault_item_id Test-vault item_one 2>/dev/null)" = aaaaaaaaaaaaaaaaaaaaaaaaaa ] && echo 1 || echo 0)"
  check "the cold path read the vault ONCE, not once per lookup" \
    "$( [ "$(wc -c < "$mapcalls" | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
  check "the vault ID came from that same single read" \
    "$( [ "$(hl_vault_id Test-vault 2>/dev/null)" = xvh7vv7aaaaaaaaaaaaaaaaaaaaaaaaaa ] && echo 1 || echo 0)"
  : > "$mapcalls"
  PATH="$fakebin:$PATH" OP_SERVICE_ACCOUNT_TOKEN="$v_env" hl_vault_item_id Test-vault item_one >/dev/null 2>&1
  PATH="$fakebin:$PATH" OP_SERVICE_ACCOUNT_TOKEN="$v_env" hl_vault_item_id Test-vault item_one >/dev/null 2>&1
  check "a warm map asks the vault NOTHING — that is the whole point of the map" \
    "$( [ "$(wc -c < "$mapcalls" | tr -d ' ')" = 0 ] && echo 1 || echo 0)"
  PATH="$fakebin:$PATH" OP_SERVICE_ACCOUNT_TOKEN="$v_env" hl_vault_item_id Test-vault never_named >/dev/null 2>&1
  cold=$?
  check "an unknown title is rc 1, so the caller keeps the NAME rather than a wrong ID" \
    "$( [ "$cold" = 1 ] && echo 1 || echo 0)"
  unset HL_VAULT_STATE_DIR HL_VAULT_CALLS HL_VAULT_FIXTURE_JSON HL_VAULT_FILE

  if [ "$fails" = 0 ]; then printf 'vault-env.sh --self-test: OK (14 arms)\n'; return 0
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
    --map)
      # Print where the map lives, what it cost, and whether it is usable — the quota question first.
      if [ -z "${2:-}" ]; then printf 'vault-env: --map needs a vault name or ID\n' >&2; exit 2; fi
      if hl_vault_map_refresh "$2"; then
        printf 'vault-env: map %s items=%d vault_id=%s file=%s\n' "$2" \
          "$(( $(wc -l <"$(hl_vault_map_file "$2")") - 1 ))" "$(hl_vault_id "$2")" "$(hl_vault_map_file "$2")"
        exit 0
      fi
      printf 'vault-env: %s\n' "the map for $2 was not rebuilt: $HL_VAULT_WHY — legs keep the name form (3 reads each)" >&2
      exit 1 ;;
    *) hl_vault_usage >&2; exit 2 ;;
  esac
fi
