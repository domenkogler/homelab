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

> 🟢 **Live since 2026-08-22** on the VPS edge (Phase 1, HD-40A): wildcard `*.kogler.si` LE cert issued, middleware chains deployed, all enabled services routed. **Internal all-app edge = the VPS `traefik-tailnet` instance (HD-331 decision, live 2026-09-07) — re-decided 2026-09-09 (HD-349), re-scoped 2026-09-10:** a home-LAN internal all-app edge (**`traefik-internal` on oldsrv**, VIP-bound + LAN-IP) joins it so `*.kogler.si` keeps working on the LAN when WAN/VPS is down, and home-hosted apps (media / *arr / downloads) get a LAN + mobile path (see [§ Edge model](#edge-model--one-public--one-internal-all-app-edge--home-lan-resilience-edge-re-decided-2026-09-09-hd-349)). **HD-350 (2026-09-10): all three internal edges (VPS `traefik-tailnet` + this + Pi `traefik-ha`) now carry the FULL route table; per-instance split-horizon DNS** (home-hosted → `oldsrv_home_ip` on home instances; `ha`/`dns-pi` → VIP; VPS-hosted/others → VPS public IP). VPS edges stay the tailnet/WAN path. ⏳ deploy-gated: `traefik-ha` Pi edge (HD-17), router-side wiring (HD-03/60), home edge deploy (HD-350/352; HD-351 deleted), per-home cert-sync authorization. Sections below remain the implementation spec.

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
- **Collections (HD-85 / KOPS-041, `crowdsec_collections` group_var):** `traefik` + `linux` baseline, plus the exposed auth-surfaces `home-assistant`, `matrix` (Synapse/Tuwunel OIDC login brute-force), and `grafana`. **HD-313:** + `a1ad/mikrotik` (parser + `mikrotik-bf` + `mikrotik-scan-multi_ports`) for the RB4011/switch/AP remote RFC5424 syslog stream — the mikrotik collection carries the syslog parsing; there is NO separate `syslog-logs` collection in the hub (2026-09-03 live: `cscli` rejected it and crowdsec crash-looped — removed). Each collection only pays off where its logs reach CrowdSec via `docker.sock` container-log parsing (docker Acquis) or the syslog receiver (HD-313) — extend the var as more services are exposed.
- Community blocklist (IPs that attacked others)
- Free for personal use
- Container on `traefik-public` network

### CrowdSec Web UI (`csui.kogler.si`, HD-272)

- **Richer ops surface** alongside the Metabase CrowdSec view (`sec.kogler.si`, HD-242): alerts, decisions, metrics, notifications, multi-LAPI, OIDC SSO, read-only mode — a modern SPA (TheDuffman85/crowdsec-web-ui, `ghcr.io/theduffman85/crowdsec-web-ui`, pinned `crowdsec_web_ui_version`).
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

## Traefik-tailnet — the tailnet edge for admin dashboards (HD-135b follow-up, 2026-08-28)

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
- **Routes (file provider `dynamic/routes.yml`):** `stats`/`logs`/`csui`/`sec`/`traefik`/`auto`
  (`*.kogler.si` **and** `*.ts.kogler.si` each). The plain names carry **Authentik Forward-Auth**
  (same middleware definitions, per-instance copies); the `*.ts` names are **ACL-gated** (no forward-auth —
  the headscale ACL `tag:sidecar:443` is the gate, see [`network-vpn.md`](network-vpn.md)).
  **LIVE-VERIFIED 2026-09-03:** plain `*.kogler.si` → **302 → sso.kogler.si** (Forward-Auth reachable);
  `*.ts.kogler.si` twins → **200 / 301→https** (ACL-gated). **Root-cause note (HD-297c):** the earlier
  `middleware "authentik-forward-auth@file" does not exist` was a **render crash, not a loop skip** — the
  template's own comment carried a literal `{{ vault['…'] }}` bracket expression, which Jinja evaluates even
  inside `#` comments → `dict has no attribute '…'` → the middlewares render task failed → file never landed.
  Fixed in `fc2b0a1` (de-activate the brace to literal text; same sweep across 8 templates).
- **Dashboard:** this edge also serves the Traefik dashboard on `traefik.kogler.si` / `traefik.ts.kogler.si`
  (the public edge has no dashboard router — single owner of that name on the tailnet).
- **Auth key/secrets:** `tailscale-sidecar_api` (API Credential, `credential` = reusable tagged preauth key)
  in 1Password; fail-loud render (`_template_vault_items`).

## Edge model — one public + one internal all-app edge + home-LAN resilience edge (re-decided 2026-09-09, HD-349)

> **Decision (owner + AI, 2026-09-09):** supersedes the HD-331 (2026-09-04) model of a **VPS-only internal all-app edge**. The VPS-only design left a real gap, surfaced live by the 2026-09-09 failover drill: **when WAN is down, every internal app is unreachable from the LAN** because internal `*.kogler.si` records resolve to the **VPS public IP**, yet all backends (immich, jellyfin, grafana, HA-standby, …) are containers on home hosts. The re-decision adds a **home-LAN internal all-app edge** so `*.kogler.si` keeps working on the LAN regardless of WAN/VPS state.

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

- **VPS `traefik-tailnet`** = the **tailnet/WG path** — unchanged, but its route table now ALSO contains the home-hosted backends (media/*arr/seerr/… → `oldsrv_home_ip:<port>` over WG, the media-bridge pattern). This is how the **mobile leg** reaches home-hosted apps: phone → tailnet → VPS edge → WG → `oldsrv_home_ip`. Still Authentik Forward-Auth on the edge, not public.
- **NEW: `traefik-internal` on oldsrv** = the **home-LAN resilience path**. Host-net, entrypoints bound to the home **VIP** (`ha-vip`):80/443 **and** the oldsrv **LAN IP** (`oldsrv_home_ip`):80/443, `net.ipv4.ip_nonlocal_bind=1`. Serves THE FULL route table (home-hosted + VPS-hosted via wg :4443 double-hop). File-provider routes (no Docker-labels — avoids router conflicts, same pattern as traefik-tailnet). Consumer-mode TLS (synced wildcard pair from the VPS issuer via traefik-cert-pull). **No Forward-Auth and no CrowdSec on this edge** — both depend on VPS containers (Authentik, CrowdSec LAPI); including them would fail exactly when this edge must survive (WAN-out). All home services carry **their own local login** (Jellyfin, Seerr, *arr built-in Forms auth).
- **Pi `traefik-ha`** = the **HA/DNS edge** for the oldsrv-down case — unchanged. Serves `ha` + `dns-pi` → VIP. Stays VIP-bound so it never fights `traefik-internal` for :443 (only the keepalived MASTER owns the VIP).
- **DNS (home LAN):** home-hosted app names (`media`/`jellyfin`, `seerr`, `seerrng`, *arr, `sab`, `torrent`) point at **oldsrv's LAN IP** on the home Technitium instances (oldsrv secondary + Pi tertiary); **`ha`/`dns-pi` keep pointing at the home VIP**. VPS primary keeps its public records (VPS edge target) for WAN/tailnet; **VPS-hosted names (foto/file/git/…) keep pointing at the VPS public IP on ALL instances** (their backends live on the VPS — the home edge reaches them via wg :4443 double-hop, and WAN clients reach them publicly). This is the only DNS change; tailnet/WAN DNS is unchanged. Re-scoped 2026-09-10 from the original "everything → VIP" (VIP normally sits on the Pi, whose edge serves only `ha`/`dns-pi` — pointing every app at the VIP would regress the normal case; the home-hosted set is served by the oldsrv edge, so they point at oldsrv's LAN IP).
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

### Implementation (HD-350/352 — tracked in todo.md §2.1a; **HD-351 DELETED 2026-09-10**)

- **HD-350 — home-edge IaC (implemented):** new `docker_services` entry `traefik-internal` on oldsrv — `templates/docker_services/traefik-internal/` (`docker-compose.yml.j2` host-net, VIP+LAN-IP entrypoints, `net.ipv4.ip_nonlocal_bind=1`, consumer TLS from pulled certs; `dynamic/routes.yml.j2` FULL route table + DEFAULT-store TLS). Reuses the `traefik-ha`/`traefik-tailnet` patterns (file-provider, no docker labels, no ACME). The wildcard pair is pulled by the SAME `traefik-cert-pull` timer (script parametrized via `traefik_consumer_dir`); VPS pubkey authorization = documented owner step. **Route set (13 + VPS set):** `media` (jellyfin :8096), `seerr` (:5055), `seerrng` (:5055), `sonarr` (:8989), `radarr` (:7878), `lidarr` (:8686), `prowlarr` (:9696), `bazarr` (:6767), `profilarr` (:6868), `sab` (:8080), `torrent` (:8080), `ha` (→ VIP:8123), `dns-pi` (→ VIP → technitium-secondary:5380) + VPS-hosted (foto/file/git/ai) via `wg-s2s ip:4443`. **No Forward-Auth, no CrowdSec** (both depend on VPS containers). **Auth on the edge's *arr/downloaders = built-in Forms auth** — deliberate reversal of the old "built-in logins disabled" rule (that rule assumed routes served only while WAN/VPS is up; the home edge must survive WAN-out, so each app must own its credentials). Jellyfin/Seerr/SeerrNG keep local login (client apps / request portal). This also repairs the **lost-routes bug**: since HD-331 removed the oldsrv edge, media / *arr / downloads hosts have NO route today (labels only, unreachable across hosts).
- **HD-351 — DELETED (2026-09-10).** Original: "start `traefik-internal` on forward takeover." Unnecessary: the edge runs **always** on oldsrv; it only serves `ha` when oldsrv owns the VIP (keepalived MASTER), and the non-`ha` routes serve from oldsrv's LAN IP regardless of VIP state. `ha-failover-api` also cannot start a host service (it runs inside the standby HA container).
- **HD-352 — DNS re-point (implemented, 2026-09-10):** home Technitium instances (oldsrv secondary + Pi tertiary) resolve **home-hosted app names → oldsrv LAN IP**, and `ha`/`dns-pi` → home VIP; VPS primary + tailnet unchanged. Seed rows in `technitium-seed.yml` are per-instance conditioned on `svc.instance in ['secondary','secondary-pi']`. (Original "everything → VIP" regressed the normal case — VIP normally sits on the Pi, whose edge serves only `ha`/`dns-pi`.)

### Certification (unchanged rules)

- **Single ACME issuer = VPS Traefik** (HD-178/HD-181/HD-204): consumers (VPS traefik-tailnet bind-mount, Pi traefik-ha ha-cert-sync, **oldsrv traefik-internal via the parametrized traefik-cert-pull**) serve the synced wildcard pair; the issuer issues via Cloudflare DNS-01. `traefik_acme_issuer: true` only on the VPS. The home edge is **offline-safe for both TLS and auth** by design (synced certs + local app logins).
- **trusted_proxies:** HA must trust **all** edges that front it — Pi `traefik-ha` (Pi Home-IP/32, SSOT `dns_tertiary_ip`), **oldsrv `traefik-internal` (oldsrv Home-IP/32 — host-net source = oldsrv Home-VLAN IP, SSOT `oldsrv_home_ip`, HD-350)** and the VPS edges (`traefik_edge_ips`/32, e.g. the oldsrv `traefik` label-edge bridge default) — so real client IPs are preserved (`ha_trusted_proxies` in group_vars/all/main.yml).

### Original HD-331 decision (historical record, superseded)

> **Decision (owner + AI, 2026-09-04):** long-term reverse-proxy architecture = **one PUBLIC edge (WAN-only, public apps) + one INTERNAL all-app edge (serves EVERY app, public + internal) reached over Headscale tailnet AND WireGuard site-to-site**. Recorded here as the owning-doc decision; the `<domain>-rejected.md` log entry locks it against re-decide (HD-331). **→ SUPERSEDED 2026-09-09 (HD-349):** the VPS-only internal edge leaves **WAN-out = all internal apps dead on the LAN** (every internal app's DNS resolves to the VPS public IP, yet all backends live on home hosts). The new model (above) adds a home-LAN internal all-app edge on oldsrv to close this.

- **Public edge (unchanged):** the main `traefik` on the **VPS** — Docker-labels (docker provider), single ACME issuer (`traefik_acme_issuer: true`), Cloudflare A records, Forward-Auth + CrowdSec. Serves **only** the public `*.kogler.si` apps (per the catalog `public:` flag).
- **Internal all-app edge (growth of `traefik-tailnet`, VPS):** the SAME VPS instance (`traefik-tailnet`) routes **every** service — public apps (identical rules, but no WAN) **and** internal-only apps. Reached over the **tailnet (existing)** and the **WireGuard S2S**. File-provider routes (no Docker-labels) keep the public/`-public` Docker-network separation intact.
- **Same-zone split-horizon = same names, different reach:** `ha.kogler.si` / `stats.kogler.si` / `home.kogler.si` resolve the same inside + on tailnet/WG; reachability is gated by topology/firewall, **not** by which name resolves.
- **No `.ts` twins needed:** headscale `search_domains: [kogler.si]` + the VPS-primary split-horizon resolve plain `*.kogler.si` to the tailnet edge once every instance carries the full split-horizon set.
- **`traefik-ha` (Pi) stays:** a physical failover edge for the HA VIP, NOT the internal all-app edge — **unchanged in the re-decision; the Pi edge also survives oldsrv-out.**

## Cockpit Routes (file-provider, no Forward-Auth)
## Cockpit Routes (file-provider, no Forward-Auth)

Cockpit is a host service (not a Docker container), so its routes are a Traefik
**file-provider** dynamic config: `/opt/traefik/dynamic/cockpit.yml` (deployed by the
`cockpit` Ansible role on oldsrv).

- `cockpit-nas.kogler.si` → `http://nas:9090` · `cockpit-oldsrv.kogler.si` → `http://oldsrv:9090` (host IPs per SSOT — backends derived from `network_static_hosts` in the template, HD-188)
- **Deliberately NO Authentik Forward-Auth**: Cockpit is a management surface with its
own login and must stay reachable if Authentik is down. Internal-only (no public DNS
record, WAN-blocked). **Carries `crowdsec-only@file`** (security.md §1 law: never zero
edge protection — HD-188).
- Traefik must preserve the original Host header on these routes — cockpit-ws validates
  that the browser Origin matches Host.
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
`office` (WOPI worker, HD-166), `vpn`/headscale (native OIDC + control traffic), and since
**HD-230 (2026-08-23)** `pairdrop` — PUBLIC P2P share on BOTH `pairdrop.kogler.si` and
`drop.kogler.si` (one router, dual Host matcher; supersedes the HD-113 LAN-only decision).
Abuse guards: CrowdSec bouncer + the app's built-in `RATE_LIMIT=true`; network isolation via
traefik-public-only attachment.