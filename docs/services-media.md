---
title: Media Stack — Photos, *arr & Streaming
role: detail
domain: services
status: active
tags: [services, media, arr, photos, streaming]
---
# Media Stack — Photos, *arr & Streaming

> **Role:** Detail — the media/photo slice of the services stack: Jellyfin + Seerr streaming, Immich photos, and the *arr management pipeline.
> **Links to:** `services-downloads.md`, `services-authentik.md`, `services-traefik.md`, `storage.md`, `observability.md`
> **Linked from:** `services.md`, `storage.md`

> 🟢 **IaC done, not yet live — ⏳ deploy-gated.** Media services are IaC-authored but **not live**; deploy-gated against `deployment-tasks.md`. Hosts (`oldsrv`, `nas`) are not provisioned.

---

## Catalog

Subdomains are relative to `kogler.si` (no port, no suffix). Network codes (`P/I/D/W`, `host`): see [Docker Networks](services.md#docker-networks). Exposure: see the [Domain & Subdomain Plan](services.md#domain-subdomain-plan) in `services.md`.

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| Jellyfin | media | P+I | 250–400 / +150–350 per stream | Media server — **Intel HD 630 iGPU** QuickSync transcode, own login |
| Immich | foto | I | 600–1,000 / 2,000 | Photo management, mobile apps (app+postgres+valkey — microservices merged into server in v3). **Originals on live Box (CIFS), docs/DB local** (HD-131 D1/D3). **Auth (HD-148): native OIDC → Authentik** (web + mobile `app.immich:///oauth-callback`); client via Blueprint + glue |
| Seerr | seerr | P+I | 150–250 / 400 | Request portal (seerr.dev, `seerr/seerr`) — own login, Jellyfin/Plex/Emby |
| Sonarr | sonarr | P+I | 120–180 / 250 | TV series management (linuxserver) |
| Radarr | radarr | P+I | 140–200 / 300 | Movie management (linuxserver) |
| Lidarr | lidarr | P+I | 90–140 / 200 | Music management (linuxserver) |
| Prowlarr | prowlarr | P+I | 70–120 / 180 | Indexer registry shared by all *arr |
| Bazarr | bazarr | P+I | 80–150 / 250 | Subtitle management (connects to Sonarr/Radarr) |
| Profilarr | profilarr | P+I | 50–100 / 150 | Quality-profile UI on top of Sonarr/Radarr |
| Recyclarr | — | I | 40–80 / 200 | TRaSH custom formats + quality profiles sync (scheduled, no UI) |

## Storage & Import (Media / *arr)

Media lives on the nas **`bulk`** pool (RAIDZ2) in a single dataset — `bulk/media` — because TRaSH
hardlinks between `downloads/` and `media/` require a **single filesystem** (ZFS hardlinks can't cross
dataset boundaries). Full layout/properties/replication: [`storage.md`](storage.md).

```
bulk/media/                       # ONE dataset — ACTIVE library, NOT backed up (redownloadable)
├── media/
│   ├── movies/
│   ├── tv/
│   └── music/
└── downloads/                    # transient scratch (hardlink-import → media/, then prune)
    ├── incomplete/{usenet,torrent}
    └── complete/{movies,tv,music}   # TRaSH per-category (SABnzbd categories / qBittorrent save paths)
```

- **Three NFS exports:** `bulk/media` → oldsrv **`/mnt/nas/media`** (the *arr share), `tank/data` →
  `/mnt/nas/data` (immutable user data) and `bulk/data/immich-thumbs` → `/mnt/nas/thumbs` (push target) —
  two pools, three exports.
- **Import = hardlink** (Sonarr/Radarr/Lidarr: `Use Hardlinks` ON) — instant, zero-space, atomic.
- **Media is not backed up** — no sanoid snapshots, no syncoid, no Kopia. Lost media is re-fetched via
  usenet/torrents. (Ingress = [`services-downloads.md`](services-downloads.md), TRaSH categories.)
- **Owner = neutral shared owner `storage_uid`/`storage_gid` (`media`, 1005)** across all *arr containers
  (linuxserver `PUID/PGID={{ storage_uid }}`/`PGID={{ storage_gid }}`; Jellyfin `user: "{{ storage_uid }}:{{ storage_gid }}"`,
  HD-94/HD-131). SMB/NFS ownership on nas must match.
- **Auth:** admin UIs (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Profilarr) = Authentik Forward-Auth,
  built-in logins disabled. Jellyfin + Seerr = own login (client apps / family request portal would break
  under forward-auth). Dozzle (observability) is also Forward-Auth — see [`observability.md`](observability.md).
- **FlareSolverr: deferred** — only if an indexer actually requires Cloudflare bypass.
- All *arr subdomains are **internal-only** (not in the public set).

| App | Web UI | Auth | Notes |
|-----|--------|------|-------|
| Jellyfin | `media.` | own login | transcode via Intel HD 630 `/dev/dri` |
| Seerr | `seerr.` | own login | family request portal |
| Sonarr/Radarr/Lidarr/Prowlarr/Bazarr/Profilarr | `<name>.` | Forward-Auth | linuxserver images |
| Immich | `foto.` | own login / OIDC | photos above |

## Related
- [Downloads stack](services-downloads.md) — SABnzbd / qBittorrent / gluetun ingress
- [Services index](services.md) — catalog legend + network/subdomain SSOT
- [Store](storage.md) — ZFS layout, `bulk/media` dataset