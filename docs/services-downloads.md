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
  `/mnt/nas/media/downloads/complete/<cat>` and the arr logs the import as **Hardlink**, not Copy.
  ⚠ Not pinned in IaC — an ini value the wizard owns; a fresh install re-defaults it to the local disk.

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

## Related
- [Media stack](services-media.md) — the *arr pipeline + storage layout this feeds
- [Store](storage.md) — ZFS layout, `bulk/media` dataset
- [Services index](services.md) — catalog legend + network/subdomain SSOT