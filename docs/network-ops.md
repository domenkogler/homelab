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
7. **Which `find` predicates actually match on RouterOS 7 (HD-322 live lessons, 2026-09-03):**
   - ✅ `/ip address find where interface=X` — `address=` does **NOT** match the stored CIDR (empty even for an existing row)
   - ✅ `/ip dhcp-server network find where gateway=X` — `address=` does **NOT** match
   - ✅ `/ip firewall address-list find where list=X` (and `list=X and address=Y`)
   - ✅ `/interface bridge port find where interface=X`, `/interface vlan find where name=X`, `/interface bridge vlan find where vlan-ids=N and dynamic=no`, `/ip pool find where name=X`, `/ip dhcp-server find where name=X`, `/ip route find where dst-address=X`, `/interface wireguard peers find where interface=X`, `/user find where name=X`, `/interface bridge find where name=X`
   - ❌ `/ip firewall filter find where dst-address=CIDR` — empty (use `comment=`)
8. **Inline `# comments` inside `:if do={ }` blocks break the parser (HD-322, 2026-09-03):** a `asdf # comment` on a guarded `/add`/`/set` line inside an `:if`/`else` block errors with `expected end of command`. Put the comment on its own line above; never inline `#` within a block body.
9. **Bootstrap-only steps must guard on the file existing (HD-322, 2026-09-03):** `/user ssh-keys import public-key-file=admin.pub` fails on a steady-state re-import because the bootstrap `.pub` files are gone from `/file` (cleaned after flash bootstrap). Guard `:if ([/file find where name=admin.pub] != "") do={ … }`.
10. **Chain-reset sections are inherently idempotent; address-lists are not.** `/ip firewall nat remove [find chain=…]` / `/ip firewall filter remove [find chain=…]` make NAT/forward/input re-imports land exactly once. But `/ip firewall address-list` has NO reset — a re-import STACKS duplicates (fixed HD-322: `remove [find list=trusted-admin]` / `trusted-ha` / `internal_lan` first).

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
- **Rotating the shared admin password (HD-321, 2026-09-03):** the rotation follows the repo-native **render → `/import`** flow, NOT a manual device-by-device SSH script. Procedure: (1) update `mikrotik-admin_login` in 1Password — set **`old-password`** = current live value, **`password`** = new value (vault = SSOT; every converge/`initial` template reads `password`). (2) Re-render `render-converge.yml` + `render-routeros.yml` so every `IaC/router/rendered/*.rsc` embeds the NEW password; **delete any stale rendered `ap_initial.rsc`** (legacy universal AP script — per-AP `ap_initial-*.rsc` are current) and any converge `.rsc` left on a device after a partial `/import`. (3) Apply the converge (or a `user set admin password` delta) per device via `scripts/routeros-apply-delta.sh` / `apply-converge.yml` (SSH `ansible` identity, pinned host key; the API `/import` step needs `librouteros` in the runner — if missing use the SSH-import path). (4) **Verify from a Mgmt-sourced API path** (e.g. the Pi's tagged-99 hop): old password must FAIL, new must authenticate — testing from a non-Mgmt source (the laptop's Home IP) is INPUT-dropped and reads as a false lockout. (5) At the **next bootstrap reset**, re-upload the re-rendered `initial` `.rsc` files (`rb4011_initial.rsc` / `crs328_initial.rsc` / `ap_initial-*.rsc`) to each device's `flash/` so a flash-bootstrap sets the NEW password. `ansible` is a key-only automation user (`group=full`, password unused) and is unaffected by the rotation.

---

## Central log shipping (HD-313) — RouterOS logs → VPS CrowdSec + Loki

The RB4011 forwards its logs as **RFC5424 syslog over the `wg-s2s` tunnel** to the VPS;
CrowdSec parses them for failed-login +
port-scan detection and the same stream is available to Loki for central search.

> **Deploy-gate IaC status (2026-09-03→04):** convergence fixes + acquisition wiring landed —
> the `central-syslog` → `centralsyslog` action-name typo (was the rule-creation error on
> converge), the `acquis-routeros.yml` copy into the CrowdSec **config mount**
> (`/srv/docker/crowdsec/config/acquis.d/` — the compose-dir extra-template copy was dead,
> CrowdSec reads acquisitions from `acquis.d/` only), and the VPS Alloy
> `loki.source.file`/`loki.process.routeros` push (`routeros.log` → Loki, `job=routeros-syslog`).
> **Live session 2026-09-04:** router side APPLIED + VERIFIED live (action `centralsyslog`
> `remote={{ wg_s2s_vps.ip }}:514 src-address={{ wg_s2s_vps.router_ip }}`, rules 6–9, `logpipe` user — all on-device
> via the Pi-99 hop); VPS side APPLIED (rsyslog `{{ wg_s2s_vps.ip }}:514` active, acquis in config
> mount, CrowdSec restarted, Alloy re-rendered with `routeros_syslog`). **Two IaC gaps found +
> fixed this session:** ① the router/switch roles' `routeros_api_password` `set_fact` was
> untagged → ANY surgical `--tags` router/switch converge failed on an undefined password;
> tagged it `always` in both roles (the HD-161 identity assert is `always`). ② the VPS
> vps-hardening nftables input (default-deny) had **no allow for UDP/514 from the router wg
> peer** → rsyslog bound the address but the input policy silently dropped every syslog
> packet; added `iifname "wg-s2s" ip saddr {{ wg_s2s_vps.router_ip }} udp dport 514 accept`
> (SSOT-derived, live-verified in the ruleset).
>
> **⚠ BLOCKED (end-to-end log flow, live session 2026-09-04):** with the config correct + live
> on BOTH ends, the RB4011 (RouterOS 7.24.1) **emits ZERO UDP/514 packets** — verified via
> router sniffer (`/tool sniffer quick interface=wg-s2s ip-protocol=udp port=514`), live
> listeners on the VPS wg address across ports 514/1514, multiple action variants (custom
> `centralsyslog` AND the canonical default `remote` action, `remote-log-format=default`/`syslog`,
> `src-address` set/unset, iso8601, `:log info` synthetic events), all while `/log print` shows
> the events in memory. This matches the reported RouterOS 7.18–7.24 remote-syslog **egress
> bug family** on RB4011/RB5009 (forum.mikrotik.com: "no packets on port 514 although syslog
> server reachable"; one user's workaround = re-add the action config, another = IP-vs-hostname;
> MikroTik confirmed a 7.17+ FQDN-related regression and said a fix is pending). Config alone
> cannot close this gate; pending: RouterOS upgrade/re-add workaround on the device, then
> re-verify end-to-end. Switch/AP forwarding stays future work (CRS328 has no wg tunnel).

- **RouterOS side (router role, `router-logging` tag):** `/system logging action centralsyslog`
  (`target=remote`, `remote=<vps wg-s2s address>:514` — SSOT `wg_s2s_vps.remote_ip`, `src-address=wg-s2s`),
  plus `/system logging` rules forwarding topics `error` (login/API failures — the a1ad parser requires
  it), `firewall` (drops → port-scan scenario), `critical`, `warning` → `centralsyslog` (RouterOS 7
  action-name rule: letters+numbers only — `central-syslog` is rejected, live-probed 2026-09-03).
  `src-address` ties the source to the wg-s2s interface (Mgmt-plane only; never WAN). Fail-loud: any
  missing SSOT value aborts the render.
- **Scoped `logpipe` API user (r/o, `read` group):** created by the role with the `mikrotik-logpipe_api`
  1Password credential; only the Mgmt plane reaches it. Reused later by the n8n firmware window
  (HD-312d) for the temp `iot-wan-allow` list toggles.
- **Receiver (monitoring role, `routeros-syslog` tag, VPS only):** `rsyslog` UDP/514 on the **wg-s2s VPS
  address** (SSOT `wg_s2s_vps.local_ip`) accepts RFC5424 from the router peer only and writes
  `/var/log/remote-syslog/routeros.log`. rsyslog is installed by the monitoring role (the
  netcup minimal image does NOT ship it — 2026-09-03 live fix).
- **CrowdSec (docker_services `crowdsec` service):** compose binds `/var/log/remote-syslog` (ro); the
  `acquis-routeros.yml` (monitoring role → `config/acquis.d/`, VPS-only) tells CrowdSec to tail the
  file as `type: mikrotik`. `crowdsec_collections` gains **`a1ad/mikrotik`** (parser + `mikrotik-bf` +
  `mikrotik-scan-multi_ports` scenarios) — the upstream-blessed remote-syslog pattern.
  ⚠ Live lesson: the acquis must live in the **config mount's `acquis.d/`** (`/etc/crowdsec/acquis.d/`
  in-container) — a compose-dir extra-template copy is dead; CrowdSec never reads it.
- **Loki (search surface):** the VPS Alloy tails `/var/log/remote-syslog/routeros.log`
  (`loki.source.file "routeros_syslog"` + `loki.process.routeros`, `job=routeros-syslog`) → Loki (14d);
  Grafana the query surface — no second log backend.
- **Deploy-gated:** the RB4011-side `system/logging` + `logpipe` user land at the next router
  converge; the VPS-side rsyslog (live), CrowdSec acquis + Alloy re-render land at the next
  `monitoring` converge (+ surgical crowdsec re-render). **Switch/AP forwarding** is a documented
  future expansion: the CRS328 has no wg tunnel and the rsyslog receiver only accepts the router wg
  peer — a routed path (receiver LAN-source allow or a switch-side tunnel) is needed before enabling
  them. See [observability.md](observability.md) and [services-traefik.md](services-traefik.md) §CrowdSec.

---

## Incident: 2026-09-02 — router mgmt plane lost after a full router.yml converge (recovered)

> **Symptom:** after the 20:08 `router.yml` re-converge (added nas/oldsrv DHCP reservations), the router's
> management plane became unreachable from the Pi's tagged-99 leg: the router mgmt IP (SSOT
> [`network-addresses-generated.md`](network-addresses-generated.md) → `router`) ARP FAILED on `eth0.99` and
> the API/SSH reset. Home ICMP to the router worked but TCP services refused (`available-from` mgmt-subnet
> lockdown, HD-301). WinBox from the laptop still worked.

**Root cause (evidence):** the converge's `changed` tasks included *Enable VLAN filtering on bridge* and
*Ensure bridge-lan bridge exists* — same two were `ok` (unchanged) in every prior dry-run. Re-asserting the
bridge after a converge left VLAN-99's tagged memberships missing on the Pi's port (ether10), so the mgmt
plane's only real client (Pi `eth0.99`) lost the router; the mgmt IP answered ICMP on the untagged plane.

**Recovery (idempotent delta, no secrets):**
```
# render from SSOT (secret-free template):
bash scripts/ansible-run.sh playbooks/render-converge.yml   # or ad-hoc render of rb4011_pi_delta
# import in WinBox terminal (or /import the file):
/import rb4011_pi_delta.rsc
```
The delta re-sets `vlan-99 tagged=bridge-lan,sfp-sfpplus1,ether2,ether10 untagged=ether7,ether9` + correct
`pvid` on ether10 — matching `router_port_map` / `rb4011_converge.rsc.j2`. Verified live: Pi `eth0.99` →
router mgmt IP (SSOT [`network-addresses-generated.md`](network-addresses-generated.md) → `router`) 0% loss,
ARP REACHABLE, API via Pi-hop tunnel works, nas/oldsrv reservations bound.

**Lesson (fold into apply workflow):** a full `router.yml` converge can disturb bridge VLAN memberships on the
mgmt plane. Prefer **surgical deltas** for mgmt-plane-sensitive changes, and keep `rb4011_pi_delta.rsc.j2`
as the canonical idempotent recovery (always re-render before use — it is SSOT-derived).

---

## Incident: 2026-09-03 — tagged-99 mgmt plane CLUSTER-WIDE DOWN (router SSH down on both legs) — RESOLVED 2026-09-03

> **Symptom (found during oldsrv Phase-3 prep):** the entire tagged-99 Management plane is unreachable at the
> host level. From the Pi's `eth0.99` (verified working 2026-09-02) — SSOT `router` (mgmt), `switch` (mgmt),
> `ups` (mgmt) rows are **all ARP-FAILED**; router mgmt SSH via the Pi-hop (`router99`) fails
> `No route to host`; the **router's SSH is DOWN on BOTH legs**: the router's Home row → `kex_exchange_identification:
> read: Connection reset by peer`, Mgmt row → unreachable. ICMP on Home works (router up on the untagged
> plane), but TCP services refuse (`available-from` = Mgmt-only lockdown, HD-301). oldsrv's new tagged Mgmt leg
> also ARP-FAILED against the router — consistent: **no device can reach any other device on the
> tagged-99 plane** right now.

**Scope:** this is a **second occurrence** of the 2026-09-02 mgmt-plane loss (see incident above), now
cluster-wide. Both times the tagged-99 leg stopped delivering frames after a **full `router.yml`/converge**
changed bridge VLAN memberships on the mgmt plane. The difference: 2026-09-02 the Pi still had WinBox + one
tagged leg; now the whole plane (router + switch + UPS + all tagged clients incl. the Pi) is dark.

**Root cause hypothesis:** a converge (the 2026-09-03 full `router.yml` run, or the Pi/Technitium-homepage
lanes' bridge touching) left the **router's VLAN-99 tagged memberships missing/incomplete on the tagged legs**
(rb4011 converge rsc expects `vlan-99 tagged=bridge-lan,sfp-sfpplus1,ether2,ether10`). That matches the
09-02 pattern exactly. The switch (CRS328) L2-only has no mgmt path to inspect remotely right now.

**Recovery (idempotent delta, no secrets — same as 09-02, re-render first):**
```
bash scripts/ansible-run.sh playbooks/render-converge.yml   # or ad-hoc render of rb4011_pi_delta.rsc
# import in WinBox terminal (or /import the file) — MUST be a path that still reaches the router
/import rb4011_pi_delta.rsc     # re-sets vlan-99 tagged=bridge-lan,sfp-sfpplus1,ether2,ether10 + pvid ether10
```
Window for the router: **only via the Home leg or laptop/WinBox** — the SSH service is Mgmt-only and Mgmt is
dark. After recovery, verify `router99` and every mgmt client ARP before continuing Phase 3/4.

**RESOLUTION (2026-09-03):** confirmed via WinBox — the root-cause hypothesis was correct. The vlan-99 bridge
entry had `ether10` (and `ether2`) in the **UNTAGGED** column instead of **TAGGED** (a stale/broken converge
had flipped them to untagged access ports), so the Pi's **tagged** Mgmt frames on `eth0.99` were dropped before
the router saw them → ARP FAILED → entire tagged-99 plane appeared dark. The fix (`/interface bridge vlan
set [find where vlan-ids=99 and dynamic=no] tagged=bridge-lan,sfp-sfpplus1,ether2,ether10
 untagged=ether7,ether9`) restored TAGGED on ether2/ether10 → mgmt-plane back: Pi → router mgmt ping 0% loss,
ARP REACHABLE, router99 SSH + API over the Pi hop work. The `rb4011_pi_delta.rsc` import did NOT apply its
vlan-99 block (comment/state mismatch) — the manual one-liner was the effective recovery. A later full
`router.yml` converge (same session) re-applied and verified the tagged memberships + KNX rule live.
PERMANENT FIX: the converge-template/role vlan-99 memberships are correct (tagged=ether2,ether10); the
broken state came from a prior partial converge — monitor the first converge after any future bridge change.
