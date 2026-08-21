# Homelab TODO Backlog

> Restructured **2026-08-17** (and trimmed 2026-08: struck rows removed → [changelog.md](changelog.md); deploy-gated live-verify moved to [`deployment-tasks.md`](deployment-tasks.md) per-phase blocks). Human decisions moved to the front, work organized into domain modules, deferred items parked. Done items live in [changelog.md](changelog.md); conventions → [`CONVENTIONS.md`](CONVENTIONS.md). Single source for planned work + open decisions (HD-XX).

---

## 0. How this backlog works

- **One row = one outcome.** New work gets `HD-<next>` and links its owning `docs/*.md`.
- **Priority (P):** 1 = highest (how hot), module = what domain it touches. Priority is per-row, modules group.
- **Executors:** `AI` · `AI + gate` (human checkpoint) · `AI + Human` (joint) · `Human` (blocks).
- **Lifecycle:** open → (decided) → done → changelog. Deferred → park section. **Decisions:** a decided item is written **once** to `changelog.md` (decision-log SSOT) and the full rationale is **removed** from `todo.md` — §1 shows only still-open decisions/purchases (compact pointer, no struck duplicate).
- **Conventions / onboarding:** consolidated rule index + 10-step service-onboarding checklist in [`CONVENTIONS.md`](CONVENTIONS.md).
- **Service stages:** service-onboarding rows (per-checklist tasks) carry **`Stage: N/10`** in the bold title = current Service-onboarding checklist step ([CONVENTIONS.md](CONVENTIONS.md) §5). `10/10` = deployed + verified; only then does a row close. Non-service tasks (network/fix/decision) carry no stage marker.

## 1. Human decisions & purchases — review first

### Decisions (blocking / waiting on a human call)

> **None open.** Resolved decisions are logged once in [`changelog.md`](changelog.md) (decision-log SSOT) and are **not** duplicated here.
> Recent: HD-22 (meteoblue weather), HD-24 (HA Dashboard), HD-25 (wake word), HD-29 (Hetzner boxes), HD-39 (no watchtower),
> HD-52 (OpenCloud OIDC), HD-122 (Matrix federation), HD-131 (storage architecture), HD-132 (Authentik-LDAP) — all in `changelog.md`.


### Purchases

| ID | D | Exec | Item |
|----|---|------|------|
| HD-30 | 1 | Human | *(buy)* **Sign up Infomaniak kSuite** — email, CalDAV, catch-all aliases; ~€3–5/mo; secrets → 1Password `Homelab-ansible`. · [subscription.md](docs/subscription.md) |

## 2. Active work — by module

### 2.1 Network & DNS — VLANs, firewall, DNS, VPN, router/switch

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-03 | 5 | AI + gate | 1 | **Network redo: VLAN segmentation** — flat 10.10.1.0/24 → VLANs 10/20/21/30/40/50/99 + inter-VLAN firewall + CAPsMAN. ✅ IaC committed (`39b9f02`); ⏳ **cutover Phase 1.5** — not live; deploy via Ansible in WSL; open switch bridge-VLAN membership + CAPsMAN SSID secrets; WG S2S VPS peer (IaC) — provision pubkeys + tunnel. · [network-vlans.md](docs/network-vlans.md) |
| HD-89 | 1 | AI | 3 | **Disable/move unused AP ethernet ports off Mgmt VLAN** — wired devices on AP ports currently get full Mgmt access (KOPS-046). · [network-vlans.md](docs/network-vlans.md) |
| HD-182 | 3 | AI | 2 | **Kids VLAN firewall (HD-179: implement at 1.5)** — bedtime 22:00–07:00 WAN block (RouterOS scheduler), forced filtered DNS for VLAN 40, Kids→Home drop; also close the audit's DNS-parity gaps while in the role (secondary-resolver forward rule; tertiary router resolver per network-dns.md). **Docs aligned ✅ 2026-08-21** (network-vlans status note + router-role placeholder now cites HD-179/182); remaining = the rules themselves. Closes audit J6/J7/S19 before Phase 1.5 verification. · [network-vlans.md](docs/network-vlans.md), [network-dns.md](docs/network-dns.md) |
| HD-198 | 2 | AI + gate | 3 | **Public-record SSOT migration (B2)** — ✅ **Decided (HD-204, 2026-08-21): incremental publication (each record added as its service lands).** `roles/cloudflare_dns/vars/main.yml` manages only `vps` + SMTP2Go CNAMEs; the service records (root/home, sso, foto, file, office, ai, git, ha, vpn, matrix, chat per services.md) exist only as comments → live zone and file are dual SSOTs. Extend the list incrementally — one record per service going live (gate: applies go LIVE on Cloudflare) — and render the human mirror as it grows. Closes audit B2/W7. · [services.md](docs/services.md), [network-dns.md](docs/network-dns.md) |

### 2.2 Storage, ZFS & UPS — NAS datasets, NFS, UPS/NUT

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-06 | 3 | AI | 1 | **NUT master on nas** — `usbhid-ups`, `upsd` :3493, `nut_exporter` :9199, `upssched-cmd` notify. ✅ IaC done; ⏳ live deploy on nas (Phase 2) + battery-pull test; feeds HD-07/08. · [hardware-ups.md](docs/hardware-ups.md) |
| HD-08 | 3 | AI | 2 | **UPS metrics + alerts → Prometheus/Grafana** — Critical/Warning/Info tiers. Depends HD-06/07. ✅ Monitoring IaC implemented; ⏳ live-verify `nut_ups_status` bitmask + metric names + Grafana alert-rule provisioning (blocks on HD-06). · [hardware-ups.md](docs/hardware-ups.md) |
| HD-09 | 1 | AI | 2 | **UPS web-UI firewall rule** — open 80/443 Home→Mgmt for `10.10.99.9` only; Modbus 502 retired. ✅ IaC done; ⏳ not deployed (Phase 1.5). · [hardware-ups.md](docs/hardware-ups.md) |
| HD-26 | 1 | AI | 3 | **Confirm UPS SNMP UDP (161/udp)** — confirmantional only (no consumer; NUT/USB is the monitor). Probe must run from a Mgmt-VLAN (99) host. · [hardware-ups.md](docs/hardware-ups.md) |
| HD-128 | 1 | AI | 1 | **Resolve NVMe pool device-path TODO** — ✅ IaC done (`storage_nvme_data_by_id`, fail-loud guard); ⏳ at first pool create, fill real `/dev/disk/by-id/nvme-…` (unblocks immich/opencloud db-backup). · [hardware-oldsrv.md](docs/hardware-oldsrv.md), [storage.md](docs/storage.md) |
| HD-132 | 3 | AI | 2 | **Authentik-as-LDAP for Samba self-service password** — ✅ IaC done (pull-model, `passdb backend=ldapsam`); ⏳ create LDAP provider + outpost, seed `authentik-ldap_bind`, firewall 3389→nas, live-verify a family drive mounts (Phase 2). · [deployment-compose.md](docs/deployment-compose.md), [storage.md](docs/storage.md) |


### 2.3 Platform & Deploy — Ansible, compose conventions, GitOps, Renovate, Forgejo Actions

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-134 | 3 | AI | 2 | **Pin all unpinned image tags + validator guard** — ✅ Done (`_version` pins in all.yml, Renovate-tracked; `validate-docker-services.py` fails on bare `latest` w/ `ALLOWED_LATEST`). ⏳ fluid/obscure services still documented `latest` — pin at first deploy when registry-verified. · [deployment-compose.md](docs/deployment-compose.md), [CONVENTIONS.md](CONVENTIONS.md) §3 |
| HD-159 | 2 | AI | 2 | **blackbox liveness — home↔VPS link tunnel-down as a first-class alert** — ✅ IaC done (`wg_icmp` scrape job probing `wg_s2s_vps.router_ip` + `wg-s2s-down` Grafana rule). ⏳ live-verify at Phase 1 (tunnel up) that the alert fires on a `wg down` test. · [observability.md](docs/observability.md) |
| HD-160 | 2 | AI | 2 | **services-internal sibling auth** — ✅ IaC done (immich-app→immich-ml key; OpenClaw→OpenCloud WebDAV app-password); ⏳ create `immich-ml-internal_api` + `openclaw-opencloud_api` 1P items; verify Immich v3 ML-auth env names; live-verify Phase 1/3. · [deployment-compose.md](docs/deployment-compose.md), [security.md](docs/security.md) |
| HD-200 | 2 | AI | 3 | **SSOT dedup bundle (W3/H2)** — derive router/switch VLAN views from `network_vlans` (kill the triple map); cross-link the two WG AllowedIPs lists or derive one from the other; drop `host_vars/oldsrv` `home_ip` dup (SSOT lookup exists); technitium state path `/opt`→`/srv/docker` or document the exception; prometheus TSDB named-volume note. Per iac-changes §2/§8/§11 D10. · [deployment-ansible.md](docs/deployment-ansible.md) |
| HD-193 | 1 | AI | 2 | **Bootstrap & guard hardening bundle (S3/R1/R2/R3)** — add `vps` to the site.yml pre-flight guard (it is provisioned + public); bind api/www-ssl/ssh to the Mgmt interface in `crs328_initial.rsc.j2` + `ap_initial.rsc.j2` (mirror rb4011 pattern); parameterize the rb4011 bootstrap DHCP DNS (1.1.1.1 literal → group_var). Closes audit S3/R1/R2/R3. · [network-ops.md](docs/network-ops.md), [deployment-ansible.md](docs/deployment-ansible.md) |
| HD-197 | 2 | AI | 3 | **Scripts hygiene pass (F2/F3/F5/F6/F10)** — validate_doc_templates: parse real group_vars (or relabel honestly) + canonical header + `Path(__file__)` root; render_rack_connections canonical `# Ansible managed` header; check_doc_ips/check_doc_map scan-scope widening (all root *.md minus prompt-*, changelog exempt for IPs); SMART snapshots → reports/ + README pointer; ansible `--syntax-check` in the gate (WSL/CI-gated). · prompt-hd197.md. Closes audit F2/F3/F5/F6/F10/F11(rest). · [scripts.md](scripts.md), [scripts/README.md](scripts/README.md) |
| HD-201 | 1 | AI | 3 | **Preseed placeholder assertions (B5/H2/H3)** — post_install asserts no `REPLACE_ME_*`/placeholder serials/pubkeys remain before reboot (preseeds + pi first-boot); repo grep gate for committed placeholders outside designated files; note the vps late_command wrong-script risk in deployment-preseed.md. Closes audit H2/H3/B5. · [deployment-preseed.md](docs/deployment-preseed.md) |

### 2.4 Services & Edge — Traefik, SSO, service catalog, Matrix, VPS edge

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-181 | 3 | AI + gate | 1 | **Single cert issuer (HD-178): `acme_issuer` flag + doc alignment** — ✅ **Decided (HD-204, 2026-08-21): oldsrv pulls its cert pair from the VPS via its own timer (second consumer, no Pi relay).** · prompt-hd181.md. — Parameterize the traefik template so ACME + certs-dumper run on the **VPS only** (oldsrv/Pi consume synced certs); align the four stale texts (`all.yml` letsencrypt comment, smart-home-failover.md, IaC/README.md, deployment-tasks Phase 3); add the S1 verify line to the services-vps checklist. **Docs aligned ✅ 2026-08-21** (all.yml, smart-home-failover, IaC/README, deployment-tasks Phase 3, services-traefik, services-vps, traefik template header); remaining = IaC mechanism + verify line. Closes audit J3/C1/W11. · [services-traefik.md](docs/services-traefik.md), [services-vps.md](docs/services-vps.md) |
| HD-183 | 3 | AI + gate | 1 | **Homepage → VPS (HD-180)** — move `homepage` from `group_vars/home_servers.yml` to `vps.yml`; add public root+`home` route on the VPS edge; replace the oldsrv docker.sock health-check with widget/probe-based reachability; fix `HOMEPAGE_ALLOWED_HOSTS` to include the `home.` alias. **Docs aligned ✅ 2026-08-21** (services.md + home_servers.yml comment mark the move); remaining = the move itself. Closes audit J10/A6/W9. · [services.md](docs/services.md), [interfaces.md](docs/interfaces.md) |
| HD-184 | 2 | AI | 1 | **Fix immich-app→immich-ml URL (cross-host)** — `IMMICH_MACHINE_LEARNING_URL` points at the container name `immich-ml`, but immich-ml runs on oldsrv (unresolvable from the VPS → ML dead on deploy). Derive the oldsrv target from the SSOT (`alloy_backend_host` pattern) **and publish immich-ml :3003 bound to oldsrv's Home IP** (currently overlay-only, unreachable cross-host). ML key auth already wired both sides (HD-160). · prompt-hd184.md. Closes audit J1/D1. · [services-ai.md](docs/services-ai.md), [deployment-compose.md](docs/deployment-compose.md) |
| HD-187 | 1 | AI | 2 | **Pi-hole conditional-forwarding points at the HA VIP** — `CONDITIONAL_FORWARDING_IP: "{{ ha_vip }}"` (the VIP serves HA/edge, not DNS) → local-name resolution via Pi-hole broken. Change to the Technitium primary IP (`dns_primary_ip`). One-line template fix + render check. Closes audit J4/D4. · [network-dns.md](docs/network-dns.md) |
| HD-141 | 4 | AI + gate | 1 | **(epic) Authentik OIDC provisioning — Blueprint + secret-egress glue** — declares OIDC providers/apps in a Blueprint; a glue copies generated client creds → 1Password `lookup()`. Sub-epics: A HD-142 · B HD-143 · C HD-144 · D HD-145 · E HD-146 · F HD-147. · [services-authentik.md](docs/services-authentik.md) |
| HD-142 | 4 | AI | 1 | **Authentik Blueprint `ks-oidc.yml` + `blueprints/` volume** — ✅ Blueprint written (OpenWebUI/Headscale/Matrix/OpenClaw/OpenCloud, Confidential + authz-code; creds not pre-seeded); volume mounted. ⏳ deploy-verify (HD-147): version-specific attrs. · [services-authentik.md](docs/services-authentik.md) |
| HD-143 | 3 | AI | 1 | **Secret-egress glue + `authentik-provision_api` token** — ✅ Glue written (harvests per-provider client_id/secret → 1Password, idempotent, fail-loud); wired into `deploy-service.yml`. ⏳ needs write token; NOT the opencloud-service_api job (HD-145). · [deployment-ansible.md](docs/deployment-ansible.md) |
| HD-144 | 4 | AI | 1 | **OpenCloud native-OIDC switch (HD-52)** — ✅ IaC done (OIDC env uncommented, Forward-Auth → `crowdsec-only@file`, CSP overlay). ⏳ deploy-verify (HD-149): CSP + desktop/mobile OAuth. Depends HD-142+143. · [deployment-compose.md](docs/deployment-compose.md), [services.md](docs/services.md) |
| HD-145 | 3 | AI | 2 | **`sync-authentik-users.sh` rework — Authentik-driven OpenCloud lifecycle** — ✅ IaC done (least-priv `opencloud-service_api`, best-effort ensure). ⚠ JIT-vs-preseed deploy-verify (HD-149). · [storage.md](docs/storage.md), [deployment-secrets.md](docs/deployment-secrets.md) |
| HD-146 | 2 | AI | 2 | **Wire `vps.yml` deploy order + IaC comments** — ✅ done (authentik precedes OIDC consumers — constraint comment; stale comments → Blueprint+glue). · [deployment-ansible.md](docs/deployment-ansible.md) |
| HD-147 | 2 | AI + gate | 1 | **Live deploy-verify** — run VPS playbook; confirm Blueprint + glue seeds all 8 OIDC items; OIDC login verify for ai/vpn/matrix/claw/cloud/foto; Forgejo register (HD-148); re-render inventory. · [services-vps.md](docs/services-vps.md) |
| HD-148 | 4 | AI + gate | 1 | **Extend OIDC Blueprint → Immich + Forgejo + Metabase** — ✅ IaC done (immich switched native; forgejo kept Forward-Auth w/ OIDC-source pending; Metabase reverted — OSS has no OIDC). ⏳ deploy-verify (HD-149). · [services-authentik.md](docs/services-authentik.md) |
| HD-149 | 2 | AI | 1 | **Verify Authentik `ks-oidc.yml` blueprint attrs vs source** — ✅ Verified (flow slugs, signing_key, sub_mode, app binding via `!KeyOf`; scripts/validate_blueprints.py added). ⏳ deploy-gated (Phase 1, HD-40A): live-apply on 2026.5.6 + glue harvest. · [services-authentik.md](docs/services-authentik.md) |
| HD-122 | 2 | AI | 2 | **Matrix federation default (open + hardening)** — ✅ decided + IaC (profile/auth + room-dir hardening; trusted_servers = key-notary not permit-list). ⏳ live-verify profile auth at first deploy (HD-46). · [services-matrix.md](docs/services-matrix.md), [security.md](docs/security.md) |
| HD-40A | 3 | AI + Human | 1 | *(Phase 1)* **Provision VPS + public Traefik edge** — ✅ Provisioned (IP `159.195.111.66`, specs); edge IaC enabled (`b070f7d`). ⏳ remaining deploy-gated: run `vps.yml`, wildcard cert (DNS-01), `sso` record, CIFS mount; WG S2S home↔VPS. · [services-vps.md](docs/services-vps.md), [deployment-tasks.md](deployment-tasks.md) |
| HD-40B | 3 | AI | 1 | *(Phase 1)* **Migrate public-facing services to VPS** — Authentik/OpenCloud/Forgejo/Grafana + AI stack; DBs stay LAN over WG; storage per HD-135. Folds into `enabled:` split. · [services-vps.md](docs/services-vps.md) |
| HD-135 | 4 | AI + gate | 2 | **VPS/oldsrv service split (+ storage/backup transport)** — ✅ IaC matrices applied (`b070f7d`/`d805f6d`); WG S2S role complete (VPS `77833f1`/router `85ba6dc`). ⏳ remaining live: provision both peer pubkeys, live-Box CIFS mount, cross-host wiring, `foto`/`file`/`git`/`ai` round-trip over tunnel. · [services-vps.md](docs/services-vps.md), [storage.md](docs/storage.md), [backup.md](docs/backup.md) |
| HD-43 | 3 | AI | 3 | **Deploy/verify Media *arr stack** — Stage 4/10; templates in `home_servers.yml` (jellyfin, *arr, qbit+gluetun, …); deploys oldsrv bulk/media NFS. · [services.md](docs/services.md) |
| HD-44 | 2 | AI | 3 | **Deploy/verify new ops services** — Stage 3/10; `dozzle` + `traefik-ha` VIP edge on the Pi (added but not verified). · [services.md](docs/services.md) |
| HD-46 | 4 | AI | 3 | **Implement Matrix IaC (native-only)** — Stage 4/10. ✅ IaC done + committed (`62e0045`; Tuwunel + Element Web, Authentik OIDC, closed registration, RocksDB). ⏳ hosts unprovisioned; needs HD-47 records + OIDC provider/redirect. No bridges in Phase 1 (HD-48). · [services-matrix.md](docs/services-matrix.md) |
| HD-47 | 2 | AI | 3 | **Matrix public records + Federation** — publish `matrix`/`chat` (Cloudflare DNS-only) + `_matrix` well-known/SRV delegation; WAN 443 (8448 optional); no Forward-Auth on `/_matrix/*`. · [services-traefik.md](docs/services-traefik.md), [network-dns.md](docs/network-dns.md) |
| HD-58 | 3 | AI | 3 | **Stirling PDF service** — Stage 4/10; ✅ IaC done (pinned `stirling_pdf_version`, OCR `slv`, Forward-Auth, internal-only). ⏳ re-render `services-inventory-generated.md`; live-verify OCR + Forward-Auth chain. · [services.md](docs/services.md) |
| HD-112 | 4 | AI | 2 | **Zipline + OpenCloud file share** — ⚠ TENSION: row assumes S3ng bucket, but HD-131 = WebDAV/filesystem — re-examine Zipline writes vs WebDAV before build. Stage 1/10; OIDC SSO. · [services.md](docs/services.md), [storage.md](docs/storage.md) |
| HD-113 | 2 | AI | 3 | **PairDrop P2P file share** — Stage 4/10; ✅ IaC done (pinned `pairdrop_version`, Forward-Auth, internal-only). ⏳ re-render inventory; live-verify WebRTC/signaling through Traefik (may need STUN/TURN). · [services.md](docs/services.md) |
| HD-166 | 2 | AI | 1 | **Deploy ONLYOFFICE Docs Server (OpenCloud browser editor, WOPI)** — Stage 6/10; no family logins (background worker, JWT shared w/ OpenCloud). ✅ IaC done (verified vs docs.opencloud.eu; pinned + opencloud collaboration + CSP). ⏳ create `opencloud-collab_password`; VPS Phase 1; live-verify editor iframe. · [services-office.md](docs/services-office.md), [services.md](docs/services.md) |

### 2.6 Smart Home — HA primary/standby, Homematic, voice, devices

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-04 | 5 | AI + gate | 1 | **Pi redo: HAOS → Debian + HA Container + Technitium secondary** — in-use migration; approved direction, not yet applied. ⏳ Homematic-local deferred: keep HmIP-HAP cloud mode, no HmIP-RFUSB buy yet (HD-13 parked). · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-72 | 3 | AI | 1 | **HA primary privileged → targeted caps** — replace `privileged: true` + `network_mode: host` with targeted `devices:` + `cap_add:` to drop root/cgroup-escape + keepalived/VRRP control on the smart-home controller (KOPS-014). · source qwen. · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-185 | 3 | AI + gate | 1 | **Fix Pi first-deploy ordering (docker_services vs home_assistant)** — ✅ **Decided (HD-204, 2026-08-21): option A: render-first reorder for the Pi (supersedes the KOPS-063/HD-117 order on this host).** KOPS-063 order auto-creates `config/`, `secrets.yaml`, `keepalived.conf` as empty **directories** at first `compose up`; the HA role's `copy → keepalived.conf` then fails and HA runs default config. Implement option A: run `home_assistant` before `docker_services` on the Pi; note the supersession in the role/playbook comments (re-read the KOPS-063 rationale for the record). · prompt-hd185.md. Closes audit J2/D2. · [smart-home-failover.md](docs/smart-home-failover.md), [deployment-ansible.md](docs/deployment-ansible.md) |

| HD-14 | 2 | AI | 2 | **Export HA entity list** — enable HA Prometheus exporter; needed for HA Dashboard `lovelace` + Grafana. Wait for observability. · [smart-home.md](docs/smart-home.md) |
| HD-15 | 1 | AI | 2 | **Confirm HACS custom-component versions/repos** — `motion`, `ai_task`, Weather-2000, OneDrive, go2rtc via SSH / config git repo (REST API can't expose). · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-17 | 3 | AI | 2 | **Single failover button + `ha-failover.sh`** — ✅ IaC done + committed (`ha-failover.sh` fwd/reverse, keepalived failover configs, trigger API + systemd, Homepage buttons). ⏳ not deployed; needs `ha-failover_api` + HmIP-RFUSB moved at runbook. · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-18 | 2 | Human | 2 | **Once: test HmIP-RFUSB pairing transfer** + entity reconstruction across stick move. Hands-on; **blocked** until the HmIP-RFUSB is bought (HD-13 parked). · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-124 | 3 | AI | 2 | **Keepalived hardening** — ✅ IaC done + constraint documented (pinned `keepalived_version: 2.3.4`; `auth_type PASS` is the protocol MAXIMUM — accepted w/ Home-VLAN isolation). ⏳ deploy-gated (hosts unprovisioned). · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-20 | 1 | Human | 3 | **Confirm full Supervisor add-on list** — `/api/hassio/addons` returned 401 (non-admin token); needs admin/SSH on HAOS host. · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-21 | 1 | AI + Human | 3 | **Confirm ESPHome / Guition ESP32-S3 status** — `esphome` not loaded; agent checks network/repo, owner knows if the device was ever added. · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-23 | 1 | AI | 3 | **Confirm HmIP-SWO-B channels** — no rain / wind-direction on this sensor; verification only. · [smart-home.md](docs/smart-home.md) |
| HD-27 | 4 | AI + Human | 3 | **Voice pipeline build-out** — Whisper → Ollama → Piper containers, flash ESP32-S3 (ESPHome + microWakeWord), HA Assist on phones; GPU + physical flashing. · [smart-home-voice.md](docs/smart-home-voice.md) |

### 2.7 AI & Office — LLM stack, Open WebUI, office MCP, vector DB

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-100 | 4 | AI | 2 | **AI stack: LiteLLM spine** — Stage 4/10; ✅ IaC done (compose on services-internal+llm-backend; config model_list = Ollama/OpenRouter/Cohere; SQLite for keys/spend). ⏳ create `litellm_master_key`/`openrouter_api`/`cohere_api`; MUST pin `litellm_version`; live-verify completion + embed. · [services-ai.md](docs/services-ai.md) |
| HD-101 | 4 | AI | 2 | **AI stack: Open Web UI** — Stage 4/10; ✅ IaC done (compose, `ai.kogler.si` route, Authentik OIDC + crowdsec, LiteLLM backend). ⏳ create `openwebui_secret` + `openwebui_api` (OIDC, redirect `ai`); live-verify OIDC + LiteLLM completion + RAG. · [services-ai.md](docs/services-ai.md) |
| HD-102 | 3 | AI | 2 | **AI stack: PGVector DB + backup** — Stage 4/10; ✅ IaC done (compose + DB04 backup block). ⏳ create `pgvector_db`; live-verify extension init + db-backup DB04. · [services-ai.md](docs/services-ai.md) |
| HD-103 | 3 | AI | 2 | **AI stack: Docling OCR** — Stage 4/10; ✅ IaC done (CPU-only compose, v1 API, backend-only). ⏳ first start downloads HF models; live-verify Slovenian scan conversion. · [services-ai.md](docs/services-ai.md) |
| HD-104 | 4 | AI | 2 | **AI stack: OpenClaw agent + integrations** — Stage 4/10; ✅ IaC done (compose, gateway; wire to LiteLLM + OpenCloud WebDAV at deploy). ⏳ run `openclaw onboard` → `openclaw.json`; live-verify round-trip. · [services-ai.md](docs/services-ai.md) |
| HD-105 | 2 | AI | 2 | **AI stack: secrets + wiring** — Stage 1/10; ⏳ **pre-deploy gate:** create the 7 1Password items + Authentik OIDC providers per [deployment-ai-stack-secrets.md](docs/deployment-ai-stack-secrets.md) — blocks HD-100→104. · [deployment-secrets.md](docs/deployment-secrets.md) |
| HD-111 | 4 | AI | 2 | **Office MCP via Open WebUI** — Stage 1/10; `ppt-mcp` first then Word/Excel; register MCP servers in Open WebUI; retires AnythingLLM + LocPilot (HD-107 path). · [services-office.md](docs/services-office.md), [services-ai.md](docs/services-ai.md) |
| HD-28 | 3 | AI | 3 | **Office AI stack** — Ollama models, n8n, ONLYOFFICE desktop + MS Office via Open WebUI MCP; depends oldsrv GPU; AnythingLLM + LocPilot superseded. · [services-office.md](docs/services-office.md) |

### 2.8 Security & Secrets — secrets hygiene, privilege, firewall, preseed hardening

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-59 | 2 | AI | 3 | **Internal service auth on flat Docker networks** — ✅ IaC applied (Ollama→`llm-backend` isolation; Kopia `--htpasswd-file` [no `--password`]; Prometheus bcrypt; Signal done). ⏳ create `kopia-server-internal_api` + `prometheus-internal_api`; wire consumers. · [deployment-compose.md](docs/deployment-compose.md), KOPS-001/016/002 |
| HD-154 | 3 | AI + gate | 1 | **Harden the public VPS host (SSH/container/firewall)** — ✅ `vps-hardening` role enforces checklist (SSH 3/no/no, fail2ban, nftables default-deny `:443`+`:51820`, Docker daemon). ⏳ deploy-gated Phase 1 (HD-40A): verify `fail2ban-client status sshd` + `nft list ruleset` + `sshd -T` + `docker info`. · [security.md](docs/security.md) §8, [services-vps.md](docs/services-vps.md) |
| HD-155 | 3 | AI + gate | 1 | **VPS→home tunnel blast radius (least-access ACL + fail-loud WG gate)** — ✅ IaC done (AllowedIPs scoped both sides, RouterOS forward ACL, fail-loud pubkey gate). ⏳ deploy-gated Phase 1/1.5 (HD-03): provision peer pubkeys + live-verify scoped access / DROP of non-scoped target. · [network-vpn.md](docs/network-vpn.md), [security.md](docs/security.md) §9 |
| HD-186 | 3 | AI + gate | 1 | **Close the published-port firewall bypass (S1)** — ✅ **Decided (HD-204, 2026-08-21): option A: remove the publish; option B (DOCKER-USER chain) documented as future hardening.** nftables forward `oifname "docker*" accept` lets DNAT'd ports skip the input default-deny; authentik publishes LDAP `3389` on all interfaces of the public VPS. Remove the authentik `3389` publish (Samba reaches the outpost over WG); document option B in `docs/security.md` §8; run the S1 verification plan after. · prompt-hd186.md. Closes audit S1. · [security.md](docs/security.md) §5, [services-vps.md](docs/services-vps.md) |
| HD-188 | 1 | AI | 2 | **Cockpit routes: derive IPs + add edge middleware** — `roles/cockpit/templates/cockpit-routes.yml.j2` hardcodes nas/oldsrv Home-IP literals (SSOT convention violation) and carries zero middleware (§1 law: at least `crowdsec-only@file`). Derive backends from `network_static_hosts`, add the middleware. Closes audit J9/D6/S17(b). · [services-traefik.md](docs/services-traefik.md) |
| HD-190 | 2 | AI | 2 | **Overlay header-trust hardening (S15/S16)** — (a) Authentik `AUTHENTIK_TRUSTED_PROXIES` trusts the whole traefik-public /16 (HD-81 anti-pattern) → pin the edge container IP(s) via group_var; (b) Grafana auth-proxy trusts raw `X-authentik-email` + `AUTO_SIGN_UP: true` → signed-header validation + signup off. · prompt-hd190.md. Closes audit S15/S16. · [security.md](docs/security.md) §5 |
| HD-194 | 1 | AI + gate | 3 | **`sso` route edge middleware (S17a)** — ✅ **Decided (HD-204, 2026-08-21): enforce `crowdsec-only@file`, falling back to a documented exception + compensating control only if Authentik outpost/OIDC callbacks break.** The public login page carries zero edge middleware (law exception, undocumented). Add `crowdsec-only@file` and verify Authentik outpost/OIDC callbacks still pass; only if they break, document the exception + compensating control (fail2ban http-auth jail) in security.md §1. · Closes audit S17(a). · [security.md](docs/security.md) §1, [services-traefik.md](docs/services-traefik.md) |
| HD-202 | 2 | AI + gate | 3 | **Container-hardening policy (S22/S21)** — ✅ **Decided (HD-204, 2026-08-21): roll out into templates (GPU/VPN/gluetun exempt); validator allowlist only as backstop.** Implement `cap_drop: ALL`/`read_only` per deployment-compose conventions; document the one intentional `default('', true)` (signal captcha) or replace it. · Closes audit S21/S22. · [deployment-compose.md](docs/deployment-compose.md) §Container Security |

### 2.9 Backup & DR — ZFS snapshots, Kopia, off-site, restore drills

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-49 | 3 | AI | 3 | **Backup Matrix identity + media** — signing/identity keys (critical — reissue breaks rooms), homeserver DB (db-backup/Kopia), media store; add to backup policy. · [services-matrix.md](docs/services-matrix.md), [backup.md](docs/backup.md) |
| HD-34 | 2 | AI + Human | 4 | **Assess Kopia Web GUI vs CLI** at the first restore drill (agent assesses during the human-run yearly drill). · [backup.md](docs/backup.md) |
| HD-191 | 2 | AI | 2 | **oldsrv Kopia agent (S18/J5)** — ✅ **Decided (HD-204, 2026-08-21): containerized agent (parity with kopia-server).** backup.md says Kopia runs on VPS + oldsrv, but no agent exists in `group_vars/home_servers.yml` → oldsrv-local state (dumps, service state, thumbs, `/opt/*` configs) has no off-site path. Add the agent as a container (kopia-server API over WG, `kopia-server-internal_api`) + sources/policy per backup.md; align backup.md in the same change. · prompt-hd191.md. Closes audit S18/J5/W12. · [backup.md](docs/backup.md) |

### 2.10 Docs & Family — family guides, docs, manual

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-32 | 2 | AI | 4 | **Write family guides `docs/manual/*`** — 10 Slovenian files, `status: wip`, not yet written; content well-specified; deferred until services live. · [manual/README.md](docs/manual/README.md) |
| HD-33 | 1 | AI | 4 | **Export live router config `rb4011_live.rsc`** — one-time RouterOS export; docs-only. · [network-ops.md](docs/network-ops.md) |
| HD-195 | 2 | AI | 2 | **deployment-tasks phase sweep** — Phase 3 service list (still pre-HD-135), Phase 4 Pi services+order, Phase 6 TileBoard, Phase 7 AnythingLLM/LocPilot, Phase 9 closed HDs (35/39), Host→Playbook table chains, Phase 2 chain missing storage role; 2025→2026 date typos. · prompt-hd195.md. Closes audit I2/A3/A4/A7 + tracking §2. · [deployment-tasks.md](deployment-tasks.md) |
| HD-196 | 2 | AI | 3 | **Stale-docs sweep (VPS era)** — backup.md DB/TSDB locations + Kopia sources; observability.md Loki-on-oldsrv line + done-TODOs; services-matrix.md oldsrv placement; hardware-nas TODO box; storage.md stub section + 3879 typo; security.md §2 stale bits; index.md dispatch rows + ★ legend; network-dns `bck` ghost + Pi-hole merge; legacy superseded blocks → ≤5 lines; interfaces.md pipeline commit/push claim (D11); date typos in 5 docs. · prompt-hd196.md. Closes audit G1–G4, §1 docs-changes. · [docs-changes.md](docs-changes.md) |
| HD-199 | 2 | AI | 4 | **Docs structure pass** — split `deployment-compose.md` (OIDC provisioning → `deployment-oidc.md`); single public-record mirror (after HD-198); services-office/ai boundary trim; standardize deploy-gate phrasing. Per docs-changes §2/§4 — do after HD-195/196. · [docs-changes.md](docs-changes.md) |
| HD-203 | 2 | AI | 4 | **Fold round-2 audit reports into canonical docs, then delete them (A3 lifecycle)** — **gate:** all HD-181…202 closed (or explicitly rejected with a changelog line). Fold still-durable content first: conventions proposals B2–B5 (apply-or-reject), S1 verify plan → services-vps checklist (via HD-186), architecture digest/W-items → owning docs, verified-good summaries → changelog note; record every rejected finding; then delete the 8 root reports (`docs-vs-iac`, `docs-changes`, `iac-changes`, `conventions-sugestions`, `tracking-sugestions`, `architecture`, `security`, `scripts` .md) + any leftover `prompt-hd*.md` in the same change. ⚠ root `security.md` name-collides with canonical `docs/security.md` — resolve by fold+delete, never rename (HD-153 precedent). · CONVENTIONS §4 (Audit reports) |


### 2.11 Finance & Subscriptions — budget apps, banks, billing

| ID | D | Exec | P | Item |
|----|---|------|---|------|
| HD-57 | 3 | AI + Human | 3 | **Finance pre-deploy prep (Actual Budget / Enable Banking)** — Stage 1/10; verify EB redirect (Traefik cert), Wise/IBKR tokens; decisions (UniCredit, actual-version). · [services-finance.md](docs/services-finance.md) |
| HD-133 | 3 | AI | 3 | **Subscription renewal reminders (Homepage + calendar + n8n)** — SSOT = `subscriptions.yml`; drives Homepage Subscriptions/calendar + n8n renewal notify; `subscription.md` derived table. · [subscription.md](docs/subscription.md), [automation-renewals.md](docs/automation-renewals.md) |

## 3. Park — deferred / optional / Phase 2

> Items here are not actively worked. They stay visible for planning.

| ID | D | Exec | Item |
|----|---|------|------|
| HD-36 | 3 | AI | **Internal AAAA records** — deferred/optional; needs stable per-host global addressing + IPv6 firewall mirroring. · [network-dns.md](docs/network-dns.md) |
| HD-37 | 3 | AI | **Long-term metric retention** — remote-write/downsampling (Thanos/VictoriaMetrics) only if ever needed. · [observability.md](docs/observability.md) |
| HD-38 | 2 | AI | **Prometheus Alertmanager** — only if Grafana-outage resilience demanded; Grafana Alerting covers Phase 1. · [observability.md](docs/observability.md) |
| HD-41 | 4 | AI | *(Phase 2)* **Proxmox role + VM lab** — bridges, storage, VMs; implementation order step 10. · [deployment-ansible.md](docs/deployment-ansible.md) |
| HD-42 | 3 | Human | *(Phase 2)* **Phase-2 hardware build** — Ryzen 9, open-frame chassis; only if Phase 1 insufficient; physical. · [hardware-phase2.md](docs/hardware-phase2.md) |
| HD-13 | 3 | Human | **Homematic full-local (HmIP-RFUSB + RaspberryMatic)** — ⏳ **Parked (2026-08-18, decision A):** keeping the **HmIP-HAP in cloud mode** for now; **no HmIP-RFUSB purchase yet**. Full-local Homematic (`homematic` XML-RPC 2001/2010) resumes only after the stick/buy. Until then HD-04's Pi redo proceeds with **cloud HmIP-HAP** (no USB placeholder step, no local pairing); HD-18 (stick-move test) is blocked on this. · [smart-home.md](docs/smart-home.md) |
| HD-45 | 3 | AI | *(Phase 2)* **Re-evaluate Homelable (topology/rack visualizer)** — Pouzor/homelable, MIT, young project; network + rack canvas + nmap scan + live health + MCP; potential successor to `Rack.canvas` visual/Homepage reachability widget. Keep deferred until services are live; re-check maturity. Noted in `observability.md` + `network-rack.md`. · [observability.md](docs/observability.md) |
| HD-48 | 3 | AI + Human | **Requested-only bridges (deferred, Phase 2 best-effort)** — WhatsApp/Messenger/Signal bridges are **out of Phase 1 scope** (every bridge risks a real external account). Revisit **only if family asks**, and then only against **dedicated** numbers, accepting re-pairing/ban. · [services-matrix.md](docs/services-matrix.md) |
| HD-129 | 2 | AI | **Router DHCP → use internal resolver** — bootstrap assigns 1.1.1.1 not the internal resolver (KOPS-028); same outcome as HD-03 DNS setup, so fold in at live DNS. · [network-vlans.md](docs/network-vlans.md) |
| HD-130 | 2 | AI | **Low-severity opportunistic fixes** — Homepage docker.sock ro visibility, Seerr SQLite failure domain, pi edge cert expiry (KOPS-058/059/061). ✅ **Applied (2026-08-18):** KOPS-058 already `:ro` on the docker.sock mount (verified); KOPS-059 Seerr config+`seerr.db` added to `backup.md` Service-state scope + documented in the compose; KOPS-061 Grafana SSL-cert-expiry alert rule added (warning tier, fires <14 days out) per the KOPS-061 recommended fix. Live dashboard/cert check still at deploy. Do remaining opportunistically during service deployment. · [services.md](docs/services.md) |

## 3b. Deploy path — Ansible-only (HD-150, supersedes HD-02 Doco-CD)

> **Doco-CD is DROPPED (HD-150).** Deployment + upgrades use **Ansible only** for BOTH VPS and
> oldsrv. The single upgrade path: **Renovate** opens Forgejo PRs → the **Forgejo Actions deploy
> button** (`workflow_dispatch`) runs Ansible (idempotent `docker_compose_v2` re-render/applies the
> merged image-tag) → post-deploy renders Homepage config + inventory. Homepage is a dashboard link to
> the Dependency Dashboard + deploy button (no deploy role). Old HD-02 activation notes removed.

## 3c. Deploy-gated verification — lives in `deployment-tasks.md`

> **Per-phase `Deploy-gated verification` checklists are the authoritative home** for every `⏳` (IaC-done, not-live-verified) row, ordered by the deployment phase (1/1.5/2/3/4/6/8) where each live-verify runs.
> See [`deployment-tasks.md`](deployment-tasks.md) → each phase's `Deploy-gated verification` block. Row detail stays in the owning doc. This section is now a pointer, not a second SSOT.
## 4. Status & dependency notes

- **HD-50 done** → blocks all `docker_services` deployments; **HD-16 done** (Authentik + Forward-Auth middleware) unblocks Forward-Auth services (HD-43/44/46).
- **HD-03 → HD-04** (network redo feeds Pi redo). **HD-04 → HD-13** was the Homematic-full-local path, but **HD-13 is parked (2026-08-18)** until an HmIP-RFUSB is bought — HmIP-HAP stays in cloud mode; HD-04's Pi redo proceeds without local-Homematic.
- **HD-06/07 done** → feeds HD-08. **HD-29 → HD-31** done (off-site = **two 1 TB Hetzner Storage Boxes**: live next-DC CIFS + backup far-DC Kopia-over-SSH/SFTP; iDrive dropped — HD-131).
- **HD-40A/40B/135 = deployment Phase 1 (VPS edge)** — the VPS is the independent public tier, **needed before Phase 2** (network redo is Phase 1.5); see `deployment-tasks.md`. **HD-135** (service split) blocks on **HD-03 WG S2S peer** + live-box CIFS mount wired.
- 'Implemented, not deployed' rows (HD-03/06/17/46/60/61/62/63/64/94 …) stay open with a ⏳ marker until a live deploy happens — closing requires a deploy/verify pass, not just IaC.

## 5. Conventions quick-reference

> Full, consolidated rule set: [`CONVENTIONS.md`](CONVENTIONS.md) — this section is only the index.

| Area | Rule | Owning doc |
|------|------|-----------|
| Hostnames | single `kogler.si` namespace, flat subdomains | `docs/index.md` Conventions
| IPs | `docs/network-addresses-generated.md` is the SSOT, generated, never hand-edit | `scripts/check_doc_ips.py`
| Secrets | 1Password `Homelab-ansible` vault, `<service>_<type>` naming | `docs/deployment-secrets.md`
| Compose | conventions & port binding policy | `docs/deployment-compose.md`
| Ansible | roles/templates/conventions | `docs/deployment-ansible.md`, `IaC/README.md`
| Service catalog | `group_vars/home_servers.yml` + `docs/services.md` | `docs/services.md`
| Validation | `bash scripts/validate-all.sh` before commit | `scripts/`

## 7. Service onboarding

> Uniform 10-step path for adding a service (exposure/auth → secrets → compose → registry → edge →
> state/backup → observability → validation → deploy gate → docs). Canonical copy:
> **`CONVENTIONS.md` §5 — Service-onboarding checklist**. Reproduced there; new services must clear all 10 steps.

