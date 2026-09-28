# Lane brief — HD-436 transport / answer-plane lane (wave 3)

> **Role:** dispatch brief for one lane session: the `zone_kogler_si` derived-list epic and what rides on its
> converge. The rows ([todo.md](todo.md) HD-436 · HD-435 · HD-460) stay the authority for WHAT is missing; this
> brief carries the lane contract, the parked-branch state and the traps. SSOT for the design and the measured
> drift table is [docs/network-dns.md](docs/network-dns.md) §`zone_kogler_si` — read that, not this file.
> **Dies with the lane:** when the last row closes, the orchestrator deletes this file in the same commit as
> its link fixes ([docs/orchestration.md](docs/orchestration.md) O7); any residue is folded back into the row.

**Rows:** HD-436 (lead) · HD-435 (rides 436's converge) · HD-460 (parked — owner decision, see below).
**Converge hosts:** the router slot is NOT needed (no `roles/router/**`); this lane touches Technitium
(oldsrv), headscale + traefik planes (VPS) and the Cloudflare API — one converge in flight per host (O3).
**Window:** owner-present. Switching the consumers re-renders live edge routing for every tailnet-served app —
this is the lane the owner's LTE-direct access rides. Never pair with another VPS or oldsrv lane.

## Parked branch — start here

Step 1 sits unmerged on `session/hd436-zone-derived-wip` (tip `20b49f4`), **validate-all GREEN in it**, several
dozen commits behind main → **first action: rebase onto main inside a fresh worktree of that branch and re-run
validate-all** (`git worktree add ../homelab-wt-<date>-<HHMM> session/hd436-zone-derived-wip` — never edit the
old worktree in place if it still exists; check `git worktree list`).

The branch already carries (do not re-do):
- the derived `zone_kogler_si` in `group_vars/all/main.yml` — every entry REQUIRED to carry
  `internal` / `ip` / `lan_only` / `tailnet` (none|edge|node|dual) / `ts_router`, so an omitted exposure field
  fails the build instead of becoming a decision nobody made;
- `scripts/zone_kogler_si_render.py` — renders all three consumer views from that one list;
- `scripts/testdata/zone_kogler_si_golden.json` pre-change golden sets — parity proven, not asserted;
- `scripts/check_dns_seed_drift.py` rewritten to RESOLVE the derived loop through the render script (dies on a
  zero-row loop) + the LAN-only gate as three-way equality (real `when` excludes vs checker expectation table vs
  `lan_only:` flags) — proven RED by re-pointing `media` and un-flagging `spark`;
- `scripts/check_zone_kogler_si_parity.py` wired into `validate-all` — holds the (empty where it must be:
  primary 35/35, home 43/43, both headscale planes match; residue = fixture shape only, Cloudflare rows carry
  `state: ""`) golden diff open against future edits;
- proof that Ansible itself (not just the Python mirror) evaluates the derived vars natively — read-only on the
  VPS: `'kogler.si' in zone_kogler_si_lan_only = False` (that boolean is the whole substring-bug class that
  once dropped the apex, `litellm` and `logs` from the primary).

## What is left (the only reasons it is unmerged)

1. **Consumer switch:** `vps.yml`'s two subdomain lists — consumed by headscale's `config.yaml.j2` AND the
   traefik-internal / traefik-tailnet / traefik-ha / spark-dashboard `dynamic/routes.yml.j2` — and
   `cloudflare_dns_records` in `roles/cloudflare_dns/vars/main.yml` are still hand-authored; those planes are
   DOUBLED and the parity gate keeps the halves equal until the switch makes them derived. Re-render with
   `zone_kogler_si_render.py` FIRST (dry diff) and converge VPS + oldsrv in separate guarded runs.
2. **Step 2 — the `extra_records_path` swap**, with **HD-435's `tailnet: dual` publish of `ha.ts.kogler.si`**
   riding the same headscale converge. ⛔ `dns.extra_records` and `dns.extra_records_path` are mutually
   exclusive in pinned headscale 0.29.3 and a fatal config still reports `Running` — run the guarded converge's
   sampled liveness probe, never a one-shot inspect (Step 0's probe shipped; a crash-looping container reports
   `Running` between crashes).
3. Close-out sweep: fix the branch header comment's claims to match reality (an earlier one named a
   `cloudflare_dns_sync.py --zone-source derived` that does not exist and a `dns.extra_records` that never did),
   update [docs/network-dns.md](docs/network-dns.md) §The answer-plane model, delete rows per lifecycle.

## Traps (measured, each cost a round)

- A `zone_kogler_si` validator must be able to express **"retired but deliberately published"**: `dsh.ts` and
  `pi-dev.ts` ARE still published by documented intent (HD-386 — the names resolve, the edge answers 502 by
  design, [docs/network-vpn.md](docs/network-vpn.md) §Parked names); never infer retirement from `enabled:`.
- Separate known residue, not drift: headscale carries an orphan `localhost` node with no tag and no online state.
- HD-435 landmines (full text in [docs/network-vpn.md](docs/network-vpn.md) §Tailnet boundary):
  `tailscale-node` was wired only into `home_servers.yml`; the pinned `.deb` needs `dpkg --print-architecture`,
  not the kernel fact; the dual answer is deliberately NOT a bolt-on to `tailnet_subdomains` (would answer the
  PLAIN name client-side for a phone standing at home, HD-382/389).
- The reciprocal fall-over drill: one direction is already measured **by accident** and must not be recorded as
  the drill; stopping a standby's listener is a weaker proxy — label it as one; measure the delay before the
  second answer instead of asserting instant failover.
- HD-460 is parked on an owner edge-networking decision (the edge netns has no global IPv6 at all — measured
  2026-09-27; details in the row + [docs/services-vps.md](docs/services-vps.md)). Do NOT spend lane time on
  `--port`/publish work for it. If pinning/publishing is ever touched: pin AND publish are ONE change, on the
  netns owner (`traefik-tailnet`, not the `network_mode: service:` dependent); `Relayed` after the change means
  the pin did not take, not that the carrier won; never read netcheck's trailing port as the disco port.

## Acceptance

Parity gate green with all consumers derived (no doubled planes left), headscale answering via
`extra_records_path`, HA reachable by its tailnet name with either home box answering (drill recorded honestly),
docs updated, rows deleted, this brief deleted with its link fixes.

## Lane rules

Full contract: [docs/orchestration.md](docs/orchestration.md) §4 (O1–O8). Touch only your own rows; never edit
`prompt.md` / `todo-table.md`; park and continue on owner gates (O4), naming the exact blocked action.
