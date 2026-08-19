---
title: Authentik — Identity & SSO
role: detail
domain: services
status: active
tags: [services, authentik, sso, oidc]
---
# Authentik — Identity & SSO

> **Role:** Detail — OIDC identity provider, WebAuthn, 1Password integration.
> **Links to:** `services-traefik.md`, `deployment-secrets.md`, `deployment-compose.md`, `deployment-ansible.md`
> **Linked from:** `services.md`, `deployment-compose.md`, `index.md`

---

## Responsibilities

- **Single Sign-On (SSO)** via OIDC for all homelab services
- **Forward Auth** — Traefik middleware delegates auth checks to Authentik
- **MFA** — WebAuthn passkeys (1Password biometric), TOTP fallback
- **Conditional access** — home LAN (skip MFA) vs remote (require MFA)

---

## 1Password + Authentik Integration

### Setup
- Authentik in **Compatibility Mode** → 1Password autofill works correctly (solves split username/password flow)
- Family uses **1Password Passkeys** (WebAuthn) for biometric login

### Passwordless Flow
1. User clicks "Log in with Passkey" on Authentik
2. 1Password intercepts, prompts FaceID/TouchID/Master Password
3. Logged in — no typing, no password

---

## Docker Compose Key Points

```yaml
services:
  authentik-server:
    environment:
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
      AUTHENTIK_POSTGRESQL__PASSWORD: ${AUTHENTIK_PG_PASSWORD}
    networks:
      - services-internal
      - traefik-public

  authentik-worker:
    environment:
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
    networks:
      - services-internal
```

---

## Forward Auth Flow

```
User → Traefik (port 443)
     → CrowdSec bouncer (WAF check)
     → Authentik Forward Auth middleware
         ├─ Has valid session? → pass to app
         └─ No session? → redirect to sso.kogler.si
              → Login with 1Password passkey
              → Redirect back to app
     → App receives request (never sees unauthenticated traffic)
```

## OIDC client provisioning — Blueprint + secret-egress glue (chosen approach)

> **Decision:** Authentik OIDC providers/applications are declared as an **Authentik Blueprint**
> (idempotent config-as-code), and a small **secret-egress glue** copies the generated
> `client_id`/`client_secret` into the 1Password items the compose templates already `lookup()`.
> No OIDC provider is hand-created in the Authentik UI for a service. (Forward-Auth services need
> no provider at all.)

### How it works
1. **Blueprint (`ks-oidc.yml`)** declares the OIDC providers + applications idempotently
   (config-as-code): Open WebUI, Headscale, Matrix (Tuwunel), OpenClaw, OpenCloud (native OIDC,
   multi-redirect web + desktop + mobile). Concern = **shape** (providers, apps, flows, outposts).
2. **Secret-egress glue** runs once after blueprints apply: `GET /api/v3/core/providers/oauth2/`
   → reads the generated `client_id` + `client_secret` → writes them into the 1Password item the
   consuming compose/`lookup()` expects. Concern = **credentials**, which Blueprint deliberately
   keeps out of committed YAML. This is the *only* piece of your own glue; it closes the loop
   Option A alone leaves open.

The two concerns are split at their natural seam — **shape** (Blueprints) vs **credentials**
(glue) — so each goes to the mechanism natively better at it. Deploy ordering + the blueprint
volume live in [`deployment-compose.md`](deployment-compose.md); the glue step is referenced in
`deployment-ansible.md`.

### Authentication tokens (two, distinct scopes)
- `authentik-api_token` — **read-only** API token; the Authentik→NAS provisioning glue
  (`sync-authentik-users.sh`, D5/HD-131) uses this to *read* the `family` group.
- `authentik-provision_api` — **write-scoped** API token (issuer/app/flow/outpost endpoints only);
  used by the blueprint apply + secret-egress glue. Least-privilege: never the read token's scope.

### What stays manual (only two, one-time)
- Issuing the **write-scoped Authentik token** (`authentik-provision_api`) in the Authentik UI.
- The **first-login admin bootstrap** (WebAuthn/passkey enrolment) at `sso.kogler.si` + the
  bootstrap admin password (set once, sourced from 1Password `authentik_login`).

Everything else — provider/application creation, secret seeding into 1Password — is automated.

---

## Security Considerations

- **No app exposes its own login publicly** — all auth is handled at the Traefik layer
- **Trusted proxies** must be configured: `AUTHENTIK_TRUSTED_PROXIES` must include Traefik IP
- **Secrets** stored in 1Password `Homelab` vault, never in repo ([`deployment-secrets.md`](deployment-secrets.md))

---

## Matrix SSO (OIDC) — identity for the homeserver

Matrix (**[`services-matrix.md`](services-matrix.md)**) cannot sit behind Traefik Forward-Auth, so it
delegates auth **into the homeserver** instead: an Authentik **OIDC Provider** for Tuwunel and a
**Provider Application** (e.g. `Tuwunel Matrix`) — both declared in the Authentik **Blueprint**
(see *OIDC client provisioning* above), never hand-created.

```
Element / native client  →  homeserver /login/sso  →  Authentik OIDC  →  1Password passkey / TOTP
                                                                              ↓
                                                              Matrix access_token → client
```

- Register the OIDC client in **Tuwunel** (`well_known`/OIDC discovery → Authentik issuer `sso.kogler.si`).
- **Redirect URIs** must include Tuwunel's SSO callback (`https://matrix.kogler.si/_synapse/...` or Tuwunel's own `/login/sso`/oidc callback).
- The Authentik client **secret** goes to 1Password `Homelab` (never the repo).
- No bridges in Phase 1 (deferred — see [`services-matrix.md`](services-matrix.md)).