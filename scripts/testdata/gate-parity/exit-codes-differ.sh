#!/usr/bin/env bash
# =====================================================================
# testdata/gate-parity/exit-codes-differ — the planted leg whose ARMS AGREE and
# whose EXIT CODES DO NOT, for bench/win/gate-parity.sh --self-test.
# ---------------------------------------------------------------------
# WHY THIS EXISTS: the runner compares three things per side, and the other fixtures in this folder
# exercise the arm COUNT and the verdict WORDS. The rc rule had no witness, so it could be deleted and
# every fixture here would stay green: three identical arms on both sides satisfy the count rule and the
# word rule, and a runner that only counted arms would call this pair PARITY while one seat answered the
# leg RED and the other answered it GREEN. That pair is not a parity and not a boundary — it is the
# finding, and the runner must name both exit codes when it says so.
#
# WHAT: three arms, identical on both sides — no flavour in the verdict lines, so the count and word
# comparisons cannot be what reddens this leg — and `exit 1` on the engine side, rc 0 here.
#
# HL_PARITY_GUEST is set by the stub door in that runner's --self-test and by nothing else; the runner
# clears it on the native side, so the flavour cannot be taken by accident.
#
# Exit: 0 native · 1 on the guest side. The runner must answer rc 1, PARITY DIFF, naming native 0 and
# engine 1 — never rc 2 (neither side hit a boundary) and never rc 0.
# =====================================================================
set -uo pipefail

printf 'ok  arm one: the same verdict on both seats\n'
printf 'ok  arm two: nothing here differs by side\n'
printf 'ok  arm three: the count and the words are equal\n'

# Only the exit code moves, and it moves on the far side: that is the whole planted difference.
if [ -n "${HL_PARITY_GUEST:-}" ]; then
  exit 1
fi
exit 0
