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

> ⚠️ **Planning phase.** Docs and IaC are still evolving — content will change often. Do **not** chase small visual-only tweaks; make substantive, content-level, consistent edits.

---

## Stack Docs (cluster index)

Each `services-<x>.md` owns its catalog rows + detail. Cross-cutting facts (networks, subdomains) live here.

| Stack doc | Scope | role |
|-----------|-------|------|
| [Media](services-media.md) | Jellyfin, Seerr, Immich, *arr (Sonarr/Radarr/Lidarr/Prowlarr/Bazarr/Profilarr/Recyclarr) + storage/import | detail |
| [Downloads](services-downloads.md) | SABnzbd, qBittorrent, gluetun — USENET/torrent ingress + VPN | detail |
| [DNS](services-dns.md) | Technitium, Pi-hole | detail |
| [Utilities](services-utilities.md) | n8n, signal-cli, PairDrop, Stirling PDF | detail |
| [Admin](services-admin.md) | Forgejo, Renovate, CrowdSec, Metabase, Headscale, Kopia, DB Backup | detail |
| [Office](services-office.md) | ONLYOFFICE, OpenCloud, office bridge (cross-cutting) | detail |
| [AI Platform](services-ai.md) | LiteLLM, Open WebUI, Docling, OpenClaw, Qdrant, Ollama, Immich-ML | detail |
| [Matrix](services-matrix.md) | Tuwunel, Element Web | detail |
| [Finance](services-finance.md) | Actual Budget | detail |
| [Traefik — Reverse Proxy & Edge](services-traefik.md) | Traefik | detail |
| [Authentik — Identity & SSO](services-authentik.md) | Authentik | detail |
| [Observability](observability.md) | Alloy, Prometheus, Loki, Grafana, blackbox, Dozzle | — |

**Standalone (owned here, no stack doc):**
- **Homepage** (family launchpad, `kogler.si` root + `home`) — public Forward-Auth; status widget. **Moved to the VPS** (HD-180; implemented **HD-183** ✅ 2026-08-21): the route is the compose's Docker-provider labels, live on the VPS edge; reachability is widget/probe-based (no Docker socket).
- **Sunshine** — game streaming (manual start), AMD dGPU/VRAM.

**Non-services (link out to owning domain):**
- **Home Assistant standby** + **RaspberryMatic standby** → [`smart-home-failover.md`](smart-home-failover.md) (failover, not services catalog).

---

## Docker Networks

| Network | Purpose |
|---------|---------|
| traefik-public | Traefik ↔ exposed services |
| services-internal | App ↔ app communication |
| db-internal | Databases, fully isolated |
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
| `ai` | Open WebUI — AI chat/RAG, public, Authentik OIDC + CrowdSec-only (HD-101) |
| `git` | Forgejo |
| `ha` | Home Assistant (VIP, HA-native auth) |
| `vpn` | Headscale |
| `matrix` | Tuwunel homeserver — public/federated, `/_matrix/*` no Forward-Auth (Matrix-native SSO → Authentik) |
| `chat` | Element Web — Matrix-native SSO → Authentik |

> Note: `office` (ONLYOFFICE) and `git` (Forgejo) belong to `services-office.md` and `services-admin.md` resp. — subdomains shared here are cross-cutting.

**Admin Dashboards decision:** Traefik Dashboard included, internal-only (`traefik.kogler.si`, see `services-traefik.md`); CrowdSec Dashboard included, internal-only `sec.kogler.si` via Metabase + **CrowdSec Web UI** `csui.kogler.si` (HD-272, internal-only, Forward-Auth) — admin stack. **Portainer / Dockge — excluded** (single Ansible-templated compose model).

---

## Service Accessibility & Traefik URL mapping (SSOT)

> **Rule of thumb:** every HTTP(S) service is `https://<sub>.kogler.si` (port 443, wildcard cert via Traefik) — **no ports in URLs**. Backends bind private overlay addresses, never exposed directly.

- **Rule C (HTTP/S):** Traefik only, hostname-based, no ports.
- **Rule D (non-HTTP, bypass Traefik — direct IP + firewall):** DNS 53 · NUT 3493 · UPS web 80/443 · SNMP 161 · WireGuard · SSH/WinBox (Mgmt, trusted). Host IPs per [`network-addresses-generated.md`](network-addresses-generated.md) (SSOT).

### URL → backend (edge cases only)

| URL | Backend | Why it's here |
|-----|---------|---------------|
| `https://ha.kogler.si` | VIP (`ha-vip`) :8123, keepalived | VIP edge switches nodes; never "correct" to a node IP |
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