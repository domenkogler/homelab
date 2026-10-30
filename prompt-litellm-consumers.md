# `prompt-litellm-consumers.md` — Lane brief · the LiteLLM consumption chain: scoped keys, the thinking control, `/ui`

> **Role:** dispatch note for **one** lane session on the LiteLLM gateway and its consumers. **The rows are the authority**
> for what is missing and how to do it — this file carries the contract, the order of work, the decided shape and the traps,
> nothing else: [todo.md](todo.md) **HD-384** (HD-249 is audited shut; its key waits for a consumer) · **HD-1178** (the
> **oldsrv** `embed` leg's next model is a bench call, not a leaderboard — [docs/services-ai-bench.md](docs/services-ai-bench.md) §3d —
> and a 768-dim winner costs a full Qdrant re-ingest, so no pin flip rides the row)
> (row ids as of `1c2cead3` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers and this brief deliberately restates none of them.

**Converge host + slot (O3):** the **oldsrv** `docker_services` slot carries the mint glue, the HA and n8n keys and the
`/ui` fix; the **VPS** slot carries the same chain's second instance; and any dial that reaches spark's engine needs the
**spark** slot, so it never runs inside a bench window. One converge in flight per host, detached, guarded, **never `--diff`**
(the secret-dump class). ⛔ **Do not share a wave with another oldsrv lane**: the Admin-UI writes here collide with a converge
that recreates the same containers, and `docs/services-ai*.md` is single-writer.

**Read first:** [docs/services-ai.md](docs/services-ai.md) §4 + **§4a** (the catalog runbook — executed payloads, row ids) +
§9c (the ecosystem constraints, stated against the pinned image) → the `litellm_scoped_keys` block in
[IaC/ansible/group_vars/home_servers.yml](IaC/ansible/group_vars/home_servers.yml) → [docs/smart-home-voice.md](docs/smart-home-voice.md)
§the LLM leg → [docs/deployment-secrets.md](docs/deployment-secrets.md).

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-384** | Finish the ordered pair: after spark has rebooted with `litellm-engine_api` in its accepted-key list, point `lan-litellm` + `litellm` `OPENAI_API_KEY` at it and converge both; then the OWUI grant, which cannot ship by editing records (create-only glue until `/key/update`) | ⚠ **Order is the whole risk** — the engine only accepts the new credential from its next boot; flipping the gateways first 401s every upstream call. Prove `GET https://llm.kogler.si/v1/models` answers **200** with the new bearer before touching either gateway. ⚠ `/model/list` is unusable with the master key; **`GET /model/info` on the LAN instance answers FOUR rows** (`spark/qwen3.8-flash-next`, `local-rerank`, `local-stt`, `bge-m3-vk`) and the VPS one, so `ollama/bge-m3` is a *fallback rung*, not a row. ⚠ The mint glue lives **inside** the `lan-litellm` deploy pass (name the service tag) and is **create-only**: a live key keeps its old allow-list until `/key/update` exists or the key is deliberately re-minted. ⚠ SGLang takes **one** key (`api_key: Optional[str]`), so a fast-sglang profile cannot host this two-credential shape |
| 2 | **HD-249** | Nothing to execute today: the audit is **done** (one workflow, one active webhook, caller is Grafana on the docker network, `auto.kogler.si` tailnet-only) and n8n has **no AI node**, so there is no key to mint yet | When an AI node appears: mint on the **LAN** instance with **no `max_budget`** and **local rows only** (`spark/qwen3.8-flash-next`) per the owner's ruling — an unused scoped key is a liability, not a head start |
| 3 | **HD-1178** | **PARKED (O4) — ruled not a standalone act.** The bench is the FIRST act of the memory-plane build (**HD-336**); while no memory server is being built nothing here is scheduled. The candidates, the two gates and the probe commands already live in [docs/services-ai-bench.md](docs/services-ai-bench.md) §3d — this row is the queue entry, not the research | ⛔ No compose change, no pin flip and no Qdrant change rides on this row; a 1024-native winner costs no re-ingest, a 768-dim one buys a full re-ingest + backtest before it buys anything. When it does run its first act is a pin bump that is **not embed-only** — the same `server-vulkan` image serves the reranker leg, so `--pooling rank` is re-proven on the new build, and a candidate measured without its own instruction prefixes was not measured |

## ⛔ Traps that cost a round

* **The pin is `litellm_version` in [IaC/ansible/group_vars/all/versions.yml](IaC/ansible/group_vars/all/versions.yml) — say
  nothing about LiteLLM's behaviour that you have not re-read there.** The rows and the
  old prose quote an older tag; §9c's constraints are written as "measured on the pinned image", so re-verify the two that
  your work touches before repeating them: DB-stored `litellm_params` do **not** expand `os.environ/…` (keys come from the
  container env, and a DB row carries none), and `jina_ai/`'s `get_complete_url` **replaces** the path, so a local reranker's
  `api_base` carries no path.
* **No re-decide list.** Decision #26 stands: generation harnesses go **direct to the engine**, LiteLLM serves the
  simple-querier tier + the pinned-AI legs, and external APIs are a harness-side fallback, **never** a proxy fallback.
  Scoped consumers get **one model row** — the `spark/qwen3.8-flash-next` **row**, never a `spark/*` wildcard; `rpm` is
  contention protection on the single KV pool, not a bill; `max_budget` was dropped for owned devices. The `rpm` figure lives
  in the SSOT, never edited in the LiteLLM DB.
* **Do not resurrect `dsh` / `pi-dev`.** The harness IaC is gone — no template dir, no service entry, the scoped-key catalog
  line is a comment — so there is nothing left to flip; the retired `dsh_api`/`pi-dev_api` items must not be re-seeded, and
  re-adding a row is a new decision, not a repair. `dsh` answers nothing in any namespace, and `pi-dev` survives only as
  `pi-dev.ts.kogler.si`, a second name on the live oldsrv cockpit backend
  ([docs/network-vpn.md](docs/network-vpn.md) §Pattern B).
* **Measured, do not re-derive:** the gateway name reaches the containers via `extra_hosts` (no host resolver answers it) ·
  **base_url is `https`** (the engine's `:80` is redirect-only and the SDK will not follow a 307 on POST) · model rows live in
  the **DB**, never in git · `lan-litellm` has no `curl`, so drive its API from the host against the backend address.
* **Secrets:** 1Password items only, `>-` block scalars, **fail-loud** (no `default('')`), and report lengths / prefixes / item
  ids / hashes — never a value. Every minted item gets its catalog row in the same change.

## Owns / never touches

**Owns:** `docs/services-ai.md` (single-writer: this lane) + `docs/services-ai-bench.md`, your items in
`docs/deployment-secrets.md`, `docs/smart-home-voice.md`, `templates/docker_services/{lan-litellm,litellm,n8n,home-assistant-primary,home-assistant-standby}/**`,
`roles/docker_services/tasks/{main,deploy-service}.yml` + `templates/litellm-bootstrap-keys.sh.j2`, `roles/home_assistant/**`,
the litellm/n8n regions of `group_vars/{home_servers,vps}.yml`, and your own `todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2) or another brief's rows; `roles/router/**`, `roles/tailscale-node/**`,
`templates/docker_services/{headscale,traefik-internal,traefik-tailnet,technitium}/**` (the transport lane's);
`roles/spark/**` and `docs/hardware-spark.md` (the spark slot's); `docs/{services-admin,security,services-vps}.md`; the
`home-assistant` **HA-side** rows (primary/standby, KNX, failover belong to the smart-home brief); the frozen archives and
generated `*-generated.md`.

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path counts as
not run. Concretely: `/model/info` on both gateways showing the decided rows · each scoped consumer authenticating with **its
own** key with one request proven end-to-end per consumer (HA Assist answering is the visible one) · the `llm`-router credential
shape named and the triple-use broken in the render, or the alternative shape recorded with the owner's call parked ·
`/ui/login` deep-link verified on the pinned image (the defect did not survive the current pin, §4c) · the plaintext-`.storage` ruling ruled and the HA entry + Assist wire live with one Slovenian turn proven ([docs/smart-home-voice.md](docs/smart-home-voice.md) header table) · every minted item in the secrets catalog · rows deleted or trimmed to their tails, no history in the
row · `bash scripts/validate-all.sh` green **in this worktree** → **stop**.
