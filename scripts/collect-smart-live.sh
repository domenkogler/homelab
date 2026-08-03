#!/bin/bash
#
# collect-smart-live.sh
# Run from a SystemRescue live ISO on the NAS host (HP MicroServer Gen8)
# with all HDDs connected (internal bays + SilverStone via miniSAS).
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/.../collect-smart-live.sh | bash
#   # or copy to USB, boot SystemRescue, run:
#   bash collect-smart-live.sh
#
# Output: /tmp/smart-report-YYYYMMDD-HHMMSS.txt
#         (copy to your machine with scp, curl, or USB)

set -euo pipefail

REPORT="/tmp/smart-report-$(date +%Y%m%d-%H%M%S).txt"
HOSTNAME="${HOSTNAME:-nas}"

# ── helpers ──────────────────────────────────────────────────────────────────
log() { printf '%s\n' "$*" | tee -a "$REPORT"; }
header() { log "══════════════════════════════════════════════════════════════════"; log "$1"; log; }

# ── 1. detect all disks ──────────────────────────────────────────────────────
header "DISK DETECTION — $(date)"
log "Host: $HOSTNAME"
log

# Method: smartctl --scan for all devices
DISKS=( $(smartctl --scan | grep -vi 'megaraid\|3ware\|cciss' | awk '{print $1}') )

if [ ${#DISKS[@]} -eq 0 ]; then
    log "ERROR: No disks detected via smartctl --scan!"
    log "Fallback: listing /dev/sd* /dev/nvme*"
    ls -la /dev/sd* /dev/nvme* 2>/dev/null | tee -a "$REPORT" || true
    exit 1
fi

log "Found ${#DISKS[@]} disk(s):"
for d in "${DISKS[@]}"; do
    cap="$(smartctl -i "$d" 2>/dev/null | grep -i 'Device Model\|Product\|Model Number' | head -1 | sed 's/.*:\s*//')"
    log "  $d  →  ${cap:-unknown}"
done
log

# ── 2. full SMART dump per disk ──────────────────────────────────────────────
for disk in "${DISKS[@]}"; do
    header "❖ $disk — smartctl -a"
    smartctl -a "$disk" 2>&1 >> "$REPORT"
    echo >> "$REPORT"
done

# ── 3. compact summary table ─────────────────────────────────────────────────
header "SUMMARY TABLE"
printf "%-8s | %-20s | %-5s | %-8s | %-5s | %-5s | %-5s | %-5s | %-6s | %-5s\n" \
    "DEVICE" "MODEL" "SIZE" "HOURS" "REALL" "PEND" "UNCOR" "SPINUP" "TEMP" "HEALTH" >> "$REPORT"
printf "%s\n" "─────────┼──────────────────────┼───────┼──────────┼───────┼───────┼───────┼───────┼────────┼───────" >> "$REPORT"

for disk in "${DISKS[@]}"; do
    raw="$(smartctl -a "$disk" 2>/dev/null)"

    model="$(echo "$raw" | grep -i 'Device Model\|Product\|Model Number' | head -1 | sed 's/.*:\s*//')"
    serial="$(echo "$raw" | grep -i 'Serial Number' | head -1 | sed 's/.*:\s*//')"
    size_raw="$(echo "$raw" | grep -i 'User Capacity' | sed 's/.*\[\(.*\)\]/\1/; s/.*bytes\s*\/\s*//')"
    size="${size_raw:-$(lsblk -dn -o SIZE "${disk%p*}" 2>/dev/null | head -1)}"

    hours="$(echo "$raw" | awk -F'[ =]+' '/Power_On_Hours/{print $10; exit}')"
    realloc="$(echo "$raw" | awk -F'[ =]+' '/Reallocated_Sector_Ct/{print $10; exit}')"
    pending="$(echo "$raw" | awk -F'[ =]+' '/Current_Pending_Sector/{print $10; exit}')"
    uncorrectable="$(echo "$raw" | awk -F'[ =]+' '/Offline_Uncorrectable/{print $10; exit}')"
    spinup="$(echo "$raw" | awk -F'[ =]+' '/Spin_Up_Time/{print $10; exit}')"
    temp="$(echo "$raw" | awk -F'[ =]+' '/Temperature_Celsius/{print $10; exit}')"

    # determine health
    health="OK"
    [ -n "$realloc" ]  && [ "$realloc"  -gt 0 ] 2>/dev/null && health="WARN(r=$realloc)"
    [ -n "$pending" ]  && [ "$pending"  -gt 0 ] 2>/dev/null && health="WARN(p=$pending)"
    [ -n "$uncorrectable" ] && [ "$uncorrectable" -gt 0 ] 2>/dev/null && health="FAIL(u=$uncorrectable)"

    # If health is numeric, trim leading zeros
    hours="${hours##0}"
    realloc="${realloc##0}";  [ -z "$realloc" ]  && realloc=0
    pending="${pending##0}";  [ -z "$pending" ]  && pending=0
    uncorrectable="${uncorrectable##0}"; [ -z "$uncorrectable" ] && uncorrectable=0
    spinup="${spinup##0}";    [ -z "$spinup" ]    && spinup="-"
    temp="${temp##0}";        [ -z "$temp" ]      && temp="-"
    [ -z "$hours" ] && hours="-"

    printf "%-8s | %-20s | %-5s | %-8s | %-5s | %-5s | %-5s | %-5s | %-6s | %-5s\n" \
        "${disk#/dev/}" "${model:0:20}" "${size:-?}" "$hours" "$realloc" "$pending" "$uncorrectable" "$spinup" "$temp" "$health" >> "$REPORT"
done

# ── 4. summary to stdout ─────────────────────────────────────────────────────
echo
echo "================================================================================"
echo "  COLLECTION COMPLETE"
echo "================================================================================"
echo "  Report: $REPORT"
echo "  Lines:  $(wc -l < "$REPORT")"
echo
echo "Options to get this file out:"
echo
echo "  1) Start HTTP server and download from another machine:"
echo "       python3 -m http.server 8000 --directory /tmp/"
echo "       # then browse to http://<HP_Gen8_IP>:8000/"
echo
echo "  2) Copy via scp (if you have SSH on this machine):"
echo "       scp $REPORT user@your-pc:~/"
echo
echo "  3) Save to a USB stick (mount first):"
echo "       mount /dev/sdX1 /mnt"
echo "       cp $REPORT /mnt/"
echo
echo "  4) curl to an upload endpoint:"
echo "       curl -F 'file=@$REPORT' https://your-upload-server/"
echo
echo "================================================================================"
