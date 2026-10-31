#!/usr/bin/env bash
# =====================================================================
# testdata/gate-parity/cannot-run — the planted leg whose ENGINE side cannot run,
# for bench/win/gate-parity.sh --self-test.
# ---------------------------------------------------------------------
# WHY THIS EXISTS: rc 2 is the repo's answer to a boundary — "this seat lacks the thing the leg
# needs", the shape testdata/rsync-max-delete/run.sh gives a missing rsync. A parity runner that
# read that pair (three arms here, one SKIP there, rc 2 on one side) as a PARITY DIFF would be wrong
# in the interesting direction: nothing about the leg was judged on either side, so the honest answer
# is that parity was not established, not that it failed. The runner must answer rc 2 and say so
# without using the parity word.
#
# WHAT: native = three arms, rc 0 (the seat has the tool). Guest = one SKIP and rc 2 (the engine does
# not). That is the pair the laptop actually presents for the legs whose arms shell out to rsync.
#
# HL_PARITY_GUEST is set by the stub door in that runner's --self-test and by nothing else; the
# runner clears it on the native side, so the guest flavour cannot be taken by accident.
#
# Exit: 0 natively · 2 on the guest side, printed with the SKIP that names the boundary.
# =====================================================================
set -uo pipefail

if [ -n "${HL_PARITY_GUEST:-}" ]; then
  printf 'SKIP: rsync is not on this seat'\''s PATH — neither real fire can run here\n'
  exit 2
fi
printf 'ok  shape parity: the flags still match the script\n'
printf 'ok  unbounded: every pending deletion happened\n'
printf 'ok  capped: exactly half happened and rc says 25\n'
exit 0
