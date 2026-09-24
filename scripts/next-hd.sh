#!/usr/bin/env bash
# next-hd.sh — derive the next free HD id (CONVENTIONS §1 / README §§0-4).
#
# The repo's "derived-values ban" (HD-253 lesson) forbids hand-typing computable
# pointers like the next free HD number into prose — a stale literal in a handoff
# silently desyncs the backlog. This script re-derives it on demand from the SSOT
# files so the number is always computed, never memorized.
#
# Source of truth scanned (in increasing precedence — the *widest* superset wins):
#   todo.md     — active/open rows (HD-267, zero-padded HD-03, ...)
#   docs/**/*.md — owning docs carry HD-XX refs for related items, decisions, deploy-gates
#   git history  — `git log -S 'HD-'` catches fully-closed rows deleted from todo.md
#                 (their HD id survives only in commit messages/history). The archived
#                 changelog was frozen → reports/changelog.md after 2026-09-01; it is NOT
#                 scanned (archive-only).
# next free = max(all HD numbers across those sources) + 1
#
# Parser intentionally lenient: matches `HD-03`, `HD-259B`, `HD-247–251`,
# `hd244+hd245`, `HD-260`, ... and takes the largest integer. Zero-padded ids
# sort numerically, never lexically (100 > 99).
#
# Usage:
#   bash scripts/next-hd.sh            # prints "HD-268" (default)
#   bash scripts/next-hd.sh --raw      # prints just the number (for scripting)
#   bash scripts/next-hd.sh --max      # prints the current max id (e.g. "267")
#   bash scripts/next-hd.sh --max-raw  # prints the current max as a bare number
#   FILES="todo.md" bash scripts/next-hd.sh   # restrict scan set (CI/debug)
#
# Exit codes: 0 ok · 2 nothing parses / files unreadable (fail loud, never 0)
set -u

# --- resolve scan set --------------------------------------------------------
SRC_REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_FILES="todo.md"
GIT_SCAN=1  # also scan `git log -S 'HD-'` for closed rows (widest superset)
# Did the CALLER restrict the scan set? Test BEFORE defaulting FILES, or the default assignment
# below makes every run look "restricted" and silently disables the tree scan — which is exactly how
# this patch failed its first test run (it printed 451, the very collision it was written to catch).
if [ -n "${FILES+set}" ]; then FILES_RESTRICTED=1; else FILES_RESTRICTED=0; fi
FILES="${FILES:-$DEFAULT_FILES}"

# --- collect every HD integer fragment from the given files -----------------
# Warn if the optional git-history scan is skipped (closed HD ids hidden).
if [ "${GIT_SCAN:-1}" = "1" ]; then
  if command -v git >/dev/null 2>&1 && git -C "$SRC_REPO" rev-parse --git-dir >/dev/null 2>&1; then
    echo "next-hd: note: scanning git history (git log -S 'HD-') + the whole tracked tree (git grep; reports/ excluded)" >&2
  else
    echo "next-hd: warn: not in a git repo — closed-row HD ids (git history) not scanned; max may undercount" >&2
  fi
fi

# Tree scan: the header has ALWAYS claimed docs/**/*.md was in the scan set; it was not — the
# default was todo.md alone, and `git log -S` was trusted to cover closed rows. It did not:
# `git log -S 'HD-'` compares a commit's before/after occurrence COUNT, so a row that entered and
# left the file (added, then swept at close-out) nets to zero and vanishes from history's view.
# HD-451 is exactly that shape — its row is gone, but the id is cited in group_vars/vps.yml,
# two route templates, deploy-service.yml and prompt.md — and this script handed HD-451 out as
# "free" on 2026-09-24. A colliding id does not fail: it silently cross-links two unrelated
# rows, which is the worst kind of backlog bug. Scanning the working tree instead makes the
# documented promise true and catches every citation, wherever it lives.
scan_tree() {
  git -C "$SRC_REPO" grep -hoIE '[Hh][Dd][-_+–][0-9]+' -- . ':(exclude)reports' 2>/dev/null
}

extract_ids() {
  local f
  {
    for f in $FILES; do
      [ -r "$SRC_REPO/$f" ] || { echo "next-hd: unreadable SSOT file: $SRC_REPO/$f" >&2; return 2; }
      # Matches HD-<n>, hd<n>, HD-n+m, HD-n–m (en dash), HD-n-m. The historical
      # lowercase `hd244+hd245` and range `HD-247–251` must be captured too.
      grep -ohE '[Hh][Dd][-_+–][0-9]+' "$SRC_REPO/$f" 2>/dev/null
    done
    # Only when the caller did not restrict the set with FILES= — that override exists for
    # CI/debug scoping and must keep meaning "exactly these files".
    [ "${FILES_RESTRICTED:-0}" = "0" ] && scan_tree
  } | grep -oE '[0-9]+' |
    sort -n | uniq   # numerically sorted, deduped; empty-safe
}

IDS="$(extract_ids)" || exit 2
MAX_STR="$(printf '%s\n' "$IDS" | tail -n 1)"
[ -n "${MAX_STR:-}" ] || { echo "next-hd: no HD ids parsed from $FILES" >&2; exit 2; }

# --- modes --------------------------------------------------------------
mode="${1:-}"
case "$mode" in
  --max)
    printf 'HD-%s\n' "$MAX_STR" ;;
  --max-raw)
    printf '%s\n' "$MAX_STR" ;;
  --raw)
    printf '%s\n' "$((MAX_STR + 1))" ;;
  ""|--next)
    printf 'HD-%s\n' "$((MAX_STR + 1))" ;;
  *)
    echo "next-hd: unknown mode '$mode' (--raw | --max | --max-raw | --next)" >&2
    exit 1 ;;
esac