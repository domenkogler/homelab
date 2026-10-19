#!/usr/bin/env bash
# =====================================================================
# testdata/rsync-max-delete — what `--max-delete` ACTUALLY does, tested in
# the tree instead of asserted in a row's prose.
# ---------------------------------------------------------------------
# WHY THIS EXISTS. The music push leg (roles/storage: oldsrv -> the live Storage Box) bounds its
# `--delete` with `--max-delete`, because a dead source mount reads as an EMPTY DIRECTORY and an
# unbounded `--delete` then empties the serving library in one timer fire that reads green. That
# bound was first described as an abort — "rsync stops, nothing is deleted" — and that reading is
# wrong in the dangerous direction. The measured behaviour is CAP semantics: with 100 entries pending
# deletion and a limit of 50, rsync DELETES 50, stops deleting the rest and exits 25 (`Deletions
# stopped due to --max-delete limit`). The per-fire guarantee is "at most `max_delete` entries",
# never "nothing" — which is exactly why the mount assert and the file-count floor, both of which run
# BEFORE any rsync, are the real guards. A row can say that once; only a fixture keeps saying it
# after the script changes, so the assertion lives here.
#
# THE SHAPE THE ARMS BUILD — no production host, no Box, nothing staged by hand:
#   fire 1 (the ordinary fire)   rsync … --remove-source-files   src(N files) -> dest(empty)
#        All N transfer and rsync removes them from the SOURCE, so what the next fire sees is the
#        precise thing a dead mount hands the real leg: an existing source directory holding NOTHING
#        beside a destination holding all N. The script's own flag creates the hazard, which is the
#        reason this pair of flags is tested together and not one at a time.
#   fire 2a (unbounded)          same command, no cap  -> ALL N deleted, rc 0.
#        THE DENOMINATOR. It proves the run really had N pending deletions, so the "exactly N/2"
#        below is a measurement and not an artefact of a shape that only had N/2 to delete.
#   fire 2b (capped)             --max-delete=N/2      -> EXACTLY N/2 deleted, N/2 still there, rc 25.
#        Cap semantics, not abort semantics, asserted as three numbers instead of quoted.
#
# THREE ARMS, and the first is the one that runs on a seat with no rsync at all:
#   shape parity — offline, always. The flags THIS fixture mirrors must be the flags the push script
#                  renders. A fixture that drifts from the script it claims to prove is a green that
#                  measures a fiction, and this arm is the only one that can notice on such a seat.
#   unbounded    — needs rsync
#   capped       — needs rsync
#
# Usage:
#   bash scripts/testdata/rsync-max-delete/run.sh              # the real thing
#   bash scripts/testdata/rsync-max-delete/run.sh --self-test  # the canaries, no rsync needed
#   bash scripts/testdata/rsync-max-delete/run.sh --fixture F  # judge recorded results (see RECORD
#                                                              # FORMAT below) — prints a FIXTURE
#                                                              # banner; the ONLY fabrication path
#   HL_PUSH_SCRIPT=<file>        point the parity arm at another script (the canary does this)
#   HL_RSYNC_N=<count>           tree size, default 100 (the measured case)
#
# RECORD FORMAT (--fixture): one line per arm, `unbounded <rc> <deleted> <dest_after>` and
# `capped <rc> <deleted> <dest_after>`. Both arms must be present: a record set that reports one arm
# is refused, not completed.
#
# Exit: 0 all arms green · 1 a finding (an assertion wrong, or the shape drifted) ·
#       2 a boundary (rsync absent, or the push script unreadable) — printed, never counted green.
# Wired into validate-all.sh through --self-test.
# =====================================================================
set -uo pipefail

_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"        # sets REPO; FATAL when no root is found

PUSH_SCRIPT="${HL_PUSH_SCRIPT:-$REPO/IaC/ansible/roles/storage/templates/storage-push-music.sh.j2}"
N="${HL_RSYNC_N:-100}"                       # files in the tree; the measured case was 100
CAP=$((N / 2))                               # the bound under test: N/2, so the cap is CROSSED

# The flags this fixture mirrors from the push script. Transport (`-e …`, the remote path) is
# deliberately NOT listed: a local scratch destination cannot carry an ssh leg and the deletion
# behaviour is not in it. Everything that decides what gets DELETED is listed.
RSYNC_FLAGS=(-rlt --no-perms --no-owner --no-group --delete --delay-updates --partial --max-delete)

pass=0 fail=0 skip=0
ok()   { printf 'PASS: %s\n' "$*"; pass=$((pass + 1)); }
bad()  { printf 'FAIL: %s\n' "$*"; fail=$((fail + 1)); }
skip() { printf 'SKIP: %s\n' "$*"; skip=$((skip + 1)); }

count_files() { CF=0; local f; while IFS= read -r f; do [ -n "$f" ] && CF=$((CF + 1)); done \
                  < <(find "$1" -type f 2>/dev/null); }

# has_flag <line> <flag> — a flag is PRESENT when it stands alone or carries its value with `=`.
# Substring matching is not enough in either direction: `--max-delete="$MAX_DELETE"` must COUNT as
# `--max-delete`, and `--delete-excluded` must NOT count as `--delete` (the second is the more
# dangerous of the two, because it would let a different deletion policy pass as the tested one).
has_flag() { printf '%s' "$1" | grep -qE "(^|[[:space:]])$2(=|[[:space:]]|$)"; }

# The one rsync shape, in ONE place, so the parity arm and the arms below cannot disagree. It is
# grepped by arm_shape, so keep it as a single line that starts with `rsync `.
# fire <cap>          — the hazard fire: identical to the timer's command, cap applied.
# fire  ""            — the unbounded fire, and the ordinary (first) fire, which consumes the source.
rsync() {
  local cap="$1"
  if [ -n "$cap" ]; then
    command rsync -rlt --no-perms --no-owner --no-group --delete --max-delete="$cap" --remove-source-files --delay-updates --partial "$SRC/" "$DEST/"
  else
    command rsync -rlt --no-perms --no-owner --no-group --delete --remove-source-files --delay-updates --partial "$SRC/" "$DEST/"
  fi
}

# --------------------------------------------------------------------------- #
# The judge — the ONLY place this fixture decides anything. Used by the real   #
# arms and by --fixture records, so a weakened assertion reddens both.         #
# --------------------------------------------------------------------------- #
judge() { # judge <arm> <rc> <deleted> <dest_after>
  local arm="$1" rc="$2" deleted="$3" after="$4"
  case "$arm" in
    unbounded)
      [ "$rc" = 0 ] || { printf '  unbounded: rc %s, want 0 — an unbounded --delete run must not exit 25\n' "$rc"; return 1; }
      [ "$deleted" = "$N" ] || { printf '  unbounded: %s deleted, want all %s — with no cap this shape must have %s pending deletions, or the capped arm measures nothing\n' "$deleted" "$N" "$N"; return 1; }
      [ "$after" = 0 ] || { printf '  unbounded: %s files left, want 0\n' "$after"; return 1; }
      ;;
    capped)
      # Three numbers, in this order on purpose. The cap was SPENT — 0 deleted would be ABORT
      # semantics, the reading this fixture exists to retire; spent EXACTLY to the bound, because
      # more than the bound means the bound is not a bound; and the residue survived, because the
      # blast radius is `max_delete` per fire and not "everything until it noticed".
      if [ "$deleted" != "$CAP" ]; then
        if [ "$deleted" = 0 ]; then
          printf '  capped: 0 deleted — that is ABORT semantics, and --max-delete does not do that; it deletes up to the bound and stops\n'
        else
          printf '  capped: %s deleted, want exactly the bound %s\n' "$deleted" "$CAP"
        fi
        return 1
      fi
      [ "$rc" = 25 ] || { printf '  capped: rc %s, want 25 (Deletions stopped due to --max-delete limit)\n' "$rc"; return 1; }
      [ "$after" = "$((N - CAP))" ] || { printf '  capped: %s files left, want %s — the residue is the whole claim\n' "$after" "$((N - CAP))"; return 1; }
      ;;
    *) printf '  unknown arm %s\n' "$arm"; return 1 ;;
  esac
  return 0
}

# --------------------------------------------------------------------------- #
# Arm 1: shape parity — the fixture and the script must still describe ONE run.#
# --------------------------------------------------------------------------- #
flags_of() { # flags_of <file> -> FL, the rsync FLAGS of its invocation, continuation lines JOINED
  # Two traps, both real in `storage-push-music.sh.j2`:
  #  * the command wraps across three lines with trailing backslashes, so reading ONE line reports a
  #    run missing every flag on line 2 — parity would fail for the wrong reason, and a fixture that
  #    cries wolf gets ignored;
  #  * the joined tail lands on the `|| fail "… rc 25 with 'Deletions stopped due to --max-delete
  #    limit' …"` handler, which MENTIONS `--max-delete` in prose. Cut at the shell `||`, so the
  #    verdict reads the flags the run actually carries and not the error text beside them.
  FL="$(awk '
    /^[ \t]*(command )?rsync / { f = 1 }
    f {
      buf = buf " " $0
      if ($0 !~ /\\$/) { sub(/\|\|.*/, "", buf); gsub(/\t/, " ", buf); print buf; exit }
      sub(/\\$/, "", buf)
    }' "$1")"
}

arm_shape() { # arm_shape <file> -> 0 parity, 1 drift
  local file="$1" f miss="" self_miss="" line self_line
  [ -f "$file" ] || { printf '  cannot read %s\n' "$file"; return 2; }
  flags_of "$file"; line="$FL"
  [ -n "$line" ] || { printf '  %s holds no rsync invocation\n' "$file"; return 1; }
  for f in "${RSYNC_FLAGS[@]}"; do has_flag "$line" "$f" || miss+="$f "; done
  flags_of "${BASH_SOURCE[0]}"; self_line="$FL"     # the mirror, read from disk, not from memory
  for f in "${RSYNC_FLAGS[@]}"; do has_flag "$self_line" "$f" || self_miss+="$f "; done
  [ -z "$miss" ] || printf '  the push script lost %s — the fixture mirrors a run nobody performs\n' "$miss"
  [ -z "$self_miss" ] || printf '  this fixture lost %s — it no longer mirrors the push script\n' "$self_miss"
  [ -z "$miss" ] && [ -z "$self_miss" ]
}

# --------------------------------------------------------------------------- #
# The real arms (need rsync).                                                 #
# --------------------------------------------------------------------------- #
W="" SRC="" DEST=""
setup() {
  SRC="$W/src"; DEST="$W/dest"
  rm -rf "$SRC" "$DEST"; mkdir -p "$SRC" "$DEST"
  local i=1
  while [ "$i" -le "$N" ]; do printf 'flac placeholder %s\n' "$i" > "$SRC/track-$i.flac"; i=$((i + 1)); done
}

arm_rsync() { # arm_rsync <capped|unbounded>
  local arm="$1" before after rc src_after
  setup
  rsync "" 2>"$W/fire1.err"; rc=$?            # the ordinary fire: master -> Box, source consumed
  # The unbounded form of the SAME command the timer runs: `--remove-source-files` is what empties
  # the source, so the next fire sees a dead-mount source with nothing hand-staged.
  count_files "$SRC"; src_after=$CF
  count_files "$DEST"; before=$CF
  if [ "$rc" != 0 ] || [ "$src_after" != 0 ] || [ "$before" != "$N" ]; then
    bad "$arm: the ordinary fire gave rc $rc src=$src_after dest=$before (want 0 0 $N) — $(tr '\n' ' ' <"$W/fire1.err")"
    return
  fi
  if [ "$arm" = capped ]; then rsync "$CAP" 2>"$W/fire2.err"; else rsync "" 2>"$W/fire2.err"; fi
  rc=$?
  count_files "$DEST"; after=$CF
  if judge "$arm" "$rc" "$((before - after))" "$after"; then
    ok "$arm: $((before - after)) of $before deleted, $after left, rc $rc (N=$N cap=$CAP)"
  else
    bad "$arm: the shape ran and the numbers disagree with what --max-delete is claimed to do"
    printf '      rsync stderr: %s\n' "$(tr '\n' ' ' <"$W/fire2.err" | cut -c1-200)"
  fi
}

# --------------------------------------------------------------------------- #
# --fixture: judge recorded results (and the self-test's record sets).        #
# --------------------------------------------------------------------------- #
run_records() { # run_records <file> -> 0 green, 1 finding
  local file="$1" arm rc deleted after seen_u=0 seen_c=0 line
  [ -f "$file" ] || { printf '  no record file %s\n' "$file"; return 1; }
  while IFS=' ' read -r arm rc deleted after; do
    [ -n "${arm:-}" ] || continue
    case "$arm" in unbounded) seen_u=1 ;; capped) seen_c=1 ;; esac
    judge "$arm" "$rc" "$deleted" "$after" || return 1
  done < <(grep -E '^(unbounded|capped) ' "$file")
  if [ "$seen_u" != 1 ] || [ "$seen_c" != 1 ]; then
    printf '  record set reported unbounded=%s capped=%s — both arms must answer, a half-set cannot pass\n' "$seen_u" "$seen_c"
    return 1
  fi
  return 0
}

# expect <want-rc> <desc> <file>: the self-test's assertion over run_records.
expect_records() { # expect_records <want-rc> <desc> <file>
  local want="$1" desc="$2" file="$3" out rc=0
  out="$(run_records "$file" 2>&1)" || rc=$?
  if [ "$want" = 0 ] && [ "$rc" = 0 ]; then ok "$desc"; return; fi
  if [ "$want" != 0 ] && [ "$rc" != 0 ]; then ok "$desc (rc $rc)"; return; fi
  if [ "$want" = 0 ]; then bad "$desc — want green, got rc $rc"
  else bad "$desc — the verdict stayed GREEN, so the assertion cannot fail"; fi
  printf '%s\n' "$out" | sed 's/^/      | /'
}

# --------------------------------------------------------------------------- #
# --self-test: the canaries, in process, over the SAME judge the arms call.    #
# --------------------------------------------------------------------------- #
self_test() {
  local t green f i
  t="$(mktemp -d)"

  printf '== the arm that runs everywhere (no rsync needed) ==\n'
  if arm_shape "$PUSH_SCRIPT"; then
    ok "shape parity: this fixture and $(basename "$PUSH_SCRIPT") name the same rsync flags"
  else
    bad "shape parity: the fixture and the push script no longer describe one run"
  fi
  # The same arm on a copy with ONE tracked flag removed. Green here means the parity arm has no
  # teeth — CONVENTIONS §6's "a test that cannot fail is not evidence".
  local mut="$t/mutated.j2"
  sed 's/ *--max-delete="\$MAX_DELETE"//' "$PUSH_SCRIPT" > "$mut"
  if arm_shape "$mut" >"$t/can.out" 2>&1; then
    bad "canary: a push script missing --max-delete still passed the parity arm"
  else
    ok "canary: a push script missing --max-delete reddens the parity arm"
  fi

  printf '== the deletion arms, over records ==\n'
  green="$t/green.rec"
  { printf 'unbounded 0 %s 0\n' "$N"; printf 'capped 25 %s %s\n' "$CAP" "$((N - CAP))"; } > "$green"
  expect_records 0 "the measured truth (N=$N, cap=$CAP): all N unbounded, exactly N/2 capped, rc 25" "$green"

  # Each record below contradicts ONE clause of the verdict. Every one must redden; a green one is an
  # assertion that was weakened without the canary noticing, which is the whole reason they are here.
  local -a lies=(
    "abort semantics accepted as a pass|unbounded 0 %N 0|capped 0 0 %N"
    "the bound did not hold (everything deleted under a cap)|unbounded 0 %N 0|capped 25 %N 0"
    "the count is right and the rc is a lie|unbounded 0 %N 0|capped 0 %CAP %RES"
    "the denominator arm is wrong (never had N pending deletions)|unbounded 25 %CAP %RES|capped 25 %CAP %RES"
  )
  i=0
  for f in "${lies[@]}"; do
    i=$((i + 1))
    local body="${f#*|}" name="${f%%|*}" rec="$t/lie$i.rec"
    # `|` separates the two record lines inside the case string, because an array element cannot
    # carry a newline without turning the table above into a wall.
    body="$(printf '%s' "$body" | tr '|' '\n' | sed -e "s/%N/$N/g" -e "s/%CAP/$CAP/g" -e "s/%RES/$((N - CAP))/g")"
    printf '%s\n' "$body" > "$rec"
    expect_records 1 "canary $i: $name" "$rec"
  done

  printf 'unbounded 0 %s 0\n' "$N" > "$t/half.rec"
  expect_records 1 "a record set with a missing arm is refused, not completed" "$t/half.rec"
  printf 'nonsense at all\n' > "$t/bad.rec"
  expect_records 1 "a record set with no arms is refused" "$t/bad.rec"
  rm -rf "$t"
}

# --------------------------------------------------------------------------- #
# Main                                                                        #
# --------------------------------------------------------------------------- #
case "${1:-}" in
  --self-test)
    printf '== rsync --max-delete fixture: canaries (N=%s, cap=%s) ==\n' "$N" "$CAP"
    n0=$((pass + fail))
    self_test
    printf '\n%d assertion(s): %s passed, %s failed\n' "$((pass + fail - n0))" "$pass" "$fail"
    [ "$fail" = 0 ] || { echo "FAIL: the --max-delete verdict has lost its teeth"; exit 1; }
    echo "OK: cap semantics are asserted as numbers, and every weakening reddens a canary"
    exit 0 ;;
  --fixture)
    f="${2:-}"
    [ -n "$f" ] || { echo "FAIL: --fixture needs a record file" >&2; exit 2; }
    printf 'FIXTURE: judging records from %s — no rsync, no writes\n' "$f"
    if run_records "$f"; then
      echo "OK: the recorded run matches cap semantics (N=$N, cap=$CAP)"; exit 0
    fi
    echo "FAIL: the recorded run does not match cap semantics"; exit 1 ;;
  "") : ;;
  *) echo "usage: run.sh [--self-test | --fixture <records>]" >&2; exit 2 ;;
esac

printf '== rsync --max-delete fixture (N=%s, cap=%s) ==\n' "$N" "$CAP"
if arm_shape "$PUSH_SCRIPT"; then
  ok "shape parity: the mirrored flags are the flags $(basename "$PUSH_SCRIPT") renders"
else
  bad "shape parity: the fixture and $(basename "$PUSH_SCRIPT") no longer describe one run"
fi

if ! type -P rsync >/dev/null 2>&1; then     # type -P, not `command -v`: this file defines a shell
  # function named `rsync`, and `command -v` answers for functions — the presence test would pass on
  # a host with no binary and every arm would then fail on rc 127 instead of SKIPping honestly.
  skip "no rsync on this host, so the two deletion arms did not run — the parity arm above did, and"
  printf '      --self-test proves both halves of the verdict can still redden without rsync.\n'
  printf '\n%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
  [ "$fail" = 0 ] || exit 1
  exit 2
fi

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
arm_rsync unbounded
arm_rsync capped
rm -rf "$W"; trap - EXIT

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ] || { echo "FAIL: --max-delete is not behaving as this fixture asserts"; exit 1; }
echo "OK: --max-delete is a CAP — exactly N/2 deleted and rc 25, on $(command rsync --version 2>/dev/null | head -1)"
