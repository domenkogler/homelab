#!/bin/bash
# =====================================================================
# SHARED BOOTSTRAP SCRIPT FOR ANSIBLE + AI DEBUG USERS
# Single copy for ALL homelab hosts (nas, oldsrv, ...) — same keys.
# Preseed late_command copies it to the target as /tmp/post_install.sh.
# =====================================================================
# SECURITY NOTE: Never commit real keys — only placeholders. The AI
# injects the real public keys from the 1Password "Homelab" vault at
# generation time (admin_laptop_ssh_pubkey, ssh_ansible_pubkey,
# ssh_ai_pubkey).
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
# ---------------------------------------------------------------------
cat >> /etc/ssh/sshd_config <<'EOF'

# Homelab hardening (post_install.sh)
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
LogLevel VERBOSE
AllowUsers ansible-admin ai-debug
EOF

systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

# 5. Cleanup temp script
rm -f /tmp/post_install.sh
exit 0
