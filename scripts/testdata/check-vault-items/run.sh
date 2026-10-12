#!/usr/bin/env bash
# =====================================================================
# Self-test for scripts/gate/check-vault-items.sh (HD-244 + HD-245).
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
# FOUND by name, not by `../../`. This fixture used to sit two levels below scripts/ and said so
# with a literal relative climb; HD-1118 Stage 3 moved the scanner into scripts/gate/ and the climb
# then pointed at scripts/scripts/ — and a fixture whose scanner is missing FAILS, which is the only
# good outcome available. Same rule as everywhere else in scripts/: the tree is not this file's
# neighbourhood.
MAIN=""
for _d in "$HERE" "$(dirname "$HERE")" "$(dirname "$(dirname "$HERE")")"; do
  _c="$(find "$_d" -maxdepth 3 -name 'check-vault-items.sh' -not -path '*/testdata/*' 2>/dev/null | head -1)"
  [ -n "$_c" ] && { MAIN="$_c"; break; }
done
[ -n "$MAIN" ] || { echo "FAIL: cannot find check-vault-items.sh near $HERE (HD-1118: by name, never by ../../)"; exit 1; }
FIXTURE="$HERE/fixture"

pass=0
fail=0
ok()   { echo "PASS: $1"; pass=$((pass + 1)); }
bad()  { echo "FAIL: $1"; fail=$((fail + 1)); }

# The helpers are FORK-FREE on purpose. This leg costs 61 s solo on the Win11 git-bash seat and ~3 s on
# WSL Debian for the SAME fixture, because a fork there is 176 ms and does not parallelise (~5.5 forks/s
# for the whole machine) — and answering "is this line present?" with `printf | grep -Fxq` is TWO processes
# per assertion, ~100 assertions per run (measured 2026-10-10). The assertions and their meanings are
# unchanged; only the way they are evaluated is.
#
# THE HALF THAT WAS STILL MISSING, measured 2026-10-12 on the same seat: a bare COMMAND SUBSTITUTION is a
# fork too — `x=$(printf hi)` × 50 costs the same 3 s as `x=$(true)` × 50, ~60 ms a call, because bash
# forks for the substitution whether or not it execs anything. So the extractors below answer through an
# out-parameter (HD-1115's shape) instead of `printf '%s'` + `$( )`: on this tree that is ~25 forks per
# run, and CONVENTIONS §6 already says the substitution form translates bytes while `read` does not.
has_line() { # haystack needle -> true when a WHOLE line equals needle (exactly what grep -Fxq said)
    local h="${1%$'\n'}" n="$2" l
    while IFS= read -r l; do [ "$l" = "$n" ] && return 0; done <<< "$h"
    return 1
}
CR_N=0
count_rows() { # string -> CR_N = how many non-empty lines (`grep -c .` answered this)
    local h="${1%$'\n'}" l
    CR_N=0
    while IFS= read -r l; do [ -n "$l" ] && CR_N=$((CR_N + 1)); done <<< "$h"
}

expect_eq() { # desc actual expected
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got: '$2', want: '$3')"; fi
}
expect_contains() { # desc haystack needle
    if has_line "$2" "$3"; then ok "$1"; else bad "$1 (missing line '$3')"; fi
}
expect_absent() { # desc haystack needle
    if has_line "$2" "$3"; then bad "$1 (forbidden line '$3' present)"; else ok "$1"; fi
}

HC=""
header_counts() { # output -> HC = "enabled needed have" (out-parameter, see the note above)
    local h1="${1%%$'\n'*}" pat part num out=("" "" "") i=0
    for pat in 'enabled services: ' 'needed items: ' 'in vault: '; do
        part="${h1#*"$pat"}"
        if [ "$part" = "$h1" ]; then num=""; else num="${part%%[!0-9]*}"; fi   # digits to the first non-digit
        out[i]="$num"; i=$((i + 1))
    done
    HC="${out[0]} ${out[1]} ${out[2]}"   # plain assignment: `HC=$(printf …)` would be a fork again
}
MI=""
missing_items() { # output -> MI = the listed missing items (lines after the MISSING banner)
    local h="${1%$'\n'}" l n=0 out=""
    while IFS= read -r l; do
        n=$((n + 1)); [ "$n" -le 2 ] && continue          # was: tail -n +3
        [ -n "${l//[[:space:]]/}" ] && out+="$l"$'\n'     # was: sed '/^[[:space:]]*$/d'
    done <<< "$h"
    MI="${out%$'\n'}"
}

[ -f "$MAIN" ] || { echo "FAIL: scanner not found at $MAIN"; exit 1; }

# --- Case 1: HD-244 regression proof (informational mode) ------------------
out="$(bash "$MAIN" --root "$FIXTURE" --fake-vault "$FIXTURE/vault-gap.txt")"   # one launch per distinct (root, vault, mode) — see case 5
rc=$?
missing_items "$out"; items="$MI"
GAP_ITEMS="$MI"        # case 5 asserts on THIS run's list instead of launching the same command again
header_counts "$out"
expect_eq "case1 gap+informational exits 0" "$rc" "0"
count_rows "$items"; expect_eq "case1 exactly one missing item" "$CR_N" "1"
expect_contains "case1 lists metabase-forgejo_ro (registry-key-only ref)" "$items" "metabase-forgejo_ro"
read -r _c1 _c2 _c3 <<< "$HC"      # was: two `echo | awk` pipelines — 4 forks to split a header line
expect_eq "case1 enabled services = 2 (disabled entry filtered)" "$_c1" "2"
expect_eq "case1 needed set = 4 (owner-seedable only; demo_oidc + the 2 HD-247 spec items are GLUE-class)" "$_c2" "4"

# --- Case 2: no-false-positive on a complete vault --------------------------
out="$(bash "$MAIN" --root "$FIXTURE" --fake-vault "$FIXTURE/vault-complete.txt")"
rc=$?
missing_items "$out"; items="$MI"
expect_eq "case2 complete-vault exits 0" "$rc" "0"
count_rows "$items"; expect_eq "case2 zero missing items" "$CR_N" "0"
expect_absent "case2 glue-seeded demo_oidc excluded" "$items" "demo_oidc"
expect_absent "case2 whole output never mentions demo_oidc" "$out" "demo_oidc"
expect_absent "case2 whole output never mentions disabled_should_never_appear" "$out" "disabled_should_never_appear"

# --- Case 3: --strict fails when something is missing ------------------------
# A real launch even though case 1 ran the same tree: the MODE is the contract here (informational 0 vs
# strict non-zero), and an rc cannot be read out of another process's stdout.
out="$(bash "$MAIN" --root "$FIXTURE" --fake-vault "$FIXTURE/vault-gap.txt" --strict)"
rc=$?
if [ "$rc" -ne 0 ]; then ok "case3 gap+strict exits non-zero ($rc)"; else bad "case3 gap+strict exited 0"; fi
missing_items "$out"
expect_contains "case3 still lists metabase-forgejo_ro in strict mode" "$MI" "metabase-forgejo_ro"

# --- Case 4: --strict passes on a complete vault ------------------------------
bash "$MAIN" --root "$FIXTURE" --fake-vault "$FIXTURE/vault-complete.txt" --strict >/dev/null
rc=$?
expect_eq "case4 complete+strict exits 0" "$rc" "0"

# --- Case 5: HD-247 scoped-key class is glue-seeded => never MISSING ----------
# NO LAUNCH: this is case 1's tree, vault and mode byte for byte, so the scanner already answered it and
# the claim ("neither scoped item is MISSING") lives in that run's MISSING list. One launch per distinct
# contract, not per case — the deleted call was the 11th of 11 and cost ~4 s of this leg on this seat.
# Reusing a captured run is only honest if the haystack is the SAME string that was certified, so its
# population is re-asserted here: an empty or stale GAP_ITEMS must not be able to read as "nothing missing".
count_rows "$GAP_ITEMS"
expect_eq "case5 reuses case 1's captured run: one missing item is still the whole list" "$CR_N" "1"
expect_absent "case5 consumer-referenced scoped item not MISSING (lk_demo_chat_api)" "$GAP_ITEMS" "lk_demo_chat_api"
expect_absent "case5 spec-only scoped item not MISSING (lk_demo_rag_api)" "$GAP_ITEMS" "lk_demo_rag_api"

# --- Case 6: VISIBILITY PROOF — de-classify the block, both spec items surface ------
# Copies the fixture tree and RENAMES the scoped-keys block header (breaking the SSOT
# naming convention) AND removes the glue template: now NOTHING classifies the two
# items as glue, so they MUST appear as MISSING — proving the entry-record rule really
# captures the vault_item: scalars and that classification rides the block name.
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
cp -r "$FIXTURE/." "$TMPD/"
rm "$TMPD/IaC/ansible/roles/docker_services/templates/litellm-bootstrap-keys.sh.j2"
sed -i 's/^litellm_scoped_keys:/litellm_keys:/' "$TMPD/IaC/ansible/group_vars/vps.yml"
out="$(bash "$MAIN" --root "$TMPD" --fake-vault "$FIXTURE/vault-gap.txt")"
rc=$?
missing_items "$out"; items="$MI"
expect_eq "case6 no-glue exits 0 (informational)" "$rc" "0"
count_rows "$items"; expect_eq "case6 exactly three missing (ro + 2 scoped)" "$CR_N" "3"
expect_contains "case6 consumer-path visibility (lk_demo_chat_api listed)" "$items" "lk_demo_chat_api"
expect_contains "case6 entry-record visibility (lk_demo_rag_api listed)" "$items" "lk_demo_rag_api"
expect_contains "case6 regression guard intact (metabase-forgejo_ro still missing)" "$items" "metabase-forgejo_ro"

# --- Case 7: specs inside a top-level `*_scoped_keys:` list => GLUE, never MISSING --
# Mutate-copy approach: append a block to a COPY of the fixture tree. A correctly-named
# `bdemo_scoped_keys:` block must route bdemo_key_api to GLUE (never MISSING); the same
# records under a non-conventional name (`bdemo_keys:`) must stay NEEDED — proving the
# classification rides the SSOT list-name convention, not template literals or entry flags.
mk_copy() { # $1 = "ctrl" | "scoped" -> MD = copy dir (out-parameter: `$(mk_copy …)` is a fork)
    local d; d="$(mktemp -d)"
    cp -r "$FIXTURE/." "$d/"
    if [ "$1" = "scoped" ]; then
        printf '%s\n%s\n' 'bdemo_scoped_keys:' '  - { alias: bdemo, vault_item: bdemo_key_api, models: "", max_budget: "", budget_duration: "" }' \
            >> "$d/IaC/ansible/group_vars/vps.yml"
    else
        printf '%s\n%s\n' 'bdemo_keys:' '  - { alias: bdemo, vault_item: bdemo_key_api, models: "", max_budget: "", budget_duration: "" }' \
            >> "$d/IaC/ansible/group_vars/vps.yml"
    fi
    MD="$d"
}
MD=""; mk_copy ctrl; CTRL="$MD"; MD=""; mk_copy scoped; GATED="$MD"
out="$(bash "$MAIN" --root "$CTRL" --fake-vault "$FIXTURE/vault-gap.txt")"
missing_items "$out"
expect_contains "case7 control (non-scoped name): bdemo_key_api listed MISSING" "$MI" "bdemo_key_api"
out="$(bash "$MAIN" --root "$GATED" --fake-vault "$FIXTURE/vault-gap.txt")"; rc=$?
expect_eq "case7 scoped block: informational exit 0" "$rc" "0"
missing_items "$out"
expect_absent "case7 scoped block: bdemo_key_api routed to GLUE (never MISSING)" "$MI" "bdemo_key_api"
out="$(bash "$MAIN" --root "$GATED" --fake-vault "$FIXTURE/vault-gap.txt" --strict)"
missing_items "$out"; count_rows "$MI"
expect_eq "case7 scoped+strict: exactly 1 missing remains (metabase gap only)" "$CR_N" "1"
rm -rf "$CTRL" "$GATED"

# --- Case 8: host_vars `*_item:` registry class (HD-1093) ---------------------------
# roles/storage names each Samba credential through a VARIABLE — storage_samba_users[].vault_item
# in host_vars/nas.kogler.si.yml — so no template lookup contains the item name and only a
# host_vars scan can see the dependency (the HD-244 blind spot, one directory over).
# The control copy renames the key to `vaultitem:`, breaking the class convention: the item must
# then VANISH from MISSING, proving the rule matches the KEY CLASS and not the literal string.
mk_hostvars() { # $1 = key name -> MD = copy dir (out-parameter, see mk_copy)
    local d; d="$(mktemp -d)"
    cp -r "$FIXTURE/." "$d/"
    mkdir -p "$d/IaC/ansible/host_vars"
    printf '%s\n%s\n%s\n' 'storage_samba_users:' "  - { name: tester, $1: smb-shared_login }" '# vault_item: comment_only_item' \
        > "$d/IaC/ansible/host_vars/nas.example.test.yml"
    MD="$d"
}
MD=""; mk_hostvars vault_item; HV_CTRL="$MD"; MD=""; mk_hostvars vaultitem; HV_NOCLASS="$MD"
out="$(bash "$MAIN" --root "$HV_CTRL" --fake-vault "$FIXTURE/vault-gap.txt")"
missing_items "$out"
expect_contains "case8 host_vars vault_item: is a real dependency (smb-shared_login MISSING)" "$MI" "smb-shared_login"
out="$(bash "$MAIN" --root "$HV_NOCLASS" --fake-vault "$FIXTURE/vault-gap.txt")"
missing_items "$out"
expect_absent "case8 control: a non-class key name makes it invisible (rule is key-class, not text)" "$MI" "smb-shared_login"
expect_absent "case8 commented-out '# vault_item:' line never creates a dependency" "$MI" "comment_only_item"
rm -rf "$HV_CTRL" "$HV_NOCLASS"

# --- Summary ------------------------------------------------------------------
echo "check-vault-items self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
