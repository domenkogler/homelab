#!/usr/bin/env bash
# =====================================================================
# seat-ssh-build.sh — the Win11 seat's ssh BUILD plane (HD-1128).
#
# WHY THIS EXISTS
# ---------------
# `ssh oldsrv-domen` worked from Git-Bash and died from pwsh on the SAME seat, with the SAME
# ~/.ssh/config and the SAME keys. Nothing was broken: two different ssh binaries answer on this
# box, and only one of them can read the fleet's keys.
#
#   Git-Bash /usr/bin/ssh          OpenSSH_10.5p1 / OpenSSL   -> rc 0 on all five legs
#   C:/WINDOWS/System32/OpenSSH    OpenSSH_for_Windows_9.5p2 / LibreSSL 3.8.2
#       -> Load key "C:\Users\domen/.ssh/ansible-admin_ssh": invalid format
#       -> ansible-admin@vps.kogler.si: Permission denied (publickey)
#
# The identity halves are PKCS#8 PEM (the `BEGIN PRIVATE KEY` PEM header), the shape the 1Password export
# writes, and OpenSSH_for_Windows cannot parse that container: it loads NO key, so the run dies on
# the FIRST hop — the `ProxyJump vps` leg — which is why it reads like a VPS auth bug and not like a
# key-format bug. `ssh/aliases.tmpl` was, and remains, correct on both builds; this plane is the
# half that decides WHICH BINARY reads it. PATH decides that today, and the machine PATH names
# C:\WINDOWS\System32\OpenSSH while Git's ssh sits in Git\usr\bin — a directory only Git-Bash itself
# adds. So every Windows-native shell gets the LibreSSL build. The fix names the build. This closes
# HD-1123's unpaid tail: "the legs are authenticated by the OpenSSL ssh build, and NOTHING in the
# repo asserts it".
#
# WHAT IT WRITES
# --------------
# ONE marker-delimited block (rendered from ssh/transport-block.ps1) into the *current-user,
# all-hosts* profile of every PowerShell installed on the seat, so `powershell.exe` and `pwsh.exe`
# both resolve a bare `ssh` to the pinned build. It deliberately does NOT touch:
#   * ~/.ssh/config — that is the alias plane (scripts/seed-seat-ssh-config.sh);
#   * the key files — re-encoding them makes System32 load them (measured rc 0) but forks this
#     seat's copy from the vault export and from every other seat; ruled out in HD-1123, re-asserted
#     here, and the render REFUSES a block that points at System32 so the rejected fix cannot regrow;
#   * PATH — a PATH edit changes which ssh every other program on the box gets, and still leaves the
#     verdict to directory order, which is the accident this plane exists to remove.
#
# VERDICTS (the same three the partner alias plane uses, plus the boundary)
#   IN SYNC (0)    every profile carries the current block AND a profile-loaded shell answers with
#                  the OpenSSL build.
#   MISSING/STALE(1) no block, or the block predates ssh/transport-block.ps1 — `--push` fixes it.
#   REFUSAL (3)    a hand-edited block (its digest line no longer matches the bytes beside it), or a
#                  shadow: a `function ssh` / `Set-Alias ssh` outside the markers — the same
#                  "two mechanisms, last one wins" class that made `Host ap-dnevna` exist twice.
#                  `--force` overrides a hand-edit ONLY, never a shadow.
#   SKIP (2)       not a Windows seat, or no OpenSSL build resolves here. A boundary prints SKIP and
#                  is never a pass (CONVENTIONS §6).
#
# USAGE
#   bash scripts/seat-ssh-build.sh                     # report, write nothing
#   bash scripts/seat-ssh-build.sh --check --strict    # same, rc 1/3 on drift (the gate form)
#   bash scripts/seat-ssh-build.sh --push              # install/refresh the block, dated .bak first
#   bash scripts/seat-ssh-build.sh --render            # print the rendered block for this seat
#   bash scripts/seat-ssh-build.sh --prove             # the canary: pinned vs -NoProfile MUST differ
#   bash scripts/seat-ssh-build.sh --self-test         # offline fixtures: no Windows, no PowerShell
#
# Env hooks (all optional; the fixture hooks are what let --self-test run on a Debian seat):
#   GIT_BUNDLED_SSH=<path>    pin the build explicitly (same variable git-bootstrap-win11.sh reads)
#   SEAT_SSH_TRANSPORT=<file> the template                (default ssh/transport-block.ps1)
#   SEAT_SSH_PROFILES=<files> colon-separated profile paths, bypassing discovery (fixtures)
#
# Owning rule: docs/network-vpn.md, section "The laptop alias contract" · CONVENTIONS §6.
# HD-1118 Stage 3 relocates harness scripts to `scripts/harness/` — the path may move, the contract
# does not.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
TMPL="${SEAT_SSH_TRANSPORT:-$SCRIPT_DIR/../ssh/transport-block.ps1}"
HD="HD-1128"
MARK_START="# >>> seat-ssh-build: $HD >>>"
MARK_END="# <<< seat-ssh-build: $HD <<<"
MODE="check"; STRICT=0; FORCE=0; FIXTURE=0; SCRATCH=""

usage() {
  cat <<'EOF'
usage: seat-ssh-build.sh [--check [--strict]] | --push | --render | --prove | --self-test [--force]
  --check    report only (default) · --strict makes any drift exit 1 (the validate-all form)
  --push     write the marker block into each installed shell's profile, dated .bak first
  --render   print the rendered block · --prove  pinned-vs-NoProfile canary
  --self-test  offline fixtures: no Windows, no PowerShell
exit: 0 in sync · 1 missing or stale · 2 usage / not-a-Windows-seat / no OpenSSL build resolves (SKIP)
      3 REFUSAL (a hand-edit, or a shadowing ssh definition)
EOF
}

err() { printf 'seat-ssh-build: %s\n' "$*" >&2; }
scratch() {
  [ -n "$SCRATCH" ] && return 0
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/seatsshbuild.XXXXXX")" || { err "mktemp failed"; exit 2; }
}
cleanup() { [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE="check" ;;
    --strict) STRICT=1 ;;
    --push) MODE="push" ;;
    --render) MODE="render" ;;
    --prove) MODE="prove" ;;
    --self-test) MODE="selftest" ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
  shift
done
command -v sha256sum >/dev/null 2>&1 || { err "sha256sum is required — the digest verdict cannot be computed"; exit 2; }
[ -r "$TMPL" ] || { err "template not readable: $TMPL"; exit 2; }

is_windows() { case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac; }
shell_exe() { case "$1" in powershell) printf 'powershell.exe\n' ;; pwsh) printf 'pwsh.exe\n' ;; esac; }

# --- the pinned build: resolve it, then PROVE it is the OpenSSL one ----------------
# Candidates, in order. The 8.3 form is first on purpose and not for tidiness: OpenSSH builds the
# ProxyCommand for a ProxyJump out of its own path UNQUOTED, so a pinned path containing a space
# makes every jumped leg die `/bin/sh: line 1: /c/Program: No such file or directory` — measured both
# ways in one session, and the reason git-bootstrap-win11.sh pins `C:/PROGRA~1/...` too.
candidates() {
  # An explicit pin is asserted, not preferred: no silent fallthrough to a different binary behind
  # the operator's back (or behind a fixture's), which would re-import the PATH accident this plane
  # exists to remove — and would let arm 7 "pass" on a host that merely happens to have Git.
  if [ -n "${GIT_BUNDLED_SSH:-}" ]; then printf '%s\n' "$GIT_BUNDLED_SSH"; return 0; fi
  printf '%s\n' 'C:/PROGRA~1/Git/usr/bin/ssh.exe'
  printf '%s\n' 'C:/Program Files/Git/usr/bin/ssh.exe'
}
# Classify on the CRYPTO LIBRARY, and LibreSSL FIRST. Both version strings contain "OpenS", so a
# classifier keyed on the product name reports the Windows build as OpenSSL and every verdict below
# then reports a green it did not earn. --self-test arms 1+2 hold both directions down.
classify_build() {
  case "$1" in
    *LibreSSL*) printf 'LIBRESSL\n' ;;
    *OpenSSL*)  printf 'OPENSSL\n' ;;
    *)          printf 'UNKNOWN\n' ;;
  esac
}
to_posix() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1" 2>/dev/null || printf '%s' "$1"; else printf '%s' "$1"; fi
}
probe_build() {
  local x; x="$(to_posix "$1")"
  if [ -x "$x" ] || command -v "$x" >/dev/null 2>&1; then "$x" -V 2>&1 | head -1; return 0; fi
  return 1
}
# Prints "<path>\t<version line>". rc 2 when nothing resolves, or the only things on disk are builds
# that cannot load the keys. Never guesses, never defaults (CONVENTIONS §2).
resolve_build() {
  local c v cls looked=""
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    case "$c" in *' '*) looked="$looked$c (contains a space: ProxyJump would split it), "; continue ;; esac
    if [ ! -e "$c" ]; then looked="$looked$c (absent), "; continue; fi
    if ! v="$(probe_build "$c")"; then looked="$looked$c (not executable), "; continue; fi
    cls="$(classify_build "$v")"
    case "$cls" in
      OPENSSL)  printf '%s\t%s\n' "$c" "$v"; return 0 ;;
      LIBRESSL) err "$c is the LibreSSL build ($v) — the one that cannot load the keys; not a pin" ;;
      *)        err "$c reported an unclassifiable version ('$v') — refusing to pin an unknown build" ;;
    esac
  done < <(candidates | awk '!seen[$0]++')
  err "no OpenSSL ssh build resolves here (looked at: ${looked:-nothing})"
  return 2
}

# --- the render, its assertions, the digest ---------------------------------------
render_body() {
  local bin="$1" line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line//@SSH_BIN@/$bin}"
    case "$line" in
      # The PLACEHOLDER SHAPE, not merely an at-sign: a typo'd name must fail the render instead of
      # landing in a profile as the literal text `@SSH_BIN@`.
      *'@'[A-Za-z0-9_]*'@'*) err "ssh/transport-block.ps1: unresolved placeholder in '$line'"; return 1 ;;
    esac
    printf '%s\n' "$line"
  done < "$TMPL"
}
# Run on EVERY render, including the one about to be written: an assertion that only runs in
# --self-test is an assertion a template edit can disable.
assert_body() {
  local f="$1" pin bad=0
  scratch
  # Non-ASCII detected by DELETION, not by a bracket expression: MSYS grep and gawk disagree about \r
  # inside brackets, and a false positive here would refuse every honest template (CONVENTIONS: a gate
  # that reds on the healthy case is a gate that gets muted).
  [ -n "$(LC_ALL=C tr -d '\040-\176\t\r\n' < "$f" | head -c1)" ] && {
    err "FAIL: the rendered block carries a non-ASCII byte — Windows PowerShell 5.1 reads a BOM-less UTF-8 profile as cp1252 and dies on it"
    bad=1; }
  # The PINNED PATH is the assertion, not the word System32: the block's own fallback WARNING names
  # System32 on purpose (it is what the operator is being warned about), and an assignment-level check
  # is the one that a comment cannot satisfy. --self-test arm 8 reddens it by substituting that path.
  pin="$(awk -F"'" '/^[[:space:]]*\$HomelabSshBin[[:space:]]*=/ {print $2; exit}' "$f")"
  case "${pin:-}" in
    "")            err "FAIL: the rendered block never assigns \$HomelabSshBin — it pins nothing"; bad=1 ;;
    *@SSH_BIN@*)   err "FAIL: \$HomelabSshBin still carries the placeholder — the build was never substituted"; bad=1 ;;
    *[Ss]ystem32*) err "FAIL: the rendered block NAMES a System32 path as the pinned build ($pin) — that is the build this plane exists to avoid, and HD-1123 rejected re-encoding the keys to make it work"; bad=1 ;;
  esac
  grep -q 'function global:ssh' "$f" || { err "FAIL: the rendered block defines no ssh function — it pins nothing"; bad=1; }
  grep -q 'PI_SSH_BIN' "$f"          || { err "FAIL: the rendered block does not set PI_SSH_BIN — a harness launched from this shell would resolve ssh off PATH again"; bad=1; }
  return "$bad"
}
hash_file() { printf '%s\n' "$(cat "$1")" | sha256sum | cut -c1-12; }
build_block() {
  local bin="$1" block="$2" body="$3" dig
  render_body "$bin" > "$body" || return 1
  printf '%s\n' "$(cat "$body")" > "$body"          # exactly one trailing newline: render ≡ extracted
  assert_body "$body" || return 1
  dig="$(hash_file "$body")"
  { printf '%s\n' "$MARK_START"
    printf '# seat-ssh-build: win11 sha256=%s\n' "$dig"
    cat "$body"
    printf '%s\n' "$MARK_END"; } > "$block"
}
# Spliced in BASH, not with awk/sed, and that is a measured choice, not a style one: MSYS awk strips the
# CR of a CRLF pair in text mode, so an awk splice SILENTLY rewrote every line ending outside the markers
# — which --self-test arm 4 caught on this host the first time it ran. A real PowerShell profile is CRLF,
# so "copies the bytes through" has to mean the bytes. `read -r` keeps the CR in the line, and the marker
# is compared after removing it, so CRLF and LF profiles both splice without touching the rest (CONVEN-
# TIONS §6: "a gate that passes in my shell is red in an agent's shell" — the inverse applies here).
# One documented byte change: a profile that did not end in a newline gains exactly one, because the
# block has to start on its own line.
splice() {
  local mode="$1" f="$2" line l inside=0
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    l="${line%$'\r'}"
    if [ "$l" = "$MARK_START" ]; then
      [ "$inside" = 0 ] || err "WARN: a second $MARK_START in $f — two blocks, last-loaded wins; collapse them"
      inside=1; continue
    fi
    if [ "$l" = "$MARK_END" ]; then inside=0; continue; fi
    if [ "$mode" = extract ] && [ "$inside" = 1 ]; then printf '%s\n' "$line"
    elif [ "$mode" = strip ] && [ "$inside" = 0 ]; then printf '%s\n' "$line"; fi
  done < "$f"
}
strip_block()  { splice strip "$1"; }
extract_block() { splice extract "$1"; }
installed_dig() { extract_block "$1" | grep -v '^# seat-ssh-build: ' > "$2" && hash_file "$2"; }
# A second mechanism naming `ssh` is a shadow: profiles dot-source in order, so last-defined wins
# and a current block can be perfectly inert.
find_shadows() {
  local f="$1"
  [ -f "$f" ] || return 0
  strip_block "$f" | grep -nE '^[[:space:]]*(function|filter)[[:space:]]+(global:)?ssh[[:space:]]*[{(]|^[[:space:]]*(Set|New)-Alias[[:space:]]+(-Name[[:space:]]+)?ssh([[:space:]]|$)' || true
}

# --- one pass against one profile file (PROF) --------------------------------------
# Sets OUT_RC to the verdict and prints it. --push writes only when it is allowed to.
check_profile() {
  local block body out inst fresh_dig got_dig inst_dig shadows rc tmp ts
  rc=0; SHADOWED=0; DUPED=0
  scratch
  block="$SCRATCH/block"; body="$SCRATCH/body"; out="$SCRATCH/outside"; inst="$SCRATCH/installed"
  build_block "$BUILD_PATH" "$block" "$body" || { err "the render failed its own assertions — nothing written"; OUT_RC=2; return 2; }
  fresh_dig="$(sed -n 's/.*sha256=\([0-9a-f]*\).*/\1/p' "$block" | head -1)"

  if [ ! -f "$PROF" ]; then
    printf 'MISSING: %s does not exist — this shell has no profile, so a bare ssh here is PATH, and PATH is the System32 build\n' "$PROF"
    rc=1
  elif ! grep -qF "$MARK_START" "$PROF"; then
    printf 'MISSING: %s carries no ssh-build block — this shell resolves ssh off PATH (the LibreSSL build)\n' "$PROF"
    rc=1
  else
    strip_block "$PROF" > "$out"
    shadows="$(find_shadows "$PROF")"
    inst_dig="$(installed_dig "$PROF" "$inst")"
    got_dig="$(sed -n 's/^# seat-ssh-build: [a-z0-9-]* sha256=\([0-9a-f]*\).*/\1/p' "$PROF" | head -1)"
    if [ -z "$got_dig" ]; then
      printf 'REFUSAL(hand-edit): the block in %s carries no digest line, so this script did not write it\n' "$PROF"
      printf '  → diff it against `--render`, fold what you learn into ssh/transport-block.ps1, then --force\n'
      rc=3
    elif [ "$inst_dig" != "$got_dig" ]; then
      printf 'REFUSAL(hand-edit): the installed block hashes %s but declares %s — a human edited it in place\n' "$inst_dig" "$got_dig"
      printf '  → NOTHING was written. Reconcile the edit with ssh/transport-block.ps1, then re-run with --force\n'
      rc=3
    elif [ "$got_dig" != "$fresh_dig" ]; then
      printf 'STALE: the installed block (%s) predates ssh/transport-block.ps1 (%s) — replacing it is the fix\n' "$got_dig" "$fresh_dig"
      rc=1
    else
      printf 'IN SYNC: %s carries the ssh-build block (digest %s)\n' "$PROF" "$fresh_dig"
      rc=0
    fi
    if [ "$(grep -cF "$MARK_START" "$PROF")" != 1 ]; then
      DUPED=1
      printf 'REFUSAL(duplicate): %s carries more than one %s — two blocks, and the last one loaded is the live one\n' "$PROF" "$MARK_START"
      printf '  → collapse them by hand (dated .bak first); this plane will not guess which half is the survivor\n'
      rc=3
    fi
    if [ -n "$shadows" ]; then
      SHADOWED=1
      printf 'REFUSAL(shadow): ssh is ALSO defined outside the markers, so two mechanisms remain and the last one loaded wins:\n'
      printf '  %s\n' "$shadows"
      printf '  → remove that definition; --force does NOT override a shadow\n'
      rc=3
    fi
  fi

  OUT_RC="$rc"
  [ "$MODE" = "check" ] && return "$rc"
  if [ "$rc" = 0 ]; then echo "already current: $PROF — nothing written"; return 0; fi
  # --force overrides OUR OWN stale/hand-edited text and nothing else: beside a shadow or a duplicate
  # block, writing another copy of the block leaves the verdict to load order while reporting success,
  # which is the failure this plane exists to remove. (Measured: --force turned a shadow REFUSAL into
  # rc 0, i.e. the one arm that could have caught it reported the shadow as fixed.)
  if [ "$rc" = 3 ] && { [ "$SHADOWED" = 1 ] || [ "$DUPED" = 1 ] || [ "$FORCE" != 1 ]; }; then
    err "REFUSED: nothing written to $PROF (--force overrides a hand-edit only, never a shadow or a duplicate block)"
    return 3
  fi
  tmp="$SCRATCH/next"
  mkdir -p "$(dirname "$PROF")" 2>/dev/null || true
  if [ -f "$PROF" ]; then
    ts="$(date -u +%Y%m%d-%H%M%S)"
    cp -p "$PROF" "$PROF.bak-$ts" && echo "  backup: $PROF.bak-$ts"
    strip_block "$PROF" > "$tmp"          # every byte outside the markers is copied through
  else
    : > "$tmp"
  fi
  cat "$block" >> "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$PROF"
  # Report what LANDED, not what was meant: re-read and re-hash.
  if grep -qxF "$MARK_START" "$PROF" && [ "$(installed_dig "$PROF" "$inst")" = "$fresh_dig" ]; then
    echo "  wrote $PROF (digest $fresh_dig)"
    OUT_RC=0; return 0
  fi
  err "FAIL: the block did not land in $PROF as written — reported, not assumed"
  OUT_RC=1; return 1
}

# --- profile discovery: asked of the shells, never assembled from $HOME ------------
# On this seat "Documents" is OneDrive-redirected, so a path built from $HOME points at a directory
# PowerShell never reads — which is how a seat ends up "pinned" in a file no shell loads.
discover_profiles() {
  local sh exe out
  for sh in powershell pwsh; do
    exe="$(shell_exe "$sh")"
    command -v "$exe" >/dev/null 2>&1 || { printf 'SKIP: %s is not installed on this seat\n' "$exe"; continue; }
    out="$("$exe" -NoProfile -NoLogo -Command '$PROFILE.CurrentUserAllHosts' 2>/dev/null | tr -d '\r' | tail -1)"
    [ -n "$out" ] || { err "$exe did not answer \$PROFILE.CurrentUserAllHosts"; continue; }
    printf '%s\t%s\n' "$exe" "$(to_posix "$out")"
  done
}
# Which build a PROFILE-LOADED shell actually runs, asked with the PATH a NORMAL terminal has.
# Why the PATH is rebuilt from the registry rather than inherited: when this script runs under Git-Bash,
# the child PowerShell inherits the MSYS PATH — Git\usr\bin first — and then answers OpenSSL whether or
# not the block is doing anything. That is a probe that cannot fail (CONVENTIONS §6), and it is exactly
# how this seat stayed green in prose while pwsh failed.
#
# Prints "<version line>\t<class>\t<LOADED|BLOCKED|UNKNOWN>"; rc 1 only when the shell did not answer.
# BLOCKED is the OTHER way a profile plane dies, and it is real on this seat: Windows PowerShell 5.1
# here has script execution disabled, so it loads NO profile at all — not ours, not the operator's own
# oh-my-posh line. A profile plane must name that instead of reporting drift forever, because a gate
# that reds on a state no --push can change is a gate that gets muted.
probe_shell() {
  local exe="$1" out v blocked=0
  out="$("$exe" -NoLogo -Command "$CLEAN_PATH ssh -V" 2>&1)"
  printf '%s' "$out" | grep -qiE 'running scripts is disabled|cannot be loaded because' && blocked=1
  v="$(printf '%s' "$out" | tr -d '\r' | grep -i 'OpenSSH' | head -1)"
  [ -n "$v" ] || [ "$blocked" = 1 ] || return 1
  printf '%s\t%s\t%s\n' "${v:-<no answer>}" "$(classify_build "$v")" "$([ "$blocked" = 1 ] && printf 'BLOCKED' || printf 'LOADED')"
}
# The classifier on its own, so --self-test can prove it keys on the message and not on luck.
blocked_msg() { case "$1" in *'running scripts is disabled'*|*'cannot be loaded because'*) printf 'BLOCKED\n' ;; *) printf 'LOADED\n' ;; esac; }
CLEAN_PATH='$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User"); '
worst() { case "$1$2" in *3*) printf 3 ;; *1*) printf 1 ;; *2*) printf 2 ;; *) printf 0 ;; esac; }
# The last verdict, given what the LIVE probes answered. Precedence is the whole point, and it is a pure
# function so --self-test arm 14 can drive it without a PowerShell in sight:
#   a refusal or a real drift outranks everything (never soften a finding to make a run green);
#   otherwise ONE reachable shell that answered OpenSSL is a PROOF → 0, and a policy-blocked shell is a
#   NOTE printed beside it — a permanent red on a state no --push can change is how a gate gets muted;
#   otherwise, if the only thing that answered was a blocked shell → 2 SKIP, never a silent pass.
final_rc() {
  local f="$1" ok="$2" bl="$3" fx="$4"
  case "$f" in 3) printf 3; return 0 ;; 1) printf 1; return 0 ;; esac
  [ "$fx" = 1 ] && { printf '%s' "$f"; return 0; }
  [ "$ok" != 0 ] && { printf 0; return 0; }
  [ "$bl" != 0 ] && { printf 2; return 0; }
  printf '%s' "$f"
}

# --- self-test: offline fixtures. No Windows, no PowerShell, no network ------------
selftest() {
  local root fails=0 before after rc got
  root="$(mktemp -d "${TMPDIR:-/tmp}/seatsshbuild-selftest.XXXXXX")"
  fails=0
  ok()  { printf '  ok   %s\n' "$1"; }
  no()  { printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
  has() { if grep -q "$2" "$1"; then printf '  ok   %s\n' "$3"; else no "$3 (no '$2' in $(tr '\n' ' ' <"$1" | cut -c1-160))"; fi; }
  mk_stub() { printf '#!/bin/sh\necho "%s" >&2\n' "$2" > "$1"; chmod +x "$1"; }
  # run EXPECT ARGS... — the fixture hook keeps this off any real HOME / any real shell.
  run() {
    local want="$1"; shift
    SEAT_SSH_PROFILES="$PROF1" GIT_BUNDLED_SSH="$STUB" bash "$SELF" "$@" >"$root/out" 2>&1
    got=$?
    [ "$got" = "$want" ] || no "expected rc $want, got $got — $(tr '\n' ' ' <"$root/out" | cut -c1-200)"
  }
  PROF1="$root/pwsh.ps1"
  STUB="$root/ssh-stub"; mk_stub "$STUB" 'OpenSSH_10.5p1, OpenSSL 3.5.7 9 Jun 2026'

  # 1+2: the classifier, BOTH directions. Arm 2 is the canary: a classifier that keyed on "OpenSSH"
  # would pass arm 1 and pass every live seat while pinning nothing.
  [ "$(classify_build 'OpenSSH_10.5p1, OpenSSL 3.5.7 9 Jun 2026')" = OPENSSL ] \
    && ok "1 classifies the Git-bundled build as OpenSSL" || no "1 the Git build did not classify as OpenSSL"
  [ "$(classify_build 'OpenSSH_for_Windows_9.5p2, LibreSSL 3.8.2')" = LIBRESSL ] \
    && ok "2 classifies the Windows build as LibreSSL (canary: keys on the library, not the product)" || no "2 the classifier calls the Windows build OpenSSL — every verdict below would be mute"

  # 3: no profile at all -> MISSING, then --push creates it and it reads IN SYNC.
  rm -f "$PROF1"
  run 1 --check; has "$root/out" 'MISSING' "3 reports MISSING when the profile does not exist"
  run 0 --push
  [ -f "$PROF1" ] && ok "3a --push created the profile" || no "3a --push created nothing"
  run 0 --check

  # 4: a human's profile bytes survive a replacement byte for byte (CONVENTIONS: copied through).
  { printf 'oh-my-posh init pwsh | Invoke-Expression\r\n'; printf 'Import-Module Z\r\n'; } > "$PROF1"
  cp "$PROF1" "$root/foreign.before"
  run 1 --check
  run 0 --push
  strip_block "$PROF1" > "$root/foreign.after"
  cmp -s "$root/foreign.before" "$root/foreign.after" \
    && ok "4 everything outside the markers is copied through unchanged" || no "4 --push changed bytes outside the markers"
  has "$PROF1" 'oh-my-posh' "4a the human's own profile line is still there"

  # 5: a hand-edit inside the block -> REFUSAL, with proof the file did not move.
  sed -i 's/^function global:ssh {$/function global:ssh { Write-Host "hand edit"/' "$PROF1"
  before="$(sha256sum < "$PROF1")"        # AFTER the edit: 5a measures the REFUSAL, not the sed
  run 3 --check; has "$root/out" 'REFUSAL(hand-edit)' "5 a hand-edited block is a REFUSAL"
  run 3 --push
  after="$(sha256sum < "$PROF1")"
  [ "$before" = "$after" ] && ok "5a the REFUSAL wrote nothing (file hash unchanged)" || no "5a the REFUSAL modified the file"
  run 0 --push --force
  grep -q 'hand edit' "$PROF1" && no "5b --force left the hand-edit in place" || ok "5b --force replaced the hand-edited block"

  # 6: a shadow outside the markers -> REFUSAL that --force does NOT override.
  run 0 --check
  printf '\nfunction ssh { & "C:/Windows/System32/OpenSSH/ssh.exe" @args }\n' >> "$PROF1"
  run 3 --check; has "$root/out" 'REFUSAL(shadow)' "6 a second ssh definition outside the markers is a REFUSAL"
  run 3 --push --force; has "$root/out" 'REFUSAL' "6a --force does NOT override a shadow"

  # 7: the pinned build must be an OpenSSL one — both ways round. (Fresh fixture: arms 7-9 assert on
  # the build/render contract, and inheriting arm 6's shadow line would make every one of them a
  # shadow REFUSAL — a green that measures the wrong thing.)
  rm -f "$PROF1"
  mk_stub "$root/libssh" 'OpenSSH_for_Windows_9.5p2, LibreSSL 3.8.2'
  SEAT_SSH_PROFILES="$PROF1" GIT_BUNDLED_SSH="$root/libssh" bash "$SELF" --check >"$root/out" 2>&1
  [ "$?" = 2 ] && ok "7 a LibreSSL-only box reports SKIP (rc 2), never a pass" || no "7 pinned a LibreSSL build (rc $?)"
  SEAT_SSH_PROFILES="$PROF1" GIT_BUNDLED_SSH="$root/absent" bash "$SELF" --push >"$root/out" 2>&1
  [ "$?" = 2 ] && ok "7a a build that is not there is a refusal, not a default" || no "7a wrote a block naming a build that does not exist"

  # 8: poisoned templates must fail the RENDER (and one control must not).
  sed 's|@SSH_BIN@|C:/Windows/System32/OpenSSH/ssh.exe|' "$TMPL" | sed 's|^[[:space:]]*#.*||' > "$root/t-sys32"
  SEAT_SSH_PROFILES="$PROF1" SEAT_SSH_TRANSPORT="$root/t-sys32" GIT_BUNDLED_SSH="$STUB" bash "$SELF" --push >"$root/out" 2>&1
  rc=$?; { [ "$rc" != 0 ] && grep -q 'System32' "$root/out"; } \
    && ok "8 a template pinning System32 fails the render (the rejected HD-1123 fix cannot regrow)" || no "8 a template pinning System32 passed (rc $rc)"
  sed 's|@SSH_BIN@|@SSH_BUIL@|' "$TMPL" > "$root/t-open"   # an UNKNOWN name, not the same one again
  SEAT_SSH_PROFILES="$PROF1" SEAT_SSH_TRANSPORT="$root/t-open" GIT_BUNDLED_SSH="$STUB" bash "$SELF" --push >"$root/out" 2>&1
  rc=$?; [ "$rc" != 0 ] && ok "8b an unresolved placeholder fails the render (rc $rc)" || no "8b an unresolved placeholder would have shipped"
  sed 's/function global:ssh/function global:zzsh/' "$TMPL" > "$root/t-none"
  SEAT_SSH_PROFILES="$PROF1" SEAT_SSH_TRANSPORT="$root/t-none" GIT_BUNDLED_SSH="$STUB" bash "$SELF" --push >"$root/out" 2>&1
  rc=$?; { [ "$rc" != 0 ] && grep -q 'defines no ssh function' "$root/out"; } \
    && ok "8c a template that pins nothing fails the render" || no "8c a template that pins nothing passed (rc $rc)"
  sed 's/\r$//' "$TMPL" | tr -d '\r' > "$root/t-clean"; sed -i 's/$//' "$root/t-clean"
  SEAT_SSH_PROFILES="$PROF1" SEAT_SSH_TRANSPORT="$root/t-clean" GIT_BUNDLED_SSH="$STUB" bash "$SELF" --push >"$root/out" 2>&1
  rc=$?; { [ "$rc" = 0 ] || [ "$rc" = 1 ]; } && ok "8d the unmodified template is NOT refused (the control)" || no "8d the control arm failed (rc $rc): $(tr '\n' ' ' <"$root/out" | cut -c1-160)"

  # 9: non-ASCII in the block must fail the render (the PS 5.1 cp1252 profile trap).
  { printf '\n# an em dash follows —\n'; cat "$TMPL"; } > "$root/t-ascii"
  SEAT_SSH_PROFILES="$PROF1" SEAT_SSH_TRANSPORT="$root/t-ascii" GIT_BUNDLED_SSH="$STUB" bash "$SELF" --push >"$root/out" 2>&1
  rc=$?; { [ "$rc" != 0 ] && grep -q 'non-ASCII' "$root/out"; } \
    && ok "9 non-ASCII in the block fails the render (Windows PowerShell 5.1 reads cp1252)" || no "9 non-ASCII would have shipped (rc $rc)"

  # 10: the digest keys on the build PATH, so a moved Git reads as STALE — not as in-sync.
  rm -f "$PROF1"; run 0 --push; run 0 --check
  mk_stub "$root/ssh-stub2" 'OpenSSH_10.5p1, OpenSSL 3.5.7 9 Jun 2026'
  SEAT_SSH_PROFILES="$PROF1" GIT_BUNDLED_SSH="$root/ssh-stub2" bash "$SELF" --check >"$root/out" 2>&1
  rc=$?; [ "$rc" = 1 ] && ok "10 a changed build path reads STALE (rc 1)" || no "10 a moved build read rc $rc, not 1"

  # 11: an unrelated profile file is MISSING, never IN SYNC.
  printf '# something else entirely\n' > "$PROF1"
  run 1 --check; has "$root/out" 'MISSING' "11 an unrelated profile reads MISSING, not IN SYNC"

  # 12: the live probe must exist and be wired into the check path — the file scan alone cannot see
  # load order, and this is the arm that keeps --check from degrading into a diff.
  grep -q 'probe_shell' "$SELF" && awk '/^MODE=|probe_shell/{print}' "$SELF" | grep -q . \
    && ok "12 the live probe is wired in (the file scan alone cannot see which build answers)" \
    || no "12 no live probe: --check would be a file diff only"

  # 13: the execution-policy classifier, BOTH ways. A profile plane that cannot tell "my block is inert"
  # from "this shell loads no profile at all" reports red forever on a state no --push can change, and a
  # permanently-red gate gets muted. Win11's Windows PowerShell 5.1 on this seat is that state.
  [ "$(blocked_msg '. : File C:\x\profile.ps1 cannot be loaded because running scripts is disabled on this system.')" = BLOCKED ] \
    && ok "13 a disabled-script shell classifies as BLOCKED, not as drift" || no "13 the policy block would read as drift"
  [ "$(blocked_msg 'OpenSSH_10.5p1, OpenSSL 3.5.7 9 Jun 2026')" = LOADED ] \
    && ok "13a a normal answer classifies as LOADED (canary: the classifier is not matching everything)" || no "13a everything classifies as BLOCKED — the SKIP would hide real drift"

  # 14: the verdict PRECEDENCE, driven as the pure function it is (a permanent red on a policy-blocked
  # shell mutes the gate; a permanent SKIP on a working seat hides it; a softened finding lies).
  [ "$(final_rc 0 0 1 0)" = 2 ] && ok "14 blocked-and-nothing-proven reads SKIP (2), not green" || no "14 an unproven seat would read green"
  [ "$(final_rc 0 1 1 0)" = 0 ] && ok "14a one proven shell outranks a blocked one (green + NOTE)" || no "14a a proven shell was downgraded by a boundary"
  [ "$(final_rc 1 1 1 0)" = 1 ] && ok "14b real drift still reds beside a blocked shell" || no "14b drift was masked by the boundary"
  [ "$(final_rc 3 1 0 0)" = 3 ] && ok "14c a REFUSAL outranks everything" || no "14c a REFUSAL was outranked"

  rm -rf "$root"
  [ "$fails" = 0 ] || { err "SELF-TEST FAILED: $fails arm(s)"; return 1; }
  echo "seat-ssh-build: self-test OK (offline fixtures; no Windows, no PowerShell, nothing written outside the fixture)"
  return 0
}

# --- main -------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then selftest; exit $?; fi

if ! is_windows && [ -z "${SEAT_SSH_PROFILES:-}" ]; then
  echo "SKIP: not a Windows seat (uname: $(uname -s)) — this plane owns only the win11 seat's PowerShell profiles; the other seats run one OpenSSL build already"
  exit 2
fi

BUILD_LINE="$(resolve_build)" || exit 2
BUILD_PATH="$(printf '%s' "$BUILD_LINE" | cut -f1)"
BUILD_VER="$(printf '%s' "$BUILD_LINE" | cut -f2-)"
echo "pinned ssh build: $BUILD_PATH  ($BUILD_VER)"

if [ "$MODE" = "render" ]; then
  scratch; build_block "$BUILD_PATH" "$SCRATCH/b" "$SCRATCH/o" || exit 2
  cat "$SCRATCH/b"; exit 0
fi

if [ -n "${SEAT_SSH_PROFILES:-}" ]; then
  FIXTURE=1
  TARGETS=""
  for p in $(printf '%s' "$SEAT_SSH_PROFILES" | tr ':' ' '); do
    TARGETS="${TARGETS}$(printf 'fixture\t%s\n' "$p")"
  done
else
  TARGETS="$(discover_profiles)"
  [ -n "$(printf '%s' "$TARGETS" | grep -v '^SKIP')" ] || { err "no PowerShell answered a profile path — cannot name a file to pin"; exit 2; }
fi

if [ "$MODE" = "prove" ]; then
  # The canary: same host, same config, two shells. The profile-loaded one must answer OpenSSL and
  # -NoProfile must answer something else. If they agree, this plane proves nothing and says so
  # (CONVENTIONS §6: a test that cannot fail is not evidence).
  rc=0
  for exe in powershell.exe pwsh.exe; do
    command -v "$exe" >/dev/null 2>&1 || { echo "SKIP: $exe is not installed here"; continue; }
    pout="$("$exe" -NoLogo -Command "$CLEAN_PATH ssh -V" 2>&1)"
    pin="$(printf '%s' "$pout" | tr -d '\r' | grep -i openssh | head -1)"
    raw="$("$exe" -NoProfile -Command "$CLEAN_PATH ssh -V" 2>&1 | tr -d '\r' | grep -i openssh | head -1)"
    if [ "$(blocked_msg "$pout")" = BLOCKED ]; then
      printf '  SKIP: %-14s loads no profile at all (script execution is disabled for this shell) — nothing to prove here; the pin cannot reach it\n' "$exe"
      continue
    fi
    printf '  %-16s profile: %-44s | -NoProfile: %s\n' "$exe" "${pin:-<no answer>}" "${raw:-<no answer>}"
    [ "$(classify_build "$pin")" = OPENSSL ] \
      || { err "FAIL: $exe still resolves the $(classify_build "$pin") build with its profile loaded"; rc=1; }
    [ "$(classify_build "$pin")" != "$(classify_build "$raw")" ] \
      || { err "NOT PROVEN: $exe answers the SAME build with and without the profile — either PATH already resolves OpenSSL on this seat, or the block is not taking effect. --check says which."; rc=1; }
  done
  [ "$rc" = 0 ] && echo "PROVEN: the block is what changes the answer on this seat"
  exit "$rc"
fi

worst_rc=0
while IFS=$'\t' read -r sh prof; do
  [ -n "$prof" ] || continue
  case "$sh" in SKIP*) printf '%s\n' "$sh"; continue ;; esac
  printf -- '-- %s profile: %s\n' "$sh" "$prof"
  PROF="$prof" check_profile "$prof"; r="${OUT_RC:-1}"
  worst_rc="$(worst "$worst_rc" "$r")"
done <<EOF
$TARGETS
EOF

# The end-to-end half of the verdict (fixtures have no shells to ask).
LIVE_OK=0; LIVE_BLOCKED=0
if [ "$FIXTURE" = 0 ] && [ "$MODE" = "check" ]; then
  for sh in powershell pwsh; do
    exe="$(shell_exe "$sh")"; command -v "$exe" >/dev/null 2>&1 || continue
    line="$(probe_shell "$exe")" || { echo "  SKIP: $exe did not answer 'ssh -V' with its profile loaded"; continue; }
    ver="$(printf '%s' "$line" | cut -f1)"; cls="$(printf '%s' "$line" | cut -f2)"; st="$(printf '%s' "$line" | cut -f3)"
    if [ "$st" = BLOCKED ]; then
      echo "  NOTE: $exe loads NO profile at all (script execution is disabled for this shell) — the block is correct on disk and unreachable here; the only move is the operator's: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
      LIVE_BLOCKED=$((LIVE_BLOCKED+1)); continue
    fi
    case "$cls" in
      OPENSSL)  echo "  $exe resolves: OpenSSL  ($ver)"; LIVE_OK=$((LIVE_OK+1)) ;;
      LIBRESSL) echo "  DRIFT: $exe still resolves the LibreSSL build ($ver) — the block is missing here, or present but inert"; worst_rc="$(worst "$worst_rc" 1)" ;;
      *)        echo "  SKIP: $exe answered an unclassifiable version ('$ver')" ;;
    esac
  done
  # A boundary is not a pass, and it is not a failure either — but it must not OUTRANK a proof. If any
  # reachable shell answered OpenSSL the plane is green and the blocked shell is a NOTE; only when NO
  # shell was reachable does the run report SKIP. (Precedence matters here: a permanent red on a state no
  # --push can change is how a gate gets muted, and a permanent SKIP on a working seat is how a gate gets
  # ignored.)
  if [ "$worst_rc" = 0 ] && [ "$LIVE_OK" != 0 ]; then worst_rc=0
  elif [ "$worst_rc" = 0 ] && [ "$LIVE_BLOCKED" != 0 ]; then worst_rc=2; fi
fi
worst_rc="$(final_rc "$worst_rc" "$LIVE_OK" "$LIVE_BLOCKED" "$FIXTURE")"

case "$worst_rc" in
  0) echo "IN SYNC: a profile-loaded shell on this seat gets the OpenSSL build"
     [ "${LIVE_BLOCKED:-0}" = 0 ] || echo "  (one shell loads no profile at all — see the NOTE above)" ;;
  1) echo "DRIFT: run: bash scripts/seat-ssh-build.sh --push" ;;
  2) echo "SKIP: the block is on disk and correct, but no shell here loaded a profile, so nothing was PROVEN end-to-end" ;;
  3) echo "REFUSED: resolve the refusal above; --force overrides a hand-edit only" ;;
esac
if [ "$STRICT" = 1 ] && [ "$worst_rc" != 0 ]; then exit 1; fi
exit "$worst_rc"
