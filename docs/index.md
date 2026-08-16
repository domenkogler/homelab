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
| **IP/static address plan (SSOT)** | [`network-addresses.md`](network-addresses.md) | `network-vlans.md`, `services.md` |
| **Configure DNS** | [`network-dns.md`](network-dns.md) | `network-vlans.md`, `services.md` |
| **Configure VPN** | [`network-vpn.md`](network-vpn.md) | `network.md` |
| **Deploy a new machine** | [`deployment-preseed.md`](deployment-preseed.md) | `hardware*.md` for target, `network-vlans.md` |
| **Understand service layout** | [`services.md`](services.md) | `services-traefik.md`, `services-authentik.md`, [`network-addresses.md`](network-addresses.md) |
| **Backlog / open decisions** | [`todo.md`](../todo.md) | — |
| **Understand personal finance / budgeting** | [`services-finance.md`](services-finance.md) | `services.md`, `llm-office.md`, `deployment-compose.md` |
| **Understand the security posture / hardening** | [`security.md`](security.md) | `services-traefik.md`, `deployment-secrets.md`, `deployment-preseed.md`, `network-ops.md` |
| **Understand messaging / Matrix chat** | [`services-matrix.md`](services-matrix.md) | `services-traefik.md`, `services-authentik.md`, `services.md` |
| **Understand / build the AI stack (chat + RAG + agents)** | [`ai-stack.md`](ai-stack.md) | `llm-office.md`, `services-authentik.md`, `deployment-secrets.md`, `hardware-gpu.md`, `hd110-office-mcp-research.md` (Office live editing) |
| **Live MS Office via Open WebUI (Word/Excel/PPT)** | [`llm-office.md`](llm-office.md) | `ai-stack.md`, `hd110-office-mcp-research.md`, [`client/office-bridge/`](../client/office-bridge/) (HD-106–111) |
| **HA failover / high availability** | [`smart-home-failover.md`](smart-home-failover.md) | `smart-home.md`, `network-dns.md`, `deployment-ansible.md` |
| **Current HA instance / HAOS→Docker feasibility** | [`home-assistant-current.md`](home-assistant-current.md) | `smart-home.md`, `smart-home-failover.md` |
| **Understand GitOps pipeline** | [`deployment.md`](deployment.md) | `deployment-renovate.md`, `interfaces.md` |
| **Configure backup** | [`backup.md`](backup.md) | `hardware-nas.md` |
| **Design/verify ZFS datasets & properties** | [`storage-zfs.md`](storage-zfs.md) | `hardware-nas.md`, `backup.md`, `services.md`, `deployment-compose.md` |
| **Add subscription / billing** | [`subscription.md`](subscription.md) | — |
| **UPS / power + shutdown monitoring** | [`hardware-ups.md`](hardware-ups.md) | `hardware-nas.md`, `observability.md` |
| **Family-facing docs** | [`manual/README.md`](manual/README.md) | Individual guides in `manual/` |

---

## Document Map

```
docs/
├── index.md                              ← YOU ARE HERE
│
├── network.md                             Broad: ISP, topology, links to →
├── network-vlans.md                       VLAN table, subnets, firewall rules
├── network-addresses.md                   ★ IP address plan — SSOT (generated from IaC)
├── network-dns.md                         Technitium/Pi-hole, per-subnet DNS
├── network-vpn.md                         WireGuard (S2S), Headscale mesh
├── assets/Network-Devices.canvas          Device wiring & interconnections  ⚠️ WIP
├── network-rack.md                        Rack layout → assets/Rack.canvas
├── network-ops.md                         Router config storage & versioning
│
├── hardware.md                            Broad: phases, all machines
├── hardware-oldsrv.md                    i7-7700K Phase 1 Docker host + family PC
├── hardware-gpu.md                        Shared GPU resource (cross-cutting)
├── hardware-nas.md                       HP MicroServer Gen8 ZFS storage (+ external SilverStone case)
├── hardware-ups.md                       PowerWalker VFI ICT/ICR IoT 3000 (UPS) — links, Modbus TCP, NUT status
├── hardware-phase2.md                     Ryzen 9 + R9700 Phase 2 build
│
├── services-finance.md                    ★ Personal finance: Actual Budget, Enable Banking, account import strategy, AI categorization
│
├── services.md                            Broad: catalog, networks, domains
├── observability.md                        Single source of truth: stack, alerting, retention
├── services-traefik.md                    Reverse proxy, CrowdSec, SSL
├── services-authentik.md                  OIDC SSO, WebAuthn, Forward Auth
├── services-matrix.md                     ★ Matrix messaging: homeserver (Tuwunel) + Element Web (native-only; bridges deferred)
├── services-vps.md                        Deferred Contabo VPS reference
├── subscription.md                        Costs, providers, renewal status
│
├── deployment.md                          Broad: GitOps philosophy, Doco-CD flow
├── deployment-preseed.md                  ★ Preseed + post_install spec
├── deployment-ansible.md                  ★ Ansible role catalog & spec
├── deployment-compose.md                  ★ Docker compose conventions
├── deployment-secrets.md                  1Password backend, passwordless-first
├── deployment-renovate.md                 Renovate Bot & update lifecycle
├── security.md                            ★ Security hardening posture (WAF, pinning, privilege, bootstrap, decisions)
├── interfaces.md                          Dashboard + management interface matrix
│
├── todo.md                              Planned work + open decisions backlog (HD-XX, single source)
│
├── smart-home.md                          Home Assistant, devices, architecture
├── home-assistant-current.md              Live HA instance inventory (HAOS, plugins) + HAOS→Docker feasibility
├── smart-home-failover.md                 HA active/standby failover + takeover/failback runbooks
├── smart-home-voice.md                    Voice pipeline: Whisper → Ollama → Piper
├── smart-home-audio.md                    WiiM Bar, Audio Pro, Chromecast
│
├── llm-office.md                          Local LLM, office tools, ONLYOFFICE, n8n
├── hd110-office-mcp-research.md            ★ Office MCP bridge research (unified vs per-app; topology) — HD-110
├── ai-stack.md                           ★ AI platform: LiteLLM spine, Open WebUI (chat+RAG), OpenClaw agents, Docling OCR, PGVector
│
├── storage-zfs.md                         ZFS dataset tree, properties, replication (SSOT)
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

Cross-cutting rules for every doc in this repo. Domain-specific policies stay in their own
`docs` (`deployment-secrets.md`, `deployment-compose.md`, `network-dns.md`, …); only the
rules below are central.

- **Validation scripts:** `scripts/` contains automated checks invoked before committing.
  Run **`bash scripts/validate-all.sh`** (Linux/CI; works on Windows git-bash) — it runs all
  checkers and exits non-zero on the first failure. Individual: `python3 scripts/validate-docker-services.py`
  after touching any compose template or group_vars docker_services list. It renders each template,
  parses the YAML, and enforces structural rules (external networks, Traefik labels, secret hygiene,
  source-level bugs). Exit 0 = all 44 templates valid. See [`scripts/validate-docker-services.py`](../scripts/validate-docker-services.py).
  Other scripts: `check_doc_ips.py` (IP address SSOT enforcement), `render_network_addresses.py`
  (regenerate SSOT doc from IaC), `validate_doc_templates.py` (smoke-test .j2 renders).

- **Hostnames:** single namespace `kogler.si` — flat subdomains, split-horizon (internal-only hosts unpublished in public DNS).

  | Host | FQDN | Role |
  |------|------|------|
  | Old desktop + Docker host | `oldsrv.kogler.si` | bare-metal Debian desktop + Docker host (Phase 1) |
  | HP MicroServer NAS | `nas.kogler.si` | ZFS storage server |
  | Raspberry Pi 4 | `pi.kogler.si` | Home Assistant primary node (HA service = VIP `ha.kogler.si`) |
  | MikroTik Router | `router.kogler.si` | PPPoE, VLAN routing, firewall, WireGuard, CAPsMAN |
  | MikroTik Switch | `switch.kogler.si` | Layer-2 VLAN-aware PoE switch |
  | Contabo VPS | `vps.kogler.si` | Phase 2 — public Traefik + public services |

- **IP addresses:** internal IPv4 ranges/addresses live **only** in
  [`network-addresses.md`](network-addresses.md) (SSOT, generated from IaC) and in IaC. Other
  docs refer to hosts by hostname/role (`oldsrv.kogler.si`, `ha-vip`, `wg-s2s`) or link the SSOT
  row. Exemptions: well-known external IPs (public DNS, third-party services — e.g. `1.1.1.1`,
  `9.9.9.9`) and historical decision-log entries (`~~strikethrough~~`). Enforced by
  `scripts/check_doc_ips.py`.
- **Language:** English (technical), Slovenian (family/manual)
- **Headers:** Every doc starts with `> **Role:** ...` and `> **Linked from:** ...`
- **Links:** Use relative paths (`[doc](deployment-preseed.md)`)
- **Secrets:** Never in docs — always reference 1Password `Homelab` vault
- **Ansible IaC:** see [`deployment-ansible.md` → IaC Authoring Conventions](deployment-ansible.md) — variables, secrets, role structure, compose template rules
- **Generation targets:** Marked with ★ — *authoring specs* read by AI to write or correct the corresponding IaC. Direction of truth: concrete values live in IaC and are rendered INTO value-carrying docs (`network-addresses.md`, `inventory.md`) — those generated views are never hand-edited.