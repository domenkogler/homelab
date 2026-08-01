#!/bin/bash
# =====================================================================
# GENERIČNA SKRIPTA ZA BOOTSTRAP ANSIBLE UPORABNIKA
# =====================================================================

# 1. Posodobitev in namestitev Python okolja, ki ga Ansible nujno potrebuje
apt-get update && apt-get install -y python3 python3-pip sudo openssh-server

# 2. Priprava SSH imenika za ansible-admin uporabnika
mkdir -p /home/ansible-admin/.ssh
chmod 700 /home/ansible-admin/.ssh

# 3. Vnos vašega osebnega ključa za zagon Ansible-a (iz 1Password)
# Ta ključ bo omogočil, da se vaš računalnik poveže in izvede Ansible playbook.
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_KLJUC_VASES_PRENOSNIKA_IZ_1PASSWORD admin@laptop" >> /home/ansible-admin/.ssh/authorized_keys
chmod 600 /home/ansible-admin/.ssh/authorized_keys
chown -R ansible-admin:ansible-admin /home/ansible-admin/.ssh

# 4. Omogočanje izvajanja ukazov brez vnosa gesla za Ansible (NOPASSWD)
mkdir -p /etc/sudoers.d
echo "ansible-admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible-admin
chmod 0440 /etc/sudoers.d/ansible-admin

# Poubijanje začasne skripte
rm -f /tmp/post_install.sh
exit 0
