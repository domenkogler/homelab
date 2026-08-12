# RouterOS Initial Configs

Bootstrap / initial RouterOS scripts for the homelab network gear — the route
**from factory-reset to "Ansible can take over"**.

## Philosophy

- **No secrets in the repo.** Credentials (PPPoE login, MikroTik admin password)
  are **injected from 1Password at render time** — the committed files never
  contain them.
- **No hardcoded IPs.** All static IPs / VLANs come from
  [`IaC/ansible/group_vars/all.yml`](../ansible/group_vars/all.yml) (SSOT) via
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
| `crs328_initial.rsc`, `ap_initial.rsc` | (being migrated to templates in follow-up tasks) |

## Workflow

1. **Sign in to 1Password** on the management laptop: `op signin`
2. **Render** the scripts (resolves secrets + IPs from SSOT):
   ```bash
   cd IaC/ansible
   ansible-playbook playbooks/render-routeros.yml -i inventory.ini
   ```
3. **Upload** each rendered `.rsc` + `admin.pub` + `ansible.pub` to the device's
   Files (WinBox or `scp`).
4. **Apply** on each device (the device resets and runs the script):
   ```text
   /system reset-configuration no-defaults=yes run-after-reset=<file>
   ```
5. Bootstrap device up → **Ansible `router` role** connects (user=`ansible`,
   SSH-key auth) and applies the real config.

> Device reset order within Phase 1: **router → switch → APs**, then Ansible.

## Secrets referenced (1Password `Homelab` vault)

| 1Password item | Used for |
|----------------|----------|
| `pppoe_login` | Router egress WAN (Telekom PPPoE) user + password |
| `mikrotik-admin_login` | Admin password on router + switch + APs (shared) |
| `ansible-admin_ssh` / `laptop-domen_ssh` | `ansible.pub` / `admin.pub` SSH keys uploaded alongside |

## Related

- [`docs/deployment-secrets.md`](../../docs/deployment-secrets.md) — secret item catalogue
- [`docs/network-ops.md`](../../docs/network-ops.md) — config lifecycle / versioning
- [`docs/network-addresses.md`](../../docs/network-addresses.md) — generated IP SSOT
