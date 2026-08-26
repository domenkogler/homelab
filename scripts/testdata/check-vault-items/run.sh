#!/usr/bin/env bash
# =====================================================================
# Self-test for scripts/check-vault-items.sh (HD-244 + HD-245).
# Runs the scanner against the committed synthetic mini-tree in fixture/
# via --root + --fake-vault: NO op CLI, NO SA token, no real vault access.
#
# Proves (HD-244 regression proof, verbatim class): with metabase-forgejo_ro
# absent from the vault, the fixed scanner lists it — the item is referenced
# ONLY through the metabase entry's `db_ro_item:` registry key on a continuation
# line, invisible to a literal-lookup grep. Also proves the inverse path
# (no false positives on a complete vault), glue-seeded exclusion, disabled-
# entry exclusion, and both --strict outcomes.
#
# Standalone: bash scripts/testdata/check-vault-items/run.sh
# Wired into validate-all.sh.
# =====================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN="$HERE/../../check-vault-items.sh"
FIXTURE="$HERE/fixture"

pass=0
fail=0
ok()   { echo "PASS: $1"; pass=$((pass + 1)); }
bad()  { echo "FAIL: $1"; fail=$((fail + 1)); }

expect_eq() { # desc actual expected
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got: '$2', want: '$3')"; fi
}
expect_contains() { # desc haystack needle
    if printf '%s\n' "$2" | grep -Fxq -- "$3"; then ok "$1"; else bad "$1 (missing line '$3')"; fi
}
expect_absent() { # desc haystack needle
    if printf '%s\n' "$2" | grep -Fxq -- "$3"; then bad "$1 (forbidden line '$3' present)"; else ok "$1"; fi
}

header_counts() { # output  -> echoes "enabled needed have"
    local h
    h="$(printf '%s\n' "$1" | head -n 1)"
    printf '%s %s %s\n' \
        "$(printf '%s\n' "$h" | grep -oE 'enabled services: [0-9]+' | grep -oE '[0-9]+')" \
        "$(printf '%s\n' "$h" | grep -oE 'needed items: [0-9]+' | grep -oE '[0-9]+')" \
        "$(printf '%s\n' "$h" | grep -oE 'in vault: [0-9]+' | grep -oE '[0-9]+')"
}
missing_items() { # output -> the listed missing items (lines after the MISSING banner)
    printf '%s\n' "$1" | tail -n +3 | sed '/^[[:space:]]*$/d'
}

[ -f "$MAIN" ] || { echo "FAIL: scanner not found at $MAIN"; exit 1; }

# --- Case 1: HD-244 regression proof (informational mode) ------------------
out="$(bash "$MAIN" --root "$FIXTURE" --fake-vault "$FIXTURE/vault-gap.txt")"
rc=$?
items="$(missing_items "$out")"
counts="$(header_counts "$out")"
expect_eq "case1 gap+informational exits 0" "$rc" "0"
expect_eq "case1 exactly one missing item" "$(printf '%s\n' "$items" | grep -c .)" "1"
expect_contains "case1 lists metabase-forgejo_ro (registry-key-only ref)" "$items" "metabase-forgejo_ro"
expect_eq "case1 enabled services = 2 (disabled entry filtered)" "$(echo "$counts" | awk '{print $1}')" "2"
expect_eq "case1 needed set = 5 (no dupes, no extras)" "$(echo "$counts" | awk '{print $2}')" "5"

# --- Case 2: no-false-positive on a complete vault --------------------------
out="$(bash "$MAIN" --root "$FIXTURE" --fake-vault "$FIXTURE/vault-complete.txt")"
rc=$?
items="$(missing_items "$out")"
expect_eq "case2 complete-vault exits 0" "$rc" "0"
expect_eq "case2 zero missing items" "$(printf '%s\n' "$items" | grep -c .)" "0"
expect_absent "case2 glue-seeded demo_oidc excluded" "$(missing_items "$out")" "demo_oidc"
expect_absent "case2 whole output never mentions demo_oidc" "$out" "demo_oidc"
expect_absent "case2 whole output never mentions disabled_should_never_appear" "$out" "disabled_should_never_appear"

# --- Case 3: --strict fails when something is missing ------------------------
out="$(bash "$MAIN" --root "$FIXTURE" --fake-vault "$FIXTURE/vault-gap.txt" --strict)"
rc=$?
if [ "$rc" -ne 0 ]; then ok "case3 gap+strict exits non-zero ($rc)"; else bad "case3 gap+strict exited 0"; fi
expect_contains "case3 still lists metabase-forgejo_ro in strict mode" "$(missing_items "$out")" "metabase-forgejo_ro"

# --- Case 4: --strict passes on a complete vault ------------------------------
bash "$MAIN" --root "$FIXTURE" --fake-vault "$FIXTURE/vault-complete.txt" --strict >/dev/null
rc=$?
expect_eq "case4 complete+strict exits 0" "$rc" "0"

# --- Summary ------------------------------------------------------------------
echo "check-vault-items self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
