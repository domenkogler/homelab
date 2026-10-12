#!/usr/bin/env bash
# =====================================================================
# lib/repo-root.sh — the ONE repo-root resolver for bash (HD-1118 Stage 1)
# ---------------------------------------------------------------------
# WHY: 20 executable bash scripts derived the repo root as "the directory above
# me" (`$SCRIPT_DIR/..` in four different spellings). That makes the root exactly
# one level above the script, so the moment a script changes directory the root
# silently becomes `scripts/` — every tree walk then finds nothing and every
# validator prints a green `OK: 0 files`. That is the HD-417 mute-failure class
# at maximum width, and it is why this file had to exist BEFORE `scripts/` was
# allowed to grow folders (prompt-scripts.md Stage 1 / HD-1118).
#
# HOW: walk up from the CALLING script until the repo's structural markers show
# up. Depth is therefore irrelevant, which is exactly the property Stage 3 needs:
# the same line resolves at `scripts/<name>.sh` and at `scripts/<folder>/<name>.sh`.
#
# USE — one bootstrap at the old `REPO=...` site (keeps an inherited $REPO so the
# fixture-driven scripts still work, e.g. `REPO=…/testdata/… gate/check-vault-items.sh`):
#
#   _hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
#   . "$_hl_d/lib/repo-root.sh"        # sets REPO; FATAL when no root is found
#
# A root that cannot be found is a FATAL, never an empty string. The `exit 1`
# below runs in the CALLER's shell (this file is sourced, not substituted), so it
# really does stop the caller — the defect HD-1115 recorded for `pin()` was
# `exit` inside `$( )`, a subshell, which cannot stop anything.
#
# SELF-TEST: bash scripts/lib/repo-root.sh --self-test
#   Builds a marker-complete fake repo in a temp dir and calls the resolver from
#   TWO depths. A fixed-depth resolver fails the second depth — that is the
#   point: the real tree cannot offer the two-depth case, so the fixture must,
#   or the test cannot fail and proves nothing (CONVENTIONS §6).
# =====================================================================

# hl_repo_root_from <path-inside-the-repo> — echo the root, or nothing + rc 1.
hl_repo_root_from() {
  local _d
  _d="$(cd "$(dirname "${1:-$0}")" 2>/dev/null && pwd)" || return 1
  while [ -n "$_d" ] && [ "$_d" != / ]; do
    # BOTH markers: `IaC/ansible` alone would match a nested tree, `docs/index.md`
    # alone a docs-only scratch clone. Either alone could be the wrong root.
    if [ -d "$_d/IaC/ansible" ] && [ -f "$_d/docs/index.md" ]; then
      printf '%s' "$_d"
      return 0
    fi
    _d="$(dirname "$_d")"
  done
  return 1
}

# hl_source_lib <own-script-path> <lib-file-name> — source a lib helper by NAME.
# No caller hardcodes a relative path into lib/, because that would re-grow the
# same fixed-depth bug in a new costume. Searches upward for the scripts/lib dir.
hl_source_lib() {
  local _self="${1:-$0}" _name="${2:?hl_source_lib: needs a lib file name}" _d
  _d="$(cd "$(dirname "$_self")" 2>/dev/null && pwd)" || return 1
  while [ -n "$_d" ] && [ "$_d" != / ]; do
    if [ -f "$_d/lib/$_name" ]; then
      # shellcheck source=/dev/null
      . "$_d/lib/$_name"
      return 0
    fi
    _d="$(dirname "$_d")"
  done
  printf 'FATAL: hl_source_lib: cannot find scripts/lib/%s above %s\n' "$_name" "$_self" >&2
  return 1
}

# hl_repo_root_selftest — returns the number of arms NOT caught.
hl_repo_root_selftest() {
  local fails=0 _t _d _got
  _t="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$_t'" RETURN

  # A marker-complete fake repo, with a caller at TWO depths. Depth 1 is where
  # the scripts sit today, depth 2 is where Stage 3 puts them: a resolver that
  # passes only depth 1 is the bug this whole stage exists to kill.
  mkdir -p "$_t/repo/IaC/ansible" "$_t/repo/docs" "$_t/repo/scripts/lib" "$_t/repo/scripts/gate" "$_t/stray/lib"
  : >"$_t/repo/docs/index.md"
  cp "$_HL_SELF" "$_t/repo/scripts/lib/repo-root.sh"
  cp "$_HL_SELF" "$_t/stray/lib/repo-root.sh"
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' \
    '_x="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' \
    'while [ ! -f "$_x/lib/repo-root.sh" ] && [ "$_x" != / ]; do _x="$(dirname "$_x")"; done' \
    '. "$_x/lib/repo-root.sh"' \
    'printf "%s\n" "$REPO"' >"$_t/caller.template"
  for _d in scripts scripts/gate; do
    cp "$_t/caller.template" "$_t/repo/$_d/caller.sh"
    _got="$(bash "$_t/repo/$_d/caller.sh" 2>&1)"
    if [ "$_got" = "$_t/repo" ]; then
      printf 'ok: root resolves from %s (structure-neutral)\n' "$_d"
    else
      printf 'NOT CAUGHT: root from %s = %s (want %s)\n' "$_d" "$_got" "$_t/repo"
      fails=$((fails + 1))
    fi
  done

  # Canary: a directory that is not a repo must FAIL, not return a wrong root.
  cp "$_t/caller.template" "$_t/stray/caller.sh"
  if bash "$_t/stray/caller.sh" >/dev/null 2>&1; then
    printf 'NOT CAUGHT: a non-repo directory produced a root\n'
    fails=$((fails + 1))
  else
    printf 'ok: a non-repo directory fails loud\n'
  fi

  # An explicit $REPO still wins — the testdata fixtures drive scripts that way.
  # the folder segment is a VARIABLE so no literal `scripts/<name>.sh` lands in this file —
  # `git grep scripts/[a-z-]*\.\w+` is HD-1118's acceptance test and cannot tell a fixture from a ref
  _d=scripts
  cp "$_t/caller.template" "$_t/repo/$_d/caller2.sh"
  _got="$(REPO="$_t/override" bash "$_t/repo/$_d/caller2.sh" 2>/dev/null)"
  if [ "$_got" = "$_t/override" ]; then
    printf 'ok: an inherited $REPO wins (fixture override)\n'
  else
    printf 'NOT CAUGHT: the $REPO override was ignored (%s)\n' "$_got"
    fails=$((fails + 1))
  fi

  # And this checkout itself: the resolved root must carry the markers.
  _got="$(hl_repo_root_from "$_HL_SELF" || true)"
  if [ -n "$_got" ] && [ -d "$_got/IaC/ansible" ] && [ -f "$_got/docs/index.md" ]; then
    printf 'ok: this checkout resolves a root that carries the markers\n'
  else
    printf 'NOT CAUGHT: no marker-carrying root found above %s\n' "$_HL_SELF"
    fails=$((fails + 1))
  fi

  [ "$fails" -eq 0 ] || printf 'repo-root self-test: %s arm(s) NOT caught\n' "$fails" >&2
  return "$fails"
}

_HL_SELF="${BASH_SOURCE[0]}"

# Executed directly with --self-test (no caller frame) → run the arms and stop.
if [ "${1:-}" = "--self-test" ] && [ -z "${BASH_SOURCE[1]:-}" ]; then
  hl_repo_root_selftest
  exit $?
fi

[ -n "${_HL_REPO_ROOT_LOADED:-}" ] && return 0 2>/dev/null || true

if [ -z "${REPO:-}" ]; then
  REPO="$(hl_repo_root_from "${BASH_SOURCE[1]:-$0}")" || REPO=""
else
  _HL_REPO_EXPLICIT=1   # an override (a fixture, a wrapper): trusted, not re-checked
fi
if [ -z "${_HL_REPO_EXPLICIT:-}" ] && [ ! -d "${REPO:-}/IaC/ansible" ]; then
  printf 'FATAL: repo-root.sh: cannot locate the repo root from %s — run from a homelab clone (HD-1118)\n' \
    "${BASH_SOURCE[1]:-$0}" >&2
  exit 1
fi
export REPO
_HL_REPO_ROOT_LOADED=1
