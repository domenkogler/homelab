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
| 3 | technitium | dns | `https://dns.kogler.si` | enabled |
| 4 | authentik | sso | `https://sso.kogler.si` | enabled |
| 5 | homepage | home | `https://home.kogler.si` | enabled |
| 6 | opencloud | file | `https://file.kogler.si` | enabled |
| 7 | onlyoffice-docs | office | `https://office.kogler.si` | enabled |
| 8 | immich-app | foto | `https://foto.kogler.si` | enabled |
| 9 | forgejo | git | `https://git.kogler.si` | enabled |
| 10 | zipline | bin | `https://bin.kogler.si` | enabled |
| 11 | litellm | litellm | `https://litellm.kogler.si` | enabled |
| 12 | qdrant | qdrant | `https://qdrant.kogler.si` | enabled |
| 13 | docling | docling | `https://docling.kogler.si` | enabled |
| 14 | open-webui | ai | `https://ai.kogler.si` | enabled |
| 15 | rag-mcp | rag-mcp | `https://rag-mcp.kogler.si` | disabled |
| 16 | forgejo-mcp | forgejo-mcp | `https://forgejo-mcp.kogler.si` | disabled |
| 17 | openclaw | openclaw | `https://openclaw.kogler.si` | enabled |
| 18 | victoria-metrics | victoria-metrics | `https://victoria-metrics.kogler.si` | enabled |
| 19 | victoria-logs | victoria-logs | `https://victoria-logs.kogler.si` | enabled |
| 20 | grafana | stats | `https://stats.kogler.si` | enabled |
| 21 | blackbox-exporter | blackbox-exporter | `https://blackbox-exporter.kogler.si` | enabled |
| 22 | dozzle | logs | `https://logs.kogler.si` | enabled |
| 23 | traefik-tailnet | traefik-tailnet | `https://traefik-tailnet.kogler.si` | enabled |
| 24 | n8n | n8n | `https://n8n.kogler.si` | enabled |
| 25 | kopia-server | kopia-server | `https://kopia-server.kogler.si` | enabled |
| 26 | db-backup | db-backup | `https://db-backup.kogler.si` | enabled |
| 27 | matrix | matrix | `https://matrix.kogler.si` | enabled |
| 28 | chat | chat | `https://chat.kogler.si` | enabled |
| 29 | headscale | vpn | `https://vpn.kogler.si` | enabled |
| 30 | metabase | sec | `https://sec.kogler.si` | disabled |
| 31 | crowdsec-web-ui | csui | `https://csui.kogler.si` | enabled |
| 32 | pairdrop | drop | `https://drop.kogler.si` | enabled |
| 33 | stirling-pdf | pdf | `https://pdf.kogler.si` | enabled |
| 34 | renovate | renovate | `https://renovate.kogler.si` | enabled |
| 35 | navidrome | music | `https://music.kogler.si` | enabled |

## oldsrv.kogler.si

| # | Service | Subdomain | URL | Status |
|---|---------|-----------|-----|--------|
| 1 | ollama | ollama | `https://ollama.kogler.si` | disabled |
| 2 | immich-ml | immich-ml | `https://immich-ml.kogler.si` | enabled |
| 3 | technitium (secondary) | technitium | `https://technitium.kogler.si` | enabled |
| 4 | pihole | ad | `https://ad.kogler.si` | enabled |
| 5 | traefik-internal | traefik-internal | `https://traefik-internal.kogler.si` | enabled |
| 6 | home-assistant-standby | home-assistant-standby | `https://home-assistant-standby.kogler.si` | disabled |
| 7 | dozzle | logs | `https://logs.kogler.si` | disabled |
| 8 | signal-cli-rest-api | signal-cli-rest-api | `https://signal-cli-rest-api.kogler.si` | enabled |
| 9 | sunshine | sunshine | `https://sunshine.kogler.si` | enabled |
| 10 | jellyfin | media | `https://media.kogler.si` | enabled |
| 11 | seerr | seerr | `https://seerr.kogler.si` | enabled |
| 12 | seerrng | seerrng | `https://seerrng.kogler.si` | enabled |
| 13 | sonarr | sonarr | `https://sonarr.kogler.si` | enabled |
| 14 | radarr | radarr | `https://radarr.kogler.si` | enabled |
| 15 | lidarr | lidarr | `https://lidarr.kogler.si` | enabled |
| 16 | aurral | aurral | `https://aurral.kogler.si` | enabled |
| 17 | slskd | slskd | `https://slskd.kogler.si` | enabled |
| 18 | lidarr-ydl | lidarr-ydl | `https://lidarr-ydl.kogler.si` | enabled |
| 19 | tube-archivist | tube-archivist | `https://tube-archivist.kogler.si` | enabled |
| 20 | prowlarr | prowlarr | `https://prowlarr.kogler.si` | enabled |
| 21 | bazarr | bazarr | `https://bazarr.kogler.si` | enabled |
| 22 | sabnzbd | sab | `https://sab.kogler.si` | enabled |
| 23 | qbittorrent | torrent | `https://torrent.kogler.si` | enabled |
| 24 | profilarr | profilarr | `https://profilarr.kogler.si` | enabled |
| 25 | recyclarr | recyclarr | `https://recyclarr.kogler.si` | enabled |
| 26 | dsh | dsh | `https://dsh.kogler.si` | enabled |
| 27 | pi-dev | pi-dev | `https://pi-dev.kogler.si` | enabled |
| 28 | lan-litellm | lan-litellm | `https://lan-litellm.kogler.si` | disabled |
| 29 | actual-budget | actual-budget | `https://actual-budget.kogler.si` | enabled |
| 30 | kopia-agent | kopia-agent | `https://kopia-agent.kogler.si` | enabled |
| 31 | mcp-victoriametrics | mcp-victoriametrics | `https://mcp-victoriametrics.kogler.si` | enabled |
| 32 | mcp-victorialogs | mcp-victorialogs | `https://mcp-victorialogs.kogler.si` | enabled |
| 33 | homelable | homelable | `https://homelable.kogler.si` | disabled |

## pi.kogler.si

| # | Service | Subdomain | URL | Status |
|---|---------|-----------|-----|--------|
| 1 | home-assistant-primary | home-assistant-primary | `https://home-assistant-primary.kogler.si` | enabled |
| 2 | technitium-secondary (secondary-pi) | technitium-secondary | `https://technitium-secondary.kogler.si` | enabled |
| 3 | traefik-ha | traefik-ha | `https://traefik-ha.kogler.si` | enabled |

---

> Generated from the `docker_services` lists | 2026-09-14T21:38:23Z