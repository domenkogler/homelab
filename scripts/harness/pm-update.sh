#!/usr/bin/env bash
#
# pm-update.sh — advance every PM-* checkout on this seat to the latest commit,
#                then merge PM-BE's dev branch into all PM-BE-* worktrees.
#
# Layout expected (checked and reported on every run):
#   PM-BE          standalone clone   -> branch dev
#   PM-FE          standalone clone   -> branch dev
#   PM-BE-auth     worktree of PM-BE  -> branch ai/auth
#   PM-BE-docs     worktree of PM-BE  -> branch ai/docs
#   PM-BE-sec      worktree of PM-BE  -> branch ai/security
#   PM-BE-sql      worktree of PM-BE  -> branch ai/sqlserver-tests
#   PM-BE-yt       worktree of PM-BE  -> branch ai/youtrack
#
# Portable: bash + git only. Runs on Debian, Debian under WSL, Windows git-bash.
#
# Usage:  ./pm-update.sh [options] [dir|name ...]
#
#   -d, --dir DIR        source root holding the PM-* dirs; authoritative when given
#                        (no fallthrough to other roots); default: auto-detect, PM_SOURCE_DIR
#   -p, --pattern GLOB   select checkouts by dir-name glob instead of the fixed
#                        target list, e.g. -p 'PM-*'
#   -r, --repo NAME      add one more checkout to the target list (repeatable)
#   -a, --autostash      stash local edits before pulling, restore afterwards
#       --skip-dirty     leave every dirty checkout alone (also the FE ones)
#       --allow-dirty    pull every dirty checkout, not only the FE ones
#   -R, --rebase         diverged checkout: pull --rebase instead of skipping
#       --add            check out PM-BE-* worktrees that are missing on disk
#       --push           push branches that gained local commits (merge commits)
#       --keep-conflict  leave a conflicted merge in place (default: abort it)
#       --no-merge       update only, skip the dev -> worktree merge phase
#       --no-fetch       do not fetch (report/merge from what is already local)
#   -n, --dry-run        show everything, change nothing   (-s is an alias)
#   -v, --verbose        show raw git output
#   -h, --help           this help
#
# Phases:
#   0. add     - only with --add: worktree add the PM-BE-* checkouts that are
#                missing here, each on the branch it is expected to hold
#   1. layout  - verify clone/worktree roles, repair stale worktree links
#   2. update  - git pull --ff-only each checkout onto its own upstream.
#              Dirty checkouts: PM-FE* is pulled anyway (default; edits are
#              never stashed and git refuses the pull if it would overwrite
#              them), everything else is left alone so local work is kept.
#              Tune with PM_DIRTY_ALLOW='<glob>', --skip-dirty, --allow-dirty.
#   3. merge   - merge PM-BE's dev into every PM-BE-* worktree
#   4. push    - only with --push
#
# Config via env: PM_SOURCE_DIR, PM_REPOS, PM_PATTERN, PM_DEV_BRANCH, PM_WT_MAP
# Exit code: 0 = nothing pending, 1 = something skipped/failed/conflicted.

set -uo pipefail

VERSION="2.5 (2026-11-04)"
TARGETS_DEFAULT="PM-BE PM-BE-auth PM-BE-docs PM-BE-sec PM-BE-sql PM-BE-yt PM-FE"
DEV_BRANCH="${PM_DEV_BRANCH:-dev}"
BE_NAME="PM-BE"
# worktree dir -> branch, for --add (a name left out falls back to ai/<suffix>)
WT_MAP="${PM_WT_MAP:-PM-BE-auth:ai/auth PM-BE-docs:ai/docs PM-BE-sec:ai/security PM-BE-sql:ai/sqlserver-tests PM-BE-yt:ai/youtrack}"

DRY=0 AUTOSTASH=0 DOREBASE=0 VERBOSE=0 PUSH=0 KEEP_CONFLICT=0 DO_MERGE=1 DO_FETCH=1 ADD_WT=0
DIRTY_MODE=auto    # auto = allow only for PM_DIRTY_ALLOW, skip the rest
DIRTY_ALLOW="${PM_DIRTY_ALLOW:-PM-FE*}"   # dirty checkouts that are pulled anyway
ROOT="${PM_SOURCE_DIR:-}"
PATTERN="${PM_PATTERN:-}"
EXTRA=() ARGDIRS=()

if [ -t 1 ]; then
  B=$'\033[1m'; OK=$'\033[32m'; WARN=$'\033[33m'; ERR=$'\033[31m'; DIM=$'\033[2m'; R=$'\033[0m'
else B=""; OK=""; WARN=""; ERR=""; DIM=""; R=""; fi

usage() { awk 'NR>2 { if (/^#/) { sub(/^# ?/, ""); print; next } exit }' "$0"; }
say() { printf '%s\n' "$*"; }
col() { printf '%-20s' "$1"; }
row() { ROWS="$ROWS
$(printf '  %-20s %-9s %-8s %s' "$1" "$2" "$3" "$4")"; }
run() { if [ $VERBOSE -eq 1 ]; then "$@"; else "$@" >/dev/null 2>&1; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--dir)    ROOT="${2:?--dir needs a path}"; shift 2 ;;
    -p|--pattern) PATTERN="${2:?--pattern needs a glob}"; shift 2 ;;
    -r|--repo)   EXTRA+=("${2:?--repo needs a name}"); shift 2 ;;
    -a|--autostash) AUTOSTASH=1; shift ;;
    --skip-dirty) DIRTY_MODE=skip; shift ;;
    --allow-dirty) DIRTY_MODE=allow; shift ;;
    -R|--rebase) DOREBASE=1; shift ;;
    --add)       ADD_WT=1; shift ;;
    --push)      PUSH=1; shift ;;
    --keep-conflict) KEEP_CONFLICT=1; shift ;;
    --no-merge)  DO_MERGE=0; shift ;;
    --no-fetch)  DO_FETCH=0; shift ;;
    -n|--dry-run|-s|--status) DRY=1; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    -*)          say "${ERR}$0: unknown option $1${R} (try --help)"; exit 2 ;;
    *)           ARGDIRS+=("$1"); shift ;;
  esac
done

# --------------------------------------------------------------- helpers ---
role_of() { if [ -f "$1/.git" ]; then echo worktree; else echo clone; fi; }

# parent checkout dir of a linked worktree ("" when it is a standalone clone)
parent_of() {
  local g
  [ -f "$1/.git" ] || return 0
  g=$(sed -n 's/^gitdir:[[:space:]]*//p' "$1/.git" 2>/dev/null | head -1)
  [ -n "$g" ] || return 0
  g=${g//\\//}
  case "$g" in */.git/worktrees/*) printf '%s' "${g%%/.git/worktrees/*}" ;; esac
}

# --------------------------------------------------------------- find root -
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
CAND=()
# An explicit -d/PM_SOURCE_DIR is a CONSTRAINT, never a hint: falling through to
# SCRIPT_DIR/$PWD/hardcoded candidates would let a run aimed at one root act on
# another, which is a different seat's working tree. Auto-detect only when no
# root was named.
if [ -n "$ROOT" ]; then
  [ -d "$ROOT" ] || { say "${ERR}$ROOT (--dir) is not a directory${R}"; exit 2; }
  CAND=("$ROOT")
else
  [ -n "$SCRIPT_DIR" ] && CAND+=("$SCRIPT_DIR")
  CAND+=("$PWD" "$HOME/source" "$HOME/source/stroka" /home/domen/source \
         /mnt/d/source/stroka /mnt/c/source/stroka "D:/source/stroka" "C:/source/stroka")
fi

SR=""
for r in "${CAND[@]}"; do
  [ -d "$r" ] || continue
  for d in "$r/$BE_NAME" "$r"/*/"$BE_NAME" "$r/PM-FE" "$r"/*/PM-FE; do
    [ -e "$d/.git" ] || continue
    if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      SR=$(CDPATH= cd -- "$d" && pwd); SR="${SR%/*}"; break 2
    fi
  done
done
[ -n "$SR" ] || { say "${ERR}No PM-BE/PM-FE checkout found${R} ${DIM}looked in: ${CAND[*]}${R}"
  [ -n "$ROOT" ] || say "${DIM}pass the root explicitly: $0 -d /path/to/source${R}"; exit 2; }

# ------------------------------------------------------------ target list --
TARGETS="${PM_REPOS:-$TARGETS_DEFAULT}"
for e in ${EXTRA+"${EXTRA[@]}"}; do TARGETS="$TARGETS $e"; done
[ ${#ARGDIRS[@]} -gt 0 ] && TARGETS=""

LIST=() OTHER=()
consider() {
  local d="$1" n="${1##*/}"
  [ -e "$d/.git" ] || return 0
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  case "$n" in PM-*) : ;; *) return 0 ;; esac
  if [ -n "$PATTERN" ]; then
    case "$n" in $PATTERN) LIST+=("$d") ;; *) OTHER+=("$d") ;; esac
    return 0
  fi
  case " $TARGETS " in *" $n "*) LIST+=("$d") ;; *) OTHER+=("$d") ;; esac
}
for base in "$SR" "$SR/stroka"; do
  [ -d "$base" ] || continue
  for d in "$base"/*/; do consider "${d%/}"; done
done
if [ ${#ARGDIRS[@]} -gt 0 ]; then
  LIST=()
  for a in "${ARGDIRS[@]}"; do
    [ -d "$a" ] || a="$SR/$a"
    if [ -e "$a/.git" ]; then LIST+=("$a"); else say "${WARN}skip $a (not a git checkout)${R}"; fi
  done
fi
[ ${#LIST[@]} -gt 0 ] || { say "${ERR}Nothing to update under $SR${R}"; exit 2; }

N_UPD=0 N_CUR=0 N_SKIP=0 N_FAIL=0 N_MERGED=0 N_DEV=0 N_CONF=0 N_ADD=0 ROWS=""
WT_LIST=()

# ---------------------------------------------------------------- update ---
update_repo() {
  local d="$1" n role br cur up remote rbr old new ahead behind dirty note dnote rowtail mode
  n="${d##*/}"; role=$(role_of "$d")
  cur=$(git -C "$d" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
  br="$cur"
  if [ -z "$br" ]; then
    say "  $(col "$n") ${WARN}detached HEAD - skipped${R}"
    row "$n" "$role" "skip" "detached HEAD"; N_SKIP=$((N_SKIP+1)); return 1
  fi

  remote=$(git -C "$d" config --get "branch.$br.remote" 2>/dev/null || echo origin)
  git -C "$d" remote get-url "$remote" >/dev/null 2>&1 || remote=origin
  if [ $DO_FETCH -eq 1 ]; then
    run git -C "$d" fetch --prune --quiet "$remote" || {
      say "  $(col "$n") ${ERR}fetch failed ($remote)${R}"
      row "$n" "$role" "FAIL" "fetch $remote"; N_FAIL=$((N_FAIL+1)); return 1; }
  fi

  up=$(git -C "$d" rev-parse --abbrev-ref --symbolic-full-name "$br@{upstream}" 2>/dev/null || echo "")
  if [ -z "$up" ] || [ "$up" = "HEAD" ]; then
    if git -C "$d" rev-parse --verify --quiet "refs/remotes/$remote/$br" >/dev/null 2>&1; then
      up="$remote/$br"
    else
      say "  $(col "$n") ${WARN}no upstream for $br - skipped${R}"
      row "$n" "$role" "skip" "no upstream"; N_SKIP=$((N_SKIP+1)); return 1
    fi
  fi
  rbr=""; case "$up" in "$remote"/*) rbr="${up#"$remote/"}" ;; esac

  old=$(git -C "$d" rev-parse --short HEAD)
  read -r ahead behind <<EOF
$(git -C "$d" rev-list --left-right --count "HEAD...$up" 2>/dev/null || echo "0 0")
EOF
  dirty=$(git -C "$d" status --porcelain=v1 2>/dev/null | wc -l | tr -d ' ')

  dnote="" rowtail=""
  if [ "$dirty" != "0" ] && [ $AUTOSTASH -eq 0 ]; then
    mode="$DIRTY_MODE"
    if [ "$mode" = auto ]; then
      case "$n" in $DIRTY_ALLOW) mode=allow ;; *) mode=skip ;; esac
    fi
    if [ "$mode" = skip ]; then
      say "  $(col "$n") ${WARN}dirty ($dirty file(s)) - left alone${R}"
      row "$n" "$role" "skip" "$br $old dirty"; N_SKIP=$((N_SKIP+1)); return 1
    fi
    dnote=" ${DIM}local edits kept ($dirty)${R}"; rowtail=" edits-kept"
    if [ "$ahead" != "0" ] && [ $DOREBASE -eq 1 ]; then
      say "  $(col "$n") ${WARN}dirty + diverged - needs -a${R}"
      row "$n" "$role" "skip" "$br $old dirty+diverged"; N_SKIP=$((N_SKIP+1)); return 1
    fi
  fi
  if [ "$behind" -eq 0 ]; then
    note="up to date"; [ "$ahead" != "0" ] && note="up to date (+$ahead local)"
    say "  $(col "$n") ${OK}$note${R} ${DIM}$br $old${R}$dnote"
    row "$n" "$role" "ok" "$br $old$rowtail"; N_CUR=$((N_CUR+1)); return 0
  fi
  if [ "$ahead" != "0" ] && [ $DOREBASE -eq 0 ]; then
    say "  $(col "$n") ${WARN}diverged (+$ahead/-$behind) - use -R${R}"
    row "$n" "$role" "skip" "$br $old diverged"; N_SKIP=$((N_SKIP+1)); return 1
  fi
  if [ $DRY -eq 1 ]; then
    say "  $(col "$n") ${B}would pull $behind commit(s)${R} ${DIM}$br $old -> $up${R}$dnote"
    row "$n" "$role" "dry" "$br $old -> $up$rowtail"; N_UPD=$((N_UPD+1)); return 0
  fi

  local -a cmd
  cmd=(git -C "$d" pull)
  [ $AUTOSTASH -eq 1 ] && cmd+=(--autostash)
  if [ "$ahead" != "0" ]; then cmd+=(--rebase); else cmd+=(--ff-only); fi
  if [ -n "$rbr" ]; then cmd+=("$remote" "$rbr"); else cmd+=("$up"); fi
  if run "${cmd[@]}"; then
    new=$(git -C "$d" rev-parse --short HEAD)
    if [ "$new" != "$old" ]; then
      say "  $(col "$n") ${OK}updated $old -> $new${R} ${DIM}$br: $(git -C "$d" log -1 --format=%s | cut -c1-52)${R}$dnote"
    else
      say "  $(col "$n") ${OK}up to date${R} ${DIM}$br $old${R}$dnote"
    fi
    row "$n" "$role" "pull" "$br $old -> $new$rowtail"; N_UPD=$((N_UPD+1))
  else
    if [ "$dirty" != "0" ] && [ $AUTOSTASH -eq 0 ]; then
      say "  $(col "$n") ${WARN}pull refused - local edits overlap incoming files${R} ${DIM}$br $old${R}"
      say "      ${DIM}resolve/stash by hand, or run: $0 -a${R}"
      row "$n" "$role" "skip" "$br $old dirty-blocked"; N_SKIP=$((N_SKIP+1)); return 1
    fi
    say "  $(col "$n") ${ERR}pull failed${R} ${DIM}$br $old${R}"
    row "$n" "$role" "FAIL" "$br $old"; N_FAIL=$((N_FAIL+1)); return 1
  fi
}

# ------------------------------------------------------------- merge dev ---
merge_dev_into() {
  local d="$1" ref="$2" n br count old new
  n="${d##*/}"
  br=$(git -C "$d" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "?")
  if [ -n "$(git -C "$d" status --porcelain=v1 2>/dev/null)" ]; then
    say "  $(col "$n") ${WARN}dirty - dev merge skipped${R}"
    row "$n" "worktree" "skip" "dev merge (dirty)"; N_SKIP=$((N_SKIP+1)); return 1
  fi
  count=$(git -C "$d" rev-list --count "HEAD..$ref" 2>/dev/null || echo 0)
  old=$(git -C "$d" rev-parse --short HEAD)
  if [ "$count" = "0" ]; then
    say "  $(col "$n") ${DIM}dev already merged${R} ${DIM}$br $old${R}"
    row "$n" "worktree" "ok" "dev in $br"; N_DEV=$((N_DEV+1)); return 0
  fi
  if [ $DRY -eq 1 ]; then
    say "  $(col "$n") ${B}would merge $count commit(s) of $DEV_BRANCH${R} ${DIM}into $br $old${R}"
    row "$n" "worktree" "dry" "dev($count) into $br"; N_MERGED=$((N_MERGED+1)); return 0
  fi
  if run git -C "$d" merge --no-edit "$ref"; then
    new=$(git -C "$d" rev-parse --short HEAD)
    say "  $(col "$n") ${OK}merged dev $old -> $new${R} ${DIM}$br (+$count)${R}"
    row "$n" "worktree" "merge" "dev into $br $old -> $new"; N_MERGED=$((N_MERGED+1)); return 0
  fi
  N_CONF=$((N_CONF+1))
  if [ $KEEP_CONFLICT -eq 0 ]; then
    git -C "$d" merge --abort >/dev/null 2>&1
    say "  $(col "$n") ${ERR}conflict merging dev - aborted${R} ${DIM}then: git -C \"$d\" merge --no-edit $ref${R}"
    row "$n" "worktree" "conflict" "dev into $br (aborted)"
  else
    say "  $(col "$n") ${ERR}conflict merging dev - left in place${R}"
    row "$n" "worktree" "conflict" "dev into $br (RESOLVE)"
  fi
  return 1
}

# ------------------------------------------------- add missing worktrees ---
# branch a PM-BE-<suffix> worktree is expected to hold (WT_MAP, see PM_WT_MAP)
branch_for() {
  local n="$1" p
  for p in $WT_MAP; do
    [ "${p%%:*}" = "$n" ] && { printf '%s' "${p#*:}"; return 0; }
  done
  printf 'ai/%s' "${n#"$BE_NAME"-}"
}

# worktree add every PM-BE-* name we expect that has no checkout on this seat
add_worktrees() {
  local be="$SR/$BE_NAME" list="$TARGETS" seen=" " n d br found=0
  [ -n "$list" ] || list="$TARGETS_DEFAULT"
  for n in ${ARGDIRS[@]+"${ARGDIRS[@]}"}; do list="$list ${n##*/}"; done
  for n in ${LIST[@]+"${LIST[@]}"}; do list="$list ${n##*/}"; done
  say "${B}add worktrees${R}"
  if [ ! -e "$be/.git" ]; then
    say "  ${DIM}no $BE_NAME clone under $SR - nothing to add${R}"
    N_FAIL=$((N_FAIL+1)); say ""; return 0
  fi
  run git -C "$be" worktree prune
  for n in $list; do
    case "$n" in "$BE_NAME"-*) : ;; *) continue ;; esac
    case "$seen" in *" $n "*) continue ;; esac
    seen="$seen$n "
    d="$SR/$n"
    [ -e "$d/.git" ] && continue
    found=1
    if [ -e "$d" ]; then
      say "  $(col "$n") ${ERR}$d exists but is not a checkout - left alone${R}"
      N_FAIL=$((N_FAIL+1)); continue
    fi
    br=$(branch_for "$n")
    if [ $DRY -eq 1 ]; then
      say "  $(col "$n") ${B}would worktree add $br${R} ${DIM}$d${R}"; continue
    fi
    if run git -C "$be" worktree add "$d" "$br"; then
      LIST+=("$d"); N_ADD=$((N_ADD+1))
      say "  $(col "$n") ${OK}checked out $br${R} ${DIM}$d${R}"
    else
      say "  $(col "$n") ${ERR}worktree add $br failed${R} ${DIM}branch on no remote, or held by another worktree${R}"
      N_FAIL=$((N_FAIL+1))
    fi
  done
  [ $found -eq 0 ] && say "  ${DIM}nothing missing - every expected worktree is on disk${R}"
  say ""
}

# ------------------------------------------------------------------ run it -
DRYTAG=""; [ $DRY -eq 1 ] && DRYTAG="  ${WARN}[dry-run]${R}"
say "${B}pm-update $VERSION${R} ${DIM}$SR${R} ${DIM}$(date '+%Y-%m-%d %H:%M')${R}$DRYTAG"
say ""
if [ $ADD_WT -eq 1 ]; then add_worktrees; fi
say "${B}layout${R}"
for d in "${LIST[@]}"; do
  n="${d##*/}"; role=$(role_of "$d")
  br=$(git -C "$d" symbolic-ref --quiet --short HEAD 2>/dev/null || echo detached)
  case "$n" in
    "$BE_NAME"|PM-FE) want=clone ;;
    "$BE_NAME"-*)    want=worktree ;;
    *)                want="" ;;
  esac
  extra=""
  if [ "$role" = worktree ]; then
    par=$(parent_of "$d"); extra=" ${DIM}of ${par:-?}${R}"
    if [ "$want" = clone ]; then tag="${ERR}worktree (expected clone)${R}"; N_FAIL=$((N_FAIL+1))
    elif [ "$want" = worktree ] && [ "${par##*/}" != "$BE_NAME" ]; then
      tag="${WARN}worktree of ${par##*/}${R} (expected $BE_NAME)"; N_FAIL=$((N_FAIL+1))
    else tag="${OK}$role${R}"; fi
  else
    if [ "$want" = worktree ]; then tag="${ERR}clone (expected worktree)${R}"; N_FAIL=$((N_FAIL+1))
    else tag="${OK}$role${R}"; fi
  fi
  [ -n "$want" ] || tag="${DIM}$role${R}"
  say "  $(col "$n") $tag ${DIM}[$br]${R}$extra"
done

# repair links between the clones and their worktrees (no-op when already fine)
for d in "${LIST[@]}"; do
  [ "$(role_of "$d")" = clone ] || continue
  case "${d##*/}" in "$BE_NAME"|PM-FE) ;; *) continue ;; esac
  for w in "${LIST[@]}"; do
    [ "$w" = "$d" ] && continue
    [ "$(role_of "$w")" = worktree ] || continue
    [ "$(parent_of "$w")" = "$d" ] && run git -C "$d" worktree repair "$w"
  done
done

# which worktrees must receive dev
for d in "${LIST[@]}"; do
  [ "$(role_of "$d")" = worktree ] || continue
  case "$(parent_of "$d")" in */"$BE_NAME") WT_LIST+=("$d") ;; esac
done

BE="$SR/$BE_NAME"
DEVREF=""
[ -e "$BE/.git" ] && DEVREF=$(git -C "$BE" rev-parse --verify --quiet "refs/heads/$DEV_BRANCH" 2>/dev/null || echo "")

say ""
say "${B}update${R}"
for d in "${LIST[@]}"; do update_repo "$d"; done

if [ $DO_MERGE -eq 1 ]; then
  say ""
  say "${B}merge $DEV_BRANCH -> $BE_NAME worktrees${R}"
  if [ ${#WT_LIST[@]} -eq 0 ]; then
    say "  ${DIM}no $BE_NAME worktrees in the target list${R}"
  elif [ -z "$DEVREF" ]; then
    say "  ${WARN}no local '$DEV_BRANCH' branch in $BE_NAME - merge skipped${R}"; N_SKIP=$((N_SKIP+1))
  else
    for d in "${WT_LIST[@]}"; do merge_dev_into "$d" "refs/heads/$DEV_BRANCH"; done
  fi
fi

if [ $PUSH -eq 1 ]; then
  say ""
  if [ $DRY -eq 1 ]; then
    say "${B}push${R} ${DIM}(skipped in dry-run)${R}"
  else
    say "${B}push${R}"
    for d in "${LIST[@]}"; do
      br=$(git -C "$d" symbolic-ref --quiet --short HEAD 2>/dev/null) || continue
      a=$(git -C "$d" rev-list --count "@{u}...HEAD" 2>/dev/null | awk '{print $2}')
      [ "${a:-0}" = "0" ] && continue
      if run git -C "$d" push origin "HEAD:refs/heads/$br"; then
        say "  $(col "${d##*/}") ${OK}pushed $br (+$a)${R}"
      else
        say "  $(col "${d##*/}") ${ERR}push refused${R} ${DIM}$br${R}"; N_FAIL=$((N_FAIL+1))
      fi
    done
  fi
fi

if [ ${#OTHER[@]} -gt 0 ]; then
  say ""
  say "${DIM}PM-* dirs outside the target list (add with -r NAME or use -p 'PM-*'):${R}"
  for d in "${OTHER[@]}"; do say "  ${DIM}$(col "${d##*/}") [$(role_of "$d")]${R}"; done
fi

say ""
ADDTAG=""; [ $ADD_WT -eq 1 ] && ADDTAG="added $N_ADD  "
say "${B}summary${R}  $ADDTAG${OK}current $N_CUR${R}  ${OK}pulled $N_UPD${R}  ${OK}dev-merged $N_MERGED${R}  ${DIM}dev already in $N_DEV${R}  ${WARN}skipped $N_SKIP${R}  ${ERR}conflict $N_CONF${R}  ${ERR}failed $N_FAIL${R}$DRYTAG"
[ -n "$ROWS" ] && printf '%s\n' "$ROWS"
[ $N_SKIP -eq 0 ] && [ $N_FAIL -eq 0 ] && [ $N_CONF -eq 0 ] && exit 0
exit 1
