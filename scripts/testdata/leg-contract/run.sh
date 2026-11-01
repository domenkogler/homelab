#!/usr/bin/env bash
# =====================================================================
# testdata/leg-contract — the DECLARING leg: what `hl_wsl_needs` does, run in the tree instead of
# asserted in a checker's planted temp directory.
# ---------------------------------------------------------------------
# WHY THIS EXISTS. `lib/wsl-route.sh` says a wrapped leg may need no tool the Debian engine lacks, and
# `hl_wsl_needs <tool>` is where a leg says WHICH tool — because `hl_wsl_route` passes the far exit code
# straight through, so a crossed leg that found nothing to run and carried on judging would come back
# rc 0 having proven less. Until this file, nothing in the tree declared anything: the contract's own
# checker could only grade planted strings in a temp tree, and `declarations 0 in 0 file(s)` is not a
# contract that was exercised. This leg is the subject. It declares `rsync`, which this laptop's engine
# lists as ABSENT on BOTH of its seats (re-derive: `bash scripts/lib/wsl-route.sh --self-test`, whose
# last arm prints the live `engine tools:` line), so the rc-2 path runs in the tree rather than in an
# example.
#
# THE SHAPE THE ARMS BUILD — no host, no vault, nothing staged by hand:
#   the declaration  hl_wsl_needs rsync || exit $?     BEFORE anything is judged, so an engine without
#                    rsync stops the leg with `CANNOT RUN` (rc 2) naming the tool, and never reports a
#                    verdict it did not take.
#   the fire         one `rsync -a` from a temp src to a temp dest. The declaration is only honest
#                    because this call exists; a leg that declares a tool it never runs refuses for no
#                    reason, which is the drift the parity arm below catches.
#
# THREE ARMS, and the first two run on a seat with no rsync at all (this laptop's, on both sides):
#   declaration — offline, always. The fire and the declaration must name the SAME tool: a leg whose
#                 call drifted away from its claim either refuses for nothing or crosses for nothing.
#   fire        — needs rsync, wherever it is: the engine's when the leg crossed, this seat's when not.
#
# Usage:
#   bash scripts/testdata/leg-contract/run.sh              # declare, then fire
#   bash scripts/testdata/leg-contract/run.sh --self-test  # the mirror's canaries, no rsync needed
#   bash scripts/testdata/leg-contract/run.sh --declare-only   # stop at the declaration (the --arms seam
#                                                            # of scripts/gate/check-leg-contract.sh)
#   HL_LEG_SCRIPT=<file>   point the mirror arm at another copy of this leg (the canaries do this)
#
# Exit: 0 all arms green · 1 a finding (the claim and the call disagree) ·
#       2 a boundary (this leg needs rsync and the seat it is standing on does not have it) — printed
#       with the tool named, never counted green. `validate-all.sh` maps this 2 to a NOTE: on the engine
#       it is the declaration that answers, at home it is the leg's own probe, and both say the same
#       true thing.
#
# Wired into validate-all.sh through a block, for that reason — and registered with the path and the
# tool named in its reason, which is what scripts/gate/check-leg-contract.sh weighs.
# =====================================================================
set -uo pipefail

_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
# shellcheck source=/dev/null
. "$_hl_d/lib/repo-root.sh"        # sets REPO; FATAL when no root is found
# shellcheck source=/dev/null
. "$REPO/scripts/lib/wsl-route.sh" # hl_wsl_needs: the leg's own claim, answered by THIS run's inventory

SELF="${HL_LEG_SCRIPT:-${BASH_SOURCE[0]}}"

pass=0 fail=0 skip=0
ok()   { printf 'ok    %s\n' "$*"; pass=$((pass + 1)); }
bad()  { printf 'FAIL: %s\n' "$*"; fail=$((fail + 1)); }
skip() { printf 'SKIP: %s\n' "$*"; skip=$((skip + 1)); }

# The ONE tool this leg shells out to on the engine side, as it must appear in the declaration line.
MIRROR_TOOL="rsync"

# arm_declaration — the claim and the call must name ONE tool, read off DISK so a weakened arm reddens
# the canary instead of agreeing with itself:
#   * the declaration line, cut at the `||` so the guard's own words cannot count as the claim;
#   * the fire, located by the `command rsync` line below (keep that call on ONE line — this reads a
#     line, not a parse tree, exactly so that it stays auditable from the shell).
arm_declaration() { # arm_declaration <file> -> 0 mirror, 1 drift
  local file="$1" decl=""
  [ -f "$file" ] || { printf '  cannot read %s\n' "$file"; return 2; }
  decl="$(while IFS= read -r _l; do
            case "$_l" in hl_wsl_needs*) printf '%s' "${_l%%||*}"; break ;; esac
          done <"$file")"
  case "$decl" in
    *"$MIRROR_TOOL"*) : ;;
    *) printf '  the leg fires %s but declares nothing about it (%s) — an undeclared call is the rc-0-lies shape this leg exists to disprove\n' "$MIRROR_TOOL" "$decl"; return 1 ;;
  esac
  # The fire is located by its invocation shape — an `if command rsync` line — so neither this file's
  # prose nor its own canaries can be mistaken for the call site.
  case "$(grep -cE '^[[:space:]]*if command rsync ' "$file")" in
    0) printf '  the declaration names %s and this leg never runs it — a claim with no call behind it refuses on a tool the leg does not need\n' "$MIRROR_TOOL"; return 1 ;;
    1) : ;;
    *) printf '  %s is invoked on more than one line — arm_declaration reads ONE line by design, so add the drift canary before adding a call site\n' "$MIRROR_TOOL"; return 1 ;;
  esac
  return 0
}

# --------------------------------------------------------------------------- #
# The real fire — needs rsync wherever the leg is standing.                     #
# --------------------------------------------------------------------------- #
arm_fire() {
  local w rc out=""
  w="$(mktemp -d)" || { bad "mktemp failed"; return; }
  mkdir -p "$w/src" "$w/dest"
  printf 'one file, one fire\n' > "$w/src/one.txt"
  # `command` so the call cannot resolve to a shell function of the same name, and the trailing
  # redirect keeps rsync's own words out of the arm's verdict line.
  if command rsync -a "$w/src/" "$w/dest/" >"$w/fire.log" 2>&1; then rc=0; else rc=$?; fi
  out="$(tr '\n' ' ' <"$w/fire.log" | cut -c1-160)"
  if [ "$rc" = 0 ] && [ -f "$w/dest/one.txt" ]; then
    ok "fire: rsync moved the file (rc 0) — the declaration named a tool this seat has"
  else
    bad "fire: rsync answered rc $rc with the file ${out:-no output}"
  fi
  rm -rf "$w"
}

# --------------------------------------------------------------------------- #
# --self-test: the mirror's canaries, over the SAME arm the real run calls.     #
# --------------------------------------------------------------------------- #
self_test() {
  local t mut
  t="$(mktemp -d)"
  if arm_declaration "$SELF"; then
    ok "declaration: this leg's claim and its rsync call name one tool"
  else
    bad "declaration: the claim and the call no longer describe one leg"
  fi

  # Canary 1: the call stays, the declaration goes. Green here would mean an undeclared crossing can
  # pass — the exact shape `hl_wsl_route`'s pass-through rc cannot catch on its own.
  mut="$t/undeclared.sh"
  sed 's/^hl_wsl_needs rsync.*/# the declaration went away/' "$SELF" >"$mut"
  if arm_declaration "$mut" >"$t/c1" 2>&1; then
    bad "canary 1: a leg whose rsync call is undeclared still passed the mirror arm"
  else
    ok "canary 1: an undeclared rsync call reddens the mirror arm"
  fi

  # Canary 2: the declaration stays, the call goes. A refusal for a tool the leg never runs is the other
  # direction of the same drift, and it is the one that makes people delete the declaration.
  mut="$t/no-fire.sh"
  sed '/if command rsync -a/d' "$SELF" >"$mut"
  if arm_declaration "$mut" >"$t/c2" 2>&1; then
    bad "canary 2: a leg that declares rsync and never runs it still passed the mirror arm"
  else
    ok "canary 2: a declaration with no call behind it reddens the mirror arm"
  fi

  # Canary 3: the arm must refuse to judge an unreadable file, never answer "mirror holds".
  if arm_declaration "$t/not-there.sh" >/dev/null 2>&1; then
    bad "canary 3: the mirror arm called a missing file a match"
  else
    ok "canary 3: an unreadable leg is refused, not judged"
  fi
  rm -rf "$t"
}

# --------------------------------------------------------------------------- #
# Main                                                                          #
# --------------------------------------------------------------------------- #
case "${1:-}" in
  --self-test)
    printf '== leg-contract fixture: the declaration mirror ==\n'
    self_test
    printf '\n%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
    [ "$fail" = 0 ] || { echo "FAIL: the declaration and the call are no longer one claim"; exit 1; }
    echo "OK: the declaring leg declares what it fires"
    exit 0 ;;
  # --declare-only is the seam scripts/gate/check-leg-contract.sh --arms drives: the door's ANSWER is
  # what is graded there, so this mode stops at the declaration and never asks whether rsync happens to
  # be installed on the seat the arm happens to run from. ONE declaration line serves every mode.
  --declare-only) _declare_only=1 ;;
  "") : ;;
  *) printf 'usage: run.sh [--self-test | --declare-only]\n' >&2; exit 2 ;;
esac

printf '== leg-contract fixture: the declaring leg ==\n'
# THE DECLARATION — before anything is judged, so an engine that lists rsync ABSENT stops this leg with
# `CANNOT RUN` (rc 2) instead of watching it report fewer arms with rc 0. The rc IS the guard.
hl_wsl_needs rsync || exit $?

if [ "${_declare_only:-0}" = 1 ]; then      # the --arms seam: the answer arrived, which is the whole question
  printf 'ok    the leg ran past its declaration\n'
  exit 0
fi

if arm_declaration "$SELF"; then
  ok "declaration: this leg's claim and its rsync call name one tool"
else
  bad "declaration: the claim and the call no longer describe one leg"
fi

if ! type -P rsync >/dev/null 2>&1; then     # type -P, not `command -v`: a leg that defines a function
  # named after a tool would otherwise answer for the function and every arm would fail on rc 127.
  skip "no rsync where this leg is standing — the arms that need it did not run, and rc 2 says that"
  printf '      rather than a verdict: at home this line is the probe; across the door, the refusal\n'
  printf '      came from the declaration above, read against the engine tools: line of this run.\n'
  printf '\n%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
  [ "$fail" = 0 ] || exit 1
  exit 2
fi

arm_fire
printf '\n%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" = 0 ] || { echo "FAIL: the declaring leg did not do the thing it declares"; exit 1; }
echo "OK: the declaring leg declared rsync, ran rsync, and said so"
