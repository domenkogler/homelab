---
title: Service Subscriptions & Costs
role: reference
domain: governance
status: active
tags: [governance, subscriptions, costs]
---
# Service Subscriptions & Costs

> **Role:** Reference — all paid subscriptions, costs, renewal, and status.
> **Linked from:** `index.md`, `services.md`

---

## Active Subscriptions

> The schedule table below is **derived from `group_vars/subscriptions.yml` (SSOT)** —
> auto-generated to [`subscriptions-table-generated.md`](subscriptions-table-generated.md) by `render-docs.yml` / the
> docker_services post-deploy hook. Prose/billing/description sections below are hand-authored.
> Keep the `subscriptions` var updated; do not hand-edit the generated table.

📄 **[Full subscription schedule → subscriptions-table-generated.md](subscriptions-table-generated.md)**

---

## 1Password

| Item | Value |
|------|-------|
| Plan | **Family** |
| Billing | Annual · 12 months |
| Last payment | 69,00 € on 2026-06-24 |
| Effective price | 5,75 €/mo |
| Valid until | **2027-06-24** |
| ⏰ Renewal reminder | ~2027-05-24 (1 month before expiry) |
| Purpose | Secrets vault, passkeys, family sharing |

---

## `kogler.si` domain

| Item | Value |
|------|-------|
| Registrar | **domenca.com** |
| Billing | 5 years (paid up front) |
| Last payment | 112,85 € on 2024-03-26 |
| Effective price | 1,88 €/mo (~22,57 €/yr) |
| Valid until | **2029-04-09** |
| ⏰ Renewal reminder | ~2029-03-09 (1 month before expiry) |
| Nameserver 1 | `george.ns.cloudflare.com` |
| Nameserver 2 | `may.ns.cloudflare.com` |
| DNS provider | **Cloudflare** (DNS-only — no proxy) |
| Certificates | wildcard `*.kogler.si` via ACME **DNS-01** (Cloudflare API token in 1Password `Homelab`) |

See [`network-dns.md`](network-dns.md) for the split-horizon DNS scheme.

## NZBGeek

| Item | Value |
|------|-------|
| Type | **Usenet indexer** |
| Billing | 6 months |
| Last payment | 5,56 € on 2026-08-10 |
| Effective price | 0,93 €/mo |
| Valid until | **2027-02-13** |
| ⏰ Renewal reminder | ~2027-01-13 (1 month before expiry) |
| Purpose | NZB search/indexing for usenet downloads |

## Eweka.nl

| Item | Value |
|------|-------|
| Type | **Usenet provider** |
| Billing | 15 months |
| Last payment | 37,50 € on 2026-08-10 |
| Effective price | 2,50 €/mo |
| Valid until | **2027-11-11** |
| ⏰ Renewal reminder | ~2027-10-11 (1 month before expiry) |
| Purpose | Usenet access (retention / binary downloads) |

---

## Telekom Slovenije (ISP)

| Item | Value |
|------|-------|
| Plan | Fiber / ISP contract **1 Gbit/s down / 300 Mbit/s up** |
| Billing | Monthly |
| Cost | 50,50 €/mo |
| Valid until | — (ongoing, no fixed end date) |
| Purpose | PPPoE, static IP, `/56` IPv6 |

---

## netcup RS 2000 G12 (VPS)

| Item | Value |
|------|-------|
| Plan | **RS 2000 G12** (root server) |
| Provider | **netcup** |
| Billing | Annual · 12 months (prepaid) |
| Last payment | 263,52 € on 2026-08-18 |
| Effective price | 21,96 €/mo |
| Valid until | **2027-08-18** |
| ⏰ Renewal reminder | ~2027-07-18 (1 month before expiry) |
| Purpose | Public web stack (Authentik, OpenCloud web, Forgejo, Grafana) — replaces deferred Contabo Storage VPS 30 (HD-93/HD-40B); DBs stay on LAN over WireGuard |

---

## Meteorblue (weather API)

| Item | Value |
|------|-------|
| Type | **Weather forecast API** (HA core `meteoblue` integration, HD-22) |
| Plan | **Free / personal API key** |
| Cost | **0,00 €** (free tier) |
| Since | 2026-08-18 |
| Valid until | **2027-08-18** |
| ⏰ Renewal reminder | ~2027-07-18 (1 month before expiry) |
| Secret | `meteoblue_api` (1Password `Homelab`, API credential) |
| Purpose | Home Assistant single authoritative weather source (Maribor) — `configuration.yaml.j2` |

---

## Hetzner Storage Box — live (BX11 1 TB)

| Item | Value |
|------|-------|
| Type | **Hetzner Storage Box BX11** (1 TB) — live data (Immich originals + OpenCloud user files + family SMB/WebDAV drives) |
| Billing | Monthly |
| Cost | **3,90 €/mo** |
| Since | 2026-08-18 |
| 🔑 Secret | `Hertzner-SB-Data` (1Password `Homelab`, server: URL/username/password) |
| Host | `653411.your-storagebox.de` (server 653411) |
| SMB/CIFS share | `//u653411.your-storagebox.de/backup` |
| SSH/SFTP | port **23** — SSH key + password in 1Password |
| Protocols | SMB/CIFS, WebDAV, SSH (external reachability) |
| Purpose | **live Immich-originals + encoded-video + OpenCloud user files (WebDAV) + family SMB/WebDAV drives** (CIFS, **not S3** — HD-135) |

> ⚠ **SMB password:** SSH key alone works for SSH/SFTP (port 23). For **CIFS/SMB + WebDAV** mounts you
> need the box **password** set via the web UI — store it in 1Password `Hertzner-SB-Data` (so the `password`
> field matches the box, not just SSH-key auth).

---

## Hetzner Storage Box — backup (BX11 1 TB)

| Item | Value |
|------|-------|
| Type | **Hetzner Storage Box BX11** (1 TB) — **off-site backup leg** (house-loss protection) |
| Billing | Monthly |
| Cost | **3,90 €/mo** |
| Since | 2026-08-18 |
| 🔑 Secret | `Hertzner-SB-Backup` (1Password `Homelab` — connection ref: URL/username only, **no password**) |
| Host | `u653424.your-storagebox.de` (server/u 653424) |
| SSH/SFTP | port **23** — **reuse existing Hetzner SSH key**, no password |
| Protocols | SSH/SFTP only (SMB/WebDAV not enabled) |
| Purpose | Kopia off-site encrypted snapshots (DBs, configs, Immich originals) — survives house loss alongside VPS |

---

## Planned Subscriptions

| Service | Plan | Est. Cost | Status | Purpose |
|---------|------|-----------|--------|---------|
| Infomaniak kSuite | TBD | ~€3–5/mo | 🔮 Planned | Email, calendar (CalDAV), catch-all aliases |
| ~~iDrive e2~~ | ~~TBD bucket~~ | ~~~€5/mo~~ | ❌ **Dropped** | ~~S3 off-site backup~~ → replaced by Hetzner Storage Boxes (HD-29/31) |

---

## Deferred Subscriptions (Phase 2+)

| Service | Plan | Est. Cost | Status | Purpose |
|---------|------|-----------|--------|---------|
| ~~Contabo~~ | ~~Storage VPS 30~~ | ~~~€15/mo~~ | ✅ **Replaced** | Public web stack → bought **netcup RS 2000 G12** (263,52 €/12 mo, 2026-08-18) — see Active above |
| ~~Hetzner~~ | ~~Storage Box (live)~~ | ~~~€4/mo~~ | ✅ **Active/Bought** | see Active — BX11 1 TB, `Hertzner-SB-Data` |
| ~~Hetzner~~ | ~~Storage Box (backup)~~ | ~~~€4/mo~~ | ✅ **Active/Bought** | see Active — off-site Kopia leg, `Hertzner-SB-Backup` |