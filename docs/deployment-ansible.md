# Ansible Specification

> **Role:** ★ Generation target — read this to generate Ansible playbooks, roles, group_vars, and templates.
> **Links to:** `services.md`, `hardware.md`, `deployment-secrets.md`, `deployment-compose.md`
> **Linked from:** `deployment.md`, `index.md`

---

## Execution Modes

### Bootstrap Mode (Domen's Laptop)
```bash
ansible-playbook site.yml -i inventory.ini
```
Used for: initial setup, new hardware, full rebuild.

### Targeted Mode
```bash
ansible-playbook site.yml --tags ollama    # Single service
ansible-playbook site.yml --tags immich-ml # GPU service
```

---

## File Layout

```
Iaac/ansible/
├── ansible.cfg                      # SSH settings, output format
├── site.yml                         # Master playbook: imports per-group
├── inventory.ini                    # Host groups
├── test-1password.yml              # 1Password connectivity test
├── playbooks/
│   ├── router.yml                   # hosts: router → role: router
│   ├── vps.yml                      # hosts: vps → common→docker→network→kopia→docker_services→monitoring
│   ├── home_servers.yml             # hosts: home_servers → common→docker→network→amd_rocm→[desktop,office]→kopia→docker_services→monitoring
│   ├── raspberry_pi.yml             # hosts: raspberry_pi → common→network→home_assistant→monitoring
│   └── all.yml                      # Cross-cutting: /etc/hosts sync
├── group_vars/
│   ├── all.yml                      # Timezone, locale, NTP, domain names
│   ├── router.yml                   # VLAN map, WireGuard peers, DNS forwarding
│   ├── vps.yml                      # docker_services list (VPS)
│   ├── home_servers.yml             # homelab_mode, docker_services list (home), GPU config
│   └── raspberry_pi.yml             # HA install method, version
├── host_vars/
│   ├── debhost.kogler.si.yml         # homelab_mode=desktop, static IP
│   └── ha-pi.kogler.si.yml          # Static IP, SSH user
├── roles/
│   ├── common/tasks/                # system.yml + main.yml
│   ├── docker/tasks/main.yml        # Docker CE + compose install
│   ├── network/tasks/main.yml       # VLAN interfaces, /etc/hosts
│   ├── amd_rocm/tasks/main.yml      # AMD ROCm, udev, OLLAMA_KEEP_ALIVE
│   ├── desktop/tasks/main.yml       # XFCE/GNOME, display manager, Xorg dual-GPU config
│   ├── office/tasks/main.yml        # ONLYOFFICE, MS fonts, OpenCloud client
│   ├── kopia/tasks/main.yml         # Kopia binary, systemd timer, S3 connect
│   ├── router/tasks/main.yml        # RouterOS REST API or .rsc push
│   ├── proxmox/tasks/main.yml       # Proxmox bridges, storage, VMs (Phase 2)
│   ├── home_assistant/tasks/main.yml# HA on Pi + cold-standby template
│   ├── docker_services/tasks/main.yml # THE key role — generic service deployer
│   └── monitoring/tasks/main.yml    # Telegraf → InfluxDB
└── templates/
    ├── docker_services/             # docker-compose.yml.j2 per service
    ├── homepage_services.yaml.j2
    ├── homepage_widgets.yaml.j2
    └── inventory.md.j2
```

---

## Inventory

```ini
[router]
rb4011.kogler.si      ansible_connection=network_cli ansible_network_os=routeros

[home_servers]
debhost.kogler.si     ansible_user=ansible-admin homelab_mode=desktop

[vps]
# Deferred to Phase 2

[raspberry_pi]
ha-pi.kogler.si       ansible_user=pi

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

---

## Host Vars

### debhost.kogler.si.yml
```yaml
homelab_mode: desktop            # "desktop" or "proxmox" or "headless"
ansible_host: 10.10.99.X         # Management VLAN static IP
```

### ha-pi.kogler.si.yml
```yaml
ansible_host: 10.10.1.122        # Home VLAN
ansible_user: pi
```

---

## Group Vars: home_servers.yml

```yaml
# Docker services deployed on home servers
docker_services:
  - { name: ollama,          template_dir: ollama }
  - { name: immich-ml,       template_dir: immich-ml }
  - { name: headscale,       template_dir: headscale }
  - { name: technitium,      template_dir: technitium }
  - { name: pihole,          template_dir: pihole }
  - { name: sunshine,        template_dir: sunshine,     enabled: "{{ homelab_mode == 'desktop' }}" }
  - { name: kopia-agent,     template_dir: kopia-agent }

# All other services: see group_vars/vps.yml (deferred)
# In Phase 1, ALL services run on debhost — see services.md

# GPU config
amd_rocm_version: "6.3"
gpu_render_group: render
gpu_video_group: video
```

---

## Group Vars: all.yml

```yaml
timezone: Europe/Ljubljana
locale: sl_SI.UTF-8
ntp_servers:
  - 0.si.pool.ntp.org
  - 1.si.pool.ntp.org

domain: kogler.si
local_domain: home.kogler.si
```

---

## Role Catalog

### `common`
- `tasks/system.yml`: apt update, prerequisites (`sudo`, `curl`, `python3-pip`, `openssh-server`), sudoers
- **Idempotency:** `state: present`, visudo validate
- **Depends on:** nothing

### `docker`
- **Repo:** DEB822 format (`deb822_repository` module), GPG key from Docker
- **Suite:** `ansible_facts['distribution_release']`
- **Post:** `systemd: name=docker state=started enabled=true`, user → `docker` group

### `network`
- **Home server:** VLAN sub-interface on trunk port, static IP
- **VPS:** Static IP on services bridge
- **Pi:** Static IP on Home VLAN
- **All:** `/etc/hosts` template with all nodes

### `amd_rocm`
- **Repo:** Official AMD ROCm (Debian-compatible path)
- **Packages:** `rocm-hip-sdk`, `rocm-opencl-sdk`
- **Groups:** `ansible_user` → `video`, `render`
- **Udev:** `/dev/kfd` mode 0666, `/dev/dri/render*` mode 0666
- **Env:** `OLLAMA_KEEP_ALIVE=5m` in `/etc/environment`
- **Condition:** `when: "'amd' in ansible_facts['gpu_vendor'] | default('')"` or hardware list

### `desktop`
- **Condition:** `when: homelab_mode == 'desktop'`
- **DM:** LightDM or GDM3 with auto-login
- **Desktop:** XFCE (preferred, lightweight)
- **Xorg:** Config in `/etc/X11/xorg.conf.d/10-igpu-primary.conf` — iGPU primary, dGPU excluded
- See [`hardware-gpu.md`](../hardware-gpu.md) for dual-GPU topology

### `office`
- **Condition:** `when: homelab_mode == 'desktop'`
- **ONLYOFFICE:** Official Debian repo, `onlyoffice-desktopeditors`
- **Fonts:** `ttf-mscorefonts-installer` (EULA via `debconf`)
- **OpenCloud client:** Official sync client

### `kopia`
- **Install:** Binary from GitHub releases (version pinned)
- **Connect:** `kopia repository connect s3 --bucket=... --access-key=...` — password from 1Password
- **Schedule:** systemd timer (`kopia-snapshot.timer`), daily 03:00
- **Policy:** Compression + encryption + 30-day retention

### `router`
- **Method:** REST API (preferred) or templated `.rsc` push
- **Configs:** VLAN interfaces, DHCP, firewall, WireGuard, CAPsMAN, DNS forwarding

### `docker_services` (Key Role)
- **Input:** `docker_services` list from group vars
- **Loop:**
  1. Skip if `enabled: false`
  2. Create `/opt/{{ item.name }}/`
  3. Template `docker-compose.yml.j2` → `/opt/{{ item.name }}/docker-compose.yml`
  4. Template extra config files from same template dir
  5. Create systemd unit: `docker-compose@{{ item.name }}.service`
  6. `systemctl enable --now docker-compose@{{ item.name }}`
- **Post-deploy:** Template Homepage config, inventory docs, reload Homepage, commit to Git
- **Tags:** Each service task tagged with `{{ item.name }}`

### `monitoring`
- **Telegraf:** All hosts → InfluxDB
- **Grafana:** Dashboard JSON provisioned
- **SNMP:** MikroTik SNMP for traffic metrics

---

## Systemd Unit Template

```ini
[Unit]
Description=Docker Compose service: %i
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/%i
ExecStart=/usr/bin/docker compose -f /opt/%i/docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f /opt/%i/docker-compose.yml down
StandardOutput=journal
User={{ ansible_user }}

[Install]
WantedBy=multi-user.target
```

---

## 1Password Secret Resolution

All secrets resolved at render time via:
```yaml
# In templates:
{{ lookup('onepassword', 'authentik_pg_password', vault='Homelab') }}
```

See [`deployment-secrets.md`](deployment-secrets.md) for the full naming convention.

---

## Idempotency

| Operation | How |
|-----------|-----|
| Package install | `state: present` — skips if installed |
| Docker repo | Checks for GPG key before download |
| Directory | `state: directory` — no-op if exists |
| systemd unit | Checks if unit file exists first |
| Docker pull | `docker compose pull` before `up` — only if digest changed |
| Templates | `force: no` — preserves local edits |

---

## Implementation Order

| Step | Role | Depends On |
|------|------|------------|
| 1 | `common` + `docker` + `network` | None |
| 2 | `router` | `network` (IPs/VLANs defined) |
| 3 | `docker_services` (core loop + systemd) | `docker`, `network` |
| 4 | Service templates (18 services) | `docker_services` |
| 5 | `kopia` | `docker` |
| 6 | `amd_rocm` | `common` |
| 7 | `desktop` + `office` | `amd_rocm` (dual GPU Xorg) |
| 8 | `home_assistant` | `docker` |
| 9 | `monitoring` | `docker_services` (InfluxDB up) |
| 10 | `proxmox` (Phase 2) | `network` |