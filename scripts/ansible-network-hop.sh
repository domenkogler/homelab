#!/usr/bin/env bash
# =====================================================================
# ansible-network-hop.sh — run a RouterOS playbook (router.yml / switch.yml)
# against a MikroTik device through the Pi-99 management hop.
# ---------------------------------------------------------------------
# WHY (HD-285 maintenance window, 2026-09-02): the Ansible runner (WSL
# Debian laptop) sits on the Home VLAN (10) — its direct connection to the
# router/switch API loses at BOTH layers of the mgmt lockdown:
#   - forward: 'Default deny inter-VLAN' drops Home->Mgmt
#   - input/service: /ip service `available-from` (mgmt subnet) + the
#     INPUT mgmt-lockdown reject any non-mgmt source (live: 'Connection
#     reset by peer' when running router.yml directly).
# The Pi (dual-home: Home untagged + eth0.99 tagged Mgmt) is the ONLY real
# mgmt client (network-vlans.md); a local SSH port-forward through it makes
# the API traffic originate from the Mgmt subnet — passing both gates with
# ZERO firewall surface (no Home->Mgmt hole; decision network-vlans.md kept).
#
# This wrapper:
#   1. resolves the device's VLAN-99 mgmt IP from the SSOT (network_static_hosts
#      in group_vars/all.yml — the SAME derivation as group_vars/network.yml,
#      so no IP literals live here),
#   2. opens an SSH local forward through `pi` to the device RouterOS API
#      (fixes the loopback bind to a stable local port),
#   3. execs the playbook via scripts/ansible-run.sh (the venv wrapper) with
#      -e routeros_api_host/port pointed at the loopback tunnel,
#   4. tears the tunnel down on exit (trap).
#
# The host/port mapping is EXTRA -e vars; the playbook/role still read
# routeros_expected_identity (HD-161 assert) from SSOT group_vars — the
# identity assert refuses a wrong-target. 9P gate N/A on WSL ext4 primary.
#
# Usage:
#   bash scripts/ansible-network-hop.sh <router|switch> <playbook> [extra -e args]
#     e.g. bash scripts/ansible-network-hop.sh router playbooks/router.yml
#          bash scripts/ansible-network-hop.sh switch playbooks/switch.yml --check --diff
#
# Requires: the same env as ansible-run.sh (venv + 1Password SA token) + the
#   `pi` SSH alias (Home) in ~/.ssh/config (it is — HD-310/311).
# =====================================================================
set -euo pipefail

TARGET="${1:?usage: ansible-network-hop.sh <router|switch> <playbook> [--check --diff]}"
PLAYBOOK="${2:?usage: ansible-network-hop.sh <router|switch> <playbook> [--check --diff]}"
shift 2

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$TARGET" in
    router) LOOPBACK_PORT=18728;;
    switch) LOOPBACK_PORT=28728;;
    *) echo "FAIL: target must be 'router' or 'switch' (got '$TARGET')" >&2; exit 2;;
esac

# --- 1. resolve the device mgmt IP from SSOT (team_vars/network_static_hosts) ---
# The router/switch VLAN-99 management IP, derived exactly like group_vars/
# network.yml does (selectattr name==inventory_hostname_short, vlan==99, first).
# Uses an inventory-visible ad-hoc on localhost (the runner) with connection=local.
DEVICE_IP="$(cd "$REPO/IaC/ansible" && \
    ANSIBLE_LOCALHOST_WARNING=0 "$HOME/ansible-venv/bin/python3" - "$TARGET" <<'PY'
import sys, yaml
# SSOT: group_vars/all/main.yml -> network_static_hosts — same derivation as
# group_vars/network.yml (name == inventory_hostname_short, vlan == 99). The IPs
# are raw literals in SSOT (no Jinja), so plain YAML parse suffices.
target = sys.argv[1]
with open('group_vars/all/main.yml') as f:
    all_ = yaml.safe_load(f)
hosts = all_.get('network_static_hosts', [])
row = next((h for h in hosts if h.get('name') == target and h.get('vlan') == 99), None)
if row:
    print(row['ip'])
PY
)"
if [ -z "$DEVICE_IP" ]; then
    echo "FAIL: could not resolve VLAN-99 mgmt IP for '$TARGET' from SSOT (network_static_hosts)" >&2
    exit 2
fi

# --- 2. open the hop tunnel through Pi (mgmt-sourced) ---
# Stable local bind port so multiple tunnels can coexist; traffic egresses the
# Pi's eth0.99 (Mgmt) so available-from + INPUT lockdown both pass.
ssh -o ConnectTimeout=6 -o ExitOnForwardFailure=yes -N -f \
    -L "$LOOPBACK_PORT:$DEVICE_IP:8728" pi
for _ in 1 2 3 4 5; do
  if (exec 3<>/dev/tcp/127.0.0.1/"$LOOPBACK_PORT") 2>/dev/null; then exec 3>&- 3<&-; break; fi
  sleep 0.3
done

# --- 3. run the playbook via ansible-run.sh with hop overrides ---
# Must also force the venv interpreter (librouteros lives there; inventory.ini
# pins /usr/bin/python3 which lacks it — deployment-manual §1.5.3).
trap 'pkill -f "ssh.*-$LOOPBACK_PORT:.*pi" 2>/dev/null || true' EXIT
bash "$REPO/scripts/ansible-run.sh" "$PLAYBOOK" \
    -e "routeros_api_host=127.0.0.1" \
    -e "routeros_api_port=$LOOPBACK_PORT" \
    -e "ansible_python_interpreter=$HOME/ansible-venv/bin/python3" \
    "$@"