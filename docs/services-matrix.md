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

> 🟢 **Containers live** (Phase 1): matrix (Tuwunel) + element-web Up on the VPS. ✅ **SSO login live +
> owner-verified 2026-09-25** — `/_matrix/client/v3/login` advertises `m.login.sso` with the `authentik`
> IdP, and a human logged in at `chat.`. ✅ **profile auth measured 2026-09-25**: unauthenticated
> `GET /_matrix/client/v3/profile/<user>` → **401 `M_MISSING_TOKEN`** (the HD-122 read).
> ✅ **The apex delegation is PUBLIC — live since 2026-09-25 (HD-47, measured):**
> `https://kogler.si/.well-known/matrix/client` → 200 `{"m.homeserver":{"base_url":"https://matrix.kogler.si/"}}`
> and `.../server` → 200 `{"m.server":"matrix.kogler.si:443"}`, both from off-network, while
> `https://kogler.si/` still 302s into Forward-Auth and `/.well-known/security.txt` still 302s too —
> so exactly the two Matrix bodies are public and nothing else inherited the hole. It is a router on
> the Tuwunel container with `Host(kogler.si) && PathPrefix(/.well-known/matrix)` at **priority 100**:
> Traefik does NOT resolve a router tie by rule length, and the launchpad (`homepage`) router matches
> the same apex Host at default priority 0, so an unprioritised route here is a coin flip.
> ⚠ **Do not "fix" the bodies.** The server document is `m.server` with the value `host:port` — that
> is the federation delegation, and it is what a remote homeserver parses.
> `{"server_name":"kogler.si","port":443}` is not a spec shape; it is the wrong fix these two small
> JSON bodies invite.
> 📱 **What a client may be pointed at (measured 2026-09-26):** `matrix.kogler.si` is the homeserver host —
> `/_matrix/client/versions` → 200 and `/v3/login` advertises the `authentik` IdP. `chat.kogler.si` is the
> **web client only**: `chat.kogler.si/.well-known/matrix/client` → 404 and
> `chat.kogler.si/_matrix/client/versions` → 404, so a native app typed at `chat.` gets neither discovery nor
> client API. Whether `chat.` should also be a client host is open (**HD-464**, which is what broke Element for
> Android on a phone on LTE). ⛔ The trailing slash in the client well-known `base_url` is NOT the fault: a
> doubled slash path (`//_matrix/client/versions`) answers 200 here, so Traefik normalizes it — do not "fix" the
> bodies chasing that.
> 🚪 **Where that 404 comes from — and a retraction.** It is **element-web's own nginx**
> (`server: nginx/1.27.4`) answering for `/_matrix/*` and `/.well-known/matrix/*`, paths a static
> client host does not serve: `GET https://chat.kogler.si/` returns `200` with
> `<title>Element</title>`. An earlier draft of this paragraph claimed `chat` was "nothing but a
> Cloudflare CNAME with **no `docker_services` entry and no Traefik router**", and that making
> `chat.` a client host would mean inventing a router for a name with no owning service. **That was
> wrong**: `group_vars/vps.yml` carries
> `- { name: chat, template_dir: element-web, subdomain: chat, public: true, enabled: true }` and
> `templates/docker_services/element-web/docker-compose.yml.j2` defines
> `traefik.http.routers.chat.rule: Host(\`chat.kogler.si\`)`. The miss came from greping service lists
> for "matrix" — the service is called **`chat`** and its template **`element-web`**, so a
> keyword-shaped search walks straight past it. It also means `chat` is exactly the kind of entry
> HD-436's derivation *can* render (it has `subdomain`/`public`/`enabled`), not the exception I
> described. Lesson kept where it will be hit again: locate a service by its **host/label**, not by
> guessing which word its name contains.
> 🧪 **What the client/server split actually is, measured 2026-09-26:** `matrix.kogler.si` is the
> homeserver and `chat.kogler.si` is the browser client — two hosts, one Matrix. The homeserver side
> is **not** legacy: it serves MSC2965 discovery three ways
> (`/_matrix/client/v1/auth_metadata` → 200 with issuer + `/_tuwunel/oidc/*` endpoints,
> `/_matrix/client/v1/auth_issuer` → 200, and the unstable variant → 200), dynamic client
> registration (MSC2966), and simplified sliding sync (`org.matrix.simplified_msc3575`). What *is*
> old is the pinned client build: `group_vars/all/versions.yml` pins
> `element_web_version: "v1.11.96"`, while upstream Element Web is on the 1.12 line, which has had
✅ **Shipped 2026-09-26: `element_web_version` went `v1.11.96` → `v1.12.29`**, so the browser
> client now speaks the same generation as the homeserver. Live proof: the `chat` container runs
> `ghcr.io/element-hq/element-web:v1.12.29` (healthy) and `https://chat.kogler.si/version` answers
> `1.12.29`; the converge was scoped with `docker_services_scope=chat` (`ok=31 changed=2
> failed=0`), so nothing else on that host moved. Two things a future bump inherits: Element Web
> offers **OIDC as the only login** once it discovers a provider, which was accepted by the owner
> because no other account uses the web client; and a GHCR tag must be verified with an anonymous
> token that carries `service=ghcr.io`, because the registry answers **404 for tags that exist**
> when it does not — which is how a first probe managed to report the then-current `v1.11.96` as
> missing. `config.json` needed no migration (only long-stable keys in use).
> 🧪 **Step 0 ran 2026-09-26 and it killed the discovery theory:** typing `matrix.kogler.si`
> into the phone produced the **same** `M_UNRECOGNISED: not found`. The server-side probe that
> followed ruled out, each by measurement rather than by elimination-on-a-forum: **routing**
> (the `matrix` router is `Host(matrix.kogler.si)` with no path constraint, and
> `/_tuwunel/oidc/jwks` returns real ES256 keys); **simplified sliding sync** — `POST
> /_matrix/client/unstable/org.matrix.simplified_msc3575/sync` → 401 `M_MISSING_TOKEN`, i.e.
> present (⚠ `/_matrix/simplified/v3/*` 404s and proves nothing: that is superseded MSC4108
> path naming, Tuwunel serves the MSC4186 `simplified_msc3575` paths — a probe against the old
> path will mislead whoever runs it next); **legacy `/sync`** (401, present — which is why
> Element Web keeps working); **the login flows** (`m.login.password` and `m.login.sso` with
> the Authentik IdP both advertised); and **the native Matrix 2.0 auth surface**
> (`POST /_tuwunel/oidc/native` → 415 "Form requests must have `application/x-www-form-urlencoded`"
> — the endpoint is live, it just wants a form post). The name and well-known layer was never
> the bug. ⛔ So do **not** publish anything on `chat.`, and do **not** hand-author
> `org.matrix.msc2965.authentication` into the client well-known: the whole host routes to
> Tuwunel, so the terse `{"m.homeserver":…}` body is **the server's own output**, and forking
> the homeserver's identity data into IaC to imitate a spec member is how a second source of
> truth gets born.
> ✅ **Root cause, confirmed from the client's own traffic (2026-09-26).** The Traefik access
> log (router `matrix@docker`) shows the classic Element app asking, twice, three seconds
> apart:
> ```
> GET /_matrix/client/r0/login/sso/redirect/<idp>?redirectUrl=…     → 404 M_UNRECOGNIZED
> ```
> Tuwunel 1.9.0 mounts only a **subset** of the retired `r0` family — `/_matrix/client/r0/login`
> answers 200 while `/_matrix/client/r0/versions` and the `r0` **SSO-redirect-with-IdP** answer
> 404 `M_UNRECOGNIZED: Not Found` — and the app surfaces that body verbatim as the
> `M_UNRECOGNISED: not found` on the phone. Upstream tuwunel **#286** is this exact report
> ("Unable to log into tuwunel via SSO from element (non x) app"). Nothing else in the classic
> path is missing: the `v3` SSO redirect answers **302 → Authentik even for the custom
> `element://connect` app-link** (so no `sso_redirect_allow_uri` change is needed and #286's
> `M_INVALID_PARAM` variant is not our case), `/v3/sync` works (which is why Element Web works),
> and the account itself is fine.
> ✅ **The A/B that proves it:** the same owner, same server, same account, **Element X logs in
> and registers the phone as a new device**. Its flow — `v3/login/sso/redirect/…?redirectUrl=
> …/_tuwunel/oidc/_complete` → Authentik flow → `v1/login/token/unused` →
> `POST /_matrix/client/unstable/org.matrix.simplified_msc3575/sync` — is fully served. So this
> was never DNS, never the well-known, never the router, never sliding sync.
> ⚠ **Two corrections to this row's earlier draft, both my own probe artifacts, recorded so
> nobody re-inherits them:** (1) `/_matrix/simplified/v3/*` 404s because that is superseded
> MSC4108 path naming — Tuwunel serves MSC4186 under `org.matrix.simplified_msc3575`, and I
> nearly shipped a "the server advertises msc4108 but serves nothing" claim on that; (2)
> `/_matrix/client/v1/login/token/unused` returning 404 for a **bogus** token is the
> spec-correct answer, not an advertise/serve mismatch — the log shows the real client
> completing through that same endpoint.
> 🔎 **How to read this log again** (both of these cost a wrong turn): the flag says
> `--accesslog.filepath=/var/log/traefik/access.log`, which is the **container** path; the host
> path is the bind source **`/opt/traefik/logs/access.log`**, and greping the flag path finds
> nothing. The format is **combined/CLF, not JSON** — there is no Host field and no JSON per
> line — so filter by the **router name** (`"matrix@docker"`), not by hostname: a hostname grep
> only matches lines whose *query string* happens to mention it. ⛔ Query strings here carry
> `login_token`/`state`/`code` values: redact at `?` before sharing a capture.
> 📱 **Element vs Element X — why one works here and the other cannot (owner asked, 2026-09-26).**
> They share a name and an account and almost nothing else. **Element** (classic) is the decade-old
> React/Android/iOS client on the **Matrix 1.x client API**: long-polled `GET /_matrix/client/v3/sync`,
> `m.login.password` / `m.login.sso`, legacy Olm/Megolm key UX. It talks to anything that implements
> the classic API, which is why it has always been the safe default — and why its login path here runs
> into a retired `r0` route. **Element X** is a ground-up rewrite on the **Rust SDK**, built for what is
> being sold as **Matrix 2.0**: the homeserver itself becomes an **OAuth 2.0 / OIDC provider**
> (MSC2965/MSC3861 — no more password or web SSO redirect inside the app), the sync loop is
> **simplified sliding sync** (MSC4108, renamed MSC4186) instead of `/sync`, and encryption onboarding
> is rebuilt around a recovery key + device verification and QR sign-in.
> **Practical consequences:** sliding sync is why Element X's first sync on a big room list is fast
> where classic Element crawls; native OIDC is why logging in never asks for a password; and
> registering the phone creates **a separate device/session**, which will prompt verification elsewhere
> and is worth pruning from the device list now and then. The trade is breadth: the classic clients (and
> Element Web, which still speaks the 1.x API and works fine here) carry widgets/legacy integrations and
> older power features that Element X has been slower to absorb.
> 🧭 **Why this homeserver is the unusual one, not the app:** most non-Synapse homeservers cannot do
> Element X at all. Tuwunel ships its **own OIDC provider** (`/_tuwunel/oidc/*`) and the
> `simplified_msc3575` sync, so it supports the modern client while having dropped the `r0` route the
> legacy client wants. **Decision: Element X is the mobile client for this deployment; classic Element
> is not supported here** (upstream tuwunel #286, and we are not rewriting `r0`→`v3` at the edge to
> imitate an API the origin does not serve). Anyone else in the family who logs in on a phone needs the
> Element X app — the same server, the same Authentik account, no other change.