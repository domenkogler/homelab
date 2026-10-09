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
⏳ **Open:** the Pi `traefik-ha` edge, its router-side wiring, and authorizing the VPS public key for the
cert-pull + the per-home cert-sync on the issuer side.
>
> ⚠ **Reachability rule of this edge:** `traefik-internal` runs
> `network_mode: host`, so a file-provider route can only reach a backend that **publishes a host socket on the
> address the route names** — container-only port exposure is invisible to it, and the failure is a silent `502`
> with nothing in the edge's log. **Jellyfin** publishes
> `{{ jellyfin_bind }}:{{ jellyfin_host_port }}` = **loopback**, which is enough for a host-net edge and keeps
> Jellyfin's login + its CrowdSec/HSTS bypass off the Home VLAN. **The whole routed group binds loopback**, so
> the edge is its only door.
> Every `*-backend` in `routes.yml.j2` (seerr, seerrng, sonarr, radarr, lidarr, prowlarr, bazarr, profilarr, sab,
> torrent) has its own `*_url` var in `group_vars/all/main.yml`, and the seerr/seerrng (both :5055 inside) and
> torrent/sab (both :8080 inside) splits get distinct host ports. Each `*_url` is composed from the matching
> `*_bind`, **which is what makes a half-flip unauthorable**: the publish and the route the edge dials are the
> same two variables, so one render moves both — the failure mode is not reachable by editing one file. A bind
> change therefore has to move the LAN *and* the `.ts` routes in ONE converge: half of it 502s the other half.
> ⚠ The bind address of a routed backend is part of the edge contract — check `docker port <svc>` against the
> route's URL before concluding an app is down. Converging a committed state onto a host whose live state came
> from an **unmerged** branch reverts that state silently.
> **The names that are NOT in that family** (so the next session does not go looking
> for plumbing that is gone): **(a)** there is no `labels: [… publish=…]` mechanism anywhere in `IaC` —
> `publish=` matches nothing;
> **(b)** `lan-litellm` (`llitellm.kogler.si` → oldsrv Home :4000) uses `lan_litellm_host_port` / `lan_litellm_bind` / `lan_litellm_url`, named
> after the CONTAINER because `litellm_*` already means three different things here (the VPS `litellm` service, the
> spark `litellm-*` profiles, and `litellm_scoped_keys`, one name with two different values on `home_servers` and
> `vps`); **(c)** `dozzle`'s backend is `http://dozzle:8080`, a **compose-DNS service name**, and `llogs`' is an
> inline `http://{{ oldsrv_home_ip }}:8081` — minting a URL var for the first would dress a service name up as a
> host URL (which is how the `service.*` class got authored in the first place), so it stays a literal on purpose,
> while `llogs` is a genuine same-class literal awaiting the edge window. Proving an edit here inert is cheap and
> mandatory: render `routes.yml.j2` recursively (Ansible resolves the nested `oldsrv_home_ip` expression; one-pass
> jinja does NOT, which is why a hand-diff lies) and require byte-identity before an edge converge is even discussed.
> Host ports: `jellyfin_host_port` 8096, `sonarr_host_port` 8989, `bazarr_host_port` 6767, `seerr_host_port` 5055,
> `seerrng_host_port` 5056, `sabnzbd_host_port` 8080, qbit-via-gluetun `qbittorrent_host_port` = **8085**
> (`signal-cli-rest-api` holds 8082 — §[services-downloads.md](services-downloads.md)).
> ⚠ Quote the var, not just the number — this list is prose, and numbers in prose are precisely what goes
> stale when a `*_host_port` moves.
>
> **What is deliberately NOT on loopback** (every exception is a
> consumer, not an oversight): `immich_ml_bind` :3003 and `actual-budget` :5006 are dialled **cross-host** (the
> VPS over the WG S2S), so a loopback bind there takes Immich ML and the n8n→Actual leg down; `dozzle` :8081
> and `lan-litellm` :4000 are dialled by this edge as **literals** (`http://{{ oldsrv_home_ip }}:8081`,
> `…:4000` in `routes.yml.j2`) rather than through a `*_url` var, so they cannot move in the render the
> invariant above depends on — introducing those vars is the work, then the same one-converge move applies;
> `dozzle-agent` :7007 is a log-shipping listener, not an edge backend. ⚠ **The music trio is the sharp one**:
> `aurral_url`/`slskd_url`/`lidarr_ydl_url` compose from their `*_bind` and the
> LAN + `.ts` routers dial those vars — but the **publishes** in `aurral/`, `slskd/` and
> `lidarr-ydl/docker-compose.yml.j2` hard-code `"{{ oldsrv_home_ip }}:<port>"`, so `ss -ltnH` on oldsrv shows
> `3001`/`5005`/`5030` on the Home address while the eleven family ports are on `127.0.0.1` and a LAN device
> can still reach those three apps beside the edge. Flipping those three
> `*_bind` values to loopback moves the dial and leaves the socket on the Home VLAN → `502` on the trio's
> hostnames. **Thread the var through the publish in the same
> change.** Prove the posture at any time
> with `ss -ltnp` filtered to the Home address plus one curl per routed hostname; do not trust this sentence.
>
> **The tailnet leg and the music trio's door.** Three legs carry it: the scoped `oldsrv` `docker_services`
> converge (traefik-internal hot-reloads its file provider — no recreate, no VIP risk), `dns-seed.yml` across
> all three Technitium instances, and the VPS headscale extra-record set behind `guarded-converge.sh`, so the
> tailnet control plane is never left down.
> ✅ LAN + `.ts` for all 14 names — the trio **200/200**,
> the family its own login redirect (302/303/307) on both legs, and **not one 404**, which is what a missing
> router looks like; MagicDNS (`dig @100.100.100.100` on a tailnet client) answers all 14 `.ts` names →
> `tailnet_oldsrv_ip` ([network-addresses-generated.md](network-addresses-generated.md)) and **no plain name at all**;
> the VPS primary answers the trio NXDOMAIN while `lidarr` answers `159.195.111.66`, which is the `lan_only`
> choice working as designed.
> ⚠ **13 of 14 names answer on both legs; `sab` is the exception** — 200 on LAN, **403 off-LAN**, and the
> response body (`External internet access denied`) makes it SABnzbd's own peer-IP locality check rather than
> this file's routing or the hostname whitelist.
> [services-downloads.md](services-downloads.md) §SABnzbd's own door says how to tell the three shapes apart
> (hostname-403 vs locality-403 vs routing-404). `host_whitelist` carries the `.ts` twin because a new Host
> genuinely needs it, not because it changes that 403.
>
> **What the trio's door consists of:** LAN routers (`websecure` + `websecure-lan`) and `*-backend` services for `aurral` ·
> `slskd` · `lidarr-ydl`, dialled through `*_url`/`*_bind`/`*_host_port` (`aurral 3001`, `slskd 5030` — the
> publish lives on its gluetun sidecar — `lidarr-ydl 5005`; all three have a host socket, so
> no compose change is needed); `websecure-ts` routers on **oldsrv's own tailnet listener** for the whole
> home set (media · seerr · seerrng · sonarr · radarr · lidarr · prowlarr · bazarr · profilarr · sab · torrent
> + the trio); those 14 names in `tailnet_ts_only_subdomains` (MagicDNS `.ts` twins, `node` class →
> `tailnet_oldsrv_ip`); the trio's three rows in `zone_kogler_si`; the matching sets in
> `check_dns_seed_drift.py`. The 11 family rows declare `tailnet: node, ts_router: true`. Node-direct on
> purpose — no VPS hop, survives a WAN-out at home — and the
> `.ts` namespace only, because MagicDNS answers client-side.
>
> **DNS shape of the two groups:** the trio's rows are seeded `lan_only` — they answer at home only and away
> clients use the `.ts` twin. The family rows answer the **VPS primary** with `dns_primary_ip`; the VPS edge
> carries routers for `media`/`seerr`/`seerrng` over WG S2S (§The home-hosted names at the public edge), the
> rest of the family has no VPS route. A new home-only name seeds `lan_only` with a `.ts` twin rather than
> copying the family's VPS-primary answer; if the VPS edge ever gains routers for the trio's names, flip the
> trio to `home_edge_ip` in that same change.
>
> ⚠ A ref sweep means `git fetch` first: a clone's refs are not the remote's refs.
>
> **The downloader is `lidarr-ydl.`** — see [services-media.md](services-media.md) §Music Pillar.
> **Loopback-only publishing (the edge as the only door) is the state:** the eleven routed `*_bind` values and
> the edge's `*-backend` URLs move in one converge — every routed service *and* the edge together, never a
> subset. Acceptance on oldsrv: `ss -ltn` shows every routed app port on `127.0.0.1` and none on the Home
> address, and the edge ladder is byte-identical to the baseline. `aurral` / `slskd` / `lidarr-ydl` are in
> this group — LAN routers, `.ts` twins, `*_url` vars and three split-horizon rows — with the publish
> exception above. Pattern for the next routed service: `*-backend` dials the var, never a literal address.


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
  route actually lives: `curl -sk --resolve <host>:443:<edge addr> https://<host>/` (a `404` from a vantage
  whose edge carries no route for the name means "wrong vantage", not "broken service"). Then split "service down" from "route wrong" by asking the upstream itself over its
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
- **Collections (`crowdsec_collections` group_var):** `traefik` + `linux` baseline, plus the exposed auth-surfaces `home-assistant`, `matrix` (Synapse/Tuwunel OIDC login brute-force), and `grafana`, plus `a1ad/mikrotik` (parser + `mikrotik-bf` + `mikrotik-scan-multi_ports`) for the RB4011/switch/AP remote RFC5424 syslog stream — the **mikrotik collection carries the syslog parsing**; there is **no** separate `syslog-logs` collection in the hub, and asking for one is a crash-loop (`cscli` rejects the unknown collection at startup). Each collection only pays off where its logs reach CrowdSec via `docker.sock` container-log parsing (docker Acquis) or the syslog receiver — extend the var as more services are exposed.
- Community blocklist (IPs that attacked others)
- Free for personal use
- Container on `traefik-public` network

### CrowdSec Web UI (`csui.kogler.si`)

- **Richer ops surface** (the dedicated CrowdSec SPA): alerts, decisions, metrics, notifications, multi-LAPI, OIDC SSO, read-only mode — a modern SPA (TheDuffman85/crowdsec-web-ui, `ghcr.io/theduffman85/crowdsec-web-ui`, pinned `crowdsec_web_ui_version`).
- **INTERNAL-ONLY** (matches the observability-internal decision): **no public Cloudflare record** — LAN/VPN only, behind **Authentik Forward-Auth** at the edge (repo-standard for internal admin UIs; this UI's native OIDC stays a hypothetical upgrade — forward-auth gives full SSO + MFA passthrough without a second login form).
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
- Traefik's own dashboard is **included**; Portainer/Dockge **excluded** (see [`services.md`](services.md)).

## Traefik-tailnet — the tailnet edge for admin dashboards

- **What:** a SECOND Traefik instance (`traefik-tailnet`, `docker_services/traefik-tailnet`) that serves the
  admin/observability dashboards over the **headscale tailnet** with clean subdomain URLs — **no public DNS,
  no port numbers**.
- **Layout:** one compose project on the VPS = `traefik-tailnet` (consumer-mode Traefik, binds :443/:80 in
  its own netns, joins `traefik-public` pinned to the tailnet-edge IP (SSOT `network-addresses-generated.md` / the compose `ipv4_address`)) + a `tailscale-sidecar` userspace tailnet node
  (`vps-obs`, `tag:sidecar`) that shares the traefik netns (`network_mode: service:traefik-tailnet`) and runs
  `tailscale serve --tcp=443 → 127.0.0.1:443` (raw passthrough, so Traefik does its own TLS+SNI).
- **TLS/consumer mode:** NO ACME resolver on this edge. It serves the **synced wildcard
  pair(s)** from the VPS issuer (`/opt/traefik/certs/...` bind-mounted read-only); the issuer also
  requests `*.ts.kogler.si` (dash router `tls.domains[1]`) so the MagicDNS twins get a valid cert.
- **Routes (file provider `dynamic/routes.yml`):** the five admin dashboards
  `stats`/`logs`/`csui`/`traefik`/`auto`, each as `*.kogler.si` **and** `*.ts.kogler.si`. The plain names
  carry **Authentik Forward-Auth** (same middleware definitions, per-instance copies) — verified shape:
  plain → **302 → sso.kogler.si**; the `*.ts` twins are **ACL-gated** (no forward-auth; the headscale ACL
  `tag:sidecar:443` is the gate, see [`network-vpn.md`](network-vpn.md)) → **200 / 301→https**.
  ⚠ **Jinja renders inside `#` template comments too.** A comment containing a literal
  `{{ vault['…'] }}` raises `dict has no attribute …`, the middlewares render task fails, and the dynamic
  file therefore never lands — which surfaces at runtime as
  `middleware "authentik-forward-auth@file" does not exist`. That is a **missing-file** error, not a skipped
  loop: check the render, not the middleware. In templates, write such examples as literal text.
- **Dashboard:** this edge also serves the Traefik dashboard on `traefik.kogler.si` / `traefik.ts.kogler.si`
  (the public edge has no dashboard router — single owner of that name on the tailnet).
- **Auth key/secrets:** `tailscale-sidecar_api` (API Credential, `credential` = reusable tagged preauth key)
  in 1Password; fail-loud render (`_template_vault_items`).

## Edge model — public edge + internal edges (home LAN + tailnet)

> **The rule:** internal apps are served by **both** a home-LAN edge and the tailnet edge. A VPS-only internal edge is not acceptable: **when WAN is down, every internal app becomes unreachable from the LAN**, because internal `*.kogler.si` records resolve to the **VPS public IP**, yet all backends (immich, jellyfin, grafana, HA-standby, …) are containers on home hosts. The **home-LAN internal all-app edge** (`traefik-internal`) exists so `*.kogler.si` keeps working on the LAN regardless of WAN/VPS state: [services-rejected.md](services-rejected.md).

### Two-path serving model

| Path | Edge | Host | Clients | Names | Reaches (backends) | Survives |
|---|---|---|---|---|---|---|
| **Public** | `traefik` (Docker-labels, single ACME issuer, Cloudflare, Forward-Auth + CrowdSec) | VPS | WAN | public `*.kogler.si` | — (public-WAN only) | WAN-up (edge is on the VPS — dies with WAN) |
| **Tailnet/WG** | `traefik-tailnet` (file-provider, no Docker-labels) | VPS | tailnet + WG-S2S | all `*.kogler.si` (plain + `*.ts` twins) | VPS-local overlay + (via WG) oldsrv LAN-IP home backends | VPS + tunnel up |
| **Home-LAN** | **`traefik-internal`** (VIP + LAN-IP bound, file-provider) | oldsrv | Home VLAN + family Wi-Fi | all internal `*.kogler.si` → home edge | home-hosted on `oldsrv_home_ip`; VPS-hosted via `wg_s2s_vps.ip`:4443 (double-hop) | WAN-out, Pi-out, both (as long as oldsrv is up) |
| **HA/DNS edge** | Pi `traefik-ha` (VIP-bound, host-net) | Pi | LAN + local | `ha` + `dns-pi` → VIP (full table present) | local HA/VIP; standby backends on oldsrv LAN IP when oldsrv is up | oldsrv-out |

> **Route table = uniform across the three internal edges**: the SAME filename (`dynamic/routes.yml.j2` per edge) carries the FULL set on `traefik-tailnet`, `traefik-internal` and `traefik-ha`, so any name works from any reachable path. The VPS **public** edge is excluded (public-only). Per-instance **DNS** is what differs: home instances resolve home-hosted names → the oldsrv LAN IP (SSOT `oldsrv_home_ip`, LAN-direct), `ha`/`dns-pi` → the home VIP (SSOT `ha_vip`), VPS-hosted/other public → the VPS public IP (SSOT `dns_primary_ip`); the VPS primary resolves all → its edge (tailnet `vps-obs` / wg `:4443`).

### Topology

- **VPS `traefik-tailnet`** = the **tailnet/WG path** — home-hosted backends (media/*arr/seerr/… →
  `oldsrv_home_ip:<port>` over WG, the media-bridge pattern) are the **intended** shape but **not yet in the
  template**: no *arr/media routers exist on `traefik-tailnet/dynamic/routes.yml.j2`, so the tailnet
  leg of the mobile path stays unserved. ⚠ They cannot reuse the LAN publishes: those are
  **loopback-only** (jellyfin rule), and a cross-host edge needs `oldsrv_home_ip`-bound publishes — a
  deliberate second change. Still Authentik Forward-Auth on
  the edge, not public.
- **`traefik-internal` on oldsrv** = the **home-LAN resilience path**. Host-net, entrypoints bound to the home **VIP** (`ha-vip`):80/443 **and** the oldsrv **LAN IP** (`oldsrv_home_ip`):80/443, `net.ipv4.ip_nonlocal_bind=1`. Serves THE FULL route table (home-hosted + VPS-hosted via wg :4443 double-hop). File-provider routes (no Docker-labels — avoids router conflicts, same pattern as traefik-tailnet). Consumer-mode TLS (synced wildcard pair from the VPS issuer via traefik-cert-pull). **No Forward-Auth and no CrowdSec on this edge** — both depend on VPS containers (Authentik, CrowdSec LAPI); including them would fail exactly when this edge must survive (WAN-out). All home services carry **their own local login** (Jellyfin, Seerr, *arr built-in Forms auth). The edge runs **always** on oldsrv: it serves `ha` only when oldsrv owns the VIP (keepalived MASTER), while the non-`ha` routes serve from oldsrv's LAN IP regardless of VIP state — `ha-failover-api` cannot start a host service (it runs inside the standby HA container).
- **Pi `traefik-ha`** = the **HA/DNS edge** for the oldsrv-down case. Serves `ha` + `dns-pi` → VIP. Stays VIP-bound so it never fights `traefik-internal` for :443 (only the keepalived MASTER owns the VIP).
- **DNS (home LAN):** home-hosted app names (`media`/`jellyfin`, `seerr`, `seerrng`, *arr, `sab`, `torrent`) point at **oldsrv's LAN IP** on the home Technitium instances (oldsrv secondary + Pi tertiary); **`ha`/`dns-pi` keep pointing at the home VIP**. VPS primary keeps its public records (VPS edge target) for WAN/tailnet; **VPS-hosted names (foto/file/git/…) keep pointing at the VPS public IP on ALL instances** (their backends live on the VPS — the home edge reaches them via wg :4443 double-hop, and WAN clients reach them publicly). Tailnet/WAN DNS is the same on every instance. ⚠ **Not "everything → VIP"**: the VIP normally sits on the Pi, whose edge serves only `ha`/`dns-pi`, so pointing every app at the VIP regresses the normal case. Home-hosted apps point at **oldsrv's LAN IP** because the oldsrv edge serves them.
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

### Implementation

- **Home-edge IaC:** the `docker_services` entry `traefik-internal` on oldsrv — `templates/docker_services/traefik-internal/` (`docker-compose.yml.j2` host-net, VIP+LAN-IP entrypoints, `net.ipv4.ip_nonlocal_bind=1`, consumer TLS from pulled certs; `dynamic/routes.yml.j2` FULL route table + DEFAULT-store TLS). It follows the `traefik-ha`/`traefik-tailnet` patterns (file-provider, no docker labels, no ACME). The wildcard pair is pulled by the SAME `traefik-cert-pull` timer (script parametrized via `traefik_consumer_dir`); VPS pubkey authorization = documented owner step. **Route set (13 + VPS set):** `media` (jellyfin :8096), `seerr` (:5055), `seerrng` (:5055), `sonarr` (:8989), `radarr` (:7878), `lidarr` (:8686), `prowlarr` (:9696), `bazarr` (:6767), `profilarr` (:6868), `sab` (:8080), `torrent` (:8080), `ha` (→ VIP:8123), `dns-pi` (→ VIP → technitium-secondary:5380) + VPS-hosted (foto/file/git/ai) via `wg-s2s ip:4443`. **No Forward-Auth, no CrowdSec** (both depend on VPS containers). **Auth on the edge's *arr/downloaders = built-in Forms auth** — the edge must survive WAN-out, so each app owns its credentials (the old "built-in logins disabled" rule assumed WAN-up serving: [services-rejected.md](services-rejected.md)). Jellyfin/Seerr/SeerrNG keep local login (client apps / request portal).
- **DNS:** home Technitium instances (oldsrv secondary + Pi tertiary) resolve **home-hosted app names → oldsrv LAN IP**, and `ha`/`dns-pi` → home VIP; VPS primary + tailnet unchanged. Seed rows in `technitium-seed.yml` are per-instance conditioned on `svc.instance in ['secondary','secondary-pi']`.

### Certification

- **Single ACME issuer = VPS Traefik:** consumers (VPS traefik-tailnet bind-mount, Pi traefik-ha ha-cert-sync, **oldsrv traefik-internal via the parametrized traefik-cert-pull**) serve the synced wildcard pair; the issuer issues via Cloudflare DNS-01. `traefik_acme_issuer: true` only on the VPS. The home edge is **offline-safe for both TLS and auth** by design (synced certs + local app logins).
- **A consumer must never pull from itself.** A pull whose `SRC` names the consumer's own address asks its own
  box for `/opt/traefik/certs/`, gets `Permission denied (publickey)`, and the pair on disk simply ages — it
  stays valid for weeks, so nothing screams. Repo validators read the rendered repo, so live drift on the box is
  invisible to every gate, and an untagged block is invisible to every scoped converge too (`roles/*` entries in
  `home_servers.yml` get no implicit role tag, so `--tags docker_services` filters such a block out and still
  reports a green run). Guards: the cert-pull block is tagged `docker_services`; the deploying tasks **assert**
  the issuer address is neither empty nor this host (plain `assert`, check-mode safe); and both pull scripts
  (`traefik-cert-pull.sh`, Pi `ha-cert-sync.sh`) exit **90** when `SRC` names one of the host's own scope-global
  addresses — a self-pull otherwise exits 0, which is why this class of fault is expensive. **Scope of what is
  deployed:** oldsrv's copy is live; the Pi carries the guard from its next `home_assistant` converge — its pull
  works today, so the HA primary is not restarted just to install a guard; Spark's `spark-dashboard` copy picks
  it up at its own next `docker_services` converge (never run from a spark-backed session).
  Tag arithmetic: reaching the Pi's pull task takes `--tags home_assistant,ha_failover`,
  because the `include_tasks` is tagged `home_assistant` and the tasks inside are tagged `ha_failover,hd17`.
  ⏳ Open: nothing observes pair age at the consumers and nothing watches these units' result.
- **trusted_proxies:** HA must trust **all** edges that front it — Pi `traefik-ha` (Pi Home-IP/32, SSOT `dns_tertiary_ip`), **oldsrv `traefik-internal` (oldsrv Home-IP/32 — host-net source = oldsrv Home-VLAN IP, SSOT `oldsrv_home_ip`)** and the VPS edges (`traefik_edge_ips`/32, e.g. the oldsrv `traefik` label-edge bridge default) — so real client IPs are preserved (`ha_trusted_proxies` in group_vars/all/main.yml).

**Consumer cert-leg check — the one a stale pair cannot fake.** Run ON the consumer (`oldsrv`/`spark`:
`traefik-cert-pull`; Pi: `ha-cert-sync`). A running timer is not evidence: a self-pull exits `0` unless the
deployed guard fires.

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
`home_assistant` on the Pi) and never hand-edit `/usr/local/sbin/traefik-cert-pull.sh`. oldsrv's pair is valid
to **2026-11-20**.

> **Invariants of the edge model** (each is load-bearing):
>
> - **Split-horizon is by *reach*, not by *name*.** `ha.kogler.si`, `stats.kogler.si` and `home.kogler.si`
>   resolve to the same name everywhere; which edge answers is decided by topology + firewall + which
>   instance's Technitium you ask. Do not invent per-zone names.
> - **`.ts.kogler.si` twins exist for one reason:** they match no Docker provider on the tailnet edge, so they
>   can be routed with ACL-only auth. Anything else should use the plain name.
> - **Every internal app needs a *home* path.** DNS for home-hosted apps must resolve to a home address on the
>   home Technitium instances; a name that resolves only to the VPS makes LAN access depend on WAN — the defect
>   the home-LAN edge closes ([services-rejected.md](services-rejected.md)).
> - **File-provider routes on the tailnet edge** (no Docker labels) are what keep the public/`-public`
>   network separation intact while still routing internal apps from that instance.
> - **`traefik-ha` on the Pi is the HA/DNS edge**, not an internal all-app edge: VIP-bound, serving `ha` +
>   `dns-pi`, so it never fights `traefik-internal` for :443 (only the keepalived MASTER binds the VIP).
> - **One ACME issuer** (the VPS public edge); every other edge is a cert **consumer**.

## Cockpit Routes (file-provider, no Forward-Auth)

Cockpit is a host service (not a Docker container), so its routes are a Traefik
**file-provider** dynamic config: `/opt/traefik/dynamic/cockpit.yml` (deployed by the
`cockpit` Ansible role on oldsrv).

- `cockpit-nas.kogler.si` → `http://nas:9090` · `cockpit-oldsrv.kogler.si` → `http://oldsrv:9090` (host IPs per SSOT — backends derived from `network_static_hosts` in the template)
- **`cockpit-nas.ts.kogler.si` → the same `cockpit-nas` service**, on the `websecure-ts` entrypoint.
  That listener is oldsrv's own tailnet address — `{{ tailnet_oldsrv_ip }}:443`, never
  `0.0.0.0` — so the chain is: MagicDNS record (headscale `tailnet_ts_only_subdomains`) → tailnet ACL
  (`tag:dev:443`) → oldsrv's node → this router → Home VLAN → nas:9090. One backend, two doors.
  ✅ **The first hop is a fact, not a requirement:** `cockpit-nas` sits in
  `tailnet_ts_only_subdomains` and the live headscale config carries the record. ⛔ It belongs in that list and **not**
  in `tailnet_subdomains`, which renders BOTH namespaces (the plain + `.ts` ambiguity trap).
  **BOTH nodes serve the Cockpit tailnet surfaces.** A console route must not die with a *healthy* box — the
  same rule HA's tailnet answer follows; oldsrv can be powered off at the chassis button while the nas runs
  ([hardware-oldsrv.md](hardware-oldsrv.md) §Remote Management). Acceptance: **the name answers with either box
  shut**, not "answers off oldsrv".
  ⚠ The constraint that comes with it:
  `pi-oldsrv.ts.kogler.si` (the pi-web seat) and `cockpit-nas.ts.kogler.si` are both served by **oldsrv's own
  `websecure-ts` listener** — so the Pi leg needs its **own** tailnet listener + router on that box (never a
  re-point of the seat's name), and the name publishes **`tailnet: dual`** through the catalogue's dual-node
  mechanism, not a `tailnet_subdomains` bolt-on (that renders both namespaces).
  ⚠ **A published name and an `online` node are still not a route:** oldsrv's deployed
  `/opt/traefik/dynamic/cockpit.yml` carries only the two LAN `Host()` rules, so
  `Host: cockpit-nas.ts.kogler.si` against the tailnet listener answers **404** while headscale publishes that
  name and reports the node `online`. The `cockpit-nas-ts` router exists in the role template and is not
  deployed.
  ⏳ Deploy `cockpit.yml` on **both** edges — the Pi carries no cockpit router at all — then run the browser
  acceptance once per node.
  ⚠ **This path dies with oldsrv**, and so does the LAN route: `cockpit.yml` is rendered onto *oldsrv*, so a
  down oldsrv costs the healthy nas its console route too — normal behaviour here, not a nas fault.
  Decoupling = the VPS `traefik-tailnet` edge + a new nftables allow for VPS→nas:9090
  (route present, :22 allowed, :9090 not) — the nas runs no edge of its own by design.
- **Deliberately NO Authentik Forward-Auth**: Cockpit is a management surface with its
  own login and must stay reachable if Authentik is down. Internal-only (no public DNS
  record, WAN-blocked). **Carries `crowdsec-only@file`** (security.md §1 law: never zero
  edge protection).
- **Identity:** Cockpit is PAM-only — a working login needs a Linux account
  with a **password**. There is one dedicated
  password-bearing `maint` user **per cockpit host** — today that is `nas` + `oldsrv`, the only two hosts running
  the `cockpit` role — with the password generated by the AI and held in 1Password as `nas-cockpit_login` /
  `oldsrv-cockpit_login`; `sudo` group, **no NOPASSWD**, no SSH keys, excluded from `AllowUsers`, so it is a
  browser/console PAM identity and never a network key surface. It is also the plan's **break-glass seat** (the
  cockpit runs on `domen`, which stops being the human-only door). ⚠ `cockpit` is in the lockout set,
  so these converges run from the laptop, never oldsrv-converging-itself.
  ✅ `roles/cockpit/tasks/maint-user.yml` provisions
  `maint` on nas, and the converge itself asserts `GET /cockpit/login` → 200 with the vault password.
  ⏳ oldsrv: the converge is what is missing. The constraint lives in [security.md](security.md):
  Debian ships `/etc/pam.d/cockpit` with **no group restriction at all**, so the `cockpit-session` group
  is not a gate by itself — the role writes the `pam_succeed_if` rule that makes
  it one.
- Traefik must preserve the original Host header on these routes. The nas
  `cockpit-ws` `/cockpit/login` returns the same `401 authentication-failed` for
  `Host: 127.0.0.1:9090`, for `Host: cockpit-nas.kogler.si`, and for `Host:` +
  `Origin: https://cockpit-nas.ts.kogler.si` — the **login endpoint does not reject a proxied Host**, so
  a `.ts` name on another edge needs no cockpit-side allow-list to get through authentication. What is NOT
  proven: cockpit's documented Origin check bites on the **WebSocket handshake**, which this
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

## Cloudflare (DNS-only)

Cloudflare is used as the **DNS provider only** (registrar: domenca.com; nameservers `george`/`may.ns.cloudflare.com`). **No proxy** — real client IPs reach Traefik, so CrowdSec/rate-limiting see actual addresses.

- Public records: only the internet-facing subset (`kogler.si`, `foto`, `file`, `git`, `sso`, `ha`, `vpn`, **`matrix`**, **`chat`**).
- Internal-only hosts/services: **no public record**; WAN firewall blocks them (split-horizon).
- Certificates: wildcard `*.kogler.si` via ACME **DNS-01** (Cloudflare API token in 1Password `Homelab-ansible`). **Issuer = the VPS Traefik** (the single issuer; consumers of the synced pair = the VPS `traefik-tailnet` internal edge (bind-mounted `/opt/traefik/certs`) and the Pi `traefik-ha` edge (ha-cert-sync pull timer); single-issuer enforced in templates by `traefik_acme_issuer`).
- No orange-cloud/DDoS/geo-WAF layer — Traefik + CrowdSec handle edge security; direct exposure without
  Cloudflare DNS is the rejected alternative ([services-rejected.md](services-rejected.md)).

---

## Matrix Routing — `/_matrix/*` is NOT behind Forward-Auth

Matrix (**[`services-matrix.md`](services-matrix.md)**) skips Forward-Auth (like `ha`, and like the
native-OIDC services OpenCloud/`file`, Immich/`foto`, Open WebUI/`ai`). Native clients,
other servers (federation), and any future appservice bridges must reach `/_matrix/*` directly, so:

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
`office` (WOPI worker), `vpn`/headscale (native OIDC + control traffic), and `pairdrop` —
PUBLIC P2P share on BOTH `pairdrop.kogler.si` and
`drop.kogler.si` (one router, dual Host matcher; the LAN-only shape is in
[services-rejected.md](services-rejected.md)).
Abuse guards: CrowdSec bouncer + the app's built-in `RATE_LIMIT=true`; network isolation via
traefik-public-only attachment.
## The home-hosted names at the public edge

The VPS Technitium primary answers `media` / `seerr` / `seerrng` with `dns_primary_ip` and Cloudflare
publishes `media`, so the VPS edge must answer them too: `traefik/dynamic/routes.yml.j2` carries one router
per name on `websecure`, behind
`crowdsec-only@file` (own login → the [security.md](security.md) §1 law still requires the bouncer), and each
points at the **home edge**, not at the app:

```
client → VPS edge (Host rule, TLS from the issuer) → https://<oldsrv Home address>:443 (Host + SNI preserved)
       → traefik-internal's own route table → jellyfin / seerr / seerrng on loopback
```

Two rules this shape depends on:

- **Dial the home EDGE, not the app.** Jellyfin publishes on loopback only, so a backend URL aimed
  at the app from the VPS is a dead port; `oldsrv_home_ip:443` is reachable over WG S2S and keeps one
  behaviour for LAN and WAN clients, because the home edge applies its own rules to the forwarded `Host`.
  `passHostHeader: true` is what makes that work.
- **`serversTransports.<name>.servername` is mandatory.** The backend URL is an *address*; without an
  explicit SNI Go verifies the `*.kogler.si` wildcard against the IP and every handshake fails. It is a
  transport field, not a service field, so one transport per name — `home-edge-media`, `home-edge-seerr`,
  `home-edge-seerrng`.

Acceptance: a `curl` from the **traefik container's own network namespace** against
the home edge with SNI + `Host` preserved returns `302` with **no `-k`**, i.e. verified end to end.
`--resolve media.kogler.si:443:<VPS IP>` → `302 → /web/`, `/System/Info/Public` returns
Jellyfin JSON through the two hops, and `seerr`/`seerrng` return their own `307`.

## The `:80 → :443` redirect

`http://` is `301` on the home edge and on the public edge; the redirect is declared on `traefik`,
`traefik-internal` and `traefik-ha`. Two failure shapes keep this from being verifiable by reading a file:

1. **`HostRegexp(`{host:.+}`)` matches nothing on Traefik v3.** The `{name:regex}` template is v2 syntax. The
   rule parses, `GET /api/http/routers` reports the router **`enabled`**, and no request ever matches it.
   Proof on this host in a throwaway `traefik:v3.7.11` container: same file, same middleware —
   template form `404`, `HostRegexp(`.+`)` `301`. The v3-valid catch-all exists, so the harsher conclusion
   recorded in [services-rejected.md](services-rejected.md) ("rules must name the host") applies to *service*
   routes, not to a redirect catch-all.
2. **An edge can reference a middleware it never declares.** `docker logs traefik` says
   `middleware "redirect-to-https@file" does not exist` for `http-redirect@file` on entrypoint `web`, and the
   router serves nothing. Every edge must declare `redirect-to-https` in its own dynamic files.

⛔ **A router that cannot match and a middleware reference that
resolves to nothing are legal Traefik configuration.** The converge reads `changed=1, failed=0` either way.
The two probes that actually see this: `GET /api/http/routers` on an edge with the API enabled, and a real
`curl -i` against the cleartext entrypoint — never "the file says so".
