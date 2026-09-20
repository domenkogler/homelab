# `prompt-407.md` — Lane brief · move the runner and the cockpit onto oldsrv (HD-407 · HD-409 · HD-411 · HD-413)

> **Role:** single-lane handoff for the **runner + cockpit** half of the remote-dev-plane thread (owner direction
> 2026-09-20). Start with [README.md](README.md) §0 → §1 mandatory context → this file → the four rows in
> [todo.md](todo.md) §2.3 / §2.7. Transport is [prompt-405.md](prompt-405.md); remote desktop is
> [prompt-412.md](prompt-412.md).
> **Linked from:** [prompt.md](prompt.md) §2 · [todo.md](todo.md) · [todo-table.md](todo-table.md)

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

| HD | Outcome | Blocker |
|----|---------|---------|
| **HD-407** | oldsrv = primary control node (repo + venv + `op` read-scope token + host keys); laptop demoted to rescue | Owner seeds the token + keys on oldsrv — only a human places those |
| **HD-413** | A fail-loud assert refusing oldsrv's own `network` / `ssh` / firewall / `storage` roles when oldsrv is the controller | None — pure IaC, do it **before** HD-407 goes live, not after |
| **HD-409** | pi harness + a phone-first browser cockpit served by oldsrv | Owner picks the surface + seeds the provider credential |
| **HD-411** | Paseo daemon trial, tailnet-bound, password-authenticated, relay **off** | Owner sideloads the APK + a 2-week verdict |

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

1. **HD-413 first.** The guardrail lands before oldsrv is allowed to drive itself. Show a **refused** run and an
   **allowed** run in the commit. Fail-loud: no `default()`, no `failed_when: false` — the HD-399 lesson.
2. **HD-407 next, and prove it, don't declare it.** Bootstrap the runner, then a `--check` pass **from oldsrv** for
   one playbook per inventory group. Known trap worth re-checking rather than trusting: the recorded "check mode
   breaks on oldsrv" was the `technitium-seed` `uri` task (**HD-399**) — if `--check` still dies there, that row is
   the blocker, say so, and use the documented interim form (`--check --tags common,network`).
   `scripts/ansible-run.sh`'s header and its `ANSIBLE_ROLES_PATH` export are WSL/`/mnt` artefacts — generalise the
   script, do not fork it, and keep the Windows invocation path documented (`cmd //c "wsl -d Debian -- bash …"`).
3. **HD-409 needs three things that are not code:** the owner's surface pick, the provider credential, and the
   **spark-edge client credential** that decision #26 defers — that is **HD-384's** scope. Until HD-384 lands,
   run on the existing `spark-llm_api` bearer and record the open item in the row; do **not** invent an allow-list.
   Mint a `*_port` var in `group_vars/all/main.yml` for the cockpit and use the var everywhere (never a literal):
   the parked container's old `:8080` reservation and `dozzle_http_port: 8081` are both spoken for — check the port
   map before choosing.
4. **A phone cockpit must survive the phone.** Prefer the session-JSONL/SSE model (disconnect-tolerant, PWA) over a
   browser-locked PTY; remember HD-298's lesson was **container-caused** (musl base, `--ignore-scripts`, the npm
   `allowScripts` gate, `cap_drop: ALL` vs node-pty/node-gyp) and a native glibc host install sidesteps all four.
   Keep the **TUI-in-tmux floor** working — the cockpit must never be the only door.
5. **State + backups.** The workspace, `~/.pi` sessions and the harness config (which carries a bearer key, never in
   git) need a Kopia seam — the oldsrv agent is live (HD-191/HD-318a), so this is scoping, not a new service.
6. **Docs move in the same change:** [pi-harness.md](docs/pi-harness.md) §1 ownership table, a numbered decision in
   [services-ai.md](docs/services-ai.md) §9 for the placement + surface, and the [todo-table.md](todo-table.md)
   dispatch view. Do not leave the laptop-only wording standing anywhere.

## Lane rules (concurrent with [prompt-405.md](prompt-405.md) and [prompt-412.md](prompt-412.md))

* **Owns:** `scripts/**`, `docs/1password.md`, `docs/deployment-ansible.md`, `docs/deployment-secrets.md`,
  `docs/hardware-oldsrv.md`, `docs/pi-harness.md`, `docs/services-ai.md`, `IaC/ansible/playbooks/**`,
  `IaC/ansible/roles/network/**` *(assert only — coordinate before editing; the router role belongs to lane 405)*.
* **Does NOT touch:** `docs/network-vpn.md` / `network-dns.md` / `network-ops.md` / `roles/router/**` (lane 405),
  `docs/security.md` (lane 412), `docs/services-admin.md`, `docs/services-vps.md`.
  If a statement belongs in one of those, write it into your own row's tail and name the lane that owes it.
* `docs/deployment-secrets.md` is shared with lane 412 (it appends RustDesk catalog rows). Keep each item's rows
  contiguous; expect a textual merge and rebase the later one.
* Never print a secret value — lengths / prefixes / item ids / hashes only (CONVENTIONS §6).

## Acceptance

An oldsrv-run `--check` log per inventory group + the refused/allowed assert pair in the commit · the cockpit
reachable and usable **from a phone** with the laptop shut · the TUI floor proven from the same phone ·
`pi-harness.md` + `services-ai.md` §9 + `1password.md` all describing the new state (no stale laptop-only claims) ·
rows trimmed or deleted per CONVENTIONS §4 · `bash scripts/validate-all.sh` green.
