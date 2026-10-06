---
title: Downloads Stack — Usenet, Torrents & VPN Ingress
role: detail
domain: services
status: active
tags: [services, downloads, usenet, torrents, vpn]
---
# Downloads Stack — Usenet, Torrents & VPN Ingress

> **Role:** Detail — the ingress/download slice of the services stack: SABnzbd (usenet), qBittorrent (torrents, VPN-locked), gluetun (WireGuard sidecar).
> **Links to:** `services-media.md`, `storage.md`, `services-traefik.md`, `deployment-compose.md`
> **Linked from:** `services.md`, `services-media.md`

> ✅ **Live on oldsrv:** SABnzbd, qBittorrent (+ the gluetun WireGuard sidecar, `custom` mode with the
> fixed PrivadoVPN endpoint, HD-318).
>
> ⚠ **The recurring failure class here is ownership, not config.** Every *arr-style image runs as
> `PUID/PGID` (1005 here) and writes into `/config`; if Docker auto-creates the host bind it is
> **root-owned**, and the container crash-loops on the first write — SABnzbd as
> `Cannot create INI file /config/sabnzbd.ini`, Bazarr as `PermissionError: /config/config`, others as a
> silent 100 % CPU restart loop. A recreate (any converge that re-renders the compose) reintroduces it,
> so the durable fix is **`bind_owner_uid: 1005` + `bind_dirs: ['config']` on every such service** (the
> Class-A pre-create in `deploy-service.yml`), not a one-off `chown`. If a downloads/arr container is
> restarting, check `ls -n` on the bind before reading the app log.


---

## Catalog

Subdomains are relative to `kogler.si`. Network codes: see [Docker Networks](services.md#docker-networks) in `services.md`; exposure per the [Domain & Subdomain Plan](services.md#domain-subdomain-plan).

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| SABnzbd | sab | P+I | 90–150 / 500 | Usenet downloader → Eweka (NL), plain LAN (no VPN) |
| qBittorrent | torrent | P+I (via gluetun) | 80–130 / 300 | Torrent downloader — VPN-locked, only egress via VPN |
| gluetun | — | P+I | 15–30 / 50 | WireGuard sidecar → PrivadoVPN (**custom** provider, fixed endpoint) — **qBittorrent AND slskd (Soulseek) route through it** (HD-362); SABnzbd stays plain LAN |

## VPN & Ingress

- **VPN:** P2P egress goes through gluetun (WireGuard, PrivadoVPN) — currently **qBittorrent + slskd**
  (HD-362). SABnzbd stays on the plain LAN (usenet is a licensed service, no VPN needed).
- qBittorrent routes through the gluetun network namespace; no direct host port.
- **Rate-limit:** each P2P service (slskd `50300`, qBittorrent) gets a **10 MB/s
  cap at the router** (per-IP limit on the egress VLAN) and an **inbound open port on the LAN side**; see
  [network-ops.md](network-ops.md) §QoS / firewall — the open port is home-LAN-only (no WAN exposure).

**gluetun provider mode — `custom` WireGuard (HD-318c).** gluetun **dropped** its native `privado` provider, so the sidecar now runs in `custom` WireGuard mode with an **explicit, fixed PrivadoVPN endpoint**. The endpoint/address values are **non-secret** and live in the IaC SSOT `group_vars/home_servers.yml` (`privado_vpn_endpoint_ip/port`, `privado_vpn_public_key`, `privado_vpn_address`, `privado_vpn_cidr`) — sourced from the owner-supplied PrivadoVPN WireGuard config; the **client private key is the only secret** (`1Password privado-vpn_api`, field `credential`, looked up at render). Endpoint mapping:
  - `WIREGUARD_ENDPOINT_IP`/`_PORT` ← `[Peer] Endpoint` (`91.148.247.8:51820`); gluetun custom requires an IP literal, not a DNS name ([qdm12/gluetun#2680](https://github.com/qdm12/gluetun/issues/2680))
  - `WIREGUARD_PUBLIC_KEY` ← `[Peer] PublicKey` (server key)
  - `WIREGUARD_PRIVATE_KEY` ← 1Password secret (client key)
  - `WIREGUARD_ADDRESSES` ← `[Interface] Address` (`privado_vpn_address`/`privado_vpn_cidr` in the SSOT — the client tunnel address, a PrivadoVPN CGNAT-range IP)
  - Full-tunnel: `[Peer] AllowedIPs 0.0.0.0/0` is gluetun's default; the `[Interface] DNS` Privado hands out is **not** rendered (gluetun runs its own internal resolver). Single fixed endpoint → no `SERVER_COUNTRIES`/server select.

## Landing & Import

- Downloads land in `bulk/media/downloads/{complete,incomplete}` (TRaSH per-category save paths) — see
  [Media Stack → Storage & Import](services-media.md#storage-import-media-arr).
- **Hardlink import** into `media/` is performed by Sonarr/Radarr/Lidarr in the media stack; downloads
  dir is transient scratch and pruned after import.
- ⚠ **SABnzbd's first-run wizard defaults BOTH folder fields to its own config bind** — `/config/Downloads/{incomplete,complete}`
  (2026-10-06, live). That path is writable and looks harmless, but it is `/srv/docker/sabnzbd/config` on
  the **local NVMe**, while the \*arrs mount the NAS share at `/downloads`; so the grab succeeds, the
  arr cannot see the file at all, and the import dies as "input file does not exist". It also breaks the
  hardlink invariant twice over: `downloads` and `media` are the **same NFS mount** (`fstype=nfs` on both,
  verified), which is the whole TRaSH condition, whereas `/srv/docker` is `ext2/ext3` and would force a
  copy even if the paths matched. Set them to `/downloads/incomplete` + `/downloads/complete` (SAB runs
  as `storage_uid`, and `/downloads/complete` is writable by it — tested), then give each category a
  **relative** dir (`movies`, `tv`, `music`) so files land in `/downloads/complete/<cat>`, which is what
  the arrs read. Proof it is right: a completed grab is visible from the host at
  `/mnt/nas/media/downloads/complete/<cat>` and the arr imports without the "path does not exist" error.
  ⚠ **The ini keys are `complete_dir` and `download_dir` — NOT `dir` / `temp_dir`.** Writing the old names
  "succeeds" (the lines sit in the file, SAB never reads them) and downloads keep landing on the local
  disk — see §SABnzbd 5's folder options below. Both keys are owned in IaC now via
  `sabnzbd_folder_ini` / `sabnzbd_folder_ini_drop` in `roles/docker_services/defaults/main.yml`.

### SABnzbd's own door: `host_whitelist` (HD-496, 2026-10-06)

SABnzbd runs a DNS-rebinding guard of its own, in front of Authentik and in front of its API key: the
incoming `Host:` must appear in `host_whitelist` or it answers **403 "Access denied - Hostname
verification failed"**. A fresh install whitelists **one** name — the container's short id — so on this
host both doors were shut, and each presented as somebody else's fault:

* the UI (`sab.kogler.si`) shows the hostname-check page — Traefik forwards the original Host, and that
  name is not in the list, so **Authentik never gets a chance to be the answer**; and
* a **Prowlarr download client pointed at `sabnzbd:8080` can never be saved** (Prowlarr sends
  `Host: sabnzbd`) — which reads as a bad API key and sent one debugging session re-pasting keys.

Separating the two walls takes one credential-free probe from the host against the container:
`Host: 127.0.0.1:8080` → `200 {"version":"5.1.1"}` (guard satisfied, so anything after that IS auth),
while `Host: sab.kogler.si` / `Host: sabnzbd` → the hostname-check text.

**Seeded by `roles/docker_services/tasks/sabnzbd-seed.yml`** (`--tags sabnzbd_seed`), because there is no
lighter door: the linuxserver image translates no `SABNZBD__*` env (no `/etc/cont-init.d`, nothing
greppable in `/app`), and SABnzbd has **no config-write API** — `GET /api?mode=config&name=…` answers
`{"status":false,"error":"not implemented"}`. So the seed unions the wanted names into the ini between
`docker stop` and `docker start` — the ordering matters, SABnzbd rewrites `sabnzbd.ini` on a clean exit,
so an edit made while it runs is silently undone — and the write keeps whatever was already there. It
reads the ini **as `storage_uid`**: the file is `0600 media:media` and the container runs `cap_drop: ALL`
without `DAC_OVERRIDE`, so even `-u root` is refused.

Two things worth recording from the same sweep — one finding and one **measurement mistake of mine**,
because a wrong probe in the SSOT is worse than no probe.

⚠ **Do not grep `sabnzbd.ini` for `[[servers]]` or `[[categories]]`.** SABnzbd 5.x names each
subsection **after the item**, so a correctly configured instance reads `0` for both patterns — which is
how I came to report "no Usenet provider, no categories" on an instance that had a server and five
categories. The real structure is `[[news.eweka.nl]]`, `[[movies]]`, `[[tv]]`, `[[audio]]`,
`[[software]]`, `[[*]]`; the honest probe is:

```bash
docker exec -u 1005 sabnzbd grep -o '^\[\[[^]]*\]\]' /config/sabnzbd.ini | sort | uniq -c
```

What the download path was actually missing (and still is until it is set): **`[misc] dir` is empty**,
which leaves the completed folder on SAB's local config bind — see §Landing & Import above. The
categories exist but every one has an empty `dir`, and there is an **`audio`** category where this
stack's layout says `music`, so Lidarr's client category must either be pointed at `audio` or a `music`
category added. · [services-media.md](services-media.md) §Request → import wiring · [subscriptions.yml](../IaC/ansible/group_vars/subscriptions.yml)

### Which half of Prowlarr to trust: indexers synced, download clients per-arr (HD-496, 2026-10-06)

Asked directly: *should we drop Prowlarr and register indexers in each arr instead?* No — measured, the
half that works is the half worth centralising:

| Measured on the three arrs | Result |
| --- | --- |
| Indexers | `NZBgeek (Prowlarr)` present in Sonarr, Radarr **and** Lidarr — sync is healthy |
| Download clients | `[]` in all three — nothing wired, because Prowlarr's SAB form will not save |

So the fault is one form in one component, not the model. Splitting by function costs little and keeps
the working half intact:

- **Indexers stay in Prowlarr** — one list, one credential, one place where an indexer's tags/penalties
  and app-profile reach all three arrs. Registering per-arr means editing NZBGeek three times forever
  and losing the flag that Gate 4 of HD-496 checks ("is this indexer Prowlarr-managed?").
- **Download clients are added directly in each arr** while SAB 5 / Prowlarr disagree: Radarr → Category
  `movies`, Sonarr → `tv`, Lidarr → `music` (SAB ships `audio`; add a `music` category or point Lidarr at
  `audio`). Each arr's own form validates differently and accepts these.
- ⚠ **Then do not add a download client in Prowlarr at all.** Adding one there and keeping the arr-side
  entries yields *two* SAB clients per arr, and the arrs round-robin grabs across enabled clients —
  the failure mode is downloads landing in the wrong folder at random, which is a miserable thing to
  debug six weeks from now.
- Cost, stated plainly: SAB's host/port/API key now live in **three** configs instead of one, so an API
  key rotation is three edits. Revisit by pulling a Prowlarr build that speaks `get_cats`; if it saves
  with a category, delete the three arr-side clients **first**, then sync from Prowlarr.

How it was verified, so the check can be repeated without trusting a screenshot — let the **arr test its
own client** instead of approximating it:

```bash
c=$(radarr); p=7878; api=v3            # sonarr/8989/v3, lidarr/8686/v1
k=$(docker exec $c sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' /config/config.xml)
docker exec $c curl -s -H "X-Api-Key: $k" http://127.0.0.1:$p/api/$api/downloadclient
# GET the client JSON, POST it back to /downloadclient/test → HTTP 200 = the arr reached SAB and
# authenticated. Measured 2026-10-06: 200 in all three, with tvCategory=tv / movieCategory=movies /
# musicCategory=music.
```

⚠ **`apiKey` reads back as 8 characters and that is NOT a broken key** — the arrs redact secret fields in
API responses, so `len=8` is the redaction placeholder, not the stored value. Judging "is the key set?"
by that string wastes time; the `Test` call above is the answer.

### SABnzbd 5's folder options are `complete_dir` / `download_dir` — the old names are inert (HD-496, 2026-10-06)

The first version of `sabnzbd-seed.yml` wrote `dir` and `temp_dir` into `[misc]`, re-checked them as
"present", reported **OK already**, and still downloaded to `/config/Downloads` on the local NVMe. Read
the running image and the reason is plain:

```python
# /app/sabnzbd/sabnzbd/cfg.py  (SABnzbd 5.1.1)
download_dir = OptionDir(...)      # ini: [misc] download_dir  = temporary / incomplete
complete_dir = OptionDir(...)      # ini: [misc] complete_dir  = completed
```

`dir`/`temp_dir` were the **SAB 3-era names**. SAB does not reject them — it keeps unrecognised keys
verbatim when it rewrites the ini, so the file ended up holding both the live
`complete_dir = Downloads/complete` (line 39) and my dead `dir = /downloads/complete` (line 177). That is
the failure shape that costs a week: **the value you wrote is in the file, and nothing happens.**

Consequence, as it actually happened: a 24 GB movie completed into
`/srv/docker/sabnzbd/config/Downloads/complete` and Radarr logged once a minute, forever —
`Import failed, path does not exist or is not accessible by Radarr: /config/Downloads/complete/…` —
because Radarr mounts the NAS at `/downloads` and cannot see a path inside SAB's config bind. The file
itself was fine: 23.7 GB MKV with a valid Matroska header. The `.rar`/`.txt` beside it are split volumes
and a PAR2 recovery file, **already unpacked** — nobody should be extracting those by hand, and if a
grab ever shows only `.rar`s, that is SAB's unpack step failing, not a missing manual step.

- Fixed in IaC: `sabnzbd_folder_ini = {complete_dir: /downloads/complete, download_dir: /downloads/incomplete}`
  plus `sabnzbd_folder_ini_drop = [dir, temp_dir]`, so dead keys cannot shadow live ones. Removal is
  scoped to `[misc]`, because `dir` legitimately appears per category (`[[movies]]`, `[[tv]]`, …).
- The proof that these two keys were the whole story: the same release, re-grabbed, went
  `/downloads/incomplete` → `/downloads/complete/movies/…` and imported.
- ⚠ Diagnostic trap that bit twice: reading the ini **inside** the container needs `docker exec -u 1005`
  (it is `0600`, owned by `media`). As root you get `Permission denied` → an empty key variable → and a
  keyless `/api` call then logs `API key missing, please enter the API key …` in SAB and fires a
  notification that reads exactly like an arr misconfiguration. When that warning appears, check the
  user-agent and source in the log line before trusting it: `curl/8.x` from `::1`/`::ffff:127.0.0.1` is
  a shell probe, not Radarr.

### End-to-end run, first success (2026-10-06 21:02)

`Seerr request → Radarr add + search → Prowlarr → NZBGeek → SABnzbd (Eweka) → /downloads/complete/movies
→ import → /media/movies`: 24.4 GB, ~10 min at ~50 MB/s, imported at 21:03, `hasFile=true`, queue drained.

The imported file ends with **one link**, because SAB's completed copy is cleaned up after Radarr links
it — so link count alone is not the test. The switch is `copyUsingHardlinks` in `mediamanagement`,
measured **`true` in all three arrs**; current builds no longer expose a "Use Hardlinks" toggle, so grep
for the key, not the label.

⚠ **A completed import is not yet a visible movie.** The file lives on **NFS**, and Jellyfin's real-time
monitoring does not reliably see writes through an NFS client, so a library can lag until
**Dashboard → Libraries → Scan All Libraries**. Order of investigation for "it downloaded but I can't see
it": `Radarr hasFile` → file present at `/mnt/nas/media/media/movies/…` → library scan. Only then Jellyfin.

**The series leg closed the same way (2026-10-06):** *House* S01 → **22/22** episode files, 78 GB under
`/mnt/nas/media/media/tv/House`, Jellyfin listing it. Two questions that always get asked next, both settled
by reading the filesystem rather than inferring: SAB's `/downloads/complete` holds **179 KB** after a 22-episode
batch — the per-release directories remain as empty husks, so nothing is stored twice — and a whole series
can arrive from **one** Seerr request, which is why episode-level monitoring is worth a look before a
112-episode show is requested (see the monitoring note in §Landing & Import).

### NZBGeek returns its *recent* feed instead of your query (HD-496, 2026-10-06)

Symptom, from the first two real requests: Seerr approves → Sonarr adds both series, monitored → Sonarr
searches `1 active indexer` → `DownloadDecisionMaker | No results found`, SAB queue never fills, nothing
lands. The request half works; the release half returns garbage.

The proof is in Sonarr's **interactive search**, which reports rejections instead of a bare "no results":
`GET /api/v3/release?seriesId=<id>` came back with 100 parsed releases for **both** series — *the same 100*,
none of them the requested show, every one rejected as `Unknown Series` or `X matches an alias for
series with TVDB ID: <someone else>`. Identical results for different queries = **the indexer is serving
its recent-items feed and ignoring the search parameter**, and the arr is correctly refusing them.

Why, for **TV**: the indexer in Prowlarr is a **generic Newznab definition** — `definitionId=None`, fields
`baseUrl / apiPath / apiKey` only, `apiPath = /api` on `https://api.nzbgeek.info`. NZBGeek's old newznab
surface is deprecated and does not honour `q`/`imdbid`/`tvmaze` filters the way the arrs call it, so every
query degrades to "latest 100". Prowlarr ships a **built-in NZBGeek definition** (Torznab-based) for
exactly this; that is what should be used.

**Fix:** Prowlarr → Indexers → Add → **NZBGeek** (the built-in one, not "Newznab") → paste the API key from
nzbgeek.info → Save → **Test**. Then verify at the arr rather than in Prowlarr: Sonarr → the series →
*Interactive Search* must list releases carrying **that show's title**; `Unknown Series` means still
ignoring the query. Log into nzbgeek.info once while you are there — a deliberately wrong key in
testing returned `error code=107 "Account Flagged - Logon To View Reason"`, which is about that attempt,
but a flagged account produces the same "search returns junk" shape for a different reason.

**Measured afterwards, and it narrows this claim:** `t=movie&imdbid=…` **does** work — Radarr processed 173 releases for a real request and grabbed one, so the indexer is not dead and the Usenet leg is proven end-to-end for movies. What fails is the **TV** path (`t=tvsearch`, and the `TVDbId`-based form Sonarr uses), which comes back unfiltered.

⚠ Two probes of mine were artifacts and are named so they do not become folklore: (1) `GET
/api/v1/search?term=…` on Prowlarr returned the same 100 releases for every term, which looks like the
bug above but was **my call** — Prowlarr's search endpoint did not apply `term`, so that probe proved
nothing either way; (2) `apiKey: length=0` came from a `sqlite3` read against a **wrong db path**, not
from a missing key — the key is present, because results do come back from the indexer. Both were re-run
cleanly before the conclusion above was written down.

**Resolved (same evening):** the built-in **NZBGeek** definition replaced the generic Newznab one and TV
searches started returning the requested show — `House-S01E09/E10/E11-…` arrived in SABnzbd under category
`tv`, ~4 GB each, imported on the arr side. The generic-definition diagnosis was right.

### SABnzbd 5 moved its categories endpoint; Prowlarr 2.5.2 still asks the old way (HD-496, 2026-10-06)

Prowlarr → Download Clients → SABnzbd refuses to save: **"Category does not exist"**, for *every* value
you can type — `movies`, `prowlarr`, `*`, all of them. The field is not wrong and the category is not
missing. **Prowlarr cannot read SABnzbd's category list at all**, so its validation compares your input
against an empty list.

Read from both sides (live, 2026-10-06):

| Caller | Endpoint | Answer |
| --- | --- | --- |
| Prowlarr 2.5.2 (`SabnzbdProxy.GetConfig`) | `api?mode=config&name=categories&schema=categories` | `not implemented` |
| SABnzbd 5.1.1's real endpoint | `api?mode=get_cats` | `["*","movies","tv","audio","software"]` |

Why: in SABnzbd 5.x `mode=config` is **no longer a generic config reader** — it dispatches only through
a fixed name table (`_api_config_table`: `speedlimit`, `set_pause`, `set_apikey`, `regenerate_certs`,
`test_server`, …); anything else falls through to `not implemented`. Categories now live behind
`mode=get_cats`. Source, read out of the running image (`/app/sabnzbd/sabnzbd/api.py`):

```python
if mode == "config" and name in _api_config_table:   # → "not implemented" for name=categories
```

**Workaround that works today: leave "Default Category" empty.** Prowlarr validates only non-empty
values, and that field only labels grabs Prowlarr originates itself — the arrs send their own category
per download, which is where `movies` / `tv` / `music` belong. Expect a "A category is recommended"
note; it is a warning, not a blocker.

⚠ **And the Host field must be `sabnzbd`, not `localhost`/`127.0.0.1`** — inside the Prowlarr container
that is Prowlarr's own loopback. Caught in its log: `Unable to connect to SABnzbd … (localhost:8080)
Connection refused`.

⏳ **Not a workaround, the real fix:** a Prowlarr build that speaks `get_cats`. This stack tracks
`linuxserver/prowlarr:develop`, so `docker compose pull prowlarr && docker compose up -d prowlarr` may
already carry it — worth checking before accepting the blank-category shape permanently. Until then
downloads route correctly (the arrs own the category) but Prowlarr's own grabs have no folder.

### Torrent indexers: Cloudflare, DNS, and which door the traffic actually uses (HD-1082, 2026-10-06)

Owner added three torrent indexers next to NZBGeek (`LimeTorrents`, `Nyaa.si`, `Zamunda LIFE`) and 1337x.to
refused to save: `Unable to access 1337x.to, blocked by Cloudflare Protection.` The question that follows is
always "can we bypass DNS for torrents?" — **DNS is not the lever.** Measured:

```
1337x.to  via the stack resolver -> 2606:4700:3033::6815:28c1, 2606:4700:3030::ac43:bc43
1337x.to  via 1.1.1.1            -> 104.21.40.193, 172.67.188.67, 2606:4700:…      # Cloudflare either way
prowlarr  egress                 -> 193.77.156.222   (oldsrv directly, no tunnel)
gluetun   egress                 -> 91.148.247.10    (WireGuard exit, §gluetun provider mode)
```

Both resolvers hand back Cloudflare addresses, so a different resolver only changes **which Cloudflare edge**
you knock on. The rejection happens one layer up: CF wants a browser-grade TLS/JS fingerprint and a indexer
client (Torznab/Newznab over plain HTTP) cannot produce one. There is also no per-indexer DNS or per-indexer
route in Prowlarr — the two knobs it has are global.

What actually moves the needle, in order of how well it fits this stack:

1. **FlareSolverr — done, and it works.** Deployed 2026-10-06 (`flaresolverr:v3.5.2`, overlay-only, no UI,
   no publish; §the solver's own door) and wired in Prowlarr → Settings → Indexers. 1337x.to then **saved
   successfully**, which is the whole point of the component. Cost: one more container with its own browser
   to keep patched. Procedure: [deployment-manual.md](../deployment-manual.md) §P3.6.
2. **Drop the CF-gated site.** Three torrent indexers were already registered; a fourth behind a challenge is
   mostly a maintenance liability. (Not taken.)
3. **Route Prowlarr's own HTTP through the tunnel** (Settings → General → Proxy, SOCKS5). Two problems, both
   measured: gluetun's built-in SOCKS5 is **not listening** (`PROXY_*` unset; `socks5h://127.0.0.1:1080`
   refused), and the proxy setting is global — NZBGeek's queries would start leaving from the VPN exit too.
   Indexers commonly block known VPN ranges, so this can trade one failure for another.

⚠ **The blocker behind the blocker: Prowlarr has no torrent client at all.** `GET /api/v1/downloadclient` →
`[]`. A torrent indexer can search all it likes; the grab has nowhere to go. qBittorrent itself is fine —
`GET http://gluetun:8080/` answers **200 from prowlarr and from sonarr** — but note where that probe has to
run: qBittorrent is `network_mode: service:gluetun`, started with `--webui-port=8080`, and does **not** bind
loopback inside gluetun, so probing `127.0.0.1:8080` from the gluetun container reads "refused" on a healthy
client. Probe it from a third container.

Until a torrent client is registered, the three enabled torrent indexers are a source of **failed grabs**,
not of content: same trap as an indexer with no download client (§Which half of Prowlarr to trust), one layer
earlier. Nothing here changes the Usenet leg, which is proven end to end (§End-to-end run, first success).

### The solver's own door (HD-1084, 2026-10-06)

`flaresolverr` is **not a website**: no subdomain, no traefik labels, no host publish, no `/config` bind.
Prowlarr reaches it on the overlay at `http://flaresolverr:8194`. Two properties differ from the fleet's
conventions and from every integration guide, both measured in the running container:

- **Upstream's default port is 8191**, not 8194 — `/app/flaresolverr.py: int(os.environ.get('PORT', 8191))`.
  The compose pins `PORT=8194` so the address stored in Prowlarr cannot move under an upstream default change.
- **`cmd` is `request.get`**; `browser.request.get` is rejected by 3.5.2 (`Request parameter 'cmd' … is invalid`).
  A solver probe that posts the wrong command fails instantly in ~0.1 s, which looks like a dead container.

Evidence that it earns its place, from the container itself:

```bash
docker exec flaresolverr curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"cmd":"request.get","url":"https://1337x.to/","timeout":60000}' http://127.0.0.1:8194/v1
# → "message": "Challenge solved!" · solution.status 200 · a cf_clearance cookie in the response
```

It is reachable **only** from the overlay by design: a headless browser that will fetch any URL you point it
at must not be listening on the LAN.

## Related
- [Media stack](services-media.md) — the *arr pipeline + storage layout this feeds
- [Store](storage.md) — ZFS layout, `bulk/media` dataset
- [Services index](services.md) — catalog legend + network/subdomain SSOT