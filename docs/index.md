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
| **Configure DNS** | [`network-dns.md`](network-dns.md) | `network-vlans.md`, `services.md` |
| **Configure VPN** | [`network-vpn.md`](network-vpn.md) | `network.md` |
| **Deploy a new machine** | [`deployment-preseed.md`](deployment-preseed.md) | `hardware*.md` for target, `network-vlans.md` |
| **Understand service layout** | [`services.md`](services.md) | `services-traefik.md`, `services-authentik.md` |
| **Understand observability / alerting** | [`observability.md`](observability.md) | `services.md`, `deployment-ansible.md` |
| **HA failover / high availability** | [`smart-home-failover.md`](smart-home-failover.md) | `smart-home.md`, `network-dns.md`, `deployment-ansible.md` |
| **Understand GitOps pipeline** | [`deployment.md`](deployment.md) | `deployment-renovate.md`, `interfaces.md` |
| **Configure backup** | [`backup.md`](backup.md) | `hardware-nas.md` |
| **Add subscription / billing** | [`subscription.md`](subscription.md) | — |
| **Family-facing docs** | [`manual/README.md`](manual/README.md) | Individual guides in `manual/` |

---

## Document Map

```
docs/
├── index.md                              ← YOU ARE HERE
│
├── network.md                             Broad: ISP, topology, links to →
├── network-vlans.md                       VLAN table, subnets, firewall rules
├── network-dns.md                         Technitium/Pi-hole, per-subnet DNS
├── network-vpn.md                         WireGuard, Headscale (travel router obsolete)
├── assets/Network-Devices.canvas          Device wiring & interconnections  ⚠️ WIP
├── network-rack.md                        Rack layout → assets/Rack.canvas
├── network-ops.md                         Router config storage & versioning
│
├── hardware.md                            Broad: phases, all machines
├── hardware-oldsrv.md                    i7-7700K Phase 1 Docker host + family PC
├── hardware-gpu.md                        Shared GPU resource (cross-cutting)
├── hardware-nas.md                       HP MicroServer Gen8 ZFS storage (+ external SilverStone case)
├── hardware-phase2.md                     Ryzen 9 + R9700 Phase 2 build
│
├── services.md                            Broad: catalog, networks, domains
├── observability.md                        Single source of truth: stack, alerting, retention
├── services-traefik.md                    Reverse proxy, CrowdSec, SSL
├── services-authentik.md                  OIDC SSO, WebAuthn, Forward Auth
├── services-vps.md                        Deferred Contabo VPS reference
├── subscription.md                        Costs, providers, renewal status
│
├── deployment.md                          Broad: GitOps philosophy, Doco-CD flow
├── deployment-preseed.md                  ★ Preseed + post_install spec
├── deployment-ansible.md                  ★ Ansible role catalog & spec
├── deployment-compose.md                  ★ Docker compose conventions
├── deployment-secrets.md                  1Password backend, passwordless-first
├── deployment-renovate.md                 Renovate Bot & update lifecycle
├── interfaces.md                          Dashboard + management interface matrix
│
├── smart-home.md                          Home Assistant, devices, architecture
├── smart-home-failover.md                 HA active/standby failover + takeover/failback runbooks
├── smart-home-voice.md                    Voice pipeline: Whisper → Ollama → Piper
├── smart-home-audio.md                    WiiM Bar, Audio Pro, Chromecast
│
├── llm-office.md                          Local LLM, office tools, ONLYOFFICE, n8n
│
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
│   └── smart-home.md
│
└── assets/
    ├── Rack.canvas
    ├── Network-Devices.canvas
    ├── images/                             Device screenshots
    ├── references/                         Raw data (DOMENPC-cpuz.txt)
    └── manuals/                            Hardware manuals (PDF)
```

---

## Conventions

- **Hostnames:** single namespace `kogler.si` — `oldsrv`, `nas`, `ha`, `router`, `switch`, `vps`
- **Language:** English (technical), Slovenian (family/manual)
- **Headers:** Every doc starts with `> **Role:** ...` and `> **Linked from:** ...`
- **Links:** Use relative paths (`[doc](deployment-preseed.md)`)
- **Secrets:** Never in docs — always reference 1Password `Homelab` vault
- **Generation targets:** Marked with ★ — these docs are read by AI to produce specific IaC files