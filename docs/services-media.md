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
| SeerrNG | seerrng | P+I | 150–250 / 400 | Music-capable Seerr fork (snapetech/seerrng, HD-353) — own Jellyfin login; runs alongside Seerr (same Sonarr/Radarr backends) |
| Sonarr | sonarr | P+I | 120–180 / 250 | TV series management (linuxserver) |
| Radarr | radarr | P+I | 140–200 / 300 | Movie management (linuxserver) |
| Lidarr | lidarr | P+I | 90–140 / 200 | Music management (linuxserver) |
| Prowlarr | prowlarr | P+I | 70–120 / 180 | Indexer registry shared by all *arr |
| Bazarr | bazarr | P+I | 80–150 / 250 | Subtitle management (connects to Sonarr/Radarr) |
| Profilarr | profilarr | P+I | 50–100 / 150 | Quality-profile UI on top of Sonarr/Radarr |
| Navidrome | music | P+I | 100–250 / 400 | Music server (deluan/navidrome, HD-354) — **on the VPS**, library on the Hetzner Storage Box; Subsonic + web UI |
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
│   └── ~~music/~~ *(2026-09-10: music library moved to the Hetzner Storage Box as Navidrome's primary — see below)*
└── downloads/                    # transient scratch (hardlink-import → media/, then prune)
    ├── incomplete/{usenet,torrent}
    └── complete/{movies,tv,music}   # TRaSH per-category (SABnzbd / qBittorrent save paths)
```

- **Three NFS exports:** `bulk/media` → oldsrv **`/mnt/nas/media`** (the *arr share), `tank/data` →
  `/mnt/nas/data` (immutable user data) and `bulk/data/immich-thumbs` → `/mnt/nas/thumbs` (push target) —
  two pools, three exports.
- **Import = hardlink** for **movies/TV** (Sonarr/Radarr: `Use Hardlinks` ON) — instant, zero-space, atomic. **Music** is the **Lidarr → copy-import** exception (HD-354): the music library lives on the Hetzner Storage Box as Navidrome's primary, and hardlinks can't cross hosts — so Lidarr **copies** music (2× temporary space accepted), then the Box refresh picks it up. `docs/storage.md` §Store tiering owns the layout.
- **Media is not backed up** (movies/TV) — no sanoid snapshots, no syncoid, no Kopia; lost media is re-fetched via
  usenet/torrents. **Music is the exception**: the library lives on the live Box (cold/bulk tier, box-side + Kopia
  coverage per [`storage.md`](storage.md)).
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

## Navidrome (music.kogler.si) — VPS + Storage Box (HD-354)

- **Placement:** on the **VPS** (reliable tier) with **app + data together** — library on the live Hetzner
  Storage Box (`/mnt/storagebox/music`, CIFS via the `cifs` role), app data + SQLite on VPS NVMe
  (`/srv/docker/navidrome/data`, Kopia-backed). Home-independent by design (music survives WAN-out scenes
  via the VPS edge / WG bridge; data is offsite).
- **Auth:** local logins retained (break-glass + Subsonic clients); the web UI **SSO via Authentik is
  optional** (deploy-gated) — `/rest/*` stays local for Subsonic clients (Symfonium, play:Sub).
- **Clients:** any Subsonic-compatible app; web at `music.kogler.si` (internal/tailnet — no public record).
- **Import path:** Lidarr on oldsrv → **copy-import** (hardlinks can't cross hosts once the library is on the
  Box); `docs/storage.md` owns the tiering/consequence line.

## Related
- [Downloads stack](services-downloads.md) — SABnzbd / qBittorrent / gluetun ingress
- [Services index](services.md) — catalog legend + network/subdomain SSOT
- [Store](storage.md) — ZFS layout, `bulk/media` dataset