---
title: Secrets Management & Passwordless Philosophy
role: detail
domain: deployment
status: active
sensitivity: secret-bearing
tags: [deployment, secrets, 1password]
---
# Secrets Management & Passwordless Philosophy

> **Role:** Detail — 1Password as sole secrets backend, self-documenting philosophy, passwordless-first design.
> **Links to:** `deployment-oidc.md` (OIDC client + egress glue), `services-authentik.md` (OIDC secret rotation runbook), `deployment-ai-stack-secrets.md` (AI items + LiteLLM glue), `scripts/README.md` (parallel-1P contract), `backup.md`, `manual/README.md`
> **Linked from:** `deployment.md`, `deployment-ansible.md`, `deployment-compose.md`, `index.md`

---

## Self-Documenting Homelab Philosophy

- **Single Git repo is source of truth** — `git clone` + `ansible-playbook` = fully rebuilt infrastructure
- **Secrets never touch the repo** — all credentials live exclusively in 1Password
- **Documentation drives automation** — these `docs/*.md` files are read by AI to generate IaC configs
- ⚠ **Rotation caveat:** updating a 1Password item does NOT update already-initialized service state — re-render + redeploy applies it only where the service reads env/config at start. Known one-time seeds: `POSTGRES_PASSWORD` initializes a volume ONCE (later rotation needs `ALTER USER` inside the container); `AUTHENTIK_BOOTSTRAP_*` applies only at user creation.
- **No tribal knowledge** — if Domen is incapacitated, family + trusted tech contact can recover from 1Password + repo

### Config vs credential split — why there is NO `server` type

1Password holds **credentials only**. Connection *configuration* (which host, which user, which port)
lives in the **Git IaC** so `git clone` → `ansible-playbook` can fully rebuild and a recoverer finds
host facts in the repo. This split is deliberate and **intentionally uses no `server`-type secret**
(an item bundling host + user + key + port).

| Connection fact | Where it lives | Why |
|-----------------|----------------|-----|
| hostname / IP / port | `host_vars/*.yml` (`ansible_host`), `group_vars/all/main.yml` (`kopia_sftp_*`, …) | **config**, not secret — part of the repo's self-rebuild + recovery premise; moving it to 1P would break the `git clone → rebuild` and the provisioning bootstrap (which needs host facts before 1P is available) |
| login (`ansible_user`, `kopia_sftp_user`) | `host_vars` / `group_vars` (inventory) | the login alone grants nothing; the **key** does. Kept in IaC so inventory is complete |
| **key / credential** | 1Password `_ssh` items via the **1Password SSH agent**, or connection-refs (`Hertzner-SB-Backup`) for kopia SFTP | this is the actual secret — never in Git; the disk-resident exceptions are named in §What actually raises a 1Password prompt. **One named exception:** the laptop's own GitHub pair exists as passphrase-free files on both laptop seats — see §What actually raises a 1Password prompt |

**Why not a `server` type:** none of the repo's consumers need a full bundle from a single
`lookup()` — Ansible reads host/login from inventory (parse-time, not 1P), and keys come from
the SSH agent / connection refs. A `server` item would (a) duplicate the IaC host/user SSOT
(second source of truth — `CONVENTIONS.md`), (b) weaken the recovery/bootstrap premise by hiding
host facts in 1P, and (c) match nothing that consumes it. The kopia SFTP case already demonstrates
the split: `kopia_sftp_host/user/port` in `group_vars` + `Hertzner-SB-Backup` key-ref in 1P.

**Exception:** genuinely credential-like, ops-only connection facts deliberately kept OFF the automation
path (e.g. `netcup-vps_login` root + IP in the **Homelab (human)** vault) stay in 1Password — a break-glass
item, not a connection-config item.

### Vault taxonomy — the two-vault model

| Vault | Role | Access |
|-------|------|--------|
| **`Homelab-ansible`** | Automation vault — holds EVERY secret the IaC consumes (`*_api` / `*_password` / `*_db` items, SSH keys). The only vault that Ansible `lookup()`, the service-account token(s) and `provision-secrets.py` touch. | `Homelab-ansible` service account(s) + owner |
| **Homelab (human)** | Break-glass vault — human-only credentials deliberately OFF the automation path (`netcup-ccp_login`, `netcup-scp_login`, `netcup-vps_login`, …). | owner only — **no service account has access** |

Rule of thumb: if Ansible must read it, it lives in `Homelab-ansible`; if it exists only for a human at a
provider console or for console break-glass, it lives in **Homelab (human)**. The split is the blast-radius
boundary — a leaked automation token never exposes break-glass credentials.

---

## 1Password as Sole Secrets Backend

| Principle | Implementation |
|-----------|---------------|
| **One vault** | All secrets in `Homelab-ansible` vault |
| **Never in Git** | No `.env` files, no Ansible Vault, no hardcoded credentials |
| **Resolved at deploy time** | Ansible templates call `lookup('community.general.onepassword', ...)` — secrets fetched at render time, never cached |
| **Forgejo Actions integration** | Service Account token with minimum-scope vault access. Secrets resolved at deploy, never on disk |
| **1Password CLI** | Installed on management laptop + Actions runner. `op` CLI + `OP_SERVICE_ACCOUNT_TOKEN` |
| **1Password SSH agent** | Private keys never on disk — served from `Homelab-ansible` vault on demand. See SSH Key Separation below. On the **Win11** seat the agent serves the GitHub pair only, and both keys are on that disk anyway (§What actually raises a 1Password prompt) |

---

## Secret Naming Convention

> **The single source of truth for 1Password items.** Every secret lives in the `Homelab-ansible` vault.
> Two repo files *reference* items and hold no values: `skills/mikrotik/.env.op` (`mikrotik-admin_login`)
> and `skills/shelly/.env.op` — both TRACKED, never gitignored, so no seat can hold a copy the repo lacks.
> `scripts/harness/sync-skills.sh` never deploys them on purpose, so point the scripts at the repo copy: `--op-env-file skills/mikrotik/.env.op`.

**Item name pattern: `<service>_<type>`**

- `<service>` = the consuming service / role. May contain `-` (e.g. `ansible-admin`, `grafana-smtp`). **Never `_` inside the service name.**
- `_` is the **only** delimiter between `<service>` and `<type>` in the whole name.
- `<type>` = the 1Password **item type** (see map below) — it determines which field the lookup reads.
- **Never put the field in the item name** (e.g. `service-name-db-password` → `service-name_db`).

**Always pass `field=` in Ansible.** The `community.general.onepassword` lookup defaults to the `password` field, which is **NOT** always the value you want. Vault is the `op_vault` variable (defined once in `group_vars/all/main.yml` → `Homelab-ansible`), so a vault rename is a one-line change:

```yaml
lookup('community.general.onepassword', '<service>_<type>', field='<field>', vault=op_vault)
```

> **Two secret-handling traps:**
>
> 1. **`--diff` on a `docker_services` converge dumps rendered secrets.** The bulk 1P pre-pass runs
>    `no_log`, but the **template diff of a rendered `docker-compose.yml` is not no_log** — an
>    `--check --diff` run prints live `LITELLM_MASTER_KEY` / `OPENROUTER_API_KEY` values onto stdout
>    into the run log. Use `--check` (no `--diff`); verify renders from the template, or diff the
>    rendered host file with the secret lines filtered. If a log ever catches values, `shred -u` it —
>    do not grep it back (CONVENTIONS §6).
> 2. **LiteLLM does not expand `os.environ/…` inside a DB-stored model's `litellm_params`.** With
>    `STORE_MODEL_IN_DB=true` the entry `api_key: os.environ/SPARK_LLM_API` is forwarded to the
>    upstream **literally** → engine 401 (proven through the proxy and in-process
>    `litellm.completion`, v1.83.10). To keep a bearer out of the Kopia-backed DB, deliver it as the
>    **provider credential env** the model's provider prefix already reads (`openai/…` → `OPENAI_API_KEY`)
>    and leave `api_key` **unset** in the row — that path returns 200. Caveat to record per service: a
>    future bare `openai/…` entry with no `api_key` silently inherits that key.
>
### Rendering a secret into a YAML config file — block scalar is the default

> When a secret VALUE lands as a **mapping value in a rendered YAML/TOML config** (not a Docker
> `KEY: "{{ … }}"` env assignment — those aren't parsed as YAML by the app), render it as a
> **folded block scalar `>-` and NEVER a quoted inline `"{{ … }}"`.** An Authentik/OIDC
> `client_secret` (or any 1P `credential`/`password`) can contain `:`, `"`, `'`, backtick, `@`, `#`,
> `&`, `*`, `[`, `]`, `!`, `?`, `<`, `>` … which a quoted scalar does **not** escape — the inline form
> breaks YAML parse and crash-loops the app (the failure surfaces as `YAMLException` / `EISDIR` on a
> consumer that parses the file at start — e.g. headscale and headplane).
>
> **Pattern (YAML-safe):**
>
> ```yaml
> oidc:
>   client_secret: >-
>     {{ lookup('community.general.onepassword', 'headscale_api', field='credential', vault=op_vault) }}
> ```
>
> **Do NOT render this way for a secret that may contain special char** (breaks on `:`/`"`):
>
> ```yaml
>   client_secret: "{{ … }}"   # BROKEN if the value contains : " ' etc.
> ```
>
> Scope: required for any file the consuming app parses as structured config (YAML/TOML/JSON) and the
> value is a 1Password secret — e.g. `headscale/config.yaml`, `headplane` config, `prometheus-web-config`,
> a Blueprint, `recyclarr.yml`, and the `home_assistant` role's **`secrets.yaml.j2`** (rendered to
> `/opt/home-assistant-primary/secrets.yaml` + `{{ ha_standby_path }}/secrets.yaml`, fenced with `>-`
> block scalars; HA resolves the values via `!secret` refs from `configuration.yaml.j2`).
> Shell scripts stay inline-quoted (never YAML-parsed). Rendered
> **compose files are still YAML** — `docker compose` parses them at deploy — so 1P-sourced
> `env:` values use `>-` there TOO (a `"` in the value breaks the entire rendered file;
> plain non-secret env strings stay quoted). **TOML:** has no `>-`; use a basic string with Jinja escaping
> (`| replace('\\','\\\\') | replace('"','\\"')`) so a value containing `"` or `\` still parses
> (`tuwunel.toml` precedent). Validators: `validate-docker-services.py` mocks lookups, so
> it does not catch a secret-as-inline-quote; the audit is `grep` across `templates/**/*.j2` for
> `: "{{ lookup('community.general.onepassword'` in a *config* (non-compose) file.
>
> **Compose `$`-interpolation — escape `$` → `$$`, and only in compose-parsed text:**
>
> `docker compose` performs raw-text `$`-interpolation (`${VAR}` / `$VAR`) over the **whole rendered
> compose file BEFORE YAML parsing** — YAML quoting, `>-` folding and block scalars do **NOT** protect
> a literal `$` in a value. A 1Password secret whose value contains a `$` (e.g. `…$PoZcG…`) is therefore
> parsed as compose variable `PoZcG` → defaulted to blank → the running config is **silently truncated**
> at the `$`. The `docker compose config --quiet` validation only *warns + blanks*, never fails, so it
> misses the drift — it only emits
> `The "<token>" variable is not set. Defaulting to a blank string.` per affected value.
>
> **Fix, Layer 1 (source, primary):** prefer generators whose alphabet **excludes `$`**, so rotated
> values are natively safe forever — `provision-secrets.py` `gen_pw()` and `gen_token()` never emit `$`,
> so every rotation through `--rotate`/`--rotate-all` is `$`-free at birth. `wg genkey` is the authoritative
> source for the wg private keys.
>
> **Fix, Layer 2 (defensive, at render):** escape a 1Password field **only when it lands in compose-parsed
> text** — append `| replace('$','$$')` to the Jinja expression:
>
> ```yaml
> SECRET: >-
>   {{ vault['secret'].password | mandatory | replace('$', '$$') }}
> ```
>
> `$$` is the Compose escape ("prevents Compose from interpolating a value"); YAML parses it back to
> a literal `$`. This is safe against **any** future secret source (hand-pasted, vendor-rotated, OIDC
> glue) regardless of rotation-by-hand.
>
> **Scope — escape ONLY in compose text, NEVER in a plain config file:**  interpolation applies
> only to docker-compose-parsed YAML. In a **non-compose** config template (`config.yaml`, `keepalived.conf`,
> `middlewares.yml`, `tuwunel.toml`, `prometheus-web-config.yml`, `recyclarr.yml`) the value is read by the
> app **as-is** — a `$$` there would be a **literal `$` you did not want** and would corrupt the secret.
> So the rule is **not** "escape every vault ref":
>
> - **Escape** every vault ref inside a `docker-compose.yml.j2` (Population A — compose interpolates it).
> - **Do NOT escape** vault refs inside non-compose config templates (Population B).
> - **Exempt the two composed `DATABASE_URL` values** (`zipline`, `litellm`) — their secret halves are
>   already `urlencode`'d, and `urlencode` writes `$` as `%24`, so no `$` survives; adding `replace`
>   would corrupt the URL.
>
> **Idempotency note:** `replace('$','$$')` is a single-layer escape. Applied once to a value the pool
> already keeps `$`-free it's a no-op; never chain the filter (it would double a pre-existing `$$`).
> Validator coverage: `validate-docker-services.py` unit-CI fixtures should be extended to assert the
> escaped vs un-escaped render; the live check is `docker inspect` env equal to the vault value.

---

## Type Map — one per `<type>`, with canonical examples

> There is **no `server` type** by design — host/login/port are connection *config* kept in Git IaC;
> 1Password holds only *credentials*. See *Config vs credential split* above.

| `type`       | 1Password item    | `field=`              | Examples |
|--------------|-------------------|-----------------------|----------|
| `login`      | Login             | `password`            | SMTP/SMTP-relay creds (`smtp_login`), admin accounts (`mikrotik-admin_login`, `grafana_login`, `authentik_login`), any username+password combo |
| `password`   | Password          | `password`            | shared / opaque secrets with no username: webhook HMAC, VRRP (`ha-vrrp_password`), upsmon (`nut_password`), repo master (`kopia_password`), Django `SECRET_KEY` (`authentik_password`), Matrix bootstrap shared secret (`matrix_password`), Headplane cookie/session signing secret (`headplane_password`), WireGuard private key (`wg_password`) |
| `api`        | API Credential    | `credential`          | tokens & keys: Cloudflare (`cloudflare_api`), Forgejo (`forgejo_api`), HA long-lived (`ha_api`), HA failover trigger (`ha-failover_api`), headscale OIDC (`headscale_api`), Headplane → Headscale API key (`headplane_api`), 1Password service-account (`op_api`), signal-cli (`signal_api`), Matrix alert bot (`matrix-alerts_api`), PrivadoVPN WireGuard client key (`privado-vpn_api`), Matrix/Authentik OIDC client (`matrix_api`), Meteoblue weather key (`meteoblue_api`) |
| `oidc`       | API Credential    | `username`=`client_id`, `credential`=`client_secret` | **OAuth2/OIDC client credentials** — the 1Password item holds the Authentik-generated client_id (in `username`) + client_secret (in `credential`), seeded by the secret-egress glue. e.g. `immich_oidc`, `opencloud_oidc`, `forgejo_oidc`. **Use `oidc`, NOT `api`**, for a service's OIDC *client* — this keeps it distinct from service API tokens (e.g. `forgejo_api` = the renovate git token, vs `forgejo_oidc` = the Authentik login client). Items older than this rule (`matrix_api`, `headscale_api`, `openwebui_api` for OIDC) are grandfathered under `api`; do not rename them. |
| `db`         | Database          | `password` (also `username`) | platform DBs: `authentik_db`, `opencloud_db`, `immich_db`, `forgejo_db`, `onlyoffice_db` — Database item holds both `username` (DB user) and `password` |
| `ssh`        | SSH Key           | `private_key` / `public_key` | `domen_ssh`, `ansible-admin_ssh`, `ai_ssh` — item stores both halves; read whichever the consumer needs |

> **Guidance:**
> - `login` = anything with a **username** (admin accounts, SMTP relays). One Login item per service — e.g. a service that has both an admin login and an SMTP relay gets two items: `grafana_login` + `smtp_login`.
> - `password` = a shared/opaque secret with **no username** (tokens for HMAC/VRRP/upsmon, repo/SECRET keys).
> - `api` = a **credential/token/key** for an API (including S3 and service-account tokens). API Credential items use `username` for access-key/client-id where applicable and `credential` for the secret.
> - `db` = Database item (`username` + `password` fields). Field for postgres link/password is `password`.
> - `ssh` = SSH Key item (`private_key` + `public_key` fields). See SSH Key Separation below.
> - `oidc` = an OAuth2/OIDC **client** (client_id + client_secret), seeded by the Authentik glue. Prefer `oidc` over `api` for a service's OIDC login client to avoid mixing with that service's API token. (Some early OIDC items use `api`; grandfathered.)

---

## Creation & Rotation Workflow

> Canonical index: CONVENTIONS §2 rows "Secret creation path / Seed before converge / Rotation propagation / Item-reference coverage" — this section carries the mechanics.

**1. Pick the creation path — every item is exactly one of four:**

| Path | When | How |
|------|------|-----|
| **Catalog-generated** | value is a fresh random secret with no external source | add a row to `provision-secrets.py` CATALOG (`--create` never overwrites existing items), then seed via `provision-vault.sh` from the WSL runner |
| **Manual-value** | value originates outside the homelab (provider dashboard, human-chosen password, alias address) | create the item by hand in 1Password; still add catalog/docs rows so scanners and docs know it exists |
| **Glue-seeded** | OAuth2/OIDC client for an Authentik-backed service (`*_oidc`) | NEVER hand-create and never put in CATALOG — the `authentik-secret-egress` glue generates and persists these at blueprint apply |
| **Externally-coupled** | rotation would break live state (DB cluster init-once passwords, admin bootstrap, shared HMAC keys) | may be catalog-created once, but MUST sit in `NOT_AUTO_ROTATABLE` with a stated reason; rotation = manual vault edit + explicit re-wire runbook |

**2. Order of operations (fail-loud invariant):** items exist BEFORE the playbook that renders their consumer runs — 1Password lookups fail loud mid-converge otherwise. Sequence per deploy: `check-vault-items.sh` → seed gaps (`provision-vault.sh`, or manual) → converge.

**3. Rotation propagation contract:** a rotated vault value reaches live state ONLY through (a) compose/config re-render on the next converge, or (b) an explicit sync task (`db_role_sync` ALTER ROLE guard; `db_ro_sync` read-only role ensure). If neither path exists for an item, it belongs in `NOT_AUTO_ROTATABLE` — silent divergence between vault and live state is what these guards exist to prevent.

**3a. How `db_role_sync` decides:** it is compare-first, and the thing it compares is a marker it owns — `COMMENT ON ROLE <role>` holding `pgsync:<sha256 of the vault password>`, written in the same `-1` psql transaction as the `ALTER ROLE`. Absent marker or different hash ⇒ repair; otherwise the task reports `changed=0`. ⛔ **Why not probe the password directly:** the VPS cluster's loopback TCP auth is `trust` (measured), so "connect with the vault password" succeeds against ANY password — a probe that can only say yes is worse than no probe, it launders drift into green — and connecting from the container's own bridge IP is refused. ⚠ **What the marker cannot do:** it records what the sync last wrote, not what the cluster currently holds. A hand-run `ALTER ROLE` is therefore out of band and will not be auto-repaired; the supported paths are rotating in vault (the hash changes ⇒ forced re-sync) or clearing the marker (`COMMENT ON ROLE <role> IS NULL`). The `nut` role uses the same shape: converge-owned state, asserted through a value the converge owns.

**4. Coverage contract:** when a change introduces a NEW group_vars key class that references a vault item (e.g. `db_ro_item`), the same change extends `check-vault-items.sh` to scan that key class — scanner blind spots defeat the fail-loud chain.

**5. Glue concurrency & 1P budget:** the two bootstrap glues (`authentik-secret-egress`, `litellm-bootstrap-keys`) both fan out their vault reads/probes in parallel under a shared 1Password rate-limit budget (`OP_PARALLEL`, default 6 — never exceed ~6 concurrent `op` calls; only curl/docker-exec HTTP probes may go wider; hosted 1P rate-limits can block 15min+). Authentik may parallel-write distinct *oidc* items; LiteLLM keeps mint/store serial (unique-alias invariant). The full mechanism × layer × direction table + extensibility rule lives in [`scripts/README.md`](../scripts/README.md) §Parallel 1Password operations. If a third glue loop is ever added, copy that bounded fan-out pattern — do NOT merge the scripts.

**6. Glue-routing index — which doc owns which secret-glue step (SSOT for findability):**

| Lookup | Owning doc | What it covers |
|--------|-----------|----------------|
| Configure / create OIDC clients + Blueprint | [`deployment-oidc.md`](deployment-oidc.md) | Authentik Blueprint + egress-glue mechanics (procedural) — the secret-egress glue step (`deployment-oidc.md` §3), deploy ordering, per-service OIDC recipes |
| Rotate an OIDC client secret | [`services-authentik.md`](services-authentik.md) §"Rotating a shared Authentik OIDC client secret" | the on-host rotation runbook (verify + edit + re-render consumers) |
| Rotate the shared RouterOS `admin` password (`mikrotik-admin_login`) | [`network-ops.md`](network-ops.md) §Rotating the shared admin password | vault `old-password`/`password` update → re-render `render-converge.yml` + `render-routeros.yml` → apply per device via `routeros-apply-delta.sh`/`apply-converge.yml` → verify from a Mgmt-sourced API path |
| AI-stack items + LiteLLM scoped-key glue | [`deployment-ai-stack-secrets.md`](deployment-ai-stack-secrets.md) | AI 1P item creation, OIDC wiring, LiteLLM bootstrap-keys rotation/rollback |
| Rotate the spark engine bearer (`spark-llm_api`, `litellm-engine_api`) | [`deployment-ai-stack-secrets.md`](deployment-ai-stack-secrets.md) §4a | the coupled bearers (engine accepted-key **list** + both LiteLLM envs + laptop `models.json`), the single-window rule and the write-scoped-token location |
| Retire an SSH grant, or audit who may SSH into a host | [`deployment-secrets.md`](deployment-secrets.md) §Who is authorized where | the per-host grant inventory + the reversible retire sequence above; `scripts/gate/check_ssh_grants.py` is the gate |
| The two glue scripts' parallel implementation + concurrency budget | [`scripts/README.md`](../scripts/README.md) §Parallel 1Password operations | layer × direction × concurrency table, the 1P budget, extensibility rule |

> Findability rule: if you search for "which glue / who provisions / how to rotate" a secret, start here; the row routes you to the owning doc. Do NOT re-author glue mechanics in multiple docs — each row is a single source.

**7. Writing a manual value from the CLI without leaking it (and without writing it wrongly):** hand
creation in the 1Password UI is the default for the manual-value path; when the write has to happen
from a runner, these rules are what make it safe *and correct*:

- **Never pass the value as an argument.** `op item edit <item> "field=<value>"` puts the secret in
  `argv`, visible to every process on the box. Values move through files (0600, `shred -u` after) or
  templates, and only **lengths/hashes** are ever printed (CONVENTIONS §6).
- **`op item create --template` with a `fields` array does NOT fill the category's built-in fields — it
  APPENDS new ones and leaves `username`/`password` empty.** The item then looks correct (`op item get`
  shows both values under the right labels) while every **label-based** read — `op://…`, the
  `onepassword` lookup, `op-vault-export.py` — resolves the empty duplicate. Rendered compose then
  carries empty credentials, which is the silent class these guards exist for. Verified on op CLI 2.39.0
  for `create --template` **and** `edit --template` with a fields-only template.
- **The correct CLI shape is a round-trip:** create the item **bare** (title/category/vault/tags),
  `op item get … --format json` → set `value` on the fields whose **`id`** already exists →
  `op item edit … --template <file>`. Pipe the template on stdin instead of writing it to a file
  (`op item get --format json | op item edit <item>`): the item JSON carries the value, so a file copy
  is one forgotten `shred` away from a plaintext secret in `/tmp`. ⚠ One artifact of the round-trip on
  an API-Credential: the built-in DATE fields `validFrom`/`expires` come back **materialised as `0`**,
  and `op item edit <item> 'expires=[delete]'` refuses them (`values for field type date must be
  YYYY-MM-DD or epoch time format`) — `0` is op's own unset-for-a-DATE and no consumer reads those
  fields (`field=credential` only), so leave them.
- **A redaction is only as good as the shape it was written against.** A filter that masks `KEY=value`
  does NOT cover the same secret in the rendered-config form `KEY: "value"` — which is what a compose
  file prints — so a `grep` over a rendered compose with a `KEY=`-shaped redaction puts the live value
  in the transcript. Redact by **value**, never by the `=` operator, and prefer the hash probe below.
  Nothing in the suite catches that shape: the one secret-shape scanner,
  [`scripts/gate/check_secrets.py`](../scripts/gate/check_secrets.py), reads the **git index plus
  untracked non-ignored files** (and archive members), not transcripts, `/tmp` run captures or live host
  state, and its shapes carry no headscale-preauth-key pattern (`hskey-auth-…`) and no `authkey`/`TS_AUTHKEY`
  keyword — measured: neither `TS_AUTHKEY=<value>` nor `TS_AUTHKEY: "<value>"` matches any of its ten
  shapes. That is a coverage gap stated as a finding, not a gate to invent: what a transcript leak
  leaves behind (including the copies the run capture writes under `/tmp/pi-subagents-*/`) is only ever
  closed by **rotating the value and expiring the old one** (docs/1password.md §Output hygiene).
- **Reading a rendered secret file is how item 7 happens.** Never `cat`, `sed -n`, or `docker exec cat` a
  rendered secret file to *inspect* it — the inspection prints the value. Pull the one field into a shell
  variable and print only its shape, and enumerate the surface without values:
  `v=$(awk -F' *= *' '/^[[:space:]]*api_key/{print $2}' f); printf '%s' "$v" | sha256sum | cut -c1-12; printf '%s' "$v" | wc -c` ·
  `grep -oE '^[a-z_]+' f | sort -u` for the key names · `stat -c '%a %U:%G %s' f` for the shape. A file that
  is `0600` on the host is still plaintext to the converge that reads it, and to whoever runs `exec cat`.
  Proving a consumer agrees is a **prefix comparison between two such variables**, never a diff of the files.
- **Reading a PROCESS ENVIRONMENT is the same act, and it is the shape nothing guards.** Never dump
  `/proc/<pid>/environ`, never `grep`/`cat` an environment, never `env` / `set` / `printenv` into a
  transcript. The environment of a control node or a seat carries `OP_SERVICE_ACCOUNT_TOKEN` — the
  `op_api` read-scoped token that reads **every other item in this vault** (§Item catalogue, `op_api`) —
  plus whatever `GIT_*` / `VAULT_*` / provider tokens the invocation exported, so a filter shaped like
  `grep -iE "^(GIT|OP|VAULT|AWS|TOKEN|SECRET|KEY)"` is not a filter: it prints all of them, in plaintext,
  into the session capture and into every `/tmp/pi-subagents-*/` copy the run writes. **A diagnostic that
  lists "interesting" environment variables is a secret read wearing a lab coat**, and it is the first
  thing an agent reaches for when a process looks hung — which is why the rule is about the *shape of the
  question*, not about carelessness. Ask it as a **COUNT** or a **HASH** instead, and the answer is the
  same answer: `tr '\0' '\n' < /proc/<pid>/environ | grep -c '^OP_SERVICE_ACCOUNT_TOKEN='` → `0` = the
  process was started without the token, `1` = it was started with it; to tell two processes' credentials
  apart, `tr '\0' '\n' < /proc/<pid>/environ | sed -n 's/^OP_SERVICE_ACCOUNT_TOKEN=//p' | sha256sum | cut -c1-12`
  and compare 12 hex characters (the same hash-the-holder rule as [1password.md](1password.md) §Proving
  which service account an install holds). What already crossed a transcript cannot be scrubbed — the
  capture lives outside the repo and is appended for the life of the session — so the only close is
  ROTATING the item ([1password.md](1password.md) §Rotating the control-node token), and
  [`scripts/gate/check_secret_leak.py`](../scripts/gate/check_secret_leak.py) is the eye that says whether
  it is still sitting there: it compares CURRENT values across the tree, the run-capture class **and** every
  blob a ref still reaches (the `git-history` class — a value that was `git rm`'d is out of the tree but not
  out of the publication, and only rotation closes that one).
- **The session transcript is the capture surface, and the verdict about it is SEAT-LOCAL.**
  `~/.pi/agent/sessions/**/*.jsonl` — the pi parent transcripts plus each child's `session.jsonl` — is appended
  for the life of a session, lives outside the repo and outside git, so no commit can scrub it and the only close
  is ROTATING the item. This is the HD-1174 class (a vault value readable in a capture —
  [backup.md](backup.md) §Layer 2: Kopia) with a **wider door**: the loud door is any command whose stdout the
  session captures, the quiet one is **the chat input itself**, because a value typed into a prompt is a transcript
  line from the moment it is typed. ⛔ **A rotated value stops being a finding — [`check_secret_leak.py`](../scripts/gate/check_secret_leak.py)
  compares CURRENT values — while an UNROTATED one is never closed by deleting, shredding or `git rm`-ing a
  transcript.** Deleting the store removes evidence and not exposure: the value stays live in the vault and in
  every other copy the session wrote, and the run after the deletion prints *greener while knowing less*.
  ⚠ **A green is a statement about the seat it was taken on.** The `run-capture` class reads the seat's own
  stores, so two checkouts of one commit do not reach the same verdict (the Win11-seat class, [harness-pi-seats.md](harness-pi-seats.md) §1, with a sharper edge).
  Measured 2026-10-21 against one vault at one commit: on the seat that has the store, **1,858 paths / 233 MB**
  scanned and the item failed with 24 hits; with `$HOME` pointed at an empty directory the same commit scanned
  **1,559 paths / 22 MB**, still listed `classes judged: [… run-capture]`, printed 24 real ledger debts as STALE
  and exited **0** — `/tmp/pi-subagents-*` keeps that class's corpus non-empty even when the transcript store is
  gone, and the `--update-ledger` guard decides per CLASS, so it cannot see a missing store inside a class it
  judged and would let that run shorten the debt register. Name the seat with every leak-check verdict, and treat
  a store-less clone's `OK` as a partial result (the honest form of the same run is `--no-captures`, which prints
  `NOT SCANNED run-capture` and marks the line `PARTIAL`).
- **Containment is not remediation.** Overwriting a leaked value's copies — in a capture, a host log, a committed
  raw artifact — lowers how many places a credential can be read from and changes nothing about the credential
  itself. It is permitted for the values this fleet **cannot** rotate, it is run by hand and never by a gate, and
  the debt line stays open until the item rotates. The distinction the tooling must keep: a contained pair prints
  **contained**, never `STALE` and never `OK` — a scanner that only asks "is the current value still here" reads a
  redaction and a rotation identically, so it is a receipt, never a hit count, that tells them apart
  ([`scripts/gate/secret_leak_ledger.txt`](../scripts/gate/secret_leak_ledger.txt)'s `STALE` means *rotated*, and a
  contained pair is not rotated). Containment that leaves no receipt is indistinguishable from hiding, which is what
  that header forbids. **The instrument is
  [`../scripts/secrets/contain-leaked-values.py`](../scripts/secrets/contain-leaked-values.py)** — manual
  invocation only, `--dry-run` by default, scope DERIVED from the register's `path: none` column and held
  against `NOT_ROTATABLE` at the moment of the act; it refuses a git object store, the repo tree and its
  IaC, rendered live config, its own receipt and the invoking lane's own live capture. It appends one 0600
  row per pair — `(item, class, seat, paths, occurrences, vault version, ts)` — to
  `~/.local/state/homelab/containment-receipt.jsonl` (`$HL_CONTAINMENT_RECEIPT`, per-seat state and never
  repo content), and `check_secret_leak.py` reads that file to print `CONTAINED` with the copy count. **A hash of a live value is not the rotation check** for the same reason a hash is not a
  proof anywhere else here: a short credential's hash is an offline guess-check; the vault's per-item `version`
  answers "rotated yet" and reads no value at all ([1password.md](1password.md) §Output hygiene).
- **A mask at the output seam prevents; it closes nothing, and it can hide.** The pi harness exposes a
  chained, redaction-capable `tool_result` hook, and every debt in the register arrived as a captured
  command output, so that hook is the only seam where a value can be stopped before the session JSONL is
  written. `pi-agent/extensions/vault-mask.ts` is that hook, **enabled — deployed to every seat by the
  `extensions` plane**, its arms kept out of that plane's glob. What it prevents:
  the next capture of a CURRENT value by a lane that was never asked to print one. What it could hide: a
  lane that reads masked output believes the value is gone — the marker is not a redaction of the vault,
  the debt stays open, `check_secret_leak.py` still finds the copy that was written before the hook
  was enabled, and a rotation leg that has to COMPARE a value would be working blind, which is why the bypass
  (`HL_VAULT_MASK_BYPASS`) is loud and process-scoped rather than a setting. The switch is PLACEMENT: the
  file under `pi-agent/extensions/` is loaded by every session on every seat, the same file under
  `pi-agent/proposed/` by none — a fleet-wide harness change and an owner call, not a lane's
  ([harness-pi-seats.md](harness-pi-seats.md) §1, "An extension's placement is its enable switch").
- **A minted preauth key is captured, never displayed.** headscale 0.29.4 has no `--output <file>` —
  `-o` is the FORMAT flag — so `preauthkeys create … -o json` writes the value to stdout, and the
  documented mint commands in this repo and in `deployment-manual.md` are therefore only safe inside a
  pipe. Capture it in the same expression: `mktemp` (0600) → ssh+docker create piped into a parser that
  writes the value into that file and prints only `id`/tags/expiry → the vault write → `shred -u`. Prove
  the shred with `ls` and a `grep -c` over every log the run created.
- **Verify by length *and* shape**, not by "the command exited 0":
  `op read op://<vault>/<item>/<field> | wc -c` for each field, plus a field-list check that each
  expected `id` appears **exactly once**. An empty `wc -c` on a field that should hold bytes means the
  duplicate-field shape bug above, not a missing value — fix the item before any converge renders it.

**8. Token scope: PROBE it, do not inherit it.** Two tokens reach this vault and their scope is a property of
the token, not of the vault, so it must be re-read wherever you stand. **Measured 2026-10-19 on the WSL seat:**
the **ambient** `OP_SERVICE_ACCOUNT_TOKEN` installed by `bootstrap-runner.sh` answers `op item list` (141 rows) and
`op item get`, but its `op item edit` fails with `Couldn't update the item.` — read-scoped on that seat — and the
IDENTICAL template write succeeds only once `op-write_api` is the token (the `tailscale-sidecar_api` row's route).
An earlier revision of this item asserted the opposite ("the ambient token is **not** read-only — it performs
`item delete`/`create`/`edit` without `op-write_api`"), which was true of some other seat and cost a rotate lane
two dead attempts. So: **try the write, and if it fails, fall back to `op-write_api`** — never conclude from
"the docs say the ambient token writes" that a failing `item edit` is a template-shape bug; it is usually scope.
Scripts that fetch `op-write_api` because "the exported SA token is READ-scoped" (`rotate-spark-llm-key.sh`, its
[`scripts/README.md`](../scripts/README.md) row) are therefore correct on this seat and were not wrong elsewhere:
what is wrong is asserting either scope from prose. Do not treat a write-capable token as permission to write from an
automation path that was designed to be read-only.

**9. A leak debt is a debt against a VALUE, so a book of hits is not a book of debts.** Two machines
hold that, and neither is the leak ledger:

- [`scripts/gate/secret_debt_register.txt`](../scripts/gate/secret_debt_register.txt) is the ledger's
  **companion**, one `<item-id-prefix>\t<class>\t<seat>\t<vault-version-at-leak>\t<path>\t<rotation-doc>`
  line per debt. It is a separate file because the ledger is a **render view** — `--update-ledger`
  rewrites its body, so anything hand-authored into it dies at the next re-derive — the SSOT rule of
  [CONVENTIONS.md](../CONVENTIONS.md) §2, applied to a debt list. `path:` is the ruling on WHO acts: `lane` (a vault rotation this lane can
  drive), `lane+converge` (the vault write plus the host or app act that makes it live), `human` (the
  act is an owner's or a provider's), `none` (no channel at either end — the line is then a standing
  exposure that only containment shrinks). The `rotation-doc` column points at the doc that carries
  the actual steps, because a debt list that restates them is a second copy of a runbook.
- [`scripts/gate/check_secret_debt.py`](../scripts/gate/check_secret_debt.py) answers **`rotated
  yet?`** from the vault's per-item `version` numbers (the same reason a hash is not the check: a short
  credential's hash is an offline guess-check, a version reads no value at all) crossed with the
  ledger's pair set. The read is names-first — one request, no value at all — and the tool says so
  when this SDK release's list rows carry no versions and the batched read had to answer instead;
  values reach memory, never the print. The verdicts: `NOT ROTATED` (version unmoved, hit standing) /
  `CANDIDATE` (version moved, hit standing — rotate-then-re-derive, the propagation half is missing) /
  `CLOSED` (version moved AND a
  re-derive proved the pair absent) / `GONE` (the vault answers no such item) / `NOT JUDGED` (another
  seat's line, or a store this run could not read). The pair the ledger alone cannot tell apart is the
  reason the checker exists: a pair that LEFT the ledger with its version UNMOVED prints `REFUSED` and
  exits 1 — a redaction, a shredded store or an edited book makes a hit disappear, and in a book of
  hits that is indistinguishable from a rotation. The other red word is `UNLEDGERED`: a register line
  whose pair the ledger names nowhere — in the tree or at `HEAD` — which is the shape a live finding
  takes when the ledger rightly refuses to mute it (the bullet above: no ledger line for a CURRENT
  value). The two are told apart by the ledger at `HEAD` (one `git show`, values never touched), and
  both are red — an unreadable HEAD keeps the harsher word, so the vocabulary can only ever make a run
  redder, never quieter.
- **The seven verdicts are classified, and the classification is a ruling, not an exit code that fell
  out of the implementation.** One question draws the line: does the verdict say something is wrong
  IN THE TREE, or that something is still owed IN THE FLEET? Reminder semantics are
  [CONVENTIONS.md](../CONVENTIONS.md) §6.4.
  - `BLOCKING` — `REFUSED`, `UNLEDGERED`, exit 1. The first is a hit that vanished with no version move,
    which is a close no rotation backs; the second is a CURRENT value the ledger rightly does not mute,
    so the book may not calmly table the finding the leak gate is reddening on. Neither is clearable by
    editing a book, which is what a blocker must be.
  - `REMINDER` — `NOT ROTATED`, `CANDIDATE`, exit 0. An open debt whose act is owed, by the actor the
    register's `path:` column names, in the doc its `rotation-doc` column names — so the line prints
    with its actor instead of becoming somebody's permanent red. It re-derives itself from the vault's
    `version` numbers on every run (no frozen seal to rot into yellow — CONVENTIONS.md §6.4), and it must
    never be
    promoted to a blocker: the `path: none` lines are credentials an ISP provisions and a network
    account whose reset mail never arrives, so a red on this word would be true forever, and a gate
    that is always red is a gate that gets scrolled past.
  - `STATE` — `CLOSED`, `GONE`, `NOT JUDGED`, exit 0. The book's own condition: a line to delete, an
    item the vault no longer answers, a line only another seat or another store may judge.
  - ⛔ What the reminder class does not mute, and cannot: a CURRENT value. That red lives in
    [`check_secret_leak.py`](../scripts/gate/check_secret_leak.py), which reads no register and is not
    the debt checker's to edit; a debt whose exposure is already declared in the ledger is a stated
    debt, and this class says only who still owes the act. `check_secret_debt.py --self-test` is what
    makes the sentence above a fact: an arm proves each verdict prints in the class it is filed under,
    that the classes are disjoint and cover the vocabulary so the printed legend cannot drift from the
    code, that a verdict left out of every class is BLOCKING rather than quietly green, and that moving
    a red word into the reminder class really does turn the exit green — which is the proof that the
    red on a live finding is the classification working and not an accident of the fixture.
- **Locality is part of the verdict.** A `run-capture` line is judged per STORE, so a checkout without
  the persistent transcript store cannot close its own lines (the measurement in the bullet above is
  why), and a line is closable only by the seat that recorded it. A seat the book carries no line for
  prints `NOT RECORDED`: a debt in a store nobody read is unknown, not absent.
- **The ledger is seat-blind and the derivation is not, so a one-seat re-derive cannot be trusted with
  another seat's `run-capture` line.** [`secret_leak_ledger.txt`](../scripts/gate/secret_leak_ledger.txt)
  is keyed `<item-id-prefix>\t<class>\t<title>` with no
  seat column, while `--update-ledger --class run-capture` derives from ONE seat's capture stores. The
  drop guard therefore asks a class question where the debt is a seat question: it prints
  `dropped <item> run-capture … — proven ABSENT this run` for a pair that is live in a store this run
  never read (measured: a `win11` re-derive drops 4 lines whose debt sits in `wsl`'s stores), and what
  it actually proved is that THIS seat's stores do not hold it. The same blindness shows on the read
  side: a one-seat scan prints those foreign lines under `STALE ledger lines (no hit this run)`, which
  invites somebody to delete a debt another store still holds — a class the run did read is treated as
  evidence about every store, and it is evidence about one. The correct act is per-seat and
  additive: on each seat derive into a temp book through the tool's own `$HL_LEAK_LEDGER` seam, then
  commit the UNION of those books — never a single seat's derivation over the committed file. ⛔ A
  `run-capture` line leaves this book only on the seat that recorded it, and a line whose pair is
  carried by two seats is two debts, closed once per store. Making the drop guard seat-aware — so a
  one-seat run cannot drop a line another seat recorded — is the machine half carried by the row that
  links here.
- **The no-rotation-path ruling lives in two places and an arm holds them equal**: the register's
  `path: none` column, and `NOT_ROTATABLE` in
  [`scripts/secrets/provision-secrets.py`](../scripts/secrets/provision-secrets.py). It is NOT
  `NOT_AUTO_ROTATABLE`, which is step 3's ordering guard and asserts only that a far end exists to act
  on — folding the two would let "auto-rotation can't do it" be read as "nothing can", which is the
  claim that made containment legal for a value that was rotatable all along.
- **The gate that stands between a commit and the remote** is a `pre-push` hook installed by
  [`scripts/git/install-hooks.sh`](../scripts/git/install-hooks.sh) (seat plane `git-hooks`, so a clone
  without it is reported rather than assumed). It runs the tree-only leg — one leg, seconds, one
  batched read — and prints the two classes it did not look at. ⛔ A green push is repo-tree clean and
  is not a clean fleet, and it closes no debt: a secret that reached a remote is closed by ROTATING it,
  never by scrubbing the commit, because the remote keeps the old blob and a force-push is a fetch away.

---

## Master Secret List (canonical)

| Item name | `field=` | Used By |
|-----------|----------|---------|
| `github-homelab-deploy_api` | `credential` (API-credential item; username = the deploy token's username) | **The runner clone's read-only GitHub pull** (`/home/ansible-admin/source/homelab` on oldsrv). Fine-grained, repo-scoped, **read-only by design**: proven by a `403` on `git push` and on `git push --dry-run`. ⚠ What it buys and does not buy: `domenkogler/homelab` is a **PUBLIC** repo (`api.github.com`), so this token is scope + a non-interactive identity, **not** code confidentiality. Placed as a 0600 `~/.git-credentials` store under `ansible-admin`, never embedded in the remote URL and never copied into another account (the seat has its own key below). Rotating = re-place the store file, then prove with `git fetch`. · [deployment-ansible.md](deployment-ansible.md) §Runner placement |
| `GitHub-homelab-deploy_ssh` | SSH_KEY item: `private_key` / `public_key` / `fingerprint` / `key_type` | **The seat clone's write path** (`/home/domen/source/homelab` on oldsrv; the item's name carries a capital `G`, which is why searching `github-homelab…` finds only the API token). Category SSH_KEY, ed25519, `fingerprint` `SHA256:dGe193grwS3d74i7I…`. ⛔ Read it with **`op read op://…/<field>`** — `op item get --fields <SSHKEY field>` returns a pretty-wrapped PEM that `ssh-keygen` cannot load. Consumer: `scripts/ansible/seed-seat-deploy-key.sh`, which installs it under `domen` only and proves the grant with `git push --dry-run`. **Registered on `domenkogler/homelab` as a deploy key WITH write access**, proven from the seat (`git push --dry-run` rc 0; GitHub greets it as `Hi domenkogler/homelab!`, the repo-scoped shape a deploy key takes). A deploy key whose public half is not registered on GitHub is installed, offered on the wire and refused. Rotating = re-register the new public half on GitHub first, then re-run the script; a repo whose only write path is a deploy key is one browser tab away from unpushable. · [deployment-ansible.md](deployment-ansible.md) §Runner placement · [deployment-manual.md](../deployment-manual.md) Phase 4c step 8 |
| `GitHub auth` | SSH_KEY item: `private key` / `public key` / `fingerprint` / `key_type` | **GitHub SSH transport on Debian machines** — installed as `~/.ssh/github_auth` and pinned in `~/.ssh/config` (`Host github.com` + `IdentitiesOnly yes`) by `git-bootstrap.sh --ssh-auth`. ed25519, `fingerprint` `SHA256:ru2YMF+u…`. ⚠ On the **oldsrv seat** transport is NOT this key: the repo-scoped `GitHub-homelab-deploy_ssh` deploy key is used there, and `seed-seat-deploy-key.sh` writes the `Host github.com` block first — `git-bootstrap.sh` sees an existing block and leaves it alone. A push attributed to the wrong credential is an `IdentitiesOnly`/block-order question, not a vault question. · [deployment-ansible.md](deployment-ansible.md) §Runner placement |
| `domen_ssh` | `private_key` / `public_key` | post_install.sh — Domen's personal key → `ansible-admin` |
| `ansible-admin_ssh` | `private_key` / `public_key` | post_install.sh — dedicated Ansible key → `ansible-admin` |
| `ai_ssh` | `private_key` / `public_key` | post_install.sh — AI debug key (maps to `openrouter_ai`) → `ai-debug` |
| `netcup-ccp_login` | `password` | netcup — **Customer Control Panel** login (item `netcup-ccp_login`, 1Password `Homelab-ansible`). Billing / orders / subscription management at netcup. **NOT** consumed by Ansible (SSH provisioning, see `ansible-admin_ssh`) — account reference only (netcup RS 2000 G12) |
| `netcup-scp_login` | `password` | netcup — **Server Control Panel (SCP)** login — per-VPS admin/console (reboot, reinstall OS, KVM/console access, root password reset). Root-level access to the box; **break-glass** fallback if SSH is unavailable. Ansible still authenticates via `ansible-admin_ssh` by default |
| `netcup-vps_login` | `password` | netcup — **root/OS access** to RS 2000 G12: root password + IPv4/IPv6 (`159.195.111.66` / `2a0a:4cc0:60:fcc:*`). **Deliberately in a SEPARATE 1Password vault (NOT `Homelab-ansible`) so Ansible cannot read it** — kept off the automation path for safety. Break-glass root fallback; day-to-day SSH is `ansible-admin_ssh` as `ansible-admin` |
| `Hertzner-SB-Data` | — (connection ref) | Hetzner Storage Box **live** (BX11 1 TB) — connection reference for CIFS/SMB + WebDAV (`u653411`, server `653411`, SSH/SFTP port 23); **SMB username + password** stored here and consumed by the **`cifs` role** (VPS live-Box mount `/mnt/storagebox`, field=`username`/`password`). Recorded under `subscriptions.yml` (`secret: Hertzner-SB-Data`) — see `subscription.md` "Hetzner Storage Box — live" |
| `Hertzner-SB-Backup` | — (connection ref) | Hetzner Storage Box **backup** (BX11 1 TB) — connection reference, **no password** (SSH-key auth). Holds URL/username (`u653424`, server `u653424`, SSH/SFTP port 23). Recorded under `subscriptions.yml` (`secret: Hertzner-SB-Backup`), not an Ansible lookup — see `subscription.md` "Hetzner Storage Box — backup" |
| `kopia_password` | `password` | kopia-server (repo master password) |
| `kopia-server_fingerprint` | `password` | **kopia-server TLS trust anchor** — SHA-256 fingerprint (lowercase hex) of the persisted self-signed cert at `/srv/docker/kopia-server/config/tls.crt`; the oldsrv agent pins it (`--server-cert-fingerprint`). **Derived value**: seeded from the live cert by the docker_services `kopia-fingerprint-sync.yml` task (NOT catalog-generated — the catalog builder returns `[]`); NOT_AUTO_ROTATABLE (rotate = regenerate cert + re-pin both sides) |
| `authentik_db` | `password` (`username` = DB user) | authentik (Postgres) |
| `authentik_password` | `password` | authentik (Django `SECRET_KEY`) |
| `authentik_login` | `password` | authentik (bootstrap admin user) |
| ⚠ `authentik-nas_api` | `api` | **Orphan — no IaC consumer, and the item is still present in the vault.** Read-only scope (family group / group members); minted durable (`expiring=False`) via `ak shell`, which is why it outlived the design that needed it. |
| `op-write_api` | `credential` (NOT `api` — the item is category API Credential but its secret field is `credential`; a lookup with `field='api'` reads an absent field and yields an empty file) | 1Password **service-account token (read+write)** for the host-side `op` CLI — deployed to `/etc/op/provision-token` (0600); the glue uses it to seed the OIDC client-credential items. Written by `roles/docker_services/tasks/op-provision-token.yml`, enabled by `docker_services_op_provision_token: true` in `home_servers.yml`, gated `scope_is_all` and mutually exclusive with the Authentik pre-pass. ⛔ A consumer must **probe** the credential (`op item list --vault Homelab-ansible` answers rows), never infer it from `[ -r /etc/op/provision-token ]` — that is how a dead token survives green converges. Refreshing the file takes a `docker_services` run at `scope_is_all` **issued from the laptop** (`self-converge-guard.yml`) — the gate cannot be narrowed, only the tag set (`--tags secret-egress` on `vps`'s pre-pass, `--tags docker_services` on a home host: [1password.md](1password.md) §Rotating the control-node token); unlike a seat file, nothing else writes it. |
| `cockpit-pi-web_api` | `credential` (API Credential item; the bearer is in `credential`, NOT `api` — a lookup with `field='api'` reads an absent field and renders an empty file) | The `PI_WEB_TOKEN` bearer behind the oldsrv coding seat, and the same bearer the `pi-oldsrv-ts` router's middleware chain validates — the two halves rotate together or every paired client re-pairs. **Consumer:** `roles/seat`, task *seat \| Render the token env file* (`roles/seat/tasks/main.yml` → `templates/pi-web-env.j2`), which reads it through `seat_pi_web_vault_item` (`IaC/ansible/group_vars/all/seat.yml` — an item named in a variable, so no template carries a literal lookup) and renders `/home/domen/.config/pi-web/env` at 0600, owner `domen`, `no_log`. The runbook's cockpit phase writes that same file as its manual step ([`deployment-manual.md`](../deployment-manual.md) §Phase 4c), so the item and the file must hold ONE value. **Deliberately absent from `provision-secrets.py`'s `CATALOG`** while the two `*-cockpit_login` rows are in it — `--create` mints a NEW random value and every paired client is bound to the live one: [`deployment-rejected.md`](deployment-rejected.md) |
| `oldsrv-cockpit_login` | `password` | The PAM password behind the `maint` break-glass identity on **oldsrv**. Consumer: `roles/cockpit/tasks/maint-user.yml`, which reads it on the control node (fail-closed: no value, no converge), crypts it **on the target** with `openssl passwd -6` and a salt derived from the item name — deterministic so the hash is stable across converges AND so the verify step can prove the installed hash IS this value — and installs it via `ansible.builtin.user`. Grants group membership `cockpit-session` (the gate) + `sudo` (the web-tty must be able to break glass) and NOTHING else: no `NOPASSWD` sudoers entry — the converge reads `sudo -l -U maint` and FAILS if a fragment ever granted one — no SSH key, and `AllowUsers` is read back and asserted not to contain `maint`. The hash is what lands in `/etc/shadow` (root-readable); the plaintext never touches the host, a log or a transcript. `cockpit-oldsrv.kogler.si` has no working login until a `--tags cockpit` converge has run against the host. |
| `nas-cockpit_login` | `password` | The same `maint` break-glass PAM identity on **nas** (`cockpit-nas.kogler.si`); same consumer, same rules, separate value on purpose (one shared item would hand two management consoles the same password, which is the opposite of why there are two). ✅ **Live + console-verified**: `maint` exists, its group set is exactly `cockpit-session` + `sudo`, the installed hash byte-matches this item, `AllowUsers` does not admit it, Cockpit accepts it at `/cockpit/login`, and re-converging is `changed=0`. The group gate is what makes this item meaningful: without it `/etc/pam.d/cockpit` authenticates any local password holder — see [security.md](security.md). |
| `smb-domen_login` | `username` + `password` | The Samba share login for the `domen` account on **nas** (`\\nas\media` + the private `\\nas\domen` drive). Consumer: `roles/storage/tasks/samba.yml`, which creates the unix account from `host_vars/nas.kogler.si.yml` `storage_samba_users` and writes this password into the local passdb with `smbpasswd -a -s` — through the environment, `no_log: true`, so the value never enters the command text or a log. `username` is NOT free-form: it must equal the account name in host_vars, or the entry is created and every mount fails. Catalog-generated (`provision-secrets.py`) for a true-zero rebuild; the converge writes it only when `pdbedit -L` lacks the account, so re-converging never resets a member's password. **Rotation:** rotate here, then converge with `-e storage_samba_password_force=domen` — a vault rotate alone reaches nothing (§2 rotation propagation). · [storage.md](storage.md) §Samba (SMB) shares on the NAS |
| `smb-shared_login` | `username` + `password` | The **service-account** Samba login (`username: shared`, no personal counterpart) whose sole share is `\\nas\music`, the Lidarr root. Deliberately not a person: `drive: false` + `/usr/sbin/nologin` in host_vars, so it can mount music and nothing else, and a laptop or a relative's machine gets the library without anyone typing a personal credential. Same consumer, same write path, same rotation rule as `smb-domen_login` above. · [storage.md](storage.md) §Samba (SMB) shares on the NAS |
| `opencloud_db` | `password` | opencloud (Postgres) |
| `opencloud_oidc` | `api` (`username` = client_id, `credential` = client_secret) | **OpenCloud native-OIDC client** — multi-redirect (web + desktop + mobile) Authentik provider, declared in the Blueprint; client_id/secret seeded by the secret-egress glue. |
| `opencloud_login` | `password` | OpenCloud **interactive admin/break-glass login** (`IDM_ADMIN_PASSWORD` in the opencloud compose) — separate from the least-privilege `opencloud-service_api` service account (above). |
| `opencloud-collab_password` | `password` | **Single shared WOPI/JWT secret across the entire OpenCloud ↔ ONLYOFFICE chain (single-secret decision)** — used on ALL of: OpenCloud `OC_JWT_SECRET` (system-wide reva token_manager secret — MUST be set so auth-minted REVA tokens validate in collaboration; absence causes “token signature is invalid” 401), OpenCloud `COLLABORATION_JWT_SECRET` (mints/verifies ONLYOFFICE REST tokens), OpenCloud `COLLABORATION_WOPI_SECRET` (mints/verifies WOPI JWT + encrypts/decrypts embedded REVA token), and ONLYOFFICE `JWT_SECRET` — all must match exactly. Generated once at deploy; fail-loud if absent. Rotation = regenerate, re-render BOTH compose files, converge, and **users must RE-LOGIN** (existing REVA tokens die). |
| `immich_oidc` | `api` (`username` = client_id, `credential` = client_secret) | **Immich native-OIDC client** — web redirects `https://foto.kogler.si/auth/login` + `https://foto.kogler.si/user-settings` + mobile custom-scheme `app.immich:///oauth-callback` (needs Authentik to accept the custom scheme, or the http(s)/Mobile Redirect Override workaround); Confidential + Auth Code; storage label `preferred_username`, optional `immich_quota`. Declared in Blueprint; creds seeded by glue. **Consumer = `tasks/immich-seed.yml`, NOT the compose** — Immich v3 reads no OAuth env var, so the seed PUTs these into the DB system config ([deployment-oidc.md](deployment-oidc.md) §Immich). |
| `immich-admin_login` | `login` (`username` = admin email, `password`) | **Immich's own admin seat** (the native e-pošta/geslo account created by the first-run wizard — NOT an Authentik identity). Owner-seeded with the real values. Consumed by `roles/docker_services/tasks/immich-seed.yml`, which must log in as it to `PUT /api/admin/config` — Immich has no API-token path for system config and no admin CLI, and the config is DB-only. Rotating the Immich admin password therefore needs a re-run of that seed lane (or nothing, if the seed is not re-run — it reads the item at run time). It is also the **break-glass login** if OIDC ever breaks, so do not lock it. |
| `forgejo_oidc` | `api` (`username` = client_id, `credential` = client_secret) | **Forgejo native-OIDC client** — web + git/API SSO on `git.`, callback `https://git.kogler.si/user/oauth2/<app-slug>/callback`; declared in Blueprint, creds seeded by glue. |
| `zipline_oidc` | `api` (`username` = client_id, `credential` = client_secret) | **Zipline native-OIDC client** — dashboard SSO on `bin.kogler.si`, callback `https://bin.kogler.si/api/auth/oauth/oidc`; declared in Blueprint, creds seeded by glue. Viewer routes + guest uploads stay anonymous by design (crowdsec-only tier). |
| `immich_db` | `password` | immich-app (Postgres) |
| `forgejo_db` | `password` | forgejo (Postgres) |
| `zipline_db` | `password` | zipline-db sidecar (Postgres metadata DB — users/links/metadata; dumped via db-backup DB05; file payloads live in the Kopia-excluded uploads tree) |
| `zipline_password` | `password` | zipline `CORE_SECRET` (session/config secret). Fail-loud at render. |
| `litellm_db` | `password` (`username`=DB user) | litellm-db sidecar (Postgres runtime DB — **keys/models/spend via STORE_MODEL_IN_DB = CRITICAL state**; dumped via db-backup **DB06**; init-once password → NOT_AUTO_ROTATABLE, rotation = re-init = data loss without dump/restore) |
| `owui-public-chat_api`, `owui-public-rag_api`, `owui-int-wife_api`, `owui-int-owner_api`, `openclaw-litellm_api`, `rag-int-svc_api` | `api` → `credential` = LiteLLM virtual key `sk-…` | per-consumer scoped auth to LiteLLM. Creation path: **glue-generated at bootstrap** — minted by POST `/key/generate` during the litellm converge and written straight into 1Password by `litellm-bootstrap-keys.sh`; NOT catalog-random (values are unprovisionable manually — they exist only server-side). Rotation semantics: delete the item's credential field AND the server key by alias in the Admin UI, re-run the glue (create-if-absent); a stale stored sk aborts loudly (rc2) since sks are hashed at rest. **Parked:** `dsh_api` + `pi-harness_openai_api` have NO consuming record any more (the `litellm_scoped_keys` entries are commented out with their consumers), so neither is minted, probed or required; the ITEMS stay in the vault untouched — `dsh_api` would trip rc2 again if the record is ever restored. Scopes/budgets SSOT: `group_vars/vps.yml` `litellm_scoped_keys`; matrix in [services-ai.md](services-ai.md) §4 |
| `onlyoffice_db` | `password` | onlyoffice-postgres sidecar (ONLYOFFICE Docs metadata/document-tracking DB — regenerable state) |
| `onlyoffice-rabbitmq_login` | `login` (`username`+`password`) | onlyoffice-rabbitmq sidecar — `RABBITMQ_DEFAULT_USER/PASS` (first mnesia init) + ONLYOFFICE `AMQP_URI`; NOT auto-rotatable (both sides coupled) |
| `forgejo_api` | `credential` | renovate (`RENOVATE_TOKEN`) — Forgejo API token. No deploy or CI role: no Forgejo runner exists on any host ([services-vps.md](services-vps.md) §Git hosting roles) |
| `grafana_login` | `password` | grafana (admin user) |
| `metabase_login` | `login` (`username` = the admin e-mail, `password`) | **Metabase's own admin seat** — the account the first-run setup wizard creates on the oldsrv instance ([services-admin.md](services-admin.md) §Metabase). Metabase OSS has no OIDC, so this is the only login the service has, and it doubles as the break-glass path. **Manual-value: owner-seeded with the real values, deliberately NOT in `provision-secrets.py`'s `CATALOG`** — `--create` would mint a password no Metabase account holds, which is a lying vault item, exactly the `immich-admin_login` case above. No IaC reads it (the compose references no such item), so `check-vault-items.sh` never asks for it and a missing item never fails a converge — the wizard is where it lands. Rotating it happens in the Metabase UI; the vault must be updated in the same sitting, because nothing propagates either way. Distinct from `metabase-forgejo_ro`, which is an intentionally-inert read-only DB grant with no consumer. |
| `smtp_login` | `password` | **SMTP relay (SMTP2Go)** — shared by Grafana (SMTP fail-safe) + NUT (UPS email notify) + HA `secrets.yaml` (rendered, consumer pending). `username` = SMTP user + notify email (`notify@kogler.si`); `password` = SMTP pass. |
| `ha_api` | `credential` | HA long-lived token → Traefik/Companion, `/api/prometheus` bearer for Prometheus |
| `ha-vrrp_password` | `password` | keepalived (VIP `ha.kogler.si`) shared auth |
| `ha-failover_api` | `credential` | HA failover trigger API — Homepage buttons + `ha-failover-api` token |
| `homelable_login` | `username`, `password`, `bcrypt_hash` | Homelable admin login — `username`/`password` = the local admin creds; `bcrypt_hash` = bcrypt(password), rendered as the backend `AUTH_PASSWORD_HASH`. Catalog-generated (Login + bcrypt_hash pair, see `homelable_login_item()` in provision-secrets.py). Rotation rewrites password + hash together. |
| `homelable_secret` | `password` | Homelable `SECRET_KEY` (JWT/session signing, ≥32 bytes) + shared `MCP_SERVICE_KEY` source when the MCP container is enabled. Catalog-generated. |
| `homelable_mcp` | `credential` | Homelable MCP server `MCP_API_KEY` (optional container) — AI-tool topology read/write. Catalog-generated; unused while `homelable_mcp_enabled` is false. |
| `rustdesk_login` | `username` = **public** key (base64), `password` = **secret** key (base64) | **RustDesk server (VPS)** — the hbbs/hbbr ed25519 keypair: `KEY_PUB`/`KEY_PRIV` in the compose; with `ENCRYPTED_ONLY=1` both binaries run `-k _`, so the PUBLIC half is what every client pins as its "Key" and the SECRET half authenticates the server to them. **Naming:** `<service>_<type>` with type = the 1Password **item type**, so this is a **Login** item — it is NOT an interactive login and there is no account behind it; Login is the category whose two field labels (`username`/`password`) both the bulk pre-pass (`op-vault-export.py`) and the `validate-docker-services.py` mock materialise, so a custom field name (or an SSH-key item) renders green and fails at deploy. The suffix also keeps it inside `check_vault_docs.py`'s derived set. **Manual-value class, NOT in the provisioner CATALOG**: `rustdesk-utils genkeypair` mints it (generation + the write rules = §Creation & Rotation Workflow item 7); this row is its coverage record. ⚠ `check-vault-items.sh` cannot see it either — the script greps literal `onepassword', 'NAME'` lookups and this template uses the `vault['…']` dict form, so **the fail-closed render is the actual gate**; seed before `enabled: true`. **NOT_AUTO_ROTATABLE — externally-coupled**: the s6 `key-secret` step seeds `/data/id_ed25519*` only when the file is absent, so the live file is authoritative and a vault edit changes nothing; rotating (replace the item **and** delete `/data/id_ed25519*` **and** re-deploy) **orphans every enrolled client**, whose stored key stops matching — re-enrolment is manual, per machine. **Backup story:** the item IS the restore (wipe `/srv/docker/rustdesk-server/data`, re-converge → the pair is re-seeded and clients keep working), which is why the seed must exist BEFORE `enabled: true` (the compose is fail-closed without it). ⚠ The pair is visible in `docker inspect` env output on that container. |
| `crowdsec-bouncer_api` | `credential` | CrowdSec LAPI bouncer key for the Traefik bouncer plugin — the value of the LAPI bouncer row **`traefik-bouncer-20261028`** (`cscli bouncers add <row> -o raw`); the row NAME is the identity and this item holds only its value, so a rotation is a new dated row + this field + a re-render, never an in-place edit · [services-traefik.md](services-traefik.md) §Middleware Chain |
| `meteoblue_api` | `credential` | Home Assistant core `meteoblue` weather integration — Meteoblue model API key |
| `headscale_api` | `credential` | headscale (OIDC client secret; `username` = client id) |
| `headplane_api` | `credential` | Headplane → **Headscale API key** (REQUIRED for Headplane OIDC mode). Mint ONCE on the VPS: `docker exec headscale headscale apikeys create --expiration 8760d` |
| `headplane_password` | `password` | Headplane cookie/session signing secret — exactly 32 chars (`openssl rand -hex 16`). **Password category** (c.f. `authentik_password`) — not under `api`. |
| `tailscale-sidecar_api` | `credential` | tailscale-sidecar — **Headscale preauth key** for the `vps-obs` sidecar node, scoped to `tag:sidecar` (`docker exec headscale headscale preauthkeys create --user 2 --tags tag:sidecar --reusable --expiration 8760h -o json`), consumed by the `traefik-tailnet` compose `TS_AUTHKEY`. API-Credential type (`credential` field). **Manual-value path** — headscale mints the value, so the item is NOT in the provisioner CATALOG and `provision-secrets.py --rotate` must not be used on it (it would write a value headscale never issued). Re-mint before the expiry below. · **Renewed 2026-10-18**, current value = headscale preauth key **id 9** (`tag:sidecar`, reusable, expires **2027-10-18**); the key it replaced (id 3) is **expired, not deleted** — `preauthkeys expire --id <id>` is the fleet's convention and expiry keeps the row readable in `preauthkeys list`. Why: the value reached a session transcript through a redaction that covered `KEY=value` but not the rendered-compose form `KEY: "value"` — the leak class the *Creation & Rotation Workflow* item 7 names. ⚠ **How far a rotation of this item is exercisable:** the compose sets `TS_AUTH_ONCE: "true"`, so containerboot authenticates only when the node is NOT already logged in. A re-render + restart therefore proves the new value reached the container env (the 12-char `sha256` of the rendered value == the vault's == `up -d` recreated the container), it does **not** prove a re-registration, and **expiring the old key does not disconnect a running node** — a live node keeps its own state in `/srv/docker/tailscale-sidecar/data`, so `vps-obs`, its node id, its pinned edge IP and `tag:sidecar` are unchanged by either act. The new key's registration power is proven at the next genuine re-registration of a replacement `vps-obs`, not by this rotation. Write path from the runner: the seat's ambient SA token is read-scoped (proved by the `op whoami` Integration ID, not by `op vault list` — [1password.md](1password.md) §1), so the write goes through `op-write_api` in one `op item edit` (*Creation & Rotation Workflow* items 7 and 8). · [network-vpn.md](network-vpn.md) §Tailnet-exposed services · [services-traefik.md](services-traefik.md) |
| `tailscale-oldsrv_api` | `credential` | tailscale-node — **headscale preauth key** for the `oldsrv` tailnet node, scoped to `tag:dev`: `docker exec headscale headscale preauthkeys create --user 2 --tags tag:dev --reusable --expiration 8760h -o json`. Consumed by `host_vars/oldsrv.kogler.si.yml` → `roles/tailscale-node`; written to `/run` mode 0600 for the one `tailscale up` and shredded in the block's `always`, so no copy outlives the join. **Manual-value path** — headscale mints it, so it is NOT in the provisioner CATALOG and `check-vault-items.sh` does not scan host roles (same exemption as `switch`/`router`); this row IS the coverage record. ⚠ headscale 0.29.3 emits the value under JSON key **`key`**, not `secret`: a redaction filter written against `secret` LEAKS it (the field name is the trap). |
| `tailscale-pi_api` | `credential` | tailscale-node — **headscale preauth key** for the SECOND permitted home node, the Pi, scoped to its OWN tag: `docker exec headscale headscale preauthkeys create --user <id> --tags tag:home-edge --reusable --expiration 8760h -o json`. ⚠ **The tag IS the reach surface**: the ACL grants `tcp/443` by tag, so a key minted with `tag:dev` (or with no tag) gives the Pi either the dev seat's ports or nothing at all — read the assignment back with `headscale nodes list` after the join. Consumed by `host_vars/pi.kogler.si.yml` → `roles/tailscale-node` (key written to `/run` mode 0600, shredded in `always`). API-Credential type (`credential` field); **manual-value path**, so it is NOT in the provisioner CATALOG and `check-vault-items.sh` does not scan host roles — this row IS the coverage record. The Pi node carries `tag:home-edge`. The Pi converge fails loud (no `default('')` fallback) if this item is ever removed. |
| `tailscale-spark_api` | `credential` | tailscale-node — **headscale preauth key** for the THIRD permitted home node, spark, scoped to its OWN tag: `docker exec headscale headscale preauthkeys create --user <id> --tags tag:spark --reusable --expiration 8760h -o json`. ⚠ **The tag is the isolation here, not the reach surface**: spark's `tcp/443` grant is written on its node **address** in `policy.hujson.j2`, so a key minted with `tag:dev` or `tag:home-edge` would widen another box's surface instead of spark's — read the landed tag back with `headscale nodes list` after the join. Consumed by `host_vars/spark.kogler.si.yml` → `roles/tailscale-node` (key written to `/run` mode 0600, shredded in `always`). API-Credential type (`credential` field); **manual-value path**, so it is NOT in the provisioner CATALOG and `check-vault-items.sh` does not scan host roles — this row IS the coverage record. The spark node carries `tag:spark`. **The item does not exist yet**: create it with the mint above (owner-present — headscale issues the value, never this repo), then join, read the assigned address into `tailnet_spark_ip` and re-converge. Until the item exists the spark join leg fails loud on the lookup (no `default('')` fallback), and the same holds if it is ever removed. |
| ~~`tailscale_dsh_api`~~ / ~~`tailscale_pi_dev_api`~~ | ~~`credential`~~ | **Parked with the harnesses** — headscale preauth keys for the `dsh` / `pi-dev` tailscale sidecars. Both harnesses are removed and their `docker_services` rows are `enabled: false`, so nothing renders them; the values stay in the provisioner catalog + the `NOT_AUTO_ROTATABLE` guard. **State of the minted keys: expired in headscale, live-verified 2026-10-18** — ids 4 (`tag:pi-dev`) + 5 (`tag:dsh`), expired not deleted; no tailnet node carries either tag, so no registration depended on them. This doc does not revoke a key, headscale does. Do **not** seed them as a prerequisite and do not re-use those ids — a rebuild of either service needs a **fresh mint** with its own tag (§Creation & Rotation Workflow). |
| `home-assistant_api` | `api` → `credential` = LiteLLM virtual key `sk-…` | Home Assistant's own scoped LiteLLM key for the Assist LLM leg: allow-list is the single row `spark/qwen3.8-flash-next` (never a `spark/*` wildcard), `rpm: 30`, no `max_budget` — read back as length 25 and `GET /v1/models` → EXACTLY `['spark/qwen3.8-flash-next']`. Glue-minted by `lan-litellm` (`bootstrap_keys` enabled there) on oldsrv with the write-scoped op token. ⚠ **The mint glue is CREATE-ONLY** (existing vault value → probe → keep), so a live key keeps its allow-list until `/key/update` exists or it is deliberately re-minted — a grant cannot be changed by editing this record. ⚠ **Consumption path:** no template renders it; HA's stock `litellm` integration stores the value in a **config entry** — plaintext `/config/.storage/core.config_entries` on the Pi — and `roles/home_assistant/templates/ha-config-sync.sh.j2` rsyncs that directory (`--delete`, excluding only `secrets.yaml`) to the oldsrv standby, so the minted key replicates off the primary. Read §Runtime plaintext that leaves the vault before treating the value as vault-scoped. |
| ~~`dsh_api`~~ | ~~`credential`~~ | **Retired LiteLLM consumer** — DSH is not a LiteLLM consumer, so this item is neither restored nor re-minted and its credential field is empty (a parked consumer is not a deleted secret). The name stays documented: `roles/docker_services/defaults/main.yml` still maps the parked `dsh` service to it, and `scripts/gate/check_vault_docs.py` fails an IaC-referenced item this table does not document. |
| `nut_password` | `password` | NUT UPS monitor (upsmon client → master auth) |
| `nut-exporter_password` | `password` | nut_exporter → upsd read-only auth (dedicated `upsmon slave` user on the NUT master) |
| `network-snmp_api` | `credential` | router + switch — MikroTik SNMP **read-only community** for Alloy polling; `credential` = the RO community string |
| `mikrotik-logpipe_api` | `password` | router — **scoped read-only RouterOS API user `logpipe`**: remote syslog/API read for log shipping + central monitoring; `password` = the user's password. `read` group = read-only to all config paths, no write. Mgmt-VLAN only. Firmware WAN traffic uses the permanent `wan_allow` rule, not a scoped API user |
| `mikrotik-n8n_api` | `password` | router — **scoped read-only RouterOS API user `n8n`**; `password` = the user's password; Mgmt-VLAN only. The firmware-workflow automation that motivated it uses the permanent `wan_allow` rule, so the user stays provisioned for admin uses |
| `wg_password` | `password` | router (WireGuard S2S private key — router side, distinct per-side) |
| `wg_password_vps` | `password` | VPS (WireGuard S2S private key — VPS side, distinct per-side) |
| `wifi-kogler_password` | `password` | CAPsMAN SSID **Kogler** (VLAN 10 Home) — router role when `routeros_capsman_enabled` flips true; alphanumeric only, 2.4 GHz-friendly chips on this SSID family |
| `wifi-kogler-iot_password` | `password` | CAPsMAN SSID **Kogler IOT** (VLAN 20 IoT, no internet) — Gen1 Shellys live here |
| `wifi-kogler-guest_password` | `password` | CAPsMAN SSID **Kogler guest** (VLAN 30 Guest, 5GHz, client-isolated internet-only) — live |
| `wifi-kogler-iot-wan_password` | `password` | CAPsMAN SSID **Kogler IOT WAN** (VLAN 21 IoT-Internet) — the SSID is deleted and VLAN 21 does not exist; cloud-IoT WAN egress rides **Kogler IOT** (VLAN 20) on the per-device `wan_allow` flag. The item stays in 1Password, referenced by no config; do **not** re-mint it |
| `wifi-kogler-kids_password` | `password` | CAPsMAN SSID **Kogler Kids** (VLAN 40 Kids) — the SSID is deleted; the kids' devices join **Kogler** (VLAN 10) and their control is the router's per-MAC DNS/WAN rules. The item stays in 1Password, referenced by no config; do **not** re-mint it |
| `tube-archivist_login` | `credential` | Tube Archivist **web-UI login** (username in `username`; the archive UI's password) — separate from `tube-archivist_api` (used by the Jellyfin plugin) and `tube-archivist_ui`. OVERWRITE the catalog-generated placeholder with the password the Tube Archivist first-run wizard sets (http://10.10.1.30:8000) after deployment. |
| `tube-archivist_ui` | `credential` | Tube Archivist **UI/API token** — used by the TubeArchivist plugin in Jellyfin (`/api/token/`); optional at deploy (only if the Jellyfin plugin is used) |
| `tube-archivist_api` | `credential` | Tube Archivist **API key** for the Jellyfin plugin — OPTIONAL (Jellyfin plugin later; NOT required by the compose — docs-only for now) |
| `tube-archivist-es` | `username`=`elastic` + `password` | **Elasticsearch `elastic` bootstrap password** (`ELASTIC_PASSWORD` on BOTH the archivist-es container and the app) — catalog-generated; the TA bootstrap env-check requires it. Applies only while `tube-archivist` is `enabled: true`; the service is disabled, so it is not a live oldsrv prerequisite today. |
| `lidarr-url-dl_login` | `username`+`credential` | **Lidarr-YouTube-Downloader** web-UI login — entered in its Settings page at first run (no env-var auth upstream); reference-only, not fetched by compose |
| `lastfm_login` | `username`+`credential` | **Last.fm** account for Aurral's discovery history (user + API key / password) |
| `metabrainz_login` | `username`+`credential` | **ListenBrainz** (Metabrainz) account for Aurral's discovery history |
| `slskd_login` | `username`+`credential` | **Soulseek** account (username/password) for slskd — the Soulseek **network** login, rendered as `SLSKD_SLSK_USERNAME`/`SLSKD_SLSK_PASSWORD` (slskd binds `SLSKD_` only; `slskd --envars` is the list — a wrong env name reaches nothing and fails silently). **Not rotatable from any seat**: the only change path is Soulseek's own account reset, its confirmation e-mail does not arrive here, so the value stands and the exposure stays a ledger debt ([services-rejected.md](services-rejected.md)). Soulseek recycles usernames after 30 days without a successful login, so slskd must stay connected — prove the login with `slskd --envars`, never by grepping a rendered compose. |
| `soulseek_api` | `credential` | **slskd web-UI password** — rendered as `SLSKD_PASSWORD` (`SLSKD_USERNAME` is the literal `slskd`). It is NOT a "token": slskd 0.26 removed the token option, so setting `SLSKD_TOKEN` is ignored and the daemon answers on the **stock `slskd`/`slskd`** login — verify with `POST /api/v0/session` (200 for this value, 401 for the stock pair). catalog-generated value, rotatable: it reaches the service only via an IaC re-render (CONVENTIONS §2). |
| `soulseek-internal_api` | `credential` | **slskd HTTP API key** — rendered as `SLSKD_API_KEY` on the slskd compose and as `[Slskd] api_key` in soularr's rendered `config.ini`. This is the ONE value that arms the Soulseek bridge: slskd answers `x-api-key` only for a configured key, and with none set every x-api-key request — including the one soularr sends — answers 401 (measured against `/api/v0/options`, 2026-10-19). **Separate from `soulseek_api` on purpose**: that item is the human web-UI login (JWT via `POST /api/v0/session`) and stays untouched by this leg; the bridge credential is minted, never typed. catalog-generated (`provision-secrets.py` CATALOG, `gen_token`) — the alphabet excludes every character either consumer parser means something by, because the value lands in a compose env AND an INI that configparser reads with ExtendedInterpolation. Rotation propagates by re-render (both templates read the item), so `--rotate` + converge is the contract; the converge RECREATES the slskd container and drops the Soulseek session, so rotate in a named window. Minted 2026-10-19 from the runner via the write-scoped one-shot `op item create` route under `op-write_api` (item id `7aqyivm64hdyuymnybdg7n43y4`, `credential` length 32). **Rotated 2026-10-19 (same day, lane X on HD-1091) TWICE, both for leaks, both by `provision-secrets.py --rotate soulseek-internal_api --yes` under `op-write_api`** — (1) `f7fb80989e1a` → `e4cca3f24f09`, because the rendered form was recoverable from a run-capture log on the driving seat; (2) `e4cca3f24f09` → `f815f24b7ce0`, because a debug read of soularr's `/data/config.ini` printed both bridge keys into a second transcript. Still length 32, `credential` still exactly one field, and the *second* write used the catalog route rather than the stdin round-trip in *Creation & Rotation Workflow* item 7 because `--rotate` is the contract for a CATALOG item (the manual `item edit` path is for hand-seeded values). Both rotations proved the same three ways: new key → 200 on `/api/v0/options`, superseded key → 401 with slskd's own `Unknown API key beginning with: <4 chars>` line, `POST /api/v0/session` with `soulseek_api` → 200 + token; and by hashing BOTH ends (`SLSKD_API_KEY` env and `[Slskd] api_key`) to the same new prefix, with soularr RESTARTED (it parses the ini once). ⛔ The superseded value must be kept in a `0600` file to PROVE the 401 half — an empty or wrong-length key also answers 401 — and deleted the moment the probe is done. · [services-media.md](services-media.md) §Music Pillar |
| `mikrotik-admin_login` | `password` | router + switch + APs — MikroTik RouterOS admin (items RB4011/CRS328/hAP; **shared across all network gear — accepted**. One admin password across all gear is an **accepted risk**: every RouterOS management surface binds to the Management VLAN (99) only — router `api`/`www-ssl`/`ssh` (8728/443/22) are `interface=vlan99-mgmt`; switch + APs are L2-only with no WAN egress — so the shared credential never crosses the internet boundary ([network-ops.md](network-ops.md)). Revisit per-gear items only if a gear gains WAN-exposed management or the Mgmt-VLAN INPUT ACL changes. |
| `pppoe_login` | `password` (`username` = PPPoE user) | router — ISP (Telekom) PPPoE credentials for the egress WAN |
| `cloudflare_api` | `credential` | ACME **DNS-01** wildcard `*.kogler.si` cert. Token IP filter: use **EXACT addresses only** — CIDR rows (/22, /64) proved unreliable on API-token filters (Wave-3 R5); VPS set = `159.195.111.66` + `2a0a:4cc0:60:fcc:d820:9dff:fe4f:95f5` (stable SLAAC), runner = home v4/v6 |
| `op_api` | `credential` | 1Password **Service Account token, read scope** — the credential every Debian control node and seat installs at `~/.config/op/homelab-sa-token` (0600) for `community.general.onepassword` lookups and the `op` CLI, and the same value handed to **Forgejo Actions** as a secret (deploy button). `Homelab-ansible` is the **only** vault and this item is the **only** lookup credential (`op vault list` returns one vault); it also reaches the GitHub auth key, which lives in this vault. ⚠ **Enumerate consumers by value hash, not by this table's rows**, and prove scope with the `op whoami` **Integration ID** — `op vault list` cannot tell a read SA from a read+write SA, and a seat seeded with a different item stays green through a rotation of this one. The Forgejo `vault-gate` secret has no holder (no runner, no `.forgejo/` workflow) and the only workflow in the tree carries no OP secret. |
| `signal_api` | `credential` (`username` = phone number) | signal-cli-rest-api (linked-device pair / captcha) |
| `signal-internal_api` | `credential` | signal-cli-rest-api — API token auth (`SIGNAL_CLI_API_TOKEN`; requests require `X-Api-Key` header) so no container on services-internal can send Signal as Domen's number without it. n8n sends this in its webhook call |
| `kopia-server-internal_api` | `username` + `credential` | kopia-server auth — `username` = the server-admin `user@host` identity (htpasswd + UI), `credential` = password; the per-client `oldsrv-agent@oldsrv.kogler.si` entry (`kopia_agent_user`, group_vars) shares the same credential. Written to the in-container `server.htpasswd` (plaintext, 0600); the repo-user password is the **repo master password** (`kopia_password`), not this credential (kopia quirk). Replaces the old `--without-password` |
| `victoria-metrics_api` | `username` + `password` | **VictoriaMetrics basic auth** — `username` + `password` only (Victoria's `-httpAuth.username` / `-httpAuth.password` are plaintext basic-auth, NOT bcrypt). Consumed by Grafana (VM datasource, uid `prometheus`) + Alloy remote_write + the oldsrv `mcp-victoriametrics` MCP server over the tailnet. Catalog-generated (`scripts/secrets/provision-secrets.py`), rotatable; seed BEFORE the Victoria converge (`provision-vault.sh`). |
| `victoria-logs_api` | `username` + `password` | **VictoriaLogs basic auth** — `username` + `password` only (VictoriaLogs `-httpAuth.username` / `-httpAuth.password` plaintext). Consumed by Grafana (VictoriaLogs datasource, uid `loki`) + Alloy log push + the oldsrv `mcp-victorialogs` MCP server over the tailnet. Catalog-generated, rotatable; seed BEFORE the Victoria converge. |
| `technitium_login` | `password` (`username` = the admin user) | **Technitium DNS admin credential — consumed by the `technitium-seed` role on ALL THREE instances** (VPS primary / oldsrv secondary / Pi tertiary). **Human-gated by construction:** the app seeds `admin`/`admin` on a fresh volume (deleting `auth.config`/`cache.bin` does NOT reset it), so the operator must set the admin to THIS value through the documented `POST /api/user/changePassword` API **before** the first seed run, or the seed's login fails and no split-horizon record is ever created. NOT catalog-generatable and NOT auto-rotatable: one value must match three instances, and rotation = re-apply on each. The seed task reads it at `roles/docker_services/tasks/technitium-seed.yml`. Runbook: [deployment-manual.md](../deployment-manual.md) §DNS admin bootstrap · spec: [network-dns.md](network-dns.md) |
| `technitium_api` | `credential` | Technitium — **declared prerequisite only.** It is listed in `_service_vault_items.technitium` (so `check-vault-items.sh` demands it), but **no task looks it up**: the seed role authenticates with `technitium_login` (username+password) and nothing reads an API key. Either wire it (if Technitium ever gets a token-auth path) or drop the entry from `_service_vault_items` — until then it is a required-but-unused item, same class as the `op_api` runner question in [deployment-ai-stack-secrets.md](deployment-ai-stack-secrets.md) §4a. |
| `crowdsec-webui_lapi_api` | `credential` | CrowdSec Web UI LAPI **watcher machine** password — `docker exec crowdsec cscli machines add crowdsec-web-ui --password '<credential>' -f /dev/null` (deploy-gated owner step). Separate from the `crowdsec-bouncer_api` bouncer key. url-safe token, rotatable (not externally-coupled). |
| `immich-ml-internal_api` | `credential` | **ML API-key auth** — shared secret between `immich-app` (sends as ML-auth header) and `immich-ml` (validates it). Fail-loud. Exact Immich v3 env var names deploy-verified. |
| `openclaw-opencloud_api` | `username` + `credential` | **OpenClaw → OpenCloud WebDAV** — `username` = OpenCloud service user, `credential` = app-specific password; consumed by `openclaw onboard` / `openclaw.json` WebDAV block. Scoped, rotatable, fail-loud. |
| `sonarr_api` | `credential` | Sonarr API key — recyclarr authenticates to this instance with it: a catalog-created placeholder at Phase-3 seed, OVERWRITE with the instance's real `config.xml` ApiKey after first boot (manual-value class), then re-run recyclarr. ⚠ The rendered config must actually be MOUNTED and read at the instance's uid — an unmounted or unreadable config syncs nothing while every lookup stays green. The service runs; the `quality_definition:` policy ships nothing by ruling (see the `radarr_api` row). **NOT auto-rotatable** (externally-coupled to the running instance). |
| `radarr_api` | `credential` | Radarr API key — recyclarr authenticates to this instance with it (`config.xml` `ApiKey`, manual-value class, NOT auto-rotatable). ⚠ **The service is enabled and runs; the quality-profile POLICY ships nothing** — the `quality_definition:` block stays commented in the template, by ruling, because enabling it rewrites the live profiles. That is a settled state, not a pending pick: a later yes is a new decision, never drift. If that decision is ever taken, the accepted values are read from the image and not from memory — `recyclarr list qualities radarr` → `movie` \| `sqp-uhd` \| `sqp-streaming` \| `anime`; `sonarr` → `series` \| `anime`. |
| `lidarr_api` | `credential` | Lidarr API key — consumer-side copy of the instance's own `config.xml` `ApiKey`, used by `templates/docker_services/lidarr-ydl/docker-compose.yml.j2` (`LIDARR_API_KEY`) and by the Aurral→Lidarr leg. Manual-value class: a catalog-created placeholder must be OVERWRITTEN with the instance's real key after first boot, then recyclarr re-run — verify with `X-Api-Key` → `/api/v1/system/status` = 200. ⚠ Two traps: read the instance key as Lidarr's **PUID** (root-in-container cannot read `config.xml`, so a failed read looks like a missing key), and `scripts/gate/check-vault-items.sh` is **not** a completeness proof for `vault['X']` refs in compose templates. NOT auto-rotatable (externally-coupled) |
| `qbittorrent_api` | `credential` | **qBittorrent's own WebUI login** — this password plus the username `admin` (`qbit_webui_username`, role defaults; not a secret). The REVERSE of the three rows above: those are consumer-side copies of a key an app issued, this one is the SOURCE. `tasks/qbittorrent-seed.yml` writes it INTO `qBittorrent.conf` as `WebUI\Password_PBKDF2` (PBKDF2-HMAC-SHA512, 100000 iterations, `@ByteArray(base64(salt):base64(dk))` — the format qBittorrent 5.2.x itself writes), because the LSIO image translates no credential env at all and regenerates a random 9-char password at every start while the stored hash is empty: without this item the arrs hold a credential that dies on the next `docker compose up`. Consumers: the three arr torrent download clients (`tasks/arr-client-torrent.yml`, pointed at `gluetun:8080`) and the browser edge. Catalog-generated and **auto-rotatable** — a `docker_services` converge rewrites the conf AND all three client configs (`qbittorrent_seed` + `arr_client_seed`), so propagation exists; between the vault write and that converge the arrs 401 against qBittorrent (nothing downloads, nothing else breaks). Absent item = the seed fails closed rather than seeding an empty credential. |
| `jellyfin-seer_api` | `credential` | **Jellyfin API key minted FOR Seerr** — pasted into Seerr's media-server setup; it lives in Seerr's own `settings.json`. **DOCS-ONLY: no IaC consumer**, same class as `lidarr-url-dl_login`. NOT auto-rotatable (externally-coupled: rotate = re-enter in the Seerr UI, and Seerr's Jellyfin logins break silently until it is saved again). · [services-media.md](services-media.md) |
| `jellyfin-seerng_api` | `credential` | The same role for **SeerrNG**; SeerrNG authenticates its users *through* Jellyfin, so this key being wrong takes the whole request portal down, not just metadata. DOCS-ONLY, NOT auto-rotatable (as above) · [services-media.md](services-media.md) |
| `bazarr_api` | `credential` | Bazarr API key — **consumer-side copy of the instance's `auth.apikey`**, app state under `/srv/docker/bazarr/config` with no IaC consumer (yet). Verify it against the live instance by sha256 rather than assuming: an instance restart rewrites `config.yaml`, not this item. NOT auto-rotatable · [services-media.md](services-media.md) §Subtitles |
| `jellyfin-bazarr_api` | `credential` | **Jellyfin API key minted FOR Bazarr** — Bazarr authenticates to `https://media.kogler.si` with it to refresh the `Movies` library after a subtitle download. Pasted into Bazarr's own settings DB; no IaC consumer until `bazarr-seed.yml` lands. DOCS-ONLY, NOT auto-rotatable (the value lives in two places that rotate independently) · [services-media.md](services-media.md) §Subtitles |
| `opensubtitles_login` | `username` + `password` | OpenSubtitles.com account for Bazarr's `opensubtitlescom` provider. ⚠ A failed login gets the provider **throttled for 12 hours** (`Throttling opensubtitlescom … 'Login failed'`); after fixing the value, `POST /api/providers?action=reset` clears the throttle without waiting it out. ⚠ Rotate it if it was ever pasted around. NOT auto-rotatable (login is instance-side) |
| `nzbgeek_api` | `credential` | NZBGeek (paid Usenet **indexer**, €0,93/mo) API credential — it is what Prowlarr's **built-in NZBGeek definition** authenticates with, and `group_vars/subscriptions.yml` references it. The failure it prevents: a *generic Newznab* definition instead of the built-in one makes every TV search return the site's recent feed ([services-downloads.md](services-downloads.md) §NZBGeek returns its *recent* feed). |
| `eweka_login` | `username` + `password` | **LOGIN category** item. Eweka.nl is the paid Usenet **provider** (subscriptions.yml, €2,50/mo). Consumed by hand, not by IaC: it is what goes into **SABnzbd → Config → Servers**, live as `name=news.eweka.nl` / `host=news.eweka.nl` / `port=563` / `ssl=1` / `connections=16` / `enable=1`. Those credentials **authenticate**: the running SABnzbd fetches through this server and completes jobs, so the vault item and the live Server entry hold the same login — the proof is the working provider connection, not a byte comparison (SAB stores the server password in a form that cannot be diffed against the vault). Nothing in IaC stores the Server entry itself, so this item is the only durable copy of it. ⚠ A **LOGIN** item's secret field is `password`, not `credential` — a template that wrote `vault['eweka_login'].credential` would render empty. A provider is not an indexer: it never belongs in Prowlarr. Procedure: [deployment-manual.md](../deployment-manual.md) §P3.6. |
| `pihole_password` | `password` | Pi-hole admin UI — Pi-hole is not deployed (blocking runs on Technitium Advanced Blocking); the item stays provisioned for re-enable |
| `matrix_api` | `credential` (`username` = client_id) | Tuwunel Matrix — Authentik OIDC client (`client_id` = username, `client_secret` = credential); callback URI registered in Authentik provider |
| `matrix_password` | `password` | Tuwunel Matrix — the `registration_shared_secret` that `templates/docker_services/matrix/tuwunel.toml.j2` renders, which is what keeps the Synapse-style `/_synapse/admin/v1/register` door open for out-of-band account creation (keep a copy with the server identity/backups). **Rotation is a re-render, not an edit**: change the item, then converge that service alone (`ansible-run.sh playbooks/vps.yml --tags docker_services -e docker_services_scope=matrix`) — the render-restart guard restarts that one stack, because Tuwunel reads the bind-mounted `tuwunel.toml` only at start ([deployment-compose.md](deployment-compose.md) §Extra Config Templates). Hand-editing `/opt/matrix/tuwunel.toml` desynchronises it from the vault until the next render. Rotating invalidates the registration DOOR and nothing already minted through it — accounts and access tokens live in the homeserver's own store, so a bot token created by registration keeps authenticating; prove the alert leg with `GET /_matrix/client/v3/account/whoami` → 200 **and** one message read back from the alert room, never with a webhook's 200. `provision-secrets.py` refuses to rotate it in place (externally coupled), so rotation is a deliberate act. Compare a deployed copy with the vault by 12-char `sha256` prefix, never by reading the value · [1password.md](1password.md) §Output hygiene · [services-matrix.md](services-matrix.md) §Alert room |
| `matrix-alerts_api` | `credential` (`username` = the bot's MXID) | Tuwunel Matrix — the **`@homelab-alerts:kogler.si` alert bot's access token**, consumed by `templates/docker_services/n8n/docker-compose.yml.j2` (`MATRIX_TOKEN`) so the `homelab-alerts` workflow can post to `#homelab-alerts` (HD-1108, [services-matrix.md](services-matrix.md) §Alert room). Minted once by shared-secret registration, so the item is **NOT auto-rotatable**: rotating means re-registering the bot (or minting a token through the admin API) and re-rendering n8n. `username` carries the MXID so the sender identity is discoverable from the vault item, and `password` holds the bot's registration password (random, never used for login) purely so the account stays recoverable. ⛔ The room id is NOT a secret and lives in `group_vars/vps.yml` |
| `n8n_password` | `password` | n8n — `N8N_ENCRYPTION_KEY` (workflow encryption; long-lived, immutable — rotating means re-encrypting stored credentials). NOT used for webhook auth (see `n8n-webhook_api`) |
| `n8n-webhook_api` | `credential` | n8n — webhook/API auth token (`N8N_BASIC_AUTH_PASSWORD`; Grafana webhook contact point `basicAuthPassword`) — independently rotatable short-lived token so the encryption key is never exposed in webhook auth. HTTP basic auth user = `grafana` |
| `n8n_api` | `credential` | **n8n — public REST API key** (Settings → n8n API; JWT `X-N8N-API-KEY`). Used to provision/activate the `homelab-alerts` alert-router workflow (`POST /api/v1/workflows` + `/activate`) instead of a manual UI import — the workflow JSON is versioned in `roles/monitoring/files/n8n/`. **Rotatable** — regenerate in the n8n UI + update this item. |
| `openrouter_api` | `credential` | **AI stack** — LiteLLM: all external LLM generation (OpenRouter). Single key reused across every LLM consumer (Open WebUI, OpenClaw); only LiteLLM sees it. **Second consumer:** the pi harness's own `~/.pi/agent/auth.json`, rendered by `scripts/harness/render-pi-config.py`. A rotation therefore reaches THREE places, none of them by the vault write alone: `litellm` (VPS) and `lan-litellm` (oldsrv) carry it as the rendered `OPENROUTER_API_KEY` env value, so a gateway not yet converged keeps sending the retired key while every direct leg stays green, and every harness client owes a render. ⚠ Duplicate-title hazard: two items with this title in one vault make every title-based lookup pick one of them — see §Item titles are load-bearing below. |
| `entrim_api` | `credential` | **AI stack — client-side** — Entrim (hosted, cost-bearing) bearer for the pi harness's `providers.entrim.apiKey` — the one client-side key that never existed outside the vault. **Recyclable** — replace in Entrim's console, update this item, re-render each client. |
| `opencode-go_api` | `credential` | **AI stack — client-side** — opencode-go provider key for the pi harness's `~/.pi/agent/auth.json` (vendor `pi-auth`). **Recyclable** at the provider, then re-render. |
| `spark-llm_api` | `credential` | **AI stack** — spark's engine bearer key: vLLM/SGLang `--api-key` on the `llm.kogler.si` OpenAI-API. The spark name edge + both LiteLLMs' spark model entry authenticate with it. **The spark node's only vault item** (it was vault-free by design); catalog-created (`provision-secrets.py`). **Guard-listed** — the accepted-key list lives in the engine's argv, so a vault-only rotation silently diverges until spark re-converges. |
| `litellm-engine_api` | `credential` | **AI stack** — the LiteLLM gateways' OWN credential for the engine leg, minted so `spark-llm_api` stops being triple-used. vLLM accepts multiple `--api-key` values (`nargs='+'`), so spark's compose renders both (harness key first — the oom-watchdog parses that position); the gateways adopt it as `OPENAI_API_KEY` only after spark has rebooted, per the ordering in [services-ai.md](services-ai.md) §4. Catalog-created; **not auto-rotatable** (needs a spark restart + both gateway re-renders). ⚠ SGLang takes ONE key (`api_key: Optional[str]`), so this shape does not survive a fast-sglang profile. |
| `spark_login` | `password` (`username` = `admin`) | **DGX Spark (GB10) first-boot admin account** — the password chosen in the NVIDIA/DGX OS setup wizard on first power-on (a human at the display + keyboard). **Not consumed by Ansible** (the automation identity is `ansible-admin` via `ansible-admin_ssh`), so per the two-vault model it lives in the **Homelab (human)** vault as a console/break-glass credential for a re-provision or KVM recovery. Set during [deployment-manual.md](../deployment-manual.md) §spark first-boot. |
| `litellm_api` | `credential` | **AI stack** — LiteLLM master key that Open WebUI + OpenClaw use to authenticate (they never hold upstream keys). |
| `openwebui_secret` | `password` | **AI stack** — Open WebUI session/encryption secret (optional). |
| `openwebui_api` | `credential` (`username` = client_id) | **AI stack** — Open WebUI **Authentik OIDC client** (`client_id` = username, `client_secret` = credential); redirect URI `https://ai.kogler.si/oauth2/callback` registered in the Authentik provider |
| `qdrant_db` | `credential` (API key; no username) | **AI stack** — Qdrant hybrid vector store. Rebuildable cache (docs/services-ai.md §5b); single static API key served via `QDRANT__SERVICE__API_KEY`. No db-backup DBxx block (not Postgres). |
| `pi-harness_forgejo_api` | `credential` | **AI stack / dual harness** — pi.dev Forgejo service-account **PR-only** token (propose-via-PR, NO merge, no FS access). Issued by the Forgejo UI; NOT_AUTO_ROTATABLE. |
| `dsh_forgejo_api` | `credential` | **AI stack / dual harness** — DSH Forgejo service-account **PR-only** token (propose-via-PR, NO merge, no FS access). Issued by the Forgejo UI; NOT_AUTO_ROTATABLE. |
| `openclaw_gateway_token` | `password` | **AI stack** — OpenClaw gateway/Control-UI auth token; generated by `openclaw onboard`, stored here fail-closed |
| `openwebui_api` *(see runbook)* | — | AI-stack OIDC wiring + full item-creation checklist: [`deployment-ai-stack-secrets.md`](deployment-ai-stack-secrets.md) |

> Entity naming: each item is a single `<service>_<type>` name with one `_` delimiter. The countable
> catalog (auto-generated + human-gated items) lives in [`../../scripts/secrets/provision-secrets.py`](../scripts/secrets/provision-secrets.py)
> (`--list`) — counts are derived, never hand-entered (CONVENTIONS §2).
> Future / not-yet-created: `n8n-smtp_login` (SMTP relay — provider not chosen yet, see deployment.md), `ha_mqtt` / `ha-mqtt_login` (if MQTT added to HA), `proxmox_root` / `proxmox_login` (Phase 2).

### Catalog-vs-vault completeness read (HD-442, 2026-10-19, seat service account, read-only)

The row's (a) leg said the read could not run because "`op` is not authenticated on the laptop". **It is now** —
the seat carries an `OP_SERVICE_ACCOUNT_TOKEN` and `op whoami` answers `User Type: SERVICE_ACCOUNT` against
`my.1password.eu`, so the read ran. **No value and no fingerprint of a live secret was printed by any command
below; counts, titles, item ids and field lengths only. Nothing was revoked, edited or rotated.**

| Read | Result |
|---|---|
| `provision-secrets.py` `CATALOG` entries | **54** names, all unique. The row's "catalog's 75 vault ids" is stale prose — the catalog is 54, not 75 |
| `op item list --vault Homelab-ansible` | **140** items |
| catalog − vault | **0** — every catalog name resolves in the vault, and `op item get <title>` returned rc 0 for all 54 (no `More than one item matches`, so no duplicate-title outage either) |
| vault − catalog | **86** items — the expected classes: SSH-key items, provider logins, OIDC items the egress glue seeds, hand-minted `*_api` bearers. A delta by class, not a leak; `check-vault-items.sh` measures the other direction (required-vs-present) and stays informational |
| field shape of the 54 | **4 items carry an empty `credential` field beside a populated 32-char `password`**: `openclaw_gateway_token`, `victoria-metrics_api`, `victoria-logs_api`, `tube-archivist-es`. **Not a defect** — every consumer reads `field='username'`/`field='password'` (e.g. `roles/monitoring/tasks/main.yml` renders the Grafana datasource with `field='username'`), and [1password.md](1password.md) already states that the Victoria pair rotates `username`+`password` in lockstep. The empty field is a vestigial API-key slot on an item that is not an API-key item. The trap it *would* become is a lookup with `field='api'`/`field='credential'` — the `cockpit-pi-web_api` row above is that bug already documented, so the shape difference is worth knowing and worth nothing more |

**Verdict on the row's (b) leg: no disagreement was found, so nothing is revoked.** Both token-dependent oldsrv
paths were accounted for on 2026-10-05; this pass adds only the correction that the completeness half was never
owner-gated — it was a command that had not been run.

Reproduce it in one pass (needs `OP_SERVICE_ACCOUNT_TOKEN` in the environment; prints counts, titles and field
lengths, never values):

```bash
python3 - <<'PYEOF'
import importlib.util, json, subprocess
spec = importlib.util.spec_from_file_location("p", "scripts/secrets/provision-secrets.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
cat = [n for (_c, n, _f) in m.CATALOG]
vault = {i["title"]: i["id"] for i in json.loads(subprocess.run(
    ["op", "item", "list", "--vault", "Homelab-ansible", "--format", "json"],
    capture_output=True, text=True).stdout)}
print("catalog", len(cat), "vault", len(vault))
print("missing from vault:", [n for n in cat if n not in vault])
for n in cat:                                  # item get, not list: list is not a substitute
    r = subprocess.run(["op", "item", "get", n, "--vault", "Homelab-ansible",
                        "--format", "json"], capture_output=True, text=True)
    if r.returncode:
        print("GET-FAIL", n, r.stderr.strip()[:80]); continue
    d = json.loads(r.stdout)
    empty = [f["label"] for f in d["fields"]
             if f["label"] in ("password", "credential", "api", "token") and not f.get("value")]
    if empty: print("EMPTY FIELD", n, empty)    # labels only, never values
PYEOF
```

### Item titles are load-bearing — they are the primary key

1Password resolves items **by title** for every consumer here (`op read op://vault/item/field`,
`op item edit "$item"`), so a title is a foreign key even though nothing enforces it. Two failure modes:

* **Duplicates.** Two items with one title in one vault (different ids) make every title-based lookup resolve
  to *one* of them, so a rotation can write the copy nobody reads — a secret that exists twice is a secret that
  rotates once and then lies about it. **De-duplicate by id, not by title** (`op item delete <id>`), and confirm
  the survivor against the consuming instance's own `config.xml` afterwards.
  * **With `op` 2.39 a duplicate title fails LOUD, not silently**: `op item get <title> --vault <vault>` — the
    exact command `scripts/secrets/op-vault-export.py` runs per item — answers `More than one item matches`, so the whole
    bulk vault pre-pass of a converge dies at that task. The failure presents as a vault outage, not as a duplicate.
  * **Hash before you act:** hash both sides and print lengths only, before acting on any claim about a secret —
    including a claim written by this repo's own docs.
* **Dirty titles.** A name that fails `op item edit` and falls through to `op item create` **mints a second item
  beside the real one** and reports success. The create is invisible to "write-only-if-changed" logic, so the sync
  rots quietly. Any script that builds item names from a list must validate every `slug:item` against
  `^[a-z0-9][a-z0-9_-]*$` before the first `op` call and fail loud (`authentik-secret-egress.sh`,
  `scripts/secrets/provision-secrets.py`).

**Read-only sweep** (prints counts, never values):

```bash
op item list --format json | python3 -c "import json,sys,re,collections; c=collections.Counter(i['title'] for i in json.load(sys.stdin)); print('dups :', {k:v for k,v in c.items() if v>1} or 'none'); print('dirty:', [k for k in c if not re.fullmatch(r'[a-z0-9][a-z0-9_-]*', k)] or 'none')"
```

`dups: none` is the expected result. `dirty:` reports `admin @dns.kogler.si` and `Hertzner-SB-Data` — **both
known-legit human-named items**, not glue output. The pattern is deliberately stricter than reality because the
titles that matter are machine-written; those two are the accepted exceptions, so leave them and watch for
anything *new*.

**What verifying a glue fix looks like.** The deployed copy on the VPS is byte-identical to the template
(`bash -n` clean), the sweep above returns exactly one clean copy of each `*_oidc` title, and a full
`docker_services` converge runs the glue and mints **nothing**. The signature that separates "written and
rotating" from "a duplicate sitting beside the real item": `updated_at == created_at` means the item was
**never** written — which is what a permanently-failing `op item edit` with a successful `op item create`
fall-through looks like from the outside.

**Retiring a service out of Authentik — the rule is: delete the live objects, keep the IaC disabled.** The
objects come out of the RUNNING Authentik while the repo keeps its (disabled) declaration, so the revival path
survives. Four standing rules make that safe:

- **Disable it in the registry first; comment a blueprint block out only where the disable flag cannot reach
  it.** `enabled: false` keeps both the IaC and the revival path. Commenting is the fallback, not the
  mechanism, because an edit that leaves a dangling `!KeyOf` behind fails the **whole** blueprint
  (`blueprints/*.yml` are `copy:`d unrendered) — an **IdP** outage rather than one service's. The same care
  applies to `outpost_embedded`: one shared object, so retire a service's entries, never the object.
- **A blueprint apply is an UPSERT: removing an entry does NOT delete the server-side object.** Deletion is a
  separate, explicit pass through the Authentik API / `ak shell` — AI work, not a human hunt-and-peck — run
  with an exact-name allowlist plus two asserts: the expected set is present, and no OTHER application rides
  those providers.
- ⚠ **Blueprint ids are not object names.** A provider can be `provider_edge_sec*` / `edge-sec-ts` in the
  blueprint but live in the DB as `forward-sec` and `forward-sec-ts`, so searching for the blueprint id returns
  nothing and invites a second, unnecessary deletion pass. Query the DB for `name`/`slug`, not for the blueprint id.
- **Acceptance is a read, not a claim:** re-render the scoped blueprint set (the retiring comments replacing
  the object blocks prove the render), apply `playbooks/authentik-blueprints.yml` to `changed=0 failed=0`,
  then take the same read again and confirm **nothing re-minted**. The one real `authentik Embedded Outpost`
  — shared by every Forward-Auth route in the fleet — stays untouched by any such pass.

A retired service's egress entry is
`{% raw %}{% if _enabled.get('<service>', false) %}{% endraw %}`-gated, so it renders nothing while
`enabled: false` — the gate, not the name-shape guard, is what makes it inert.

⚠ **A Cloudflare record is an owner step from anywhere but home:** the `cloudflare_api` token is IP-filtered
to the home WAN, so no away session can delete a public record.

A hard-coded provider list, not the fleet, decides what gets synced — an entry that outlives its service is a
glue that writes beside the fleet instead of into it.

---

## Rename Map (legacy → canonical)

| Legacy (before) | Canonical (now) |
|-----------------|-----------------|
| `admin_laptop_ssh_pubkey` | `domen_ssh` |
| `ssh_ansible_pubkey` | `ansible-admin_ssh` |
| `ssh_ai_pubkey` | `ai_ssh` |
| `kopia_master_password` | `kopia_password` |
| `authentik_pg_password` | `authentik_db` |
| `authentik_secret_key` | `authentik_password` |
| `smbpasswd -a -s` on nas (passdb entry, not a config value) | `smb-domen_login`, `smb-shared_login` — needs `-e storage_samba_password_force=<name>` on the converge |
| `opencloud_db_password` | `opencloud_db` |
| `immich_db_password` | `immich_db` |
| `forgejo_db_password` | `forgejo_db` |
| `forgejo_token` | `forgejo_api` |
| `grafana_admin_password` | `grafana_login` |
| `grafana_smtp_password` | `smtp_login` |
| `ha_api_key` / `ha_exporter_token` / `ha_prometheus_token` / `long_lived_token` | `ha_api` |
| `ha_vrrp_password` | `ha-vrrp_password` |
| `headscale_oidc_secret` | `headscale_api` |
| `headscale_client_secret` | `headscale_api` |
| `headplane_headscale_api_key` / `headplane_api_key` | `headplane_api` |
| `headplane_cookie_secret` | `headplane_password` |
| `upsmon_password` / `nut_upsmon_password` | `nut_password` |
| `smtp_notify_creds` / `nut_notify_email` / `nut_smtp_user` / `nut_smtp_pass` | `smtp_login` |
| `snmp_ro_community` (snmp.yml.j2 auth) | `network-snmp_api` |
| `network-snmp_login` (misnamed; API Credential, `credential` field) | `network-snmp_api` |
| `wireguard_private_key` | `wg_password` |
| `router_admin_password` | `mikrotik-admin_login` |
| `router_login` | `mikrotik-admin_login` |
| `cloudflare_api_token` / `cloudflare_api_token_credential` | `cloudflare_api` |
| `op_service_account_token` | `op_api` |
| ~~`vps-op-write_api`~~ | `op-write_api` (the old title is deleted — a stale reference 403s) |

| `signal_api_*` | `signal_api` |

> `nut_smtp_server` (relay host, not a credential) is **config** — it lives in `group_vars`, not
> 1Password. `wildcard_cert_file` / `wildcard_cert_key_file` are cert filenames, not secrets.

---

## SSH Key Separation

Three independent ED25519 keys, one per purpose. Separate keys = revoke/rotate one without affecting the others, and audit which key was used.

| Key (1Password item) | Authorized user on hosts | Access level |
|----------------------|--------------------------|--------------|
| `domen_ssh` | `domen`, on **every** node | Human seat — `sudo` group, **password-required, no NOPASSWD**, credential in a `domen_login` item |
| `ansible-admin_ssh` | `ansible-admin`, on **every** node | Full (NOPASSWD sudo) — the converge key, and the only account IaC needs |
| `ai_ssh` (private maps to `openrouter_ai`) | `ai-debug`, on **every** node | Debug only — **no sudo group, no 1Password/op access**, LAN-only, no forwarding |

**This table is the decision, not an observation:** the human key is an **account** (`domen`) rather than a
second key under the automation account; the AI account is fleet-wide with no sudo; the Pi uses the same
`ansible-admin` shape as every other host. The item title `domen_ssh` and the four script references
(`check_ssh_grants.py`, `gen-custom-script.sh`, `gen-media-post-install.sh`, `get-bootstrap-keys.sh`) move in
one window — a script still reading the old item name breaks every bootstrap path mid-flight. On the Windows
seat the same change is a **file on the seat's disk**: `~/.ssh/domen_ssh.pub`, with the private halves placed
from the vault and the `IdentityFile`s repointed by the alias plane. No vault write, no unlock, no dialog — the
agent matches the key's **bytes, not an item or file name**, so a rename is a rename, not a re-issue.

⚠ **`OpenSSH_for_Windows` (9.5p2, LibreSSL) cannot parse the vault's PKCS#8 export** — the same client fact as
the transport row below, and it reproduces on the fleet keys, not just the GitHub pair. One file, both builds,
same seat: the Git-Bash build (`/usr/bin/ssh`, 10.5p1/OpenSSL) authenticates;
`C:/WINDOWS/System32/OpenSSH/ssh.exe` answers `Load key "…\.ssh/ansible-admin_ssh": invalid format` →
`Permission denied (publickey)`. Stripping CR changes nothing (not a text-mode artifact), and `openssl pkey`
reads the file as a valid Ed25519 PKCS#8 PEM, so the key is sound — only the parser differs. Re-encoding with
`ssh-keygen -p -f <key> -o` does make the System32 build load it, but it forks that seat's copy from the vault
export and from every other seat, so the answer stays **name the OpenSSL build**.
Seat-leg measurement: [network-vpn.md](network-vpn.md) §The laptop alias contract.

**Not "the same keys everywhere" — check per host with `scripts/gate/check_ssh_grants.py`.** The accounts, their
`authorized_keys` and the `AllowUsers` gate come from `IaC/ansible/group_vars/all/access.yml` and a converge
owns them, so a line that no role writes is drift, not a placement. No vault key is authorized on the HA guests.
The guests (`haos-vm-1`, `haos-mininta`) are **not swept** — their short names do not resolve from any host the
sweep can drive (`ssh ansible-admin@haos-vm-1` → "Could not resolve hostname"); that scope is accepted, which
makes it a declared limit, **not** a clean bill. Placement and verdicts live in one place: §Who is authorized
where below, machine-checked.

**AI access is safe because it is a different user.** The AI key can never log in as `ansible-admin` (which has passwordless root). The `ai-debug` authorized_keys line is injected by `post_install.sh`:

```
restrict,no-agent-forwarding,no-port-forwarding,no-X11-forwarding,from="10.10.0.0/16" ssh-ed25519 <AI_PUBKEY> openrouter_ai
```

**1Password SSH agent:** private keys never exist on disk — served on demand from the `Homelab-ansible` vault (Settings → Developer → SSH agent, socket path). Create the `.pub` reference files once in `~/.ssh/` (the agent reads them to identify items). Laptop `~/.ssh/config`:

```
Host nas nas-ansible nas-ai
  IdentityAgent <1Password SSH agent socket>

Host nas              # personal key
  User domen
  IdentityFile ~/.ssh/domen_ssh.pub
  IdentitiesOnly yes

Host nas-ansible      # dedicated Ansible key
  HostName nas
  User ansible-admin
  IdentityFile ~/.ssh/ansible-admin.pub
  IdentitiesOnly yes

Host nas-ai           # AI debugging — tell the AI: "use ssh nas-ai"
  HostName nas
  User ai-debug
  IdentityFile ~/.ssh/ai.pub
  IdentitiesOnly yes
  ForwardAgent no
  ForwardX11 no
```

After a host reinstall the host key changes — run `ssh-keygen -R nas` (or `-R oldsrv`) once on the laptop.

---

### What actually raises a 1Password prompt on the Win11 seat

Three paths ask, and the timings are the proof — a consent dialog is a 7–12 s wait for a human, a
credential the machine already holds answers in under a second. Measured on `Domen_P14s`:

| action | path | dialog |
|---|---|---|
| `git push` / `git fetch` from a new process | `core.sshCommand = C:/Windows/System32/OpenSSH/ssh.exe` → the agent's named pipe | **yes — per application/process** |
| `op item get <item>` (the client render) | the `op` CLI, which authorises the *calling* process (`bash.exe`) | **yes — one per read** (8–12 s) |
| `git commit` on the seat default (`--git-identity`: `commit.gpgsign=false`, `gpg.ssh.program` absent) | git never reaches a signer | no — 0 s, `%G?` = `N` |
| `git ls-remote` through `C:/Program Files/Git/usr/bin/ssh.exe -i ~/.ssh/github_auth -o IdentityAgent=none -o BatchMode=yes` | the bundled OpenSSH 10.5p1 | no — 1 s, authenticates |
| the gate's vault legs (`check_secret_leak.py`, `check_host_reporting.py`, `check_ssh_grants.py`, `check-vault-items.sh`) | the credential rule in [`../scripts/lib/vault-env.sh`](../scripts/lib/vault-env.sh): env → this seat's 0600 install → the Debian engine's install across the WSL door | no — 1.2 s for `op item list`, and a seat with none of those three answers is a named **SKIP**, never a dialog |
| ANY service-account read, once the account's 24 h request budget is spent | 1000 requests/24 h shared by **every** service account on the account (`op service-account ratelimit`), and a leg that addresses an item by NAME pays 3 of them where the ID form pays 1 | no — `Too many requests … Try again in  seconds` (the seconds blank: no retry-after for this class), which a leg reports as a boundary **SKIP** |

Why it is per-process: 1Password authorises a key *against a requesting process*, and a harness that
starts a fresh shell per command (an agent, a scheduled task) is a new process every time. Same
mechanism that makes `op` prompt from Git-Bash but not from a terminal that stays open; also why
VS Code's `git.autofetch` produced dialogs nobody ran (now `false` on this seat — **a suppressed
prompt is not a refusal, it is a wait**).

⚠ **The third row is why an `op` call never gets to decide this for itself.** A leg that reaches the CLI with
no credential resolved does not error on this seat — it authenticates through the desktop app and waits for a
human, so "the gate is slow" is what a missing credential looks like from the inside. The resolution lives in
one file, every vault leg calls it, and a seat where it answers nothing says so as an environment boundary
([`1password.md`](1password.md) §Reading the vault from the Win11 seat).

**What the `key / credential` row in §Config vs credential split means on this seat.** The fleet keys
(`ansible-admin_ssh`, `domen_ssh`) are "never on disk" only as told from the agent side: on the Windows seats
both are plain files, placed from the vault (see below). The same holds for the laptop's GitHub pair:
`~/.ssh/github_signing` and `~/.ssh/github_auth` exist as unencrypted PKCS#8 files on BOTH seats — the WSL
bootstrap writes them out with `op read`, and the Win11 seat carries the same two files (168 bytes each). So the
Win11 `op-ssh-sign` path guards nothing that is not already on that disk; it only decides **who has to be
asked**. It is why the unattended identity below is not a new exposure, and why this laptop's GitHub pair must
be inventoried as a disk-resident secret wherever the laptop goes.

**The same inventory covers the key with the widest blast radius on the fleet: `ansible-admin_ssh`, the
fleet-wide root-capable automation key, is disk-resident on the Windows laptop** — an unencrypted PKCS#8
private half at `C:\Users\domen\.ssh\ansible-admin_ssh`, exported headless from the vault, because Git-Bash's
`ssh` has no agent to ask (`SSH_AUTH_SOCK` unset) and the `.pub` hint therefore selects a key that does not exist
there. The ACL proof that it is **not world-readable** (`icacls C:\Users\domen\.ssh\ansible-admin_ssh`) lists
exactly three principals — `NT AUTHORITY\SYSTEM:(F)`, `BUILTIN\Administrators:(F)`, `DOMEN_P14S\domen:(F)` —
no `Everyone`, no `Authenticated Users`, no `Users`; the same reading applies to `domen_ssh`.

**Unattended git on Win11 — this is the seat DEFAULT, not an opt-in.**
[`../scripts/git/gitconfig-nightly`](../scripts/git/gitconfig-nightly) is the payload and
[`../scripts/git/git-bootstrap-win11.sh`](../scripts/git/git-bootstrap-win11.sh)` --git-identity` installs it
to `~/.gitconfig-nightly` and includes it — appended last and scoped to github remotes with
`includeIf "hasconfig:remote.*.url:*github.com*/**"` — so no git call in a github clone on this seat,
interactive, subagent, or scheduled, can raise a dialog (`--1password` is the opt-back, `--check`
prints which route the seat will take). It carries `IdentityAgent=none` + `BatchMode=yes` (fail into
the log in 15 s) and file-path signing, because a leg that runs while nobody is watching must fail
rather than wait. The traps:

* **`gpg.ssh.program` must be ABSENT, not empty.** Git cannot un-set a key from a later include, so
  the script removes it from `.gitconfig-windows` instead of overriding it; `-c gpg.ssh.program=`
  (empty) makes git try to spawn `""` → `cannot spawn : No such file or directory`.
* **Include order is the mechanism — and scope is why the form is an `includeIf`.**
  `.gitconfig-github` sets `user.signingkey` to the public-key string, so the payload must be READ
  AFTER it. It is added as `[includeIf "hasconfig:remote.*.url:*github.com*/**"] path =
  .gitconfig-nightly`, which puts that path directly below `.gitconfig-github`'s in the section that
  fires for github remotes (`git config --add` appends the value to the section whose pattern
  matches rather than writing a new one at EOF); beside `.gitconfig-windows`
  it loses and signing silently reverts to the agent route. Proven in a fabricated seat carrying
  that exact `includeIf` block: the commit came out signed (`%G?` = `G`) with no dialog. Why
  `includeIf` and not a plain `[include]`: the payload's `core.sshCommand` names `~/.ssh/github_auth`,
  and a global include would hand that key to the `git.stroka.si` / `git.kogler.si` legs as well —
  those authenticate with a credential helper, and this seat has two HTTPS stroka clones under
  `D:/source/stroka`.
* **The one edge case that scope buys: no remote, no payload.** `hasconfig:` matches against a
  remote URL, so OUTSIDE a clone — `git ls-remote <url>` or `git fetch <url>` in a bare directory —
  there is no remote to match, the payload never fires, and the transport falls back to
  `.gitconfig-windows`' `C:/Windows/System32/OpenSSH/ssh.exe`, which does resolve the 1Password named
  pipe and can prompt. Inside any github clone it cannot. `git-bootstrap-win11.sh --check` reports
  this as **`route: PARTIAL`** rather than claiming the seat default, so the fallback is visible
  instead of assumed (`--check` is always honest about the directory it is run from).
* **Commits are not signed.** `commit.gpgsign=false` on every seat — `gpgsign=false` in `[commit]` and
  `[tag]` of `~/.gitconfig-github` and `~/.gitconfig-nightly` on the Windows seat, and in the two places that
  would otherwise restore it on a rebuild: `scripts/git/git-bootstrap.sh --ssh-auth` and the repo template
  `scripts/git/gitconfig-nightly`. A `commit.gpgsign=true` whose SSH signing key is not registered on GitHub is
  not a policy but a HANG: git blocks waiting for an agent to sign with a key nothing can validate, in the
  shells nobody watches (cron, a converge, pi's bash). Key-file entries stay in place so already-signed commits
  still verify, and `allowed_signers` needs the public half to verify that history.
  ⚠ **A DEBIAN seat has neither of those files.** `~/.gitconfig-github` is the Windows seat's `includeIf` file
  and `~/.gitconfig-nightly` is installed only there by `git-bootstrap-win11.sh --git-identity`, so on oldsrv
  (and any bare Debian seat) the ONLY git config is `~/.gitconfig` — leaving it at `gpgsign = true` keeps the
  hang while every repo-side path reads green. The acceptance form is the same everywhere: a commit under a
  `github.com` remote from a bare `env -i` shell returns immediately with `%G?` = `N`.
  ✅ **Every account on a fleet host that owns a `github.com` clone carries the explicit `false` in its own
  user-scoped global file** — measured FROM each seat, 2026-10-18. On the Debian seats that file is `~/.gitconfig`
  alone (`oldsrv` seat + runner, `vps` runner, `spark` runner, whose `/opt/homelab/ultrafast-src` third-party
  `github.com` checkout is what makes that account a git seat); on the Windows and WSL seats it is the per-remote
  `~/.gitconfig-github`, fired by `includeIf "hasconfig:remote.*.url:*github.com*/**"`, and that seat's own
  `~/.gitconfig` carries no `gpgsign` line at all, so the *no remote, no payload* case above applies there too.
  An account that owns no clone owes nothing, and that is the trap in reading this state: **git's own default for
  `commit.gpgsign` is already `false`**, so an unconverged seat answers `false` to a bare
  `git config --global commit.gpgsign` without anything having converged — the verdict is `git config --global
  --show-origin --get-all commit.gpgsign` printing the value while NAMING the seat file, plus
  `git config --list --show-origin | grep -i gpgsign` inside a `github.com` clone showing `false` and nothing
  else. No fleet host carries a `gpgsign` key in `/etc/gitconfig` or in an XDG config, so a machine-wide source
  is measured absent, not assumed. A host with no `git` binary at all (`nas`) is not a git seat, and neither is an
  account that owns no clone: no cron job or systemd timer on any fleet host runs `git`, so nothing there commits
  outside an interactive shell.
  ⚠ **The seat-global half is scripted since HD-495 (2026-10-19); the clone half always was.** `git-bootstrap.sh --ssh-auth`
  writes the **clone's** config and says so. `git-bootstrap.sh --git-identity` now owns the three lines a Debian seat needs
  **outside** any clone — `commit.gpgsign=false` (explicit, never merely unset: an inherited `true` is a HANG in cron, a
  converge or pi's non-interactive bash, because the signature prompt has no tty), `gpg.format=ssh`, and
  `gpg.ssh.allowedSignersFile=$HOME/.ssh/allowed_signers` — read back with `git config --global --get` so git's own
  precedence, `includeIf` included, is the thing reported. `--git-identity --check` and `--reload` write nothing, and the mode
  never generates or pulls a signing key (that stays `--ssh-auth`, and the sign half is retired) and never installs an `ssh-add`
  recovery block. The Win11 seat's equivalent is `git-bootstrap-win11.sh --git-identity`. So a rebuilt seat is repaired by one
  command rather than remembered by hand — which was the point of the role-ownership leg. Where a seat still holds `true` the
  historical repair is still a hand edit: take the backup in the same command (`cp -p <file> ~/.gitconfig.pre-signing-$(date +%Y%m%d-%H%M%S)`, then
  `git config --file <file> commit.gpgsign false`) and read the verdict knowing that the backup legitimately
  still holds `true` — a glob-wide `grep -n gpgsign ~/.gitconfig*` returning "no `true`" is therefore NOT the
  acceptance form; `git config --list --show-origin` inside a `github.com` clone, printing `false` only, is.
  On a CRLF seat file `git config --file` rewrites the touched line with a bare LF — harmless to git, and
  `sed -i 's/gpgsign = true/gpgsign = false/'` preserves the file's byte pattern instead.
* **The repo's own `.git/config` outranks every global file** and pinned `user.signingkey` to the
  public-key string, so the file alone was not enough — `--git-identity` rewrites the local pin to the
  key path (it was `git-bootstrap.sh` that wrote the string form in the first place).
* **`core.sshCommand` must be the 8.3 short path** (`C:/PROGRA~1/Git/usr/bin/ssh.exe`): Git for Windows
  hands the string to `sh`, which drops the quoting around "Program Files" and execs `C:/Program`.

The same key-FORM finding holds on the oldsrv seat, and here it is scripted rather than hand-planted.
The manual form is [../deployment-manual.md](../deployment-manual.md) §0.4b.

#### What a Win11 seat needs for git to work, per route

Both routes were exercised on `Domen_P14s` and both authenticate; the row that matters for
an unattended seat is the last one. `scripts/git/git-bootstrap-win11.sh --check` prints which route the seat
is on without changing anything.

| requirement | modal-free seat default (`--git-identity`) | 1Password route (`--1password`) |
|---|---|---|
| transport | **Git for Windows' own ssh** — `C:/PROGRA~1/Git/usr/bin/ssh.exe` (OpenSSH 10.5p1 / OpenSSL) | **Windows OpenSSH** — `C:/Windows/System32/OpenSSH/ssh.exe` (9.5p2 / LibreSSL), because that client is what resolves `\\.\pipe\openssh-ssh-agent` |
| key material | the two **files** `~/.ssh/github_auth` + `~/.ssh/github_signing` (passphrase-free PKCS#8, vault item `GitHub auth`; commits are unsigned, and a seat may still hold the `github_signing` FILE — harmless, and `allowed_signers` needs its public half to verify the signed history) | the same keys as **1Password SSH-key items**, the desktop app running with the SSH agent toggled on, and `op-ssh-sign.exe` in `WindowsApps` |
| `user.signingkey` | the **file path** — in `~/.gitconfig-nightly` *and* in every clone's local config | the **public-key string** (`.gitconfig-github`, via `includeIf`) |
| `gpg.ssh.program` | **absent** (an empty value makes git spawn `""`) | `op-ssh-sign.exe` |
| needs a human present | never | yes — once per new process, and see the hard-failure shape below |

The transport row is not a preference. Same key file, both clients, measured:

```bash
C:/Windows/System32/OpenSSH/ssh.exe -i ~/.ssh/github_auth -o IdentityAgent=none -T git@github.com
#   Load key "C:/Users/domen/.ssh/github_auth": invalid format        ← LibreSSL cannot read these PKCS#8 files
"C:/Program Files/Git/usr/bin/ssh.exe" -i ~/.ssh/github_auth -o IdentityAgent=none -T git@github.com
#   Hi domenkogler! You've successfully authenticated…                ← OpenSSL can
```

Two things that look like leaks or breakage and are neither. `ls -l` reports the key files `0644`, which
is what MSVCRT says about every file on this platform — the real ACL (`icacls ~/.ssh/github_auth`) is
`DOMEN_P14S\domen` + SYSTEM/Administrators only, so the 168-byte passphrase-free private halves are not
world-readable. And `%G?` printing `N` next to `gpg.ssh.allowedSignersFile needs to be configured` is a
**verification** gap, never a signing one: the object carries the signature
(`git cat-file commit HEAD | grep -c gpgsig` → `1`), and `-c gpg.ssh.allowedSignersFile=~/.ssh/allowed_signers`
makes git report `G` with the key fingerprint.

**The 1Password route does not only wait — it can die.** A `git fetch` on the seat failed outright:

```
sign_and_send_pubkey: signing failed for ED25519 "GitHub auth" from agent: communication with agent failed
git@github.com: Permission denied (publickey).
```

Thirty seconds later the same command succeeded, so the cause was the desktop app locked or mid-restart,
not a config fault — but it sharpens the argument above. On that route a background git call does not
merely block on a dialog nobody can answer; when the app is not answering the pipe it fails hard, and the
modal-free route on the same box authenticated inside the same minute. Which is the failure mode an
overnight leg actually hits.

---

### Who is authorized where — the grant inventory (`scripts/gate/check_ssh_grants.py`)

The three vault keys above are **not** the whole `authorized_keys` picture: hand-made grants exist on
the boxes, nothing in IaC declares them, and the only way to know is sweeping every host. Fingerprints
only, never key material (CONVENTIONS §6):

| Fingerprint | Identity | Where authorized | Verdict |
|---|---|---|---|
| `XTmK3tR…` | `domen_ssh` | the `domen` account on **vps · oldsrv · nas · pi · spark** | vault-issued, live — fleet-wide and **not** under `ansible-admin`; spark is sanctioned as the `domen` seat |
| `1uKzmwf…` | `ansible-admin_ssh` | every managed host → `ansible-admin`; ~~pi → `admin`~~ | vault-issued, the converge key. The Pi's `admin` placement is neutralized, not deleted — see the live-state table below. ⛔ Order is the safety property: prove `ansible-admin` (then `domen`) can log in on the Pi → remove the key from `admin` → only then lock or remove the account. Never reverse it (`self-converge-guard.yml`) |
| `Ug788c…` | `ai_ssh` | nas · oldsrv → `ai-debug` | vault-issued; sanctioned on every node (`nas · oldsrv · pi · spark · vps`) with no sudo and no `op` access — live placement follows where `roles/ai_diag` runs, and the `restrict,…,from=` options stay |
| `DxoZeGK…` | `ha-sync@pi.kogler.si` | oldsrv · vps | hand-made, live (HA failover + cert pull), **no vault item** |
| `VX0TbLr…` | `traefik-cert-sync@oldsrv.kogler.si` | vps → `ansible-admin` | hand-made, live on a timer, **no vault item** |
| `7ZuAhqI…` | `traefik-cert-sync@spark.kogler.si` | vps → `ansible-admin` | hand-made, live on a timer, **no vault item** |

**This table is a machine-checked gate, not prose.** `python3 scripts/gate/check_ssh_grants.py`
sweeps every `authorized_keys` + `/root/.ssh/authorized_keys` on the managed hosts (`ssh` +
`ssh-keygen -lf`, read-only), derives the named set from THIS table plus the vault public halves
(`domen_ssh` / `ansible-admin_ssh` / `ai_ssh`), and exits 1 unless named ≡ live. It reds on
`UNKNOWN` (live key nobody named), `RETIRED-BUT-PRESENT`, `WRONG-ACCOUNT` (a named key under an
account the table does not name), `UNPLACED` (a key on a host the table does not name) and
`AMBIGUOUS` (two identities matching one key — reported, never guessed away). `--self-test` scores
fixtures offline; `--dump` keeps a capture. Run it before and after any grant change; it revokes
nothing. The sweep set is the five managed hosts (`nas`, `oldsrv`, `pi`, `spark`, `vps`) — **the HA
guests are not in it and are therefore unaudited**, which is a declared limit, not a clean bill:
unaudited ≠ clean.

**The gate scores `(key, host, account)`, not identity.** One key can carry several placements, and one of
them may be must-be-absent while the rest are must-be-present: a `~~struck~~` placement is must-be-absent at
that host and account only, and a whole key is retired only on a structural marker (`Verdict` *starting* with
`retired`, or a `Where` cell whose every placement is struck). `--self-test` pins both directions of that plus
the violation KIND, because a red that fires for the wrong reason teaches the next reader the wrong lesson.

**A grant that is not vault-issued is retired by evidence, not by age.** A hand-made key with no vault item and
no IaC reference is a standing risk on the account it authorizes — against an `ALL=(ALL) NOPASSWD:ALL` account
it is "anyone holding that host can root this data store". Prove disuse from
the authorizer's own log plus a fleet-wide **fingerprint** sweep (`ssh-keygen -lf` over every
`authorized_keys*`) showing zero live acceptances — then retire it with the sequence below. A commented-out
line is inert but is still not a deletion: enumerate by fingerprint, then read what the match actually is.

**Retiring an SSH grant — the reversible sequence.** The characteristic failure of an SSH change
is being locked out by your own fix, so the order matters and each step is evidence, not opinion:

1. **Enumerate before touching anything.** Run `ssh-keygen -lf` per `authorized_keys` file on
   every host. A file stores the base64 blob, so grepping for a *fingerprint* matches nothing; and a
   `#`-commented line is **not** a grant — enumerate by fingerprint, then read what the match is.
2. **Establish disuse from the authorizing host's log**, not from memory:
   `journalctl -u ssh -u sshd | grep <fingerprint>`, and confirm the journal actually covers the
   interval you are claiming silence for — rotation or a reboot explains absence too.
   `atime` is not evidence: a read-only `grep -r` over the home directory updates it. Disuse is also
   not what `host_vars` implies: the consumer may be the **operator's own client config**, and then
   the count that looks like idleness is the human at the keyboard.
   ⚠ **Two ways this reading lies, both measured on the Pi (HD-443, 2026-10-19).** (a) The Pi runs
   `Storage=volatile`, so its journal reaches back exactly one boot — the window it happened to cover
   started 2026-10-04 23:00 and CONTAINED nine `admin` acceptances, so the row's 14-day and 30-day claims
   are not windows on this host at all: they are the same seven days of RAM read twice. A volatile host
   cannot prove a 30-day silence; say so rather than reporting zero. **On a host whose journal cannot cover
   the interval, the disuse test is replaced — by ruling, not by shortcut — with the neutralized state plus
   the fingerprint match:** the key absent from `authorized_keys`, and the dated `.disabled-*` copy holding
   exactly the fingerprint the logged acceptances carry. Where that holds, the delete is authorized; hunting
   a different host to log on is not required and buys nothing. (b) **A raw journal grep matches the
   probe that greps for it** — an ansible `command` task carrying the literal string in its `_raw_params`
   lands in the journal and was counted as an acceptance (it read 1-in-7-days for a fingerprint with no
   logins at all). Filter on the authorizing unit (`sshd-session[…]: Accepted publickey for <user>`, or
   `_EXE=` / `-u ssh.service`), never on the bare phrase.
3. **Back up, then neutralize without deleting** — comment the line out with a dated marker.
   One line, instantly revertible.
4. **Prove inert with something you actually depend on:** a fresh `ssh` as that account plus one
   `--check` converge leg against that host. `failed=0` is the proof; "it looked unused" is not.
5. **Delete on a test of the grant itself** — never on the colour of an adjacent timer, and never a key
   whose grant has not been enumerated. Then delete both halves: the private key on the holder, the line
   on the authorizer.
6. **Do not adopt a discovered key into the vault as the first move.** That promotes an unknown,
   often one-time key to a managed secret and makes it permanent. Retire it, and mint a named key
   only when a real job needs one.

**The rule this section carries forward:** a grant that is neither vault-issued nor named in
the table above does not exist as far as this repo is concerned — and that is precisely why a
grant has to be named here or removed. The hand-made-but-live keys (`ha-sync`, the two
`traefik-cert-sync`, and any future one) are a standing decision, not an oversight: either give
them items and stop hand-making them, or accept that revocation depends on remembering where they
live. `scripts/gate/check_ssh_grants.py` is the gate for that.

**The inventory is converged state, not a hand-kept list.** The accounts, their `authorized_keys` and the
`AllowUsers` gate come from `IaC/ansible/group_vars/all/access.yml` and a converge owns them. Live state,
measured per host with `ssh-keygen -lf`:

| Fact | Live state |
|---|---|
| `domen_ssh` placement | the `domen` account on **vps · oldsrv · nas · pi · spark**, and **not** under `ansible-admin` on any of them — place-then-remove is task order in the role, so no host ever has the key on neither account |
| `ansible-admin_ssh` | every host, unchanged — the converge key; the role asserts `ansible_admin_users` stays inside `AllowUsers` BEFORE it writes the gate (the guard is also in `self-converge-guard.yml`) |
| `ai_ssh` | oldsrv + nas only (where `roles/ai_diag` runs), with `from="10.10.0.0/16"` on the live line |
| Pi `admin` | **not an authorized identity, and scheduled for deletion.** A volatile journal cannot produce the acceptance count the retire sequence normally waits for, so the delete rests on the neutralized state: uid 1000 still present, `/etc/sudoers.d/admin` = `NOPASSWD:ALL`, the key line carrying a `# RETIRED-20261005` marker with a copy at `authorized_keys.disabled-20261005`; the operator's `Host pi` alias uses `domen`. Delete trigger = zero `admin` acceptances in `journalctl -u sshd`, then drop `access_admit_extra` from `host_vars/pi.kogler.si.yml` and remove the account; taking that reading is AI work, not an owner errand. With `admin` closed, `ssh ansible-admin@pi` (same key, that account) still authenticates and `sudo` there is NOPASSWD, so a botched revoke is recoverable without another credential |
| spark `admin` | exists, has no `~/.ssh` at all and is not admitted → inert; not a grant, so nothing here names it |

**Third-party grants survive by construction**: the role writes non-exclusively, so
`ha-sync@pi.kogler.si` (oldsrv/nas/vps) and the two `traefik-cert-sync@*` keys on the VPS
are untouched and stay named by their owning roles. `scripts/gate/check_ssh_grants.py` NAMES the
`domen_ssh` → `domen` grant.

## AI Diagnostics Access (`ai-diag`)

For disk-failure forensics, `ai-debug` gets **exactly one** sudo entry — a locked-down dispatcher, never a shell:

```
# /etc/sudoers.d/ai-diag  (deployed by Ansible role `ai_diag`, mode 0440)
ai-debug ALL=(root) NOPASSWD: /usr/local/sbin/ai-diag *
```

- **No free-form flags.** In sudoers `*` is greedy and matches spaces, so a bare `smartctl *` would allow `smartctl -a /dev/sda -s off`. The dispatcher runs only fixed command lines with regex-validated `/dev/` or identifier arguments — flag smuggling is impossible.
- **Runtime contract:** the AI runs `sudo ai-diag help` to see everything it may do. Read-only SMART/ZFS/journal diagnostics, plus three non-destructive ops: `smart-test-short`, `smart-test-long`, `smart-test-abort`.
- **Audited:** every invocation appears in the sudo + journal logs (`LogLevel VERBOSE`).
- **Updating:** the script lives in the repo (`IaC/ansible/roles/ai_diag/files/ai-diag`). Edit it → re-run the `ai_diag` role → hosts updated. No SSH gymnastics, no drift.

---

## Passwordless-First Design

### For Family

- **No passwords to remember or type** — everything is biometric
- **Authentik** serves the SSO login page
- **1Password Passkeys** (WebAuthn) handle authentication:
  1. Click "Log in with Passkey"
  2. 1Password intercepts → FaceID/TouchID/Master Password
  3. Logged in — no typing
- **No app has its own login** — Traefik Forward Auth blocks unauthenticated traffic before it reaches any service

### For Administration (Domen)

- **SSH keys** — three separate ED25519 keys (personal / Ansible / AI) in 1Password, injected by post_install.sh. AI key restricted to the `ai-debug` user (no sudo, LAN-only, no forwarding)
- **Ansible** — 1Password lookup at render time, no passwords in playbooks

- **Forgejo** — OIDC via Authentik, or deploy key with push access

### Cockpit maint seat — the one interactive password on a host

`maint` on nas + oldsrv is a break-glass console identity (`cockpit-<host>.kogler.si`), not a user, and it
is the only password a host holds. The vault item (`<host>-cockpit_login`, one per host) is the
**recovery copy**; the host keeps only the crypt hash in `/etc/shadow` — see the `…-cockpit_login` rows
in §Master Secret List.

- **Membership is an exact set, rebuilt every converge** (`cockpit-session` + `sudo`, `append: false`):
  a hand-added `docker` or `lxd` is dropped by the next run instead of persisting. What is *not* granted is
  asserted the same way — no SSH key, no `AllowUsers` entry, no `NOPASSWD` sudoers fragment.
- **The group is the control, so the gate lands in the same run as the account:** `/etc/pam.d/cockpit`
  ships with no group restriction, so `maint` without the `pam_succeed_if` line widens the surface
  instead of narrowing it ([security.md](security.md) §1).

---

## Family Safe — Physical Backup

Paper stored in family safe:

1. **1Password master password + recovery codes**
2. **Link to the GitHub repo** — `https://github.com/domenkogler/homelab` (public). It is the repo's **only**
   remote, so this link IS the off-site copy: there is no second git remote to fall back to, and the VPS
   Forgejo holds no copy of the homelab repo (the two git surfaces and their roles:
   [services-vps.md](services-vps.md) §Git hosting roles)
3. **Brief instructions in Slovenian:**
   - "Odpri ta link na računalniku"
   - "Preberi README.md"
   - "Če ne razumeš, pokliči [trusted tech contact]"

This ensures no single point of failure: 1Password cloud + paper backup + one public Git remote.

> **Transport a rebuild needs:** pulling the tree needs no credential at all (public over HTTPS); **pushing**
> rides SSH to GitHub with the seat key (`GitHub-homelab-deploy_ssh`). The VPS Forgejo publishes no git-SSH port
> — nothing is pushed there over SSH, and its git surface is HTTPS with a token
> ([services-vps.md](services-vps.md) §Git transport, as measured).

---

## Security Boundaries

> ⚠ **A rendered compose file on a host IS a secret file.** The templates substitute vault values at render
> time, so `grep`-ing `/opt/<svc>/docker-compose.yml` for a key name prints the credential next to it — asking
> "which env var does this read" against the rendered file is how a value reaches a transcript. Same class as the `--diff` ban in
> [`scripts/README.md`](../scripts/README.md): `--check` is safe, the *rendered text* is not. Read the
> **template** for names, and prove what the running app sees with a probe that prints a boolean or a length
> (`docker exec <c> env | cut -d= -f1`, or its own config API masked through `jq`).

| Boundary | Detail |
|----------|--------|
| **Actions runner → VPS** | Dedicated SSH key (separate from Domen's personal key) |
| **Actions runner → 1Password** | Service Account token (`op_api`) — stored as Forgejo secret |
| **Homepage → internet** | Protected by Authentik Forward Auth |
| **Renovate → Docker Hub** | Read-only registry access — no credentials for public images |
| **AI → homelab hosts** | Dedicated `ai-debug` user — LAN-only (`from=`), no agent/port/X11 forwarding; sudo limited to the `ai-diag` allowlist (read-only diagnostics, see below) |
| **Ansible → hosts** | Fail-closed guards (site.yml pre-flight + `common` role assert) — playbooks refuse to run as `ai-debug` or unknown users; sudo + docker group granted only to `ansible_admin_users` (`ansible-admin`, `pi`) |

### Runtime plaintext that leaves the vault — HA's `/config/.storage` (**ruling: ACCEPT**)

**The statement.** Home Assistant's `litellm` config entry stores the minted `home-assistant_api` virtual key in
plaintext at `/config/.storage/core.config_entries` on the Pi, and
[`ha-config-sync.sh.j2`](../IaC/ansible/roles/home_assistant/templates/ha-config-sync.sh.j2) rsyncs that whole
directory (`--delete`, excluding only `secrets.yaml`) to `/opt/home-assistant-standby/config/` on oldsrv every
~15 minutes. **That replication is accepted as-is.** It is the first case in this repo where a vault-minted value
leaves the vault-rendered set by a path no template controls, so it gets an explicit ruling instead of an
assumption (§6 secret hygiene).

**Why it is accepted — three measured facts, not a shrug** (all verified on the live pair):

1. **No new class of secret crosses that pipe.** The same directory already holds `auth` (HA's long-lived access
   tokens + refresh tokens) and `auth_provider.homeassistant` (the password hashes) — listed on the primary and on
   the standby copy. The standby has been receiving HA's *own* credentials since the sync shipped; a LiteLLM key
   joins a set that was never protected by the `.storage` boundary.
2. **The standby host is already a secret-holding host by design.** The sync excludes `secrets.yaml` precisely
   because each side renders **its own** from 1Password, so oldsrv already holds a rendered copy of every HA
   secret. "The key would land on a host that otherwise knows nothing" is not the situation.
3. **The value is deliberately capability-poor.** It is a scoped virtual key whose allow-list is the single row
   `spark/qwen3.8-flash-next` (measured `GET /v1/models` → exactly that list), `rpm: 30`, **no** `max_budget` —
   local inference behind the LAN edge, no upstream credential reachable with it, nothing metered to rotate for
   cost. Revocation is one Admin-UI delete (or clearing the vault item, which the create-only glue then re-mints).

**The mitigation that was rejected, and why.** Excluding `core.config_entries` from the rsync would keep the key off
oldsrv and cost exactly the thing the sync exists to buy: the standby would come up after a takeover **without the
conversation agent or its pipeline wiring**, so voice dies on failover and only returns after a hand-edited config
flow — a worse secret-hygiene story than the one accepted (it trades a local, revocable key for an unrecoverable
service difference), and it would silently re-open the voice-on-failover gap the standby exists to close.
`!secret` indirection is not available:
HA config entries take a literal string, and the integration reads no YAML — there is no `LITELLM_BASE_URL` and no
secret-reference path into a config entry.

**Compensating controls that are actually load-bearing.** The key is minted by IaC, so its *spec* (allow-list, rpm)
stays in git even though the value does not · it never appears in git, a rendered compose or a template — only in
the app's own store, which is out of reach of `scripts/gate/check_secrets.py` and is therefore **not** covered by that
gate (said out loud so nobody reads a green run as coverage) · the standby directory holds no vault-rendered file
that the sync itself wrote · rotation path: delete the alias in the LAN instance's Admin UI **and** clear the vault
item, then let the next `lan-litellm` deploy pass re-mint, then re-enter the value in HA's UI (config-flow only).

**Reopen trigger (the ruling is scoped, not blanket).** Re-decide this before any of: (a) the key's allow-list
gains an **external** model (`openrouter/…` — it would then be a metered credential sitting in a plaintext
replica); (b) a `max_budget` or a broader `models:` grant rides it; (c) `.storage` is ever backed up to a target
outside the two hosts without encryption; (d) the standby stops rendering its own `secrets.yaml` (fact 2 above is
load-bearing, so if that design changes, so does this ruling).
