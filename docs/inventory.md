# Ansible managed
<!-- Service inventory — auto-generated from IaC/ansible/group_vars docker_services list. -->
<!-- Do NOT hand-edit. Change group_vars/home_servers.yml (or raspberry_pi.yml) and re-render. -->
<!-- Re-render:   ansible-playbook IaC/ansible/playbooks/render-docs.yml -i IaC/ansible/inventory.ini -->
<!-- (also regenerated automatically by the docker_services role post-deploy hook) -->
<!-- Source of truth: IaC/ansible/group_vars/ (home_servers.yml, raspberry_pi.yml) -->

# Service Inventory

> **Source of truth:** `group_vars/home_servers.yml` / `group_vars/raspberry_pi.yml` — the `docker_services` list.
> This page is a generated view. For architectural context (RAM, networks, descriptions), see
> [`services.md`](services.md).

Services listed in the order defined in `group_vars` (grouped by purpose in the source).

| # | Service | Subdomain | URL | Host | Status |
|---|---------|-----------|-----|------|--------|
| 1 | traefik | traefik | `https://traefik.kogler.si` | oldsrv | enabled |
| 2 | crowdsec | crowdsec | `https://crowdsec.kogler.si` | oldsrv | enabled |
| 3 | authentik | sso | `https://sso.kogler.si` | oldsrv | enabled |
| 4 | opencloud | file | `https://file.kogler.si` | oldsrv | enabled |
| 5 | immich-app | foto | `https://foto.kogler.si` | oldsrv | enabled |
| 6 | forgejo | git | `https://git.kogler.si` | oldsrv | enabled |
| 7 | ollama | ollama | `https://ollama.kogler.si` | oldsrv | enabled |
| 8 | immich-ml | immich-ml | `https://immich-ml.kogler.si` | oldsrv | enabled |
| 9 | technitium | dns | `https://dns.kogler.si` | oldsrv | enabled (oldsrv only) |
| 10 | pihole | ad | `https://ad.kogler.si` | oldsrv | enabled |
| 11 | raspberrymatic-standby (standby) | raspberrymatic | `https://raspberrymatic.kogler.si` | oldsrv | enabled (oldsrv only) |
| 12 | home-assistant-standby | home-assistant-standby | `https://home-assistant-standby.kogler.si` | oldsrv | enabled (oldsrv only) |
| 13 | headscale | vpn | `https://vpn.kogler.si` | oldsrv | enabled |
| 14 | kopia-server | kopia-server | `https://kopia-server.kogler.si` | oldsrv | enabled |
| 15 | db-backup | db-backup | `https://db-backup.kogler.si` | oldsrv | enabled |
| 16 | grafana | stats | `https://stats.kogler.si` | oldsrv | enabled |
| 17 | n8n | auto | `https://auto.kogler.si` | oldsrv | enabled |
| 18 | homepage | home | `https://home.kogler.si` | oldsrv | enabled |
| 19 | metabase | sec | `https://sec.kogler.si` | oldsrv | enabled |
| 20 | blackbox-exporter | blackbox-exporter | `https://blackbox-exporter.kogler.si` | oldsrv | enabled |
| 21 | loki | loki | `https://loki.kogler.si` | oldsrv | enabled |
| 22 | prometheus | prometheus | `https://prometheus.kogler.si` | oldsrv | enabled |
| 23 | signal-cli-rest-api | signal-cli-rest-api | `https://signal-cli-rest-api.kogler.si` | oldsrv | enabled |
| 24 | dozzle | logs | `https://logs.kogler.si` | oldsrv | enabled |
| 25 | sunshine | sunshine | `https://sunshine.kogler.si` | oldsrv | enabled (desktop mode) |
| 26 | matrix | matrix | `https://matrix.kogler.si` | oldsrv | enabled |
| 27 | chat | chat | `https://chat.kogler.si` | oldsrv | enabled |
| 28 | jellyfin | media | `https://media.kogler.si` | oldsrv | enabled |
| 29 | seerr | seerr | `https://seerr.kogler.si` | oldsrv | enabled |
| 30 | sonarr | sonarr | `https://sonarr.kogler.si` | oldsrv | enabled |
| 31 | radarr | radarr | `https://radarr.kogler.si` | oldsrv | enabled |
| 32 | lidarr | lidarr | `https://lidarr.kogler.si` | oldsrv | enabled |
| 33 | prowlarr | prowlarr | `https://prowlarr.kogler.si` | oldsrv | enabled |
| 34 | bazarr | bazarr | `https://bazarr.kogler.si` | oldsrv | enabled |
| 35 | sabnzbd | sab | `https://sab.kogler.si` | oldsrv | enabled |
| 36 | qbittorrent | torrent | `https://torrent.kogler.si` | oldsrv | enabled |
| 37 | profilarr | profilarr | `https://profilarr.kogler.si` | oldsrv | enabled |
| 38 | recyclarr | recyclarr | `https://recyclarr.kogler.si` | oldsrv | enabled |
| 39 | renovate | renovate | `https://renovate.kogler.si` | oldsrv | enabled |
| 40 | doco-cd | doco-cd | `https://doco-cd.kogler.si` | oldsrv | enabled |

---

> Generated from `docker_services` list | oldsrv | 2025-08-15T01:00:00Z