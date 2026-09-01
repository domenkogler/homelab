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
> (→ `docs/network-addresses-generated.md`, later `docs/services-inventory-generated.md`); those generated
> views must not be hand-edited.
>
> **Regenerate `docs/network-addresses-generated.md` after a master `.yml` change** — easiest is
> the unified entry `python scripts/render_all.py` (pure-Python, refreshes ALL generated docs;
> see `scripts/README.md`). Equivalent per-doc: `python scripts/render_network_addresses.py`
> (works on the Windows host directly, no
> Ansible needed) or `ansible-playbook playbooks/render-docs.yml -i inventory.ini` (Linux/CI,
> or on this machine via **WSL Debian**). Native Windows ansible crashes at startup
> `python scripts/render_network_addresses.py` (works on the Windows host directly, no
> Ansible needed) or `ansible-playbook playbooks/render-docs.yml -i inventory.ini` (Linux/CI,
> or on this machine via **WSL Debian**). Native Windows ansible crashes at startup
> (`os.get_blocking` → `OSError [WinError 87]`); on this machine run Ansible inside
> `wsl.exe -d Debian` with `~/ansible-venv/bin/activate` (see `[ansible.md](../IaC/bootstrap-ansible-client/ansible.md)`).
> **Links to:** `services.md`, `hardware.md`, `deployment-secrets.md`, `deployment-compose.md`
> **Linked from:** `deployment.md`, `index.md`

---

## IaC Authoring Conventions

> Rules that apply to every role, template, and group_var. Violations must be
> flagged during code review.

### Variables & IPs
- **Never hardcode IPs or CIDRs** — reference `network_static_hosts` / `network_ranges`
  from `group_vars/all/main.yml` (the SSOT). Even Docker bridge CIDRs (`traefik-public`,
  `services-internal`, `db-internal`) have entries there.
- **Service config → `group_vars/`, not role defaults.** `defaults/main.yml` is for
  role-internal knobs (directories, timeouts), not architecture values.
- **`/opt/<service>/`** is the standard compose path — this is an architectural
  constant used by all templates and systemd units.

### Secrets
- **Never hardcode secrets.** All credentials use
  `{{ lookup('community.general.onepassword', '<item>', field='<field>', vault=op_vault) }}`
  at render time. See `docs/deployment-secrets.md` for the naming convention.
- **One vault: `Homelab-ansible`.** The variable `op_vault` is defined in `group_vars/all/main.yml` —
  always use it, never a literal string.
- **The `field=` parameter is mandatory.** The lookup defaults to `password`, which is
  NOT always the right field (API credentials use `credential`; Database items also carry
  `username`).
- **Bulk-fetch mode (HD-258):** to avoid re-spawning `op` per lookup (≈160/converge), the
  `docker_services` role batches the needed item set into a `vault: {...}` dict once and
  renders from it (see the §docker_services *Bulk 1Password pre-pass*). New templates may
  consume the dict (`vault['<item>'].<field>`) instead of a raw lookup; keep the fail-closed
  contract either way.

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

### Tags & surgical runs (HD-220 wiring)

How `--tags` actually behaves in THIS repo — verified against `site.yml`,
`playbooks/vps.yml`, `roles/docker_services/tasks/{main,deploy-service}.yml`:

- **Selection is a UNION.** A filtered run executes every task carrying ANY requested tag
  (plus every task tagged `always`; tasks tagged `never` run only when explicitly named).
  Adding tags to the filter can only ADD work — it never narrows a broader tag.
- **Inheritance stops at dynamic includes.** Tags attach downward from play → role → block,
  but `include_tasks:` is evaluated as ONE task: its own effective tags gate WHETHER the file
  loads at all, and they do NOT cascade into the included file's contents. (`import_tasks:`
  would inherit/cascade — this role uses `include_tasks:` everywhere.) Inside
  `docker_services`, that means:
  - role-level tag `[docker_services]` (`vps.yml`) + explicit `tags: docker_services` on the
    include lines reach all **direct** `main.yml` tasks (asserts, networks `[docker_services,
    networks]`, teardown, homepage block `[homepage, docker_services]`) AND fire all six
    include lines under `--tags docker_services`;
  - contents of `deploy-service.yml` carry ONLY their per-service tags — all 13 tasks are
    tagged `"{{ svc.name }}"` (dirs, bind-dir pre-create, copy/template/extra-render, compose
    config-validate, compose up, systemd enable, db-role-sync, forgejo syncs, OIDC source);
    nothing inside runs unless the filter names that service;
  - authentik-lane includes have UNtagged include lines (pre-pass, blueprint one-shot, glue) —
    they still fire via inherited `[docker_services]`, but their contents self-filter:
    blueprint apply is `[authentik, docker_services]` (runs on every `docker_services` pass),
    pre-pass/glue tasks are `[authentik, secret-egress]` (need those tags requested).
- **Consequences / gotchas:**
  - `--tags <service>` alone (e.g. `--tags opencloud`) matches no include line → SILENT
    NO-OP. Always pair role + service: `--tags "docker_services,opencloud"`.
  - TRUE surgical convergence needs the **`docker_services_scope`** var (HD-255/HD-260, extended HD-269):
    `--tags docker_services -e docker_services_scope=<service>` deploys a single service, or a
    comma-list for several: `-e docker_services_scope="forgejo,traefik"`. Without it, the include
    lines' `tags: docker_services` (union selection) run every direct-role `main.yml` task
    (networks, teardown, homepage, cert-pull, authentik-lane) even when only one inner service is
    matched — the scope var gates those platform tasks AND collapses the deploy loop to the scoped
    service(s), so a surgical run is genuinely scoped (nothing else even iterates).
  - Handlers are tag-filtered too: a handler must match the filter (or carry `tags: always`)
    or it is skipped even when notified by a task that ran — since HD-237 EVERY role handler
    carries `tags: always` (all 22 across 9 roles; monitoring was first, HD-220), so a
    notification fired inside a filtered run can never be silently dropped. Keep it that way:
    any new handler must carry `tags: always`.
  - Filtered runs skip untagged top-level tasks: e.g. `site.yml`'s pre-flight admin-user
    assert and any playbook whose roles have no role-level tags (`home_servers.yml`,
    `raspberry_pi.yml`, `router.yml`, …) can only ever run their `always`-tagged tasks under
  - Filtered runs skip untagged top-level tasks: e.g. `site.yml`'s pre-flight admin-user
    assert and any playbook whose roles have no role-level tags (`home_servers.yml`,
    `raspberry_pi.yml`, `router.yml`, …) can only ever run their `always`-tagged tasks under
    `--tags`. Only `vps.yml` (and `all.yml`'s `[hosts]`) supports role-surgical filtering today.
  - **Base bootstrap tier (HD-269 Step 4):** the rarely-changing roles (`common`, `docker`,
    `hardening`, `network`, `cifs`, `wireguard`) each carry an **additive `base` tag** alongside
    their own role tag. Because selection is a UNION, naming `base` groups all six as ONE
    runnable unit (`--tags base`) while a services-only run (`--tags docker_services,monitoring`)
    still works untouched — the `base` tag simply isn't in that filter, so nothing from those
    roles runs. The tier is never a *skip-default*: a full converge (no `--tags`) runs everything
    in order; `base` only makes the rare roles *selectable as a set*. Roles keep their own tags
    so they can still be run individually (`--tags common`).
  - Partial application is the failure mode to fear (renders without up, service changed but
    its Traefik routes stale): prefer the canonical forms below and verify with
    `--list-tasks --tags <filter>` before running.
- **Canonical invocations:**

  | Goal | Command |
  |------|---------|
  | Full converge | `ansible-run.sh site.yml` (or the group playbook) |
  | Single VPS role | `ansible-run.sh playbooks/vps.yml --tags monitoring` |
  | Single service (recommended) | `ansible-run.sh playbooks/vps.yml --tags docker_services -e docker_services_scope=<service>` |
  | Several services (HD-269) | `--tags docker_services -e docker_services_scope="<svc1>,<svc2>"` |
  | Service + edge/dynamic-file companions | `--tags "docker_services,<service>,traefik"` |
  | Include Authentik pre-pass/glue lanes | append `,authentik,secret-egress` |
  | Resume after a failing step | `--start-at-task="<task name>"` (no `--tags` → everything from there runs) |
  | Run the rare base bootstrap tier (HD-269 Step 4) | `--tags base` — runs `common`, `docker`, `hardening`, `network`, `cifs`, `wireguard` only (first-boot / a rare infra change); `docker_services` & `monitoring` excluded |
  | Discovery | `--list-tags` / `--list-tasks --tags "<filter>"` |

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
- **`bind_owner_uid`** + **`bind_dirs`** (optional; Wave-3 R5, HD-218) — Class-A fix for
  non-root images: Docker auto-creates host bind-mount sources as `root:root`, so services
  whose image runs a fixed uid (grafana 472, node-user images 1000) or `storage_uid` died with
  EACCES on first boot. `deploy-service.yml` pre-creates `/srv/docker/<name>/<dir>` owned by
  `bind_owner_uid` for each entry in `bind_dirs` (`'.'` = the service root). Set both keys
  together on the service entry whenever a template bind-mounts `/srv/docker/<name>/...` into
  a non-root container.
- **`db_role_sync`** + **`db_item`** + **`db_pg_container`** (optional; HD-220, incident
  2026-08-23) — postgres-image rotation-drift guard: the official postgres image applies
  `POSTGRES_PASSWORD` ONLY at first cluster init, so rotating the vault `<service>_db` item
  re-renders every compose env while the persisted cluster keeps the OLD role password
  (forgejo crash-looped overnight on exactly this). Opted-in services get an idempotent
  `ALTER ROLE ... WITH PASSWORD` executed via `docker exec` into the pg container AFTER the
  stack is up — the password source is the SAME vault item (no_log; IaC-only, no hand-run
  SQL against managed DBs). Set all three keys on any service entry whose template bundles
  its own postgres container. Sibling opt-in **`db_ro_sync` + `db_ro_item` +
  `db_pg_container`** (HD-242): ensures a dedicated READ-ONLY login role (CREATE-if-absent,
  then password + `SELECT`-only grants on schema `public` incl. default privileges,
  re-applied every converge) in ANOTHER stack's pg container — consumer-side key set, e.g.
  Metabase → forgejo-db via `metabase-forgejo_ro`; vault rotation propagates automatically.
- **Lazy loop_var shadowing (HD-185 pattern, generalized):** `vars: { svc: "{{ item }}" }` on an
  `include_tasks` loop is LAZY - any INNER loop in the included file re-resolves `item` in its own
  context, so `svc` collapses to that inner string ('str' has no attribute 'name', found live on
  traefik's extra-.j2 templates). Always give include loops a dedicated `loop_var` (`svc_entry`) AND
  declare explicit `loop_var:` for every inner loop whose var name is referenced in task args
  (`extra` precedent).

---

## Execution Modes

> **Safety guard:** `site.yml` starts with a pre-flight check that **refuses to run as `ai-debug` or any user outside `ansible_admin_users`** (per `group_vars/all/main.yml`: `ansible-admin` only). The `common` role repeats the same assert for direct playbook/role runs. Anyone running Ansible as `ai-debug` gets an immediate abort — it must never gain sudo.

### Bootstrap Mode (Domen's Laptop)
```bash
ansible-playbook site.yml -i inventory.ini
```
Used for: initial setup, new hardware, full rebuild.

### Targeted Mode
```bash
# Single-service converge: role tag + the docker_services_scope var (union semantics
# alone can't narrow the direct-role main.yml tasks — see §Tags & surgical runs above).
ansible-playbook site.yml --tags docker_services -e docker_services_scope=immich-ml
# A service tag alone matches nothing; keep the role tag (union semantics).
```

### Dry-run Mode (`--check --diff`)

`--check` mode is **NOT** compatible with the HD-258 bulk 1Password pre-pass: the pre-pass
calls `op-vault-export.py --derive` which requires a live 1Password session to read items
(vault in `~/.config/op/homelab-sa-token`), and in check mode the lookup returns empty stdout
→ the `combine(vault, from_json(empty))` filter raises `from_json failed: Expecting value` and
the play aborts at `fetch-vault-pass.yml:62` (other session's audit AUD-B-2, reproduced live
2026-08-29). For diff/inspection of a future change without running it, use one of:
- `--check --diff` only after seeding the `vault` dict another way (e.g. mock the bulk pre-pass
  by exporting `op-vault-export.py --services <single> --format=json` to a fixture file and
  reading it via `set_fact: op_vault_out: {stdout: ... }`); the rest of the role is then
  check-mode-safe;
- skip the pre-pass and render single-service templates with `lookup('community.general.onepassword', ...)`
  inline (slow, but check-mode compatible);
- run the live converge scoped to the service (`-e docker_services_scope=<svc>`) and use
  `--diff` on the rendered compose on the target (`ssh vps 'docker compose -f /opt/<svc>/docker-compose.yml config'`).
  The live run is fast (HD-269 measured ~18s for a single service) and you get the real diff.

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
│   ├── switch.yml                   # hosts: switch → role: switch
│   ├── storage.yml                  # hosts: storage (nas) → common→ai_diag→network→storage→nut(master)→cockpit
│   ├── vps.yml                      # hosts: vps → common→docker→vps-hardening→network→cifs→[wireguard]→docker_services→monitoring
│   ├── home_servers.yml             # hosts: home_servers (oldsrv) → common→ai_diag→docker→network→storage→nut(client)→cockpit→[amd_rocm,desktop,office,proxmox]→docker_services→home_assistant(standby)
│   ├── raspberry_pi.yml             # hosts: raspberry_pi → common→ai_diag→network→nut(client)→docker→home_assistant(render-first, HD-185)→docker_services→monitoring
│   ├── dns.yml                      # Cloudflare public-record runs (roles/cloudflare_dns)
│   ├── render-docs.yml              # renders generated docs from group_vars (Ansible path)
│   ├── render-routeros.yml          # renders RouterOS bootstrap .rsc (secrets) → gitignored IaC/router/rendered/
│   └── all.yml                      # hosts: all:!router:!localhost — /etc/hosts sync
├── group_vars/
│   ├── all/                          # directory fragments — Ansible loads these, a sibling all.yml would be SHADOWED
│   │   ├── main.yml                  # Timezone, locale, NTP, domain names; infra vars (network/IP/WG/livebox)
│   │   └── versions.yml              # Docker image version pins (ALL hosts, HD-156) — one-file Renovate review
│   ├── network.yml                   # router+switch shared connectivity/auth (ansible_host derived from SSOT)
│   ├── router.yml                   # WG peers, DNS forwarding; VLAN map = derived view of group_vars/all/main.yml network_vlans
│   ├── switch.yml                   # switch ports/VLANs (switch_vlans derives from network_vlans, HD-200)
│   ├── vps.yml                      # docker_services list (VPS edge tier)
│   ├── home_servers.yml             # homelab_mode, docker_services list (oldsrv core), GPU config
│   ├── raspberry_pi.yml             # HA install method/version pin, Pi docker_services (technitium-secondary etc.)
│   └── subscriptions.yml            # subscriptions SSOT (drives subscription.md render + renewals)
├── host_vars/
│   ├── oldsrv.kogler.si.yml         # homelab_mode=desktop, static IP
│   ├── nas.kogler.si.yml            # HP MicroServer Gen8 — ZFS storage
│   ├── vps.kogler.si.yml            # netcup RS 2000 G12 (bought 2026-08-18)
│   └── pi.kogler.si.yml             # Static IP, SSH user (node; ha.kogler.si = VIP)
├── roles/                            # full catalog = ls roles/ (count derived, never hand-entered)
│   ├── common/tasks/                # system.yml + main.yml
│   ├── ai_diag/                     # ai-debug diagnostics dispatcher + sudoers
│   ├── docker/tasks/main.yml        # Docker CE + compose install
│   ├── network/tasks/main.yml       # VLAN interfaces, /etc/hosts
│   ├── storage/                     # ZFS pools/datasets/sanoid/syncoid/NFS/Samba/push timers (nas + oldsrv)
│   ├── nut/                         # UPS: master (nas) + clients (oldsrv, pi) — host-level, no Docker
│   ├── cockpit/                     # management UI + file-provider Traefik routes (HD-188)
│   ├── cifs/                        # VPS live-Box CIFS mount
│   ├── wireguard/                   # WG S2S VPS side (router peer lives in roles/router) — netdev + `wg-ensure-s2s-peer` oneshot (HD-306: networkd never applies the peer; a peer-only `wg setconf` re-attaches it after networkd init)
│   ├── cloudflare_dns/              # public-record runs (vars/main.yml = IaC side of the record SSOT)
│   ├── vps-hardening/tasks/main.yml # HD-154: VPS pre-deploy hardening — fail2ban, nftables default-deny, docker daemon (public edge only)
│   ├── amd_rocm/tasks/main.yml      # AMD ROCm, udev, OLLAMA_KEEP_ALIVE
│   ├── desktop/tasks/main.yml       # XFCE/GNOME, display manager, Xorg dual-GPU config
│   ├── office/tasks/main.yml        # ONLYOFFICE, MS fonts, OpenCloud client
│   ├── router/                      # RouterOS api_modify: VLANs, DHCP, firewall, CAPsMAN, Kids rules, address lists
│   ├── switch/                      # CRS328 trunk/access port map via api_modify
│   ├── proxmox/tasks/main.yml       # Proxmox bridges, storage, VMs (Phase 2 stub)
│   ├── home_assistant/tasks/main.yml# HA primary (Pi) + standby (oldsrv) + keepalived VIP + failover trigger
│   ├── docker_services/             # THE key role — generic service deployer (+ prepass-authentik)
│   └── monitoring/tasks/main.yml    # Alloy → Prometheus + Loki; Grafana + alerting; blackbox; HA exporter
└── templates/
    ├── docker_services/             # docker-compose.yml.j2 per service
    ├── homepage_services.yaml.j2
    ├── homepage_widgets.yaml.j2
    ├── inventory.md.j2
    └── nut/                         # nut.conf.j2, ups.conf.j2, upsd.users.j2, upsmon.conf.j2, upssched.conf.j2
```

### ansible-core 2.24 readiness (HD-271)

`ansible.cfg` sets `inject_facts_as_vars: false` (the default True is deprecated and removed
at core 2.24): tasks must reference facts via `ansible_facts['service_mgr']` (never bare
`ansible_service_mgr`). The two WireGuard pubkey lookups in `group_vars` use `lookup('vars',
'<key>', default='')` — previously they guarded with `'key' in vars`, but the internal `vars`
dict is itself deprecated at 2.24 (verified live in core 2.21.3: the membership check still
emits `[DEPRECATION WARNING] The internal "vars" dictionary is deprecated`; the deprecation
help text prescribes the `vars`/`varnames` **lookups** instead). The `default=''` fallback
preserves the fail-closed load-time empty value. A runtime `assert` in the wireguard/router
roles still fails-closed on a blank peer at deploy — so `default=''` here does NOT violate
HD-65's no-`default('')` rule, which applies to **1Password secret lookups**; these pubkeys are
structural vars with a "provision at deploy" lifecycle (the repo's own `vps.yml` gate + role
asserts already use `| default('')` on them).

---

## Inventory

```ini
[router]
router.kogler.si

[switch]
switch.kogler.si

[network:children]
router
switch

[vps]
vps.kogler.si

[home_servers]
oldsrv.kogler.si              # bare-metal Debian desktop + Docker host

[storage]
nas.kogler.si                 # HP MicroServer Gen8 — ZFS storage (NO Docker)

[raspberry_pi]
pi.kogler.si                  # HA primary node (ha.kogler.si = VIP)

[docker_hosts:children]
vps
home_servers

[monitoring]
oldsrv.kogler.si              # collector — forwards home telemetry to VPS
vps.kogler.si                 # backend host — Prometheus/Loki/Grafana

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

---

## Host Vars

### oldsrv.kogler.si.yml
```yaml
homelab_mode: desktop            # "desktop" or "proxmox" or "headless"
ansible_host: 10.10.99.30        # Management VLAN 99 static IP
home_ip: "{{ oldsrv_home_ip }}"  # Home VLAN 10 — node IP (VRRP anchor); SSOT-derived (HD-200)
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

> **Canonical list:** `docker_services` (with `enabled`/`instance`/`subdomain`/`template_dir`
> modifiers and per-host gates) lives only in [`group_vars/home_servers.yml`](../IaC/ansible/group_vars/home_servers.yml)
> — derived data, never re-typed in docs (CONVENTIONS §2). Post-HD-135, oldsrv keeps the
> **GPU / LAN / storage-bound core** (ollama, immich-ml, technitium-primary, pihole,
> home-assistant-standby, signal-cli-rest-api, sunshine [desktop-gated], jellyfin + seerr
> + the *arr stack, kopia-agent); the public edge, public apps, AI stack, observability backend and
> n8n live on the VPS (`group_vars/vps.yml`). Human catalog: [`services.md`](services.md).

Non-derived reference values that DO belong here (host-agnostic GPU config):

```yaml
# GPU config
amd_rocm_version: "6.3"
gpu_render_group: render
gpu_video_group: video
```

---

## Group Vars: all/

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

### `vps-hardening`  *(HD-154 — VPS public edge only, mandatory pre-deploy)*
- **Scope:** VPS-only hardening role run **before** `docker_services` in `playbooks/vps.yml` (the VPS is the single public trust boundary — `security.md` §8).
- **fail2ban:** SSH jail (`maxretry 3`) + `http-auth` jail for public login pages; installed + enabled.
- **nftables:** `/etc/nftables.conf` (template) — input policy `drop`; allow `:443` + `:51820` (WG S2S) + loopback + established/related; forward allows docker bridges only.
- **Docker daemon:** `daemon.json` — `iptables: true`, `userland-proxy: false`, `live-restore: true`, capped json-file logs.
- **sshd assert:** `PasswordAuthentication no` / `PermitRootLogin no` / `MaxAuthTries 3` present (post_install.sh supplies; role asserts + fail-loud).
- **Idempotency:** lineinfile asserts + file copies; handlers restart fail2ban/nftables/docker on change.
- **Secrets:** None.

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

### `storage` (roles/storage — data model SSOT: [`storage.md`](storage.md))
- **Hosts:** nas (ZFS + NFS server) and oldsrv (`nvme` data pool + fstab mounts + push timers)
- Installs `zfsutils-linux`, `sanoid`, `syncoid`; **imports** pools — `tank`/`bulk` on nas, `nvme` on
  oldsrv (never re-creates; pools are self-describing); creates datasets with the properties from
  `storage.md`; templates `sanoid.conf`;
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

### `router`
- **Method:** REST API (preferred) or templated `.rsc` push
- **Configs:** VLAN interfaces, DHCP, firewall, WireGuard, CAPsMAN, DNS forwarding

### `docker_services` (Key Role)
- **Input:** `docker_services` list from group vars
- **Authentik OIDC pre-pass (HD-162):** a dedicated pre-pass (`tasks/prepass-authentik.yml`),
  run **before** the deploy loop on hosts where `authentik` is in `docker_services` (the VPS
  edge), applies the `ks-oidc.yml` Blueprint + runs the **secret-egress glue** to seed client
  creds into the 1Password OIDC items (`openwebui_api`…`metabase_oidc`, 8 providers). The
  **OpenCloud Graph-API service account** (`opencloud-service_api`) is **NOT** the glue's job
  — it is provisioned by the `sync-authentik-users` rework (**HD-145**). The pre-pass is
  gated on `authentik` presence via `when:`, so home hosts (home_servers / raspberry_pi)
  skip it entirely; the assert inside is a safety net that should never fire.
  Ordering: `authentik` → blueprint+glue → OIDC consumers. Fail-closed on a missing
  `authentik-provision_api` (HD-65/91). See [`deployment-oidc.md`](deployment-oidc.md)
  and [`services-authentik.md`](services-authentik.md).
- **Loop:** each enabled service:
  1. Skip if `enabled: false`
  2. Create `/opt/{{ item.name }}/`
  3. Template `docker-compose.yml.j2` → `/opt/{{ item.name }}/docker-compose.yml`
  4. Template extra config files from same template dir
  5. **Validate the rendered compose file** (`docker compose -f <svc>/docker-compose.yml
     validate`) — catches a bad render before `up` (HD-162)
  6. `docker compose up -d` (systemd unit `docker-compose@{{ item.name }}`)
- **Post-deploy:** Template Homepage config, inventory docs, reload Homepage, commit to Git
- **Tags:** Each service task tagged with `{{ item.name }}`
- **Bulk 1Password pre-pass (HD-258 — deploy speed):** each `community.general.onepassword`
  `lookup()` spawns the `op` CLI on the control node (≈160 spawns per VPS converge across
  compose/extras templates + `deploy-service.yml` guards + `monitoring` + role defaults).
  Batch them: one pre-pass fetches the **needed item set once** (`delegate_to: localhost`,
  `run_once`, `no_log`) into a `vault: {<name> -> {username,password,credential}}` dict, then
  renders read from the dict instead of re-invoking `op` per template:
  ```yaml
  - name: Fetch all vault items once
    ansible.builtin.shell:
      cmd: op item get "{{ item }}" --vault "{{ op_vault }}" --format json
    loop: "{{ op_items_needed }}"
    register: op_items
    no_log: true
    changed_when: false
  ```
  then `vault: {...}` via `set_fact`, and templates/guards switch from
  `lookup('community.general.onepassword', ...)` to `{{ vault['headscale_api'].username }}` etc.
  **Fail-closed contract (HD-91/HD-65) must hold:** no `default('')`, assert the backend is up,
  assert every needed name resolves (absent name → loud failure). Do it **incrementally per
  template_dir** — each service's render switches to the dict; the dict is populated only for
  names that exist. Expected: tens of seconds off each full converge, seconds off surgical runs.
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
| 7 | `home_assistant` (Pi primary + oldsrv standby + keepalived VIP `10.10.1.200`) + Pi `docker_services` (`technitium-secondary`, `traefik-ha` edge for `ha` + `dns-pi`) — on the Pi, `home_assistant` runs BEFORE `docker_services` (render-first, HD-204 — supersedes the KOPS-063/HD-117 order) | `docker` |
| 8 | `nut` — nas: master (usbhid-ups + upsd + nut_exporter); oldsrv/ha: client (upsmon slave + upssched + notifycmd) | `common`, `network` |
| 9 | `monitoring` (incl. Grafana alerting rules + SMTP) | `docker_services` (Prometheus/Loki/n8n up) **and** `nut` (needs nut_exporter) |
| 10 | `router` | `network` (IPs/VLANs defined) |
| 11 | `proxmox` (Phase 2) | `network` |

---

## Deploy Timing Runbook (HD-269, Step f — measured)

> **Role:** where the speed budget lives. These are **measured** numbers from the live full
> converge (`vps.yml`, 2026-08-28, log `/tmp/fullconverge2.log`, `profile_tasks` enabled by
> `ansible.cfg`). Re-measure with `ansible-run.sh playbooks/vps.yml` — the same run that
> regenerates this page — whenever a change claims to affect deploy time.

### Full-converge baseline (measured 2026-08-28)

| Metric | Value | Notes |
|--------|-------|-------|
| Wall accumulate (TASKS RECAP) | **~193s (3:13)** | `profile_tasks` cumulative; ≈ wall. Prior baseline ~204s (2026-08-27) |
| Result | `ok=311 changed=45 failed=0 skipped=381` | idempotent converge, no functional change |
| Slowest glue | **Authentik secret-egress 11.94s** | was ~21-22s; parallel win (HD-269) |
| 2nd | **LiteLLM bootstrap-keys 8.07s** | **serial** (reverted 2026-08-28); paid only on the `litellm` pass |
| 3rd | **op-vault-export (derive) 4.62s** | bulk 1P read; scoped runs ≈0.8s |

### Measured cost ledger (TASKS RECAP, 2026-08-28)

Top tasks by elapsed time:

| Task | Elapsed | Lane |
|------|---------|------|
| `docker_services : Run Authentik secret-egress glue` | **11.94s** | glue · parallel (win) |
| `docker_services : Run LiteLLM bootstrap-keys glue (litellm)` | **8.07s** | glue · serial |
| `docker_services : Run op-vault-export (derive mode)` | **4.62s** | pre-pass · parallel read |
| `docker_services : Register Authentik OIDC source (Forgejo)` | 2.77s | docker_services |
| `cifs : Write CIFS credentials file` | 2.75s | **base tier** |
| `docker_services : Copy template files for traefik` | 2.51s | docker_services |
| `docker_services : Template extra .j2 for traefik` | 2.24s | docker_services |
| `docker_services : Copy template files for headscale` | 2.00s | docker_services |
| `docker_services : Template extra .j2 for headscale` | 1.80s | docker_services |
| `monitoring : Provision Grafana alert contact points` | 1.78s | monitoring |
| `common : Update apt + install prerequisites` | 1.74s | **base tier** |
| `docker_services : Deploy provision token (op)` | 1.71s | docker_services |
| `docker_services : Create external networks` | 1.68s | docker_services |
| `docker : Install Docker components` | 1.59s | **base tier** |
| `docker_services : compose up authentik` | 1.57s | docker_services |
| `vps-hardening : Install fail2ban` | 1.57s | **base tier** |
| `docker_services : Copy template files for prometheus` | 1.55s | docker_services |
| … | ~1.4s each | remainder ≈150 tasks under 1s |

### The three deploy-speed mechanisms (when to use each)

1. **`docker_services_scope` (HD-255/260/269)** — TRUE surgical run of one/many services; the
   op pre-pass drops to ~0.8s + only the named service iterates. Use for a single-service fix.
2. **`--tags base` (HD-269 Step 4)** — run ONLY the rare bootstrap tier
   (`common`/`docker`/`hardening`/`network`/`cifs`/`wireguard`) as one unit. Use for a rare infra
   change; excludes all docker_services/monitoring.
3. **Parallel glue (HD-269)** — authentik egress is `xargs -P` (11.94s vs 21-22s); litellm stays
   **serial** — the `docker exec -i` heredoc probe can't be fanned out (see §Tags & surgical).

### Expected timing map

```
Full converge                       ~193s   (baseline ~204s)
├─ base tier (common/docker/…/wg)    ~8s      (--tags base)
├─ op glue (3 loops)                ~25s     (authentik 11.9 + litellm 8 + derive 4.6)
├─ docker_services core loop         ~most   (copy/template/up per ~28 services)
└─ monitoring / other                few s
```

A surgical single-service run (`--tags docker_services -e docker_services_scope=<svc>`) is
**~5-6s**; a base-tier run (`--tags base`) avoids the docker_services/monitoring cost entirely.
Deploy times drift with image versions/service count — re-measure per the top of this page.
`profile_tasks` prints the recap to every run; keep it in `ansible.cfg` (it's the arbitrage tool
for any future speed change, HD-257).