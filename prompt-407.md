# `prompt-407.md` — Lane brief · move the runner and the cockpit onto oldsrv (HD-407 · HD-409 · HD-411 · + HD-399 · HD-386 · HD-416 · HD-388)

> **Role:** single-lane handoff for the **runner + cockpit** half of the remote-dev-plane thread (owner direction
> 2026-09-20), **Wave 1**. Start with [README.md](README.md) §0 → §1 mandatory context →
> [prompt.md](prompt.md) **§4 (orchestrator mode)** → this file → the rows in [todo.md](todo.md) §2.3 / §2.7.
> Transport is [`prompt-414.md`](prompt-414.md) (Wave 2 — the successor to the closed `prompt-405`); remote desktop
> is `prompt-412` — brief deleted; **this wave's sibling
> lane is [`prompt-420.md`](prompt-420.md)** (file-disjoint, different converge host).
> **Linked from:** [prompt.md](prompt.md) §2 + §4 · [todo.md](todo.md) · [todo-table.md](todo-table.md)
>
> **Lane contract (orchestrator mode — the authority is [prompt.md](prompt.md) §4, which OVERRIDES parts of
> README §4 and CONVENTIONS §6 at items O1–O8; where §4 is silent, README + CONVENTIONS stand and outrank this
> brief).** One session, one worktree, one branch, one brief; the parent creates them
> (`../homelab-wt-<YYYYMMDD>-<HHMM>` / `session/407-runner-<YYYYMMDD>-<HHMM>`).
> **Never edit `prompt.md` or `todo-table.md`** (O2 — orchestrator-only); edit **your own `todo.md` rows only**,
> never re-sort or re-flow the table, and tick **your own** `deployment-tasks.md` lines only.
> **You hold the oldsrv converge slot** (O3): one converge in flight, detached (`nohup … &` + log + poll),
> `--tags` + scope, **never `--diff`** on `docker_services` (the 2026-09-17 secret-dump class). Owner gate → **park and
> continue** (O4): write the exact blocked action into the row's ⏳ tail, finish the rest, name the park in your
> report. Did a hand-repeatable step? `deployment-manual.md` gains the imperative line **in your commit** (O6).
> Close-out = owning doc + row tail + signed commit + `bash scripts/validate-all.sh` green **in this worktree**
> → **stop**: the parent merges, rebases the sibling, re-syncs the two views and deletes this brief.

## Goal

Make **oldsrv the machine you work on** — repo, harness, runner and cockpit — so the phone is a remote control
rather than a laptop replacement, and the WSL laptop stops being the only place anything happens.

Read first, because both premises were settled recently and this lane must not re-litigate them:
[pi-harness.md](docs/pi-harness.md) §1 (the harness config is *"admin workstation (laptop) only"* — **this lane
changes that ownership**, say so explicitly in the doc) and
[1password.md](docs/1password.md) §1 (*"this WSL Debian laptop — the only place `ansible-playbook` is run
interactively"* — **this lane changes that too**, decision row already appended in
[deployment-rejected.md](docs/deployment-rejected.md) 2026-09-20).

## Rows

**Merged-in rows** (added 2026-09-21, deliberately): they touch this lane's files or ride its converge, so one
session pays for the oldsrv converge once instead of three times. `todo.md` stays the registry SSOT — this table
is dispatch, not a second record of the row.

| HD | Outcome | Gate / next action |
|----|---------|--------------------|
| **HD-399** *(merged — do it first)* | every `docker_services --check` on oldsrv runs at all: gate the Technitium login block with `not ansible_check_mode` | **None — and it is row 1 because HD-407's acceptance is a `--check` pass from oldsrv, and this is the task that currently fails it** (`technitium-seed.yml:102`). ⛔ no `default()` / `failed_when: false` — fail-loud (the HD-399 rule the guard validator now enforces) |
| **HD-407** | oldsrv = primary control node (repo + venv + `op` read-scope token + host keys); laptop demoted to rescue | **None.** The 2026-09-21 owner round made the seeding **AI-runnable and authorized**: pull with the **read-only** `github-homelab-deploy_api` over HTTPS via a 0600 credential store (never in the remote URL); **GitHub is the live remote** (the VPS Forgejo holds no copy of this repo); the vault **signing** key is reused so commits there are signed and attributed; `github_auth` (push) stays off the box → **oldsrv is PULL-ONLY until HD-409** adds a repo-scoped write key |
| **HD-409** | pi harness + a phone-first browser cockpit served by oldsrv, under the **`domen`** seat | Surface + seat **decided**: `@ygncode/pi-web`. The **spark-edge client credential** is HD-384's scope ([`prompt-384.md`](prompt-384.md)) — until that lands, run on the existing `spark-llm_api` bearer and record the open item in the row; do **not** invent an allow-list |
| **HD-411** | Paseo daemon trial, tailnet-bound, password-authenticated, relay **off**, one 1P item | Runs **simultaneously with HD-409** (one comparison window, its own `*_port` var). Owner hand = sideload + pair + 2-week verdict → **park it, do not wait** (O4) |
| **HD-386** *(merged)* | the oldsrv converge goes green with `dsh` + `pi-dev` parked | You are converging oldsrv anyway: `--tags docker_services,lan-litellm` (**both** tags — scope alone tag-filters the per-service task list), detached, no `--diff`; expect the parked pair + the key glue to SKIP with `failed=0`, and put that log in the row |
| **HD-416** *(merged)* | every SSH grant on a managed host is named, or it does not exist — **read-only** `authorized_keys` audit (fingerprints + comments) diffed against the named set, failing loud on an unknown | Same inventory as this lane's own tail: the retired `oldsrv-rsync` key halves get deleted after one green backup night. ⛔ it must **never** edit an `authorized_keys` — the characteristic failure of an SSH tool is locking yourself out with your own fix |
| **HD-388** *(merged)* | client model config rendered from one repo spec (`pi` `models.json` + Continue config), credential resolved via `op` at render time | The cockpit must not hand-copy model config. ⚠ the template must **not** merge the two `contextWindow` numbers (engine **262,144** vs the LiteLLM row's **245,760** = window − reserve) — they differ on purpose |
| **HD-356** *(merged tail)* | the LAN gateway confirmed live **after** the converge | One re-check of `lan-litellm` (live + serving) once HD-386's converge is green. ⚠ Its role changed with decision #26: gateway for the **simple queriers**, not the harnesses — and the scoped-key glue tail is **not** a fix, it is OFF by design and belongs to HD-384 ([`prompt-384.md`](prompt-384.md)) |
| ~~HD-413~~ | ✅ **already shipped** — its row is deleted from `todo.md` and the guardrail is validator-enforced (`check_self_converge_guard.py`) | Context only, do not re-implement: it is the guard that makes a phone-driven oldsrv converge safe. `roles/tailscale-node` is lockout-capable, so **HD-413's lockout set includes `cockpit`** — converge from the laptop, not through the cockpit you are building |

## ⛔ No-re-decide list

* **Decision #26 stands** ([services-ai.md](docs/services-ai.md) §9 row 26 + §9d, [pi-harness.md](docs/pi-harness.md)
  §1b): the harness goes **direct to `llm.kogler.si`**, not through LiteLLM, and external APIs stay a harness-side
  fallback. Moving the harness to oldsrv does not change its route.
* **HD-386 stands:** `dsh` + `pi-dev` are parked `enabled: false` and their scoped-key records stay commented out.
  This lane adds a **dedicated deployment**, which is exactly the shape #26 left room for — it does **not** flip
  those registry entries. Flipping them re-renders a deliberately-empty 1P item and takes the whole oldsrv
  `docker_services` converge down (the live-found lesson is written into `group_vars/home_servers.yml` — read that
  comment block before touching the file).
* **HD-398 A (VLAN-99 seal)** and the oldsrv Home-leg reachability contract are settled —
  [network-vpn.md](docs/network-vpn.md) §Reaching LAN nodes when away is the only reachability SSOT; do not
  re-derive it, and it is **not this lane's file** (see lane rules).
* **HD-51:** family users are not in `docker`; the workspace account is a separate non-human one
  (`ansible-admin` / `ai-debug` precedent — `ai-debug` is admissible on oldsrv, which is not a public box; the VPS
  forbids it).

## Sequence + gates

1. **HD-399 first** *(the merged row that unblocks the rest of this brief)*. One `not ansible_check_mode` gate on
   the Technitium login block. Show a `home_servers.yml --limit oldsrv.kogler.si --check` run that reaches the
   Technitium tasks **before** and **after**, in the commit. Fail-loud: no `default()`, no `failed_when: false`.
   The interim form (`--check --tags common,network`) is the **before** evidence, not the deliverable.
   *HD-413, the guardrail this row used to wait on, is already in and validator-enforced.*
2. **HD-407 next, and prove it, don't declare it.** Bootstrap the runner, then a `--check` pass **from oldsrv** for
   one playbook per inventory group — which is only possible because of row 1. Known trap worth re-checking rather
   than trusting: the recorded "check mode breaks on oldsrv" was that same `technitium-seed` `uri` task.
   `scripts/ansible-run.sh`'s header and its `ANSIBLE_ROLES_PATH` export are WSL/`/mnt` artefacts — generalise the
   script, do not fork it, and keep the Windows invocation path documented (`cmd //c "wsl -d Debian -- bash …"`).
   **Nothing syncs the clones** — `git pull --ff-only` is an explicit act; say so in the doc.
3. **HD-409: two things are decided, one is deferred.** Surface = `@ygncode/pi-web`, seat = **`domen`** (measured:
   that account holds neither the `op` token nor the fleet key; `ansible-admin` stays runner-only; break-glass is
   the new `<host>-cockpit_login`, HD-361 — and `cockpit` is in HD-413's lockout set, so converge from the laptop).
   The deferred item is the **spark-edge client credential** = **HD-384**'s scope, not a gate: run on the existing
   `spark-llm_api` bearer and record it. Mint a `*_port` var in `group_vars/all/main.yml` for the cockpit and use
   the var everywhere (never a literal): the parked container's old `:8080` reservation and `dozzle_http_port:
   8081` are both spoken for — check the port map before choosing. HD-411's daemon takes its **own** var.
4. **A phone cockpit must survive the phone.** Prefer the session-JSONL/SSE model (disconnect-tolerant, PWA) over a
   browser-locked PTY; remember HD-298's lesson was **container-caused** (musl base, `--ignore-scripts`, the npm
   `allowScripts` gate, `cap_drop: ALL` vs node-pty/node-gyp) and a native glibc host install sidesteps all four.
   Keep the **TUI-in-tmux floor** working — the cockpit must never be the only door.
5. **State + backups.** The workspace, `~/.pi` sessions and the harness config (which carries a bearer key, never in
   git) need a Kopia seam — the oldsrv agent is live (HD-191/HD-318a), so this is scoping, not a new service.
6. **Docs move in the same change:** [pi-harness.md](docs/pi-harness.md) §1 ownership table, a numbered decision in
   [services-ai.md](docs/services-ai.md) §9 for the placement + surface, and the HD-416 grant inventory in
   [deployment-secrets.md](docs/deployment-secrets.md) §Who is authorized where. Do not leave the laptop-only
   wording standing anywhere. **`todo-table.md` is not yours this wave** (O2) — the parent re-syncs it after the merge.

## Lane rules (Wave 1: runs alongside [`prompt-420.md`](prompt-420.md) only)

* **Owns:** `scripts/**` **except** `scripts/build-llm-dashboard.py` and `scripts/adapt-vllm-dashboards.py`
  (those two belong to lane 420 this wave), `docs/1password.md`, `docs/deployment-ansible.md`,
  `docs/deployment-secrets.md`, `docs/hardware-oldsrv.md`, `docs/pi-harness.md`, `docs/services-ai.md`,
  `IaC/ansible/playbooks/**`, `IaC/ansible/roles/network/**` *(assert only — coordinate before editing; the router
  role belongs to lane 414)*, and — added 2026-09-21 because the merged rows need them and the old list did not
  cover them (the defect `prompt-405.md` recorded for itself): **`IaC/ansible/roles/docker_services/tasks/technitium-seed.yml`**
  (HD-399 only), **`IaC/ansible/templates/docker_services/lan-litellm/**`** and a **new** service directory of your
  own under `IaC/ansible/templates/docker_services/` for the cockpit (per-directory writer, O3), plus **your own
  keys only** in `group_vars/all/main.yml` (the cockpit/`paseo` port vars) and `group_vars/home_servers.yml`.
* **Never touches (this wave, orchestrator mode):** `prompt.md`, `todo-table.md` (O2),
  `scripts/build-llm-dashboard.py` + `scripts/adapt-vllm-dashboards.py` + `IaC/ansible/roles/monitoring/**` +
  `templates/docker_services/spark-dcgm/**` (lane 420), `docs/network-{vpn,dns,ops}.md` / `roles/router/**` /
  `roles/tailscale-node/**` / `templates/docker_services/{headscale,traefik-internal,traefik-tailnet}/**` (lane
  414), `docs/security.md` + `docs/services-admin.md` + `docs/services-vps.md` (lane 412), the frozen archives
  (`reports/changelog.md`, `reports/deployment-journal.md`, `docs/archived/`) and generated `*-generated.md`.
  If a statement belongs in a file you do not own, write it into your own row's tail and **name the lane that
  owes it**.
* `docs/deployment-secrets.md` is shared with lane 412 (it appends RustDesk catalog rows) and read by HD-416.
  Keep each item's rows contiguous; expect a textual merge and let the **later** merge rebase (O1).
* `group_vars/vps.yml` is **not yours** this wave — if HD-388 needs a VPS-side value, put it in your row's tail.
* Never print a secret value — lengths / prefixes / item ids / hashes only (CONVENTIONS §6).

## Acceptance

An oldsrv-run `--check` log per inventory group (HD-399's gate is what makes it possible — include the before/after
proof) · the runner bootstrap log + `restore-runner-key.sh` finding an empty path · the cockpit reachable and
usable **from a phone** with the laptop shut · the TUI-in-tmux floor proven from the same phone ·
`pi-harness.md` + `services-ai.md` §9 + `1password.md` all describing the new state (no stale laptop-only claims)
· the retired `oldsrv-rsync` key halves' disposition stated (HD-416 inventory updated, nothing edited) ·
each merged row keeps its ⏳ tail or is deleted per CONVENTIONS §4 · `deployment-manual.md` gains the imperative
off-box converge line if you ran the first one (O6) · `bash scripts/validate-all.sh` green **in this worktree**.

**Then stop.** Do not merge, do not re-sync `todo-table.md`, do not delete this brief — that is
[prompt.md](prompt.md) §4's merge-and-cleanup sequence, and it belongs to the parent.
