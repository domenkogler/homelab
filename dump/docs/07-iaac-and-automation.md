# IaC & Automation

> **Canonical doc.** Based on `Iaac/` directory contents and answers from Theme F.

---

## Overview

Infrastructure-as-Code via **Ansible**, secrets via **1Password**, version-controlled in **Git**.

---

## Control Node (Management Laptop)

### Setup
- **OS:** Windows 10/11 with WSL2 Debian
- **Networking:** Mirrored mode (`.wslconfig`: `networkingMode=mirrored, dnsTunneling=true, firewall=true, autoProxy=true`)
- **Bootstrapped by:** `Iaac/bootstrap-ansible-client/bootstrap.sh`

### Bootstrap Script Installs:
1. System packages: Python3, pip, curl, gpg, git
2. **1Password CLI** (official repo, GPG-verified)
3. Python virtual environment (`~/ansible-venv`)
4. Ansible + collections (`community.docker`, `community.general`)
5. SSH keypair (ED25519, `domen@kogler.si`)
6. 1Password Service Account token (interactive prompt, stored in `~/.bashrc`)
7. Passwordless sudo for WSL user

### After Bootstrap
```bash
source ~/.bashrc       # activates venv + sets OP_SERVICE_ACCOUNT_TOKEN
ansible-playbook site.yml -i inventory.ini
```

---

## Managed Nodes

### deblab (Test VM)
- **What:** Debian in WSL2
- **IP:** 10.10.1.125
- **User:** `domen`
- **Connection:** SSH with ED25519 key
- **Purpose:** Test all Ansible roles before production

### Production Server (Future)
- **What:** Custom Ryzen server or existing hardware with Proxmox
- **Hostname:** TBD (different from deblab)
- **Orchestration:** Same laptop controls both test and production

---

## Ansible Playbook (`site.yml`)

```yaml
- name: Orkestracija Družinskega Strežnika
  hosts: home_servers
  become: true
  vars:                          # Secrets from 1Password
    kopia_pass: "{{ lookup('community.general.onepassword', 'kopia_master_password', ...) }}"
    auth_pg_pass: "{{ lookup('community.general.onepassword', 'authentik_pg_password', ...) }}"
    auth_secret: "{{ lookup('community.general.onepassword', 'authentik_secret_key', ...) }}"
    ...
  roles:
    - common                      # ✅ Active: Docker + /opt directories
    # - storage                   # ⬜ Placeholder
    # - identity                  # ⬜ Placeholder
    # - apps                      # ⬜ Placeholder
```

---

## Current Common Role

### system.yml
- Installs prerequisites: `apt-transport-https`, `ca-certificates`, `curl`, `gpg`, `python3-pip`
- Passwordless sudo for `ansible_user`

### docker.yml
- Docker GPG key (official, modern DEB822 repo format)
- Installs: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`, `python3-docker`
- Docker service enabled + started
- Adds `ansible_user` to `docker` group

### directories.yml
Creates `/opt/` structure:
```
/opt/
  kopia/config/
  kopia/cache/
  authentik/
  nextcloud/html/      ← kept as-is for testing (OpenCloud vs Nextcloud TBD)
  nextcloud/db/        ← kept as-is for testing (OpenCloud vs Nextcloud TBD)
  immich/
  homeassistant/
```

---

## 1Password Integration

### Setup Status
- **Service Account:** ✅ Set up, in use daily
- **Token access:** ✅ Works on deblab (test VM)
- **Vault:** `Homelab`
- **Secrets referenced:**
  - `kopia_master_password`
  - `authentik_pg_password`
  - `authentik_secret_key`
  - `nextcloud_db_password` (may rename to `opencloud_db_password`)
  - `onlyoffice_jwt_secret` (may become unused if OnlyOffice is dropped)
  - `Debian Ansible on Laptop P14s` (test credential)

### Security
- Secrets never in plaintext — read at runtime from 1Password
- Ansible doesn't store them in logs (lookup plugin)
- `.gitignore` should exclude any `.env` or cached secret files

---

## Planned Roles (To Be Generated)

| Role | Purpose | Priority |
|------|---------|----------|
| `storage` | Kopia setup, backup scheduling, Storage Box mount | No priority — placeholders |
| `identity` | Authentik deployment (Docker Compose) | No priority — placeholders |
| `apps` | Immich, OpenCloud, Forgejo, Traefik, monitoring | No priority — placeholders |

> All roles to be generated (not written manually).

---

## Host Setup Reference

### WSL2 Method (Management Laptop)
See `Iaac/host/host-wsl2.md`:
- Install Debian in WSL2
- Enable systemd in `/etc/wsl.conf`
- Install SSH server
- Configure `.wslconfig` for mirrored networking

### Hyper-V Method (Optional Test VM)
See `Iaac/host/host-Hyper-v.md`:
- Enable Hyper-V in Windows
- Create External Virtual Switch (`DomaciBridge`)
- Debian VM with Generation 2, Secure Boot off, TPM off
- Hostname: `deblab.kogler.si`

---

## Idempotency

All scripts and playbooks are designed to be **idempotent** — safe to re-run:
- Bootstrap checks if files/keys exist before creating
- Ansible modules are naturally idempotent
- Docker install uses version-pinned repo, not latest script

---

## Next Steps

- **Storage role:** When ready to implement, the Ansible role will deploy Kopia, schedule backups, and mount Hetzner Storage Box
- **Identity + Apps roles:** Placeholders — to be generated (not written manually)