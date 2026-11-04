# `prompt-spark-edge-authz.md` — Lane brief · moving inference auth to the edge

> **Role:** dispatch note for the spark **edge-authz** wave — the work that makes a bearer rotation stop costing an
> engine cold boot, by making the credential a client holds no longer be the credential the engine holds.
> **The rows are the authority** for what is missing: [todo.md](todo.md) **HD-1239 · HD-1240**. This file carries the
> ruled decisions, the phase order and the traps; it restates no process rule.
> **Linked from:** [todo.md](todo.md) · [todo-table.md](todo-table.md) §B0 (view-sync pending — the §B0 cell is owed in
> the merge commit, CONVENTIONS §6, orchestration §4 O7 step 4)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11). **Converge host + slot (O3):** **spark**,
one converge in flight; `spark-ai`, `spark-dashboard` and `spark-llm-authz` are three separate service directories.
**Rule 0:** a session whose own model is `spark/…` takes **no timed number** and runs **no engine act** — and by §C rule 2
anything that recreates `spark-ai` (engine args, its env, the `spark-llm_api` item) is outside such a session entirely.

---

## 1. Why this wave exists (the fact, not the plan)

vLLM's accepted-key list is **argv** (`templates/docker_services/spark-ai/docker-compose.yml.j2` renders `--api-key`
with N values, `nargs='+'`), and argv is fixed at container create. So every rotation of a client-held engine bearer is
a container recreate plus a cold load (`spark_llm_profiles.fast.health_start_period` = **2400 s**), which is why the
`spark-llm_api` / `litellm-engine_api` pair sits in `NOT_AUTO_ROTATABLE` and parked in
[`scripts/gate/secret_debt_register.txt`](scripts/gate/secret_debt_register.txt). The engine cannot be made
restart-free; **what can be changed is whether the value being rotated lives in it.**

## 2. Ruled by the owner (2026-11-04) — do not re-decide

| # | Ruling | Consequence |
|---|---|---|
| **D1 = 1A** | The engine ends up holding **one internal constant** (`spark-llm_api`, never client-held again). The `litellm-engine_api` argv slot is **removed**; `litellm-engine_api` stays the **gateway leg's own** credential but is then verified at the verifier, not by the engine. The harness/direct leg gets a **new** item, `spark-client_api`. | Deleting slot 2 also retires SGLang's `api_key: Optional[str]` blocker ([services-ai.md](docs/services-ai.md) §9c-adjacent note) |
| **D2 = 2A** | A **`forwardAuth` target on spark** (`spark-llm-authz`), stdlib-only Python, `python:3.12-slim` digest-pinned. Client tokens arrive as **plaintext in a 0600 rendered config** — the `spark-ai` compose pattern, deliberately not a hash allow-list ([deployment-rejected.md](docs/deployment-rejected.md) refuses live-secret hashes as *attestation*, a different purpose). | Verifier down = **inference dark**, accepted by the owner |
| **D3 = A+C+D** | The internal constant rotates **on already-planned boots** and **on proven exposure** — never on a calendar. **And** argv stops carrying it: `VLLM_API_KEY` replaces `--api-key`, which closes the class of leak that made HD-1170 a debt. | ⛔ `--api-key` and `VLLM_API_KEY` are mutually exclusive: the pin reads env **only** when `--api-key` is absent (`api_server.py`: `args.api_key or [envs.VLLM_API_KEY]`) → env accepts exactly **one** token, so D3-D is only legal **after** D1 |
| **D4 = 4B** | Prove on a **shadow router**, then attach to the live router as a separate one-line change. **Fail closed, no bypass var.** | The verifier joins the `monitoring` leg like any other critical service |

## 3. The phase ladder (this is the shape of the work)

There is no "both tokens work" state by accident: seats today hold a value the **engine** accepts, and after the change
they must hold one the **verifier** accepts — while the value HD-1170 published must **never** become an accepted client
token. The ladder is what makes that ordering safe.

| Phase | Act | Costs a boot? | Engine down? |
|---|---|---|---|
| **P0** | Deny `/invocations` at both edges — HD-1240 | no (file-provider reload) | no |
| **P1** | Engine argv = `spark-llm_api` **+** `spark-client_api` **+** `litellm-engine_api` (3 slots); `spark-llm-authz` deployed, **not attached**; seats re-render to `spark-client_api` | **yes** | no — every old value still valid |
| **P2** | Attach `forwardAuth` + the key rewrite to the shadow router, prove both directions, then flip it onto the live `llm` router | no | no; rollback = one line |
| **P3** | Drop `--api-key`, set `VLLM_API_KEY` = the internal constant only; re-teach `roles/spark/files/spark-oom-watchdog.sh` | **yes** | one cold load |

**Two boots, and both ride boots the queue already owes** ([spark/reports/external-window-card.md](spark/reports/external-window-card.md))
— that is what "D3 = A" buys. ⛔ The 3-slot argv is **temporary**: if it survives P3, D1 is only half true and the
rotation coupling survives on paper.

## 4. Traps, each one paid for already

- **Priority must be DECLARED.** The `llm` routers are Host-only; Traefik resolves overlap by priority, never by longest
  match, and an undeclared priority is **derived from rule length**. A security rule must not rest on that derivation.
- **`forwardBody` must stay `false`** — Traefik reads the body before forwarding, which **breaks streaming**. Authz is
  header/path-only here.
- **`authResponseHeaders` carrying a header literally named `Authorization` is undocumented either way.** Two requests
  decide it. Fallback if it fails: the `headers` middleware's `customRequestHeaders`, which is documented to overwrite —
  at the cost of putting the internal key in `/opt/spark-dashboard/dynamic/`.
- **`/metrics` answers 200 with no bearer at all**, so the watchdog's bearer is decorative and its re-teach is cheap.
- **Env is create-time too** — D3-D buys *leak* hygiene, never a rotation win.
- **A rotation window forbids any other converge** (`secret_debt_register.txt` preflight), and a green *scoped* converge
  is not evidence a credential landed — only the argv/env hash is.

## 5. Owed to the docs, blocked on another lane (transcribe verbatim, do not re-derive)

`docs/services-ai*.md` is single-writer (§C4) and was held by another session while this wave was prepared. When it is
free, in one commit: (a) a new §9 decision row for D1/D2/D3/D4 citing #26 (whose sanctioned direction this is — "harden
at the edge: router allow-list / a distinct client credential"); (b) rewrite §4a's consumer map — the engine stops
holding a client-held value and the "four independent bearers" list changes; (c) **retire the ruling at
[deployment-rejected.md](docs/deployment-rejected.md) "edge 401 with the old bearer as containment test"** — its stated
reason ("that host authenticates with the engine key") stops being true once the edge authenticates; (d) the
`services-ai-rejected.md` rows for the declined shapes (blue/green engine pair, hash allow-list delivery, authentik
outpost as a machine-token verifier); (e) the `spark-llm_api` / `litellm-engine_api` register lines and
`NOT_AUTO_ROTATABLE` membership move with the P3 boot, not before it.
