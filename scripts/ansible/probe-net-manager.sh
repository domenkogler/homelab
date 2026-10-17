#!/usr/bin/env bash
# =====================================================================
# probe-net-manager.sh — print, per host, WHICH network config-manager actually
#   owns the uplink. Read-only, no converge. HD-487.
#
# WHY THIS EXISTS: the repo's stated model (network-rejected.md, 2026-08-16) is
# "systemd-networkd is the config-manager", with the Pi as the NM exception. A
# read-only sweep on 2026-10-08 found that true on exactly two of five hosts, and
# the failure mode is not "a host differs" but "a unit can be rendered, enabled
# and inert at the same time": oldsrv carries three /etc/systemd/network files
# that a DISABLED networkd never reads while NetworkManager holds the address.
# Editing the netd unit there changes nothing on the wire and the converge still
# prints green — a silent no-op, the same class as a duplicate YAML key (HD-1098)
# or a profile that restates a global (HD-494).
#
# The rule this tool enforces: ASK THE BOX, never the filename. `is-active` is not
# "owns the route", so the probe prints BOTH and derives the verdict from the
# interface the DEFAULT ROUTE rides — the only field that shows what carries traffic.
# Three states are legal and one of them is not a config-manager: classic ifupdown owns the uplink on
# a Debian box that has NetworkManager installed and idle and systemd-networkd disabled, and it
# proves it in /run/network/ifstate. The repo's per-host declaration lives in host_vars
# (network_manager / network_manager_target); scripts/gate/check_net_manager.py keeps the two agreed.
#
# USAGE:  scripts/ansible/probe-net-manager.sh                # every seat-reachable host
#         scripts/ansible/probe-net-manager.sh oldsrv nas     # a subset
# Exit: 0 always for a sweep — a verdict of BOTH / NONE is a FINDING, not a script failure;
#       refusing the edit it argues against is the caller's job. `--self-test` exits 1 when the
#       verdict function stops separating the states it is supposed to name.
# =====================================================================
set -uo pipefail

# The verdict, from one measurement: who owns the interface the DEFAULT ROUTE rides. Its own
# function, so `--self-test` can breed it with fabricated measurements — a verdict nobody can force
# into a wrong shape is a verdict that quietly stopped meaning anything.
#   nd=systemd-networkd state  nm=NetworkManager state  st=NM state OF the route interface  fw=ifupdown
#   owns the route interface (proved by /run/network/ifstate, not inferred from the managers)
verdict_of() {
  local nd="$1" nm="$2" st="$3" fw="${4:-no}"
  # ifupdown wins the tie: its state file proves the interface is up under its own hands, while a
  # manager that owns nothing is only RUNNING. `is-active` alone never separates those two.
  if [ "$fw" = yes ]; then printf "ifupdown"; return; fi
  if [ "$nd" = active ] && [ "$nm" = active ]; then printf "BOTH"; return; fi
  if [ "$nd" = active ]; then printf "networkd"; return; fi
  if [ "$nm" = active ]; then
    case "$st" in
      *externally*) printf "NM-external" ;;
      unmanaged|"") printf "NONE?!" ;;
      connected*)   printf "NetworkManager" ;;
      *)            printf 'NM:%s' "$st" ;;
    esac
    return
  fi
  printf "NONE"
}

# The states this tool must be able to name. scripts/gate/check_net_manager.py keeps this list and the
# host_vars vocabulary (network_manager) from drifting apart.
VERDICT_STATES=(NetworkManager networkd ifupdown)

self_test() {
  local fails=0
  # shape                      nd       nm       st          fw   expected verdict
  local cases=(
    "inactive|active|connected|no|NetworkManager"   # the seat: NM holds the route, networkd disabled
    "inactive|active|unmanaged|yes|ifupdown"        # NM installed and running, the uplink is not its
    "active|inactive|unmanaged|yes|ifupdown"        # networkd running and configuring nothing
    "active|active|connected|no|BOTH"               # two managers, one box
    "active|inactive|n/a|no|networkd"               # the classic netd box
    "inactive|inactive||no|NONE"                    # nothing at all claims it
    "inactive|active|unmanaged|no|NONE?!"           # a manager runs, owns nothing, ifupdown says no
  )
  local row nd nm st fw want got
  for row in "${cases[@]}"; do
    IFS='|' read -r nd nm st fw want <<<"$row"
    got=$(verdict_of "$nd" "$nm" "$st" "$fw")
    if [ "$got" = "$want" ]; then
      printf 'caught: %-8s %-8s %-12s fw=%-3s -> %s\n' "$nd" "$nm" "$st" "$fw" "$got"
    else
      printf 'NOT CAUGHT: %s/%s/%s/%s -> %s, expected %s\n' "$nd" "$nm" "$st" "$fw" "$got" "$want"
      fails=$((fails + 1))
    fi
  done
  # The tie-break IS the rule: ifupdown must beat a running networkd, or the third state disappears
  # into a verdict that says the opposite about the same box.
  if [ "$(verdict_of active inactive unmanaged yes)" != ifupdown ]; then
    echo "NOT CAUGHT: a running networkd outvoted the ifupdown proof"; fails=$((fails + 1))
  else
    echo "caught: the ifupdown proof beats a running networkd"
  fi
  local s found
  for s in "${VERDICT_STATES[@]}"; do
    found=no
    for row in "${cases[@]}"; do
      case "$row" in *"|$s") found=yes ;; esac
    done
    if [ "$found" = no ]; then echo "NOT CAUGHT: no case produces the state $s"; fails=$((fails + 1)); fi
  done
  if [ "$fails" -eq 0 ]; then
    echo "OK: probe-net-manager verdicts separate the states they name"
  else
    echo "FAIL: $fails verdict case(s) not caught"
  fi
  return "$fails"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

HOSTS=("$@")
[ ${#HOSTS[@]} -gt 0 ] || HOSTS=(oldsrv nas spark pi vps)

printf '%-8s %-10s %-9s %-9s %-12s %s\n' HOST networkd NetworkMgr route-if VERDICT detail
# The probe body, run verbatim on the target OR locally when the target IS this box
# (the seat hosts itself, and `ssh <self>` is not always allowed — oldsrv read as
# UNREACHABLE for exactly that reason on the first run, which is a wrong answer
# about the control node's own manager).
PROBE='
    nd=$(systemctl is-active systemd-networkd 2>/dev/null)
    nm=$(systemctl is-active NetworkManager 2>/dev/null)
    ri=$(ip route get 1.1.1.1 2>/dev/null | sed -n "s/.* dev \([a-zA-Z0-9._-]*\).*/\1/p" | head -1)
    nu=$(ls /etc/systemd/network/*.network 2>/dev/null | wc -l)
    nk=$(ls /etc/NetworkManager/system-connections/*.nmconnection 2>/dev/null | wc -l)
    # ifupdown keeps one `iface=iface` line per interface it brought up. That file listing the route
    # interface is the proof of the third state, whatever the two managers say about themselves.
    fw=no
    if [ -n "$ri" ]; then grep -q "^${ri}=${ri}\$" /run/network/ifstate 2>/dev/null && fw=yes; fi
    st=""
    if [ "$nm" = active ] && command -v nmcli >/dev/null 2>&1 && [ -n "$ri" ]; then
      st=$(nmcli -t -f DEVICE,STATE device 2>/dev/null | awk -F: -v d="$ri" "\$1==d{print \$2}")
    fi
    printf "%s|%s|%s|%s|%s" "$nd" "$nm" "$ri" "$nu" "$nk"
    printf "|%s|%s" "$st" "$fw"
'
for h in "${HOSTS[@]}"; do
me=$(hostname -s); mef=$(hostname -f 2>/dev/null | cut -d. -f1)
if [ "$h" = "$me" ] || [ "$h" = "$mef" ]; then
  out=$(timeout 25 bash -c "$PROBE" 2>/dev/null | tr -d "\r" | tail -1)
else
  # `-n` per CONVENTIONS §6: for the duration of an ssh without it, stdin is whatever the parent was
  # reading, so a caller that pipes this probe into `bash -s` or runs it from a read loop loses every
  # host after the first and still exits 0.
  out=$(timeout 25 ssh -n -o BatchMode=yes -o ConnectTimeout=8 "$h" "$PROBE" 2>/dev/null | tr -d "\r" | tail -1)
fi

  IFS='|' read -r nd nm ri nu nk st fw <<< "${out:-}"
  if [ -z "${nd:-}" ]; then
    printf '%-8s %s\n' "$h" "UNREACHABLE — this says nothing about its config-manager"
    continue
  fi

  # ONE question is answered: who owns the interface the default route rides. The rule lives in
  # verdict_of() above, where --self-test can breed it.
  v=$(verdict_of "$nd" "$nm" "$st" "${fw:-no}")

  dead=""
  if [ "$nd" != active ] && [ "${nu:-0}" -gt 0 ]; then
    dead="${nu} netd unit(s) on disk while networkd is INACTIVE = dead files"
  fi
  if [ "$nm" != active ] && [ "${nk:-0}" -gt 0 ]; then
    dead="${dead:+$dead; }${nk} NM keyfile(s) on disk while NM is INACTIVE = dead files"
  fi
  # A manager that runs WITHOUT owning the route is the two-managers shape. It is worth naming even
  # when the verdict is right: it can still rewrite the interface under the owner's feet, and
  # roles/network refuses exactly this at converge.
  also=""
  if [ "$v" != BOTH ] && [ "$v" != NONE ]; then
    if [ "$nd" = active ] && [ "$v" != networkd ]; then
      also="systemd-networkd ALSO runs"
    fi
    if [ "$nm" = active ] && [ "$v" != NetworkManager ] && [ "$v" != NM-external ]; then
      also="${also:+$also; }NetworkManager ALSO runs$( [ "$v" = ifupdown ] && printf ', route-if unmanaged to it' )"
    fi
  fi
  detail="route-if NM state: ${st:-n/a}${dead:+ · $dead}${also:+ · $also}"
  printf '%-8s %-10s %-9s %-9s %-12s %s\n' "$h" "$nd" "$nm" "${ri:-?}" "$v" "$detail"
done
cat <<'NOTE'

Read the VERDICT column, not the filenames. It answers one question — who owns the interface the
DEFAULT ROUTE rides — and there are three right answers plus two broken ones:
  NetworkManager / networkd   one of the two config-managers owns the uplink.
  ifupdown       NEITHER does: classic Debian /etc/network/interfaces (dhcpcd or dhclient as its
                client) carries the address, proved by the route interface being up in
                /run/network/ifstate. A box in this state is MANAGED, by a third path — the two
                managers can be installed and even running while configuring nothing.
  BOTH           two managers can rewrite the same box (HD-321's "`nmcli … modify` strips `dns=`
                 wherever NM is active" is that event seen from the other host).
  NONE / NONE?!  nothing claims the interface and ifupdown does not either — the address came from
                 somewhere IaC cannot see. Always a finding.
A "dead files" note means IaC renders config the running manager never reads: editing it is a green
converge that changes nothing. An "ALSO runs" note is the shape roles/network refuses at converge.
The per-host declaration this verdict is compared against lives in IaC/ansible/host_vars
(network_manager / network_manager_target); scripts/gate/check_net_manager.py keeps them agreed.
NOTE
