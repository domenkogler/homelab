#!/usr/bin/env bash
# =====================================================================
# testdata/gate-parity/portable — a real leg that answers the SAME THREE ARMS on
# either seat, spelled however the seat it is standing on spells them, for
# bench/win/gate-parity.sh --self-test's live-door arm.
# ---------------------------------------------------------------------
# WHY THIS EXISTS: every other fixture in this folder is answered by a stub door, which grades the
# comparison but proves nothing about the door. This leg is run for real, natively and through
# hl_wsl_route, so the normalizer is graded against the two spellings this box actually produces
# rather than against planted literals. It reads nothing but its own working directory and a temp
# directory it makes and removes, which is the conjunction lib/wsl-route.sh requires of a leg that
# crosses: no git, no network, no seat HOME, no seat-class question.
#
# Exit: 0. Three arms on both sides — a side that lost one is the finding, not the expectation.
# =====================================================================
set -uo pipefail

_t="$(mktemp -d)" || exit 2
printf 'ok  the checkout reads %s\n' "$PWD"
printf 'ok  the scratch dir reads %s\n' "$_t"
rmdir "$_t" 2>/dev/null || true
printf 'ok  control: three arms, whichever way this seat spells a path\n'
exit 0
