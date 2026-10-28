#!/usr/bin/env bash
# =====================================================================
# seat-llm-path-timer.sh — the RE-ASSERT arm of the `llm-path` seat plane: the systemd pair that lands
# the hosts pin again on a box whose distro rewrites its own hosts file.
#
# WHY THIS EXISTS
# ---------------
#   The seat's hosts file is WSL-generated — the file's own header says so, and `generateHosts` is on —
#   so EVERY distro start DELETES the marker block seat-llm-path.sh owns. The plane sees that and reports
#   MISSING, which is a read and not an act: with nothing running the push half, a reboot put the
#   inference name back on the edge answer until a person, or the seat fan-out's `llm-path` leg, happened
#   to ask. The route arm beside this seat already re-asserts itself on a 2-minute timer; this pair gives
#   the pin the same shape, so the state survives a boot instead of surviving until the next look.
#
# WHAT THIS OWNS / WHAT IT DOES NOT
# ---------------------------------
#   The two unit files, byte for byte, and nothing else:
#     seat-llm-path.service  a oneshot whose ExecStart runs the PLANE's push half, at the repo path
#     seat-llm-path.timer    the cadence, WantedBy=timers.target — the only unit that gets enabled
#   It NEVER writes a hosts file. The hosts WRITE stays `seat-llm-path.sh --push`, and that is what the
#   unit runs: the push half remains a root act, the SSOT read and the reachability probe stay inside
#   that one script, and `installer: none` on the plane's registry record keeps meaning what it says — a
#   from-zero bootstrap still does not converge a root-owned hosts file. What a reimaged box gains is a
#   unit pair that exists in the repo, so the arm comes back with the clone instead of living on one box.
#   Not the resolver arms — the per-link claim, the resolved drop-in and the homelab-dns-route pair are a
#   separate family with their own ExecStart and their own cadence, untouched here. Not the answer plane
#   (zone rows, netmap records, tailnet policy), not the engine, not the certificate.
#
# WHY A SIBLING PAIR AND NOT THE ROUTE UNIT
# -----------------------------------------
#   One unit family per arm. The route pair converges resolver STATE through `resolvectl`; folding a
#   hosts WRITE into it would make one arm's failure print as the other's, and one unit carries one `Type=`
#   and one cadence, not two. Two pairs is also what lets a drift verdict name WHICH arm moved.
#
# THE CONSTANTS THIS FILE HOLDS — and the values it does NOT
# ---------------------------------------------------------
#   cadence     OnBootSec=10s OnUnitActiveSec=120s — the shape of the seat's existing
#               homelab-dns-route.timer: 10 s so the first fire lands AFTER the distro start that
#               regenerates the file, 120 s so a pin whose path stopped answering is gone within one
#               interval.
#   ExecStart   `/bin/bash <this repo>/scripts/harness/seat-llm-path.sh --push`, the repo root FOUND from
#               this script's own location. Never a copy under `/usr/local/sbin`: an unowned copy is a
#               second source that no converge reaches and no drift check can see (CONVENTIONS §2), which
#               is the standing complaint about the seat's other hand-placed artifacts. A clone that moves
#               to another path therefore reads as DRIFT that `--install` repairs, not as a working arm.
#   No fleet value sits in either unit. The name and the address are read from the SSOT by the plane
#   script at every fire, so re-addressing a host never touches a unit file — and a unit file that carried
#   an address would be one value with two owners.
#
# WHY Type=oneshot WITHOUT RemainAfterExit
# ----------------------------------------
#   With `RemainAfterExit=yes` the unit stays `active (exited)` after its first run, and systemd starts an
#   already-active unit by doing NOTHING: every later start — every timer fire included — becomes a no-op
#   that REPORTS SUCCESS. The re-assert is the whole point of the unit, so it must go inactive when it
#   finishes. The same trap is written into the route unit's own comment, which is why a drop-in that adds
#   the key back is a DRIFT(drop-in) verdict here rather than something a green file compare hides.
#
# VERDICTS   (`OK` is BYTE equality with what `--install` writes, so "in sync" and "an install changes
#            nothing" are one fact, never two claims that can disagree — the rule seat-llm-path.sh
#            applies to the hosts block)
#   OK               both unit files are the render
#   MISSING          a unit file is not there: the arm does not exist (a reimaged box, a hand cleanup)
#   DRIFT            a file this script wrote is not the render — a moved cadence, an ExecStart aimed
#                    outside the repo, a hand-added RemainAfterExit, a clone whose path moved
#   DRIFT(foreign)   a unit file with this arm's NAME that this script did not write. `--install` REFUSES
#                    it and writes NOTHING, because half an installed arm is a state no later verdict can
#                    describe.
#   DRIFT(drop-in)   a drop-in under <unit>.d/ that sets RemainAfterExit — the trap, arriving through a
#                    side door. Any OTHER drop-in content prints as a NOTE and changes no verdict: that is
#                    an operator override, outside what this arm owns.
#
# Exit: 0 OK / repaired · 1 MISSING, or DRIFT under `--strict`, or an `--install` that refused, or one
#       whose enable leg could not run (a written-but-never-enabled timer is an arm that never fires) ·
#       2 NO VERDICT — the unit directory cannot be read, the plane the ExecStart names is not in the
#       repo, or a sandbox hook is wrong (a guess is not a verdict).
#
# Usage:
#   bash scripts/harness/seat-llm-path-timer.sh                     # --check, report only
#   bash scripts/harness/seat-llm-path-timer.sh --check --strict    # the failing form of a check
#   bash scripts/harness/seat-llm-path-timer.sh --render [unit]     # print what it renders; writes nothing
#   sudo bash scripts/harness/seat-llm-path-timer.sh --install      # the act (root: it writes unit files
#                                                                   #   and enables the timer)
#   bash scripts/harness/seat-llm-path-timer.sh --self-test         # fixtures; nothing under /etc, no
#                                                                   #   systemd, no network
#
# Env hooks — every one points the script at a FIXTURE; none of them changes a verdict rule:
#   REPO                      a fixture repo whose scripts/harness/seat-llm-path.sh is the ExecStart target
#   SEAT_LLM_TIMER_DIR        the unit directory (default /etc/systemd/system)
#   SEAT_LLM_TIMER_ST         set by a fixture run only: it arms the guard that STOPS an install which
#                             forgot the systemctl stub, so no self-test arm can drive a real systemd.
#   SEAT_LLM_TIMER_SYSTEMCTL  the systemctl used by the enable leg and the read-back (default: PATH's).
#                             A self-test arm points it at a STUB that RECORDS its argv, so "the timer got
#                             enabled" is an arm rather than a hope, provable on a machine with no systemd.
#
# ⚠ Nothing here is wired into validate-all.sh, and that is deliberate: on the Debian hosts these units
#   are legitimately absent, so a gate item would report MISSING everywhere forever — the mute-a-gate
#   class. `--check` on the seat is the read, `--install` on the seat as root is the act.
#   Registry: scripts/lib/seat-planes.yml owns the PLANE this arms (the record `plane: llm-path`, whose
#   owner stays seat-llm-path.sh). The registry has no field for a re-assert arm and none was invented —
#   a key invented for one reader is a second source about a plane the reader does not fan out.
#   Rules: docs/network-dns.md §Host-side resolver · docs/harness-pi-seats.md §1
# =====================================================================
set -uo pipefail

# The repo root is FOUND by scripts/lib/repo-root.sh, never assumed from a depth. An inherited $REPO
# still wins, which is the lever --self-test uses to point the ExecStart at a fixture repo.
_hl_self="${BASH_SOURCE[0]}"
case "$_hl_self" in */*) _hl_d="${_hl_self%/*}" ;; *) _hl_d="." ;; esac
_hl_d="$(cd "$_hl_d" && pwd)"
SCRIPT_DIR="$_hl_d"
SELF="$SCRIPT_DIR/$(basename "$_hl_self")"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"

SVC="seat-llm-path.service"
TMR="seat-llm-path.timer"
UNIT_DIR="${SEAT_LLM_TIMER_DIR:-/etc/systemd/system}"
SYSTEMCTL="${SEAT_LLM_TIMER_SYSTEMCTL:-systemctl}"
PLANE="$REPO/scripts/harness/seat-llm-path.sh"
ON_BOOT_SEC="10s"
ON_ACTIVE_SEC="120s"
# WHO WROTE THIS UNIT. The identity is the PLANE, not this file's path: a marker that names a path goes
# stale the day the script changes folder, and every unit it wrote would start reading as foreign — the
# `managed-by:` lesson install-tmux-conf.sh carries after its own folder move.
MARKER='# managed-by: homelab llm-path re-assert arm (scripts/harness/seat-llm-path-timer.sh)'

MODE="check"; STRICT=0; SCRATCH=""; RENDER_ONLY=""
STATE=""; REASON=""; RANK=0
U_NAMES=(); U_STATES=()

err()  { printf 'seat-llm-path-timer: %s\n' "$*" >&2; }
note() { printf '  %s\n' "$*"; }
# A STOP, never a report: exit 2 means "no verdict was computed", so nothing downstream may read the run
# as a state. It must run in the CALLER's shell — inside `$( )` an `exit` stops only the subshell (the
# rule lib/pi-seat.sh carries), which is why every read here returns through a variable and never a
# command substitution.
stop() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }
usage() {
  cat <<'EOF'
usage: seat-llm-path-timer.sh [--check [--strict]] | --render [unit] | --install | --self-test

  --check          (default) report the two unit files against what this script renders
  --check --strict exit 1 on DRIFT too (MISSING exits 1 either way)
  --render [unit]  print the rendered unit(s) to stdout — nothing written, nothing enabled. The unit
                   names are seat-llm-path.service and seat-llm-path.timer.
  --install        root act: write the two unit files — only what this script owns; a foreign file is a
                   REFUSAL that writes nothing — then daemon-reload and `enable --now` the timer.
                   Unprivileged: prints the exact sudo command and changes nothing.
  --self-test      fixture unit dir, fixture repo, stub systemctl; no /etc, no systemd, no network
EOF
}

scratch() {
  [ -n "$SCRATCH" ] && return 0
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/seat-llm-path-timer.XXXXXX")" || { err "mktemp failed"; exit 2; }
}
cleanup() { [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

# The self-test's belt: a fixture run must never be able to drive a real systemd. The stub hook is the
# mechanism; this is what makes FORGETTING the hook a STOP instead of an act on the host running it.
st_guard() {
  [ -n "${SEAT_LLM_TIMER_ST:-}" ] || return 0
  [ -n "${SEAT_LLM_TIMER_SYSTEMCTL:-}" ] \
    || stop "self-test arm with no systemctl stub — refusing to run a real systemctl for a fixture"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check)     MODE="check" ;;
    --strict)    STRICT=1 ;;
    --install)   MODE="install" ;;
    --render)    MODE="render" ;;
    --self-test) MODE="selftest" ;;
    -h|--help)   usage; exit 0 ;;
    *)
      if [ "$MODE" = "render" ] && { [ "$1" = "$SVC" ] || [ "$1" = "$TMR" ]; }; then
        RENDER_ONLY="$1"
      else
        usage; exit 2
      fi ;;
  esac
  shift
done

# --- the render -------------------------------------------------------------------
# The render is the ONLY writer of unit text, so there is no second copy of a unit file in the tree to
# drift from. Both `--check` and `--install` compare against it, and everything a unit needs is composed
# from the repo root this script was found in — which is what makes the same bytes correct on a reimaged
# box at a different path.
render_service() {
  { printf '%s\n' "$MARKER"
    printf '# Re-asserts the homelab WSL seat'"'"'s llm-path hosts pin. Edit this unit in that script,\n'
    printf '# not here: its --install rewrites only what it owns and REFUSES bytes it did not write.\n'
    printf '[Unit]\n'
    printf 'Description=Homelab WSL seat: re-assert the llm-path hosts pin (seat-llm-path.sh --push)\n'
    printf 'Documentation=file://%s/docs/network-dns.md\n' "$REPO"
    printf '\n[Service]\n'
    printf '# Type=oneshot WITHOUT RemainAfterExit, on purpose: with RemainAfterExit=yes the unit stays\n'
    printf '# active (exited) and every later start - every timer fire included - is a NO-OP that\n'
    printf '# reports success. The re-assert is the whole point, so the unit must go inactive when done.\n'
    printf 'Type=oneshot\n'
    printf '# The REPO path, never a copy under /usr/local/sbin: an unowned copy is what no converge\n'
    printf '# reaches and what no drift check can see. The name and the address live inside that script,\n'
    printf '# read from the SSOT at every fire, so this unit carries no fleet value of its own.\n'
    printf 'ExecStart=/bin/bash %s/scripts/harness/seat-llm-path.sh --push\n' "$REPO"
    printf '\n# No [Install] section: the timer starts this unit, and the timer is the only thing\n'
    printf '# --install enables, so the pair has exactly one trigger.\n'; } >"$1"
}
render_timer() {
  { printf '%s\n' "$MARKER"
    printf '# The cadence of the homelab llm-path re-assert arm. Edit it in that script, not here.\n'
    printf '[Unit]\n'
    printf 'Description=Re-assert the llm-path hosts pin on the WSL seat (the distro rewrites /etc/hosts)\n'
    printf 'Documentation=file://%s/docs/network-dns.md\n' "$REPO"
    printf '\n[Timer]\n'
    printf '# The homelab-dns-route.timer shape: once shortly after each boot — that start is when WSL\n'
    printf '# regenerates /etc/hosts and deletes the pin — then every interval, so a pin whose path\n'
    printf '# stopped answering is removed within one interval.\n'
    printf 'OnBootSec=%s\n' "$ON_BOOT_SEC"
    printf 'OnUnitActiveSec=%s\n' "$ON_ACTIVE_SEC"
    printf '\n[Install]\n'
    printf 'WantedBy=timers.target\n'; } >"$1"
}
render() {   # render <unit> <out>
  case "$1" in
    "$SVC") render_service "$2" ;;
    "$TMR") render_timer   "$2" ;;
    *)      stop "render: [$1] is not a unit this script owns ($SVC, $TMR)" ;;
  esac
}

# --- the verdict ------------------------------------------------------------------
# assess fills the per-unit states and the overall STATE: OK | MISSING | DRIFT | DRIFT(foreign) |
# DRIFT(drop-in). Every finding is printed; the overall word is the STRONGEST one, because the report has
# to name the finding that explains a broken arm best, and an exit code cannot tell "absent" from "wrong".
rank_state() {   # rank_state <state> — keeps the strongest finding of the sweep
  local r
  case "$1" in
    OK)               r=0 ;;
    DRIFT)            r=2 ;;
    'DRIFT(drop-in)') r=3 ;;
    'DRIFT(foreign)') r=4 ;;
    MISSING)          r=5 ;;
    *)                stop "rank_state: unknown state [$1]" ;;
  esac
  [ "$r" -le "$RANK" ] && return 0
  RANK="$r"; STATE="$1"
}

assess() {
  [ -d "$UNIT_DIR" ] || stop "no unit directory at $UNIT_DIR — nothing can be read, so no verdict is owed"
  [ -r "$PLANE" ] || stop "the plane this arm must call is not readable at $PLANE — a unit whose ExecStart names a script that is not in the repo is a timer that fires a failure, so nothing here is reported as in sync"
  local u inst want dropin i why=""
  STATE="OK"; REASON=""; RANK=0; U_NAMES=(); U_STATES=()
  for u in "$SVC" "$TMR"; do
    inst="$UNIT_DIR/$u"; want="$SCRATCH/$u.want"
    render "$u" "$want"
    if [ ! -e "$inst" ]; then
      U_NAMES+=("$u"); U_STATES+=("MISSING")
      note "$u: MISSING — not installed ($inst is not there)"
      rank_state MISSING
      continue
    fi
    [ -r "$inst" ] || stop "cannot read $inst — a verdict about a unit file nobody can read is not a verdict"
    if cmp -s "$inst" "$want"; then
      U_NAMES+=("$u"); U_STATES+=("OK")
    elif grep -qF "$MARKER" "$inst"; then
      U_NAMES+=("$u"); U_STATES+=("DRIFT")
      note "$u: DRIFT — not what this script renders (left: the render, right: the file):"
      diff "$want" "$inst" | sed -e 's/^/      /' -e '13q'
      rank_state DRIFT
    else
      U_NAMES+=("$u"); U_STATES+=("DRIFT(foreign)")
      note "$u: DRIFT(foreign) — a unit with this name that carries no '$MARKER' line"
      rank_state 'DRIFT(foreign)'
    fi
    # A drop-in merges OVER the unit, so the RemainAfterExit trap can come back without any change to
    # the unit file at all. Content that does not touch that key is an operator override: printed, and
    # no verdict, because an exclusion wider than the trap is just blindness with a NOTE attached.
    dropin="$UNIT_DIR/$u.d"
    if [ -d "$dropin" ]; then
      if [ -n "$(grep -rlE '^[[:space:]]*RemainAfterExit' "$dropin" 2>/dev/null)" ]; then
        U_NAMES+=("$u.d"); U_STATES+=("DRIFT(drop-in)")
        note "$u.d: DRIFT(drop-in) — a drop-in sets RemainAfterExit, which makes every timer fire a no-op that reports success"
        rank_state 'DRIFT(drop-in)'
      else
        note "NOTE: $u has drop-ins in $dropin that this arm does not own — they merge over the unit, so read them before believing a fire"
      fi
    fi
  done
  if [ "$STATE" = "OK" ]; then
    REASON="in sync"
  else
    for i in "${!U_NAMES[@]}"; do
      [ "${U_STATES[i]}" = "$STATE" ] || continue
      why="$why${why:+, }${U_NAMES[i]}"
    done
    REASON="units in this state: $why"
  fi
  return 0
}

read_inputs() { assess; }

say_verdict() {
  printf 'read: dir=%s repo=%s\n' "$UNIT_DIR" "$REPO"
  printf 'exec: /bin/bash %s/scripts/harness/seat-llm-path.sh --push\n' "$REPO"
  printf '%s' "$STATE"
  [ -n "$REASON" ] && printf ': %s' "$REASON"
  printf '\n'
}

do_check() {
  say_verdict
  case "$STATE" in
    MISSING) return 1 ;;
    DRIFT|'DRIFT(foreign)'|'DRIFT(drop-in)')
             [ "$STRICT" = 1 ] && return 1; return 0 ;;
    *)       return 0 ;;
  esac
}

# enable_leg — the half that makes the pair an ARM and not two files. A unit systemd has never reloaded
# is not known to it, and a timer that is never enabled never fires, so an install that stops at the
# write is the "NOTE asking the operator for a step owned by nobody" shape this repo has been taught
# about. It prints its OWN read-back, because an exit code 0 says the call ran, not that anything is
# scheduled.
enable_leg() {
  st_guard
  if ! command -v "$SYSTEMCTL" >/dev/null 2>&1; then
    printf 'INCOMPLETE(systemctl): the unit files are in place, but no systemctl answered, so nothing was reloaded or enabled and NOTHING WILL FIRE.\n'
    printf '  → on a systemd host: sudo systemctl daemon-reload && sudo systemctl enable --now %s\n' "$TMR"
    return 1
  fi
  local out rc enabled active
  out="$("$SYSTEMCTL" daemon-reload 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then
    printf 'FAILED(reload): systemctl daemon-reload rc %s: %s\n' "$rc" "$out"
    return 1
  fi
  out="$("$SYSTEMCTL" enable --now "$TMR" 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then
    printf 'FAILED(enable): systemctl enable --now %s rc %s: %s\n' "$TMR" "$rc" "$out"
    return 1
  fi
  enabled="$("$SYSTEMCTL" is-enabled "$TMR" 2>&1)"
  active="$("$SYSTEMCTL" is-active  "$TMR" 2>&1)"
  printf 'read-back: is-enabled=%s is-active=%s\n' "${enabled%%$'\r'}" "${active%%$'\r'}"
  return 0
}

do_install() {
  local u inst want tmp ts wrote=0
  st_guard
  # A LINKED WORKTREE IS NOT A HOME FOR THIS ARM. ExecStart names $REPO by ABSOLUTE path, and a lane worktree is
  # `git worktree remove`-d the day its lane closes — the unit would then fire every 120 s into a directory that is
  # gone, which is the same silence as no timer at all. `.git` being a FILE (not a directory) is how a linked
  # worktree says so. --render and --check stay read-only and still run from anywhere; a unit installed from a
  # worktree shows up as DRIFT on the next --check from the primary tree, so the mistake is visible, not durable.
  if [ -f "$REPO/.git" ]; then
    printf 'REFUSAL(worktree): %s is a LINKED worktree — the path its ExecStart names is deleted when that lane closes.\n' "$REPO"
    printf '  → install from the PRIMARY checkout: cd <primary clone> && sudo bash scripts/harness/seat-llm-path-timer.sh --install\n'
    return 1
  fi
  # A foreign file is refused BEFORE anything is written: writing the unit this script does own and then
  # refusing the other would leave half an arm installed, which is worse than no arm at all.
  for u in "$SVC" "$TMR"; do
    inst="$UNIT_DIR/$u"
    if [ -e "$inst" ] && ! cmp -s "$inst" "$SCRATCH/$u.want" && ! grep -qF "$MARKER" "$inst"; then
      printf 'REFUSAL(foreign): %s carries no marker this script writes — it is someone else'"'"'s unit under this arm'"'"'s name.\n' "$inst"
      printf '  → rename or remove it (keep a dated .bak), then re-run: sudo bash %s --install\n' "$SELF"
      return 1
    fi
  done
  if [ ! -w "$UNIT_DIR" ]; then
    printf 'REFUSAL(not-writable): %s is not writable by this user — installing unit files and enabling a timer are root acts.\n' "$UNIT_DIR"
    printf '  → sudo bash %s --install\n' "$SELF"
    return 1
  fi
  for u in "$SVC" "$TMR"; do
    inst="$UNIT_DIR/$u"; want="$SCRATCH/$u.want"
    cmp -s "$inst" "$want" 2>/dev/null && continue
    if [ -e "$inst" ]; then
      ts="$(date -u +%Y%m%d-%H%M%S)"
      cp -p "$inst" "$inst.bak-$ts" && note "backup: $inst.bak-$ts"
    fi
    # Written beside its target and renamed in, so no reader can catch a half-written unit file:
    # `daemon-reload` reads these, and a truncated parse is a failed start rather than a warning.
    tmp="$(mktemp "$UNIT_DIR/.${u}.XXXXXX")" || { err "cannot create a temp file in $UNIT_DIR"; return 1; }
    if ! cat "$want" > "$tmp" || ! chmod 644 "$tmp" || ! mv -f "$tmp" "$inst"; then
      rm -f "$tmp"
      printf 'FAILED: %s could not be written\n' "$inst"
      return 1
    fi
    wrote=1
  done
  if [ "$wrote" = 0 ]; then
    echo "already in sync: both unit files are the render — nothing written"
  else
    echo "repaired: the unit files this script owns are now the render"
  fi
  assess
  say_verdict
  if [ "$STATE" != "OK" ]; then
    # Nothing was written and the finding stands, or something was written and did not land. The first
    # case is the drop-in: a file under <unit>.d/ is not this arm's to rewrite, so it says so and stops
    # before enabling, rather than enabling an arm the verdict just called neutered.
    if [ "$wrote" = 0 ]; then
      printf 'NOT-FIXED: nothing was written and the finding above stands — a drop-in under <unit>.d/ belongs to whoever wrote it, so edit or remove it and re-run.\n'
    else
      printf 'FAILED: the units were written but do not read back in sync\n'
    fi
    return 1
  fi
  enable_leg
}

do_render() {
  local u
  scratch
  # Rendered to a file and then cat'd, never straight to /dev/stdout: a `> /dev/stdout` redirect OPENS
  # the caller's target again and truncates it, so the second unit would erase the first — the pair
  # would render as one unit and every comparison against it would read a file nobody wrote.
  if [ -n "$RENDER_ONLY" ]; then
    render "$RENDER_ONLY" "$SCRATCH/$RENDER_ONLY" && cat "$SCRATCH/$RENDER_ONLY"
    return 0
  fi
  for u in "$SVC" "$TMR"; do
    printf '# ===== %s =====\n' "$u"
    render "$u" "$SCRATCH/$u" && cat "$SCRATCH/$u"
  done
}

# --- self-test --------------------------------------------------------------------
# A fixture unit DIRECTORY, a fixture REPO whose scripts/harness/seat-llm-path.sh stands in for the plane
# the ExecStart names, and a systemctl that is a SCRIPT recording its argv — so "the timer got enabled"
# is an arm rather than a hope, provable on a machine with no systemd at all. Both halves of every rule
# (CONVENTIONS §6): every STOP with the unpoisoned control that reads green again, every state with its
# opposite state, and no arm allowed to pass on a file the run was supposed to leave alone.
#
# A dead systemctl is reported INCOMPLETE rather than STOPPED, and that is a deliberate difference from
# seat-llm-path.sh's dead probe: a probe ANSWERS a question, so a dead one may not become a verdict;
# systemctl PERFORMS an act, so a missing one means the act did not happen, which is what INCOMPLETE says.
selftest() {
  local fails=0 pass=0 root dir plane_real want
  scratch; root="$SCRATCH"; dir="$root/units"
  mkdir -p "$root/repo/scripts/harness" "$dir"
  # The fixture plane: the ExecStart target. Arm 8 proves what happens when it is NOT there.
  printf '#!/usr/bin/env bash\n# fixture stand-in for the llm-path plane\n' \
    > "$root/repo/scripts/harness/seat-llm-path.sh"
  # The systemctl stub records every argv it was called with. Every arm points at it, and arm 8c proves
  # that an arm which FORGOT to point at it stops instead of driving the host's real systemd.
  { printf '#!/bin/sh\n'
    printf 'printf "%%s\\n" "$*" >> "%s/systemctl.log"\n' "$root"
    printf 'case "$1" in\n  is-enabled) echo enabled ;;\n  is-active)  echo active  ;;\nesac\n'
    printf 'exit 0\n'; } > "$root/stub-systemctl"
  chmod +x "$root/stub-systemctl"
  plane_real="$REPO/scripts/harness/seat-llm-path.sh"

  run() {   # run <label> <want-rc> <args…> — the fixture dir, the fixture repo, the stub systemctl
    local label="$1" want="$2"; shift 2
    local rc=0
    REPO="$root/repo" SEAT_LLM_TIMER_DIR="$dir" SEAT_LLM_TIMER_ST=1 \
      SEAT_LLM_TIMER_SYSTEMCTL="$root/stub-systemctl" \
      bash "$SELF" "$@" >"$root/out" 2>&1 || rc=$?
    if [ "$rc" = "$want" ]; then pass=$((pass + 1)); printf 'ok   %s (rc %s)\n' "$label" "$rc"
    else fails=$((fails + 1)); printf 'FAIL %s: rc %s, want %s\n' "$label" "$rc" "$want"
      sed 's/^/     | /' "$root/out" | head -8; fi
  }
  says() { if grep -qE "$2" "$root/out"; then pass=$((pass + 1)); printf 'ok   %s\n' "$1"
           else fails=$((fails + 1)); printf 'FAIL %s: output lacks /%s/\n' "$1" "$2"; sed 's/^/     | /' "$root/out" | head -6; fi; }
  equal() { if cmp -s "$1" "$2"; then pass=$((pass + 1)); printf 'ok   %s\n' "$3"
            else fails=$((fails + 1)); printf 'FAIL %s: %s and %s differ\n' "$3" "${1##*/}" "${2##*/}"; diff "$1" "$2" | head -6 | sed 's/^/     | /'; fi; }
  unchanged() { if cmp -s "$1" "$2"; then pass=$((pass + 1)); printf 'ok   %s\n' "$3"
                else fails=$((fails + 1)); printf 'FAIL %s: %s changed when it must not have\n' "$3" "$2"; diff "$1" "$2" | head -6 | sed 's/^/     | /'; fi; }
  has_line() { if grep -qE "$3" "$2"; then pass=$((pass + 1)); printf 'ok   %s\n' "$1"
               else fails=$((fails + 1)); printf 'FAIL %s: %s lacks /%s/\n' "$1" "${2##*/}" "$3"; grep -nE '^(ExecStart|Type|On|WantedBy)' "$2" | sed 's/^/     | /' | head -6; fi; }
  lacks_line() { if grep -qE "$3" "$2"; then fails=$((fails + 1)); printf 'FAIL %s: %s carries /%s/\n' "$1" "${2##*/}" "$3"
                 else pass=$((pass + 1)); printf 'ok   %s\n' "$1"; fi; }
  skip_arm() { printf 'SKIP %s (%s)\n' "$1" "$2"; }
  edit_in() { sed -e "$2" "$dir/$1" > "$dir/$1.next" && mv "$dir/$1.next" "$dir/$1"; }   # in-place without a stray .bak
  use_dir() { rm -rf "$root/$1"; mkdir -p "$root/$1"; dir="$root/$1"; log_clear; }
  run_no_systemctl() {   # the same run with NO systemctl resolving — the host that runs no systemd
    local label="$1" want="$2"; shift 2
    local rc=0
    REPO="$root/repo" SEAT_LLM_TIMER_DIR="$dir" SEAT_LLM_TIMER_ST=1 \
      SEAT_LLM_TIMER_SYSTEMCTL="$root/no-systemctl-here" \
      bash "$SELF" "$@" >"$root/out" 2>&1 || rc=$?
    if [ "$rc" = "$want" ]; then pass=$((pass + 1)); printf 'ok   %s (rc %s)\n' "$label" "$rc"
    else fails=$((fails + 1)); printf 'FAIL %s: rc %s, want %s\n' "$label" "$rc" "$want"
      sed 's/^/     | /' "$root/out" | head -8; fi
  }
  log_clear() { rm -f "$root/systemctl.log"; }
  log_has()  { if [ -f "$root/systemctl.log" ] && grep -qxF "$2" "$root/systemctl.log"; then pass=$((pass + 1)); printf 'ok   %s\n' "$1"
               else fails=$((fails + 1)); printf 'FAIL %s: systemctl was never called with [%s]\n' "$1" "$2"; fi; }
  log_empty() { if [ ! -s "$root/systemctl.log" ]; then pass=$((pass + 1)); printf 'ok   %s\n' "$1"
                else fails=$((fails + 1)); printf 'FAIL %s: systemctl was called anyway:\n' "$1"; sed 's/^/     | /' "$root/systemctl.log"; fi; }

  # 1. MISSING, and the act that ends it — the state a reimaged box is in. Both halves: absent is not OK,
  #    and after the install the very same command is.
  run "1a  no units installed is MISSING" 1 --check
  says  "1b  and the verdict names the units that are absent" 'MISSING: units in this state: seat-llm-path\.service, seat-llm-path\.timer'
  run "1c  MISSING fails without --strict too (a missing arm is not a seat state, it is no arm)" 1 --check --strict
  log_clear
  run "1d  --install writes the pair and enables the timer" 0 --install
  if [ -f "$dir/$SVC" ] && [ -f "$dir/$TMR" ]; then pass=$((pass + 1)); echo "ok   1e  both unit files are in the unit dir"
  else fails=$((fails + 1)); echo "FAIL 1e  a unit file is absent after --install"; ls -a "$dir" | sed 's/^/     | /'; fi
  log_has "1f  the install reloaded systemd (a unit systemd has never read cannot fire)" 'daemon-reload'
  log_has "1g  and enabled --now the TIMER (a written unit that is never enabled is an arm that never fires)" "enable --now $TMR"
  says  "1h  and printed its own read-back, because rc 0 says the call ran, not that anything is scheduled" 'read-back: is-enabled=enabled is-active=active'
  run "1i  control: the same command now reads OK" 0 --check --strict

  # 2. RENDER vs INSTALLED, byte for byte: `OK` claims equality, so the claim is compared, not asserted.
  REPO="$root/repo" bash "$SELF" --render "$SVC" > "$root/want-service" 2>&1
  REPO="$root/repo" bash "$SELF" --render "$TMR" > "$root/want-timer"  2>&1
  equal "$root/want-service" "$dir/$SVC" "2a  the installed .service is BYTE-equal to what --render prints"
  equal "$root/want-timer"  "$dir/$TMR" "2b  the installed .timer is BYTE-equal to what --render prints"
  cp -p "$dir/$SVC" "$root/service.snap"
  run "2c  --install twice writes nothing" 0 --install
  says  "2d  and says so" 'already in sync'
  equal "$root/service.snap" "$dir/$SVC" "2e  installing twice lands the same bytes (an arm that rewrote its own units every fire would never read OK)"

  # 3. DRIFT by a moved value — the cadence is the value most likely to be tuned in the wrong file.
  edit_in "$TMR" 's/^OnUnitActiveSec=120s$/OnUnitActiveSec=180s/'
  run "3a  a hand-moved cadence is report-only in plain --check" 0 --check
  says  "3b  and it is reported as DRIFT, naming the file" "^  seat-llm-path\.timer: DRIFT"
  run "3c  the same file is a FAILURE under --strict" 1 --check --strict
  run "3d  --install repairs it" 0 --install
  equal "$root/want-timer" "$dir/$TMR" "3e  and the timer is the render again"
  if ls "$dir" | grep -q "^$TMR\.bak-[0-9]"; then pass=$((pass + 1)); echo "ok   3f  the replaced unit kept a dated .bak- beside it"
  else fails=$((fails + 1)); echo "FAIL 3f  a unit file was replaced with no backup"; ls -a "$dir" | sed 's/^/     | /'; fi
  run "3g  control: OK after the repair" 0 --check --strict

  # 4. WHAT THE UNIT CALLS — the repo path, and the unowned copy it must never call.
  has_line "4a  the rendered ExecStart runs the PLANE's push half" "$root/want-service" '^ExecStart=/bin/bash .*/scripts/harness/seat-llm-path\.sh --push$'
  has_line "4b  the installed ExecStart calls the same push half"  "$dir/$SVC"          '^ExecStart=/bin/bash .*/scripts/harness/seat-llm-path\.sh --push$'
  has_line "4c  and it names the repo the install ran from"        "$dir/$SVC"          "^ExecStart=/bin/bash $root/repo/scripts/harness/seat-llm-path\\.sh --push\$"
  if [ -f "$root/repo/scripts/harness/seat-llm-path.sh" ]; then pass=$((pass + 1)); echo "ok   4d  the path the ExecStart names is a file that exists"
  else fails=$((fails + 1)); echo "FAIL 4d  the ExecStart names a script that is not there"; fi
  edit_in "$SVC" 's|^ExecStart=.*|ExecStart=/bin/bash /usr/local/sbin/seat-llm-path.sh --push|'
  run "4e  an ExecStart aimed at an unowned copy under /usr/local/sbin is DRIFT under --strict" 1 --check --strict
  says  "4f  and it reads as drift, not as a missing arm" "^  seat-llm-path\.service: DRIFT"
  run "4g  --install pulls it back into the repo" 0 --install
  has_line "4h  and the ExecStart names the repo clone again" "$dir/$SVC" "^ExecStart=/bin/bash $root/repo/scripts/harness/seat-llm-path\\.sh --push\$"
  lacks_line "4i  no /usr/local/sbin path survives the repair in an ExecStart (an unowned copy is what no converge reaches)" "$dir/$SVC" '^ExecStart=.*usr/local/sbin'
  lacks_line "4j  and the render never names a copy outside the repo either" "$root/want-service" '^ExecStart=.*usr/local/sbin'

  # 5. THE TRAP: Type=oneshot, and RemainAfterExit nowhere near it. A comment MAY name the key (that is
  #    what the rendered comment is for); a line that SETS it is the defect, so the rule is the key form.
  has_line  "5a  the rendered service is Type=oneshot" "$root/want-service" '^Type=oneshot$'
  lacks_line "5b  and renders no RemainAfterExit setting (with it the unit stays active(exited) and every timer fire is a no-op that reports success)" "$root/want-service" '^[[:space:]]*RemainAfterExit'
  has_line  "5c  the timer carries the boot-time fire, 10 s after the distro start that regenerates the file" "$root/want-timer" '^OnBootSec=10s$'
  has_line  "5d  and the 120 s re-assert interval, the route timer's shape" "$root/want-timer" '^OnUnitActiveSec=120s$'
  has_line  "5e  and it is wanted by timers.target" "$root/want-timer" '^WantedBy=timers.target$'
  printf '%s\n' '' '[Service]' 'RemainAfterExit=yes' >> "$dir/$SVC"
  run "5f  a hand-added RemainAfterExit is DRIFT under --strict" 1 --check --strict
  says  "5g  and the finding names the file that moved it" "^  seat-llm-path\.service: DRIFT"
  run "5h  --install removes it" 0 --install
  lacks_line "5i  the trap does not survive the repair" "$dir/$SVC" '^[[:space:]]*RemainAfterExit'
  mkdir -p "$dir/$SVC.d"
  printf '[Service]\nNice=10\n' > "$dir/$SVC.d/operator.conf"
  run "5j  a drop-in that does not touch the trap stays outside the verdict" 0 --check --strict
  says  "5k  and it is printed as a NOTE, because a drop-in merges over the unit" 'NOTE: .*drop-ins'
  printf '[Service]\nRemainAfterExit=yes\n' > "$dir/$SVC.d/trap.conf"
  run "5l  a drop-in that SETS RemainAfterExit is the verdict: the trap through the side door" 1 --check --strict
  says  "5m  and it is named as the drop-in rather than as file drift" 'DRIFT\(drop-in\)'
  log_clear
  run "5n  --install will not enable an arm it just called neutered" 1 --install
  says  "5o  and it says the finding is not its own to fix" 'NOT-FIXED'
  log_empty "5p  a refused install enables nothing"
  rm -rf "$dir/$SVC.d"
  run "5q  control: with the drop-in gone the arm reads OK again" 0 --check --strict

  # 6. A FOREIGN unit file: refused, with the bytes proven untouched and NO half arm written.
  rm -rf "$dir"; mkdir -p "$dir"
  printf '[Unit]\nDescription=someone else unit under this arm name\n\n[Service]\nType=simple\nExecStart=/bin/true\n' > "$dir/$SVC"
  cp -p "$dir/$SVC" "$root/foreign-before"
  run "6a  a unit file this script did not write is DRIFT(foreign)" 1 --check --strict
  says  "6b  and the verdict names it foreign rather than drift" 'DRIFT\(foreign\)'
  log_clear
  run "6c  --install REFUSES it" 1 --install
  says  "6d  and the refusal says what it is" 'REFUSAL\(foreign\)'
  unchanged "$root/foreign-before" "$dir/$SVC" "6e  the refusal left the foreign unit byte-identical"
  if [ -e "$dir/$TMR" ]; then fails=$((fails + 1)); echo "FAIL 6f  the refusal wrote the OTHER unit too — half an installed arm is a state no later verdict can describe"
  else pass=$((pass + 1)); echo "ok   6f  nothing at all was written: no half-installed arm"; fi
  log_empty "6g  and a refused install tells systemd nothing"
  rm -f "$dir/$SVC"
  run "6h  control: with the foreign file gone the pair installs" 0 --install
  run "6i  and it reads OK" 0 --check --strict

  # 7. The boundaries. Each is an environment edge, so it prints a named state rather than a verdict,
  #    and the mode-dependent ones print SKIP when the mode does not bind (an environment boundary is
  #    never a green).
  use_dir nosystemd
  SEAT_LLM_SYSTEMCTL_MISSING=1 run_no_systemctl "7a  with no systemctl answering, the install is INCOMPLETE" 1 --install
  says  "7b  and the line says plainly that nothing will fire" 'INCOMPLETE\(systemctl\)'
  run     "7c  control: the unit files really did land, so the write half succeeded and only the arm failed" 0 --check --strict
  if [ "$(id -u)" = 0 ]; then
    skip_arm "7d  an unwritable unit dir REFUSES instead of pretending" "running as root, file modes do not bind"
    skip_arm "7e  an unreadable unit file is a STOP, not a verdict" "running as root, file modes do not bind"
  else
    use_dir unwritable
    chmod 555 "$dir"
    run     "7d  an unwritable unit dir REFUSES, it does not pretend" 1 --install
    says    "7e  and the refusal prints the exact sudo command" 'sudo bash .*/scripts/harness/seat-llm-path-timer\.sh --install'
    if [ -z "$(ls -A "$dir")" ]; then pass=$((pass + 1)); echo "ok   7f  the refusal wrote nothing"
    else fails=$((fails + 1)); echo "FAIL 7f  the refusal wrote into a directory it cannot write"; ls -a "$dir" | sed 's/^/     | /'; fi
    chmod 755 "$dir"
    run     "7g  control: writable again, the install lands" 0 --install
    chmod 000 "$dir/$SVC"
    run     "7h  an unreadable unit file is a STOP, not a verdict" 2 --check
    says    "7i  and it says FATAL rather than guessing a state" '^FATAL'
    chmod 644 "$dir/$SVC"
    run     "7j  control: readable again, it answers" 0 --check --strict
  fi
  REPO="$root/repo" SEAT_LLM_TIMER_DIR="$root/never-made" SEAT_LLM_TIMER_ST=1 \
    SEAT_LLM_TIMER_SYSTEMCTL="$root/stub-systemctl" bash "$SELF" --check >"$root/out" 2>&1; rc=$?
  if [ "$rc" = 2 ] && grep -q '^FATAL' "$root/out"; then pass=$((pass + 1)); echo "ok   7k  no unit directory is a STOP, never MISSING (a directory nobody can read answers nothing)"
  else fails=$((fails + 1)); printf 'FAIL 7k a missing unit dir answered rc %s\n' "$rc"; sed 's/^/     | /' "$root/out" | head -4; fi
  use_dir nodir-control
  run     "7l  control: the same install against a directory that exists completes" 0 --install

  # 8. The STOPs, each with the byte-identical control that reads green again.
  mv "$root/repo/scripts/harness/seat-llm-path.sh" "$root/plane.moved"
  use_dir stopped
  run     "8a  a unit whose ExecStart names a script the repo does not have is a STOP" 2 --check
  says    "8b  and it says so rather than reporting two files in sync" '^FATAL'
  run     "8c  and --install stops too, before writing anything" 2 --install
  if [ -e "$dir/$SVC" ] || [ -e "$dir/$TMR" ]; then fails=$((fails + 1)); echo "FAIL 8d  the STOP wrote a unit for a plane that is not here"
  else pass=$((pass + 1)); echo "ok   8d  nothing was installed for a plane the repo does not carry"; fi
  mv "$root/plane.moved" "$root/repo/scripts/harness/seat-llm-path.sh"
  run     "8e  control: the unpoisoned repo installs again" 0 --install
  run     "8f  and reads OK" 0 --check --strict

  # 9. The self-test's own belt: a fixture arm that FORGOT the systemctl stub must stop rather than
  #    drive the host's real systemd. Without this arm, every arm above would be trusting the next one.
  use_dir guard
  REPO="$root/repo" SEAT_LLM_TIMER_DIR="$dir" SEAT_LLM_TIMER_ST=1 \
    bash "$SELF" --install >"$root/out" 2>&1; rc=$?
  if [ "$rc" = 2 ] && grep -q 'no systemctl stub' "$root/out"; then pass=$((pass + 1)); echo "ok   9a  a fixture run with no systemctl stub stops before it touches anything"
  else fails=$((fails + 1)); printf 'FAIL 9a the self-test guard did not fire (rc %s)\n' "$rc"; sed 's/^/     | /' "$root/out" | head -4; fi
  if [ -e "$dir/$SVC" ] || [ -e "$dir/$TMR" ]; then fails=$((fails + 1)); echo "FAIL 9b  the guarded run wrote a unit file anyway"
  else pass=$((pass + 1)); echo "ok   9b  and it wrote nothing"; fi

  # 10. THE REPO CARRIER — the arm that makes this more than one box's state. The render is asked of THIS
  #     checkout, with no fixture override: what a reimaged box gets is what this tree carries, and the
  #     ExecStart it carries names a file that is IN the tree.
  bash "$SELF" --render > "$root/render-this-checkout" 2>&1; rc=$?
  if [ "$rc" = 0 ]; then pass=$((pass + 1)); echo "ok   10a this checkout renders the pair with no fixture in the way"
  else fails=$((fails + 1)); printf 'FAIL 10a --render on this checkout rc %s\n' "$rc"; sed 's/^/     | /' "$root/render-this-checkout" | head -6; fi
  has_line "10b the render this checkout carries names the plane that lives in this checkout" \
    "$root/render-this-checkout" "^ExecStart=/bin/bash $REPO/scripts/harness/seat-llm-path\\.sh --push\$"
  if [ -f "$plane_real" ]; then pass=$((pass + 1)); echo "ok   10c and that script is tracked here, so a reimaged box gets the arm with the clone"
  else fails=$((fails + 1)); echo "FAIL 10c the ExecStart names $plane_real, which is not in this tree"; fi
  lacks_line "10d this checkout renders no copy of the plane outside the repo" "$root/render-this-checkout" '^ExecStart=.*usr/local/sbin'
  has_line "10e both rendered units carry the marker that makes them nameable as ours" \
    "$root/render-this-checkout" '^# managed-by: homelab llm-path re-assert arm'

  # 11. THE PATH THAT OUTLIVES NOTHING — an install from a LINKED worktree is refused. The ExecStart names $REPO
  #     by absolute path, and `git worktree remove` deletes a lane worktree when its lane closes: a timer firing
  #     into a removed directory is silence, the failure this arm exists to prevent.
  mkdir -p "$root/wt/scripts/harness" "$root/wt-dir"
  : > "$root/wt/.git"                       # a linked worktree says so with a .git FILE, not a directory
  cp "$plane_real" "$root/wt/scripts/harness/seat-llm-path.sh"
  REPO="$root/wt" SEAT_LLM_TIMER_DIR="$root/wt-dir" SEAT_LLM_TIMER_ST=1 \
    SEAT_LLM_TIMER_SYSTEMCTL="$root/stub-systemctl" bash "$SELF" --install >"$root/out" 2>&1; rc=$?
  if [ "$rc" = 1 ] && grep -q 'REFUSAL(worktree)' "$root/out"; then pass=$((pass + 1)); echo "ok   11a installing from a linked worktree is REFUSED"
  else fails=$((fails + 1)); printf 'FAIL 11a the worktree install answered rc %s, want 1 with a refusal\n' "$rc"; sed 's/^/     | /' "$root/out" | head -4; fi
  if [ -e "$root/wt-dir/$SVC" ] || [ -e "$root/wt-dir/$TMR" ]; then fails=$((fails + 1)); echo "FAIL 11b the refused worktree install wrote units anyway"
  else pass=$((pass + 1)); echo "ok   11b and it wrote nothing into that tree"; fi
  REPO="$root/wt" SEAT_LLM_TIMER_DIR="$root/wt-dir" SEAT_LLM_TIMER_ST=1 \
    SEAT_LLM_TIMER_SYSTEMCTL="$root/stub-systemctl" bash "$SELF" --check >"$root/out" 2>&1; rc=$?
  if [ "$rc" = 1 ] && grep -q 'MISSING' "$root/out"; then pass=$((pass + 1)); echo "ok   11c --check still reports from a worktree (it writes nothing, so it needs no home)"
  else fails=$((fails + 1)); printf 'FAIL 11c --check from a worktree answered rc %s\n' "$rc"; sed 's/^/     | /' "$root/out" | head -4; fi

  printf '\nself-test: %s (%d passed, %d failed)\n' \
    "$([ "$fails" -eq 0 ] && echo OK || echo FAILED)" "$pass" "$fails"
  [ "$fails" -eq 0 ]
}

# --- dispatch ---------------------------------------------------------------------
case "$MODE" in
  selftest) selftest; exit $? ;;
  render)   do_render; exit $? ;;
esac
scratch
read_inputs
case "$MODE" in
  install) do_install ;;
  *)       do_check  ;;
esac
exit $?
