# Homelab Kogler

1. **Kloniranje kode:** `git clone <vaš-repozitorij>`
2. **Zagon pripravljalne skripte:** `bash bootstrap.sh` (vnesete svoj 1Password žeton, ustvari se nov SSH ključ).
3. **Osvežitev okolja:** `source ~/.bashrc`
4. **Avtorizacija na PC-ju:** `ssh-copy-id uporabnik@IP_NASLOV_PCJA` (s tem PC-ju poveste, da od zdaj naprej zaupa tudi vašemu novemu prenosniku).
5. **Zagon:** `ansible-playbook -i inventory.ini site.yml`

## Arhitektura

  [ UPRAVLJALNA NAPRAVA ] (Prenosnik 1, Prenosnik 2, itd.)
           │
           ├── (Varno vleče skrivnosti med izvajanjem) ──► [ 1Password Cloud ]
           │
     (SSH ed25519)
           │
           ▼
     [ DOMAČI STREŽNIK (PC) ] ── (Zagon vlog preko Ansibla)
           │
           ├── roles/common       ──► Namestitev Dockerja in OS paketov
           ├── roles/storage      ──► Standalone Kopia (Read-Only dostop do /opt)
           ├── roles/identity     ──► Authentik Server + PostgreSQL bazo
           └── roles/cloud_apps   ──► Nextcloud, OnlyOffice, Immich, HA

## Bootstrap Ansible

[Upravljanje z Ansible](./bootstrap/ansible.md)