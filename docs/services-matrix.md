---
title: Matrix — Messaging
role: ssot
domain: services
status: active
tags: [services, matrix, chat, messaging]
---
# Matrix — Messaging

> **Role:** Single source of truth — the Matrix messaging stack, domains, auth, federation posture, and the deferred-bridges decision.
> **Links to:** `services.md`, `services-traefik.md`, `services-authentik.md`, `interfaces.md`, `network-dns.md`, `manual/chat.md`
> **Linked from:** `index.md`, `services.md`

> ⚠️ **Phase 1 (planned, not yet deployed).** Nothing about Matrix is live. Decisions below are the
> authoring spec for the IaC (`docker_services` templates + `group_vars/home_servers.yml`) and the
> network/DNS records. IaC implementation is tracked as **HD-46**; public records/federation as **HD-47**;
> backup as **HD-49** (see [`todo.md`](../todo.md)). Bridges are **deferred** (Phase 2 best-effort) — HD-48.

---

## Goals

Family messaging that does **not** depend on any single commercial chat app: a self-hosted Matrix
homeserver with **Element Web** as the web client. Runs on `oldsrv` (Phase 1) alongside every other
service.

> **Scope (decided):** Phase 1 is **Matrix-native only** — family↔family in Matrix rooms. The family
> keeps WhatsApp/Signal native on their phones for the outside world. **Third-party bridges are
> deliberately deferred** (see [Bridges — deferred](#bridges--deferred-phase-2-best-effort)) because
> every bridge links a real external account and puts that account at ban/isolation risk without
> cleanly serving a whole family.

---

## FQDN & Components

| Component | FQDN / role | Notes |
|-----------|-------------|-------|
| **Tuwunel** (homeserver) | `matrix.kogler.si` | Rust homeserver — official successor to Conduwuit. Handles `/_matrix/*` (client-server + federation). **Public + federated.** |
| **Element Web** (web client) | `chat.kogler.si` | Static web client. **Matrix-native SSO → Authentik.** |

- **Container:** homeserver + Element Web on `oldsrv` (`traefik-public` + `services-internal`).
- **Storage:** Tuwunel uses a **RocksDB file store** (`database_path`, includes media) — **no external Postgres**; bind-mounted to `/srv/docker/matrix` on oldsrv and included in ZFS/Kopia backup (**HD-49**).
- **RAM (idle/peak MB, to validate after deploy):** Tuwunel 150–350 / 700 · Element Web 30–80 / 150.
  ≈ **180–430 idle / ≤ 900 peak** — comfortable on `oldsrv` (48 GB).

---

## Domain & Federation Decision

- **Homeserver name = `kogler.si`** (decided), **delegated** to the physical homeserver on
  `matrix.kogler.si` via `_matrix` well-known (client `/_matrix/client` + server `/_matrix/server`).
  User IDs are clean `@user:kogler.si`, and the name is **stable across future host moves** (e.g. a
  Phase-2 VPS): only the well-known pointer changes, never the user IDs / rooms / encrypted history.
- **Public + federated.** Needed because the family uses chat on phones/from outside the LAN. This
  **adds `matrix` and `chat` to the public internet-facing set** (the repo's public subset today:
  `kogler.si`, `home`, `sso`, `foto`, `file`, `git`, `ha`, `vpn`).
- The wildcard `*.kogler.si` cert (Cloudflare DNS-01) already covers both subdomains — no extra cert work.
- **Federation transport:** serve `matrix.kogler.si` through Traefik on **443/TLS** (federation-over-443).
  Optional listener on **8448** is not required. WAN firewall must allow 443 (and 8448 if used) **to oldsrv — `/_matrix/*` is NOT behind Forward-Auth.** See [`services-traefik.md`](services-traefik.md).

---

## Authentication — Matrix-native SSO (NOT Traefik Forward-Auth)

Unlike web apps that sit entirely behind Authentik Forward-Auth (e.g. `file`), Matrix **cannot** be
wrapped at the edge: native clients and other servers must reach `/_matrix/*` directly. Instead,
authentication is **delegated into the homeserver**:

```
Element Web (chat.kogler.si)
   └─ "Log in with SSO"  →  homeserver /login/sso  →  Authentik OIDC (sso.kogler.si)
                                                       └─ 1Password passkey / TOTP
                                → returns Matrix access_token to the client
Phones / Element X ─────────────  same homeserver /login/sso flow
```

- **Element Web is NOT wrapped in Traefik Forward-Auth** — that would force a double login (Authentik,
  then Matrix) and would not help native apps. The SSO is Matrix's own OIDC flow backed by Authentik.
- This is the one deviation from the repo rule *"No app exposes its own login publicly"* — document it
  explicitly; Matrix's public login endpoint is the homeserver itself, and Authentik is the identity
  source. Provider/application for Tuwunel lives in [`services-authentik.md`](services-authentik.md).

---

## Server Identity & Backup (Critical)

- The homeserver **signing key + room encryption keys** are the server's identity. **Losing them breaks
  all existing rooms / encrypted history.** They are **secrets**: keep in 1Password *and* include the
  identity file in the ZFS/Kopia backup (see [`backup.md`](backup.md)).
- Back up: homeserver Postgres DB (via `db-backup` / Kopia), the **media store**, and the signing/identity
  keys. Tracked as **HD-49**.

---

## Observability & Alerting (optional consolidation)

- Homeserver exposes metrics; scrape into Prometheus (`/metrics`) as part of the stack.
- **Optional:** expose a `#homelab` room and route Grafana alerts to it so alerting can also reach
  Matrix — alongside the existing Signal + SMTP fail-safe. See [`observability.md`](observability.md).

---

## Bridges — Deferred (Phase 2 best-effort)

WhatsApp / Messenger / Signal bridges are **not part of Phase 1**. Rationale (recorded decision):

- Every bridge links a **real external account**. In the multi-user model each family member who wants
  *their* contacts in Matrix links *their own* number → each personal number at ban/isolation risk
  (WhatsApp/Meta actively detect and block unofficial bridges; numbers are often 2FA for other services).
- Protected via **dedicated throwaway numbers**, a whole family needs several **and** a throwaway has
  **no real contacts**, so nobody's actual contacts are reachable — the model doesn't cleanly serve a family.

**Decision:** defer. Revisit **only if** the family explicitly asks for a specific bridge, and then
**only** against a **dedicated** number, accepting ongoing re-pairing and possible ban. Tracked as
**HD-48**.

---

## Related

- [Service Catalog](services.md) — catalog rows, networks, the public subdomain set
- [Traefik — Reverse Proxy & Edge](services-traefik.md) — Matrix routing, public records, no Forward-Auth on `/_matrix/*`
- [Authentik — Identity & SSO](services-authentik.md) — Matrix OIDC SSO provider/application
- [Interface Matrix](interfaces.md) — Element Web as a family interface
- [DNS / Delegation](network-dns.md) — `_matrix` well-known, public records
- [Družinski vodnik: klepet](manual/chat.md) *(Slovenian, wip)*
