# Deployment Tasks — Kogler Homelab (redo from scratch)

> **Goal:** take the homelab from zero — **network redo** (flat single subnet → VLAN segmentation),
> **fresh installs of `nas`, `pi`, `oldsrv`**, and **1Password-secret wiring** — to the **working
> homelab as desired** (single `*.kogler.si` namespace, HA primary+standby, observability, GitOps CD).
>
> **Authoritative build order:** derived from `docs/index.md`, `docs/deployment-preseed.md`,
> `docs/deployment-ansible.md`, `docs/network-vlans.md`, `IaC/README.md`, and
> `docs/deployment-secrets.md` (secrets single source of truth).
>
> **Status tracking for sub-tasks / difficulty:** `docs/todo.md` (HD-XX IDs).
>
---

## 0. Prerequisites & Global Secrets

> **Everything runs from the management laptop (Phase 0).** The `Homelab` 1Password vault is the
> **only** secrets backend — Ansible lookups resolve items at render time, keys are served on demand
> by the 1Password SSH agent. No secret is ever committed to Git.

### 1Password items (the full canonical set — `docs/deployment-secrets.md` is the single source of truth)

All **25** items use the `<service>_<type>` convention (single `_`, `-` in service names). A phase that
lists an item as a prerequisite must have that item created in the `Homelab` vault first.

| Item | type → `field=` | First needed in |
|------|-----------------|-----------------|
| `laptop-domen_ssh` | ssh → `private_key`/`public_key` | Phase 0 (bootstrap key on laptop) |
| `ansible-admin_ssh` | ssh → `private_key`/`public_key` | Phase 0 |
| `ai_ssh` | ssh → `private_key`/`public_key` | Phase 0 |
| `op_api` | api → `credential` (1Password Service Account token) | Phase 0 |
| `mikrotik-admin_login` | login → `password` | Phase 1 |
| `wg_password` | password → `password` (WireGuard S2S key) | Phase 1 |
| `nut_password` | password → `password` | Phase 2 |
| `nut-smtp_login` | login → `password` (`username`=notify email/SMTP user) | Phase 2 |
| `cloudflare_api` | api → `credential` (ACME DNS-01) | Phase 3 |
| `kopia_password` | password → `password` | Phase 0 (seed; read by the 1Password test, later by kopia) |
| `kopia-s3_api` | api → `credential` (`username`=S3 access key) | Phase 3 |
| `authentik_db` | db → `password` (`username`=DB user) | Phase 3 |
| `authentik_password` | password → `password` (Django SECRET_KEY) | Phase 3 |
| `authentik_login` | login → `password` (bootstrap admin) | Phase 3 |
| `opencloud_db` | db → `password` | Phase 3 |
| `immich_db` | db → `password` | Phase 3 |
| `forgejo_db` | db → `password` | Phase 3 |
| `forgejo_api` | api → `credential` | Phase 3 |
| `grafana_login` | login → `password` | Phase 3 |
| `grafana-smtp_login` | login → `password` | Phase 3 |
| `ha_api` | api → `credential` (long-lived token) | Phase 3 |
| `ha-vrrp_password` | password → `password` | Phase 3 (standby) / 4 (primary) |
| `headscale_api` | api → `credential` (OIDC client secret) | Phase 3 |
| `signal_api` | api → `credential` (`username`=phone number) | Phase 3 |
| `doco-cd_password` | password → `password` (webhook HMAC) | Phase 5 |

> **Creation gap:** most items are created during deployment. The **ssh items + `op_api`** must exist
> first (Phase 0), because `post_install.sh` injects the SSH keys into every fresh install and Ansible
> needs the Service Account token to resolve secrets.

---

## Phase 0 — Bootstrap the Management Laptop

> **Depends on:** nothing (first action).
> **1Password prerequisites:** `laptop-domen_ssh`, `ansible-admin_ssh`, `ai_ssh`, `op_api`, and
> `kopia_password` (seed `password`-type item read by `test-1password.yml`) all exist in `Homelab`.
> **Continuation:** once verified, you can run Ansible and the 1Password test; nothing else.

1. Clone the repo; run the client bootstrap:
   ```bash
   cd IaC/bootstrap-ansible-client && bash bootstrap.sh
   source ~/.bashrc
   ```
2. Verify tooling: `ansible --version`, `op --version`.
3. Set up the 1Password SSH agent + `~/.ssh/config` (see `docs/deployment-secrets.md`).
4. Verify 1Password connectivity:
   ```bash
   ansible-playbook -i IaC/ansible/inventory.ini IaC/ansible/test-1password.yml
   ```
   (reads `kopia_password` — item must exist, `<service>_db` placeholders don't matter here.)

**Verify:** test-1password.yml prints the fetched password; laptop can `ssh nas` via the agent.

---

## Phase 1 — Network Redo from Scratch (Router RB4011 + Switch CRS328)

> **This is the irreversible cutover**: the current **flat single-subnet** network is replaced by
> **VLAN segmentation** per `docs/network-vlans.md`. Until the router is rebuilt, the whole home is
> offline — do this at a planned maintenance window. All subsequent fresh installs depend on it.
>
> **Depends on:** Phase 0 (laptop + 1Password agent).
> **1Password prerequisites:** `mikrotik-admin_login` (login→`password`), `wg_password` (password→`password`).
> **Continuation:** next phases require the router serving DHCP on VLANs 10 + 99 (and 20/21/30/40/50 as configured).

1. **Router baseline** — factory-reset the RB4011 and apply `IaC/router/rb4011_initial.rsc`:
   - VLANs: 10 Home, 20 IoT, 21 IoT-Internet, 30 Guest, 40 Kids, 50 Media, 99 Management
   - Inter-VLAN firewall (default-deny; address-lists `trusted-ha`/`trusted-admin`; the UPS web rule on 99)
   - DHCP per VLAN (option 15 `domain=kogler.si`), WireGuard S2S (key from `wg_password`)
   - CAPsMAN: SSIDs `Kogler`, `Kogler IOT`, `Kogler IOT WAN`, `Kogler guest`, `Kogler Kids`, `local-forwarding=no`
   - DNS forwarder → Technitium (on oldsrv, Phase 3); fallback `1.1.1.1`
   - Config is stored/versioned via `docs/network-ops.md`.
2. **AP + switch** — apply `IaC/router/ap_initial.rsc` (CAP-mode); configure the CRS328 as L2 trunk + PoE.
3. **Migrate devices** — move each device to its intended VLAN access port / SSID (see `network-vlans.md` Port Type Reference).

**Verify:**
- `ip addr` on the router shows all VLAN interfaces up; DHCP issues leases on each VLAN.
- Inter-VLAN reachability matches the firewall matrix (e.g. Home→99 management allowed from `trusted-admin` only).
- CAPsMAN SSIDs visible; WireGuard handshake established.
- Rollback plan documented before starting (preserve the previous flat config as `rb4011_flat_backup.rsc`).

---

## Phase 2 — NAS Fresh Install + Storage + UPS Master (`nas.kogler.si`)

> **Depends on:** Phase 1 (router VLANs + DHCP). NAS is on VLAN 10 (Home, access) + VLAN 99 (Mgmt, native).
> **1Password prerequisites (new this phase):** `nut_password` (password→`password`), `nut-smtp_login`
> (login; `username`=notify email/SMTP user, `password`=SMTP pass). SSH items from Phase 0 are injected
> by `post_install.sh`. **No Docker on NAS.**
> **Continuation:** the NAS is the **NUT master** — `oldsrv` and `pi` are NUT clients and depend on it.

1. **Preseed install** — boot the HP MicroServer from `IaC/host/nas/preseed.cfg`
   (single-SSD boot; ZFS HDDs **not touched** by preseed) + shared `IaC/host/post_install.sh`
   (ansible-admin + ai-debug keys, sshd hardening).
2. **Ansible** — `ansible-playbook -i inventory.ini playbooks/storage.yml`:
   `common` → `ai_diag` → `network` (static on VLAN 10, IP per SSOT) → `nut` (mode=master) → `cockpit`.
3. **NUT master** — `nut-server` + `usbhid-ups` (PowerWalker USB), `upsd` listening intra-VLAN
   `nas:3493` (no inter-VLAN rule needed — see `docs/hardware-ups.md`), `nut_exporter` as a
   host binary (:9199), `upssched-cmd` email/Signal notify (`nut-smtp_login`).
4. **Storage** — create ZFS pool + datasets; exports (NFS/SMB); mount layout per `docs/hardware-nas.md`.

**Verify:**
- `zpool status` healthy; `upsc powerwalker@nas` returns live UPS data.
- `nut_exporter` scrapable on :9199; cockpit reachable at `cockpit-nas.kogler.si` (Traefik file-provider route).

---

## Phase 3 — oldsrv Fresh Install + Primary Docker Host (`oldsrv.kogler.si`)

> **Depends on:** Phase 1 (VLAN 99 native + tags), Phase 2 (NAS NUT master for the `nut` client).
> oldsrv is the Phase 1 compute host — **all** home services, HA **standby**, monitoring, single ACME issuer.
> **1Password prerequisites (new this phase):** the platform block below must exist in `Homelab`.
> **Continuation:** Forgejo, Traefik (wildcard cert), and all services come up here; Phases 4–6 depend on them.

1. **Preseed install** — boot from `IaC/host/oldsrv/preseed.cfg` (NVMe partitions; iGPU-primary, dGPU RX 7600
   reserved for compute) + shared `post_install.sh`.
2. **Ansible** — `ansible-playbook -i inventory.ini playbooks/home_servers.yml` (ordered):
   `common` → `ai_diag` → `docker` → `network` (trunk VLAN 99 native + 10/20/50 tagged) → `nut` (client,
   `shutdown_delay_seconds=60` → `powerwalker@nas`) → `amd_rocm` (ROCm stack, udev, `OLLAMA_KEEP_ALIVE=5m`)
   → `desktop` → `office` → `cockpit` → `docker_services` → `home_assistant` (standby) → `monitoring`.
3. **Edge + services** — Traefik issues `*.kogler.si` wildcard via ACME DNS-01 (`cloudflare_api`);
   `docker_services` deploys every service listed in `group_vars/home_servers.yml` (see that file or
   `docs/services.md` — **SSOT**; includes traefik, crowdsec, authentik, opencloud, immich-app/mml,
   forgejo, ollama, technitium, pihole, headscale, kopia-server/agent, db-backup, grafana→stats, n8n,
   homepage, metabase, signal-cli-rest-api, sunshine, home-assistant-standby, plus the Media /·\*arr
   stack and `dozzle` → **HD-43/-44**).

4. **HA standby** — `home-assistant-standby` compose + keepalived (`ha-vrrp_password`); disabled by default.

**New 1Password prerequisites (Phase 3):**
- `cloudflare_api` (api→`credential`) — wildcard cert
- `kopia_password` (password), `kopia-s3_api` (api; `username`=access key, `credential`=secret key)
- `authentik_db` (db→`password`), `authentik_password` (password→`password`), `authentik_login` (login→`password`)
- `opencloud_db`, `immich_db`, `forgejo_db` (db→`password` each)
- `forgejo_api` (api→`credential`) — renovate + doco-cd token
- `grafana_login` (login→`password`), `grafana-smtp_login` (login→`password`)
- `ha_api` (api→`credential`), `ha-vrrp_password` (password→`password`)
- `headscale_api` (api→`credential`) — OIDC client secret
- `signal_api` (api; `username`=phone, `credential`=captcha) — signal-cli-rest-api

**Verify:**
- `docker compose ps` for every service is healthy; `systemctl status docker-compose@<service>`.
- Homepage (`home.kogler.si`), Grafana (`stats.kogler.si`), Forgejo (`git.kogler.si`) reachable (after Authentik SSO).
- Wildcard `*.kogler.si` cert issued (Traefik ACME logs).

---

## Phase 4 — Pi Fresh Install + HA Primary (`pi.kogler.si`)

> **Depends on:** Phase 1 (VLANs), Phase 2 (NAS NUT master). The Pi is the HA **primary** node;
> oldsrv (Phase 3) is standby. Both share one `configuration.yaml` and the VIP (`ha-vip`).
> **1Password prerequisites (new this phase):** none beyond Phase 3 (`ha_api`, `ha-vrrp_password`,
> `nut_password`, `nut-smtp_login` already exist). Add `ha-mqtt_login` if/when MQTT is introduced
> (currently out of scope).
> **Continuation:** `ha.kogler.si` → VIP becomes live here; observability (Phase 6) scrapes the HA
> exporter and smart-home work (Phase 7) builds on this node.

1. **Preseed install** — boot from `IaC/host/pi/preseed.cfg` (**headless**, no desktop/Cockpit) +
   shared `post_install.sh`.
2. **Ansible** — `ansible-playbook -i inventory.ini playbooks/raspberry_pi.yml`:
   `common` → `network` (static on VLAN 10, IP per SSOT) → `nut` (client, `shutdown_delay_seconds=0`)
   → `docker` → `home_assistant` (**primary**, Debian + HA Container + keepalived → VIP `ha-vip`)
   → `docker_services` (Pi-specific: `technitium` DNS, `pihole`, `raspberrymatic`) → `monitoring` (Alloy only).
3. **Local Homematic** — `raspberrymatic` + HmIP-RFUSB (full-local XML-RPC, no cloud) — HD-13.

**Verify:**
- `ha.kogler.si` resolves to the VIP (`ha-vip` per SSOT); `keepalived` is MASTER on the Pi.
- Technitium (on oldsrv/Pi) resolves `*.kogler.si` internally; Pi-hole filtering active.
- HA web login via Authentik SSO (native OIDC on the `ha` route — no Forward-Auth).
- Manual failover runbook in `docs/smart-home-failover.md` passes Pi→oldsrv and back.

---

## Phase 5 — GitOps Pipeline Activation (Doco-CD + Forgejo Actions)

> **Depends on:** Phase 3 (Forgejo + services live, Renovate running), Phase 4 (HA live).
> **1Password prerequisites (new this phase):** `doco-cd_password` (password→`password`, webhook HMAC);
> `forgejo_api` + `op_api` (already created). Doco-CD reads `op_api` for the Service Account token.
> **Continuation:** once active, deploys happen on merge instead of manual Ansible runs (HD-02).

1. **Finalize `.doco-cd.yml`** — `auto_discovery` vs per-service compose, `compose_files`, `reference`,
   `external_secrets:` (1Password refs `op://Homelab/<item>/<field>`).
2. **1Password provider** — add `SECRET_PROVIDER=1password` + `SECRET_PROVIDER_ACCESS_TOKEN` (`op_api`)
   to the doco-cd compose env.
3. **Trigger** — Forgejo webhook `/v1/webhook` (port 80, HMAC `WEBHOOK_SECRET` ← `doco-cd_password`)
   **or** polling (decide on private-network reachability first).
4. **Metrics** — fix doco-cd metrics port **9120** + Prometheus scrape target.
5. **Post-deploy hooks** — regenerate Homepage config + `inventory.md` → commit+push.
6. **Forgejo Actions** — add `.forgejo/workflows/deploy.yml` (manual dispatch, `--tags` selector);
   test Renovate PR → Actions → service updated.

**Verify:** a Renovate PR → merge → service updated with **no manual Ansible run**; webhook reachable.

---

## Phase 6 — Observability & Alerting Hardening

> **Depends on:** Phase 3 (monitoring role, Prometheus/Loki/Grafana central), Phase 4 (HA exporter).
> **1Password prerequisites:** existing — `ha_api` (HA bearer), `grafana-smtp_login`, `nut-smtp_login`,
> `signal_api` (Signal notify via n8n). **Runs in parallel with Phase 5+.**

- UPS metrics + alerts in Grafana (Critical battery/runtime, Warning on-battery, Info transitions) — **HD-08**
- UPS web-UI firewall rule (80/443 Home→Mgmt for the `ups` host only, + touches Phase 1 firewall) — **HD-09**
- HA entity list export (Prometheus exporter) for TileBoard + Grafana — **HD-14**
- HA recorder trim (`purge_keep_days`) to protect the Pi SD — **HD-19**
- Grafana Alerting tiers (Critical/Warning/Info), self-monitoring, n8n + signal-cli-routing (details: `docs/observability.md`)

---

## Phase 7 — Smart Home Enhancements

> **Depends on:** Phase 4 (HA primary stable), Homematic HmIP-RFUSB stick available (human action).
> **1Password prerequisites:** existing — `authentik_login`, `authentik_db` (SSO), `ha_api`, `signal_api`.
> Items are tracked in `docs/todo.md` (HD-XX) — execute per-item, don't restate here.

1. Homematic full-local (HmIP-RFUSB + RaspberryMatic, local XML-RPC; human moves/fits the stick) — **HD-13**
2. Confirm HACS custom components (motion, ai_task, Weather-2000, OneDrive, go2rtc) — **HD-15**
3. Authentik/OIDC SSO timing decision (during redo or later?) — **HD-16**
4. Single failover button + `ha-failover.sh` (RMat → wait → VIP → standby) — **HD-17**
5. Test HmIP-RFUSB pairing transfer + entity reconstruction — **HD-18**
6. Voice pipeline (Whisper → Ollama → Piper, ESP32-S3 microWakeWord, HA Assist) — **HD-27**
7. Office AI stack (Ollama models, n8n, AnythingLLM + LocPilot, ONLYOFFICE) — **HD-28**

---

## Phase 8 — Backup & DR

> **Depends on:** Phase 2 (NAS ZFS datasets), Phase 3 (kopia-server/agent), off-site target decision.
> **1Password prerequisites:** existing — `kopia_password`, `kopia-s3_api` (S3 target access/secret).

- Decide bulk media off-site: iDrive e2 vs local-only ZFS — **HD-29**
- Sign up Infomaniak kSuite (email, CalDAV, catch-all) — **HD-30**
- Sign up iDrive e2 (S3 for Kopia) — **HD-31**
- Kopia: server (Phase 1 on oldsrv) + per-host agents; verify policies/retention
- Assess Kopia Web GUI vs CLI at first restore drill — **HD-34**

---

## Phase 9 — Documentation & Polish

> **Depends on:** services live (Phase 3+) to document accurately.
> **1Password prerequisites:** `mikrotik-admin_login` (export the live config).

- Write family guides `docs/manual/*` (10 Slovenian files, `status: wip`) — **HD-32**
- Export live router config `rb4011_live.rsc` (RouterOS export) — **HD-33**
- Fix broken `docs/network-devices.md` reference — **HD-35**
- Confirm watchtower vs Renovate for the Pi HA container — **HD-39**

---

## Phase 10 — Phase 2 (Deferred — start only after Phase 1 is stable)

> **Trigger:** Phase 1 insufficient or new hardware available. Public exposure introduces the VPS +
> Cloudflare layer.
> **1Password prerequisites (future):** `op_api`/`forgejo_api` (deploy), `proxmox_login` (VM lab), etc.

- VPS (Contabo) + public stack: Traefik, Cloudflare layer, public services — **HD-40**
- Proxmox role + VM lab (bridges, storage, VMs) — **HD-41**
- Phase-2 hardware build (Ryzen 9, open-frame chassis) — **HD-42**

---

## Continuation Dependency Graph

```
Phase 0 (bootstrap + ssh keys + op_api)
   │
   ▼
Phase 1 (network redo: flat ─▶ VLANs 10/20/21/30/40/50/99)  ◀── IRREVERSIBLE CUTOVER
   │  ├──────────────► Phase 2 (nas: storage + NUT master)
   │  │                       │
   │  │                       ▼
   │  └────────────────► Phase 3 (oldsrv: Docker host, all services, HA standby, monitoring, wildcard cert)
   │                          │
   │                          ▼
   │                   Phase 4 (pi: HA primary + VIP, Technitium DNS, RaspberryMatic)
   │                          │
   │                          ▼
   │                   Phase 5 (GitOps: Doco-CD + Forgejo Actions)
   │                          │
   ▼                          ▼
   Phase 6-9 (observability, smart-home, backup, docs) ── can run in parallel
   ▼
   Phase 10 (Phase 2: VPS, Proxmox, hardware) — deferred
```

**Phase prerequisites (1Password) recap — what must exist before you start:**
- **Phase 0:** `laptop-domen_ssh`, `ansible-admin_ssh`, `ai_ssh`, `op_api`, `kopia_password` (seed)
- **Phase 1:** + `mikrotik-admin_login`, `wg_password`
- **Phase 2:** + `nut_password`, `nut-smtp_login`
- **Phase 3:** + `cloudflare_api`, `kopia-s3_api`, `authentik_db/password/login`,
  `opencloud_db`, `immich_db`, `forgejo_db`, `forgejo_api`, `grafana_login`, `grafana-smtp_login`,
  `ha_api`, `ha-vrrp_password`, `headscale_api`, `signal_api`
- **Phase 4–9:** no new items (reuse the above)
- **Phase 5 specifically:** `doco-cd_password` (webhook HMAC)
- **Phase 10:** future (`proxmox_login`, etc.)

---

## Host → Playbook → VLAN Mapping

| Host | FQDN | VLANs | Playbook | Key roles (order) |
|------|------|-------|----------|-------------------|
| router | `router.kogler.si` | L3 all | `router.yml` | `router` |
| switch | `switch.kogler.si` | L2 trunk | (`.rsc`) | — |
| nas | `nas.kogler.si` | 10 + 99 native | `storage.yml` | common → ai_diag → network → nut(master) → cockpit |
| oldsrv | `oldsrv.kogler.si` | 99 native + 10/20/50 tagged | `home_servers.yml` | common → ai_diag → docker → network → nut(client) → amd_rocm → desktop → office → cockpit → docker_services → home_assistant(standby) → monitoring |
| pi | `pi.kogler.si` | 10 | `raspberry_pi.yml` | common → network → nut(client) → docker → home_assistant(primary+keepalived) → docker_services(pi) → monitoring(alloy) |
| vps | `vps.kogler.si` | public | `vps.yml` (Phase 2) | common → docker → network → docker_services → monitoring |
| — | all | — | `all.yml` | `/etc/hosts` sync |
| laptop | control | 10 | `render-docs.yml` | renders `docs/network-addresses.md` |

> Static IPs: [`docs/network-addresses.md`](docs/network-addresses.md) (SSOT).

---

## Validation Gates (Human)

| Gate | After | Check |
|------|-------|-------|
| Network cutover | Phase 1 | all VLANs up, DHCP per VLAN, inter-VLAN firewall matrix, CAPsMAN SSIDs, WireGuard up |
| NAS + UPS master | Phase 2 | `zpool status` healthy, `upsc powerwalker@nas` live, cockpit reachable |
| oldsrv services | Phase 3 | every `docker compose ps` healthy, wildcard cert issued, Homepage/Grafana/Forgejo reachable |
| HA VIP | Phase 4 | `ha.kogler.si`→VIP (`ha-vip`), keepalived MASTER on Pi, manual failover works |
| GitOps | Phase 5 | Renovate PR → merge → deployed with no manual Ansible run |
| Restore drill | Phase 8 | Kopia restores a test dataset to an alternate location |

---

## Notes

- **Service list source of truth:** `group_vars/home_servers.yml` (not this doc) — `docker_services` loop.
- **Generated docs (never hand-edit):** `docs/network-addresses.md`, `docs/inventory.md` (rendered by `render-docs.yml`).
- **Secrets source of truth:** `docs/deployment-secrets.md` (type map, master list, rename map).
- **Architecture rationale:** `docs/hardware.md`, `docs/services.md`, `docs/observability.md`,
  `docs/deployment.md`, `docs/network-vlans.md`, `docs/smart-home-failover.md`.
- **Per-item status / difficulty:** `docs/todo.md` (HD-XX IDs referenced above).
