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

> 🟢 **Live since 2026-08-22** on the VPS edge (Phase 1, HD-40A): wildcard `*.kogler.si` LE cert issued, middleware chains deployed, all enabled services routed. ⏳ deploy-gated: oldsrv-internal Traefik (Phase 3), `traefik-ha` Pi edge (HD-17), router-side wiring (HD-03/60). Sections below remain the implementation spec.

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
- Useful for tracing the routing/middleware chain; service metrics still flow to Prometheus (see [`observability.md`](observability.md)).
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
- Certificates: wildcard `*.kogler.si` via ACME **DNS-01** (Cloudflare API token in 1Password `Homelab-ansible`). **Issuer = the VPS Traefik** (HD-178 — the single issuer; oldsrv's internal edge and the Pi `traefik-ha` consume the synced pair; single-issuer enforced in templates by `traefik_acme_issuer`, HD-181).
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