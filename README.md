# Kogler Homelab

Domači strežnik in omrežje družine Kogler — hibridni Debian homelab, ki hkrati služi kot družinski računalnik.
Vse je opisano tako, da lahko deluje brez Domna.

---

## Za družino (v slovenščini)

→ **[Dokumentacija za družino](docs/manual/README.md)** *(v nastajanju — zadnja prioriteta)*

Domača stran na **`kogler.si`** je glavna vstopna točka za vse storitve.

| Storitev | Naslov | Kaj je to |
|----------|--------|-----------|
| Fotografije | `foto.kogler.si` | Družinske slike (kot Google Photos) |
| Datoteke | `file.kogler.si` | Skupne datoteke (kot Google Drive) |
| Git | `git.kogler.si` | Koda in dokumentacija |

---

## For Maintainers (in English)

> Start at **[`docs/index.md`](docs/index.md)** — the AI dispatcher / document map.

### Hosts (single namespace `kogler.si`)

| Host | Role |
|------|------|
| `oldsrv.kogler.si` | Old i7-7700K desktop → family PC + Docker host |
| `nas.kogler.si` | HP MicroServer ZFS storage (+ external SilverStone case) |
| `ha.kogler.si` | Raspberry Pi 4 — Home Assistant |
| `router.kogler.si` | MikroTik RB4011 — routing/firewall/VPN/CAPsMAN |
| `switch.kogler.si` | MikroTik CRS328 — L2 PoE switch |
| `vps.kogler.si` | Contabo VPS (Phase 2 — public Traefik + services) |

### Implementation

| Path | Content |
|------|---------|
| [`IaC/README.md`](IaC/README.md) | Ansible implementation specification — roles, templates, build order |
| [`IaC/ansible/`](IaC/ansible/) | Ansible playbooks, roles, inventory, group vars |
| [`IaC/bootstrap-ansible-client/`](IaC/bootstrap-ansible-client/) | Management laptop setup script |
| [`IaC/router/`](IaC/router/) | RouterOS `.rsc` (rb4011, ap) |

### Bootstrap (Management Laptop)

```bash
git clone <this-repo>
cd IaC/bootstrap-ansible-client
bash bootstrap.sh
source ~/.bashrc
ansible-playbook -i ../ansible/inventory.ini ../ansible/site.yml
```

---

## Repository Structure

```
.
├── docs/                     # Canonical documentation (index.md → document map)
├── docs/manual/              # Family guides (Slovenian)
├── IaC/                      # Ansible code + implementation spec
│   ├── README.md
│   ├── ansible/
│   ├── host/                 # preseed.cfg (nas) + shared post_install.sh
│   └── router/               # RouterOS .rsc scripts (rb4011, ap)
├── brainstorming/            # Source material (LLM chats, legacy notes)
├── obsolete/                 # Superseded configs (e.g. pre-Headscale travel VPN)
└── README.md                 # You are here
```

---

## Key Design Decisions

- **Phase 1 first:** Existing i7-7700K + RX 7600 as bare-metal Debian desktop (now `oldsrv`). No hardware purchase needed to start
- **GitOps operations:** Renovate tracks updates → Forgejo Actions deploys via Ansible `--tags`
- **Single Git repo:** IaC, documentation, and family guides live together
- **Single DNS namespace `kogler.si`** — split-horizon; one `*.kogler.si` wildcard cert (Cloudflare DNS-01)
- **Six interfaces, no overlap:** Homepage (family launchpad), TileBoard (smart home), Grafana (analytics), Forgejo (admin), Obsidian (knowledge base), Doco-CD (deployment status)
