# `prompt-smart-home.md` — Lane brief · HA primary/standby, KNX, failover, the Pi's box hygiene

> **Role:** dispatch note for **one** lane session on the smart-home domain. **The rows are the authority** for what is
> missing and how to do it — this file carries the contract, the order of work and the traps, nothing else:
> [todo.md](todo.md) **HD-04 · HD-418 · HD-434 · HD-438 · HD-439 · HD-319 · HD-1109 · HD-1103 · HD-1101 · HD-17 · HD-217**
> (row ids as of `9e661845` — re-derive with `grep -c "^| HD-<id> " todo.md` before quoting one).
> **Linked from:** [todo-table.md](todo-table.md) §B0 · [todo.md](todo.md)

**Lane contract:** [docs/orchestration.md](docs/orchestration.md) §4 (O1–O9) — read it once; it overrides README §4 and
CONVENTIONS §6 at the items it numbers and this brief deliberately restates none of them.

**Converge hosts + slots (O3):** the **Pi** (the only HA that exists today, plus its box hygiene) and **oldsrv** (the standby
+ the edges) — one converge in flight per host, detached, **never `--diff`**. HD-438's firewall delta needs the **router**
slot, which is **global**: holding it blocks every other router change, so sequence it rather than bundling it.
⛔ **Do not share a wave with another oldsrv lane** (same containers, same `home_assistant` converge). **HD-418 pairs with
HD-1103 in the same Pi window** — the reboot is owed once, not twice — and its converge host is the **Pi**, not oldsrv.

**Read first:** [docs/smart-home.md](docs/smart-home.md) → [docs/smart-home-failover.md](docs/smart-home-failover.md)
(gaps + the drill record) → [docs/smart-home-rejected.md](docs/smart-home-rejected.md) before re-proposing anything →
[docs/home-assistant-current.md](docs/home-assistant-current.md) → [docs/hardware.md](docs/hardware.md) for the Pi's SD budget.

## Order of work

| # | Row | Do | Gate / trap |
|---|-----|----|-------------|
| 1 | **HD-1109** | Read what `roles/home_assistant` **intends** vs what `docker ps -a` + the `ha_standby_*` vars actually render on oldsrv, then either converge the standby **cold** (`enabled: false` until takeover) or write the downgrade into the failover doc and this row | This row decides whether HD-418 and HD-434 have a subject: an edge that proxies to a standby container that does not exist proves nothing. ⛔ Never describe HA failover as live from the 2026-09-09 drill while the fleet-wide container count reads 0 |
| 2 | **HD-418** | **Measure before you edit:** read the Pi's rendered `configuration.yaml` `http.trusted_proxies`. In this repo the entry is **already there** — `group_vars/all/main.yml:455` lists `10.10.1.30/32`, which is `oldsrv_home_ip` (`group_vars/all/main.yml:574`), in tree since `c9c36f23` (2026-09-11). So the open half is the **HA reload** + proving the standby edge with XFF present → 200, and the sentence in `templates/docker_services/traefik-internal/dynamic/routes.yml.j2` that says the opposite must be corrected with your measurement | ⛔ It restarts the smart-home controller (voice outage): authorised **unattended in the overnight window**, with one read of HA's active conversations first. **PARKED from this worktree** — the Pi is not reachable from here, so the blocked action is: read the rendered list on the Pi, then schedule the restart beside HD-1103 (O4) |
| 3 | **HD-1103** | Give `/var/log`'s mode an owner in IaC (the Pi ships `1777 root:root`, which trips logrotate's insecure-parent check for **every** stanza; Debian's form is `root:syslog` + sticky), then prove rotation and a clean `systemctl --failed`. Note the cosmetic `smartmontools` exit 17 separately | Nothing in `roles/*/tasks` touches `/var/log` today, so no converge will ever fix it; `journalctl` silence is not proof — logrotate fails while exiting invisibly to `systemd-analyze`. The Pi runs the fleet's only HA off an **SD card**, so unrotated logs are a slow rootfs-full |
| 4 | **HD-1101** | Replace the oldsrv-shaped resolver guard with a shape check keyed on the var **each host** applies, per leg | Acceptance is two-sided: `--tags nm-resolver` on both pi and oldsrv asserts with a real interface, **and** a deliberately-broken `dns_tertiary_ip` fails the play on the Pi too. ⚠ Do not re-converge the Pi expecting the oldsrv resolver guard to cover it before this lands |
| 5 | **HD-438** | Settle KNX end-to-end with a **positive instrument** — an entity that changes in the HA UI or the HA API — and account for the 2026-09-20 10:16 boundary (gate entered the template 2026-09-10, live rows dated later) | The `trusted-ha` widening is already folded into `IaC/router/templates/rb4011_converge.rsc.j2`; reachability was proven and is **not** the service. Never conclude from the absence of xknx timeouts, and never from raw UDP probes: the tunnel authenticates with a `user_id`, so unauthenticated `SEARCH`/`CONNECT` returns nothing from the healthy primary too |
| 6 | **HD-439** | Keep the leftover check that makes the KNX render claim checkable: the generated `state_address` set compared against the ETS project (`docs/assets/references/knx/StanovanjeKogler_v1_0.knxproj`), committed artifact == fresh render == what the Pi holds | The earlier "~36 invented addresses" figure described neither the file nor the generator; a count quoted without the comparison that produces it is not a finding |
| 7 | **HD-434** | Owner-present takeover-drill retest of KNX on the standby, once HD-1109 says a standby exists: bring it up, confirm a live tunnel via an entity that moves with the bus, and on failure read `xknx` for authorization vs no-channel vs no-route | The GIRA-router explanation was withdrawn — oldsrv has always been in `trusted-ha`. Do not re-run the probe class that produced it |
| 8 | **HD-04** | The standing tails: restore oldsrv's standby keepalived priority to **BACKUP 100** (the drill left the 120 variant) **before** the next standby cold boot; then the two owner legs — the GIRA-side KNX allowlist check and the `ha.kogler.si` HTTPS-with-Pi-down gap | A priority left at 120 makes the standby preempt the primary for no reason; that is a self-inflicted takeover, not a drill |
| 9 | **HD-319** | Owner/verify: confirm the three rekuperator group addresses (12/1/*) answer on the bus (the `GroupValueRead` warnings are the only signal so far) | One positive read closes it; a warning count going down is not a read |
| 10 | **HD-17** | Render the Homepage failover button in its **IP-only** form behind the `homepage_failover_button` gate, on the template, not the live file | ⛔ The RFUSB path is obsolete — the stick was rejected; the live path is VIP move + standby start. The visual pass is the owner's eye: land the wiring, hand over the eyeball, keep the ⏳ tail |
| 11 | **HD-217** | The next green `vps.yml` run renders the homepage with the gate off — verify the render, do not re-author the gate | Deploy-gated: if no VPS window is open, park with the exact command and continue |

## ⛔ Traps that cost a round (re-grounded at this `HEAD`)

* **HA's header trust is exact-match, and it fails loud-but-confusing:** any request carrying `X-Forwarded-For` from a peer
  outside `ha_trusted_proxies` gets a `400` from aiohttp, while the same request without the header gets `200`. The tailnet
  router only works because it **strips** the forwarding headers — so a green tailnet path proves nothing about the home edge.
* **Do not "add `oldsrv_home_ip`" from the row's wording.** The list already carries `10.10.1.30/32` in this repo
  (`group_vars/all/main.yml:455`, and `oldsrv_home_ip` resolves to `10.10.1.30` via the `network_static_hosts` vlan-10 row at
  `group_vars/all/main.yml:574`). Either the Pi's rendered file predates it, or HA never reloaded, or the standby has no HA at
  all (HD-1109). Whichever it is, **say which premise is wrong in the row**, and keep the overlay-wide list in sync with the
  edge IP pin it mirrors.
* **KNX is authenticated.** Never infer reachability from unauthenticated `SEARCH`/`CONNECT` or from raw UDP; settle it with
  an entity that moves. Home→IoT (VLAN 20) is gated on the `trusted-ha` address list — HA tunnels from its own address
  (`local_ip: null`), so the HA host itself must be in it.
* **Positive instruments only** across this whole lane: a container being `Up`, a timer being enabled, a counter advancing, or
  log silence are all states that coexist with a broken service.
* A **router** delta goes alone (global slot) and arrives widening-only; the RB4011 import is device-wide, so never bundle it
  with an oldsrv or Pi converge.
* Converge the `home_assistant` role on the **active** HA host, detached, guarded, never with `--diff`; the standby stays cold
  until a takeover is the point of the run.

## Owns / never touches

**Owns:** `IaC/ansible/roles/home_assistant/**` (incl. `files/knx-entities.yaml` + `scripts/knx-hass-gen.py`), the `ha_*`
regions of `group_vars/all/main.yml` (`ha_trusted_proxies`, `ha_vip`) and of `host_vars/pi.kogler.si.yml` /
`host_vars/oldsrv.kogler.si.yml`, the keepalived + resolver legs on the Pi, the `trusted-ha` line in
`IaC/router/templates/rb4011_converge.rsc.j2` (router slot global), `docs/smart-home*.md`, `docs/home-assistant-current.md`,
and your own `todo.md` rows.
**Never:** `prompt.md` / `todo-table.md` (O2) or another brief's rows; the LiteLLM gateway, its keys and
`templates/docker_services/{lan-litellm,litellm}/**` (the litellm-consumers lane owns HA's LLM leg and the voice chain);
traefik edge/route work beyond the `ha` router your rows name (the transport lane); `roles/router/**` generally and the DNS
answer plane; `roles/monitoring/**`; the NAS/ZFS and backup rows; the frozen archives and generated `*-generated.md`.

## Acceptance

Every item returns `PASS` / `FAIL` / `BLOCKED` / `PARKED` + the number + the evidence path; a claim with no path counts as
not run. Concretely: the standby state decided — deployed cold, or downgraded in the doc with the container count quoted ·
HD-418's measurement of the Pi's rendered list with the wrong premise named, and the restart either executed in the paired Pi
window or parked with the exact blocked action · logrotate proven on the Pi with the mode owned in IaC and `systemctl
--failed` clean · the resolver shape guard breeding a red on the Pi in its self-test · KNX proven by an entity that moves,
with the 09-20 boundary explained or explicitly left unexplained · the render-vs-`.knxproj` comparison in tree · the drill
legs either run and recorded or parked as owner-present · the standby keepalived priority restored before any cold boot ·
rows deleted or trimmed to their tails, no history in the row · `bash scripts/validate-all.sh` green **in this worktree** → **stop**.
