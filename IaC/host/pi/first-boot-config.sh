#!/bin/bash
# =====================================================================
# Pi first-boot SD card config — run AFTER flashing raspi.debian.net image
#
# Prerequisites:
#   1. Download the latest tested image from https://raspi.debian.net/tested-images/
#      (pick the Pi 4 image for the current Debian release).
#   2. Flash to SD card (Raspberry Pi Imager, Balena Etcher, or dd).
#   3. DO NOT boot yet — re-insert the SD card so the boot partition mounts.
#
# Usage:
#   ./first-boot-config.sh <sd_card_mount_point>
#
# Example (Windows WSL / Debian):
#   ./first-boot-config.sh /mnt/d/sd_boot          # Windows-mounted FAT32 partition
#   ./first-boot-config.sh /media/$USER/boot        # Linux automount
#
# What this does:
#   - Enables SSH (creates `ssh` file on the boot partition)
#   - Writes cloud-init user-data (hostname, users, SSH keys)
#   - Sets hostname on the root partition (if accessible)
# =====================================================================

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <sd_card_mount_point>"
    echo "Example: $0 /mnt/d/sd_boot"
    echo ""
    echo "The mount point must contain the FAT32 boot partition"
    echo "(look for 'config.txt' or 'cmdline.txt' in it)."
    exit 1
fi

BOOT="$1"

# -----------------------------------------------------------------
# Verify we're looking at a Raspberry Pi boot partition
# -----------------------------------------------------------------
if [ ! -f "$BOOT/config.txt" ] && [ ! -f "$BOOT/cmdline.txt" ]; then
    echo "Error: '$BOOT' does not look like a Raspberry Pi boot partition"
    echo "(neither config.txt nor cmdline.txt found)."
    exit 1
fi

echo "=== Pi first-boot config ==="
echo "Boot partition: $BOOT"

# -----------------------------------------------------------------
# 1. Enable SSH (standard Raspberry Pi convention)
# -----------------------------------------------------------------
touch "$BOOT/ssh"
echo "  [1/3] SSH enabled (boot/ssh)"

# -----------------------------------------------------------------
# 2. Cloud-init user-data (harmless if image lacks cloud-init)
# -----------------------------------------------------------------
cat > "$BOOT/user-data" <<'EOF'
#cloud-config
hostname: pi
manage_etc_hosts: true

users:
  - name: ansible-admin
    groups: sudo
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ssh-ed25519 <PERSONAL_PUBKEY_FROM_1PASSWORD> admin@laptop
      - ssh-ed25519 <ANSIBLE_PUBKEY_FROM_1PASSWORD> ansible

  - name: ai-debug
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - restrict,no-agent-forwarding,no-port-forwarding,no-X11-forwarding,from="10.10.0.0/16" ssh-ed25519 <AI_PUBKEY_FROM_1PASSWORD> openrouter_ai

ssh_pwauth: false
EOF
echo "  [2/3] Cloud-init user-data written (boot/user-data)"
echo "        ⚠ Replace SSH key placeholders with real 1Password values!"

# -----------------------------------------------------------------
# 3. Hostname + sudo (root partition, if accessible)
# -----------------------------------------------------------------
ROOT_ETC="${BOOT/\/boot/\/etc}"  # crude root partition path guess
if [ -d "$ROOT_ETC" ]; then
    echo "pi" > "$ROOT_ETC/hostname"
    echo "  [3/3] Hostname set to 'pi'"
else
    echo "  [3/3] SKIPPED — root partition not mounted."
fi

echo ""
echo "=== Done ==="
echo "Safely eject the SD card, insert it into the Pi, and power on."
echo "After boot:"
echo "  ssh ansible-admin@pi.kogler.si"
echo "  ansible-playbook -i inventory.ini playbooks/raspberry_pi.yml"