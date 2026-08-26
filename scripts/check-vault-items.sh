#!/usr/bin/env bash
# =====================================================================
# check-vault-items.sh - diff the 1Password items REQUIRED by the enabled
# service configuration against what actually exists in the Homelab-ansible
# vault. Prints the items you must create (or seed via provision-vault.sh).
# OIDC client items that the secret-egress glue auto-seeds are excluded.
#
# Usage (WSL Debian runner): bash scripts/check-vault-items.sh
#
# Flags (HD-244/245):
#   --root DIR       scan DIR instead of this repo (self-test fixture tree)
#   --fake-vault F   use F (one item title per line) as the HAVE-list instead of
#                    querying 1Password - skips the op CLI / SA-token requirement
#   --strict         exit 1 when the MISSING-and-not-glue list is non-empty
#                    (default stays informational: always exit 0)
# Self-test fixture + runner: scripts/testdata/check-vault-items/ - wired into
# validate-all.sh; standalone: bash scripts/testdata/check-vault-items/run.sh
# =====================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$REPO"
FAKE_VAULT=""
STRICT=0

usage() {
    cat <<'EOF'
Usage: bash scripts/check-vault-items.sh [--root DIR] [--fake-vault FILE] [--strict]

  --root DIR         operate on DIR as the repo root (default: this repo); used by the
                     self-test fixture in scripts/testdata/check-vault-items/fixture/
  --fake-vault FILE  treat FILE (one item title per line) as the vault contents instead
                     of querying 1Password; skips the SA-token source + op CLI call
  --strict           exit 1 if any required item is MISSING and not glue-seeded
                     (default: informational listing, always exit 0)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --root)       ROOT="${2:?--root needs a directory argument}"; shift 2 ;;
        --fake-vault) FAKE_VAULT="${2:?--fake-vault needs a file argument}"; shift 2 ;;
        --strict)     STRICT=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            echo "check-vault-items.sh: unknown flag: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ ! -d "$ROOT/IaC/ansible/group_vars" ]; then
    echo "check-vault-items.sh: --root '$ROOT' does not look like a repo root (missing IaC/ansible/group_vars)" >&2
    exit 2
fi
if [ -n "$FAKE_VAULT" ] && [ ! -f "$FAKE_VAULT" ]; then
    echo "check-vault-items.sh: --fake-vault '$FAKE_VAULT' not found" >&2
    exit 2
fi

cd "$ROOT"
GV="IaC/ansible/group_vars"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# enabled service template_dirs (group_vars/vps.yml is the loop SSOT)
grep -E "^[[:space:]]*-[[:space:]]*\{ name:" "$GV/vps.yml" |
    grep -v "enabled: false" |
    sed -E 's/.*name:[[:space:]]*([a-z0-9_-]+).*template_dir:[[:space:]]*([a-z0-9_-]+).*/\2/' > "$TMP/enabled.txt"

# items referenced by those templates
: > "$TMP/needed.txt"
while read -r t; do
    [ -n "$t" ] || continue
    grep -rhoE "onepassword', '[a-z0-9_-]+'" "IaC/ansible/templates/docker_services/$t/" 2>/dev/null |
        sed "s/onepassword', '//; s/'//" >> "$TMP/needed.txt"
done < "$TMP/enabled.txt"

# Blind-spot fix (Wave-2 triage 2026-08-22): item refs OUTSIDE per-service template dirs.
# Lesson from the kopia-server miss: lookups can land in files this script never scanned
# (shared top-level templates like homepage_services.yaml.j2 -> ha-failover_api; the VPS
# host context in group_vars/vps.yml + all/ -> cloudflare_api ACME env). Scan those too.
# Non-VPS role items (router/nut/Pi hosts) stay deliberately out of scope.
grep -rhoE "onepassword', '[a-z0-9_-]+'" \
    IaC/ansible/templates/*.j2 \
    "$GV/vps.yml" "$GV/all/" 2>/dev/null |
    sed "s/onepassword', '//; s/'//" >> "$TMP/needed.txt"

# HD-244 (2026-08-25): registry-key class - scalar `*_item:` values (db_item,
# db_ro_item, future classes) inside ENABLED service entries of vps.yml AND
# home_servers.yml. deploy-service.yml consumes these DYNAMICALLY via
# `svc.<key>` lookups, so a literal-lookup grep can never see them (live gap
# found while seeding metabase-forgejo_ro for HD-241/242). Parse whole ENTRY
# RECORDS: a record starts at a `- {` line and ends at the first line whose
# comment-stripped content ends with `}` - continuation lines carry the db_*
# keys, so line-based grepping cannot attribute them to the right entry.
# Records containing a literal `enabled: false` are skipped (same convention as
# the template-dir filter above, which relies on the flag sitting on the first
# line); a templated `enabled: "{{ }}"` value counts as enabled. The closing-
# brace-at-end-of-line rule is what lets such records terminate correctly even
# though their values contain `}}`.
for f in "$GV/vps.yml" "$GV/home_servers.yml"; do
    [ -f "$f" ] || continue
    awk '
        function flush(   s, v, g) {
            if (!inrec) return
            if (buf !~ /enabled:[[:space:]]*false/) {
                # HD-247 glue class: spec records living inside a top-level
                # `*_scoped_keys:` list are MINTED by the bootstrap-keys glue at
                # converge time - emit them G|-prefixed so they land in the GLUE
                # set, not NEEDED. Service-entry registry keys (db_item/db_ro_item)
                # are owner-seeded catalog items and stay NEEDED - the flag lives on
                # the BLOCK name, never on individual entry records.
                g = inscoped ? "G|" : ""
                s = buf
                while (match(s, /[a-z0-9_]+_item:[[:space:]]*[a-z0-9_-]+/)) {
                    v = substr(s, RSTART, RLENGTH)
                    sub(/.*:[[:space:]]*/, "", v)
                    print g v
                    s = substr(s, RSTART + RLENGTH)
                }
            }
            inrec = 0; buf = ""
        }
        {
            if ($0 ~ /^[A-Za-z0-9_]+_scoped_keys:/) { inscoped = 1; next }
            if (inscoped && $0 !~ /^[ \t]/ && $0 !~ /^[ \t]*#/ && $0 !~ /^[ \t]*$/) inscoped = 0
            if (!inrec) {
                if ($0 !~ /^[[:space:]]*-[[:space:]]*\{/) next
                inrec = 1; buf = ""
            }
            line = $0
            sub(/[[:space:]]+#.*$/, "", line)
            buf = buf (buf == "" ? "" : "\n") line
            if (line ~ /\}[[:space:]]*$/) flush()
        }
        END { flush() }
    ' "$f" > "$TMP/rec_items.txt"
    grep -v '^G|' "$TMP/rec_items.txt" >> "$TMP/needed.txt"
    { grep '^G|' "$TMP/rec_items.txt" || true; } | sed 's/^G|//' | sort -u >> "$TMP/glue_entry.txt"
done

sort -u "$TMP/needed.txt" -o "$TMP/needed.txt"

# items present in the vault (--fake-vault swaps the query for a static list)
if [ -n "$FAKE_VAULT" ]; then
    sort -u "$FAKE_VAULT" > "$TMP/have.txt"
else
    # shellcheck disable=SC1091
    source "$HOME/.config/op/homelab-sa-token"
    op item list --vault Homelab-ansible --format json 2>/dev/null |
        python3 -c "import json,sys; [print(i['title']) for i in json.load(sys.stdin)]" | sort -u > "$TMP/have.txt"
fi

# items the deploy-time glues auto-create/auto-seed (skip them):
#   authentik-secret-egress.sh.j2  — OIDC client creds (HD-143); literal name pairs
#                                    in the template are greppable directly
#   litellm-bootstrap-keys.sh.j2   — LiteLLM scoped virtual keys (HD-247): item names
#                                    are Jinja-rendered (spec.vault_item), so NO literal
#                                    exists — instead, spec records inside a top-level
#                                    `*_scoped_keys:` list (the group_vars SSOT) route
#                                    into this GLUE set (entry-record rule above;
#                                    live-found gap 2026-08-26). db_item/db_ro_item on
#                                    service entries stay NEEDED (owner-seeded catalog).
grep -hoE '"[a-z0-9_-]+:[a-z0-9_-]+"' \
    IaC/ansible/roles/docker_services/templates/authentik-secret-egress.sh.j2 \
    IaC/ansible/roles/docker_services/templates/litellm-bootstrap-keys.sh.j2 2>/dev/null \
    | cut -d: -f2 | tr -d '"' > "$TMP/glue.txt"
# entry-record glue class (bootstrap_keys:true records) — names come from the
# group_vars SSOT, never from literals inside the (Jinja) glue template:
[ -f "$TMP/glue_entry.txt" ] && cat "$TMP/glue_entry.txt" >> "$TMP/glue.txt"
sort -u "$TMP/glue.txt" -o "$TMP/glue.txt"

# Glue-minted items are never owner-seedable: drop them from NEEDED entirely.
# They can enter via MULTIPLE capture paths (spec blocks above AND literal
# consumer-template lookups), so subtract once at the end, not per-path.
comm -23 "$TMP/needed.txt" "$TMP/glue.txt" > "$TMP/needed_owner.txt"
mv "$TMP/needed_owner.txt" "$TMP/needed.txt"

echo "== enabled services: $(wc -l < "$TMP/enabled.txt") | needed items: $(wc -l < "$TMP/needed.txt") | in vault: $(wc -l < "$TMP/have.txt") =="
echo "== MISSING and NOT glue-seeded => create these =="
comm -23 "$TMP/needed.txt" <(sort -u "$TMP/have.txt" "$TMP/glue.txt") | tee "$TMP/missing.txt"

if [ "$STRICT" = 1 ] && [ -s "$TMP/missing.txt" ]; then
    echo "== --strict: $(wc -l < "$TMP/missing.txt") missing item(s) => FAIL ==" >&2
    exit 1
fi

exit 0
