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

> 🟢 **LIVE 2026-09-08 (oldsrv Phase-3 converge)** — Jellyfin, Seerr, sonarr/radarr/lidarr/prowlarr/bazarr, profilarr(+parser), recyclarr, immich-ml all Up + healthy on oldsrv; NFS mounts to nas live (`/mnt/nas/media`, `/mnt/nas/data`, `/mnt/nas/thumbs`). immich-ml bundled-ROCm ready for the whole-collection import (separate later task).

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
- **Auth (decided 2026-09-10):** *arr / downloader UIs (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Profilarr, SABnzbd, qBittorrent) = **built-in Forms auth** on the home edge (deliberate reversal of the old "Authentik Forward-Auth, built-in logins disabled" — that served only while WAN/VPS is up; the home edge must survive WAN-out, so each admin tool owns its credentials). Jellyfin + Seerr + SeerrNG = **local login only** (client apps / family request portal would break under forward-auth; Jellyfin SSO dropped — SSO accounts can't fall back to local). API integration between the *arr (Prowlarr↔Sonarr/Radarr, Seerr↔*arr) keeps using API keys, unaffected by UI auth. Dozzle (observability) is also Forward-Auth — see [`observability.md`](observability.md).
- **Request middleware identity:** Seerr / SeerrNG log in via **Jellyfin** (user/password validated by the Jellyfin API — home-local, works offline, no Authentik). SeerrNG (snapetech/seerrng) is a Seerr fork adding **music** — runs alongside Seerr for now (both point at the same Sonarr/Radarr backends); **books/Readarr dropped** (Readarr effectively unmaintained).
- **FlareSolverr: deferred** — only if an indexer actually requires Cloudflare bypass.
- All *arr subdomains are **internal-only** (not in the public set).

| App | Web UI | Auth | Notes |
|-----|--------|------|-------|
| Jellyfin | `media.` | own login (local only) | transcode via Intel HD 630 `/dev/dri` |
| Seerr | `seerr.` | Jellyfin login | family request portal (movies/TV) |
| SeerrNG | `seerrng.` | Jellyfin login | Seerr fork + music (snapetech/seerrng); alongside Seerr |
| Sonarr/Radarr/Lidarr/Prowlarr/Bazarr/Profilarr | `<name>.` | built-in Forms auth (home edge) | linuxserver images; API keys for integration |
| Sabnzbd/Qbittorrent | `sab.`/`torrent.` | built-in Forms auth | downloads (qbitorrent through gluetun) |
| Navidrome | `music.` | **VPS** (SSO web UI optional + local) | music server — library on Storage Box (moved off nas) |
| Immich | `foto.` | OIDC → Authentik | photos (VPS) |

## Related
- [Downloads stack](services-downloads.md) — SABnzbd / qBittorrent / gluetun ingress
- [Services index](services.md) — catalog legend + network/subdomain SSOT
- [Store](storage.md) — ZFS layout, `bulk/media` dataset