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
  the Technitium Home addresses.
- **Likely fix:** rewrite the DNS reachability/firewall prose to the Home-based
  resolver addresses and decide whether clients/other VLANs resolve via the router
  (gateway forward) or directly to `10.10.1.30/.20` (add forward rules).
- **Priority:** high (correctness) · **Status:** open

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
- **Priority:** high · **Status:** open

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

---

## Resolved in this session (kept for history)
- **DNS secondary host** — was contradictory (`network-dns.md` said nas, others said Pi).
  Resolved: **Pi** (`10.10.1.20`), primary on oldsrv (`10.10.1.30`).
- **`trusted-ha` firewall list** — pointed at `10.10.1.10` (the NAS); corrected to the
  HA VIP `10.10.1.200` so Home→IoT MQTT/HA rules follow the active HA node.
- **UPS / iLO / VIP old flat-LAN IPs** — removed from all docs and IaC; new static
  plan in `network-addresses.md`.
