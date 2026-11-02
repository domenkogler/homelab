#!/usr/bin/env bash
# =====================================================================
# gate-snapshot.sh — the driver that moves a GRADED COMMIT into the Debian engine's own
# ext4 with GIT ONLY, stamps the commit it graded, and (with --run) spends exactly ONE
# engine round trip on the whole tree face.
#
# WHY THIS EXISTS (the fact that makes it more than a clone command): the win11 seat's
# launcher pays 16-150 ms per fork, so the same commit that grades in about a minute on
# the engine's ext4 takes ten-to-twenty minutes across the /mnt mount — and the snapshot
# is how the tree face buys the engine's price without a second item list. It is a
# SNAPSHOT, not a seat: a standing clone at a fixed path may never be reported as a
# win11 verdict, and the commit stamp is what keeps that honest (docs/harness-pi-seats.md
# §1; lib/wsl-route.sh's header refuses to call a mounted clone an engine verdict either).
# GIT ONLY, never a file copier, because four legs read HISTORY
# (check_string_twins.py's baseline rev, check_hd_mint_space.py, check_todo_history.py,
# check_bench_provenance.py) and a working-tree copy has none of it.
#
# THE RECIPE, as the driver runs it (this header is the SSOT: the hand-typed form that
# A7's brief carried is retired, and nowhere else writes it down):
#
#   # first run — a git clone INTO the engine's own filesystem (ext4, not /mnt):
#   wsl.exe -d Debian -u domen -- bash -c \
#     'git clone -q --no-hardlinks /mnt/d/source/domenkogler/homelab ~/gate-snap/homelab'
#   # every run — fetch, force the detached checkout, clean, and PROVE the HEAD:
#   wsl.exe -d Debian -u domen -- bash -c \
#     'cd ~/gate-snap/homelab && git fetch -q <src-git> <branch> \
#      && git checkout -qf --detach FETCH_HEAD && git clean -fdq && git log --oneline -1'
#   # a dirty tree, ONLY under --carry, inside the SAME spawn as the checkout above:
#   git diff HEAD            → a patch the guest applies with `git apply --index`
#   git ls-files --others    → ONE tar stream the guest extracts over the stamped base
#
# One spawn per run is the whole point on this seat: a round trip across the door costs about what a
# leg costs, so the driver builds ONE guest script — move, prove, stamp, carry, grade — and spends ONE
# `wsl.exe` on it. Carrying is what makes the tree face honest about uncommitted work: it lands on top
# of the VERIFIED base commit and is named, never graded as if it were committed.
#
# WHAT WENT WRONG WITHOUT THE TEETH (2026-11-01, this is why every step verifies): a
# station snapshot drifted dirty, git refused the checkout, the `&&` chain stopped, and
# a full gate silently graded a FIVE-MINUTE-OLD commit and printed a verdict that
# belonged to nothing. So: `checkout -f` and `clean -fdq` (never a polite checkout), the
# synced HEAD is compared to the graded sha INSIDE the sync, the stamped sha is printed
# on every sync, and a dirty tree is carried loudly (patch + tar) or REFUSED with the
# exact command — never graded as a silent mix.
#
# MODES
#   --run [--only SUB] [--profile P]   sync, then run `bash scripts/validate-all.sh --face tree`
#                                      IN the snapshot: one spawn, the engine pools its own
#                                      legs natively. What validate-all.sh --face auto (split)
#                                      launches here. Refuses a dirty tree unless --carry.
#   --sync                             bring the snapshot to the graded commit, print `graded: <sha>`.
#   --check                            same sync + the HEAD proof, and NOTHING else — grades without
#                                      running the gate (the receipt the brief asked for).
#   --verify                           no fetch: snapshot HEAD == stamp == the commit to grade AND the
#                                      snapshot's own tree clean, or FAIL. The third condition is the
#                                      `--carry` residue: HEAD and the stamp still agree after a previous
#                                      `--sync --carry`, so a two-condition verify reads GREEN with carried
#                                      bytes on top — a graded `--run` cannot inherit them (it cleans before
#                                      the checkout) but a gate typed by hand inside that snapshot does.
#   --self-test                        the arms on a MINTED fixture repo over the LOCAL door (no engine, no wsl.exe), and the
#                                      run prints its own count: no-snapshot first run · a planted stale file gone after a
#                                      sync · stamp matches · a snapshot left behind the graded commit reddens · a dirty tree
#                                      refuses by default and carries on purpose · --verify's SENTENCE both ways (agreement,
#                                      and a stamp on another commit) · --verify names a snapshot still carrying --carry ·
#                                      `--face auto` inside a stamped snapshot selects the TREE face and a disagreeing stamp
#                                      selects NO face · the forced-local-door policy · one-writer-per-snapshot lock · the
#                                      stamp names who last synced it.
#   --carry                            modifier: tracked edits as a patch + untracked files as ONE
#                                      tar stream, both applied INTO the snapshot in the same spawn,
#                                      each named.
#
# SEAMS (every engine touch goes through ONE spawn, and a fixture injects it):
#   HL_SNAP_DIR     the snapshot path IN THE ENGINE's spelling (default "$HOME/gate-snap/homelab";
#                   an absolute local path is what a stub-door fixture plants it as).
#                   ONE WRITER PER SNAPSHOT — the path is SHARED STATE, so two lanes pointed at the same
#                   snapshot grade WHICHEVER TREE SYNCED LAST: each run's HEAD proof and stamp agree with
#                   itself perfectly and neither describes the tree the other is about to read. The rule is
#                   that a concurrent lane sets HL_SNAP_DIR to its OWN path ($HOME/gate-snap/<lane>), and the
#                   driver enforces it two ways, both cheap: a mkdir-atomic sibling `$SNAP.lock` holding a
#                   holder line, taken INSIDE the one spawn and refused (rc 4) while a holder younger than
#                   HL_SNAP_TIMEOUT still stands (a lock past that wall came from a spawn the wall killed),
#                   and an ORIGIN field on the stamp — the graded repo's path, kept in the THIRD field
#                   because validate-all.sh's face block reads field 1 only — so `--verify` prints WHO last
#                   moved the tree it is about to certify.
#   HL_SNAP_DOOR    auto | local. auto = wsl.exe when this box classifies as win11, local when the
#                   box IS the engine. local is what --self-test forces.
#                   THE TRAP WHEN FORCED: `local` asserts "the engine is THIS bash". On the win11 class that
#                   bash is Git-Bash on the NTFS mount, so with no HL_SNAP_DIR the DEFAULT path resolves
#                   $HOME in the CALLER's home and the snapshot lands where the engine has no view of it —
#                   measured on this seat: a bare `HL_SNAP_DOOR=local … --sync` minted
#                   C:\Users\domen\gate-snap\homelab, the exact mount the driver exists to avoid, silently.
#                   `_snap_door_policy` refuses THAT combination before anything moves; an explicit
#                   HL_SNAP_DIR is still allowed, because that is how --self-test injects a fixture and a
#                   caller who spells the path chose the filesystem with eyes open.
#   HL_SNAP_REPO    the repo whose commit is graded (default: the repo this file lives in).
#   HL_SNAP_TIMEOUT wall in seconds on every spawn (a spawn that blocks on a half-open door is a
#                   lane lost — stdin is CLOSED on every spawn, CONVENTIONS §6).
# =====================================================================
set -uo pipefail

SELF="scripts/harness/gate-snapshot.sh"
_snap_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The same script by the path the shell found it at: the self-test arms spawn THEIR OWN driver, and a
# relative path only resolves while nobody has moved — a fixture that cd-s would exec nothing and report
# an arm that passed.
SELF_FILE="$_snap_here/$(basename "${BASH_SOURCE[0]}")"
HL_ROOT="$(cd "$_snap_here/../.." && pwd)"
# shellcheck source=/dev/null
source "$HL_ROOT/scripts/lib/wsl-route.sh"

MODE=""; ONLY=""; PROFILE="full"; CARRY=0
CARRY_PATCH=""; CARRY_TAR=""; CARRY_TMP=""   # the --carry material, filled by _snap_materialize
while [ $# -gt 0 ]; do
  case "$1" in
    --run) MODE=run ;;
    --sync | --check | --verify | --self-test) MODE="${1#--}" ;;
    --carry) CARRY=1 ;;
    --only) shift; [ $# -gt 0 ] || { echo "error: --only needs a substring" >&2; exit 2; }; ONLY="$1" ;;
    --only=*) ONLY="${1#--only=}" ;;
    --profile) shift; [ $# -gt 0 ] || { echo "error: --profile needs a name" >&2; exit 2; }; PROFILE="$1" ;;
    --profile=*) PROFILE="${1#--profile=}" ;;
    -h | --help) echo "usage: bash $SELF --run|--sync|--check|--verify|--self-test [--carry] [--only SUB] [--profile P]"; exit 0 ;;
    *) echo "FAIL: $SELF: unknown argument '$1'." >&2; exit 2 ;;
  esac
  shift
done

SNAP_REPO="${HL_SNAP_REPO:-$HL_ROOT}"
SNAP_LIMIT="${HL_SNAP_TIMEOUT:-3600}"
[ -n "${HL_SNAP_DOOR:-}" ] || HL_SNAP_DOOR=auto

_snap_class="$(hl_wsl_class)"
case "$HL_SNAP_DOOR" in
  auto)
    case "$_snap_class" in
      win11) SNAP_DOOR=remote ;;
      win11-nodoor) SNAP_DOOR=none ;;        # no engine reachable — say so, never run half a face
      *) SNAP_DOOR=local ;;                  # the box IS an engine (or has no door to cross)
    esac ;;
  local) SNAP_DOOR=local ;;
  *) echo "FAIL: $SELF: HL_SNAP_DOOR wants auto | local, not '$HL_SNAP_DOOR'." >&2; exit 2 ;;
esac

# _snap_door_policy <class> <door> <dir-set> — rc 0 proceed, rc 1 refuse with the reason on stdout.
# Arguments instead of readings, the same reason `hl_wsl_class` takes a uname string: the rule is about the
# CLASS, so the arm that grades it must answer the same way on the engine as on the Windows seat. What it
# refuses is the measured trap in the HL_SNAP_DOOR note — a FORCED local door on a Windows class with the
# DEFAULT snapshot path, which resolves $HOME wherever the CALLER's home is (a Windows directory the engine
# never sees), while the class-derived door would have chosen the engine. An explicit HL_SNAP_DIR is not
# refused: that is the fixture seam, and the caller named the filesystem.
_snap_door_policy() {
  local cls="${1:-}" door="${2:-}" dir_set="${3:-0}"
  [ "$door" = local ] || return 0
  case "$cls" in win11 | win11-nodoor) ;; *) return 0 ;; esac
  [ "$dir_set" = 1 ] && return 0
  echo "REFUSE: HL_SNAP_DOOR=local on a $cls box runs the engine half in THIS bash, so the default snapshot path resolves \$HOME where the ENGINE has no view of it — on this seat that is a Windows directory on the NTFS mount this driver exists to avoid (measured: a bare local-door --sync minted C:\\Users\\<user>\\gate-snap\\homelab). Either drop HL_SNAP_DOOR and let the seat class choose the door, or set HL_SNAP_DIR to the path the engine spells — that is what --self-test does for its fixtures. NOTHING was graded."
  return 1
}

# The policy is applied to a snapshot run only. --self-test IS not one: it mints fixtures and injects its
# own HL_SNAP_DIR into every arm, so the top-level environment says nothing about where an arm writes, and
# refusing there would stop the arms that grade this very rule.
if [ "$MODE" != self-test ] && [ "$SNAP_DOOR" = local ]; then
  _snap_dir_set=0
  [ -n "${HL_SNAP_DIR:-}" ] && _snap_dir_set=1
  _snap_door_policy "$_snap_class" "$SNAP_DOOR" "$_snap_dir_set" || exit 3
fi

# _snap_sq <s> — shell-quote for one WORD inside the guest script. DEFINED BEFORE ITS TOP-LEVEL
# CALL (the SNAP_ASSIGN block below) and the two stay adjacent on purpose: a function defined after
# the line that calls it inside $( ) is no function yet when that line runs — the substitution answered
# empty, the guest cloned into nothing, and every fixture-driven child (every --self-test arm) died
# several layers away from the cause. Same DOA family as the fixed `echo <unstamped>`.
_snap_sq() { local s="${1//\'/\'\\\'\'}"; printf "'%s'" "$s"; }
# The snapshot path AS THE ENGINE SPELLS IT. With no HL_SNAP_DIR the assignment carries $HOME
# UNEXPANDED so the GUEST shell resolves it in the guest's own home; a fixture (or an operator)
# that sets HL_SNAP_DIR gets its value embedded VERBATIM — it is then the caller's job to spell
# the path the way the engine reads it (that is what makes the seam honest, not clever).
SNAP_ASSIGN='SNAP="$HOME/gate-snap/homelab"'
if [ -n "${HL_SNAP_DIR:-}" ]; then SNAP_ASSIGN="SNAP=$(_snap_sq "$HL_SNAP_DIR")"; fi

# _snap_want — the commit to grade: HEAD of the repo being graded. Also the two dirty facts,
# which the POLICY below turns into either a carry or a refusal — never a silent mix.
SNAP_WANT=""; SNAP_SRC=""; DIR_TRACKED=0; DIR_UNtracked=0
_snap_want() {
  SNAP_WANT="$(git -C "$SNAP_REPO" rev-parse HEAD 2>/dev/null)" || return 1
  local d
  d="$(git -C "$SNAP_REPO" rev-parse --git-common-dir 2>/dev/null)" || return 1
  # ABSOLUTE in EITHER spelling: git-for-windows answers a drive letter (`D:/…/.git`) where the
  # engine answers `/home/…/.git`, and prefixing the first with $SNAP_REPO is how the source dir
  # becomes `/…/homelab-wt-…/D:/source/…` and every later git call dies on it.
  case "$d" in /* | [A-Za-z]:[\/]*) : ;; *) d="$SNAP_REPO/$d" ;; esac
  SNAP_SRC="$d"
  if [ "$SNAP_DOOR" = remote ]; then
    SNAP_SRC="$(hl_wsl_mntpath "$d")" || { echo "FAIL: $SELF: the repo's git dir has no /mnt spelling: $d" >&2; return 1; }
  fi
  DIR_TRACKED=0; DIR_UNtracked=0
  git -C "$SNAP_REPO" diff --quiet HEAD -- || DIR_TRACKED=1
  [ -n "$(git -C "$SNAP_REPO" ls-files --others --exclude-standard | head -1)" ] && DIR_UNtracked=1
  return 0
}

_snap_refuse_dirty() {
  echo "REFUSE: the working tree is DIRTY ($([ "$DIR_TRACKED" = 1 ] && printf 'tracked edits')$([ "$DIR_TRACKED" = 1 ] && [ "$DIR_UNtracked" = 1 ] && printf ' + ')$([ "$DIR_UNtracked" = 1 ] && printf 'untracked files')) — the snapshot would grade a MIX of HEAD and uncommitted work and call it HEAD's verdict. One of, exactly:"
  echo "  1. commit in $SNAP_REPO, then: bash $SELF --run"
  echo "  2. carry it ON PURPOSE: bash $SELF --run --carry   (tracked edits as a patch, untracked files as ONE tar stream, both NAMED)"
  echo "  3. grade here instead: HL_FACE=both bash scripts/validate-all.sh"
  echo "Nothing was graded."
}


# _snap_verify_script — no fetch, no move: HEAD and stamp must BOTH answer the graded commit, and the
# tree they describe must be the tree that is actually there. The third condition is what a HEAD-vs-stamp
# compare cannot see: a snapshot left by an earlier `--sync --carry` agrees with itself perfectly while
# carrying bytes on top of the stamp, and `--verify` is the mode a human reaches for before typing a gate
# by hand IN the snapshot — the one place those bytes get graded (a `--run` cleans first, so it cannot).
_snap_verify_script() {
  printf 'set -e\n%s\nWANT=%s\n' "$SNAP_ASSIGN" "$(_snap_sq "$1")"
  cat <<'GUEST'
if [ ! -d "$SNAP/.git" ]; then
  echo "FAIL: no snapshot at $SNAP yet — first run needs a sync: bash scripts/harness/gate-snapshot.sh --sync"
  exit 3
fi
# IGNORE-RESPECTING on purpose: `status --porcelain` (not `--ignored`, not `ls-files -o`) is the half a
# checkout/compare cannot see — carried edits and carried untracked files — while the artifacts a graded run
# legitimately leaves in the snapshot (`__pycache__`, a bench scratch path) are ignored and stay out of it.
DIRTY_NOW="$(git -C "$SNAP" status --porcelain | head -1)"
HEAD_NOW="$(git -C "$SNAP" rev-parse HEAD)"
STAMP_SHA="$(cut -d' ' -f1 "$SNAP.stamp" 2>/dev/null || echo '<unstamped>')"
# WHO last synced the tree — the question HEAD-vs-stamp cannot answer, because two lanes sharing one
# snapshot each leave a stamp that agrees with the HEAD they moved it to. The origin is the stamp's THIRD
# field (field 1 is what validate-all.sh's face block reads), so a stamp written before the field exists
# says so rather than printing an empty name. The `|| echo` is not decoration: an absent stamp makes `cut`
# exit 1, and inside this `set -e` guest an unguarded assignment would end the script RIGHT THERE — a
# silent rc 1 with no sentence, the same dead-on-arrival family as the `echo <unstamped>` redirect.
STAMP_ORIGIN="$(cut -d' ' -f3- "$SNAP.stamp" 2>/dev/null || echo '')"
if [ -z "$STAMP_ORIGIN" ]; then STAMP_ORIGIN='<no origin recorded — a stamp written before the origin field>'; fi
HELD=""
if [ -d "$SNAP.lock" ]; then HELD="$(cut -c1-160 "$SNAP.lock/holder" 2>/dev/null || echo '<no holder line>')"; fi
if [ "$HEAD_NOW" != "$WANT" ] || [ "$STAMP_SHA" != "$WANT" ]; then
  echo "FAIL: the snapshot is not the graded commit — HEAD $HEAD_NOW · stamped $STAMP_SHA · to grade $WANT. Run --sync; a stale stamp is why a gate once printed a verdict that belonged to nothing."
  exit 1
fi
if [ -n "$DIRTY_NOW" ]; then
  echo "FAIL: HEAD and the stamp both name $WANT, but this snapshot's TREE is DIRTY on top of it — the first entry is '$DIRTY_NOW' — bytes a previous --carry left behind, or a hand edit. --verify REFUSES: a gate typed by hand in this checkout would grade a tree no stamp describes. Run --sync for the stamped tree, or --run --carry if a carried tree is what you mean to grade."
  exit 1
fi
echo "graded: $WANT (verified: HEAD and stamp agree)"
echo "stamped by: $STAMP_ORIGIN"
if [ -n "$HELD" ]; then
  echo "note: $SNAP.lock is held RIGHT NOW by $HELD — another lane has this snapshot open, and its next --sync moves the tree you are about to grade."
fi
GUEST
}

# _snap_scratch — a directory BOTH seats can read, for the run script and the --carry material. Inside
# the git dir, so nothing lands in a worktree where the corpus walk would count it as an untracked file;
# absolute in either spelling, because git-for-windows answers `--git-common-dir` with a drive letter.
_snap_scratch() {
  local gk
  gk="$(git -C "$SNAP_REPO" rev-parse --git-common-dir)" || return 1
  case "$gk" in /* | [A-Za-z]:[\/]*) : ;; *) gk="$SNAP_REPO/$gk" ;; esac
  SNAP_TMP="$(mktemp -d "$gk/gate-snap-run.XXXXXX")" || return 1
  printf '%s\n' "$SNAP_TMP"
}

# _snap_spawn <script> — the ONE engine touch. The script goes to a FILE and the spawn carries ONE argv
# word, never the script itself: a multi-line program with `"$SNAP"`-shaped quoting inside is exactly
# what a Windows seat's argv layer mangles on its way through `timeout` and `wsl.exe` into the guest's
# bash, and the mangled form fails as an empty `git -C` argument several layers away from the cause. A path cannot
# mangle, and the file is written by the same seat that wrote the checkout recipe. stdin stays CLOSED
# (stdin IS the parent's — CONVENTIONS §6 — and a door spawn that inherits a terminal is a frozen lane),
# and every spawn stays walled by HL_SNAP_TIMEOUT.
_snap_spawn() {
  local _script="$1" _f="" _rc=0
  if [ "$SNAP_DOOR" = remote ]; then
    local _dir _gf
    _dir="$(_snap_scratch)" || return 1
    _f="$_dir/run.sh"
    printf '%s\n' "$_script" >"$_f" || { rm -rf "$_dir"; return 1; }
    _gf="$(hl_wsl_mntpath "$_f")" || { rm -rf "$_dir"; return 1; }
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'       timeout "$SNAP_LIMIT" "$HL_WSL_EXE" -d "$HL_WSL_DISTRO" -- bash "$_gf" < /dev/null
    _rc=$?
    rm -rf "$_dir"
    return $_rc
  fi
  _f="$(mktemp)" || return 1
  printf '%s\n' "$_script" >"$_f" || { rm -f "$_f"; return 1; }
  timeout "$SNAP_LIMIT" bash "$_f" < /dev/null
  _rc=$?
  rm -f "$_f"
  return $_rc
}

_snap_script() { # -> stdout; $1=want $2=src (both host-resolved already) $3=1 to run the tree face
  local _want="$1" _src="$2" _grade="${3:-0}" _gate _holder
  # The holder line names the LANE, which in this repo means the worktree whose commit is being graded,
  # plus the pid of the driver that took the lock — enough for a refused lane to say who to go ask.
  _holder="$SNAP_REPO head=$(printf '%s' "$_want" | cut -c1-12) pid=$$"
  printf 'set -e\n%s\nSRC=%s\nWANT=%s\nHOLDER=%s\nORIGIN=%s\nLOCK_LIMIT=%s\n' \
    "$SNAP_ASSIGN" "$(_snap_sq "$_src")" "$(_snap_sq "$_want")" "$(_snap_sq "$_holder")" \
    "$(_snap_sq "$SNAP_REPO")" "$SNAP_LIMIT"
  cat <<'GUEST'
STAMP="$SNAP.stamp"
# ONE WRITER PER SNAPSHOT (the HL_SNAP_DIR seam in the header): the lock is the sibling DIRECTORY, taken
# with `mkdir` because that is the one operation both filesystems here make atomic, and taken INSIDE this
# spawn so the rule costs no extra door trip. A lock can outlive its writer only through a spawn that was
# killed, and HL_SNAP_TIMEOUT is the wall that spawn ran under — older than the wall is a stale lock.
mkdir -p "$(dirname "$SNAP")"
LOCK="$SNAP.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || date +%s) ))
  [ "$AGE" -ge 0 ] || AGE=0
  HELD="$(cut -c1-160 "$LOCK/holder" 2>/dev/null || echo '<no holder line>')"
  if [ "$AGE" -lt "$LOCK_LIMIT" ]; then
    echo "REFUSE: $LOCK is held by $HELD — lock age ${AGE}s, staleness bound ${LOCK_LIMIT}s (HL_SNAP_TIMEOUT), so its writer is still running. ONE WRITER PER SNAPSHOT: two lanes sharing one snapshot grade whichever tree synced last, and this run would certify a tree another lane is moving. Point this run at its own path: HL_SNAP_DIR=$HOME/gate-snap/<lane> bash scripts/harness/gate-snapshot.sh …  NOTHING was graded."
    exit 4
  fi
  echo "note: taking $LOCK over from $HELD — ${AGE}s old, past the ${LOCK_LIMIT}s spawn wall, so its writer is gone"
fi
printf '%s\n' "$HOLDER" > "$LOCK/holder"
trap 'rm -rf "$LOCK"' EXIT
if [ ! -d "$SNAP/.git" ]; then
  git clone -q --no-hardlinks "$SRC" "$SNAP"
fi
git -C "$SNAP" fetch -q "$SRC" '+refs/heads/*:refs/gate-snap/*' || git -C "$SNAP" fetch -q "$SRC"
git -C "$SNAP" cat-file -e "$WANT^{commit}" 2>/dev/null || git -C "$SNAP" fetch -q "$SRC" "$WANT" 2>/dev/null || true
if ! git -C "$SNAP" cat-file -e "$WANT^{commit}" 2>/dev/null; then
  echo "REFUSE: commit $WANT is not reachable from $SRC and cannot be fetched by sha — push the branch that carries it or grade a commit that is pushed. NOTHING was graded."
  exit 3
fi
git -C "$SNAP" clean -fdq
git -C "$SNAP" checkout -f -q --detach "$WANT"
git -C "$SNAP" clean -fdq
HEAD_NOW="$(git -C "$SNAP" rev-parse HEAD)"
if [ "$HEAD_NOW" != "$WANT" ]; then
  echo "FAIL: the snapshot answers $HEAD_NOW, the commit to grade is $WANT — the checkout refused or moved under the sync. NOTHING was graded."
  exit 1
fi
STAMPED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s %s %s\n' "$WANT" "$STAMPED" "$ORIGIN" > "$STAMP"
echo "graded: $WANT $(git -C "$SNAP" log -1 --format=%s)"
echo "stamped: $STAMP at $STAMPED by $ORIGIN"
GUEST
  # CARRY rides in the SAME spawn, AFTER the HEAD proof: the base stays exactly the stamped commit, so
  # what sits on top of it is a carried tree rather than a commit's — and the gate says so on its own line.
  if [ -n "$CARRY_PATCH" ]; then
    printf 'git -C "$SNAP" apply --index %s || { echo "FAIL: the carried patch does not apply onto the stamped base — it was cut against another commit. NOTHING was graded."; exit 1; }\n' \
      "$(_snap_sq "$CARRY_PATCH")"
  fi
  if [ -n "$CARRY_TAR" ]; then
    printf 'tar -xf %s -C "$SNAP" || { echo "FAIL: the carried tar did not extract into the snapshot. NOTHING was graded."; exit 1; }\n' \
      "$(_snap_sq "$CARRY_TAR")"
  fi
  if [ -n "$CARRY_PATCH" ] || [ -n "$CARRY_TAR" ]; then
    printf 'echo "carry: applied onto the stamped base — the tree on top is carried, NOT graded as committed"\n'
  fi
  if [ "$_grade" = 1 ]; then
    _gate='cd "$SNAP" || exit 3'
    _gate+=$'\n'"bash scripts/validate-all.sh --face tree"
    [ -z "$ONLY" ] || _gate+=" --only $(_snap_sq "$ONLY")"
    [ "$PROFILE" = full ] || _gate+=" --profile $(_snap_sq "$PROFILE")"
    printf '%s\n' "$_gate"
  fi
  return 0
}

# _snap_materialize — the HOST half of --carry: tracked edits as a patch, untracked files as ONE tar
# stream, both written where BOTH seats can read them and each named as it goes. Nothing is piped
# through the door: a stream that dies half-way leaves a half-applied tree behind and prints nothing that
# says so, while a file the guest reads itself is checked by `git apply` / `tar -x` — the copy and the
# verdict come from the same rc.
_snap_materialize() {
  [ "$CARRY" = 1 ] || return 0
  [ "$DIR_TRACKED" = 1 ] || [ "$DIR_UNtracked" = 1 ] || return 0
  local gk tmp
  gk="$(git -C "$SNAP_REPO" rev-parse --git-common-dir)" || return 1
  case "$gk" in /* | [A-Za-z]:[\/]*) : ;; *) gk="$SNAP_REPO/$gk" ;; esac   # absolute in either spelling
  # scratch INSIDE the git dir: a worktree-visible /tmp would either leak untracked garbage into the
  # corpus or arrive at the guest through a path the mnt translator could misread as a drive.
  tmp="$(mktemp -d "$gk/gate-snap-carry.XXXXXX")" || return 1
  CARRY_TMP="$tmp"
  trap 'rm -rf "${CARRY_TMP:-}"' EXIT
  if [ "$DIR_TRACKED" = 1 ]; then
    git -C "$SNAP_REPO" diff HEAD --binary >"$tmp/edits.patch" || return 1
    CARRY_PATCH="$tmp/edits.patch"
    if [ "$SNAP_DOOR" = remote ]; then
      CARRY_PATCH="$(hl_wsl_mntpath "$CARRY_PATCH")" || return 1
    fi
    printf 'carry: tracked edits as a patch (%s line(s))\n' "$(wc -l <"$tmp/edits.patch")"
  fi
  if [ "$DIR_UNtracked" = 1 ]; then
    # `-z` into `tar --null -T -`: a newline-joined list breaks on the one filename shape this repo can
    # produce, and a tar that swallowed half the list would still exit 0.
    ( cd "$SNAP_REPO" && git ls-files --others --exclude-standard -z | tar --null -cf - -T - ) >"$tmp/untracked.tar" || return 1
    CARRY_TAR="$tmp/untracked.tar"
    if [ "$SNAP_DOOR" = remote ]; then
      CARRY_TAR="$(hl_wsl_mntpath "$CARRY_TAR")" || return 1
    fi
    printf 'carry: untracked files as one tar stream (%s byte(s))\n' "$(wc -c <"$tmp/untracked.tar")"
  fi
  return 0
}

# _snap_prepare — the dirty-tree POLICY first, the carry material second. A dirty tree is carried on
# purpose or the run REFUSES with the exact commands; it is never graded as a silent mix of HEAD and
# whatever else was on the disk.
_snap_prepare() {
  if [ "$DIR_TRACKED" = 1 ] || [ "$DIR_UNtracked" = 1 ]; then
    if [ "$CARRY" != 1 ]; then _snap_refuse_dirty; return 3; fi
  fi
  _snap_materialize
}

# ---------------------------------------------------------------------------
# --self-test: the arms on a MINTED fixture repo over the LOCAL door — no wsl.exe,
# no engine, no station state. The git mechanics under test are the same bytes the
# remote door sends; only the filesystem is nearer.
# ---------------------------------------------------------------------------
_st_n=0; _st_f=0
_st_ok() { printf '  ok: %s\n' "$*"; _st_n=$((_st_n + 1)); }
_st_no() { printf 'SELFTEST FAIL: %s\n' "$*"; _st_f=$((_st_f + 1)); }
self_test() {
  local t out rc
  t="$(mktemp -d)" || return 1
  trap "rm -rf '$t'" RETURN
  # the fixture repo: two commits, clean, one branch.
  mkdir -p "$t/repo" && git -C "$t/repo" init -q \
    && git -C "$t/repo" config user.email st@invalid && git -C "$t/repo" config user.name st \
    || { _st_no "fixture repo could not be minted"; return 1; }
  printf 'one\n' > "$t/repo/f.txt" && git -C "$t/repo" add -A && git -C "$t/repo" commit -q -m first
  printf 'two\n' > "$t/repo/f.txt" && git -C "$t/repo" commit -q -am second
  export HL_SNAP_REPO="$t/repo" HL_SNAP_DOOR=local HL_SNAP_TIMEOUT=60
  local want; want="$(git -C "$t/repo" rev-parse HEAD)"

  # ARM 1 — first run with NO snapshot: the clone half executes and the sync still proves the HEAD.
  out="$(HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --sync 2>&1)"; rc=$?
  if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q "graded: $want"; then _st_ok "first run with no snapshot graded the right commit"
  else _st_no "first run with no snapshot (rc $rc): $out"; fi

  # ARM 2 — a planted STALE file does not survive a sync (the drifted-snapshot class, dead on arrival).
  printf 'stale\n' > "$t/snap/stale-file.txt"
  HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --sync >/dev/null 2>&1 || true
  if [ ! -e "$t/snap/stale-file.txt" ]; then _st_ok "a planted stale file is GONE after a sync"
  else _st_no "a planted stale file SURVIVED the sync — clean -fdq did not run or ran in the wrong tree"; fi

  # ARM 3 — the stamp matches: stamped sha == snapshot HEAD == the commit to grade.
  local stampsha headsha
  stampsha="$(cut -d ' ' -f1 "$t/snap.stamp" 2>/dev/null || echo "<none>")"
  headsha="$(git -C "$t/snap" rev-parse HEAD)"
  if [ "$stampsha" = "$want" ] && [ "$headsha" = "$want" ]; then _st_ok "the stamp and the snapshot HEAD both answer the graded commit"
  else _st_no "stamp $stampsha / HEAD $headsha / want $want — the receipt and the tree disagree"; fi

  # ARM 4 — a snapshot LEFT BEHIND the graded commit reddens --verify (the five-minute-old-verdict
  # class: a checkout that refused must never be able to grade on). Then --sync repairs and re-verifies.
  git -C "$t/snap" checkout -qf --detach HEAD~1
  out="$(HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --verify 2>&1)"; rc=$?
  if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'FAIL: the snapshot is not the graded commit'; then
    HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --sync >/dev/null 2>&1 || true
    if HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --verify >/dev/null 2>&1; then
      _st_ok "a snapshot behind the graded commit reddened --verify, and --sync repaired it"
    else _st_no "the drift reddened, but --sync did NOT repair it"; fi
  else _st_no "a snapshot a commit BEHIND passed --verify (rc $rc): $out"; fi

  # ARM 5 — the dirty-tree POLICY: refuse with the exact commands, or carry on purpose.
  printf 'dirty\n' > "$t/repo/loose.txt"
  out="$(HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --sync 2>&1)"; rc=$?
  if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'REFUSE: the working tree is DIRTY'; then
    if HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --sync --carry >/dev/null 2>&1 && [ -f "$t/snap/loose.txt" ]; then
      _st_ok "a dirty tree REFUSES by default and CARRIES on purpose"
    else _st_no "the refusal worked but --carry did not land the untracked file"; fi
  else _st_no "a dirty tree graded silently (rc $rc): $out"; fi
  rm -f "$t/repo/loose.txt"

  # ARM 6 — --verify FOR REAL, BOTH directions, with the output read. The mode was once dead on
  # arrival — an `echo <unstamped>` in the generated guest script parsed as a redirect and died at the
  # closing `)`, and every arm around it stayed green because they only ever asked `rc != 0` or
  # `>/dev/null`: a door that is never asked to read the program's WORDS certifies nothing about the
  # program behind it. So this arm runs the mode as a user does and grades the sentence, not just the
  # code: agreeing stamp → rc 0 naming the agreement; a stamp pointing at ANOTHER commit (HEAD clean,
  # receipt stale — the class the FAIL line exists to name) → rc 1 with all three shas in its mouth.
  local other orig_stamp
  other="$(git -C "$t/repo" rev-parse HEAD~1)"; orig_stamp="$(cat "$t/snap.stamp")"
  # ARM 5 leaves the snapshot CARRYING an untracked file, which is exactly the state ARM 7 grades; a
  # clean sync first, so this arm's two halves are about the RECEIPT and not about the tree.
  printf 'clean\n' > "$t/repo/f.txt" && git -C "$t/repo" commit -qam "arm6-base" && want="$(git -C "$t/repo" rev-parse HEAD)"
  HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --sync >/dev/null 2>&1 || true
  out="$(HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --verify 2>&1)"; rc=$?
  if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'verified: HEAD and stamp agree'; then
    printf '%s %s\n' "$other" "self-test-stale" > "$t/snap.stamp"   # HEAD agrees, the RECEIPT points elsewhere
    out="$(HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --verify 2>&1)"; rc=$?
    if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q "HEAD $want" \
       && printf '%s' "$out" | grep -q "stamped $other" \
       && printf '%s' "$out" | grep -q "to grade $want"; then
      _st_ok "--verify runs for real both ways: agreement rc 0 saying so, a stamp on another commit rc 1 naming HEAD, stamp and target"
    else _st_no "a stamp pointing at $other while HEAD=$want answered rc $rc: $out"; fi
  else _st_no "--verify with HEAD and stamp BOTH at $want answered rc $rc: $out"; fi
  printf '%s\n' "$orig_stamp" > "$t/snap.stamp"        # leave the receipt as the arms found it

  # ARM 7 — the CARRIED SNAPSHOT: `--verify` must NAME it, not pass it. HEAD and the stamp still agree
  # after a `--sync --carry`, so a verify that compares only those two reads GREEN while the tree under
  # the stamp carries bytes — and `--verify` is the mode reached for before a gate typed BY HAND inside
  # the snapshot, the one place those bytes are actually graded (a `--run` cleans before the checkout, so
  # a graded run cannot inherit them; that asymmetry is the whole finding). The state is PLANTED here
  # rather than assumed from ARM 5, and the SENTENCE is graded in both directions (ARM 6's shape).
  printf 'carried\n' > "$t/repo/loose-2.txt"
  HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --sync --carry >/dev/null 2>&1 || true
  out="$(HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --verify 2>&1)"; rc=$?
  if [ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'TREE is DIRTY on top of it' \
     && printf '%s' "$out" | grep -q "both name $want" \
     && printf '%s' "$out" | grep -q 'loose-2.txt'; then
    rm -f "$t/repo/loose-2.txt"
    if HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --sync >/dev/null 2>&1 \
       && HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --verify 2>&1 | grep -q 'HEAD and stamp agree'; then
      _st_ok "--verify names a snapshot still carrying a previous --carry, and goes green again once --sync cleans it"
    else _st_no "the carried tree was named but --sync did NOT clear it for a green verify: $out"; fi
  else _st_no "a snapshot carrying carried bytes passed --verify (rc $rc): $out"; fi

  # ARM 8 — the FACE SELECTION inside a stamped snapshot, both directions, grading the SENTENCE. Until this
  # arm existed the behavior rested on reading validate-all.sh's face block: nothing planted a snapshot and
  # asked the real block which face it picks. The seam is the DOCUMENTED inherited-$REPO
  # override (scripts/lib/repo-root.sh:150-153 — an inherited $REPO is trusted, not re-checked), which is what
  # lets the real validate-all.sh run against a fixture snapshot that carries no IaC markers: the block then
  # reads the driver's OWN stamp sibling and the snapshot's HEAD, exactly as it does in the engine.
  # The run STOPS at the unknown-profile refusal, which sits three lines below the face block: `--list` costs
  # ~14 s and performs a real 1Password read, so an arm that let the item list print would turn --self-test
  # into a leg. The refusal line is therefore graded too — if that stop ever moves, this arm fails loudly
  # instead of quietly paying for the registry, and the `timeout` is the wall behind the wall.
  local va stamped _pol_ok=1
  va="$HL_ROOT/scripts/validate-all.sh"
  HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --sync >/dev/null 2>&1 || true      # the driver's own stamp, freshly written
  stamped="$(cut -d ' ' -f1 "$t/snap.stamp")"
  out="$(REPO="$t/snap" timeout 120 bash "$va" --face auto --profile selftest-stop 2>&1)"; rc=$?
  if printf '%s' "$out" | grep -q "face: auto → tree" \
     && printf '%s' "$out" | grep -q "snapshot ($stamped)" \
     && printf '%s' "$out" | grep -q "FAIL: unknown --profile 'selftest-stop'"; then
    other="$(git -C "$t/repo" rev-parse HEAD~1)"
    printf '%s %s %s\n' "$other" "1970-01-01T00:00:00Z" "$t/repo" > "$t/snap.stamp"   # HEAD clean, RECEIPT elsewhere
    out="$(REPO="$t/snap" timeout 120 bash "$va" --face auto --profile selftest-stop 2>&1)"; rc=$?
    if printf '%s' "$out" | grep -q 'a disagreeing stamp selects NO face' \
       && printf '%s' "$out" | grep -q "names '$other', not this commit" \
       && ! printf '%s' "$out" | grep -q 'face: auto → tree'; then
      _st_ok "--face auto inside a stamped snapshot selects the tree face naming the stamp, and a stamp disagreeing with HEAD selects NO face"
    else _st_no "a stamp naming $other while the snapshot is at $stamped answered: $out"; fi
  else _st_no "--face auto in a stamped snapshot did not select the tree face (rc $rc): $out"; fi
  HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --sync >/dev/null 2>&1 || true       # re-stamp for the arms after this one

  # ARM 9 — the FORCED-LOCAL-DOOR POLICY, graded on its ARGUMENTS so it answers the same on every seat (the
  # rule is about the CLASS, not about the host asking — the same shape `hl_wsl_class` takes). What it refuses
  # was measured here, not imagined: `local` means "the engine is THIS bash", so on a win11 box with the
  # DEFAULT path the snapshot is minted under the CALLER's $HOME — a Windows directory the engine cannot see.
  out="$(_snap_door_policy win11 local 0)"; rc=$?
  if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'REFUSE: HL_SNAP_DOOR=local' \
     && printf '%s' "$out" | grep -q 'HL_SNAP_DIR'; then
    _pol_ok=1
    _snap_door_policy win11 local 1 >/dev/null 2>&1 || _pol_ok=0     # an explicit path: the fixture seam
    _snap_door_policy wsl local 0 >/dev/null 2>&1 || _pol_ok=0       # the box IS the engine
    _snap_door_policy linux local 0 >/dev/null 2>&1 || _pol_ok=0     # a Debian seat, no door to cross
    _snap_door_policy win11 remote 0 >/dev/null 2>&1 || _pol_ok=0    # the class-derived door, untouched
    _snap_door_policy win11 auto 0 >/dev/null 2>&1 || _pol_ok=0
    if [ "$_pol_ok" = 1 ]; then _st_ok "a forced local door on a win11 class with the default path is refused by name, and every other shape runs"
    else _st_no "the door policy refused a shape it must allow (rc of the four: see the policy text)"; fi
  else _st_no "a forced local door on a win11 class with the default path was NOT refused (rc $rc): $out"; fi

  # ARM 10 — ONE WRITER PER SNAPSHOT. The state is PLANTED (a lock dir, a holder line naming another lane),
  # and all three facts that make the rule usable are graded: the refusal names the HOLDER and the bound, a
  # lock older than HL_SNAP_TIMEOUT is taken over rather than obeyed forever, and a normal sync leaves no
  # lock behind — a leaked lock is a lane that cannot run until the bound expires.
  mkdir -p "$t/snap.lock" && printf '%s\n' "$t/lane-other head.0123456789ab pid 4242" > "$t/snap.lock/holder"
  out="$(HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --sync 2>&1)"; rc=$?
  if [ "$rc" = 4 ] && printf '%s' "$out" | grep -q 'REFUSE:' \
     && printf '%s' "$out" | grep -q 'ONE WRITER PER SNAPSHOT' \
     && printf '%s' "$out" | grep -q 'lane-other'; then
    touch -d '2 hours ago' "$t/snap.lock" 2>/dev/null || true        # HL_SNAP_TIMEOUT is 60 here → stale
    out="$(HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --sync 2>&1)"; rc=$?
    if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'taking .* over' && [ ! -d "$t/snap.lock" ]; then
      _st_ok "a held snapshot REFUSES the second writer by name, a lock past the spawn wall is taken over, and a sync leaves no lock behind"
    else _st_no "the lock took over or leaked (rc $rc, lock still there: $([ -d "$t/snap.lock" ] && printf yes || printf no)): $out"; fi
  else _st_no "a second writer synced straight into a locked snapshot (rc $rc): $out"; fi

  # ARM 11 — WHO stamped the tree, and what the stamp's FIELDS do in each state. Two lanes sharing one
  # snapshot is a PROVENANCE question that HEAD-vs-stamp cannot answer, so the stamp carries the graded repo
  # path and --verify prints it. THIRD field on purpose: validate-all.sh's face block reads field 1 only, and
  # the field must stay out of the way of that reader. The third state is the one this change could have
  # broken — an absent stamp is a `cut` failure, and a `set -e` guest eats an unguarded assignment into a
  # silent rc 1, which is how `--verify` was dead on arrival once before (HD-1230).
  local stamped_by
  stamped_by="$(cut -d ' ' -f3 "$t/snap.stamp")"
  out="$(HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --verify 2>&1)"; rc=$?
  if [ "$rc" = 0 ] && [ "$stamped_by" = "$t/repo" ] \
     && printf '%s' "$out" | grep -q "stamped by: $t/repo"; then
    printf '%s %s\n' "$want" "2026-01-01T00:00:00Z" > "$t/snap.stamp"   # a stamp from before the origin field
    out="$(HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --verify 2>&1)"; rc=$?
    if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'stamped by: <no origin recorded'; then
      rm -f "$t/snap.stamp"                                            # HEAD agrees, there is no RECEIPT at all
      out="$(HL_SNAP_DIR="$t/snap" bash "$SELF_FILE" --verify 2>&1)"; rc=$?
      if [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'stamped <unstamped>'; then
        _st_ok "the stamp's fields hold in all three states: the repo that synced it is named, a pre-origin stamp says it has no origin, an absent stamp still prints the FAIL sentence rather than exiting silent"
      else _st_no "a snapshot with NO stamp answered rc $rc and printed: $out — the origin read died before the verdict"; fi
    else _st_no "a two-field stamp printed an origin it never had (rc $rc): $out"; fi
  else _st_no "the stamp's origin field is '$stamped_by', not the graded repo '$t/repo' (rc $rc): $out"; fi

  printf 'self-test: %d arm(s), %d failed\n' "$_st_n" "$_st_f"
  [ "$_st_f" = 0 ]
}

# ---------------------------------------------------------------------------
main_rc=0
case "$MODE" in
  self-test) self_test; main_rc=$? ;;
  # --sync and --check are the same guest script with the gate left off: the move, the HEAD proof and the
  # stamp, and NOTHING else. --check is the receipt the brief asked for — it grades a commit by proving
  # the snapshot answers it, without spending a minute on the legs.
  sync | check)
    _snap_want && _snap_prepare && _snap_spawn "$(_snap_script "$SNAP_WANT" "$SNAP_SRC" 0)"; main_rc=$? ;;
  verify) _snap_want && _snap_spawn "$(_snap_verify_script "$SNAP_WANT")"; main_rc=$? ;;
  run)
    if [ "$SNAP_DOOR" = none ]; then
      echo "FAIL: $SELF --run: this box classifies as win11 with NO wsl.exe door — there is no engine to snapshot, so there is no tree face to run. Run the whole set here instead: HL_FACE=both bash scripts/validate-all.sh" >&2
      main_rc=2
    else
      # ONE spawn for the whole tree face, carried tree or not: the sync chain, the carry on top of the
      # verified base, and the gate inside the same guest shell.
      _snap_want && _snap_prepare && _snap_spawn "$(_snap_script "$SNAP_WANT" "$SNAP_SRC" 1)"; main_rc=$?
      fi ;;
  *) echo "usage: bash $SELF --run|--sync|--check|--verify|--self-test [--carry] [--only SUB] [--profile P]" >&2; main_rc=2 ;;
esac
exit "$main_rc"
