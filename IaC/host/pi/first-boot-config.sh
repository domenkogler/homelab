#!/bin/bash
# =====================================================================
# Pi first-boot SD card config — run AFTER flashing raspi.debian.net image
#
# Prerequisites:
#   1. Download the latest tested image from https://raspi.debian.net/tested-images/
#      (pick the Pi 4 image for the current Debian release).
#   2. Flash to microSD (≥32 GB) — Raspberry Pi Imager, Balena Etcher, or dd.
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
#   - Writes cloud-init user-data (ansible-admin + ai-debug users, SSH keys)
#   - Writes fallback post-boot script (if image lacks cloud-init)
#   - Sets hostname on the root partition (if accessible)
#
# SSH keys: replace the <PLACEHOLDER> values below with real public keys
# from the 1Password "Homelab" vault (laptop-domen_ssh, ansible-admin_ssh, ai_ssh).
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
# 1. Enable SSH
# -----------------------------------------------------------------
touch "$BOOT/ssh"
echo "  [1/4] SSH enabled (boot/ssh)"

# -----------------------------------------------------------------
# 2. Cloud-init user-data (primary method)
#    raspi.debian.net images historically don't include cloud-init, but
#    writing user-data is harmless if unsupported. The fallback script
#    below covers that case.
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
echo "  [2/4] Cloud-init user-data written (boot/user-data)"
echo "        ⚠ Replace SSH key placeholders with real 1Password values!"

# -----------------------------------------------------------------
# 3. Fallback post-boot script (for images without cloud-init)
#    If the image doesn't support cloud-init, use this after first boot:
#      sudo bash /boot/firstboot.sh
# -----------------------------------------------------------------
cat > "$BOOT/firstboot.sh" <<'EOF'
#!/bin/bash
# Fallback first-boot setup — run if cloud-init didn't create the users.
# Usage from the Pi after first SSH login:
#   sudo bash /boot/firstboot.sh
set -euo pipefail

# Create ansible-admin user (passwordless sudo)
if ! id ansible-admin &>/dev/null; then
    useradd -m -s /bin/bash ansible-admin
    usermod -aG sudo ansible-admin
    mkdir -p /home/ansible-admin/.ssh && chmod 700 /home/ansible-admin/.ssh
    echo "ssh-ed25519 <PERSONAL_PUBKEY_FROM_1PASSWORD> admin@laptop" >> /home/ansible-admin/.ssh/authorized_keys
    echo "ssh-ed25519 <ANSIBLE_PUBKEY_FROM_1PASSWORD> ansible" >> /home/ansible-admin/.ssh/authorized_keys
    chmod 600 /home/ansible-admin/.ssh/authorized_keys
    chown -R ansible-admin:ansible-admin /home/ansible-admin/.ssh
    echo "ansible-admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible-admin
    chmod 0440 /etc/sudoers.d/ansible-admin
    echo "  Created ansible-admin user"
fi

# Create ai-debug user (no sudo)
if ! id ai-debug &>/dev/null; then
    useradd -m -s /bin/bash ai-debug
    mkdir -p /home/ai-debug/.ssh && chmod 700 /home/ai-debug/.ssh
    echo 'restrict,no-agent-forwarding,no-port-forwarding,no-X11-forwarding,from="10.10.0.0/16" ssh-ed25519 <AI_PUBKEY_FROM_1PASSWORD> openrouter_ai' \
        >> /home/ai-debug/.ssh/authorized_keys
    chmod 600 /home/ai-debug/.ssh/authorized_keys
    chown -R ai-debug:ai-debug /home/ai-debug/.ssh
    echo "  Created ai-debug user"
fi

# Harden SSH
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\?LogLevel.*/LogLevel VERBOSE/' /etc/ssh/sshd_config
if ! grep -q '^AllowUsers' /etc/ssh/sshd_config; then
    echo 'AllowUsers ansible-admin ai-debug' >> /etc/ssh/sshd_config
fi
systemctl restart ssh
echo "  SSH hardened"

echo "=== First-boot setup complete ==="
echo "You can now run: ansible-playbook -i inventory.ini playbooks/raspberry_pi.yml"
EOF
chmod +x "$BOOT/firstboot.sh"
echo "  [3/4] Fallback script written (boot/firstboot.sh)"

# -----------------------------------------------------------------
# 4. Placeholder assertion (B5/H2/H3 — HD-201): refuse to hand back an
#    SD card that would boot with placeholder keys — the Pi has no root
#    password and no console recovery, so placeholder pubkeys = locked-out
#    host. The generated files on the card must carry the real 1Password
#    public keys BEFORE first power-on. On a hit the written files stay on
#    the card: fix them in place, or edit the key lines in this script and
#    re-run it. DO NOT power on the Pi until the placeholders are gone.
#    (This script's own source intentionally still contains placeholders —
#    only the WRITTEN files are asserted.)
# -----------------------------------------------------------------
PLACEHOLDER_PATTERNS='REPLACE_ME_|<SERIAL>|VNESI_MODEL_IN_SERIJSKO_SSD_STEVILKO|VNESI_SERIJSKO_USB_KLJUCA|_FROM_1PASSWORD>|<PLACEHOLDER>'
placeholder_hits=""
for cfg_file in "$BOOT/user-data" "$BOOT/firstboot.sh"; do
    if grep -Eq "$PLACEHOLDER_PATTERNS" "$cfg_file"; then
        echo "FATAL (HD-201): placeholder keys still present in $cfg_file" >&2
        placeholder_hits=1
    fi
done
if [ -n "$placeholder_hits" ]; then
    echo "       Replace them with the real 1Password Homelab-ansible public keys" >&2
    echo "       (laptop-domen_ssh / ansible-admin_ssh / ai_ssh): edit the files on" >&2
    echo "       the card directly, or edit the key lines in this script and re-run." >&2
    exit 1
fi

# -----------------------------------------------------------------
# 4. Set hostname (root partition, if accessible)
# -----------------------------------------------------------------
ROOT_ETC="${BOOT/\/boot/\/etc}"  # crude root partition path guess
if [ -d "$ROOT_ETC" ]; then
    echo "pi" > "$ROOT_ETC/hostname"
    echo "  [4/4] Hostname set to 'pi'"
else
    echo "  [4/4] SKIPPED — root partition not mounted."
fi

echo ""
echo "=== Done ==="
echo "Safely eject the SD card, insert it into the Pi, and power on."
echo ""
echo "After boot:"
echo "  ping pi.kogler.si"
echo "  ssh ansible-admin@pi.kogler.si   (if cloud-init worked)"
echo ""
echo "If cloud-init did NOT create the users, log in with the default"
echo "credentials and run the fallback script:"
echo "  sudo bash /boot/firstboot.sh"
echo ""
echo "Then:"
echo "  ansible-playbook -i inventory.ini playbooks/raspberry_pi.yml"