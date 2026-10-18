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
# HD-1118 Stage 1 (the ratchet caught this one at Stage 4): the repo root is FOUND by
# scripts/lib/repo-root.sh, not assumed from `$(dirname "$0")/..`. This file stayed at scripts/
# root through the restructure, so the assumption still happened to work — which is exactly how a
# fixed depth survives: it is not wrong today, it is wrong the day someone moves the file.
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"   # sets REPO
SRC_REPO="$REPO"
DEFAULT_FILES="todo.md"
GIT_SCAN=1  # also scan `git log -S 'HD-'` for closed rows (widest superset)
# RESERVED ids — HD tokens that are TOOL FIXTURE TEXT or a documented mis-mint, not backlog ids.
# This exists because the tree scan is deliberately wide, and a wide scan reads a tool's own
# canary as evidence: `check_todo_done.py` writes literal `HD-900` / `HD-900z` rows into a
# throwaway copy of todo.md to breed a duplicate-id collision (its self-test, lines around the
# `canary parent` fixture). Measured 2026-10-06: max came out 900 and this script handed out
# **HD-901** while the real top of the registry was HD-494 — a 400-number jump, into an id no row
# ever held. The renamed-to-HD-495 work is that session; 901 is reserved too so no later run
# re-mints the same phantom out of the two commit messages that still name it.
# Keep this list in sync with the canary comment in scripts/gate/check_todo_done.py; env-overridable
# so a test can prove the filter is load-bearing (`RESERVED_IDS='' bash scripts/next-hd.sh --max`
# → the 900 comes back). Note the `${VAR-default}`, NOT `${VAR:-default}`: an explicitly empty
# value must mean "no filtering", which `:-` cannot express — it silently re-applies the default
# and turns the mutation test into a pass that proves nothing (measured on first try here).
RESERVED_IDS="${RESERVED_IDS-900 901}"
# RESERVED RANGES — the whole 9000-block is the TOOL-FIXTURE namespace, one call, recorded here and
# in CONVENTIONS §1 / todo.md §0. The list above is a per-id patch and it did not hold: the 900/901
# exclusion was written against ONE tool's canary, and `corpus_diff.py`'s classifier fixtures mint
# their own synthetic ids (`HD-9001`…`HD-9007`) because the shapes under test must look like real
# tokens. Measured 2026-10-18: `next-hd.sh` printed **HD-9008** while the registry top was HD-1158 —
# the same mis-mint class as HD-901, four orders of magnitude higher, and it recurs on every fixture
# anyone adds. So the exclusion is a RANGE now, not a list: 9000-9999 is reserved for synthetic
# tokens and no backlog row may ever be minted into it. `scripts/gate/check_hd_mint_space.py` holds
# both halves — a synthetic id OUTSIDE the block reddens, and a registry row INSIDE it reddens — so
# the block stays exclusive by rule rather than by nobody noticing. Same `${VAR-default}` form as
# RESERVED_IDS: an explicitly empty value means "no filtering", so a test can prove it is load-bearing
# (`RESERVED_RANGES='' bash scripts/next-hd.sh --max` → the poisoned 9000-block max comes back).
RESERVED_RANGES="${RESERVED_RANGES-9000-9999}"
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
    # drop reserved ids (fixture text / mis-mints) and reserved ranges (the tool-fixture namespace)
    # before the max is taken — see RESERVED_IDS / RESERVED_RANGES above.
    # awk, not `grep -f <(...)`: an empty RESERVED_IDS must be a PASS-THROUGH, and an empty pattern
    # file would instead delete every candidate and make the script fail as though no HD existed.
    awk -v reserved="${RESERVED_IDS}" -v ranges="${RESERVED_RANGES}" '
      BEGIN{
        split(reserved,a," "); for(i in a) skip[a[i]+0]=1
        n=split(ranges,r,","); for(i=1;i<=n;i++){ split(r[i],b,"-"); lo[i]=b[1]+0; hi[i]=(b[2]""=="")?b[1]+0:b[2]+0 }
      }
      { if(skip[$1+0]) next; for(i=1;i<=n;i++) if($1+0>=lo[i] && $1+0<=hi[i]) next; print }' |
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