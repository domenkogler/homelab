# `prompt-384.md` — Lane brief · give the simple queriers a route (HD-384 · HD-403 · HD-387 · HD-373 · HD-249)

> **Role:** dispatch note for **one** lane session on the LiteLLM consumption chain. **The rows are the authority** for what
> is missing and how to do it: [todo.md](todo.md) HD-384 · HD-403 · HD-387 · HD-373 · HD-249. This file carries the
> contract, the order of work, the decided shape and the traps — nothing else. History lives in the owning docs and in git.
> **Linked from:** [prompt.md](prompt.md) §3 · [todo.md](todo.md) · [todo-table.md](todo-table.md)

**Goal:** every scoped consumer that should reach the gateway **does**, through a credential of its own, with the caps
decided rather than invented — and the one contradiction in the record (does the thinking control survive the proxy?)
settled by measurement, not by a note in a row.

**Contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O8), which overrides README §4 / CONVENTIONS §6 at the
items it numbers. One session, one worktree, one branch, one brief. Never edit `prompt.md` or `todo-table.md` (O2); edit
**only your own `todo.md` rows** and tick **only your own** `deployment-tasks.md` lines. **You hold the oldsrv + VPS
`docker_services` converge slots** (O3): one in flight per host, detached, **never `--diff`** (the 2026-09-17 secret-dump
class). Owner gate → **park and continue** (O4). Any hand-repeatable step you performed writes its
[deployment-manual.md](deployment-manual.md) line **in your commit** (O6). Close-out = `docs/services-ai.md` +
`docs/deployment-secrets.md` + row tails + signed commit + `bash scripts/validate-all.sh` green **in this worktree** → **stop**.

⛔ Never in the same wave with [prompt-357.md](prompt-357.md), [prompt-361.md](prompt-361.md) or
[prompt-376.md](prompt-376.md) (oldsrv slot; the Admin-UI writes here also collide with a converge that recreates the same
containers) — pair with 376 only inside an open bench window.

## Order of work

| # | Row | Do | Gate / note |
|---|-----|----|-------------|
| 1 | **HD-384** | Mint the scoped consumers, then give the `llm` router a client credential of its own so `spark-llm_api` stops being triple-used | Decided 2026-09-21: the **`spark/qwen3.8-flash-next` row only** (never a `spark/*` wildcard), **`rpm` caps yes**, **`max_budget` dropped** (owned devices, no metered cost). ⚠ Read the catalog with **`GET /model/info`** first — `/model/list` is unusable with the master key and both gateways return **one row each**, so `ollama/bge-m3` is a *fallback rung*, not a row. ⚠ The mint glue lives **inside** the `lan-litellm` deploy pass (`--tags docker_services` alone never runs it — name the service tag) and is **create-only** |
| 2 | **HD-403** | Home Assistant gets an LLM to call: mint the vault-first `home-assistant` key, then point HA's **stock `litellm` integration** at the LAN gateway and add its conversation agent to the Assist pipeline | ⛔ There is **no `LITELLM_BASE_URL`** — URL + key go into HA's **config entry** (`.storage/core.config_entries`), config-flow only, no YAML import, so no compose template changes. ⚠ The key then sits in plaintext in `/config/.storage`, which the standby rsync copies to oldsrv — that ruling is owed in [docs/deployment-secrets.md](docs/deployment-secrets.md) **before** the entry is created. ⚠ The flow queries `/v1/models` **before** it creates the entry, so the mint must land first. [docs/smart-home-voice.md](docs/smart-home-voice.md) |
| 3 | **HD-387** | Run the **written probe protocol** against the LAN instance on the pinned image: baseline → toggle → budget pair → `top_k` → the proxy's own dropped-params log | A recorded live measurement and the pinned source **contradict each other**, and the failure mode is silent thinking-ON at HTTP 200. Master-key path, **no client change**; the harness route does not move either way (decision #26) |
| 4 | **HD-373** | Land the `/ui` SPA fix (nginx SPA fallback **or** Traefik `PathPrefix(/ui/)` rewrite); `/fallback/login` already works, so this is a real fix, not a fire | ⛔ Do **not** put Authentik/forward-auth on `/ui/*` route-wide — it breaks the same-host API bearer consumers |
| 5 | **HD-249** | n8n's AI nodes get a budgeted key — after the `WEBHOOK_URL` + external-webhook dependency audit | n8n rides the tailnet edge; its key is an HD-384 consumer once row 1 exists |

## ⛔ No-re-decide list (all of it is on record; re-deciding is the expensive failure here)

* **Decision #26 stands:** generation harnesses go **direct to `llm.kogler.si`**; LiteLLM serves the **simple-querier tier**
  + the pinned-AI legs; **external APIs are a harness-side fallback, never a proxy fallback**
  ([docs/services-ai.md](docs/services-ai.md) §9 row 26 + §9d, [docs/pi-harness.md](docs/pi-harness.md) §1b).
* **Row 1's shape** is decided in [docs/services-rejected.md](docs/services-rejected.md) (2026-09-21): scoped consumers get
  **one model row**; `rpm` is contention protection on the single KV pool, **not** a bill.
* **Do not re-enable `dsh` / `pi-dev`** (HD-386 + decision #26): their templates render a deliberately-empty 1P item, so
  flipping them takes the whole oldsrv `docker_services` converge down, and their tailnet names answering **502 is by design**.
  The `dsh` bearer itself is already cleared (HD-383 closed — record in [docs/deployment-secrets.md](docs/deployment-secrets.md));
  nothing here waits on it.
* **Measured, do not re-derive:** `llm.kogler.si` reaches the containers via `extra_hosts` (no host resolver answers it) ·
  **base_url is `https`** (spark `:80` is redirect-only and the SDK will not follow a 307 on POST) · LiteLLM **v1.83.10 does
  not expand `os.environ/`** in DB-stored `litellm_params`, so the key rides the container's `OPENAI_API_KEY` env and the DB
  row carries none.
* **Secrets:** 1P items only, `>-` block scalars, **fail-loud** (no `default('')`), and never print a value — lengths /
  prefixes / item ids / hashes only (CONVENTIONS §6).

## First action

Read the **§4a catalog runbook** in [docs/services-ai.md](docs/services-ai.md) (executed payloads, resulting row ids, the
v1.83.10 API shape) and the `litellm_scoped_keys` block in `IaC/ansible/group_vars/home_servers.yml`. Then `GET /model/info`
on **both** gateways, so any allow-list you design describes the catalog that exists.

## Owns / never touches

**Owns:** `docs/services-ai.md` + `docs/services-ai-bench.md`, `docs/deployment-secrets.md` (your items),
`docs/smart-home-voice.md`, `templates/docker_services/{lan-litellm,litellm,n8n,home-assistant-primary,home-assistant-standby}/**`,
`roles/docker_services/tasks/{main,deploy-service}.yml` + `templates/litellm-bootstrap-keys.sh.j2`, `roles/home_assistant/**`,
the **litellm/n8n regions** of `group_vars/{home_servers,vps}.yml`, your own `todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2); `roles/router/**`, `roles/tailscale-node/**`,
`templates/docker_services/{headscale,traefik-internal,traefik-tailnet,technitium}/**`; `roles/spark/**` +
`docs/hardware-spark.md` ([prompt-376.md](prompt-376.md)); `docs/{services-admin,security,services-vps}.md`;
the frozen archives and generated `*-generated.md`.

## Acceptance

`/model/info` on both gateways showing the decided rows · each scoped consumer authenticates with **its own** key and one
request is proven end-to-end per consumer (HA Assist answering is the visible one) · HD-387's probe table lands in §9d with
a **verdict**, not a hypothesis · every minted item has its [docs/deployment-secrets.md](docs/deployment-secrets.md) row ·
closed rows deleted, others trimmed (CONVENTIONS §4) · `bash scripts/validate-all.sh` green **in this worktree** → **stop**.
