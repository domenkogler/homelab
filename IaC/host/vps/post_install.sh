#!/bin/bash
# =====================================================================
# VPS-SPECIFIC BOOTSTRAP SCRIPT (host vps.kogler.si — netcup RS 2000 G12)
# Public-edge box on the internet. Deliberately NOT identical to the
# shared IaC/host/post_install.sh: this box does NOT get ai-debug, and
# SSH is limited to ansible-admin only (no LAN constraint applies on
# a public host).
# Preseed late_command copies it to the target as /tmp/post_install.sh.
# =====================================================================
# SECURITY NOTE: same convention as the shared script — never commit real
# keys; the AI injects the real public keys from the 1Password "Homelab"
# vault at generation time (admin_laptop_ssh_pubkey, ssh_ansible_pubkey).
# Only TWO keys are authorized on the VPS (Domen + Ansible). NO AI key.
# =====================================================================

set -euo pipefail

# 1. Update + install Python (Ansible requirement)
apt-get update && apt-get install -y python3 python3-pip sudo openssh-server

# ---------------------------------------------------------------------
# 2. ansible-admin user
#    netcup hook flow: the d-i preseed does NOT run, so the user may not
#    exist yet — create it if missing (idempotent). On the preseed path it
#    already exists; useradd -D is a no-op via getent guard.
# ---------------------------------------------------------------------
if ! id -u ansible-admin >/dev/null 2>&1; then
  useradd -m -s /bin/bash ansible-admin
fi
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
# 3. NO ai-debug user on the VPS (public box — do not expose the AI key).
# ---------------------------------------------------------------------

# ---------------------------------------------------------------------
# 4. sshd hardening (VPS flavor) — key-only, ansible-admin only.
#    Idempotent marker so preseed retries never accumulate directives.
# ---------------------------------------------------------------------
if ! grep -q '^# Homelab hardening (post_install.sh)' /etc/ssh/sshd_config 2>/dev/null; then
cat >> /etc/ssh/sshd_config <<'EOF'

# Homelab hardening (post_install.sh)
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
LogLevel VERBOSE
AllowUsers ansible-admin
EOF
fi

systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

# 5. Cleanup temp script
rm -f /tmp/post_install.sh
exit 0