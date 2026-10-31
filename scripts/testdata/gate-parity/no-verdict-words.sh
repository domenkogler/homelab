#!/usr/bin/env bash
# =====================================================================
# testdata/gate-parity/no-verdict-words — the planted leg whose corpus the arm
# recognizer cannot read, for bench/win/gate-parity.sh --self-test.
# ---------------------------------------------------------------------
# WHY THIS EXISTS: the recognizer counts an arm when a line carries a verdict word, so a leg that
# reports in prose ("all good", "done", a table of numbers) has NO arms to compare — and a runner
# that answered "0 arms vs 0 arms, parity" would be certifying a comparison it never made. This
# fixture plants that corpus and the answer the runner owes it: rc 2, with the recognition command
# printed so the reader can extend the recognizer rather than mute the leg.
#
# Exit: 0, with three lines of prose that carry no verdict word.
# =====================================================================
set -uo pipefail

printf 'checked the tree\nrewrote nothing\nthree of three lines agree\n'
exit 0
