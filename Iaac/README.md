# IaC Implementation Specification

> **Companion to `docs/` architecture docs.** This document describes HOW the Ansible infrastructure is implemented — exact file layout, role responsibilities, template paths, and build order.  
> For architectural rationale (WHY these choices), see `docs/` docs, particularly `02` (hardware), `03` (VPS), `07` (LLM), and `08` (GitOps).

---

## Repository Layout

```
./
├── Iaac/                                    # This directory — Infrastructure as Code
│   ├── README.md                            # This file
│   ├── ansible/
│   │   ├── ansible.cfg                      # SSH settings, output format
│   │   ├── site.yml                         # Master playbook — imports per-group playbooks
│   │   ├── inventory.ini                    # Host groups: router, vps, home_servers, raspberry_pi
│   │   ├── test-1password.yml               # Quick 1Password connectivity test
│   │   ├── playbooks/
│   │   │   ├── router.yml                   # hosts: router → role: router
│   │   │   ├── vps.yml                      # hosts: vps → common→docker→network→proxmox→kopia→docker_services→monitoring
│   │   │   ├── home_servers.yml             # hosts: home_servers → common→docker→network→amd_rocm→[desktop,office]→kopia→docker_services→monitoring
│   │   │   ├── raspberry_pi.yml             # hosts: raspberry_pi → common→network→home_assistant→monitoring
│   │   │   └── all.yml                      # Cross-cutting: /etc/hosts sync
│   │   ├── group_vars/
│   │   │   ├── all.yml                      # Timezone, locale, NTP, domain names
│   │   │   ├── router.yml                   # VLAN map, WireGuard peers, DNS forwarding
│   │   │   ├── vps.yml                      # docker_services list (VPS), Proxmox bridges
│   │   │   ├── home_servers.yml             # homelab_mode, docker_services list (home), GPU config
│   │   │   └── raspberry_pi.yml             # HA install method, version
│   │   ├── host_vars/
│   │   │   ├── homelab-pc.kogler.lan.yml    # Phase 1: homelab_mode=desktop, static IP
│   │   │   └── ha-pi.kogler.lan.yml         # Static IP, SSH user
│   │   ├── templates/
│   │   │   ├── docker_services/             # docker-compose.yml.j2 per service (19 services)
│   │   │   │   ├── traefik/                 #   + traefik.yml.j2, dynamic/middlewares.yml.j2
│   │   │   │   ├── crowdsec/
│   │   │   │   ├── authentik/
│   │   │   │   ├── opencloud/
│   │   │   │   ├── immich-app/
│   │   │   │   ├── forgejo/
│   │   │   │   ├── grafana/
│   │   │   │   ├── n8n/
│   │   │   │   ├── kopia-server/
│   │   │   │   ├── db-backup/
│   │   │   │   ├── renovate/
│   │   │   │   ├── homepage/
│   │   │   │   ├── ollama/
│   │   │   │   ├── immich-ml/
│   │   │   │   ├── headscale/
│   │   │   │   ├── technitium/
│   │   │   │   ├── pihole/
│   │   │   │   ├── sunshine/
│   │   │   │   ├── kopia-agent/
│   │   │   │   └── home-assistant-standby/
│   │   │   ├── homepage_services.yaml.j2    # Homepage layout (auto-generated)
│   │   │   ├── homepage_widgets.yaml.j2     # Homepage status widgets
│   │   │   └── inventory.md.j2              # Service inventory table (auto-generated)
│   │   └── roles/
│   │       ├── common/tasks/main.yml        # Calls system.yml
│   │       ├── common/tasks/system.yml      # apt update, prerequisites, sudo
│   │       ├── docker/tasks/main.yml        # Docker CE + compose, daemon.json, user group
│   │       ├── network/tasks/main.yml       # Interfaces, VLANs, /etc/hosts
│   │       ├── amd_rocm/tasks/main.yml      # AMD repo, ROCm, udev, OLLAMA_KEEP_ALIVE
│   │       ├── desktop/tasks/main.yml       # XFCE/GNOME, display manager, Xorg config
│   │       ├── office/tasks/main.yml        # ONLYOFFICE, MS fonts, OpenCloud client
│   │       ├── kopia/tasks/main.yml         # Kopia binary, systemd timer, iDrive e2 connect
│   │       ├── router/tasks/main.yml        # RouterOS REST API or .rsc push
│   │       ├── proxmox/tasks/main.yml       # Proxmox bridges, storage, VMs
│   │       ├── home_assistant/tasks/main.yml# HA on Pi + cold-standby template
│   │       ├── docker_services/tasks/main.yml # THE key role — generic service deployer
│   │       └── monitoring/tasks/main.yml    # Telegraf agents → InfluxDB
│   ├── bootstrap-ansible-client/
│   │   ├── bootstrap.sh                     # Management laptop setup
│   │   └── ansible.md                       # WSL2 Debian install guide
│   └── host/
│       ├── .wslconfig                       # Mirrored networking for WSL2
│       ├── host-wsl2.md                     # WSL2 setup instructions
│       ├── host-Hyper-v.md                  # Hyper-V test VM setup
│       └── sudo user.md                     # Post-install sudo config
│
├── docs/                                   # Architecture documentation
│   ├── 01-network-architecture.md
│   ├── 02-home-server-hardware.md
│   ├── 03-vps-infrastructure.md
│   ├── 04-vpn-and-remote-access.md
│   ├── 05-smart-home-and-voice.md
│   ├── 06-backup-and-disaster-recovery.md
│   ├── 07-local-llm-office.md
│   └── 08-gitops-operations.md
│
└── docs/family/                             # Family guides (Slovenian) — LAST PRIORITY
```

---

## Role Catalog (Implementation Details)

### `common`
- **File:** `roles/common/tasks/main.yml` → includes `system.yml`
- **Idempotency:** Package install (`state: present`), sudo file (`validate` with visudo)
- **Secrets:** None
- **Dependencies:** None

### `docker`
- **File:** `roles/docker/tasks/main.yml`
- **Key detail:** Uses DEB822 repo format (`deb822_repository` module) with GPG key from `https://download.docker.com/linux/debian/gpg`. Suite from `ansible_facts['distribution_release']`.
- **Post-install:** `systemd: name=docker state=started enabled=true`, user added to `docker` group
- **Secrets:** None

### `network`
- **File:** `roles/network/tasks/main.yml`
- **Home server (Phase 1):** Creates VLAN sub-interface on trunk port, static IP assignment
- **VPS:** Static IP on vmbr2 (Services bridge)
- **Pi:** Static IP on Home VLAN
- **All hosts:** `/etc/hosts` template with all node entries for local name resolution
- **Secrets:** None

### `amd_rocm`
- **File:** `roles/amd_rocm/tasks/main.yml`
- **Repo:** Official AMD ROCm repo (`https://repo.radeon.com/amdgpu-install/latest/ubuntu/...` — Debian-compatible path)
- **Packages:** `rocm-hip-sdk`, `rocm-opencl-sdk`
- **Groups:** `ansible_user` → `video`, `render`
- **Udev:** Rules for `/dev/kfd` (mode 0666), `/dev/dri/render*` (mode 0666)
- **Env:** `OLLAMA_KEEP_ALIVE=5m` in `/etc/environment`
- **Secrets:** None

### `desktop`
- **File:** `roles/desktop/tasks/main.yml`
- **Condition:** `when: homelab_mode == 'desktop'`
- **DM:** LightDM or GDM3 with auto-login for family user
- **Desktop:** XFCE (preferred, lightweight) or GNOME
- **Xorg:** Config fragment in `/etc/X11/xorg.conf.d/10-igpu-primary.conf` — forces Intel iGPU as primary, excludes AMD dGPU from desktop compositing
- **Secrets:** None

### `office`
- **File:** `roles/office/tasks/main.yml`
- **Condition:** `when: homelab_mode == 'desktop'`
- **ONLYOFFICE:** Official Debian repo, `onlyoffice-desktopeditors` package
- **Fonts:** `ttf-mscorefonts-installer` (accepts EULA non-interactively via `debconf`)
- **OpenCloud client:** Official client package for desktop sync
- **Secrets:** None

### `kopia`
- **File:** `roles/kopia/tasks/main.yml`
- **Install:** Kopia binary from official GitHub releases (version pinned in vars)
- **Connect:** `kopia repository connect s3 --bucket=... --access-key=...` — password from 1Password
- **Schedule:** systemd timer (`kopia-snapshot.timer`), daily at 03:00
- **Policy:** Compression + encryption + 30-day retention
- **Secrets:** `kopia_master_password` (1Password), S3 credentials

### `router`
- **File:** `roles/router/tasks/main.yml`
- **Method:** REST API (preferred) or templated `.rsc` file push
- **Configs:** VLAN interfaces, DHCP servers, firewall rules, WireGuard peers, CAPsMAN, DNS forwarding
- **Secrets:** RouterOS admin password, WireGuard keys

### `proxmox`
- **File:** `roles/proxmox/tasks/main.yml`
- **Condition:** `when: homelab_mode == 'proxmox'` (VPS always, home Phase 2)
- **Config:** Bridges (vmbr0–vmbr4), storage pools, firewall rules, user management
- **Secrets:** Proxmox root password

### `home_assistant`
- **File:** `roles/home_assistant/tasks/main.yml`
- **Pi:** Docker-based HA install (or supervised). `configuration.yaml` templated from repo
- **Cold standby:** Templates `home-assistant-standby/docker-compose.yml.j2` to `/opt/home-assistant-standby/` on home_servers. Systemd unit disabled by default — manual enable to promote
- **Secrets:** HA API keys, MQTT credentials

### `docker_services` (Key Role)
- **File:** `roles/docker_services/tasks/main.yml`
- **Input:** `docker_services` list from group vars (see below)
- **Loop logic:**
  1. For each service in `docker_services`:
     - Skip if `enabled: false`
     - Create `/opt/{{ item.name }}/`
     - Template `templates/docker_services/{{ item.template_dir }}/docker-compose.yml.j2` → `/opt/{{ item.name }}/docker-compose.yml`
     - Template any additional config files from the same template directory
     - Create systemd unit: `/etc/systemd/system/docker-compose@{{ item.name }}.service`
     - `systemctl enable --now docker-compose@{{ item.name }}`
  2. After all services deployed:
     - Template `homepage_services.yaml.j2` → write to `/opt/homepage/config/services.yaml` (on VPS)
     - Template `homepage_widgets.yaml.j2` → write to `/opt/homepage/config/widgets.yaml` (on VPS)
     - Template `inventory.md.j2` → write to `docs/inventory.md` in repo
     - Reload Homepage container
     - Commit + push updated docs to Git
- **Tag support:** Each service task is tagged with `{{ item.name }}` for targeted `--tags` execution
- **Secrets:** Per-service (via `lookup()` in templates)

### `monitoring`
- **File:** `roles/monitoring/tasks/main.yml`
- **Telegraf:** Installed on all hosts, configured to push to InfluxDB on VPS
- **Grafana:** Dashboard JSON provisioned on VPS Grafana container
- **SNMP:** MikroTik SNMP enabled for traffic metrics
- **Secrets:** InfluxDB token

---

## Service Definitions (Group Vars)

### VPS Services (`group_vars/vps.yml`)

```yaml
docker_services:
  - { name: traefik,       template_dir: traefik }
  - { name: crowdsec,      template_dir: crowdsec }
  - { name: authentik,     template_dir: authentik }
  - { name: opencloud,     template_dir: opencloud }
  - { name: immich-app,    template_dir: immich-app }
  - { name: forgejo,       template_dir: forgejo }
  - { name: grafana,       template_dir: grafana }
  - { name: n8n,           template_dir: n8n }
  - { name: kopia-server,  template_dir: kopia-server }
  - { name: db-backup,     template_dir: db-backup }
  - { name: renovate,      template_dir: renovate }
  - { name: homepage,      template_dir: homepage }
```

### Home Server Services (`group_vars/home_servers.yml`)

```yaml
docker_services:
  - { name: ollama,        template_dir: ollama }
  - { name: immich-ml,     template_dir: immich-ml }
  - { name: headscale,     template_dir: headscale }
  - { name: technitium,    template_dir: technitium }
  - { name: pihole,        template_dir: pihole }
  - { name: sunshine,      template_dir: sunshine,       enabled: "{{ homelab_mode == 'desktop' }}" }
  - { name: kopia-agent,   template_dir: kopia-agent }
```

---

## Systemd Unit Template

Each service gets a systemd unit generated from this template:

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

This ensures containers start at boot (`multi-user.target`), before any user login — critical for Phase 1 where services must run headless.

---

## Template Catalog

### docker-compose Templates (19 services)

Each template directory under `templates/docker_services/<name>/` contains:

| File | Purpose |
|------|---------|
| `docker-compose.yml.j2` | Main compose file. GPU devices mapped for ollama, immich-ml, sunshine. Secrets via `lookup()`. |
| `traefik.yml.j2` | Traefik static config (traefik only) |
| `dynamic/middlewares.yml.j2` | Authentik Forward Auth middleware (traefik only) |

### Documentation Templates

| Template | Output | Trigger |
|----------|--------|---------|
| `homepage_services.yaml.j2` | `/opt/homepage/config/services.yaml` | Post-deploy hook (on VPS) |
| `homepage_widgets.yaml.j2` | `/opt/homepage/config/widgets.yaml` | Post-deploy hook (on VPS) |
| `inventory.md.j2` | `docs/inventory.md` in repo | Post-deploy hook |

---

## 1Password Secret Naming Convention

All secrets live in the `Homelab` vault. Naming pattern: `<service>_<secret_type>`.

| Secret Name | Used By |
|-------------|---------|
| `kopia_master_password` | kopia role, kopia-agent, kopia-server |
| `authentik_pg_password` | authentik |
| `authentik_secret_key` | authentik |
| `opencloud_db_password` | opencloud |
| `immich_db_password` | immich-app |
| `forgejo_db_password` | forgejo |
| `grafana_admin_password` | grafana |
| `headscale_oidc_secret` | headscale |
| `ha_api_key` | home_assistant |
| `influxdb_token` | monitoring |
| `router_admin_password` | router |
| `wireguard_private_key` | router, proxmox (S2S) |

---

## Implementation Order

Roles and templates must be built in this sequence — each step depends on the previous:

| Step | What | Depends On | Estimated Effort |
|------|------|------------|-----------------|
| 1 | `common` + `docker` + `network` roles | None — base OS | ✅ Done (deblab tested) |
| 2 | `router` role | `network` (IPs/VLANs defined) | Medium |
| 3 | `docker_services` role (core loop + systemd) | `docker`, `network` | Medium |
| 4 | VPS service templates (traefik, authentik, opencloud, immich-app, forgejo, grafana, n8n, crowdsec, kopia-server, db-backup) | `docker_services` | Large |
| 5 | `proxmox` role | `network` | Medium |
| 6 | `kopia` role | `docker` | Small |
| 7 | `amd_rocm` role | `common` | Small |
| 8 | Home server service templates (ollama, immich-ml, headscale, technitium, pihole, sunshine, kopia-agent) | `docker_services`, `amd_rocm` | Medium |
| 9 | `desktop` + `office` roles | `amd_rocm` (dual GPU Xorg config) | Medium |
| 10 | `home_assistant` role (Pi + cold standby) | `docker` | Small |
| 11 | `monitoring` role | `docker_services` (InfluxDB on VPS) | Small |
| 12 | Renovate + Homepage templates | `docker_services` | Small |
| 13 | Post-deploy hooks (Homepage config + inventory generation) | `docker_services`, `homepage` template | Medium |
| 14 | Forgejo Actions workflow (`.forgejo/workflows/deploy.yml`) | All roles functional | Small |
| 15 | End-to-end test: Renovate → PR → Actions → Deploy | Everything above | Medium |

---

## Two Execution Modes

### Bootstrap Mode (Domen's Laptop)

```bash
# Full provisioning — new nodes or disaster recovery
source ~/.bashrc
ansible-playbook site.yml -i inventory.ini
```

Used for: initial setup, adding new hardware, full rebuild after catastrophic failure.

### Production Mode (Forgejo Actions)

```
Forgejo UI → Actions tab → "Manual Infrastructure Deploy"
  → Enter tag: "immich"
  → Click "Run workflow"
```

Used for: day-to-day container updates after Renovate PR merge.

The same playbook and roles serve both modes. Tags enable targeted execution:

```bash
# Equivalent CLI (what Actions runs internally):
ansible-playbook main_deploy.yml --tags immich
```

---

## Idempotency Guarantees

| Operation | How |
|-----------|-----|
| Package install | `state: present` (apt module) — skips if installed |
| Docker repo | Checks if `.asc` key exists before downloading |
| Directory creation | `state: directory` — no-op if exists |
| systemd unit | Checks if unit file exists before creating |
| Docker pull | `docker compose pull` before `up` — only pulls if digest changed |
| 1Password secrets | Lookup at render time — never cached |
| File templates | `force: no` on config files — preserves local edits if desired |

---

> **Cross-references:**
> - Architecture decisions (why 12 roles, why systemd): see `docs/` docs
> - GitOps operations (Renovate, Actions, Homepage): see `docs/08-gitops-operations.md`
> - Hardware context (GPU, Phase 1 vs 2): see `docs/02-home-server-hardware.md`
> - VPS service context: see `docs/03-vps-infrastructure.md`