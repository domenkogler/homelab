#!/usr/bin/env bash
# =====================================================================
# pi-seat-sync.sh — ONE command, every pi.dev seat, every harness plane (HD-1110).
#
# WHY THIS EXISTS
# ---------------
# A seat's harness is eight planes (the pi build itself, skills, extensions, settings, the model contract, the TUI
# package + its footer key, tmux, the TUI font), each owned by its own script, on three
# machines (Win11, WSL Debian, the oldsrv cockpit). Before 2026-10-08 the planes were run one
# at a time, per seat, by a session remembering which ones it had done — and the gaps that
# produced are on the record: HD-446 ("this was the seat the extension SSOT never reached"),
# HD-493 (the seat trailing the laptop on packages), HD-1085 ("install-pi-debian.sh does not
# call the installer yet"). Owner ruling 2026-10-08: the sync is a script, and it runs on all
# the seats. This file fans out and reports; it owns NO value — every plane keeps its owner.
#
# RUNS ON BOTH PLATFORMS, AND SAYS WHICH SEATS ARE WHICH
# -----------------------------------------------------
# bash either way (Git-Bash on Win11, bash on Debian). What differs is which TRANSPORTS exist
# here: `wsl.exe` exists only on the Windows side, and the `win11` seat is the Windows
# filesystem — so a Debian host reports that seat NOT-HERE instead of pretending, and running
# inside WSL makes this shell the `wsl` seat directly (no nested wsl.exe). Every seat gets a
# verdict, and an UNREACHABLE seat FAILS the run: a sync that "succeeded" because it never got
# to the seat is the exact failure this file exists to kill.
#
# THE PRE-FLIGHT IS THE POINT
# ---------------------------
# Every plane script deploys from ITS OWN clone (`pi-agent/`, `skills/`, the pins), so a seat
# whose clone sits on an old commit would happily deploy an OLD SSOT and report success. Each
# seat's `git rev-parse HEAD` is therefore compared with this checkout's, and a mismatch is
# STALE-CLONE: the seat's planes are NOT run, and the ff-only remediation is printed.
#
# USAGE (from a homelab clone, on any seat)
#   bash scripts/harness/pi-seat-sync.sh                    # report (drift report-only per plane)
#   bash scripts/harness/pi-seat-sync.sh --push             # converge every seat
#   bash scripts/harness/pi-seat-sync.sh --seat wsl --check # one seat
#   bash scripts/harness/pi-seat-sync.sh --plane settings   # one plane, every seat
#   bash scripts/harness/pi-seat-sync.sh --list             # the seat/transport matrix, run nothing
#   bash scripts/harness/pi-seat-sync.sh --self-test         # stubbed transports, no network
#
# Seats (env PI_SEATS overrides): win11 (this shell, Windows side) · wsl (wsl.exe -d
# $PI_WSL_DISTRO, or this shell when running inside WSL) · oldsrv (ssh $PI_OLDSRV_TARGET, the
# HD-492 door over the vps jump). Env sandbox hooks: PI_SEATS, PI_WSL_DISTRO, PI_WSL_REPO,
# PI_OLDSRV_TARGET, PI_OLDSRV_REPO, PI_SSH_OPTS, PI_SEAT_STUB (the self-test's transport).
#
# Exit: 0 all seats OK or printed-SKIP · 1 a plane drifted or failed, a seat was UNREACHABLE or
# STALE-CLONE, or a seat's declared planes did NOT all run (`coverage`) · 2 usage. A SKIP is never
# counted as in-sync, and a seat that "synced" by skipping its plane list is a FAILURE — the loop
# reads on FD 3 and the ssh transport takes `-n` for exactly that reason (see sync_seat).
#
# Owning rule: docs/pi-harness.md §1 + §5/§5a · CONVENTIONS §6.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# HD-1118 Stage 1: the repo root is FOUND by scripts/lib/repo-root.sh, never assumed
# from a depth — "one level above me" is what turns a folder move into green-while-nothing.
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"   # sets REPO (an inherited $REPO still wins)
hl_source_lib "${BASH_SOURCE[0]}" pi-seat.sh   # the plane registry reader (HD-1118 Stage 2)
MODE="check"
WANT_SEAT=""; WANT_PLANE=""

# OS class of the machine RUNNING this. `wsl.exe`'s presence is part of the test, not
# `uname` alone: Git-Bash says MINGW*, WSL says Linux, a real Debian host has no wsl.exe.
IS_WINDOWS=0; IS_WSL=0
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;; esac
[ -f /proc/version ] && grep -qi microsoft /proc/version && IS_WSL=1
command -v wsl.exe >/dev/null 2>&1 && [ "$IS_WSL" -eq 0 ] && IS_WINDOWS=1

if [ -z "${PI_SEATS:-}" ]; then
  if [ "$IS_WSL" -eq 1 ]; then SEATS="wsl oldsrv"          # inside WSL: the wsl seat is this shell
  else SEATS="${PI_SEATS:-win11 wsl oldsrv}"; fi
else SEATS="$PI_SEATS"; fi

WSL_DISTRO="${PI_WSL_DISTRO:-Debian}"
WSL_REPO="${PI_WSL_REPO:-/home/domen/source/homelab}"
OLDSRV_TARGET="${PI_OLDSRV_TARGET:-oldsrv-domen}"
OLDSRV_REPO="${PI_OLDSRV_REPO:-/home/domen/source/homelab}"
SSH_OPTS="${PI_SSH_OPTS:--o ConnectTimeout=10 -o BatchMode=yes}"

# --- the planes: the SET lives in scripts/lib/seat-planes.yml (HD-1118 Stage 2) ----------
# This file used to own the list, and install-pi-debian.sh / install-pi-wsl.sh each kept their
# own copy of it. Three lists, silently diverged — and two of the divergences were live defects:
# a from-zero seat could read GREEN with three planes never checked (its check() piped them
# through `tail -2`, which throws the exit status away and never set `bad`), and its check()
# never ran the tmux plane at all while its --push did. One registry now, read by all three
# readers: the set that CONVERGES a seat and the set that CHECKS it are the same read, so the
# two cannot drift apart again. Owners are named by FILE, so a folder move touches the tree and
# not this vocabulary — which is also why no plane argv lives here any more.
planes_for_seat() {
  # $1 = seat name, $2 = check | push. Emits `plane<TAB>argv`; argv is repo-relative because
  # it runs ON the seat with the seat's clone as cwd.
  seat_planes "$1" "${2:-check}"
}

err()  { printf 'pi-seat-sync: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }
usage() { sed -n '/^# USAGE/,/^# Exit/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) MODE="check" ;;
    --push)  MODE="push" ;;
    --seat)  shift; WANT_SEAT="${1:-}" ;;
    --plane) shift; WANT_PLANE="${1:-}" ;;
    --list)  MODE="list" ;;
    --self-test) MODE="selftest" ;;
    --help|-h) usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

# --- transports ---------------------------------------------------------------
# run_on_seat <seat> <cmd…>: stdout+stderr on stdout; rc 255 = transport died (UNREACHABLE),
# rc 3 = the seat does not exist on this host (NOT-HERE).
run_on_seat() {
  local seat="$1"; shift
  local cmd="$*"
  case "$seat" in
    win11) [ "$IS_WINDOWS" -eq 1 ] || { info "win11 seat: this host is not the Windows workstation"; return 3; }
           ( cd "$REPO" && eval "$cmd" ) ;;
    wsl)   if [ "$IS_WSL" -eq 1 ]; then ( cd "$REPO" && eval "$cmd" )
           elif command -v wsl.exe >/dev/null 2>&1; then
             wsl.exe -d "$WSL_DISTRO" -- bash -lc "cd $WSL_REPO && $cmd" 2>&1 | tr -d '\000'
           else info "wsl.exe absent — this host cannot reach the WSL seat"; return 3; fi ;;
    oldsrv) ssh -n $SSH_OPTS "$OLDSRV_TARGET" "cd $OLDSRV_REPO && $cmd" 2>&1 </dev/null ;;
    *) err "unknown seat: $seat"; return 2 ;;
  esac
}
seat_repo()  { case "$1" in win11) printf '%s' "$REPO" ;;
                        wsl)    if [ "$IS_WSL" -eq 1 ]; then printf '%s' "$REPO"; else printf '%s' "$WSL_REPO"; fi ;;
                        oldsrv) printf '%s' "$OLDSRV_REPO" ;; esac; }
seat_label() { case "$1" in win11) printf 'Win11 workstation seat' ;; wsl) printf 'Debian-on-WSL seat' ;; oldsrv) printf 'oldsrv cockpit seat' ;; esac; }

# The self-test replaces the transport with stubs; no other reason for the hook.
[ -n "${PI_SEAT_STUB:-}" ] && . "$PI_SEAT_STUB"

# classify <rc> <output> -> OK | SKIP | DRIFT | FAILED | UNREACHABLE | NOT-HERE
# The plane scripts' own rc contract: 0 ok · 1 drift-or-failure · 2 SKIP.
classify() {
  local rc="$1" out="$2"
  case "$rc" in
    0) printf 'OK' ;;
    2) printf 'SKIP' ;;
    255) printf 'UNREACHABLE' ;;
    3) printf 'NOT-HERE' ;;
    *) if printf '%s' "$out" | grep -qiE 'drift|MISSING|REFUSAL|not in sync'; then printf 'DRIFT'
       elif printf '%s' "$out" | grep -q 'SKIP'; then printf 'SKIP'
       else printf 'FAILED'; fi ;;
  esac
}

ok=0; bad=0; skipped=0; NOTES=""
tally() {
  case "$1" in
    OK) ok=$((ok+1)) ;;
    SKIP) skipped=$((skipped+1)); NOTES="$NOTES
    SKIP  $2 — a leg that proved nothing" ;;
    *) bad=$((bad+1)) ;;
  esac
}

sync_seat() {
  local seat="$1" head seat_head out rc verdict name cmd2 _mode=check
  head="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')"
  info ""
  info "── seat $seat · $(seat_label "$seat") · repo $(seat_repo "$seat")"
  out="$(run_on_seat "$seat" 'git rev-parse --short HEAD')"; rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '  %-8s %-11s %s\n' "$seat" "pre-flight" "UNREACHABLE"
    # the rev-parse call swallows a transport's own stderr into $out, which is empty when the
    # leg dies before the remote shell starts — so ask the leg once more for its reason.
    run_on_seat "$seat" 'true' 2>&1 | sed 's/^/           /'
    tally UNREACHABLE "$seat pre-flight"
    info "   the leg is down (or absent on this host). Fix the leg, or run this command FROM"
    info "   a host that can reach the seat: bash scripts/harness/pi-seat-sync.sh --seat $seat"
    return 1
  fi
  seat_head="$(printf '%s' "$out" | tr -d '\000' | tr -d '[:space:]')"
  if [ "$seat_head" != "$head" ]; then
    printf '  %-8s %-11s %s\n' "$seat" "pre-flight" "STALE-CLONE"
    tally STALE-CLONE "$seat clone at $seat_head, not $head"
    info "   this checkout $head, seat clone $seat_head — the seat's planes were NOT RUN, because"
    info "   deploying from a stale clone deploys a stale SSOT. First:"
    info "   git -C $(seat_repo "$seat") fetch origin && git -C $(seat_repo "$seat") merge --ff-only origin/main"
    return 1
  fi
  printf '  %-8s %-11s %s (%s)\n' "$seat" "pre-flight" "OK" "$head"
  tally OK ""
  # THE LOOP READS ON FD 3, and the ssh transport takes `-n` + `</dev/null`. Both are load-bearing,
  # measured on oldsrv 2026-10-09: a `while read` fed by a process substitution owns stdin, and a
  # bare `ssh` inside the loop forwards that stdin to the remote shell — so the FIRST plane ate the
  # rest of the plane list, the loop ended cleanly, and the seat reported `IN SYNC` with SEVEN OF
  # EIGHT PLANES NEVER RUN. CONVENTIONS §6's stdin rule names the piped-`bash -s` form; a loop list
  # streamed on stdin is the same trap, and this is the form a fleet driver is built out of. FD 3
  # is the invariant (a plane that reads stdin truncates nothing); `-n` is the transport's own half.
  local ran=0 expected=0 n cmd2 _mode=check _rows
  [ "$MODE" = push ] && _mode=push
  # ONE read of the registry instead of TWO process substitutions (HD-1135: a process
  # substitution measured 143 ms on a loaded Win11 seat, and this pair ran once per seat).
  # The list is materialised, the loops keep FD 3 — the stdin pairing below is the invariant
  # self-test arm 7 reddens, so only the SOURCE of the list moved.
  # A FAILED registry read is loud: an empty list from a broken read would tally 0-of-0 and
  # print a seat that synced by running nothing. An empty list from a healthy read stays
  # exactly the case their tripwire already handles.
  _rows="$(seat_planes "$seat" "$_mode")" || { tally FAILED "$seat registry"; printf '  %-8s %-11s %s\n' "$seat" "registry" "FAILED"; err "the plane registry yielded nothing for $seat ($_mode) — a short read is a broken read, not a clean seat"; return 1; }
  while IFS=$'\t' read -r -u 3 n _; do
    { [ -z "$WANT_PLANE" ] || [ "$WANT_PLANE" = "$n" ]; } && expected=$((expected+1))
  done 3<<< "$_rows"
  while IFS=$'\t' read -r -u 3 name cmd2; do
    [ -n "$WANT_PLANE" ] && [ "$WANT_PLANE" != "$name" ] && continue
    out="$(run_on_seat "$seat" "$cmd2")"; rc=$?
    verdict="$(classify "$rc" "$out")"
    printf '  %-8s %-11s %s\n' "$seat" "$name" "$verdict"
    [ "$verdict" = OK ] || printf '%s\n' "$out" | sed 's/^/           /'
    tally "$verdict" "$seat/$name"
    ran=$((ran+1))
  done 3<<< "$_rows"
  # Tripwire: never trust the plane count to equal the plane list. An IN SYNC that skipped planes
  # is the mute gate CONVENTIONS §6 names, and the exit code cannot tell the two states apart.
  if [ "$ran" -ne "$expected" ]; then
    printf '  %-8s %-11s %s\n' "$seat" "coverage" "FAILED"
    info "   only $ran of $expected declared planes ran on this seat — the run was truncated"
    info "   (something inside the loop consumed the plane list). A seat that synced by NOT running"
    info "   its planes is the failure this file exists to kill; do not read the line above as OK."
    tally FAILED "$seat coverage ($ran/$expected planes)"
    return 1
  fi
  return 0
}

# --- self-test: stubbed transports, no network, no seats ------------------------
self_test() {
  local tmp fails=0 head
  tmp="$(mktemp -d 2>/dev/null)" || { err "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  head="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')"   # same fallback as the
  # main path: a checkout without git (a tarball, a CI artifact) must still self-test — the
  # first Debian run of this file ran from one and read every seat as STALE-CLONE (2026-10-08).
  mk_stub() {  # $1 = file, $2 = rev-parse answer (EMPTY = the transport itself is dead),
              # $3 = plane rc, $4 = plane output
    if [ -z "$2" ]; then
      # A dead leg answers NOTHING, to rev-parse included — that is what ssh rc 255 means. A
      # fixture that answered rev-parse and then died would be a different bug (a mid-session
      # drop), and it passed this canary as 'synced' the first time it was written (2026-10-08).
      { printf '#!/bin/sh\nprintf "%%s\\n" "%s"\nexit %s\n' "$4" "$3"; } > "$1"
    else
      { printf '#!/bin/sh\ncase "$*" in *rev-parse*) echo "%s"; exit 0;; esac\n' "$2"
        printf 'printf "%%s\\n" "%s"\n' "$4"
        printf 'exit %s\n' "$3"; } > "$1"
    fi
    chmod +x "$1"
  }
  mk_stub "$tmp/good"   "$head"    0   "  OK: nothing to do"
  mk_stub "$tmp/drift"  "$head"    1   "  DRIFT: repo != deployed"
  mk_stub "$tmp/skip"   "$head"    2   "  SKIP: no tmux on this host"
  mk_stub "$tmp/fail"   "$head"    1   "boom: the plane threw"
  mk_stub "$tmp/down"   ""       255   "ssh: connect to host port 22: Connection timed out"
  mk_stub "$tmp/stale"  "deadbee"   0  "must never run"

  cat > "$tmp/stub.sh" <<EOS
# The CASE is selected by env, not by seat name: the plane registry knows only the REAL seats,
# and a fake seat name selects ZERO planes — which reads as a perfectly clean seat, the exact
# mute failure this file exists to catch. So the harness runs a real seat name and varies the
# transport instead.
# eat: the fixture for the truncated-plane-list defect measured on oldsrv 2026-10-09 (1 of 8
# planes ran and the run reported IN SYNC) - the good fixture PLUS the stdin drain a bare ssh
# does, so the coverage tripwire is exercised and not just documented. The -t 0 guard keeps the
# drain from hanging on a terminal. (No backticks anywhere in this heredoc: it is UNQUOTED, so a
# backtick here would run a command substitution.)
run_on_seat() { shift
  if [ "\${PI_STUB_CASE:-good}" = eat ]; then
    bash "\$STUB_DIR/good" "\$*"; [ -t 0 ] || cat >/dev/null
  else
    bash "\$STUB_DIR/\${PI_STUB_CASE:-good}" "\$*"
  fi; }
seat_repo() { printf '/stub/wsl'; }
EOS

  run_stub() { local _case="$1"; shift
    PI_SEATS="wsl" STUB_DIR="$tmp" PI_STUB_CASE="$_case" PI_SEAT_STUB="$tmp/stub.sh" \
      bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" "$@"; }
  # verdict of one case, as printed by the real reporting path
  verdict_of() { run_stub "$1" --check 2>&1 | sed -n "s/^ *wsl *pre-flight *//p" | head -1 | cut -d' ' -f1; }
  plane_line() { run_stub "$1" --check 2>&1 | sed -n "s/^ *wsl *$2 *//p" | head -1 | cut -d' ' -f1; }
  # An arm that EXPECTS green re-probes up to 3 times. The pre-flight asks git twice (here and in
  # the child it spawns), and under a 60-item parallel gate a transient read failure surfaces as a
  # verdict mismatch — a false RED. A genuine drift fails EVERY probe, so retrying removes the
  # load flake without silencing the canary; the retry is capped, and the last verdict is what
  # gets asserted. Failure-expecting arms keep their single probe.
  probe_of() { local _n _v="?" ; for _n in 1 2 3; do _v="$(verdict_of "$1")"; [ "$_v" = "$2" ] && break; sleep 0.2; done; printf '%s' "$_v"; }

  # 1. a seat that agrees -> pre-flight OK, every plane OK, exit 0.
  out="$(run_stub good --check)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$(probe_of good OK)" = OK ] && [ "$(plane_line good tui)" = OK ]; then
    info "good-seat        GREEN"
  else err "canary: a clean seat did not report IN SYNC (rc $rc)"; fails=$((fails+1)); fi

  # 2. a plane that drifted -> exit 1 and a DRIFT line (the gate's whole purpose).
  out="$(run_stub drift --check)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q DRIFT; then info "drift-seat       caught"; else err "canary passed: a drifting plane stayed green"; fails=$((fails+1)); fi

  # 3. a plane that FAILED (not drift — no recognizable word) must not read as drift or OK.
  out="$(run_stub fail --check)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q FAILED; then info "fail-seat        caught"; else err "canary passed: a failing plane was classified as something else"; fails=$((fails+1)); fi

  # 4. an unreachable seat -> UNREACHABLE + exit 1: never a silent success.
  out="$(run_stub down --check)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q UNREACHABLE; then info "unreachable      caught"; else err "canary passed: an unreachable seat read as synced"; fails=$((fails+1)); fi

  # 5. a stale clone -> STALE-CLONE and the planes must NOT have run.
  out="$(run_stub stale --check)"; rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q STALE-CLONE && ! printf '%s' "$out" | grep -q "must never run"; then
    info "stale-clone      caught (the seat's planes were not run)"
  else err "canary passed: a stale clone deployed anyway"; fails=$((fails+1)); fi

  # 6. a SKIP is not a pass and is not a failure either — printed, counted, exit 0.
  for _n in 1 2 3; do out="$(run_stub skip --check)"; rc=$?; printf '%s' "$out" | grep -q "SKIP  wsl/tmux" && break; sleep 0.2; done
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "SKIP  wsl/tmux"; then info "skip-honest      GREEN (a SKIP is named, not passed)"; else err "canary: a SKIP was not reported as a SKIP leg"; fails=$((fails+1)); fi

  # 7. a transport that drains stdin must not truncate the plane list. Deleting the `-u 3` / `3< <()`
  #    pairing reddens this arm — the first plane eats the loop's list, so `tui` never prints AND the
  #    coverage tripwire fires: both halves held down, not just the happy path.
  out="$(run_stub eat --check)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$(plane_line eat tui)" = OK ] && ! printf '%s' "$out" | grep -q 'coverage'; then
    info "stdin-drain      GREEN (every declared plane ran)"
  else err "canary passed: a stdin-eating transport truncated the plane list"; fails=$((fails+1)); fi

  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

# ================================ dispatch ======================================
if [ "$MODE" = selftest ]; then self_test; exit $?; fi
if [ "$MODE" = list ]; then
  if [ "$IS_WINDOWS" -eq 1 ]; then c="Windows (Git-Bash / PowerShell class)"
  elif [ "$IS_WSL" -eq 1 ]; then c="Debian in WSL"
  else c="Debian"; fi
  info "this host: $c"
  info "seats:  $SEATS"
  for s in $SEATS; do info "  $s — $(seat_label "$s")  repo $(seat_repo "$s")"; done
  info "planes: $(planes_for_seat wsl check | cut -f1 | tr '\n' ' ')"
  exit 0
fi

info "pi-seat-sync · $MODE · seats: $SEATS · this checkout $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')"
for s in $SEATS; do
  [ -n "$WANT_SEAT" ] && [ "$WANT_SEAT" != "$s" ] && continue
  sync_seat "$s" || true
done
echo
printf 'RESULT  ok=%d  problems=%d  skipped=%d\n' "$ok" "$bad" "$skipped"
[ "$skipped" -gt 0 ] && printf '%s\n' "$NOTES"
if [ "$bad" -gt 0 ]; then echo "NOT IN SYNC — every non-OK line above is the work list."; exit 1; fi
echo "IN SYNC (every seat reachable, every plane reporting OK)"
