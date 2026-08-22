#!/bin/sh
#
# collect-disk-facts.sh — Phase 1a read-only disk-facts collector (kogler homelab)
#
# Run from a Debian installer/live USB on a host BEFORE its preseed reinstall
# (oldsrv today, nas equally usable). Collects everything the Phase 1a
# facts-gathering task needs, strictly READ-ONLY toward the disks:
#
#   - full /dev/disk/by-id/ listing + reverse map by-id <-> /dev node
#     (headline item: real Linux nvme-eui.* by-ids for HD-128 /
#      storage_nvme_data_by_id — the doc values were derived from Windows
#      EUI64 and are unverified, see docs/hardware-oldsrv.md)
#   - per disk: model, serial, size, transport, rotational
#   - SMART key attributes + full `smartctl -x` dump per disk when
#     smartmontools is present (refreshes the hour counts recorded against
#     unstable sdX names in docs/hardware-nas.md; pre-flight identity check
#     before the Pool-Creation Runbook's wipefs step)
#   - lsblk / blkid / nvme list context (existing filesystem signatures =
#     pre-wipe awareness)
#
# Output: disk-facts-<label>-<YYYYmmdd-HHMMSS>.txt written to the ROOT OF THE
# WRITABLE USB STICK (Ventoy/exFAT or FAT32 partition). Destination search:
#   1. already-mounted writable partition on a REMOVABLE disk
#      (live session / Ventoy auto-mount)
#   2. unmounted writable partition on the BOOT medium's disk -> mounted rw
#   3. any other unmounted writable partition on a removable disk -> mounted rw
#   4. fallback: CWD, then /tmp — LOUDLY reported as volatile (RAM-backed on
#      the installer; copy the file off before reboot!)
# A plain dd'd ISO stick (read-only ISO9660) can never pass tests 1-3 — you
# get fallback 4 plus a hint. Use Ventoy or a second FAT32 stick instead.
#
# Usage (as root, or via sudo in a live session; the d-i console is root):
#   sh collect-disk-facts.sh [label]        # label: oldsrv | nas (default: hostname)
#   sh collect-disk-facts.sh --help
#
# POSIX sh on purpose — runs in the debian-installer busybox console
# (Ctrl+Alt+F2), a Debian live session, and SystemRescue alike.
#
# Owning specs: deployment-tasks.md §Phase 1a · docs/hardware-oldsrv.md ·
#               docs/hardware-nas.md · todo.md HD-128/HD-207
# Sibling: scripts/collect-smart-live.sh (SystemRescue/NAS variant, /tmp output)

set -u

# ── CLI ───────────────────────────────────────────────────────────────────────
case "${1:-}" in
  -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

LABEL=${1:-}
[ -n "$LABEL" ] || LABEL=$(cat /etc/hostname 2>/dev/null || hostname 2>/dev/null || echo host)
LABEL=$(printf '%s' "$LABEL" | tr -c 'A-Za-z0-9._-' '_')

STAMP=$(date +%Y%m%d-%H%M%S)
REPORT_NAME="disk-facts-${LABEL}-${STAMP}.txt"
WORK=$(mktemp -d 2>/dev/null) || WORK="/tmp/collect-facts.$$"
mkdir -p "$WORK"
REPORT="$WORK/$REPORT_NAME"
TBL="$WORK/table.txt"
: > "$REPORT"
: > "$TBL"

CLEANUP=1   # cleared when the only surviving copy lives in $WORK
cleanup() { [ "$CLEANUP" = 1 ] && rm -rf "$WORK"; return 0; }
trap cleanup EXIT INT TERM

say() { printf '%s\n' "$*" >&2; }
sec() { printf '\n============================================================\n== %s\n============================================================\n' "$*" >> "$REPORT"; }
cap() { printf '\n$ %s\n' "$1" >> "$REPORT"; sh -c "$1" >> "$REPORT" 2>&1; }

# ── tool availability ─────────────────────────────────────────────────────────
have() { command -v "$1" >/dev/null 2>&1; }
HAVE_SMARTCTL=0; have smartctl && HAVE_SMARTCTL=1
HAVE_LSBLK=0;    have lsblk    && HAVE_LSBLK=1
HAVE_BLKID=0;    have blkid    && HAVE_BLKID=1
HAVE_NVME=0;     have nvme     && HAVE_NVME=1
if [ "$(id -u 2>/dev/null)" = "0" ]; then ROOT=1; else ROOT=0; fi

say "==================================================================="
say " kogler homelab — Phase 1a disk-facts collector (READ-ONLY)"
say " label=$LABEL  root=$ROOT  smartctl=$HAVE_SMARTCTL lsblk=$HAVE_LSBLK blkid=$HAVE_BLKID nvme=$HAVE_NVME"
say "==================================================================="

# ── destination resolution ────────────────────────────────────────────────────
ALLOWED_FS='vfat fat exfat exfat_fuse ntfs ntfs3 ntfs-3g udf ext4 ext3 ext2 btrfs xfs f2fs'
fs_ok() { case " $ALLOWED_FS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

disk_of_part() {
  case $1 in
    *p[0-9]*)                 b=${1%p*} ;;                       # nvme0n1p2 / mmcblk0p1
    nvme*n[0-9]|mmcblk[0-9])  b=$1 ;;                            # whole-disk sources
    *)                        b=$(printf '%s' "$1" | sed 's/[0-9]*$//') ;;  # sda1 -> sda
  esac
  printf '%s' "$b"
}

is_removable() { [ "$(cat "/sys/class/block/$1/removable" 2>/dev/null)" = "1" ]; }

probe_write() {
  pf="$1/.facts-probe.$$"
  if : > "$pf" 2>/dev/null; then rm -f "$pf"; return 0; fi
  return 1
}

MNTDIR=""; MOUNTED_BY_US=0
try_mount_rw() {                       # $1 = /dev/<part> ; sets MNTDIR on success
  mnt="$WORK/mt$$"
  mkdir -p "$mnt" 2>/dev/null || return 1
  if mount "$1" "$mnt" >/dev/null 2>&1; then
    if probe_write "$mnt"; then MNTDIR=$mnt; MOUNTED_BY_US=1; return 0; fi
    umount "$mnt" 2>/dev/null
  fi
  return 1
}

list_parts() {                         # $1 = disk ; prints unmounted partition names
  for ent in /sys/class/block/"$1"/*; do
    [ -e "$ent" ] || continue
    pn=${ent##*/}
    [ -f "$ent/partition" ] || continue
    grep -qs "^/dev/$pn " /proc/mounts && continue
    printf '%s\n' "$pn"
  done
}

DEST="" ; HOW=""
# Stage 1: already-mounted writable fs on a removable disk
while read -r src mp fstype _rest; do
  case $src in /dev/*) ;; *) continue ;; esac            # skips 9p/drvfs/net mounts too
  case ${src#/dev/} in dm-*|mapper/*|loop*|sr*|fd*|md*) continue ;; esac
  case $mp in
    /run/media/*) : ;;
    /|/proc*|/sys*|/dev*|/run/*|/lib/live*|/var/live*|/cdrom*|/media/cdrom*|/target*) continue ;;
  esac
  fs_ok "$fstype" || continue
  disk=$(disk_of_part "${src#/dev/}")
  is_removable "$disk" || continue
  if probe_write "$mp"; then DEST=$mp; HOW="already-mounted removable partition ($src)"; break; fi
done < /proc/mounts

# Boot-medium disk (for stage 2)
BOOT_DISK=""
while read -r src mp _fs _rest; do
  case $src in /dev/*) ;; *) continue ;; esac
  if [ -f "$mp/.disk/info" ] || [ -f "$mp/live/filesystem.squashfs" ] \
     || [ -f "$mp/casper/filesystem.squashfs" ] || [ -f "$mp/boot/grub/grub.cfg" ]; then
    BOOT_DISK=$(disk_of_part "${src#/dev/}"); break
  fi
done < /proc/mounts

# Stage 2: unmounted writable partition on the boot medium's own disk
if [ -z "$DEST" ] && [ -n "$BOOT_DISK" ]; then
  say "boot medium disk: $BOOT_DISK — looking for a writable partition ..."
  for pn in $(list_parts "$BOOT_DISK"); do
    if try_mount_rw "/dev/$pn"; then DEST=$MNTDIR; HOW="boot-medium partition /dev/$pn (auto-mounted)"; break; fi
  done
fi

# Stage 3: any other unmounted writable partition on a removable disk
if [ -z "$DEST" ]; then
  for p in /sys/class/block/*; do
    [ -e "$p" ] || continue
    dk=${p##*/}
    [ "$dk" = "$BOOT_DISK" ] && continue
    is_removable "$dk" || continue
    for pn in $(list_parts "$dk"); do
      if try_mount_rw "/dev/$pn"; then DEST=$MNTDIR; HOW="removable partition /dev/$pn (auto-mounted)"; break 2; fi
    done
  done
fi

# Stage 4: fallbacks
if [ -z "$DEST" ]; then
  if [ -w . ] && [ "$PWD" != "/" ]; then DEST=$PWD; HOW="FALLBACK current directory"
  elif [ -w /tmp ]; then DEST=/tmp; HOW="FALLBACK /tmp"
  else DEST=$WORK; CLEANUP=0; HOW="FALLBACK tmpfs (VOLATILE — lost on reboot)"; fi
fi
say "output destination: $DEST  [$HOW]"
[ "$HOW" != "${HOW#FALLBACK}" ] && say "NOTE: stick not writable/auto-mountable — file lands outside the USB; copy it off manually!"

# ── report header ─────────────────────────────────────────────────────────────
{
  echo "kogler homelab — disk facts (Phase 1a, READ-ONLY collector)"
  echo "generated : $(date)"
  echo "label     : $LABEL"
  echo "hostname  : $(cat /etc/hostname 2>/dev/null || echo '?')"
  echo "kernel    : $(uname -r 2>/dev/null || echo '?')"
  echo "root      : $ROOT   tools: smartctl=$HAVE_SMARTCTL lsblk=$HAVE_LSBLK blkid=$HAVE_BLKID nvme=$HAVE_NVME"
  echo "guarantee : this script only READS disks; it wrote exactly one file (this report)."
  [ "$HAVE_SMARTCTL" = 0 ] && echo "WARNING   : smartmontools absent — identity facts complete, health/hour data missing."
} >> "$REPORT"
cap 'cat /etc/os-release 2>/dev/null || cat /etc/debian_version 2>/dev/null'

# ── by-id reverse map ────────────────────────────────────────────────────────
ls -l /dev/disk/by-id/ 2>/dev/null \
  | awk '/ -> / {id=$9; t=$NF; sub(/^.*\//,"",t); print t "\t" id}' > "$WORK/byid.tsv"

ids_of() { awk -F'\t' -v D="$1" '$1==D {printf "%s ", $2}' "$WORK/byid.tsv" 2>/dev/null; }

sec "/dev/disk/by-id/ FULL LISTING (SSOT discipline: never use sdX names)"
cap 'ls -l /dev/disk/by-id/'

# ── per-disk collection ──────────────────────────────────────────────────────
DISKS=""
for p in /sys/class/block/*; do
  [ -e "$p" ] || continue
  d=${p##*/}
  case $d in
    loop*|ram*|zram*|sr*|fd*|dm-*|md*) continue ;;
    *p[0-9]*) continue ;;                                        # partitions (nvme0n1p1, mmcblk0p1)
    sd[a-z]|sd[a-z][a-z]|vd[a-z]|vd[a-z][a-z]) : ;;              # whole SATA/SCSI/virtio disks
    nvme*n[0-9]|nvme*n[0-9][0-9]|mmcblk[0-9]) : ;;               # whole NVMe/mmcblk disks
    *) continue ;;
  esac
  DISKS="$DISKS $d"
done
[ -z "$DISKS" ] && say "no block devices matched /sys/class/block filters!"

printf '%-7s %-21s %-16s %6s %-4s %7s %5s %5s %s\n' \
  DEV MODEL SERIAL SIZE TRAN POWHRS REALL PEND HEALTH > "$TBL"

num_or_zero() { case $1 in ''|*[!0-9]*) echo 0 ;; *) echo "$1" ;; esac; }

for d in $DISKS; do
  p="/sys/class/block/$d"
  df="$WORK/smart.$d"

  model=$(cat "$p/device/model" 2>/dev/null | tr -s ' \t' ' ')
  serial=$(cat "$p/device/serial" 2>/dev/null | tr -s ' \t' ' ')
  vendor=$(cat "$p/device/vendor" 2>/dev/null | tr -s ' \t' ' ')
  fw=$(cat "$p/device/firmware_rev" 2>/dev/null | tr -s ' \t' ' ')
  sect=$(cat "$p/size" 2>/dev/null)
  size=$(awk -v S="${sect:-0}" 'BEGIN{printf "%.0fG", S*512/1073741824}')
  rota=$(cat "$p/queue/rotational" 2>/dev/null)
  tpath=$(readlink -f "$p" 2>/dev/null)
  case $tpath in
    */virtual/*) transport=virt ;;
    *nvme*)      transport=nvme ;;
    */usb*)      transport=usb ;;
    */ata[0-9]*) transport=sata ;;
    *)           transport=scsi ;;
  esac
  ids=$(ids_of "$d")

  hours=-; realloc=-; pending=-; uncorr=-; temp=-; ovr="-"; have_smart=0
  if [ "$HAVE_SMARTCTL" = 1 ]; then
    smartctl -x "/dev/$d" > "$df" 2>&1 && have_smart=1
    hours=$(awk '/Power_On_Hours/{v=$10} END{print v}' "$df" | tr -d ',')
    realloc=$(awk '/Reallocated_Sector_Ct/{v=$10} END{print v}' "$df")
    pending=$(awk '/Current_Pending_Sector/{v=$10} END{print v}' "$df")
    uncorr=$(awk '/Offline_Uncorrectable|Uncorrectable_Error_Cnt/{v=$10} END{print v}' "$df")
    temp=$(awk '/Temperature_Celsius/{v=$10} END{print v}' "$df")
    [ -z "$temp" ] && temp=$(awk -F': *' '/^Temperature:/{print $2; exit}' "$df" | cut -d' ' -f1)
    ovr=$(grep -i 'overall-health' "$df" | tail -n 1 | awk -F': *' '{print $2}')
    ovr=${ovr:-unknown}
  fi

  health="OK"
  r=$(num_or_zero "$realloc"); pp=$(num_or_zero "$pending"); u=$(num_or_zero "$uncorr")
  [ "$r"  -gt 0 ] && health="WARN(realloc=$r)"
  [ "$pp" -gt 0 ] && health="WARN(pending=$pp)"
  [ "$u"  -gt 0 ] && health="FAIL(uncorr=$u)"
  case $ovr in *FAILED*) health="FAIL(self-assessment)" ;; esac
  [ "$have_smart" = 0 ] && health="n/a (no smartctl)"

  printf '%-7s %-21.21s %-16.16s %6s %-4s %7s %5s %5s %s\n' \
    "$d" "${model:-${vendor:-?}}" "${serial:-?}" "$size" "$transport" "$hours" "${realloc#0}" "${pending#0}" "$health" >> "$TBL"

  sec "DISK /dev/$d — model=${model:-?}  serial=${serial:-?}"
  {
    echo "size=$size sectors=$sect transport=$transport rotational=$rota firmware=${fw:--}"
    echo "by-id:"
    for id in $ids; do echo "  /dev/disk/by-id/$id"; done
    [ -z "$ids" ] && echo "  (no by-id link resolved)"
  } >> "$REPORT"
  if [ "$have_smart" = 1 ]; then
    printf '\n--- smartctl -x ---\n' >> "$REPORT"; cat "$df" >> "$REPORT"
  else
    echo "(smartctl absent — install smartmontools in the live session for health data)" >> "$REPORT"
  fi
done

# ── HD-128 quick-reference section ───────────────────────────────────────────
sec "NVMe BY-ID (HD-128) — paste these EXACT strings into host_vars/oldsrv storage_nvme_data_by_id"
ls -l /dev/disk/by-id/ 2>/dev/null | grep -i 'nvme' >> "$REPORT" || echo "(no nvme by-id links found)" >> "$REPORT"

# ── summary (console + report) ───────────────────────────────────────────────
sec "SUMMARY TABLE"
cat "$TBL" >> "$REPORT"
say ""
say "---------------------------- disks found -------------------------------------"
cat "$TBL" >&2
say "------------------------------------------------------------------------------"

sec "CONTEXT — lsblk"
[ "$HAVE_LSBLK" = 1 ] && { cap 'lsblk'; cap 'lsblk -o NAME,KNAME,MODEL,SERIAL,SIZE,TYPE,FSTYPE,TRAN,ROTA,MOUNTPOINT'; }

sec "CONTEXT — blkid (EXISTING filesystem signatures — pre-wipe awareness, read-only query)"
[ "$HAVE_BLKID" = 1 ] && cap 'blkid -o full 2>/dev/null || blkid'

sec "CONTEXT — nvme-cli"
[ "$HAVE_NVME" = 1 ] && cap 'nvme list'

sec "CONTEXT — kernel view"
cap 'cat /proc/partitions'
cap 'cat /proc/mounts'

sec "RETURN PATH"
{
  echo "destination used : $DEST  [$HOW]"
  echo "file             : $DEST/$REPORT_NAME"
  echo
  echo "back at the laptop:"
  echo "  1. nvme-eui.* strings  -> host_vars/oldsrv  storage_nvme_data_by_id  (closes HD-128)"
  echo "  2. HDD power-on hours  -> refresh docs/hardware-nas.md tables (old sdX-based ranges)"
  echo "  3. blkid section       -> sanity input before Pool-Creation Runbook step 0 (wipefs)"
} >> "$REPORT"

# ── deliver ──────────────────────────────────────────────────────────────────
cp "$REPORT" "$DEST/$REPORT_NAME" || { CLEANUP=0; say "ERROR: copy to $DEST failed — report kept at $REPORT"; exit 1; }
sync
say ""
say "==================================================================="
say " DONE — report written to:"
say "   $DEST/$REPORT_NAME"
[ "$MOUNTED_BY_US" = 1 ] && say " (stick partition was auto-mounted; umount before unplugging: umount $DEST)"
[ "$CLEANUP" = 0 ] && say " !! VOLATILE location — copy the file off THIS SYSTEM before rebooting !!"
say "==================================================================="

exit 0
