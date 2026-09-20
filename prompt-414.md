# `prompt-414.md` — Lane brief · dual-stack the home edge, then close the remote-dev transport (HD-414 · HD-415 · HD-405 tail · HD-410 · HD-406 · HD-408)

> **Role:** successor to [prompt-405.md](prompt-405.md). That lane shipped the transport (HD-405 LIVE: `oldsrv`
> is a headscale node on `tag:dev:443`, `ha.ts.kogler.si` served from oldsrv's own edge) and **measured the
> assumption the thread was built on — and it did not survive.** First away session ever run to the node
> (owner's phone, cellular): **`Relayed connection (FRA)`, 60–90 ms**, i.e. the data path left the VPS and
> landed on someone else's relay in Frankfurt instead. Owner holds a **static IPv6 /56 from the ISP, not yet
> configured on the RB4011**. This lane makes that path direct, then finishes what 405 left open.
> Start with [README.md](README.md) §0 → §1 mandatory context → this file → the HD rows in [todo.md](todo.md).
> **Linked from:** [prompt.md](prompt.md) §2 · [todo.md](todo.md) · [todo-table.md](todo-table.md)
> **Sibling lanes:** runner/cockpit = [prompt-407.md](prompt-407.md) · remote desktop =
> [prompt-412.md](prompt-412.md) — this lane runs alongside them; one writer per file.

## Goal

Home is IPv4-only behind RB4011 NAT: `tailscale netcheck` on oldsrv reports `UDP: true`, external
`<home WAN>:49343` (the router rewrites tailscaled's port), `MappingVariesByDestIP: false`, **no port
mapping**, **no IPv6 anywhere**, nearest DERP fra 18 ms. Single NAT with endpoint-independent mapping is the
*punchable* case, yet cellular→node still relayed ⇒ the block is on the carrier side and/or the router
dropping the punch. A `/56` of static IPv6 removes the punching problem instead of winning it.

**The one thing that can wreck the design while doing this:** IPv4 NAT is currently doing *implicit* inbound
protection for every VLAN. The moment GUAs exist, inbound safety becomes **purely** the RouterOS v6 filter's
job — and VLAN-20 (Shelly / Homematic / KNX) has unauthenticated HTTP APIs and the standing invariant that
IoT and guest are **never** inbound-reachable. So IPv6 is scoped to the Home VLAN and proven from outside,
not enabled fleet-wide.

## Rows (do them in this order)

| # | HD | Action | Gate / why here |
|---|----|--------|-----------------|
| 1 | **HD-414** | **Scoped IPv6 (dual-stack) on the RB4011** — spec below. Home VLAN 10 gets a GUA path; VLAN 20/30/40 get **no IPv6 at all** | gate: external probe from the VPS proves inbound v6 answers **nothing** except UDP 41641 → oldsrv. Nothing else may be enabled first — 410/406 are measured *after* it |
| 2 | **HD-405 tail** | The acceptance matrix still owed by the owner on cellular: **node path with headscale STOPPED** (T2), IoT/guest unreachable (T4 strong form = `headscale routes list` empty — captured 2026-09-20 ✅), HA Companion arbitration between the LAN URL and `ha.ts.…`, plain `ha.kogler.si` still dead on cellular (✅) | stop/start headscale on the VPS is a **shared control plane** action → owner's word, and restore it in the same breath. See [network-vpn.md](docs/network-vpn.md) §Tailnet boundary |
| 3 | **HD-415** | **Tailnet resolver chain — a tradeoff, not a defect** (details below). Decide, don't "fix" | the previous pass called this a bug and was wrong; the row exists so the next agent doesn't repeat that mistake |
| 4 | **HD-406** | Router WG road-warrior peer — **re-evaluate after HD-414**, do not build it before. With v6 direct the case weakens; if v6 fails the case strengthens | it opens a second public listener, and that decision must be made against a measurement |
| 5 | **HD-410** | DERP posture — **decide after HD-414.** Recommendation on the table today: **do not** self-host DERP on the VPS | a VPS-hosted DERP re-inserts the VPS into the data path, which is the thing HD-405 exists to remove, and fra is already 18 ms from home |
| 6 | **HD-408** | Exit-node host (Pi vs oldsrv) — pure owner call, independent of all of the above | recommendation on record: keep it on the Pi |
| 7 | hygiene | Retired **preauth keys 4 (`tag:pi-dev`) + 5 (`tag:dsh`)** are live, reusable and non-expiring on headscale for services that no longer exist. The tombstones in [deployment-secrets.md](docs/deployment-secrets.md) do not revoke them — headscale does | one `headscale preauthkeys expire` each; report ids only, never values |
| 8 | hygiene | **Delete [prompt-405.md](prompt-405.md)** — it is a CLOSED banner, its facts live in this brief + the SSOT docs, and its audit trail is `git log --follow prompt-405.md`. Held back on 2026-09-20 only because **five files still link it, two of them other lanes' briefs** ([prompt-407.md](prompt-407.md), [prompt-412.md](prompt-412.md)) and `check_doc_map.py` hard-fails on dangling links | delete it in ONE commit that also fixes those two links — i.e. the first time this lane legitimately edits those briefs, or on the owner's explicit "edit their briefs". Do not hand-edit another live lane's brief for tidiness alone |

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
measurement); and **no AAAA records for home hosts in the public zone** while this lands, so nothing new
becomes an inbound target by DNS accident.

## HD-415 detail

headscale's tailnet `nameservers` chain is MagicDNS loop → VPS public → **oldsrv LAN IP → Pi LAN IP**. The
last two are unreachable from a phone on cellular → the Tailscale app shows `DNS unavailable` and resolution
burns timeouts. That is **not** a defect: those two are what keep `*.kogler.si` resolvable on a tailnet
device **at home with the WAN down**, because the alternative (VPS primary) is exactly the path a WAN outage
takes away. Options, with the tradeoff written down: leave it; reorder/trim so the away case is cheap and
the WAN-out case survives; or per-source split DNS. Do not just delete the home resolvers — the 2026-09-20
pass made that error out loud and it is on record.

## Sequence + gates

1. Read [network-vlans.md](docs/network-vlans.md) + [network-dns.md](docs/network-dns.md) + §Tailnet boundary
   of [network-vpn.md](docs/network-vpn.md), then the 2026-09-20 findings rows.
2. IaC only: **`roles/router/` + `templates/router/rb4011_converge.rsc.j2`**.
   `IaC/router/rb4011-patched-r-7.21.3-converge.rsc` is **generated — never edit it by hand, never hand
   `/import` from `/flash`, and never `system reset`** (that is the 2026-08-28 outage). Converge with
   `/env/run scripts/rd-converge.sh` from the router's own shell. Verify every `/ipv6` submenu name and
   argument against RouterOS **7.21** before converging — this repo has been bitten by guessed RouterOS
   syntax more than once.
3. Converge the tailscale port pin with the normal scoped ritual (detached, `--tags` + scope, **no `--diff`**
   on docker_services) — [scripts/README.md](scripts/README.md) says why.
4. Prove step 5 above **before** telling the owner the edge is safe.
5. Only then re-measure the phone, then make the HD-406 / HD-410 calls.
6. Close-out: code + docs in ONE commit, `scripts/validate-all.sh` green, then FF-merge into `main`.
   Permanent knowledge goes to the SSOT docs; **there is no changelog** — the frozen archives stay frozen.

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
- If an owner-gated item appears (preauth key, WG peer, exit node, HA `trusted_proxies`), **stop and ask**.

## Two live faults HD-405 found and did not fix (both owner calls, both pre-existing)

1. **HA rejects anything oldsrv proxies.** HA answers `400 Bad Request` to any request carrying
   `X-Forwarded-For` from a peer outside `ha_trusted_proxies` — which means oldsrv's *standby* `ha` router has
   **never worked** and would fail the same way in a takeover. The tailnet router sidesteps it by stripping the
   forwarding headers. The honest fix is adding `oldsrv_home_ip` to `ha_trusted_proxies` = **restarts the
   smart-home controller** → owner's call.
2. **`media.kogler.si` → 502**, even locally on oldsrv: jellyfin publishes no host port, unlike the
   `actual-budget:5006` / `immich-ml:3003` precedent. One line in `group_vars/all/main.yml`.

## Lane rules (this runs concurrently — one writer per file)

**Owns:** `IaC/ansible/roles/router/**`, `IaC/ansible/templates/router/rb4011_converge.rsc.j2`,
`IaC/ansible/roles/tailscale-node/**`, `IaC/ansible/templates/docker_services/{headscale,traefik-internal,traefik-tailnet}/**`,
`IaC/ansible/group_vars/{all,vps}.yml` + `host_vars/oldsrv.kogler.si.yml` **for tailnet/v6 keys only**,
`docs/network.md` (interfaces) · `docs/network-{vlans,dns,vpn,ops,review,rejected}.md` — and
**`docs/network-addresses-generated.md` is generated**: v6 allocations belong in the vars/purpose strings that
feed it, never in the rendered file (the HD-404 rule).
`docs/deployment-secrets.md`, `todo.md`, `todo-table.md`.

**Doesn't touch:** `scripts/**` (HD-407's lane — and it does not need a script edit),
`docs/{services-ai,pi-harness,security,1password,deployment-ansible}.md` (407's), `docs/services-rustdesk.md` +
`rustdesk-server` IaC (412's), `.secrets/.claude/.codex/.vscode/.clinerules`, the frozen archives
(`reports/changelog.md`, `reports/deployment-journal.md`, `docs/archived/`).

**Collides with:** **HD-406 wants `roles/router` too** — it is row 4 *in this lane*, on purpose; keep one
writer there. If another session must touch the router render, this lane yields and says so out loud.

## First action

Read the v6 surface before changing it: `ipv6 nd`, `ipv6 dhcp-client` (does the ISP delegate the /56 today?)
and the existing v6 filter chains on the RB4011, then confirm **which VLANs must never get a GUA** against the
VLAN inventory in [network-vlans.md](docs/network-vlans.md) and the interface map in
[network.md](docs/network.md). Then write the allocation into `roles/router` vars.
