# Interface Matrix — Dashboards & Management

> **Role:** Detail — every user-facing interface, its audience, and its responsibility.
> **Links to:** `smart-home-dashboards.md`
> **Linked from:** `deployment.md`, `index.md`

---

## 6-Tier Interface Model

| Interface | Audience | Config | Responsibility |
|-----------|----------|--------|----------------|
| **Forgejo Control Panel** | Domen (admin) | Markdown & YAML | Management: Renovate checkboxes, PR review, Git |
| **Doco-CD Status** | Domen (admin) | REST API, Prometheus | Deployment status, drift detection, logs |
| **Homepage Launcher** | Entire family | `services.yaml`, `widgets.yaml` | Navigation: `kogler.si`, app bookmarks, health dots |
| **TileBoard Interface** | Family / Guests | `config.js` (from HA entities) | Smart home: lights, blinds, RGBW, security |
| **Grafana Dashboard** | Domen (admin) | Provisioned JSON | Observability: analytics, logs, resource metrics |
| **Obsidian Desktop** | Domen (admin) | Local `.md` folder (repo clone) | Knowledge base: docs, runbooks, Canvas diagrams |

---

## Homepage — Family Launchpad

- **Access:** `kogler.si` (root), Authentik Forward Auth
- **Content:** Grid of service tiles with green/red health dots
- **Health checks:** debhost services via Docker socket
- **Auto-generated:** Doco-CD post-deploy hook regenerates `services.yaml` + `widgets.yaml`
- **Local-only links:** `ha.home.kogler.si`, `dns.home.kogler.si` — resolve on home network or VPN only

---

## TileBoard — Smart Home Control

- **Purpose:** Fast control for lights, blinds, Shelly RGBW, media
- **Display:** Wall-mounted tablet (model TBD)
- **Style:** Dark mode, minimal
- **Config:** `config.js` generated from Home Assistant entities via Ansible template
- See [`smart-home-dashboards.md`](smart-home-dashboards.md)

---

## Grafana — Admin Analytics

- **Purpose:** Time-series data visualization
- **Data sources:** InfluxDB (fed by Telegraf from all hosts)
- **Planned graphs:**
  - MikroTik traffic (24h, 1s refresh)
  - Weather station temperature (7 days)
  - Heat-recovery ventilator metrics
  - Docker container resource usage
- **Integration:** Panels embeddable in TileBoard via `TYPES.IFRAME`

---

## Forgejo Control Panel

- **Dependency Dashboard:** Forgejo Issue with Renovate checkboxes
- **Actions tab:** Manual `workflow_dispatch` for Ansible deployment
- **Git browsing:** All configs, docs, and IaC code

---

## Obsidian Desktop

- **Vault:** Local clone of homelab Git repo
- **Targets:** `docs/` folder — technical docs + family guides
- **Canvas:** Visual topology maps (`.canvas` files in `assets/`)
- **Edit workflow:** Edit locally → commit → push → rendered in Forgejo file viewer
- **Offline:** No web UI dependency

---

## Auto-Generation Pipeline

```
Doco-CD deploys/updates container
    │
    ▼
Post-deploy hooks:
  1. Render homepage_services.yaml.j2 → /opt/homepage/config/services.yaml
  2. Render homepage_widgets.yaml.j2 → /opt/homepage/config/widgets.yaml
  3. Render inventory.md.j2 → docs/inventory.md
  4. Reload Homepage container
  5. Commit + push updated docs to Git
```