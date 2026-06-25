#!/bin/bash
# bootstrap.sh - Zažene se na upravljalni napravi (prenosniku)
set -e

# 1. Posodobitev sistema in namestitev osnovnih orodij
echo "=== 1. Posodobitev sistema in priprava okolja ==="
sudo apt update && sudo apt upgrade -y
sudo apt install python3 python3-pip python3-venv curl gpg git -y

# 2. Namestitev uradnega 1Password CLI 
echo "=== 2. Namestitev 1Password CLI ==="
curl -sS https://1password.com | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://1password.com stable main" | sudo tee /etc/apt/sources.list.d/1password.list
sudo apt update && sudo apt install 1password-cli -y

# 3. Ustvarjanje izoliranega Python virtualnega okolja za Ansible
echo "=== 3. Izolirano okolja za Ansible ==="
mkdir -p ~/ansible-venv
python3 -m venv ~/ansible-venv
source ~/ansible-venv/bin/activate

# 4. Namestitev Ansibla in potrebnih Docker vtičnikov znotraj okolja
echo "=== 4. Namestitev Ansible in Docker ==="
pip install --upgrade pip
pip install ansible
ansible-galaxy collection install community.docker community.general

echo "=== 5. Generiranje SSH ključev ==="
if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "domen@kogler.si" -N "" -f ~/.ssh/id_ed25519
    echo "✔ Nov SSH ključ ustvarjen."
else
    echo "ℹ SSH ključ že obstaja, preskakujem."
fi

echo "=== 6. Vnos 1Password Service Account žetona ==="
# Preveri, če žeton že obstaja v .bashrc, sicer pozove k vnosu
if ! grep -q "OP_SERVICE_ACCOUNT_TOKEN" ~/.bashrc; then
    read -sp "Prilepite vaš 1Password OP_SERVICE_ACCOUNT_TOKEN: " OP_TOKEN
    echo ""
    echo "source ~/ansible-venv/bin/activate" >> ~/.bashrc
    echo "export OP_SERVICE_ACCOUNT_TOKEN=\"$OP_TOKEN\"" >> ~/.bashrc
    echo "✔ 1Password žeton shranjen."
else
    echo "ℹ 1Password žeton že nastavljen v ~/.bashrc."
fi

echo "========================================================================="
echo " SETUP KONČAN! Prosimo, zaženite naslednje ukaze:"
echo " 1. source ~/.bashrc"
echo " 2. ssh-copy-id uporabnik@IP_NASLOV_PCJA"
echo "========================================================================="