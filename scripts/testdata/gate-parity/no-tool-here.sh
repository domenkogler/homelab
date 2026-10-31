#!/usr/bin/env bash
# =====================================================================
# testdata/gate-parity/no-tool-here — the planted leg that cannot run on EITHER
# seat, for bench/win/gate-parity.sh --self-test.
# ---------------------------------------------------------------------
# WHY THIS EXISTS: the rc-2 classification is per SIDE, and the native side needs its own witness.
# A leg that exits 2 here (no rsync on this box, no token, no tmux) has judged nothing, and a runner
# that compared "nothing" with "nothing" and called that parity would be reporting an agreement
# between two silences. rc 2 must win over both a parity claim and a parity diff.
#
# WHAT: one SKIP and exit 2, both seats — the same leg on a laptop that has the tool on neither side
# of the door, which is the measured state of the rsync legs here.
#
# Exit: 2 on both sides, by design.
# =====================================================================
set -uo pipefail

printf 'SKIP: the tool this leg fires is on neither seat of this box — nothing was run\n'
exit 2
