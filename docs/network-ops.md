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

> **Apply model (decided 2026-09-01):** RouterOS config is **authored in Jinja templates (IaC, single SSOT)** and **deployed by importing a rendered `.rsc`** — NOT by driving `api_modify` command-by-command for day-to-day changes. The API path is used only for **idempotent, order-independent state** (DHCP reservations, firewall lists the role owns) and for **verification** (`api_facts`/`api`), never as the primary apply for multi-step changes.

### The three tiers (roles + when each is used)

1. **`*_initial.rsc` — the one-time MANUAL bootstrap** (`rb4011_initial.rsc.j2`, `crs328_initial.rsc.j2`, `ap_initial.rsc.j2`). Factory-reset / first-boot: creates users (incl. the `ansible` SSH identity), uploads SSH keys, binds mgmt services, sets the INPUT firewall floor. **Manual by design** — it hands the device over to automation. After it runs once, you never need it again.
2. **`*_converge.rsc` — the SSOT "full" steady-state** (`rb4011_converge.rsc.j2` → `rendered/rb4011_converge.rsc`). The complete final device state. **Independent of the initial script** (self-sufficient on its own after a reset) and **idempotent** (every `/add` guarded — safe to re-import live at any time). **From the moment initial hands over, converge is the single source of truth / the apply for everything.** A change = edit the converge template → render → import.
3. **`*_delta.rsc` — TRANSIENT only** (`*_delta.rsc.j2` → `rendered/*_delta.rsc`). A **quick patch / debug / test**, or an operator-scoped live fix with a bounded blast radius. **Always a subset of the converge (never divergent truth), and its final state must be folded back into the converge** so the converge stays the SSOT. Deltas may be deleted once folded.

> **Name note:** `converge` is the "full" script. A rename to `full` was considered (2026-09-01) but **rejected** to avoid churn across ~25 files + tooling; the **concept** of converge=full is what matters, and it's stated here.

### Lifecycle in practice

1. **Factory reset / true baseline** → import the **rendered** `rb4011_initial.rsc` via WinBox (`run-after-reset=` or `/import`). The committed file is the TEMPLATE `rb4011_initial.rsc.j2`; render with `playbooks/render-routeros.yml` (secrets-injected output into the gitignored `rendered/`). **Never import the raw `.j2`.**
2. **Initial hands over → Ansible + converge take over.** All subsequent config = **edit the converge template → render → /import** (the universal apply).
3. **Deltas** are allowed for quick patch/debug/fix, but **final state lands in converge** (fold the delta in, then it's obsolete).
4. **Optional:** export a manual snapshot as `IaC/router/rb4011_live.rsc` for documentation (not yet created).

Source of truth: the **Jinja templates** (`rb4011_{initial,converge}.rsc.j2`; deltas are transient) + the `router` Ansible role. The live export is documentation-only.

### Apply workflow (imports)

- **Render from SSOT:** `bash scripts/ansible-run.sh playbooks/render-converge.yml` renders `rb4011_converge.rsc` (+ `crs328_converge.rsc`); any `*_delta.rsc.j2` renders to `IaC/router/rendered/` the same way. Rendered files are **gitignored** (they contain live secrets from 1Password).
- **Apply via SSH (ansible identity, pinned host key)** — the sanctioned non-WinBox path. **Automated (HD-309):** `bash scripts/routeros-apply-delta.sh <router-ip> <delta-file>` performs key pull + parse-verify + host-key pin + SCP + `/import` in one step (see [scripts/README.md](../scripts/README.md)). Manual equivalent (the classic loop it replaces):
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
  - **Key-extraction note (live 2026-09-01):** use `op read` (canonical, clean PEM), NOT `op item get --reveal` piped through shell — the latter emits an inconsistent leading `"`/`\n` wrapper that corrupts the key file and surfaces as OpenSSH's cryptic `error in libcrypto`. `routeros-apply-delta.sh` uses `op read` and verifies the key loads (ssh-keygen) before touching the device.
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
4. **Converge = the universal apply; delta = transient.** The converge is the full idempotent SSOT — a change goes into the converge template, not a persistent delta. A delta is a quick patch/debug that must be folded back in; don't keep deltas as a parallel long-term truth.
5. **Secrets stay out of the repo.** The rendered `.rsc` (with `mikrotik-admin_login`, `pppoe_login`) is gitignored; the template has Jinja placeholders resolved at render. Never commit/`cat`/grep rendered files.
6. **Every rsc change needs a counterpart in the SSOT** (the template) — the rendered file is a view, never hand-edited.

### Why this model (2026-09-01)

`community.routeros.api_modify` / `command` are **order- and state-sensitive**: partials, has `can not change dynamic`, needs `librouteros` in the exact interpreter, and framings for `/import` are unreliable. A single imported `.rsc` applies many commands as one atomic-ish set — much easier, reproducible, and reviewable (the diff is the template). The **API remains for verification + idempotent state**; the **rsc import is the apply**.

### Ordering pitfall — a new FORWARD accept must sit ABOVE the default-deny (live 2026-09-01)

RouterOS evaluates `chain=forward` **top-down**. A rule appended to the END of the forward
chain lands **below** the "Default deny inter-VLAN" row (the repo's forward chain keeps the
default-deny mid-list, before the Comtrend/WAN tail) — so an accept added at the tail is
**shadowed**: the deny already dropped the packet. HD-307 hit this live: the first delta
import left "Mgmt -> Home" at rule #33 while the deny sat at #25 (never matched).
Fix pattern:
```
/ip firewall filter remove [find where chain=forward and comment="<new-rule>"]   # dedup
/ip firewall filter add chain=forward action=accept … comment="<new-rule>"
:local r [/ip firewall filter find where chain=forward and comment="<new-rule>"]
:local d [/ip firewall filter find where chain=forward and action=drop and comment="Default deny inter-VLAN"]
/ip firewall filter move $r destination=$d     # RouterOS 7 `move … destination=` places BEFORE
```
**Always verify position after a delta apply** (`/ip firewall filter print where chain=forward`)
— a rule that exists but sits below the default-deny is dead weight and reads as "working".


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
