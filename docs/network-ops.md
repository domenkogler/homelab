# Network Operations — Router Config Storage

> **Role:** Detail — where RouterOS configuration lives, versioning, change workflow.
> **Links to:** `network.md`, `network-vlans.md`
> **Linked from:** `network.md`, `index.md`

---

## Router Config Storage

- **Host:** `router.kogler.si` (MikroTik RB4011iGS+)
- `rb4011_initial.rsc` — fresh-start baseline (`IaC/router/rb4011_initial.rsc`)
- Current config exported as `rb4011_config.rsc` → stored in `IaC/router/`
- All config changes via **Ansible** or version-controlled `.rsc` snippets
- Git-versioned in the homelab repo

## Change Workflow

1. Modify `.rsc` snippet / Ansible role in the repo
2. Apply via Ansible `router` role (REST API preferred) or WinBox import
3. Export final config → commit `rb4011_config.rsc` to Git

## Related

- VLAN plan / firewall: [`network-vlans.md`](network-vlans.md)
- Topology & ISP: [`network.md`](network.md)
- AP config: `IaC/router/ap_initial.rsc` (CAP mode)
