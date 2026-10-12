#!/usr/bin/env bash
# guard-session.sh — session-discipline mechanical enforcement (HD-253).
#
# Modes:
#   (default)       Pre-edit guard: refuses ANY edit-context while the PRIMARY
#                   checkout sits on `main` — editing there IS the violation,
#                   clean or dirty. Run it right after creating the session
#                   worktree, before the first write/edit (CONVENTIONS §6 ritual).
#   --validate-mode Used by scripts/validate-all.sh: hard-fails ONLY when running
#                   from primary+main+DIRTY (committing primary-resident edits =
#                   the violation). A clean-main merge-station run passes
#                   silently; session worktrees (branch != main) unaffected.
#   --self-test     Sandboxed fixture over throwaway temp repos (never touches
#                   the calling repo): asserts fire-on-primary-main, the clean-main
#                   merge-station exemption, worktree pass-through and detached-HEAD
#                   pass-through, plus the remediation-text contract. Invoked BY
#                   validate-all.sh so failures surface through the standard gate.
#
# Primary detection (HD-253): a checkout is PRIMARY ⇔
#   git rev-parse --git-dir  ==  git rev-parse --git-common-dir
# Branch via `git rev-parse --abbrev-ref HEAD`; detached HEAD or a CI
# environment ($CI set) → pass-through in every mode.
#
# Every violation message carries the EXACT remediation command with a LIVE
# timestamp prefilled:
#   git worktree add ../homelab-wt-YYYYMMDD-HHMM
# plus `git status --short` and per-dirty-file last-commit subjects so parallel
# lanes can coordinate instead of stashing each other's WIP.
#
# Owning rule: CONVENTIONS.md §6 (Git worktrees) · registered as HD-253.
set -uo pipefail

TS="$(date +%Y%m%d-%H%M)"
REMEDIATION_CMD="git worktree add ../homelab-wt-${TS}"

err() { printf 'guard-session: %s\n' "$*" >&2; }

# --- detection helpers -------------------------------------------------------
is_primary() {
  local gd gcd
  gd="$(git rev-parse --git-dir 2>/dev/null)" || return 2
  gcd="$(git rev-parse --git-common-dir 2>/dev/null)" || return 2
  if command -v realpath >/dev/null 2>&1; then
    gd="$(realpath "$gd" 2>/dev/null || printf '%s' "$gd")"
    gcd="$(realpath "$gcd" 2>/dev/null || printf '%s' "$gcd")"
  fi
  [ "$gd" = "$gcd" ]
}

current_branch() { git rev-parse --abbrev-ref HEAD 2>/dev/null; }

is_dirty() { [ -n "$(git status --porcelain 2>/dev/null)" ]; }

pass_through() { [ "$(current_branch)" = "HEAD" ] || [ -n "${CI:-}" ]; }

# --- reporting ---------------------------------------------------------------
print_coordination() {
  err "Coordination info (do NOT stash/discard foreign WIP — coordinate first):"
  git status --short >&2 || true
  local line f subj
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    f="${line:3}"
    case "$f" in *" -> "*) f="${f##* -> }" ;; esac
    if git cat-file -e "HEAD:$f" 2>/dev/null; then
      subj="$(git log -1 --format='%h %s' -- "$f" 2>/dev/null || true)"
    else
      subj="(untracked — no history)"
    fi
    err "  ${f} → last touch: ${subj}"
  done <<EOF_STATUS
$(git status --porcelain 2>/dev/null || true)
EOF_STATUS
}

print_refusal() {
  err "$1"
  err "Remediation — create a session worktree FIRST, then do the work there:"
  err "    ${REMEDIATION_CMD}"
  err ""
  print_coordination
}

# --- core check --------------------------------------------------------------
# $1 = mode: "edit" (pre-edit guard) | "validate" (validate-all gate)
check_mode() {
  local mode="$1"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    err "not inside a git work tree — cannot apply the session-discipline guard"
    return 2
  }

  if pass_through; then
    [ "$mode" = "edit" ] && err "detached HEAD or CI environment — guard passes through"
    return 0
  fi

  local branch primary dirty
  branch="$(current_branch)"
  if is_primary; then primary=yes; else primary=no; fi
  if is_dirty; then dirty=yes; else dirty=no; fi

  if [ "$mode" = "edit" ]; then
    if [ "$primary" = "yes" ] && [ "$branch" = "main" ]; then
      print_refusal "REFUSED: this is the PRIMARY checkout sitting on 'main' — editing here IS the violation (CONVENTIONS §6, HD-253), clean or dirty."
      return 1
    fi
    err "OK: edit context safe (primary=${primary}, branch=${branch}, dirty=${dirty})"
    return 0
  fi

  # validate mode: fail only primary+main+DIRTY (clean main = merge station, exempt)
  if [ "$primary" = "yes" ] && [ "$branch" = "main" ] && [ "$dirty" = "yes" ]; then
    print_refusal "HARD FAIL: validate-all ran from the PRIMARY checkout on 'main' with DIRTY files — committing primary-resident edits is the violation (CONVENTIONS §6, HD-253)."
    return 1
  fi
  return 0
}

# --- self-test ---------------------------------------------------------------
self_test() {
  local rc fails=0 out
  FIXDIR="$(mktemp -d "${TMPDIR:-/tmp}/guard-selftest.XXXXXX")" || { err "self-test: mktemp failed"; return 1; }
  # Explicit best-effort cleanup (Windows: git worktree handles can still be held at
  # script-exit time, so a bare EXIT trap races — clean up BEFORE returning instead).
  selftest_cleanup() { rm -rf "${FIXDIR:-}" 2>/dev/null || true; FIXDIR=""; }

  run_in() { # run check_mode in a given directory (subshell cwd)
    ( cd "$1" && check_mode "$2" )
  }
  expect_fail() { # $1 label, rest = command
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
      err "SELFTEST FAIL: ${label} — expected refusal, got pass"; fails=$((fails + 1))
    else
      err "ok: ${label} → refused"
    fi
  }
  expect_pass() { # $1 label, rest = command
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
      err "ok: ${label} → passed"
    else
      err "SELFTEST FAIL: ${label} — expected pass, got refusal"; fails=$((fails + 1))
    fi
  }

  git init -q -b main "${FIXDIR}/primary"
  git -C "${FIXDIR}/primary" config user.email guard@selftest.invalid
  git -C "${FIXDIR}/primary" config user.name "guard-selftest"
  git -C "${FIXDIR}/primary" config core.autocrlf false
  printf 'base\n' >"${FIXDIR}/primary/file.txt"
  git -C "${FIXDIR}/primary" add file.txt
  git -C "${FIXDIR}/primary" commit -qm init

  # Case A: primary + main + DIRTY → both gates fire
  printf 'dirty\n' >>"${FIXDIR}/primary/file.txt"
  expect_fail "primary+main+DIRTY (pre-edit guard)" run_in "${FIXDIR}/primary" edit
  expect_fail "primary+main+DIRTY (validate gate)" run_in "${FIXDIR}/primary" validate

  # Remediation contract: refusal output names the exact worktree command
  out="$(run_in "${FIXDIR}/primary" edit 2>&1 || true)"
  case "$out" in
    *"git worktree add ../homelab-wt-"*) err "ok: refusal prints remediation command with live timestamp" ;;
    *) err "SELFTEST FAIL: remediation command missing from refusal output"; fails=$((fails + 1)) ;;
  esac

  # Case B: primary + main + CLEAN → pre-edit still refuses; validate passes SILENTLY
  git -C "${FIXDIR}/primary" checkout -q -- file.txt
  expect_fail "primary+main+CLEAN (pre-edit guard — editing IS the violation)" run_in "${FIXDIR}/primary" edit
  local brc=0 out_b
  out_b="$(run_in "${FIXDIR}/primary" validate 2>&1)" || brc=$?
  if [ "$brc" -eq 0 ] && [ -z "$out_b" ]; then
    err "ok: clean-main merge-station exemption (validate) → silent pass"
  else
    err "SELFTEST FAIL: clean-main merge-station exemption broke (out='${out_b}')"; fails=$((fails + 1))
  fi

  # Case C: session worktree on a session branch (even dirty) → both pass
  git -C "${FIXDIR}/primary" worktree add -q -b session/selftest "${FIXDIR}/wt"
  printf 'wip\n' >>"${FIXDIR}/wt/file.txt"
  expect_pass "session worktree branch≠main, dirty (pre-edit guard)" run_in "${FIXDIR}/wt" edit
  expect_pass "session worktree branch≠main, dirty (validate gate)" run_in "${FIXDIR}/wt" validate

  # Case D: detached HEAD → pass-through even though dirty
  git -C "${FIXDIR}/wt" checkout -q --detach HEAD
  expect_pass "detached HEAD pass-through" run_in "${FIXDIR}/wt" edit

  if [ "$fails" -eq 0 ]; then
    selftest_cleanup
    err "SELFTEST OK: all guard cases passed (fixture removed)"
    return 0
  fi
  selftest_cleanup
  err "SELFTEST FAILED: ${fails} case(s) failed"
  return 1
}

# --- dispatch ----------------------------------------------------------------
rc=0
case "${1:-}" in
  --validate-mode) check_mode validate || rc=$? ;;
  --self-test)     self_test || rc=$? ;;
  "")              check_mode edit || rc=$? ;;
  *)
    err "usage: guard-session.sh [--validate-mode | --self-test]"
    rc=2
    ;;
esac
exit "$rc"
