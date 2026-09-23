# `prompt-414.md` — Lane brief · dual-stack the home edge, then close the remote-dev transport (HD-414 · HD-415 · HD-405 tail · HD-410 · HD-406 · + HD-419 · HD-09 · HD-301 · HD-159)

> **Status — 2026-09-22 close-out.** The AI-runnable half of this lane is **shipped and measured**. Registry rows
> it closed: **HD-414** (scoped IPv6 on VLAN 10, filter before RA, delta folded into the converge, invariants
> re-proven), **HD-410** (DERP posture decided — no self-hosted relay, confirmed by two measurements), **HD-419**
> (jellyfin loopback publish, `media` 502→200), **HD-301** (hardening floor verified on the live device) and
> **HD-09** (void — [docs/network-rejected.md](docs/network-rejected.md)). What this file is still for: **HD-415** (shipped 2026-09-22 — only the owner's three-case drill remains)
> — the owner ACL call is **answered ✅ include `udp 53`**, and the headscale stop/start is authorized **conditional
> on a safety auto-re-enable if the driving session drops**, so it is now AI-runnable — **HD-406**, **re-decided as
> MikroTik Back To Home** and deferred by the owner, and the **HD-159** wg-down window (owner-gated). Delete this
> brief when the last of them closes.

> **Role:** successor to `prompt-405.md` (the closed transport banner — the orchestrator deleted that file
> 2026-09-22 with the link fixes in the two views; audit trail `git log --follow prompt-405.md`). That lane shipped the transport (HD-405 LIVE: `oldsrv`
> is a headscale node on `tag:dev:443`, `ha.ts.kogler.si` served from oldsrv's own edge) and **measured the
> assumption the thread was built on — and it did not survive.** First away session ever run to the node
> (owner's phone, cellular): **`Relayed connection (FRA)`, 60–90 ms**, i.e. the data path left the VPS and
> landed on someone else's relay in Frankfurt instead. Owner holds a **static IPv6 /56 from the ISP, not yet
> configured on the RB4011**. This lane makes that path direct, then finishes what 405 left open.
> Start with [README.md](README.md) §0 → §1 mandatory context → this file → the HD rows in [todo.md](todo.md).
> **Linked from:** [prompt.md](prompt.md) §2 + §4 · [todo.md](todo.md) · [todo-table.md](todo-table.md)
> **Sibling lanes:** runner/cockpit = `prompt-407.md` (**closed 2026-09-23, brief deleted**) · remote desktop =
> prompt-412.md — brief deleted · cadence = [`prompt-420.md`](prompt-420.md).
> **Wave 2.** Pair it with prompt-412.md — brief deleted only (you hold the router + oldsrv slots, it holds the
> VPS one). ⛔ **Never with `prompt-407.md` (**closed 2026-09-23, brief deleted**)** — both converge
> oldsrv, both need `group_vars/all/main.yml`, and once this brief's HD-415 row lands they would both reach the
> Technitium files; and never with `prompt-357` / `prompt-384` for the same reason. `prompt-420` is also
> compatible, but it is consumed in Wave 1.
>
> **Lane contract (orchestrator mode — the authority is [prompt.md](prompt.md) §4, which OVERRIDES parts of
> README §4 and CONVENTIONS §6 at items O1–O8; where §4 is silent, README + CONVENTIONS stand and outrank this
> brief).** One session, one worktree, one branch, one brief; the parent creates them
> (`../homelab-wt-<YYYYMMDD>-<HHMM>` / `session/414-ipv6-<YYYYMMDD>-<HHMM>`).
> **Never edit `prompt.md` or `todo-table.md`** (O2); edit **your own `todo.md` rows only**. **You hold the router
> slot — and the router slot is global** (O3): that converge is a device-wide `/import`, so nothing else touches
> RouterOS while you are in it, and **no away/hotspot re-measure runs anywhere in the repo while your converge is
> in flight**. Owner gate → **park and continue** (O4): the phone-on-cellular matrix, the headscale stop/start and
> any HA restart are the owner's word — write the exact blocked action into the row's ⏳ tail, finish the IaC and
> the docs, report the park. Any hand-repeatable step writes its `deployment-manual.md` line **in your commit**
> (O6) — the v6 probe runbook almost certainly qualifies. Close-out = SSOT docs + row tails + signed commit +
> `bash scripts/validate-all.sh` green **in this worktree** → **stop**; the parent merges and cleans up.

## Goal

Home is IPv4-only behind RB4011 NAT: `tailscale netcheck` on oldsrv reports `UDP: true`, external
`<home WAN>:49343` (the router rewrites tailscaled's port), `MappingVariesByDestIP: false`, **no port
mapping**, **no IPv6 anywhere**, nearest DERP fra 18 ms. Single NAT with endpoint-independent mapping is the
*punchable* case, yet cellular→node still relayed ⇒ the block is on the carrier side and/or the router
dropping the punch. A `/56` of static IPv6 removes the punching problem instead of winning it.
**SETTLED by measurement 2026-09-22, and it went the other way.** A log-only discriminator (`log=yes` on the WAN
drops, no hole opened, instrument validated before its silence was trusted) showed **zero packets from the phone
arriving on either family** while v4 internet scans hit the WAN constantly — so the router was never the blocker,
and the `/56` did **not** remove the punching problem (still relayed both ways). Both inbound remedies this brief
carried are retired. Method, numbers and the RouterOS traps: [network-vpn.md](docs/network-vpn.md).

**The one thing that can wreck the design while doing this:** IPv4 NAT is currently doing *implicit* inbound
protection for every VLAN. The moment GUAs exist, inbound safety becomes **purely** the RouterOS v6 filter's
job — and VLAN-20 (Shelly / Homematic / KNX) has unauthenticated HTTP APIs and the standing invariant that
IoT and guest are **never** inbound-reachable. So IPv6 is scoped to the Home VLAN and proven from outside,
not enabled fleet-wide.

## Rows (do them in this order)

| # | HD | Action | Gate / why here |
|---|----|--------|-----------------|
| 1 | **HD-414** | **Scoped IPv6 (dual-stack) on the RB4011** — spec below. Home VLAN 10 gets a GUA path; VLAN 20/30/40 get **no IPv6 at all** | gate: external probe from the VPS proves inbound v6 answers **nothing** except UDP 41641 → oldsrv. Nothing else may be enabled first — 410/406 are measured *after* it |
| 2 | ~~HD-405 tail~~ | ✅ **DONE 2026-09-21 — the phone-on-cellular matrix ran and passed.** T1 reachable on mobile data; **T2 headscale stopped for 162 s and the node path served a *new* session with the control plane provably dead** (`vpn.kogler.si` → 404; restored at `restarts=0`, no delta left); T3 HA Companion works on `ha.ts.kogler.si`; T4 `PrimaryRoutes` empty on every peer + `10.10.20.10` unreachable. Record: [network-vpn.md](docs/network-vpn.md) §Tailnet boundary | **Nothing owed.** Two measurement traps for anyone re-running this: `headscale routes list` **does not exist** in this build (use `tailscale status --json` → `PrimaryRoutes`), and a loopback `curl` to `ha.ts.kogler.si` returns **000** because the edge binds the node IP only |
| 3 | **HD-415** | **Tailnet resolver chain — ✅ closed 2026-09-22** | **Decided 2026-09-21** (owner): neither "leave it" nor "trim it" — make the chain survivable. **Shipped and proved live 2026-09-22** (`100.100.100.100 → oldsrv node → VPS public`, `udp 53` on the node address, one restart under `scripts/guarded-converge.sh`). **Closed on the owner-present drill:** (a) home ✅, (c) WAN pulled ✅, (b) re-scoped — the cause is `override_local_dns: false` making the delivered chain advisory, answered by per-name reachable records (HD-436) rather than resolver ordering; (d) refused | ✅ closed 2026-09-22 (drill run; (b) re-scoped, (d) refused) |
| 4 | **HD-406** | Router WG road-warrior peer — **re-evaluate after HD-414**, do not build it before. With v6 direct the case weakens; if v6 fails the case strengthens | it opens a second public listener, and that decision must be made against a measurement |
| 5 | **HD-410** | DERP posture — **decide after HD-414.** Recommendation on the table today: **do not** self-host DERP on the VPS | a VPS-hosted DERP re-inserts the VPS into the data path, which is the thing HD-405 exists to remove, and fra is already 18 ms from home |
| 6 | ~~HD-408~~ | ✅ **Deleted row — decided 2026-09-21: the exit node stays on the Pi.** Nothing to do | [network-rejected.md](docs/network-rejected.md) 2026-09-21; the re-open trigger is row 4's full-tunnel profile proving geo-egress with no exit node at all. Do not re-open |
| 6b | **HD-419** *(merged 2026-09-21)* | `media.kogler.si` stops answering 502: publish a jellyfin host port on the **Home leg** (the `actual-budget:5006` / `immich-ml:3003` precedent) as a `*_port` var + the compose publish | Registered as its own row and **decided**. It is edge work in files this lane owns (`traefik-internal` routes + the port var), and it feeds HD-357's tile in [`prompt-357.md`](prompt-357.md) |
| 6c | **HD-09** *(merged)* | the UPS web-UI firewall rule lands — its ⏳ literally says *"ride the next router converge import"*, and **this lane is that converge** | IaC-only and tiny; doing it here avoids a second `/import` of the device, which is this brief's expensive and risky artifact |
| 6d | **HD-301 tail** *(merged)* | the Phase-1.5 bootstrap-hardening tail rides the same converge | Same reason as 6c: one router session, one import, one verification |
| 6e | **HD-159** *(optional — window-gated)* | prove `wg-s2s-down` fires by taking the tunnel down deliberately, once | ⛔ **Owner's window first** (O4): it drops the S2S tunnel and fires a CRIT alert. Take it only with the window stated in the row, otherwise park it with the exact command |
| 7 | hygiene | Retired **preauth keys 4 (`tag:pi-dev`) + 5 (`tag:dsh`)** are live, reusable and non-expiring on headscale for services that no longer exist. The tombstones in [deployment-secrets.md](docs/deployment-secrets.md) do not revoke them — headscale does | one `headscale preauthkeys expire` each; report ids only, never values |
| 8 | hygiene | **The orchestrator — not this lane — deletes a brief.** It did so for `prompt-405.md` on 2026-09-22 (a closed banner: its facts live in this brief + the SSOT docs, audit trail `git log --follow prompt-405.md`; the path no longer resolves on disk) | Rewritten 2026-09-21: under [prompt.md](prompt.md) §4 O7 the deletion belongs to the parent's cleanup commit, made **together with** the link fixes in `prompt.md`, `todo.md` and `todo-table.md`. Those three are what `check_doc_map.py` actually scans — it **excludes `prompt-*` files**, so links *between* briefs are not checked at all (what this row previously asserted overstated the gate). **Do not hand-edit another live lane's brief and do not delete a brief yourself** |

## HD-414 spec

1. **WAN:** DHCPv6 client with **prefix delegation** (request the /56). Verify the ISP actually delegates on
   the existing WAN leg before writing anything downstream.
2. **Allocation:** carve /64s from the pool in `roles/router` vars → the generated addresses doc follows.
   **Assign them only to the VLANs you intend to be on v6** (Home VLAN 10 first — that is where oldsrv
   lives). Nothing on 20/30/40.
3. **RA:** enable `/ipv6 nd` **on VLAN 10 only**. Keeping v6 off IoT/guest/kids preserves the invariant *by
   construction* rather than by firewall correctness, and avoids RA on firmware that mishandles SLAAC.
4. **Filter, in this order:** accept `established,related`; accept the ICMPv6 that ND and PMTUD need
   (dropping ICMPv6 is the classic silent-v6-breakage); then **`drop` all from WAN**; then exactly one
   exception — **UDP 41641 → oldsrv's GUA**, with tailscaled pinned (`tailscale up --port=41641`, and the
   flag goes into `roles/tailscale-node` so it is IaC, not a habit).
5. **Verify from OUTSIDE.** The VPS already has a GUA — use it as the prober: scan inbound v6 into the home
   prefix and require **nothing answers except UDP 41641 at oldsrv**. Record the probe in
   [network-ops.md](docs/network-ops.md) as a repeatable runbook, not a one-off.
6. **Re-measure:** `tailscale netcheck` on oldsrv flips `IPv6: yes`; the phone's node page flips from
   `Relayed (FRA)` to **Direct**; record RTT before/after (before = 60–90 ms).
7. **Rollback is two switches:** remove the one accept, disable RA on VLAN 10. Write both into the row before
   you converge.

⚠ Two honest caveats to keep in the row: carriers often firewall **inbound** v6 to phones (fine — the phone
initiates — but if the SIM's v6 is broken, v6 alone will not produce Direct, which is why step 6 is a
measurement) — **that is precisely what happened**, and the mirror half turned out to be bigger: no unsolicited
inbound v6 reached the delegated prefix at all, so inbound-over-v6 from home is unavailable regardless of SIM;
and **no AAAA records for home hosts in the public zone** while this lands, so nothing new
becomes an inbound target by DNS accident (which is now moot in the good direction — such a record would be
unreachable anyway).

## HD-415 detail — decided 2026-09-21 · ✅ implemented 2026-09-22 · drill pending

> **Status of this section:** everything below is implemented and live. Three things it prescribed that the
> measurements changed: (1) **no Technitium bind was needed** — it already listens on `0.0.0.0:53` + `[::]:53`,
> which covers the node address; (2) the blocker was the **headscale ACL** (`tag:dev` was `tcp 443` only), now
> widened by one `udp 53` rule scoped to the node **address** rather than the tag; (3) the answer from the node
> is the **home LAN address**, and the VPS fallback's away-side view does **not** carry the media family — so
> the node entry is the only resolver that has ever answered those names away from home. What shipped, the four
> measurements and the procedure (including the guarded restart) are in
> [network-dns.md](docs/network-dns.md) §The resolution requirement and
> [deployment-manual.md](deployment-manual.md) §1.4e; the design rationale below stays as written so the
> reasoning that produced it is not lost.

headscale's tailnet `nameservers` chain is MagicDNS loop → VPS public → **oldsrv LAN IP → Pi LAN IP**. The
last two are unreachable from a phone on cellular → the Tailscale app shows `DNS unavailable` and resolution
burns timeouts. That was **not** a defect: those two are what keep `*.kogler.si` resolvable on a tailnet
device **at home with the WAN down**, because the alternative (VPS primary) is exactly the path a WAN outage
takes away — which is why the 2026-09-20 pass that called it a bug was wrong, and why the answer is
**reachability, not sort order**.

**The decided design:** bind Technitium to **oldsrv's tailnet node address** and make *that* the headscale
nameserver — direct-over-LAN at home with the WAN pulled, reachable away while the home link is up — keep the
**VPS public instance as the fallback**, and **remove the two LAN-address entries**. Case (d), *away while the
home WAN is down*, is accepted as unresolvable: no resolver behind a dead WAN is reachable from the internet.
Acceptance is therefore the **three-case drill** (LAN / cellular / home with the WAN pulled), and the third case
needs the owner present — **park** it with the exact steps rather than declaring the row done (O4).
⚠ The files are `templates/docker_services/technitium/**` + the headscale config — **not**
`roles/docker_services/tasks/technitium-seed.yml`, whose check-mode gate is HD-399 in `prompt-407.md` (**closed 2026-09-23, brief deleted**).

## Sequence + gates

1. Read [network-vlans.md](docs/network-vlans.md) + [network-dns.md](docs/network-dns.md) + §Tailnet boundary
   of [network-vpn.md](docs/network-vpn.md), then the 2026-09-20 findings rows.
2. IaC only: **`roles/router/` + `templates/router/rb4011_converge.rsc.j2`**.
   `IaC/router/rb4011-patched-r-7.21.3-converge.rsc` is **generated — never edit it by hand, never hand
   `/import` from `/flash`, and never `system reset`** (that is the 2026-08-28 outage). The apply of record is the
   documented 3-tier path: **edit the converge template → render → `/import`**
   ([network-ops.md](docs/network-ops.md) 3-tier rule; transient deltas only via `scripts/routeros-apply-delta.sh`,
   folded back and deleted, never left). ⚠ **The `/env/run scripts/rd-converge.sh` command this brief used to quote
   exists nowhere in the repo or the docs** — establish the real apply of record on the device before running
   anything, and if it is not written down, write it into `network-ops.md` / `deployment-manual.md` (O6). Verify
   every `/ipv6` submenu name and
   argument against RouterOS **7.21** before converging — this repo has been bitten by guessed RouterOS
   syntax more than once.
3. Converge the tailscale port pin with the normal scoped ritual (detached, `--tags` + scope, **no `--diff`**
   on docker_services) — [scripts/README.md](scripts/README.md) says why.
4. Prove step 5 above **before** telling the owner the edge is safe.
5. Only then re-measure the phone, then make the HD-406 / HD-410 calls.
6. Close-out: code + docs in ONE signed commit, `bash scripts/validate-all.sh` green **in this worktree** —
   then **stop**. The parent owns the merge ([prompt.md](prompt.md) §4: the first lane fast-forwards, the second
   rebases and re-validates, and `main` never gets a merge commit). Permanent knowledge goes to the SSOT docs;
   **there is no changelog** — the frozen archives stay frozen.

## ⛔ No-re-decide list

- **The tailnet is not a LAN bridge — and that includes IPv6.** v6 makes the *transport* better; it must not
  make the tailnet a route into VLAN 20/30/40. **No advertised routes**, no exit node on the home node.
- **VLAN-99 seal (HD-398 = A) untouched.**
- **IoT and guest are never inbound-reachable**, and after HD-414 that is enforced by an explicit v6 drop
  rather than by NAT. Prove it.
- Do **not** widen `wg_s2s_vps.allowed_ips` or the router `available-from` set for any of this.
- **Do not re-decide** what is recorded in [network-rejected.md](docs/network-rejected.md) — including the
  two 2026-09-20 rows this thread added: *tailnet ≠ LAN bridge*, and *HA over the tailnet reuses `.ts` rather
  than being publicized*.
- **No AAAA records** pointing at home hosts while the v6 filter is unproven.
- If an owner-gated item appears (preauth key, WG peer, exit node, HA `trusted_proxies`, the phone on cellular,
  the headscale stop/start, a `wg down` window): **park and continue** — [prompt.md](prompt.md) §4 O4 replaces
  "stop and ask" for lane sessions. Write the exact blocked action into the row's ⏳ tail, do everything that is
  not blocked, report the park. **Never stop and wait unattended.**

## Two live faults HD-405 found — now registered rows, both decided 2026-09-21

1. **HD-418 — HA rejects anything oldsrv proxies.** HA answers `400 Bad Request` to any request carrying
   `X-Forwarded-For` from a peer outside `ha_trusted_proxies` — which means oldsrv's *standby* `ha` router has
   **never worked** and would fail the same way in a takeover. The tailnet router sidesteps it by stripping the
   forwarding headers. **Decided:** `ha_trusted_proxies` += `oldsrv_home_ip`, **in a planned window**, because the
   fix **restarts the smart-home controller** → the owner's word, so it is a *park*, not a lane task (O4). It
   belongs to [`prompt-357.md`](prompt-357.md) with the window stated; the files are
   `roles/home_assistant/templates/configuration.yaml.j2` + the `ha_trusted_proxies` key in `group_vars/all/main.yml`.
2. **HD-419 — `media.kogler.si` → 502**, even locally on oldsrv: jellyfin publishes no host port, unlike the
   `actual-budget:5006` / `immich-ml:3003` precedent. **This one IS this lane's** — row 6b above: one `*_port` var
   + the compose publish + the `traefik-internal` route, and it feeds HD-357's tile.

## Lane rules (this runs concurrently — one writer per file)

**Owns:** `IaC/ansible/roles/router/**`, `IaC/ansible/templates/router/rb4011_converge.rsc.j2`,
`IaC/ansible/roles/tailscale-node/**`, `IaC/ansible/templates/docker_services/{headscale,traefik-internal,traefik-tailnet}/**`,
`IaC/ansible/templates/docker_services/technitium/**` (added 2026-09-21: the decided HD-415 bind edits it, and the
old Owns list did not cover a file its own row must touch), `IaC/ansible/templates/docker_services/jellyfin/**`
(row 6b),
`IaC/ansible/group_vars/{all,vps}.yml` + `host_vars/oldsrv.kogler.si.yml` **for tailnet/v6/jellyfin-port keys only**,
`docs/network.md` (interfaces) · `docs/network-{vlans,dns,vpn,ops,review,rejected}.md` — and
**`docs/network-addresses-generated.md` is generated**: v6 allocations belong in the vars/purpose strings that
feed it, never in the rendered file (the HD-404 rule).
`docs/deployment-secrets.md` and **your own `todo.md` rows**.

**Never touches (orchestrator mode):** **`prompt.md` and `todo-table.md`** (O2 — the old list claimed both),
`roles/docker_services/tasks/technitium-seed.yml` and `…/dns-seed.yml` — the **check-mode** gate there is HD-399,
which belongs to `prompt-407.md` (**closed 2026-09-23, brief deleted**); edit them only after 407 has merged, and say so in the commit,
`scripts/**` (HD-407's lane — and it does not need a script edit),
`docs/{services-ai,pi-harness,security,1password,deployment-ansible}.md` (407's), `docs/services-admin.md` (412's
owning doc — the `docs/services-rustdesk.md` named in this list until now **does not exist**),
`rustdesk-server` IaC (412's), `.secrets/.claude/.codex/.vscode/.clinerules`, the frozen archives
(`reports/changelog.md`, `reports/deployment-journal.md`, `docs/archived/`).

**Collides with:** **HD-406 wants `roles/router` too** — it is row 4 *in this lane*, on purpose; keep one
writer there. If another session must touch the router render, this lane yields and says so out loud — the router
slot is global (O3). ⛔ **Never the same wave as `prompt-407` / `prompt-357` / `prompt-384`**: all four converge
oldsrv.

## First action

Read the v6 surface before changing it: `ipv6 nd`, `ipv6 dhcp-client` (does the ISP delegate the /56 today?)
and the existing v6 filter chains on the RB4011, then confirm **which VLANs must never get a GUA** against the
VLAN inventory in [network-vlans.md](docs/network-vlans.md) and the interface map in
[network.md](docs/network.md). Then write the allocation into `roles/router` vars.
