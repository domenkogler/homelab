# IaC Implementation Specification

> **Companion to `docs/` architecture docs.** This document describes HOW the Ansible infrastructure is implemented — exact file layout, role responsibilities, template paths, and build order.
> For architectural rationale (WHY these choices), see `docs/` — in particular `hardware.md`, `services.md`, `observability.md`, and `deployment.md`.

## Hostname / Domain Convention

Single namespace **`kogler.si`** — hosts and services use flat subdomains of `kogler.si`.
Internal-only hosts/services are **not** published in public DNS (split-horizon; enforced by WAN firewall).

| Machine | FQDN | Role |
|---------|------|------|
| Old desktop + Docker host | `oldsrv.kogler.si` | bare-metal Debian desktop + Docker host (Phase 1) |
| HP MicroServer NAS | `nas.kogler.si` | ZFS storage server |
| Raspberry Pi 4 | `ha.kogler.si` | Home Assistant |
| MikroTik Router | `router.kogler.si` | PPPoE, VLAN routing, firewall, WireGuard, CAPsMAN |
| MikroTik Switch | `switch.kogler.si` | Layer-2 VLAN-aware PoE switch |
| Contabo VPS | `vps.kogler.si` | Phase 2 — public Traefik + public services |

Local DNS (Technitium) resolves `*.kogler.si` to internal IPs; TLS via a single `*.kogler.si`
wildcard certificate issued with Cloudflare **DNS-01** (Cloudflare = DNS-only, no proxy).

---

## Repository Layout

```
./
├── IaC/                                    # Infrastructure as Code
│   ├── README.md                           # This file
│   ├── ansible/
│   │   ├── ansible.cfg                     # SSH settings, output format
│   │   ├── site.yml                        # Master playbook — imports per-group playbooks
│   │   ├── inventory.ini                   # Host groups: router, vps, home_servers, raspberry_pi
│   │   ├── test-1password.yml              # Quick 1Password connectivity test
│   │   ├── playbooks/
│   │   │   ├── router.yml                  # hosts: router → role: router
│   │   │   ├── vps.yml                     # hosts: vps → common→docker→network→proxmox→kopia→docker_services→monitoring
│   │   │   ├── home_servers.yml            # hosts: home_servers → common→ai_diag→docker→network→amd_rocm→[desktop,office]→kopia→docker_services→home_assistant→monitoring
│   │   │   ├── raspberry_pi.yml            # hosts: raspberry_pi → common→network→home_assistant→monitoring
│   │   │   └── all.yml                     # Cross-cutting: /etc/hosts sync
│   │   ├── group_vars/
│   │   │   ├── all.yml                     # Timezone, locale (sl_SI.UTF-8), NTP, domain kogler.si
│   │   │   ├── router.yml                  # VLAN map (10/20/21/30/40/50/99), WireGuard, DNS
│   │   │   ├── vps.yml                     # docker_services list (VPS, Phase 2)
│   │   │   ├── home_servers.yml            # homelab_mode, docker_services list (home), GPU config
│   │   │   └── raspberry_pi.yml            # HA install method, version
│   │   ├── host_vars/
│   │   │   ├── oldsrv.kogler.si.yml        # Phase 1: homelab_mode=desktop, static IP
│   │   │   └── ha.kogler.si.yml            # Static IP, SSH user
│   │   ├── templates/
│   │   │   ├── docker_services/            # docker-compose.yml.j2 per service (canonical list = docs/services.md)
│   │   │   │   ├── traefik/                #   + traefik.yml.j2, dynamic/middlewares.yml.j2
│   │   │   │   ├── crowdsec/
│   │   │   │   ├── authentik/
│   │   │   │   ├── opencloud/
│   │   │   │   ├── immich-app/
│   │   │   │   ├── forgejo/
│   │   │   │   ├── grafana/
│   │   │   │   ├── n8n/
│   │   │   │   ├── kopia-server/
│   │   │   │   ├── db-backup/
│   │   │   │   ├── ollama/
│   │   │   │   ├── immich-ml/
│   │   │   │   ├── headscale/
│   │   │   │   ├── technitium/
│   │   │   │   ├── pihole/
│   │   │   │   ├── sunshine/
│   │   │   │   ├── kopia-agent/
│   │   │   │   └── home-assistant-standby/
│   │   │   │   # TODO (create): homepage/, renovate/ — services in docs/services.md
│   │   │   ├── homepage_services.yaml.j2    # Homepage layout (auto-generated)
│   │   │   ├── homepage_widgets.yaml.j2     # Homepage status widgets
│   │   │   └── inventory.md.j2              # Service inventory table (auto-generated)
│   │   └── roles/
│   │       ├── common/tasks/{main,system}.yml  # fail-closed admin guard, apt, sudo
│   │       ├── docker/tasks/main.yml        # Docker CE + compose, daemon.json, user group
│   │       ├── network/tasks/main.yml       # VLAN interfaces, /etc/hosts
│   │       ├── amd_rocm/tasks/main.yml      # AMD ROCm, udev, OLLAMA_KEEP_ALIVE
│   │       ├── desktop/tasks/main.yml       # XFCE/GNOME, display manager, Xorg dual-GPU config
│   │       ├── office/tasks/main.yml        # ONLYOFFICE, MS fonts, OpenCloud client
│   │       ├── kopia/tasks/main.yml         # Kopia binary, systemd timer, iDrive e2 connect
│   │       ├── router/tasks/main.yml        # RouterOS REST API or .rsc push
│   │       ├── proxmox/tasks/main.yml       # Proxmox bridges, storage, VMs (Phase 2)
│   │       ├── home_assistant/tasks/main.yml# HA on Pi (OIDC SSO w/ Authentik) + cold-standby
│   │       ├── docker_services/tasks/main.yml # THE key role — generic service deployer
│   │       ├── monitoring/tasks/main.yml    # Alloy → Prometheus + Loki; Grafana; blackbox; HA exporter
│   │       ├── alerting/tasks/main.yml      # Grafana Alerting → n8n → Signal/email; self-monitoring
│   │       └── ai_diag/                     # ai-debug diagnostics dispatcher + sudoers
│   │           ├── tasks/main.yml
│   │           └── files/ai-diag
│   ├── bootstrap-ansible-client/
│   │   ├── bootstrap.sh                     # Management laptop setup
│   │   └── ansible.md                       # WSL2 Debian install guide
│   ├── host/
│   │   ├── post_install.sh                 # SHARED bootstrap: ansible-admin + ai-debug + sshd hardening
│   │   ├── nas/                            # preseed.cfg for nas.kogler.si (HP MicroServer)
│   │   ├── .wslconfig                       # Mirrored networking for WSL2
│   │   ├── host-wsl2.md                     # WSL2 setup instructions
│   │   ├── host-Hyper-v.md                  # Hyper-V test VM setup
│   │   └── sudo user.md                     # Post-install sudo config
│   └── router/
│       ├── rb4011_initial.rsc               # Router baseline (router.kogler.si, VLAN 10/20/21/30/40/50/99, CAPsMAN)
│       └── ap_initial.rsc                   # CAP-mode AP config
│
├── docs/                                   # Architecture documentation (canonical)
├── manual/                                 # Family guides (Slovenian) — see docs/manual/
└── README.md                               # Repo root (you are here)
```

> **Note:** `docs/` and `manual/` are the canonical, currently maintained documentation. This file documents the *intended* IaC implementation. Missing templates (homepage, renovate) and role stubs (TODO) are created as services are deployed.

---

## Role Catalog (Implementation Details)

### `common`
- **Files:** `tasks/main.yml` → includes `tasks/system.yml`
- **Fail-closed guard:** asserts `ansible_user` is in `ansible_admin_users` — `ai-debug` can **never** run Ansible or receive sudo.
- **Idempotency:** package install (`state: present`), sudo file (`validate` with visudo)
- **Secrets:** None

### `docker`
- **File:** `roles/docker/tasks/main.yml`
- Docker CE via DEB822 repo format (`deb822_repository`), GPG key from `https://download.docker.com/linux/debian/gpg`; suite from `ansible_facts['distribution_release']`.
- **Post-install:** `systemd: name=docker state=started enabled=true`, admin user → `docker` group
- **Secrets:** None

### `network`
- **Home server (Phase 1):** VLAN sub-interface on trunk port, static IP (VLAN 99 for oldsrv, VLAN 10 + 99 native for nas)
- **VPS:** Static IP on services bridge
- **Pi:** Static IP on Home VLAN
- **All hosts:** `/etc/hosts` template with all node entries (resolved via local DNS)

### `amd_rocm`
- Official AMD ROCm repo (Debian-compatible path); packages `rocm-hip-sdk`, `rocm-opencl-sdk`
- Groups: `ansible_user` → `video`, `render`; udev rules for `/dev/kfd` (0666) + `/dev/dri/render*` (0666)
- Env: `OLLAMA_KEEP_ALIVE=5m` in `/etc/environment`
- Condition: `when: "'amd' in ansible_facts['gpu_vendor'] | default('')"` or hardware list

### `desktop`
- Condition: `when: homelab_mode == 'desktop'`
- DM: LightDM/GDM3 with auto-login (family user); Desktop: XFCE (preferred) or GNOME
- Xorg fragment `/etc/X11/xorg.conf.d/10-igpu-primary.conf` — iGPU primary, dGPU excluded
- See `docs/hardware-gpu.md`

### `office`
- Condition: `when: homelab_mode == 'desktop'`
- ONLYOFFICE Desktop Editors, `ttf-mscorefonts-installer` (EULA via debconf), OpenCloud client

### `kopia`
- Binary from GitHub releases (version pinned); `kopia repository connect s3` (iDrive e2) — password from 1Password
- systemd timer (`kopia-snapshot.timer`) daily 03:00; compression + encryption + 30-day retention
- Secrets: `kopia_master_password`, S3 credentials (1Password)

### `router`
- Method: REST API (preferred) or templated `.rsc` push
- Configs: VLAN interfaces (10/20/21/30/40/50/99), DHCP, firewall, WireGuard, CAPsMAN (SSIDs incl. `Kogler IOT WAN`), DNS forwarding
- Secrets: RouterOS admin password, WireGuard keys

### `proxmox`
- Condition: `when: homelab_mode == 'proxmox'` (home Phase 2 only — not on Contabo VPS)
- Bridges (vmbr0–vmbr4), storage, firewall; Secrets: Proxmox root password

### `home_assistant`
- Pi: Docker-based HA (or supervised). **HA web login = Authentik SSO via native OIDC**; Companion/API = HA long-lived token. **No Authentik Forward-Auth on the `ha` route.**
- `configuration.yaml` templated from repo (`use_x_forwarded_for: true`, `trusted_proxies: <Traefik>`).
- Cold standby: `home-assistant-standby/docker-compose.yml.j2` → `/opt/home-assistant-standby/` on home_servers; systemd unit disabled by default
- Secrets: HA API keys, MQTT credentials

### `docker_services` (Key Role)
- **Input:** `docker_services` list from group vars
- **Loop:** skip if `enabled: false` → create `/opt/<service>/` → template `docker-compose.yml.j2` → template extra configs → create `docker-compose@<service>.service` → `systemctl enable --now`
- **Post-deploy:** template Homepage config + inventory docs, reload Homepage, commit+push to Git
- **Tags:** each service task tagged `{{ item.name }}` for targeted `--tags`

### `monitoring`
- **Alloy:** host agent (Ansible-installed, not containerized) — host metrics, container logs (`docker.sock`), SNMP; remote-write → Prometheus, logs → Loki
- **Prometheus:** sole metrics store, 30 d retention, `db-internal`
- **Loki:** single-node/SSD log store, 14 d retention
- **Grafana:** provisioned dashboards; datasources = Prometheus + Loki; Authentik OIDC; **admin-only, internal** (`stats.kogler.si`)
- **blackbox-exporter:** external reachability → `probe_success`
- **HA exporter:** HA `/api/prometheus` (bearer token from 1Password); Prometheus scrape
- **SNMP:** MikroTik poll 5–15 s
- **Ordering:** after `docker_services`
- **Secrets:** `ha_exporter_token`, `grafana_admin_password`, `grafana_smtp_password`

### `alerting`
- Grafana Unified Alerting → n8n webhook → Signal + email (Grafana-native SMTP fail-safe in parallel)
- Tiers Critical/Warning/Info; ~30 min poke; self-monitoring rules
- `signal-cli-rest-api` linked to personal device → "Homelab Alerts" group
- **Ordering:** after `monitoring`

### `ai_diag`
- `/usr/local/sbin/ai-diag` + `/etc/sudoers.d/ai-diag` (single NOPASSWD entry for `ai-debug`)
- Deps: smartmontools, hdparm, dmidecode, sg3-utils; read-only SMART/ZFS/journal diagnostics + smart tests
- Update: edit `roles/ai_diag/files/ai-diag` → re-run role

---

## Service Definitions (Group Vars)

### Home Server Services (`group_vars/home_servers.yml`)

```yaml
docker_services:
  - { name: ollama,          template_dir: ollama }
  - { name: immich-ml,       template_dir: immich-ml }
  - { name: headscale,       template_dir: headscale }
  - { name: technitium,      template_dir: technitium }
  - { name: pihole,          template_dir: pihole }
  - { name: sunshine,        template_dir: sunshine,       enabled: "{{ homelab_mode == 'desktop' }}" }
  - { name: kopia-agent,     template_dir: kopia-agent }
```

> **Canonical catalog:** all services (incl. Traefik, Authentik, Immich, OpenCloud, Forgejo, Grafana,
> Homepage, Renovate, n8n, Doco-CD …) are defined in `docs/services.md`. In Phase 1 **all** run on
> `oldsrv.kogler.si`; public-facing ones move to `vps.kogler.si` (Traefik) in Phase 2.

### VPS Services (`group_vars/vps.yml`) — Phase 2, reference only

```yaml
docker_services:
  - { name: traefik,        template_dir: traefik }
  - { name: crowdsec,       template_dir: crowdsec }
  - { name: authentik,      template_dir: authentik }
  - { name: opencloud,      template_dir: opencloud }
  - { name: immich-app,     template_dir: immich-app }
  - { name: forgejo,        template_dir: forgejo }
  - { name: grafana,        template_dir: grafana }
  - { name: n8n,            template_dir: n8n }
  - { name: kopia-server,   template_dir: kopia-server }
  - { name: db-backup,      template_dir: db-backup }
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

This ensures containers start at boot (`multi-user.target`), before any user login —
critical for Phase 1 where services must run headless.

---

## DNS / TLS Model

- **Local DNS:** Technitium (on `oldsrv`) is the central DNS router/resolver. DHCP clients point at the router;
  router forwards to Technitium (fallback `1.1.1.1`). Technitium answers `*.kogler.si` internally.
- **Public DNS:** Cloudflare (registry registrar: **domenca.com**) publishes only the internet-facing subset
  (`kogler.si`, `foto`, `file`, `git`, `sso`, `ha`). **No proxy** — DNS-only, real client IPs reach Traefik.
- **Certificates:** single `*.kogler.si` wildcard via ACME **DNS-01** with a Cloudflare API token (1Password `Homelab`).

---

## 1Password Secret Naming Convention

All secrets live in the `Homelab` vault. Naming pattern: `<service>_<secret_type>`.
See `docs/deployment-secrets.md` for the full list (including `cloudflare_api_token`).

| Secret Name | Used By |
|-------------|---------|
| `kopia_master_password` | kopia role, kopia-agent, kopia-server |
| `authentik_pg_password`, `authentik_secret_key` | authentik |
| `opencloud_db_password`, `immich_db_password`, `forgejo_db_password` | platform DBs |
| `grafana_admin_password`, `grafana_smtp_password` | grafana |
| `headscale_oidc_secret` | headscale |
| `ha_api_key`, `ha_exporter_token` | home_assistant / monitoring |
| `cloudflare_api_token` | ACME DNS-01 wildcard cert |
| `router_admin_password`, `wireguard_private_key` | router |

---

## Implementation Order

| Step | What | Depends On |
|------|------|------------|
| 1 | `common` + `docker` + `network` roles | None — base OS |
| 2 | `router` role (+ `.rsc`) | `network` (IPs/VLANs defined) |
| 3 | `docker_services` role (core loop + systemd) | `docker`, `network` |
| 4 | Home-server service templates | `docker_services`, `amd_rocm` |
| 5 | `kopia` role | `docker` |
| 6 | `amd_rocm` role | `common` |
| 7 | `desktop` + `office` roles | `amd_rocm` (dual-GPU Xorg) |
| 8 | `home_assistant` role (Pi + cold standby) | `docker` |
| 9 | `monitoring` role | `docker_services` |
| 10 | `alerting` role | `monitoring` |
| 11 | `proxmox` (Phase 2) | `network` |
| 12 | Renovate + Homepage templates | `docker_services` |
| 13 | Post-deploy hooks (Homepage + inventory) | `docker_services` |
| 14 | Forgejo Actions workflow (`.forgejo/workflows/deploy.yml`) | all roles |
| 15 | End-to-end test: Renovate → PR → Actions → Deploy | everything |

---

## Two Execution Modes

### Bootstrap Mode (Domen's Laptop)

```bash
source ~/.bashrc
ansible-playbook site.yml -i inventory.ini
```

### Production Mode (Forgejo Actions)

Forgejo UI → Actions → "Manual Infrastructure Deploy" → tag (e.g. `immich`) → Run workflow.
Equivalent CLI: `ansible-playbook site.yml --tags immich`.

---

## Idempotency Guarantees

| Operation | How |
|-----------|-----|
| Package install | `state: present` — skips if installed |
| Docker repo | checks GPG key before download |
| Directory creation | `state: directory` — no-op |
| systemd unit | checks existence first |
| Docker pull | `docker compose pull` before `up` — only on digest change |
| 1Password secrets | lookup at render time — never cached |
| File templates | `force: no` where local edits should be preserved |

---

> **Cross-references:**
> - Architecture & rationale: `docs/hardware.md`, `docs/services.md`, `docs/observability.md`, `docs/deployment.md`
> - VLAN plan: `docs/network-vlans.md` · DNS: `docs/network-dns.md` · VPN: `docs/network-vpn.md`
> - Secrets: `docs/deployment-secrets.md` · Service catalog: `docs/services.md`
