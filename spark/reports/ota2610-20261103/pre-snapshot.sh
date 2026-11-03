#!/usr/bin/env bash
# pre-snapshot.sh — read-only identity/state capture of the DGX Spark box, run as root ON the box.
#
# Why it exists: OTA2610 arrives through the vendor's own update path, which is
# `nvidia-spark-run-apt-upgrade-once.sh` (`apt-get update` → driver+modules install → `apt-get -y
# full-upgrade` → reboot) rather than a scoped installer, so the platform act has to be reconstructable
# afterwards from what the box was BEFORE it. Everything here is a read: no unit is touched, no package
# moves, no service restarts.
#
# Usage (from a seat that is not served by spark):
#   ssh spark 'sudo -n bash -s' < pre-snapshot.sh > pre-snapshot.txt
set -u

{
  echo "=== pre-update snapshot $(date -Is) seat=$(uname -n)"
  echo "--- identity"
  cat /etc/dgx-release
  echo "uname: $(uname -r)   bios: $(cat /sys/class/dmi/id/bios_version 2>/dev/null)"
  echo "--- cmdline"
  cat /proc/cmdline
  echo "--- nvidia"
  nvidia-smi --query-gpu=name,driver_version,vbios_version,clocks.sm,clocks.max.sm,uuid --format=csv,noheader 2>/dev/null
  echo "--- ota"
  nvidia-spark-ota-check installed-name 2>/dev/null
  nvidia-spark-ota-check torn-score 2>/dev/null
  echo "--- platform + kernel packages"
  dpkg-query -W -f='${Package} ${Version} ${Status}\n' 'linux-image*' 'linux-modules-nvidia*' 'linux-nvidia-hwe*' \
    'nvidia-driver*' 'nvidia-spark-*' 'dgx-*' 'nvidia-dgx-*' 2>/dev/null \
    | grep ' install ok installed' | sed 's/ install ok installed//' | sort
  echo "--- holds"
  apt-mark showhold
  echo "--- units"
  for u in dgx-dashboard.service dgx-dashboard-admin.service docker-compose@dgx-dashboard.service \
           docker-compose@spark-ai.service docker-compose@spark-dashboard.service \
           docker-compose@spark-dcgm.service docker-compose@dozzle-agent.service \
           spark-gpu-clock-cap.service spark-oom-watchdog.service \
           nvidia-spark-run-apt-upgrade-once.service nvidia-spark-mlnx-firmware-manager.service \
           docker.service containerd.service alloy.service fwupd.service tailscaled.service; do
    printf '%-48s enabled=%-12s active=%s\n' "$u" \
      "$(systemctl is-enabled "$u" 2>&1)" "$(systemctl is-active "$u" 2>&1)"
  done
  echo "default-target: $(systemctl get-default)"
  echo "masked units:"
  systemctl list-unit-files --state=masked --no-legend --no-pager | awk '{print "  "$1}'
  echo "--- containers"
  docker ps --format '{{.Names}} {{.Status}}' | sort
  for c in $(docker ps --format '{{.Names}}'); do
    docker inspect "$c" --format "  $c started={{.State.StartedAt}} restarts={{.RestartCount}} img={{.Image}}" | cut -c1-150
  done
  echo "--- listeners"
  ss -ltn | awk 'NR>1{print "  "$4}' | sort -u
  echo "--- disk"
  df -h /
  docker system df
  echo "--- boot images"
  ls -1 /boot/vmlinuz-* 2>/dev/null
  echo "--- fwupd devices"
  fwupdmgr get-devices --json 2>/dev/null | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
for x in d.get("Devices",[]):
    print("  %-28s %-12s %s" % (x.get("Name"), x.get("Plugin"), (x.get("Version") or "")[:12]))' 2>/dev/null
  echo "--- markers"
  ls /var/run/reboot-required 2>/dev/null || echo "  no reboot-required marker"
  ls -l /var/lib/nvidia-spark-run-apt-upgrade-once/done 2>/dev/null
  echo "=== end"
} 2>&1
