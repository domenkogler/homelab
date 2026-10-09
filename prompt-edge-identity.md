# `prompt-edge-identity.md` — Lane brief · SSO tails, Matrix federation, zipline, published names (VPS)

> **Role:** dispatch note for **one** lane session on the VPS identity + published-name surface. **The rows are the
> authority** for what is missing and how to do it — this file carries the contract, the order of work and the traps,
> nothing else: [todo.md](todo.md) **HD-147 · HD-457 · HD-458 · HD-459 · HD-112 · HD-47**
> (row ids as of `16177f19` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O9) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers and this brief deliberately restates none of them.

**Converge host + slot (O3):** the **VPS** (`vps.kogler.si`, `IaC/ansible/playbooks/vps.yml`) — one converge in flight on
that host, detached, **never `--diff`**. The Authentik blueprint apply is a separate leg (`playbooks/authentik-blueprints.yml`
or the in-container one-shot apply) and it restarts nothing on its own — do not treat "applied" as "consumed".
⛔ **Do not share a wave with another VPS lane**: `vps.yml` renders and recreates the whole VPS service set, so a sibling
restarting the edge or the IdP while you recreate Open WebUI produces a login that fails for a reason neither row owns. The
DNS/edge-policy lane and the LiteLLM lane both have VPS legs — sequence behind them, do not bundle. **The router slot is
global** and HD-47 needs no router delta; if you think it does, stop and re-read the row.

**Read first:** [docs/services-authentik.md](docs/services-authentik.md) §OIDC client provisioning → §Blueprint authoring
notes → §Rotating a shared Authentik OIDC client secret · [docs/deployment-oidc.md](docs/deployment-oidc.md) §Per-service
SSO login ledger → §Open WebUI native-OIDC note → §Immich · [docs/services-matrix.md](docs/services-matrix.md) ·
[docs/services-vps.md](docs/services-vps.md) · [docs/services-utilities.md](docs/services-utilities.md) for zipline.

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-458** | Move the OWUI redirect on **both** sides of the wire to `/oauth/oidc/callback`, recreate Open WebUI, re-apply the blueprints, then verify the login lands logged in | At this `HEAD` both sides still carry `/oauth2/callback`: `IaC/ansible/templates/docker_services/open-webui/docker-compose.yml.j2:48` and `provider_openwebui.redirect_uris` in `IaC/ansible/templates/docker_services/authentik/blueprints/ks-oidc.yml:59`. Changing one side only reads as a broken IdP |
| 2 | **HD-147** | Walk the ledger's open tails: the native desktop/mobile OAuth legs (the web logins work, the native clients are unwired), the HD-458 `ai` break (item 1 above), the Forgejo content gap, the stale `vpn` re-proof, then re-render the service inventory | ⛔ Do not re-derive the per-service autopsies — they live in [docs/deployment-oidc.md](docs/deployment-oidc.md) §Per-service SSO login ledger. Forgejo's gap is **content, not auth**: nothing has ever been pushed and `22/tcp` is exposed but published on no host port (`IaC/ansible/templates/docker_services/forgejo/docker-compose.yml.j2:17`), so git transport is an **owner call** — park it with the exact question (O4) |
| 3 | **HD-457** | Delete the disposable test assets on the native `admin@kogler.si` seat, confirm that seat still logs in by password, and re-read role + quota on the SSO seat; then the owner-asked upstream read for the per-user + shared-album shape | ⚠ `immich_role` / `immich_quota` are **creation-only and never re-synced** — re-saving the blueprint proves nothing. The `admin` seat is break-glass: prove password login before and after. `immich-app` converges on the VPS, `immich-ml` on oldsrv (one var, two hosts — `IaC/ansible/group_vars/all/versions.yml:301`) — two slots, so never bundle them |
| 4 | **HD-459** | Onboard the remaining OpenCloud native clients: Desktop and iOS each get **their own scheme-callback redirect entry** on the existing shared client | ⛔ One provider = one `client_id` = one issuer: a multi-client app shares **one** client, so never add a provider per platform. A device whose app predates client-id discovery arrives as `OpenCloudAndroid` → flip the **shared** id (`WEBFINGER_WEB_OIDC_CLIENT_ID` + the ORM-set provider `client_id`). Before touching any OIDC client read [docs/services-authentik.md](docs/services-authentik.md) §Blueprint authoring notes facts 7 + 9 — the apply consumes the **deployed** render and a refresh token exists only if `offline_access` is a property mapping on the provider |
| 5 | **HD-112** | The post-up seeding, in order: local admin → OIDC login verify → flip `bypass-local-login` → create the `guestbin` user + `dropzone` folder → anonymous upload → short-URL → viewer round-trip → the 6 h TTL sweep → the family drop script (capability secret → 1Password) + family guide entry | The pin is `zipline_version: "4.6.5"` (`IaC/ansible/group_vars/all/versions.yml:318`) — **not** the v4.7.0 this row once quoted, and 4.8.0 crash-loops on its own Prisma migration ledger, so a bump is HD-1100 work, not a renovate commit. Its metadata DB is dumped as contiguous slot `DB05`; the uploads dir is Kopia-excluded by design (≤ 6 h TTL) — see [docs/backup.md](docs/backup.md) §The slot-numbering rule |
| 6 | **HD-47** | **PARKED (O4), owner-paced.** The only unproven fact is an inbound federation delivery, which requires a join from an account on **another** homeserver | ⛔ A second client or a second Element on `chat.kogler.si` is not a foreign server; our own two servers prove nothing. There is no `_matrix._tcp`/`_matrix._https` SRV anywhere, so the apex well-known is the only delegation — it answers 200 off-network while the launchpad root and `/.well-known/security.txt` 302 into Forward-Auth on the priority-100 router, and that body-shape asymmetry is a documented **do-not-fix**, not a bug to chase |

## ⛔ Traps that cost a round (re-grounded at this `HEAD`)

* **A blueprint apply is not a consume.** `playbooks/authentik-blueprints.yml` reads the **deployed** blueprint render, and
  upserts have wiped `grant_types` to `[]` before (the warning is inline in
  `IaC/ansible/templates/docker_services/authentik/blueprints/ks-oidc.yml`, at the `provider_openwebui` provider). After any
  apply, re-read `grant_types` + `property_mappings` on the affected provider; the in-container one-shot apply is the sanctioned
  fast loop ([docs/services-authentik.md](docs/services-authentik.md) §Blueprint authoring notes fact 7).
* **Redirect URIs are a two-sided invariant.** The compose env and the blueprint must move together, in the same change, or the
  failure looks like an IdP outage. Both live values are readable in-tree — read them before editing
  (`.../open-webui/docker-compose.yml.j2:48`, `ks-oidc.yml:59`).
* **Token-bearing consumers fail silently.** Before declaring an OIDC client healthy, replay the token endpoint
  ([docs/services-authentik.md](docs/services-authentik.md) §Rotating a shared Authentik OIDC client secret step 5): an
  authorization-code exchange that returns `invalid_grant` proves client auth, a 200 on a callback page proves nothing.
* **Creation-only attributes.** `immich_role` / `immich_quota` never re-sync from a blueprint edit; assert the live values.
* **`admin@kogler.si` is break-glass.** `passwordLogin` is deliberately still true for it; any "harden the login" reflex here
  removes the only path in when the IdP misbehaves. Prove the password login works as an explicit step, not as an assumption.
* **Slot numbering is load-bearing in the backup config.** A `DB0n` block that is *named* in prose but absent from the compose
  silently dumps nothing; blocks are numbered contiguously from `DB01`. If you touch a dump target, quote the rendered block, not
  the doc table ([docs/backup.md](docs/backup.md) §The slot-numbering rule).
* **The VPS IdP database is on the fleet's PG-18 line** — `authentik_db_version: "18.6-alpine"`
  (`IaC/ansible/group_vars/all/versions.yml:39`). Never describe an Authentik data leg against a `postgres:16` assumption; the
  16→18 data-format work is HD-1100's, not this lane's.
* Converge the VPS **detached and guarded** (`scripts/guarded-converge.sh` is the repo-native wrapper), never with `--diff`
  (O3: the secret-dump class). Diff-only is what an unattended run is authorised for.

## Owns / never touches

**Owns:** `IaC/ansible/templates/docker_services/{authentik,open-webui,opencloud,immich-app,zipline,matrix,element-web,forgejo}/**`,
the Authentik blueprints in `authentik/blueprints/` (`ks-oidc.yml`, `ks-forward-auth.yml`) and
`IaC/ansible/playbooks/authentik-blueprints.yml`, the identity/edge-name sections of `docs/services-authentik.md`,
`docs/deployment-oidc.md`, `docs/services-matrix.md`, `docs/services-vps.md`, `docs/services-utilities.md`, and your own
`todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2) or another brief's rows; the LiteLLM gateway, its keys and
`templates/docker_services/{litellm,lan-litellm}/**` (the litellm-consumers lane); traefik edge/route and DNS answer-plane work
beyond the published names your rows name (the dns-transport lane); `IaC/router/**` and the router slot; the headscale/tailnet
policy files (the seat/cockpit lane owns tailnet exposure decisions); `roles/monitoring/**`; the Kopia/backup rows and every
`DB0n` block except by citing them; the laptop legs; the frozen archives and generated `*-generated.md`.

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path counts as
not run. Concretely: an OWUI login that **lands logged in** with the two changed files quoted, and the post-apply
`grant_types`/`property_mappings` read · each HD-147 tail either closed or named as the owner leg it is (the Forgejo transport
question parked with its exact wording) · the Immich seat cleanup done with `admin` password login proven and role+quota quoted
from the live instance · the OpenCloud client onboarding done on the **shared** client id, per-platform callback entries listed,
and no new provider minted · the zipline seeding sequence walked end-to-end with the anonymous upload→viewer round-trip and the
6 h sweep quoted, at the pin named above · HD-47 recorded as `PARKED` with the exact blocked action (a foreign-homeserver join),
never as satisfied · rows trimmed to their tails or deleted, no history in the row · `bash scripts/validate-all.sh` green **in
this worktree** → **stop**.
