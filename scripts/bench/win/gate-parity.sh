#!/usr/bin/env bash
# =====================================================================
# bench/win/gate-parity.sh — did a wrapped leg judge the SAME THING on both sides of the door?
# ---------------------------------------------------------------------
# WHY THIS EXISTS: on the win11 seat a leg can cross to the Debian engine, come back FAST, come back
# rc 0, and be a lie. The failure this seat keeps meeting is an arm that answers NOTHING on the far
# side — a tool the engine lacks (rsync, and behind the route's PATH pin also node/rg/sqlite3/gawk), a
# path the engine cannot open, an early return on a seat test — so the crossed run finishes with the
# SAME exit code having judged FEWER arms. `hl_wsl_route` passes the far rc straight through, which is
# exactly why rc alone cannot certify a wrap: the parity diff, not the stopwatch, is what authorises a
# leg to cross (prompt-gate.md §4). This runner is that diff, as a command.
#
# WHAT IT DOES: runs the argv HERE, runs the SAME argv through `hl_wsl_route`, and compares three things
# per side — the exit code, the RECOGNIZED ARM COUNT, and the verdict words. It mutates nothing and
# wraps nothing itself; it is an instrument, which is why validate-all.sh registers its `--self-test`
# and never a full-leg parity sweep.
#
#   bash scripts/bench/win/gate-parity.sh -- <argv>     # the two runs, one verdict
#   bash scripts/bench/win/gate-parity.sh --self-test    # the fixtures in testdata/gate-parity/
#   bash scripts/bench/win/gate-parity.sh --help         # the exit contract, in full
#
# AN ARM is a line the leg OFFERS as a verdict, recognized by HL_PARITY_ARM_RE below. The recognizer is
# printed at the top of every run and again on the rc-2 verdict: when a leg reports in prose the honest
# answer is that NO comparison happened, and the reader must be handed the command to EXTEND rather than
# a reason to mute the leg.
#
# THE VOCABULARY, in words, because rc 2 must never be read as a boundary when it is really a blind spot:
#   ok · not ok · PASS · FAIL · ERROR · SKIP · NOTE · WARNING · WARN · FATAL · CANNOT   the verdict-word idiom
#   GREEN · caught                                                                     what THIS repo's harness
#                                                                                      self-tests answer with
# A word is a verdict only when the character BEFORE it is a space or the line's start and the one AFTER
# it is `:` `!` `?` a space or the line's end — so `uncaught` and `GREENHOUSE` are not arms. Without
# `GREEN` and `caught` the runner answers rc 2 with `0 arm(s)` on BOTH sides of a leg that printed 17
# verdict lines each (measured 2026-10-31 on `bash scripts/bench/win/gate-parity.sh -- bash
# scripts/harness/pi-tui-config.sh --self-test`). That answer
# is not a boundary, it is blindness, and it makes a leg unwrappable-as-specified: a wrap is authorised
# by a parity line, and a blind recognizer can print only rc 2. Re-derive what is in force with either:
#   bash scripts/bench/win/gate-parity.sh --self-test | head -1    # the recognizer, as every run prints it
#   grep -n '^HL_PARITY_ARM_RE=' scripts/bench/win/gate-parity.sh  # the expression itself
#
# WHAT IS NOISE — one rule per line of the normalizer, each with the difference it removes, and never a
# blanket `grep -v`, because a rule that drops a whole class of lines is how a lost arm gets muted:
#   CR              the Windows side ends a line with \r, the engine does not
#   route:          the route's own banner says WHERE the leg ran, never WHAT it judged
#   D:/ ↔ /mnt/d/   one path, three spellings: the seat writes `D:/x`, Git-Bash writes `/d/x`,
#                   the engine sees `/mnt/d/x`
#   temp root       the seat writes `%LOCALAPPDATA%\Temp`, the engine writes `/tmp` — one place, two names
#   tmp.XXXXXXXXXX  a mktemp suffix is random per run — compared byte-for-byte it reddens every leg
#
# THE EXIT CONTRACT — rc 2 OUTRANKS BOTH parity and diff, and that precedence is the whole design.
#   0  PARITY        same rc (0), same arm count, same verdict words
#   1  PARITY DIFF   the two answers differ; both arm counts are printed
#   2  CANNOT RUN    either side exited 2 (a boundary, the shape testdata/rsync-max-delete/run.sh uses
#                    for a tool this seat lacks), or a side produced ZERO recognizable arms, or a side
#                    produced NO BYTES.
# rc 2 is the answer whenever nothing was judged, because "0 arms vs 0 arms" is not parity: a runner that
# called that green would certify any leg that never started, and would call the seat-classifier class a
# pass — a leg that asks which seat it is on answers for the WRONG SEAT, so its diff comes back empty
# AND worthless. rc 2 never prints the word PARITY; it has no comparison to claim.
#
# WHAT A VERDICT IS WORTH IN A WORKTREE, said at run time as well as here: in a Windows LINKED WORKTREE
# a Linux git cannot open the checkout (`git=unavailable` — the `.git` file names `D:/…` and a Linux git
# resolves it relatively). Two runs that both read NOTHING still agree, so a parity verdict about a
# git-reading leg in a worktree is worthless evidence, whatever it prints.
#
# SELF-TEST: bash scripts/bench/win/gate-parity.sh --self-test
#   Each fixture in scripts/testdata/gate-parity/ plants ONE difference, in the open, so every verdict is
#   graded against a known difference and not against the luck of a real leg. The crossed side is reached
#   through a STUB door injected at the lib's own `HL_WSL_EXE` seam; that stub is the ONLY thing outside a
#   fixture that sets `HL_PARITY_GUEST`, and the native side drops the variable first, so a flavour cannot
#   be taken by accident. `portable.sh` then runs the LIVE door. Four mutations of this file prove the
#   comparison has teeth: mute the verdict-word rule and the lost arm must still redden by ARM COUNT, mute
#   the arm-count rule and it must still redden by WORDS, mute BOTH and the fixture must go green (a red
#   with nothing left to compare would be reddened by something outside the rules), and mute the rc-2-over-
#   parity precedence and a boundary must come back as a PARITY DIFF instead of the honest rc 2. Each runs
#   over a COPY of the decision region above, so a mutant cannot pass for a reason the real runner would not.
# =====================================================================
set -uo pipefail

_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ -n "$_hl_d" ] && [ "$_hl_d" != / ] && [ ! -f "$_hl_d/lib/repo-root.sh" ]; do
  _n="${_hl_d%/*}"; [ "$_n" = "$_hl_d" ] && _n="/"; _hl_d="$_n"    # expansion, not dirname:
done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"        # sets REPO; FATAL when no root is found
# shellcheck source=/dev/null
. "$REPO/scripts/lib/wsl-route.sh"    # the crossed side is the lib's decision, never this file's

# >>> MUTABLE
# --------------------------------------------------------------------------- #
# MUTABLE — the decision half. The self-test copies THIS REGION into a temp file, weakens one flag, and #
# re-runs the same fixtures through it, so a rule that stops working is caught by a fixture instead of  #
# rotting behind a comment. The mutant shares everything else with the real thing, so it cannot pass for #
# a different reason.                                                           #
# --------------------------------------------------------------------------- #

# An arm is a line the leg OFFERS as a verdict, so the head list is kept honest to this tree's legs: the
# fixtures and the wrapped self-tests print `ok  `, `PASS:`, `FAIL:`, `SKIP:`, and the harness self-tests
# (pi-tui-config, install-tmux-conf, pi-settings-config) answer `… GREEN` / `… caught`. The tail class
# accepts the END OF THE LINE as well as punctuation, because `  file-untouched   GREEN` is a verdict
# too — and an arm nobody reads is an rc 2 that reads as a boundary (see the header's VOCABULARY block).
# A leg that reports ONLY in prose has NO arms, and that is an rc 2 — nothing to compare — never a free green.
HL_PARITY_ARM_RE='(^|[[:space:]])(ok|not ok|PASS|FAIL|SKIP|NOTE|ERROR|WARNING|WARN|FATAL|CANNOT|GREEN|caught)([!?:[:space:]]|$)'

PARITY_STRICT_ARMS=1     # MUTATION SEAM (self-test): 0 = stop comparing the arm COUNTS
PARITY_STRICT_WORDS=1    # MUTATION SEAM (self-test): 0 = stop comparing the normalized verdict WORDS
PARITY_RC2_FIRST=1       # MUTATION SEAM (self-test): 0 = let a parity diff outrank a side that could not run

# The command a reader extends instead of muting a leg. Built when printed, so what a reader sees is the
# recognizer actually in force — a stale printed command is worse than none.
_recognizer_line() { printf "grep -E '%s'" "$HL_PARITY_ARM_RE"; }

# normalize — reads stdin, one rule per -e. Backslash handling: to sed's `s` a literal backslash in the
# pattern is `\`, which also escapes the delimiter, so the separator rules use a bracket class.
normalize() {
  sed -e 's/\r$//' `# (1) CR: the Windows side ends a line with \r, the engine never does` \
      -e '/^[Rr]oute: /d' `# (2) the route's own banner: it says WHERE the leg ran, not WHAT it judged` \
      -e '/[A-Za-z]:[\]/ s#[\]#/#g' `# (3) a Windows path spelled with backslashes: on a line that already` \
                                      `#     carries a drive-prefixed path, a backslash IS a separator` \
      -e 's#\(^\|[^A-Za-z0-9_]\)\([A-Za-z]\):[\/][\/]*#\1/mnt/\L\2/#g' `# (4) D:/x -> /mnt/d/x` \
      -e 's#\(^\|[[:space:]"=(]\)/\([A-Za-z]\)/#\1/mnt/\2/#g' `# (5) Git-Bash's /d/x -> /mnt/d/x; the guard` \
                                                                `#     char is why /mnt/d/ is not rewritten twice` \
      -e 's#/mnt/[A-Za-z]/[Uu]sers/[^/]*/AppData/Local/[Tt]emp#/tmp#g' `# (6) the seat's temp root -> /tmp, in the` \
                                                                      `#     engine's own spelling (rules 4+5 got it there)` \
      -e 's#\(/tmp/\)tmp[._][A-Za-z0-9]\{4,\}#\1mktemp#g' `# (7) a mktemp suffix is random per run`
}

# _arm_scan <corpus-file> <arms-file> — writes the recognized arms (normalized, trimmed, in order) to
# <arms-file> and prints "<count>\t<histogram>". ONE pass on purpose: the win11 seat pays tens of
# milliseconds per fork and a gate run under load pays hundreds, so the recognizer is not allowed to
# re-scan a corpus four times per leg. Non-arm prose is narration: it stays in the printed corpus and is
# never compared, because a leg may reword its prose without changing a verdict.
_arm_scan() {
  sed -e 's/\r$//' "$1" | grep -E "$HL_PARITY_ARM_RE" 2>/dev/null \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | normalize >"$2"
  awk 'BEGIN { i = 0 }
    { s = $0; w = ""
      if      (s ~ /CANNOT([ !?:]|$)/)                       w = "CANNOT"
      else if (s ~ /FAIL([ !?:]|$)/)                         w = "FAIL"
      else if (s ~ /ERROR([ !?:]|$)/)                        w = "ERROR"
      else if (s ~ /SKIP([ !?:]|$)/)                         w = "SKIP"
      else if (s ~ /^(NOTE|WARNING|WARN)([ !?:]|$)/)         w = "NOTE"
      else if (s ~ /(^|[[:space:]])not ok/)                  w = "not-ok"
      else if (s ~ /(^|[[:space:]])(ok|PASS)([ !?:]|$)/)     w = "ok"
      # The harness-leg idiom — `foreign-probe     GREEN`, `noms-canary     caught`. It sits LAST among
      # the ok tests, so a severity word elsewhere on the line still owns the LABEL, and an arm that
      # merely EXPLAINS a skip (`… GREEN (rc 2 = SKIP, not a pass)` — the comma keeps the severity test
      # away, since it wants a word boundary after its own word) keeps its ok. An arm that stopped
      # running changes the COUNT, and the COUNT rule is what catches a lost arm. The VOCABULARY block
      # in the header owns the word list; the recognizer line every run prints is what a reader extends.
      else if (s ~ /(^|[[:space:]])(GREEN|caught)([ !?:]|$)/) w = "ok"
      if (w == "") w = "?"
      if (!(w in c)) { i++; o[w] = i }
      c[w]++
    }
    END { printf "%d\t", NR; sep = ""
          for (k = 1; k <= i; k++) for (x in c) if (o[x] == k) { printf "%s%s x%d", sep, x, c[x]; sep = " · " }
          print "" }' "$2"
}

# parity_of <native-corpus> <native-arms> <guest-arms> <native-rc> <guest-rc> — the whole verdict, in ONE
# place so the self-test and a real run cannot drift apart. Two comparisons: the arm COUNTS, then the
# normalized verdict WORDS. rc 2 OUTRANKS both (PARITY_RC2_FIRST).
parity_of() {
  local nc="$1" na="$2" ga="$3" nrc="$4" grc="$5" n=0 g=0 _d=""
  n="$(awk 'END { print NR }' "$na")"; g="$(awk 'END { print NR }' "$ga")"
  if [ "$PARITY_RC2_FIRST" = 1 ]; then
    # rc 2 first, and from either side: a boundary means that side judged NOTHING, and comparing a
    # judgement with a silence is how a leg gets a verdict it never earned.
    if [ "$nrc" = 2 ] || [ "$grc" = 2 ]; then return 2; fi
    [ -s "$nc" ] || return 2     # rc 0 and no bytes is "did not run", not "agreed"
    [ "$n" -gt 0 ] || return 2   # zero recognizable arms = no comparison happened
    [ "$g" -gt 0 ] || return 2
  fi
  if [ "$nrc" != "$grc" ]; then
    printf 'PARITY DIFF: the exit codes differ — native %s, engine %s\n' "$nrc" "$grc"
    return 1
  fi
  if [ "$PARITY_STRICT_ARMS" = 1 ] && [ "$n" != "$g" ]; then
    _d="$(diff "$na" "$ga" 2>/dev/null | sed -n '1,40p' | sed 's/^/      | /')"
    printf 'PARITY DIFF: the arm counts differ — native %s, engine %s\n' "$n" "$g"
    [ -z "$_d" ] || printf '%s\n' "$_d"
    return 1
  fi
  if [ "$PARITY_STRICT_WORDS" = 1 ] && ! cmp -s "$na" "$ga"; then
    _d="$(diff "$na" "$ga" 2>/dev/null | sed -n '1,40p' | sed 's/^/      | /')"
    printf 'PARITY DIFF: %s arm(s) on both sides, but the verdict words differ\n' "$n"
    [ -z "$_d" ] || printf '%s\n' "$_d"
    return 1
  fi
  # Equal, non-zero, both sides: the legs agree that the leg is RED. Parity of failure is not a parity
  # this tool certifies — a wrap that only reproduces a failure says nothing about the arms.
  [ "$nrc" = 0 ] \
    || { printf 'PARITY DIFF: both sides exited %s — they agree the leg is red, which is not a pass\n' "$nrc"; return 1; }
  printf 'PARITY: native and engine agree — %s arm(s), rc 0 both sides\n' "$n"
  return 0
}
# <<< MUTABLE

usage() {
  cat <<'USAGE'
usage: bash scripts/bench/win/gate-parity.sh [--self-test] -- <argv>

Runs <argv> on this seat, and the SAME <argv> through hl_wsl_route, then compares rc, the
recognized arm count and the verdict words (CR / drive-letter / temp-path noise normalized).

exit 0  PARITY        same rc (0), same arm count, same verdict words
exit 1  PARITY DIFF   the answers differ; both arm counts are printed
exit 2  CANNOT RUN    either side exited 2, or a side printed no bytes, or a side produced
                      zero recognizable arms — nothing was judged, so no parity is claimed

The argv head matters: hl_wsl_route knows an engine-side launcher for a python|python3|py|bash|sh head
only, so pass the leg as `bash <path>` (or `python3 <path>`) — any other head is DECLINED and runs at
home twice, which makes the parity verdict vacuous rather than wrong.
USAGE
}

# capture <out> <mode> <argv…> — mode: native, or route (whatever door the route is pointing at). The
# crossed leg is told which side it is on by the DOOR alone.
capture() {
  local _out="$1" _mode="$2"; shift 2
  case "$_mode" in
    # HL_PARITY_GUEST is dropped HERE, not merely absent from the environment: a fixture must not be
    # able to take the guest flavour on the native side because some parent shell happened to export it.
    native) ( unset HL_PARITY_GUEST; cd "$REPO" 2>/dev/null || exit 2; exec "$@" ) >"$_out" 2>&1 ;;
    route)  ( unset HL_PARITY_GUEST; cd "$REPO" 2>/dev/null || exit 2; hl_wsl_route "$@" ) >"$_out" 2>&1 ;;
    *) return 2 ;;
  esac
  return $?
}

# run_parity <crossed-label> <out> <mode> <argv…> — the two runs, the printed record, one verdict.
run_parity() {
  local _lbl="$1" _out="$2" _mode="$3"; shift 3
  local _nf="$_out.native" _gf="$_out.guest" _na="$_out.native-arms" _ga="$_out.guest-arms"
  local _nrc _grc _vrc _ninfo _ginfo _ncount _gcount _nwords _gwords
  capture "$_nf" native "$@"; _nrc=$?
  capture "$_gf" "$_mode" "$@"; _grc=$?
  _ninfo="$(_arm_scan "$_nf" "$_na")"
  _ginfo="$(_arm_scan "$_gf" "$_ga")"
  _ncount="${_ninfo%%$'\t'*}"; _nwords="${_ninfo#*$'\t'}"
  _gcount="${_ginfo%%$'\t'*}"; _gwords="${_ginfo#*$'\t'}"
  printf '  native    rc %-2s · %2s arm(s) · %s\n' "$_nrc" "$_ncount" "${_nwords:-no verdict word recognized}"
  printf '  %-9s rc %-2s · %2s arm(s) · %s\n' "$_lbl" "$_grc" "$_gcount" "${_gwords:-no verdict word recognized}"
  parity_of "$_nf" "$_na" "$_ga" "$_nrc" "$_grc"; _vrc=$?
  if [ "$_vrc" = 2 ]; then
    printf '      CANNOT RUN — nothing was compared: a side hit a boundary of its own seat, or a side\n'
    printf '      judged nothing. The arm recognizer in force is:\n        %s\n' "$(_recognizer_line)"
    printf '      If this leg reports its arms another way, EXTEND that expression here:\n        %s\n' \
      "${BASH_SOURCE[0]}"
  fi
  return $_vrc
}

# _side_prelude — what a mutated copy needs before it can judge: the lib, and the same stub door the
# real self-test raised. Without the door the mutant would compare native against native — a vacuous
# green that would "prove" the teeth of a rule that was never asked.
_side_prelude() {
  # shellcheck source=/dev/null
  . "$REPO/scripts/lib/wsl-route.sh"
  [ -n "${HL_PARITY_STUB:-}" ] && stub_on "$HL_PARITY_STUB"
  return 0
}

# mutate_parity <out> <assignments> <mode> <argv…> — re-judge one fixture with one or more decision
# flags weakened, over a COPY of the region above. The awk stops at the END marker because a sed range
# would restart at the next `# >>> MUTABLE` — which this very line contains (found the hard way: the
# "mutant" then redefined the whole rest of the file, including its own extractor).
mutate_parity() {
  local _out="$1" _assign="$2" _mode="$3"; shift 3
  local _mut="$_out.mutant"
  { awk '/# >>> MUTABLE/{f=1} f{print} f && /# <<< MUTABLE/{exit}' "${BASH_SOURCE[0]}"
    printf '%s\n' "$_assign"
  } >"$_mut"
  (
    # shellcheck source=/dev/null
    . "$_mut"
    _side_prelude
    run_parity MUTED "$_out.mut" "$_mode" "$@"
  )
}

# --------------------------------------------------------------------------- #
# SELF-TEST — the stub door, the live door, and the four mutations.                    #
# --------------------------------------------------------------------------- #

# The stub wsl.exe, echoed as a path. It answers the lib's probe (door, distro, tree, launcher,
# interpreter, git) and then executes the leg IN THIS FILESYSTEM as the guest, with HL_PARITY_GUEST set.
# Two honest simplifications, both of which the arms above depend on: it does not `cd` to `--cd` (the
# crossed argv of this repo's legs is repo-relative, so the seat's cwd IS the tree the leg reads), and it
# does not apply the guest PATH (that pin is the lib's own decision and lib/wsl-route.sh --self-test is
# where it is proved). What it must get right is executing the leg at all — an arm that never ran on the
# far side and an arm the far side declined to judge look identical in the output.
_stub_exe() {
  local _d="${TMPDIR:-/tmp}/gate-parity-stub-$$"
  rm -rf "$_d"; mkdir -p "$_d" || return 1
  cat >"$_d/wsl-stub" <<'STUB'
#!/usr/bin/env bash
# A stub door for bench/win/gate-parity.sh --self-test. Parses the real argv shape
# (-d DISTRO --cd PATH -- guest argv…), answers the probe's questions, then RUNS THE LEG HERE with
# HL_PARITY_GUEST=1. A leg that cannot be executed here has no business in this self-test.
set -u
d=""; wd=""; mode="${HL_PARITY_STUB_MODE:-ok}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -d) d="$2"; shift 2 ;;
    --cd) wd="$2"; shift 2 ;;
    --) shift; break ;;
    *) shift ;;
  esac
done
{ [ -z "$d" ] || [ "$d" = "${HL_PARITY_STUB_DISTRO:-Debian}" ]; } || { echo "stub: unknown distro $d" >&2; exit 127; }
[ "$mode" != rcfail ] || exit 3
if [ "${1:-}" = env ] || [ "${1:-}" = /usr/bin/env ]; then
  shift
  while [ "$#" -gt 0 ]; do case "$1" in *=*) shift ;; *) break ;; esac; done
fi
case "${1:-}" in
  */sh)
    # The probe's ONE question. `--cd`'s value must come back as pwd or the route goes OFF and every arm
    # then grades a refusal instead of a comparison — which is why this line is the stub's load-bearing one.
    case "${3:-}" in
      *'command -v bash'*)
        printf '%s\nLinux\n%s\n%s\n' "$wd" "${HL_PARITY_STUB_BASH:-/usr/bin/bash}" "${HL_PARITY_STUB_PY:-/usr/bin/python3}" ;;
      *) printf 'ok  the stub ran a shell leg\n' ;;
    esac ;;
  */python3 | */python)
    printf '%s\n' "${HL_PARITY_STUB_PY:-/usr/bin/python3}" ;;
  */git | git)
    printf '%s\n' "$wd" ;;
  */bash | */sh)
    HL_PARITY_GUEST=1 "${BASH:-bash}" "${@:2}" ;;
  *)
    echo "stub: unexpected guest argv: $*" >&2; exit 127 ;;
esac
STUB
  chmod +x "$_d/wsl-stub" || return 1
  printf '%s' "$_d/wsl-stub"
}

# stub_on <exe> — raise the route against the stub. Every piece of lib state is cleared with STATEMENTS
# first: lib/wsl-route.sh's own lesson is that a leftover HL_WSL_ON=1 is exactly what a control expects,
# so an arm that grades a leftover verdict is worse than no arm. The class is passed, not read, so the
# arms grade this repo's decisions rather than the distro installed on the host.
stub_on() {
  HL_WSL=auto; _HL_WSL_PROBED=0; HL_WSL_ON=0; HL_WSL_WHY=""; HL_WSL_PY=""; HL_WSL_BASH=""
  HL_WSL_GIT=0; HL_WSL_GIT_WHY=""; HL_WSL_MNT=""; HL_WSL_GUEST=(); HL_WSL_EXE="$1"
  hl_wsl_probe "$REPO" win11 /mnt/M/tree >/dev/null 2>&1
}

# _ctl_leg <dir> <rc> — a leg that proves the stub is a DOOR and not a replay: two arms, each naming the
# flavour of the side that ran it, and the exit code the arm was told to exit with.
_ctl_leg() {
  local _f="$1/ctl-leg-$2.sh"
  { printf '%s\n' '#!/usr/bin/env bash' \
      'if [ -n "${HL_PARITY_GUEST:-}" ]; then printf "ok  flavour: guest\n"; else printf "ok  flavour: native\n"; fi' \
      'printf "ok  both sides answer\n"' \
      "exit $2"; } >"$_f"
  printf '%s' "$_f"
}

_st_ok() { printf '  ok: %s\n' "$1"; _st_n=$((_st_n + 1)); }
_st_no() { printf 'SELFTEST FAIL: %s\n' "$1"; _st=$((_st + 1)); }

st_fixture() { # st_fixture <name> <want-rc> <why>
  local name="$1" want="$2" why="$3" _out _rc
  _out="$_st_tmp/$name"
  if run_parity engine "$_out" route bash "scripts/testdata/gate-parity/$name.sh" >"$_out.log" 2>&1
  then _rc=0; else _rc=$?; fi
  if [ "$_rc" != "$want" ]; then
    _st_no "$name answered rc $_rc, want $want ($why)"
    sed 's/^/      | /' <"$_out.log"
    return 0
  fi
  # An rc-2 verdict must not claim a comparison. PARITY is a word this runner prints only when it
  # compared — matched case-sensitively on a word, because `gate-parity` in a printed path is not a claim.
  if [ "$want" = 2 ] && grep -qw PARITY "$_out.log"; then
    _st_no "$name answered rc 2 AND printed the parity word — a boundary is not a comparison"
    return 0
  fi
  if [ "$name" = "loses-an-arm" ]; then
    # The count is the finding, so the finding must be PRINTED: a red that makes the reader diff the
    # corpus by hand is a red that gets muted.
    grep -q 'native 3, engine 2' "$_out.log" \
      && _st_ok "$name → rc $_rc ($why)" \
      || _st_no "$name reddened without naming both arm counts (native 3, engine 2)"
    return 0
  fi
  _st_ok "$name → rc $_rc ($why)"
}

self_test() {
  local _name _rest _want _why _out _rc _got _in _pi _ps _vi
  _st=0; _st_n=0
  _st_tmp="$(mktemp -d "${TMPDIR:-/tmp}/gate-parity-st-XXXXXX")" || return 1
  # Scratch the self-test owns, cleaned on the way out: its corpus and mutant files, and the stub door's
  # directory. Nothing here writes inside the checkout, which is the rule that matters — an untracked file
  # left in the primary hard-fails the merge station's own gate, and a gate item that litters the tree is
  # a lane's bug, not the tree's.
  trap "rm -rf '$_st_tmp' \"${HL_PARITY_STUB%/*}\"" EXIT

  printf '== the recognizer: what counts as an arm ==\n'
  printf 'ok  one\nSKIP: two\nchecked the tree in prose\n' >"$_st_tmp/probe"
  _pi="$(_arm_scan "$_st_tmp/probe" "$_st_tmp/probe.arms")"
  [ "${_pi%%$'\t'*}" = 2 ] \
    && _st_ok "two verdict lines out of three recognized; the prose line is not an arm" \
    || _st_no "the recognizer does not read this tree's verdict lines"
  # The words HALF of the same scan, pinned: `ok  ` carries no colon and `SKIP:` does, so one expression
  # that forgets the colon reports the shape of this repo's legs as `? x2` — an unhelpful label at best,
  # and a reason a reader would stop trusting the printed histogram.
  [ "${_pi#*$'\t'}" = "ok x1 · SKIP x1" ] \
    && _st_ok "the histogram reads the verdict words it is shown (ok x1 · SKIP x1), not a question mark" \
    || _st_no "the verdict-word histogram printed '${_pi#*$'\t'}' for an ok line and a SKIP line"
  printf 'checked the tree\nrewrote nothing\n' >"$_st_tmp/prose"
  _ps="$(_arm_scan "$_st_tmp/prose" "$_st_tmp/prose.arms")"
  [ "${_ps%%$'\t'*}" = 0 ] \
    && _st_ok "prose yields ZERO arms — the shape the rc-2 rule exists to refuse" \
    || _st_no "prose was counted as arms"
  # THE HARNESS VOCABULARY — the words this repo's harness self-tests actually answer with. Without them
  # the runner answers rc 2 with `0 arm(s)` on BOTH sides of a leg that printed 17 verdict lines each
  # (measured 2026-10-31 on `bash scripts/bench/win/gate-parity.sh -- bash
  # scripts/harness/pi-tui-config.sh --self-test`). A recognizer blind to those words reports "nothing
  # was compared" about a leg that compared everything it has: blindness wearing a boundary's face, and
  # it makes a leg unwrappable, because a wrap is authorised by a parity line and rc 2 never prints one.
  # Pinned HERE so narrowing the expression reddens an arm instead of returning rc 2 from every harness
  # leg, one lane at a time.
  # Line 4 is the canary that keeps the widening a WORD rule: `uncaught` and `GREENHOUSE` contain the
  # words and carry no verdict. Lines 5 and 6 pin the labelling rule stated in _arm_scan: a real SKIP
  # verdict keeps its label even beside a GREEN-carrying line, and an explanatory word does not steal one.
  printf 'foreign-probe    GREEN\nnoms-canary      caught\nchecked the tree, rewrote nothing in prose\nuncaught exception in a fixture, GREENHOUSE gas\nforeign-probe    SKIP (no tmux) — install ran, the load probe cannot\nskip-arm         GREEN (rc 2 = SKIP, not a pass)\n' >"$_st_tmp/vocab"
  _vi="$(_arm_scan "$_st_tmp/vocab" "$_st_tmp/vocab.arms")"
  if [ "${_vi%%$'\t'*}" = 4 ] && [ "${_vi#*$'\t'}" = "ok x3 · SKIP x1" ]; then
    _st_ok "the words a harness leg answers with are ARMS — 4 of 6 lines counted (GREEN, caught; not uncaught/GREENHOUSE), and the severity label survives them"
  else
    _st_no "the harness vocabulary gave ${_vi%%$'\t'*} arm(s) and the histogram '${_vi#*$'\t'}' — want 4 and 'ok x3 · SKIP x1'; the recognizer no longer reads what this repo's legs print"
  fi

  printf '== the normalizer: each rule on a planted literal ==\n'
  local _before_fail=$_st
  while IFS='|' read -r _in _want; do
    [ -n "$_in" ] || continue
    _got="$(printf '%s\n' "$_in" | normalize)"
    [ "$_got" = "$_want" ] || _st_no "normalize: $_in -> $_got (want $_want)"
  done <<'PAIRS'
worked on D:/source/x|worked on /mnt/d/source/x
worked on D:\source\x|worked on /mnt/d/source/x
worked on /d/source/x|worked on /mnt/d/source/x
kept /mnt/d/source/x|kept /mnt/d/source/x
in C:\Users\amy\AppData\Local\Temp\run\out|in /tmp/run/out
in C:/Users/amy/AppData/Local/Temp/run/out|in /tmp/run/out
in /c/Users/amy/AppData/Local/Temp/run/out|in /tmp/run/out
in /mnt/c/Users/amy/AppData/Local/Temp/run/out|in /tmp/run/out
in /tmp/tmp.Ab12Cd34Ef/x|in /tmp/mktemp/x
route: this leg ran in Debian (/mnt/d/x)|
PAIRS
  [ "$_st" = "$_before_fail" ] \
    && _st_ok "CR, the route banner, four drive spellings, both temp roots and a mktemp suffix all normalize away" \
    || true

  printf '== the planted legs, across the stub door ==\n'
  # One fixture, one planted difference, one expected rc. This IS the spec of the exit contract above.
  for _name in "loses-an-arm|1|rc 0 both sides and one arm never reached the engine" \
               "path-spelling|0|the same three arms, spelled as each seat spells a path" \
               "cannot-run|2|the engine side exits 2 with a SKIP — a boundary, not a diff" \
               "no-tool-here|2|neither side could run — two silences are not an agreement" \
               "silent|2|rc 0 and no bytes — did not run, not parity" \
               "no-verdict-words|2|rc 0 and zero recognized arms — nothing to compare"; do
    _rest="${_name#*|}"; _want="${_rest%%|*}"; _why="${_rest#*|}"
    st_fixture "${_name%%|*}" "$_want" "$_why"
  done

  printf '== teeth: mutations of this file, so a weakened rule cannot pass unnoticed ==
'
  # Three mutations of the comparison, each over the SAME fixture, so the arms say WHICH rule does the
  # work. A canary that stayed red while its own rule was muted would be reddening some other code path,
  # which is no evidence at all.
  # (1) Keep ONLY the arm-count rule (mute the verdict-word comparison): loses-an-arm must STILL redden.
  if mutate_parity "$_st_tmp/mut-count" "PARITY_STRICT_WORDS=0" route        bash scripts/testdata/gate-parity/loses-an-arm.sh >"$_st_tmp/mut-count.log" 2>&1; then
    _st_no "with only the arm-count rule left, loses-an-arm went GREEN - the count comparison has no teeth"
    sed 's/^/      | /' <"$_st_tmp/mut-count.log"
  elif grep -q 'the arm counts differ' "$_st_tmp/mut-count.log" \
       && grep -q 'native 3, engine 2' "$_st_tmp/mut-count.log"; then
    _st_ok "muted the verdict-word comparison and loses-an-arm still REDDENS by arm count alone - that rule has teeth"
  else
    _st_no "the arm-count mutation reddened without naming both counts - which rule answered?"
    sed 's/^/      | /' <"$_st_tmp/mut-count.log"
  fi
  # (2) The mirror: mute ONLY the count and the verdict words must still catch the lost arm.
  if mutate_parity "$_st_tmp/mut-words" "PARITY_STRICT_ARMS=0" route \
       bash scripts/testdata/gate-parity/loses-an-arm.sh >"$_st_tmp/mut-words.log" 2>&1; then
    _st_no "muted the arm count and loses-an-arm went GREEN - the verdict-word comparison has no teeth"
    sed 's/^/      | /' <"$_st_tmp/mut-words.log"
  elif grep -q 'the verdict words differ' "$_st_tmp/mut-words.log"; then
    _st_ok "muted the arm count and loses-an-arm still REDDENS by verdict words - the second rule has teeth too"
  else
    _st_no "the verdict-word mutation reddened without naming the words - which rule answered?"
    sed 's/^/      | /' <"$_st_tmp/mut-words.log"
  fi
  # (3) Mute BOTH comparison rules: the fixture must go GREEN. If it stayed red with nothing left to
  # compare, something outside the decision region is doing the reddening and arms (1)+(2) proved nothing.
  if mutate_parity "$_st_tmp/mut-both" "$(printf 'PARITY_STRICT_ARMS=0
PARITY_STRICT_WORDS=0')" route        bash scripts/testdata/gate-parity/loses-an-arm.sh >"$_st_tmp/mut-both.log" 2>&1; then
    _st_ok "muting BOTH comparison rules turns loses-an-arm GREEN - its red comes from those rules, not a side effect"
  else
    _st_no "loses-an-arm stayed red with both comparison rules muted - something else reddens it"
    sed 's/^/      | /' <"$_st_tmp/mut-both.log"
  fi
  # (4) The precedence. Mute it and the boundary leg must come back as a PARITY DIFF (rc 1) instead of
  # the honest rc 2 - wrong in the interesting direction: a reader would conclude the leg DISAGREES
  # across the door when in fact nothing was judged on either side.
  if mutate_parity "$_st_tmp/mut-rc2" "PARITY_RC2_FIRST=0" route        bash scripts/testdata/gate-parity/cannot-run.sh >"$_st_tmp/mut-rc2.log" 2>&1; then
    _st_no "muted precedence still answers rc 2 for a boundary - the rc-2 rule is doing no work"
    sed 's/^/      | /' <"$_st_tmp/mut-rc2.log"
  elif grep -q 'PARITY DIFF' "$_st_tmp/mut-rc2.log"; then
    _st_ok "muted precedence turns cannot-run's boundary into a PARITY DIFF - the ordering is what answers rc 2"
  else
    _st_no "muted precedence reddened without the parity word - the fixture never reached the comparison"
    sed 's/^/      | /' <"$_st_tmp/mut-rc2.log"
  fi

  printf '== the stub is a door, not a replay ==\n'
  local _ctl3 _ctl0
  _ctl3="$(_ctl_leg "$_st_tmp" 3)"
  if run_parity engine "$_st_tmp/stub-rc" route bash "$_ctl3" >"$_st_tmp/stub-rc.log" 2>&1; then
    _st_no "the stub door swallowed a non-zero rc — both sides would read as a diff, never as a verdict"
  elif grep -Eq "engine[[:space:]]+rc 3" "$_st_tmp/stub-rc.log"; then
    _st_ok "the stub door passes the far exit code through (a leg that exits 3 comes back rc 3 on the crossed side)"
  else
    _st_no "the stub-door leg did not report its rc"
    sed 's/^/      | /' <"$_st_tmp/stub-rc.log"
  fi
  # The flavour, both directions: the guest half must be reached THROUGH THE DOOR, and the native half
  # must not be able to take it. If this ever goes red, the fixtures are lying about which side ran.
  _ctl0="$(_ctl_leg "$_st_tmp" 0)"
  # The verdict here is a DIFF and must be: the leg answers differently on the two seats. What this arm
  # grades is WHERE each half ran — a guest flavour on the native side, or none on the crossed side,
  # means the fixtures are lying about which side ran and every arm above is grading a fiction.
  run_parity engine "$_st_tmp/stub-flav" route bash "$_ctl0" >"$_st_tmp/stub-flav.log" 2>&1; _rc=$?
  if [ "$_rc" != 1 ]; then
    _st_no "a leg that answers differently per seat answered rc $_rc, want 1 — the two sides were not compared"
    sed 's/^/      | /' <"$_st_tmp/stub-flav.log"
  elif grep -q 'flavour: native' "$_st_tmp/stub-flav.native" \
     && grep -q 'flavour: guest'  "$_st_tmp/stub-flav.guest"; then
    _st_ok "the native side drops HL_PARITY_GUEST and the stub door sets it — both arms, both sides, seen as a diff"
  else
    _st_no "HL_PARITY_GUEST did not arrive through the door as declared"
    sed 's/^/      | /' <"$_st_tmp/stub-flav.log"
  fi

  printf '== the live door (the real engine, or this seat when it has no route) ==\n'
  HL_WSL=auto; _HL_WSL_PROBED=0; HL_WSL_ON=0; HL_WSL_WHY=""; HL_WSL_PY=""; HL_WSL_BASH=""
  HL_WSL_GIT=0; HL_WSL_GIT_WHY=""; HL_WSL_MNT=""; HL_WSL_GUEST=(); HL_WSL_EXE=wsl.exe
  hl_wsl_probe "$REPO" >/dev/null 2>&1
  if [ "$HL_WSL_ON" = 1 ]; then
    if run_parity engine "$_st_tmp/live" route bash scripts/testdata/gate-parity/portable.sh \
         >"$_st_tmp/live.log" 2>&1; then
      _st_ok "portable.sh agrees across the REAL door ($HL_WSL_MNT) — the normalizer was graded on this box"
      printf '%s' "$HL_WSL_WHY" | grep -qi 'git=unavailable' \
        && printf '      NOTE: git=unavailable here, so a verdict about a git-READING leg is worthless\n'
    else
      _rc=$?
      if [ "$_rc" = 2 ]; then
        _st_ok "portable.sh across the real door answered rc 2 and named the boundary instead of a parity"
        sed 's/^/      | /' <"$_st_tmp/live.log"
      else
        _st_no "portable.sh disagrees across the real door (rc $_rc) — read the diff before wrapping anything"
        sed 's/^/      | /' <"$_st_tmp/live.log"
      fi
    fi
  else
    printf '  SKIP: live-door arm skipped — this seat has no route (%s); the stub arms still ran\n' "$HL_WSL_WHY"
    _st_n=$((_st_n + 1))
  fi

  printf '\n%s arm(s) checked, %s failure(s)\n' "$_st_n" "$_st"
  [ "$_st" = 0 ]
}

# --------------------------------------------------------------------------- #
# Main                                                                          #
# --------------------------------------------------------------------------- #
_selftest=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --self-test) _selftest=1; shift ;;
    -h | --help) usage; exit 0 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

if [ "$_selftest" = 1 ]; then
  _st=0 _st_n=0 _st_tmp=""
  HL_PARITY_STUB="$(_stub_exe)" || { echo "FATAL: could not build the stub door" >&2; exit 2; }
  stub_on "$HL_PARITY_STUB"
  if [ "$HL_WSL_ON" != 1 ]; then
    printf 'FATAL: the stub door did not raise the route (%s) — every arm would grade a refusal\n' "$HL_WSL_WHY" >&2
    exit 2
  fi
  export HL_PARITY_STUB        # the mutants raise the same door, so they judge the same two sides
  printf 'recognizer: %s\n' "$(_recognizer_line)"
  printf 'stub door: %s (HL_WSL_EXE) · guest flavour: HL_PARITY_GUEST\n' "$HL_PARITY_STUB"
  if self_test; then printf 'self-test: all arms caught, control clean\n'; exit 0; fi
  exit 1
fi

if [ "$#" = 0 ]; then usage; exit 2; fi
[ "${1:-}" = "--" ] && shift
if [ "$#" = 0 ]; then usage; exit 2; fi

hl_wsl_probe "$REPO" >/dev/null 2>&1
printf 'route: %s\n' "$HL_WSL_WHY"
if [ "$HL_WSL_ON" = 1 ] && [ "$HL_WSL_GIT" != 1 ]; then
  printf 'NOTE: the engine cannot open this checkout through git — a parity verdict about a git-reading\n'
  printf '      leg is WORTHLESS here (two runs over a checkout neither side could read still agree)\n'
fi
printf 'recognizer: %s\n' "$(_recognizer_line)"
_run_out="${TMPDIR:-/tmp}/gate-parity-run-$$"
trap 'rm -f "$_run_out".*' EXIT
run_parity engine "$_run_out" route "$@"
