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
# FAST (HD-1135): versions.yml is parsed ONCE per process into a cache, so a pin() costs zero
#   execs, and a plane owner is resolved by ONE directory walk per process, not one `find` per
#   plane. The verdicts are unchanged — the cache is a different WAY to evaluate the same
#   assertion, never a weaker one (see the cache sections below and the self-test arms).
#
# SELF-TEST: bash scripts/lib/pi-seat.sh --self-test
#   Both halves, per CONVENTIONS §6 ("a test that cannot fail is not evidence"):
#   a missing pin must STOP the caller, and a present pin must return the value.
# =====================================================================

# ---- the pin cache (HD-1135): one pass per process, zero execs per pin -------------------
# WHY: `grep -E | head -1 | sed -E | tr` is FOUR EXECs per call — 398 ms on the Win11 git-bash
# seat, where process creation is serialised, so only FEWER forks buy time. `pin` sits on the
# start-up path of every harness leg, and a leg launches the CLI per case.
# SHAPE: one `IFS=: read` pass over the file into an associative array. Why a loop and not a
# string search: `${BIG#*"$pat"}` (prefix removal with a LEADING WILDCARD) is not a substring
# search — it retries the match at every prefix length, so on this 45 KB file it measured ~1.3 s
# per lookup for a key near the end (position-proportional = quadratic). A one-pass read is ~30 ms.
# The pass reads FROM THE FILE (`done < "$VERSIONS"`), never through `$(<"$VERSIONS")`: a command
# substitution applies the MSYS text-mode translation (CONVENTIONS §6, the second half of the trap)
# and would lose the CR of a CRLF checkout. `IFS= read -r` keeps the byte, and the whitespace
# strip at the end of the body drops it — the same result `tr -d '[:space:]'` gave.
# `-g` IS LOAD-BEARING: every caller sources this file from INSIDE a function (`hl_source_lib`), and a
# bare `declare -A` there is FUNCTION-LOCAL — it dies with that function and the next assignment
# silently creates an INDEXED array, whose subscripts are ARITHMETIC-evaluated. Measured with the
# lib sourced that way: three different keys all answered `v3.7.13` (every `key` evaluated to index 0,
# so the last row written answered every lookup), and a file name containing a dot aborted the walk
# with `README.md: arithmetic syntax error`. A cache that answers the wrong key is worse than a fork.
declare -gA _HL_PIN_CACHE=()
_HL_PIN_CACHE_FILE=""

# _hl_pin_load [versions.yml] — parse the whole SSOT into _HL_PIN_CACHE. Column-0 `key:` rows only,
# which is exactly what the old `grep -E "^key:"` could see: comments, indented (nested) rows and the
# `---` document marker carry a non-word first field and are skipped.
# The optional argument is for `seat_pkg_val`, which may be pointed at another file than $VERSIONS;
# the cache is ONE map with the loaded path recorded in _HL_PIN_CACHE_FILE, so the two entry points
# cannot each hold a half-stale view of the same SSOT.
_hl_pin_load() {
  local _k="" _rest="" _line _a _b _src="${1:-${VERSIONS:-}}"
  [ -f "$_src" ] || { printf 'FATAL: no versions file at %s (§7)\n' "$_src" >&2; return 1; }
  declare -gA _HL_PIN_CACHE=()          # -g: see the note above; also the reset, so a re-read cannot keep a stale row
  while IFS=: read -r _k _rest || [ -n "${_k}${_rest}" ]; do   # trailing `||`: an unterminated last row still counts
    case "$_k" in ''|*[!A-Za-z0-9_]*) continue ;; esac
    if [ -n "${_HL_PIN_CACHE[$_k]+set}" ]; then continue; fi   # `head -1`: the FIRST row for a key wins
    _line="$_rest"
    _line="${_line#"${_line%%[![:space:]]*}"}"                 # ltrim: sed's `:[[:space:]]*`
    _line="${_line#\"}"                                        # an optional opening quote: sed's `"?`
    _a="$_line"; _b="$_line"
    case "$_a" in *\"*) _a="${_a%%\"*}" ;; esac                # stop at the first " …
    case "$_b" in *#*)  _b="${_b%%#*}" ;; esac                 # … or at the first #,
    if [ "${#_b}" -lt "${#_a}" ]; then _a="$_b"; fi            # whichever comes FIRST (sed's [^"#]*)
    _HL_PIN_CACHE[$_k]="${_a//[[:space:]]/}"                   # `tr -d '[:space:]'`, CR included
  done < "$_src"
  # A test seam, not a feature: with `_HL_PIN_READ_LOG` set (the self-test only), every read of an
  # SSOT appends its path. The count lives on DISK because the thing it must catch is a SUBSHELL — a
  # `$(seat_pkg_val …)` inside a loop drops the cache and re-reads per call, and a counter in a
  # variable dies with that subshell, so it would report the one read that never happened.
  # `if`, never `[ … ] && …`: an AND-list that ends a function RETURNS 1, and `set -e` in a caller
  # that sources this file would turn a disabled seam into a dead leg.
  if [ -n "${_HL_PIN_READ_LOG:-}" ]; then
    printf '%s\n' "$_src" >>"$_HL_PIN_READ_LOG"
  fi
  _HL_PIN_CACHE_FILE="$_src"
  _HL_PIN_CACHE_FILE="$_src"
}

# pin <var> <key> — set <var> from the versions SSOT; a missing pin STOPS the caller.
# The cache may not soften that: an absent key AND a key that exists with an empty value both
# read as empty here, and empty is a STOP (HD-1115 — the `exit 1` is the CALLER's own exit, which
# is why the value travels through an out-parameter and never through `$(pin …)`).
pin() {
  local __out="${1:?pin: needs an output variable}" __key="${2:?pin: needs a pin key}" __v=""
  if [ -z "${VERSIONS:-}" ]; then
    VERSIONS="${REPO:?pin: neither VERSIONS nor REPO is set}/IaC/ansible/group_vars/all/versions.yml"
  fi
  if [ ! -f "$VERSIONS" ]; then
    printf 'FATAL: pin: no versions file at %s (§7)\n' "$VERSIONS" >&2
    exit 1
  fi
  if [ "$_HL_PIN_CACHE_FILE" != "$VERSIONS" ]; then _hl_pin_load || exit 1; fi   # re-pointed VERSIONS = new cache, never a stale one
  __v="${_HL_PIN_CACHE[$__key]-}"
  if [ -z "$__v" ]; then
    printf 'FATAL: pin %s missing from %s — add it there, do not hardcode it here (§7)\n' \
      "$__key" "$VERSIONS" >&2
    exit 1
  fi
  printf -v "$__out" '%s' "$__v"
}

# hl_seat_registry_path — locate lib/seat-planes.yml from this helper's own location.
hl_seat_registry_path() { printf '%s' "$(dirname "$_HL_PIN_SELF")/seat-planes.yml"; }

# hl_owner_path <var> <file-name> — set <var> to the owner's repo-relative path, rc 1 if that name
# is not under scripts/. By name, so this registry never becomes a second copy of the tree: when
# HD-1118 Stage 3 moved these owners into folders (pi-self-update.sh is harness/ now), resolving by
# name means the registry never had to learn about the move.
# OUT-PARAMETER, like pin() (HD-1115's rule, for a second reason): `p="$(hl_owner_path x)"` runs in
# a SUBSHELL, and a subshell throws the memoised map away — the walk would then run again for every
# plane, which is exactly the fork this section exists to remove.
# FAST (HD-1135): the tree is walked ONCE per process. The old body paid one `find` (~129 ms) per
# plane per seat, so a registry read cost an exec per row. The walk is still a WALK, never a map of
# folder names hardcoded here — a hardcoded map is the thing that breaks `install-pi-debian.sh
# --check` the next time a file moves, which is the whole point of name lookup. The walk is a glob,
# so it costs no exec at all; `find -type f` semantics are kept: regular files only, symlinks not
# followed, `*/testdata/*` excluded, first hit wins (what `head -1` took).
declare -gA _HL_OWNER_PATH=()   # -g, load-bearing for the same reason as _HL_PIN_CACHE (see above)
_HL_OWNER_ROOT=""              # the root the map was built from; empty = never walked

hl_owner_paths_load() {
  local _root="${REPO:-.}/scripts" _p _name _gs=0 _ng=0
  declare -gA _HL_OWNER_PATH=()        # -g: see the note on _HL_PIN_CACHE
  if shopt -q globstar; then _gs=1; fi           # the caller's own shell options are restored below:
  if shopt -q nullglob; then _ng=1; fi           # a lib must not silently change how a glob behaves there
  shopt -s globstar; shopt -s nullglob
  for _p in "$_root"/**; do
    if [ -L "$_p" ]; then continue; fi                       # `find -type f` does not follow a link either
    case "$_p" in */testdata/*) continue ;; esac             # fixtures are not plane owners
    if [ ! -f "$_p" ]; then continue; fi
    _name="${_p##*/}"
    if [ -n "${_HL_OWNER_PATH[$_name]+set}" ]; then continue; fi
    _HL_OWNER_PATH[$_name]="${_p#"${REPO:-.}/"}"
  done
  if [ "$_gs" != 1 ]; then shopt -u globstar; fi
  if [ "$_ng" != 1 ]; then shopt -u nullglob; fi
  _HL_OWNER_ROOT="$_root"
}

hl_owner_path() {
  local __out="${1:?hl_owner_path: needs an output variable}" _want="${2:?hl_owner_path: needs a file name}" _hit
  if [ "$_HL_OWNER_ROOT" != "${REPO:-.}/scripts" ]; then hl_owner_paths_load; fi
  _hit="${_HL_OWNER_PATH[$_want]-}"
  [ -n "$_hit" ] || return 1
  printf -v "$__out" '%s' "$_hit"
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
  hl_owner_path path "$owner" || { printf 'FATAL: seat-planes.yml: plane %s names owner %s, which is not under scripts/ (a plane whose owner moved is a plane that silently stops running)\n' "$plane" "$owner" >&2; return 1; }
  # The driver runs these ON a seat with the seat's repo as cwd (relative is correct there);
  # an installer runs them from wherever the operator typed the command, and sets
  # HL_REPO_PREFIX="$REPO/" so the same registry line still names a real file.
  path="${HL_REPO_PREFIX:-}${path}"
  case "$runner" in
    bash)       printf '%s\t%s %s %s\n' "$plane" bash "$path" "$args" ;;
    python3)    # WHICH interpreter answers is a fact about the box that RUNS this line, and the
                 # driver is not that box: the command is composed HERE and executed in the SEAT
                 # (docs/harness-pi-seats.md §1). seat-python.sh carries the per-box case — the
                 # Windows half exists because `python3` there is the Microsoft-Store alias stub,
                 # the Debian half because a Debian seat has no `py` at all. Choosing it here is
                 # what made a Windows driver ship `py -3` into both Debian seats.
                 local _pyw
                 hl_owner_path _pyw seat-python.sh || { printf 'FATAL: seat-planes.yml: plane %s needs the launcher resolver seat-python.sh, which is not under scripts/ (a runner whose resolver moved runs nothing and says nothing)\n' "$plane" >&2; return 1; }
                 printf '%s\t%s %s%s %s %s\n' "$plane" bash "${HL_REPO_PREFIX:-}$_pyw" "$path" "$args" ;;
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

  # 5. the python runner's launcher is chosen WHERE THE COMMAND RUNS, not where it was composed.
  #    A Windows driver that emits `py -3 …` ships a Windows command line into a Debian seat, which
  #    dies at `py: command not found` and reads as that seat's `models` plane being broken — while
  #    the same registry line reads green from a Debian driver, which is why no other arm sees it.
  #    The fake Windows driver is a `uname` shim: go back to a compose-time `uname -s` case and this
  #    arm reddens. (The resolver's own two halves: harness/seat-python.sh --self-test.)
  mkdir -p "$_t/windrv"
  printf '%s\n' '#!/bin/sh' 'printf "MINGW64_NT-10.0-19045\n"' >"$_t/windrv/uname"
  chmod +x "$_t/windrv/uname"
  local _mdl
  _mdl="$(PATH="$_t/windrv:$PATH" seat_planes win11 check 2>/dev/null | awk -F'\t' '$1=="models"{print $2}')"
  if [ -z "$_mdl" ]; then
    printf 'NOT CAUGHT: the models plane emitted no command at all\n'; fails=$((fails + 1))
  elif printf '%s' "$_mdl" | grep -Eq '(^|[[:space:]])py([[:space:]]|$)'; then
    printf 'NOT CAUGHT: a Windows driver composed a seat command naming py: %s\n' "$_mdl"; fails=$((fails + 1))
  elif ! printf '%s' "$_mdl" | grep -q 'seat-python.sh'; then
    printf 'NOT CAUGHT: the python runner ships no launcher resolver: %s\n' "$_mdl"; fails=$((fails + 1))
  else
    printf 'ok: the python runner ships the resolver, not a compose-time launcher\n'
  fi

  [ "$fails" -eq 0 ] || printf 'seat-planes self-test: %s arm(s) NOT caught\n' "$fails" >&2
  return "$fails"
}

# seat_pkg_val <key> [versions.yml] — one scalar out of the version SSOT, no YAML parser needed
# in the seat path (the same trick pin() uses; a reader that needs a venv on a bare seat is a
# reader that fails on exactly the machine that is being bootstrapped).
# FAST (HD-1135) but SUBSHELL-SENSITIVE: the body is a lookup in the one-pass cache `pin()` fills,
# so the SSOT is read ONCE per process. ⚠ `v="$(seat_pkg_val k f)"` runs in a SUBSHELL, which throws
# that cache away — the next call re-reads the whole file, and a bash `read` loop over a 45 KB file
# is slower than the `sed | head` it replaced (measured on this WSL Debian seat: the inventory read
# went 1.11 s → 3.18 s when `seat_pkg_rows` kept calling through `$( )`). So the HOT path is
# `seat_pkg_rows`, which loads once and reads the map IN-PROCESS; this function stays the single-key
# entry point for callers that are not in a loop. Same out-parameter rule as pin() and
# hl_owner_path(), for the same reason.
seat_pkg_val() {
  local _f="${2:-${VERSIONS:-${REPO:-.}/IaC/ansible/group_vars/all/versions.yml}}" _v
  if [ "$_HL_PIN_CACHE_FILE" != "$_f" ]; then _hl_pin_load "$_f" || return 1; fi
  _v="${_HL_PIN_CACHE[$1]-}"
  printf '%s' "$_v"
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
  if [ "$_HL_PIN_CACHE_FILE" != "$_f" ]; then _hl_pin_load "$_f" || return 1; fi
  # The ids are DISCOVERED from the cache's own keys, so the inventory still lives in versions.yml
  # and never in a copy inside a script. ONE `sort` for the whole walk — the old form paid two forks
  # (sed | sort) plus five `sed | head` pairs PER package; ~70 forks a process, most of what
  # `pi-settings-config --self-test` spent. Sorting is kept because the output feeds a rendered
  # `packages` array, so its ORDER is part of the drift verdict.
  local _k _ids=()
  for _k in "${!_HL_PIN_CACHE[@]}"; do
    case "$_k" in
      pi_pkg_*_name) _k="${_k#pi_pkg_}"; _ids+=("${_k%_name}") ;;   # the id is what sits BETWEEN the two
    esac
  done
  [ "${#_ids[@]}" -ge 1 ] || { printf 'FATAL: the version SSOT carries ZERO packages (%s) — an empty inventory here means the reader broke, not that the fleet has no packages\n' "$_f" >&2; return 1; }
  for id in $(printf '%s\n' "${_ids[@]}" | sort -u); do
    name="${_HL_PIN_CACHE[pi_pkg_${id}_name]-}"
    scope="${_HL_PIN_CACHE[pi_pkg_${id}_scope]-}"
    ver="${_HL_PIN_CACHE[pi_pkg_${id}_version]-}"
    vpin="${_HL_PIN_CACHE[pi_pkg_${id}_version_pin]-}"
    mutable="${_HL_PIN_CACHE[pi_pkg_${id}_mutable]-}"
    [ -n "$name" ] || { printf 'FATAL: pi_pkg_%s has no _name — a row that names nothing is a row that installs nothing\n' "$id" >&2; return 1; }
    [ -n "$scope" ] || { printf 'FATAL: package %s has no scope — fleet or seat is exactly the question that got asked too late for pi-subagents\n' "$name" >&2; return 1; }
    if [ -n "$vpin" ]; then
      # IN-PROCESS, never `$(seat_pkg_val …)`: a subshell drops the cache and re-reads the file
      # (measured 3.2 s for this loop when it did — see the seat_pkg_val note above).
      ver="${_HL_PIN_CACHE[$vpin]-}"
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

  # 6. THE DIET (HD-1135): seat_pkg_val is a cache lookup, not a `sed | head`. The cache is only a
  #    valid way to EVALUATE the same assertion if it answers like the fork body on the keys the
  #    inventory path reads, byte for byte. Breeding the comparison rather than trusting it: the fork
  #    body runs alongside the cache, so a cache that answers a different key (the indexed-array
  #    class) or truncates a value reddens here, not on a seat. The key set is the inventory's own
  #    (pi_pkg_* plus the pins those rows reference) — NOT the whole SSOT: comparing every one of the
  #    147 keys turned this arm into 147 seds, which is the cost the arm exists to remove. The fork
  #    body is the ORIGINAL expression, transcription unchanged, handed to ONE `sed -f` instead of one
  #    `sed | head` a key — the key name goes into the substitution so every answer stays attributed,
  #    and `head -1` becomes "first row wins" in the read loop below.
  local _k _old _new _bad=0 _nkeys=0 _sf _keys _inv="${VERSIONS:-${REPO:-.}/IaC/ansible/group_vars/all/versions.yml}"
  local -A _fork=()
  _keys="$(grep -oE '^pi_pkg_[A-Za-z0-9_]+:' "$_inv" | tr -d ':'
           grep -oE '^pi_pkg_[A-Za-z0-9_]+_version_pin: *[A-Za-z0-9_]+' "$_inv" | awk '{print $2}')"
  _sf="$_t/compare.sed"; : >"$_sf"
  for _k in $(printf '%s\n' "$_keys" | sort -u); do
    # \1 NOT \x01: a bare `\1` in a printf FORMAT is an OCTAL escape and silently becomes SOH, which
    # is a sed replacement that captures nothing — the arm would compare an empty fork answer with the
    # cache and call that a divergence. Every other backslash here survives printf untouched.
    printf 's/^%s: *"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*#.*/%s\t\\1/p\ns/^%s: *"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/%s\t\\1/p\n' \
           "$_k" "$_k" "$_k" "$_k" >>"$_sf"
  done
  while IFS=$'\t' read -r _k _old; do
    [ -n "${_fork[$_k]+set}" ] || _fork[$_k]="$_old"        # the fork body's answer, first row per key
  done < <(sed -n -f "$_sf" "$_inv")
  for _k in $(printf '%s\n' "$_keys" | sort -u); do
    _nkeys=$((_nkeys + 1))
    _old="${_fork[$_k]-}"
    # NOT `$(seat_pkg_val …)`: a command substitution forks, and forking 27 times inside the arm whose
    # whole subject is fork cost is the tail wagging the dog. Redirecting a FUNCTION runs it in the
    # current shell (bash opens the file, forks nothing) — the same reason the legs are told to read
    # the map in-process. `|| :` because the value carries no trailing newline, so `read` returns 1 on
    # the partial line with the bytes correctly assigned.
    seat_pkg_val "$_k" "$_inv" >"$_t/one" || { printf 'NOT CAUGHT: seat_pkg_val stopped on %s\n' "$_k"; fails=$((fails + 1)); }
    _new=""; IFS= read -r _new <"$_t/one" || :
    # The ONLY tolerated difference is padding the fork body leaked for an UNQUOTED value — `\([^"]*\)`
    # is greedy, so `key: 1.6.1␣␣␣` came back with the spaces attached and a consumer building
    # `npm:name@$_old` got a spec with trailing blanks. Stripping it is the fix, not a divergence.
    [ "${_old//[[:space:]]/}" = "$_new" ] || { _bad=$((_bad + 1)); [ "$_bad" -le 3 ] && printf 'NOT CAUGHT: cache disagrees with the fork body on %s: fork=[%s] cache=[%s]\n' "$_k" "$_old" "$_new"; }
  done
  if [ "$_bad" -eq 0 ] && [ "$_nkeys" -ge 20 ]; then
    printf 'ok: seat_pkg_val answers like the fork body on %s inventory keys\n' "$_nkeys"
  elif [ "$_nkeys" -lt 20 ]; then
    printf 'NOT CAUGHT: the inventory key walk saw only %s keys — the SSOT was not read, not compared\n' "$_nkeys"; fails=$((fails + 1))
  else
    fails=$((fails + _bad))
  fi

  # 7. the cache must FOLLOW a re-pointed file. Two SSOTs in one process with a shared map is the
  #    stale-answer shape; the fixture points at a second file and asks for a key only it has.
  printf 'pi_pkg_only_here_name: "only-here"\n' >"$_t/other.yml"
  if [ "$(seat_pkg_val pi_pkg_only_here_name "$_t/other.yml")" = "only-here" ] \
     && [ -z "$(seat_pkg_val pi_pkg_web_access_name "$_t/other.yml")" ]; then
    printf 'ok: a re-pointed SSOT re-reads, it does not answer from the previous file\n'
  else
    printf 'NOT CAUGHT: seat_pkg_val answered from a stale cache after the file changed\n'; fails=$((fails + 1))
  fi

  # 8. THE DIET IS REAL, not just equal (HD-1135). Arm 6 compares `seat_pkg_val` with the fork body, so
  #    a `seat_pkg_val` that went BACK to `sed | head` would compare sed with sed and print GREEN —
  #    the one mutation this row must not survive. So count the reads instead of trusting the shape:
  #    one cold `seat_pkg_rows` walk must read the SSOT EXACTLY ONCE. Zero means the loader never ran,
  #    i.e. a fork per lookup (the body this row deleted); two or more means the walk lost its cache —
  #    the `$(seat_pkg_val …)` shape, whose reload happens in a subshell and is invisible to a counter
  #    held in a variable, which is why `_hl_pin_load` writes the tally to a file. Teeth, both sides:
  #    the fork body back in `seat_pkg_rows` reddens it (0 lines), and so does routing the walk's
  #    lookups through `$( )` (1 + one line per call).
  local _log="$_t/reads.log" _n
  _HL_PIN_CACHE_FILE=""                       # cold start: the walk must load the file itself
  : >"$_log"
  _HL_PIN_READ_LOG="$_log" seat_pkg_rows "$_inv" >/dev/null 2>&1
  _HL_PIN_READ_LOG=""
  _n=0
  while IFS= read -r _; do _n=$((_n + 1)); done <"$_log"   # `read`, not `wc -l`: a fork-free arm in a fork diet
  if [ "$_n" -eq 1 ]; then
    printf 'ok: one inventory walk reads the SSOT once, not once a key\n'
  else
    printf 'NOT CAUGHT: an inventory walk read the SSOT %s time(s) — 0 means a fork per lookup (the body this diet deleted), >1 means the walk dropped its cache and re-read per call\n' "$_n"
    fails=$((fails + 1))
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
  # Three rows, not one: `the_second` proves a warm cache answers a key nobody asked for yet,
  # `the_empty` is the mapping-key shape `tailscale_host_deb_sha256_by_arch` has in the real SSOT.
  printf 'the_pin: "9.9.9"  # fixture\nthe_second: 8.8.8\nthe_empty:\n' >"$_t/versions.yml"

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

  # Half 4 (the cache's own shape, HD-1135): the SSOT is parsed ONCE and EVERY row lands in the
  # cache, so a SECOND pin in the same process is not a miss. A parser that caches only the row it
  # was asked for — or stops at the first row — reddens here, not in the leg it starves.
  printf '#!/usr/bin/env bash\nVERSIONS="%s/versions.yml"\n. "%s/lib/pi-seat.sh"\npin A the_pin\npin B the_second\nprintf "%%s %%s %%s\\n" "$A" "$B" "${#_HL_PIN_CACHE[@]}"\n' "$_t" "$_t" >"$_t/warm.sh"
  _out="$(bash "$_t/warm.sh" 2>&1)"
  if [ "$_out" = "9.9.9 8.8.8 3" ]; then
    printf 'ok: a warm cache answers a second key (all fixture rows parsed)\n'
  else
    printf 'NOT CAUGHT: warm cache gave %s (want "9.9.9 8.8.8 3")\n' "$_out"
    fails=$((fails + 1))
  fi

  # Half 5: a key that EXISTS with an EMPTY value is a missing pin. The cache stores the empty
  # string, so the STOP must test the VALUE — an empty version is exactly the blank string HD-1115
  # was about, and a mapping key (`tailscale_host_deb_sha256_by_arch`) is this shape in the SSOT.
  printf '#!/usr/bin/env bash\nVERSIONS="%s/versions.yml"\n. "%s/lib/pi-seat.sh"\npin OUT the_empty\nprintf "REACHED-AFTER-EMPTY-PIN\\n"\n' "$_t" "$_t" >"$_t/empty.sh"
  _out="$(bash "$_t/empty.sh" 2>&1)"; _rc=$?
  if [ "$_rc" -ne 0 ] && ! printf '%s' "$_out" | grep -q "REACHED-AFTER-EMPTY-PIN"; then
    printf 'ok: a pin that exists with an empty value stops the caller (rc %s)\n' "$_rc"
  else
    printf 'NOT CAUGHT: an empty-valued pin was accepted (rc %s): %s\n' "$_rc" "$_out"
    fails=$((fails + 1))
  fi

  # Half 6: the cache is keyed on the file it read. A re-pointed VERSIONS in the SAME shell must
  # answer from the NEW file — a cache that ignores the re-point serves a stale pin forever.
  printf 'the_pin: "7.7.7"\n' >"$_t/versions2.yml"
  printf '#!/usr/bin/env bash\nVERSIONS="%s/versions.yml"\n. "%s/lib/pi-seat.sh"\npin A the_pin\nVERSIONS="%s/versions2.yml"\npin B the_pin\nprintf "%%s %%s\\n" "$A" "$B"\n' "$_t" "$_t" "$_t" >"$_t/repoint.sh"
  _out="$(bash "$_t/repoint.sh" 2>&1)"
  if [ "$_out" = "9.9.9 7.7.7" ]; then
    printf 'ok: a re-pointed VERSIONS re-reads (no stale pin served from the cache)\n'
  else
    printf 'NOT CAUGHT: re-pointed VERSIONS gave %s (want "9.9.9 7.7.7")\n' "$_out"
    fails=$((fails + 1))
  fi

  # Half 7: how the lib is ACTUALLY loaded. Every caller sources it through hl_source_lib, which is a
  # FUNCTION, and a `declare -A` at source time is function-LOCAL: the map then silently comes back
  # INDEXED, its subscripts are arithmetic-evaluated, and every key collapses onto one element —
  # three different pins answering ONE pin's value, with no error. Source it the way they do.
  printf '#!/usr/bin/env bash\nVERSIONS="%s/versions.yml"\nload(){ . "%s/lib/pi-seat.sh"; }\nload\npin A the_pin\npin B the_second\nprintf "%%s %%s\\n" "$A" "$B"\n' "$_t" "$_t" >"$_t/funcsrc.sh"
  _out="$(bash "$_t/funcsrc.sh" 2>&1)"
  if [ "$_out" = "9.9.9 8.8.8" ]; then
    printf 'ok: a function-sourced lib answers every key (the cache really is global)\n'
  else
    printf 'NOT CAUGHT: function-sourced lib gave %s (want "9.9.9 8.8.8")\n' "$_out"
    fails=$((fails + 1))
  fi

  # Half 8: the same trap on the owner map — an INDEXED map answers every lookup with one path, and a
  # name containing a dot aborts the walk in arithmetic. Fixture tree, one real owner, one unknown.
  mkdir -p "$_t/scripts/harness"
  : >"$_t/scripts/harness/warm-owner.sh"
  printf '#!/usr/bin/env bash\nREPO="%s"\nload(){ . "%s/lib/pi-seat.sh"; }\nload\nhl_owner_path P warm-owner.sh && printf "P=%%s;" "$P"\nhl_owner_path Q nope.sh; _rc=$?\nprintf "unknown=%%s\\n" "$_rc"\n' "$_t" "$_t" >"$_t/funcown.sh"
  _out="$(bash "$_t/funcown.sh" 2>&1)"
  if [ "$_out" = "P=scripts/harness/warm-owner.sh;unknown=1" ]; then
    printf 'ok: a function-sourced owner map resolves by name (unknown still rc 1)\n'
  else
    printf 'NOT CAUGHT: function-sourced owner map gave %s (want "P=scripts/harness/warm-owner.sh;unknown=1")\n' "$_out"
    fails=$((fails + 1))
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
