# `prompt-ha.md` — Execution plan · HA's tailnet name and the manual failover

> **Role:** the plan of execution the last session left for the next one — **it carries no rows of its own**, so the row it
> works stays dispatched through its own brief in [todo-table.md](todo-table.md) §B0 and nothing in the dispatch map moves
> for this file's sake. It exists because the *decision* that row waits on was answered by measurement, not by more
> analysis, and the shape of that answer belongs where the next session reads it before it types anything.
> **Linked from:** nothing yet — it is a row-less plan note, so `todo-table.md` §B0 does not carry it and no row points at
> it; the row's own brief pointer stays where it is.

**The row this plan closes** is [todo.md](todo.md) **HD-435** — a citation, not a claim: the row's brief pointer stays where
§B0 puts it. Re-derive it with `grep -n "^| HD-435 " todo.md` before quoting the number.

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O11). **Converge host (O3):** the **VPS**, for the
headscale records file — never share that wave with another VPS lane (`docker_services` restarts the edge under a sibling),
never `--diff`. The drill and the standby create are **owner-present** acts on the **Pi** and **oldsrv**.

**Read first:** [docs/network-vpn.md](docs/network-vpn.md) §Tailnet boundary →
[docs/smart-home-failover.md](docs/smart-home-failover.md) §Away access (tailnet) + §Nodes & Deployment →
[docs/network-dns.md](docs/network-dns.md) §The answer-plane model rulings 6 and 8.

## Established — carry it, do not re-derive it

| fact | where it comes from |
|---|---|
| a tailnet client answers **ONE** A record per name — the first IPv4 of the rows it was handed | `ipn/ipnlocal/node_backend.go` appends every `ExtraRecord` into `dcfg.Hosts`; `net/dns/resolver/tsdns.go` `resolveLocal`, `case dns.TypeA:`, returns the first IPv4 and `respond()` emits one RR (the multi-answer field `resp.IPs` is exit-node-only) — same at the pins and at upstream `main` |
| no client version, no setting and no `CNAME` twin turns two rows into two answers | upstream declines: `juanfont/headscale#2499` (`not_planned`), `tailscale/tailscale#6185` (open); the same type switch accepts only `"", "A", "AAAA"` and drops the rest |
| under `dns.extra_records_path` the **order** rows arrive in is headscale's Go-set order, not the render's | `hscontrol/dns/extrarecords.go` `set.SetOf` → `Slice()`, re-drawn per headscale start and per rewrite of the records file — so a `dual` name's leading row can change with no diff in git |
| **oldsrv's node answers `ha.ts.kogler.si` and proxies to the VIP**, so the VIP — not the record — decides which HA you reach | oldsrv's live render: the `ha-ts` router (`Host(ha.ts.kogler.si)` \|\| `Host(oldsrv.ts.kogler.si)`) on `websecure-ts` → `ha-backend` → `http://10.10.1.200:8123` |
| HA runs on the **Pi**, the VIP is a static address there, `keepalived` is inactive on both boxes, and **the standby container on oldsrv is absent** | [smart-home-failover.md](docs/smart-home-failover.md) 🔴 banner + `ip addr` / `systemctl is-active keepalived` on both boxes |

## The plan

1. **Take the owner's ruling on `ha`'s `tailnet:` class.** The recommended shape is `tailnet: node` with `tailnet_ip:`
   **omitted** — the class default is `tailnet_oldsrv_ip`, and because oldsrv's edge proxies to the VIP, that shape gives
   the *same* answer as today, drops the set-order artifact, and leaves the manual failover with **no DNS step at all**:
   the failover moves the VIP, the name keeps pointing at it. The alternative the owner may still prefer is
   `tailnet: node, tailnet_ip: "<tailnet_pi_ip>"` — the name then visibly rides the box that runs HA, and the failover
   runbook **must** gain the flip step; it also makes a Pi `tailscaled` death an outage for the name while HA stays
   healthy. ⛔ Keeping `dual` is the one option that buys an order nothing declares.
2. **Land it.** One field in `IaC/ansible/group_vars/all/main.yml`'s `zone_kogler_si`; then
   `python3 scripts/gate/check_zone_kogler_si_parity.py`, **read the diff it prints**, and move
   `scripts/testdata/zone_kogler_si_golden.json` **by hand in the same commit** —
   `capture_zone_kogler_si_golden.py` refuses to re-capture a derived zone, which is the point. Expected diff for the
   recommended shape: `headscale:ts_only` 29 → 28, the `ha.ts.kogler.si → <tailnet_pi_ip>` row gone; the Technitium and
   Cloudflare surfaces must not move. Name the changed answer, and why, in the commit message.
3. **Converge `headscale` on the VPS and prove it reached clients.** ⛔ no restart is owed: headscale watches the records
   file and pushes an ExtraRecords change to every client — the same watcher that shuffles the order today. From a tailnet
   device: `dig +short @100.100.100.100 A ha.ts.kogler.si` → the one surviving address, then
   `curl -s -o /dev/null -w '%{http_code} %{ssl_verify_result}\n' https://ha.ts.kogler.si/` → `200 0`. A client still
   answering the old row is a client cache, not an un-pushed netmap.
4. **Run the fall-over drill on purpose, in both directions** (owner-present). With one answer per name the symptom is a
   **hard failure of the name, not a switch**: stop the answering node's `tailscaled`, read `ha.ts` (must fail) and the
   other node's own name (must still answer 200), then the reciprocal direction. The direction already hit by accident
   does not count, and a one-direction repoint is a proxy, not the drill. Optional experiment that settles the set-order
   claim live: `sudo touch /opt/headscale/extra_records.json` on the VPS, then re-read which address a client gets —
   content-neutral, but it pushes a DNS update to every client, so it is an owner-present act.
5. **Fold the failover runbook to the ruling** in [docs/smart-home-failover.md](docs/smart-home-failover.md): either
   "the tailnet answer rides the standby and the VIP is the switch — **no DNS leg**", or the explicit flip step. Either
   way record the alias that needs no converge: whichever node is alive answers under its own name
   (`oldsrv.ts.kogler.si` / `pi.ts.kogler.si`) straight from the netmap. ⛔ Do not let the runbook imply the name was ever
   the gap — **the standby on oldsrv is absent**, its cold create is HD-1109's owner-window act, and until that runs no
   URL survives a Pi death.
6. **Close HD-435** when 1–5 are done: the row goes and every `HD-435` mention leaves **in the same change**
   (`todo.md`, `todo-table.md`, `prompt.md`, `prompt-dns-transport.md`, `deployment-manual.md` §1.4d, this file), and the
   docs that describe a `dual` answer say that **no live name uses the class** — it stays authored and validated.
7. **The app, per device (owner, no IaC path).** `https://ha.ts.kogler.si/` is the URL: it is the name IaC controls, so a
   future ruling moves it with a converge. `pi.ts.kogler.si` is a MagicDNS **node name** — free, but IaC cannot move it
   and it disappears with the peer's netmap entry, so it is the emergency alias and not the app's home.

## ⛔ Traps that cost a round

* **Never print a raw netmap** — `tailscale debug netmap` carries node keys. Project it:
  `sudo -n tailscale debug netmap | jq -c '[.DNS.ExtraRecords[] | select(.Name | startswith("ha"))]'` (CONVENTIONS §3).
* **A peer is not in every netmap.** The Pi is absent from oldsrv's netmap, so a `.ts` node name can answer on one device
  and not on another; family devices hold no grant to either home node, so a family phone off-LAN resolves neither `.ts`
  name. Test the device the app lives on, not the seat.
* **Two resolvers, one command.** `curl https://ha.ts.kogler.si/` uses the machine's resolver, not quad-100 — on a home
  host that answers nothing for `.ts`, so it prints `000` and reads like an outage. Pin it for the read:
  `curl --resolve ha.ts.kogler.si:443:100.64.0.3 …`.
* ⛔ a `200` fetched with `-k` is **not** a certificate verdict — read `ssl_verify_result` or `subject=`.
* **Read the pin, not the prose:** `headscale_version` / `tailscale_host_version` in
  `IaC/ansible/group_vars/all/versions.yml`; re-check the client behaviour above against them after any bump.
* **`ha_vip` is an A-record value, never a tailnet answer** — publishing the VIP as a `.ts` record hands tailnet peers an
  unroutable address (HD-477's defect class).

## Acceptance

Each step returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` with the number and the evidence path; a claim with no path
counts as not run. Concretely: `check_zone_kogler_si_parity.py` green with the fixture moved **in the same commit** and
the diff read in the message · exactly one `ha.ts` row in the rendered records file and a device-side `dig` naming the
address the ruling chose · `200` with `ssl_verify_result=0` on it · the drill recorded in both directions with the
accidental one labelled a proxy · the runbook naming either "no DNS leg" or the flip step, plus the alive-node alias ·
HD-435 deleted with its mentions swept in the same change · `bash scripts/validate-all.sh` green **in the worktree** →
**stop**.
