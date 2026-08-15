# Homelab TODO Backlog

> **Source:** TODO / deferred / open-question / not-yet-implemented items extracted from `docs/`.
> **Priority (P):** 1 = highest (section header). **Difficulty (D):** 1–5, per the `plan-task` rubric:
>
> | Diff | Meaning |
> |------|---------|
> | 1 | Trivial / mechanical, single file, no research, low risk |
> | 2 | Straightforward, small batch, well-specified |
> | 3 | Moderate, multi-file, some judgment, needs validation |
> | 4 | Demanding, cross-cutting, design + verification |
> | 5 | Ambiguous / high-risk / needs human gate |
>
> **Executor (Exec):** `AI` agent-executable · `Human` decision/purchase/physical (blocks) · `AI + gate` agent work w/ human checkpoint · `AI + Human` joint.
> **Status:** `open` · `done`. Decided items point to the owning doc.

**Status: 42 open · 8 done** · **Total: 50**

---

## HD-02 — Activation notes (for the next session)

> **HD-02 (Activate Doco-CD) is a MULTI-STAGE task — do NOT attempt as a single run.
> Use `plan_task` to split it into ordered, idempotent tasks with exact validations
> and an explicit dependency graph. Stages (analysis from the HD-01 session):**
> 1. **Config finalization** — turn the `.doco-cd.yml` skeleton into the real deploy
>    path (`auto_discovery` vs per-service compose), `compose_files`, `reference`,
>    and `external_secrets:` mappings (`op://Homelab/<item>/<field>` refs). Deferred
>    from HD-01/T7.
> 2. **1Password secret provider** — add `SECRET_PROVIDER=1password` +
>    `SECRET_PROVIDER_ACCESS_TOKEN` to the `doco-cd` compose env (deferred from T7).
> 3. **Trigger wiring** — webhook `/v1/webhook` (HTTP port 80, `WEBHOOK_SECRET` HMAC,
>    configure the Forgejo webhook) and/or polling for the repo → deploy on merge.
>    Private network → decide polling vs webhook reachability first.
> 4. **Cross-task prerequisite (T6)** — fix doco-cd **metrics port 9120** + host-IP
>    scrape in `prometheus.yml` (recorded as a run-note in the HD-01 index).
> 5. **Post-deploy hooks** — regenerate Homepage config + inventory docs + reload /
>    commit+push. May depend on **HD-12** (inventory.md render pipeline, separate
>    open item) — check before planning this stage.
> 6. **Activate + verify** — render templates and bring the container up. ⚠️ This
>    box has **no docker/ansible**; live activation likely happens on a different
>    host → separate stage, likely a human gate + a decision on trigger method.

## Priority 1

| ID | D | Exec | Status | Item |
|----|---|------|--------|------|
| HD-01 | 3 | AI | done | **Create remaining `docker_services` compose templates** — 24 created ✅ (pre-existing), 17 TODO stubs implemented ✅ (bazarr, dozzle, immich-app, immich-ml, jellyfin, lidarr, ollama, pihole, profilarr, prowlarr, qbittorrent, radarr, recyclarr, sabnzbd, seerr, sonarr, sunshine). 18+ compliance fixes applied across all 43 templates. Immich v3 updated (microservices merged, postgres/valkey images). All validators pass. · [deployment-ansible.md](docs/deployment-ansible.md) |
| HD-02 | 3 | AI | open | **Activate Doco-CD** — GitOps CD, currently ⚠️ WIP / not activated: webhook + compose lifecycle + post-deploy hooks. Ansible handles everything until live. · [deployment.md](docs/deployment.md) |
| HD-03 | 5 | AI + gate | open | **Network redo: implement VLAN segmentation** — currently flat `10.10.1.0/24` → VLANs 10/20/21/30/40/50/99, inter-VLAN firewall, CAPsMAN SSIDs. ✅ **IaC implemented + committed (`39b9f02`):** router + switch `community.routeros` roles (VLANs, DHCP, firewall, mgmt). ⏳ **NOT deployed to live gear** — Ansible can't run on this Windows host (see render note). Open before deploy: switch bridge-VLAN access-port membership (under review vs Rack.canvas), CAPsMAN SSID secret items, WG VPS peer. · [network-vlans.md](docs/network-vlans.md) |
| HD-04 | 5 | AI + gate | open | **Pi redo: HAOS → Debian + HA Container + RaspberryMatic + Technitium secondary** — in-use device migration, done opportunistically during the network redo; approved direction, not yet applied. · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-05 | 1 | Human | **done** | **VIP address / notation / firewall IP-set** — decided: `10.10.1.200/32` (`ha-vip`), DHCP pool ≤ `.199`, router lists `trusted-ha` + `trusted-admin`. · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-06 | 3 | AI | open | **NUT master on nas** — `usbhid-ups`, `upsd` (3493), `nut_exporter`, `upssched-cmd` notify. ✅ **IaC done+fixed** (SSOT exporter on master `:9199`, scrape via `all.yml` vars, `@latest` release w/ verified asset URL, `nut-exporter_password` upsd auth, SMTP+Signal notify wired via `NOTIFYCMD`, battery.runtime/charge thresholds, USB verify task — G1–G7). ⏳ **Missing:** live deploy on nas (host not provisioned yet) + battery-pull test; feeds HD-07 (clients) / HD-08 (metrics+alerts). · [hardware-ups.md](docs/hardware-ups.md) |
| HD-07 | 2 | AI | open | **NUT clients on `oldsrv` + `pi`** — upsmon slave, per-host shutdown delay 60/0/0. Same role pattern, well-specified. · [hardware-ups.md](docs/hardware-ups.md) |
| HD-16 | 3 | AI | done | **Implement Authentik compose template + Traefik Forward-Auth middleware** — server+worker+postgres+redis compose (115 lines), `authentik-forward-auth@file` middleware (42 lines), `subdomain: sso` entry. All implemented in `db51854`. · [services-authentik.md](docs/services-authentik.md), [services-traefik.md](docs/services-traefik.md) |
| HD-50 | 3 | AI | done | **Implement `docker_services` Ansible role** — ✅ **Done (`eadf9d4`).** Role creates external Docker networks, copies templates, renders Jinja2 with 1Password lookups, runs `docker compose up -d`. Added: systemd auto-start per service (`docker-compose@.service` template unit + `systemctl enable`), post-deploy Homepage reload + `inventory.md` render. Fixed pre-existing path bugs (templates at playbook level, not in role). All 43 templates validated. · [deployment-ansible.md](docs/deployment-ansible.md) |

## Priority 2

| ID | D | Exec | Status | Item |
|----|---|------|--------|------|
| HD-08 | 3 | AI | open | **Wire UPS metrics + alerts into Prometheus/Grafana** — Critical battery/runtime, Warning on-battery, Info transitions. Depends on HD-06/07. · [hardware-ups.md](docs/hardware-ups.md) |
| HD-09 | 1 | AI | open | **UPS web-UI firewall rule** — open 80/443 Home→Mgmt for `10.10.99.9` only; Modbus 502 retired (no consumer). ✅ **IaC done** (router role: trusted-admin → `ups_management` 80/443); ⏳ not deployed. · [hardware-ups.md](docs/hardware-ups.md) |
| HD-10 | 2 | AI | done | **Generate `oldsrv/preseed.cfg`** — created: ext4 root on 960 EVO 500 GB, 970 EVO 1 TB left raw for ZFS pool `nvme`, XFCE desktop, GRUB on NVMe. · [deployment-preseed.md](docs/deployment-preseed.md) |
| HD-11 | 2 | AI | done | **Create Pi first-boot config** — `first-boot-config.sh` writes cloud-init `user-data` + fallback SSH enable on boot partition for raspi.debian.net images. · [deployment-preseed.md](docs/deployment-preseed.md) |
| HD-12 | 3 | AI | done | **Implement `inventory.md` render pipeline** — enhanced `inventory.md.j2` template (proper frontmatter, 5-column table, render instructions), created initial `docs/inventory.md` from group_vars data. Render hook already wired in `render-docs.yml` + `docker_services` post-deploy. · [interfaces.md](docs/interfaces.md) |
| HD-13 | 3 | AI + Human | open | **Homematic full-local (HmIP-RFUSB + RaspberryMatic)** — replace HAP cloud mode with local `homematic` XML-RPC; agent builds roles, human moves/fits the stick. Part of redo (HD-04). · [observability.md](docs/observability.md) |
| HD-14 | 2 | AI | open | **Export HA entity list** — enable HA Prometheus exporter; needed for TileBoard + Grafana. Wait for observability. · [smart-home.md](docs/smart-home.md) |
| HD-15 | 1 | AI | open | **Confirm HACS custom-component versions/repos** — `motion`, `ai_task`, Weather-2000, OneDrive, go2rtc via SSH / config git repo (REST API can't expose). · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-17 | 3 | AI | open | **Single failover button + `ha-failover.sh`** — RMat → wait → VIP → standby, on Homepage; manual-trigger design accepted. · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-18 | 2 | Human | open | **Once: test HmIP-RFUSB pairing transfer** + entity reconstruction across stick move. Hands-on; requires HD-13. · [smart-home-failover.md](docs/smart-home-failover.md) |

## Priority 3

| ID | D | Exec | Status | Item |
|----|---|------|--------|------|
| HD-19 | 2 | AI | open | **Pi SD-card wear: trim HA recorder + log strategy** — recorder `purge_keep_days: 1–2` / `commit_interval` / `exclude` (**not disabled**: keeps Logbook/Energy-LTS/history_stats, Grafana replaces long-term graphs) + Pi Docker-log driver `local` (10m×2) + `journald Storage=volatile` + `/var/log` tmpfs. Protects microSD once observability is live. · [observability.md](docs/observability.md)
| HD-20 | 1 | Human | open | **Confirm full Supervisor add-on list** — `/api/hassio/addons` returned 401 (non-admin token); needs admin/SSH on HAOS host. · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-21 | 1 | AI + Human | open | **Confirm ESPHome / Guition ESP32-S3 status** — `esphome` not loaded; agent checks network/repo, owner knows if the device was ever added. · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-22 | 1 | AI + Human | open | *(decision)* **Weather 2000 (SI) source** — third-party/HACS vs core; retain or replace. Agent researches, human decides. · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-23 | 1 | AI | open | **Confirm HmIP-SWO-B channels** — no rain / wind-direction on this sensor; verification only. · [smart-home.md](docs/smart-home.md) |
| HD-24 | 1 | Human | open | *(decision)* **TileBoard wall tablet model** — iPad / Android / repurposed; family/hardware purchase. · [interfaces.md](docs/interfaces.md) |
| HD-25 | 1 | Human | open | *(decision)* **Wake word final approval** — "Hey, assistant" is tentative; family meeting needed. · [smart-home.md](docs/smart-home.md) |
| HD-26 | 1 | AI | open | **Confirm UPS SNMP UDP (161/udp)** on the NIC — TCP probe closed, UDP untested; one probe vs `10.10.99.9`. · [hardware-ups.md](docs/hardware-ups.md) |
| HD-27 | 4 | AI + Human | open | **Voice pipeline build-out** — Whisper → Ollama → Piper containers, flash ESP32-S3 (ESPHome + microWakeWord), HA Assist on phones; GPU + physical flashing. · [smart-home-voice.md](docs/smart-home-voice.md) |
| HD-28 | 3 | AI | open | **Office AI stack** — Ollama models/downloads, n8n Docker, AnythingLLM + LocPilot on laptops, ONLYOFFICE; depends on oldsrv GPU. · [llm-office.md](docs/llm-office.md) |
| HD-29 | 2 | Human | open | *(decision)* **Bulk media off-site** — iDrive e2 space/cost headroom, or keep bulk local-only (ZFS). Input to HD-31. · [backup.md](docs/backup.md) |
| HD-30 | 1 | Human | open | *(buy)* **Sign up Infomaniak kSuite** — email, CalDAV, catch-all aliases; ~€3–5/mo; secrets → 1Password `Homelab`. · [subscription.md](docs/subscription.md) |
| HD-43 | 3 | AI | open | **Deploy/verify Media ·\*arr stack** — recent IaC added the templates (jellyfin, seerr, sonarr, radarr, lidarr, prowlarr, bazarr, sabnzbd, qbittorrent+gluetun, profilarr, recyclarr) in `group_vars/home_servers.yml`; deploys on oldsrv bulk/media NFS. · [services.md](docs/services.md) |
| HD-44 | 2 | AI | open | **Deploy/verify new ops services** — `dozzle` (`logs.`, Forward-Auth, viewer-only) and `traefik-ha` VIP edge on the Pi (added in recent IaC but not tracked/verified). · [services.md](docs/services.md) |
| HD-46 | 4 | AI | open | **Implement Matrix IaC (native-only)** — ✅ **IaC done + committed (`62e0045`):** `matrix/` (Tuwunel, `matrix.kogler.si`) + `element-web/` (Element Web, `chat.kogler.si`) compose templates + `group_vars/home_servers.yml` entries; SSO → Authentik OIDC; registration closed (`allow_registration=false`, bootstrap via `registration_shared_secret`); RocksDB on `/srv/docker/matrix` (no external DB). Secrets → 1Password `matrix_api` + `matrix_password` ([deployment-secrets.md](docs/deployment-secrets.md)). ⏳ **Not deployed:** hosts not provisioned; needs HD-47 (public records + `.well-known` delegation) + Authentik OIDC provider/redirect URI. ⚠ **No bridges in Phase 1** (deferred — HD-48). · [services-matrix.md](docs/services-matrix.md) |
| HD-47 | 2 | AI | open | **Matrix public records + Federation** — publish `matrix`/`chat` (Cloudflare DNS-only) + `_matrix` well-known/SRV delegation; WAN allow 443 (8448 optional) to oldsrv; **no Forward-Auth on `/_matrix/*`**. · [services-traefik.md](docs/services-traefik.md), [network-dns.md](docs/network-dns.md) |
| HD-48 | 3 | AI + Human | open | **Requested-only bridges (deferred, Phase 2 best-effort)** — WhatsApp/Messenger/Signal bridges are **out of Phase 1 scope** (every bridge risks a real external account). Revisit **only if family asks**, and then only against **dedicated** numbers, accepting re-pairing/ban. · [services-matrix.md](docs/services-matrix.md) |
| HD-49 | 3 | AI | open | **Backup Matrix identity + media** — signing/identity keys (critical — reissue breaks rooms), homeserver DB (db-backup/Kopia), media store; add to backup policy. · [services-matrix.md](docs/services-matrix.md), [backup.md](docs/backup.md) |

## Priority 4

| ID | D | Exec | Status | Item |
|----|---|------|--------|------|
| HD-31 | 1 | Human | open | *(buy)* **Sign up iDrive e2** — S3 Kopia off-site target; ~€5/mo; depends on HD-29. · [subscription.md](docs/subscription.md) |
| HD-32 | 2 | AI | open | **Write family guides `docs/manual/*`** — 10 Slovenian files, `status: wip`, not yet written; content well-specified; deferred until services live. · [manual/README.md](docs/manual/README.md) |
| HD-33 | 1 | AI | open | **Export live router config `rb4011_live.rsc`** — one-time RouterOS export; docs-only. · [network-ops.md](docs/network-ops.md) |
| HD-34 | 2 | AI + Human | open | **Assess Kopia Web GUI vs CLI** at the first restore drill (agent assesses during the human-run yearly drill). · [backup.md](docs/backup.md) |
| HD-35 | 1 | AI | done | **Fix broken `network-devices.md` reference** — link was already removed from network-vlans.md (resolved). The content lives in `assets/Network-Devices.canvas`. · [network-vlans.md](docs/network-vlans.md) |

## Priority 5 (deferred / optional / Phase 2)

| ID | D | Exec | Status | Item |
|----|---|------|--------|------|
| HD-36 | 3 | AI | open | **Internal AAAA records** — deferred/optional; needs stable per-host global addressing + IPv6 firewall mirroring. · [network-dns.md](docs/network-dns.md) |
| HD-37 | 3 | AI | open | **Long-term metric retention** — remote-write/downsampling (Thanos/VictoriaMetrics) only if ever needed. · [observability.md](docs/observability.md) |
| HD-38 | 2 | AI | open | **Prometheus Alertmanager** — only if Grafana-outage resilience demanded; Grafana Alerting covers Phase 1. · [observability.md](docs/observability.md) |
| HD-39 | 1 | Human | open | *(decision)* **watchtower for Pi HA container** — Renovate + pinned images may suffice. · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-40 | 4 | AI + Human | open | *(Phase 2)* **VPS (Contabo) + public stack** — incl. Cloudflare layer (TBD); agent automates after human provides the VPS. · [services-vps.md](docs/services-vps.md) |
| HD-41 | 4 | AI | open | *(Phase 2)* **Proxmox role + VM lab** — bridges, storage, VMs; implementation order step 10. · [deployment-ansible.md](docs/deployment-ansible.md) |
| HD-42 | 3 | Human | open | *(Phase 2)* **Phase-2 hardware build** — Ryzen 9, open-frame chassis; only if Phase 1 insufficient; physical. · [hardware-phase2.md](docs/hardware-phase2.md) |
| HD-45 | 3 | AI | open | *(Phase 2)* **Re-evaluate Homelable (topology/rack visualizer)** — Pouzor/homelable, MIT, young project; network + rack canvas + nmap scan + live health + MCP; potential successor to `Rack.canvas` visual/Homepage reachability widget. Keep deferred until services are live; re-check maturity. Noted in `observability.md` + `network-rack.md`. · [observability.md](docs/observability.md) |

---

## Network redo — implementation status (router/switch Ansible)

> **Commit `39b9f02`** implemented the Ansible halves of the network redo (HD-03) at the
> **role/template level**. None of this is **live** — the network is still flat (single
> Home subnet) and no device has been reconfigured. First apply must be a human-gated
> deploy (dry-run → single host) on a working Ansible host.
>
> ### Done (implemented + committed, NOT deployed)
> - **Router role** (`roles/router/`): VLAN interfaces+gateways (SSOT-derived), per-VLAN
>   DHCP, inter-VLAN firewall (address-lists, NAT masquerade on `pppoe-telekom`,
>   established/related return path, trusted-admin rules, IoT→WAN drop), AP DHCP static
>   leases, mgmt services. `community.routeros` added to requirements.yml. Auth via
>   `admin` + 1Password (`mikrotik-admin_login`).
> - **Switch role + inventory** (`roles/switch/`, `[switch]` group, `playbooks/switch.yml`):
>   VLAN-filtering bridge, trunk (`sfp-sfpplus1`), access ports + PoE (config-driven),
>   mgmt on VLAN 99, default route + DNS.
> - **SSOT / dedup:** `group_vars/network.yml` derives `ansible_host` from
>   `network_static_hosts`; `vlan_subnets` / `router_mgmt_ip` / `switch_mgmt_ip` derived;
>   missing router gateway entries (VLAN 20/21/30/40/50) added to `network_static_hosts`.
> - **Bug fixes (6):** inverted switch safety guard; hardcoded IP literals; broken
>   `item.vlan.*`/`item.subnet` refs in gateway IP + all DHCP tasks; firewall logic gaps;
>   VLAN 1 Blackhole loop skip + bridge-lan created before use.
> - **Docs/tooling:** `scripts/render_network_addresses.py` (Windows-friendly SSOT
>   render), regenerated `docs/network-addresses.md`, render instructions in
>   `deployment-ansible.md` + template header.
>
> ### Not done / deferred (open items before the network is usable)
> - **Switch bridge-VLAN access-port membership** — access ports get a `pvid` but are
>   NOT yet `untagged` members of their VLAN in the bridge VLAN DB; segmentation won't
>   actually work until implemented. Under review vs `Rack.canvas`.
> - **Per-switch port→VLAN/PoE map** — not finalized; `group_vars/switch.yml` marked
>   TODO (estimates from `Rack.canvas`; also conflicts noted: HAP/RPi on switch vs router,
>   sfp+ sweep, printer/AP-garage ports).
> - **CAPsMAN SSIDs** — need WPA2 passphrases from 1Password (`wifi_login` or per-SSID);
>   left commented with TODO.
> - **WireGuard S2S → VPS** — deferred to Phase 10 (VPS peer not built); left commented.
> - **Deploy/verify on gear** — not run (Ansible crashes on Windows; run on WSL/Debian).

## Notes / observed gaps

- `issues.md` is the official scratchpad for follow-ups (`docs/issues.md`) and is currently **empty** — decide whether it or this file is the backlog home (single source, avoid duplication). Recommended split: **todo.md = planned work**, **issues.md = defects/follow-ups**.
- Two dead references in docs: `docs/network-devices.md` (HD-35) and `docs/inventory.md` (HD-12).
- Dependencies: HD-03 → HD-04 → HD-13 · HD-06/07 → HD-08 · HD-01 done ✅ · HD-29 → HD-31 · HD-50 done ✅ → HD-16 → HD-43/HD-44/HD-46 (Authentik is a hard prerequisite for Forward-Auth services) · HD-50 blocks all `docker_services` deployments.
- **Recently-implemented IaC (done at template/role level, NOT yet deployed):** storage role (ZFS layout, snapshots, NFS, push jobs), face-thumbnail push over NFS, boot-time provisioning, traefik-ha edge failover, the Media/·\*arr + dozzle templates (→ HD-43/-44), and the **router/switch network roles** (→ HD-03). These are **not** live on any host yet — track them as open until a deploy/verify task (Phase 2/3) runs.

## Executor summary

| Exec | Count | IDs |
|------|-------|-----|
| AI | 32 | HD-01,02,06,07,08,09,10,11,12,14,15,16,17,19,23,26,28,32,33,35,36,37,38,41,43,44,45,46,47,49,50 |
| Human | 10 | HD-05(done),18,20,24,25,29,30,31,39,42 |
| AI + gate | 2 | HD-03, HD-04 |
| AI + Human | 7 | HD-13,21,22,27,34,40,48 |
