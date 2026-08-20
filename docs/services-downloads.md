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

> ⚠️ **Planning phase — not yet deployed.** Downloads services are IaC-authored but **not live**; deploy-gated against `deployment-tasks.md`.

---

## Catalog

Subdomains are relative to `kogler.si`. Network codes: see [Docker Networks](services.md#docker-networks) in `services.md`; exposure per the [Domain & Subdomain Plan](services.md#domain--subdomain-plan).

| Service | Subdomain | Network | RAM (idle/peak MB) | Description |
|---------|-----------|---------|--------------------|-------------|
| SABnzbd | sab | P+I | 90–150 / 500 | Usenet downloader → Eweka (NL), plain LAN (no VPN) |
| qBittorrent | torrent | P+I (via gluetun) | 80–130 / 300 | Torrent downloader — VPN-locked, only egress via VPN |
| gluetun | — | P+I | 15–30 / 50 | WireGuard sidecar → PrivadoVPN (NL); only qBittorrent routes through it |

## VPN & Ingress

- **VPN:** only qBittorrent egress → gluetun (WireGuard, PrivadoVPN, Netherlands — same region as Eweka usenet). SABnzbd stays on the plain LAN (usenet is a licensed service, no VPN needed).
- qBittorrent routes through the gluetun network namespace; no direct host port.

## Landing & Import

- Downloads land in `bulk/media/downloads/{complete,incomplete}` (TRaSH per-category save paths) — see
  [Media Stack → Storage & Import](services-media.md#storage--import-media--arr).
- **Hardlink import** into `media/` is performed by Sonarr/Radarr/Lidarr in the media stack; downloads
  dir is transient scratch and pruned after import.

## Related
- [Media stack](services-media.md) — the *arr pipeline + storage layout this feeds
- [Store](storage.md) — ZFS layout, `bulk/media` dataset
- [Services index](services.md) — catalog legend + network/subdomain SSOT