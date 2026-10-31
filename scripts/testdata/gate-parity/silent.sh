#!/usr/bin/env bash
# =====================================================================
# testdata/gate-parity/silent — the planted side that produced NO BYTES and
# exited 0, for bench/win/gate-parity.sh --self-test.
# ---------------------------------------------------------------------
# WHY THIS EXISTS: "it ran and judged nothing" and "nothing ran" are the same line in a log — the
# observation lib/wsl-route.sh writes into its own header. A leg that exits 0 having printed nothing
# therefore cannot be compared at all, and a runner that saw 0 arms on both sides and called that
# parity would certify any leg that never started. This fixture is that pair: rc 0, no bytes.
#
# Exit: 0, and that is the whole finding.
# =====================================================================
set -uo pipefail
exit 0
