#!/usr/bin/env bash
# =====================================================================
# seat-mcp-server.sh — the `mcp-server` seat plane: the launcher that keeps a localhost-only
# MCP server answering on a Debian seat (HD-1238).
#
# WHAT THIS OWNS
# --------------
#   ONE systemd USER unit, `~/.config/systemd/user/amazingmcp.service`, and nothing else. It is
#   the answer to "who keeps port 7777 up", which until this file existed was nobody: the server
#   was a terminal's child, so closing the shell deleted the MCP entry's transport and pi reported
#   the server disconnected with no act to point at.
#
#     the unit file bytes            this script renders them, and `OK` is BYTE equality
#     enabled + active               `systemctl --user is-enabled` / `is-active`, read back
#     the port answers               one HTTP read on 127.0.0.1 — see WHY 127.0.0.1
#
# WHAT IT DOES NOT OWN
# --------------------
#   Not the MCP client config: `~/.pi/agent/mcp.json` stays seat state with no owner, which is
#   the OTHER half of HD-1238 and a separate ruling (a fleet copy of a `localhost` entry buys
#   every seat a server it can never reach). Not the .NET SDK, and not the tool itself — this
#   plane REFUSES to install either, because `dotnet tool install` moves a binary no pin in
#   `IaC/ansible/group_vars/all/versions.yml` names (CONVENTIONS §7). Not the win11 carrier: on
#   that seat the launcher is a per-user Startup entry, and the registry row does not name win11,
#   so this script answers SKIP there rather than pretending systemd exists.
#
# WHY 127.0.0.1 AND NOT localhost
# -------------------------------
#   Measured on the WSL seat: the server listens on BOTH 127.0.0.1 and ::1, and the ::1 leg
#   answers NOTHING. A probe that resolves `localhost` first takes the dead leg and reports a
#   server that is up as down — the mute-gate class (CONVENTIONS §6), in the other direction.
#   So every read here names the IPv4 loopback explicitly.
#
# THE ONE VALUE READ FROM THE BOX
# -------------------------------
#   `DOTNET_ROOT` in the unit belongs there ONLY where the .NET runtime is not a prefix install.
#   On the cockpit the runtime lives in `~/.dotnet`, and without the line the apphost answers
#   `You must install .NET`. On the WSL seat the runtime is `/usr/share/dotnet`, and SETTING the
#   variable to a `~/.dotnet` that does not exist is what BREAKS the same binary. The rule is a
#   read of the filesystem, never a per-seat name — a box that gets reimaged changes the answer
#   without anyone editing this file.
#
# VERDICTS   (`OK` is BYTE equality with what `--push` writes, so "in sync" and "a push changes
#            nothing" are one fact and never two claims that can disagree)
#   OK                  the unit is ours, is enabled, is active, and 127.0.0.1 answers
#   MISSING             no unit file under this name
#   DRIFT               the unit is not the render, or is not enabled, or is not active
#   DRIFT(no-listener)  the unit is active and NOTHING answers on the port — an `active` service
#                       is not evidence of a serving process, and this is the verdict that says so
#   REFUSAL             a unit file with this name that carries no `managed-by:` line. The file is
#                       left byte-identical; `--push` will not overwrite a launcher it did not write
#
# Exit: 0 OK / repaired · 1 MISSING, DRIFT under `--strict`, a REFUSAL, or a push that did not
#       take · 2 NO VERDICT — systemctl(1) absent, the probe died rather than answered, or THIS BOX
#       IS NOT A SEAT THIS ROW NAMES (the fan-out counts that rc as its own SKIP, which is neither
#       a pass nor a failure).
#
# USAGE
#   bash scripts/harness/seat-mcp-server.sh                  # --check
#   bash scripts/harness/seat-mcp-server.sh --check --strict # the seat-leg form
#   bash scripts/harness/seat-mcp-server.sh --push           # write, enable, re-prove
#   bash scripts/harness/seat-mcp-server.sh --self-test      # stubs, no systemd, no network
#
# Env (sandbox hooks for --self-test only): MCP_UNIT, MCP_SYSTEMCTL, MCP_PROBE, MCP_TOOL,
#   MCP_DOTNET_DIR, PI_SEAT.
#
# Owning rule: docs/harness-pi-seats.md §1 (the mcp.json row) · scripts/lib/seat-planes.yml
# (`plane: mcp-server`) · todo.md HD-1238.
set -uo pipefail

_hl_self="${BASH_SOURCE[0]}"
case "$_hl_self" in */*) _hl_d="${_hl_self%/*}" ;; *) _hl_d="." ;; esac
_hl_d="$(cd "$_hl_d" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"
# shellcheck source=/dev/null
hl_source_lib "${BASH_SOURCE[0]}" pi-seat.sh    # hl_seat_here + hl_seat_scope_lists: who owes a leg

PLANE_ID="mcp-server"
UNIT="${MCP_UNIT:-$HOME/.config/systemd/user/amazingmcp.service}"
UNIT_NAME="amazingmcp.service"
RUNTIME_DIR="${MCP_DOTNET_DIR:-$HOME/.dotnet}"
PORT=7777
SYSTEMCTL="${MCP_SYSTEMCTL:-systemctl}"
PROBE="${MCP_PROBE:-}"                      # empty = the real curl read
MODE="check"; STRICT=0

err()  { printf 'seat-mcp-server: %s\n' "$*" >&2; }
stop() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }
usage() { sed -n '/^# USAGE/,/^# Env/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --- the render: ONE text, written by --push and compared by --check -------------------------
render_unit() {
  # Resolved INSIDE the render, never frozen at load: a self-test arm must be able to move the
  # runtime and the tool under a render that is still running in the same shell.
  local tool="${MCP_TOOL:-$HOME/.dotnet/tools/AmazingMCP}"
  local rd="${MCP_DOTNET_DIR:-$HOME/.dotnet}"
  local envline='# DOTNET_ROOT deliberately unset: the runtime is a system prefix install.'
  # A read of the box, not of its name — see THE ONE VALUE READ FROM THE BOX.
  if [ -d "$rd/shared/Microsoft.NETCore.App" ]; then
    envline="Environment=DOTNET_ROOT=$rd   # the runtime lives here on this box"
  fi
  printf '%s\n' "[Unit]
Description=AmazingMCP - MCP over HTTP for pi (launcher owned by the $PLANE_ID plane)
Documentation=file:$REPO/docs/harness-pi-seats.md
After=network.target

[Service]
# --urls is not cosmetic: an EMPTY command line makes the host fall back to port 5000 while
# --help still advertises 7777, so a typed start and a silent one looked like two services.
ExecStart=$tool --urls http://localhost:$PORT
$envline
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target

# managed-by: scripts/harness/seat-mcp-server.sh — do not edit in place; edit the owner and
# re-run it with --push. A unit with this name and no such line is a REFUSAL, never an overwrite."
}

# --- the reads ------------------------------------------------------------------------------
sysd() { # sysd <verb> — one systemctl --user call, rc 0/1/other, never fatal here
  local v="$1" out rc=0
  out="$("$SYSTEMCTL" --user "$v" "$UNIT_NAME" 2>&1)" || rc=$?
  printf '%s' "${out%%$'\n'*}"
  return "$rc"
}
probe_port() { # rc 0 answers (any HTTP answer, 400 included), 1 nothing serves, 2 the probe DIED
  # rc 2 is not a verdict about the server: CONVENTIONS §6 — a dead probe is never evidence.
  local rc=0 code
  if [ -n "$PROBE" ]; then
    "$PROBE" >/dev/null 2>&1 || rc=$?
    case "$rc" in 0) return 0 ;; 1) return 1 ;; *) return 2 ;; esac
  fi
  command -v curl >/dev/null 2>&1 || return 2
  code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:$PORT/" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) [ -n "$code" ] && [ "$code" != "000" ] && return 0; return 1 ;;
    7|52|56|55) return 1 ;;   # refused / empty reply / reset — nothing serves that port
    *) return 2 ;;            # curl itself failed (missing, no TLS lib, bad option): no verdict
  esac
}

# --- the assess: one path for --check and for the read-back after --push ----------------------
say_read() {
  printf 'read: seat=%s unit=%s exists=%s enabled=%s active=%s port=%s\n' \
    "${SEAT:-?}" "$UNIT" "$([ -e "$UNIT" ] && echo yes || echo no)" "$ENABLED" "$ACTIVE" "$PORTVERDICT"
}
assess() {
  ENABLED="$(sysd is-enabled || true)"; ACTIVE="$(sysd is-active || true)"
  PORTVERDICT="silent"; probe_port; case $? in 0) PORTVERDICT="answers" ;; 1) ;; *) PORTVERDICT="probe-died" ;; esac
  local want got
  # A dead probe ends the assess BEFORE any comparison: "the probe could not read the port" outranks
  # every statement about the file, or a broken probe would be reported as a unit defect.
  if [ "$PORTVERDICT" = "probe-died" ]; then VERDICT="NO-PROBE"; REASON="the port probe died rather than answered — an unread port is not evidence about a server"; return 0; fi
  if [ ! -e "$UNIT" ]; then VERDICT="MISSING"; REASON="no unit file under this name"; return 0; fi
  if ! grep -q '^# managed-by: scripts/harness/seat-mcp-server.sh' "$UNIT"; then
    VERDICT="REFUSAL"; REASON="a unit with this name that this script did not write — bytes left alone"; return 0
  fi
  got="$(cat "$UNIT")"; want="$(render_unit)"
  if [ "$got" != "$want" ]; then VERDICT="DRIFT"; REASON="the unit is not the render (its DOTNET_ROOT line follows the box, so this is usually a moved runtime)"; return 0; fi
  if [ "$ENABLED" != "enabled" ]; then VERDICT="DRIFT"; REASON="the unit exists but is not enabled — systemctl --user is-enabled says: $ENABLED"; return 0; fi
  if [ "$ACTIVE" != "active" ]; then VERDICT="DRIFT"; REASON="the unit is enabled but not active — systemctl --user is-active says: $ACTIVE"; return 0; fi
  if [ "$PORTVERDICT" != "answers" ]; then
    VERDICT="DRIFT(no-listener)"; REASON="the service reports active and NOTHING answers on $PORT — an active unit is not a serving process"; return 0
  fi
  VERDICT="OK"; REASON=""
}

# --- the scope read, FIRST: a unit cannot be owed on a box whose seat this row does not name --
seat_scope() {
  hl_seat_here SEAT
  SCOPE_LIST="$(hl_seat_scope_list "$PLANE_ID")"
  if [ -z "${SEAT:-}" ] || [ "$SEAT" = none ]; then SCOPE="no-seat"; return 0; fi
  hl_seat_scope_lists "$PLANE_ID" "$SEAT"
  case $? in
    0) SCOPE="here" ;;
    1) SCOPE="elsewhere" ;;
    *) stop "the plane registry at $(hl_seat_registry_path) cannot be read — the leg cannot tell whether this box owes a launcher, and a unit written on that guess is a service nobody asked for" ;;
  esac
}
scope_verdict() {
  case "$SCOPE" in
    elsewhere) printf 'SKIP: %s — the `%s` leg belongs to the seats its registry row names (seats: %s); this box owes no systemd launcher\n' \
        "$SEAT" "$PLANE_ID" "${SCOPE_LIST:-<empty>}" ;;
    no-seat)   printf 'SKIP: no seat — this box is none of the harness seats, so `%s` cannot be scoped here\n' "$PLANE_ID" ;;
  esac
  return 2
}

do_check() {
  seat_scope
  [ "$SCOPE" = here ] || { scope_verdict; return $?; }
  command -v curl >/dev/null 2>&1 || [ -n "$PROBE" ] || stop "no curl and no MCP_PROBE — the port cannot be read, and an unread port is not evidence of a dead server"
  assess
  say_read
  [ "$VERDICT" = NO-PROBE ] && stop "$REASON"
  if [ "$VERDICT" = OK ]; then printf 'OK: %s is ours, enabled, active, and 127.0.0.1:%s answers\n' "$UNIT_NAME" "$PORT"; return 0; fi
  printf '%s: %s — %s\n' "$VERDICT" "$UNIT_NAME" "$REASON"
  [ "$STRICT" -eq 1 ] && return 1
  case "$VERDICT" in MISSING|REFUSAL) return 1 ;; *) return 0 ;; esac
}

do_push() {
  seat_scope
  [ "$SCOPE" = here ] || { scope_verdict; return $?; }
  if [ -e "$UNIT" ] && ! grep -q '^# managed-by: scripts/harness/seat-mcp-server.sh' "$UNIT"; then
    printf 'REFUSAL: %s exists and was not written by this script — NOTHING was written\n' "$UNIT"
    printf '         read it, then either retire the foreign launcher or move it aside and re-run.\n'
    return 1
  fi
  want="$(render_unit)"
  if [ -e "$UNIT" ] && [ "$(cat "$UNIT")" = "$want" ]; then
    assess
    [ "$VERDICT" = NO-PROBE ] && stop "$REASON"
    if [ "$VERDICT" = OK ]; then printf 'no-op: the unit is already the render and the port answers (enabled=%s active=%s)\n' "$ENABLED" "$ACTIVE"; return 0; fi
  fi
  mkdir -p "$(dirname "$UNIT")" || { err "cannot create the unit directory"; return 1; }
  printf '%s\n' "$want" > "$UNIT" || { err "cannot write $UNIT"; return 1; }
  "$SYSTEMCTL" --user daemon-reload >/dev/null 2>&1 || stop "systemctl --user daemon-reload failed — is a user manager running here?"
  "$SYSTEMCTL" --user enable --now "$UNIT_NAME" >/dev/null 2>&1 || stop "systemctl --user enable --now failed for $UNIT_NAME"
  sleep 2
  assess; say_read
  [ "$VERDICT" = NO-PROBE ] && stop "$REASON"
  if [ "$VERDICT" = OK ]; then printf 'OK: wrote the unit and RE-PROVED it — enabled, active, 127.0.0.1:%s answers\n' "$PORT"; return 0; fi
  printf '%s: after the push — %s\n' "$VERDICT" "$REASON"
  return 1
}

# --- self-test: stubs, so no systemd, no network, no seat required ---------------------------
self_test() {
  local t fails=0 want
  t="$(mktemp -d)" || { err "mktemp failed"; return 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$t'" RETURN
  want_unit() { MCP_TOOL="$t/AmazingMCP" MCP_DOTNET_DIR="$DOTNET" render_unit; }

  # fixtures: a stub systemctl that answers from files, and a probe that answers from a file.
  cat > "$t/systemctl" <<'EOS'
#!/bin/sh
# answers is-enabled / is-active / daemon-reload / enable from files the arms write
for a in "$@"; do case "$a" in is-enabled) cat "$ST_ENABLED" 2>/dev/null || printf 'disabled\n'; exit 0;; is-active) cat "$ST_ACTIVE" 2>/dev/null || printf 'inactive\n'; exit 0;; esac; done
exit 0
EOS
  cat > "$t/probe-answer" <<'EOS'
#!/bin/sh
[ -f "$ST_LISTENING" ] && exit 0
exit 1
EOS
  chmod +x "$t/systemctl" "$t/probe-answer"
  printf 'enabled\n' > "$t/on"; printf 'disabled\n' > "$t/off"
  printf 'active\n'  > "$t/act"; printf 'inactive\n' > "$t/inact"
  mkdir -p "$t/dotnet-shared/shared/Microsoft.NETCore.App"

  run_at() { # run_at <expect-rc> <env assignments...> -- the arms all run the REAL CLI
    local want="$1"; shift
    PI_SEAT="${PI_SEAT:-wsl}" MCP_SYSTEMCTL="$t/systemctl" MCP_PROBE="$t/probe-answer" \
    MCP_TOOL="$t/AmazingMCP" MCP_DOTNET_DIR="${DOTNET:-$t/dotnet-none}" \
    MCP_UNIT="$UNIT_PATH" bash "${BASH_SOURCE[0]}" "$@" > "$t/out" 2>&1
    local got=$?
    if [ "$got" = "$want" ]; then printf 'ok   rc %s  %s\n' "$got" "$1"
    else printf 'NOT CAUGHT  wanted rc %s, got %s  %s\n' "$want" "$got" "$1"; printf '%s\n' "$(sed 's/^/        /' "$t/out")"; fails=$((fails+1)); fi
  }
  UNIT_PATH="$t/unit.service"
  DOTNET="$t/dotnet-none"
  export ST_ENABLED="$t/on" ST_ACTIVE="$t/act" ST_LISTENING="$t/listening"

  # 1. every fact true, under a prefix runtime → OK, rc 0.
  touch "$ST_LISTENING"
  want_unit > "$UNIT_PATH"; run_at 0 --check --strict
  grep -q '^OK:' "$t/out" || { printf 'NOT CAUGHT OK did not print its OK line\n'; fails=$((fails+1)); }

  # 2. THE MUTE GATE: enabled, active, NOTHING answering. `active` is not a server.
  rm -f "$ST_LISTENING"; run_at 1 --check --strict
  grep -q 'DRIFT(no-listener)' "$t/out" || { printf 'NOT CAUGHT a silent unit was not named as silent\n'; fails=$((fails+1)); }
  touch "$ST_LISTENING"

  # 3. enabled-but-inactive, and a unit that is not the render, both redden.
  ST_ENABLED="$t/on" ST_ACTIVE="$t/inact" bash -c "MCP_SYSTEMCTL='$t/systemctl' MCP_PROBE='$t/probe-answer' MCP_TOOL='$t/AmazingMCP' PI_SEAT=wsl MCP_UNIT='$UNIT_PATH' MCP_DOTNET_DIR='$t/dotnet-none' bash '${BASH_SOURCE[0]}' --check --strict" > "$t/out" 2>&1
  [ $? -eq 1 ] && grep -q '^DRIFT: .*not active.*inactive' "$t/out" \
    || { printf 'NOT CAUGHT an inactive unit stayed green, or its systemctl answer never reached the line (a backquote in a REASON runs the service output)\n'; fails=$((fails+1)); }
  printf 'tampered\n' >> "$UNIT_PATH"; run_at 1 --check --strict
  grep -q 'not the render' "$t/out" || { printf 'NOT CAUGHT a tampered unit was not named\n'; fails=$((fails+1)); }

  # 4. absent file → MISSING; a FOREIGN unit → REFUSAL that writes nothing.
  rm -f "$UNIT_PATH"; run_at 1 --check --strict
  grep -q '^MISSING:' "$t/out" || { printf 'NOT CAUGHT an absent unit was not MISSING\n'; fails=$((fails+1)); }
  printf '[Service]\nExecStart=/somewhere/else\n' > "$UNIT_PATH"
  cp "$UNIT_PATH" "$t/foreign.before"; run_at 1 --check --strict
  grep -q '^REFUSAL:' "$t/out" || { printf 'NOT CAUGHT a foreign unit was not a refusal\n'; fails=$((fails+1)); }
  run_at 1 --push
  cmp -s "$UNIT_PATH" "$t/foreign.before" || { printf 'NOT CAUGHT --push overwrote a foreign unit\n'; fails=$((fails+1)); }

  # 5. the DOTNET_ROOT rule is a read of the box: a home-prefix runtime gets the line, a system
  #    prefix gets its ABSENCE — asserted on what --push writes, not on a function call that would
  #    read a RUNTIME_DIR frozen before the fixture could move.
  rm -f "$UNIT_PATH"; DOTNET="$t/dotnet-shared" run_at 0 --push
  grep -q '^Environment=DOTNET_ROOT=' "$UNIT_PATH" \
    || { printf 'NOT CAUGHT no DOTNET_ROOT line where the runtime is a home prefix\n'; fails=$((fails+1)); }
  rm -f "$UNIT_PATH"; DOTNET="$t/dotnet-none" run_at 0 --push
  grep -q 'deliberately unset' "$UNIT_PATH" \
    || { printf 'NOT CAUGHT a DOTNET_ROOT line where the runtime is a system prefix\n'; fails=$((fails+1)); }
  printf 'ok   the DOTNET_ROOT line follows the box in both arms\n'

  # 6. a seat the row does not name answers SKIP (rc 2), and --push writes NOTHING there.
  PI_SEAT=oldsrv run_at 2 --check --strict
  grep -q '^SKIP: oldsrv' "$t/out" || { printf 'NOT CAUGHT an off-scope seat did not answer SKIP\n'; fails=$((fails+1)); }
  rm -f "$UNIT_PATH"; PI_SEAT=oldsrv run_at 2 --push
  [ -e "$UNIT_PATH" ] && { printf 'NOT CAUGHT --push wrote a unit off-scope\n'; fails=$((fails+1)); }

  # 7. --push on a box with nothing: writes the render and re-proves it (rc 0 with the stubs).
  want_unit > "$UNIT_PATH.tmp"; rm -f "$UNIT_PATH"; run_at 0 --push
  cmp -s "$UNIT_PATH" "$UNIT_PATH.tmp" || { printf 'NOT CAUGHT --push wrote something other than the render\n'; fails=$((fails+1)); }

  # 8. a probe that DIES is not a verdict about the server: rc 2, and the word "died".
  printf '#!/bin/sh\nexit 3\n' > "$t/probe-dead"; chmod +x "$t/probe-dead"
  bash -c "MCP_SYSTEMCTL='$t/systemctl' MCP_PROBE='$t/probe-dead' MCP_TOOL='$t/AmazingMCP' PI_SEAT=wsl MCP_UNIT='$UNIT_PATH' MCP_DOTNET_DIR='$t/dotnet-none' bash '${BASH_SOURCE[0]}' --check --strict" > "$t/out" 2>&1
  [ $? -eq 2 ] && grep -qi 'died' "$t/out" || { printf 'NOT CAUGHT a dead probe produced a verdict instead of no verdict\n'; fails=$((fails+1)); }

  printf '\nself-test: %s\n' "$([ "$fails" -eq 0 ] && echo "OK — all canaries caught" || echo "$fails canary/canaries NOT caught")"
  return "$fails"
}

MODE="check"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) MODE="check" ;;
    --strict) STRICT=1 ;;
    --push)  MODE="push" ;;
    --self-test) MODE="selftest" ;;
    --help|-h) usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

case "$MODE" in
  check)    do_check ;;
  push)     do_push ;;
  selftest) self_test ;;
esac
