#!/usr/bin/env bash
# =====================================================================
# probe-snmp-presence.sh — fail LOUDLY when a metric the SNMP module asks
#   for is not arriving in VictoriaMetrics. Read-only: GET /api/v1/query
#   only, never a device, never a config change.
#
# WHY THIS EXISTS: an OID the device does not answer does not make a scrape
# fail. snmp_exporter walks, gets nothing back for that subtree, and emits
# the rest — so the metric is simply absent and every panel on it is blank
# forever. That is green-by-absence, and the walk is the only place it can
# be caught. So the required set is NOT a hand-kept list here: it is read
# out of snmp.yml.j2, which means widening the module automatically widens
# the test, and a metric that silently stops landing (device upgraded, OID
# moved, community revoked) fails this script instead of emptying a panel.
#
# USAGE (from a seat that can reach the Victoria backend):
#   VM_URL=http://10.255.40.2:8428 scripts/ansible/probe-snmp-presence.sh
#   VM_URL=… scripts/ansible/probe-snmp-presence.sh --window 30m
#   scripts/ansible/probe-snmp-presence.sh --list      # offline: the derived set only
#   A window narrower than the default 15m can report a metric ABSENT right after a collector
#   restart: the new series have not had a scrape cycle plus an insert yet (measured — a
#   --window 5m run minutes after an Alloy restart showed the switch's new series in and the
#   router's not). Widen --window; do not "fix" the finding.
#
# Env:  VM_URL   REQUIRED, no default on purpose (same rule as
#                scripts/bench/spark/vm-window.sh): the endpoint is the IaC
#                `victoria_backend_host` on :8428 and a guessed default would
#                silently query the wrong store and report everything missing.
#       creds    1Password `Homelab-ansible/victoria-metrics_api` via `op`, else
#                VM_USERNAME + VM_PASSWORD. Written to a 0600 curl config and
#                unlinked on exit — never argv, never printed.
#       SNMP_MODULE  path to the module config, default
#                IaC/ansible/roles/monitoring/templates/snmp.yml.j2
# Exit: 0 every metric present on every device · 1 something absent · 2 could not run
# =====================================================================
set -uo pipefail

WINDOW="15m"; LIST_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --window) WINDOW="${2:?--window needs a duration, e.g. 15m}"; shift ;;
    --list)   LIST_ONLY=1 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
  shift
done

# HD-1118 Stage 1: the repo root is FOUND by scripts/lib/repo-root.sh, never assumed
_hl_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_hl_d/lib/repo-root.sh" ] && [ "$_hl_d" != / ]; do _hl_d="$(dirname "$_hl_d")"; done
. "$_hl_d/lib/repo-root.sh"   # sets REPO
MODULE=${SNMP_MODULE:-$REPO/IaC/ansible/roles/monitoring/templates/snmp.yml.j2}
[ -f "$MODULE" ] || { echo "ERROR: no module config at $MODULE (set SNMP_MODULE)" >&2; exit 2; }

# The metric set: every `- name:` under `metrics:`. Anchors/aliases carry the
# shared lookups, not metrics, so a name line is exactly one emitted metric.
METRICS=$(awk '/^    metrics:/{f=1;next} f&&/^      - name: /{print $3}' "$MODULE")
[ -n "$METRICS" ] || { echo "ERROR: parsed no metrics out of $MODULE — the module shape changed, fix this probe" >&2; exit 2; }
DEVICES="router switch"   # the two MikroTiks Alloy scrapes (alloy.river.j2, oldsrv only)

if [ "$LIST_ONLY" = "1" ]; then
  echo "# required set, derived from ${MODULE#$REPO/} — one per device, plus up{} per device:"
  for m in $METRICS; do for d in $DEVICES; do echo "  $m  instance=$d"; done; done
  exit 0
fi

[ -n "${VM_URL:-}" ] || { echo "ERROR: VM_URL unset. Point it at the Victoria endpoint = IaC victoria_backend_host:8428" >&2; exit 2; }
if [ -z "${VM_USERNAME:-}" ] || [ -z "${VM_PASSWORD:-}" ]; then
  command -v op >/dev/null 2>&1 || { echo "ERROR: no op CLI and VM_USERNAME/VM_PASSWORD unset" >&2; exit 2; }
  VM_USERNAME=$(op read "op://Homelab-ansible/victoria-metrics_api/username" 2>/dev/null || true)
  VM_PASSWORD=$(op read "op://Homelab-ansible/victoria-metrics_api/password" 2>/dev/null || true)
fi
[ -n "${VM_USERNAME:-}" ] && [ -n "${VM_PASSWORD:-}" ] || { echo "ERROR: victoria-metrics_api credentials unreadable" >&2; exit 2; }
case "$VM_PASSWORD" in *\"*) echo "ERROR: credential contains a double quote; this script cannot embed it safely" >&2; exit 2;; esac

CFG=$(mktemp); chmod 0600 "$CFG"; trap 'rm -f "$CFG"' EXIT
printf 'user = "%s:%s"\n' "$VM_USERNAME" "$VM_PASSWORD" > "$CFG"
echo ">>> creds: user=${#VM_USERNAME} chars, secret=${#VM_PASSWORD} chars (values not printed)"
echo ">>> presence window: last $WINDOW, job=alloy-snmp, devices: $DEVICES"

ask(){ curl -sf -K "$CFG" -G --data-urlencode "query=$1" "${VM_URL%/}/api/v1/query" \
       | python3 -c 'import sys,json
try:
    r = json.load(sys.stdin).get("data", {}).get("result", [])
except Exception:
    print("QUERY-FAIL"); raise SystemExit
print(r[0]["value"][1] if r else "EMPTY")'; }

FAIL=0
printf '%-26s %-8s %-8s %s\n' METRIC DEVICE SERIES VERDICT
for m in $METRICS; do
  for d in $DEVICES; do
    # count(max_over_time(…[w])) = how many distinct series carried a sample in
    # the window. EMPTY (no result) and 0 both mean: nothing arrived.
    n=$(ask "count(max_over_time(${m}{job=\"alloy-snmp\",instance=\"${d}\"}[${WINDOW}]))")
    case "$n" in
      ''|EMPTY|0|QUERY-FAIL) v="ABSENT"; FAIL=1 ;;
      *) v="present" ;;
    esac
    printf '%-26s %-8s %-8s %s\n' "$m" "$d" "${n:-EMPTY}" "$v"
  done
done

# The scrape itself must be up, or "absent" means "the collector is dead" and not "the OID is gone".
for d in $DEVICES; do
  u=$(ask "up{job=\"alloy-snmp\",instance=\"${d}\"}")
  printf '%-26s %-8s %-8s %s\n' "up" "$d" "$u" "$([ "$u" = "1" ] && echo present || echo "ABSENT — scrape not up")"
  [ "$u" = "1" ] || FAIL=1
done

if [ "$FAIL" = "1" ]; then
  echo ">>> FAILED — a metric the module asks for is not in VictoriaMetrics."
  echo "    If up{} is present and the metric is ABSENT on BOTH devices, the OID is not answered"
  echo "    by this firmware: remove it from the walk (do not 'fix' it with a default) and record"
  echo "    the finding in docs/observability.md §SNMP coverage."
  exit 1
fi
echo ">>> OK — every metric in the module is arriving on both MikroTiks."
