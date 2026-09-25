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
**LDAP provider/outpost** (D7/HD-132) was planned to be declared here — **HD-360** adds it
(2026-09-14: still absent from the blueprint; the live LDAP enable is pending that row).

### Deploy ordering (in `vps.yml`)
Steps 2–4 map to the Ansible **Authentik pre-pass** (`roles/docker_services/tasks/prepass-authentik.yml`,
HD-162), which runs **before** the per-service deploy loop and is gated on `authentik` being in
`docker_services`. The loop (`deploy-service.yml`) additionally validates each rendered compose
file (`docker compose -f … validate`) before `up`. See
[`deployment-ansible.md`](deployment-ansible.md) §`docker_services`.

1. Deploy `authentik` (+ bundled pg/redis/ldap) — `docker compose up -d`.
2. **Apply the Blueprint** (`ks-oidc.yml`) — via the dedicated, externalized playbook
   `playbooks/authentik-blueprints.yml` (owner decision 2026-08-27: blueprints are rarely-changed
   integration wiring, so the ~45s one-shot was moved OUT of the routine docker_services lane; run
   this playbook explicitly when a blueprint file is edited, HD-230b/HD-268). Blueprint discovery
   never registers `/blueprints/custom/*` as instances, so hash-reapply never fires on its own;
   do NOT hand-create in the UI.
3. **Run the secret-egress glue** — for each declared provider, `GET /api/v3/core/providers/oauth2/`
   → seed the 1Password item (`openwebui_api`, `headscale_api`, `matrix_api`, `openclaw_api`,
   `opencloud_oidc`, `immich_oidc`, `forgejo_oidc`, `metabase_oidc`). (The OpenCloud Graph-API
   service account `opencloud-service_api` is NOT this glue's job — it is seeded by the
   `sync-authentik-users` rework, HD-145.)
4. Deploy the **OIDC consumers** — their compose `lookup()` now resolves real client creds.

Fail-closed (HD-65/91): the glue aborts loudly instead of rendering a consumer with an
empty/placeholder OIDC secret. It authenticates with an EPHEMERAL api-intent token minted per
run via `ak shell` and revoked on exit — NOT a persisted provision token: the former
`authentik-provision_api` was retired 2026-08-22 because authentik AUTO-ROTATES expiring
api-intent tokens (HD-216; any vault-stored copy dies within minutes). A durable persisted
token is possible only with `expiring=False` — recipe + mechanism:
[services-authentik.md](services-authentik.md) *API-token auto-rotation*.

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
[docs.immich.app/administration/oauth/](https://docs.immich.app/administration/oauth/) and
[integrations.goauthentik.io/media/immich/](https://integrations.goauthentik.io/media/immich/).
⚠ Both pages describe the settings as things you fill in on the **Administration → Settings** page; neither
offers an env-var form — that is the detail that cost this service six weeks.

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

⚠ **`enabled` is a setting, not a side-effect of the client creds — and in v3 it is not an env var either
(the corrected root cause, both halves measured 2026-09-25).** The login page showed only e-pošta/geslo while
the container carried `IMMICH_OAUTH_ISSUER_URL/CLIENT_ID/CLIENT_SECRET/SCOPE/STORAGE_LABEL_CLAIM`. The first
cut at this, written the same day, said “`oauth.enabled` defaults to **false**, so set `IMMICH_OAUTH_ENABLED`”
— **that fix was also wrong**: setting it, recreating the container, and re-reading the env changed nothing.
The real shape, read out of the shipped image (`ghcr.io/immich-app/immich-server:v3.2.2`):

- **Immich v3 has no OAuth environment variables at all.** `grep -rI 'IMMICH_OAUTH'` over
  `dist/` + `node_modules/` = **0 hits**; `dist/repositories/config.repository.js getEnv()` is a whitelist
  of *bootstrap* vars (`DB_*`, `IMMICH_MEDIA_LOCATION`, `IMMICH_LOG_LEVEL`, `IMMICH_CONFIG_FILE`,
  `IMMICH_WORKERS_*`, …) and OAuth is not in it.
- `dist/utils/config.js buildConfig()` takes the settings partial from **either** the DB row
  `system_metadata.key='system-config'` **or** a file when `IMMICH_CONFIG_FILE` is set — never from the
  environment. The Admin UI writes that row via `PUT /api/admin/config` (and the PUT is *refused* with
  “Cannot update configuration while IMMICH_CONFIG_FILE is in use” when the file variant is active).
- `services/server.service.js getFeatures()` returns `oauth: config.oauth.enabled` **from that config**; the
  login page renders the button off the feature flag. So the read-only ladder is
  `GET /api/server/features` → `oauth` · `GET /api/public/config` → `oauth.enabled` ·
  `GET /api/server/config` → `oauthButtonText`, and only then the button itself.

⇒ The values are IaC-owned but **not compose-owned**: `roles/docker_services/defaults/main.yml`
(`immich_oauth_*`) + 1Password `immich_oidc`, applied by `roles/docker_services/tasks/immich-seed.yml`
(login as `immich-admin_login` → read config → merge only the OAuth keys → PUT only on drift → re-read the
flag). The compose keeps a comment where the six dead vars used to sit.
**Why the DB and not `IMMICH_CONFIG_FILE`:** the file *replaces* the DB partial in `buildConfig()`, so it
would silently revert everything the family admin sets in the UI — the live row already carries
`storageTemplate.enabled=true` (the HD-135 originals-on-Box naming). An IaC-owned file wins on
drift-proofing and loses someone else's setting; a seed that touches only the keys it owns loses nothing.

⚠ **Why the seed logs in instead of using an API key:** system config has no API-key path and no admin CLI
in v3 — the only writable surface is the admin bearer token from `POST /api/auth/login`, hence the
`immich-admin_login` item (which is also the break-glass account if OIDC ever breaks; `passwordLogin.enabled`
is deliberately left true and `autoLaunch` false so the native page stays reachable).

⚠ **The trap that eats an afternoon (why the first SSO login must be a decision, not a click):** Immich links
an OIDC identity to an existing user **by email**, and `Auto Register` creates a **new empty library** for any
email it does not recognise — so an SSO login with the wrong email looks exactly like "my photos are gone" when
what happened is a second account. `immich_role`/`immich_quota` are **creation-only**, never re-synced, so the
role has to be right on the first login. **Decide which account owns the family library BEFORE the first
`domen` SSO login**, and verify with the family seat, not the `admin` password login (that proves the admin
seat, not the family one).

**What the seed writes (`immich_oidc` from 1Password for the creds, role defaults for the rest):**
`scope openid email profile`; claims `preferred_username` → storage label, `immich_role` → role
(`user`/`admin`), `immich_quota` → storage quota (claims are creation-only, not re-synced);
`buttonText Prijava z SSO`; `Auto Register` true; `Auto Launch` false (per-request override stays
`/auth/login?autoLaunch=0|1`); `Mobile Redirect URI Override` off → the custom scheme is used, only set it
if Authentik rejects that scheme (http(s)-forwarder workaround — **verified accepted 2026-09-25**, so it
stays off: `GET /application/o/authorize/` answers 302 for all three redirect URIs and 400 for a
not-registered control URI).

**Edge (already live):** `traefik.http.routers.immich.middlewares: crowdsec-only@file` — the
`authentik-forward-auth@file` label is NOT to be restored: a browser-redirect SSO layer in front of the
service swallows the mobile `app.immich:///oauth-callback` redirect.

**Live-verified 2026-09-25 (foto leg of HD-147):** issuer discovery `200` with
`issuer = https://sso.kogler.si/application/o/immich/`; `PUT /api/admin/config` → `200`;
`GET /api/server/features` → `oauth=true, oauthAutoLaunch=false, passwordLogin=true`;
`GET /api/server/config` → `oauthButtonText="Prijava z SSO"`. **The remaining acceptance is the human one**
— the button in a browser and the first `domen` OIDC login (deployment-manual.md §1.6b), which this doc
cannot prove from the API side. ⚠ Still open on this service: `immich_version` is ONE pin for TWO images
(server on the VPS, `immich-machine-learning` on oldsrv), and the pair sits SPLIT 3.2.2 / 3.1.0 while
oldsrv is off the network (HD-455).

### Forgejo / Metabase native-OIDC notes (HD-148)
- **Forgejo** (`git.`): callback `https://git.kogler.si/user/oauth2/<app-slug>/callback`; keep
  `crowdsec-only` edge; decide whether git-over-https/API pushes stay open or follow web SSO.
- **Metabase** (`sec.`): **RETIRED 2026-09-14** (removed from the VPS; future home oldsrv). Historically: Metabase OSS has **NO OIDC/SSO — paid Enterprise only** (image pinned in `group_vars/all/versions.yml`); the `metabase_oidc` provider was declared (Blueprint) only for a future Enterprise license, so the live route **stayed Forward-Auth**. A future oldsrv Metabase is a sandbox (no sources) and does **not** re-use this VPS Authentik OIDC provider — revisit only with an Enterprise license + VPS Authentik.

---

## Per-service SSO login ledger

What has been proven by an actual human login (not a 302), and what has not. The forward-auth tier is
verified by its redirect; native-OIDC services are verified by the session existing on the other side.

| Service | Tier | Proof | Status |
|---|---|---|---|
| `ai` (Open WebUI) | native OIDC | authorize works, **the callback 404s** — the app serves `/oauth/oidc/callback` since 0.11 and our redirect URI still says `/oauth2/callback` on both sides | ❌ **HD-458** (the ✅ this row carried since HD-219 was wrong) |
| `vpn` (Headscale) | native OIDC | owner login in the HD-219 era | ✅ then — **not re-verified 2026-09-25** (`ai` is the lesson: an old ✅ is not a current one) |
| `chat` (Element + Tuwunel) | homeserver SSO | `/_matrix/client/v3/login` advertises `m.login.sso` with the `authentik` IdP + owner login | ✅ 2026-09-25 |
| `file` (OpenCloud) | native OIDC (web) | owner login **and** a `.docx` open through the ONLYOFFICE WOPI chain in that session ([services-office.md](services-office.md)) | ✅ 2026-09-25 |
| `foto` (Immich) | native OIDC | the button, then an owner login as `domen` (see §Immich for how the settings get there) | ✅ 2026-09-25 |
| `git` (Forgejo) | native OIDC | `user/login` advertises `Sign in with authentik`; the source is registered by `deploy-service.yml`, `ENABLE_AUTO_REGISTRATION=true`, `/user/register` 404 by design | ✅ 2026-09-25 |
| `claw` (OpenClaw) | native OIDC | — | ⏳ desktop/mobile OAuth + CSP (HD-144) |
| `office` (ONLYOFFICE) | no auth surface (WOPI helper) | reached through `file` | ✅ by way of `file` |
| Forward-auth edge apps | Forward-Auth | 302 to `sso.` per HD-219 | ✅ |

⚠ **A green `GET /api/v3/...` or a working redirect is not a login.** Every ✅ above is a human in a
browser; the ⏳ rows have neither.

⚠ **Found while measuring the SSO surface (belongs to HD-47, not to auth):**
`https://kogler.si/.well-known/matrix/client` and `.../server` answer **302 → `sso.kogler.si`**, i.e. the
apex well-knowns a remote homeserver needs for the federation handshake are behind the Forward-Auth wall.
`matrix.kogler.si` serves both correctly (200 + JSON) and both hosts resolve publicly, but federation
resolves the **apex** (`kogler.si` = the `server_name`), so it lands on the login redirect. Excluding
`/.well-known/matrix/*` from Forward-Auth is the same rule class HD-47 already states for `/_matrix/*`.
No `_matrix._tcp` / `_matrix._https` SRV exists anywhere (public DoH: NXDOMAIN) — fine only if the
well-known path is made public.

---

## Related

- [Authentik — Identity & SSO](services-authentik.md) — the decision + Blueprint authoring notes
- [Docker Compose Specification](deployment-compose.md) — compose conventions the consumer templates follow
- [Ansible Role Catalog](deployment-ansible.md) — the pre-pass + deploy loop implementation
- [Secrets](deployment-secrets.md) — the `*_api`/`*_oidc` items the glue seeds
