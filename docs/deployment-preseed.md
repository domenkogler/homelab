# Preseed & Post-Install Specification

> **Role:** ★ Generation target — read this to generate `preseed.cfg` and `post_install.sh` for Debian deployment.
> **Links to:** `hardware-gen8.md`, `hardware-debhost.md`, `network-vlans.md`, `deployment-secrets.md`
> **Linked from:** `deployment.md`, `index.md`

---

## Purpose

These two files automate a fully unattended Debian installation:

- **`preseed.cfg`** — answers all Debian installer questions (locale, partitioning, users, packages, GRUB)
- **`post_install.sh`** — runs after base install: Python, SSH key injection, sudo config for Ansible

Reference implementation: [`Iaac/host/gen8/preseed.cfg`](../../Iaac/host/gen8/preseed.cfg) and [`post_install.sh`](../../Iaac/host/gen8/post_install.sh)

---

## preseed.cfg — Required Sections

### 1. Localization
```
d-i debian-installer/locale string sl_SI.UTF-8
d-i keyboard-configuration/xkb-map select si
```

### 2. Network
```
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string <hostname>
d-i netcfg/get_domain string kogler.si
```

Hostname must match the target machine:
- `debhost` for i7-7700K ([`hardware-debhost.md`](hardware-debhost.md))
- `gen8` for HP MicroServer ([`hardware-gen8.md`](hardware-gen8.md))

### 3. Mirror
```
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
```

### 4. Partitioning

**For gen8 (single SSD boot):**
```
d-i partman-auto/disk string /dev/disk/by-id/<SSD_MODEL_SERIAL>
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
```

**For debhost (NVMe + dual drives):**
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

**For gen8 (boots from USB):**
```
d-i grub-installer/bootdev string /dev/disk/by-id/usb-<USB_SERIAL>
```

**For debhost (boots from NVMe):**
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

---

## post_install.sh — Required Steps

```bash
#!/bin/bash
# 1. Update + install Python (Ansible requirement)
apt-get update && apt-get install -y python3 python3-pip sudo openssh-server

# 2. SSH key injection for ansible-admin
mkdir -p /home/ansible-admin/.ssh
chmod 700 /home/ansible-admin/.ssh
echo "<ED25519_PUBLIC_KEY from 1Password>" >> /home/ansible-admin/.ssh/authorized_keys
chmod 600 /home/ansible-admin/.ssh/authorized_keys
chown -R ansible-admin:ansible-admin /home/ansible-admin/.ssh

# 3. Passwordless sudo for Ansible
echo "ansible-admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible-admin
chmod 0440 /etc/sudoers.d/ansible-admin

# 4. Cleanup
rm -f /tmp/post_install.sh
exit 0
```

### SSH Key

The ED25519 public key for Domen's management laptop is stored in 1Password `Homelab` vault as `admin_laptop_ssh_pubkey`. See [`deployment-secrets.md`](deployment-secrets.md).

---

## Machine-Specific Partitions

### gen8 (HP MicroServer)
- Boot: Crucial MX300 525 GB SSD (SATA)
- HDDs HGST 4TB + Seagate 4TB are ZFS — **not touched by preseed**
- SilverStone drives are ZFS-only — **not touched by preseed**
- Refer to [`hardware-gen8.md`](hardware-gen8.md) for drive details

### debhost (i7-7700K)
- OS: Samsung SSD 970 EVO 1TB (NVMe)
- Data: Samsung SSD 960 EVO 500GB (NVMe)
- Desktop environment: XFCE or GNOME (see [`hardware-debhost.md`](hardware-debhost.md))
- Additional packages for desktop: `xorg xfce4 lightdm` (or GNOME equivalent)

---

## VLAN Assignment (post-install Ansible)

Preseed uses DHCP. After boot, Ansible's `network` role assigns the correct VLAN:

| Machine | VLAN | IP |
|---------|------|-----|
| debhost | 99 (Management, native) + 10,20,50 tagged | static on VLAN 99 |
| gen8 | 10 (Home) access + 99 (Management) native | static on VLAN 10 |

Refer to [`network-vlans.md`](network-vlans.md) for the VLAN plan.

---

## Files in Repo

```
Iaac/host/
├── gen8/
│   ├── preseed.cfg          # Reference implementation for HP Gen8
│   └── post_install.sh      # Bootstrap script for ansible-admin
└── debhost/
    ├── preseed.cfg          # (to be generated)
    └── post_install.sh      # (to be generated)
```