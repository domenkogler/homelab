#!/bin/bash
# bootstrap.sh - Popolnoma idempotenten setup za kateri koli upravljalni prenosnik
set -e

echo "=== 1. Posodobitev sistema in predpogoji ==="
sudo apt update && sudo apt upgrade -y
sudo apt install python3 python3-pip python3-venv curl gpg git -y

echo "=== 2. Idempotentna namestitev 1Password CLI ==="
# Prenesi uradni GPG ključ in preveri politike (Uradna 1Password razvijalska metoda)
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

echo "=== 3. Idempotentno Python virtualno okolje ==="
if [ ! -d ~/ansible-venv ]; then
    python3 -m venv ~/ansible-venv
fi

# Aktivacija in posodobitev paketov znotraj okolja
source ~/ansible-venv/bin/activate
pip install --upgrade pip
pip install ansible

# Namestitev zbirk (Galaxy sam poskrbi za idempotenco in ne namešča ponovno)
ansible-galaxy collection install community.docker community.general

echo "=== 4. Idempotentno generiranje SSH ključev ==="
if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "domen@kogler.si" -N "" -f ~/.ssh/id_ed25519
    echo "✔ Nov SSH ključ ustvarjen."
else
    echo "ℹ SSH ključ že obstaja, preskakujem."
fi

echo "=== 5. Idempotenten vnos 1Password žetona ==="
if ! grep -q "OP_SERVICE_ACCOUNT_TOKEN" ~/.bashrc; then
    read -sp "Prilepite vaš 1Password OP_SERVICE_ACCOUNT_TOKEN: " OP_TOKEN
    echo ""
    echo "source ~/ansible-venv/bin/activate" >> ~/.bashrc
    echo "export OP_SERVICE_ACCOUNT_TOKEN=\"$OP_TOKEN\"" >> ~/.bashrc
    echo "✔ 1Password žeton shranjen v ~/.bashrc."
else
    echo "ℹ 1Password žeton že nastavljen v ~/.bashrc."
fi

echo "=== 6. Idempotentna nastavitev sudo brez gesla za lokalni WSL ==="
if [ ! -f /etc/sudoers.d/$USER ]; then
    echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$USER > /dev/null
    sudo chmod 0440 /etc/sudoers.d/$USER
    echo "✔ Sudo pravice brez gesla so uspešno nastavljene."
else
    echo "ℹ Sudo pravice za uporabnika $USER so že urejene, preskakujem."
fi

echo "========================================================================="
echo " ✔ POPOLNI BOOTSTRAP USPEŠNO ZAKLJUČEN!"
echo " Prosimo, zaženite naslednji ukaz za osvežitev okolja:"
echo " source ~/.bashrc"
echo "========================================================================="
