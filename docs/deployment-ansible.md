---
title: Ansible Specification
role: design-spec
domain: deployment
status: active
tags: [deployment, ansible, iac]
---
# Ansible Specification

> **Role:** ★ Design spec — read this to **author or correct** the Ansible IaC
> (playbooks, roles, group_vars, templates).
>
> **Direction of truth:** this document is an *authoring* spec, not the source
> of runtime values. Concrete values (IPs, VLANs, service lists) live in IaC
> (`group_vars/*.yml`, `host_vars/*.yml`) and flow **IaC → docs** via the render
> (→ `docs/network-addresses.md`, later `docs/inventory.md`); those generated
> views must not be hand-edited.
>
> **Regenerate `docs/network-addresses.md` after a master `.yml` change** — either
> `python scripts/render_network_addresses.py` (works on this Windows host, no
> Ansible needed) or `ansible-playbook playbooks/render-docs.yml -i inventory.ini`
> (Linux/CI). Ansible's `render-docs.yml` cannot run on Windows (ansible crashes at
> startup: `os.get_blocking` → `OSError [WinError 87]`), so use the Python script
> locally.
> **Links to:** `services.md`, `hardware.md`, `deployment-secrets.md`, `deployment-compose.md`
> **Linked from:** `deployment.md`, `index.md`

---

## IaC Authoring Conventions

> Rules that apply to every role, template, and group_var. Violations must be
> flagged during code review.

### Variables & IPs
- **Never hardcode IPs or CIDRs** — reference `network_static_hosts` / `network_ranges`
  from `group_vars/all.yml` (the SSOT). Even Docker bridge CIDRs (`traefik-public`,
  `services-internal`, `db-internal`) have entries there.
- **Service config → `group_vars/`, not role defaults.** `defaults/main.yml` is for
  role-internal knobs (directories, timeouts), not architecture values.
- **`/opt/<service>/`** is the standard compose path — this is an architectural
  constant used by all templates and systemd units.

### Secrets
- **Never hardcode secrets.** All credentials use
  `{{ lookup('community.general.onepassword', '<item>', field='<field>', vault=op_vault) }}`
  at render time. See `docs/deployment-secrets.md` for the naming convention.
- **One vault: `Homelab`.** The variable `op_vault` is defined in `group_vars/all.yml` —
  always use it, never a literal string.
- **The `field=` parameter is mandatory.** The lookup defaults to `password`, which is
  NOT always the right field (API credentials use `credential`; Database items also carry
  `username`).

### Role structure
- **One entry point:** `tasks/main.yml` → `include_tasks:` for sub-files
  (see the `nut` role for the canonical pattern).
- **Always assert safe execution context** at the top:
  ```yaml
  - name: Refuse runs as ai-debug or unknown users
    assert:
      that: ansible_user in ansible_admin_users
  ```
- **Idempotent by default.** Use `state: present`, `force: no` where local edits
  should survive, check for existence before resource-heavy operations.
- **Tag every loop item** for targeted `--tags`:
  ```yaml
  tags: "{{ item.name }}"
  ```

### Compose templates (`templates/docker_services/`)
- **One directory per service.** Files inside: `docker-compose.yml.j2` (always),
  plus extra configs (e.g. `dynamic/routes.yml.j2`, `tuwunel.toml.j2`).
- **Networks are `external: true`** — the `docker_services` role creates
  `traefik-public`, `services-internal`, `db-internal` before any compose up.
- **Labels reference group_vars** (`timezone`, `domain_local`, `ha_vip`) and
  1Password lookups — never hardcoded values.
- **Secrets placeholders:** every template starts with a comment block documenting
  which 1Password items it consumes:
  ```yaml
  # Secrets via {{ lookup('community.general.onepassword', '<name>', vault=op_vault) }}
  #   - service_db       field=password
  #   - service_api      field=credential
  ```

### `docker_services` entry fields
- **`name`** — project name, also `/opt/<name>/` directory.
- **`template_dir`** — subdirectory under `templates/docker_services/`.
- **`subdomain`** (optional) — overrides `{{ name }}.kogler.si`. Required when
  the service URL differs from its name (e.g. `grafana` → `stats.kogler.si`).
- **`enabled`** (optional) — Jinja2 expression, evaluated per-host. Defaults to
  `true`. Use for per-host gating (`technitium` on `oldsrv` only).
- **`instance`** (optional) — for multi-instance services sharing one template
  (e.g. `raspberrymatic-standby`).

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
│   ├── raspberry_pi.yml             # hosts: raspberry_pi → common→network→docker→home_assistant→docker_services→monitoring
│   └── all.yml                      # Cross-cutting: /etc/hosts sync
├── group_vars/
│   ├── all.yml                      # Timezone, locale, NTP, domain names
│   ├── router.yml                   # VLAN map, WireGuard peers, DNS forwarding
│   ├── vps.yml                      # docker_services list (VPS)
│   ├── home_servers.yml             # homelab_mode, docker_services list (home), GPU config
│   └── raspberry_pi.yml             # HA install method, Pi docker_services (raspberrymatic, technitium-secondary)
├── host_vars/
│   ├── oldsrv.kogler.si.yml         # homelab_mode=desktop, static IP
│   ├── nas.kogler.si.yml            # HP MicroServer Gen8 — ZFS storage
│   ├── vps.kogler.si.yml            # netcup RS 2000 G12 (bought 2026-08-18)
│   └── pi.kogler.si.yml             # Static IP, SSH user (node; ha.kogler.si = VIP)
├── roles/
│   ├── common/tasks/                # system.yml + main.yml
│   ├── docker/tasks/main.yml        # Docker CE + compose install
│   ├── network/tasks/main.yml       # VLAN interfaces, /etc/hosts
│   ├── cockpit/tasks/main.yml       # Cockpit management UI (nas+oldsrv, own login, no Authentik)
│   ├── storage/tasks/main.yml       # nas: ZFS pools/datasets, sanoid/syncoid, NFS exports; oldsrv push timers — see roles/storage (implemented)
│   ├── amd_rocm/tasks/main.yml      # AMD ROCm, udev, OLLAMA_KEEP_ALIVE
│   ├── desktop/tasks/main.yml       # XFCE/GNOME, display manager, Xorg dual-GPU config
│   ├── office/tasks/main.yml        # ONLYOFFICE, MS fonts, OpenCloud client
│   ├── kopia/tasks/main.yml         # kopia-agent + kopia-server Docker containers (deployed by docker_services)
│   ├── router/tasks/main.yml        # RouterOS REST API or .rsc push
│   ├── proxmox/tasks/main.yml       # Proxmox bridges, storage, VMs (Phase 2)
│   ├── home_assistant/tasks/main.yml# HA primary (Pi) + standby (oldsrv) + keepalived VIP + failover trigger
│   ├── docker_services/tasks/main.yml # THE key role — generic service deployer
│   ├── monitoring/tasks/main.yml    # Alloy → Prometheus + Loki; Grafana + alerting; blackbox; HA exporter
│   ├── nut/                         # UPS: master (nas) + clients (oldsrv, ha) — see Role Catalog
│   │   ├── tasks/main.yml
│   │   └── files/upssched-cmd       # direct email+Signal notify on ONBATT/LOWBATT
│   └── ai_diag/                     # ai-debug diagnostics dispatcher + sudoers
│       ├── tasks/main.yml
│       └── files/ai-diag
└── templates/
    ├── docker_services/             # docker-compose.yml.j2 per service
    ├── homepage_services.yaml.j2
    ├── homepage_widgets.yaml.j2
    ├── inventory.md.j2
    └── nut/                         # nut.conf.j2, ups.conf.j2, upsd.users.j2, upsmon.conf.j2, upssched.conf.j2
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
pi.kogler.si         ansible_user=ansible-admin

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

---

## Host Vars

### oldsrv.kogler.si.yml
```yaml
homelab_mode: desktop            # "desktop" or "proxmox" or "headless"
ansible_host: 10.10.99.30        # Management VLAN 99 static IP
home_ip: 10.10.1.30              # Home VLAN 10 — node IP (VRRP anchor)
dns_primary_ip: 10.10.1.30       # Technitium primary binds node IP
ansible_user: ansible-admin
nut_mode: client                 # UPS NUT slave → delayed shutdown (see nut role)
ut_host: nas.kogler.si           # NUT master endpoint
shutdown_delay_seconds: 60       # lets Grafana→n8n→Signal flush Critical alert before powerdown
```

### nas.kogler.si.yml
```yaml
ansible_host: 10.10.1.10           # VLAN 10 (Home) — static (Cockpit/NFS/NUT master)
mgmt_ip: 10.10.99.10               # VLAN 99 (Management) — native
ilo_ip: 10.10.99.11                # iLO4 remote mgmt
ansible_user: ansible-admin
nut_mode: master                 # NUT master (only host physically USB-wired to the UPS)
ut_driver: usbhid-ups            # PowerWalker VFI ICT/ICR IoT 3000 via USB HID
nut_serial: auto                 # USB HID auto-detect; battery/runtime thresholds set here
```

### vps.kogler.si.yml
```yaml
ansible_host: 159.195.111.66        # Public IPv4 (netcup RS 2000 G12); IPv6 2a0a:4cc0:60:fcc:*
ansible_user: ansible-admin
```

**SSH host fingerprints** (netcup SCP, 2026-08-18) — for `known_hosts` pinning / MITM reference:

| Type | SHA256 | MD5 |
|---|---|---|
| RSA | `SHA256:LpwYdCSTDcIZ0fvGUj8mRFJOgLXabbMYU+7VTr+tWIE` | `73:94:9d:34:5d:9c:c1:78:09:28:ca:73:fb:78:f3:ea` |
| ECDSA | `SHA256:aPEyZBN0xmIMhqV2SsWSy0OANMRdbmIOYYcYWtgejzI` | `d8:95:ad:63:97:df:f5:0a:3d:44:71:07:a3:64:46:a3` |
| ED25519 | `SHA256:DfRE+i6EiZUYD2Bot2hanIh+Ey47tTpzv352boxB3fY` | `d7:9f:00:72:b9:26:68:ce:64:eb:49:05:1e:00:d1:8e` |

### pi.kogler.si.yml
```yaml
ansible_host: 10.10.1.20        # Home VLAN — node IP (VRRP anchor); ha.kogler.si = VIP
ansible_user: ansible-admin      # preseed-installed like nas/oldsrv (no Cockpit)
dns_secondary_ip: 10.10.1.20     # Technitium secondary binds node IP
# Roles: primary HA (Docker) + RaspberryMatic/HmIP-RFUSB + Technitium secondary DNS
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
  - { name: pihole,          template_dir: pihole }
  - { name: raspberrymatic-standby, template_dir: raspberrymatic, instance: standby, enabled: "{{ inventory_hostname == 'oldsrv.kogler.si' }}" }
  - { name: home-assistant-standby, template_dir: home-assistant-standby, enabled: "{{ inventory_hostname == 'oldsrv.kogler.si' }}" }
  - { name: headscale,       template_dir: headscale }
  - { name: kopia-server,    template_dir: kopia-server }
  - { name: db-backup,       template_dir: db-backup }
  - { name: grafana,         template_dir: grafana,     subdomain: stats }
  - { name: n8n,             template_dir: n8n,          subdomain: auto }
  - { name: sunshine,        template_dir: sunshine,     enabled: "{{ homelab_mode == 'desktop' }}" }

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

### `cockpit`
- **Scope:** nas + oldsrv only (Pi excluded). Installs `cockpit` (+ `cockpit-zfs` on nas), enables `cockpit.socket`, grants Cockpit admin group to `ansible_admin_users`.
- **Own login — NOT behind Authentik** (management surface must work independently of SSO).
- **Traefik:** file-provider routes (`/opt/traefik/dynamic/cockpit.yml` on oldsrv): `cockpit-nas → 10.10.1.10:9090`, `cockpit-oldsrv → 10.10.1.30:9090`, no Forward-Auth middleware.
- 9090 is intra-Home-VLAN between Traefik (oldsrv) and nas — no inter-VLAN firewall rule needed.

### `storage` (roles/storage — data model SSOT: [`storage-zfs.md`](storage-zfs.md))
- **Hosts:** nas (ZFS + NFS server) and oldsrv (`nvme` data pool + fstab mounts + push timers)
- Installs `zfsutils-linux`, `sanoid`, `syncoid`; **imports** pools — `tank`/`bulk` on nas, `nvme` on
  oldsrv (never re-creates; pools are self-describing); creates datasets with the properties from
  `storage-zfs.md`; templates `sanoid.conf`;
  enables `sanoid.timer`/`syncoid.timer`; renders `/etc/exports` (`tank/data`, `bulk/media`); oldsrv
  fstab mounts; deploys the three nightly push jobs (db dumps → `tank/data/db-dumps`, service state →
  `tank/data/services`, face thumbs → `bulk/data/immich-thumbs`); wires Kopia sources on oldsrv
  (local-only, NAS-independent)

### `amd_rocm`
- **Repo:** Official AMD ROCm (Debian-compatible path)
- **Packages:** `rocm-hip-sdk`, `rocm-opencl-sdk`
- **Groups:** `ansible_user` → `video`, `render`
- **Udev:** `/dev/kfd` mode 0666, `/dev/dri/render*` mode 0666
- **Env:** `OLLAMA_KEEP_ALIVE=5m` in `/etc/environment`
- **Condition:** applied from `playbooks/home_servers.yml` when `gpu_vendor | default('') == 'amd'` (group var; the role itself asserts the admin-user guard)

### `desktop`  *(implemented — user accounts/auto-login pending → HD-51)*
- **Condition:** `when: homelab_mode == 'desktop'`
- **DM/Desktop:** LightDM + XFCE (decision: XFCE preferred, lightweight) — installed, greeter enabled
- **Xorg:** `10-igpu-primary.conf.j2` → `/etc/X11/xorg.conf.d/10-igpu-primary.conf` — Intel iGPU (modesetting, BusID `PCI:0:2:0` from `desktop_igpu_busid`) as `PrimaryGPU`; AMD dGPU headless by design (no monitor — reserved for Docker GPU containers)
- **PENDING (HD-51):** family user accounts + auto-login — 4 members + guest + a **neutral family account** owning shared media data (NOT a personal account as uid/gid 1000/1000); UID/group strategy under research. Role currently boots to the greeter with no local users.
- See [`hardware-gpu.md`](hardware-gpu.md) for dual-GPU topology

### `office`  *(implemented — OpenCloud client = Debian 13 AppImage, manual install → HD-52)*
- **Condition:** `when: homelab_mode == 'desktop'`
- **ONLYOFFICE:** official ONLYOFFICE apt repo (`deb https://download.onlyoffice.com/repo/debian squeeze main`), `onlyoffice-desktopeditors` — installed
- **Fonts:** `ttf-mscorefonts-installer` (EULA pre-accepted via `debconf`) — installed
- **OpenCloud client (HD-52, Debian 13 only):** the official client (`opencloud-eu/desktop`) ships **AppImage only** — installed **manually** per client (download → `chmod +x` → `/opt` or `~` + `.desktop` entry). Ansible only preps the **runtime dependency `libfuse2t64`** (FUSE for AppImage) — **Debian 13 (trixie) only**, no bookworm support. Auth via **native OIDC → Authentik** (multi-redirect provider + CSP) — *not* Traefik Forward-Auth (see deployment-compose).

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

### `nut`
- **Mode-driven** via `nut_mode` (see host_vars):
  - **master** (`nas`): install `nut-server` + `usbhid-ups` driver (USB HID to the PowerWalker) → `upsd` serving `powerwalker@localhost` on **TCP 3493** (restricted to homelab hosts). Deploys **`nut_exporter`** (single instance) → Prometheus. Installs the **`upssched-cmd`** notify script (email + Signal directly on `ONBATT`/`LOWBATT`, secrets from 1Password).
  - **client** (`oldsrv`, `ha`/Pi): install `nut-client` + `upsmon` slave → `MONITOR powerwalker@{{ nut_host }} 1 …`, local `shutdown` on low battery. Port **3493** is intra-VLAN to the master (no inter-VLAN rule needed).
- **Shutdown policy:** Critical = battery < **20%** or runtime < **5 min**. `upssched` applies **`shutdown_delay_seconds`** per host — `oldsrv=60` (flush Grafana/n8n/Signal alerts before powerdown), `nas=0`, `ha=0`.
- **Exporter:** **one** `nut_exporter` on the master only (SSOT — other hosts are NUT clients, not exporters).
- **Depends on:** `common`, `network`
- **Run before** `monitoring` (monitoring needs the exporter up).

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
{{ lookup('community.general.onepassword', 'authentik_db', field='password', vault=op_vault) }}
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
| 4 | `storage` (ZFS import/datasets, sanoid/syncoid, NFS exports/mounts, push timers — `roles/storage`) | `common`, `network` |
| 5 | `docker_services` (core loop + systemd + templates) | `docker`, `network`, `amd_rocm`, `storage` (NFS mounts ready) |
| 6 | `desktop` + `office` | `amd_rocm` (dual GPU Xorg) |
| 7 | `home_assistant` (Pi primary + oldsrv standby + keepalived VIP `10.10.1.200`) + Pi `docker_services` (`raspberrymatic`, `technitium-secondary`, `traefik-ha` edge for `ha` + `dns-pi`) | `docker` |
| 8 | `nut` — nas: master (usbhid-ups + upsd + nut_exporter); oldsrv/ha: client (upsmon slave + upssched + notifycmd) | `common`, `network` |
| 9 | `monitoring` (incl. Grafana alerting rules + SMTP) | `docker_services` (Prometheus/Loki/n8n up) **and** `nut` (needs nut_exporter) |
| 10 | `router` | `network` (IPs/VLANs defined) |
| 11 | `proxmox` (Phase 2) | `network` |