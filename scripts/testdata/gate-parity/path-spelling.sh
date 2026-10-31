#!/usr/bin/env bash
# =====================================================================
# testdata/gate-parity/path-spelling — three arms that mean the SAME THING on
# both seats and are spelled differently, for bench/win/gate-parity.sh
# --self-test.
# ---------------------------------------------------------------------
# WHY THIS EXISTS: the other direction from loses-an-arm. A crossed leg whose verdicts agree but
# whose LINES differ by nothing but spelling — `/mnt/d/…` where this seat writes `D:\…`, the engine's
# `/tmp` where the seat writes its own AppData temp — must stay GREEN. If the runner reddens on that,
# every wrap in the fleet turns into a permanent red that teaches the reader to ignore the tool, and
# the class it exists to catch goes unnoticed under the noise.
#
# WHAT: three arms, identical in meaning on both sides, carrying all three spellings the pair can
# produce — a drive path written the Windows way here and the Debian way there, a temp root written
# the seat's way here and `/tmp` there, and the same path written Git-Bash's `/d/…` way against the
# engine's `/mnt/d/…`. The values are PLANTED rather than read from the host so the arm behaves the
# same on a Debian seat, where the route is off by design but the comparison still has to be graded.
#
# HL_PARITY_GUEST is set by the stub door in that runner's --self-test and by nothing else; the
# runner clears it on the native side, so the guest flavour cannot be taken by accident.
#
# Exit: 0 both sides, three arms both sides.
# =====================================================================
set -uo pipefail

if [ -n "${HL_PARITY_GUEST:-}" ]; then
  printf 'ok  reads /mnt/d/fixture/tree/golden.json\n'
  printf 'ok  worked in /tmp/gate-parity/out\n'
  printf 'ok  compares it with /mnt/d/fixture/tree/golden.json\n'
else
  printf 'ok  reads D:/fixture/tree/golden.json\n'
  printf 'ok  worked in C:/Users/fixture/AppData/Local/Temp/gate-parity/out\n'
  printf 'ok  compares it with /d/fixture/tree/golden.json\n'
fi
exit 0
