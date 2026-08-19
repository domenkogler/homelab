# Deployment Tasks — Kogler Homelab (redo from scratch)

> **Goal:** take the homelab from zero — **network redo** (flat single subnet → VLAN segmentation),
> **provision the netcup VPS as the public edge**, **fresh installs of `nas`, `pi`, `oldsrv`**, and
> **1Password-secret wiring** — to the **working homelab as desired** (single `*.kogler.si` namespace,
> HA primary+standby, observability, GitOps CD).
>
> **Authoritative build order:** derived from `docs/index.md`, `docs/deployment-preseed.md`,
> `docs/deployment-ansible.md`, `docs/network-vlans.md`, `IaC/README.md`, and
> `docs/deployment-secrets.md` (secrets single source of truth).
>
> **Status tracking for sub-tasks / difficulty:** `todo.md` (HD-XX IDs).

> **✅ Decisions (2025-08-16 — overriding some phase wording below):** see `todo.md` for the full
> rationale. **HD-92:** `oldsrv` stays bare-metal Debian + Docker (no Proxmox / no GPU passthrough on the
> single Phase-1 box; Proxmox deferred to HD-41/42). **HD-93:** the netcup VPS (**RS 2000 G12**, bought 2026-08-18) is **bought before go-live**
> and the **public edge (Traefik + CrowdSec + Authentik + public apps) goes on the VPS from day one**
> (fold HD-40A/40B into Phase 1) — oldsrv becomes an internal/GPU/LAN box. **The VPS carries the
> independent public tier (Authentik, Traefik, CrowdSec + co-located public apps & DBs) and is
> deployed BEFORE oldsrv/nas — it has no dependency on them** (only the GPU-backend cross-host links
> — immich-app→immich-ml, litellm→ollama — wait for the WG tunnel). **HD-135:** storage split (Immich
> originals+encoded-video → live Box,CIFS; hot data → VPS NVMe). **HD-51:** multi-axis identity model
> (persons = Authentik; shared bytes = neutral `media` owner via `storage_uid`/`storage_gid`; no human
> logins on nas; OpenCloud via Authentik OIDC).
>
---

## 0. Prerequisites & Global Secrets

> **Everything runs from the management laptop (Phase 0).** The `Homelab` 1Password vault is the
> **only** secrets backend — Ansible lookups resolve items at render time, keys are served on demand
> by the 1Password SSH agent. No secret is ever committed to Git.

### 1Password items (the full canonical set — `docs/deployment-secrets.md` is the single source of truth)

All **36** items use the `<service>_<type>` convention (single `_`, `-` in service names). A phase that
lists an item as a prerequisite must have that item created in the `Homelab` vault first. (Count + catalog
are SSOT in `docs/deployment-secrets.md` — this table is the deployment-phase view.)

| Item | type → `field=` | First needed in |
|------|-----------------|-----------------|
| `laptop-domen_ssh` | ssh → `private_key`/`public_key` | Phase 0 (bootstrap key on laptop) |
| `ansible-admin_ssh` | ssh → `private_key`/`public_key` | Phase 0 |
| `ai_ssh` | ssh → `private_key`/`public_key` | Phase 0 |
| `op_api` | api → `credential` (1Password Service Account token) | Phase 0 |
| `mikrotik-admin_login` | login → `password` | Phase 1.5 |
| `wg_password` | password → `password` (WireGuard S2S key) | Phase 1.5 |
| `nut_password` | password → `password` | Phase 2 |
| `nut-smtp_login` | login → `password` (`username`=notify email/SMTP user) | Phase 2 |
| `cloudflare_api` | api → `credential` (ACME DNS-01) | Phase 3 |
| `kopia_password` | password → `password` | Phase 0 (seed; read by the 1Password test, later by kopia) |
| ~~`kopia-s3_api`~~ | ~~api → `credential` (S3 access key)~~ — **retired**: iDrive e2 dropped, Kopia → backup Box via **SSH/SFTP (port 23)** (`kopia_password` + `Hertzner-SB-Backup` key) | — (no longer needed) |
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
| `doco-cd_password` | password → `password` (webhook HMAC) | Phase 6 |
| `netcup-ccp_login` | login → `password` (netcup CCP — billing/orders) | Phase 1 (VPS) |
| `netcup-scp_login` | login → `password` (netcup SCP — console/reboot/root reset) | Phase 1 (VPS) |
| `netcup-vps_login` | login → `password` (**separate vault**, root/OS break-glass) | Phase 1 (VPS) |
| `Hertzner-SB-Data` | — (connection ref; CIFS/SMB/WebDAV live box) | Phase 1 (VPS) |
| `Hertzner-SB-Backup` | — (connection ref; SSH/SFTP backup box) | Phase 1 (VPS) |

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

## Phase 1 — VPS Public Edge (netcup `vps.kogler.si`) — the independent public tier

> **Depends on:** Phase 0 (laptop + 1Password agent). Requires **public access** to netcup SCP + the VPS public IP;
> the LAN/network work (Phase 1.5) is **not** a prerequisite — this tier is public (netcup → internet → Cloudflare), not LAN.
> The VPS hosts the **self-contained public tier first**: Traefik + CrowdSec + Authentik (+ their co-located Postgres/Redis)
> and the public apps whose DBs live on VPS NVMe. It has **no dependency on oldsrv or nas**. **Needed before Phase 2.**
> **1Password prerequisites (new this phase):** `netcup-ccp_login`, `netcup-scp_login`, `netcup-vps_login` (separate vault),
> `Hertzner-SB-Data`, `Hertzner-SB-Backup`, plus the cloudflare/authentik/DB items listed in **Phase 3** for the moved apps.
> **Continuation:** once the edge + Authentik are live, the LAN track (Phase 1.5 network redo → Phase 2 nas → Phase 3 oldsrv)
> brings up the internal/GPU backends; the WG S2S tunnel (Phase 1.5 / HD-03 WG VPS peer) then lets the VPS reach them.

1. **Provision VPS (netcup SCP)** — netcup boots its **pre-built Debian 13 image**; the operative install hook
   is the **Custom Script** (netcup SCP field) = **`IaC/host/vps/post_install.sh`** (pasted as `*_with_secrets.sh`;
   no `ai-debug`, `AllowUsers ansible-admin` only — public box). **NOTE:** the `d-i` preseed lines
   (`IaC/host/vps/preseed.cfg`) do **NOT** run on netcup's image — that file is a reference/fallback only
   (see `deployment-preseed.md` → VPS Deviations). The `*_with_secrets.sh` injects the real SSH keys;
   root login disabled. Single 512 GB NVMe root (ext4, no ZFS).
2. **Ansible** — `ansible-playbook -i inventory.ini playbooks/vps.yml`:
   `common` → `docker` → `network` (static public IP per SSOT) → `docker_services` → `monitoring`.
3. **Edge tier** — enable the self-contained subset in `group_vars/vps.yml`: **`traefik`, `crowdsec`, `authentik`**
   (+ co-located DBs); Traefik issues the wildcard `*.kogler.si` cert via ACME **DNS-01** (`cloudflare_api`).
   The `dns.yml` control-plane playbook (roles/cloudflare_dns) adds the public records — start with `vps` A/AAAA,
   then `sso` (+ each public app as it lands).
4. **Live Box CIFS mount** — the `cifs` role (in `vps.yml`) mounts `//u653411.your-storagebox.de/backup` (`Hertzner-SB-Data`) at `/mnt/storagebox` on the VPS (0600 creds from 1Password) for Immich originals + encoded-video + OpenCloud files (HD-135 storage split). Applied automatically by Ansible; verify `mountpoint --q /mnt/storagebox` after deploy.
5. **NOT yet online (needs WG S2S + oldsrv):** immich-app→immich-ml, litellm→ollama — these expose only after the
   S2S tunnel (VPS↔home router, `wg-s2s`) reaches oldsrv's GPU backends (Phase 1.5). Their DBs/thumbs can be stood up now; the ML/local-model link waits.

**Verify:**
- `sso.kogler.si` (Authentik) reachable publicly through the VPS Traefik with the wildcard cert; crowdsec decision active.
- **Authentik OAuth2 Blueprint** — verify the `ks-oidc.yml` blueprint imports + the secret-egress glue seeds client creds on the pinned `2026.5.6` (version-specific flow/signing/binding attrs). Tracked: **HD-149**.
- `vps` A/AAAA records live at Cloudflare (via `dns.yml`); `ansible-admin` SSH works with the agent.
- Live Box CIFS mount returns data; VPS NVMe under 80%.

---

## Phase 1.5 — Network Redo from Scratch (Router RB4011 + Switch CRS328)

> **This is the irreversible cutover**: the current **flat single-subnet** network is replaced by
> **VLAN segmentation** per `docs/network-vlans.md`. Until the router is rebuilt, the whole home is
> offline — do this at a planned maintenance window. Phases 2–3 (nas/oldsrv fresh installs) depend on it.
>
> **Depends on:** Phase 0 (laptop + 1Password agent), Phase 1 (VPS edge + Authentik live).
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

> **Depends on:** Phase 1 (VPS edge + Authentik live), Phase 1.5 (router VLANs + DHCP). NAS is on VLAN 10 (Home, access) + VLAN 99 (Mgmt, native).
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

## Phase 3 — oldsrv Fresh Install + Internal/GPU Compute Host (`oldsrv.kogler.si`)

> **Depends on:** Phase 1.5 (VLAN 99 native + tags), Phase 2 (NAS NUT master for the `nut` client),
> Phase 1 (VPS edge + Authentik live).
> oldsrv is the **internal/GPU/LAN compute host**: the GPU + storage-bound backends (ollama, immich-ml,
> jellyfin/iGPU, sunshine), HA **standby**, DNS, media/*arr, observability, and an **internal** Traefik edge
> (the `ha` VIP + internal routes). The **public edge + stateless/live-data public apps live on the VPS**
> (Phase 1) — the wildcard cert is issued by the VPS Traefik; oldsrv serves internal-only + GPU workloads.
> **1Password prerequisites (new this phase):** the platform block below must exist in `Homelab`.
> **Continuation:** the GPU/AI stack (Phase 1's deferred `litellm→ollama`, `immich-app→immich-ml` links) comes
> online here once the WG S2S tunnel to the VPS exists; HA primary (Phase 4) builds on this node's standby.

1. **Preseed install** — boot from `IaC/host/oldsrv/preseed.cfg` (NVMe partitions; iGPU-primary, dGPU RX 7600
   reserved for compute) + shared `post_install.sh`.
2. **Ansible** — `ansible-playbook -i inventory.ini playbooks/home_servers.yml` (ordered):
   `common` → `ai_diag` → `docker` → `network` (trunk VLAN 99 native + 10/20/50 tagged) → `nut` (client,
   `shutdown_delay_seconds=60` → `powerwalker@nas`) → `amd_rocm` (ROCm stack, udev, `OLLAMA_KEEP_ALIVE=5m`)
   → `desktop` → `office` → `cockpit` → `docker_services` → `home_assistant` (standby) → `monitoring`.
3. **Services (internal/GPU subset)** — `docker_services` deploys the **oldsrv** subset in
   `group_vars/home_servers.yml`: ollama, immich-ml, jellyfin (iGPU), sunshine, technitium, pihole,
   headscale, kopia-server/agent, n8n, homepage, metabase, signal-cli-rest-api, home-assistant-standby,
   the Media /*arr stack and dozzle → **HD-43/-44**. The **public apps (traefik/crowdsec/authentik/opencloud/
   forgejo/immich-app/grafana) are on the VPS** (Phase 1/HD-135), not oldsrv — remove/downgrade them
   here per the HD-135 `enabled:` split.

   ✅ **Templates status (live):** all **42** compose templates exist under `docker_services/` — HD-16
   (authentik + Forward-Auth middleware) and HD-50 (`docker_services` role) are **done**. The authoritative
   service list is `group_vars/home_servers.yml` (the loop source of truth) + `docs/services.md`; it is
   **not** a per-template TODO list. New services are added by dropping a template under
   `docker_services/<name>/` and listing it in `home_servers.yml` — no per-template placeholder caveats.

4. **HA standby** — `home-assistant-standby` compose + keepalived (`ha-vrrp_password`); disabled by default.

**New 1Password prerequisites (Phase 3):**
- `cloudflare_api` (api→`credential`) — wildcard cert
- `kopia_password` (password) — Kopia off-site = **backup Box over SSH/SFTP (port 23)** (`kopia_sftp_*` in `all.yml`; SSH key in `Hertzner-SB-Backup`; **no password secret item**). ~~`kopia-s3_api`~~ retired (iDrive e2 dropped).
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

> **Depends on:** Phase 1.5 (VLANs), Phase 2 (NAS NUT master). The Pi is the HA **primary** node;
> oldsrv (Phase 3) is standby. Both share one `configuration.yaml` and the VIP (`ha-vip`).
> **1Password prerequisites (new this phase):** none beyond Phase 3 (`ha_api`, `ha-vrrp_password`,
> `nut_password`, `nut-smtp_login` already exist). Add `ha-mqtt_login` if/when MQTT is introduced
> (currently out of scope).
> **Continuation:** `ha.kogler.si` → VIP becomes live here; observability (Phase 6) scrapes the HA
> exporter and smart-home work (Phase 7) builds on this node.

1. **Flash + first-boot config** — download the latest raspi.debian.net Pi 4 image, flash to microSD,
   then run `IaC/host/pi/first-boot-config.sh` on the boot partition **before first boot**
   (see [`deployment-preseed.md` → Pi Image Deployment](docs/deployment-preseed.md)).
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
- UPS web-UI firewall rule (80/443 Home→Mgmt for the `ups` host only, + touches Phase 1.5 firewall) — **HD-09**
- HA entity list export (Prometheus exporter) for TileBoard + Grafana — **HD-14**
- HA recorder trim (`purge_keep_days`) to protect the Pi SD — **HD-19**
- Grafana Alerting tiers (Critical/Warning/Info), self-monitoring, n8n + signal-cli-routing (details: `docs/observability.md`)

---

## Phase 7 — Smart Home Enhancements

> **Depends on:** Phase 4 (HA primary stable), Homematic HmIP-RFUSB stick available (human action).
> **1Password prerequisites:** existing — `authentik_login`, `authentik_db` (SSO), `ha_api`, `signal_api`.
> Items are tracked in `todo.md` (HD-XX) — execute per-item, don't restate here.

1. Homematic full-local (HmIP-RFUSB + RaspberryMatic, local XML-RPC; human moves/fits the stick) — **HD-13**
2. Confirm HACS custom components (motion, ai_task, Weather-2000, OneDrive, go2rtc) — **HD-15**
3. Authentik OIDC provider + redirect URIs for downstream services (Matrix, Forgejo) — **HD-16** (compose template is Phase 3; post-deploy provider config)
4. Single failover button + `ha-failover.sh` (RMat → wait → VIP → standby) — **HD-17**
5. Test HmIP-RFUSB pairing transfer + entity reconstruction — **HD-18**
6. Voice pipeline (Whisper → Ollama → Piper, ESP32-S3 microWakeWord, HA Assist) — **HD-27**
7. Office AI stack (Ollama models, n8n, AnythingLLM + LocPilot, ONLYOFFICE) — **HD-28**

---

## Phase 8 — Backup & DR

> **Depends on:** Phase 1 (VPS Kopia → backup Box), Phase 2 (NAS ZFS datasets), Phase 3 (oldsrv kopia agent).
> **1Password prerequisites:** existing — `kopia_password`, `Hertzner-SB-Backup` (SSH/SFTP port 23, **not S3/SO**).
> **Off-site = two Hetzner Storage Boxes (bought 2026-08-18, HD-29/31):** live (Immich originals+encoded-video,
> OpenCloud files, CIFS) + backup (Kopia repo, SSH/SFTP port 23). **iDrive e2 dropped.**
>
> - Wire **VPS Kopia agent → backup Box** (SSH/SFTP, port 23) + **oldsrv agent → backup Box** (Kopia on both hosts).
> - Confirm VPS NVMe (DBs/thumbs/service state) is in Kopia scope; live-Box originals off-site via Kopia.
> - Kopia: server + per-host agents; verify policies/retention.
> - Assess Kopia Web GUI vs CLI at first restore drill — **HD-34**
> - Sign up Infomaniak kSuite (email, CalDAV, catch-all) — **HD-30**

---

## Phase 9 — Documentation & Polish

> **Depends on:** services live (Phase 3+) to document accurately.
> **1Password prerequisites:** `mikrotik-admin_login` (export the live config).

- Write family guides `docs/manual/*` (10 Slovenian files, `status: wip`) — **HD-32**
- Export live router config `rb4011_live.rsc` (RouterOS export) — **HD-33**
- Fix broken `docs/network-devices.md` reference — **HD-35**
- Confirm watchtower vs Renovate for the Pi HA container — **HD-39**

---

## Phase 10 — Deferred (Phase 2 hardware / Proxmox)

> **Trigger:** new bare-metal hardware available (→ Proxmox host, HD-41/42). The VPS edge is **already live**
> (Phase 1) — it is **not** deferred here.
> **1Password prerequisites (future):** `proxmox_login` (VM lab), etc.

- Proxmox role + VM lab (bridges, storage, VMs) — **HD-41**
- Phase-2 hardware build (Ryzen 9, open-frame chassis) — **HD-42**

---

## Continuation Dependency Graph

```
Phase 0 (bootstrap + 1Password/ssh keys + op_api)
   │
   ▼
Phase 1 — VPS PUBLIC EDGE (Traefik+CrowdSec+Authentik+public apps+DBs)   ◀── needed BEFORE Phase 2
   │      independent public tier — depends on Phase 0 only (public IP ~ DNS ~ internet);
   │      runs before / in parallel with the LAN track (it is public, not LAN)
   │
   ▼
Phase 1.5 — Network Redo (Router RB4011 + Switch CRS328)   ◀── IRREVERSIBLE CUTOVER (VLANs 10/20/21/30/40/50/99)
   │          (WG S2S peer lives here — HD-03)
   ▼
Phase 2 (nas: storage + NUT master)
   │
   ▼
Phase 3 (oldsrv: internal/GPU host — ollama/immich-ml/jellyfin, DNS, media, HA standby)
   │        (WG S2S tunnel now lets Phase 1 VPS reach oldsrv GPU backends: litellm→ollama, immich-app→immich-ml)
   ▼
Phase 4 (pi: HA primary + VIP, Technitium DNS, RaspberryMatic)
   │
   ▼
Phase 5 (GitOps: Doco-CD + Forgejo Actions)
   ▼
Phase 6-9 (observability, smart-home, backup, docs) ── can run in parallel
   ▼
Phase 10 (deferred: Phase-2 Proxmox hardware, HD-41/42)
```

**Phase prerequisites (1Password) recap — what must exist before you start:**
- **Phase 0:** `laptop-domen_ssh`, `ansible-admin_ssh`, `ai_ssh`, `op_api`, `kopia_password` (seed)
- **Phase 1 (VPS):** + `netcup-ccp_login`, `netcup-scp_login`, `netcup-vps_login` (separate vault), `Hertzner-SB-Data`,
  `Hertzner-SB-Backup`, `cloudflare_api`, `authentik_db/password/login`, `opencloud_db`, `immich_db`, `forgejo_db`,
  `forgejo_api`, `grafana_login`, `grafana-smtp_login`
- **Phase 1.5 (network):** + `mikrotik-admin_login`, `wg_password`
- **Phase 2:** + `nut_password`, `nut-smtp_login`
- **Phase 3:** + `ha_api`, `ha-vrrp_password`, `headscale_api`, `signal_api`
- **Phase 4–9:** no new items (reuse the above)
- **Phase 5 specifically:** `doco-cd_password` (webhook HMAC)
- **Phase 8 (backup):** no S3 items — Kopia = backup Box via **SSH/SFTP** (`kopia_password` + SSH key `Hertzner-SB-Backup`)
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
| vps | `vps.kogler.si` | public | `vps.yml` (**Phase 1**) | common → docker → network → docker_services → monitoring |
| — | all | — | `all.yml` | `/etc/hosts` sync |
| laptop | control | 10 | `render-docs.yml` + `dns.yml` | renders `docs/network-addresses.md`; maintains Cloudflare public DNS records |

> Static IPs: [`docs/network-addresses.md`](docs/network-addresses.md) (SSOT).

---

## Validation Gates (Human)

| Gate | After | Check |
|------|-------|-------|
| **VPS public edge** | Phase 1 | `sso.kogler.si` (Authentik) reachable via VPS Traefik + wildcard cert; crowdsec active; `vps` public records live; VPS NVMe < 80% |
| Network cutover | Phase 1.5 | all VLANs up, DHCP per VLAN, inter-VLAN firewall matrix, CAPsMAN SSIDs, WireGuard up |
| NAS + UPS master | Phase 2 | `zpool status` healthy, `upsc powerwalker@nas` live, cockpit reachable |
| oldsrv services | Phase 3 | internal/GPU subset healthy (`docker compose ps`); HA standby + GPU backends up; WG S2S lets VPS reach ollama/immich-ml |
| HA VIP | Phase 4 | `ha.kogler.si`→VIP (`ha-vip`), keepalived MASTER on Pi, manual failover works |
| GitOps | Phase 5 | Renovate PR → merge → deployed with no manual Ansible run |
| Restore drill | Phase 8 | Kopia restores a test dataset to an alternate location |

---

## Notes

- **Service list source of truth:** `group_vars/home_servers.yml` (not this doc) — `docker_services` loop.
- **Generated docs (never hand-edit):** `docs/network-addresses.md`, `docs/inventory.md` (rendered by `render-docs.yml`).
- **Secrets source of truth:** `docs/deployment-secrets.md` (type map, master list, rename map).
- **Kopia off-site transport (decided HD-31/HD-135):** Hetzner Storage Box **backup** supports **SSH/SFTP only**
  (port 23, `u653424`, SSH-key auth via `Hertzner-SB-Backup`) — **NOT S3**. iDrive e2 S3 dropped. Backend config:
  `kopia_sftp_*` in `group_vars/all.yml`; repo password `kopia_password`; `~~kopia-s3_api~~` retired.
- **Architecture rationale:** `docs/hardware.md`, `docs/services.md`, `docs/observability.md`,
  `docs/deployment.md`, `docs/network-vlans.md`, `docs/smart-home-failover.md`.
- **Per-item status / difficulty:** `todo.md` (HD-XX IDs referenced above).
