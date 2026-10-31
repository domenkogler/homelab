#!/usr/bin/env bash
# =====================================================================
# testdata/gate-parity/loses-an-arm — the planted leg that LOSES AN ARM across
# the door, for bench/win/gate-parity.sh --self-test.
# ---------------------------------------------------------------------
# WHY THIS EXISTS: a wrapped leg that runs FAST on the engine can still be a lie. The failure the
# win11 seat keeps meeting is an arm that answers NOTHING on the far side — a tool the engine does
# not have, a path the engine cannot open, an early return on a seat test — so the crossed run
# finishes rc 0 having judged fewer arms than the native run did. The exit code is identical; only
# the arm count moved. This file plants exactly that, in the open, so the runner is graded against a
# known difference instead of against the luck of a real leg.
#
# WHAT: three arms here, two there. The third stands for the arm that shells out to something the
# Debian engine does not carry; asking whether it resolves and then saying NOTHING when it does not
# is the shape being planted, because that is the shape that reads green. The honest version of the
# same arm prints `SKIP:` and exits 2 — `cannot-run.sh` plants that one, and the runner answers a
# different rc for it.
#
# HL_PARITY_GUEST is set by the stub door in that runner's --self-test and by nothing else; the
# runner clears it on the native side, so the guest flavour cannot be taken by accident.
#
# Exit: 0 on both sides — which is the whole point: rc 0, two different arm counts.
# =====================================================================
set -uo pipefail

printf 'ok  arm one: the tree half\n'
printf 'ok  arm two: the sandbox half\n'
if [ -z "${HL_PARITY_GUEST:-}" ]; then
  printf 'ok  arm three: the half the engine never reached\n'
fi
exit 0
