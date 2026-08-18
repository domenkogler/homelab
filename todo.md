# Homelab TODO Backlog

> Restructured **2026-08-17** from the old flat-priority backlog: human decisions moved to the front,
> work reorganized into domain modules, deferred items parked. Done items → [changelog.md](changelog.md);
> conventions → [`CONVENTIONS.md`](CONVENTIONS.md). Single source for planned work + open decisions (HD-XX).

**Status:** 64 open · 7 decisions · 2 purchases · 9 parked · 53 done (in changelog)

---

## 0. How this backlog works

- **One row = one outcome.** New work gets `HD-<next>` and links its owning `docs/*.md`.
- **Priority (P):** 1 = highest (how hot), module = what domain it touches. Priority is per-row, modules group.
- **Executors:** `AI` · `AI + gate` (human checkpoint) · `AI + Human` (joint) · `Human` (blocks).
- **Lifecycle:** open → (decided → front section) → done → changelog. Deferred → park section.
- **Conventions / onboarding:** consolidated rule index + 10-step service-onboarding checklist in [`CONVENTIONS.md`](CONVENTIONS.md).
- **Service stages:** service-onboarding rows (per-checklist tasks) carry **`Stage: N/10`** in the bold title = current Service-onboarding checklist step ([CONVENTIONS.md](CONVENTIONS.md) §5). `10/10` = deployed + verified; only then does a row close. Non-service tasks (network/fix/decision) carry no stage marker.

## 1. Human decisions & purchases — review first

### Decisions (blocking / waiting on a human call)

| ID | D | Exec | Item |
|----|---|------|------|
| HD-22 | 1 | AI + Human | *(decision)* **Weather 2000 (SI) source** — third-party/HACS vs core; retain or replace. Agent researches, human decides. · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-24 | 1 | Human | *(decision)* **TileBoard wall tablet model** — iPad / Android / repurposed; family/hardware purchase. · [interfaces.md](docs/interfaces.md) |
| HD-25 | 1 | Human | *(decision)* **Wake word final approval** — "Hey, assistant" is tentative; family meeting needed. · [smart-home.md](docs/smart-home.md) |
| HD-29 | 2 | Human | *(decision)* **Off-site storage: two Hetzner Storage Boxes (drop iDrive)** — ✅ **Decided (2026-08-18):** **two Hetzner Storage Boxes** — nearest-DC box = **live** (Immich originals S3 + family SMB/WebDAV drives), far-DC box (Helsinki/Falkenstein) = **backup** (Kopia repo). **iDrive e2 dropped** (Hetzner is cheaper per TB + SMB/WebDAV; single-provider risk on Hetzner accepted). Decide box size tier for Immich-originals growth + Kopia backup capacity. Input to HD-31. · [backup.md](docs/backup.md), [subscription.md](docs/subscription.md) |.md](docs/backup.md) |
| HD-39 | 1 | Human | *(decision)* **watchtower for Pi HA container** — Renovate + pinned images may suffice. · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-52 | 1 | AI + Human | *(decision)* **OpenCloud sync client packaging** — official client (opencloud-eu/desktop) ships AppImage only, no apt repo; options: AppImage → /opt + .desktop entry vs Debian `nextcloud-desktop` (protocol-equivalent) vs skip. Blocks office role's client. · [llm-office.md](docs/llm-office.md) |
| HD-55 | 2 | AI + Human | *(decision)* **Alloy per-host `instance` label** — every host scrapes `127.0.0.1:9998` → identical `instance` (series collide in Prometheus); set per-host (e.g. `{{ inventory_hostname }}`) before enabling Alloy on the Pi. · [observability.md](docs/observability.md) |

### Purchases

| ID | D | Exec | Item |
|----|---|------|------|
| HD-30 | 1 | Human | *(buy)* **Sign up Infomaniak kSuite** — email, CalDAV, catch-all aliases; ~€3–5/mo; secrets → 1Password `Homelab`. · [subscription.md](docs/subscription.md) |
| HD-31 | 1 | Human | *(buy)* **Sign up two Hetzner Storage Boxes** — ✅ **Decided (2026-08-18):** buy **two** Storage Boxes per HD-29 (live: nearest DC — Immich S3 + drives; backup: far DC Helsinki/Falkenstein — Kopia repo); **iDrive e2 dropped**. Depends on HD-29. · [subscription.md](docs/subscription.md) |

## 2. Active work — by module

### 2.1 Network & DNS — VLANs, firewall, DNS, VPN, router/switch

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-03 | 5 | AI + gate | 1 | **Network redo: implement VLAN segmentation** — currently flat `10.10.1.0/24` → VLANs 10/20/21/30/40/50/99, inter-VLAN firewall, CAPsMAN SSIDs. ✅ **IaC implemented + committed (`39b9f02`):** router + switch `community.routeros` roles (VLANs, DHCP, firewall, mgmt). ⏳ **NOT deployed to live gear** — Ansible can't run on this Windows host (see render note). Open before deploy: switch bridge-VLAN access-port membership (under review vs Rack.canvas), CAPsMAN SSID secret items, WG VPS peer. · [network-vlans.md](docs/network-vlans.md) |
| HD-89 | 1 | AI | 3 | **Disable/move unused AP ethernet ports off Mgmt VLAN** — wired devices on AP ports currently get full Management access (KOPS-046). · source qwen. · [network-vlans.md](docs/network-vlans.md) |

### 2.2 Storage, ZFS & UPS — NAS datasets, NFS, UPS/NUT

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-06 | 3 | AI | 1 | **NUT master on nas** — `usbhid-ups`, `upsd` (3493), `nut_exporter`, `upssched-cmd` notify. ✅ **IaC done+fixed** (SSOT exporter on master `:9199`, scrape via `all.yml` vars, `@latest` release w/ verified asset URL, `nut-exporter_password` upsd auth, SMTP+Signal notify wired via `NOTIFYCMD`, battery.runtime/charge thresholds, USB verify task — G1–G7). ⏳ **Missing:** live deploy on nas (host not provisioned yet) + battery-pull test; feeds HD-07 (clients) / HD-08 (metrics+alerts). · [hardware-ups.md](docs/hardware-ups.md) |
| HD-08 | 3 | AI | 2 | **Wire UPS metrics + alerts into Prometheus/Grafana** — Critical battery/runtime, Warning on-battery, Info transitions. Depends on HD-06/07. ✅ **Monitoring IaC implemented** (nut_* alert rules + UPS dashboard — commits `aaa3f7c`/`8c50d7f`). ⚠ **Deploy-time verification:** confirm DRuggeri/nut_exporter `nut_ups_status` bitmask + metric names, and that Grafana alert-rule provisioning loads (live check). · [hardware-ups.md](docs/hardware-ups.md) |
| HD-09 | 1 | AI | 2 | **UPS web-UI firewall rule** — open 80/443 Home→Mgmt for `10.10.99.9` only; Modbus 502 retired (no consumer). ✅ **IaC done** (router role: trusted-admin → `ups_management` 80/443); ⏳ not deployed. · [hardware-ups.md](docs/hardware-ups.md) |
| HD-26 | 1 | AI | 3 | **Confirm UPS SNMP UDP (161/udp)** on the NIC — TCP probe closed, UDP untested; one probe vs `10.10.99.9`. · [hardware-ups.md](docs/hardware-ups.md) |
| HD-128 | 1 | AI | 1 | **Resolve NVMe pool device-path TODO** — ✅ **IaC done:** replaced the literal `<970_EVO_SERIAL>` TODO in the `storage` role with SSOT var `storage_nvme_data_by_id` (host_vars/oldsrv.kogler.si.yml), referenced in the `nvme` pool vdevs, plus a fail-loud guard in `zfs_common.yml` that aborts any fresh-build CREATE while the path is still a placeholder/UNDEFINED (import-only runs unaffected) — HD-65/91 fail-closed policy (KOPS-057). Docs updated (deployment-preseed.md + storage-zfs.md pointer). ⏳ **Deploy-gated:** fill the REAL `/dev/disk/by-id/nvme-...` of the 970 EVO into `storage_nvme_data_by_id` at first pool create (read from the deployed host). Unblocks immich/opencloud db-backup (KOPS-026). [hardware-oldsrv.md](docs/hardware-oldsrv.md), [deployment-preseed.md](docs/deployment-preseed.md), [storage-zfs.md](docs/storage-zfs.md)
| HD-132 | 3 | AI | 2 | **Implement Authentik-as-LDAP for Samba self-service password (D7/HD-131)** — ✅ **IaC done (pull-model):** Samba `passdb backend = ldapsam` (LDAP outpost on oldsrv); `smbpasswd -a` provisioning REMOVED from both Ansible (`samba.yml`) and the D5 glue (`sync-authentik-users.sh`) — Authentik is SSOT, Samba pulls, so nothing rewrites a user's portal password; bind/base DN = design constants (`storage_samba_ldap`), bind password = `authentik-ldap_bind` (1Password); `ak-outpost-ldap` container added to authentik compose; smb.conf → 0600; docs updated. ⏳ **Deploy-gated (not live):** create the Authentik **LDAP provider** (base DN `DC=home,DC=kogler,DC=si`, bind DIRECT) + **outpost**, seed `authentik-ldap_bind` token, firewall 3389 to nas, live-verify a family drive mounts. · [deployment-compose.md](docs/deployment-compose.md), [storage-zfs.md](docs/storage-zfs.md) |

### 2.3 Platform & Deploy — Ansible, compose conventions, GitOps, Renovate, Doco-CD

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-02 | 3 | AI | 1 | **Activate Doco-CD** — GitOps CD, currently ⚠️ WIP / not activated: webhook + compose lifecycle + post-deploy hooks. Ansible handles everything until live. · [deployment.md](docs/deployment.md) |


### 2.4 Services & Edge — Traefik, SSO, service catalog, Matrix, VPS edge

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-122 | 2 | AI | 2 | **Matrix federation default decision** — federation enabled lets any Matrix user DM the family (KOPS-033); needs an explicit permit-list or disable before go-live. · source qwen. · [services-matrix.md](docs/services-matrix.md) |
| HD-40A | 3 | AI + Human | 3 | *(Phase 1.5)* **Provision VPS + establish public Traefik edge** — Contabo VPS purchased, WireGuard S2S home↔VPS, Traefik on VPS terminates TLS for public subset. Backends still on oldsrv over WG tunnel. Cloudflare A records updated. · [services-vps.md](docs/services-vps.md) |
| HD-40B | 3 | AI | 3 | *(Phase 1.5)* **Migrate public-facing services to VPS** — Authentik, OpenCloud web, Forgejo, Grafana. Databases stay on LAN over WG tunnel. · [services-vps.md](docs/services-vps.md) |
| HD-43 | 3 | AI | 3 | **Deploy/verify Media ·\*arr stack** — Stage: 4/10. recent IaC added the templates (jellyfin, seerr, sonarr, radarr, lidarr, prowlarr, bazarr, sabnzbd, qbittorrent+gluetun, profilarr, recyclarr) in `group_vars/home_servers.yml`; deploys on oldsrv bulk/media NFS + Samba shared media (owner `media`/1005, HD-94/HD-131). · [services.md](docs/services.md) |
| HD-44 | 2 | AI | 3 | **Deploy/verify new ops services** — Stage: 3/10. `dozzle` (`logs.`, Forward-Auth, viewer-only) and `traefik-ha` VIP edge on the Pi (added in recent IaC but not tracked/verified). · [services.md](docs/services.md) |
| HD-46 | 4 | AI | 3 | **Implement Matrix IaC (native-only)** — Stage: 4/10. ✅ **IaC done + committed (`62e0045`):** `matrix/` (Tuwunel, `matrix.kogler.si`) + `element-web/` (Element Web, `chat.kogler.si`) compose templates + `group_vars/home_servers.yml` entries; SSO → Authentik OIDC; registration closed (`allow_registration=false`, bootstrap via `registration_shared_secret`); RocksDB on `/srv/docker/matrix` (no external DB). Secrets → 1Password `matrix_api` + `matrix_password` ([deployment-secrets.md](docs/deployment-secrets.md)). ⏳ **Not deployed:** hosts not provisioned; needs HD-47 (public records + `.well-known` delegation) + Authentik OIDC provider/redirect URI. ⚠ **No bridges in Phase 1** (deferred — HD-48). · [services-matrix.md](docs/services-matrix.md) |
| HD-47 | 2 | AI | 3 | **Matrix public records + Federation** — publish `matrix`/`chat` (Cloudflare DNS-only) + `_matrix` well-known/SRV delegation; WAN allow 443 (8448 optional) to oldsrv; **no Forward-Auth on `/_matrix/*`**. · [services-traefik.md](docs/services-traefik.md), [network-dns.md](docs/network-dns.md) |
| HD-58 | 3 | AI | 3 | **Implement Stirling PDF service** — Stage: 4/10. self-hosted PDF toolkit (merge/split/compress/convert/number/OCR via Tesseract); family-friendly replacement for online PDF editors. Compose template + `group_vars/home_servers.yml` entry per the `docker_services` role (HD-50); catalog row in [`services.md`](docs/services.md). **Auth (decided 2025-08-15): anonymous mode** (`SECURITY_ENABLELOGIN=false`, default) **+ Authentik Forward-Auth at the Traefik edge** — same pattern as admin UIs; **native Stirling OIDC/SAML deliberately NOT used** (beta, adds per-user roles we don't need). **Exposure: internal-only** — no Cloudflare record, WAN-blocked; remote access only via the Headscale VPN (road-warrior), NOT public. Enable OCR (`TESSERACT_LANGS=eng+slv`, Slovenian). All processing in-memory, nothing persisted to disk → no ZFS/backup implication. Low RAM (~100–200 MB idle). · [services.md](docs/services.md) |
| HD-112 | 4 | AI | 2 | **Zipline + OpenCloud file share** — ⚠️ **TENSION with HD-131 (D2):** row assumes an OpenCloud **S3ng bucket**; HD-131 decides **OpenCloud = WebDAV/filesystem (not S3)** — re-examine whether Zipline writes into OpenCloud's filesystem (WebDAV) instead of an S3ng bucket before build. Stage: 1/10. All-in-one Zipline (URL shortener + QR generator + pastebin + file share) with **OIDC SSO** so users log in with the same OpenCloud credentials. Compose template + `group_vars/home_servers.yml` entry per `docker_services` role; catalog row in [`services.md`](docs/services.md). See [services.md](docs/services.md), [storage-zfs.md](docs/storage-zfs.md). |
| HD-113 | 2 | AI | 3 | **PairDrop P2P file share** — Stage: 1/10. Self-hosted direct "AirDrop-style" peer-to-peer transfer between devices (browser WebRTC, no upload through server, local-network device discovery). Compose template + catalog row per `docker_services` role; internal exposure. See [services.md](docs/services.md). |

### 2.6 Smart Home — HA primary/standby, Homematic, voice, devices

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-04 | 5 | AI + gate | 1 | **Pi redo: HAOS → Debian + HA Container + RaspberryMatic + Technitium secondary** — in-use device migration, done opportunistically during the network redo; approved direction, not yet applied. · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-72 | 3 | AI | 1 | **HA primary privileged → targeted caps** — replace `privileged: true` + `network_mode: host` with targeted `devices:` + `cap_add:` to drop root/cgroup-escape + keepalived/VRRP control on the smart-home controller (KOPS-014). · source qwen. · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-13 | 3 | AI + Human | 2 | **Homematic full-local (HmIP-RFUSB + RaspberryMatic)** — replace HAP cloud mode with local `homematic` XML-RPC; agent builds roles, human moves/fits the stick. Part of redo (HD-04). · [observability.md](docs/observability.md) |
| HD-14 | 2 | AI | 2 | **Export HA entity list** — enable HA Prometheus exporter; needed for TileBoard + Grafana. Wait for observability. · [smart-home.md](docs/smart-home.md) |
| HD-15 | 1 | AI | 2 | **Confirm HACS custom-component versions/repos** — `motion`, `ai_task`, Weather-2000, OneDrive, go2rtc via SSH / config git repo (REST API can't expose). · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-17 | 3 | AI | 2 | **Single failover button + `ha-failover.sh`** — RMat → wait → VIP → standby, on Homepage; manual-trigger design accepted. ✅ **IaC done + committed:** `ha-failover.sh` (forward + reverse), standby keepalived normal/failover configs (VRID/interface/priority vars), trigger API endpoint + systemd unit (`ha-failover-api`, token auth), Homepage forward/reverse buttons. ⏳ **Not deployed** (hosts not provisioned); deploy needs 1Password `ha-failover_api` (api → credential) + the HmIP-RFUSB stick physically moved at runbook time. · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-18 | 2 | Human | 2 | **Once: test HmIP-RFUSB pairing transfer** + entity reconstruction across stick move. Hands-on; requires HD-13. · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-124 | 3 | AI | 2 | **Keepalived hardening** — pin standby `:latest` image (KOPS-053) + replace `auth_type PASS` (obfuscated, KOPS-020) with a real auth mechanism. · source qwen. · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-20 | 1 | Human | 3 | **Confirm full Supervisor add-on list** — `/api/hassio/addons` returned 401 (non-admin token); needs admin/SSH on HAOS host. · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-21 | 1 | AI + Human | 3 | **Confirm ESPHome / Guition ESP32-S3 status** — `esphome` not loaded; agent checks network/repo, owner knows if the device was ever added. · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-23 | 1 | AI | 3 | **Confirm HmIP-SWO-B channels** — no rain / wind-direction on this sensor; verification only. · [smart-home.md](docs/smart-home.md) |
| HD-27 | 4 | AI + Human | 3 | **Voice pipeline build-out** — Whisper → Ollama → Piper containers, flash ESP32-S3 (ESPHome + microWakeWord), HA Assist on phones; GPU + physical flashing. · [smart-home-voice.md](docs/smart-home-voice.md) |

### 2.7 AI & Office — LLM stack, Open WebUI, office MCP, vector DB

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-100 | 4 | AI | 2 | **AI stack: LiteLLM spine** — Stage: 1/10. LLM gateway/router (local Ollama + OpenRouter gen + Cohere embed); single endpoint; only component holding upstream keys; `config.yaml.j2`; `litellm_master_key` auth. No host port binds. · [ai-stack.md](docs/ai-stack.md) |
| HD-101 | 4 | AI | 2 | **AI stack: Open Web UI** — Stage: 1/10. compose + `ai` route (**public**, Authentik OIDC + `crowdsec-only`); RAG (Cohere embed-v4, Docling, PGVector); pin secrets. · [ai-stack.md](docs/ai-stack.md), [services-traefik.md](docs/services-traefik.md) |
| HD-102 | 3 | AI | 2 | **AI stack: PGVector DB + backup** — Stage: 1/10. `pgvector` postgres on `db-internal`; add DBxx block to `db-backup` + Kopia scope (RAG index + chat history — KOPS-026 class). · [ai-stack.md](docs/ai-stack.md), [backup.md](docs/backup.md) |
| HD-103 | 3 | AI | 2 | **AI stack: Docling OCR** — Stage: 1/10. CPU `docling-serve` for RAG ingestion (spares dGPU). · [ai-stack.md](docs/ai-stack.md) |
| HD-104 | 4 | AI | 2 | **AI stack: OpenClaw agent + integrations** — Stage: 1/10. pinned version; register as model in LiteLLM; OpenCloud WebDAV skill (read/write family files); wire Open WebUI ↔ OpenClaw ↔ OpenCloud. · [ai-stack.md](docs/ai-stack.md) |
| HD-105 | 2 | AI | 2 | **AI stack: secrets + wiring** — Stage: 1/10 (→ step 2). `openrouter_api`, `cohere_api`, `litellm_master_key`, `openwebui_secret`, `pgvector_db` in 1Password; catalog rows + index map already added. · [deployment-secrets.md](docs/deployment-secrets.md) |
| HD-111 | 4 | AI | 2 | **Office MCP via Open WebUI** — Stage: 1/10 (MCP tool, partial checklist fit). `ppt-mcp` first (proven, from OpenWeb.md), then extend/parallel Word+Excel; register as MCP **servers in Open WebUI** (Tools); **retires AnythingLLM + LocPilot**. Server-side python-docx/pptx/openpyxl path for Linux (HD-107). Depends on HD-110. · [llm-office.md](docs/llm-office.md), [ai-stack.md](docs/ai-stack.md) |
| HD-28 | 3 | AI | 3 | **Office AI stack** — Ollama models/downloads, n8n Docker, ONLYOFFICE on Debian desktop + **MS Office via MCP tools in Open WebUI** (see HD-106–HD-111); depends on oldsrv GPU. Superseded: AnythingLLM + LocPilot replaced by the Open WebUI MCP path. · [llm-office.md](docs/llm-office.md) |

### 2.8 Security & Secrets — secrets hygiene, privilege, firewall, preseed hardening

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-59 | 2 | AI | 3 | **Internal service auth on flat Docker networks** — Ollama (`OLLAMA_AUTH_*` env vars), Kopia server (`--password` flag replacing `--without-password`), Signal CLI (basic auth wrapper on services-internal), Prometheus (`--web.config.file` with htpasswd). Flat networks = zero auth between containers; supply-chain compromise in one image gives attacker free rein. Auth tokens → 1Password `<service>-internal_api`. · [deployment-compose.md](docs/deployment-compose.md), Qwen-bugs KOPS-001/016/002 |

### 2.9 Backup & DR — ZFS snapshots, Kopia, off-site, restore drills

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-49 | 3 | AI | 3 | **Backup Matrix identity + media** — signing/identity keys (critical — reissue breaks rooms), homeserver DB (db-backup/Kopia), media store; add to backup policy. · [services-matrix.md](docs/services-matrix.md), [backup.md](docs/backup.md) |
| HD-34 | 2 | AI + Human | 4 | **Assess Kopia Web GUI vs CLI** at the first restore drill (agent assesses during the human-run yearly drill). · [backup.md](docs/backup.md) |

### 2.10 Docs & Family — family guides, docs, manual

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-32 | 2 | AI | 4 | **Write family guides `docs/manual/*`** — 10 Slovenian files, `status: wip`, not yet written; content well-specified; deferred until services live. · [manual/README.md](docs/manual/README.md) |
| HD-33 | 1 | AI | 4 | **Export live router config `rb4011_live.rsc`** — one-time RouterOS export; docs-only. · [network-ops.md](docs/network-ops.md) |

### 2.11 Finance & Subscriptions — budget apps, banks, billing

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-57 | 3 | AI + Human | 3 | **Finance pre-deploy prep (Actual Budget / Enable Banking)** — Stage: 1/10. verify EB redirect URL (`budget.kogler.si`) covered by Traefik + wildcard cert; Wise API token (read-only); IBKR Flex Query token URL; *(decision)* UniCredit SI email-transaction alerts (World Elite) vs SMS; *(decision)* `actual-server:nightly` vs stable + n8n bridge; enter initial capital base. · [services-finance.md](docs/services-finance.md) |

## 3. Park — deferred / optional / Phase 2

> Items here are not actively worked. They stay visible for planning.

| ID | D | Exec | Item |
|----|---|------|------|
| HD-36 | 3 | AI | **Internal AAAA records** — deferred/optional; needs stable per-host global addressing + IPv6 firewall mirroring. · [network-dns.md](docs/network-dns.md) |
| HD-37 | 3 | AI | **Long-term metric retention** — remote-write/downsampling (Thanos/VictoriaMetrics) only if ever needed. · [observability.md](docs/observability.md) |
| HD-38 | 2 | AI | **Prometheus Alertmanager** — only if Grafana-outage resilience demanded; Grafana Alerting covers Phase 1. · [observability.md](docs/observability.md) |
| HD-41 | 4 | AI | *(Phase 2)* **Proxmox role + VM lab** — bridges, storage, VMs; implementation order step 10. · [deployment-ansible.md](docs/deployment-ansible.md) |
| HD-42 | 3 | Human | *(Phase 2)* **Phase-2 hardware build** — Ryzen 9, open-frame chassis; only if Phase 1 insufficient; physical. · [hardware-phase2.md](docs/hardware-phase2.md) |
| HD-45 | 3 | AI | *(Phase 2)* **Re-evaluate Homelable (topology/rack visualizer)** — Pouzor/homelable, MIT, young project; network + rack canvas + nmap scan + live health + MCP; potential successor to `Rack.canvas` visual/Homepage reachability widget. Keep deferred until services are live; re-check maturity. Noted in `observability.md` + `network-rack.md`. · [observability.md](docs/observability.md) |
| HD-48 | 3 | AI + Human | **Requested-only bridges (deferred, Phase 2 best-effort)** — WhatsApp/Messenger/Signal bridges are **out of Phase 1 scope** (every bridge risks a real external account). Revisit **only if family asks**, and then only against **dedicated** numbers, accepting re-pairing/ban. · [services-matrix.md](docs/services-matrix.md) |
| HD-129 | 2 | AI | **Router DHCP → use internal resolver** — bootstrap assigns 1.1.1.1 not the internal resolver (KOPS-028); same outcome as HD-03 DNS setup, so fold in at live DNS. · [network-vlans.md](docs/network-vlans.md) |
| HD-130 | 2 | AI | **Low-severity opportunistic fixes** — Homepage docker.sock ro visibility, Seerr SQLite failure domain, pi edge cert expiry (KOPS-058/059/061); do opportunistically during service deployment. · [services.md](docs/services.md) |

## 3b. Activation notes - HD-02 (Doco-CD)

> **HD-02 is a MULTI-STAGE task - do NOT attempt as a single run.** Use `plan_task` to
> split into ordered, idempotent tasks with exact validations and an explicit dependency graph.

- Config finalization: turn .doco-cd.yml into the real deploy path (auto_discovery vs per-service compose), compose_files, reference, external_secrets mappings.
- 1Password secret provider: SECRET_PROVIDER=1password + SECRET_PROVIDER_ACCESS_TOKEN in the doco-cd compose env.
- Trigger wiring: webhook /v1/webhook (HTTP 80, WEBHOOK_SECRET HMAC, Forgejo webhook) and/or polling; decide polling vs webhook reachability first.
- Cross-task prerequisite: fix doco-cd metrics port 9120 + host-IP scrape in prometheus.yml.
- Post-deploy hooks: regenerate Homepage config + inventory docs + reload/commit+push. May depend on HD-12 - check before planning.
- Activate + verify: render templates and bring the container up; live activation likely on another host (human gate).

## 4. Status & dependency notes

- **HD-50 done** → blocks all `docker_services` deployments; **HD-16 done** (Authentik + Forward-Auth middleware) unblocks Forward-Auth services (HD-43/44/46).
- **HD-03 → HD-04 → HD-13** (network redo feeds Pi redo feeds Homematic full-local).
- **HD-06/07 done** → feeds HD-08. **HD-29 → HD-31** (off-site = **two Hetzner Storage Boxes**: live + backup; iDrive dropped — HD-131).
- 'Implemented, not deployed' rows (HD-03/06/17/46/60/61/62/63/64/94 …) stay open with a ⏳ marker until a live deploy happens — closing requires a deploy/verify pass, not just IaC.

## 5. Tally (as of restructure)

- Open rows: 64
- Decisions front: 7 · Buys: 2 · Park: 9
- Active work per module: ai=8, backup=2, docs=2, finance=1, net=2, observ=0, platform=1, security=1, services=10, smart=12, storage=5

## 6. Conventions quick-reference

> Full, consolidated rule set: [`CONVENTIONS.md`](CONVENTIONS.md) — this section is only the index.

| Area | Rule | Owning doc |
|------|------|-----------|
| Hostnames | single `kogler.si` namespace, flat subdomains | `docs/index.md` Conventions
| IPs | `docs/network-addresses.md` is the SSOT, generated, never hand-edit | `scripts/check_doc_ips.py`
| Secrets | 1Password `Homelab` vault, `<service>_<type>` naming | `docs/deployment-secrets.md`
| Compose | conventions & port binding policy | `docs/deployment-compose.md`
| Ansible | roles/templates/conventions | `docs/deployment-ansible.md`, `IaC/README.md`
| Service catalog | `group_vars/home_servers.yml` + `docs/services.md` | `docs/services.md`
| Validation | `bash scripts/validate-all.sh` before commit | `scripts/`

## 7. Service onboarding

> Uniform 10-step path for adding a service (exposure/auth → secrets → compose → registry → edge →
> state/backup → observability → validation → deploy gate → docs). Canonical copy:
> **`CONVENTIONS.md` §5 — Service-onboarding checklist**. Reproduced there; new services must clear all 10 steps.

