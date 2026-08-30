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
#   changelog.md — append-only decision log + done rows (fully-done rows are
#               *deleted* from todo.md but their HD survives here; ranges like
#               HD-247–251 and compound tags like hd244+hd245 also appear)
# next free = max(all HD numbers across those files) + 1
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
DEFAULT_FILES="todo.md changelog.md"
FILES="${FILES:-$DEFAULT_FILES}"

# --- collect every HD integer fragment from the given files -----------------
extract_ids() {
  local f raw
  for f in $FILES; do
    [ -r "$SRC_REPO/$f" ] || { echo "next-hd: unreadable SSOT file: $SRC_REPO/$f" >&2; return 2; }
    # Matches HD-<n>, hd<n>, HD-n+m, HD-n–m (en dash), HD-n-m. The historical
    # lowercase `hd244+hd245` and range `HD-247–251` must be captured too.
    grep -ohE '[Hh][Dd][-_+–][0-9]+' "$SRC_REPO/$f" 2>/dev/null
  done | grep -oE '[0-9]+' |
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