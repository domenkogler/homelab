# `prompt-436.md` — Lane brief · the transport / answer-plane lane (HD-436 lead · HD-435 rides it · HD-460 parked)

> **Role:** dispatch note for **one** lane session. **The rows are the authority** for what is missing and how to do it:
> [todo.md](todo.md) HD-436 · HD-435 · HD-460. Design SSOT + the measured drift table:
> [docs/network-dns.md](docs/network-dns.md) §`zone_kogler_si` — read that, not this file.
> **Linked from:** [prompt.md](prompt.md) §3 · [todo.md](todo.md) · [todo-table.md](todo-table.md)

**Contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O8), which overrides README §4 / CONVENTIONS §6 at the
items it numbers. One session, one worktree, one branch. Never edit `prompt.md` or `todo-table.md` (O2); edit **only your own
`todo.md` rows**. Owner gate → **park and continue** (O4), naming the exact blocked action. Close-out = docs + row tails +
signed commit + `bash scripts/validate-all.sh` green **in this worktree** → **stop**; when the last row closes this brief
dies in the **parent's** cleanup commit (O7).

**Converge hosts:** Technitium (**oldsrv**) + the headscale / traefik planes (**VPS**) + the Cloudflare API. The router slot
is **not** needed (no `roles/router/**`). One converge per host, in flight, guarded.
**Window: owner-present.** Switching the consumers re-renders **live edge routing** for every tailnet-served app — this is
the lane the owner's LTE-direct access rides. ⛔ Never pair with another VPS or oldsrv lane.

## Step 1 sits unmerged — start there

`session/hd436-zone-derived-wip` (tip `20b49f4`, `validate-all` green **in it**), a few dozen commits behind `main`.
**First action:** `git worktree list`, then rebase it onto `main` **in a fresh worktree of that branch** and re-run
`validate-all` — never edit the old worktree in place. It already carries (do not re-do): the derived `zone_kogler_si` in
`group_vars/all/main.yml` with every entry required to carry `internal` / `ip` / `lan_only` / `tailnet` (none|edge|node|dual)
/ `ts_router`, so an omitted exposure field fails the build instead of becoming a decision nobody made;
`scripts/zone_kogler_si_render.py` (all three consumer views from that one list) + the pre-change golden set in
`scripts/testdata/zone_kogler_si_golden.json`; `scripts/check_dns_seed_drift.py` rewritten to **resolve** the derived loop
through the render script (it dies on a zero-row loop) with the LAN-only gate as three-way equality;
`scripts/check_zone_kogler_si_parity.py` wired into `validate-all`; and read-only proof that Ansible evaluates the derived
vars natively (the `'kogler.si' in zone_kogler_si_lan_only = False` boolean is the whole substring-bug class that once
dropped the apex, `litellm` and `logs` from the primary).

## What is left (the only reasons it is unmerged)

1. **Consumer switch:** `vps.yml`'s two subdomain lists (consumed by headscale's `config.yaml.j2` **and** the
   traefik-internal / traefik-tailnet / traefik-ha / spark-dashboard `dynamic/routes.yml.j2`) and `cloudflare_dns_records`
   in `roles/cloudflare_dns/vars/main.yml` are still hand-authored — those planes are **doubled**, and the parity gate keeps
   the halves equal until the switch makes them derived. Re-render with `zone_kogler_si_render.py` **first** (dry diff) and
   converge VPS + oldsrv in separate guarded runs.
2. **Step 2 — the `extra_records_path` swap**, with **HD-435's `tailnet: dual`** publish of `ha.ts.kogler.si` riding the
   same headscale converge. ⛔ `dns.extra_records` and `dns.extra_records_path` are mutually exclusive in pinned headscale
   0.29.3 and a fatal config still reports `Running` — run the guarded converge's **sampled** liveness probe, never a
   one-shot inspect.
3. **Close-out sweep:** make the branch header comment's claims match reality, update
   [docs/network-dns.md](docs/network-dns.md) §The answer-plane model, delete rows per lifecycle.

## Traps (measured; each cost a round)

- A `zone_kogler_si` validator must be able to say **"retired but deliberately published"**: `dsh.ts` and `pi-dev.ts` ARE
  still published by documented intent (HD-386 — the names resolve, the edge answers 502 by design,
  [docs/network-vpn.md](docs/network-vpn.md) §Parked names). Never infer retirement from `enabled:`.
- Separate known residue, not drift: headscale carries an orphan `localhost` node with no tag and no online state.
- **HD-435 landmines** ([docs/network-vpn.md](docs/network-vpn.md) §Tailnet boundary): `tailscale-node` was wired only into
  `home_servers.yml`; the pinned `.deb` needs `dpkg --print-architecture`, not the kernel fact; the dual answer is
  deliberately **not** a bolt-on to `tailnet_subdomains` (it would answer the PLAIN name client-side for a phone standing
  at home, HD-382/389).
- The reciprocal fall-over drill: one direction was already measured **by accident** and must not be recorded as the drill;
  stopping a standby's listener is a weaker proxy — label it as one; measure the delay before the second answer instead of
  asserting instant failover.
- **HD-460 is parked** on an owner edge-networking decision (the edge netns has no global IPv6 at all — measured 2026-09-27;
  the row + [docs/services-vps.md](docs/services-vps.md) carry it). Do not spend lane time on `--port`/publish work for it.
  If pin/publish is ever touched: **pin AND publish are ONE change**, on the netns owner (`traefik-tailnet`, not the
  `network_mode: service:` dependent); `Relayed` after the change means the pin did not take, not that the carrier won;
  never read netcheck's trailing port as the disco port.
- The seat constraint that came with the DNS-tier rulings: `pi-oldsrv.ts.kogler.si` is a headscale **MagicDNS `extra_record`**
  (`tailnet_ts_only_subdomains` in `group_vars/vps.yml`), **not** a Technitium record — anything that changes the MagicDNS
  answer set is **this** lane's work, and the DNS lane must not touch it.

## Acceptance

Parity gate green with all consumers derived (no doubled planes left) · headscale answering via `extra_records_path` ·
HA reachable by its tailnet name with either home box answering, drill recorded honestly · the seat still loads **with
Technitium stopped** (the only proof it gained no new dependency) · docs updated, rows deleted, this brief deleted with its
link fixes (the parent does both in one commit).
