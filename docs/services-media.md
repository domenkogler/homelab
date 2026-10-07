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
> ⚠ **Found 2026-10-06 while wiring the download leg: SABnzbd was unreachable by anything in this
> stack** — its `host_whitelist` shipped with only the container id, so the UI answered "Hostname
> verification failed" and a Prowlarr client at `sabnzbd:8080` could not be saved. Seeded by
> `tasks/sabnzbd-seed.yml`; the why-and-why-not-env autopsy is in
> [services-downloads.md](services-downloads.md) §SABnzbd's own door.
> ⏳ **Prowlarr holds 0 indexers and 0 synced apps (measured 2026-10-06), so no request can be
> searched end-to-end** — the request half of this stack is live (§Request → import wiring) and the
> acquisition half is not. · [todo.md](../todo.md) HD-496
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
| Recyclarr | — | I | 40–80 / 200 | TRaSH custom formats + quality profiles sync (`@daily` inside the container, no UI) — **mechanism fixed + proven 2026-09-28, policy switch still commented** (it rewrites live quality profiles): [deployment-secrets.md](deployment-secrets.md) §the `sonarr_api`/`radarr_api` rows |

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
- **Import = hardlink** for **movies/TV** (the switch is `copyUsingHardlinks` in `mediamanagement` — measured `true` in all three arrs; current builds no longer expose a "Use Hardlinks" toggle, so look for the key, not the label) — instant, zero-space, atomic. **Music** is the exception — and the leg **does not exist yet** (measured 2026-10-07): Lidarr's root is `/media/music` = nas `bulk/media/media/music` (empty), and neither oldsrv nor the NAS can write the Box — `roles/cifs/tasks/main.yml` asserts the Box mount onto the **VPS only**, and `mount | grep cifs` on oldsrv shows nothing. So the HD-354 prose ("Lidarr copies music to the Box") described a path with no mount behind it. Owner ruled the shape on 2026-10-07: **NAS master + a push leg to the Box** — **HD-1088**. `docs/storage.md` §Store tiering owns the layout.
- **Media is not backed up** (movies/TV) — no sanoid snapshots, no syncoid, no Kopia; lost media is re-fetched via
  usenet/torrents. ⚠ **Music must not be read as "the exception" any more (HD-1088):** under the ruled shape the FLAC
  master sits on the NAS in the same not-backed-up tier, and the Box holds a second *serving* copy — the Kopia trail
  runs to the **backup** box (`kopia_sftp_host`, a different server than the live Box), so nothing snapshots or
  replicates either copy. A Soulseek FLAC is not re-fetchable the way a movie is; that durability call is `HD-1088`'s.
- **Owner = neutral shared owner `storage_uid`/`storage_gid` (`media`, 1005)** across all *arr containers
  (linuxserver `PUID/PGID={{ storage_uid }}`/`PGID={{ storage_gid }}`; Jellyfin `user: "{{ storage_uid }}:{{ storage_gid }}"`,
  HD-94/HD-131). SMB/NFS ownership on nas must match.
- **Auth:** *arr / downloader UIs (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, Profilarr, SABnzbd, qBittorrent) = **built-in Forms auth** on the home edge (deliberate reversal of the old "Authentik Forward-Auth, built-in logins disabled" — that served only while WAN/VPS is up; the home edge must survive WAN-out, so each admin tool owns its credentials). Jellyfin + Seerr + SeerrNG = **local login only** (client apps / family request portal would break under forward-auth; Jellyfin SSO dropped — SSO accounts can't fall back to local). API integration between the *arr (Prowlarr↔Sonarr/Radarr, Seerr↔*arr) keeps using API keys, unaffected by UI auth. Dozzle (observability) is also Forward-Auth — see [`observability.md`](observability.md).
- **Request middleware identity:** Seerr / SeerrNG log in via **Jellyfin** (user/password validated by the Jellyfin API — home-local, works offline, no Authentik). SeerrNG (snapetech/seerrng) is a Seerr fork adding **music** — runs alongside Seerr for now (both point at the same Sonarr/Radarr backends); **books/Readarr dropped** (Readarr effectively unmaintained).
- **FlareSolverr: deployed** (`flaresolverr`, overlay-only, no UI/publish) — the condition this line set
  was met on 2026-10-06 by 1337x.to. Wiring + evidence: [services-downloads.md](services-downloads.md)
  §The solver's own door; the manual step is [deployment-manual.md](../deployment-manual.md) §P3.6.
- All *arr subdomains are **internal-only** (not in the public set).
- **Reachability is resolver-dependent (HD-1095, measured 2026-10-07):** `media.`, `seerr.` and `seerrng.`
  are answered **per Technitium instance** — the home instances return `oldsrv_home_ip` (the home edge, which
  serves all three), the VPS primary returns `dns_primary_ip`, and the VPS edge has **no route** for these
  names → HTTP **404**. So the question "does Jellyfin work here?" is really "which resolver did this device
  get first?": the Home VLAN always did, a VPS-first VLAN did not, and the Media VLAN (50 — the Shield and
  the TV) was moved to a home-first DHCP chain on 2026-10-07 via `network_vlans[].lan_first_dns` to make the
  living-room TV work. ⚠ That flag is a per-VLAN workaround: the durable fix, and the owner's stated goal of
  these three names working on **every** network *including away/traveling*, is the missing VPS-edge route
  (+ its public DNS record) — see [network-dns.md](network-dns.md) §Per-Instance Split-Horizon.

| App | Web UI | Auth | Notes |
|-----|--------|------|-------|
| Jellyfin | `media.` | own login (local only) | transcode via Intel HD 630 `/dev/dri` |
| Seerr | `seerr.` | Jellyfin login | family request portal (movies/TV) |
| SeerrNG | `seerrng.` | Jellyfin login | Seerr fork + music (snapetech/seerrng); alongside Seerr |
| Aurral | `aurral.` | own login | discovery + Lidarr requests (Last.fm / ListenBrainz history, free) — internal-only |
| Lidarr-URL-DL | `lidarr-ydl.` | own login | YouTube → Lidarr download client (Angrido) — #3 priority, **audio only** (name ruled 2026-10-07, HD-1087; retires the old `url-dl.` spelling) |
| Slskd | `slskd.` | own login `slskd` + password (`soulseek_api`; 0.26 has **no token** option) | Soulseek P2P — gluetun sidecar, VPN-locked egress, #2 priority |
| Tube Archivist | `tube.` | own login | personal YouTube — internal-only; headless yt-dlp |
| Sonarr/Radarr/Lidarr/Prowlarr/Bazarr/Profilarr | `<name>.` | built-in Forms auth (home edge) | linuxserver images; API keys for integration |
| Sabnzbd/Qbittorrent | `sab.`/`torrent.` | built-in Forms auth | downloads (qbitorrent through gluetun) |
| Navidrome | `music.` | **VPS** (SSO web UI optional + local) | music server — library on Storage Box; ⚠ **no door yet: `music.kogler.si` answers nothing** (see §Navidrome) |
| Immich | `foto.` | OIDC → Authentik | photos (VPS) |

> ✅ **The door is live as of 2026-10-07 (HD-1087, converged).** `aurral` (`oldsrv_home_ip:3001`),
> `slskd` (`:5030`, published by its gluetun sidecar) and `lidarr-ydl` (`:5005`) now resolve from authored
> rows, route on the home edge and on `.ts`, and answer **200** where they answered 404 for a year — their A
> records had been live on the home instances all along, un-managed by anything on `main`, and the converge
> brought `changed=0`: the IaC caught up to the host, not the other way round. ✅ **`slskd` now logs in**
> (both doors — the web UI and the Soulseek network; the env-name root cause is in §Music Pillar, fixed
> 2026-10-07).
> Mechanics + the two shape calls: [services-traefik.md](services-traefik.md) §The tailnet leg and the
> music trio's door.
>
> **Name ruling (owner, 2026-10-07): the downloader is `lidarr-ydl.`** — a neutral `ydl.` was proposed and rejected,
> because the tool is **music-only**: `angrido/lidarr-downloader` talks only to Lidarr (`LIDARR_URL` /
> `LIDARR_API_KEY`), searches YouTube for *missing albums*, and hands Lidarr MP3/M4A/Opus at up to 320 kbps — it has
> no Sonarr wiring, so YouTube **video** never flows through it. Video-from-YouTube is Tube Archivist's job (disabled,
> see §Music Pillar). The same ruling kills the `url-dl.` spelling wherever it is still written.

## Request → import wiring (Seerr / SeerrNG → *arr → Jellyfin)

> **Status: 🟢 configured + live 2026-10-06** (bootstrap completed through the UIs; the parts IaC can
> own are seeded by [`tasks/arr-seed.yml`](../IaC/ansible/roles/docker_services/tasks/arr-seed.yml),
> HD-358). ⏳ What is still missing is upstream of all of it: **indexers** (§Catalog Prowlarr, HD-496).

Every integration form in this family takes the **overlay address** — the container name on
`services-internal` — never a `*.kogler.si` host. The `Server name` field is a label only; naming a
Radarr instance `media.kogler.si` is what made the 2026-10-06 config read as if it pointed at
Jellyfin's box. Verified from inside the containers, not from the docs:

| From → To | Address the form needs | Measured |
|---|---|---|
| Seerr/SeerrNG → Sonarr / Radarr / Lidarr | `sonarr:8989` · `radarr:7878` · `lidarr:8686` | 302 / 302 / 200 (`/`), API 200 with the key |
| **Prowlarr → SABnzbd** | `sabnzbd:8080` | **403 — but NOT the API key**: SAB's own DNS-rebinding guard refuses `Host: sabnzbd`. Re-measured 2026-10-06 against the container without any credential, which separates the two walls: `Host: sab.kogler.si` and `Host: sabnzbd` → *"Access denied - Hostname verification failed"*, while `Host: 127.0.0.1:8080` / the container IP → `200 {"version":"5.1.1"}`. **Fixed by `tasks/sabnzbd-seed.yml`** (the shipped whitelist holds only the container id); a client still unsavable after that IS an API-key problem. |
| **Prowlarr → qBittorrent** | **`gluetun:8080`** — qBittorrent is `network_mode: service:gluetun`, so it owns no netns and **`qbittorrent:8080` does not connect** (`code=000`) | `gluetun:8080` → 200 |

**The three values every *arr form needs, and where each is true:**

| App | API base | Root folder (what the app must be told) | Host path behind it | Profile Seerr pins |
|---|---|---|---|---|
| Sonarr 4.0.19 | `/api/v3` | `/media/tv` | `/mnt/nas/media/media/tv` | `HD-1080p` |
| Radarr 6.3.0 | `/api/v3` | `/media/movies` | `/mnt/nas/media/media/movies` | `HD-1080p` |
| Lidarr 3.1.0 | **`/api/v1`** | `/media/music` (name `Music`, `defaultMetadataProfileId: 1`) | `/mnt/nas/media/media/music` | `Lossless` |

⚠ **The API bases are not shared.** Lidarr 3.x answers `/api/v1` and returns **404 with an empty
body** on `/api/v3` — which looks exactly like "this app has no root folders" when probed from a
shell. There is no such thing as "the \*arr API path"; pin it per app.

⚠ **The failure mode that ate an hour (2026-10-06):** Seerr builds its **Root folder** dropdown from
`GET <app>/rootfolder`. A freshly deployed app has none, so the dropdown is **empty and the Add-server
button is disabled with no error anywhere** — Test passes (same key, same URL) and the form just
refuses to submit. `tasks/arr-seed.yml` now creates the folder when absent, so a rebuild recovers it.
Profiles are deliberately NOT created there: that is Profilarr/Recyclarr's job (see §Catalog), and
this repo does not let one tool invent another tool's policy — the seed only asserts the pinned
profile still exists and fails loudly when it does not.

- **Jellyfin's own library folders** are the same paths seen from the Jellyfin container, which is
  where its folder picker browses: `/media/movies` + `/media/tv` (the mount is
  `/mnt/nas/media/media:/media:ro` — **ro**, metadata goes to `/config`; the retired `music` dir is
  not a library, the music primary is the Storage Box, §Music Pillar). Seerr lists Jellyfin libraries
  from the API, so a Jellyfin with no library gives Seerr an empty library picker — create the
  libraries first, then bootstrap Seerr.
- **Seerr API keys for Jellyfin** are the two owner-minted items `jellyfin-seer_api` /
  `jellyfin-seerng_api` (app state inside each Seerr's `settings.json`; no IaC consumer) —
  [deployment-secrets.md](deployment-secrets.md).

## Navidrome (music.kogler.si) — VPS + Storage Box (HD-354)

- **Placement:** on the **VPS** (reliable tier) with **app + data together** — library on the live Hetzner
  Storage Box (`/mnt/storagebox/music`, CIFS via the `cifs` role), app data + SQLite on VPS NVMe
  (`/srv/docker/navidrome/data`, Kopia-backed). Home-independent by design (music survives WAN-out scenes
  via the VPS edge / WG bridge; data is offsite).
- **Auth:** local logins retained (break-glass + Subsonic clients); the web UI **SSO via Authentik is
  optional** (deploy-gated) — `/rest/*` stays local for Subsonic clients (Symfonium, play:Sub).
- **Clients:** any Subsonic-compatible app; web at `music.kogler.si` (internal/tailnet — no public record).
- **Import path:** **not implemented** — Lidarr keeps its root on the NAS (`/media/music`) and a push leg to the Box
  is what is owed (**HD-1088**, ruled 2026-10-07); there is no Box mount on oldsrv to import into.
  `docs/storage.md` owns the tiering/consequence line. Until that leg lands, only files placed on the Box by hand (or
  by the owner's own SMB mount) reach Navidrome.
- **⚠ The door is still missing, and the landed trio patch does not fix it (HD-354 tail).** `music.kogler.si` is
  published **nowhere**: no row in `zone_kogler_si` on any of the three Technitium instances, no entry in
  headscale's extra-record sets, and **no router in any edge file** — the VPS `traefik-tailnet` set routes
  `foto` / `file` / `git` but not Navidrome, and this container sets `traefik.enable: "false"` and publishes no
  host port. `dig` answers nothing; the control (`lidarr`) answers `200`. The 2026-09-18 ✅ verified the
  container, the Box bind and the scanner — never the hostname — so it is true of the server and false of the
  service. HD-1087 landed the *trio's* door on 2026-10-07 and deliberately did not guess this one: the correct
  shape depends on which edge is allowed to serve VPS-resident internal apps at home (the `foto` precedent dials
  `wg_s2s_vps.ip:wg_internal_edge_port` from the home edge), so it goes in as its own change with a route on the
  VPS edge **and** the home edge plus one zone row, not as a bolt-on to a DNS lane.

## Music Pillar — acquisition + discovery (HD-362)

> **Status: 🟢 live on oldsrv** — slskd + its gluetun/PrivadoVPN sidecar healthy, aurral up,
> `lidarr-ydl` up and healthy. **Tube Archivist is disabled** (row `enabled: false`) — see the two gotchas
> below; re-enabling means fixing ES first.
> ✅ **2026-10-07: slskd is on the Soulseek network** — `Logged in to the Soulseek server` after three weeks
> of `Not connecting … username and/or password invalid`. The vault was never the problem (it holds the real
> account, 9/9-char, verified by length); **the compose passed every credential under a name slskd does not
> read**. See the third trap below — it is the reason this row stayed open after two "wrong password" passes.
>
> The shape of this pillar: **oldsrv downloads and manages, the VPS serves** (Navidrome, HD-354). All **P2P**
> egress (slskd + qBittorrent) goes through the **shared gluetun WireGuard → PrivadoVPN**; **SABnzbd stays on
> the plain LAN** — usenet does not need the VPN and sharing a tunnel with torrents couples two risk sets.
>
> Three implementation traps this stack taught (the first two generic, the third the one that cost
> three weeks):
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
>
> And a third, measured 2026-10-07 while fixing the login — **an env var the app does not know is a silent
> `null`, and this compose had four of them.** slskd binds only `SLSKD_`-prefixed names, so
> `SOULSEEK_USERNAME`/`SOULSEEK_PASSWORD` (→ empty credentials), `SLSKD_TOKEN` (removed in 0.26 → the UI fell
> back to the **stock `slskd`/`slskd`** login, which is what actually answered on `slskd.kogler.si`) and
> `SLSKD_{DOWNLOAD,UPLOAD}_BANDWIDTH_LIMIT` (→ the ruled 10 MB/s cap never applied at the container) each did
> exactly nothing while `docker compose ps` reported `healthy`. Correct names, from the binary itself:
> `SLSKD_SLSK_USERNAME`/`SLSKD_SLSK_PASSWORD`, `SLSKD_USERNAME`/`SLSKD_PASSWORD`,
> `SLSKD_{DOWNLOAD,UPLOAD}_SPEED_LIMIT` (KiB/s), `SLSKD_DOWNLOADS_DIR`/`SLSKD_INCOMPLETE_DIR`.
> **The probe that ends this class in one command:** `docker exec slskd /slskd/slskd --envars` — 152 lines,
> the authority over any README or older memory; cross-check what the process holds with
> `GET /api/v0/options` **printing emptiness/length only** (`/soulseek/username -> len=9`,
> `/soulseek/password -> masked`), never a value. A second trap in the same family: slskd **validates** both
> download directories at startup and **exits 0** when one is missing, so `docker ps` shows `Restarting (0)`
> — no non-zero code, no FATAL line, twelve times. `roles/storage/tasks/nas.yml` now provisions
> `downloads/incomplete/music`; an arr/service bind is not a substitute for creating the directory.

- **Acquisition chain (ALL on oldsrv):**
  - **Lidarr** (existing) → manages the FLAC library in `bulk/media/media/music` (nas; its API rootFolder is
    `/media/music`) — copy-import to the Box per HD-354 (⚠ **the push leg does not exist yet — HD-1088**);
    **the owner's ladder is usenet #1 → Soulseek #2 → YouTube #3**, and note that for Soulseek that is an
    ordering *rule the human follows*, not wiring — see the slskd bullet and §"*arr ← downloader wiring".
  - **orpheusdl** — manual LAPTOP pip tool (no container; owner runs it on demand for paid-source
    FLAC. NOT in IaC — the automated ladder covers it).
  - **slskd** — Soulseek P2P daemon (Soulseek account, free): **gluetun WireGuard sidecar** (same tunnel as
    qBittorrent), **no inbound port → fetch-only** (search + download; no upload credit). Rate limit is
    enforced **at the container** (`SLSKD_DOWNLOAD_SPEED_LIMIT`, 10 MiB/s = the ruled per-P2P-service cap;
    the router-side per-IP cap this doc used to cite has **no implementation** — see
    [services-downloads.md](services-downloads.md) §VPN & Ingress). Acquisition **#2**.
  - **lidarr-ydl** — Lidarr-YouTube-Downloader (Angrido): YouTube search → Lidarr import, **#3** — **audio only**
    (yt-dlp + the bgutil PO-token sidecar → MP3/M4A/Opus into Lidarr); it has no video path and no Sonarr wiring.
  - **Murglar** — stays a **manual device app** (Android/Desktop; it is a client with **no API**, per
    `Music stack.md` it's removed from the chain — it just downloads to the phone, never auto-triggers).
  - **Aurral** — **music discovery** companion (lklynet/aurral, free): **Last.fm / ListenBrainz** login history
    → recommends artists/albums → sends requests to **Lidarr**, which lands them in the same FLAC chain.
- **Video pillar (separate, HD-361 later):** Tube Archivist (personal YouTube) is an oldsrv service,
  currently **disabled** (see the gotchas above); Jellyfin keeps serving TV/movies. Plex/StreamFab/YTDLNis
  stay **manual / not-IaC** by owner choice — Tube Archivist is the headless yt-dlp piece of that set.
- **Auth:** Aurral / Tube Archivist / Slskd = **own local logins** (same home-edge pattern — *arr UIs use
  built-in Forms auth); no Forward-Auth. `lidarr_api` token = the Lidarr instance key (minted from its
  `config.xml` ApiKey 2026-10-07; see deployment-secrets.md). **Slskd's UI is `slskd` + the `soulseek_api`
  credential** as `SLSKD_PASSWORD` — slskd 0.26 has no token option, and while `SLSKD_TOKEN` was the only
  thing the compose set, the UI answered to the stock `slskd`/`slskd` (fixed + verified 2026-10-07:
  `POST /api/v0/session` → 200 with the vault password, 401 for the stock pair).
- **Storage / where music enters the library:** the library is `bulk/media/media/music` (nas) = oldsrv
  `/mnt/nas/media/media/music` = Lidarr `/media/music`; slskd completes into
  `bulk/media/downloads/complete/music` and stages partials in `…/downloads/incomplete/music`. Three ways in:
  1. **slskd** → `…/downloads/complete/music` (needs a bridge for the *import* step — see the wiring bullet);
  2. **the arr's own clients** (SABnzbd/qBittorrent) → hardlink import within `bulk/media`;
  3. **`\\nas\music`** — a Samba share pointed **straight at the Lidarr root**, added 2026-10-07 so a laptop
     can drop finished albums with no follow-up move (`bulk/media` is NFS-exported to oldsrv only, so nothing
     Windows-facing reached that tree before). Layout: `<Artist>/<Album (Year)>/<files>`, then Lidarr →
     Artists → **Add New → Import mode "Existing Files"** (or Rescan on a known artist). Files land
     media-owned (`force user/group = storage_uid`) so the arr can still rename/hardlink them. Mount it with
     the **`shared`** Samba service account (`smb-shared_login`; local tdbsam, no IdP in the path) — see
     [storage.md](storage.md) §Samba (SMB) shares on the NAS.
- *****arr ←? downloader wiring:***** Prowlarr (existing) points at SABnzbd + qBittorrent for Lidarr.
  ⚠ **slskd cannot be a Lidarr download client at all** — `GET /api/v1/downloadclient/schema` on the live
  Lidarr **3.1.0.4875** returns 18 client types and every one is usenet or torrent; there is no Soulseek/Slskd
  type (checked in the binary's own schema, not from the UI). So nothing pulls slskd's completed albums into
  the library on its own, and any text claiming "Lidarr sees Soulseek as #2" describes an intention, not a
  wiring. Options, none implemented yet: **[`mrusse/soularr`](https://github.com/mrusse/soularr)** (polls
  Lidarr's wanted list, drives slskd, drops the album where Lidarr scans), a Lidarr plugin adding a Slskd
  client, or the manual `\\nas\music` drop above. **lidarr-ydl** does register (Newznab indexer + a SABnzbd-
  emulating client) — that leg is a real client, unlike this one. SeerrNG stays the music-request UI on top
  of the same Lidarr (HD-353).

## Related
- [Downloads stack](services-downloads.md) — SABnzbd / qBittorrent / gluetun ingress
- [Services index](services.md) — catalog legend + network/subdomain SSOT
- [Store](storage.md) — ZFS layout, `bulk/media` dataset
- [Media stack redefined brainstorm](../brainstorming/Media stack redefined.md) — source vision (music pillar)