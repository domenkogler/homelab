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

> **Status: 🟢 live on oldsrv** — Jellyfin, Seerr/SeerrNG, Sonarr/Radarr/Lidarr/Prowlarr/Bazarr,
> Profilarr (+parser), Recyclarr, immich-ML, and the music-acquisition pillar (§Music Pillar), with the NFS
> mounts to nas live (`/mnt/nas/media`, `/mnt/nas/data`, `/mnt/nas/thumbs`). Streaming/immich-app run on the
> VPS; the **music library** lives on the Hetzner Storage Box.
> ⏳ **Open:** immich's whole-collection ML import (a separate task), and Tube Archivist, which is
> **disabled** until its Elasticsearch `path.repo` problem is fixed (§Music Pillar).
>
> ✅ **Immich SSO is live 2026-09-25** (`foto.kogler.si` → Authentik). The settings are NOT compose env:
> Immich v3 has no OAuth env vars, so `roles/docker_services/tasks/immich-seed.yml` PUTs them into the
> service's own database config (proof + the six-week autopsy of the inert env block:
> [deployment-oidc.md](deployment-oidc.md) §Immich). ⚠ Consequence still open: the only assets live on
> the native `admin` seat while the new SSO seat is empty — **HD-457**.

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
| Aurral | aurral | I | 100–200 / 400 | Music discovery + Lidarr-request companion (lklynet/aurral, HD-362) — community radio via Last.fm / ListenBrainz; **free/no sub**; internal-only; own login |
| Orpheusdl (manual) | — | host/laptop | — | **Not in IaC:** orpheusdl is a pip CLI with no container — run on the LAPTOP on demand for paid-source FLAC; not part of the automated ladder |
| Lidarr-URL-DL | url-dl | I | 150–300 / 500 | Lidarr-YouTube-Downloader (angrido/lidarr-downloader, HD-362) — acquisition **#3**: YouTube → Lidarr (Newznab + SABnzbd emulation, yt-dlp + PO-token sidecar), up to 320 kbps MP3/M4A/Opus; internal-only UI |
| Slskd | slskd | I | 60–140 / 250 | Soulseek P2P daemon (slskd/slskd, HD-362) — **gluetun WireGuard sidecar, VPN-locked egress**, acquisition **#2**; no inbound port → fetch-only peer (search + download, no upload credit); own login/token |
| Tube Archivist | tube | I | 300–700 / 1200 | Personal YouTube (bbilly1/tubearchivist + ES + redis, HD-362) — headless yt-dlp (bundled), channel/playlist subs, **no Google account**; internal-only; own login · **new `tube` subdir on nas `bulk/media`** · needs `vm.max_map_count` · **⏳ disabled** — ES `path.repo` problem, see §Music Pillar
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
│   └── (no `music/` — the music library lives on the Hetzner Storage Box as Navidrome's primary, see §Navidrome)
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
- **Auth:** *arr / downloader UIs (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Profilarr, SABnzbd, qBittorrent) = **built-in Forms auth** on the home edge (deliberate reversal of the old "Authentik Forward-Auth, built-in logins disabled" — that served only while WAN/VPS is up; the home edge must survive WAN-out, so each admin tool owns its credentials). Jellyfin + Seerr + SeerrNG = **local login only** (client apps / family request portal would break under forward-auth; Jellyfin SSO dropped — SSO accounts can't fall back to local). API integration between the *arr (Prowlarr↔Sonarr/Radarr, Seerr↔*arr) keeps using API keys, unaffected by UI auth. Dozzle (observability) is also Forward-Auth — see [`observability.md`](observability.md).
- **Request middleware identity:** Seerr / SeerrNG log in via **Jellyfin** (user/password validated by the Jellyfin API — home-local, works offline, no Authentik). SeerrNG (snapetech/seerrng) is a Seerr fork adding **music** — runs alongside Seerr for now (both point at the same Sonarr/Radarr backends); **books/Readarr dropped** (Readarr effectively unmaintained).
- **FlareSolverr: deferred** — only if an indexer actually requires Cloudflare bypass.
- All *arr subdomains are **internal-only** (not in the public set).

| App | Web UI | Auth | Notes |
|-----|--------|------|-------|
| Jellyfin | `media.` | own login (local only) | transcode via Intel HD 630 `/dev/dri` |
| Seerr | `seerr.` | Jellyfin login | family request portal (movies/TV) |
| SeerrNG | `seerrng.` | Jellyfin login | Seerr fork + music (snapetech/seerrng); alongside Seerr |
| Aurral | `aurral.` | own login | discovery + Lidarr requests (Last.fm / ListenBrainz history, free) — internal-only |
| Lidarr-URL-DL | `url-dl.` | own login | YouTube → Lidarr download client (Angrido) — #3 priority |
| Slskd | `slskd.` | own login/token | Soulseek P2P — gluetun sidecar, VPN-locked egress, #2 priority |
| Tube Archivist | `tube.` | own login | personal YouTube — internal-only; headless yt-dlp |
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

## Music Pillar — acquisition + discovery (HD-362)

> **Status: 🟢 live on oldsrv** — slskd + its gluetun/PrivadoVPN sidecar healthy, aurral up,
> `lidarr-ydl` up and healthy. **Tube Archivist is disabled** (row `enabled: false`) — see the two gotchas
> below; re-enabling means fixing ES first.
>
> The shape of this pillar: **oldsrv downloads and manages, the VPS serves** (Navidrome, HD-354). All **P2P**
> egress (slskd + qBittorrent) goes through the **shared gluetun WireGuard → PrivadoVPN**; **SABnzbd stays on
> the plain LAN** — usenet does not need the VPN and sharing a tunnel with torrents couples two risk sets.
>
> Two implementation traps this stack taught, both generic:
> - **An image with a read-only layer may have no writable appuser home.** `lidarr-ydl` crash-looped FATAL on
>   `/home/appuser/.profile` `EACCES`; the fix is a durable host bind at `/home/appuser`, not a chmod inside
>   the image. Same class: aurral needed `/app/downloads` durable-bound or its weekly playlist fails.
> - **Elasticsearch `path.repo` must be set in `elasticsearch.yml`, never by env or `-E`.** Tube Archivist
>   requires ES snapshot support to serve; `path.repo:` in the compose env **derails ES config generation**,
>   and passing it as `-E path.repo=…` re-boot-straps unstably on the data volume — which presented as
>   constant CPU + alternating RAM on the host. Apply it inside the ES container's `elasticsearch.yml`
>   **before** re-enabling the row. (TA's own stack also needed `ES_DISABLE_VERIFY_SSL` with an https
>   `ES_URL`, redis running with `DAC_OVERRIDE`, and a reset ES data volume; its secret is the
>   `tube-archivist-es` vault item, used as `ELASTIC_PASSWORD` on both sides.)

- **Acquisition chain (ALL on oldsrv):**
  - **Lidarr** (existing) → manages the FLAC library in `bulk/media/music` (nas) — copy-import to the
    Box per HD-354; **sees usenet (SABnzbd) as priority #1, then Soulseek (slskd, #2), then YouTube
    (lidarr-ydl, #3)** (owner-set ladder).
  - **orpheusdl** — manual LAPTOP pip tool (no container; owner runs it on demand for paid-source
    FLAC. NOT in IaC — the automated ladder covers it).
  - **slskd** — Soulseek P2P daemon (Soulseek account, free): **gluetun WireGuard sidecar** (same tunnel as
    qBittorrent), **no inbound port → fetch-only** (search + download; no upload credit). Router rate-limit
    **10 MB/s per P2P service** (both slskd + torrent, owner decision). Acquisition **#2**.
  - **lidarr-ydl** — Lidarr-YouTube-Downloader (Angrido): YouTube search → Lidarr import, **#3**.
  - **Murglar** — stays a **manual device app** (Android/Desktop; it is a client with **no API**, per
    `Music stack.md` it's removed from the chain — it just downloads to the phone, never auto-triggers).
  - **Aurral** — **music discovery** companion (lklynet/aurral, free): **Last.fm / ListenBrainz** login history
    → recommends artists/albums → sends requests to **Lidarr**, which lands them in the same FLAC chain.
- **Video pillar (separate, HD-361 later):** Tube Archivist (personal YouTube) is an oldsrv service,
  currently **disabled** (see the gotchas above); Jellyfin keeps serving TV/movies. Plex/StreamFab/YTDLNis
  stay **manual / not-IaC** by owner choice — Tube Archivist is the headless yt-dlp piece of that set.
- **Auth:** Aurral / Tube Archivist / Slskd = **own local logins** (same home-edge pattern — *arr UIs use
  built-in Forms auth); no Forward-Auth. `lidarr_api` token = the Lidarr instance key — **placeholder value**, overwrite with the real `config.xml` ApiKey (see deployment-secrets.md).
- **Storage:** Tube Archivist lives in a **`bulk/media/tube` subdir** on nas (same `bulk/media` dataset
  so TRaSH-style hardlink compose stays valid). Music files stay in `bulk/media/music` (existing).
- *****arr ←? downloader wiring:***** Prowlarr (existing) points at SABnzbd + qBittorrent for Lidarr;
  slskd + lidarr-ydl are **standalone download clients** (slskd has no indexer; lidarr-ydl registers as
  a Newznab indexer + SABnzbd emulating client inside Lidarr). SeerrNG stays the music-request UI on top
  of the same Lidarr (HD-353).

## Related
- [Downloads stack](services-downloads.md) — SABnzbd / qBittorrent / gluetun ingress
- [Services index](services.md) — catalog legend + network/subdomain SSOT
- [Store](storage.md) — ZFS layout, `bulk/media` dataset
- [Media stack redefined brainstorm](../brainstorming/Media stack redefined.md) — source vision (music pillar)