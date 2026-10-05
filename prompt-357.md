# `prompt-357.md` — Lane brief · the family-facing surface (HD-357 · HD-17 + HD-217 · HD-358 · HD-418)

> **Role:** dispatch note for **one** lane session. **The rows are the authority** for what is missing and how to do it:
> [todo.md](todo.md) HD-357 · HD-17 · HD-217 · HD-358 · HD-418. This file carries the lane contract, the order of work and
> where to look — nothing else. History lives in the owning docs and in git.
> **Linked from:** [prompt.md](prompt.md) §3 · [todo.md](todo.md) · [todo-table.md](todo-table.md)

**Contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O8) — it overrides README §4 / CONVENTIONS §6 at the
items it numbers. One session, one worktree (`../homelab-wt-<YYYYMMDD>-<HHMM>`), one branch
(`session/357-launchpad-<YYYYMMDD>-<HHMM>`), one brief. Never edit `prompt.md` or `todo-table.md` (O2); edit **only your own
`todo.md` rows**. Owner gate → **park and continue** (O4), naming the exact blocked action. Close-out = owning doc + row
tails + signed commit + `bash scripts/validate-all.sh` green **in this worktree** → **stop**; the parent merges.

**Converge host:** **oldsrv** `docker_services` — one converge in flight, detached, **never `--diff`** (O3).
⛔ Never in the same wave as [prompt-384.md](prompt-384.md) or [prompt-361.md](prompt-361.md): all three converge oldsrv.

## Order of work

| # | Row | Do | Where the detail lives |
|---|-----|----|------------------------|
| 1 | **HD-357** | Wire the Homepage tiles/widgets to the endpoints that answer **today**, through the edge | `IaC/ansible/templates/homepage_services.yaml.j2` + `homepage_widgets.yaml.j2` **as rendered** — fix the template, never the live file. Tile layout SSOT: [docs/services.md](docs/services.md) |
| 2 | **HD-17 + HD-217** | Render the **IP-only** failover button (`homepage_failover_button`) | [docs/smart-home-failover.md](docs/smart-home-failover.md) · ⛔ the RFUSB path is obsolete (HD-18 rejected the stick) |
| 3 | **HD-358** | Close the Seerr → \*arr API-key + URL hand-off — **prefer automating it in IaC** over documenting it | [docs/services-media.md](docs/services-media.md); any step a human will repeat earns a [deployment-manual.md](deployment-manual.md) line in the same commit (O6) |
| 4 | **HD-418** | `ha_trusted_proxies` += `oldsrv_home_ip`. ⛔ It **restarts the smart-home controller** → only in an owner-named window; if no window is open, park it with the change staged (O4) | [docs/smart-home.md](docs/smart-home.md) · [docs/smart-home-rejected.md](docs/smart-home-rejected.md) |

## Traps

- Verify a tile **through the edge** — the home edge (`traefik-internal` on oldsrv) first, then the VPS edge — never from
  the container. `media.kogler.si` answers 200 through the home edge since HD-419 (jellyfin published on **loopback**).
- ⛔ No new public listeners: the family surface rides the existing edge + middleware tiers.
- A `curl 200` is not a working tile — the visual pass is the **owner's eye** ([todo-table.md](todo-table.md) §A2). Land the
  wiring, hand over the eyeball, leave the row a ⏳ tail.
- If you find the old 502 shape on other home-hosted services, **record it in** [docs/services-traefik.md](docs/services-traefik.md)
  and leave it — it is not this lane's row.

## Owns / never touches

**Owns:** the `homepage_*` templates, `templates/docker_services/{homepage,seerr,seerrng,jellyfin}/**`, the
`traefik-internal` routes your tiles need, `roles/home_assistant/**` (HD-418 only), your keys in
`IaC/ansible/group_vars/all/main.yml`, `docs/{services,services-media,services-traefik}.md`, your own `todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2); `roles/router/**`, `roles/tailscale-node/**`,
`templates/docker_services/{headscale,technitium,traefik-tailnet}/**` and the v6/filter work in `traefik-internal`
(the answer-plane lane, [prompt-436.md](prompt-436.md)); `roles/monitoring/**`; the frozen archives and generated `*-generated.md`.

## Acceptance

Every tile renders live data or is removed with a word in the row · the failover button renders in its IP-only form ·
the Seerr hand-off is automated in IaC **or** written as imperative procedure · closed rows deleted, others trimmed to an
exact ⏳ tail · `bash scripts/validate-all.sh` green **in this worktree** → **stop** ([docs/orchestration.md](docs/orchestration.md) §4).
