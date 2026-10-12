#!/usr/bin/env bash
# =====================================================================
# lib/pi-seat.sh — the seat helpers (HD-1118 Stage 1: ONE pin(), not five)
# ---------------------------------------------------------------------
# WHY: `pin()` existed five times over, byte-identical
# (install-pi-debian.sh, pi-self-update.sh, install-nerd-font.sh,
# pi-settings-config.sh, install-pi-wsl.sh), and every copy carried the defect
# HD-1115 recorded: the value is fetched with `X="$(pin k)"`, and `exit 1` inside
# a `$( )` subshell stops NOTHING but the subshell. On the three scripts that have
# no `set -e` (pi-self-update.sh, install-nerd-font.sh, pi-settings-config.sh) a
# missing pin therefore continued with an EMPTY value — which is how a version
# pin becomes a blank string in an installer rather than a stop.
#
# FIX: the out-parameter form. `pin VAR KEY` runs in the CALLER's shell, so the
# fail-loud `exit 1` is the caller's own exit and works whether or not the script
# uses `set -e`. Nothing here is fetched through a command substitution, so there
# is no subshell to swallow it. (§7: fail-loud, never `default('')`/inline default.)
#
# USE:  hl_source_lib "${BASH_SOURCE[0]}" pi-seat.sh    # after repo-root.sh
#       pin PI_VERSION pi_host_npm_version
#
# SELF-TEST: bash scripts/lib/pi-seat.sh --self-test
#   Both halves, per CONVENTIONS §6 ("a test that cannot fail is not evidence"):
#   a missing pin must STOP the caller, and a present pin must return the value.
# =====================================================================

# pin <var> <key> — set <var> from the versions SSOT; a missing pin STOPS the caller.
pin() {
  local __out="${1:?pin: needs an output variable}" __key="${2:?pin: needs a pin key}" __v=""
  if [ -z "${VERSIONS:-}" ]; then
    VERSIONS="${REPO:?pin: neither VERSIONS nor REPO is set}/IaC/ansible/group_vars/all/versions.yml"
  fi
  if [ ! -f "$VERSIONS" ]; then
    printf 'FATAL: pin: no versions file at %s (§7)\n' "$VERSIONS" >&2
    exit 1
  fi
  __v="$(grep -E "^${__key}:" "$VERSIONS" 2>/dev/null | head -1 | sed -E 's/^[^:]+:[[:space:]]*"?([^"#]*)"?.*/\1/' | tr -d '[:space:]')"
  if [ -z "$__v" ]; then
    printf 'FATAL: pin %s missing from %s — add it there, do not hardcode it here (§7)\n' \
      "$__key" "$VERSIONS" >&2
    exit 1
  fi
  printf -v "$__out" '%s' "$__v"
}

# hl_seat_registry_path — locate lib/seat-planes.yml from this helper's own location.
hl_seat_registry_path() { printf '%s' "$(dirname "$_HL_PIN_SELF")/seat-planes.yml"; }

# hl_owner_path <file-name> — resolve a plane owner by NAME under scripts/, printed
# repo-relative. By name, so this registry never becomes a second copy of the tree: when
# HD-1118 Stage 3 moved these owners into folders (pi-self-update.sh is harness/ now); resolving by
# name means the registry never had to learn about the move.
hl_owner_path() {
  local _want="${1:?hl_owner_path: needs a file name}" _hit
  _hit="$(find "${REPO:-.}/scripts" -type f -name "$_want" -not -path '*/testdata/*' 2>/dev/null | head -1)"
  [ -n "$_hit" ] || return 1
  printf '%s' "${_hit#"${REPO:-.}/"}"
}

# seat_planes <selector> <mode> — emit `plane<TAB>argv` lines, one per applicable record.
#   selector  a seat name (win11|wsl|oldsrv) with mode driver,
#             an installer key (debian|wsl) with mode installer-check|installer-push
# The argv is built from the record's runner + owner + the mode's arguments, so the plane
# set and the command that runs it come from ONE place (the divergence that this file
# exists to remove).
seat_planes() {
  local _sel="${1:?seat_planes: needs a seat or installer key}" _mode="${2:-check}" _f _line _key _val
  _f="${HL_REGISTRY:-$(hl_seat_registry_path)}"
  [ -f "$_f" ] || { printf 'FATAL: no plane registry at %s (HD-1118 Stage 2)\n' "$_f" >&2; return 1; }
  local plane="" harness="" owner="" runner="" ccheck="" cinst="" cpush="" seats="" installer="" key="" val=""
  while IFS= read -r _line || [ -n "${_line:-}" ]; do
    case "$_line" in
      '---')
        if [ -n "$owner" ]; then
          seat_planes_emit "$plane" "$owner" "$runner" "$_mode" "$ccheck" "$cinst" "$cpush" "$seats" "$installer" "$_sel"
        fi
        plane=""; harness=""; owner=""; runner=""; ccheck=""; cinst=""; cpush=""; seats=""; installer=""
        continue ;;
      ''|'#'*) continue ;;
    esac
    key="${_line%%:*}"; val="${_line#*:}"
    val="${val#"${val%%[![:space:]]*}"}"
    case "$key" in
      plane) plane="$val" ;; harness) harness="$val" ;; owner) owner="$val" ;;
      runner) runner="$val" ;; check) ccheck="$val" ;; install_check) cinst="$val" ;;
      push) cpush="$val" ;; seats) seats="$val" ;; installer) installer="$val" ;;
      *) printf 'FATAL: seat-planes.yml: unknown key %s: (a reader that guesses is worse than one that stops)\n' "$key" >&2; return 1 ;;
    esac
  done < "$_f"
  if [ -n "$owner" ]; then
    seat_planes_emit "$plane" "$owner" "$runner" "$_mode" "$ccheck" "$cinst" "$cpush" "$seats" "$installer" "$_sel"
  fi
}

# seat_planes_emit — the applicability test + the argv, kept in one place so the reader's
# last record and every middle record go through the same code path.
seat_planes_emit() {
  local plane="$1" owner="$2" runner="$3" mode="$4" ccheck="$5" cinst="$6" cpush="$7" seats="$8" installer="$9" sel="${10}"
  local args path
  # check/push select on SEATS (what the fan-out asks); installer-check/installer-push select
  # on INSTALLER (what a from-zero bootstrap converges). One record answers both halves, which
  # is the whole point: the set that converges a seat and the set that CHECKS it cannot diverge.
  case "$mode" in
    check)           args="$ccheck";           case " $seats "    in *" $sel "*) : ;; *) return 0 ;; esac ;;
    push)            args="$cpush";            case " $seats "    in *" $sel "*) : ;; *) return 0 ;; esac ;;
    installer-check) args="${cinst:-$ccheck}"; case " $installer " in *" $sel "*) : ;; *) return 0 ;; esac ;;
    installer-push)  args="$cpush";            case " $installer " in *" $sel "*) : ;; *) return 0 ;; esac ;;
    *) printf 'FATAL: seat_planes: unknown mode %s\n' "$mode" >&2; return 1 ;;
  esac
  [ -n "$args" ] || { printf 'FATAL: seat-planes.yml: plane %s has no %s arguments\n' "$plane" "$mode" >&2; return 1; }
  path="$(hl_owner_path "$owner")" || { printf 'FATAL: seat-planes.yml: plane %s names owner %s, which is not under scripts/ (a plane whose owner moved is a plane that silently stops running)\n' "$plane" "$owner" >&2; return 1; }
  # The driver runs these ON a seat with the seat's repo as cwd (relative is correct there);
  # an installer runs them from wherever the operator typed the command, and sets
  # HL_REPO_PREFIX="$REPO/" so the same registry line still names a real file.
  path="${HL_REPO_PREFIX:-}${path}"
  case "$runner" in
    bash)       printf '%s\t%s %s %s\n' "$plane" bash "$path" "$args" ;;
    python3)    printf '%s\t%s %s %s\n' "$plane" python3 "$path" "$args" ;;
    powershell) printf '%s\tpowershell.exe -NoProfile -ExecutionPolicy Bypass -File %s %s\n' "$plane" "$path" "$args" ;;
    *) printf 'FATAL: seat-planes.yml: plane %s has unknown runner %s\n' "$plane" "$runner" >&2; return 1 ;;
  esac
}

# hl_planes_selftest — the registry reader's arms. Returns arms NOT caught.
hl_planes_selftest() {
  local fails=0 _t _n _miss
  _t="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$_t'" RETURN

  # 1. the real registry parses and carries the plane set (the corpus ratchet: a truncated
  #    or unparseable file must not read as "this seat has no planes to check").
  _n="$(seat_planes oldsrv check 2>/dev/null | cut -f1 | sort -u | wc -l)"
  if [ "$_n" -ge 8 ]; then
    printf 'ok: registry parses — %s planes for the oldsrv seat\n' "$_n"
  else
    printf 'NOT CAUGHT: only %s planes read from the registry\n' "$_n"; fails=$((fails + 1))
  fi

  # 2. THE DEFECT THIS FILE EXISTS FOR: the installer's CHECK half must include every plane
  #    its PUSH half runs — tmux was the one it never checked (HD-1085's tail, HD-1118 Stage 2).
  _miss="$(seat_planes debian installer-check 2>/dev/null | cut -f2 | grep -c 'install-tmux-conf.sh')"
  if [ "$_miss" -ge 1 ]; then
    printf 'ok: the installer check half runs the tmux plane\n'
  else
    printf 'NOT CAUGHT: install-pi-debian --check would still skip the tmux plane\n'; fails=$((fails + 1))
  fi

  # 3. a plane an installer converges must be a plane some seat reports, or the fan-out
  #    would go on reporting green while the bootstrap wrote the file.
  local s p seen
  for s in debian cockpit wsl; do
    while IFS=$'\t' read -r p _; do
      seen=0
      for _seat in win11 wsl oldsrv; do
        seat_planes "$_seat" check 2>/dev/null | cut -f1 | grep -qx "$p" && seen=1
      done
      [ "$seen" = 1 ] || { printf 'NOT CAUGHT: installer %s converges plane %s, which no seat reports\n' "$s" "$p"; fails=$((fails + 1)); }
    done < <(seat_planes "$s" installer-push 2>/dev/null)
  done
  [ "$fails" -eq 0 ] && printf 'ok: every installer plane is reported by a seat\n'

  # 4. canaries: an owner that does not exist, and an unknown key, must be LOUD — a reader
  #    that shrugs at either is how a plane disappears from every seat at once.
  local f_self="$_HL_PIN_SELF"
  mkdir -p "$_t/lib" "$_t/scripts"
  : >"$_t/$(printf scripts)/x.sh"   # folder in a command substitution: see the acceptance-grep note in repo-root.sh
  for _case in missing-owner unknown-key; do
    case "$_case" in
      missing-owner) printf '%s\n' '---' 'plane: ghost' 'harness: pi' 'owner: not-a-real-script.sh' \
                            'runner: bash' 'check: --check' 'push: --push' 'seats: oldsrv' 'installer: debian' >"$_t/registry.yml" ;;
      unknown-key)   printf '%s\n' '---' 'plane: skills' 'harness: pi' 'owner: x.sh' 'runer: bash' \
                            'check: --check' 'push: --push' 'seats: oldsrv' 'installer: debian' >"$_t/registry.yml" ;;
    esac
    if HL_REGISTRY="$_t/registry.yml" REPO="$_t" bash -c \
         '. "'"$f_self"'"; seat_planes oldsrv check' >/dev/null 2>&1; then
      printf 'NOT CAUGHT: registry case %s was accepted\n' "$_case"; fails=$((fails + 1))
    else
      printf 'ok: registry case %s fails loud\n' "$_case"
    fi
  done

  [ "$fails" -eq 0 ] || printf 'seat-planes self-test: %s arm(s) NOT caught\n' "$fails" >&2
  return "$fails"
}

# seat_pkg_val <key> <versions.yml> — one scalar out of the version SSOT, no YAML parser needed
# in the seat path (the same trick pin() uses; a reader that needs a venv on a bare seat is a
# reader that fails on exactly the machine that is being bootstrapped).
seat_pkg_val() {
  sed -n "s/^$1: *\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*#.*/\1/p; s/^$1: *\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*$/\1/p" "${2:-${VERSIONS:-}}" | head -1
}

# seat_pkg_rows [versions.yml] — emit `name|spec|scope` for every pi package the repo carries.
# DISCOVERED from pi_pkg_*_name keys, so the inventory lives in versions.yml and NOT in a copy
# inside a script: adding a fleet package is one row there, and every seat gets it. Before this,
# four fleet packages lived only as an unversioned `pi install` list inside install-pi-wsl.sh,
# which is how npm:pi-subagents — the thing that RUNS sessions — reached other seats only when a
# session happened to hand-install it.
seat_pkg_rows() {
  local _f="${1:-${VERSIONS:-${REPO:-.}/IaC/ansible/group_vars/all/versions.yml}}" id name scope ver vpin mutable n=0
  [ -f "$_f" ] || { printf 'FATAL: no version SSOT at %s — an inventory that cannot be read is not an empty one\n' "$_f" >&2; return 1; }
  for id in $(sed -n 's/^pi_pkg_\([a-z0-9_]*\)_name:.*/\1/p' "$_f" | sort -u); do
    name="$(seat_pkg_val "pi_pkg_${id}_name" "$_f")"
    scope="$(seat_pkg_val "pi_pkg_${id}_scope" "$_f")"
    ver="$(seat_pkg_val "pi_pkg_${id}_version" "$_f")"
    vpin="$(seat_pkg_val "pi_pkg_${id}_version_pin" "$_f")"
    mutable="$(seat_pkg_val "pi_pkg_${id}_mutable" "$_f")"
    [ -n "$name" ] || { printf 'FATAL: pi_pkg_%s has no _name — a row that names nothing is a row that installs nothing\n' "$id" >&2; return 1; }
    [ -n "$scope" ] || { printf 'FATAL: package %s has no scope — fleet or seat is exactly the question that got asked too late for pi-subagents\n' "$name" >&2; return 1; }
    if [ -n "$vpin" ]; then
      ver="$(seat_pkg_val "$vpin" "$_f")"
      [ -n "$ver" ] || { printf 'FATAL: package %s points at pin %s, which has no value\n' "$name" "$vpin" >&2; return 1; }
    fi
    if [ "$mutable" != "true" ] && [ -z "$ver" ]; then
      printf 'FATAL: package %s has no version and no version_pin (CONVENTIONS §7: a package without a version is a package that changes on its own)\n' "$name" >&2; return 1
    fi
    n=$((n + 1))
    if [ "$mutable" = "true" ]; then
      printf '%s\tnpm:%s\t%s\n' "$name" "$name" "$scope"
    else
      printf '%s\tnpm:%s@%s\t%s\n' "$name" "$name" "$ver" "$scope"
    fi
  done
  [ "$n" -ge 1 ] || { printf 'FATAL: the version SSOT carries ZERO packages (%s) — an empty inventory here means the reader broke, not that the fleet has no packages\n' "$_f" >&2; return 1; }
}

# hl_pkg_selftest — the inventory's arms. Returns arms NOT caught.
hl_pkg_selftest() {
  local fails=0 _t n fleet hit
  _t="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$_t'" RETURN

  # 1. corpus: the real SSOT yields rows, and the FLEET half is not empty.
  n="$(seat_pkg_rows 2>/dev/null | wc -l)"
  fleet="$(seat_pkg_rows 2>/dev/null | awk -F'\t' '$3=="fleet"' | wc -l)"
  if [ "$n" -ge 6 ] && [ "$fleet" -ge 5 ]; then
    printf 'ok: package inventory reads — %s rows, %s fleet\n' "$n" "$fleet"
  else
    printf 'NOT CAUGHT: inventory read %s rows / %s fleet\n' "$n" "$fleet"; fails=$((fails + 1))
  fi

  # 2. THE DEFECT: pi-subagents is fleet infrastructure, not something a session installs by hand.
  hit="$(seat_pkg_rows 2>/dev/null | awk -F'\t' '$1=="pi-subagents" && $3=="fleet"' | head -1)"
  if [ -n "$hit" ]; then
    printf 'ok: pi-subagents is declared fleet (%s)\n' "$hit"
  else
    printf 'NOT CAUGHT: pi-subagents is not a fleet package — seats will keep getting it by hand\n'; fails=$((fails + 1))
  fi

  # 3. canary: an unversioned row fails loud — §7's rule, enforced by the reader, not by review.
  printf 'pi_pkg_ghost_name: "ghost-pkg"\npi_pkg_ghost_scope: "fleet"\n' >"$_t/versions.yml"
  if seat_pkg_rows "$_t/versions.yml" >/dev/null 2>&1; then
    printf 'NOT CAUGHT: an unversioned package row was accepted\n'; fails=$((fails + 1))
  else
    printf 'ok: an unversioned package row fails loud\n'
  fi

  # 4. canary: a missing SSOT is a stop, never "no packages, carry on".
  if seat_pkg_rows "$_t/nope.yml" >/dev/null 2>&1; then
    printf 'NOT CAUGHT: a missing version SSOT read as an empty inventory\n'; fails=$((fails + 1))
  else
    printf 'ok: a missing version SSOT fails loud\n'
  fi

  # 5. canary: a row without scope — the exact question this section exists to answer.
  printf 'pi_pkg_x_name: "x"\npi_pkg_x_version: "1.0"\n' >"$_t/versions.yml"
  if seat_pkg_rows "$_t/versions.yml" >/dev/null 2>&1; then
    printf 'NOT CAUGHT: a scope-less package row was accepted\n'; fails=$((fails + 1))
  else
    printf 'ok: a scope-less package row fails loud\n'
  fi

  [ "$fails" -eq 0 ] || printf 'package inventory self-test: %s arm(s) NOT caught\n' "$fails" >&2
  return "$fails"
}

# hl_pin_selftest — returns the number of arms NOT caught.
hl_pin_selftest() {
  local fails=0 _t _out _rc
  _t="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$_t'" RETURN
  mkdir -p "$_t/lib"
  cp "$_HL_PIN_SELF" "$_t/lib/pi-seat.sh"
  printf 'the_pin: "9.9.9"  # fixture\n' >"$_t/versions.yml"

  # Half 1 (the defect): a missing pin must stop the caller — and the caller below
  # deliberately has NO `set -e`, because that is the shape that used to continue.
  printf '#!/usr/bin/env bash\nVERSIONS="%s/versions.yml"\n. "%s/lib/pi-seat.sh"\npin OUT not_a_pin\nprintf "REACHED-AFTER-MISSING-PIN\\n"\n' "$_t" "$_t" >"$_t/missing.sh"
  _out="$(bash "$_t/missing.sh" 2>&1)"; _rc=$?
  if [ "$_rc" -ne 0 ] && ! printf '%s' "$_out" | grep -q "REACHED-AFTER-MISSING-PIN"; then
    printf 'ok: a missing pin stops the caller (rc %s)\n' "$_rc"
  else
    printf 'NOT CAUGHT: the caller survived a missing pin (rc %s): %s\n' "$_rc" "$_out"
    fails=$((fails + 1))
  fi

  # Half 2: a present pin returns the value, into the named variable.
  printf '#!/usr/bin/env bash\nVERSIONS="%s/versions.yml"\n. "%s/lib/pi-seat.sh"\npin OUT the_pin\nprintf "%%s\\n" "$OUT"\n' "$_t" "$_t" >"$_t/present.sh"
  _out="$(bash "$_t/present.sh" 2>&1)"
  if [ "$_out" = "9.9.9" ]; then
    printf 'ok: a present pin returns the pinned value\n'
  else
    printf 'NOT CAUGHT: present pin gave %s (want 9.9.9)\n' "$_out"
    fails=$((fails + 1))
  fi

  # Half 3: the old shape must stay gone — `$(pin ...)` may not come back, because
  # in that shape a missing pin cannot stop anything.
  if grep -RElq '^[^#]*\$\(pin ' --include='*.sh' --exclude='pi-seat.sh' \
       "$(dirname "$(dirname "$_HL_PIN_SELF")")" 2>/dev/null; then
    printf 'NOT CAUGHT: a $(pin ...) call site is still live (HD-1115 shape)\n'
    fails=$((fails + 1))
  else
    printf 'ok: no $(pin ...) call site remains\n'
  fi

  [ "$fails" -eq 0 ] || printf 'pi-seat self-test: %s arm(s) NOT caught\n' "$fails" >&2
  return "$fails"
}

_HL_PIN_SELF="${BASH_SOURCE[0]}"

if [ "${1:-}" = "--self-test" ] && [ -z "${BASH_SOURCE[1]:-}" ]; then
  _rc=0
  hl_pin_selftest || _rc=1
  hl_planes_selftest || _rc=1
  hl_pkg_selftest || _rc=1
  exit "$_rc"
fi
