---
title: Ansible Specification
role: generation-target
domain: deployment
status: active
tags: [deployment, ansible, iac]
---
# Ansible Specification

> **Role:** ★ Generation target — read this to generate Ansible playbooks, roles, group_vars, and templates.
> **Links to:** `services.md`, `hardware.md`, `deployment-secrets.md`, `deployment-compose.md`
> **Linked from:** `deployment.md`, `index.md`

---

## Execution Modes

> **Safety guard:** `site.yml` starts with a pre-flight check that **refuses to run as `ai-debug` or any user outside `ansible_admin_users`** (`ansible-admin`, `pi`). The `common` role repeats the same assert for direct playbook/role runs. Anyone running Ansible as `ai-debug` gets an immediate abort — it must never gain sudo.

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
IaC/ansible/
├── ansible.cfg                      # SSH settings, output format
├── site.yml                         # Master playbook: imports per-group
├── inventory.ini                    # Host groups
├── test-1password.yml              # 1Password connectivity test
├── playbooks/
│   ├── router.yml                   # hosts: router → role: router
│   ├── vps.yml                      # hosts: vps → common→docker→network→docker_services→monitoring
│   ├── home_servers.yml             # hosts: home_servers → common→ai_diag→docker→network→amd_rocm→[desktop,office]→docker_services→home_assistant→monitoring
│   ├── raspberry_pi.yml             # hosts: raspberry_pi → common→network→home_assistant→monitoring
│   └── all.yml                      # Cross-cutting: /etc/hosts sync
├── group_vars/
│   ├── all.yml                      # Timezone, locale, NTP, domain names
│   ├── router.yml                   # VLAN map, WireGuard peers, DNS forwarding
│   ├── vps.yml                      # docker_services list (VPS)
│   ├── home_servers.yml             # homelab_mode, docker_services list (home), GPU config
│   └── raspberry_pi.yml             # HA install method, version
├── host_vars/
│   ├── oldsrv.kogler.si.yml         # homelab_mode=desktop, static IP
│   ├── nas.kogler.si.yml            # HP MicroServer Gen8 — ZFS storage
│   ├── vps.kogler.si.yml            # Contabo VPS — Phase 2, deferred
│   └── ha.kogler.si.yml             # Static IP, SSH user
├── roles/
│   ├── common/tasks/                # system.yml + main.yml
│   ├── docker/tasks/main.yml        # Docker CE + compose install
│   ├── network/tasks/main.yml       # VLAN interfaces, /etc/hosts
│   ├── amd_rocm/tasks/main.yml      # AMD ROCm, udev, OLLAMA_KEEP_ALIVE
│   ├── desktop/tasks/main.yml       # XFCE/GNOME, display manager, Xorg dual-GPU config
│   ├── office/tasks/main.yml        # ONLYOFFICE, MS fonts, OpenCloud client
│   ├── kopia/tasks/main.yml         # kopia-agent + kopia-server Docker containers (deployed by docker_services)
│   ├── router/tasks/main.yml        # RouterOS REST API or .rsc push
│   ├── proxmox/tasks/main.yml       # Proxmox bridges, storage, VMs (Phase 2)
│   ├── home_assistant/tasks/main.yml# HA primary (Pi) + standby (oldsrv) + keepalived VIP
│   ├── docker_services/tasks/main.yml # THE key role — generic service deployer
│   ├── monitoring/tasks/main.yml    # Alloy → Prometheus + Loki; Grafana + alerting; blackbox; HA exporter
│   └── ai_diag/                     # ai-debug diagnostics dispatcher + sudoers
│       ├── tasks/main.yml
│       └── files/ai-diag
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
router.kogler.si      ansible_user=ansible-admin

[home_servers]
oldsrv.kogler.si     ansible_user=ansible-admin homelab_mode=desktop
nas.kogler.si        ansible_user=ansible-admin

[vps]
# Deferred to Phase 2

[raspberry_pi]
ha.kogler.si          ansible_user=pi

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

---

## Host Vars

### oldsrv.kogler.si.yml
```yaml
homelab_mode: desktop            # "desktop" or "proxmox" or "headless"
ansible_host: 10.10.99.10        # Management VLAN 99 static IP
ansible_user: ansible-admin
```

### nas.kogler.si.yml
```yaml
ansible_host: 10.10.1.50           # VLAN 10 (Home) — static; Mgmt via VLAN 99 native
ansible_user: ansible-admin
```

### vps.kogler.si.yml
```yaml
ansible_host: <TBD>                # Public IP — filled when VPS is provisioned
ansible_user: ansible-admin
```

### ha.kogler.si.yml
```yaml
ansible_host: 10.10.1.122        # Home VLAN
ansible_user: pi
```

---

## Group Vars: home_servers.yml

```yaml
# All services run on oldsrv in Phase 1 — see IaC/README.md for the canonical list.
# Phase 2: public-facing services move to VPS (group_vars/vps.yml, enabled: false).
docker_services:
  - { name: traefik,        template_dir: traefik }
  - { name: crowdsec,       template_dir: crowdsec }
  - { name: authentik,      template_dir: authentik }
  - { name: opencloud,      template_dir: opencloud }
  - { name: immich-app,     template_dir: immich-app }
  - { name: forgejo,        template_dir: forgejo }
  - { name: ollama,          template_dir: ollama }
  - { name: immich-ml,       template_dir: immich-ml }
  - { name: technitium,      template_dir: technitium, enabled: "{{ inventory_hostname == 'oldsrv.kogler.si' }}" }
  - { name: technitium-secondary, template_dir: technitium, instance: secondary, enabled: "{{ inventory_hostname == 'nas.kogler.si' }}" }
  - { name: pihole,          template_dir: pihole }
  - { name: home-assistant-standby, template_dir: home-assistant-standby, enabled: "{{ inventory_hostname == 'oldsrv.kogler.si' }}" }
  - { name: headscale,       template_dir: headscale }
  - { name: kopia-server,    template_dir: kopia-server }
  - { name: db-backup,       template_dir: db-backup }
  - { name: kopia-agent,     template_dir: kopia-agent }
  - { name: grafana,         template_dir: grafana,     subdomain: stats }
  - { name: n8n,             template_dir: n8n,          subdomain: auto }
  - { name: sunshine,        template_dir: sunshine,     enabled: "{{ homelab_mode == 'desktop' }}" }
  # TODO (create templates): homepage, renovate, doco-cd, prometheus, loki, blackbox-exporter, signal-cli-rest-api

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

domain_public: kogler.si
domain_local: kogler.si
```

---

## Role Catalog

### `common`
- `tasks/system.yml`: **fail-closed guard** (asserts `ansible_user` is in `ansible_admin_users` — `ai-debug` can never run Ansible), apt update, prerequisites (`sudo`, `curl`, `python3-pip`, `openssh-server`), sudoers
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
- See [`hardware-gpu.md`](hardware-gpu.md) for dual-GPU topology

### `office`
- **Condition:** `when: homelab_mode == 'desktop'`
- **ONLYOFFICE:** Official Debian repo, `onlyoffice-desktopeditors`
- **Fonts:** `ttf-mscorefonts-installer` (EULA via `debconf`)
- **OpenCloud client:** Official sync client

### `kopia`
- Kopia runs as two Docker containers deployed by the `docker_services` role:
  - **kopia-server:** Web UI + repository server (on VPS in Phase 2, on oldsrv in Phase 1)
  - **kopia-agent:** Per-host backup agent
- The standalone `kopia` Ansible role is **not used** — Kopia backup is entirely containerized.

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
- **Alloy:** host agent (Ansible-installed, not containerized) — host metrics, container logs (`docker.sock`), SNMP scrape
- **Prometheus:** sole metrics backend, retention 30d, `db-internal`
- **Loki:** single-node/SSD log store, retention 14d
- **Grafana:** provisioned dashboards + alert rules; datasources = Prometheus + Loki; Authentik OIDC, admin-only
- **Grafana Alerting:** 3 tiers (Critical/Warning/Info), poke interval ~30 min, self-monitoring rules
- **Grafana-native SMTP:** fail-safe contact point in parallel with n8n (independent of n8n)
- **blackbox-exporter:** external reachability → `probe_success`
- **HA exporter:** enable HA `/api/prometheus` (bearer token from 1Password); Prometheus scrape job
- **SNMP:** MikroTik SNMP for traffic metrics, poll **5–15 s**
- **Alert delivery:** n8n + signal-cli-rest-api are Docker services (see `group_vars/home_servers.yml`), deployed by `docker_services` — they handle webhook routing, dedup, and Signal notification at runtime
- **Ordering:** run **after** `docker_services` (needs Prometheus/Loki/n8n up)

### `ai_diag`
- **Deploy:** `/usr/local/sbin/ai-diag` + `/etc/sudoers.d/ai-diag` (single NOPASSWD entry for `ai-debug`)
- **Deps:** smartmontools, hdparm, dmidecode, sg3-utils
- **Scope:** read-only diagnostics (SMART, ZFS, journal) — see [`deployment-secrets.md`](deployment-secrets.md); script lives in `roles/ai_diag/files/ai-diag`
- **Update:** edit the file → re-run the role

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
{{ lookup('community.general.onepassword', 'authentik_pg_password', vault='Homelab') }}
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
| 2 | `ai_diag` | `common` |
| 3 | `amd_rocm` | `common` |
| 4 | `docker_services` (core loop + systemd + templates) | `docker`, `network`, `amd_rocm` |
| 5 | `desktop` + `office` | `amd_rocm` (dual GPU Xorg) |
| 6 | `home_assistant` (Pi primary + oldsrv standby + keepalived VIP `10.10.1.122`) | `docker` |
| 7 | `monitoring` (incl. Grafana alerting rules + SMTP) | `docker_services` (Prometheus/Loki/n8n up) |
| 8 | `router` | `network` (IPs/VLANs defined) |
| 9 | `proxmox` (Phase 2) | `network` |