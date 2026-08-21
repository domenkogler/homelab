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
>
> **Execution log:** every manual command, chosen setting, captured value and deviation is recorded
> as-built in **[`deployment-journal.md`](deployment-journal.md)** (append-only). Steps get ticked
> `- [x]` + date here as they complete; human-only steps carry a **`[MANUAL]`** prefix.
> **Human feed:** paste raw notes into [`prompt-journal.md`](prompt-journal.md) DATA — the AI writes the entry.

> **✅ Decisions (2026-08-16 — overriding some phase wording below):** see `todo.md` for the full
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

> **Everything runs from the management laptop (Phase 0).** The `Homelab-ansible` 1Password vault is the
> **only** secrets backend — Ansible lookups resolve items at render time, keys are served on demand
> by the 1Password SSH agent. No secret is ever committed to Git.

### 1Password items — human-gated (not auto-generated)

> The 1Password item catalog SSOT is [`docs/deployment-secrets.md`](docs/deployment-secrets.md) — the canonical list
> of ALL items (generated + human + derived). This section lists **only the human-gated items**: external values,
> manual/deploy-provisioned tokens or keys, break-glass vaults, and connection refs. Auto-generatable items are
> seeded by [`scripts/provision-secrets.py`](../scripts/provision-secrets.py) and are **not repeated here**.
> `✓` = item already present. Ansible-consumed vs account/ref-only are split into two tables below.

#### A) Ansible-consumed secrets (rendered into IaC — need a value in `Homelab-ansible` before the phase runs)

| Item | type → `field=` | First needed in | In OP? |
|------|-----------------|-----------------|--------|
| **Phase 0** | | | |
| `ai_ssh` | ssh → `private_key`/`public_key` | Phase 0 | ✓ |
| `ansible-admin_ssh` | ssh → `private_key`/`public_key` | Phase 0 | ✓ |
| `laptop-domen_ssh` | ssh → `private_key`/`public_key` | Phase 0 (bootstrap key on laptop) | ✓ |
| `op_api` | api → `credential` (1Password Service Account token) | Phase 0 | ✓ |
| **Phase 1** | | | |
| `Hertzner-SB-Data` | — (connection ref; CIFS/SMB/WebDAV live box, `cifs` role) | Phase 1 (VPS) | ✓ |
| **Phase 1.5** | | | |
| `mikrotik-admin_login` | login → `password` | Phase 1.5 | ✓ |
| `network-snmp_api` | api → `credential` (SNMP RO community) | Phase 1.5 | ✓ |
| `pppoe_login` | login → `password` (`username`=PPPoE user) | Phase 1.5 (router) | ✓ |
| `wg_password` | password → `password` (**WireGuard S2S private key** — a `wg genkey` value, never a random password; the auto-tool does not write it) | Phase 1.5 | ✓ |
| **Phase 2** | | | |
| `smtp_login` | login → `password` (**SMTP relay, HD-54 SMTP2Go** — shared by Grafana + NUT; `username`=SMTP user/notify email) | Phase 2 | ✓ |
| **Phase 3** | | | |
| `authentik_login` | login → `password` (bootstrap admin) | Phase 3 | ✗ |
| `cloudflare_api` | api → `credential` (ACME DNS-01) | Phase 3 | ✓ |
| `forgejo_api` | api → `credential` (Forgejo deploy token) | Phase 3 | ✗ |
| `grafana_login` | login → `password` (admin) | Phase 3 | ✓ |
| `ha_api` | api → `credential` (long-lived HA token) | Phase 3 | ✗ |
| `headscale_api` | api → `credential` (OIDC client secret) | Phase 3 | ✗ |
| `signal_api` | api → `credential` (`username`=phone number) | Phase 3 | ✗ |

#### B) Account / connection refs — NOT consumed by Ansible (human maintenance / break-glass)

> These live in 1Password for **a human / break-glass recovery**, not as an Ansible `lookup`. They do not gate
> a deployment phase; keep them in the vault for operating-account access, not in a compose template.

| Item | What it is | Vault | In OP? |
|------|-------------------------|-------|--------|
| `netcup-ccp_login` | netcup Customer Control Panel login (billing/orders) | Ansible vault | ✓ |
| `netcup-scp_login` | netcup Server Control Panel login (reboot/OS reset) | Ansible vault | ✓ |
| `netcup-vps_login` | netcup root/OS credential — **separate break-glass vault** | separate vault | ✓ |
| `Hertzner-SB-Backup` | Hetzner backup Box SSH/SFTP connection ref (kopia, no password) | Ansible vault | ✓ |

> **Provisioning note:** the generated items — the DB items `authentik_db`/`opencloud_db`/`immich_db`/`forgejo_db`/
> `pgvector_db`, the secrets `authentik_password`/`nut_password`/`nut-exporter_password`/`kopia_password`/
> `ha-vrrp_password`/`n8n_password`/`matrix_password`/`opencloud-collab_password`/`openwebui_secret`, and the
> API creds `litellm_master_key`/`immich-ml-internal_api`/`n8n-webhook_api`/`signal-internal_api`/
> `kopia-server-internal_api`/`prometheus-internal_api` — are seeded automatically into `Homelab-ansible` by the
> provisioner above, so they are deliberately **absent** from the human-gated tables. Exception (manual key):
> `wg_password` stays out of the auto-catalog because WireGuard needs a real private key; provision it by hand
> with a `wg genkey` value.

---

## Phase 0 — Bootstrap the Management Laptop

> **Depends on:** nothing (first action).
> **1Password prerequisites:** `laptop-domen_ssh`, `ansible-admin_ssh`, `ai_ssh`, `op_api`, and
> `kopia_password` (seed `password`-type item read by `test-1password.yml`) all exist in `Homelab-ansible`.
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
   `common` → `docker` → **`vps-hardening`** (HD-154: fail2ban + nftables default-deny + docker daemon) → `network` (static public IP per SSOT) → `docker_services` → `monitoring`.
3. **Mandatory hardening checklist (HD-154, enforced by the `vps-hardening` role — NOT optional prose):**
   - **SSH:** `PasswordAuthentication no`, `PermitRootLogin no`, `MaxAuthTries 3`, `AllowUsers ansible-admin` only (post_install.sh + role assert).
   - **fail2ban:** SSH jail (`maxretry 3`) + `http-auth` jail for public login pages (n8n/Grafana/Forgejo) — role-installed + enabled.
   - **Firewall (nftables):** default-deny inbound; allow only `:443` (Traefik) + `:51820` (WG S2S) + loopback + established/related; ICMP echo limited. Role-deployed `/etc/nftables.conf`.
   - **Docker daemon:** `iptables: true`, `userland-proxy: false`, `live-restore: true`, capped json-file logs; no public container `privileged` / host-net by compose policy.
   - **SSO admission:** root disabled, per-host keys only (Domen + Ansible), no `ai-debug` on a public box.
4. **Edge tier** — enable the self-contained subset in `group_vars/vps.yml`: **`traefik`, `crowdsec`, `authentik`**
   (+ co-located DBs); Traefik issues the wildcard `*.kogler.si` cert via ACME **DNS-01** (`cloudflare_api`).
   The `dns.yml` control-plane playbook (roles/cloudflare_dns) adds the public records — start with `vps` A/AAAA,
   then `sso` (+ each public app as it lands).
5. **Live Box CIFS mount** — the `cifs` role (in `vps.yml`) mounts `//u653411.your-storagebox.de/backup` (`Hertzner-SB-Data`) at `/mnt/storagebox` on the VPS (0600 creds from 1Password) for Immich originals + encoded-video + OpenCloud files (HD-135 storage split). Applied automatically by Ansible; verify `mountpoint --q /mnt/storagebox` after deploy.
6. **NOT yet online (needs WG S2S + oldsrv):** immich-app→immich-ml, litellm→ollama — these expose only after the

**Verify:**
- `sso.kogler.si` (Authentik) reachable publicly through the VPS Traefik with the wildcard cert; crowdsec decision active.
- **Authentik OAuth2 Blueprint** — verify the `ks-oidc.yml` blueprint imports + the secret-egress glue seeds client creds on the pinned `2026.5.6` (version-specific flow/signing/binding attrs). Tracked: **HD-149**.
- `vps` A/AAAA records live at Cloudflare (via `dns.yml`); `ansible-admin` SSH works with the agent.
- **Hardening verified (HD-154):** `fail2ban-client status sshd` shows the SSH jail active; `nft list ruleset` shows the default-deny input chain with `:443`/`:51820` accepts; `sshd -T | grep -E 'maxauthtries|passwordauthentication|permitrootlogin'` = 3/no/no; `docker info` shows `userland-proxy=false` + capped log driver.
- Live Box CIFS mount returns data; VPS NVMe under 80%.

**Deploy-gated verification (Phase 1):**
- **HD-40A** — root-level VPS playbook run in WSL; Traefik wildcard cert via ACME DNS-01 (`cloudflare_api`); `sso` record via `dns.yml`; live-Box CIFS mount. · [services-vps.md](docs/services-vps.md)
- **HD-135** — live-Box CIFS mount; cross-host app wiring; `foto`/`file`/`git`/`ai` round-trip over the WG S2S tunnel (peer pubkeys in Phase 1.5). · [services-vps.md](docs/services-vps.md)
- **HD-149** — Authentik `ks-oidc.yml` Blueprint live-apply on `2026.5.6` (flow slugs, signing_key, app-provider binding) + glue harvests client creds; `redirect_uris` match compose (`ai`/`vpn`/`matrix`/`file`). · [deployment-compose.md](docs/deployment-compose.md)
- **HD-143** — create write-scoped `authentik-provision_api` 1Password item; glue seeds the 8 OIDC client-creds items after Blueprint (NOT `opencloud-service_api`). · [deployment-ansible.md](docs/deployment-ansible.md)
- **HD-144** — uncomment OpenCloud OIDC block, drop Forward-Auth, add CSP `opencloud/csp.yaml.j2` (provider = Blueprint entry HD-142). · [deployment-compose.md](docs/deployment-compose.md)
- **HD-146** — `vps.yml` deploy ordering enforced (authentik precedes every OIDC consumer) + glue wired in `deploy-service.yml`. · [deployment-ansible.md](docs/deployment-ansible.md)
- **HD-166** — create `opencloud-collab_password` (single JWT, both sides); first deploy on VPS Phase 1; live-verify `file`→ONLYOFFICE iframe + CSP. · [services-office.md](docs/services-office.md)
- **HD-159** — blackbox liveness: verify the `wg_icmp` probe (VPS→home router WG-side peer IP, `wg_s2s_vps.router_ip`) + the Critical `wg-s2s-down` Grafana rule fires on a `wg down` test at Phase 1. · [observability.md](docs/observability.md)

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

**Deploy-gated verification (Phase 1.5):**
- **HD-03** — Network redo live: VLANs 10/20/21/30/40/50/99 + inter-VLAN firewall + CAPsMAN SSIDs NOT yet on live gear (deploy runnable via Ansible in WSL Debian); open switch bridge-VLAN membership + CAPsMAN SSID secret items; WG S2S VPS peer (IaC present VPS `77833f1`/router `85ba6dc`) — provision both peer pubkeys + bring up tunnel. · [network-vlans.md](docs/network-vlans.md)
- **HD-09** — UPS web-UI firewall rule (80/443 Home→Mgmt for `10.10.99.9` only) not deployed. · [hardware-ups.md](docs/hardware-ups.md)
- **HD-89** — disable/move unused AP ethernet ports off Mgmt VLAN (wired devices currently get full Management access). · [network-vlans.md](docs/network-vlans.md)
- **HD-161** — router/switch `api_facts` assert-before-mutate step + router API TLS decision (`routeros_api_tls`, TODO after Let's Encrypt). · [deployment-ansible.md](docs/deployment-ansible.md)
- **HD-26** — confirmantional UPS SNMP UDP (161/udp) probe must run from a Mgmt-VLAN (99) host; even if present, no consumer uses it (NUT/USB is the monitor). · [hardware-ups.md](docs/hardware-ups.md)

---

## Phase 2 — NAS Fresh Install + Storage + UPS Master (`nas.kogler.si`)

> **Depends on:** Phase 1 (VPS edge + Authentik live), Phase 1.5 (router VLANs + DHCP). NAS is on VLAN 10 (Home, access) + VLAN 99 (Mgmt, native).
> **1Password prerequisites (new this phase):** `nut_password` (password→`password`), `smtp_login`
> (login; `username`=notify email/SMTP user, `password`=SMTP pass). SSH items from Phase 0 are injected
> by `post_install.sh`. **No Docker on NAS.**
> **Continuation:** the NAS is the **NUT master** — `oldsrv` and `pi` are NUT clients and depend on it.

1. **Preseed install** — boot the HP MicroServer from `IaC/host/nas/preseed.cfg`
   (single-SSD boot; ZFS HDDs **not touched** by preseed) + shared `IaC/host/post_install.sh`
   (ansible-admin + ai-debug keys, sshd hardening).
2. **Ansible** — `ansible-playbook -i inventory.ini playbooks/storage.yml`:
   `common` → `ai_diag` → `network` (static on VLAN 10, IP per SSOT) → `storage` (ZFS import/create, datasets, NFS exports) → `nut` (mode=master) → `cockpit`.
3. **NUT master** — `nut-server` + `usbhid-ups` (PowerWalker USB), `upsd` listening intra-VLAN
   `nas:3493` (no inter-VLAN rule needed — see `docs/hardware-ups.md`), `nut_exporter` as a
   host binary (:9199), `upssched-cmd` email/Signal notify (`smtp_login`).
4. **Storage** — pools already created by the one-time bootstrap runbook (`docs/hardware-nas.md` → Pool-Creation Runbook; role is import-only for tank/bulk); Ansible imports them + creates datasets, exports (NFS/SMB); mount layout per `docs/hardware-nas.md`.

**Verify:**
- `zpool status` healthy; `upsc powerwalker@nas` returns live UPS data.
- `nut_exporter` scrapable on :9199; cockpit reachable at `cockpit-nas.kogler.si` (Traefik file-provider route).

**Deploy-gated verification (Phase 2):**
- **HD-06** — NUT master live on nas: `upsd` :3493 + `nut_exporter` :9199 + `upssched-cmd` SMTP/Signal notify; **battery-pull test** on the PowerWalker USB. · [hardware-ups.md](docs/hardware-ups.md)
- **HD-07** — NUT clients on `oldsrv` (Phase 3) / `pi` (Phase 4) — `upsmon` slave + per-host shutdown delay (60/0). · [hardware-ups.md](docs/hardware-ups.md)
- **HD-08** — live-verify `nut_exporter` `nut_ups_status` bitmask + metric names + Grafana alert-rule provisioning loads (blocked on HD-06). · [hardware-ups.md](docs/hardware-ups.md)
- **HD-132** — create Authentik **LDAP provider** `DC=home,DC=kogler,DC=si` (bind DIRECT) + outpost; seed `authentik-ldap_bind`; live-verify a family drive mounts. Samba (nas, the client) reaches the VPS outpost over WG at the VPS's WG-side address — nothing is published publicly (HD-186). · [deployment-compose.md](docs/deployment-compose.md)

---

## Phase 3 — oldsrv Fresh Install + Internal/GPU Compute Host (`oldsrv.kogler.si`)

> **Depends on:** Phase 1.5 (VLAN 99 native + tags), Phase 2 (NAS NUT master for the `nut` client),
> Phase 1 (VPS edge + Authentik live).
> oldsrv is the **internal/GPU/LAN compute host**: the GPU + storage-bound backends (ollama, immich-ml,
> jellyfin/iGPU, sunshine), HA **standby**, DNS, media/*arr, observability, and an **internal** Traefik edge
> (the `ha` VIP + internal routes). The **public edge + stateless/live-data public apps live on the VPS**
> (Phase 1) — the wildcard cert is issued by the VPS Traefik; oldsrv serves internal-only + GPU workloads.
> **1Password prerequisites (new this phase):** the platform block below must exist in `Homelab-ansible`.
> **Continuation:** the GPU/AI stack (Phase 1's deferred `litellm→ollama`, `immich-app→immich-ml` links) comes
> online here once the WG S2S tunnel to the VPS exists; HA primary (Phase 4) builds on this node's standby.

1. **Preseed install** — boot from `IaC/host/oldsrv/preseed.cfg` (NVMe partitions; iGPU-primary, dGPU RX 7600
   reserved for compute) + shared `post_install.sh`.
2. **Ansible** — `ansible-playbook -i inventory.ini playbooks/home_servers.yml` (ordered):
   `common` → `ai_diag` → `docker` → `network` (trunk VLAN 99 native + 10/20/50 tagged) → `nut` (client,
   `shutdown_delay_seconds=60` → `powerwalker@nas`) → `amd_rocm` (ROCm stack, udev, `OLLAMA_KEEP_ALIVE=5m`)
   → `desktop` → `office` → `cockpit` → `docker_services` → `home_assistant` (standby) → `monitoring`.
3. **Services (internal/GPU subset)** — `docker_services` deploys the **oldsrv** subset in
   `group_vars/home_servers.yml`: ollama, immich-ml, technitium (primary), pihole, homepage
   (moves to the VPS per HD-180/183), dozzle, signal-cli-rest-api, sunshine
   (`homelab_mode == 'desktop'` gated), home-assistant-standby, and the media stack
   (jellyfin iGPU + seerr/sonarr/radarr/lidarr/prowlarr/bazarr/sabnzbd/qbittorrent/profilarr/recyclarr).
   The public apps (traefik/crowdsec/authentik/opencloud/forgejo/immich-app/grafana and the
   observability backend) are on the VPS (Phase 1/HD-135), not oldsrv.

   ✅ **Templates status (live):** all compose templates exist under `docker_services/` — HD-16
   (authentik + Forward-Auth middleware) and HD-50 (`docker_services` role) are **done**. The authoritative
   service list is `group_vars/home_servers.yml` (the loop source of truth) + `docs/services.md`; it is
   **not** a per-template TODO list. New services are added by dropping a template under
   `docker_services/<name>/` and listing it in `home_servers.yml` — no per-template placeholder caveats.

4. **HA standby** — `home-assistant-standby` compose + keepalived (`ha-vrrp_password`); disabled by default.

**New 1Password prerequisites (Phase 3):**
- ~~`cloudflare_api` (api→`credential`) — wildcard cert~~ — **moved to Phase 1 (VPS)**: the wildcard is issued by the VPS Traefik (HD-178); oldsrv consumes synced certs via its own pull timer (HD-181, decided HD-204).
- `kopia_password` (password) — Kopia off-site = **backup Box over SSH/SFTP (port 23)** (`kopia_sftp_*` in `all.yml`; SSH key in `Hertzner-SB-Backup`; **no password secret item**). ~~`kopia-s3_api`~~ retired (iDrive e2 dropped).
- `authentik_db` (db→`password`), `authentik_password` (password→`password`), `authentik_login` (login→`password`)
- `opencloud_db`, `immich_db`, `forgejo_db` (db→`password` each)
- `forgejo_api` (api→`credential`) — renovate token + Forgejo Actions deploy runner
- `grafana_login` (login→`password`), `smtp_login` (login→`password`)
- `ha_api` (api→`credential`), `ha-vrrp_password` (password→`password`)
- `headscale_api` (api→`credential`) — OIDC client secret
- `signal_api` (api; `username`=phone, `credential`=captcha) — signal-cli-rest-api

**Verify:**
- `docker compose ps` for every service is healthy; `systemctl status docker-compose@<service>`.
- Homepage (`home.kogler.si`) reachable after Authentik SSO (moves to the VPS per HD-180; until HD-183 lands it still renders on oldsrv). Grafana/Forgejo are VPS-edge services — verify via their public URLs in Phase 1, not here.
- Wildcard `*.kogler.si` cert: issued on the **VPS** (Phase 1, HD-178) — oldsrv serves internal routes from the synced pair (pulled from the VPS by its own timer, HD-181); no ACME logs expected on oldsrv.

**Deploy-gated verification (Phase 3):**
- **HD-105** — **AI-stack pre-deploy gate:** create the 7 1Password items (`openrouter_api`, `cohere_api`, `litellm_master_key`, `openwebui_secret`, `openwebui_api`, `pgvector_db`, `openclaw_gateway_token`) + Authentik OIDC providers per [`deployment-ai-stack-secrets.md`](docs/deployment-ai-stack-secrets.md); blocks HD-100→104. · [deployment-secrets.md](docs/deployment-secrets.md)
- **HD-100** — LiteLLM live: create `litellm_master_key`/`openrouter_api`/`cohere_api`; MUST pin `litellm_version` semver; OpenAI-compatible completion + embed respond. · [services-ai.md](docs/services-ai.md)
- **HD-101** — Open Web UI live: `openwebui_secret` + `openwebui_api` (Authentik OIDC, redirect `https://ai.kogler.si/oauth2/callback`); OIDC login + LiteLLM completion + RAG. · [services-ai.md](docs/services-ai.md)
- **HD-102** — PGVector live: `pgvector_db`; extension init + db-backup DB04 dump. · [services-ai.md](docs/services-ai.md)
- **HD-103** — Docling live: first start downloads HF models (multi-GB); v1 API converts a Slovenian scan. · [services-ai.md](docs/services-ai.md)
- **HD-104** — OpenClaw live: `openclaw_gateway_token`; `openclaw onboard` → schema-valid `openclaw.json` (LiteLLM + WebDAV); Open WebUI ↔ OpenClaw ↔ OpenCloud round-trip. · [services-ai.md](docs/services-ai.md)
- **HD-58** — Stirling PDF: re-render `services-inventory-generated.md`; OCR `slv` + Forward-Auth chain live-verify. · [services.md](docs/services.md)
- **HD-113** — PairDrop: re-render `services-inventory-generated.md`; WebRTC/signaling through Traefik (may need `RTC_CONFIG` STUN/TURN). · [services.md](docs/services.md)
- **HD-46** — Matrix live: hosts provisioned; needs HD-47 records + Authentik OIDC provider/redirect URI; verify profile endpoints require auth (HD-122). · [services-matrix.md](docs/services-matrix.md)
- **HD-47** — Matrix public records + `_matrix` well-known/SRV delegation; WAN 443 (8448 optional). · [services-traefik.md](docs/services-traefik.md)
- **HD-122** — Matrix federation hardening live-verify that profile endpoints require auth at first deploy. · [services-matrix.md](docs/services-matrix.md)
- **HD-59** — internal service auth: `kopia-server-internal_api` + `prometheus-internal_api` 1Password items; wire consumers. · [deployment-compose.md](docs/deployment-compose.md)
- **HD-160** — services-internal sibling auth: create `immich-ml-internal_api` + `openclaw-opencloud_api` 1Password items; verify Immich v3 ML-auth env names + `openclaw onboard` + WebDAV round-trip; Ollama stays isolated on `llm-backend`. · [deployment-compose.md](docs/deployment-compose.md)
- **HD-43** — Media `*arr` stack Stage: 4/10; deploy + verify on oldsrv bulk/media NFS. · [services.md](docs/services.md)
- **HD-44** — ops services (`dozzle`, `traefik-ha` VIP edge) Stage: 3/10; deploy + verify. · [services.md](docs/services.md)
- **HD-128** — at first pool create on oldsrv, fill the REAL `/dev/disk/by-id/nvme-…` into `storage_nvme_data_by_id` (read from the deployed host); unblocks immich/opencloud db-backup (KOPS-026). · [hardware-oldsrv.md](docs/hardware-oldsrv.md), [storage.md](docs/storage.md)

---

## Phase 4 — Pi Fresh Install + HA Primary (`pi.kogler.si`)

> **Depends on:** Phase 1.5 (VLANs), Phase 2 (NAS NUT master). The Pi is the HA **primary** node;
> oldsrv (Phase 3) is standby. Both share one `configuration.yaml` and the VIP (`ha-vip`).
> **1Password prerequisites (new this phase):** none beyond Phase 3 (`ha_api`, `ha-vrrp_password`,
> `nut_password`, `smtp_login` already exist). Add `ha-mqtt_login` if/when MQTT is introduced
> (currently out of scope).
> **Continuation:** `ha.kogler.si` → VIP becomes live here; observability (Phase 6) scrapes the HA
> exporter and smart-home work (Phase 7) builds on this node.

1. **Flash + first-boot config** — download the latest raspi.debian.net Pi 4 image, flash to microSD,
   then run `IaC/host/pi/first-boot-config.sh` on the boot partition **before first boot**
   (see [`deployment-preseed.md` → Pi Image Deployment](docs/deployment-preseed.md)).
2. **Ansible** — `ansible-playbook -i inventory.ini playbooks/raspberry_pi.yml`:
   `common` → `ai_diag` → `network` (static on VLAN 10, IP per SSOT) → `nut` (client,
   `shutdown_delay_seconds=0`) → `docker` → `docker_services` (Pi-specific:
   `home-assistant-primary`, `technitium-secondary`, `traefik-ha` — no pihole/raspberrymatic;
   KOPS-063: containers BEFORE the HA role so they are up when keepalived/VIP renders)
   → `home_assistant` (**primary**, Debian + HA Container + keepalived → VIP `ha-vip`)
   → `monitoring` (Alloy only).
3. **Local Homematic** — ⏳ **parked** (HD-13): `raspberrymatic` was dropped from the Pi loop
   (2026-08-18); re-add with an HmIP-RFUSB only when local RF is purchased (HmIP-HAP stays in
   cloud mode until then).

**Verify:**
- `ha.kogler.si` resolves to the VIP (`ha-vip` per SSOT); `keepalived` is MASTER on the Pi.
- Technitium (on oldsrv/Pi) resolves `*.kogler.si` internally; Pi-hole filtering active.
- HA web login via Authentik SSO (native OIDC on the `ha` route — no Forward-Auth).
- Manual failover runbook in `docs/smart-home-failover.md` passes Pi→oldsrv and back.

**Deploy-gated verification (Phase 4):**
- **HD-04** — Pi redo: HAOS → Debian + HA Container + Technitium secondary; leaves HmIP-HAP in cloud mode (no HmIP-RFUSB yet — HD-13 parked). · [home-assistant-current.md](docs/home-assistant-current.md)
- **HD-17** — single failover button + `ha-failover.sh` needs `ha-failover_api` 1Password + HmIP-RFUSB stick physically moved at runbook time. · [smart-home-failover.md](docs/smart-home-failover.md)
- **HD-124** — keepalived hardening live (pinned `keepalived_version: 2.3.4`, hosts unprovisioned). · [smart-home-failover.md](docs/smart-home-failover.md)

---

## Phase 5 — GitOps Deploy Button (Forgejo Actions → Ansible) — Doco-CD removed (HD-150)

> **Depends on:** Phase 3 (Forgejo + services live, Renovate running), Phase 4 (HA live).
> **1Password prerequisites:** `forgejo_api` + `op_api` (already created). Doco-CD + `doco-cd_password` are
> **removed** (HD-150) — single Ansible-only deploy path; the deploy button runs Ansible (not a webhook agent).
> **Continuation:** once active, merges are applied via the Forgejo Actions deploy button instead of manual Ansible runs.

1. **Forgejo Actions deploy workflow** — add `.forgejo/workflows/deploy.yml` (manual `workflow_dispatch`,
   `--tags` selector); the runner SSHes to the target host(s) and runs `ansible-playbook`
   (`vps.yml` for VPS, `home_servers.yml` for oldsrv).
2. **1Password for the runner** — `op_api` Service Account token stored as a Forgejo secret; the runner
   resolves secrets at Ansible render time (same as the control node).
3. **Trigger** — no webhook; you click the **deploy button** on Forgejo (Dependency Dashboard / Actions tab).
4. **Renovate** — already live (Phase 3); it opens PRs; the deploy button applies them via Ansible.
5. **Metrics** — none (no Doco-CD exporter); Prometheus scrape set stays Traefik/CrowdSec + services.
6. **Post-deploy hooks** — Ansible regenerates Homepage config + `services-inventory-generated.md` → commit+push.

**Verify:** a Renovate PR → merge → Forgejo **deploy button** → service updated with **no manual Ansible run**.

---

## Phase 6 — Observability & Alerting Hardening

> **Depends on:** Phase 3 (monitoring role, Prometheus/Loki/Grafana central), Phase 4 (HA exporter).
> **1Password prerequisites:** existing — `ha_api` (HA bearer), `smtp_login`,
> `signal_api` (Signal notify via n8n). **Runs in parallel with Phase 5+.**

- UPS metrics + alerts in Grafana (Critical battery/runtime, Warning on-battery, Info transitions) — **HD-08**
- UPS web-UI firewall rule (80/443 Home→Mgmt for the `ups` host only, + touches Phase 1.5 firewall) — **HD-09**
- HA entity list export (Prometheus exporter) for the HA Dashboard (lovelace) + Grafana — **HD-14**
- HA recorder trim (`purge_keep_days`) to protect the Pi SD — **HD-19**
- Grafana Alerting tiers (Critical/Warning/Info), self-monitoring, n8n + signal-cli-routing (details: `docs/observability.md`)

**Deploy-gated verification (Phase 6):**
- **HD-14** — enable HA Prometheus exporter → HA Dashboard `lovelace` + Grafana (`ha_api`). · [smart-home.md](docs/smart-home.md)
- **HD-19** — HA recorder trim (`purge_keep_days: 2`) + log strategy to protect the Pi SD. · [observability.md](docs/observability.md)

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
7. Office AI stack (Ollama models, n8n, Office MCP path per HD-108/111 — AnythingLLM/LocPilot retired, ONLYOFFICE) — **HD-28**

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

**Deploy-gated verification (Phase 8):**
- **HD-49** — Back up Matrix identity + media (signing/identity keys, homeserver DB, media store) into the backup policy. · [services-matrix.md](docs/services-matrix.md)
- **HD-34** — Assess Kopia Web GUI vs CLI at the first (human-run) restore drill. · [backup.md](docs/backup.md)

---

## Phase 9 — Documentation & Polish

> **Depends on:** services live (Phase 3+) to document accurately.
> **1Password prerequisites:** `mikrotik-admin_login` (export the live config).

- Write family guides `docs/manual/*` (10 Slovenian files, `status: wip`) — **HD-32**
- Export live router config `rb4011_live.rsc` (RouterOS export) — **HD-33**

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
Phase 5 (GitOps: Forgejo Actions deploy button → Ansible)
   ▼
Phase 6-9 (observability, smart-home, backup, docs) ── can run in parallel
   ▼
Phase 10 (deferred: Phase-2 Proxmox hardware, HD-41/42)
```

**Phase prerequisites (1Password) recap — what must exist before you start:**
- **Phase 0:** `laptop-domen_ssh`, `ansible-admin_ssh`, `ai_ssh`, `op_api`, `kopia_password` (seed)
- **Phase 1 (VPS):** + `netcup-ccp_login`, `netcup-scp_login`, `netcup-vps_login` (separate vault), `Hertzner-SB-Data`,
  `Hertzner-SB-Backup`, `cloudflare_api`, `authentik_db/password/login`, `opencloud_db`, `immich_db`, `forgejo_db`,
  `forgejo_api`, `grafana_login`, `smtp_login`
- **Phase 1.5 (network):** + `mikrotik-admin_login`, `wg_password`
- **Phase 2:** + `nut_password`, `smtp_login`
- **Phase 3:** + `ha_api`, `ha-vrrp_password`, `headscale_api`, `signal_api`
- **Phase 4–9:** no new items (reuse the above)
- **Phase 5 specifically:** `forgejo_api` + `op_api` (deploy runner token) — Doco-CD `doco-cd_password` retired (HD-150)
- **Phase 8 (backup):** no S3 items — Kopia = backup Box via **SSH/SFTP** (`kopia_password` + SSH key `Hertzner-SB-Backup`)
- **Phase 10:** future (`proxmox_login`, etc.)

---

## Host → Playbook → VLAN Mapping

| Host | FQDN | VLANs | Playbook | Key roles (order) |
|------|------|-------|----------|-------------------|
| router | `router.kogler.si` | L3 all | `router.yml` | `router` |
| switch | `switch.kogler.si` | L2 trunk | (`.rsc`) | — |
| nas | `nas.kogler.si` | 10 + 99 native | `storage.yml` | common → ai_diag → network → storage → nut(master) → cockpit |
| oldsrv | `oldsrv.kogler.si` | 99 native + 10/20/50 tagged | `home_servers.yml` | common → ai_diag → docker → network → nut(client) → amd_rocm → desktop → office → cockpit → docker_services → home_assistant(standby) → monitoring |
| pi | `pi.kogler.si` | 10 | `raspberry_pi.yml` | common → ai_diag → network → nut(client) → docker → docker_services(pi) → home_assistant(primary+keepalived) → monitoring(alloy) |
| vps | `vps.kogler.si` | public | `vps.yml` (**Phase 1**) | common → docker → vps-hardening → network → cifs → wireguard(cond.) → docker_services → monitoring |
| — | all | — | `all.yml` | `/etc/hosts` sync |
| laptop | control | 10 | `render-docs.yml` + `dns.yml` | renders `docs/network-addresses-generated.md`; maintains Cloudflare public DNS records |

> Static IPs: [`docs/network-addresses-generated.md`](docs/network-addresses-generated.md) (SSOT).

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
- **Generated docs (never hand-edit):** `docs/network-addresses-generated.md`, `docs/services-inventory-generated.md` (rendered by `render-docs.yml`).
- **Secrets source of truth:** `docs/deployment-secrets.md` (type map, master list, rename map).
- **Kopia off-site transport (decided HD-31/HD-135):** Hetzner Storage Box **backup** supports **SSH/SFTP only**
  (port 23, `u653424`, SSH-key auth via `Hertzner-SB-Backup`) — **NOT S3**. iDrive e2 S3 dropped. Backend config:
  `kopia_sftp_*` in `group_vars/all.yml`; repo password `kopia_password`; `~~kopia-s3_api~~` retired.
- **Architecture rationale:** `docs/hardware.md`, `docs/services.md`, `docs/observability.md`,
  `docs/deployment.md`, `docs/network-vlans.md`, `docs/smart-home-failover.md`.
- **Per-item status / difficulty:** `todo.md` (HD-XX IDs referenced above).
