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
#
# USAGE:  scripts/probe-net-manager.sh                # every seat-reachable host
#         scripts/probe-net-manager.sh oldsrv nas     # a subset
# Exit: 0 always — a verdict of BOTH / NONE is a FINDING, not a script failure;
#       refusing the edit it argues against is the caller's job.
# =====================================================================
set -uo pipefail

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
    st=""
    if [ "$nm" = active ] && command -v nmcli >/dev/null 2>&1 && [ -n "$ri" ]; then
      st=$(nmcli -t -f DEVICE,STATE device 2>/dev/null | awk -F: -v d="$ri" "\$1==d{print \$2}")
    fi
    printf "%s|%s|%s|%s|%s" "$nd" "$nm" "$ri" "$nu" "$nk"
    printf "|%s" "$st"
'
for h in "${HOSTS[@]}"; do
me=$(hostname -s); mef=$(hostname -f 2>/dev/null | cut -d. -f1)
if [ "$h" = "$me" ] || [ "$h" = "$mef" ]; then
  out=$(timeout 25 bash -c "$PROBE" 2>/dev/null | tr -d "\r" | tail -1)
else
  out=$(timeout 25 ssh -o BatchMode=yes -o ConnectTimeout=8 "$h" "$PROBE" 2>/dev/null | tr -d "\r" | tail -1)
fi

  IFS='|' read -r nd nm ri nu nk st <<< "${out:-}"
  if [ -z "${nd:-}" ]; then
    printf '%-8s %s\n' "$h" "UNREACHABLE — this says nothing about its config-manager"
    continue
  fi

  if [ "$nd" = active ] && [ "$nm" = active ]; then v="BOTH"
  elif [ "$nd" = active ]; then v="networkd"
  elif [ "$nm" = active ]; then
    case "$st" in
      *externally*) v="NM-external" ;;
      unmanaged|"") v="NONE?!" ;;
      connected*)   v="NetworkManager" ;;
      *)            v="NM:$st" ;;
    esac
  else v="NONE"; fi

  dead=""
  if [ "$nd" != active ] && [ "${nu:-0}" -gt 0 ]; then
    dead="${nu} netd unit(s) on disk while networkd is INACTIVE = dead files"
  fi
  if [ "$nm" != active ] && [ "${nk:-0}" -gt 0 ]; then
    dead="${dead:+$dead; }${nk} NM keyfile(s) on disk while NM is INACTIVE = dead files"
  fi
  detail="route-if NM state: ${st:-n/a}${dead:+ · $dead}"
  printf '%-8s %-10s %-9s %-9s %-12s %s\n' "$h" "$nd" "$nm" "${ri:-?}" "$v" "$detail"
done
cat <<'NOTE'

Read the VERDICT column, not the filenames: BOTH means two managers can rewrite the
same box (HD-321's "`nmcli … modify` strips `dns=` wherever NM is active" is that event
seen from the other host), and NONE?! means the address came from neither — HD-487's
open question, always. A "dead files" note means IaC renders config the running manager
never reads: editing it is a green converge that changes nothing.
NOTE
