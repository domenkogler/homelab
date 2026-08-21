---
title: Authentik OIDC Provisioning
role: design-spec
domain: deployment
status: active
tags: [deployment, authentik, oidc, blueprint]
---
# Authentik OIDC Provisioning — Blueprint + Secret-Egress Glue

> **Role:** ★ Design spec — read this to **provision or correct** Authentik OIDC wiring for any
> homelab service: the Blueprint (`ks-oidc.yml`) + secret-egress glue contract, deploy ordering,
> and the per-service native-OIDC recipes (OpenCloud, Immich, Forgejo, Metabase). Split out of
> [`deployment-compose.md`](deployment-compose.md) (HD-199); that doc stays pure compose conventions.
> **Links to:** `services-authentik.md`, `deployment-compose.md`, `deployment-ansible.md`, `deployment-secrets.md`
> **Linked from:** `deployment-compose.md`, `services-authentik.md`, `index.md`

---

## Decision

OIDC providers/applications are declared as an **Authentik Blueprint**; a
**secret-egress glue** copies the generated client creds into 1Password. See
[`services-authentik.md`](services-authentik.md) *OIDC client provisioning* for the decision.
This file is the compose/provisioning-side contract.

### Blueprint volume (authentik compose template)
The `authentik-server` service mounts a **`blueprints/`** volume (alongside the existing
`/templates`): Authentik applies the Blueprint idempotently at startup / on demand. The
`ks-oidc.yml` Blueprint declares the OIDC providers + applications for Open WebUI, Headscale,
Matrix (Tuwunel), OpenClaw, OpenCloud (native OIDC, multi-redirect), **Immich, Forgejo, Metabase**
(HD-148). Optionally the Authentik
**LDAP provider/outpost** (D7/HD-132) is also declared here, removing a manual UI create-step.

### Deploy ordering (in `vps.yml`)
Steps 2–4 map to the Ansible **Authentik pre-pass** (`roles/docker_services/tasks/prepass-authentik.yml`,
HD-162), which runs **before** the per-service deploy loop and is gated on `authentik` being in
`docker_services`. The loop (`deploy-service.yml`) additionally validates each rendered compose
file (`docker compose -f … validate`) before `up`. See
[`deployment-ansible.md`](deployment-ansible.md) §`docker_services`.

1. Deploy `authentik` (+ bundled pg/redis/ldap) — `docker compose up -d`.
2. **Apply the Blueprint** (`ks-oidc.yml`) — via Authentik API (`authentik-provision_api`) or the
   bundled blueprint on container start.
3. **Run the secret-egress glue** — for each declared provider, `GET /api/v3/core/providers/oauth2/`
   → seed the 1Password item (`openwebui_api`, `headscale_api`, `matrix_api`, `openclaw_api`,
   `opencloud_oidc`, `immich_oidc`, `forgejo_oidc`, `metabase_oidc`). (The OpenCloud Graph-API
   service account `opencloud-service_api` is NOT this glue's job — it is seeded by the
   `sync-authentik-users` rework, HD-145.)
4. Deploy the **OIDC consumers** — their compose `lookup()` now resolves real client creds.

Fail-closed (HD-65/91): the glue aborts loudly if `authentik-provision_api` is missing, rather than
rendering a consumer with an empty/placeholder OIDC secret.

### OpenCloud native-OIDC switch (HD-52)
For OpenCloud, native OIDC (desktop/mobile client) requires, in the `opencloud` compose:
- uncomment the `OC_OIDC_ISSUER` / `PROXY_OIDC_*` / `OC_EXCLUDE_RUN_SERVICES: idm` block;
- remove the `traefik.http.routers.opencloud.middlewares: authentik-forward-auth@file` label;
- add `sso.kogler.si` to OpenCloud `csp.yaml` `connect-src`/`frame-src`.
The Authentik provider itself is a **Blueprint entry** (multi-redirect web + desktop + mobile), so
no UI creation is needed.

### Immich native-OIDC note (HD-148)
Immich v3 mobile is OAuth-capable; its default mobile redirect is the custom scheme
`app.immich:///oauth-callback`. Per the official Immich OAuth docs (Authentik is first-class):

**Authentik client profile (confidential):** Provider type OIDC/OAuth2, **Confidential** client,
Application type **Web**, Grant type **Authorization Code** (no `implicit`). `issuer_url` =
`https://sso.kogler.si/application/o/immich/` (the `.well-known/openid-configuration` suffix is
auto-appended on discovery).

**Redirect URIs (Authentik provider `redirect_uris` must include all):**
- `app.immich:///oauth-callback` — **mobile** (MUST be present for iOS/Android)
- `https://foto.kogler.si/auth/login` — web login
- `https://foto.kogler.si/user-settings` — web manual OAuth link
- optional **Backchannel logout**: `https://foto.kogler.si/api/oauth/backchannel-logout`
For local debugging also allow `http://localhost:2283/auth/login` + `http://localhost:2283/user-settings`.

**Immich env/config (`immich_oidc` from 1Password):** `scope openid email profile`; claims
`preferred_username` → storage label, `immich_role` → role (`user`/`admin`), `immich_quota` →
storage quota (claims are creation-only, not re-synced); `Auto Register` true, optional `Auto Launch`
(per-request `/auth/login?autoLaunch=0|1`). `Mobile Redirect URI Override` empty → uses the custom scheme;
only set it if Authentik rejects the custom scheme (http(s)-forwarder workaround, deploy-verify).

**Edge changes in the `immich-app` compose:**
- add the config above (client creds from 1Password `immich_oidc`, issuer/scope/claims);
- **remove** the `traefik.http.routers.immich.middlewares: authentik-forward-auth@file` label
  (would block the mobile OAuth redirect).

### Forgejo / Metabase native-OIDC notes (HD-148)
- **Forgejo** (`git.`): callback `https://git.kogler.si/user/oauth2/<app-slug>/callback`; keep
  `crowdsec-only` edge; decide whether git-over-https/API pushes stay open or follow web SSO.
- **Metabase** (`sec.`): **Metabase OSS has NO OIDC/SSO — it is a paid Enterprise feature** (image
  pinned in `group_vars/all/versions.yml`). The `metabase_oidc` provider is declared (Blueprint)
  only for a future Enterprise license; with OSS the route **stays Forward-Auth** (free, works).
  If Enterprise is ever licensed: switch this route to `crowdsec-only` + enable `MB_OIDC_*`
  (single provider, `https://sec.kogler.si/auth/sso` callback).

---

## Related

- [Authentik — Identity & SSO](services-authentik.md) — the decision + Blueprint authoring notes
- [Docker Compose Specification](deployment-compose.md) — compose conventions the consumer templates follow
- [Ansible Role Catalog](deployment-ansible.md) — the pre-pass + deploy loop implementation
- [Secrets](deployment-secrets.md) — the `*_api`/`*_oidc` items the glue seeds
