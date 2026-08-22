---
title: Homelab Documentation Index
role: index
domain: meta
status: active
tags: [index, dispatcher, ai]
---
# Homelab Documentation Index

> **Role:** AI dispatcher — start here for any task. Points to the correct context document.
> **Linked from:** `../README.md`

> ⚠️ **Planning phase.** Docs and IaC are still evolving — content will change often. **Do not chase small visual-only tweaks** (ASCII-art alignment, spacing, wording polish). Make substantive, content-level, consistent edits; accept minor cosmetic imperfections.

---

## For AI: Which Document to Read First

| Task | Start At | Also Read |
|------|----------|-----------|
| **Generate `preseed.cfg` + `post_install.sh`** | [`deployment-preseed.md`](deployment-preseed.md) | `hardware-nas.md` or `hardware-oldsrv.md`, `network-vlans.md`, `deployment-secrets.md` |
| **Generate Ansible playbook / role** | [`deployment-ansible.md`](deployment-ansible.md) | `deployment-secrets.md`, `services.md`, `hardware*.md` for target machine |
| **Generate `docker-compose.yml`** | [`deployment-compose.md`](deployment-compose.md) | `services.md`, `hardware-gpu.md` (if service uses GPU), `network-vlans.md` |
| **Configure VLANs / firewall** | [`network-vlans.md`](network-vlans.md) | `network.md`, `network-dns.md` |
| **IP/static address plan (SSOT)** | [`network-addresses-generated.md`](network-addresses-generated.md) | `network-vlans.md`, `services.md` |
| **Configure DNS** | [`network-dns.md`](network-dns.md) | `network-vlans.md`, `services.md` |
| **Configure VPN** | [`network-vpn.md`](network-vpn.md) | `network.md` |
| **Deploy a new machine** | [`deployment-preseed.md`](deployment-preseed.md) | `hardware*.md` for target, `network-vlans.md` |
| **Deployment progress / as-built record** (what did I run, what did I choose) | [`../deployment-journal.md`](../deployment-journal.md) | [`../deployment-tasks.md`](../deployment-tasks.md), [`deployment.md`](deployment.md) |
| **Redeploy a host from true zero (step-by-step runbook)** | [`../deployment-manual.md`](../deployment-manual.md) | [`../deployment-tasks.md`](../deployment-tasks.md), [`deployment-preseed.md`](deployment-preseed.md), [`../scripts/README.md`](../scripts/README.md) |
| **Understand service layout** | [`services.md`](services.md) | `services-*.md` stack docs (media/downloads/dns/utilities/admin), `services-traefik.md`, `services-authentik.md`, [`network-addresses-generated.md`](network-addresses-generated.md) |
| **Triage a candidate service / check past rejections** | [`services-review.md`](services-review.md) + [`services-rejected.md`](services-rejected.md) | `services.md`, `CONVENTIONS.md` §8.3 |
| **Triage a storage candidate / check past rejections** | [`storage-review.md`](storage-review.md) + [`storage-rejected.md`](storage-rejected.md) | `storage.md`, `CONVENTIONS.md` §8.3 |
| **Provision Authentik OIDC clients (Blueprint + glue)** | [`deployment-oidc.md`](deployment-oidc.md) | `services-authentik.md`, `deployment-secrets.md`, `deployment-compose.md`, `deployment-ansible.md`, `security.md` |
| **Backlog / open decisions** | [`todo.md`](../todo.md) | — |
| **Cross-cutting conventions / onboarding a service** | [`CONVENTIONS.md`](../CONVENTIONS.md) | owning docs (`deployment-*.md`, `network-*.md`, `services.md`) |
| **Find a script / validation gate / renderer** | [`../scripts/README.md`](../scripts/README.md) | `CONVENTIONS.md` §8, [`validate-all.sh`](../scripts/validate-all.sh) |
| **Understand personal finance / budgeting** | [`services-finance.md`](services-finance.md) | `services.md`, `services-office.md`, `deployment-compose.md` |
| **Understand the security posture / hardening** | [`security.md`](security.md) | `services-traefik.md`, `deployment-secrets.md`, `deployment-preseed.md`, `network-ops.md` |
| **Understand messaging / Matrix chat** | [`services-matrix.md`](services-matrix.md) | `services-traefik.md`, `services-authentik.md`, `services.md` |
| **Understand / build the AI stack (chat + RAG + agents)** | [`services-ai.md`](services-ai.md) | `services-office.md`, `services-authentik.md`, `deployment-secrets.md`, `deployment-ai-stack-secrets.md` (item-creation runbook, HD-105), `hardware-gpu.md` |
| **Live MS Office via Open WebUI (Word/Excel/PPT)** | [`services-office.md`](services-office.md) | `services-ai.md`, [`client/office-bridge/`](../client/office-bridge/) (HD-106–111) |
| **HA failover / high availability** | [`smart-home-failover.md`](smart-home-failover.md) | `smart-home.md`, `network-dns.md`, `deployment-ansible.md` |
| **Current HA instance / HAOS→Docker feasibility** | [`home-assistant-current.md`](home-assistant-current.md) | `smart-home.md`, `smart-home-failover.md` |
| **Understand GitOps pipeline** | [`deployment.md`](deployment.md) | `deployment-renovate.md`, `interfaces.md` |
| **Configure backup** | [`backup.md`](backup.md) | `hardware-nas.md` |
| **Design/verify ZFS datasets & properties** | [`storage.md`](storage.md) | `hardware-nas.md`, `backup.md`, `services.md`, `deployment-compose.md` |
| **Add subscription / billing** | [`subscription.md`](subscription.md) | — |
| **UPS / power + shutdown monitoring** | [`hardware-ups.md`](hardware-ups.md) | `hardware-nas.md`, `observability.md` |
| **Family-facing docs** | [`manual/README.md`](manual/README.md) | Individual guides in `manual/` |

---

## Document Map

```
docs/
├── index.md                              ← YOU ARE HERE
│
├── network.md                             Index: ISP, topology, links to network-*.md
├── network-review.md                      Network intake queue
├── network-rejected.md                    Append-only network decision log
├── network-vlans.md                       VLAN table, subnets, firewall rules
├── network-addresses-generated.md         IP address plan — SSOT (generated from IaC; never hand-edited)
├── network-dns.md                         Technitium/Pi-hole, per-subnet DNS
├── network-vpn.md                         WireGuard (S2S), Headscale mesh
├── assets/Network-Devices.canvas          Device wiring & interconnections  ⚠️ WIP
├── network-rack.md                        Rack layout → assets/Rack.canvas
├── network-ops.md                         Router config storage & versioning
│
├── hardware.md                            Index: phases, all machines, links to hardware-*.md
├── hardware-oldsrv.md                    i7-7700K internal/GPU/LAN host (GPU + media + DNS + HA standby)
├── hardware-gpu.md                        Shared GPU resource (cross-cutting)
├── hardware-nas.md                       HP MicroServer Gen8 ZFS storage (+ external SilverStone case)
├── hardware-ups.md                       PowerWalker VFI ICT/ICR IoT 3000 (UPS) — links, Modbus TCP, NUT status
├── hardware-phase2.md                     Ryzen 9 + R9700 Phase 2 build
│
├── services-finance.md                    Personal finance: Actual Budget, Enable Banking, account import strategy, AI categorization
│
├── services.md                            Index: catalog legend, networks, domains → services-*.md stack docs
├── services-media.md                      Media: Jellyfin, Immich, Seerr, *arr + storage/import
├── services-downloads.md                  Usenet/torrent ingress (SABnzbd, qBittorrent, gluetun)
├── services-dns.md                        DNS services (Technitium, Pi-hole)
├── services-utilities.md                  Utility sidekicks (n8n, signal-cli, PairDrop, Stirling)
├── services-admin.md                      Ops/GitOps/security/backup (Forgejo, Renovate, CrowdSec, Metabase, Headscale, Kopia, DB Backup)
├── observability.md                        Observability domain — stack, alerting, retention
├── services-traefik.md                    Reverse proxy edge, CrowdSec, SSL
├── services-authentik.md                  OIDC SSO, WebAuthn, Forward Auth, Blueprint + glue provisioning
├── services-matrix.md                     ★ Matrix messaging: homeserver (Tuwunel) + Element Web (native-only; bridges deferred)
├── services-vps.md                        netcup VPS (public edge) reference
├── services-review.md                     Services intake queue (rejected first, 30-day stale)
├── services-rejected.md                   Append-only services decision log (§8.3)
├── subscription.md                        Costs, providers, renewal status
├── subscriptions-table-generated.md       Subscription schedule (generated from group_vars/subscriptions.yml; never hand-edited)
├── automation-renewals.md                 Renewal-reminder automation (Homepage + n8n)
│
├── network-rack-generated.md              Rack wiring map (generated from rack-connections.json — do not hand-edit)
│
├── deployment.md                          Broad: GitOps philosophy, Ansible-only deploy flow
├── deployment-review.md                   Deployment intake queue
├── deployment-rejected.md                 Append-only deploy/hypervisor decision log
├── deployment-preseed.md                  ★ Preseed + post_install spec
├── deployment-ansible.md                  ★ Ansible role catalog & spec
├── deployment-compose.md                  ★ Docker compose conventions
├── deployment-oidc.md                     ★ Authentik OIDC provisioning: Blueprint + secret-egress glue, per-service native-OIDC recipes
├── deployment-secrets.md                  1Password backend, passwordless-first
├── 1password.md                           1Password CLI + SSH agent runner setup (SA token, vaults, ssh keys)
├── deployment-ai-stack-secrets.md         ★ AI-stack 1Password item-creation + OIDC wiring runbook (HD-105)
├── deployment-renovate.md                 Renovate Bot & update lifecycle
├── security.md                            ★ Security hardening posture (WAF, pinning, privilege, bootstrap, decisions)
├── interfaces.md                          Dashboard + management interface matrix
├── services-inventory-generated.md        Service inventory (generated from group_vars docker_services; never hand-edited)
│
├── todo.md                              Planned work + open decisions backlog (HD-XX, single source)
├── CONVENTIONS.md                        Cross-cutting rules index + service-onboarding checklist (repo root)
│
├── smart-home.md                          Index: HA, devices, architecture, links to smart-home-*.md
├── smart-home-review.md                   Smart-home intake queue
├── smart-home-rejected.md                 Append-only smart-home decision log
├── home-assistant-current.md              Live HA instance inventory (HAOS, plugins) + HAOS→Docker feasibility
├── smart-home-failover.md                 HA active/standby failover + takeover/failback runbooks
├── smart-home-voice.md                    Voice pipeline: Whisper → Ollama → Piper
├── smart-home-audio.md                    WiiM Bar, Audio Pro, Chromecast
│
├── services-office.md                          Local LLM, office tools, ONLYOFFICE, n8n

├── services-ai.md                         ★ AI platform: LiteLLM spine, Open WebUI (chat+RAG), OpenClaw agents, Docling OCR, PGVector
│
├── storage.md                         ★ ZFS dataset tree, properties, replication (SSOT — authoring spec for the `storage` role)
├── storage-review.md                    Storage intake queue
├── storage-rejected.md                  Append-only storage decision log
├── backup.md                              LAST: ZFS + Kopia, DR, restore drills
│
├── manual/                                Family guides (Slovenian, ⚠️ not yet written — deferred)
│   ├── README.md
│   ├── wifi.md
│   ├── desktop.md
│   ├── immich.md
│   ├── opencloud.md
│   ├── vpn.md
│   ├── server-restart.md
│   ├── restore-backup.md
│   ├── contacts.md
│   ├── smart-home.md
│   ├── chat.md
│   └── office-ai.md
│
└── assets/
    ├── Rack.canvas
    ├── Network-Devices.canvas
    ├── images/                             Device screenshots
    ├── references/                         Raw data (knx/, old-ha/) — machine dumps live in repo-root reports/
    └── manuals/                            Hardware manuals (PDF)
```

---

## Conventions

> **Consolidated index:** [`CONVENTIONS.md`](../CONVENTIONS.md) (repo root) names every cross-cutting rule and
> points to its owning doc — validation, IPs, secrets, language, headers, links. It is the SSOT for those;
> this index keeps only the hostnames SSOT it owns, plus two pointer legends.

- **Hostnames:** single namespace `kogler.si` — flat subdomains, split-horizon (internal-only hosts unpublished in public DNS).

  | Host | FQDN | Role |
  |------|------|------|
  | Old desktop + Docker host | `oldsrv.kogler.si` | internal/GPU/LAN host (ollama, immich-ml, jellyfin/*arr, DNS, HA standby) |
  | HP MicroServer NAS | `nas.kogler.si` | ZFS storage server |
  | Raspberry Pi 4 | `pi.kogler.si` | Home Assistant primary node (HA service = VIP `ha.kogler.si`) |
  | MikroTik Router | `router.kogler.si` | PPPoE, VLAN routing, firewall, WireGuard, CAPsMAN |
  | MikroTik Switch | `switch.kogler.si` | Layer-2 VLAN-aware PoE switch |
  | netcup VPS | `vps.kogler.si` | **public edge + live-data apps + observability backend** (day-one edge, HD-93/HD-40A) |

- **Ansible IaC:** see [`deployment-ansible.md` → IaC Authoring Conventions](deployment-ansible.md) — variables, secrets, role structure, compose template rules
- **★ legend:** Marked with ★ — *authoring specs* read by AI to write or correct the corresponding IaC. Generated views (`*-generated.md`) are **not** starred: they are rendered FROM IaC and never hand-edited — direction of truth is IaC → rendered doc (`network-addresses-generated.md`, `services-inventory-generated.md`).