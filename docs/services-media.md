---
title: Media Stack — Photos, *arr & Streaming
role: detail
domain: services
status: active
sensitivity: infra
tags: [services, media, arr, photos, streaming]
---
# Media Stack — Photos, *arr & Streaming

> **Role:** Detail — the media/photo slice of the services stack: Jellyfin + Seerr streaming, Immich photos, and the *arr management pipeline.
> **Links to:** `services-downloads.md`, `services-authentik.md`, `services-traefik.md`, `storage.md`, `observability.md`
> **Linked from:** `services.md`, `storage.md`

> **Status: 🟢 live on oldsrv** — Jellyfin, Seerr/SeerrNG, Sonarr/Radarr/Lidarr/Prowlarr/Bazarr,
> Profilarr (+parser), Recyclarr, immich-ML, and the music-acquisition pillar (§Music Pillar), with the NFS
> mounts to nas live (`/mnt/nas/media`, `/mnt/nas/data`, `/mnt/nas/thumbs`). Streaming/immich-app run on the
> VPS; the **music FLAC master** lives on the NAS (`bulk/media/media/music`) and the Hetzner Storage Box
> holds Navidrome's serving copy.
> ⏳ **Open:** immich's whole-collection ML import (a separate task), and Tube Archivist, which is
> **disabled** until its Elasticsearch `path.repo` problem is fixed (§Music Pillar).
> ⚠ **SABnzbd is unreachable by anything in this stack unless its `host_whitelist` names the caller** —
> the shipped default holds only the container id, so the UI answers "Hostname verification failed" and a
> Prowlarr client at `sabnzbd:8080` cannot be saved. Owned by `tasks/sabnzbd-seed.yml`; the details are in
> [services-downloads.md](services-downloads.md) §SABnzbd's own door.
> ⏳ **Prowlarr holds 0 indexers and 0 synced apps, so no request can be searched end-to-end** — the
> request half of this stack is live (§Request → import wiring) and the acquisition half is not.
>
> ✅ **Recyclarr `@daily` sync verified on the box (HD-318(b), 2026-10-18)** — image 8.7.2, `Up 9 days`
> (`StartedAt` 2026-10-08T17:24:54Z, `RestartCount=0`); ten consecutive fires `iteration=0`…`9` (00:00 local,
> 2026-10-09→18), each processing **both** configured instances `radarr-homelab` + `sonarr-homelab`, zero
> `[ERR]`/`[WRN]` lines; `/config` carries the image's own uid 1000, and the date the sync actually landed is
> **2026-09-28** (fix `5dbe85a6`) — the 2026-09-15 `bind_owner_uid` sweep set 1005, so every run before it died
> on `Access to the path '/config/cache' is denied`. It authenticates and ships nothing, by ruling (§Catalog):
> both instances' `state/*/*-mappings.json` are `{"mappings": []}`. ⚠ Two traps: `recyclarr sync` **exits 0 even
> when it skips every config**, so only log lines and the `state/` mtimes are evidence (an `Up` container proves
> nothing); and **Lidarr is not a configured instance** — no `lidarr:` block in `recyclarr.yml`, no
> `state/lidarr/` — so this service has never touched Lidarr.
> ✅ **Immich SSO is live** (`foto.kogler.si` → Authentik). The settings are NOT compose env:
> Immich v3 has no OAuth env vars, so `roles/docker_services/tasks/immich-seed.yml` PUTs them into the
> service's own database config (why an env block is inert:
> [deployment-oidc.md](deployment-oidc.md) §Immich). ⚠ Open: the only assets live on the native `admin`
> seat while the SSO seat is empty.

---

## Catalog

Subdomains are relative to `kogler.si` (no port, no suffix). Network codes (`P/I/D/W`, `host`): see [Docker Networks](services.md#docker-networks). Exposure: see the [Domain & Subdomain Plan](services.md#domain-subdomain-plan) in `services.md`.

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| Jellyfin | media | P+I | 250–400 / +150–350 per stream | Media server — **Intel HD 630 iGPU** QuickSync transcode, own login |
| Immich | foto | I | 600–1,000 / 2,000 | Photo management, mobile apps (app+postgres+valkey — microservices merged into server in v3). **Originals on live Box (CIFS), docs/DB local**. **Auth: native OIDC → Authentik** (web + mobile `app.immich:///oauth-callback`); client via Blueprint + glue |
| Seerr | seerr | P+I | 150–250 / 400 | Request portal (seerr.dev, `seerr/seerr`) — own login, Jellyfin/Plex/Emby |
| SeerrNG | seerrng | P+I | 150–250 / 400 | Music-capable Seerr fork (snapetech/seerrng) — own Jellyfin login; runs alongside Seerr (same Sonarr/Radarr backends) |
| Sonarr | sonarr | P+I | 120–180 / 250 | TV series management (linuxserver) |
| Radarr | radarr | P+I | 140–200 / 300 | Movie management (linuxserver) |
| Lidarr | lidarr | P+I | 90–140 / 200 | Music management (linuxserver) |
| Prowlarr | prowlarr | P+I | 70–120 / 180 | Indexer registry shared by all *arr |
| Bazarr | bazarr | P+I | 80–150 / 250 | Subtitle management (connects to Sonarr/Radarr) |
| Profilarr | profilarr | P+I | 50–100 / 150 | Quality-profile UI on top of Sonarr/Radarr |
| Navidrome | music | P+I | 100–250 / 400 | Music server (deluan/navidrome) — **on the VPS**, library on the Hetzner Storage Box; Subsonic + web UI |
| Aurral | aurral | I | 100–200 / 400 | Music discovery + Lidarr-request companion (lklynet/aurral) — community radio via Last.fm / ListenBrainz; **free/no sub**; internal-only; own login |
| Orpheusdl (manual) | — | host/laptop | — | **Not in IaC:** orpheusdl is a pip CLI with no container — run on the LAPTOP on demand for paid-source FLAC; not part of the automated ladder |
| Lidarr-URL-DL | lidarr-ydl | I | 150–300 / 500 | Lidarr-YouTube-Downloader (angrido/lidarr-downloader) — acquisition **#3**: YouTube → Lidarr (Newznab + SABnzbd emulation, yt-dlp + PO-token sidecar), up to 320 kbps MP3/M4A/Opus; internal-only UI |
| Slskd | slskd | I | 60–140 / 250 | Soulseek P2P daemon (slskd/slskd) — **gluetun WireGuard sidecar, VPN-locked egress**, acquisition **#2**; no inbound port → fetch-only peer (search + download, no upload credit); own login |
| Tube Archivist | tube | I | 300–700 / 1200 | Personal YouTube (bbilly1/tubearchivist + ES + redis) — headless yt-dlp (bundled), channel/playlist subs, **no Google account**; internal-only; own login · `tube` subdir on nas `bulk/media` · needs `vm.max_map_count` · **⏳ disabled** — ES `path.repo` problem, see §Music Pillar
| Recyclarr | — | I | 40–80 / 200 | TRaSH custom formats + quality profiles sync (`@daily` inside the container, no UI) — the **service runs**; the **quality-profile policy ships nothing**, by ruling: the `quality_definition:` block stays commented because enabling it rewrites the live Radarr/Sonarr profiles, and the ruled position is that this stays off — a later yes is a new decision, never drift: [deployment-secrets.md](deployment-secrets.md) §the `sonarr_api`/`radarr_api` rows |

## Storage & Import (Media / *arr)

Media lives on the nas **`bulk`** pool (RAIDZ2) in a single dataset — `bulk/media` — because TRaSH
hardlinks between `downloads/` and `media/` require a **single filesystem** (ZFS hardlinks can't cross
dataset boundaries). Full layout/properties/replication: [`storage.md`](storage.md).

```
bulk/media/                       # ONE dataset — ACTIVE library; the movies/TV tier is NOT backed up (redownloadable)
├── media/
│   ├── movies/
│   ├── tv/
│   └── music/                    # the FLAC MASTER — backed up (Kopia) + pushed to the Box as Navidrome's serving copy, see §Navidrome
└── downloads/                    # transient scratch (hardlink-import → media/, then prune)
    ├── incomplete/{usenet,torrent}
    └── complete/{movies,tv,music}   # TRaSH per-category (SABnzbd / qBittorrent save paths)
```

- **Three NFS exports:** `bulk/media` → oldsrv **`/mnt/nas/media`** (the *arr share), `tank/data` →
  `/mnt/nas/data` (immutable user data) and `bulk/data/immich-thumbs` → `/mnt/nas/thumbs` (push target) —
  two pools, three exports.
- **Import = hardlink** for **movies/TV** (the switch is `copyUsingHardlinks` in `mediamanagement` — `true` in all three arrs; current builds no longer expose a "Use Hardlinks" toggle, so look for the key, not the label) — instant, zero-space, atomic. **Music** is the exception, and its leg **does not exist yet**: Lidarr's root is `/media/music` = nas `bulk/media/media/music` (empty), and neither oldsrv nor the NAS can write the Box — `roles/cifs/tasks/main.yml` asserts the Box mount onto the **VPS only**, and `mount | grep cifs` on oldsrv shows nothing, so a "Lidarr copies music to the Box" path has no mount behind it. The shape: **NAS master + a push leg to the Box**, and the push is **`oldsrv` → Box rsync/SFTP over `:23`** — no new mount, so the VPS-only `cifs` assert stays; the mount assert and a bounded `--max-delete` are part of the requirement, not advice (a dead mount is an empty directory, and an empty directory is what Navidrome will serve). Retention stays an owner call: neither copy is inside Kopia's scope. `docs/storage.md` §Service ↔ Storage Placement owns the layout.
- **Movies/TV media are not backed up** — no sanoid snapshots, no syncoid, no Kopia; lost media is re-fetched via
  usenet/torrents. **Music is the exception, and it is backed up:** the FLAC master (`bulk/media/media/music`)
  is a Kopia source of the oldsrv agent — its own guarded snapshot line, encrypted and retention-managed on the
  **backup** box (`kopia_sftp_host`, a different server from the live Box) — while the live Box holds the *serving*
  copy. A Soulseek FLAC is not re-fetchable the way a movie is, which is why this tree is not folded back into the
  unbacked media tier. Neither sanoid nor syncoid covers it: sanoid names **datasets** and the master is a
  directory inside `bulk/media` ([storage.md](storage.md) §Snapshot & Replication).
- **Owner = neutral shared owner `storage_uid`/`storage_gid` (`media`, 1005)** across all *arr containers
  (linuxserver `PUID/PGID={{ storage_uid }}`/`PGID={{ storage_gid }}`; Jellyfin `user: "{{ storage_uid }}:{{ storage_gid }}"`).
  SMB/NFS ownership on nas must match.
- **Auth:** *arr / downloader UIs (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Profilarr, SABnzbd, qBittorrent) = **built-in Forms auth** on the home edge — the home edge must survive WAN-out, so each admin tool owns its credentials. Jellyfin + Seerr + SeerrNG = **local login only** (client apps / family request portal would break under forward-auth). API integration between the *arr (Prowlarr↔Sonarr/Radarr, Seerr↔*arr) keeps using API keys, unaffected by UI auth. Dozzle (observability) is also Forward-Auth — see [`observability.md`](observability.md).
- **Request middleware identity:** Seerr / SeerrNG log in via **Jellyfin** (user/password validated by the Jellyfin API — home-local, works offline, no Authentik). SeerrNG (snapetech/seerrng) is a Seerr fork adding **music** — runs alongside Seerr (both point at the same Sonarr/Radarr backends). No books/Readarr tier.
- **FlareSolverr: deployed** (`flaresolverr`, overlay-only, no UI/publish) — the CF-challenge gate for indexers such as 1337x.to. Wiring + evidence: [services-downloads.md](services-downloads.md)
  §The solver's own door; the manual step is [deployment-manual.md](../deployment-manual.md) §P3.6.
- All *arr subdomains are **internal-only** (not in the public set).
- **How to reach it from anywhere:** the three names are answered **per
  Technitium instance** — the home instances return `oldsrv_home_ip` (the home edge serves all three), the VPS
  primary returns `dns_primary_ip` — and the VPS edge **routes** `media` / `seerr` / `seerrng` to the home
  edge over WG S2S, so both answers lead to a served URL instead of a 404. `media.kogler.si` is **published
  publicly** (Cloudflare CNAME → the VPS, `public: true` in the zone list) and
  carries `crowdsec-only@file`, not Forward-Auth: client apps (Shield/Android TV) cannot sit behind an Authentik
  dance. `seerr`/`seerrng` are routed there but **unpublished** — reachable by name where a resolver is told.
  The Media VLAN (50 — the Shield and the TV) uses a home-first DHCP chain via
  `network_vlans[].lan_first_dns`. Probes: `--resolve media.kogler.si:443:<VPS IP>` → `302 →
  /web/` and `/System/Info/Public` returns Jellyfin JSON through the two hops; the same URL family on the home
  edge → `302`. Mechanics in [services-traefik.md](services-traefik.md) §The home-hosted names at the public
  edge; the split-horizon reasoning in [network-dns.md](network-dns.md) §Per-Instance Split-Horizon.
- **`http://` works:** `curl -I http://media.kogler.si/` → `301` and `http://foto.kogler.si/` → `301` on
  both edges, so the Android-TV connect wizard's default `http://` form finds the server. A v2-style
  `HostRegexp(`{host:.+}`)` redirect rule parses and reports `enabled` while matching nothing, and an edge that
  references a middleware it never declared fails the same way silently — read
  [services-traefik.md](services-traefik.md) §The `:80 → :443` redirect… before adding another redirect router.

| App | Web UI | Auth | Notes |
|-----|--------|------|-------|
| Jellyfin | `media.` | own login (local only) | transcode via Intel HD 630 `/dev/dri` |
| Seerr | `seerr.` | Jellyfin login | family request portal (movies/TV) |
| SeerrNG | `seerrng.` | Jellyfin login | Seerr fork + music (snapetech/seerrng); alongside Seerr |
| Aurral | `aurral.` | own login | discovery + Lidarr requests (Last.fm / ListenBrainz history, free) — internal-only |
| Lidarr-URL-DL | `lidarr-ydl.` | own login | YouTube → Lidarr download client (Angrido) — #3 priority, **audio only** |
| Slskd | `slskd.` | own login `slskd` + password (`soulseek_api`; 0.26 has **no token** option) | Soulseek P2P — gluetun sidecar, VPN-locked egress, #2 priority |
| Tube Archivist | `tube.` | own login | personal YouTube — internal-only; headless yt-dlp |
| Sonarr/Radarr/Lidarr/Prowlarr/Bazarr/Profilarr | `<name>.` | built-in Forms auth (home edge) | linuxserver images; API keys for integration |
| Sabnzbd/Qbittorrent | `sab.`/`torrent.` | built-in Forms auth | downloads (qbitorrent through gluetun) |
| Navidrome | `music.` | **VPS** (SSO web UI optional + local) | music server — library on Storage Box; ⚠ **no door yet: `music.kogler.si` answers nothing** (see §Navidrome) |
| Immich | `foto.` | OIDC → Authentik | photos (VPS) |

> ✅ **The trio's door is live.** `aurral` (`oldsrv_home_ip:3001`),
> `slskd` (`:5030`, published by its gluetun sidecar) and `lidarr-ydl` (`:5005`) resolve from authored
> rows, route on the home edge and on `.ts`, and answer **200**. ✅ **`slskd` logs in** on both doors — the
> web UI and the Soulseek network (the env-name rule is in §Music Pillar).
> Mechanics: [services-traefik.md](services-traefik.md) §The tailnet leg and the
> music trio's door.
>
> **The downloader's name is `lidarr-ydl.`** — the tool is **music-only**: `angrido/lidarr-downloader` talks only
> to Lidarr (`LIDARR_URL` / `LIDARR_API_KEY`), searches YouTube for *missing albums*, and hands Lidarr
> MP3/M4A/Opus at up to 320 kbps — it has no Sonarr wiring, so YouTube **video** never flows through it.
> Video-from-YouTube is Tube Archivist's job (disabled, see §Music Pillar).

## Request → import wiring (Seerr / SeerrNG → *arr → Jellyfin)

> **Status: 🟢 live** — configured through the UIs; the parts IaC can
> own are seeded by [`tasks/arr-seed.yml`](../IaC/ansible/roles/docker_services/tasks/arr-seed.yml).
> ⏳ What is still missing is upstream of all of it: **indexers** (§Catalog Prowlarr).

Every integration form in this family takes the **overlay address** — the container name on
`services-internal` — never a `*.kogler.si` host. The `Server name` field is a label only: naming a
Radarr instance `media.kogler.si` makes it read as if it pointed at Jellyfin's box. Verified from inside
the containers, not from the docs:

| From → To | Address the form needs | Measured |
|---|---|---|
| Seerr/SeerrNG → Sonarr / Radarr / Lidarr | `sonarr:8989` · `radarr:7878` · `lidarr:8686` | 302 / 302 / 200 (`/`), API 200 with the key |
| **Prowlarr → SABnzbd** | `sabnzbd:8080` | **403 — but NOT the API key**: SAB's own DNS-rebinding guard refuses `Host: sabnzbd`. A credential-free probe against the container separates the two walls: `Host: sab.kogler.si` and `Host: sabnzbd` → *"Access denied - Hostname verification failed"*, while `Host: 127.0.0.1:8080` / the container IP → `200 {"version":"5.1.1"}`. **Owned by `tasks/sabnzbd-seed.yml`** (the shipped whitelist holds only the container id); a client still unsavable after that IS an API-key problem. |
| **Prowlarr → qBittorrent** | **`gluetun:8080`** — qBittorrent is `network_mode: service:gluetun`, so it owns no netns and **`qbittorrent:8080` does not connect** (`code=000`) | `gluetun:8080` → 200 |

**qBittorrent's WebUI credential is the SOURCE, not a copy**: the vault `qbittorrent_api` is what
`roles/docker_services/tasks/qbittorrent-seed.yml` writes into `qBittorrent.conf` as `WebUI\Password_PBKDF2`
(the image translates no credential env and mints a random 9-char password at every start while the stored
hash is empty), and `arr-client-torrent.yml` then writes the same value into the Sonarr/Radarr/Lidarr/Prowlarr
torrent clients — so the propagation is a `qbittorrent_seed` + `arr_client_seed` converge, and between the
vault write and that converge the four arrs 401 against qbit. The seed re-runs each app's client `test`, so
four `arr client test HTTP 200` lines are the proof the consumers authenticate.

**The three values every *arr form needs, and where each is true:**

| App | API base | Root folder (what the app must be told) | Host path behind it | Profile Seerr pins |
|---|---|---|---|---|
| Sonarr 4.0.19 | `/api/v3` | `/media/tv` | `/mnt/nas/media/media/tv` | `HD-1080p` |
| Radarr 6.3.0 | `/api/v3` | `/media/movies` | `/mnt/nas/media/media/movies` | `HD-1080p` |
| Lidarr 3.1.0 | **`/api/v1`** | `/media/music` (name `Music`, `defaultMetadataProfileId: 1`) | `/mnt/nas/media/media/music` | `Lossless` |

⚠ **The API bases are not shared.** Lidarr 3.x answers `/api/v1` and returns **404 with an empty
body** on `/api/v3` — which looks exactly like "this app has no root folders" when probed from a
shell. There is no such thing as "the \*arr API path"; pin it per app.

⚠ **A freshly deployed app hides its own blocker.** Seerr builds its **Root folder** dropdown from
`GET <app>/rootfolder`. A freshly deployed app has none, so the dropdown is **empty and the Add-server
button is disabled with no error anywhere** — Test passes (same key, same URL) and the form just
refuses to submit. `tasks/arr-seed.yml` creates the folder when absent, so a rebuild recovers it.
Profiles are deliberately NOT created there: that is Profilarr/Recyclarr's job (see §Catalog), and
this repo does not let one tool invent another tool's policy — the seed only asserts the pinned
profile still exists and fails loudly when it does not.

- **Jellyfin's own library folders** are the same paths seen from the Jellyfin container, which is
  where its folder picker browses: `/media/movies` + `/media/tv` (the mount is
  `/mnt/nas/media/media:/media:ro` — **ro**, metadata goes to `/config`; music is not a Jellyfin library —
  the music primary is the Storage Box, §Music Pillar). Seerr lists Jellyfin libraries
  from the API, so a Jellyfin with no library gives Seerr an empty library picker — create the
  libraries first, then bootstrap Seerr.
- **Seerr API keys for Jellyfin** are the two owner-minted items `jellyfin-seer_api` /
  `jellyfin-seerng_api` (app state inside each Seerr's `settings.json`; no IaC consumer) —
  [deployment-secrets.md](deployment-secrets.md).

## Credential rotation: which end issues each media key

A rotation holds only if the **issuing** end moves first and every holder is then re-taught. On this stack the
issuers are the apps, not the vault — and one surface has no machine path at all:

| Credential | Issuer (moves first) | Propagation to the consumers | Machine path |
|---|---|---|---|
| `lidarr_api` | Lidarr `config.xml` `<ApiKey>`, applied by a container restart | converge re-renders `lidarr-ydl` (`LIDARR_API_KEY`) + soularr `[Lidarr] api_key`; SeerrNG `settings.json` `lidarr[].apiKey` is app state, restarted by hand | yes |
| `bazarr_api` | Bazarr `config/config.yaml` `auth.apikey` | **none by design** — `bazarr-seed.yml` READS that file and authenticates with the key the instance issued, so the vault copy is a record, not a source; a converge never writes it | yes (read path) |
| `radarr_api` / `sonarr_api` as Bazarr sees them | each arr's `config.xml` `<ApiKey>` | converge `bazarr_seed` re-reads every `config.xml` and POSTs the current key (the `arr-seed.yml` rule) — before that seed, a rotated arr key reached every consumer EXCEPT Bazarr, whose stored key went `401` silently while its own library rows kept listing | yes |
| `qbittorrent_api` | the vault, then `roles/docker_services/tasks/qbittorrent-seed.yml` writes `WebUI\Password_PBKDF2` | converge `qbittorrent_seed` + `arr_client_seed`; the seed re-runs each arr's client `test`, so four `HTTP 200` lines are the consumer proof | yes |
| `soulseek-internal_api`, `soulseek_api` | the vault; the slskd render **is** the far end | converge recreates `slskd` (bounded restart, no persistent state to lose) + soularr `[Slskd] api_key` | yes |
| `privado-vpn_api` | the provider, by the owner | re-read the non-secret WG fields into `home_servers.yml` (`privado_vpn_endpoint_ip/_port/_public_key/_address`), then converge the two gluetun renders | yes — and the item's notes carry an `[Interface] PrivateKey` line, so read it **field-wise**, never by dumping or printing the body |
| `jellyfin-seer_api`, `jellyfin-seerng_api` | **the Jellyfin admin UI** | each Seerr's own `settings.json` `jellyfin.apiKey` + restart, then the vault copy | **none**: this Jellyfin answers `GET /api/ApiKeys` and `GET /ApiKeys` with **404** and `GET /Users` with **401** unsigned. A vault-only write mints a value the server never issued and breaks request approval |
| `jellyfin-bazarr_api` | **the Jellyfin admin UI**, same issuer as the two rows above | `bazarr-seed.yml` writes the vault copy into Bazarr's settings DB — the one Jellyfin leg the seed writes rather than reads, so a re-pointed vault item plus that converge re-teaches Bazarr | **none**, measured with an authenticated key rather than inferred: the same token that gets **200** from `/Users` and `/Devices` gets **404** from `GET /ApiKeys`, `GET /api/ApiKeys` and `POST /api/ApiKeys/New`, so this build has no key surface to mint or revoke at all; the value is one plaintext row in Jellyfin's own `ApiKeys` table (3 rows, one per key) and the only mechanical alternative is that table with the server stopped |
| `admin @radarr.kogler.si` | the Radarr instance's **user store** (`<AuthenticationMethod>Forms</AuthenticationMethod>`, the password held hashed in the app's DB) | ⚠ it is **not** `radarr_api`: the two were provisioned equal and are separate stores, so rotating the API key leaves this login working — measured as `POST /login` → **302** with the session root answering **200** after an `<ApiKey>` rotation. Changing the login itself needs `AuthMethod=None` or a stopped Radarr. `/api/v3/user` → **404**: this build has no user store to PUT | no clean path |
| `admin @media.kogler.si` | the Jellyfin user store | `POST /Users/<id>/Password` → **403** on the shapes probed (`NewPassword`, and `NewPassword`+`Password`); `GET /Users` is 200 once a bearer is issued by `POST /Users/AuthenticateByName` **with** the `X-Emby-Authorization` device header (without it: 400) | UI path |

Two facts that decide the order: the Soulseek **network** login (`soulseek_login`) is a different credential and
must not be touched by a rotation here — a 30-day-unused account is recycled, so liveness is proved from the
app's own log (`Logged in` / `Disconnected`) or its connection state, never by grepping a rendered compose
file. And the two `admin @…` items carry the **same** password value, so a rotation of one leaves the other
stale unless both move in the same act.

**What a rotated `radarr_api` / `sonarr_api` key actually reaches, measured end to end.** The instance's own
`config.xml` is the source, so every leg that reads it follows the rotate — `arr-seed.yml`, `bazarr-seed.yml`, and
Bazarr's own DB through the `bazarr_seed` re-teach (each proved by the stored key's `sha256[:12]` against the vault
and one live call answered **200** with it). Seerr and SeerrNG hold **neither** key: their `settings.json`
`radarr[0].apiKey` / `sonarr[0].apiKey` are empty on this install, so they are not consumers of these two items
(they do hold the two owner-minted `jellyfin-seer*_api` keys). ⚠ **recyclarr is a consumer in IaC only:** the
compose binds `/opt/recyclarr/recyclarr.yml` over the container's `/config/recyclarr.yml`, while the role's render
writes `/srv/docker/recyclarr/config/recyclarr.yml`, which the running container never reads (and that file is
empty). The two keys in the *mounted* file match neither the vault's current values nor the values they replaced, so
recyclarr authenticates with neither — it has been refusing to sync independently of any rotation, and closing that
is a render-path fix, never a rotation.

## Subtitles — Bazarr app-state wiring

> **Status: 🟢 live + seeded** — Radarr + Sonarr + Jellyfin connected, provider and languages
> set, `.srt` sidecars landing next to the media. The wiring is IaC: `compose` owns the container and
> **`roles/docker_services/tasks/bazarr-seed.yml`** owns the app state (converge
> `--tags docker_services,bazarr_seed -e docker_services_scope=bazarr`). Bazarr keeps its settings in
> its own SQLite DB (`/srv/docker/bazarr/config/db/bazarr.db`; `config/config.yaml` is only a partial
> mirror — `use_radarr` there can disagree with the running instance), so without that seed a from-zero
> converge recovers a blank app.

**Readiness is not the container.** Up, `bazarr.kogler.si` → 200 and a honoured `versions.yml` pin can
still sit next to `GET /api/movies` = `{"data": [], "total": 0}` and `GET /api/providers` = `[]` — a
running app that cannot fetch anything, because the compose owns the container and **the app's own DB
owns the behaviour** — the same split `tasks/arr-seed.yml` handles (§Request → import wiring).

**API surface worth knowing** (the shape is identical on 1.6.1 and the pinned `bazarr_version: 1.6.2`;
no spec is published — `/api/schema` serves the SPA — so this was read out of the shipped app source and
then measured):

| Call | Notes |
|---|---|
| `GET/POST /api/system/settings` | POST is **form-urlencoded**, one field per value: `settings-<section>-<key>=<value>` (`settings-radarr-ip=radarr`), plus the **bare** keys `languages-enabled=<code2>` (repeat the field for several languages) and `languages-profiles=<json>`. **204** on success; a wrong key shape answers **500** and the reason only appears in `log/bazarr.log` — read that file after every POST. The GET returns the same values nested as `[section][key]`, which is what makes one field name serve both directions |
| `GET /api/system/languages` | one row per language with an `enabled` flag — the ONLY place the enabled set is readable, `settings` has no languages section. A POST of `languages-enabled` is **replace-all**: the app disables every row and re-enables the sent codes |
| `POST /api/system?action=restart` | graceful restart from inside the app; the PVR link needs it to run its initial sync, and it works where the operator has no `docker` access. A settings POST naming a PVR field already restarts that app's SignalR client by itself (`app/config.py:run_signalr_client`), so the seed does not call it |
| `GET /api/system/health` | the honest gate — `{"object": "Missing languages profile"}` is what "the search did nothing" looks like from outside |
| `GET /api/providers` | the honest provider-auth read — the per-provider `status` is what separates "configured" from "working" (`AuthenticationError` is the credential, not the network) |
| `PATCH /api/movies/subtitles?radarrid=<n>&language=<code2>&forced=false&hi=false` | automatic search, one movie × one language. **All four params are required**; the 400 names exactly the one missing |
| `GET /api/providers/movies?radarrid=<n>` | the UI's Manual Search; 500s without an assigned profile (`int() argument … not 'NoneType'`) |
| `POST /api/jellyfin/test-connection` (`url`, `apikey`) | run it before saving the Jellyfin leg — it is the only thing that separates a wrong URL from a wrong key |

⚠ **The profile-shape trap.**
`GET /api/system/languages/profiles` renders each item's `language` as an **object**
(`{"code2": "sl", "name": "Slovenian", "enabled": true}`), but the writer wants the **bare code2 string**
(`"language": "sl"`). POST the object and it is stored verbatim; every movie serialisation then dies in
`api/utils.py:73 postprocess` — `subs.split(':')` on a dict — so `GET /api/movies` 500s and every page
that reads the movie list, **Settings → Languages included**, comes up empty. Undo: `POST
/api/system/settings` with `languages-profiles=[]` **and** `POST /api/movies` with an empty `profileid`
per movie (the rows still point at the deleted profile otherwise), then `POST /api/system?action=restart`.
**Create profiles in the UI**; read them back over the API if a seed has to reproduce them.

**Addresses — same rule as §Request → import wiring (overlay/container name, never a `*.kogler.si`
host), with exactly one exception.** Measured from inside the Bazarr container:

| Leg | Value that works | Evidence |
|---|---|---|
| Bazarr → Radarr | `radarr:7878` + the key read from `/srv/docker/radarr/config/config.xml` | `GET /api/v3/system/status` → `200` with that key, while the key Bazarr had stored answered `401`; the seed writes the `config.xml` value |
| Bazarr → Sonarr | `sonarr:8989` + its own `config.xml` key (the `arr-seed.yml` rule: instance key, never the vault copy) | the same `401`-vs-`200` pair |
| Bazarr → Jellyfin | **`https://media.kogler.si`** — the container name fails (`HTTPSConnectionPool(host='media', port=443) … NameResolutionError`), because Bazarr dials this one over HTTPS by name | `test-connection` → `{"success": true, "server_name": "media", "version": "10.11.11"}`; `Movies` library + refresh-on-download on |
| Bazarr → provider | `opensubtitlescom` with `opensubtitles_login` | ❌ `Throttling opensubtitlescom … AuthenticationError … 'Login failed'`, retried hourly — and the stored login is **byte-equal to the vault item**, so this is the credential itself, not a propagation failure or the network |

**The PVR legs are the propagation gap this seed closes.** A rotated arr API key reaches
`lidarr-ydl`, soularr and SeerrNG through their renders, and reached Bazarr through nothing: the pin
window left Bazarr storing pre-rotation Radarr/Sonarr keys, which is invisible from the outside — the
library keeps listing rows synced before the rotate (`GET /api/movies` is Bazarr's own DB, not the
arr's), while every live call returns the arr's `401` body. `bazarr-seed.yml` reads each key from the
app's own `config.xml` on every converge, so the gap is closed by the render rule rather than by memory.

**Keys are app state, documented as such:** Bazarr's own API key is the vault `bazarr_api`. **The
instance issues it, so a rotation goes there first**: `auth.apikey` in
`/srv/docker/bazarr/config/config/config.yaml`, edited with the container STOPPED — a running Bazarr
rewrites that file on a graceful exit and would restore the old value — then Bazarr starts, then the vault
copy is written. `bazarr-seed.yml` READS that file (as `X-Api-Key`) and never writes it, so no converge
propagates a rotate and `--rotate` on the item alone writes a value the app never issued. Jellyfin's
read-only key minted for Bazarr is `jellyfin-bazarr_api` → [deployment-secrets.md](deployment-secrets.md);
that one leg the seed DOES write, because Jellyfin mints it and there is no instance file to read.

**App state read over the API:** languages enabled
`sl, en, hr, sr, sh` (`bazarr_seed_languages`; `sh` is what the `cro/srb` profile asks for, so dropping it
from the list would silently stop hunting Serbo-Croatian); profiles `slo + eng` (sl,en), `slo` (sl),
`cro/srb` (hr,sh) — ⚠ **no profile is assigned and default hunting is off**: both movies carry
`profileid: null`, `movie_default_profile`/`serie_default_profile` are empty and
`movie_default_enabled`/`serie_default_enabled` are `false`, so the scheduled search will keep finding
nothing until an owner sets it (Settings → Radarr → Default profile, or per movie) ⏳. The library holds
one sidecar for the title *Svadba* / `The Wedding` (2026, tmdb 1551507, Radarr id 2):
`movies/The Wedding (2026)/Svadba.2026.WEBRip.1080p.h264.[ExYuSubs].en.hi.srt` (English, HI; Bazarr lists
it with `hi: true`). No `sl`/`hr`/`sr` file exists for the title — a provider-availability question that
cannot be answered until the provider login works.

## Navidrome (music.kogler.si) — VPS + Storage Box

- **Placement:** on the **VPS** (reliable tier) with **app + data together** — library on the live Hetzner
  Storage Box (`/mnt/storagebox/music`, CIFS via the `cifs` role), app data + SQLite on VPS NVMe
  (`/srv/docker/navidrome/data`, Kopia-backed). Home-independent by design (music survives WAN-out scenes
  via the VPS edge / WG bridge; data is offsite).
- **Auth:** local logins retained (break-glass + Subsonic clients); the web UI **SSO via Authentik is
  optional** (deploy-gated) — `/rest/*` stays local for Subsonic clients (Symfonium, play:Sub).
- **Clients:** any Subsonic-compatible app; web at `music.kogler.si` (internal/tailnet — no public record).
- **Import path:** Lidarr keeps its root on the NAS (`/media/music`) — that is where the FLAC master lives and
  where it is backed up. The Box is filled by a **push from `oldsrv` to the Box over rsync/SFTP on `:23`**
  (`push-music.timer` → `storage-push-music.sh`, with a mountpoint assert, a non-empty floor and a bounded
  `--max-delete`); there is deliberately no Box mount on oldsrv to import into, so "wire the mount" is not the
  missing step. `docs/storage.md` owns the tiering/consequence line. The timer is **not armed** while the Box SSH
  identity is missing on oldsrv, so today only files placed on the Box by hand (or by the owner's own SMB mount)
  reach Navidrome, and an import that appears to work on the NAS has not reached the serving copy.
- **⚠ The door is still missing.** `music.kogler.si` is
  published **nowhere**: no row in `zone_kogler_si` on any of the three Technitium instances, no entry in
  headscale's extra-record sets, and **no router in any edge file** — the VPS `traefik-tailnet` set routes
  `foto` / `file` / `git` but not Navidrome, and this container sets `traefik.enable: "false"` and publishes no
  host port. `dig` answers nothing; the control (`lidarr`) answers `200`. The container, the Box bind and the
  scanner are verified; the hostname is not, so the statement is true of the server and false of the service.
  The correct shape depends on which edge is allowed to serve VPS-resident internal apps at home (the `foto`
  precedent dials `wg_s2s_vps.ip:wg_internal_edge_port` from the home edge), so it needs a route on the
  VPS edge **and** the home edge plus one zone row — not a bolt-on to a DNS lane.

## Music Pillar — acquisition + discovery

> **Status: 🟢 live on oldsrv** — slskd + its gluetun/PrivadoVPN sidecar healthy, aurral up,
> `lidarr-ydl` up and healthy, and **slskd is on the Soulseek network** (`Logged in to the Soulseek
> server`). **Tube Archivist is disabled** (row `enabled: false`) — see the gotchas
> below; re-enabling means fixing ES first.
>
> The shape of this pillar: **oldsrv downloads and manages, the VPS serves** (Navidrome). All **P2P**
> egress (slskd + qBittorrent) goes through the **shared gluetun WireGuard → PrivadoVPN**; **SABnzbd stays on
> the plain LAN** — usenet does not need the VPN and sharing a tunnel with torrents couples two risk sets.
>
> Three implementation traps:
> - **An image with a read-only layer may have no writable appuser home.** `lidarr-ydl` fails FATAL on
>   `/home/appuser/.profile` `EACCES` without one; the fix is a durable host bind at `/home/appuser`, not a chmod
>   inside the image. Same class: aurral needs `/app/downloads` durable-bound or its weekly playlist fails.
> - **Elasticsearch `path.repo` must be set in `elasticsearch.yml`, never by env or `-E`.** Tube Archivist
>   requires ES snapshot support to serve; `path.repo:` in the compose env **derails ES config generation**,
>   and passing it as `-E path.repo=…` re-boot-straps unstably on the data volume, which presents as
>   constant CPU + alternating RAM on the host. Apply it inside the ES container's `elasticsearch.yml`
>   **before** re-enabling the row. (TA's own stack also needs `ES_DISABLE_VERIFY_SSL` with an https
>   `ES_URL`, redis running with `DAC_OVERRIDE`, and a reset ES data volume; its secret is the
>   `tube-archivist-es` vault item, used as `ELASTIC_PASSWORD` on both sides.)
>
> And a third: **an env var the app does not know is a silent `null` — this compose had four of them.**
> slskd binds only `SLSKD_`-prefixed names, so
> `SOULSEEK_USERNAME`/`SOULSEEK_PASSWORD` (→ empty credentials — the vault holds the real account; the name,
> not the credential, is the failure), `SLSKD_TOKEN` (removed in 0.26 → the UI falls
> back to the **stock `slskd`/`slskd`** login on `slskd.kogler.si`) and
> `SLSKD_{DOWNLOAD,UPLOAD}_BANDWIDTH_LIMIT` (→ the ruled 10 MB/s cap never applies at the container) each do
> exactly nothing while `docker compose ps` reports `healthy`. Correct names, from the binary itself:
> `SLSKD_SLSK_USERNAME`/`SLSKD_SLSK_PASSWORD`, `SLSKD_USERNAME`/`SLSKD_PASSWORD`,
> `SLSKD_{DOWNLOAD,UPLOAD}_SPEED_LIMIT` (KiB/s), `SLSKD_DOWNLOADS_DIR`/`SLSKD_INCOMPLETE_DIR`.
> **The probe that ends this class in one command:** `docker exec slskd /slskd/slskd --envars` — 152 lines,
> the authority over any README or older memory; cross-check what the process holds with
> `GET /api/v0/options` **printing emptiness/length only** (`/soulseek/username -> len=9`,
> `/soulseek/password -> masked`), never a value. A second trap in the same family: slskd **validates** both
> download directories at startup and **exits 0** when one is missing, so `docker ps` shows `Restarting (0)`
> — no non-zero code, no FATAL line, on every restart. `roles/storage/tasks/nas.yml` provisions
> `downloads/incomplete/music`; an arr/service bind is not a substitute for creating the directory.

- **Acquisition chain (ALL on oldsrv):**
  - **Lidarr** (existing) → manages the FLAC library in `bulk/media/media/music` (nas; its API rootFolder is
    `/media/music`) — copy-import to the Box is **not implemented** (no push leg yet, §Storage & Import);
    **the owner's ladder is usenet #1 → Soulseek #2 → YouTube #3**, and for Soulseek that is an
    ordering *rule the human follows*, not wiring — see the slskd bullet and §"*arr ← downloader wiring".
  - **orpheusdl** — manual LAPTOP pip tool (no container; owner runs it on demand for paid-source
    FLAC. NOT in IaC — the automated ladder covers it).
  - **slskd** — Soulseek P2P daemon (Soulseek account, free): **gluetun WireGuard sidecar** (same tunnel as
    qBittorrent), **no inbound port → fetch-only** (search + download; no upload credit). Rate limit is
    enforced **at the container** (`SLSKD_DOWNLOAD_SPEED_LIMIT`, 10 MiB/s = the per-P2P-service cap; there is
    **no router-side per-IP cap** — see
    [services-downloads.md](services-downloads.md) §VPN & Ingress). Acquisition **#2**.
  - **lidarr-ydl** — Lidarr-YouTube-Downloader (Angrido): YouTube search → Lidarr import, **#3** — **audio only**
    (yt-dlp + the bgutil PO-token sidecar → MP3/M4A/Opus into Lidarr); it has no video path and no Sonarr wiring.
  - **Murglar** — a **manual device app** (Android/Desktop): a client with **no API** that downloads to the
    phone and never auto-triggers, so it is not in the automated chain.
  - **Aurral** — **music discovery** companion (lklynet/aurral, free): **Last.fm / ListenBrainz** login history
    → recommends artists/albums → sends requests to **Lidarr**, which lands them in the same FLAC chain.
- **Video pillar (separate):** Tube Archivist (personal YouTube) is an oldsrv service,
  currently **disabled** (see the gotchas above); Jellyfin keeps serving TV/movies. Plex/StreamFab/YTDLNis
  stay **manual / not-IaC** by owner choice — Tube Archivist is the headless yt-dlp piece of that set.
- **Auth:** Aurral / Tube Archivist / Slskd = **own local logins** (same home-edge pattern — *arr UIs use
  built-in Forms auth); no Forward-Auth. `lidarr_api` = the Lidarr instance key, read from its
  `config.xml` ApiKey (see deployment-secrets.md). **The instance is the issuer, so it rotates first:**
  the key lives in `/srv/docker/lidarr/config/config.xml` `<ApiKey>` — change it there and restart the
  container, then write the vault copy, then move the holders: `lidarr-ydl` (`LIDARR_API_KEY` env) and
  soularr (`[Lidarr] api_key`) by converge, and SeerrNG's own `lidarr[].apiKey` in
  `/srv/docker/seerrng/config/settings.json` (app state, no IaC consumer, read at container start).
  **`seerr` carries NO Lidarr server entry at all**, so a rotation that "re-renders Seerr" changes nothing
  there — prove the holder set by reading both `settings.json` files, not by assuming the pair is symmetric. **Slskd's UI is `slskd` + the `soulseek_api`
  credential** as `SLSKD_PASSWORD` — slskd 0.26 has no token option, so a compose that sets only
  `SLSKD_TOKEN` answers at `slskd.kogler.si` with the stock `slskd`/`slskd` login. Proven shape:
  `POST /api/v0/session` → 200 with the vault password, 401 for the stock pair.
- **Storage / where music enters the library:** the library is `bulk/media/media/music` (nas) = oldsrv
  `/mnt/nas/media/media/music` = Lidarr `/media/music`; slskd completes into
  `bulk/media/downloads/complete/music` and stages partials in `…/downloads/incomplete/music`. Three ways in:
  1. **slskd** → `…/downloads/complete/music` (needs a bridge for the *import* step — see the wiring bullet);
  2. **the arr's own clients** (SABnzbd/qBittorrent) → hardlink import within `bulk/media`;
  3. **`\\nas\music`** — a Samba share pointed **straight at the Lidarr root**, so a laptop
     can drop finished albums with no follow-up move (`bulk/media` is NFS-exported to oldsrv only, so nothing
     else Windows-facing reaches that tree). Layout: `<Artist>/<Album (Year)>/<files>`, then Lidarr →
     Artists → **Add New → Import mode "Existing Files"** (or Rescan on a known artist). Files land
     media-owned (`force user/group = storage_uid`) so the arr can still rename/hardlink them. Mount it with
     the **`shared`** Samba service account (`smb-shared_login`; local tdbsam, no IdP in the path) — see
     [storage.md](storage.md) §Samba (SMB) shares on the NAS.
- **Lidarr's root-folder set is SSOT'd as ONE path** — `arr_seed_apps.lidarr.root_folders: ['/media/music']`
  (`roles/docker_services/defaults/main.yml`), and `roles/docker_services/tasks/arr-seed.yml` GETs the live
  `rootfolder` list and POSTs **only the absent paths**. **There is no DELETE for `rootfolder` anywhere in
  `IaC/`**, so a root that exists in the running app but is not declared is neither removed nor reported —
  the converge reads `ok` over it while the dropdown offers it. That matters because `/downloads/complete/music`
  is simultaneously slskd's completion dir (`SLSKD_DOWNLOADS_DIR`) and soularr's `download_dir` (both
  `[Lidarr]` and `[Slskd]`), and Lidarr binds `/mnt/nas/media/downloads` to `/downloads`: an album pinned to a
  root inside the completion tree lives where soularr's timeout pass deletes (measured, in the soularr ini's own
  comment: an album enqueued at 17:17:35 was deleted at 17:22:39 — 304 s). **Never pin a library root inside
  `downloads/`**; prove the live set with `GET /api/v1/rootfolder` (`lidarr_api`) rather than trusting the YAML,
  because the YAML cannot see the difference. Options and the owed read-and-report leg: [`todo.md`](../todo.md)
  HD-1172, cross-linked to HD-1091.
- *****arr ←? downloader wiring:***** Prowlarr (existing) points at SABnzbd + qBittorrent for Lidarr.
  ⚠ **slskd cannot be a Lidarr download client at all** — `GET /api/v1/downloadclient/schema` on the live
  Lidarr **3.1.0.4875** returns 18 client types and every one is usenet or torrent; there is no Soulseek/Slskd
  type (checked in the binary's own schema, not from the UI). So nothing pulls slskd's completed albums into
  the library on its own, and any text claiming "Lidarr sees Soulseek as #2" describes an intention, not a
  wiring. **lidarr-ydl** does register (Newznab indexer + a SABnzbd-emulating client) — that leg is a real
  client, unlike this one. SeerrNG stays the music-request UI on top of the same Lidarr.

- **The Soulseek bridge is [`mrusse/soularr`](https://github.com/mrusse/soularr), and it is armed.** It is
  a poller, not a download client — it cannot be anything else, because an arr has no Soulseek client type —
  and its loop is: read Lidarr's wanted list → search via the slskd API → enqueue → wait for the completion
  folder → rename + tag the folder → `DownloadedAlbumsScan`. Its two ends are two different secrets and only
  one of them is a key: the slskd **API** takes the minted `soulseek-internal_api` credential, rendered into
  slskd as `SLSKD_API_KEY` and into soularr's `config.ini` as `[Slskd] api_key` from the SAME vault item, so
  the bridge cannot be armed on one side and left dark on the other; the slskd **UI** keeps taking
  `soulseek_api` as a password through `POST /api/v0/session` (a JWT, never an `x-api-key`). The API answers
  on the **sidecar's** name — `gluetun-slskd:5030`, not `slskd:5030`, because slskd shares that network
  namespace — so that is the `host_url` soularr must use. soularr reads exactly one config file and has no
  env surface, so the rendered `config.ini` is bind-mounted over its state dir (`/data/config.ini`, not a
  `/data/*` glob) with mode `0600` and the container's own uid as owner: the file carries both API keys, and
  a `0600 root` render is a file the poller cannot open. Its patience knobs are one hour on purpose: while a
  peer is sending, slskd keeps reporting the transfer as queued, so a short queue bound deletes an album
  whose bytes are already landing on disk. ⚠ **The timeout path destroys partial progress instead of leaving
  it for import** — soularr's timeout branch calls `cancel_and_delete()`, which `shutil.rmtree`s the album's
  COMPLETED folder out of the completion dir and never runs the import trigger, so a retry starts from zero
  and no knob in `config.ini` can express "leave the partial for import"; patience delays the deletion, it
  does not prevent it. The lever for that is an upstream/config question about the rmtree, not another knob. What the bridge does NOT change is the import cost: the arr cannot
  hardlink across the `/downloads` → `/media` binds, so it MOVES the files and seeding stops at import.
  A Soulseek find still has to survive the network itself — a wanted album is only as fast as the peer that
  holds it — so the `\\nas\music` drop remains the manual path that never depends on a stranger.

- **YouTube acquisition (`lidarr-ydl`) — the credential works, the grab path has never fired.** Read from
  the app and from Lidarr on the same pass:
  - the downloader authenticates and syncs — its log repeats `Lidarr sync complete: 3 albums cached`, which
    matches Lidarr's own `wanted/missing` count, so `lidarr_api` is valid and its read of the wanted list
    is live (no 401 class in its log);
  - **it has never downloaded anything**: `download_queue`, `track_downloads`, `download_client_jobs` and
    `download_logs` are all 0 rows and only `missing_albums_cache` holds content (3) — there is no
    YouTube-sourced album in the library to point at, and there never has been;
  - **and Lidarr has no route to it**: the instance's indexer list is the three Prowlarr-sourced ones and
    its download clients are qBittorrent + SABnzbd (`host: SABnzbd`, port 8080) — nothing points at
    `lidarr-ydl:5000`, so a Lidarr search can never hand it a release. Its Newznab surface is not at
    `/api/v1/indexers.xml` either (404; the real path is not established).
  So today it is a poll-and-cache reader of the wanted list, not a client Lidarr can grab through. Closing
  that is APP state — a Lidarr indexer entry plus a download-client entry — which is the open seed-in-IaC
  question, not a credential question. Until it lands, "YouTube #3" is an intention.

## Related
- [Downloads stack](services-downloads.md) — SABnzbd / qBittorrent / gluetun ingress
- [Services index](services.md) — catalog legend + network/subdomain SSOT
- [Store](storage.md) — ZFS layout, `bulk/media` dataset
- [Media stack redefined brainstorm](../brainstorming/Media stack redefined.md) — source vision (music pillar)