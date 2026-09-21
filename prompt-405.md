# `prompt-405.md` — Lane brief · remote-dev transport: reach oldsrv without the VPS (HD-405 · HD-406 · HD-408 · HD-410)

> **Role:** single-lane handoff for the **transport** half of the remote-dev-plane thread (owner direction
> 2026-09-20). Start with [README.md](README.md) §0 → §1 mandatory context → this file → the four HD rows in
> [todo.md](todo.md) §2.1. The *runner/cockpit* half is [prompt-407.md](prompt-407.md); remote desktop is
> [prompt-412.md](prompt-412.md). Decisions are already recorded — see the no-re-decide list.
> **Linked from:** [prompt.md](prompt.md) §2 · [todo.md](todo.md) · [todo-table.md](todo-table.md)
>
> ⛔ **CLOSED 2026-09-20 — do not start a session from this brief;** the thread continues in
> [`prompt-414.md`](prompt-414.md). **What shipped:** HD-405 LIVE — host `tailscaled` node `oldsrv`,
> `tag:dev:443`, `ha.ts.kogler.si` served from oldsrv's own edge. Do **not** re-run it. **What left the
> lane:** the owner's phone-on-cellular acceptance matrix, the two pre-existing faults (HA
> `ha_trusted_proxies`, `media.kogler.si` 502), and the new measurement — the first away session to the node
> came back **relayed via FRA** — all carried into the HD-405 / HD-414 / HD-415 rows of [todo.md](todo.md).
> **HD-406 / HD-408 / HD-410 stay open** and owner-gated. Two lane-rule gaps found while executing:
> `docs/services-admin.md` and the oldsrv node IaC (`roles/tailscale-node`, `roles/docker_services` 1P refs,
> `templates/docker_services/traefik-internal/**`) had to be edited for HD-405's own Goal but sat outside the
> Owns list — folded into `prompt-414.md`'s Owns.
>
> **Deletion is scheduled, and it is not a lane's job (2026-09-21):** under [prompt.md](prompt.md) §4 O7 the parent
> removes this file in its **cleanup commit**, together with the link fixes in `prompt.md`, `todo.md` and
> `todo-table.md` — those three are what `check_doc_map.py` actually scans. Until then the banner stays, so nothing
> launches a session from here. **Do not start work here, and do not delete it yourself.** (Amended 2026-09-21:
> **HD-408 is since decided — the exit node stays on the Pi, its row is deleted**; HD-406 and HD-410 are carried in
> [`prompt-414.md`](prompt-414.md) rows 4 and 5.)

## Goal

Two independent paths from the phone to a service on oldsrv, so that **remote development does not stop when
the VPS does** — and a measured answer (not a guess) about what happens when P2P fails.

Today every home-hosted UI reaches a phone as `mobile → headscale → VPS traefik-tailnet → WG S2S → oldsrv`,
so the VPS sits in the data path of the owner's own work. The thread's premise, in one line: **the home WAN is
a static public IPv4** ([network.md](docs/network.md) §WAN), so a direct path is available and we have been
routing around it.

## Rows (do them in this order)

| HD | Outcome | The one next action |
|----|---------|---------------------|
| **HD-405** | oldsrv joins headscale as its own node; phone↔oldsrv is P2P; oldsrv serves its own TLS from the synced wildcard pair | Owner mints the preauth key + tag and seeds the 1P item — stop and ask before that |
| **HD-406** | A WG peer on the RB4011 (DDNS endpoint, scoped allowed-IPs, optional full-tunnel for geo egress) | Owner picks peer credential + full-tunnel vs scoped |
| **HD-408** | Exit-node host (Pi vs oldsrv) — an owner call, not work | Ask it; implement whichever way it lands |
| **HD-410** | Measured `DIRECT`-vs-`relay` split from a phone on mobile data, then a DERP decision on evidence | Measure before building anything |

## ⛔ No-re-decide list (checked 2026-09-20 — these are settled, and two of them this thread had to walk around)

* **The tailnet boundary is now a scoped exception, not a repealed rule.** [network-rejected.md](docs/network-rejected.md)
  carries the 2026-09-20 `accepted` row: **one host**, **no advertised routes**, **no LAN bridge**. The
  boundary's purpose — Shelly/KNX/IoT/guest never tailnet-reachable — is preserved *on purpose*. `--advertise-routes`
  is not in scope, ever.
* **HD-398 closed as A — the VLAN-99 seal stays** ([network-rejected.md](docs/network-rejected.md) 2026-09-19).
  Do **not** widen `wg_s2s_vps.allowed_ips` or the router `available-from`. This lane's node is a *host* node, not
  a plane opening.
* **WG was "site-to-site only, no road-warrior"** — re-evaluated *only* for one admin device, with the reason for
  the original stance (family app-toggle simplicity) explicitly preserved for the family path. The row's gates are
  load-bearing: known-peer-only, allowed-IPs scoped to the one host, rate-limit + log the listener.
* **DERP is not to be self-hosted on a hypothesis** (HD-410). The derp map uses the public Tailscale set; that is
  a *measured* problem before it is an owned listener.

## Sequence + gates

1. **Owner gates first.** HD-405 needs a headscale preauth key + tag; HD-406 needs the peer key/password;
   HD-408 is a decision. Secrets: item names per `deployment-secrets.md` conventions, `>-` block scalars, never a
   literal, never a printed value (CONVENTIONS §6) — report **lengths/prefixes/ids only**.
2. **`tagOwners` before user #2.** `policy.hujson` is email-ACL only today (`tagOwners` intentionally empty since
   HD-268c), so `domen@kogler.si:*` would cover the new node. Declare `tagOwners` for the dev tag in the same
   change that joins the node — otherwise this lane quietly widens who can reach the box that holds the vault
   token.
3. **Docs move with the code.** [network-vpn.md](docs/network-vpn.md) §Tailnet-boundary currently states *"No home
   host runs a tailnet node"* and [services-admin.md](docs/services-admin.md) says *"oldsrv is a tailnet node"* —
   **both** are wrong after this lane in opposite directions. Fix both, plus the exit-node section and the
   MagicDNS/DNS records ([network-dns.md](docs/network-dns.md)).
4. **Router changes land in IaC**, not as hand-applied deltas: `roles/router` + `rb4011_converge.rsc.j2`, then the
   documented render → `/import` path ([network-ops.md](docs/network-ops.md) 3-tier rule;
   `scripts/routeros-apply-delta.sh` exists for transient deltas and the delta gets folded + deleted, never left).
5. **Verify = the actual dependency test, not a 200 OK.** From a phone on **mobile data** (not home WiFi):
   (a) cockpit/UI reachable via the node path with **headscale stopped** → proves control-plane independence;
   (b) same via the router WG peer with the tailnet interface **off** → proves path independence;
   (c) `tailscale netcheck` + the session-type line, recorded for HD-410;
   (d) an IoT/guest device is still *not* reachable from the tailnet (the invariant, proven not assumed).

## Lane rules (this runs concurrently — one writer per file)

* **Owns:** `docs/network-vpn.md`, `docs/network-dns.md`, `docs/network-ops.md`, `IaC/ansible/roles/router/**`,
  `IaC/router/templates/**`, `IaC/ansible/templates/docker_services/headscale/**`,
  `group_vars/vps.yml` **only** in the `tailnet_subdomains` / tailnet-IP region, and the tailscale ACL policy file.
* **Does NOT touch:** `docs/services-ai.md`, `docs/pi-harness.md`, `docs/security.md`, `scripts/**`,
  `docs/1password.md` (all [prompt-407.md](prompt-407.md)); no edits under
  `IaC/ansible/templates/docker_services/**` except the headscale ones ([prompt-412.md](prompt-412.md) adds the
  RustDesk templates).
* `group_vars/vps.yml` is shared with the RustDesk lane — stay inside `tailnet_subdomains`/tailnet IPs; that lane
  stays inside its `docker_services`/ports region. If the two edits collide, rebase the later merge, do not
  hand-merge YAML by eye.
* **Never run the away/hotspot re-measure while another lane has a converge in flight** — converge-hygiene notes in
  [scripts/README.md](scripts/README.md). Live converges run **detached**; never `--diff` on a
  `docker_services` converge; never `-e ansible_host=`.

## Acceptance (what "done" means here)

Reach matrix recorded per path (mobile data / home WiFi / headscale stopped / tailnet off) + an explicit
not-reachable assertion for IoT/guest · IaC in the repo with the converge/import log · `network-vpn.md`
rewritten to the new state (no stale "no home host runs a tailnet node" left standing) · HD-410 carries measured
numbers, including the boring result "P2P always wins, DERP stays public" · every open row keeps a trimmed ⏳ tail,
closed rows deleted (CONVENTIONS §4) · `bash scripts/validate-all.sh` green.
