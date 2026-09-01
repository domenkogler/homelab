# Ansible managed
<!-- Service inventory — auto-generated from IaC/ansible/group_vars docker_services list. -->
<!-- Do NOT hand-edit. Change group_vars/*.yml (home_servers.yml, raspberry_pi.yml, vps.yml) and re-render. -->
<!-- Re-render:   ansible-playbook IaC/ansible/playbooks/render-docs.yml -i IaC/ansible/inventory.ini -->
<!-- (also regenerated automatically by the docker_services role post-deploy hook) -->
<!-- Source of truth: IaC/ansible/group_vars/ (home_servers.yml, raspberry_pi.yml, vps.yml) -->

# Service Inventory

> **Source of truth:** the `docker_services` lists in `group_vars/*.yml` (home_servers.yml, vps.yml).
> This page is a generated view across ALL docker hosts. For architectural context (RAM, networks, descriptions), see
> [`services.md`](services.md).

Services grouped by host, in the order defined in `group_vars` (grouped by purpose in the source).

## vps.kogler.si

| # | Service | Subdomain | URL | Status |
|---|---------|-----------|-----|--------|
| 1 | traefik | traefik | `https://traefik.kogler.si` | enabled |
| 2 | crowdsec | crowdsec | `https://crowdsec.kogler.si` | enabled |
| 3 | authentik | sso | `https://sso.kogler.si` | enabled |
| 4 | homepage | home | `https://home.kogler.si` | enabled |
| 5 | opencloud | file | `https://file.kogler.si` | enabled |
| 6 | onlyoffice-docs | office | `https://office.kogler.si` | enabled |
| 7 | immich-app | foto | `https://foto.kogler.si` | enabled |
| 8 | forgejo | git | `https://git.kogler.si` | enabled |
| 9 | zipline | bin | `https://bin.kogler.si` | enabled |
| 10 | litellm | litellm | `https://litellm.kogler.si` | enabled |
| 11 | qdrant | qdrant | `https://qdrant.kogler.si` | enabled |
| 12 | docling | docling | `https://docling.kogler.si` | enabled |
| 13 | open-webui | ai | `https://ai.kogler.si` | enabled |
| 14 | pi-dev | pi-dev | `https://pi-dev.kogler.si` | enabled |
| 15 | dsh | dsh | `https://dsh.kogler.si` | enabled |
| 16 | rag-mcp | rag-mcp | `https://rag-mcp.kogler.si` | disabled |
| 17 | forgejo-mcp | forgejo-mcp | `https://forgejo-mcp.kogler.si` | disabled |
| 18 | openclaw | openclaw | `https://openclaw.kogler.si` | enabled |
| 19 | prometheus | prometheus | `https://prometheus.kogler.si` | enabled |
| 20 | loki | loki | `https://loki.kogler.si` | enabled |
| 21 | grafana | stats | `https://stats.kogler.si` | enabled |
| 22 | blackbox-exporter | blackbox-exporter | `https://blackbox-exporter.kogler.si` | enabled |
| 23 | dozzle | logs | `https://logs.kogler.si` | enabled |
| 24 | traefik-tailnet | traefik-tailnet | `https://traefik-tailnet.kogler.si` | enabled |
| 25 | n8n | n8n | `https://n8n.kogler.si` | enabled |
| 26 | kopia-server | kopia-server | `https://kopia-server.kogler.si` | enabled |
| 27 | db-backup | db-backup | `https://db-backup.kogler.si` | enabled |
| 28 | matrix | matrix | `https://matrix.kogler.si` | enabled |
| 29 | chat | chat | `https://chat.kogler.si` | enabled |
| 30 | headscale | vpn | `https://vpn.kogler.si` | enabled |
| 31 | metabase | sec | `https://sec.kogler.si` | enabled |
| 32 | crowdsec-web-ui | csui | `https://csui.kogler.si` | enabled |
| 33 | pairdrop | drop | `https://drop.kogler.si` | enabled |
| 34 | stirling-pdf | pdf | `https://pdf.kogler.si` | enabled |
| 35 | renovate | renovate | `https://renovate.kogler.si` | enabled |

## oldsrv.kogler.si

| # | Service | Subdomain | URL | Status |
|---|---------|-----------|-----|--------|
| 1 | ollama | ollama | `https://ollama.kogler.si` | enabled |
| 2 | immich-ml | immich-ml | `https://immich-ml.kogler.si` | enabled |
| 3 | technitium | dns | `https://dns.kogler.si` | enabled |
| 4 | pihole | ad | `https://ad.kogler.si` | enabled |
| 5 | home-assistant-standby | home-assistant-standby | `https://home-assistant-standby.kogler.si` | disabled |
| 6 | dozzle | logs | `https://logs.kogler.si` | disabled |
| 7 | signal-cli-rest-api | signal-cli-rest-api | `https://signal-cli-rest-api.kogler.si` | enabled |
| 8 | sunshine | sunshine | `https://sunshine.kogler.si` | enabled |
| 9 | jellyfin | media | `https://media.kogler.si` | enabled |
| 10 | seerr | seerr | `https://seerr.kogler.si` | enabled |
| 11 | sonarr | sonarr | `https://sonarr.kogler.si` | enabled |
| 12 | radarr | radarr | `https://radarr.kogler.si` | enabled |
| 13 | lidarr | lidarr | `https://lidarr.kogler.si` | enabled |
| 14 | prowlarr | prowlarr | `https://prowlarr.kogler.si` | enabled |
| 15 | bazarr | bazarr | `https://bazarr.kogler.si` | enabled |
| 16 | sabnzbd | sab | `https://sab.kogler.si` | enabled |
| 17 | qbittorrent | torrent | `https://torrent.kogler.si` | enabled |
| 18 | profilarr | profilarr | `https://profilarr.kogler.si` | enabled |
| 19 | recyclarr | recyclarr | `https://recyclarr.kogler.si` | enabled |
| 20 | actual-budget | actual-budget | `https://actual-budget.kogler.si` | enabled |
| 21 | kopia-agent | kopia-agent | `https://kopia-agent.kogler.si` | enabled |

## pi.kogler.si

| # | Service | Subdomain | URL | Status |
|---|---------|-----------|-----|--------|
| 1 | home-assistant-primary | home-assistant-primary | `https://home-assistant-primary.kogler.si` | enabled |
| 2 | technitium-secondary (secondary) | technitium-secondary | `https://technitium-secondary.kogler.si` | enabled |
| 3 | traefik-ha | traefik-ha | `https://traefik-ha.kogler.si` | enabled |

---

> Generated from the `docker_services` lists | 2026-09-01T19:18:09Z