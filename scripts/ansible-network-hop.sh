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

# --- 2. open the hop tunnel through Pi (mgmt-sourced), DYNAMIC local port ---
# Traffic egresses the Pi's eth0.99 (Mgmt) so available-from + INPUT lockdown
# both pass. The local bind port is DYNAMIC (OS-assigned): a FIXED port
# (18728/28728) caused a persistent cross-session failure — ssh would not bind
# while stale TIME_WAIT sockets from a previous run's API calls sat on that
# port (no listener, but ssh's bind check is strict), so the first tunnel of a
# later session died with 'Address already in use'. An OS-assigned ephemeral
# port is never re-used while sockets linger, and a lockfile serializes
# concurrent runs of the same target (no double tunnels).
LOCKDIR="${TMPDIR:-/tmp}/ansible-network-hop-locks"
mkdir -p "$LOCKDIR"
LOCKFILE="$LOCKDIR/$TARGET.lock"
exec 9>"$LOCKFILE"
flock 9          # wait for a concurrent same-target run, then proceed

# OS-assigned free local port (python: bind socket to port 0 → free ephemeral).
# A fixed port is what broke across sessions — ssh's listen bind is strict and
# stale TIME_WAIT sockets on the fixed port from a previous run's API calls
# made it fail 'Address already in use'. Dynamic ports are never re-bound while
# sockets linger; the tiny bind-close-bind race on 127.0.0.1 is acceptable and
# fails loudly (never silently persists).
LOOPBACK_PORT="$("$HOME/ansible-venv/bin/python3" - <<'PY'
import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))            # OS-assigned free port
print(s.getsockname()[1])
s.close()
PY
)"
SOCK="$LOCKDIR/$TARGET.ctl"       # ssh control socket (per target)
# ssh -f backgrounds the tunnel; ControlMaster + ControlPersist=no means the
# control master is a single deterministic process we can close with `-O exit`
# on EXIT — nothing detached survives to block a later session.
ssh -f -o ConnectTimeout=6 -o ExitOnForwardFailure=yes \
    -o ControlMaster=yes -o ControlPath="$SOCK" -o ControlPersist=no \
    -N -L "127.0.0.1:$LOOPBACK_PORT:$DEVICE_IP:8728" pi
for _ in 1 2 3 4 5; do
  if (exec 3<>/dev/tcp/127.0.0.1/"$LOOPBACK_PORT") 2>/dev/null; then exec 3>&- 3<&-; break; fi
  sleep 0.3
done

# --- 3. run the playbook via ansible-run.sh with hop overrides ---
# Must also force the venv interpreter (librouteros lives there; inventory.ini
# pins /usr/bin/python3 which lacks it — deployment-manual §1.5.3).
# Deterministic teardown: close the ssh control master (kills the forwarded
# connection) and release the lock — always, on any exit path.
trap 'ssh -S "$SOCK" -O exit pi 2>/dev/null || true; rm -f "$LOCKFILE" 2>/dev/null || true' EXIT
# Non-recursive converge_rsc default lives HERE (a playbook-level
# `{{ converge_rsc | default(...) }}` self-references and recurses infinitely).
# Inject -e converge_rsc=$DEFAULT_RSC only when the user didn't already pass one
# (e.g. `-e converge_rsc=crs328_converge.rsc` for the switch).
DEFAULT_RSC=rb4011_converge.rsc
for _arg in "$@"; do
    case "$_arg" in
        converge_rsc=*|-e"converge_rsc=*") DEFAULT_RSC="${_arg#-e}";;   # last -e converge_rsc= wins
    esac
done
bash "$REPO/scripts/ansible-run.sh" "$PLAYBOOK" \
    -e "routeros_api_host=127.0.0.1" \
    -e "routeros_api_port=$LOOPBACK_PORT" \
    -e "ansible_python_interpreter=$HOME/ansible-venv/bin/python3" \
    -e "converge_rsc=$DEFAULT_RSC" \
    "$@"