---
title: Authentik OIDC Provisioning
role: design-spec
domain: deployment
status: active
sensitivity: infra
tags: [deployment, authentik, oidc, blueprint]
---
# Authentik OIDC Provisioning — Blueprint + Secret-Egress Glue

> **Role:** ★ Design spec — read this to **provision or correct** Authentik OIDC wiring for any
> homelab service: the Blueprint (`ks-oidc.yml`) + secret-egress glue contract, deploy ordering,
> and the per-service native-OIDC recipes (OpenCloud, Immich, Forgejo). It is the
> OIDC side of [`deployment-compose.md`](deployment-compose.md), which stays pure compose conventions.
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
Matrix (Tuwunel), OpenClaw, OpenCloud (native OIDC, multi-redirect), **Immich, Forgejo**.
No LDAP provider/outpost is declared here — NAS SMB auth is local tdbsam
([storage.md](storage.md) §Samba (SMB) shares).

### Deploy ordering (in `vps.yml`)
Steps 2–4 map to the Ansible **Authentik pre-pass** (`roles/docker_services/tasks/prepass-authentik.yml`),
which runs **before** the per-service deploy loop and is gated on `authentik` being in
`docker_services`. The loop (`deploy-service.yml`) additionally validates each rendered compose
file (`docker compose -f … validate`) before `up`. See
[`deployment-ansible.md`](deployment-ansible.md) §`docker_services`.

1. Deploy `authentik` (+ bundled pg/redis) — `docker compose up -d`.
2. **Apply the Blueprint** (`ks-oidc.yml`) — via the dedicated, externalized playbook
   `playbooks/authentik-blueprints.yml`. Blueprints are rarely-changed integration wiring, so the
   ~45s one-shot is deliberately NOT part of the routine `docker_services` lane: run this playbook
   explicitly when a blueprint file is edited. Blueprint discovery
   never registers `/blueprints/custom/*` as instances, so hash-reapply never fires on its own;
   do NOT hand-create in the UI.
3. **Run the secret-egress glue** — for each declared provider, `GET /api/v3/core/providers/oauth2/`
   → seed the 1Password item (`openwebui_api`, `headscale_api`, `matrix_api`, `openclaw_api`,
   `opencloud_oidc`, `immich_oidc`, `forgejo_oidc`). The OpenCloud Graph-API
   service account `opencloud-service_api` is NOT this glue's job.
4. Deploy the **OIDC consumers** — their compose `lookup()` now resolves real client creds.

Fail-closed: the glue aborts loudly instead of rendering a consumer with an
empty/placeholder OIDC secret. It authenticates with an EPHEMERAL api-intent token minted per
run via `ak shell` and revoked on exit — NOT a persisted provision token: authentik AUTO-ROTATES
expiring api-intent tokens, so any vault-stored copy dies within minutes. A durable persisted
token is possible only with `expiring=False` — recipe + mechanism:
[services-authentik.md](services-authentik.md) *API-token auto-rotation*.

### OpenCloud native-OIDC switch
For OpenCloud, native OIDC (desktop/mobile client) requires, in the `opencloud` compose:
- uncomment the `OC_OIDC_ISSUER` / `PROXY_OIDC_*` / `OC_EXCLUDE_RUN_SERVICES: idm` block;
- remove the `traefik.http.routers.opencloud.middlewares: authentik-forward-auth@file` label;
- add `sso.kogler.si` to OpenCloud `csp.yaml` `connect-src`/`frame-src`.
The Authentik provider itself is a **Blueprint entry** (multi-redirect web + desktop + mobile), so
no UI creation is needed.

### Immich native-OIDC note
Immich v3 mobile is OAuth-capable; its default mobile redirect is the custom scheme
`app.immich:///oauth-callback`. Per the official Immich OAuth docs (Authentik is first-class):
[docs.immich.app/administration/oauth/](https://docs.immich.app/administration/oauth/) and
[integrations.goauthentik.io/media/immich/](https://integrations.goauthentik.io/media/immich/).
⚠ Both pages describe the settings as things you fill in on the **Administration → Settings** page; neither
offers an env-var form.

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

⚠ **`enabled` is a setting, not a side-effect of the client creds — and in v3 it is not an env var
either.** Setting `IMMICH_OAUTH_ISSUER_URL/CLIENT_ID/CLIENT_SECRET/SCOPE/STORAGE_LABEL_CLAIM` on the
container changes nothing, and there is no `IMMICH_OAUTH_ENABLED` to set either. The shape, read out of
the shipped image (`ghcr.io/immich-app/immich-server:v3.2.2`):

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
flag).
**Why the DB and not `IMMICH_CONFIG_FILE`:** the file *replaces* the DB partial in `buildConfig()`, so it
would silently revert everything the family admin sets in the UI — the live row already carries
`storageTemplate.enabled=true` (the originals-on-Box naming). An IaC-owned file wins on
drift-proofing and loses someone else's setting; a seed that touches only the keys it owns loses nothing.

⚠ **Why the seed logs in instead of using an API key:** system config has no API-key path and no admin CLI
in v3 — the only writable surface is the admin bearer token from `POST /api/auth/login`, hence the
`immich-admin_login` item (which is also the break-glass account if OIDC ever breaks; `passwordLogin.enabled`
is deliberately left true and `autoLaunch` false so the native page stays reachable).

⚠ **The first SSO login must be a decision, not a click:** Immich links
an OIDC identity to an existing user **by email**, and `Auto Register` creates a **new empty library** for any
email it does not recognise — so an SSO login with the wrong email looks exactly like "my photos are gone" when
what happened is a second account. Verify with the family seat, not the `admin` password login (that
proves the admin seat, not the family one).

**What the claims actually do here — read live, not from the setting names.** The config points at
`immich_role` and `immich_quota`, but the Authentik provider `immich` carries only the
`openid`/`email`/`profile` mappings and the server has **no** property mapping named for Immich at all, so
**neither claim is ever in the profile**. Upstream's own wording matches what that produces: claims are applied
at registration and "claims that are absent from the profile are left unchanged" (and from v3.3.0 claims that
ARE present re-sync on every login — a version boundary, since the deployed server is 3.2.x). So role and quota
are not IdP-managed in this deployment at all: they are whatever registration defaulted to — the SSO seat
`domen@kogler.si` reads `isAdmin=false` (role `user`) with `quotaSizeInBytes` NULL (**unlimited**), and the
break-glass seat `admin@kogler.si` reads `isAdmin=true`, also unlimited, with a password hash present and the
SSO seat having none (which is the intended shape: break-glass can enter by password, the family seat cannot).
Per-user quotas would need a property mapping that MINTS `immich_quota` on the provider — a scope decision, not
a re-save.

✅ **The SSO seat `domen@kogler.si` IS the family library**; `admin@kogler.si` stays a break-glass seat whose
assets are upload tests, so there is nothing to migrate and `Auto Register` costs nothing here. Both seats'
assets are test uploads by the owner's ruling — the live count is 4 on the native seat (2 JPEG + 2 MP4, one
2026-07-27 capture pair ×2) and 2 on the SSO seat, so the "2 assets" figure some notes still carry is stale.
Deleting them is an irreversible act on a photo store whose own row miscounts it, so it stays an owner act.
`admin`'s password login needs no separate ritual: `immich-seed.yml`'s first leg IS that login
(`POST /api/auth/login`), so a green seed leg — and one ran on the 2026-10-30 `docker_services_scope=immich-app`
converge with the container left running — is the proof, and it fails loudly if the password stops working.

**The family library shape, answered from upstream rather than guessed.** "One account per member, each adding
their own captures to one shared album" is the documented album model: a shared album's members are editors
(read-write) or viewers (read-only), and "the shared users can view **and add their own** photos and videos to
the shared album" ([docs.immich.app/features/sharing](https://docs.immich.app/features/sharing/)). The live
schema agrees — `album_user_role_enum` = `owner|editor|viewer` — and the instance has **0 albums** today, so the
target model is unbuilt, not blocked.

**Cross-account face recognition exists and is OFF here.** Cluster groups shipped in **v3.2.0** ("have people
recognized across trusted users") and shared people management in **v3.3.0** (share a person with another user in
your cluster group; cross-user merging), with people-sharing fixes in v3.3.1 — so the practical floor is v3.3.1,
not the deployed 3.2.x. Forming or joining a cluster group **requires re-running facial recognition for every
user in it**, which loses names and birth dates. Live: the two seats sit in **two different** cluster groups,
which is the per-user default — cross-account recognition is off, and turning it on is an owner act with a
re-recognition cost attached, not a config tweak.

**What the seed writes (`immich_oidc` from 1Password for the creds, role defaults for the rest):**
`scope openid email profile`; claims `preferred_username` → storage label, `immich_role` → role
(`user`/`admin`), `immich_quota` → storage quota (claims are creation-only, not re-synced);
`buttonText Prijava z SSO`; `Auto Register` true; `Auto Launch` false (per-request override stays
`/auth/login?autoLaunch=0|1`); `Mobile Redirect URI Override` off → the custom scheme is used, only set it
if Authentik rejects that scheme (the http(s)-forwarder workaround). It stays off:
`GET /application/o/authorize/` answers 302 for all three redirect URIs and 400 for a
not-registered control URI.

**Edge (live):** `traefik.http.routers.immich.middlewares: crowdsec-only@file` — the
`authentik-forward-auth@file` label is NOT to be restored: a browser-redirect SSO layer in front of the
service swallows the mobile `app.immich:///oauth-callback` redirect.

**Live (foto):** issuer discovery `200` with
`issuer = https://sso.kogler.si/application/o/immich/`; `PUT /api/admin/config` → `200`;
`GET /api/server/features` → `oauth=true, oauthAutoLaunch=false, passwordLogin=true`;
`GET /api/server/config` → `oauthButtonText="Prijava z SSO"`. **The remaining acceptance is the human one**
— the button in a browser and the first `domen` OIDC login (deployment-manual.md §1.6b), which this doc
cannot prove from the API side. ⚠ Still open on this service: `immich_version` is ONE pin for TWO images
(server on the VPS, `immich-machine-learning` on oldsrv), and the pair sits SPLIT 3.2.2 / 3.1.0 — the ML leg
can be converged.

### Forgejo native-OIDC notes
- **Forgejo** (`git.`): callback `https://git.kogler.si/user/oauth2/<app-slug>/callback`; keep
  `crowdsec-only` edge; decide whether git-over-https/API pushes stay open or follow web SSO.
- **Metabase** — **no entry in this doc, by design**: Metabase OSS has **no OIDC/SSO** (paid
  Enterprise only), so there is no client to declare and the service logs in natively on
  `metabase.kogler.si` (oldsrv). A future Enterprise license would be a new decision, not a re-enable
  of something here — see [services-admin.md](services-admin.md) §Metabase.

### Open WebUI native-OIDC note — the callback path

`ai.kogler.si` runs Authentik SSO on the callback path this build actually serves,
**`/oauth/oidc/callback`**, and it is a **two-sided invariant**: `OPENID_REDIRECT_URI` in
`templates/docker_services/open-webui/docker-compose.yml.j2` and `provider_openwebui.redirect_uris` in
`authentik/blueprints/ks-oidc.yml` are the SAME string and move together, in one change. Moving one side
only reads as an IdP outage. Against the shipped build:

- The callback is served at **`/oauth/oidc/callback`** — `main.py:2652` registers
  `@app.get('/oauth/{provider}/login/callback')` and `:2653` the legacy `/oauth/{provider}/callback`,
  with the provider slug `oidc`. The same route set is registered by 0.11.x and 0.12.x, so the path is
  not a pin-specific detail.
- **`/oauth2/callback` does not exist in this build** (there is no `routers/oauth2.py`), so that path falls
  through to the SPA shell — every unmatched URL returns `index.html`, and the client router has no such
  route either. A 200 + HTML on a callback path therefore means *no route ran*; a 3xx off the same request
  means the app's own handler ran. That contrast is the read-only way to tell "route exists" from "route
  is missing" without a browser.
- Everything upstream is what makes the flow *start*: `OPENID_PROVIDER_URL` + client id/secret satisfy the
  provider-registration gate at `config.py:2678`, so `OAUTH_PROVIDERS['oidc']` exists and discovery is
  fetched. `OPENID_REDIRECT_URI` is then handed to the provider verbatim (`config.py:2694`).
- OWUI's `config` table holds **no** `oauth.*` rows, so env is authoritative here. That is the opposite of
  Immich (§Immich: env is inert, the DB is the only surface) — the same defect class with opposite
  remedies, which is why the standing rule is: **read the shipped build to find which surface it actually
  consults, before choosing env or a seed.**
- **Proving the return leg without an admin token or a browser**, in this order:
  1. `GET https://ai.kogler.si/oauth/oidc/login` → the 302's `location` carries the `redirect_uri` the
     app will actually send, so it reads the live compose env rather than the repo file.
  2. Ask the authorize endpoint to accept that URI (and a bogus one as the control): 302 to
     `/if/flow/default-authentication-flow/` = accepted, 400 = rejected.
  3. `GET https://ai.kogler.si/oauth/oidc/callback?code=probe&state=probe` → a **307 to `/auth?error=…`**
     means the handler ran and attempted the token exchange; a **200 + `index.html`** means no route served
     it. A bogus code is the point: the app's own failure redirect proves the exchange was reached, which a
     200 on a callback page never proves.
  A human still has to do the login itself for the ✅ in the ledger below — an error redirect proves the
  plumbing, not the session.

---

## Per-service SSO login ledger

What has been proven by an actual human login (not a 302), and what has not. The forward-auth tier is
verified by its redirect; native-OIDC services are verified by the session existing on the other side.

| Service | Tier | Proof | Status |
|---|---|---|---|
| `ai` (Open WebUI) | native OIDC | the return leg is proven end to end without a browser: the login 302 carries `redirect_uri=…/oauth/oidc/callback`, the authorize endpoint accepts that URI and 400s the old `/oauth2/callback` one, and a bogus-code `GET` of the callback returns **307 → `/auth?error=…`** (handler ran, exchange attempted) where the dead path returns 200 + `index.html` | ⏳ plumbing proven — **a human login is still the ✅** |
| `vpn` (Headscale) | native OIDC | owner login, not re-proven since. The IdP side re-checked 2026-10-30: provider `headscale` carries `https://vpn.kogler.si/oidc/callback` + `/admin/oidc/callback`, grants `authorization_code`+`refresh_token`, and the authorize endpoint 302s the first and 400s a bogus path | ✅ once — **not re-verified by a login** (an old ✅ is not a current one) |
| `chat` (Element + Tuwunel) | homeserver SSO | `/_matrix/client/v3/login` advertises `m.login.sso` with the `authentik` IdP + owner login | ✅ |
| `file` (OpenCloud) | native OIDC (web) | owner login **and** a `.docx` open through the ONLYOFFICE WOPI chain in that session ([services-office.md](services-office.md)) | ✅ |
| `file` (OpenCloud) **native Android app** | native OIDC, client_id from WebFinger | owner login as `domen` **and** the file list on device; acceptance measured server-side = a `RefreshToken` row for the provider whose scope still contains `offline_access` (an app that logs in but gets no refresh token LOOKS alive for an hour) | ✅ |
| `file` (OpenCloud) **native iOS / Desktop clients** | native OIDC, same shared client id from WebFinger | the per-platform callbacks are on the shared provider and each is accepted at the authorize endpoint (iOS `oc://ios.opencloud.eu` → 302; Desktop `http://127.0.0.1:<port>` → 302 via a REGEX entry, 400 without one). Shapes + sources: [services-authentik.md](services-authentik.md) §Blueprint authoring notes | ⏳ server side ready — **the device onboarding is an owner act** |
| `foto` (Immich) | native OIDC | the button, then an owner login as `domen` (see §Immich for how the settings get there); **plus the mobile app** — picture **and** video uploaded from the phone, which is also what makes Immich the family photo SSOT rather than OpenCloud photo backup ([services-office.md](services-office.md)) | ✅ |
| `git` (Forgejo) | native OIDC | `user/login` advertises `Sign in with authentik`; the source is registered by `deploy-service.yml`, `ENABLE_AUTO_REGISTRATION=true`, `/user/register` 404 by design | ✅ |
| `claw` (OpenClaw) | native OIDC | — | ⏳ desktop/mobile OAuth + CSP |
| `office` (ONLYOFFICE) | no auth surface (WOPI helper) | reached through `file` | ✅ by way of `file` |
| Forward-auth edge apps | Forward-Auth | 302 to `sso.` | ✅ |

⚠ **A green `GET /api/v3/...` or a working redirect is not a login.** Every ✅ above is a human in a
browser; the ⏳ rows have neither.

---

## Related

- [Authentik — Identity & SSO](services-authentik.md) — the decision + Blueprint authoring notes
- [Docker Compose Specification](deployment-compose.md) — compose conventions the consumer templates follow
- [Ansible Role Catalog](deployment-ansible.md) — the pre-pass + deploy loop implementation
- [Secrets](deployment-secrets.md) — the `*_api`/`*_oidc` items the glue seeds
