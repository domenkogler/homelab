---
title: Service Catalog — Central Stack Index
role: index
domain: services
status: active
tags: [services, catalog, index]
---
# Service Catalog — Central Stack Index

> **Role:** Index — the central services hub. Catalog legend, shared SSOT facts (Docker Networks, Domain & Subdomain Plan, URL→backend), and links to each per-domain `services-<x>.md` stack doc. Per-service detail lives in the stack docs, not here.
> **Links to:** `services-traefik.md`, `services-authentik.md`, `services-matrix.md`, `services-finance.md`, `services-office.md`, `services-ai.md`, `services-media.md`, `services-downloads.md`, `services-dns.md`, `services-utilities.md`, `services-admin.md`, `observability.md`, `deployment-compose.md`, `subscription.md`
> **Linked from:** `index.md`, `deployment-ansible.md`

> Most of this catalog is **live**; the rows that are not carry an explicit ⏳/⚠ in their stack doc. IaC
> (`IaC/ansible/group_vars/*`) is the per-service SSOT — this index only aggregates and points.

---

## Stack Docs (cluster index)

Each `services-<x>.md` owns its catalog rows + detail. Cross-cutting facts (networks, subdomains) live here.

| Stack doc | Scope | role |
|-----------|-------|------|
| [Media](services-media.md) | Jellyfin, Seerr, SeerrNG, Immich, Navidrome, *arr (Sonarr/Radarr/Lidarr/Prowlarr/Bazarr/Profilarr/Recyclarr) + storage/import | detail |
| [Downloads](services-downloads.md) | SABnzbd, qBittorrent, gluetun — USENET/torrent ingress + VPN | detail |
| [DNS](services-dns.md) | Technitium (ad blocking = Technitium Advanced Blocking; Pi-hole is retired) | detail |
| [Utilities](services-utilities.md) | n8n, signal-cli, PairDrop, Stirling PDF | detail |
| [Admin](services-admin.md) | Forgejo, Renovate, CrowdSec, Headscale, Kopia, DB Backup · **Homelable (HD-45, oldsrv, deploy-gated)** · Metabase is retired (revival = oldsrv) | detail |
| [Office](services-office.md) | ONLYOFFICE, OpenCloud, office bridge (cross-cutting) | detail |
| [AI Platform](services-ai.md) | LiteLLM (VPS + LAN), Open WebUI, Docling, OpenClaw, Qdrant · **spark = big-model generation (vLLM behind `llm.kogler.si`)** · **pinned-AI tier on the oldsrv RX 7600: `whisper` / `reranker` / `embed` (Vulkan), Ollama = embed fallback rung** · Immich-ML (oldsrv GPU, lowest priority) | detail |
| [Matrix](services-matrix.md) | Tuwunel, Element Web | detail |
| [Finance](services-finance.md) | Actual Budget | detail |
| [Traefik — Reverse Proxy & Edge](services-traefik.md) | Traefik | detail |
| [Authentik — Identity & SSO](services-authentik.md) | Authentik | detail |
| [Observability](observability.md) | Alloy, VictoriaMetrics, VictoriaLogs, Grafana, blackbox, Dozzle (VPS viewer `logs` + **LAN hub `llogs`** on oldsrv w/ pi+spark agents) · **mcp-victoriametrics / mcp-victorialogs (HD-344, oldsrv, deploy-gated)** | — |

**Standalone (owned here, no stack doc):**
- **Homepage** (family launchpad, `kogler.si` root + `home`) — public behind Forward-Auth, with the HA-failover status widget. Lives on the **VPS**: the route is the compose's Docker-provider labels at the VPS edge; reachability is widget/probe-based (no Docker socket).
- **Sunshine** — game streaming (manual start, `restart: "no"`), AMD dGPU **gaming-encode first**; immich-ML batch is pause-able GPU consumer (prep-commands). Idle ~5 W when neither gaming nor ML.

**Non-services (link out to owning domain):**
- **Home Assistant standby** + **RaspberryMatic standby** → [`smart-home-failover.md`](smart-home-failover.md) (failover, not services catalog).

---

## Docker Networks

| Network | Purpose |
|---------|---------|
| traefik-public | Traefik ↔ exposed services |
| services-internal | App ↔ app communication |
| db-internal | Databases, fully isolated |
| llm-backend | **Pinned-AI inference tier ↔ LiteLLM only** (HD-59): `ollama` (embed fallback rung) + the HD-391 Vulkan legs `whisper` / `reranker` / `embed` on oldsrv. Fully isolated because none of those APIs has auth — the network IS the boundary; no publish, no labels. Owner doc: [services-ai.md](services-ai.md) §3a-1 |
| wireguard-s2s | WireGuard S2S tunnel home router ↔ VPS (HD-03/HD-135; reaches home VLANs + wg-vps-services) |

> CIDRs: [`network-addresses-generated.md`](network-addresses-generated.md) → *Infrastructure networks* (SSOT).

> **Network codes (used in every catalog table):** `P` = traefik-public (edge) · `I` = services-internal
> (app ↔ app) · `D` = db-internal (isolated) · `W` = wireguard-s2s (home router ↔ VPS S2S tunnel)
> · `host` = host process / host docker.sock, not on an overlay (Linux). (Doco-CD removed — HD-150.)

> **Catalog convention:** subdomains relative to `kogler.si`; RAM = approx **idle / peak MB** (estimates to
> validate with `container_memory_working_set_bytes` after deploy — `observability.md`).

---

## Domain & Subdomain Plan

- **Single namespace:** `kogler.si`. Public DNS (Cloudflare, **DNS-only**), local DNS (Technitium, split-horizon).
- One wildcard `*.kogler.si` cert via Cloudflare DNS-01.
- **Placement (HD-99):** public/edge/GitOps/observability tier → **VPS**; GPU/LAN/storage-bound core → **oldsrv**. Subdomains/URLs are host-agnostic. See [`services-vps.md`](services-vps.md).

### Everything is internal by default
The catalog stack docs list each service's subdomain. **Only** the following subset gets a Cloudflare record and a WAN allow; everything else is **internal-only** (no public record, WAN-blocked; defense in depth).

| Subdomain | Service |
|-----------|---------|
| `kogler.si` (root) + `home` | Homepage — public, behind Authentik Forward-Auth |
| `sso` | Authentik |
| `foto` | Immich |
| `file` | OpenCloud |
| `bin` | Zipline (HD-112) — public viewer/share routes + guest dropzone uploads; dashboard native OIDC; `crowdsec-only` tier |
| `office` | ONLYOFFICE — browser editor UI via Traefik (WOPI helper, JWT-auth, no user auth itself — HD-166) |
| `pairdrop` | PairDrop public (HD-230) — P2P browser file transfer (signaling-only server), `crowdsec-only` tier (no Forward-Auth) |
| `pdf` | Stirling PDF — public, `authentik-forward-auth` (SSO login) |
| `ai` | Open WebUI — AI chat/RAG, public, Authentik OIDC + CrowdSec-only (HD-101) |
| `git` | Forgejo |
| `ha` | Home Assistant (VIP, HA-native auth) |
| `vpn` | Headscale |
| `matrix` | Tuwunel homeserver — public/federated, `/_matrix/*` no Forward-Auth (Matrix-native SSO → Authentik) |
| `chat` | Element Web — Matrix-native SSO → Authentik |
| `drop` | PairDrop public alt-host (HD-230) — same instance as `pairdrop.kogler.si`; P2P browser file transfer, `crowdsec-only` tier (no Forward-Auth, abuse-guard by CrowdSec + built-in rate limit) |

> Note: `office` (ONLYOFFICE) and `git` (Forgejo) belong to `services-office.md` and `services-admin.md` resp. — subdomains shared here are cross-cutting.

**Admin Dashboards:** the **five** admin dashboards — `stats` (Grafana), `traefik` (dashboard), `logs` (Dozzle), `csui` (CrowdSec UI), `auto` (n8n) — are **tailnet-only** over the `traefik-tailnet` edge: no public records, reached at `https://<app>.kogler.si` or `https://<app>.ts.kogler.si` on the tailnet (see `services-traefik.md` → **traefik-tailnet**). The **LAN log hub `llogs.kogler.si`** (Dozzle on oldsrv, showing oldsrv+pi+spark via remote agents) is **LAN-only** — served by the traefik-internal home edge for WAN-out survival, never the VPS/tailnet. **Portainer / Dockge are excluded** — there is one Ansible-templated compose model, so a container manager would only fork it.
>
> **Homelable** (HD-45) — the network/rack *topology* visualizer, on **oldsrv** and internal-only (no public record; it must sit on the LAN to scan it). Reached at `http://<oldsrv-home-ip>:3000` on the LAN (tailnet route = future tail, see [`services-admin.md`](services-admin.md) §Homelable). Not one of the tailnet-edge dashboards above — those run on the VPS; Homelable runs where the network is. Deployment spec + onboarding: [`services-admin.md`](services-admin.md) §Homelable.

---

## Service Accessibility & Traefik URL mapping (SSOT)

> **Rule of thumb:** every HTTP(S) service is `https://<sub>.kogler.si` (port 443, wildcard cert via Traefik) —
> **no ports in URLs**. Backends bind private overlay addresses, never exposed directly. The one deliberate
> exception is a LAN tool reached by IP:port because it must scan the LAN (Homelable).

- **Rule C (HTTP/S):** Traefik only, hostname-based, no ports.
- **Rule D (non-HTTP, bypass Traefik — direct IP + firewall):** DNS 53 · NUT 3493 · SNMP 161 · WireGuard · SSH/WinBox (Mgmt, trusted). The UPS has **no web-UI firewall path** (its NIC sits on IoT 20 with no WAN; monitoring is NUT/USB). Host IPs per [`network-addresses-generated.md`](network-addresses-generated.md) (SSOT).

### URL → backend (edge cases only)

| URL | Backend | Why it's here |
|-----|---------|---------------|
| `https://ha.kogler.si` | VIP (`ha-vip`) :8123, keepalived | VIP edge switches nodes (Pi `traefik-ha` normal → oldsrv `traefik-internal` on takeover, HD-349); never "correct" to a node IP |
| `https://dns-pi.kogler.si` | VIP (`ha-vip`) → Pi `traefik-ha` → `pi:5380` | Pi edge — reachable when oldsrv is down |
| `https://cockpit-nas.kogler.si` | `nas:9090` (IP per SSOT) | host service (not Docker) |
| `https://cockpit-oldsrv.kogler.si` | `oldsrv:9090` (IP per SSOT) | host service |

> The executable half lives in the Traefik labels in `IaC/ansible/templates/docker_services/*/docker-compose.yml.j2`.

**Cockpit scope:** nas + oldsrv only. The Pi is managed via SSH/Ansible + HA Web UI.

**`ha` route coupling (VIP, must-not-break):** see [`smart-home-failover.md`](smart-home-failover.md).

---

## Related
- [Traefik — Reverse Proxy & Edge](services-traefik.md) · [Authentik — Identity & SSO](services-authentik.md)
- [Matrix](services-matrix.md) · [Finance](services-finance.md) · [Office](services-office.md) · [AI](services-ai.md)
- [Observability](observability.md) · [Docker Compose Spec](deployment-compose.md) · [Subscriptions](subscription.md)