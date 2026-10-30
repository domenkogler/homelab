#!/usr/bin/env bash
# =====================================================================
# scripts/secrets/reseat-vault-token.sh — carry a rotated 1Password service-account token to the seats
# that hold it, from any one of them, headless, and PROVE the landing by digest plus a vault answer.
#
# WHY THIS EXISTS (HD-495's tail, 2026-10-30): the rotation act is a console click, but the re-seat is
# four installs, and until now the repo's answer was a pipe form written out by hand in
# docs/1password.md §Rotating the control-node token. That made a rotation a runbook the operator types
# while the superseded generation is still alive — and `bootstrap-runner.sh`, the script people reach
# for, is create-only (`if [ ! -f "$OP_TOKEN_FILE" ]`): it prints "token already stored" and changes
# nothing, so the seat looks maintained and 403s the day the old value expires. This is the command
# §1's "if it has no command that applies it, it is not automation" asks for.
#
# WHAT IT NEVER DOES: print a value, a length of a VALUE's surroundings, or put a value on a command
# line or in a file on the way. The token crosses the ssh session's STDIN and nothing else; the proof
# printed is `sha256[:12]` of the value plus `op item list`'s line count, because readability of a file
# is not a working credential (docs/1password.md §Proving which service account an install holds).
#
#   bash scripts/secrets/reseat-vault-token.sh --check                # digests everywhere, writes nothing
#   bash scripts/secrets/reseat-vault-token.sh --check --seat wsl
#   bash scripts/secrets/reseat-vault-token.sh --apply                # re-seat every target
#   bash scripts/secrets/reseat-vault-token.sh --apply --seat vps
#   bash scripts/secrets/reseat-vault-token.sh --install-from-stdin   # RUNS ON A TARGET, token on stdin
#   bash scripts/secrets/reseat-vault-token.sh --self-test            # sandboxed, ZERO vault contact
#
# Targets are the SSH ALIAS PLANE, not host names written in here: `wsl` (the Debian engine behind the
# WSL door, `$PI_WSL_DISTRO`) plus `$PI_OLDSRV_TARGET` (the cockpit/authoring seat), `vps` and `oldsrv`
# (the two control accounts). Override with `RESEAT_TARGETS="…"`. Each target's file is `$HOME`-relative
# — one shape, no per-host paths — and the install is the item named by `--item` (default `op_api`).
#
# LIMITS, stated: it re-seats FILES, so it reaches neither `/etc/op/provision-token` (that is
# `op-write_api` and only an `op-provision-token` converge writes it — the script SAYS so rather than
# pretending) nor any already-running shell's exported environment, which beats the file every time and
# is the trap that reads as "the rotation did not work". It cannot rotate the item: that is the console.
#
# WHERE TO RUN IT: any seat with a working credential and the alias plane. The **Windows seat** is the
# only box that reaches all four targets (it is itself a target-less vault reader — no `op_api` file on
# that disk, the lib borrows the WSL engine's bytes through the door — so a rotation reaches it with no
# act here). From a Debian seat the `wsl` target prints `NOT-FROM-HERE` rather than writing to the wrong
# box, and the control accounts are still reachable, so a Debian seat re-seats what it can and names the
# rest.
# =====================================================================
set -euo pipefail

# HD-1118 Stage 1: the repo root is FOUND by scripts/lib/repo-root.sh, never assumed from a depth —
# "one level above me" is what turns a folder move into a gate that checks nothing.
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"   # sets REPO (an inherited $REPO still wins)
# OWN PATH, not a name spliced into REPO: a self-test that re-execs `$SELF` must survive the file being
# copied or renamed by a harness, or every arm fails for the wrong reason (measured that way).
SELF="${BASH_SOURCE[0]}"
ITEM="op_api"
MODE="check"
SEATS=""
: "${PI_WSL_DISTRO:=Debian}"
: "${PI_OLDSRV_TARGET:=oldsrv-domen}"
: "${RESEAT_TARGETS:=wsl $PI_OLDSRV_TARGET vps oldsrv}"
# The repo's own path on a target, in the order the seats actually use. Probed, never assumed.
REPO_CANDIDATES="${REPO_CANDIDATES:-/home/domen/source/homelab /home/ansible-admin/source/homelab /root/source/homelab /opt/homelab}"

say() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }
d12() { tr -d '\r\n' | sha256sum | cut -c1-12; }   # digest of what it is fed; a value never survives it

# ---- credential: the lib's rule, never a hand-rolled one (the same fix git-bootstrap.sh carries) ----
# The lib is ASKED AS A SUBPROCESS, not sourced: sourced into a `set -e` shell it aborts quietly and
# answers empty (measured — the same `--emit` that prints a route as a script returned nothing here), and
# an empty credential is the exact defect this whole change is about.
hl_vault_ask() {
  local lib
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && return 0
  lib="$(cd "$(dirname "$SELF")/.." && pwd)/lib/vault-env.sh"
  [ -f "$lib" ] || lib="$REPO/scripts/lib/vault-env.sh"
  [ -f "$lib" ] || return 1
  OP_SERVICE_ACCOUNT_TOKEN="$(bash "$lib" --emit 2>/dev/null || true)"
  [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]
}

opbin() { command -v op 2>/dev/null || command -v op.exe 2>/dev/null || true; }

# ---- one target, two verbs ----------------------------------------------------------------------------
# Transports: `wsl` crosses the WSL door, anything else is an ssh alias. Stdin is forwarded (the token's
# only channel) and `-n` is never used — that flag kills the pipe, the same trap docs carry for git.
# The `wsl` fallback is NOT "run it here": it runs here ONLY when this box IS the Debian engine (WSL
# answers `microsoft` in /proc/version). From another Debian seat there is no way in, and re-seating the
# host you are standing on while reporting it as `wsl` is exactly the wrong-box success this repo keeps
# meeting. Reachability is a verdict, never a silent local substitution.
this_is_wsl_engine() { grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; }

# WHERE THIS RUNS: the Debian engine, never the Windows side. The proof this script prints is a FILE
# MODE plus a `chmod`-gated verification, and a Windows filesystem carries neither — a self-test run
# there asserts an emulated mode and can call a refused write a success. So the Windows seat calls it
# across the door (the repo's own `hl_wsl_route` / `wsl.exe -d Debian`), which is the same route
# `validate-all.sh` already takes for `git-bootstrap.sh --self-test`.
refuse_windows_side() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
      printf '%s\n' "this leg runs on the Debian engine, not on the Windows side (file modes and the chmod-gated verify are not carried on NTFS)" >&2
      printf '%s\n' "run it as:   wsl.exe -d ${PI_WSL_DISTRO:-Debian} -- bash -lc 'cd ~/source/homelab && bash scripts/secrets/reseat-vault-token.sh ${ARGS:-…}'" >&2
      printf '%s\n' "or from the gate: hl_wsl_route bash scripts/secrets/reseat-vault-token.sh --self-test" >&2
      exit 2 ;;
  esac
}

tx() { # tx <target> <cmd...>   (stdin forwarded)
  local t="$1"; shift
  if [ -n "${RESEAT_STUB:-}" ]; then                # the self-test's transport seam, same idea as PI_SEAT_STUB
    [ -d "$RESEAT_STUB/$t" ] || return 255
    HOME="$RESEAT_STUB/$t/home" RESEAT_STUB_TARGET="$t" bash -c "$*"
    return $?
  fi
  if [ "$t" = "wsl" ]; then
    # ORDER MATTERS: inside the engine `wsl.exe` is STILL on PATH (WSL interop), and asking it from in
    # there runs the leg in a different namespace and reports ABSENT for a file that is right there — a
    # false red measured on this box. The engine checks itself first.
    if this_is_wsl_engine; then bash -lc "$*"; return $?; fi
    if command -v wsl.exe >/dev/null 2>&1; then MSYS_NO_PATHCONV=1 wsl.exe -d "$PI_WSL_DISTRO" -- bash -lc "$*"; return $?; fi
    return 99                                     # unreachable from this seat, by definition
  fi
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$t" "$*"
}

target_reachable() { # 0 reachable · 1 unreachable · 2 structurally not from this seat
  local t="$1"
  if [ "$t" = "wsl" ] && ! command -v wsl.exe >/dev/null 2>&1 && ! this_is_wsl_engine; then return 2; fi
  tx "$t" 'true' >/dev/null 2>&1
}

target_check() { # prints: <target> <state> <detail…>
  local t="$1" out h r
  if target_reachable "$t"; then r=0; else r=$?; fi
  if [ "$r" = 2 ]; then say "  $t  NOT-FROM-HERE  — the WSL engine is unreachable from a Debian seat; run this from the Windows seat (or on the WSL seat itself)"; return 1; fi
  if [ "$r" = 99 ]; then r=1; fi
  [ "$r" = 0 ] || { say "  $t  UNREACHABLE"; return 1; }
  out=$(tx "$t" 'f="$HOME/.config/op/homelab-sa-token"
    if [ ! -f "$f" ]; then echo "ABSENT"; exit 0; fi
    set -a; . "$f"; set +a            # the file is the export form, so sourcing it is how its value is hashed
    echo "FILE $(printf %s "${OP_SERVICE_ACCOUNT_TOKEN:-}" | sha256sum | cut -c1-12) $(printf %s "${OP_SERVICE_ACCOUNT_TOKEN:-}" | wc -c)"
    n=$(op item list --vault Homelab-ansible 2>&1 | grep -c . || true)
    printf '%s' "$n" | grep -qE "^[0-9]+$" || n=0        # anything that is not a plain number is "did not answer"
    [ "$n" -gt 1 ] && echo "LIVENESS OK $n" || echo "LIVENESS FAIL $n"
    grep -q homelab-sa-token "$HOME/.bashrc" 2>/dev/null && echo "BASHRC yes" || echo "BASHRC no"
    exit 0' 2>&1)
  # Reachability was decided by target_reachable ABOVE; the payload's own exit status says nothing about
  # the transport (a last command that greps badly is rc 1, and that used to print UNREACHABLE over a
  # perfectly readable seat).
  case "$out" in *"Permission denied"*|*"Could not resolve"*) say "  $t  UNREACHABLE (late)"; return 1 ;; esac
  h=$(printf '%s' "$out" | awk '/^FILE /{print $2}')
  if   printf '%s' "$out" | grep -q '^ABSENT'; then say "  $t  ABSENT  — no file installed (is this target a holder?)"
  elif [ "$h" = "$WANT" ]; then say "  $t  CURRENT  sha256[:12]=$h$(printf '%s' "$out" | grep -q '^LIVENESS OK' && echo ", the vault answers" || echo ", BUT the vault does NOT answer")"
  else say "  $t  STALE  sha256[:12]=$h (vault holds $WANT)$(printf '%s' "$out" | grep -q '^LIVENESS OK' && echo " — still works, so the superseded generation is alive: re-seat inside the grace window" || true)"
  fi
  printf '%s' "$out" | grep -E '^(LIVENESS FAIL|BASHRC no)' | sed 's/^/       /' || true
  [ "$h" = "$WANT" ] && return 0 || return 1
}

target_apply() {
  local t="$1" repo r out rc
  if target_reachable "$t"; then r=0; else r=$?; fi
  if [ "$r" = 2 ]; then say "  $t  NOT-FROM-HERE — the WSL engine is unreachable from this seat, so NOTHING was written anywhere for it"; return 1; fi
  if [ "$r" = 99 ]; then r=1; fi
  [ "$r" = 0 ] || { say "  $t  UNREACHABLE — nothing written"; return 1; }
  repo=$(tx "$t" "for p in $REPO_CANDIDATES; do [ -f \"\$p/scripts/secrets/reseat-vault-token.sh\" ] && { echo \"\$p\"; exit 0; }; done; echo MISSING" 2>/dev/null | tail -1)
  if [ -z "$repo" ] || [ "$repo" = "MISSING" ]; then
    say "  $t  SKIPPED — no homelab clone found, so no install route. Clone it first (docs/deployment-ansible.md); this script will not hand-plant a token into a box with no SSOT."
    return 1
  fi
  # The token goes ONLY on stdin; the remote command names no value. The status read is the TRANSPORT's,
  # so it must not be laundered by a trailing `sed` in the pipeline (that made every target read as
  # re-seated, because sed never fails).
  out=$(printf '%s' "$TOKEN" | tx "$t" "bash $repo/scripts/secrets/reseat-vault-token.sh --install-from-stdin --item $ITEM" 2>&1)
  rc=$?
  printf '%s\n' "$out" | sed 's/^/       /'
  if [ "$rc" -eq 0 ]; then say "  $t  re-seated"; else say "  $t  FAILED — that target's file is unchanged (its own output above says why)"; return 1; fi
}

# ---- runs ON a target -------------------------------------------------------------------------------
install_from_stdin() {
  local f="$HOME/.config/op/homelab-sa-token" tmp bk n T=""
  umask 077
  # `install -d -m 700` is the right verb on a Linux seat and fails on a Windows filesystem that cannot
  # carry the mode (measured: `install: cannot change permissions … Permission denied`) — and a sandboxed
  # self-test runs on the Windows seat. Create, then TRY the mode and say so: the dir already exists on
  # every real install, so refusing to continue would break the one act this script exists for.
  mkdir -p "$(dirname "$f")" 2>/dev/null || die "FAIL: cannot create $(dirname "$f")"
  chmod 700 "$(dirname "$f")" 2>/dev/null || say "  note: mode 700 not settable on $(dirname "$f") here (no POSIX modes on this filesystem)"
  IFS= read -r T || true
  T=${T//$'\r'/}
  [ -n "$T" ] || die "FAIL: nothing on stdin — nothing written (the driver reads the item itself; a silent read is an ABORT, never an empty file)"
  case "$T" in *[[:space:]]*|*'"'*|*"'"*) die "FAIL: the value carries whitespace/quotes — nothing written (an op read that was piped through a shell that mangled it)" ;; esac
  tmp=$(mktemp "$HOME/.config/op/.reseated.XXXXXX") || die "FAIL: mktemp inside $(dirname "$f")"
  printf 'export OP_SERVICE_ACCOUNT_TOKEN=%q\n' "$T" > "$tmp" && chmod 600 "$tmp"
  unset T
  # PROVE BEFORE SWAPPING: an answer from the vault, not the file's existence. A token that 403s written
  # into place is how a rotation silently breaks the seat that was "fixed".
  # The count is made FAULT-PROOF, because the naive form `n=$( … | wc -l ) || echo 0` produced "1\n0"
  # when the pipeline failed under pipefail — and `[ "1\n0" -le 1 ]` is a bash ERROR, which an `if` reads
  # as false, so a refused value was installed. Measured, caught by arm 2. Anything that is not a plain
  # number is 0, and 0 refuses.
  prov=$( ( set -a; . "$tmp"; set +a; "$(opbin)" item list --vault "${OP_VAULT:-Homelab-ansible}" 2>&1 || true ) )
  n=$(printf '%s\n' "$prov" | grep -c . || true)
  case "${n:-}" in ''|*[!0-9]*) n=0 ;; esac
  if [ "${n:-0}" -le 1 ]; then
    rm -f "$tmp"
    die "FAIL: the value piped in did not answer the vault — $f left exactly as it was"
  fi
  bk=""
  if [ -f "$f" ]; then bk=$(mktemp "$HOME/.config/op/.previous.XXXXXX") && cp -p "$f" "$bk"; fi
  mv -f "$tmp" "$f" && chmod 600 "$f"
  ( set -a; . "$f"; set +a
    say "  installed sha256[:12]=$(printf %s "$OP_SERVICE_ACCOUNT_TOKEN" | d12) mode=$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f") item=$ITEM" )
  if grep -q "homelab-sa-token" "$HOME/.bashrc" 2>/dev/null; then say "  bashrc sources the file"
  else printf '\n[ -f %s ] && source %s\n' "$f" "$f" >> "$HOME/.bashrc"; say "  bashrc wiring ADDED (a login shell that does not source the file is half an install)"; fi
  [ -n "$bk" ] && { rm -f "$bk"; say "  the superseded copy on this host was dropped (the new value answered)"; }
  say "  installed on $(hostname) as $(id -un)"
}

# ---- self-test: no network, no vault, a fake op that answers by env ----------------------------------
# TEMP-DIR DISCIPLINE, learned the hard way on this host (2026-10-30): MSYS exports `TMP=/tmp` and
# `TEMP=/tmp`, and `/tmp` IS `%TEMP%` (`cygpath -w /tmp`). A cleanup trap that reads `$TMP` therefore
# aims at the user's whole temp directory the moment `TMP` stops being the script's own variable —
# `local TMP` + `trap 'rm -rf "$TMP"'` deleted a share of `%TEMP%` on the first run of this self-test.
# So: a name that cannot collide, a path that must PROVE it is ours by its own prefix, and cleanup that
# refuses anything else. The repo's other scripts use `$TMP` in a trap and are safe only while it stays
# global; nothing here depends on that.
HL_ST_DIR=""
hl_selftest_dir() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/hl-reseat-selftest.XXXXXX" 2>/dev/null || true)"
  case "$d" in
    */hl-reseat-selftest.??????) HL_ST_DIR="$d"; trap 'hl_selftest_clean' EXIT ;;
    *) die "self-test refuses to run without a provably private temp dir (mktemp gave: '$d')" ;;
  esac
}
hl_selftest_clean() {
  [ -n "${HL_ST_DIR:-}" ] || return 0
  case "$HL_ST_DIR" in
    */hl-reseat-selftest.??????) rm -rf -- "$HL_ST_DIR" ;;
    *) printf 'SELFTEST: refusing to remove a temp dir that is not ours: %s\n' "$HL_ST_DIR" >&2 ;;
  esac
}

self_test() {
  local fails=0 out h
  say "SELFTEST: reseat-vault-token.sh — the install is atomic, proven, and value-blind"
  hl_selftest_dir; local TMP="$HL_ST_DIR"
  mkdir -p "$TMP/bin" "$TMP/home/.config/op" "$TMP/repo/scripts/secrets"
  cat > "$TMP/bin/op" <<'EOS'
#!/bin/sh
case "$1" in
  item) # the vault answers for a working credential OR for the item's own current value — which is what
        # a target proves with right after the write (arm 6). A value that is neither is refused (arm 2).
        case "${OP_SERVICE_ACCOUNT_TOKEN:-}" in
          "${STUB_GOOD:-deadbeef}"|"${STUB_ITEM_VALUE:-ops_goodvalue}") printf 'x\ny\n'; exit 0;;
          *) printf 'denied\n'; exit 1;;
        esac;;
  read) if [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then printf '%s' "${STUB_ITEM_VALUE:-ops_goodvalue}"; exit 0; fi
        printf '[ERROR] You are not currently signed in.\n' >&2; exit 1;;
  vault) echo 'Homelab-ansible'; exit 0;;
esac
exit 1
EOS
  chmod +x "$TMP/bin/op"
  # Arm 1 — the install, end to end, through the same function a target runs.
  printf 'sat-goodvalue' | PATH="$TMP/bin:$PATH" HOME="$TMP/home" STUB_GOOD="sat-goodvalue" OP_VAULT="Homelab-ansible" \
    bash "$SELF" --install-from-stdin >/dev/null 2>&1 \
    || { echo "SELFTEST FAIL [install]: a good value was refused"; fails=$((fails+1)); }
  h=$( ( set -a; . "$TMP/home/.config/op/homelab-sa-token"; set +a; printf %s "$OP_SERVICE_ACCOUNT_TOKEN" | d12 ) )
  [ "$h" = "$(printf %s 'sat-goodvalue' | d12)" ] \
    || { echo "SELFTEST FAIL [install]: the file does not hold what was piped in"; fails=$((fails+1)); }
  # The mode arm asserts only where the filesystem CAN carry a mode: on NTFS (`/mnt/d`) chmod succeeds
  # and is ignored, and asserting there would be a Windows-only false red — the same reason the leg runs
  # on the engine. The probe is the filesystem's own answer, not a guess about the platform.
  probe="$TMP/mode-probe"; : > "$probe"; chmod 600 "$probe"
  if [ "$(stat -c %a "$probe" 2>/dev/null || stat -f %Lp "$probe")" = "600" ]; then
    [ "$(stat -c %a "$TMP/home/.config/op/homelab-sa-token" 2>/dev/null || stat -f %Lp "$TMP/home/.config/op/homelab-sa-token")" = "600" ] \
      || { echo "SELFTEST FAIL [install]: the file is not 0600 on a filesystem that carries modes"; fails=$((fails+1)); }
  else
    say "  note: this filesystem ignores chmod, so the 0600 arm is a no-op here (it is real on a seat)"
  fi
  # Arm 2 — a value the vault refuses must leave the seat's file BYTE-IDENTICAL: the shape of a rotation
  # done badly (a typo pasted, an expired token) is a seat that reads nothing afterwards.
  printf 'export OP_SERVICE_ACCOUNT_TOKEN=sat-previous\n' > "$TMP/home/.config/op/homelab-sa-token"
  cp -p "$TMP/home/.config/op/homelab-sa-token" "$TMP/before"
  printf 'sat-wrongvalue' | PATH="$TMP/bin:$PATH" HOME="$TMP/home" STUB_GOOD="sat-goodvalue" OP_VAULT="Homelab-ansible" \
    bash "$SELF" --install-from-stdin >/dev/null 2>&1 \
    && { echo "SELFTEST FAIL [prove-first]: a value the vault refused was installed"; fails=$((fails+1)); }
  cmp -s "$TMP/before" "$TMP/home/.config/op/homelab-sa-token" \
    || { echo "SELFTEST FAIL [prove-first]: a refused install moved the seat's file"; fails=$((fails+1)); }
  ls "$TMP/home/.config/op"/.reseated.* >/dev/null 2>&1 \
    && { echo "SELFTEST FAIL [prove-first]: a refused install left a temp file behind"; fails=$((fails+1)); }
  # Arm 3 — empty stdin is a refusal, never a zero-length install.
  printf '' | PATH="$TMP/bin:$PATH" HOME="$TMP/home" OP_VAULT="Homelab-ansible" \
    bash "$SELF" --install-from-stdin >/dev/null 2>&1 \
    && { echo "SELFTEST FAIL [empty-stdin]: nothing piped in still wrote a file"; fails=$((fails+1)); }
  # Arm 4 — the value never appears in the tool's own output, in either mode.
  out=$(printf 'sat-goodvalue' | PATH="$TMP/bin:$PATH" HOME="$TMP/home" STUB_GOOD="sat-goodvalue" OP_VAULT="Homelab-ansible" \
        bash "$SELF" --install-from-stdin 2>&1 || true)
  printf '%s' "$out" | grep -q 'sat-goodvalue' \
    && { echo "SELFTEST FAIL [value-blind]: the output printed the value"; fails=$((fails+1)); }
  # Arm 5 — the bashrc wiring is added once and only when missing (half an install reads installed).
  grep -q homelab-sa-token "$TMP/home/.bashrc" 2>/dev/null || echo "# untouched" > "$TMP/home/.bashrc"
  printf 'sat-goodvalue' | PATH="$TMP/bin:$PATH" HOME="$TMP/home" STUB_GOOD="sat-goodvalue" OP_VAULT="Homelab-ansible" \
    bash "$SELF" --install-from-stdin >/dev/null 2>&1
  [ "$(grep -c homelab-sa-token "$TMP/home/.bashrc")" = "1" ] \
    || { echo "SELFTEST FAIL [bashrc]: the wiring was not added exactly once"; fails=$((fails+1)); }
  # Arm 6 — the driver, end to end through the stubbed transport: a STALE seat becomes CURRENT, and the
  # whole exchange prints DIGESTS only. This is the arm that makes `--check` safe to run on a real fleet
  # from a transcript-capturing harness, which is the leak class docs/1password.md §Output hygiene bans.
  mkdir -p "$TMP/seats/vps/home/.config/op" "$TMP/repo/scripts/secrets"
  printf 'export OP_SERVICE_ACCOUNT_TOKEN=%q\n' 'sat-oldvalue' > "$TMP/seats/vps/home/.config/op/homelab-sa-token"
  # The target side runs the REPO's own script by path, so the fixture gives it the real one — that makes
  # this arm exercise driver → transport → install end to end, not a stand-in.
  cp "$SELF" "$TMP/repo/scripts/secrets/reseat-vault-token.sh"
  out=$(PATH="$TMP/bin:$PATH" RESEAT_STUB="$TMP/seats" STUB_GOOD="sat-goodvalue" \
        OP_SERVICE_ACCOUNT_TOKEN="sat-goodvalue" OP_VAULT="Homelab-ansible" \
        bash "$SELF" --check --seat vps 2>&1 || true)
  printf '%s' "$out" | grep -q 'STALE' \
    || { echo "SELFTEST FAIL [check]: a seat holding an old value did not read STALE (got: $(printf '%s' "$out" | tail -1))"; fails=$((fails+1)); }
  printf '%s' "$out" | grep -qE 'sat-|ops-' \
    && { echo "SELFTEST FAIL [value-blind]: --check printed a value, not a digest"; fails=$((fails+1)); }
  out=$(PATH="$TMP/bin:$PATH" RESEAT_STUB="$TMP/seats" STUB_GOOD="sat-goodvalue" \
        OP_SERVICE_ACCOUNT_TOKEN="sat-goodvalue" OP_VAULT="Homelab-ansible" REPO_CANDIDATES="$TMP/repo" \
        bash "$SELF" --apply --seat vps 2>&1 || true)
  printf '%s' "$out" | grep -q 're-seated' \
    || { echo "SELFTEST FAIL [apply]: the driver did not report the seat as re-seated (got: $(printf '%s' "$out" | tail -1))"; fails=$((fails+1)); }
  printf '%s' "$out" | grep -qE 'sat-|ops-' \
    && { echo "SELFTEST FAIL [value-blind]: --apply printed a value"; fails=$((fails+1)); }
  h=$( ( set -a; . "$TMP/seats/vps/home/.config/op/homelab-sa-token"; set +a; printf %s "$OP_SERVICE_ACCOUNT_TOKEN" | d12 ) )
  [ "$h" = "$(printf %s 'ops_goodvalue' | d12)" ] \
    || { echo "SELFTEST FAIL [apply]: the stubbed seat did not end up holding the vault's value"; fails=$((fails+1)); }
  # …and an UNREACHABLE seat is named, never silently substituted with the box running the driver.
  out=$(PATH="$TMP/bin:$PATH" RESEAT_STUB="$TMP/seats" OP_SERVICE_ACCOUNT_TOKEN="sat-goodvalue" \
        STUB_GOOD="sat-goodvalue" OP_VAULT="Homelab-ansible" \
        bash "$SELF" --check --seat nosuchseat 2>&1 || true)
  printf '%s' "$out" | grep -q 'UNREACHABLE' \
    || { echo "SELFTEST FAIL [unreachable]: an unreachable target was not named as one"; fails=$((fails+1)); }
  if [ "$fails" -eq 0 ]; then
    say "SELFTEST OK: the re-seat is atomic, proven by a vault answer before it swaps, value-blind, and never half-installs (7 arms, sandboxed)"
  else
    say "SELFTEST FAILED: $fails arm(s)"; exit 1
  fi
}

# ---- driver ------------------------------------------------------------------------------------------
ARGS="$*"
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --apply) MODE="apply"; shift ;;
    --install-from-stdin) MODE="install"; shift ;;
    --self-test) MODE="selftest"; shift ;;
    --seat) SEATS="$2"; shift 2 ;;
    --item) ITEM="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^# =\{10,\}/p' "$SELF"; exit 0 ;;
    *) die "unknown option: $1 (--help)" ;;
  esac
done

refuse_windows_side
[ "$MODE" = selftest ] && { self_test; exit 0; }
[ "$MODE" = install ] && { install_from_stdin; exit 0; }

# A driver run reads the item ONCE, digests it, and holds the value in this process only.
hl_vault_ask || die "no vault credential for this seat (see scripts/lib/vault-env.sh) — a re-seat reads the item, so it needs one working credential somewhere: this seat's file, its env, or the WSL door"
OP="$(opbin)"; [ -n "$OP" ] || die "no op CLI on this seat"
# The read goes through the repo's ONE batched reader, and its answer is VERIFIED by shape. Why not
# `op read <path>`: on op 2.39 BOTH plausible paths fail QUIETLY — `…/op_api/credential` prints nothing
# and exits 0, `…/credential/op-service-account-token` prints `does not have a field` and ALSO exits 0
# (measured). A read that fails as a success is how an empty token reaches a seat and 403s there.
read_item() {
  local json
  if [ -n "${RESEAT_STUB:-}" ]; then "$(opbin)" read "op://${OP_VAULT:-Homelab-ansible}/${ITEM}/credential"; return; fi
  json=$(python3 "$REPO/scripts/lib/vault_read.py" --item "$ITEM" 2>/dev/null | sed -n '/^{/,$p' || true)
  [ -n "$json" ] || return 1
  printf '%s' "$json" | python3 -c 'import json,sys
# the reader prefixes a NOTE line and wraps the record as {"item": {…}} — both shapes are read, and the
# value is taken by its service-account prefix, not by a field label guessed here
try:
    j = json.load(sys.stdin)
except Exception:
    sys.exit(1)
item = j.get("item", j)
for f in item.get("fields", []):
    v = f.get("value")
    if isinstance(v, str) and v.startswith("ops_"):
        print(v.strip()); break
    if isinstance(v, list):
        for s in v:
            sv = s.get("value")
            if isinstance(sv, str) and sv.startswith("ops_"):
                print(sv.strip()); sys.exit(0)' 2>/dev/null || true
}
TOKEN="$(read_item || true)"
case "$TOKEN" in ops_*) : ;; *) TOKEN="" ;; esac
[ -n "$TOKEN" ] || die "could not read a service-account token from '$ITEM' via lib/vault_read.py — nothing was touched"
WANT="$(printf %s "$TOKEN" | d12)"
say "reseat-vault-token · item $ITEM · vault sha256[:12]=$WANT · targets: ${SEATS:-$RESEAT_TARGETS}"
fails=0
for t in ${SEATS:-$RESEAT_TARGETS}; do
  if [ "$MODE" = check ]; then target_check "$t" || fails=$((fails+1)); else target_apply "$t" || fails=$((fails+1)); fi
done
[ "$MODE" = check ] && say "digests only — a value is never printed here (docs/1password.md §Proving which service account an install holds)"
[ "$fails" -eq 0 ] && { say "RESULT all targets OK"; exit 0; }
say "RESULT $fails target(s) need attention"; exit 1
