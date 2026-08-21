#!/bin/bash
# =====================================================================
# SHARED BOOTSTRAP SCRIPT FOR ANSIBLE + AI DEBUG USERS
# Single copy for ALL homelab hosts (nas, oldsrv, ...) — same keys.
# Preseed late_command copies it to the target as /tmp/post_install.sh.
# =====================================================================
# SECURITY NOTE: Never commit real keys — only placeholders. At media-build time
# the real PUBLIC keys are injected from the 1Password `Homelab-ansible` vault
# (items: laptop-domen_ssh · ansible-admin_ssh · ai_ssh, field=public_key).
# =====================================================================

set -euo pipefail

# 1. Update + install Python (Ansible requirement)
apt-get update && apt-get install -y python3 python3-pip sudo openssh-server

# ---------------------------------------------------------------------
# 2. ansible-admin user (created by preseed.cfg)
# ---------------------------------------------------------------------
mkdir -p /home/ansible-admin/.ssh
chmod 700 /home/ansible-admin/.ssh

# 2a. Domen's personal key (1Password: admin_laptop_ssh_pubkey)
echo "ssh-ed25519 <PERSONAL_PUBKEY_FROM_1PASSWORD> admin@laptop" >> /home/ansible-admin/.ssh/authorized_keys

# 2b. Dedicated Ansible key (1Password: ssh_ansible_pubkey)
echo "ssh-ed25519 <ANSIBLE_PUBKEY_FROM_1PASSWORD> ansible" >> /home/ansible-admin/.ssh/authorized_keys

chmod 600 /home/ansible-admin/.ssh/authorized_keys
chown -R ansible-admin:ansible-admin /home/ansible-admin/.ssh

# 2c. Passwordless sudo ONLY for ansible-admin
mkdir -p /etc/sudoers.d
echo "ansible-admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible-admin
chmod 0440 /etc/sudoers.d/ansible-admin

# ---------------------------------------------------------------------
# 3. ai-debug user — AI debugging only, NO sudo
# ---------------------------------------------------------------------
useradd -m -s /bin/bash ai-debug
mkdir -p /home/ai-debug/.ssh
chmod 700 /home/ai-debug/.ssh

# AI key (1Password: ssh_ai_pubkey / openrouter_ai)
# Restrictions: LAN only (10.10.0.0/16), no agent/port/X11 forwarding
echo 'restrict,no-agent-forwarding,no-port-forwarding,no-X11-forwarding,from="10.10.0.0/16" ssh-ed25519 <AI_PUBKEY_FROM_1PASSWORD> openrouter_ai' >> /home/ai-debug/.ssh/authorized_keys

chmod 600 /home/ai-debug/.ssh/authorized_keys
chown -R ai-debug:ai-debug /home/ai-debug/.ssh

# ---------------------------------------------------------------------
# 4. sshd hardening (all homelab hosts)
# Idempotent (KOPS-012 / HD-88): skip the append if the hardening marker already exists so a
# re-run (e.g. preseed retry) never accumulates duplicate sshd directives.
if ! grep -q '^# Homelab hardening (post_install.sh)' /etc/ssh/sshd_config 2>/dev/null; then
cat >> /etc/ssh/sshd_config <<'EOF'

# Homelab hardening (post_install.sh)
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
LogLevel VERBOSE
AllowUsers ansible-admin ai-debug
EOF
fi

systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

# ---------------------------------------------------------------------
# 5. Placeholder assertion (B5/H2/H3 — HD-201): fail loudly BEFORE the
#    installer reboots when the produced config still carries placeholders
#    (REPLACE_ME_* tokens, placeholder disk serials, placeholder pubkeys).
#    A host that boots with unreplaced keys is locked out (no root
#    password, KOPS-044) — the late_command failure surfaces the misfire
#    on the installer console/log instead.
#    Covers the shared preseeds (nas + oldsrv) and, by the same rule,
#    pi/first-boot-config.sh (same assertion, same pattern list).
# ---------------------------------------------------------------------
PLACEHOLDER_PATTERNS='REPLACE_ME_|<SERIAL>|VNESI_MODEL_IN_SERIJSKO_SSD_STEVILKO|VNESI_SERIJSKO_USB_KLJUCA|_FROM_1PASSWORD>|<PLACEHOLDER>'
# Produced-config files only — never this script itself (its pattern
# definition would self-match). fstab/boot-device strings cover the
# placeholder-serial class; authorized_keys cover the pubkey class.
PLACEHOLDER_CHECK_FILES="/home/ansible-admin/.ssh/authorized_keys /home/ai-debug/.ssh/authorized_keys /etc/ssh/sshd_config /etc/fstab"
placeholder_hits=""
for cfg_file in $PLACEHOLDER_CHECK_FILES; do
    if [ -f "$cfg_file" ] && grep -Eq "$PLACEHOLDER_PATTERNS" "$cfg_file"; then
        placeholder_hits="$placeholder_hits $cfg_file"
    fi
done
if [ -n "$placeholder_hits" ]; then
    echo "FATAL (HD-201): placeholder content still present in:$placeholder_hits" >&2
    echo "       patterns: $PLACEHOLDER_PATTERNS" >&2
    echo "       Replace the placeholders with the real 1Password Homelab-ansible" >&2
    echo "       values (laptop-domen_ssh / ansible-admin_ssh / ai_ssh) and re-run" >&2
    echo "       the install — aborting BEFORE reboot so the misfire is loud." >&2
    exit 1
fi

# 6. Cleanup temp script
rm -f /tmp/post_install.sh
exit 0
