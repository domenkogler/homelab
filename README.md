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
| Klepet | `chat.kogler.si` | Družinski klepet (Matrix) |

---

## Agent skills & pi config (`skills/` → global pi folder)

The repo's **`skills/` folder is the single source of truth** for the pi coding
agent's skills on the management laptop. Edit there, commit, then run
**`update_pi.cmd`** to deploy them into the global pi skills folder
(`%USERPROFILE%\.pi\agent\skills\`). Do **not** edit the global copy directly —
it is refreshed from this repo.

| Skill | Purpose |
|-------|---------|
| `platform-env` | Detect OS/shell once and apply platform assumptions (paths, `\` vs `/`, `/tmp`, `~`, `py -3` vs `python3`, UTF-8, CRLF/LF, `&&`). Run at session start and when producing plans; re-consult only on an env failure. Self-learning: records new platform traps into its reference docs. |
| `plan-task` | Produce a reviewable execution-plan directory from a goal (records the detected environment in the plan). |
| `run-task` | Execute a plan one task at a time (honors the plan's Environment + per-task models). |
| `mikrotik` | Read RouterOS config/state via the RouterOS API. |
| `shelly` | Manage WiFi Shelly devices (switch, dim, colors, WiFi). |

**Session-start config** ships from `pi-agent/` and is also deployed by
`update_pi.cmd`:
- `AGENTS.md` → `%USERPROFILE%\.pi\agent\AGENTS.md` — auto-loaded at session
  start; instructs the agent to run `platform-env` and state the environment
  before acting.
- `prompts/start.md` → `%USERPROFILE%\.pi\agent\prompts\start.md` — `/start`
  prompt template (on-demand trigger for the same environment check).

> ⚠ `update_pi.cmd` **overwrites** `~/.pi/agent/AGENTS.md` and
> `~/.pi/agent/prompts/\*` with the repo copies. If you customize your global
> `AGENTS.md` or prompts elsewhere, keep them in this repo instead.

---

## For Maintainers (in English)

> Start at **[`docs/index.md`](docs/index.md)** — the AI dispatcher / document map.

> ⚠️ **It's still the planning phase.** Docs will change often. Do **not** spend effort on small visual/cosmetic tweaks (ASCII-art alignment, spacing, wording polish) — prefer substantive, content-level edits. Keep it consistent and correct, not pixel-perfect.

### Hosts (single namespace `kogler.si`)

| Host | Role |
|------|------|
| `oldsrv.kogler.si` | Old i7-7700K desktop → family PC + Docker host |
| `nas.kogler.si` | HP MicroServer ZFS storage (+ external SilverStone case) |
| `pi.kogler.si` | Raspberry Pi 4 — Home Assistant **primary node** (`ha.kogler.si` = the VIP; standby on oldsrv), + RaspberryMatic/HmIP-RFUSB, + Technitium secondary DNS (see [`docs/smart-home-failover.md`](docs/smart-home-failover.md)) |
| `router.kogler.si` | MikroTik RB4011 — routing/firewall/VPN/CAPsMAN |
| `switch.kogler.si` | MikroTik CRS328 — L2 PoE switch |
| `vps.kogler.si` | Contabo VPS (Phase 2 — public Traefik + services) |

> Canonical host list + naming/IP conventions: [`docs/index.md`](docs/index.md) → Conventions.

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
└── README.md                 # You are here
```

---

## Key Design Decisions

- **Phase 1 first:** Existing i7-7700K + RX 7600 as bare-metal Debian desktop (now `oldsrv`). No hardware purchase needed to start
- **GitOps operations:** Renovate tracks updates → Forgejo Actions deploys via Ansible `--tags`
- **Single Git repo:** IaC, documentation, and family guides live together
- **Single DNS namespace `kogler.si`** — split-horizon; one `*.kogler.si` wildcard cert (Cloudflare DNS-01)
- **Six interfaces, no overlap:** Homepage (family launchpad), TileBoard (smart home), Grafana (analytics), Forgejo (admin), Obsidian (knowledge base), Doco-CD (deployment status)
- **Self-hosted messaging:** Matrix (Tuwunel) + Element Web — native family chat, no commercial-app dependency, no third-party bridges (deferred, Phase 2 best-effort) — see [`docs/services-matrix.md`](docs/services-matrix.md)
