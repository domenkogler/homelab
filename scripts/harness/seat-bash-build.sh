#!/usr/bin/env bash
# =====================================================================
# seat-bash-build.sh — the Win11 seat's BASH BUILD plane.
#
# WHY THIS EXISTS
# ---------------
# `bash scripts/harness/pi-settings-config.sh --check` worked from Git-Bash and failed from pwsh on
# the SAME seat, in the SAME repo, with the SAME files. Nothing was broken in the repo: two different
# bash binaries answer on this box, and a Windows-native PATH selects the one that is not a bash seat
# at all.
#
#   C:\Program Files\Git\bin\bash.exe   MSYS/MINGW — $HOME = C:\Users\<op>, Windows node   (the seat)
#   C:\WINDOWS\system32\bash.exe        the WSL launcher — enters the WSL DEFAULT distro
#   C:\Users\...\WindowsApps\bash.exe   an app-execution alias for the same wsl.exe
#
# The machine PATH names C:\WINDOWS\system32 and, for Git, only `Git\cmd` — no PATH entry adds
# `Git\bin`, which is where Git's bash actually sits. So every Windows-native shell gets the WSL
# launcher for a bare `bash`, and the repo writes its harness commands as `bash scripts/...`. WSL
# keeps the Windows working directory (D:\x arrives as /mnt/d/x), so the repo IS found, the SSOT IS
# found, and then the script reads that distro's `$HOME` and that distro's `node` — a Windows
# node.exe over WSL interop cannot open a `/mnt/...` path, so it died with a stack trace and the
# settings plane reported "INVALID: /home/user/.pi/agent/settings.json is not parseable JSON" about
# a file it had never opened. This is HD-1128's ssh defect with a different binary: PATH decides
# which build a bare name is, and PATH is the accident. The fix names the build.
#
# WHAT IT WRITES
# --------------
# ONE marker-delimited block (rendered from win/bash-block.ps1) into the *current-user, all-hosts*
# profile of every PowerShell installed on the seat, so `powershell.exe` and `pwsh.exe` both resolve
# a bare `bash` to Git's build, and sets PI_BASH_BIN for a harness launched from that shell. It
# deliberately does NOT touch:
#   * PATH — a PATH edit changes which bash every other program on the box gets, and still leaves the
#     verdict to directory order, which is the accident this plane exists to remove;
#   * the WSL distro list — setting a different default distro would make a stray WSL bash report
#     ANOTHER seat's verdict under the `win11` label, which is a false green, i.e. worse than a loud
#     red;
#   * cmd.exe — not covered, and docs/harness-pi-seats.md says so rather than implying otherwise.
#
# VERDICTS (the same shape as the ssh-build plane)
#   IN SYNC (0)     every discovered profile carries the current block AND a profile-loaded shell
#                   answers `uname -s` with MINGW/MSYS — the behavioral half: what a bare `bash`
#                   actually IS, not what a path string looks like.
#   MISSING/STALE(1) no block, or the block predates the template — `--push` fixes it.
#   REFUSAL (3)     a hand-edited block (digest no longer matches the bytes beside it), a duplicate
#                   block, or a shadow: a `function bash` / `Set-Alias bash` outside the markers.
#                   `--force` overrides a hand-edit ONLY, never a shadow or a duplicate.
#   SKIP (2)        not a Windows seat, no Git bash resolves here, or no installed shell loads a
#                   profile. A boundary prints SKIP and is never a pass (CONVENTIONS §6).
#
# USAGE
#   bash scripts/harness/seat-bash-build.sh                    # report, write nothing
#   bash scripts/harness/seat-bash-build.sh --check --strict    # the gate form (rc 1/3 on drift)
#   bash scripts/harness/seat-bash-build.sh --push              # install/refresh, dated .bak first
#   bash scripts/harness/seat-bash-build.sh --render            # print the rendered block
#   bash scripts/harness/seat-bash-build.sh --prove             # what a bare `bash` IS, per shell
#   bash scripts/harness/seat-bash-build.sh --self-test          # offline fixtures, no PowerShell
#
# Env hooks (fixtures): GIT_BUNDLED_BASH=<path>  SEAT_BASH_BLOCK=<template>  SEAT_BASH_PROFILES=<a:b>
#
# Owning rule: docs/harness-pi-seats.md §1 (the seat × plane matrix) · CONVENTIONS §6 (a gate that
# cannot see the file cannot fail either; an environment boundary prints SKIP, never a pass).
set -uo pipefail

_hl_self="${BASH_SOURCE[0]}"
case "$_hl_self" in */*) _hl_d="${_hl_self%/*}" ;; *) _hl_d="." ;; esac
_hl_d="$(cd "$_hl_d" && pwd)"
SCRIPT_DIR="$_hl_d"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"
TMPL="${SEAT_BASH_BLOCK:-$SCRIPT_DIR/win/bash-block.ps1}"
MARK_START="# >>> seat-bash-build >>>"
MARK_END="# <<< seat-bash-build <<<"
MODE="check"; STRICT=0; FORCE=0; SCRATCH=""

usage() {
  cat <<'EOF'
usage: seat-bash-build.sh [--check [--strict]] | --push | --render | --prove | --self-test [--force]
  --check    report only (default) · --strict makes drift exit 1 (the validate-all form)
  --push     write the marker block into each installed shell's profile, dated .bak first
  --render   print the rendered block · --prove  ask each shell what a bare `bash` IS
  --self-test  offline fixtures: no Windows, no PowerShell
exit: 0 in sync · 1 missing/stale/still-the-WSL-launcher · 2 usage / not-a-Windows-seat /
      no Git bash resolves / no shell loads a profile (SKIP) · 3 REFUSAL (hand-edit, shadow, duplicate)
EOF
}

err() { printf 'seat-bash-build: %s\n' "$*" >&2; }
info() { printf '  %s\n' "$*"; }
scratch() {
  [ -n "$SCRATCH" ] && return 0
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/seatbashbuild.XXXXXX")" || { err "mktemp failed"; exit 2; }
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
to_posix() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1" 2>/dev/null || printf '%s' "$1"; else printf '%s' "$1"; fi
}

# --- the pinned build: resolve it, then PROVE it is a Git-Bash and not a launcher ---------------
# An explicit pin is ASSERTED, not preferred: no silent fallthrough to a different binary behind the
# operator's (or a fixture's) back, which would re-import the PATH accident this plane removes.
candidates() {
  if [ -n "${GIT_BUNDLED_BASH:-}" ]; then printf '%s\n' "$GIT_BUNDLED_BASH"; return 0; fi
  printf '%s\n' 'C:/Program Files/Git/bin/bash.exe'
  printf '%s\n' 'C:/PROGRA~1/Git/bin/bash.exe'
  printf '%s\n' 'C:/Program Files/Git/usr/bin/bash.exe'
}
# Classify on BEHAVIOUR, and WSL FIRST: `uname -s` is the question that cannot lie. A classifier
# keyed on "the file exists and runs" would pin C:\WINDOWS\system32\bash.exe — the exact binary this
# plane exists to step around — and every verdict below would report a green it did not earn.
classify_build() {
  case "$1" in
    Linux)   printf 'WSL\n' ;;
    MINGW*|MSYS*|CYGWIN*) printf 'GITBASH\n' ;;
    *)       printf 'UNKNOWN\n' ;;
  esac
}
probe_build() {
  local x; x="$(to_posix "$1")"
  if [ -x "$x" ] || command -v "$x" >/dev/null 2>&1; then "$x" -c 'uname -s' 2>/dev/null; return 0; fi
  return 1
}
# "<path>\t<uname>"; rc 2 when nothing resolves or every candidate is a WSL launcher. Never guesses,
# never defaults (CONVENTIONS §2).
resolve_build() {
  local c v cls looked=""
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if [ ! -e "$c" ]; then looked="$looked$c (absent), "; continue; fi
    if ! v="$(probe_build "$c")"; then looked="$looked$c (not executable), "; continue; fi
    cls="$(classify_build "$v")"
    case "$cls" in
      GITBASH) printf '%s\t%s\n' "$c" "$v"; return 0 ;;
      WSL)     err "$c is a WSL launcher (uname says Linux) — it runs the repo in a Linux distro with another HOME; not a pin" ;;
      *)       err "$c reported an unclassifiable uname ('$v') — refusing to pin an unknown build" ;;
    esac
  done < <(candidates | awk '!seen[$0]++')
  err "no Git-Bash build resolves here (looked at: ${looked:-nothing})"
  return 2
}

# --- the render, its assertions, the digest ---------------------------------------
render_body() {
  local bin="$1" line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line//@BASH_BIN@/$bin}"
    case "$line" in
      # The PLACEHOLDER SHAPE, not merely an at-sign: a typo'd name must fail the render rather than
      # land in a profile as the literal text `@BASH_BIN@`.
      *'@'[A-Za-z0-9_]*'@'*) err "win/bash-block.ps1: unresolved placeholder in '$line'"; return 1 ;;
    esac
    printf '%s\n' "$line"
  done < "$TMPL"
}
# Run on EVERY render, including the one about to be written — an assertion that only runs in
# --self-test is an assertion a template edit can disable.
assert_body() {
  local f="$1" pin bad=0
  scratch
  # Non-ASCII detected by DELETION, not by a bracket expression (MSYS grep and gawk disagree about \r
  # inside brackets): Windows PowerShell 5.1 reads a BOM-less UTF-8 profile as cp1252 and dies.
  [ -n "$(LC_ALL=C tr -d '\040-\176\t\r\n' < "$f" | head -c1)" ] && {
    err "FAIL: the rendered block carries a non-ASCII byte — 5.1 would read this profile as cp1252"
    bad=1; }
  pin="$(awk -F"'" '/^[[:space:]]*\$env:PI_BASH_BIN[[:space:]]*=/ {print $2; exit}' "$f")"
  case "${pin:-}" in
    "")            err "FAIL: the rendered block never assigns \$env:PI_BASH_BIN — it pins nothing"; bad=1 ;;
    *@BASH_BIN@*)  err "FAIL: \$env:PI_BASH_BIN still carries the placeholder — the build was never substituted"; bad=1 ;;
    *[Ss]ystem32*|*indowsApps*) err "FAIL: the rendered block NAMES a WSL-launcher path as the pinned build ($pin) — that is the binary this plane exists to step around"; bad=1 ;;
  esac
  grep -q 'function global:bash' "$f" || { err "FAIL: the rendered block defines no bash function — it pins nothing"; bad=1; }
  grep -q 'PI_BASH_BIN' "$f"         || { err "FAIL: the rendered block does not set PI_BASH_BIN — a harness launched from this shell would resolve bash off PATH again"; bad=1; }
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
    printf '# seat-bash-build: win11 sha256=%s\n' "$dig"
    cat "$body"
    printf '%s\n' "$MARK_END"; } > "$block"
}
# Spliced in BASH, not with awk/sed, and that is a measured choice: MSYS awk strips the CR of a CRLF
# pair in text mode, so an awk splice SILENTLY rewrites every line ending outside the markers — and a
# real PowerShell profile is CRLF. `read -r` keeps the CR, and the marker is compared without it, so
# CRLF and LF profiles both splice with every foreign byte copied through (CONVENTIONS §6).
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
strip_block()   { splice strip "$1"; }
extract_block() { splice extract "$1"; }
installed_dig() { extract_block "$1" | grep -v '^# seat-bash-build: ' > "$2" && hash_file "$2"; }
# A second mechanism naming `bash` is a shadow: profiles dot-source in order, last-defined wins, and
# a current block can be perfectly inert beside one.
find_shadows() {
  local f="$1"
  [ -f "$f" ] || return 0
  strip_block "$f" | grep -nE '^[[:space:]]*(function|filter)[[:space:]]+(global:)?bash[[:space:]]*[{(]|^[[:space:]]*(Set|New)-Alias[[:space:]]+(-Name[[:space:]]+)?bash([[:space:]]|$)' || true
}

# --- one pass against one profile file (PROF) --------------------------------------
check_profile() {
  local block body out inst fresh_dig got_dig inst_dig shadows rc ts tmp
  rc=0; SHADOWED=0; DUPED=0
  scratch
  block="$SCRATCH/block"; body="$SCRATCH/body"; out="$SCRATCH/outside"; inst="$SCRATCH/installed"
  build_block "$BUILD_PATH" "$block" "$body" || { err "the render failed its own assertions — nothing written"; OUT_RC=2; return 2; }
  fresh_dig="$(sed -n 's/.*sha256=\([0-9a-f]*\).*/\1/p' "$block" | head -1)"

  if [ ! -f "$PROF" ]; then
    printf 'MISSING: %s does not exist — this shell has no profile, so a bare bash here is PATH, and PATH is the WSL launcher\n' "$PROF"
    rc=1
  elif ! grep -qF "$MARK_START" "$PROF"; then
    printf 'MISSING: %s carries no bash-build block — this shell resolves bash off PATH (the WSL launcher)\n' "$PROF"
    rc=1
  else
    strip_block "$PROF" > "$out"
    shadows="$(find_shadows "$PROF")"
    inst_dig="$(installed_dig "$PROF" "$inst")"
    got_dig="$(sed -n 's/^# seat-bash-build: [a-z0-9-]* sha256=\([0-9a-f]*\).*/\1/p' "$PROF" | head -1)"
    if [ -z "$got_dig" ]; then
      printf 'REFUSAL(hand-edit): the block in %s carries no digest line, so this script did not write it\n' "$PROF"
      printf '  → diff it against `--render`, fold what you learn into win/bash-block.ps1, then --force\n'
      rc=3
    elif [ "$inst_dig" != "$got_dig" ]; then
      printf 'REFUSAL(hand-edit): the installed block hashes %s but declares %s — a human edited it in place\n' "$inst_dig" "$got_dig"
      printf '  → NOTHING was written. Reconcile the edit with win/bash-block.ps1, then re-run with --force\n'
      rc=3
    elif [ "$got_dig" != "$fresh_dig" ]; then
      printf 'STALE: the installed block (%s) predates win/bash-block.ps1 (%s) — replacing it is the fix\n' "$got_dig" "$fresh_dig"
      rc=1
    else
      printf 'IN SYNC: %s carries the bash-build block (digest %s)\n' "$PROF" "$fresh_dig"
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
      printf 'REFUSAL(shadow): bash is ALSO defined outside the markers, so two mechanisms remain and the last loaded wins:\n'
      printf '  %s\n' "$shadows"
      printf '  → remove that definition; --force does NOT override a shadow\n'
      rc=3
    fi
  fi

  OUT_RC="$rc"
  [ "$MODE" = "check" ] && return "$rc"
  if [ "$rc" = 0 ]; then echo "already current: $PROF — nothing written"; return 0; fi
  # --force overrides OUR OWN stale/hand-edited text and nothing else: beside a shadow it would write
  # a third copy and still leave the verdict to load order while reporting success.
  if [ "$rc" = 3 ] && { [ "$SHADOWED" = 1 ] || [ "$DUPED" = 1 ] || [ "$FORCE" != 1 ]; }; then
    err "REFUSED: nothing written to $PROF (--force overrides a hand-edit only, never a shadow or a duplicate block)"
    return 3
  fi
  tmp="$SCRATCH/next"
  mkdir -p "$(dirname "$PROF")" 2>/dev/null || true
  if [ -f "$PROF" ]; then
    ts="$(date -u +%Y%m%d-%H%M%S)"
    cp -p "$PROF" "$PROF.bak-$ts" && echo "  backup: $PROF.bak-$ts"
    strip_block "$PROF" > "$tmp"
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

# --- the behavioral proof: what a bare `bash` IS, asked with a NORMAL terminal's PATH ------------
# The PATH is rebuilt from the registry rather than inherited because a child PowerShell launched
# from Git-Bash inherits the MSYS PATH — Git\usr\bin first — and would answer GITBASH whether or not
# the block does anything. That is a probe that cannot fail (CONVENTIONS §6), and it is exactly how
# this seat stayed green in prose while pwsh ran the repo in a Linux distro.
CLEAN_PATH='$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User"); '
# "<uname answer>\t<class>\t<LOADED|BLOCKED|UNKNOWN>"; rc 1 only when the shell did not answer at all.
# BLOCKED is the OTHER way a profile plane dies, and it is real on this seat: script execution is
# disabled for Windows PowerShell 5.1, so it loads NO profile at all. A profile plane must NAME that
# instead of reporting drift forever — a gate that reds on a state no --push can change gets muted.
probe_shell() {
  local exe="$1" out v blocked=0
  out="$("$exe" -NoLogo -Command "${CLEAN_PATH}bash -c 'uname -s'" 2>&1)"
  printf '%s' "$out" | grep -qiE 'running scripts is disabled|cannot be loaded because' && blocked=1
  v="$(printf '%s' "$out" | tr -d '\r' | grep -iE '^(MINGW|MSYS|CYGWIN|Linux)' | head -1)"
  [ -n "$v" ] || [ "$blocked" = 1 ] || return 1
  printf '%s\t%s\t%s\n' "${v:-<no answer>}" "$(classify_build "${v:-}")" "$([ "$blocked" = 1 ] && printf 'BLOCKED' || printf 'LOADED')"
}
# The last verdict. Precedence is the whole point, and it is a pure function so --self-test can drive
# it without a PowerShell in sight: a refusal or a real drift outranks everything; otherwise ONE
# reachable shell whose bare `bash` really is Git-Bash is the proof → 0, and a policy-blocked shell
# is a NOTE beside it; if only a blocked shell answered → 2 SKIP, never a silent pass.
final_rc() {
  local f="$1" ok="$2" bl="$3" fx="$4"
  case "$f" in 3) printf 3; return 0 ;; 1) printf 1; return 0 ;; esac
  [ "$fx" = 1 ] && { printf '%s' "$f"; return 0; }
  [ "$ok" != 0 ] && { printf 0; return 0; }
  [ "$bl" != 0 ] && { printf 2; return 0; }
  printf '%s' "$f"
}
# worst_of <a> <b> — the more severe verdict on this plane's own scale (3 refusal > 1 drift >
# 2 skip > 0 in sync). Pure bash, no sort, no exec (HD-1135: this seat pays an exec per fork).
worst_of() { case "$1$2" in *3*) printf 3 ;; *1*) printf 1 ;; *2*) printf 2 ;; *) printf 0 ;; esac; }

# --- self-test: offline fixtures. No Windows, no PowerShell, no network ------------
selftest() {
  local root fails=0 rc out got PROF STUB
  root="$(mktemp -d "${TMPDIR:-/tmp}/seatbashbuild-selftest.XXXXXX")"
  ok()  { printf '  ok   %s\n' "$1"; }
  no()  { printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
  has() { if grep -q "$2" "$1"; then printf '  ok   %s\n' "$3"; else no "$3 (no '$2' in $(tr '\n' ' ' <"$1" | cut -c1-180))"; fi; }
  PROF="$root/pwsh.ps1"
  STUB="$root/bash-stub"
  # A stub that BEHAVES like Git-Bash: the classifier reads what `uname -s` answers, not a path.
  printf '#!/bin/sh\nif [ "$1" = "-c" ]; then echo MINGW64_NT-10.0-26300; fi\n' > "$STUB"
  chmod +x "$STUB"
  run() {
    local want="$1"; shift
    SEAT_BASH_PROFILES="$PROF" GIT_BUNDLED_BASH="$STUB" bash "$SELF" "$@" >"$root/out" 2>&1
    got=$?
    [ "$got" = "$want" ] || no "expected rc $want, got $got — $(tr '\n' ' ' <"$root/out" | cut -c1-200)"
  }

  # 1+2: the classifier, BOTH directions. Arm 2 is the canary: a classifier keyed on "the file runs"
  # would pass arm 1, pass every live seat, and pin the WSL launcher anyway.
  [ "$(classify_build 'MINGW64_NT-10.0-26300')" = GITBASH ] \
    && ok "1 classifies Git-Bash's uname as GITBASH" || no "1 Git-Bash's uname did not classify as GITBASH"
  [ "$(classify_build 'Linux')" = WSL ] \
    && ok "2 classifies the WSL launcher's uname as WSL (canary: keys on behaviour, not existence)" || no "2 the classifier calls the WSL launcher GITBASH — every verdict below is mute"

  # 3: no profile -> MISSING, then --push creates it and it reads IN SYNC (fixture mode: no live probe).
  rm -f "$PROF"
  run 1 --check; has "$root/out" 'MISSING' "3 reports MISSING when the profile does not exist"
  run 0 --push
  [ -f "$PROF" ] && ok "3a --push created the profile" || no "3a --push created nothing"
  run 0 --check

  # 4: a human's profile bytes survive a replacement byte for byte.
  { printf 'oh-my-posh init pwsh | Invoke-Expression\r\n'; printf 'Import-Module Z\r\n'; } > "$PROF"
  cp "$PROF" "$root/foreign.before"
  run 1 --check
  run 0 --push
  strip_block "$PROF" > "$root/foreign.after"
  cmp -s "$root/foreign.before" "$root/foreign.after" \
    && ok "4 everything outside the markers is copied through unchanged" || no "4 --push changed bytes outside the markers"
  has "$PROF" 'oh-my-posh' "4a the human's own profile line is still there"

  # 5: a hand-edit inside the block -> REFUSAL, with proof the file did not move.
  sed -i 's/^function global:bash {$/function global:bash { Write-Host "hand edit"/' "$PROF"
  local before after; before="$(sha256sum < "$PROF")"      # AFTER the edit: 5a measures the REFUSAL
  run 3 --check; has "$root/out" 'REFUSAL(hand-edit)' "5 a hand-edited block is a REFUSAL"
  run 3 --push
  after="$(sha256sum < "$PROF")"
  [ "$before" = "$after" ] && ok "5a the REFUSAL wrote nothing (file hash unchanged)" || no "5a the REFUSAL modified the file"
  run 0 --push --force
  grep -q 'hand edit' "$PROF" && no "5b --force left the hand-edit in place" || ok "5b --force replaced the hand-edited block"

  # 6: a shadow outside the markers -> REFUSAL that --force does NOT override.
  run 0 --check
  printf '\nfunction bash { & "C:/WINDOWS/system32/bash.exe" @args }\n' >> "$PROF"
  run 3 --check; has "$root/out" 'REFUSAL(shadow)' "6 a second bash definition outside the markers is a REFUSAL"
  run 3 --push --force; has "$root/out" 'REFUSAL' "6a --force does NOT override a shadow"

  # 7: the pinned build must be a Git-Bash — both ways round, and absent is not a default.
  rm -f "$PROF"
  printf '#!/bin/sh\nif [ "$1" = "-c" ]; then echo Linux; fi\n' > "$root/wsl-stub"     # a launcher
  chmod +x "$root/wsl-stub"
  SEAT_BASH_PROFILES="$PROF" GIT_BUNDLED_BASH="$root/wsl-stub" bash "$SELF" --check >"$root/out" 2>&1
  [ "$?" = 2 ] && ok "7 a box whose only bash is a WSL launcher reports SKIP (rc 2), never a pass" || no "7 pinned a WSL launcher (rc $?)"
  SEAT_BASH_PROFILES="$PROF" GIT_BUNDLED_BASH="$root/absent" bash "$SELF" --push >"$root/out" 2>&1
  [ "$?" = 2 ] && ok "7a a build that is not there is a refusal, not a default" || no "7a wrote a block naming a build that does not exist"

  # 8: poisoned templates must fail the RENDER (and the honest one must not).
  rm -f "$PROF"
  sed 's|@BASH_BIN@|C:/WINDOWS/system32/bash.exe|' "$TMPL" | sed 's|^[[:space:]]*#.*||' > "$root/t-sys32"
  SEAT_BASH_PROFILES="$PROF" SEAT_BASH_BLOCK="$root/t-sys32" GIT_BUNDLED_BASH="$STUB" bash "$SELF" --push >"$root/out" 2>&1
  rc=$?; { [ "$rc" != 0 ] && grep -q 'WSL-launcher path' "$root/out"; } \
    && ok "8 a template pinning the WSL launcher fails the render (the rejected fix cannot regrow)" || no "8 a template pinning system32 passed (rc $rc)"
  sed 's|@BASH_BIN@|@BASH_BUIL@|' "$TMPL" > "$root/t-open"          # an UNKNOWN name, not the same one
  SEAT_BASH_PROFILES="$PROF" SEAT_BASH_BLOCK="$root/t-open" GIT_BUNDLED_BASH="$STUB" bash "$SELF" --push >"$root/out" 2>&1
  rc=$?; [ "$rc" != 0 ] && ok "8b an unresolved placeholder fails the render (rc $rc)" || no "8b an unresolved placeholder would have shipped"
  sed 's/function global:bash/function global:zzbash/' "$TMPL" > "$root/t-none"
  SEAT_BASH_PROFILES="$PROF" SEAT_BASH_BLOCK="$root/t-none" GIT_BUNDLED_BASH="$STUB" bash "$SELF" --push >"$root/out" 2>&1
  rc=$?; { [ "$rc" != 0 ] && grep -q 'defines no bash function' "$root/out"; } \
    && ok "8c a template that pins nothing fails the render" || no "8c a template that pins nothing passed (rc $rc)"
  cp "$TMPL" "$root/t-nonascii"; printf '\xc3\xa9\n' >> "$root/t-nonascii"   # valid body + one non-ASCII byte
  SEAT_BASH_PROFILES="$PROF" SEAT_BASH_BLOCK="$root/t-nonascii" GIT_BUNDLED_BASH="$STUB" bash "$SELF" --push >"$root/out" 2>&1
  rc=$?; { [ "$rc" != 0 ] && grep -q 'non-ASCII' "$root/out"; } \
    && ok "8d a non-ASCII body is refused (5.1 would read the profile as cp1252)" || no "8d a non-ASCII body would have shipped (rc $rc)"

  # 9: the verdict precedence, driven as a pure function — including the shape this plane is about:
  #    a current block beside a bare `bash` that still answers Linux is DRIFT (1), not a pass.
  [ "$(final_rc 0 1 0 0)" = 0 ] && ok "9 one reachable shell answering GITBASH is the proof -> 0" || no "9 a proven shell did not yield 0"
  [ "$(final_rc 0 0 1 0)" = 2 ] && ok "9a only a policy-blocked shell answered -> SKIP, never green" || no "9a a blocked-only run was not a SKIP"
  [ "$(final_rc 1 0 0 0)" = 1 ] && ok "9b drift outranks a proven shell (a red is never softened)" || no "9b drift was softened"
  [ "$(final_rc 3 1 0 0)" = 3 ] && ok "9c a refusal outranks everything" || no "9c a refusal did not outrank the probe"

  # 10: the STUBBED live probe — a fake pwsh that answers with a configured uname. Both directions:
  #     a probe whose parser always said GITBASH would pass every arm above and still call WSL green.
  mkdir -p "$root/fakebin"
  printf '#!/bin/sh\na="$*"\ncase "$a" in\n  *CurrentUserAllHosts*) printf "%%s\\n" "$FAKE_PROFILE" ;;\n  *"uname -s"*) printf "%%s\\n" "$FAKE_UNAME" ;;\nesac\n' > "$root/fakebin/pwsh.exe"
  chmod +x "$root/fakebin/pwsh.exe"
  for want in MINGW64_NT-10.0-26300 Linux; do
    want_cls="$(classify_build "$want")"
    got_cls="$(FAKE_UNAME="$want" PATH="$root/fakebin:$PATH" probe_shell pwsh.exe | cut -f2)"
    [ "$got_cls" = "$want_cls" ] && ok "10 the live probe classifies a bare bash answering $want as $want_cls" \
      || no "10 the live probe answered $got_cls for a bare bash answering $want (want $want_cls)"
  done
  FAKE_UNAME="running scripts is disabled on this system" PATH="$root/fakebin:$PATH" probe_shell pwsh.exe \
    | grep -q BLOCKED && ok "10a a profile the policy blocks is BLOCKED (rc-2 territory), not drift" \
    || no "10a a blocked profile was not reported as BLOCKED"

  [ "$fails" = 0 ] && printf '\nself-test: OK — all arms hold\n' || printf '\nself-test: %s arm(s) NOT caught\n' "$fails" >&2
  return "$fails"
}

# ================================ dispatch ======================================
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

if [ "$MODE" = "selftest" ]; then selftest; exit $?; fi

# A given profile list = fixture mode: no discovery, no live PowerShell probe, and no Windows
# boundary — which is what lets --self-test run on a Debian seat and still exercise every arm.
FIXTURE=0
[ -n "${SEAT_BASH_PROFILES:-}" ] && FIXTURE=1

if [ "$MODE" = "render" ]; then
  rline="$(resolve_build)" || exit 2
  scratch; build_block "${rline%%$'\t'*}" "$SCRATCH/block" "$SCRATCH/body" || exit 2
  cat "$SCRATCH/block"; exit 0
fi

# The boundary first: this plane owns only the Windows seat's PowerShell profiles. On the Debian seats
# and on a runner it prints SKIP and exits 2 — never a silent 0 (CONVENTIONS §6).
if [ "$FIXTURE" = 0 ] && ! is_windows; then
  echo "SKIP: not a Windows seat — the bash-build plane owns the win11 seat's PowerShell profiles only"; exit 2
fi

BUILD_LINE="$(resolve_build)" || exit 2
BUILD_PATH="${BUILD_LINE%%$'\t'*}"
echo "pinned build: $BUILD_PATH  [uname: ${BUILD_LINE#*$'\t'}]"

# Collect the profile list: the fixture hook bypasses discovery, exactly as the ssh plane's does.
profiles=()
if [ -n "${SEAT_BASH_PROFILES:-}" ]; then
  IFS=: read -r -a profiles <<<"$SEAT_BASH_PROFILES"
else
  while IFS=$'\t' read -r exe path; do
    case "$exe" in SKIP*) echo "$exe"; continue ;; esac
    [ -n "$path" ] || continue
    profiles+=("$exe"$'\t'"$path")
  done < <(discover_profiles)
fi
[ "${#profiles[@]}" -gt 0 ] || { echo "SKIP: no installed PowerShell answered a profile path — a profile plane proves nothing here"; exit 2; }

worst=0; proven=0; blocked=0; answered=0
for entry in "${profiles[@]}"; do
  PROF="${entry#*$'\t'}"; PEXE="${entry%%$'\t'*}"
  check_profile
  v=$OUT_RC
  # The behavioral half, once per shell, and only where a live shell was asked (a fixture pins its own).
  # In --push it runs AFTER the write: the proof is what a bare `bash` IS once the block landed, not
  # what the file now contains ("report what LANDED, not what was meant").
  if [ "$FIXTURE" = 0 ]; then
    if pr="$(probe_shell "$PEXE")"; then
      printf '  probe: %s — a bare `bash` answers uname with %s (%s, profile %s)\n' "$PEXE" "$(printf '%s' "$pr" | cut -f1)" "$(printf '%s' "$pr" | cut -f2)" "$(printf '%s' "$pr" | cut -f3)"
      answered=$((answered+1))
      pcls="$(printf '%s' "$pr" | cut -f2)"
      case "$(printf '%s' "$pr" | cut -f2,3)" in
        GITBASH*) proven=$((proven+1)) ;;
        *BLOCKED) blocked=$((blocked+1)) ;;
        # A bare bash that is still the launcher while the block is in the file = a shadow or a second
        # mechanism. Where the file verdict is already MISSING/STALE the probe adds no NEW finding, and
        # the probe line above says so — claiming "the block is in place" over a missing block would be
        # a false line in the operator's own diagnosis.
        *) if [ "$v" = 0 ]; then printf '  DRIFT: the block is in place but a bare `bash` here is still %s — a shadow or a second mechanism\n' "$pcls"; v=1; fi ;;
      esac
    else
      printf '  probe: %s did not answer — reported, not assumed\n' "$PEXE"
    fi
  fi
  worst="$(worst_of "$worst" "$v")"
done

if [ "$MODE" = prove ]; then
  [ "$proven" != 0 ] && { echo "OK: a profile-loaded shell's bare bash IS Git-Bash"; exit 0; }
  [ "$blocked" != 0 ] && { echo "SKIP: the only shell that answered loads no profile (script execution disabled)"; exit 2; }
  echo "FAIL: no installed shell answered a bare bash that is Git-Bash"; exit 1
fi

# No shell answered at all: the file contract alone proves nothing, so this is a boundary and not a
# green — a block sitting in a profile no shell loads is exactly the false green to avoid.
if [ "$FIXTURE" = 0 ] && [ "$answered" = 0 ] && [ "$worst" != 1 ] && [ "$worst" != 3 ]; then
  echo "SKIP: no installed PowerShell answered the behavioral probe — the block's presence alone proves nothing"; exit 2
fi

rc_final="$(final_rc "$worst" "$proven" "$blocked" "$FIXTURE")"
case "$rc_final" in
  0) echo "IN SYNC: every discovered profile carries the block, and a bare bash is Git-Bash" ;;
  1) echo "DRIFT: a profile is missing or stale, or a bare bash is still the WSL launcher — run: bash scripts/harness/seat-bash-build.sh --push" ;;
  2) echo "SKIP: nothing was proved here (boundary above) — a SKIP is not a pass" ;;
  3) echo "REFUSAL: a hand-edit, a duplicate block, or a shadow outside the markers — reconcile it, then --push (--force for a hand-edit only)" ;;
esac
exit "$rc_final"
