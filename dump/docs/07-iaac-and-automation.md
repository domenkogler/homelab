# IaC & Automation

> **Canonical doc.** Based on `Iaac/` directory contents, answers from Theme F, and cross-document synthesis of the full homelab architecture.

---

## Overview

Infrastructure-as-Code via **Ansible**, secrets via **1Password**, version-controlled in **Git** (self-hosted Forgejo on VPS). Every managed node — router, VPS, home server, Raspberry Pi — is configured from a single `site.yml`.

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

### All Production Nodes

| Host | Group | IP | OS | Role |
|------|-------|----|----|------|
| `rb4011.kogler.lan` | `router` | 10.10.99.1 | RouterOS 7 | MikroTik RB4011 — VLANs, firewall, WireGuard |
| `vps.kogler.si` | `vps` | public IP | Debian + Proxmox | Traefik, Authentik, OpenCloud, Immich, Forgejo, Kopia |
| `homelab-pc.kogler.lan` | `home_servers` | 10.10.1.x | Debian (bare-metal) | Phase 1 hybrid: Docker AI host + family desktop |
| `ha-pi.kogler.lan` | `raspberry_pi` | 10.10.1.y | Raspberry Pi OS | Home Assistant |
| *(future)* `homelab-ryzen.kogler.lan` | `home_servers` | 10.10.1.z | Debian + Proxmox | Phase 2 dedicated AI server |

---

## Inventory Structure

```ini
# inventory.ini

[router]
rb4011.kogler.lan

[vps]
vps.kogler.si

[home_servers]
homelab-pc.kogler.lan          # Phase 1: bare-metal Debian desktop
# homelab-ryzen.kogler.lan     # Phase 2: Proxmox host (future)

[raspberry_pi]
ha-pi.kogler.lan

[docker_hosts:children]
vps
home_servers

[all:children]
router
vps
home_servers
raspberry_pi
```

---

## Roles (12 Total)

Each role is designed for a specific host group. Roles are idempotent and safe to re-run.

| # | Role | Applies To | Purpose |
|---|------|-----------|---------|
| 1 | **`common`** | vps, home_servers, raspberry_pi | OS updates, essential packages (`curl`, `gpg`, `python3-pip`, `git`), SSH hardening, UFW/fail2ban, timezone, locale, NTP |
| 2 | **`docker`** | docker_hosts | Docker CE + compose plugin, `daemon.json` (log rotation, live-restore), user → `docker` group, `python3-docker` for Ansible module |
| 3 | **`network`** | home_servers, vps, raspberry_pi | Static IP on correct VLAN, VLAN sub-interface on trunk port (home server), `/etc/hosts` with all host entries, MTU tuning |
| 4 | **`amd_rocm`** | home_servers | Official AMD ROCm repo, `rocm-hip-sdk`, user in `video`+`render` groups, udev rules for `/dev/kfd`+`/dev/dri`, `OLLAMA_KEEP_ALIVE=5m` in `/etc/environment` |
| 5 | **`desktop`** | home_servers (Phase 1) | XFCE or GNOME, display manager, auto-login. Xorg config ensuring Intel iGPU is primary display and AMD dGPU is excluded. Condition: `when: homelab_mode == 'desktop'` |
| 6 | **`office`** | home_servers (Phase 1) | ONLYOFFICE Desktop Editors (official repo), `ttf-mscorefonts-installer`, OpenCloud sync client. Condition: `when: homelab_mode == 'desktop'` |
| 7 | **`kopia`** | vps, home_servers | Kopia binary install, connect to iDrive e2 repo (password from 1Password), systemd timer for scheduled snapshots. Source paths defined per host |
| 8 | **`router`** | router | MikroTik RouterOS config via REST API or templated `.rsc` file. VLANs, firewall rules, DHCP servers, WireGuard peers, CAPsMAN, DNS forwarding to Technitium IP |
| 9 | **`proxmox`** | vps, home_servers (Phase 2) | Proxmox VE host config: bridges (vmbr0–vmbr4), storage pools, firewall, user management. VM/LXC provisioning. Condition: `when: homelab_mode == 'proxmox'` |
| 10 | **`home_assistant`** | raspberry_pi | HA container or supervised install, `configuration.yaml` deployment, secrets from 1Password. Also templates a cold-standby docker-compose on home_servers (disabled by default) |
| 11 | **`docker_services`** | docker_hosts | **The key role.** Reads a service list from host/group vars and deploys each one — templates `docker-compose.yml.j2` + config files, creates systemd units for boot-time start |
| 12 | **`monitoring`** | vps, home_servers, raspberry_pi | Telegraf agent → InfluxDB on VPS. Grafana dashboards provisioned on VPS. MikroTik SNMP collector config |

---

## The `docker_services` Role (Key Architecture)

This is a **single generic role** — not one per service. It iterates over a service list defined in group/host vars and deploys each identically.

### How It Works

For each service in the list:
1. Create `/opt/{{ service.name }}/` directory
2. Template `docker-compose.yml.j2` from `templates/docker_services/{{ service.template_dir }}/`
3. Template any additional config files (Traefik dynamic config, Authentik blueprint, etc.)
4. Create systemd unit `docker-compose@{{ service.name }}.service` — `WantedBy=multi-user.target` (starts at boot, before login)
5. Inject secrets from 1Password lookup at template render time
6. Run `docker compose up -d`

### Service Definitions

```yaml
# group_vars/vps.yml
docker_services:
  - name: traefik
    template_dir: traefik
  - name: crowdsec
    template_dir: crowdsec
  - name: authentik
    template_dir: authentik
  - name: opencloud
    template_dir: opencloud
  - name: immich-app
    template_dir: immich-app
  - name: forgejo
    template_dir: forgejo
  - name: grafana
    template_dir: grafana
  - name: n8n
    template_dir: n8n
  - name: kopia-server
    template_dir: kopia-server
  - name: db-backup
    template_dir: db-backup

# group_vars/home_servers.yml
docker_services:
  - name: ollama
    template_dir: ollama
  - name: immich-ml
    template_dir: immich-ml
  - name: headscale
    template_dir: headscale
  - name: technitium
    template_dir: technitium
  - name: pihole
    template_dir: pihole
  - name: sunshine
    template_dir: sunshine
    enabled: "{{ homelab_mode == 'desktop' }}"   # Phase 1 only
  - name: kopia-agent
    template_dir: kopia-agent
```

---

## Playbook Structure

```
site.yml                          # Main entry — imports per-group playbooks
playbooks/
  router.yml                      # hosts: router → role: router
  vps.yml                         # hosts: vps → common→docker→network→kopia→proxmox→docker_services→monitoring
  home_servers.yml                # hosts: home_servers → common→docker→network→amd_rocm→[desktop,office]→kopia→docker_services→monitoring
  raspberry_pi.yml                # hosts: raspberry_pi → common→network→home_assistant→monitoring
  all.yml                         # Cross-cutting: /etc/hosts sync, timezone verify

group_vars/
  all.yml                         # timezone, locale, 1Password vault name, NTP servers
  router.yml                      # RouterOS API credentials, VLAN definitions, firewall rule list
  vps.yml                         # Proxmox bridges, docker_services list, Traefik entrypoints, domain config
  home_servers.yml                # homelab_mode (desktop/proxmox), GPU config, docker_services list
  raspberry_pi.yml                # HA version, integrations secret names

host_vars/
  homelab-pc.kogler.lan.yml       # homelab_mode: desktop, static IP, MAC for DHCP reservation
  # homelab-ryzen.kogler.lan.yml  # (future) homelab_mode: proxmox
  ha-pi.kogler.lan.yml            # static IP, MAC

templates/
  docker_services/
    traefik/
      docker-compose.yml.j2
      traefik.yml.j2
      dynamic/middlewares.yml.j2
    crowdsec/
      docker-compose.yml.j2
    authentik/
      docker-compose.yml.j2
    opencloud/
      docker-compose.yml.j2
    immich-app/
      docker-compose.yml.j2
    forgejo/
      docker-compose.yml.j2
    grafana/
      docker-compose.yml.j2
    n8n/
      docker-compose.yml.j2
    kopia-server/
      docker-compose.yml.j2
    db-backup/
      docker-compose.yml.j2
    ollama/
      docker-compose.yml.j2        # GPU devices mapped, OLLAMA_KEEP_ALIVE
    immich-ml/
      docker-compose.yml.j2        # GPU devices mapped
    headscale/
      docker-compose.yml.j2
    technitium/
      docker-compose.yml.j2
    pihole/
      docker-compose.yml.j2
    sunshine/
      docker-compose.yml.j2        # GPU devices mapped
    kopia-agent/
      docker-compose.yml.j2
    home-assistant-standby/
      docker-compose.yml.j2        # Cold standby on home server
```

---

## `site.yml`

```yaml
---
- name: Configure MikroTik Router
  import_playbook: playbooks/router.yml

- name: Configure Cloud VPS
  import_playbook: playbooks/vps.yml

- name: Configure Home Servers
  import_playbook: playbooks/home_servers.yml

- name: Configure Raspberry Pi (Home Assistant)
  import_playbook: playbooks/raspberry_pi.yml

- name: Cross-Cutting Host Configuration
  import_playbook: playbooks/all.yml
```

---

## Phase 1 vs Phase 2: The `homelab_mode` Variable

| Variable | Phase 1 Value | Phase 2 Value |
|----------|--------------|--------------|
| `homelab_mode` | `desktop` | `proxmox` |

Roles use this to conditionally activate:

```yaml
# In playbooks/home_servers.yml
roles:
  - common
  - docker
  - network
  - amd_rocm
  - role: desktop
    when: homelab_mode == 'desktop'
  - role: office
    when: homelab_mode == 'desktop'
  - role: proxmox
    when: homelab_mode == 'proxmox'
  - kopia
  - docker_services
  - monitoring
```

---

## Current Common Role (Already Implemented)

### system.yml
- Installs prerequisites: `apt-transport-https`, `ca-certificates`, `curl`, `gpg`, `python3-pip`
- Passwordless sudo for `ansible_user`

### docker.yml (moves to separate `docker` role)
- Docker GPG key (official, modern DEB822 repo format)
- Installs: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`, `python3-docker`
- Docker service enabled + started
- Adds `ansible_user` to `docker` group

### directories.yml (moves to `docker_services` role)
- `/opt/` structure is now created dynamically by `docker_services` per service definition

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
  - `opencloud_db_password`
  - `immich_db_password`
  - `forgejo_db_password`
  - `grafana_admin_password`
  - `headscale_oidc_secret`
  - `Debian Ansible on Laptop P14s` (test credential)

### Security
- Secrets never in plaintext — read at runtime from 1Password
- Ansible doesn't store them in logs (lookup plugin)
- `.gitignore` excludes any `.env` or cached secret files
- Each service's `docker-compose.yml.j2` uses `lookup('community.general.onepassword', ...)` inline

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
- `docker_services` role checks if systemd unit exists before creating
- `amd_rocm` role checks if repo is already configured

---

## Key Design Decisions

| Decision | Why |
|----------|-----|
| **12 roles, not 5** | Router, VPS, Raspberry Pi, and home server are equally managed nodes. Each has distinct provisioning needs |
| **One `docker_services` role** | Avoids 15+ near-identical roles. New service = new template directory + one line in group vars |
| **`homelab_mode` variable** | Clean switch between Phase 1 (`desktop`) and Phase 2 (`proxmox`) on the same host group |
| **1Password at render time** | No secrets in vars files. `lookup('community.general.onepassword', ...)` in templates |
| **systemd for Docker containers** | Guarantees start-before-login on Phase 1 desktop. `WantedBy=multi-user.target` |
| **Router via REST API** | Idempotent, no manual `.rsc` imports. Falls back to templated `.rsc` push if API unavailable |

---

## Next Steps

1. **Split `common` role** — extract `docker` into its own role (currently both in `common`)
2. **Implement `router` role** — MikroTik REST API or `.rsc` template approach
3. **Implement `docker_services` role** — generic loop + systemd unit creation
4. **Implement `amd_rocm` role** — AMD repo, ROCm packages, udev rules
5. **Implement `desktop` + `office`** — Phase 1 family PC setup
6. **Implement `proxmox` role** — VPS Proxmox bridges + VM/LXC provisioning
7. **Implement `home_assistant` role** — Pi deployment + cold standby template
8. **Create service templates** — `docker-compose.yml.j2` for each of the ~20 services