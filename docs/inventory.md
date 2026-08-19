#
# Ansible managed
#
<!-- Service inventory — auto-generated from IaC/ansible/group_vars docker_services list. -->
<!-- Do NOT hand-edit. Change group_vars/home_servers.yml (or raspberry_pi.yml, vps.yml) and re-render. -->
<!-- Re-render:   ansible-playbook IaC/ansible/playbooks/render-docs.yml -i IaC/ansible/inventory.ini -->
<!-- (also regenerated automatically by the docker_services role post-deploy hook) -->
<!-- Source of truth: IaC/ansible/group_vars/ (home_servers.yml, raspberry_pi.yml, vps.yml) -->

# Service Inventory

> **Source of truth:** `group_vars/home_servers.yml` / `group_vars/raspberry_pi.yml` — the `docker_services` list.
> This page is a generated view. For architectural context (RAM, networks, descriptions), see
> [`services.md`](services.md).

Services listed in the order defined in `group_vars` (grouped by purpose in the source).

| # | Service | Subdomain | URL | Host | Status |
|---|---------|-----------|-----|------|--------|
| 1 | traefik | traefik | `https://traefik.kogler.si` | vps.kogler.si | enabled |
| 2 | crowdsec | crowdsec | `https://crowdsec.kogler.si` | vps.kogler.si | enabled |
| 3 | authentik | sso | `https://sso.kogler.si` | vps.kogler.si | enabled |
| 4 | opencloud | file | `https://file.kogler.si` | vps.kogler.si | enabled |
| 5 | immich-app | foto | `https://foto.kogler.si` | vps.kogler.si | enabled |
| 6 | forgejo | git | `https://git.kogler.si` | vps.kogler.si | enabled |
| 7 | litellm | litellm | `https://litellm.kogler.si` | vps.kogler.si | enabled |
| 8 | pgvector | pgvector | `https://pgvector.kogler.si` | vps.kogler.si | enabled |
| 9 | docling | docling | `https://docling.kogler.si` | vps.kogler.si | enabled |
| 10 | open-webui | ai | `https://ai.kogler.si` | vps.kogler.si | enabled |
| 11 | openclaw | openclaw | `https://openclaw.kogler.si` | vps.kogler.si | enabled |
| 12 | prometheus | prometheus | `https://prometheus.kogler.si` | vps.kogler.si | enabled |
| 13 | loki | loki | `https://loki.kogler.si` | vps.kogler.si | enabled |
| 14 | grafana | stats | `https://stats.kogler.si` | vps.kogler.si | enabled |
| 15 | blackbox-exporter | blackbox-exporter | `https://blackbox-exporter.kogler.si` | vps.kogler.si | enabled |
| 16 | n8n | auto | `https://auto.kogler.si` | vps.kogler.si | enabled |
| 17 | kopia-server | kopia-server | `https://kopia-server.kogler.si` | vps.kogler.si | enabled |
| 18 | db-backup | db-backup | `https://db-backup.kogler.si` | vps.kogler.si | enabled |
| 19 | matrix | matrix | `https://matrix.kogler.si` | vps.kogler.si | enabled |
| 20 | chat | chat | `https://chat.kogler.si` | vps.kogler.si | enabled |
| 21 | headscale | vpn | `https://vpn.kogler.si` | vps.kogler.si | enabled |
| 22 | metabase | sec | `https://sec.kogler.si` | vps.kogler.si | enabled |
| 23 | pairdrop | pairdrop | `https://pairdrop.kogler.si` | vps.kogler.si | enabled |
| 24 | stirling-pdf | pdf | `https://pdf.kogler.si` | vps.kogler.si | enabled |
| 25 | renovate | renovate | `https://renovate.kogler.si` | vps.kogler.si | enabled |

---

> Generated from `docker_services` list | 2026-08-19T15:28:44Z