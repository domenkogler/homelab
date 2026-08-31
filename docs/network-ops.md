---
title: Network Operations — Router Config Storage
role: detail
domain: network
status: active
tags: [network, routeros, ops]
---
# Network Operations — Router Config Storage

> **Role:** Detail — where RouterOS configuration lives, versioning, change workflow.
> **Links to:** `network.md`, `network-vlans.md`
> **Linked from:** `network.md`, `index.md`

---

## Router Config Lifecycle

> **Apply model (decided 2026-09-01):** RouterOS config is **authored in Jinja templates (IaC, single SSOT)** and **deployed by importing a rendered `.rsc`** into the device — NOT by driving `api_modify` command-by-command for day-to-day changes. The API path is used only for **idempotent, order-independent state** (DHCP reservations that already exist, firewall lists the role owns) and for **verification** (`api_facts`/`api`) — never as the primary apply mechanism for multi-step changes.

1. **Factory reset / true baseline** → import the **rendered** `IaC/router/rendered/rb4011_initial.rsc` via WinBox (`run-after-reset=`, or `/import`). The committed file is the TEMPLATE `IaC/router/templates/rb4011_initial.rsc.j2`; render it with `playbooks/render-routeros.yml` (secrets-injected output into the gitignored `rendered/` dir). **Never import the raw `.j2`**.
2. **Steady-state apply = import a rendered `.rsc`** (converge or delta, below):
   - **Full converge** (`IaC/router/templates/rb4011_converge.rsc.j2` → `rendered/rb4011_converge.rsc`) — the complete final state, self-sufficient after a reset. **Not for routine incremental changes** (many `/add` lines duplicate-abort live, see Authoring below).
   - **Delta** (`IaC/router/templates/*_delta.rsc.j2` → `rendered/*_delta.rsc`) — a **small, idempotent** set of `/set` + guarded `/add` operations for one change (e.g. `rb4011_pi_delta.rsc`). **This is the default for a new change.**
3. **Ansible `router` role** remains the **SSOT renderer + verifier**: it renders/validates the templates, applies idempotent state it owns (DHCP static reservations, firewall address-lists), and **verifies** live state (`api_facts`/`api`). It does **not** re-drive the multi-step bridge/VLAN mutations that a delta-import handles.
4. **Optional:** after manual WinBox changes, export a snapshot as `IaC/router/rb4011_live.rsc` for documentation (not yet created).

Source of truth: the **Jinja templates** (`rb4011_{initial,converge,delta}.rsc.j2`) + the `router` Ansible role. The live export is documentation-only.

### Apply workflow (imports)

- **Render from SSOT:** `bash scripts/ansible-run.sh playbooks/render-converge.yml` renders `rb4011_converge.rsc` (+ `crs328_converge.rsc`); any `*_delta.rsc.j2` renders to `IaC/router/rendered/` the same way. Rendered files are **gitignored** (they contain live secrets from 1Password).
- **Apply via SSH (ansible identity, pinned host key)** — the sanctioned non-WinBox path:
  ```bash
  # pin the router's CURRENT host key (rotated at reset; TOFU):
  ssh-keyscan -T 5 -t ed25519,rsa <router-ip> > /tmp/router_hostkeys.txt
  ssh-keygen -lf /tmp/router_hostkeys.txt   # verify the fingerprint
  # upload + import:
  scp -i <ansible-key> -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/tmp/router_hostkeys.txt \
      IaC/router/rendered/rb4011_pi_delta.rsc ansible@<router-ip>:/rb4011_pi_delta.rsc
  ssh  … ansible@<router-ip> '/import rb4011_pi_delta.rsc'
  ```
  - The `ansible` SSH identity (bootstrap-created, full group) is used; `admin` is password-only (never used for automation).
  - **Host-key pinning is mandatory** (the router rotated keys at every reset) — never `StrictHostKeyChecking=no` on a live edge.
- **Verify live state** afterward via the read-only API (`api_facts`, `mikrotik-read.py`) — never assume the import applied.

### Rsc authoring conventions (the rules that make imports safe)

1. **Idempotent by default.** Every `/add` must be guarded so re-import never duplicate-aborts the whole script:
   ```text
   :if ([/interface bridge vlan find where vlan-ids=10 and dynamic=no] = "") do={
       /interface bridge vlan add …
   } else={
       /interface bridge vlan set [find where vlan-ids=10 and dynamic=no] …
   }
   ```
   The guard must target **static** entries (`dynamic=no` for bridge-vlan/lease) — dynamic auto-created entries can't be `set` (live 2026-09-01: `can not change dynamic`).
2. **Never `set` a dynamic object.** DHCP leases and bridge-vlans that the router auto-creates are dynamic; guard static-only, and **add a static reservation** (it takes precedence) rather than mutating the dynamic one.
3. **Order matters.** Import runs top-to-bottom and **aborts at the first error**. Put `/set` (safe, idempotent) before `/add`; put the least-risky, most-reversible changes first; keep the change self-contained so a failure leaves a clear, bounded state.
4. **Delta over converge for routine changes.** A converge rsc is for resets; a delta is a bounded change. Don't re-import a full converge to make one change — it will hit unrelated duplicate-aborts.
5. **Secrets stay out of the repo.** The rendered `.rsc` (with `mikrotik-admin_login`, `pppoe_login`) is gitignored; the template has Jinja placeholders resolved at render. Never commit/`cat`/grep rendered files.
6. **Every rsc change needs a counterpart in the SSOT** (the template) — the rendered file is a view, never hand-edited.

### Why this model (2026-09-01)

`community.routeros.api_modify` / `command` are **order- and state-sensitive**: partials, has `can not change dynamic`, needs `librouteros` in the exact interpreter, and framings for `/import` are unreliable. A single imported `.rsc` applies many commands as one atomic-ish set — much easier, reproducible, and reviewable (the diff is the template). The **API remains for verification + idempotent state**; the **rsc import is the apply**.


## Service Binding & INPUT Firewall (HD-78 / HD-83)

- **Bootstrap (HD-83 / KOPS-003/042):** in `rb4011_initial.rsc.j2` every management service
  (`api`, `www-ssl`, `ssh`) is **bound to the Management VLAN interface** (`interface=vlan{mgmt}-mgmt`)
  so none listens on WAN or any other VLAN during the bootstrap window. Plain `www` (HTTP) and
  `api-ssl` (no TLS cert yet) are left disabled.
- **Bootstrap-window binding floor (B4):** EVERY bootstrap template (`rb4011`, `crs328`, `ap`) must
  bind management services to the Management interface/bridge **from the first line of device
  uptime** — the rb4011 template above is the canonical pattern; no template may enable an unbound
  management service. The crs328/ap templates are aligned to this floor by **HD-193** before the
  Phase 1.5 cutover.
- **Steady-state INPUT chain (HD-78 / KOPS-003/009):** Ansible router role adds `chain: input` rules so
  the management service ports (`22,8728,8729,8291,80,443`) are reachable **only from the Management
  VLAN (99) and `trusted-admin` hosts** (nas/oldsrv/ha-vip); the ports are dropped from every other
  source. Established/related and DHCP input remain accepted so the control plane, clients and the
  deferred WireGuard/VRRP links keep working.
- **Assert-before-mutate (HD-161):** both the router and switch Ansible roles start with a `community.routeros.api_facts` read of `/system identity` and assert the target matches the per-gear `routeros_expected_identity` from `group_vars/` (fail-loud — a blank identity aborts). This runs **once per role run**, before any `api_modify`, so a wrong-target or swapped-host can never receive config meant for another device.
- **Router API TLS (HD-161 Part B):** the management API is moved to **`api-ssl` (:8729) with a self-signed device cert** and `validate_certs: false` in Ansible — TLS encryption on a private Mgmt-VLAN link, **no public CA / no Let's Encrypt dependency**. Enabled via the role (cert creation + `api-ssl` enable), then plaintext `api` (:8728) retired by a manual WinBox cutover. See `rb4011_initial.rsc.j2` / `crs328_initial.rsc.j2`.
- **Shared RouterOS admin credential (HD-165):** because all management binds to Mgmt-VLAN 99 (above), the **same `mikrotik-admin_login` password is deliberately shared** across RB4011 + CRS328 + APs as an **accepted** risk — it cannot be reached from WAN or any non-Mgmt VLAN. Revisit per-gear items only if a device gains WAN-exposed management or this ACL changes. See [deployment-secrets.md](deployment-secrets.md).
