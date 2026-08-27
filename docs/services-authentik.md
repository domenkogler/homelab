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

> 🟢 **Live since 2026-08-22** (Phase 1): Authentik server + worker up on the VPS; the OIDC provisioning chain is proven live — all 15 expected providers exist via the deterministic, now-externalized blueprint one-shot (`playbooks/authentik-blueprints.yml`, HD-230b/HD-268). ⏳ deploy-gated tails below where flagged (e.g. LDAP authoring HD-132). Sections below remain the implementation spec.

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
`deployment-ansible.md`. Mechanic/implementation detail (the parallel fan-out + concurrency budget) lives in [`scripts/README.md`](../scripts/README.md) §Parallel 1Password operations; the SSOT routing index for **all** secret-glue steps (who provisions / how to rotate) is [`deployment-secrets.md`](deployment-secrets.md) §"Glue-routing index".

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

> **Facts 5–8 verified LIVE on the pinned 2026.5.6 during the Phase-1 deploy (2026-08-22)** — the
> blueprint had never reached a real server before; each of these failed the first true apply:

5. **`identifiers` is REQUIRED on every entry** (Blueprint-v1 spec:
   docs.goauthentik.io/customize/blueprints/v1/structure). Providers identify by `name`, applications
   by `slug`; keep the identifier field OUT of `attrs` ("avoid setting the same field in both
   places"). On create, identifiers merge into attrs; on update only `attrs` apply — so the
   auto-generated `client_id`/`client_secret` survive every re-apply. An entry without identifiers
   fails validation: "No or invalid identifiers".
6. **2026.5.6 OAuth2Provider serializer:** `invalidation_flow` is REQUIRED
   (`!Find … default-provider-invalidation-flow`) and `redirect_uris` must be a **list of objects**
   `{url, matching_mode: strict|regex}` (+ optional `redirect_uri_type: authorization|logout`). The
   legacy newline-separated string AND plain string-list forms fail validation. Authoritative shape:
   `/blueprints/schema.json` inside the image (`$defs.model_authentik_providers_oauth2.oauth2provider`).
7. **One-shot apply for fast loops:** `docker exec authentik-worker ak apply_blueprint
   /blueprints/custom/ks-oidc.yml` applies immediately without waiting for worker file-discovery.
   **MANDATORY for EVERY custom-blueprint edit since HD-230 (2026-08-23):** discovery has never
   registered `/blueprints/custom/*` as BlueprintInstances (28 instances, 0 custom — hourly
   `blueprints_discovery` runs complete 'done' but skip them), so the file-hash re-apply machinery
   does NOT fire for our blueprints. The one-shot applies are EXTERNALIZED (owner decision
   2026-08-27): run `bash scripts/ansible-run.sh playbooks/authentik-blueprints.yml` whenever a
   blueprint file changes — the routine docker_services lane no longer applies them every converge.
   Layer-2 cause of discovery non-registration still unknown — follow-up investigation pending.
   Remember: apply = UPSERT; removing a blueprint entry does NOT delete the server-side object —
   intentional deletions need ak-shell ORM one-shots in the same change.
8. **openclaw placeholder:** the serializer requires ≥1 redirect_uri even for the not-yet-onboarded
   provider — ks-oidc.yml carries `{url: "http://localhost:.*", matching_mode: regex}` as an explicit
   placeholder; replace with the real `openclaw onboard` callback(s) at HD-104.

**Canonical 2-entry pattern (per OIDC consumer):**

```yaml
- model: authentik_providers_oauth2.oauth2provider
  id: provider_<svc>
  identifiers:
    name: <svc>
  attrs:
    authentication_flow: !Find [authentik_flows.flow, [slug, default-authentication-flow]]
    authorization_flow: !Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]
    invalidation_flow: !Find [authentik_flows.flow, [slug, default-provider-invalidation-flow]]
    client_type: confidential
    redirect_uris:
      - {url: "https://<svc>.kogler.si/<callback>", matching_mode: strict}
    signing_key: !Find [authentik_crypto.certificatekeypair, [name, authentik Self-signed Certificate]]
    sub_mode: hashed_user_id
- model: authentik_core.application
  id: app_<svc>
  identifiers:
    slug: <svc>
  attrs:
    name: <Service Name>
    meta_launch_url: https://<svc>.kogler.si
    provider: !KeyOf provider_<svc>
```

### Live-deploy findings — authentik 2026.5.6 image & API (Phase 1, 2026-08-22)

- **Blueprint upsert EMPTIES absent array attrs (HD-231, 2026-08-24):** applying a blueprint that omits `grant_types` / `property_mappings` writes `[]` over them — killing the `authorization_code` grant and all token scopes while authorize/token still look healthy (UserInfo then 403 `insufficient_scope`). Pin EVERY array attr explicitly in ks-oidc.yml / ks-forward-auth.yml entries; the docker_services one-shot apply runs on every converge.
- **`AUTHENTIK_BOOTSTRAP_*` applies ONLY at user creation** (Phase 1 R5, 2026-08-22): if the DB was
  initialized before the bootstrap env landed in compose, `akadmin` keeps its creation-time
  defaults (email `root@example.com`, no vault password) and later env changes are silently
  ignored — login with the 1Password value fails forever. Fix: ORM sync inside the worker via
  ak-shell (`set_password(os.environ[...])` — note the WORKER container does not carry the
  `AUTHENTIK_BOOTSTRAP_*` env, pass values in explicitly).
- **The server image has NO default CMD**: entrypoint is `dumb-init -- ak`; compose MUST set
  `command: server` (the worker passes `command: worker`). Without it the container runs bare `ak`,
  prints the management-command help and exit-0-flaps forever — while `ak healthcheck` still reports
  "healthy" (process-level, not route-level).
- **Custom blueprints mount at `/blueprints/custom`**, never `/blueprints`: a root mount shadows the
  image's system tree and the server's migrate pre-start dies on the missing
  `/blueprints/system/bootstrap.yaml` in a ~9 s loop — gunicorn workers never bind and every route
  answers 502 (`dial unix /dev/shm/authentik-core.sock`). Discovery IS recursive (the image ships
  `system/` as its own subdir), so the custom subdir is picked up normally.
- **API paths:** OAuth2 providers live at `/api/v3/providers/oauth2/` — NOT
  `/api/v3/core/providers/oauth2/` (that 404s; `core/*` is users/groups/apps).
- **Health probes:** `/-/health/live/` and `/-/health/ready/`; bare `/-/health/` does not exist (404).
- **RBAC:** `User` has NO `is_superuser` field in 2026.x (Django FieldError if queried). Admin
  capability = membership of a group with `is_superuser: true` — the bootstrap admin `akadmin` sits
  in "authentik Admins". API tokens inherit their user's permissions. Human users are **Internal
  type** by policy (runbook imperative: [deployment-manual.md](../deployment-manual.md) §1.5) —
  External/Service-account types are not for people.
- **CLI:** `ak shell -c "<python>"` executes code; the REPL ignores piped stdin, and `-c` takes NO
  extra argv (pass parameters via `docker exec -e VAR=...`, options before the container name).
  When driving over ssh, base64-wrap non-trivial python to survive quoting layers
  (`scripts/ak-shell.sh` wraps all of this). Token minting:
  `Token.objects.create(user=…, identifier=…, intent="api", expiring=False)` for a PERSISTED
  token — see *API-token auto-rotation* below: an ORM create defaults to `expiring=True`, so the
  background sweep ROTATES it on its first ≈5-min pass even with `expires` left NULL (the earlier
  `.update(expires=None)` advice did NOT protect against this).
- **Provision-token issuance until the Authentik UI exists:** mint via ak-shell (above, user
  `akadmin`) and store in vault item `authentik-provision_api.credential`. Scoping it down to
  issuer/app/flow/outpost-only (catalog's least-privilege target) stays a post-green hygiene step
  (HD-211 batch) — needs Authentik RBAC roles, doable via blueprint later.

### Authentication tokens (TWO secrets + one ephemeral — never merge them)
- `vps-op-write_api` — 1Password **SERVICE ACCOUNT token (write-scoped)**, deployed by the pre-pass
  to VPS `/etc/op/provision-token`; authenticates the HOST-side `op` CLI the glue uses to seed the
  OIDC client-cred items.
- `authentik-nas_api` — **read-only** Authentik-issued API token, minted durable (`expiring=False`) at NAS provisioning; the Authentik→NAS provisioning
  glue (`sync-authentik-users.sh`, D5/HD-131) uses this to *read* the `family` group.
- **Ephemeral glue token (NOT a secret anywhere):** the OIDC secret-egress glue mints its own
  api-intent token via `ak shell` per run (identifier `egress-glue-<pid>-<ts>`, revoked on exit).
  Rationale: persisted ORM tokens were observed being rotated/invalidated server-side within
  minutes (Phase 1, 2026-08-22) — root cause since IDENTIFIED as upstream auto-rotation
  (**HD-216**, mechanism below), which silently killed any vault-stored copy; the former
  `authentik-provision_api` vault item was RETIRED because of it.
  Trade-off note: the minted token carries akadmin's full rights for its seconds-long life —
  equivalent to the existing trust model (glue already requires root on the VPS), but NOT the
  least-privilege scope the old catalog row aspired to. A scoped RBAC role + PERSISTED token is
  now viable whenever wanted via the `expiring=False` recipe below (unblocks the HD-211 batch).

#### API-token auto-rotation (HD-216 — identified & documented; offline source read, no live probing)

Expiring API tokens are **auto-ROTATED by authentik itself** — a legitimate security feature,
not an attack or bug (upstream docs: service accounts → "Expiring API tokens are rotated by
authentik"; source branch `version-2026.5`, pinned image 2026.5.6 = same minor):

- **Scheduler:** `clean_expired_models` runs on crontab `2-59/5 * * * *` (≈ every 5 min;
  `core/apps.py`) over all `ExpiringModel` subclasses, selecting rows with `expiring=True`
  AND `expires<=now()` — note an ORM-created token defaults to `expiring=True`, so one with
  `expires=NULL` also matches and is swept on the FIRST pass.
- **`Token.expire_action()` override (`core/models.py`):** intent `api` → NEW key + fresh expiry
  (`now() + tenant.default_token_duration`; upstream default **`days=1`**) + a `SECRET_ROTATE`
  audit event ("Token <identifier>'s secret was rotated.") — never deleted. Intents
  `recovery` / `verification` / `app_password` → simply DELETED at expiry (app passwords from
  the service-account wizard default to 360-day expiry — LDAP bind users must be created
  non-expiring or get a renewal runbook before Phase-3 LDAP use).
- **API serializer:** for api-intent it FORCE-SETS `expires = default_token_duration()`
  ("expires cannot be overridden") and takes `expiring` from the owner-user attribute
  `goauthentik.io/user/token-expires` (default `true`).

Durable-persisted-token rules for this homelab:

1. A persisted Authentik API token survives ONLY with **`expiring=False`** — never selected by
   the sweep, never rotated/deleted. Recipe: ORM `... , expiring=False)`, or set user attribute
   `goauthentik.io/user/token-expires: false` BEFORE creating the token via UI/API.
2. Tenant setting `default_token_duration` (Admin → System → Tenants) only SLOWS rotation
   (rotated tokens live that long per cycle) — it never prevents it.
3. Audit trail: Events filtered to `SECRET_ROTATE` show every rotation — the read-only
   verification path if this ever needs re-confirming live (no DB probing).

Consequences applied here: the glue's ephemeral mint stays (immune by construction); a future
scoped persisted `authentik-provision_api` (HD-211) follows rule 1; `authentik-nas_api`
(sync-authentik-users glue) gets a one-time `expiring=False` verification at its next live touch.

#### Rotating a shared Authentik OIDC client secret (runbook; verified 2026-08-26)

The recipe the CONVENTIONS §2 *Secret output hygiene* row points at for a shared OIDC
client (`headscale_api` = headscale + headplane; pattern generalizes to any glue-seeded
`*_oidc` / grandfathered client). The whole value-transfer runs **on the VPS host**, so the
secret never reaches the runner session / argv / git. **Hashes & lengths only** in any output.

```bash
# 0) Pre-flight state: confirm the split (DB already has the NEW value, vault holds OLD).
#    Read the provider secret on-box, hash-only:
bash scripts/ak-shell.sh 'from authentik.providers.oauth2.models import OAuth2Provider
import hashlib
p = OAuth2Provider.objects.get(pk=13)
print(hashlib.sha256(p.client_secret.encode()).hexdigest())'
op read "op://Homelab-ansible/headscale_api/credential" | sha256sum   # compare to above

# 1) Drop the NEW DB secret into the worker container /tmp (ak-shell is the sanctioned write path;
#    the worker container cannot reach /media — root-owned, uid 1000 gets EACCES):
bash scripts/ak-shell.sh 'from authentik.providers.oauth2.models import OAuth2Provider
p = OAuth2Provider.objects.get(pk=13)
open("/tmp/hs_new_secret.txt","w").write(p.client_secret)'

# 2) Worker -> VPS host temp file. **Do NOT use `docker cp` — it is broken on this host**
#    ("Could not find the file" despite `docker exec ls` showing it). Use `docker exec cat`:
ssh ansible-admin@vps.kogler.si \
  'sudo docker exec authentik-worker cat /tmp/hs_new_secret.txt > /tmp/hs_secret_raw.txt \
   && tr -d "\n" </tmp/hs_secret_raw.txt > /tmp/hs_secret.txt'

# 3) (on VPS) fail-closed hash-assert crawled value == DB secret, then apply to 1Password.
#    **`op item edit` cannot combine --template with stdin** ("cannot edit an item from template
#    and stdin at the same time") — so `op item get` to a base file first, then edit from the file.
ssh ansible-admin@vps.kogler.si '
set -e
[ "$(sha256sum /tmp/hs_secret.txt | awk "{print \$1}")" = "<DB sha256>" ] || exit 3
export OP_SERVICE_ACCOUNT_TOKEN="$(sudo cat /etc/op/provision-token)"
op item get headscale_api --vault Homelab-ansible --format json --reveal > /tmp/hs_item_base.json
NEWSEC_VALUE="$(cat /tmp/hs_secret.txt)" SECRET_FILE=/tmp/hs_secret.txt python3 -c \
  "import json,os; it=json.load(open('/tmp/hs_item_base.json'));
   [f.update(value=open(os.environ['SECRET_FILE']).read()) for f in it['fields'] if f['id']=='credential'];
   print(json.dumps(it))" > /tmp/hs_item_new.json
op item edit headscale_api --vault Homelab-ansible --template /tmp/hs_item_new.json < /dev/null
# verify stored hash == DB (hash-only), then rm the temp files + worker /tmp file'

# 4) Re-render + restart the consumers (both share the SAME item; converges both):
bash scripts/ansible-run.sh playbooks/vps.yml \
  --tags docker_services -e docker_services_scope=headscale --limit vps
#    -> /opt/headscale/config.yaml + headplane-config.yaml re-rendered to the new secret;
#       restart-on-config-change guard fires (changed extra -> restart).

# 5) Verify: token-endpoint replay (dummy code -> `invalid_grant` = client auth OK),
#    `/health` HTTP 200, `docker exec headscale headscale health` rc=0.
```

> Gotchas learned live (2026-08-26):
> - `docker cp authentik-worker:/tmp/...` fails on this box — use `docker exec cat` instead.
> - `op item edit --template` + stdin are mutually exclusive — `op item get` to a file first,
>   then hand `--template <file>` and redirect stdin from `/dev/null`.
> - The worker can't write to `/media` (root-owned); its `/tmp` IS writable. The worker /tmp file
>   is the reliable host-visible channel only via `docker exec cat` (docker cp can't see it).

### What stays manual (only two, one-time)
- Creating/re-issuing the **1Password write-scoped service account** (`vps-op-write_api`) in the
  1Password admin console (show-once secret; item history can also restore a prior value).
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