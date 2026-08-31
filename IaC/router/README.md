# RouterOS Initial Configs

Bootstrap / initial RouterOS scripts for the homelab network gear — the route
**from factory-reset to "Ansible can take over"**.

## Philosophy

- **No secrets in the repo.** Credentials (PPPoE login, MikroTik admin password)
  are **injected from 1Password at render time** — the committed files never
  contain them.
- **No hardcoded IPs.** All static IPs / VLANs come from
  [`IaC/ansible/group_vars/all/main.yml`](../ansible/group_vars/all/main.yml) (SSOT) via
  Jinja templates.
- **Minimal bootstrap only.** These scripts establish the **Management VLAN 99**
  plane (static gateway + DHCP for temporary hosts) so Ansible can connect.
  Everything else (full VLANs, firewall, DHCP per VLAN, CAPsMAN SSIDs,
  WireGuard) is configured by the **Ansible `router` role** afterwards.

## Layout

| Path | Content |
|------|---------|
| `templates/*.rsc.j2` | Jinja2 source templates (**source of truth**, committed) |
| `rendered/*.rsc` | Generated output — **gitignored**, never committed |

Scripts rendered: `rb4011_initial.rsc` (router), `crs328_initial.rsc` (switch), and
`ap_initial.rsc` (a **universal** AP script — all APs).

## Workflow

1. **Sign in to 1Password** on the management laptop: `op signin`
2. **Render** the scripts (resolves secrets + IPs from SSOT):
   ```bash
   cd IaC/ansible
   ansible-playbook playbooks/render-routeros.yml -i inventory.ini
   ```
3. **Upload** each rendered `.rsc` + the 2 `.pub` files to the device's
   Files (WinBox or `scp`). **Flash-persistence rule (HD-304):** on the switch
   and APs the `.pub` files MUST be placed in the `flash/` folder — files in the
   device **root** are wiped on reboot, and the `/user ssh-keys import` runs
   post-reset from `flash/`. The RB4011 boots off flash and is immune, so its
   `.pub` files stay in root. The rendered bootstraps import
   `public-key-file=flash/admin.pub` / `flash/ansible.pub` on switch+APs.
   ```text
   /system reset-configuration no-defaults=yes run-after-reset=<file>
   ```
5. Bootstrap device up → **Ansible `router` role** connects (user=`ansible`,
   SSH-key auth) and applies the real config.

> Device reset order within Phase 1: **router → switch → APs**, then Ansible.

## AP addressing (no per-AP static IP)

APs get a **static DHCP reservation** from the router (MAC → Management IP), so one
universal `ap_initial.rsc` is enough — the AP just DHCPs on VLAN 99. The reservations
are added by the **Ansible `router` role** (not the router template). AP → IP mapping
(SSOT, `network_static_hosts`):

| AP | MAC | IP |
|----|-----|-----|
| ap-spalnica | `C4:AD:34:42:F1:7D` | per `network_static_hosts` (all.yml) |
| ap-dnevna | `C4:AD:34:42:F0:B9` | per `network_static_hosts` (all.yml) |
| ap-spare | (TBD) | per `network_static_hosts` (all.yml) |

> **ap-garage REMOVED 2026-08-30:** ☠️ wAP ac DEAD 2026-08-24 (hardware fault) — removed from
> the canvas + `network_static_hosts` + `switch_port_map` (Phase 1.5 prep); CRS328 `ether1` is
> now EMPTY. Any future replacement gets a fresh AP entry + PoE port config.

## Secrets referenced (1Password `Homelab-ansible` vault)

| 1Password item | Used for |
|----------------|----------|
| `pppoe_login` | Router egress WAN (Telekom PPPoE) user + password |
| `mikrotik-admin_login` | Admin password on router + switch + APs (**shared — accepted, HD-165**); every RouterOS mgmt surface binds to Mgmt-VLAN 99 only → never reaches the internet |
| `ansible-admin_ssh` / `laptop-domen_ssh` | `ansible.pub` / `admin.pub` SSH keys uploaded alongside |

## Related

- [`docs/deployment-secrets.md`](../../docs/deployment-secrets.md) — secret item catalogue
- [`docs/network-ops.md`](../../docs/network-ops.md) — config lifecycle / versioning
- [`docs/network-addresses-generated.md`](../../docs/network-addresses-generated.md) — generated IP SSOT
