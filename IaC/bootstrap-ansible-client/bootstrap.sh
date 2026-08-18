#!/bin/bash
# bootstrap.sh - Fully idempotent setup for any management laptop
set -e

echo "=== 1. System update and prerequisites ==="
sudo apt update && sudo apt upgrade -y
sudo apt install python3 python3-pip python3-venv curl gpg git -y

echo "=== 2. Idempotent 1Password CLI install ==="
# Download the official GPG key and verify policies (official 1Password developer method)
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --yes --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg && \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
  sudo tee /etc/apt/sources.list.d/1password.list && \
  sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/ && \
  curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | \
  sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol && \
  sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22 && \
  curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --yes --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg && \
  sudo apt update && sudo apt install 1password-cli -y

echo "=== 3. Idempotent Python virtual environment ==="
if [ ! -d ~/ansible-venv ]; then
    python3 -m venv ~/ansible-venv
fi

# Activate and update packages inside the environment
source ~/ansible-venv/bin/activate
pip install --upgrade pip
pip install ansible

# Install collections (Galaxy handles idempotency and skips re-installs)
ansible-galaxy collection install community.docker community.general

echo "=== 4. Idempotent SSH key generation ==="
if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "domen@kogler.si" -N "" -f ~/.ssh/id_ed25519
    echo "✔ New SSH key created."
else
    echo "ℹ SSH key already exists, skipping."
fi

echo "=== 5. Idempotent 1Password token setup ==="
# Store the service-account token in a 0600-protected file, NOT inline in ~/.bashrc
# (KOPS-011 / HD-86). ~/.bashrc is world-readable; a separate chmod 600 file keeps the
# secret out of any shell history/logs and limits it to a single purpose. Ansible's
# community.general.onepassword lookup reads OP_SERVICE_ACCOUNT_TOKEN at run time.
OP_TOKEN_FILE=~/.config/op/homelab-sa-token
mkdir -p ~/.config/op
if [ ! -f "$OP_TOKEN_FILE" ]; then
    read -sp "Paste your 1Password OP_SERVICE_ACCOUNT_TOKEN: " OP_TOKEN
    echo ""
    umask 077
    printf 'export OP_SERVICE_ACCOUNT_TOKEN=%q\n' "$OP_TOKEN" > "$OP_TOKEN_FILE"
    chmod 600 "$OP_TOKEN_FILE"
    unset OP_TOKEN
    echo "✔ 1Password token stored in $OP_TOKEN_FILE (chmod 600)."
else
    echo "ℹ 1Password token already stored in $OP_TOKEN_FILE."
fi
# Idempotently source the venv + the restricted token file from bashrc.
grep -q 'ansible-venv' ~/.bashrc || echo 'source ~/ansible-venv/bin/activate' >> ~/.bashrc
grep -q "homelab-sa-token" ~/.bashrc || printf '\n[ -f %s ] && source %s\n' "$OP_TOKEN_FILE" "$OP_TOKEN_FILE" >> ~/.bashrc

echo "=== 6. Idempotent passwordless sudo for local WSL ==="
if [ ! -f /etc/sudoers.d/$USER ]; then
    echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$USER > /dev/null
    sudo chmod 0440 /etc/sudoers.d/$USER
    echo "✔ Passwordless sudo configured."
else
    echo "ℹ Sudo rules for user $USER already configured, skipping."
fi

echo "========================================================================="
echo " ✔ FULL BOOTSTRAP COMPLETED SUCCESSFULLY!"
echo " Please run the following command to refresh the environment:"
echo " source ~/.bashrc"
echo "========================================================================="
