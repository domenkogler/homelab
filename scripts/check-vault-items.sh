#!/usr/bin/env bash
# =====================================================================
# check-vault-items.sh — diff the 1Password items REQUIRED by the enabled
# VPS service templates against what actually exists in the Homelab-ansible
# vault. Prints the items you must create (or seed via provision-vault.sh).
# OIDC client items that the secret-egress glue auto-seeds are excluded.
#
# Usage (WSL Debian runner): bash scripts/check-vault-items.sh
# =====================================================================
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HOME/.config/op/homelab-sa-token"
cd "$REPO"

# enabled service template_dirs (group_vars/vps.yml is the loop SSOT)
grep -E "^[[:space:]]*-[[:space:]]*\{ name:" IaC/ansible/group_vars/vps.yml |
    grep -v "enabled: false" |
    sed -E 's/.*name:[[:space:]]*([a-z0-9_-]+).*template_dir:[[:space:]]*([a-z0-9_-]+).*/\2/' > /tmp/enabled.txt

# items referenced by those templates
: > /tmp/needed.txt
while read -r t; do
    grep -rhoE "onepassword', '[a-z0-9_-]+'" "IaC/ansible/templates/docker_services/$t/" 2>/dev/null |
        sed "s/onepassword', '//; s/'//" >> /tmp/needed.txt
done < /tmp/enabled.txt
sort -u /tmp/needed.txt -o /tmp/needed.txt

# items present in the vault
op item list --vault Homelab-ansible --format json 2>/dev/null |
    python3 -c "import json,sys; [print(i['title']) for i in json.load(sys.stdin)]" | sort -u > /tmp/have.txt

# items the secret-egress glue auto-seeds (skip them)
grep -oE '"[a-z0-9_-]+:[a-z0-9_-]+"' \
    IaC/ansible/roles/docker_services/templates/authentik-secret-egress.sh.j2 |
    cut -d: -f2 | tr -d '"' | sort -u > /tmp/glue.txt

echo "== enabled services: $(wc -l < /tmp/enabled.txt) · needed items: $(wc -l < /tmp/needed.txt) · in vault: $(wc -l < /tmp/have.txt) =="
echo "== MISSING and NOT glue-seeded => create these =="
comm -23 /tmp/needed.txt <(sort -u /tmp/have.txt /tmp/glue.txt)
