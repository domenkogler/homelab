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

**Status: 76 open · 19 done** · **Total: 95**

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
| HD-07 | 2 | AI | done | **NUT clients on `oldsrv` + `pi`** — upsmon slave, per-host shutdown delay 60/0/0. ✅ **IaC done:** host_vars wired (oldsrv 60 / pi 0), client upsmon + secret-free upssched-cmd deployed on clients, **fixed deferred-shutdown bug** (`shutdown -h +60` = minutes not seconds → now owned by the upssched ONBATT timer `AT onbatt-delay * EXECUTE powerdown`; LOWBATT stays immediate). ⏳ Not deployed (hosts unprovisioned). · [hardware-ups.md](docs/hardware-ups.md) |
| HD-16 | 3 | AI | done | **Implement Authentik compose template + Traefik Forward-Auth middleware** — server+worker+postgres+redis compose (115 lines), `authentik-forward-auth@file` middleware (42 lines), `subdomain: sso` entry. All implemented in `db51854`. · [services-authentik.md](docs/services-authentik.md), [services-traefik.md](docs/services-traefik.md) |
| HD-50 | 3 | AI | done | **Implement `docker_services` Ansible role** — ✅ **Done (`eadf9d4`).** Role creates external Docker networks, copies templates, renders Jinja2 with 1Password lookups, runs `docker compose up -d`. Added: systemd auto-start per service (`docker-compose@.service` template unit + `systemctl enable`), post-deploy Homepage reload + `inventory.md` render. Fixed pre-existing path bugs (templates at playbook level, not in role). All 43 templates validated. · [deployment-ansible.md](docs/deployment-ansible.md) |
| HD-53 | 2 | AI + Human | open | *(decision)* **MikroTik SNMP community** — Alloy collector assumes v2c `public` (monitoring role); decide a dedicated read-only community + mgmt-VLAN ACL vs RouterOS default, then enable `/snmp` on RB4011/CRS328 (device-side — blocks HD-03 deploy). · [observability.md](docs/observability.md) |
| HD-56 | 3 | AI + Human | done | *(decision)* **Host network config-manager: systemd-networkd vs netplan** — ✅ **Decided: systemd-networkd.** Rationale: native Debian server tooling, no Python dependency (netplan pulls python3+libnetplan), Ansible `community.general.systemd_network` module is mature, consistent with existing systemd timer usage (sanoid/syncoid/db-backup). Netplan rejected — Ubuntu desktop default, extra translation layer on Debian server. Blocker cleared for network role's static-IP/VLAN-trunk provisioning. · [deployment-ansible.md](docs/deployment-ansible.md) |
| HD-92 | 2 | AI + Human | done | *(decision)* **oldsrv stays bare-metal Debian — no local Proxmox / no GPU passthrough on the single Phase-1 box** — ✅ **Decided (2025-08-16):** keep Phase 1 as bare-metal Debian + Docker on oldsrv. Rationale: one shared dGPU (RX 7600) is needed by **both** the family desktop and the AI stack (Ollama/immich-ML) — VM/GPU-passthrough is mutually exclusive and would force choosing one; a single host gains no HA/migration from VMs; hypervisor + ~40 containers is RAM-heavy and fights the "works without Domen" priority. **Proxmox deferred to HD-41/HD-42** (Phase 2) once a real 2nd local node exists. If desktop isolation ever becomes a hard requirement → dedicated 2nd local desktop box, **not** a VM on oldsrv. · [hardware-oldsrv.md](docs/hardware-oldsrv.md), [IaC/README.md](IaC/README.md) |
| HD-93 | 3 | AI + Human | done | *(decision)* **Buy Contabo VPS before go-live; public edge on VPS from day one** — ✅ **Decided (2025-08-16):** purchase the VPS pre-go-live and fold **HD-40A/HD-40B forward into Phase 1** — public Traefik + CrowdSec + Authentik and public apps (Forgejo, Grafana, OpenCloud web) terminate TLS on the VPS (WG S2S → oldsrv backends); oldsrv becomes an internal/LAN box (leaner, less exposed → mitigates the audit's SPOF critique). Does **not** change HD-92 — the VPS is remote/GPU-less, hosts no desktop or AI, and is not a substitute for a 2nd local node. · [services-vps.md](docs/services-vps.md) |

| HD-60 | 2 | AI | open | **crowdsec-only middleware chain** — add `crowdsec-only@file` to `middlewares.yml.j2`; apply to every self-auth'd route (ha, jellyfin, seerr, matrix, chat, ha-standby). ROI · source qwen. · [services-traefik.md](docs/services-traefik.md) |
| HD-61 | 1 | AI | open | **Pin image tags — Traefik first** — `traefik_version: latest` today in group_vars; pin to a semver + Renovate follow-up (also dedupe the other `latest`/`:rocm` mutable tags). ROI · source qwen. · [deployment-compose.md](docs/deployment-compose.md) |
| HD-62 | 2 | AI | open | **Remove / unbind host ports** — signal `8080:8080`; prometheus `9090:9090`; technitium `53:53`; sunshine `47989-48010` → bind loopback or a specific VLAN IP, or drop (prefer the Docker overlay network). ROI · source qwen. · [deployment-compose.md](docs/deployment-compose.md) |
| HD-63 | 2 | AI | open | **Uncomment immich DB backup + opencloud tar** — host default `immich-postgres` (the stale `db-backup` comment says `immich-db`; the real service is `immich-postgres`). ROI · source qwen. · [backup.md](docs/backup.md) |
| HD-64 | 1 | AI | open | **Fix Loki schema `from:` date** — `2026-01-01` (future) → `2025-01-01` / current; Loki silently drops all logs until the schema activates. ROI · source qwen. · [observability.md](docs/observability.md) |

| HD-72 | 3 | AI | open | **HA primary privileged → targeted caps** — replace `privileged: true` + `network_mode: host` with targeted `devices:` + `cap_add:` to drop root/cgroup-escape + keepalived/VRRP control on the smart-home controller (KOPS-014). · source qwen. · [smart-home-failover.md](docs/smart-home-failover.md) |

## Priority 2

| ID | D | Exec | Status | Item |
|----|---|------|--------|------|
| HD-08 | 3 | AI | open | **Wire UPS metrics + alerts into Prometheus/Grafana** — Critical battery/runtime, Warning on-battery, Info transitions. Depends on HD-06/07. ✅ **Monitoring IaC implemented** (nut_* alert rules + UPS dashboard — commits `aaa3f7c`/`8c50d7f`). ⚠ **Deploy-time verification:** confirm DRuggeri/nut_exporter `nut_ups_status` bitmask + metric names, and that Grafana alert-rule provisioning loads (live check). · [hardware-ups.md](docs/hardware-ups.md) |
| HD-94 | 2 | AI | open | **Centralize shared-data owner as `storage_uid`/`storage_gid` (KOPS-060)** — replace the hardcoded `PUID/PGID: 1000:1000` literals in the *arr / opencloud / immich compose templates with the group_vars `storage_uid`/`storage_gid` (the neutral owner from HD-51); define the shared-owner uid/gid once (e.g. `1005`) in the storage role group_vars and use it on both nas and oldsrv. Verify NFS ownership + container perms after the change. · [deployment-compose.md](docs/deployment-compose.md), [hardware-nas.md](docs/hardware-nas.md) |
| HD-100 | 4 | AI | open | **AI stack: LiteLLM spine** — LLM gateway/router (local Ollama + OpenRouter gen + Cohere embed); single endpoint; only component holding upstream keys; `config.yaml.j2`; `litellm_master_key` auth. No host port binds. · [ai-stack.md](docs/ai-stack.md) |
| HD-101 | 4 | AI | open | **AI stack: Open Web UI** — compose + `ai` route (**public**, Authentik OIDC + `crowdsec-only`); RAG (Cohere embed-v4, Docling, PGVector); pin secrets. · [ai-stack.md](docs/ai-stack.md), [services-traefik.md](docs/services-traefik.md) |
| HD-102 | 3 | AI | open | **AI stack: PGVector DB + backup** — `pgvector` postgres on `db-internal`; add DBxx block to `db-backup` + Kopia scope (RAG index + chat history — KOPS-026 class). · [ai-stack.md](docs/ai-stack.md), [backup.md](docs/backup.md) |
| HD-103 | 3 | AI | open | **AI stack: Docling OCR** — CPU `docling-serve` for RAG ingestion (spares dGPU). · [ai-stack.md](docs/ai-stack.md) |
| HD-104 | 4 | AI | open | **AI stack: OpenClaw agent + integrations** — pinned version; register as model in LiteLLM; OpenCloud WebDAV skill (read/write family files); wire Open WebUI ↔ OpenClaw ↔ OpenCloud. · [ai-stack.md](docs/ai-stack.md) |
| HD-105 | 2 | AI | open | **AI stack: secrets + wiring** — `openrouter_api`, `cohere_api`, `litellm_master_key`, `openwebui_secret`, `pgvector_db` in 1Password; catalog rows + index map already added. · [deployment-secrets.md](docs/deployment-secrets.md) |
| HD-106 | 2 | AI + Human | done | *(decision)* **Office MCP bridges = native Windows per-client apps (no Docker)** — Office COM requires a licensed, installed Office **natively on the Windows host**; Docker/Linux can't reach host COM automation. The bridge (Node MCP/SSE wrapper + pinned PyWin32 COM worker) runs natively per client. Version-pinned (Flaw-B supply-chain discipline). Distributed from a repo-owned `client/office-bridge/` folder served read-only over the Headscale tunnel (independent of Ansible/GitOps, which manages server Docker, not Windows endpoints). · [llm-office.md](docs/llm-office.md) |
| HD-107 | 2 | AI + Human | done | *(decision)* **Linux clients = server-side Office tools only** — `python-docx`/`python-pptx`/`openpyxl` on the server act on files in OpenCloud (file SSOT); results appear in the synced OpenCloud folder on any host (Linux opens them in ONLYOFFICE). No live COM on Linux — file-level sync latency, **not** in-app live editing. · [llm-office.md](docs/llm-office.md) |
| HD-108 | 2 | AI + Human | done | *(decision)* **OpenCloud = file SSOT · Open WebUI = chat/UX SSOT** — Office files live/round-trip in OpenCloud; chat + RAG + all tools live in Open WebUI (+PGVector). **AnythingLLM and LocPilot retired** once the Office MCP path lands. · [llm-office.md](docs/llm-office.md), [ai-stack.md](docs/ai-stack.md) |
| HD-109 | 2 | AI + Human | done | *(decision)* **Office MCP bridges exposed over Headscale-only, token-auth** — bind to the Headscale interface only (no public, no host `0.0.0.0`), token-auth, matching the repo exposure convention. · [network-vpn.md](docs/network-vpn.md) |
| HD-110 | 3 | AI | done | **Research: unified vs per-app Office MCP bridge + client topology** — ✅ **Complete (2026-08):** one unified bridge (PPT+Excel+Word) behind a single Headscale endpoint + token is feasible, but **needs a thin STDIO→HTTP wrapper** we own — Open WebUI's MCP client is `streamablehttp_client` (remote HTTP), while every native COM server (`ppt-mcp`, `word-mcp-live`, `office-mcp`) is stdio-local. **Recommendation:** unified bridge v1 on the shared family desktop; use mature per-app backends (`ppt-mcp` 1.7.0 + `word-mcp-live` + an added Excel) or adopt immature unified `office-mcp` (0★) for PoC. Excel-live server gap is an open risk. Gates HD-111. · [hd110-office-mcp-research.md](docs/hd110-office-mcp-research.md) |
| HD-111 | 4 | AI | open | **Office MCP via Open WebUI** — `ppt-mcp` first (proven, from OpenWeb.md), then extend/parallel Word+Excel; register as MCP **servers in Open WebUI** (Tools); **retires AnythingLLM + LocPilot**. Server-side python-docx/pptx/openpyxl path for Linux (HD-107). Depends on HD-110. · [llm-office.md](docs/llm-office.md), [ai-stack.md](docs/ai-stack.md) |
| HD-09 | 1 | AI | open | **UPS web-UI firewall rule** — open 80/443 Home→Mgmt for `10.10.99.9` only; Modbus 502 retired (no consumer). ✅ **IaC done** (router role: trusted-admin → `ups_management` 80/443); ⏳ not deployed. · [hardware-ups.md](docs/hardware-ups.md) |
| HD-10 | 2 | AI | done | **Generate `oldsrv/preseed.cfg`** — created: ext4 root on 960 EVO 500 GB, 970 EVO 1 TB left raw for ZFS pool `nvme`, XFCE desktop, GRUB on NVMe. · [deployment-preseed.md](docs/deployment-preseed.md) |
| HD-11 | 2 | AI | done | **Create Pi first-boot config** — `first-boot-config.sh` writes cloud-init `user-data` + fallback SSH enable on boot partition for raspi.debian.net images. · [deployment-preseed.md](docs/deployment-preseed.md) |
| HD-12 | 3 | AI | done | **Implement `inventory.md` render pipeline** — enhanced `inventory.md.j2` template (proper frontmatter, 5-column table, render instructions), created initial `docs/inventory.md` from group_vars data. Render hook already wired in `render-docs.yml` + `docker_services` post-deploy. · [interfaces.md](docs/interfaces.md) |
| HD-13 | 3 | AI + Human | open | **Homematic full-local (HmIP-RFUSB + RaspberryMatic)** — replace HAP cloud mode with local `homematic` XML-RPC; agent builds roles, human moves/fits the stick. Part of redo (HD-04). · [observability.md](docs/observability.md) |
| HD-14 | 2 | AI | open | **Export HA entity list** — enable HA Prometheus exporter; needed for TileBoard + Grafana. Wait for observability. · [smart-home.md](docs/smart-home.md) |
| HD-15 | 1 | AI | open | **Confirm HACS custom-component versions/repos** — `motion`, `ai_task`, Weather-2000, OneDrive, go2rtc via SSH / config git repo (REST API can't expose). · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-17 | 3 | AI | open | **Single failover button + `ha-failover.sh`** — RMat → wait → VIP → standby, on Homepage; manual-trigger design accepted. ✅ **IaC done + committed:** `ha-failover.sh` (forward + reverse), standby keepalived normal/failover configs (VRID/interface/priority vars), trigger API endpoint + systemd unit (`ha-failover-api`, token auth), Homepage forward/reverse buttons. ⏳ **Not deployed** (hosts not provisioned); deploy needs 1Password `ha-failover_api` (api → credential) + the HmIP-RFUSB stick physically moved at runbook time. · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-18 | 2 | Human | open | **Once: test HmIP-RFUSB pairing transfer** + entity reconstruction across stick move. Hands-on; requires HD-13. · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-54 | 2 | AI + Human | open | *(decision)* **Grafana/n8n SMTP relay provider** — `grafana_smtp_host` undecided; the alert fail-safe email can't deliver until a relay is chosen. Related: HD-30 (Infomaniak). · [observability.md](docs/observability.md), [deployment-secrets.md](docs/deployment-secrets.md) |

| HD-65 | 2 | AI | open | **Fail-loud on missing secrets** — remove `default('')` (pihole `WEBPASSWORD`) so a failed 1Password lookup fails loudly instead of deploying unprotected. ROI · source qwen. · [deployment-secrets.md](docs/deployment-secrets.md) |

| HD-77 | 2 | AI | open | **Split `n8n_password`** — separate `n8n_password` (N8N_ENCRYPTION_KEY) from `n8n-webhook_api` (webhook auth token) so key rotation is independent (KOPS-031). · source qwen. · [deployment-secrets.md](docs/deployment-secrets.md) |
| HD-78 | 2 | AI | open | **Router INPUT-chain firewall** — restrict management services (API, SSH, WinBox, www) to Management VLAN 99 only; currently extensive FORWARD but no INPUT chain (KOPS-003/009). · source qwen. · [network-vlans.md](docs/network-vlans.md), [network-ops.md](docs/network-ops.md) |
| HD-79 | 2 | AI | open | **Pin RaspberryMatic USB path per host** — exact `/dev/serial/by-id/` in `host_vars` + udev rule/symlink (glob in template doesn't resolve; KOPS-040). · source qwen. · [smart-home-failover.md](docs/smart-home-failover.md) |
| HD-80 | 2 | AI | open | **Unique root password hash per host in preseed** — render per-host hash at preseed time, or disable root login (ansible-admin has NOPASSWD sudo); currently identical placeholder hash on nas+oldsrv (KOPS-044). · source qwen. · [deployment-preseed.md](docs/deployment-preseed.md) |
| HD-81 | 2 | AI | open | **Shrink HA `trusted_proxies` from `/16` to Traefik container IPs** — prevent spoofed client IPs from sibling containers (KOPS-039). · source qwen. · [smart-home-failover.md](docs/smart-home-failover.md), [security.md](docs/security.md) |
| HD-82 | 2 | AI | open | **Grafana single auth path** — enable `GF_AUTH_DISABLE_LOGIN_FORM: "true"` to force auth through Authentik proxy (KOPS-008). · source qwen. · [observability.md](docs/observability.md) |
| HD-83 | 2 | AI | open | **Restrict router API to Management VLAN in bootstrap .rsc itself** — disable `api`/`www-ssl` or bind to mgmt interface in the bootstrap scripts, not just the Ansible role (KOPS-003/042). · source qwen. · [network-ops.md](docs/network-ops.md) |
| HD-84 | 2 | AI | open | **Headscale ACL policy or fix misleading comment** — empty `acl_policy_path` auto-approves OIDC registrations; add real ACL or correct the comment (KOPS-022). · source qwen. · [network-vpn.md](docs/network-vpn.md) |

## Priority 3

| ID | D | Exec | Status | Item |
|----|---|------|--------|------|
| HD-19 | 2 | AI | done | **Pi SD-card wear: trim HA recorder + log strategy** — recorder `purge_keep_days: 2` / `commit_interval: 5` / `exclude` (not disabled: keeps Logbook/Energy-LTS/history_stats) + Docker log driver `local` (10m×2) + `journald Storage=volatile` + `/var/log` tmpfs. Implemented as HA config template + docker role daemon.json + home_assistant role tasks (all gated to Pi only). · [observability.md](docs/observability.md)
| HD-20 | 1 | Human | open | **Confirm full Supervisor add-on list** — `/api/hassio/addons` returned 401 (non-admin token); needs admin/SSH on HAOS host. · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-21 | 1 | AI + Human | open | **Confirm ESPHome / Guition ESP32-S3 status** — `esphome` not loaded; agent checks network/repo, owner knows if the device was ever added. · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-22 | 1 | AI + Human | open | *(decision)* **Weather 2000 (SI) source** — third-party/HACS vs core; retain or replace. Agent researches, human decides. · [home-assistant-current.md](docs/home-assistant-current.md) |
| HD-23 | 1 | AI | open | **Confirm HmIP-SWO-B channels** — no rain / wind-direction on this sensor; verification only. · [smart-home.md](docs/smart-home.md) |
| HD-24 | 1 | Human | open | *(decision)* **TileBoard wall tablet model** — iPad / Android / repurposed; family/hardware purchase. · [interfaces.md](docs/interfaces.md) |
| HD-25 | 1 | Human | open | *(decision)* **Wake word final approval** — "Hey, assistant" is tentative; family meeting needed. · [smart-home.md](docs/smart-home.md) |
| HD-26 | 1 | AI | open | **Confirm UPS SNMP UDP (161/udp)** on the NIC — TCP probe closed, UDP untested; one probe vs `10.10.99.9`. · [hardware-ups.md](docs/hardware-ups.md) |
| HD-27 | 4 | AI + Human | open | **Voice pipeline build-out** — Whisper → Ollama → Piper containers, flash ESP32-S3 (ESPHome + microWakeWord), HA Assist on phones; GPU + physical flashing. · [smart-home-voice.md](docs/smart-home-voice.md) |
| HD-28 | 3 | AI | open | **Office AI stack** — Ollama models/downloads, n8n Docker, ONLYOFFICE on Debian desktop + **MS Office via MCP tools in Open WebUI** (see HD-106–HD-111); depends on oldsrv GPU. Superseded: AnythingLLM + LocPilot replaced by the Open WebUI MCP path. · [llm-office.md](docs/llm-office.md) |
| HD-29 | 2 | Human | open | *(decision)* **Bulk media off-site** — iDrive e2 space/cost headroom, or keep bulk local-only (ZFS). Input to HD-31. · [backup.md](docs/backup.md) |
| HD-30 | 1 | Human | open | *(buy)* **Sign up Infomaniak kSuite** — email, CalDAV, catch-all aliases; ~€3–5/mo; secrets → 1Password `Homelab`. · [subscription.md](docs/subscription.md) |
| HD-43 | 3 | AI | open | **Deploy/verify Media ·\*arr stack** — recent IaC added the templates (jellyfin, seerr, sonarr, radarr, lidarr, prowlarr, bazarr, sabnzbd, qbittorrent+gluetun, profilarr, recyclarr) in `group_vars/home_servers.yml`; deploys on oldsrv bulk/media NFS. · [services.md](docs/services.md) |
| HD-44 | 2 | AI | open | **Deploy/verify new ops services** — `dozzle` (`logs.`, Forward-Auth, viewer-only) and `traefik-ha` VIP edge on the Pi (added in recent IaC but not tracked/verified). · [services.md](docs/services.md) |
| HD-46 | 4 | AI | open | **Implement Matrix IaC (native-only)** — ✅ **IaC done + committed (`62e0045`):** `matrix/` (Tuwunel, `matrix.kogler.si`) + `element-web/` (Element Web, `chat.kogler.si`) compose templates + `group_vars/home_servers.yml` entries; SSO → Authentik OIDC; registration closed (`allow_registration=false`, bootstrap via `registration_shared_secret`); RocksDB on `/srv/docker/matrix` (no external DB). Secrets → 1Password `matrix_api` + `matrix_password` ([deployment-secrets.md](docs/deployment-secrets.md)). ⏳ **Not deployed:** hosts not provisioned; needs HD-47 (public records + `.well-known` delegation) + Authentik OIDC provider/redirect URI. ⚠ **No bridges in Phase 1** (deferred — HD-48). · [services-matrix.md](docs/services-matrix.md) |
| HD-47 | 2 | AI | open | **Matrix public records + Federation** — publish `matrix`/`chat` (Cloudflare DNS-only) + `_matrix` well-known/SRV delegation; WAN allow 443 (8448 optional) to oldsrv; **no Forward-Auth on `/_matrix/*`**. · [services-traefik.md](docs/services-traefik.md), [network-dns.md](docs/network-dns.md) |
| HD-48 | 3 | AI + Human | open | **Requested-only bridges (deferred, Phase 2 best-effort)** — WhatsApp/Messenger/Signal bridges are **out of Phase 1 scope** (every bridge risks a real external account). Revisit **only if family asks**, and then only against **dedicated** numbers, accepting re-pairing/ban. · [services-matrix.md](docs/services-matrix.md) |
| HD-49 | 3 | AI | open | **Backup Matrix identity + media** — signing/identity keys (critical — reissue breaks rooms), homeserver DB (db-backup/Kopia), media store; add to backup policy. · [services-matrix.md](docs/services-matrix.md), [backup.md](docs/backup.md) |
| HD-55 | 2 | AI + Human | open | *(decision)* **Alloy per-host `instance` label** — every host scrapes `127.0.0.1:9998` → identical `instance` (series collide in Prometheus); set per-host (e.g. `{{ inventory_hostname }}`) before enabling Alloy on the Pi. · [observability.md](docs/observability.md) |
| HD-57 | 3 | AI + Human | open | **Finance pre-deploy prep (Actual Budget / Enable Banking)** — verify EB redirect URL (`budget.kogler.si`) covered by Traefik + wildcard cert; Wise API token (read-only); IBKR Flex Query token URL; *(decision)* UniCredit SI email-transaction alerts (World Elite) vs SMS; *(decision)* `actual-server:nightly` vs stable + n8n bridge; enter initial capital base. · [services-finance.md](docs/services-finance.md) |
| HD-51 | 2 | AI + Human | done | *(decision)* **Family users & shared-data ownership (multi-axis identity model)** — ✅ **Decided (2025-08-16):** keep three **separate** ownership axes — ① **persons** = one Authentik identity each (4 family + `guest`); ② **shared bytes** = a neutral `media`/`media` **system** account (dedicated uid/gid, e.g. `1005`, stored once as `storage_uid`/`storage_gid` — **not** `domen`, **not** 1000) owning the shared NAS datasets + local shared files; ③ **processes** = least-privilege containers using `storage_uid`/`storage_gid` (→ HD-94 / KOPS-060). oldsrv: each human = own Linux login (4 + guest), auto-login = primary family account (**not** domen), family users **not** in the `docker` group. **nas: no interactive human logins** — only `ansible-admin` + `ai-debug` (ops) + the neutral system owner. **OpenCloud: Authentik OIDC per-person accounts** (native SSO, not Forward-Auth) so each user gets real per-user file isolation; storage on a NAS dataset owned by the neutral uid. · [services-authentik.md](docs/services-authentik.md), [deployment-ansible.md](docs/deployment-ansible.md) |
| HD-52 | 1 | AI + Human | open | *(decision)* **OpenCloud sync client packaging** — official client (opencloud-eu/desktop) ships AppImage only, no apt repo; options: AppImage → /opt + .desktop entry vs Debian `nextcloud-desktop` (protocol-equivalent) vs skip. Blocks office role's client. · [llm-office.md](docs/llm-office.md) |
| HD-58 | 3 | AI | open | **Implement Stirling PDF service** — self-hosted PDF toolkit (merge/split/compress/convert/number/OCR via Tesseract); family-friendly replacement for online PDF editors. Compose template + `group_vars/home_servers.yml` entry per the `docker_services` role (HD-50); catalog row in [`services.md`](docs/services.md). **Auth (decided 2025-08-15): anonymous mode** (`SECURITY_ENABLELOGIN=false`, default) **+ Authentik Forward-Auth at the Traefik edge** — same pattern as admin UIs; **native Stirling OIDC/SAML deliberately NOT used** (beta, adds per-user roles we don't need). **Exposure: internal-only** — no Cloudflare record, WAN-blocked; remote access only via the Headscale VPN (road-warrior), NOT public. Enable OCR (`TESSERACT_LANGS=eng+slv`, Slovenian). All processing in-memory, nothing persisted to disk → no ZFS/backup implication. Low RAM (~100–200 MB idle). · [services.md](docs/services.md) |
| HD-40A | 3 | AI + Human | open | *(Phase 1.5)* **Provision VPS + establish public Traefik edge** — Contabo VPS purchased, WireGuard S2S home↔VPS, Traefik on VPS terminates TLS for public subset. Backends still on oldsrv over WG tunnel. Cloudflare A records updated. · [services-vps.md](docs/services-vps.md) |
| HD-40B | 3 | AI | open | *(Phase 1.5)* **Migrate public-facing services to VPS** — Authentik, OpenCloud web, Forgejo, Grafana. Databases stay on LAN over WG tunnel. · [services-vps.md](docs/services-vps.md) |
| HD-59 | 2 | AI | open | **Internal service auth on flat Docker networks** — Ollama (`OLLAMA_AUTH_*` env vars), Kopia server (`--password` flag replacing `--without-password`), Signal CLI (basic auth wrapper on services-internal), Prometheus (`--web.config.file` with htpasswd). Flat networks = zero auth between containers; supply-chain compromise in one image gives attacker free rein. Auth tokens → 1Password `<service>-internal_api`. · [deployment-compose.md](docs/deployment-compose.md), Qwen-bugs KOPS-001/016/002 |

| HD-85 | 1 | AI | open | **Add CrowdSec collections** — extend beyond traefik+linux: home-assistant, matrix, grafana parsers (KOPS-041). · source qwen. · [observability.md](docs/observability.md) |
| HD-86 | 1 | AI | open | **`op signin --account` instead of bashrc token** — stop persisting OP token in `~/.bashrc` for production (bootstrap OK as-is; KOPS-011). · source qwen. · [deployment-secrets.md](docs/deployment-secrets.md) |
| HD-87 | 1 | AI | open | **Pin CrowdSec bouncer plugin version** — explicit version in group_vars instead of hardcoded default (KOPS-029). · source qwen. · [deployment-compose.md](docs/deployment-compose.md) |
| HD-88 | 1 | AI | open | **Dedup sshd_config append in post_install.sh** — guard against double-run (KOPS-012). · source qwen. · [deployment-preseed.md](docs/deployment-preseed.md) |
| HD-89 | 1 | AI | open | **Disable/move unused AP ethernet ports off Mgmt VLAN** — wired devices on AP ports currently get full Management access (KOPS-046). · source qwen. · [network-vlans.md](docs/network-vlans.md) |
| HD-90 | 1 | AI | open | **Renovate managers: ansible-galaxy + pip** — track Ansible collections + Python packages, not just Docker (KOPS-062). · source qwen. · [deployment-renovate.md](docs/deployment-renovate.md) |
| HD-91 | 2 | AI | open | **Fail-closed guards on missing secrets** — add `fail: msg=` in templates when critical secrets absent (relates to HD-65; KOPS cross-cutting). · source qwen. · [deployment-secrets.md](docs/deployment-secrets.md) |

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

- **Single backlog decided:** `todo.md` is the one backlog for planned work + open decisions (HD-XX). The former `docs/issues.md` scratchpad was **removed** — route new defects/follow-ups into `todo.md` with an HD-XX entry (or mark inline in the owning doc with a ⚠ marker).
- **Resolved dead references:** `docs/network-devices.md` (HD-35 — content adopted into `assets/Network-Devices.canvas`; HD-35 done) and `docs/inventory.md` (HD-12 — render pipeline done; `docs/inventory.md` is now generated). No open dead references remain.
- Dependencies: HD-03 → HD-04 → HD-13 · HD-06/07 → HD-08 · HD-01 done ✅ · HD-29 → HD-31 · HD-50 done ✅ → HD-16 → HD-43/HD-44/HD-46 (Authentik is a hard prerequisite for Forward-Auth services) · HD-50 blocks all `docker_services` deployments.
- **Recently-implemented IaC (committed at template/role level):** storage role (ZFS layout, snapshots, NFS, push jobs), face-thumbnail push over NFS, boot-time provisioning, traefik-ha edge failover (**HA primary/standby steps now committed** — keepalived + `ha-failover.sh` (HD-17)), the Media/·\*arr + dozzle templates (→ HD-43/-44), and the **router/switch network roles** (→ HD-03). These are **implemented and committed in IaC but not yet deployed** to live hosts; that pending live provisioning is tracked by the deploy/verify tasks (Phase 2/3), not as open defects.

## Executor summary

| Exec | Count | IDs |
|------|-------|-----|
| AI | 42 | HD-01,02,06,07,08,09,10,11,12,14,15,16,17,19,23,26,28,32,33,35,36,37,38,40B,41,43,44,45,46,47,49,50,59,94,100,101,102,103,104,105,110,111 |
| Human | 10 | HD-05(done),18,20,24,25,29,30,31,39,42 |
| AI + gate | 2 | HD-03, HD-04 |
| AI + Human | 20 | HD-13,21,22,27,34,40A,48,51,52,53,54,55,56(done),57,92,93,106,107,108,109 |
