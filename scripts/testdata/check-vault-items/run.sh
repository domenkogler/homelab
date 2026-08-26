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
expect_eq "case1 needed set = 7 (5 base + 2 HD-247 spec items, no dupes)" "$(echo "$counts" | awk '{print $2}')" "7"

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

# --- Case 5: HD-247 scoped-key class is glue-seeded => never MISSING ----------
out="$(bash "$MAIN" --root "$FIXTURE" --fake-vault "$FIXTURE/vault-gap.txt")"
items="$(missing_items "$out")"
expect_absent "case5 consumer-referenced scoped item not MISSING (lk_demo_chat_api)" "$items" "lk_demo_chat_api"
expect_absent "case5 spec-only scoped item not MISSING (lk_demo_rag_api)" "$items" "lk_demo_rag_api"

# --- Case 6: VISIBILITY PROOF — without the glue file both items surface ------
# Copies the fixture tree WITHOUT the glue template: now the scanner has no glue-seed
# exclusion, so the same two items MUST appear as MISSING — proving the consumer-literal
# path AND the entry-record `vault_item:` rule actually parse them (not silently ignored).
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
cp -r "$FIXTURE/." "$TMPD/"
rm "$TMPD/IaC/ansible/roles/docker_services/templates/litellm-bootstrap-keys.sh.j2"
out="$(bash "$MAIN" --root "$TMPD" --fake-vault "$FIXTURE/vault-gap.txt")"
rc=$?
items="$(missing_items "$out")"
expect_eq "case6 no-glue exits 0 (informational)" "$rc" "0"
expect_eq "case6 exactly three missing (ro + 2 scoped)" "$(printf '%s
' "$items" | grep -c .)" "3"
expect_contains "case6 consumer-path visibility (lk_demo_chat_api listed)" "$items" "lk_demo_chat_api"
expect_contains "case6 entry-record visibility (lk_demo_rag_api listed)" "$items" "lk_demo_rag_api"
expect_contains "case6 regression guard intact (metabase-forgejo_ro still missing)" "$items" "metabase-forgejo_ro"

# --- Case 7: bootstrap_keys:true record => its vault_item is GLUE, never MISSING --
# Mutate-copy approach: append a one-line gated entry to a COPY of the fixture tree.
# Control (no flag) must list bdemo_key_api as MISSING; gated run must not — proving
# the routing is driven by the flag on the group_vars record, not by template literals
# (the real litellm glue template has NO literal names: Jinja spec.vault_item).
mk_copy() { # $1 = extra entry fields -> echoes copy dir
    local d; d="$(mktemp -d)"
    cp -r "$FIXTURE/." "$d/"
    printf '%s\n' "- { name: bdemo, image: bdemo:1, enabled: true, $1 vault_item: bdemo_key_api }" \
        >> "$d/IaC/ansible/group_vars/vps.yml"
    printf '%s\n' "$d"
}
CTRL="$(mk_copy '')"; GATED="$(mk_copy 'bootstrap_keys: true,')"
out="$(bash "$MAIN" --root "$CTRL" --fake-vault "$FIXTURE/vault-gap.txt")"
expect_contains "case7 control (no flag): bdemo_key_api listed MISSING" "$(missing_items "$out")" "bdemo_key_api"
out="$(bash "$MAIN" --root "$GATED" --fake-vault "$FIXTURE/vault-gap.txt")"
expect_eq "case7 gated: informational exit 0" "$?" "0"
expect_absent "case7 gated: bdemo_key_api routed to GLUE (never MISSING)" "$(missing_items "$out")" "bdemo_key_api"
out="$(bash "$MAIN" --root "$GATED" --fake-vault "$FIXTURE/vault-gap.txt" --strict)"
expect_eq "case7 gated+strict: exactly 1 missing remains (metabase gap only)" "$(missing_items "$out" | grep -c .)" "1"
rm -rf "$CTRL" "$GATED"

# --- Summary ------------------------------------------------------------------
echo "check-vault-items self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
