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

## I1 — Several IaC roles are still "TODO: implement" (SSOT model is aspirational)
- **Area:** `IaC/ansible/roles/`, `IaC/ansible/templates/docker_services/`
- **Symptom:** `docker_services`, `monitoring`, `amd_rocm`, `desktop`, `office`,
  `router`, `proxmox` roles are literally `# TODO: implement`; all 19 compose
  templates under `templates/docker_services/` are TODO stubs. The "IaC = source of
  truth, docs generated" model is only partially real: `network-addresses.md` is
  rendered from IaC, but `inventory.md` still needs the `docker_services` post-deploy
  hook, and the `network` role's static-IP/trunk provisioning is pending a
  config-manager decision (systemd-networkd vs netplan).
- **Likely fix:** implement the roles (esp. the `docker_services` generic loop and
  `network` static IP/VLAN provisioning), then wire the `inventory.md` render into
  the same post-deploy hook.
- **Priority:** high · **Status:** open

## I2 — Traefik (`ha` route) depends on cross-host VIP
- **Area:** `services.md` accessibility / `smart-home-failover.md`
- **Symptom:** Traefik runs on oldsrv; HA primary runs on the Pi. The `ha.kogler.si`
  backend is the VIP `10.10.1.200` over the Home VLAN. This works intra-VLAN today,
  but is a hidden coupling: if HA ever leaves the Home VLAN, Traefik's `ha` route
  breaks. Worth an explicit note/runbook reference.
- **Likely fix:** document the coupling in the accessibility SSOT; no code change now.
- **Priority:** low · **Status:** open

## I3 — Hardcoded NTP server in router baseline
- **Area:** `IaC/router/rb4011_initial.rsc`
- **Symptom:** line 18 pins `/system ntp client servers add server=193.2.1.66`.
  Verify this is intentional (vs. a Slovenian pool).
- **Likely fix:** if not intentional, use `0.si.pool.ntp.org` to match `group_vars/all.yml`.
- **Priority:** low · **Status:** open

## I4 — shared `post_install.sh` sshd `AllowUsers` locks out the Pi's `pi` user
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

## I5 — `ha.kogler.si` is both the HA service VIP name and the Pi's inventory host
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

## I6 — Live HA reads UPS via Modbus 502, but the decided NUT topology uses USB HID
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

## I7 — IaC/README.md is stale vs real group_vars and other docs
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

## I8 — Metabase (`sec.kogler.si`) documented but absent from service list and TODOs
- **Area:** `services.md` / `interfaces.md` / `observability.md` / `IaC/ansible`
- **Symptom:** `sec.kogler.si` (CrowdSec dashboard + Metabase learning sandbox) is
  described in three docs. It has **no compose template**, is **not** in
  `group_vars/home_servers.yml`'s `docker_services`, and is **not even** in the
  `# TODO (create templates)` line (homepage, renovate, doco-cd, prometheus, loki,
  blackbox-exporter, signal-cli-rest-api).
- **Likely fix:** add a `metabase` service entry + template (and CrowdSec dashboard
  wiring), or add it to the TODO list.
- **Priority:** low · **Status:** open

## I9 — preseed keyboard key mismatch (`xkb-map` vs `xkb-keymap`)
- **Area:** `deployment-preseed.md` / `IaC/host/nas/preseed.cfg`
- **Symptom:** `deployment-preseed.md` says `d-i keyboard-configuration/xkb-map select si`;
  the reference `nas/preseed.cfg` uses `d-i keyboard-configuration/xkb-keymap select si`.
  `xkb-keymap` is the correct Debian clave-type key.
- **Likely fix:** fix the `deployment-preseed.md` spelling to `xkb-keymap`.
- **Priority:** low · **Status:** open

## I10 — README references a non-existent `obsolete/` directory
- **Area:** `README.md`
- **Symptom:** `README.md`'s Repository Structure lists an `obsolete/` folder that does
  not exist in the repo.
- **Likely fix:** remove the `obsolete/` line (or add the folder if it's meant to exist).
- **Priority:** low · **Status:** open
