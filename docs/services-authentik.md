---
title: Authentik — Identity & SSO
role: detail
domain: services
status: active
tags: [services, authentik, sso, oidc]
---
# Authentik — Identity & SSO

> **Role:** Detail — OIDC identity provider, WebAuthn, 1Password integration.
> **Links to:** `services-traefik.md`, `deployment-secrets.md`, `deployment-compose.md`, `deployment-oidc.md`, `deployment-ansible.md`
> **Linked from:** `services.md`, `deployment-compose.md`, `index.md`

> 🟢 **IaC done, not yet live — ⏳ deploy-gated.** Authentik is IaC-authored (`docker_services` templates + `ks-oidc.yml` Blueprint + secret-egress glue) but **not live** — it deploys on the VPS during Phase 1 (HD-40A), and the OIDC provisioning chain (Blueprint + glue) is deploy-gated ⏳ (HD-142/143/147/149). Decisions below are the authoring spec, not a live system.

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
   multi-redirect web + desktop + mobile), **Immich** (HD-148: web + `app.immich:///oauth-callback`),
   **Forgejo** + **Metabase** (HD-148). Concern = **shape** (providers, apps, flows, outposts).
2. **Secret-egress glue** runs once after blueprints apply: `GET /api/v3/core/providers/oauth2/`
   → reads the generated `client_id` + `client_secret` → writes them into the 1Password item the
   consuming compose/`lookup()` expects. Concern = **credentials**, which Blueprint deliberately
   keeps out of committed YAML. This is the *only* piece of your own glue; it closes the loop
   Option A alone leaves open.

The two concerns are split at their natural seam — **shape** (Blueprints) vs **credentials**
(glue) — so each goes to the mechanism natively better at it. Deploy ordering + the blueprint
volume live in [`deployment-oidc.md`](deployment-oidc.md); the glue step is referenced in
`deployment-ansible.md`.

### Blueprint authoring notes (verified against Authentik source, 2026-08-19 — HD-149)

> Local validation: **`scripts/validate_blueprints.py`** parses Blueprint YAML (custom `!Find`/`!KeyOf`
> tags) and fails on the mistakes below — run it (or `scripts/validate-all.sh`) before committing a
> blueprint change.
>
> These four facts were **verified against `goauthentik/authentik` `main`** (blueprints + models) on
> 2026-08-19 and the `ks-oidc.yml` blueprint was corrected to match. Follow them when adding any
> future OIDC provider/app to the blueprint:

1. **Flow slugs (both have the `default-` prefix).** The default provider-authorization flow slug is
   `default-provider-authorization-implicit-consent` (NOT `provider-authorization-implicit-consent` —
   omitting `default-` makes the `!Find` return null and the blueprint import fails). The default
   *authentication* flow slug is `default-authentication-flow`. ⚠ Do NOT point `authentication_flow`
   at the authorization slug — they are different flows.
2. **Signing key:** `!Find [authentik_crypto.certificatekeypair, [name, authentik Self-signed Certificate]]`
   is correct — Authentik's default bootstrap cert carries that exact name.
3. **`sub_mode: hashed_user_id`** is correct (it is the OAuth2Provider model default).
4. **Provider→application binding:** there is **NO `authentik_providers_oauth2.application` model.**
   The `authentik_core.application` model carries a `provider` OneToOneField, so bind via
   `provider: !KeyOf <provider-id>` **inside the application entry's `attrs`**. Do NOT use a separate
   link entry (`model: authentik_providers_oauth2.application` + `application:`/`provider:` `!Key`
   refs) — that model does not exist and the import fails.

**Canonical 2-entry pattern (per OIDC consumer):**

```yaml
- model: authentik_providers_oauth2.oauth2provider
  id: provider_<svc>
  attrs:
    name: <svc>
    authentication_flow: !Find [authentik_flows.flow, [slug, default-authentication-flow]]
    authorization_flow: !Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]
    client_type: confidential
    redirect_uris: |
      https://<svc>.kogler.si/<callback>
    signing_key: !Find [authentik_crypto.certificatekeypair, [name, authentik Self-signed Certificate]]
    sub_mode: hashed_user_id
- model: authentik_core.application
  id: app_<svc>
  attrs:
    name: <Service Name>
    slug: <svc>
    meta_launch_url: https://<svc>.kogler.si
    provider: !KeyOf provider_<svc>
```

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
- **Secrets** stored in 1Password `Homelab-ansible` vault, never in repo ([`deployment-secrets.md`](deployment-secrets.md))

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
- The Authentik client **secret** goes to 1Password `Homelab-ansible` (never the repo).
- No bridges in Phase 1 (deferred — see [`services-matrix.md`](services-matrix.md)).