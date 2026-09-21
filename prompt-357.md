# `prompt-357.md` — Lane brief · make the launchpad and the home edge tell the truth (HD-357 · HD-17 + HD-217 · HD-358 · + HD-418 window-gated)

> **Role:** one lane for the **family-facing surface**: the tiles that are dead, the failover button that is rendered
> nowhere, and the two hand-offs that still need a human to paste a key. **Wave 4** — it waits on
> [`prompt-414.md`](prompt-414.md), because HD-414's row 6b publishes the jellyfin port that HD-357's tile depends on.
> Start with [README.md](README.md) §0 → §1 mandatory context → [prompt.md](prompt.md) **§4 (orchestrator mode)** →
> this file → the rows in [todo.md](todo.md) §2 (Network / platform, AI / Office).
> **Linked from:** [prompt.md](prompt.md) §2 + §4 · [todo.md](todo.md) · [todo-table.md](todo-table.md)
>
> **Lane contract (orchestrator mode — the authority is [prompt.md](prompt.md) §4, which OVERRIDES parts of
> README §4 and CONVENTIONS §6 at items O1–O8; where §4 is silent, README + CONVENTIONS stand and outrank this
> brief).** One session, one worktree, one branch, one brief; the parent creates them
> (`../homelab-wt-<YYYYMMDD>-<HHMM>` / `session/357-launchpad-<YYYYMMDD>-<HHMM>`).
> **Never edit `prompt.md` or `todo-table.md`** (O2); edit **your own `todo.md` rows only**. **You hold the oldsrv
> converge slot** (O3): one converge in flight, detached, **no `--diff`**. Owner gate → **park and continue** (O4):
> the HD-418 HA restart and the visual sign-off are the owner's — park them with the exact action. Close-out = owning
> docs + row tails + signed commit + `bash scripts/validate-all.sh` green **in this worktree** → **stop**.

## Rows

| # | HD | Action | Gate / note |
|---|----|--------|-------------|
| 1 | **HD-357** | Wire the Homepage tiles/widgets to the **verified** endpoints (home edge + VPS edge): Jellyfin and Seerr are dead, Immich is stuck "Soon" (bug #6) | Endpoints and route tables are **final** — this is wiring, not architecture. The tile only lights up once **HD-419** (lane 414 row 6b) has published the jellyfin Home-leg port; if it has not, say so and park that tile |
| 2 | **HD-17 + HD-217** | Render the **IP-only** failover button (`homepage_failover_button`) — `ha-failover-api` has been active on oldsrv since 2026-09-08, only the render is missing | ⛔ the RFUSB path is obsolete (**HD-18 rejected**); one failover button, IP-only · [services-traefik.md](docs/services-traefik.md) |
| 3 | **HD-358** | Record the Seerr → \*arr API-key + URL hand-off as a runbook step, and **prefer automating it in IaC** over documenting it (bug #7) | Home edge is up; the manual step is exactly the class README §4.8 says the doing session writes down — or removes |
| 4 | **HD-418** *(window-gated)* | `ha_trusted_proxies` += `oldsrv_home_ip`, so the **standby** HA edge stops answering `400` to anything oldsrv proxies | ⛔ The fix **restarts the smart-home controller** → it runs only in a planned window the owner names (O4). Decided 2026-09-21; **park it with the exact change staged** if no window is open · [smart-home-rejected.md](docs/smart-home-rejected.md) |

## ⛔ No-re-decide list

* **Placement and endpoints are settled** — the home edge (`traefik-internal` on oldsrv) and the VPS edge exist; the
  tile layout is the accessibility SSOT in [services.md](docs/services.md). Do not re-plan the launchpad.
* **`media.kogler.si` 502 is HD-419, not yours** (lane 414). Your tile consumes its result.
* **HD-316's visual pass is the owner's eye** ([todo-table.md](todo-table.md) §A2). Land the wiring, hand over the
  eyeball, and leave the row with a ⏳ tail — do not declare a tile "working" from a `curl 200`.
* **No new public listeners.** The family surface rides the existing edge and middleware tiers.

## First action

Read `IaC/ansible/templates/homepage_services.yaml.j2` and `homepage_widgets.yaml.j2` **as rendered**, then diff each
tile against the endpoint that actually answers today (the home edge first, then the VPS edge). Fix the template, not
the live file — the render is the SSOT.

## Lane rules (Wave 4 — pair with prompt-394.md — brief deleted only)

* **Owns:** `IaC/ansible/templates/homepage_services.yaml.j2`, `IaC/ansible/templates/homepage_widgets.yaml.j2`,
  `IaC/ansible/templates/docker_services/{homepage,seerr,seerrng,jellyfin}/**`,
  `IaC/ansible/templates/docker_services/traefik-internal/dynamic/routes.yml.j2` **for the routes your tiles need**,
  `IaC/ansible/roles/home_assistant/**` (HD-418 only), your own keys in `IaC/ansible/group_vars/all/main.yml`,
  `docs/{services.md,services-media.md,services-traefik.md}`, and **your own `todo.md` rows**.
* **Never touches:** `prompt.md` / `todo-table.md` (O2); `roles/router/**`, `roles/tailscale-node/**`,
  `templates/docker_services/{headscale,technitium,traefik-tailnet}/**` and the **v6/filter** work in
  `traefik-internal` (lane 414 — if it is still live, you are early: rebase or stop); `docs/{services-ai*,pi-harness,1password,deployment-*}.md` +
  `scripts/**` (lanes 384 / 407); `roles/monitoring/**` (420); `docs/{services-admin,security,services-vps}.md`
  (412); the frozen archives and generated `*-generated.md`.
* ⛔ **Never the same wave as `prompt-407` / `prompt-384` / `prompt-414`** — all converge oldsrv.

## Acceptance

Every launchpad tile either renders live data or is removed with a word in the row · the failover button renders with
the IP-only form and the ⛔ RFUSB note is reflected in the doc · the Seerr→\*arr step is either automated in IaC or
written as imperative procedure in [deployment-manual.md](deployment-manual.md) (O6) · closed rows deleted, others
trimmed with an exact ⏳ tail · `bash scripts/validate-all.sh` green **in this worktree** → **stop**
([prompt.md](prompt.md) §4).
