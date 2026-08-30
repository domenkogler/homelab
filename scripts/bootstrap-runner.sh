#!/bin/bash
# bootstrap-runner.sh — fully idempotent setup for any management laptop / WSL Debian runner (relocated from IaC/, HD-256)
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

# Install collections (Galaxy handles idempotency and skips re-installs).
# SSOT = requirements.yml (Renovate-tracked, HD-90) — covers community.general,
# community.docker AND community.routeros (router/switch roles need it).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
ansible-galaxy collection install -r "$REPO/IaC/ansible/requirements.yml"

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
chmod 700 ~/.config/op   # op CLI refuses world-accessible config dirs (found live 2026-08-22, true-zero rebuild)
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
# Neutralize any LEGACY inline token export in ~/.bashrc (HD-86): older setups embedded
# the plaintext token there; the restricted file above is the only sanctioned location.
# Last assignment wins in bash, so a leftover inline export shadows or duplicates the file.
sed -i '/^export OP_SERVICE_ACCOUNT_TOKEN=/d' ~/.bashrc

# Make the systemd ssh-agent socket (if present) the default SSH agent for git commit
# signing + SSH auth (HD-265). Guarded: only exported when the socket actually exists.
# Kept here (host environment, not git-bootstrap) so every shell can use the loaded keys.
if ! grep -q 'SSH_AUTH_SOCK=.*openssh_agent' ~/.bashrc; then
  cat >> ~/.bashrc <<'BASHRC_SSH'
# 1Password-op-managed SSH agent (systemd socket) for git commit signing + SSH auth (HD-265).
if [ -S /run/user/$(id -u)/openssh_agent ]; then
    export SSH_AUTH_SOCK=/run/user/$(id -u)/openssh_agent
fi
BASHRC_SSH
  echo "✔ SSH_AUTH_SOCK set in ~/.bashrc (systemd ssh-agent socket)."
else
  echo "ℹ SSH_AUTH_SOCK line already in ~/.bashrc."
fi

# Auto-load the commit-signing + GitHub auth SSH keys into the agent on every shell start
# (HD-300). ssh-agent keeps keys in memory only (security by design), so each new agent
# process loses them on restart; this block re-adds the on-disk keys when the agent is
# reachable but empty. Idempotent: ssh-add -l + grep is a no-op when both keys are
# already loaded. Pairs with the SSH_AUTH_SOCK line above — one agent socket + one
# auto-load is enough. Guarded by the grep -q marker so re-runs are safe.
if ! grep -q 'hd300-github-keys-autoload' ~/.bashrc; then
  cat >> ~/.bashrc <<'BASHRC_KEYS'
# hd300-github-keys-autoload: re-add github_signing + github_auth to the ssh-agent
# when the agent is reachable but the keys are missing (ssh-agent is non-persistent).
if [ -S "$SSH_AUTH_SOCK" ] && [ -f "$HOME/.ssh/github_signing" ] && [ -f "$HOME/.ssh/github_auth" ]; then
    if ! ssh-add -l 2>/dev/null | grep -q 'github_signing'; then
        ssh-add "$HOME/.ssh/github_signing" "$HOME/.ssh/github_auth" 2>/dev/null
    fi
fi
BASHRC_KEYS
  echo "✔ GitHub keys auto-load block set in ~/.bashrc (HD-300)."
else
  echo "ℹ GitHub keys auto-load block already in ~/.bashrc."
fi

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
