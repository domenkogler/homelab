---
title: Preseed & Post-Install Specification
role: design-spec
domain: deployment
status: active
tags: [deployment, preseed, debian]
---
# Preseed & Post-Install Specification

> **Role:** ★ Design spec — read this to **author or correct** `preseed.cfg` and
> `post_install.sh` for Debian deployment. The reference implementations in
> `IaC/host/` are the source of truth; this doc describes what they must contain.
> **Links to:** `hardware-nas.md`, `hardware-oldsrv.md`, `network-vlans.md`, `deployment-secrets.md`
> **Linked from:** `deployment.md`, `index.md`

---

## Purpose

These two files automate a fully unattended Debian installation:

- **`preseed.cfg`** — answers all Debian installer questions (locale, partitioning, users, packages, GRUB)
- **`post_install.sh`** — runs after base install: Python, SSH key injection, sudo config for Ansible

Reference implementation: [`IaC/host/nas/preseed.cfg`](../../IaC/host/nas/preseed.cfg) and the **shared** [`IaC/host/post_install.sh`](../../IaC/host/post_install.sh) — one copy for all hosts.

---

## preseed.cfg — Required Sections

### 1. Localization
```
d-i debian-installer/locale string sl_SI.UTF-8
d-i keyboard-configuration/xkb-keymap select si
```

### 2. Network
```
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string <hostname>
d-i netcfg/get_domain string kogler.si
```

Hostname must match the target machine:
- `oldsrv` for i7-7700K ([`hardware-oldsrv.md`](hardware-oldsrv.md))
- `nas` for HP MicroServer ([`hardware-nas.md`](hardware-nas.md))
- `pi` for Raspberry Pi 4 (HA primary node — preseed-installed like nas/oldsrv, no desktop/Cockpit; its `preseed.cfg` is deferred like oldsrv)

### 3. Mirror
```
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
```

### 4. Partitioning

**For nas (single SSD boot):**
```
d-i partman-auto/disk string /dev/disk/by-id/<SSD_MODEL_SERIAL>
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
```

**For oldsrv (NVMe + dual drives):**
- OS on NVMe 1 (`Samsung SSD 970 EVO 1TB`)
- Data on NVMe 2 (`Samsung SSD 960 EVO 500GB`)
- Use `/dev/disk/by-id/nvme-*` paths

### 5. Users

**Root account:**
```
d-i passwd/root-login boolean true
d-i passwd/root-password-crypted password <SHA-512_HASH>
```

Generate hash with: `mkpasswd -m sha-512`

**Ansible admin user (passwordless — SSH key only):**
```
d-i passwd/user-fullname string Ansible Automation Account
d-i passwd/username string ansible-admin
d-i passwd/user-password-crypted password !
```

### 6. Packages
```
tasksel tasksel/first multiselect standard, ssh-server
d-i pkgsel/include string sudo curl
d-i pkgsel/upgrade select safe-upgrade
```

### 7. GRUB

**For nas (boots from USB):**
```
d-i grub-installer/bootdev string /dev/disk/by-id/usb-<USB_SERIAL>
```

**For oldsrv (boots from NVMe):**
```
d-i grub-installer/bootdev string /dev/disk/by-id/nvme-<NVME_SERIAL>
```

### 8. Late Command
```
d-i preseed/late_command string \
    cp /cdrom/preseed/post_install.sh /target/tmp/post_install.sh; \
    chmod 755 /target/tmp/post_install.sh; \
    in-target /bin/bash /tmp/post_install.sh
```

> **Media layout:** when assembling the install media, place the shared `post_install.sh` where the late_command expects it (`preseed/post_install.sh` on the media), alongside the per-host `preseed.cfg`.

---

## post_install.sh — Required Steps

```bash
#!/bin/bash
set -euo pipefail

# 1. Python (Ansible requirement)
apt-get update && apt-get install -y python3 python3-pip sudo openssh-server

# 2. ansible-admin (created by preseed) — personal + Ansible keys
mkdir -p /home/ansible-admin/.ssh && chmod 700 /home/ansible-admin/.ssh
echo "ssh-ed25519 <PERSONAL_PUBKEY_FROM_1PASSWORD> admin@laptop" >> /home/ansible-admin/.ssh/authorized_keys
echo "ssh-ed25519 <ANSIBLE_PUBKEY_FROM_1PASSWORD> ansible"       >> /home/ansible-admin/.ssh/authorized_keys
chmod 600 /home/ansible-admin/.ssh/authorized_keys
chown -R ansible-admin:ansible-admin /home/ansible-admin/.ssh
echo "ansible-admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible-admin
chmod 0440 /etc/sudoers.d/ansible-admin

# 3. ai-debug user — AI debugging only, NO sudo
useradd -m -s /bin/bash ai-debug
mkdir -p /home/ai-debug/.ssh && chmod 700 /home/ai-debug/.ssh
echo 'restrict,no-agent-forwarding,no-port-forwarding,no-X11-forwarding,from="10.10.0.0/16" ssh-ed25519 <AI_PUBKEY_FROM_1PASSWORD> openrouter_ai' \
  >> /home/ai-debug/.ssh/authorized_keys
chmod 600 /home/ai-debug/.ssh/authorized_keys
chown -R ai-debug:ai-debug /home/ai-debug/.ssh

# 4. sshd hardening (all homelab hosts)
cat >> /etc/ssh/sshd_config <<'EOF'
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
LogLevel VERBOSE
AllowUsers ansible-admin ai-debug
EOF
systemctl restart ssh

# 5. Cleanup
rm -f /tmp/post_install.sh
exit 0
```

### SSH Keys — three keys, injected at generation time

Public keys are fetched from 1Password `Homelab` vault by the AI when generating the real `post_install.sh` — **the repo only ever contains placeholders**. The same three keys are authorized on **every** homelab host (nas, oldsrv, ...). There is a **single shared `post_install.sh`** in `IaC/host/` — no per-host copies to drift.

| Key (1Password item) | Authorized user | Access |
|----------------------|-----------------|--------|
| `admin_laptop_ssh_pubkey` | `ansible-admin` | Full (NOPASSWD sudo) |
| `ssh_ansible_pubkey` | `ansible-admin` | Full (NOPASSWD sudo) |
| `ssh_ai_pubkey` | `ai-debug` | Debug only — no sudo, LAN-only, no forwarding |

**The AI key must never be authorized for `ansible-admin`** — that user has passwordless root.

See [`deployment-secrets.md`](deployment-secrets.md) for the laptop `~/.ssh/config` and 1Password SSH agent setup.

> **Note:** AI hardware diagnostics (`sudo ai-diag ...`) are deployed by the `ai_diag` Ansible role on the first playbook run — not by post_install. See [`deployment-ansible.md`](deployment-ansible.md).

---

## Machine-Specific Partitions

### nas (HP MicroServer)
- Boot: Crucial MX300 525 GB SSD (SATA)
- HDDs HGST 4TB + Seagate 4TB are ZFS — **not touched by preseed**
- SilverStone drives are ZFS-only — **not touched by preseed**
- Refer to [`hardware-nas.md`](hardware-nas.md) for drive details

### oldsrv (i7-7700K)
- OS: Samsung SSD 970 EVO 1TB (NVMe)
- Data: Samsung SSD 960 EVO 500GB (NVMe)
- Desktop environment: XFCE or GNOME (see [`hardware-oldsrv.md`](hardware-oldsrv.md))
- Additional packages for desktop: `xorg xfce4 lightdm` (or GNOME equivalent)

---

## VLAN Assignment (post-install Ansible)

Preseed uses DHCP. After boot, Ansible's `network` role assigns the correct VLAN:

| Machine | VLAN | IP |
|---------|------|-----|
| oldsrv | 99 (Management, native) + 10,20,50 tagged | static on VLAN 99 |
| nas | 10 (Home) access + 99 (Management) native | static on VLAN 10 |
| pi | 10 (Home) access | static on VLAN 10 (`10.10.1.20`) |

Refer to [`network-vlans.md`](network-vlans.md) for the VLAN plan.

---

## Files in Repo

```
IaC/host/
├── post_install.sh         # SHARED bootstrap — ansible-admin + ai-debug + sshd hardening (single copy for all hosts)
└── nas/
    └── preseed.cfg          # Reference implementation for HP Gen8

# oldsrv/preseed.cfg — deferred, not yet created (generated from this spec when Phase 1 deployment begins)
# pi/preseed.cfg — deferred, not yet created (same preseed path as nas/oldsrv; headless, no desktop/Cockpit)
```