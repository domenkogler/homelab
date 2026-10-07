---
title: Traefik — Reverse Proxy & Edge
role: detail
domain: services
status: active
tags: [services, traefik, proxy, ssl]
---
# Traefik — Reverse Proxy & Edge

> **Role:** Detail — reverse proxy configuration, SSL, CrowdSec, security headers.
> **Links to:** `services-authentik.md`, `services.md`
> **Linked from:** `services.md`, `deployment-compose.md`

> **Status: 🟢 live.** The **VPS public edge** (`traefik`) issues and serves the wildcard `*.kogler.si`
LE cert (Cloudflare DNS-01) and routes every `public: true` service; the **VPS `traefik-tailnet`** instance
is the tailnet/WAN path for the admin dashboards; **`traefik-internal` on oldsrv** is the home-LAN internal
all-app edge (host-net, VIP + LAN-IP entrypoints, TLS from the pulled cert pair) so `*.kogler.si` keeps
working on the LAN when WAN/VPS is down. All three internal edges carry the **full route table**, and
split-horizon DNS is **per instance**: home-hosted apps → `oldsrv_home_ip` on the home instances,
`ha`/`dns-pi` → the home VIP, everything else → the VPS.
⏳ **Open:** the Pi `traefik-ha` edge (HD-17), its router-side wiring (HD-03/HD-60), and authorizing the VPS
public key for the cert-pull + the per-home cert-sync on the issuer side.
>
> ⚠ **Reachability rule of this edge (measured 2026-09-22, HD-419):** `traefik-internal` runs
> `network_mode: host`, so a file-provider route can only reach a backend that **publishes a host socket on the
> address the route names** — container-only port exposure is invisible to it, and the failure is a silent `502`
> with nothing in the edge's log. Two cases, same cause, both now closed: **jellyfin** publishes
> `{{ jellyfin_bind }}:{{ jellyfin_host_port }}` = **loopback**, which is enough for a host-net edge and keeps
> Jellyfin's login + its CrowdSec/HSTS bypass off the Home VLAN; `media.kogler.si` 502 → 200. **The whole
> routed group binds loopback now (HD-1083, ruled and landed 2026-10-07); between 2026-10-06 and that change it
> published on the HOME IP, which is what `38f918c` had to correct after a subset flip 502'd the group.**
> Every `*-backend` in `routes.yml.j2` (seerr, seerrng, sonarr, radarr, lidarr, prowlarr, bazarr, profilarr, sab,
> torrent) has its own `*_url` var in `group_vars/all/main.yml`, and the seerr/seerrng (both :5055 inside) and
> torrent/sab (both :8080 inside) splits get distinct host ports. Each `*_url` is composed from the matching
> `*_bind`, **which is what makes a half-flip unauthorable**: the publish and the route the edge dials are the
> same two variables, so one render moves both — the failure mode is no longer reachable by editing one file.
> Host ports: `jellyfin_host_port` 8096, `sonarr_host_port` 8989, `bazarr_host_port` 6767, `seerr_host_port` 5055,
> `seerrng_host_port` 5056, `sabnzbd_host_port` 8080, qbit-via-gluetun `qbittorrent_host_port` = **8085**.
> qBittorrent moved off 8082 on 2026-10-07: gluetun had taken 8082 away from `signal-cli-rest-api` and broken
> alerting (§[services-downloads.md](services-downloads.md)).
> ⚠ Quote the var, not just the number — this list is prose, and numbers in prose are precisely what goes
> stale when a `*_host_port` moves.
>
> **The tailnet leg and the music trio's door — LANDED IN IaC (HD-1087, translated from the
> `18913c63` patch; branch closed 2026-10-07).** ⏳ **Deploy-gated:** the routes and records below are
> authored, not converged. One `oldsrv` `docker_services` converge (traefik-internal hot-reloads its file
> provider) plus the Technitium seed on the three instances — owner-present, it re-renders live edge routing
> and the MagicDNS answer set.
>
> **What landed:** LAN routers (`websecure` + `websecure-lan`) and `*-backend` services for `aurral` ·
> `slskd` · `lidarr-ydl`, dialled through `*_url`/`*_bind`/`*_host_port` (`aurral 3001`, `slskd 5030` — the
> publish lives on its gluetun sidecar — `lidarr-ydl 5005`; all three already had a host socket, measured, so
> no compose change was needed); `websecure-ts` routers on **oldsrv's own tailnet listener** for the whole
> home set (media · seerr · seerrng · sonarr · radarr · lidarr · prowlarr · bazarr · profilarr · sab · torrent
> + the trio); those 14 names in `tailnet_ts_only_subdomains` (MagicDNS `.ts` twins, `node` class →
> `tailnet_oldsrv_ip`); the trio's three rows in `zone_kogler_si`; the matching sets in
> `check_dns_seed_drift.py`. The 11 family rows now declare `tailnet: node, ts_router: true`, so the catalogue
> says what the edge actually does. Node-direct on purpose — no VPS hop, survives a WAN-out at home — and the
> `.ts` namespace only, because MagicDNS answers client-side (HD-382/389).
>
> **Two shape calls the patch did not carry:**
> - **The trio is seeded `lan_only`; the family is not.** The family rows answer the **VPS primary** with
>   `dns_primary_ip`, yet no edge file on the VPS carries a route for those names — away from home the plain
>   family name resolves and then 404s. That is a pre-existing wart, not a contract, so a new name does not
>   inherit it: the trio answers at home only, and away clients use the `.ts` twin. If HD-1083's edge work ever
>   gives the VPS edge this family, flip the trio to `home_edge_ip` in that same change.
> - **The patch's `*_bind` loopback→Home-IP hunks were dropped.** `38f918c` already moved `main`'s routed group
>   onto `oldsrv_home_ip`; re-applying the flip would have a converge "fix" that silently reverts live state.
>   Recorded in [services-rejected.md](services-rejected.md).
>
> **Both router sets dial the same `*_url` vars**, which is exactly why **HD-1083** (loopback-only publishes)
> has to move the LAN *and* the `.ts` routes in ONE converge — half of it 502s the other half, the way
> `38f918c` recorded for the LAN leg.
>
> ⚠ **How this section got a confidently wrong sentence once (2026-10-07).** A session read
> `session/arr-door-20261006` at tip `79749c64`, proved from it that *"no patch exists"*, and wrote that into
> three docs — while `18913c63` was being pushed to the same branch that day. A ref sweep means `git fetch`
> first: a clone's refs are not the remote's refs.
>
> **Name ruled (owner, 2026-10-07):** the downloader is `lidarr-ydl.` — see
> [services-media.md](services-media.md) §Music Pillar for why the neutral `ydl.` was rejected.
> ⚠ **This prose used to say "loopback", and the gap between that sentence and the running host caused a
> three-service outage** (2026-10-06 20:24): a routine `docker_services` converge of radarr/prowlarr/lidarr
> applied the loopback binds, while the edge still dialed `oldsrv_home_ip:<port>` → `502` on those three hostnames,
> with `sonarr` (not recreated) still serving `302` next to them. Two rules came out of it: **(a)** the bind
> address of a routed backend is part of the edge contract — check `docker port <svc>` against the route's URL
> before concluding an app is down; **(b)** converging a committed state onto a host whose live state came from
> an **unmerged** branch reverts that state silently. Loopback-only publishing (edge as the only door) **was
> the target and is now the state — HD-1083 landed 2026-10-07**: the eleven routed `*_bind` values and the
> edge's `*-backend` URLs moved in one converge, acceptance measured on oldsrv (`ss -ltn`: every routed app
> port on `127.0.0.1`, none on the Home address; edge ladder byte-identical to the pre-change baseline).
> It had to be every routed service *and* the edge in one converge; a subset is what caused the outage above. **aurral / slskd / lidarr-ydl joined this group on
> 2026-10-07 (HD-1087)** — LAN routers, `.ts` twins, `*_url` vars and three split-horizon rows, ⏳ pending the
> oldsrv converge. Until that converge they still 404 exactly as before, so a live 404 is not a routing bug —
> check `docker exec traefik-internal cat /etc/traefik/dynamic/routes.yml | grep aurral` first.
> Follow the same pattern for the next one: the `*-backend` URL points at the var, never a literal address.


---

## Responsibilities

- **Reverse proxy** for all public-facing services
- **Auto-SSL** via Let's Encrypt
- **Forward Auth middleware** — delegates authentication to Authentik before traffic reaches apps
- **CrowdSec integration** — WAF and brute-force protection

---

## Network

- Container on `traefik-public` network (CIDR per [`network-addresses-generated.md`](network-addresses-generated.md) SSOT)
- Exposes ports 80, 443 on host
- **Verify an edge route from inside with `--resolve`, not with the public name.** Neither old-srv (upstream
  `1.1.1.1`) nor the WSL runner resolves `*.kogler.si` — the split DNS lives elsewhere — so a plain `curl` from
  those vantages returns `000` / exit 6 and reads exactly like an outage. Pin the name to the address where the
  route actually lives: `curl -sk --resolve <host>:443:<edge addr> https://<host>/` (2026-09-22 the media route
  answered 302→200 on the old-srv Home address and 404 on the VIP — so a `404` here means "wrong vantage", not
  "broken service"). Then split "service down" from "route wrong" by asking the upstream itself over its
  loopback bind. Same class of false alarm as a dead Mgmt99 vNIC — see [network-ops.md](network-ops.md).

---

## Security Headers

```yaml
browserXssFilter: true
contentTypeNosniff: true
forceSTSHeader: true
stsSeconds: 31536000
stsIncludeSubdomains: true
frameDeny: true
X-Robots-Tag: "none,noarchive,nosnippet,notranslate,noimageindex"
```

---

## CrowdSec

- Parses Authentik + Traefik logs
- **Collections (HD-85 / KOPS-041, `crowdsec_collections` group_var):** `traefik` + `linux` baseline, plus the exposed auth-surfaces `home-assistant`, `matrix` (Synapse/Tuwunel OIDC login brute-force), and `grafana`. **HD-313:** + `a1ad/mikrotik` (parser + `mikrotik-bf` + `mikrotik-scan-multi_ports`) for the RB4011/switch/AP remote RFC5424 syslog stream — the **mikrotik collection carries the syslog parsing**; there is **no** separate `syslog-logs` collection in the hub, and asking for one is a crash-loop (`cscli` rejects the unknown collection at startup). Each collection only pays off where its logs reach CrowdSec via `docker.sock` container-log parsing (docker Acquis) or the syslog receiver (HD-313) — extend the var as more services are exposed.
- Community blocklist (IPs that attacked others)
- Free for personal use
- Container on `traefik-public` network

### CrowdSec Web UI (`csui.kogler.si`, HD-272)

- **Richer ops surface** (the dedicated CrowdSec SPA): alerts, decisions, metrics, notifications, multi-LAPI, OIDC SSO, read-only mode — a modern SPA (TheDuffman85/crowdsec-web-ui, `ghcr.io/theduffman85/crowdsec-web-ui`, pinned `crowdsec_web_ui_version`).
- **INTERNAL-ONLY** (HD-272, matches the observability-internal decision): **no public Cloudflare record** — LAN/VPN only, behind **Authentik Forward-Auth** at the edge (repo-standard for internal admin UIs; this UI's native OIDC stays a hypothetical upgrade — forward-auth gives full SSO + MFA passthrough without a second login form).
- **LAPI watcher auth** (deploy-gated owner step): `docker exec crowdsec cscli machines add crowdsec-web-ui --password '<crowdsec-webui_lapi_api credential>' -f /dev/null` (the `-f /dev/null` is REQUIRED — registers without overwriting the container's credentials file). Separate from the `crowdsec-bouncer_api` bouncer key.
- Container on `traefik-public` (reaches `crowdsec:8080` LAPI + the edge).

---

## Traefik Dashboard

- **URL:** `traefik.kogler.si` — **internal-only** (no public DNS record; WAN-blocked)
- **Auth:** behind **Authentik Forward-Auth** (admin only)
- **Config:** enable the API + dashboard and expose the `api@internal` service as an internal backend:
  ```yaml
  command:
    - "--api.insecure=false"
  labels:
    traefik.enable: "true"
    traefik.http.routers.traefik-dash.rule: "Host(`traefik.kogler.si`)"
    traefik.http.routers.traefik-dash.entrypoints: websecure
    traefik.http.routers.traefik-dash.tls.certresolver: letsencrypt
    traefik.http.routers.traefik-dash.service: api@internal
    traefik.http.routers.traefik-dash.middlewares: authentik-forward-auth@file
  ```
- Useful for tracing the routing/middleware chain; service metrics still flow to VictoriaMetrics (see [`observability.md`](observability.md)).
- Decision: **included**; Portainer/Dockge **excluded** (see [`services.md`](services.md)).

## Traefik-tailnet — the tailnet edge for admin dashboards

- **What:** a SECOND Traefik instance (`traefik-tailnet`, `docker_services/traefik-tailnet`) that serves the
  admin/observability dashboards over the **headscale tailnet** with clean subdomain URLs — **no public DNS,
  no port numbers** (the old `tailscale serve :8080..8085` sidecar skeleton is replaced by this edge).
- **Layout:** one compose project on the VPS = `traefik-tailnet` (consumer-mode Traefik, binds :443/:80 in
  its own netns, joins `traefik-public` pinned to the tailnet-edge IP (SSOT `network-addresses-generated.md` / the compose `ipv4_address`)) + a `tailscale-sidecar` userspace tailnet node
  (`vps-obs`, `tag:sidecar`) that shares the traefik netns (`network_mode: service:traefik-tailnet`) and runs
  `tailscale serve --tcp=443 → 127.0.0.1:443` (raw passthrough, so Traefik does its own TLS+SNI).
- **TLS/consumer mode (HD-181/HD-204):** NO ACME resolver on this edge. It serves the **synced wildcard
  pair(s)** from the VPS issuer (`/opt/traefik/certs/...` bind-mounted read-only); the issuer now also
  requests `*.ts.kogler.si` (dash router `tls.domains[1]`) so the MagicDNS twins get a valid cert.
- **Routes (file provider `dynamic/routes.yml`):** the five admin dashboards
  `stats`/`logs`/`csui`/`traefik`/`auto`, each as `*.kogler.si` **and** `*.ts.kogler.si`. The plain names
  carry **Authentik Forward-Auth** (same middleware definitions, per-instance copies) — verified shape:
  plain → **302 → sso.kogler.si**; the `*.ts` twins are **ACL-gated** (no forward-auth; the headscale ACL
  `tag:sidecar:443` is the gate, see [`network-vpn.md`](network-vpn.md)) → **200 / 301→https**.
  ⚠ **Jinja renders inside `#` template comments too (HD-297c).** A comment containing a literal
  `{{ vault['…'] }}` raised `dict has no attribute …`, the middlewares render task failed, and the dynamic
  file therefore never landed — which surfaced at runtime as
  `middleware "authentik-forward-auth@file" does not exist`. That is a **missing-file** error, not a skipped
  loop: check the render, not the middleware. In templates, write such examples as literal text.
- **Dashboard:** this edge also serves the Traefik dashboard on `traefik.kogler.si` / `traefik.ts.kogler.si`
  (the public edge has no dashboard router — single owner of that name on the tailnet).
- **Auth key/secrets:** `tailscale-sidecar_api` (API Credential, `credential` = reusable tagged preauth key)
  in 1Password; fail-loud render (`_template_vault_items`).

## Edge model — public edge + internal edges (home LAN + tailnet)

> **The rule (HD-349):** internal apps are served by **both** a home-LAN edge and the tailnet edge. A VPS-only internal edge is not acceptable: **when WAN is down, every internal app becomes unreachable from the LAN**, because internal `*.kogler.si` records resolve to the **VPS public IP**, yet all backends (immich, jellyfin, grafana, HA-standby, …) are containers on home hosts. The re-decision adds a **home-LAN internal all-app edge** so `*.kogler.si` keeps working on the LAN regardless of WAN/VPS state.

### Two-path serving model (current SSOT)

| Path | Edge | Host | Clients | Names | Reaches (backends) | Survives |
|---|---|---|---|---|---|---|
| **Public** | `traefik` (Docker-labels, single ACME issuer, Cloudflare, Forward-Auth + CrowdSec) | VPS | WAN | public `*.kogler.si` | — (public-WAN only) | WAN-up (edge is on the VPS — dies with WAN) |
| **Tailnet/WG** | `traefik-tailnet` (file-provider, no Docker-labels) | VPS | tailnet + WG-S2S | all `*.kogler.si` (plain + `*.ts` twins) | VPS-local overlay + (via WG) oldsrv LAN-IP home backends | VPS + tunnel up |
| **Home-LAN** | **`traefik-internal`** (VIP + LAN-IP bound, file-provider) | oldsrv | Home VLAN + family Wi-Fi | all internal `*.kogler.si` → home edge | home-hosted on `oldsrv_home_ip`; VPS-hosted via `wg_s2s_vps.ip`:4443 (double-hop) | WAN-out, Pi-out, both (as long as oldsrv is up) |
| **HA/DNS edge** | Pi `traefik-ha` (VIP-bound, host-net) | Pi | LAN + local | `ha` + `dns-pi` → VIP (full table present) | local HA/VIP; standby backends on oldsrv LAN IP when oldsrv is up | oldsrv-out |

> **Route table = uniform across the three internal edges** (HD-350): the SAME filename (`dynamic/routes.yml.j2` per edge) carries the FULL set on `traefik-tailnet`, `traefik-internal` and `traefik-ha`, so any name works from any reachable path. The VPS **public** edge is excluded (public-only). Per-instance **DNS** is what differs: home instances resolve home-hosted names → the oldsrv LAN IP (SSOT `oldsrv_home_ip`, LAN-direct), `ha`/`dns-pi` → the home VIP (SSOT `ha_vip`), VPS-hosted/other public → the VPS public IP (SSOT `dns_primary_ip`); the VPS primary resolves all → its edge (tailnet `vps-obs` / wg `:4443`).

### Why this is needed (the drill finding)

- **Backends are all home-local** (immich, jellyfin, grafana, HA-standby, … run as containers on oldsrv; HA primary on the Pi).
- **Edges were all VPS** (public Traefik + traefik-tailnet). So LAN clients reached home backends *via the VPS* — a single point of failure for **every** access path (LAN, WAN, tailnet).
- **WAN-out = all internal services dead on the LAN**, even though nothing locally is broken (DNS resolved to the VPS public IP).
- **Pi-down = `ha` dead** (traefik-ha edge was on the Pi, no standby edge served the VIP:443).

### Topology (target, HD-349)

- **VPS `traefik-tailnet`** = the **tailnet/WG path** — home-hosted backends (media/*arr/seerr/… →
  `oldsrv_home_ip:<port>` over WG, the media-bridge pattern) are the **intended** shape but **not yet in the
  template** (2026-10-06: no *arr/media routers exist on `traefik-tailnet/dynamic/routes.yml.j2`; the tailnet
  leg of the mobile path stays unserved). ⚠ And they cannot reuse the LAN publishes: those are
  **loopback-only** (jellyfin rule), and a cross-host edge needs `oldsrv_home_ip`-bound publishes — a
  deliberate second change, not an oversight of the 2026-10-06 LAN-door fix. Still Authentik Forward-Auth on
  the edge, not public.
- **NEW: `traefik-internal` on oldsrv** = the **home-LAN resilience path**. Host-net, entrypoints bound to the home **VIP** (`ha-vip`):80/443 **and** the oldsrv **LAN IP** (`oldsrv_home_ip`):80/443, `net.ipv4.ip_nonlocal_bind=1`. Serves THE FULL route table (home-hosted + VPS-hosted via wg :4443 double-hop). File-provider routes (no Docker-labels — avoids router conflicts, same pattern as traefik-tailnet). Consumer-mode TLS (synced wildcard pair from the VPS issuer via traefik-cert-pull). **No Forward-Auth and no CrowdSec on this edge** — both depend on VPS containers (Authentik, CrowdSec LAPI); including them would fail exactly when this edge must survive (WAN-out). All home services carry **their own local login** (Jellyfin, Seerr, *arr built-in Forms auth).
- **Pi `traefik-ha`** = the **HA/DNS edge** for the oldsrv-down case — unchanged. Serves `ha` + `dns-pi` → VIP. Stays VIP-bound so it never fights `traefik-internal` for :443 (only the keepalived MASTER owns the VIP).
- **DNS (home LAN):** home-hosted app names (`media`/`jellyfin`, `seerr`, `seerrng`, *arr, `sab`, `torrent`) point at **oldsrv's LAN IP** on the home Technitium instances (oldsrv secondary + Pi tertiary); **`ha`/`dns-pi` keep pointing at the home VIP**. VPS primary keeps its public records (VPS edge target) for WAN/tailnet; **VPS-hosted names (foto/file/git/…) keep pointing at the VPS public IP on ALL instances** (their backends live on the VPS — the home edge reaches them via wg :4443 double-hop, and WAN clients reach them publicly). This is the only DNS change; tailnet/WAN DNS is unchanged. ⚠ **Not "everything → VIP"**: the VIP normally sits on the Pi, whose edge serves only `ha`/`dns-pi`, so pointing every app at the VIP would regress the normal case. Home-hosted apps point at **oldsrv's LAN IP** because the oldsrv edge serves them.
- **HA `external_url` / Companion:** both `ha` edges (Pi traefik-ha + oldsrv traefik-internal) carry `ha` → the app works over any live path (LAN via home edge, tailnet/WAN via VPS edge).

### Scenario matrix (what it buys)

| Scenario | `ha` | Home-hosted apps (jellyfin, seerr, *arr, downloads) | via |
|---|---|---|---|
| Normal | ✅ Pi edge | ✅ home edge (oldsrv) | home VIP → Pi; oldsrv LAN IP → home edge |
| **Pi dies** (+ manual failover) | ✅ **standby HA @ VIP** | ✅ **home edge (oldsrv)** | oldsrv `traefik-internal` → VIP → standby HA; others via oldsrv edge |
| **WAN dies** | ✅ home edge (oldsrv) | ✅ **home edge (oldsrv)** | LAN DNS → oldsrv LAN IP → home edge; `ha` → VIP → edge |
| **Pi + WAN die** | ✅ standby @ VIP | ✅ home edge (oldsrv) | same as WAN-out, standby HA active |
| **oldsrv dies** | ✅ Pi `traefik-ha` → local HA | ❌ backends dead (containers on oldsrv) — unavoidable | Pi edge + VPS edge (if WAN up) |
| **oldsrv + WAN die** | ✅ Pi edge (local, offline-safe cert) | ❌ backends dead | Pi `traefik-ha` — HA stays reachable |

### Implementation (HD-350 / HD-352)

- **HD-350 — home-edge IaC (implemented):** new `docker_services` entry `traefik-internal` on oldsrv — `templates/docker_services/traefik-internal/` (`docker-compose.yml.j2` host-net, VIP+LAN-IP entrypoints, `net.ipv4.ip_nonlocal_bind=1`, consumer TLS from pulled certs; `dynamic/routes.yml.j2` FULL route table + DEFAULT-store TLS). Reuses the `traefik-ha`/`traefik-tailnet` patterns (file-provider, no docker labels, no ACME). The wildcard pair is pulled by the SAME `traefik-cert-pull` timer (script parametrized via `traefik_consumer_dir`); VPS pubkey authorization = documented owner step. **Route set (13 + VPS set):** `media` (jellyfin :8096), `seerr` (:5055), `seerrng` (:5055), `sonarr` (:8989), `radarr` (:7878), `lidarr` (:8686), `prowlarr` (:9696), `bazarr` (:6767), `profilarr` (:6868), `sab` (:8080), `torrent` (:8080), `ha` (→ VIP:8123), `dns-pi` (→ VIP → technitium-secondary:5380) + VPS-hosted (foto/file/git/ai) via `wg-s2s ip:4443`. **No Forward-Auth, no CrowdSec** (both depend on VPS containers). **Auth on the edge's *arr/downloaders = built-in Forms auth** — deliberate reversal of the old "built-in logins disabled" rule (that rule assumed routes served only while WAN/VPS is up; the home edge must survive WAN-out, so each app must own its credentials). Jellyfin/Seerr/SeerrNG keep local login (client apps / request portal). This also repairs the **lost-routes bug**: since HD-331 removed the oldsrv edge, media / *arr / downloads hosts have NO route today (labels only, unreachable across hosts).
- **HD-351 was deleted as unnecessary.** Its premise was "start `traefik-internal` on forward takeover" — but the edge runs **always** on oldsrv: it serves `ha` only when oldsrv owns the VIP (keepalived MASTER), while the non-`ha` routes serve from oldsrv's LAN IP regardless of VIP state. `ha-failover-api` also cannot start a host service (it runs inside the standby HA container).
- **HD-352 — DNS re-point:** home Technitium instances (oldsrv secondary + Pi tertiary) resolve **home-hosted app names → oldsrv LAN IP**, and `ha`/`dns-pi` → home VIP; VPS primary + tailnet unchanged. Seed rows in `technitium-seed.yml` are per-instance conditioned on `svc.instance in ['secondary','secondary-pi']`. (Original "everything → VIP" regressed the normal case — VIP normally sits on the Pi, whose edge serves only `ha`/`dns-pi`.)

### Certification (unchanged rules)

- **Single ACME issuer = VPS Traefik** (HD-178/HD-181/HD-204): consumers (VPS traefik-tailnet bind-mount, Pi traefik-ha ha-cert-sync, **oldsrv traefik-internal via the parametrized traefik-cert-pull**) serve the synced wildcard pair; the issuer issues via Cloudflare DNS-01. `traefik_acme_issuer: true` only on the VPS. The home edge is **offline-safe for both TLS and auth** by design (synced certs + local app logins).
- **A consumer must never pull from itself — proved, not assumed (HD-450).** Closing HD-350's tail found
  oldsrv's `traefik-cert-pull.timer` failing every 15 minutes since 2026-09-19: the rendered
  `/usr/local/sbin/traefik-cert-pull.sh` carried `SRC` = **oldsrv's own Home IP**, so it asked its own box for
  `/opt/traefik/certs/` and got `Permission denied (publickey)`, while the pair on disk stayed the 2026-08-28
  copy (valid to 2026-11-20 — which is why nothing screamed). No repo state renders that value (`git log -S` on
  the `SRC` line shows only the `hostvars['vps.kogler.si']` form ever existed), so it was **live drift, not an
  IaC bug** — and the reason it survived four days of scoped converges is that the cert-pull block carried **no
  tag**, and `roles/*` in `home_servers.yml` get no implicit role tag, so `--tags docker_services` filtered the
  whole block out and still reported a green run. Three durable changes shipped with the close-out: the block is
  tagged `docker_services`; the deploying tasks **assert** the issuer address is neither empty nor this host;
  and both pull scripts (`traefik-cert-pull.sh`, Pi `ha-cert-sync.sh`) exit **90** when `SRC` names one of the
  host's own scope-global addresses. **Scope of what is live:** oldsrv's copy is deployed and proved; the Pi
  carries the guard from its next `home_assistant` converge (render-proved in `--check`: assert `ok`, render
  `changed=1`, `failed=0`) — its pull works today, so the HA primary was not restarted to install a guard.
  Spark's `spark-dashboard` copy picks the guard up at its own next `docker_services` converge (never run from
  a spark-backed session).
  Note the tag arithmetic that hid it: reaching the Pi's pull task takes `--tags home_assistant,ha_failover`,
  because the `include_tasks` is tagged `home_assistant` and the tasks inside are tagged `ha_failover,hd17`.
  The age/alerting half of the lesson is **HD-450**.
- **trusted_proxies:** HA must trust **all** edges that front it — Pi `traefik-ha` (Pi Home-IP/32, SSOT `dns_tertiary_ip`), **oldsrv `traefik-internal` (oldsrv Home-IP/32 — host-net source = oldsrv Home-VLAN IP, SSOT `oldsrv_home_ip`, HD-350)** and the VPS edges (`traefik_edge_ips`/32, e.g. the oldsrv `traefik` label-edge bridge default) — so real client IPs are preserved (`ha_trusted_proxies` in group_vars/all/main.yml).

**Consumer cert-leg check — the one a stale pair cannot fake.** Run ON the consumer (`oldsrv`/`spark`:
`traefik-cert-pull`; Pi: `ha-cert-sync`). A running timer is not evidence: this fault ran a green-looking timer
for four days.

```bash
systemctl list-timers traefik-cert-pull.timer                    # Pi: ha-cert-sync.timer
sudo systemctl start traefik-cert-pull.service && echo PULL_OK
# empty itemize output = this consumer holds the issuer's current pair:
sudo rsync -azn --itemize-changes --exclude='dump/' \
  -e "ssh -i /root/.ssh/traefik-cert-sync -o BatchMode=yes" \
  "ansible-admin@<issuer address>:/opt/traefik/certs/" "<local certs dir>/"
# the edge must serve the wildcard, never the Traefik default cert:
echo | openssl s_client -connect <edge address>:443 -servername media.kogler.si 2>/dev/null \
  | openssl x509 -noout -subject -enddate
```

`Permission denied (publickey)` = the consumer's `/root/.ssh/traefik-cert-sync.pub` is not on the issuer's
`ansible-admin` `authorized_keys` (append it with the restricted option prefix the existing consumer entries
carry). Exit `90` = the deployed script drifted; re-converge it (`docker_services` on oldsrv/spark,
`home_assistant` on the Pi) and never hand-edit `/usr/local/sbin/traefik-cert-pull.sh`.

> **Invariants of the edge model** (each survived every revision of the model, and each is load-bearing):
>
> - **Split-horizon is by *reach*, not by *name*.** `ha.kogler.si`, `stats.kogler.si` and `home.kogler.si`
>   resolve to the same name everywhere; which edge answers is decided by topology + firewall + which
>   instance's Technitium you ask. Do not invent per-zone names.
> - **`.ts.kogler.si` twins exist for one reason:** they match no Docker provider on the tailnet edge, so they
>   can be routed with ACL-only auth. Anything else should use the plain name.
> - **Every internal app needs a *home* path.** DNS for home-hosted apps must resolve to a home address on the
>   home Technitium instances; a name that resolves only to the VPS makes LAN access depend on WAN. That was
>   the defect of the VPS-only internal-edge model (HD-331) — see [services-rejected.md](services-rejected.md).
> - **File-provider routes on the tailnet edge** (no Docker labels) are what keep the public/`-public`
>   network separation intact while still routing internal apps from that instance.
> - **`traefik-ha` on the Pi is the HA/DNS edge**, not an internal all-app edge: VIP-bound, serving `ha` +
>   `dns-pi`, so it never fights `traefik-internal` for :443 (only the keepalived MASTER binds the VIP).
> - **One ACME issuer** (the VPS public edge); every other edge is a cert **consumer**.

**A consumer's pull can be aimed at itself, and no scoped converge can repair it (HD-350/HD-450,
measured 2026-09-23).** oldsrv's wildcard pair LOOKED synced and was not: the deployed
`/usr/local/sbin/traefik-cert-pull.sh` carried `SRC = ansible-admin@<oldsrv's own Home address>`, so
every 15-minute fire asked its own box for `/opt/traefik/certs/` and got `Permission denied
(publickey)` → rsync rc 255 (405 units, 2026-09-19 → 09-23). Two facts the row had wrong and the
measurement settled: **(1)** it was **live drift, not an IaC bug** — `git log -S` on that line shows
only the `hostvars['vps.kogler.si'].ansible_host` form ever existed and a fresh lookup resolves the
VPS address, while the file's mtime was 2026-09-19 16:14, i.e. hand-touched on the box; validators
read the repo, so the fault was invisible to every gate. **(2)** the repairing block carried **no
tag**, and `roles:` entries get no implicit role tag, so `--tags docker_services` filtered the whole
block out and reported a clean `changed=0` — four days of scoped converges could not re-render it
(the same trap `scripts/README.md` warns about for `--tags tailscale-node`, in a different block).
The SSH identity was never the gap: the pull key's pubkey has been in the VPS `authorized_keys`
since 2026-09-15. Guards, so the silent form cannot come back: the block is tagged
`docker_services`; the deploying task asserts the issuer is non-empty and not this host (plain
`assert`, check-mode safe); and BOTH pull scripts (`traefik-cert-pull.sh`, the Pi's
`ha-cert-sync.sh`) exit **90** when SRC names one of the host's own scope-global addresses — a
self-pull otherwise exits 0, which is exactly why this class of fault is expensive. Live re-check
2026-10-07: SRC renders the VPS address, the timer is active, 0 failures in 3 days, pair valid to
2026-11-20. What remains open is only the **instrumentation** (nothing observes pair age at the
consumers, and nothing watches these units' result — HD-450).

## Cockpit Routes (file-provider, no Forward-Auth)

Cockpit is a host service (not a Docker container), so its routes are a Traefik
**file-provider** dynamic config: `/opt/traefik/dynamic/cockpit.yml` (deployed by the
`cockpit` Ansible role on oldsrv).

- `cockpit-nas.kogler.si` → `http://nas:9090` · `cockpit-oldsrv.kogler.si` → `http://oldsrv:9090` (host IPs per SSOT — backends derived from `network_static_hosts` in the template, HD-188)
- **`cockpit-nas.ts.kogler.si` → the same `cockpit-nas` service**, on the `websecure-ts` entrypoint (HD-361,
  2026-09-24). That listener is oldsrv's own tailnet address — `{{ tailnet_oldsrv_ip }}:443`, never
  `0.0.0.0` — so the chain is: MagicDNS record (headscale `tailnet_ts_only_subdomains`) → tailnet ACL
  (`tag:dev:443`) → oldsrv's node → this router → Home VLAN → nas:9090. One backend, two doors.
  ✅ **The first hop is a fact, not a requirement (HD-465):** `cockpit-nas` sits in
  `tailnet_ts_only_subdomains` (since `97d9fbf`) and the live headscale config carries the record — the earlier
  claim that the name was never published read a stale copy of that list. ⛔ It belongs in that list and **not**
  in `tailnet_subdomains`, which renders BOTH namespaces (the HD-382/389 ambiguity trap).
  **Placement decided 2026-09-27 (owner):** the Cockpit surfaces stay pinned to **oldsrv's** node; the deciding
  fact was the type of the 2026-09-23 outage — a human poweroff at the chassis button, not a lost leg
  ([hardware-oldsrv.md](hardware-oldsrv.md) §Remote Management) — so the record stays rather than being
  re-pointed at the Pi. Accepted cost: one node behind both doors.
  ⚠ **A published name and an `online` node are still not a route (measured 2026-09-27):** oldsrv's deployed
  `/opt/traefik/dynamic/cockpit.yml` is the **2026-09-03** render and carries only the two LAN `Host()` rules, so
  `Host: cockpit-nas.ts.kogler.si` against the tailnet listener answers **404** while headscale publishes that
  name and reports the node `online`. The `cockpit-nas-ts` router authored on 2026-09-24 exists in the role
  template and has never been deployed — the box was offline through every converge that would have rendered it.
  ⚠ **This path dies with oldsrv**, and so does the LAN route: `cockpit.yml` is rendered onto *oldsrv*, so a
  down oldsrv costs the healthy nas its console route too — normal behaviour here, not a nas fault.
  Decoupling = the VPS `traefik-tailnet` edge + a new nftables allow for VPS→nas:9090
  (measured blocked: route present, :22 allowed, :9090 not) — the nas runs no edge of its own by design.
- **Deliberately NO Authentik Forward-Auth**: Cockpit is a management surface with its
  own login and must stay reachable if Authentik is down. Internal-only (no public DNS
  record, WAN-blocked). **Carries `crowdsec-only@file`** (security.md §1 law: never zero
  edge protection — HD-188).
- **Identity gap (HD-361):** Cockpit is PAM-only — a working login needs a Linux account
  with a **password**, and until 2026-09-24 none existed on either host (all accounts
  key-only/locked), so the cockpit-* UIs had **no valid credential**. **Decided 2026-09-21 (HD-361):** one dedicated
  password-bearing `maint` user **per cockpit host** — today that is `nas` + `oldsrv`, the only two hosts running
  the `cockpit` role — with the password generated by the AI and held in 1Password as `nas-cockpit_login` /
  `oldsrv-cockpit_login`; `sudo` group, **no NOPASSWD**, no SSH keys, excluded from `AllowUsers`, so it is a
  browser/console PAM identity and never a network key surface. It is also the plan's **break-glass seat** (the
  HD-409 cockpit runs on `domen`, which stops being the human-only door). ⚠ `cockpit` is in the HD-413 lockout set,
  so these converges run from the laptop, never oldsrv-converging-itself.
  ✅ **Landed and console-verified on nas 2026-09-24** — `roles/cockpit/tasks/maint-user.yml` provisions
  `maint`, and the converge itself asserts `GET /cockpit/login` → 200 with the vault password.
  ⏳ oldsrv: the box answers again (2026-09-27) — what is missing is the converge itself. The finding that mattered is in [security.md](security.md):
  Debian ships `/etc/pam.d/cockpit` with **no group restriction at all**, so the `cockpit-session` group
  was never the gate these docs claimed it was — the role now writes the `pam_succeed_if` rule that makes
  it one.
- Traefik must preserve the original Host header on these routes. Measured on the live nas
  `cockpit-ws` 2026-09-24: `/cockpit/login` returns the same `401 authentication-failed` for
  `Host: 127.0.0.1:9090`, for `Host: cockpit-nas.kogler.si`, and for `Host:` +
  `Origin: https://cockpit-nas.ts.kogler.si` — the **login endpoint does not reject a proxied Host**, so
  a `.ts` name on another edge needs no cockpit-side allow-list to get through authentication. What this
  does NOT prove: cockpit's documented Origin check bites on the **WebSocket handshake**, which this
  probe cannot reach, so the authenticated pane (terminal, metrics) needs one real browser load per new
  name before anyone is entitled to call that route done.
- Requires Traefik's file provider to watch `/opt/traefik/dynamic` (mount in the
  `traefik` compose template).

> **`dns-pi.kogler.si` is NOT a file-provider route.** The Technitium secondary web UI
> (on the Pi) is served by the Pi's **`traefik-ha`** edge like `ha`: `dns-pi.kogler.si →
> VIP` so it stays reachable when oldsrv is down (see [`smart-home-failover.md`](smart-home-failover.md)).
> The `service-host` FQDN shape is the only thing borrowed from the cockpit naming pattern.

---

## Trusted Proxies (Critical)

```
AUTHENTIK_TRUSTED_PROXIES = <Traefik IP>, <Cloudflare IPs if used>
```

Without this, CrowdSec/Fail2Ban will block the proxy itself.

---

## Cloudflare (DECIDED — DNS-only)

Cloudflare is used as the **DNS provider only** (registrar: domenca.com; nameservers `george`/`may.ns.cloudflare.com`). **No proxy** — real client IPs reach Traefik, so CrowdSec/rate-limiting see actual addresses.

- Public records: only the internet-facing subset (`kogler.si`, `foto`, `file`, `git`, `sso`, `ha`, `vpn`, **`matrix`**, **`chat`**).
- Internal-only hosts/services: **no public record**; WAN firewall blocks them (split-horizon).
- Certificates: wildcard `*.kogler.si` via ACME **DNS-01** (Cloudflare API token in 1Password `Homelab-ansible`). **Issuer = the VPS Traefik** (HD-178 — the single issuer; consumers of the synced pair = the VPS `traefik-tailnet` internal edge (bind-mounted `/opt/traefik/certs`, HD-181/HD-204) and the Pi `traefik-ha` edge (ha-cert-sync pull timer); single-issuer enforced in templates by `traefik_acme_issuer`, HD-181).
- No orange-cloud/DDoS/geo-WAF layer — Traefik + CrowdSec handle edge security.

Alternative (rejected): direct exposure without Cloudflare DNS — same result, no benefit.

---

## Matrix Routing — `/_matrix/*` is NOT behind Forward-Auth

Matrix (**[`services-matrix.md`](services-matrix.md)**) skips Forward-Auth (like `ha`, and like the
native-OIDC services OpenCloud/`file`, Immich/`foto`, Open WebUI/`ai` — HD-144/148). Native clients,
other servers (federation), and any future appservice bridges must reach `/_matrix/*` directly, so:
(federation), and any future appservice bridges must reach `/_matrix/*` directly, so:

- `matrix.kogler.si` → Tuwunel homeserver. **No Authentik Forward-Auth middleware on `/_matrix/*`** —
  auth happens *inside* the homeserver via Matrix-native SSO → Authentik OIDC.
- `chat.kogler.si` → Element Web (static). Also no Forward-Auth (avoids double login); SSO is Matrix's own flow.
- **Federation over 443** (TLS) via Traefik + the existing wildcard `*.kogler.si` cert; 8448 optional and not required.
- Public DNS must add `matrix` + `chat` records and the `_matrix` well-known/SRV delegation (see [`network-dns.md`](network-dns.md)); WAN firewall allows 443 (and 8448 if used) to oldsrv for these.

> Precedent in this repo: `ha.kogler.si` (VIP) is already a public route with **no Forward-Auth**
> because the app owns its auth. Matrix and the other native-OIDC routes follow the same shape.

---

## Docker Compose Key Points

```yaml
services:
  traefik:
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - traefik-public
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare"

networks:
  traefik-public:
    external: true
```

---

## Middleware Chain

1. **CrowdSec bouncer** — blocks malicious IPs. Plugin contract (Wave-3 R5): module
   `github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin` (note spelling), pin in
   `versions.yml` (`crowdsec_bouncer_plugin_version`, registry-verified; v1.7.1 REQUIRES
   `crowdsecLapiKey`) — key lives in vault item `crowdsec-bouncer_api`, generated via
   `cscli bouncers add traefik-bouncer`. The container needs a `/plugins-storage` tmpfs:
   under `read_only: true` the plugin manager cannot create it and plugins silently disable,
   killing every router that references the chain.
2. **Authentik Forward Auth** — redirects unauthenticated users to SSO
3. **Security headers** — applied to all responses

Traefik middleware prevents any traffic from reaching an app before authentication and WAF checks pass.

### Public (crowdsec-only) routes

Apps exempt from the auth chain carry `crowdsec-only@file` instead (bouncer + headers, no SSO):
`office` (WOPI worker, HD-166), `vpn`/headscale (native OIDC + control traffic), and `pairdrop` (HD-230) —
PUBLIC P2P share on BOTH `pairdrop.kogler.si` and
`drop.kogler.si` (one router, dual Host matcher; supersedes the HD-113 LAN-only decision).
Abuse guards: CrowdSec bouncer + the app's built-in `RATE_LIMIT=true`; network isolation via
traefik-public-only attachment.