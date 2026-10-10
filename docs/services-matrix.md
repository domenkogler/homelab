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

> 🟢 **Containers live** (Phase 1): matrix (Tuwunel) + element-web Up on the VPS. ✅ **SSO login is live**
> — `/_matrix/client/v3/login` advertises `m.login.sso` with the `authentik` IdP, and a human logged in at
> `chat.`. ✅ **Profile auth:** unauthenticated
> `GET /_matrix/client/v3/profile/<user>` → **401 `M_MISSING_TOKEN`**.
> ✅ **The apex delegation is PUBLIC — live since 2026-09-25:**
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
> 📱 **What a client may be pointed at:** `matrix.kogler.si` is the homeserver host —
> `/_matrix/client/versions` → 200 and `/v3/login` advertises the `authentik` IdP. `chat.kogler.si` is the
> **web client only**: `chat.kogler.si/.well-known/matrix/client` → 404 and
> `chat.kogler.si/_matrix/client/versions` → 404, so a native app typed at `chat.` gets neither discovery nor
> client API. Whether `chat.` should also be a client host is open. ⛔ The trailing slash in the client
> well-known `base_url` is NOT the fault: a
> doubled slash path (`//_matrix/client/versions`) answers 200 here, so Traefik normalizes it — do not "fix" the
> bodies chasing that.
> 🚪 **Where that 404 comes from:** `chat` **is** a service — `group_vars/vps.yml` carries
> `- { name: chat, template_dir: element-web, subdomain: chat, public: true, enabled: true }` and
> `templates/docker_services/element-web/docker-compose.yml.j2` defines
> `traefik.http.routers.chat.rule: Host(\`chat.kogler.si\`)`. The 404 is **element-web's own nginx**
> (`server: nginx/1.27.4`) answering for `/_matrix/*` and `/.well-known/matrix/*`, paths a static
> client host does not serve: `GET https://chat.kogler.si/` returns `200` with
> `<title>Element</title>`. Locate a service by its **host/label**, not by guessing which word its name
> contains — this one is `chat`, its template is `element-web`, and a keyword search for "matrix" walks
> straight past it.
> 🧪 **The client/server split:** `matrix.kogler.si` is the
> homeserver and `chat.kogler.si` is the browser client — two hosts, one Matrix. The homeserver side
> is **not** legacy: it serves MSC2965 discovery three ways
> (`/_matrix/client/v1/auth_metadata` → 200 with issuer + `/_tuwunel/oidc/*` endpoints,
> `/_matrix/client/v1/auth_issuer` → 200, and the unstable variant → 200), dynamic client
> registration (MSC2966), and simplified sliding sync (`org.matrix.simplified_msc3575`). The browser
> client is the same generation: `group_vars/all/versions.yml` pins
> `element_web_version: "v1.12.30"` (`ghcr.io/element-hq/element-web`, the 1.12 OIDC line) and
> `config.json` needs no migration (only long-stable keys are in use). Two things any bump inherits:
> Element Web offers **OIDC as the only login** once it discovers a provider — accepted, because no other
> account uses the web client; and a GHCR tag must be verified with an anonymous
> token that carries `service=ghcr.io`, because the registry answers **404 for tags that exist**
> when it does not.
> 🧪 **The server side is ruled out by measurement.** **Routing** — the
> `matrix` router is `Host(matrix.kogler.si)` with no path constraint, and
> `/_tuwunel/oidc/jwks` returns real ES256 keys. **Simplified sliding sync** — `POST
> /_matrix/client/unstable/org.matrix.simplified_msc3575/sync` → 401 `M_MISSING_TOKEN`, i.e.
> present (⚠ `/_matrix/simplified/v3/*` 404s and proves nothing: that is superseded MSC4108
> path naming, Tuwunel serves the MSC4186 `simplified_msc3575` paths — a probe against the old
> path will mislead whoever runs it next). **Legacy `/sync`** (401, present — which is why
> Element Web keeps working). **The login flows** (`m.login.password` and `m.login.sso` with
> the Authentik IdP both advertised). **The native Matrix 2.0 auth surface**
> (`POST /_tuwunel/oidc/native` → 415 "Form requests must have `application/x-www-form-urlencoded`"
> — the endpoint is live, it just wants a form post). The name and well-known layer is not
> the bug. ⛔ Do **not** publish anything on `chat.`, and do **not** hand-author
> `org.matrix.msc2965.authentication` into the client well-known: the whole host routes to
> Tuwunel, so the terse `{"m.homeserver":…}` body is **the server's own output**, and forking
> the homeserver's identity data into IaC to imitate a spec member is how a second source of
> truth gets born.
> ✅ **Root cause: a retired `r0` route.** The Traefik access
> log (router `matrix@docker`) shows the classic Element app asking:
> ```
> GET /_matrix/client/r0/login/sso/redirect/<idp>?redirectUrl=…     → 404 M_UNRECOGNIZED
> ```
> Tuwunel mounts only a **subset** of the retired `r0` family — `/_matrix/client/r0/login`
> answers 200 while `/_matrix/client/r0/versions` and the `r0` **SSO-redirect-with-IdP** answer
> 404 `M_UNRECOGNIZED: Not Found` — and the app surfaces that body verbatim as the
> `M_UNRECOGNISED: not found` on the phone. Upstream tuwunel **#286** is this exact report
> ("Unable to log into tuwunel via SSO from element (non x) app"). Nothing else in the classic
> path is missing: the `v3` SSO redirect answers **302 → Authentik even for the custom
> `element://connect` app-link** (so no `sso_redirect_allow_uri` change is needed and #286's
> `M_INVALID_PARAM` variant is not our case), `/v3/sync` works (which is why Element Web works),
> and the account itself is fine.
> ✅ **The A/B:** the same owner, same server, same account, **Element X logs in
> and registers the phone as a new device**. Its flow — `v3/login/sso/redirect/…?redirectUrl=
> …/_tuwunel/oidc/_complete` → Authentik flow → `v1/login/token/unused` →
> `POST /_matrix/client/unstable/org.matrix.simplified_msc3575/sync` — is fully served. So this
> is not DNS, not the well-known, not the router, not sliding sync.
> ⚠ **Two probe artifacts that mislead:** (1) `/_matrix/simplified/v3/*` 404s because that is superseded
> MSC4108 path naming — Tuwunel serves MSC4186 under `org.matrix.simplified_msc3575`; (2)
> `/_matrix/client/v1/login/token/unused` returning 404 for a **bogus** token is the
> spec-correct answer, not an advertise/serve mismatch — the log shows the real client
> completing through that same endpoint.
> 🔎 **Reading the Traefik access log:** the flag says
> `--accesslog.filepath=/var/log/traefik/access.log`, which is the **container** path; the host
> path is the bind source **`/opt/traefik/logs/access.log`**, and greping the flag path finds
> nothing. The format is **combined/CLF, not JSON** — there is no Host field and no JSON per
> line — so filter by the **router name** (`"matrix@docker"`), not by hostname: a hostname grep
> only matches lines whose *query string* happens to mention it. ⛔ Query strings here carry
> `login_token`/`state`/`code` values: redact at `?` before sharing a capture.
> 📱 **Element vs Element X — why one works here and the other cannot.**
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


## Alert room

The **alert delivery surface is Matrix/Element**, not Signal: the `signal-cli-rest-api` daemon is linked
to the operator's personal number, the "Homelab Alerts" Signal group has **exactly one human member**,
and the operator's everyday reader is Element. The alert path is:
**Grafana → n8n → this homeserver → a dedicated `#homelab-alerts` room**, with the
Grafana-native **SMTP contact point running in parallel** as the fail-safe that survives n8n or
Matrix being down ([observability.md](observability.md) §Alerting owns the delivery chain and its two
silent-failure mutes — read it before touching the workflow).

What is owed, none of it an owner act:

- one **dedicated alert user** on this homeserver (not the operator's account — an alert sent as you
  cannot be told apart from a message you wrote), with its access token in the `Homelab-ansible` vault
  (`<service>_<type>` naming per CONVENTIONS §6, rendered block-scalar, never a literal in compose);
- the **room**, created once, with its id in SSOT the way `signal_alert_recipients` is today — an alias
  reads better to a human, but the write wants the id;
- n8n's `homelab-alerts` workflow gains the Matrix leg **beside** the Signal one, so the cutover is a diff
  in one run rather than swapping a live alerting path out from under the rules;
- acceptance is **the room's own event read** for a canary: a workflow `200` means a
  run started, never that a message landed.

⛔ Signal is not deleted by this decision. `signal-cli-rest-api` stays live until the Matrix leg proves
itself, then demotes to a documented fallback or is retired — **that teardown is the last step**.
