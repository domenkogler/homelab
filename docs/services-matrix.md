---
title: Matrix — Messaging & Bridges
role: ssot
domain: services
status: active
tags: [services, matrix, chat, messaging]
---
# Matrix — Messaging & Bridges

> **Role:** Single source of truth — the Matrix messaging stack, bridges, domains, auth, and federation posture.
> **Links to:** `services.md`, `services-traefik.md`, `services-authentik.md`, `interfaces.md`, `network-dns.md`, `manual/chat.md`
> **Linked from:** `index.md`, `services.md`

> ⚠️ **Phase 1 (planned, not yet deployed).** Nothing about Matrix is live. Decisions below are the
> authoring spec for the IaC (`docker_services` templates + `group_vars/home_servers.yml`) and the
> network/DNS records. IaC implementation is tracked as **HD-46**; federation/public records as **HD-47**;
> bridge pairing as **HD-48**; backup as **HD-49** (see [`todo.md`](../todo.md)).

---

## Goals

Family messaging that does **not** depend on any single commercial chat app: a self-hosted Matrix
homeserver with **Element Web** as the web client, plus bridges so the family can reach their
existing **WhatsApp**, **Messenger**, and **Signal** contacts from one place. Runs on `oldsrv`
(Phase 1) alongside every other service.

---

## FQDN & Components

| Component | FQDN / role | Notes |
|-----------|-------------|-------|
| **Tuwunel** (homeserver) | `matrix.kogler.si` | Rust homeserver — official successor to Conduwuit. Handles `/_matrix/*` (client-server + federation). **Public + federated.** |
| **Element Web** (web client) | `chat.kogler.si` | Static web client. **Matrix-native SSO → Authentik.** |
| **mautrix-whatsapp** (bridge) | — (appservice) | WhatsApp ↔ Matrix. Phone-link (like `signal-cli`). |
| **mautrix-meta** (Messenger bridge) | — (appservice) | Facebook Messenger ↔ Matrix. |
| **mautrix-signal** (bridge) | — (appservice) | Signal ↔ Matrix. |

- **Container:** 4–5 containers on `oldsrv` (`traefik-public` + `services-internal`; homeserver DB on `db-internal`).
- **RAM (idle/peak MB, to validate after deploy):** Tuwunel 120–250 / 600 · Element Web 30–80 / 150 ·
  mautrix-whatsapp 80–150 / 300 · mautrix-meta 80–150 / 300 · mautrix-signal 60–120 / 250 · homeserver DB 100–200 / 400.
  ≈ **470–950 idle / ≤ 2 000 peak** — comfortable on `oldsrv` (48 GB).
- Bridges have **no user-facing FQDN** — they are administrable via Element (admin rooms / bot), not via a web UI.

---

## Domain & Federation Decision

- **Public + federated.** Needed because the family uses chat on phones/from outside the LAN and the
  bridges reach *external* contacts. This **adds `matrix` and `chat` to the public internet-facing set**
  (the repo's public subset today: `kogler.si`, `home`, `sso`, `foto`, `file`, `git`, `ha`, `vpn`).
- Homeserver name = `kogler.si`; **delegated** to `matrix.kogler.si` via well-known + SRV so `@user:kogler.si`
  IDs are clean without exposing the raw homeserver subdomain in every user ID (see [`network-dns.md`](network-dns.md)).
  The wildcard `*.kogler.si` cert (Cloudflare DNS-01) already covers both subdomains — no extra cert work.
- **Federation transport:** serve `matrix.kogler.si` through Traefik on **443/TLS** (federation-over-443).
  Optional listener on **8448** is not required. WAN firewall must allow 443 (and 8448 if used) **to oldsrv — `/_matrix/*` is NOT behind Forward-Auth.** See [`services-traefik.md`](services-traefik.md).

---

## Authentication — Matrix-native SSO (NOT Traefik Forward-Auth)

Unlike web apps that sit entirely behind Authentik Forward-Auth (e.g. `file`), Matrix **cannot** be
wrapped at the edge: native clients, other servers, and the bridges must reach `/_matrix/*` directly.
Instead, authentication is **delegated into the homeserver**:

```
Element Web (chat.kogler.si)
   └─ "Log in with SSO"  →  homeserver /login/sso  →  Authentik OIDC (sso.kogler.si)
                                                       └─ 1Password passkey / TOTP
                                → returns Matrix access_token to the client
Bridges (mautrix-*) ────────────  appservice tokens (independent of Authentik)
Phones / Element X ─────────────  same homeserver /login/sso flow
```

- **Element Web is NOT wrapped in Traefik Forward-Auth** — that would force a double login (Authentik,
  then Matrix) and would not help native apps. The SSO is Matrix's own OIDC flow backed by Authentik.
- This is the one deviation from the repo rule *"No app exposes its own login publicly"* — document it
  explicitly; Matrix's public login endpoint is the homeserver itself, and Authentik is the identity
  source. Provider/application for Tuwunel lives in [`services-authentik.md`](services-authentik.md).

---

## Bridges — Appservice Setup

| Bridge | Purpose | Pairing / risk |
|--------|---------|----------------|
| mautrix-whatsapp | WhatsApp contacts | Link a WhatsApp account (secondary/registered number — **anti-abuse risk: WhatsApp/Meta can block**; use a dedicated number, not the personal one) |
| mautrix-meta | Messenger contacts | Facebook account link; Meta anti-abuse risk |
| mautrix-signal | Signal contacts | Phone-link (second device), like the existing `signal-cli` → a **second SIM / dedicated number** if needed |

- Bridges are logged in as **appservice users** under names like `@whatsappbot:kogler.si`; the family
  talks to contacts by adding the bridge bot to a room.
- **Ongoing maintenance, not fire-and-forget:** WhatsApp/Meta actively detect unofficial bridges and
  periodically show "link this device" screens or block. Expect occasional re-pairing. Only worth
  committing to if the family actually uses it — these can be dropped per-bridge without touching the rest.
- **Secrets → 1Password `Homelab`:** bridge login/QT tokens, appservice registration tokens, homeserver
  DB credentials, signing keys. See [`deployment-secrets.md`](deployment-secrets.md).

---

## Server Identity & Backup (Critical)

- The homeserver **signing key + room encryption keys** are the server's identity. **Losing them breaks
  all existing rooms / encrypted history.** They are **secrets**: keep in 1Password *and* include the
  identity file in the ZFS/Kopia backup (see [`backup.md`](backup.md)).
- Back up: homeserver Postgres DB (via `db-backup` / Kopia), the **media store**, and the signing/identity
  keys. Tracked as **HD-49**.

---

## Observability & Alerting (optional consolidation)

- Homeserver + bridges expose metrics; scrape into Prometheus (`/metrics`) as part of the stack.
- **Optional:** expose a `#homelab` room and route Grafana alerts to it (a lightweight bot/webhook) so
  alerting can also reach Matrix — alongside the existing Signal + SMTP fail-safe. This is a *consolidation
  opportunity*, not a replacement; see [`observability.md`](observability.md).

---

## Related

- [Service Catalog](services.md) — catalog rows, networks, the public subdomain set
- [Traefik — Reverse Proxy & Edge](services-traefik.md) — Matrix routing, public records, no Forward-Auth on `/_matrix/*`
- [Authentik — Identity & SSO](services-authentik.md) — Matrix OIDC SSO provider/application
- [Interface Matrix](interfaces.md) — Element Web as a family interface
- [DNS / Delegation](network-dns.md) — `_matrix` well-known + SRV, public records
- [Družinski vodnik: klepet](manual/chat.md) *(Slovenian, wip)*
