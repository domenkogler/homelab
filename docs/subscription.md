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

> Column **Valid until** doubles as the renewal reminder trigger (⏰ set a reminder ~1 month before expiry).

| Service | € / month | Valid until ⏰ |
|---------|-----------|----------------|
| 1Password (Family) | 5,75 € | 2027-06-24 |
| `kogler.si` domain | 1,88 € | 2029-04-09 |
| NZBGeek (Usenet indexer) | 0,93 € | 2027-02-13 |
| Eweka.nl (Usenet) | 2,50 € | 2027-11-11 |
| Telekom Slovenije (ISP) | 50,50 € | — (monthly) |
| Meteorblue (weather API) | **0,00 € (free)** | 2027-08-18 |

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

## Planned Subscriptions

| Service | Plan | Est. Cost | Status | Purpose |
|---------|------|-----------|--------|---------|
| Infomaniak kSuite | TBD | ~€3–5/mo | 🔮 Planned | Email, calendar (CalDAV), catch-all aliases |
| ~~iDrive e2~~ | ~~TBD bucket~~ | ~~~€5/mo~~ | ❌ **Dropped** | ~~S3 off-site backup~~ → replaced by a 2nd Hetzner Storage Box (HD-29/31) |

---

## Deferred Subscriptions (Phase 2+)

| Service | Plan | Est. Cost | Status | Purpose |
|---------|------|-----------|--------|---------|
| Contabo | Storage VPS 30 | ~€15/mo | 📦 Deferred | Public web stack |
| Hetzner | Storage Box (live) | ~€4/mo | 📦 Deferred | Live Immich-originals S3 + family SMB/WebDAV drives — nearest DC (HD-131 D1) |
| Hetzner | Storage Box (backup) | ~€4/mo | 📦 Deferred | Kopia off-site backup repo — far DC (Helsinki/Falkenstein, HD-29/31) |