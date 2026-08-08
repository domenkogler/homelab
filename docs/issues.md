---
title: Known Issues & Out-of-Scope Follow-ups
role: detail
domain: meta
status: active
tags: [meta, issues, backlog]
---
# Known Issues & Out-of-Scope Follow-ups

> **Role:** Scratchpad for inconsistencies and follow-ups **not** handled in the
> current session's change. Each entry is scoped, so a future session can pick
> one up without re-deriving context. Do **not** put resolved items here.
> **Linked from:** `index.md`

---

## I1 — Road-warrior WireGuard subnet conflict
- **Area:** `network-vpn.md` / IaC router
- **Symptom:** `IaC/ansible/group_vars/router.yml` declares
  `wireguard_roadwarrior.subnet: "10.99.0.0/24"`, but `IaC/router/rb4011_initial.rsc`
  configures the road-warrior interface as `10.255.50.1/24`. `docs/network-vpn.md`
  also references travel-router `10.99.99.0/31` for the (obsolete) travel device.
- **Likely fix:** pick one address space for road-warrior (10.99.0.0/24 vs
  10.255.50.0/24) and align router.yml with the rsc; keep travel `10.99.99.0/31`
  clearly separate.
- **Priority:** medium · **Status:** open

## I2 — `network-dns.md` firewall wording contradicts Home-based DNS
- **Area:** `network-dns.md` / `network-vlans.md`
- **Symptom:** After this session, DNS primary/secondary now bind **Home** node IPs
  (`10.10.1.30` oldsrv, `10.10.1.20` pi), but `network-dns.md` still says "allow DNS
  from all user VLANs to Technitium on the **Management VLAN (99)**" and relies on
  "no inter-VLAN rule is needed" (old Mgmt placement). The MikroTik forward rules
  in `rb4011_initial.rsc` also only permit DNS toward the **gateways**, not toward
  the Technitium Home addresses. Related `rb4011_initial.rsc` drift from
  `network-vlans.md`: the `Home→Mgmt` forward rule only opens `22,8291,80,443` from
  **all** Home (no `502` UPS Modbus, no `8728`, no trusted-host restriction), and the
  `Home→IoT`/`Home→IoT-Internet` rules allow **only the VIP** (`10.10.1.200`) because
  `trusted-ha` is the sole address-list entry (the rsc even notes "Debian PC address
  added later") — so `oldsrv`/`nas`/`10.10.1.30` cannot reach IoT or manage the UPS
  per the doc's rules.
- **Likely fix:** rewrite the DNS reachability/firewall prose to the Home-based
  resolver addresses and decide whether clients/other VLANs resolve via the router
  (gateway forward) or directly to `10.10.1.30/.20` (add forward rules); align the
  `rsc` `Home→Mgmt` (add 502/8728, restrict to trusted hosts) and `Home→IoT`
  (add oldsrv/nas IPs to a trusted address-list) rules with `network-vlans.md`.
- **See also:** I12 (firewall drift, folded into this entry).
- **Progress (506b856):** `rb4011_initial.rsc` updated — DHCP hands out Technitium
  primary+secondary (Home) + gateway tertiary; forward rules to `10.10.1.30/.20`
  above the inter-VLAN drop; input DNS allowed; `Home→Mgmt` adds 502/8728 restricted
  to `trusted-admin`; `trusted-ha` extended to nas/pi/oldsrv. `network-dns.md` /
  `network-vlans.md` rewritten to the Home-based model. Config NOT yet deployed to
  the live router / verified.
- **Priority:** high (correctness) · **Status:** implemented in IaC/docs · **pending deploy/verify** · open

## I3 — Several IaC roles are still "TODO: implement" (SSOT model is aspirational)
- **Area:** `IaC/ansible/roles/`
- **Symptom:** `roles/network/tasks/main.yml`, `roles/docker_services/tasks/main.yml`
  are literally `# TODO: implement`; `roles/home_assistant/tasks/main.yml` is a
  comment-only spec. The "IaC = source of truth, docs generated" model — including
  the new `network-addresses.md.j2` render hook — only becomes real once these roles
  execute. The render step for `network-addresses.md` is not yet wired into the
  post-deploy hook.
- **Likely fix:** implement the roles (esp. `network` for static IP/VLAN provisioning),
  then add the `network-addresses.md` render to the same hook that renders `inventory.md`.
- **Progress (506b856):** the SSOT render is now wired — `playbooks/render-docs.yml`
  renders `docs/network-addresses.md` from `group_vars/all.yml` as the final `site.yml`
  step; `network` role foundation added (admin guard + `/etc/hosts`). Still TODO:
  `docker_services`, `monitoring`, `amd_rocm`, `desktop`, `office`, `router`, `proxmox`,
  the 19 compose templates, and `network` static-IP/trunk provisioning (needs
  networkd-vs-netplan decision).
- **Priority:** high · **Status:** partially addressed · open

## I4 — Cockpit has no Ansible role (scope now decided)
- **Area:** `services.md` / `IaC/ansible`
- **Symptom:** `cockpit-nas.kogler.si` / `cockpit-oldsrv.kogler.si` URLs are documented
  (and now fronted by Traefik), but there is no `cockpit` Ansible role. Session decided
  scope: **nas + oldsrv only**; the Pi does not run Cockpit.
- **Likely fix:** add a `cockpit` role scoped to `nas` + `oldsrv`, subdomains as above.
- **Priority:** medium · **Status:** open

## I5 — Docs↔IaC direction of truth is contradictory
- **Area:** `deployment-ansible.md` / generate pipeline
- **Symptom:** `deployment-ansible.md` is labeled *"generation-target — read this to
  generate Ansible playbooks"* (docs → IaC), but the repo also has an IaC → docs
  render pipeline (`inventory.md.j2`). The session chose **IaC as source of truth**,
  which contradicts the "generation-target" framing of that doc.
- **Likely fix:** update `deployment-ansible.md` framing to reflect IaC-as-source,
  or document the intended direction explicitly so future AI sessions don't ping-pong.
- **Priority:** low · **Status:** open

## I6 — Traefik (`ha` route) depends on cross-host VIP
- **Area:** `services.md` accessibility / `smart-home-failover.md`
- **Symptom:** Traefik runs on oldsrv; HA primary runs on the Pi. The `ha.kogler.si`
  backend is the VIP `10.10.1.200` over the Home VLAN. This works intra-VLAN today,
  but is a hidden coupling: if HA ever leaves the Home VLAN, Traefik's `ha` route
  breaks. Worth an explicit note/runbook reference.
- **Likely fix:** document the coupling in the accessibility SSOT; no code change now.
- **Priority:** low · **Status:** open

## I7 — Hardcoded NTP server in router baseline
- **Area:** `IaC/router/rb4011_initial.rsc`
- **Symptom:** line 18 pins `/system ntp client servers add server=193.2.1.66`.
  Verify this is intentional (vs. a Slovenian pool).
- **Likely fix:** if not intentional, use `0.si.pool.ntp.org` to match `group_vars/all.yml`.
- **Priority:** low · **Status:** open

## I8 — `nut` role referenced by docs but absent from IaC entirely
- **Area:** `deployment-ansible.md` / `observability.md` / `hardware-ups.md` / `IaC/ansible`
- **Symptom:** `deployment-ansible.md`'s file layout lists
  `roles/nut/tasks/main.yml`, `files/upssched-cmd`, and `templates/nut/*.j2`;
  `hardware-ups.md` and `observability.md` route the whole UPS plan (master/client,
  `nut_exporter`, `upssched-cmd` notify) through **"the `nut` Ansible role"**. But
  `IaC/ansible/roles/` has **no `nut` role**, `templates/` has **no `nut/`** dir,
  no playbook invokes it, and `IaC/README.md`'s role catalog omits it. This is a
  *completely missing* role (not just a `TODO: implement` stub like I3's roles).
- **Likely fix:** add a `nut` role (master on nas: `usbhid-ups` + `upsd` +
  `nut_exporter`; clients on oldsrv/ha: `upsmon` slave + `shutdown_delay_seconds`,
  `upssched-cmd` notify) with `templates/nut/*.j2`, wire it into `home_servers.yml`
  / `raspberry_pi.yml` before `monitoring`, and add it to `IaC/README.md`.
- **Progress (506b856):** implement — `roles/nut/` added (master USB-HID + host
  `nut_exporter` on nas, clients oldsrv=60s / ha=0s delays, `upssched-cmd` notify),
  host_vars + play wiring, `IaC/README.md` catalog. Note: `nut_exporter_release` is an
  operator-set var (binary download). PENDING deploy/verify on real hardware.
- **Priority:** high · **Status:** implemented in IaC · pending deploy/verify · open

## I9 — `home_servers.yml` deploys the entire Docker stack onto `nas`
- **Area:** `IaC/ansible/group_vars/home_servers.yml` / `inventory.ini` / `deployment.md`
- **Symptom:** the `home_servers` inventory group contains **oldsrv + nas**, but
  `docker_services` is applied to *every* host in that group. Only `technitium`,
  `raspberrymatic-standby`, `home-assistant-standby`, and `sunshine` are gated by
  `enabled: "{{ inventory_hostname == 'oldsrv…' }}"`; `traefik`, `authentik`,
  `opencloud`, `immich`, `forgejo`, `grafana`, `n8n`, kopia, etc. would be templated
  and deployed onto `nas` too. This contradicts `deployment.md` ("nas (no Docker) —
  Ansible bootstrap only") and `hardware-nas.md` (ZFS storage, no Docker).
- **Likely fix:** put `nas` in its own group (e.g. `[storage]`) so it gets only
  `common`/`ai_diag`/`network`/`nut` (+ any future storage-only roles), or gate the
  whole service loop per-host.
- **Progress (506b856):** implemented — `nas` moved to a new `[storage]` group via
  `playbooks/storage.yml` (common → ai_diag → network → nut, NO Docker); `home_servers`
  is now oldsrv-only; `site.yml` + pre-flight guard updated. Pending deploy/verify.
- **Priority:** high · **Status:** implemented in IaC · pending deploy/verify · open

## I10 — shared `post_install.sh` sshd `AllowUsers` locks out the Pi's `pi` user
- **Area:** `IaC/host/post_install.sh` / `deployment-preseed.md` / `host_vars/ha.kogler.si.yml`
- **Symptom:** `post_install.sh` (and `deployment-preseed.md`) harden sshd with
  `AllowUsers ansible-admin ai-debug`. But the Raspberry Pi's deploy user is **`pi`**
  (`host_vars/ha.kogler.si → ansible_user: pi`; inventory `[raspberry_pi]`). The docs
  call this "the **single shared** `post_install.sh` for **all** hosts" — applied to
  the Pi it would SSH-lock `pi`. Also `ansible-admin` is created only by preseed
  (present for `nas`/`oldsrv`, **not** the Pi), and there is no Pi preseed in `IaC/host/`.
- **Likely fix:** document the Pi's bootstrap as *not* using the shared
  `post_install.sh` (or add `AllowUsers … pi` / a Pi-specific variant), and clarify the
  Pi's SSH user/creation path.
- **Priority:** medium · **Status:** open

## I11 — `ha.kogler.si` is both the HA service VIP name and the Pi's inventory host
- **Area:** `services.md` / `smart-home*.md` / `IaC/ansible/inventory.ini` / `host_vars/ha.kogler.si.yml`
- **Symptom:** `ha.kogler.si` is documented to resolve to the VIP `10.10.1.200`, but it
  is also the Ansible inventory host for the Pi node, whose SSH/node IP is `10.10.1.20`.
  `group_vars/router.yml` reads `hostvars['ha.kogler.si'].dns_secondary_ip`, and
  `network-dns.md` says the secondary Technitium is "on the Pi (`ha.kogler.si`)" — the
  FQDN is ambiguous (VIP service name vs node hostname).
- **Likely fix:** give the Pi node a distinct hostname (e.g. `pi.kogler.si` in inventory
  / `etc_hosts`) so `ha.kogler.si` unambiguously means the VIP, or explicitly document
  the node-vs-VIP naming convention.
- **Priority:** medium · **Status:** open

## I12 — `rb4011_initial.rsc` firewall drifts from `network-vlans.md` (folded into I2)
- **Area:** `network-vlans.md` / `IaC/router/rb4011_initial.rsc`
- **Symptom:** `network-vlans.md` Home→Mgmt = SSH/WinBox/HTTPS **+ 502 (UPS Modbus) +
  80/443 from trusted monitoring hosts**; the `rsc` Home→Mgmt rule is
  `dst-port=22,8291,80,443` from **all** Home (no `502`, no `8728`, no trusted-host
  restriction). Home→IoT (and IoT-Internet) rules in the `rsc` allow only the VIP via
  `src-address-list=trusted-ha` (sole entry `10.10.1.200`) — `oldsrv`/`nas` are on no
  trusted list, so Home→IoT from `10.10.1.30` and UPS `502` from monitoring hosts are
  blocked per the doc's rules.
- **Likely fix:** align the `rsc` rules with `network-vlans.md` (add `502`/`8728` to
  Home→Mgmt + restrict to trusted hosts; extend the trusted address-list with
  oldsrv/nas/Home IPs). Consolidated into I2 — tracked here as a cross-reference.
- **Priority:** medium · **Status:** folded into I2

## I13 — Live HA reads UPS via Modbus 502, but the decided NUT topology uses USB HID
- **Area:** `home-assistant-current.md` / `hardware-ups.md` / `observability.md`
- **Symptom:** `home-assistant-current.md` shows a **Modbus** integration reading the
  UPS on `10.10.99.9:502` (scaled battery/voltage/load sensors). `hardware-ups.md`'s
  "Monitoring & Shutdown Topology (decided)" uses **USB HID + NUT master on nas —
  not Modbus for monitoring" (single `nut_exporter` SSOT). Two overlapping UPS data
  paths (HA Modbus vs NUT/USB) — which is the source of truth?
- **Likely fix:** establish one source (NUT/USB via `nut_exporter` is the documented
  SSOT); either retire the HA Modbus sensors or document them as a read-only
  second/independent view.
- **Priority:** medium · **Status:** open

## I14 — IaC/README.md is stale vs real group_vars and other docs
- **Area:** `IaC/README.md`
- **Symptom:** its `docker_services` sample lacks `raspberrymatic-standby` and
  `home-assistant-standby`, and drops the `enabled:`/`instance:`/`subdomain:`
  modifiers present in the actual `group_vars/home_servers.yml` (technitium
  on-oldsrv-only, pihole=ad, grafana=stats, n8n=auto). Its public-DNS subset lists
  `(kogler.si, foto, file, git, sso, ha)` — omitting **`vpn`** (Headscale), which
  `network-dns.md`/`services.md` list as public.
- **Likely fix:** regenerate/align `IaC/README.md`'s service + DNS-subset listings
  with `group_vars/home_servers.yml` and `network-dns.md`.
- **Priority:** low · **Status:** open

## I15 — Metabase (`sec.kogler.si`) documented but absent from service list and TODOs
- **Area:** `services.md` / `interfaces.md` / `observability.md` / `IaC/ansible`
- **Symptom:** `sec.kogler.si` (CrowdSec dashboard + Metabase learning sandbox) is
  described in three docs. It has **no compose template**, is **not** in
  `group_vars/home_servers.yml`'s `docker_services`, and is **not even** in the
  `# TODO (create templates)` line (homepage, renovate, doco-cd, prometheus, loki,
  blackbox-exporter, signal-cli-rest-api).
- **Likely fix:** add a `metabase` service entry + template (and CrowdSec dashboard
  wiring), or add it to the TODO list.
- **Priority:** low · **Status:** open

## I16 — preseed keyboard key mismatch (`xkb-map` vs `xkb-keymap`)
- **Area:** `deployment-preseed.md` / `IaC/host/nas/preseed.cfg`
- **Symptom:** `deployment-preseed.md` says `d-i keyboard-configuration/xkb-map select si`;
  the reference `nas/preseed.cfg` uses `d-i keyboard-configuration/xkb-keymap select si`.
  `xkb-keymap` is the correct Debian clave-type key.
- **Likely fix:** fix the `deployment-preseed.md` spelling to `xkb-keymap`.
- **Priority:** low · **Status:** open

## I17 — README references a non-existent `obsolete/` directory
- **Area:** `README.md`
- **Symptom:** `README.md`'s Repository Structure lists an `obsolete/` folder that does
  not exist in the repo.
- **Likely fix:** remove the `obsolete/` line (or add the folder if it's meant to exist).
- **Priority:** low · **Status:** open

---

## Resolved in this session (kept for history)
- **DNS secondary host** — was contradictory (`network-dns.md` said nas, others said Pi).
  Resolved: **Pi** (`10.10.1.20`), primary on oldsrv (`10.10.1.30`).
- **`trusted-ha` firewall list** — pointed at `10.10.1.10` (the NAS); corrected to the
  HA VIP `10.10.1.200` so Home→IoT MQTT/HA rules follow the active HA node.
- **UPS / iLO / VIP old flat-LAN IPs** — removed from all docs and IaC; new static
  plan in `network-addresses.md`.
