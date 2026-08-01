# Authentik — Identity & SSO

> **Role:** Detail — OIDC identity provider, WebAuthn, 1Password integration.
> **Links to:** `services-traefik.md`, `deployment-secrets.md`
> **Linked from:** `services.md`, `deployment-compose.md`

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

---

## Security Considerations

- **No app exposes its own login publicly** — all auth is handled at the Traefik layer
- **Trusted proxies** must be configured: `AUTHENTIK_TRUSTED_PROXIES` must include Traefik IP
- **Secrets** stored in 1Password `Homelab` vault, never in repo ([`deployment-secrets.md`](deployment-secrets.md))