# Worker Prompt — Homelab Router & Switch Ansible Roles

You are an autonomous implementation agent. Execute **two related tasks** in the
Kogler Homelab repo. Read the Context first, then the two Task specs, then
implement. Work from the repo root: `D:/source/domenkogler/homelab` (git-bash on
Windows 11; python launcher is `python`). Follow the repo's existing Ansible
conventions and the SSOT model.

---

## 0. Context you must understand before writing code

The homelab is being **rebuilt from scratch**. Network Phase 1 is split into two halves:

1. **Bootstrap (DONE, committed)** — minimal RouterOS scripts, now rendered from
   `.j2` templates with secrets injected from 1Password at render time. These
   bring router, switch, and APs to a *minimal management (VLAN 99) plane* so
   Ansible can reach them. See `IaC/router/README.md`.
2. **Ansible takes over (YOUR WORK)** — the `router`/`switch` roles that turn the
   minimal bootstrap into the full network (VLANs, firewall, DHCP, CAPsMAN, WG).

> **Golden rule:** Ansible is the source of truth for the *full* config; the
> bootstrap only establishes management reachability. All static IPs/VLANs must
> come from `group_vars/all.yml` (SSOT), never hardcoded. Secrets come from
> 1Password at run time, never committed.

### Where the desired end-state is defined (READ THESE FIRST)

| Purpose | Path |
|---------|------|
| IP / VLAN / host SSOT (single source of truth) | `IaC/ansible/group_vars/all.yml` |
| Router-specific vars (API port, VLAN map, WG, DNS) | `IaC/ansible/group_vars/router.yml` |
| Router bootstrap template (shows the intended RouterOS end-state style) | `IaC/router/templates/rb4011_initial.rsc.j2` |
| Switch bootstrap template (desired switch VLAN/trunk/PoE) | `IaC/router/templates/crs328_initial.rsc.j2` |
| AP bootstrap template (AP DHCP reservations doc) | `IaC/router/templates/ap_initial.rsc.j2` |
| RouterOS config lifecycle / storage doc | `docs/network-ops.md` |
| Network redo design (VLAN table, firewall matrix, port types) | `docs/network-vlans.md` |
| DNS topology (Technitium on oldsrv/Pi) | `docs/network-dns.md` |
| Role catalog / conventions & the `router` role section | `docs/deployment-ansible.md` |
| Secret item catalogue | `docs/deployment-secrets.md` |

### Hard constraints & conventions

- **No secrets in the repo.** Use the `community.general.onepassword` lookup
  exactly as in `IaC/ansible/test-1password.yml` and
  `IaC/ansible/playbooks/render-routeros.yml` (vault = `op_vault: Homelab`).
- **No hardcoded IPs.** Derive every address from `network_vlans`/
  `network_static_hosts` in `group_vars/all.yml` (SSOT).
- **Idempotent + non-destructive.** Never sever the running Ansible session.
- **Guard role entry** — every host role asserts `ansible_user in
  ansible_admin_users` (see `IaC/ansible/roles/network/tasks/main.yml` for the
  pattern). `ai-debug` must never run these.
- **Ansible collections:** `IaC/ansible/requirements.yml` currently installs
  `community.general`. You will add the **`community.routeros`** collection for
  RouterOS config and document/install it.
- Follow the platform env note (Windows host, `python` launcher, LF, UTF-8
  no-BOM) and keep edits consistent, not pixel-perfect.

---

## Task A — Implement the `router` role

**File to fill in:** `IaC/ansible/roles/router/tasks/main.yml` (currently an
empty stub: `# router role — TODO: implement`). Add `defaults/main.yml`,
templates/vars as needed.

### A1. Connection & auth (resolve + document your choice)

The bootstrap creates an **`ansible` user (SSH-key only, empty password)** and
**`admin`** (password + key) on the router. `group_vars/router.yml` sets
`routeros_api_port: 8728`.

- Recommended: connect with the **`community.routeros`** collection, device `router.kogler.si`.
- **Auth decision to resolve:** `community.routeros` authenticates over the
  RouterOS API (username+password), but the `ansible` user is key-only. Decide
  and document one of:
  1. Use SSH-key auth (preferred — aligns with the key-only bootstrap), or
  2. If API/password is required, authenticate as `admin` using
     `mikrotik-admin_login` from 1Password.
- Update `inventory.ini` (`[router]`) and/or `ansible.cfg` with the chosen
  connection + `ansible_user`, and add the collection to `requirements.yml`.

### A2. Config to apply (from `group_vars/router.yml` + `all.yml` SSOT)

Build the full RouterOS config, using the router bootstrap template as the
intended-style reference:
1. **VLAN interfaces** — the `vlans` list in `router.yml` (10/20/21/30/40/50/99),
   gateways from `network_static_hosts` (SSOT).
2. **Per-VLAN DHCP** — pools/servers/networks from `network_vlans` (subnet+pool).
   DNS handed to clients = `dns_primary_ip` (10.10.1.30) + `dns_secondary_ip`
   (10.10.1.20). See the bootstrap template's DHCP block + `docs/network-dns.md`.
3. **Firewall** — the inter-VLAN matrix from `docs/network-vlans.md`:
   address-lists `trusted-admin`/`trusted-ha`, default-deny inter-VLAN, DNS to
   Technitium, UPS web 80/443 (`10.10.99.9`), NAT masquerade.
4. **CAPsMAN SSIDs** — 5 SSIDs from `network_vlans[...].ssid`, `local-forwarding=no`.
   ⚠️ WPA2 passphrases are secrets — add/propose a 1Password item (e.g.
   `wifi_login` or per-SSID) and read via `onepassword`. If not yet available,
   leave the CAPsMAN block commented with a clear TODO + exact secret items needed.
5. **WireGuard** S2S → VPS — from `wireguard_s2s_vps` in `router.yml`, private key
   from `wg_password` (1Password). VPS peer may be deferred (Phase 10) — leave
   commented if so.
6. **AP static DHCP leases** — one reservation per AP in `network_static_hosts`
   that has a `mac` (ap-garage/spalnica/dnevna) → its `ip`. Use the SSOT loop.

### A3. Deliverables (Task A)
- `roles/router/tasks/main.yml` (+ `defaults/main.yml`, templates) implementing the above, idempotent.
- `requirements.yml` updated with `community.routeros`.
- `inventory.ini` / `ansible.cfg` connection + auth fix.
- Document any open items (CAPsMAN secret item, VPS WG peer) as comments in the role.

---

## Task B — Add the switch to Ansible

The switch (CRS328, `10.10.99.2`, VLAN 99 mgmt) is **L2** — currently absent from
Ansible entirely. A flat/L2-only switch + VLANs on the router = broken segmentation
(see the bootstrap README), so the switch must carry VLANs/trunk/PoE.

### B1. Inventory
- Add a `[switch]` group to `inventory.ini`: `switch.kogler.si` with the right
  connection/auth (same `community.routeros` approach as Task A; IP from SSOT
  `network_static_hosts` → `10.10.99.2`).

### B2. Switch config role
Create `IaC/ansible/roles/switch/` (or a shared `network` subtask) that applies:
1. **VLAN filtering** bridge over all ports — mirror the switch bootstrap template
   (`crs328_initial.rsc.j2`).
2. **Trunk** = `sfp-sfpplus1` (uplink to router) carrying all VLANs tagged.
3. **Access ports** per the Port Type Reference in `docs/network-vlans.md`
   (device→VLAN: Home 10, IoT 20, IoT-Internet 21, Guest 30, Kids 40, Media 50,
   Management 99), using the physical port map in
   `docs/assets/Rack.canvas` (APs/CPUs/panels). Keep it config-driven; if the
   physical port→VLAN map is not fully decided, implement the trunk + mgmt now
   and leave the per-port map as a clearly-marked var (in `group_vars`) the human
   finalizes.
4. **PoE** on the ports that power APs (see canvas).
5. **Management stays** on `10.10.99.2` (VLAN 99) — never break reachability.

### B3. Deliverables (Task B)
- `[switch]` in `inventory.ini`.
- A `switch` role (or network subtask) implementing VLANs/trunk/access/PoE/mgmt,
  idempotent, driven by SSOT vars.
- Per-port VLAN/PoE map as `group_vars` data (finalize or clearly mark TODO for
  the human).

---

## Validation (do all you can)

- `python -c "import yaml"` sanity; run `python` YAML parse on all edited `.yml`.
- `ansible-playbook --syntax-check playbooks/router.yml -i inventory.ini`
- `ansible-playbook --syntax-check playbooks/site.yml -i inventory.ini`
- If devices are reachable/credentials available, run with `--check`/`--diff`
  first, then against a single host. Do **not** push destructive config to live
  gear without being asked — prefer `--check`/dry-run and report.
- `python scripts/check_doc_ips.py` must pass (no new bare internal IP literals
  outside the generated SSOT doc) if you touch docs.

## Report back
Summarize: what you implemented (files changed), the connection/auth decision
you made + why, any open items (CAPsMAN secret item, VPS WG peer, per-switch-port
map to finalize), and the exact validation commands you ran + their output.
Do **not** commit — leave changes staged/unstaged for the human to review.
