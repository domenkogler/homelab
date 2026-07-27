# Kogler Homelab

Domači strežnik in omrežje družine Kogler — hibridni Debian homelab, ki hkrati služi kot družinski računalnik.
Vse je opisano tako, da lahko deluje brez Domna.

---

## Za družino (v slovenščini)

→ **[Dokumentacija za družino](docs/_DEFERRED-family-documentation-plan.md)** *(v nastajanju — zadnja prioriteta)*

Ko bo postavljeno, bo domača stran na **`kogler.si`** glavna vstopna točka za vse storitve.

| Storitev | Naslov | Kaj je to |
|----------|--------|-----------|
| Fotografije | `foto.kogler.si` | Družinske slike (kot Google Photos) |
| Datoteke | `file.kogler.si` | Skupne datoteke (kot Google Drive) |
| Git | `git.kogler.si` | Koda in dokumentacija |

---

## For Maintainers (in English)

### Documentation

| Document | Content |
|----------|---------|
| [01 — Network Architecture](docs/01-network-architecture.md) | VLANs, DNS, firewall, physical layout |
| [02 — Home Server Hardware](docs/02-home-server-hardware.md) | Phase 1 Debian desktop + Phase 2 Ryzen build |
| [03 — VPS Infrastructure](docs/03-vps-infrastructure.md) | Proxmox, Traefik, Authentik, services, domains |
| [04 — VPN & Remote Access](docs/04-vpn-and-remote-access.md) | WireGuard, Headscale, travel router |
| [05 — Smart Home & Voice](docs/05-smart-home-and-voice.md) | Home Assistant, voice pipeline, dashboards |
| [06 — Backup & Disaster Recovery](docs/06-backup-and-disaster-recovery.md) | Kopia, db-backup, recovery scenarios |
| [07 — Local LLM & Office](docs/07-local-llm-office.md) | Ollama models, ONLYOFFICE, MS Word AI chain |
| [08 — GitOps Operations (Isaac)](docs/08-gitops-operations.md) | Renovate, Forgejo Actions, Homepage, deployment lifecycle |
| [09 — Device Inventory](docs/09-device-inventory.md) | Printable port map — CRS328 + RB4011 every port |

### Implementation

| Path | Content |
|------|---------|
| [`Iaac/README.md`](Iaac/README.md) | Ansible implementation specification — roles, templates, build order |
| [`Iaac/ansible/`](Iaac/ansible/) | Ansible playbooks, roles, inventory, group vars |
| [`Iaac/bootstrap-ansible-client/`](Iaac/bootstrap-ansible-client/) | Management laptop setup script |

### Bootstrap (Management Laptop)

```bash
git clone <this-repo>
cd Iaac/bootstrap-ansible-client
bash bootstrap.sh
source ~/.bashrc
ansible-playbook -i ../ansible/inventory.ini ../ansible/site.yml
```

---

## Repository Structure

```
.
├── docs/                     # Canonical documentation (01–09)
├── Iaac/                     # Ansible code + implementation spec
│   ├── README.md
│   ├── ansible/
│   └── router/               # RouterOS .rsc scripts (rb4011, ap, crs328)
├── brainstorming/            # Source material (LLM chats, legacy notes)
├── obsolete/                 # Superseded configs (pre-IaC RouterOS scripts)
└── README.md                 # You are here
```

---

## Key Design Decisions

- **Phase 1 first:** Existing i7-7700K + RX 7600 as bare-metal Debian desktop. No hardware purchase needed to start
- **GitOps operations:** Renovate tracks updates → Forgejo Actions deploys via Ansible `--tags`
- **Single Git repo:** IaC, documentation, and family guides live together
- **Five interfaces, no overlap:** Homepage (family launchpad), TileBoard (smart home), Grafana (analytics), Forgejo (admin), Obsidian (knowledge base)