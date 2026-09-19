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

> **Apply model:** RouterOS config is **authored in Jinja templates (IaC, single SSOT)** and **deployed by
> importing a rendered `.rsc`** — NOT by driving `api_modify` command-by-command for day-to-day changes.
> The API path is used only for **idempotent, order-independent state** (DHCP reservations, firewall lists
> the role owns) and for **verification** (`api_facts`/`api`), never as the primary apply for multi-step changes.
>
> **⚠️ Role ↔ `.rsc` parity (HD-338):** the `router` Ansible role still contains a handful of `api_modify`
> tasks that mirror converge state (the trunk `interface bridge vlan` task and the port-model
> `interface bridge port` task). These are the **only** places where the role carries day-to-day apply
> logic, and they are a **drift risk**: a role task that silently differs from the template gets
> re-applied on the next role run, or reverted by the next converge — either way the live device state
> depends on which ran last. **Rule: any `api_modify` task that mirrors converge state must stay
> byte-identical to `rb4011_converge.rsc.j2` — edit BOTH or NEITHER.** When in doubt, drop the role task
> and rely on the import. The header of `roles/router/tasks/main.yml` + the two L2 tasks carry this
> warning inline.
>
> **⚠️ Forward-chain ownership (HD-03):** the role's `Ensure inter-VLAN forward firewall rules` task must
> stay **gated off** (`when: false`). It is/was an ungated full-reconcile over `chain: forward`, and the
> live per-MAC rows (the `iot-wan-allow` accepts and the `kids-*` tablet bedtime/DoT drops) exist **only**
> in the converge template — a live role run would DELETE them. Related invariant: the apply-of-record
> template (`rb4011_converge.rsc.j2`) must carry the same narrowed scopes as the role SSOT — e.g. the
> Home→IoT new-connection rule is `trusted-ha`, never `trusted-admin`, or a converge silently
> re-broadens it to include `nas`.

### The three tiers (roles + when each is used)

1. **`*_initial.rsc` — the one-time MANUAL bootstrap** (`rb4011_initial.rsc.j2`, `crs328_initial.rsc.j2`, `ap_initial.rsc.j2`). Factory-reset / first-boot: creates users (incl. the `ansible` SSH identity), uploads SSH keys, binds mgmt services, sets the INPUT firewall floor. **Manual by design** — it hands the device over to automation. After it runs once, you never need it again.
2. **`*_converge.rsc` — the SSOT "full" steady-state** (`rb4011_converge.rsc.j2` → `rendered/rb4011_converge.rsc`). The complete final device state. **Independent of the initial script** (self-sufficient on its own after a reset) and **idempotent** (every `/add` guarded — safe to re-import live at any time). **From the moment initial hands over, converge is the single source of truth / the apply for everything.** A change = edit the converge template → render → import.
3. **`*_delta.rsc` — TRANSIENT only** (`*_delta.rsc.j2` → `rendered/*_delta.rsc`). A **quick patch / debug / test**, or an operator-scoped live fix with a bounded blast radius. **Always a subset of the converge (never divergent truth), and its final state must be folded back into the converge** so the converge stays the SSOT. Deltas may be deleted once folded.

> **Name note:** `converge` is the "full" script. A rename to `full` was considered and **rejected** to
> avoid churn across ~25 files + tooling ([network-rejected.md](network-rejected.md)); the **concept** of
> converge=full is what matters, and it is stated here.

### Lifecycle in practice

1. **Factory reset / true baseline** → import the **rendered** `rb4011_initial.rsc` via WinBox (`run-after-reset=` or `/import`). The committed file is the TEMPLATE `rb4011_initial.rsc.j2`; render with `playbooks/render-routeros.yml` (secrets-injected output into the gitignored `rendered/`). **Never import the raw `.j2`.**
2. **Initial hands over → Ansible + converge take over.** All subsequent config = **edit the converge template → render → /import** (the universal apply).
3. **Deltas** are allowed for quick patch/debug/fix, but **final state lands in converge** (fold the delta in, then it's obsolete).
4. **Optional:** export a manual snapshot as `IaC/router/rb4011_live.rsc` for documentation (not yet created).

Source of truth: the **Jinja templates** (`rb4011_{initial,converge}.rsc.j2`; deltas are transient) + the `router` Ansible role. The live export is documentation-only.

### Apply workflow (imports)

- **Render from SSOT:** `bash scripts/ansible-run.sh playbooks/render-converge.yml` renders `rb4011_converge.rsc` (+ `crs328_converge.rsc`); any `*_delta.rsc.j2` renders to `IaC/router/rendered/` the same way. Rendered files are **gitignored** (they contain live secrets from 1Password).
- **Apply via SSH (ansible identity, pinned host key)** — the sanctioned non-WinBox path. The device host is its **.99 mgmt IP** (the router's `mgmt` row in [`network-addresses-generated.md`](network-addresses-generated.md)). ⚠ **That is an ON-SITE path only** (the Mgmt plane stays sealed from the VPS site-to-site tunnel, and the `available-from` scoping refuses a tunnel-sourced SSH anyway — [network-rejected.md](network-rejected.md) HD-398) and only when the laptop's Mgmt99 vNIC actually has link (`wsl-nat-resolv.ps1 -EnableMgmt99`). **A timeout there is a missing station path, not a dead router**: check `ip -br addr` in WSL for the VLAN-99 route first. Away from home, router/switch work is **deferred, not improvised** — see [network-vpn.md](network-vpn.md) §Reaching LAN nodes when away. **Automated (HD-309):** `bash scripts/routeros-apply-delta.sh <router-ip> <delta-file>` performs key pull + parse-verify + host-key pin + SCP + `/import` in one step (see [scripts/README.md](../scripts/README.md)). Manual equivalent (the loop it replaces):
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
  - **Host-key pinning is mandatory** (the router rotates keys at every reset) — never `StrictHostKeyChecking=no` on a live edge.
  - **Key extraction:** use `op read` (canonical, clean PEM), NOT `op item get --reveal` piped through shell — the latter emits an inconsistent leading `"`/`\n` wrapper that corrupts the key file and surfaces as OpenSSH's cryptic `error in libcrypto`. `routeros-apply-delta.sh` uses `op read` and verifies the key loads (`ssh-keygen`) before touching the device.
  - **Ansible `copy`-module SCP is NOT RouterOS-safe:** `ansible.builtin.copy` fails with "Destination / not writable" even though raw `scp -i <key> file ansible@<router>:/file` succeeds — the copy module's stat-based writability check is incompatible with RouterOS's pseudo-filesystem (root `/` reports not-writable to stat). **Use `scripts/routeros-apply-delta.sh` (raw scp) for ANY device file upload/import.**
  - **Delta dedup:** importing the same delta twice leaves duplicate rules. They are behaviorally harmless but reconcile only on a full converge — a `--tags network` role run does NOT own the static `ip firewall filter` table, so it will not dedupe them. Remove duplicates via the API by exact `.id` when cleanliness matters.
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
   The guard must target **static** entries (`dynamic=no` for bridge-vlan/lease) — dynamic auto-created entries can't be `set` (`can not change dynamic`).
2. **Never `set` a dynamic object.** DHCP leases and bridge-vlans that the router auto-creates are dynamic; guard static-only, and **add a static reservation** (it takes precedence) rather than mutating the dynamic one.
3. **Order matters.** Import runs top-to-bottom and **aborts at the first error**. Put `/set` (safe, idempotent) before `/add`; put the least-risky, most-reversible changes first; keep the change self-contained so a failure leaves a clear, bounded state.
4. **Converge = the universal apply; delta = transient.** The converge is the full idempotent SSOT — a change goes into the converge template, not a persistent delta. A delta is a quick patch/debug that must be folded back in; don't keep deltas as a parallel long-term truth.
5. **Secrets stay out of the repo.** The rendered `.rsc` (with `mikrotik-admin_login`, `pppoe_login`) is gitignored; the template has Jinja placeholders resolved at render. Never commit/`cat`/grep rendered files.
6. **Every rsc change needs a counterpart in the SSOT** (the template) — the rendered file is a view, never hand-edited.
7. **Which `find` predicates actually match on RouterOS 7 (HD-322):**
   - ✅ `/ip address find where interface=X` — `address=` does **NOT** match the stored CIDR (empty even for an existing row)
   - ✅ `/ip dhcp-server network find where gateway=X` — `address=` does **NOT** match
   - ✅ `/ip firewall address-list find where list=X` (and `list=X and address=Y`)
   - ✅ `/interface bridge port find where interface=X`, `/interface vlan find where name=X`, `/interface bridge vlan find where vlan-ids=N and dynamic=no`, `/ip pool find where name=X`, `/ip dhcp-server find where name=X`, `/ip route find where dst-address=X`, `/interface wireguard peers find where interface=X`, `/user find where name=X`, `/interface bridge find where name=X`
   - ❌ `/ip firewall filter find where dst-address=CIDR` — empty (use `comment=`)
8. **Inline `# comments` inside `:if do={ }` blocks break the parser (HD-322):** a `asdf # comment` on a guarded `/add`/`/set` line inside an `:if`/`else` block errors with `expected end of command`. Put the comment on its own line above; never inline `#` within a block body.
9. **Bootstrap-only steps must guard on the file existing (HD-322):** `/user ssh-keys import public-key-file=admin.pub` fails on a steady-state re-import because the bootstrap `.pub` files are gone from `/file` (cleaned after flash bootstrap). Guard `:if ([/file find where name=admin.pub] != "") do={ … }`.
10. **Chain-reset sections are inherently idempotent; address-lists are not.** `/ip firewall nat remove [find chain=…]` / `/ip firewall filter remove [find chain=…]` make NAT/forward/input re-imports land exactly once. But `/ip firewall address-list` has NO reset — a re-import STACKS duplicates, so remove the list members first (`trusted-admin` / `trusted-ha` / `internal_lan`).

### Why this model

`community.routeros.api_modify` / `command` are **order- and state-sensitive**: partials, `can not change dynamic`, needs `librouteros` in the exact interpreter, and framings for `/import` are unreliable. A single imported `.rsc` applies many commands as one atomic-ish set — much easier, reproducible, and reviewable (the diff is the template). The **API remains for verification + idempotent state**; the **rsc import is the apply**.

### Ordering pitfall — a new FORWARD accept must sit ABOVE the default-deny

RouterOS evaluates `chain=forward` **top-down**. A rule appended to the END of the forward chain lands
**below** the "Default deny inter-VLAN" row (the repo's forward chain keeps the default-deny mid-list,
before the Comtrend/WAN tail) — so an accept added at the tail is **shadowed**: the deny already dropped
the packet. Fix pattern:

```
/ip firewall filter remove [find where chain=forward and comment="<new-rule>"]   # dedup
/ip firewall filter add chain=forward action=accept … comment="<new-rule>"
:local r [/ip firewall filter find where chain=forward and comment="<new-rule>"]
:local d [/ip firewall filter find where chain=forward and action=drop and comment="Default deny inter-VLAN"]
/ip firewall filter move $r destination=$d     # RouterOS 7 `move … destination=` places BEFORE
```

**Always verify position after a delta apply** (`/ip firewall filter print where chain=forward`) — a rule
that exists but sits below the default-deny is dead weight and *reads* as working.

### Mgmt-plane caution (learned by breaking it twice)

A **full `router.yml` converge can disturb bridge VLAN memberships on the Management plane**: re-asserting
the bridge has twice left VLAN-99's **tagged** memberships missing/flipped-to-untagged on the tagged legs
(router `ether2`/`ether10`), which silently kills the whole tagged-99 plane — every mgmt client goes
ARP-FAILED while the router still answers ICMP on the untagged plane, and because `available-from` is
Mgmt-only the router's own SSH/API become unreachable **from every mgmt client at once**. Rules that came
out of it:

- Prefer **surgical deltas** for mgmt-plane-sensitive changes
  ([network-rejected.md](network-rejected.md) full-converge-for-mgmt-plane-changes).
- Keep `rb4011_pi_delta.rsc.j2` as the canonical **idempotent recovery** — always re-render before use
  (it is SSOT-derived). It re-sets `vlan-99 tagged=bridge-lan,sfp-sfpplus1,ether2,ether10` + the correct
  `pvid` on the Pi's port, matching `router_port_map` / `rb4011_converge.rsc.j2`.
- **A delta import can silently skip a block** (comment/state mismatch inside a guard). After recovery,
  verify the memberships in the live device rather than trusting the import, and re-check every mgmt
  client's ARP before continuing work.
- The recovery window when the mgmt plane is dark is **WinBox from the laptop / the Home leg only**.

---

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
- **Steady-state INPUT chain (HD-78 / KOPS-003/009):** the Ansible router role adds `chain: input` rules so
  the management service ports (`22,8728,8729,8291,80,443`) are reachable **only from the Management
  VLAN (99) and `trusted-admin` hosts** (nas/oldsrv/ha-vip); the ports are dropped from every other
  source. Established/related and DHCP input remain accepted so the control plane, clients and the
  WireGuard/VRRP links keep working.
- **Assert-before-mutate (HD-161):** both the router and switch Ansible roles start with a `community.routeros.api_facts` read of `/system identity` and assert the target matches the per-gear `routeros_expected_identity` from `group_vars/` (fail-loud — a blank identity aborts). This runs **once per role run**, before any `api_modify`, so a wrong-target or swapped-host can never receive config meant for another device.
- **Router API TLS (HD-161 Part B):** the management API is moved to **`api-ssl` (:8729) with a self-signed device cert** and `validate_certs: false` in Ansible — TLS encryption on a private Mgmt-VLAN link, **no public CA / no Let's Encrypt dependency**. Enabled via the role (cert creation + `api-ssl` enable), then plaintext `api` (:8728) retired by a manual WinBox cutover. See `rb4011_initial.rsc.j2` / `crs328_initial.rsc.j2`.
- **Shared RouterOS admin credential (HD-165):** because all management binds to Mgmt-VLAN 99 (above), the **same `mikrotik-admin_login` password is deliberately shared** across RB4011 + CRS328 + APs as an **accepted** risk — it cannot be reached from WAN or any non-Mgmt VLAN. Revisit per-gear items only if a device gains WAN-exposed management or this ACL changes. See [deployment-secrets.md](deployment-secrets.md).
- **Rotating the shared admin password (HD-321):** the rotation follows the repo-native **render → `/import`** flow, NOT a manual device-by-device SSH script. Procedure: (1) update `mikrotik-admin_login` in 1Password — set **`old-password`** = current live value, **`password`** = new value (vault = SSOT; every converge/`initial` template reads `password`). (2) Re-render `render-converge.yml` + `render-routeros.yml` so every `IaC/router/rendered/*.rsc` embeds the NEW password; **delete any stale rendered `ap_initial.rsc`** (legacy universal AP script — per-AP `ap_initial-<name>.rsc` are current) and any converge `.rsc` left on a device after a partial `/import`. (3) Apply the converge (or a `user set admin password` delta) per device via `scripts/routeros-apply-delta.sh` / `apply-converge.yml` (SSH `ansible` identity, pinned host key; the API `/import` step needs `librouteros` in the runner — if missing use the SSH-import path). (4) **Verify from a Mgmt-sourced API path**: old password must FAIL, new must authenticate — testing from a non-Mgmt source (e.g. a Home IP) is INPUT-dropped and reads as a **false lockout**. (5) At the **next bootstrap reset**, re-upload the re-rendered `initial` `.rsc` files (`rb4011_initial.rsc` / `crs328_initial.rsc` / `ap_initial-<name>.rsc`) to each device's `flash/` so a flash-bootstrap sets the NEW password. `ansible` is a key-only automation user (`group=full`, password unused) and is unaffected by the rotation.

---

## Central log shipping (HD-313) — RouterOS logs → VPS CrowdSec + VictoriaLogs

✅ **LIVE end-to-end.** The RB4011 forwards its logs as **RFC5424 syslog over the `wg-s2s` tunnel** to the
VPS; CrowdSec parses them for failed-login + port-scan detection and the same stream is available to
VictoriaLogs for central search.

- **RouterOS side (router role, `router-logging` tag):** `/system logging action centralsyslog`
  (`target=remote`, `remote=<vps wg-s2s address>:514` — SSOT `wg_s2s_vps.remote_ip`,
  `src-address=wg-s2s`) plus `/system logging` rules forwarding topics `error` (login/API failures — the
  `a1ad` parser requires it), `firewall` (drops → port-scan scenario), `critical`, `warning` →
  `centralsyslog`. RouterOS 7 action-name rule: **letters+numbers only** — `central-syslog` is rejected by
  the device. `src-address` ties the source to the wg-s2s interface (Mgmt-plane only; never WAN).
  Fail-loud: any missing SSOT value aborts the render.
- **WireGuard AllowedIPs gotcha (the reason this class of failure is invisible):** WireGuard **silently
  drops any inner packet whose source IP is not in the peer's `AllowedIPs`**. The syslog packets are
  sourced from the **router's own tunnel address** (`wg_s2s_vps.router_ip`), so that /32 MUST be in
  `wg_s2s_vps.allowed_ips` (`group_vars/all.yml`, the single SSOT consumed by both tunnel sides per
  HD-200) — otherwise the tunnel looks perfectly healthy (handshake + big transfer counters, all `10.10.*`
  traffic flowing) while every log packet dies inside the tunnel. **Re-render the VPS `wg-s2s.conf` and
  re-run the `wg-ensure-s2s-peer` oneshot whenever that list changes.** Diagnosing this class needs a
  synchronized test: router-side `/tool sniffer quick interface=wg-s2s ip-protocol=udp port=514` **and** a
  listener on the VPS wg address — packets visible on one side only localizes the drop.
- **Scoped `logpipe` API user (r/o, `read` group):** created by the role with the `mikrotik-logpipe_api`
  1Password credential; only the Mgmt plane reaches it. A dedicated `n8n` scoped read-only user
  (HD-312(4), `mikrotik-n8n_api` item) follows the same pattern and stays provisioned for admin use (the
  n8n firmware workflow itself is superseded — [network-vlans.md](network-vlans.md) §CAPsMAN).
- **Receiver (monitoring role, `routeros-syslog` tag, VPS only):** `rsyslog` UDP/514 on the **wg-s2s VPS
  address** (SSOT `wg_s2s_vps.local_ip`) accepts RFC5424 from the router peer only and writes
  `/var/log/remote-syslog/routeros.log`. Notes: the **netcup minimal image does NOT ship rsyslog** (the
  monitoring role installs it); the VPS default-deny nftables input needs an explicit
  `iifname "wg-s2s" ip saddr <router wg address> udp dport 514 accept`, otherwise rsyslog binds the
  address and the input policy silently drops every syslog packet.
- **CrowdSec (docker_services `crowdsec` service):** compose binds `/var/log/remote-syslog` (ro); the
  `acquis-routeros.yml` (monitoring role → `config/acquis.d/`, VPS-only) tells CrowdSec to tail the file as
  `type: mikrotik`. `crowdsec_collections` carries **`a1ad/mikrotik`** (parser + `mikrotik-bf` +
  `mikrotik-scan-multi_ports` scenarios) — the upstream-blessed remote-syslog pattern.
  ⚠ The acquis must live in the **config mount's `acquis.d/`** (`/etc/crowdsec/acquis.d/` in-container) —
  a compose-dir extra-template copy is never read by CrowdSec.
- **VictoriaLogs (search surface):** the VPS Alloy tails `/var/log/remote-syslog/routeros.log`
  (`loki.source.file "routeros_syslog"` + `loki.process.routeros`, `job=routeros-syslog`) → VictoriaLogs (90d);
  Grafana is the query surface — no second log backend.
- **Role/runner gotcha:** the router/switch roles' `routeros_api_password` `set_fact` must stay tagged
  `always` — otherwise any surgical `--tags router`/`--tags switch` converge fails on an undefined
  password (the HD-161 identity assert is `always`).
- **Retained safety net:** a `/system script` + startup scheduler (`fixsyslog`) on the RB4011 re-applies the
  `centralsyslog` action target 10s post-boot (toggle remote → back). Harmless, self-healing insurance if
  RouterOS ever fails to (re)init the action on boot; the converge template folds it in.
- ⏳ **Future expansion — Switch/AP log forwarding:** the CRS328 has no wg tunnel and the rsyslog receiver
  accepts only the router's wg peer; a routed path (receiver LAN-source allow or a switch-side tunnel) is
  needed before enabling them. See [observability.md](observability.md) and
  [services-traefik.md](services-traefik.md) §CrowdSec.

---

## CAPsMAN steady-state contract (`wifi-qcom-ac`) — HD-232 / HD-308 / HD-312

> The imperative apply procedure lives in [deployment-manual.md](../deployment-manual.md) §1.5.4; this is the
> **why**, so a future change does not re-derive it from a broken WLAN. Every item below was learned by breaking
> the live network.

1. **The manager has to be enabled.** `/interface wifi capsman set enabled=yes` is the FIRST line of the rendered
   steady-state. Config objects existing is not enough: with the manager at `enabled=no` no AP ever provisions, and
   the symptom is "APs not functioning" with a clean-looking config.
2. **wifi-qcom-ac CAPs cannot honour `datapath vlan-id`.** Configs use a named datapath `DP_AC` (bridge-lan, **no**
   vlan-id). The per-SSID VLAN rides the CAP's **bridge** instead: pvid on the provisioned slave interface + the
   uplink `ether1` tagged.
3. **Radios must be told to be CAPs.** Each radio needs `configuration.manager=capsman` + `disabled=no`, and the CAP
   needs `slaves-static=yes` (carried by `ap_initial.rsc.j2`). A bare `cap set enabled=yes` leaves the radio a
   locally-configured master that never joins — the `MBX` state.
4. **AP identities are descriptive and rendered per AP** (`ap-spalnica`, `ap-dnevna`, `ap-spare`) via
   `ap_initial-<name>.rsc`; do not hand-name them on the device.
5. **Three SSIDs, band-split by provisioning rule** (HD-312): `Kogler` (both bands), `Kogler IOT`
   (**2.4 GHz only**), `Kogler guest` (**5 GHz only**) — expressed as `band:` per SSID in the
   `routeros_capsman_ssids` SSOT. The extra per-purpose SSIDs are deleted (their configs and security profiles
   are gone; kids control became firewall MAC rules) — [network-vlans.md](network-vlans.md) §CAPsMAN.
6. **The switch must carry the wifi VLANs tagged on the AP ports.** An AP port that is only an untagged VLAN-99
   access drops the CAP's per-SSID tagged frames at switch ingress: clients associate, never get DHCP ("phone
   disconnects"). Encoded in `wifi_ports` (`group_vars/switch.yml`) + the converge rsc — ether11/ether12 carry
   10+20+30 tagged.
7. **A new slave SSID does not materialize on a provisioning change alone.** After adding a slave to a rule, kick
   the manager (`enabled=no` then `=yes`) so each CAP re-pulls and creates the slave interface, then add the bridge
   VLAN entry (`/interface bridge vlan add vlan-ids=<v> tagged=ether1 untagged=<slave>`) and the port pvid. See
   `ap_guest_delta.rsc.j2` for the guarded, idempotent form.
8. **Flash persistence:** the `.pub` files and anything else that must survive a reboot go under `flash/` on the
   switch and the APs — files written at device root are wiped on reboot (HD-304). RB4011 root is fine.

VLAN landing per SSID: `Kogler` → 10, `Kogler IOT` → 20, `Kogler guest` → 30.
