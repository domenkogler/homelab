#!/usr/bin/env bash
# next-hd.sh — derive the next free HD id (CONVENTIONS §1 / README §§0-4).
#
# The repo's "derived-values ban" (HD-253 lesson) forbids hand-typing computable
# pointers like the next free HD number into prose — a stale literal in a handoff
# silently desyncs the backlog. This script re-derives it on demand from the SSOT
# files so the number is always computed, never memorized.
#
# Source of truth scanned (in increasing precedence — the *widest* superset wins):
#   todo.md       — active/open rows (HD-267, zero-padded HD-03, ...)
#   the tracked tree (`git grep`, reports/ excluded) — owning docs, IaC and prompts carry HD-XX refs
#                   for related items, decisions and deploy-gates, wherever they happen to live.
#   git history    — every id any reachable commit WROTE, read off the diff lines of ONE
#                   `git log -p` pass. The aggregate form this header used to advertise,
#                   `git log -S 'HD-'`, lists the COMMITS whose per-path occurrence COUNT changed —
#                   not the ids those commits contain — and it goes quiet on a commit that swapped an
#                   id's row for its citation inside one file. See the history-half block below. The
#                   archived changelog was frozen → reports/changelog.md; it is NOT scanned
#                   (archive-only), in either half.
# next free = the smallest number above the tree max that no commit ever wrote, searched across a
# bounded candidate window. It is NOT `max+1`: a row deleted from todo.md stops counting in the tree
# while history keeps having written it, so the tree max can point straight at a used id.
#
# Parser intentionally lenient: matches `HD-03`, `HD-259B`, `HD-247–251`,
# `hd244+hd245`, `HD-260`, ... and takes the largest integer. Zero-padded ids
# sort numerically, never lexically (100 > 99).
#
# Usage:
#   bash scripts/next-hd.sh            # prints the next free id, "HD-<n>" (default; --next)
#   bash scripts/next-hd.sh --raw      # prints just the number (for scripting)
#   bash scripts/next-hd.sh --max      # prints the largest id standing in the tree (no history run)
#   bash scripts/next-hd.sh --max-raw  # prints that max as a bare number
#   FILES="todo.md" bash scripts/next-hd.sh   # restrict scan set (CI/debug)
#
# Environment (all `${VAR-default}`, so an empty override means "no filtering", never "re-apply the
# default" — the `${VAR:-default}` form cannot express that difference and turns the test into a lie):
#   FILES            restrict the tree scan to these files (turns the tree half off; see below)
#   RESERVED_IDS     ids filtered out of the max and of the candidate walk
#   RESERVED_RANGES  comma-separated <lo>-<hi> blocks filtered out the same way
#   GIT_SCAN         0 = skip the history half (debug, and the gate's "what would the tree half alone
#                    propose" probe). Loud when skipped: the tree half cannot see a deleted row.
#   CANDIDATE_WINDOW how many ids above the tree max the walk may examine before it refuses to mint
#
# Exit codes: 0 ok · 2 nothing parses, files unreadable, or the candidate window was exhausted — the
# script never prints an id it did not prove free (fail loud, never 0)
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
# 0 skips the history half — the reason, the cost and the tests for it are in the history-half block.
GIT_SCAN="${GIT_SCAN-1}"
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
# THE HISTORY HALF — an id that any commit already wrote is NOT free.
# The tree scan answers "which ids stand in a file today". That is not the same question as "which
# ids has this repo used", and the gap is the whole defect: a row minted and then deleted at
# close-out leaves the tree, the minter's max walks past it, and the next row gets a number that
# already has a history. Measured on the id this fix was written for:
# `git log --all --format=%h -S'HD-1184'` returns commits while the script called that number free.
# The aggregate sweep cannot save it either, and neither can the per-id form of it everywhere: `git
# log -S` asks "did the NUMBER of occurrences change on a path?", so a commit that swaps an id's row
# for its citation inside one file — one copy added, one deleted — answers "no", and an aggregate
# `-S 'HD-'` names commits rather than ids in the first place, so it can never be turned into an id
# list at all. A reused id never fails — it cross-links two rows and silently breaks
# `git log -S 'HD-XX'`, the prior-art sweep §0 is built on. So: test each candidate PER id
# (`git log --all -S"HD-<id>" --format=%h` non-empty ⇒ used), in addition to the tree-wide `git grep`
# half, and cache the answer instead of paying for a full-history walk per candidate.
#
# COST, and what is BOUNDED (measured at this commit, 3.4k commits, one minting run):
#   tree-wide `git grep`            ~0.1 s   once
#   one `git log -p` history pass   ~2.8 s   once per run — NEVER once per id: one `-S` probe costs
#                                            ~1.7 s, so walking upward from 1 is unusable at this size
#   one per-id `-S` probe           ~1.7 s   confirms the single id that is about to be printed
#   total                           ~4.5 s   — a pre-edit tool, not a per-commit one
# Bounded three ways: the pass runs ONCE per invocation and every later lookup reads its cached
# output; the walk examines at most CANDIDATE_WINDOW ids above the tree max and then REFUSES to mint
# (exit 2) instead of guessing; and `--max`/`--max-raw` never pay for history at all.
CANDIDATE_WINDOW="${CANDIDATE_WINDOW-16}"
# Did the CALLER restrict the scan set? Test BEFORE defaulting FILES, or the default assignment
# below makes every run look "restricted" and silently disables the tree scan — which is exactly how
# this patch failed its first test run (it printed 451, the very collision it was written to catch).
if [ -n "${FILES+set}" ]; then FILES_RESTRICTED=1; else FILES_RESTRICTED=0; fi
FILES="${FILES:-$DEFAULT_FILES}"

# --- collect every HD integer fragment from the given files -----------------
# Is there a history to scan at all? `next_free` says out loud which halves actually ran.
IN_GIT=0
command -v git >/dev/null 2>&1 && git -C "$SRC_REPO" rev-parse --git-dir >/dev/null 2>&1 && IN_GIT=1

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

# --- the two halves of "is this id free?" -------------------------------------------------------
# is_reserved <n> — fixture text and the fixture block are not backlog ids. The walk steps over them
# by the same two variables the max calculation filters by, so one rule cannot disagree with itself.
is_reserved() {
  local n="$1" t r lo hi
  for t in $RESERVED_IDS; do [ "$t" = "$n" ] && return 0; done
  for r in ${RESERVED_RANGES//,/ }; do
    lo="${r%%-*}"; hi="${r#*-}"; [ "$hi" = "$r" ] && hi="$lo"
    case "$lo$hi" in *[!0-9]*) continue ;; esac
    [ "$n" -ge "$lo" ] && [ "$n" -le "$hi" ] && return 0
  done
  return 1
}

# history_ids — every HD id any reachable commit wrote, one pass, no sorting: the ids a commit WROTE
# are read off the +/- diff LINES, because the count question is the wrong question (see above) and a
# line-level scan still sees the commit that only swapped an id's location. `--diff-merges=first-parent`
# keeps merge commits in the walk — plain `git log -p` prints no diff for a merge, so content that
# entered in a conflict resolution would otherwise be visible nowhere but the tree. Same scan set as
# the tree half (reports/ excluded: archive-only, so an id that survives ONLY there is an id no row
# holds).
history_ids() {
  git -C "$SRC_REPO" log --all --no-color --format='' -p -U0 --diff-merges=first-parent -- \
      . ':(exclude)reports' 2>/dev/null |
    grep -aoIE '[Hh][Dd][-_+–][0-9]+' | grep -oE '[0-9]+'
}

# sweep_id <n> — the per-id prior-art sweep, §0's own command. Non-empty ⇒ used. It is NOT a proof of
# absence (the count trap above), so it never runs alone: the pass is the wide net, this is the
# confirmation on the one id about to be printed, and the two disagreeing is worth hearing.
sweep_id() {
  git -C "$SRC_REPO" log --all --format=%h -S"HD-$1" -- . ':(exclude)reports' 2>/dev/null
}

# next_free — echo the bare number. Start above the largest id the tree still carries; step over
# anything the cached history pass wrote, over the reserved ids and block, and over anything the
# per-id sweep still names; stop at the first id nobody ever wrote.
next_free() {
  local c top hist="" hits n commits history_scanned=0
  if [ "$GIT_SCAN" = "1" ] && [ "$IN_GIT" = "1" ]; then
    commits="$(git -C "$SRC_REPO" rev-list --all --count 2>/dev/null || echo '?')"
    echo "next-hd: note: tree half = git grep (reports/ excluded); history half = one git log -p pass" \
         "over $commits commits + one per-id -S probe on the answer" >&2
    hist="$(history_ids)"
    # A pass that finds NOTHING is a broken pass, not an empty repo: every candidate would look free.
    if [ -z "$hist" ]; then
      echo "next-hd: fail: the history pass found no HD id in any commit — that is a broken scan, not" \
           "a clean repo (GIT_SCAN=0 skips this half deliberately)" >&2
      return 2
    fi
    history_scanned=1
  elif [ "$GIT_SCAN" != "1" ]; then
    echo "next-hd: warn: GIT_SCAN=$GIT_SCAN — the history half is SKIPPED, so a row deleted from the" \
         "tree is invisible here; check git log -S yourself before minting from this number" >&2
  else
    echo "next-hd: warn: not a git checkout — the history half did not run, so a row deleted from the" \
         "tree is invisible and this id is tree-proven only" >&2
  fi
  # 10# : a zero-padded id like HD-0009 parses as text and would otherwise be read as OCTAL here.
  top=$(( 10#$MAX_STR + CANDIDATE_WINDOW ))
  for (( c = 10#$MAX_STR + 1; c < top; c++ )); do
    is_reserved "$c" && continue
    if [ -n "$hist" ] && printf '%s\n' "$hist" | grep -qx "$c"; then
      echo "next-hd: note: HD-$c is written by a commit (cached history pass) — not free, walking on" >&2
      continue
    fi
    if [ "$history_scanned" = "1" ]; then
      hits="$(sweep_id "$c")"
      if [ -n "$hits" ]; then
        n="$(printf '%s\n' "$hits" | grep -c .)"
        echo "next-hd: note: HD-$c is named by the per-id sweep in $n commit(s) — walking on" >&2
        continue
      fi
    fi
    printf '%s\n' "$c"
    return 0
  done
  echo "next-hd: fail: no free id in the $CANDIDATE_WINDOW candidates above HD-$MAX_STR — the bounded" \
       "window is exhausted, so NOTHING is proposed. Raise CANDIDATE_WINDOW or fix the scan;" \
       "never hand-type the id." >&2
  return 2
}

# --- modes --------------------------------------------------------------
# Only the minting modes pay for the history half; --max reads the tree and returns.
mode="${1:-}"
case "$mode" in
  --max)
    printf 'HD-%s\n' "$MAX_STR"; exit 0 ;;
  --max-raw)
    printf '%s\n' "$MAX_STR"; exit 0 ;;
  ""|--next|--raw)
    : ;;
  *)
    echo "next-hd: unknown mode '$mode' (--raw | --max | --max-raw | --next)" >&2
    exit 1 ;;
esac
NEXT="$(next_free)" || exit 2
case "$mode" in
  --raw) printf '%s\n' "$NEXT" ;;
  *)     printf 'HD-%s\n' "$NEXT" ;;
esac