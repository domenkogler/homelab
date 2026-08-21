# IaC Implementation Specification

> **Companion to `docs/` architecture docs.** This document describes HOW the Ansible infrastructure is implemented — exact file layout, role responsibilities, template paths, and build order.
> For architectural rationale (WHY these choices), see `docs/` — in particular `hardware.md`, `services.md`, `observability.md`, and `deployment.md`.

## Implementation Status

| Component | Implemented | Stubs / TODO |
|-----------|-------------|--------------|
| Ansible roles | `common`, `docker`, `ai_diag`, `nut`, `cockpit`, `network` (foundation), `storage`, `router`, `switch` (HD-03), `home_assistant`, `docker_services` (HD-50), `monitoring`, `amd_rocm`, `desktop`, `office`, `cifs`, `cloudflare_dns`, `wireguard` (18) | `proxmox` (1, TODO) |
| Docker compose templates | 49 templates implemented (HD-01) — see `templates/docker_services/` | — |
| RouterOS scripts | `rb4011_initial.rsc`, `ap_initial.rsc` (2) | — |
| Bootstrap | `bootstrap.sh`, `post_install.sh`, `pi/first-boot-config.sh` (3) | — |

> `network` role: static-IP + VLAN trunk provisioning is a scoped TODO until the host network config manager (systemd-networkd vs netplan) is decided — see `roles/network/tasks/main.yml`.
> `network` role: static-IP + VLAN trunk provisioning is a scoped TODO until the host network config manager (systemd-networkd vs netplan) is decided — see `roles/network/tasks/main.yml`.

## Hostname / Domain Convention

Single namespace **`kogler.si`** — hosts and services use flat subdomains of `kogler.si`.
Internal-only hosts/services are **not** published in public DNS (split-horizon; enforced by WAN firewall).

Canonical host list + naming rules: **[`docs/index.md` → Conventions](../docs/index.md)** (single SSOT).

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
│   │   ├── inventory.ini                   # Host groups: router, vps, home_servers (oldsrv), storage (nas), raspberry_pi
│   │   ├── test-1password.yml              # Quick 1Password connectivity test
│   │   ├── playbooks/
│   │   │   ├── router.yml                  # hosts: router → role: router
│   │   │   ├── vps.yml                     # hosts: vps → common→docker→network→docker_services→monitoring
│   │   │   ├── home_servers.yml            # hosts: home_servers (oldsrv) → common→ai_diag→docker→network→storage→nut→amd_rocm→[desktop,office]→docker_services→home_assistant→monitoring
│   │   │   ├── storage.yml                 # hosts: storage (nas) → common→ai_diag→network→storage→nut→cockpit  (ZFS, NO Docker)
│   │   │   ├── raspberry_pi.yml            # hosts: raspberry_pi → common→network→nut→docker→home_assistant→docker_services→monitoring
│   │   │   ├── all.yml                     # Cross-cutting: /etc/hosts sync
│   │   │   └── render-docs.yml             # Control-plane SSOT render → docs/network-addresses-generated.md
│   │   ├── group_vars/
│   │   │   ├── all.yml                     # Timezone, locale (sl_SI.UTF-8), NTP, domain kogler.si; infra vars (network/IP/WG/livebox)
│   │   │   ├── all/
│   │   │   │   └── versions.yml              # Docker image version pins (ALL hosts, HD-156) — one-file Renovate review
│   │   │   ├── router.yml                  # VLAN map (10/20/21/30/40/50/99), WireGuard, DNS
│   │   │   ├── vps.yml                     # docker_services list (VPS, Phase 2)
│   │   │   ├── home_servers.yml            # homelab_mode, docker_services list (home), GPU config
│   │   │   └── raspberry_pi.yml            # HA install method, version
│   │   ├── host_vars/
│   │   │   ├── oldsrv.kogler.si.yml        # Phase 1: homelab_mode=desktop, static IP
│   │   │   └── pi.kogler.si.yml             # Static IP, SSH user (node; ha.kogler.si = VIP)
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
│   │   │   │   └── home-assistant-standby/
│   │   │   ├── homepage_services.yaml.j2    # Homepage layout (auto-generated)
│   │   │   ├── homepage_widgets.yaml.j2     # Homepage status widgets
│   │   │   └── inventory.md.j2              # Service inventory table (auto-generated)
│   │   └── roles/
│   │       ├── common/tasks/{main,system}.yml  # fail-closed admin guard, apt, sudo
│   │       ├── docker/tasks/main.yml        # Docker CE + compose, daemon.json, user group
│   │       ├── vps-hardening/               # HD-154: VPS pre-deploy hardening (public edge only) — fail2ban, nftables default-deny, docker daemon
│   │       │   ├── tasks/main.yml
│   │       │   ├── templates/nftables.conf.j2
│   │       │   └── handlers/main.yml
│   │       ├── network/tasks/main.yml       # /etc/hosts (foundation; static-IP/trunk pending)
│   │       ├── nut/                         # UPS: master (nas) + clients (oldsrv, ha) — host-binary nut_exporter
│   │       │   ├── tasks/main.yml
│   │       │   ├── templates/*.j2
│   │       │   └── (upssched-cmd notify)
│   │       ├── cockpit/tasks/main.yml       # Management UI (nas + oldsrv, not Pi) — own login, no Authentik
│   │       ├── storage/                     # ZFS: import tank/bulk+nvme, datasets+props, sanoid/syncoid, NFS exports/mounts, push timers (docs/storage.md)
│   │       │   ├── defaults/main.yml        #   dataset/property/schedule map (mirrors storage.md)
│   │       │   ├── tasks/{main,zfs_common,nas,oldsrv}.yml
│   │       ├── amd_rocm/tasks/main.yml      # AMD ROCm, udev, OLLAMA_KEEP_ALIVE
│   │       ├── desktop/tasks/main.yml       # XFCE/GNOME, display manager, Xorg dual-GPU config
│   │       ├── office/tasks/main.yml        # ONLYOFFICE, MS fonts, OpenCloud client
│   │       ├── router/tasks/main.yml        # RouterOS REST API or .rsc push
│   │       ├── router/tasks/main.yml        # RouterOS REST API or .rsc push
│   │       ├── proxmox/tasks/main.yml       # Proxmox bridges, storage, VMs (Phase 2)
│   │       ├── home_assistant/tasks/main.yml# HA primary (Pi) + standby (oldsrv) + keepalived VIP
│   │       ├── docker_services/tasks/main.yml # THE key role — generic service deployer
│   │       ├── monitoring/tasks/main.yml    # Alloy → Prometheus + Loki; Grafana + alerting; blackbox; HA exporter
│   │       └── ai_diag/                     # ai-debug diagnostics dispatcher + sudoers
│   │           ├── tasks/main.yml
│   │           └── files/ai-diag
│   ├── bootstrap-ansible-client/
│   │   ├── bootstrap.sh                     # Management laptop setup
│   │   └── ansible.md                       # WSL2 Debian install guide
│   ├── host/
│   │   ├── post_install.sh                 # SHARED bootstrap: ansible-admin + ai-debug + sshd hardening
│   │   ├── nas/                            # preseed.cfg for nas.kogler.si (HP MicroServer)
│   │   ├── oldsrv/                         # preseed.cfg for oldsrv.kogler.si (i7-7700K)
│   │   ├── pi/                             # first-boot-config.sh for raspi.debian.net images (Pi 4)
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

> **Note:** `docs/` and `manual/` are the canonical, currently maintained documentation. This file documents the *intended* IaC implementation.

---

## Role Catalog (Implementation Details)

> **Catalog SSOT:** the role *list + responsibilities* live in [`docs/deployment-ansible.md`](../docs/deployment-ansible.md) (Role Catalog).
> This section adds implementation-level detail (files, idempotency, secrets) per role — the two are kept in sync, the doc is the owner.

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

### `vps-hardening`  *(HD-154 — public VPS only, mandatory pre-deploy)*
- **File:** `roles/vps-hardening/tasks/main.yml`, `templates/nftables.conf.j2`, `handlers/main.yml`
- **Scope:** the VPS is the single public trust boundary — run BEFORE `docker_services` in `playbooks/vps.yml`.
- **fail2ban:** SSH jail (`maxretry 3`) + `http-auth` jail for public login pages; installed + enabled.
- **nftables:** `/etc/nftables.conf` — input policy `drop`, allow `:443` + `:51820` + loopback + established/related (ICMP echo limited); forward allows docker bridges only.
- **Docker daemon:** `daemon.json` with `iptables: true`, `userland-proxy: false`, `live-restore: true`, capped json-file logs.
- **sshd assert:** `PasswordAuthentication no`, `PermitRootLogin no`, `MaxAuthTries 3` present (post_install.sh supplies the directives; the role asserts + fails loud if missing).
- **Secrets:** None.

### `network`
- **Current scope (foundation):** admin-role assert + `/etc/hosts` sync; SSOT doc render via `render-docs.yml`.
- **Pending:** VLAN sub-interface on trunk port, static IP (VLAN 99 for oldsrv, VLAN 10 + 99 native for nas); Pi static IP on Home VLAN. Network config-manager (systemd-networkd vs netplan) decision needed first.
- **All hosts:** `/etc/hosts` template with all node entries (resolved via local DNS)

### `cockpit`
- **Scope:** nas + oldsrv only (Pi excluded — managed via SSH/HA UI).
- Installs `cockpit` (+ `cockpit-zfs` on nas), enables `cockpit.socket`, grants `sudo` group (Cockpit admins on Debian) to `ansible_admin_users`.
- **Own login — deliberately NOT behind Authentik** (management surface, independent of SSO). Routes are Traefik **file-provider** config (`/opt/traefik/dynamic/cockpit.yml`, rendered on oldsrv): `cockpit-nas → nas.kogler.si:9090`, `cockpit-oldsrv → oldsrv.kogler.si:9090` (backends derived from the address SSOT, HD-188), no Forward-Auth middleware.
- Host/Origin note: Traefik preserves the original Host, so cockpit-ws Origin validation passes — no header rewrite on these routes.

### `nut`
- **Mode-driven** via `nut_mode` (host_vars): `master` (nas) / `client` (oldsrv, ha). See `docs/hardware-ups.md`, `docs/observability.md`.
- **master (nas):** `nut-server` + `usbhid-ups` (USB HID), `upsd` listening on the nas Home-VLAN address (`network_static_hosts` SSOT), port 3493, `nut_exporter` as a **host binary** (nas has no Docker) + systemd, `upssched-cmd` direct email/Signal notify (independent of Grafana/n8n).
- **client (oldsrv, ha):** `nut-client` + `upsmon` slave → `MONITOR powerwalker@{{ nut_host }} …`, per-host `shutdown_delay_seconds` (oldsrv 60 / ha 0).
- **Secrets:** `nut_password` + notify SMTP/Signal (`smtp_login`) from 1Password `Homelab-ansible` at render time.

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

### `router`
- Method: REST API (preferred) or templated `.rsc` push
- Configs: VLAN interfaces (10/20/21/30/40/50/99), DHCP, firewall, WireGuard, CAPsMAN (SSIDs incl. `Kogler IOT WAN`), DNS forwarding
- Secrets: RouterOS admin password, WireGuard keys

### `proxmox`
- Condition: `when: homelab_mode == 'proxmox'` (home Phase 2 only — not on netcup VPS)
- Bridges (vmbr0–vmbr4), storage, firewall; Secrets: Proxmox root password

### `home_assistant`
- **Pi = primary** (Debian + HA Container); **oldsrv = standby** (`home-assistant-standby`). Both render the **same `configuration.yaml`** from this repo — see `docs/smart-home-failover.md`.
- **HA web login = Authentik SSO via native OIDC**; Companion/API = HA long-lived token. **No Authentik Forward-Auth on the `ha` route.**
- `configuration.yaml` templated from repo (`use_x_forwarded_for: true`, `trusted_proxies: <Traefik>`).
- **VIP/VRRP:** `keepalived` on both HA nodes sharing the `ha-vip` (address SSOT); `ha.kogler.si` → VIP.
- Standby: `home-assistant-standby/docker-compose.yml.j2` → `/opt/home-assistant-standby/` on home_servers; systemd unit disabled by default; started manually on forward takeover.
- State sync: config + optional DB pushed Pi → standby every ~15 min (LAN); reverse on failback.
- Secrets: HA API keys, MQTT credentials

### `home_assistant` — failover runbooks
- Forward (Pi→oldsrv) and reverse (oldsrv→new Pi) manual runbooks in `docs/smart-home-failover.md`.

### `docker_services` (Key Role)
- **Input:** `docker_services` list from group vars
- **Loop:** skip if `enabled: false` → create `/opt/<service>/` → template `docker-compose.yml.j2` → template extra configs → create `docker-compose@<service>.service` → `systemctl enable --now`
- **Post-deploy:** template Homepage config + inventory docs, reload Homepage, commit+push to Git
- **Tags:** each service task tagged `{{ item.name }}` for targeted `--tags`

### `monitoring`
- **Alloy:** host agent (Ansible-installed, not containerized) — host metrics, container logs (`docker.sock`), SNMP; remote-write → Prometheus, logs → Loki
- **Prometheus:** sole metrics store, 30 d retention, `db-internal`
- **Loki:** single-node/SSD log store, 14 d retention
- **Grafana:** provisioned dashboards + alert rules; datasources = Prometheus + Loki; Authentik OIDC; **admin-only, internal** (`stats.kogler.si`)
- **Grafana Alerting:** 3 tiers (Critical/Warning/Info), ~30 min poke, self-monitoring rules
- **Grafana-native SMTP:** fail-safe contact point in parallel with n8n
- **blackbox-exporter:** external reachability → `probe_success`
- **HA exporter:** HA `/api/prometheus` (bearer token from 1Password); Prometheus scrape
- **SNMP:** MikroTik poll 5–15 s
- **Alert delivery:** n8n + signal-cli-rest-api are Docker services in `group_vars/home_servers.yml`, deployed by the `docker_services` role — they handle webhook routing, dedup, and Signal notification at runtime
- **Ordering:** after `docker_services`
- **Secrets:** `ha_api`, `grafana_login`, `smtp_login`

### `ai_diag`
- `/usr/local/sbin/ai-diag` + `/etc/sudoers.d/ai-diag` (single NOPASSWD entry for `ai-debug`)
- Deps: smartmontools, hdparm, dmidecode, sg3-utils; read-only SMART/ZFS/journal diagnostics + smart tests
- Update: edit `roles/ai_diag/files/ai-diag` → re-run role

---

## Service Definitions (Group Vars)

### Home Server Services (`group_vars/home_servers.yml`)

> **Canonical list:** `docker_services` lives in `group_vars/home_servers.yml` (the
> runtime source of truth — including the `enabled`/`instance`/`subdomain` modifiers
> and any per-host gates). The inline sample below is **illustrative only and may
> drift** — do not edit it to "keep it in sync"; edit the group_vars instead.

```yaml
# Illustrative sample — canonical list: group_vars/home_servers.yml
# (traefik, crowdsec, authentik, opencloud, immich-app, forgejo, ollama, immich-ml,
#  technitium[oldsrv], pihole, (raspberrymatic-standby[oldsrv] — HD-13 parked), home-assistant-standby[oldsrv],
#  headscale, kopia-server, db-backup, grafana→stats, n8n→auto,
#  sunshine[desktop], + TODO templates: homepage, renovate, prometheus, loki,
#  blackbox-exporter, signal-cli-rest-api, metabase)
```

> **Catalog:** all services are defined in `docs/services.md`. In Phase 1 **all** run on
> `oldsrv.kogler.si`; public-facing ones move to `vps.kogler.si` (Traefik) in Phase 2.

### VPS Services (`group_vars/vps.yml`) — Phase 2, reference only

```yaml
docker_services:
  - { name: traefik,        template_dir: traefik,      enabled: false }
  - { name: crowdsec,       template_dir: crowdsec,     enabled: false }
  - { name: authentik,      template_dir: authentik,    enabled: false }
  - { name: opencloud,      template_dir: opencloud,    enabled: false }
  - { name: immich-app,     template_dir: immich-app,   enabled: false }
  - { name: forgejo,        template_dir: forgejo,      enabled: false }
  - { name: grafana,        template_dir: grafana,      enabled: false }
  - { name: n8n,            template_dir: n8n,           enabled: false }
  - { name: kopia-server,   template_dir: kopia-server, enabled: false }
  - { name: db-backup,      template_dir: db-backup,    enabled: false }
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
  (`kogler.si`, `foto`, `file`, `git`, `sso`, `ha`, `vpn`). **No proxy** — DNS-only, real client IPs reach Traefik.
- **Certificates:** single `*.kogler.si` wildcard via ACME **DNS-01**, issued by the **VPS Traefik** (single issuer, HD-178; oldsrv/Pi edges consume synced certs — enforced by the `traefik_acme_issuer` flag, HD-181) with a Cloudflare API token (1Password `Homelab-ansible`).

---

## 1Password Secret Naming Convention

All secrets live in the `Homelab-ansible` vault. Naming pattern: `<service>_<type>` (service uses `-`, single `_` delimiter).
See `docs/deployment-secrets.md` for the full master list + rename map (including `cloudflare_api`).

| Item Name | Used By |
|-----------|---------|
| `kopia_password` | kopia-server |
| `authentik_db`, `authentik_password`, `authentik_login` | authentik |
| `opencloud_db`, `immich_db`, `forgejo_db` | platform DBs |
| `grafana_login`, `smtp_login` | grafana |
| `headscale_api` | headscale |
| `ha_api`, `ha-vrrp_password` | home_assistant / monitoring |
| `cloudflare_api` | ACME DNS-01 wildcard cert |
| `router_login`, `wg_password` | router |

---

## Implementation Order

| Step | What | Depends On |
|------|------|------------|
| 1 | `common` + `docker` + `network` roles | None — base OS |
| 2 | `ai_diag` role | `common` |
| 3 | `amd_rocm` role | `common` |
| 4 | `docker_services` role (core loop + systemd + templates) | `docker`, `network`, `amd_rocm` |
| 5 | `desktop` + `office` roles | `amd_rocm` (dual-GPU Xorg) |
| 6 | `home_assistant` role (Pi primary + oldsrv standby + keepalived VIP `ha-vip`) | `docker` |
| 7 | `monitoring` role (incl. Grafana alerting rules + SMTP) | `docker_services` |
| 8 | `router` role (+ `.rsc`) | `network` (IPs/VLANs defined) |
| 9 | `proxmox` (Phase 2) | `network` |
| 10 | Renovate + Homepage templates | `docker_services` |
| 11 | Post-deploy hooks (Homepage + inventory) | `docker_services` |
| 12 | Forgejo Actions workflow (`.forgejo/workflows/deploy.yml`) | all roles |
| 13 | End-to-end test: Renovate → PR → Actions → Deploy | everything |

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
