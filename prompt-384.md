# `prompt-384.md` — Lane brief · give the simple queriers a route (HD-383 → HD-384 → HD-403 · + HD-387 · HD-373 · HD-249)

> **Role:** one lane for the whole **LiteLLM consumption chain** — the vault-and-registry change that finally gives
> voice and the simple-querier tier something to call, plus the two measurements/tails hanging off the same gateway.
> **Wave 3**, and it **follows** [`prompt-407.md`](prompt-407.md): HD-409's cockpit runs on the borrowed
> `spark-llm_api` bearer only until this lane mints the router its own client credential.
> Start with [README.md](README.md) §0 → §1 mandatory context → [prompt.md](prompt.md) **§4 (orchestrator mode)** →
> this file → the rows in [todo.md](todo.md) §2 (AI / Office).
> **Linked from:** [prompt.md](prompt.md) §2 + §4 · [todo.md](todo.md) · [todo-table.md](todo-table.md)
>
> **Lane contract (orchestrator mode — the authority is [prompt.md](prompt.md) §4, which OVERRIDES parts of
> README §4 and CONVENTIONS §6 at items O1–O8; where §4 is silent, README + CONVENTIONS stand and outrank this
> brief).** One session, one worktree, one branch, one brief; the parent creates them
> (`../homelab-wt-<YYYYMMDD>-<HHMM>` / `session/384-gateway-<YYYYMMDD>-<HHMM>`).
> **Never edit `prompt.md` or `todo-table.md`** (O2); edit **your own `todo.md` rows only** and tick your own
> `deployment-tasks.md` lines. **You hold the oldsrv + VPS `docker_services` converge slots** (O3): one converge in
> flight per host, detached, **never `--diff`** (HD-382 secret dump). Owner gate → **park and continue** (O4).
> Any hand-repeatable step (an Admin-UI click, a key mint) writes its `deployment-manual.md` line **in your commit**
> (O6). Close-out = `services-ai.md` + `deployment-secrets.md` + row tails + signed commit +
> `bash scripts/validate-all.sh` green **in this worktree** → **stop**; the parent merges and cleans up.

## Goal

Every scoped consumer that should reach the gateway **does**, through a credential of its own, with the caps decided
rather than invented — and the one contradiction in the record (does the thinking control survive the proxy?) settled
by measurement instead of by a note in a row.

## Rows — in this order, because the first one is a precondition

| # | HD | Action | Gate / note |
|---|----|--------|-------------|
| 1 | **HD-383** | Remediate the stale `dsh` secret **now** (owner authorized the write path): clear the 1P credential → delete the `dsh` alias in the **LAN** Admin UI → drop the item's doc row — **one change** | It is the precondition: the bootstrap-keys glue aborts `rc2` on a stale secret, and the glue must go back **on** for row 2. The abort is currently *unreachable*, not remediated |
| 2 | **HD-384** | Mint the scoped consumers, **decided 2026-09-21**: the **`spark/qwen3.8-flash-next` row only** (never a `spark/*` wildcard), **`rpm` caps yes**, **`max_budget` dropped** (owned devices, no metered cost), and **a separate client credential for the `llm` router** so `spark-llm_api` stops being triple-used (engine `--api-key` + both gateways' env + every direct client) | ⚠ Before writing allow-lists, read the catalog with **`/model/info`** — `/model/list` is unusable with the master key and both gateways return **one row each**, so `ollama/bge-m3` is a *fallback rung*, not a row (§4a runbook) |
| 3 | **HD-403** | Home Assistant gets an LLM to call: vault-first `home-assistant` scoped key, render `LITELLM_BASE_URL` + key into the compose env, point the Assist pipeline at it | HA's env carries **only `TZ`** today. Files: `templates/docker_services/home-assistant-primary/**` + `roles/home_assistant/**`, not `smart-home-voice.md` prose · [smart-home-voice.md](docs/smart-home-voice.md) |
| 4 | **HD-387** | Run the **written probe protocol** against the LAN instance on the pinned image (baseline → toggle → budget pair → `top_k` → the proxy's own dropped-params log) | A recorded live measurement and the pinned source **contradict each other**; the failure mode is silent thinking-ON at HTTP 200. Master-key path, **no client change**, and the harness route does not move either way (decision #26) |
| 5 | **HD-373** | Pick and land the `/ui` SPA fix (nginx SPA fallback **or** Traefik `PathPrefix(/ui/)` rewrite); the `/fallback/login` workaround already works, so this is a real fix, not a fire | ⛔ Do **not** put Authentik/forward-auth on `/ui/*` route-wide — it breaks the same-host API bearer consumers |
| 6 | **HD-249** | n8n's AI nodes get a budgeted key (its `WEBHOOK_URL` + external webhook dep audit first) | n8n lives behind the tailnet edge; its key is an HD-384 consumer once row 2 exists |

## ⛔ No-re-decide list (all of it is on record — re-deciding is the expensive failure here)

* **Decision #26 stands:** generation harnesses go **direct to `llm.kogler.si`**; LiteLLM serves the
  **simple-querier tier** + the pinned-AI legs; **external APIs are a harness-side fallback, never a proxy fallback**.
  [services-ai.md](docs/services-ai.md) §9 row 26 + §9d, [pi-harness.md](docs/pi-harness.md) §1b.
* **The decided shape of row 2** is in [services-rejected.md](docs/services-rejected.md) 2026-09-21 — scoped
  consumers get **one model row**, `rpm` is contention protection on the single 262k KV pool, **not** a bill.
* **Do not re-enable `dsh` / `pi-dev`** (HD-386 + decision #26): their compose templates render a
  **deliberately-empty 1P item**, so flipping them re-renders that item and takes the whole oldsrv
  `docker_services` converge down. Their tailnet names answering **502 is by design**.
* **Technical facts already measured** — do not re-derive: `llm.kogler.si` reaches the containers via `extra_hosts`
  (no host resolver can answer it); **base_url is `https`** (spark `:80` is redirect-only and the SDK won't follow a
  307 on POST); **LiteLLM v1.83.10 does not expand `os.environ/` in DB-stored `litellm_params`**, so the key rides the
  container's `OPENAI_API_KEY` env and the DB row carries none.
* **Secrets:** 1P items only, `>-` block scalars, **fail-loud** (no `default('')`), and never print a value —
  lengths / prefixes / item ids / hashes (CONVENTIONS §6).

## First action

Read the two things the record says are easy to get wrong: the §4a **catalog runbook** in
[services-ai.md](docs/services-ai.md) (executed payloads, resulting row ids, the v1.83.10 API shape) and the
`litellm_scoped_keys` block + the HD-386 comment in `IaC/ansible/group_vars/home_servers.yml`. Then `GET /model/info`
on **both** gateways before designing any consumer, so the allow-list describes the catalog that exists.

## Lane rules (Wave 3 — pair with [`prompt-376.md`](prompt-376.md) only, and only in an open bench window; otherwise run it alone)

* **Owns:** `docs/services-ai.md` + `docs/services-ai-bench.md` **once lane 407 has merged** (they are 407's while
  that lane is live — if it has not merged, you are in the wrong wave), `docs/deployment-secrets.md` (your items),
  `docs/smart-home-voice.md`, `IaC/ansible/templates/docker_services/{lan-litellm,litellm,n8n,home-assistant-primary,home-assistant-standby}/**`,
  `IaC/ansible/roles/docker_services/tasks/{main,deploy-service}.yml` + `templates/litellm-bootstrap-keys.sh.j2`,
  `IaC/ansible/roles/home_assistant/**`, the **litellm/n8n regions** of `group_vars/{home_servers,vps}.yml`, and
  **your own `todo.md` rows**.
* **Never touches:** `prompt.md` / `todo-table.md` (O2); `roles/router/**` + `roles/tailscale-node/**` +
  `templates/docker_services/{headscale,traefik-internal,traefik-tailnet,technitium}/**` (lane 414);
  `scripts/**` + `docs/{pi-harness,1password,deployment-ansible}.md` (lane 407's, still true while it lives);
  `docs/{services-admin,security,services-vps}.md` + `rustdesk-server` (lane 412); `roles/monitoring/**`
  (lane 420); `roles/spark/**` + `docs/hardware-spark.md` (lane 376); the frozen archives and generated
  `*-generated.md`.
* ⛔ **Never the same wave as `prompt-407` / `prompt-357` / `prompt-414`** — all converge oldsrv; the Admin-UI
  writes here also collide with a converge that recreates the same containers.

## Acceptance

`/model/info` on both gateways showing the decided rows · each scoped consumer authenticates with **its own** key and
one request is proven end-to-end per consumer (HA Assist answering is the visible one) · the stale `dsh` secret is
gone from the vault **and** the alias gone from the LAN gateway, with `bootstrap_keys` restored in the same change ·
HD-387's probe table lands in §9d with a verdict, not a hypothesis · every minted item has its
[deployment-secrets.md](docs/deployment-secrets.md) row · closed rows deleted, others trimmed per CONVENTIONS §4 ·
`bash scripts/validate-all.sh` green **in this worktree** → **stop** ([prompt.md](prompt.md) §4).
